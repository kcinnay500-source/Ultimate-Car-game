-- Meilensteine, Tagesauftrag, Tagesziele, "Nächstes Ziel", Boni – im echten Server, verknüpft mit der 2.4.0-Werkstatt
local DAY = 86400
local Flow

return {
	{ "Meilenstein nur einmal und nur bei erreichtem Wert", function(T, H)
		local g = H.Garage()
		local player = g:Join(501, { name = "Nora" })
		g:Advance(1)
		local d = g:D(player)
		d.games.press.upgrades = {}
		local money = d.money
		g:Act(player, "mini_milestone_claim", { id = "m_scrap_10k", rid = 1 })
		T.eq(d.games.milestones.m_scrap_10k, nil, "nicht erreicht: keine Belohnung")
		T.eq(d.money, money, "keine Credits")
		d.games.press.lifetime = 10000
		g:Advance(0.2)
		g:Act(player, "mini_milestone_claim", { id = "m_scrap_10k", rid = 2 })
		T.eq(d.games.milestones.m_scrap_10k, true, "abgeholt")
		local after = d.money
		T.check(after >= money + 500, "Belohnung")
		g:Advance(0.2)
		g:Act(player, "mini_milestone_claim", { id = "m_scrap_10k", rid = 3 })
		g:Advance(0.2)
		g:Act(player, "mini_milestone_claim", { id = "m_scrap_10k", rid = 4 })
		T.eq(d.money, after, "nur einmal")
		g:Leave(player)
		g:Advance(1)
		local p2 = g:Join(501, { name = "Nora" })
		g:Advance(0.5)
		local d2 = g:D(p2)
		local c2 = d2.money
		g:Act(p2, "mini_milestone_claim", { id = "m_scrap_10k", rid = 5 })
		T.eq(d2.money, c2, "nach Rejoin nicht erneut")
		g:Act(p2, "mini_milestone_claim", { id = "gibtsnicht", rid = 6 })
		T.eq(d2.money, c2, "unbekannter Meilenstein")
		d2.games.press.runScrap = 1e9
		g:Act(p2, "mini_press_rebirth", { rebirths = 0, rid = 7 })
		T.eq(d2.games.milestones.m_scrap_10k, true, "Meilenstein bleibt nach Rebirth")
	end },

	{ "Veteran: abgerechnete 2.4.0-Aufträge zählen für Meilensteine", function(T, H)
		local g = H.Garage()
		g:Seed(505, { version = 2, data = { version = 2, money = 100, level = 3, completed = 12 }, receipts = {} })
		local p = g:Join(505)
		g:Advance(1)
		local d = g:D(p)
		T.eq(d.games.stats.jobsDone, 12, "jobsDone = completed")
		local money = d.money
		g:Act(p, "mini_milestone_claim", { id = "m_jobs_10", rid = 1 })
		T.eq(d.games.milestones.m_jobs_10, true, "10 Aufträge sofort abholbar")
		T.check(d.money >= money + 1500, "Belohnung")
	end },

	{ "Tagesauftrag und Tagesziele: pro UTC-Tag, nicht doppelt nach Rejoin", function(T, H)
		local g = H.Garage({ startTime = 1760000000 - (1760000000 % DAY) + 3600 }) -- 01:00 UTC
		local MC, GR, MR = g:MiniShared("MiniConfig"), g:MiniShared("GoalRules"), g:MiniShared("MiniRules")
		local player = g:Join(502, { name = "Olaf" })
		g:Advance(1)
		local d = g:D(player)
		local money = d.money
		g:Act(player, "mini_daily_claim", { rid = 1 })
		T.eq(d.games.daily.claimed, false, "ohne Aktivität nicht abholbar")
		g:Advance(1)
		g:Act(player, "mini_press_click", { count = 1 })
		T.eq(d.games.daily.active, true, "Aktivität erkannt")
		local m = g:Mark()
		g:Act(player, "mini_daily_claim", { rid = 2 })
		T.eq(d.games.daily.claimed, true, "abgeholt")
		T.check(d.money >= money + MC.DailyCredits, "350 Cr")
		T.check(g:HasToast(player, "Tagesauftrag erledigt", m), "Toast")
		local after = d.money
		g:Advance(0.2)
		g:Act(player, "mini_daily_claim", { rid = 3 })
		T.eq(d.money, after, "nicht doppelt")
		g:Leave(player)
		g:Advance(1)
		local p2 = g:Join(502, { name = "Olaf" })
		g:Advance(0.5)
		local d2 = g:D(p2)
		local c2 = d2.money
		g:Act(p2, "mini_daily_claim", { rid = 4 })
		T.eq(d2.money, c2, "nach Rejoin nicht doppelt")
		local goals = GR.DailyGoals(MR.DayKey(g:Now()))
		T.eq(#goals, 3, "drei Tagesziele")
		local short = goals[1]
		T.check(short.id:sub(1, 2) == "d_", "Tagesziel-ID")
		g:Act(p2, "mini_daily_goal_claim", { id = short.id, rid = 5 })
		T.eq(d2.games.daily.goalsClaimed[short.id], nil, "nicht erreicht")
		d2.games.daily.progress[short.stat] = short.target
		g:Advance(0.2)
		g:Act(p2, "mini_daily_goal_claim", { id = short.id, rid = 6 })
		T.eq(d2.games.daily.goalsClaimed[short.id], true, "abgeholt")
		local c3 = d2.money
		g:Advance(0.2)
		g:Act(p2, "mini_daily_goal_claim", { id = short.id, rid = 7 })
		T.eq(d2.money, c3, "nicht doppelt")
		g:Act(p2, "mini_daily_goal_claim", { id = "d_nicht_heute", rid = 8 })
		T.eq(d2.money, c3, "fremdes Tagesziel abgelehnt")
		-- Mitternacht UTC: Zurücksetzen im Tick
		g:Advance(DAY)
		T.eq(d2.games.daily.claimed, false, "neuer Tag: Tagesauftrag offen")
		T.eq(d2.games.daily.goalsClaimed[short.id], nil, "neuer Tag: Tagesziele offen")
		T.eq(d2.games.daily.day, MR.DayKey(g:Now()), "Tag aktualisiert")
		T.eq(d2.games.daily.active, false, "Aktivität zurückgesetzt")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Werkstatt-Abrechnung zählt für Ziele und schaltet den Tagesauftrag frei", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage()
		local p = g:Join(506)
		g:Advance(1)
		local d = g:D(p)
		T.eq(d.games.daily.active, false, "noch nicht aktiv")
		local jobs0 = d.games.stats.jobsDone
		local receipt = Flow.CompleteInspection(T, g, p)
		T.check(receipt ~= nil, "Auftrag abgerechnet")
		T.eq(d.games.stats.jobsDone, jobs0 + 1, "jobsDone +1")
		T.eq(d.games.daily.progress.jobsDone, 1, "Tagesfortschritt jobsDone")
		T.eq(d.games.daily.active, true, "Abrechnung zählt als heute gespielt")
		local money = d.money
		g:Act(p, "mini_daily_claim", { rid = 1 })
		T.eq(d.games.daily.claimed, true, "Tagesauftrag abholbar")
		T.check(d.money > money, "Belohnung")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Tagesziele sammeln Fortschritt aus verschiedenen Spielen", function(T, H)
		local g = H.Garage({ noServer = true })
		local R, GR, MR = g:Rules(), g:MiniShared("GoalRules"), g:MiniShared("MiniRules")
		local now = 1760000000
		local d = R.NewData(now)
		GR.EnsureDay(d, now)
		MR.AddStat(d, "jobsDone", 2, now)
		MR.AddStat(d, "quizCorrect", 1, now)
		T.eq(d.games.daily.progress.jobsDone, 2, "Werkstatt zählt")
		T.eq(d.games.stats.jobsDone, 2, "Gesamtstatistik zählt")
		local a = GR.DailyGoals("2026-09-28")
		local b = GR.DailyGoals("2026-09-28")
		T.eq(a[1].id, b[1].id, "deterministisch")
		local seen = {}
		for day = 1, 30 do
			seen[GR.DailyGoals(string.format("2026-10-%02d", day))[2].id] = true
		end
		local n = 0
		for _ in pairs(seen) do
			n += 1
		end
		T.check(n >= 2, "Tagesziele wechseln")
		-- passive Produktion zählt für Ziele, aber nicht als "heute gespielt"
		local d2 = R.NewData(now)
		MR.AddStat(d2, "pressed", 100, now, true)
		T.eq(d2.games.daily.progress.pressed, 100, "passiv gezählt")
		T.eq(d2.games.daily.active, false, "passiv nicht aktiv")
	end },

	{ "Nächstes Ziel aktualisiert sich nach jeder relevanten Aktion", function(T, H)
		local g = H.Garage()
		local player = g:Join(503, { name = "Paul" })
		g:Advance(1)
		local d = g:D(player)
		d.games.press.upgrades = {}
		d.games.press.scrap = 0
		d.games.milestones = {}
		g:Advance(0.6)
		local s1 = g:MiniSnapshot(player)
		T.check(s1 and s1.goals.next and s1.goals.next.text ~= "", "Ziel vorhanden: " .. tostring(s1 and s1.goals.next.text))
		d.games.press.scrap = 0
		for _ = 1, 4 do
			g:Advance(0.5)
			g:Act(player, "mini_press_click", { count = 5 })
		end
		g:Advance(0.6)
		local s2 = g:MiniSnapshot(player)
		T.check(s2.goals.next.progress >= 1, "Fortschritt 1: " .. s2.goals.next.text)
		d.money = 1e6
		g:Act(player, "mini_tuning_start", { id = "folie", rid = 1 })
		g:Advance(0.6)
		local s3 = g:MiniSnapshot(player)
		local found = false
		for _, pj in ipairs(s3.tuning.projects) do
			found = found or pj.id == "folie"
		end
		T.check(found, "Tuning im Snapshot")
		g:Advance(301)
		local s4 = g:MiniSnapshot(player)
		T.check(s4.goals.next.progress >= 1, "abholbares Ziel priorisiert: " .. s4.goals.next.text)
		-- 2.4.0-Auftrag wartet auf Abrechnung: Ziel verweist auf die Werkstatt
		local GR = g:MiniShared("GoalRules")
		local C = g:Config()
		local R = g:Rules()
		local dd = R.NewData(g:Now())
		dd.games.press.scrap = 0
		dd.jobs = { { id = "job_1", kind = C.Jobs[1].id, carId = C.Cars[1].id, bay = 1, phase = "invoice", step = 1, quality = 100, usedParts = {} } }
		local nextGoal = GR.NextGoal(dd, g:Now())
		T.eq(nextGoal.tab, "workshop", "Auftrag abrechnen -> Werkstatt")
		T.check(nextGoal.text:find("Auftrag abrechnen") ~= nil, "Text: " .. nextGoal.text)
		local snap = g:MiniShared("MiniSnapshot").Build(dd, g:Now(), {}, nil)
		T.eq(snap.workshopJobs.total, 1, "Snapshot: 1 Auftrag")
		T.eq(snap.workshopJobs.ready, 1, "Snapshot: 1 abrechenbar")
	end },

	{ "Boni-Übersicht nennt alle aktiven Boni", function(T, H)
		local g = H.Garage({ noServer = true })
		local R, GR = g:Rules(), g:MiniShared("GoalRules")
		local d = R.NewData(1760000000)
		local list = GR.ActiveBoni(d, { doubleScrap = true, pressPlus = false })
		local text = table.concat(list, "\n")
		for _, needle in ipairs({ "Presse → Werkstatt", "Presse → Tuning", "Rebirth", "Diagnose", "Parkplatz", "Werkzeugqualität", "Game Pass 2× Schrott" }) do
			T.check(text:find(needle, 1, true) ~= nil, "Bonus aufgeführt: " .. needle)
		end
		T.check(not text:find("Schrottpresse+", 1, true), "nicht besessener Pass fehlt")
	end },
}
