-- CrossBonus: Querboni der Minispiele auf die 2.4.0-Werkstatt (HTML workshopBonus, diagReduction,
-- customerBonus, clickerWorkshopMultiplier). Blattmodul: benötigt nur MiniConfig, damit
-- GarageShared.Rules es ohne Ringabhängigkeit laden kann.
-- Alle Funktionen sind nil-sicher: der Client ruft R.Reward auf state.data auf, und Profile ohne
-- games (oder ein fehlendes d) ergeben neutrale Werte (1 bzw. 0).
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))

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

-- Gesamtfaktor auf die Werkstatt-Vergütung (R.Reward)
function CrossBonus.WorkshopReward(d)
	return CrossBonus.PressWorkshop(d) * CrossBonus.TuningWorkshop(d) * CrossBonus.CustomerBonus(d)
end

return CrossBonus
