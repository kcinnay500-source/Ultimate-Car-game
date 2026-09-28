-- SideGameRules: Schrottplatz, Mechaniker-Quiz, Parkplatz-Chaos (HTML: buyScrap, sellParts, answerQuestion, startParking, tapSpot).
local Config = require(script.Parent:WaitForChild("Config"))
local Catalog = require(script.Parent:WaitForChild("Catalog"))
local Rules = require(script.Parent:WaitForChild("Rules"))

local SideGameRules = {}

---------------------------------------------------------------- Schrottplatz
function SideGameRules.ToolBonus(p)
	return 1 + (p.games.toolLevel - 1) * 0.14 -- HTML scrapBonus
end

function SideGameRules.RareChance(p)
	return 0.08 + p.games.scrapyardLevel * 0.025
end

function SideGameRules.BuyVehicle(p)
	local sy = p.games.scrapyard
	if sy.vehicle then
		return false, "Es steht schon ein Fahrzeug zum Zerlegen bereit."
	end
	if p.credits < Config.ScrapyardCarCost then
		return false, "Nicht genug Credits."
	end
	p.credits -= Config.ScrapyardCarCost
	sy.vehicle = true
	return true
end

-- Funde landen im Lager (games.parts); zusätzlich Schrott nach A8 (zählt nicht für die Bestenliste).
function SideGameRules.Dismantle(p, rng, now)
	local sy = p.games.scrapyard
	if not sy.vehicle then
		return false, nil
	end
	sy.vehicle = false
	local g = p.games
	local found = math.max(2, Rules.Round((2 + rng:NextNumber() * 6) * SideGameRules.ToolBonus(p) * (1 + (g.scrapyardLevel - 1) * 0.12)))
	local rare = rng:NextNumber() < SideGameRules.RareChance(p)
	local parts = found + (rare and Config.ScrapyardRareParts or 0)
	local credits = rng:NextInteger(0, 90)
	local scrap = found * Config.ScrapyardScrapPerPart
	g.parts += parts
	p.credits += credits
	g.press.scrap += scrap
	Rules.AddStat(p, "dismantled", 1, now)
	local xp = Rules.GainXP(p, 8 + found)
	return true, { parts = parts, rare = rare, credits = credits, scrap = scrap, xp = xp }
end

function SideGameRules.SellParts(p)
	local g = p.games
	if g.parts < Config.ScrapyardSellParts then
		return false, "Du brauchst mindestens " .. Config.ScrapyardSellParts .. " Teile."
	end
	g.parts -= Config.ScrapyardSellParts
	p.credits += Config.ScrapyardSellCredits
	local xp = Rules.GainXP(p, 5)
	return true, Config.ScrapyardSellCredits, xp
end

---------------------------------------------------------------- Quiz
-- Die Frage liegt nur auf dem Server; der Client sieht Text und gemischte Antworten.
function SideGameRules.NewQuestion(p, rng, t)
	local qz = p.games.quiz
	if qz.lastAsked > 0 and t - qz.lastAsked < Config.QuizCooldown then
		return false, nil
	end
	local index = rng:NextInteger(1, #Catalog.Questions)
	local order = { 1, 2, 3, 4 }
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	qz.token = (qz.token or 0) + 1
	qz.current = { index = index, order = order, token = qz.token }
	qz.lastAsked = t
	return true, qz.current
end

function SideGameRules.QuestionView(p)
	local cur = p.games.quiz.current
	if not cur then
		return nil
	end
	local q = Catalog.Questions[cur.index]
	local answers = {}
	for i, src in ipairs(cur.order) do
		answers[i] = q.a[src]
	end
	return { text = q.q, answers = answers, token = cur.token }
end

-- choice = angezeigte Position 1..4. Jede Frage kann genau einmal beantwortet werden.
function SideGameRules.Answer(p, token, choice, now)
	local qz = p.games.quiz
	local cur = qz.current
	if not cur or token ~= cur.token then
		return false, nil
	end
	if type(choice) ~= "number" or choice ~= math.floor(choice) or choice < 1 or choice > 4 then
		return false, nil
	end
	qz.current = false
	local correctPos = table.find(cur.order, 1)
	if cur.order[choice] == 1 then
		qz.diagPoints += 1
		p.credits += Config.QuizCorrectCredits
		Rules.AddStat(p, "quizCorrect", 1, now)
		local xp = Rules.GainXP(p, Config.QuizCorrectXp)
		return true, { correct = true, correctPos = correctPos, credits = Config.QuizCorrectCredits, xp = xp }
	end
	local xp = Rules.GainXP(p, Config.QuizWrongXp)
	return true, { correct = false, correctPos = correctPos, credits = 0, xp = xp }
end

---------------------------------------------------------------- Parkplatz-Chaos
-- Raster Size x Size, Zellen 0..Size²-1. Ausfahrt unten rechts.
-- Das Zielauto fährt nach rechts bis zum Rand und dann nach unten zur Ausfahrt.
-- Blockierende Autos wegfahren (antippen), dann das Zielauto antippen.
-- Zielauto bei blockiertem Weg antippen = Blechschaden, die Serie endet.
function SideGameRules.ParkingPath(target)
	local n = Config.ParkingSize
	local r, c = math.floor(target / n), target % n
	local path = {}
	for cc = c + 1, n - 1 do
		table.insert(path, r * n + cc)
	end
	for rr = r + 1, n - 1 do
		table.insert(path, rr * n + (n - 1))
	end
	return path
end

function SideGameRules.ParkingBlocked(puzzle)
	local cars = {}
	for _, c in ipairs(puzzle.cars) do
		cars[c] = true
	end
	for _, cell in ipairs(SideGameRules.ParkingPath(puzzle.target)) do
		if cars[cell] then
			return true
		end
	end
	return false
end

function SideGameRules.NewPuzzle(p, rng)
	local pk = p.games.parking
	local n = Config.ParkingSize
	local exit = n * n - 1
	local old = pk.puzzle
	if old and not old.solved and not old.crashed and old.moves > 0 then
		pk.streak = 0 -- abgebrochene Runde beendet die Serie
	end
	local cars = {}
	local used = { [exit] = true }
	while #cars < Config.ParkingCars do
		local cell = rng:NextInteger(0, exit - 1)
		if not used[cell] then
			used[cell] = true
			table.insert(cars, cell)
		end
	end
	pk.puzzle = { cars = cars, target = cars[1], exit = exit, moves = 0, solved = false, crashed = false }
	return pk.puzzle
end

function SideGameRules.Tap(p, cell, now)
	local pk = p.games.parking
	local pz = pk.puzzle
	if not pz or pz.solved or pz.crashed then
		return false, nil
	end
	if type(cell) ~= "number" or not table.find(pz.cars, cell) then
		return false, nil
	end
	pz.moves += 1
	if cell == pz.target then
		if SideGameRules.ParkingBlocked(pz) then
			pz.crashed = true
			pk.streak = 0
			return true, { crashed = true }
		end
		pz.solved = true
		pk.streak += 1
		if pk.streak > pk.best then
			pk.best = pk.streak
		end
		local reward = Config.ParkingRewardBase + pk.streak * Config.ParkingRewardPerStreak
		p.credits += reward
		p.games.reputation += 1
		Rules.AddStat(p, "parkingSolved", 1, now)
		local xp = Rules.GainXP(p, Config.ParkingXp)
		return true, { solved = true, credits = reward, xp = xp }
	end
	table.remove(pz.cars, table.find(pz.cars, cell))
	return true, { moved = true }
end

return SideGameRules
