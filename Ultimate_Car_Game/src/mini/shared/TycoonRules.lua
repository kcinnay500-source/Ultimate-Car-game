-- TycoonRules: Tycoon als reine Funktionen (docs/PHASE4_CONTRACT.md §2, §8).
-- Kein Geld (Credits), keine Instanzen, keine Dienste: alles rechnet auf d.games.tycoon und dem Durchlauf run.
-- Bargeld (run.cash, run.container) ist NIE Credits und verlässt den Durchlauf nie (Rebirth/Abbruch löschen es).
--   d.games.tycoon = { runsDone = { [typ] = int }, rebirths = int, xpStage = 0..5 (Stufen-XP schon vergeben),
--                      run = false | { building, stage 1..5, cash, container, upgrades = { [id] = 1 }, startedAt,
--                                      lastTick, produced, rebirthBoost, storage = { [item] = int },
--                                      itemAcc = { [item] = 0..1 } } }
-- container = Bargeld im Sammelbehälter (bis Capacity), cash = eingesammeltes Bargeld (davon wird gekauft).
-- Alle Zahlen aus GameConfig.Tycoon. Der TycoonService ruft: NewRun beim Start, Tick im Server-Tick (0,5 s),
-- Collect am Sammel-Pad, Buy für Kaufpads und Stufen-Pads, Rebirth/Abandon, TradeValid/ApplyTrade für den Handel,
-- Summary für den Snapshot. Der Bonus auf die Open World läuft über BonusFor/CrossBonus.
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local PrestigeRules = require(script.Parent:WaitForChild("PrestigeRules"))
local C = require(script.Parent.Parent:WaitForChild("Config"))

local TycoonRules = {}

local TY = GameConfig.Tycoon
local MAX_SAFE = 2 ^ 53
local NUMBER_CAP = C.NumberCap or 1e24

export type Run = {
	building: string, stage: number, cash: number, container: number, upgrades: { [string]: number },
	startedAt: number, lastTick: number, produced: number, rebirthBoost: number,
	storage: { [string]: number }, itemAcc: { [string]: number },
}
export type Tycoon = { runsDone: { [string]: number }, rebirths: number, run: Run | boolean, xpStage: number }

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function loadNum(v: any, default: number, min: number, max: number): number
	if not finite(v) or v < min then
		return default
	end
	return math.min(v, max)
end

local function loadInt(v: any, default: number, min: number, max: number): number
	if not finite(v) or v < min then
		return default
	end
	return math.floor(math.min(v, max))
end

local function building(typ: any): GameConfig.TycoonBuilding?
	return type(typ) == "string" and TY.Buildings[typ] or nil
end

local function tycoonOf(d: any): Tycoon?
	local g = type(d) == "table" and d.games or nil
	local t = type(g) == "table" and g.tycoon or nil
	return type(t) == "table" and t or nil
end

---------------------------------------------------------------- Standardwerte und Laden
function TycoonRules.Default(): Tycoon
	local runsDone = {}
	for _, typ in ipairs(TY.Types) do
		runsDone[typ] = 0
	end
	return { runsDone = runsDone, rebirths = 0, run = false, xpStage = 0 }
end

-- Whitelist eines gespeicherten Durchlaufs: unbekannter Gebäudetyp -> kein Durchlauf. Upgrades nur mit gültiger Id
-- des Gebäudes bis zur aktuellen Stufe, Lager nur bekannte Waren 0..ItemCap, Behälter höchstens Capacity.
local function loadRun(raw: any, now: any): Run | boolean
	if type(raw) ~= "table" then
		return false
	end
	local b = building(raw.building)
	if not b then
		return false
	end
	local run: Run = {
		building = b.typ,
		stage = loadInt(raw.stage, 1, 1, TY.MaxStage),
		cash = loadNum(raw.cash, 0, 0, NUMBER_CAP),
		container = 0,
		upgrades = {},
		startedAt = loadInt(raw.startedAt, 0, 0, MAX_SAFE),
		lastTick = loadInt(raw.lastTick, 0, 0, MAX_SAFE),
		produced = loadNum(raw.produced, 0, 0, NUMBER_CAP),
		rebirthBoost = loadNum(raw.rebirthBoost, 0, 0, TY.Rebirth.capPct / 100 + GameConfig.Prestige.RebirthBonus),
		storage = {},
		itemAcc = {},
	}
	if type(raw.upgrades) == "table" then
		for id, v in pairs(raw.upgrades) do
			local u = type(id) == "string" and TY.UpgradeById[id] or nil
			if u and u.typ == run.building and u.stage <= run.stage and finite(v) and v >= 1 then
				run.upgrades[id] = 1
			end
		end
	end
	for _, item in ipairs(TY.ItemList) do
		local st = type(raw.storage) == "table" and raw.storage[item] or nil
		local n = loadInt(st, 0, 0, TY.ItemCap)
		if n > 0 then
			run.storage[item] = n
		end
		local acc = type(raw.itemAcc) == "table" and raw.itemAcc[item] or nil
		if finite(acc) and acc > 0 and acc < 1 then
			run.itemAcc[item] = acc
		end
	end
	run.container = loadNum(raw.container, 0, 0, TycoonRules.Capacity(run))
	if finite(now) and now > 0 then
		if run.startedAt == 0 or run.startedAt > now then
			run.startedAt = math.floor(now)
		end
		if run.lastTick > now then
			run.lastTick = math.floor(now)
		end
	end
	return run
