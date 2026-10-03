-- Ausbaustufe 4, Meilenstein 4 (Team tycoon-rules): TycoonRules als reines Modul gegen die echte GameConfig.Tycoon,
-- ohne Server. Load idempotent/Müll, Rate/Behälter, Kauf- und Stufen-Sperren, Rebirth/Abbruch, Handel (Erhaltung
-- von Waren und Bargeld) und eine gierige Simulation: ein aufmerksamer Spieler erreicht Stufe 5 komplett in
-- 4 h .. 6,5 h (Ziel ≈ 5 h) für jeden Gebäudetyp.
local NOW = 1760000000

local function modules(H)
	local g = H.Garage({ noServer = true })
	return g, g:MiniShared("GameConfig"), g:MiniShared("TycoonRules")
end

-- Profil wie R.NewData, dazu games.tycoon (bis MiniRules.DefaultGames TycoonRules.ApplyDefault aufruft)
local function profile(g, TR, level)
	local d = g:Rules().NewData(NOW)
	d.level = level or 1
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	TR.ApplyDefault(d.games)
	return d
end

-- Läuft einen Durchlauf mit gierigem Spieler: alle 15 s sammeln, dann das teuerste bezahlbare Angebot der Stufe
-- kaufen (Produzent/Tempo zuerst). Rückgabe: Sekunden bis Stufe 5 komplett (oder nil bei Abbruch).
local function simulate(TR, GC, d, typ)
	local run = TR.NewRun(d, typ, NOW)
	local t = NOW
	local limit = NOW + 12 * 3600
	local step = 15
	while t < limit do
		t += step
		-- der Server tickt alle 0,5 s; hier in 0,5-s-Schritten, damit MaxTickSeconds nicht greift
		for _ = 1, step * 2 do
			TR.Tick(run, run.lastTick + 0.5)
		end
		TR.Collect(run)
		local bought = true
		while bought do
			bought = false
			local best, bestCost = nil, -1
			for _, o in ipairs(TR.Offers(run)) do
				if o.ok and o.cost > bestCost then
					best, bestCost = o.id, o.cost
				end
			end
			if best then
				TR.Buy(run, best)
				bought = true
			end
		end
		if run.stage == GC.Tycoon.MaxStage and TR.StageComplete(run, run.stage) then
			return t - NOW, run
		end
	end
	return nil, run
end

