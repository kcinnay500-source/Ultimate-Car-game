-- Spielbarkeits-Fixes (Review Meilenstein 9) über die echte Verkabelung (H.Garage, Remotes.Command -> request ->
-- Mini.Handle bzw. act): Reisen aus Lobby/Schnellem Spiel in die Stadt wechseln den Modus (2.4.0-Tablet travel/target,
-- mini_travel, Autos), einzelne Lobby-Places lehnen ab; Party-Mitglied reist zum Leiter, Leiter holt Mitglieder nach;
-- Kiesplatz-Verkauf vor „Starten“ zählt für c1_m1; Tutorial-Belohnung aus OnLeave nie doppelt; Neustart-Endkarte.

local function join(g, userId, name)
	local pl = g:Join(userId, { name = name })
	g:Advance(1.1)
	g:Send(pl, "hello")
	g:Advance(1.1)
	return pl, g:D(pl), g:Session(pl)
end

local rid = 9100
local function act(T, g, pl, action, payload, expect, msg)
	g:Advance(3.2) -- Abklingzeiten (mini_travel 3 s)
	rid += 1
	payload = payload or {}
	payload.rid = rid
	local res = g:Act(pl, action, payload)
	if expect then
		T.eq(res, expect, msg or (action .. " -> " .. expect))
	end
	return res
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, what .. ": keine Fehler: " .. g:ErrorText())
end

local function cityStation(g, key)
	local st = g:Find("Workspace.City.Stations")
	return st and st:FindFirstChild(key)
end

