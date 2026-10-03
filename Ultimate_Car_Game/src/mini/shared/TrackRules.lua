-- TrackRules: Zeitfahren auf der Teststrecke als reine Funktionen (Serverzeit, keine Instanzen).
-- Ablauf: NewRun (Startampel) -> Touch je Checkpoint in Reihenfolge -> "finish" -> Complete (Bestzeit, Belohnung).
-- Plausibilität: jeder Abschnitt braucht mindestens Luftlinie / Höchsttempo (gegen Teleport), die ganze
-- Runde mindestens max(Track.minLapSeconds, Streckenlänge / Höchsttempo). Höchsttempo = das des GEFAHRENEN Autos
-- (CarSpeed: Spitze × Nitro × speedMargin), nicht das schnellste Auto des Katalogs. Belohnung nur für eine verbesserte Bestzeit, gedeckelt.
-- Daten: d.games.track = { best = <Sekunden oder 0>, rewardedBest = <Sekunden oder 0>, runs = <int>, layout = <int> }
-- layout = Version der Streckenführung (TrackRules.Layout.version). Zeiten einer anderen Streckenführung verfallen beim
-- Laden (3.0: Grand-Prix-Kurs statt Oval); die Anzahl der Läufe bleibt.
local CarCatalog = require(script.Parent:WaitForChild("CarCatalog"))

local TrackRules = {}

-- Streckenführung (tools/worldgen/vehicles.py TRACK_LAYOUT / track_length; City.Track hat die Attribute Layout und
-- Length). legacyMin: Zeiten aus Profilen ohne layout-Feld darunter stammen sicher vom alten, kurzen Oval
-- (~780 Studs, 8–16 s) und verfallen; längere Zeiten sind auf dem neuen Kurs ohnehin schlagbar und bleiben.
TrackRules.Layout = {
	version = 2,
	name = "Grand-Prix-Kurs",
	length = 1223, -- Studs (Mittellinie)
	checkpoints = 12, -- Zwischenpunkte, dazu das Ziel
	legacyMin = 20,
	sections = { "Start/Ziel-Gerade", "Kurve 1", "S-Kurve", "schnelle Kurve", "lange Gerade", "Haarnadel", "Zielkurve" },
}

local MAX_SAFE = 2 ^ 53
local MAX_TIME = 24 * 3600

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function cfg()
	return CarCatalog.Track
end

---------------------------------------------------------------- Daten
function TrackRules.Default()
	return { best = 0, rewardedBest = 0, runs = 0, layout = TrackRules.Layout.version }
end

-- raw = gespeichertes d.games.track (oder nil). Idempotent; NaN/negativ/unsinnig -> Standard.
function TrackRules.Load(raw)
	local t = TrackRules.Default()
	if type(raw) ~= "table" then
		return t
	end
	local function time(v)
		if not finite(v) or v <= 0 or v > MAX_TIME then
			return 0
		end
		return v
	end
	t.best = time(raw.best)
	t.rewardedBest = time(raw.rewardedBest)
	if t.rewardedBest > 0 and (t.best == 0 or t.best > t.rewardedBest) then
		t.best = t.rewardedBest -- die belohnte Zeit war eine gefahrene Zeit
	end
	if finite(raw.runs) and raw.runs >= 0 then
		t.runs = math.floor(math.min(raw.runs, MAX_SAFE))
	end
	-- Zeiten einer anderen Streckenführung verfallen (Bestzeit vom alten Oval wäre auf dem Grand-Prix-Kurs unschlagbar)
	local L = TrackRules.Layout
	local stale
	if raw.layout == nil then
		stale = (t.best > 0 and t.best < L.legacyMin) or (t.rewardedBest > 0 and t.rewardedBest < L.legacyMin)
	else
		stale = raw.layout ~= L.version
	end
	if stale then
		t.best, t.rewardedBest = 0, 0
	end
	return t
end

---------------------------------------------------------------- Plausibilität
-- Höchstes glaubwürdiges Tempo in Studs/s: schnellstes Modell, volle Tuning-Stufen, stärkstes Nitro, Reserve.
function TrackRules.MaxSpeed()
	local e = CarCatalog.Effects
	local top = 0
	for _, m in ipairs(CarCatalog.Models) do
		top = math.max(top, m.top)
	end
	local tuned = top * (1 + e.engineTop * CarCatalog.Tune.engine.max + e.gearboxTop * CarCatalog.Tune.gearbox.max)
	local boost = 1
	for _, n in ipairs(CarCatalog.Nitro) do
		boost = math.max(boost, n.boost)
	end
	return tuned * boost / CarCatalog.KmhPerStud * cfg().speedMargin
end

-- Höchstes glaubwürdiges Tempo eines bestimmten Autos (stats = CarRules.Stats(car)) in Studs/s
function TrackRules.CarSpeed(stats)
	if type(stats) ~= "table" or not finite(stats.topSpeedStuds) or stats.topSpeedStuds <= 0 then
		return TrackRules.MaxSpeed()
	end
	local boost = type(stats.nitro) == "table" and finite(stats.nitro.boost) and math.max(1, stats.nitro.boost) or 1
	return stats.topSpeedStuds * boost * cfg().speedMargin
end

local function pos(p)
	if type(p) == "table" then
		return p.X or p.x or p[1] or 0, p.Y or p.y or p[2] or 0, p.Z or p.z or p[3] or 0
	end
	return p.X, p.Y, p.Z -- Vector3
end

local function dist(a, b)
	local ax, ay, az = pos(a)
	local bx, by, bz = pos(b)
	return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2 + (az - bz) ^ 2)
end

