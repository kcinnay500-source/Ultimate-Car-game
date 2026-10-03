-- Ausbaustufe 4, Meilensteine 6–7 Ende-zu-Ende über die echte Verkabelung (H.Garage, Remotes.Command -> request ->
-- Mini.Handle, echte Stadt aus tools/worldgen): neuer Spieler -> Tutorial bis zum Kiesplatz -> Story Kapitel 1 am Kiesplatz
-- (Verkäufe aller Preisstufen, Werkstatt-Auftrag, 2.500 Credits) -> Kapitel 2 über echte Aufträge (jobsDone über
-- MiniRules.StatHook), Hebebühne, Zeitfahren -> Level-Sperre für Kapitel 3 -> ow_build Autohaus (Baustelle, Zeitraffer,
-- ow_ready) -> ow_collect -> Perks wirken in R.Reward und CarRules.DealerPrice (Deckel ×1,6) -> Kapitel 3 über Autokauf und
-- Auktions-Einlieferung (Ereignisse aus Hinweisen/api.event) -> Passiv-Modus blockt und gibt frei -> Nebenmissionen mit
-- Tageswechsel -> Speichern/Laden. Dazu Co-op in der Party (zwei Spieler) und der Client (Tabs story/buildings).
local DAY = 86400
local NOW = 1760000000 - (1760000000 % DAY) + 3600 -- 01:00 UTC

local function join(g, userId, name)
	local pl = g:Join(userId, { name = name })
	g:Advance(1.1)
	g:Send(pl, "hello")
	g:Advance(1.1)
	return pl, g:D(pl), g:Session(pl)
end

local rid = 7000
local function act(T, g, pl, action, payload, expect, msg)
	g:Advance(1.1) -- Abklingzeit je Aktion (MiniNet.Cooldowns)
	rid += 1
	payload = payload or {}
	payload.rid = rid
	local res = g:Act(pl, action, payload)
	if expect then
		T.eq(res, expect, msg or (action .. " -> " .. expect))
	end
	return res
end

local function cityStation(g, key)
	local st = g:Find("Workspace.City.Stations")
	return st and st:FindFirstChild(key)
end

local function openCityStation(g, pl, key)
	local st = cityStation(g, key)
	assert(st, "Stadt-Station fehlt: " .. key)
	local arrival = st:FindFirstChild("Arrival")
	g:Teleport(pl, arrival and arrival.WorldPosition or st.Position, arrival and nil or Vector3.new(0, 3, 4))
	g:Advance(0.2)
	local m = g:Mark()
	g:Trigger(pl, st:FindFirstChildOfClass("ProximityPrompt"), { force = true })
	g:Advance(1.1)
	return m
end

-- Zeitraffer ohne Zwischen-Ticks (Wanduhr springt wie offline), danach ein paar Server-Ticks
local function lapse(g, seconds)
	g.env.clock:Jump(seconds)
	g:Advance(2.1)
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, what .. ": keine Fehler: " .. g:ErrorText())
end

local function levelTo(g, d, level)
	local MR = g:MiniShared("MiniRules")
	local guard = 0
	while d.level < level and guard < 5000 do
		guard += 1
		MR.GainXP(d, 25)
	end
end

local function story(g, pl)
	return g:D(pl).games.story
end

-- Zum Kiesplatz, dann warten, bis ein Kunde da ist (StoryService.Tick über Mini.Tick)
local function customer(g, pl)
	local st = cityStation(g, "kiesplatz")
	local arrival = st and st:FindFirstChild("Arrival")
	g:Teleport(pl, arrival and arrival.WorldPosition or st.Position, arrival and nil or Vector3.new(0, 3, 4))
	local SS = g:MiniServer("StoryService")
	for _ = 1, 400 do
		local offer = SS.Offer(g:MiniState(pl))
		if offer then
			return offer
		end
		g:Advance(0.5)
	end
	return nil
end

-- Nächsten Kunden holen, dessen beim Angebot festgelegter Wurf die Stufe tier gelingen (fail = false) bzw. scheitern lässt
local function customerFor(T, g, pl, tier, fail)
	for _ = 1, 40 do
		local offer = customer(g, pl)
		assert(offer, "kein Kunde am Kiesplatz")
		local ok = tier == 1 or offer.roll < offer.tiers[tier].chance
		if ok ~= fail then
			return offer
		end
		act(T, g, pl, "story_sell", { offer = offer.serial, price = 1 }, "ok") -- sicher abfertigen, nächsten abwarten
		g:Advance(46)
	end
	error("kein passender Kunde gefunden")
end

-- Verkauf zur Stufe tier an einen passenden Kunden. customerFor fertigt unpassende Kunden vorher günstig ab (Geld und
-- Fortschritt ändern sich dabei), darum liefert sell als drittes den Stand unmittelbar vor dem eigentlichen Versuch.
local function sell(T, g, pl, tier, fail)
	local offer = customerFor(T, g, pl, tier, fail)
	local d = g:D(pl)
	local before = { money = d.money, progress = type(d.games.story.active) == "table" and d.games.story.active.progress or 0, sales = d.games.story.sales.n }
	local m = g:Mark()
	act(T, g, pl, "story_sell", { offer = offer.serial, price = tier }, "ok", "story_sell Stufe " .. tier)
	for _, n in ipairs(g:Notices(pl, "story", m)) do
		if n.event == "sale" then
			return n, offer, before
		end
	end
	return nil, offer, before
end

local function missionNotice(g, pl, id, since)
	local last
	for _, n in ipairs(g:Notices(pl, "mission", since)) do
		if n.id == id then
			last = n
		end
	end
	return last
end

local function finishTutorial(T, g, pl, d, Flow)
	local TR = g:MiniShared("TutorialRules")
	T.eq(TR.StepIndex(d), 1, "Tutorial Schritt 1")
	-- neues Profil: erst die Startwahl (Werkstatt), vorher zählt „Weiter“ nicht
	local MR = g:MiniShared("MetaRules")
	T.check(MR.StartPending(d), "Startwahl offen")
	act(T, g, pl, "tutorial_next", { step = 1 }, "ok")
	T.eq(TR.StepIndex(d), 1, "vor der Startwahl kein Fortschritt")
	act(T, g, pl, "start_choose", { path = "werkstatt" }, "ok")
	T.eq(MR.StartPath(d), "werkstatt", "Startweg werkstatt")
	act(T, g, pl, "tutorial_next", { step = 1 }, "ok")
	act(T, g, pl, "tutorial_next", { step = 2 }, "ok")
	g:Send(pl, "travel", { key = "workshop" })
	T.eq(TR.StepIndex(d), 4, "Schritt 4 (Auftrag annehmen)")
	local j = Flow.AcceptInspection(T, g, pl)
	T.check(j ~= nil, "Auftrag angenommen")
	g:Advance(1.1)
	local C = g:Config()
	local def = C.JobById[j.kind]
	Flow.Scan(T, g, pl, j.id)
	g:Send(pl, "diagnose", { id = j.id, choice = def.cause })
	g:Advance(1.1)
	for i = 1, #def.steps do
		T.check(Flow.RepairStep(T, g, pl, j.id, i), "Reparaturschritt " .. i)
	end
	Flow.Scan(T, g, pl, j.id)
	g:Advance(1.1)
	g:Teleport(pl, g:Station(pl, "workshop"), Vector3.new(0, 0, 3))
	g:Advance(0.3)
	g:Send(pl, "settle", { id = j.id })
	T.eq(TR.StepIndex(d), 8, "Schritt 8 (Stadtplan)")
	act(T, g, pl, "mini_travel", { key = "hub" }, "ok")
	g:Advance(3.1)
	openCityStation(g, pl, "dealer")
	openCityStation(g, pl, "goals")
	T.eq(TR.StepIndex(d), 11, "Schritt 11 (Kiesplatz)")
	local m = openCityStation(g, pl, "kiesplatz")
	T.check(d.games.meta.tutorialDone and not d.games.meta.tutorialSkipped, "Tutorial am Kiesplatz beendet")
	local open = g:Events(pl, "mini_open", m)[1]
	T.check(open ~= nil and open.tab == "story", "Kiesplatz-Station öffnet den Tab story")
	return m
