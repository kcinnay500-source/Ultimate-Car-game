-- AuctionRules: Auktionshaus als reine Funktionen (PHASE2_CONTRACT §1, §3, §4, §6). Keine Instanzen, keine Yields;
-- Server (AuctionService) und Client (AuctionUI) nutzen dieselben Zahlen.
--
-- Lose (nur in der Server-Sitzung, nie im Profil):
--   lot = { id, kind = "npc" | "player", model, name, brand, body, level, special,
--           car = { model, paint, rims, glow, spoiler, engine, gearbox, tires, suspension, nitro, bought, locked },
--           value (Richtwert), start, maxBid, sellerId (0 = NPC-Auktion), sellerName, carId (Auto-Id beim Verkäufer),
--           startedAt, endsAt, hardEnd, changedAt, state = "open" | "closing" | "sold" | "unsold" | "canceled",
--           bids = { {userId, name, amount, at, npc = <Index in npcs> | nil}, ... }  (streng steigend),
--           npcs = { {name, style, limit, think}, ... }, skipped = { [userId] = Grund }, result, endedAt, reason }
-- Profil (d.games.auction): { won = <int>, sold = <int> }
--
-- NPC-Bieter (fair und nachvollziehbar): Limit und Bedenkzeit stehen beim Öffnen des Loses fest (aus dem Seed, nie
-- abhängig von Spielern oder deren Guthaben). Ein NPC bietet nur, wenn er nicht vorn liegt, frühestens `think`
-- Sekunden nach der letzten Änderung, immer genau das Mindestgebot und nie über seinem Limit. Die Stil-Stufe
-- (vorsichtig / Kenner / Liebhaber) samt Limit-Spanne wird offen angezeigt; wer das Limit überschreitet, sieht
-- „steigt aus“. Gebote in den letzten 15 Sekunden verlängern für alle gleich (höchstens bis hardEnd).
local CarCatalog = require(script.Parent:WaitForChild("CarCatalog"))
local CarRules = require(script.Parent:WaitForChild("CarRules"))
local MiniLocale = require(script.Parent:WaitForChild("MiniLocale"))

local AuctionRules = {}

local MAX_SAFE = 2 ^ 53

-- MiniRules erst beim ersten Geld-Aufruf laden (MiniRules.LoadGames lädt dieses Modul; keine Ringabhängigkeit)
local MiniRules
local function mini()
	if not MiniRules then
		MiniRules = require(script.Parent:WaitForChild("MiniRules"))
	end
	return MiniRules
end

---------------------------------------------------------------- Stellschrauben
AuctionRules.FeeShare = 0.05 -- Gebühr des Verkäufers bei Spieler-Auktionen (vom Endpreis)
AuctionRules.Durations = { 120, 300, 600 } -- erlaubte Laufzeiten einer Spieler-Auktion (Sekunden)
AuctionRules.StartShares = { 0.25, 0.5, 0.75, 1.0 } -- Startgebot-Stufen als Anteil am Richtwert (Wert + Tuning)
AuctionRules.MinStart = 100
AuctionRules.StepShare = 0.05 -- Mindestschritt: 5 % des aktuellen Gebots, auf „runde“ Werte gerundet
AuctionRules.MinStep = 50
AuctionRules.MaxBidFactor = 3 -- ein Gebot höchstens 3× Richtwert (Vertipper, Geldschieben)
AuctionRules.ExtendWindow = 15 -- Gebot in den letzten 15 s: Restzeit wieder 15 s
AuctionRules.MaxExtend = 120 -- höchstens 2 Minuten Verlängerung insgesamt
AuctionRules.MaxPlayerLots = 6 -- gleichzeitige Spieler-Auktionen je Server
AuctionRules.MaxLotsPerSeller = 1
AuctionRules.ConsignCooldown = 10
AuctionRules.SettleWaitMax = 45 -- so lange wartet der Zuschlag auf ein Profil mitten in einem Robux-Kauf
AuctionRules.ResultSeconds = 30 -- beendete Lose bleiben so lange sichtbar
AuctionRules.HistorySize = 6

