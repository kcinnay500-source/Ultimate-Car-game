-- Mehrspieler: getrennte Zustände, Spieler B beeinflusst Spieler A nicht
local function snapshotOf(prof)
	return {
		credits = prof.credits, scrap = prof.games.press.scrap, lifetime = prof.games.press.lifetime,
		ups = prof.games.press.upgrades.pu0, rebirths = prof.games.press.rebirths, milestones = prof.games.milestones.m_scrap_10k,
		projects = #prof.games.tuning.projects, jobs = #prof.games.jobs, streak = prof.games.parking.streak,
		daily = prof.games.daily.claimed, diag = prof.games.quiz.diagPoints,
	}
end

return {
	{ "Zwei Spieler: getrennte Zustände", function(T, H)
		local srv = H.Server()
		local a = H.Join(srv, 701, "Alma")
		local b = H.Join(srv, 702, "Bodo")
		local pa, pb = H.Profile(srv, a), H.Profile(srv, b)
		T.check(pa ~= pb, "eigene Profile")
		pa.games.press.upgrades.pu1 = 5
		H.Advance(srv, 1)
		local before = snapshotOf(pa)
		before.scrap = nil
		before.lifetime = nil
		-- B macht alles Mögliche
		pb.credits = 1e7
		pb.games.press.scrap = 1e7
		pb.games.press.runScrap = 1e12
		pb.games.press.lifetime = 1e7
		local rid = 0
		local function actB(name, payload)
			rid += 1
			payload = payload or {}
			payload.rid = rid
			H.Act(srv, b, name, payload)
		end
		actB("press_click", { count = 20 })
		actB("press_buy", { id = "pu0", level = 0 })
		actB("press_exchange", { index = 1 })
		actB("press_rebirth", { rebirths = 0 })
		actB("milestone_claim", { id = "m_scrap_10k" })
		actB("tuning_start", { id = "folie" })
		actB("workshop_accept", { id = pa.games.offers[1].id })
		actB("parking_new")
		actB("quiz_new")
		actB("daily_claim")
		local after = snapshotOf(pa)
		after.scrap = nil
		after.lifetime = nil
		for k, v in pairs(before) do
			T.eq(after[k], v, "A unverändert: " .. k)
		end
		T.eq(pb.games.press.rebirths, 1, "B hat eigenes Rebirth")
		T.eq(pb.games.milestones.m_scrap_10k, true, "B hat eigenen Meilenstein")
	end },

	{ "Bestenlistenwerte getrennt", function(T, H)
		local srv = H.Server()
		local a = H.Join(srv, 703, "Carmen")
		local b = H.Join(srv, 704, "Dirk")
		H.Advance(srv, 1)
		for _ = 1, 10 do
			H.Act(srv, b, "press_click", { count = 10 })
			H.Advance(srv, 0.5)
		end
		local la, lb = H.Profile(srv, a).games.press.lifetime, H.Profile(srv, b).games.press.lifetime
		T.check(lb > la, "B klickt, A nicht")
		H.Leave(srv, a)
		H.Leave(srv, b)
		local ordered = srv.env.services.DataStoreService.__data.ordered[srv.S.Config.LeaderboardStoreName].data
		T.check(ordered["703"] == nil or ordered["703"] < ordered["704"], "Werte je Spieler getrennt gespeichert")
		T.eq(srv.S.PressRules.DecodeScore(ordered["704"]), math.floor(lb + 0.5), "B-Wert korrekt")
	end },

	{ "8 Spieler gleichzeitig", function(T, H)
		local srv = H.Server()
		local ps = {}
		for i = 1, 8 do
			ps[i] = H.Join(srv, 800 + i, "P" .. i)
		end
		for step = 1, 20 do
			for i, p in ipairs(ps) do
				H.Act(srv, p, "press_click", { count = i })
			end
			H.Advance(srv, 0.5)
		end
		for i, p in ipairs(ps) do
			T.check(H.Profile(srv, p).games.press.clicks >= i * 19, "Spieler " .. i .. " eigene Klicks")
			T.check(H.LastSync(srv, p) ~= nil, "Spieler " .. i .. " erhält Snapshots")
		end
		for _, p in ipairs(ps) do
			H.Leave(srv, p)
		end
		T.eq(#H.Errors(srv.env), 0, "keine Laufzeitfehler")
	end },
}
