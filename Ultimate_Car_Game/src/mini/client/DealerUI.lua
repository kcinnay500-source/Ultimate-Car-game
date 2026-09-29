-- DealerUI: Tab "dealer" (Autohaus). Katalog mit 3D-Vorschau (ViewportFrame, Klon aus
-- ReplicatedStorage.GarageShared.PreviewCars.<body>, umgefärbt), Preis, Level, Fahrwerte als Balken,
-- Kaufen (mit Bestätigung), Probefahrt und "Meine Autos" (holen, zur Werkstatt, abstellen, tunen, verkaufen).
-- Der Client zeigt nur an und sendet Absichten: mini_car_buy {model}, mini_car_testdrive {model},
-- mini_car_spawn {id, at}, mini_car_despawn, mini_car_sell {id}. Preise, Level, Guthaben prüft der Server.
--
-- DealerUI.Lib: gemeinsame Helfer für CarTuningUI, TrackUI, CarwashUI (Katalog, Paletten, Vorschau, Namen).
-- Snapshot-Felder (PHASE2_CONTRACT §5, Form wie CarRules.SnapshotFields): cars (CarRules.View), activeCar,
-- spawnedCar, garageMax, catalog (CarRules.CatalogView; darf nur einmal kommen, wird zwischengespeichert).
-- Fehlende Werte (Grip, Gewicht, Paletten, Stufen-Grenzen) ergänzt das geteilte Modul CarCatalog, falls vorhanden.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("GarageShared")
local Mini = Shared:WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local DealerUI = {}
local Lib = {}
DealerUI.Lib = Lib

local UI, Remote, T, ctx
local refs = {}
local state -- letzter Snapshot

---------------------------------------------------------------- Lib: Daten
-- 2.4.0-Config (C.Cars / C.CarById: Namen, Karosserie, Grundfarbe). Begrenztes Warten: fehlt sie, nur Snapshot-Daten.
local C
do
	local ok, mod = pcall(function()
		local m = Shared:WaitForChild("Config", 10)
		return m and require(m)
	end)
	if ok and type(mod) == "table" then
		C = mod
	end
end
Lib.Config = C

-- Optional: geteilter Autokatalog (PHASE2_CONTRACT §3, CarCatalog). Nur wenn vorhanden, ohne zu warten.
-- Gefunden wird es einmal geladen; fehlt es (noch nicht repliziert), wird beim nächsten Aufruf erneut gesucht.
local catalogModule = nil
local catalogFailed = false
local function carCatalogModule()
	if catalogModule or catalogFailed then
		return catalogModule
	end
	local inst = Mini:FindFirstChild("CarCatalog")
	if inst and inst:IsA("ModuleScript") then
		local ok, mod = pcall(require, inst)
		if ok and type(mod) == "table" then
			catalogModule = mod
		else
			catalogFailed = true
		end
	end
	return catalogModule
end
Lib.CarCatalogModule = carCatalogModule

Lib.PartKeys = { "engine", "gearbox", "tires", "suspension", "nitro" }
Lib.PartNames = { engine = "Motor", gearbox = "Getriebe", tires = "Reifen", suspension = "Fahrwerk", nitro = "Nitro" }
Lib.PartDesc = {
	engine = "Mehr Leistung und Beschleunigung",
	gearbox = "Höhere Endgeschwindigkeit",
	tires = "Mehr Grip in Kurven",
	suspension = "Stabiler, weniger Wanken",
	nitro = "Schub auf Knopfdruck (Taste N)",
}
Lib.DefaultTuneMax = { engine = 5, gearbox = 5, tires = 5, suspension = 5, nitro = 3 }
Lib.MaxCars = 20
Lib.TestDriveSeconds = 60

-- Abholpunkte (City.CarSpawns.<key>) und ihre Anzeigenamen; erlaubt sind nur die Schlüssel des Servers
-- (CarCatalog.SpawnKeys), sonst diese Standardliste
Lib.SpawnNames = {
	dealer = "Autohaus",
	testdrive = "Übergabe-Halle",
	track = "Teststrecke",
	carwash = "Waschstraße",
	plaza = "Stadtplatz",
	scrapyard = "Schrottplatz",
	tuning = "Tuning-Zentrum",
	workshop = "Werkstatt",
}
Lib.NearSpawnDistance = 250

-- Ausweich-Paletten, falls weder Snapshot (carPalettes) noch CarCatalog Farben liefern
local FALLBACK = {
	paint = {
		{ "Petrol", { 47, 169, 163 } }, { "Signalrot", { 200, 40, 52 } }, { "Tiefschwarz", { 24, 26, 30 } },
		{ "Polarweiß", { 236, 238, 240 } }, { "Silber", { 176, 184, 192 } }, { "Racing-Gelb", { 240, 196, 40 } },
		{ "Orange", { 236, 120, 36 } }, { "Königsblau", { 44, 86, 200 } }, { "Grasgrün", { 70, 160, 70 } },
		{ "Violett", { 120, 72, 190 } }, { "Bordeaux", { 110, 24, 44 } }, { "Graphit", { 70, 76, 84 } },
	},
	rims = {
		{ "Stahl", { 97, 112, 124 } }, { "Schwarz", { 28, 30, 34 } }, { "Gold", { 212, 170, 60 } }, { "Chrom", { 215, 222, 230 } },
		{ "Rot", { 190, 40, 50 } }, { "Blau", { 50, 100, 210 } }, { "Bronze", { 150, 100, 60 } }, { "Weiß", { 240, 240, 240 } },
	},
	glow = {
		{ "Cyan", { 40, 220, 240 } }, { "Magenta", { 230, 60, 200 } }, { "Grün", { 60, 230, 90 } },
		{ "Rot", { 240, 50, 50 } }, { "Blau", { 60, 90, 255 } }, { "Gelb", { 250, 220, 50 } },
	},
}

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end
Lib.Num = num

