-- Startwahl in der Open World (wie im Tycoon): GameConfig.Start, MetaRules (startPath), OWRules.GrantStart,
-- TutorialRules/TutorialService je Weg, StoryRules (erste Mission von Kapitel 1 je Weg), StartService im echten Server
-- (eigene Aktionen-Tabelle wie test_tutorial, unabhängig von der MiniService-Verkabelung) und StartUI im Mock-Client.
-- Geprüft: Wahl nur einmal, Veteranen bekommen werkstatt automatisch, Stufe 1 geschenkt (sofort fertig, kostenlos,
-- nie zweimal), Tutorial-Schritte je Weg, Kapitel-1-Mission je Weg, Speichern/Laden, ungültiger Weg abgelehnt.
local NOW = 1760000000
local PATHS = { "werkstatt", "autohaus", "produktion", "schrottplatz" }

---------------------------------------------------------------- Hilfen
local function mods(g)
	return {
		GC = g:MiniShared("GameConfig"),
		MR = g:MiniShared("MetaRules"),
		OWR = g:MiniShared("OWRules"),
		TR = g:MiniShared("TutorialRules"),
		SR = g:MiniShared("StoryRules"),
		MiniRules = g:MiniShared("MiniRules"),
	}
end

-- Frisches Profil mit allen Spieldaten (neues Profil: startPath = "")
local function profile(g, level)
	local M = mods(g)
	local d = g:Rules().NewData(NOW)
	d.level = level or 1
	d.completed = 0
	d.games = M.MiniRules.DefaultGames()
	return d
end

local function ids(list)
	local out = {}
	for _, s in ipairs(list) do
		table.insert(out, s.id)
	end
	return table.concat(out, ",")
end

local function indexOf(list, id)
	for i, s in ipairs(list) do
		if s.id == id then
			return i
		end
	end
	return nil
end

-- Server mit StartService über eine eigene Aktionen-Tabelle und protokollierender api
local function setup(H, opts)
	local g = H.Garage(opts)
	local SS = g:MiniServer("StartService")
	local log = { notices = {}, toasts = {} }
	local handlers = {}
	local fakeApi = {
		now = function()
			return g:Now()
		end,
		toast = function(ms, text)
			table.insert(log.toasts, { player = ms.player, text = text })
		end,
		notice = function(ms, kind, data)
			table.insert(log.notices, { player = ms.player, kind = kind, data = data })
		end,
		dirty = function(ms)
			ms.dirty = true
		end,
		changed = function(ms)
			ms.dirty = true
		end,
		worldChanged = function() end,
		writable = function()
			return true
		end,
		alive = function()
			return true
		end,
	}
	SS.Register({
		Register = function(name, fn)
			handlers[name] = fn
		end,
	}, fakeApi)
	local S = { g = g, SS = SS, log = log, handlers = handlers }
	function S.join(userId, name)
		local pl = g:Join(userId, { name = name })
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		SS.OnJoin(ms, d, g:Now())
		return pl, ms, d
	end
	function S.choose(pl, path)
		g:Activate()
		return handlers.start_choose(g:MiniState(pl), { path = path }, g:D(pl), g:Now())
	end
	function S.hasToast(pl, text)
		for _, t in ipairs(log.toasts) do
			if t.player == pl and string.find(t.text, text, 1, true) then
				return true
			end
		end
		return false
	end
	return S
end

