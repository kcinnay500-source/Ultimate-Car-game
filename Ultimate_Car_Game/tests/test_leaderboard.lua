-- Phase 2: Bestenliste (Kodierung, Reihenfolge, eigene Platzierung, Drosselung, Fehlerfall)
return {
	{ "Kodierung ist monoton, ganzzahlig und dekodierbar", function(T, H)
		local env = H.Env()
		local R = H.Shared(env).PressRules
		local values = { 0, 1, 2, 9, 10, 999, 1000, 123456, 1e6, 2 ^ 53 - 1, 2 ^ 53, 2 ^ 53 + 2, 1e18, 1e30, 1e100, 1e300 }
		local last = -1
		for _, v in ipairs(values) do
			local c = R.EncodeScore(v)
			T.check(c == math.floor(c), "Ganzzahl für " .. tostring(v))
			T.check(c < 2 ^ 53, "unter 2^53 für " .. tostring(v))
			T.check(c >= last, "monoton bei " .. tostring(v))
			last = c
		end
		T.check(R.EncodeScore(1e6 + 1) > R.EncodeScore(1e6), "benachbarte Werte unterscheidbar (1 Mio.)")
		T.check(R.EncodeScore(1e15 * 1.001) > R.EncodeScore(1e15), "0,1 % Unterschied bei 1 Brd. unterscheidbar")
		T.check(R.EncodeScore(1e300 * 1.0001) > R.EncodeScore(1e300), "0,01 % bei 1e300 unterscheidbar")
		for _, v in ipairs({ 1, 42, 1000, 987654321, 2 ^ 40 }) do
			T.eq(R.DecodeScore(R.EncodeScore(v)), v, "Rundreise " .. v)
		end
		local big = R.DecodeScore(R.EncodeScore(1e30))
		T.check(math.abs(big / 1e30 - 1) < 1e-9, "Rundreise 1e30 relativ genau")
		T.eq(R.EncodeScore(0 / 0), 0, "NaN -> 0")
		T.eq(R.EncodeScore(-5), 0, "negativ -> 0")
		T.eq(R.EncodeScore(math.huge), 0, "inf -> 0")
	end },

	{ "Reihenfolge mit sehr großen Werten und eigene Platzierung", function(T, H)
		local srv = H.Server()
		local LB = srv.LeaderboardService
		local store = srv.env.services.DataStoreService.__data.ordered[srv.S.Config.LeaderboardStoreName]
		T.check(store ~= nil, "OrderedDataStore angelegt")
		-- 120 fremde Einträge, einige riesig
		for i = 1, 120 do
			store.data[tostring(1000 + i)] = srv.S.PressRules.EncodeScore(i * 1e20)
		end
		store.data["5000"] = srv.S.PressRules.EncodeScore(2 ^ 60)
		local player = H.Join(srv, 77, "Carla")
		local prof = H.Profile(srv, player)
		prof.games.press.lifetime = 50.5e20 -- zwischen Eintrag 50 und 51
		H.Advance(srv, 61)
		LB.Refresh(true)
		local view = LB.View(H.Session(srv, player))
		T.eq(view.available, true, "verfügbar")
		T.eq(#view.rows, 50, "Top 50")
		T.eq(view.rows[1].name, "Nutzer1120", "größter Wert zuerst")
		local ok = true
		for i = 2, #view.rows do
			if view.rows[i].value > view.rows[i - 1].value then
				ok = false
			end
		end
		T.check(ok, "absteigend sortiert")
		T.eq(view.own.rank, 71, "eigene Platzierung außerhalb der Top 50")
		-- eigener Wert ganz oben
		prof.games.press.lifetime = 1e300
		T.eq(LB.View(H.Session(srv, player)).own.rank, 1, "Platz 1 mit 1e300")
		-- Push an den Client
		srv.LeaderboardService.Push(H.Session(srv, player))
		local pushed = H.Notices(srv, player, "leaderboard")
		T.check(#pushed >= 1 and pushed[#pushed].available == true, "Ansicht an den Client gesendet")
	end },

	{ "Platzierung jenseits des gelesenen Bereichs", function(T, H)
		local srv = H.Server()
		local store = srv.env.services.DataStoreService.__data.ordered[srv.S.Config.LeaderboardStoreName]
		for i = 1, 600 do
			store.data[tostring(1000 + i)] = srv.S.PressRules.EncodeScore(1e6 + i)
		end
		local player = H.Join(srv, 88, "Dora")
		H.Profile(srv, player).games.press.lifetime = 10
		srv.LeaderboardService.Refresh(true)
		local view = srv.LeaderboardService.View(H.Session(srv, player))
		T.eq(view.own.rank, nil, "kein genauer Rang")
		T.eq(view.own.atLeast, 501, "mindestens Platz 501")
		T.eq(#srv.LeaderboardService.Cache.entries, 500, "höchstens 5 Seiten gelesen")
	end },

	{ "Schreib- und Lese-Drosselung", function(T, H)
		local srv = H.Server()
		local calls = srv.env.services.DataStoreService.__data.calls
		local player = H.Join(srv, 90, "Emil")
		local prof = H.Profile(srv, player)
		prof.games.press.upgrades = { pu1 = 5 }
		local sets0, sorted0 = calls.set, calls.sorted
		-- 10 Minuten Spielzeit mit ständigem Produzieren und vielen Refresh-Anfragen
		for _ = 1, 600 do
			H.Advance(srv, 1)
			H.Act(srv, player, "leaderboard_refresh")
		end
		local sets = calls.set - sets0
		local reads = calls.sorted - sorted0
		T.check(sets <= 600 / 120 + 1, "höchstens alle 120 s geschrieben (" .. sets .. ")")
		T.check(sets >= 4, "regelmäßig geschrieben (" .. sets .. ")")
		T.check(reads <= 600 / 60 + 1, "höchstens alle 60 s gelesen (" .. reads .. ")")
		-- Verlassen schreibt sofort
		H.Advance(srv, 5)
		local before = calls.set
		H.Leave(srv, player)
		T.eq(calls.set, before + 1, "Schreiben beim Verlassen")
		-- Profil speichert nie pro Klick
		local p2 = H.Join(srv, 91, "Fritz")
		local updates = calls.update
		for _ = 1, 50 do
			H.Act(srv, p2, "press_click", { count = 1 })
		end
		T.eq(calls.update, updates, "kein Profil-Speichern pro Klick")
	end },

	{ "DataStore-Fehler: Hinweis statt Absturz", function(T, H)
		local srv = H.Server()
		local ds = srv.env.services.DataStoreService.__data
		local player = H.Join(srv, 93, "Gina")
		ds.fail = true
		srv.LeaderboardService.Refresh(true)
		H.Advance(srv, 10)
		local view = srv.LeaderboardService.View(H.Session(srv, player))
		T.eq(view.available, false, "nicht verfügbar")
		T.eq(H.Act(srv, player, "leaderboard_refresh", { rid = 1 }), "ok", "Anfrage stürzt nicht ab")
		H.Advance(srv, 10)
		local notices = H.Notices(srv, player, "leaderboard")
		T.eq(notices[#notices].available, false, "Client erhält 'nicht verfügbar'")
		T.check(srv.World.BoardStatus.Text == srv.S.Locale.T("leaderboard_unavailable"), "Tafel zeigt Hinweis")
		T.eq(#H.Errors(srv.env), 0, "keine Laufzeitfehler")
		-- Spiel läuft weiter
		H.Act(srv, player, "press_click", { count = 3 })
		T.check(H.Profile(srv, player).games.press.clicks >= 3, "Spiel läuft weiter")
		ds.fail = false
		H.Advance(srv, 61)
		srv.LeaderboardService.Refresh(true)
		T.eq(srv.LeaderboardService.Cache.available, true, "erholt sich")
	end },
}
