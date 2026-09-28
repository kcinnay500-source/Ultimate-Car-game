-- CityClient: rein optische Animationen der Stadt, nur auf dem Client (nichts wird repliziert, nichts ist spielrelevant).
-- Animiert werden Parts oder Models unter Workspace.City.Animated mit dem Attribut Anim (CITY_SPEC §8):
--   press      Presse: die Pressplatte fährt periodisch herunter (1,2 s runter, 0,4 s halten, 2 s hoch); eigene Klicks
--              in der PressUI lösen einen zusätzlichen Stoß aus. Bewegt wird das direkte Kind mit Attribut Mover=true,
--              sonst das Kind mit genau einem dieser Namen: Platen, Ram, Stempel, Kolben, Pressplatte, Platte
--              (ganzer Name, keine Teilwörter – "Crosshead" oder "Frame" bewegen sich nie). Ein Model ohne solches
--              Kind bleibt stehen (Warnung). Attribute: Stroke (12,5), Period (3,6), Down (1,2 s), Hold (0,4 s), Up (2 s)
--   crane      Kran schwenkt um die Hochachse. Attribute: Swing (Grad, 50), Period (14)
--   turntable  Drehteller dreht sich. Attribute: Speed (Grad/s, 18)
--   door       Tor öffnet und schließt periodisch. Attribute: Lift (Studs, 90 % der Höhe), Period (10), Axis ("Y"|"X"|"Z")
--   fountain   Wasserstrahl pulsiert (Parts mit "Wasser"/"Water"/"Jet"/"Strahl" im Namen, sonst das Part selbst).
--              Attribute: Amplitude (Anteil, 0.35), Period (2). Crown = Name eines Kind-Models (z. B. Zahnradkrone), das
--              sich um Center (Vector3, sonst sein Pivot) dreht: YawPeriod (s, Hochachse) und SpinPeriod (s, Welt-Z-Achse);
--              die Krone ist kein Wasserstrahl und wippt nicht.
--   spin       Dauerdrehung um die eigene Achse, optional zusätzlich Gieren um die Hochachse (z. B. Zahnradkrone).
--              Attribute: Axis ("X"|"Y"|"Z", "Z"), Period (s pro Umdrehung, 12), YawPeriod (s pro Umdrehung, aus)
--   vault      Tresorrad dreht sich (wie spin). Attribute: Axis ("Z"), Period (8)
--   neon       Leuchtreklame pulsiert (Farbe → ColorB, sonst Transparenz), Lichter dimmen mit. Attribute: Period (1.6), ColorB
--   beacon     Warnleuchte blinkt (wie neon). Attribute: Period (1)
--   pylon      Hausnummer-Pylon pulsiert, solange das Attribut Owner nicht leer ist. Attribute: Period (2.4)
--   dyno       Leistungsprüfstand: Rollen ("Roll"/"Rolle"/"Walze" im Namen) drehen, das Auto darauf vibriert (nur nah).
--              Attribute: Speed (Grad/s, 720), Period (12)
--   lift       Hebebühne fährt hoch und wieder herunter. Mover wie bei press (Namen Platform, Plattform, Buehne, Bühne),
--              sonst das Objekt selbst. Attribute: Lift (3.6), Period (60)
--   barrier    Schranke öffnet (Drehung um die lokale Z-Achse des Pivots) und schließt. Mover: Kind mit Mover=true oder
--              Name Boom/Baum/Schlagbaum/Schranke, sonst das Objekt selbst. Attribute: Angle (80), Period (12), Axis ("Z")
--   gavel      Auktionshammer schlägt. Mover: Kind Mover=true oder Name Hammer, sonst das Objekt. Attribute: Period (6)
--   clock      Uhrzeiger nach Lighting.ClockTime (vom Server gesetzt). Zeiger = das Objekt selbst oder seine Kinder mit
--              Attribut Hand ("hour"|"minute") bzw. "Stunde"/"Hour"/"Minute" im Namen. Mit Vector3-Attribut Pivot am Zeiger
--              (Nabe des Zifferblatts; Hub am Model = Turmmitte, bestimmt die Außenseite) wird der Winkel absolut gesetzt,
--              gleich in welcher Ruhestellung der Zeiger steht; sonst Drehung um die lokale Z-Achse des eigenen Pivots
--              mit Grundstellung 12 Uhr.
--   signal     Ampel nach dem 32-s-Programm der Serverzeit (CITY_SPEC §3.6). Linsen: Kinder Red/Amber/Green, PedRed/PedGreen.
--              Attribute: Serves ("Meile"|"Markt"|…), Group, PedPhase ("NS" 1–13 s | "WE" 18–26 s; sonst abgeleitet)
--   startlight Startampel: Neon-Lampen (nach Namen sortiert) gehen nacheinander an, dann alle aus. Attribute: Period (5)
--   wash       Waschbürsten ("Buerste"/"Bürste"/"Brush" im Namen) drehen um ihre Achse. Attribute: Speed (Grad/s, 240), Axis ("X")
--   parkgrid   bekannt, keine Animation (lokale Rätselautos)
--   traffic    Autos fahren eine Wegpunktliste ab. Wegpunkte: Vector3-Attribute WP1..WPn, String-Attribut Waypoints
--              ("x,y,z;x,y,z"), Kind-Parts WP1..WPn (auch im Kind-Ordner "Waypoints") oder Attribut Path = Name eines
--              Ordners/Models in City mit WP1..WPn. Attribute: Speed (Studs/s, 14), Loop (false = hin und zurück, sonst
--              Rundkurs), FacingOffset (Grad, 0), HeightOffset (Studs; Standard: Pivot-Höhe minus Höhe von WP1),
--              Phase (0..1) bzw. StartOffset (Studs; Standard: Startposition des Autos).
--              Haltelinien: String-Attribut Stops ("x,z,Serves;…") am Pfad-Ordner oder am Auto; das Auto hält dort,
--              solange die Ampel für Serves nicht grün ist. Autos auf demselben Pfad halten 14 Studs Abstand.
--              Die Teile eines Verkehrsautos werden lokal CanCollide/CanQuery/CanTouch=false gesetzt (rein optisch).
--   flag       Fahne weht (Drehung um die Mastkante bzw. den Pivot). Attribute: Swing (Grad, 12), Period (3)
-- Unbekannte Anim-Werte werden einmal je Wert gemeldet (warn) und nicht animiert.
-- Kosten (CITY_SPEC §3.7/§8): nur Objekte bis 300 Studs von der Kamera laufen; bis 120 Studs jedes Frame, dahinter im
-- 0,25-s-Takt. Höchstens 8 Autos (die nächsten) werden jedes Frame bewegt, die übrigen im 0,25-s-Takt (Parts per Tween).
-- Neon, Fahnen, Fontänen, Pylonen und Warnleuchten laufen als endlose Tweens ohne Lua-Arbeit pro Frame.
-- Periodische Bewegungen richten sich nach der Serverzeit, damit alle Spieler dasselbe sehen.
-- Fehlt Workspace.City (oder Animated), wartet das Modul still, bis es erscheint.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")

