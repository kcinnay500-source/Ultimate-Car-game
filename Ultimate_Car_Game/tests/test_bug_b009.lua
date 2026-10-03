-- B-009: "hello" kommt an, bevor die Sitzung existiert (Profil lädt langsam). Der Client hört nach dem ersten
-- `state` auf zu senden; die Sitzung muss trotzdem begrüßt werden (Auktion, Bestenliste, eingereihte Hinweise).
local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
end

-- Beitritt mit echtem Client, während das Profil `seconds` lang lädt
local function slowJoin(g, userId, name, seconds)
	local ds = g:DataStoreMock()
	ds.updateYield = seconds
	local player = g:Join(userId, { name = name })
	ds.updateYield = 0 -- nur das Laden ist langsam
	g:StartClient(player)
	return player
end

local function greetedSoon(T, g, player, since, what)
	local ms = g:MiniState(player)
	T.check(ms ~= nil, what .. ": Sitzung entstanden")
	T.eq(ms and ms.greeted, true, what .. ": Sitzung begrüßt")
	T.check(#g:Notices(player, "auction_update", since) >= 1, what .. ": auction_update angekommen")
	T.check(#g:Notices(player, "leaderboard", since) >= 1, what .. ": leaderboard angekommen")
	T.check(g:MiniSnapshot(player, since) ~= nil, what .. ": Minispiel-Snapshot angekommen")
end

return {
	{ "5 s Ladezeit: Sitzung ist kurz nach dem ersten state begrüßt, auch nach Rejoin", function(T, H)
		local g = H.Garage({ level = 20 })
		local m = g:Mark()
		local player = slowJoin(g, 9091, "Sven", 5)
		g:Advance(3)
		T.eq(g:MiniState(player), nil, "Profil lädt noch")
		T.eq(#g:Events(player, "state", m), 0, "noch kein state")
		g:Advance(5)
		T.check(#g:Events(player, "state", m) >= 1, "state angekommen")
		greetedSoon(T, g, player, m, "erster Beitritt")
		g:Leave(player)
		g:Advance(2)
		local m2 = g:Mark()
		local again = slowJoin(g, 9091, "Sven", 5)
		g:Advance(8)
		greetedSoon(T, g, again, m2, "Rejoin")
		noErrors(T, g)
	end },

	{ "Eingereihter Hinweis kommt nach langsamem Laden an", function(T, H)
		local g = H.Garage({ level = 20 })
		local m = g:Mark()
		local player = slowJoin(g, 9092, "Tom", 5)
		g:Advance(5.3)
		local ms = g:MiniState(player)
		T.check(ms ~= nil, "Sitzung entstanden")
		g:Advance(3)
		ms = g:MiniState(player)
		T.eq(ms and #ms.notices, 0, "keine Hinweise mehr eingereiht")
		T.eq(ms and ms.greeted, true, "begrüßt")
		local _ = m
		noErrors(T, g)
	end },

	{ "Schnelles Laden: genau eine Begrüßung", function(T, H)
		local g = H.Garage({ level = 20 })
		local m = g:Mark()
		local player = g:Join(9093, { name = "Uta" })
		g:StartClient(player)
		g:Advance(4)
		T.eq(g:MiniState(player).greeted, true, "begrüßt")
		T.eq(#g:Notices(player, "auction_update", m), 1, "ein auction_update")
		T.check(#g:Notices(player, "leaderboard", m) >= 1, "Bestenliste angekommen") -- (eine Aktualisierung des Caches sendet sie erneut)
		noErrors(T, g)
	end },

	{ "Langsames Laden: ein nachzügelndes hello begrüßt nicht doppelt", function(T, H)
		local g = H.Garage({ level = 20 })
		local ds = g:DataStoreMock()
		ds.updateYield = 3
		local m = g:Mark()
		local player = g:Join(9094, { name = "Vito" })
		ds.updateYield = 0
		g:Advance(1)
		g:Send(player, "hello") -- kommt vor der Sitzung an
		g:Advance(2.2) -- Sitzung entsteht
		T.check(g:MiniState(player) ~= nil, "Sitzung entstanden")
		g:Send(player, "hello") -- war beim ersten state schon unterwegs
		g:Advance(1)
		T.eq(g:MiniState(player) and g:MiniState(player).greeted, true, "begrüßt")
		T.eq(#g:Notices(player, "auction_update", m), 1, "ein auction_update")
		T.check(#g:Notices(player, "leaderboard", m) >= 1, "Bestenliste angekommen") -- (eine Aktualisierung des Caches sendet sie erneut)
		-- ein späteres hello (z. B. Tests, neu gestarteter Client) wirkt wie bisher
		g:Advance(5)
		local m2 = g:Mark()
		g:Send(player, "hello")
		T.eq(#g:Notices(player, "auction_update", m2), 1, "späteres hello sendet den Zustand erneut")
		noErrors(T, g)
	end },
}