end

-- raw = gespeichertes d.games.tycoon (oder nil). Idempotent; NaN/negativ/Müll -> Standard.
function TycoonRules.Load(raw: any, d: any, now: any): Tycoon
	local t = TycoonRules.Default()
	if type(raw) ~= "table" then
		return t
	end
	for _, typ in ipairs(TY.Types) do
		local n = type(raw.runsDone) == "table" and raw.runsDone[typ] or nil
		t.runsDone[typ] = loadInt(n, 0, 0, MAX_SAFE)
	end
	t.rebirths = loadInt(raw.rebirths, 0, 0, MAX_SAFE)
	-- höchste Stufe, für die seit dem letzten Rebirth schon Stufen-XP vergeben wurden (Abbruch setzt sie NICHT zurück)
	t.xpStage = loadInt(raw.xpStage, 0, 0, TY.MaxStage)
	t.run = loadRun(raw.run, now)
	return t
end

-- Für MiniRules.DefaultGames/LoadGames (g = d.games)
function TycoonRules.ApplyDefault(g: any)
	g.tycoon = TycoonRules.Default()
end

function TycoonRules.ApplyLoad(g: any, raw: any, d: any, now: any)
	local r = type(raw) == "table" and raw or {}
	g.tycoon = TycoonRules.Load(r.tycoon, d, now)
end

---------------------------------------------------------------- Zugriff
function TycoonRules.Tycoon(d: any): Tycoon?
	return tycoonOf(d)
end

function TycoonRules.RunOf(d: any): Run?
	local t = tycoonOf(d)
	local run = t and t.run
	return type(run) == "table" and run or nil
end

function TycoonRules.IsType(typ: any): boolean
	return type(typ) == "string" and TY.TypeSet[typ] == true
end

function TycoonRules.IsItem(item: any): boolean
	return type(item) == "string" and TY.Items[item] ~= nil
end

-- Rebirth-Boost eines neuen Durchlaufs: min(rebirths × 15 %, 150 %) + Prestige-Rebirth-Bonus (ab Rang 3, +5 %)
function TycoonRules.BoostFor(d: any): number
	local t = tycoonOf(d)
	local rebirths = t and finite(t.rebirths) and t.rebirths or 0
	local boost = math.min(rebirths * TY.Rebirth.boostPct, TY.Rebirth.capPct) / 100
	local ok, extra = pcall(PrestigeRules.RebirthBonus, d)
	if ok and finite(extra) and extra > 0 then
		boost += extra
	end
	return boost
end

-- Neuer Durchlauf (tycoon_choose): Stufe 1, StartCash, kein Upgrade. nil bei unbekanntem Typ oder laufendem Durchlauf.
function TycoonRules.NewRun(d: any, typ: any, now: any): Run?
	local t = tycoonOf(d)
	local b = building(typ)
	if not t or not b or type(t.run) == "table" then
		return nil
	end
	local at = finite(now) and math.floor(math.max(0, now)) or 0
	local run: Run = {
		building = b.typ,
		stage = 1,
		cash = TY.StartCash,
		container = 0,
		upgrades = {},
		startedAt = at,
		lastTick = at,
		produced = 0,
		rebirthBoost = TycoonRules.BoostFor(d),
		storage = {},
		itemAcc = {},
	}
	t.run = run
	return run
end

