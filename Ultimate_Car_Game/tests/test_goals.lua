-- Phase 5: Meilensteine, Tagesauftrag, Tagesziele, "Nächstes Ziel", Boni
local DAY = 86400

return {
	{ "Meilenstein nur einmal und nur bei erreichtem Wert", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 501, "Nora")
		local prof = H.Profile(srv, player)
		local credits = prof.credits
		H.Act(srv, player, "milestone_claim", { id = "m_scrap_10k", rid = 1 })
		T.eq(prof.games.milestones.m_scrap_10k, nil, "nicht erreicht: keine Belohnung")
		T.eq(prof.credits, credits, "keine Credits")
		prof.games.press.lifetime = 10000
		H.Act(srv, player, "milestone_claim", { id = "m_scrap_10k", rid = 2 })
		T.eq(prof.games.milestones.m_scrap_10k, true, "abgeholt")
		local after = prof.credits
		T.check(after >= credits + 500, "Belohnung")
		H.Act(srv, player, "milestone_claim", { id = "m_scrap_10k", rid = 3 })
		H.Act(srv, player, "milestone_claim", { id = "m_scrap_10k", rid = 4 })
		T.eq(prof.credits, after, "nur einmal")
		-- nach Rejoin weiterhin nur einmal
		H.Leave(srv, player)
		local p2 = H.Join(srv, 501, "Nora")
		local prof2 = H.Profile(srv, p2)
		local c2 = prof2.credits
		H.Act(srv, p2, "milestone_claim", { id = "m_scrap_10k", rid = 5 })
		T.eq(prof2.credits, c2, "nach Rejoin nicht erneut")
		H.Act(srv, p2, "milestone_claim", { id = "gibtsnicht", rid = 6 })
		T.eq(prof2.credits, c2, "unbekannter Meilenstein")
		-- Rebirth setzt Meilensteine nicht zurück
		prof2.games.press.runScrap = 1e9
		H.Act(srv, p2, "press_rebirth", { rebirths = 0, rid = 7 })
		T.eq(prof2.games.milestones.m_scrap_10k, true, "Meilenstein bleibt nach Rebirth")
	end },

	{ "Tagesauftrag und Tagesziele: pro UTC-Tag, nicht doppelt nach Rejoin", function(T, H)
		local srv = H.Server({ startTime = 1760000000 - (1760000000 % DAY) + 3600 }) -- 01:00 UTC
		local player = H.Join(srv, 502, "Olaf")
		local prof = H.Profile(srv, player)
		local credits = prof.credits
		H.Act(srv, player, "daily_claim", { rid = 1 })
		T.eq(prof.games.daily.claimed, false, "ohne Aktivität nicht abholbar")
		H.Advance(srv, 1)
		H.Act(srv, player, "press_click", { count = 1 })
		T.eq(prof.games.daily.active, true, "Aktivität erkannt")
		H.Act(srv, player, "daily_claim", { rid = 2 })
		T.eq(prof.games.daily.claimed, true, "abgeholt")
		T.eq(prof.credits, credits + srv.S.Config.DailyCredits + 0, "350 Cr")
		H.Act(srv, player, "daily_claim", { rid = 3 })
		T.eq(prof.credits, credits + srv.S.Config.DailyCredits, "nicht doppelt")
		-- Rejoin am selben Tag
		H.Leave(srv, player)
		local p2 = H.Join(srv, 502, "Olaf")
		local prof2 = H.Profile(srv, p2)
		local c2 = prof2.credits
		H.Act(srv, p2, "daily_claim", { rid = 4 })
		T.eq(prof2.credits, c2, "nach Rejoin nicht doppelt")
		-- Tagesziele: je Stufe eines
		local goals = srv.S.GoalRules.DailyGoals(srv.S.Rules.DayKey(srv.env.clock.now))
		T.eq(#goals, 3, "drei Tagesziele")
		local short = goals[1]
		T.check(short.id:sub(1, 2) == "d_", "Tagesziel-ID")
		H.Act(srv, p2, "daily_goal_claim", { id = short.id, rid = 5 })
		T.eq(prof2.games.daily.goalsClaimed[short.id], nil, "nicht erreicht")
		prof2.games.daily.progress[short.stat] = short.target
		H.Act(srv, p2, "daily_goal_claim", { id = short.id, rid = 6 })
		T.eq(prof2.games.daily.goalsClaimed[short.id], true, "abgeholt")
		local c3 = prof2.credits
		H.Act(srv, p2, "daily_goal_claim", { id = short.id, rid = 7 })
		T.eq(prof2.credits, c3, "nicht doppelt")
		H.Act(srv, p2, "daily_goal_claim", { id = "d_nicht_heute", rid = 8 })
		T.eq(prof2.credits, c3, "fremdes Tagesziel abgelehnt")
		-- Mitternacht UTC: Zurücksetzen im Tick
		H.Advance(srv, DAY)
		T.eq(prof2.games.daily.claimed, false, "neuer Tag: Tagesauftrag offen")
		T.eq(prof2.games.daily.goalsClaimed[short.id], nil, "neuer Tag: Tagesziele offen")
		T.eq(prof2.games.daily.day, srv.S.Rules.DayKey(srv.env.clock.now), "Tag aktualisiert")
		T.eq(prof2.games.daily.active, false, "Aktivität zurückgesetzt")
	end },

	{ "Tagesziele sammeln Fortschritt aus verschiedenen Spielen", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local now = 1760000000
		local p = S.Rules.LoadData(nil)
		S.GoalRules.EnsureDay(p, now)
		S.Rules.AddStat(p, "jobsDone", 2, now)
		S.Rules.AddStat(p, "quizCorrect", 1, now)
		T.eq(p.games.daily.progress.jobsDone, 2, "Werkstatt zählt")
		T.eq(p.games.stats.jobsDone, 2, "Gesamtstatistik zählt")
		-- deterministisch pro Tag, verschiedene Tage können andere Ziele haben
		local a = S.GoalRules.DailyGoals("2026-09-28")
		local b = S.GoalRules.DailyGoals("2026-09-28")
		T.eq(a[1].id, b[1].id, "deterministisch")
		local seen = {}
		for d = 1, 30 do
			seen[S.GoalRules.DailyGoals(string.format("2026-10-%02d", d))[2].id] = true
		end
		local n = 0
		for _ in pairs(seen) do
			n += 1
		end
		T.check(n >= 2, "Tagesziele wechseln")
	end },

	{ "Nächstes Ziel aktualisiert sich nach jeder relevanten Aktion", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 503, "Paul")
		local prof = H.Profile(srv, player)
		H.Advance(srv, 0.5)
		local s1 = H.LastSync(srv, player)
		T.check(s1.goals.next and s1.goals.next.text ~= "", "Ziel vorhanden: " .. tostring(s1.goals.next.text))
		-- Klicken bis ein Upgrade bezahlbar ist
		for _ = 1, 4 do
			H.Advance(srv, 0.5)
			H.Act(srv, player, "press_click", { count = 5 })
		end
		H.Advance(srv, 0.5)
		local s2 = H.LastSync(srv, player)
		T.check(s2.goals.next.progress >= 1 and s2.goals.next.text:find("kaufbar") ~= nil, "zeigt bezahlbares Upgrade: " .. s2.goals.next.text)
		prof.credits = 1e6
		H.Act(srv, player, "tuning_start", { id = "folie", rid = 1 })
		H.Advance(srv, 0.5)
		local s3 = H.LastSync(srv, player)
		local found = false
		for _, pj in ipairs(s3.tuning.projects) do
			found = found or pj.id == "folie"
		end
		T.check(found, "Tuning im Snapshot")
		H.Advance(srv, 301)
		local s4 = H.LastSync(srv, player)
		T.check(s4.goals.next.progress >= 1, "abholbares Ziel priorisiert: " .. s4.goals.next.text)
	end },

	{ "Boni-Übersicht nennt alle aktiven Boni", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local p = S.Rules.LoadData(nil)
		local list = S.GoalRules.ActiveBoni(p, { doubleScrap = true, pressPlus = false })
		local text = table.concat(list, "\n")
		for _, needle in ipairs({ "Presse → Werkstatt", "Presse → Tuning", "Rebirth", "Diagnose", "Parkplatz", "Game Pass 2× Schrott" }) do
			T.check(text:find(needle, 1, true) ~= nil, "Bonus aufgeführt: " .. needle)
		end
		T.check(not text:find("Schrottpresse+", 1, true), "nicht besessener Pass fehlt")
	end },
}
