-- B-002: gestrichener Bieter (Garage voll, Level, beschäftigt, Profil) bot erneut den Höchstbetrag, sperrte alle aus und
-- wurde beim Zuschlag still übergangen -> Komplize gewann zum Startgebot. Hilfen wie in tests/test_auction.lua.
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

-- Garage bis auf `free` Plätze füllen
local function fillGarage(W, d, free)
	while #d.games.cars < W.CC.MaxCars - (free or 0) do
		giveCar(W.g, d, "komet")
	end
end

return {
	{ "B-002 Spieler-Los: gestrichener Bieter darf nicht erneut bieten und sperrt niemanden aus", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local x, xd = W.join(2, "Xaver", 1000000, 10)
		local c, cd = W.join(3, "Chris", 1000000, 10)
		local e, ed = W.join(4, "Eva", 1000000, 10)
		local lot = W.consign(s, giveCar(W.g, sd, "komet"), 1, 120)
		T.check(lot ~= nil, "Los eingeliefert")
		fillGarage(W, xd, 1)
		W.bid(x, lot, lot.start)
		T.eq(W.AR.Top(lot).userId, 2, "Xaver vorn")
		fillGarage(W, xd, 0) -- Garage beim Zuschlag voll
		W.run(lot.endsAt - W.t + 1)
		T.eq(lot.state, "open", "Gebot gestrichen: Los läuft weiter")
		T.eq(lot.skipped[2], "garage", "Xaver gestrichen (Garage)")
		T.eq(#lot.bids, 0, "Xavers Gebote entfernt")
		-- Xaver macht Platz, Komplize bietet das Startgebot, Xaver will mit dem Höchstbetrag alle aussperren
		W.CR.RemoveCar(xd, xd.games.cars[#xd.games.cars].id)
		W.bid(c, lot, lot.start)
		T.eq(W.AR.Top(lot).userId, 3, "Chris bietet das Startgebot")
		W.bid(x, lot, lot.maxBid)
		T.eq(W.AR.Top(lot).userId, 3, "Xavers neues Gebot wird nicht angenommen")
		T.eq(#lot.bids, 1, "kein Gebot von Xaver im Los")
		T.check(W.toasted(x, "nicht mehr bieten"), "Xaver bekommt einen Hinweis")
		local ok, err = W.AR.CheckBid(lot, { userId = 2, level = 10, money = 1000000, cars = 0, writable = true }, lot.maxBid, W.t)
		T.eq(ok, false, "CheckBid lehnt Gestrichene ab")
		T.check(err ~= nil and err == W.AR.Text.struck, "mit dem passenden Text")
		-- ehrliche Bieterin ist nicht ausgesperrt
		W.bid(e, lot)
		T.eq(W.AR.Top(lot).userId, 4, "Eva kann überbieten (kein „Höchstgebot erreicht“)")
		-- Übergang: Xaver verlässt den Server und kommt wieder -> bleibt für dieses Los gestrichen
		W.leave(x)
		local x2 = W.join(2, "Xaver", 1000000, 10)
		W.bid(x2, lot, lot.maxBid)
		T.eq(W.AR.Top(lot).userId, 4, "auch nach erneutem Beitritt kein Gebot von Xaver")
		W.runUntilEnded(lot)
		T.eq(lot.state, "sold", "verkauft")
		T.eq(lot.result and lot.result.userId, 4, "Zuschlag an die Höchstbietende, nicht an den Komplizen")
		T.check(lot.result and lot.result.amount > lot.start, "nicht zum Startgebot")
		T.eq(countModel(cd, "komet"), 0, "Chris bekommt nichts")
		T.check((lot.reopens or 0) <= W.AR.MaxReopens, "Verlängerungen begrenzt")
		W.done(T)
	end },

	{ "B-002 NPC-Los: gestrichener Bieter kann NPCs nicht mit dem Höchstbetrag aussperren", function(T, H)
		local W = world(H)
		local x, xd = W.join(2, "Xaver", 1000000, 10)
		local c, cd = W.join(3, "Chris", 1000000, 10)
		local lot = W.AS.StartNpcLot("komet_rally", W.t)
		T.check(lot ~= nil, "NPC-Los komet_rally")
		fillGarage(W, xd, 1)
		W.bid(x, lot, lot.maxBid) -- sofort am Höchstbetrag: keine NPC-Gebote
		T.eq(W.AR.Top(lot).userId, 2, "Xaver am Höchstbetrag")
		fillGarage(W, xd, 0)
		W.run(lot.endsAt - W.t + 1)
		T.eq(lot.state, "open", "Gebot gestrichen: Los läuft weiter")
		T.eq(lot.skipped[2], "garage", "Xaver gestrichen (Garage)")
		T.eq(#lot.bids, 0, "keine Gebote mehr im Los")
		W.CR.RemoveCar(xd, xd.games.cars[#xd.games.cars].id)
		W.bid(c, lot, lot.start)
		W.bid(x, lot, lot.maxBid)
		T.eq(W.AR.Top(lot).userId, 3, "Xavers neues Gebot wird nicht angenommen")
		T.check(W.toasted(x, "nicht mehr bieten"), "Xaver bekommt einen Hinweis")
		W.runUntilEnded(lot)
		T.eq(lot.state, "sold", "zugeschlagen")
		local npcBids = 0
		for _, b in ipairs(lot.bids) do
			npcBids += b.npc and 1 or 0
		end
		T.check(npcBids > 0, "NPCs haben wieder mitgeboten")
		T.check(lot.result and lot.result.amount > lot.start, "nicht zum Startgebot")
		T.check(not (lot.result and lot.result.userId == 3 and lot.result.amount == lot.start), "Komplize gewinnt nicht zum Startgebot")
		T.eq(countModel(xd, "komet_rally"), 0, "Xaver bekommt nichts")
		W.done(T)
	end },

	{ "B-002 Verlängerung: Streichung gilt über die ganze Restlaufzeit, keine weitere Verlängerung durch den Gestrichenen", function(T, H)
		local W = world(H)
		local s, sd = W.join(1, "Sina", 0, 10)
		local x, xd = W.join(2, "Xaver", 1000000, 10)
		local lot = W.consign(s, giveCar(W.g, sd, "komet"), 1, 120)
		fillGarage(W, xd, 1)
		W.bid(x, lot, lot.start)
		fillGarage(W, xd, 0)
		W.run(lot.endsAt - W.t + 1)
		T.eq(lot.reopens, 1, "erste Verlängerung")
		W.CR.RemoveCar(xd, xd.games.cars[#xd.games.cars].id)
		-- Xaver versucht es immer wieder: kein Gebot, keine weitere Verlängerung
		for _ = 1, 6 do
			W.bid(x, lot, lot.maxBid)
			W.run(10)
		end
		T.eq(#lot.bids, 0, "kein Gebot von Xaver angenommen")
		W.runUntilEnded(lot, 120)
		T.eq(lot.state, "unsold", "ohne gültiges Gebot endet das Los unverkauft")
		T.eq(lot.reopens, 1, "keine weitere Verlängerung durch den Gestrichenen")
		T.eq(countModel(sd, "komet"), 1, "Auto bleibt beim Verkäufer")
		T.eq(W.CR.Find(sd, lot.carId).locked, false, "und ist wieder frei")
		-- auf einem anderen Los darf Xaver normal bieten
		W.t += W.AR.ConsignCooldown
		local lot2 = W.consign(s, sd.games.cars[1], 1, 120)
		T.check(lot2 ~= nil, "zweites Los")
		if lot2 then
			W.bid(x, lot2, lot2.start)
			T.eq(W.AR.Top(lot2) and W.AR.Top(lot2).userId, 2, "Streichung gilt nur für das betroffene Los")
		end
		W.done(T)
	end },
}