---------------------------------------------------------------- Rechnen
-- Bargeld je Sekunde: (Grundrate + Produzenten) × Tempo-Faktoren × (1 + Deko-Boni) × (1 + Rebirth-Boost)
function TycoonRules.Rate(run: any): number
	local b = type(run) == "table" and building(run.building) or nil
	if not b then
		return 0
	end
	local prod, tempo, deko = b.baseRate, 1, 1
	for id in pairs(run.upgrades or {}) do
		local u = TY.UpgradeById[id]
		if u and u.typ == b.typ then
			if u.kind == "producer" then
				prod += u.rate or 0
			elseif u.kind == "tempo" then
				tempo *= u.mult or 1
			elseif u.kind == "deko" then
				deko += u.bonus or 0
			end
		end
	end
	local boost = finite(run.rebirthBoost) and math.max(0, run.rebirthBoost) or 0
	return prod * tempo * deko * (1 + boost)
end

-- Behälter: Grundwert der Stufe + Lager-Upgrades
function TycoonRules.Capacity(run: any): number
	local b = type(run) == "table" and building(run.building) or nil
	if not b then
		return 0
	end
	local st = b.Stages[loadInt(run.stage, 1, 1, TY.MaxStage)]
	local cap = st.capacity
	for id in pairs(run.upgrades or {}) do
		local u = TY.UpgradeById[id]
		if u and u.typ == b.typ and u.kind == "lager" then
			cap += u.cap or 0
		end
	end
	return cap
end

-- Warenausstoß je Minute je Ware (Lager-Upgrades)
function TycoonRules.ItemRates(run: any): { [string]: number }
	local out = {}
	local b = type(run) == "table" and building(run.building) or nil
	if not b then
		return out
	end
	for id in pairs(run.upgrades or {}) do
		local u = TY.UpgradeById[id]
		if u and u.typ == b.typ and u.kind == "lager" and u.item then
			out[u.item] = (out[u.item] or 0) + (u.perMin or 0)
		end
	end
	return out
end

-- Server-Tick: erzeugt Bargeld in den Behälter (bis Capacity) und Waren ins Lager (bis ItemCap) aus lastTick.
-- Höchstens MaxTickSeconds werden angerechnet (Offline zählt nicht; der Dienst setzt beim Fortsetzen lastTick = now).
-- Rückgabe: erzeugtes Bargeld.
function TycoonRules.Tick(run: any, now: any): number
	if type(run) ~= "table" or not building(run.building) or not finite(now) then
		return 0
	end
	local last = finite(run.lastTick) and run.lastTick or now
	local dt = math.clamp(now - last, 0, TY.MaxTickSeconds)
	run.lastTick = now
	if dt <= 0 then
		return 0
	end
	local cap = TycoonRules.Capacity(run)
	local before = finite(run.container) and math.max(0, run.container) or 0
	local produced = TycoonRules.Rate(run) * dt
	run.container = math.min(cap, before + produced)
	local gained = math.max(0, run.container - before)
	run.produced = math.min(NUMBER_CAP, (finite(run.produced) and run.produced or 0) + gained)
	run.storage = type(run.storage) == "table" and run.storage or {}
	run.itemAcc = type(run.itemAcc) == "table" and run.itemAcc or {}
	for item, perMin in pairs(TycoonRules.ItemRates(run)) do
		local acc = (run.itemAcc[item] or 0) + perMin * dt / 60
		local whole = math.floor(acc)
		run.itemAcc[item] = acc - whole
		if whole > 0 then
			run.storage[item] = math.min(TY.ItemCap, (run.storage[item] or 0) + whole)
		end
	end
	return gained
end

-- Sammeln (tycoon_collect): Behälter -> Bargeld (Deckel NumberCap). Rückgabe: eingesammelter Betrag.
function TycoonRules.Collect(run: any): number
	if type(run) ~= "table" or not finite(run.container) or run.container <= 0 then
		return 0
	end
	local amount = math.floor(run.container)
	if amount <= 0 then
		return 0
	end
	local cash = finite(run.cash) and run.cash or 0
	local room = math.max(0, NUMBER_CAP - cash)
	amount = math.min(amount, room)
	run.cash = cash + amount
	run.container -= amount
	return amount
end

---------------------------------------------------------------- Kaufen
-- Alle Upgrades einer Stufe gekauft?
function TycoonRules.StageComplete(run: any, stage: number?): boolean
	local b = type(run) == "table" and building(run.building) or nil
	if not b then
		return false
	end
	local st = b.Stages[stage or run.stage]
	if not st then
		return false
	end
	for _, u in ipairs(st.Upgrades) do
		if not (run.upgrades and run.upgrades[u.id]) then
			return false
		end
	end
	return true