return {
	{ "GameConfig.Tycoon: feste IDs, 8 Slots wie worldgen, Stufenpreise und Warenbedarf, Nachschlagetabellen", function(T, H)
		local g, GC, TR = modules(H)
		local TY = GC.Tycoon
		local MiniRules = g:MiniShared("MiniRules")
		T.check(MiniRules.IsClean(TY), "Tycoon-Konfiguration ohne NaN/Instanzen")
		T.eq(#TY.Types, 4, "vier Gebäudetypen")
		T.eq(#TY.Slots, 8, "acht Grundstücke")
		local expect = { { -45, 760, 0 }, { 45, 760, 0 }, { -45, 940, 180 }, { 45, 940, 180 }, { -135, 760, 0 }, { 135, 760, 0 }, { -135, 940, 180 }, { 135, 940, 180 } }
		for i, sl in ipairs(TY.Slots) do
			T.eq(sl.slot, i, "Slot-Nummer " .. i)
			T.check(sl.x == expect[i][1] and sl.z == expect[i][2] and sl.rot == expect[i][3], "Slot-Pivot " .. i)
			T.check(TY.SlotByNumber[i] == sl, "SlotByNumber " .. i)
		end
		T.eq(TY.TickSeconds, 0.5, "TickSeconds")
		T.eq(TY.TradeTTL, 120, "TradeTTL")
		T.eq(TY.TradeMaxOpen, 5, "TradeMaxOpen")
		T.eq(TY.Rebirth.boostPct, 15, "Rebirth-Boost")
		T.eq(TY.Rebirth.capPct, 150, "Rebirth-Deckel")
		T.eq(TY.Rebirth.requiresStage, 5, "Rebirth ab Stufe 5")
		T.check(TY.Rebirth.requiresAllUpgrades == true, "Rebirth mit allen Upgrades")
		T.eq(TY.XP.run, GC.XP.TycoonRun, "XP je Durchlauf aus GameConfig.XP")
		T.near(TY.Bonus.werkstatt.step, 0.02, 1e-9, "Bonus werkstatt")
		T.near(TY.Bonus.autohaus.step, 0.015, 1e-9, "Bonus autohaus")
		T.near(TY.Bonus.produktion.step, 0.03, 1e-9, "Bonus produktion")
		T.near(TY.Bonus.schrottplatz.step, 0.03, 1e-9, "Bonus schrottplatz")
		for _, item in ipairs(TY.ItemList) do
			T.check(type(TY.Items[item]) == "table" and #TY.Items[item].name > 0, "Ware " .. item)
		end
		for _, typ in ipairs(TY.Types) do
			local b = TY.Buildings[typ]
			T.check(b and b.typ == typ and #b.name > 0 and #b.desc > 0, "Gebäude " .. typ)
			T.check(b.baseRate > 0, "Grundrate " .. typ)
			T.eq(#b.Stages, 5, "fünf Stufen " .. typ)
			T.eq(b.Stages[1].price, 0, "Stufe 1 kostenlos " .. typ)
			local lastPrice = 0
			for s, st in ipairs(b.Stages) do
				T.eq(#st.Upgrades, 4, "vier Upgrades " .. typ .. " Stufe " .. s)
				T.check(st.capacity > 0, "Behälter " .. typ .. s)
				if s > 1 then
					T.check(st.price > lastPrice, "Stufenpreis wächst " .. typ .. s)
					lastPrice = st.price
					T.check(TY.StageById[typ .. "_stage" .. s] ~= nil and TY.StageById[typ .. "_stage" .. s].stage == s, "StageById " .. typ .. s)
					T.eq(b.Stages[s - 1].stageId, typ .. "_stage" .. s, "stageId der Vorstufe " .. typ .. s)
				else
					T.check(TY.StageById[typ .. "_stage1"] == nil, "kein Pad für Stufe 1")
				end
				T.check((s >= 3) == (next(st.items) ~= nil), "Warenbedarf ab Stufe 3 " .. typ .. s)
				for k, u in ipairs(st.Upgrades) do
					T.eq(u.id, typ .. "_s" .. s .. "_u" .. k, "Upgrade-Id")
					T.eq(u.kind, TY.UpgradeKinds[k], "Upgrade-Art " .. u.id)
					T.check(#u.name > 0 and #u.desc > 0 and u.cost > 0 and u.cost == math.floor(u.cost), "Name/Text/Kosten " .. u.id)
					T.check(TY.UpgradeById[u.id] == u, "UpgradeById " .. u.id)
					if u.kind == "producer" then
						T.check(u.rate > 0, "Produzentenrate " .. u.id)
					elseif u.kind == "tempo" then
						T.check(u.mult > 1, "Tempo " .. u.id)
					elseif u.kind == "lager" then
						T.check(u.cap > 0 and TY.Items[u.item] and u.perMin > 0, "Lager " .. u.id)
					else
						T.check(u.bonus > 0, "Deko " .. u.id)
					end
					T.check(u.name:find("rbxassetid", 1, true) == nil, "keine Asset-IDs")
				end
			end
			T.eq(b.Stages[5].stageId, nil, "keine Stufe 6")
		end
	end },

	{ "Default/Load: idempotent, Müll -> Standard, Whitelist der Upgrade-Ids, Lager und Behälter gedeckelt", function(T, H)
		local g, GC, TR = modules(H)
		local def = TR.Default()
		T.check(def.run == false and def.rebirths == 0, "Standard ohne Durchlauf")
		for _, typ in ipairs(GC.Tycoon.Types) do
			T.eq(def.runsDone[typ], 0, "runsDone " .. typ)
		end
		local ok, diff = H.DeepEqual(TR.Load(nil), def)
		T.check(ok, "Load(nil) = Default " .. tostring(diff))
		for _, garbage in ipairs({ 5, "x", { run = "nein" }, { run = { building = "burg" } }, { runsDone = "x", rebirths = 0 / 0 } }) do
			local t = TR.Load(garbage, nil, NOW)
			T.check(t.run == false and t.rebirths == 0 and t.runsDone.werkstatt == 0, "Müll -> Standard")
		end
		local raw = {
			runsDone = { werkstatt = 3.7, autohaus = -2, produktion = 0 / 0, fremd = 9 },
			rebirths = 2.9,
			run = {
				building = "produktion", stage = 99, cash = -5, container = 1e30,
				upgrades = { produktion_s1_u1 = 1, produktion_s1_u2 = 0, werkstatt_s1_u1 = 1, produktion_s5_u1 = 1, [7] = 1, produktion_s1_u3 = 3 },
				startedAt = NOW + 999999, lastTick = -1, produced = 0 / 0, rebirthBoost = 99,
				storage = { bauteile = 5000, lack = 2.5, gold = 4, reifen = -1 },
				itemAcc = { bauteile = 0.5, lack = 3 },
				fremd = true,
			},
		}
		local t = TR.Load(raw, nil, NOW)
		T.eq(t.runsDone.werkstatt, 3, "runsDone abgerundet")
		T.eq(t.runsDone.autohaus, 0, "runsDone negativ -> 0")
		T.eq(t.runsDone.produktion, 0, "runsDone NaN -> 0")
		T.check(t.runsDone.fremd == nil, "unbekannter Typ fällt weg")
		T.eq(t.rebirths, 2, "rebirths abgerundet")
		local run = t.run
		T.check(type(run) == "table", "Durchlauf geladen")
		T.eq(run.building, "produktion", "Gebäude")
		T.eq(run.stage, 5, "Stufe gedeckelt")
		T.eq(run.cash, 0, "Bargeld negativ -> 0")
		T.eq(run.container, TR.Capacity(run), "Behälter höchstens Capacity")
		T.check(run.upgrades.produktion_s1_u1 == 1 and run.upgrades.produktion_s5_u1 == 1, "gültige Upgrades bleiben")
		T.check(run.upgrades.produktion_s1_u2 == nil and run.upgrades.werkstatt_s1_u1 == nil and run.upgrades[7] == nil, "0/fremdes Gebäude/Zahl-Schlüssel weg")
		T.eq(run.upgrades.produktion_s1_u3, 1, "Stufe eines Upgrades ist immer 1")
		T.eq(run.storage.bauteile, GC.Tycoon.ItemCap, "Lager gedeckelt")
		T.eq(run.storage.lack, 2, "Lager ganzzahlig")
		T.check(run.storage.gold == nil and run.storage.reifen == nil, "unbekannte/negative Waren weg")
		T.eq(run.itemAcc.bauteile, 0.5, "Rest behalten")
		T.check(run.itemAcc.lack == nil, "Rest >= 1 weg")
		T.eq(run.startedAt, NOW, "startedAt in der Zukunft -> now")
		T.eq(run.lastTick, 0, "lastTick negativ -> 0")
		T.eq(run.produced, 0, "produced NaN -> 0")
		T.near(run.rebirthBoost, 1.5 + GC.Prestige.RebirthBonus, 1e-9, "rebirthBoost gedeckelt")
		T.check(run.fremd == nil, "unbekannte Felder weg")
		-- Upgrade über der aktuellen Stufe fällt weg
		local t2 = TR.Load({ run = { building = "werkstatt", stage = 2, upgrades = { werkstatt_s3_u1 = 1, werkstatt_s2_u1 = 1 } } }, nil, NOW)
		T.check(t2.run.upgrades.werkstatt_s3_u1 == nil and t2.run.upgrades.werkstatt_s2_u1 == 1, "Upgrade über der Stufe weg")
		-- idempotent
		local again = TR.Load(H.Copy(t), nil, NOW)
		local ok2, diff2 = H.DeepEqual(again, t)
		T.check(ok2, "Load idempotent " .. tostring(diff2))
		-- ApplyDefault/ApplyLoad
		local gm = {}
		TR.ApplyDefault(gm)
		T.check(type(gm.tycoon) == "table" and gm.tycoon.run == false, "ApplyDefault")
		TR.ApplyLoad(gm, { tycoon = { rebirths = 4 } }, nil, NOW)
		T.eq(gm.tycoon.rebirths, 4, "ApplyLoad")
		-- Runde mit JSON-artigen Zeichenketten-Schlüsseln im Lager bleibt sauber
		local t3 = TR.Load({ run = { building = "autohaus", storage = { ["lack"] = 3 } } }, nil, NOW)
		T.eq(t3.run.storage.lack, 3, "Lager geladen")
	end },

	{ "NewRun, Rate, Capacity, Tick (Deckel, Waren, Offline zählt nicht), Collect", function(T, H)
		local g, GC, TR = modules(H)
		local TY = GC.Tycoon
		local d = profile(g, TR)
		T.check(TR.NewRun(d, "burg", NOW) == nil, "unbekannter Typ")
		local run = TR.NewRun(d, "werkstatt", NOW)
		T.check(run ~= nil and d.games.tycoon.run == run, "Durchlauf angelegt")
		T.check(TR.NewRun(d, "autohaus", NOW) == nil, "kein zweiter Durchlauf")
		T.eq(run.stage, 1, "Stufe 1")
		T.eq(run.cash, TY.StartCash, "StartCash")
		T.eq(run.rebirthBoost, 0, "kein Boost")
		local b = TY.Buildings.werkstatt
		T.near(TR.Rate(run), b.baseRate, 1e-9, "Grundrate")
		T.eq(TR.Capacity(run), b.Stages[1].capacity, "Grundbehälter")
		-- Rate-Mathematik: Produzent + Tempo + Deko + Rebirth
		local u = b.Stages[1].Upgrades
		run.upgrades[u[1].id] = 1
		T.near(TR.Rate(run), b.baseRate + u[1].rate, 1e-9, "Produzent addiert")
		run.upgrades[u[2].id] = 1
		T.near(TR.Rate(run), (b.baseRate + u[1].rate) * u[2].mult, 1e-9, "Tempo multipliziert")
		run.upgrades[u[4].id] = 1
		T.near(TR.Rate(run), (b.baseRate + u[1].rate) * u[2].mult * (1 + u[4].bonus), 1e-9, "Deko addiert Bonus")
		run.rebirthBoost = 0.3
		T.near(TR.Rate(run), (b.baseRate + u[1].rate) * u[2].mult * (1 + u[4].bonus) * 1.3, 1e-9, "Rebirth-Boost")
		run.upgrades[u[3].id] = 1
		T.eq(TR.Capacity(run), b.Stages[1].capacity + u[3].cap, "Lager vergrößert Behälter")
		T.near(TR.ItemRates(run)[u[3].item], u[3].perMin, 1e-9, "Warenausstoß")
		-- Tick
		local rate = TR.Rate(run)
		T.eq(TR.Tick(run, NOW), 0, "Tick ohne Zeit")
		local gained = TR.Tick(run, NOW + 0.5)
		T.near(gained, rate * 0.5, 1e-6, "halbe Sekunde")
		T.near(run.container, rate * 0.5, 1e-6, "Behälter")
		T.near(run.produced, rate * 0.5, 1e-6, "produced")
		T.eq(run.lastTick, NOW + 0.5, "lastTick")
		-- Offline zählt nicht: großer Sprung -> höchstens MaxTickSeconds
		local before = run.container
		local big = TR.Tick(run, NOW + 0.5 + 3600)
		T.near(big, rate * TY.MaxTickSeconds, 1e-6, "höchstens MaxTickSeconds angerechnet")
		T.eq(run.lastTick, NOW + 0.5 + 3600, "lastTick nach Sprung")
		-- Zeit rückwärts -> nichts
		T.eq(TR.Tick(run, NOW), 0, "rückwärts nichts")
		-- Deckel Behälter
		local cap = TR.Capacity(run)
		local tNow = run.lastTick
		local total = 0
		for _ = 1, 100000 do
			tNow += 0.5
			total += TR.Tick(run, tNow)
			if run.container >= cap then
				break
			end
		end
		T.eq(run.container, cap, "Behälter voll")
		T.eq(TR.Tick(run, tNow + 0.5), 0, "voll: nichts mehr")
		-- Waren: perMin/60 je Sekunde, ganzzahlig im Lager
		local item = u[3].item
		T.check((run.storage[item] or 0) >= 1, "Ware erzeugt")
		T.check(run.itemAcc[item] >= 0 and run.itemAcc[item] < 1, "Rest 0..1")
		-- Collect
		run.cash = 0
		local amount = TR.Collect(run)
		T.eq(amount, math.floor(cap), "eingesammelt")
		T.eq(run.cash, amount, "Bargeld")
		T.check(run.container < 1, "Behälter leer (Rest < 1)")
		T.eq(TR.Collect(run), 0, "nichts mehr zu sammeln")
		-- NumberCap
		run.cash = g:Config().NumberCap
		run.container = 100
		T.eq(TR.Collect(run), 0, "Collect gedeckelt auf NumberCap")
		T.eq(run.cash, g:Config().NumberCap, "cash = NumberCap")
		T.eq(TR.Rate({}), 0, "Rate ohne Gebäude")
		T.eq(TR.Tick(nil, NOW), 0, "Tick ohne Durchlauf")
		T.eq(TR.Collect(nil), 0, "Collect ohne Durchlauf")
		-- Lagerdeckel
		run.storage[item] = TY.ItemCap
		run.itemAcc[item] = 0.99
		TR.Tick(run, run.lastTick + 5)
		T.eq(run.storage[item], TY.ItemCap, "Lager gedeckelt")
	end },

	{ "CanBuy/Buy: nur aktuelle Stufe, nicht doppelt, Bargeld, Stufen-Pad nur komplett + Waren; Offers", function(T, H)
		local g, GC, TR = modules(H)
		local TY = GC.Tycoon
		local d = profile(g, TR)
		local run = TR.NewRun(d, "autohaus", NOW)
		local b = TY.Buildings.autohaus
		local u1 = b.Stages[1].Upgrades[1]
		local ok, reason, cost = TR.CanBuy(run, u1.id)
		T.check(not ok and reason == "cash" and cost == u1.cost, "zu wenig Bargeld " .. reason)
		T.check(select(2, TR.CanBuy(run, 42)) == "unknown", "keine Zeichenkette")
		T.check(select(2, TR.CanBuy(run, "quatsch")) == "unknown", "unbekannte Id")
		T.check(select(2, TR.CanBuy(run, "werkstatt_s1_u1")) == "wrong_building", "fremdes Gebäude")
		T.check(select(2, TR.CanBuy(run, "autohaus_s2_u1")) == "wrong_stage", "falsche Stufe")
		T.check(select(2, TR.CanBuy(run, "autohaus_stage3")) == "wrong_stage", "Stufe überspringen")
		T.check(select(2, TR.CanBuy(run, "werkstatt_stage2")) == "wrong_building", "fremdes Stufen-Pad")
		T.check(select(2, TR.CanBuy(nil, u1.id)) == "no_run", "ohne Durchlauf")
		run.cash = 1e9
		T.check(select(2, TR.CanBuy(run, "autohaus_stage2")) == "stage_incomplete", "Stufe 2 erst mit allen Upgrades")
		ok = TR.Buy(run, u1.id)
		T.check(ok and run.upgrades[u1.id] == 1 and run.cash == 1e9 - u1.cost, "gekauft und bezahlt")
		T.check(select(2, TR.CanBuy(run, u1.id)) == "owned", "nicht doppelt")
		local ok2, reason2 = TR.Buy(run, u1.id)
		T.check(not ok2 and reason2 == "owned" and run.cash == 1e9 - u1.cost, "Doppelkauf kostet nichts")
		for k = 2, 4 do
			T.check(TR.Buy(run, b.Stages[1].Upgrades[k].id), "Upgrade " .. k)
		end
		T.check(TR.StageComplete(run, 1), "Stufe 1 komplett")
		local offers = TR.Offers(run)
		T.eq(#offers, 1, "nur noch das Stufen-Pad im Angebot")
		T.check(offers[1].id == "autohaus_stage2" and offers[1].ok and offers[1].cost == b.Stages[2].price, "Stufen-Pad kaufbar")
		local cashBefore = run.cash
		T.check(TR.Buy(run, "autohaus_stage2"), "Stufe 2 gekauft")
		T.eq(run.stage, 2, "Stufe 2")
		T.eq(run.cash, cashBefore - b.Stages[2].price, "Stufenpreis bezahlt")
		T.eq(#TR.Offers(run), 5, "vier Upgrades + Pad")
		T.check(select(2, TR.CanBuy(run, u1.id)) == "wrong_stage", "Stufe-1-Upgrade nicht mehr kaufbar")
		-- Stufe 3 braucht Waren
		for k = 1, 4 do
			T.check(TR.Buy(run, b.Stages[2].Upgrades[k].id), "Stufe-2-Upgrade " .. k)
		end
		run.storage = {}
		local ok3, reason3 = TR.CanBuy(run, "autohaus_stage3")
		T.check(not ok3 and reason3 == "items", "Waren fehlen")
		local missing = TR.MissingItems(run, 3)
		T.check(next(missing) ~= nil, "MissingItems gefüllt")
		for item, need in pairs(b.Stages[3].items) do
			T.eq(missing[item], need, "fehlt " .. item)
			run.storage[item] = need + 2
		end
		T.check(next(TR.MissingItems(run, 3)) == nil, "nichts fehlt mehr")
		T.check(TR.Buy(run, "autohaus_stage3"), "Stufe 3 gekauft")
		for item in pairs(b.Stages[3].items) do
			T.eq(run.storage[item], 2, "Waren verbraucht " .. item)
		end
		-- Waren genau aufgebraucht -> Schlüssel weg
		for k = 1, 4 do
			TR.Buy(run, b.Stages[3].Upgrades[k].id)
		end
		for item, need in pairs(b.Stages[4].items) do
			run.storage[item] = need
		end
		T.check(TR.Buy(run, "autohaus_stage4"), "Stufe 4 gekauft")
		for item in pairs(b.Stages[4].items) do
			T.check(run.storage[item] == nil, "Lager leer " .. item)
		end
		T.check(select(2, TR.CanBuy(run, "autohaus_stage3")) == "wrong_stage", "zurück geht nicht")
	end },

	{ "Rebirth: erst Stufe 5 komplett; zählt runsDone/rebirths, Boost mit Deckel und Prestige; Abandon zählt nichts", function(T, H)
		local g, GC, TR = modules(H)
		local TY = GC.Tycoon
		local d = profile(g, TR)
		T.check(not TR.Rebirth(d, NOW), "ohne Durchlauf kein Rebirth")
		T.check(not TR.Abandon(d), "ohne Durchlauf kein Abbruch")
		local run = TR.NewRun(d, "schrottplatz", NOW)
		local ok, reason = TR.CanRebirth(run)
		T.check(not ok and reason == "stage", "Stufe zu klein")
		run.stage = 5
		ok, reason = TR.CanRebirth(run)
		T.check(not ok and reason == "upgrades", "Upgrades fehlen")
		for _, u in ipairs(TY.Buildings.schrottplatz.Stages[5].Upgrades) do
			run.upgrades[u.id] = 1
		end
		run.cash = 12345
		T.check(TR.CanRebirth(run), "Rebirth möglich")
		local ok2, _, typ = TR.Rebirth(d, NOW)
		T.check(ok2 and typ == "schrottplatz", "Rebirth")
		local t = d.games.tycoon
		T.eq(t.runsDone.schrottplatz, 1, "runsDone")
		T.eq(t.rebirths, 1, "rebirths")
		T.check(t.run == false, "Durchlauf weg")
		T.near(TR.BonusFor(d, "schrottplatz"), 0.03, 1e-9, "Bonus nach einem Durchlauf")
		T.eq(TR.BonusFor(d, "werkstatt"), 0, "kein Bonus ohne Durchlauf")
		T.eq(TR.BonusFor(d, "burg"), 0, "unbekannter Typ")
		t.runsDone.schrottplatz = 9
		T.near(TR.BonusFor(d, "schrottplatz"), 0.15, 1e-9, "Bonus gedeckelt bei 5 Durchläufen")
		T.near(TR.BoostFor(d), 0.15, 1e-9, "Boost nach einem Rebirth")
		local run2 = TR.NewRun(d, "werkstatt", NOW)
		T.near(run2.rebirthBoost, 0.15, 1e-9, "neuer Durchlauf mit Boost")
		T.near(TR.Rate(run2), TY.Buildings.werkstatt.baseRate * 1.15, 1e-9, "Boost wirkt auf die Rate")
		-- Abbruch zählt nichts
		T.check(TR.Abandon(d), "Abbruch")
		T.check(t.run == false and t.rebirths == 1 and t.runsDone.werkstatt == 0, "Abbruch zählt nichts")
		-- Deckel 150 %
		t.rebirths = 20
		T.near(TR.BoostFor(d), 1.5, 1e-9, "Boost-Deckel")
		-- Prestige-Rebirth-Bonus ab Rang 3
		local PR = g:MiniShared("PrestigeRules")
		d.level = PR.Threshold(3)
		T.near(TR.BoostFor(d), 1.5 + GC.Prestige.RebirthBonus, 1e-9, "Prestige-Rebirth-Bonus")
		-- Summary
		TR.NewRun(d, "produktion", NOW)
		local s = TR.Summary(d)
		T.check(type(s.run) == "table" and s.run.building == "produktion" and s.run.stage == 1, "Summary run")
		T.eq(s.rebirths, 20, "Summary rebirths")
		T.eq(s.runsDone.schrottplatz, 9, "Summary runsDone")
		T.near(s.bonus.schrottplatz.pct, 15, 1e-9, "Summary bonus pct")
		T.eq(#s.run.offers, 5, "Summary offers")
		T.check(s.run.canRebirth == false and s.run.rebirthReason == "stage", "Summary rebirth")
		T.check(g:MiniShared("MiniRules").IsClean(s), "Summary sauber")
		T.eq(TR.XPForRun(), GC.XP.TycoonRun, "XP je Durchlauf")
		local s0 = TR.Summary(profile(g, TR))
		T.check(s0.run == false and s0.boost == 0, "Summary ohne Durchlauf")
	end },

	{ "Handel: TradeValid, ApplyTrade in einem Schritt, Erhaltung von Waren und Bargeld, Deckel, nie Credits", function(T, H)
		local g, GC, TR = modules(H)
		local TY = GC.Tycoon
		local d1, d2 = profile(g, TR), profile(g, TR)
		local seller = TR.NewRun(d1, "werkstatt", NOW)
		local buyer = TR.NewRun(d2, "autohaus", NOW)
		seller.storage.bauteile = 20
		seller.cash = 100
		buyer.cash = 500
		local moneyBefore = d1.money + d2.money
		T.check(select(2, TR.TradeValid(seller, "gold", 1, 10)) == "item", "unbekannte Ware")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 0, 10)) == "qty", "qty 0")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 1.5, 10)) == "qty", "qty gebrochen")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 1000, 10)) == "qty", "qty zu groß")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 1, 0)) == "price", "Preis 0")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 1, 0 / 0)) == "price", "Preis NaN")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 1, 2.5)) == "price", "Preis gebrochen")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 1, 1e12)) == "price", "Preis über TradeMaxPrice")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 1, TY.TradeMaxPrice + 1)) == "price", "Preis TradeMaxPrice + 1")
		T.check(TR.TradeValid(seller, "bauteile", 1, TY.TradeMaxPrice), "Preis = TradeMaxPrice erlaubt")
		T.check(type(TY.TradeMaxPrice) == "number" and TY.TradeMaxPrice >= 1e6 and TY.TradeMaxPrice < 1e12, "TradeMaxPrice in GameConfig.Tycoon")
		T.check(select(2, TR.TradeValid(seller, "bauteile", 21, 10)) == "storage", "Lager reicht nicht")
		T.check(select(2, TR.TradeValid(seller, "reifen", 1, 10)) == "storage", "keine Reifen")
		T.check(select(2, TR.TradeValid(nil, "bauteile", 1, 10)) == "no_run", "ohne Durchlauf")
		T.check(TR.TradeValid(seller, "bauteile", 20, 10), "gültig")
		-- Käufer ohne Bargeld: nichts passiert
		local ok, reason = TR.ApplyTrade(seller, buyer, "bauteile", 5, 600)
		T.check(not ok and reason == "cash", "Käufer zu arm")
		T.check(seller.storage.bauteile == 20 and buyer.cash == 500 and seller.cash == 100 and buyer.storage.bauteile == nil, "nichts übergeben")
		T.check(select(2, TR.ApplyTrade(seller, seller, "bauteile", 1, 1)) == "same", "nicht mit sich selbst")
		T.check(select(2, TR.ApplyTrade(seller, nil, "bauteile", 1, 1)) == "no_run", "Käufer ohne Durchlauf")
		-- Übergabe
		ok = TR.ApplyTrade(seller, buyer, "bauteile", 5, 300)
		T.check(ok, "Handel")
		T.eq(seller.storage.bauteile, 15, "Verkäufer-Lager")
		T.eq(buyer.storage.bauteile, 5, "Käufer-Lager")
		T.eq(seller.cash, 400, "Verkäufer-Bargeld")
		T.eq(buyer.cash, 200, "Käufer-Bargeld")
		T.eq(seller.storage.bauteile + buyer.storage.bauteile, 20, "Waren erhalten")
		T.eq(seller.cash + buyer.cash, 600, "Bargeld erhalten")
		T.eq(d1.money + d2.money, moneyBefore, "Credits unberührt")
		-- Rest verkaufen -> Schlüssel weg
		T.check(TR.ApplyTrade(seller, buyer, "bauteile", 15, 1), "Rest verkauft")
		T.check(seller.storage.bauteile == nil and buyer.storage.bauteile == 20, "Lager leer / voll")
		-- Lagerdeckel des Käufers
		buyer.storage.bauteile = TY.ItemCap - 1
		seller.storage.bauteile = 5
		T.check(select(2, TR.ApplyTrade(seller, buyer, "bauteile", 2, 1)) == "full", "Käufer-Lager voll")
		T.check(seller.storage.bauteile == 5 and buyer.storage.bauteile == TY.ItemCap - 1, "nichts übergeben (voll)")
		-- viele Zufallshandel: Summen bleiben
		seller.storage = { bauteile = 300, reifen = 100 }
		buyer.storage = { bauteile = 50 }
		seller.cash, buyer.cash = 1000, 5000
		local items0 = 350 + 100
		local cash0 = 6000
		local rng = Random.new(7)
		for i = 1, 200 do
			local a, b = seller, buyer
			if i % 2 == 0 then
				a, b = buyer, seller
			end
			local item = rng:NextInteger(1, 2) == 1 and "bauteile" or "reifen"
			TR.ApplyTrade(a, b, item, rng:NextInteger(1, 30), rng:NextInteger(1, 400))
		end
		local itemsSum = (seller.storage.bauteile or 0) + (seller.storage.reifen or 0) + (buyer.storage.bauteile or 0) + (buyer.storage.reifen or 0)
		T.eq(itemsSum, items0, "Waren-Summe nach 200 Handeln")
		T.eq(seller.cash + buyer.cash, cash0, "Bargeld-Summe nach 200 Handeln")
		T.check(seller.cash >= 0 and buyer.cash >= 0, "nie negativ")
	end },

	{ "Stufen-Sperre hat einen eigenen Schalter (StageRequiresAllUpgrades), unabhängig von Rebirth.requiresAllUpgrades; ClaimStageXP je Stufe einmal", function(T, H)
		local g, GC, TR = modules(H)
		local TY = GC.Tycoon
		local d = profile(g, TR)
		local run = TR.NewRun(d, "werkstatt", NOW)
		run.cash = 1e9
		T.eq(TY.StageRequiresAllUpgrades, true, "StageRequiresAllUpgrades = true")
		local ok, reason = TR.CanBuy(run, "werkstatt_stage2")
		T.check(not ok and reason == "stage_incomplete", "Stufen-Pad ohne Upgrades gesperrt")
		-- Rebirth-Schalter aus: die Stufen-Sperre bleibt
		local saved = TY.Rebirth.requiresAllUpgrades
		TY.Rebirth.requiresAllUpgrades = false
		ok, reason = TR.CanBuy(run, "werkstatt_stage2")
		T.check(not ok and reason == "stage_incomplete", "Rebirth.requiresAllUpgrades = false ändert die Stufen-Sperre nicht")
		run.stage = 5
		T.check(TR.CanRebirth(run), "Rebirth ohne Upgrades nur über den Rebirth-Schalter")
		TY.Rebirth.requiresAllUpgrades = saved
		T.check(not TR.CanRebirth(run), "Rebirth-Schalter wieder an")
		run.stage = 1
		-- eigener Schalter aus: Stufen-Pad frei (nur Waren/Bargeld)
		TY.StageRequiresAllUpgrades = false
		ok = TR.CanBuy(run, "werkstatt_stage2")
		T.check(ok, "StageRequiresAllUpgrades = false: Stufen-Pad frei")
		TY.StageRequiresAllUpgrades = true
		-- ClaimStageXP: je Stufe einmal seit dem letzten Rebirth
		T.eq(d.games.tycoon.xpStage, 0, "xpStage 0 zu Beginn")
		T.eq(TR.ClaimStageXP(d), 0, "Stufe 1: keine Stufen-XP")
		run.stage = 2
		T.eq(TR.ClaimStageXP(d), TR.XPForStage(), "Stufe 2: XP")
		T.eq(TR.ClaimStageXP(d), 0, "Stufe 2 nicht doppelt")
		T.check(TR.Abandon(d), "Abbruch")
		T.eq(d.games.tycoon.xpStage, 2, "Abbruch behält xpStage")
		run = TR.NewRun(d, "autohaus", NOW)
		run.stage = 2
		T.eq(TR.ClaimStageXP(d), 0, "nach Abbruch+Neustart keine XP für Stufe 2")
		run.stage = 3
		T.eq(TR.ClaimStageXP(d), TR.XPForStage(), "Stufe 3: XP")
		run.stage = 5
		for _, u in ipairs(TY.Buildings.autohaus.Stages[5].Upgrades) do
			run.upgrades[u.id] = 1
		end
		T.check(TR.Rebirth(d, NOW), "Rebirth")
		T.eq(d.games.tycoon.xpStage, 0, "Rebirth setzt xpStage zurück")
		T.eq(TR.Load({ xpStage = -3 }, d, NOW).xpStage, 0, "Load: negativ -> 0")
		T.eq(TR.Load({ xpStage = 3.7 }, d, NOW).xpStage, 3, "Load: ganzzahlig")
	end },

	{ "Vorlagen in der Fixture (ServerStorage.TycoonTemplates): je Stufe genau die Pads aus GameConfig (Ids, Namen, TycoonKind), jede Id genau einmal, Hidden mit Producer_1..4", function(T, H)
		local g, GC = modules(H)
		local TY = GC.Tycoon
		local root = g:Find("ServerStorage.TycoonTemplates")
		T.check(root ~= nil, "ServerStorage.TycoonTemplates in der Fixture")
		if not root then
			return
		end
		local seen = {}
		for _, typ in ipairs(TY.Types) do
			local folder = root:FindFirstChild(typ)
			T.check(folder ~= nil, "Ordner " .. typ)
			for s = 1, TY.MaxStage do
				local st = TY.Buildings[typ].Stages[s]
				local m = folder and folder:FindFirstChild("Stage_" .. s)
				T.check(m ~= nil and m.PrimaryPart ~= nil and m.PrimaryPart.Name == "Root", typ .. " Stage_" .. s .. " mit Root")
				if m then
					local expected = {}
					for _, u in ipairs(st.Upgrades) do
						expected[u.id] = u
					end
					if st.stageId then
						expected[st.stageId] = { name = "Stufe " .. (s + 1), stage = true }
					end
					local found = {}
					for _, x in ipairs(m:GetDescendants()) do
						local id = x:GetAttribute("TycoonButton")
						if type(id) == "string" then
							T.check(found[id] == nil, typ .. " Stage_" .. s .. ": Pad " .. id .. " nur einmal")
							found[id] = true
							local u = expected[id]
							T.check(u ~= nil, typ .. " Stage_" .. s .. ": Pad " .. id .. " gehört zu dieser Stufe")
							seen[id] = (seen[id] or 0) + 1
							local label = x:FindFirstChild("Label")
							local nameLabel = label and label:FindFirstChild("Name")
							local priceLabel = label and label:FindFirstChild("Price")
							T.check(nameLabel ~= nil and priceLabel ~= nil, id .. ": Label mit Name/Price")
							if u and nameLabel then
								T.eq(nameLabel.Text, u.name, id .. ": Name-Label wie GameConfig")
							end
							if u and not u.stage then
								T.eq(x:GetAttribute("TycoonKind"), u.kind, id .. ": TycoonKind")
							end
						end
					end
					for id in pairs(expected) do
						T.check(found[id], typ .. " Stage_" .. s .. ": Pad " .. id .. " vorhanden")
					end
					local hidden = m:FindFirstChild("Hidden")
					T.check(hidden ~= nil and hidden:IsA("Folder"), typ .. " Stage_" .. s .. ": Ordner Hidden")
					for k = 1, TY.UpgradesPerStage do
						T.check(hidden and hidden:FindFirstChild("Producer_" .. k) ~= nil, typ .. " Stage_" .. s .. ": Producer_" .. k)
					end
					T.check(m:FindFirstChild("CashDisplay") ~= nil, typ .. " Stage_" .. s .. ": CashDisplay")
				end
			end
		end
		for id in pairs(TY.UpgradeById) do
			T.eq(seen[id], 1, "Upgrade " .. id .. " genau ein Pad")
		end
		for id in pairs(TY.StageById) do
			T.eq(seen[id], 1, "Stufen-Pad " .. id .. " genau einmal")
		end
	end },

	{ "Simulation: gieriger Spieler erreicht Stufe 5 komplett in 4 h .. 6,5 h (Ziel 5 h) je Gebäudetyp; Waren reichen", function(T, H)
		local g, GC, TR = modules(H)
		for _, typ in ipairs(GC.Tycoon.Types) do
			local d = profile(g, TR)
			local seconds, run = simulate(TR, GC, d, typ)
			T.check(seconds ~= nil, "Stufe 5 komplett erreicht " .. typ)
			if seconds then
				local hours = seconds / 3600
				T.check(hours >= 4 and hours <= 6.5, string.format("%s: %.2f h (erwartet 4 .. 6,5)", typ, hours))
			end
			T.check(TR.CanRebirth(run), "Rebirth möglich " .. typ)
			T.check(run.cash < g:Config().NumberCap, "Bargeld unter NumberCap " .. typ)
			-- ein zweiter Durchlauf mit Rebirth-Boost ist schneller
			T.check(TR.Rebirth(d, NOW), "Rebirth " .. typ)
			local seconds2 = simulate(TR, GC, d, typ)
			T.check(seconds2 ~= nil and seconds2 < seconds, "mit Boost schneller " .. typ)
		end
	end },
}
