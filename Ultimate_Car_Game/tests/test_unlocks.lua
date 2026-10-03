-- Ausbaustufe 4, Meilenstein 1: Freischaltungen (Unlocks), Prestige (PrestigeRules) und Meta-Daten (MetaRules)
-- als reine Module gegen die echte GameConfig, ohne Server (MiniRules ruft MetaRules noch nicht auf).
local NOW = 1760000000

local function modules(H)
	local g = H.Garage({ noServer = true })
	return g, g:MiniShared("GameConfig"), g:MiniShared("Unlocks"), g:MiniShared("PrestigeRules"), g:MiniShared("MetaRules")
end

-- Profil wie R.NewData, dazu meta/prestige (bis MiniRules.DefaultGames das selbst anlegt)
local function profile(g, level)
	local d = g:Rules().NewData(NOW)
	d.level = level or 1
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	return d
end

return {
	{ "Unlock-Tabelle: sortiert, eindeutig, Vertragslevel, alle Autos gestreckt (Elys 90), Nachschlagetabellen", function(T, H)
		local g, GC, U = modules(H)
		local C = g:Config()
		local seen, last = {}, 0
		local kindSet = {}
		for _, k in ipairs(GC.UnlockKinds) do
			kindSet[k] = true
		end
		for i, u in ipairs(GC.Unlocks) do
			T.check(u.level >= last, "nach Level sortiert bei " .. u.key)
			last = u.level
			T.check(not seen[u.key], "Schlüssel eindeutig " .. u.key)
			seen[u.key] = true
			T.check(type(u.title) == "string" and #u.title > 0 and type(u.hint) == "string" and #u.hint > 0, "Titel und Hinweis " .. u.key)
			T.check(GC.UnlockByKey[u.key] == u, "UnlockByKey " .. u.key)
			T.eq(u.order, i, "order " .. u.key)
			T.check(kindSet[u.kind], "Art bekannt " .. u.key)
			T.check(u.key:sub(1, #u.kind + 1) == u.kind .. ":" or u.key == "auction:player", "Schlüssel passt zur Art " .. u.key)
		end
		local expect = {
			["mode:tycoon"] = 1, ["mode:openworld"] = 1, ["story:1"] = 1,
			["feature:press"] = 2, ["feature:scrapyard"] = 3, ["feature:dealer"] = 3, ["feature:quiz"] = 4, ["feature:parking"] = 5,
			["feature:tuning"] = 6, ["feature:track"] = 8, ["feature:carwash"] = 8, ["feature:arcade"] = 10, ["feature:auction"] = 12,
			["auction:player"] = 20, ["story:2"] = 5, ["story:3"] = 15, ["story:4"] = 30, ["story:5"] = 50,
			["building:autohaus"] = 10, ["building:schrottplatz"] = 18, ["building:produktion"] = 30,
			["car:komet"] = 3, ["car:komet_s2"] = 8, ["car:nord"] = 14, ["car:komet_urban"] = 22, ["car:atlas"] = 32,
			["car:vektor"] = 45, ["car:vektor_gtx"] = 58, ["car:aureon"] = 72, ["car:elys"] = 90,
			["car:komet_rally"] = 10, ["car:nord_classic"] = 18, ["car:vektor_gold"] = 50, ["car:aureon_nero"] = 78, ["car:elys_proto"] = 95,
		}
		for key, lvl in pairs(expect) do
			T.eq(U.Level(key), lvl, "Level " .. key)
		end
		for _, car in ipairs(C.Cars) do
			local lvl = U.Level("car:" .. car.id)
			T.check(lvl ~= nil, "Eintrag für " .. car.id)
			T.check(lvl ~= nil and lvl >= car.level, "später als 2.4.0 " .. car.id)
			T.eq(GC.UnlockByKey["car:" .. car.id].title, car.name, "Name aus C.Cars " .. car.id)
			T.eq(GC.UnlockByKey["car:" .. car.id].special, nil, "Händlermodell " .. car.id)
		end
		T.eq(GC.UnlockByKey["car:elys_proto"].special, true, "Sondermodell markiert")
		T.eq(U.CarLevel("elys"), 90, "CarLevel elys")
		T.eq(U.CarLevel("elys_proto"), 95, "CarLevel Sondermodell")
		T.eq(U.CarLevel("gibtsnicht"), nil, "unbekanntes Modell")
		T.eq(U.CarLevel(42), nil, "keine Zeichenkette")
		GC.UnlockByKey["car:komet"] = nil -- Eintrag entfernt: Rückfall auf das 2.4.0-Level
		T.eq(U.Level("car:komet"), nil, "Level ohne Eintrag")
		T.eq(U.CarLevel("komet"), C.CarById.komet.level, "Rückfall auf C.Cars.level")
		T.eq(U.Level("nix"), nil, "unbekannt")
		T.eq(U.Level(nil), nil, "nil")
		T.eq(U.Level(5), nil, "Zahl")
		T.eq(U.Known("feature:press"), true, "Known")
		T.eq(U.Known("feature:pres"), false, "Known Tippfehler")
		T.check(#GC.UnlockLevels > 5 and GC.UnlockLevels[1] == 1 and GC.UnlockLevels[#GC.UnlockLevels] == 95, "UnlockLevels")
		T.eq(GC.UnlockByTab.press.key, "feature:press", "UnlockByTab press")
		T.eq(GC.UnlockByTab.auction.key, "feature:auction", "erster Feature-Eintrag je Tab")
		T.eq(GC.UnlockByTab.lobby, nil, "mode-Einträge sind keine Feature-Tabs")
		T.eq(#GC.UnlocksByKind.car, 14, "14 Autos (9 Händler + 5 Sondermodelle)")
		T.eq(#GC.UnlocksByKind.story, 5, "5 Kapitel")
		T.eq(#GC.UnlocksByKind.building, 3, "3 Gebäude")
		T.eq(#GC.UnlocksByKind.mode, 2, "2 Modi")
	end },

	{ "Has, Gate, NextFor, ListFor, NewlyReached, TabAllowed – nil-sicher und NaN-sicher", function(T, H)
		local g, GC, U = modules(H)
		local d = profile(g, 1)
		T.eq(U.Has(d, "mode:tycoon"), true, "Tycoon immer")
		T.eq(U.Has(d, "feature:press"), false, "Presse erst ab 2")
		T.eq(U.Has(d, "nix"), false, "unbekannt = nicht frei")
		T.eq(U.Has(d, 42), false, "Zahl als Schlüssel")
		T.eq(U.Has(nil, "mode:tycoon"), true, "ohne d gilt Level 1")
		T.eq(U.Has(nil, "feature:press"), false, "ohne d gilt Level 1 (2)")
		d.level = 0 / 0
		T.eq(U.LevelOf(d), 1, "NaN-Level = 1")
		T.eq(U.Has(d, "feature:press"), false, "NaN-Level sperrt")
		d.level = math.huge
		T.eq(U.LevelOf(d), 1, "inf-Level = 1")
		d.level = 2.9
		T.eq(U.LevelOf(d), 2, "ganzzahlig")
		T.eq(U.Has(d, "feature:press"), true, "Level 2")
		T.eq(U.Has(d, "feature:scrapyard"), false, "Level 3 fehlt")
		local ok, msg = U.Gate(d, "feature:scrapyard")
		T.eq(ok, false, "Gate gesperrt")
		T.check(type(msg) == "string" and msg:find("Level 3", 1, true) ~= nil, "Meldung nennt das Level: " .. tostring(msg))
		ok, msg = U.Gate(d, "feature:press")
		T.eq(ok, true, "Gate offen")
		T.eq(msg, nil, "keine Meldung")
		ok, msg = U.Gate(d, "tippfehler")
		T.eq(ok, false, "Gate unbekannt")
		T.check(type(msg) == "string" and msg:find("Unbekannt", 1, true) ~= nil, "Tippfehler fällt auf")
		d.level = 1
		local nxt = U.NextFor(d)
		T.check(nxt ~= nil and nxt.level == 2 and nxt.key == "feature:press", "nächste Freischaltung bei Level 1")
		d.level = 2
		T.eq(U.NextFor(d).level, 3, "nächste bei Level 2")
		d.level = 89
		T.eq(U.NextFor(d).key, "car:elys", "Elys als Nächstes")
		d.level = 95
		T.eq(U.NextFor(d), nil, "alles erreicht")
		T.eq(U.NextFor(nil).level, 2, "ohne d")
		d.level = 7
		local list = U.ListFor(d)
		T.eq(#list, #GC.Unlocks, "Liste vollständig")
		local reached, open = 0, 0
		for i, row in ipairs(list) do
			T.eq(row.key, GC.Unlocks[i].key, "Reihenfolge " .. i)
			T.eq(row.reached, row.level <= 7, "erreicht " .. row.key)
			if row.reached then
				reached += 1
			else
				open += 1
			end
		end
		T.check(reached > 0 and open > 0, "erreicht und offen gemischt")
		local keys = {}
		for _, u in ipairs(U.NewlyReached(2, 3)) do
			keys[u.key] = true
		end
		T.check(keys["feature:scrapyard"] and keys["feature:dealer"] and keys["car:komet"] and not keys["feature:press"], "NewlyReached 2 -> 3")
		T.eq(#U.NewlyReached(3, 3), 0, "kein Aufstieg")
		T.eq(#U.NewlyReached(5, 2), 0, "rückwärts")
		T.eq(#U.NewlyReached(89, 90), 1, "Elys")
		T.eq(U.NewlyReached(89, 90)[1].key, "car:elys", "Elys Schlüssel")
		T.eq(type(U.NewlyReached(0 / 0, 0 / 0)), "table", "NaN ohne Fehler")
		T.eq(#U.NewlyReached(nil, 1), 3, "0 -> 1: die drei Level-1-Einträge")
		T.eq(U.TabAllowed(d, "overview"), true, "Tab ohne Eintrag offen")
		T.eq(U.TabAllowed(d, "map"), true, "map offen")
		T.eq(U.TabAllowed(d, "press"), true, "press ab 2")
		T.eq(U.TabAllowed(d, "arcade"), false, "arcade ab 10")
		T.eq(U.TabAllowed(nil, "press"), false, "ohne d Level 1")
		T.eq(U.TabAllowed(d, nil), true, "nil-Tab")
		T.eq(U.ForTab("dealer").key, "feature:dealer", "ForTab")
		T.eq(U.ForTab("lobby"), nil, "mode-Einträge zählen nicht")
		T.eq(#U.OfKind("building"), 3, "OfKind")
		T.eq(#U.OfKind("nix"), 0, "OfKind unbekannt")
		T.eq(#U.OfKind(nil), 0, "OfKind nil")
	end },

	{ "Prestige-Schwellen 100, 250, 500, 900, 1.650, 3.000 …, Deckel 20; RankFor an den Kanten; NextThreshold; Belohnungstabelle", function(T, H)
		local _, GC, _, PR = modules(H)
		local expect = { 100, 250, 500, 900, 1650, 3000, 5400, 9750, 17550, 31600 }
		for n, lvl in ipairs(expect) do
			T.eq(PR.Threshold(n), lvl, "Schwelle " .. n)
		end
		T.eq(#PR.Thresholds, 20, "20 Ränge")
		T.eq(PR.MaxRank, 20, "MaxRank")
		for n = 2, 20 do
			T.check(PR.Threshold(n) > PR.Threshold(n - 1), "steigend " .. n)
			T.eq(PR.Threshold(n) % 50, 0, "Vielfaches von 50 " .. n)
			if n > 3 then
				T.eq(PR.Threshold(n), math.ceil(PR.Threshold(n - 1) * 1.8 / 50 - 1e-9) * 50, "Formel " .. n)
			end
		end
		T.eq(PR.Threshold(0), nil, "Rang 0")
		T.eq(PR.Threshold(21), nil, "über dem Deckel")
		T.eq(PR.Threshold(1.5), nil, "Bruch")
		T.eq(PR.Threshold("1"), nil, "Zeichenkette")
		T.eq(PR.Threshold(0 / 0), nil, "NaN")
		T.eq(PR.RankFor(1), 0, "Level 1")
		T.eq(PR.RankFor(99), 0, "Level 99")
		T.eq(PR.RankFor(100), 1, "Level 100")
		T.eq(PR.RankFor(249), 1, "Level 249")
		T.eq(PR.RankFor(250), 2, "Level 250")
		T.eq(PR.RankFor(500), 3, "Level 500")
		T.eq(PR.RankFor(899), 3, "Level 899")
		T.eq(PR.RankFor(900), 4, "Level 900")
		T.eq(PR.RankFor(PR.Threshold(20)), 20, "höchster Rang")
		T.eq(PR.RankFor(PR.Threshold(20) - 1), 19, "knapp darunter")
		T.eq(PR.RankFor(1e12), 20, "Deckel")
		T.eq(PR.RankFor(0 / 0), 0, "NaN")
		T.eq(PR.RankFor(-5), 0, "negativ")
		T.eq(PR.RankFor(math.huge), 0, "inf")
		T.eq(PR.RankFor(nil), 0, "nil")
		T.eq(PR.RankFor("100"), 0, "Zeichenkette")
		T.eq(PR.NextThreshold(1), 100, "nächste bei 1")
		T.eq(PR.NextThreshold(100), 250, "nächste bei 100")
		T.eq(PR.NextThreshold(249), 250, "nächste bei 249")
		T.eq(PR.NextThreshold(PR.Threshold(20)), nil, "keine über 20")
		T.eq(PR.NextThreshold(0 / 0), 100, "NaN")
		local pg = PR.Progress(175)
		T.eq(pg.rank, 1, "Progress Rang")
		T.eq(pg.from, 100, "Progress von")
		T.eq(pg.next, 250, "Progress nächste")
		T.near(pg.pct, 0.5, 1e-9, "Progress Anteil")
		pg = PR.Progress(50)
		T.eq(pg.rank, 0, "Progress ohne Rang")
		T.near(pg.pct, 0.5, 1e-9, "Progress Anteil ab 0")
		pg = PR.Progress(PR.Threshold(20) + 5)
		T.eq(pg.next, nil, "Progress oben")
		T.eq(pg.pct, 1, "Progress voll")
		T.eq(PR.Progress(0 / 0).rank, 0, "Progress NaN")
		T.eq(#GC.Prestige.Rewards, 20, "20 Belohnungen")
		local titles, cosmetics = {}, {}
		for n, r in ipairs(GC.Prestige.Rewards) do
			T.eq(r.rank, n, "rank " .. n)
			T.check(not titles[r.title] and not cosmetics[r.cosmetic], "Titel und Kosmetik eindeutig " .. n)
			titles[r.title] = true
			cosmetics[r.cosmetic] = true
			T.near(r.incomePct, math.min(2 * n, 30), 1e-9, "incomePct " .. n)
			T.near(r.discountPct, math.min(n, 10), 1e-9, "discountPct " .. n)
			T.eq(r.tycoonRebirthPct, n >= 3 and 5 or 0, "tycoonRebirthPct " .. n)
			T.check(PR.Reward(n) == r, "Reward " .. n)
		end
		T.eq(GC.Prestige.Rewards[1].title, "Meisterschrauber I", "Titel Rang 1")
		T.eq(GC.Prestige.Rewards[5].title, "Meisterschrauber V", "Titel Rang 5")
		T.eq(PR.Reward(0), nil, "Reward 0")
		T.eq(PR.Reward(1.5), nil, "Reward Bruch")
	end },

	{ "Prestige-Boni (Deckel +30 % / 10 %) und Abholen: Reihenfolge, einmalig, Titel, JSON-sicheres claimed", function(T, H)
		local g, _, _, PR = modules(H)
		local d = profile(g, 1)
		T.eq(PR.Rank(d), 0, "Rang 0")
		T.near(PR.IncomeBonus(d), 1, 1e-9, "kein Bonus")
		T.eq(PR.Discount(d), 0, "kein Rabatt")
		T.eq(PR.RebirthBonus(d), 0, "kein Rebirth-Bonus")
		T.eq(PR.Title(d), "", "kein Titel")
		T.eq(#PR.Claimable(d), 0, "nichts abholbar")
		T.eq(PR.NextClaim(d), nil, "NextClaim leer")
		local ok, msg = PR.Claim(d, 1)
		T.eq(ok, false, "Rang 1 nicht erreicht")
		T.check(type(msg) == "string" and msg:find("Level 100", 1, true) ~= nil, "Meldung nennt Level 100: " .. tostring(msg))
		d.level = 100
		T.near(PR.IncomeBonus(d), 1.02, 1e-9, "+2 %")
		T.near(PR.Discount(d), 0.01, 1e-9, "1 %")
		T.eq(PR.RebirthBonus(d), 0, "Rebirth-Bonus erst ab 3")
		d.level = 500
		T.near(PR.IncomeBonus(d), 1.06, 1e-9, "+6 %")
		T.near(PR.Discount(d), 0.03, 1e-9, "3 %")
		T.near(PR.RebirthBonus(d), 0.05, 1e-9, "Rebirth-Bonus ab Rang 3")
		d.level = PR.Threshold(20)
		T.near(PR.IncomeBonus(d), 1.30, 1e-9, "Deckel +30 %")
		T.near(PR.Discount(d), 0.10, 1e-9, "Deckel 10 %")
		T.near(PR.IncomeBonus(nil), 1, 1e-9, "nil-sicher")
		T.eq(PR.Discount({}), 0, "leeres Profil")
		d.level = 500
		local cl = PR.Claimable(d)
		T.eq(#cl, 3, "drei Ränge abholbar")
		T.eq(cl[1], 1, "aufsteigend")
		T.eq(cl[3], 3, "aufsteigend (3)")
		T.eq(PR.NextClaim(d), 1, "zuerst Rang 1")
		ok, msg = PR.Claim(d, 2)
		T.eq(ok, false, "Reihenfolge")
		T.check(type(msg) == "string" and msg:find("Rang 1", 1, true) ~= nil, "Meldung: zuerst Rang 1")
		local reward
		ok, reward = PR.Claim(d, 1)
		T.eq(ok, true, "Rang 1 abgeholt")
		T.eq(reward.title, "Meisterschrauber I", "Belohnung Rang 1")
		T.eq(reward.cosmetic, "wrap_prestige_1", "Kosmetik Rang 1")
		T.eq(d.games.prestige.claimed[1], true, "claimed[1]")
		T.eq(d.games.prestige.titleRank, 1, "Titel folgt")
		T.eq(PR.Title(d), "Meisterschrauber I", "Titel")
		ok, msg = PR.Claim(d, 1)
		T.eq(ok, false, "einmalig")
		T.eq(msg, nil, "Doppelklick still")
		T.eq(PR.Claim(d, 2), true, "Rang 2")
		T.eq(PR.Claim(d, 3), true, "Rang 3")
		T.eq(#PR.Claimable(d), 0, "alles abgeholt")
		T.eq(PR.NextClaim(d), nil, "nichts offen")
		ok, msg = PR.Claim(d, 4)
		T.eq(ok, false, "Rang 4 nicht erreicht")
		T.check(type(msg) == "string" and msg:find("Level 900", 1, true) ~= nil, "Meldung nennt Level 900")
		T.eq(PR.Claim(d, "1"), false, "Zeichenkette")
		T.eq(PR.Claim(d, 1.5), false, "Bruch")
		T.eq(PR.Claim(d, 0), false, "Rang 0")
		T.eq(PR.Claim(d, 21), false, "über dem Deckel")
		T.eq(PR.Claim(d, 0 / 0), false, "NaN")
		T.eq(PR.Claim(nil, 1), false, "ohne Profil")
		T.eq(PR.Claim({ games = {} }, 1), false, "ohne Prestige-Bereich")
		T.eq(d.games.prestige.titleRank, 3, "höchster abgeholter Titel")
		T.eq(PR.SetTitle(d, 2), true, "Titel wählen")
		T.eq(PR.Title(d), "Meisterschrauber II", "gewählter Titel")
		T.eq(PR.SetTitle(d, 0), true, "kein Titel")
		T.eq(PR.Title(d), "", "leer")
		T.eq(PR.SetTitle(d, 5), false, "nicht abgeholt")
		T.eq(PR.SetTitle(d, -1), false, "negativ")
		T.eq(PR.SetTitle(d, 1.5), false, "Bruch")
		T.eq(#d.games.prestige.claimed, 3, "dichtes Feld")
		local MiniRules = g:MiniShared("MiniRules")
		T.check(MiniRules.IsClean(d.games.prestige), "speicherbar")
		local rt = H.Mock.JSONDecode(H.Mock.JSONEncode(d.games.prestige))
		T.eq(rt.claimed[3], true, "übersteht JSON")
		local loaded = PR.Load(rt, d, NOW)
		T.eq(loaded.claimed[3], true, "nach Laden")
		T.eq(loaded.titleRank, 0, "titleRank 0 bleibt")
	end },

	{ "MetaRules: Default/Load idempotent (Standard, Müll, NaN), Whitelist; Prestige-Load hält nur den dichten Anfang", function(T, H)
		local g, GC, _, PR, MR = modules(H)
		local MiniRules = g:MiniShared("MiniRules")
		local d = profile(g, 500)
		local def = MR.Default()
		T.eq(def.tutorialStep, 1, "Schritt 1")
		T.eq(def.tutorialDone, false, "Tutorial offen")
		T.eq(def.tutorialSkipped, false, "nicht übersprungen")
		T.eq(def.beginner, true, "Beginner an")
		T.eq(def.passive, false, "Passiv aus")
		T.eq(def.single, false, "Single aus")
		T.eq(def.lastMode, "lobby", "erster Beitritt Lobby")
		T.eq(def.firstSeen, 0, "firstSeen 0")
		T.eq(def.playSeconds, 0, "playSeconds 0")
		T.eq(next(def.hintsSeen), nil, "keine Hinweise")
		local once = MR.Load(H.Copy(def), d, NOW)
		local twice = MR.Load(H.Copy(once), d, NOW)
		local ok, where = H.DeepEqual(once, twice)
		T.check(ok, "idempotent auf Default: " .. tostring(where))
		T.eq(once.firstSeen, NOW, "firstSeen aus now")
		local fromNil = MR.Load(nil, d, NOW)
		ok, where = H.DeepEqual(fromNil, once)
		T.check(ok, "Load(nil) = Load(Default): " .. tostring(where))
		T.eq(MR.Load(nil, d, nil).firstSeen, 0, "ohne now bleibt 0")
		T.eq(MR.Load(nil, d, 0 / 0).firstSeen, 0, "NaN-now bleibt 0")
		local garbage = {
			tutorialStep = 0 / 0, tutorialDone = "ja", tutorialSkipped = true, beginner = false, passive = 1, single = "x",
			lastMode = "mars", firstSeen = -5, playSeconds = math.huge,
			hintsSeen = { h_press = true, fremd = true, h_quiz = "x", [7] = true }, unbekannt = { x = 1 },
		}
		local m = MR.Load(H.Copy(garbage), d, NOW)
		T.eq(m.tutorialStep, 1, "NaN-Schritt")
		T.eq(m.tutorialDone, true, "übersprungen = beendet")
		T.eq(m.tutorialSkipped, true, "übersprungen")
		T.eq(m.beginner, false, "ausdrückliches false")
		T.eq(m.passive, false, "1 ist kein true")
		T.eq(m.single, false, "Zeichenkette ist kein true")
		T.eq(m.lastMode, "lobby", "unbekannter Modus")
		T.eq(m.firstSeen, NOW, "negativ -> now")
		T.eq(m.playSeconds, 0, "inf -> 0")
		T.eq(m.hintsSeen.h_press, true, "bekannter Hinweis bleibt")
		T.eq(m.hintsSeen.fremd, nil, "fremder Hinweis weg")
		T.eq(m.hintsSeen.h_quiz, nil, "kein true")
		T.eq(m.hintsSeen[7], nil, "Zahl-Schlüssel weg")
		T.eq(m.unbekannt, nil, "unbekanntes Feld weg")
		local m2 = MR.Load(H.Copy(m), d, NOW)
		ok, where = H.DeepEqual(m, m2)
		T.check(ok, "idempotent auf Müll: " .. tostring(where))
		T.check(MiniRules.IsClean(m), "sauber")
		local good = {
			tutorialStep = 7, tutorialDone = false, beginner = true, passive = true, single = true, lastMode = "tycoon",
			firstSeen = NOW - 1000, playSeconds = 4242, hintsSeen = { h_map = true },
		}
		m = MR.Load(good, d, NOW)
		T.eq(m.tutorialStep, 7, "Schritt bleibt")
		T.eq(m.tutorialDone, false, "offen bleibt")
		T.eq(m.passive, true, "passive bleibt")
		T.eq(m.single, true, "single bleibt")
		T.eq(m.lastMode, "tycoon", "Modus bleibt")
		T.eq(m.firstSeen, NOW - 1000, "firstSeen bleibt")
		T.eq(m.playSeconds, 4242, "playSeconds bleibt")
		T.eq(m.hintsSeen.h_map, true, "Hinweis bleibt")
		T.eq(MR.Load({ tutorialStep = 99 }, d, NOW).tutorialStep, #GC.Tutorial.Steps, "Schritt gedeckelt")
		T.eq(MR.Load({ tutorialStep = 0 }, d, NOW).tutorialStep, 1, "Schritt mindestens 1")
		T.eq(MR.Load({ tutorialStep = 3.7 }, d, NOW).tutorialStep, 3, "Schritt ganzzahlig")
		T.eq(MR.Load({ firstSeen = NOW + 5000 }, d, NOW).firstSeen, NOW, "Zukunft -> now")
		T.eq(MR.Load("x", d, NOW).lastMode, "lobby", "kein Table")
		-- Veteranen ohne meta: Tutorial gilt als beendet, nicht als übersprungen; mit meta zählt nur meta
		local vet = profile(g, 17)
		vet.completed = 23
		local vm = MR.Load(nil, vet, NOW)
		T.eq(vm.tutorialDone, true, "Veteran: Tutorial beendet")
		T.eq(vm.tutorialSkipped, false, "Veteran: nicht übersprungen")
		T.eq(vm.beginner, true, "Veteran: Hinweise bleiben an")
		ok, where = H.DeepEqual(MR.Load(H.Copy(vm), vet, NOW), vm)
		T.check(ok, "Veteran idempotent: " .. tostring(where))
		T.eq(MR.Load({ tutorialDone = false }, vet, NOW).tutorialDone, false, "mit meta zählt meta")
		T.eq(MR.Load(nil, profile(g, 1), NOW).tutorialDone, false, "neues Profil: Tutorial offen")
		local gv = {}
		MR.ApplyLoad(gv, { stats = { jobsDone = 23 } }, vet, NOW)
		T.eq(gv.meta.tutorialDone, true, "3.x-Profil ohne meta: Veteran")
		-- Prestige: nur der dichte Anfang, gedeckelt durch den Rang aus d.level (500 = Rang 3)
		local pr = PR.Load({ claimed = { [1] = true, [3] = true }, titleRank = 7 }, d, NOW)
		T.eq(pr.claimed[1], true, "Rang 1 bleibt")
		T.eq(pr.claimed[2], nil, "Lücke")
		T.eq(pr.claimed[3], nil, "hinter der Lücke weg")
		T.eq(pr.titleRank, 1, "Titel höchstens abgeholter Rang")
		pr = PR.Load({ claimed = { ["1"] = true, ["2"] = true }, titleRank = 2 }, d, NOW)
		T.eq(pr.claimed[2], true, "Zeichenketten-Schlüssel aus JSON")
		T.eq(pr.titleRank, 2, "Titel aus JSON")
		pr = PR.Load({ claimed = { true, true, true, true }, titleRank = 4 }, d, NOW)
		T.eq(#pr.claimed, 3, "höchstens bis zum Rang aus dem Level")
		T.eq(pr.titleRank, 3, "Titel gedeckelt")
		pr = PR.Load({ claimed = { true, true }, titleRank = 2 }, profile(g, 1), NOW)
		T.eq(#pr.claimed, 0, "Level 1 hat keinen Rang")
		T.eq(pr.titleRank, 0, "kein Titel")
		pr = PR.Load({ claimed = { true, true } }, {}, NOW)
		T.eq(#pr.claimed, 2, "ohne Level keine Deckelung")
		pr = PR.Load({ claimed = "x", titleRank = 0 / 0 }, d, NOW)
		T.eq(#pr.claimed, 0, "Müll claimed")
		T.eq(pr.titleRank, 0, "NaN titleRank")
		T.eq(#PR.Load(5, d, NOW).claimed, 0, "kein Table")
		T.eq(PR.Load({ claimed = { true }, titleRank = -3 }, d, NOW).titleRank, 0, "negativer Titel")
		local p1 = PR.Load({ claimed = { true, false, true } }, d, NOW)
		T.eq(#p1.claimed, 1, "false unterbricht")
		local p2 = PR.Load(H.Copy(p1), d, NOW)
		ok, where = H.DeepEqual(p1, p2)
		T.check(ok, "Prestige idempotent: " .. tostring(where))
		local pd = PR.Load(PR.Default(), d, NOW)
		ok, where = H.DeepEqual(pd, PR.Default())
		T.check(ok, "Prestige Load(Default) = Default: " .. tostring(where))
		local gm = {}
		MR.ApplyDefault(gm)
		T.eq(type(gm.meta), "table", "ApplyDefault meta")
		T.eq(type(gm.prestige), "table", "ApplyDefault prestige")
		T.check(MiniRules.IsClean(gm), "ApplyDefault sauber")
		local g2 = {}
		MR.ApplyLoad(g2, { meta = garbage, prestige = { claimed = { true } } }, d, NOW)
		T.eq(g2.meta.lastMode, "lobby", "ApplyLoad meta")
		T.eq(g2.prestige.claimed[1], true, "ApplyLoad prestige")
		local g3 = {}
		MR.ApplyLoad(g3, nil, d, NOW)
		T.eq(g3.meta.tutorialStep, 1, "ApplyLoad ohne raw")
		T.eq(#g3.prestige.claimed, 0, "ApplyLoad ohne raw (prestige)")
		T.check(MR.DefaultPrestige == PR.Default and MR.LoadPrestige == PR.Load, "Prestige-Default/Load auch über MetaRules")
	end },

	{ "SetSettings, SetMode, Hinweise (nur Beginner, je einmal), Spielzeit, erster Beitritt", function(T, H)
		local g, _, _, _, MR = modules(H)
		local d = profile(g, 3)
		local s = MR.Settings(d)
		T.eq(s.beginner, true, "Beginner an")
		T.eq(s.passive, false, "Passiv aus")
		T.eq(s.single, false, "Single aus")
		T.eq(MR.SetSettings(d, { single = true, passive = "ja", beginner = 0, fremd = true }), true, "geändert")
		s = MR.Settings(d)
		T.eq(s.single, true, "single übernommen")
		T.eq(s.passive, false, "kein Boolean: ignoriert")
		T.eq(s.beginner, true, "Zahl: ignoriert")
		T.eq(d.games.meta.fremd, nil, "fremdes Feld nicht übernommen")
		T.eq(MR.SetSettings(d, { single = true }), false, "keine Änderung")
		T.eq(MR.SetSettings(d, nil), false, "nil")
		T.eq(MR.SetSettings(d, "x"), false, "Zeichenkette")
		T.eq(MR.SetSettings(nil, { single = false }), false, "ohne Profil")
		T.eq(MR.SetSettings(d, { passive = true, beginner = false }), true, "zwei Felder")
		T.eq(MR.IsPassive(d), true, "IsPassive")
		T.eq(MR.IsBeginner(d), false, "IsBeginner")
		T.eq(MR.Mode(d), "lobby", "Standardmodus")
		T.eq(MR.SetMode(d, "tycoon"), true, "Modus setzen")
		T.eq(MR.Mode(d), "tycoon", "Modus gesetzt")
		T.eq(MR.SetMode(d, "mars"), false, "unbekannter Modus")
		T.eq(MR.Mode(d), "tycoon", "unverändert")
		T.eq(MR.SetMode(d, 5), false, "Zahl")
		T.eq(MR.SetMode(nil, "lobby"), false, "ohne Profil")
		T.eq(MR.Mode(nil), "lobby", "Mode nil-sicher")
		T.eq(MR.Settings(nil).beginner, true, "Settings nil-sicher")
		T.eq(MR.Meta({ games = 5 }), nil, "Meta ohne games-Table")
		T.eq(MR.HintFor(d, "unlock:feature:press"), nil, "ohne Beginner keine Hinweise")
		MR.SetSettings(d, { beginner = true })
		local h = MR.HintFor(d, "unlock:feature:press")
		T.check(h ~= nil and h.id == "h_press", "Hinweis zur Presse")
		T.eq(MR.MarkHint(d, "h_press"), true, "gesehen")
		T.eq(MR.MarkHint(d, "h_press"), false, "je einmal")
		T.eq(MR.HintFor(d, "unlock:feature:press"), nil, "nicht erneut")
		T.eq(MR.MarkHint(d, "fremd"), false, "unbekannt")
		T.eq(d.games.meta.hintsSeen.fremd, nil, "unbekannt nicht gespeichert")
		T.eq(MR.MarkHint(d, 7), false, "Zahl")
		T.eq(MR.HintFor(d, "nix"), nil, "unbekannter Auslöser")
		T.eq(MR.HintFor(d, nil), nil, "nil-Auslöser")
		T.eq(MR.HintFor(nil, "station:map"), nil, "ohne Profil")
		T.check(MR.HintFor(d, "station:map") ~= nil, "Stadtplan-Hinweis")
		T.check(MR.HintFor(d, "first:jobsDone") ~= nil, "erster Auftrag")
		MR.AddPlaySeconds(d, 30.7)
		MR.AddPlaySeconds(d, 0 / 0)
		MR.AddPlaySeconds(d, -5)
		MR.AddPlaySeconds(nil, 5)
		T.eq(d.games.meta.playSeconds, 30, "Spielzeit ganzzahlig, nur positiv")
		MR.Touch(d, NOW)
		T.eq(d.games.meta.firstSeen, NOW, "erster Beitritt")
		MR.Touch(d, NOW + 100)
		T.eq(d.games.meta.firstSeen, NOW, "nur einmal")
		MR.Touch(nil, NOW)
		MR.Touch(d, 0 / 0)
		T.eq(d.games.meta.firstSeen, NOW, "NaN ignoriert")
	end },

	{ "GameConfig: Places 0, Zonen, Party, Tutorial (11 Schritte, bekannte Ziele/Ereignisse), Hinweise (≥ 12, gültige Auslöser), Platzhalter leer", function(T, H)
		local g, GC, U = modules(H)
		local MiniRules = g:MiniShared("MiniRules")
		for _, k in ipairs({ "lobby", "openworld", "tycoon" }) do
			T.eq(GC.Places[k], 0, "Place-ID Platzhalter " .. k)
			T.check(GC.Zones[k] ~= nil and type(GC.Zones[k].model) == "string" and GC.Zones[k].arrival == "hub", "Zone " .. k)
			T.eq(GC.ModeSet[k], true, "Modus " .. k)
		end
		T.eq(GC.Zones.lobby.model, "Lobby", "Lobby-Modell")
		T.eq(GC.Zones.openworld.model, "City", "Stadt-Modell")
		T.eq(GC.Zones.tycoon.model, "Tycoon", "Tycoon-Modell")
		T.eq(#GC.Zones.lobby.stations, 5, "fünf Lobby-Stationen")
		T.eq(GC.DefaultMode, "lobby", "Standardmodus")
		T.eq(GC.ModeSet.all, nil, "all ist kein Modus")
		T.eq(GC.PlaceKindSet.all, true, "all ist ein PlaceKind")
		T.eq(GC.Party.MaxMembers, 4, "Party max 4")
		T.eq(GC.Party.CodeLength, 4, "Code 4 Zeichen")
		T.check(GC.Party.InviteSeconds > 0 and GC.Party.TravelOfferSeconds > 0, "Angebotsdauern")
		T.check(GC.Party.CodeAlphabet:find("[IO01]") == nil, "Alphabet ohne I, O, 0, 1")
		T.eq(#GC.Tutorial.Steps, 11, "11 Schritte (Meilenstein 7: Schritt 11 Kiesplatz)")
		T.eq(GC.Tutorial.Count, 11, "Count")
		T.eq(GC.Tutorial.Reward.credits, 500, "500 Credits")
		T.eq(GC.Tutorial.Reward.xp, 60, "60 XP")
		T.eq(GC.XP.Tutorial, GC.Tutorial.Reward.xp, "XP-Regler passt")
		local plotStations = { home = true, workshop = true, parts = true, upgrades = true, tools = true, shop = true }
		local cityStations = { map = true, dealer = true, goals = true, kiesplatz = true }
		local ids, kinds = {}, {}
		for _, k in ipairs(GC.Tutorial.EventKinds) do
			kinds[k] = true
		end
		for i, s in ipairs(GC.Tutorial.Steps) do
			T.check(not ids[s.id], "Schritt-Id eindeutig " .. s.id)
			ids[s.id] = true
			T.eq(GC.TutorialStepIndex[s.id], i, "Index " .. s.id)
			T.check(GC.TutorialStepById[s.id] == s, "ById " .. s.id)
			T.check(type(s.text) == "string" and #s.text > 10, "Text " .. s.id)
			T.check(kinds[s.event:match("^([a-z]+)")], "Ereignisart bekannt: " .. s.event)
			if s.target then
				T.check(s.zone == "plot" or s.zone == "city", "Zone bei Ziel " .. s.id)
				T.check((s.zone == "plot" and plotStations[s.target]) or (s.zone == "city" and cityStations[s.target]), "Ziel bekannt " .. s.id)
			end
		end
		T.eq(GC.Tutorial.Steps[1].event, "next", "Bewegen ist ein Lese-Schritt")
		T.eq(GC.Tutorial.Steps[7].event, "settled", "Abrechnen über OnSettled")
		T.check(#GC.Hints >= 12, "mindestens 12 Hinweise")
		local statSet = {}
		for _, k in ipairs(MiniRules.STAT_KEYS) do
			statSet[k] = true
		end
		for _, k in ipairs({ "missionsDone", "tycoonRuns", "prestigeClaims" }) do
			statSet[k] = true
		end
		local hid = {}
		for _, h in ipairs(GC.Hints) do
			T.check(not hid[h.id], "Hinweis-Id eindeutig " .. h.id)
			hid[h.id] = true
			T.check(GC.HintById[h.id] == h, "HintById " .. h.id)
			T.check(type(h.text) == "string" and #h.text > 10, "Text " .. h.id)
			local kind, arg = h.when:match("^(%a+):(.+)$")
			if kind == "unlock" then
				T.check(U.Known(arg), "unlock-Auslöser bekannt " .. h.when)
			elseif kind == "first" then
				T.check(statSet[arg], "Statistik bekannt " .. h.when)
			elseif kind == "job" then
				T.check(arg == "accepted" or arg == "approval", "Auftrags-Auslöser bekannt " .. h.when)
			elseif kind == "car" then
				T.eq(arg, "intro", "Auto-Auslöser bekannt (Willkommens-Flitzer) " .. h.when)
			else
				T.eq(kind, "station", "Auslöser " .. h.when)
			end
			T.check(GC.HintsByWhen[h.when] ~= nil, "HintsByWhen " .. h.when)
		end
		T.check(type(GC.Shop) == "table" and #GC.Shop.Products >= 8 and #GC.Shop.Passes == 2 and #GC.Shop.Cosmetics >= 15 and #GC.Shop.Slots == 4, "GameConfig.Shop gefüllt (Meilenstein 8)")
		T.check(type(GC.OW) == "table" and #GC.OW.Types == 4 and GC.OW.MaxStage == 4 and type(GC.OW.Perks) == "table", "GameConfig.OW gefüllt (Meilenstein 6)")
		T.check(type(GC.Story) == "table" and #GC.Story.Chapters == 5 and type(GC.Story.Side) == "table" and type(GC.Story.Sale) == "table", "GameConfig.Story gefüllt (Meilenstein 7)")
		T.check(type(GC.Tycoon) == "table" and #GC.Tycoon.Types == 4 and GC.Tycoon.MaxStage == 5, "GameConfig.Tycoon gefüllt (Meilenstein 4)")
		T.check(MiniRules.IsClean(GC.Unlocks) and MiniRules.IsClean(GC.Prestige.Rewards) and MiniRules.IsClean(GC.Tutorial.Steps) and MiniRules.IsClean(GC.Hints), "Konfiguration ohne NaN/Instanzen")
		for _, list in ipairs({ GC.Hints, GC.Tutorial.Steps }) do
			for _, e in ipairs(list) do
				T.check(e.text:find("rbxassetid", 1, true) == nil, "keine Asset-IDs in Texten")
			end
		end
	end },
}
