-- CarRules: eigene Autos im Profil (d.games.cars) als reine, serverautoritative Funktionen.
-- Daten (PHASE2_CONTRACT §2):
--   d.games.cars      = { {id, model, paint, rims, glow, spoiler, engine, gearbox, tires, suspension, nitro,
--                          bought, locked}, ... }   (höchstens CarCatalog.MaxCars)
--   d.games.carSerial = letzte vergebene Auto-Id
--   d.games.activeCar = Id des aktiven Autos oder 0
-- Geld ändert sich nur über MiniRules.AddMoney (gedeckelt auf C.NumberCap), XP über MiniRules.GainXP.
-- MiniRules wird erst beim ersten Aufruf geladen (MiniRules.LoadGames lädt dieses Modul; keine Ringabhängigkeit).
local CarCatalog = require(script.Parent:WaitForChild("CarCatalog"))
local PrestigeRules = require(script.Parent:WaitForChild("PrestigeRules")) -- Rabatt im Autohaus je Rang (PHASE4_CONTRACT §4)
local CrossBonus = require(script.Parent:WaitForChild("CrossBonus")) -- Tycoon-Autohaus-Rabatt (§8); braucht kein CarRules

local CarRules = {}

local MAX_SAFE = 2 ^ 53

local MiniRules
local function mini()
	if not MiniRules then
		MiniRules = require(script.Parent:WaitForChild("MiniRules"))
	end
	return MiniRules
end

local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function int(v, default, min, max)
	if not finite(v) then
		return default
	end
	v = math.floor(v)
	if v < min or v > max then
		return default
	end
	return v
end

local function money(d)
	return finite(d.money) and d.money or 0
end

local function level(d)
	return finite(d.level) and d.level or 1
end

---------------------------------------------------------------- Daten
function CarRules.Default()
	return { cars = {}, carSerial = 0, activeCar = 0 }
end

-- Neues Auto eines Modells im Auslieferungszustand (ohne Id)
function CarRules.NewCar(modelId, now)
	local m = CarCatalog.Model(modelId)
	if not m then
		return nil
	end
	return {
		id = 0, model = m.id, paint = m.paint, rims = m.rims, glow = m.glow, spoiler = m.spoiler,
		engine = 0, gearbox = 0, tires = 0, suspension = 0, nitro = 0,
		bought = finite(now) and math.max(0, math.floor(now)) or 0, locked = false,
	}
end

