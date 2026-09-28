-- SideGameRules: Schrottplatz, Mechaniker-Quiz, Parkplatz-Chaos (HTML: buyScrap, sellParts, answerQuestion,
-- startParking, tapSpot). d = 2.4.0-Profildaten, Geld = d.money über MiniRules.AddMoney.
--
-- Schrottplatz-Funde (Entscheidung):
-- * Gewöhnliche Funde bleiben Altteile (d.games.parts) und sind nur beim Schrotthändler verkäuflich
--   (5 Stück -> 220 Cr). Sie in 2.4.0-Lagerteile (d.inventory) umzuwandeln wäre wirtschaftlich
--   falsch: 2.4.0 kennt keinen Teileverkauf, und Lagerteile sind nach Marke, Familie und Level
--   bepreist (18 bis 2016 Cr). Würde der Verkauf Lagerteile annehmen, ergäbe sich eine Geldquelle
--   (Nexra-Ölfilter für 18 Cr kaufen, als Altteil für 44 Cr verkaufen).
-- * Ein seltener Fund ist dagegen ein echtes gebrauchtes Ersatzteil (Marke Nexra, Qualität 0) für
--   d.inventory: Teiletyp und Fahrzeugfamilie sind für das eigene Level freigeschaltet, das Teil ist
--   also in der Werkstatt verwendbar, aber nicht verkäuflich. Passt noch kein Teil, gibt es wie in
--   3.0 zusätzliche Altteile (ScrapyardRareParts).
-- * Der Tagesauftrag gibt weiter Altteile (DailyParts).
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))
local MiniCatalog = require(script.Parent:WaitForChild("MiniCatalog"))
local MiniRules = require(script.Parent:WaitForChild("MiniRules"))
local C = require(script.Parent.Parent:WaitForChild("Config"))

local SideGameRules = {}

local function find(list, value)
	for i, v in ipairs(list) do
		if v == value then
			return i
		end
	end
	return nil
end

---------------------------------------------------------------- Schrottplatz
-- 2.4.0-Werkzeugqualität (d.toolLevel) bringt mehr Funde (HTML scrapBonus)
function SideGameRules.ToolBonus(d)
	local lvl = MiniRules.SafeNumber(d.toolLevel, 1, 1, 1e6)
	return 1 + (lvl - 1) * 0.14
end

function SideGameRules.RareChance(d)
	return math.min(1, 0.08 + d.games.scrapyardLevel * 0.025)
end

function SideGameRules.BuyVehicle(d)
	local sy = d.games.scrapyard
	if sy.vehicle then
		return false, "Es steht schon ein Fahrzeug zum Zerlegen bereit."
	end
	if d.money < MiniConfig.ScrapyardCarCost then
		return false, "Nicht genug Credits."
	end
	MiniRules.AddMoney(d, -MiniConfig.ScrapyardCarCost)
	sy.vehicle = true
	return true
end

