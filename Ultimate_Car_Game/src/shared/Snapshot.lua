-- Snapshot: der Zustand, den der Server an den Besitzer schickt. Rein, testbar.
local Config = require(script.Parent:WaitForChild("Config"))
local Rules = require(script.Parent:WaitForChild("Rules"))
local PressRules = require(script.Parent:WaitForChild("PressRules"))
local WorkshopRules = require(script.Parent:WaitForChild("WorkshopRules"))
local TuningRules = require(script.Parent:WaitForChild("TuningRules"))
local SideGameRules = require(script.Parent:WaitForChild("SideGameRules"))
local GoalRules = require(script.Parent:WaitForChild("GoalRules"))

local Snapshot = {}

function Snapshot.Build(p, now, passes)
	local g = p.games
	local pr = g.press

	local upgrades = {}
	for _, u in ipairs(Config.Upgrades) do
		table.insert(upgrades, {
			key = u.key, name = u.name, desc = u.desc, level = g[u.key], max = u.max,
			cost = WorkshopRules.UpgradeCost(p, u),
		})
	end

	local exchange = {}
	for i, amount in ipairs(Config.ScrapExchangePackages) do
		table.insert(exchange, { index = i, amount = amount, credits = PressRules.ExchangeCredits(amount) })
	end

	local offers = {}
	for _, j in ipairs(g.offers) do
		local cash, useParts = WorkshopRules.CashCost(p, j)
		table.insert(offers, {
			id = j.id, name = j.name, time = math.ceil(j.time / WorkshopRules.RepairSpeed(p)), cash = cash, partUse = useParts,
			parts = j.parts, reward = WorkshopRules.Reward(p, j), xp = j.xp,
		})
	end
	local jobs = {}
	for _, j in ipairs(g.jobs) do
		table.insert(jobs, { id = j.id, name = j.name, startedAt = j.startedAt, endsAt = j.endsAt, reward = WorkshopRules.Reward(p, j) })
	end

	local projects = {}
	for _, pj in ipairs(g.tuning.projects) do
		local def = TuningRules.ProjectDef(pj.id)
		table.insert(projects, {
			slot = pj.slot, id = pj.id, name = def and def.name or pj.id, duration = pj.duration,
			remaining = TuningRules.Remaining(pj, now), reward = def and TuningRules.Reward(p, def) or 0,
		})
	end
	local catalog = {}
	for _, def in ipairs(Config.TuningProjects) do
		table.insert(catalog, {
			id = def.id, name = def.name, minutes = def.minutes, unlock = def.unlock,
			locked = g.tuningLevel < def.unlock, cost = TuningRules.Cost(def), reward = TuningRules.Reward(p, def),
		})
	end

	local milestones = {}
	for _, m in ipairs(Config.Milestones) do
		table.insert(milestones, {
			id = m.id, text = m.text, value = GoalRules.Stat(p, m.stat), target = m.target,
			claimed = g.milestones[m.id] == true, credits = m.credits,
		})
	end
	local today = Rules.DayKey(now)
	local dailyGoals = {}
	for i, def in ipairs(GoalRules.DailyGoals(today)) do
		local sameDay = g.daily.day == today
		table.insert(dailyGoals, {
			id = def.id, tier = i, text = GoalRules.DailyGoalText(def),
			value = sameDay and (g.daily.progress[def.stat] or 0) or 0, target = def.target,
			claimed = sameDay and g.daily.goalsClaimed[def.id] == true, credits = def.credits,
		})
	end

	local pz = g.parking.puzzle
	local puzzle = nil
	if pz then
		puzzle = {
			cars = pz.cars, target = pz.target, exit = pz.exit, moves = pz.moves, solved = pz.solved, crashed = pz.crashed,
			path = SideGameRules.ParkingPath(pz.target), blocked = SideGameRules.ParkingBlocked(pz),
		}
	end

	return {
		version = Config.Version,
		now = now,
		credits = p.credits,
		level = p.level,
		xp = p.xp,
		xpNeeded = Rules.XpNeeded(p.level),
		reputation = g.reputation,
		parts = g.parts,
		upgrades = upgrades,
		press = {
			scrap = pr.scrap,
			lifetime = pr.lifetime,
			runScrap = pr.runScrap,
			clicks = pr.clicks,
			levels = pr.upgrades,
			clickPower = PressRules.ClickPower(p) * PressRules.PassClickMultiplier(passes),
			machinePerSecond = PressRules.MachinePower(p) * PressRules.PassMachineMultiplier(passes),
			globalMultiplier = PressRules.GlobalMultiplier(p),
			rebirths = pr.rebirths,
			rebirthMultiplier = PressRules.RebirthMultiplier(p),
			nextRebirthMultiplier = 1 + (pr.rebirths + 1) * Config.RebirthMultiplierPerRebirth,
			rebirthThreshold = PressRules.RebirthThreshold(p),
			canRebirth = PressRules.CanRebirth(p),
			workshopMultiplier = PressRules.WorkshopMultiplier(p),
			tuningMultiplier = PressRules.TuningMultiplier(p),
			exchange = exchange,
		},
		workshop = {
			bays = g.bays,
			available = WorkshopRules.AvailableBays(p, now),
			offers = offers,
			jobs = jobs,
			repairSpeed = WorkshopRules.RepairSpeed(p),
		},
		tuning = {
			level = g.tuningLevel,
			slots = TuningRules.Slots(p),
			projects = projects,
			catalog = catalog,
			idleRate = TuningRules.IdleRate(p),
			pendingIdle = TuningRules.PendingIdle(p, now),
			idleSeconds = TuningRules.IdleSeconds(p, now),
			idleCapSeconds = Config.TuningIdleCapHours * 3600,
			completed = g.tuning.completed,
		},
		scrapyard = {
			vehicle = g.scrapyard.vehicle,
			carCost = Config.ScrapyardCarCost,
			rareChance = SideGameRules.RareChance(p),
			toolBonus = SideGameRules.ToolBonus(p),
			sellParts = Config.ScrapyardSellParts,
			sellCredits = Config.ScrapyardSellCredits,
		},
		quiz = {
			diagPoints = g.quiz.diagPoints,
			reduction = WorkshopRules.DiagReduction(p),
			question = SideGameRules.QuestionView(p),
		},
		parking = {
			streak = g.parking.streak,
			best = g.parking.best,
			size = Config.ParkingSize,
			customerBonus = WorkshopRules.CustomerBonus(p),
			puzzle = puzzle,
		},
		goals = {
			milestones = milestones,
			daily = {
				claimed = g.daily.day == today and g.daily.claimed,
				active = g.daily.day == today and g.daily.active,
				credits = Config.DailyCredits, parts = Config.DailyParts, xp = Config.DailyXp,
				goals = dailyGoals,
			},
			next = GoalRules.NextGoal(p, now),
			boni = GoalRules.ActiveBoni(p, passes),
		},
		passes = {
			doubleScrap = passes and passes.doubleScrap == true or false,
			pressPlus = passes and passes.pressPlus == true or false,
			doubleScrapConfigured = Config.GamePasses.DoubleScrap.id > 0,
			pressPlusConfigured = Config.GamePasses.PressPlus.id > 0,
		},
	}
end

return Snapshot
