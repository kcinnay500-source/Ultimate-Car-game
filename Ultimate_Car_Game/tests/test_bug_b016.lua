-- B-016: Nach einem Gruppen-Teleport wurde Party-Leiter, wer am Ziel zuerst geladen hatte (LobbyService.OnJoin legte
-- die Party für den ersten Ankömmling an). Jetzt reist die Leiter-Kennung (UserId) in den TeleportData mit: ein
-- Mitglied, das vor dem Leiter ankommt, führt nur vorläufig; kommt der Leiter an, übernimmt er. Kommt er nie, bleibt
-- die Party mit dem vorläufigen Leiter benutzbar. TeleportData ist manipulierbar: die Kennung wirkt nur innerhalb der
-- Party mit demselben Code und nur, solange der aktuelle Leiter selbst jemand anderen als Leiter genannt hat.
local function join(H, g, userId, name, td)
	if not g:Record(userId) then
		g:SeedLevel(userId, 60)
	end
	local pl = H.Mock.NewPlayer(g.env, userId, name)
	if td then
		H.Mock.SetJoinData(g.env, pl, { TeleportData = td })
	end
	table.insert(g.players, pl)
	H.Mock.Join(g.env, pl)
	H.Mock.Flush(g.env)
	H.Mock.SpawnCharacter(g.env, pl)
	H.Mock.Flush(g.env)
	g:Advance(0.5)
	return pl
end

local function act(g, p, action, payload)
	g:Advance(3.5)
	return g:Act(p, action, payload)
end

local function leaderId(LS, code)
	local party = LS.Parties[code]
	return party and party.leader and party.leader.UserId or nil
end

