-- GoalRules: Meilensteine, Tagesauftrag, Tagesziele, "Nächstes Ziel", Boni-Übersicht.
local Config = require(script.Parent:WaitForChild("Config"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Locale = require(script.Parent:WaitForChild("Locale"))
local Rules = require(script.Parent:WaitForChild("Rules"))
local PressRules = require(script.Parent:WaitForChild("PressRules"))
local WorkshopRules = require(script.Parent:WaitForChild("WorkshopRules"))
local TuningRules = require(script.Parent:WaitForChild("TuningRules"))

local GoalRules = {}

function GoalRules.Stat(p, key)
	local g = p.games
	if key == "lifetimeScrap" then
		return g.press.lifetime
	elseif key == "level" then
		return p.level
	elseif key == "bestParkingStreak" then
		return g.parking.best
	elseif key == "rebirths" then
		return g.press.rebirths
	end
	return g.stats[key] or 0
end

function GoalRules.Milestone(id)
	for _, m in ipairs(Config.Milestones) do
		if m.id == id then
			return m
		end
	end
	return nil
end

function GoalRules.ClaimMilestone(p, id)
	local m = type(id) == "string" and GoalRules.Milestone(id)
	if not m then
		return false, nil
	end
	if p.games.milestones[id] then
		return false, nil
	end
	if GoalRules.Stat(p, m.stat) < m.target then
		return false, "Ziel noch nicht erreicht."
	end
	p.games.milestones[id] = true
	p.credits += m.credits
	local xp = Rules.GainXP(p, m.xp)
	return true, m, xp
end

-- Tageswechsel (UTC): setzt Tagesauftrag und Tagesziele zurück, sonst nichts.
function GoalRules.EnsureDay(p, now)
	local today = Rules.DayKey(now)
	local dl = p.games.daily
	if dl.day ~= today then
		dl.day = today
		dl.claimed = false
		dl.active = false
		dl.progress = {}
		dl.goalsClaimed = {}
		return true
	end
	return false
end

local TIERS = { "short", "mid", "long" }
function GoalRules.DailyGoals(day)
	local list = {}
	for _, tier in ipairs(TIERS) do
		local pool = Config.DailyGoalPool[tier]
		local idx = (Rules.HashString(day .. ":" .. tier) % #pool) + 1
		table.insert(list, pool[idx])
	end
	return list
end

function GoalRules.DailyGoalText(def)
	return (string.gsub(def.text, "{1}", Locale.Number(def.target)))
end

function GoalRules.ClaimDailyGoal(p, id, now)
	GoalRules.EnsureDay(p, now)
	local dl = p.games.daily
	local def
	for _, d in ipairs(GoalRules.DailyGoals(dl.day)) do
		if d.id == id then
			def = d
		end
	end
	if not def or dl.goalsClaimed[id] then
		return false, nil
	end
	if (dl.progress[def.stat] or 0) < def.target then
		return false, "Tagesziel noch nicht erreicht."
	end
	dl.goalsClaimed[id] = true
	p.credits += def.credits
	return true, def
end

-- HTML claimDaily: einmal pro UTC-Tag, sobald heute ein Bereich gespielt wurde.
function GoalRules.ClaimDaily(p, now)
	GoalRules.EnsureDay(p, now)
	local dl = p.games.daily
	if dl.claimed then
		return false, nil
	end
	if not dl.active then
		return false, "Spiele heute zuerst einen Bereich."
	end
	dl.claimed = true
	p.credits += Config.DailyCredits
	p.games.parts += Config.DailyParts
	local xp = Rules.GainXP(p, Config.DailyXp)
	return true, xp
end

function GoalRules.CheapestPressUpgrade(p)
	local best, bestCost
	for _, u in ipairs(Catalog.PressUpgrades) do
		local cost = PressRules.UpgradeCost(u, PressRules.Level(p, u.id))
		if not bestCost or cost < bestCost then
			best, bestCost = u, cost
		end
	end
	return best, bestCost
end

-- Das nächstliegende Ziel: zuerst Abholbares, sonst das Ziel mit dem größten Fortschritt.
function GoalRules.NextGoal(p, now)
	local g = p.games
	local candidates = {}
	local function add(text, progress, tab)
		table.insert(candidates, { text = text, progress = math.clamp(progress, 0, 1), tab = tab })
	end

	for _, m in ipairs(Config.Milestones) do
		if not g.milestones[m.id] then
			local v = GoalRules.Stat(p, m.stat)
			if v >= m.target then
				add("Meilenstein abholen: " .. m.text, 1, "goals")
			else
				add("Meilenstein: " .. m.text, v / m.target, "goals")
			end
		end
	end
	if g.daily.day == Rules.DayKey(now) then
		for _, def in ipairs(GoalRules.DailyGoals(g.daily.day)) do
			if not g.daily.goalsClaimed[def.id] then
				local v = g.daily.progress[def.stat] or 0
				add((v >= def.target and "Tagesziel abholen: " or "Tagesziel: ") .. GoalRules.DailyGoalText(def), v / def.target, "goals")
			end
		end
	end
	for _, pj in ipairs(g.tuning.projects) do
		local def = TuningRules.ProjectDef(pj.id)
		local remaining = TuningRules.Remaining(pj, now)
		local name = def and def.name or pj.id
		if remaining <= 0 then
			add("Tuning abholen: " .. name, 1, "tuning")
		else
			add("Tuning „" .. name .. "“ fertig in " .. Locale.Duration(remaining), 1 - remaining / pj.duration, "tuning")
		end
	end
	for _, job in ipairs(g.jobs) do
		if now >= job.endsAt then
			add("Auftrag abrechnen: " .. job.name, 1, "workshop")
		end
	end
	local u, cost = GoalRules.CheapestPressUpgrade(p)
	if u then
		local v = g.press.scrap
		add((v >= cost and "Upgrade kaufbar: " or "Nächstes Upgrade: ") .. u.name .. " (" .. Locale.Number(cost) .. " Schrott)", v / cost, "press")
	end

	local best
	for _, c in ipairs(candidates) do
		if not best or c.progress > best.progress then
			best = c
		end
	end
	return best or { text = "Alle Ziele erreicht!", progress = 1, tab = "overview" }
end

function GoalRules.ActiveBoni(p, passes)
	local list = {
		"Presse → Werkstatt: +" .. Locale.Percent(PressRules.WorkshopMultiplier(p) - 1),
		"Presse → Tuning: +" .. Locale.Percent(PressRules.TuningMultiplier(p) - 1),
		"Rebirth-Schrott: ×" .. string.format("%.2f", PressRules.RebirthMultiplier(p)),
		"Tuning-Stufe → Werkstatt: +" .. Locale.Percent(WorkshopRules.TuningWorkshopBonus(p) - 1),
		"Diagnose → Reparaturzeit: −" .. Locale.Percent(WorkshopRules.DiagReduction(p)) .. " (max. " .. Locale.Percent(Config.DiagReductionCap) .. ")",
		"Parkplatz-Serie → Auftragsqualität: ×" .. string.format("%.2f", WorkshopRules.CustomerBonus(p)) .. " (max. ×" .. string.format("%.2f", Config.CustomerBonusCap) .. ")",
		"Werkzeug → Reparaturtempo und Teile: +" .. Locale.Percent((p.games.toolLevel - 1) * 0.08),
	}
	if passes and passes.doubleScrap then
		table.insert(list, "Game Pass 2× Schrott: ×" .. Config.GamePasses.DoubleScrap.multiplier .. " (zählt nicht für die Bestenliste)")
	end
	if passes and passes.pressPlus then
		table.insert(list, "Game Pass Schrottpresse+: Maschinen ×" .. Config.GamePasses.PressPlus.machineMultiplier .. " (zählt nicht für die Bestenliste)")
	end
	return list
end

return GoalRules
