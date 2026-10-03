--!nonstrict
-- PublicWorkshopService: die „Große Werkstatt“ am Westende der Spielermeile (Welt: City.Districts.Grosswerkstatt,
-- Stationen City.Stations.grosswerkstatt (Reparatur-Hallen) und City.Stations.teileankauf (Teile-Ankauf)).
-- Jeder Spieler darf sie nutzen; das Panel hebt hervor, was zum Startweg passt (Verkäufer: Autos reparieren,
-- Schrottplatz: Teile verkaufen, Werkstatt: −10 % auf Reparaturen).
--
-- Aktionen (MiniNet, flach, keine Beträge vom Client):
--   pw_open {}                         Ansicht schicken (mini_notice { kind = "pw", event = "open", … })
--   pw_repair { car = "<Auto-Id>" }    eigenes Auto reparieren: bezahlen (Credits), RepairSeconds warten, in der Nähe
--                                      bleiben; Zustand -> 100 %, Wertbonus bis GameConfig.PublicWorkshop.MaxBonus
--   pw_sell_parts { part, count }      Teile aus dem Lager verkaufen (heute: "altteile" = d.games.parts), besser als
--                                      beim Schrotthändler; füllt den Teile-Vorrat des Servers (Rabatt für alle)
-- Story-Ereignisse über api.storyEvent (sonst api.event): "pw_repair" { car, gain }, "pw_parts_sold" { part, count, value }.
--
-- Daten: d.games.pw = { cars = { ["<Auto-Id>"] = { b = Bonus in %, p = bezahlt (laufende Reparatur) } },
--                       day = "YYYY-MM-DD", sold = Teile heute, refund = Erstattung, repairs = n, partsSold = n }
-- (Tiefe 3 unter games; Load ist eine Whitelist). Der Anfangszustand eines Autos ist nicht gespeichert, sondern fest
-- aus Auto-Id und Modell berechnet (InitialCondition); erst die Reparatur speichert den Bonus.
-- Geld ändert sich nur in den Handlern (innerhalb von request()): bezahlt wird beim Start, die XP gibt es beim Start;
-- der Tick schließt die Reparatur nur ab (Zustand/Bonus, Story-Ereignis) – nie Geld. Wird ein bezahltes Auto vor dem
-- Ende verkauft, merkt sich das Profil eine Erstattung, die die nächste pw_*-Aktion auszahlt.
--
-- Schnittstelle (Verkabelung durch MiniService):
--   PublicWorkshopService.Register(Actions, api)      pw_open, pw_repair, pw_sell_parts
--   PublicWorkshopService.Init(ctx)                    optional (ctx.now)
--   PublicWorkshopService.OnJoin(ms, d, now)           Daten normalisieren, verwaiste Einträge aufräumen
--   PublicWorkshopService.Tick(ms, d, now) -> bool     laufende Reparatur: Abstand, Abschluss (true = Snapshot fällig)
--   PublicWorkshopService.OnLeave(ms)                  laufende Reparatur pausieren (bezahlt bleibt bezahlt)
--   PublicWorkshopService.ValueBonus(d, carId) -> n    Faktor ≥ 1 für den Verkaufspreis (Autohaus-Rückkauf)
--   PublicWorkshopService.OnCarSold(d, carId)          Eintrag nach dem Verkauf löschen (optional; Prune räumt sonst auf)
--   PublicWorkshopService.Default() / Load(raw, d, now)  für MiniRules.DefaultGames/LoadGames (games.pw)
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local CarCatalog = require(MiniShared:WaitForChild("CarCatalog"))
local CarRules = require(MiniShared:WaitForChild("CarRules"))
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))

local PublicWorkshopService = {}

local MAX_SAFE = 2 ^ 53
local MAX_RECORDS = 64
local MAX_ID_LENGTH = 12

PublicWorkshopService.NoticeKind = "pw"

