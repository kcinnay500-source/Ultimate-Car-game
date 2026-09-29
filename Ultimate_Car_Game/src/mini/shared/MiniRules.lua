-- MiniRules: Minispiel-Daten im 2.4.0-Profil (d = profile.data, Minispiele unter d.games),
-- Normalisierung beim Laden, gemeinsame Helfer (Geld, Ruf, XP, Statistiken, Tageswechsel).
-- Geld ist d.money (2.4.0), gedeckelt auf C.NumberCap; Level/XP laufen über R.GainXP.
local MiniConfig = require(script.Parent:WaitForChild("MiniConfig"))
local MiniCatalog = require(script.Parent:WaitForChild("MiniCatalog"))
local C = require(script.Parent.Parent:WaitForChild("Config"))
-- 3.x: Autos, Teststrecke, Auktion, Spielhalle (keine Ringabhängigkeit: diese Module laden MiniRules erst beim Aufruf)
local CarRules = require(script.Parent:WaitForChild("CarRules"))
local TrackRules = require(script.Parent:WaitForChild("TrackRules"))
local AuctionRules = require(script.Parent:WaitForChild("AuctionRules"))
local ArcadeRules = require(script.Parent:WaitForChild("ArcadeRules"))
-- Ausbaustufe 4: Einstellungen/Tutorial (games.meta) und Prestige (games.prestige); MetaRules braucht nur GameConfig
local MetaRules = require(script.Parent:WaitForChild("MetaRules"))

local MiniRules = {}

MiniRules.GamesVersion = 1
local MAX_SAFE = 2 ^ 53
local HUGE = 1e300 -- Schrott und Lebenszeit-Werte (Bestenliste) dürfen sehr groß werden

-- GarageShared.Rules lädt dieses Modul beim Start; umgekehrt wird Rules erst beim ersten
-- Aufruf geladen (keine Ringabhängigkeit beim require).
local Rules
local function rules()
	if not Rules then
		Rules = require(script.Parent.Parent:WaitForChild("Rules"))
	end
	return Rules
end

