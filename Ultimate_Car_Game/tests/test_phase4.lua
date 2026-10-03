-- Ausbaustufe 4, Meilensteine 1–3 Ende-zu-Ende über die echte Verkabelung (H.Garage mit placeKind "all",
-- Remotes.Command -> request -> Mini.Handle, echte Stationen aus tools/worldgen): Lobby -> Einstellungen ->
-- Reise (Simulation) -> Tutorial bis zum Ende über echte Werkstatt-Ereignisse -> Level-Aufstieg mit
-- Freischaltungs-Hinweis -> Prestige-Abholung unter Rang 1 abgelehnt -> Speichern/Laden; lobby_return; Party zu
-- zweit; Veteran ohne meta; Freischaltungs-Sperren; Client (Lobby öffnet sich, Sperrhinweis).
local HUB = { lobby = { 0, -668 }, openworld = { 0, -192 }, tycoon = { 0, 856 } }

local function rootPos(g, pl)
	local root = g:Root(pl)
	return root and root.Position or nil
end

local function near(T, pos, x, z, tol, msg)
	T.check(pos ~= nil, msg .. ": keine Figur")
	if pos then
		T.check(math.abs(pos.X - x) <= tol and math.abs(pos.Z - z) <= tol, string.format("%s – erwartet ≈(%g, %g), erhalten (%g, %g)", msg, x, z, pos.X, pos.Z))
	end
end

local function join(g, userId, name)
	local pl = g:Join(userId, { name = name })
	g:Advance(1.1)
	g:Send(pl, "hello")
	g:Advance(1.1)
	return pl, g:D(pl), g:Session(pl)
end

local function cityStation(g, key)
	local city = g:Find("Workspace.City.Stations")
	return city and city:FindFirstChild(key)
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

local function step(g, d)
	return g:MiniShared("TutorialRules").StepIndex(d)
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, what .. ": keine Fehler: " .. g:ErrorText())
end

