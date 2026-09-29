-- ArcadeRules: die Spielhalle (8 Automaten) als reine Funktionen, auf Server und Client nutzbar
-- (ReplicatedStorage.GarageShared.Mini.ArcadeRules). Keine Instanzen, keine Zufallszahlen außer dem Seed-Generator.
--
-- Ablauf einer Runde (serverautoritativ, PHASE2_CONTRACT §4/§6):
--   NewRound(key, seed, now, token)  Server: Parameter aus dem Seed, Start nach Countdown (startAt = now + 3)
--   View(round)                      öffentliche Parameter für den Client (mini_notice "arcade_round"), ohne Geheimnisse
--                                    (BLITZ-REAKTION: ohne die Zeitpunkte, an denen die Lampen ausgehen; die kommen erst
--                                    im Moment selbst als mini_notice "arcade_go", siehe GoEvents/GoView)
--   Input(round, at, value, now)     eine Eingabe: at = GetServerTimeNow() des Clients, nur gültig in
--                                    [now − 0,5; now + 0,06] (wie das 2.4.0-Mess-QTE), streng in Zeitreihenfolge.
--                                    Zurückdatieren ist begrenzt: gewertet wird höchstens
--                                    now − Latenz − LatencySlack (Latenz = Einweg-Schätzung, höchstens LatencyCap).
--                                    Bewertet wird ausschließlich auf der Zeitachse des Servers (startAt aus dem Seed).
--   Finish(round, now)               Punkte 0..1000 aus den angenommenen Eingaben; danach ist die Runde geschlossen.
--   Reward(key, score)               Credits hängen nur von den Punkten ab (kein Einsatz, kein Zufall).
--   Payout(a, key, score, now)       Tageslimit (UTC-Tag) und Rekord je Automat in d.games.arcade.
-- Daten: d.games.arcade = { day = "YYYY-MM-DD", earned = <Cr heute>, best = { [key] = <Punkte> } }
local ArcadeRules = {}

local MAX_SAFE = 2 ^ 53
local MOD = 2147483647

---------------------------------------------------------------- Grundwerte (Balance-Stellschrauben)
ArcadeRules.Countdown = 3 -- Sekunden von der Startbestätigung bis zum Spielbeginn
ArcadeRules.PastTolerance = 0.5 -- Eingabe darf höchstens so alt sein (Serverzeit bei Ankunft − at)
ArcadeRules.FutureTolerance = 0.06 -- … und höchstens so weit in der Zukunft liegen
-- Rückdatierung: at wird auf mindestens (Ankunft − Latenz − LatencySlack) angehoben. Latenz = halbe Round-Trip-Zeit
-- (Player:GetNetworkPing), höchstens LatencyCap; ohne Messung DefaultLatency.
ArcadeRules.LatencyCap = 0.15
ArcadeRules.LatencySlack = 0.05
ArcadeRules.DefaultLatency = 0.08
ArcadeRules.FinishGrace = 60 -- Abrechnung bis endAt + FinishGrace, danach verfällt die Runde
ArcadeRules.StartCooldown = 1 -- Sekunden zwischen zwei Rundenstarts
ArcadeRules.MaxInputs = 600 -- Eingaben je Runde (danach wird nichts mehr angenommen)
ArcadeRules.InputRate = 25 -- Eingaben je Sekunde (Eimer), zusätzlich zum 2.4.0-Budget
ArcadeRules.InputBurst = 30
ArcadeRules.DailyCap = 1500 -- Credits je UTC-Tag aus der Spielhalle
ArcadeRules.MaxScore = 1000
ArcadeRules.MinRewardScore = 100 -- darunter gibt es keine Credits
ArcadeRules.RewardCurve = 1.25 -- Credits = reward × (Punkte/1000)^Kurve (Spitzenleistung lohnt sich mehr)
ArcadeRules.MaxXp = 8 -- XP je Runde bei 1000 Punkten (nur solange das Tageslimit nicht erreicht ist)
ArcadeRules.RecentTokens = 16 -- abgerechnete Tokens, deren Ergebnis erneut gesendet werden kann

-- Automaten (Schlüssel = Stations-Keys aus tools/worldgen/contract.py ARCADE_GAMES).
-- reward = Credits bei 1000 Punkten. Werkstatt bleibt die Haupteinnahme (PHASE2_CONTRACT §7): eine Runde dauert
-- mit Countdown und Auswertung etwa eine Minute, Level 1 bringt in der Werkstatt rund 100–200 Cr pro Minute.
ArcadeRules.Games = {
	{
		key = "arcade_1", name = "BLITZ-REAKTION", title = "Blitz-Reaktion", kind = "reaction", reward = 35,
		color = { 255, 64, 180 },
		blurb = "Fünf rote Lampen – gehen sie aus, drückst du!",
		howto = "Fünf Starts wie in der Formel 1: Die roten Lampen leuchten nacheinander auf und gehen nach einer zufälligen Pause gleichzeitig aus. Genau dann drückst du. Wer vorher drückt oder schneller als 0,1 s ist, macht einen Frühstart.",
		controls = "Knopf „START!“, Leertaste oder Controller-Taste A",
	},
	{
		key = "arcade_2", name = "BREMSWEG-PROFI", title = "Bremsweg-Profi", kind = "brake", reward = 40,
		color = { 60, 220, 255 },
		blurb = "Bremse so, dass du genau an der Haltelinie stehst.",
		howto = "Vier Anfahrten mit wechselndem Tempo und Straßenzustand. Oben steht der Bremsweg. Die Leitpfosten zeigen den Abstand zur Haltelinie in Metern. Bremse genau dort, wo der Bremsweg beginnt. Zu früh kostet Punkte, über die Linie kostet viele.",
		controls = "Knopf „BREMSEN!“, Leertaste oder Controller-Taste A",
	},
	{
		key = "arcade_3", name = "BOXENSTOPP", title = "Boxenstopp", kind = "pitstop", reward = 30,
		color = { 235, 184, 72 },
		blurb = "Vier Räder, zwanzig Muttern – über Kreuz und schnell!",
		howto = "Ziehe an allen vier Rädern die fünf Radmuttern über Kreuz an. An den ersten beiden Rädern stehen die Nummern, ab dem dritten Rad nur noch die erste Mutter: Danach immer eine Mutter überspringen. Falsche Mutter = 1 Strafsekunde. Du hast 28 Sekunden.",
		controls = "Radmuttern antippen oder anklicken",
	},
	{
		key = "arcade_4", name = "DREHMOMENT", title = "Drehmoment", kind = "torque", reward = 30,
		color = { 150, 80, 255 },
		blurb = "Halte das Drehmoment im grünen Bereich.",
		howto = "Halte den Knopf gedrückt, um den Drehmomentschlüssel anzuziehen, und lass los, damit er nachgibt. Bleib 24 Sekunden lang im grünen Sollbereich – er wandert und wird enger. Über 184 Nm ist die Schraube überdreht und kostet Punkte.",
		controls = "Knopf „ANZIEHEN“ halten, Leertaste halten oder Controller-Taste A halten",
	},
	{
		key = "arcade_5", name = "MOTOR-OHR", title = "Motor-Ohr", kind = "engine", reward = 40,
		color = { 50, 192, 137 },
		blurb = "Erkenne den kranken Motor am Klangbild.",
		howto = "Sechs Diagnosen: Oben steht, wie der Fehler klingt. Darunter laufen die Klangbilder von vier Motoren. Tippe auf den Motor, der genau dieses Problem hat. Je schneller du richtig liegst, desto mehr Punkte. Für jede Frage hast du 7 Sekunden.",
		controls = "Motor A–D antippen oder anklicken",
	},
	{
		key = "arcade_6", name = "EINPARK-PROFI", title = "Einpark-Profi", kind = "park", reward = 45,
		color = { 59, 134, 218 },
		blurb = "Park vorwärts oder rückwärts in die markierte Lücke.",
		howto = "Drei Parkaufgaben in 50 Sekunden. Pfeil in Fahrtrichtung = vorwärts, Pfeil entgegen = rückwärts (das Auto bleibt ausgerichtet), Pfeil zur Seite = einlenken. Die grüne Lücke zeigt, ob vorwärts oder rückwärts eingeparkt wird. Wenige Züge und kein Blechschaden bringen die meisten Punkte.",
		controls = "Pfeiltasten, WASD, Steuerkreuz oder die Pfeilknöpfe",
	},
	{
		key = "arcade_7", name = "RENNSIMULATOR 1", title = "Rennsimulator 1 · Landstraße", kind = "race", reward = 45,
		color = { 212, 65, 89 },
		blurb = "Drei Spuren, 40 Sekunden: weich dem Verkehr aus.",
		howto = "Du fährst auf einer dreispurigen Landstraße. Wechsle die Spur, um Hindernissen auszuweichen, und sammle Pokale. Das Tempo steigt. Drei Unfälle, und das Rennen ist vorbei.",
		controls = "Links/Rechts: Pfeiltasten, A/D, Steuerkreuz oder die Knöpfe",
		lanes = 3, duration = 40, gap0 = 1.0, gap1 = 0.55, double = 0.2, doubleGrow = 0.5, triple = 0,
		pickup = 0.3, oil = 0, startLane = 2, theme = "day",
	},
	{
		key = "arcade_8", name = "RENNSIMULATOR 2", title = "Rennsimulator 2 · Nachtrennen", kind = "race", reward = 50,
		color = { 255, 150, 60 },
		blurb = "Vier Spuren bei Nacht – Vorsicht, Ölspuren!",
		howto = "Nachtrennen auf der vierspurigen Stadtautobahn, 45 Sekunden. Weiche Hindernissen aus und sammle Pokale. Fährst du über eine Ölspur, rutscht dein Auto kurz und lässt sich nicht lenken. Drei Unfälle, und das Rennen ist vorbei.",
		controls = "Links/Rechts: Pfeiltasten, A/D, Steuerkreuz oder die Knöpfe",
		lanes = 4, duration = 45, gap0 = 0.85, gap1 = 0.45, double = 0.3, doubleGrow = 0.45, triple = 0.3,
		pickup = 0.3, oil = 0.18, startLane = 2, theme = "night",
	},
}
ArcadeRules.GameByKey = {}
ArcadeRules.GameByName = {}
for i, def in ipairs(ArcadeRules.Games) do
	def.index = i
	ArcadeRules.GameByKey[def.key] = def
	ArcadeRules.GameByName[def.name] = def