-- Normalisiert ein Auto (Whitelist). Unbekanntes Modell -> nil.
function CarRules.NormalizeCar(raw)
	if type(raw) ~= "table" then
		return nil
	end
	local m = CarCatalog.Model(raw.model)
	if not m then
		return nil
	end
	local T = CarCatalog.Tune
	local car = {
		id = int(raw.id, 0, 1, MAX_SAFE),
		model = m.id,
		paint = int(raw.paint, m.paint, 1, #CarCatalog.Paints),
		rims = int(raw.rims, m.rims, 1, #CarCatalog.Rims),
		glow = int(raw.glow, 0, 0, #CarCatalog.Glows),
		spoiler = raw.spoiler == true,
		engine = int(raw.engine, 0, 0, T.engine.max),
		gearbox = int(raw.gearbox, 0, 0, T.gearbox.max),
		tires = int(raw.tires, 0, 0, T.tires.max),
		suspension = int(raw.suspension, 0, 0, T.suspension.max),
		nitro = int(raw.nitro, 0, 0, T.nitro.max),
		bought = int(raw.bought, 0, 0, MAX_SAFE),
		locked = raw.locked == true,
	}
	return car
end

-- Übernimmt die Autodaten aus dem gespeicherten games-Table (rawGames = gespeichertes d.games oder nil).
-- Rückgabe { cars, carSerial, activeCar }. Idempotent. Unbekannte Modelle fallen weg, doppelte/fehlende Ids
-- bekommen neue, höchstens MaxCars Autos. locked wird aufgehoben: Spieler-Auktionen sind an die Sitzung
-- gebunden (verlässt der Verkäufer den Server, endet die Auktion), ein gespeichertes locked ist also verwaist.
function CarRules.Load(rawGames, d, now)
	local out = CarRules.Default()
	if type(rawGames) ~= "table" then
		return out
	end
	local serial = int(rawGames.carSerial, 0, 0, MAX_SAFE)
	local list = type(rawGames.cars) == "table" and rawGames.cars or {}
	local seen = {}
	local pending = {}
	for _, raw in ipairs(list) do
		if #out.cars + #pending >= CarCatalog.MaxCars then
			break
		end
		local car = CarRules.NormalizeCar(raw)
		if car then
			car.locked = false
			if car.id > 0 and not seen[car.id] then
				seen[car.id] = true
				serial = math.max(serial, car.id)
				table.insert(out.cars, car)
			else
				table.insert(pending, car)
			end
		end
	end
	for _, car in ipairs(pending) do
		serial += 1
		car.id = serial
		table.insert(out.cars, car)
	end
	table.sort(out.cars, function(a, b)
		return a.id < b.id
	end)
	out.carSerial = serial
	local active = int(rawGames.activeCar, 0, 0, MAX_SAFE)
	if active > 0 and not seen[active] then
		active = 0
	end
	if active == 0 and out.cars[1] then
		active = out.cars[1].id
	end
	out.activeCar = active
	return out
end

-- Setzt die Standardwerte bzw. die geladenen Werte in ein games-Table (für MiniRules.DefaultGames/LoadGames).
function CarRules.ApplyDefault(g)
	for k, v in pairs(CarRules.Default()) do
		g[k] = v
	end
	return g
end
function CarRules.ApplyLoad(g, rawGames, d, now)
	for k, v in pairs(CarRules.Load(rawGames, d, now)) do
		g[k] = v
	end
	return g
end

local function games(d)
	local g = d.games
	if type(g.cars) ~= "table" then
		CarRules.ApplyDefault(g)
	end
	return g
end

function CarRules.Find(d, id)
	if type(id) ~= "number" then
		return nil
	end
	for i, car in ipairs(games(d).cars) do
		if car.id == id then
			return car, i
		end
	end
	return nil
end

function CarRules.Active(d)
	local g = games(d)
	return CarRules.Find(d, g.activeCar)
end

---------------------------------------------------------------- Werte
-- Effektive Fahrwerte aus Grundwerten + Tuning.
-- topSpeed km/h, topSpeedStuds Studs/s, accel Studs/s², grip Reibwert, weight kg, mass Roblox-Masse,
-- steerAngle Grad, springRate/damping (Faktor/Dämpfungsmaß), drive, gears, nitro {level, boost, seconds, cooldown}
function CarRules.Stats(car)
	local m = CarCatalog.Model(car and car.model)
	if not m then
		return nil
	end
	local e = CarCatalog.Effects
	local engine, gearbox = car.engine or 0, car.gearbox or 0
	local tires, susp, nitro = car.tires or 0, car.suspension or 0, car.nitro or 0
	local power = m.power * (1 + e.enginePower * engine)
	local topSpeed = m.top * (1 + e.engineTop * engine + e.gearboxTop * gearbox)
	local accel = CarCatalog.AccelFactor * math.sqrt(power / m.weight) * (1 + e.gearboxAccel * gearbox)
	local topStuds = topSpeed / CarCatalog.KmhPerStud
	local hundred = 100 / CarCatalog.KmhPerStud
	local grip = math.min(e.gripMax, m.grip + e.tiresGrip * tires)
	local n = CarCatalog.Nitro[nitro]
	local stats = {
		power = math.floor(power + 0.5),
		topSpeed = math.floor(topSpeed + 0.5),
		topSpeedStuds = topStuds,
		reverseSpeedStuds = topStuds * CarCatalog.ReverseShare,
		accel = accel,
		zeroTo100 = topStuds >= hundred and math.floor(hundred / accel * 10 + 0.5) / 10 or nil,
		grip = grip,
		weight = m.weight,
		mass = m.weight / CarCatalog.KgPerMass,
		steerAngle = m.steer + e.suspSteer * susp,
		springRate = 1 + e.suspStiffness * susp,
		damping = CarCatalog.Physics.dampingRatio + e.suspDamping * susp,
		drive = m.drive,
		gears = CarCatalog.BaseGears + (gearbox >= e.gearsFromGearbox and 1 or 0),
		nitro = {
			level = n and nitro or 0,
			boost = n and n.boost or 1,
			seconds = n and n.seconds or 0,
			cooldown = n and n.cooldown or 0,
		},
	}
	-- Leistungsindex fürs UI (0..~1000)
	stats.rating = math.floor(stats.topSpeed * 2.2 + accel * 9 + grip * 120 + stats.nitro.boost * 40 - 100 + 0.5)
	return stats
end

-- Wert eines Autos (Händlerpreis bzw. Richtwert des Sondermodells)
function CarRules.Value(car)
	local m = CarCatalog.Model(car and car.model)
	return m and m.value or 0
end

function CarRules.TuneCost(car, part, lvl)
	local def = CarCatalog.Tune[part]
	if not def or lvl < 1 or lvl > def.max then
		return nil
	end
	local cost = CarRules.Value(car) * def.share * CarCatalog.TuneGrowth ^ (lvl - 1)
	return math.max(CarCatalog.TuneMinCost, math.floor(cost + 0.5))
end

-- Summe der bezahlten Tuning-Stufen (für den Rückkauf)
function CarRules.TuningValue(car)
	local sum = 0
	for _, part in ipairs(CarCatalog.TuneParts) do
		for lvl = 1, car[part] or 0 do
			sum += CarRules.TuneCost(car, part, lvl) or 0
		end
	end
	return sum
end

function CarRules.SellValue(car)
	return math.floor((CarRules.Value(car) + CarRules.TuningValue(car)) * CarCatalog.SellShare + 0.5)
end

function CarRules.StyleCost(car, key)
	local def = CarCatalog.Style[key]
	if not def then
		return nil
	end
	return math.max(def.min, math.floor(CarRules.Value(car) * def.share + 0.5))
end

-- Rabatt im Autohaus: Prestige (1 % je Rang, Deckel 10 %) + Tycoon-Durchläufe „Autohaus“ (1,5 % je Durchlauf,
-- Deckel 7,5 %, CrossBonus.TycoonDealerDiscount): tatsächlicher Kaufpreis eines Modells für dieses Profil
function CarRules.DealerPrice(d, m)
	local price = type(m) == "table" and m.price or 0
	if not finite(price) or price <= 0 then
		return 0
	end
	local ok, discount = pcall(PrestigeRules.Discount, d)
	if not ok or not finite(discount) or discount < 0 then
		discount = 0
	end
	local okT, tycoon = pcall(CrossBonus.TycoonDealerDiscount, d)
	if okT and finite(tycoon) and tycoon > 0 then
		discount += tycoon
	end
	-- Open-World-Autohaus (PHASE4_CONTRACT §7): Rabatt-Anteil 0..0,12 je fertiger Stufe (CrossBonus.OWPerk autohaus)
	local okO, ow = pcall(CrossBonus.OWDealerDiscount, d)
	if okO and finite(ow) and ow > 0 then
		discount += ow
	end
	if discount <= 0 then
		return price
	end
	return math.max(1, math.floor(price * (1 - math.min(discount, 0.9)) + 0.5))
end

---------------------------------------------------------------- Aktionen (Server)
-- Kauf beim Händler. Rückgabe: true, car | false, Meldung (nil = still verworfen, z. B. Doppelklick)
function CarRules.Buy(d, modelId, now)
	local g = games(d)
	local m = CarCatalog.Model(modelId)
	if not m or not m.dealer then
		return false, "Dieses Modell gibt es beim Händler nicht."
	end
	local price = CarRules.DealerPrice(d, m) -- Prestige-Rabatt (Snapshot/Autohaus zeigen denselben Preis)
	if level(d) < m.level then
		return false, "Dafür brauchst du Level " .. m.level .. "."
	end
	-- Doppelklick: dasselbe Modell gerade eben gekauft
	for _, car in ipairs(g.cars) do
		if car.model == m.id and finite(now) and now - car.bought >= 0 and now - car.bought < CarCatalog.BuyRepeatSeconds then
			return false, nil
		end
	end
	if #g.cars >= CarCatalog.MaxCars then
		return false, "Deine Garage ist voll (" .. CarCatalog.MaxCars .. " Autos)."
	end
	if money(d) < price then
		return false, "Nicht genug Credits."
	end
	mini().AddMoney(d, -price)
	local car = CarRules.AddCar(d, CarRules.NewCar(m.id, now))
	mini().GainXP(d, CarCatalog.BuyXp)
	return true, car
end

-- Fügt ein Auto (Datensatz, z. B. aus einer Auktion) mit neuer Id hinzu. Rückgabe: car oder nil (Garage voll).
function CarRules.AddCar(d, record)
	local g = games(d)
	local car = CarRules.NormalizeCar(record)
	if not car or #g.cars >= CarCatalog.MaxCars then
		return nil
	end
	g.carSerial = math.min(MAX_SAFE, (g.carSerial or 0) + 1)
	car.id = g.carSerial
	car.locked = false
	table.insert(g.cars, car)
	if not CarRules.Find(d, g.activeCar) then
		g.activeCar = car.id
	end
	return car
end

-- Sondermodell/beliebiges Modell gutschreiben (NPC-Auktion). Rückgabe: car oder nil, Meldung
function CarRules.GrantModel(d, modelId, now)
	local fresh = CarRules.NewCar(modelId, now)
	if not fresh then
		return nil, "Unbekanntes Modell."
	end
	local car = CarRules.AddCar(d, fresh)
	if not car then
		return nil, "Deine Garage ist voll (" .. CarCatalog.MaxCars .. " Autos)."
	end
	return car
end

-- Entfernt ein Auto (Verkauf, Auktions-Übergabe). Rückgabe: entfernter Datensatz oder nil
function CarRules.RemoveCar(d, id)
	local g = games(d)
	local car, index = CarRules.Find(d, id)
	if not car then
		return nil
	end
	table.remove(g.cars, index)
	if g.activeCar == id then
		g.activeCar = g.cars[1] and g.cars[1].id or 0
	end
	return car
end

-- Auktions-Sperre setzen/aufheben (AuctionService)
function CarRules.SetLocked(d, id, locked)
	local car = CarRules.Find(d, id)
	if not car then
		return false
	end
	car.locked = locked == true
	return true
end

-- Rückkauf durch den Händler (50 % von Wert + Tuning). Rückgabe: true, Erlös, car | false, Meldung
function CarRules.Sell(d, id)
	local car = CarRules.Find(d, id)
	if not car then
		return false, nil -- schon verkauft (Doppelklick) oder fremde Id
	end
	if car.locked then
		return false, "Dieses Auto ist gerade in einer Auktion."
	end
	local value = CarRules.SellValue(car)
	CarRules.RemoveCar(d, id)
	mini().AddMoney(d, value)
	return true, value, car
end

-- Tuning: level = die Stufe, die der Client gesehen hat (aktuelle Stufe). Veraltet -> still verworfen.
-- Rückgabe: true, neueStufe, Kosten | false, Meldung
function CarRules.Tune(d, id, part, seenLevel)
	local car = CarRules.Find(d, id)
	if not car then
		return false, "Auto nicht gefunden."
	end
	local def = type(part) == "string" and CarCatalog.Tune[part]
	if not def then
		return false, "Unbekanntes Bauteil."
	end
	if car.locked then
		return false, "Dieses Auto ist gerade in einer Auktion."
	end
	local current = car[part] or 0
	if type(seenLevel) ~= "number" or seenLevel ~= current then
		return false, nil
	end
	if current >= def.max then
		return false, def.name .. ": maximale Stufe erreicht."
	end
	local nextLevel = current + 1
	local need = def.levels[nextLevel] or 1
	if level(d) < need then
		return false, def.name .. " Stufe " .. nextLevel .. " ab Level " .. need .. "."
	end
	local cost = CarRules.TuneCost(car, part, nextLevel)
	if money(d) < cost then
		return false, "Nicht genug Credits."
	end
	mini().AddMoney(d, -cost)
	car[part] = nextLevel
	mini().GainXP(d, CarCatalog.TuneXp)
	return true, nextLevel, cost
end

-- Optik: nur geänderte Werte kosten. Gleiche Werte (Doppelklick) -> true, 0 ohne Änderung.
-- Rückgabe: true, Kosten, geänderte Schlüssel | false, Meldung
function CarRules.Style(d, id, paint, rims, glow, spoiler)
	local car = CarRules.Find(d, id)
	if not car then
		return false, "Auto nicht gefunden."
	end
	if car.locked then
		return false, "Dieses Auto ist gerade in einer Auktion."
	end
	if type(paint) ~= "number" or paint % 1 ~= 0 or not CarCatalog.Paints[paint] then
		return false, "Ungültige Lackfarbe."
	end
	if type(rims) ~= "number" or rims % 1 ~= 0 or not CarCatalog.Rims[rims] then
		return false, "Ungültige Felgenfarbe."
	end
	if type(glow) ~= "number" or glow % 1 ~= 0 or glow < 0 or glow > #CarCatalog.Glows then
		return false, "Ungültiges Unterbodenlicht."
	end
	if type(spoiler) ~= "boolean" then
		return false, "Ungültige Auswahl."
	end
	local changes = {}
	local cost = 0
	local function change(key, value)
		if car[key] ~= value then
			local def = CarCatalog.Style[key]
			if level(d) < def.level then
				return def.name .. " ab Level " .. def.level .. "."
			end
			table.insert(changes, key)
			cost += CarRules.StyleCost(car, key)
		end
		return nil
	end
	for _, pair in ipairs({ { "paint", paint }, { "rims", rims }, { "glow", glow }, { "spoiler", spoiler } }) do
		local err = change(pair[1], pair[2])
		if err then
			return false, err
		end
	end
	if #changes == 0 then
		return true, 0, changes
	end
	if money(d) < cost then
		return false, "Nicht genug Credits."
	end
	mini().AddMoney(d, -cost)
	car.paint, car.rims, car.glow, car.spoiler = paint, rims, glow, spoiler
	mini().GainXP(d, CarCatalog.StyleXp)
	return true, cost, changes
end
CarRules.Paint = CarRules.Style -- Name aus dem Vertrag

function CarRules.SetActive(d, id)
	local car = CarRules.Find(d, id)
	if not car then
		return false, "Auto nicht gefunden."
	end
	if car.locked then
		return false, "Dieses Auto ist gerade in einer Auktion."
	end
	games(d).activeCar = id
	return true, car
end

-- Darf das Auto auf die Straße? Rückgabe: true, car | false, Meldung
function CarRules.CanSpawn(d, id)
	local car = CarRules.Find(d, id)
	if not car then
		return false, "Auto nicht gefunden."
	end
	if car.locked then
		return false, "Dieses Auto ist gerade in einer Auktion."
	end
	if not CarCatalog.Model(car.model) then
		return false, "Unbekanntes Modell."
	end
	return true, car
end

---------------------------------------------------------------- Ansicht (Snapshot, PHASE2_CONTRACT §5)
local function styleView(car)
	local out = {}
	for key in pairs(CarCatalog.Style) do
		out[key] = CarRules.StyleCost(car, key)
	end
	return out
end

function CarRules.View(car, d)
	local m = CarCatalog.Model(car.model)
	local tune = {}
	for _, part in ipairs(CarCatalog.TuneParts) do
		local def = CarCatalog.Tune[part]
		local lvl = car[part] or 0
		tune[part] = {
			level = lvl,
			max = def.max,
			cost = lvl < def.max and CarRules.TuneCost(car, part, lvl + 1) or 0,
			needLevel = lvl < def.max and (def.levels[lvl + 1] or 1) or 0,
		}
	end
	local s = CarRules.Stats(car)
	return {
		id = car.id, model = car.model, name = m.name, brand = m.brand, body = m.body, special = m.special, dlc = m.dlc == true,
		paint = car.paint, rims = car.rims, glow = car.glow, spoiler = car.spoiler,
		engine = car.engine, gearbox = car.gearbox, tires = car.tires, suspension = car.suspension, nitro = car.nitro,
		locked = car.locked, bought = car.bought,
		value = CarRules.Value(car), sellValue = CarRules.SellValue(car),
		tune = tune, styleCost = styleView(car),
		stats = {
			power = s.power, topSpeed = s.topSpeed, zeroTo100 = s.zeroTo100, grip = math.floor(s.grip * 100 + 0.5) / 100,
			weight = s.weight, drive = s.drive, gears = s.gears, rating = s.rating, nitroLevel = s.nitro.level,
			nitroSeconds = s.nitro.seconds, nitroCooldown = s.nitro.cooldown,
		},
	}
end

-- Katalog fürs Autohaus (klein; dealer-Modelle mit Freischaltung nach Level)
function CarRules.CatalogView(d)
	local out = {}
	for _, m in ipairs(CarCatalog.DealerModels) do
		local s = CarRules.Stats(CarRules.NewCar(m.id, 0))
		local price = CarRules.DealerPrice(d, m) -- mit Prestige-Rabatt; basePrice = Listenpreis
		table.insert(out, {
			id = m.id, name = m.name, brand = m.brand, body = m.body, level = m.level, price = price, basePrice = m.price,
			unlocked = level(d) >= m.level, affordable = money(d) >= price,
			power = s.power, topSpeed = s.topSpeed, zeroTo100 = s.zeroTo100, drive = s.drive, rating = s.rating,
		})
	end
	return out
end

-- Felder für MiniSnapshot.Build (rein): cars, activeCar, catalog, garageMax
function CarRules.SnapshotFields(d)
	local g = games(d)
	local cars = {}
	for _, car in ipairs(g.cars) do
		table.insert(cars, CarRules.View(car, d))
	end
	return {
		cars = cars,
		activeCar = g.activeCar or 0,
		catalog = CarRules.CatalogView(d),
		garageMax = CarCatalog.MaxCars,
	}
end

return CarRules
