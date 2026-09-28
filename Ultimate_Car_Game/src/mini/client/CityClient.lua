-- CityClient: rein optische Animationen der Stadt, nur auf dem Client (nichts wird repliziert, nichts ist spielrelevant).
-- Animiert werden Parts oder Models unter Workspace.City.Animated mit dem Attribut Anim:
--   press      Presse: Stempel fährt periodisch herunter; eigene Klicks in der PressUI lösen einen zusätzlichen Stoß aus
--              (bewegt das Kind "Ram"/"Stempel"/"Head"/"Kolben", sonst das ganze Objekt). Attribute: Stroke (4), Period (2.6)
--   crane      Kran schwenkt um die Hochachse. Attribute: Swing (Grad, 50), Period (14)
--   turntable  Drehteller dreht sich. Attribute: Speed (Grad/s, 18)
--   door       Tor öffnet und schließt periodisch. Attribute: Lift (Studs, 90 % der Höhe), Period (10), Axis ("Y"|"X"|"Z")
--   fountain   Wasserstrahl pulsiert (Parts mit "Wasser"/"Water"/"Jet"/"Strahl" im Namen, sonst das Part selbst).
--              Attribute: Amplitude (Anteil, 0.35), Period (2)
--   neon       Leuchtreklame pulsiert (Farbe → ColorB, sonst Transparenz), Lichter dimmen mit. Attribute: Period (1.6), ColorB
--   dyno       Leistungsprüfstand: Rollen ("Roll"/"Rolle"/"Walze" im Namen) drehen, das Auto darauf vibriert.
--              Attribute: Speed (Grad/s, 720), Period (12)
--   traffic    Autos fahren eine Wegpunktliste ab. Wegpunkte: Vector3-Attribute WP1..WPn, String-Attribut Waypoints
--              ("x,y,z;x,y,z"), Kind-Parts WP1..WPn (auch im Kind-Ordner "Waypoints") oder Attribut Path = Name eines
--              Ordners/Models in City mit WP1..WPn. Attribute: Speed (Studs/s, 14), Loop (true; false = hin und zurück),
--              FacingOffset (Grad, 0; die LookVector des Pivots ist die Fahrtrichtung), HeightOffset (Studs; Standard:
--              Pivot-Höhe minus Höhe von WP1), Phase (0..1) bzw. StartOffset (Studs; Standard: Startposition des Autos).
--              Die Teile eines Verkehrsautos werden lokal CanCollide=false gesetzt (rein optisch).
--   flag       Fahne weht (Drehung um die Mastkante bzw. den Pivot). Attribute: Swing (Grad, 12), Period (3)
-- Kosten: höchstens 8 Autos (die nächsten zur Kamera) werden jedes Frame per PivotTo bewegt, alle anderen alle 0,25 s
-- (einzelne Parts per Tween). Neon, Fahnen und Fontänen laufen als endlose Tweens ohne Lua-Arbeit pro Frame.
-- Periodische Bewegungen richten sich nach der Serverzeit, damit alle Spieler dasselbe sehen.
-- Fehlt Workspace.City (oder Animated), wartet das Modul still, bis es erscheint.
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local CityClient = {}

local started = false
local records = {} -- [inst] = Datensatz
local frameRecs = {} -- Liste der pro Frame aktualisierten Datensätze (ohne Verkehr)
local trafficRecs = {} -- Verkehr
local pressRecs = {}
local stompAt = -math.huge
local lastStomp = -math.huge

local FAST_TRAFFIC = 8
local CULL = 700 -- Studs: weiter entfernte Animationen pausieren
local SLOW_INTERVAL = 0.25

CityClient.FastTraffic = FAST_TRAFFIC

---------------------------------------------------------------- Hilfen
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

---------------------------------------------------------------- Arten
local Kinds = {}

-- Presse: schnell herunter, kurz halten, langsam hoch; eigener Klick = zusätzlicher kurzer Stoß
function Kinds.press(inst)
	local mover = inst
	if inst:IsA("Model") then
		for _, c in ipairs(inst:GetChildren()) do
			if (c:IsA("BasePart") or c:IsA("Model")) and nameHas(c, { "ram", "stempel", "head", "kolben", "platte" }) then
				mover = c
				break
			end
		end
	end
	local rec = { inst = mover, base = mover:GetPivot(), stroke = num(inst, "Stroke", 4), period = num(inst, "Period", 2.6) }
	rec.update = function(r, t)
		local p = phaseOf(t, r.period)
		local f
		if p < 0.15 then
			f = (p / 0.15) ^ 2
		elseif p < 0.25 then
			f = 1
		else
			f = 1 - smooth((p - 0.25) / 0.75)
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
	local jets = {}
	for _, part in ipairs(baseParts(inst)) do
		if nameHas(part, { "wasser", "water", "jet", "strahl", "fontaene", "fontäne" }) then
			table.insert(jets, part)
		end
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

