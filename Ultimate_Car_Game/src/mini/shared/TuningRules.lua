-- TuningRules: Idle Tuning Garage (HTML: tuneCar, idleRate, pendingIdle, collectIdle).
-- d = 2.4.0-Profildaten. Alle Zeiten sind Serverzeit-Sekunden (Unix-Epoche).
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))
local MiniRules = require(script.Parent:WaitForChild("MiniRules"))
local CrossBonus = require(script.Parent:WaitForChild("CrossBonus"))

local TuningRules = {}

function TuningRules.ProjectDef(id)
	return MiniConfig.TuningProjectById[id]
end

function TuningRules.LevelFactor(d)
	return 1 + (d.games.tuningLevel - 1) * 0.085 -- HTML tuneCar
end

-- Überproportional zur Laufzeit: Basis * Minuten^1,2
function TuningRules.BaseReward(def)
	return MiniRules.Round(MiniConfig.TuningRewardBase * def.minutes ^ MiniConfig.TuningRewardExponent)
end

function TuningRules.Reward(d, def)
	return MiniRules.Round(TuningRules.BaseReward(def) * TuningRules.LevelFactor(d) * CrossBonus.PressTuning(d))
end

function TuningRules.Cost(def)
	return MiniRules.Round(TuningRules.BaseReward(def) * MiniConfig.TuningCostShare)
end

function TuningRules.Xp(def)
	return math.max(1, MiniRules.Round(def.minutes * MiniConfig.TuningXpPerMinute))
end

function TuningRules.Slots(d)
	return math.min(MiniConfig.TuningSlotsMax, MiniConfig.TuningSlotsBase + math.floor(d.games.tuningLevel / MiniConfig.TuningSlotsEvery))
end

function TuningRules.FindSlot(d, slot)
	for i, pj in ipairs(d.games.tuning.projects) do
		if pj.slot == slot then
			return i, pj
		end
	end
	return nil, nil
end

function TuningRules.FreeSlot(d)
	for s = 1, TuningRules.Slots(d) do
		if not TuningRules.FindSlot(d, s) then
			return s
		end
	end
	return nil
end

-- Restzeit; eine Serverzeit vor dem Start zählt als "nicht fertig", nie als negativ.
function TuningRules.Remaining(pj, now)
	if now < pj.startedAt then
		return pj.duration
	end
	return math.max(0, pj.startedAt + pj.duration - now)
end

function TuningRules.Start(d, id, now)
	local def = type(id) == "string" and TuningRules.ProjectDef(id)
	if not def then
		return false, "Unbekanntes Projekt."
	end
	if d.games.tuningLevel < def.unlock then
		return false, "Benötigt Tuning-Stufe " .. def.unlock .. "."
	end
	local slot = TuningRules.FreeSlot(d)
	if not slot then
		return false, "Alle Tuning-Plätze sind belegt."
	end
	local cost = TuningRules.Cost(def)
	if d.money < cost then
		return false, "Nicht genug Credits."
	end
	MiniRules.AddMoney(d, -cost)
	table.insert(d.games.tuning.projects, { slot = slot, id = def.id, startedAt = now, duration = def.minutes * 60 })
	MiniRules.AddStat(d, "tuningStarted", 1, now)
	return true, slot
end

function TuningRules.Collect(d, slot, now)
	local idx, pj = TuningRules.FindSlot(d, slot)
	if not idx then
		return false, nil -- schon abgeholt
	end
	if TuningRules.Remaining(pj, now) > 0 then
		return false, "Das Projekt läuft noch."
	end
	local def = TuningRules.ProjectDef(pj.id)
	table.remove(d.games.tuning.projects, idx)
	if not def then
		return true, 0, { levels = 0, credits = 0 }
	end
	local reward = MiniRules.AddIncome(d, TuningRules.Reward(d, def))
	MiniRules.AddReputation(d, 2)
	d.games.tuning.completed += 1
	MiniRules.AddStat(d, "tuningCollected", 1, now)
	if def.minutes >= MiniConfig.TuningLongMinutes then
		MiniRules.AddStat(d, "longTuning", 1, now)
	end
	local xp = MiniRules.GainXP(d, TuningRules.Xp(def))
	return true, reward, xp
end

-- HTML idleRate: Credits pro Minute
function TuningRules.IdleRate(d)
	local g = d.games
	return (10 + g.tuningLevel * 4 + g.tuning.completed ^ 1.12 * 1.5) * CrossBonus.PressTuning(d)
end

function TuningRules.IdleSeconds(d, now)
	local last = d.games.tuning.lastIdle
	if last <= 0 or now <= last then
		return 0
	end
	return math.min(MiniConfig.TuningIdleCapHours * 3600, now - last)
end

function TuningRules.PendingIdle(d, now)
	return math.floor(TuningRules.IdleSeconds(d, now) / 60 * TuningRules.IdleRate(d))
end

function TuningRules.CollectIdle(d, now)
	local value = TuningRules.PendingIdle(d, now)
	if value < 1 then
		return false, "Noch keine Einnahmen."
	end
	local paid = MiniRules.AddIncome(d, value)
	d.games.tuning.lastIdle = now
	MiniRules.AddStat(d, "idleCollected", 1, now)
	local xp = MiniRules.GainXP(d, math.max(1, math.floor(value / 80)))
	return true, paid, xp
end

return TuningRules