-- Grenzen aus CarCatalog (Garage, Probefahrt), sonst Vertragswerte
function Lib.MaxGarage(s)
	local cat = carCatalogModule()
	return num(type(s) == "table" and s.garageMax) or num(cat and cat.MaxCars) or Lib.MaxCars
end

function Lib.TestDrive()
	local cat = carCatalogModule()
	return cat and type(cat.Testdrive) == "table" and num(cat.Testdrive.seconds) or Lib.TestDriveSeconds
end

-- Farbe aus Color3, {r,g,b}, {r=,g=,b=}, {color=...}/{rgb=...}
local function toColor(v)
	if typeof(v) == "Color3" then
		return v
	end
	if type(v) ~= "table" then
		return nil
	end
	if num(v[1]) and num(v[2]) and num(v[3]) then
		return Color3.fromRGB(num(v[1]), num(v[2]), num(v[3]))
	end
	if num(v.r) and num(v.g) and num(v.b) then
		return Color3.fromRGB(num(v.r), num(v.g), num(v.b))
	end
	return toColor(v.color or v.rgb or v.Color)
end
Lib.ToColor = toColor

local function normPalette(list, fallback)
	local out = {}
	if type(list) == "table" then
		for i, entry in ipairs(list) do
			local color = toColor(entry)
			if color then
				local name = type(entry) == "table" and (entry.name or entry.label or entry[4]) or nil
				table.insert(out, { name = type(name) == "string" and name or ("Farbe " .. i), color = color })
			end
		end
	end
	if #out == 0 then
		for _, f in ipairs(fallback) do
			table.insert(out, { name = f[1], color = Color3.fromRGB(f[2][1], f[2][2], f[2][3]) })
		end
	end
	return out
end

local paletteSource -- zuletzt gesehene Paletten aus dem Snapshot (kommen evtl. nur einmal)
local paletteCache
function Lib.Palettes(s)
	local src = s and (s.carPalettes or s.palettes)
	if type(src) == "table" and src ~= paletteSource then
		paletteSource = src
		paletteCache = nil
	end
	if paletteCache then
		return paletteCache
	end
	local from = paletteSource
	if not from then
		local cat = carCatalogModule()
		if cat then
			local p = type(cat.Palettes) == "table" and cat.Palettes or cat
			from = {
				paint = p.paint or p.Paints or p.Paint or cat.Paints,
				rims = p.rims or p.Rims or cat.Rims,
				glow = p.glow or p.Glows or p.Glow or cat.Glows,
			}
		end
	end
	from = from or {}
	paletteCache = {
		paint = normPalette(from.paint, FALLBACK.paint),
		rims = normPalette(from.rims, FALLBACK.rims),
		glow = normPalette(from.glow or from.underglow, FALLBACK.glow),
	}
	return paletteCache
end

-- Fahrwerte: stats{power, topSpeed, grip, weight} (Aliasse werden akzeptiert)
function Lib.Stats(e)
	if type(e) ~= "table" then
		return {}
	end
	local st = type(e.stats) == "table" and e.stats or e
	return {
		power = num(st.power or st.hp or st.ps),
		topSpeed = num(st.topSpeed or st.top or st.topSpeedKmh or st.vmax or st.maxSpeed),
		grip = num(st.grip),
		weight = num(st.weight),
		zeroTo100 = num(st.zeroTo100),
		drive = type(st.drive) == "string" and st.drive or nil,
	}
end

-- Modell-Grundwerte aus CarCatalog (Grip, Gewicht, Standardlack), falls das Modul vorhanden ist
function Lib.ModelDef(model)
	local cat = carCatalogModule()
	if not cat then
		return nil
	end
	if type(cat.Model) == "function" then
		local ok, def = pcall(cat.Model, model)
		if ok and type(def) == "table" then
			return def
		end
	end
	return type(cat.ModelById) == "table" and cat.ModelById[model] or nil
end

local function normEntry(e, key)
	if type(e) ~= "table" then
		return nil
	end
	local model = e.model or e.id or key
	if type(model) ~= "string" and type(model) ~= "number" then
		return nil
	end
	local cfg = C and C.CarById and C.CarById[model]
	local def = Lib.ModelDef(model)
	local stats = Lib.Stats(e)
	if def then
		local base = Lib.Stats(def)
		for k, v in pairs(base) do
			if stats[k] == nil then
				stats[k] = v
			end
		end
	end
	return {
		model = model,
		name = type(e.name) == "string" and e.name or (def and def.name) or (cfg and cfg.name) or "Auto",
		brand = type(e.brand) == "string" and e.brand or (def and def.brand) or (cfg and cfg.brand) or nil,
		body = type(e.body) == "string" and e.body or (def and def.body) or (cfg and cfg.body) or nil,
		price = num(e.price or e.cost) or (def and num(def.price)) or nil,
		level = num(e.level) or (def and num(def.level)) or (cfg and cfg.level) or 1,
		paint = num(e.paint) or (def and num(def.paint)) or nil,
		color = toColor(e.color) or (cfg and toColor(cfg.color)) or nil,
		stats = stats,
		special = e.special == true or e.buyable == false or e.dealer == false,
		desc = type(e.desc) == "string" and e.desc or nil,
	}