return {
	{ "GameConfig.Start und Tutorial je Weg: vier Wege, gemeinsamer Anfang und Schluss, werkstatt unverändert", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local GC = M.GC
		T.eq(table.concat(GC.Start.Order, ","), table.concat(PATHS, ","), "vier Wege in fester Reihenfolge wie der Tycoon")
		for _, typ in ipairs(PATHS) do
			local p = GC.Start.Paths[typ]
			T.check(p ~= nil and p.id == typ, "Weg " .. typ)
			T.check(type(p.name) == "string" and #p.desc > 20 and #p.first > 10 and #p.bonus > 10 and #p.short > 5, "Kartentexte " .. typ)
			T.check(GC.Tycoon.TypeSet[typ] == true, "gleicher Typ wie im Tycoon: " .. typ)
			T.check(p.building == nil or GC.OW.TypeSet[p.building] == true, "Gebäude bekannt: " .. typ)
			T.check(type(p.yieldHours) == "number" and p.yieldHours >= 0 and p.yieldHours <= GC.OW.PassiveCapHours, "Startertrag im Deckel: " .. typ)
		end
		T.eq(GC.Start.Default, "werkstatt", "Veteranen: werkstatt")
		-- werkstatt = klassischer Weg, unverändert (11 Schritte)
		T.check(GC.Tutorial.ByPath.werkstatt == GC.Tutorial.Steps, "Steps = ByPath.werkstatt")
		T.eq(ids(GC.Tutorial.Steps), "move,menu,reception,accept,obd,repair,settle,map,dealer,goals,kiesplatz", "klassischer Weg unverändert")
		local kinds = {}
		for _, k in ipairs(GC.Tutorial.EventKinds) do
			kinds[k] = true
		end
		for _, typ in ipairs(PATHS) do
			local list = GC.Tutorial.ByPath[typ]
			T.check(type(list) == "table" and #list >= 6, "Schritte für " .. typ)
			T.eq(list[1].id, "move", typ .. ": Intro laufen")
			T.eq(list[2].id, "menu", typ .. ": Intro Menü")
			local map, kies = indexOf(list, "map"), indexOf(list, "kiesplatz")
			T.check(map ~= nil and kies ~= nil and map < kies, typ .. ": gemeinsamer Schluss Stadtplan -> Kiesplatz")
			local seen = {}
			for i, s in ipairs(list) do
				T.check(not seen[s.id], typ .. ": Schritt doppelt " .. s.id)
				seen[s.id] = true
				local kind = string.match(s.event, "^([%a_]+)")
				T.check(kinds[kind] == true, typ .. ": Ereignisart bekannt " .. s.event)
				T.check(type(s.text) == "string" and #s.text > 20, typ .. ": Text " .. s.id)
				T.check(GC.TutorialStepById[s.id] == s, "ById " .. s.id)
				T.eq(GC.TutorialStepIndexByPath[typ][s.id], i, "Index je Weg " .. s.id)
				if s.zone == "city" then
					T.check(i > map, typ .. ": Stadt-Schritt " .. s.id .. " erst nach dem Stadtplan")
				end
			end
		end
		T.eq(ids(GC.Tutorial.ByPath.autohaus), "move,menu,ah_buildings,ah_collect,map,ah_dealer,kiesplatz,ah_sell", "autohaus: Gebäude, Abholen, Händler, Verkauf")
		T.eq(ids(GC.Tutorial.ByPath.produktion), "move,menu,pr_buildings,pr_collect,map,pr_tuning,kiesplatz", "produktion: Gebäude, Pakete, Tuning-Zentrum")
		T.eq(ids(GC.Tutorial.ByPath.schrottplatz), "move,menu,sc_buildings,sc_collect,map,sc_press,kiesplatz", "schrottplatz: Gebäude, Schrott, Presse")
		T.eq(GC.TutorialStepById.ah_buildings.openTab, "buildings", "Gebäude-Tab öffnen erledigt den Lese-Schritt")
		T.eq(GC.TutorialStepById.ah_collect.event, "action:ow_collect", "Abholen über die echte Aktion")
		T.eq(GC.TutorialStepById.pr_tuning.event, "tab:tuning", "Tuning-Zentrum (City.Stations.tuning)")
		T.eq(GC.TutorialStepById.sc_press.event, "tab:press", "Schrottpresse (City.Stations.press)")
		T.eq(GC.TutorialStepById.ah_sell.passiveSkip, true, "Kiesplatz-Verkauf entfällt im Passiv-Modus")
		T.check(M.MiniRules.IsClean(GC.Start) and M.MiniRules.IsClean(GC.Tutorial.ByPath), "Konfiguration sauber")
	end },

	{ "MetaRules: startPath Default/Load (Whitelist, idempotent), Veteranen automatisch werkstatt, Wahl nur einmal", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local MR = M.MR
		local d = profile(g)
		T.eq(MR.Default().startPath, "", "neues Profil: Wahl offen")
		T.eq(MR.StartPath(d), "", "StartPath leer")
		T.eq(MR.EffectivePath(d), "werkstatt", "ohne Wahl: klassischer Weg")
		T.eq(MR.StartPending(d), true, "Wahl offen")
		T.eq(MR.ResolveStartPath(d), "", "neues Profil bleibt offen")
		-- ungültige Wege
		for _, bad in ipairs({ "", "lobby", "WERKSTATT", 5, true, "werkstatt " }) do
			local ok, why = MR.SetStartPath(d, bad)
			T.eq(ok, false, "ungültig abgelehnt: " .. tostring(bad))
			T.eq(why, "invalid", "Grund invalid")
		end
		T.eq(MR.StartPath(d), "", "nichts gesetzt")
		local ok = MR.SetStartPath(d, "produktion")
		T.eq(ok, true, "gültige Wahl")
		T.eq(MR.StartPath(d), "produktion", "gespeichert")
		local ok2, why2 = MR.SetStartPath(d, "autohaus")
		T.eq(ok2, false, "zweite Wahl abgelehnt")
		T.eq(why2, "already", "Grund already")
		T.eq(MR.StartPath(d), "produktion", "Wahl bleibt")
		T.eq(MR.StartPending(d), false, "nicht mehr offen")
		-- Laden: Whitelist und Idempotenz
		T.eq(MR.Load({ startPath = "schrottplatz" }, d, NOW).startPath, "schrottplatz", "gültiger Weg bleibt")
		T.eq(MR.Load({ startPath = "mars" }, profile(g), NOW).startPath, "", "unbekannter Weg -> offen")
		T.eq(MR.Load({ startPath = 7 }, profile(g), NOW).startPath, "", "Zahl -> offen")
		local once = MR.Load({ startPath = "autohaus", tutorialStep = 99 }, profile(g), NOW)
		T.eq(once.tutorialStep, #M.GC.Tutorial.ByPath.autohaus, "Schritt gedeckelt auf die Länge des Wegs")
		local twice = MR.Load(H.Copy(once), profile(g), NOW)
		local same, where = H.DeepEqual(once, twice)
		T.check(same, "idempotent: " .. tostring(where))
		T.check(M.MiniRules.IsClean(once), "sauber")
		-- Veteranen: abgerechnete Aufträge (mit und ohne meta), Tutorial beendet/übersprungen, schon im Tutorial, Gebäude
		local vet = profile(g)
		vet.completed = 12
		T.eq(MR.Load(nil, vet, NOW).startPath, "werkstatt", "2.4.0-Veteran ohne meta")
		T.eq(MR.Load({ tutorialDone = false }, vet, NOW).startPath, "werkstatt", "Veteran mit meta")
		T.eq(MR.Load({ tutorialDone = true }, profile(g), NOW).startPath, "werkstatt", "Tutorial beendet")
		T.eq(MR.Load({ tutorialSkipped = true }, profile(g), NOW).startPath, "werkstatt", "Tutorial übersprungen")
		T.eq(MR.Load({ tutorialStep = 5 }, profile(g), NOW).startPath, "werkstatt", "schon im klassischen Tutorial")
		local gv = {}
		MR.ApplyLoad(gv, { meta = { tutorialStep = 1 }, ow = { buildings = { autohaus = { stage = 1, built = 1 } } } }, profile(g), NOW)
		T.eq(gv.meta.startPath, "werkstatt", "Open-World-Gebäude im Datensatz")
		local gn = {}
		MR.ApplyLoad(gn, { meta = { tutorialStep = 1 } }, profile(g), NOW)
		T.eq(gn.meta.startPath, "", "neues 3.x-Profil bleibt offen")
		-- zur Laufzeit (Profil aus einer laufenden Sitzung)
		local live = profile(g)
		live.games.ow.buildings.schrottplatz.stage = 1
		T.eq(MR.StartPending(live), false, "Gebäude: keine Wahl")
		T.eq(MR.ResolveStartPath(live), "werkstatt", "Gebäude: werkstatt")
		local live2 = profile(g)
		live2.completed = 3
		T.eq(MR.ResolveStartPath(live2), "werkstatt", "Aufträge: werkstatt")
		T.eq(MR.ResolveStartPath(live2), "werkstatt", "idempotent")
		-- ohne meta: nie offen
		T.eq(MR.StartPending({ games = {} }), false, "ohne meta keine Wahl")
		-- Rundreise über MiniRules.LoadGames
		local saved = profile(g)
		MR.SetStartPath(saved, "autohaus")
		local loaded = M.MiniRules.LoadGames(H.Copy(saved.games), saved, NOW)
		T.eq(loaded.meta.startPath, "autohaus", "LoadGames hält den Weg")
	end },

	{ "OWRules.GrantStart: Stufe 1 je Weg geschenkt, sofort fertig, kostenlos, ohne Level-Sperre, nie zweimal", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local OWR, GC = M.OWR, M.GC
		-- werkstatt: nichts zu schenken
		local dw = profile(g)
		local okW, whyW = OWR.GrantStart(dw, "werkstatt", NOW)
		T.eq(okW, false, "werkstatt schenkt kein Gebäude")
		T.eq(whyW, "werkstatt", "Grund werkstatt")
		T.eq(OWR.StageOf(dw, "autohaus") + OWR.StageOf(dw, "produktion") + OWR.StageOf(dw, "schrottplatz"), 0, "werkstatt: kein Gebäude")
		for _, bad in ipairs({ "lobby", "", 3 }) do
			local ok, why = OWR.GrantStart(profile(g), bad, NOW)
			T.eq(ok, false, "unbekannter Weg " .. tostring(bad))
			T.eq(why, "unknown", "Grund unknown")
		end
		local expect = {
			autohaus = { credits = math.floor(1500 * GC.Start.Paths.autohaus.yieldHours) },
			produktion = { parts = 20, packs = 2 },
			schrottplatz = { scrap = 2000000000, parts = 2 },
		}
		for _, typ in ipairs({ "autohaus", "produktion", "schrottplatz" }) do
			local d = profile(g, 1)
			d.money = 800
			T.check(OWR.CanBuild(d, typ, NOW) == false, typ .. ": auf Level 1 normal nicht baubar")
			local ok, why = OWR.GrantStart(d, typ, NOW)
			T.eq(ok, true, typ .. ": geschenkt")
			T.eq(why, "ok", typ .. ": Grund ok")
			T.eq(d.money, 800, typ .. ": kostet nichts")
			local e = OWR.Entry(d, typ)
			T.eq(e.stage, 1, typ .. ": Stufe 1")
			T.eq(e.gift, true, typ .. ": als Geschenk markiert")
			T.eq(OWR.Ready(d, typ, NOW), true, typ .. ": sofort fertig (keine Bauzeit)")
			T.eq(OWR.Remaining(d, typ, NOW), 0, typ .. ": keine Restzeit")
			-- der nächste Tick (OWService: Settle) stellt das Modell auf
			local done = OWR.Settle(d, NOW)
			T.eq(done[1], typ, typ .. ": Settle meldet fertig")
			T.eq(OWR.Built(d, typ), 1, typ .. ": gebaut")
			T.eq(OWR.Perk(d, typ) > 1, true, typ .. ": Perk wirkt")
			-- nie zweimal (auch nicht nach Settle oder nach einem Abriss der Markierung)
			local ok2, why2 = OWR.GrantStart(d, typ, NOW + 10)
			T.eq(ok2, false, typ .. ": nicht zweimal")
			T.eq(why2, "already", typ .. ": Grund already")
			T.eq(OWR.StageOf(d, typ), 1, typ .. ": bleibt Stufe 1")
			-- Startertrag wartet schon
			local before = d.games.press.scrap
			local a = OWR.Collect(d, typ, NOW)
			T.check(a ~= nil, typ .. ": Startertrag abholbar")
			local x = expect[typ]
			if x.credits then
				T.check(a.credits >= x.credits and d.money >= 800 + x.credits, typ .. ": Credits " .. tostring(a.credits))
			end
			if x.parts then
				T.eq(a.parts, x.parts, typ .. ": Altteile")
				T.eq(e.partsTotal, x.parts, typ .. ": Lebenszeit-Altteile")
			end
			if x.packs then
				T.eq(e.packs, x.packs, typ .. ": Bauteil-Pakete gezählt")
			end
			if x.scrap then
				T.eq(a.scrap, x.scrap, typ .. ": Schrott")
				T.eq(d.games.press.scrap - before, x.scrap, typ .. ": Schrott in der Presse")
			end
			T.eq(e.collects, 1, typ .. ": eine Abholung gezählt")
			-- Speichern/Laden hält Geschenk und Zähler
			local loaded = OWR.Load(H.Copy(d.games.ow), d, NOW)
			T.eq(loaded.buildings[typ].gift, true, typ .. ": gift nach Laden")
			T.eq(loaded.buildings[typ].collects, 1, typ .. ": collects nach Laden")
			T.eq(loaded.buildings[typ].partsTotal, e.partsTotal, typ .. ": partsTotal nach Laden")
			local again = OWR.Load(H.Copy(loaded), d, NOW)
			local same, where = H.DeepEqual(loaded, again)
			T.check(same, typ .. ": Load idempotent: " .. tostring(where))
			T.check(M.MiniRules.IsClean(d.games.ow), typ .. ": ow sauber")
		end
		-- ein schon gebautes Gebäude wird nicht überschrieben
		local built = profile(g, 20)
		built.games.ow.buildings.autohaus.stage = 2
		built.games.ow.buildings.autohaus.built = 2
		local okB, whyB = OWR.GrantStart(built, "autohaus", NOW)
		T.eq(okB, false, "vorhandenes Gebäude bleibt")
		T.eq(whyB, "already", "Grund already")
		T.eq(OWR.StageOf(built, "autohaus"), 2, "Stufe 2 bleibt")
		-- Load(nil) = Default auch mit den neuen Feldern
		local same = H.DeepEqual(OWR.Load(nil, {}, NOW), OWR.Default())
		T.check(same, "Load(nil) = Default")
	end },

	{ "TutorialRules je Weg: wartet auf die Wahl, Schritte und Ereignisse des Wegs, Passiv-Modus, Belohnung einmal", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local TR, MR, GC = M.TR, M.MR, M.GC
		local d = profile(g)
		-- Wahl offen: in der Open World wartet das Tutorial, ohne Modus (reine Regeln) läuft der klassische Weg
		T.eq(TR.Waiting(d, "openworld"), true, "wartet in der Open World")
		T.eq(TR.Active(d, "openworld"), false, "nicht aktiv")
		T.eq(TR.ShouldStart(d, "openworld"), false, "kein Pflicht-Start vor der Wahl")
		local v = TR.View(d, "openworld")
		T.eq(v.active, false, "Karte verborgen")
		T.eq(v.waiting, true, "View.waiting")
		T.eq(v.text, "", "kein Text")
		T.eq(TR.Waiting(d, nil), false, "ohne Modus wartet nichts")
		T.eq(TR.Count(d), 11, "ohne Wahl: klassischer Weg")
		T.eq(TR.Count(), 11, "ohne Profil: klassischer Weg")
		local function walk(path, events)
			local dd = profile(g)
			MR.SetStartPath(dd, path)
			T.eq(TR.ShouldStart(dd, "openworld"), true, path .. ": startet nach der Wahl")
			T.eq(TR.Count(dd), #GC.Tutorial.ByPath[path], path .. ": Anzahl")
			T.eq(TR.View(dd, "openworld").path, path, path .. ": View.path")
			for i, ev in ipairs(events) do
				local step = TR.Current(dd, "openworld")
				T.check(step ~= nil, path .. ": Schritt " .. i .. " aktiv")
				if not step then
					return dd
				end
				T.eq(step.event, ev, path .. ": Ereignis Schritt " .. i)
				-- falsches Ereignis bewegt nichts
				T.eq(select(1, TR.Advance(dd, "tab:nichts")), false, path .. ": falsches Ereignis")
				if ev == "next" then
					local ok = TR.Next(dd, i)
					T.eq(ok, true, path .. ": Weiter " .. i)
				else
					local adv = TR.Advance(dd, ev)
					T.eq(adv, true, path .. ": Ereignis " .. ev)
				end
			end
			T.eq(TR.Done(dd), true, path .. ": fertig")
			T.eq(TR.Current(dd, "openworld"), nil, path .. ": kein Schritt mehr")
			return dd
		end
		walk("werkstatt", { "next", "next", "station:workshop", "job:accepted", "job:repair", "job:invoice", "settled", "action:mini_travel", "tab:dealer", "tab:goals", "tab:story" })
		walk("autohaus", { "next", "next", "next", "action:ow_collect", "action:mini_travel", "tab:dealer", "tab:story", "action:story_sell" })
		walk("produktion", { "next", "next", "next", "action:ow_collect", "action:mini_travel", "tab:tuning", "tab:story" })
		local ds = walk("schrottplatz", { "next", "next", "next", "action:ow_collect", "action:mini_travel", "tab:press", "tab:story" })
		-- Belohnung bleibt einmal (Neustart am Kiosk: gleicher Weg, keine zweite Belohnung)
		TR.MarkRewarded(ds)
		T.eq(TR.Restart(ds), true, "Neustart")
		T.eq(MR.StartPath(ds), "schrottplatz", "Weg bleibt nach Neustart")
		T.eq(TR.Rewarded(ds), true, "Belohnung bleibt verbucht")
		T.eq(TR.Current(ds, "openworld").id, "move", "wieder bei Schritt 1")
		-- Passiv-Modus: der Kiesplatz-Verkauf (passiveSkip) gilt als erledigt
		local dp = profile(g)
		MR.SetStartPath(dp, "autohaus")
		dp.games.meta.tutorialStep = TR.Count(dp)
		T.eq(TR.Current(dp, "openworld").id, "ah_sell", "letzter Schritt Verkauf")
		T.eq(TR.PendingPassiveEvent(dp), nil, "ohne Passiv-Modus nichts")
		dp.games.meta.passive = true
		T.eq(TR.PendingPassiveEvent(dp), "action:story_sell", "Passiv-Modus erledigt den Verkauf")
		-- Weg-Ansicht
		T.eq(TR.View(dp, "openworld").openTab, nil, "Verkauf ohne Tab")
		dp.games.meta.tutorialStep = 3
		T.eq(TR.View(dp, "openworld").openTab, "buildings", "Gebäude-Schritt nennt den Tab")
	end },

	{ "StoryRules: erste Mission von Kapitel 1 je Weg, übrige Kapitel unverändert, Veteranen behalten ihren Stand, Balance", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local SR, MR, OWR, GC = M.SR, M.MR, M.OWR, M.GC
		local expect = { werkstatt = "c1_m1", autohaus = "c1_m1", produktion = "c1_m1_produktion", schrottplatz = "c1_m1_schrottplatz" }
		T.eq(SR.Current(profile(g)).mission.id, "c1_m1", "ohne Wahl: Kiesplatz-Verkauf wie bisher")
		for _, typ in ipairs(PATHS) do
			local d = profile(g)
			MR.SetStartPath(d, typ)
			local cur = SR.Current(d)
			T.eq(cur.chapter, 1, typ .. ": Kapitel 1")
			T.eq(cur.mission.id, expect[typ], typ .. ": erste Mission")
			local list = SR.Missions(d, 1)
			T.eq(#list, 3, typ .. ": drei Missionen")
			T.eq(list[2].id, "c1_m2", typ .. ": Mission 2 gleich")
			T.eq(list[3].id, "c1_m3", typ .. ": Mission 3 gleich")
			T.eq(SR.RequiredLevel(cur.mission), 1, typ .. ": ab Level 1 machbar")
			local cfg = cur.mission.reward
			T.check(cfg and cfg.credits > 0 and cfg.credits / cur.mission.minutes <= GC.Story.Balance.Share * SR.WorkshopPerMinute(1) + 1e-9, typ .. ": 40-%-Regel")
			-- falsche Varianten lassen sich nicht starten
			for other, id in pairs(expect) do
				if other ~= typ and id ~= expect[typ] then
					T.eq(select(1, SR.Start(d, id, NOW)), false, typ .. ": " .. id .. " nicht startbar")
				end
			end
			T.eq(select(1, SR.Start(d, cur.mission.id, NOW)), true, typ .. ": eigene Mission startbar")
		end
		-- Fortschritt je Weg bis zur Abholung
		local dw = profile(g)
		MR.SetStartPath(dw, "werkstatt")
		-- werkstatt = klassischer Start: Kiesplatz-Verkäufe wie bisher (das Werkstatt-Tutorial endet am Kiesplatz)
		T.eq(select(1, SR.Start(dw, "c1_m1", NOW)), true, "werkstatt: c1_m1 startbar")
		SR.OnStat(dw, "jobsDone", 3, NOW)
		T.eq(select(1, SR.Claim(dw, "c1_m1", NOW)), false, "Aufträge zählen nicht für den Kiesplatz")
		for _ = 1, 3 do
			SR.OnSale(dw, 1, false, NOW)
		end
		local okW = SR.Claim(dw, "c1_m1", NOW)
		T.eq(okW, true, "werkstatt: drei Verkäufe abgeholt")
		T.eq(SR.Current(dw).mission.id, "c1_m2", "weiter mit Mission 2")
		local da = profile(g)
		MR.SetStartPath(da, "autohaus")
		SR.Start(da, "c1_m1", NOW)
		for _ = 1, 3 do
			SR.OnSale(da, 1, false, NOW)
		end
		T.eq(select(1, SR.Claim(da, "c1_m1", NOW)), true, "autohaus: drei Verkäufe")
		for _, typ in ipairs({ "produktion", "schrottplatz" }) do
			local d = profile(g)
			MR.SetStartPath(d, typ)
			OWR.GrantStart(d, typ, NOW)
			OWR.Settle(d, NOW)
			local id = expect[typ]
			SR.Start(d, id, NOW)
			local def = SR.Mission(id)
			T.eq(SR.ProgressOf(d, def), 0, typ .. ": noch nichts abgeholt")
			T.eq(select(1, SR.Claim(d, id, NOW)), false, typ .. ": nicht vor dem Abholen")
			OWR.Collect(d, typ, NOW)
			T.eq(SR.ProgressOf(d, def), 2, typ .. ": Startertrag erfüllt die Mission")
			local money = d.money
			T.eq(select(1, SR.Claim(d, id, NOW)), true, typ .. ": abgeholt")
			T.eq(d.money - money, def.reward.credits, typ .. ": Belohnung")
			T.eq(SR.Current(d).mission.id, "c1_m2", typ .. ": weiter mit Mission 2")
		end
		-- Veteran (werkstatt) mit erledigtem c1_m1 behält Kapitel 1 Stelle 1 als erledigt; ganze Kapitel bleiben erledigt
		local vet = profile(g)
		vet.completed = 30
		MR.ResolveStartPath(vet)
		vet.games.story = SR.Load({ done = { c1_m1 = true } }, vet, NOW)
		T.eq(SR.Current(vet).mission.id, "c1_m2", "Veteran: Stelle 1 erledigt")
		local done = {}
		for ci = 1, 4 do
			for _, m in ipairs(GC.Story.Chapters[ci].Missions) do
				done[m.id] = true
			end
		end
		vet.games.story = SR.Load({ done = done }, vet, NOW)
		T.eq(SR.Current(vet).chapter, 5, "Kapitel 5 bleibt")
		-- laufende Variante eines anderen Wegs läuft zu Ende (z. B. Verkaufsmission von vor der Wahl)
		local mixed = profile(g)
		SR.Start(mixed, "c1_m1", NOW)
		MR.SetStartPath(mixed, "werkstatt")
		T.eq(SR.Current(mixed).mission.id, "c1_m1", "aktive Variante bleibt die Mission ihrer Stelle")
		-- Speichern/Laden: erledigte Variante zählt
		local saved = SR.Load({ done = { c1_m1_produktion = true } }, profile(g), NOW)
		T.eq(saved.done.c1_m1_produktion, true, "Variante bleibt in done")
		T.eq(saved.step, 2, "Stelle 1 erledigt")
		local dl = profile(g)
		MR.SetStartPath(dl, "schrottplatz")
		dl.games.story = SR.Load({ active = { id = "c1_m1_schrottplatz", progress = 0 } }, dl, NOW)
		T.eq(type(dl.games.story.active), "table", "aktive Variante überlebt das Laden")
		-- Kapitel 2–5 unverändert, Prüfungen über alle Varianten
		T.eq(#SR.AllMissions(1), 5, "Kapitel 1: 3 Missionen + 2 Varianten (produktion, schrottplatz; werkstatt/autohaus = c1_m1)")
		T.eq(#SR.UnlockCheck(), 0, "alle Varianten ohne Sackgasse: " .. table.concat(SR.UnlockCheck(), "; "))
		T.eq(#SR.BalanceCheck(), 0, "40-%-Regel: " .. table.concat(SR.BalanceCheck(), "; "))
		for ci = 2, 5 do
			for k, m in ipairs(GC.Story.Chapters[ci].Missions) do
				T.eq(m.id, "c" .. ci .. "_m" .. k, "Kapitel " .. ci .. " unverändert")
			end
		end
	end },

	{ "StartService im Server: Wahl einmal, Gebäude sofort am Grundstück, Tutorial des Wegs, ungültig abgelehnt, Speichern/Laden", function(T, H)
		local S = setup(H)
		local g, SS = S.g, S.SS
		local M = mods(g)
		local MR, OWR, TR = M.MR, M.OWR, M.TR
		local TS = g:MiniServer("TutorialService")
		local OWS = g:MiniServer("OWService")
		local pl, ms, d = S.join(7301, "Mila")
		T.eq(ms.p.mode, "openworld", "Open-World-Place")
		T.eq(MR.StartPath(d), "", "neues Profil")
		local snap = SS.SnapshotFields(ms, d, g:Now(), true)
		T.eq(snap.start.pending, true, "Snapshot: Wahl offen")
		T.eq(#snap.start.choices, 4, "vier Karten")
		T.eq(snap.start.choices[1].id, "werkstatt", "Reihenfolge")
		T.eq(snap.start.choices[2].gift, true, "Autohaus mit Geschenk")
		local tut = TS.SnapshotFields(ms, d, g:Now(), true).tutorial
		T.eq(tut.active, false, "Tutorial wartet")
		T.eq(tut.waiting, true, "Tutorial: waiting")
		T.eq(SS.OnMode(ms, d, "openworld"), true, "Angebot beim Betreten")
		T.eq(SS.OnMode(ms, d, "openworld"), false, "Angebot nur einmal je Sitzung")
		T.eq(SS.OnMode(ms, d, "lobby"), false, "nicht in der Lobby")
		-- ungültig
		local money = d.money
		T.eq(S.choose(pl, "mars"), nil, "unbekannter Weg")
		T.check(S.hasToast(pl, "gibt es nicht"), "Hinweis ungültig")
		T.eq(MR.StartPath(d), "", "nichts gewählt")
		-- außerhalb der Open World
		ms.p.mode = "lobby"
		T.eq(S.choose(pl, "autohaus"), nil, "in der Lobby abgelehnt")
		T.eq(MR.StartPath(d), "", "nichts gewählt (Lobby)")
		ms.p.mode = "openworld"
		-- gültig
		T.eq(S.choose(pl, "autohaus"), true, "Autohaus gewählt")
		T.eq(MR.StartPath(d), "autohaus", "Weg gespeichert")
		T.eq(d.money, money, "kostenlos")
		T.eq(OWR.Built(d, "autohaus"), 1, "Autohaus sofort fertig (Settle im selben Zug)")
		T.check(OWS.ModelOf(pl, "autohaus") ~= nil, "Modell am Grundstück")
		T.eq(SS.SnapshotFields(ms, d, g:Now(), false).start.pending, false, "Snapshot: gewählt")
		T.eq(#SS.SnapshotFields(ms, d, g:Now(), false).start.choices, 0, "keine Karten mehr")
		tut = TS.SnapshotFields(ms, d, g:Now(), true).tutorial
		T.eq(tut.active, true, "Tutorial läuft")
		T.eq(tut.path, "autohaus", "Tutorial des Wegs")
		T.eq(tut.count, #M.GC.Tutorial.ByPath.autohaus, "Schrittzahl des Wegs")
		T.eq(ms.tutorialStarted, true, "Tutorial gestartet")
		local chosen = nil
		for _, n in ipairs(S.log.notices) do
			if n.kind == "start" and n.data.event == "chosen" then
				chosen = n.data
			end
		end
		T.check(chosen ~= nil and chosen.path == "autohaus" and chosen.gift == true, "Hinweis chosen mit Geschenk")
		-- zweite Wahl abgelehnt, nichts geschenkt
		T.eq(S.choose(pl, "produktion"), nil, "zweite Wahl abgelehnt")
		T.check(S.hasToast(pl, "schon gewählt"), "Hinweis schon gewählt")
		T.eq(MR.StartPath(d), "autohaus", "Weg bleibt")
		T.eq(OWR.StageOf(d, "produktion"), 0, "keine Produktion")
		-- Tutorial-Schritte des Wegs über echte Ereignisse
		TS.OnEvent(ms, d, "next")
		TS.OnEvent(ms, d, "next")
		TS.OnEvent(ms, d, "next")
		T.eq(TR.Current(d, "openworld").id, "ah_collect", "beim Abholen")
		T.eq(TS.OnEvent(ms, d, "action:ow_collect"), true, "Abholen erledigt den Schritt")
		T.eq(TR.Current(d, "openworld").id, "map", "weiter mit dem Stadtplan")
		-- werkstatt: kein Gebäude, klassisches Tutorial
		local pl2, ms2, d2 = S.join(7302, "Ole")
		T.eq(S.choose(pl2, "werkstatt"), true, "werkstatt gewählt")
		T.eq(OWR.StageOf(d2, "autohaus") + OWR.StageOf(d2, "produktion") + OWR.StageOf(d2, "schrottplatz"), 0, "werkstatt: kein Geschenk")
		T.eq(TR.Count(d2), 11, "klassisches Tutorial")
		-- Speichern/Laden
		g:Leave(pl)
		g:Advance(1)
		local rec = g:Record(7301)
		local games = rec and rec.data and rec.data.games
		T.check(type(games) == "table", "Datensatz gespeichert")
		if type(games) == "table" then
			T.eq(games.meta and games.meta.startPath, "autohaus", "startPath im Datensatz")
			local b = games.ow and games.ow.buildings and games.ow.buildings.autohaus
			T.eq(b and b.stage, 1, "Autohaus im Datensatz")
			T.eq(b and b.gift, true, "Geschenk im Datensatz")
		end
		local pl3, ms3, d3 = S.join(7301, "Mila")
		T.eq(MR.StartPath(d3), "autohaus", "nach Rejoin: Weg bleibt")
		T.eq(MR.StartPending(d3), false, "nach Rejoin: keine Wahl")
		T.eq(OWR.Built(d3, "autohaus"), 1, "nach Rejoin: Autohaus steht")
		T.eq(S.choose(pl3, "schrottplatz"), nil, "nach Rejoin keine zweite Wahl")
		T.eq(OWR.StageOf(d3, "schrottplatz"), 0, "nach Rejoin nichts geschenkt")
		-- Veteran (2.4.0-Datensatz mit Aufträgen): automatisch werkstatt, keine Wahl, kein Geschenk
		g:SeedLevel(7303, 12, function(data)
			data.completed = 40
		end)
		local pl4, ms4, d4 = S.join(7303, "Veteran")
		T.eq(MR.StartPath(d4), "werkstatt", "Veteran: werkstatt")
		T.eq(SS.SnapshotFields(ms4, d4, g:Now(), true).start.pending, false, "Veteran sieht keine Wahl")
		T.eq(SS.OnMode(ms4, d4, "openworld"), false, "Veteran: kein Angebot")
		T.eq(S.choose(pl4, "autohaus"), nil, "Veteran kann nicht wählen")
		T.eq(OWR.StageOf(d4, "autohaus"), 0, "Veteran: kein Geschenk")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "StartUI: große Karten, Handy einspaltig ohne Überstand, Klick sendet start_choose, verschwindet nach der Wahl", function(T, H)
		for _, vp in ipairs({ Vector2.new(390, 700), Vector2.new(1280, 650) }) do
			local g = H.Garage({ viewport = vp })
			local p = g:Join(1101, { name = "Kim" })
			g:Advance(0.5)
			g:StartClient(p, { run = false })
			g:Advance(1)
			local MiniUI = g:ClientModule(p, "Mini.MiniUI")
			local mod = g:ClientModule(p, "Mini.StartUI")
			local sent = {}
			local rec = {
				Send = function(action, payload)
					table.insert(sent, { action, payload })
				end,
			}
			g:InClient(p, function()
				if not MiniUI.Gui then
					MiniUI.Build()
				end
				mod.Start({ UI = MiniUI, Remote = rec, Toast = function() end })
			end)
			T.eq(mod.IsOpen(), false, "ohne Snapshot verborgen")
			local choices = g:MiniServer("StartService").Choices()
			g:InClient(p, function()
				mod.OnSnapshot({ mode = "lobby", start = { pending = true, path = "", choices = choices } })
			end)
			T.eq(mod.IsOpen(), false, "in der Lobby verborgen")
			g:InClient(p, function()
				mod.OnSnapshot({ mode = "openworld", start = { pending = true, path = "", choices = choices } })
			end)
			g:Advance(0.2)
			T.eq(mod.IsOpen(), true, "Open World: Wahl offen")
			local gui = mod.Gui()
			T.eq(gui.DisplayOrder > 21, true, "über Tutorial-Karte und Hinweisen")
			local panel = gui:FindFirstChild("Panel")
			T.check(panel ~= nil, "Tafel")
			T.check(panel.AbsoluteSize.X <= vp.X - 2 * mod.Margin + 1, "Tafel passt in die Breite (" .. tostring(vp.X) .. ")")
			T.check(panel.AbsolutePosition.X >= mod.Margin - 1, "Rand links")
			for _, typ in ipairs(PATHS) do
				local card = mod.Card(typ)
				T.check(card ~= nil, "Karte " .. typ)
				if card then
					T.check(card.AbsoluteSize.Y >= 44, typ .. ": große Touch-Fläche")
					T.check(card.AbsolutePosition.X >= 0 and card.AbsolutePosition.X + card.AbsoluteSize.X <= vp.X + 1, typ .. ": kein Überstand")
				end
			end
			local colB = gui:FindFirstChild("ColumnB", true)
			T.eq(colB.Visible, vp.X >= mod.TwoColumnsFrom, "Spalten passend zur Breite")
			T.check(g:FindGui(p, "Das wähle ich!") ~= nil, "Knopftext sichtbar")
			T.check(g:FindGui(p, "Bonus:") ~= nil, "Bonus sichtbar")
			g:Click(mod.Card("produktion"))
			T.eq(#sent, 1, "eine Absicht")
			T.eq(sent[1] and sent[1][1], "start_choose", "Aktion start_choose")
			T.eq(sent[1] and sent[1][2].path, "produktion", "Weg produktion")
			g:Click(mod.Card("autohaus"))
			T.eq(#sent, 1, "wartet auf den Server (kein Doppeltipp)")
			g:InClient(p, function()
				mod.OnNotice({ kind = "start", event = "chosen", path = "produktion" })
			end)
			T.eq(mod.IsOpen(), false, "nach der Wahl verborgen")
			g:InClient(p, function()
				mod.OnSnapshot({ mode = "openworld", start = { pending = false, path = "produktion", choices = {} } })
			end)
			T.eq(mod.IsOpen(), false, "bleibt verborgen")
			-- „Später entscheiden“: weg bis zum nächsten Betreten der Open World
			g:InClient(p, function()
				mod.OnSnapshot({ mode = "openworld", start = { pending = true, path = "", choices = choices } })
			end)
			T.eq(mod.IsOpen(), true, "wieder offen (Test)")
			g:Click(gui:FindFirstChild("Later", true))
			T.eq(mod.IsOpen(), false, "später entscheiden")
			g:InClient(p, function()
				mod.OnSnapshot({ mode = "lobby", start = { pending = true, path = "", choices = choices } })
				mod.OnSnapshot({ mode = "openworld", start = { pending = true, path = "", choices = choices } })
			end)
			T.eq(mod.IsOpen(), true, "beim nächsten Betreten wieder da")
			T.eq(g:ErrorText(), "", "keine Skriptfehler")
		end
	end },
}
