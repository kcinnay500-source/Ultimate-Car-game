-- Idle Tuning Garage im echten Server und ihr Querbonus auf die 2.4.0-Werkstatt
local NOW = 1760000000

return {
	{ "Belohnung wächst überproportional mit der Laufzeit", function(T, H)
		local g = H.Garage({ noServer = true })
		local R, MC, TR = g:Rules(), g:MiniShared("MiniConfig"), g:MiniShared("TuningRules")
		local d = R.NewData(NOW)
		local prev
		for _, def in ipairs(MC.TuningProjects) do
			local perMinute = TR.Reward(d, def) / def.minutes
			if prev then
				T.check(perMinute > prev, "längeres Projekt lohnt mehr pro Minute: " .. def.name)
			end
			prev = perMinute
		end
		T.eq(MC.TuningProjects[1].minutes, 5, "kürzestes 5 Min.")
		T.eq(MC.TuningProjects[#MC.TuningProjects].minutes, 480, "längstes 8 Std.")
	end },

	{ "Starten, Rejoin während der Laufzeit, Abholen erst nach Ablauf, nie doppelt", function(T, H)
		local g = H.Garage({ level = 12 })
		local TR = g:MiniShared("TuningRules")
		local player = g:Join(301, { name = "Hanna" })
		g:Advance(1)
		local d = g:D(player)
		d.money = 100000
		d.games.press.upgrades = {}
		g:Act(player, "mini_tuning_start", { id = "folie", rid = 1 })
		T.eq(#d.games.tuning.projects, 1, "Projekt läuft")
		local cost = TR.Cost(TR.ProjectDef("folie"))
		T.eq(d.money, 100000 - cost, "Kosten abgezogen")
		g:Act(player, "mini_tuning_start", { id = "fahrwerk", rid = 2 })
		T.eq(#d.games.tuning.projects, 1, "nur ein Platz auf Stufe 1")
		g:Act(player, "mini_tuning_collect", { slot = 1, rid = 3 })
		T.eq(#d.games.tuning.projects, 1, "vor Ablauf nicht abholbar")
		g:Advance(120)
		g:Leave(player)
		g:Advance(1)
		g.env.clock:Jump(200)
		local p2 = g:Join(301, { name = "Hanna" })
		g:Advance(0.5)
		local d2 = g:D(p2)
		T.eq(#d2.games.tuning.projects, 1, "Projekt nach Rejoin vorhanden")
		local money = d2.money
		local reward = TR.Reward(d2, TR.ProjectDef("folie"))
		g:Act(p2, "mini_tuning_collect", { slot = 1, rid = 4 })
		T.check(d2.money >= money + reward, "offline abgelaufen und abgeholt")
		T.eq(#d2.games.tuning.projects, 0, "Platz frei")
		local after = d2.money
		g:Advance(0.2)
		g:Act(p2, "mini_tuning_collect", { slot = 1, rid = 5 })
		g:Advance(0.2)
		g:Act(p2, "mini_tuning_collect", { slot = 1, rid = 6 })
		T.eq(d2.money, after, "kein doppeltes Abholen")
		T.eq(d2.games.stats.tuningCollected, 1, "Statistik einmal gezählt")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Gesperrte Projekte, Uhr rückwärts", function(T, H)
		local g = H.Garage({ noServer = true })
		local R, TR = g:Rules(), g:MiniShared("TuningRules")
		local d = R.NewData(NOW)
		d.money = 1e9
		local ok = TR.Start(d, "restomod", 1000)
		T.eq(ok, false, "8-Std.-Projekt erst ab Stufe 12")
		d.games.tuningLevel = 12
		T.eq(TR.Start(d, "restomod", 1000), true, "freigeschaltet")
		T.eq(TR.Remaining(d.games.tuning.projects[1], 500), 480 * 60, "Serveruhr vor dem Start: volle Restzeit, nie fertig")
		T.eq((TR.Collect(d, 1, 500)), false, "nicht abholbar bei Uhr rückwärts")
		local ok2 = TR.Collect(d, 1, 1000 + 480 * 60)
		T.eq(ok2, true, "nach 8 Std. abholbar")
		T.eq(d.games.stats.longTuning, 1, "8-Std.-Tuning gezählt")
		T.eq(TR.Slots(d), 2, "Stufe 12: 2 Plätze")
	end },

	{ "Passive Einnahmen nach HTML-Formel, gedeckelt, Offline verrechnet", function(T, H)
		local g0 = H.Garage({ noServer = true })
		local R, TR = g0:Rules(), g0:MiniShared("TuningRules")
		local d = R.NewData(NOW)
		d.games.tuningLevel = 3
		d.games.tuning.completed = 4
		local rate = (10 + 3 * 4 + 4 ^ 1.12 * 1.5) * 1
		T.near(TR.IdleRate(d), rate, 1e-9, "idleRate wie HTML")
		d.games.tuning.lastIdle = 1000
		T.eq(TR.PendingIdle(d, 1000 + 600), math.floor(600 / 60 * rate), "10 Minuten")
		T.eq(TR.PendingIdle(d, 1000 + 30 * 3600), math.floor(8 * 3600 / 60 * rate), "gedeckelt auf 8 Std.")
		T.eq(TR.PendingIdle(d, 500), 0, "Uhr rückwärts: 0")
		local money = d.money
		local ok, value = TR.CollectIdle(d, 1000 + 600)
		T.eq(ok, true, "abgeholt")
		T.check(d.money >= money + value, "gutgeschrieben")
		T.eq((TR.CollectIdle(d, 1000 + 600)), false, "sofort erneut: nichts")

		local g = H.Garage({ level = 12 })
		local player = g:Join(302, { name = "Ida" })
		g:Advance(0.1)
		T.near(g:D(player).games.tuning.lastIdle, g:Now(), 1, "Sammeln beginnt beim ersten Beitritt")
		g:Leave(player)
		g:Advance(1)
		g.env.clock:Jump(3600)
		local p2 = g:Join(302, { name = "Ida" })
		g:Advance(1)
		local snap = g:MiniSnapshot(p2)
		T.check(snap and snap.tuning.pendingIdle >= math.floor(59 * TR.IdleRate(g:D(p2))), "Offline-Stunde verrechnet")
		local m = g:Mark()
		local money2 = g:D(p2).money
		g:Act(p2, "mini_tuning_idle", { rid = 1 })
		T.check(g:D(p2).money > money2, "passive Einnahmen abgeholt")
		T.check(g:HasToast(p2, "Passive Einnahmen", m), "Toast")
	end },

	{ "Tuning-Stufe und Presse steigern die Werkstatt-Vergütung (R.Reward)", function(T, H)
		local g = H.Garage({ noServer = true })
		local R, C, CB = g:Rules(), g:Config(), g:MiniShared("CrossBonus")
		local d = R.NewData(NOW)
		local job = { kind = C.Jobs[1].id, carId = C.Cars[1].id, quality = 100, usedParts = {} }
		local base = R.Reward(d, job)
		d.games.tuningLevel = 11
		T.near(CB.TuningWorkshop(d), 1 + 10 * 0.045, 1e-9, "Tuning-Stufe -> Werkstatt")
		local def, car = C.JobById[job.kind], C.CarById[job.carId]
		T.eq(R.Reward(d, job), math.floor(def.reward * car.reward * 1.45 * (1 + 100 * 0.0025) + 0.5), "Vergütung mit Tuning-Bonus")
		T.check(R.Reward(d, job) > base, "mehr als ohne Bonus")
		-- ohne games (z. B. alter Client-Zustand) neutral
		local plain = R.NewData(NOW)
		plain.games = nil
		T.eq(R.Reward(plain, job), base, "ohne games: 2.4.0-Vergütung")
	end },

	{ "Minispiel-Ausbau (mini_upgrade): Preis, Doppelklick, Maximum", function(T, H)
		local g = H.Garage({ level = 12 })
		local MC, MR = g:MiniShared("MiniConfig"), g:MiniShared("MiniRules")
		local p = g:Join(303)
		g:Advance(1)
		local d = g:D(p)
		d.money = 100000
		local u = MC.UpgradeByKey.tuningLevel
		local cost = MR.UpgradeCost(d, u)
		T.eq(cost, 850, "HTML-Preis Tuning-Stufe 2")
		g:Act(p, "mini_upgrade", { key = "tuningLevel", level = 1, rid = 1 })
		g:Act(p, "mini_upgrade", { key = "tuningLevel", level = 1, rid = 2 })
		T.eq(d.games.tuningLevel, 2, "Doppelklick: eine Stufe")
		T.check(d.money <= 100000 - 850 + 1000, "Preis abgezogen (Level-Bonus möglich)")
		g:Act(p, "mini_upgrade", { key = "scrapyardLevel", level = 1, rid = 3 })
		T.eq(d.games.scrapyardLevel, 2, "zweiter Ausbau direkt danach (anderes Ziel)")
		g:Advance(0.2)
		local money = d.money
		g:Act(p, "mini_upgrade", { key = "bays", level = 1, rid = 4 })
		g:Act(p, "mini_upgrade", { key = "hack", level = 1, rid = 5 })
		T.eq(d.money, money, "2.4.0-Ausbau und Unbekanntes nicht über mini_upgrade")
		T.eq(d.bays, 1, "Hebebühnen unverändert")
		d.games.tuningLevel = u.max
		g:Advance(0.2)
		g:Act(p, "mini_upgrade", { key = "tuningLevel", level = u.max, rid = 6 })
		T.eq(d.games.tuningLevel, u.max, "Maximum")
		T.eq(d.money, money, "am Maximum kein Abzug")
	end },
}