local CityClient = {}

local started = false
local records = {} -- [inst] = Datensatz
local frameRecs = {} -- Liste der bewegten Datensätze (ohne Verkehr)
local trafficRecs = {} -- Verkehr
local pressRecs = {}
local pathCache = {} -- [Container] = gemeinsamer Pfad (für Abstand zwischen Autos)
local warned = {}
local stompAt = -math.huge
local lastStomp = -math.huge

local FAST_TRAFFIC = 8
local CULL = 300 -- Studs: weiter entfernte Animationen pausieren (CITY_SPEC: 300)
local NEAR = 120 -- Studs: bis hier jedes Frame, dahinter im langsamen Takt
local SHAKE_NEAR = 80 -- Studs: Rüttel-Effekt des Prüfstands nur aus der Nähe
local SLOW_INTERVAL = 0.25
local FOLLOW_GAP = 14
local SIGNAL_CYCLE = 32

CityClient.FastTraffic = FAST_TRAFFIC
CityClient.Cull = CULL
CityClient.Near = NEAR

---------------------------------------------------------------- Hilfen
local function warnOnce(key, text)
	if warned[key] then
		return
	end
	warned[key] = true
	warn("[CityClient] " .. text)
end

local function num(inst, name, default)
	local v = inst:GetAttribute(name)
	return type(v) == "number" and v == v and v or default
end

local function now()
	return workspace:GetServerTimeNow()
end

local function phaseOf(t, period)
	period = math.max(0.05, period)
	return (t % period) / period
end

local function lower(s)
	return string.lower(s)
end

local function nameHas(inst, words)
	local n = lower(inst.Name)
	for _, w in ipairs(words) do
		if string.find(n, w, 1, true) then
			return true
		end
	end
	return false
end

-- Ganzer Name (ohne Groß/Klein und ohne Ziffern-/Leerzeichen-Anhang wie "Platen 2"), keine Teilwörter
local function nameIs(inst, names)
	local n = lower(inst.Name):gsub("[%s_%-]*%d*$", "")
	for _, w in ipairs(names) do
		if n == w then
			return true
		end
	end
	return false
end

local function movable(c)
	return c:IsA("BasePart") or c:IsA("Model")
end

-- Bewegtes Kind: zuerst Attribut Mover=true, sonst ganzer Name aus names. nil, wenn keines passt.
local function findMover(inst, names)
	if not inst:IsA("Model") then
		return nil
	end
	for _, c in ipairs(inst:GetChildren()) do
		if movable(c) and c:GetAttribute("Mover") == true then
			return c
		end
	end
	for _, c in ipairs(inst:GetChildren()) do
		if movable(c) and nameIs(c, names) then
			return c
		end
	end
	return nil
end

local function baseParts(root)
	local list = {}
	if root:IsA("BasePart") then
		table.insert(list, root)
	end
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			table.insert(list, d)
		end
	end
	return list
end

local function neonParts(root)
	local parts = {}
	for _, part in ipairs(baseParts(root)) do
		if part.Material == Enum.Material.Neon then
			table.insert(parts, part)
		end
	end
	return parts
end

local function extentsY(inst)
	if inst:IsA("BasePart") then
		return inst.Size.Y
	elseif inst:IsA("Model") then
		local ok, size = pcall(function()
			return inst:GetExtentsSize()
		end)
		if ok and size then
			return size.Y
		end
	end
	return 8
end

local function dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function axisAngles(axisName, a)
	if axisName == "X" then
		return CFrame.Angles(a, 0, 0)
	elseif axisName == "Y" then
		return CFrame.Angles(0, a, 0)
	end
	return CFrame.Angles(0, 0, a)
end

local function camPos()
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame and cam.CFrame.Position or nil
end

-- Endloser Hin-und-her-Tween. Der Versatz wirkt nur einmal beim Start (DelayTime würde jede Wiederholung verzögern).
local function endless(inst, seconds, goal, delay)
	local info = TweenInfo.new(seconds, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true, 0)
	local tw = TweenService:Create(inst, info, goal)
	if delay and delay > 0 then
		task.delay(delay, function()
			if inst.Parent then
				tw:Play()
			end
		end)
	else
		tw:Play()
	end
	return tw
end

-- Neon-Teile pulsieren (Farbe oder Transparenz), Lichter dimmen mit. Liefert die Tweens.
local function pulse(inst, period, colorB)
	local parts = neonParts(inst)
	if #parts == 0 then
		parts = baseParts(inst)
	end
	local delay = math.random() * period
	local tweens = {}
	for _, part in ipairs(parts) do
		if typeof(colorB) == "Color3" then
			table.insert(tweens, endless(part, period / 2, { Color = colorB }, delay))
		else
			table.insert(tweens, endless(part, period / 2, { Transparency = math.min(1, part.Transparency + 0.45) }, delay))
		end
	end
	local lights = {}
	if inst:IsA("Light") then
		table.insert(lights, inst)
	end
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("Light") then
			table.insert(lights, d)
		end
	end
	for _, light in ipairs(lights) do
		table.insert(tweens, endless(light, period / 2, { Brightness = light.Brightness * 0.3 }, delay))
	end
	return tweens
end

---------------------------------------------------------------- Ampelprogramm (CITY_SPEC §3.6)
-- Zustand der Fahrzeugampel für einen Strom ("Meile" | "Markt"): "green" | "amber" | "red"
function CityClient.SignalState(serves, t)
	local tt = (t or now()) % SIGNAL_CYCLE
	if serves == "Meile" then
		return tt < 14 and "green" or tt < 16 and "amber" or "red"
	elseif serves == "Markt" then
		return tt < 17 and "red" or tt < 27 and "green" or tt < 29 and "amber" or "red"
	end
	return "red"