end

local function sortEntries(list)
	table.sort(list, function(a, b)
		if a.level ~= b.level then
			return a.level < b.level
		end
		if (a.price or 0) ~= (b.price or 0) then
			return (a.price or 0) < (b.price or 0)
		end
		return tostring(a.model) < tostring(b.model)
	end)
	return list
end

local function normCatalog(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local list = {}
	if #raw > 0 then
		for _, e in ipairs(raw) do
			local n = normEntry(e)
			if n then
				table.insert(list, n)
			end
		end
	else
		for k, e in pairs(raw) do
			local n = normEntry(e, k)
			if n then
				table.insert(list, n)
			end
		end
	end
	if #list == 0 then
		return nil
	end
	return sortEntries(list)
end

local catalogSource, catalogCache, catalogFromServer = nil, nil, false
-- Katalog (normalisiert, sortiert): Snapshot > CarCatalog-Modul > 2.4.0-C.Cars (nur Anzeige, ohne Preis)
function Lib.Catalog(s)
	local raw = s and s.catalog
	if type(raw) == "table" and raw ~= catalogSource then
		local list = normCatalog(raw)
		if list then
			catalogSource, catalogCache, catalogFromServer = raw, list, true
		end
	end
	if catalogCache then
		return catalogCache, catalogFromServer
	end
	local cat = carCatalogModule()
	if cat then
		local list = normCatalog(cat.DealerModels or cat.Models or cat.Cars)
		if list then
			catalogCache, catalogFromServer = list, true
			return catalogCache, true
		end
	end
	local list = {}
	for _, v in ipairs(C and C.Cars or {}) do
		local n = normEntry({ model = v.id })
		if n then
			n.price = nil
			table.insert(list, n)
		end
	end
	return sortEntries(list), false
end

function Lib.Entry(s, model)
	for _, e in ipairs((Lib.Catalog(s))) do
		if e.model == model then
			return e
		end
	end
	return nil
end

function Lib.Cars(s)
	return type(s) == "table" and type(s.cars) == "table" and s.cars or {}
end

function Lib.FindCar(s, id)
	for _, car in ipairs(Lib.Cars(s)) do
		if car.id == id then
			return car
		end
	end
	return nil
end

function Lib.ActiveId(s)
	return type(s) == "table" and num(s.activeCar) or 0
end

-- Ist dieses Auto gerade draußen? spawnedId (CarService) bzw. aktives Auto + spawnedCar
function Lib.IsOut(s, car)
	if car == nil or type(s) ~= "table" then
		return false
	end
	local spawned = num(s.spawnedId)
	if spawned and spawned > 0 then
		return spawned == car.id
	end
	return Lib.ActiveId(s) == car.id and s.spawnedCar == true
end

-- Laufende Probefahrt aus dem Snapshot: {model, name, endsAt (Serverzeit)} oder nil
function Lib.TestDriveState(s)
	local td = type(s) == "table" and s.testdrive
	if type(td) == "table" and num(td.endsAt) and num(td.endsAt) > workspace:GetServerTimeNow() then
		return td
	end
	return nil
end

function Lib.CarName(s, car)
	if type(car) ~= "table" then
		return "Auto"
	end
	if type(car.name) == "string" and car.name ~= "" then
		return car.name
	end
	local e = Lib.Entry(s, car.model)
	return e and e.name or "Auto"
end

function Lib.CarBody(s, car)
	if type(car) ~= "table" then
		return nil
	end
	if type(car.body) == "string" then
		return car.body
	end
	local e = Lib.Entry(s, car.model)
	return e and e.body
end

function Lib.TuneMax(s)
	local cat = carCatalogModule()
	local tune = cat and type(cat.Tune) == "table" and cat.Tune or {}
	local out = {}
	for k, v in pairs(Lib.DefaultTuneMax) do
		out[k] = type(tune[k]) == "table" and num(tune[k].max) or v
	end
	return out
end

-- Level-Voraussetzung einer Optik-Änderung (CarCatalog.Style[key].level), sonst 1
function Lib.StyleLevel(key)
	local cat = carCatalogModule()
	local def = cat and type(cat.Style) == "table" and cat.Style[key]
	return type(def) == "table" and num(def.level) or 1
end

-- Antrieb lesbar
Lib.DriveNames = { FWD = "Frontantrieb", RWD = "Heckantrieb", AWD = "Allrad" }

-- Stil eines Autos (Palettenindex -> Farben). paint 0/nil = Grundfarbe des Modells, glow 0 = aus.
function Lib.Style(s, car, override)
	local pal = Lib.Palettes(s)
	local src = override or car or {}
	local paintIndex, rimsIndex, glowIndex = num(src.paint) or 0, num(src.rims) or 0, num(src.glow) or 0
	local base
	if car then
		local e = Lib.Entry(s, car.model)
		base = (e and e.paint and pal.paint[e.paint] and pal.paint[e.paint].color) or (e and e.color) or toColor(car.color)
	end
	local paint = pal.paint[paintIndex] and pal.paint[paintIndex].color or base or Color3.fromRGB(47, 169, 163)
	local rims = pal.rims[rimsIndex] and pal.rims[rimsIndex].color or nil
	local glow = glowIndex > 0 and pal.glow[glowIndex] and pal.glow[glowIndex].color or nil
	local spoiler = src.spoiler
	if type(spoiler) ~= "boolean" then
		spoiler = nil
	end
	return { paint = paint, rims = rims, glow = glow, spoiler = spoiler }
end

-- Nächster Abholpunkt (City.CarSpawns.<key>) in der Nähe der Figur, sonst die eigene Werkstatt.
-- Nur ein Wunsch: Der Server prüft den Schlüssel und wählt notfalls selbst.
function Lib.NearestSpawn()
	local city = workspace:FindFirstChild("City")
	local folder = city and city:FindFirstChild("CarSpawns")
	local player = Players.LocalPlayer
	local char = player and player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not folder or not root then
		return "workshop"
	end
	local allowed = {}
	local cat = carCatalogModule()
	if cat and type(cat.SpawnKeys) == "table" then
		for _, k in ipairs(cat.SpawnKeys) do
			allowed[k] = true
		end
	else
		for k in pairs(Lib.SpawnNames) do
			allowed[k] = true
		end
	end
	local best, bestDist = nil, Lib.NearSpawnDistance
	for _, child in ipairs(folder:GetChildren()) do
		local pos
		if child:IsA("BasePart") then
			pos = child.Position
		elseif child:IsA("Model") then
			pos = child:GetPivot().Position
		end
		if pos and allowed[child.Name] and child.Name ~= "workshop" then
			local dist = (pos - root.Position).Magnitude
			if dist < bestDist then
				best, bestDist = child.Name, dist
			end
		end
	end
	return best or "workshop"
end

---------------------------------------------------------------- Lib: Anzeige
local function ui()
	return UI or require(script.Parent:WaitForChild("MiniUI"))
end

function Lib.Number(n)
	return MiniLocale.Number(n or 0)
end

-- Rundenzeit: 83.456 -> "1:23,46"
function Lib.LapTime(seconds)
	seconds = num(seconds)
	if not seconds or seconds <= 0 then
		return "–"
	end
	local m = math.floor(seconds / 60)
	local s = seconds - m * 60
	return (string.format("%d:%05.2f", m, s):gsub("%.", ","))
end

-- Fahrwert-Balken: Zeile mit Text links und Balken rechts. Liefert {Set = function(value, max, text)}
function Lib.StatBar(parent, label, color, order)
	local U = ui()
	local th = U.Theme
	local row = U.Frame(parent, { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order or 0 })
	local text = U.Label(row, label, {
		AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(0.5, -6, 1, 0), TextSize = 13, TextColor3 = th.muted,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd, TextYAlignment = Enum.TextYAlignment.Center,
	})
	local bar = U.Frame(row, { AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = th.bg, Size = UDim2.new(0.5, 0, 0, 8), Position = UDim2.new(0.5, 0, 0.5, -4) })
	U.Corner(bar, 4)
	local fill = U.Frame(bar, { AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = color or th.green, Size = UDim2.new(0, 0, 1, 0) })
	U.Corner(fill, 4)
	local item = { root = row, label = text, fill = fill }
	function item.Set(value, max, caption)
		text.Text = caption or label
		U.SetProgress(fill, value and max and max > 0 and value / max or 0)
	end
	return item
end

-- Vier Fahrwert-Balken (Leistung, Höchstgeschwindigkeit, Grip, Gewicht)
function Lib.StatBlock(parent, order)
	local U = ui()
	local th = U.Theme
	local box = U.Frame(parent, { BackgroundTransparency = 1, LayoutOrder = order or 0 })
	U.List(box, 4)
	local block = {
		root = box,
		power = Lib.StatBar(box, "Leistung", th.red, 1),
		topSpeed = Lib.StatBar(box, "Höchstgeschw.", th.yellow, 2),
		grip = Lib.StatBar(box, "Grip", th.green, 3),
		weight = Lib.StatBar(box, "Gewicht", th.blue, 4),
	}
	function block.Set(st, maxima)
		st = st or {}
		maxima = maxima or {}
		block.power.Set(st.power, maxima.power, st.power and ("Leistung " .. MiniLocale.Number(st.power) .. " PS") or "Leistung –")
		block.topSpeed.Set(st.topSpeed, maxima.topSpeed, st.topSpeed and ("Spitze " .. MiniLocale.Number(st.topSpeed) .. " km/h") or "Spitze –")
		block.grip.Set(st.grip, maxima.grip, st.grip and ("Grip " .. MiniLocale.Decimal(st.grip, 2)) or "Grip –")
		block.weight.Set(st.weight, maxima.weight, st.weight and ("Gewicht " .. MiniLocale.Number(st.weight) .. " kg") or "Gewicht –")
	end
	return block
end

-- Höchstwerte über Katalog und eigene Autos (Balken relativ zum stärksten Modell)
function Lib.StatMaxima(s)
	local m = { power = 0, topSpeed = 0, grip = 0, weight = 0 }
	local function add(st)
		for k in pairs(m) do
			if st[k] and st[k] > m[k] then
				m[k] = st[k]
			end
		end
	end
	for _, e in ipairs((Lib.Catalog(s))) do
		add(e.stats)
	end
	for _, car in ipairs(Lib.Cars(s)) do
		add(Lib.Stats(car))
	end
	return m
end

local PAINT_PARTS = { Paint = true, Hood = true, Mirror = true }
local SPOILER_PARTS = { Spoiler = true, SpoilerMount = true, RoofSpoiler = true, RearWingEnd = true }
local function isRimPart(name)
	return name:match("^Wheel%u%uRim$") ~= nil or name:match("^Wheel%u%uSpoke$") ~= nil
end
Lib.IsRimPart = isRimPart
Lib.PaintParts = PAINT_PARTS
Lib.SpoilerParts = SPOILER_PARTS

-- Färbt ein Vorschau-Modell (Klon aus PreviewCars) wie das Fahrzeug: Lack (Paint/Hood/Mirror), Felgen
-- (Wheel**Rim/Wheel**Spoke), Spoiler (vorhandene Spoiler-Teile ein/aus, sonst ein schlichter Heckflügel),
-- Unterbodenlicht (Neon-Fläche unter dem Auto). Nur Optik im ViewportFrame.
function Lib.ApplyStyle(model, style, originals)
	originals = originals or {}
	local tail, chassis
	local hasSpoiler = false
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local name = part.Name
			if PAINT_PARTS[name] then
				part.Color = style.paint
			elseif isRimPart(name) then
				if originals[part] == nil then
					originals[part] = part.Color
				end
				part.Color = style.rims or originals[part]
			elseif SPOILER_PARTS[name] then
				hasSpoiler = true
				if originals[part] == nil then
					originals[part] = part.Transparency
				end
				part.Transparency = style.spoiler == false and 1 or originals[part]
			elseif name == "TailLamp" and (not tail or part.Position.Z > tail.Position.Z) then
				tail = part
			elseif name == "Chassis" then
				chassis = part
			end
		end
	end
	-- zusätzlicher Heckflügel für Karosserien ohne eigenen Spoiler
	local wing = model:FindFirstChild("PreviewSpoiler")
	if style.spoiler == true and not hasSpoiler and tail then
		if not wing then
			wing = Instance.new("Model")
			wing.Name = "PreviewSpoiler"
			local y, z = tail.Position.Y, tail.Position.Z - 0.9
			local function piece(size, pos)
				local p = Instance.new("Part")
				p.Name = "Wing"
				p.Anchored = true
				p.CanCollide = false
				p.Material = Enum.Material.SmoothPlastic
				p.Size = size
				p.CFrame = CFrame.new(pos)
				p.Parent = wing
				return p
			end
			piece(Vector3.new(7.2, 0.18, 1.1), Vector3.new(0, y + 1.25, z))
			piece(Vector3.new(0.22, 1.1, 0.35), Vector3.new(-2.4, y + 0.65, z))
			piece(Vector3.new(0.22, 1.1, 0.35), Vector3.new(2.4, y + 0.65, z))
			wing.Parent = model
		end
		for _, p in ipairs(wing:GetChildren()) do
			if p:IsA("BasePart") then
				p.Color = style.paint
			end
		end
	elseif wing then
		wing:Destroy()
	end
	-- Unterbodenlicht als Lichtfläche am Boden (ViewportFrames zeigen keine Lichtquellen)
	local glow = model:FindFirstChild("PreviewGlow")
	if style.glow then
		if not glow then
			glow = Instance.new("Part")
			glow.Name = "PreviewGlow"
			glow.Anchored = true
			glow.CanCollide = false
			glow.Material = Enum.Material.Neon
			glow.Transparency = 0.3
			local length = chassis and chassis.Size.Z or 12
			local cz = chassis and chassis.Position.Z or 0
			glow.Size = Vector3.new(8.6, 0.06, length + 0.8)
			glow.CFrame = CFrame.new(0, 0.05, cz)
			glow.Parent = model
		end
		glow.Color = style.glow
	elseif glow then
		glow:Destroy()
	end
end

-- 3D-Vorschau: ViewportFrame mit WorldModel und fester Kamera wie im 2.4.0-Tablet (GarageClient viewport()).
-- preview:Set(body, style) tauscht die Karosserie nur bei Bedarf und färbt nur bei geänderter Optik neu.
function Lib.Preview(parent, height, order, props)
	local U = ui()
	local th = U.Theme
	local view = Instance.new("ViewportFrame")
	view.Name = "Vorschau"
	view.BackgroundColor3 = th.bg
	view.BorderSizePixel = 0
	view.Size = UDim2.new(1, 0, 0, height or 130)
	view.LayoutOrder = order or 0
	view.Ambient = Color3.fromRGB(150, 166, 187)
	view.LightColor = Color3.fromRGB(245, 246, 255)
	view.LightDirection = Vector3.new(-1, -1, -1)
	for k, v in pairs(props or {}) do
		view[k] = v
	end
	U.Corner(view, 10)
	local world = Instance.new("WorldModel")
	world.Parent = view
	local camera = Instance.new("Camera")
	camera.FieldOfView = 40
	camera.CFrame = CFrame.lookAt(Vector3.new(18, 11, -23), Vector3.new(0, 2, 0))
	camera.Parent = view
	view.CurrentCamera = camera
	local missing = U.Label(view, "Vorschau nicht verfügbar", {
		AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, TextSize = 14, TextColor3 = th.muted, Visible = false,
	})
	view.Parent = parent
	local preview = { frame = view, world = world, camera = camera, body = nil, model = nil, key = nil, originals = {} }
	function preview:Set(body, style)
		if body ~= self.body then
			self.body = body
			self.key = nil
			self.originals = {}
			if self.model then
				self.model:Destroy()
				self.model = nil
			end
			local folder = Shared:FindFirstChild("PreviewCars")
			local template = folder and type(body) == "string" and folder:FindFirstChild(body)
			if template and template:IsA("Model") then
				local ok, clone = pcall(function()
					return template:Clone()
				end)
				if ok and clone then
					clone.Parent = world
					self.model = clone
				end
			end
			missing.Visible = self.model == nil
		end
		if self.model and style then
			local key = table.concat({ tostring(style.paint), tostring(style.rims), tostring(style.glow), tostring(style.spoiler) }, "|")
			if key ~= self.key then
				self.key = key
				Lib.ApplyStyle(self.model, style, self.originals)
			end
		end
	end
	return preview
end

-- Wunsch aus "Meine Autos": dieses Auto im Tuning öffnen (CarTuningUI liest es beim nächsten Anzeigen)
Lib.TuneRequest = nil
function Lib.RequestTune(id)
	Lib.TuneRequest = id
end

---------------------------------------------------------------- Aufbau
local function statusLine(parent, order)
	return UI.Label(parent, "", { TextSize = 14, TextColor3 = T.green, LayoutOrder = order, Visible = false })
end

local function grid(parent, order)
	local U = ui()
	local f = U.Frame(parent, { BackgroundTransparency = 1, LayoutOrder = order or 0 })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -4, 0, U.MinTouch)
	gl.CellPadding = UDim2.new(0, 8, 0, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = f
	return f
end
Lib.Grid = function(parent, order)
	return grid(parent, order)
end

local function buyCar(entry)
	if not entry or not state then
		return
	end
	local model = entry.model
	local priceText = entry.price and (" für " .. MiniLocale.Credits(entry.price)) or ""
	UI.Confirm(entry.name .. priceText .. " kaufen? Das Auto steht danach unter „Meine Autos“ bereit.", function()
		Remote.Send("mini_car_buy", { model = model })
	end, "Auto kaufen?", "Kaufen", T.green)
end

local function testDrive(entry)
	if entry then
		Remote.Send("mini_car_testdrive", { model = entry.model })
	end
end

local function createCatalogItem(parent, i)
	local card = UI.Card(parent, 10 + i)
	card.BackgroundColor3 = T.panel
	card.Name = "Modell"
	local item = { root = card }
	item.preview = Lib.Preview(card, 130, 1)
	item.name = UI.Label(card, "", { Font = UI.FontBold, TextSize = 18, LayoutOrder = 2 })
	item.sub = UI.Small(card, "", 3)
	item.price = UI.Label(card, "", { Font = UI.FontBold, TextSize = 17, TextColor3 = T.yellow, LayoutOrder = 4 })
	item.stats = Lib.StatBlock(card, 5)
	local buttons = grid(card, 6)
	item.buy = UI.Button(buttons, "Kaufen", T.green, function()
		buyCar(item.entry)
	end, { Name = "Kaufen", LayoutOrder = 1, TextSize = 14 })
	item.test = UI.Button(buttons, "Probefahrt", T.blue, function()
		testDrive(item.entry)
	end, { Name = "Probefahrt", LayoutOrder = 2, TextSize = 14 })
	item.owned = UI.Small(card, "", 7)
	return item
end

local function createCarItem(parent, i)
	local box = UI.Frame(parent, { BackgroundColor3 = T.panel, LayoutOrder = 10 + i, Name = "MeinAuto" })
	UI.Corner(box, 10)
	UI.Padding(box, 10, 10)
	UI.List(box, 8)
	local item = { root = box }
	local top = UI.Frame(box, { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 84), LayoutOrder = 1 })
	item.preview = Lib.Preview(top, 84, 0, { Size = UDim2.new(0, 116, 0, 84) })
	local text = UI.Frame(top, { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -126, 1, 0), Position = UDim2.new(0, 126, 0, 0) })
	UI.List(text, 2)
	item.name = UI.Label(text, "", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1, TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd })
	item.status = UI.Label(text, "", { TextSize = 14, LayoutOrder = 2 })
	item.tune = UI.Label(text, "", { TextSize = 13, TextColor3 = T.muted, LayoutOrder = 3 })
	local buttons = grid(box, 2)
	item.spawn = UI.Button(buttons, "Holen", T.green, function()
		if item.id then
			Remote.Send("mini_car_spawn", { id = item.id, at = Lib.NearestSpawn() }) -- Ort beim Tippen bestimmen
		end
	end, { Name = "Holen", LayoutOrder = 1, TextSize = 14 })
	item.workshop = UI.Button(buttons, "Zur Werkstatt", T.blue, function()
		if item.id then
			Remote.Send("mini_car_spawn", { id = item.id, at = "workshop" })
		end
	end, { Name = "ZurWerkstatt", LayoutOrder = 2, TextSize = 14 })
	item.despawn = UI.Button(buttons, "Abstellen", T.card, function()
		Remote.Send("mini_car_despawn")
	end, { Name = "Abstellen", LayoutOrder = 3, TextSize = 14 })
	item.tuneButton = UI.Button(buttons, "Tunen", T.purple, function()
		if item.id then
			Lib.RequestTune(item.id)
			if UI.Pages and UI.Pages.tuning then
				UI.Show("tuning")
			end
		end
	end, { Name = "Tunen", LayoutOrder = 4, TextSize = 14 })
	item.sell = UI.Button(buttons, "Verkaufen", T.red, function()
		local id, name = item.id, item.carName or "Auto"
		if not id then
			return
		end
		local price = item.sellPrice and (" für " .. MiniLocale.Credits(item.sellPrice)) or ""
		UI.Confirm(name .. price .. " an den Händler verkaufen? Tuning und Optik gehen mit dem Auto weg.", function()
			Remote.Send("mini_car_sell", { id = id })
		end, "Auto verkaufen?", "Verkaufen", T.red)
	end, { Name = "Verkaufen", LayoutOrder = 5, TextSize = 14 })
	return item
