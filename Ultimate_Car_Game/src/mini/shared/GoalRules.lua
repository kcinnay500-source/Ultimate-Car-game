-- GoalRules: Meilensteine, Tagesauftrag, Tagesziele, "Nächstes Ziel", Boni-Übersicht.
-- d = 2.4.0-Profildaten (Level d.level, Aufträge d.jobs, Minispiele d.games).
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))
local MiniCatalog = require(script.Parent:WaitForChild("MiniCatalog"))
local MiniLocale = require(script.Parent:WaitForChild("MiniLocale"))
local MiniRules = require(script.Parent:WaitForChild("MiniRules"))
local PressRules = require(script.Parent:WaitForChild("PressRules"))
local TuningRules = require(script.Parent:WaitForChild("TuningRules"))
local CrossBonus = require(script.Parent:WaitForChild("CrossBonus"))
local C = require(script.Parent.Parent:WaitForChild("Config"))

local GoalRules = {}

function GoalRules.Stat(d, key)
	local g = d.games
	if key == "lifetimeScrap" then
		return g.press.lifetime
	elseif key == "level" then
		return d.level
	elseif key == "bestParkingStreak" then
		return g.parking.best
	elseif key == "rebirths" then
		return g.press.rebirths
	end
	return g.stats[key] or 0
end

function GoalRules.Milestone(id)
	return MiniConfig.MilestoneById[id]
end

function GoalRules.ClaimMilestone(d, id)
	local m = type(id) == "string" and GoalRules.Milestone(id)
	if not m then
		return false, nil
	end
	if d.games.milestones[id] then
		return false, nil
	end
	if GoalRules.Stat(d, m.stat) < m.target then
		return false, "Ziel noch nicht erreicht."
	end
	d.games.milestones[id] = true
	MiniRules.AddMoney(d, m.credits)
	local xp = MiniRules.GainXP(d, m.xp)
	return true, m, xp
end

-- Tageswechsel (UTC): setzt Tagesauftrag und Tagesziele zurück, sonst nichts.
function GoalRules.EnsureDay(d, now)
	return MiniRules.EnsureDay(d, now)
end