end

-- Fußgängerampel: "NS" (Querachse, Kreuzungsarme N/S) grün bei 1–13 s, "WE" (Plaza, Arme W/O) bei 18–26 s
function CityClient.PedGreen(phase, t)
	local tt = (t or now()) % SIGNAL_CYCLE
	if phase == "WE" then
		return tt >= 18 and tt < 26
	end
	return tt >= 1 and tt < 13
end

---------------------------------------------------------------- Arten
local Kinds = {}

-- Presse: schnell herunter, kurz halten, langsam hoch; eigener Klick = zusätzlicher kurzer Stoß
local PRESS_MOVERS = { "platen", "ram", "stempel", "kolben", "pressplatte", "platte" }
function Kinds.press(inst)
	local mover = inst
	if inst:IsA("Model") then
		mover = findMover(inst, PRESS_MOVERS)
		if not mover then
			warnOnce("press_" .. inst:GetFullName(), inst:GetFullName() .. ": Presse ohne Pressplatte (Kind 'Platen' oder Attribut Mover=true) – steht still")
			return nil
		end
	end
	local period = math.max(0.5, num(inst, "Period", 3.6))
	local rec = { inst = mover, base = mover:GetPivot(), stroke = num(inst, "Stroke", 12.5), period = period }
	-- Spezifikation: 1,2 s herunter, 0,4 s halten, 2 s hoch; Rest der Periode oben warten
	local downS = math.max(0.05, num(inst, "Down", 1.2))
	local holdS = math.max(0, num(inst, "Hold", 0.4))
	local upS = math.max(0.05, num(inst, "Up", period - downS - holdS))
	local scale = math.min(1, period / (downS + holdS + upS)) -- passt nicht in die Periode: gleichmäßig stauchen
	local down = downS * scale / period
	local hold = down + holdS * scale / period
	local up = hold + upS * scale / period
	rec.update = function(r, t)
		local p = phaseOf(t, r.period)
		local f
		if p < down then
			f = (p / down) ^ 2
		elseif p < hold then
			f = 1
		elseif p < up then
			f = 1 - smooth((p - hold) / (up - hold))
		else
			f = 0
		end
		local s = os.clock() - stompAt
		if s >= 0 and s < 0.35 then
			local g = s < 0.1 and s / 0.1 or 1 - (s - 0.1) / 0.25
			f = math.max(f, 0.7 * g)
		end
		r.inst:PivotTo(CFrame.new(0, -r.stroke * f, 0) * r.base)
	end
	table.insert(pressRecs, rec)
	return rec
end

function Kinds.crane(inst)
	local rec = { inst = inst, base = inst:GetPivot(), swing = math.rad(num(inst, "Swing", 50)), period = num(inst, "Period", 14) }
	rec.update = function(r, t)
		local a = r.swing * math.sin(phaseOf(t, r.period) * 2 * math.pi)
		r.inst:PivotTo(r.base * CFrame.Angles(0, a, 0))
	end
	return rec
end

function Kinds.turntable(inst)
	local speed = num(inst, "Speed", 18)
	local rec = { inst = inst, base = inst:GetPivot(), speed = speed }
	rec.update = function(r, t)
		local turn = 360 / math.max(0.01, math.abs(r.speed))
		local a = math.rad(phaseOf(t, turn) * 360) * (r.speed < 0 and -1 or 1)
		r.inst:PivotTo(r.base * CFrame.Angles(0, a, 0))
	end
	return rec
end

function Kinds.door(inst)
	local axisName = inst:GetAttribute("Axis")
	local axis = axisName == "X" and Vector3.new(1, 0, 0) or axisName == "Z" and Vector3.new(0, 0, 1) or Vector3.new(0, 1, 0)
	local rec = { inst = inst, base = inst:GetPivot(), lift = num(inst, "Lift", extentsY(inst) * 0.9), period = num(inst, "Period", 10), axis = axis }
	rec.update = function(r, t)
		local p = phaseOf(t, r.period)
		local open
		if p < 0.15 then
			open = smooth(p / 0.15)
		elseif p < 0.55 then
			open = 1
		elseif p < 0.7 then
			open = 1 - smooth((p - 0.55) / 0.15)
		else
			open = 0
		end
		r.inst:PivotTo(r.base * CFrame.new(r.axis * (r.lift * open)))
	end
	return rec
end

-- Fontäne: Wasserteile wachsen und schrumpfen (Unterkante bleibt), als endloser Tween
function Kinds.fountain(inst)
	local amp = math.clamp(num(inst, "Amplitude", 0.35), 0.05, 0.9)
	local period = num(inst, "Period", 2)
	-- Zahnradkrone (Attribut Crown): dreht sich, statt zu pulsieren oder zu wippen
	local crownName = inst:GetAttribute("Crown")
	local crown = type(crownName) == "string" and inst:FindFirstChild(crownName) or nil
	if crown and not movable(crown) then
		crown = nil
	end
	local jets = {}
	for _, part in ipairs(baseParts(inst)) do
		if not (crown and (part == crown or part:IsDescendantOf(crown)))
			and nameHas(part, { "wasser", "water", "jet", "strahl", "fontaene", "fontäne" }) then
			table.insert(jets, part)
		end
	end
	if crown then
		for i, part in ipairs(jets) do
			local size, cf = part.Size, part.CFrame
			local low = 1 - amp
			endless(part, period / 2, { Size = Vector3.new(size.X, size.Y * low, size.Z), CFrame = cf * CFrame.new(0, -size.Y * (1 - low) / 2, 0) }, (i - 1) * 0.15)
		end
		local center = inst:GetAttribute("Center")
		local base = crown:GetPivot()
		local rec = {
			inst = crown, base = base, center = typeof(center) == "Vector3" and center or base.Position,
			yawPeriod = num(inst, "YawPeriod", 30), spinPeriod = num(inst, "SpinPeriod", 12),
		}
		rec.local0 = CFrame.new(rec.center):Inverse() * base
		rec.update = function(r, t)
			local yaw = r.yawPeriod > 0 and phaseOf(t, r.yawPeriod) * 2 * math.pi or 0
			local spin = r.spinPeriod > 0 and phaseOf(t, r.spinPeriod) * 2 * math.pi or 0
			r.inst:PivotTo(CFrame.new(r.center) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, 0, spin) * r.local0)
		end
		return rec
	end
	if #jets == 0 and inst:IsA("BasePart") then
		jets = { inst }
	end
	if #jets > 0 then
		for i, part in ipairs(jets) do
			local size, cf = part.Size, part.CFrame
			local low = 1 - amp
			local goalSize = Vector3.new(size.X, size.Y * low, size.Z)
			local goalCf = cf * CFrame.new(0, -size.Y * (1 - low) / 2, 0)
			endless(part, period / 2, { Size = goalSize, CFrame = goalCf }, (i - 1) * 0.15)
		end
		return nil
	end
	-- Model ohne Wasserteile: sanft wippen
	local rec = { inst = inst, base = inst:GetPivot(), period = period, amp = amp }
	rec.update = function(r, t)
		r.inst:PivotTo(r.base * CFrame.new(0, math.sin(phaseOf(t, r.period) * 2 * math.pi) * r.amp, 0))
	end
	return rec
