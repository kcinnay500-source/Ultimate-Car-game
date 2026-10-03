-- Grundlage: echte 2.4.0-Hülle lädt ohne Verlust inkl. games, Normalisierung, Zahlenformat, Karriere, Katalog.
-- Läuft gegen die echten Module (GarageShared.Rules, GarageShared.Mini.*), ohne Server.
local NOW = 1760000000

local function modules(H)
	local g = H.Garage({ noServer = true })
	return g, g:Rules(), g:MiniShared("MiniRules"), g:Config()
end

-- Ein gespeicherter 2.4.0-Datensatz (data von 2.4.0, noch ohne games)
local function veteranData()
	return {
		version = 2, workshopVersion = 1, days = 42, money = 12345, xp = 250, level = 17, reputation = 33,
		bays = 2, offerSlots = 5, toolLevel = 4, completed = 23, serial = 40,
		jobs = {}, offers = {}, orders = {}, parkedJobs = {},
		inventory = { nexra_C_filter = 5, nexra_C_oil = 2 },
		equipment = {}, equipmentBays = {}, yardReady = {},
		loadout = { "scanner", "ratchet", "screwdriver", "multimeter", "impact" },
	}
end

return {
	{ "2.4.0-Hülle lädt ohne Verlust, games wird angelegt, version bleibt 2", function(T, H)
		local g, R, MiniRules, C = modules(H)
		local raw = veteranData()
		local d = R.LoadData(H.Copy(raw), C, NOW)
		T.eq(d.version, 2, "data.version")
		T.eq(d.money, 12345, "Geld")
		T.eq(d.level, 17, "Level")
		T.eq(d.xp, 250, "XP")
		T.eq(d.days, 42, "Tage")
		T.eq(d.reputation, 33, "Ruf")
		T.eq(d.bays, 2, "Hebebühnen")
		T.eq(d.offerSlots, 5, "Auftragsannahme")
		T.eq(d.toolLevel, 4, "Werkzeugqualität")
		T.eq(d.completed, 23, "abgeschlossene Aufträge")
		T.eq(d.inventory.nexra_C_filter, 5, "Lager 2.4.0 unverändert")
		T.eq(type(d.games), "table", "Minispiel-Bereich angelegt")
		T.eq(d.games.v, 1, "games.v")
		T.eq(d.games.press.scrap, 0, "Schrott Standardwert")
		T.eq(d.games.press.lifetime, 0, "Bestenlistenwert Standardwert")
		T.eq(d.games.tuningLevel, 1, "Tuning-Stufe Standardwert")
		T.eq(d.games.quiz.diagPoints, 0, "Diagnosepunkte Standardwert")
		T.eq(d.games.stats.jobsDone, 23, "Veteran: jobsDone = completed")
		T.eq(d.games.bays, nil, "keine 3.0-Werkstattfelder in games")
		T.eq(d.games.jobs, nil, "keine 2D-Aufträge in games")
		T.eq(d.credits, nil, "kein 3.0-Feld credits")
		T.eq(d.schema, nil, "kein 3.0-Feld schema")
		T.check(MiniRules.IsClean(d), "geladene Daten sauber")
		-- Mit Spielstand in games: nichts geht verloren
		local withGames = veteranData()
		withGames.games = MiniRules.DefaultGames()
		withGames.games.parts = 17
		withGames.games.tuningLevel = 6
		withGames.games.press.scrap = 5e20
		withGames.games.press.lifetime = 7e20
		withGames.games.press.upgrades = { pu0 = 3, pu7 = 1 }
		withGames.games.press.rebirths = 2
		withGames.games.tuning.projects = { { slot = 1, id = "folie", startedAt = NOW - 10, duration = 300 } }
		withGames.games.milestones = { m_jobs_10 = true }
		withGames.games.stats.jobsDone = 99
		local d2 = R.LoadData(H.Copy(withGames), C, NOW)
		T.eq(d2.games.parts, 17, "Altteile")
		T.eq(d2.games.tuningLevel, 6, "Tuning-Stufe")
		T.eq(d2.games.press.scrap, 5e20, "sehr großer Schrott bleibt")
		T.eq(d2.games.press.lifetime, 7e20, "Bestenlistenwert bleibt")
		T.eq(d2.games.press.upgrades.pu7, 1, "Upgrades")
		T.eq(d2.games.press.rebirths, 2, "Rebirths")
		T.eq(#d2.games.tuning.projects, 1, "laufendes Tuning")
		T.eq(d2.games.milestones.m_jobs_10, true, "Meilenstein")
		T.eq(d2.games.stats.jobsDone, 99, "Statistik nicht erneut aus completed")
		local _ = g
	end },

	{ "Echte Hülle {version=2,data,receipts,lock} über den Server: laden, speichern, erneut laden", function(T, H)
		local g = H.Garage()
		local MiniRules = g:MiniShared("MiniRules")
		local data = veteranData()
		data.games = MiniRules.DefaultGames()
		data.games.press.scrap = 4242
		data.games.parts = 9
		data.games.milestones = { m_jobs_10 = true }
		g:Seed(1001, { version = 2, data = data, receipts = { ["kauf-1"] = true } })
		local p = g:Join(1001)
		g:Advance(1)
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
		local d = g:D(p)
		T.eq(d.money, 12345, "Geld geladen")
		T.eq(d.level, 17, "Level geladen")
		T.check(d.games.press.scrap >= 4242, "Schrott geladen")
		T.eq(d.games.parts, 9, "Altteile geladen")
		T.eq(d.games.milestones.m_jobs_10, true, "Meilenstein geladen")
		local rec = g:Record(1001)
		T.eq(rec.version, 2, "Hülle version")
		T.eq(rec.data.version, 2, "data.version bleibt 2")
		T.eq(type(rec.data.games), "table", "games im gespeicherten Datensatz")
		T.eq(rec.receipts["kauf-1"], true, "Belege bleiben")
		d.games.parts = 11
		g:Leave(p)
		g:Advance(5)
		rec = g:Record(1001)
		T.eq(rec.lock, nil, "Sperre freigegeben")
		T.eq(rec.data.games.parts, 11, "games gespeichert")
		for k in pairs(rec) do
			T.check(k == "version" or k == "data" or k == "receipts" or k == "lock", "keine fremden Hüllenfelder (" .. tostring(k) .. ")")
		end
		local g2 = H.Garage({ shareDataStoresWith = g })
		local p2 = g2:Join(1001)
		g2:Advance(1)
		T.eq(g2:D(p2).games.parts, 11, "games nach Wiederbeitritt")
		T.eq(g2:D(p2).money, 12345, "Geld nach Wiederbeitritt")
		T.eq(#g2:Errors(), 0, "keine Laufzeitfehler")
	end },

	{ "Doppeltes Laden verändert nichts", function(T, H)
		local _, R, _, C = modules(H)
		local once = R.LoadData(H.Copy(veteranData()), C, NOW)
		local twice = R.LoadData(H.Copy(once), C, NOW)
		local ok, where = H.DeepEqual(once, twice)
		T.check(ok, "LoadData ist idempotent (Veteran), Abweichung bei " .. tostring(where))
		-- (R.LoadData(nil) liefert R.NewData; ab dem ersten echten Laden ist das Ergebnis stabil)
		local fresh = R.LoadData(H.Copy(R.NewData(NOW)), C, NOW)
		ok, where = H.DeepEqual(fresh, R.LoadData(H.Copy(fresh), C, NOW))
		T.check(ok, "LoadData ist idempotent (neu), Abweichung bei " .. tostring(where))
		local p = R.LoadData(nil, C, NOW)
		p.games.press.upgrades = { pu0 = 3, pu1 = 2 }
		p.games.tuning.projects = { { slot = 1, id = "folie", startedAt = 100, duration = 300 } }
		p.games.parking.puzzle = { cars = { 0, 1, 2, 3, 5, 9, 12 }, target = 0, exit = 15, moves = 1, solved = false, crashed = false }
		p.games.milestones = { m_jobs_10 = true }
		p.games.daily = { day = "2025-10-09", claimed = true, active = true, progress = { clicks = 5 }, goalsClaimed = { d_clicks = true } }
		local a = R.LoadData(H.Copy(p), C, NOW)
		ok, where = H.DeepEqual(a, R.LoadData(H.Copy(a), C, NOW))
		T.check(ok, "LoadData ist idempotent (Spielstand), Abweichung bei " .. tostring(where))
		T.eq(a.games.parking.puzzle.moves, 1, "Rätsel bleibt")
		T.eq(a.games.daily.goalsClaimed.d_clicks, true, "Tagesziel bleibt")
	end },

	{ "Beschädigte Minispiel-Felder werden normalisiert", function(T, H)
		local g, R, MiniRules, C = modules(H)
		local nan = 0 / 0
		local raw = veteranData()
		raw.money = nan
		raw.level = -5
		raw.xp = math.huge
		raw.games = {
			parts = -3,
			tuningLevel = 1e9,
			scrapyardLevel = nan,
			press = { scrap = nan, lifetime = -1, runScrap = math.huge, upgrades = { pu0 = nan, pu1 = -2, pu2 = 4, hack = 99, [5] = 1 }, rebirths = "x", combo = 1e9 },
			tuning = { projects = { { slot = 1, id = "folie", startedAt = nan, duration = -5 }, "kaputt", { slot = 9, id = "gibtsnicht", startedAt = 1, duration = 5 } }, lastIdle = -100 },
			quiz = { diagPoints = nan, current = { order = { 1, 2, 3, 4 } } },
			parking = { streak = -1, puzzle = { cars = { 1, 1, 99, "x" }, target = 99 } },
			stats = { jobsDone = nan, hack = 5 },
			milestones = { m_jobs_10 = "ja", gibtsnicht = true },
			daily = { day = 5, progress = { clicks = nan, hack = 1 } },
			jobs = { "x" },
			bays = 3,
		}
		local d = R.LoadData(raw, C, NOW)
		T.eq(d.money, C.StartMoney, "NaN-Geld -> Standard")
		T.eq(d.level, 1, "negatives Level -> 1")
		T.eq(d.xp, 0, "inf-XP -> 0")
		local gm = d.games
		T.eq(gm.parts, g:MiniShared("MiniConfig").StartParts, "negative Altteile -> Standard")
		T.eq(gm.tuningLevel, 100, "Tuning-Stufe gedeckelt")
		T.eq(gm.scrapyardLevel, 1, "NaN-Stufe -> 1")
		T.eq(gm.press.scrap, 0, "NaN-Schrott -> 0")
		T.eq(gm.press.lifetime, 0, "negativer Bestenlistenwert -> 0")
		T.eq(gm.press.runScrap, 0, "inf-Durchlauf -> 0")
		T.eq(gm.press.upgrades.pu0, nil, "NaN-Upgrade entfernt")
		T.eq(gm.press.upgrades.pu1, nil, "negatives Upgrade entfernt")
		T.eq(gm.press.upgrades.pu2, 4, "gültiges Upgrade bleibt")
		T.eq(gm.press.upgrades.hack, nil, "unbekannter Schlüssel entfernt")
		T.eq(gm.press.rebirths, 0, "Text-Rebirths -> 0")
		T.eq(#gm.tuning.projects, 0, "ungültige Projekte entfernt")
		T.eq(gm.tuning.lastIdle, 0, "negative Zeit -> 0")
		T.eq(gm.quiz.diagPoints, 0, "NaN-Diagnose -> 0")
		T.eq(gm.quiz.current, nil, "offene Quizfrage wird nie aus dem Profil geladen")
		T.eq(gm.parking.streak, 0, "negative Serie -> 0")
		T.eq(gm.parking.puzzle, false, "kaputtes Rätsel verworfen")
		T.eq(gm.stats.jobsDone, 0, "NaN-Statistik -> 0")
		T.eq(gm.stats.hack, nil, "unbekannte Statistik entfernt")
		T.eq(gm.milestones.m_jobs_10, nil, "ungültiger Meilenstein-Eintrag entfernt")
		T.eq(gm.milestones.gibtsnicht, nil, "unbekannter Meilenstein entfernt")
		T.eq(gm.daily.day, "", "ungültiger Tag -> leer")
		T.eq(gm.daily.progress.clicks, 0, "NaN-Fortschritt -> 0")
		T.eq(gm.daily.progress.hack, nil, "unbekannter Fortschritt entfernt")
		T.eq(gm.jobs, nil, "3.0-Aufträge entfallen")
		T.eq(gm.bays, nil, "3.0-Hebebühnen entfallen")
		T.check(MiniRules.IsClean(d), "Profil enthält danach keine NaN/inf")
		T.check(not MiniRules.IsClean({ a = { b = 0 / 0 } }), "IsClean erkennt NaN")
		T.check(not MiniRules.IsClean({ a = math.huge }), "IsClean erkennt inf")
		T.check(not MiniRules.IsClean({ f = function() end }), "IsClean erkennt Funktionen")
		-- Tiefe: games höchstens 5 Ebenen (Grenze von R.Snapshot ist 12)
		local function depth(v)
			if type(v) ~= "table" then
				return 0
			end
			local m = 0
			for _, x in pairs(v) do
				m = math.max(m, depth(x))
			end
			return m + 1
		end
		T.check(depth(d.games) <= 5, "Verschachtelungstiefe games ≤ 5 (" .. depth(d.games) .. ")")
	end },

	{ "Zahlenformat (eine Formatierung für Werkstatt und Minispiele)", function(T, H)
		local g = H.Garage({ noServer = true })
		local L = g:MiniShared("MiniLocale")
		T.eq(L.Number(0), "0", "0")
		T.eq(L.Number(999), "999", "999")
		T.eq(L.Number(12345), "12.345", "Tausenderpunkt")
		T.eq(L.Number(99999), "99.999", "unter 100 Tsd.")
		T.eq(L.Number(123456), "123 Tsd.", "Tsd.")
		T.eq(L.Number(1200000), "1,2 Mio.", "Mio.")
		T.eq(L.Number(1000000), "1 Mio.", "glatte Mio.")
		T.eq(L.Number(3.5e9), "3,5 Mrd.", "Mrd.")
		T.eq(L.Number(7e12), "7 Bio.", "Bio.")
		T.eq(L.Number(2.26e15), "2,3 Brd.", "Brd.")
		T.eq(L.Number(-1500000), "-1,5 Mio.", "negativ")
		T.eq(L.Number(0 / 0), "0", "NaN")
		T.eq(L.Number(math.huge), "0", "inf")
		T.check(L.Number(1e30):find("e30") ~= nil, "sehr groß wissenschaftlich: " .. L.Number(1e30))
		T.eq(L.Duration(3725), "1 Std. 02 Min.", "Dauer Std.")
		T.eq(L.Duration(65), "1 Min. 05 Sek.", "Dauer Min.")
		T.eq(L.Duration(-5), "0 Sek.", "negative Dauer")
		T.eq(L.Credits(1500), "1.500 Cr", "Credits")
		T.eq(L.Factor(1.25), "×1,25", "Faktor")
		T.eq(L.Percent(0.35), "35 %", "Prozent")
		T.eq(L.T("offline_press", "5"), "Während du weg warst: +5", "Platzhalter")
		T.eq(L.T("coming_soon", "Das Autohaus"), "Das Autohaus eröffnet bald.", "Hinweis eröffnet bald")
	end },

	{ "Karriere: Minispiel-XP über die 2.4.0-Kurve", function(T, H)
		local _, R, MiniRules, C = modules(H)
		local d = R.NewData(NOW)
		T.eq(R.XPNeeded(d), math.floor(80 + 22 + 4), "XPNeeded Level 1")
		local money = d.money
		local r = MiniRules.GainXP(d, R.XPNeeded(d))
		T.eq(d.level, 2, "Levelaufstieg")
		T.eq(r.levels, 1, "ein Level")
		T.eq(r.credits, 120 + 2 * 18, "Level-Bonus 2.4.0")
		T.eq(d.money, money + 156, "Credits gutgeschrieben")
		T.eq(d.reputation, 2, "Ruf +2")
		local r2 = MiniRules.GainXP(d, 0 / 0)
		T.eq(r2.levels, 0, "NaN-XP ignoriert")
		local r3 = MiniRules.GainXP(d, -50)
		T.eq(r3.levels, 0, "negative XP ignoriert")
		T.check(d.xp >= 0, "XP nie negativ")
		T.eq(MiniRules.AddMoney(d, 0 / 0), 0, "NaN-Geld ignoriert")
		d.money = C.NumberCap - 1e9
		T.near(MiniRules.AddMoney(d, 5e9), 1e9, 2e8, "Geld auf NumberCap gedeckelt")
		T.eq(d.money, C.NumberCap, "Deckel")
		d.money = 10
		T.eq(MiniRules.AddMoney(d, -50), -10, "nie unter 0")
		T.check(MiniRules.IsClean(d), "Profil sauber")
	end },

	{ "Tageswechsel nach UTC", function(T, H)
		local _, _, MiniRules = modules(H)
		T.eq(MiniRules.DayKey(0), "1970-01-01", "Epoche")
		T.eq(MiniRules.DayKey(86399), "1970-01-01", "letzte Sekunde")
		T.eq(MiniRules.DayKey(86400), "1970-01-02", "nächster Tag")
	end },

	{ "Katalog: 100 Presse-Upgrades wie HTML, Quizfragen, keine alte Punktewährung", function(T, H)
		local g = H.Garage({ noServer = true })
		local Cat = g:MiniShared("MiniCatalog")
		T.eq(#Cat.PressUpgrades, 100, "100 Upgrades")
		local bad = 0
		for i, u in ipairs(Cat.PressUpgrades) do
			local idx = i - 1
			if not (u.id == "pu" .. idx and u.type == idx % 5 and u.baseCost == math.floor(8 * 1.19 ^ idx + 0.5) and u.baseEffect == 1 + math.floor(idx / 5) and type(u.name) == "string") then
				bad += 1
			end
		end
		T.eq(bad, 0, "alle Upgrades nach der HTML-Formel")
		local names = {}
		for _, u in ipairs(Cat.PressUpgrades) do
			T.check(not names[u.name], "Name eindeutig: " .. u.name)
			names[u.name] = true
		end
		-- Quizfragen mit Lösung nur auf dem Server (ServerScriptService.Garage.Mini.QuizBank)
		local Bank = g:Require("ServerScriptService.Garage.Mini.QuizBank")
		T.check(#Bank.Questions >= 7, "mindestens die 7 HTML-Fragen")
		for _, q in ipairs(Bank.Questions) do
			T.eq(#q.a, 4, "4 Antworten: " .. q.q)
		end
		T.eq(Cat.Questions, nil, "kein Fragenkatalog im geteilten MiniCatalog")
		-- Kein Skript, das der Client sieht (ReplicatedStorage, StarterPlayer), enthält eine richtige Antwort
		local leaks = {}
		for _, root in ipairs({ "ReplicatedStorage", "StarterPlayer", "StarterGui", "ReplicatedFirst" }) do
			local node = g:Find(root)
			for _, x in ipairs(node and node:GetDescendants() or {}) do
				if x:IsA("LuaSourceContainer") then
					for _, q in ipairs(Bank.Questions) do
						if string.find(x.Source, q.a[1], 1, true) and string.find(x.Source, q.q, 1, true) then
							table.insert(leaks, x:GetFullName() .. ": " .. q.q)
							break
						end
					end
				end
			end
		end
		T.eq(#leaks, 0, "Antwortschlüssel beim Client: " .. table.concat(leaks, "; "))
		local L = g:Require("ReplicatedStorage.GarageShared.Locale")
		for k, v in pairs(L.Catalog.en or {}) do
			T.check(not tostring(k):find("Autopunkt") and not tostring(v):find("car points"), "keine alte Punktewährung im 2.4.0-Katalog: " .. tostring(k))
		end
	end },
}
