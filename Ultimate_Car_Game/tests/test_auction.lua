-- Auktionshaus: AuctionRules (rein) und AuctionService mit Stub-api (unabhängig von der MiniService-Verkabelung),
-- dazu AuctionUI im Mock-Client (Aufbau, Anzeige, gesendete Absichten).
local NOW = 1760000000

---------------------------------------------------------------- Hilfen
-- Profil wie nach MiniRules.DefaultGames mit den Feldern aus PHASE2_CONTRACT §2 (cars/carSerial/activeCar, auction),
-- auch solange die Verkabelung sie noch nicht anlegt.
local function newData(g, money, level)
	local d = g:Rules().NewData(NOW)
	d.money = money or 0
	d.level = level or 1
	if type(d.games.cars) ~= "table" then
		g:MiniShared("CarRules").ApplyDefault(d.games)
	end
	if type(d.games.auction) ~= "table" then
		d.games.auction = g:MiniShared("AuctionRules").Default()
	end
	return d
end

local function giveCar(g, d, model, tune)
	local CR = g:MiniShared("CarRules")
	local car = CR.AddCar(d, CR.NewCar(model, NOW - 3600))
	for k, v in pairs(tune or {}) do
		car[k] = v
	end
	return car
end

local function countModel(d, model)
	local n = 0
	for _, car in ipairs(d.games.cars or {}) do
		if car.model == model then
			n += 1
		end
	end
	return n
end