PublicWorkshopService.Text = {
	noCity = "Die Große Werkstatt steht in der Open World an der Spielermeile.",
	farRepair = "Fahr oder lauf zur Großen Werkstatt am Westende der Spielermeile – dort wird repariert.",
	farParts = "Geh zum Teile-Ankauf an der Großen Werkstatt (Schalter neben der Halle).",
	busy = "In deiner Halle läuft schon eine Reparatur.",
	noCar = "Dieses Auto steht nicht (mehr) in deiner Garage.",
	locked = "Dieses Auto ist gerade in einer Auktion.",
	excluded = "Dein Startauto ist immer top in Schuss – es braucht keine Reparatur.",
	dlc = "Diese Sonderedition ist werkneu – sie braucht keine Reparatur.",
	done = "Dieses Auto ist schon top in Schuss. Eine zweite Reparatur bringt nichts.",
	small = "Eine Reparatur lohnt sich bei diesem Auto nicht.",
	money = "Für die Reparatur fehlen dir %s.",
	started = "Reparatur gestartet: %s (%s).",
	resumed = "Reparatur geht weiter: %s – schon bezahlt.",
	finished = "%s ist repariert! Beim Verkauf bekommst du jetzt +%d %% (+%s).",
	paused = "Reparatur unterbrochen – du hast dich zu weit entfernt. Komm zurück, sie ist schon bezahlt.",
	gone = "Reparatur abgebrochen: Das Auto ist nicht mehr in deiner Garage.",
	refund = "Erstattung für eine abgebrochene Reparatur: +%s.",
	badPart = "Diese Teile kauft die Große Werkstatt nicht an.",
	badCount = "Bitte 1 bis %d Teile auswählen.",
	notEnough = "Du hast nur %d %s im Lager.",
	dailyLimit = "Der Teile-Ankauf nimmt heute keine Teile mehr von dir an. Morgen wieder!",
	sold = "%d %s verkauft: +%s. Danke – das füllt den Teile-Vorrat der Werkstatt!",
	soldCapped = "Heute nimmt der Ankauf nur noch %d Teile von dir an.",
}

local api: any = nil
local ctx: any = nil

PublicWorkshopService.Stock = 0 -- Teile-Vorrat der Werkstatt (je Server, für alle Spieler)

local function cfg(): any
	return GameConfig.PublicWorkshop
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function clampInt(v: any, default: number, lo: number, hi: number): number
	if not finite(v) then
		return default
	end
	v = math.floor(v)
	if v < lo then
		return default
	end
	return math.min(v, hi)
end

local function now(): number
	if api and type(api.now) == "function" then
		return api.now()
	end
	if ctx and type(ctx.now) == "function" then
		return ctx.now()
	end
	return os.time()
end

local function toast(ms: any, text: string?)
	if api and type(api.toast) == "function" and type(text) == "string" and text ~= "" then
		api.toast(ms, text)
	end
end

local function dirty(ms: any)
	if api and type(api.dirty) == "function" then
		api.dirty(ms)
	end
end

local function storyEvent(ms: any, name: string, data: any)
	local fn = api and (api.storyEvent or api.event)
	if type(fn) == "function" then
		local ok, err = pcall(fn, ms, name, data)
		if not ok then
			warn("[Große Werkstatt] Story-Ereignis " .. name .. ": " .. tostring(err))
		end
	end
end

local function session(ms: any): any
	local s = ms.pw
	if type(s) ~= "table" then
		s = { job = nil }
		ms.pw = s
	end
	return s
end

---------------------------------------------------------------- Daten (games.pw)
function PublicWorkshopService.Default(): any
	return { cars = {}, day = "", sold = 0, refund = 0, repairs = 0, partsSold = 0 }
end

local function validKey(k: any): boolean
	return type(k) == "string" and #k > 0 and #k <= MAX_ID_LENGTH and string.match(k, "^%d+$") ~= nil
end

-- Whitelist-Normalisierung (idempotent): NaN/negativ -> Standard, unbekannte Schlüssel fallen weg, Tiefe 3.
function PublicWorkshopService.Load(raw: any, _d: any?, _now: number?): any
	local out = PublicWorkshopService.Default()
	if type(raw) ~= "table" then
		return out
	end
	local maxPct = math.floor((cfg().MaxBonus - 1) * 100 + 0.5)
	local n = 0
	if type(raw.cars) == "table" then
		local keys = {}
		for k in pairs(raw.cars) do
			if validKey(k) then
				table.insert(keys, k)
			end
		end
		table.sort(keys, function(a, b)
			return tonumber(a) < tonumber(b)
		end)
		for _, k in ipairs(keys) do
			local rec = raw.cars[k]
			if type(rec) == "table" and n < MAX_RECORDS then
				local b = clampInt(rec.b, 0, 0, maxPct)
				local p = clampInt(rec.p, 0, 0, MAX_SAFE)
				if b > 0 or p > 0 then
					local e = {}
					if b > 0 then
						e.b = b
					end
					if p > 0 and b == 0 then
						e.p = p
					end
					out.cars[k] = e
					n += 1
				end
			end
		end
	end
	out.day = (type(raw.day) == "string" and string.match(raw.day, "^%d%d%d%d%-%d%d%-%d%d$")) and raw.day or ""
	out.sold = out.day ~= "" and clampInt(raw.sold, 0, 0, MAX_SAFE) or 0
	out.refund = clampInt(raw.refund, 0, 0, MAX_SAFE)
	out.repairs = clampInt(raw.repairs, 0, 0, MAX_SAFE)
	out.partsSold = clampInt(raw.partsSold, 0, 0, MAX_SAFE)
	return out
