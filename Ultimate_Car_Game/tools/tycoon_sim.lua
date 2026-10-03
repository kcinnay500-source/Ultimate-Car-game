-- tycoon_sim.lua: Rundendauer des Tycoons (Tycoon) mit den echten Regeln (TycoonRules, GameConfig.Tycoon)
-- als JSON – für tools/economy_sim.py --tycoon (PHASE4_CONTRACT §8: Ziel ≈ 5 Std. aktiv bis Stufe 5 komplett).
-- Aufruf (aus dem Projektordner): tools/luaurun/target/release/luaurun run tools/tycoon_sim.lua .
-- Gieriger Spieler wie in tests/test_tycoon_rules.lua simulate(): alle 15 s sammeln und das teuerste bezahlbare
-- Angebot kaufen (Stufen-Pad eingeschlossen); der Server tickt alle 0,5 s. Zweiter Durchlauf mit Rebirth-Boost.
-- Reine Datenmodule über denselben Ersatz für script/WaitForChild wie economy_dump.lua (ohne Roblox-Mock).
local ROOT = ARGS[1] or "."

local FILES = {
	Config = "src/garage/shared/Config.lua",
	GameConfig = "src/mini/shared/GameConfig.lua",
	PrestigeRules = "src/mini/shared/PrestigeRules.lua",
	TycoonRules = "src/mini/shared/TycoonRules.lua",
	Unlocks = "src/mini/shared/Unlocks.lua",
}

local loaded = {}
local node
local function requireName(name)
	if loaded[name] == nil then
		local path = FILES[name]
		assert(path, "tycoon_sim: Modul nicht vorgesehen: " .. tostring(name))
		local fn = loadsource("local script = ...; " .. readfile(ROOT .. "/" .. path), path)
		loaded[name] = fn(node(name))
	end
	return loaded[name]
end

function node(name)
	local n = { Name = name }
	n.Parent = setmetatable({}, {
		__index = function(_, k)
			if k == "WaitForChild" then
				return function(_, child)
					return node(child)
				end
			elseif k == "Parent" then
				return { WaitForChild = function(_, child)
					return node(child)
				end }
			end
		end,
	})
	n.WaitForChild = function(_, child)
		return node(child)
	end
	return n
end

local rawRequire = require
require = function(x)
	if type(x) == "table" and x.Name then
		return requireName(x.Name)
	end
	return rawRequire(x)
end

local GC = requireName("GameConfig")
local TR = requireName("TycoonRules")
local TY = GC.Tycoon

local NOW = 1760000000
local STEP = 15 -- Sekunden zwischen Sammeln/Kaufen
local LIMIT = 12 * 3600

local function simulate(d, typ)
	local run = TR.NewRun(d, typ, d._t)
	assert(run, "NewRun " .. typ)
	local t = d._t
	local start = t
	local stages = {}
	local lastStage = 1
	while t - start < LIMIT do
		t += STEP
		for _ = 1, STEP * 2 do
			TR.Tick(run, run.lastTick + 0.5)
		end
		TR.Collect(run)
		local bought = true
		while bought do
			bought = false
			local best, bestCost = nil, -1
			for _, o in ipairs(TR.Offers(run)) do
				if o.ok and o.cost > bestCost then
					best, bestCost = o.id, o.cost
				end
			end
			if best then
				TR.Buy(run, best)
				bought = true
			end
		end
		if run.stage > lastStage then
			lastStage = run.stage
			stages[run.stage] = t - start
		end
		if run.stage == TY.MaxStage and TR.StageComplete(run, run.stage) then
			d._t = t
			return t - start, run, stages
		end
	end
	d._t = t
	return nil, run, stages
end

local out = { types = {}, target = { min = 4 * 3600, max = 6.5 * 3600 } }
for _, typ in ipairs(TY.Types) do
	local d = { level = 1, games = {}, _t = NOW }
	TR.ApplyDefault(d.games)
	local seconds, run, stages = simulate(d, typ)
	local okR = TR.Rebirth(d, d._t)
	local second = nil
	if okR then
		second = simulate(d, typ)
	end
	table.insert(out.types, {
		typ = typ,
		name = TY.Buildings[typ].name,
		seconds = seconds,
		second = second,
		produced = run.produced,
		stages = { stages[2], stages[3], stages[4], stages[5] },
	})
end

-- JSON (nur Zahlen, Strings, Listen, Tabellen mit String-Schlüsseln)
local function encode(v)
	local t = type(v)
	if t == "number" then
		if v ~= v or v == math.huge or v == -math.huge then
			return "null"
		end
		if v == math.floor(v) and math.abs(v) < 1e15 then
			return string.format("%d", v)
		end
		return string.format("%.17g", v)
	elseif t == "string" then
		return '"' .. v:gsub('[%c"\\]', function(c)
			return string.format("\\u%04x", string.byte(c))
		end) .. '"'
	elseif t == "boolean" then
		return v and "true" or "false"
	elseif t == "nil" then
		return "null"
	elseif t == "table" then
		if #v > 0 or next(v) == nil then
			local parts = {}
			for i = 1, #v do
				parts[i] = encode(v[i])
			end
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k in pairs(v) do
			table.insert(keys, tostring(k))
		end
		table.sort(keys)
		local parts = {}
		for _, k in ipairs(keys) do
			table.insert(parts, encode(k) .. ":" .. encode(v[k]))
		end
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

print(encode(out))