-- Auktionshaus mit Stub-api und Test-Sitzungen (ms-Tabellen wie MiniService: userId, player, p.profile, greeted)
local function world(H, opts)
	opts = opts or {}
	local g = H.Garage({ noServer = true })
	local W = {
		g = g, t = NOW, handlers = {}, sessions = {},
		log = { toasts = {}, notices = {}, saves = {}, changed = {}, released = {} },
	}
	W.AR = g:MiniShared("AuctionRules")
	W.AS = g:MiniServer("AuctionService")
	W.CR = g:MiniShared("CarRules")
	W.CC = g:MiniShared("CarCatalog")
	W.AS.Reset(opts.seed or 4242)
	local api = {
		now = function()
			return W.t
		end,
		toast = function(ms, text)
			table.insert(W.log.toasts, { uid = ms.userId, text = text })
		end,
		notice = function(ms, kind, data)
			data.kind = kind
			table.insert(W.log.notices, { uid = ms.userId, kind = kind, data = data })
		end,
		dirty = function(ms)
			ms.dirty = true
		end,
		writable = function(ms)
			return ms.p.profile.writable == true
		end,
		alive = function()
			return true
		end,
		changed = function(ms)
			table.insert(W.log.changed, ms.userId)
		end,
		save = function(ms)
			local d = ms.p.profile.data
			table.insert(W.log.saves, { uid = ms.userId, money = d.money, cars = #d.games.cars, t = W.t })
		end,
		releaseCar = function(ms, id)
			table.insert(W.log.released, { uid = ms.userId, id = id })
		end,
	}
	if opts.api then
		for k, v in pairs(opts.api) do
			api[k] = v
		end
	end
	W.api = api
	W.AS.Register({
		Register = function(name, fn)
			assert(W.handlers[name] == nil, "doppelt: " .. name)
			W.handlers[name] = fn
		end,
	}, api)
	function W.join(uid, name, money, level, writable)
		local d = newData(g, money, level)
		local player = { UserId = uid, Name = name, DisplayName = name, Parent = true }
		local ms = {
			userId = uid, player = player, greeted = true,
			p = { player = player, profile = { data = d, writable = writable ~= false, transacting = false } },
		}
		W.sessions[uid] = ms
		W.AS.OnJoin(ms)
		return ms, d
	end
	function W.leave(ms)
		ms.p.closing = true
		W.AS.OnLeave(ms)
		ms.player.Parent = nil
	end
	function W.act(ms, action, data)
		g:Activate()
		W.handlers[action](ms, data or {}, ms.p.profile.data, W.t)
	end
	function W.tick(dt)
		W.t += dt or 0.5
		g:Activate()
		W.AS.Tick(W.t)
	end
	function W.run(seconds)
		for _ = 1, math.ceil(seconds / 0.5) do
			W.tick(0.5)
		end
	end
	-- bis das Los nicht mehr läuft (höchstens `limit` Sekunden)
	function W.runUntilEnded(lot, limit)
		local steps = 0
		while (lot.state == "open" or lot.state == "closing") and steps < (limit or 900) * 2 do
			W.tick(0.5)
			steps += 1
		end
	end
	function W.toasted(ms, pattern)
		for _, e in ipairs(W.log.toasts) do
			if e.uid == ms.userId and e.text:find(pattern, 1, true) then
				return true
			end
		end
		return false
	end
	function W.notices(ms, kind)
		local out = {}
		for _, e in ipairs(W.log.notices) do
			if e.uid == ms.userId and e.kind == kind then
				table.insert(out, e.data)
			end
		end
		return out
	end
	function W.saves(ms)
		local out = {}
		for _, e in ipairs(W.log.saves) do
			if e.uid == ms.userId then
				table.insert(out, e)
			end
		end
		return out
	end
	-- neueste Spieler-Auktion (auch beendet, solange sie noch angezeigt wird)
	function W.playerLot()
		local order = W.AS.State().order
		for i = #order, 1, -1 do
			local lot = W.AS.Lot(order[i])
			if lot and lot.kind == "player" then
				return lot
			end
		end
		return nil
	end
	-- keine abgefangenen Fehler (pcall im Tick meldet sie nur per warn)
	function W.done(T)
		for _, w in ipairs(g:Warnings()) do
			T.check(not tostring(w):find("[Auktion]", 1, true), "Warnung: " .. tostring(w))
		end
		for _, e in ipairs(g:Errors()) do
			T.check(not tostring(e):find("Auction", 1, true), "Fehler: " .. tostring(e))
		end
	end
	function W.bid(ms, lot, amount)
		W.act(ms, "mini_auction_bid", { lot = lot.id, amount = amount or W.AR.MinBid(lot) })
	end
	-- Einliefern mit der kleinsten Startstufe und 120 s
	-- Rückgabe: das neue Los oder nil (abgelehnt)
	function W.consign(ms, car, startIndex, duration)
		local options = W.AR.StartOptions(car)
		local before = W.AS.State().serial
		W.act(ms, "mini_auction_consign", { id = car.id, start = options[startIndex or 1], duration = duration or 120 })
		local st = W.AS.State()
		return st.serial > before and W.AS.Lot(st.serial) or nil
	end
	return W
end

return {
	---------------------------------------------------------------- AuctionRules (rein)
	{ "Daten: Default/Load normalisiert, idempotent, Snapshot-Feld", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local def = AR.Default()
		T.eq(def.won, 0, "won Standard")
		T.eq(def.sold, 0, "sold Standard")
		local bad = AR.Load({ won = 0 / 0, sold = -3 }, nil, NOW)
		T.eq(bad.won, 0, "NaN -> 0")
		T.eq(bad.sold, 0, "negativ -> 0")
		local ok = AR.Load({ won = 3.7, sold = 2, junk = "x" }, nil, NOW)
		T.eq(ok.won, 3, "ganzzahlig")
		T.eq(ok.sold, 2, "sold übernommen")
		T.eq(ok.junk, nil, "Whitelist")
		T.check(H.DeepEqual(AR.Load(AR.Load(ok)), ok), "idempotent")
		T.eq(AR.Load({ auction = { won = 5, sold = 1 } }).won, 5, "ganzes games-Table wird erkannt")
		T.eq(AR.Load("kaputt").won, 0, "kein Table -> Standard")
		T.eq(AR.Load({ won = math.huge }).won, 0, "inf -> 0")
		local d = newData(g, 0, 1)
		d.games.auction = nil
		local snap = AR.SnapshotFields(d)
		T.eq(snap.won, 0, "Snapshot ohne Daten")
		AR.Stats(d).won += 2
		T.eq(AR.SnapshotFields(d).won, 2, "Stats legt an und zählt")
	end },

	{ "Zahlen: Gebotsschritte, Startgebote, Laufzeiten, Gebühr 5 %", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		T.eq(AR.Nice(2425), 2500, "Nice 2425")
		T.eq(AR.Nice(480), 500, "Nice 480")
		T.eq(AR.Nice(100), 100, "Nice 100")
		T.eq(AR.RoundPrice(3086), 3100, "RoundPrice 3086")
		T.eq(AR.RoundPrice(228000), 230000, "RoundPrice 228000")
		T.eq(AR.Step(0), AR.MinStep, "Mindestschritt")
		local last = 0
		for _, p in ipairs({ 100, 999, 5000, 48500, 380000, 1e7 }) do
			local s = AR.Step(p)
			T.check(s >= last and s >= AR.MinStep and s % 1 == 0, "Schritt wächst, ganzzahlig: " .. p)
			last = s
		end
		local fee, payout = AR.Fee(10000)
		T.eq(fee, 500, "Gebühr 5 %")
		T.eq(payout, 9500, "Auszahlung 95 %")
		T.eq(select(1, AR.Fee(0 / 0)), 0, "NaN-Betrag ohne Gebühr")
		local d = newData(g)
		local car = giveCar(g, d, "komet")
		local opts = AR.StartOptions(car)
		T.eq(#opts, #AR.StartShares, "vier Startstufen")
		for i = 2, #opts do
			T.check(opts[i] > opts[i - 1], "Stufen steigend")
		end
		T.eq(AR.ValidStart(car, opts[2]), opts[2], "Betrag einer Stufe gültig")
		T.eq(AR.ValidStart(car, 3), opts[3], "Index einer Stufe gültig")
		T.eq(AR.ValidStart(car, opts[2] + 1), nil, "anderer Betrag ungültig")
		T.eq(AR.ValidStart(car, 0 / 0), nil, "NaN ungültig")
		-- Tuning erhöht den Richtwert und damit die Stufen
		local tuned = giveCar(g, d, "komet", { engine = 3, tires = 2 })
		T.check(AR.StartOptions(tuned)[4] > opts[4], "Tuning zählt zum Richtwert")
		T.eq(AR.ValidDuration(300), 300, "300 s erlaubt")
		T.eq(AR.ValidDuration(301), nil, "301 s nicht erlaubt")
		T.eq(AR.Clock(150), "2:30", "Uhr")
	end },

	{ "Gebote: Prüfungen, Mindestgebot, Verlängerung mit Obergrenze", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local d = newData(g, 0, 10)
		local car = giveCar(g, d, "nord") -- Level 1? egal: Verkäufer
		car.locked = true
		local lot = AR.NewPlayerLot(1, { userId = 1, name = "Verkäufer" }, car, AR.StartOptions(car)[1], 120, NOW)
		local lvl = lot.level
		local bidder = { userId = 2, level = lvl, money = 1e6, cars = 0, writable = true }
		local minBid = AR.MinBid(lot)
		T.eq(minBid, lot.start, "erstes Mindestgebot = Start")
		T.check(not AR.CheckBid(lot, { userId = 1, level = 99, money = 1e9, cars = 0, writable = true }, minBid, NOW), "nicht aufs eigene Auto")
		T.check(not AR.CheckBid(lot, { userId = 2, level = 99, money = 1e9, cars = 0, writable = false }, minBid, NOW), "Spieler-Auktion nur schreibbar")
		T.check(not AR.CheckBid(lot, bidder, minBid - 1, NOW), "unter Mindestgebot")
		T.check(not AR.CheckBid(lot, bidder, minBid + 0.5, NOW), "nur ganze Credits")
		T.check(not AR.CheckBid(lot, bidder, lot.maxBid + 1, NOW), "über der Höchstgrenze")
		T.check(not AR.CheckBid(lot, { userId = 2, level = lvl, money = minBid - 1, cars = 0, writable = true }, minBid, NOW), "Guthaben reicht nicht")
		T.check(not AR.CheckBid(lot, { userId = 2, level = lvl, money = 1e9, cars = 20, writable = true }, minBid, NOW), "Garage voll")
		T.check(AR.CheckBid(lot, bidder, minBid, NOW), "gültiges Gebot")
		AR.PlaceBid(lot, 2, "B", minBid, NOW)
		T.check(not AR.CheckBid(lot, bidder, AR.MinBid(lot), NOW + 1), "schon Höchstbietender")
		T.eq(AR.MinBid(lot), minBid + AR.Step(minBid), "Mindestgebot = Gebot + Schritt")
		T.eq(lot.endsAt, NOW + 120, "frühes Gebot verlängert nicht")
		-- Gebot 5 s vor Schluss: Restzeit wieder 15 s
		AR.PlaceBid(lot, 3, "C", AR.MinBid(lot), NOW + 115)
		T.eq(lot.endsAt, NOW + 130, "Anti-Snipe auf 15 s")
		-- Verlängerung höchstens bis hardEnd
		local t = NOW + 129
		for i = 1, 30 do
			AR.PlaceBid(lot, 2 + i % 2, "X", AR.MinBid(lot), t)
			t = lot.endsAt - 1
		end
		T.eq(lot.endsAt, lot.hardEnd, "Verlängerung gedeckelt")
		T.check(not AR.CheckBid(lot, { userId = 9, level = 99, money = 1e12, cars = 0, writable = true }, AR.MinBid(lot), lot.endsAt), "nach Ablauf kein Gebot")
		-- NPC-Lose: auch ohne schreibbares Profil, aber mit Level
		local npcLot = AR.NewNpcLot(2, "komet_rally", 7, NOW)
		T.check(AR.CheckBid(npcLot, { userId = 5, level = 5, money = 1e6, cars = 0, writable = false }, AR.MinBid(npcLot), NOW), "NPC-Los ohne Speicherprofil")
		T.check(not AR.CheckBid(npcLot, { userId = 5, level = 4, money = 1e6, cars = 0, writable = true }, AR.MinBid(npcLot), NOW), "Level-Voraussetzung")
		-- Bieter verlässt: seine Gebote fallen weg, Liste bleibt steigend
		local l2 = AR.NewNpcLot(3, "komet_rally", 7, NOW)
		AR.PlaceBid(l2, 10, "A", AR.MinBid(l2), NOW)
		AR.PlaceBid(l2, 11, "B", AR.MinBid(l2), NOW + 1)
		AR.PlaceBid(l2, 10, "A", AR.MinBid(l2), NOW + 2)
		T.eq(AR.RemoveBidder(l2, 10, NOW + 3), 2, "zwei Gebote entfernt")
		T.eq(AR.Top(l2).userId, 11, "B vorn")
		T.eq(AR.MinBid(l2), AR.Top(l2).amount + AR.Step(AR.Top(l2).amount), "Mindestgebot folgt dem neuen Höchstgebot")
	end },

	{ "NPC-Bieter: feste Limits, Bedenkzeit, Mindestschritt, nie über dem Limit", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local CC = g:MiniShared("CarCatalog")
		local seenCollector, seenWithout = false, false
		for seed = 1, 12 do
			local lot = AR.NewNpcLot(seed, "vektor_gold", seed * 13, NOW)
			local again = AR.NewNpcLot(seed, "vektor_gold", seed * 13, NOW)
			T.check(H.DeepEqual(lot.npcs, again.npcs), "deterministisch aus dem Seed")
			T.check(#lot.npcs >= 2 and #lot.npcs <= 3, "2–3 NPCs")
			if #lot.npcs == 3 then
				seenCollector = true
			else
				seenWithout = true
			end
			local names = {}
			for _, n in ipairs(lot.npcs) do
				local st = AR.Styles[n.style]
				local share = n.limit / lot.value
				T.check(share >= st.lo - 0.02 and share <= st.hi + 0.02, "Limit in der Stil-Spanne " .. n.style)
				T.check(n.think >= st.think[1] and n.think <= st.think[2], "Bedenkzeit in der Spanne")
				T.check(not names[n.name], "verschiedene Namen")
				names[n.name] = true
			end
			T.eq(lot.start, AR.RoundPrice(CC.Model("vektor_gold").value * AR.Npc.startShare), "Startgebot 60 %")
			-- Ablauf nur mit NPCs
			local t = NOW
			local lastAt, lastNpc = -math.huge, nil
			while t < lot.endsAt do
				local i, amount = AR.NpcDecide(lot, t)
				if i then
					T.eq(amount, AR.MinBid(lot), "NPC bietet genau das Mindestgebot")
					T.check(amount <= lot.npcs[i].limit, "nie über dem Limit")
					T.check(i ~= lastNpc, "überbietet sich nie selbst")
					T.check(t - lastAt >= lot.npcs[i].think - 1e-9, "wartet seine Bedenkzeit")
					AR.PlaceBid(lot, 0, lot.npcs[i].name, amount, t, i)
					lastAt, lastNpc = t, i
				end
				t += 0.5
			end
			-- Sieger ist der NPC mit dem höchsten Limit; die anderen sind ausgestiegen
			local best = 1
			for i, n in ipairs(lot.npcs) do
				if n.limit > lot.npcs[best].limit then
					best = i
				end
			end
			local top = AR.Top(lot)
			T.check(top ~= nil and top.npc ~= nil and lot.npcs[top.npc].limit == lot.npcs[best].limit, "höchstes Limit gewinnt")
			for i in ipairs(lot.npcs) do
				if top and i ~= top.npc then
					T.check(AR.NpcOut(lot, i), "andere NPCs sind ausgestiegen")
				end
			end
			T.check(lot.endsAt <= lot.hardEnd, "Ende innerhalb der Obergrenze")
		end
		T.check(seenCollector and seenWithout, "Liebhaber mal dabei, mal nicht")
		-- Modellreihe: nie zweimal hintereinander
		local prev
		for s = 1, 30 do
			local m = AR.PickNpcModel(s, 99, prev)
			T.check(CC.Model(m) and CC.Model(m).special, "Sondermodell")
			T.check(m ~= prev, "kein doppeltes Los hintereinander")
			prev = m
		end
		-- Ansicht: Stil und Hinweis lesbar
		local lot = AR.NewNpcLot(1, "komet_rally", 5, NOW)
		local view = AR.LotView(lot, NOW)
		T.check(view.npcs[1].hint:find("Richtwerts", 1, true) ~= nil, "Hinweis zum Limit")
		T.check(type(view.npcs[1].styleName) == "string", "Stilname")
		T.eq(view.minBid, lot.start, "Mindestgebot in der Ansicht")
	end },

	{ "Übergabe: ein Schritt, Geld stimmt, kein Duplikat, kein zweiter Zuschlag", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local CR = g:MiniShared("CarRules")
		local sd = newData(g, 1000, 20)
		local bd = newData(g, 100000, 20) -- Vektor RS: ab Level 18
		local car = giveCar(g, sd, "vektor", { engine = 2, paint = 3 })
		giveCar(g, sd, "komet")
		local carId = car.id
		car.locked = true
		local lot = AR.NewPlayerLot(1, { userId = 1, name = "S" }, car, AR.StartOptions(car)[1], 120, NOW)
		local bid = AR.PlaceBid(lot, 2, "B", 40000, NOW)
		T.check(not AR.Handover(lot, bid, bd, sd, NOW), "nur im Zustand closing")
		lot.state = "closing"
		local buyerCars = #bd.games.cars
		local ok, info = AR.Handover(lot, bid, bd, sd, NOW + 1)
		T.check(ok, "Übergabe gelingt")
		T.eq(lot.state, "sold", "Los verkauft")
		T.eq(CR.Find(sd, carId), nil, "Auto beim Verkäufer weg")
		T.eq(#bd.games.cars, buyerCars + 1, "genau ein Auto beim Käufer")
		T.eq(countModel(bd, "vektor"), 1, "das Modell einmal")
		T.eq(info.car.engine, 2, "Tuning wandert mit")
		T.eq(info.car.paint, 3, "Lack wandert mit")
		T.eq(info.car.locked, false, "beim Käufer nicht gesperrt")
		T.eq(bd.money, 100000 - 40000, "Käufer zahlt sein Gebot")
		T.eq(sd.money, 1000 + 38000, "Verkäufer bekommt 95 %")
		T.eq(info.fee, 2000, "Gebühr 2.000")
		T.eq(bd.games.auction.won, 1, "won gezählt")
		T.eq(sd.games.auction.sold, 1, "sold gezählt")
		-- zweiter Zuschlag: weder im Zustand sold noch nach (fehlerhaftem) Zurücksetzen möglich
		T.check(not AR.Handover(lot, bid, bd, sd, NOW + 2), "zweite Übergabe verweigert")
		lot.state = "closing"
		local ok2, why = AR.Handover(lot, bid, bd, sd, NOW + 3)
		T.check(not ok2 and why == "car", "Auto nicht mehr da -> keine zweite Übergabe")
		T.eq(bd.money, 60000, "kein zweites Abbuchen")
		T.eq(sd.money, 39000, "keine zweite Gutschrift")
		T.eq(#bd.games.cars, buyerCars + 1, "kein zweites Auto")
		-- ungedeckt: nichts ändert sich
		local sd2, bd2 = newData(g, 0, 10), newData(g, 500, 10)
		local car2 = giveCar(g, sd2, "komet")
		car2.locked = true
		local lot2 = AR.NewPlayerLot(2, { userId = 1, name = "S" }, car2, AR.StartOptions(car2)[1], 120, NOW)
		local bid2 = AR.PlaceBid(lot2, 2, "B", 4000, NOW)
		lot2.state = "closing"
		local ok3, why3 = AR.Handover(lot2, bid2, bd2, sd2, NOW)
		T.check(not ok3 and why3 == "money", "ungedeckt")
		T.check(CR.Find(sd2, car2.id) ~= nil, "Auto bleibt beim Verkäufer")
		T.eq(bd2.money, 500, "Geld unverändert")
		T.eq(lot2.state, "closing", "Los wartet auf das nächste Gebot")
		-- Garage voll
		local bd3 = newData(g, 1e6, 10)
		for _ = 1, 20 do
			giveCar(g, bd3, "komet")
		end
		local ok4, why4 = AR.Handover(lot2, bid2, bd3, sd2, NOW)
		T.check(not ok4 and why4 == "garage", "Garage voll")
		-- NPC-Los: Sondermodell
		local nd = newData(g, 50000, 10)
		local nlot = AR.NewNpcLot(3, "komet_rally", 1, NOW)
		local nb = AR.PlaceBid(nlot, 7, "P", 20000, NOW)
		nlot.state = "closing"
		local ok5, info5 = AR.GrantNpcLot(nlot, nb, nd, NOW)
		T.check(ok5, "Sondermodell zugeschlagen")
		T.eq(info5.car.model, "komet_rally", "Modell")
		T.eq(nd.money, 30000, "Gebot bezahlt")
		T.check(not AR.GrantNpcLot(nlot, nb, nd, NOW), "kein zweiter Zuschlag")
		T.eq(countModel(nd, "komet_rally"), 1, "genau ein Sondermodell")
	end },

	{ "Zuschlag: nächsthöheres gültiges Gebot, NPC immer gültig, warten", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local lot = AR.NewNpcLot(1, "komet_rally", 3, NOW)
		AR.PlaceBid(lot, 0, lot.npcs[1].name, AR.MinBid(lot), NOW, 1)
		AR.PlaceBid(lot, 10, "A", AR.MinBid(lot), NOW + 1)
		AR.PlaceBid(lot, 11, "B", AR.MinBid(lot), NOW + 2)
		AR.PlaceBid(lot, 10, "A", AR.MinBid(lot), NOW + 3)
		local c = AR.Candidates(lot)
		T.eq(#c, 3, "je Bieter ein Gebot")
		T.eq(c[1].userId, 10, "A zuerst (höchstes)")
		T.eq(c[2].userId, 11, "dann B")
		T.check(c[3].npc == 1, "dann NPC")
		local verdicts = { [10] = "money", [11] = "ok" }
		local w = AR.PickWinner(lot, function(b)
			return verdicts[b.userId]
		end)
		T.eq(w.userId, 11, "B gewinnt, weil A nicht zahlen kann")
		T.eq(lot.skipped[10], "money", "A ausgeschlossen")
		verdicts[11] = "wait"
		local w2, wait = AR.PickWinner(lot, function(b)
			return verdicts[b.userId]
		end)
		T.eq(w2, nil, "kein Sieger während Warten")
		T.eq(wait, "wait", "wartet")
		verdicts[11] = "garage"
		local w3 = AR.PickWinner(lot, function(b)
			return verdicts[b.userId]
		end)
		T.check(w3 and w3.npc == 1, "NPC-Gebot ist das nächste gültige")
	end },

	---------------------------------------------------------------- AuctionService mit Stub-api
	{ "NPC-Zeitplan: Los öffnet, NPCs bieten sichtbar, Zuschlag an NPC, Pause, nächstes Los", function(T, H)
		local W = world(H)
		local a = W.join(1, "Anna", 0, 1)
		W.tick(0.5)
		local st = W.AS.State()
		T.check(st.npcNext ~= nil, "nächstes Los geplant")
		T.eq(countModel(a.p.profile.data, "x"), 0, "nichts geändert")
		local ups = W.notices(a, "auction_update")
		T.check(#ups >= 1, "Zustand an neue Sitzung")
		T.check(ups[#ups].next ~= nil and type(ups[#ups].next.name) == "string", "nächstes Los angekündigt")
		T.eq(ups[#ups].you.userId, 1, "you.userId")
		W.run(W.AR.Npc.firstDelay + 1)
		local lot = W.AS.Lot(st.order[1])
		T.check(lot ~= nil and lot.kind == "npc" and lot.state == "open", "NPC-Los offen")
		W.runUntilEnded(lot)
		T.eq(lot.state, "sold", "an NPC verkauft")
		T.check(lot.result and lot.result.npc, "Ergebnis: NPC")
		T.check(#lot.bids >= 2, "NPCs haben geboten")
		T.check(st.npcNext ~= nil and st.npcNext.at == lot.endedAt + W.AR.Npc.breakSeconds, "Pause bis zum nächsten Los")
		local sawSold = false
		for _, u in ipairs(W.notices(a, "auction_update")) do
			for _, lv in ipairs(u.lots) do
				if lv.id == lot.id and lv.state == "sold" then
					sawSold = true
				end
			end
		end
		T.check(sawSold, "Ergebnis öffentlich gesendet")
		W.run(W.AR.Npc.breakSeconds + 1)
		local open = 0
		for _, id in ipairs(st.order) do
			local l = W.AS.Lot(id)
			if l.kind == "npc" and l.state == "open" then
				open += 1
				T.check(l.model ~= lot.model, "anderes Modell")
			end
		end
		T.eq(open, 1, "nächstes NPC-Los offen")
		-- ohne Spieler keine neuen Lose
		W.leave(a)
		local W2 = world(H)
		W2.run(60)
		T.eq(#W2.AS.State().order, 0, "ohne Spieler kein Los")
		T.eq(#W.CR.Default().cars, 0, "Sanity")
		W.done(T)
	end },

	{ "NPC-Los: Spieler überbietet alle NPCs, zahlt beim Zuschlag, bekommt das Sondermodell", function(T, H)
		local W = world(H)
		local a, ad = W.join(1, "Anna", 200000, 10)
		local b = W.join(2, "Ben", 0, 1)
		W.tick()
		local lot = W.AS.StartNpcLot("komet_rally", W.t)
		T.check(lot ~= nil, "Los gestartet")
		W.bid(a, lot)
		T.eq(W.AR.Top(lot).userId, 1, "Anna vorn")
		T.eq(ad.money, 200000, "Gebot bucht noch nichts ab")
		T.check(W.toasted(a, "Gebot abgegeben"), "Bestätigung")
		-- Ben (Level 1) darf nicht
		W.bid(b, lot)
		T.check(W.toasted(b, "Level"), "Level-Hinweis")
		-- NPC antwortet nach seiner Bedenkzeit
		W.run(10)
		T.check(W.AR.Top(lot).npc ~= nil, "NPC hat überboten")
		T.check(W.toasted(a, "Überboten"), "Überboten-Hinweis")
		-- Anna bietet über alle Limits
		local maxLimit = 0
		for _, n in ipairs(lot.npcs) do
			maxLimit = math.max(maxLimit, n.limit)
		end
		W.bid(a, lot, maxLimit + 1000)
		W.runUntilEnded(lot)
		T.eq(lot.state, "sold", "verkauft")
		T.eq(lot.result.userId, 1, "an Anna")
		T.eq(ad.money, 200000 - (maxLimit + 1000), "Anna zahlt ihr Gebot")
		T.eq(countModel(ad, "komet_rally"), 1, "Sondermodell in der Garage")
		T.eq(ad.games.auction.won, 1, "won")
		T.check(#W.notices(a, "auction_won") == 1, "auction_won")
		T.check(#W.saves(a) >= 1, "sofort gespeichert")
		T.check(table.find(W.log.changed, 1) ~= nil, "api.changed für Anna")
		W.done(T)
	end },

	{ "Spieler-Auktion: Einliefern sperrt, Überbieten, Übergabe + sofort beide Profile speichern", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 500, 10)
		local a, ad = W.join(2, "Anna", 100000, 10)
		local b, bd = W.join(3, "Ben", 100000, 10)
		local car = giveCar(W.g, sd, "komet", { engine = 1 })
		local carId = car.id
		local lot = W.consign(s, car, 1, 120)
		T.check(lot ~= nil and lot.kind == "player", "Los angelegt")
		T.eq(car.locked, true, "Auto gesperrt")
		T.eq(W.log.released[1] and W.log.released[1].id, carId, "gespawntes Auto wird abgebaut")
		T.eq(lot.sellerName, "Sina", "Verkäufer")
		T.eq(lot.car.engine, 1, "Tuning sichtbar")
		-- gesperrt: nicht erneut einlieferbar, nicht tunebar/verkaufbar
		W.consign(s, car, 1, 120)
		T.check(W.toasted(s, "schon in einer Auktion"), "nicht doppelt einliefern")
		T.check(not W.CR.Tune(sd, carId, "engine", 1), "gesperrt: kein Tuning")
		T.check(not W.CR.Sell(sd, carId), "gesperrt: kein Verkauf")
		T.check(not W.CR.CanSpawn(sd, carId), "gesperrt: kein Spawn")
		-- Bieten
		W.bid(a, lot)
		W.bid(b, lot)
		T.check(W.toasted(a, "Überboten: Ben"), "Anna überboten")
		W.bid(a, lot)
		local price = W.AR.Top(lot).amount
		T.eq(W.AR.Top(lot).userId, 2, "Anna vorn")
		W.runUntilEnded(lot)
		T.eq(lot.state, "sold", "verkauft")
		T.eq(W.CR.Find(sd, carId), nil, "Auto beim Verkäufer weg")
		T.eq(countModel(ad, "komet"), 1, "Auto bei Anna")
		T.eq(countModel(bd, "komet"), 0, "nicht bei Ben")
		local fee = math.floor(price * 0.05 + 0.5)
		T.eq(ad.money, 100000 - price, "Anna zahlt")
		T.eq(sd.money, 500 + price - fee, "Sina bekommt 95 %")
		T.eq(bd.money, 100000, "Ben zahlt nichts")
		local sSaves, aSaves = W.saves(s), W.saves(a)
		T.check(#sSaves >= 1 and #aSaves >= 1, "beide Profile gespeichert")
		T.eq(sSaves[1].money, sd.money, "Verkäufer-Speichern nach der Übergabe")
		T.eq(aSaves[1].cars, #ad.games.cars, "Käufer-Speichern nach der Übergabe")
		T.eq(#W.notices(a, "auction_won"), 1, "auction_won an Anna")
		local sold = W.notices(s, "auction_sold")
		T.eq(#sold, 1, "auction_sold an Sina")
		T.eq(sold[1] and sold[1].payout, price - fee, "Auszahlung im Hinweis")
		T.check(W.toasted(b, "ging an Anna"), "Ben erfährt den Ausgang")
		T.check(table.find(W.log.changed, 1) and table.find(W.log.changed, 2), "api.changed für beide")
		W.done(T)
	end },

	{ "Zuschlag: Guthaben beim Zuschlag nicht gedeckt -> nächsthöheres gültiges Gebot", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a, ad = W.join(2, "Anna", 100000, 10)
		local b, bd = W.join(3, "Ben", 100000, 10)
		local car = giveCar(W.g, sd, "nord")
		local lot = W.consign(s, car, 1, 120)
		W.bid(b, lot)
		local benBid = W.AR.Top(lot).amount
		W.bid(a, lot)
		local annaBid = W.AR.Top(lot).amount
		T.check(annaBid > benBid, "Anna höher")
		-- Anna gibt ihr Geld aus (z. B. in der Werkstatt)
		ad.money = annaBid - 1
		W.runUntilEnded(lot)
		T.eq(lot.state, "sold", "trotzdem verkauft")
		T.eq(lot.result.userId, 3, "an Ben (nächsthöheres Gebot)")
		T.eq(lot.result.amount, benBid, "zu Bens Gebot")
		T.eq(ad.money, annaBid - 1, "Anna unverändert")
		T.eq(bd.money, 100000 - benBid, "Ben zahlt")
		T.eq(countModel(bd, "nord"), 1, "Ben hat das Auto")
		T.check(W.toasted(a, "nicht gedeckt"), "Anna erfährt es")
		-- niemand kann zahlen: unverkauft, Auto wieder frei
		local s2, sd2 = W.join(4, "Sven", 0, 10)
		local c2 = giveCar(W.g, sd2, "komet")
		W.t += W.AR.ConsignCooldown
		local lot2 = W.consign(s2, c2, 1, 120)
		T.check(lot2 ~= nil and lot2 ~= lot and lot2.state == "open", "zweites Los")
		W.bid(a, lot2)
		ad.money = 0
		W.runUntilEnded(lot2)
		T.eq(lot2.state, "unsold", "unverkauft")
		T.eq(c2.locked, false, "Auto entsperrt")
		T.check(W.CR.Find(sd2, c2.id) ~= nil, "Auto bleibt beim Verkäufer")
		W.done(T)
	end },

	{ "Verkäufer verlässt den Server: Auktion abgebrochen, Auto entsperrt, Bieter informiert", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a, ad = W.join(2, "Anna", 100000, 10)
		local car = giveCar(W.g, sd, "komet")
		local lot = W.consign(s, car, 1, 300)
		W.bid(a, lot)
		W.leave(s)
		T.eq(lot.state, "canceled", "abgebrochen")
		T.eq(car.locked, false, "Auto im (gleich gespeicherten) Profil entsperrt")
		T.eq(lot.reason, "seller_left", "Grund")
		T.check(W.toasted(a, "abgebrochen"), "Anna informiert")
		W.run(400)
		T.eq(ad.money, 100000, "kein Geld bewegt")
		T.eq(countModel(ad, "komet"), 0, "kein Auto bewegt")
		T.eq(#W.notices(a, "auction_won"), 0, "kein Zuschlag")
		T.eq(W.AS.Lot(lot.id), nil, "beendetes Los verschwindet nach der Anzeigezeit")
		W.done(T)
	end },

	{ "Bieter verlässt den Server: Gebot fällt weg, nächstes Gebot gewinnt", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a, ad = W.join(2, "Anna", 100000, 10)
		local b, bd = W.join(3, "Ben", 100000, 10)
		local car = giveCar(W.g, sd, "komet")
		local lot = W.consign(s, car, 1, 120)
		W.bid(b, lot)
		local benBid = W.AR.Top(lot).amount
		W.bid(a, lot)
		W.leave(a)
		T.eq(W.AR.Top(lot).userId, 3, "Ben wieder vorn")
		T.eq(W.AR.MinBid(lot), benBid + W.AR.Step(benBid), "Mindestgebot folgt")
		W.runUntilEnded(lot)
		T.eq(lot.result and lot.result.userId, 3, "Ben gewinnt")
		T.eq(ad.money, 100000, "Anna (weg) zahlt nichts")
		T.eq(countModel(ad, "komet"), 0, "Anna bekommt nichts")
		T.eq(bd.money, 100000 - benBid, "Ben zahlt")
		-- letzter Bieter weg: unverkauft
		local s2, sd2 = W.join(4, "Sven", 0, 10)
		local c2 = giveCar(W.g, sd2, "komet")
		local lot2 = W.consign(s2, c2, 1, 120)
		W.bid(b, lot2)
		W.leave(b)
		W.runUntilEnded(lot2)
		T.eq(lot2.state, "unsold", "unverkauft")
		T.eq(c2.locked, false, "Auto frei")
		W.done(T)
	end },

	{ "Doppelter Zuschlag unmöglich (Tick, Settle, erneutes closing)", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a, ad = W.join(2, "Anna", 100000, 10)
		local car = giveCar(W.g, sd, "komet")
		local lot = W.consign(s, car, 2, 120)
		W.bid(a, lot)
		W.runUntilEnded(lot)
		T.eq(lot.state, "sold", "verkauft")
		local money, smoney, cars = ad.money, sd.money, #ad.games.cars
		local saves = #W.log.saves
		for _ = 1, 10 do
			W.tick()
			T.eq(W.AS.Settle(lot, W.t), false, "Settle auf beendetem Los tut nichts")
		end
		lot.state = "closing" -- simulierter Fehler: dasselbe Los noch einmal abrechnen
		W.AS.Settle(lot, W.t)
		W.tick()
		T.eq(ad.money, money, "kein zweites Abbuchen")
		T.eq(sd.money, smoney, "keine zweite Gutschrift")
		T.eq(#ad.games.cars, cars, "kein zweites Auto")
		T.eq(countModel(ad, "komet"), 1, "Auto genau einmal")
		T.eq(#W.log.saves, saves, "kein weiteres Speichern")
		T.eq(lot.state, "canceled", "fehlendes Auto -> Abbruch statt Übergabe")
		T.eq(#W.notices(a, "auction_won"), 1, "nur ein auction_won")
		W.done(T)
	end },

	{ "Dup-sicher: neue Id beim Käufer, Weiterverkauf, keine Doppel-Einlieferung", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a, ad = W.join(2, "Anna", 100000, 10)
		giveCar(W.g, ad, "nord") -- Anna hat schon ein Auto mit Id 1
		local car = giveCar(W.g, sd, "komet")
		local lot = W.consign(s, car, 1, 120)
		W.act(s, "mini_auction_consign", { id = car.id, start = W.AR.StartOptions(car)[1], duration = 120 })
		T.eq(W.AS.State().order[#W.AS.State().order], lot.id, "kein zweites Los")
		W.bid(a, lot)
		W.runUntilEnded(lot)
		local ids = {}
		for _, c in ipairs(ad.games.cars) do
			T.check(not ids[c.id], "Ids eindeutig")
			ids[c.id] = true
		end
		local bought
		for _, c in ipairs(ad.games.cars) do
			if c.model == "komet" then
				bought = c
			end
		end
		T.check(bought ~= nil and bought.locked == false, "gekauftes Auto frei")
		-- Sina kann das verkaufte Auto nicht mehr einliefern
		W.t += W.AR.ConsignCooldown
		W.act(s, "mini_auction_consign", { id = car.id, start = W.AR.StartOptions(car)[1], duration = 120 })
		T.check(W.toasted(s, "Auto nicht gefunden"), "verkauftes Auto weg")
		-- Anna kann es weiterverkaufen
		W.t += W.AR.ConsignCooldown
		local lot2 = W.consign(a, bought, 1, 120)
		T.check(lot2 ~= nil and lot2.id ~= lot.id and lot2.sellerId == 2, "Weiterverkauf möglich")
		W.done(T)
	end },

	{ "Zuschlag wartet, solange ein Profil transacting ist (begrenzt)", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a, ad = W.join(2, "Anna", 100000, 10)
		local b, bd = W.join(3, "Ben", 100000, 10)
		local car = giveCar(W.g, sd, "komet")
		local lot = W.consign(s, car, 1, 120)
		W.bid(b, lot)
		W.bid(a, lot)
		a.p.profile.transacting = true
		W.run(125)
		T.eq(lot.state, "closing", "wartet auf Annas Kauf")
		T.eq(ad.money, 100000, "Geld nicht angefasst")
		T.eq(countModel(ad, "komet") + countModel(bd, "komet"), 0, "noch keine Übergabe")
		a.p.profile.transacting = false
		W.tick()
		T.eq(lot.state, "sold", "danach Zuschlag")
		T.eq(lot.result.userId, 2, "an Anna")
		-- Verkäufer transacting: wartet ebenso
		local s2, sd2 = W.join(4, "Sven", 0, 10)
		local c2 = giveCar(W.g, sd2, "komet")
		local lot2 = W.consign(s2, c2, 1, 120)
		W.bid(b, lot2)
		s2.p.profile.transacting = true
		W.run(125)
		T.eq(lot2.state, "closing", "wartet auf den Verkäufer")
		T.eq(bd.money, 100000, "Ben noch nicht belastet")
		s2.p.profile.transacting = false
		W.tick()
		T.eq(lot2.state, "sold", "dann verkauft")
		-- dauerhaft transacting: nach SettleWaitMax gewinnt das nächste Gebot
		local s3, sd3 = W.join(5, "Sara", 0, 10)
		local c3 = giveCar(W.g, sd3, "komet")
		local lot3 = W.consign(s3, c3, 1, 120)
		W.bid(b, lot3)
		W.bid(a, lot3)
		a.p.profile.transacting = true
		W.run(120 + W.AR.SettleWaitMax + 2)
		T.eq(lot3.state, "sold", "nicht ewig blockiert")
		T.eq(lot3.result.userId, 3, "Ben als nächstes Gebot")
		T.check(W.toasted(a, "gespeichert"), "Anna erfährt den Grund")
		W.done(T)
	end },

	{ "Schreibschutz: ohne schreibbares Profil kein Einliefern/Bieten bei Spielern (NPC-Los geht)", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10, false)
		local a, ad = W.join(2, "Anna", 100000, 10, false)
		local car = giveCar(W.g, sd, "komet")
		W.consign(s, car, 1, 120)
		T.eq(W.playerLot(), nil, "kein Los")
		T.eq(car.locked, false, "Auto nicht gesperrt")
		T.check(W.toasted(s, "gespeichertem Profil"), "Hinweis")
		local s2, sd2 = W.join(3, "Sven", 0, 10)
		local c2 = giveCar(W.g, sd2, "komet")
		local lot = W.consign(s2, c2, 1, 120)
		W.bid(a, lot)
		T.eq(#lot.bids, 0, "Bieten verweigert")
		-- Profil verliert die Schreibbarkeit vor dem Zuschlag: Bieter fällt heraus
		local b, bd = W.join(4, "Ben", 100000, 10)
		W.bid(b, lot)
		b.p.profile.writable = false
		W.runUntilEnded(lot)
		T.eq(lot.state, "unsold", "kein gültiges Gebot")
		T.eq(bd.money, 100000, "Ben unverändert")
		-- NPC-Los: auch ohne Speicherprofil
		W.tick()
		local npcLot = W.AS.StartNpcLot("komet_rally", W.t)
		if not npcLot then
			for _, id in ipairs(W.AS.State().order) do
				local l = W.AS.Lot(id)
				if l.kind == "npc" and l.state == "open" then
					npcLot = l
				end
			end
		end
		ad.level, ad.money = 60, 1e7
		W.bid(a, npcLot)
		T.eq(W.AR.Top(npcLot).userId, 2, "NPC-Los: Gebot angenommen")
		W.done(T)
	end },

	{ "Zurückziehen nur durch den Verkäufer und nur ohne Gebote; Grenzen je Verkäufer", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a = W.join(2, "Anna", 100000, 10)
		local car = giveCar(W.g, sd, "komet")
		local car2 = giveCar(W.g, sd, "komet")
		local lot = W.consign(s, car, 1, 120)
		W.act(a, "mini_auction_cancel", { lot = lot.id })
		T.check(W.toasted(a, "gehört dir nicht"), "fremd")
		T.eq(lot.state, "open", "läuft weiter")
		-- zweites Auto: höchstens ein Los je Verkäufer
		W.t += W.AR.ConsignCooldown
		W.act(s, "mini_auction_consign", { id = car2.id, start = W.AR.StartOptions(car2)[1], duration = 120 })
		T.check(W.toasted(s, "schon ein Auto in der Auktion"), "ein Los je Verkäufer")
		T.eq(car2.locked, false, "zweites Auto frei")
		-- ungültige Laufzeit / Startgebot
		W.act(s, "mini_auction_consign", { id = car2.id, start = W.AR.StartOptions(car2)[1], duration = 999 })
		T.check(W.toasted(s, "Laufzeit"), "Laufzeit geprüft")
		W.act(s, "mini_auction_consign", { id = car2.id, start = 12345, duration = 120 })
		T.check(W.toasted(s, "Startgebot"), "Startgebot geprüft")
		W.bid(a, lot)
		W.act(s, "mini_auction_cancel", { lot = lot.id })
		T.check(W.toasted(s, "schon Gebote"), "mit Geboten kein Rückzug")
		T.eq(lot.state, "open", "läuft weiter")
		-- ohne Gebote: Rückzug
		local s2, sd2 = W.join(3, "Sven", 0, 10)
		local c3 = giveCar(W.g, sd2, "komet")
		local lot2 = W.consign(s2, c3, 1, 120)
		W.act(s2, "mini_auction_cancel", { lot = lot2.id })
		T.eq(lot2.state, "canceled", "zurückgezogen")
		T.eq(c3.locked, false, "Auto frei")
		W.act(s2, "mini_auction_cancel", { lot = lot2.id })
		T.check(W.toasted(s2, "schon beendet"), "zweiter Rückzug harmlos")
		-- NaN/ungültige Beträge
		W.act(a, "mini_auction_bid", { lot = lot.id, amount = 0 / 0 })
		W.act(a, "mini_auction_bid", { lot = 999, amount = 100 })
		T.check(W.toasted(a, "gibt es nicht mehr"), "unbekanntes Los")
		W.done(T)
	end },

	{ "auction_update an alle Sitzungen (gedrosselt), neue Sitzung und Hello bekommen den Zustand", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local a = W.join(2, "Anna", 100000, 10)
		local late = W.join(3, "Lars", 0, 1)
		late.greeted = false -- Client hört noch nicht zu
		W.tick()
		local before = #W.notices(a, "auction_update")
		T.check(before >= 1, "Anna hat den Zustand")
		T.eq(#W.notices(late, "auction_update"), 0, "vor hello nichts")
		local car = giveCar(W.g, sd, "komet")
		W.t += 0.3 -- Drossel (0,25 s) seit dem letzten Senden abgelaufen
		local lot = W.consign(s, car, 1, 120)
		local ups = W.notices(a, "auction_update")
		T.check(#ups > before, "Einliefern sofort an alle")
		local found
		for _, lv in ipairs(ups[#ups].lots) do
			if lv.id == lot.id then
				found = lv
			end
		end
		T.check(found ~= nil and found.sellerName == "Sina" and found.minBid == lot.start, "Los öffentlich sichtbar")
		T.eq(found and found.name, "Komet C1", "Name im Los")
		-- schnelle Folge: gedrosselt, im Tick nachgeholt
		W.bid(a, lot)
		local n1 = #W.notices(s, "auction_update")
		W.t += 0.05
		W.act(a, "mini_auction_bid", { lot = lot.id, amount = W.AR.MinBid(lot) }) -- Anna schon vorn: abgelehnt
		T.eq(#W.notices(s, "auction_update"), n1, "keine Flut")
		late.greeted = true
		W.AS.Hello(late)
		T.check(#W.notices(late, "auction_update") >= 1, "nach Hello")
		local u = W.notices(late, "auction_update")
		T.eq(u[#u].you.writable, true, "you.writable")
		T.check(type(u[#u].rules) == "table" and u[#u].rules.fee == 0.05, "Regeln mitgeschickt")
		W.done(T)
	end },

	{ "In-World-Bildschirm AuctionScreen (Title/Lot/Bid/Time)", function(T, H)
		local W = world(H)
		local g = W.g
		g:Activate()
		local env = g.env
		local city = env.workspace:FindFirstChild("City")
		if not city then
			city = env.Instance.new("Model")
			city.Name = "City"
			city.Parent = env.workspace
		end
		local part = env.Instance.new("Part")
		part.Name = "AuctionScreen"
		part.Anchored = true
		part.Parent = city
		local gui = env.Instance.new("SurfaceGui")
		gui.Parent = part
		local labels = {}
		for _, key in ipairs({ "Title", "Lot", "Bid", "Time" }) do
			local l = env.Instance.new("TextLabel")
			l.Name = key
			l.Parent = gui
			labels[key] = l
		end
		local a = W.join(1, "Anna", 200000, 50)
		W.tick()
		T.check(labels.Title.Text ~= "" and labels.Lot.Text:find("Als Nächstes", 1, true) ~= nil, "Ankündigung: " .. labels.Lot.Text)
		local lot = W.AS.StartNpcLot("vektor_gold", W.t)
		W.tick(1)
		T.check(labels.Title.Text:find("LOS", 1, true) ~= nil, "Los-Nummer")
		T.check(labels.Lot.Text:find("Vektor RS Goldstück", 1, true) ~= nil, "Modellname")
		T.check(labels.Bid.Text:find("Startgebot", 1, true) ~= nil, "Startgebot")
		T.check(labels.Time.Text:find("Restzeit", 1, true) ~= nil, "Restzeit")
		W.bid(a, lot)
		W.tick(1)
		T.check(labels.Bid.Text:find("Anna", 1, true) ~= nil, "Höchstbietende sichtbar")
		W.runUntilEnded(lot)
		W.tick(1)
		T.check(labels.Bid.Text:find("Zuschlag", 1, true) ~= nil, "Zuschlag: " .. labels.Bid.Text)
		-- ohne Bildschirm: kein Fehler, keine Warnung
		local function auctionWarnings()
			local n = 0
			for _, w in ipairs(g:Warnings()) do
				if tostring(w):find("[Auktion]", 1, true) then
					n += 1
				end
			end
			return n
		end
		local warnBefore = auctionWarnings()
		part:Destroy()
		W.run(20)
		T.eq(auctionWarnings(), warnBefore, "keine Warnung ohne Bildschirm")
		T.eq(auctionWarnings(), 0, "keine Auktions-Warnungen")
		W.done(T)
	end },

	---------------------------------------------------------------- Echter Weg (nach der Verkabelung)
	{ "Verkabelung (sobald MiniNet die Auktions-Aktionen kennt): Remotes.Command, Zuschlag, Speichern, Verlassen", function(T, H)
		local g = H.Garage()
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.Actions.mini_auction_consign then
			T.check(true, "noch nicht verkabelt")
			return
		end
		T.eq(MiniNet.TabSet.auction, true, "Tab auction")
		local AR = g:MiniShared("AuctionRules")
		local CR = g:MiniShared("CarRules")
		local AS = g:MiniServer("AuctionService")
		local seller = g:Join(701, { name = "Sina" })
		local buyer = g:Join(702, { name = "Ben" })
		g:Advance(1)
		g:Send(seller, "hello")
		g:Send(buyer, "hello")
		g:Advance(0.5)
		local sd, bd = g:D(seller), g:D(buyer)
		T.check(g:Profile(seller).writable and g:Profile(buyer).writable, "Profile schreibbar (Mock-DataStore)")
		T.eq(type(sd.games.auction), "table", "games.auction angelegt")
		sd.level, bd.level = 10, 10
		bd.money = 100000
		local car = CR.AddCar(sd, CR.NewCar("komet", g:Now()))
		local start = AR.StartOptions(car)[1]
		T.eq(g:Act(seller, "mini_auction_consign", { id = car.id, start = start, duration = 120, rid = 11 }), "ok", "consign")
		T.eq(car.locked, true, "gesperrt")
		local lot
		for _, id in ipairs(AS.State().order) do
			local l = AS.Lot(id)
			if l.kind == "player" then
				lot = l
			end
		end
		T.check(lot ~= nil, "Los angelegt")
		g:Advance(0.6)
		T.eq(g:Act(buyer, "mini_auction_bid", { lot = lot.id, amount = start, rid = 12 }), "ok", "bid")
		T.eq(AR.Top(lot).userId, 702, "Ben vorn")
		T.check(#g:Notices(buyer, "auction_update") >= 1, "auction_update beim Käufer")
		T.check(#g:Notices(seller, "auction_update") >= 1, "auction_update beim Verkäufer")
		g:Advance(122)
		T.eq(lot.state, "sold", "verkauft")
		T.eq(CR.Find(sd, car.id), nil, "Auto beim Verkäufer weg")
		T.eq(#bd.games.cars, 1, "Auto beim Käufer")
		T.eq(bd.money, 100000 - start, "Ben zahlt")
		g:Advance(3)
		local rs, rb = g:Record(701), g:Record(702)
		T.check(rs ~= nil and rb ~= nil, "beide Datensätze gespeichert")
		T.eq(rs and #rs.data.games.cars, 0, "Verkäufer ohne Auto gespeichert")
		T.eq(rb and #rb.data.games.cars, 1, "Käufer mit Auto gespeichert")
		T.eq(rb and rb.data.money, bd.money, "Käufer-Geld gespeichert")
		T.eq(rs and rs.data.money, sd.money, "Verkäufer-Geld gespeichert")
		T.eq(#g:Notices(buyer, "auction_won"), 1, "auction_won")
		T.eq(#g:Notices(seller, "auction_sold"), 1, "auction_sold")
		g:Advance(1)
		local snap = g:MiniSnapshot(buyer)
		T.check(snap ~= nil and type(snap.auction) == "table" and snap.auction.won == 1, "Snapshot auction.won")
		-- Ben liefert weiter ein, Sina bietet, Ben verlässt den Server: Abbruch, entsperrt gespeichert
		sd.money = 100000
		local mine = bd.games.cars[1]
		g:Advance(1)
		T.eq(g:Act(buyer, "mini_auction_consign", { id = mine.id, start = AR.StartOptions(mine)[1], duration = 300, rid = 13 }), "ok", "consign 2")
		local lot2
		for _, id in ipairs(AS.State().order) do
			local l = AS.Lot(id)
			if l.kind == "player" and l.state == "open" then
				lot2 = l
			end
		end
		T.check(lot2 ~= nil and lot2.sellerId == 702, "zweites Los")
		g:Advance(0.6)
		T.eq(g:Act(seller, "mini_auction_bid", { lot = lot2.id, amount = lot2.start, rid = 14 }), "ok", "bid 2")
		g:Leave(buyer)
		g:Advance(3)
		T.eq(lot2.state, "canceled", "abgebrochen")
		local rb2 = g:Record(702)
		T.eq(rb2 and rb2.data.games.cars[1] and rb2.data.games.cars[1].locked, false, "entsperrt gespeichert")
		T.eq(sd.money, 100000, "Sina zahlt nichts")
		-- Transacting blockiert Auktions-Aktionen (request())
		g:Profile(seller).transacting = true
		T.eq(g:Act(seller, "mini_auction_bid", { lot = lot2.id, amount = 1, rid = 15 }), "dropped", "während transacting verworfen")
		g:Profile(seller).transacting = false
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
		for _, w in ipairs(g:Warnings()) do
			T.check(not tostring(w):find("[Auktion]", 1, true) and not tostring(w):find("mini_auction", 1, true), "Warnung: " .. tostring(w))
		end
	end },

	{ "Verkabelung Client (sobald der Tab auction existiert): Tab zeigt das Los, Gebot über den echten Weg", function(T, H)
		local g = H.Garage()
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.TabSet.auction then
			T.check(true, "noch nicht verkabelt")
			return
		end
		local AR = g:MiniShared("AuctionRules")
		local AS = g:MiniServer("AuctionService")
		local p = g:Join(1101, { name = "Tina" })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(2)
		local d = g:D(p)
		d.level, d.money = 50, 1000000
		g:MiniState(p).dirty = true -- neuer Snapshot mit Level und Guthaben
		local lot = AS.StartNpcLot("komet_rally", g:Now())
		T.check(lot ~= nil, "NPC-Los")
		g:Advance(1)
		local MiniClient = g:ClientModule(p, "Mini.MiniClient")
		local MiniUI = g:ClientModule(p, "Mini.MiniUI")
		g:InClient(p, function()
			MiniClient.Open("auction")
		end)
		g:Advance(0.5)
		T.check(g:FindGui(p, "Komet C1 Rallye") ~= nil, "Los im Tab sichtbar")
		local button = g:FindGui(p, function(x)
			return x.Name == "NpcBieten" and x:IsA("TextButton")
		end)
		T.check(button ~= nil, "Bieten-Knopf sichtbar")
		g:Advance(0.35)
		g:Click(button)
		g:Advance(0.05)
		if MiniUI.Shade and MiniUI.Shade.Visible then
			g:Advance(0.35)
			g:Click(MiniUI.ConfirmYes)
		end
		g:Advance(0.6)
		local top = AR.Top(lot)
		T.check(top ~= nil and top.userId == 1101 and top.amount == lot.start, "Gebot kam über Remotes.Command an")
		T.check(g:FindGui(p, "Tina") ~= nil, "eigenes Gebot im Verlauf")
		for _, e in ipairs(g:Errors()) do
			T.check(not tostring(e):find("Auction", 1, true), "Fehler: " .. tostring(e))
		end
		for _, w in ipairs(g:Warnings()) do
			T.check(not tostring(w):find("auction", 1, true) and not tostring(w):find("Auktion", 1, true), "Warnung: " .. tostring(w))
		end
	end },

	---------------------------------------------------------------- AuctionUI (Client)
	{ "AuctionUI: Aufbau, NPC-Los, Spieler-Auktionen, Einliefern – nur Absichten", function(T, H)
		local g = H.Garage()
		local p = g:Join(1001, { name = "Tester" })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(1.5)
		local sent = {}
		local rec = {
			Send = function(action, payload)
				payload = payload or {}
				local n = 0
				for k, v in pairs(payload) do
					n += 1
					local t = type(v)
					T.check(t == "string" or t == "number" or t == "boolean", action .. ": flaches Feld " .. k)
				end
				T.check(n <= 9, action .. ": höchstens 9 Felder")
				table.insert(sent, { action, payload })
				return #sent
			end,
		}
		rec.SendRaw = rec.Send
		local function last(name)
			for i = #sent, 1, -1 do
				if sent[i][1] == name then
					return sent[i][2]
				end
			end
			return nil
		end
		local MiniUI = g:ClientModule(p, "Mini.MiniUI")
		local mod = g:ClientModule(p, "Mini.AuctionUI")
		local toasts = {}
		local page = g:InClient(p, function()
			local gui = Instance.new("ScreenGui")
			gui.Name = "AuktionTest"
			gui.ResetOnSpawn = false
			gui.Parent = p.PlayerGui
			local frame = MiniUI.Frame(gui, { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(0, 338, 0, 0) })
			MiniUI.List(frame, 12)
			mod.Build(frame, {
				UI = MiniUI, Remote = rec,
				Toast = function(text)
					table.insert(toasts, text)
				end,
				Close = function() end,
			})
			return frame
		end)
		T.check(page ~= nil, "Seite gebaut")
		local now = g:Now()
		local snapshot = {
			credits = 150000, level = 12, auction = { won = 2, sold = 1 },
			cars = {
				{ id = 7, model = "komet", name = "Komet C1", body = "compact", paint = 1, rims = 1, glow = 0, spoiler = false,
					engine = 1, gearbox = 0, tires = 0, suspension = 0, nitro = 0, locked = false, value = 4500 },
				{ id = 8, model = "nord", name = "Nord R4", body = "sedan", paint = 3, rims = 1, glow = 0, spoiler = false,
					engine = 0, gearbox = 0, tires = 0, suspension = 0, nitro = 0, locked = true, value = 24000 },
			},
		}
		local update = {
			kind = "auction_update", now = now, you = { userId = 1001, writable = true },
			rules = { fee = 0.05, durations = { 120, 300, 600 }, extend = 15 },
			lots = {
				{ id = 3, kind = "npc", model = "vektor_gold", name = "Vektor RS Goldstück", body = "sport", level = 10, special = true,
					paint = 8, rims = 2, glow = 6, spoiler = true, value = 140000, start = 84000, maxBid = 420000, minBid = 90000,
					step = 5000, top = 85000, topName = "Sammler Konrad", topUserId = 0, topNpc = true, bidCount = 2,
					history = { { name = "Sammler Konrad", amount = 85000, npc = true }, { name = "Tester", amount = 84000, npc = false, userId = 1001 } },
					npcs = { { name = "Sammler Konrad", styleName = "Kenner", hint = "steigt bei etwa 90–105 % des Richtwerts aus", out = false, leading = true } },
					sellerId = 0, sellerName = "", startedAt = now - 30, endsAt = now + 90, state = "open" },
				{ id = 4, kind = "player", model = "atlas", name = "Atlas X", body = "suv", level = 1, paint = 5, rims = 1, glow = 0,
					spoiler = false, value = 48000, start = 12000, maxBid = 144000, minBid = 12000, step = 1000, top = 0, topName = "",
					topUserId = 0, topNpc = false, bidCount = 0, history = {}, npcs = {}, sellerId = 55, sellerName = "Sina",
					startedAt = now - 10, endsAt = now + 110, state = "open" },
			},
		}
		g:InClient(p, function()
			mod.Render(snapshot)
			mod.OnNotice(update)
			mod.Step()
		end)
		local function findText(pattern)
			for _, x in ipairs(page:GetDescendants()) do
				if (x:IsA("TextLabel") or x:IsA("TextButton")) and type(x.Text) == "string" and x.Text:find(pattern, 1, true) and H.Mock.IsGuiVisible(x) then
					return x
				end
			end
			return nil
		end
		T.check(findText("Vektor RS Goldstück") ~= nil, "NPC-Los sichtbar")
		T.check(findText("Sammler Konrad") ~= nil, "NPC-Bieter sichtbar")
		T.check(findText("Richtwerts") ~= nil, "Limit-Hinweis lesbar")
		T.check(findText("Atlas X") ~= nil, "Spieler-Auktion sichtbar")
		T.check(findText("Sina") ~= nil, "Verkäufer sichtbar")
		-- Klick (mit 0,3-s-Entprellung) und ggf. Bestätigung im Dialog
		local function clickConfirm(button)
			g:Advance(0.35)
			g:Click(button)
			g:Advance(0.05)
			if MiniUI.Shade and MiniUI.Shade.Visible then
				g:Advance(0.35)
				g:Click(MiniUI.ConfirmYes)
				g:Advance(0.05)
			end
		end
		-- Bieten auf das NPC-Los (Mindestgebot)
		local bidButton = page:FindFirstChild("NpcBieten", true)
		T.check(bidButton ~= nil, "Bieten-Knopf")
		clickConfirm(bidButton)
		local b = last("mini_auction_bid")
		T.check(b ~= nil and b.lot == 3 and b.amount == 90000, "Gebot = Mindestgebot als Absicht")
		-- bis zur Antwort des Servers ist der Knopf gesperrt (kein Doppelgebot)
		sent = {}
		clickConfirm(bidButton)
		T.eq(last("mini_auction_bid"), nil, "gesperrt bis zur Antwort")
		g:InClient(p, function()
			mod.OnNotice(update) -- Antwort des Servers (hier unverändert)
		end)
		-- Plus: ein Schritt mehr (mit Bestätigung)
		sent = {}
		g:Advance(0.35)
		g:Click(page:FindFirstChild("NpcPlus", true))
		clickConfirm(bidButton)
		local b2 = last("mini_auction_bid")
		T.check(b2 ~= nil and b2.amount == 95000, "Sprung um einen Schritt: " .. tostring(b2 and b2.amount))
		-- Spieler-Auktion: Bieten (Mindestgebot)
		sent = {}
		local row = page:FindFirstChild("Los_4", true)
		T.check(row ~= nil, "Zeile der Spieler-Auktion")
		local rowButton = row and row:FindFirstChild("Bieten", true)
		T.check(rowButton ~= nil, "Bieten in der Zeile")
		clickConfirm(rowButton)
		local b3 = last("mini_auction_bid")
		T.check(b3 ~= nil and b3.lot == 4 and b3.amount == 12000, "Gebot auf Spieler-Auktion")
		-- Einliefern: nur freie Autos, Startstufe, Laufzeit
		sent = {}
		local consign = page:FindFirstChild("Einliefern", true)
		T.check(consign ~= nil, "Einliefern-Knopf")
		clickConfirm(consign)
		local c = last("mini_auction_consign")
		local AR = g:MiniShared("AuctionRules")
		T.check(c ~= nil and c.id == 7, "freies Auto gewählt (gesperrtes übersprungen)")
		local opts = AR.StartOptions({ model = "komet", engine = 1, gearbox = 0, tires = 0, suspension = 0, nitro = 0 })
		local okStart = false
		for _, v in ipairs(opts) do
			if c and c.start == v then
				okStart = true
			end
		end
		T.check(okStart, "Startgebot ist eine erlaubte Stufe")
		T.check(c ~= nil and AR.ValidDuration(c.duration) ~= nil, "erlaubte Laufzeit")
		-- nächstes Auto: das gesperrte wird übersprungen, es bleibt bei Id 7
		g:Advance(0.35)
		g:Click(page:FindFirstChild("AutoWeiter", true))
		sent = {}
		clickConfirm(consign)
		local c2 = last("mini_auction_consign")
		T.check(c2 ~= nil and c2.id == 7, "gesperrtes Auto nie angeboten")
		-- ohne Speicherprofil: Einliefern gesperrt
		local upd2 = table.clone(update)
		upd2.you = { userId = 1001, writable = false }
		g:InClient(p, function()
			mod.OnNotice(upd2)
			mod.Step()
		end)
		sent = {}
		clickConfirm(consign)
		T.eq(last("mini_auction_consign"), nil, "kein Einliefern ohne Speicherprofil")
		T.check(findText("gespeichertem Profil") ~= nil, "Hinweis zum Speicherprofil")
		-- Ergebnis-Hinweise
		g:InClient(p, function()
			mod.OnNotice({ kind = "auction_won", lot = 3, model = "vektor_gold", name = "Vektor RS Goldstück", amount = 95000 })
			mod.Step()
		end)
		T.check(findText("Zuschlag") ~= nil, "Zuschlag angezeigt")
		-- keine Fehler aus AuctionUI
		for _, e in ipairs(g:Errors()) do
			T.check(not tostring(e):find("AuctionUI", 1, true), "Fehler: " .. tostring(e))
		end
		for _, w in ipairs(g:Warnings()) do
			T.check(not tostring(w):find("AuctionUI", 1, true), "Warnung: " .. tostring(w))
		end
	end },
}