end

-- Automat aus Schlüssel ("arcade_3") oder Anzeigenamen ("BOXENSTOPP", Stations-Attribut Game)
function ArcadeRules.Resolve(x)
	if type(x) ~= "string" then
		return nil
	end
	return ArcadeRules.GameByKey[x] or ArcadeRules.GameByName[x] or ArcadeRules.GameByName[string.upper(x)]
end

---------------------------------------------------------------- Spielregeln je Automat
ArcadeRules.Reaction = {
	attempts = 5, lights = 5, lightStep = 0.5, minDelay = 0.5, maxDelay = 2.5, window = 1.2, gap = 1.3, tail = 0.8,
	minReaction = 0.1, full = 0.2, zero = 0.75, points = 200,
}
ArcadeRules.Brake = {
	runs = 4, points = 250, perfect = 0.04, early = 0.6, late = 0.3, overrun = 8, rest = 1.8, minApproach = 2.0,
	conditions = {
		{ id = "dry", name = "Trockene Fahrbahn", a = 8, lo = 70, hi = 130 },
		{ id = "wet", name = "Nasse Fahrbahn", a = 5.5, lo = 60, hi = 100 },
		{ id = "snow", name = "Schneeglätte", a = 3.5, lo = 40, hi = 70 },
	},
}
ArcadeRules.Pitstop = {
	wheels = 4, nuts = 5, limit = 28, swap = 0.6, penalty = 1, minGap = 0.06, ideal = 7, numbered = 2,
	names = { "Vorne links", "Vorne rechts", "Hinten links", "Hinten rechts" },
}
ArcadeRules.Torque = {
	duration = 24, rise = 40, fall = 30, max = 100, red = 92, step = 3, first = 30, lo = 25, hi = 80,
	minJump = 8, maxJump = 30, halves = { 9, 7.5, 6 }, halfStep = 8, dt = 0.05, lead = 1, overWeight = 0.5,
	display = 2, -- Anzeige in Nm = Wert × 2 (0..200 Nm)
}
ArcadeRules.Engine = {
	questions = 6, limit = 7, pause = 1.5, samples = 64, grace = 1, base = 0.6,
	faults = { "misfire", "knock", "belt", "rough", "bearing" },
	names = {
		misfire = "Zündaussetzer", knock = "Klopfen", belt = "Keilriemen", rough = "Unrunder Lauf",
		bearing = "Lagerschaden", healthy = "Gesunder Motor",
	},
	texts = {
		misfire = "Zündaussetzer: Der Motor stottert. Im Klangbild fehlt regelmäßig ein Takt – jeder vierte Ausschlag bleibt aus.",
		knock = "Klopfen: Es klingelt metallisch. Direkt hinter jedem Takt sitzt ein zusätzlicher, spitzer Ausschlag.",
		belt = "Keilriemen: Es quietscht hoch. Zwischen den Takten zittert die Grundlinie fein auf und ab.",
		rough = "Unrunder Lauf: Der Leerlauf schwankt. Die Abstände zwischen den Takten sind ungleichmäßig.",
		bearing = "Lagerschaden: Es brummt tief. Die Ausschläge schwellen langsam an und ab, die Grundlinie brummt mit.",
		healthy = "Gesunder Motor gesucht: Drei Motoren haben einen Defekt. Welcher läuft sauber und gleichmäßig?",
	},
}
ArcadeRules.Park = {
	w = 8, h = 6, tasks = 3, duration = 50, pause = 1, minGap = 0.08, parked = 0.6, minPar = 3,
	moveWeight = 0.3, timeWeight = 0.2, base = 0.5, bumpPenalty = 0.08, minDone = 0.1, secondsPerMove = 0.35, slack = 12,
}
ArcadeRules.Race = { first = 2.0, lives = 3, minSwitch = 0.1, invuln = 1.0, slide = 0.6, rowPts = 10, pickPts = 25 }

---------------------------------------------------------------- Hilfen
local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end
ArcadeRules.Finite = finite

local function clamp(x, lo, hi)
	if x < lo then
		return lo
	elseif x > hi then
		return hi
	end
	return x
end

local function r3(x)
	return math.floor(x * 1000 + 0.5) / 1000
end

-- Deterministischer Zufallsgenerator (Park–Miller, exakt in doppelter Genauigkeit)
function ArcadeRules.Rng(seed)
	local s = math.floor(math.abs(tonumber(seed) or 1)) % (MOD - 1) + 1
	local r = {}
	function r.next()
		s = (s * 48271) % MOD
		return s / MOD
	end
	function r.int(a, b)
		return a + math.floor(r.next() * (b - a + 1))
	end
	function r.shuffle(list)
		for i = #list, 2, -1 do
			local j = r.int(1, i)
			list[i], list[j] = list[j], list[i]
		end
		return list
	end
	return r
end

function ArcadeRules.DayKey(now)
	return os.date("!%Y-%m-%d", math.floor(now))
end