---------------------------------------------------------------- Zahlen
function MiniRules.IsFiniteNumber(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Eingaben: endlich -> in [min, max] geklemmt, sonst Standard
function MiniRules.SafeNumber(v, default, min, max)
	if not MiniRules.IsFiniteNumber(v) then
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

function MiniRules.SafeInt(v, default, min, max)
	return math.floor(MiniRules.SafeNumber(v, default, min, max))
end

-- Gespeicherte Werte: NaN/inf/unter dem Minimum -> Standard, über dem Maximum -> Maximum
local function load(v, default, min, max)
	if not MiniRules.IsFiniteNumber(v) or v < min then
		return default
	end
	return math.min(v, max)
end
local function loadInt(v, default, min, max)
	return math.floor(load(v, default, min, max))
end
local function tableOr(v)
	return type(v) == "table" and v or {}
end

function MiniRules.Round(n)
	return math.floor(n + 0.5)
end

function MiniRules.DayKey(now)
	return os.date("!%Y-%m-%d", math.floor(now))
end

function MiniRules.HashString(s)
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

---------------------------------------------------------------- Standardwerte und Laden
MiniRules.STAT_KEYS = {
	"clicks", "pressed", "pressUpgrades", "rebirths", "jobsDone", "quizCorrect", "parkingSolved",
	"dismantled", "tuningStarted", "tuningCollected", "longTuning", "idleCollected",
	"missionsDone", "tycoonRuns", "prestigeClaims", -- Ausbaustufe 4 (PHASE4_CONTRACT §2)
}
local STAT_SET = {}
for _, key in ipairs(MiniRules.STAT_KEYS) do
	STAT_SET[key] = true
end

-- Tiefe höchstens 3 unter games (games.press.upgrades.pu1, games.cars[1].paint, games.arcade.best.arcade_1,
-- games.meta.hintsSeen.h_map, games.prestige.claimed[n]);
-- R.Snapshot erlaubt 12.
function MiniRules.DefaultGames()
	local stats = {}
	for _, key in ipairs(MiniRules.STAT_KEYS) do
		stats[key] = 0
	end
	local g = {
		v = MiniRules.GamesVersion,
		parts = MiniConfig.StartParts,
		tuningLevel = 1,
		scrapyardLevel = 1,
		press = {
			scrap = MiniConfig.PressStartScrap,
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
		scrapyard = { vehicle = false, readyAt = 0 }, -- readyAt: Serverzeit, ab der Zerlegen erlaubt ist
		quiz = { diagPoints = 0 }, -- die offene Frage liegt nur in der Server-Sitzung (nie im Profil)
		parking = { streak = 0, best = 0, puzzle = false },
		stats = stats,
		milestones = {},
		daily = { day = "", claimed = false, active = false, progress = {}, goalsClaimed = {} },
		auction = AuctionRules.Default(),
		track = TrackRules.Default(),
		arcade = ArcadeRules.Default(),
	}
	CarRules.ApplyDefault(g) -- cars = {}, carSerial = 0, activeCar = 0
	MetaRules.ApplyDefault(g) -- meta, prestige (Ausbaustufe 4)
	return g
end

function MiniRules.NormalizePuzzle(pz)
	if type(pz) ~= "table" or type(pz.cars) ~= "table" then
		return false
	end
	local cells = MiniConfig.ParkingSize * MiniConfig.ParkingSize
	local cars, seen = {}, {}
	for _, c in ipairs(pz.cars) do
		if type(c) == "number" and c == math.floor(c) and c >= 0 and c < cells - 1 and not seen[c] and #cars < MiniConfig.ParkingCars then
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
		moves = loadInt(pz.moves, 0, 0, 1000),
		solved = pz.solved == true,
		crashed = pz.crashed == true,
	}
end

-- Normalisiert raw (= gespeichertes d.games) gegen eine Whitelist. Idempotent:
-- LoadGames(LoadGames(x, d), d) == LoadGames(x, d). Unbekannte Felder fallen weg.
-- Fehlt games ganz (neues Profil oder 2.4.0-Veteran), zählen bereits abgerechnete Aufträge (d.completed)
-- als jobsDone für Meilensteine.
function MiniRules.LoadGames(raw, d, now)
	local g = MiniRules.DefaultGames()
	if type(raw) ~= "table" then
		local completed = type(d) == "table" and d.completed or 0
		g.stats.jobsDone = loadInt(completed, 0, 0, MAX_SAFE)
		g.meta = MetaRules.Load(nil, d, now) -- 2.4.0-Veteranen: Tutorial gilt als erledigt
		return g
	end
	g.auction = AuctionRules.Load(raw.auction, d, now)
	g.track = TrackRules.Load(raw.track)
	g.arcade = ArcadeRules.Load(raw.arcade, d, now)
	CarRules.ApplyLoad(g, raw, d, now)
	MetaRules.ApplyLoad(g, raw, d, now)
	g.parts = loadInt(raw.parts, g.parts, 0, MAX_SAFE)
	for _, u in ipairs(MiniConfig.Upgrades) do
		g[u.key] = loadInt(raw[u.key], u.start, u.start, u.max)
	end

	local pr, gp = tableOr(raw.press), g.press
	gp.scrap = load(pr.scrap, gp.scrap, 0, HUGE)
	gp.runScrap = load(pr.runScrap, 0, 0, HUGE)
	gp.lifetime = load(pr.lifetime, 0, 0, HUGE)
	gp.clicks = loadInt(pr.clicks, 0, 0, MAX_SAFE)
	gp.rebirths = loadInt(pr.rebirths, 0, 0, 100000)
	gp.lastTick = load(pr.lastTick, 0, 0, MAX_SAFE)
	gp.combo = load(pr.combo, 1, 1, MiniConfig.PressComboMax)
	gp.comboAt = 0 -- eine Combo überlebt keinen Neustart
	for id, lvl in pairs(tableOr(pr.upgrades)) do
		if type(id) == "string" and MiniCatalog.PressUpgradeById[id] then
			local n = loadInt(lvl, 0, 0, 100000)
			if n > 0 then
				gp.upgrades[id] = n
			end
		end
	end

	local tu, gt = tableOr(raw.tuning), g.tuning
	gt.lastIdle = load(tu.lastIdle, 0, 0, MAX_SAFE)
	gt.completed = loadInt(tu.completed, 0, 0, MAX_SAFE)
	local usedSlots = {}
	for _, pj in ipairs(tableOr(tu.projects)) do
		if type(pj) == "table" and type(pj.id) == "string" and MiniConfig.TuningProjectById[pj.id] then
			local slot = loadInt(pj.slot, 0, 0, MiniConfig.TuningSlotsMax)
			local startedAt = load(pj.startedAt, 0, 0, MAX_SAFE)
			local duration = load(pj.duration, 0, 0, 7 * 86400)
			if slot >= 1 and not usedSlots[slot] and duration > 0 then
				usedSlots[slot] = true
				table.insert(gt.projects, { slot = slot, id = pj.id, startedAt = startedAt, duration = duration })
			end
		end
	end

	g.scrapyard.vehicle = tableOr(raw.scrapyard).vehicle == true
	g.scrapyard.readyAt = g.scrapyard.vehicle and load(tableOr(raw.scrapyard).readyAt, 0, 0, HUGE) or 0
	g.quiz.diagPoints = loadInt(tableOr(raw.quiz).diagPoints, 0, 0, MAX_SAFE)

	local pk, gk = tableOr(raw.parking), g.parking
	gk.streak = loadInt(pk.streak, 0, 0, MAX_SAFE)
	gk.best = math.max(gk.streak, loadInt(pk.best, 0, 0, MAX_SAFE))
	gk.puzzle = MiniRules.NormalizePuzzle(pk.puzzle)

	local st = tableOr(raw.stats)
	for _, key in ipairs(MiniRules.STAT_KEYS) do
		g.stats[key] = load(st[key], 0, 0, HUGE)
	end

	for id, v in pairs(tableOr(raw.milestones)) do
		if type(id) == "string" and MiniConfig.MilestoneById[id] and v == true then
			g.milestones[id] = true
		end
	end

	local dl, gd = tableOr(raw.daily), g.daily
	gd.day = (type(dl.day) == "string" and string.match(dl.day, "^%d%d%d%d%-%d%d%-%d%d$")) and dl.day or ""
	gd.claimed = dl.claimed == true
	gd.active = dl.active == true
	for key, v in pairs(tableOr(dl.progress)) do
		if STAT_SET[key] then
			gd.progress[key] = load(v, 0, 0, HUGE)
		end
	end
	for id, v in pairs(tableOr(dl.goalsClaimed)) do
		if type(id) == "string" and MiniConfig.DailyGoalById[id] and v == true then
			gd.goalsClaimed[id] = true
		end
	end
	return g
end

-- Prüft rekursiv, dass nur speicherbare, endliche Werte im Profil stehen (vor dem Speichern).
function MiniRules.IsClean(v, depth)
	depth = depth or 0
	if depth > 20 then
		return false
	end
	local t = type(v)
	if t == "number" then
		return MiniRules.IsFiniteNumber(v)
	elseif t == "table" then
		for k, x in pairs(v) do
			if not MiniRules.IsClean(k, depth + 1) or not MiniRules.IsClean(x, depth + 1) then
				return false
			end
		end
		return true
	end
	return t == "string" or t == "boolean" or t == "nil"
end

---------------------------------------------------------------- Geld, Ruf, XP
-- Einzige Stelle, an der Minispiele d.money ändern (gedeckelt auf 0 .. C.NumberCap). Rückgabe: tatsächliche Änderung.
function MiniRules.AddMoney(d, amount)
	if not MiniRules.IsFiniteNumber(amount) then
		return 0
	end
	local before = MiniRules.IsFiniteNumber(d.money) and d.money or 0
	d.money = math.min(C.NumberCap, math.max(0, before + amount))
	return d.money - before
end

function MiniRules.AddReputation(d, amount)
	local before = MiniRules.IsFiniteNumber(d.reputation) and d.reputation or 0
	d.reputation = math.min(C.NumberCap, math.max(0, before + amount))
end

-- XP über die 2.4.0-Karriere (R.GainXP: gleiche Kurve, Level-Bonus 120 + 18 × Level Cr und +2 Ruf).
-- Rückgabe wie 3.0: { levels = n, credits = c }
function MiniRules.GainXP(d, amount)
	amount = MiniRules.SafeNumber(amount, 0, 0, 1e15)
	local before = d.money
	local levels = amount > 0 and rules().GainXP(d, amount) or 0
	return { levels = levels, credits = math.max(0, d.money - before) }
end

---------------------------------------------------------------- Tageswechsel und Statistiken
-- Tageswechsel (UTC): setzt Tagesauftrag und Tagesziele zurück. true, wenn ein neuer Tag begann.
function MiniRules.EnsureDay(d, now)
	local today = MiniRules.DayKey(now)
	local dl = d.games.daily
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

-- Zählt eine Statistik hoch und führt den Tages-Fortschritt mit.
-- passive = true (Maschinen): zählt für Ziele, gilt aber nicht als "heute gespielt".
function MiniRules.AddStat(d, key, amount, now, passive)
	local g = d.games
	g.stats[key] = (g.stats[key] or 0) + amount
	if now then
		MiniRules.EnsureDay(d, now)
		local dl = g.daily
		dl.progress[key] = (dl.progress[key] or 0) + amount
		if not passive then
			dl.active = true
		end
	end
end

-- Heute gespielt (z. B. eine Außenarbeit der Werkstatt): schaltet den Tagesauftrag frei.
function MiniRules.MarkActive(d, now)
	MiniRules.EnsureDay(d, now)
	d.games.daily.active = true
end

---------------------------------------------------------------- Minispiel-Ausbau (tuningLevel, scrapyardLevel)
function MiniRules.UpgradeCost(d, u)
	return MiniRules.Round(u.base * u.growth ^ (d.games[u.key] - u.start))
end

-- expectedLevel = die Stufe, die der Client gesehen hat; veraltet -> still verworfen.
function MiniRules.BuyUpgrade(d, key, expectedLevel)
	local u = type(key) == "string" and MiniConfig.UpgradeByKey[key]
	if not u then
		return false, "Unbekannter Ausbau."
	end
	local lvl = d.games[u.key]
	if type(expectedLevel) ~= "number" or expectedLevel ~= lvl then
		return false, nil
	end
	if lvl >= u.max then
		return false, "Maximale Stufe erreicht."
	end
	local cost = MiniRules.UpgradeCost(d, u)
	if d.money < cost then
		return false, "Nicht genug Credits."
	end
	MiniRules.AddMoney(d, -cost)
	d.games[u.key] = lvl + 1
	local xp = MiniRules.GainXP(d, MiniConfig.UpgradeXp)
	return true, u, xp
end

return MiniRules
