-- Mehrspieler: getrennte Zustände, Spieler B beeinflusst Spieler A nicht
local function snapshotOf(d)
	return {
		money = d.money, ups = d.games.press.upgrades.pu0, rebirths = d.games.press.rebirths,
		milestones = d.games.milestones.m_scrap_10k, projects = #d.games.tuning.projects, jobs = #d.jobs,
		offers = #d.offers, streak = d.games.parking.streak, daily = d.games.daily.claimed, diag = d.games.quiz.diagPoints,
		parts = d.games.parts, vehicle = d.games.scrapyard.vehicle,
	}
end

return {
	{ "Zwei Spieler: getrennte Zustände", function(T, H)
		local g = H.Garage()
		local a = g:Join(701, { name = "Alma" })
		local b = g:Join(702, { name = "Bodo" })
		g:Advance(1)
		local da, db = g:D(a), g:D(b)
		T.check(da ~= db and da.games ~= db.games, "eigene Profile")
		da.games.press.upgrades.pu1 = 5
		g:Advance(1)
		local before = snapshotOf(da)
		db.money = 1e7
		db.games.press.scrap = 1e9 -- reicht für das kleinste Umtauschpaket
		db.games.press.runScrap = 1e12
		db.games.press.lifetime = 1e9 -- über dem Ziel von m_scrap_10k
		local rid = 0
		local function actB(name, payload)
			rid += 1
			payload = payload or {}
			payload.rid = rid
			g:Act(b, name, payload)
		end
		actB("mini_press_click", { count = 20 })
		actB("mini_press_buy", { id = "pu0", level = 0 })
		actB("mini_press_exchange", { index = 1 })
		actB("mini_press_rebirth", { rebirths = 0 })
		actB("mini_milestone_claim", { id = "m_scrap_10k" })
		actB("mini_tuning_start", { id = "folie" })
		actB("mini_parking_new")
		actB("mini_quiz_new")
		actB("mini_scrapyard_buy")
		actB("mini_daily_claim")
		actB("mini_upgrade", { key = "tuningLevel", level = 1 })
		local after = snapshotOf(da)
		for k, v in pairs(before) do
			T.eq(after[k], v, "A unverändert: " .. k)
		end
		T.eq(db.games.press.rebirths, 1, "B hat eigenes Rebirth")
		T.eq(db.games.milestones.m_scrap_10k, true, "B hat eigenen Meilenstein")
		-- Snapshots gehen nur an den Besitzer
		local m = g:Mark()
		g:Act(b, "mini_sync", { rid = 99 })
		g:Advance(0.6)
		for _, snap in ipairs(g:Events(a, "mini", m)) do
			T.check(snap.press.rebirths == 0, "A sieht nur eigene Daten")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Bestenlistenwerte getrennt", function(T, H)
		local g = H.Garage()
		local MC, PR = g:MiniShared("MiniConfig"), g:MiniShared("PressRules")
		local a = g:Join(703, { name = "Carmen" })
		local b = g:Join(704, { name = "Dirk" })
		g:Advance(1)
		for _ = 1, 10 do
			g:Act(b, "mini_press_click", { count = 10 })
			g:Advance(0.5)
		end
		local la, lb = g:D(a).games.press.lifetime, g:D(b).games.press.lifetime
		T.check(lb > la, "B klickt, A nicht")
		g:Leave(a)
		g:Leave(b)
		g:Advance(1)
		local ordered = g:DataStoreMock().ordered[MC.LeaderboardStoreName].data
		T.check(ordered["703"] == nil or ordered["703"] < ordered["704"], "Werte je Spieler getrennt gespeichert")
		T.near(PR.DecodeScore(ordered["704"]), lb, lb * 1e-6 + 1, "B-Wert korrekt")
	end },

	{ "8 Spieler gleichzeitig: eigene Grundstücke, eigene Klicks, Snapshots", function(T, H)
		local g = H.Garage()
		local ps = {}
		for i = 1, 8 do
			ps[i] = g:Join(800 + i, { name = "P" .. i })
		end
		g:Advance(1)
		local plots = {}
		for i, p in ipairs(ps) do
			local plot = g:Plot(p)
			T.check(plot ~= nil, "Spieler " .. i .. " hat ein Grundstück")
			if plot then
				T.check(not plots[plot], "eigenes Grundstück " .. i)
				plots[plot] = true
			end
		end
		for _ = 1, 20 do
			for i, p in ipairs(ps) do
				g:Act(p, "mini_press_click", { count = i })
			end
			g:Advance(0.5)
		end
		for i, p in ipairs(ps) do
			T.check(g:D(p).games.press.clicks >= i * 19, "Spieler " .. i .. " eigene Klicks")
			T.check(g:MiniSnapshot(p) ~= nil, "Spieler " .. i .. " erhält Snapshots")
		end
		-- neunter Spieler: alle Grundstücke belegt (2.4.0)
		local ninth = g:Join(809)
		g:Advance(1)
		T.check(ninth.__data.kicked ~= nil or g:Plot(ninth) == nil, "neunter Spieler ohne Grundstück")
		T.eq(g:Mini().Sessions[ninth], nil, "keine Minispiel-Sitzung ohne Grundstück")
		for _, p in ipairs(ps) do
			g:Leave(p)
		end
		g:Advance(1)
		T.eq(next(g:Mini().Sessions), nil, "alle Minispiel-Sitzungen beendet")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
