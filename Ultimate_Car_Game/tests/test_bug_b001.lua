-- B-001: ow_collect im Dauertakt (alle 0,5 s, Serverzeit mit Nachkommastellen) darf nicht mehr auszahlen als die real
-- verstrichene Zeit hergibt. Vorher: collectedAt = floor(t) schenkte bei jedem Abholen den schon bezahlten Sekundenbruchteil.
local NOW = 1760000000
local HOUR = 3600

local function modules(H)
	local g = H.Garage({ noServer = true })
	return g, g:MiniShared("GameConfig"), g:MiniShared("OWRules")
end

local function profile(g, OWR)
	local d = g:Rules().NewData(NOW)
	d.level = 90
	d.money = 10 ^ 12
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	g:MiniShared("TycoonRules").ApplyDefault(d.games)
	OWR.ApplyDefault(d.games)
	return d
end

local function finish(OWR, d, typ, stage, t)
	for _ = OWR.StageOf(d, typ) + 1, stage do
		assert(OWR.Build(d, typ, t))
		t = OWR.Entry(d, typ).readyAt
		OWR.Settle(d, t)
	end
	return t
end

-- Baut typ auf stage aus und liefert (Profil, Startzeit des Ertrags)
local function ready(g, OWR, typ, stage)
	local d = profile(g, OWR)
	local t = finish(OWR, d, typ, stage, NOW)
	d.money = 0
	d.games.press.scrap = 0
	d.games.parts = 0
	return d, t
end

local function totals(OWR, d, typ)
	local e = OWR.Entry(d, typ)
	return { credits = d.money, scrap = d.games.press.scrap, parts = d.games.parts + e.partsCarry }
end

-- n Abholungen im Abstand step ab t0 + first; reload = true lädt das Gebäude vor jedem Abholen neu (Rejoin)
local function spam(g, OWR, typ, stage, n, first, step, reload)
	local d, t0 = ready(g, OWR, typ, stage)
	for i = 1, n do
		local t = t0 + first + (i - 1) * step
		if reload then
			d.games.ow = OWR.Load(d.games.ow, d, t)
		end
		OWR.Collect(d, typ, t)
	end
	return totals(OWR, d, typ)
end

local function once(g, OWR, typ, stage, dt)
	local d, t0 = ready(g, OWR, typ, stage)
	OWR.Collect(d, typ, t0 + dt)
	return totals(OWR, d, typ)
end

local EPS = 1e-6

return {
	{ "B-001: 240 Abholungen in 120 s bringen höchstens so viel wie einmal abholen (Autohaus, Schrottplatz)", function(T, H)
		local g, _, OWR = modules(H)
		for _, typ in ipairs({ "autohaus", "schrottplatz" }) do
			for _, reload in ipairs({ false, true }) do
				local label = typ .. (reload and " (mit Neuladen)" or "")
				-- Abholen bei x,49 und x,99 – genau die Abklingzeit von 0,5 s
				local many = spam(g, OWR, typ, 4, 240, 0.49, 0.5, reload)
				local single = once(g, OWR, typ, 4, 0.49 + 239 * 0.5)
				T.check(single.credits + single.scrap > 0, label .. ": einmal abholen bringt Ertrag")
				T.check(many.credits <= single.credits, label .. ": Credits " .. many.credits .. " ≤ " .. single.credits)
				T.check(many.scrap <= single.scrap, label .. ": Schrott " .. many.scrap .. " ≤ " .. single.scrap)
				T.check(many.parts <= single.parts + EPS, label .. ": Altteile " .. many.parts .. " ≤ " .. single.parts)
			end
		end
	end },

	{ "B-001: Altteile je Stunde – Dauertakt über eine Stunde ergibt nicht mehr Teile als die Zeit hergibt", function(T, H)
		local g, GC, OWR = modules(H)
		local perHour = GC.OW.Buildings.schrottplatz.Stages[4].partsPerHour
		-- 720 Abholungen alle 5,5 s (x,49 / x,99 wechseln sich ab)
		local many = spam(g, OWR, "schrottplatz", 4, 720, 0.49, 5.5, false)
		local span = 0.49 + 719 * 5.5
		local single = once(g, OWR, "schrottplatz", 4, span)
		T.check(many.parts <= single.parts + EPS, "Altteile " .. many.parts .. " ≤ " .. single.parts)
		T.check(many.parts <= perHour * span / HOUR + EPS, "Altteile ≤ Stundensatz × Zeit")
		T.check(many.scrap <= single.scrap, "Schrott " .. many.scrap .. " ≤ " .. single.scrap)
	end },

	{ "B-001: Paketbau (Produktion) – Dauertakt und Neuladen schenken kein Paket", function(T, H)
		local g, GC, OWR = modules(H)
		local st = GC.OW.Buildings.produktion.Stages[1]
		local period = st.partsEveryHours * HOUR
		for _, reload in ipairs({ false, true }) do
			local d, t0 = ready(g, OWR, "produktion", 1)
			local label = reload and " (mit Neuladen)" or ""
			-- im Halbsekundentakt über jede Paketgrenze hinweg
			for k = 1, 3 do
				for i = -4, 4 do
					local t = t0 + k * period + i * 0.5 - 0.01
					if reload then
						d.games.ow = OWR.Load(d.games.ow, d, t)
					end
					local a = OWR.Collect(d, "produktion", t)
					if i <= 0 then
						T.check(a == nil, "vor Ablauf von Paket " .. k .. " nichts" .. label)
					end
				end
				T.eq(d.games.parts, k * st.partsPerPack, "nach " .. k .. " Zeiträumen genau " .. k .. " Pakete" .. label)
			end
			T.check(OWR.Entry(d, "produktion").collectedAt >= t0 + 3 * period - EPS, "Zeitraum beginnt nicht vor dem dritten Paket" .. label)
		end
	end },

	{ "B-001: Laden rundet collectedAt nicht ab (kein geschenkter Sekundenbruchteil nach Rejoin)", function(T, H)
		local g, _, OWR = modules(H)
		local d, t0 = ready(g, OWR, "autohaus", 4)
		assert(OWR.Collect(d, "autohaus", t0 + 600.75))
		local loaded = OWR.Load(d.games.ow, d, t0 + 601)
		T.check(loaded.buildings.autohaus.collectedAt >= t0 + 600.75, "geladenes collectedAt nicht vor dem letzten Abholen")
		T.check(H.DeepEqual(OWR.Load(loaded, d, t0 + 601), loaded), "Load bleibt idempotent")
		T.check(g:MiniShared("MiniRules").IsClean(loaded), "ow bleibt sauber")
	end },
}