-- Zeitfenster wie das 2.4.0-QTE: at ∈ [now − 0,5; now + 0,06]
function ArcadeRules.AcceptTime(at, now)
	return finite(at) and finite(now) and at >= now - ArcadeRules.PastTolerance and at <= now + ArcadeRules.FutureTolerance
end

-- Einweg-Latenz aus der Round-Trip-Zeit (Player:GetNetworkPing, Sekunden), begrenzt auf [0; LatencyCap]
function ArcadeRules.Latency(ping)
	if not finite(ping) or ping < 0 then
		return ArcadeRules.DefaultLatency
	end
	return clamp(ping / 2, 0, ArcadeRules.LatencyCap)
end

-- Gewerteter Zeitpunkt einer Eingabe: nie früher als Ankunft − Latenz − LatencySlack (Rückdatierung begrenzt)
function ArcadeRules.InputTime(at, now, lat)
	local floor = now - clamp(finite(lat) and lat or 0, 0, ArcadeRules.LatencyCap) - ArcadeRules.LatencySlack
	if at < floor then
		return floor
	end
	return at
end

function ArcadeRules.Rating(score)
	score = finite(score) and score or 0
	if score >= 900 then
		return "Weltklasse!"
	elseif score >= 750 then
		return "Stark!"
	elseif score >= 550 then
		return "Gut gemacht!"
	elseif score >= 300 then
		return "Solide."
	end
	return "Übung macht den Meister."
end

local function fmt(n, places)
	return (string.format("%." .. (places or 1) .. "f", n):gsub("%.", ","))
end
ArcadeRules.Format = fmt

---------------------------------------------------------------- BLITZ-REAKTION
local Reaction = {}

function ArcadeRules.ReactionPoints(r)
	local c = ArcadeRules.Reaction
	if not finite(r) or r < c.minReaction then
		return 0
	end
	return math.floor(c.points * clamp((c.zero - r) / (c.zero - c.full), 0, 1) + 0.5)
end

-- Feste Taktung: Start i beginnt bei (i−1) × Periode, unabhängig von den Pausen davor. So verraten weder der
-- nächste Start noch die Rundendauer, wann die Lampen des vorigen Starts ausgegangen sind (View zeigt nur l).
function ArcadeRules.ReactionPeriod()
	local c = ArcadeRules.Reaction
	return (c.lights - 1) * c.lightStep + c.maxDelay + c.window + c.gap
end

