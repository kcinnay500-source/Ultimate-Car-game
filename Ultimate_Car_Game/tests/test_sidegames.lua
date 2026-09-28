-- Phase 4: Nebenspiele (Schrottplatz, Quiz, Parkplatz) und Werkstatt
return {
	{ "Schrottplatz: Kauf, Zerlegen, Funde ins Lager, Schrott gutgeschrieben", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 401, "Jan")
		local prof = H.Profile(srv, player)
		local credits, parts, scrap, lifetime = prof.credits, prof.games.parts, prof.games.press.scrap, prof.games.press.lifetime
		H.Act(srv, player, "scrapyard_dismantle", { rid = 1 })
		T.eq(prof.games.parts, parts, "ohne Fahrzeug kein Zerlegen")
		H.Act(srv, player, "scrapyard_buy", { rid = 2 })
		T.eq(prof.credits, credits - srv.S.Config.ScrapyardCarCost, "Kaufpreis abgezogen")
		H.Act(srv, player, "scrapyard_buy", { rid = 3 })
		T.eq(prof.credits, credits - srv.S.Config.ScrapyardCarCost, "kein zweites Fahrzeug gleichzeitig")
		H.Act(srv, player, "scrapyard_dismantle", { rid = 4 })
		local results = H.Notices(srv, player, "scrapyard")
		T.eq(#results, 1, "Ergebnis gemeldet")
		local r = results[1]
		T.check(r.parts >= 2, "mindestens 2 Teile")
		T.eq(prof.games.parts, parts + r.parts, "Teile im Lager")
		T.eq(r.scrap, (r.parts - (r.rare and srv.S.Config.ScrapyardRareParts or 0)) * srv.S.Config.ScrapyardScrapPerPart, "Schrott je Teil")
		T.check(prof.games.press.scrap >= scrap + r.scrap, "Schrott gutgeschrieben")
		T.eq(prof.games.press.lifetime - lifetime <= prof.games.press.scrap - scrap - r.scrap + 1e-6, true, "Zerlege-Schrott zählt nicht für die Bestenliste")
		H.Act(srv, player, "scrapyard_dismantle", { rid = 5 })
		T.eq(#H.Notices(srv, player, "scrapyard"), 1, "kein doppeltes Zerlegen")
		T.eq(prof.games.stats.dismantled, 1, "Statistik")
		-- Verkauf
		prof.games.parts = 7
		local c = prof.credits
		H.Act(srv, player, "scrapyard_sell", { rid = 6 })
		T.eq(prof.games.parts, 2, "5 Teile verkauft")
		T.eq(prof.credits >= c + 220, true, "220 Cr")
		H.Act(srv, player, "scrapyard_sell", { rid = 7 })
		T.eq(prof.games.parts, 2, "zu wenig Teile: nichts")
	end },

	{ "Quiz: Auswertung auf dem Server, Spam wirkungslos, Bonus ≤ 35 %", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 402, "Kai")
		local prof = H.Profile(srv, player)
		H.Act(srv, player, "quiz_answer", { token = 1, choice = 1, rid = 1 })
		T.eq(prof.games.quiz.diagPoints, 0, "ohne Frage keine Wertung")
		H.Act(srv, player, "quiz_new", { rid = 2 })
		local cur = prof.games.quiz.current
		T.check(cur ~= false, "Frage gestellt")
		H.Advance(srv, 0.5)
		local snap = H.LastSync(srv, player)
		T.eq(snap.quiz.question.token, cur.token, "Client sieht Token")
		T.eq(snap.quiz.question.correct, nil, "Client sieht keine Lösung")
		T.eq(#snap.quiz.question.answers, 4, "vier Antworten")
		local correctPos = table.find(cur.order, 1)
		local wrongPos = correctPos % 4 + 1
		-- Spam: viele Antworten auf dieselbe Frage
		H.Act(srv, player, "quiz_answer", { token = cur.token, choice = wrongPos, rid = 3 })
		for i = 1, 10 do
			H.Act(srv, player, "quiz_answer", { token = cur.token, choice = correctPos, rid = 10 + i })
		end
		T.eq(prof.games.quiz.diagPoints, 0, "nach falscher Antwort keine zweite Chance")
		local res = H.Notices(srv, player, "quiz")
		T.eq(#res, 1, "genau eine Auswertung")
		T.eq(res[1].correct, false, "falsch gewertet")
		T.eq(res[1].correctPos, correctPos, "richtige Position gemeldet")
		-- richtig beantworten
		H.Act(srv, player, "quiz_new", { rid = 30 })
		T.eq(prof.games.quiz.current, false, "Abklingzeit: keine neue Frage sofort")
		H.Advance(srv, 1.1)
		H.Act(srv, player, "quiz_new", { rid = 31 })
		cur = prof.games.quiz.current
		local credits = prof.credits
		H.Act(srv, player, "quiz_answer", { token = cur.token, choice = table.find(cur.order, 1), rid = 32 })
		T.eq(prof.games.quiz.diagPoints, 1, "Diagnosepunkt")
		T.check(prof.credits >= credits + 90, "90 Cr")
		-- ungültige Wahl
		H.Advance(srv, 1.1)
		H.Act(srv, player, "quiz_new", { rid = 33 })
		cur = prof.games.quiz.current
		H.Act(srv, player, "quiz_answer", { token = cur.token, choice = 7, rid = 34 })
		H.Act(srv, player, "quiz_answer", { token = cur.token, choice = 1.5, rid = 35 })
		T.check(prof.games.quiz.current ~= false, "ungültige Wahl verbraucht die Frage nicht")
		-- Deckel
		prof.games.quiz.diagPoints = 1000
		T.eq(srv.S.WorkshopRules.DiagReduction(prof), 0.35, "Diagnose-Bonus gedeckelt auf 35 %")
		-- Antwortreihenfolge wird gemischt
		local positions = {}
		for i = 1, 30 do
			H.Advance(srv, 1.1)
			H.Act(srv, player, "quiz_new", { rid = 100 + i })
			positions[table.find(prof.games.quiz.current.order, 1)] = true
		end
		local distinct = 0
		for _ in pairs(positions) do
			distinct += 1
		end
		T.check(distinct >= 3, "richtige Antwort steht nicht immer an derselben Stelle")
	end },

	{ "Parkplatz: Lösung serverseitig geprüft, Serienbonus gedeckelt", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 403, "Lea")
		local prof = H.Profile(srv, player)
		local SG = srv.S.SideGameRules
		H.Act(srv, player, "parking_tap", { cell = 3, rid = 1 })
		T.eq(prof.games.parking.streak, 0, "ohne Rätsel nichts")
		H.Act(srv, player, "parking_new", { rid = 2 })
		local pz = prof.games.parking.puzzle
		T.eq(#pz.cars, srv.S.Config.ParkingCars, "7 Autos")
		T.check(not table.find(pz.cars, pz.exit), "Ausfahrt frei")
		-- leeres Feld / Ausfahrt antippen: keine Wirkung
		local empty
		for c = 0, 14 do
			if not table.find(pz.cars, c) then
				empty = c
				break
			end
		end
		H.Act(srv, player, "parking_tap", { cell = empty, rid = 3 })
		H.Act(srv, player, "parking_tap", { cell = pz.exit, rid = 4 })
		T.eq(pz.moves, 0, "leere Felder zählen nicht")
		-- Blockierer wegfahren, dann Ziel
		local rid = 10
		for _, cell in ipairs(SG.ParkingPath(pz.target)) do
			if table.find(pz.cars, cell) then
				rid += 1
				H.Act(srv, player, "parking_tap", { cell = cell, rid = rid })
			end
		end
		T.eq(SG.ParkingBlocked(pz), false, "Weg frei")
		local credits = prof.credits
		H.Act(srv, player, "parking_tap", { cell = pz.target, rid = 50 })
		T.eq(pz.solved, true, "gelöst")
		T.eq(prof.games.parking.streak, 1, "Serie 1")
		T.check(prof.credits >= credits + 135, "Belohnung 120 + 15")
		H.Act(srv, player, "parking_tap", { cell = pz.target, rid = 51 })
		T.eq(prof.games.parking.streak, 1, "kein doppeltes Lösen")
		-- Blechschaden: Ziel bei blockiertem Weg
		local crashed = false
		for i = 1, 50 do
			H.Act(srv, player, "parking_new", { rid = 100 + i })
			local p2 = prof.games.parking.puzzle
			if SG.ParkingBlocked(p2) then
				prof.games.parking.streak = 4
				H.Act(srv, player, "parking_tap", { cell = p2.target, rid = 200 + i })
				crashed = p2.crashed and prof.games.parking.streak == 0
				break
			end
		end
		T.check(crashed, "blockiertes Ziel: Blechschaden, Serie beendet")
		-- Deckel
		prof.games.parking.streak = 1000
		T.eq(srv.S.WorkshopRules.CustomerBonus(prof), 1.7, "Serienbonus gedeckelt auf 1,7")
		T.eq(srv.S.WorkshopRules.DesiredOffers(prof), 3 + 5, "Zusatzangebote gedeckelt")
		-- Abbruch beendet die Serie
		H.Act(srv, player, "parking_new", { rid = 300 })
		local p3 = prof.games.parking.puzzle
		prof.games.parking.streak = 3
		local other
		for _, c in ipairs(p3.cars) do
			if c ~= p3.target then
				other = c
				break
			end
		end
		H.Act(srv, player, "parking_tap", { cell = other, rid = 301 })
		H.Act(srv, player, "parking_new", { rid = 302 })
		T.eq(prof.games.parking.streak, 0, "abgebrochene Runde beendet die Serie")
	end },

	{ "Werkstatt: Annehmen, Hebebühnen, Abrechnen, Ausbau", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 404, "Mia")
		local prof = H.Profile(srv, player)
		local W = srv.S.WorkshopRules
		T.eq(#prof.games.offers, 3, "3 Angebote")
		local offer = prof.games.offers[1]
		local cash, useParts = W.CashCost(prof, offer)
		local credits, parts = prof.credits, prof.games.parts
		H.Act(srv, player, "workshop_accept", { id = offer.id, rid = 1 })
		T.eq(#prof.games.jobs, 1, "Auftrag auf der Bühne")
		T.eq(prof.credits, credits - cash, "Barkosten")
		T.eq(prof.games.parts, parts - useParts, "Teile verbraucht")
		T.eq(#prof.games.offers, 3, "Angebote aufgefüllt")
		H.Act(srv, player, "workshop_accept", { id = prof.games.offers[1].id, rid = 2 })
		T.eq(#prof.games.jobs, 1, "nur eine Hebebühne")
		H.Act(srv, player, "workshop_accept", { id = offer.id, rid = 3 })
		T.eq(#prof.games.jobs, 1, "angenommenes Angebot nicht erneut")
		local job = prof.games.jobs[1]
		H.Act(srv, player, "workshop_finish", { id = job.id, rid = 4 })
		T.eq(#prof.games.jobs, 1, "vor Ablauf nicht abrechenbar")
		H.Advance(srv, job.endsAt - srv.env.clock.now + 1)
		local c2 = prof.credits
		H.Act(srv, player, "workshop_finish", { id = job.id, rid = 5 })
		T.eq(#prof.games.jobs, 0, "abgerechnet")
		T.check(prof.credits >= c2 + W.Reward(prof, job), "Vergütung")
		H.Act(srv, player, "workshop_finish", { id = job.id, rid = 6 })
		T.eq(prof.games.stats.jobsDone, 1, "kein doppeltes Abrechnen")
		-- Ausbau
		prof.credits = 100000
		H.Act(srv, player, "upgrade_buy", { key = "bays", level = 1, rid = 7 })
		H.Act(srv, player, "upgrade_buy", { key = "bays", level = 1, rid = 8 })
		T.eq(prof.games.bays, 2, "Doppelklick: eine Stufe")
		T.eq(prof.credits, 100000 - 1100, "HTML-Preis 1100")
		H.Act(srv, player, "upgrade_buy", { key = "hack", level = 1, rid = 9 })
		T.eq(prof.credits, 100000 - 1100, "unbekannter Ausbau")
		prof.games.offerSlots = 30
		H.Act(srv, player, "upgrade_buy", { key = "offerSlots", level = 30, rid = 10 })
		T.eq(prof.games.offerSlots, 30, "Maximum")
		-- Diagnosepunkte verkürzen die Reparatur
		prof.games.quiz.diagPoints = 10
		local speed = W.RepairSpeed(prof)
		T.near(speed, 1 * (1 - 0.15), 1e-9, "Diagnose verkürzt Reparaturzeit")
	end },
}
