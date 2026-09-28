-- Nebenspiele (Schrottplatz, Quiz, Parkplatz) im echten Server und ihre Querboni auf die 2.4.0-Werkstatt
local function find(list, v)
	for i, x in ipairs(list) do
		if x == v then
			return i
		end
	end
end

return {
	{ "Schrottplatz: Kauf, Zerlegen, Altteile, seltene Funde ins 2.4.0-Lager, Schrott gutgeschrieben", function(T, H)
		local g = H.Garage()
		local MC = g:MiniShared("MiniConfig")
		local C = g:Config()
		local player = g:Join(401, { name = "Jan" })
		g:Advance(1)
		local d = g:D(player)
		d.games.press.upgrades = {}
		local money, parts = d.money, d.games.parts
		g:Act(player, "mini_scrapyard_dismantle", { rid = 1 })
		T.eq(d.games.parts, parts, "ohne Fahrzeug kein Zerlegen")
		g:Act(player, "mini_scrapyard_buy", { rid = 2 })
		T.eq(d.money, money - MC.ScrapyardCarCost, "Kaufpreis abgezogen")
		g:Advance(0.2)
		g:Act(player, "mini_scrapyard_buy", { rid = 3 })
		T.eq(d.money, money - MC.ScrapyardCarCost, "kein zweites Fahrzeug gleichzeitig")
		local scrap, lifetime = d.games.press.scrap, d.games.press.lifetime
		local inv = H.Copy(d.inventory)
		g:Act(player, "mini_scrapyard_dismantle", { rid = 4 })
		local results = g:Notices(player, "scrapyard")
		T.eq(#results, 1, "Ergebnis gemeldet")
		local r = results[1]
		T.check(r.parts >= 2, "mindestens 2 Altteile")
		T.eq(d.games.parts, parts + r.parts, "Altteile im Lager")
		T.check(d.games.press.scrap >= scrap + r.scrap, "Schrott gutgeschrieben")
		T.check(d.games.press.lifetime - lifetime < r.scrap, "Zerlege-Schrott zählt nicht für die Bestenliste")
		if r.rare and r.rareSku then
			T.eq(d.inventory[r.rareSku], (inv[r.rareSku] or 0) + 1, "seltener Fund im 2.4.0-Lager")
			T.check(C.PartById[r.rareSku] ~= nil, "echtes Ersatzteil")
		end
		g:Advance(0.2)
		g:Act(player, "mini_scrapyard_dismantle", { rid = 5 })
		T.eq(#g:Notices(player, "scrapyard"), 1, "kein doppeltes Zerlegen")
		T.eq(d.games.stats.dismantled, 1, "Statistik")
		-- Verkauf
		d.games.parts = 7
		local c = d.money
		g:Act(player, "mini_scrapyard_sell", { rid = 6 })
		T.eq(d.games.parts, 2, "5 Altteile verkauft")
		T.check(d.money >= c + 220, "220 Cr")
		g:Advance(0.2)
		g:Act(player, "mini_scrapyard_sell", { rid = 7 })
		T.eq(d.games.parts, 2, "zu wenig Altteile: nichts")
		-- 2.4.0-Lagerteile lassen sich nicht als Altteile verkaufen
		T.eq(d.inventory.nexra_C_filter ~= nil, true, "Lagerteile unberührt")
		-- Seltene Funde: sicher (Stufe hoch) – echtes Teil passend zum Level
		d.games.scrapyardLevel = 100
		local rareSeen = 0
		for i = 1, 5 do
			d.money = 1e6
			g:Advance(0.2)
			g:Act(player, "mini_scrapyard_buy", { rid = 100 + i })
			g:Advance(0.2)
			local mark = g:Mark()
			g:Act(player, "mini_scrapyard_dismantle", { rid = 200 + i })
			local n = g:Notices(player, "scrapyard", mark)[1]
			if n and n.rare then
				rareSeen += 1
				local part = n.rareSku and C.PartById[n.rareSku]
				T.check(part ~= nil and part.brand ~= nil, "seltener Fund ist ein echtes Teil: " .. tostring(n.rareSku))
				T.check(type(n.rarePart) == "string" and n.rarePart:find("Nexra") ~= nil, "Name des Teils: " .. tostring(n.rarePart))
				T.check(g:State(player).data.inventory[n.rareSku] ~= nil, "2.4.0-Zustand zeigt das Teil")
			end
		end
		T.eq(rareSeen, 5, "bei 100 % Chance immer selten")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Quiz: Auswertung auf dem Server, Frage nie im Profil, Spam wirkungslos, Bonus ≤ 35 %", function(T, H)
		local g = H.Garage()
		local CB = g:MiniShared("CrossBonus")
		local player = g:Join(402, { name = "Kai" })
		g:Advance(1)
		local d = g:D(player)
		local ms = g:MiniState(player)
		g:Act(player, "mini_quiz_answer", { token = 1, choice = 1, rid = 1 })
		T.eq(d.games.quiz.diagPoints, 0, "ohne Frage keine Wertung")
		g:Act(player, "mini_quiz_new", { rid = 2 })
		local cur = ms.quiz.current
		T.check(cur ~= false, "Frage gestellt")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(player)
		T.eq(snap.quiz.question.token, cur.token, "Client sieht Token")
		T.eq(snap.quiz.question.correct, nil, "Client sieht keine Lösung")
		T.eq(snap.quiz.question.order, nil, "Client sieht keine Reihenfolge")
		T.eq(#snap.quiz.question.answers, 4, "vier Antworten")
		T.eq(d.games.quiz.current, nil, "offene Frage nicht im Profil")
		T.eq(g:State(player).data.games.quiz.current, nil, "offene Frage nicht im 2.4.0-Zustand (Client)")
		local correctPos = find(cur.order, 1)
		local wrongPos = correctPos % 4 + 1
		g:Act(player, "mini_quiz_answer", { token = cur.token, choice = wrongPos, rid = 3 })
		for i = 1, 10 do
			g:Advance(0.13)
			g:Act(player, "mini_quiz_answer", { token = cur.token, choice = correctPos, rid = 10 + i })
		end
		T.eq(d.games.quiz.diagPoints, 0, "nach falscher Antwort keine zweite Chance")
		local res = g:Notices(player, "quiz")
		T.eq(#res, 1, "genau eine Auswertung")
		T.eq(res[1].correct, false, "falsch gewertet")
		T.eq(res[1].correctPos, correctPos, "richtige Position gemeldet")
		-- Abklingzeit 1 s zwischen Fragen
		g:Advance(1.1)
		g:Act(player, "mini_quiz_new", { rid = 30 })
		cur = ms.quiz.current
		local token = ms.quiz.token
		g:Advance(0.2)
		g:Act(player, "mini_quiz_new", { rid = 31 })
		T.eq(ms.quiz.token, token, "Abklingzeit: keine neue Frage sofort")
		T.eq(ms.quiz.current, cur, "offene Frage bleibt")
		local money = d.money
		g:Act(player, "mini_quiz_answer", { token = cur.token, choice = find(cur.order, 1), rid = 32 })
		T.eq(d.games.quiz.diagPoints, 1, "Diagnosepunkt")
		T.check(d.money >= money + 90, "90 Cr")
		-- ungültige Wahl verbraucht die Frage nicht
		g:Advance(1.1)
		g:Act(player, "mini_quiz_new", { rid = 33 })
		cur = ms.quiz.current
		g:Act(player, "mini_quiz_answer", { token = cur.token, choice = 7, rid = 34 })
		g:Advance(0.2)
		g:Act(player, "mini_quiz_answer", { token = cur.token, choice = 1.5, rid = 35 })
		T.check(ms.quiz.current ~= false, "ungültige Wahl verbraucht die Frage nicht")
		-- Deckel
		d.games.quiz.diagPoints = 1000
		T.eq(CB.DiagReduction(d), 0.35, "Diagnose-Bonus gedeckelt auf 35 %")
		-- Antwortreihenfolge wird gemischt
		local positions = {}
		for i = 1, 30 do
			g:Advance(1.1)
			g:Act(player, "mini_quiz_new", { rid = 100 + i })
			positions[find(ms.quiz.current.order, 1)] = true
		end
		local distinct = 0
		for _ in pairs(positions) do
			distinct += 1
		end
		T.check(distinct >= 3, "richtige Antwort steht nicht immer an derselben Stelle")
	end },

	{ "Parkplatz: Lösung serverseitig geprüft, Serienbonus gedeckelt", function(T, H)
		local g = H.Garage()
		local SG, MC, CB = g:MiniShared("SideGameRules"), g:MiniShared("MiniConfig"), g:MiniShared("CrossBonus")
		local player = g:Join(403, { name = "Lea" })
		g:Advance(1)
		local d = g:D(player)
		g:Act(player, "mini_parking_tap", { cell = 3, rid = 1 })
		T.eq(d.games.parking.streak, 0, "ohne Rätsel nichts")
		g:Act(player, "mini_parking_new", { rid = 2 })
		local pz = d.games.parking.puzzle
		T.eq(#pz.cars, MC.ParkingCars, "7 Autos")
		T.check(not find(pz.cars, pz.exit), "Ausfahrt frei")
		local empty
		for c = 0, 14 do
			if not find(pz.cars, c) then
				empty = c
				break
			end
		end
		g:Act(player, "mini_parking_tap", { cell = empty, rid = 3 })
		g:Act(player, "mini_parking_tap", { cell = pz.exit, rid = 4 })
		T.eq(pz.moves, 0, "leere Felder zählen nicht")
		-- Blockierer wegfahren (verschiedene Felder direkt nacheinander), dann Ziel
		local rid = 10
		for _, cell in ipairs(SG.ParkingPath(pz.target)) do
			if find(pz.cars, cell) then
				rid += 1
				T.eq(g:Act(player, "mini_parking_tap", { cell = cell, rid = rid }), "ok", "Tipp auf Feld " .. cell)
			end
		end
		T.eq(SG.ParkingBlocked(pz), false, "Weg frei")
		local money = d.money
		g:Advance(0.2) -- Abklingzeit je Feld (das Feld wurde vor dem Rätsel schon angetippt)
		g:Act(player, "mini_parking_tap", { cell = pz.target, rid = 50 })
		T.eq(pz.solved, true, "gelöst")
		T.eq(d.games.parking.streak, 1, "Serie 1")
		T.check(d.money >= money + 135, "Belohnung 120 + 15")
		g:Advance(0.2)
		g:Act(player, "mini_parking_tap", { cell = pz.target, rid = 51 })
		T.eq(d.games.parking.streak, 1, "kein doppeltes Lösen")
		-- Blechschaden: Ziel bei blockiertem Weg
		local crashed = false
		for i = 1, 50 do
			g:Advance(0.2)
			g:Act(player, "mini_parking_new", { rid = 100 + i })
			local p2 = d.games.parking.puzzle
			if SG.ParkingBlocked(p2) then
				d.games.parking.streak = 4
				g:Act(player, "mini_parking_tap", { cell = p2.target, rid = 200 + i })
				crashed = p2.crashed and d.games.parking.streak == 0
				break
			end
		end
		T.check(crashed, "blockiertes Ziel: Blechschaden, Serie beendet")
		-- Deckel und Querboni
		d.games.parking.streak = 1000
		T.eq(CB.CustomerBonus(d), 1.7, "Serienbonus gedeckelt auf 1,7")
		T.eq(CB.OfferBonus(d), 5, "Zusatzangebote gedeckelt auf +5")
		-- Abbruch beendet die Serie
		g:Advance(0.2)
		g:Act(player, "mini_parking_new", { rid = 300 })
		local p3 = d.games.parking.puzzle
		d.games.parking.streak = 3
		local other
		for _, c in ipairs(p3.cars) do
			if c ~= p3.target then
				other = c
				break
			end
		end
		g:Act(player, "mini_parking_tap", { cell = other, rid = 301 })
		g:Advance(0.2)
		g:Act(player, "mini_parking_new", { rid = 302 })
		T.eq(d.games.parking.streak, 0, "abgebrochene Runde beendet die Serie")
	end },

	{ "Querboni auf die 2.4.0-Werkstatt: Angebote, Reparaturzeit, Vergütung", function(T, H)
		local g = H.Garage({ noServer = true })
		local R, C = g:Rules(), g:Config()
		local now = 1760000000
		local d = R.NewData(now)
		d.level = 50
		R.RefreshOffers(d, function(a, b)
			return a
		end)
		local base = #d.offers
		T.eq(base, math.min(35, d.offerSlots), "ohne Serie: offerSlots Angebote")
		d.games.parking.streak = 12
		R.RefreshOffers(d, function(a, b)
			return a
		end)
		T.eq(#d.offers, base + 2, "12er-Serie: +2 Angebote")
		-- Diagnosepunkte verkürzen die Reparatur
		local step = { seconds = 10 }
		local plain = R.StepDuration(d, step)
		d.games.quiz.diagPoints = 10
		T.near(R.StepDuration(d, step), plain * (1 - 0.15), 1e-9, "Diagnose verkürzt Reparaturzeit um 15 %")
		d.games.quiz.diagPoints = 1000
		T.near(R.StepDuration(d, step), plain * 0.65, 1e-9, "höchstens 35 %")
		-- Kundenbonus der Parkplatz-Serie auf die Vergütung
		local job = { kind = C.Jobs[1].id, carId = C.Cars[1].id, quality = 100, usedParts = {} }
		d.games.parking.streak = 0
		local reward = R.Reward(d, job)
		d.games.parking.streak = 10
		local def, car = C.JobById[job.kind], C.CarById[job.carId]
		T.eq(R.Reward(d, job), math.floor(def.reward * car.reward * 1.3 * 1.25 + 0.5), "Kundenbonus ×1,3")
		T.check(R.Reward(d, job) > reward, "mehr Vergütung mit Serie")
	end },
}