local TIERS = { "short", "mid", "long" }
function GoalRules.DailyGoals(day)
	local list = {}
	for _, tier in ipairs(TIERS) do
		local pool = MiniConfig.DailyGoalPool[tier]
		local idx = (MiniRules.HashString(day .. ":" .. tier) % #pool) + 1
		table.insert(list, pool[idx])
	end
	return list
end

function GoalRules.DailyGoalText(def)
	return (string.gsub(def.text, "{1}", MiniLocale.Number(def.target)))
end

function GoalRules.ClaimDailyGoal(d, id, now)
	GoalRules.EnsureDay(d, now)
	local dl = d.games.daily
	local def
	for _, candidate in ipairs(GoalRules.DailyGoals(dl.day)) do
		if candidate.id == id then
			def = candidate
		end
	end
	if not def or dl.goalsClaimed[id] then
		return false, nil
	end
	if (dl.progress[def.stat] or 0) < def.target then
		return false, "Tagesziel noch nicht erreicht."
	end
	dl.goalsClaimed[id] = true
	MiniRules.AddMoney(d, def.credits)
	return true, def
end

-- HTML claimDaily: einmal pro UTC-Tag, sobald heute ein Bereich gespielt wurde
-- (Minispiel, Werkstatt-Abrechnung oder Außenarbeit).
function GoalRules.ClaimDaily(d, now)
	GoalRules.EnsureDay(d, now)
	local dl = d.games.daily
	if dl.claimed then
		return false, nil
	end
	if not dl.active then
		return false, "Spiele heute zuerst einen Bereich."
	end
	dl.claimed = true
	MiniRules.AddMoney(d, MiniConfig.DailyCredits)
	d.games.parts = math.min(2 ^ 53, d.games.parts + MiniConfig.DailyParts)
	local xp = MiniRules.GainXP(d, MiniConfig.DailyXp)
	return true, xp
end

function GoalRules.CheapestPressUpgrade(d)
	local best, bestCost
	for _, u in ipairs(MiniCatalog.PressUpgrades) do
		local cost = PressRules.UpgradeCost(u, PressRules.Level(d, u.id))
		if not bestCost or cost < bestCost then
			best, bestCost = u, cost
		end
	end
	return best, bestCost
end

-- Das nächstliegende Ziel: zuerst Abholbares, sonst das Ziel mit dem größten Fortschritt.
-- tab "workshop" meint die 2.4.0-Werkstatt (Empfang/Abrechnung), alle anderen sind Minispiel-Tabs.
function GoalRules.NextGoal(d, now)
	local g = d.games
	local candidates = {}
	local function add(text, progress, tab)
		table.insert(candidates, { text = text, progress = math.clamp(progress, 0, 1), tab = tab })
	end

	for _, m in ipairs(MiniConfig.Milestones) do
		if not g.milestones[m.id] then
			local v = GoalRules.Stat(d, m.stat)
			if v >= m.target then
				add("Meilenstein abholen: " .. m.text, 1, "goals")
			else
				add("Meilenstein: " .. m.text, v / m.target, "goals")
			end
		end
	end
	if g.daily.day == MiniRules.DayKey(now) then
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
			add("Tuning „" .. name .. "“ fertig in " .. MiniLocale.Duration(remaining), 1 - remaining / pj.duration, "tuning")
		end
	end
	-- 2.4.0-Werkstatt: Aufträge nach bestandener Endkontrolle warten am Empfang auf die Abrechnung
	for _, job in ipairs(type(d.jobs) == "table" and d.jobs or {}) do
		if job.phase == "invoice" then
			local def = C.JobById[job.kind]
			add("Auftrag abrechnen: " .. (def and def.name or "Kundenauto"), 1, "workshop")
		end
	end
	local u, cost = GoalRules.CheapestPressUpgrade(d)
	if u then
		local v = g.press.scrap
		add((v >= cost and "Upgrade kaufbar: " or "Nächstes Upgrade: ") .. u.name .. " (" .. MiniLocale.Number(cost) .. " Schrott)", v / cost, "press")
	end

	local best
	for _, c in ipairs(candidates) do
		if not best or c.progress > best.progress then
			best = c
		end
	end
	return best or { text = "Alle Ziele erreicht!", progress = 1, tab = "overview" }
end

function GoalRules.ActiveBoni(d, passes)
	local toolLevel = MiniRules.SafeNumber(d.toolLevel, 1, 1, 1e6)
	local list = {
		"Presse → Werkstatt: +" .. MiniLocale.Percent(CrossBonus.PressWorkshop(d) - 1),
		"Presse → Tuning: +" .. MiniLocale.Percent(CrossBonus.PressTuning(d) - 1),
		"Rebirth-Schrott: " .. MiniLocale.Factor(PressRules.RebirthMultiplier(d)),
		"Tuning-Stufe → Werkstatt: +" .. MiniLocale.Percent(CrossBonus.TuningWorkshop(d) - 1),
		"Diagnose → Reparaturzeit: −" .. MiniLocale.Percent(CrossBonus.DiagReduction(d)) .. " (max. " .. MiniLocale.Percent(MiniConfig.DiagReductionCap) .. ")",
		"Parkplatz-Serie → Werkstatt-Vergütung: " .. MiniLocale.Factor(CrossBonus.CustomerBonus(d)) .. " (max. " .. MiniLocale.Factor(MiniConfig.CustomerBonusCap) .. ")",
		"Parkplatz-Serie → Kundenangebote: +" .. CrossBonus.OfferBonus(d),
		"Werkzeugqualität → Reparaturtempo +" .. MiniLocale.Percent((toolLevel - 1) * 0.08) .. ", Schrottplatz-Funde +" .. MiniLocale.Percent((toolLevel - 1) * 0.14),
	}
	if passes and passes.doubleScrap then
		table.insert(list, "Game Pass 2× Schrott: ×" .. MiniConfig.GamePasses.DoubleScrap.multiplier .. " (zählt nicht für die Bestenliste)")
	end
	if passes and passes.pressPlus then
		table.insert(list, "Game Pass Schrottpresse+: Maschinen " .. MiniLocale.Factor(MiniConfig.GamePasses.PressPlus.machineMultiplier) .. " (zählt nicht für die Bestenliste)")
	end
	return list
end

return GoalRules