-- Mindestzeiten je Abschnitt: start = Startposition, points = Positionen der Checkpoints in Reihenfolge
-- (der letzte ist das Ziel). Rückgabe: Liste gleicher Länge wie points.
function TrackRules.MinTimes(start, points, maxSpeed)
	maxSpeed = maxSpeed or TrackRules.MaxSpeed()
	local out = {}
	local prev = start
	for i, p in ipairs(points) do
		local d = prev and dist(prev, p) or 0
		out[i] = math.max(cfg().segmentFloor, d / maxSpeed)
		prev = p
	end
	return out
end

-- Mindestzeit der ganzen Runde: Luftlinien-Summe über alle Checkpoints / Höchsttempo, mindestens minLapSeconds
function TrackRules.MinLap(start, points, maxSpeed)
	maxSpeed = maxSpeed or TrackRules.MaxSpeed()
	local total, prev = 0, start
	for _, p in ipairs(points) do
		total += prev and dist(prev, p) or 0
		prev = p
	end
	return math.max(cfg().minLapSeconds, total / maxSpeed)
end

---------------------------------------------------------------- Lauf
-- Neuer Lauf: Zeit läuft ab startAt = now + Countdown. minTimes aus MinTimes (Länge = Anzahl Checkpoints).
-- minLap = Mindestzeit der ganzen Runde (MinLap), maxSpeed = zugrunde gelegtes Höchsttempo (für Rescale).
function TrackRules.NewRun(minTimes, now, countdown, minLap, maxSpeed)
	countdown = countdown or cfg().countdown
	local startAt = now + countdown
	return {
		minLap = finite(minLap) and minLap or cfg().minLapSeconds,
		maxSpeed = maxSpeed,
		startAt = startAt,
		lastAt = startAt,
		next = 1,
		total = #minTimes,
		minTimes = minTimes,
		splits = {},
		expiresAt = startAt + cfg().maxRunSeconds,
	}
end

-- Tuning während des Laufs: das Auto ist schneller geworden -> offene Abschnitte und Rundenzeit passend kürzen
-- (nie verlängern). Rückgabe: true, wenn angepasst
function TrackRules.Rescale(run, maxSpeed)
	if type(run) ~= "table" or not finite(maxSpeed) or not finite(run.maxSpeed) or maxSpeed <= run.maxSpeed then
		return false
	end
	local f = run.maxSpeed / maxSpeed
	for i = run.next, run.total do
		run.minTimes[i] = math.max(cfg().segmentFloor, (run.minTimes[i] or 0) * f)
	end
	run.minLap = math.max(cfg().minLapSeconds, run.minLap * f)
	run.maxSpeed = maxSpeed
	return true
end

function TrackRules.Elapsed(run, now)
	return math.max(0, now - run.startAt)
end

function TrackRules.Expired(run, now)
	return now > run.expiresAt
end

-- Berührung des Checkpoints `index` (1..total) zur Serverzeit now.
-- Rückgabe: result, info
--   "ignored"    schon passiert oder (noch) nicht der nächste (z. B. Ziellinie beim Losfahren)
--   "early"      Frühstart: erster Checkpoint vor dem Startsignal -> Lauf ungültig
--   "tooFast"    Abschnitt schneller als physikalisch möglich -> Lauf ungültig
--   "checkpoint" info = { index, total, time, split }
--   "finish"     info = { index, total, time, split }
function TrackRules.Touch(run, index, now)
	if type(run) ~= "table" or run.done or type(index) ~= "number" then
		return "ignored"
	end
	if index ~= run.next then
		return "ignored"
	end
	if now < run.startAt then
		run.done = true
		return "early"
	end
	local split = now - run.lastAt
	if split + 1e-6 < (run.minTimes[index] or 0) then
		run.done = true
		return "tooFast", { index = index, split = split, min = run.minTimes[index] }
	end
	local time = now - run.startAt
	run.splits[index] = time
	run.lastAt = now
	run.next = index + 1
	local info = { index = index, total = run.total, time = time, split = split }
	if index >= run.total then
		run.done = true
		if time + 1e-6 < (run.minLap or cfg().minLapSeconds) then
			return "tooFast", info
		end
		return "finish", info
	end
	return "checkpoint", info
end

---------------------------------------------------------------- Belohnung
-- Belohnung für eine gültige Zeit (ohne Seiteneffekte). Rückgabe: credits, newRewardedBest
function TrackRules.Reward(track, time, level)
	local c = cfg()
	if not finite(time) or time <= 0 then
		return 0, track.rewardedBest
	end
	local bonus = 1 + c.levelBonus * math.max(0, (finite(level) and level or 1) - 1)
	if track.rewardedBest <= 0 then
		return math.floor(c.firstReward * bonus + 0.5), time
	end
	if time > track.rewardedBest - c.minImprovement then
		return 0, track.rewardedBest
	end
	local ref = math.min(track.rewardedBest, c.baselineSeconds)
	local gain = math.max(0, ref - time)
	local credits = math.min(c.maxReward, c.perSecond * gain) * bonus
	return math.floor(credits + 0.5), time
end

-- Wertet eine beendete Runde aus und schreibt d.games.track fort (runs, best, rewardedBest).
-- Rückgabe: { time, best, newBest, reward, xp, rewardedBest }
function TrackRules.Complete(track, time, level)
	local c = cfg()
	track.runs = math.min(MAX_SAFE, (track.runs or 0) + 1)
	local newBest = track.best <= 0 or time < track.best
	if newBest then
		track.best = time
	end
	local reward, rewarded = TrackRules.Reward(track, time, level)
	local improvedReward = rewarded ~= track.rewardedBest
	track.rewardedBest = rewarded
	return {
		time = time,
		best = track.best,
		newBest = newBest,
		reward = reward,
		xp = (newBest and improvedReward) and c.xp or 0,
		rewardedBest = track.rewardedBest,
	}
end

return TrackRules
