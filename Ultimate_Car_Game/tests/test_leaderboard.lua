-- Bestenliste (Kodierung, Reihenfolge, eigene Platzierung, Drosselung, Schreiben nur mit writable, Fehlerfall)
local function ordered(g)
	local MC = g:MiniShared("MiniConfig")
	local ds = g:DataStoreMock()
	ds.ordered[MC.LeaderboardStoreName] = ds.ordered[MC.LeaderboardStoreName] or { data = {} }
	return ds.ordered[MC.LeaderboardStoreName].data
end

return {
	{ "Kodierung ist monoton, ganzzahlig und dekodierbar", function(T, H)
		local g = H.Garage({ noServer = true })
		local R = g:MiniShared("PressRules")
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
		local g = H.Garage()
		local LB, PR = g:MiniServer("LeaderboardService"), g:MiniShared("PressRules")
		local store = ordered(g)
		for i = 1, 120 do
			store[tostring(1000 + i)] = PR.EncodeScore(i * 1e20)
		end
		store["5000"] = PR.EncodeScore(2 ^ 60)
		local player = g:Join(77, { name = "Carla" })
		g:Advance(1)
		local d = g:D(player)
		d.games.press.upgrades = {}
		d.games.press.lifetime = 50.5e20 -- zwischen Eintrag 50 und 51
		LB.Refresh(true)
		local ms = g:MiniState(player)
		local view = LB.View(ms)
		T.eq(view.available, true, "verfügbar")
		T.eq(#view.rows, 50, "Top 50")
		T.eq(view.rows[1].name, "Nutzer1120", "größter Wert zuerst")
		local sorted = true
		for i = 2, #view.rows do
			if view.rows[i].value > view.rows[i - 1].value then
				sorted = false
			end
		end
		T.check(sorted, "absteigend sortiert")
		T.eq(view.own.rank, 71, "eigene Platzierung außerhalb der Top 50")
		d.games.press.lifetime = 1e300
		T.eq(LB.View(ms).own.rank, 1, "Platz 1 mit 1e300")
		-- Ansicht an den Client (erste nach hello, danach auf Anfrage)
		g:Send(player, "hello")
		local pushed = g:Notices(player, "leaderboard")
		T.check(#pushed >= 1 and pushed[#pushed].available == true, "Ansicht an den Client gesendet")
		local m = g:Mark()
		g:Advance(6)
		T.eq(g:Act(player, "mini_leaderboard_refresh", { rid = 1 }), "ok", "Aktualisieren")
		T.check(#g:Notices(player, "leaderboard", m) >= 1, "Ansicht nach Anfrage")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Platzierung jenseits des gelesenen Bereichs", function(T, H)
		local g = H.Garage()
		local LB, PR = g:MiniServer("LeaderboardService"), g:MiniShared("PressRules")
		local store = ordered(g)
		for i = 1, 600 do
			store[tostring(1000 + i)] = PR.EncodeScore(1e6 + i)
		end
		local player = g:Join(88, { name = "Dora" })
		g:Advance(1)
		g:D(player).games.press.upgrades = {}
		g:D(player).games.press.lifetime = 10
		LB.Refresh(true)
		local view = LB.View(g:MiniState(player))
		T.eq(view.own.rank, nil, "kein genauer Rang")
		T.eq(view.own.atLeast, 501, "mindestens Platz 501")
		T.eq(#LB.Cache.entries, 500, "höchstens 5 Seiten gelesen")
	end },

	{ "Schreib- und Lese-Drosselung", function(T, H)
		local g = H.Garage()
		local calls = g:DataStoreMock().calls
		local player = g:Join(90, { name = "Emil" })
		g:Advance(1)
		g:D(player).games.press.upgrades = { pu1 = 5 }
		local sets0, sorted0 = calls.set, calls.sorted
		local store = ordered(g)
		-- 10 Minuten Spielzeit mit ständigem Produzieren und vielen Refresh-Anfragen
		for _ = 1, 600 do
			g:Advance(1)
			g:Act(player, "mini_leaderboard_refresh")
		end
		local sets = calls.set - sets0
		local reads = calls.sorted - sorted0
		T.check(sets <= 600 / 120 + 1, "höchstens alle 120 s geschrieben (" .. sets .. ")")
		T.check(sets >= 4, "regelmäßig geschrieben (" .. sets .. ")")
		T.check(reads <= 600 / 60 + 1, "höchstens alle 60 s gelesen (" .. reads .. ")")
		T.check(store["90"] ~= nil, "Eintrag des Spielers vorhanden")
		-- Verlassen schreibt sofort (auch wenn die letzte Schreibung < 120 s her ist)
		g:Advance(5)
		local before = calls.set
		g:Leave(player)
		T.eq(calls.set, before + 1, "Schreiben beim Verlassen")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler")
	end },

	{ "Schreiben nur mit beschreibbarem Profil, in Studio nie", function(T, H)
		-- Fremde Sperre: temporäre Sitzung, kein Eintrag in der Bestenliste
		local g = H.Garage()
		g:Seed(95, { version = 2, data = { version = 2, money = 50, level = 1 }, receipts = {}, lock = { token = "anderer-server", expires = g:Now() + 170 } })
		local p = g:Join(95)
		g:Advance(1)
		T.eq(g:Profile(p).writable, false, "Profil nicht beschreibbar")
		g:D(p).games.press.upgrades = { pu1 = 5 }
		g:Advance(300)
		g:Leave(p)
		g:Advance(5)
		T.eq(ordered(g)["95"], nil, "kein Bestenlisten-Eintrag ohne writable")
		-- Studio: nie schreiben
		local gs = H.Garage({ studio = true })
		local ps = gs:Join(96)
		gs:Advance(1)
		gs:D(ps).games.press.upgrades = { pu1 = 5 }
		gs:Advance(300)
		gs:Leave(ps)
		gs:Advance(5)
		T.eq(ordered(gs)["96"], nil, "in Studio kein Bestenlisten-Eintrag")
		-- Normalfall zum Vergleich
		local gn = H.Garage()
		local pn = gn:Join(97)
		gn:Advance(1)
		gn:D(pn).games.press.upgrades = { pu1 = 5 }
		gn:Advance(10)
		gn:Leave(pn)
		gn:Advance(5)
		T.check(ordered(gn)["97"] ~= nil, "mit writable geschrieben")
		T.eq(#g:Errors() + #gs:Errors() + #gn:Errors(), 0, "keine Laufzeitfehler")
	end },

	{ "DataStore-Fehler: Hinweis statt Absturz, Tafel zeigt Hinweis", function(T, H)
		local g = H.Garage({ before = function(g)
			g:BuildCity({})
		end })
		local L = g:MiniShared("MiniLocale")
		local LB = g:MiniServer("LeaderboardService")
		local ds = g:DataStoreMock()
		local player = g:Join(93, { name = "Gina" })
		g:Advance(2)
		g:Send(player, "hello")
		ds.fail = true
		LB.Refresh(true)
		g:Advance(10)
		local view = LB.View(g:MiniState(player))
		T.eq(view.available, false, "nicht verfügbar")
		g:Advance(6)
		local m = g:Mark()
		T.eq(g:Act(player, "mini_leaderboard_refresh", { rid = 1 }), "ok", "Anfrage stürzt nicht ab")
		g:Advance(10)
		local notices = g:Notices(player, "leaderboard", m)
		T.eq(notices[#notices] and notices[#notices].available, false, "Client erhält 'nicht verfügbar'")
		local status = g:Find("Workspace.City.LeaderboardBoard"):FindFirstChild("Status", true)
		T.eq(status.Text, L.T("leaderboard_unavailable"), "Tafel zeigt Hinweis")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
		-- Spiel läuft weiter
		local clicks = g:D(player).games.press.clicks
		g:Act(player, "mini_press_click", { count = 3 })
		T.check(g:D(player).games.press.clicks >= clicks + 3, "Spiel läuft weiter")
		ds.fail = false
		g:Advance(61)
		LB.Refresh(true)
		T.eq(LB.Cache.available, true, "erholt sich")
		g:Advance(1)
		T.eq(status.Text, L.T("leaderboard_title"), "Tafel wieder mit Titel")
		local row1 = g:Find("Workspace.City.LeaderboardBoard"):FindFirstChild("Row1", true)
		T.check(row1.Text:find("1%.") ~= nil, "Tafel-Zeile 1 gefüllt: " .. tostring(row1.Text))
	end },

	{ "Tafel zeigt Hinweis, wenn die Bestenliste fehlt (Studio ohne DataStore)", function(T, H)
		local g = H.Garage({ studio = true, dataStore = { getFail = true }, before = function(g)
			g:BuildCity({})
		end })
		local L = g:MiniShared("MiniLocale")
		g:Join(94)
		g:Advance(2)
		local status = g:Find("Workspace.City.LeaderboardBoard"):FindFirstChild("Status", true)
		T.eq(status.Text, L.T("leaderboard_unavailable"), "nicht mehr 'wird geladen'")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