end

-- Dauerdrehung um die eigene Achse, optional zusätzlich Gieren um die Hochachse (Zahnradkrone: YawPeriod 30, Period 12)
local function spinner(inst, defaultPeriod)
	local axisName = inst:GetAttribute("Axis")
	axisName = (axisName == "X" or axisName == "Y") and axisName or "Z"
	local rec = {
		inst = inst, base = inst:GetPivot(), axis = axisName,
		period = math.max(0.1, num(inst, "Period", defaultPeriod)),
		yawPeriod = num(inst, "YawPeriod", 0),
	}
	rec.update = function(r, t)
		local spin = axisAngles(r.axis, phaseOf(t, r.period) * 2 * math.pi)
		if r.yawPeriod > 0 then
			local yaw = CFrame.Angles(0, phaseOf(t, r.yawPeriod) * 2 * math.pi, 0)
			local pos = r.base.Position
			r.inst:PivotTo(CFrame.new(pos) * yaw * (r.base - pos) * spin)
		else
			r.inst:PivotTo(r.base * spin)
		end
	end
	return rec
end

function Kinds.spin(inst)
	return spinner(inst, 12)
end

function Kinds.vault(inst)
	return spinner(inst, 8)
end

-- Leuchtreklame: Neon-Teile pulsieren (Farbe oder Transparenz), Lichter dimmen mit
function Kinds.neon(inst)
	pulse(inst, num(inst, "Period", 1.6), inst:GetAttribute("ColorB"))
	return nil
end

-- Warnleuchte: blinkt im Sekundentakt
function Kinds.beacon(inst)
	pulse(inst, num(inst, "Period", 1), inst:GetAttribute("ColorB"))
	return nil
end

-- Hausnummer-Pylon: pulsiert nur, solange ein Besitzer eingetragen ist (Attribut Owner, vom Server gesetzt)
function Kinds.pylon(inst)
	local period = num(inst, "Period", 2.4)
	local tweens = nil
	local originals = {}
	for _, part in ipairs(neonParts(inst)) do
		originals[part] = part.Transparency
	end
	local function apply()
		local owner = inst:GetAttribute("Owner")
		local on = type(owner) == "string" and owner ~= ""
		if on and not tweens then
			tweens = pulse(inst, period)
		elseif not on and tweens then
			for _, tw in ipairs(tweens) do
				tw:Cancel()
			end
			tweens = nil
			for part, tr in pairs(originals) do
				part.Transparency = tr
			end
		end
	end
	apply()
	inst:GetAttributeChangedSignal("Owner"):Connect(apply)
	return nil
end

-- Leistungsprüfstand: Rollen drehen in Zyklen (hochfahren, halten, auslaufen), das Auto darauf vibriert (nur nah)
function Kinds.dyno(inst)
	local rollers, body = {}, nil
	if inst:IsA("BasePart") then
		table.insert(rollers, { part = inst, base = inst.CFrame })
	else
		for _, part in ipairs(baseParts(inst)) do
			if nameHas(part, { "roll", "walze" }) then
				table.insert(rollers, { part = part, base = part.CFrame })
			end
		end
		for _, c in ipairs(inst:GetChildren()) do
			if movable(c) and nameHas(c, { "car", "auto", "fahrzeug" }) then
				body = { inst = c, base = c:GetPivot() }
				break
			end
		end
		if #rollers == 0 and not body then
			body = { inst = inst, base = inst:GetPivot() }
		end
	end
	local rec = { inst = inst, base = inst:GetPivot(), speed = math.rad(num(inst, "Speed", 720)), period = num(inst, "Period", 12), angle = 0, shaken = false }
	rec.update = function(r, t, dt)
		local p = phaseOf(t, r.period)
		local factor
		if p < 0.1 then
			factor = smooth(p / 0.1)
		elseif p < 0.6 then
			factor = 1
		elseif p < 0.75 then
			factor = 1 - smooth((p - 0.6) / 0.15)
		else
			factor = 0
		end
		r.angle = (r.angle + r.speed * factor * dt) % (2 * math.pi)
		for _, roller in ipairs(rollers) do
			if roller.part.Parent then
				roller.part.CFrame = roller.base * CFrame.Angles(r.angle, 0, 0)
			end
		end
		if body and body.inst.Parent then
			if factor > 0 and (r.camDist or math.huge) < SHAKE_NEAR then
				local shake = factor * 0.04
				body.inst:PivotTo(body.base * CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0))
				r.shaken = true
			elseif r.shaken then
				body.inst:PivotTo(body.base)
				r.shaken = false
			end
		end
	end
	return rec
end

-- Hebebühne: hoch (10 %), oben halten, herunter (10 %), unten warten
function Kinds.lift(inst)
	local mover = findMover(inst, { "platform", "plattform", "buehne", "bühne" }) or inst
	local rec = { inst = mover, base = mover:GetPivot(), lift = num(inst, "Lift", 3.6), period = math.max(1, num(inst, "Period", 60)) }
	rec.update = function(r, t)
		local p = phaseOf(t, r.period)
		local up
		if p < 0.1 then
			up = smooth(p / 0.1)
		elseif p < 0.5 then
			up = 1
		elseif p < 0.6 then
			up = 1 - smooth((p - 0.5) / 0.1)
		else
			up = 0
		end
		r.inst:PivotTo(CFrame.new(0, r.lift * up, 0) * r.base)
	end
	return rec