end

-- Fehlende Waren für eine Stufe: { [item] = fehlend } (leer = alles da)
function TycoonRules.MissingItems(run: any, stage: number): { [string]: number }
	local out = {}
	local b = type(run) == "table" and building(run.building) or nil
	local st = b and b.Stages[stage] or nil
	if not st then
		return out
	end
	for item, need in pairs(st.items) do
		local have = type(run.storage) == "table" and run.storage[item] or 0
		if have < need then
			out[item] = need - have
		end
	end
	return out
end

-- Prüft Upgrade-Ids ("<typ>_s<n>_u<k>", nur aktuelle Stufe, noch nicht gekauft) und Stufen-Pads ("<typ>_stage<n>",
-- n = run.stage + 1, Vorstufe komplett, Waren ab Stufe 3). Rückgabe: ok, Grund, Kosten.
-- Gründe: no_run | unknown | wrong_building | wrong_stage | owned | stage_incomplete | items | cash
function TycoonRules.CanBuy(run: any, id: any): (boolean, string, number)
	if type(run) ~= "table" or not building(run.building) then
		return false, "no_run", 0
	end
	if type(id) ~= "string" then
		return false, "unknown", 0
	end
	local cash = finite(run.cash) and run.cash or 0
	local u = TY.UpgradeById[id]
	if u then
		if u.typ ~= run.building then
			return false, "wrong_building", u.cost
		end
		if u.stage ~= run.stage then
			return false, "wrong_stage", u.cost
		end
		if run.upgrades and run.upgrades[id] then
			return false, "owned", u.cost
		end
		if cash < u.cost then
			return false, "cash", u.cost
		end
		return true, "", u.cost
	end
	local sid = TY.StageById[id]
	if not sid then
		return false, "unknown", 0
	end
	local st = TY.Buildings[sid.typ].Stages[sid.stage]
	if sid.typ ~= run.building then
		return false, "wrong_building", st.price
	end
	if sid.stage ~= run.stage + 1 then
		return false, "wrong_stage", st.price
	end
	if TY.StageRequiresAllUpgrades ~= false and not TycoonRules.StageComplete(run, run.stage) then
		return false, "stage_incomplete", st.price
	end
	if next(TycoonRules.MissingItems(run, sid.stage)) ~= nil then
		return false, "items", st.price
	end
	if cash < st.price then
		return false, "cash", st.price
	end
	return true, "", st.price
end

-- Kauft (Upgrade oder Stufe) aus run.cash; Waren für Stufen werden verbraucht. Rückgabe: ok, Grund, Kosten.
function TycoonRules.Buy(run: any, id: any): (boolean, string, number)
	local ok, reason, cost = TycoonRules.CanBuy(run, id)
	if not ok then
		return false, reason, cost
	end
	run.cash -= cost
	if TY.UpgradeById[id] then
		run.upgrades[id] = 1
	else
		local sid = TY.StageById[id]
		local st = TY.Buildings[sid.typ].Stages[sid.stage]
		for item, need in pairs(st.items) do
			run.storage[item] = (run.storage[item] or 0) - need
			if run.storage[item] <= 0 then
				run.storage[item] = nil
			end
		end
		run.stage = sid.stage
	end
	return true, "", cost
end

-- Kaufbare Ids der aktuellen Stufe (für Snapshot/Client): { { id, cost, ok, reason } }
function TycoonRules.Offers(run: any): { { id: string, cost: number, ok: boolean, reason: string } }
	local out = {}
	local b = type(run) == "table" and building(run.building) or nil
	if not b then
		return out
	end
	local st = b.Stages[run.stage]
	for _, u in ipairs(st.Upgrades) do
		if not run.upgrades[u.id] then
			local ok, reason, cost = TycoonRules.CanBuy(run, u.id)
			table.insert(out, { id = u.id, cost = cost, ok = ok, reason = reason })
		end
	end
	if st.stageId then
		local ok, reason, cost = TycoonRules.CanBuy(run, st.stageId)
		table.insert(out, { id = st.stageId, cost = cost, ok = ok, reason = reason })
	end
	return out
end

