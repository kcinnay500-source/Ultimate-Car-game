-- mock_roblox: minimale Roblox-Nachbildung für automatisierte Tests mit dem Luau-Interpreter (tools/luaurun).
-- Bildet Instanzen, Signale, einen Scheduler (task.*), DataStores mit Fehlerinjektion und die
-- benötigten Datentypen nach. Jede Umgebung (Mock.NewEnv) hat eigenen Baum, Modulcache und Uhr.
local Mock = {}

---------------------------------------------------------------- Scheduler
local Scheduler = {}
Scheduler.__index = Scheduler

function Scheduler.new(clock)
	return setmetatable({ clock = clock, sleeping = {}, errors = {} }, Scheduler)
end

function Scheduler:resume(co, ...)
	local ok, err = coroutine.resume(co, ...)
	if not ok then
		table.insert(self.errors, tostring(err))
	end
end

function Scheduler:spawn(fn, ...)
	local co
	if type(fn) == "thread" then
		co = fn
	else
		co = coroutine.create(fn)
	end
	self:resume(co, ...)
	return co
end

function Scheduler:wait(seconds)
	local co = coroutine.running()
	if not coroutine.isyieldable() then
		-- Hauptthread: kein Warten möglich, Zeit trotzdem vergehen lassen
		self.clock:Advance(seconds or 0)
		return seconds or 0
	end
	table.insert(self.sleeping, { co = co, at = self.clock.precise + math.max(seconds or 0, 0) })
	coroutine.yield()
	return seconds or 0
end

function Scheduler:delay(seconds, fn, ...)
	local args = table.pack(...)
	local co = coroutine.create(function()
		fn(table.unpack(args, 1, args.n))
	end)
	table.insert(self.sleeping, { co = co, at = self.clock.precise + math.max(seconds or 0, 0), fresh = true })
	return co
end

function Scheduler:cancel(co)
	for i = #self.sleeping, 1, -1 do
		if self.sleeping[i].co == co then
			table.remove(self.sleeping, i)
		end
	end
end

-- Weckt alle fälligen Coroutinen (in Zeitreihenfolge)
function Scheduler:run()
	local guard = 0
	while guard < 100000 do
		guard += 1
		local bestIndex, best
		for i, s in ipairs(self.sleeping) do
			if s.at <= self.clock.precise + 1e-9 and (not best or s.at < best.at) then
				bestIndex, best = i, s
			end
		end
		if not best then
			return
		end
		table.remove(self.sleeping, bestIndex)
		if coroutine.status(best.co) == "suspended" then
			self:resume(best.co)
		end
	end
	error("Scheduler: Endlosschleife")
end

---------------------------------------------------------------- Uhr
local Clock = {}
Clock.__index = Clock

function Clock.new(startTime)
	local start = startTime or 1760000000
	return setmetatable({ wall = start, now = start, precise = 1000, scheduler = nil }, Clock)
end

-- Lässt Zeit vergehen und führt dabei fällige Aufgaben in 0,25-s-Schritten aus
function Clock:Advance(seconds)
	local remaining = seconds
	while remaining > 1e-9 do
		local step = math.min(0.25, remaining)
		self.precise += step
		self.wall += step
		self.now = math.floor(self.wall + 1e-9)
		remaining -= step
		if self.scheduler then
			self.scheduler:run()
		end
	end
end

-- Springt die Wandzeit (os.time) ohne Zwischen-Ticks, z. B. für Offline-Tests
function Clock:Jump(seconds)
	self.wall += seconds
	self.now = math.floor(self.wall + 1e-9)
end

---------------------------------------------------------------- Datentypen
local Vector3 = {}
Vector3.__index = function(v, k)
	if k == "Magnitude" then
		return math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
	elseif k == "Unit" then
		local m = math.sqrt(v.X * v.X + v.Y * v.Y + v.Z * v.Z)
		return Vector3.new(v.X / m, v.Y / m, v.Z / m)
	end
	return Vector3[k]
end
function Vector3.new(x, y, z)
	return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0, __type = "Vector3" }, Vector3)
end
Vector3.__add = function(a, b)
	return Vector3.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z)
end
Vector3.__sub = function(a, b)
	return Vector3.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z)
