-- economy_dump.lua: gibt die Balance-Zahlen der echten Module als JSON aus (für tools/economy_sim.py).
-- Aufruf (aus dem Projektordner): tools/luaurun/target/release/luaurun run tools/economy_dump.lua .
-- Lädt nur reine Datenmodule (GarageShared.Config, Mini: MiniConfig, MiniCatalog, CarCatalog, ArcadeRules,
-- TrackRules, AuctionRules-Zahlen) über einen kleinen Ersatz für script/WaitForChild – ohne Roblox-Mock.
local ROOT = ARGS[1] or "."

local FILES = {
	Config = "src/garage/shared/Config.lua",
	MiniConfig = "src/mini/shared/MiniConfig.lua",
	MiniCatalog = "src/mini/shared/MiniCatalog.lua",
	CarCatalog = "src/mini/shared/CarCatalog.lua",
	ArcadeRules = "src/mini/shared/ArcadeRules.lua",
	TrackRules = "src/mini/shared/TrackRules.lua",
	-- Ausbaustufe 4: CarCatalog nimmt die Händler-Level aus GameConfig.Unlocks (reine Datenmodule)
	Unlocks = "src/mini/shared/Unlocks.lua",
	GameConfig = "src/mini/shared/GameConfig.lua",
	PrestigeRules = "src/mini/shared/PrestigeRules.lua",
}

local loaded = {}
local node
local function requireName(name)
	if loaded[name] == nil then
		local path = FILES[name]
		assert(path, "economy_dump: Modul nicht vorgesehen: " .. tostring(name))
		local fn = loadsource("local script = ...; " .. readfile(ROOT .. "/" .. path), path)
		loaded[name] = fn(node(name))
	end
	return loaded[name]
end

-- Ersatz-Instanz: WaitForChild liefert einen Knoten, require(Knoten) lädt die Datei gleichen Namens.
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

-- JSON (Funktionen und Zyklen werden ausgelassen)
local function encode(v, seen)
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
		return tostring(v)
	elseif t == "table" then
		seen = seen or {}
		if seen[v] then
			return "null"
		end
		seen[v] = true
		local n = #v
		local parts = {}
		if n > 0 then
			for i = 1, n do
				parts[i] = encode(v[i], seen)
			end
			seen[v] = nil
			return "[" .. table.concat(parts, ",") .. "]"
		end
		local keys = {}
		for k, x in pairs(v) do
			if type(k) == "string" and type(x) ~= "function" then
				table.insert(keys, k)
			end
		end
		table.sort(keys)
		for _, k in ipairs(keys) do
			table.insert(parts, encode(k) .. ":" .. encode(v[k], seen))
		end
		seen[v] = nil
		return "{" .. table.concat(parts, ",") .. "}"
	end
	return "null"
end

local C = requireName("Config")
local MC = requireName("MiniConfig")
local Cat = requireName("MiniCatalog")
local CC = requireName("CarCatalog")
local AR = requireName("ArcadeRules")
local TR = requireName("TrackRules")
local GC = requireName("GameConfig")

local arcade = {}
for k, v in pairs(AR) do
	if type(v) ~= "function" and k ~= "GameByKey" and k ~= "GameByName" then
		arcade[k] = v
	end
end

-- mittlere Rundendauer je Automat (Sekunden ab Spielbeginn, ohne Countdown) aus 40 Seeds
local durations = {}
for _, def in ipairs(AR.Games) do
	local sum, n = 0, 0
	for seed = 1, 40 do
		local ok, round = pcall(AR.NewRound, def.key, seed * 7919, 1000, seed)
		if ok and type(round) == "table" and type(round.duration) == "number" then
			sum += round.duration
			n += 1
		end
	end
	durations[def.key] = n > 0 and sum / n or nil
end
arcade.RoundSeconds = durations

local models = {}
for _, m in ipairs(CC.Models) do
	table.insert(models, m)
end

print(encode({
	config = {
		StartMoney = C.StartMoney,
		Cars = C.Cars,
		Jobs = C.Jobs,
		PartTypes = C.PartTypes,
		Brands = C.Brands,
		Equipment = C.Equipment,
		Upgrades = C.Upgrades,
		BayLevels = C.BayLevels,
		YardTasks = C.YardTasks,
	},
	mini = MC,
	pressUpgrades = Cat.PressUpgrades,
	cars = {
		Models = models,
		Tune = CC.Tune,
		TuneParts = CC.TuneParts,
		TuneGrowth = CC.TuneGrowth,
		TuneMinCost = CC.TuneMinCost,
		Style = CC.Style,
		SellShare = CC.SellShare,
		Carwash = CC.Carwash,
		Track = CC.Track,
	},
	trackMaxSpeed = TR.MaxSpeed(),
	-- Ausbaustufe 4 (GameConfig): XP-Regler, Unlocks, Prestige, Tycoon-Boni, OW-Gebäude/Perks, Story, Shop
	game = {
		XP = GC.XP,
		Unlocks = GC.Unlocks,
		WorkshopRewardCap = GC.WorkshopRewardCap,
		TutorialReward = GC.Tutorial.Reward,
		Prestige = {
			MaxRank = GC.Prestige.MaxRank, BaseThresholds = GC.Prestige.BaseThresholds, Growth = GC.Prestige.Growth,
			RoundTo = GC.Prestige.RoundTo, IncomePerRank = GC.Prestige.IncomePerRank, IncomeCap = GC.Prestige.IncomeCap,
			DiscountPerRank = GC.Prestige.DiscountPerRank, DiscountCap = GC.Prestige.DiscountCap,
			RebirthBonusFromRank = GC.Prestige.RebirthBonusFromRank, RebirthBonus = GC.Prestige.RebirthBonus,
		},
		Tycoon = { Bonus = GC.Tycoon.Bonus, Rebirth = GC.Tycoon.Rebirth, Types = GC.Tycoon.Types },
		OW = {
			Types = GC.OW.Types, Buildings = GC.OW.Buildings, Perks = GC.OW.Perks, PerkCap = GC.OW.PerkCap,
			PassiveCapHours = GC.OW.PassiveCapHours,
		},
		Story = {
			Chapters = GC.Story.Chapters, Side = GC.Story.Side, Sale = GC.Story.Sale, Balance = GC.Story.Balance,
			Requires = GC.Story.Requires,
		},
		Shop = {
			Cosmetics = GC.Shop.Cosmetics, Products = GC.Shop.Products, Passes = GC.Shop.Passes,
			DlcPriceFactor = GC.Shop.DlcPriceFactor, BuyXp = GC.Shop.BuyXp,
		},
	},
	carBuyXp = CC.BuyXp,
	arcade = arcade,
}))