-- Ein gebrauchtes Ersatzteil, das zum Level passt (siehe Kopfkommentar). nil, wenn keines passt.
function SideGameRules.RarePart(d, rng)
	local level = MiniRules.SafeNumber(d.level, 1, 1, 1e6)
	local kinds = {}
	for _, kind in ipairs(C.PartTypes) do
		if kind.level <= level then
			table.insert(kinds, kind)
		end
	end
	local hasFamily = {}
	for _, car in ipairs(C.Cars) do
		if car.level <= level then
			hasFamily[car.family] = true
		end
	end
	local families = {}
	for _, family in ipairs({ "C", "L", "P" }) do
		if hasFamily[family] then
			table.insert(families, family)
		end
	end
	if #kinds == 0 or #families == 0 then
		return nil
	end
	local kind = kinds[rng:NextInteger(1, #kinds)]
	local family = families[rng:NextInteger(1, #families)]
	local sku = MiniConfig.ScrapyardRareBrand .. "_" .. family .. "_" .. kind.id
	return C.PartById[sku] and sku or nil
end

-- Funde: Altteile (games.parts) und Schrott (zählt nicht für die Bestenliste); seltene Funde siehe oben.
function SideGameRules.Dismantle(d, rng, now)
	local sy = d.games.scrapyard
	if not sy.vehicle then
		return false, nil
	end
	sy.vehicle = false
	local g = d.games
	local found = math.max(2, MiniRules.Round((2 + rng:NextNumber() * 6) * SideGameRules.ToolBonus(d) * (1 + (g.scrapyardLevel - 1) * 0.12)))
	local rare = rng:NextNumber() < SideGameRules.RareChance(d)
	local parts = found
	local rareSku, rareName
	if rare then
		rareSku = SideGameRules.RarePart(d, rng)
		if rareSku then
			d.inventory[rareSku] = math.min(1000000, (d.inventory[rareSku] or 0) + 1)
			local part = C.PartById[rareSku]
			rareName = part.brand .. " " .. part.name .. " (" .. (C.Families[part.family] or part.family) .. ")"
		else
			parts += MiniConfig.ScrapyardRareParts
		end
	end
	local scrap = found * MiniConfig.ScrapyardScrapPerPart
	g.parts = math.min(2 ^ 53, g.parts + parts)
	local credits = MiniRules.AddMoney(d, rng:NextInteger(0, 90))
	g.press.scrap += scrap
	MiniRules.AddStat(d, "dismantled", 1, now)
	local xp = MiniRules.GainXP(d, 8 + found)
	return true, { parts = parts, rare = rare, rareSku = rareSku, rarePart = rareName, credits = credits, scrap = scrap, xp = xp }
end

function SideGameRules.SellParts(d)
	local g = d.games
	if g.parts < MiniConfig.ScrapyardSellParts then
		return false, "Du brauchst mindestens " .. MiniConfig.ScrapyardSellParts .. " Altteile."
	end
	g.parts -= MiniConfig.ScrapyardSellParts
	local credits = MiniRules.AddMoney(d, MiniConfig.ScrapyardSellCredits)
	local xp = MiniRules.GainXP(d, 5)
	return true, credits, xp
end

---------------------------------------------------------------- Quiz
-- qs = Quiz-Zustand der Server-Sitzung { current, token, lastAsked }. Die offene Frage (mit der
-- richtigen Reihenfolge) liegt nie im Profil, weil 2.4.0 das Profil an den Client spiegelt.
function SideGameRules.NewQuizState()
	return { current = false, token = 0, lastAsked = 0 }
end

function SideGameRules.NewQuestion(qs, rng, t)
	if qs.lastAsked > 0 and t - qs.lastAsked < MiniConfig.QuizCooldown then
		return false, nil
	end
	local index = rng:NextInteger(1, #MiniCatalog.Questions)
	local order = { 1, 2, 3, 4 }
	for i = #order, 2, -1 do
		local j = rng:NextInteger(1, i)
		order[i], order[j] = order[j], order[i]
	end
	qs.token += 1
	qs.current = { index = index, order = order, token = qs.token }
	qs.lastAsked = t
	return true, qs.current
end

function SideGameRules.QuestionView(qs)
	local cur = qs and qs.current
	if not cur then
		return nil
	end
	local q = MiniCatalog.Questions[cur.index]
	local answers = {}
	for i, src in ipairs(cur.order) do
		answers[i] = q.a[src]
	end
	return { text = q.q, answers = answers, token = cur.token }
end

-- choice = angezeigte Position 1..4. Jede Frage kann genau einmal beantwortet werden.
function SideGameRules.Answer(d, qs, token, choice, now)
	local cur = qs.current
	if not cur or token ~= cur.token then
		return false, nil
	end
	if type(choice) ~= "number" or choice ~= math.floor(choice) or choice < 1 or choice > 4 then
		return false, nil
	end
	qs.current = false
	local correctPos = find(cur.order, 1)
	if cur.order[choice] == 1 then
		d.games.quiz.diagPoints += 1
		local credits = MiniRules.AddMoney(d, MiniConfig.QuizCorrectCredits)
		MiniRules.AddStat(d, "quizCorrect", 1, now)
		local xp = MiniRules.GainXP(d, MiniConfig.QuizCorrectXp)
		return true, { correct = true, correctPos = correctPos, credits = credits, xp = xp }
	end
	MiniRules.MarkActive(d, now)
	local xp = MiniRules.GainXP(d, MiniConfig.QuizWrongXp)
	return true, { correct = false, correctPos = correctPos, credits = 0, xp = xp }
end

---------------------------------------------------------------- Parkplatz-Chaos
-- Raster Size x Size, Zellen 0..Size²-1. Ausfahrt unten rechts.
-- Das Zielauto fährt nach rechts bis zum Rand und dann nach unten zur Ausfahrt.
-- Blockierende Autos wegfahren (antippen), dann das Zielauto antippen.
-- Zielauto bei blockiertem Weg antippen = Blechschaden, die Serie endet.
function SideGameRules.ParkingPath(target)
	local n = MiniConfig.ParkingSize
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

function SideGameRules.NewPuzzle(d, rng)
	local pk = d.games.parking
	local n = MiniConfig.ParkingSize
	local exit = n * n - 1
	local old = pk.puzzle
	if old and not old.solved and not old.crashed and old.moves > 0 then
		pk.streak = 0 -- abgebrochene Runde beendet die Serie
	end
	local cars = {}
	local used = { [exit] = true }
	while #cars < MiniConfig.ParkingCars do
		local cell = rng:NextInteger(0, exit - 1)
		if not used[cell] then
			used[cell] = true
			table.insert(cars, cell)
		end
	end
	pk.puzzle = { cars = cars, target = cars[1], exit = exit, moves = 0, solved = false, crashed = false }
	return pk.puzzle
end

function SideGameRules.Tap(d, cell, now)
	local pk = d.games.parking
	local pz = pk.puzzle
	if not pz or pz.solved or pz.crashed then
		return false, nil
	end
	if type(cell) ~= "number" or not find(pz.cars, cell) then
		return false, nil
	end
	pz.moves += 1
	if cell == pz.target then
		if SideGameRules.ParkingBlocked(pz) then
			pz.crashed = true
			pk.streak = 0
			MiniRules.MarkActive(d, now)
			return true, { crashed = true }
		end
		pz.solved = true
		pk.streak += 1
		if pk.streak > pk.best then
			pk.best = pk.streak
		end
		local reward = MiniRules.AddMoney(d, MiniConfig.ParkingRewardBase + pk.streak * MiniConfig.ParkingRewardPerStreak)
		MiniRules.AddReputation(d, 1)
		MiniRules.AddStat(d, "parkingSolved", 1, now)
		local xp = MiniRules.GainXP(d, MiniConfig.ParkingXp)
		return true, { solved = true, credits = reward, xp = xp }
	end
	table.remove(pz.cars, find(pz.cars, cell))
	return true, { moved = true }
end

return SideGameRules