-- Leuchtreklame: Neon-Teile pulsieren (Farbe oder Transparenz), Lichter dimmen mit
function Kinds.neon(inst)
	local period = num(inst, "Period", 1.6)
	local colorB = inst:GetAttribute("ColorB")
	local parts = {}
	for _, part in ipairs(baseParts(inst)) do
		if part.Material == Enum.Material.Neon then
			table.insert(parts, part)
		end
	end
	if #parts == 0 then
		parts = baseParts(inst)
	end
	local delay = math.random() * period
	for _, part in ipairs(parts) do
		if typeof(colorB) == "Color3" then
			endless(part, period / 2, { Color = colorB }, delay)
		else
			endless(part, period / 2, { Transparency = math.min(1, part.Transparency + 0.45) }, delay)
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
		endless(light, period / 2, { Brightness = light.Brightness * 0.3 }, delay)
	end
	return nil
end

-- Leistungsprüfstand: Rollen drehen in Zyklen (hochfahren, halten, auslaufen), das Auto darauf vibriert
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
			if (c:IsA("Model") or c:IsA("BasePart")) and nameHas(c, { "car", "auto", "fahrzeug" }) then
				body = { inst = c, base = c:GetPivot() }
				break
			end
		end
		if #rollers == 0 and not body then
			body = { inst = inst, base = inst:GetPivot() }
		end
	end
	local rec = { inst = inst, base = inst:GetPivot(), speed = math.rad(num(inst, "Speed", 720)), period = num(inst, "Period", 12), angle = 0 }
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
			local shake = factor * 0.04
			body.inst:PivotTo(body.base * CFrame.new((math.random() - 0.5) * shake, (math.random() - 0.5) * shake, 0))
		end
	end
	return rec
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
	return { segs = segs, total = total, loop = loop }
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

function Kinds.traffic(inst)
	local points = waypointsFrom(inst)
	if #points < 2 then
		local folder = inst:FindFirstChild("Waypoints")
		points = waypointsFrom(folder)
	end
	if #points < 2 then
		points = waypointsFrom(findPath(inst:GetAttribute("Path")))
	end
	if #points < 2 then
		return nil
	end
	local loop = inst:GetAttribute("Loop") ~= false
	local path = buildPath(points, loop)
	if path.total <= 0 then
		return nil
	end
	-- rein optisch: lokal bewegte Autos sollen niemanden schieben oder einklemmen
	for _, part in ipairs(baseParts(inst)) do
		part.CanCollide = false
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
	local rec = {
		inst = inst, path = path, speed = math.max(0.1, num(inst, "Speed", 14)), offset = offset,
		height = num(inst, "HeightOffset", pivot.Position.Y - points[1].Y),
		facing = CFrame.Angles(0, math.rad(num(inst, "FacingOffset", 0)), 0),
		isPart = inst:IsA("BasePart"), base = pivot, lastDir = pivot.LookVector, fast = false,
	}
	rec.cframe = function(r, t)
		local L = r.path.total
		local u = r.offset + r.speed * t
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
local MOVING = { press = true, crane = true, turntable = true, door = true, fountain = true, dyno = true, traffic = true, flag = true }

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
		rec.active = true
		records[inst] = rec
		table.insert(frameRecs, rec)
	end
end

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

local function refreshActivity()
	local cam = camPos()
	if not cam then
		return
	end
	for i = #frameRecs, 1, -1 do
		local r = frameRecs[i]
		if not r.inst.Parent then
			table.remove(frameRecs, i)
		else
			r.active = (r.pos - cam).Magnitude < CULL
		end
	end
	-- die nächsten 8 Autos jedes Frame, die übrigen im langsamen Takt
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
		local fast = i <= FAST_TRAFFIC and r.dist < CULL
		if fast and not r.fast and r.tween then
			r.tween:Cancel()
			r.tween = nil
		end
		r.fast = fast
		r.active = r.dist < CULL * 1.5
	end
end

local function step(dt)
	local t = now()
	cullTimer += dt
	if cullTimer >= 0.5 then
		cullTimer = 0
		refreshActivity()
	end
	for _, r in ipairs(frameRecs) do
		if r.active and r.inst.Parent then
			r.update(r, t, dt)
		end
	end
	slowTimer += dt
	local slowTick = slowTimer >= SLOW_INTERVAL
	if slowTick then
		slowTimer = 0
	end
	for _, r in ipairs(trafficRecs) do
		if r.inst.Parent and r.active then
			if r.fast then
				r.inst:PivotTo(r.cframe(r, t))
			elseif slowTick then
				if r.isPart then
					-- einzelnes Part: Tween zur Position beim nächsten Takt (flüssig, ohne Lua pro Frame)
					r.tween = TweenService:Create(r.inst, TweenInfo.new(SLOW_INTERVAL, Enum.EasingStyle.Linear), { CFrame = r.cframe(r, t + SLOW_INTERVAL) })
					r.tween:Play()
				else
					r.inst:PivotTo(r.cframe(r, t))
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
	local tweened = 0
	for _, v in pairs(records) do
		if type(v) == "string" and v ~= "traffic" then
			tweened += 1
		end
	end
	return { frame = #frameRecs, traffic = #trafficRecs, press = #pressRecs, tweened = tweened }
end

return CityClient
