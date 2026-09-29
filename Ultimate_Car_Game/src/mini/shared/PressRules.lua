-- PressRules: reine Formeln der Schrottpresse (HTML: Auto Clicker). d = 2.4.0-Profildaten.
-- passes = { doubleScrap = bool, pressPlus = bool } kommt immer vom Server.
-- Presse-Erträge sind Schrott, nie Geld; Geld entsteht nur beim Schrotthändler (Exchange).
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))
local MiniCatalog = require(script.Parent:WaitForChild("MiniCatalog"))
local MiniRules = require(script.Parent:WaitForChild("MiniRules"))
local CrossBonus = require(script.Parent:WaitForChild("CrossBonus"))

local PressRules = {}

function PressRules.Level(d, id)
	return d.games.press.upgrades[id] or 0
end

-- HTML clickerCost: max(1, floor(baseCost * 1.145^Stufe))
function PressRules.UpgradeCost(u, level)
	return math.max(1, math.floor(u.baseCost * MiniConfig.PressUpgradeCostGrowth ^ level))
end

function PressRules.TotalLevels(d)
	return CrossBonus.PressLevels(d)
end

-- HTML clickerGlobalMultiplier
function PressRules.GlobalMultiplier(d)
	return CrossBonus.PressGlobal(d)
end

function PressRules.RebirthMultiplier(d)
	return 1 + d.games.press.rebirths * MiniConfig.RebirthMultiplierPerRebirth
end

local function bonuses(d)
	local click, machine = 0, 0
	for id, lvl in pairs(d.games.press.upgrades) do
		local u = MiniCatalog.PressUpgradeById[id]
		if u then
			if u.type == 0 or u.type == 3 then
				click += lvl * u.baseEffect
			elseif u.type == 1 or u.type == 4 then
				machine += lvl * u.baseEffect * MiniConfig.PressMachineEffectFactor
			end
		end
	end
	return click, machine
end

-- Grundertrag pro Klick ohne Combo und ohne gekaufte Multiplikatoren (HTML clickPowerTotal)
function PressRules.ClickPower(d)
	local click = bonuses(d)
	return math.max(1, (MiniConfig.PressBaseClick + click) * PressRules.GlobalMultiplier(d) * PressRules.RebirthMultiplier(d))
end

-- Grundertrag der Maschinen pro Sekunde (HTML autoPowerTotal)
function PressRules.MachinePower(d)
	local _, machine = bonuses(d)
	return math.max(0, (MiniConfig.PressBaseMachine + machine) * PressRules.GlobalMultiplier(d) * PressRules.RebirthMultiplier(d))
end

-- Gekaufte Multiplikatoren (wirken auf das Guthaben, nie auf den Bestenlistenwert)
function PressRules.PassClickMultiplier(passes)
	return (passes and passes.doubleScrap) and MiniConfig.GamePasses.DoubleScrap.multiplier or 1
end

function PressRules.PassMachineMultiplier(passes)
	local m = PressRules.PassClickMultiplier(passes)
	if passes and passes.pressPlus then
		m *= MiniConfig.GamePasses.PressPlus.machineMultiplier
	end
	return m
end

-- Querboni (HTML clickerWorkshopMultiplier / clickerTuningMultiplier)
function PressRules.WorkshopMultiplier(d)
	return CrossBonus.PressWorkshop(d)
end

function PressRules.TuningMultiplier(d)
	return CrossBonus.PressTuning(d)
end

-- Schreibt Ertrag gut: ranked zählt für die Bestenliste, paid landet im Schrott-Guthaben.
local function credit(d, ranked, paid, now, passive)
	local pr = d.games.press
	pr.scrap += paid
	pr.runScrap += paid
	pr.lifetime += ranked
	MiniRules.AddStat(d, "pressed", paid, now, passive)
end

-- Bucht n akzeptierte Klicks. t = präzise Serverzeit, now = Serverzeit für Tagesziele.
-- Rückgabe: bezahlter Ertrag, Combo danach
function PressRules.ApplyClicks(d, n, t, now, passes)
	local pr = d.games.press
	n = MiniRules.SafeInt(n, 0, 0, 100000)
	if n <= 0 then
		return 0, pr.combo
	end
	local combo = pr.combo
	local within = pr.comboAt > 0 and t >= pr.comboAt and (t - pr.comboAt) <= MiniConfig.PressComboWindow
	if not within then
		combo = 1
	end
	local base = PressRules.ClickPower(d)
	local ranked = 0
	for i = 1, n do
		if i > 1 or within then
			combo = math.min(MiniConfig.PressComboMax, combo + MiniConfig.PressComboStep)
		end
		ranked += base * combo
	end
	pr.combo = combo
	pr.comboAt = t
	pr.clicks += n
	MiniRules.AddStat(d, "clicks", n, now)
	local paid = ranked * PressRules.PassClickMultiplier(passes)
	credit(d, ranked, paid, now)
	return paid, combo
