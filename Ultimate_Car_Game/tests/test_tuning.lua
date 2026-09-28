-- Phase 3: Idle Tuning Garage
return {
	{ "Belohnung wächst überproportional mit der Laufzeit", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local p = S.Rules.LoadData(nil)
		local prev
		for _, def in ipairs(S.Config.TuningProjects) do
			local perMinute = S.TuningRules.Reward(p, def) / def.minutes
			if prev then
				T.check(perMinute > prev, "längeres Projekt lohnt mehr pro Minute: " .. def.name)
			end
			prev = perMinute
		end
		T.eq(S.Config.TuningProjects[1].minutes, 5, "kürzestes 5 Min.")
		T.eq(S.Config.TuningProjects[#S.Config.TuningProjects].minutes, 480, "längstes 8 Std.")
	end },

	{ "Starten, Rejoin während der Laufzeit, Abholen erst nach Ablauf, nie doppelt", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 301, "Hanna")
		local prof = H.Profile(srv, player)
		prof.credits = 100000
		H.Act(srv, player, "tuning_start", { id = "folie", rid = 1 })
		T.eq(#prof.games.tuning.projects, 1, "Projekt läuft")
		local cost = srv.S.TuningRules.Cost(srv.S.TuningRules.ProjectDef("folie"))
		T.eq(prof.credits, 100000 - cost, "Kosten abgezogen")
		H.Act(srv, player, "tuning_start", { id = "fahrwerk", rid = 2 })
		T.eq(#prof.games.tuning.projects, 1, "nur ein Platz auf Stufe 1")
		H.Act(srv, player, "tuning_collect", { slot = 1, rid = 3 })
		T.eq(#prof.games.tuning.projects, 1, "vor Ablauf nicht abholbar")
		-- Rejoin nach 2 Minuten
		H.Advance(srv, 120)
		H.Leave(srv, player)
		srv.env.clock:Jump(200)
		local p2 = H.Join(srv, 301, "Hanna")
		local prof2 = H.Profile(srv, p2)
		T.eq(#prof2.games.tuning.projects, 1, "Projekt nach Rejoin vorhanden")
		local credits = prof2.credits
		H.Act(srv, p2, "tuning_collect", { slot = 1, rid = 4 })
		T.eq(prof2.credits, credits + srv.S.TuningRules.Reward(prof2, srv.S.TuningRules.ProjectDef("folie")), "offline abgelaufen und abgeholt")
		T.eq(#prof2.games.tuning.projects, 0, "Platz frei")
		local after = prof2.credits
		H.Act(srv, p2, "tuning_collect", { slot = 1, rid = 5 })
		H.Act(srv, p2, "tuning_collect", { slot = 1, rid = 6 })
		T.eq(prof2.credits, after, "kein doppeltes Abholen")
		T.eq(prof2.games.stats.tuningCollected, 1, "Statistik einmal gezählt")
	end },

	{ "Gesperrte Projekte, Uhr rückwärts", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local p = S.Rules.LoadData(nil)
		p.credits = 1e9
		local ok = S.TuningRules.Start(p, "restomod", 1000)
		T.eq(ok, false, "8-Std.-Projekt erst ab Stufe 12")
		p.games.tuningLevel = 12
		T.eq(S.TuningRules.Start(p, "restomod", 1000), true, "freigeschaltet")
		T.eq(S.TuningRules.Remaining(p.games.tuning.projects[1], 500), 480 * 60, "Serveruhr vor dem Start: volle Restzeit, nie fertig")
		T.eq((S.TuningRules.Collect(p, 1, 500)), false, "nicht abholbar bei Uhr rückwärts")
		local ok2 = S.TuningRules.Collect(p, 1, 1000 + 480 * 60)
		T.eq(ok2, true, "nach 8 Std. abholbar")
		T.eq(p.games.stats.longTuning, 1, "8-Std.-Tuning gezählt")
		T.eq(S.TuningRules.Slots(p), 2, "Stufe 12: 2 Plätze")
	end },

	{ "Passive Einnahmen nach HTML-Formel, gedeckelt, Offline verrechnet", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local p = S.Rules.LoadData(nil)
		p.games.tuningLevel = 3
		p.games.tuning.completed = 4
		local rate = (10 + 3 * 4 + 4 ^ 1.12 * 1.5) * 1
		T.near(S.TuningRules.IdleRate(p), rate, 1e-9, "idleRate wie HTML")
		p.games.tuning.lastIdle = 1000
		T.eq(S.TuningRules.PendingIdle(p, 1000 + 600), math.floor(600 / 60 * rate), "10 Minuten")
		T.eq(S.TuningRules.PendingIdle(p, 1000 + 30 * 3600), math.floor(8 * 3600 / 60 * rate), "gedeckelt auf 8 Std.")
		T.eq(S.TuningRules.PendingIdle(p, 500), 0, "Uhr rückwärts: 0")
		local credits = p.credits
		local ok, value = S.TuningRules.CollectIdle(p, 1000 + 600)
		T.eq(ok, true, "abgeholt")
		T.eq(p.credits, credits + value, "gutgeschrieben")
		T.eq((S.TuningRules.CollectIdle(p, 1000 + 600)), false, "sofort erneut: nichts")

		local srv = H.Server()
		local player = H.Join(srv, 302, "Ida")
		local prof = H.Profile(srv, player)
		T.eq(prof.games.tuning.lastIdle, srv.env.clock.now, "Sammeln beginnt beim ersten Beitritt")
		H.Leave(srv, player)
		srv.env.clock:Jump(3600)
		local p2 = H.Join(srv, 302, "Ida")
		local snap
		H.Advance(srv, 0.5)
		snap = H.LastSync(srv, p2)
		T.check(snap and snap.tuning.pendingIdle >= math.floor(59 * srv.S.TuningRules.IdleRate(H.Profile(srv, p2))), "Offline-Stunde verrechnet")
	end },

	{ "Tuning-Stufe steigert die Werkstatt-Vergütung wie HTML", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local p = S.Rules.LoadData(nil)
		p.games.tuningLevel = 11
		T.near(S.WorkshopRules.TuningWorkshopBonus(p), 1 + 10 * 0.045, 1e-9, "workshopBonus")
		local job = { reward = 1000 }
		T.eq(S.WorkshopRules.Reward(p, job), math.floor(1000 * 1.45 + 0.5), "Vergütung mit Tuning-Bonus")
	end },
}
