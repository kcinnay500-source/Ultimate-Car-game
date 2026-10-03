-- B-017: Schlug GetNameFromUserIdAsync einmal fehl, blieb der Ersatztext „Spieler <id>“ bis zum Serverende im
-- Names-Cache. Jetzt wird nur ein echter Name dauerhaft gemerkt; Fehlschläge werden später erneut versucht – mit
-- wachsendem Abstand, damit dauerhaft fehlschlagende IDs nicht bei jedem Refresh das Budget belasten.
local function ordered(g)
	local MC = g:MiniShared("MiniConfig")
	local ds = g.env.services.DataStoreService.__data
	ds.ordered[MC.LeaderboardStoreName] = ds.ordered[MC.LeaderboardStoreName] or { data = {} }
	return ds.ordered[MC.LeaderboardStoreName].data
end

local function nameOf(view, value)
	for _, row in ipairs(view.rows) do
		if row.value == value then
			return row.name
		end
	end
	return nil
end

return {
	{ "Einmaliger Fehler: späterer Refresh zeigt den echten Namen; Dauerfehler wird nicht bei jedem Refresh abgefragt", function(T, H)
		local g = H.Garage({ level = 12 })
		local LB, PR = g:MiniServer("LeaderboardService"), g:MiniShared("PressRules")
		local store = ordered(g)
		store["1001"] = PR.EncodeScore(3e20)
		store["1002"] = PR.EncodeScore(2e20)
		store["1003"] = PR.EncodeScore(1e20)
		-- Namensdienst: 1002 fällt genau einmal aus, 1003 immer
		local calls = {}
		local pd = rawget(g.env.services.Players, "__data")
		pd.nameFromUserId = function(id)
			calls[id] = (calls[id] or 0) + 1
			if id == 1003 or (id == 1002 and calls[id] == 1) then
				error("HTTP 429")
			end
			return "Nutzer" .. id
		end
		local player = g:Join(77, { name = "Carla" })
		g:Advance(1)
		local ms = g:MiniState(player)
		local function view()
			LB.Refresh(true)
			local v = LB.View(ms)
			local out = {}
			for _, row in ipairs(v.rows) do
				out[#out + 1] = row.name
			end
			return v, out
		end
		local v, names = view()
		T.eq(v.available, true, "verfügbar")
		T.eq(calls[1002], 1, "Namensdienst gefragt (Test-Überschreibung greift)")
		T.eq(names[1], "Nutzer1001", "Platz 1: echter Name")
		T.eq(names[2], "Spieler 1002", "Platz 2: Ersatztext nach dem Fehler")
		T.eq(names[3], "Spieler 1003", "Platz 3: Ersatztext")
		-- kurz danach: kein neuer Versuch (Budget)
		g:Advance(60)
		v, names = view()
		T.eq(calls[1002], 1, "nach 60 s kein zweiter Versuch")
		T.eq(calls[1003], 1, "nach 60 s kein zweiter Versuch (Dauerfehler)")
		T.eq(names[2], "Spieler 1002", "weiter Ersatztext")
		-- nach 5 Minuten: erneuter Versuch -> echter Name
		g:Advance(300)
		v, names = view()
		T.eq(names[2], "Nutzer1002", "nach 5 Minuten: echter Name")
		T.eq(calls[1002], 2, "genau ein weiterer Versuch")
		T.eq(names[3], "Spieler 1003", "Dauerfehler: weiter Ersatztext")
		-- eine Stunde lang jede Minute ein Refresh: Erfolge nie wieder, Dauerfehler mit wachsendem Abstand
		for _ = 1, 60 do
			g:Advance(60)
			v, names = view()
		end
		T.eq(calls[1001], 1, "erfolgreicher Name: nie wieder abgefragt")
		T.eq(calls[1002], 2, "nach dem Erfolg nie wieder abgefragt")
		T.check(calls[1003] >= 3, "Dauerfehler wird weiter versucht (" .. calls[1003] .. ")")
		T.check(calls[1003] <= 6, "Dauerfehler: 62 Refreshes, höchstens 6 Abfragen (" .. calls[1003] .. ")")
		T.eq(names[3], "Spieler 1003", "Dauerfehler: Ersatztext bleibt")
		T.eq(names[1], "Nutzer1001", "Platz 1 unverändert")
		-- Dienst erholt sich: irgendwann erscheint der echte Name
		pd.nameFromUserId = nil
		g:Advance(2 * 3600)
		v, names = view()
		T.eq(names[3], "Nutzer1003", "nach Erholung des Dienstes: echter Name")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
