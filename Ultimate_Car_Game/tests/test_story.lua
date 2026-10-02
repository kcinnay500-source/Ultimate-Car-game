-- Ausbaustufe 4, Meilenstein 7 (Team story): StoryRules (rein) und StoryService im echten Server (H.Garage, eigene
-- Aktionen-Tabelle wie test_tycoon, bis der Integrator MiniService verkabelt). Kapitel 1 bis zum Ende über echte Ereignisse
-- (Kiesplatz-Verkäufe aller Preisstufen inkl. geseedeter Pleite, Werkstatt-Abrechnung über garage_flow, Kontostand),
-- Level-Sperren, einmaliges Abholen, Nebenmissionen mit Tageswechsel und Lieferung, Co-op in der Party, Passiv-Modus,
-- Verlassen/Wiederkommen, Load idempotent.
local DAY = 86400
local NOW = 1760000000 - (1760000000 % DAY) + 3600 -- 01:00 UTC

---------------------------------------------------------------- Verkabelung (wie der Integrator in MiniService)
local function setup(H, opts)
	opts = opts or {}
	opts.placeKind = opts.placeKind or "openworld"
	opts.startTime = opts.startTime or NOW
	local g = H.Garage(opts)
	local SR = g:MiniShared("StoryRules")
	local SS = g:MiniServer("StoryService")
	local MR = g:MiniShared("MiniRules")
	local Event = g:Remote("Event")
	local handlers = {}
	local function emit(p, kind, data)
		if p.player.Parent then
			Event:FireClient(p.player, kind, data)
		end
	end
	local ctx = {
		emit = emit,
		toast = function(p, text)
			emit(p, "toast", text)
		end,
		now = function()
			return g:Now()
		end,
		getSession = function(player)
			return g:Session(player)
		end,
	}
	local fakeApi = {
		now = function()
			return g:Now()
		end,
		toast = function(ms, text)
			ctx.toast(ms.p, text)
		end,
		notice = function(ms, kind, data)
			data = type(data) == "table" and data or {}
			data.kind = kind
			emit(ms.p, "mini_notice", data)
		end,
		dirty = function(ms)
			ms.dirty = true
		end,
		changed = function(ms)
			ms.dirty = true
		end,
		worldChanged = function() end,
		writable = function(ms)
			return ms.p.profile.writable == true
		end,
		alive = function(ms)
			return ms ~= nil and ms.player.Parent ~= nil
		end,
	}
	SS.Register({
		Register = function(name, fn)
			handlers[name] = fn
		end,
	}, fakeApi)
	SS.Init(ctx)
	local S = { g = g, SR = SR, SS = SS, MR = MR, handlers = handlers, sessions = {} }
	function S.join(userId, name)
		-- Rohdatensatz vor dem Beitritt: bis MiniRules.LoadGames StoryRules.ApplyLoad aufruft, lädt der Test
		-- d.games.story selbst aus dem gespeicherten Datensatz (wie der Integrator es verkabelt)
		local raw = g:Record(userId)
		raw = raw and raw.data and raw.data.games or nil
		local pl = g:Join(userId, { name = name })
		g:Advance(1.1)
		g:Send(pl, "hello")
		g:Advance(0.6)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		ms.greeted = true
		if type(raw) == "table" and type(d.games.story) ~= "table" then
			SR.ApplyLoad(d.games, raw, d, g:Now())
		end
		SS.OnJoin(ms, d, g:Now())
		g:Flush()
		table.insert(S.sessions, pl)
		return pl, ms, d
	end
	function S.act(pl, action, data)
		g:Activate()
		local ms = g:MiniState(pl)
		local ok, err = pcall(handlers[action], ms, data or {}, g:D(pl), g:Now())
		g:Flush()
		if not ok then
			error(action .. ": " .. tostring(err))
		end
		return ok
	end
	-- Zeit in Schritten laufen lassen und dabei den Dienst ticken (wie MiniService.Tick)
	function S.tick(seconds, step)
		step = step or 0.5
		local n = math.max(1, math.floor(seconds / step + 0.5))
		for _ = 1, n do
			g:Advance(step)
			for _, pl in ipairs(S.sessions) do
				local ms = g:MiniState(pl)
				if ms and pl.Parent then
					SS.Tick(ms, g:D(pl), g:Now())
				end
			end
		end
		g:Flush()
	end
	function S.leave(pl)
		local ms = g:MiniState(pl)
		if ms then
			SS.OnLeave(ms)
		end
		g:Leave(pl)
		for i, x in ipairs(S.sessions) do
			if x == pl then
				table.remove(S.sessions, i)
				break
			end
		end
	end
	function S.snapshot(pl, full)
		local ms = g:MiniState(pl)
		return SS.SnapshotFields(ms, g:D(pl), g:Now(), full ~= false).story
	end
	function S.offer(pl)
		return SS.Offer(g:MiniState(pl))
	end
	function S.story(pl)
		return g:D(pl).games.story
	end
	-- Zum Kiesplatz (falls die Stadt ihn schon hat), dann warten, bis ein Kunde da ist
	function S.customer(pl)
		local st = g:Find("Workspace.City.Stations.kiesplatz")
		if st then
			g:Teleport(pl, st, Vector3.new(0, 3, 4))
		end
		for _ = 1, 400 do
			if S.offer(pl) then
				return S.offer(pl)
			end
			S.tick(0.5)
		end
		return nil
	end
	-- Verkauf zur Stufe tier an den aktuellen Kunden; liefert den story-Hinweis (sale)
	function S.sell(pl, tier)
		local offer = S.customer(pl)
		assert(offer, "kein Kunde am Kiesplatz")
		local m = g:Mark()
		S.act(pl, "story_sell", { offer = offer.serial, price = tier })
		local list = g:Notices(pl, "story", m)
		for _, n in ipairs(list) do
			if n.event == "sale" then
				return n, offer
			end
		end
		return nil, offer
	end
	-- Nächsten Kunden holen, dessen Wurf die Stufe tier scheitern (fail = true) bzw. gelingen lässt
	function S.customerFor(pl, tier, fail)
		for _ = 1, 40 do
			local offer = S.customer(pl)
			assert(offer, "kein Kunde")
			local chance = offer.tiers[tier].chance
			local ok = tier == 1 or offer.roll < chance
			if ok ~= fail then
				return offer
			end
			-- diesen Kunden günstig abfertigen (sicher), dann den nächsten abwarten
			S.act(pl, "story_sell", { offer = offer.serial, price = 1 })
			S.tick(46)
		end
		error("kein passender Kunde gefunden")
	end
	return S
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, what .. ": keine Fehler: " .. g:ErrorText())
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

