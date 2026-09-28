-- mock_roblox: Roblox-Nachbildung für automatisierte Tests mit dem Luau-Interpreter (tools/luaurun).
-- Bildet Instanzen (Klassenhierarchie, Standardwerte, Ereignisse), Signale, einen ereignisgenauen Scheduler
-- (task.*), Tweens, DataStores mit Fehlerinjektion, Dienste für Server und Client sowie die Roblox-Datentypen
-- nach. Jede Umgebung (Mock.NewEnv) hat eigenen Baum, eigene Modul-Caches (Server und je Client), eigene Uhr
-- und eigene Globals (Skripte laufen mit setfenv in env.G).
--
-- Server und Clients teilen sich EIN DataModel (keine Replikation): Clients laufen in einem eigenen Kontext
-- (Players.LocalPlayer, Modul-Cache, Remote-Empfang, Eingaben), sehen aber dieselben Instanzen wie der Server.
local Mock = {}
local realOs = os

---------------------------------------------------------------- Kontexte (Server / Client je Spieler)
-- Jede Coroutine erbt den Kontext ihres Erzeugers; Signal-Handler laufen im Kontext des Verbinders.
local ctxOf = setmetatable({}, { __mode = "k" })
local function currentCtx(env)
	local co = coroutine.running()
	local c = co and ctxOf[co]
	if c and c.env == env then
		return c
	end
	return env.mainCtx
end
Mock.CurrentContext = currentCtx

local function isInstance(v)
	return type(v) == "table" and rawget(v, "__data") ~= nil
end

---------------------------------------------------------------- Scheduler
local Scheduler = {}
Scheduler.__index = Scheduler
local FRAME = 1 / 60

function Scheduler.new(clock, env)
	-- heap: Binärheap nach (at, seq); entryOf: Coroutine -> aktiver Eintrag (Löschen per Markierung)
	return setmetatable({ clock = clock, heap = {}, entryOf = setmetatable({}, { __mode = "k" }), errors = {}, env = env, seq = 0 }, Scheduler)
end

local function before(a, b)
	if a.at == b.at then
		return a.seq < b.seq
	end
	return a.at < b.at
end

function Scheduler:push(entry)
	local heap = self.heap
	local i = #heap + 1
	heap[i] = entry
	while i > 1 do
		local parent = i // 2
		if before(heap[i], heap[parent]) then
			heap[i], heap[parent] = heap[parent], heap[i]
			i = parent
		else
			break
		end
	end
end

function Scheduler:pop()
	local heap = self.heap
	local n = #heap
	local top = heap[1]
	heap[1] = heap[n]
	heap[n] = nil
	n -= 1
	local i = 1
	while true do
		local l, r = i * 2, i * 2 + 1
		local smallest = i
		if l <= n and before(heap[l], heap[smallest]) then
			smallest = l
		end
		if r <= n and before(heap[r], heap[smallest]) then
			smallest = r
		end
		if smallest == i then
			break
		end
		heap[i], heap[smallest] = heap[smallest], heap[i]
		i = smallest
	end
	return top
end

-- Oberster gültiger Eintrag (markierte werden verworfen)
function Scheduler:peek()
	local heap = self.heap
	while heap[1] and heap[1].dead do
		self:pop()
	end
	return heap[1]
end

-- Kompatibilität: Liste der wartenden Einträge
function Scheduler:sleepingList()
	local out = {}
	for _, e in ipairs(self.heap) do
		if not e.dead then
			table.insert(out, e)
		end
	end
	return out
end

function Scheduler:resume(co, ...)
	if coroutine.status(co) ~= "suspended" then
		return
	end
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		local tb = debug.traceback(co)
		local msg = tostring(err)
		if tb and tb ~= "" then
			msg = msg .. "\n" .. tb
		end
		table.insert(self.errors, msg)
		if self.env and self.env.echoErrors then
			print("[Mock-Fehler] " .. msg)
		end
	end
end

function Scheduler:add(co, at, args)
	local old = self.entryOf[co]
	if old then
		old.dead = true
	end
	self.seq += 1
	local entry = { co = co, at = at, seq = self.seq, args = args }
	self.entryOf[co] = entry
	self:push(entry)
end

function Scheduler:remove(co)
	local e = self.entryOf[co]
	if e then
		e.dead = true
		self.entryOf[co] = nil
	end
end

-- Startet fn (oder setzt einen Thread fort) sofort im angegebenen Kontext
function Scheduler:spawnIn(ctx, fn, ...)
	local co
	if type(fn) == "thread" then
		co = fn
		self:remove(co)
	else
		co = coroutine.create(fn)
	end
	if ctx and ctxOf[co] == nil then
		ctxOf[co] = ctx
	end
	self:resume(co, ...)
	return co
end

function Scheduler:spawn(fn, ...)
	return self:spawnIn(self.env and currentCtx(self.env) or nil, fn, ...)
end

function Scheduler:wait(seconds)
	local co = coroutine.running()
	if not co or not coroutine.isyieldable() then
		-- Hauptthread (Testcode): kein Warten möglich, Zeit trotzdem vergehen lassen
		self.clock:Advance(seconds or 0)
		return seconds or 0
	end
	local start = self.clock.precise
	local d = seconds or 0
	if d ~= d or d < FRAME then
		d = FRAME -- wie Roblox: mindestens ein Frame
	end
	self:add(co, start + d)
	coroutine.yield()
	return self.clock.precise - start
end

-- Schläft höchstens `seconds`, kann über wake() früher geweckt werden; liefert die Weck-Argumente
function Scheduler:sleep(seconds)
	local co = coroutine.running()
	self:add(co, self.clock.precise + math.max(seconds, 0))
	return coroutine.yield()
end

-- Weckt eine schlafende Coroutine beim nächsten Durchlauf (gleiche Simulationszeit)
function Scheduler:wake(co, ...)
	self:add(co, self.clock.precise, table.pack(...))
end

function Scheduler:delay(seconds, fn, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		fn(table.unpack(args, 1, args.n))
	end)
	if self.env then
		ctxOf[co] = currentCtx(self.env)
	end
	local d = tonumber(seconds) or 0
	if d ~= d then
		d = 0
	end
	self:add(co, self.clock.precise + math.max(d, 0))
	return co
end

function Scheduler:cancel(co)
	self:remove(co)
	if type(co) == "thread" and coroutine.status(co) == "suspended" then
		pcall(coroutine.close, co)
	end
end

function Scheduler:nextDue()
	local top = self:peek()
	return top and top.at
end

-- Weckt alle fälligen Coroutinen (in Zeitreihenfolge, bei gleicher Zeit in Einfügereihenfolge)
function Scheduler:run()
	local guard = 0
	while true do
		local top = self:peek()
		if not top or top.at > self.clock.precise + 1e-9 then
			return
		end
		guard += 1
		if guard > 200000 then
			error("Scheduler: Endlosschleife (Coroutine wartet immer wieder 0 s?)")
		end
		self:pop()
		if self.entryOf[top.co] == top then
			self.entryOf[top.co] = nil
		end
		if top.args then
			self:resume(top.co, table.unpack(top.args, 1, top.args.n))
		else
			self:resume(top.co)
		end
	end
end

---------------------------------------------------------------- Uhr
local Clock = {}
Clock.__index = Clock

function Clock.new(startTime)
	local start = startTime or 1760000000
	return setmetatable({ wall = start, now = math.floor(start), precise = 1000, scheduler = nil, env = nil }, Clock)
end

function Clock:setPrecise(t)
	local dt = t - self.precise
	self.precise = t
	self.wall += dt
	self.now = math.floor(self.wall + 1e-9)
end

local updateTweens, nextTweenEnd, runFrame