end

-- d.games.pw (legt es an bzw. normalisiert es einmal je Tabelle, falls MiniRules es noch nicht lädt)
local normalized = setmetatable({}, { __mode = "k" })
function PublicWorkshopService.Data(d: any): any
	local g = d.games
	local pw = g.pw
	if type(pw) ~= "table" or not normalized[pw] then
		pw = PublicWorkshopService.Load(pw, d)
		g.pw = pw
		normalized[pw] = true
	end
	return pw
end

---------------------------------------------------------------- Autos, Zustand, Preise
local function keyOf(id: any): string?
	if type(id) == "number" and finite(id) and id >= 1 and id == math.floor(id) then
		return tostring(math.floor(id))
	elseif validKey(id) then
		return id
	end
	return nil
end

-- Kurzer, stabiler Hash (wie MiniRules.HashString)
local function hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- Anfangszustand 0..100 (fest aus Id und Modell): Händlerautos CondMin..CondMax, Sondermodelle (Auktion) niedriger
function PublicWorkshopService.InitialCondition(car: any): number
	local c = cfg()
	local m = CarCatalog.Model(car and car.model)
	local lo, hi = c.CondMin, c.CondMax
	if m and m.special then
		lo, hi = c.UsedCondMin, c.UsedCondMax
	end
	local h = hash(tostring(car and car.id) .. ":" .. tostring(car and car.model))
	return lo + h % (hi - lo + 1)
end

-- Bonus in Prozent für einen Anfangszustand (gedeckelt)
function PublicWorkshopService.BonusPct(cond: number): number
	local c = cfg()
	local maxPct = math.floor((c.MaxBonus - 1) * 100 + 0.5)
	local pct = math.floor((100 - cond) / 100 * c.BonusPerMissing * 100 + 0.5)
	return math.clamp(pct, 0, maxPct)
end

-- Warum dieses Auto nicht repariert werden kann (nil = geht)
local function blockedReason(car: any): string?
	local m = CarCatalog.Model(car.model)
	if not m then
		return PublicWorkshopService.Text.noCar
	end
	local ex = cfg().ExcludedModels or {}
	if ex[m.id] or m.starter == true or m.sellable == false or m.noSell == true then
		return PublicWorkshopService.Text.excluded
	end
	if m.dlc then
		return PublicWorkshopService.Text.dlc
	end
	return nil
end

-- Faktor für den Verkaufspreis: 1 + Bonus, nur für reparierte Autos; nie unter 1, nie über MaxBonus.
function PublicWorkshopService.ValueBonus(d: any, carId: any): number
	local key = keyOf(carId)
	local g = type(d) == "table" and d.games
	local pw = type(g) == "table" and g.pw
	if not key or type(pw) ~= "table" or type(pw.cars) ~= "table" then
		return 1
	end
	local rec = pw.cars[key]
	local b = type(rec) == "table" and rec.b
	if not finite(b) or b <= 0 then
		return 1
	end
	return math.clamp(1 + b / 100, 1, cfg().MaxBonus)
end

function PublicWorkshopService.OnCarSold(d: any, carId: any)
	local key = keyOf(carId)
	if key and type(d) == "table" and type(d.games) == "table" and type(d.games.pw) == "table" then
		local pw = PublicWorkshopService.Data(d)
		local rec = pw.cars[key]
		if rec and (rec.p or 0) > 0 then
			pw.refund = math.min(MAX_SAFE, pw.refund + rec.p)
		end
		pw.cars[key] = nil
	end
end

local function startPath(d: any): string
	local ok, p = pcall(MetaRules.StartPath, d)
	return ok and type(p) == "string" and p or ""
end

