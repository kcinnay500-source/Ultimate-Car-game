-- Test-Runner: führt alle tests/test_*.lua im Mock aus.
-- Aufruf (aus dem Projektordner): tools/luaurun/target/release/luaurun run tests/run_tests.lua .
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

local FILES = {
	shared = listdir(ROOT .. "/src/shared"),
	server = listdir(ROOT .. "/src/server"),
	client = listdir(ROOT .. "/src/client"),
}

---------------------------------------------------------------- Harness
local H = { Mock = Mock }

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

-- Startet den kompletten Server (Main.server.lua) mit Mock-Uhr
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

---------------------------------------------------------------- Ausführen
local testFiles = {}
for _, f in ipairs(listdir(ROOT .. "/tests")) do
	if f:match("^test_.*%.lua$") and (not FILTER or f:find(FILTER, 1, true)) then
		table.insert(testFiles, f)
	end
end

for _, f in ipairs(testFiles) do
	local suite = load("tests/" .. f)
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