return {
	{ "Lobby -> 2.4.0-Tablet „Zum Empfang“ (travel/target) wechselt in die Open World: Tutorial startet, Snapshot mode openworld", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local pl, d, p = join(g, 9101, "Mia")
		T.eq(p.mode, "lobby", "erster Beitritt: Lobby")
		local m = g:Mark()
		g:Send(pl, "travel", { key = "workshop" })
		g:Advance(1.1)
		T.eq(p.mode, "openworld", "Modus nach travel: openworld")
		T.eq(d.games.meta.lastMode, "openworld", "lastMode gespeichert")
		local modeNotice = g:Notices(pl, "mode", m)[1]
		T.check(modeNotice ~= nil and modeNotice.mode == "openworld", "mini_notice mode openworld")
		-- neues Profil: zuerst die Startwahl, das Tutorial wartet so lange
		T.eq(#g:Notices(pl, "tutorial", m), 0, "kein Tutorial vor der Startwahl")
		T.check(g:MiniSnapshot(pl).start and g:MiniSnapshot(pl).start.pending == true, "Startwahl offen")
		T.eq(g:Act(pl, "start_choose", { path = "werkstatt", rid = 901 }), "ok", "start_choose werkstatt")
		g:Advance(0.6)
		local started = g:Notices(pl, "tutorial", m)
		T.check(#started >= 1 and started[1].started == true, "Pflicht-Tutorial gestartet")
		T.eq(g:MiniSnapshot(pl).mode, "openworld", "Snapshot mode")
		T.eq(g:MiniSnapshot(pl).tutorial.active, true, "Tutorial-Karte aktiv")
		local home = g:Station(pl, "workshop")
		local root = g:Root(pl)
		T.check(home and root and (root.Position - home.Position).Magnitude < 15, "Figur am Empfang")
		-- target (Zum Ziel) aus der Lobby: zweiter Spieler
		local pl2, _, p2 = join(g, 9102, "Ole")
		T.eq(p2.mode, "lobby", "Ole in der Lobby")
		g:Send(pl2, "target", {})
		g:Advance(1.1)
		T.eq(p2.mode, "openworld", "Modus nach target: openworld")
		noErrors(T, g, "travel/target")
	end },

	{ "Lobby/Tycoon -> Stadtplan (mini_travel) wechselt den Modus; Ziel in der Lobby bleibt Lobby; einzelner Lobby-Place lehnt ab", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local pl, d, p = join(g, 9111, "Lea")
		T.eq(p.mode, "lobby", "Lobby")
		-- Ankunftspunkt nur in der Lobby: kein Moduswechsel
		local lobbyArrivals = g:Find("Workspace.Lobby.Arrivals")
		local cityArrivals = g:Find("Workspace.City.Arrivals")
		local lobbyOnly = nil
		for _, a in ipairs(lobbyArrivals and lobbyArrivals:GetChildren() or {}) do
			if not (cityArrivals and cityArrivals:FindFirstChild(a.Name)) then
				lobbyOnly = a.Name
				break
			end
		end
		if lobbyOnly then
			act(T, g, pl, "mini_travel", { key = lobbyOnly }, "ok")
			T.eq(p.mode, "lobby", "Lobby-Ziel " .. lobbyOnly .. ": bleibt Lobby")
		end
		-- Kiesplatz (Stadt): Moduswechsel, dann die Reise
		act(T, g, pl, "mini_travel", { key = "kiesplatz" }, "ok")
		T.eq(p.mode, "openworld", "Kiesplatz: openworld")
		local kies = cityArrivals and cityArrivals:FindFirstChild("kiesplatz")
		local root = g:Root(pl)
		local kpos = kies and (kies:IsA("BasePart") and kies.Position or kies:GetPivot().Position)
		T.check(kpos and root and (Vector3.new(root.Position.X, 0, root.Position.Z) - Vector3.new(kpos.X, 0, kpos.Z)).Magnitude < 12, "Figur am Kiesplatz")
		T.eq(d.games.meta.lastMode, "openworld", "lastMode")
		-- Tycoon -> Stadtplan: Tycoon verlassen
		local pl2, _, p2 = join(g, 9112, "Tom")
		act(T, g, pl2, "lobby_mode", { mode = "tycoon" }, "ok")
		act(T, g, pl2, "lobby_go", {}, "ok")
		T.eq(p2.mode, "tycoon", "Tom im Tycoon")
		g:Advance(2)
		T.check(g:MiniServer("TycoonService").PlotOf(pl2) ~= nil, "Tycoon-Grundstück belegt")
		act(T, g, pl2, "mini_travel", { key = "workshop" }, "ok")
		T.eq(p2.mode, "openworld", "nach Stadtplan: openworld")
		g:Advance(2)
		T.eq(g:MiniServer("TycoonService").PlotOf(pl2), nil, "Tycoon-Grundstück freigegeben")
		noErrors(T, g, "mini_travel")

		-- einzelner Lobby-Place: keine Stadt, Hinweis statt Reise
		local gl = H.Garage({ placeKind = "lobby" })
		local pl3, _, p3 = join(gl, 9113, "Kim")
		T.eq(p3.mode, "lobby", "Lobby-Place")
		local m = gl:Mark()
		act(T, gl, pl3, "mini_travel", { key = "workshop" }, "mode", "mini_travel im Lobby-Place abgelehnt")
		T.eq(p3.mode, "lobby", "bleibt Lobby")
		T.check(gl:HasToast(pl3, "nur in der Open World", m), "Hinweis: nur in der Open World")
		noErrors(T, gl, "Lobby-Place")
	end },

	{ "Party: Mitglied in der Lobby reist mit „Los geht's“ zum Leiter; Leiter am Ziel holt Mitglieder nach", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local a, _, pa = join(g, 9121, "Anna")
		local b, _, pb = join(g, 9122, "Ben")
		act(T, g, a, "party_create", {}, "ok")
		local LS = g:MiniServer("LobbyService")
		local code = LS.PartyOf(a).code
		act(T, g, b, "party_join", { code = code }, "ok")
		act(T, g, a, "lobby_mode", { mode = "openworld" }, "ok")
		act(T, g, a, "lobby_go", {}, "ok")
		T.eq(pa.mode, "openworld", "Leiter in der Open World")
		T.eq(pb.mode, "openworld", "Mitglied reist mit")
		-- Mitglied allein zurück, dann wieder zum Leiter
		act(T, g, b, "lobby_return", {}, "ok")
		T.eq(pb.mode, "lobby", "Mitglied allein in der Lobby")
		g:Advance(1.1)
		local snap = g:MiniSnapshot(b)
		T.eq(snap.party and snap.party.leaderMode, "openworld", "Snapshot party.leaderMode")
		local m = g:Mark()
		act(T, g, b, "lobby_go", {}, "ok")
		T.eq(pb.mode, "openworld", "Mitglied reist zum Leiter")
		T.check(g:HasToast(b, "zu deiner Party", m), "Toast: zu deiner Party")
		T.check(LS.PartyOf(b) ~= nil and LS.PartyOf(b).code == code, "Party besteht weiter")
		T.eq(pa.mode, "openworld", "Leiter unverändert")
		-- Mitglied wieder zurück; der Leiter (schon in der Open World) holt es mit „Los geht's“
		act(T, g, b, "lobby_return", {}, "ok")
		T.eq(pb.mode, "lobby", "Mitglied wieder in der Lobby")
		g:Advance(1.1)
		T.eq(g:MiniSnapshot(a).party.away, true, "Snapshot: Mitglied woanders")
		m = g:Mark()
		act(T, g, a, "lobby_go", {}, "ok")
		T.eq(pb.mode, "openworld", "Leiter holt Mitglied nach")
		T.check(g:HasToast(a, "Party kommt zu dir", m), "Toast an den Leiter")
		-- Leiter in der Lobby: Mitglied darf nicht allein starten
		act(T, g, a, "lobby_return", {}, "ok")
		T.eq(pa.mode, "lobby", "Leiter in der Lobby (Party reist mit)")
		T.eq(pb.mode, "lobby", "Mitglied mit in der Lobby")
		m = g:Mark()
		act(T, g, b, "lobby_go", {}, "ok")
		T.eq(pb.mode, "lobby", "ohne Leiter unterwegs: Mitglied bleibt")
		T.check(g:HasToast(b, "Nur der Party-Leiter", m), "Toast notLeader")
		noErrors(T, g, "Party")
	end },

	{ "Kiesplatz: Verkauf vor „Starten“ startet c1_m1 automatisch und zählt", function(T, H)
		local g = H.Garage({})
		local pl, d, p = join(g, 9131, "Paul")
		T.eq(p.mode, "openworld", "Open World")
		-- 3.x: Startwahl ist Pflicht (Überspringen erst danach); auf dem Weg Verkaufshaus folgt c1_m1 auf c1_ah1
		act(T, g, pl, "start_choose", { path = "autohaus" }, "ok")
		T.check(type(d.games.story.active) == "table" and d.games.story.active.id == "c1_ah1", "Story läuft sofort: c1_ah1 aktiv")
		act(T, g, pl, "tutorial_skip", {}, "ok")
		-- erste Einnahmen schon abgeholt (c1_ah1 erledigt, nichts aktiv)
		local SR = g:MiniShared("StoryRules")
		d.games.story = SR.Load({ layout = SR.Layout, done = { c1_ah1 = true } }, d)
		local st = d.games.story
		T.eq(st.active, false, "nach c1_ah1 nichts aktiv")
		g:Advance(1.1)
		T.check(type(st.active) == "table" and st.active.id == "c1_m1", "c1_m1 startet ohne „Starten“ im Takt")
		local station = cityStation(g, "kiesplatz")
		local arrival = station and station:FindFirstChild("Arrival")
		g:Teleport(pl, arrival and arrival.WorldPosition or station.Position, arrival and nil or Vector3.new(0, 3, 4))
		local SS = g:MiniServer("StoryService")
		local offer = nil
		for _ = 1, 200 do
			offer = SS.Offer(g:MiniState(pl))
			if offer then
				break
			end
			g:Advance(0.5)
		end
		T.check(offer ~= nil, "Kunde am Kiesplatz")
		-- Verkauf, bevor der Takt die Mission (wieder) gestartet hat: der Verkauf selbst startet c1_m1 und zählt
		st = d.games.story
		st.active = false
		T.eq(d.games.story.active, false, "nichts gestartet")
		local m = g:Mark()
		act(T, g, pl, "story_sell", { offer = offer.serial, price = 1 }, "ok")
		local active = d.games.story.active
		T.check(type(active) == "table" and active.id == "c1_m1", "c1_m1 automatisch gestartet")
		T.eq(type(active) == "table" and active.progress, 1, "erster Verkauf zählt (1/3)")
		local started = nil
		for _, n in ipairs(g:Notices(pl, "story", m)) do
			if n.event == "started" then
				started = n
			end
		end
		T.check(started ~= nil and started.mission == "c1_m1", "mini_notice story started")
		noErrors(T, g, "Kiesplatz")
	end },

	{ "Tutorial-Belohnung: zurückgehalten und beim Verlassen verbucht -> als ausgezahlt markiert, Neustart zahlt nicht noch einmal; Endhinweis again", function(T, H)
		local g = H.Garage({})
		local pl, d = join(g, 9141, "Ida")
		local TS = g:MiniServer("TutorialService")
		local TR = g:MiniShared("TutorialRules")
		local ms = g:MiniState(pl)
		-- Belohnung zurückgehalten (Robux-Quittung lief), Spieler verlässt das Spiel vor dem nächsten Tick
		-- 3.x: Überspringen erst nach der (Pflicht-)Startwahl
		T.eq((g:MiniShared("MetaRules").SetStartPath(d, "werkstatt")), true, "Startweg werkstatt")
		TR.Skip(d)
		ms.tutorialRewardPending = true
		local money, xp = d.money, d.xp
		TS.OnLeave(ms, d)
		T.check(d.money > money, "Belohnung beim Verlassen verbucht")
		T.eq(TR.Rewarded(d), true, "als ausgezahlt markiert")
		-- zweiter Versuch (z. B. erneut zurückgehalten): nie doppelt
		money = d.money
		ms.tutorialRewardPending = true
		TS.OnLeave(ms, d)
		T.eq(d.money, money, "kein zweites Mal")
		T.check(d.xp >= xp, "XP nicht verloren")
		-- Neustart am Kiosk und erneuter Abschluss: Hinweis finished mit again = true, kein Geld
		T.check((TR.Restart(d)), "Neustart erlaubt")
		ms.tutorialStarted = nil
		g:MiniShared("MetaRules").Meta(d).tutorialStep = TR.Count() -- direkt zum letzten Schritt (Kiesplatz)
		money = d.money
		local m = g:Mark()
		-- letzter Schritt über das echte Ereignis (tab:story)
		local ok = TS.OnEvent(ms, d, "tab:story")
		g:Advance(0.6)
		if ok then
			local fin = nil
			for _, n in ipairs(g:Notices(pl, "tutorial", m)) do
				if n.finished then
					fin = n
				end
			end
			T.check(fin ~= nil and fin.again == true, "Endhinweis mit again = true")
			T.eq(d.money, money, "keine zweite Belohnung")
		else
			T.check(false, "letzter Tutorial-Schritt nicht erreicht (Schritt " .. tostring(TR.StepIndex(d)) .. ")")
		end
		noErrors(T, g, "Tutorial-Belohnung")
	end },
}