end

function DealerUI.Build(page, c)
	ctx = c
	UI, Remote = c.UI, c.Remote
	T = UI.Theme
	refs = {}

	local head = UI.Card(page, 1)
	UI.Title(head, "Autohaus", 1)
	UI.Small(head, "Kaufe dein eigenes Auto, mach eine Probefahrt (" .. Lib.TestDrive() .. " s) oder hol ein Auto aus deiner Garage. Autos erscheinen am nächsten Abholpunkt oder an deiner Werkstatt.", 2)
	refs.info = UI.Label(head, "", { TextSize = 15, LayoutOrder = 3 })
	refs.status = statusLine(head, 4)
	refs.testdrive = UI.Label(head, "", { Name = "Probefahrt", TextSize = 15, TextColor3 = T.yellow, LayoutOrder = 5, Visible = false })

	local mine = UI.Card(page, 2)
	mine.Name = "MeineAutos"
	UI.Title(mine, "Meine Autos", 1)
	refs.mineInfo = UI.Small(mine, "", 2)
	refs.none = UI.Small(mine, "Du hast noch kein eigenes Auto. Unten im Katalog findest du dein erstes.", 3)
	refs.cars = UI.Pool(mine, createCarItem)

	local catalog = UI.Card(page, 3)
	catalog.Name = "Katalog"
	UI.Title(catalog, "Katalog", 1)
	refs.catalogInfo = UI.Small(catalog, "Leistung, Spitze, Grip und Gewicht im Vergleich zum stärksten Modell.", 2)
	refs.catalog = UI.Pool(catalog, createCatalogItem)
