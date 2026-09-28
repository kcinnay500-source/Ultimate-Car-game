-- Rules: Profil-Normalisierung (Migration), Karriere (Level/XP), Hilfsfunktionen.
-- Rein und ohne Roblox-Dienste, damit alles im Mock testbar ist.
local Config = require(script.Parent:WaitForChild("Config"))

local Rules = {}

Rules.SCHEMA = 3
local MAX_SAFE = 2 ^ 53

-- Liefert eine endliche Zahl im Bereich [min, max], sonst den Standardwert.
function Rules.SafeNumber(v, default, min, max)
	if type(v) ~= "number" or v ~= v or v == math.huge or v == -math.huge then
		return default
	end
	if min ~= nil and v < min then
		return min
	end
	if max ~= nil and v > max then
		return max
	end
	return v
end

function Rules.SafeInt(v, default, min, max)
	local n = Rules.SafeNumber(v, default, min, max)
	return math.floor(n)
end

function Rules.IsFiniteNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

function Rules.DayKey(now)
	return os.date("!%Y-%m-%d", now)
end

-- Standardwerte aller Felder, die Version 3.0 benötigt.
function Rules.DefaultGames()
	return {
		parts = Config.StartParts,
		reputation = 0,
		bays = 1,
		offerSlots = 3,
		toolLevel = 1,
		tuningLevel = 1,
		scrapyardLevel = 1,
		jobs = {},
		offers = {},
		nextId = 1,
		press = {
			scrap = Config.PressStartScrap,
			runScrap = 0,
			lifetime = 0,
			clicks = 0,
			upgrades = {},
			rebirths = 0,
			lastTick = 0,
			combo = 1,
			comboAt = 0,
		},
		tuning = { projects = {}, lastIdle = 0, completed = 0 },
		scrapyard = { vehicle = false },
		quiz = { diagPoints = 0, current = false, lastAsked = 0 },
		parking = { streak = 0, best = 0, puzzle = false },
		stats = {},
		milestones = {},
		daily = { day = "", claimed = false, active = false, progress = {}, goalsClaimed = {} },
	}
end

Rules.STAT_KEYS = {
	"clicks", "pressed", "pressUpgrades", "rebirths", "jobsDone", "quizCorrect", "parkingSolved",
	"dismantled", "tuningStarted", "tuningCollected", "longTuning", "idleCollected",
}

function Rules.DefaultProfile()
	return {
		schema = Rules.SCHEMA,
		credits = Config.StartCredits,
		level = 1,
		xp = 0,
		games = Rules.DefaultGames(),
	}
end

local function tableOr(v)
	if type(v) == "table" then
		return v
	end
	return {}
end

local function normalizeJob(j)
	if type(j) ~= "table" then
		return nil
	end
	if type(j.id) ~= "number" or type(j.name) ~= "string" then
		return nil
	end
	return {
		id = Rules.SafeInt(j.id, 0, 0, MAX_SAFE),
		name = j.name,
		reward = Rules.SafeInt(j.reward, 0, 0, MAX_SAFE),
		xp = Rules.SafeInt(j.xp, 0, 0, MAX_SAFE),
		parts = Rules.SafeInt(j.parts, 0, 0, 10000),
		cost = Rules.SafeInt(j.cost, 0, 0, MAX_SAFE),
		time = Rules.SafeNumber(j.time, 1, 1, 86400),
		startedAt = Rules.SafeNumber(j.startedAt, 0, 0, MAX_SAFE),
		endsAt = Rules.SafeNumber(j.endsAt, 0, 0, MAX_SAFE),
	}
end

function Rules.NormalizePuzzle(pz)
	if type(pz) ~= "table" or type(pz.cars) ~= "table" then
		return false
	end
	local cells = Config.ParkingSize * Config.ParkingSize
	local cars, seen = {}, {}
	for _, c in ipairs(pz.cars) do
		if type(c) == "number" and c == math.floor(c) and c >= 0 and c < cells - 1 and not seen[c] then
			seen[c] = true
			table.insert(cars, c)
		end
	end
	if type(pz.target) ~= "number" or not seen[pz.target] then
		return false
	end
	return {
		cars = cars,
		target = pz.target,
		exit = cells - 1,
		moves = Rules.SafeInt(pz.moves, 0, 0, 1000),
		solved = pz.solved == true,
		crashed = pz.crashed == true,
	}