-- Frames nur, wenn jemand sie braucht (RunService-Verbindungen, RenderStep, Tweens, Clients)
local FRAME_SIGNALS = { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation", "PreAnimation" }
local function frameWork(env)
	if #env.tweens > 0 or next(env.clients) or next(env.renderSteps) then
		return true
	end
	local rs = env.services and env.services.RunService
	if rs then
		local sigs = rawget(rs, "__data")._signals
		for _, name in ipairs(FRAME_SIGNALS) do
			local sig = sigs[name]
			if sig and #sig.handlers > 0 then
				return true
			end
		end
	end
	return false
end

-- Lässt Zeit vergehen. Fällige Aufgaben laufen genau zu ihrer Zeit; Frames (RunService, Tweens,
-- Prompt-Sichtbarkeit) alle env.frameStep Sekunden.
function Clock:Advance(seconds)
	local env = self.env
	local sched = self.scheduler
	local target = self.precise + math.max(seconds or 0, 0)
	if sched then
		sched:run()
	end
	local guard = 0
	while true do
		guard += 1
		if guard > 10000000 then
			error("Uhr: Endlosschleife")
		end
		local nextT = target
		local frames = env and frameWork(env)
		if env and not frames then
			-- ohne Frame-Arbeit springt die Uhr direkt zur nächsten fälligen Aufgabe
			env.nextFrame = nil
		elseif env and not env.nextFrame then
			env.nextFrame = self.precise + env.frameStep
		end
		if env then
			if env.nextFrame and env.nextFrame < nextT then
				nextT = env.nextFrame
			end
			local tw = nextTweenEnd(env)
			if tw and tw < nextT then
				nextT = tw
			end
		end
		if sched then
			local d = sched:nextDue()
			if d and d < nextT then
				nextT = d
			end
		end
		if nextT > self.precise then
			self:setPrecise(nextT)
		end
		if env then
			updateTweens(env)
			if env.nextFrame and self.precise >= env.nextFrame - 1e-9 then
				local dt = env.frameStep
				env.nextFrame += env.frameStep
				if env.nextFrame < self.precise then
					env.nextFrame = self.precise + env.frameStep
				end
				runFrame(env, dt)
			end
		end
		if sched then
			sched:run()
		end
		if self.precise >= target - 1e-9 then
			return
		end
	end
end

-- Springt die Wandzeit (os.time) ohne Zwischen-Ticks, z. B. für Offline-Tests
function Clock:Jump(seconds)
	self.wall += seconds
	self.now = math.floor(self.wall + 1e-9)
end

---------------------------------------------------------------- Datentypen
local function fmtNum(n)
	if n == math.floor(n) and math.abs(n) < 1e15 then
		return tostring(math.floor(n))
	end
	return string.format("%.6g", n)
end

-- Vector3
local Vector3 = {}
local V3Meta = { __type = "Vector3" }
local function v3(x, y, z)
	return setmetatable({ X = x, Y = y, Z = z, __type = "Vector3" }, V3Meta)
end
function Vector3.new(x, y, z)
	return v3(x or 0, y or 0, z or 0)
end
V3Meta.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		if m == 0 then
			return v3(0 / 0, 0 / 0, 0 / 0)
		end
		return v3(v.X / m, v.Y / m, v.Z / m)
	elseif k == "x" then
		return v.X
	elseif k == "y" then
		return v.Y
	elseif k == "z" then
		return v.Z
	end
	return Vector3[k]
end
V3Meta.__add = function(a, b)
	return v3(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
V3Meta.__sub = function(a, b)
	return v3(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
V3Meta.__mul = function(a, b)
	if type(a) == "number" then
		return v3(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return v3(a.X * b, a.Y * b, a.Z * b)
	end
	return v3(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
V3Meta.__div = function(a, b)
	if type(a) == "number" then
		return v3(a / b.X, a / b.Y, a / b.Z)
	elseif type(b) == "number" then
		return v3(a.X / b, a.Y / b, a.Z / b)
	end
	return v3(a.X / b.X, a.Y / b.Y, a.Z / b.Z)
end
V3Meta.__idiv = function(a, b)
	if type(b) == "number" then
		return v3(a.X // b, a.Y // b, a.Z // b)
	end
	return v3(a.X // b.X, a.Y // b.Y, a.Z // b.Z)
end
V3Meta.__unm = function(a)
	return v3(-a.X, -a.Y, -a.Z)
end
V3Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y and a.Z == b.Z
end
V3Meta.__tostring = function(v)
	return fmtNum(v.X) .. ", " .. fmtNum(v.Y) .. ", " .. fmtNum(v.Z)
end
function Vector3.Dot(a, b)
	return a.X * b.X + a.Y * b.Y + a.Z * b.Z
end
function Vector3.Cross(a, b)
	return v3(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end
function Vector3.Lerp(a, b, t)
	return v3(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t)
end
function Vector3.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps and math.abs(a.Z - b.Z) <= eps
end
function Vector3.Abs(a)
	return v3(math.abs(a.X), math.abs(a.Y), math.abs(a.Z))
end
function Vector3.Floor(a)
	return v3(math.floor(a.X), math.floor(a.Y), math.floor(a.Z))
end
function Vector3.Ceil(a)
	return v3(math.ceil(a.X), math.ceil(a.Y), math.ceil(a.Z))
end
function Vector3.Sign(a)
	return v3(math.sign(a.X), math.sign(a.Y), math.sign(a.Z))
end
function Vector3.Min(a, b)
	return v3(math.min(a.X, b.X), math.min(a.Y, b.Y), math.min(a.Z, b.Z))
end
function Vector3.Max(a, b)
	return v3(math.max(a.X, b.X), math.max(a.Y, b.Y), math.max(a.Z, b.Z))
end
function Vector3.Angle(a, b)
	local d = Vector3.Dot(a, b) / (a.Magnitude * b.Magnitude)
	return math.acos(math.clamp(d, -1, 1))
end
function Vector3.fromNormalId(id)
	local n = id.Name
	return ({ Right = v3(1, 0, 0), Left = v3(-1, 0, 0), Top = v3(0, 1, 0), Bottom = v3(0, -1, 0), Back = v3(0, 0, 1), Front = v3(0, 0, -1) })[n]
end
Vector3.zero = v3(0, 0, 0)
Vector3.one = v3(1, 1, 1)
Vector3.xAxis = v3(1, 0, 0)
Vector3.yAxis = v3(0, 1, 0)
Vector3.zAxis = v3(0, 0, 1)

-- Vector2
local Vector2 = {}
local V2Meta = {}
local function v2(x, y)
	return setmetatable({ X = x, Y = y, __type = "Vector2" }, V2Meta)
end
function Vector2.new(x, y)
	return v2(x or 0, y or 0)
end
V2Meta.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y)
		return v2(v.X / m, v.Y / m)
	elseif k == "x" then
		return v.X
	elseif k == "y" then
		return v.Y
	end
	return Vector2[k]
end
V2Meta.__add = function(a, b)
	return v2(a.X + b.X, a.Y + b.Y)
end
V2Meta.__sub = function(a, b)
	return v2(a.X - b.X, a.Y - b.Y)
end
V2Meta.__mul = function(a, b)
	if type(a) == "number" then
		return v2(b.X * a, b.Y * a)
	elseif type(b) == "number" then
		return v2(a.X * b, a.Y * b)
	end
	return v2(a.X * b.X, a.Y * b.Y)
end
V2Meta.__div = function(a, b)
	if type(b) == "number" then
		return v2(a.X / b, a.Y / b)
	end
	return v2(a.X / b.X, a.Y / b.Y)
end
V2Meta.__unm = function(a)
	return v2(-a.X, -a.Y)
end
V2Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
V2Meta.__tostring = function(v)
	return fmtNum(v.X) .. ", " .. fmtNum(v.Y)
end
function Vector2.Dot(a, b)
	return a.X * b.X + a.Y * b.Y
end
function Vector2.Cross(a, b)
	return a.X * b.Y - a.Y * b.X
end
function Vector2.Lerp(a, b, t)
	return v2(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t)
end
function Vector2.Min(a, b)
	return v2(math.min(a.X, b.X), math.min(a.Y, b.Y))
end
function Vector2.Max(a, b)
	return v2(math.max(a.X, b.X), math.max(a.Y, b.Y))
end
function Vector2.Abs(a)
	return v2(math.abs(a.X), math.abs(a.Y))
end
function Vector2.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	return math.abs(a.X - b.X) <= eps and math.abs(a.Y - b.Y) <= eps
end
Vector2.zero = v2(0, 0)
Vector2.one = v2(1, 1)
Vector2.xAxis = v2(1, 0)
Vector2.yAxis = v2(0, 1)

-- CFrame: _m = {x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22}
local CFrame = {}
local CFMeta = {}
local function cf(x, y, z, a, b, c, d, e, f, g, h, i)
	return setmetatable({ _m = { x, y, z, a, b, c, d, e, f, g, h, i }, __type = "CFrame" }, CFMeta)
end
local function orthonormal(ax, ay, az, bx, by, bz)
	-- x-Achse a, y-Achse b (b wird orthogonalisiert), z = a × b
	local la = math.sqrt(ax * ax + ay * ay + az * az)
	ax, ay, az = ax / la, ay / la, az / la
	local dot = ax * bx + ay * by + az * bz
	bx, by, bz = bx - ax * dot, by - ay * dot, bz - az * dot
	local lb = math.sqrt(bx * bx + by * by + bz * bz)
	bx, by, bz = bx / lb, by / lb, bz / lb
	local cx, cy, cz = ay * bz - az * by, az * bx - ax * bz, ax * by - ay * bx
	return ax, ay, az, bx, by, bz, cx, cy, cz
end
local function fromQuat(x, y, z, qx, qy, qz, qw)
	local n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw)
	if n == 0 then
		return cf(x, y, z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	qx, qy, qz, qw = qx / n, qy / n, qz / n, qw / n
	return cf(
		x, y, z,
		1 - 2 * (qy * qy + qz * qz), 2 * (qx * qy - qz * qw), 2 * (qx * qz + qy * qw),
		2 * (qx * qy + qz * qw), 1 - 2 * (qx * qx + qz * qz), 2 * (qy * qz - qx * qw),
		2 * (qx * qz - qy * qw), 2 * (qy * qz + qx * qw), 1 - 2 * (qx * qx + qy * qy)
	)
end
local function toQuat(m)
	local m00, m01, m02, m10, m11, m12, m20, m21, m22 = m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12]
	local tr = m00 + m11 + m22
	local qx, qy, qz, qw
	if tr > 0 then
		local s = math.sqrt(tr + 1) * 2
		qw = 0.25 * s
		qx = (m21 - m12) / s
		qy = (m02 - m20) / s
		qz = (m10 - m01) / s
	elseif m00 > m11 and m00 > m22 then
		local s = math.sqrt(1 + m00 - m11 - m22) * 2
		qw = (m21 - m12) / s
		qx = 0.25 * s
		qy = (m01 + m10) / s
		qz = (m02 + m20) / s
	elseif m11 > m22 then
		local s = math.sqrt(1 + m11 - m00 - m22) * 2
		qw = (m02 - m20) / s
		qx = (m01 + m10) / s
		qy = 0.25 * s
		qz = (m12 + m21) / s
	else
		local s = math.sqrt(1 + m22 - m00 - m11) * 2
		qw = (m10 - m01) / s
		qx = (m02 + m20) / s
		qy = (m12 + m21) / s
		qz = 0.25 * s
	end
	return qx, qy, qz, qw
end
function CFrame.new(...)
	local n = select("#", ...)
	local a = { ... }
	if n == 0 then
		return cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if type(a[1]) == "table" then
		local p = a[1]
		if n >= 2 and type(a[2]) == "table" then
			return CFrame.lookAt(p, a[2])
		end
		return cf(p.X, p.Y, p.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	if n >= 12 then
		return cf(a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
	elseif n >= 7 then
		return fromQuat(a[1], a[2], a[3], a[4], a[5], a[6], a[7])
	end
	return cf(a[1] or 0, a[2] or 0, a[3] or 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
end
local function mulRot(a, b)
	-- 3x3 a (row-major in _m[4..12]) * b
	local A, B = a, b
	local out = {}
	for i = 0, 2 do
		for j = 0, 2 do
			out[i * 3 + j + 1] = A[4 + i * 3] * B[4 + j] + A[5 + i * 3] * B[7 + j] + A[6 + i * 3] * B[10 + j]
		end
	end
	return out
end
local function mulCF(a, b)
	local A, B = a._m, b._m
	local r = mulRot(A, B)
	local x = A[4] * B[1] + A[5] * B[2] + A[6] * B[3] + A[1]
	local y = A[7] * B[1] + A[8] * B[2] + A[9] * B[3] + A[2]
	local z = A[10] * B[1] + A[11] * B[2] + A[12] * B[3] + A[3]
	return cf(x, y, z, r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9])
end
local function rotX(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, 1, 0, 0, 0, c, -s, 0, s, c)
end
local function rotY(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, c, 0, s, 0, 1, 0, -s, 0, c)
end
local function rotZ(t)
	local c, s = math.cos(t), math.sin(t)
	return cf(0, 0, 0, c, -s, 0, s, c, 0, 0, 0, 1)
end
function CFrame.Angles(rx, ry, rz)
	return mulCF(mulCF(rotX(rx or 0), rotY(ry or 0)), rotZ(rz or 0))
end
CFrame.fromEulerAnglesXYZ = CFrame.Angles
function CFrame.fromEulerAnglesYXZ(rx, ry, rz)
	return mulCF(mulCF(rotY(ry or 0), rotX(rx or 0)), rotZ(rz or 0))
end
CFrame.fromOrientation = CFrame.fromEulerAnglesYXZ
function CFrame.fromEulerAngles(rx, ry, rz, order)
	return CFrame.Angles(rx, ry, rz)
end
function CFrame.fromAxisAngle(axis, angle)
	local u = axis.Unit
	local s = math.sin(angle / 2)
	return fromQuat(0, 0, 0, u.X * s, u.Y * s, u.Z * s, math.cos(angle / 2))
end
function CFrame.lookAt(pos, target, up)
	up = up or v3(0, 1, 0)
	local look = (target - pos)
	if look.Magnitude < 1e-12 then
		return cf(pos.X, pos.Y, pos.Z, 1, 0, 0, 0, 1, 0, 0, 0, 1)
	end
	look = look.Unit
	local right = look:Cross(up)
	if right.Magnitude < 1e-9 then
		right = look:Cross(v3(0, 0, 1))
	end
	right = right.Unit
	local up2 = right:Cross(look)
	return cf(pos.X, pos.Y, pos.Z, right.X, up2.X, -look.X, right.Y, up2.Y, -look.Y, right.Z, up2.Z, -look.Z)
end
function CFrame.lookAlong(pos, dir, up)
	return CFrame.lookAt(pos, pos + dir, up)
end
function CFrame.fromMatrix(pos, vx, vy, vz)
	vz = vz or vx:Cross(vy)
	return cf(pos.X, pos.Y, pos.Z, vx.X, vy.X, vz.X, vx.Y, vy.Y, vz.Y, vx.Z, vy.Z, vz.Z)
end
CFrame.identity = cf(0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1)
function CFrame.Inverse(c)
	local m = c._m
	-- Rotation ist orthonormal: Inverse = Transponierte
	local r00, r01, r02 = m[4], m[7], m[10]
	local r10, r11, r12 = m[5], m[8], m[11]
	local r20, r21, r22 = m[6], m[9], m[12]
	local x, y, z = m[1], m[2], m[3]
	return cf(
		-(r00 * x + r01 * y + r02 * z), -(r10 * x + r11 * y + r12 * z), -(r20 * x + r21 * y + r22 * z),
		r00, r01, r02, r10, r11, r12, r20, r21, r22
	)
end
function CFrame.ToWorldSpace(a, b)
	return mulCF(a, b)
end
function CFrame.ToObjectSpace(a, b)
	return mulCF(CFrame.Inverse(a), b)
end
function CFrame.PointToWorldSpace(c, v)
	return c * v
end
function CFrame.PointToObjectSpace(c, v)
	return CFrame.Inverse(c) * v
end
function CFrame.VectorToWorldSpace(c, v)
	local m = c._m
	return v3(m[4] * v.X + m[5] * v.Y + m[6] * v.Z, m[7] * v.X + m[8] * v.Y + m[9] * v.Z, m[10] * v.X + m[11] * v.Y + m[12] * v.Z)
end
function CFrame.VectorToObjectSpace(c, v)
	local m = c._m
	return v3(m[4] * v.X + m[7] * v.Y + m[10] * v.Z, m[5] * v.X + m[8] * v.Y + m[11] * v.Z, m[6] * v.X + m[9] * v.Y + m[12] * v.Z)
end
function CFrame.GetComponents(c)
	return table.unpack(c._m, 1, 12)
end
CFrame.components = CFrame.GetComponents
function CFrame.ToEulerAnglesXYZ(c)
	local m = c._m
	local ry = math.asin(math.clamp(m[6], -1, 1))
	local rx, rz
	if math.abs(m[6]) < 0.9999999 then
		rx = math.atan2(-m[9], m[12])
		rz = math.atan2(-m[5], m[4])
	else
		rx = math.atan2(m[11], m[8])
		rz = 0
	end
	return rx, ry, rz
end
function CFrame.ToEulerAnglesYXZ(c)
	local m = c._m
	local rx = math.asin(math.clamp(-m[9], -1, 1))
	local ry, rz
	if math.abs(m[9]) < 0.9999999 then
		ry = math.atan2(m[6], m[12])
		rz = math.atan2(m[7], m[8])
	else
		ry = math.atan2(-m[10], m[4])
		rz = 0
	end
	return rx, ry, rz
end
CFrame.ToOrientation = CFrame.ToEulerAnglesYXZ
function CFrame.ToAxisAngle(c)
	local qx, qy, qz, qw = toQuat(c._m)
	local angle = 2 * math.acos(math.clamp(qw, -1, 1))
	local s = math.sqrt(math.max(0, 1 - qw * qw))
	if s < 1e-9 then
		return v3(1, 0, 0), 0
	end
	return v3(qx / s, qy / s, qz / s), angle
end
function CFrame.Lerp(a, b, t)
	local A, B = a._m, b._m
	local ax, ay, az, aw = toQuat(A)
	local bx, by, bz, bw = toQuat(B)
	local dot = ax * bx + ay * by + az * bz + aw * bw
	if dot < 0 then
		bx, by, bz, bw, dot = -bx, -by, -bz, -bw, -dot
	end
	local qx, qy, qz, qw
	if dot > 0.9995 then
		qx, qy, qz, qw = ax + (bx - ax) * t, ay + (by - ay) * t, az + (bz - az) * t, aw + (bw - aw) * t
	else
		local th = math.acos(dot)
		local s = math.sin(th)
		local wa, wb = math.sin((1 - t) * th) / s, math.sin(t * th) / s
		qx, qy, qz, qw = ax * wa + bx * wb, ay * wa + by * wb, az * wa + bz * wb, aw * wa + bw * wb
	end
	return fromQuat(A[1] + (B[1] - A[1]) * t, A[2] + (B[2] - A[2]) * t, A[3] + (B[3] - A[3]) * t, qx, qy, qz, qw)
end
function CFrame.Orthonormalize(c)
	local m = c._m
	local ax, ay, az, bx, by, bz, cx, cy, cz = orthonormal(m[4], m[7], m[10], m[5], m[8], m[11])
	return cf(m[1], m[2], m[3], ax, bx, cx, ay, by, cy, az, bz, cz)
end
function CFrame.FuzzyEq(a, b, eps)
	eps = eps or 1e-5
	for i = 1, 12 do
		if math.abs(a._m[i] - b._m[i]) > eps then
			return false
		end
	end
	return true
end
CFMeta.__index = function(c, k)
	local m = c._m
	if k == "Position" or k == "p" then
		return v3(m[1], m[2], m[3])
	elseif k == "X" then
		return m[1]
	elseif k == "Y" then
		return m[2]
	elseif k == "Z" then
		return m[3]
	elseif k == "LookVector" then
		return v3(-m[6], -m[9], -m[12])
	elseif k == "RightVector" or k == "XVector" then
		return v3(m[4], m[7], m[10])
	elseif k == "UpVector" or k == "YVector" then
		return v3(m[5], m[8], m[11])
	elseif k == "ZVector" then
		return v3(m[6], m[9], m[12])
	elseif k == "Rotation" then
		return cf(0, 0, 0, m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12])
	end
	return CFrame[k]
end
CFMeta.__mul = function(a, b)
	if getmetatable(b) == V3Meta then
		local m = a._m
		return v3(
			m[4] * b.X + m[5] * b.Y + m[6] * b.Z + m[1],
			m[7] * b.X + m[8] * b.Y + m[9] * b.Z + m[2],
			m[10] * b.X + m[11] * b.Y + m[12] * b.Z + m[3]
		)
	end
	return mulCF(a, b)
end
CFMeta.__add = function(a, b)
	local m = a._m
	return cf(m[1] + b.X, m[2] + b.Y, m[3] + b.Z, m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12])
end
CFMeta.__sub = function(a, b)
	local m = a._m
	return cf(m[1] - b.X, m[2] - b.Y, m[3] - b.Z, m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12])
end
CFMeta.__eq = function(a, b)
	for i = 1, 12 do
		if a._m[i] ~= b._m[i] then
			return false
		end
	end
	return true
end
CFMeta.__tostring = function(c)
	local parts = {}
	for i = 1, 12 do
		parts[i] = fmtNum(c._m[i])
	end
	return table.concat(parts, ", ")
end

-- Color3
local Color3 = {}
local C3Meta = {}
local function c3(r, g, b)
	return setmetatable({ R = r, G = g, B = b, __type = "Color3" }, C3Meta)
end
C3Meta.__index = Color3
C3Meta.__eq = function(a, b)
	return a.R == b.R and a.G == b.G and a.B == b.B
end
C3Meta.__tostring = function(c)
	return fmtNum(c.R) .. ", " .. fmtNum(c.G) .. ", " .. fmtNum(c.B)
end
function Color3.new(r, g, b)
	return c3(r or 0, g or 0, b or 0)
end
function Color3.fromRGB(r, g, b)
	return c3((r or 0) / 255, (g or 0) / 255, (b or 0) / 255)
end
function Color3.fromHSV(h, s, v)
	local i = math.floor(h * 6)
	local f = h * 6 - i
	local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
	i = i % 6
	if i == 0 then
		return c3(v, t, p)
	elseif i == 1 then
		return c3(q, v, p)
	elseif i == 2 then
		return c3(p, v, t)
	elseif i == 3 then
		return c3(p, q, v)
	elseif i == 4 then
		return c3(t, p, v)
	end
	return c3(v, p, q)
end
function Color3.fromHex(hex)
	hex = hex:gsub("#", "")
	return Color3.fromRGB(tonumber(hex:sub(1, 2), 16), tonumber(hex:sub(3, 4), 16), tonumber(hex:sub(5, 6), 16))
end
function Color3.Lerp(a, b, t)
	return c3(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end
function Color3.ToHSV(c)
	local r, g, b = c.R, c.G, c.B
	local mx, mn = math.max(r, g, b), math.min(r, g, b)
	local d = mx - mn
	local h = 0
	if d > 0 then
		if mx == r then
			h = ((g - b) / d) % 6
		elseif mx == g then
			h = (b - r) / d + 2
		else
			h = (r - g) / d + 4
		end
		h = h / 6
	end
	return h, mx == 0 and 0 or d / mx, mx
end
function Color3.ToHex(c)
	return string.format("%02X%02X%02X", math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5))
end

-- UDim / UDim2
local UDim, UDim2 = {}, {}
local UDimMeta, UDim2Meta = {}, {}
local function udim(s, o)
	return setmetatable({ Scale = s or 0, Offset = o or 0, __type = "UDim" }, UDimMeta)
end
UDimMeta.__index = UDim
UDimMeta.__add = function(a, b)
	return udim(a.Scale + b.Scale, a.Offset + b.Offset)
end
UDimMeta.__sub = function(a, b)
	return udim(a.Scale - b.Scale, a.Offset - b.Offset)
end
UDimMeta.__eq = function(a, b)
	return a.Scale == b.Scale and a.Offset == b.Offset
end
UDimMeta.__tostring = function(u)
	return fmtNum(u.Scale) .. ", " .. fmtNum(u.Offset)
end
function UDim.new(s, o)
	return udim(s, o)
end
local function udim2(xs, xo, ys, yo)
	return setmetatable({ X = udim(xs, xo), Y = udim(ys, yo), __type = "UDim2" }, UDim2Meta)
end
UDim2Meta.__index = function(u, k)
	if k == "Width" then
		return u.X
	elseif k == "Height" then
		return u.Y
	end
	return UDim2[k]
end
UDim2Meta.__add = function(a, b)
	return udim2(a.X.Scale + b.X.Scale, a.X.Offset + b.X.Offset, a.Y.Scale + b.Y.Scale, a.Y.Offset + b.Y.Offset)
end
UDim2Meta.__sub = function(a, b)
	return udim2(a.X.Scale - b.X.Scale, a.X.Offset - b.X.Offset, a.Y.Scale - b.Y.Scale, a.Y.Offset - b.Y.Offset)
end
UDim2Meta.__eq = function(a, b)
	return a.X == b.X and a.Y == b.Y
end
UDim2Meta.__tostring = function(u)
	return "{" .. tostring(u.X) .. "}, {" .. tostring(u.Y) .. "}"
end
function UDim2.new(xs, xo, ys, yo)
	if type(xs) == "table" then
		return udim2(xs.Scale, xs.Offset, xo.Scale, xo.Offset)
	end
	return udim2(xs or 0, xo or 0, ys or 0, yo or 0)
end
function UDim2.fromScale(x, y)
	return udim2(x or 0, 0, y or 0, 0)
end
function UDim2.fromOffset(x, y)
	return udim2(0, x or 0, 0, y or 0)
end
function UDim2.Lerp(a, b, t)
	return udim2(
		a.X.Scale + (b.X.Scale - a.X.Scale) * t, a.X.Offset + (b.X.Offset - a.X.Offset) * t,
		a.Y.Scale + (b.Y.Scale - a.Y.Scale) * t, a.Y.Offset + (b.Y.Offset - a.Y.Offset) * t
	)
end

local function plain(typeName, fields)
	fields.__type = typeName
	return fields
end

-- TweenInfo
local TweenInfo = {}
function TweenInfo.new(time, style, direction, repeatCount, reverses, delayTime)
	return plain("TweenInfo", {
		Time = time or 1,
		EasingStyle = style,
		EasingDirection = direction,
		RepeatCount = repeatCount or 0,
		Reverses = reverses == true,
		DelayTime = delayTime or 0,
		args = { time, style, direction, repeatCount, reverses, delayTime },
	})
end

-- Weitere Datentypen
local NumberRange = {
	new = function(a, b)
		return plain("NumberRange", { Min = a, Max = b or a })
	end,
}
local NumberSequenceKeypoint = {
	new = function(t, v, e)
		return plain("NumberSequenceKeypoint", { Time = t, Value = v, Envelope = e or 0 })
	end,
}
local NumberSequence = {
	new = function(a, b)
		local kp
		if type(a) == "table" then
			kp = a
		else
			kp = { NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b or a) }
		end
		return plain("NumberSequence", { Keypoints = kp })
	end,
}
local ColorSequenceKeypoint = {
	new = function(t, c)
		return plain("ColorSequenceKeypoint", { Time = t, Value = c })
	end,
}
local ColorSequence = {
	new = function(a, b)
		local kp
		if type(a) == "table" and rawget(a, "__type") ~= "Color3" then
			kp = a
		else
			kp = { ColorSequenceKeypoint.new(0, a), ColorSequenceKeypoint.new(1, b or a) }
		end
		return plain("ColorSequence", { Keypoints = kp })
	end,
}
local Rect = {
	new = function(a, b, c, d)
		local mn, mx
		if type(a) == "table" then
			mn, mx = a, b
		else
			mn, mx = v2(a or 0, b or 0), v2(c or 0, d or 0)
		end
		return plain("Rect", { Min = mn, Max = mx, Width = mx.X - mn.X, Height = mx.Y - mn.Y })
	end,
}
local Ray = {
	new = function(o, d)
		return plain("Ray", { Origin = o, Direction = d, Unit = nil })
	end,
}
local BRICK = { [194] = { "Medium stone grey", 163, 162, 165 }, [1] = { "White", 242, 243, 243 }, [26] = { "Black", 27, 42, 53 } }
local BrickColor = {}
function BrickColor.new(v)
	local entry = BRICK[v] or BRICK[194]
	return plain("BrickColor", { Number = type(v) == "number" and v or 194, Name = type(v) == "string" and v or entry[1], Color = Color3.fromRGB(entry[2], entry[3], entry[4]) })
end
BrickColor.random = function()
	return BrickColor.new(194)
end
local PhysicalProperties = {
	new = function(d, f, e, fw, ew)
		return plain("PhysicalProperties", { Density = d, Friction = f, Elasticity = e, FrictionWeight = fw, ElasticityWeight = ew })
	end,
}
local Font = {}
function Font.new(family, weight, style)
	return plain("Font", { Family = family, Weight = weight, Style = style })
end
function Font.fromEnum(e)
	return plain("Font", { Family = "rbxasset://fonts/families/" .. tostring(e and e.Name) .. ".json" })
end
function Font.fromName(name, weight, style)
	return Font.new("rbxasset://fonts/families/" .. name .. ".json", weight, style)
end
local RaycastParams = {
	new = function()
		return plain("RaycastParams", { FilterDescendantsInstances = {}, IgnoreWater = false })
	end,
}
local OverlapParams = {
	new = function()
		return plain("OverlapParams", { FilterDescendantsInstances = {}, MaxParts = 0 })
	end,
}

-- Enum: Enum.Material.Grass -> eindeutiges Token (Identität bleibt über den ganzen Lauf gleich)
local ENUM_VALUES = {
	PlaybackState = { Begin = 0, Delayed = 1, Playing = 2, Paused = 3, Completed = 4, Cancelled = 5 },
	UserInputState = { Begin = 0, Change = 1, End = 2, Cancel = 3, None = 4 },
	UserInputType = { MouseButton1 = 0, MouseButton2 = 1, MouseButton3 = 2, MouseWheel = 3, MouseMovement = 4, Touch = 7, Keyboard = 8, Focus = 9, Gamepad1 = 12, TextInput = 20, None = 25 },
	ContextActionResult = { Sink = 0, Pass = 1 },
	ProductPurchaseDecision = { NotProcessedYet = 0, PurchaseGranted = 1 },
	KeyCode = { Unknown = 0, Backspace = 8, Tab = 9, Return = 13, Escape = 27, Space = 32, Zero = 48, One = 49, Two = 50, Three = 51, Four = 52, Five = 53, Six = 54, Seven = 55, Eight = 56, Nine = 57, ButtonX = 1000, ButtonY = 1001, ButtonA = 1002, ButtonB = 1003 },
	Material = { Plastic = 256, SmoothPlastic = 272, Neon = 288, Wood = 512, Concrete = 816, DiamondPlate = 1056, Metal = 1088, Grass = 1280, Asphalt = 1376, Glass = 1568 },
	NormalId = { Right = 0, Top = 1, Back = 2, Left = 3, Bottom = 4, Front = 5 },
	PartType = { Ball = 0, Block = 1, Cylinder = 2, Wedge = 3, CornerWedge = 4 },
	HumanoidStateType = { FallingDown = 0, Running = 8, RunningNoPhysics = 10, Climbing = 12, StrafingNoPhysics = 11, Ragdoll = 1, GettingUp = 2, Jumping = 3, Landed = 7, Flying = 6, Freefall = 5, Seated = 13, PlatformStanding = 14, Dead = 15, Swimming = 4, Physics = 16, None = 18 },
}
for c = 0, 25 do
	ENUM_VALUES.KeyCode[string.char(65 + c)] = 97 + c
end
local enumCache = {}
local EnumItemMeta = {
	__tostring = function(e)
		return "Enum." .. e.EnumType .. "." .. e.Name
	end,
	__index = {
		IsA = function(e, name)
			return e.EnumType == name
		end,
	},
}
local function enumType(typeName)
	local t = enumCache[typeName]
	if t then
		return t
	end
	t = setmetatable({}, {
		__index = function(tbl, name)
			if name == "GetEnumItems" then
				return function()
					local out = {}
					for n in pairs(ENUM_VALUES[typeName] or {}) do
						table.insert(out, tbl[n])
					end
					table.sort(out, function(a, b)
						return (a.Value or 0) < (b.Value or 0)
					end)
					return out
				end
			elseif name == "FromValue" or name == "FromName" then
				return function(_, x)
					if name == "FromName" then
						return tbl[x]
					end
					return Mock.EnumFromValue(typeName, x)
				end
			end
			local token = setmetatable({ EnumType = typeName, Name = name, Value = ENUM_VALUES[typeName] and ENUM_VALUES[typeName][name], __type = "EnumItem" }, EnumItemMeta)
			rawset(tbl, name, token)
			return token
		end,
		__tostring = function()
			return typeName
		end,
	})
	enumCache[typeName] = t
	return t
end
local Enum = setmetatable({}, {
	__index = function(_, typeName)
		return enumType(typeName)
	end,
})
function Mock.EnumFromValue(typeName, value)
	for name, v in pairs(ENUM_VALUES[typeName] or {}) do
		if v == value then
			return enumType(typeName)[name]
		end
	end
	local token = enumType(typeName)["Unknown" .. tostring(value)]
	rawset(token, "Value", value)
	return token
end

-- Random mit Roblox-Schnittstelle (deterministisch pro Seed)
local Random = {}
Random.__index = Random
local seedCounter = 12345
function Random.new(seed)
	seedCounter += 7919
	local s = math.floor(math.abs(seed or seedCounter)) % 2147483647
	if s == 0 then
		s = 1
	end
	return setmetatable({ state = s, __type = "Random" }, Random)
end
function Random:NextNumber(a, b)
	self.state = (self.state * 48271) % 2147483647
	local f = self.state / 2147483647
	if a then
		return a + f * (b - a)
	end
	return f
end
function Random:NextInteger(a, b)
	return a + math.floor(self:NextNumber() * (b - a + 1))
end
function Random:NextUnitVector()
	local z = self:NextNumber(-1, 1)
	local t = self:NextNumber(0, 2 * math.pi)
	local r = math.sqrt(1 - z * z)
	return v3(r * math.cos(t), r * math.sin(t), z)
end
function Random:Shuffle(t)
	for i = #t, 2, -1 do
		local j = self:NextInteger(1, i)
		t[i], t[j] = t[j], t[i]
	end
end
function Random:Clone()
	return setmetatable({ state = self.state, __type = "Random" }, Random)
end

-- Interpolation für Tweens
local function lerpValue(a, b, t)
	local ta = type(a)
	if ta == "number" and type(b) == "number" then
		return a + (b - a) * t
	end
	if ta == "table" and type(b) == "table" then
		local mt = getmetatable(a)
		if mt == V3Meta then
			return Vector3.Lerp(a, b, t)
		elseif mt == V2Meta then
			return Vector2.Lerp(a, b, t)
		elseif mt == C3Meta then
			return Color3.Lerp(a, b, t)
		elseif mt == UDim2Meta then
			return UDim2.Lerp(a, b, t)
		elseif mt == UDimMeta then
			return udim(a.Scale + (b.Scale - a.Scale) * t, a.Offset + (b.Offset - a.Offset) * t)
		elseif mt == CFMeta then
			return CFrame.Lerp(a, b, t)
		end
	end
	if b == nil then
		return a
	end
	return t >= 1 and b or a
end

local function easing(style, direction, t)
	local s = style and style.Name or "Quad"
	local d = direction and direction.Name or "Out"
	local function inF(x)
		if s == "Linear" then
			return x
		elseif s == "Sine" then
			return 1 - math.cos(x * math.pi / 2)
		elseif s == "Quad" then
			return x * x
		elseif s == "Cubic" then
			return x * x * x
		elseif s == "Quart" then
			return x ^ 4
		elseif s == "Quint" then
			return x ^ 5
		elseif s == "Exponential" then
			return x == 0 and 0 or 2 ^ (10 * x - 10)
		elseif s == "Circular" then
			return 1 - math.sqrt(math.max(0, 1 - x * x))
		elseif s == "Back" then
			local c1 = 1.70158
			return (c1 + 1) * x ^ 3 - c1 * x * x
		elseif s == "Elastic" then
			if x == 0 or x == 1 then
				return x
			end
			return -(2 ^ (10 * x - 10)) * math.sin((x * 10 - 10.75) * (2 * math.pi) / 3)
		elseif s == "Bounce" then
			local function out(y)
				local n1, d1 = 7.5625, 2.75
				if y < 1 / d1 then
					return n1 * y * y
				elseif y < 2 / d1 then
					y -= 1.5 / d1
					return n1 * y * y + 0.75
				elseif y < 2.5 / d1 then
					y -= 2.25 / d1
					return n1 * y * y + 0.9375
				end
				y -= 2.625 / d1
				return n1 * y * y + 0.984375
			end
			return 1 - out(1 - x)
		end
		return x
	end
	if d == "In" then
		return inF(t)
	elseif d == "Out" then
		return 1 - inF(1 - t)
	end
	if t < 0.5 then
		return inF(t * 2) / 2
	end
	return 1 - inF((1 - t) * 2) / 2
end
Mock.Easing = easing

---------------------------------------------------------------- Signale
local Signal = {}
Signal.__index = Signal
local Connection = {}
Connection.__index = Connection
function Connection:Disconnect()
	if not self.Connected then
		return
	end
	self.Connected = false
	local list = self.signal.handlers
	for i, h in ipairs(list) do
		if h == self then
			table.remove(list, i)
			break
		end
	end
end

function Signal.new(env, name)
	return setmetatable({ env = env, name = name, handlers = {}, waiting = {}, __type = "RBXScriptSignal" }, Signal)
end
function Signal:Connect(fn)
	assert(type(fn) == "function", "Attempt to connect failed: Passed value is not a function")
	local conn = setmetatable({ Connected = true, fn = fn, signal = self, __type = "RBXScriptConnection" }, Connection)
	conn.ctx = self.env and currentCtx(self.env) or nil
	table.insert(self.handlers, conn)
	return conn
end
Signal.connect = Signal.Connect
function Signal:ConnectParallel(fn)
	return self:Connect(fn)
end
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Wait()
	local env = self.env
	local co = coroutine.running()
	assert(co and coroutine.isyieldable(), "Signal:Wait nur in einer Coroutine möglich")
	table.insert(self.waiting, co)
	return coroutine.yield()
end
local function deliver(self, filter, ...)
	local env = self.env
	local list = table.clone(self.handlers)
	for _, conn in ipairs(list) do
		if conn.Connected and (not filter or filter(conn)) then
			if env then
				env.scheduler:spawnIn(conn.ctx, conn.fn, ...)
			else
				conn.fn(...)
			end
		end
	end
	if #self.waiting > 0 then
		local waiting = self.waiting
		self.waiting = {}
		for _, co in ipairs(waiting) do
			if env then
				env.scheduler:wake(co, ...)
			end
		end
	end
end
function Signal:Fire(...)
	deliver(self, nil, ...)
end
-- Nur an Verbindungen aus dem Client-Kontext dieses Spielers (bzw. ohne Spieler: an Server-Verbindungen)
function Signal:FireFor(player, ...)
	deliver(self, function(conn)
		local c = conn.ctx
		if player == nil then
			return not (c and c.player)
		end
		return c ~= nil and c.player == player
	end, ...)
end
function Signal:ConnectionCount()
	return #self.handlers
end
function Signal:DisconnectAll()
	for _, conn in ipairs(table.clone(self.handlers)) do
		conn:Disconnect()
	end
end

---------------------------------------------------------------- Klassen
local SUPER = {
	PVInstance = "Instance", Model = "PVInstance", WorldRoot = "Model", Workspace = "WorldRoot", WorldModel = "WorldRoot",
	BasePart = "PVInstance", FormFactorPart = "BasePart", Part = "FormFactorPart", WedgePart = "FormFactorPart",
	CornerWedgePart = "BasePart", TrussPart = "BasePart", SpawnLocation = "Part", Seat = "Part", VehicleSeat = "BasePart",
	TriangleMeshPart = "BasePart", MeshPart = "TriangleMeshPart", PartOperation = "TriangleMeshPart",
	UnionOperation = "PartOperation", NegateOperation = "PartOperation", Terrain = "BasePart",
	Folder = "Instance", Configuration = "Instance", Camera = "PVInstance",
	GuiBase = "Instance", GuiBase2d = "GuiBase", LayerCollector = "GuiBase2d", ScreenGui = "LayerCollector",
	SurfaceGuiBase = "LayerCollector", SurfaceGui = "SurfaceGuiBase", BillboardGui = "LayerCollector",
	GuiObject = "GuiBase2d", Frame = "GuiObject", ScrollingFrame = "GuiObject", GuiLabel = "GuiObject",
	TextLabel = "GuiLabel", ImageLabel = "GuiLabel", GuiButton = "GuiObject", TextButton = "GuiButton",
	ImageButton = "GuiButton", TextBox = "GuiObject", ViewportFrame = "GuiObject", CanvasGroup = "GuiObject",
	VideoFrame = "GuiObject",
	UIBase = "Instance", UIComponent = "UIBase", UIConstraint = "UIComponent", UISizeConstraint = "UIConstraint",
	UIAspectRatioConstraint = "UIConstraint", UITextSizeConstraint = "UIConstraint", UILayout = "UIComponent",
	UIGridStyleLayout = "UILayout", UIListLayout = "UIGridStyleLayout", UIGridLayout = "UIGridStyleLayout",
	UIPageLayout = "UIGridStyleLayout", UITableLayout = "UIGridStyleLayout", UICorner = "UIComponent",
	UIStroke = "UIComponent", UIScale = "UIComponent", UIPadding = "UIComponent", UIGradient = "UIComponent",
	UIFlexItem = "UIComponent",
	ValueBase = "Instance", NumberValue = "ValueBase", IntValue = "ValueBase", StringValue = "ValueBase",
	BoolValue = "ValueBase", ObjectValue = "ValueBase", Vector3Value = "ValueBase", CFrameValue = "ValueBase",
	Color3Value = "ValueBase", BrickColorValue = "ValueBase", RayValue = "ValueBase",
	JointInstance = "Instance", Weld = "JointInstance", Snap = "JointInstance", Motor = "JointInstance",
	Motor6D = "Motor", ManualWeld = "JointInstance", WeldConstraint = "Instance", NoCollisionConstraint = "Instance",
	Constraint = "Instance", RopeConstraint = "Constraint", HingeConstraint = "Constraint", AlignPosition = "Constraint",
	AlignOrientation = "Constraint",
	Light = "Instance", PointLight = "Light", SpotLight = "Light", SurfaceLight = "Light",
	Attachment = "Instance", Bone = "Attachment",
	Humanoid = "Instance", Animator = "Instance", Animation = "Instance", AnimationTrack = "Instance",
	Sound = "Instance", SoundGroup = "Instance",
	BaseRemoteEvent = "Instance", RemoteEvent = "BaseRemoteEvent", UnreliableRemoteEvent = "BaseRemoteEvent",
	RemoteFunction = "Instance", BindableEvent = "Instance", BindableFunction = "Instance",
	ProximityPrompt = "Instance", ClickDetector = "Instance", Highlight = "Instance",
	LuaSourceContainer = "Instance", BaseScript = "LuaSourceContainer", Script = "BaseScript",
	LocalScript = "Script", ModuleScript = "LuaSourceContainer",
	Player = "Instance", BasePlayerGui = "Instance", PlayerGui = "BasePlayerGui", StarterGui = "BasePlayerGui",
	Backpack = "Instance", PlayerScripts = "Instance", StarterPlayerScripts = "Instance",
	StarterCharacterScripts = "StarterPlayerScripts", Mouse = "Instance", PlayerMouse = "Mouse",
	TweenBase = "Instance", Tween = "TweenBase",
	PostEffect = "Instance", BloomEffect = "PostEffect", ColorCorrectionEffect = "PostEffect", BlurEffect = "PostEffect",
	SunRaysEffect = "PostEffect", DepthOfFieldEffect = "PostEffect", Atmosphere = "Instance", Sky = "Instance", Clouds = "Instance",
	ParticleEmitter = "Instance", Beam = "Instance", Trail = "Instance", Fire = "Instance", Smoke = "Instance", Sparkles = "Instance",
	DataModelMesh = "Instance", FileMesh = "DataModelMesh", SpecialMesh = "FileMesh", BlockMesh = "DataModelMesh",
	FaceInstance = "Instance", Decal = "FaceInstance", Texture = "Decal", SurfaceAppearance = "Instance",
	Accessory = "Instance", Tool = "Instance", Team = "Instance",
	DataModel = "Instance",
}
local SERVICES = {
	"Players", "Lighting", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService",
	"StarterPlayer", "StarterPack", "SoundService", "Teams", "Chat", "LocalizationService", "TweenService",
	"RunService", "HttpService", "DataStoreService", "MarketplaceService", "UserInputService",
	"ContextActionService", "ProximityPromptService", "GuiService", "CollectionService", "Debris", "TextService",
	"PolicyService", "BadgeService", "SocialService", "AnalyticsService", "MessagingService", "TeleportService",
	"PhysicsService", "PathfindingService", "VRService", "HapticService", "TextChatService", "GroupService",
	"AssetService", "ContentProvider", "Stats", "LogService", "TestService", "VoiceChatService", "ScriptContext",
	"MemoryStoreService", "StarterGui",
}
for _, s in ipairs(SERVICES) do
	if not SUPER[s] then
		SUPER[s] = "Instance"
	end
end

local CLASS = {} -- Name -> {defaults, methods, signals, getters, setters}
local function spec(name)
	CLASS[name] = CLASS[name] or { defaults = {}, methods = {}, signals = {}, getters = {}, setters = {} }
	return CLASS[name]
end
local resolved = {}
local function resolve(name)
	local r = resolved[name]
	if r then
		return r
	end
	local chain = {}
	local cur = name
	local seen = {}
	while cur and not seen[cur] do
		seen[cur] = true
		table.insert(chain, 1, cur)
		cur = SUPER[cur] or (cur ~= "Instance" and "Instance" or nil)
	end
	r = { defaults = {}, methods = {}, signals = {}, getters = {}, setters = {}, isA = {}, name = name }
	for _, c in ipairs(chain) do
		r.isA[c] = true
		local s = CLASS[c]
		if s then
			for k, v in pairs(s.defaults) do
				r.defaults[k] = v
			end
			for k, v in pairs(s.methods) do
				r.methods[k] = v
			end
			for k, v in pairs(s.signals) do
				r.signals[k] = v
			end
			for k, v in pairs(s.getters) do
				r.getters[k] = v
			end
			for k, v in pairs(s.setters) do
				r.setters[k] = v
			end
		end
	end
	resolved[name] = r
	return r
end
local function signals(className, list)
	local s = spec(className)
	for _, n in ipairs(list) do
		s.signals[n] = true
	end
end

---------------------------------------------------------------- Instanzen
local Instance = {}
local InstanceMeta = {}

local function newInstance(env, className, name)
	local data = {
		ClassName = className,
		Name = name or className,
		_cls = resolve(className),
		_children = {},
		_attributes = {},
		_signals = {},
		_env = env,
		_parent = nil,
		_destroyed = false,
	}
	local inst = setmetatable({}, InstanceMeta)
	rawset(inst, "__data", data)
	env.instanceCount += 1
	env.nextId += 1
	data._id = env.nextId
	if className == "ProximityPrompt" then
		env.prompts[inst] = true
	end
	return inst
end
Mock.NewInstance = newInstance

local function getSignal(data, key)
	local s = data._signals[key]
	if not s then
		s = Signal.new(data._env, key)
		data._signals[key] = s
		if key == "DescendantAdded" or key == "DescendantRemoving" or key == "AncestryChanged" then
			data._env.treeWatchers += 1
		end
	end
	return s
end
local function fireIf(data, key, ...)
	local s = data._signals[key]
	if s and (#s.handlers > 0 or #s.waiting > 0) then
		s:Fire(...)
	end
end

local function findChild(data, name)
	for _, c in ipairs(data._children) do
		if rawget(c, "__data").Name == name then
			return c
		end
	end
	return nil
end

local function propertyChanged(inst, data, key, value)
	local sigs = data._signals
	if not next(sigs) then
		return
	end
	local s = sigs["Changed:" .. key]
	if s and (#s.handlers > 0 or #s.waiting > 0) then
		s:Fire()
	end
	s = sigs.Changed
	if s and (#s.handlers > 0 or #s.waiting > 0) then
		if data._cls.isA.ValueBase then
			if key == "Value" then
				s:Fire(value)
			end
		else
			s:Fire(key)
		end
	end
end

local function rawSet(inst, data, key, value)
	local old = data[key]
	data[key] = value
	if old ~= value then
		propertyChanged(inst, data, key, value)
	end
end

local function descendantsOf(inst, out)
	out = out or {}
	local stack = { inst }
	local i = 1
	-- Tiefensuche in Kindreihenfolge
	local function walk(x)
		for _, c in ipairs(rawget(x, "__data")._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(inst)
	return out
end

local function rawAttach(child, parent)
	local cd = rawget(child, "__data")
	cd._parent = parent
	table.insert(rawget(parent, "__data")._children, child)
end

local function setParent(inst, data, value)
	if data._destroyed then
		error("The Parent property of " .. tostring(data.Name) .. " is locked, current parent: NULL, new parent " .. tostring(value and value.Name), 3)
	end
	local old = data._parent
	if old == value then
		return
	end
	if value ~= nil then
		assert(isInstance(value), "Parent muss eine Instanz sein")
		local cur = value
		while cur do
			if cur == inst then
				error("Attempt to set " .. inst:GetFullName() .. " as its own parent", 3)
			end
			cur = rawget(cur, "__data")._parent
		end
	end
	local env = data._env
	local watch = env.treeWatchers > 0
	if old then
		local od = rawget(old, "__data")
		if watch then
			local list = { inst }
			descendantsOf(inst, list)
			local a = old
			while a do
				local ad = rawget(a, "__data")
				if ad._signals.DescendantRemoving then
					for _, x in ipairs(list) do
						fireIf(ad, "DescendantRemoving", x)
					end
				end
				a = ad._parent
			end
		end
		local list = od._children
		for i, c in ipairs(list) do
			if c == inst then
				table.remove(list, i)
				break
			end
		end
		data._parent = nil
		fireIf(od, "ChildRemoved", inst)
	end
	data._parent = value
	if value then
		local vd = rawget(value, "__data")
		table.insert(vd._children, inst)
		fireIf(vd, "ChildAdded", inst)
		if watch then
			local list = { inst }
			descendantsOf(inst, list)
			local a = value
			while a do
				local ad = rawget(a, "__data")
				if ad._signals.DescendantAdded then
					for _, x in ipairs(list) do
						fireIf(ad, "DescendantAdded", x)
					end
				end
				a = ad._parent
			end
		end
	end
	if watch then
		local list = { inst }
		descendantsOf(inst, list)
		for _, x in ipairs(list) do
			local xd = rawget(x, "__data")
			if xd._signals.AncestryChanged then
				fireIf(xd, "AncestryChanged", inst, value)
			end
		end
	end
	propertyChanged(inst, data, "Parent", value)
end

InstanceMeta.__index = function(self, key)
	local data = rawget(self, "__data")
	if key == "Parent" then
		return data._parent
	end
	local cls = data._cls
	local m = cls.methods[key]
	if m then
		return m
	end
	if cls.signals[key] then
		return getSignal(data, key)
	end
	local v = data[key]
	if v ~= nil then
		return v
	end
	local g = cls.getters[key]
	if g then
		return g(self, data)
	end
	local d = cls.defaults[key]
	if d ~= nil then
		return d
	end
	return findChild(data, key)
end
InstanceMeta.__newindex = function(self, key, value)
	local data = rawget(self, "__data")
	if key == "Parent" then
		setParent(self, data, value)
		return
	end
	local s = data._cls.setters[key]
	if s then
		s(self, data, value)
		return
	end
	local old = data[key]
	if old == nil then
		old = data._cls.defaults[key]
	end
	data[key] = value
	if old ~= value then
		propertyChanged(self, data, key, value)
	end
end
InstanceMeta.__tostring = function(self)
	return rawget(self, "__data").Name
end
Instance.Meta = InstanceMeta

---------------------------------------------------------------- Instance-Methoden
local I = spec("Instance")
signals("Instance", { "Changed", "ChildAdded", "ChildRemoved", "DescendantAdded", "DescendantRemoving", "AncestryChanged", "AttributeChanged", "Destroying" })
I.defaults.Archivable = true
local M = I.methods
Instance.Methods = M

function M:GetChildren()
	return table.clone(rawget(self, "__data")._children)
end
function M:GetDescendants()
	return descendantsOf(self, {})
end
function M:FindFirstChild(name, recursive)
	local data = rawget(self, "__data")
	local c = findChild(data, name)
	if c or not recursive then
		return c
	end
	for _, child in ipairs(data._children) do
		local found = child:FindFirstChild(name, true)
		if found then
			return found
		end
	end
	return nil
end
function M:FindFirstChildOfClass(cls)
	for _, c in ipairs(rawget(self, "__data")._children) do
		if rawget(c, "__data").ClassName == cls then
			return c
		end
	end
	return nil
end
function M:FindFirstChildWhichIsA(cls, recursive)
	local data = rawget(self, "__data")
	for _, c in ipairs(data._children) do
		if rawget(c, "__data")._cls.isA[cls] then
			return c
		end
	end
	if recursive then
		for _, c in ipairs(data._children) do
			local found = c:FindFirstChildWhichIsA(cls, true)
			if found then
				return found
			end
		end
	end
	return nil
end
function M:FindFirstDescendant(name)
	return self:FindFirstChild(name, true)
end
function M:FindFirstAncestor(name)
	local cur = rawget(self, "__data")._parent
	while cur do
		if rawget(cur, "__data").Name == name then
			return cur
		end
		cur = rawget(cur, "__data")._parent
	end
	return nil
end
function M:FindFirstAncestorOfClass(cls)
	local cur = rawget(self, "__data")._parent
	while cur do
		if rawget(cur, "__data").ClassName == cls then
			return cur
		end
		cur = rawget(cur, "__data")._parent
	end
	return nil
end
function M:FindFirstAncestorWhichIsA(cls)
	local cur = rawget(self, "__data")._parent
	while cur do
		if rawget(cur, "__data")._cls.isA[cls] then
			return cur
		end
		cur = rawget(cur, "__data")._parent
	end
	return nil
end
function M:IsA(cls)
	return rawget(self, "__data")._cls.isA[cls] == true
end
function M:IsDescendantOf(ancestor)
	local cur = rawget(self, "__data")._parent
	while cur do
		if cur == ancestor then
			return true
		end
		cur = rawget(cur, "__data")._parent
	end
	return false
end
function M:IsAncestorOf(desc)
	return isInstance(desc) and desc:IsDescendantOf(self)
end
function M:WaitForChild(name, timeout)
	local data = rawget(self, "__data")
	local c = findChild(data, name)
	if c then
		return c
	end
	local env = data._env
	local co = coroutine.running()
	if not co or not coroutine.isyieldable() then
		if timeout then
			return nil
		end
		error("WaitForChild: '" .. tostring(name) .. "' fehlt unter " .. self:GetFullName() .. " (Hauptthread kann nicht warten)", 2)
	end
	local sched = env.scheduler
	local clock = env.clock
	local start = clock.precise
	local done, result, warned = false, nil, false
	local conn = getSignal(data, "ChildAdded"):Connect(function(child)
		if not done and child.Name == name then
			done, result = true, child
			sched:wake(co)
		end
	end)
	while not done do
		local step = 1
		if timeout then
			step = math.min(step, math.max(0, start + timeout - clock.precise))
		end
		sched:sleep(step)
		if not done then
			local found = findChild(data, name)
			if found then
				done, result = true, found
			elseif data._destroyed then
				done = true
			elseif timeout and clock.precise >= start + timeout - 1e-9 then
				done = true
			elseif not timeout and not warned and clock.precise - start >= 5 then
				warned = true
				table.insert(env.warnings, "Infinite yield possible on '" .. self:GetFullName() .. ':WaitForChild("' .. tostring(name) .. '")\'')
			end
		end
	end
	conn:Disconnect()
	return result
end
function M:Destroy()
	local data = rawget(self, "__data")
	if data._destroyed then
		return
	end
	fireIf(data, "Destroying")
	for _, c in ipairs(table.clone(data._children)) do
		c:Destroy()
	end
	if data._parent then
		setParent(self, data, nil)
	end
	data._destroyed = true
	for _, sig in pairs(data._signals) do
		for _, conn in ipairs(table.clone(sig.handlers)) do
			conn.Connected = false
		end
		sig.handlers = {}
	end
end
function M:Remove()
	self.Parent = nil
end
function M:ClearAllChildren()
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
end
function M:GetPropertyChangedSignal(prop)
	return getSignal(rawget(self, "__data"), "Changed:" .. tostring(prop))
end
function M:GetAttributeChangedSignal(name)
	return getSignal(rawget(self, "__data"), "AttrChanged:" .. tostring(name))
end
local ATTRIBUTE_TYPES = {
	boolean = true, number = true, string = true, Vector3 = true, Vector2 = true, CFrame = true, Color3 = true,
	UDim = true, UDim2 = true, NumberRange = true, NumberSequence = true, ColorSequence = true, Rect = true,
	BrickColor = true, EnumItem = true, Font = true,
}
local function typeOf(v)
	local t = type(v)
	if t == "table" then
		if rawget(v, "__data") then
			return "Instance"
		end
		local tt = rawget(v, "__type")
		if tt then
			return tt
		end
		if getmetatable(v) == EnumItemMeta then
			return "EnumItem"
		end
	end
	return t
end
Mock.typeof = typeOf
function M:SetAttribute(k, v)
	assert(type(k) == "string", "Attributname muss ein String sein")
	if v ~= nil and not ATTRIBUTE_TYPES[typeOf(v)] then
		error("SetAttribute: Typ " .. typeOf(v) .. " wird als Attribut nicht unterstützt (" .. k .. ")", 2)
	end
	local data = rawget(self, "__data")
	local old = data._attributes[k]
	data._attributes[k] = v
	if old ~= v then
		fireIf(data, "AttributeChanged", k)
		fireIf(data, "AttrChanged:" .. k)
	end
end
function M:GetAttribute(k)
	return rawget(self, "__data")._attributes[k]
end
function M:GetAttributes()
	return table.clone(rawget(self, "__data")._attributes)
end
function M:GetFullName()
	local parts = {}
	local cur = self
	while cur do
		local d = rawget(cur, "__data")
		if d.ClassName == "DataModel" then
			break
		end
		table.insert(parts, 1, d.Name)
		cur = d._parent
	end
	return table.concat(parts, ".")
end
function M:GetDebugId()
	return tostring(rawget(self, "__data")._id)
end
function M:AddTag(tag)
	local data = rawget(self, "__data")
	data._tags = data._tags or {}
	data._tags[tag] = true
end
function M:RemoveTag(tag)
	local data = rawget(self, "__data")
	if data._tags then
		data._tags[tag] = nil
	end
end
function M:HasTag(tag)
	local data = rawget(self, "__data")
	return data._tags ~= nil and data._tags[tag] == true
end
function M:GetTags()
	local out = {}
	for t in pairs(rawget(self, "__data")._tags or {}) do
		table.insert(out, t)
	end
	table.sort(out)
	return out
end
function M:Clone()
	local src = rawget(self, "__data")
	if src.Archivable == false then
		return nil
	end
	local env = src._env
	local map = {}
	local list = {}
	local function copy(inst)
		local sd = rawget(inst, "__data")
		if sd.Archivable == false then
			return nil
		end
		local c = newInstance(env, sd.ClassName, sd.Name)
		local cd = rawget(c, "__data")
		for k, v in pairs(sd) do
			if type(k) == "string" and string.byte(k, 1) ~= 95 then
				cd[k] = v
			end
		end
		for k, v in pairs(sd._attributes) do
			cd._attributes[k] = v
		end
		if sd._tags then
			cd._tags = table.clone(sd._tags)
		end
		map[inst] = c
		table.insert(list, c)
		for _, ch in ipairs(sd._children) do
			local cc = copy(ch)
			if cc then
				rawAttach(cc, c)
			end
		end
		return c
	end
	local root = copy(self)
	-- Ref-Eigenschaften (PrimaryPart, Part0/1, Adornee …) innerhalb der Kopie umbiegen
	for _, c in ipairs(list) do
		local cd = rawget(c, "__data")
		for k, v in pairs(cd) do
			if type(v) == "table" and type(k) == "string" and string.byte(k, 1) ~= 95 and map[v] then
				cd[k] = map[v]
			end
		end
	end
	return root
end

---------------------------------------------------------------- PVInstance / BasePart / Model
local IDENTITY = CFrame.identity
local function isBasePart(inst)
	return rawget(inst, "__data")._cls.isA.BasePart == true
end

local BP = spec("BasePart")
BP.defaults.Anchored = false
BP.defaults.CanCollide = true
BP.defaults.CanQuery = true
BP.defaults.CanTouch = true
BP.defaults.CastShadow = true
BP.defaults.Transparency = 0
BP.defaults.Reflectance = 0
BP.defaults.Massless = false
BP.defaults.Locked = false
BP.defaults.Color = Color3.fromRGB(163, 162, 165)
BP.defaults.Material = Enum.Material.Plastic
BP.defaults.Size = Vector3.new(4, 1.2, 2)
BP.defaults.CFrame = IDENTITY
BP.defaults.PivotOffset = IDENTITY
BP.defaults.AssemblyLinearVelocity = Vector3.zero
BP.defaults.AssemblyAngularVelocity = Vector3.zero
BP.defaults.Velocity = Vector3.zero
BP.defaults.CollisionGroup = "Default"
spec("Part").defaults.Shape = Enum.PartType.Block
signals("BasePart", { "Touched", "TouchEnded" })
BP.getters.Position = function(_, data)
	local c = data.CFrame or IDENTITY
	return c.Position
end
BP.setters.Position = function(inst, data, value)
	local c = data.CFrame or IDENTITY
	local m = c._m
	rawSet(inst, data, "CFrame", cf(value.X, value.Y, value.Z, m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12]))
	propertyChanged(inst, data, "Position", value)
end
BP.setters.CFrame = function(inst, data, value)
	assert(typeOf(value) == "CFrame", "CFrame erwartet, erhalten " .. typeOf(value))
	rawSet(inst, data, "CFrame", value)
end
BP.getters.Orientation = function(_, data)
	local rx, ry, rz = CFrame.ToOrientation(data.CFrame or IDENTITY)
	return Vector3.new(math.deg(rx), math.deg(ry), math.deg(rz))
end
BP.setters.Orientation = function(inst, data, value)
	local p = (data.CFrame or IDENTITY).Position
	rawSet(inst, data, "CFrame", CFrame.new(p.X, p.Y, p.Z) * CFrame.fromOrientation(math.rad(value.X), math.rad(value.Y), math.rad(value.Z)))
end
BP.getters.Rotation = BP.getters.Orientation
BP.getters.Mass = function(_, data)
	local s = data.Size or BP.defaults.Size
	return s.X * s.Y * s.Z * 0.7
end
BP.getters.AssemblyMass = BP.getters.Mass
BP.setters.BrickColor = function(inst, data, value)
	rawSet(inst, data, "BrickColor", value)
	rawSet(inst, data, "Color", value.Color)
end
BP.getters.BrickColor = function(_, data)
	return BrickColor.new(194)
end
BP.getters.ExtentsCFrame = function(_, data)
	return data.CFrame or IDENTITY
end
BP.getters.AssemblyRootPart = function(inst)
	return inst
end
local BPM = BP.methods
function BPM:GetPivot()
	local d = rawget(self, "__data")
	return (d.CFrame or IDENTITY) * (d.PivotOffset or IDENTITY)
end
function BPM:PivotTo(target)
	local d = rawget(self, "__data")
	local old = self:GetPivot()
	local delta = target * old:Inverse()
	self.CFrame = target * (d.PivotOffset or IDENTITY):Inverse()
	-- Parts, die als Nachfahren an diesem Part hängen, wandern mit
	for _, x in ipairs(self:GetDescendants()) do
		if isBasePart(x) then
			x.CFrame = delta * x.CFrame
		end
	end
end
function BPM:GetMass()
	return self.Mass
end
function BPM:GetTouchingParts()
	return {}
end
function BPM:GetConnectedParts()
	return { self }
end
function BPM:GetRootPart()
	return self
end
function BPM:SetNetworkOwner() end
function BPM:SetNetworkOwnershipAuto() end
function BPM:GetNetworkOwner()
	return nil
end
function BPM:CanSetNetworkOwnership()
	return true
end
function BPM:ApplyImpulse() end
function BPM:ApplyAngularImpulse() end
function BPM:BreakJoints() end
function BPM:Resize()
	return true
end

local function partsOf(model)
	local out = {}
	for _, x in ipairs(model:GetDescendants()) do
		if isBasePart(x) then
			table.insert(out, x)
		end
	end
	return out
end
local function boundingBox(parts, frame)
	-- Achsenparallele Box im Koordinatensystem `frame` (oder Welt)
	local inv = frame and frame:Inverse()
	local mn, mx
	for _, p in ipairs(parts) do
		local c = p.CFrame
		local s = p.Size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local w = c * Vector3.new(s.X * sx, s.Y * sy, s.Z * sz)
					if inv then
						w = inv * w
					end
					mn = mn and Vector3.Min(mn, w) or w
					mx = mx and Vector3.Max(mx, w) or w
				end
			end
		end
	end
	return mn, mx
end
Mock.BoundingBox = boundingBox

local MD = spec("Model")
MD.getters.WorldPivot = function(inst)
	return inst:GetPivot()
end
MD.setters.WorldPivot = function(inst, data, value)
	rawSet(inst, data, "WorldPivot", value)
end
MD.defaults.PivotOffset = IDENTITY
local MM = MD.methods
function MM:GetPivot()
	local d = rawget(self, "__data")
	local pp = d.PrimaryPart
	if pp and pp:IsDescendantOf(self) then
		return pp.CFrame * (d.PivotOffset or IDENTITY)
	end
	if d.WorldPivot then
		return d.WorldPivot
	end
	local parts = partsOf(self)
	if #parts == 0 then
		return IDENTITY
	end
	local mn, mx = boundingBox(parts)
	return CFrame.new((mn + mx) / 2)
end
function MM:PivotTo(target)
	local d = rawget(self, "__data")
	local old = self:GetPivot()
	local delta = target * old:Inverse()
	for _, p in ipairs(partsOf(self)) do
		p.CFrame = delta * p.CFrame
	end
	local pp = d.PrimaryPart
	if not (pp and pp:IsDescendantOf(self)) then
		d.WorldPivot = target
	end
end
function MM:SetPrimaryPartCFrame(c)
	local pp = rawget(self, "__data").PrimaryPart
	assert(pp, "SetPrimaryPartCFrame: Model hat kein PrimaryPart")
	self:PivotTo(c * (rawget(self, "__data").PivotOffset or IDENTITY))
end
function MM:GetPrimaryPartCFrame()
	local pp = rawget(self, "__data").PrimaryPart
	return pp and pp.CFrame
end
function MM:GetBoundingBox()
	local parts = partsOf(self)
	if #parts == 0 then
		return self:GetPivot(), Vector3.zero
	end
	local frame = self:GetPivot()
	local mn, mx = boundingBox(parts, frame)
	return frame * CFrame.new((mn + mx) / 2), mx - mn
end
function MM:GetExtentsSize()
	local _, size = self:GetBoundingBox()
	return size
end
function MM:MoveTo(pos)
	local c = self:GetPivot()
	self:PivotTo(c - c.Position + pos)
end
function MM:TranslateBy(delta)
	self:PivotTo(self:GetPivot() + delta)
end
function MM:GetScale()
	return 1
end
function MM:ScaleTo() end
function MM:BreakJoints() end
function MM:MakeJoints() end

-- Camera
local CAM = spec("Camera")
CAM.defaults.CFrame = IDENTITY
CAM.defaults.Focus = IDENTITY
CAM.defaults.FieldOfView = 70
CAM.defaults.CameraType = Enum.CameraType.Custom
CAM.getters.ViewportSize = function(_, data)
	return data._env.viewport
end
function CAM.methods:GetPivot()
	return self.CFrame
end
function CAM.methods:PivotTo(c)
	self.CFrame = c
end
function CAM.methods:WorldToViewportPoint(p)
	return Vector3.new(0, 0, 1), true
end
CAM.methods.WorldToScreenPoint = CAM.methods.WorldToViewportPoint
function CAM.methods:ViewportPointToRay(x, y)
	return Ray.new(self.CFrame.Position, self.CFrame.LookVector)
end
CAM.methods.ScreenPointToRay = CAM.methods.ViewportPointToRay

-- Workspace
local WS = spec("Workspace")
WS.defaults.Gravity = 196.2
WS.getters.CurrentCamera = function(inst, data)
	local cam = findChild(data, "Camera")
	if not cam then
		cam = newInstance(data._env, "Camera", "Camera")
		rawAttach(cam, inst)
	end
	data.CurrentCamera = cam
	return cam
end
function WS.methods:GetServerTimeNow()
	return rawget(self, "__data")._env.clock.wall
end
function WS.methods:Raycast()
	return nil
end
function WS.methods:GetPartBoundsInBox()
	return {}
end
function WS.methods:GetPartBoundsInRadius()
	return {}
end
function WS.methods:GetPartsInPart()
	return {}
end
function WS.methods:FindPartOnRay()
	return nil, Vector3.zero
end
function WS.methods:FindPartOnRayWithIgnoreList()
	return nil, Vector3.zero
end
function WS.methods:GetRealPhysicsFPS()
	return 60
end
spec("Terrain").methods.FillBlock = function() end
spec("Terrain").methods.FillBall = function() end
spec("Terrain").methods.Clear = function() end

-- Attachment
local AT = spec("Attachment")
AT.defaults.CFrame = IDENTITY
AT.getters.Position = function(_, data)
	return (data.CFrame or IDENTITY).Position
end
AT.setters.Position = function(inst, data, v)
	local m = (data.CFrame or IDENTITY)._m
	rawSet(inst, data, "CFrame", cf(v.X, v.Y, v.Z, m[4], m[5], m[6], m[7], m[8], m[9], m[10], m[11], m[12]))
end
AT.getters.WorldCFrame = function(inst, data)
	local parent = data._parent
	local base = (parent and isBasePart(parent)) and parent.CFrame or IDENTITY
	return base * (data.CFrame or IDENTITY)
end
AT.getters.WorldPosition = function(inst, data)
	return AT.getters.WorldCFrame(inst, data).Position
end
AT.getters.Axis = function(inst, data)
	return (data.CFrame or IDENTITY).RightVector
end

-- Joints
spec("JointInstance").defaults.C0 = IDENTITY
spec("JointInstance").defaults.C1 = IDENTITY
spec("JointInstance").defaults.Enabled = true
spec("WeldConstraint").defaults.Enabled = true
spec("Motor").defaults.MaxVelocity = 0.1

-- Lichter / Effekte
spec("Light").defaults.Enabled = true
spec("Light").defaults.Brightness = 1
spec("Light").defaults.Range = 8
spec("Light").defaults.Color = Color3.new(1, 1, 1)
spec("Light").defaults.Shadows = false
spec("PostEffect").defaults.Enabled = true
spec("ParticleEmitter").defaults.Enabled = true
spec("ParticleEmitter").methods.Emit = function() end
spec("Highlight").defaults.Enabled = true
spec("Highlight").defaults.FillTransparency = 0.5
spec("Highlight").defaults.OutlineTransparency = 0
spec("Highlight").defaults.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
spec("SpawnLocation").defaults.Enabled = true
spec("SpawnLocation").defaults.Neutral = true
spec("SpawnLocation").defaults.Duration = 10
spec("Decal").defaults.Transparency = 0
spec("ClickDetector").defaults.MaxActivationDistance = 32
signals("ClickDetector", { "MouseClick", "RightMouseClick", "MouseHoverEnter", "MouseHoverLeave" })

-- Werte
spec("NumberValue").defaults.Value = 0
spec("IntValue").defaults.Value = 0
spec("StringValue").defaults.Value = ""
spec("BoolValue").defaults.Value = false
spec("Vector3Value").defaults.Value = Vector3.zero
spec("CFrameValue").defaults.Value = IDENTITY
spec("Color3Value").defaults.Value = Color3.new()
spec("IntValue").setters.Value = function(inst, data, v)
	rawSet(inst, data, "Value", math.floor(tonumber(v) or 0))
end

-- ProximityPrompt
local PP = spec("ProximityPrompt")
PP.defaults.Enabled = true
PP.defaults.ActionText = "Interact"
PP.defaults.ObjectText = ""
PP.defaults.HoldDuration = 0
PP.defaults.MaxActivationDistance = 10
PP.defaults.KeyboardKeyCode = Enum.KeyCode.E
PP.defaults.GamepadKeyCode = Enum.KeyCode.ButtonX
PP.defaults.RequiresLineOfSight = true
PP.defaults.ClickablePrompt = true
PP.defaults.Style = Enum.ProximityPromptStyle.Default
PP.defaults.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
PP.defaults.UIOffset = Vector2.zero
PP.defaults.AutoLocalize = true
signals("ProximityPrompt", { "Triggered", "TriggerEnded", "PromptButtonHoldBegan", "PromptButtonHoldEnded", "PromptShown", "PromptHidden" })
function PP.methods:InputHoldBegin() end
function PP.methods:InputHoldEnd() end

-- Humanoid
local HU = spec("Humanoid")
HU.defaults.Health = 100
HU.defaults.MaxHealth = 100
HU.defaults.WalkSpeed = 16
HU.defaults.JumpPower = 50
HU.defaults.JumpHeight = 7.2
HU.defaults.UseJumpPower = false
HU.defaults.AutoJumpEnabled = true
HU.defaults.Jump = false
HU.defaults.Sit = false
HU.defaults.PlatformStand = false
HU.defaults.HipHeight = 2
HU.defaults.DisplayName = ""
HU.defaults.RigType = Enum.HumanoidRigType.R15
HU.defaults.MoveDirection = Vector3.zero
HU.defaults.FloorMaterial = Enum.Material.Plastic
signals("Humanoid", { "Died", "HealthChanged", "StateChanged", "Running", "Jumping", "MoveToFinished", "Seated", "Touched", "FreeFalling", "Climbing" })
HU.getters.RootPart = function(inst, data)
	local p = data._parent
	return p and p:FindFirstChild("HumanoidRootPart")
end
HU.setters.Health = function(inst, data, v)
	local max = data.MaxHealth or 100
	v = math.clamp(v, 0, max)
	local old = data.Health or 100
	rawSet(inst, data, "Health", v)
	if v ~= old then
		fireIf(data, "HealthChanged", v)
	end
	if v <= 0 and not data._dead then
		data._dead = true
		data._state = Enum.HumanoidStateType.Dead
		fireIf(data, "StateChanged", Enum.HumanoidStateType.Running, Enum.HumanoidStateType.Dead)
		getSignal(data, "Died"):Fire()
	end
end
local HM = HU.methods
function HM:GetStateEnabled(state)
	local d = rawget(self, "__data")
	d._states = d._states or {}
	local v = d._states[state]
	if v == nil then
		return true
	end
	return v
end
function HM:SetStateEnabled(state, enabled)
	local d = rawget(self, "__data")
	d._states = d._states or {}
	d._states[state] = enabled == true
end
function HM:ChangeState(state)
	local d = rawget(self, "__data")
	local old = d._state or Enum.HumanoidStateType.Running
	d._state = state
	fireIf(d, "StateChanged", old, state)
end
function HM:GetState()
	return rawget(self, "__data")._state or Enum.HumanoidStateType.Running
end
function HM:TakeDamage(n)
	self.Health = self.Health - n
end
function HM:MoveTo(pos)
	local d = rawget(self, "__data")
	local ch = d._parent
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if root and ch:IsA("Model") then
		local c = ch:GetPivot()
		ch:PivotTo(c - c.Position + Vector3.new(pos.X, c.Position.Y, pos.Z))
	end
	fireIf(d, "MoveToFinished", true)
end
function HM:Move() end
function HM:EquipTool() end
function HM:UnequipTools() end
function HM:GetAppliedDescription()
	return nil
end
function HM:LoadAnimation()
	local env = rawget(self, "__data")._env
	return newInstance(env, "AnimationTrack")
end
spec("Animator").methods.LoadAnimation = HM.LoadAnimation
local AT2 = spec("AnimationTrack")
signals("AnimationTrack", { "Stopped", "Ended", "KeyframeReached", "DidLoop" })
AT2.methods.Play = function() end
AT2.methods.Stop = function() end
AT2.methods.AdjustSpeed = function() end
AT2.methods.AdjustWeight = function() end
AT2.defaults.IsPlaying = false

-- Sound
local SO = spec("Sound")
SO.defaults.Volume = 0.5
SO.defaults.Playing = false
SO.defaults.Looped = false
SO.defaults.SoundId = ""
SO.defaults.PlaybackSpeed = 1
SO.defaults.TimePosition = 0
SO.defaults.IsPlaying = false
SO.defaults.TimeLength = 0
signals("Sound", { "Ended", "Played", "Paused", "Resumed", "Stopped", "Loaded", "DidLoop" })
function SO.methods:Play()
	local d = rawget(self, "__data")
	d.Playing = true
	d.IsPlaying = true
	d._plays = (d._plays or 0) + 1
	fireIf(d, "Played", d.SoundId)
end
function SO.methods:Stop()
	local d = rawget(self, "__data")
	d.Playing = false
	d.IsPlaying = false
	fireIf(d, "Stopped", d.SoundId)
end
function SO.methods:Pause()
	rawget(self, "__data").Playing = false
end
function SO.methods:Resume()
	rawget(self, "__data").Playing = true
end

-- Skripte
spec("BaseScript").defaults.Disabled = false
spec("BaseScript").defaults.Enabled = true
spec("LuaSourceContainer").defaults.Source = ""

-- Remotes / Bindables
local RE = spec("RemoteEvent")
signals("BaseRemoteEvent", { "OnServerEvent", "OnClientEvent" })
local function copyArg(v, seen)
	local t = type(v)
	if t == "function" or t == "thread" or t == "userdata" then
		return nil
	end
	if t ~= "table" then
		return v
	end
	if rawget(v, "__data") or rawget(v, "__type") or getmetatable(v) == EnumItemMeta then
		return v -- Instanzen per Referenz, Datentypen sind unveränderlich
	end
	seen = seen or {}
	if seen[v] then
		error("Remote: zyklische Tabelle kann nicht gesendet werden", 3)
	end
	seen[v] = true
	local out = {}
	for k, x in pairs(v) do
		out[k] = copyArg(x, seen)
	end
	seen[v] = nil
	return out
end
Mock.CopyRemoteArg = copyArg
local function packCopy(...)
	local n = select("#", ...)
	local out = { n = n }
	for i = 1, n do
		out[i] = copyArg((select(i, ...)))
	end
	return out
end

-- Server empfängt (player, ...) von einem Client
function Mock.FireServerAs(env, remote, player, ...)
	local d = rawget(remote, "__data")
	d.sentToServer = d.sentToServer or {}
	local args = packCopy(...)
	table.insert(d.sentToServer, args)
	args.player = player
	local sig = d._signals.OnServerEvent
	if sig and player then
		local list = table.clone(sig.handlers)
		for _, conn in ipairs(list) do
			if conn.Connected and not (conn.ctx and conn.ctx.side == "client") then
				local copy = packCopy(table.unpack(args, 1, args.n))
				env.scheduler:spawnIn(conn.ctx or env.serverCtx, conn.fn, player, table.unpack(copy, 1, copy.n))
			end
		end
	end
end
function RE.methods:FireServer(...)
	local d = rawget(self, "__data")
	local env = d._env
	local ctx = currentCtx(env)
	local player = ctx.player or rawget(env.services.Players, "__data").LocalPlayer
	Mock.FireServerAs(env, self, player, ...)
end
function RE.methods:FireClient(player, ...)
	local d = rawget(self, "__data")
	local env = d._env
	assert(isInstance(player) and player.ClassName == "Player", "FireClient: Argument 1 muss ein Player sein")
	local sent = d.sent or {}
	d.sent = sent
	local args = packCopy(...)
	table.insert(sent, { player = player, args = args, t = env.clock.wall })
	if env.onFireClient then
		env.onFireClient(self, player, ...)
	end
	local sig = d._signals.OnClientEvent
	if sig then
		local legacy = rawget(env.services.Players, "__data").LocalPlayer
		for _, conn in ipairs(table.clone(sig.handlers)) do
			local c = conn.ctx
			local target = c and c.player or (c == nil or c.side ~= "client") and legacy or nil
			if conn.Connected and target == player then
				local copy = packCopy(...)
				env.scheduler:spawnIn(c, conn.fn, table.unpack(copy, 1, copy.n))
			end
		end
	end
end
function RE.methods:FireAllClients(...)
	local env = rawget(self, "__data")._env
	for _, p in ipairs(env.players) do
		if p.Parent ~= nil then
			self:FireClient(p, ...)
		end
	end
end
spec("UnreliableRemoteEvent").methods = RE.methods
local RF = spec("RemoteFunction")
function RF.methods:InvokeServer(...)
	local d = rawget(self, "__data")
	local env = d._env
	local ctx = currentCtx(env)
	local cb = d.OnServerInvoke
	assert(cb, "RemoteFunction ohne OnServerInvoke")
	local copy = packCopy(...)
	return cb(ctx.player, table.unpack(copy, 1, copy.n))
end
function RF.methods:InvokeClient(player, ...)
	local cb = rawget(self, "__data").OnClientInvoke
	assert(cb, "RemoteFunction ohne OnClientInvoke")
	return cb(...)
end
local BE = spec("BindableEvent")
signals("BindableEvent", { "Event" })
function BE.methods:Fire(...)
	getSignal(rawget(self, "__data"), "Event"):Fire(...)
end
spec("BindableFunction").methods.Invoke = function(self, ...)
	local cb = rawget(self, "__data").OnInvoke
	assert(cb, "BindableFunction ohne OnInvoke")
	return cb(...)
end

---------------------------------------------------------------- GUI
local GB = spec("GuiBase2d")
GB.defaults.AutoLocalize = true
local LC = spec("LayerCollector")
LC.defaults.Enabled = true
LC.defaults.ResetOnSpawn = true
LC.defaults.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
local SG = spec("ScreenGui")
SG.defaults.DisplayOrder = 0
SG.defaults.IgnoreGuiInset = false
SG.getters.AbsoluteSize = function(inst, data)
	local vp = data._env.viewport
	if data.IgnoreGuiInset then
		return vp
	end
	return Vector2.new(vp.X, vp.Y - data._env.guiInset)
end
SG.getters.AbsolutePosition = function()
	return Vector2.zero
end
local SFG = spec("SurfaceGui")
SFG.defaults.Face = Enum.NormalId.Front
SFG.defaults.CanvasSize = Vector2.new(800, 600)
SFG.defaults.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
SFG.defaults.AlwaysOnTop = false
SFG.defaults.LightInfluence = 1
SFG.defaults.PixelsPerStud = 50
SFG.getters.AbsoluteSize = function(_, data)
	return data.CanvasSize or SFG.defaults.CanvasSize
end
SFG.getters.AbsolutePosition = function()
	return Vector2.zero
end
local BBG = spec("BillboardGui")
BBG.defaults.Size = UDim2.new()
BBG.defaults.StudsOffset = Vector3.zero
BBG.defaults.ExtentsOffset = Vector3.zero
BBG.defaults.AlwaysOnTop = false
BBG.defaults.MaxDistance = math.huge
BBG.defaults.LightInfluence = 1
BBG.getters.AbsoluteSize = function(_, data)
	local s = data.Size or BBG.defaults.Size
	return Vector2.new(s.X.Offset, s.Y.Offset)
end
BBG.getters.AbsolutePosition = function()
	return Vector2.zero
end

local GO = spec("GuiObject")
GO.defaults.Visible = true
GO.defaults.Size = UDim2.new()
GO.defaults.Position = UDim2.new()
GO.defaults.AnchorPoint = Vector2.zero
GO.defaults.BackgroundColor3 = Color3.fromRGB(163, 162, 165)
GO.defaults.BackgroundTransparency = 0
GO.defaults.BorderColor3 = Color3.fromRGB(27, 42, 53)
GO.defaults.BorderSizePixel = 1
GO.defaults.ZIndex = 1
GO.defaults.LayoutOrder = 0
GO.defaults.Rotation = 0
GO.defaults.ClipsDescendants = false
GO.defaults.Active = false
GO.defaults.Selectable = false
GO.defaults.AutomaticSize = Enum.AutomaticSize.None
GO.defaults.SizeConstraint = Enum.SizeConstraint.RelativeXY
signals("GuiObject", { "InputBegan", "InputEnded", "InputChanged", "MouseEnter", "MouseLeave", "MouseMoved", "TouchTap", "SelectionGained", "SelectionLost" })
local function parentAbs(data)
	local p = data._parent
	if not p then
		return Vector2.zero, Vector2.zero
	end
	local pd = rawget(p, "__data")
	if pd._cls.isA.GuiBase2d then
		return p.AbsoluteSize, p.AbsolutePosition
	end
	return Vector2.zero, Vector2.zero
end
GO.getters.AbsoluteSize = function(inst, data)
	local ps = parentAbs(data)
	local s = data.Size or GO.defaults.Size
	return Vector2.new(ps.X * s.X.Scale + s.X.Offset, ps.Y * s.Y.Scale + s.Y.Offset)
end
GO.getters.AbsolutePosition = function(inst, data)
	local ps, pp = parentAbs(data)
	local pos = data.Position or GO.defaults.Position
	local size = GO.getters.AbsoluteSize(inst, data)
	local a = data.AnchorPoint or Vector2.zero
	return Vector2.new(pp.X + ps.X * pos.X.Scale + pos.X.Offset - a.X * size.X, pp.Y + ps.Y * pos.Y.Scale + pos.Y.Offset - a.Y * size.Y)
end
GO.getters.AbsoluteRotation = function(_, data)
	return data.Rotation or 0
end
local function guiTween(inst, props, time, style, direction)
	local env = rawget(inst, "__data")._env
	local tw = env.services.TweenService:Create(inst, TweenInfo.new(time or 1, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out), props)
	tw:Play()
	return true
end
function GO.methods:TweenPosition(pos, direction, style, time)
	return guiTween(self, { Position = pos }, time, style, direction)
end
function GO.methods:TweenSize(size, direction, style, time)
	return guiTween(self, { Size = size }, time, style, direction)
end
function GO.methods:TweenSizeAndPosition(size, pos, direction, style, time)
	return guiTween(self, { Size = size, Position = pos }, time, style, direction)
end
local function textDefaults(className, text)
	local s = spec(className)
	s.defaults.Text = text
	s.defaults.TextSize = 14
	s.defaults.TextColor3 = Color3.fromRGB(27, 42, 53)
	s.defaults.TextTransparency = 0
	s.defaults.TextStrokeTransparency = 1
	s.defaults.TextStrokeColor3 = Color3.new()
	s.defaults.Font = Enum.Font.Legacy
	s.defaults.TextScaled = false
	s.defaults.TextWrapped = false
	s.defaults.RichText = false
	s.defaults.TextXAlignment = Enum.TextXAlignment.Center
	s.defaults.TextYAlignment = Enum.TextYAlignment.Center
	s.defaults.TextTruncate = Enum.TextTruncate.None
	s.defaults.LineHeight = 1
	s.defaults.MaxVisibleGraphemes = -1
	s.getters.TextBounds = function(_, data)
		local txt = tostring(data.Text or text)
		local size = data.TextSize or 14
		local lines = 1
		for _ in txt:gmatch("\n") do
			lines += 1
		end
		return Vector2.new(math.min(#txt, 200) * size * 0.5, size * lines)
	end
	s.getters.TextFits = function()
		return true
	end
	s.getters.ContentText = function(_, data)
		return data.Text or text
	end
end
textDefaults("TextLabel", "Label")
textDefaults("TextButton", "Button")
textDefaults("TextBox", "")
local GBt = spec("GuiButton")
GBt.defaults.AutoButtonColor = true
GBt.defaults.Modal = false
GBt.defaults.Selected = false
GBt.defaults.Active = true
signals("GuiButton", { "Activated", "MouseButton1Click", "MouseButton1Down", "MouseButton1Up", "MouseButton2Click", "MouseButton2Down", "MouseButton2Up" })
local TB = spec("TextBox")
TB.defaults.PlaceholderText = ""
TB.defaults.ClearTextOnFocus = true
TB.defaults.MultiLine = false
TB.defaults.TextEditable = true
signals("TextBox", { "FocusLost", "Focused", "ReturnPressedFromOnScreenKeyboard" })
function TB.methods:CaptureFocus()
	local d = rawget(self, "__data")
	d._env.focusedTextBox = self
	fireIf(d, "Focused")
end
function TB.methods:ReleaseFocus(submitted)
	local d = rawget(self, "__data")
	if d._env.focusedTextBox == self then
		d._env.focusedTextBox = nil
	end
	getSignal(d, "FocusLost"):Fire(submitted == true, nil)
end
function TB.methods:IsFocused()
	return rawget(self, "__data")._env.focusedTextBox == self
end
spec("ImageLabel").defaults.Image = ""
spec("ImageLabel").defaults.ImageTransparency = 0
spec("ImageLabel").defaults.ImageColor3 = Color3.new(1, 1, 1)
spec("ImageButton").defaults.Image = ""
spec("ImageButton").defaults.ImageTransparency = 0
local SF = spec("ScrollingFrame")
SF.defaults.CanvasSize = UDim2.new(0, 0, 2, 0)
SF.defaults.CanvasPosition = Vector2.zero
SF.defaults.ScrollBarThickness = 12
SF.defaults.ScrollingDirection = Enum.ScrollingDirection.XY
SF.defaults.ScrollingEnabled = true
SF.defaults.AutomaticCanvasSize = Enum.AutomaticSize.None
SF.defaults.ElasticBehavior = Enum.ElasticBehavior.WhenScrollable
SF.getters.AbsoluteCanvasSize = function(inst, data)
	local abs = GO.getters.AbsoluteSize(inst, data)
	local c = data.CanvasSize or SF.defaults.CanvasSize
	return Vector2.new(abs.X * c.X.Scale + c.X.Offset, abs.Y * c.Y.Scale + c.Y.Offset)
end
SF.getters.AbsoluteWindowSize = GO.getters.AbsoluteSize
local VF = spec("ViewportFrame")
VF.defaults.Ambient = Color3.fromRGB(200, 200, 200)
VF.defaults.LightColor = Color3.fromRGB(140, 140, 140)
VF.defaults.LightDirection = Vector3.new(-1, -1, -1)
spec("CanvasGroup").defaults.GroupTransparency = 0
local UIS_ = spec("UIScale")
UIS_.defaults.Scale = 1
spec("UICorner").defaults.CornerRadius = UDim.new(0, 8)
local UST = spec("UIStroke")
UST.defaults.Thickness = 1
UST.defaults.Color = Color3.new()
UST.defaults.Transparency = 0
UST.defaults.Enabled = true
local UPD = spec("UIPadding")
UPD.defaults.PaddingTop = UDim.new()
UPD.defaults.PaddingBottom = UDim.new()
UPD.defaults.PaddingLeft = UDim.new()
UPD.defaults.PaddingRight = UDim.new()
spec("UISizeConstraint").defaults.MinSize = Vector2.zero
spec("UISizeConstraint").defaults.MaxSize = Vector2.new(math.huge, math.huge)
spec("UIAspectRatioConstraint").defaults.AspectRatio = 1
spec("UIGradient").defaults.Enabled = true
spec("UIGradient").defaults.Rotation = 0
spec("UIGradient").defaults.Offset = Vector2.zero
local UGL = spec("UIGridStyleLayout")
UGL.defaults.SortOrder = Enum.SortOrder.LayoutOrder
UGL.defaults.FillDirection = Enum.FillDirection.Vertical
UGL.defaults.HorizontalAlignment = Enum.HorizontalAlignment.Left
UGL.defaults.VerticalAlignment = Enum.VerticalAlignment.Top
spec("UIListLayout").defaults.Padding = UDim.new()
spec("UIGridLayout").defaults.CellSize = UDim2.fromOffset(100, 100)
spec("UIGridLayout").defaults.CellPadding = UDim2.fromOffset(5, 5)
UGL.getters.AbsoluteContentSize = function(inst, data)
	local parent = data._parent
	if not parent then
		return Vector2.zero
	end
	local pAbs = parent:IsA("GuiBase2d") and parent.AbsoluteSize or Vector2.zero
	local items = {}
	for _, c in ipairs(parent:GetChildren()) do
		if c:IsA("GuiObject") and c.Visible then
			table.insert(items, c)
		end
	end
	if data.ClassName == "UIGridLayout" then
		local cell = data.CellSize or UDim2.fromOffset(100, 100)
		local pad = data.CellPadding or UDim2.fromOffset(5, 5)
		local cw = pAbs.X * cell.X.Scale + cell.X.Offset + pad.X.Offset
		local ch = pAbs.Y * cell.Y.Scale + cell.Y.Offset + pad.Y.Offset
		local perRow = math.max(1, math.floor((pAbs.X + pad.X.Offset) / math.max(cw, 1)))
		local rows = math.ceil(#items / perRow)
		return Vector2.new(math.min(#items, perRow) * cw, rows * ch)
	end
	local horizontal = data.FillDirection == Enum.FillDirection.Horizontal
	local pad = data.Padding or UDim.new()
	local main, cross = 0, 0
	for i, c in ipairs(items) do
		local s = c.AbsoluteSize
		main += horizontal and s.X or s.Y
		cross = math.max(cross, horizontal and s.Y or s.X)
		if i > 1 then
			main += pad.Offset + pad.Scale * (horizontal and pAbs.X or pAbs.Y)
		end
	end
	return horizontal and Vector2.new(main, cross) or Vector2.new(cross, main)
end
function UGL.methods:ApplyLayout() end

---------------------------------------------------------------- Tweens
local TW = spec("Tween")
TW.defaults.PlaybackState = Enum.PlaybackState.Begin
signals("Tween", { "Completed" })
local function finishTween(env, tw, state)
	local d = rawget(tw, "__data")
	for i, x in ipairs(env.tweens) do
		if x == tw then
			table.remove(env.tweens, i)
			break
		end
	end
	d.PlaybackState = state
	getSignal(d, "Completed"):Fire(state)
end
function TW.methods:Play()
	local d = rawget(self, "__data")
	local env = d._env
	if d.PlaybackState == Enum.PlaybackState.Playing then
		return
	end
	local info = d.TweenInfo
	local target = d.Instance
	if d.PlaybackState == Enum.PlaybackState.Paused and d._start then
		d._start = env.clock.precise - (d._pausedAt or 0)
	else
		-- Laufende Tweens auf denselben Eigenschaften werden abgebrochen (wie in Roblox)
		for _, other in ipairs(table.clone(env.tweens)) do
			local od = rawget(other, "__data")
			if od.Instance == target then
				for k in pairs(od._goals) do
					if d._goals[k] ~= nil then
						finishTween(env, other, Enum.PlaybackState.Cancelled)
						break
					end
				end
			end
		end
		d._from = {}
		for k in pairs(d._goals) do
			d._from[k] = target[k]
		end
		d._start = env.clock.precise + (info.DelayTime or 0)
	end
	d.PlaybackState = Enum.PlaybackState.Playing
	table.insert(env.tweens, self)
	if (info.Time or 0) <= 0 and (info.DelayTime or 0) <= 0 then
		updateTweens(env)
	end
end
function TW.methods:Pause()
	local d = rawget(self, "__data")
	local env = d._env
	if d.PlaybackState ~= Enum.PlaybackState.Playing then
		return
	end
	for i, x in ipairs(env.tweens) do
		if x == self then
			table.remove(env.tweens, i)
			break
		end
	end
	d._pausedAt = env.clock.precise - d._start
	d.PlaybackState = Enum.PlaybackState.Paused
end
function TW.methods:Cancel()
	local d = rawget(self, "__data")
	local env = d._env
	if d.PlaybackState == Enum.PlaybackState.Playing or d.PlaybackState == Enum.PlaybackState.Paused then
		local wasPlaying = d.PlaybackState == Enum.PlaybackState.Playing
		for i, x in ipairs(env.tweens) do
			if x == self then
				table.remove(env.tweens, i)
				break
			end
		end
		d.PlaybackState = Enum.PlaybackState.Cancelled
		getSignal(d, "Completed"):Fire(Enum.PlaybackState.Cancelled)
	end
end
local function tweenTotal(info)
	local cycle = (info.Time or 0) * (info.Reverses and 2 or 1)
	local rc = info.RepeatCount or 0
	if rc < 0 then
		return math.huge
	end
	return cycle * (rc + 1)
end
nextTweenEnd = function(env)
	local best
	for _, tw in ipairs(env.tweens) do
		local d = rawget(tw, "__data")
		local e = d._start + tweenTotal(d.TweenInfo)
		if not best or e < best then
			best = e
		end
	end
	return best
end
updateTweens = function(env)
	if #env.tweens == 0 then
		return
	end
	local now = env.clock.precise
	for _, tw in ipairs(table.clone(env.tweens)) do
		local d = rawget(tw, "__data")
		if d.PlaybackState == Enum.PlaybackState.Playing then
			local info = d.TweenInfo
			local elapsed = now - d._start
			if elapsed >= 0 then
				local time = info.Time or 0
				local total = tweenTotal(info)
				local target = d.Instance
				if elapsed >= total - 1e-9 then
					for k, goal in pairs(d._goals) do
						target[k] = info.Reverses and d._from[k] or goal
					end
					finishTween(env, tw, Enum.PlaybackState.Completed)
				else
					local cycle = time * (info.Reverses and 2 or 1)
					local e = cycle > 0 and elapsed % cycle or 0
					local alpha
					if e <= time then
						alpha = time > 0 and e / time or 1
					else
						alpha = 1 - (e - time) / time
					end
					local eased = easing(info.EasingStyle, info.EasingDirection, math.clamp(alpha, 0, 1))
					for k, goal in pairs(d._goals) do
						target[k] = lerpValue(d._from[k], goal, eased)
					end
				end
			end
		end
	end
end

---------------------------------------------------------------- Spieler
local PL = spec("Player")
PL.defaults.UserId = 0
PL.defaults.AccountAge = 365
PL.defaults.MembershipType = Enum.MembershipType.None
PL.defaults.LocaleId = "de-de"
PL.defaults.CanLoadCharacterAppearance = true
PL.defaults.AutoJumpEnabled = true
signals("Player", { "CharacterAdded", "CharacterRemoving", "CharacterAppearanceLoaded", "Chatted", "Idled", "OnTeleport" })
function PL.methods:Kick(msg)
	local d = rawget(self, "__data")
	d.kicked = msg or true
	local env = d._env
	if env.kickRemovesPlayer and d._parent then
		Mock.Leave(env, self)
	end
end
function PL.methods:GetMouse()
	local d = rawget(self, "__data")
	if not d._mouse then
		local m = newInstance(d._env, "PlayerMouse", "Mouse")
		local md = rawget(m, "__data")
		md.Hit = IDENTITY
		md.Origin = IDENTITY
		md.X = 0
		md.Y = 0
		md.Icon = ""
		md.ViewSizeX = d._env.viewport.X
		md.ViewSizeY = d._env.viewport.Y
		d._mouse = m
	end
	return d._mouse
end
signals("Mouse", { "Button1Down", "Button1Up", "Button2Down", "Button2Up", "Move", "WheelForward", "WheelBackward", "Idle" })
function PL.methods:LoadCharacter()
	return Mock.SpawnCharacter(rawget(self, "__data")._env, self)
end
function PL.methods:IsInGroup()
	return false
end
function PL.methods:GetRankInGroup()
	return 0
end
function PL.methods:GetRoleInGroup()
	return "Guest"
end
function PL.methods:HasAppearanceLoaded()
	return true
end
function PL.methods:GetJoinData()
	return {}
end
function PL.methods:GetFriendsOnline()
	return {}
end
function PL.methods:IsFriendsWith()
	return false
end
function PL.methods:GetNetworkPing()
	return 0.05
end

---------------------------------------------------------------- Dienste
local function service(className, fnTable)
	local s = spec(className)
	for k, v in pairs(fnTable or {}) do
		s.methods[k] = v
	end
	return s
end
local function envOf(inst)
	return rawget(inst, "__data")._env
end

-- DataModel (game)
local DM = spec("DataModel")
DM.defaults.PlaceId = 0
DM.defaults.GameId = 0
DM.defaults.PlaceVersion = 1
DM.defaults.CreatorId = 0
DM.defaults.CreatorType = Enum.CreatorType.User
signals("DataModel", { "Loaded", "Close" })
function DM.methods:GetService(name)
	local env = envOf(self)
	local s = env.services[name]
	if s then
		return s
	end
	if name == "Workspace" then
		return env.workspace
	end
	for _, known in ipairs(SERVICES) do
		if known == name then
			return Mock.CreateService(env, name)
		end
	end
	error("'" .. tostring(name) .. "' is not a valid Service name", 2)
end
function DM.methods:FindService(name)
	return envOf(self).services[name]
end
function DM.methods:BindToClose(fn)
	local d = rawget(self, "__data")
	d.closeCallbacks = d.closeCallbacks or {}
	table.insert(d.closeCallbacks, fn)
end
function DM.methods:IsLoaded()
	return true
end
function DM.methods:GetJobsInfo()
	return {}
end

-- Players
local PS = service("Players")
PS.defaults.MaxPlayers = 8
PS.defaults.RespawnTime = 5
PS.defaults.CharacterAutoLoads = true
signals("Players", { "PlayerAdded", "PlayerRemoving", "PlayerMembershipChanged" })
PS.getters.LocalPlayer = function(inst, data)
	local ctx = currentCtx(data._env)
	return ctx.player
end
function PS.methods:GetPlayers()
	local out = {}
	for _, p in ipairs(envOf(self).players) do
		if p.Parent ~= nil then
			table.insert(out, p)
		end
	end
	return out
end
function PS.methods:GetPlayerByUserId(id)
	for _, p in ipairs(envOf(self).players) do
		if p.UserId == id and p.Parent ~= nil then
			return p
		end
	end
	return nil
end
function PS.methods:GetPlayerFromCharacter(ch)
	for _, p in ipairs(envOf(self).players) do
		if p.Character == ch and ch ~= nil then
			return p
		end
	end
	return nil
end
function PS.methods:GetNameFromUserIdAsync(id)
	return "Nutzer" .. tostring(id)
end
function PS.methods:GetUserIdFromNameAsync(name)
	return tonumber(tostring(name):match("%d+")) or 1
end
function PS.methods:GetUserThumbnailAsync()
	return "", true
end
function PS.methods:GetFriendsAsync()
	return { GetCurrentPage = function()
		return {}
	end, IsFinished = true }
end

-- Lighting
local LI = service("Lighting")
LI.defaults.ClockTime = 14
LI.defaults.Brightness = 2
LI.defaults.GeographicLatitude = 41.7
LI.defaults.Ambient = Color3.fromRGB(0, 0, 0)
LI.defaults.OutdoorAmbient = Color3.fromRGB(128, 128, 128)
LI.defaults.FogEnd = 100000
LI.defaults.FogStart = 0
LI.defaults.FogColor = Color3.fromRGB(192, 192, 192)
LI.defaults.GlobalShadows = true
LI.defaults.ExposureCompensation = 0
LI.setters.ClockTime = function(inst, data, v)
	rawSet(inst, data, "ClockTime", (tonumber(v) or 0) % 24)
end
LI.getters.TimeOfDay = function(inst, data)
	local c = data.ClockTime or 14
	local h = math.floor(c)
	local m = math.floor((c - h) * 60)
	local s = math.floor(((c - h) * 60 - m) * 60)
	return string.format("%02d:%02d:%02d", h, m, s)
end
LI.setters.TimeOfDay = function(inst, data, v)
	local h, m, s = tostring(v):match("(%d+):(%d+):?(%d*)")
	rawSet(inst, data, "ClockTime", ((tonumber(h) or 0) + (tonumber(m) or 0) / 60 + (tonumber(s) or 0) / 3600) % 24)
end
function LI.methods:GetMinutesAfterMidnight()
	return (self.ClockTime or 14) * 60
end
function LI.methods:SetMinutesAfterMidnight(m)
	self.ClockTime = m / 60
end
function LI.methods:GetSunDirection()
	return Vector3.new(0, 1, 0)
end

-- TweenService
service("TweenService", {
	Create = function(self, inst, info, goals)
		local env = envOf(self)
		assert(isInstance(inst), "TweenService:Create: Argument 1 muss eine Instanz sein")
		assert(type(info) == "table" and info.__type == "TweenInfo", "TweenService:Create: TweenInfo erwartet")
		assert(type(goals) == "table", "TweenService:Create: Ziel-Tabelle erwartet")
		for k, v in pairs(goals) do
			local cur = inst[k]
			if cur ~= nil and typeOf(cur) ~= typeOf(v) then
				error("TweenService:Create: Eigenschaft " .. tostring(k) .. " hat Typ " .. typeOf(cur) .. ", Ziel " .. typeOf(v), 2)
			end
		end
		local tw = newInstance(env, "Tween", "Tween")
		env.instanceCount -= 1 -- Tweens hängen nicht im Baum; instanceCount zählt nur Baum-Instanzen
		local d = rawget(tw, "__data")
		d.Instance = inst
		d.TweenInfo = info
		d._goals = table.clone(goals)
		return tw
	end,
	GetValue = function(_, alpha, style, direction)
		return easing(style, direction, alpha)
	end,
	SmoothDamp = function(_, current, target, velocity)
		return target, velocity
	end,
})

-- RunService
local RS = service("RunService")
signals("RunService", { "Heartbeat", "RenderStepped", "Stepped", "PreRender", "PreSimulation", "PostSimulation", "PreAnimation" })
function RS.methods:IsStudio()
	return envOf(self).studio == true
end
function RS.methods:IsServer()
	return currentCtx(envOf(self)).side ~= "client"
end
function RS.methods:IsClient()
	return currentCtx(envOf(self)).side == "client"
end
function RS.methods:IsRunning()
	return true
end
function RS.methods:IsRunMode()
	return false
end
function RS.methods:IsEdit()
	return false
end
function RS.methods:BindToRenderStep(name, priority, fn)
	local env = envOf(self)
	env.renderSteps[name] = { priority = priority, fn = fn, ctx = currentCtx(env) }
end
function RS.methods:UnbindFromRenderStep(name)
	envOf(self).renderSteps[name] = nil
end

-- HttpService
local HS = service("HttpService")
HS.defaults.HttpEnabled = false
function HS.methods:GenerateGUID(wrap)
	local env = envOf(self)
	env.guid += 1
	local n = env.guid
	local s = string.format("%08X-%04X-4%03X-8%03X-%012X", (n * 2654435761) % 4294967296, n % 65536, n % 4096, (n * 7) % 4096, n)
	if wrap == false then
		return s
	end
	return "{" .. s .. "}"
end
local function jsonEncode(v, seen)
	local t = type(v)
	if t == "nil" then
		return "null"
	elseif t == "boolean" then
		return v and "true" or "false"
	elseif t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.17g", v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			local map = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
			return map[c] or string.format("\\u%04x", c:byte())
		end) .. '"'
	elseif t == "table" then
		seen = seen or {}
		assert(not seen[v], "JSONEncode: zyklische Tabelle")
		seen[v] = true
		local out = {}
		if #v > 0 or next(v) == nil then
			for _, x in ipairs(v) do
				table.insert(out, jsonEncode(x, seen))
			end
			seen[v] = nil
			return "[" .. table.concat(out, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			local x = v[k]
			if x == nil then
				x = v[tonumber(k)]
			end
			table.insert(out, jsonEncode(k) .. ":" .. jsonEncode(x, seen))
		end
		seen[v] = nil
		return "{" .. table.concat(out, ",") .. "}"
	end
	error("JSONEncode: Typ " .. t .. " nicht unterstützt")
end
local function jsonDecode(s)
	local i = 1
	local function ws()
		i = s:find("[^ \t\r\n]", i) or (#s + 1)
	end
	local value
	local function str()
		local out = {}
		i += 1
		while true do
			local c = s:sub(i, i)
			if c == "" then
				error("JSONDecode: String nicht beendet")
			elseif c == '"' then
				i += 1
				return table.concat(out)
			elseif c == "\\" then
				local n = s:sub(i + 1, i + 1)
				local map = { n = "\n", r = "\r", t = "\t", b = "\b", f = "\f", ["/"] = "/", ["\\"] = "\\", ['"'] = '"' }
				if n == "u" then
					local code = tonumber(s:sub(i + 2, i + 5), 16)
					table.insert(out, utf8.char(code))
					i += 6
				else
					table.insert(out, map[n] or n)
					i += 2
				end
			else
				table.insert(out, c)
				i += 1
			end
		end
	end
	value = function()
		ws()
		local c = s:sub(i, i)
		if c == "{" then
			local obj = {}
			i += 1
			ws()
			if s:sub(i, i) == "}" then
				i += 1
				return obj
			end
			while true do
				ws()
				local k = str()
				ws()
				assert(s:sub(i, i) == ":", "JSONDecode: ':' erwartet")
				i += 1
				obj[k] = value()
				ws()
				local d = s:sub(i, i)
				i += 1
				if d == "}" then
					return obj
				end
				assert(d == ",", "JSONDecode: ',' erwartet")
			end
		elseif c == "[" then
			local arr = {}
			i += 1
			ws()
			if s:sub(i, i) == "]" then
				i += 1
				return arr
			end
			while true do
				table.insert(arr, value())
				ws()
				local d = s:sub(i, i)
				i += 1
				if d == "]" then
					return arr
				end
				assert(d == ",", "JSONDecode: ',' erwartet")
			end
		elseif c == '"' then
			return str()
		elseif s:sub(i, i + 3) == "true" then
			i += 4
			return true
		elseif s:sub(i, i + 4) == "false" then
			i += 5
			return false
		elseif s:sub(i, i + 3) == "null" then
			i += 4
			return nil
		end
		local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
		assert(num and #num > 0, "JSONDecode: ungültiges Zeichen bei " .. i)
		i += #num
		return tonumber(num)
	end
	local v = value()
	return v
end
Mock.JSONDecode = jsonDecode
Mock.JSONEncode = jsonEncode
function HS.methods:JSONEncode(v)
	return jsonEncode(v)
end
function HS.methods:JSONDecode(s)
	return jsonDecode(s)
end
function HS.methods:UrlEncode(s)
	return (tostring(s):gsub("[^%w%-_%.~]", function(c)
		return string.format("%%%02X", c:byte())
	end))
end
function HS.methods:GetAsync()
	error("Http requests are not enabled. Enable via game settings", 2)
end
HS.methods.PostAsync = HS.methods.GetAsync
HS.methods.RequestAsync = HS.methods.GetAsync

-- StarterGui (Core-GUI je Kontext)
local STG = service("StarterGui")
STG.defaults.ShowDevelopmentGui = true
local function coreState(inst)
	local env = envOf(inst)
	local ctx = currentCtx(env)
	ctx.core = ctx.core or { enabled = {}, values = {} }
	return ctx.core
end
function STG.methods:SetCoreGuiEnabled(kind, enabled)
	coreState(self).enabled[kind] = enabled == true
end
function STG.methods:GetCoreGuiEnabled(kind)
	local v = coreState(self).enabled[kind]
	if v == nil then
		return true
	end
	return v
end
function STG.methods:SetCore(name, value)
	coreState(self).values[name] = value
end
function STG.methods:GetCore(name)
	local v = coreState(self).values[name]
	if v == nil and name == "ChatActive" then
		return false
	end
	return v
end

-- GuiService
local GS = service("GuiService")
GS.defaults.TouchControlsEnabled = true
GS.defaults.MenuIsOpen = false
signals("GuiService", { "MenuOpened", "MenuClosed" })
function GS.methods:GetGuiInset()
	local inset = envOf(self).guiInset
	return Vector2.new(0, inset), Vector2.zero
end
function GS.methods:IsTenFootInterface()
	return false
end

-- UserInputService (Zustand je Client-Kontext)
local UI = service("UserInputService")
UI.defaults.TouchEnabled = false
UI.defaults.KeyboardEnabled = true
UI.defaults.MouseEnabled = true
UI.defaults.GamepadEnabled = false
UI.defaults.VREnabled = false
UI.defaults.MouseBehavior = Enum.MouseBehavior.Default
UI.defaults.MouseIconEnabled = true
signals("UserInputService", { "InputBegan", "InputEnded", "InputChanged", "TouchStarted", "TouchEnded", "TouchTap", "JumpRequest", "LastInputTypeChanged", "WindowFocused", "WindowFocusReleased", "TextBoxFocused", "TextBoxFocusReleased", "GamepadConnected", "GamepadDisconnected" })
local function clientOf(env)
	local ctx = currentCtx(env)
	return ctx.player and env.clients[ctx.player]
end
function UI.methods:GetFocusedTextBox()
	local env = envOf(self)
	local tb = env.focusedTextBox
	if tb and tb.Parent then
		return tb
	end
	return nil
end
function UI.methods:IsKeyDown(key)
	local c = clientOf(envOf(self))
	return c ~= nil and c.keysDown[key] == true
end
function UI.methods:IsMouseButtonPressed(button)
	local c = clientOf(envOf(self))
	return c ~= nil and c.keysDown[button] == true
end
function UI.methods:GetKeysPressed()
	return {}
end
function UI.methods:GetMouseLocation()
	return Vector2.new(0, 0)
end
function UI.methods:GetLastInputType()
	return Enum.UserInputType.Keyboard
end
function UI.methods:GetConnectedGamepads()
	return {}
end
function UI.methods:GetStringForKeyCode(key)
	return key and key.Name or ""
end

-- ContextActionService (Bindungen je Kontext)
local CA = service("ContextActionService")
signals("ContextActionService", { "LocalToolEquipped", "LocalToolUnequipped" })
local function bind(self, name, fn, createTouch, priority, ...)
	local env = envOf(self)
	local inputs = {}
	for i = 1, select("#", ...) do
		inputs[select(i, ...)] = true
	end
	env.casSeq += 1
	env.casBindings[name] = { name = name, fn = fn, priority = priority, inputs = inputs, ctx = currentCtx(env), order = env.casSeq }
end
function CA.methods:BindAction(name, fn, createTouch, ...)
	bind(self, name, fn, createTouch, 2000, ...)
end
function CA.methods:BindActionAtPriority(name, fn, createTouch, priority, ...)
	bind(self, name, fn, createTouch, priority, ...)
end
function CA.methods:UnbindAction(name)
	envOf(self).casBindings[name] = nil
end
function CA.methods:UnbindAllActions()
	envOf(self).casBindings = {}
end
function CA.methods:GetAllBoundActionInfo()
	local out = {}
	for name, b in pairs(envOf(self).casBindings) do
		out[name] = { priority = b.priority }
	end
	return out
end
function CA.methods:GetBoundActionInfo(name)
	local b = envOf(self).casBindings[name]
	return b and { priority = b.priority } or {}
end
function CA.methods:SetTitle() end
function CA.methods:SetDescription() end
function CA.methods:SetImage() end
function CA.methods:SetPosition() end
function CA.methods:GetButton()
	return nil
end

-- ProximityPromptService
local PPS = service("ProximityPromptService")
PPS.defaults.Enabled = true
PPS.defaults.MaxPromptsVisible = 16
signals("ProximityPromptService", { "PromptShown", "PromptHidden", "PromptTriggered", "PromptTriggerEnded", "PromptButtonHoldBegan", "PromptButtonHoldEnded" })

-- CollectionService
local CS = service("CollectionService")
function CS.methods:GetTagged(tag)
	local env = envOf(self)
	local out = {}
	for _, x in ipairs(env.game:GetDescendants()) do
		if x:HasTag(tag) then
			table.insert(out, x)
		end
	end
	return out
end
function CS.methods:AddTag(inst, tag)
	inst:AddTag(tag)
end
function CS.methods:RemoveTag(inst, tag)
	inst:RemoveTag(tag)
end
function CS.methods:HasTag(inst, tag)
	return inst:HasTag(tag)
end
function CS.methods:GetTags(inst)
	return inst:GetTags()
end
function CS.methods:GetInstanceAddedSignal(tag)
	return getSignal(rawget(self, "__data"), "TagAdded:" .. tag)
end
function CS.methods:GetInstanceRemovedSignal(tag)
	return getSignal(rawget(self, "__data"), "TagRemoved:" .. tag)
end

-- Debris
service("Debris", {
	AddItem = function(self, inst, lifetime)
		local env = envOf(self)
		env.scheduler:delay(lifetime or 10, function()
			if inst and not rawget(inst, "__data")._destroyed then
				inst:Destroy()
			end
		end)
	end,
})

-- TextService
service("TextService", {
	GetTextSize = function(_, text, size, font, frame)
		local lines = 1
		for _ in tostring(text):gmatch("\n") do
			lines += 1
		end
		return Vector2.new(math.min(#tostring(text) * size * 0.5, frame and frame.X or math.huge), size * lines)
	end,
	FilterStringAsync = function(_, text)
		return {
			GetNonChatStringForBroadcastAsync = function()
				return text
			end,
			GetNonChatStringForUserAsync = function()
				return text
			end,
		}
	end,
})

-- SoundService
service("SoundService", { PlayLocalSound = function() end })

-- PolicyService / Sonstiges
service("PolicyService", {
	GetPolicyInfoForPlayerAsync = function()
		return { AreAdsAllowed = true, ArePaidRandomItemsRestricted = false, AllowedExternalLinkReferences = {}, IsPaidItemTradingAllowed = true, IsSubjectToChinaPolicies = false }
	end,
})
service("AnalyticsService", { LogCustomEvent = function() end, LogEconomyEvent = function() end, LogProgressionEvent = function() end, LogOnboardingFunnelStepEvent = function() end, LogFunnelStepEvent = function() end })
service("BadgeService", { AwardBadge = function()
	return true
end, UserHasBadgeAsync = function()
	return false
end, GetBadgeInfoAsync = function()
	return { IsEnabled = false }
end })
service("MessagingService", { PublishAsync = function() end, SubscribeAsync = function()
	return { Disconnect = function() end }
end })
service("LocalizationService").defaults.RobloxLocaleId = "de-de"
service("LocalizationService").defaults.SystemLocaleId = "de-de"
service("Teams", { GetTeams = function()
	return {}
end })
service("PhysicsService", { RegisterCollisionGroup = function() end, CollisionGroupSetCollidable = function() end, SetPartCollisionGroup = function() end, IsCollisionGroupRegistered = function()
	return true
end })

---------------------------------------------------------------- DataStores (mit Fehlerinjektion)
local function copyValue(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[copyValue(k)] = copyValue(x)
	end
	return o
end
-- Wie Roblox: nur JSON-fähige Werte (keine NaN/inf, keine gemischten oder löchrigen Tabellen, keine Instanzen)
local function checkStorable(v, path, depth)
	local t = type(v)
	if t == "nil" or t == "boolean" or t == "string" then
		return
	end
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			error("DataStore: " .. path .. " ist NaN oder unendlich und kann nicht gespeichert werden", 0)
		end
		return
	end
	if t ~= "table" or getmetatable(v) ~= nil or rawget(v, "__data") or rawget(v, "__type") then
		error("DataStore: " .. path .. " hat den nicht speicherbaren Typ " .. typeOf(v), 0)
	end
	if depth > 100 then
		error("DataStore: " .. path .. " ist zu tief verschachtelt", 0)
	end
	local n = #v
	local hasString, hasNumber = false, false
	for k, x in pairs(v) do
		if type(k) == "string" then
			hasString = true
		elseif type(k) == "number" then
			hasNumber = true
			if k ~= math.floor(k) or k < 1 or k > n then
				error("DataStore: " .. path .. " hat den Zahlenschlüssel " .. tostring(k) .. " außerhalb eines lückenlosen Arrays", 0)
			end
		else
			error("DataStore: " .. path .. " hat einen Schlüssel vom Typ " .. type(k), 0)
		end
		checkStorable(x, path .. "." .. tostring(k), depth + 1)
	end
	if hasString and hasNumber then
		error("DataStore: " .. path .. " mischt Array- und Text-Schlüssel", 0)
	end
end
Mock.CheckStorable = function(v)
	checkStorable(v, "Wert", 0)
end

local function makeDataStoreService(env)
	local svc = newInstance(env, "DataStoreService", "DataStoreService")
	local d = rawget(svc, "__data")
	d.stores = {}
	d.ordered = {}
	d.fail = false -- true: alle Aufrufe werfen Fehler
	d.failNext = 0 -- die nächsten n Aufrufe werfen Fehler
	d.getFail = false -- true: GetDataStore wirft (Studio ohne API-Zugriff)
	d.calls = { update = 0, set = 0, sorted = 0, get = 0 }
	d.updateYield = 0 -- Sekunden Latenz pro UpdateAsync/GetAsync/SetAsync
	d.strict = true -- Roblox-Regeln für speicherbare Werte prüfen
	d.log = {} -- {op, store, key, t}
	d.copy = copyValue
	local function failing()
		if d.fail then
			return true
		end
		if d.failNext > 0 then
			d.failNext -= 1
			return true
		end
		return false
	end
	local function latency()
		if d.updateYield > 0 then
			env.scheduler:wait(d.updateYield)
		end
	end
	d.GetDataStore = function(_, name, scope)
		if d.getFail then
			error("You must publish this place to the web to access DataStore.")
		end
		local key = name .. (scope and ("/" .. scope) or "")
		d.stores[key] = d.stores[key] or { data = {}, name = name }
		local store = d.stores[key]
		return {
			UpdateAsync = function(_, k, fn)
				d.calls.update += 1
				table.insert(d.log, { op = "update", store = key, key = k, t = env.clock.wall })
				latency()
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				local result = fn(copyValue(store.data[k]), nil)
				if result ~= nil then
					if d.strict then
						checkStorable(result, k, 0)
					end
					store.data[k] = copyValue(result)
				end
				return copyValue(result), nil
			end,
			GetAsync = function(_, k)
				d.calls.get += 1
				latency()
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				return copyValue(store.data[k]), nil
			end,
			SetAsync = function(_, k, value)
				d.calls.set += 1
				latency()
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				if d.strict then
					checkStorable(value, k, 0)
				end
				store.data[k] = copyValue(value)
				return "v1"
			end,
			RemoveAsync = function(_, k)
				latency()
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				local old = store.data[k]
				store.data[k] = nil
				return copyValue(old)
			end,
			IncrementAsync = function(_, k, delta)
				latency()
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				store.data[k] = (tonumber(store.data[k]) or 0) + (delta or 1)
				return store.data[k]
			end,
			data = store.data,
		}
	end
	d.GetOrderedDataStore = function(_, name)
		if d.getFail then
			error("You must publish this place to the web to access DataStore.")
		end
		d.ordered[name] = d.ordered[name] or { data = {} }
		local store = d.ordered[name]
		return {
			SetAsync = function(_, key, value)
				d.calls.set += 1
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				assert(type(value) == "number" and value == math.floor(value), "OrderedDataStore: nur Ganzzahlen")
				assert(value < 2 ^ 63, "OrderedDataStore: Wert zu groß")
				store.data[key] = value
			end,
			UpdateAsync = function(_, key, fn)
				d.calls.update += 1
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				local v = fn(store.data[key])
				if v ~= nil then
					assert(type(v) == "number" and v == math.floor(v), "OrderedDataStore: nur Ganzzahlen")
					store.data[key] = v
				end
				return v
			end,
			GetAsync = function(_, key)
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				return store.data[key]
			end,
			IncrementAsync = function(_, key, delta)
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				store.data[key] = (store.data[key] or 0) + (delta or 1)
				return store.data[key]
			end,
			RemoveAsync = function(_, key)
				store.data[key] = nil
			end,
			GetSortedAsync = function(_, ascending, pageSize)
				d.calls.sorted += 1
				if failing() then
					error("DataStore-Fehler (Mock)")
				end
				local list = {}
				for k, v in pairs(store.data) do
					table.insert(list, { key = k, value = v })
				end
				table.sort(list, function(a, b)
					if a.value == b.value then
						return tostring(a.key) < tostring(b.key)
					end
					if ascending then
						return a.value < b.value
					end
					return a.value > b.value
				end)
				local pageIndex = 1
				local pages = {}
				local function slice()
					local out = {}
					for i = (pageIndex - 1) * pageSize + 1, math.min(#list, pageIndex * pageSize) do
						table.insert(out, list[i])
					end
					return out
				end
				pages.IsFinished = #list <= pageSize
				function pages:GetCurrentPage()
					return slice()
				end
				function pages:AdvanceToNextPageAsync()
					pageIndex += 1
					pages.IsFinished = #list <= pageIndex * pageSize
				end
				return pages
			end,
			data = store.data,
		}
	end
	d.GetRequestBudgetForRequestType = function()
		return 100
	end
	d.GetGlobalDataStore = function(self2)
		return d.GetDataStore(self2, "__global")
	end
	return svc
end

local function makeMarketplace(env)
	local svc = newInstance(env, "MarketplaceService", "MarketplaceService")
	local d = rawget(svc, "__data")
	d.owned = {}
	d.prompts = {}
	d.products = {} -- [productId] = Info-Tabelle für GetProductInfoAsync
	d.yield = 0 -- Sekunden Latenz (echte Aufrufe warten)
	d.UserOwnsGamePassAsync = function(_, userId, passId)
		if d.yield > 0 then
			env.scheduler:wait(d.yield)
		end
		return d.owned[userId .. ":" .. passId] == true
	end
	d.PromptGamePassPurchase = function(_, player, passId)
		table.insert(d.prompts, { player = player, passId = passId })
	end
	d.PromptProductPurchase = function(_, player, productId)
		table.insert(d.prompts, { player = player, productId = productId })
	end
	d.PromptPurchase = function(_, player, assetId)
		table.insert(d.prompts, { player = player, assetId = assetId })
	end
	d.GetProductInfoAsync = function(_, id, infoType)
		if d.yield > 0 then
			env.scheduler:wait(d.yield)
		end
		if type(id) ~= "number" or id <= 0 then
			error("MarketplaceService:GetProductInfoAsync: ungültige Id " .. tostring(id))
		end
		local info = d.products[id]
		if info then
			return copyValue(info)
		end
		return { ProductId = id, Name = "Produkt " .. id, Description = "", PriceInRobux = 100, IsForSale = true }
	end
	d.PlayerOwnsAsset = function()
		return false
	end
	return svc
end
signals("MarketplaceService", { "PromptGamePassPurchaseFinished", "PromptProductPurchaseFinished", "PromptPurchaseFinished", "PromptBundlePurchaseFinished" })

---------------------------------------------------------------- Frames (RunService, Prompt-Sichtbarkeit)
local function promptPart(prompt)
	local p = prompt.Parent
	if not p then
		return nil
	end
	if isBasePart(p) then
		return p.Position
	end
	if p:IsA("Attachment") then
		return p.WorldPosition
	end
	if p:IsA("Model") then
		return p:GetPivot().Position
	end
	return nil
end
Mock.PromptPosition = promptPart

-- Welche Prompts sieht dieser Spieler gerade? (Enabled, im Workspace, in Reichweite)
function Mock.VisiblePrompts(env, player)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local out = {}
	if not root then
		return out
	end
	local rp = root.Position
	for prompt in pairs(env.prompts) do
		local pd = rawget(prompt, "__data")
		if not pd._destroyed and prompt.Enabled and prompt:IsDescendantOf(env.workspace) then
			local pos = promptPart(prompt)
			if pos and (pos - rp).Magnitude <= prompt.MaxActivationDistance then
				out[prompt] = true
			end
		end
	end
	return out
end

-- Aktualisiert PromptShown/PromptHidden für den Client dieses Spielers
function Mock.UpdatePrompts(env, player)
	local client = env.clients[player]
	if not client then
		return
	end
	local visible = Mock.VisiblePrompts(env, player)
	local pps = env.services.ProximityPromptService
	for prompt in pairs(client.shownPrompts) do
		if not visible[prompt] then
			client.shownPrompts[prompt] = nil
			getSignal(rawget(pps, "__data"), "PromptHidden"):FireFor(player, prompt)
			getSignal(rawget(prompt, "__data"), "PromptHidden"):FireFor(player)
		end
	end
	for prompt in pairs(visible) do
		if not client.shownPrompts[prompt] then
			client.shownPrompts[prompt] = true
			getSignal(rawget(pps, "__data"), "PromptShown"):FireFor(player, prompt, Enum.ProximityPromptInputType.Keyboard)
			getSignal(rawget(prompt, "__data"), "PromptShown"):FireFor(player, Enum.ProximityPromptInputType.Keyboard)
		end
	end
end

runFrame = function(env, dt)
	local rs = env.services.RunService
	if rs then
		local rd = rawget(rs, "__data")
		fireIf(rd, "Stepped", env.clock.precise - 1000, dt)
		fireIf(rd, "PreSimulation", dt)
		fireIf(rd, "PostSimulation", dt)
		fireIf(rd, "Heartbeat", dt)
		fireIf(rd, "PreRender", dt)
		fireIf(rd, "RenderStepped", dt)
		for _, b in pairs(env.renderSteps) do
			env.scheduler:spawnIn(b.ctx, b.fn, dt)
		end
	end
	for player in pairs(env.clients) do
		if player.Parent then
			Mock.UpdatePrompts(env, player)
		end
	end
end

---------------------------------------------------------------- Umgebung
function Mock.CreateService(env, name)
	if env.services[name] then
		return env.services[name]
	end
	local inst
	if name == "DataStoreService" then
		inst = makeDataStoreService(env)
	elseif name == "MarketplaceService" then
		inst = makeMarketplace(env)
	else
		inst = newInstance(env, name, name)
	end
	rawget(inst, "__data").Name = name
	inst.Parent = env.game
	env.services[name] = inst
	return inst
end

function Mock.NewEnv(opts)
	opts = opts or {}
	local env = {
		players = {},
		instanceCount = 0,
		nextId = 0,
		modules = {},
		moduleCaches = {},
		sources = {},
		warnings = {},
		output = {},
		prompts = setmetatable({}, { __mode = "k" }),
		tweens = {},
		clients = {},
		renderSteps = {},
		casBindings = {},
		casSeq = 0,
		guid = 0,
		treeWatchers = 0,
		frameStep = opts.frameStep or 0.25,
		viewport = opts.viewport or Vector2.new(1280, 800),
		guiInset = 36,
		echoErrors = opts.echoErrors == true,
		kickRemovesPlayer = opts.kickRemovesPlayer == true,
	}
	env.moduleCaches.server = env.modules
	env.clock = Clock.new(opts.startTime)
	env.clock.env = env
	env.scheduler = Scheduler.new(env.clock, env)
	env.clock.scheduler = env.scheduler
	env.nextFrame = env.clock.precise + env.frameStep
	env.serverCtx = { env = env, side = "server", name = "Server" }
	env.mainCtx = env.serverCtx
	env.studio = opts.studio == true

	local game = newInstance(env, "DataModel", "game")
	rawget(game, "__data").JobId = opts.jobId or "job-A"
	rawget(game, "__data").closeCallbacks = {}
	env.game = game
	env.services = {}
	local ws = newInstance(env, "Workspace", "Workspace")
	ws.Parent = game
	env.services.Workspace = ws
	env.workspace = ws
	local terrain = newInstance(env, "Terrain", "Terrain")
	rawget(terrain, "__data").Anchored = true
	rawAttach(terrain, ws)
	for _, name in ipairs({ "Players", "Lighting", "ReplicatedStorage", "ReplicatedFirst", "ServerStorage", "ServerScriptService", "StarterPlayer", "StarterGui", "StarterPack", "SoundService", "RunService", "GuiService", "TweenService", "HttpService", "DataStoreService", "MarketplaceService", "UserInputService", "ContextActionService", "ProximityPromptService", "CollectionService", "Teams" }) do
		Mock.CreateService(env, name)
	end

	env.Instance = {
		new = function(className, parent)
			assert(type(className) == "string", "Instance.new: Klassenname erwartet")
			local inst = newInstance(env, className)
			if parent then
				inst.Parent = parent
			end
			return inst
		end,
		fromExisting = function(inst)
			return inst:Clone()
		end,
	}
	env.task = {
		wait = function(s)
			return env.scheduler:wait(s)
		end,
		spawn = function(fn, ...)
			return env.scheduler:spawn(fn, ...)
		end,
		defer = function(fn, ...)
			return env.scheduler:delay(0, fn, ...)
		end,
		delay = function(s, fn, ...)
			return env.scheduler:delay(s, fn, ...)
		end,
		cancel = function(co)
			env.scheduler:cancel(co)
		end,
		synchronize = function() end,
		desynchronize = function() end,
	}
	env.os = setmetatable({
		time = function(t)
			if t then
				return realOs.time(t)
			end
			return env.clock.now
		end,
		clock = function()
			return env.clock.precise
		end,
		date = function(fmt, t)
			return realOs.date(fmt, t or env.clock.now)
		end,
		difftime = function(a, b)
			return a - (b or 0)
		end,
	}, { __index = realOs })
	env.DateTime = {
		now = function()
			return plain("DateTime", { UnixTimestamp = env.clock.now, UnixTimestampMillis = math.floor(env.clock.wall * 1000) })
		end,
		fromUnixTimestamp = function(t)
			return plain("DateTime", { UnixTimestamp = t, UnixTimestampMillis = t * 1000 })
		end,
		fromUnixTimestampMillis = function(t)
			return plain("DateTime", { UnixTimestamp = math.floor(t / 1000), UnixTimestampMillis = t })
		end,
	}
	-- Globals der Skripte dieser Umgebung
	local G = {
		game = game,
		Game = game,
		workspace = ws,
		Workspace = ws,
		Instance = env.Instance,
		task = env.task,
		os = env.os,
		DateTime = env.DateTime,
		shared = {},
		tick = function()
			return env.clock.wall
		end,
		time = function()
			return env.clock.precise - 1000
		end,
		elapsedTime = function()
			return env.clock.precise - 1000
		end,
		wait = function(s)
			local elapsed = env.scheduler:wait(s or 0.03)
			return elapsed, env.clock.precise - 1000
		end,
		spawn = function(fn)
			env.scheduler:delay(0, fn)
		end,
		delay = function(s, fn)
			env.scheduler:delay(s, fn)
		end,
		warn = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(env.warnings, table.concat(parts, " "))
		end,
		print = function(...)
			local parts = {}
			for i = 1, select("#", ...) do
				parts[i] = tostring((select(i, ...)))
			end
			table.insert(env.output, table.concat(parts, " "))
			if env.echoPrint then
				print(...)
			end
		end,
		typeof = typeOf,
		require = function(module)
			return Mock.Require(env, module)
		end,
		settings = function()
			return { Rendering = { QualityLevel = 1 }, Physics = {}, Network = {} }
		end,
		UserSettings = function()
			return { GetService = function()
				return { SavedQualityLevel = Enum.SavedQualitySetting.Automatic }
			end }
		end,
	}
	for k, v in pairs(Mock.Globals) do
		if G[k] == nil then
			G[k] = v
		end
	end
	env.G = setmetatable(G, { __index = _G })
	return env
end

-- Datentyp-Globals (identisch in allen Umgebungen)
Mock.Globals = {
	Enum = Enum, Vector3 = Vector3, Vector2 = Vector2, CFrame = CFrame, Color3 = Color3, UDim = UDim, UDim2 = UDim2,
	TweenInfo = TweenInfo, Random = Random, NumberRange = NumberRange, NumberSequence = NumberSequence,
	NumberSequenceKeypoint = NumberSequenceKeypoint, ColorSequence = ColorSequence,
	ColorSequenceKeypoint = ColorSequenceKeypoint, Rect = Rect, Ray = Ray, BrickColor = BrickColor,
	PhysicalProperties = PhysicalProperties, Font = Font, RaycastParams = RaycastParams, OverlapParams = OverlapParams,
}

-- Setzt die globalen Roblox-Namen (für Testcode im Hauptthread) auf diese Umgebung
function Mock.Activate(env)
	_G.game = env.game
	_G.workspace = env.workspace
	_G.Instance = env.Instance
	_G.task = env.task
	for k, v in pairs(Mock.Globals) do
		_G[k] = v
	end
	_G.warn = env.G.warn
	_G.typeof = typeOf
	_G.require = env.G.require
	_G.os = env.os
	_G.tick = env.G.tick
	_G.DateTime = env.DateTime
	Mock.Current = env
end

local function compile(env, inst, what)
	local d = rawget(inst, "__data")
	local chunk = d.path or inst:GetFullName()
	local fn, err = loadsource("local script = ...; " .. (d.Source or ""), chunk)
	if not fn then
		error(err)
	end
	setfenv(fn, env.G)
	return fn
end

-- Lädt ein ModuleScript (Cache je Kontext: Server bzw. Client eines Spielers)
function Mock.Require(env, module)
	assert(type(module) == "table" and rawget(module, "__data"), "require: kein ModuleScript (" .. tostring(module) .. ")")
	assert(module.ClassName == "ModuleScript", "require: " .. module.Name .. " ist kein ModuleScript")
	local ctx = currentCtx(env)
	local key = ctx.side == "client" and ("client:" .. tostring(ctx.player and ctx.player.UserId)) or "server"
	local cache = env.moduleCaches[key]
	if not cache then
		cache = {}
		env.moduleCaches[key] = cache
	end
	local cached = cache[module]
	if cached then
		if cached.loading then
			error("Requested module was required recursively: " .. module:GetFullName(), 2)
		end
		return cached.value
	end
	cache[module] = { loading = true }
	local ok, fn = pcall(compile, env, module)
	if not ok then
		cache[module] = nil
		error("Syntaxfehler in " .. module:GetFullName() .. ": " .. tostring(fn), 2)
	end
	local okRun, value = pcall(fn, module)
	if not okRun then
		cache[module] = nil
		error("Requested module experienced an error while loading (" .. module:GetFullName() .. "): " .. tostring(value), 2)
	end
	if value == nil then
		cache[module] = nil
		error("Module code did not return exactly one value: " .. module:GetFullName(), 2)
	end
	cache[module] = { value = value }
	return value
end

-- Führt ein Script/LocalScript aus (Standard: Server-Kontext)
function Mock.RunScript(env, scriptInst, ctx)
	local ok, fn = pcall(compile, env, scriptInst)
	if not ok then
		table.insert(env.scheduler.errors, "Syntaxfehler in " .. scriptInst:GetFullName() .. ": " .. tostring(fn))
		return nil
	end
	return env.scheduler:spawnIn(ctx or env.serverCtx, fn, scriptInst)
end

-- Führt fällige Aufgaben aus, ohne Zeit vergehen zu lassen
function Mock.Flush(env)
	env.scheduler:run()
end

local function classify(file)
	if file:match("%.server%.lua$") then
		return "Script", (file:gsub("%.server%.lua$", ""))
	elseif file:match("%.client%.lua$") then
		return "LocalScript", (file:gsub("%.client%.lua$", ""))
	end
	return "ModuleScript", (file:gsub("%.lua$", ""))
end
Mock.Classify = classify

-- Alter 3.0-Aufbau (src/shared, src/server, src/client). Dateiliste kommt vom Test-Runner.
function Mock.LoadPlace(env, root, files)
	local function add(parent, folderName, dir, list, clientScriptsParent)
		local folder = env.Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = parent
		for _, file in ipairs(list or {}) do
			local cls, name = classify(file)
			local inst = env.Instance.new(cls)
			inst.Name = name
			inst.Source = readfile(root .. "/" .. dir .. "/" .. file)
			rawget(inst, "__data").path = dir .. "/" .. file
			if cls == "LocalScript" and clientScriptsParent then
				inst.Parent = clientScriptsParent
			else
				inst.Parent = folder
			end
		end
		return folder
	end
	local s = env.services
	add(s.ReplicatedStorage, "Shared", "src/shared", files.shared)
	add(s.ServerScriptService, "Server", "src/server", files.server)
	local sps = s.StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if not sps then
		sps = env.Instance.new("StarterPlayerScripts")
		sps.Name = "StarterPlayerScripts"
		sps.Parent = s.StarterPlayer
	end
	add(sps, "Client", "src/client", files.client, sps)
end

---------------------------------------------------------------- Fixture (Basisbaum aus dem Place)
local fixtureCtors
local function ctors()
	if fixtureCtors then
		return fixtureCtors
	end
	fixtureCtors = {
		CF = function(...)
			return CFrame.new(...)
		end,
		V3 = function(x, y, z)
			return v3(x, y, z)
		end,
		V2 = function(x, y)
			return v2(x, y)
		end,
		C3 = function(r, g, b)
			return c3(r, g, b)
		end,
		C3u = function(r, g, b)
			return Color3.fromRGB(r, g, b)
		end,
		U = function(s, o)
			return udim(s, o)
		end,
		U2 = function(xs, xo, ys, yo)
			return udim2(xs, xo, ys, yo)
		end,
		E = Enum,
		EV = function(t, v)
			return Mock.EnumFromValue(t, v)
		end,
		R = function(ref)
			return { __ref = ref }
		end,
		NS = function(list)
			local kp = {}
			for i = 1, #list, 3 do
				table.insert(kp, NumberSequenceKeypoint.new(list[i], list[i + 1], list[i + 2]))
			end
			return plain("NumberSequence", { Keypoints = kp })
		end,
		CS = function(list)
			local kp = {}
			for i = 1, #list, 4 do
				table.insert(kp, ColorSequenceKeypoint.new(list[i], c3(list[i + 1], list[i + 2], list[i + 3])))
			end
			return plain("ColorSequence", { Keypoints = kp })
		end,
		NR = function(a, b)
			return NumberRange.new(a, b)
		end,
		BC = function(n)
			return BrickColor.new(n)
		end,
		RC = function(a, b, c, d)
			return Rect.new(a, b, c, d)
		end,
	}
	return fixtureCtors
end

-- Liefert die (einmal gebauten) Fixture-Knoten; fixture = Rückgabe von tests/fixtures/base_tree.lua
function Mock.FixtureNodes(fixture)
	if not fixture._nodes then
		fixture._nodes = fixture.build(ctors())
	end
	return fixture._nodes
end

-- Baut den Fixture-Baum in die Umgebung (Dienste werden über den Klassennamen zusammengeführt)
function Mock.LoadTree(env, fixture)
	local nodes = Mock.FixtureNodes(fixture)
	local byRef = {}
	local pending = {}
	local count = 0
	local function apply(inst, node)
		local d = rawget(inst, "__data")
		for k, v in pairs(node[3]) do
			if type(v) == "table" and v.__ref then
				table.insert(pending, { d, k, v.__ref })
			else
				d[k] = v
			end
		end
		if node.attrs then
			for k, v in pairs(node.attrs) do
				d._attributes[k] = v
			end
		end
		if node.tags then
			d._tags = {}
			for _, t in ipairs(node.tags) do
				d._tags[t] = true
			end
		end
		if node.id then
			byRef[node.id] = inst
		end
	end
	local function build(node, parent)
		local inst = newInstance(env, node[1], node[2])
		count += 1
		apply(inst, node)
		if node[4] then
			for _, child in ipairs(node[4]) do
				build(child, inst)
			end
		end
		rawAttach(inst, parent)
		return inst
	end
	for _, node in ipairs(nodes) do
		local svc = env.services[node[1]] or Mock.CreateService(env, node[1])
		apply(svc, node)
		rawget(svc, "__data").Name = node[2]
		for _, child in ipairs(node[4] or {}) do
			build(child, svc)
		end
	end
	for _, p in ipairs(pending) do
		p[1][p[2]] = byRef[p[3]]
	end
	return count
end

---------------------------------------------------------------- Spieler, Figuren, Clients
function Mock.NewPlayer(env, userId, name)
	local p = newInstance(env, "Player", name or ("Spieler" .. userId))
	local d = rawget(p, "__data")
	d.DisplayName = d.Name
	d.UserId = userId
	local gui = newInstance(env, "PlayerGui", "PlayerGui")
	rawAttach(gui, p)
	local backpack = newInstance(env, "Backpack", "Backpack")
	rawAttach(backpack, p)
	return p
end

function Mock.Join(env, player)
	table.insert(env.players, player)
	player.Parent = env.services.Players
	env.services.Players.PlayerAdded:Fire(player)
end

function Mock.Leave(env, player)
	env.services.Players.PlayerRemoving:Fire(player)
	player.Parent = nil
	local client = env.clients[player]
	if client then
		env.clients[player] = nil
	end
	local ch = rawget(player, "__data").Character
	if ch then
		getSignal(rawget(player, "__data"), "CharacterRemoving"):Fire(ch)
		ch:Destroy()
		rawget(player, "__data").Character = nil
	end
end

-- Erster aktivierter SpawnLocation im Workspace (Tiefensuche), sonst Ursprung
function Mock.SpawnCFrame(env)
	local function find(inst)
		for _, c in ipairs(rawget(inst, "__data")._children) do
			local cd = rawget(c, "__data")
			if cd.ClassName == "SpawnLocation" and c.Enabled ~= false then
				return c
			end
			local f = find(c)
			if f then
				return f
			end
		end
	end
	local spawn = find(env.workspace)
	if spawn then
		return spawn.CFrame * CFrame.new(0, spawn.Size.Y / 2 + 3, 0), spawn
	end
	return CFrame.new(0, 3, 0), nil
end

-- Baut eine R15-ähnliche Figur (HumanoidRootPart, Humanoid, Kopf, Rumpf, Arme mit RightHand) und setzt sie ein
function Mock.SpawnCharacter(env, player, at)
	local pd = rawget(player, "__data")
	local old = pd.Character
	if old then
		getSignal(pd, "CharacterRemoving"):Fire(old)
		old:Destroy()
	end
	-- ScreenGuis mit ResetOnSpawn verschwinden, StarterGui wird neu kopiert
	local gui = player:FindFirstChild("PlayerGui")
	if gui and old then
		for _, g in ipairs(gui:GetChildren()) do
			if g:IsA("LayerCollector") and g.ResetOnSpawn ~= false then
				g:Destroy()
			end
		end
		for _, g in ipairs(env.services.StarterGui:GetChildren()) do
			if g:IsA("LayerCollector") and g.ResetOnSpawn ~= false then
				g:Clone().Parent = gui
			end
		end
	end
	local model = newInstance(env, "Model", pd.Name)
	local function part(name, size, offset, props)
		local p = newInstance(env, "Part", name)
		local d = rawget(p, "__data")
		d.Size = size
		d.CFrame = CFrame.new(offset.X, offset.Y, offset.Z)
		d.CanCollide = false
		d.Anchored = false
		for k, v in pairs(props or {}) do
			d[k] = v
		end
		rawAttach(p, model)
		return p
	end
	local root = part("HumanoidRootPart", Vector3.new(2, 2, 1), Vector3.zero, { Transparency = 1 })
	local head = part("Head", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, 1.6, 0))
	local upper = part("UpperTorso", Vector3.new(2, 1.6, 1), Vector3.new(0, 0.2, 0))
	part("LowerTorso", Vector3.new(2, 0.4, 1), Vector3.new(0, -0.8, 0))
	local rua = part("RightUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(1.5, 0.4, 0))
	part("RightLowerArm", Vector3.new(1, 1, 1), Vector3.new(1.5, -0.6, 0))
	local hand = part("RightHand", Vector3.new(1, 0.3, 1), Vector3.new(1.5, -1.25, 0))
	part("LeftUpperArm", Vector3.new(1, 1.2, 1), Vector3.new(-1.5, 0.4, 0))
	part("LeftLowerArm", Vector3.new(1, 1, 1), Vector3.new(-1.5, -0.6, 0))
	part("LeftHand", Vector3.new(1, 0.3, 1), Vector3.new(-1.5, -1.25, 0))
	part("RightUpperLeg", Vector3.new(1, 1, 1), Vector3.new(0.5, -1.5, 0))
	part("LeftUpperLeg", Vector3.new(1, 1, 1), Vector3.new(-0.5, -1.5, 0))
	part("RightFoot", Vector3.new(1, 0.3, 1), Vector3.new(0.5, -2.85, 0))
	part("LeftFoot", Vector3.new(1, 0.3, 1), Vector3.new(-0.5, -2.85, 0))
	local grip = newInstance(env, "Attachment", "RightGripAttachment")
	rawget(grip, "__data").CFrame = CFrame.new(0, -0.15, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
	rawAttach(grip, hand)
	local shoulder = newInstance(env, "Motor6D", "RightShoulder")
	local sd = rawget(shoulder, "__data")
	sd.Part0 = upper
	sd.Part1 = rua
	sd.C0 = CFrame.new(1, 0.56, 0)
	sd.C1 = CFrame.new(-0.5, 0.4, 0)
	rawAttach(shoulder, rua)
	local neck = newInstance(env, "Motor6D", "Neck")
	rawget(neck, "__data").Part0 = upper
	rawget(neck, "__data").Part1 = head
	rawAttach(neck, head)
	local humanoid = newInstance(env, "Humanoid", "Humanoid")
	rawget(humanoid, "__data").DisplayName = pd.DisplayName or pd.Name
	rawAttach(humanoid, model)
	local animator = newInstance(env, "Animator", "Animator")
	rawAttach(animator, humanoid)
	rawget(model, "__data").PrimaryPart = root
	local target = at
	if target and typeOf(target) == "Vector3" then
		target = CFrame.new(target)
	end
	model:PivotTo(target or Mock.SpawnCFrame(env))
	pd.Character = model
	-- Wie Roblox: CharacterAdded kommt, bevor die Figur im Workspace hängt
	getSignal(pd, "CharacterAdded"):Fire(model)
	if not rawget(model, "__data")._destroyed and pd.Character == model then
		model.Parent = env.workspace
	end
	getSignal(pd, "CharacterAppearanceLoaded"):Fire(model)
	return model
end

-- Setzt die Figur (Model:PivotTo) so, dass HumanoidRootPart an `target` steht
function Mock.Teleport(env, player, target, offset)
	local ch = player.Character
	assert(ch, "Teleport: Spieler hat keine Figur")
	local c
	local t = typeOf(target)
	if t == "Vector3" then
		c = CFrame.new(target)
	elseif t == "CFrame" then
		c = target
	elseif t == "Instance" then
		if isBasePart(target) then
			c = CFrame.new(target.Position)
		elseif target:IsA("Model") then
			c = CFrame.new(target:GetPivot().Position)
		elseif target:IsA("Attachment") then
			c = CFrame.new(target.WorldPosition)
		end
	end
	assert(c, "Teleport: Ziel nicht erkannt (" .. tostring(target) .. ")")
	if offset then
		c = c + offset
	end
	ch:PivotTo(c)
end

-- Löst einen ProximityPrompt für den Spieler aus (prüft Enabled und Reichweite, außer opts.force)
function Mock.TriggerPrompt(env, prompt, player, opts)
	opts = opts or {}
	if not opts.force then
		if not prompt.Enabled or not prompt:IsDescendantOf(env.workspace) then
			return false, "Prompt nicht aktiv"
		end
		local ch = player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		local pos = promptPart(prompt)
		if not root or not pos or (pos - root.Position).Magnitude > prompt.MaxActivationDistance then
			return false, "außer Reichweite"
		end
	end
	local pd = rawget(prompt, "__data")
	getSignal(pd, "PromptButtonHoldBegan"):Fire(player)
	getSignal(pd, "Triggered"):Fire(player)
	getSignal(rawget(env.services.ProximityPromptService, "__data"), "PromptTriggered"):Fire(prompt, player)
	getSignal(pd, "TriggerEnded"):Fire(player)
	Mock.Flush(env)
	return true
end

-- Startet die Client-Skripte eines Spielers (StarterPlayerScripts -> PlayerScripts, StarterGui -> PlayerGui)
function Mock.StartClient(env, player, opts)
	opts = opts or {}
	assert(player.Parent, "StartClient: Spieler ist nicht im Spiel")
	local ctx = { env = env, side = "client", player = player, name = "Client:" .. tostring(player.UserId) }
	local client = { player = player, ctx = ctx, keysDown = {}, shownPrompts = {}, scripts = {} }
	env.clients[player] = client
	local ps = player:FindFirstChild("PlayerScripts")
	if not ps then
		ps = newInstance(env, "PlayerScripts", "PlayerScripts")
		rawAttach(ps, player)
	end
	local starter = env.services.StarterPlayer:FindFirstChild("StarterPlayerScripts")
	if starter then
		for _, c in ipairs(starter:GetChildren()) do
			c:Clone().Parent = ps
		end
	end
	local gui = player:FindFirstChild("PlayerGui")
	for _, g in ipairs(env.services.StarterGui:GetChildren()) do
		g:Clone().Parent = gui
	end
	local function runAll(root)
		for _, x in ipairs(root:GetDescendants()) do
			if x.ClassName == "LocalScript" and not x.Disabled and x.Enabled ~= false then
				table.insert(client.scripts, x)
				Mock.RunScript(env, x, ctx)
			end
		end
	end
	runAll(ps)
	runAll(gui)
	Mock.Flush(env)
	return client
end

local function inputObject(spec)
	return plain("InputObject", {
		KeyCode = spec.KeyCode or Enum.KeyCode.Unknown,
		UserInputType = spec.UserInputType or Enum.UserInputType.Keyboard,
		UserInputState = spec.UserInputState or Enum.UserInputState.Begin,
		Position = spec.Position or Vector3.zero,
		Delta = spec.Delta or Vector3.zero,
		IsModifierKeyDown = function()
			return false
		end,
	})
end

-- Simuliert eine Eingabe beim Client des Spielers: UserInputService-Ereignisse und ContextActionService-Bindungen
-- (nach Priorität, Sink stoppt). state = "Begin" | "End".
function Mock.Input(env, player, keyOrType, state)
	local client = env.clients[player]
	assert(client, "Input: für diesen Spieler läuft kein Client")
	state = state or "Begin"
	local isType = keyOrType.EnumType == "UserInputType"
	local input = inputObject({
		KeyCode = not isType and keyOrType or nil,
		UserInputType = isType and keyOrType or Enum.UserInputType.Keyboard,
		UserInputState = Enum.UserInputState[state],
	})
	client.keysDown[keyOrType] = state == "Begin" or nil
	local uis = rawget(env.services.UserInputService, "__data")
	local processed = env.focusedTextBox ~= nil
	getSignal(uis, state == "Begin" and "InputBegan" or "InputEnded"):FireFor(player, input, processed)
	-- ContextActionService
	local candidates = {}
	for _, b in pairs(env.casBindings) do
		if b.ctx and b.ctx.player == player then
			local hit = b.inputs[keyOrType]
			if not hit and (keyOrType == Enum.KeyCode.Space or keyOrType == Enum.KeyCode.ButtonA) then
				hit = b.inputs[Enum.PlayerActions.CharacterJump]
			end
			if hit then
				table.insert(candidates, b)
			end
		end
	end
	table.sort(candidates, function(a, b)
		if a.priority == b.priority then
			return a.order > b.order
		end
		return a.priority > b.priority
	end)
	local sunk = false
	for _, b in ipairs(candidates) do
		local result
		local co = coroutine.create(function()
			result = b.fn(b.name, input.UserInputState, input)
		end)
		ctxOf[co] = b.ctx
		env.scheduler:resume(co)
		if result ~= Enum.ContextActionResult.Pass then
			sunk = true
			break
		end
	end
	Mock.Flush(env)
	return sunk
end

function Mock.KeyPress(env, player, key)
	local sunk = Mock.Input(env, player, key, "Begin")
	Mock.Input(env, player, key, "End")
	return sunk
end

-- Klick auf einen GuiButton (Activated + MouseButton1Click), nur wenn sichtbar (außer force)
function Mock.IsGuiVisible(obj)
	local cur = obj
	while cur do
		local d = rawget(cur, "__data")
		if d._cls.isA.GuiObject and cur.Visible == false then
			return false
		end
		if d._cls.isA.LayerCollector then
			return cur.Enabled ~= false
		end
		if d.ClassName == "PlayerGui" then
			return true
		end
		cur = d._parent
	end
	return false
end
function Mock.Click(env, button, opts)
	if not (opts and opts.force) and not Mock.IsGuiVisible(button) then
		return false
	end
	local d = rawget(button, "__data")
	local input = inputObject({ UserInputType = Enum.UserInputType.MouseButton1 })
	fireIf(d, "MouseButton1Down", 0, 0)
	fireIf(d, "MouseButton1Up", 0, 0)
	getSignal(d, "Activated"):Fire(input, 1)
	getSignal(d, "MouseButton1Click"):Fire()
	Mock.Flush(env)
	return true
end

-- Klick in die 3D-Welt: setzt Mouse.Target und löst MouseButton1 aus
function Mock.ClickWorld(env, player, part)
	local mouse = player:GetMouse()
	local md = rawget(mouse, "__data")
	md.Target = part
	md.Hit = part and CFrame.new(part.Position) or IDENTITY
	getSignal(md, "Button1Down"):FireFor(player)
	Mock.Input(env, player, Enum.UserInputType.MouseButton1, "Begin")
	Mock.Input(env, player, Enum.UserInputType.MouseButton1, "End")
	getSignal(md, "Button1Up"):FireFor(player)
end

-- Tötet die Figur (Humanoid.Health = 0); mit respawn nach Players.RespawnTime neu erscheinen lassen
function Mock.Kill(env, player, respawn)
	local ch = player.Character
	local h = ch and ch:FindFirstChildOfClass("Humanoid")
	if h then
		h.Health = 0
	end
	if respawn then
		env.scheduler:delay(env.services.Players.RespawnTime, function()
			if player.Parent then
				Mock.SpawnCharacter(env, player)
			end
		end)
	end
	Mock.Flush(env)
end

-- Simuliert einen Developer-Product-Kauf: ruft MarketplaceService.ProcessReceipt wie Roblox auf
function Mock.Purchase(env, player, productId, purchaseId)
	local mp = rawget(env.services.MarketplaceService, "__data")
	local cb = mp.ProcessReceipt
	assert(type(cb) == "function", "Purchase: ProcessReceipt ist nicht gesetzt")
	local result, done
	local co = coroutine.create(function()
		result = cb({ PlayerId = player.UserId, ProductId = productId, PurchaseId = purchaseId or ("kauf-" .. tostring(env.guid + 1)), CurrencySpent = 0, CurrencyType = Enum.CurrencyType.Robux, PlaceIdWherePurchased = 0 })
		done = true
	end)
	ctxOf[co] = env.serverCtx
	env.scheduler:resume(co)
	Mock.Flush(env)
	return result, done == true
end

function Mock.SetViewport(env, size)
	env.viewport = size
	local cam = env.workspace.CurrentCamera
	if cam then
		propertyChanged(cam, rawget(cam, "__data"), "ViewportSize", size)
	end
end

Mock.Signal = Signal
Mock.Scheduler = Scheduler
Mock.Clock = Clock
Mock.Vector3 = Vector3
Mock.Vector2 = Vector2
Mock.CFrame = CFrame
Mock.Color3 = Color3
Mock.UDim2 = UDim2
Mock.Enum = Enum
Mock.Instance = Instance
Mock.IsInstance = isInstance
Mock.RawAttach = rawAttach
Mock.GetSignal = getSignal

return Mock