return {
	{ "TeleportData trägt die Leiter-Kennung; Sanitize lässt nur eine ganze positive Zahl durch", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local LS, PR, GC = g:MiniServer("LobbyService"), g:MiniServer("PlaceRouter"), g:MiniShared("GameConfig")
		local a = join(H, g, 11, "Anna")
		local b = join(H, g, 12, "Ben")
		T.eq(act(g, a, "party_create"), "ok", "party_create")
		local code = LS.PartyOf(a) and LS.PartyOf(a).code
		T.check(type(code) == "string", "Party-Code")
		T.eq(act(g, b, "party_join", { code = code }), "ok", "party_join")
		GC.Places.tycoon, GC.Places.openworld, GC.Places.lobby = 12345, 23456, 34567
		act(g, a, "lobby_mode", { mode = "tycoon" })
		act(g, a, "lobby_go")
		local calls = g.env.services.TeleportService.__calls
		local call = calls[#calls] or {}
		T.eq(call.method, "TeleportAsync", "TeleportAsync")
		T.eq(#(call.players or {}), 2, "Party reist gemeinsam")
		T.eq(call.teleportData and call.teleportData.party, code, "TeleportData.party")
		T.eq(call.teleportData and call.teleportData.leader, 11, "TeleportData.leader = UserId des Leiters")
		-- Sanitize / InitialMode
		T.eq(PR.SanitizeTeleportData({ leader = 11 }).leader, 11, "Sanitize: leader Zahl")
		T.eq(PR.SanitizeTeleportData({ leader = "11" }).leader, nil, "Sanitize: leader als String verworfen")
		T.eq(PR.SanitizeTeleportData({ leader = 0 / 0 }).leader, nil, "Sanitize: NaN verworfen")
		local _, info = PR.InitialMode(nil, "all", { TeleportData = { party = "abcd", leader = 77 } })
		T.eq(info.leader, 77, "InitialMode: info.leader")
		for _, bad in ipairs({ -5, 0, 1.5, math.huge }) do
			local _, i2 = PR.InitialMode(nil, "all", { TeleportData = { party = "abcd", leader = bad } })
			T.eq(i2.leader, nil, "InitialMode: leader " .. tostring(bad) .. " verworfen")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Mitglied lädt vor dem Leiter: führt vorläufig, der ankommende Leiter übernimmt (Hinweise, Snapshot, Reihenfolge)", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local LS = g:MiniServer("LobbyService")
		local td = function()
			return { mode = "tycoon", party = "KLMN", leader = 21 }
		end
		local ben = join(H, g, 22, "Ben", td())
		T.eq(leaderId(LS, "KLMN"), 22, "Ben (zuerst da) führt vorläufig")
		local cem = join(H, g, 23, "Cem", td())
		T.eq(leaderId(LS, "KLMN"), 22, "zweites Mitglied ändert nichts")
		local mark = g:Mark()
		local anna = join(H, g, 21, "Anna", td())
		T.eq(leaderId(LS, "KLMN"), 21, "Anna (ursprüngliche Leiterin) übernimmt bei Ankunft")
		local party = LS.Parties.KLMN
		T.eq(#party.members, 3, "drei Mitglieder")
		T.check(party.members[1] == anna, "Leiterin steht vorn (nächster Leiter = ältestes Mitglied)")
		T.eq(LS.PartyOf(ben), party, "Ben bleibt Mitglied")
		local snap = LS.SnapshotFields(g:MiniState(ben), g:D(ben), g:Now(), true)
		T.eq(snap.party and snap.party.leader, 21, "Snapshot Ben: Leiter Anna")
		T.eq(snap.party and snap.party.isLeader, false, "Snapshot Ben: nicht mehr Leiter")
		local sawLeader = false
		for _, n in ipairs(g:Notices(cem, "party", mark)) do
			if n.event == "leader" and n.userId == 21 then
				sawLeader = true
			end
		end
		T.check(sawLeader, "Mitglieder sehen den Hinweis leader")
		-- Leiter-Rechte: Anna darf entfernen, Ben nicht mehr
		act(g, ben, "party_kick", { userId = 23 })
		T.eq(LS.PartyOf(cem), party, "Ben (kein Leiter mehr) kann nicht entfernen")
		act(g, anna, "party_kick", { userId = 23 })
		T.eq(LS.PartyOf(cem), nil, "Anna kann entfernen")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Leiter kommt nie an: Party bleibt benutzbar; verspätete Ankunft übernimmt nicht mehr", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local LS = g:MiniServer("LobbyService")
		local ben = join(H, g, 32, "Ben", { mode = "tycoon", party = "PQRS", leader = 31 })
		local cem = join(H, g, 33, "Cem", { mode = "tycoon", party = "PQRS", leader = 31 })
		T.eq(leaderId(LS, "PQRS"), 32, "Ben führt")
		local snap = LS.SnapshotFields(g:MiniState(ben), g:D(ben), g:Now(), true)
		T.eq(snap.party and snap.party.isLeader, true, "Snapshot: Ben ist Leiter")
		act(g, ben, "party_kick", { userId = 33 })
		T.eq(LS.PartyOf(cem), nil, "vorläufiger Leiter hat Leiter-Rechte (entfernen)")
		T.eq(#LS.Parties.PQRS.members, 1, "Party besteht weiter")
		-- lange nach dem Teleport: wer jetzt mit dem Code ankommt, tritt nur bei
		g:Advance(600)
		local anna = join(H, g, 31, "Anna", { mode = "tycoon", party = "PQRS", leader = 31 })
		T.eq(LS.PartyOf(anna), LS.Parties.PQRS, "Anna tritt bei")
		T.eq(leaderId(LS, "PQRS"), 32, "nach Ablauf der Wartezeit bleibt Ben Leiter")
		-- vorläufiger Leiter geht vor der Ankunft des Leiters: ältestes Mitglied führt, Leiter übernimmt trotzdem
		local dan = join(H, g, 42, "Dan", { mode = "tycoon", party = "TUVW", leader = 41 })
		local eva = join(H, g, 43, "Eva", { mode = "tycoon", party = "TUVW", leader = 41 })
		g:Leave(dan)
		g:Advance(1)
		T.eq(leaderId(LS, "TUVW"), 43, "Eva rückt nach")
		local fay = join(H, g, 41, "Fay", { mode = "tycoon", party = "TUVW", leader = 41 })
		T.eq(leaderId(LS, "TUVW"), 41, "Fay (ursprüngliche Leiterin) übernimmt")
		T.check(eva ~= nil and fay ~= nil, "Spieler da")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Manipulierte Leiter-Kennung: keine Übernahme einer fremden oder schon geführten Party", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local LS = g:MiniServer("LobbyService")
		-- echte Leiterin zuerst da (nennt sich selbst): niemand kann übernehmen
		local anna = join(H, g, 51, "Anna", { mode = "tycoon", party = "ABCD", leader = 51 })
		local mallory = join(H, g, 59, "Mallory", { mode = "tycoon", party = "ABCD", leader = 59 })
		T.eq(leaderId(LS, "ABCD"), 51, "Anna bleibt Leiterin trotz gefälschter Kennung")
		T.eq(LS.PartyOf(mallory), LS.Parties.ABCD, "Mallory ist nur Mitglied")
		-- Party ohne Leiter-Kennung (alte TeleportData / in der Lobby angelegt): Kennung des Ankömmlings zählt nicht
		local ben = join(H, g, 52, "Ben", { mode = "tycoon", party = "EFGH" })
		local m2 = join(H, g, 58, "Mona", { mode = "tycoon", party = "EFGH", leader = 58 })
		T.eq(leaderId(LS, "EFGH"), 52, "ohne Kennung des Ersten: keine Übernahme")
		T.check(m2 ~= nil, "Mona da")
		-- hier auf dem Server angelegte Party: Beitritt per TeleportData mit eigener Kennung übernimmt nicht
		local cem = join(H, g, 53, "Cem")
		T.eq(act(g, cem, "party_create"), "ok", "party_create")
		local code = LS.PartyOf(cem).code
		local m3 = join(H, g, 57, "Milo", { mode = "lobby", party = code, leader = 57 })
		T.eq(leaderId(LS, code), 53, "lokal angelegte Party: Leiter bleibt")
		T.check(m3 ~= nil, "Milo da")
		T.check(anna and ben, "Spieler da")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Manipulierte Leiter-Kennung: Dritter übernimmt eine wartende Party nicht; nur eine Übergabe", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local LS = g:MiniServer("LobbyService")
		-- vorläufig geführte Party wartet auf 61: ein Dritter mit eigener Kennung übernimmt nicht
		local dan = join(H, g, 62, "Dan", { mode = "tycoon", party = "JKLM", leader = 61 })
		local m4 = join(H, g, 56, "Max", { mode = "tycoon", party = "JKLM", leader = 56 })
		T.eq(leaderId(LS, "JKLM"), 62, "Dritter mit eigener Kennung übernimmt nicht")
		local eva = join(H, g, 61, "Eva", { mode = "tycoon", party = "JKLM", leader = 61 })
		T.eq(leaderId(LS, "JKLM"), 61, "die erwartete Leiterin übernimmt")
		-- einmal übernommen: keine zweite Übergabe
		g:Leave(eva)
		g:Advance(1)
		local eva2 = join(H, g, 61, "Eva", { mode = "tycoon", party = "JKLM", leader = 61 })
		T.eq(leaderId(LS, "JKLM"), 62, "nach dem Weggang führt wieder das älteste Mitglied; Rückkehr übernimmt nicht erneut")
		T.check(dan and m4 and eva2, "Spieler da")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
