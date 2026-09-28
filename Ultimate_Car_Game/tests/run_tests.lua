-- Test-Runner: führt alle tests/test_*.lua im Mock aus.
-- Aufruf (aus dem Projektordner): tools/luaurun/target/release/luaurun run tests/run_tests.lua . [Filter]
--   Filter = Teilstring des Dateinamens, z. B. "test_garage" für die 2.4.0-Tests.
--
-- Harness für die echten Place-Skripte: H.Garage(opts) baut den Basisbaum aus tests/fixtures/base_tree.lua
-- (erzeugt von tools/export_fixture.py), setzt die Skripte aus src/** (Zuordnung aus default.project.json,
-- wie tools/build_place.py) oder die unveränderten 2.4.0-Skripte (opts.scripts = "base") ein und startet
-- ServerScriptService.Garage.GarageServer wie Roblox.
local ROOT = ARGS[1] or "."
local FILTER = ARGS[2]

local function load(path)
	return loadsource(readfile(ROOT .. "/" .. path), path)()
end

local Mock = load("tests/mock_roblox.lua")

local T = { checks = 0, failures = {}, current = "" }

function T.check(cond, msg)
	T.checks += 1
	if not cond then
		table.insert(T.failures, T.current .. ": " .. tostring(msg))
	end
	return cond
end

function T.eq(actual, expected, msg)
	return T.check(actual == expected, (msg or "Wert") .. " – erwartet " .. tostring(expected) .. ", erhalten " .. tostring(actual))
end

function T.near(actual, expected, tol, msg)
	return T.check(type(actual) == "number" and math.abs(actual - expected) <= (tol or 1e-6), (msg or "Wert") .. " – erwartet ≈" .. tostring(expected) .. ", erhalten " .. tostring(actual))
end

local function tryList(dir)
	local ok, list = pcall(listdir, dir)
	return ok and list or {}
end

-- Alte 3.0-Ordner (werden nach src/mini portiert); fehlen sie, bleiben die Listen leer
local FILES = {
	shared = tryList(ROOT .. "/src/shared"),
	server = tryList(ROOT .. "/src/server"),
	client = tryList(ROOT .. "/src/client"),
}

---------------------------------------------------------------- Harness (alte 3.0-Tests)
local H = { Mock = Mock, T = T, ROOT = ROOT }

function H.Env(opts)
	local env = Mock.NewEnv(opts)
	Mock.Activate(env)
	Mock.LoadPlace(env, ROOT, FILES)
	return env
end

function H.Shared(env)
	local folder = env.services.ReplicatedStorage.Shared
	local mods = {}
	for _, inst in ipairs(folder:GetChildren()) do
		mods[inst.Name] = require(inst)
	end
	return mods
end

function H.ServerModule(env, name)
	return require(env.services.ServerScriptService.Server:WaitForChild(name))
end

-- Startet den kompletten alten 3.0-Server (Main.server.lua) mit Mock-Uhr
function H.Server(opts)
	opts = opts or {}
	local env = H.Env(opts)
	if opts.dataStoreGetFail then
		env.services.DataStoreService.__data.getFail = true
	end
	local srv = { env = env }
	srv.S = H.Shared(env)
	srv.Core = H.ServerModule(env, "Core")
	srv.Core.Now = function()
		return env.clock.now
	end
	srv.Core.Precise = function()
		return env.clock.precise
	end
	srv.Core.NewRandom = function()
		return Random.new(opts.seed or 4242)
	end
	for _, name in ipairs({ "Actions", "Profiles", "PressService", "LeaderboardService", "World", "DataUtil", "Purchases" }) do
		srv[name] = H.ServerModule(env, name)
	end
	if opts.before then
		opts.before(srv)
	end
	Mock.RunScript(env, env.services.ServerScriptService.Server.Main)
	T.check(#env.scheduler.errors == 0, "Serverstart ohne Laufzeitfehler: " .. table.concat(env.scheduler.errors, " | "))
	return srv
end

function H.Join(srv, userId, name)
	Mock.Activate(srv.env)
	local p = Mock.NewPlayer(srv.env, userId, name)
	Mock.Join(srv.env, p)
	return p
end

function H.Leave(srv, player)
	Mock.Activate(srv.env)
	Mock.Leave(srv.env, player)
end

function H.Session(srv, player)
	return srv.Core.Get(player)
end

function H.Profile(srv, player)
	local s = srv.Core.Get(player)
	return s and s.profile
end

function H.Act(srv, player, action, payload)
	Mock.Activate(srv.env)
	return srv.Actions.Handle(player, action, payload)
end

function H.Advance(srv, seconds)
	Mock.Activate(srv.env)
	srv.env.clock:Advance(seconds)
end

-- Alle Nachrichten eines Remotes an einen Spieler
function H.Sent(srv, remoteName, player)
	local remote = srv.env.services.ReplicatedStorage.Remotes[remoteName]
	local out = {}
	for _, e in ipairs(remote.__data.sent or {}) do
		if e.player == player then
			table.insert(out, e.args)
		end
	end
	return out
end

function H.Notices(srv, player, kind)
	local out = {}
	for _, args in ipairs(H.Sent(srv, "Notice", player)) do
		if args[1] == kind then
			table.insert(out, args[2])
		end
	end
	return out
end

function H.LastSync(srv, player)
	local list = H.Sent(srv, "Sync", player)
	return list[#list] and list[#list][1]
end

function H.Store(srv)
	local ds = srv.env.services.DataStoreService.__data
	return ds.stores[srv.S.Config.ProfileStoreName], ds
end

function H.Close(srv)
	Mock.Activate(srv.env)
	for _, fn in ipairs(srv.env.game.__data.closeCallbacks) do
		srv.env.scheduler:spawn(fn)
	end
	srv.env.clock:Advance(30)
end

function H.Errors(env)
	return env.scheduler.errors
end

---------------------------------------------------------------- Fixture (Basisbaum) mit Aktualitätsprüfung
-- Gleiche Prüfsumme wie tools/export_fixture.py (zwei Polynom-Hashes über 3-Byte-Gruppen)
local function fileHash(s)
	local h1, h2 = 0, 0
	local byte = string.byte
	for i = 1, #s, 3 do
		local a, b, c = byte(s, i, i + 2)
		local w = a + (b or 0) * 256 + (c or 0) * 65536
		h1 = (h1 * 1000003 + w) % 2147483647
		h2 = (h2 * 65599 + w + 1) % 1000000007
	end
	return string.format("%08x%08x", h1, h2)
end
H.FileHash = fileHash

local REGENERATE = "Neu erzeugen mit: python3 tools/export_fixture.py"
local function staleReasons(fixture, name)
	local reasons = {}
	for _, src in ipairs(fixture.sources or {}) do
		local ok, content = pcall(readfile, ROOT .. "/" .. src.path)
		if not ok then
			table.insert(reasons, src.path .. " fehlt")
		elseif #content ~= src.size or fileHash(content) ~= src.hash then
			table.insert(reasons, src.path .. " wurde geändert")
		end
	end
	if fixture.worldgen ~= nil and fixture.source == "base+worldgen" then
		local now = tryList(ROOT .. "/tools/worldgen")
		local recorded = {}
		for _, f in ipairs(fixture.worldgen or {}) do
			recorded[f] = true
		end
		for _, f in ipairs(now) do
			if not recorded[f] and not f:match("%.pyc$") then
				table.insert(reasons, "neue Datei tools/worldgen/" .. f)
			end
		end
		if fixture.worldgen == false and #now > 0 then
			table.insert(reasons, "tools/worldgen ist neu")
		end
	end
	return reasons
end

local fixtureCache = {}
local function loadFixture(name)
	local cached = fixtureCache[name]
	if cached then
		if cached.err then
			error(cached.err, 0)
		end
		return cached.value
	end
	local path = "tests/fixtures/" .. name .. ".lua"
	local ok, fixture = pcall(load, path)
	if not ok then
		fixtureCache[name] = { err = path .. " fehlt oder ist defekt (" .. tostring(fixture) .. "). " .. REGENERATE }
		error(fixtureCache[name].err, 0)
	end
	local reasons = staleReasons(fixture, name)
	if #reasons > 0 then
		fixtureCache[name] = { err = path .. " ist veraltet: " .. table.concat(reasons, "; ") .. ". " .. REGENERATE }
		error(fixtureCache[name].err, 0)
	end
	fixtureCache[name] = { value = fixture }
	return fixture
end
H.LoadFixture = loadFixture

---------------------------------------------------------------- Zuordnung src -> Place (wie tools/build_place.py)
local FALLBACK_MAPPING = {
	{ dir = "src/garage/shared", path = { "ReplicatedStorage", "GarageShared" } },
	{ dir = "src/garage/server", path = { "ServerScriptService", "Garage" } },
	{ dir = "src/garage/client", path = { "StarterPlayer", "StarterPlayerScripts" } },
	{ dir = "src/mini/shared", path = { "ReplicatedStorage", "GarageShared", "Mini" } },
	{ dir = "src/mini/server", path = { "ServerScriptService", "Garage", "Mini" } },
	{ dir = "src/mini/client", path = { "StarterPlayer", "StarterPlayerScripts", "Mini" } },
}
local mappingCache
local function projectMapping()
	if mappingCache then
		return mappingCache
	end
	local ok, project = pcall(function()
		return Mock.JSONDecode(readfile(ROOT .. "/default.project.json"))
	end)
	if not ok or type(project) ~= "table" or type(project.tree) ~= "table" then
		mappingCache = FALLBACK_MAPPING
		return mappingCache
	end
	local out = {}
	local function walk(node, path)
		for key, child in pairs(node) do
			if type(key) == "string" and key:sub(1, 1) ~= "$" and type(child) == "table" then
				local here = table.clone(path)
				table.insert(here, key)
				if type(child["$path"]) == "string" then
					table.insert(out, { dir = child["$path"], path = here })
				end
				walk(child, here)
			end
		end
	end
	walk(project.tree, {})
	table.sort(out, function(a, b)
		if #a.path ~= #b.path then
			return #a.path < #b.path
		end
		return table.concat(a.path, ".") < table.concat(b.path, ".")
	end)
	mappingCache = #out > 0 and out or FALLBACK_MAPPING
	return mappingCache
end
H.ProjectMapping = projectMapping

local function ensurePath(env, path)
	local node = env.services[path[1]] or Mock.CreateService(env, path[1])
	for i = 2, #path do
		local nxt = node:FindFirstChild(path[i])
		if not nxt then
			nxt = env.Instance.new("Folder")
			nxt.Name = path[i]
			nxt.Parent = node
		end
		node = nxt
	end
	return node
end

local function addScript(env, parent, cls, name, source, chunk)
	local inst = env.Instance.new(cls)
	inst.Name = name
	inst.Source = source
	inst.__data.path = chunk
	inst.Parent = parent
	return inst
end

-- Setzt die Skripte ein: "src" (Standard, Ordner aus default.project.json) oder "base" (2.4.0 unverändert)
local function insertScripts(env, opts)
	local mode = opts.scripts or "src"
	local list = {}
	if mode == "base" then
		local fx = loadFixture("base_scripts")
		for _, s in ipairs(fx.scripts) do
			local parentPath = table.move(s.path, 1, #s.path - 1, 1, {})
			local inst = addScript(env, ensurePath(env, parentPath), s.class, s.path[#s.path], s.source, "base:" .. table.concat(s.path, "/"))
			table.insert(list, inst)
		end
		return list
	end
	local srcRoot = opts.srcRoot or ROOT
	for _, m in ipairs(projectMapping()) do
		local dir = m.dir
		if opts.mini == false and dir:find("mini", 1, true) then
			continue
		end
		local files = tryList(srcRoot .. "/" .. dir)
		local parent
		for _, file in ipairs(files) do
			if file:match("%.lua$") or file:match("%.luau$") then
				parent = parent or ensurePath(env, m.path)
				local cls, name = Mock.Classify((file:gsub("%.luau$", ".lua")))
				local source = readfile(srcRoot .. "/" .. dir .. "/" .. file)
				table.insert(list, addScript(env, parent, cls, name, source, dir .. "/" .. file))
			end
		end
	end
	return list
end

---------------------------------------------------------------- H.Garage: echter 2.4.0-Server (und Clients)
local Garage = {}
Garage.__index = Garage

-- opts: scripts = "src" | "base", srcRoot, mini = false, studio, startTime, seed, frameStep, viewport,
--       shareDataStoresWith = <anderes Garage-Objekt> (gleiche "Cloud"), dataStore = {updateYield, strict, ...},
--       before = function(g) (vor dem Serverstart, z. B. Profile anlegen), noServer = true
function H.Garage(opts)
	opts = opts or {}
	local fixture = loadFixture("base_tree")
	local env = Mock.NewEnv({
		startTime = opts.startTime,
		studio = opts.studio,
		frameStep = opts.frameStep,
		viewport = opts.viewport,
		echoErrors = opts.echoErrors,
		jobId = opts.jobId,
		kickRemovesPlayer = opts.kickRemovesPlayer,
	})
	Mock.Activate(env)
	math.randomseed(opts.seed or 24)
	Mock.LoadTree(env, fixture)
	local g = setmetatable({ env = env, opts = opts, fixture = fixture, players = {} }, Garage)
	g.scripts = insertScripts(env, opts)
	local ds = env.services.DataStoreService.__data
	if opts.shareDataStoresWith then
		local other = opts.shareDataStoresWith.env.services.DataStoreService.__data
		ds.stores = other.stores
		ds.ordered = other.ordered
	end
	for k, v in pairs(opts.dataStore or {}) do
		ds[k] = v
	end
	if opts.before then
		opts.before(g)
	end
	if not opts.noServer then
		g:StartServer()
	end
	return g
end

function Garage:Activate()
	Mock.Activate(self.env)
	return self
end

-- Startet alle Server-Skripte (Script unter ServerScriptService) im Server-Kontext
function Garage:StartServer()
	self:Activate()
	for _, x in ipairs(self.env.services.ServerScriptService:GetDescendants()) do
		if x.ClassName == "Script" and not x.Disabled and x.Enabled ~= false then
			Mock.RunScript(self.env, x)
		end
	end
	Mock.Flush(self.env)
	return self
end

function Garage:Find(path)
	local node = self.env.game
	for part in string.gmatch(path, "[^%.]+") do
		local nxt = self.env.services[part] and node == self.env.game and self.env.services[part] or node:FindFirstChild(part)
		if not nxt then
			return nil
		end
		node = nxt
	end
	return node
end

-- Lädt ein ModuleScript im Server-Kontext, z. B. g:Require("ReplicatedStorage.GarageShared.Config")
function Garage:Require(path)
	self:Activate()
	local inst = assert(self:Find(path), "Modul fehlt: " .. path)
	return Mock.Require(self.env, inst)
end

function Garage:Config()
	return self:Require("ReplicatedStorage.GarageShared.Config")
end

function Garage:Rules()
	return self:Require("ReplicatedStorage.GarageShared.Rules")
end

function Garage:Remote(name)
	return self:Find("ReplicatedStorage.GarageShared.Remotes." .. name)
end

function Garage:Now()
	return self.env.clock.wall
end

function Garage:Flush()
	self:Activate()
	Mock.Flush(self.env)
end

function Garage:Advance(seconds)
	self:Activate()
	self.env.clock:Advance(seconds)
end

-- Lässt die Serverzeit (workspace:GetServerTimeNow) genau bis `t` laufen
function Garage:AdvanceTo(t)
	local dt = t - self.env.clock.wall
	if dt > 0 then
		self:Advance(dt)
	end
end

-- Spieler betritt das Spiel; standardmäßig erscheint danach seine Figur (wie CharacterAutoLoads)
function Garage:Join(userId, opts)
	opts = opts or {}
	self:Activate()
	local p = Mock.NewPlayer(self.env, userId, opts.name)
	table.insert(self.players, p)
	Mock.Join(self.env, p)
	Mock.Flush(self.env)
	if opts.character ~= false and p.Parent then
		Mock.SpawnCharacter(self.env, p, opts.at)
		Mock.Flush(self.env)
	end
	return p
end

function Garage:Leave(player)
	self:Activate()
	Mock.Leave(self.env, player)
	Mock.Flush(self.env)
end

function Garage:Respawn(player, at)
	self:Activate()
	local ch = Mock.SpawnCharacter(self.env, player, at)
	Mock.Flush(self.env)
	return ch
end

-- Sendet eine Client-Absicht über GarageShared.Remotes.Command (wie Command:FireServer(action, args))
function Garage:Send(player, action, args)
	self:Activate()
	local command = assert(self:Remote("Command"), "Remotes.Command fehlt")
	Mock.FireServerAs(self.env, command, player, action, args or {})
	Mock.Flush(self.env)
end

-- Position im Event-Verlauf (für Events(..., since))
function Garage:Mark()
	local event = self:Remote("Event")
	return #(event.__data.sent or {})
end

-- Alle Event-Nachrichten `kind` an den Spieler (Nutzlast als Kopie zum Sendezeitpunkt)
function Garage:Events(player, kind, since)
	local event = self:Remote("Event")
	local out = {}
	local sent = event.__data.sent or {}
	for i = (since or 0) + 1, #sent do
		local e = sent[i]
		if e.player == player and (kind == nil or e.args[1] == kind) then
			table.insert(out, kind and e.args[2] or { kind = e.args[1], data = e.args[2], t = e.t })
		end
	end
	return out
end

function Garage:Last(player, kind, since)
	local list = self:Events(player, kind, since)
	return list[#list]
end

function Garage:Toasts(player, since)
	return self:Events(player, "toast", since)
end

function Garage:HasToast(player, pattern, since)
	for _, msg in ipairs(self:Toasts(player, since)) do
		if type(msg) == "string" and msg:find(pattern, 1, true) then
			return true
		end
	end
	return false
end

function Garage:State(player)
	return self:Last(player, "state")
end

function Garage:Data(player)
	local s = self:State(player)
	return s and s.data
end

function Garage:Plot(player)
	local folder = self.env.workspace:FindFirstChild("PlayerWorkshops")
	return folder and folder:FindFirstChild("Plot_" .. player.UserId)
end

function Garage:Station(player, key)
	local plot = self:Plot(player)
	return plot and plot.Stations:FindFirstChild(key)
end

function Garage:Car(player, jobId)
	local plot = self:Plot(player)
	return plot and plot.ActiveCars:FindFirstChild(jobId)
end

function Garage:Root(player)
	local ch = player.Character
	return ch and ch:FindFirstChild("HumanoidRootPart")
end

function Garage:Teleport(player, target, offset)
	self:Activate()
	Mock.Teleport(self.env, player, target, offset)
end

function Garage:Trigger(player, prompt, opts)
	self:Activate()
	return Mock.TriggerPrompt(self.env, prompt, player, opts)
end

function Garage:DataStoreMock()
	return self.env.services.DataStoreService.__data
end

-- Profil-Store (Config.DataStoreName bzw. StudioDataStoreName) als Rohtabelle {[key] = record}
function Garage:Store()
	local C = self:Config()
	local name = self.env.studio and C.StudioDataStoreName or C.DataStoreName
	local ds = self:DataStoreMock()
	ds.stores[name] = ds.stores[name] or { data = {}, name = name }
	return ds.stores[name].data
end

function Garage:Record(userId)
	return self:Store()["Player_" .. userId]
end

-- Legt einen gespeicherten Datensatz an (z. B. {version=2, data={...}, receipts={}}), vor dem Beitritt
function Garage:Seed(userId, record)
	self:Store()["Player_" .. userId] = Mock.JSONDecode(Mock.JSONEncode(record))
end

-- BindToClose-Rückrufe ausführen und bis zu 30 s warten
function Garage:Close()
	self:Activate()
	for _, fn in ipairs(self.env.game.__data.closeCallbacks or {}) do
		self.env.scheduler:spawnIn(self.env.serverCtx, fn)
	end
	self.env.clock:Advance(30)
end

function Garage:Errors()
	return self.env.scheduler.errors
end

function Garage:Warnings()
	return self.env.warnings
end

function Garage:ErrorText()
	return table.concat(self.env.scheduler.errors, "\n---\n")
end

-- Client (LocalScripts aus StarterPlayerScripts) für den Spieler starten
function Garage:StartClient(player)
	self:Activate()
	return Mock.StartClient(self.env, player)
end

function Garage:Key(player, key, state)
	self:Activate()
	if state then
		return Mock.Input(self.env, player, key, state)
	end
	return Mock.KeyPress(self.env, player, key)
end

function Garage:Click(button, opts)
	self:Activate()
	return Mock.Click(self.env, button, opts)
end

function Garage:ClickWorld(player, part)
	self:Activate()
	Mock.ClickWorld(self.env, player, part)
end

-- Sucht in PlayerGui ein GUI-Objekt: Text (Teilstring) oder Prädikat; nur sichtbare, außer opts.hidden
function Garage:FindGui(player, what, opts)
	opts = opts or {}
	local gui = player:FindFirstChild("PlayerGui")
	if not gui then
		return nil
	end
	for _, x in ipairs(gui:GetDescendants()) do
		if x:IsA("GuiObject") and (opts.hidden or Mock.IsGuiVisible(x)) then
			local hit
			if type(what) == "function" then
				hit = what(x)
			else
				local text = x.Text
				hit = type(text) == "string" and text:find(what, 1, true) ~= nil and (not opts.class or x:IsA(opts.class))
			end
			if hit then
				return x
			end
		end
	end
	return nil
end

H.GarageMeta = Garage

---------------------------------------------------------------- Ausführen
local testFiles = {}
for _, f in ipairs(listdir(ROOT .. "/tests")) do
	if f:match("^test_.*%.lua$") and (not FILTER or f:find(FILTER, 1, true)) then
		table.insert(testFiles, f)
	end
end

for _, f in ipairs(testFiles) do
	local okLoad, suite = pcall(load, "tests/" .. f)
	if not okLoad then
		table.insert(T.failures, f .. ": Datei lädt nicht: " .. tostring(suite))
		T.checks += 1
		continue
	end
	for _, case in ipairs(suite) do
		T.current = f .. " › " .. case[1]
		local ok, err = pcall(case[2], T, H)
		if not ok then
			table.insert(T.failures, T.current .. ": Laufzeitfehler: " .. tostring(err))
			T.checks += 1
		end
	end
end

for _, msg in ipairs(T.failures) do
	print("FEHLER " .. msg)
end
print(string.format("Tests: %d Dateien, %d Prüfungen, %d Fehler", #testFiles, T.checks, #T.failures))
if #T.failures > 0 then
	error("Tests fehlgeschlagen")
end
