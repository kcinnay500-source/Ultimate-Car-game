-- CrossBonus: Querboni der Minispiele auf die 2.4.0-Werkstatt (HTML workshopBonus, diagReduction,
-- customerBonus, clickerWorkshopMultiplier). Benötigt nur MiniConfig, GameConfig und PrestigeRules (alle
-- ohne Rückbezug auf Rules/MiniRules), damit GarageShared.Rules es ohne Ringabhängigkeit laden kann.
-- Alle Funktionen sind nil-sicher: der Client ruft R.Reward auf state.data auf, und Profile ohne
-- games (oder ein fehlendes d) ergeben neutrale Werte (1 bzw. 0).
-- Ausbaustufe 4 (docs/PHASE4_CONTRACT.md §4, §8): Prestige-Einnahmenbonus (PrestigeIncome), Tycoon-Durchläufe
-- (TycoonWorkshop), Open-World-Perks (OWPerk, Platzhalter bis Meilenstein 6). Der Gesamtfaktor auf die
-- Werkstatt-Vergütung (WorkshopReward) ist auf GameConfig.WorkshopRewardCap (Standard ×1,6) gedeckelt.
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local PrestigeRules = require(script.Parent:WaitForChild("PrestigeRules"))

local CrossBonus = {}

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function games(d)
	local g = type(d) == "table" and d.games
	return type(g) == "table" and g or nil
end

local function sub(d, key)
	local g = games(d)
	local t = g and g[key]
	return type(t) == "table" and t or nil
end

-- Summe aller Presse-Upgrade-Stufen
function CrossBonus.PressLevels(d)
	local press = sub(d, "press")
	local ups = press and press.upgrades
	if type(ups) ~= "table" then
		return 0
	end
	local total = 0
	for _, lvl in pairs(ups) do
		if finite(lvl) and lvl > 0 then
			total += lvl
		end
	end
	return total
end

-- HTML clickerGlobalMultiplier
function CrossBonus.PressGlobal(d)
	return 1 + CrossBonus.PressLevels(d) * MiniConfig.PressGlobalPerLevel
end

-- Presse -> Werkstatt: 60 % des Presse-Multiplikators
function CrossBonus.PressWorkshop(d)
	return 1 + (CrossBonus.PressGlobal(d) - 1) * MiniConfig.PressWorkshopShare
end

-- Presse -> Tuning: 80 % des Presse-Multiplikators
function CrossBonus.PressTuning(d)
	return 1 + (CrossBonus.PressGlobal(d) - 1) * MiniConfig.PressTuningShare
end

-- Tuning-Stufe -> Werkstatt: +4,5 % je Stufe über 1
function CrossBonus.TuningWorkshop(d)
	local g = games(d)
	local lvl = g and g.tuningLevel
	if not finite(lvl) or lvl < 1 then
		return 1
	end
	return 1 + (lvl - 1) * 0.045
end

-- Diagnosepunkte aus dem Quiz verkürzen Reparaturen: min(35 %, Punkte × 1,5 %)
function CrossBonus.DiagReduction(d)
	local quiz = sub(d, "quiz")
	local points = quiz and quiz.diagPoints
	if not finite(points) or points <= 0 then
		return 0
	end
	return math.min(MiniConfig.DiagReductionCap, points * MiniConfig.DiagReductionPerPoint)
end

-- Parkplatz-Serie -> Kundenbonus auf die Vergütung, höchstens ×1,7
function CrossBonus.CustomerBonus(d)
	local parking = sub(d, "parking")
	local streak = parking and parking.streak
	if not finite(streak) or streak <= 0 then
		return 1
	end
	return math.min(MiniConfig.CustomerBonusCap, 1 + streak * MiniConfig.CustomerBonusPerStreak)
end

-- Parkplatz-Serie -> zusätzliche Angebote am Empfang (+1 je 5er-Serie, höchstens +5)
function CrossBonus.OfferBonus(d)
	local parking = sub(d, "parking")
	local streak = parking and parking.streak
	if not finite(streak) or streak <= 0 then
		return 0
	end
	return math.min(MiniConfig.ParkingOfferBonusMax, math.floor(streak / MiniConfig.ParkingOfferBonusEvery))
end

