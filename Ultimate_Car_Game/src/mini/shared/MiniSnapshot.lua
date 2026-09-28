-- MiniSnapshot: der Minispiel-Zustand, den der Server an den Besitzer schickt (Event-Kind "mini").
-- Rein und testbar. d = 2.4.0-Profildaten; quizState = Quiz-Zustand der Server-Sitzung (optional).
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))
local MiniRules = require(script.Parent:WaitForChild("MiniRules"))
local PressRules = require(script.Parent:WaitForChild("PressRules"))
local TuningRules = require(script.Parent:WaitForChild("TuningRules"))
local SideGameRules = require(script.Parent:WaitForChild("SideGameRules"))
local GoalRules = require(script.Parent:WaitForChild("GoalRules"))
local CrossBonus = require(script.Parent:WaitForChild("CrossBonus"))
local C = require(script.Parent.Parent:WaitForChild("Config"))
local R = require(script.Parent.Parent:WaitForChild("Rules"))

local MiniSnapshot = {}

local function copy(t)
	local out = {}
	for k, v in pairs(t) do
		out[k] = v
	end
	return out
end

function MiniSnapshot.Build(d, now, passes, quizState)
	local g = d.games
	local pr = g.press

	local upgrades = {}
	for _, u in ipairs(MiniConfig.Upgrades) do
		table.insert(upgrades, {
			key = u.key, name = u.name, desc = u.desc, level = g[u.key], max = u.max,
			cost = MiniRules.UpgradeCost(d, u),
		})
	end

	local exchange = {}
	for i, amount in ipairs(MiniConfig.ScrapExchangePackages) do
		table.insert(exchange, { index = i, amount = amount, credits = PressRules.ExchangeCredits(amount) })
	end

	local ready = 0
	for _, job in ipairs(d.jobs) do
		if job.phase == "invoice" then
			ready += 1
		end
	end

	local projects = {}
	for _, pj in ipairs(g.tuning.projects) do
		local def = TuningRules.ProjectDef(pj.id)
		table.insert(projects, {
			slot = pj.slot, id = pj.id, name = def and def.name or pj.id, duration = pj.duration,
			remaining = TuningRules.Remaining(pj, now), reward = def and TuningRules.Reward(d, def) or 0,
		})
	end
	local catalog = {}
	for _, def in ipairs(MiniConfig.TuningProjects) do
		table.insert(catalog, {
			id = def.id, name = def.name, minutes = def.minutes, unlock = def.unlock,
			locked = g.tuningLevel < def.unlock, cost = TuningRules.Cost(def), reward = TuningRules.Reward(d, def),
		})
	end

	local milestones = {}
	for _, m in ipairs(MiniConfig.Milestones) do
		table.insert(milestones, {
			id = m.id, text = m.text, value = GoalRules.Stat(d, m.stat), target = m.target,
			claimed = g.milestones[m.id] == true, credits = m.credits,
		})
	end
	local today = MiniRules.DayKey(now)
	local sameDay = g.daily.day == today
	local dailyGoals = {}
	for i, def in ipairs(GoalRules.DailyGoals(today)) do
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
			cars = copy(pz.cars), target = pz.target, exit = pz.exit, moves = pz.moves, solved = pz.solved, crashed = pz.crashed,
			path = SideGameRules.ParkingPath(pz.target), blocked = SideGameRules.ParkingBlocked(pz),
		}
	end

	return {
		version = C.Version,
		now = now,
		credits = d.money,
		level = d.level,
		xp = d.xp,
		xpNeeded = R.XPNeeded(d),
		reputation = d.reputation,
		parts = g.parts,
		upgrades = upgrades,
		workshopJobs = { total = #d.jobs, ready = ready, bays = d.bays },
		press = {
			scrap = pr.scrap,
			lifetime = pr.lifetime,
			runScrap = pr.runScrap,
			clicks = pr.clicks,
			levels = copy(pr.upgrades),
			clickPower = PressRules.ClickPower(d) * PressRules.PassClickMultiplier(passes),
			machinePerSecond = PressRules.MachinePower(d) * PressRules.PassMachineMultiplier(passes),
			globalMultiplier = PressRules.GlobalMultiplier(d),
			rebirths = pr.rebirths,
			rebirthMultiplier = PressRules.RebirthMultiplier(d),
			nextRebirthMultiplier = 1 + (pr.rebirths + 1) * MiniConfig.RebirthMultiplierPerRebirth,
			rebirthThreshold = PressRules.RebirthThreshold(d),
			canRebirth = PressRules.CanRebirth(d),
			workshopMultiplier = PressRules.WorkshopMultiplier(d),
			tuningMultiplier = PressRules.TuningMultiplier(d),
			exchange = exchange,
		},
		tuning = {
			level = g.tuningLevel,
			slots = TuningRules.Slots(d),
			projects = projects,
			catalog = catalog,
			idleRate = TuningRules.IdleRate(d),
			pendingIdle = TuningRules.PendingIdle(d, now),
			idleSeconds = TuningRules.IdleSeconds(d, now),
			idleCapSeconds = MiniConfig.TuningIdleCapHours * 3600,
			completed = g.tuning.completed,
		},
		scrapyard = {
			vehicle = g.scrapyard.vehicle,
			readyIn = SideGameRules.DismantleIn(d, now),
			carsLeft = SideGameRules.ScrapyardCarsLeft(d, now),
			carsPerDay = MiniConfig.ScrapyardCarsPerDay,
			carCost = MiniConfig.ScrapyardCarCost,
			rareChance = SideGameRules.RareChance(d),
			toolBonus = SideGameRules.ToolBonus(d),
			sellParts = MiniConfig.ScrapyardSellParts,
			sellCredits = MiniConfig.ScrapyardSellCredits,
		},
		quiz = {
			diagPoints = g.quiz.diagPoints,
			reduction = CrossBonus.DiagReduction(d),
			question = SideGameRules.QuestionView(quizState),
			paidLeft = SideGameRules.QuizPaidLeft(d, now),
		},
		parking = {
			streak = g.parking.streak,
			best = g.parking.best,
			size = MiniConfig.ParkingSize,
			customerBonus = CrossBonus.CustomerBonus(d),
			paidLeft = SideGameRules.ParkingPaidLeft(d, now),
			nextReward = SideGameRules.ParkingReward(g.parking.streak + 1),
			offerBonus = CrossBonus.OfferBonus(d),
			puzzle = puzzle,
		},
		goals = {
			milestones = milestones,
			daily = {
				claimed = sameDay and g.daily.claimed,
				active = sameDay and g.daily.active,
				credits = MiniConfig.DailyCredits, parts = MiniConfig.DailyParts, xp = MiniConfig.DailyXp,
				goals = dailyGoals,
			},
			next = GoalRules.NextGoal(d, now),
			boni = GoalRules.ActiveBoni(d, passes),
		},
		passes = {
			doubleScrap = passes and passes.doubleScrap == true or false,
			pressPlus = passes and passes.pressPlus == true or false,
			doubleScrapConfigured = MiniConfig.GamePasses.DoubleScrap.id > 0,
			pressPlusConfigured = MiniConfig.GamePasses.PressPlus.id > 0,
		},
	}
end

return MiniSnapshot
