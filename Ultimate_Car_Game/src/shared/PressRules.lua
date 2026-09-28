-- PressRules: reine Formeln der Schrottpresse (HTML: Auto Clicker).
-- passes = { doubleScrap = bool, pressPlus = bool } kommt immer vom Server.
local Config = require(script.Parent:WaitForChild("Config"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Rules = require(script.Parent:WaitForChild("Rules"))

local PressRules = {}

function PressRules.Level(p, id)
	return p.games.press.upgrades[id] or 0
end

-- HTML clickerCost: max(1, floor(baseCost * 1.145^Stufe))
function PressRules.UpgradeCost(u, level)
	return math.max(1, math.floor(u.baseCost * Config.PressUpgradeCostGrowth ^ level))
end

function PressRules.TotalLevels(p)
	local total = 0
	for _, lvl in pairs(p.games.press.upgrades) do
		total += lvl
	end
	return total
end

-- HTML clickerGlobalMultiplier
function PressRules.GlobalMultiplier(p)
	return 1 + PressRules.TotalLevels(p) * Config.PressGlobalPerLevel
end

function PressRules.RebirthMultiplier(p)
	return 1 + p.games.press.rebirths * Config.RebirthMultiplierPerRebirth
end

local function bonuses(p)
	local click, machine = 0, 0
	for id, lvl in pairs(p.games.press.upgrades) do
		local u = Catalog.PressUpgradeById[id]
		if u then
			if u.type == 0 or u.type == 3 then
				click += lvl * u.baseEffect
			elseif u.type == 1 or u.type == 4 then
				machine += lvl * u.baseEffect * Config.PressMachineEffectFactor
			end
		end
	end
	return click, machine
end

-- Grundertrag pro Klick ohne Combo und ohne gekaufte Multiplikatoren (HTML clickPowerTotal)
function PressRules.ClickPower(p)
	local click = bonuses(p)
	return math.max(1, (Config.PressBaseClick + click) * PressRules.GlobalMultiplier(p) * PressRules.RebirthMultiplier(p))
end

-- Grundertrag der Maschinen pro Sekunde (HTML autoPowerTotal)
function PressRules.MachinePower(p)
	local _, machine = bonuses(p)
	return math.max(0, (Config.PressBaseMachine + machine) * PressRules.GlobalMultiplier(p) * PressRules.RebirthMultiplier(p))
end

-- Gekaufte Multiplikatoren (wirken auf das Guthaben, nie auf den Bestenlistenwert)
function PressRules.PassClickMultiplier(passes)
	return (passes and passes.doubleScrap) and Config.GamePasses.DoubleScrap.multiplier or 1
end

function PressRules.PassMachineMultiplier(passes)
	local m = PressRules.PassClickMultiplier(passes)
	if passes and passes.pressPlus then
		m *= Config.GamePasses.PressPlus.machineMultiplier
	end
	return m
end

-- Querboni (HTML clickerWorkshopMultiplier / clickerTuningMultiplier)
function PressRules.WorkshopMultiplier(p)
	return 1 + (PressRules.GlobalMultiplier(p) - 1) * Config.PressWorkshopShare
end

function PressRules.TuningMultiplier(p)
	return 1 + (PressRules.GlobalMultiplier(p) - 1) * Config.PressTuningShare
end

-- Schreibt Ertrag gut: ranked zählt für die Bestenliste, paid landet im Guthaben.
local function credit(p, ranked, paid, now, passive)
	local pr = p.games.press
	pr.scrap += paid
	pr.runScrap += paid
	pr.lifetime += ranked
	Rules.AddStat(p, "pressed", paid, now, passive)
end

-- Bucht n akzeptierte Klicks. t = Serverzeit (präzise), now = os.time()
-- Rückgabe: bezahlter Ertrag, Combo danach
function PressRules.ApplyClicks(p, n, t, now, passes)
	local pr = p.games.press
	n = Rules.SafeInt(n, 0, 0, 100000)
	if n <= 0 then
		return 0, pr.combo
	end
	local combo = pr.combo
	local within = pr.comboAt > 0 and t >= pr.comboAt and (t - pr.comboAt) <= Config.PressComboWindow
	if not within then
		combo = 1
	end
	local base = PressRules.ClickPower(p)
	local ranked = 0
	for i = 1, n do
		if i > 1 or within then
			combo = math.min(Config.PressComboMax, combo + Config.PressComboStep)
		end
		ranked += base * combo
	end
	pr.combo = combo
	pr.comboAt = t
	pr.clicks += n
	Rules.AddStat(p, "clicks", n, now)
	local paid = ranked * PressRules.PassClickMultiplier(passes)
	credit(p, ranked, paid, now)
	return paid, combo
end

-- Maschinenertrag für eine Zeitspanne (Server-Tick und Offline)
function PressRules.Produce(p, seconds, now, passes)
	seconds = Rules.SafeNumber(seconds, 0, 0, Config.PressOfflineCapHours * 3600)
	if seconds <= 0 then
		return 0
	end
	local ranked = PressRules.MachinePower(p) * seconds
	local paid = ranked * PressRules.PassMachineMultiplier(passes)
	credit(p, ranked, paid, now, true)
	return paid
end

-- Offline-Sekunden aus os.time()-Differenz: negativ/unplausibel -> 0, gedeckelt
function PressRules.OfflineSeconds(lastTick, now)
	if not Rules.IsFiniteNumber(lastTick) or not Rules.IsFiniteNumber(now) or lastTick <= 0 then
		return 0
	end
	local diff = now - lastTick
	if diff <= 0 then
		return 0
	end
	return math.min(diff, Config.PressOfflineCapHours * 3600)
end

-- Kauf: expectedLevel ist die Stufe, die der Client gesehen hat. Doppelte Absicht -> abgelehnt.
function PressRules.BuyUpgrade(p, id, expectedLevel, now)
	local u = type(id) == "string" and Catalog.PressUpgradeById[id]
	if not u then
		return false, "Unbekanntes Upgrade."
	end
	local lvl = PressRules.Level(p, id)
	if type(expectedLevel) ~= "number" or expectedLevel ~= lvl then
		return false, nil -- veraltete oder doppelte Anfrage: still verwerfen
	end
	local cost = PressRules.UpgradeCost(u, lvl)
	local pr = p.games.press
	if pr.scrap < cost then
		return false, "Nicht genug Schrott."
	end
	pr.scrap -= cost
	pr.upgrades[id] = lvl + 1
	Rules.AddStat(p, "pressUpgrades", 1, now)
	if u.type == 2 then
		p.games.reputation += 1
		p.credits += math.max(1, math.floor(u.baseEffect * 0.5))
	end
	return true, u
end

-- Schrott -> Credits in festen Paketen. Es gibt keine Gegenrichtung.
function PressRules.ExchangeCredits(scrap)
	return math.floor(scrap / Config.ScrapPerCredit * Config.ScrapExchangePayout)
end

function PressRules.Exchange(p, packageIndex)
	local amount = type(packageIndex) == "number" and Config.ScrapExchangePackages[packageIndex]
	if not amount then
		return false, "Unbekanntes Paket."
	end
	local pr = p.games.press
	if pr.scrap < amount then
		return false, "Nicht genug Schrott."
	end
	local credits = PressRules.ExchangeCredits(amount)
	pr.scrap -= amount
	p.credits += credits
	return true, credits
end

function PressRules.RebirthThreshold(p)
	return Config.RebirthBaseThreshold * Config.RebirthThresholdGrowth ^ p.games.press.rebirths
end

function PressRules.CanRebirth(p)
	return p.games.press.runScrap >= PressRules.RebirthThreshold(p)
end

-- Setzt genau Schrott, Durchlauf und Presse-Upgrades zurück.
function PressRules.Rebirth(p, expectedRebirths)
	local pr = p.games.press
	if type(expectedRebirths) ~= "number" or expectedRebirths ~= pr.rebirths then
		return false, nil
	end
	if not PressRules.CanRebirth(p) then
		return false, "Rebirth ist erst ab " .. math.floor(PressRules.RebirthThreshold(p)) .. " Schrott in diesem Durchlauf möglich."
	end
	pr.scrap = Config.PressStartScrap
	pr.runScrap = 0
	pr.upgrades = {}
	pr.combo = 1
	pr.comboAt = 0
	pr.rebirths += 1
	Rules.AddStat(p, "rebirths", 1, nil)
	return true, PressRules.RebirthMultiplier(p)
end

-- Bestenlisten-Kodierung: OrderedDataStore speichert nur Ganzzahlen; Schrott kann 2^53 übersteigen.
-- log10(1 + x) * 1e13 bleibt für alle Doubles unter 2^53 und ist monoton.
local SCALE = 1e13
function PressRules.EncodeScore(value)
	if not Rules.IsFiniteNumber(value) or value <= 0 then
		return 0
	end
	return math.floor(math.log10(1 + value) * SCALE)
end

function PressRules.DecodeScore(code)
	if not Rules.IsFiniteNumber(code) or code <= 0 then
		return 0
	end
	local v = 10 ^ (code / SCALE) - 1
	if v < 2 ^ 53 then
		v = math.floor(v + 0.5)
	end
	return v
end

return PressRules