return {
	{ "StoryRules rein: Default/Load idempotent, NaN/Grenzen, Kapitel aus done, Konfiguration, Balance ≤ 40 %", function(T, H)
		local g = H.Garage({ noServer = true })
		local SR = g:MiniShared("StoryRules")
		local Cfg = SR.Config()
		T.eq(#Cfg.Chapters, 5, "5 Kapitel")
		for i, ch in ipairs(Cfg.Chapters) do
			T.check(#ch.Missions >= 3 and #ch.Missions <= 5, "Kapitel " .. i .. ": 3–5 Missionen")
			for k, m in ipairs(ch.Missions) do
				T.eq(m.id, "c" .. i .. "_m" .. k, "Missions-Id " .. m.id)
				T.check(type(m.title) == "string" and #m.text > 20, "Texte " .. m.id)
			end
		end
		T.eq(SR.ChapterLevel(1), 1, "Kapitel 1 ab Level 1")
		T.eq(SR.ChapterLevel(2), 5, "Kapitel 2 ab Level 5 (Unlocks story:2)")
		T.eq(SR.ChapterLevel(5), 50, "Kapitel 5 ab Level 50")
		T.check(#Cfg.Side.Pool >= 8, "mindestens 8 Nebenmissionen im Pool")
		T.eq(#Cfg.Side.Legend, 3, "3 Legende-Missionen")
		T.check(#Cfg.Sale.Customers >= 8, "Kundenpool")
		local viol = SR.BalanceCheck()
		T.eq(#viol, 0, "Belohnungen ≤ 40 % der Werkstatt-Cr/Min: " .. table.concat(viol, "; "))
		T.near(SR.WorkshopPerMinute(1), 214, 0.01, "Werkstatt Lv 1")
		T.near(SR.WorkshopPerMinute(15), 1135.5, 0.01, "Werkstatt Lv 15 (interpoliert)")
		-- Default/Load
		local def = SR.Default()
		T.eq(def.chapter, 1, "Default chapter")
		T.eq(def.step, 1, "Default step")
		T.eq(def.active, false, "Default active")
		local nan = 0 / 0
		local raw = {
			chapter = 9, step = -3, done = { c1_m1 = true, c1_m2 = true, c1_m3 = true, c2_m1 = true, bogus = true, c3_m1 = "ja" },
			side = { s_jobs = { n = nan, day = "2026-10-02", claimed = false }, s_wash = { n = 2, day = "gestern", claimed = true },
				l_bays4 = { n = 7, day = "x", claimed = true }, nix = { n = 1 } },
			active = { id = "c2_m2", progress = 99, startedAt = -5, party = 100 },
			sales = { n = 10, best = 20, special = -1, serial = 3.7 }, title = 12,
		}
		local d = { level = 1, money = 0, games = {} }
		local a = SR.Load(raw, d, NOW)
		T.eq(a.chapter, 2, "Kapitel aus done: Kapitel 1 komplett -> 2")
		T.eq(a.step, 2, "Stufe aus done: c2_m1 erledigt -> 2")
		T.eq(a.done.bogus, nil, "unbekannte Mission fällt weg")
		T.eq(a.done.c3_m1, nil, "nur true zählt")
		T.eq(a.side.s_jobs, nil, "NaN-Zähler ohne Abholung fällt weg")
		T.eq(a.side.s_wash.day, "", "ungültiges Datum -> leer")
		T.eq(a.side.l_bays4.day, "legend", "Legende abgeholt")
		T.eq(a.side.l_bays4.n, 0, "Legende ohne Zähler")
		T.eq(a.side.nix, nil, "unbekannte Nebenmission fällt weg")
		T.eq(a.active and a.active.id, "c2_m2", "aktive Mission bleibt (Kapitel passt)")
		T.eq(a.active.progress, 2, "Fortschritt gedeckelt auf das Ziel")
		T.eq(a.active.startedAt, 0, "negativ -> 0")
		T.eq(a.active.party, 8, "party gedeckelt")
		T.eq(a.sales.best, 10, "best ≤ n")
		T.eq(a.sales.special, 0, "negativ -> 0")
		T.eq(a.sales.serial, 3, "serial ganzzahlig")
		T.eq(a.title, "", "Titel nur String")
		local b = SR.Load(a, d, NOW)
		T.check(H.DeepEqual(a, b), "Load idempotent")
		T.check(H.DeepEqual(SR.Load(nil, d, NOW), SR.Default()), "Load(nil) = Default")
		-- aktive Mission eines anderen Kapitels oder erledigt -> verworfen
		local c = SR.Load({ done = { c1_m1 = true }, active = { id = "c2_m1", progress = 1 } }, d, NOW)
		T.eq(c.active, false, "aktive Mission aus fremdem Kapitel verworfen")
		local e = SR.Load({ done = { c1_m1 = true }, active = { id = "c1_m1", progress = 1 } }, d, NOW)
		T.eq(e.active, false, "erledigte Mission nicht aktiv")
		-- ApplyDefault/ApplyLoad für MiniRules
		local gm = {}
		SR.ApplyDefault(gm)
		T.check(type(gm.story) == "table" and gm.story.chapter == 1, "ApplyDefault")
		SR.ApplyLoad(gm, { story = raw }, d, NOW)
		T.eq(gm.story.chapter, 2, "ApplyLoad liest raw.story")
		-- Tagesauswahl deterministisch und verschieden
		local ids = SR.DailyIds("2026-10-02")
		T.eq(#ids, 3, "3 Nebenmissionen je Tag")
		T.check(ids[1] ~= ids[2] and ids[2] ~= ids[3] and ids[1] ~= ids[3], "drei verschiedene")
		T.check(H.DeepEqual(ids, SR.DailyIds("2026-10-02")), "deterministisch")
		-- Kiesplatz: Angebot aus Seed deterministisch, Wurf 0..1, Stufenpreise steigen
		local dd = { level = 1, money = 0, games = { story = SR.Default() } }
		local o1, o2 = SR.NextSale(dd, "1:1", 1), SR.NextSale(dd, "1:1", 1)
		T.check(H.DeepEqual(o1, o2), "NextSale deterministisch")
		T.check(o1.roll >= 0 and o1.roll < 1, "Wurf 0..1")
		T.check(o1.tiers[1].profit < o1.tiers[2].profit and o1.tiers[2].profit < o1.tiers[3].profit, "Gewinn steigt je Stufe")
		T.eq(o1.tiers[1].chance, 1, "Stufe 1 sicher")
		local o10 = SR.NextSale({ level = 10, money = 0, games = { story = SR.Default() } }, "1:1", 10)
		T.check(o10.tiers[1].profit > o1.tiers[1].profit, "Level-Skalierung")
		T.eq(o1.special, false, "Kapitel 1: kein Sondermodell-Kunde")
		local d4 = { level = 30, money = 0, games = { story = SR.Load({ done = { c1_m1 = true, c1_m2 = true, c1_m3 = true, c2_m1 = true, c2_m2 = true, c2_m3 = true, c3_m1 = true, c3_m2 = true, c3_m3 = true, c3_m4 = true } }, nil, NOW) } }
		d4.games.story.sales.serial = 2
		T.eq(d4.games.story.chapter, 4, "Kapitel 4")
		local o4 = SR.NextSale(d4, "x", 30)
		T.eq(o4.special, true, "Kapitel 4: jeder dritte Kunde ist Sammler")
		-- Co-op: nur geteilte Arten, nur dieselbe aktive Mission
		T.eq(SR.CoopShared(SR.Mission("c1_m1")), true, "sell geteilt")
		T.eq(SR.CoopShared(SR.Mission("c1_m3")), false, "own nicht geteilt")
		T.eq(SR.CoopShared(SR.SideDef("l_jobs100")), false, "Legende nicht geteilt")
	end },

	{ "Kapitel 1 bis zum Ende: Kiesplatz (alle Stufen, geseedete Pleite), Werkstatt-Abrechnung, Kontostand; nur einmal abholen; Kapitel 2 ab Level 5", function(T, H)
		local S = setup(H)
		local g, SR, SS = S.g, S.SR, S.SS
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local pl, ms, d = S.join(7001, "Kim")
		T.eq(ms.p.mode, "openworld", "Open World")
		local snap = S.snapshot(pl)
		T.eq(snap.chapter, 1, "Snapshot Kapitel 1")
		T.eq(snap.step, 1, "Stufe 1")
		T.eq(snap.active, false, "nichts aktiv")
		T.eq(snap.next, "c1_m1", "nächste Mission")
		T.check(type(snap.missions) == "table" and #snap.missions == 3 and snap.missions[1].startable == true, "Missionsliste im vollen Snapshot")
		T.eq(S.snapshot(pl, false).missions, nil, "Missionsliste nur bei full")
		T.check(#snap.side == 1 + 3, "Level 1: nur die immer machbare Nebenmission (s_jobs) + 3 Legende")
		T.eq(snap.side[1].id, "s_jobs", "Level 1: s_jobs")
		T.check(#snap.intro > 50 and snap.chapterTitle == "Der Kiesplatz", "Intro/Titel")
		-- falsche Reihenfolge / unbekannt
		local m = g:Mark()
		S.act(pl, "story_start", { id = "c1_m2" })
		T.check(g:HasToast(pl, "der Reihe nach", m), "nur die aktuelle Stufe startbar")
		S.act(pl, "story_start", { id = "gibtsnicht" })
		T.check(g:HasToast(pl, "gibt es nicht", m), "unbekannte Mission")
		-- Verkaufen ohne aktive Mission geht (Einnahme), zählt aber nicht
		S.act(pl, "story_claim", { id = "c1_m1" })
		T.check(g:HasToast(pl, "Starte die Mission", m), "Abholen ohne Start")
		m = g:Mark()
		S.act(pl, "story_start", { id = "c1_m1" })
		T.check(g:HasToast(pl, "Mission gestartet", m), "Start-Toast")
		local started = g:Notices(pl, "story", m)
		T.check(#started == 1 and started[1].event == "started" and started[1].mission == "c1_m1", "story-Hinweis started")
		T.eq(S.story(pl).active.id, "c1_m1", "aktiv")
		-- Kunde kommt nach FirstOfferDelay; Snapshot zeigt das Angebot ohne den Wurf
		local offer = S.customer(pl)
		T.check(offer ~= nil, "Kunde da")
		snap = S.snapshot(pl)
		T.check(snap.sale and snap.sale.offer == offer.serial and #snap.sale.tiers == 3 and snap.sale.roll == nil, "Snapshot sale ohne Wurf")
		T.check(snap.sale.tiers[3].profit > snap.sale.tiers[1].profit, "erwartete Gewinne je Stufe")
		-- falsche Angebotsnummer / falsche Stufe
		m = g:Mark()
		S.act(pl, "story_sell", { offer = offer.serial + 5, price = 1 })
		T.check(g:HasToast(pl, "schon weg", m), "falsches Angebot")
		S.act(pl, "story_sell", { offer = offer.serial, price = 7 })
		T.check(g:HasToast(pl, "Preisstufe", m), "falsche Stufe")
		T.eq(S.story(pl).sales.n, 0, "noch kein Verkauf")
		-- Stufe 1: sicher
		local money = d.money
		local n1 = S.sell(pl, 1)
		T.check(n1 and n1.sold == true and n1.tier == 1, "Stufe 1 verkauft")
		T.check(d.money >= money + offer.tiers[1].profit, "Gewinn Stufe 1")
		T.eq(S.story(pl).active.progress, 1, "Fortschritt 1/3")
		T.eq(S.offer(pl), false, "Kunde weg")
		T.check(S.snapshot(pl).saleIn > 40, "nächster Kunde in ~45 s")
		local missionNotices = g:Notices(pl, "mission")
		T.check(#missionNotices >= 1 and missionNotices[#missionNotices].progress == 1, "mission-Hinweis")
		S.tick(10)
		T.eq(S.offer(pl), false, "noch kein neuer Kunde")
		S.tick(36)
		-- Stufe 3 mit Pleite (Wurf ≥ Chance): kein Geld, kein Fortschritt, derselbe Kunde antwortet nicht noch einmal
		local bad = S.customerFor(pl, 3, true)
		money = d.money
		local sales = S.story(pl).sales.n
		local progress = S.story(pl).active.progress
		m = g:Mark()
		S.act(pl, "story_sell", { offer = bad.serial, price = 3 })
		local fail = g:Notices(pl, "story", m)[1]
		T.check(fail and fail.event == "sale" and fail.sold == false, "Verhandlung geplatzt (Seed)")
		T.eq(d.money, money, "kein Geld bei Pleite")
		T.eq(S.story(pl).sales.n, sales, "kein Verkauf gezählt")
		T.eq(S.story(pl).active.progress, progress, "kein Fortschritt")
		T.eq(S.offer(pl), false, "Kunde weg nach Pleite")
		S.act(pl, "story_sell", { offer = bad.serial, price = 1 })
		T.eq(d.money, money, "derselbe Kunde ist weg (kein zweiter Versuch)")
		S.tick(21)
		-- Stufe 3 mit Erfolg
		local good = S.customerFor(pl, 3, false)
		money = d.money
		progress = S.story(pl).active.progress
		local n3 = S.sell(pl, 3)
		T.check(n3 and n3.sold == true and n3.tier == 3, "Stufe 3 verkauft")
		T.check(d.money >= money + good.tiers[3].profit, "Gewinn Stufe 3")
		T.eq(S.story(pl).active.progress, math.min(3, progress + 1), "Fortschritt +1 (Deckel 3; Zwischenverkäufe zählten schon)")
		T.check(S.story(pl).sales.best >= 1, "Bestpreis gezählt")
		-- Rest mit Stufe 2 (erfolgreich) bis 3/3
		local guard = 0
		while S.story(pl).active and S.story(pl).active.progress < 3 and guard < 10 do
			guard += 1
			S.tick(46)
			S.customerFor(pl, 2, false)
			local n2 = S.sell(pl, 2)
			T.check(n2 and n2.sold == true, "Stufe 2 verkauft")
		end
		T.eq(S.story(pl).active.progress, 3, "3/3")
		T.check(g:HasToast(pl, "Mission geschafft"), "Erfüllt-Toast")
		snap = S.snapshot(pl)
		T.check(snap.active and snap.active.claimable == true and snap.active.done == false, "claimable")
		-- Abholen: Credits + XP, nur einmal
		money = d.money
		local xp = d.xp
		m = g:Mark()
		S.act(pl, "story_claim", { id = "c1_m1" })
		local claimed = g:Notices(pl, "story", m)[1]
		T.check(claimed and claimed.event == "claimed" and claimed.mission == "c1_m1" and claimed.credits == 150, "claimed-Hinweis")
		T.check(d.money >= money + 150, "150 Credits")
		T.check(d.xp > xp or d.level > 1, "XP")
		T.eq(S.story(pl).done.c1_m1, true, "erledigt")
		T.eq(S.story(pl).active, false, "nicht mehr aktiv")
		T.eq(S.story(pl).step, 2, "Stufe 2")
		T.eq(d.games.stats.missionsDone, 1, "missionsDone")
		money = d.money
		S.act(pl, "story_claim", { id = "c1_m1" })
		T.eq(d.money, money, "zweites Abholen bringt nichts")
		S.act(pl, "story_start", { id = "c1_m1" })
		T.check(g:HasToast(pl, "schon geschafft", m), "erledigte Mission nicht neu startbar")
		-- c1_m2: echte Werkstatt-Abrechnung (Integrator: OnEvent "settle" + OnStat jobsDone aus MiniService.OnSettled)
		S.act(pl, "story_start", { id = "c1_m2" })
		T.eq(S.story(pl).active.id, "c1_m2", "c1_m2 aktiv")
		local jobs = d.games.stats.jobsDone
		local receipt = Flow.CompleteInspection(T, g, pl)
		T.check(receipt ~= nil, "Auftrag abgerechnet")
		T.eq(d.games.stats.jobsDone, jobs + 1, "jobsDone +1")
		SS.OnStat(ms, d, "jobsDone", 1)
		SS.OnEvent(ms, d, "settle")
		T.eq(S.story(pl).active.progress, 1, "settle gezählt")
		S.act(pl, "story_claim", { id = "c1_m2" })
		T.eq(S.story(pl).done.c1_m2, true, "c1_m2 abgeholt")
		-- c1_m3: Kontostand ≥ 2.500 (Startgeld + Belohnungen reichen nicht: Bedingung wird erst im Tick erfüllt)
		T.check(d.money < 2500, "Kontostand noch unter 2.500 (" .. tostring(d.money) .. ")")
		m = g:Mark()
		S.act(pl, "story_start", { id = "c1_m3" })
		S.tick(1.5)
		snap = S.snapshot(pl)
		T.check(snap.active and snap.active.progress < 2500 and not snap.active.claimable, "Bedingung noch offen")
		S.MR.AddMoney(d, 2500 - d.money)
		S.tick(1.5)
		snap = S.snapshot(pl)
		T.check(snap.active and snap.active.progress == 2500 and snap.active.claimable, "Bedingung im Tick erfüllt")
		money = d.money
		S.act(pl, "story_claim", { id = "c1_m3" })
		local done = g:Notices(pl, "story", m)
		local last = done[#done]
		T.check(last and last.event == "claimed" and last.chapterDone == true and last.nextChapter == 2 and last.nextLevel == 5, "Kapitel 1 abgeschlossen")
		T.check(g:HasToast(pl, "Kapitel 1 abgeschlossen", m), "Kapitel-Toast")
		T.check(d.money >= money + 200, "200 Credits")
		T.eq(S.story(pl).chapter, 2, "Kapitel 2")
		T.eq(S.story(pl).step, 1, "Stufe 1")
		-- Kapitel 2 erst ab Level 5
		snap = S.snapshot(pl)
		T.eq(snap.locked, d.level < 5, "locked je Level")
		if d.level < 5 then
			m = g:Mark()
			S.act(pl, "story_start", { id = "c2_m1" })
			T.check(g:HasToast(pl, "ab Level 5", m), "Kapitel 2 gesperrt")
			T.eq(S.story(pl).active, false, "nicht gestartet")
			d.level = 5
			S.act(pl, "story_start", { id = "c2_m1" })
			T.eq(S.story(pl).active and S.story(pl).active.id, "c2_m1", "ab Level 5 startbar")
		end
		-- Verlassen mitten im Vorgang und Wiederkommen: aktive Mission und Verkäufe bleiben
		local salesN = S.story(pl).sales.n
		S.leave(pl)
		g:Advance(1)
		local pl2, _, d2 = S.join(7001, "Kim")
		T.eq(d2.games.story.chapter, 2, "nach Rejoin Kapitel 2")
		T.eq(d2.games.story.done.c1_m3, true, "done bleibt")
		T.eq(d2.games.story.sales.n, salesN, "Verkäufe bleiben")
		if d2.level >= 5 then
			T.eq(d2.games.story.active and d2.games.story.active.id, "c2_m1", "aktive Mission bleibt")
		end
		noErrors(T, g, "Kapitel 1")
	end },

	{ "Level-Sperren und Kapitel 2/3: stat-Zähler ab Start, Hebebühne als Bedingung, Ereignisse mit Zeit, build aus d.games.ow", function(T, H)
		local S = setup(H, { level = 20 })
		local g, SR, SS = S.g, S.SR, S.SS
		g:SeedLevel(7101, 20, function(data)
			data.games = { story = { done = { c1_m1 = true, c1_m2 = true, c1_m3 = true } } }
		end)
		local pl, ms, d = S.join(7101, "Ravi")
		T.eq(d.level, 20, "Level 20")
		T.eq(S.story(pl).chapter, 2, "Kapitel 2 aus done")
		-- stat: nur Zuwachs seit dem Start zählt
		d.games.stats.jobsDone = 40
		S.act(pl, "story_start", { id = "c2_m1" })
		T.eq(S.story(pl).active.progress, 0, "alte Aufträge zählen nicht")
		SS.OnStat(ms, d, "jobsDone", 2)
		SS.OnStat(ms, d, "quizCorrect", 2)
		T.eq(S.story(pl).active.progress, 2, "2 neue Aufträge")
		SS.OnStat(ms, d, "jobsDone", 10)
		T.eq(S.story(pl).active.progress, 5, "gedeckelt auf 5")
		S.act(pl, "story_claim", { id = "c2_m1" })
		T.eq(S.story(pl).done.c2_m1, true, "c2_m1")
		-- own bays: Bedingung später erfüllt -> Tick meldet
		S.act(pl, "story_start", { id = "c2_m2" })
		S.tick(1.5)
		T.eq(S.snapshot(pl).active.claimable, false, "noch eine Bühne")
		d.bays = 2
		local m = g:Mark()
		S.tick(1.5)
		local n = g:Notices(pl, "mission", m)
		T.check(#n >= 1 and n[#n].id == "c2_m2" and n[#n].done == true, "Tick meldet erfüllte Bedingung")
		S.act(pl, "story_claim", { id = "c2_m2" })
		T.eq(S.story(pl).done.c2_m2, true, "c2_m2")
		-- stat quizCorrect (Quiz ab Level 4 – passt zu Kapitel 2 ab 5)
		S.act(pl, "story_start", { id = "c2_m3" })
		SS.OnStat(ms, d, "quizCorrect", 4)
		SS.OnStat(ms, d, "quizCorrect", 6)
		T.eq(S.story(pl).active.progress, 10, "zehn Quizfragen gezählt")
		m = g:Mark()
		S.act(pl, "story_claim", { id = "c2_m3" })
		T.check(g:HasToast(pl, "Kapitel 2 abgeschlossen", m), "Kapitel 2 fertig")
		T.eq(S.story(pl).chapter, 3, "Kapitel 3 (Level 20 ≥ 15)")
		-- Kapitel 3: build aus d.games.ow, car_bought, Auktion (eins von zwei Ereignissen)
		S.act(pl, "story_start", { id = "c3_m1" })
		S.tick(1.5)
		T.eq(S.snapshot(pl).active.progress, 0, "kein Autohaus")
		d.games.ow = { buildings = { autohaus = { stage = 1, readyAt = 0 } }, passive = false, lastPassiveAt = 0 }
		SS.OnEvent(ms, d, "ow_built:autohaus")
		S.tick(1.5)
		T.eq(S.snapshot(pl).active.claimable, true, "Autohaus Stufe 1 erkannt")
		S.act(pl, "story_claim", { id = "c3_m1" })
		S.act(pl, "story_start", { id = "c3_m2" })
		SS.OnEvent(ms, d, "car_bought", { model = "komet" })
		S.act(pl, "story_claim", { id = "c3_m2" })
		-- event track_finish (beliebige Zeit; Teststrecke ab 8, eigenes Auto aus c3_m2)
		S.act(pl, "story_start", { id = "c3_m3" })
		SS.OnEvent(ms, d, "track_finish", { time = 123.4 })
		T.eq(S.story(pl).active.progress, 1, "Zeitfahren gezählt")
		S.act(pl, "story_claim", { id = "c3_m3" })
		S.act(pl, "story_start", { id = "c3_m4" })
		SS.OnEvent(ms, d, "auction_lost")
		T.eq(S.story(pl).active.progress, 0, "fremdes Ereignis zählt nicht")
		SS.OnEvent(ms, d, "auction_consigned")
		T.eq(S.story(pl).active.progress, 1, "Einliefern zählt")
		m = g:Mark()
		S.act(pl, "story_claim", { id = "c3_m4" })
		T.eq(S.story(pl).chapter, 4, "Kapitel 4")
		T.check(g:HasToast(pl, "ab Level 30", m), "Kapitel 4 ab Level 30")
		T.eq(S.snapshot(pl).locked, true, "locked")
		S.act(pl, "story_start", { id = "c4_m1" })
		T.eq(S.story(pl).active, false, "gesperrt")
		T.eq(d.games.stats.missionsDone, 7, "7 Missionen")
		noErrors(T, g, "Kapitel 2/3")
	end },

	{ "Kapitel 5: Bestpreis-Verkäufe, Sondermodell-Kunden, Traumwagen, Titel und Story-Ende", function(T, H)
		local S = setup(H, { level = 60 })
		local g, SR, SS = S.g, S.SR, S.SS
		local GC = g:MiniShared("GameConfig")
		g:SeedLevel(7201, 60, function(data)
			local done = {}
			for ci = 1, 4 do
				for _, m in ipairs(GC.Story.Chapters[ci].Missions) do
					done[m.id] = true
				end
			end
			data.games = { story = { done = done } }
		end)
		local pl, ms, d = S.join(7201, "Nadia")
		T.eq(S.story(pl).chapter, 5, "Kapitel 5")
		d.games.ow = { buildings = { produktion = { stage = 4, readyAt = 0 } }, passive = false, lastPassiveAt = 0 }
		S.act(pl, "story_start", { id = "c5_m1" })
		S.tick(1.5)
		S.act(pl, "story_claim", { id = "c5_m1" })
		T.eq(S.story(pl).done.c5_m1, true, "Produktion Stufe 4")
		-- Bestpreis: nur Stufe 3 zählt; Sondermodell-Kunden kommen (jeder dritte), Gewinn ×3 und Level-Faktor
		S.act(pl, "story_start", { id = "c5_m2" })
		S.customerFor(pl, 2, false)
		S.sell(pl, 2)
		T.eq(S.story(pl).active.progress, 0, "Stufe 2 zählt nicht als Bestpreis")
		S.tick(46)
		local good = S.customerFor(pl, 3, false)
		local money = d.money
		S.sell(pl, 3)
		T.eq(S.story(pl).active.progress, 1, "Bestpreis gezählt")
		T.check(d.money - money >= good.tiers[3].profit, "Gewinn (Level-Faktor, evtl. Prestige)")
		T.check(good.tiers[3].profit >= 130 * 3 - 1, "Level 60: Faktor ×3 (gedeckelt)")
		local sawSpecial = false
		for _ = 1, 4 do
			S.tick(46)
			local o = S.customer(pl)
			if o and o.special then
				sawSpecial = true
			end
			S.act(pl, "story_sell", { offer = o.serial, price = 1 })
		end
		T.check(sawSpecial, "Sondermodell-Kunde erschienen")
		T.check(S.story(pl).sales.special >= 1, "Sondermodell-Verkauf gezählt")
		-- Traumwagen: Auto in der Garage
		S.story(pl).active.progress = 10 -- Rest der Bestpreise abkürzen (Regelpfad oben geprüft)
		S.act(pl, "story_claim", { id = "c5_m2" })
		S.act(pl, "story_start", { id = "c5_m3" })
		S.tick(1.5)
		T.eq(S.snapshot(pl).active.claimable, false, "kein Traumwagen")
		local CR = g:MiniShared("CarRules")
		T.check(CR.GrantModel(d, "aureon", g:Now()) ~= nil, "Aureon in der Garage")
		S.tick(1.5)
		local m = g:Mark()
		S.act(pl, "story_claim", { id = "c5_m3" })
		local n = g:Notices(pl, "story", m)
		local last = n[#n]
		T.check(last and last.event == "claimed" and last.finished == true and last.titleReward == "Mega-Verkäufer", "Story-Ende")
		T.check(g:HasToast(pl, "Mega-Verkäufer", m), "Titel-Toast")
		T.eq(S.story(pl).title, "Mega-Verkäufer", "Titel gespeichert")
		local snap = S.snapshot(pl)
		T.eq(snap.finished, true, "finished")
		T.eq(snap.next, false, "keine nächste Mission")
		T.eq(snap.titleEarned, "Mega-Verkäufer", "Snapshot Titel")
		T.eq(#snap.chapters, 5, "Kapitelübersicht")
		T.eq(snap.chapters[5].done, true, "Kapitel 5 fertig")
		S.act(pl, "story_start", { id = "c5_m3" })
		T.check(g:HasToast(pl, "ganze Story geschafft", m), "nach dem Ende nichts mehr startbar")
		noErrors(T, g, "Kapitel 5")
	end },

	{ "Nebenmissionen: Tagesauswahl, Zähler, Abholen einmal, Tageslimit, Reset am nächsten Tag, Legende, Lieferung mit eigenem Auto", function(T, H)
		local S = setup(H, { level = 12 })
		local g, SR, SS = S.g, S.SR, S.SS
		-- einen Tag wählen, an dem die Lieferung und eine Statistik-Mission dabei sind
		local day0 = NOW - 3600
		local dayAt
		for k = 0, 400 do
			local ids = SR.DailyIds(SR.DayKey(day0 + k * DAY))
			local hasDelivery, hasJobs = false, false
			for _, id in ipairs(ids) do
				if id == "s_delivery" then
					hasDelivery = true
				end
				if id == "s_jobs" then
					hasJobs = true
				end
			end
			if hasDelivery and hasJobs then
				dayAt = day0 + k * DAY + 3600
				break
			end
		end
		T.check(dayAt ~= nil, "Tag mit Lieferung + Aufträgen gefunden")
		g:AdvanceTo(dayAt)
		local pl, ms, d = S.join(7301, "Ola")
		local snap = S.snapshot(pl)
		local byId = {}
		for _, v in ipairs(snap.side) do
			byId[v.id] = v
		end
		T.check(byId.s_delivery and byId.s_jobs and byId.l_jobs100 and byId.l_bays4 and byId.l_equipment, "Tagesauswahl + Legende im Snapshot")
		T.eq(byId.s_jobs.credits, math.floor(150 * (1 + 0.03 * 11) + 0.5), "Credits mit Level-Skalierung")
		-- Zähler über OnStat, Abholen einmal
		SS.OnStat(ms, d, "jobsDone", 2)
		T.eq(S.story(pl).side.s_jobs.n, 2, "2/3")
		local m = g:Mark()
		S.act(pl, "side_claim", { id = "s_jobs" })
		T.check(g:HasToast(pl, "Noch nicht geschafft", m), "zu früh")
		SS.OnStat(ms, d, "jobsDone", 1)
		T.check(g:HasToast(pl, "Nebenmission geschafft", m), "Erfüllt-Toast")
		local money = d.money
		S.act(pl, "side_claim", { id = "s_jobs" })
		T.check(d.money >= money + byId.s_jobs.credits, "Credits der Nebenmission")
		T.eq(S.story(pl).side.s_jobs.claimed, true, "abgeholt")
		money = d.money
		S.act(pl, "side_claim", { id = "s_jobs" })
		T.eq(d.money, money, "nur einmal")
		S.act(pl, "side_claim", { id = "s_wash" })
		T.check(g:HasToast(pl, "gibt es heute nicht", m) or byId.s_wash ~= nil, "nicht in der Tagesauswahl")
		T.eq(d.games.stats.missionsDone, 1, "missionsDone zählt Nebenmissionen")
		-- Lieferung: Route in der Stadt, eigenes Auto am Start, dann am Ziel
		g:Activate()
		local city = g:Find("Workspace.City")
		-- Die Stadt aus tools/worldgen bringt City.Missions.Delivery_1..3 mit (Weltteam); fehlt sie, baut der Test eine Route
		local missions = city:FindFirstChild("Missions")
		local start, finish
		if missions and missions:FindFirstChild("Delivery_1") then
			local route = missions.Delivery_1
			for _, x in ipairs(route:GetChildren()) do
				if x:IsA("BasePart") and x:GetAttribute("Role") == "start" then
					start = x
				elseif x:IsA("BasePart") and x:GetAttribute("Role") == "end" then
					finish = x
				end
			end
		else
			missions = Instance.new("Folder")
			missions.Name = "Missions"
			missions.Parent = city
			local route = Instance.new("Model")
			route.Name = "Delivery_1"
			route.Parent = missions
			start = Instance.new("Part")
			start.Name = "Start"
			start.Anchored = true
			start.Size = Vector3.new(12, 1, 12)
			start.CFrame = CFrame.new(120, 0.5, 60)
			start:SetAttribute("Role", "start")
			start:SetAttribute("Delivery", 1)
			start.Parent = route
			finish = Instance.new("Part")
			finish.Name = "Ziel"
			finish.Anchored = true
			finish.Size = Vector3.new(12, 1, 12)
			finish.CFrame = CFrame.new(-150, 0.5, -80)
			finish:SetAttribute("Role", "end")
			finish:SetAttribute("Delivery", 1)
			finish.Parent = route
		end
		T.check(start ~= nil and finish ~= nil, "Lieferroute 1 mit Start und Ziel (City.Missions.Delivery_1)")
		local CR = g:MiniShared("CarRules")
		local car = CR.GrantModel(d, "komet", g:Now())
		T.check(car ~= nil, "Auto in der Garage")
		T.eq(g:Act(pl, "mini_car_spawn", { id = car.id, at = "workshop", rid = 1 }), "ok", "Auto gespawnt")
		local model = g.env.workspace:FindFirstChild("PlayerCars") and g.env.workspace.PlayerCars:FindFirstChild("Car_7301")
		T.check(model ~= nil, "Auto unter PlayerCars")
		local chassis = model and model:FindFirstChild("Chassis")
		T.check(chassis ~= nil, "Chassis")
		-- Figur an den Start stellen: ohne Auto zählt nichts
		g:Teleport(pl, start, Vector3.new(0, 3, 0))
		S.tick(6)
		T.eq(SS.Delivery(ms), false, "Figur ohne Auto startet keine Lieferung")
		chassis.CFrame = start.CFrame * CFrame.new(0, 2, 0)
		m = g:Mark()
		S.tick(6)
		local run = SS.Delivery(ms)
		T.check(type(run) == "table" and run.n == 1, "Lieferung gestartet")
		T.check(g:HasToast(pl, "Lieferung 1 gestartet", m), "Start-Toast")
		chassis.CFrame = finish.CFrame * CFrame.new(0, 2, 0)
		S.tick(1)
		T.eq(SS.Delivery(ms), false, "Lieferung beendet")
		T.check(g:HasToast(pl, "abgeliefert", m), "Ziel-Toast")
		T.eq(S.story(pl).side.s_delivery.n, 1, "Lieferung gezählt")
		local n = g:Notices(pl, "mission", m)
		T.check(#n >= 1 and n[#n].id == "s_delivery" and n[#n].done == true and n[#n].side == true, "mission-Hinweis (side)")
		S.act(pl, "side_claim", { id = "s_delivery" })
		T.eq(S.story(pl).side.s_delivery.claimed, true, "Lieferung abgeholt")
		-- erledigt: keine weitere Lieferung mehr
		chassis.CFrame = start.CFrame * CFrame.new(0, 2, 0)
		S.tick(6)
		T.eq(SS.Delivery(ms), false, "ohne offene Lieferaufgabe startet nichts")
		-- Zeitlimit
		d.games.story.side.s_delivery = nil
		S.tick(6)
		T.check(type(SS.Delivery(ms)) == "table", "wieder gestartet")
		chassis.CFrame = CFrame.new(0, 2, 0) -- unterwegs, weder Start noch Ziel
		S.tick(S.SR.Config().Side.Delivery.TimeLimit + 2)
		T.eq(SS.Delivery(ms), false, "abgelaufen")
		T.check(g:HasToast(pl, "zu lange gedauert"), "Ablauf-Toast")
		T.eq((S.story(pl).side.s_delivery or { n = 0 }).n, 0, "nicht gezählt")
		-- Legende: absoluter Wert aus dem Profil, einmal abholbar, bleibt über den Tageswechsel
		d.games.stats.jobsDone = 100
		m = g:Mark()
		S.tick(1.5)
		T.check(g:HasToast(pl, "Werkstatt-Legende: 100 Aufträge", m), "Legende erfüllt gemeldet")
		money = d.money
		S.act(pl, "side_claim", { id = "l_jobs100" })
		T.check(d.money >= money + 5000, "5.000 Credits Legende")
		money = d.money
		S.act(pl, "side_claim", { id = "l_jobs100" })
		T.eq(d.money, money, "Legende nur einmal")
		-- Tageslimit: 3 Abholungen je Tag (zwei schon), dritte geht, vierte nicht
		local third
		for _, id in ipairs(SR.DailyIds(SR.DayKey(g:Now()))) do
			if id ~= "s_jobs" and id ~= "s_delivery" then
				third = id
			end
		end
		local def3 = SR.SideDef(third)
		d.games.story.side[third] = { n = def3.target, day = SR.DayKey(g:Now()), claimed = false }
		S.act(pl, "side_claim", { id = third })
		T.eq(d.games.story.side[third].claimed, true, "dritte Nebenmission abgeholt")
		-- Nächster Tag: neue Auswahl, Zähler weg, Legende bleibt abgeholt
		g:Advance(DAY)
		S.tick(1)
		T.eq(d.games.story.side.s_jobs, nil, "Tageseintrag weg")
		T.eq(d.games.story.side.l_jobs100.claimed, true, "Legende bleibt")
		T.eq(d.games.story.side.l_jobs100.day, "legend", "Legende-Markierung")
		snap = S.snapshot(pl)
		local todays = SR.DailyIds(SR.DayKey(g:Now()))
		T.eq(snap.side[1].id, todays[1], "neue Tagesauswahl im Snapshot")
		for _, v in ipairs(snap.side) do
			if not v.legend then
				T.eq(v.progress, 0, "Zähler zurückgesetzt: " .. v.id)
			end
		end
		noErrors(T, g, "Nebenmissionen")
	end },

	{ "Co-op: Party teilt Fortschritt derselben Mission; nicht an Passive, nicht an Fremde, nicht bei eigenen Bedingungen", function(T, H)
		local S = setup(H, { placeKind = "openworld" })
		local g, SR, SS = S.g, S.SR, S.SS
		local LS = g:MiniServer("LobbyService")
		local a, msA, dA = S.join(7401, "Anna")
		local b, msB, dB = S.join(7402, "Ben")
		local c, msC, dC = S.join(7403, "Cem")
		T.eq(g:Act(a, "party_create", { rid = 1 }), "ok", "party_create")
		local party = LS.PartyOf(a)
		T.check(party ~= nil, "Party")
		g:Advance(0.5)
		T.eq(g:Act(b, "party_join", { code = party.code, rid = 2 }), "ok", "Ben tritt bei")
		S.act(a, "story_start", { id = "c1_m1" })
		S.act(b, "story_start", { id = "c1_m1" })
		S.act(c, "story_start", { id = "c1_m1" })
		T.eq(S.story(a).active.party, 2, "Party-Größe beim Start")
		-- Anna verkauft -> Ben zählt mit, Cem nicht
		local m = g:Mark()
		local moneyB = dB.money
		S.customerFor(a, 1, false)
		S.sell(a, 1)
		T.eq(S.story(a).active.progress, 1, "Anna 1/3")
		T.eq(S.story(b).active.progress, 1, "Ben 1/3 (Co-op)")
		T.eq(S.story(c).active.progress, 0, "Cem 0/3 (keine Party)")
		T.eq(dB.money, moneyB, "Ben bekommt kein Geld vom Verkauf")
		local nb = g:Notices(b, "mission", m)
		T.check(#nb == 1 and nb[1].coop == true and nb[1].from == "Anna", "Ben: Co-op-Hinweis")
		T.check(g:HasToast(b, "Party: Anna", m), "Ben: Co-op-Toast")
		-- Ben verkauft -> Anna zählt mit (beide Richtungen)
		S.tick(2)
		S.customerFor(b, 1, false)
		S.sell(b, 1)
		T.eq(S.story(a).active.progress, 2, "Anna 2/3")
		T.eq(S.story(b).active.progress, 2, "Ben 2/3")
		-- Ben passiv: Annas Fortschritt kommt nicht mehr an
		T.eq(g:Act(b, "lobby_settings", { single = false, passive = true, beginner = false, rid = 3 }), "ok", "Ben passiv")
		S.tick(46)
		S.customerFor(a, 1, false)
		S.sell(a, 1)
		T.eq(S.story(a).active.progress, 3, "Anna 3/3")
		T.eq(S.story(b).active.progress, 2, "Ben bleibt bei 2 (passiv)")
		T.eq(g:Act(b, "lobby_settings", { single = false, passive = false, beginner = false, rid = 4 }), "ok", "Ben aktiv")
		-- Belohnung holt jeder selbst: Ben erst, wenn er selbst fertig ist
		local moneyA = dA.money
		S.act(a, "story_claim", { id = "c1_m1" })
		T.check(dA.money >= moneyA + 150, "Anna holt ab")
		S.act(b, "story_claim", { id = "c1_m1" })
		T.eq(S.story(b).done.c1_m1, nil, "Ben kann noch nicht abholen")
		-- Verschiedene aktive Missionen: nichts geteilt (Anna bei c1_m2, Ben noch c1_m1)
		S.act(a, "story_start", { id = "c1_m2" })
		SS.OnEvent(msA, dA, "settle")
		T.eq(S.story(a).active.progress, 1, "Anna settle")
		T.eq(S.story(b).active.progress, 2, "Ben unverändert (andere Mission)")
		-- Ben verkauft, Anna hat c1_m2 -> kein Übertrag; Ben wird fertig
		S.tick(2)
		S.customerFor(b, 1, false)
		S.sell(b, 1)
		T.eq(S.story(b).active.progress, 3, "Ben 3/3")
		T.eq(S.story(a).active.progress, 1, "Anna bleibt bei c1_m2 1/1")
		S.act(b, "story_claim", { id = "c1_m1" })
		T.eq(S.story(b).done.c1_m1, true, "Ben holt selbst ab")
		-- Party verlassen: kein Übertrag mehr
		S.act(a, "story_claim", { id = "c1_m2" })
		S.act(b, "story_start", { id = "c1_m2" })
		T.eq(g:Act(b, "party_leave", { rid = 5 }), "ok", "Ben verlässt die Party")
		S.act(a, "story_start", { id = "c1_m3" })
		SS.OnEvent(msB, dB, "settle")
		T.eq(S.story(b).active.progress, 1, "Ben settle")
		T.eq(S.story(a).active.id, "c1_m3", "Anna bei c1_m3 (eigene Bedingung)")
		-- Mitglied verlässt den Server mitten im Vorgang: kein Fehler beim nächsten Übertrag
		T.eq(g:Act(c, "party_join", { code = party.code, rid = 6 }), "ok", "Cem tritt bei")
		S.leave(c)
		g:Advance(1)
		S.act(a, "story_claim", { id = "c1_m3" })
		noErrors(T, g, "Co-op")
	end },

	{ "Passiv-Modus: Start/Verkauf abgelehnt, Ereignisse zählen nicht, kein Kunde; außerhalb der Open World kein Verkauf", function(T, H)
		local S = setup(H, { placeKind = "all" })
		local g, SR, SS = S.g, S.SR, S.SS
		local pl, ms, d = S.join(7501, "Pia")
		T.eq(ms.p.mode, "lobby", "all-Place: Lobby")
		S.tick(3)
		T.eq(S.offer(pl), false, "Lobby: kein Kunde")
		S.act(pl, "story_start", { id = "c1_m1" })
		T.eq(S.story(pl).active.id, "c1_m1", "Start geht auch in der Lobby")
		local m = g:Mark()
		S.act(pl, "story_sell", { offer = 1, price = 1 })
		T.check(g:HasToast(pl, "Open World", m), "Verkauf nur in der Open World")
		-- Passiv
		T.eq(g:Act(pl, "lobby_settings", { single = false, passive = true, beginner = false, rid = 1 }), "ok", "passiv")
		T.eq(S.snapshot(pl).passive, true, "Snapshot passive")
		g:Advance(0.5)
		T.eq(g:Act(pl, "lobby_mode", { mode = "openworld", rid = 2 }), "ok", "lobby_mode")
		T.eq(g:Act(pl, "lobby_go", { rid = 3 }), "ok", "lobby_go")
		T.eq(ms.p.mode, "openworld", "Open World")
		SS.OnMode(ms, d, "openworld")
		S.tick(4)
		T.eq(S.offer(pl), false, "passiv: kein Kunde")
		SS.OnEvent(ms, d, "settle")
		SS.OnStat(ms, d, "jobsDone", 1)
		T.eq(S.story(pl).active.progress, 0, "passiv: Ereignisse zählen nicht")
		m = g:Mark()
		S.act(pl, "story_sell", { offer = 1, price = 1 })
		T.check(g:HasToast(pl, "Passiv", m), "Verkauf im Passiv-Modus abgelehnt")
		S.act(pl, "story_start", { id = "c1_m1" })
		T.check(g:HasToast(pl, "Passiv", m), "Start im Passiv-Modus abgelehnt")
		-- wieder aktiv: Kunde kommt
		T.eq(g:Act(pl, "lobby_settings", { single = false, passive = false, beginner = false, rid = 4 }), "ok", "aktiv")
		T.check(S.customer(pl) ~= nil, "Kunde kommt wieder")
		-- Kunde zieht nach Patience weiter
		m = g:Mark()
		S.tick(S.SR.Config().Sale.Patience + 2)
		T.eq(S.offer(pl), false, "Kunde weg")
		T.check(g:HasToast(pl, "keine Lust mehr", m), "Geduld-Toast")
		-- zurück in die Lobby: Kunde weg
		T.check(S.customer(pl) ~= nil, "neuer Kunde")
		g:Advance(3.1)
		T.eq(g:Act(pl, "lobby_return", { rid = 5 }), "ok", "lobby_return")
		SS.OnMode(ms, d, ms.p.mode)
		T.eq(S.offer(pl), false, "Lobby: Kunde weg")
		noErrors(T, g, "Passiv")
	end },

	{ "Regressionen (Regeln): Voraussetzung ≤ Kapitel-Level, Tagesauswahl nach Level, Kunde nach Geduld = neuer Kunde, Server-Geheimnis im Seed, Kunden-Takt über Moduswechsel/Rejoin", function(T, H)
		local S = setup(H, { level = 12 })
		local g, SR, SS = S.g, S.SR, S.SS
		-- Jede Story-Mission ist spätestens auf dem Level ihres Kapitels machbar (keine Sackgasse wie Produktion 35 in Kapitel 4 ab 30)
		local bad = SR.UnlockCheck()
		T.eq(#bad, 0, "UnlockCheck leer: " .. table.concat(bad, "; "))
		T.eq(SR.RequiredLevel(SR.Mission("c2_m3")), 4, "c2_m3 (Quiz) braucht Level 4")
		T.eq(SR.RequiredLevel(SR.Mission("c3_m3")), 8, "c3_m3 (Teststrecke) braucht Level 8")
		T.eq(SR.RequiredLevel(SR.Mission("c3_m4")), 12, "c3_m4: günstigste Alternative (NPC-Auktion 12, Einliefern 20)")
		T.eq(SR.RequiredLevel(SR.Mission("c4_m2")), 30, "c4_m2 (Produktion) braucht Level 30")
		T.eq(SR.RequiredLevel(SR.Mission("c5_m3")), 50, "c5_m3: günstigster Traumwagen ab Level 50")
		T.eq(#SR.BalanceCheck(), 0, "Balance weiter ≤ 40 %: " .. table.concat(SR.BalanceCheck(), "; "))
		-- Tagesauswahl: nur Nebenmissionen, die das Level schon erlaubt; jeden Tag mindestens eine
		local day0 = NOW - 3600
		for _, lvl in ipairs({ 1, 3, 5, 8, 50 }) do
			local minCount = math.huge
			for k = 0, 59 do
				local ids = SR.DailyIds(SR.DayKey(day0 + k * DAY), lvl)
				minCount = math.min(minCount, #ids)
				for _, id in ipairs(ids) do
					local need = SR.SideLevel(SR.SideDef(id))
					if need > lvl then
						T.check(false, "Level " .. lvl .. ", Tag " .. k .. ": " .. id .. " braucht Level " .. need)
					end
				end
			end
			T.check(minCount >= 1, "Level " .. lvl .. ": jeden Tag mindestens eine Nebenmission (" .. tostring(minCount) .. ")")
			if lvl >= 12 then
				T.eq(minCount, 3, "Level " .. lvl .. ": drei je Tag")
			end
		end
		T.check(H.DeepEqual(SR.DailyIds("2026-10-02", 1), { "s_jobs" }), "Level 1: nur s_jobs")
		T.check(H.DeepEqual(SR.DailyIds("2026-10-02", 50), SR.DailyIds("2026-10-02")), "alles frei = ganzer Pool")
		T.eq(SR.SideDef("s_delivery").needsCar, true, "Lieferung braucht ein eigenes Auto (Hinweis)")
		-- Server-Geheimnis: der Wurf lässt sich aus userId und Serial (Snapshot) nicht nachrechnen
		local pl, ms, d = S.join(7601, "Kim")
		local predicted = 0
		local seen = 0
		for i = 1, 3 do
			if i > 1 then
				S.tick(46)
			end
			local offer = S.customer(pl)
			T.check(offer ~= nil, "Kunde")
			local naive = SR.NextSale(d, "7601:" .. tostring(offer.serial), d.level)
			seen += 1
			if naive.roll == offer.roll and naive.customer == offer.customer then
				predicted += 1
			end
			S.act(pl, "story_sell", { offer = offer.serial, price = 1 })
		end
		T.check(seen == 3 and predicted < 3, "Wurf aus userId:serial nicht vorhersagbar (" .. predicted .. " von 3 Treffer)")
		T.eq(S.snapshot(pl).sale, false, "kein Kunde direkt nach dem Verkauf")
		-- Kunden-Takt steht im Profil: Moduswechsel und Rejoin bringen keinen früheren Kunden
		local nextAt = S.story(pl).sales.nextAt
		T.check(nextAt >= g:Now() + 40, "sales.nextAt ≈ jetzt + 45 s")
		SS.OnMode(ms, d, "lobby")
		SS.OnMode(ms, d, "openworld")
		SS.OnJoin(ms, d, g:Now())
		S.tick(10)
		T.eq(S.offer(pl), false, "nach Lobby-Hin-und-Zurück: noch kein Kunde (Takt bleibt)")
		S.leave(pl)
		g:Advance(1)
		local rec = g:Record(7601)
		T.eq(rec and rec.data.games.story.sales.nextAt, nextAt, "nextAt gespeichert")
		local pl2, ms2, d2 = S.join(7601, "Kim")
		T.eq(d2.games.story.sales.nextAt, nextAt, "nextAt geladen (Whitelist)")
		S.tick(5)
		T.eq(S.offer(pl2), false, "nach Rejoin: noch kein Kunde")
		S.tick(40)
		T.check(S.customer(pl2) ~= nil, "nach dem Takt kommt der Kunde")
		-- Geduld zu Ende: der nächste Kunde ist ein anderer (Serial +1), nicht derselbe mit demselben Wurf
		local o1 = S.offer(pl2)
		local m = g:Mark()
		S.tick(SR.Config().Sale.Patience + 2)
		T.eq(S.offer(pl2), false, "Kunde weg")
		T.eq(S.story(pl2).sales.serial, o1.serial, "Serial rückt vor (OfferGone)")
		local o2 = S.customer(pl2)
		T.check(o2 ~= nil and o2.serial == o1.serial + 1, "nächster Kunde hat Serial + 1")
		T.check(o2.roll ~= o1.roll or o2.customer ~= o1.customer, "nächster Kunde ist ein anderer")
		-- Moduswechsel mit wartendem Kunden: Serial rückt ebenfalls vor
		SS.OnMode(ms2, d2, "lobby")
		T.eq(S.story(pl2).sales.serial, o2.serial, "OnMode: Serial rückt vor")
		SS.OnMode(ms2, d2, "openworld")
		local o3 = S.customer(pl2)
		T.check(o3 ~= nil and o3.serial == o2.serial + 1, "nach Moduswechsel neuer Kunde")
		noErrors(T, g, "Regressionen")
	end },
}