end

-- Schranke: öffnet (Drehung um die lokale Achse des Pivots = Scharnier), bleibt offen, schließt
function Kinds.barrier(inst)
	local mover = findMover(inst, { "boom", "baum", "schlagbaum", "schranke" }) or inst
	local axisName = inst:GetAttribute("Axis")
	local rec = {
		inst = mover, base = mover:GetPivot(), angle = math.rad(num(inst, "Angle", 80)),
		period = math.max(1, num(inst, "Period", 12)), axis = (axisName == "X" or axisName == "Y") and axisName or "Z",
	}
	rec.update = function(r, t)
		local p = phaseOf(t, r.period)
		local open
		if p < 0.1 then
			open = 0
		elseif p < 0.25 then
			open = smooth((p - 0.1) / 0.15)
		elseif p < 0.6 then
			open = 1
		elseif p < 0.75 then
			open = 1 - smooth((p - 0.6) / 0.15)
		else
			open = 0
		end
		r.inst:PivotTo(r.base * axisAngles(r.axis, r.angle * open))
	end
	return rec
end

-- Auktionshammer: kurzer Schlag (Drehung um die lokale X-Achse des Pivots), dann Pause
function Kinds.gavel(inst)
	local mover = findMover(inst, { "hammer" }) or inst
	local rec = { inst = mover, base = mover:GetPivot(), period = math.max(1, num(inst, "Period", 6)), angle = math.rad(num(inst, "Angle", 35)) }
	rec.update = function(r, t)
		local p = phaseOf(t, r.period)
		local a = 0
		if p < 0.04 then
			a = p / 0.04
		elseif p < 0.14 then
			a = 1 - smooth((p - 0.04) / 0.1)
		end
		r.inst:PivotTo(r.base * CFrame.Angles(-r.angle * a, 0, 0))
	end
	return rec
end

-- Uhr: Zeiger nach Lighting.ClockTime; Grundstellung 12 Uhr, Drehung um die lokale Z-Achse des Pivots
local function handKind(inst)
	local h = inst:GetAttribute("Hand")
	if type(h) == "string" then
		h = lower(h)
		if h == "minute" or h == "min" or h == "minuten" then
			return "minute"
		elseif h == "hour" or h == "stunde" or h == "stunden" then
			return "hour"
		end
	end
	if nameHas(inst, { "minute", "minuten" }) then
		return "minute"
	elseif nameHas(inst, { "stunde", "hour" }) then
		return "hour"
	end
	return nil
end

function Kinds.clock(inst)
	local hands = {}
	local own = handKind(inst)
	if own or inst:IsA("BasePart") then
		table.insert(hands, { inst = inst, base = inst:GetPivot(), kind = own or "hour" })
	else
		for _, c in ipairs(inst:GetDescendants()) do
			local k = movable(c) and handKind(c)
			if k then
				table.insert(hands, { inst = c, base = c:GetPivot(), kind = k })
			end
		end
	end
	if #hands == 0 then
		warnOnce("clock_" .. inst:GetFullName(), inst:GetFullName() .. ": Uhr ohne Zeiger (Attribut Hand oder Name Stunde/Minute)")
		return nil
	end
	-- Absoluter Modus (Worldgen): Zeiger mit Pivot = Nabe; Außenseite von der Turmmitte (Hub am Model) weg
	local towerHub = inst:GetAttribute("Hub")
	local UP = Vector3.new(0, 1, 0)
	for _, hnd in ipairs(hands) do
		local hub = hnd.inst:GetAttribute("Pivot")
		if typeof(hub) == "Vector3" then
			local out
			if typeof(towerHub) == "Vector3" then
				local flat = Vector3.new(hub.X - towerHub.X, 0, hub.Z - towerHub.Z)
				out = flat.Magnitude > 1e-3 and flat.Unit or nil
			end
			if not out then
				local z = hnd.base.ZVector
				out = Vector3.new(z.X, 0, z.Z).Magnitude > 1e-3 and Vector3.new(z.X, 0, z.Z).Unit or Vector3.new(0, 0, 1)
			end
			local right = UP:Cross(out) -- für den Betrachter rechts (er blickt entgegen out)
			local d0 = hnd.base.Position - hub
			hnd.hub, hnd.out = hub, out
			hnd.angle0 = math.atan2(d0:Dot(right), d0:Dot(UP)) -- Ruhestellung, im Uhrzeigersinn ab 12 Uhr
			hnd.local0 = CFrame.new(hub):Inverse() * hnd.base
		end
	end
	local rec = { inst = inst, base = inst:GetPivot(), hands = hands, slow = true, shown = nil }
	rec.update = function(r)
		local clock = Lighting.ClockTime % 24
		local key = math.floor(clock * 60 * 4) -- Viertelminuten
		if key == r.shown then
			return
		end
		r.shown = key
		for _, hnd in ipairs(r.hands) do
			if hnd.inst.Parent then
				local turns = hnd.kind == "minute" and (clock % 1) or ((clock % 12) / 12)
				if hnd.hub then
					-- Drehung um die Achse "out" durch die Nabe; negativer Winkel = im Uhrzeigersinn für den Betrachter
					local phi = -(turns * 2 * math.pi - hnd.angle0)
					hnd.inst:PivotTo(CFrame.new(hnd.hub) * CFrame.fromAxisAngle(hnd.out, phi) * hnd.local0)
				else
					hnd.inst:PivotTo(hnd.base * CFrame.Angles(0, 0, -turns * 2 * math.pi))
				end
			end
		end
	end
	return rec
end