function Reaction.gen(r)
	local c = ArcadeRules.Reaction
	local list = {}
	local period = ArcadeRules.ReactionPeriod()
	local steps = math.floor((c.maxDelay - c.minDelay) / 0.05 + 0.5)
	for i = 1, c.attempts do
		local t = (i - 1) * period
		local delay = c.minDelay + r.int(0, steps) * 0.05
		list[i] = { l = r3(t), g = r3(t + (c.lights - 1) * c.lightStep + delay) }
	end
	local lastL = list[#list].l
	local duration = r3(lastL + (c.lights - 1) * c.lightStep + c.maxDelay + c.window + c.tail)
	return { attempts = list, lights = c.lights, lightStep = c.lightStep, window = c.window }, {}, duration
end

function Reaction.new()
	return { res = {} }
end

-- Welcher Start ist zur Zeit t offen? (von den ersten Lampen bis Ende des Reaktionsfensters). Auf dem Client ist
-- g erst nach "arcade_go" bekannt: bis dahin gilt der Start bis zum Beginn des nächsten als offen.
function ArcadeRules.ReactionAttempt(p, t)
	for i, a in ipairs(p.attempts) do
		if t >= a.l then
			local open
			if a.g ~= nil then
				open = t <= a.g + p.window
			else
				local nextA = p.attempts[i + 1]
				open = nextA == nil or t < nextA.l
			end
			if open then
				return i, a
			end
		end
	end
	return nil
end

function Reaction.input(p, st, t)
	local i, a = ArcadeRules.ReactionAttempt(p, t)
	if not i or st.res[i] then
		return false, nil
	end
	-- Lampen noch nicht aus (Client: g noch unbekannt) = Frühstart. Die Reaktionszeit wird um die Einweg-Latenz
	-- (p.lat, höchstens LatencyCap) bereinigt: "arcade_go" kommt so viel später beim Spieler an.
	local r = a.g and (t - a.g - (p.lat or 0)) or -1
	if r < ArcadeRules.Reaction.minReaction then
		st.res[i] = { early = true, points = 0 }
		return true, { attempt = i, early = true, points = 0 }
	end
	local pts = ArcadeRules.ReactionPoints(r)
	st.res[i] = { r = r, points = pts }
	return true, { attempt = i, reaction = r3(r), points = pts }
end

function Reaction.finish(p, st, cut)
	local score, best, early, missed = 0, nil, 0, 0
	for i, a in ipairs(p.attempts) do
		local res = st.res[i]
		if res then
			score += res.points
			if res.early then
				early += 1
			elseif not best or res.r < best then
				best = res.r
			end
		elseif a.g + p.window <= cut then
			missed += 1
		end
	end
	local lines = {}
	table.insert(lines, best and ("Beste Reaktion: " .. fmt(best, 3) .. " s") or "Keine gültige Reaktion")
	if early > 0 then
		table.insert(lines, "Frühstarts: " .. early)
	end
	if missed > 0 then
		table.insert(lines, "Verpasst: " .. missed)
	end
	return score, lines, { best = best and r3(best) or 0, early = early, missed = missed }
end

---------------------------------------------------------------- BREMSWEG-PROFI
local Brake = {}

local function speed(run)
	return run.kmh / 3.6
end

-- Position der Fahrzeugfront (Meter ab Start) zur Zeit t (relativ zum Start der Anfahrt), tb = Bremsbeginn oder nil
function ArcadeRules.BrakePosition(run, tb, t)
	local v = speed(run)
	if not tb or t <= tb then
		return v * t
	end
	local dt = math.min(t - tb, v / run.a)
	return v * tb + v * dt - 0.5 * run.a * dt * dt
end

-- Haltepunkt bei Bremsbeginn tb; Abweichung zur Linie in Metern (positiv = über die Linie)
function ArcadeRules.BrakeError(run, tb)
	local v = speed(run)
	return v * tb + v * v / (2 * run.a) - run.line
end

-- Punkte aus der Abweichung, gemessen als Zeitfehler beim Bremsbeginn (gerecht bei jedem Tempo)
function ArcadeRules.BrakePoints(run, err)
	local c = ArcadeRules.Brake
	local e = err / speed(run)
	if math.abs(e) <= c.perfect then
		return c.points
	elseif e < 0 then
		return math.floor(c.points * clamp(1 - (-e - c.perfect) / c.early, 0, 1) + 0.5)
	end
	return math.floor(c.points * 0.5 * clamp(1 - (e - c.perfect) / c.late, 0, 1) + 0.5)
end

function Brake.gen(r)
	local c = ArcadeRules.Brake
	local runs, t = {}, 0
	for i = 1, c.runs do
		local ci = r.int(1, #c.conditions)
		local cond = c.conditions[ci]
		local kmh = cond.lo + 5 * r.int(0, math.floor((cond.hi - cond.lo) / 5))
		local v = kmh / 3.6
		local dist = v * v / (2 * cond.a)
		local approach = c.minApproach + r.int(0, 15) * 0.1
		local line = r3(v * approach + dist)
		local pass = r3((line + c.overrun) / v)
		runs[i] = { at = r3(t), kmh = kmh, cond = ci, a = cond.a, line = line, pass = pass, dist = math.floor(dist + 0.5) }
		t = t + math.max(pass, approach + v / cond.a) + c.rest
	end
	return { runs = runs, conditions = { c.conditions[1].name, c.conditions[2].name, c.conditions[3].name } }, {}, r3(t)
end

function Brake.new()
	return { res = {} }
end

function ArcadeRules.BrakeRun(p, t)
	for i, run in ipairs(p.runs) do
		if t >= run.at and t <= run.at + run.pass then
			return i, run
		end
	end
	return nil
end

function Brake.input(p, st, t)
	local i, run = ArcadeRules.BrakeRun(p, t)
	if not i or st.res[i] then
		return false, nil
	end
	local tb = t - run.at
	local err = ArcadeRules.BrakeError(run, tb)
	local pts = ArcadeRules.BrakePoints(run, err)
	st.res[i] = { tb = tb, err = err, points = pts }
	return true, { run = i, err = r3(err), points = pts }
end

function Brake.finish(p, st, cut)
	local score, best, over, missed = 0, nil, 0, 0
	for i, run in ipairs(p.runs) do
		local res = st.res[i]
		if res then
			score += res.points
			if res.err > 0 and res.err / speed(run) > ArcadeRules.Brake.perfect then
				over += 1
			end
			if not best or math.abs(res.err) < math.abs(best) then
				best = res.err
			end
		elseif run.at + run.pass <= cut then
			missed += 1
		end
	end
	local lines = {}
	table.insert(lines, best and ("Beste Bremsung: " .. fmt(math.abs(best), 1) .. " m " .. (best > 0 and "über der Linie" or "vor der Linie")) or "Keine Bremsung")
	if over > 0 then
		table.insert(lines, "Über die Linie: " .. over)
	end
	if missed > 0 then
		table.insert(lines, "Nicht gebremst: " .. missed)
	end
	return score, lines, { best = best and r3(best) or 0, over = over, missed = missed }
end

---------------------------------------------------------------- BOXENSTOPP
local Pitstop = {}

local function wrap(n)
	return (n - 1) % 5 + 1
end

-- Position der k-ten Mutter (k ab 0) bei Startmutter start und Richtung dir (+1 im Uhrzeigersinn, −1 dagegen)
function ArcadeRules.NutAt(start, k, dir)
	return wrap(start + 2 * k * dir)
end

-- Erwartete Mutter(n) als Menge {[pos] = richtung}; ohne Richtung sind beide Kreuz-Nachbarn richtig
function ArcadeRules.PitstopExpect(wheel, k, dir)
	if k == 0 then
		return { [wheel.start] = 0 }
	end
	if not dir or dir == 0 then
		return { [wrap(wheel.start + 2)] = 1, [wrap(wheel.start - 2)] = -1 }
	end
	return { [ArcadeRules.NutAt(wheel.start, k, dir)] = dir }
end

function Pitstop.gen(r)
	local c = ArcadeRules.Pitstop
	local wheels = {}
	for w = 1, c.wheels do
		local numbered = w <= c.numbered
		local start = r.int(1, c.nuts)
		local dir = r.int(0, 1) * 2 - 1
		wheels[w] = { start = start, dir = numbered and dir or 0, numbered = numbered, name = c.names[w] }
	end
	return { wheels = wheels, limit = c.limit, swap = c.swap, penalty = c.penalty, nuts = c.nuts }, {}, c.limit
end

function Pitstop.new(p)
	return {
		w = 1, k = 0, dir = p.wheels[1].dir ~= 0 and p.wheels[1].dir or nil, ready = 0, last = -math.huge,
		mistakes = 0, done = 0, tight = {}, finish = nil,
	}
end

function Pitstop.input(p, st, t, v)
	local c = ArcadeRules.Pitstop
	if st.finish or t < st.ready or v < 1 or v > c.nuts then
		return false, nil
	end
	if t - st.last < c.minGap then
		return false, nil
	end
	st.last = t
	local wheel = p.wheels[st.w]
	local expect = ArcadeRules.PitstopExpect(wheel, st.k, st.dir)
	local dir = expect[v]
	if dir == nil then
		st.mistakes += 1
		return true, { ok = false, wheel = st.w, pos = v, mistakes = st.mistakes }
	end
	local w = st.w
	st.k += 1
	st.done += 1
	st.tight[w * 10 + v] = true
	if dir ~= 0 and not st.dir then
		st.dir = dir
	end
	local info = { ok = true, wheel = w, pos = v, nut = st.k, mistakes = st.mistakes }
	if st.k >= c.nuts then
		info.wheelDone = true
		if w >= #p.wheels then
			st.finish = t
			info.finished = true
		else
			st.w = w + 1
			st.k = 0
			local nextDir = p.wheels[st.w].dir
			st.dir = nextDir ~= 0 and nextDir or nil
			st.ready = t + c.swap
			info.ready = r3(st.ready)
		end
	end
	return true, info
end

function ArcadeRules.PitstopScore(finishT, mistakes, done)
	local c = ArcadeRules.Pitstop
	if finishT then
		local eff = finishT + mistakes * c.penalty
		return math.floor(400 + 600 * clamp((c.limit - eff) / (c.limit - c.ideal), 0, 1) + 0.5)
	end
	return clamp(20 * done - 10 * mistakes, 0, 380)
end

function Pitstop.finish(p, st)
	local score = ArcadeRules.PitstopScore(st.finish, st.mistakes, st.done)
	local lines = {}
	if st.finish then
		table.insert(lines, "Zeit: " .. fmt(st.finish, 2) .. " s")
	else
		table.insert(lines, "Nicht fertig: " .. st.done .. " von " .. (#p.wheels * p.nuts) .. " Muttern")
	end
	table.insert(lines, st.mistakes > 0 and ("Falsche Muttern: " .. st.mistakes) or "Keine falsche Mutter")
	return score, lines, { time = st.finish and r3(st.finish) or 0, mistakes = st.mistakes, done = st.done }
end

---------------------------------------------------------------- DREHMOMENT
local Torque = {}

function Torque.gen(r)
	local c = ArcadeRules.Torque
	local wp = { c.first }
	local n = math.floor(c.duration / c.step + 0.5)
	for i = 2, n + 1 do
		local prev = wp[i - 1]
		local delta = r.int(-c.maxJump, c.maxJump)
		if math.abs(delta) < c.minJump then
			delta = delta < 0 and -c.minJump or c.minJump
		end
		local nxt = prev + delta
		if nxt < c.lo or nxt > c.hi then
			nxt = prev - delta
		end
		wp[i] = clamp(nxt, c.lo, c.hi)
	end
	return {
		waypoints = wp, step = c.step, halves = table.clone(c.halves), halfStep = c.halfStep,
		rise = c.rise, fall = c.fall, max = c.max, red = c.red, display = c.display,
	}, {}, c.duration
end

-- Sollbereich zur Zeit t: Mitte, halbe Breite
function ArcadeRules.TorqueBand(p, t)
	local wp = p.waypoints
	local x = clamp(t / p.step, 0, #wp - 1)
	local i = math.floor(x)
	local f = x - i
	local a = wp[i + 1]
	local b = wp[math.min(i + 2, #wp)]
	local half = p.halves[math.min(#p.halves, math.floor(math.max(0, t) / p.halfStep) + 1)]
	return a + (b - a) * f, half
end

local function torqueStep(p, tau, hold, dt)
	if dt <= 0 then
		return tau
	end
	return clamp(tau + (hold and p.rise or -p.fall) * dt, 0, p.max)
end

-- Drehmoment zur Zeit t aus den Wechseln events = { {t = Zeit, v = 1 gedrückt | 0 losgelassen}, ... }
function ArcadeRules.TorqueAt(p, events, t)
	local tau, hold, last = 0, false, 0
	for _, e in ipairs(events) do
		if e.t > t then
			break
		end
		tau = torqueStep(p, tau, hold, e.t - last)
		last = e.t
		hold = e.v == 1
	end
	return torqueStep(p, tau, hold, t - last), hold
end

-- Zeit im Sollbereich und im roten Bereich bis cut (feste Abtastung, auf Server und Client gleich)
function ArcadeRules.TorqueEval(p, events, cut)
	local c = ArcadeRules.Torque
	local dt = c.dt
	local n = math.floor(c.duration / dt + 0.5)
	local tau, hold, last, ei = 0, false, 0, 1
	local inBand, over = 0, 0
	for k = 0, n - 1 do
		local t = (k + 0.5) * dt
		if t > cut then
			break
		end
		while events[ei] and events[ei].t <= t do
			local e = events[ei]
			tau = torqueStep(p, tau, hold, e.t - last)
			last = e.t
			hold = e.v == 1
			ei += 1
		end
		tau = torqueStep(p, tau, hold, t - last)
		last = t
		local center, half = ArcadeRules.TorqueBand(p, t)
		if math.abs(tau - center) <= half then
			inBand += dt
		end
		if tau > p.red then
			over += dt
		end
	end
	return inBand, over
end

function ArcadeRules.TorqueScore(inBand, over)
	local c = ArcadeRules.Torque
	local usable = c.duration - c.lead
	return math.floor(1000 * clamp((inBand - c.overWeight * over) / usable, 0, 1) + 0.5)
end

function Torque.new()
	return { events = {}, hold = false }
end

function Torque.input(p, st, t, v)
	if v ~= 0 and v ~= 1 then
		return false, nil
	end
	local hold = v == 1
	if hold == st.hold then
		return true, nil -- keine Änderung (z. B. doppelt gemeldet)
	end
	st.hold = hold
	table.insert(st.events, { t = t, v = v })
	return true, nil
end

function Torque.finish(p, st, cut)
	local inBand, over = ArcadeRules.TorqueEval(p, st.events, cut)
	local share = inBand / ArcadeRules.Torque.duration
	local lines = { "Im Sollbereich: " .. math.floor(share * 100 + 0.5) .. " %" }
	if over > 0 then
		table.insert(lines, "Überdreht: " .. fmt(over, 1) .. " s")
	end
	return ArcadeRules.TorqueScore(inBand, over), lines, { inBand = r3(inBand), over = r3(over) }
end

---------------------------------------------------------------- MOTOR-OHR
local Engine = {}

-- Klangbild als Zeichenkette aus 64 Ziffern 0..9 (Ausschlaghöhe je Abtastwert)
function ArcadeRules.EngineWave(kind, r)
	local n = ArcadeRules.Engine.samples
	local base = kind == "bearing" and 2 or 1
	local s = table.create(n, base)
	local function put(i, v)
		if i >= 1 and i <= n and v > s[i] then
			s[i] = v
		end
	end
	local period = r.int(6, 8)
	local pos = r.int(1, period)
	local wobble = r.next() * 2 * math.pi
	local idx = 0
	while pos <= n do
		idx += 1
		if not (kind == "misfire" and idx % 4 == 0) then
			local amp = 8
			if kind == "bearing" then
				amp = 4 + math.floor(5 * (0.5 + 0.5 * math.sin(pos / n * 4 * math.pi + wobble)) + 0.5)
			end
			put(pos, amp)
			put(pos + 1, amp - 2)
			put(pos + 2, math.max(1, amp - 5))
			if kind == "knock" then
				put(pos + 3, 9)
			end
		end
		local gap = period
		if kind == "rough" then
			gap = math.max(4, period + r.int(-3, 3))
		end
		pos += gap
	end
	if kind == "belt" then
		for i = 1, n do
			if s[i] <= 1 then
				s[i] = (i % 2 == 0) and 3 or 1
			end
		end
	end
	local out = table.create(n)
	for i = 1, n do
		out[i] = tostring(clamp(s[i], 0, 9))
	end
	return table.concat(out)
end

function Engine.gen(r)
	local c = ArcadeRules.Engine
	local targets = table.clone(c.faults)
	r.shuffle(targets)
	table.insert(targets, r.int(1, #targets + 1), "healthy")
	while #targets > c.questions do
		table.remove(targets)
	end
	local questions, answers, kinds = {}, {}, {}
	for q, target in ipairs(targets) do
		local distract = {}
		if target == "healthy" then
			local pool = r.shuffle(table.clone(c.faults))
			distract = { pool[1], pool[2], pool[3] }
		else
			local pool = {}
			for _, f in ipairs(c.faults) do
				if f ~= target then
					table.insert(pool, f)
				end
			end
			r.shuffle(pool)
			local used = 0
			for j = 1, 3 do
				if r.next() < 0.5 then
					distract[j] = "healthy"
				else
					used += 1
					distract[j] = pool[used]
				end
			end
		end
		local answer = r.int(1, 4)
		local options, j = {}, 0
		for k = 1, 4 do
			if k == answer then
				options[k] = target
			else
				j += 1
				options[k] = distract[j]
			end
		end
		local waves = {}
		for k = 1, 4 do
			waves[k] = ArcadeRules.EngineWave(options[k], r)
		end
		questions[q] = {
			title = target == "healthy" and "Welcher Motor ist gesund?" or ("Welcher Motor hat diesen Fehler: " .. c.names[target] .. "?"),
			text = c.texts[target],
			waves = waves,
		}
		answers[q] = answer
		kinds[q] = options
	end
	local duration = r3(#questions * (c.limit + c.pause))
	return { questions = questions, limit = c.limit, pause = c.pause }, { answers = answers, kinds = kinds }, duration
end

function Engine.new()
	return { q = 1, qAt = 0, res = {}, points = 0, correct = 0 }
end

-- Abgelaufene Fragen bis t auflösen (ohne Antwort = 0 Punkte). Rückgabe: letzte aufgelöste Frage oder nil
local function engineAdvance(p, st, t)
	local last
	while st.q <= #p.questions and t > st.qAt + p.limit do
		st.res[st.q] = { timeout = true, points = 0 }
		last = st.q
		st.qAt = st.qAt + p.limit + p.pause
		st.q += 1
	end
	return last
end

function ArcadeRules.EnginePoints(dt)
	local c = ArcadeRules.Engine
	local speedShare = clamp(1 - (dt - c.grace) / (c.limit - c.grace), 0, 1)
	return 1000 / c.questions * (c.base + (1 - c.base) * speedShare)
end

function Engine.input(p, st, t, v, secret)
	local timedOut = engineAdvance(p, st, t)
	local q = st.q
	if v == 0 then
		-- "Zeit abgelaufen" vom Client: nur auflösen, keine Antwort
		if timedOut then
			return true, {
				q = timedOut, timeout = true, answer = secret.answers[timedOut], points = 0,
				nextAt = r3(st.qAt), done = st.q > #p.questions,
			}
		end
		return false, nil
	end
	if q > #p.questions or t < st.qAt or v < 1 or v > 4 then
		return false, nil
	end
	local correct = v == secret.answers[q]
	local pts = correct and ArcadeRules.EnginePoints(t - st.qAt) or 0
	st.res[q] = { choice = v, correct = correct, points = pts, dt = t - st.qAt }
	st.points += pts
	if correct then
		st.correct += 1
	end
	st.qAt = t + p.pause
	st.q = q + 1
	return true, {
		q = q, correct = correct, answer = secret.answers[q], choice = v, points = math.floor(pts + 0.5),
		nextAt = r3(st.qAt), done = st.q > #p.questions, timedOut = timedOut,
	}
end

function Engine.finish(p, st, cut, secret)
	engineAdvance(p, st, cut)
	local lines = { "Richtig: " .. st.correct .. " von " .. #p.questions }
	local fastest
	for _, res in pairs(st.res) do
		if res.correct and (not fastest or res.dt < fastest) then
			fastest = res.dt
		end
	end
	if fastest then
		table.insert(lines, "Schnellste Diagnose: " .. fmt(fastest, 1) .. " s")
	end
	return math.floor(st.points + 1e-6), lines, { correct = st.correct, total = #p.questions }
end

---------------------------------------------------------------- EINPARK-PROFI
local Park = {}
-- Richtungen: 1 = hoch (Norden), 2 = rechts (Osten), 3 = runter (Süden), 4 = links (Westen)
ArcadeRules.DX = { 0, 1, 0, -1 }
ArcadeRules.DY = { -1, 0, 1, 0 }

function ArcadeRules.Opposite(d)
	return (d + 1) % 4 + 1
end

local function cellIndex(p, x, y)
	return y * p.w + x + 1
end

function ArcadeRules.ParkCell(p, task, x, y)
	return string.sub(task.grid, cellIndex(p, x, y), cellIndex(p, x, y))
end

-- Ein Zug: Pfeil in Fahrtrichtung = vorwärts, entgegen = rückwärts (Ausrichtung bleibt), seitlich = einlenken.
-- Parkbuchten (oberste und unterste Reihe) sind seitlich durch Linien getrennt.
-- Rückgabe: x, y, h, blockiert
function ArcadeRules.ParkMove(p, task, x, y, h, d)
	local nh = (d == h or d == ArcadeRules.Opposite(h)) and h or d
	local nx, ny = x + ArcadeRules.DX[d], y + ArcadeRules.DY[d]
	if nx < 0 or nx >= p.w or ny < 0 or ny >= p.h then
		return x, y, h, true
	end
	if ny == y and (y == 0 or y == p.h - 1) then
		return x, y, h, true
	end
	if ArcadeRules.ParkCell(p, task, nx, ny) ~= "." then
		return x, y, h, true
	end
	return nx, ny, nh, false
end

-- Kürzeste Zugfolge (Breitensuche über Feld und Ausrichtung). Rückgabe: Anzahl Züge oder nil
function ArcadeRules.ParkPar(p, task)
	local function id(x, y, h)
		return (y * p.w + x) * 4 + h
	end
	local seen = { [id(task.sx, task.sy, task.sh)] = 0 }
	local queue, head = { { task.sx, task.sy, task.sh } }, 1
	while queue[head] do
		local cur = queue[head]
		head += 1
		local dist = seen[id(cur[1], cur[2], cur[3])]
		if cur[1] == task.tx and cur[2] == task.ty and cur[3] == task.th then
			return dist
		end
		for d = 1, 4 do
			local nx, ny, nh, blocked = ArcadeRules.ParkMove(p, task, cur[1], cur[2], cur[3], d)
			if not blocked then
				local k = id(nx, ny, nh)
				if seen[k] == nil then
					seen[k] = dist + 1
					table.insert(queue, { nx, ny, nh })
				end
			end
		end
	end
	return nil
end

local function parkTask(r, p, index)
	local c = ArcadeRules.Park
	local w, h = p.w, p.h
	for attempt = 1, 40 do
		local grid = table.create(w * h, ".")
		local free = {}
		for _, y in ipairs({ 0, h - 1 }) do
			for x = 0, w - 1 do
				if r.next() < c.parked then
					grid[y * w + x + 1] = "c"
				else
					table.insert(free, { x, y })
				end
			end
		end
		if #free > 0 then
			local tg = free[r.int(1, #free)]
			local mode
			if index == 1 then
				mode = "forward"
			elseif index == 2 then
				mode = "reverse"
			else
				mode = r.next() < 0.5 and "forward" or "reverse"
			end
			local th
			if tg[2] == 0 then
				th = mode == "forward" and 1 or 3
			else
				th = mode == "forward" and 3 or 1
			end
			local side = r.int(0, 1)
			local task = {
				sx = side == 0 and 0 or w - 1, sy = r.int(1, h - 2), sh = side == 0 and 2 or 4,
				tx = tg[1], ty = tg[2], th = th, mode = mode,
			}
			local cones = attempt <= 30 and r.int(1, 3) or 0
			for _ = 1, cones do
				local cx, cy = r.int(1, w - 2), r.int(1, h - 2)
				if not (cx == task.sx and cy == task.sy) then
					grid[cy * w + cx + 1] = "k"
				end
			end
			task.grid = table.concat(grid)
			local par = ArcadeRules.ParkPar(p, task)
			if par and par >= c.minPar then
				task.par = par
				return task
			end
		end
	end
	-- Rückfall (praktisch nie): leerer Platz, Lücke oben links, vorwärts
	local task = { sx = p.w - 1, sy = 2, sh = 4, tx = 0, ty = 0, th = 1, mode = "forward", grid = string.rep(".", p.w * p.h) }
	task.par = ArcadeRules.ParkPar(p, task)
	return task
end

function Park.gen(r)
	local c = ArcadeRules.Park
	local p = { w = c.w, h = c.h, pause = c.pause }
	local tasks = {}
	for i = 1, c.tasks do
		tasks[i] = parkTask(r, p, i)
	end
	p.tasks = tasks
	return p, {}, c.duration
end

function Park.new(p)
	local t1 = p.tasks[1]
	return { i = 1, x = t1.sx, y = t1.sy, h = t1.sh, moves = 0, bumps = 0, taskAt = 0, last = -math.huge, res = {}, totalBumps = 0 }
end

function ArcadeRules.ParkTaskPoints(task, moves, bumps, dt)
	local c = ArcadeRules.Park
	local eff = math.min(1, task.par / math.max(1, moves))
	local tf = clamp(1 - (dt - task.par * c.secondsPerMove) / c.slack, 0, 1)
	local share = clamp(c.base + c.moveWeight * eff + c.timeWeight * tf - c.bumpPenalty * bumps, c.minDone, 1)
	return 1000 / c.tasks * share
end

function Park.input(p, st, t, v)
	local c = ArcadeRules.Park
	if st.i > #p.tasks or t < st.taskAt or v < 1 or v > 4 or t - st.last < c.minGap then
		return false, nil
	end
	st.last = t
	local task = p.tasks[st.i]
	local nx, ny, nh, blocked = ArcadeRules.ParkMove(p, task, st.x, st.y, st.h, v)
	if blocked then
		st.bumps += 1
		st.totalBumps += 1
		return true, { task = st.i, bump = true, x = st.x, y = st.y, h = st.h, bumps = st.bumps }
	end
	st.x, st.y, st.h = nx, ny, nh
	st.moves += 1
	local info = { task = st.i, x = nx, y = ny, h = nh, moves = st.moves, bumps = st.bumps }
	if nx == task.tx and ny == task.ty and nh == task.th then
		local pts = ArcadeRules.ParkTaskPoints(task, st.moves, st.bumps, t - st.taskAt)
		st.res[st.i] = { moves = st.moves, bumps = st.bumps, time = t - st.taskAt, points = pts }
		info.parked = true
		info.points = math.floor(pts + 0.5)
		st.i += 1
		st.moves, st.bumps = 0, 0
		st.taskAt = t + p.pause
		info.nextAt = r3(st.taskAt)
		info.done = st.i > #p.tasks
		local nxt = p.tasks[st.i]
		if nxt then
			st.x, st.y, st.h = nxt.sx, nxt.sy, nxt.sh
		end
	end
	return true, info
end

function Park.finish(p, st)
	local score, done, moves, par = 0, 0, 0, 0
	for i, res in pairs(st.res) do
		score += res.points
		done += 1
		moves += res.moves
		par += p.tasks[i].par
	end
	local lines = { "Eingeparkt: " .. done .. " von " .. #p.tasks }
	if done > 0 then
		table.insert(lines, "Züge: " .. moves .. " (bestmöglich " .. par .. ")")
	end
	table.insert(lines, st.totalBumps > 0 and ("Blechschäden: " .. st.totalBumps) or "Ohne Kratzer")
	return math.floor(score + 1e-6), lines, { done = done, moves = moves, par = par, bumps = st.totalBumps }
end

---------------------------------------------------------------- RENNSIMULATOR 1/2
local Race = {}
-- Reihe = Zeichenkette je Spur: "0" frei, "1" Hindernis, "2" Pokal, "3" Ölspur. times[k] = Zeitpunkt, an dem
-- die Reihe die Höhe des eigenen Autos erreicht (relativ zum Start). Kollision: Spur des Autos zu diesem Zeitpunkt.

function Race.gen(r, def)
	local c = ArcadeRules.Race
	local lanes, duration = def.lanes, def.duration
	local times, rows = {}, {}
	local pickups = 0
	local t = c.first
	while t <= duration - 0.4 do
		local prog = t / duration
		local blocked = 1
		if r.next() < def.double + def.doubleGrow * prog then
			blocked += 1
		end
		if lanes >= 4 and prog > 0.45 and r.next() < def.triple then
			blocked += 1
		end
		blocked = math.min(blocked, lanes - 1)
		local order = {}
		for l = 1, lanes do
			order[l] = l
		end
		r.shuffle(order)
		local row = table.create(lanes, "0")
		for k = 1, blocked do
			row[order[k]] = "1"
		end
		local k = blocked + 1
		if k <= lanes and r.next() < def.pickup then
			row[order[k]] = "2"
			pickups += 1
			k += 1
		end
		-- Ölspur nur, wenn danach noch eine ganz freie Spur bleibt (immer vermeidbar)
		if def.oil > 0 and lanes - k >= 1 and r.next() < def.oil then
			row[order[k]] = "3"
		end
		table.insert(times, r3(t))
		table.insert(rows, table.concat(row))
		t += def.gap0 + (def.gap1 - def.gap0) * prog
	end
	local maxPoints = #times * c.rowPts + pickups * c.pickPts
	return {
		lanes = lanes, lives = c.lives, times = times, rows = rows, startLane = def.startLane, theme = def.theme,
		minSwitch = c.minSwitch, slide = c.slide, invuln = c.invuln, rowPts = c.rowPts, pickPts = c.pickPts,
		maxPoints = maxPoints,
	}, {}, duration
end

function ArcadeRules.RaceNew(p)
	return {
		lane = p.startLane, lastSwitch = -math.huge, slide = -math.huge, invuln = -math.huge, row = 1,
		lives = p.lives, dead = false, deadAt = nil, passed = 0, picks = 0, crashes = 0, slides = 0, points = 0,
	}
end

-- Wertet alle Reihen bis t aus (inclusive: auch die Reihe genau bei t). Rückgabe: Liste der Ereignisse
-- { {row, kind = "crash"|"pick"|"oil"|"pass"|"dead"} } (für die Anzeige auf dem Client).
function ArcadeRules.RaceAdvance(p, st, t, inclusive)
	local events
	while st.row <= #p.times do
		local tk = p.times[st.row]
		if tk > t or (tk == t and not inclusive) then
			break
		end
		if not st.dead then
			local obj = string.sub(p.rows[st.row], st.lane, st.lane)
			local kind
			if obj == "1" then
				if tk >= st.invuln then
					st.lives -= 1
					st.crashes += 1
					st.invuln = tk + p.invuln
					kind = "crash"
					if st.lives <= 0 then
						st.dead = true
						st.deadAt = tk
						kind = "dead"
					end
				end
			else
				st.passed += 1
				st.points += p.rowPts
				kind = "pass"
				if obj == "2" then
					st.picks += 1
					st.points += p.pickPts
					kind = "pick"
				elseif obj == "3" then
					st.slide = tk + p.slide
					st.slides += 1
					kind = "oil"
				end
			end
			if kind then
				events = events or {}
				table.insert(events, { row = st.row, kind = kind, lane = st.lane })
			end
		end
		st.row += 1
	end
	return events
end

-- Spurwahl zur Zeit t (Reihen davor müssen ausgewertet sein). Rückgabe: ok, Grund
function ArcadeRules.RaceSteer(p, st, t, lane)
	if st.dead then
		return false, "dead"
	end
	if lane == st.lane then
		return true, nil
	end
	if lane < 1 or lane > p.lanes or math.abs(lane - st.lane) > 1 then
		return false, "lane"
	end
	if t < st.slide then
		return false, "slide"
	end
	if t - st.lastSwitch < p.minSwitch then
		return false, "fast"
	end
	st.lane = lane
	st.lastSwitch = t
	return true, nil
end

function Race.new(p)
	return ArcadeRules.RaceNew(p)
end

function Race.input(p, st, t, v)
	ArcadeRules.RaceAdvance(p, st, t, false)
	if st.dead then
		return false, nil
	end
	local ok, reason = ArcadeRules.RaceSteer(p, st, t, v)
	if not ok then
		return false, { reject = reason, lane = st.lane, lives = st.lives }
	end
	return true, nil
end

function Race.finish(p, st, cut)
	ArcadeRules.RaceAdvance(p, st, cut, true)
	local score = p.maxPoints > 0 and math.floor(1000 * st.points / p.maxPoints + 1e-6) or 0
	local lines = { "Reihen geschafft: " .. st.passed .. " von " .. #p.times }
	if st.picks > 0 then
		table.insert(lines, "Pokale: " .. st.picks)
	end
	table.insert(lines, st.crashes > 0 and ("Unfälle: " .. st.crashes) or "Unfallfrei!")
	if st.slides > 0 then
		table.insert(lines, "Ölspuren: " .. st.slides)
	end
	return score, lines, { passed = st.passed, picks = st.picks, crashes = st.crashes, dead = st.dead }
end

---------------------------------------------------------------- Runde (Server)
local KINDS = { reaction = Reaction, brake = Brake, pitstop = Pitstop, torque = Torque, engine = Engine, park = Park, race = Race }
ArcadeRules.Kinds = KINDS

-- Neue Runde. seed bestimmt alle Parameter; startAt = now + Countdown. Rückgabe: round oder nil
-- lat = Einweg-Latenz des Spielers (ArcadeRules.Latency), wird für die Runde festgehalten.
function ArcadeRules.NewRound(key, seed, now, token, lat)
	local def = ArcadeRules.GameByKey[key]
	if not def or not finite(seed) or not finite(now) then
		return nil
	end
	local K = KINDS[def.kind]
	local r = ArcadeRules.Rng(seed)
	local p, secret, duration = K.gen(r, def)
	lat = clamp(finite(lat) and lat or 0, 0, ArcadeRules.LatencyCap)
	p.lat = lat
	local startAt = now + ArcadeRules.Countdown
	return {
		token = token, key = def.key, kind = def.kind, seed = seed,
		startAt = startAt, duration = duration, endAt = startAt + duration,
		p = p, secret = secret, st = K.new(p, secret), lat = lat,
		lastAt = -math.huge, inputs = 0, rejected = 0, closed = false,
	}
end

-- Öffentliche Parameter: BLITZ-REAKTION ohne die Ausgeh-Zeitpunkte g (sonst könnte ein Skript genau g + 0,2 senden)
local function publicParams(round)
	if round.kind ~= "reaction" then
		return round.p
	end
	local p = table.clone(round.p)
	p.attempts = {}
	for i, a in ipairs(round.p.attempts) do
		p.attempts[i] = { l = a.l }
	end
	return p
end
ArcadeRules.PublicParams = publicParams

-- BLITZ-REAKTION: Zeitpunkte (Serverzeit), zu denen der Server "arcade_go" sendet. Rückgabe: { {attempt, at} }
function ArcadeRules.GoEvents(round)
	local out = {}
	if round.kind == "reaction" then
		for i, a in ipairs(round.p.attempts) do
			table.insert(out, { attempt = i, at = round.startAt + a.g })
		end
	end
	return out
end

-- Inhalt von mini_notice "arcade_go" (erst im Moment, in dem die Lampen ausgehen)
function ArcadeRules.GoView(round, i)
	local a = round.p.attempts and round.p.attempts[i]
	if round.kind ~= "reaction" or not a then
		return nil
	end
	return { token = round.token, attempt = i, g = a.g }
end

-- Öffentliche Rundendaten für den Client. Ohne Seed und ohne Lösungen: aus dem Seed ließen sich mit diesem
-- (geteilten) Modul die Antworten von MOTOR-OHR nachrechnen. Feld gameKind statt kind, weil mini_notice
-- das Feld kind für die Art des Hinweises nutzt.
function ArcadeRules.View(round)
	return {
		token = round.token, game = round.key, gameKind = round.kind,
		startAt = round.startAt, endAt = round.endAt, duration = round.duration, params = publicParams(round),
	}
end

-- Eine Eingabe. Rückgabe: angenommen (bool), Info für den Client (mini_notice "arcade_step") oder nil.
-- Abgelehnt werden: falsches Zeitfenster (reject = "late"/"early"), falsche Reihenfolge ("order"), zu viele Eingaben.
-- Eingaben vor dem Start oder nach dem Ende werden still ignoriert.
function ArcadeRules.Input(round, at, value, now)
	if type(round) ~= "table" or round.closed then
		return false, nil
	end
	if not finite(at) or not finite(value) or value ~= math.floor(value) then
		round.rejected += 1
		return false, { reject = "invalid" }
	end
	if not ArcadeRules.AcceptTime(at, now) then
		round.rejected += 1
		return false, { reject = at < now and "late" or "early" }
	end
	at = ArcadeRules.InputTime(at, now, round.lat)
	if at < round.lastAt then
		round.rejected += 1
		return false, { reject = "order" }
	end
	if round.inputs >= ArcadeRules.MaxInputs then
		round.rejected += 1
		return false, { reject = "limit" }
	end
	local t = at - round.startAt
	if t < 0 or t > round.duration then
		return false, nil
	end
	round.lastAt = at
	round.inputs += 1
	local ok, info = KINDS[round.kind].input(round.p, round.st, t, value, round.secret)
	if info and info.reject then
		round.rejected += 1
	end
	return ok, info
end

-- Schließt die Runde und bewertet sie bis min(now, endAt). Rückgabe: { score, lines, stats }
function ArcadeRules.Finish(round, now)
	local cut = math.min(now, round.endAt) - round.startAt
	if cut < 0 then
		cut = -1
	end
	local score, lines, stats = KINDS[round.kind].finish(round.p, round.st, cut, round.secret)
	round.closed = true
	score = math.floor(clamp(finite(score) and score or 0, 0, ArcadeRules.MaxScore))
	return { score = score, lines = lines or {}, stats = stats or {} }
end

---------------------------------------------------------------- Belohnung, Tageslimit, Daten
-- Credits nur aus den Punkten (kein Einsatz, kein Zufall): reward × (Punkte/1000)^Kurve, unter MinRewardScore nichts.
function ArcadeRules.Reward(key, score)
	local def = ArcadeRules.GameByKey[key]
	if not def or not finite(score) or score < ArcadeRules.MinRewardScore then
		return 0
	end
	local q = clamp(score, 0, ArcadeRules.MaxScore) / ArcadeRules.MaxScore
	return math.floor(def.reward * q ^ ArcadeRules.RewardCurve + 0.5)
end

function ArcadeRules.Xp(score)
	if not finite(score) or score < ArcadeRules.MinRewardScore then
		return 0
	end
	return math.floor(ArcadeRules.MaxXp * clamp(score, 0, ArcadeRules.MaxScore) / ArcadeRules.MaxScore + 1e-6)
end

function ArcadeRules.Default()
	return { day = "", earned = 0, best = {} }
end

-- raw = gespeichertes d.games.arcade (oder nil). Idempotent; NaN/negativ/unbekannte Automaten -> verworfen.
function ArcadeRules.Load(raw, d, now)
	local a = ArcadeRules.Default()
	if type(raw) ~= "table" then
		return a
	end
	if type(raw.day) == "string" and string.match(raw.day, "^%d%d%d%d%-%d%d%-%d%d$") then
		a.day = raw.day
	end
	if finite(raw.earned) and raw.earned > 0 and a.day ~= "" then
		a.earned = math.floor(math.min(raw.earned, MAX_SAFE))
	end
	if type(raw.best) == "table" then
		for key, v in pairs(raw.best) do
			if type(key) == "string" and ArcadeRules.GameByKey[key] and finite(v) and v >= 1 then
				a.best[key] = math.floor(math.min(v, ArcadeRules.MaxScore))
			end
		end
	end
	return a
end

-- d.games.arcade (legt es an, falls die Verkabelung in MiniRules.LoadGames noch fehlt)
function ArcadeRules.Data(d)
	d.games = type(d.games) == "table" and d.games or {}
	local a = d.games.arcade
	if type(a) ~= "table" or type(a.best) ~= "table" or not finite(a.earned) or type(a.day) ~= "string" then
		a = ArcadeRules.Load(a)
		d.games.arcade = a
	end
	return a
end

-- Tageswechsel (UTC): Tageszähler zurücksetzen. true, wenn ein neuer Tag begann.
function ArcadeRules.EnsureDay(a, now)
	local today = ArcadeRules.DayKey(now)
	if a.day ~= today then
		a.day = today
		a.earned = 0
		return true
	end
	return false
end

function ArcadeRules.CapLeft(a, now)
	local today = ArcadeRules.DayKey(now)
	local earned = a.day == today and a.earned or 0
	return math.max(0, ArcadeRules.DailyCap - earned)
end

-- Verbucht eine abgerechnete Runde (ohne Geld: das zahlt der Dienst über MiniRules.AddMoney).
-- Rückgabe: { credits, want, capped, capLeft, best, newBest, xp }
function ArcadeRules.Payout(a, key, score, now)
	ArcadeRules.EnsureDay(a, now)
	local want = ArcadeRules.Reward(key, score)
	local left = math.max(0, ArcadeRules.DailyCap - a.earned)
	local credits = math.min(want, left)
	a.earned += credits
	local prev = a.best[key] or 0
	local newBest = score > prev
	if newBest then
		a.best[key] = score
	end
	return {
		credits = credits, want = want, capped = credits < want, capLeft = left - credits,
		best = math.max(prev, score), newBest = newBest and score > 0,
		xp = left > 0 and ArcadeRules.Xp(score) or 0, -- XP nur, solange das Tageslimit nicht erreicht war
	}
end

-- Snapshot-Feld arcade (PHASE2_CONTRACT §5)
function ArcadeRules.SnapshotView(d, now)
	local a = type(d.games) == "table" and type(d.games.arcade) == "table" and d.games.arcade or ArcadeRules.Default()
	local today = ArcadeRules.DayKey(now)
	local earned = a.day == today and finite(a.earned) and a.earned or 0
	local best = {}
	for key, v in pairs(type(a.best) == "table" and a.best or {}) do
		best[key] = v
	end
	return { earnedToday = earned, cap = ArcadeRules.DailyCap, left = math.max(0, ArcadeRules.DailyCap - earned), best = best }
end

return ArcadeRules