---------------------------------------------------------------- Rebirth und Abbruch
-- Rebirth erst ab Stufe 5 komplett (alle Upgrades). Rückgabe: ok, Grund
function TycoonRules.CanRebirth(run: any): (boolean, string)
	if type(run) ~= "table" or not building(run.building) then
		return false, "no_run"
	end
	if run.stage < TY.Rebirth.requiresStage then
		return false, "stage"
	end
	if TY.Rebirth.requiresAllUpgrades and not TycoonRules.StageComplete(run, run.stage) then
		return false, "upgrades"
	end
	return true, ""
end

-- Rebirth (tycoon_rebirth): runsDone[typ] + 1, rebirths + 1, run = false. Bargeld verfällt (nie Credits).
-- Rückgabe: ok, Grund, abgeschlossener Gebäudetyp
function TycoonRules.Rebirth(d: any, now: any): (boolean, string, string?)
	local t = tycoonOf(d)
	local run = TycoonRules.RunOf(d)
	if not t or not run then
		return false, "no_run", nil
	end
	local ok, reason = TycoonRules.CanRebirth(run)
	if not ok then
		return false, reason, nil
	end
	local typ = run.building
	t.runsDone[typ] = math.min(MAX_SAFE, (t.runsDone[typ] or 0) + 1)
	t.rebirths = math.min(MAX_SAFE, t.rebirths + 1)
	t.run = false
	t.xpStage = 0 -- Stufen-XP gibt es im nächsten Durchlauf wieder
	return true, "", typ
end

-- Abbruch (tycoon_abandon): Durchlauf weg, nichts gezählt. Rückgabe: true, wenn einer lief.
function TycoonRules.Abandon(d: any): boolean
	local t = tycoonOf(d)
	if not t or type(t.run) ~= "table" then
		return false
	end
	t.run = false
	return true
end

---------------------------------------------------------------- Handel (nur Bargeld, nur Waren)
-- Angebot des Verkäufers: Ware bekannt, qty ganzzahlig 1..TradeMaxQty, price ganzzahlig TradeMinPrice..TradeMaxPrice,
-- Lager reicht. Rückgabe: ok, Grund (item | qty | price | storage | no_run)
function TycoonRules.TradeValid(run: any, item: any, qty: any, price: any): (boolean, string)
	if type(run) ~= "table" or not building(run.building) then
		return false, "no_run"
	end
	if not TycoonRules.IsItem(item) then
		return false, "item"
	end
	if not finite(qty) or qty ~= math.floor(qty) or qty < 1 or qty > TY.TradeMaxQty then
		return false, "qty"
	end
	if not finite(price) or price ~= math.floor(price) or price < TY.TradeMinPrice or price > (TY.TradeMaxPrice or NUMBER_CAP) then
		return false, "price"
	end
	local have = type(run.storage) == "table" and run.storage[item] or 0
	if have < qty then
		return false, "storage"
	end
	return true, ""
end

-- Übergabe in einem Schritt: Ware Verkäufer -> Käufer, Bargeld Käufer -> Verkäufer. Nichts passiert, wenn eine
-- Prüfung scheitert (Lager, Bargeld, Lagerdeckel des Käufers, Bargeld-Deckel des Verkäufers).
-- Rückgabe: ok, Grund (storage | cash | full | same | ...)
function TycoonRules.ApplyTrade(sellerRun: any, buyerRun: any, item: any, qty: any, price: any): (boolean, string)
	local ok, reason = TycoonRules.TradeValid(sellerRun, item, qty, price)
	if not ok then
		return false, reason
	end
	if type(buyerRun) ~= "table" or not building(buyerRun.building) then
		return false, "no_run"
	end
	if sellerRun == buyerRun then
		return false, "same"
	end
	local buyerCash = finite(buyerRun.cash) and buyerRun.cash or 0
	if buyerCash < price then
		return false, "cash"
	end
	buyerRun.storage = type(buyerRun.storage) == "table" and buyerRun.storage or {}
	local buyerHave = buyerRun.storage[item] or 0
	if buyerHave + qty > TY.ItemCap then
		return false, "full"
	end
	local sellerCash = finite(sellerRun.cash) and sellerRun.cash or 0
	if sellerCash + price > NUMBER_CAP then
		return false, "full"
	end
	sellerRun.storage[item] -= qty
	if sellerRun.storage[item] <= 0 then
		sellerRun.storage[item] = nil
	end
	buyerRun.storage[item] = buyerHave + qty
	buyerRun.cash = buyerCash - price
	sellerRun.cash = sellerCash + price
	return true, ""
end