-- Kostenanteil am Wertgewinn: CostShare × (1 − Vorrat-Rabatt) × (1 − Weg-Rabatt), nie unter MinCostShare
local function costShare(d: any, withStock: boolean): number
	local c = cfg()
	local share = c.CostShare
	if withStock then
		share *= 1 - c.StockDiscount
	end
	local pd = c.PathDiscount and c.PathDiscount[startPath(d)]
	if finite(pd) then
		share *= 1 - pd
	end
	return math.clamp(share, c.MinCostShare, 0.95)
end

-- Angebot für ein Auto: { key, name, cond, bonus (%), gain, cost, value, state, reason }
function PublicWorkshopService.Quote(d: any, car: any): any
	local c = cfg()
	local pw = PublicWorkshopService.Data(d)
	local key = keyOf(car.id)
	local m = CarCatalog.Model(car.model)
	local rec = key and pw.cars[key] or nil
	local value = CarRules.SellValue(car)
	local q = { key = key, name = m and m.name or tostring(car.model), value = value, cond = 100, bonus = 0, gain = 0, cost = 0 }
	if rec and (rec.b or 0) > 0 then
		q.state = "repaired"
		q.bonus = rec.b
		q.gain = math.floor(value * rec.b / 100)
		q.reason = PublicWorkshopService.Text.done
		return q
	end
	local reason = blockedReason(car)
	if reason then
		q.state = "blocked"
		q.reason = reason
		return q
	end
	q.cond = PublicWorkshopService.InitialCondition(car)
	q.bonus = PublicWorkshopService.BonusPct(q.cond)
	q.gain = math.floor(value * q.bonus / 100)
	local stock = PublicWorkshopService.Stock >= c.PartsPerRepair
	q.withStock = stock
	q.cost = math.max(1, math.floor(q.gain * costShare(d, stock)))
	if car.locked then
		q.state = "blocked"
		q.reason = PublicWorkshopService.Text.locked
	elseif rec and (rec.p or 0) > 0 then
		q.state = "paid"
		q.cost = 0
	elseif q.gain < c.MinGain or q.cost >= q.gain then
		q.state = "blocked"
		q.reason = PublicWorkshopService.Text.small
	else
		q.state = "ready"
	end
	return q
end

-- Teile: Bestand und Preis je Stück (Startweg Schrottplatz +10 %)
local function partDef(id: any): any
	if type(id) ~= "string" then
		return nil
	end
	for _, p in ipairs(cfg().Parts) do
		if p.id == id then
			return p
		end
	end
	return nil
end

local function partsHave(d: any, id: string): number
	if id == "altteile" then
		local n = d.games.parts
		return finite(n) and math.max(0, math.floor(n)) or 0
	end
	return 0
end

local function partsTake(d: any, id: string, n: number): boolean
	if id == "altteile" then
		local have = partsHave(d, id)
		if have < n then
			return false
		end
		d.games.parts = have - n
		return true
	end
	return false
end

function PublicWorkshopService.PartPrice(d: any, id: any): number
	local def = partDef(id)
	if not def then
		return 0
	end
	local bonus = cfg().PathPartsBonus and cfg().PathPartsBonus[startPath(d)]
	local price = def.price * (1 + (finite(bonus) and bonus or 0))
	return math.floor(price * 100 + 0.5) / 100
end

local function rollDay(pw: any, t: number)
	local today = MiniRules.DayKey(t)
	if pw.day ~= today then
		pw.day = today
		pw.sold = 0
	end
end

---------------------------------------------------------------- Welt: Stationen und Abstand
local function station(key: string): any
	local city = workspace:FindFirstChild("City")
	local stations = city and city:FindFirstChild("Stations")
	local st = stations and stations:FindFirstChild(key)
	if st and st:IsA("BasePart") then
		return st
	end
	return nil
end

-- Abstand der Figur zur Station (math.huge ohne Figur/Station)
local function distanceTo(ms: any, key: string): number
	local st = station(key)
	local player = ms.player
	local ch = player and player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local hum = ch and ch:FindFirstChildOfClass("Humanoid")
	if not st or not root or (hum and hum.Health <= 0) then
		return math.huge
	end
	return (root.Position - st.Position).Magnitude
end

local function nearRepair(ms: any): boolean
	local c = cfg()
	return distanceTo(ms, c.StationRepair) <= c.RepairRange + c.RangeSlack
end