end

-- mini_notice: car_spawned, testdrive_end (Server-Toasts zeigt 2.4.0 selbst; hier nur die Statuszeile)
function DealerUI.OnNotice(data)
	if type(data) ~= "table" or not refs.status then
		return
	end
	if data.kind == "car_bought" then
		local name = type(data.name) == "string" and data.name or "Dein neues Auto"
		refs.status.Text = name .. " gehört jetzt dir! Unter „Meine Autos“ kannst du es holen."
		refs.status.TextColor3 = T.green
		refs.status.Visible = true
	elseif data.kind == "car_spawned" then
		local where = Lib.SpawnNames[data.at] or nil
		local name = type(data.name) == "string" and data.name or "Dein Auto"
		if data.testdrive then
			refs.status.Text = "Probefahrt: " .. name .. " steht bereit" .. (where and (" (" .. where .. ")") or "") .. ". Einsteigen und los!"
		else
			refs.status.Text = name .. " steht bereit" .. (where and (" (" .. where .. ")") or "") .. "."
		end
		refs.status.TextColor3 = T.green
		refs.status.Visible = true
		-- Panel schließen, damit das Auto sichtbar ist (nur wenn gerade das Autohaus offen ist)
		if UI.IsOpen and UI.CurrentTab == "dealer" and ctx and ctx.Close then
			ctx.Close()
		end
	elseif data.kind == "testdrive_end" then
		refs.status.Text = "Probefahrt beendet. Gefallen? Das Modell steht im Katalog."
		refs.status.TextColor3 = T.yellow
		refs.status.Visible = true
	end