AuctionRules.Npc = {
	duration = 180, -- Laufzeit einer NPC-Versteigerung
	breakSeconds = 60, -- Pause bis zum nächsten Los
	firstDelay = 20, -- erstes Los nach Serverstart
	startShare = 0.6, -- Startgebot = 60 % des Richtwerts
	collectorChance = 0.5, -- Anteil der Lose mit einem „Liebhaber“
	names = {
		"Sammler Konrad", "Oldtimer-Olga", "Rennfahrer Jens", "Händlerin Mira",
		"Tüftler Paul", "Baronin von Blech", "Garagen-Gerd", "Chromjägerin Lea",
	},
}
-- Stil-Stufen: Limit-Spanne (Anteil am Richtwert) und Bedenkzeit in Sekunden
AuctionRules.Styles = {
	cautious = { name = "vorsichtig", lo = 0.70, hi = 0.85, think = { 6, 9 } },
	expert = { name = "Kenner", lo = 0.90, hi = 1.05, think = { 5, 8 } },
	collector = { name = "Liebhaber", lo = 1.05, hi = 1.20, think = { 4, 7 } },
}

local TEXT = {
	ended = "Diese Auktion ist schon beendet.",
	own = "Auf dein eigenes Auto kannst du nicht bieten.",
	writable = "Spieler-Auktionen gehen nur mit gespeichertem Profil (nicht in Studio oder einer Ersatzsitzung).",
	invalid = "Ungültiges Gebot.",
	top = "Du hast bereits das Höchstgebot.",
	capped = "Das Höchstgebot für dieses Los ist erreicht.",
	money = "Nicht genug Credits für dieses Gebot.",
}
AuctionRules.Text = TEXT

---------------------------------------------------------------- Zahlen
local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
AuctionRules.Finite = finite

local function loadInt(v)
	if not finite(v) or v < 0 then
		return 0
	end
	return math.floor(math.min(v, MAX_SAFE))
end

-- Aufrunden auf 1 / 2 / 2,5 / 5 × 10^n (Gebotsschritte)
function AuctionRules.Nice(x)
	if not finite(x) or x <= 0 then
		return 0
	end
	local mag = 10 ^ math.floor(math.log10(x))
	local m = x / mag
	local nice
	if m <= 1 then
		nice = 1
	elseif m <= 2 then
		nice = 2
	elseif m <= 2.5 then
		nice = 2.5
	elseif m <= 5 then
		nice = 5
	else
		nice = 10
	end
	return math.floor(nice * mag + 0.5)
end

-- Preis auf zwei gültige Stellen (Hälfte der zweiten Stelle), mindestens 10: 3086 -> 3100, 228000 -> 230000
function AuctionRules.RoundPrice(x)
	if not finite(x) or x <= 0 then
		return 0
	end
	local unit = math.max(10, 10 ^ (math.floor(math.log10(x)) - 1) / 2)
	return math.max(unit, math.floor(x / unit + 0.5) * unit)
end

function AuctionRules.Step(price)
	return math.max(AuctionRules.MinStep, AuctionRules.Nice((finite(price) and price or 0) * AuctionRules.StepShare))
end

-- Gebühr (gerundet) und Auszahlung an den Verkäufer
function AuctionRules.Fee(amount)
	if not finite(amount) or amount <= 0 then
		return 0, 0
	end
	local fee = math.floor(amount * AuctionRules.FeeShare + 0.5)
	return fee, amount - fee
end

-- Lesbare Restzeit: 150 -> "2:30"
function AuctionRules.Clock(seconds)
	if not finite(seconds) or seconds < 0 then
		seconds = 0
	end
	seconds = math.ceil(seconds)
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

---------------------------------------------------------------- Profil (d.games.auction)
function AuctionRules.Default()
	return { won = 0, sold = 0 }
end