---------------------------------------------------------------- Ausbaustufe 4: Prestige, Tycoon, Open World
-- Deckel des Gesamtfaktors auf die Werkstatt (Vertrag §8: ×1,6). Das Balance-Team stellt ihn über
-- GameConfig.WorkshopRewardCap ein; fehlt der Eintrag, gilt der Vertragswert.
CrossBonus.WorkshopCapDefault = 1.6
-- Tycoon-Bonus werkstatt (Vertrag §8): je abgeschlossenem Durchlauf +2 %, höchstens 5 Durchläufe (+10 %).
-- Ab Meilenstein 4 liegen die Zahlen in GameConfig.Tycoon.Bonus.werkstatt = { step = 0.02, maxRuns = 5 };
-- bis dahin gelten die Vertragswerte.
CrossBonus.TycoonWorkshopDefault = { step = 0.02, maxRuns = 5 }

function CrossBonus.WorkshopCap(): number
	local cap = GameConfig.WorkshopRewardCap
	if finite(cap) and cap >= 1 then
		return cap
	end
	return CrossBonus.WorkshopCapDefault
end

-- Prestige-Rang -> alle Credits-Einnahmen: 1 + 0,02 je Rang, Deckel +30 % (PrestigeRules.IncomeBonus)
function CrossBonus.PrestigeIncome(d: any): number
	local ok, factor = pcall(PrestigeRules.IncomeBonus, d)
	if ok and finite(factor) and factor >= 1 then
		return factor
	end
	return 1
end

-- Abgeschlossene Tycoon-Durchläufe eines Gebäudetyps (d.games.tycoon.runsDone[typ]); 0, solange es die
-- Tabelle noch nicht gibt (Meilenstein 4) oder der Wert kein endlicher Zähler ist.
function CrossBonus.TycoonRuns(d: any, typ: string): number
	local tycoon = sub(d, "tycoon")
	local runs = tycoon and tycoon.runsDone
	local n = type(runs) == "table" and runs[typ] or nil
	if not finite(n) or n <= 0 then
		return 0
	end
	return math.floor(n)
end

-- Tycoon-Durchläufe „Werkstatt“ -> Werkstatt-Vergütung: 1 + min(n, 5) × 0,02
function CrossBonus.TycoonWorkshop(d: any): number
	local tycoon = GameConfig.Tycoon
	local bonus = type(tycoon) == "table" and type(tycoon.Bonus) == "table" and tycoon.Bonus.werkstatt or nil
	local step = type(bonus) == "table" and bonus.step or nil
	local maxRuns = type(bonus) == "table" and bonus.maxRuns or nil
	if not finite(step) or step < 0 then
		step = CrossBonus.TycoonWorkshopDefault.step
	end
	if not finite(maxRuns) or maxRuns < 0 then
		maxRuns = CrossBonus.TycoonWorkshopDefault.maxRuns
	end
	return 1 + math.min(CrossBonus.TycoonRuns(d, "werkstatt"), maxRuns) * step
end

-- Open-World-Perk eines Karrierewegs (GameConfig.OW.Perks, Meilenstein 6): Platzhalter, wirkt neutral.
-- typ: werkstatt | autohaus | schrottplatz | produktion
function CrossBonus.OWPerk(d: any, typ: string?): number
	return 1
end

-- Faktor der Ausbaustufe 4 (Prestige × Tycoon × Open-World-Perk), ungedeckelt
function CrossBonus.CareerBonus(d: any): number
	return CrossBonus.PrestigeIncome(d) * CrossBonus.TycoonWorkshop(d) * CrossBonus.OWPerk(d, "werkstatt")
end

-- Gesamtfaktor auf die Werkstatt-Vergütung ohne Deckel (für Anzeigen, die den Deckel erklären)
function CrossBonus.WorkshopRewardRaw(d: any): number
	return CrossBonus.PressWorkshop(d) * CrossBonus.TuningWorkshop(d) * CrossBonus.CustomerBonus(d) * CrossBonus.CareerBonus(d)
end

-- Gesamtfaktor auf die Werkstatt-Vergütung (R.Reward): Presse × Tuning-Stufe × Kundenbonus × Prestige × Tycoon
-- × OW-Perk, zusammen gedeckelt auf WorkshopCap (Vertrag §8: ×1,6), nie unter 1.
function CrossBonus.WorkshopReward(d: any): number
	local raw = CrossBonus.WorkshopRewardRaw(d)
	if not finite(raw) or raw < 1 then
		return 1
	end
	return math.min(CrossBonus.WorkshopCap(), raw)
end

return CrossBonus
