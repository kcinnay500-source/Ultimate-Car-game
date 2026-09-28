-- WorkshopRules: Werkstatt-Aufträge und Ausbau (HTML: refreshOffers, acceptJob, finishJob, upgrades).
local Config = require(script.Parent:WaitForChild("Config"))
local Rules = require(script.Parent:WaitForChild("Rules"))
local PressRules = require(script.Parent:WaitForChild("PressRules"))

local WorkshopRules = {}

-- HTML workshopBonus (ohne Karriere-Prestige, das nicht Teil von 3.0 ist)
function WorkshopRules.TuningWorkshopBonus(p)
	return 1 + (p.games.tuningLevel - 1) * 0.045
end

-- HTML diagReduction, gedeckelt auf 35 %
function WorkshopRules.DiagReduction(p)
	return math.min(Config.DiagReductionCap, p.games.quiz.diagPoints * Config.DiagReductionPerPoint)
end

-- HTML customerBonus, gedeckelt auf 1,7
function WorkshopRules.CustomerBonus(p)
	return math.min(Config.CustomerBonusCap, 1 + p.games.parking.streak * Config.CustomerBonusPerStreak)
end

function WorkshopRules.RepairSpeed(p)
	return (1 + (p.games.toolLevel - 1) * 0.08) * (1 - WorkshopRules.DiagReduction(p))
end

function WorkshopRules.AvailableBays(p, now)
	return p.games.bays - #p.games.jobs
end

function WorkshopRules.DesiredOffers(p)
	local g = p.games
	return math.min(Config.MaxOffers, math.max(3, g.offerSlots) + math.min(Config.ParkingOfferBonusMax, math.floor(g.parking.streak / Config.ParkingOfferBonusEvery)))
end

-- Füllt die Angebotsliste auf. rng: Objekt mit NextNumber() und NextInteger(a, b)
function WorkshopRules.RefreshOffers(p, rng)
	local g = p.games
	local desired = WorkshopRules.DesiredOffers(p)
	while #g.offers < desired do
		local maxIndex = math.min(#Config.Jobs, 3 + math.floor(p.level / 20))
		local src = Config.Jobs[rng:NextInteger(1, maxIndex)]
		local job = { name = src.name, time = src.time, cost = src.cost, reward = src.reward, xp = src.xp, parts = src.parts }
		local tier = math.max(0, math.floor(p.level / 75))
		if tier > 0 and rng:NextNumber() < math.min(0.75, tier * 0.035) then
			job.name = Config.JobTierNames[(tier % #Config.JobTierNames) + 1] .. " T" .. tier
			job.time = Rules.Round(job.time * (1 + tier * 0.18))
			job.cost = Rules.Round(job.cost * (1 + tier * 0.25))
			job.parts = Rules.Round(job.parts * (1 + tier * 0.12))
			job.reward = Rules.Round(job.reward * (1 + tier * 0.55))
			job.xp = Rules.Round(job.xp * (1 + tier * 0.32))
		end
		local quality = WorkshopRules.CustomerBonus(p)
		job.reward = Rules.Round(job.reward * quality)
		job.xp = Rules.Round(job.xp * (1 + (quality - 1) * 0.5))
		job.id = g.nextId
		job.startedAt = 0
		job.endsAt = 0
		g.nextId += 1
		table.insert(g.offers, job)
	end
end

function WorkshopRules.CashCost(p, job)
	local useParts = math.min(p.games.parts, job.parts)
	local remaining = job.parts - useParts
	return Rules.Round(job.cost * (remaining / math.max(1, job.parts))), useParts
end

local function findIndex(list, id)
	for i, j in ipairs(list) do
		if j.id == id then
			return i
		end
	end
	return nil
end

function WorkshopRules.Accept(p, id, now, rng)
	local g = p.games
	local idx = type(id) == "number" and findIndex(g.offers, id)
	if not idx then
		return false, nil -- Angebot schon angenommen oder unbekannt
	end
	if WorkshopRules.AvailableBays(p, now) <= 0 then
		return false, "Keine Hebebühne frei."
	end
	local job = g.offers[idx]
	local cash, useParts = WorkshopRules.CashCost(p, job)
	if p.credits < cash then
		return false, "Du brauchst " .. cash .. " Cr oder mehr Teile."
	end
	g.parts -= useParts
	p.credits -= cash
	table.remove(g.offers, idx)
	local duration = job.time / WorkshopRules.RepairSpeed(p)
	job.time = duration
	job.startedAt = now
	job.endsAt = now + math.ceil(duration)
	table.insert(g.jobs, job)
	WorkshopRules.RefreshOffers(p, rng)
	return true, job
end

function WorkshopRules.Reward(p, job)
	return Rules.Round(job.reward * WorkshopRules.TuningWorkshopBonus(p) * PressRules.WorkshopMultiplier(p))
end

function WorkshopRules.Finish(p, id, now, rng)
	local g = p.games
	local idx = type(id) == "number" and findIndex(g.jobs, id)
	if not idx then
		return false, nil
	end
	local job = g.jobs[idx]
	if now < job.endsAt then
		return false, "Die Reparatur läuft noch."
	end
	table.remove(g.jobs, idx)
	local reward = WorkshopRules.Reward(p, job)
	p.credits += reward
	g.reputation += 1 + math.floor(g.tuningLevel / 3)
	Rules.AddStat(p, "jobsDone", 1, now)
	local xp = Rules.GainXP(p, job.xp)
	WorkshopRules.RefreshOffers(p, rng)
	return true, reward, xp
end

-- Ausbau (HTML upgradeCost/buyUpgrade)
function WorkshopRules.UpgradeDef(key)
	for _, u in ipairs(Config.Upgrades) do
		if u.key == key then
			return u
		end
	end
	return nil
end

function WorkshopRules.UpgradeCost(p, u)
	return Rules.Round(u.base * u.growth ^ (p.games[u.key] - 1))
end

function WorkshopRules.BuyUpgrade(p, key, expectedLevel, now, rng)
	local u = type(key) == "string" and WorkshopRules.UpgradeDef(key)
	if not u then
		return false, "Unbekannter Ausbau."
	end
	local lvl = p.games[u.key]
	if type(expectedLevel) ~= "number" or expectedLevel ~= lvl then
		return false, nil
	end
	if lvl >= u.max then
		return false, "Maximale Stufe erreicht."
	end
	local cost = WorkshopRules.UpgradeCost(p, u)
	if p.credits < cost then
		return false, "Nicht genug Credits."
	end
	p.credits -= cost
	p.games[u.key] = lvl + 1
	local xp = Rules.GainXP(p, Config.UpgradeXp)
	if u.key == "offerSlots" then
		WorkshopRules.RefreshOffers(p, rng)
	end
	return true, u, xp
end

return WorkshopRules