end

-- Beschriftung "Holen: <Ort>" und "Zur Werkstatt" nach dem nächsten Abholpunkt
local spawnLabelAt = -math.huge
local function refreshSpawnLabels(force)
	if not refs.cars or (not force and os.clock() - spawnLabelAt < 0.5) then
		return
	end
	spawnLabelAt = os.clock()
	local at = Lib.NearestSpawn()
	for _, item in ipairs(refs.cars.items) do
		if item.root.Visible then
			item.spawn.Text = at == "workshop" and "Holen" or ("Holen: " .. (Lib.SpawnNames[at] or "hier"))
			item.workshop.Visible = at ~= "workshop"
		end
	end
end

-- Pro Frame (sichtbarer Tab): Restzeit einer laufenden Probefahrt, Abholpunkt-Beschriftung (alle 0,5 s)
function DealerUI.Step()
	if not refs.testdrive or not state then
		return
	end
	refreshSpawnLabels(false)
	local td = Lib.TestDriveState(state)
	refs.testdrive.Visible = td ~= nil
	if td then
		local left = math.max(0, math.ceil(num(td.endsAt) - workspace:GetServerTimeNow() - 1e-6))
		refs.testdrive.Text = string.format("Probefahrt läuft: %s · noch %d:%02d", type(td.name) == "string" and td.name or "Testwagen", math.floor(left / 60), left % 60)
	end