end

-- Maschinenertrag für eine Zeitspanne (Server-Tick und Offline). Nur Schrott, nie Geld.
function PressRules.Produce(d, seconds, now, passes)
	seconds = MiniRules.SafeNumber(seconds, 0, 0, MiniConfig.PressOfflineCapHours * 3600)
	if seconds <= 0 then
		return 0
	end
	local ranked = PressRules.MachinePower(d) * seconds
	local paid = ranked * PressRules.PassMachineMultiplier(passes)
	credit(d, ranked, paid, now, true)
	return paid
end

-- Offline-Sekunden aus der Differenz der Serverzeit: negativ/unplausibel -> 0, gedeckelt
function PressRules.OfflineSeconds(lastTick, now)
	if not MiniRules.IsFiniteNumber(lastTick) or not MiniRules.IsFiniteNumber(now) or lastTick <= 0 then
		return 0
	end
	local diff = now - lastTick
	if diff <= 0 then
		return 0
	end
	return math.min(diff, MiniConfig.PressOfflineCapHours * 3600)
end

-- Kauf: expectedLevel ist die Stufe, die der Client gesehen hat. Doppelte Absicht -> still verworfen.
function PressRules.BuyUpgrade(d, id, expectedLevel, now)
	local u = type(id) == "string" and MiniCatalog.PressUpgradeById[id]
	if not u then
		return false, "Unbekanntes Upgrade."
	end
	local lvl = PressRules.Level(d, id)
	if type(expectedLevel) ~= "number" or expectedLevel ~= lvl then
		return false, nil
	end
	local cost = PressRules.UpgradeCost(u, lvl)
	local pr = d.games.press
	if pr.scrap < cost then
		return false, "Nicht genug Schrott."
	end
	pr.scrap -= cost
	pr.upgrades[id] = lvl + 1
	MiniRules.AddStat(d, "pressUpgrades", 1, now)
	if u.type == 2 then
		-- Händlerkontakte: etwas Ruf und ein kleiner Credit-Bonus beim Kauf
		MiniRules.AddReputation(d, 1)
		MiniRules.AddMoney(d, math.max(1, math.floor(u.baseEffect * 0.5)))
	end
	return true, u
end

-- Schrott -> Credits in festen Paketen. Es gibt keine Gegenrichtung.
function PressRules.ExchangeCredits(scrap)
	return math.floor(scrap / MiniConfig.ScrapPerCredit * MiniConfig.ScrapExchangePayout)
end

function PressRules.Exchange(d, packageIndex)
	local amount = type(packageIndex) == "number" and MiniConfig.ScrapExchangePackages[packageIndex]
	if not amount then
		return false, "Unbekanntes Paket."
	end
	local pr = d.games.press
	if pr.scrap < amount then
		return false, "Nicht genug Schrott."
	end
	pr.scrap -= amount
	local credits = MiniRules.AddIncome(d, PressRules.ExchangeCredits(amount))
	return true, credits
end

function PressRules.RebirthThreshold(d)
	return MiniConfig.RebirthBaseThreshold * MiniConfig.RebirthThresholdGrowth ^ d.games.press.rebirths
end

function PressRules.CanRebirth(d)
	return d.games.press.runScrap >= PressRules.RebirthThreshold(d)
end

-- Setzt genau Schrott, Durchlauf und Presse-Upgrades zurück.
function PressRules.Rebirth(d, expectedRebirths, now)
	local pr = d.games.press
	if type(expectedRebirths) ~= "number" or expectedRebirths ~= pr.rebirths then
		return false, nil
	end
	if not PressRules.CanRebirth(d) then
		return false, "Rebirth ist erst ab " .. math.floor(PressRules.RebirthThreshold(d)) .. " Schrott in diesem Durchlauf möglich."
	end
	pr.scrap = MiniConfig.PressStartScrap
	pr.runScrap = 0
	pr.upgrades = {}
	pr.combo = 1
	pr.comboAt = 0
	pr.rebirths += 1
	MiniRules.AddStat(d, "rebirths", 1, now)
	return true, PressRules.RebirthMultiplier(d)
end

-- Bestenlisten-Kodierung: OrderedDataStore speichert nur Ganzzahlen; Schrott kann 2^53 übersteigen.
-- log10(1 + x) * 1e13 bleibt für alle Doubles unter 2^53 und ist monoton.
local SCALE = 1e13
function PressRules.EncodeScore(value)
	if not MiniRules.IsFiniteNumber(value) or value <= 0 then
		return 0
	end
	return math.floor(math.log10(1 + value) * SCALE)
end

function PressRules.DecodeScore(code)
	if not MiniRules.IsFiniteNumber(code) or code <= 0 then
		return 0
	end
	local v = 10 ^ (code / SCALE) - 1
	if v < 2 ^ 53 then
		v = math.floor(v + 0.5)
	end
	return v
end

return PressRules