-- raw = gespeichertes d.games.auction (auch das ganze games-Table wird erkannt). Idempotent, NaN/negativ -> 0.
function AuctionRules.Load(raw, d, now)
	if type(raw) == "table" and type(raw.auction) == "table" and raw.won == nil and raw.sold == nil then
		raw = raw.auction
	end
	local out = AuctionRules.Default()
	if type(raw) ~= "table" then
		return out
	end
	out.won = loadInt(raw.won)
	out.sold = loadInt(raw.sold)
	return out
end

function AuctionRules.Stats(d)
	local g = d.games
	if type(g.auction) ~= "table" then
		g.auction = AuctionRules.Default()
	end
	return g.auction
end

-- Snapshot-Feld `auction` (PHASE2_CONTRACT §5; der öffentliche Zustand kommt über auction_update)
function AuctionRules.SnapshotFields(d)
	local st = type(d) == "table" and type(d.games) == "table" and d.games.auction
	st = type(st) == "table" and st or AuctionRules.Default()
	return { won = loadInt(st.won), sold = loadInt(st.sold) }
end

---------------------------------------------------------------- Zufall (deterministisch, rein)
local function rng(seed)
	local s = math.floor(math.abs(finite(seed) and seed or 1)) % 2147483646 + 1
	return function()
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end
AuctionRules.Rng = rng

---------------------------------------------------------------- Autos, Richtwert, Startgebot
-- Richtwert eines eigenen Autos: Modellwert + bezahltes Tuning (wie der Rückkauf, aber ohne Abschlag)
function AuctionRules.RefValue(car)
	if type(car) ~= "table" or not CarCatalog.Model(car.model) then
		return 0
	end
	return CarRules.Value(car) + CarRules.TuningValue(car)
end

function AuctionRules.StartOptions(car)
	local ref = AuctionRules.RefValue(car)
	local out, seen = {}, {}
	for _, share in ipairs(AuctionRules.StartShares) do
		local v = math.max(AuctionRules.MinStart, AuctionRules.RoundPrice(ref * share))
		if not seen[v] then
			seen[v] = true
			table.insert(out, v)
		end
	end
	table.sort(out)
	return out
end

-- start = Betrag einer erlaubten Stufe (oder deren Index 1..n). Rückgabe: Betrag oder nil
function AuctionRules.ValidStart(car, start)
	if not finite(start) or start % 1 ~= 0 then
		return nil
	end
	local options = AuctionRules.StartOptions(car)
	if start >= 1 and start <= #options then
		return options[start]
	end
	for _, v in ipairs(options) do
		if v == start then
			return v
		end
	end
	return nil
end

function AuctionRules.ValidDuration(seconds)
	for _, v in ipairs(AuctionRules.Durations) do
		if v == seconds then
			return v
		end
	end
	return nil
end

local function carRecord(car)
	return {
		model = car.model, paint = car.paint, rims = car.rims, glow = car.glow, spoiler = car.spoiler == true,
		engine = car.engine or 0, gearbox = car.gearbox or 0, tires = car.tires or 0, suspension = car.suspension or 0,
		nitro = car.nitro or 0, bought = car.bought or 0, locked = false,
	}
end

---------------------------------------------------------------- Lose anlegen
local function baseLot(id, kind, m, car, now, duration)
	return {
		id = id, kind = kind, model = m.id, name = m.name, brand = m.brand, body = m.body, level = m.level or 1,
		special = m.special == true, car = car, startedAt = now, endsAt = now + duration,
		hardEnd = now + duration + AuctionRules.MaxExtend, changedAt = now, state = "open", bids = {}, npcs = {},
		skipped = {}, sellerId = 0, sellerName = "", carId = 0,
	}
end

