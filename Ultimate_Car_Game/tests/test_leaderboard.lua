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
		local g = H.Garage({ level = 12 })
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
		local g = H.Garage({ level = 12 })
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
		local g = H.Garage({ level = 12 })
		local calls = g:DataStoreMock().calls
		local player = g:Join(90, { name = "Emil" })
		g:Advance(1)
		g:D(player).games.press.upgrades = { pu1 = 5 }
		local sets0, sorted0 = calls.ordered, calls.sorted
		local store = ordered(g)
		-- 10 Minuten Spielzeit mit ständigem Produzieren und vielen Refresh-Anfragen
		for _ = 1, 600 do
			g:Advance(1)
			g:Act(player, "mini_leaderboard_refresh")
		end
		local sets = calls.ordered - sets0
		local reads = calls.sorted - sorted0
		T.check(sets <= 600 / 120 + 1, "höchstens alle 120 s geschrieben (" .. sets .. ")")
		T.check(sets >= 4, "regelmäßig geschrieben (" .. sets .. ")")
		T.check(reads <= 600 / 60 + 1, "höchstens alle 60 s gelesen (" .. reads .. ")")
		T.check(store["90"] ~= nil, "Eintrag des Spielers vorhanden")
		-- Verlassen schreibt sofort (auch wenn die letzte Schreibung < 120 s her ist)
		g:Advance(5)
		local before = calls.ordered
		g:Leave(player)
		T.eq(calls.ordered, before + 1, "Schreiben beim Verlassen")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler")
	end },

	{ "Schreiben nur mit beschreibbarem Profil, in Studio nie", function(T, H)
		-- Fremde Sperre: temporäre Sitzung, kein Eintrag in der Bestenliste
		local g = H.Garage({ level = 12 })
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
		local gs = H.Garage({ level = 12,  studio = true })
		local ps = gs:Join(96)
		gs:Advance(1)
		gs:D(ps).games.press.upgrades = { pu1 = 5 }
		gs:Advance(300)
		gs:Leave(ps)
		gs:Advance(5)
		T.eq(ordered(gs)["96"], nil, "in Studio kein Bestenlisten-Eintrag")
		-- Normalfall zum Vergleich
		local gn = H.Garage({ level = 12 })
		local pn = gn:Join(97)
		gn:Advance(1)
		gn:D(pn).games.press.upgrades = { pu1 = 5 }
		gn:Advance(10)
		gn:Leave(pn)
		gn:Advance(5)
		T.check(ordered(gn)["97"] ~= nil, "mit writable geschrieben")
		T.eq(#g:Errors() + #gs:Errors() + #gn:Errors(), 0, "keine Laufzeitfehler")
	end },

	{ "Verspäteter Wiederholungsversuch überschreibt keinen neueren Wert (Verlassen, anderer Server)", function(T, H)
		local g = H.Garage({ level = 12 })
		local LB, PR = g:MiniServer("LeaderboardService"), g:MiniShared("PressRules")
		local ds = g:DataStoreMock()
		local player = g:Join(98, { name = "Olga" })
		g:Advance(1)
		local d = g:D(player)
		d.games.press.upgrades = {}
		local ms = g:MiniState(player)
		local store = ordered(g)
		-- Tick-Schreiben mit altem Wert c1 scheitert einmal (Drosselung) und wartet 1 s auf den Wiederholungsversuch
		d.games.press.lifetime = 1000
		ms.leaderboardWrittenAt = g:Now() - 1000
		ms.leaderboardWrittenCode = -1
		ds.failNext = 1
		g:Advance(0.5)
		T.eq(ds.failNext, 0, "erster Versuch ist gescheitert")
		T.eq(LB.Pending, 1, "Wiederholung steht aus")
		-- Währenddessen verlässt der Spieler das Spiel: Schreiben mit dem höheren Wert c2
		d.games.press.lifetime = 5e6
		local c2 = PR.EncodeScore(5e6)
		g:Leave(player)
		T.eq(store["98"], c2, "Verlassen schreibt den neuen Wert")
		g:Advance(5)
		T.eq(LB.Pending, 0, "nichts mehr offen")
		T.eq(store["98"], c2, "alter Wiederholungsversuch überschreibt den höheren Wert nicht")
		-- Anderer Server mit älterem Stand: UpdateAsync mit math.max lässt den höheren Wert stehen
		local stale = {
			userId = 98, leaderboardWrittenAt = 0, leaderboardWrittenCode = -1,
			p = { profile = { data = { games = { press = { lifetime = 10 } } } } },
		}
		T.eq(LB.Write(stale, true, true), true, "Schreibaufruf gelingt")
		T.eq(store["98"], c2, "niedrigerer Wert eines anderen Servers ändert nichts")
		stale.p.profile.data.games.press.lifetime = 9e9
		stale.leaderboardWrittenCode = -1
		LB.Write(stale, true, true)
		T.eq(store["98"], PR.EncodeScore(9e9), "höherer Wert wird geschrieben")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Bestenliste beim Verlassen nur nach gelungenem Speichern (offener Robux-Beleg, verlorene Sperre)", function(T, H)
		-- Fall 1: offener Robux-Beleg – P.Save verweigert, also kein Bestenlisten-Wert, den das Profil nicht hat
		local g = H.Garage({ level = 12 })
		local PR = g:MiniShared("PressRules")
		local p1 = g:Join(99, { name = "Paul" })
		g:Advance(1)
		local d1 = g:D(p1)
		d1.games.press.upgrades = {}
		g:Advance(1)
		local before = ordered(g)["99"]
		d1.games.press.lifetime = 7e6
		g:Profile(p1).receiptPending = { id = "kauf-offen", amount = 100, snapshot = { money = d1.money } }
		g:Leave(p1)
		g:Advance(5)
		T.eq(ordered(g)["99"], before, "kein ungespeicherter Wert in der Bestenliste (offener Beleg)")
		-- Fall 2: ein anderer Server hat die Sperre übernommen – Speichern scheitert (lostLock)
		local p2 = g:Join(100, { name = "Quirin" })
		g:Advance(1)
		local d2 = g:D(p2)
		d2.games.press.upgrades = {}
		g:Advance(1)
		local before2 = ordered(g)["100"]
		d2.games.press.lifetime = 8e6
		g:Record(100).lock = { token = "anderer-server", expires = g:Now() + 170 }
		g:Leave(p2)
		g:Advance(5)
		T.eq(ordered(g)["100"], before2, "kein ungespeicherter Wert in der Bestenliste (Sperre verloren)")
		-- Normalfall: gespeichert, dann geschrieben
		local p3 = g:Join(101, { name = "Rita" })
		g:Advance(1)
		local d3 = g:D(p3)
		d3.games.press.upgrades = {}
		d3.games.press.lifetime = 9e6
		g:Leave(p3)
		g:Advance(5)
		T.eq(ordered(g)["101"], PR.EncodeScore(9e6), "nach gelungenem Speichern geschrieben")
		T.eq(g:Record(101).data.games.press.lifetime, 9e6, "Profil enthält denselben Wert")
		-- BindToClose: Speichern und danach Bestenliste, der Server wartet darauf
		local gc = H.Garage({ level = 12 })
		local pc = gc:Join(102, { name = "Sara" })
		gc:Advance(1)
		local dc = gc:D(pc)
		dc.games.press.upgrades = {}
		dc.games.press.lifetime = 6e6
		gc:Close()
		T.eq(ordered(gc)["102"], PR.EncodeScore(6e6), "BindToClose schreibt nach dem Speichern")
		T.eq(#g:Errors() + #gc:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText() .. gc:ErrorText())
	end },

	{ "DataStore-Fehler: Hinweis statt Absturz, Tafel zeigt Hinweis", function(T, H)
		local g = H.Garage({ level = 12,  before = function(g)
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
		local g = H.Garage({ level = 12,  studio = true, dataStore = { getFail = true }, before = function(g)
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