---------------------------------------------------------------- Bonus und Snapshot
-- Bonus-Anteil eines Typs auf die Open World: min(n, maxRuns) × step (z. B. 0,06 = +6 %)
function TycoonRules.BonusFor(d: any, typ: any): number
	local bonus = type(typ) == "string" and TY.Bonus[typ] or nil
	if not bonus then
		return 0
	end
	local t = tycoonOf(d)
	local n = t and t.runsDone and t.runsDone[typ] or 0
	if not finite(n) or n <= 0 then
		return 0
	end
	return math.min(math.floor(n), bonus.maxRuns) * bonus.step
end

-- Alle Boni als Tabelle { [typ] = { runs, pct, text } } (Snapshot-Feld tycoon.bonus)
function TycoonRules.Bonuses(d: any): { [string]: { runs: number, pct: number, text: string } }
	local out = {}
	local t = tycoonOf(d)
	for _, typ in ipairs(TY.Types) do
		local n = t and t.runsDone and t.runsDone[typ] or 0
		out[typ] = {
			runs = finite(n) and math.floor(n) or 0,
			pct = math.floor(TycoonRules.BonusFor(d, typ) * 100 * 10 + 0.5) / 10,
			text = TY.Bonus[typ].text,
		}
	end
	return out
end

-- Für den Snapshot (tycoon.run): kleine, saubere Tabelle ohne Zähler-Reste
function TycoonRules.Summary(d: any): { run: any, rebirths: number, runsDone: { [string]: number }, boost: number, bonus: any }
	local t = tycoonOf(d)
	local run = TycoonRules.RunOf(d)
	local out = {
		run = false,
		rebirths = t and t.rebirths or 0,
		runsDone = {},
		boost = TycoonRules.BoostFor(d),
		bonus = TycoonRules.Bonuses(d),
	}
	for _, typ in ipairs(TY.Types) do
		out.runsDone[typ] = t and t.runsDone and t.runsDone[typ] or 0
	end
	if run then
		local b = TY.Buildings[run.building]
		local upgrades = {}
		for id in pairs(run.upgrades) do
			table.insert(upgrades, id)
		end
		table.sort(upgrades)
		local storage = {}
		for _, item in ipairs(TY.ItemList) do
			if (run.storage[item] or 0) > 0 then
				storage[item] = run.storage[item]
			end
		end
		local canRebirth, rebirthReason = TycoonRules.CanRebirth(run)
		out.run = {
			building = run.building,
			name = b.name,
			stage = run.stage,
			cash = math.floor(run.cash),
			container = math.floor(run.container),
			capacity = TycoonRules.Capacity(run),
			rate = math.floor(TycoonRules.Rate(run) * 100 + 0.5) / 100,
			upgrades = upgrades,
			storage = storage,
			items = TycoonRules.ItemRates(run),
			offers = TycoonRules.Offers(run),
			missing = run.stage < TY.MaxStage and TycoonRules.MissingItems(run, run.stage + 1) or {},
			startedAt = run.startedAt,
			produced = math.floor(run.produced),
			rebirthBoost = run.rebirthBoost,
			complete = TycoonRules.StageComplete(run, run.stage),
			canRebirth = canRebirth,
			rebirthReason = rebirthReason,
		}
	end
	return out
end

-- XP je abgeschlossenem Durchlauf / je erreichter Stufe (Regler in GameConfig.XP)
function TycoonRules.XPForRun(): number
	return TY.XP.run
end

function TycoonRules.XPForStage(): number
	return TY.XP.stage
end

-- Stufen-XP nur einmal je Stufe seit dem letzten Rebirth: Abbruch + Neustart (tycoon_abandon/tycoon_choose) wiederholt
-- die frühen Stufen sonst beliebig oft und wandelt so Bargeld schneller in Level-Credits um als ein ganzer Durchlauf.
-- Rückgabe: XP, die für das Erreichen von run.stage jetzt fällig sind (0, wenn schon vergeben); merkt sich die Stufe.
function TycoonRules.ClaimStageXP(d: any): number
	local t = tycoonOf(d)
	local run = TycoonRules.RunOf(d)
	if not t or not run then
		return 0
	end
	local done = math.max(1, finite(t.xpStage) and t.xpStage or 0) -- Stufe 1 ist der Start, keine „erreichte“ Stufe
	if run.stage <= done then
		return 0
	end
	t.xpStage = run.stage
	return TycoonRules.XPForStage()
end

return TycoonRules