return {
	{ "Neues Profil: Lobby → Einstellungen → lobby_go (Simulation) → Tutorial über echte Werkstatt-Ereignisse → Level-Aufstieg → Prestige → Speichern/Laden", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local MiniRules = g:MiniShared("MiniRules")
		local pl, d, p = join(g, 4001, "Anna")
		-- Erster Beitritt im all-Place: Lobby, Figur an der Lobby-Ankunft, Snapshot mit mode/meta/tutorial/prestige/unlocks
		T.eq(p.mode, "lobby", "Anfangsmodus lobby")
		near(T, rootPos(g, pl), HUB.lobby[1], HUB.lobby[2], 8, "Figur in der Lobby-Halle")
		local snap = g:MiniSnapshot(pl)
		T.check(snap ~= nil, "Minispiel-Snapshot")
		T.eq(snap and snap.mode, "lobby", "snapshot.mode")
		T.eq(snap and snap.placeKind, "all", "snapshot.placeKind")
		T.eq(snap and snap.meta and snap.meta.beginner, true, "meta.beginner")
		T.eq(snap and snap.meta and snap.meta.tutorialDone, false, "meta.tutorialDone")
		T.eq(snap and snap.tutorial and snap.tutorial.step, 1, "tutorial.step 1")
		T.eq(snap and snap.prestige and snap.prestige.rank, 0, "prestige.rank 0")
		T.check(snap and snap.unlocks and type(snap.unlocks.list) == "table" and #snap.unlocks.list > 10, "unlocks.list im vollen Snapshot")
		T.check(snap and snap.unlocks and snap.unlocks.next and snap.unlocks.next.level == 2, "nächste Freischaltung Level 2")
		T.eq(snap and snap.party, false, "keine Party")
		for _, n in ipairs(g:Notices(pl, "tutorial")) do
			T.check(n.started ~= true, "in der Lobby startet das Tutorial nicht (started)")
		end
		-- In der Lobby ruht das Tutorial (§6: Pflicht beim ersten Beitritt in der Open World): kein Hinweis, keine
		-- Karte (active = false), tutorial_next bringt keinen Fortschritt
		T.eq(#g:Notices(pl, "tutorial"), 0, "in der Lobby kein tutorial-Hinweis")
		T.eq(snap and snap.tutorial and snap.tutorial.active, false, "Lobby: tutorial.active false")
		T.eq(snap and snap.tutorial and snap.tutorial.text, "", "Lobby: kein Schritt-Text")
		local mLobby = g:Mark()
		T.eq(g:Act(pl, "tutorial_next", { step = 1, rid = 90 }), "ok", "tutorial_next in der Lobby -> Toast")
		T.eq(step(g, d), 1, "Lobby: kein Fortschritt")
		T.check(g:HasToast(pl, "Spielermeile", mLobby), "Toast: Tutorial läuft in der Spielermeile")
		T.eq(#g:Notices(pl, "hint", mLobby), 0, "kein Tutorial-Hinweis in der Lobby")
		-- Einstellungen (nur Booleans, sofort im Profil)
		T.eq(g:Act(pl, "lobby_settings", { single = false, passive = true, beginner = true, rid = 1 }), "ok", "lobby_settings")
		T.eq(d.games.meta.passive, true, "passive gespeichert")
		T.eq(g:Act(pl, "lobby_settings", { single = "ja", passive = true, beginner = true, rid = 2 }), "invalid", "Typprüfung")
		g:Advance(0.5)
		T.eq(g:Act(pl, "lobby_settings", { single = false, passive = false, beginner = true, rid = 3 }), "ok", "zurück")
		-- Reise in die Open World (Simulation: Place-Ids 0)
		g:Advance(0.5)
		T.eq(g:Act(pl, "lobby_mode", { mode = "mars", rid = 4 }), "ok", "lobby_mode unbekannt -> Toast")
		T.check(g:HasToast(pl, "gibt es nicht"), "Toast unbekannter Modus")
		g:Advance(0.5)
		T.eq(g:Act(pl, "lobby_mode", { mode = "openworld", rid = 5 }), "ok", "lobby_mode openworld")
		local m = g:Mark()
		g:Advance(0.5)
		T.eq(g:Act(pl, "lobby_go", { rid = 6 }), "ok", "lobby_go")
		T.eq(p.mode, "openworld", "Modus openworld")
		T.eq(d.games.meta.lastMode, "openworld", "lastMode gespeichert")
		local modeNotice = g:Notices(pl, "mode", m)[1]
		T.check(modeNotice ~= nil and modeNotice.simulated == true and modeNotice.mode == "openworld", "mini_notice mode (Simulation)")
		-- Neuer Spieler mit Pflicht-Tutorial: Ankunft in der eigenen Werkstatt („Willkommen in deiner Werkstatt“,
		-- Schritt 3 „Geh zum Empfang“), nicht am Stadt-Hub (bis zu 500 Studs entfernt)
		local homeStation = g:Station(pl, "home")
		T.check(homeStation and (rootPos(g, pl) - homeStation.Position).Magnitude < 12, "Figur in der eigenen Werkstatt (Tutorial)")
		g:Advance(1.1)
		T.eq(g:MiniSnapshot(pl).mode, "openworld", "Snapshot mode openworld")
		-- Startwahl zuerst (neues Profil): das Tutorial wartet, bis ein Startweg gewählt ist
		T.eq(#g:Notices(pl, "tutorial", m), 0, "kein Tutorial vor der Startwahl")
		T.check(#g:Notices(pl, "start", m) >= 1, "Startwahl angeboten (mini_notice start)")
		T.check(g:MiniSnapshot(pl).start and g:MiniSnapshot(pl).start.pending == true, "Snapshot start.pending")
		T.eq(g:Act(pl, "start_choose", { path = "werkstatt", rid = 60 }), "ok", "start_choose werkstatt")
		g:Advance(0.6)
		-- Pflicht-Tutorial beim ersten Open-World-Beitritt
		local started = g:Notices(pl, "tutorial", m)
		T.check(#started >= 1 and started[1].started == true and started[1].step == 1, "Tutorial gestartet (Schritt 1)")
		-- 1, 2: Lese-Schritte (Client sendet tutorial_next)
		T.eq(g:Act(pl, "tutorial_next", { step = 1, rid = 10 }), "ok", "Weiter 1")
		T.eq(step(g, d), 2, "Schritt 2")
		g:Advance(0.3)
		T.eq(g:Act(pl, "tutorial_next", { step = 2, rid = 11 }), "ok", "Weiter 2")
		T.eq(step(g, d), 3, "Schritt 3 (Empfang)")
		-- 3: Empfang der eigenen Werkstatt (2.4.0-Tablet-Navigation 'travel' -> Mini.OnStation)
		m = g:Mark()
		g:Send(pl, "travel", { key = "workshop" })
		T.eq(step(g, d), 4, "Schritt 4 (Auftrag annehmen)")
		local hints = g:Notices(pl, "hint", m)
		T.check(#hints == 1 and hints[1].id == "h_workshop", "Beginner-Hinweis zum Empfang")
		-- 4..6: echter Auftrag (Tick erkennt die Phasen)
		local j = Flow.AcceptInspection(T, g, pl)
		T.check(j ~= nil, "Auftrag angenommen")
		g:Advance(1.1)
		T.eq(step(g, d), 5, "Schritt 5 (OBD)")
		local C = g:Config()
		local def = C.JobById[j.kind]
		local diag = Flow.Scan(T, g, pl, j.id)
		T.check(diag ~= nil, "diagnose-Event")
		g:Send(pl, "diagnose", { id = j.id, choice = def.cause })
		g:Advance(1.1)
		T.eq(step(g, d), 6, "Schritt 6 (Reparatur)")
		for i = 1, #def.steps do
			T.check(Flow.RepairStep(T, g, pl, j.id, i), "Reparaturschritt " .. i)
		end
		Flow.Scan(T, g, pl, j.id)
		T.eq(Flow.Job(g, pl, j.id) and Flow.Job(g, pl, j.id).phase, "invoice", "Phase invoice")
		g:Advance(1.1)
		T.eq(step(g, d), 7, "Schritt 7 (Abrechnen)")
		-- 7: Abrechnen (act 'settle' -> Mini.OnSettled)
		g:Teleport(pl, g:Station(pl, "workshop"), Vector3.new(0, 0, 3))
		g:Advance(0.3)
		m = g:Mark()
		g:Send(pl, "settle", { id = j.id })
		T.check(g:Last(pl, "receipt", m) ~= nil, "Quittung")
		T.eq(step(g, d), 8, "Schritt 8 (Stadtplan)")
		T.eq(d.games.stats.jobsDone, 1, "jobsDone")
		local firstJob = false
		for _, h in ipairs(g:Notices(pl, "hint", m)) do
			if h.id == "h_first_job" then
				firstJob = true
			end
		end
		T.check(firstJob, "Hinweis first:jobsDone")
		-- 8: Schnellreise in die Stadt (nur eine gelungene Reise zählt)
		g:Advance(3.1)
		T.eq(g:Act(pl, "mini_travel", { key = "gibt_es_nicht", rid = 20 }), "ok", "mini_travel unbekannt -> Toast")
		T.eq(step(g, d), 8, "fehlgeschlagene Reise zählt nicht")
		g:Advance(3.1)
		T.eq(g:Act(pl, "mini_travel", { key = "hub", rid = 21 }), "ok", "mini_travel hub")
		T.eq(step(g, d), 9, "Schritt 9 (Autohaus)")
		near(T, rootPos(g, pl), HUB.openworld[1], HUB.openworld[2], 8, "Figur an der Stadt-Ankunft (Schnellreise)")
		-- 9, 10: Stadt-Stationen (ProximityPrompt -> MiniService.openStation)
		m = openCityStation(g, pl, "goals")
		T.eq(step(g, d), 9, "Infotafel zu früh")
		T.check(g:Events(pl, "mini_open", m)[1] ~= nil and g:Events(pl, "mini_open", m)[1].tab == "goals", "Tab goals geöffnet")
		T.eq(d.level, 1, "noch Level 1 (Autohaus ab 3 gesperrt)")
		m = openCityStation(g, pl, "dealer")
		T.eq(step(g, d), 10, "Schritt 10 (Ziele)")
		-- Tutorial-Station mit Level-Sperre: der Tab öffnet trotzdem (nur ansehen), kein Sperr-Toast
		local openDealer = g:Events(pl, "mini_open", m)[1]
		T.check(openDealer ~= nil and openDealer.tab == "dealer", "Autohaus öffnet im Tutorial auch auf Level 1")
		T.check(not g:HasToast(pl, "Ab Level 3", m), "kein Sperr-Toast im Tutorial-Schritt")
		T.eq(g:Act(pl, "mini_car_buy", { model = "komet", rid = 19 }), "locked", "Kauf bleibt gesperrt")
		m = openCityStation(g, pl, "goals")
		T.eq(step(g, d), 11, "Schritt 11 (Kiesplatz)")
		T.check(not d.games.meta.tutorialDone, "Infotafel beendet das Tutorial noch nicht")
		-- 11: Kiesplatz (Meilenstein 7): Station mit MiniTab story öffnet den Story-Tab und beendet das Tutorial
		local money, xp, level = d.money, d.xp, d.level
		m = openCityStation(g, pl, "kiesplatz")
		T.check(g:Events(pl, "mini_open", m)[1] ~= nil and g:Events(pl, "mini_open", m)[1].tab == "story", "Tab story geöffnet")
		T.check(d.games.meta.tutorialDone and not d.games.meta.tutorialSkipped, "Tutorial beendet")
		local fin = g:Notices(pl, "tutorial", m)
		T.check(#fin >= 1 and fin[#fin].finished == true and fin[#fin].done == true, "tutorial-Hinweis finished")
		T.check(d.money - money >= 500, "500 Credits Belohnung (" .. tostring(d.money - money) .. ")")
		T.check(d.level > level or d.xp == xp + 60, "60 XP")
		T.check(g:HasToast(pl, "Tutorial geschafft", m), "Toast Tutorial geschafft")
		g:Advance(1.1)
		local st = g:State(pl)
		T.check(st and st.data.money == d.money, "2.4.0-state trägt das neue Guthaben")
		-- Level-Aufstieg: Freischaltungs-Hinweise (Presse ab 2, Schrottplatz/Autohaus/Komet ab 3)
		m = g:Mark()
		local before = d.level
		MiniRules.GainXP(d, 100000)
		T.check(d.level >= 3, "Level gestiegen (" .. tostring(d.level) .. ")")
		g:Advance(1.1)
		local unlocks = g:Notices(pl, "unlock", m)
		local keys = {}
		for _, u in ipairs(unlocks) do
			keys[u.key] = u
		end
		T.check(keys["feature:press"] ~= nil and keys["feature:press"].level == 2, "unlock feature:press")
		T.check(keys["feature:press"] and keys["feature:press"].hint ~= nil, "Beginner-Hinweis reist im unlock-Hinweis mit")
		T.eq(d.games.meta.hintsSeen.h_press, true, "h_press gemerkt")
		T.check(keys["car:komet"] ~= nil, "unlock car:komet")
		snap = g:MiniSnapshot(pl)
		T.check(snap and snap.unlocks and snap.unlocks.unseen and snap.unlocks.unseen >= 2, "unlocks.unseen > 0")
		T.eq(g:Act(pl, "unlocks_seen", { rid = 30 }), "ok", "unlocks_seen")
		g:Advance(1.1)
		T.eq(g:MiniSnapshot(pl).unlocks.unseen, 0, "gesehen")
		-- Prestige: Rang 1 erst ab Level 100
		m = g:Mark()
		T.eq(g:Act(pl, "prestige_claim", { rank = 1, rid = 31 }), "ok", "prestige_claim unter Rang 1 -> Toast")
		T.check(g:HasToast(pl, "Rang 1 gibt es ab Level 100", m), "Toast Rang 1 ab Level 100")
		T.eq(#d.games.prestige.claimed, 0, "nichts abgeholt")
		T.eq(g:Act(pl, "prestige_claim", { rank = "1", rid = 32 }), "invalid", "rank muss number sein")
		-- Speichern/Laden: meta bleibt (Tutorial erledigt, Hinweise gesehen, lastMode openworld)
		g:Leave(pl)
		local rec = g:Record(4001)
		T.check(rec ~= nil and rec.data and rec.data.games and rec.data.games.meta, "Datensatz mit meta")
		T.eq(rec.data.games.meta.tutorialDone, true, "gespeichert tutorialDone")
		T.eq(rec.data.games.meta.lastMode, "openworld", "gespeichert lastMode")
		T.eq(rec.data.games.meta.hintsSeen.h_workshop, true, "gespeichert hintsSeen")
		T.eq(rec.data.games.prestige and #rec.data.games.prestige.claimed, 0, "gespeichert prestige")
		local pl2, d2, p2 = join(g, 4001, "Anna")
		T.eq(p2.mode, "openworld", "Wiederbeitritt im letzten Modus")
		T.eq(d2.games.meta.tutorialDone, true, "meta geladen")
		T.eq(d2.games.meta.hintsSeen.h_press, true, "hintsSeen geladen")
		local home = g:Station(pl2, "home")
		T.check(home and (rootPos(g, pl2) - home.Position).Magnitude < 12, "Open World: Figur wie bisher in der Werkstatt")
		T.eq(#g:Notices(pl2, "tutorial"), 0, "Tutorial startet nicht erneut")
		local snap2 = g:MiniSnapshot(pl2)
		T.check(snap2 and snap2.tutorial and snap2.tutorial.done == true, "Snapshot tutorial.done")
		noErrors(T, g, "Ablauf")
	end },

	{ "lobby_return und Party zu zweit: Leiter reist, Mitglied kommt mit; Mitglied darf nicht allein starten", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local LS = g:MiniServer("LobbyService")
		local a, _, pa = join(g, 4101, "Anna")
		local b, _, pb = join(g, 4102, "Ben")
		T.eq(pa.mode, "lobby", "Anna in der Lobby")
		T.eq(g:Act(a, "party_create", { rid = 1 }), "ok", "party_create")
		local party = LS.PartyOf(a)
		T.check(party ~= nil, "Party angelegt")
		local code = party and party.code or "????"
		g:Advance(0.5)
		T.eq(g:Act(b, "party_join", { code = string.lower(code), rid = 2 }), "ok", "party_join (Kleinschreibung)")
		T.eq(LS.PartyOf(b), party, "Ben in der Party")
		g:Advance(1.1)
		local snap = g:MiniSnapshot(b)
		T.check(snap and snap.party and snap.party.code == code and #snap.party.members == 2 and snap.party.isLeader == false, "Snapshot party")
		-- Mitglied darf nicht allein reisen
		g:Advance(0.5)
		T.eq(g:Act(b, "lobby_mode", { mode = "tycoon", rid = 3 }), "ok", "Ben wählt")
		local m = g:Mark()
		g:Advance(3.1)
		T.eq(g:Act(b, "lobby_go", { rid = 4 }), "ok", "lobby_go Ben")
		T.eq(pb.mode, "lobby", "Ben bleibt")
		T.check(g:HasToast(b, "Party-Leiter", m), "Toast nur der Leiter")
		-- Leiter reist: beide im Tycoon
		g:Advance(0.5)
		T.eq(g:Act(a, "lobby_mode", { mode = "tycoon", rid = 5 }), "ok", "Anna wählt")
		m = g:Mark()
		g:Advance(3.1)
		T.eq(g:Act(a, "lobby_go", { rid = 6 }), "ok", "lobby_go Anna")
		T.eq(pa.mode, "tycoon", "Anna im Tycoon")
		T.eq(pb.mode, "tycoon", "Ben mitgereist")
		near(T, rootPos(g, a), HUB.tycoon[1], HUB.tycoon[2], 8, "Anna an der Tycoon-Ankunft")
		near(T, rootPos(g, b), HUB.tycoon[1], HUB.tycoon[2], 8, "Ben an der Tycoon-Ankunft")
		local travel = g:Notices(b, "party", m)
		T.check(#travel >= 1 and travel[#travel].event == "travel" and travel[#travel].mode == "tycoon", "Ben erhält travel")
		g:Advance(1.1)
		T.eq(g:MiniSnapshot(b).mode, "tycoon", "Snapshot Ben tycoon")
		-- Tycoon mit Tycoon-Dienst (Meilenstein 4): Ankunfts-Toast „Viel Erfolg“, die Tycoon-Stationen
		-- öffnen den Tab „tycoon“ (kein „eröffnet bald“ mehr)
		T.check(g:HasToast(a, "Viel Erfolg", m), "Ankunfts-Toast: Tycoon")
		T.check(not g:HasToast(a, "eröffnet bald", m), "kein Toast eröffnet bald")
		local tst = g:Find("Workspace.Tycoon.Stations.tycoon")
		T.check(tst ~= nil, "Tycoon-Station tycoon")
		if tst then
			local arrivalT = tst:FindFirstChild("Arrival")
			g:Teleport(a, arrivalT and arrivalT.WorldPosition or tst.Position, arrivalT and nil or Vector3.new(0, 3, 4))
			g:Advance(0.2)
			local mt = g:Mark()
			g:Trigger(a, tst:FindFirstChildOfClass("ProximityPrompt"), { force = true })
			g:Advance(0.3)
			local openT = g:Events(a, "mini_open", mt)[1]
			T.check(openT ~= nil and openT.tab == "tycoon", "Tycoon-Station öffnet den Tab tycoon")
			T.check(not g:HasToast(a, "eröffnet bald", mt), "kein Hinweis eröffnet bald")
		end
		-- Mitglied kehrt allein zurück (Vertrag §5: lobby_return aus jedem Modus), Party und Leiter bleiben
		g:Advance(3.1)
		m = g:Mark()
		T.eq(g:Act(b, "lobby_return", { rid = 40 }), "ok", "lobby_return Mitglied")
		T.eq(pb.mode, "lobby", "Ben allein in der Lobby")
		T.eq(pa.mode, "tycoon", "Anna bleibt im Tycoon")
		T.eq(LS.PartyOf(b), party, "Ben bleibt in der Party")
		T.check(g:HasToast(b, "allein zurück", m), "Toast: allein zurück, Party bleibt")
		near(T, rootPos(g, b), HUB.lobby[1], HUB.lobby[2], 8, "Ben an der Lobby-Ankunft")
		T.eq(#g:Notices(a, "party", m), 0, "Leiter bekommt kein travel-Ereignis")
		-- Ben reist mit dem Leiter wieder mit (nur das Ziel zählt)
		g:Advance(3.1)
		T.eq(g:Act(a, "lobby_mode", { mode = "openworld", rid = 41 }), "ok", "Anna wählt Open World")
		g:Advance(0.5)
		T.eq(g:Act(a, "lobby_go", { rid = 42 }), "ok", "lobby_go Anna")
		T.eq(pb.mode, "openworld", "Ben mitgereist")
		g:Advance(3.1)
		T.eq(g:Act(a, "lobby_mode", { mode = "tycoon", rid = 43 }), "ok", "Anna wählt Tycoon")
		g:Advance(0.5)
		T.eq(g:Act(a, "lobby_go", { rid = 44 }), "ok", "lobby_go Anna zurück in den Tycoon")
		T.eq(pa.mode, "tycoon", "Anna im Tycoon")
		T.eq(pb.mode, "tycoon", "Ben im Tycoon")
		-- Respawn im Tycoon: Figur landet an der Zonen-Ankunft, nicht in der Werkstatt (Mini.OnCharacter)
		g:Respawn(a)
		g:Advance(1.1)
		near(T, rootPos(g, a), HUB.tycoon[1], HUB.tycoon[2], 8, "Anna nach Respawn an der Tycoon-Ankunft")
		-- zurück in die Lobby (Leiter nimmt die Party mit)
		g:Advance(3.1)
		T.eq(g:Act(a, "lobby_return", { rid = 7 }), "ok", "lobby_return")
		T.eq(pa.mode, "lobby", "Anna in der Lobby")
		T.eq(pb.mode, "lobby", "Ben mitgereist")
		near(T, rootPos(g, a), HUB.lobby[1], HUB.lobby[2], 8, "Anna an der Lobby-Ankunft")
		g:Advance(3.1)
		m = g:Mark()
		T.eq(g:Act(a, "lobby_return", { rid = 8 }), "ok", "lobby_return in der Lobby")
		T.check(g:HasToast(a, "schon in der Lobby", m), "Toast schon in der Lobby")
		-- Lobby-Station (Portal) wählt den Modus vor und öffnet den Lobby-Tab mit der Aktion
		local st = g:Find("Workspace.Lobby.Stations.mode_tycoon")
		T.check(st ~= nil, "Lobby-Station mode_tycoon")
		if st then
			g:Teleport(a, st.Arrival.WorldPosition)
			g:Advance(0.2)
			m = g:Mark()
			g:Trigger(a, st:FindFirstChildOfClass("ProximityPrompt"), { force = true })
			local open = g:Events(a, "mini_open", m)[1]
			T.check(open ~= nil and open.tab == "lobby" and open.action == "mode_tycoon", "mini_open lobby mit LobbyAction")
			local lobbyNotice = g:Notices(a, "lobby", m)[1]
			T.check(lobbyNotice ~= nil and lobbyNotice.action == "mode_tycoon" and lobbyNotice.hint ~= nil, "lobby-Hinweis mit Beginner-Hinweis (h_tycoon)")
			g:Advance(1.1)
			T.eq(g:MiniState(a).lobbyChoice, "tycoon", "Sitzung: Vorauswahl tycoon")
			T.eq(g:MiniSnapshot(a).choice, "tycoon", "Snapshot choice tycoon")
		end
		-- Leiter verlässt den Server: Ben wird Leiter (eigener Toast in korrekter Grammatik, kein Doppel-Hinweis)
		m = g:Mark()
		g:Leave(a)
		T.eq(party.leader, b, "Ben ist Leiter")
		T.check(g:HasToast(b, "Du bist jetzt Party-Leiter", m), "Toast: Du bist jetzt Party-Leiter.")
		T.check(not g:HasToast(b, "Du ist", m), "kein Grammatikfehler")
		local leaderNotices = 0
		for _, n in ipairs(g:Notices(b, "party", m)) do
			if n.event == "leader" then
				leaderNotices += 1
			end
		end
		T.eq(leaderNotices, 0, "neuer Leiter bekommt das leader-Ereignis nicht auch noch (kein zweiter Toast)")
		g:Advance(0.5)
		T.eq(g:Act(b, "party_leave", { rid = 9 }), "ok", "party_leave")
		T.eq(LS.Parties[code], nil, "Party aufgelöst")
		noErrors(T, g, "Party")
	end },

	{ "Veteran ohne meta lädt mit Standardwerten, Tutorial gilt als erledigt, Start in der Open World", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local R = g:Rules()
		local data = R.NewData(g:Now())
		data.completed = 12
		data.level = 7
		data.money = 4321
		data.games = nil -- 2.4.0-Profil ohne Minispiel-Daten
		g:Seed(4201, { version = 2, data = data, receipts = {} })
		local pl, d, p = join(g, 4201, "Veteran")
		T.eq(p.mode, "openworld", "Veteran startet in der Open World")
		T.eq(d.games.meta.tutorialDone, true, "Tutorial erledigt")
		T.eq(d.games.meta.tutorialSkipped, false, "nicht übersprungen")
		T.eq(d.games.meta.lastMode, "openworld", "lastMode openworld")
		T.eq(d.games.meta.beginner, true, "Standard: Beginner-Hinweise an")
		T.eq(d.games.stats.jobsDone, 12, "jobsDone aus completed")
		T.eq(d.games.prestige.titleRank, 0, "Prestige-Standard")
		-- Erstlings-Hinweise („Super, dein erster Auftrag!“, Empfang erklärt) passen nicht zu 12 Aufträgen
		T.eq(d.games.meta.hintsSeen.h_first_job, true, "Veteran: first:jobsDone gilt als gesehen")
		T.eq(d.games.meta.hintsSeen.h_workshop, true, "Veteran: station:workshop gilt als gesehen")
		T.eq(d.games.meta.tutorialRewarded, true, "Veteran: Tutorial-Belohnung gilt als verbucht")
		local TS = g:MiniServer("TutorialService")
		local m0 = g:Mark()
		local MiniRulesV = g:MiniShared("MiniRules")
		MiniRulesV.AddStat(d, "jobsDone", 1, g:Now())
		T.eq(TS.OnStat(g:MiniState(pl), d, "jobsDone"), 0, "13. Auftrag: kein Erstlings-Hinweis (nur beim Übergang 0 -> 1)")
		T.eq(#g:Notices(pl, "hint", m0), 0, "kein hint-Notice")
		-- Beginner ohne Vorgeschichte: erst der erste Auftrag (Wert 1) löst den Hinweis aus, ein späterer nie mehr
		local R2 = g:Rules()
		local dNew = R2.NewData(g:Now())
		g:MiniShared("MetaRules").ApplyDefault(dNew.games)
		dNew.games.stats.jobsDone = 2
		T.eq(g:MiniShared("MetaRules").HintFor(dNew, "first:jobsDone") ~= nil, true, "neues Profil: Hinweis noch offen")
		T.eq(TS.OnStat(g:MiniState(pl), dNew, "jobsDone"), 0, "Wert 2: kein Hinweis")
		dNew.games.stats.jobsDone = 1
		T.eq(TS.OnStat(g:MiniState(pl), dNew, "jobsDone"), 1, "Wert 1: Hinweis")
		T.eq(d.money, 4321, "Geld bleibt")
		T.eq(#g:Notices(pl, "tutorial"), 0, "kein Tutorial-Hinweis")
		local home = g:Station(pl, "home")
		T.check(home and (rootPos(g, pl) - home.Position).Magnitude < 12, "Figur in der Werkstatt")
		local snap = g:MiniSnapshot(pl)
		T.check(snap and snap.tutorial and snap.tutorial.done == true and snap.mode == "openworld", "Snapshot")
		-- Profil mit meta und gespeichertem Modus tycoon
		local data2 = R.NewData(g:Now())
		data2.games.meta.lastMode = "tycoon"
		data2.games.meta.tutorialDone = true
		g:Seed(4202, { version = 2, data = data2, receipts = {} })
		local pl2, _, p2 = join(g, 4202, "Tycoonist")
		T.eq(p2.mode, "tycoon", "gespeicherter Modus tycoon")
		near(T, rootPos(g, pl2), HUB.tycoon[1], HUB.tycoon[2], 8, "Figur am Tycoon-Gelände")
		noErrors(T, g, "Veteran")
	end },

	{ "Freischaltungen: gesperrte Aktionen antworten mit einem Toast, Stationen mit Level-Voraussetzung öffnen nicht", function(T, H)
		local g = H.Garage()
		local pl, d = join(g, 4301, "Neu")
		T.eq(d.level, 1, "Level 1")
		local m = g:Mark()
		T.eq(g:Act(pl, "mini_press_click", { count = 3 }), "locked", "Presse ab Level 2 gesperrt")
		T.check(g:HasToast(pl, "Ab Level 2: Schrottpresse", m), "Toast Ab Level 2")
		T.eq(d.games.press.clicks, 0, "keine Klicks gezählt")
		m = g:Mark()
		T.eq(g:Act(pl, "mini_press_click", { count = 3 }), "locked", "weiter gesperrt")
		T.eq(#g:Toasts(pl, m), 0, "Toast gedrosselt")
		T.eq(g:Act(pl, "mini_arcade_start", { game = "arcade_1", rid = 1 }), "locked", "Spielhalle ab Level 10")
		T.eq(g:Act(pl, "mini_car_buy", { model = "komet", rid = 2 }), "locked", "Komet ab Level 3")
		T.eq(g:Act(pl, "mini_car_buy", { model = "gibt_es_nicht", rid = 3 }), "ok", "unbekanntes Modell meldet CarRules")
		T.eq(g:Act(pl, "mini_auction_consign", { id = 1, start = 100, duration = 120, rid = 4 }), "locked", "Spieler-Auktionen ab Level 20")
		T.eq(g:Act(pl, "mini_quiz_new", { rid = 5 }), "locked", "Quiz ab Level 4")
		T.eq(g:Act(pl, "mini_daily_claim", { rid = 6 }), "ok", "Aktion ohne Voraussetzung läuft")
		-- Presse: Maschinen, Händler und Rebirth sind ebenfalls gesperrt; die Maschinen produzieren nicht
		T.eq(g:Act(pl, "mini_press_buy", { id = "pu1", level = 0, rid = 7 }), "locked", "mini_press_buy gesperrt")
		T.eq(g:Act(pl, "mini_press_exchange", { index = 1, rid = 8 }), "locked", "mini_press_exchange gesperrt")
		T.eq(g:Act(pl, "mini_press_rebirth", { rebirths = 0, rid = 9 }), "locked", "mini_press_rebirth gesperrt")
		T.eq(g:Act(pl, "mini_upgrade", { key = "scrapyardLevel", level = 1, rid = 10 }), "locked", "Schrottplatz-Ausbau gesperrt")
		T.eq(g:Act(pl, "mini_upgrade", { key = "tuningLevel", level = 1, rid = 11 }), "locked", "Tuning-Abteilung gesperrt")
		-- Tuning: passive Einnahmen werden vor Level 6 weder angesammelt noch ausgezahlt
		T.eq(g:Act(pl, "mini_tuning_idle", { rid = 12 }), "locked", "mini_tuning_idle gesperrt")
		T.eq(g:Act(pl, "mini_tuning_collect", { slot = 1, rid = 13 }), "locked", "mini_tuning_collect gesperrt")
		local money0 = d.money
		g.env.clock:Jump(3600)
		g:Advance(1.1)
		local TR = g:MiniShared("TuningRules")
		T.eq(TR.PendingIdle(d, g:Now()), 0, "keine passiven Einnahmen angespart (Uhr läuft mit)")
		T.eq(d.games.press.scrap, 0, "Presse produziert vor Level 2 keinen Schrott")
		T.eq(g:Act(pl, "mini_tuning_idle", { rid = 14 }), "locked", "nach einer Stunde weiter gesperrt")
		T.eq(d.money, money0, "Geld unverändert")
		-- Verlassen/Beitritt: auch offline nichts angespart
		g:Leave(pl)
		g.env.clock:Jump(3600)
		g:Advance(1)
		pl, d = join(g, 4301, "Neu")
		g:Advance(1.1)
		T.eq(TR.PendingIdle(d, g:Now()), 0, "offline nichts angespart")
		T.eq(d.games.press.scrap, 0, "kein Offline-Schrott vor Level 2")
		T.eq(#g:Notices(pl, "offline"), 0, "kein Offline-Hinweis")
		local snapL = g:MiniSnapshot(pl)
		T.eq(snapL and snapL.tuning and snapL.tuning.pendingIdle, 0, "Snapshot pendingIdle 0")
		-- Stadt-Station mit Level-Voraussetzung: Toast statt mini_open
		m = openCityStation(g, pl, "arcade")
		T.eq(#g:Events(pl, "mini_open", m), 0, "Spielhalle öffnet nicht")
		T.check(g:HasToast(pl, "Ab Level 10: Spielhalle", m), "Toast Spielhalle")
		m = openCityStation(g, pl, "map")
		T.check(g:Events(pl, "mini_open", m)[1] ~= nil and g:Events(pl, "mini_open", m)[1].tab == "map", "Stadtplan (ohne Voraussetzung) öffnet")
		-- Level 10: alles offen (ab Level 6 sammeln sich passive Einnahmen an)
		d.level = 10
		g:Advance(1.1)
		T.eq(g:Act(pl, "mini_press_click", { count = 3 }), "ok", "Presse ab Level 2")
		T.eq(d.games.press.clicks, 3, "Klicks gezählt")
		g.env.clock:Jump(600)
		g:Advance(1.1)
		T.check(TR.PendingIdle(d, g:Now()) > 0, "ab Level 6 sammeln sich passive Einnahmen an")
		T.check(d.games.press.scrap > 3, "Maschinen produzieren ab Level 2")
		g:Advance(0.5)
		T.eq(g:Act(pl, "mini_tuning_idle", { rid = 15 }), "ok", "mini_tuning_idle ab Level 6")
		m = openCityStation(g, pl, "arcade")
		T.check(g:Events(pl, "mini_open", m)[1] ~= nil and g:Events(pl, "mini_open", m)[1].tab == "arcade", "Spielhalle öffnet ab Level 10")
		T.eq(g:Act(pl, "mini_arcade_start", { game = "arcade_1", rid = 7 }), "ok", "Spielhalle spielbar")
		noErrors(T, g, "Sperren")
	end },

	{ "Tutorial-Kiosk: tutorial_restart nach Überspringen, nie eine zweite Belohnung, Kiosk-Station öffnet den Lobby-Tab", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local TR = g:MiniShared("TutorialRules")
		local pl, d, p = join(g, 4501, "Kim")
		-- Neustart in der Lobby, solange es läuft: abgelehnt
		local m = g:Mark()
		T.eq(g:Act(pl, "tutorial_restart", { rid = 1 }), "ok", "tutorial_restart (läuft noch) -> Toast")
		T.check(g:HasToast(pl, "läuft schon", m), "Toast: läuft schon")
		T.eq(d.games.meta.tutorialDone, false, "unverändert")
		-- Kiosk-Station in der Lobby: Lobby-Tab mit action tutorial, Hinweis mit tutorialDone
		local st = g:Find("Workspace.Lobby.Stations.tutorial")
		T.check(st ~= nil, "Lobby-Station tutorial")
		if st then
			g:Teleport(pl, st.Arrival.WorldPosition)
			g:Advance(0.2)
			m = g:Mark()
			g:Trigger(pl, st:FindFirstChildOfClass("ProximityPrompt"), { force = true })
			g:Advance(0.3)
			local open = g:Events(pl, "mini_open", m)[1]
			T.check(open ~= nil and open.tab == "lobby" and open.action == "tutorial", "mini_open lobby mit action tutorial")
			local n = g:Notices(pl, "lobby", m)[1]
			T.check(n ~= nil and n.action == "tutorial" and n.tutorialDone == false, "lobby-Hinweis mit tutorialDone")
		end
		-- in die Open World, überspringen
		g:Advance(0.5)
		T.eq(g:Act(pl, "lobby_mode", { mode = "openworld", rid = 2 }), "ok", "lobby_mode")
		g:Advance(3.1)
		T.eq(g:Act(pl, "lobby_go", { rid = 3 }), "ok", "lobby_go")
		T.eq(p.mode, "openworld", "Open World")
		g:Advance(1.1)
		m = g:Mark()
		T.eq(g:Act(pl, "tutorial_skip", { rid = 4 }), "ok", "tutorial_skip")
		T.eq(d.games.meta.tutorialDone, true, "übersprungen")
		T.check(g:HasToast(pl, "Tutorial-Kiosk", m), "Skip-Toast nennt den Kiosk")
		T.check(g:HasToast(pl, "neu starten", m), "Skip-Toast verspricht nur, was es gibt (Neustart)")
		-- Neustart: Schritt 1, aktiv, gestartet-Hinweis; keine Belohnung verbucht
		g:Advance(2.1)
		m = g:Mark()
		local money = d.money
		T.eq(g:Act(pl, "tutorial_restart", { rid = 5 }), "ok", "tutorial_restart")
		T.eq(d.games.meta.tutorialDone, false, "läuft wieder")
		T.eq(d.games.meta.tutorialSkipped, false, "nicht mehr übersprungen")
		T.eq(step(g, d), 1, "Schritt 1")
		T.eq(d.games.meta.tutorialRewarded, false, "noch keine Belohnung verbucht")
		local n = g:Notices(pl, "tutorial", m)
		T.check(#n >= 1 and n[#n].restarted == true and n[#n].active == true and n[#n].step == 1, "tutorial-Hinweis restarted/active")
		T.check(g:HasToast(pl, "neu gestartet", m), "Toast neu gestartet")
		g:Advance(1.1)
		T.eq(g:MiniSnapshot(pl).tutorial.active, true, "Snapshot aktiv")
		-- Ende erreicht (letzter Schritt am Kiesplatz): Belohnung genau einmal
		d.games.meta.tutorialStep = TR.Count()
		g:Advance(0.5)
		m = g:Mark()
		openCityStation(g, pl, "kiesplatz")
		T.eq(d.games.meta.tutorialDone, true, "beendet")
		T.eq(d.games.meta.tutorialRewarded, true, "Belohnung verbucht")
		T.check(d.money - money >= 500, "500 Credits beim ersten Abschluss")
		-- zweiter Durchlauf: Neustart erlaubt, am Ende keine zweite Belohnung
		g:Advance(2.1)
		T.eq(g:Act(pl, "tutorial_restart", { rid = 6 }), "ok", "tutorial_restart nach Abschluss")
		T.eq(d.games.meta.tutorialDone, false, "läuft erneut")
		T.eq(d.games.meta.tutorialRewarded, true, "Flag bleibt")
		d.games.meta.tutorialStep = TR.Count()
		money = d.money
		local xp = d.xp
		g:Advance(0.5)
		m = g:Mark()
		openCityStation(g, pl, "kiesplatz")
		T.eq(d.games.meta.tutorialDone, true, "zweites Mal beendet")
		T.eq(d.money, money, "keine zweite Belohnung (Credits)")
		T.eq(d.xp, xp, "keine zweite Belohnung (XP)")
		T.check(g:HasToast(pl, "hattest du schon", m), "Toast: Belohnung hattest du schon")
		-- Speichern/Laden: Flag bleibt
		g:Leave(pl)
		local rec = g:Record(4501)
		T.eq(rec and rec.data.games.meta.tutorialRewarded, true, "tutorialRewarded gespeichert")
		local _, d2 = join(g, 4501, "Kim")
		T.eq(d2.games.meta.tutorialRewarded, true, "tutorialRewarded geladen")
		-- altes Profil ohne Flag, regulär beendet: gilt als belohnt; übersprungen: nicht
		local MR = g:MiniShared("MetaRules")
		local mOld = MR.Load({ tutorialDone = true }, nil, g:Now())
		T.eq(mOld.tutorialRewarded, true, "alt + beendet = belohnt")
		local mSkip = MR.Load({ tutorialDone = true, tutorialSkipped = true }, nil, g:Now())
		T.eq(mSkip.tutorialRewarded, false, "alt + übersprungen = nicht belohnt")
		noErrors(T, g, "Kiosk")
	end },

	{ "Spieler-Auktionen: Gebote auf Spieler-Lose erst ab Level 20 (auction:player), NPC-Lose ab 12", function(T, H)
		local g = H.Garage()
		local AR = g:MiniShared("AuctionRules")
		local CR = g:MiniShared("CarRules")
		local AS = g:MiniServer("AuctionService")
		local seller, sd = join(g, 4601, "Sina")
		local buyer, bd = join(g, 4602, "Ben")
		sd.level = 20
		bd.level = 12
		bd.money = 100000
		local car = CR.AddCar(sd, CR.NewCar("komet", g:Now()))
		local start = AR.StartOptions(car)[1]
		T.eq(g:Act(seller, "mini_auction_consign", { id = car.id, start = start, duration = 120, rid = 1 }), "ok", "consign")
		local lot
		for _, id in ipairs(AS.State().order) do
			local l = AS.Lot(id)
			if l.kind == "player" then
				lot = l
			end
		end
		T.check(lot ~= nil, "Spieler-Los angelegt")
		g:Advance(0.6)
		local m = g:Mark()
		T.eq(g:Act(buyer, "mini_auction_bid", { lot = lot.id, amount = start, rid = 2 }), "locked", "Level 12: Gebot auf Spieler-Los gesperrt")
		T.check(g:HasToast(buyer, "Ab Level 20: Spieler-Auktionen", m), "Toast Spieler-Auktionen ab Level 20")
		T.eq(AR.Top(lot), nil, "kein Gebot")
		-- NPC-Los: ab Level 12 erlaubt (Prüfung läuft durch CheckBid, nicht durch die Sperre)
		local npc
		for _, id in ipairs(AS.State().order) do
			local l = AS.Lot(id)
			if l.kind ~= "player" then
				npc = l
			end
		end
		if npc then
			g:Advance(0.6)
			T.check(g:Act(buyer, "mini_auction_bid", { lot = npc.id, amount = AR.MinBid(npc), rid = 3 }) ~= "locked", "NPC-Los nicht gesperrt")
		end
		T.eq(g:Act(buyer, "mini_auction_bid", { lot = 999999, amount = 1, rid = 4 }) ~= "locked", true, "unbekanntes Los: keine Sperre, AuctionService meldet selbst")
		-- Level 20: Gebot geht durch
		bd.level = 20
		g:Advance(0.6)
		T.eq(g:Act(buyer, "mini_auction_bid", { lot = lot.id, amount = start, rid = 5 }), "ok", "Level 20: Gebot angenommen")
		T.eq(AR.Top(lot) and AR.Top(lot).userId, 4602, "Ben vorn")
		noErrors(T, g, "Auktion")
	end },

	{ "Client: im all-Place öffnet sich der Lobby-Tab einmal, Tabs lobby/unlocks/prestige vorhanden, Sperrhinweis am gesperrten Bereich", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local pl = g:Join(4401, { name = "Tester" })
		g:Advance(0.5)
		g:StartClient(pl)
		g:Advance(2)
		local MiniUI = g:ClientModule(pl, "Mini.MiniUI")
		T.check(MiniUI.Pages.lobby ~= nil and MiniUI.Pages.unlocks ~= nil and MiniUI.Pages.prestige ~= nil, "Tabs lobby/unlocks/prestige")
		T.eq(MiniUI.Tabs[1].key, "lobby", "Lobby ist der erste Tab")
		T.eq(MiniUI.IsOpen, true, "Panel offen (Lobby)")
		T.eq(MiniUI.CurrentTab, "lobby", "Lobby-Tab")
		local gui = pl.PlayerGui
		T.check(gui:FindFirstChild("Tutorial") ~= nil, "TutorialUI gestartet")
		T.check(gui:FindFirstChild("ProgressHUD") ~= nil, "Prestige-Abzeichen gebaut")
		-- Sperrhinweis am Bereich Schrottpresse (Level 1 < 2)
		MiniUI.Show("press")
		g:Advance(0.3)
		local note = MiniUI.Pages.press:FindFirstChild("LockNote")
		T.check(note ~= nil and note.Visible == true and note.Text:find("Ab Level 2", 1, true) ~= nil, "Sperrhinweis Presse")
		local goals = MiniUI.Pages.goals:FindFirstChild("LockNote")
		T.check(goals == nil, "Ziele ohne Sperrhinweis")
		-- Panel schließen: kein erneutes Öffnen ohne Moduswechsel
		MiniUI.Close()
		g:Advance(1.2)
		T.eq(MiniUI.IsOpen, false, "bleibt zu")
		-- Reise (Simulation): mode-Hinweis, Panel bleibt zu; zurück in die Lobby -> öffnet erneut
		g:Advance(0.5)
		T.eq(g:Act(pl, "lobby_mode", { mode = "openworld", rid = 1 }), "ok", "lobby_mode")
		g:Advance(3.1)
		T.eq(g:Act(pl, "lobby_go", { rid = 2 }), "ok", "lobby_go")
		g:Advance(1.2)
		T.eq(MiniUI.IsOpen, false, "in der Open World zu")
		g:Advance(3.1)
		T.eq(g:Act(pl, "lobby_return", { rid = 3 }), "ok", "lobby_return")
		g:Advance(1.2)
		T.eq(MiniUI.IsOpen, true, "Lobby öffnet sich wieder")
		T.eq(MiniUI.CurrentTab, "lobby", "Lobby-Tab")
		noErrors(T, g, "Client")
	end },
}