-- Spieler-Auktion. seller = { userId, name }, car = Datensatz aus d.games.cars (wird kopiert)
function AuctionRules.NewPlayerLot(id, seller, car, start, duration, now)
	local m = CarCatalog.Model(car and car.model)
	if not m then
		return nil
	end
	local lot = baseLot(id, "player", m, carRecord(car), now, duration)
	local ref = AuctionRules.RefValue(car)
	lot.value = ref
	lot.start = start
	lot.maxBid = math.max(start * AuctionRules.MaxBidFactor, AuctionRules.RoundPrice(ref * AuctionRules.MaxBidFactor))
	lot.sellerId = seller.userId
	lot.sellerName = seller.name or ""
	lot.carId = car.id
	return lot
end

-- Nächstes Sondermodell der NPC-Reihe (nie zweimal hintereinander dasselbe)
function AuctionRules.PickNpcModel(serial, seed, avoid)
	local list = CarCatalog.Specials
	if #list == 0 then
		return nil
	end
	local r = rng((seed or 1) * 7919 + (serial or 0) * 104729)
	local i = math.floor(r() * #list) + 1
	if list[i].id == avoid and #list > 1 then
		i = i % #list + 1
	end
	return list[i].id
end

-- NPC-Versteigerung eines Sondermodells mit 2–3 NPC-Bietern (Limits und Bedenkzeiten aus dem Seed)
function AuctionRules.NewNpcLot(id, modelId, seed, now)
	local m = CarCatalog.Model(modelId)
	if not m then
		return nil
	end
	local N = AuctionRules.Npc
	local lot = baseLot(id, "npc", m, carRecord(CarRules.NewCar(m.id, 0)), now, N.duration)
	lot.value = m.value
	lot.start = AuctionRules.RoundPrice(m.value * N.startShare)
	lot.maxBid = AuctionRules.RoundPrice(m.value * AuctionRules.MaxBidFactor)
	local r = rng((seed or 1) * 31 + id * 7907)
	-- Namen mischen (Fisher-Yates mit dem Seed)
	local names = table.clone(N.names)
	for i = #names, 2, -1 do
		local j = math.floor(r() * i) + 1
		names[i], names[j] = names[j], names[i]
	end
	local styles = { "cautious", "expert" }
	if r() < N.collectorChance then
		table.insert(styles, "collector")
	end
	for i, key in ipairs(styles) do
		local st = AuctionRules.Styles[key]
		local share = st.lo + (st.hi - st.lo) * r()
		local think = st.think[1] + math.floor(r() * (st.think[2] - st.think[1] + 1))
		lot.npcs[i] = {
			name = names[i], style = key, limit = math.max(lot.start, AuctionRules.RoundPrice(m.value * share)),
			think = math.min(think, st.think[2]),
		}
	end
	return lot
end

---------------------------------------------------------------- Gebote
function AuctionRules.Top(lot)
	return lot.bids[#lot.bids]
end

function AuctionRules.MinBid(lot)
	local top = AuctionRules.Top(lot)
	if not top then
		return lot.start
	end
	return top.amount + AuctionRules.Step(top.amount)
end

function AuctionRules.IsOpen(lot, now)
	return lot.state == "open" and now < lot.endsAt
end

-- bidder = { userId, level, money, cars (Anzahl), writable }. Rückgabe: true | false, Meldung
function AuctionRules.CheckBid(lot, bidder, amount, now)
	if not AuctionRules.IsOpen(lot, now) then
		return false, TEXT.ended
	end
	if lot.kind == "player" then
		if bidder.userId == lot.sellerId then
			return false, TEXT.own
		end
		if not bidder.writable then
			return false, TEXT.writable
		end
	end
	if not finite(amount) or amount % 1 ~= 0 or amount <= 0 then
		return false, TEXT.invalid
	end
	local top = AuctionRules.Top(lot)
	if top and not top.npc and top.userId == bidder.userId then
		return false, TEXT.top
	end
	local minBid = AuctionRules.MinBid(lot)
	if minBid > lot.maxBid then
		return false, TEXT.capped
	end
	if amount < minBid then
		return false, "Das Mindestgebot ist jetzt " .. MiniLocale.Credits(minBid) .. "."
	end
	if amount > lot.maxBid then
		return false, "Höchstens " .. MiniLocale.Credits(lot.maxBid) .. " für dieses Los."
	end
	if (bidder.level or 1) < lot.level then
		return false, "Dafür brauchst du Level " .. lot.level .. "."
	end
	if (bidder.cars or 0) >= CarCatalog.MaxCars then
		return false, "Deine Garage ist voll (" .. CarCatalog.MaxCars .. " Autos)."
	end
	if not finite(bidder.money) or bidder.money < amount then
		return false, TEXT.money
	end
	return true
end

-- Trägt ein (geprüftes) Gebot ein und verlängert bei Bedarf. npc = Index in lot.npcs oder nil.
function AuctionRules.PlaceBid(lot, userId, name, amount, now, npc)
	local bid = { userId = npc and 0 or userId, name = name or "", amount = amount, at = now, npc = npc }
	table.insert(lot.bids, bid)
	lot.changedAt = now
	if lot.endsAt - now < AuctionRules.ExtendWindow then
		lot.endsAt = math.max(lot.endsAt, math.min(lot.hardEnd, now + AuctionRules.ExtendWindow))
	end
	return bid
end

-- Bieter verlässt den Server: alle seine Gebote fallen weg. Rückgabe: Anzahl entfernter Gebote
function AuctionRules.RemoveBidder(lot, userId, now)
	local removed = 0
	for i = #lot.bids, 1, -1 do
		local b = lot.bids[i]
		if not b.npc and b.userId == userId then
			table.remove(lot.bids, i)
			removed += 1
		end
	end
	if removed > 0 then
		lot.changedAt = now or lot.changedAt
	end
	return removed
end

---------------------------------------------------------------- NPC-Bieter
function AuctionRules.NpcOut(lot, i)
	local n = lot.npcs[i]
	local top = AuctionRules.Top(lot)
	if not n or (top and top.npc == i) then
		return false
	end
	return AuctionRules.MinBid(lot) > math.min(n.limit, lot.maxBid)
end

-- Welcher NPC bietet jetzt? Rückgabe: Index, Betrag | nil. Höchstens ein NPC je Aufruf.
function AuctionRules.NpcDecide(lot, now)
	if lot.kind ~= "npc" or not AuctionRules.IsOpen(lot, now) then
		return nil
	end
	local top = AuctionRules.Top(lot)
	local minBid = AuctionRules.MinBid(lot)
	if minBid > lot.maxBid then
		return nil
	end
	local best, bestAt
	for i, n in ipairs(lot.npcs) do
		if not (top and top.npc == i) and minBid <= n.limit then
			local at = lot.changedAt + n.think
			if now >= at and (bestAt == nil or at < bestAt) then
				best, bestAt = i, at
			end
		end
	end
	if not best then
		return nil
	end
	return best, minBid
end

---------------------------------------------------------------- Zuschlag
-- Bieter-Reihenfolge für den Zuschlag: je Bieter sein höchstes Gebot, absteigend
function AuctionRules.Candidates(lot)
	local out, seen = {}, {}
	for i = #lot.bids, 1, -1 do
		local b = lot.bids[i]
		local key = b.npc and ("npc" .. b.npc) or b.userId
		if not seen[key] then
			seen[key] = true
			table.insert(out, b)
		end
	end
	return out
end

-- Nächsthöheres gültiges Gebot. check(bid) -> "ok" | "wait" | Grund (ungültig, Bieter fällt für dieses Los raus).
-- NPC-Gebote sind immer gültig. Rückgabe: bid | nil, "wait" | nil
function AuctionRules.PickWinner(lot, check)
	lot.skipped = lot.skipped or {}
	for _, b in ipairs(AuctionRules.Candidates(lot)) do
		if b.npc then
			return b
		end
		if not lot.skipped[b.userId] then
			local verdict = check(b)
			if verdict == "ok" then
				return b
			elseif verdict == "wait" then
				return nil, "wait"
			end
			lot.skipped[b.userId] = type(verdict) == "string" and verdict or "invalid"
		end
	end
	return nil
end

-- Prüft den Käufer beim Zuschlag (Geld, Garage, Level). Rückgabe: "ok" | Grund
function AuctionRules.BuyerCheck(d, lot, amount)
	if type(d) ~= "table" or type(d.games) ~= "table" then
		return "profile"
	end
	if not finite(d.money) or d.money < amount then
		return "money"
	end
	local cars = type(d.games.cars) == "table" and #d.games.cars or 0
	if cars >= CarCatalog.MaxCars then
		return "garage"
	end
	if (finite(d.level) and d.level or 1) < lot.level then
		return "level"
	end
	return "ok"
end

local function finish(lot, state, now, result, reason)
	lot.state = state
	lot.endedAt = now
	lot.result = result
	lot.reason = reason
end

-- Abschluss ohne Übergabe: "unsold" (kein gültiges Gebot), NPC gewinnt ("sold", result.npc) oder "canceled"
function AuctionRules.Finish(lot, state, now, result, reason)
	if lot.state ~= "open" and lot.state ~= "closing" then
		return false
	end
	finish(lot, state, now, result, reason)
	return true
end

-- Abbruch einer Spieler-Auktion: Auto beim Verkäufer entsperren (sellerD darf nil sein)
function AuctionRules.Cancel(lot, sellerD, now, reason)
	if lot.state ~= "open" and lot.state ~= "closing" then
		return false
	end
	if sellerD and lot.kind == "player" then
		CarRules.SetLocked(sellerD, lot.carId, false)
	end
	finish(lot, "canceled", now, nil, reason)
	return true
end

-- Spieler-Auktion: Auto + Geld in einem Schritt (ohne Yield). Alles wird vor der ersten Änderung geprüft.
-- Rückgabe: true, { car (neuer Datensatz beim Käufer), amount, fee, payout } | false, Grund
function AuctionRules.Handover(lot, bid, buyerD, sellerD, now)
	if lot.kind ~= "player" or lot.state ~= "closing" then
		return false, "state"
	end
	if not bid or bid.npc or buyerD == sellerD or type(sellerD) ~= "table" then
		return false, "bid"
	end
	local car, index = CarRules.Find(sellerD, lot.carId)
	if not car or not car.locked or not CarRules.NormalizeCar(car) then
		return false, "car"
	end
	local amount = bid.amount
	local verdict = AuctionRules.BuyerCheck(buyerD, lot, amount)
	if verdict ~= "ok" then
		return false, verdict
	end
	local fee, payout = AuctionRules.Fee(amount)
	-- ab hier keine Abbrüche: ein Server-Schritt
	local record = CarRules.RemoveCar(sellerD, lot.carId)
	local newCar = CarRules.AddCar(buyerD, record)
	if not newCar then
		-- nach den Prüfungen unmöglich; zur Sicherheit unverändert zurücklegen
		table.insert(sellerD.games.cars, math.min(index, #sellerD.games.cars + 1), record)
		return false, "garage"
	end
	mini().AddMoney(buyerD, -amount)
	local paid = mini().AddMoney(sellerD, payout)
	AuctionRules.Stats(buyerD).won += 1
	AuctionRules.Stats(sellerD).sold += 1
	finish(lot, "sold", now, { userId = bid.userId, name = bid.name, amount = amount, npc = false })
	return true, { car = newCar, amount = amount, fee = fee, payout = paid }
end

-- NPC-Auktion, ein Spieler gewinnt: Geld ab, Sondermodell in die Garage (ein Schritt).
-- Rückgabe: true, { car, amount } | false, Grund
function AuctionRules.GrantNpcLot(lot, bid, buyerD, now)
	if lot.kind ~= "npc" or lot.state ~= "closing" then
		return false, "state"
	end
	if not bid or bid.npc then
		return false, "bid"
	end
	local verdict = AuctionRules.BuyerCheck(buyerD, lot, bid.amount)
	if verdict ~= "ok" then
		return false, verdict
	end
	local record = table.clone(lot.car)
	record.bought = finite(now) and math.max(0, math.floor(now)) or 0
	local car = CarRules.AddCar(buyerD, record)
	if not car then
		return false, "garage"
	end
	mini().AddMoney(buyerD, -bid.amount)
	AuctionRules.Stats(buyerD).won += 1
	finish(lot, "sold", now, { userId = bid.userId, name = bid.name, amount = bid.amount, npc = false })
	return true, { car = car, amount = bid.amount }
end

---------------------------------------------------------------- Öffentliche Ansicht (auction_update)
local function styleHint(st)
	return string.format("steigt bei etwa %d–%d %% des Richtwerts aus", math.floor(st.lo * 100 + 0.5), math.floor(st.hi * 100 + 0.5))
end

function AuctionRules.LotView(lot, now)
	local top = AuctionRules.Top(lot)
	local minBid = AuctionRules.MinBid(lot)
	local history = {}
	for i = #lot.bids, math.max(1, #lot.bids - AuctionRules.HistorySize + 1), -1 do
		local b = lot.bids[i]
		table.insert(history, { name = b.name, amount = b.amount, npc = b.npc ~= nil, userId = b.userId, at = b.at })
	end
	local npcs = {}
	for i, n in ipairs(lot.npcs) do
		local st = AuctionRules.Styles[n.style]
		table.insert(npcs, {
			name = n.name, style = n.style, styleName = st and st.name or n.style, hint = st and styleHint(st) or "",
			out = AuctionRules.NpcOut(lot, i), leading = top ~= nil and top.npc == i,
		})
	end
	local c = lot.car or {}
	local res = lot.result
	return {
		id = lot.id, kind = lot.kind, model = lot.model, name = lot.name, brand = lot.brand, body = lot.body,
		level = lot.level, special = lot.special,
		paint = c.paint, rims = c.rims, glow = c.glow, spoiler = c.spoiler,
		engine = c.engine, gearbox = c.gearbox, tires = c.tires, suspension = c.suspension, nitro = c.nitro,
		value = lot.value, start = lot.start, maxBid = lot.maxBid,
		minBid = minBid, step = AuctionRules.Step(top and top.amount or lot.start), capped = minBid > lot.maxBid,
		top = top and top.amount or 0, topName = top and top.name or "", topUserId = top and top.userId or 0,
		topNpc = top ~= nil and top.npc ~= nil, bidCount = #lot.bids, history = history, npcs = npcs,
		sellerId = lot.sellerId, sellerName = lot.sellerName,
		startedAt = lot.startedAt, endsAt = lot.endsAt, hardEnd = lot.hardEnd, state = lot.state,
		remaining = math.max(0, lot.endsAt - now), endedAt = lot.endedAt or 0,
		result = res and { name = res.name, amount = res.amount, npc = res.npc == true, userId = res.userId or 0 } or nil,
		reason = lot.reason,
	}
end

-- Kurzinfo zum nächsten NPC-Los
function AuctionRules.NextView(modelId, at)
	local m = CarCatalog.Model(modelId)
	if not m then
		return nil
	end
	return {
		model = m.id, name = m.name, body = m.body, level = m.level, value = m.value, at = at,
		start = AuctionRules.RoundPrice(m.value * AuctionRules.Npc.startShare),
		paint = m.paint, rims = m.rims, glow = m.glow, spoiler = m.spoiler,
	}
end

-- Regeln für die Anzeige (Client braucht sie nicht zu raten)
function AuctionRules.RulesView()
	return {
		fee = AuctionRules.FeeShare, durations = table.clone(AuctionRules.Durations), extend = AuctionRules.ExtendWindow,
		maxExtend = AuctionRules.MaxExtend, maxLots = AuctionRules.MaxPlayerLots, npcDuration = AuctionRules.Npc.duration,
		npcBreak = AuctionRules.Npc.breakSeconds,
	}
end

return AuctionRules