end

return {
	{ "Neuer Spieler: Tutorial bis zum Kiesplatz -> Kapitel 1 (Verkäufe aller Stufen, Auftrag, 1.000 Cr) -> Kapitel 2 (echte Aufträge, Hebebühne, Zeitfahren) -> Level-Sperre -> Autohaus bauen/abholen -> Perks -> Kapitel 3 -> Passiv -> Nebenmissionen/Tageswechsel -> Speichern/Laden", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW })
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local MR = g:MiniShared("MiniRules")
		local SR = g:MiniShared("StoryRules")
		local OWR = g:MiniShared("OWRules")
		local CB = g:MiniShared("CrossBonus")
		local CR = g:MiniShared("CarRules")
		local CC = g:MiniShared("CarCatalog")
		local SS = g:MiniServer("StoryService")
		local OWS = g:MiniServer("OWService")
		local R = g:Rules()
		local pl, d, p = join(g, 6001, "Anna")
		T.eq(p.mode, "openworld", "Modus openworld")
		-- Daten (Vertrag §2): story und ow aus MiniRules.DefaultGames
		T.check(type(d.games.story) == "table" and d.games.story.chapter == 1 and d.games.story.active == false, "d.games.story Standard")
		T.check(type(d.games.ow) == "table" and type(d.games.ow.buildings) == "table" and d.games.ow.passive == false, "d.games.ow Standard")
		local snap = g:MiniSnapshot(pl)
		T.check(snap and type(snap.story) == "table" and snap.story.chapter == 1 and type(snap.story.missions) == "table" and #snap.story.missions == 3, "Snapshot story (voll: missions)")
		T.check(snap and type(snap.ow) == "table" and type(snap.ow.buildings) == "table" and snap.ow.passive == false, "Snapshot ow")
		T.check(snap and type(snap.story.side) == "table" and #snap.story.side >= 3, "Snapshot story.side (Tagesauswahl + Legende)")

		---------------------------------------------------------------- Tutorial bis zum Kiesplatz
		finishTutorial(T, g, pl, d, Flow)
		T.eq(d.games.stats.jobsDone, 1, "ein Auftrag im Tutorial")
		T.eq(story(g, pl).active, false, "Story noch nicht gestartet (Tutorial-Auftrag zählt nicht)")

		---------------------------------------------------------------- Kapitel 1: Der Kiesplatz
		-- c1_m1: drei Verkäufe (alle Preisstufen; Stufe 3 einmal geplatzt, denn der Wurf gehört zum Kunden)
		act(T, g, pl, "story_start", { id = "c1_m2" }, "ok", "falsche Reihenfolge -> Toast")
		T.eq(story(g, pl).active, false, "c1_m2 nicht gestartet (erst c1_m1)")
		local m = g:Mark()
		act(T, g, pl, "story_start", { id = "c1_m1" }, "ok", "story_start c1_m1")
		T.check(type(story(g, pl).active) == "table" and story(g, pl).active.id == "c1_m1", "c1_m1 aktiv")
		local started = g:Notices(pl, "story", m)
		T.check(#started >= 1 and started[1].event == "started" and started[1].mission == "c1_m1", "mini_notice story started")
		-- Verkauf nur am Kiesplatz: weit weg -> Toast, kein Verkauf
		local offer = customer(g, pl)
		T.check(offer ~= nil, "Kunde am Kiesplatz (story.sale im Snapshot)")
		g:Advance(1.1)
		T.check(g:MiniSnapshot(pl).story.sale and g:MiniSnapshot(pl).story.sale.offer == offer.serial, "Snapshot story.sale mit Angebot")
		g:Teleport(pl, g:Station(pl, "workshop"), Vector3.new(0, 0, 3))
		m = g:Mark()
		act(T, g, pl, "story_sell", { offer = offer.serial, price = 1 }, "ok")
		T.check(g:HasToast(pl, "Kiesplatz", m), "weit weg: Hinweis, zum Kiesplatz zu gehen")
		T.eq(story(g, pl).sales.n, 0, "kein Verkauf aus der Ferne")
		act(T, g, pl, "story_sell", { offer = offer.serial, price = "teuer" }, "invalid", "price muss number sein")
		-- Stufe 1 (sicher)
		local money = d.money
		local mStart = g:Mark()
		local n1 = sell(T, g, pl, 1)
		local tier1 = g:MiniShared("GameConfig").Story.Sale.Tiers[1].profit -- Level 1: Faktor 1
		T.check(n1 ~= nil and n1.sold == true and n1.tier == 1 and n1.credits == tier1, "Stufe 1 verkauft: +" .. tier1 .. " Cr Reingewinn")
		T.eq(d.money - money, tier1, "Credits nur über den Server (Reingewinn)")
		T.eq(story(g, pl).sales.n, 1, "sales.n 1")
		T.eq(story(g, pl).active.progress, 1, "c1_m1 Fortschritt 1")
		-- Stufe 3 geplatzt (Wurf ≥ 0,5): kein Geld, kein Fortschritt (Stand unmittelbar vor dem Versuch, siehe sell)
		local n3f, _, b3f = sell(T, g, pl, 3, true)
		T.check(n3f ~= nil and n3f.sold == false and n3f.credits == 0, "Stufe 3 geplatzt")
		T.eq(d.money, b3f.money, "geplatzt: kein Geld")
		T.eq(story(g, pl).active.progress, b3f.progress, "geplatzt: kein Fortschritt")
		T.eq(story(g, pl).sales.n, b3f.sales, "geplatzt: kein Verkauf gezählt")
		-- Stufe 2 und Stufe 3 erfolgreich (Gewinn je Stufe × Level-Faktor, beim Angebot festgelegt: offer.tiers[tier].profit);
		-- unpassende Kunden dazwischen wurden günstig verkauft, darum zählt der Fortschritt relativ und mit Deckel 3
		local n2, o2, b2 = sell(T, g, pl, 2, false)
		T.check(n2 ~= nil and n2.sold == true and n2.credits == o2.tiers[2].profit and n2.credits >= g:MiniShared("GameConfig").Story.Sale.Tiers[2].profit, "Stufe 2 verkauft: +" .. tostring(n2 and n2.credits) .. " Cr (Gewinn der Stufe)")
		T.check(d.money - b2.money >= (n2 and n2.credits or 1e9), "Stufe 2: Gewinn gutgeschrieben (dazu evtl. Level-Bonus)")
		local n3, o3, b3 = sell(T, g, pl, 3, false)
		T.check(n3 ~= nil and n3.sold == true and n3.credits == o3.tiers[3].profit and n3.credits >= g:MiniShared("GameConfig").Story.Sale.Tiers[3].profit, "Stufe 3 verkauft: +" .. tostring(n3 and n3.credits) .. " Cr (Gewinn der Stufe)")
		T.check(d.money - b3.money >= (n3 and n3.credits or 1e9), "Stufe 3: Gewinn gutgeschrieben (dazu evtl. Level-Bonus)")
		T.near(o3.tiers[3].profit, math.floor(g:MiniShared("GameConfig").Story.Sale.Tiers[3].profit * SR.LevelFactor(d.level) + 0.5), 1, "Gewinn = Stufe-3-Gewinn × Level-Faktor")
		T.check(story(g, pl).sales.best >= 1, "Bestpreis-Verkäufe gezählt")
		T.eq(story(g, pl).active.progress, 3, "c1_m1 3/3")
		local done1 = missionNotice(g, pl, "c1_m1", mStart)
		T.check(done1 ~= nil and done1.done == true and done1.progress == 3, "mini_notice mission c1_m1 erledigt")
		act(T, g, pl, "story_claim", { id = "c1_m1" }, "ok", "story_claim c1_m1")
		T.eq(story(g, pl).done.c1_m1, true, "c1_m1 abgeholt")
		T.eq(story(g, pl).step, 2, "Schritt 2")
		T.eq(d.games.stats.missionsDone, 1, "missionsDone 1")
		act(T, g, pl, "story_claim", { id = "c1_m1" }, "ok", "zweites Abholen -> Toast")
		T.eq(d.games.stats.missionsDone, 1, "nicht zweimal")
		-- c1_m2: Zurück in die Werkstatt (settle-Ereignis aus Mini.OnSettled)
		act(T, g, pl, "story_start", { id = "c1_m2" }, "ok")
		m = g:Mark()
		local receipt = Flow.CompleteInspection(T, g, pl)
		T.check(receipt ~= nil, "Auftrag abgerechnet")
		T.check(missionNotice(g, pl, "c1_m2", m) ~= nil and missionNotice(g, pl, "c1_m2", m).done == true, "c1_m2 erledigt durch echte Abrechnung")
		act(T, g, pl, "story_claim", { id = "c1_m2" }, "ok")
		-- c1_m3: 2.500 Credits auf dem Konto (Bedingung aus dem Profil, im Tick 1×/s). Startgeld + Tutorial + Belohnungen
		-- liegen knapp darunter (die Probeverkäufe oben haben etwas dazugegeben); unter 2.500 ist die Mission offen
		if d.money >= 2500 then
			MR.AddMoney(d, 2400 - d.money)
		end
		m = g:Mark()
		act(T, g, pl, "story_start", { id = "c1_m3" }, "ok")
		g:Advance(2.1)
		T.check(missionNotice(g, pl, "c1_m3", m) == nil or missionNotice(g, pl, "c1_m3", m).done ~= true, "c1_m3 unter 2.500 Cr offen")
		MR.AddMoney(d, 2500 - d.money)
		g:Advance(2.1)
		local c13 = missionNotice(g, pl, "c1_m3", m)
		T.check(c13 ~= nil and c13.done == true, "c1_m3 erfüllt (Kontostand)")
		m = g:Mark()
		act(T, g, pl, "story_claim", { id = "c1_m3" }, "ok")
		local claimed = nil
		for _, n in ipairs(g:Notices(pl, "story", m)) do
			if n.event == "claimed" then
				claimed = n
			end
		end
		T.check(claimed ~= nil and claimed.chapterDone == true and claimed.nextChapter == 2 and claimed.nextLevel == 5, "Kapitel 1 abgeschlossen, Kapitel 2 ab Level 5")
		T.eq(story(g, pl).chapter, 2, "Kapitel 2")

		---------------------------------------------------------------- Kapitel 2: Die erste Werkstatt
		if d.level < 5 then
			act(T, g, pl, "story_start", { id = "c2_m1" }, "locked", "Kapitel 2 unter Level 5 gesperrt (Unlocks story:2)")
		end
		levelTo(g, d, 5)
		g:Advance(1.1)
		act(T, g, pl, "story_start", { id = "c2_m1" }, "ok", "story_start c2_m1")
		-- fünf echte Aufträge (jobsDone läuft über MiniRules.AddStat -> StatHook -> StoryService.OnStat)
		local jobsBefore = d.games.stats.jobsDone
		m = g:Mark()
		for i = 1, 5 do
			T.check(Flow.CompleteInspection(T, g, pl) ~= nil, "Auftrag " .. i)
		end
		T.eq(d.games.stats.jobsDone, jobsBefore + 5, "fünf Aufträge")
		local c21 = missionNotice(g, pl, "c2_m1", m)
		T.check(c21 ~= nil and c21.done == true and c21.progress == 5, "c2_m1 erledigt (5/5)")
		act(T, g, pl, "story_claim", { id = "c2_m1" }, "ok")
		-- c2_m2: Hebebühne 2 (Bedingung aus dem Profil); vorher der Werkstatt-Perk: Bühnen über der ersten erhöhen R.Reward
		local j = Flow.AcceptInspection(T, g, pl)
		T.check(j ~= nil, "Auftrag für die Vergütungsprobe")
		local job = Flow.Job(g, pl, j.id)
		local bays = d.bays
		d.bays = 1
		T.near(CB.OWPerk(d, "werkstatt"), 1, 1e-9, "Werkstatt-Perk mit 1 Bühne neutral")
		local reward1 = job and R.Reward(d, job) or 0
		d.bays = 3
		T.near(CB.OWPerk(d, "werkstatt"), 1.16, 1e-9, "Werkstatt-Perk mit 3 Bühnen +16 %")
		local reward3 = job and R.Reward(d, job) or 0
		T.check(reward1 > 0 and math.abs(reward3 / reward1 - 1.16) < 0.02, "R.Reward steigt um den Perk (" .. tostring(reward1) .. " -> " .. tostring(reward3) .. ")")
		d.bays = 4
		T.near(CB.OWPerk(d, "werkstatt"), 1.24, 1e-9, "Werkstatt-Perk gedeckelt +24 %")
		T.check(CB.CareerCapped(d) <= CB.WorkshopCap(), "CareerCapped ≤ Deckel ×1,6")
		d.bays = bays
		act(T, g, pl, "story_start", { id = "c2_m2" }, "ok")
		m = g:Mark()
		d.bays = 2
		g:Advance(2.1)
		T.check(missionNotice(g, pl, "c2_m2", m) ~= nil and missionNotice(g, pl, "c2_m2", m).done == true, "c2_m2 erfüllt (2 Bühnen)")
		act(T, g, pl, "story_claim", { id = "c2_m2" }, "ok")
		-- c2_m3: zehn Quizfragen (Statistik quizCorrect über MiniRules.AddStat -> StatHook -> StoryService.OnStat)
		act(T, g, pl, "story_start", { id = "c2_m3" }, "ok")
		m = g:Mark()
		MR.AddStat(d, "quizCorrect", 10, g:Now())
		g:Advance(1.1)
		T.check(missionNotice(g, pl, "c2_m3", m) ~= nil and missionNotice(g, pl, "c2_m3", m).done == true, "c2_m3 erledigt (quizCorrect)")
		act(T, g, pl, "story_claim", { id = "c2_m3" }, "ok")
		T.eq(story(g, pl).chapter, 3, "Kapitel 3 erreicht")

		---------------------------------------------------------------- Level-Sperre Kapitel 3 (ab 15) und Gebäude-Sperre
		T.check(d.level < 15, "noch unter Level 15 (" .. tostring(d.level) .. ")")
		m = g:Mark()
		act(T, g, pl, "story_start", { id = "c3_m1" }, "locked", "Kapitel 3 gesperrt (ACTION_UNLOCK story:3)")
		T.check(g:HasToast(pl, "Ab Level 15", m), "Sperr-Toast Level 15")
		T.eq(g:MiniSnapshot(pl).story.locked, true, "Snapshot story.locked")
		if d.level < 10 then
			act(T, g, pl, "ow_build", { typ = "autohaus" }, "locked", "Autohaus unter Level 10 gesperrt (building:autohaus)")
		end
		act(T, g, pl, "ow_build", { typ = "werkstatt" }, "ok", "werkstatt: kein zweiter Kaufweg (Toast)")
		T.eq(OWR.StageOf(d, "autohaus"), 0, "nichts gebaut")

		---------------------------------------------------------------- Autohaus bauen (Zeitraffer), abholen, Perks
		levelTo(g, d, 20) -- Kapitel 3 (15), Autohaus (10), Spieler-Auktionen (20)
		g:Advance(1.1)
		local price = CR.DealerPrice(d, CC.Model("komet"))
		local basePrice = CC.Model("komet").price
		m = g:Mark()
		d.money = 100
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok", "ow_build ohne Credits -> Toast")
		T.check(g:HasToast(pl, "Nicht genug Credits", m), "Toast Credits")
		MR.AddMoney(d, 60000)
		money = d.money
		m = g:Mark()
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok", "ow_build autohaus")
		T.eq(money - d.money, 12000, "12.000 Cr bezahlt")
		local e = OWR.Entry(d, "autohaus")
		T.check(e and e.stage == 1 and e.built == 0 and e.readyAt > g:Now(), "Baustelle (stage 1, built 0)")
		T.check(#g:Notices(pl, "ow_build", m) == 1, "mini_notice ow_build")
		T.check(OWS.ModelOf(pl, "autohaus") ~= nil and OWS.ModelOf(pl, "autohaus").Name == "baustelle", "Baustellen-Modell am Grundstück")
		g:Advance(1.1)
		local ow = g:MiniSnapshot(pl).ow
		T.check(ow and ow.buildings.autohaus.building == true and ow.buildings.autohaus.remaining > 0, "Snapshot: Baustelle mit Restzeit")
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok", "zweiter Bau während der Baustelle -> Toast")
		T.eq(OWR.Entry(d, "autohaus").stage, 1, "immer noch Stufe 1")
		T.near(CB.OWPerk(d, "autohaus"), 1, 1e-9, "Perk zählt nur fertige Stufen (Baustelle nicht)")
		m = g:Mark()
		lapse(g, 600)
		T.eq(OWR.Built(d, "autohaus"), 1, "nach 10 Min. fertig (Settle im Tick)")
		local ready = g:Notices(pl, "ow_ready", m)
		T.check(#ready == 1 and ready[1].typ == "autohaus" and ready[1].stage == 1, "mini_notice ow_ready")
		T.check(OWS.ModelOf(pl, "autohaus") ~= nil and OWS.ModelOf(pl, "autohaus").Name == "autohaus_1", "Stufenmodell getauscht")
		-- Perks: Händlerrabatt 3 % (Deckel 12 %), CrossBonus = OWRules
		T.near(CB.OWPerk(d, "autohaus"), 1.03, 1e-9, "Autohaus-Perk +3 %")
		T.near(CB.OWPerk(d, "autohaus"), OWR.Perk(d, "autohaus"), 1e-9, "CrossBonus.OWPerk = OWRules.Perk")
		local price2 = CR.DealerPrice(d, CC.Model("komet"))
		T.check(price2 < price and price2 == math.max(1, math.floor(basePrice * (1 - (1 - price / basePrice) - 0.03) + 0.5)), "Händlerpreis um 3 % günstiger (" .. tostring(price) .. " -> " .. tostring(price2) .. ")")
		-- Abholen: gleich nach der Fertigstellung nur die paar Sekunden, dann 1 Stunde Ertrag (1.500 Cr/Std. × Prestige 1)
		money = d.money
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok", "ow_collect kurz nach der Fertigstellung")
		T.check(d.money - money <= 5, "nur Sekunden Ertrag (" .. tostring(d.money - money) .. " Cr)")
		m = g:Mark()
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok", "ow_collect ohne Ertrag -> Toast")
		T.check(g:HasToast(pl, "nichts abzuholen", m), "Toast nichts abzuholen")
		lapse(g, 3600)
		money = d.money
		m = g:Mark()
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok", "ow_collect")
		T.near(d.money - money, 1500, 2, "1.500 Cr Ertrag je Stunde")
		local collected = g:Notices(pl, "ow_collect", m)
		T.check(#collected == 1 and collected[1].typ == "autohaus" and math.abs(collected[1].credits - 1500) <= 2, "mini_notice ow_collect")
		money = d.money
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok", "zweites Abholen leer")
		T.eq(d.money, money, "nicht zweimal")
		-- Deckel 12 Std.: nach 20 Std. nur 12 × 1.500
		lapse(g, 20 * 3600)
		money = d.money
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok")
		T.near(d.money - money, 12 * 1500, 3, "Ertrag auf 12 Std. gedeckelt")

		---------------------------------------------------------------- Kapitel 3: Autohaus (Bau-Mission), Autokauf, Einlieferung
		act(T, g, pl, "story_start", { id = "c3_m1" }, "ok", "story_start c3_m1 (Level 20)")
		g:Advance(2.1)
		local v = SR.MissionView(d, SR.Mission("c3_m1"), d.level)
		T.check(v.claimable == true, "c3_m1 sofort erfüllt (Autohaus steht)")
		act(T, g, pl, "story_claim", { id = "c3_m1" }, "ok")
		act(T, g, pl, "story_start", { id = "c3_m2" }, "ok")
		m = g:Mark()
		MR.AddMoney(d, price2 + 10)
		act(T, g, pl, "mini_car_buy", { model = "komet" }, "ok", "Auto kaufen (car_bought -> Story)")
		T.eq(#d.games.cars, 1, "ein Auto in der Garage")
		T.check(missionNotice(g, pl, "c3_m2", m) ~= nil and missionNotice(g, pl, "c3_m2", m).done == true, "c3_m2 erledigt (car_bought aus dem Hinweis)")
		act(T, g, pl, "story_claim", { id = "c3_m2" }, "ok")
		-- c3_m3: Zeitfahren ins Ziel mit dem neuen Auto (CarService meldet track_finish über api.notice -> Story-Ereignis;
		-- hier über das Dienst-Ereignis, weil das Fahren Physik braucht)
		act(T, g, pl, "story_start", { id = "c3_m3" }, "ok")
		m = g:Mark()
		SS.OnEvent(g:MiniState(pl), d, "track_finish", { time = 61 })
		g:Advance(1.1)
		T.check(missionNotice(g, pl, "c3_m3", m) ~= nil and missionNotice(g, pl, "c3_m3", m).done == true, "c3_m3 erledigt (track_finish)")
		act(T, g, pl, "story_claim", { id = "c3_m3" }, "ok")
		act(T, g, pl, "story_start", { id = "c3_m4" }, "ok")
		m = g:Mark()
		local car = d.games.cars[1]
		act(T, g, pl, "mini_auction_consign", { id = car.id, start = 1, duration = 120 }, "ok", "Auto einliefern (auction_consigned über api.event)")
		T.check(missionNotice(g, pl, "c3_m4", m) ~= nil and missionNotice(g, pl, "c3_m4", m).done == true, "c3_m4 erledigt (auction_consigned)")
		act(T, g, pl, "story_claim", { id = "c3_m4" }, "ok")
		T.eq(story(g, pl).chapter, 4, "Kapitel 4 erreicht (ab Level 30 gesperrt)")
		g:Advance(1.1)
		T.eq(g:MiniSnapshot(pl).story.locked, true, "Kapitel 4 gesperrt im Snapshot")
		act(T, g, pl, "mini_auction_cancel", { lot = 1 }, "ok", "Auktion abbrechen (kein Gebot)")

		---------------------------------------------------------------- Passiv-Modus: blockt Story/Verkauf/Auktion, gibt wieder frei
		m = g:Mark()
		act(T, g, pl, "ow_passive", { on = true }, "ok", "ow_passive an")
		T.eq(OWR.IsPassive(d), true, "passiv (meta.passive)")
		T.eq(d.games.meta.passive, true, "meta.passive = ow.passive")
		T.check(#g:Notices(pl, "ow_passive", m) == 1, "mini_notice ow_passive")
		levelTo(g, d, 30)
		g:Advance(1.1)
		m = g:Mark()
		act(T, g, pl, "story_start", { id = "c4_m1" }, "passive", "story_start im Passiv-Modus geblockt")
		T.check(g:HasToast(pl, "Passiv-Modus", m), "freundlicher Hinweis (GameConfig.OW.PassiveHint)")
		T.eq(story(g, pl).active, false, "nichts gestartet")
		act(T, g, pl, "story_sell", { offer = 1, price = 1 }, "passive", "story_sell geblockt")
		act(T, g, pl, "mini_auction_bid", { lot = 1, amount = 1 }, "passive", "mini_auction_bid geblockt")
		act(T, g, pl, "mini_auction_consign", { id = 1, start = 1, duration = 120 }, "passive", "mini_auction_consign geblockt")
		act(T, g, pl, "story_claim", { id = "c3_m4" }, "ok", "Abholen bleibt erlaubt (Toast: schon abgeholt)")
		T.eq(SS.Offer(g:MiniState(pl)), false, "kein Kunde im Passiv-Modus")
		g:Advance(1.1)
		local ps = g:MiniSnapshot(pl)
		T.check(ps.story.passive == true and ps.ow.passive == true and ps.meta.passive == true, "Snapshot passiv (story/ow/meta)")
		-- passive Einnahmen laufen weiter
		lapse(g, 3600)
		money = d.money
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok", "Abholen im Passiv-Modus erlaubt")
		T.check(d.money - money >= 1400, "Gebäude verdient im Passiv-Modus weiter")
		act(T, g, pl, "ow_passive", { on = false }, "ok", "ow_passive aus")
		T.eq(OWR.IsPassive(d), false, "nicht mehr passiv")
		act(T, g, pl, "story_start", { id = "c4_m1" }, "ok", "story_start nach Passiv wieder möglich")
		T.check(type(story(g, pl).active) == "table" and story(g, pl).active.id == "c4_m1", "c4_m1 aktiv")

		---------------------------------------------------------------- Nebenmissionen: Tagesauswahl, Abholen, Tageswechsel
		g:Advance(1.1)
		local side = g:MiniSnapshot(pl).story.side
		local jobsAtSide = d.games.stats.jobsDone
		local today = SR.DayKey(g:Now())
		local wantIds = SR.DailyIds(today, d.level)
		local daily = {}
		for _, s in ipairs(side) do
			if not s.legend then
				table.insert(daily, s.id)
			end
		end
		T.eq(#daily, #wantIds, "drei Nebenmissionen des Tages")
		for i, id in ipairs(wantIds) do
			T.eq(daily[i], id, "Tagesauswahl deterministisch " .. id)
		end
		-- s_jobs (3 Aufträge) ist im Pool: Fortschritt über echte Aufträge, falls heute dabei; sonst Legende prüfen
		local hasJobs = false
		for _, id in ipairs(wantIds) do
			if id == "s_jobs" then
				hasJobs = true
			end
		end
		local sideBefore = d.games.stats.missionsDone
		if hasJobs then
			for _ = 1, 3 do
				Flow.CompleteInspection(T, g, pl)
			end
			T.eq(story(g, pl).side.s_jobs and story(g, pl).side.s_jobs.n, 3, "s_jobs 3/3")
			act(T, g, pl, "side_claim", { id = "s_jobs" }, "ok", "side_claim s_jobs")
			T.eq(story(g, pl).side.s_jobs.claimed, true, "abgeholt")
			T.eq(d.games.stats.missionsDone, sideBefore + 1, "missionsDone zählt Nebenmissionen")
		end
		act(T, g, pl, "side_claim", { id = "gibt_es_nicht" }, "ok", "unbekannte Nebenmission -> Toast")
		-- Legende: 100 Aufträge (absolut) – Fortschritt aus dem Profil
		local legend = nil
		for _, s in ipairs(side) do
			if s.id == "l_jobs100" then
				legend = s
			end
		end
		T.check(legend ~= nil and legend.legend == true and legend.progress == jobsAtSide, "Legende l_jobs100 mit Gesamtfortschritt")
		-- Tageswechsel: neue Auswahl, Zähler weg
		lapse(g, DAY)
		local tomorrow = SR.DayKey(g:Now())
		T.check(tomorrow ~= today, "neuer UTC-Tag")
		for _, id in ipairs(wantIds) do
			T.eq(story(g, pl).side[id], nil, "Tageszähler " .. id .. " zurückgesetzt")
		end
		local side2 = g:MiniSnapshot(pl).story.side
		local want2 = SR.DailyIds(tomorrow, d.level)
		local daily2 = {}
		for _, s in ipairs(side2) do
			if not s.legend then
				table.insert(daily2, s.id)
				T.eq(s.progress, 0, "neuer Tag: " .. s.id .. " bei 0")
			end
		end
		T.eq(#daily2, #want2, "drei neue Nebenmissionen")
		for i, id in ipairs(want2) do
			T.eq(daily2[i], id, "neue Tagesauswahl " .. id)
		end

		---------------------------------------------------------------- Speichern/Laden
		local chapterBefore = story(g, pl).chapter
		local doneBefore = H.Copy(story(g, pl).done)
		g:Leave(pl)
		local rec = g:Record(6001)
		T.check(rec and rec.data and rec.data.games and rec.data.games.story and rec.data.games.ow, "Datensatz mit story und ow")
		T.eq(rec.data.games.story.chapter, chapterBefore, "gespeichert story.chapter")
		T.eq(rec.data.games.story.active and rec.data.games.story.active.id, "c4_m1", "gespeichert story.active")
		T.eq(rec.data.games.ow.buildings.autohaus.built, 1, "gespeichert ow.buildings.autohaus.built")
		T.eq(rec.data.games.meta.passive, false, "gespeichert meta.passive")
		-- Load idempotent
		local loaded = SR.Load(rec.data.games.story, rec.data, g:Now())
		local again = SR.Load(loaded, rec.data, g:Now())
		local same, where = H.DeepEqual(loaded, again)
		T.check(same, "StoryRules.Load idempotent (" .. tostring(where) .. ")")
		local pl2, d2 = join(g, 6001, "Anna")
		T.eq(d2.games.story.chapter, chapterBefore, "story geladen (Kapitel)")
		for id in pairs(doneBefore) do
			T.eq(d2.games.story.done[id], true, "geladen done " .. id)
		end
		T.check(type(d2.games.story.active) == "table" and d2.games.story.active.id == "c4_m1", "aktive Mission geladen")
		T.eq(OWR.Built(d2, "autohaus"), 1, "Autohaus geladen")
		T.check(OWS.ModelOf(pl2, "autohaus") ~= nil and OWS.ModelOf(pl2, "autohaus").Name == "autohaus_1", "Gebäude-Modell nach dem Laden")
		T.near(CB.OWPerk(d2, "autohaus"), 1.03, 1e-9, "Perk nach dem Laden")
		local snap2 = g:MiniSnapshot(pl2)
		T.check(snap2 and snap2.story and snap2.story.chapter == chapterBefore and snap2.story.active and snap2.story.active.id == "c4_m1", "Snapshot nach dem Laden")
		noErrors(T, g, "Ablauf")
	end },

	{ "Co-op: Party zu zweit, gleiche aktive Mission – Verkauf des einen zählt für den anderen; Passive bekommen nichts; Abholen jeder selbst", function(T, H)
		local g = H.Garage({ placeKind = "all", startTime = NOW })
		local LS = g:MiniServer("LobbyService")
		local OWR = g:MiniShared("OWRules")
		local a, da = join(g, 6101, "Anna")
		local b, db = join(g, 6102, "Ben")
		act(T, g, a, "party_create", {}, "ok", "party_create")
		local party = LS.PartyOf(a)
		T.check(party ~= nil and type(party.code) == "string", "Party mit Code")
		act(T, g, b, "party_join", { code = party.code }, "ok", "party_join")
		T.eq(#LS.PartyOf(a).members, 2, "zwei Mitglieder")
		act(T, g, a, "lobby_mode", { mode = "openworld" }, "ok")
		act(T, g, a, "lobby_go", {}, "ok", "Leiter reist, Mitglied kommt mit")
		T.eq(g:Session(a).mode, "openworld", "Anna in der Open World")
		T.eq(g:Session(b).mode, "openworld", "Ben in der Open World")
		-- Tutorial läuft für beide (neue Profile); die Story ist davon unabhängig
		act(T, g, a, "tutorial_skip", {}, "ok")
		act(T, g, b, "tutorial_skip", {}, "ok")
		act(T, g, a, "story_start", { id = "c1_m1" }, "ok", "Anna startet c1_m1")
		act(T, g, b, "story_start", { id = "c1_m1" }, "ok", "Ben startet c1_m1")
		T.eq(da.games.story.active.party, 2, "Party-Größe beim Start gemerkt")
		-- Anna verkauft am Kiesplatz: Ben bekommt den Fortschritt (mini_notice mission coop, Toast)
		local m = g:Mark()
		local n = sell(T, g, a, 1)
		T.check(n ~= nil and n.sold == true, "Anna verkauft")
		T.eq(da.games.story.active.progress, 1, "Anna 1/3")
		T.eq(db.games.story.active.progress, 1, "Ben 1/3 (Co-op)")
		local coop = missionNotice(g, b, "c1_m1", m)
		T.check(coop ~= nil and coop.coop == true and coop.from == "Anna" and coop.progress == 1, "Ben: mini_notice mission coop von Anna")
		T.check(g:HasToast(b, "Party: Anna", m), "Ben: Co-op-Toast")
		-- Ben passiv: bekommt nichts mehr; Anna weiter
		act(T, g, b, "ow_passive", { on = true }, "ok", "Ben passiv")
		T.eq(OWR.IsPassive(db), true, "Ben passiv")
		sell(T, g, a, 1)
		T.eq(da.games.story.active.progress, 2, "Anna 2/3")
		T.eq(db.games.story.active.progress, 1, "Ben bleibt bei 1 (passiv)")
		act(T, g, b, "ow_passive", { on = false }, "ok", "Ben wieder aktiv")
		m = g:Mark()
		sell(T, g, a, 1)
		T.eq(da.games.story.active.progress, 3, "Anna 3/3")
		T.eq(db.games.story.active.progress, 2, "Ben 2/3")
		local doneA = missionNotice(g, a, "c1_m1", m)
		T.check(doneA ~= nil and doneA.done == true, "Anna erledigt")
		-- Belohnung holt jeder selbst: Ben noch nicht fertig
		local moneyB = db.money
		act(T, g, b, "story_claim", { id = "c1_m1" }, "ok", "Ben: Abholen zu früh -> Toast")
		T.eq(db.money, moneyB, "Ben: nichts abgeholt")
		T.eq(db.games.story.done.c1_m1, nil, "Ben: nicht erledigt")
		local moneyA = da.money
		act(T, g, a, "story_claim", { id = "c1_m1" }, "ok", "Anna holt ab")
		T.eq(da.money - moneyA, 150, "Anna: 150 Cr Belohnung")
		T.eq(da.games.story.done.c1_m1, true, "Anna: erledigt")
		-- Ben verkauft selbst den dritten: fertig; Anna (andere Mission aktiv/keine) bekommt nichts
		sell(T, g, b, 1)
		T.eq(db.games.story.active.progress, 3, "Ben 3/3")
		T.eq(da.games.story.active, false, "Anna: keine aktive Mission mehr")
		act(T, g, b, "story_claim", { id = "c1_m1" }, "ok", "Ben holt ab")
		T.eq(db.games.story.done.c1_m1, true, "Ben: erledigt")
		-- Party verlassen: kein Co-op mehr
		act(T, g, b, "party_leave", {}, "ok", "Ben verlässt die Party")
		act(T, g, a, "story_start", { id = "c1_m2" }, "ok")
		act(T, g, b, "story_start", { id = "c1_m2" }, "ok")
		local Flow = H.Load("tests/lib/garage_flow.lua")
		T.check(Flow.CompleteInspection(T, g, a) ~= nil, "Anna rechnet ab")
		T.eq(da.games.story.active.progress, 1, "Anna 1/1")
		T.eq(db.games.story.active.progress, 0, "Ben ohne Party: 0")
		noErrors(T, g, "Co-op")
	end },

	{ "Client: Tabs story und buildings im Panel, Kiesplatz-Station öffnet den Story-Tab, Karten aus dem echten Snapshot, Absichten ohne Beträge", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW })
		local pl, d = join(g, 6201, "Tester")
		act(T, g, pl, "tutorial_skip", {}, "ok")
		levelTo(g, d, 12)
		g:MiniShared("MiniRules").AddMoney(d, 20000)
		g:StartClient(pl, { run = true })
		g:Advance(2.5)
		local MiniUI = g:ClientModule(pl, "Mini.MiniUI")
		T.check(MiniUI.Pages.story ~= nil and MiniUI.Pages.buildings ~= nil, "Seiten story und buildings gebaut")
		T.eq(MiniUI.TabTitles.story ~= nil and MiniUI.TabTitles.buildings ~= nil, true, "Tab-Titel vorhanden")
		-- Station Kiesplatz: mini_open { tab = "story" } öffnet den Tab im Client
		local m = openCityStation(g, pl, "kiesplatz")
		local open = g:Events(pl, "mini_open", m)[1]
		T.check(open ~= nil and open.tab == "story", "mini_open story")
		g:Advance(1.1)
		local MiniClient = g:ClientModule(pl, "Mini.MiniClient")
		T.check(MiniClient.IsOpen() and MiniUI.CurrentTab == "story", "Story-Tab offen (" .. tostring(MiniUI.CurrentTab) .. ")")
		local gui = pl.PlayerGui:FindFirstChild("Minispiele") or MiniUI.Gui
		local function byName(root, name)
			for _, x in ipairs(root:GetDescendants()) do
				if x.Name == name then
					return x
				end
			end
			return nil
		end
		T.check(byName(MiniUI.Pages.story, "ChapterCard") ~= nil, "Kapitel-Karte")
		-- Kunde da -> Verkaufskarte mit Preisknöpfen; Klick sendet story_sell { offer, price } (zwei Felder, kein Betrag)
		local offer = customer(g, pl)
		T.check(offer ~= nil, "Kunde")
		g:Advance(1.6)
		local priceButton = byName(MiniUI.Pages.story, "Price_2")
		T.check(priceButton ~= nil and priceButton.Visible, "Preisknopf Stufe 2 sichtbar")
		local Command = g:Remote("Command")
		local sent = {}
		local conn = Command.OnServerEvent:Connect(function(_, action, payload)
			if action == "story_sell" then
				table.insert(sent, payload)
			end
		end)
		if priceButton then
			g:Click(priceButton)
			g:Advance(0.6)
		end
		T.check(#sent == 1 and sent[1].offer == offer.serial and sent[1].price == 2 and sent[1].amount == nil and sent[1].credits == nil, "story_sell { offer, price } gesendet")
		conn:Disconnect()
		-- Gebäude-Tab: Karten je Typ, Bauen sendet ow_build { typ }
		MiniClient.Open("buildings")
		g:Advance(1.1)
		T.eq(MiniUI.CurrentTab, "buildings", "Gebäude-Tab offen")
		local BuildingsUI = g:ClientModule(pl, "Mini.BuildingsUI")
		local items = BuildingsUI.Items and BuildingsUI.Items() or nil
		T.check(type(items) == "table" and items.autohaus ~= nil and items.werkstatt ~= nil, "Karten je Gebäudetyp")
		local sentBuild = {}
		local conn2 = Command.OnServerEvent:Connect(function(_, action, payload)
			if action == "ow_build" then
				table.insert(sentBuild, payload)
			end
		end)
		local buildButton = items and items.autohaus and items.autohaus.buildButton
		if buildButton then
			g:Click(buildButton)
			g:Advance(1.6)
		end
		T.check(#sentBuild >= 1 and sentBuild[1].typ == "autohaus" and sentBuild[1].price == nil and sentBuild[1].cost == nil, "ow_build { typ } gesendet")
		T.eq(g:MiniShared("OWRules").StageOf(d, "autohaus"), 1, "Server hat gebaut (Baustelle)")
		noErrors(T, g, "Client")
	end },

	{ "Regressionen (Ende-zu-Ende): keine Kunden fern vom Kiesplatz, Kunden-Takt über Lobby/Rejoin, Nebenmissionen nur nach gelungenen Aktionen, abgebrochene Spielhallen-Runde, Lieferung bei schneller Durchfahrt, keine Snapshot-Flut der Baustelle", function(T, H)
		-- Tag, an dem Lieferung, Schrott-Tausch und Spielhalle in der Tagesauswahl (Level 12) liegen
		local probe = H.Garage({ noServer = true })
		local SRp = probe:MiniShared("StoryRules")
		local dayAt
		for k = 0, 5000 do
			local ids = SRp.DailyIds(SRp.DayKey(NOW + k * DAY), 12)
			local has = {}
			for _, id in ipairs(ids) do
				has[id] = true
			end
			if has.s_delivery and has.s_press and has.s_arcade then
				dayAt = NOW + k * DAY
				break
			end
		end
		T.check(dayAt ~= nil, "Tag mit Lieferung, Tausch und Spielhalle gefunden")
		local g = H.Garage({ placeKind = "all", startTime = dayAt, level = 12 })
		local SR = g:MiniShared("StoryRules")
		local SS = g:MiniServer("StoryService")
		local MR = g:MiniShared("MiniRules")
		local MC = g:MiniShared("MiniConfig")
		local CR = g:MiniShared("CarRules")
		local Sale = SR.Config().Sale
		local pl, d = join(g, 6301, "Timo")
		T.eq(d.level, 12, "Level 12")
		act(T, g, pl, "tutorial_skip", {}, "ok")
		act(T, g, pl, "lobby_mode", { mode = "openworld" }, "ok")
		act(T, g, pl, "lobby_go", {}, "ok")
		T.eq(g:Session(pl).mode, "openworld", "Open World")
		local function state()
			return g:MiniState(pl)
		end
		local function noGone(since, what)
			T.check(not g:HasToast(pl, "keine Lust mehr", since), what .. ": kein „keine Lust mehr“-Hinweis")
		end

		---------------------------------------------------------------- Kunden nur am Kiesplatz, Abschied nur vor Ort
		g:Teleport(pl, g:Station(pl, "workshop"), Vector3.new(0, 0, 3))
		local m = g:Mark()
		g:Advance(60)
		T.eq(SS.Offer(state()), false, "in der Werkstatt kommt kein Kunde")
		noGone(m, "Werkstatt")
		local o1 = customer(g, pl)
		T.check(o1 ~= nil, "am Kiesplatz kommt der Kunde")
		g:Teleport(pl, g:Station(pl, "workshop"), Vector3.new(0, 0, 3))
		m = g:Mark()
		g:Advance(Sale.Patience + 5)
		T.eq(SS.Offer(state()), false, "Kunde nach der Geduld weg")
		noGone(m, "weit weg")
		T.eq(story(g, pl).sales.serial, o1.serial, "Serial rückt vor")
		local o2 = customer(g, pl)
		T.check(o2 ~= nil and o2.serial == o1.serial + 1, "zurück am Kiesplatz: neuer Kunde (Serial + 1)")
		m = g:Mark()
		g:Advance(Sale.Patience + 5)
		T.eq(SS.Offer(state()), false, "zweiter Kunde nach der Geduld weg")
		T.check(g:HasToast(pl, "keine Lust mehr", m), "vor Ort: Abschieds-Hinweis")

		---------------------------------------------------------------- Kunden-Takt über Lobby-Hin-und-Zurück und Rejoin
		local o3 = customer(g, pl)
		T.check(o3 ~= nil, "Kunde")
		act(T, g, pl, "story_sell", { offer = o3.serial, price = 1 }, "ok", "Verkauf")
		T.check(story(g, pl).sales.nextAt >= g:Now() + 40, "sales.nextAt ≈ +45 s")
		act(T, g, pl, "lobby_return", {}, "ok")
		T.eq(g:Session(pl).mode, "lobby", "Lobby")
		act(T, g, pl, "lobby_go", {}, "ok")
		T.eq(g:Session(pl).mode, "openworld", "wieder Open World")
		local st = cityStation(g, "kiesplatz")
		local arrival = st and st:FindFirstChild("Arrival")
		g:Teleport(pl, arrival and arrival.WorldPosition or st.Position, arrival and nil or Vector3.new(0, 3, 4))
		g:Advance(10)
		T.eq(SS.Offer(state()), false, "Lobby-Hin-und-Zurück: kein früherer Kunde")
		g:Advance(40)
		T.check(SS.Offer(state()) ~= false, "nach 45 s kommt der nächste Kunde")
		local o4 = SS.Offer(state())
		act(T, g, pl, "story_sell", { offer = o4.serial, price = 1 }, "ok", "zweiter Verkauf")
		local nextAt = story(g, pl).sales.nextAt
		g:Leave(pl)
		g:Advance(1)
		pl, d = join(g, 6301, "Timo")
		T.eq(d.games.story.sales.nextAt, nextAt, "nextAt gespeichert und geladen")
		act(T, g, pl, "lobby_go", {}, "ok")
		T.eq(g:Session(pl).mode, "openworld", "nach Rejoin Open World")
		g:Teleport(pl, arrival and arrival.WorldPosition or st.Position, arrival and nil or Vector3.new(0, 3, 4))
		g:Advance(10)
		T.eq(SS.Offer(state()), false, "Rejoin: kein früherer Kunde")
		g:Advance(40)
		T.check(SS.Offer(state()) ~= false, "nach dem Takt wieder ein Kunde")

		---------------------------------------------------------------- Nebenmissionen: nur gelungene Aktionen zählen
		local function sideN(id)
			local e = story(g, pl).side[id]
			return e and e.n or 0
		end
		d.games.press.scrap = 0
		m = g:Mark()
		for _ = 1, 3 do
			act(T, g, pl, "mini_press_exchange", { index = 1 }, "ok", "Tausch ohne Schrott -> Toast")
		end
		T.check(g:HasToast(pl, "Nicht genug Schrott", m), "Toast: nicht genug Schrott")
		T.eq(sideN("s_press"), 0, "abgelehnter Tausch zählt nicht")
		d.games.press.scrap = MC.ScrapExchangePackages[1] * 2
		act(T, g, pl, "mini_press_exchange", { index = 1 }, "ok", "echter Tausch")
		T.eq(sideN("s_press"), 1, "gelungener Tausch zählt")
		act(T, g, pl, "mini_press_exchange", { index = 1 }, "ok", "zweiter echter Tausch")
		T.eq(sideN("s_press"), 2, "zwei Tauschgeschäfte")
		local sideBefore = H.Copy(story(g, pl).side)
		m = g:Mark()
		act(T, g, pl, "mini_carwash", {}, "ok", "Waschstraße ohne Auto -> Toast")
		act(T, g, pl, "mini_auction_bid", { lot = 987654, amount = 1 }, "ok", "Gebot auf ein Los, das es nicht gibt -> Toast")
		T.eq(#g:Notices(pl, "mission", m), 0, "abgelehnte Aktionen: kein Missions-Hinweis")
		T.check(H.DeepEqual(story(g, pl).side, sideBefore), "abgelehnte Aktionen ändern keine Nebenmission")
		-- Spielhalle: sofort beendete Runde (abgebrochen, 0 Punkte) zählt nicht
		m = g:Mark()
		act(T, g, pl, "mini_arcade_start", { game = "arcade_1" }, "ok", "Runde starten")
		local rounds = g:Notices(pl, "arcade_round", m)
		T.check(#rounds >= 1 and rounds[#rounds].token ~= nil, "Rundenpaket")
		act(T, g, pl, "mini_arcade_finish", { token = rounds[#rounds].token }, "ok", "sofort beenden")
		local results = g:Notices(pl, "arcade_result", m)
		T.check(#results == 1 and results[1].aborted == true and results[1].score == 0, "Runde abgebrochen mit 0 Punkten")
		T.eq(sideN("s_arcade"), 0, "abgebrochene Runde zählt nicht für „Dreimal Spielhalle“")

		---------------------------------------------------------------- Lieferung: Durchfahrt mit Tempo (Segment statt Punktprobe)
		local car = CR.GrantModel(d, "komet", g:Now())
		T.check(car ~= nil, "Auto in der Garage")
		act(T, g, pl, "mini_car_spawn", { id = car.id, at = "workshop" }, "ok", "Auto gespawnt")
		local model = g:Find("Workspace.PlayerCars.Car_6301")
		local chassis = model and model:FindFirstChild("Chassis")
		T.check(chassis ~= nil, "Rumpf des eigenen Autos")
		local route = g:Find("Workspace.City.Missions.Delivery_1")
		local start, finish
		for _, x in ipairs(route:GetChildren()) do
			if x:IsA("BasePart") and x:GetAttribute("Role") == "start" then
				start = x
			elseif x:IsA("BasePart") and x:GetAttribute("Role") == "end" then
				finish = x
			end
		end
		T.check(start ~= nil and finish ~= nil, "Lieferroute 1")
		chassis.CFrame = CFrame.new(start.Position + Vector3.new(0, 2, 0))
		m = g:Mark()
		g:Advance(1.2)
		T.check(type(SS.Delivery(state())) == "table", "Lieferung gestartet")
		T.check(g:HasToast(pl, "Lieferung 1 gestartet", m), "Start-Toast")
		-- 30 Studs vor dem Ziel (Sprung > MaxStep: nur Punktprobe, nicht im Ziel) …
		chassis.CFrame = CFrame.new(finish.Position + Vector3.new(-30, 2, 0))
		g:Advance(0.6)
		T.check(type(SS.Delivery(state())) == "table", "30 Studs vor dem Ziel: noch unterwegs")
		-- … und in einem Tick 60 Studs weiter: die Strecke führt durch das Zielfeld
		chassis.CFrame = CFrame.new(finish.Position + Vector3.new(30, 2, 0))
		g:Advance(0.6)
		T.eq(SS.Delivery(state()), false, "Durchfahrt erkannt: Lieferung abgeliefert")
		T.check(g:HasToast(pl, "abgeliefert", m), "Ziel-Toast")
		T.eq(sideN("s_delivery"), 1, "Lieferung gezählt")
		local dn = g:Notices(pl, "story", m)
		T.check(dn[#dn] and dn[#dn].event == "delivery" and dn[#dn].state == "done", "mini_notice delivery done")

		---------------------------------------------------------------- Baustelle: kein Snapshot je Sekunde
		MR.AddMoney(d, 100000)
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok", "Autohaus bauen (Baustelle 10 Min.)")
		T.check(g:MiniShared("OWRules").InProgress(d, "autohaus"), "Baustelle läuft")
		g:Advance(1.1)
		m = g:Mark()
		g:Advance(12)
		-- Leichte Produktions-Snapshots (Presse, 1×/s) sind normal; die Baustelle darf keinen VOLLEN Snapshot je Sekunde
		-- erzwingen (voll = mit story.missions/Katalog; vorher: ms.dirty jede Sekunde über OWService.Tick)
		local full, light = 0, 0
		for _, snap in ipairs(g:Events(pl, "mini", m)) do
			if type(snap) == "table" and type(snap.story) == "table" and snap.story.missions ~= nil then
				full += 1
			else
				light += 1
			end
		end
		T.check(full <= 3, "Baustelle: höchstens 3 volle Snapshots in 12 s statt einem je Sekunde (" .. tostring(full) .. " voll, " .. tostring(light) .. " leicht)")
		T.check(g:MiniSnapshot(pl).ow.buildings.autohaus.remaining > 0, "letzter Snapshot kennt die Restzeit (Client zählt lokal weiter)")
		noErrors(T, g, "Regressionen")
	end },
}
