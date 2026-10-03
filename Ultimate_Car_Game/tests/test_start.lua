-- Startwahl in der Open World (wie im Tycoon): GameConfig.Start, MetaRules (startPath), OWRules.GrantStart,
-- TutorialRules/TutorialService je Weg, StoryRules (erste Mission von Kapitel 1 je Weg), StartService im echten Server
-- (eigene Aktionen-Tabelle wie test_tutorial, unabhängig von der MiniService-Verkabelung) und StartUI im Mock-Client.
-- Geprüft: Wahl nur einmal, Veteranen bekommen werkstatt automatisch, Stufe 1 geschenkt (sofort fertig, kostenlos,
-- nie zweimal), Tutorial-Schritte je Weg, Kapitel-1-Mission je Weg, Speichern/Laden, ungültiger Weg abgelehnt.
-- 3.x: Die Wahl ist Pflicht (kein „Später entscheiden“, auch Tutorial-Überspringen und abgerechnete Aufträge umgehen sie
-- nicht), die Story startet sofort nach der Wahl (Mission 1 des Wegs aktiv, ohne Kiesplatz-Besuch), Kapitel 1 hat je
-- Weg sechs Missionen und lässt sich mit simulierten Ereignissen ganz durchspielen, Veteranen behalten Weg und Stand,
-- StartService.ResetStart (Entwickler-Menü) setzt Wahl, Tutorial und Kapitel 1 zurück.
local NOW = 1760000000
local PATHS = { "werkstatt", "autohaus", "produktion", "schrottplatz" }
-- erste Mission von Kapitel 1 je Weg (3.x) und die Namen der Startkarten
local FIRST = { werkstatt = "c1_ws1", autohaus = "c1_ah1", produktion = "c1_m1_produktion", schrottplatz = "c1_m1_schrottplatz" }
local NAMES = { werkstatt = "Werkstatt", autohaus = "Verkaufshaus", produktion = "Herstellung", schrottplatz = "Schrottplatz" }

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
		-- 3.x: Namen wie gewünscht und gleich im Tycoon und bei den Open-World-Gebäuden; Symbol und Kapiteltitel je Karte
		for _, typ in ipairs(PATHS) do
			local p = GC.Start.Paths[typ]
			T.eq(p.name, NAMES[typ], "Name der Startkarte " .. typ)
			T.eq(GC.Tycoon.Buildings[typ].name, NAMES[typ], "gleicher Name im Tycoon: " .. typ)
			T.eq(GC.OW.Buildings[typ].name, NAMES[typ], "gleicher Name als Open-World-Gebäude: " .. typ)
			T.check(type(p.icon) == "string" and p.icon ~= "", "Symbol " .. typ)
			local info = GC.Story.Chapters[1].PathInfo[typ]
			T.eq(p.chapter, "Kapitel 1: " .. info.title, "Kapiteltitel auf der Karte " .. typ)
			local _, lines = string.gsub(p.desc, "\n", "")
			T.eq(lines, 1, "zweizeilige Beschreibung " .. typ)
		end
		T.eq(GC.Start.Texts.later, nil, "kein „Später entscheiden“ mehr")
		T.eq(GC.Start.Texts.laterHint, nil, "kein Später-Hinweis mehr")
		T.check(type(GC.Start.Texts.mustChoose) == "string" and type(GC.Start.Texts.reset) == "string", "Texte Pflichtwahl/Zurücksetzen")
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
		-- 3.x: Wahl gezeigt (Pflicht): Aufträge, Tutorial-Schritt UND Gebäude machen das Profil nicht mehr zum Veteranen
		local shown = profile(g)
		T.eq(MR.MarkStartOffered(shown), true, "Wahl gezeigt")
		shown.completed = 4
		shown.games.meta.tutorialStep = 3
		shown.games.ow.buildings.autohaus.stage = 1
		T.eq(MR.StartPending(shown), true, "gezeigt + Aufträge + Gebäude: Wahl bleibt Pflicht")
		T.eq(MR.ResolveStartPath(shown), "", "kein automatischer Weg")
		local gs = {}
		MR.ApplyLoad(gs, H.Copy(shown.games), shown, NOW)
		T.eq(gs.meta.startPath, "", "Laden: Wahl bleibt offen (Gebäude im Datensatz)")
		T.eq(gs.meta.startOffered, true, "Laden: startOffered bleibt")
		-- ResetStart (Entwickler-Menü): Weg offen, Wahl gilt als gezeigt, Tutorial wartet wieder, Belohnung bleibt verbucht
		local rs = profile(g)
		MR.SetStartPath(rs, "schrottplatz")
		rs.completed = 9
		rs.games.meta.tutorialDone = true
		rs.games.meta.tutorialRewarded = true
		rs.games.meta.tutorialStep = 7
		T.eq(MR.ResetStart(rs), true, "ResetStart")
		T.eq(MR.StartPath(rs), "", "Weg wieder offen")
		T.eq(MR.StartPending(rs), true, "Wahl wieder Pflicht (trotz Aufträgen)")
		T.eq(rs.games.meta.tutorialDone, false, "Tutorial läuft wieder")
		T.eq(rs.games.meta.tutorialStep, 1, "Tutorial ab Schritt 1")
		T.eq(rs.games.meta.tutorialRewarded, true, "Belohnung bleibt verbucht (keine zweite)")
		local rl = MR.Load(H.Copy(rs.games.meta), rs, NOW)
		T.eq(rl.startPath, "", "nach Laden weiter offen")
		T.eq(MR.SetStartPath(rs, "produktion"), true, "neue Wahl möglich")
		T.eq(MR.ResetStart({ games = {} }), false, "ohne meta nichts")
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
		-- 3.x: vor der Wahl lässt sich das Tutorial nicht überspringen (sonst wäre die Pflichtwahl umgangen)
		local okSkip, whySkip = TR.Skip(d)
		T.eq(okSkip, false, "Überspringen vor der Wahl abgelehnt")
		T.eq(whySkip, "waiting", "Grund: wartet auf die Wahl")
		T.eq(d.games.meta.tutorialDone, false, "Tutorial nicht beendet")
		T.eq(MR.StartPending(d), true, "Wahl bleibt Pflicht")
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

	{ "StoryRules: Kapitel 1 je Weg (sechs Missionen mit Ort), XP-Kette ohne Sackgasse, Kapitel 2–5 unverändert, Balance", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local SR, MR, GC = M.SR, M.MR, M.GC
		local ch1 = GC.Story.Chapters[1]
		T.eq(SR.Current(profile(g)).mission.id, "c1_ah1", "ohne Wahl: Liste Missions (Weg Verkaufshaus)")
		local seen = {}
		for _, typ in ipairs(PATHS) do
			local d = profile(g)
			MR.SetStartPath(d, typ)
			local cur = SR.Current(d)
			T.eq(cur.chapter, 1, typ .. ": Kapitel 1")
			T.eq(cur.mission.id, FIRST[typ], typ .. ": erste Mission")
			local list = SR.Missions(d, 1)
			T.eq(#list, 6, typ .. ": sechs Missionen")
			T.eq(#ch1.Paths[typ], #ch1.Missions, typ .. ": gleich viele Stellen wie Missions")
			if typ ~= "autohaus" then
				T.eq(list[6].id, "c1_m3", typ .. ": gemeinsame letzte Mission (2.500 Credits)")
			end
			local title = SR.ChapterInfo(d, 1)
			T.eq("Kapitel 1: " .. title, GC.Start.Paths[typ].chapter, typ .. ": Kapiteltitel wie auf der Startkarte")
			for i, m in ipairs(list) do
				T.eq(SR.MissionAt(d, 1, i), m, typ .. ": MissionAt " .. i)
				T.eq(m.index, i, typ .. ": Stelle " .. m.id)
				T.check(type(m.text) == "string" and #m.text >= 60, typ .. ": klarer Text " .. m.id)
				-- jede Mission hat einen Ort (Marker, Schnellreise; Gebäude-Missionen gehen im Menü überall) – außer Kontostand
				-- und Lieferung (eigene Start-/Ziel-Marker)
				local t = SR.TargetOf(m)
				local free = m.money ~= nil or m.event == "delivery"
				T.check(free or (t ~= nil and type(t.name) == "string" and t.name ~= ""), typ .. ": Ziel für " .. m.id)
				if t and m.kind ~= "own" and m.kind ~= "build" then
					T.check(t.travel ~= "", typ .. ": Schnellreise für " .. m.id)
				end
				T.check(m.reward and m.reward.credits > 0 and m.reward.xp == 80, typ .. ": Belohnung " .. m.id)
				if m.id ~= "c1_m3" then
					T.check(not seen[m.id] or seen[m.id] == m, "Id eindeutig: " .. m.id)
				end
				seen[m.id] = m
			end
			-- falsche Varianten lassen sich nicht starten, die eigene schon
			for other, id in pairs(FIRST) do
				if other ~= typ and id ~= FIRST[typ] then
					T.eq(select(1, SR.Start(d, id, NOW)), false, typ .. ": " .. id .. " nicht startbar")
				end
			end
			T.eq(select(1, SR.Start(d, cur.mission.id, NOW)), true, typ .. ": eigene Mission startbar")
		end
		-- Inhalt je Weg (Wunsch des Auftraggebers)
		local function ids(typ)
			local out = {}
			for _, m in ipairs(SR.PathMissions(1, typ)) do
				table.insert(out, m.id)
			end
			return table.concat(out, ",")
		end
		T.eq(ids("autohaus"), "c1_ah1,c1_m1,c1_m2,c1_ah5,c1_ah3,c1_ah4", "Verkaufshaus: Kiesplatz-Kapitel + Gebrauchtwagen + Große Werkstatt + teurer verkaufen")
		T.eq(SR.Mission("c1_ah5").event, "car_bought", "eigener Gebrauchtwagen (der Flitzer wird in der Großen Werkstatt nicht repariert)")
		T.eq(SR.RequiredLevel(SR.Mission("c1_ah5")), 3, "Händler ab Level 3 – nach drei Missionen sicher erreicht")
		T.eq(ids("werkstatt"), "c1_ws1,c1_ws2,c1_ws3,c1_ws4,c1_ws5,c1_m3", "Werkstatt: Ölwechsel, Check mit Anruf, Teile …")
		T.eq(ids("produktion"), "c1_m1_produktion,c1_pr2,c1_pr3,c1_pr4,c1_pr5,c1_m3", "Herstellung: Pakete, Lieferungen, Teile")
		T.eq(ids("schrottplatz"), "c1_m1_schrottplatz,c1_sc2,c1_sc3,c1_sc4,c1_sc5,c1_m3", "Schrottplatz: Minispiele + Teile an die Große Werkstatt")
		-- 3.x: Große-Werkstatt-Missionen lesen das Profil (own/pwStat), damit frühere Reparaturen/Verkäufe zählen
		T.eq(SR.Mission("c1_ah3").pwStat, "repairs", "Reparatur in der Großen Werkstatt (pw.repairs)")
		T.eq(SR.Mission("c1_ah4").repaired, true, "reparierten Wagen teurer verkaufen")
		T.eq(SR.Mission("c1_sc2").pwStat, "partsSold", "Teile an die Große Werkstatt (pw.partsSold)")
		T.eq(SR.Mission("c1_pr3").pwStat, "partsSold", "Herstellung: Teile an die Große Werkstatt")
		T.eq(SR.TargetOf(SR.Mission("c1_sc2")).key, "teileankauf", "Schrottplatz: Ziel Teile-Ankauf (City.Stations.teileankauf)")
		T.eq(SR.TargetOf(SR.Mission("c1_pr3")).travel, "teileankauf", "Herstellung: Schnellreise zum Teile-Ankauf")
		T.eq(SR.TargetOf({ kind = "event", event = "pw_parts_sold" }).key, "teileankauf", "pw_parts_sold: Teile-Ankauf")
		T.eq(SR.Mission("c1_ws1").event, "settle:oil", "Ölwechsel")
		T.eq(SR.Mission("c1_ws2").event, "settle:inspection", "Fahrzeug-Check mit Anruf")
		T.eq(SR.Mission("c1_ws3").event, "parts_bought", "Teile kaufen")
		T.eq(SR.Mission("c1_pr2").event, "delivery", "Lieferfahrt")
		T.eq(SR.TargetOf(SR.Mission("c1_ah3")).key, "grosswerkstatt", "Ziel Große Werkstatt (City.Stations.grosswerkstatt)")
		T.eq(SR.TargetOf(SR.Mission("c1_ah3")).travel, "grosswerkstatt", "Schnellreise zur Großen Werkstatt")
		T.eq(SR.TargetOf(SR.Mission("c1_ah1")).zone, "anchor", "Gebäude-Mission zeigt aufs eigene Gebäude")
		T.eq(#SR.AllMissions(1), 6 + 6 + 5 + 5, "Kapitel 1: Verkaufshaus 6, Werkstatt 6, Herstellung/Schrottplatz je 5 eigene (c1_m3 gemeinsam)")
		-- XP-Kette: was eine Mission braucht, bringt der Spieler durch die vorigen Missionen sicher mit (Presse Lv 2, Zerlegeplatz Lv 3)
		T.eq(#SR.UnlockCheck(), 0, "alle Wege ohne Sackgasse: " .. table.concat(SR.UnlockCheck(), "; "))
		T.eq(SR.RequiredLevel(SR.Mission("c1_sc4")), 3, "Zerlegeplatz braucht Level 3")
		T.eq(SR.RequiredLevel(SR.Mission("c1_sc3")), 2, "Schrottpresse braucht Level 2")
		T.eq(SR.RequiredLevel(SR.Mission("c1_ws5")), 2, "Gerätekauf ab Level 2 (minLevel)")
		T.eq(SR.RequiredLevel(SR.Mission("c1_pr2")), 1, "Lieferfahrt mit dem Flitzer ab Level 1")
		T.check(SR.LevelAfterXp(1, 240) >= 3, "drei Missionen (240 XP) bringen Level 3")
		T.eq(SR.LevelAfterXp(1, 100), 1, "100 XP: noch Level 1")
		T.eq(#SR.BalanceCheck(), 0, "40-%-Regel: " .. table.concat(SR.BalanceCheck(), "; "))
		-- Balance wie tools/economy_sim.py --check (das nur die Liste Missions prüft) für JEDEN Weg: (Credits + XP × XP-Wert) /
		-- Minuten + Kapitel-Bonus ≤ 40 % der Werkstatt auf Level 1; XP-Wert = 2.4.0-Levelbonus (120 + 18 × 2) / XP bis Level 2
		local R = g:Rules()
		local xv = (120 + 18 * 2) / R.XPNeeded({ level = 1 })
		local cap = GC.Story.Balance.Share * SR.WorkshopPerMinute(1)
		for _, typ in ipairs(PATHS) do
			local list = SR.PathMissions(1, typ)
			local total = 0
			for _, m in ipairs(list) do
				total += m.minutes
			end
			local bonus = GC.XP.StoryChapter[1] * xv / total
			for _, m in ipairs(list) do
				local per = (m.reward.credits + m.reward.xp * xv) / m.minutes + bonus
				T.check(per <= cap + 1e-9, string.format("%s %s: %.1f Credits-Wert/Min ≤ %.1f", typ, m.id, per, cap))
			end
		end
		-- Kapitel 2–5 unverändert
		for ci = 2, 5 do
			for k, m in ipairs(GC.Story.Chapters[ci].Missions) do
				T.eq(m.id, "c" .. ci .. "_m" .. k, "Kapitel " .. ci .. " unverändert")
			end
			T.eq(GC.Story.Chapters[ci].Paths, nil, "Kapitel " .. ci .. " ohne Startweg-Listen")
		end
		T.check(M.MiniRules.IsClean(GC.Story.Chapters[1]), "Kapitel 1 sauber (sendbar)")
	end },

	{ "StoryRules: jedes Kapitel 1 lässt sich mit simulierten Ereignissen ganz durchspielen (Level 1 → Kapitel 2)", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local SR, MR, OWR = M.SR, M.MR, M.OWR
		for _, typ in ipairs(PATHS) do
			local d = profile(g, 1)
			d.money = 800
			MR.SetStartPath(d, typ)
			OWR.GrantStart(d, typ, NOW)
			OWR.Settle(d, NOW)
			local claimed = 0
			for step = 1, 6 do
				local def = SR.AutoStart(d, NOW + step, 0)
				if not T.check(def ~= nil, typ .. ": Mission " .. step .. " startet von selbst") then
					break
				end
				T.eq(def.index, step, typ .. ": Stelle " .. step)
				T.eq(SR.AutoStart(d, NOW + step, 0), nil, typ .. ": nur eine Mission gleichzeitig")
				T.check(SR.RequiredLevel(def) <= d.level, typ .. ": " .. def.id .. " ist auf Level " .. d.level .. " machbar")
				T.eq(select(1, SR.Claim(d, def.id, NOW)), false, typ .. ": " .. def.id .. " nicht vor dem Ziel")
				-- Ereignisse wie im Spiel (Server meldet sie)
				local target = SR.Target(def)
				if def.kind == "own" and def.pwStat then
					-- Große Werkstatt (PublicWorkshopService zählt im Profil; pw_repair merkt den Kiesplatz-Bonus)
					d.games.pw = type(d.games.pw) == "table" and d.games.pw or { cars = {}, repairs = 0, partsSold = 0 }
					d.games.pw[def.pwStat] = math.max(d.games.pw[def.pwStat] or 0, target)
					if def.pwStat == "repairs" then
						SR.OnEvent(d, "pw_repair", { car = "1", gain = 100 }, NOW)
					end
				elseif def.kind == "own" and def.owTyp then
					local e = OWR.Entry(d, def.owTyp)
					e[def.owStat] = math.max(e[def.owStat] or 0, target)
				elseif def.kind == "own" and def.money then
					d.money = math.max(d.money, def.money)
				elseif def.kind == "sell" then
					for _ = 1, target do
						if def.repaired then
							-- die Reparatur aus der Mission davor (pw_repair) wartet schon auf ihren Verkauf
							local waiting = d.games.story.sales.repaired
							T.check(waiting >= 1, typ .. ": reparierter Wagen wartet (" .. waiting .. ")")
							local before = d.money
							local offer = SR.NextSale(d, "seed:" .. step, d.level)
							local res = SR.Sell(d, offer, 1, NOW)
							T.check(res and res.sold and res.repaired == true, typ .. ": Verkauf frisch repariert")
							T.check(d.money - before >= math.floor(offer.tiers[1].profit * 1.5), typ .. ": +50 % Gewinn")
							T.eq(d.games.story.sales.repaired, waiting - 1, typ .. ": Reparatur verbraucht")
						else
							SR.OnSale(d, 1, false, NOW)
						end
					end
				elseif def.kind == "event" then
					for _ = 1, target do
						SR.OnEvent(d, def.event, { count = 1 }, NOW)
					end
				elseif def.kind == "stat" then
					SR.OnStat(d, def.stat, target, NOW)
				end
				local money = d.money
				local ok, res = SR.Claim(d, def.id, NOW)
				T.eq(ok, true, typ .. ": " .. def.id .. " abgeholt")
				if ok then
					claimed += 1
					T.eq(res.credits, def.reward.credits, typ .. ": Belohnung " .. def.id)
					T.check(d.money - money >= def.reward.credits, typ .. ": Credits gutgeschrieben " .. def.id)
					if step == 6 then
						T.eq(res.chapterDone, true, typ .. ": Kapitel 1 geschafft")
					end
				end
			end
			T.eq(claimed, 6, typ .. ": alle sechs Missionen")
			T.eq(SR.Current(d).chapter, 2, typ .. ": weiter mit Kapitel 2")
			T.check(d.level >= 3, typ .. ": Level " .. d.level .. " nach Kapitel 1")
			local nxt = SR.AutoStart(d, NOW, 0, d.level)
			T.eq(nxt ~= nil, d.level >= SR.ChapterLevel(2), typ .. ": Kapitel 2 startet von selbst, sobald Level " .. SR.ChapterLevel(2) .. " erreicht ist (Level " .. d.level .. ")")
			T.eq(d.games.stats.missionsDone, 6, typ .. ": sechs Missionen gezählt")
		end
		-- Sell-Mission „repariert“: ein normaler Verkauf zählt nicht
		local d = profile(g)
		MR.SetStartPath(d, "autohaus")
		d.games.story = SR.Load({ layout = SR.Layout, done = { c1_ah1 = true, c1_m1 = true, c1_m2 = true, c1_ah5 = true, c1_ah3 = true } }, d, NOW)
		T.eq(SR.AutoStart(d, NOW, 0).id, "c1_ah4", "Mission „teurer verkaufen“")
		T.eq(#SR.OnSale(d, 3, false, NOW, false), 0, "ohne Reparatur zählt der Verkauf nicht")
		-- 3.x: Händler-Verkauf (CarService car_sold { repaired }): nur ein reparierter Wagen zählt
		T.eq(#SR.OnEvent(d, "action:mini_car_sell", {}, NOW), 0, "Aktion allein zählt nicht mehr")
		T.eq(#SR.OnEvent(d, "car_sold", { repaired = false }, NOW), 0, "unreparierter Wagen beim Händler zählt nicht")
		T.eq(#SR.OnEvent(d, "car_sold", {}, NOW), 0, "ohne Angabe zählt nicht")
		T.eq(#SR.OnEvent(d, "car_sold", { repaired = true }, NOW), 1, "reparierter Wagen beim Händler zählt")
		-- 3.x: Große Werkstatt früher genutzt (Mission davor noch nicht abgeholt): zählt trotzdem (Profil, nicht Ereignis)
		for _, case in ipairs({
			{ path = "schrottplatz", done = {}, first = "c1_m1_schrottplatz", id = "c1_sc2", stat = "partsSold", key = "teileankauf" },
			{ path = "produktion", done = { c1_m1_produktion = true }, first = "c1_pr2", id = "c1_pr3", stat = "partsSold", key = "teileankauf" },
			{ path = "autohaus", done = { c1_ah1 = true, c1_m1 = true, c1_m2 = true }, first = "c1_ah5", id = "c1_ah3", stat = "repairs", key = "grosswerkstatt" },
		}) do
			local dp = profile(g, 5)
			MR.SetStartPath(dp, case.path)
			dp.games.story = SR.Load({ layout = SR.Layout, done = case.done }, dp, NOW)
			T.eq(SR.AutoStart(dp, NOW, 0, 5).id, case.first, case.path .. ": " .. case.first .. " läuft")
			-- jetzt schon Teile verkauft / repariert (PublicWorkshopService zählt im Profil, das Ereignis geht ins Leere)
			dp.games.pw = { cars = {}, day = "", sold = 0, refund = 0, repairs = 0, partsSold = 0 }
			dp.games.pw[case.stat] = 2
			SR.OnEvent(dp, case.stat == "repairs" and "pw_repair" or "pw_parts_sold", { count = 2 }, NOW)
			-- Mission davor erledigen und abholen: die Werkstatt-Mission ist sofort erfüllt
			local done2 = table.clone(case.done)
			done2[case.first] = true
			dp.games.story = SR.Load({ layout = SR.Layout, done = done2 }, dp, NOW)
			local nxt = SR.AutoStart(dp, NOW + 1, 0, 5)
			T.eq(nxt and nxt.id, case.id, case.path .. ": " .. case.id .. " startet")
			T.eq(SR.ProgressOf(dp, SR.Mission(case.id)), 1, case.path .. ": frühere Werkstatt-Nutzung zählt")
			T.eq(select(1, SR.Claim(dp, case.id, NOW + 2)), true, case.path .. ": sofort abholbar")
			T.eq(SR.TargetOf(SR.Mission(case.id)).key, case.key, case.path .. ": Marker am richtigen Schalter")
		end
		-- reparierter Wagen in der Garage (pw.cars[id].b > 0) zählt für c1_ah3 auch ohne Zähler
		local dr = profile(g, 5)
		dr.games.pw = { cars = { ["3"] = { b = 20 } }, repairs = 0, partsSold = 0 }
		T.eq(SR.PwStat(dr, "repairs"), 1, "repariertes Auto zählt als Reparatur")
		T.eq(SR.PwStat({ games = {} }, "partsSold"), 0, "ohne Werkstatt-Daten 0")
		-- Ereignis „settle“ allein erfüllt den Ölwechsel nicht, „settle:oil“ schon
		local dw = profile(g)
		MR.SetStartPath(dw, "werkstatt")
		SR.AutoStart(dw, NOW, 0)
		T.eq(#SR.OnEvent(dw, "settle", {}, NOW), 0, "irgendein Auftrag ist kein Ölwechsel")
		T.eq(#SR.OnEvent(dw, "settle:inspection", {}, NOW), 0, "Fahrzeug-Check ist kein Ölwechsel")
		T.eq(#SR.OnEvent(dw, "settle:oil", {}, NOW), 1, "Ölwechsel")
	end },

	{ "StoryRules: Veteranen behalten ihren Stand (alte Kapitel-1-Liste), ResetChapter1, Laden/Whitelist", function(T, H)
		local g = H.Garage({ noServer = true })
		local M = mods(g)
		local SR, MR, GC = M.SR, M.MR, M.GC
		-- altes Kapitel 1 ganz geschafft (ohne layout): Kapitel 1 bleibt erledigt, keine zweite Belohnung
		local vet = profile(g, 7)
		vet.completed = 30
		MR.ResolveStartPath(vet)
		T.eq(MR.StartPath(vet), "werkstatt", "Veteran: werkstatt")
		vet.games.story = SR.Load({ done = { c1_m1 = true, c1_m2 = true, c1_m3 = true } }, vet, NOW)
		T.eq(SR.Current(vet).chapter, 2, "altes Kapitel 1 geschafft -> Kapitel 2")
		for _, m in ipairs(SR.Missions(vet, 1)) do
			T.eq(SR.SlotDone(vet.games.story, 1, m.index), true, "Stelle erledigt: " .. m.id)
		end
		local vp = SR.Load({ done = { c1_m1_produktion = true, c1_m2 = true, c1_m3 = true } }, vet, NOW)
		T.eq(vp.chapter, 2, "alte Herstellungs-Variante geschafft -> Kapitel 2")
		-- spätere Kapitel geschafft (ohne layout): Kapitel 1 gilt als erledigt
		local done = {}
		for ci = 2, 4 do
			for _, m in ipairs(GC.Story.Chapters[ci].Missions) do
				done[m.id] = true
			end
		end
		vet.games.story = SR.Load({ done = done }, vet, NOW)
		T.eq(SR.Current(vet).chapter, 5, "Kapitel 5 bleibt")
		-- angefangener alter Stand: erledigte Missionen bleiben erledigt (Stelle zählt), nichts doppelt
		local part = SR.Load({ done = { c1_m1 = true } }, profile(g), NOW)
		T.eq(part.done.c1_m1, true, "c1_m1 bleibt erledigt")
		T.eq(part.chapter, 1, "noch Kapitel 1")
		local dp = profile(g)
		MR.SetStartPath(dp, "autohaus")
		dp.games.story = part
		T.eq(SR.Current(dp).mission.id, "c1_ah1", "Verkaufshaus: erst die Einnahmen")
		T.eq(SR.SlotDone(part, 1, 2), true, "Stelle 2 (Kiesplatz-Verkäufe) erledigt")
		-- neuer Stand (layout) mit c1_m3: kein Altbestand, Kapitel 1 nicht automatisch fertig
		local fresh = SR.Load({ layout = SR.Layout, done = { c1_m3 = true } }, profile(g), NOW)
		T.eq(fresh.chapter, 1, "neuer Stand: Kapitel 1 bleibt offen")
		-- Laden: Whitelist, Idempotenz, aktive Mission nur an der aktuellen Stelle
		local dl = profile(g)
		MR.SetStartPath(dl, "schrottplatz")
		dl.games.story = SR.Load({ layout = SR.Layout, active = { id = "c1_m1_schrottplatz", progress = 0 } }, dl, NOW)
		T.eq(type(dl.games.story.active), "table", "aktive Mission der aktuellen Stelle überlebt das Laden")
		local skip = SR.Load({ layout = SR.Layout, active = { id = "c1_sc3", progress = 5 } }, dl, NOW)
		T.eq(skip.active, false, "Mission einer späteren Stelle ist nach dem Laden nicht aktiv")
		local raw = { layout = SR.Layout, done = { c1_ws1 = true, quatsch = true }, sales = { n = 2, repaired = 99 }, active = { id = "c1_ws2", progress = 0 } }
		local once = SR.Load(raw, profile(g), NOW)
		T.eq(once.done.quatsch, nil, "unbekannte Mission fällt weg")
		T.eq(once.sales.repaired, GC.Story.Sale.RepairedMax, "reparierte Wagen gedeckelt")
		T.eq(once.layout, SR.Layout, "layout gespeichert")
		local twice = SR.Load(H.Copy(once), profile(g), NOW)
		local same, where = H.DeepEqual(once, twice)
		T.check(same, "Load idempotent: " .. tostring(where))
		T.check(M.MiniRules.IsClean(once), "sauber")
		T.eq(SR.Default().layout, SR.Layout, "neues Profil: aktueller Stand")
		-- ResetChapter1: alle Kapitel-1-Missionen (jeder Weg) wieder offen, spätere Kapitel bleiben
		local dr = profile(g)
		MR.SetStartPath(dr, "werkstatt")
		local all = { c2_m1 = true }
		for _, m in ipairs(SR.AllMissions(1)) do
			all[m.id] = true
		end
		dr.games.story = SR.Load({ layout = SR.Layout, done = all }, dr, NOW)
		T.eq(SR.Current(dr).chapter, 2, "vorher Kapitel 2")
		T.eq(SR.ResetChapter1(dr), true, "ResetChapter1")
		T.eq(SR.Current(dr).chapter, 1, "wieder Kapitel 1")
		T.eq(SR.Current(dr).mission.id, "c1_ws1", "ab Mission 1")
		T.eq(dr.games.story.done.c2_m1, true, "Kapitel 2 bleibt erledigt")
		for _, m in ipairs(SR.AllMissions(1)) do
			T.eq(dr.games.story.done[m.id], nil, "offen: " .. m.id)
		end
		SR.AutoStart(dr, NOW, 0)
		T.eq(dr.games.story.active.id, "c1_ws1", "läuft wieder")
		SR.ResetChapter1(dr)
		T.eq(dr.games.story.active, false, "laufende Kapitel-1-Mission endet beim Zurücksetzen")
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
		-- 3.x: Story läuft sofort – Kapitel 1 des Wegs, Mission 1 aktiv
		local stA = d.games.story
		T.check(type(stA.active) == "table" and stA.active.id == FIRST.autohaus, "Mission 1 des Verkaufshauses läuft sofort: " .. tostring(type(stA.active) == "table" and stA.active.id))
		local chapterNote = nil
		for _, n in ipairs(g:Notices(pl, "story")) do
			if n.event == "chapter" then
				chapterNote = n
			end
		end
		T.check(chapterNote ~= nil and chapterNote.chapter == 1 and chapterNote.title == "Der Kiesplatz", "Kapitel-Intro des Wegs (mini_notice story/chapter)")
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
		T.check(type(d2.games.story.active) == "table" and d2.games.story.active.id == FIRST.werkstatt, "Werkstatt: Ölwechsel läuft sofort")
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
		T.eq(MR.StartPath(d4), "werkstatt", "Veteran behält seinen Weg")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "Pflicht-Startwahl: kein „Später“, Tutorial-Überspringen und abgerechnete Aufträge umgehen sie nicht, Respawn bietet sie wieder an", function(T, H)
		local S = setup(H)
		local g, SS = S.g, S.SS
		local M = mods(g)
		local MR = M.MR
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local pl, ms, d = S.join(7311, "Lena")
		ms.greeted = true -- wie nach dem „hello“ des Clients (sonst wartet der Hinweis)
		T.eq(SS.OnMode(ms, d, "openworld"), true, "Angebot beim Betreten")
		T.eq(d.games.meta.startOffered, true, "Angebot gemerkt")
		-- Tutorial überspringen (echte Aktion) geht vor der Wahl nicht – sonst wäre die Wahl umgangen
		local m = g:Mark()
		g:Act(pl, "tutorial_skip", { rid = 11 })
		T.eq(d.games.meta.tutorialDone, false, "Tutorial nicht übersprungen")
		T.eq(MR.StartPending(d), true, "Wahl weiter Pflicht")
		T.check(g:HasToast(pl, "Wähle zuerst", m), "Hinweis: erst wählen")
		-- über das Tablet einen Auftrag abrechnen: die Wahl bleibt offen, die Story wartet
		local receipt = Flow.CompleteInspection(T, g, pl)
		T.check(receipt ~= nil, "Werkstatt-Auftrag abgerechnet")
		T.check(d.completed >= 1, "d.completed gezählt")
		g:Advance(1.2)
		T.eq(MR.StartPending(d), true, "Startwahl nach dem Auftrag weiter offen")
		T.eq(SS.SnapshotFields(ms, d, g:Now(), true).start.pending, true, "Snapshot: weiter offen")
		T.eq(d.games.story.active, false, "Story wartet auf die Wahl")
		-- nächste Ankunft in der Spielermeile (neue Figur): erneutes Angebot
		local function offers()
			local n = 0
			for _, x in ipairs(S.log.notices) do
				if x.kind == "start" and x.data.event == "offer" then -- nur ein Spieler in diesem Fall
					n += 1
				end
			end
			return n
		end
		local before = offers()
		SS.OnArrive(ms, d) -- erste Figur der Sitzung zählt nicht (Angebot kam schon beim Betreten)
		g:Respawn(pl)
		g:Advance(0.5)
		T.eq(offers(), before + 1, "nach dem Respawn kommt die Startwahl wieder")
		ms.p.mode = "lobby"
		T.eq(SS.OnArrive(ms, d), false, "in der Lobby kein Angebot")
		ms.p.mode = "openworld"
		-- Rejoin: die Wahl ist weiter Pflicht (gespeichert: startOffered)
		g:Leave(pl)
		g:Advance(1)
		local pl2, ms2, d2 = S.join(7311, "Lena")
		T.eq(MR.StartPending(d2), true, "nach Rejoin weiter offen (trotz abgerechnetem Auftrag)")
		T.eq(SS.SnapshotFields(ms2, d2, g:Now(), true).start.pending, true, "Snapshot nach Rejoin: offen")
		T.eq(S.choose(pl2, "schrottplatz"), true, "Wahl nach Aufträgen noch möglich")
		T.eq(MR.StartPath(d2), "schrottplatz", "Weg gespeichert")
		T.check(type(d2.games.story.active) == "table" and d2.games.story.active.id == FIRST.schrottplatz, "Story läuft sofort")
		local n0 = offers()
		g:Respawn(pl2)
		g:Advance(0.5)
		T.eq(offers(), n0, "gewählt: kein weiteres Angebot")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "Nach der Wahl (echte Aktion start_choose) läuft Mission 1 jedes Wegs sofort – Snapshot, Hinweise, Tutorial", function(T, H)
		local g = H.Garage()
		local GC = g:MiniShared("GameConfig")
		for i, typ in ipairs(PATHS) do
			local pl = g:Join(7400 + i, { name = "Neu" .. i })
			g:Advance(1.2)
			local d = g:D(pl)
			local ms = g:MiniState(pl)
			T.eq(ms.p.mode, "openworld", typ .. ": Open World")
			local snap0 = g:MiniSnapshot(pl)
			T.eq(snap0 and snap0.start and snap0.start.pending, true, typ .. ": neuer Spieler bekommt die Wahl")
			T.eq(snap0 and snap0.start and #snap0.start.choices, 4, typ .. ": vier Karten")
			T.eq(d.games.story.active, false, typ .. ": vor der Wahl läuft keine Mission")
			local m = g:Mark()
			T.eq(g:Act(pl, "start_choose", { path = typ, rid = 50 + i }), "ok", typ .. ": start_choose")
			local st = d.games.story
			T.check(type(st.active) == "table" and st.active.id == FIRST[typ], typ .. ": Mission 1 aktiv: " .. tostring(type(st.active) == "table" and st.active.id))
			local started = nil
			for _, n in ipairs(g:Notices(pl, "story", m)) do
				if n.event == "started" and n.mission == FIRST[typ] then
					started = n
				end
			end
			T.check(started ~= nil and started.auto == true, typ .. ": Hinweis „Mission gestartet“ (automatisch)")
			T.check(g:HasToast(pl, "Neue Mission", m), typ .. ": Toast „Neue Mission“")
			g:Advance(1.1)
			local snap = g:MiniSnapshot(pl, m)
			local active = snap and snap.story and snap.story.active
			T.check(type(active) == "table" and active.id == FIRST[typ], typ .. ": Snapshot story.active")
			T.check(type(active) == "table" and type(active.text) == "string" and #active.text > 40, typ .. ": Missionstext im Snapshot")
			T.eq(snap and snap.story and snap.story.path, typ, typ .. ": Snapshot story.path")
			T.eq(snap and snap.story and snap.story.chapterTitle, GC.Story.Chapters[1].PathInfo[typ].title, typ .. ": Kapiteltitel des Wegs")
			T.eq(snap and snap.start and snap.start.pending, false, typ .. ": Wahl erledigt")
			T.eq(snap and snap.tutorial and snap.tutorial.active, true, typ .. ": Tutorial läuft")
			-- story_start der laufenden Mission ist kein Fehler (alter Client)
			m = g:Mark()
			T.eq(g:Act(pl, "story_start", { id = FIRST[typ], rid = 70 + i }), "ok", typ .. ": story_start der laufenden Mission")
			T.check(not g:HasToast(pl, "schon bei", m), typ .. ": kein Fehler-Toast")
		end
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "Werkstatt im Server: Ölwechsel, Fahrzeug-Check mit Anruf und Teilekauf zählen über echte 2.4.0-Abläufe; nächste Mission startet nach dem Abholen", function(T, H)
		local g = H.Garage()
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local C = g:Config()
		local pl = g:Join(7451, { name = "Mech" })
		g:Advance(1.2)
		T.eq(g:Act(pl, "start_choose", { path = "werkstatt", rid = 1 }), "ok", "start_choose werkstatt")
		local d = g:D(pl)
		T.eq(d.games.story.active.id, "c1_ws1", "Ölwechsel läuft")
		-- ein Fahrzeug-Check ist kein Ölwechsel
		local rec = Flow.CompleteInspection(T, g, pl)
		T.check(rec ~= nil, "Fahrzeug-Check abgerechnet")
		g:Advance(1.1)
		T.eq(d.games.story.active.progress, 0, "Check zählt nicht als Ölwechsel")
		-- Ölwechsel: Angebot sicherstellen, annehmen, reparieren, abrechnen
		local function ensureOffer(kind)
			if not Flow.FindOffer(g, pl, kind) then
				table.insert(d.offers, { id = "offer_test_" .. kind, kind = kind, carId = "komet" })
				g:Send(pl, "select", {})
				g:Advance(0.2)
			end
		end
		ensureOffer("oil")
		local j = Flow.AcceptKind(T, g, pl, "oil")
		T.check(j ~= nil, "Ölwechsel angenommen")
		if j then
			Flow.Scan(T, g, pl, j.id)
			j = Flow.Diagnose(T, g, pl, j.id) or j
			local def = C.JobById.oil
			for i = 1, #def.steps do
				Flow.RepairStep(T, g, pl, j.id, i)
			end
			Flow.Scan(T, g, pl, j.id)
			T.eq(Flow.Job(g, pl, j.id) and Flow.Job(g, pl, j.id).phase, "invoice", "Ölwechsel fertig")
			local m = g:Mark()
			Flow.Settle(T, g, pl, j.id)
			g:Advance(0.2)
			local done = nil
			for _, n in ipairs(g:Notices(pl, "mission", m)) do
				if n.id == "c1_ws1" and n.done then
					done = n
				end
			end
			T.check(done ~= nil, "Ölwechsel erfüllt die Mission (settle:oil)")
		end
		g:Advance(0.6)
		T.eq(g:Act(pl, "story_claim", { id = "c1_ws1", rid = 2 }), "ok", "Belohnung abholen")
		T.eq(d.games.story.done.c1_ws1, true, "Mission 1 erledigt")
		T.check(type(d.games.story.active) == "table" and d.games.story.active.id == "c1_ws2", "Mission 2 startet direkt nach dem Abholen")
		-- Fahrzeug-Check mit Befund und Kundenanruf (Handy/Anruf) -> settle:inspection
		local m2 = g:Mark()
		local rec2 = Flow.CompleteInspection(T, g, pl, { finding = "oil", decision = true })
		T.check(rec2 ~= nil, "Check mit Befund und Anruf abgerechnet")
		g:Advance(0.2)
		local done2 = nil
		for _, n in ipairs(g:Notices(pl, "mission", m2)) do
			if n.id == "c1_ws2" and n.done then
				done2 = n
			end
		end
		T.check(done2 ~= nil, "Fahrzeug-Check mit Anruf erfüllt Mission 2")
		g:Advance(0.6)
		T.eq(g:Act(pl, "story_claim", { id = "c1_ws2", rid = 3 }), "ok", "Mission 2 abholen")
		T.eq(d.games.story.active.id, "c1_ws3", "Mission 3: Teile kaufen")
		-- Teile kaufen am Teilehandel (2.4.0-Aktion order)
		local sku = nil
		for _, part in ipairs(C.Parts) do
			if part.eta == 0 and part.level <= d.level and not sku then
				sku = part.id
			end
		end
		g:Send(pl, "travel", { key = "parts" })
		g:Advance(0.3)
		g:Send(pl, "order", { sku = sku, qty = 1 })
		g:Advance(1.2)
		T.eq(d.games.story.active.progress, 1, "Teilekauf zählt (parts_bought)")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "StartService.ResetStart (Entwickler-Menü): Wahl wieder offen, Kapitel 1 und Tutorial von vorn, neue Wahl startet die Story neu", function(T, H)
		local S = setup(H)
		local g, SS = S.g, S.SS
		local M = mods(g)
		local MR, SR, TR = M.MR, M.SR, M.TR
		local pl, ms, d = S.join(7501, "Dev")
		ms.greeted = true
		T.eq(S.choose(pl, "autohaus"), true, "Verkaufshaus gewählt")
		T.eq(d.games.story.active.id, "c1_ah1", "Mission 1 läuft")
		-- etwas Fortschritt: Mission 1 erfüllt und abgeholt, Mission 2 läuft
		g:D(pl).games.ow.buildings.autohaus.collects = 1
		T.eq(select(1, SR.Claim(d, "c1_ah1", g:Now())), true, "Mission 1 abgeholt")
		SR.AutoStart(d, g:Now(), 0)
		d.games.meta.tutorialRewarded = true
		local before = #S.log.notices
		T.eq(SS.ResetStart(ms, d), true, "ResetStart")
		T.eq(MR.StartPath(d), "", "Weg offen")
		T.eq(MR.StartPending(d), true, "Wahl wieder Pflicht")
		T.eq(d.games.story.done.c1_ah1, nil, "Kapitel 1 von vorn")
		T.eq(d.games.story.active, false, "keine Mission aktiv")
		T.eq(TR.Waiting(d, "openworld"), true, "Tutorial wartet wieder")
		local offer, reset = false, false
		for i = before + 1, #S.log.notices do
			local n = S.log.notices[i]
			if n.kind == "start" and n.data.event == "offer" then
				offer = true
			elseif n.kind == "start" and n.data.event == "reset" then
				reset = true
			end
		end
		T.check(offer and reset, "Hinweise reset und offer (die Karte kommt sofort)")
		T.check(S.hasToast(pl, "zurückgesetzt"), "Toast zurückgesetzt")
		T.eq(SS.SnapshotFields(ms, d, g:Now(), true).start.pending, true, "Snapshot: Wahl offen")
		g:Advance(1.2)
		T.eq(d.games.story.active, false, "Story wartet wieder auf die Wahl")
		-- neue Wahl: anderer Weg, Story und Tutorial starten neu, keine zweite Tutorial-Belohnung
		T.eq(S.choose(pl, "schrottplatz"), true, "neue Wahl")
		T.eq(MR.StartPath(d), "schrottplatz", "neuer Weg")
		T.eq(d.games.story.active.id, FIRST.schrottplatz, "Mission 1 des neuen Wegs läuft")
		T.eq(TR.Current(d, "openworld").id, "move", "Tutorial ab Schritt 1")
		T.eq(TR.Rewarded(d), true, "Tutorial-Belohnung bleibt verbucht")
		T.eq(ms.tutorialStarted, true, "Tutorial des neuen Wegs gestartet")
		-- ohne Profil-meta: nichts
		T.eq(SS.ResetStart(ms, { games = {} }), false, "ohne meta nichts")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "Veteranen: alter 2.4.0-/3.0-Datensatz behält Weg und Story-Stand, sieht keine Wahl, Story läuft weiter", function(T, H)
		local g = H.Garage()
		local MR = g:MiniShared("MetaRules")
		g:SeedLevel(7601, 12, function(data)
			data.completed = 40
			data.games = data.games or {}
			data.games.meta = { tutorialDone = true, startPath = "produktion" }
			data.games.story = { done = { c1_m1_produktion = true, c1_m2 = true, c1_m3 = true, c2_m1 = true } }
		end)
		local pl = g:Join(7601, { name = "Alt" })
		g:Advance(1.2)
		local d = g:D(pl)
		T.eq(MR.StartPath(d), "produktion", "Weg bleibt")
		T.eq(MR.StartPending(d), false, "keine Wahl")
		local snap = g:MiniSnapshot(pl)
		T.eq(snap and snap.start and snap.start.pending, false, "Snapshot: keine Wahl")
		T.eq(d.games.story.chapter, 2, "Kapitel 2 (altes Kapitel 1 geschafft)")
		T.eq(d.games.story.done.c2_m1, true, "c2_m1 bleibt erledigt")
		T.check(type(d.games.story.active) == "table" and d.games.story.active.id == "c2_m2", "Story läuft weiter mit c2_m2")
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
			-- 3.x: Pflichtwahl – kein „Später entscheiden“, die Tafel steht, bis gewählt ist (z. B. nach ResetStart wieder)
			g:InClient(p, function()
				mod.OnNotice({ kind = "start", event = "reset" })
				mod.OnSnapshot({ mode = "openworld", start = { pending = true, path = "", choices = choices } })
			end)
			T.eq(mod.IsOpen(), true, "wieder offen (ResetStart)")
			T.eq(gui:FindFirstChild("Later", true), nil, "kein Knopf „Später entscheiden“")
			local later = nil
			for _, x in ipairs(gui:GetDescendants()) do
				if (x:IsA("TextLabel") or x:IsA("TextButton")) and x.Text:find("Später", 1, true) then
					later = x
				end
			end
			T.eq(later, nil, "kein Später-Text auf der Tafel")
			-- große Karten: gezeichnetes Symbol, zwei Zeilen „was du machst“, Kapiteltitel der Story, Name wie gewünscht
			local GC = g:MiniShared("GameConfig")
			for _, typ in ipairs(PATHS) do
				local card = mod.Card(typ)
				local icon = card and card:FindFirstChild("Icon", true)
				T.check(icon ~= nil and #icon:GetChildren() >= 4, typ .. ": gezeichnetes Symbol (Frames)")
				T.check(icon and icon.AbsoluteSize.X >= 60, typ .. ": Symbol groß genug")
				local chapter = card and card:FindFirstChild("Chapter", true)
				T.check(chapter ~= nil and chapter.Visible and chapter.Text == GC.Start.Paths[typ].chapter, typ .. ": Kapiteltitel " .. tostring(chapter and chapter.Text))
				local title = card and card:FindFirstChild("Title", true)
				T.eq(title and title.Text, NAMES[typ], typ .. ": Name")
				local desc = card and card:FindFirstChild("Desc", true)
				T.check(desc ~= nil and desc.Text:find("\n", 1, true) ~= nil, typ .. ": zwei Zeilen Beschreibung")
			end
			-- Tablet/QTE/Panel offen (IsGarageBusy): Tafel weicht kurz, danach ist sie wieder da
			local busy = true
			g:InClient(p, function()
				mod.Build(nil, { UI = MiniUI, Remote = rec, Toast = function() end, IsGarageBusy = function()
					return busy
				end })
				mod.Render()
			end)
			T.eq(mod.IsOpen(), false, "2.4.0-Dialog offen: Tafel weicht")
			busy = false
			g:InClient(p, function()
				mod.Render()
			end)
			T.eq(mod.IsOpen(), true, "danach wieder da")
			-- Handy (alter Weg „Startweg wählen“): Reopen zeigt sie, solange sie offen ist
			local reopened = false
			g:InClient(p, function()
				reopened = mod.Reopen()
			end)
			T.eq(reopened, true, "Reopen zeigt die Startwahl")
			g:InClient(p, function()
				mod.OnSnapshot({ mode = "lobby", start = { pending = true, path = "", choices = choices } })
			end)
			T.eq(mod.IsOpen(), false, "Lobby: verborgen")
			g:InClient(p, function()
				mod.OnSnapshot({ mode = "openworld", start = { pending = true, path = "", choices = choices } })
			end)
			T.eq(mod.IsOpen(), true, "beim nächsten Betreten wieder da")
			T.eq(g:ErrorText(), "", "keine Skriptfehler")
		end
	end },
}