-- Ampel: Linsen nach dem Programm (Transparenz 0 = an, 0,7 = aus), nur bei Zustandswechsel geschrieben
local LENS_OFF = 0.7
function Kinds.signal(inst)
	local lenses = {}
	for _, d in ipairs(inst:GetDescendants()) do
		if d:IsA("BasePart") then
			local n = d.Name
			if n == "Red" or n == "Amber" or n == "Green" or n == "PedRed" or n == "PedGreen" then
				lenses[n] = lenses[n] or {}
				table.insert(lenses[n], d)
			end
		end
	end
	local serves = inst:GetAttribute("Serves")
	local group = tostring(inst:GetAttribute("Group") or "")
	local ped = inst:GetAttribute("PedPhase")
	if ped ~= "NS" and ped ~= "WE" then
		if group == "Plaza" then
			ped = "WE"
		elseif string.sub(group, 1, 9) == "Querachse" then
			ped = "NS"
		else
			-- Fußgänger gehen, während der Strom dieses Masts rot hat
			ped = serves == "Meile" and "WE" or "NS"
		end
	end
	local rec = { inst = inst, base = inst:GetPivot(), slow = true, serves = serves, ped = ped, lenses = lenses, shown = nil }
	local function set(name, on)
		for _, part in ipairs(rec.lenses[name] or {}) do
			part.Transparency = on and 0 or LENS_OFF
		end
	end
	rec.update = function(r, t)
		local state = (r.serves == "Meile" or r.serves == "Markt") and CityClient.SignalState(r.serves, t) or "red"
		local walk = CityClient.PedGreen(r.ped, t)
		local key = state .. (walk and "+" or "-")
		if key == r.shown then
			return
		end
		r.shown = key
		set("Red", state == "red")
		set("Amber", state == "amber")
		set("Green", state == "green")
		set("PedRed", not walk)
		set("PedGreen", walk)
	end
	return rec
end

-- Startampel: Lampen gehen nacheinander an, dann kurz alle aus
function Kinds.startlight(inst)
	local lamps = neonParts(inst)
	if #lamps == 0 then
		warnOnce("startlight_" .. inst:GetFullName(), inst:GetFullName() .. ": Startampel ohne Neon-Lampen")
		return nil
	end
	table.sort(lamps, function(a, b)
		return a.Name < b.Name
	end)
	local rec = { inst = inst, base = inst:GetPivot(), slow = true, lamps = lamps, period = math.max(1, num(inst, "Period", 5)), shown = -1 }
	rec.update = function(r, t)
		local n = #r.lamps
		local lit = math.floor(phaseOf(t, r.period) * (n + 2))
		if lit > n then
			lit = 0
		end
		if lit == r.shown then
			return
		end
		r.shown = lit
		for i, part in ipairs(r.lamps) do
			part.Transparency = i <= lit and 0 or 0.8
		end
	end
	return rec
end

-- Waschanlage: Bürsten drehen um ihre Achse
function Kinds.wash(inst)
	local brushes = {}
	for _, part in ipairs(baseParts(inst)) do
		if nameHas(part, { "buerste", "bürste", "brush" }) then
			table.insert(brushes, { part = part, base = part.CFrame })
		end
	end
	if #brushes == 0 then
		return nil
	end
	local axisName = inst:GetAttribute("Axis")
	local rec = {
		inst = inst, base = inst:GetPivot(), brushes = brushes, speed = math.rad(num(inst, "Speed", 240)),
		axis = (axisName == "Y" or axisName == "Z") and axisName or "X",
	}
	rec.update = function(r, t)
		local a = (t * r.speed) % (2 * math.pi)
		for _, b in ipairs(r.brushes) do
			if b.part.Parent then
				b.part.CFrame = b.base * axisAngles(r.axis, a)
			end
		end
	end
	return rec
end

-- Parkplatz-Raster: die Rätselautos bewegt die ParkingUI lokal; hier nichts zu tun
function Kinds.parkgrid()
	return nil
end

-- Fahne: Drehung um die Mastkante (Part) bzw. den Pivot (Model), als endloser Tween je Part
function Kinds.flag(inst)
	local swing = math.rad(num(inst, "Swing", 12))
	local period = num(inst, "Period", 3)
	local POLE = { "pole", "mast", "stange", "pfahl" }
	local hinge
	local cloth = {}
	if inst:IsA("BasePart") then
		local side = inst:GetAttribute("PoleSide") == "right" and 1 or -1
		hinge = inst.CFrame * CFrame.new(side * inst.Size.X / 2, 0, 0)
		cloth = { inst }
	else
		local pivot = inst:GetPivot()
		hinge = pivot
		for _, part in ipairs(baseParts(inst)) do
			if nameHas(part, POLE) then
				-- senkrechte Drehachse durch den Mast
				hinge = CFrame.new(part.Position) * (pivot - pivot.Position)
			else
				table.insert(cloth, part)
			end
		end
	end
	local delay = math.random() * period
	for _, part in ipairs(cloth) do
		local rel = hinge:Inverse() * part.CFrame
		part.CFrame = hinge * CFrame.Angles(0, -swing, 0) * rel
		endless(part, period / 2, { CFrame = hinge * CFrame.Angles(0, swing, 0) * rel }, delay)
	end
	return nil
end

