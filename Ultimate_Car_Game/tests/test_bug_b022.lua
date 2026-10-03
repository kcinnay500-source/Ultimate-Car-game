-- B-022: Startwahl „Später entscheiden“ – nach dem ersten Respawn in der Open World kommt die Wahl nicht wieder,
-- wenn der Spieler in der Lobby beigetreten ist (all-Place). StartService.OnArrive hielt den ersten Aufruf in der
-- Open World für die erste Figur der Sitzung, obwohl die erste Figur schon in der Lobby erschienen war.
-- Echter Server (MiniService-Verkabelung, Remotes.Command), kein Client.

local function offers(g, pl, since)
	local n = 0
	for _, x in ipairs(g:Notices(pl, "start", since)) do
		if x.event == "offer" then
			n += 1
		end
	end
	return n
end

local function join(g, id, name)
	local pl = g:Join(id, { name = name })
	g:Advance(0.5)
	local ms = g:MiniState(pl)
	ms.greeted = true -- wie nach dem „hello“ des Clients (sonst wartet der Hinweis)
	return pl, ms, g:D(pl)
end

return {
	{ "B-022 Startwahl: Beitritt in der Lobby, lobby_go, ein Respawn – genau ein neues Angebot", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local MR = g:MiniShared("MetaRules")
		local pl, ms, d = join(g, 7401, "Lena")
		T.eq(ms.p.mode, "lobby", "neues Profil im all-Place: Lobby")
		T.eq(MR.StartPending(d), true, "Startwahl offen")
		T.eq(offers(g, pl), 0, "in der Lobby kein Angebot")
		-- in die Open World: Angebot genau einmal
		g:Act(pl, "lobby_mode", { mode = "openworld" })
		g:Act(pl, "lobby_go")
		g:Advance(0.5)
		T.eq(ms.p.mode, "openworld", "Modus Open World")
		T.eq(offers(g, pl), 1, "Angebot beim Betreten der Open World (genau eins)")
		-- „Später entscheiden“ (nur Client: Karte zu). Erster Respawn: die Wahl kommt wieder
		local m = g:Mark()
		g:Respawn(pl)
		g:Advance(0.5)
		T.eq(offers(g, pl, m), 1, "erster Respawn: genau ein neues Angebot")
		m = g:Mark()
		g:Respawn(pl)
		g:Advance(0.5)
		T.eq(offers(g, pl, m), 1, "zweiter Respawn: wieder genau eins")
		T.eq(MR.StartPending(d), true, "Wahl bleibt offen")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "B-022 Startwahl: Beitritt direkt in der Open World – kein doppeltes Angebot bei der ersten Figur, Respawn bietet wieder an", function(T, H)
		local g = H.Garage({ placeKind = "openworld" })
		local MR = g:MiniShared("MetaRules")
		local SS = g:MiniServer("StartService")
		local pl, ms, d = join(g, 7402, "Mats")
		T.eq(MR.StartPending(d), true, "Startwahl offen")
		T.check(ms.p.mode == nil or ms.p.mode == "openworld", "Modus Open World")
		-- erste Figur ist schon erschienen (Join): OnArrive hat sie gezählt und nichts angeboten
		T.eq(ms.startArrived, true, "erste Figur der Sitzung gemerkt")
		T.eq(ms.startOffered, true, "Angebot beim Betreten schon vermerkt (die Karte öffnet aus dem Snapshot)")
		local m = g:Mark()
		g:Respawn(pl)
		g:Advance(0.5)
		T.eq(offers(g, pl, m), 1, "Respawn: genau ein neues Angebot")
		-- in der Lobby/im Tycoon nie
		ms.p.mode = "tycoon"
		T.eq(SS.OnArrive(ms, d), false, "außerhalb der Open World kein Angebot")
		ms.p.mode = "openworld"
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "B-022 Startwahl: erste Figur einer Sitzung in der Open World löst kein zweites Angebot aus", function(T, H)
		local g = H.Garage({ placeKind = "openworld" })
		local SS = g:MiniServer("StartService")
		local pl, ms, d = join(g, 7403, "Nora")
		-- Sitzungsbeginn nachstellen: Angebot beim Betreten, dann erscheint die erste Figur
		SS.OnJoin(ms, d, g:Now())
		local m = g:Mark()
		T.eq(SS.OnMode(ms, d, "openworld"), true, "Angebot beim Betreten")
		T.eq(SS.OnArrive(ms, d), false, "erste Figur: kein zweites Angebot")
		T.eq(offers(g, pl, m), 1, "genau ein Angebot")
		T.eq(SS.OnArrive(ms, d), true, "zweite Figur: Angebot kommt wieder")
		T.eq(offers(g, pl, m), 2, "ein weiteres")
	end },
}
