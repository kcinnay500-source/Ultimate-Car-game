-- TuningRules: Idle Tuning Garage (HTML: tuneCar, idleRate, pendingIdle, collectIdle).
-- Alle Zeiten sind os.time()-Sekunden des Servers.
local Config = require(script.Parent:WaitForChild("Config"))
local Rules = require(script.Parent:WaitForChild("Rules"))
local PressRules = require(script.Parent:WaitForChild("PressRules"))

local TuningRules = {}

function TuningRules.ProjectDef(id)
	for _, def in ipairs(Config.TuningProjects) do
		if def.id == id then
			return def
		end
	end
	return nil
end

function TuningRules.LevelFactor(p)
	return 1 + (p.games.tuningLevel - 1) * 0.085 -- HTML tuneCar
end

-- Überproportional zur Laufzeit: Basis * Minuten^1,2
function TuningRules.BaseReward(def)
	return Rules.Round(Config.TuningRewardBase * def.minutes ^ Config.TuningRewardExponent)
end

function TuningRules.Reward(p, def)
	return Rules.Round(TuningRules.BaseReward(def) * TuningRules.LevelFactor(p) * PressRules.TuningMultiplier(p))
end

function TuningRules.Cost(def)
	return Rules.Round(TuningRules.BaseReward(def) * Config.TuningCostShare)
end

function TuningRules.Xp(def)
	return math.max(1, Rules.Round(def.minutes * Config.TuningXpPerMinute))
end

function TuningRules.Slots(p)
	return math.min(Config.TuningSlotsMax, Config.TuningSlotsBase + math.floor(p.games.tuningLevel / Config.TuningSlotsEvery))
end

function TuningRules.FindSlot(p, slot)
	for i, pj in ipairs(p.games.tuning.projects) do
		if pj.slot == slot then
			return i, pj
		end
	end
	return nil, nil
end

function TuningRules.FreeSlot(p)
	for s = 1, TuningRules.Slots(p) do
		if not TuningRules.FindSlot(p, s) then
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

function TuningRules.Start(p, id, now)
	local def = type(id) == "string" and TuningRules.ProjectDef(id)
	if not def then
		return false, "Unbekanntes Projekt."
	end
	if p.games.tuningLevel < def.unlock then
		return false, "Benötigt Tuning-Stufe " .. def.unlock .. "."
	end
	local slot = TuningRules.FreeSlot(p)
	if not slot then
		return false, "Alle Tuning-Plätze sind belegt."
	end
	local cost = TuningRules.Cost(def)
	if p.credits < cost then
		return false, "Nicht genug Credits."
	end
	p.credits -= cost
	table.insert(p.games.tuning.projects, { slot = slot, id = def.id, startedAt = now, duration = def.minutes * 60 })
	Rules.AddStat(p, "tuningStarted", 1, now)
	return true, slot
end

function TuningRules.Collect(p, slot, now)
	local idx, pj = TuningRules.FindSlot(p, slot)
	if not idx then
		return false, nil -- schon abgeholt
	end
	if TuningRules.Remaining(pj, now) > 0 then
		return false, "Das Projekt läuft noch."
	end
	local def = TuningRules.ProjectDef(pj.id)
	table.remove(p.games.tuning.projects, idx)
	if not def then
		return true, 0, { levels = 0, credits = 0 }
	end
	local reward = TuningRules.Reward(p, def)
	p.credits += reward
	p.games.reputation += 2
	p.games.tuning.completed += 1
	Rules.AddStat(p, "tuningCollected", 1, now)
	if def.minutes >= Config.TuningLongMinutes then
		Rules.AddStat(p, "longTuning", 1, now)
	end
	local xp = Rules.GainXP(p, TuningRules.Xp(def))
	return true, reward, xp
end

-- HTML idleRate: Credits pro Minute
function TuningRules.IdleRate(p)
	local g = p.games
	return (10 + g.tuningLevel * 4 + g.tuning.completed ^ 1.12 * 1.5) * PressRules.TuningMultiplier(p)
end

function TuningRules.IdleSeconds(p, now)
	local last = p.games.tuning.lastIdle
	if last <= 0 or now <= last then
		return 0
	end
	return math.min(Config.TuningIdleCapHours * 3600, now - last)
end

function TuningRules.PendingIdle(p, now)
	return math.floor(TuningRules.IdleSeconds(p, now) / 60 * TuningRules.IdleRate(p))
end

function TuningRules.CollectIdle(p, now)
	local value = TuningRules.PendingIdle(p, now)
	if value < 1 then
		return false, "Noch keine Einnahmen."
	end
	p.credits += value
	p.games.tuning.lastIdle = now
	Rules.AddStat(p, "idleCollected", 1, now)
	local xp = Rules.GainXP(p, math.max(1, math.floor(value / 80)))
	return true, value, xp
end

return TuningRules