local function nearParts(ms: any): boolean
	local c = cfg()
	return distanceTo(ms, c.StationParts) <= c.PartsRange + c.RangeSlack
end

---------------------------------------------------------------- Aufräumen und Erstattung
-- Einträge zu Autos, die es nicht mehr gibt (verkauft, versteigert), löschen; bezahlte, nicht fertige Reparaturen
-- werden zur Erstattung.
function PublicWorkshopService.Prune(d: any)
	local pw = PublicWorkshopService.Data(d)
	for key, rec in pairs(pw.cars) do
		if not CarRules.Find(d, tonumber(key)) then
			if (rec.p or 0) > 0 then
				pw.refund = math.min(MAX_SAFE, pw.refund + rec.p)
			end
			pw.cars[key] = nil
		end
	end
end

-- Nur in Handlern (Geld innerhalb von request())
local function settleRefund(ms: any, d: any)
	local pw = PublicWorkshopService.Data(d)
	if pw.refund > 0 then
		local amount = pw.refund
		pw.refund = 0
		MiniRules.AddMoney(d, amount)
		toast(ms, string.format(PublicWorkshopService.Text.refund, MiniLocale.Credits(amount)))
	end
end

---------------------------------------------------------------- Ansicht
function PublicWorkshopService.View(ms: any, d: any, t: number): any
	local c = cfg()
	local pw = PublicWorkshopService.Data(d)
	local s = session(ms)
	local path = startPath(d)
	local cars = {}
	for _, car in ipairs(type(d.games.cars) == "table" and d.games.cars or {}) do
		local q = PublicWorkshopService.Quote(d, car)
		if q.key then
			if s.job and s.job.key == q.key then
				q.state = "working"
			end
			table.insert(cars, {
				id = q.key, name = q.name, cond = q.cond, bonus = q.bonus, gain = q.gain, cost = q.cost,
				value = q.value, state = q.state, reason = q.reason,
			})
		end
	end
	-- Erst was sich lohnt, dann bezahlte/laufende, dann gesperrte, zuletzt reparierte
	local order = { working = 1, paid = 2, ready = 3, blocked = 4, repaired = 5 }
	table.sort(cars, function(a, b)
		local oa, ob = order[a.state] or 9, order[b.state] or 9
		if oa ~= ob then
			return oa < ob
		end
		if a.gain ~= b.gain then
			return a.gain > b.gain
		end
		return tonumber(a.id) < tonumber(b.id)
	end)
	rollDay(pw, t)
	local parts = {}
	for _, def in ipairs(c.Parts) do
		local have = partsHave(d, def.id)
		local left = math.max(0, c.DailyPartsLimit - pw.sold)
		table.insert(parts, {
			id = def.id, name = def.name, have = have, price = PublicWorkshopService.PartPrice(d, def.id),
			max = math.min(have, c.MaxSellCount, left),
		})
	end
	local job = nil
	if s.job then
		job = { car = s.job.key, name = s.job.name, left = math.max(0, s.job.endsAt - t), total = c.RepairSeconds }
	end
	local focus = "repair"
	local nearP, nearR = nearParts(ms), nearRepair(ms)
	if nearP or (path == "schrottplatz" and not s.job) then
		focus = "parts"
	end
	local pathDiscount = c.PathDiscount and c.PathDiscount[path] or 0
	local partsBonus = c.PathPartsBonus and c.PathPartsBonus[path] or 0
	return {
		title = c.Title, path = path, focus = focus,
		nearRepair = nearR, nearParts = nearP, hasCity = station(c.StationRepair) ~= nil,
		credits = finite(d.money) and d.money or 0,
		stock = PublicWorkshopService.Stock, stockCap = c.StockCap, partsPerRepair = c.PartsPerRepair,
		stockDiscount = PublicWorkshopService.Stock >= c.PartsPerRepair and math.floor(c.StockDiscount * 100 + 0.5) or 0,
		pathDiscount = math.floor((finite(pathDiscount) and pathDiscount or 0) * 100 + 0.5),
		partsBonus = math.floor((finite(partsBonus) and partsBonus or 0) * 100 + 0.5),
		maxBonus = math.floor((c.MaxBonus - 1) * 100 + 0.5),
		seconds = c.RepairSeconds, maxSell = c.MaxSellCount,
		dailyLimit = c.DailyPartsLimit, dailyLeft = math.max(0, c.DailyPartsLimit - pw.sold),
		cars = cars, parts = parts, job = job, repairs = pw.repairs,
	}