end

-- Normalisiert ein geladenes Profil. Unbekannte Felder (z. B. aus 2.4.0) bleiben unverändert erhalten.
-- Idempotent: LoadData(LoadData(x)) == LoadData(x).
function Rules.LoadData(raw)
	local p = type(raw) == "table" and raw or {}
	local d = Rules.DefaultGames()

	p.schema = Rules.SCHEMA
	p.credits = Rules.SafeNumber(p.credits, Config.StartCredits, 0, MAX_SAFE)
	p.level = Rules.SafeInt(p.level, 1, 1, 1000000)
	p.xp = Rules.SafeNumber(p.xp, 0, 0, MAX_SAFE)

	local g = tableOr(p.games)
	p.games = g
	g.parts = Rules.SafeInt(g.parts, d.parts, 0, MAX_SAFE)
	g.reputation = Rules.SafeInt(g.reputation, 0, 0, MAX_SAFE)
	for _, u in ipairs(Config.Upgrades) do
		local start = u.key == "offerSlots" and 3 or 1
		g[u.key] = Rules.SafeInt(g[u.key], start, start, u.max)
	end
	g.nextId = Rules.SafeInt(g.nextId, 1, 1, MAX_SAFE)

	local jobs = {}
	for _, j in ipairs(tableOr(g.jobs)) do
		local nj = normalizeJob(j)
		if nj and #jobs < g.bays then
			table.insert(jobs, nj)
			if nj.id >= g.nextId then
				g.nextId = nj.id + 1
			end
		end
	end
	g.jobs = jobs
	local offers = {}
	for _, j in ipairs(tableOr(g.offers)) do
		local nj = normalizeJob(j)
		if nj and #offers < Config.MaxOffers then
			table.insert(offers, nj)
			if nj.id >= g.nextId then
				g.nextId = nj.id + 1
			end
		end
	end
	g.offers = offers

	local pr = tableOr(g.press)
	g.press = pr
	pr.scrap = Rules.SafeNumber(pr.scrap, d.press.scrap, 0, 1e300)
	pr.runScrap = Rules.SafeNumber(pr.runScrap, 0, 0, 1e300)
	pr.lifetime = Rules.SafeNumber(pr.lifetime, 0, 0, 1e300)
	pr.clicks = Rules.SafeInt(pr.clicks, 0, 0, MAX_SAFE)
	pr.rebirths = Rules.SafeInt(pr.rebirths, 0, 0, 100000)
	pr.lastTick = Rules.SafeNumber(pr.lastTick, 0, 0, MAX_SAFE)
	pr.combo = Rules.SafeNumber(pr.combo, 1, 1, Config.PressComboMax)
	pr.comboAt = 0 -- Combo überlebt keinen Neustart
	local ups = {}
	for id, lvl in pairs(tableOr(pr.upgrades)) do
		if type(id) == "string" and string.match(id, "^pu%d+$") then
			local n = Rules.SafeInt(lvl, 0, 0, 100000)
			if n > 0 then
				ups[id] = n
			end
		end
	end
	pr.upgrades = ups

	local tu = tableOr(g.tuning)
	g.tuning = tu
	tu.lastIdle = Rules.SafeNumber(tu.lastIdle, 0, 0, MAX_SAFE)
	tu.completed = Rules.SafeInt(tu.completed, 0, 0, MAX_SAFE)
	local projects = {}
	local usedSlots = {}
	for _, pj in ipairs(tableOr(tu.projects)) do
		if type(pj) == "table" and type(pj.id) == "string" then
			local slot = Rules.SafeInt(pj.slot, 0, 0, Config.TuningSlotsMax)
			local startedAt = Rules.SafeNumber(pj.startedAt, 0, 0, MAX_SAFE)
			local duration = Rules.SafeNumber(pj.duration, 0, 0, 7 * 86400)
			if slot >= 1 and not usedSlots[slot] and duration > 0 then
				usedSlots[slot] = true
				table.insert(projects, { slot = slot, id = pj.id, startedAt = startedAt, duration = duration })
			end
		end
	end
	tu.projects = projects

	local sy = tableOr(g.scrapyard)
	g.scrapyard = sy
	sy.vehicle = sy.vehicle == true

	local qz = tableOr(g.quiz)
	g.quiz = qz
	qz.diagPoints = Rules.SafeInt(qz.diagPoints, 0, 0, MAX_SAFE)
	qz.current = false -- offene Fragen werden nicht über Sitzungen gespeichert
	qz.lastAsked = 0

	local pk = tableOr(g.parking)
	g.parking = pk
	pk.streak = Rules.SafeInt(pk.streak, 0, 0, MAX_SAFE)
	pk.best = Rules.SafeInt(pk.best, 0, 0, MAX_SAFE)
	if pk.best < pk.streak then
		pk.best = pk.streak
	end
	pk.puzzle = Rules.NormalizePuzzle(pk.puzzle)

	local st = tableOr(g.stats)
	g.stats = st
	for _, key in ipairs(Rules.STAT_KEYS) do
		st[key] = Rules.SafeNumber(st[key], 0, 0, 1e300)
	end

	local ms = {}
	for id, v in pairs(tableOr(g.milestones)) do
		if type(id) == "string" and v == true then
			ms[id] = true
		end
	end
	g.milestones = ms

	local dl = tableOr(g.daily)
	g.daily = dl
	dl.day = type(dl.day) == "string" and dl.day or ""
	dl.claimed = dl.claimed == true
	dl.active = dl.active == true
	local progress = {}
	for k, v in pairs(tableOr(dl.progress)) do
		if type(k) == "string" then
			progress[k] = Rules.SafeNumber(v, 0, 0, 1e300)
		end
	end
	dl.progress = progress
	local claimed = {}
	for k, v in pairs(tableOr(dl.goalsClaimed)) do
		if type(k) == "string" and v == true then
			claimed[k] = true
		end
	end
	dl.goalsClaimed = claimed

	return p