end
Vector3.__mul = function(a, b)
	if type(a) == "number" then
		return Vector3.new(b.X * a, b.Y * a, b.Z * a)
	elseif type(b) == "number" then
		return Vector3.new(a.X * b, a.Y * b, a.Z * b)
	end
	return Vector3.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
function Vector3.Cross(a, b)
	return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X)
end

local CFrame = {}
CFrame.__index = function(c, k)
	if k == "Position" then
		return Vector3.new(c.p[1], c.p[2], c.p[3])
	elseif k == "LookVector" then
		return Vector3.new(-c.r[1][3], -c.r[2][3], -c.r[3][3])
	end
	return CFrame[k]
end
local function ident()
	return { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
end
local function mat(r, p)
	return setmetatable({ r = r, p = p, __type = "CFrame" }, CFrame)
end
function CFrame.new(x, y, z)
	if type(x) == "table" then
		return mat(ident(), { x.X, x.Y, x.Z })
	end
	return mat(ident(), { x or 0, y or 0, z or 0 })
end
local function mul3(a, b)
	local out = { {}, {}, {} }
	for i = 1, 3 do
		for j = 1, 3 do
			out[i][j] = a[i][1] * b[1][j] + a[i][2] * b[2][j] + a[i][3] * b[3][j]
		end
	end
	return out
end
function CFrame.Angles(rx, ry, rz)
	local cx, sx, cy, sy, cz, sz = math.cos(rx), math.sin(rx), math.cos(ry), math.sin(ry), math.cos(rz), math.sin(rz)
	local X = { { 1, 0, 0 }, { 0, cx, -sx }, { 0, sx, cx } }
	local Y = { { cy, 0, sy }, { 0, 1, 0 }, { -sy, 0, cy } }
	local Z = { { cz, -sz, 0 }, { sz, cz, 0 }, { 0, 0, 1 } }
	return mat(mul3(mul3(X, Y), Z), { 0, 0, 0 })
end
function CFrame.lookAt(pos, target)
	local look = (target - pos).Unit
	local right = look:Cross(Vector3.new(0, 1, 0)).Unit
	local up = right:Cross(look)
	return mat({
		{ right.X, up.X, -look.X },
		{ right.Y, up.Y, -look.Y },
		{ right.Z, up.Z, -look.Z },
	}, { pos.X, pos.Y, pos.Z })
end
CFrame.__mul = function(a, b)
	if getmetatable(b) == Vector3 then
		local r = a.r
		return Vector3.new(
			r[1][1] * b.X + r[1][2] * b.Y + r[1][3] * b.Z + a.p[1],
			r[2][1] * b.X + r[2][2] * b.Y + r[2][3] * b.Z + a.p[2],
			r[3][1] * b.X + r[3][2] * b.Y + r[3][3] * b.Z + a.p[3]
		)
	end
	local r = mul3(a.r, b.r)
	local p = {}
	for i = 1, 3 do
		p[i] = a.r[i][1] * b.p[1] + a.r[i][2] * b.p[2] + a.r[i][3] * b.p[3] + a.p[i]
	end
	return mat(r, p)
end

local Color3 = {}
Color3.__index = Color3
function Color3.new(r, g, b)
	return setmetatable({ R = r or 0, G = g or 0, B = b or 0, __type = "Color3" }, Color3)
end
function Color3.fromRGB(r, g, b)
	return Color3.new(r / 255, g / 255, b / 255)
end
function Color3.Lerp(a, b, t)
	return Color3.new(a.R + (b.R - a.R) * t, a.G + (b.G - a.G) * t, a.B + (b.B - a.B) * t)
end

local function plain(typeName, fields)
	fields.__type = typeName
	return fields
end
local UDim = {
	new = function(s, o)
		return plain("UDim", { Scale = s, Offset = o })
	end,
}
local UDim2 = {
	new = function(xs, xo, ys, yo)
		return plain("UDim2", { X = UDim.new(xs, xo), Y = UDim.new(ys, yo) })
	end,
	fromScale = function(x, y)
		return plain("UDim2", { X = UDim.new(x, 0), Y = UDim.new(y, 0) })
	end,
	fromOffset = function(x, y)
		return plain("UDim2", { X = UDim.new(0, x), Y = UDim.new(0, y) })
	end,
}
local Vector2 = {
	new = function(x, y)
		return plain("Vector2", { X = x or 0, Y = y or 0 })
	end,
}
local TweenInfo = {
	new = function(...)
		return plain("TweenInfo", { args = { ... } })
	end,
}

-- Enum: Enum.Material.Grass -> eindeutiges Token
local enumCache = {}
local Enum = setmetatable({}, {
	__index = function(_, typeName)
		enumCache[typeName] = enumCache[typeName] or setmetatable({}, {
			__index = function(t, name)
				local token = { EnumType = typeName, Name = name, __type = "EnumItem" }
				rawset(t, name, token)
				return token
			end,
		})
		return enumCache[typeName]
	end,
})

-- Random mit Roblox-Schnittstelle (deterministisch pro Seed)
local Random = {}
Random.__index = Random
local seedCounter = 12345
function Random.new(seed)
	seedCounter += 7919
	return setmetatable({ state = (seed or seedCounter) % 2147483647 }, Random)
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

---------------------------------------------------------------- Signale
local Signal = {}
Signal.__index = Signal
function Signal.new(env)
	return setmetatable({ env = env, handlers = {}, __type = "RBXScriptSignal" }, Signal)
end
function Signal:Connect(fn)
	local conn = { Connected = true, __type = "RBXScriptConnection" }
	local signal = self
	function conn:Disconnect()
		conn.Connected = false
		for i, h in ipairs(signal.handlers) do
			if h == conn then
				table.remove(signal.handlers, i)
				break
			end
		end
	end
	conn.fn = fn
	table.insert(self.handlers, conn)
	return conn
end
function Signal:Once(fn)
	local conn
	conn = self:Connect(function(...)
		conn:Disconnect()
		fn(...)
	end)
	return conn
end
function Signal:Fire(...)
	local list = table.clone(self.handlers)
	for _, conn in ipairs(list) do
		if conn.Connected then
			self.env.scheduler:spawn(conn.fn, ...)
		end
	end
end
function Signal:ConnectionCount()
	return #self.handlers
end

---------------------------------------------------------------- Instanzen
local SIGNALS = {
	Triggered = true, OnServerEvent = true, OnClientEvent = true, PlayerAdded = true, PlayerRemoving = true,
	Activated = true, InputBegan = true, Heartbeat = true, RenderStepped = true, PromptGamePassPurchaseFinished = true,
	MouseButton1Click = true, ChildAdded = true, Changed = true,
}
local IS_A = {
	BasePart = { Part = true, SpawnLocation = true, MeshPart = true },
	GuiObject = { Frame = true, TextLabel = true, TextButton = true, ScrollingFrame = true, ImageLabel = true },
	GuiButton = { TextButton = true },
	LuaSourceContainer = { Script = true, LocalScript = true, ModuleScript = true },
}

local Instance = {}

local function newInstance(env, className, name)
	local data = {
		ClassName = className,
		Name = name or className,
		_children = {},
		_attributes = {},
		_signals = {},
		_env = env,
		_parent = nil,
		_destroyed = false,
	}
	local inst = setmetatable({}, Instance.Meta)
	rawset(inst, "__data", data)
	env.instanceCount += 1
	return inst
end

Instance.Methods = {}
local M = Instance.Methods

function M:GetChildren()
	return table.clone(self.__data._children)
end
function M:GetDescendants()
	local out = {}
	local function walk(i)
		for _, c in ipairs(i.__data._children) do
			table.insert(out, c)
			walk(c)
		end
	end
	walk(self)
	return out
end
function M:FindFirstChild(name)
	for _, c in ipairs(self.__data._children) do
		if c.__data.Name == name then
			return c
		end
	end
	return nil
end
function M:FindFirstChildOfClass(cls)
	for _, c in ipairs(self.__data._children) do
		if c.__data.ClassName == cls then
			return c
		end
	end
	return nil
end
function M:WaitForChild(name, timeout)
	local c = self:FindFirstChild(name)
	if c then
		return c
	end
	if timeout then
		return nil
	end
	error("WaitForChild: '" .. tostring(name) .. "' fehlt unter " .. self.__data.Name, 2)
end
function M:IsA(cls)
	local cn = self.__data.ClassName
	if cn == cls or cls == "Instance" then
		return true
	end
	return IS_A[cls] ~= nil and IS_A[cls][cn] == true
end
function M:Destroy()
	self.Parent = nil
	self.__data._destroyed = true
	for _, c in ipairs(self:GetChildren()) do
		c:Destroy()
	end
	for _, sig in pairs(self.__data._signals) do
		sig.handlers = {}
	end
end
function M:GetPropertyChangedSignal(prop)
	local key = "Changed:" .. tostring(prop)
	local data = self.__data
	data._signals[key] = data._signals[key] or Signal.new(data._env)
	return data._signals[key]
end
function M:SetAttribute(k, v)
	self.__data._attributes[k] = v
end
function M:GetAttribute(k)
	return self.__data._attributes[k]
end
function M:GetFullName()
	local parts = {}
	local cur = self
	while cur do
		table.insert(parts, 1, cur.__data.Name)
		cur = cur.__data._parent
	end
	return table.concat(parts, ".")
end
function M:Clone()
	local c = newInstance(self.__data._env, self.__data.ClassName, self.__data.Name)
	for k, v in pairs(self.__data) do
		if type(k) == "string" and k:sub(1, 1) ~= "_" then
			c.__data[k] = v
		end
	end
	return c
end
-- RemoteEvent
function M:FireClient(player, ...)
	local sent = self.__data.sent or {}
	self.__data.sent = sent
	table.insert(sent, { player = player, args = table.pack(...) })
	local env = self.__data._env
	if env.onFireClient then
		env.onFireClient(self, player, ...)
	end
end
function M:FireAllClients(...)
	for _, p in ipairs(self.__data._env.players) do
		self:FireClient(p, ...)
	end
end
function M:FireServer(...)
	local sent = self.__data.sentToServer or {}
	self.__data.sentToServer = sent
	table.insert(sent, table.pack(...))
end
-- Player
function M:Kick(msg)
	self.__data.kicked = msg or true
end
-- Sound / Tween
function M:Play() end
function M:Stop() end
-- ProximityPrompt / Misc
function M:GetServerTimeNow()
	return self.__data._env.clock.now + (self.__data._env.clock.precise % 1)
end

Instance.Meta = {
	__index = function(self, key)
		local data = rawget(self, "__data")
		if key == "Parent" then
			return data._parent
		end
		if M[key] then
			return M[key]
		end
		if SIGNALS[key] then
			data._signals[key] = data._signals[key] or Signal.new(data._env)
			return data._signals[key]
		end
		local v = data[key]
		if v ~= nil then
			return v
		end
		local child = self:FindFirstChild(key)
		if child then
			return child
		end
		if key == "AbsolutePosition" or key == "AbsoluteSize" then
			return Vector2.new(0, 0)
		end
		return nil
	end,
	__newindex = function(self, key, value)
		local data = rawget(self, "__data")
		if key == "Parent" then
			local old = data._parent
			if old == value then
				return
			end
			if old then
				local list = old.__data._children
				for i, c in ipairs(list) do
					if c == self then
						table.remove(list, i)
						break
					end
				end
			end
			data._parent = value
			if value then
				table.insert(value.__data._children, self)
			end
			return
		end
		data[key] = value
	end,
	__tostring = function(self)
		return rawget(self, "__data").Name
	end,
}

---------------------------------------------------------------- Dienste
local function makeDataStoreService(env)
	local svc = newInstance(env, "DataStoreService")
	local d = svc.__data
	d.stores = {}
	d.ordered = {}
	d.fail = false -- true: alle Aufrufe werfen Fehler
	d.getFail = false -- true: GetDataStore wirft (Studio ohne API-Zugriff)
	d.calls = { update = 0, set = 0, sorted = 0 }
	d.updateYield = 0 -- Sekunden Latenz pro UpdateAsync
	local function copy(v)
		if type(v) ~= "table" then
			return v
		end
		local o = {}
		for k, x in pairs(v) do
			o[copy(k)] = copy(x)
		end
		return o
	end
	d.copy = copy
	svc.__data.GetDataStore = function(_, name)
		if d.getFail then
			error("You must publish this place to the web to access DataStore.")
		end
		d.stores[name] = d.stores[name] or { data = {} }
		local store = d.stores[name]
		return {
			UpdateAsync = function(_, key, fn)
				d.calls.update += 1
				if d.updateYield > 0 then
					env.scheduler:wait(d.updateYield)
				end
				if d.fail then
					error("DataStore-Fehler (Mock)")
				end
				local result = fn(copy(store.data[key]))
				if result ~= nil then
					store.data[key] = copy(result)
				end
				return copy(result)
			end,
			GetAsync = function(_, key)
				if d.fail then
					error("DataStore-Fehler (Mock)")
				end
				return copy(store.data[key])
			end,
			data = store.data,
		}
	end
	svc.__data.GetOrderedDataStore = function(_, name)
		if d.getFail then
			error("You must publish this place to the web to access DataStore.")
		end
		d.ordered[name] = d.ordered[name] or { data = {} }
		local store = d.ordered[name]
		return {
			SetAsync = function(_, key, value)
				d.calls.set += 1
				if d.fail then
					error("DataStore-Fehler (Mock)")
				end
				assert(type(value) == "number" and value == math.floor(value), "OrderedDataStore: nur Ganzzahlen")
				assert(value < 2 ^ 63, "OrderedDataStore: Wert zu groß")
				store.data[key] = value
			end,
			GetSortedAsync = function(_, ascending, pageSize)
				d.calls.sorted += 1
				if d.fail then
					error("DataStore-Fehler (Mock)")
				end
				local list = {}
				for k, v in pairs(store.data) do
					table.insert(list, { key = k, value = v })
				end
				table.sort(list, function(a, b)
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
	return svc
end

local function makePlayers(env)
	local svc = newInstance(env, "Players", "Players")
	svc.__data.GetPlayers = function()
		local out = {}
		for _, p in ipairs(env.players) do
			if p.Parent ~= nil then
				table.insert(out, p)
			end
		end
		return out
	end
	svc.__data.GetPlayerByUserId = function(_, id)
		for _, p in ipairs(env.players) do
			if p.UserId == id and p.Parent ~= nil then
				return p
			end
		end
		return nil
	end
	svc.__data.GetNameFromUserIdAsync = function(_, id)
		return "Nutzer" .. tostring(id)
	end
	return svc
end

local function makeMarketplace(env)
	local svc = newInstance(env, "MarketplaceService")
	svc.__data.owned = {}
	svc.__data.prompts = {}
	svc.__data.yield = 0 -- Sekunden Latenz (echte Aufrufe warten)
	svc.__data.UserOwnsGamePassAsync = function(_, userId, passId)
		if svc.__data.yield > 0 then
			env.scheduler:wait(svc.__data.yield)
		end
		return svc.__data.owned[userId .. ":" .. passId] == true
	end
	svc.__data.PromptGamePassPurchase = function(_, player, passId)
		table.insert(svc.__data.prompts, { player = player, passId = passId })
	end
	return svc
end

---------------------------------------------------------------- Umgebung
function Mock.NewEnv(opts)
	opts = opts or {}
	local env = { players = {}, instanceCount = 0, modules = {}, sources = {}, warnings = {} }
	env.clock = Clock.new(opts.startTime)
	env.scheduler = Scheduler.new(env.clock)
	env.clock.scheduler = env.scheduler

	local game = newInstance(env, "DataModel", "game")
	game.__data.JobId = opts.jobId or "job-A"
	game.__data.closeCallbacks = {}
	game.__data.BindToClose = function(_, fn)
		table.insert(game.__data.closeCallbacks, fn)
	end
	local services = {}
	local function service(name, inst)
		inst = inst or newInstance(env, name, name)
		inst.__data.Name = name
		inst.Parent = game
		services[name] = inst
		return inst
	end
	service("Workspace").__data.GetServerTimeNow = M.GetServerTimeNow
	service("ReplicatedStorage")
	service("ServerScriptService")
	service("StarterPlayer")
	service("SoundService")
	service("Players", makePlayers(env))
	service("DataStoreService", makeDataStoreService(env))
	service("MarketplaceService", makeMarketplace(env))
	env.studio = opts.studio == true
	service("RunService").__data.IsStudio = function()
		return env.studio
	end
	service("GuiService")
	local tween = service("TweenService")
	tween.__data.Create = function()
		return { Play = function() end, Cancel = function() end }
	end
	game.__data.GetService = function(_, name)
		local s = services[name]
		assert(s, "Unbekannter Dienst: " .. tostring(name))
		return s
	end
	env.game = game
	env.services = services
	env.workspace = services.Workspace

	env.Instance = {
		new = function(className, parent)
			local inst = newInstance(env, className)
			if parent then
				inst.Parent = parent
			end
			return inst
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
	}
	return env
end

-- Setzt die globalen Roblox-Namen auf diese Umgebung
function Mock.Activate(env)
	_G.game = env.game
	_G.workspace = env.workspace
	_G.Instance = env.Instance
	_G.task = env.task
	_G.Enum = Enum
	_G.Vector3 = Vector3
	_G.Vector2 = Vector2
	_G.CFrame = CFrame
	_G.Color3 = Color3
	_G.UDim = UDim
	_G.UDim2 = UDim2
	_G.TweenInfo = TweenInfo
	_G.Random = Random
	_G.warn = function(...)
		table.insert(env.warnings, table.concat(table.pack(...), " "))
	end
	_G.typeof = function(v)
		if type(v) == "table" then
			if rawget(v, "__data") then
				return "Instance"
			end
			if v.__type then
				return v.__type
			end
		end
		return type(v)
	end
	_G.require = function(module)
		return Mock.Require(env, module)
	end
	Mock.Current = env
end

-- Lädt ein ModuleScript aus dem Mock-Baum; Quelle kommt aus src/
function Mock.Require(env, module)
	assert(type(module) == "table" and rawget(module, "__data"), "require: kein ModuleScript")
	assert(module.ClassName == "ModuleScript", "require: " .. module.Name .. " ist kein ModuleScript")
	local cached = env.modules[module]
	if cached then
		if cached.loading then
			error("Zirkulärer require: " .. module:GetFullName())
		end
		return cached.value
	end
	env.modules[module] = { loading = true }
	local fn = loadsource("local script = ...; " .. module.Source, module.__data.path or module.Name)
	local value = fn(module)
	env.modules[module] = { value = value }
	return value
end

-- Führt ein Script/LocalScript aus
function Mock.RunScript(env, scriptInst)
	local fn = loadsource("local script = ...; " .. scriptInst.Source, scriptInst.__data.path or scriptInst.Name)
	env.scheduler:spawn(fn, scriptInst)
end

local function classify(file)
	if file:match("%.server%.lua$") then
		return "Script", (file:gsub("%.server%.lua$", ""))
	elseif file:match("%.client%.lua$") then
		return "LocalScript", (file:gsub("%.client%.lua$", ""))
	end
	return "ModuleScript", (file:gsub("%.lua$", ""))
end

-- Baut den Place-Baum wie tools/build_place.py (Dateiliste kommt vom Test-Runner)
function Mock.LoadPlace(env, root, files)
	local function add(parent, folderName, dir, list, clientScriptsParent)
		local folder = env.Instance.new("Folder")
		folder.Name = folderName
		folder.Parent = parent
		for _, file in ipairs(list) do
			local cls, name = classify(file)
			local inst = env.Instance.new(cls)
			inst.Name = name
			inst.Source = readfile(root .. "/" .. dir .. "/" .. file)
			inst.__data.path = dir .. "/" .. file
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
	local sps = env.Instance.new("StarterPlayerScripts")
	sps.Name = "StarterPlayerScripts"
	sps.Parent = s.StarterPlayer
	add(sps, "Client", "src/client", files.client, sps)
end

-- Spieler anlegen (ohne Beitritt auszulösen)
function Mock.NewPlayer(env, userId, name)
	local p = env.Instance.new("Player")
	p.Name = name or ("Spieler" .. userId)
	p.DisplayName = p.Name
	p.UserId = userId
	local gui = env.Instance.new("PlayerGui")
	gui.Name = "PlayerGui"
	gui.Parent = p
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
end

Mock.Signal = Signal
Mock.Vector3 = Vector3
Mock.CFrame = CFrame
Mock.Enum = Enum

return Mock