end

local function sendView(ms: any, d: any, t: number, event: string, extra: any?)
	if not api or type(api.notice) ~= "function" then
		return
	end
	local v = PublicWorkshopService.View(ms, d, t)
	v.event = event
	for k, x in pairs(extra or {}) do
		v[k] = x
	end
	api.notice(ms, PublicWorkshopService.NoticeKind, v)
end

---------------------------------------------------------------- Handler
function PublicWorkshopService.Open(ms: any, _data: any, d: any, t: number): boolean?
	t = finite(t) and t or now()
	PublicWorkshopService.Prune(d)
	settleRefund(ms, d)
	sendView(ms, d, t, "open")
	return true
end

function PublicWorkshopService.Repair(ms: any, data: any, d: any, t: number): boolean?
	local c = cfg()
	local T = PublicWorkshopService.Text
	t = finite(t) and t or now()
	PublicWorkshopService.Prune(d)
	settleRefund(ms, d)
	local s = session(ms)
	local key = type(data) == "table" and keyOf(data.car) or nil
	local car = key and CarRules.Find(d, tonumber(key)) or nil
	if not car then
		toast(ms, T.noCar)
		sendView(ms, d, t, "rejected")
		return nil
	end
	if s.job then
		toast(ms, T.busy)
		return nil
	end
	local q = PublicWorkshopService.Quote(d, car)
	if q.state == "repaired" or q.state == "blocked" then
		toast(ms, q.reason)
		sendView(ms, d, t, "rejected")
		return nil
	end
	if not station(c.StationRepair) then
		toast(ms, T.noCity)
		return nil
	end
	if not nearRepair(ms) then
		toast(ms, T.farRepair)
		sendView(ms, d, t, "rejected")
		return nil
	end
	local pw = PublicWorkshopService.Data(d)
	local rec = pw.cars[key]
	local resumed = rec ~= nil and (rec.p or 0) > 0
	if not resumed then
		local money = finite(d.money) and d.money or 0
		if money < q.cost then
			toast(ms, string.format(T.money, MiniLocale.Credits(q.cost - money)))
			sendView(ms, d, t, "rejected")
			return nil
		end
		-- erst abbuchen, dann vermerken: das Profil weiß ab jetzt, dass diese Reparatur bezahlt ist
		MiniRules.AddMoney(d, -q.cost)
		pw.cars[key] = { p = q.cost }
		if q.withStock then
			PublicWorkshopService.Stock = math.max(0, PublicWorkshopService.Stock - c.PartsPerRepair)
		end
		MiniRules.GainXP(d, c.RepairXP)
		MiniRules.MarkActive(d, t)
	end
	s.job = { key = key, name = q.name, startedAt = t, endsAt = t + c.RepairSeconds, bonus = q.bonus }
	if resumed then
		toast(ms, string.format(T.resumed, q.name))
	else
		toast(ms, string.format(T.started, q.name, MiniLocale.Credits(q.cost)))
	end
	dirty(ms)
	sendView(ms, d, t, resumed and "resumed" or "started", { car = key })
	return true
end

function PublicWorkshopService.SellParts(ms: any, data: any, d: any, t: number): boolean?
	local c = cfg()
	local T = PublicWorkshopService.Text
	t = finite(t) and t or now()
	settleRefund(ms, d)
	local def = type(data) == "table" and partDef(data.part) or nil
	if not def then
		toast(ms, T.badPart)
		return nil
	end
	local count = type(data) == "table" and data.count or nil
	if not finite(count) or count ~= math.floor(count) or count < 1 or count > c.MaxSellCount then
		toast(ms, string.format(T.badCount, c.MaxSellCount))
		return nil
	end
	if not station(c.StationParts) then
		toast(ms, T.noCity)
		return nil
	end
	if not nearParts(ms) then
		toast(ms, T.farParts)
		sendView(ms, d, t, "rejected")
		return nil
	end
	local pw = PublicWorkshopService.Data(d)
	rollDay(pw, t)
	local left = math.max(0, c.DailyPartsLimit - pw.sold)
	if left <= 0 then
		toast(ms, T.dailyLimit)
		sendView(ms, d, t, "rejected")
		return nil
	end
	local n = math.min(count, left)
	local have = partsHave(d, def.id)
	if have < n then
		toast(ms, string.format(T.notEnough, have, def.name))
		sendView(ms, d, t, "rejected")
		return nil
	end
	-- Teile zuerst abbuchen, dann bezahlen
	if not partsTake(d, def.id, n) then
		toast(ms, string.format(T.notEnough, have, def.name))
		return nil
	end
	pw.sold = math.min(MAX_SAFE, pw.sold + n)
	pw.partsSold = math.min(MAX_SAFE, pw.partsSold + n)
	local value = MiniRules.AddIncome(d, math.floor(n * PublicWorkshopService.PartPrice(d, def.id) + 0.5))
	MiniRules.GainXP(d, n * (def.xp or 0))
	MiniRules.MarkActive(d, t)
	PublicWorkshopService.Stock = math.min(c.StockCap, PublicWorkshopService.Stock + n)
	if n < count then
		toast(ms, string.format(T.soldCapped, n))
	end
	toast(ms, string.format(T.sold, n, def.name, MiniLocale.Credits(value)))
	storyEvent(ms, "pw_parts_sold", { part = def.id, count = n, value = value })
	dirty(ms)
	sendView(ms, d, t, "sold", { part = def.id, count = n, value = value })
	return true