end

local function tuneSummary(car)
	local parts = {}
	for _, key in ipairs(Lib.PartKeys) do
		table.insert(parts, Lib.PartNames[key] .. " " .. tostring(num(car[key]) or 0))
	end
	return table.concat(parts, " · ")
end

function DealerUI.Render(s)
	if type(s) ~= "table" or not refs.info then
		return
	end
	state = s
	local cars = Lib.Cars(s)
	local slots = Lib.MaxGarage(s)
	local credits = num(s.credits) or 0
	local level = num(s.level) or 1
	refs.info.Text = string.format("Guthaben %s · Level %d · Garage %d/%d", MiniLocale.Credits(credits), level, #cars, slots)

	-- Meine Autos
	refs.none.Visible = #cars == 0
	refs.mineInfo.Text = #cars > 0 and string.format("%d von %d Stellplätzen belegt. Nur ein Auto kann gleichzeitig unterwegs sein.", #cars, slots) or ""
	refs.mineInfo.Visible = #cars > 0
	refs.cars:Ensure(#cars)
	for i, car in ipairs(cars) do
		local item = refs.cars.items[i]
		item.id = car.id
		item.carName = Lib.CarName(s, car)
		local entry = Lib.Entry(s, car.model)
		item.sellPrice = num(car.sellValue) or num(car.sellPrice) or (entry and entry.price and math.floor(entry.price * 0.5)) or nil
		item.name.Text = item.carName
		local out = Lib.IsOut(s, car)
		local active = Lib.ActiveId(s) == car.id
		if car.locked then
			item.status.Text = "In einer Auktion · gesperrt"
			item.status.TextColor3 = T.yellow
		elseif out then
			item.status.Text = "Unterwegs · aktives Auto"
			item.status.TextColor3 = T.green
		elseif active then
			item.status.Text = "Aktives Auto · abgestellt"
			item.status.TextColor3 = T.text
		else
			item.status.Text = "In der Garage"
			item.status.TextColor3 = T.muted
		end
		item.tune.Text = tuneSummary(car)
		item.preview:Set(Lib.CarBody(s, car), Lib.Style(s, car))
		local free = not car.locked
		UI.SetEnabled(item.spawn, free, T.green)
		UI.SetEnabled(item.workshop, free, T.blue)
		item.despawn.Visible = out
		UI.SetEnabled(item.tuneButton, free, T.purple)
		UI.SetEnabled(item.sell, free, T.red)
	end

	refreshSpawnLabels(true)

	-- Katalog
	local list, fromServer = Lib.Catalog(s)
	local shown = {}
	for _, e in ipairs(list) do
		if not e.special then
			table.insert(shown, e)
		end
	end
	local owned = {}
	for _, car in ipairs(cars) do
		owned[car.model] = (owned[car.model] or 0) + 1
	end
	local maxima = Lib.StatMaxima(s)
	refs.catalogInfo.Text = fromServer and "Leistung, Spitze, Grip und Gewicht im Vergleich zum stärksten Modell."
		or "Preise werden geladen …"
	refs.catalog:Ensure(#shown)
	for i, e in ipairs(shown) do
		local item = refs.catalog.items[i]
		item.entry = e
		item.name.Text = e.name
		local sub = { (e.brand and (e.brand .. " · ") or "") .. "ab Level " .. tostring(e.level) }
		if e.stats.drive and Lib.DriveNames[e.stats.drive] then
			table.insert(sub, Lib.DriveNames[e.stats.drive])
		end
		if e.stats.zeroTo100 then
			table.insert(sub, "0–100 in " .. MiniLocale.Decimal(e.stats.zeroTo100, 1) .. " s")
		end
		item.sub.Text = table.concat(sub, " · ")
		item.price.Text = e.price and MiniLocale.Credits(e.price) or "Preis folgt"
		item.stats.Set(e.stats, maxima)
		local pal = Lib.Palettes(s)
		local paint = e.paint and pal.paint[e.paint] and pal.paint[e.paint].color or e.color or Color3.fromRGB(47, 169, 163)
		item.preview:Set(e.body, { paint = paint })
		local n = owned[e.model] or 0
		item.owned.Text = n > 0 and ("Du besitzt " .. (n == 1 and "dieses Modell" or (n .. " Stück")) .. ".") or ""
		item.owned.Visible = n > 0
		local levelOk = level >= e.level
		local full = #cars >= slots
		if not levelOk then
			item.buy.Text = "Ab Level " .. tostring(e.level)
			UI.SetEnabled(item.buy, false)
		elseif full then
			item.buy.Text = "Garage voll"
			UI.SetEnabled(item.buy, false)
		elseif not fromServer or not e.price then
			item.buy.Text = "Kaufen"
			UI.SetEnabled(item.buy, false)
		else
			item.buy.Text = "Kaufen"
			UI.SetEnabled(item.buy, credits >= e.price, T.green)
		end
		item.test.Text = "Probefahrt"
		UI.SetEnabled(item.test, fromServer, T.blue)
	end
	DealerUI.Step()
end

return DealerUI