---------------------------------------------------------------- Verkehr
local function parseWaypoints(s)
	local list = {}
	for x, y, z in string.gmatch(s, "(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)") do
		table.insert(list, Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
	end
	return list
end

local function waypointsFrom(container)
	local list = {}
	if not container then
		return list
	end
	local i = 1
	while true do
		local attr = container:GetAttribute("WP" .. i)
		if typeof(attr) == "Vector3" then
			table.insert(list, attr)
		else
			local child = container:FindFirstChild("WP" .. i)
			if child and child:IsA("BasePart") then
				table.insert(list, child.Position)
			elseif child and child:IsA("Attachment") then
				table.insert(list, child.WorldPosition)
			else
				break
			end
		end
		i += 1
	end
	if #list == 0 then
		local s = container:GetAttribute("Waypoints")
		if type(s) == "string" then
			list = parseWaypoints(s)
		end
	end
	return list
end

local function findPath(name)
	local city = workspace:FindFirstChild("City")
	if not city or type(name) ~= "string" or name == "" then
		return nil
	end
	local paths = city:FindFirstChild("Paths")
	return (paths and paths:FindFirstChild(name)) or city:FindFirstChild(name, true)
end

local function buildPath(points, loop)
	local segs, total = {}, 0
	local n = #points
	local count = loop and n or n - 1
	for i = 1, count do
		local a, b = points[i], points[i % n + 1]
		local len = (b - a).Magnitude
		if len > 1e-3 then
			table.insert(segs, { a = a, b = b, len = len, start = total })
			total += len
		end
	end
	return { segs = segs, total = total, loop = loop, cars = {}, stops = {} }
end

-- Punkt bei Strecke d (0..total)
local function sample(path, d)
	local segs = path.segs
	local lo, hi = 1, #segs
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		if segs[mid].start <= d then
			lo = mid
		else
			hi = mid - 1
		end
	end
	local s = segs[lo]
	local f = math.clamp((d - s.start) / s.len, 0, 1)
	return s.a + (s.b - s.a) * f
end

-- Strecke des Punkts auf dem Pfad, der p am nächsten liegt (Startposition des Autos)
local function project(path, p)
	local best, bestDist = 0, math.huge
	for _, s in ipairs(path.segs) do
		local ab = s.b - s.a
		local f = math.clamp(dot(p - s.a, ab) / (s.len * s.len), 0, 1)
		local q = s.a + ab * f
		local dist = (q - p).Magnitude
		if dist < bestDist then
			best, bestDist = s.start + f * s.len, dist
		end
	end
	return best
end

-- Haltelinien "x,z,Serves;x,z,Serves" (Serves Standard "Meile") → Strecken auf dem Pfad
local function addStops(path, s)
	if type(s) ~= "string" or not path.loop or #path.segs == 0 then
		return
	end
	local y = path.segs[1].a.Y
	for entry in string.gmatch(s, "[^;]+") do
		local x, z, serves = string.match(entry, "^%s*(%-?[%d%.]+)%s*,%s*(%-?[%d%.]+)%s*,?%s*([%w%-]*)%s*$")
		if x then
			table.insert(path.stops, { d = project(path, Vector3.new(tonumber(x), y, tonumber(z))), serves = serves ~= "" and serves or "Meile" })
		end
	end
end

function Kinds.traffic(inst)
	local container = inst
	local points = waypointsFrom(inst)
	if #points < 2 then
		container = inst:FindFirstChild("Waypoints")
		points = waypointsFrom(container)
	end
	if #points < 2 then
		container = findPath(inst:GetAttribute("Path"))
		points = waypointsFrom(container)
	end
	if #points < 2 then
		warnOnce("traffic_" .. inst:GetFullName(), inst:GetFullName() .. ": Verkehrsauto ohne Wegpunkte")
		return nil
	end
	local loop = inst:GetAttribute("Loop") ~= false
	-- Autos auf demselben Pfad-Ordner teilen sich den Pfad (Abstand halten, gemeinsame Haltelinien)
	local path = container ~= inst and pathCache[container]
	if not path or path.loop ~= loop then
		path = buildPath(points, loop)
		addStops(path, container and container:GetAttribute("Stops"))
		if container ~= inst then
			pathCache[container] = path
		end
	end
	addStops(path, container ~= inst and inst:GetAttribute("Stops") or nil)
	if path.total <= 0 then
		return nil
	end
	-- rein optisch: lokal bewegte Autos sollen niemanden schieben, einklemmen oder Treffer auslösen
	for _, part in ipairs(baseParts(inst)) do
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
	end
	local pivot = inst:GetPivot()
	local offset
	if type(inst:GetAttribute("StartOffset")) == "number" then
		offset = inst:GetAttribute("StartOffset")
	elseif type(inst:GetAttribute("Phase")) == "number" then
		offset = inst:GetAttribute("Phase") * path.total * (loop and 1 or 2)
	else
		offset = project(path, pivot.Position)
	end
	local speed = math.max(0.1, num(inst, "Speed", 14))
	local span = loop and path.total or 2 * path.total
	local rec = {
		inst = inst, path = path, speed = speed,
		u = (offset + speed * now()) % span, -- Strecke (Rundkurs 0..L, hin und zurück 0..2L)
		height = num(inst, "HeightOffset", pivot.Position.Y - points[1].Y),
		facing = CFrame.Angles(0, math.rad(num(inst, "FacingOffset", 0)), 0),
		isPart = inst:IsA("BasePart"), base = pivot, lastDir = pivot.LookVector, fast = false, moved = true,
	}
	table.insert(path.cars, rec)
	-- Fortschritt um dt: hält an roten Haltelinien und hinter dem vorausfahrenden Auto (nur Rundkurse)
	rec.advance = function(r, t, dt)
		local want = r.speed * dt
		local L = r.path.total
		if r.path.loop then
			local limit = want
			for _, st in ipairs(r.path.stops) do
				local gap = (st.d - r.u) % L
				if gap <= want + 0.5 and CityClient.SignalState(st.serves, t) ~= "green" then
					limit = math.min(limit, gap < 0.5 and 0 or gap)
				end
			end
			for _, o in ipairs(r.path.cars) do
				if o ~= r and o.inst.Parent then
					local gap = (o.u - r.u) % L
					if gap > 0 and gap < FOLLOW_GAP + want then
						limit = math.min(limit, math.max(0, gap - FOLLOW_GAP))
					end
				end
			end
			if limit > 0 then
				r.u = (r.u + limit) % L
				r.moved = true
			end
		else
			r.u = (r.u + want) % (2 * L)
			r.moved = true
		end
	end
	rec.cframe = function(r, extra)
		local L = r.path.total
		local u = r.u + (extra or 0)
		local d, ahead
		local look = math.min(4, L / 4)
		if r.path.loop then
			d = u % L
			ahead = sample(r.path, (d + look) % L)
		else
			u = u % (2 * L)
			if u <= L then
				d = u
				ahead = sample(r.path, math.min(L, d + look))
			else
				d = 2 * L - u
				ahead = sample(r.path, math.max(0, d - look))
			end
		end
		local p = sample(r.path, d)
		local dir = ahead - p
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude > 1e-3 then
			r.lastDir = dir
		end
		local pos = p + Vector3.new(0, r.height, 0)
		return CFrame.lookAt(pos, pos + r.lastDir) * r.facing
	end
	table.insert(trafficRecs, rec)
	return nil -- eigener Takt, nicht in frameRecs
end

---------------------------------------------------------------- Verwaltung
local MOVING = {
	press = true, crane = true, turntable = true, door = true, fountain = true, dyno = true, traffic = true, flag = true,
	spin = true, vault = true, lift = true, barrier = true, gavel = true, clock = true, wash = true,
}

local function animatedAncestor(inst, root)
	local p = inst.Parent
	while p and p ~= root do
		if (p:IsA("Model") or p:IsA("BasePart")) and type(p:GetAttribute("Anim")) == "string" then
			return true
		end
		p = p.Parent
	end
	return false
end

local function consider(inst, root)
	if records[inst] or not (inst:IsA("BasePart") or inst:IsA("Model")) then
		return
	end
	local kind = inst:GetAttribute("Anim")
	if type(kind) ~= "string" then
		return
	end
	kind = lower(kind)
	local fn = Kinds[kind]
	if not fn then
		warnOnce("kind_" .. kind, "Unbekannte Animation Anim='" .. kind .. "' (z. B. " .. inst:GetFullName() .. ") – wird nicht animiert")
		return
	end
	-- Bewegte Objekte in einem bereits animierten Objekt überspringen (sonst kämpfen zwei Animationen)
	if MOVING[kind] and animatedAncestor(inst, root) then
		return
	end
	records[inst] = kind -- Tween-Arten und Verkehr behalten nur die Art als Markierung
	local ok, rec = pcall(fn, inst)
	if not ok then
		warn("[CityClient] " .. inst:GetFullName() .. ": " .. tostring(rec))
		return
	end
	if rec then
		rec.kind = kind
		rec.pos = rec.base and rec.base.Position or inst:GetPivot().Position
		rec.active = false
		rec.fast = false
		rec.pendingDt = 0
		records[inst] = rec
		table.insert(frameRecs, rec)
	end
end

local refreshActivity

local function attach(animated)
	for _, d in ipairs(animated:GetDescendants()) do
		consider(d, animated)
	end
	animated.DescendantAdded:Connect(function(d)
		task.defer(function()
			if d.Parent then
				consider(d, animated)
			end
		end)
	end)
end

-- Ruft fn(child) auf, sobald parent ein Kind namens name hat (sofort oder später)
local function whenChild(parent, name, fn)
	local existing = parent:FindFirstChild(name)
	if existing then
		fn(existing)
		return
	end
	local conn
	conn = parent.ChildAdded:Connect(function(c)
		if c.Name == name and conn then
			conn:Disconnect()
			conn = nil
			fn(c)
		end
	end)
end

---------------------------------------------------------------- Takt
local cullTimer, slowTimer = 0, 0

refreshActivity = function()
	local cam = camPos()
	if not cam then
		return
	end
	for i = #frameRecs, 1, -1 do
		local r = frameRecs[i]
		if not r.inst.Parent then
			table.remove(frameRecs, i)
		else
			local dist = (r.pos - cam).Magnitude
			r.camDist = dist
			r.active = dist < CULL
			r.fast = r.active and not r.slow and dist < NEAR
		end
	end
	-- die nächsten 8 Autos jedes Frame, die übrigen im langsamen Takt; jenseits von CULL geparkt
	local sorted = {}
	for i = #trafficRecs, 1, -1 do
		local r = trafficRecs[i]
		if not r.inst.Parent then
			table.remove(trafficRecs, i)
		else
			local pos = r.inst:GetPivot().Position
			r.dist = (pos - cam).Magnitude
			table.insert(sorted, r)
		end
	end
	table.sort(sorted, function(a, b)
		return a.dist < b.dist
	end)
	for i, r in ipairs(sorted) do
		local fast = i <= FAST_TRAFFIC and r.dist < NEAR
		if fast and not r.fast and r.tween then
			r.tween:Cancel()
			r.tween = nil
		end
		r.fast = fast
		r.active = r.dist < CULL
	end
end

local function step(dt)
	local t = now()
	cullTimer += dt
	if cullTimer >= 0.5 then
		cullTimer = 0
		refreshActivity()
	end
	slowTimer += dt
	local slowTick = slowTimer >= SLOW_INTERVAL
	if slowTick then
		slowTimer = 0
	end
	for _, r in ipairs(frameRecs) do
		if r.active and r.inst.Parent then
			if r.fast then
				r.update(r, t, dt)
			else
				r.pendingDt += dt
				if slowTick then
					r.update(r, t, r.pendingDt)
					r.pendingDt = 0
				end
			end
		end
	end
	for _, r in ipairs(trafficRecs) do
		if r.inst.Parent and r.active then
			r.advance(r, t, dt) -- nur Arithmetik; bewegt wird unten
			if r.fast then
				if r.moved then
					r.moved = false
					r.inst:PivotTo(r.cframe(r))
				end
			elseif slowTick and r.moved then
				r.moved = false
				if r.isPart then
					-- einzelnes Part: Tween zur Position beim nächsten Takt (flüssig, ohne Lua pro Frame)
					r.tween = TweenService:Create(r.inst, TweenInfo.new(SLOW_INTERVAL, Enum.EasingStyle.Linear), { CFrame = r.cframe(r, r.speed * SLOW_INTERVAL) })
					r.tween:Play()
				else
					r.inst:PivotTo(r.cframe(r))
				end
			end
		end
	end
end

---------------------------------------------------------------- Schnittstelle
function CityClient.Start()
	if started then
		return
	end
	started = true
	whenChild(workspace, "City", function(city)
		whenChild(city, "Animated", function(animated)
			attach(animated)
			refreshActivity()
		end)
	end)
	local failures = 0
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok then
			failures += 1
			if failures <= 3 then
				warn("[CityClient] " .. tostring(err))
			end
		end
	end)
end

-- Eigener Klick in der PressUI: alle Pressen der Stadt stoßen kurz zu (lokal, höchstens alle 0,12 s neu)
function CityClient.Stomp()
	local t = os.clock()
	if t - lastStomp < 0.12 then
		return
	end
	lastStomp = t
	stompAt = t
end

-- Für Tests und Fehlersuche
function CityClient.Counts()
	local tweened, byKind, active, fast = 0, {}, 0, 0
	for _, v in pairs(records) do
		local kind = type(v) == "string" and v or v.kind
		byKind[kind] = (byKind[kind] or 0) + 1
		if type(v) == "string" and v ~= "traffic" then
			tweened += 1
		end
	end
	for _, r in ipairs(frameRecs) do
		if r.active then
			active += 1
		end
		if r.fast then
			fast += 1
		end
	end
	return { frame = #frameRecs, traffic = #trafficRecs, press = #pressRecs, tweened = tweened, kinds = byKind, active = active, fast = fast }
end

-- Datensatz eines animierten Objekts (Tests)
function CityClient.Record(inst)
	local r = records[inst]
	return type(r) == "table" and r or nil
end

return CityClient