end

---------------------------------------------------------------- Tick, Beitritt, Verlassen
function PublicWorkshopService.Tick(ms: any, d: any, t: number): boolean
	local s = ms and ms.pw
	local job = type(s) == "table" and s.job or nil
	if not job then
		return false
	end
	local T = PublicWorkshopService.Text
	local pw = PublicWorkshopService.Data(d)
	local car = CarRules.Find(d, tonumber(job.key))
	if not car then
		s.job = nil
		PublicWorkshopService.Prune(d) -- bezahlte Reparatur -> Erstattung bei der nächsten Aktion
		toast(ms, T.gone)
		sendView(ms, d, t, "aborted", { car = job.key })
		return true
	end
	if car.locked or not nearRepair(ms) then
		s.job = nil
		toast(ms, car.locked and T.locked or T.paused)
		sendView(ms, d, t, "paused", { car = job.key })
		return true
	end
	if t < job.endsAt then
		return false
	end
	s.job = nil
	local bonus = job.bonus
	local value = CarRules.SellValue(car)
	local gain = math.floor(value * bonus / 100)
	pw.cars[job.key] = { b = bonus }
	pw.repairs = math.min(MAX_SAFE, pw.repairs + 1)
	toast(ms, string.format(T.finished, job.name, bonus, MiniLocale.Credits(gain)))
	storyEvent(ms, "pw_repair", { car = job.key, gain = gain })
	sendView(ms, d, t, "done", { car = job.key, gain = gain })
	return true
end

function PublicWorkshopService.OnJoin(ms: any, d: any, _t: number?)
	session(ms).job = nil
	PublicWorkshopService.Data(d)
	PublicWorkshopService.Prune(d)
end

function PublicWorkshopService.OnLeave(ms: any)
	if ms and type(ms.pw) == "table" then
		ms.pw.job = nil -- bezahlt bleibt im Profil vermerkt (p): beim nächsten Mal geht es ohne neue Kosten weiter
	end
end

function PublicWorkshopService.Init(c: any)
	ctx = c
end

function PublicWorkshopService.Register(Actions: any, a: any)
	api = a
	Actions.Register("pw_open", PublicWorkshopService.Open)
	Actions.Register("pw_repair", PublicWorkshopService.Repair)
	Actions.Register("pw_sell_parts", PublicWorkshopService.SellParts)
end

-- Nur für Tests
function PublicWorkshopService._SetApi(a: any)
	api = a
end
function PublicWorkshopService._Reset(stock: number?)
	PublicWorkshopService.Stock = finite(stock) and stock or cfg().StockStart
end

PublicWorkshopService.Stock = cfg().StockStart

-- Verkabelung mit den gemeinsamen Regeln (beim ersten require auf dem Server):
-- games.pw wird mit dem Profil gespeichert/geladen (MiniRules.ExtraGames), der Händler zahlt den Wertbonus
-- reparierter Autos (CarRules.Sell/SalePrice) und räumt den Eintrag nach dem Verkauf auf.
MiniRules.ExtraGames.pw = { Default = PublicWorkshopService.Default, Load = PublicWorkshopService.Load }
CarRules.SaleBonus = PublicWorkshopService.ValueBonus
CarRules.OnSold = PublicWorkshopService.OnCarSold

return PublicWorkshopService