end

-- Prüft rekursiv, dass keine NaN/inf-Werte im Profil stehen (vor dem Speichern).
function Rules.IsClean(v, depth)
	depth = depth or 0
	if depth > 20 then
		return false
	end
	local t = type(v)
	if t == "number" then
		return Rules.IsFiniteNumber(v)
	elseif t == "table" then
		for k, x in pairs(v) do
			if not Rules.IsClean(k, depth + 1) or not Rules.IsClean(x, depth + 1) then
				return false
			end
		end
	end
	return true
end

-- Karriere (HTML: xpNeeded, gainXP)
function Rules.XpNeeded(level)
	return math.floor(80 + level * 22 + level ^ 1.16 * 4)
end

-- Gibt { levels = n, credits = c } zurück.
function Rules.GainXP(p, amount)
	amount = Rules.SafeNumber(amount, 0, 0, MAX_SAFE)
	p.xp += amount
	local levels, credits = 0, 0
	while p.xp >= Rules.XpNeeded(p.level) and levels < 10000 do
		p.xp -= Rules.XpNeeded(p.level)
		p.level += 1
		levels += 1
		local bonus = math.floor(Config.LevelUpCreditsBase + p.level * Config.LevelUpCreditsPerLevel + 0.5)
		p.credits += bonus
		credits += bonus
		p.games.reputation += Config.LevelUpReputation
	end
	return { levels = levels, credits = credits }
end

-- Zählt eine Statistik hoch und führt den Tages-Fortschritt mit.
-- passive = true (z. B. Maschinen): zählt für Ziele, gilt aber nicht als "heute gespielt".
function Rules.AddStat(p, key, amount, now, passive)
	local st = p.games.stats
	st[key] = (st[key] or 0) + amount
	local dl = p.games.daily
	if now and dl.day == Rules.DayKey(now) then
		dl.progress[key] = (dl.progress[key] or 0) + amount
		if not passive then
			dl.active = true
		end
	end
end

-- Pseudo-Zufall mit Roblox-Random-Schnittstelle, deterministisch pro Seed.
function Rules.HashString(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

function Rules.Round(n)
	return math.floor(n + 0.5)
end

return Rules
