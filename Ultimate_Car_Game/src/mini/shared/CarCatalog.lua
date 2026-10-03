-- CarCatalog: alle Zahlen der eigenen Autos an einer Stelle (Balance-Stellschrauben).
-- Modelle = die neun 2.4.0-Karosserien aus C.Cars (Id, Name, Marke, Karosserie, Level werden übernommen),
-- ergänzt um Händlerpreis und Fahrwerte; dazu Sondermodelle für NPC-Auktionen, Tuning-Stufen und -Preise,
-- Farbpaletten, Waschstraße, Probefahrt, Zeitfahren und die Physik-Grundwerte der VehicleFactory.
-- Rein (keine Instanzen), auf Server und Client nutzbar (ReplicatedStorage.GarageShared.Mini.CarCatalog).
-- Ausbaustufe 4 (docs/PHASE4_CONTRACT.md §3): das Händler-/Auktions-Level jedes Modells kommt aus der
-- Freischalt-Tabelle GameConfig.Unlocks ("car:<id>", Unlocks.CarLevel), nicht mehr aus C.Cars[].level – das
-- 2.4.0-Feld gilt weiter für die Kundenautos der Werkstatt und bleibt unverändert. Die Level in Specials und
-- C.Cars sind nur noch Rückfall für Modelle ohne Eintrag in GameConfig.Unlocks.
local C = require(script.Parent.Parent:WaitForChild("Config"))
local Unlocks = require(script.Parent:WaitForChild("Unlocks"))

local CarCatalog = {}

---------------------------------------------------------------- Grundwerte
CarCatalog.MaxCars = 20 -- Garage: höchstens 20 eigene Autos (PHASE2_CONTRACT §2)
CarCatalog.KmhPerStud = 1.008 -- 1 Stud = 0,28 m: Studs/s × 1,008 = km/h (Tacho)
CarCatalog.KgPerMass = 21.952 -- Roblox-Masseeinheit (0,28³ m³ Wasser)
CarCatalog.AccelFactor = 40 -- Beschleunigung in Studs/s² = AccelFactor × sqrt(PS / kg)
CarCatalog.ReverseShare = 0.3 -- Rückwärtsgang: Anteil der Höchstgeschwindigkeit
CarCatalog.BaseGears = 5 -- Gang-Anzeige im Tacho (rein optisch)

-- Händlerpreise und Fahrwerte je 2.4.0-Modell (Schlüssel = C.Cars.id).
-- price: Cr beim Autohaus; power: PS; top: km/h (≈ Studs/s); weight: kg; grip: Reibwert der Reifen;
-- steer: maximaler Lenkeinschlag in Grad; drive: FWD | RWD | AWD; paint: Standard-Lackfarbe (Index in Paints)
-- Balance (§7, tools/economy_sim.py, docs/BALANCE.md): erstes Auto (Kompakt) nach etwa 25 Minuten Werkstatt,
-- Sportwagen nach etwa 4 Stunden, Supersportwagen/Elektro nach 12–18 Stunden (Level wie C.Cars).
-- Richtwert der Preise ist der Kontostand eines Spielers, der nur Werkstatt-Aufträge macht und dabei Bühnen und
-- Geräte ausbaut; die 2.4.0-Aufträge bringen auf Level 30–40 etwa 3.000–6.000 Cr pro Minute.
CarCatalog.Dealer = {
	komet = { price = 4500, power = 90, top = 78, weight = 1050, grip = 0.95, steer = 34, drive = "FWD", paint = 1 },
	komet_s2 = { price = 18000, power = 180, top = 96, weight = 1200, grip = 1.0, steer = 33, drive = "FWD", paint = 2 },
	nord = { price = 28000, power = 150, top = 92, weight = 1400, grip = 0.95, steer = 32, drive = "RWD", paint = 3 },
	komet_urban = { price = 40000, power = 170, top = 90, weight = 1550, grip = 0.92, steer = 31, drive = "AWD", paint = 4 },
	atlas = { price = 72000, power = 220, top = 100, weight = 1600, grip = 0.97, steer = 31, drive = "AWD", paint = 5 },
	vektor = { price = 390000, power = 380, top = 118, weight = 1350, grip = 1.08, steer = 31, drive = "RWD", paint = 6 },
	vektor_gtx = { price = 850000, power = 520, top = 126, weight = 1500, grip = 1.1, steer = 30, drive = "RWD", paint = 7 },
	aureon = { price = 2600000, power = 780, top = 140, weight = 1450, grip = 1.15, steer = 29, drive = "AWD", paint = 8 },
	elys = { price = 4600000, power = 700, top = 134, weight = 1900, grip = 1.12, steer = 30, drive = "AWD", paint = 9 },
}
-- Rückfall für ein C.Cars-Modell ohne Eintrag oben: Preis = C.Cars.value, sonst Kompakt-Werte
CarCatalog.DealerFallback = { power = 120, top = 85, weight = 1300, grip = 0.95, steer = 32, drive = "RWD", paint = 1 }

-- Sondermodelle: nicht beim Händler, nur über NPC-Auktionen (AuctionService: CarRules.GrantModel).
-- value: Richtwert (Startgebot/Verkaufswert); rims/glow/spoiler: Auslieferungszustand.
-- level: nur Rückfall – maßgeblich ist GameConfig.Unlocks "car:<id>" (Rallye 10, Classic 18, Goldstück 50, Nero 78, Prototyp 95).
CarCatalog.Specials = {
	{ id = "komet_rally", name = "Komet C1 Rallye", brand = "Komet", body = "compact", level = 5, value = 24000,
		power = 160, top = 92, weight = 980, grip = 1.05, steer = 35, drive = "AWD", paint = 2, rims = 2, glow = 0, spoiler = true },
	{ id = "nord_classic", name = "Nord R4 Classic", brand = "Nord", body = "sedan", level = 8, value = 48000,
		power = 200, top = 98, weight = 1350, grip = 0.98, steer = 32, drive = "RWD", paint = 11, rims = 3, glow = 0, spoiler = false },
	{ id = "vektor_gold", name = "Vektor RS Goldstück", brand = "Vektor", body = "sport", level = 20, value = 520000,
		power = 420, top = 124, weight = 1320, grip = 1.1, steer = 31, drive = "RWD", paint = 8, rims = 2, glow = 6, spoiler = true },
	{ id = "aureon_nero", name = "Vektor Aureon Nero", brand = "Vektor", body = "super", level = 32, value = 3400000,
		power = 850, top = 146, weight = 1420, grip = 1.18, steer = 29, drive = "AWD", paint = 11, rims = 6, glow = 4, spoiler = true },
	{ id = "elys_proto", name = "Nord Elys Prototyp", brand = "Nord", body = "electric", level = 40, value = 5800000,
		power = 800, top = 140, weight = 1850, grip = 1.15, steer = 30, drive = "AWD", paint = 10, rims = 8, glow = 1, spoiler = true },
}

-- Karosserien mit eigenem Spoiler in der Vorlage (Standard: Spoiler an)
CarCatalog.BodySpoiler = { hot_hatch = true, sport = true, super = true }

---------------------------------------------------------------- Startauto „Flitzer“ (3.x)
-- Winziges Startauto (Karosserie "flitzer", VehicleFactory baut es aus Parts – keine Vorlage, keine Assets).
-- Jedes Profil besitzt es immer (CarRules.OwnsStarter): es steht NICHT in d.games.cars, zählt nicht zur Garage,
-- ist kostenlos, nicht verkäuflich, nicht versteigerbar, nicht tunebar und kann nicht verloren gehen.
-- Bewusst NICHT in Models/ModelById/DealerModels (Händler, Auktionen, Shop und Teststrecke kennen es nicht);
-- CarCatalog.Model("flitzer") liefert es trotzdem (Fahrwerte, Name, Optik für CarRules.Stats/View).
-- Fahrwerte: schnelle Beschleunigung (≈ 14,8 Studs/s², wie die Mittelklasse), wendig (Lenkung 36°), Spitze 88 km/h
-- (knapp unter der Mittelklasse 90–100) – kein Nitro, kein Tuning, beim Zeitfahren außer Konkurrenz: kein Vorteil
-- gegenüber gekauften Autos (Leistungsindex ≈ 380, zwischen Komet C1 ≈ 330 und Komet S2 ≈ 410).
CarCatalog.StarterId = "flitzer"
CarCatalog.StarterCarId = -1 -- feste Auto-Id des Flitzers (gekaufte Autos haben Ids ≥ 1, 0 = kein Auto)
CarCatalog.Starter = {
	id = "flitzer", name = "Flitzer", brand = "Mini", body = "flitzer", level = 1,
	price = 0, value = 0, -- kostenlos, Verkaufswert 0
	power = 75, top = 88, weight = 520, grip = 0.95, steer = 36, drive = "RWD",
	paint = 2, rims = 4, glow = 0, spoiler = false,
	dealer = false, special = false, dlc = false,
	starter = true, sellable = false, tunable = false, track = false,
}
-- Eigene Physik-Maße der kleinen Karosserie (überschreiben CarCatalog.Physics für body = "flitzer"; unten definiert)
CarCatalog.BodyPhysics = {
	flitzer = {
		hullBottom = 1.0, -- Kollisionsrumpf tiefer (kleine Räder, Radius 0,95)
		hullTop = 2.4,
		hullHalfWidth = 1.9,
		seatTop = 2.1, -- Sitzfläche (die Figur schaut oben heraus: Go-Kart-Gefühl)
		springLength = 1.6,
		travel = 0.45,
		rideDeflection = 0.3,
	},
}

---------------------------------------------------------------- DLC-Autos (Shop, PHASE4_CONTRACT §9, Meilenstein 8)
-- Eigene Modell-Ids "dlc_<name>": Karosserie aus einer bestehenden Vorlage, Fahrwerte EXAKT vom Basismodell
-- (base = Händlermodell derselben Klasse – kein Pay-to-win, Test in tests/test_shop_rules.lua), dazu feste Optik
-- (paint/rims/glow/spoiler wie der Auslieferungszustand) und eine exklusive Folierung (wrap = Kosmetik-Id aus
-- GameConfig.Shop, Beigabe des Produkts). Nicht beim Händler (CarRules.Buy lehnt ab): Kauf über ShopRules.Buy
-- (Credits: Basispreis × GameConfig.Shop.DlcPriceFactor, ab dem Level des Basismodells) oder als Developer
-- Product (GameConfig.Shop.Products kind="car" -> ShopRules.Grant). value = Händlerpreis des Basismodells
-- (Rückkauf/Auktions-Richtwert wie ein normales Auto derselben Klasse).
CarCatalog.Dlc = {
	{ id = "dlc_komet_sunset", name = "Komet S2 Sunset", brand = "Komet", body = "hot_hatch", base = "komet_s2",
		paint = 2, rims = 3, glow = 6, spoiler = true, wrap = "wrap_sunset" },
	{ id = "dlc_nord_nacht", name = "Nord R4 Nachtfalke", brand = "Nord", body = "sedan", base = "nord",
		paint = 11, rims = 7, glow = 3, spoiler = false, wrap = "wrap_nacht" },
	{ id = "dlc_vektor_blitz", name = "Vektor RS Blitz", brand = "Vektor", body = "sport", base = "vektor",
		paint = 9, rims = 4, glow = 2, spoiler = true, wrap = "wrap_blitz" },
}
CarCatalog.DlcPriceFactor = 1.5 -- Rückfall; maßgeblich ist GameConfig.Shop.DlcPriceFactor (ShopRules.DlcPrice)
CarCatalog.DlcById = {} -- id -> Dlc-Eintrag (nach dem Aufbau der Modell-Liste gefüllt)

---------------------------------------------------------------- Farbpaletten (Lack 12, Felgen 8, Unterboden 6)
CarCatalog.Paints = {
	{ name = "Petrol", color = { 48, 170, 157 } },
	{ name = "Bernstein", color = { 235, 167, 48 } },
	{ name = "Kobaltblau", color = { 79, 132, 215 } },
	{ name = "Salbeigrün", color = { 106, 150, 93 } },
	{ name = "Silber", color = { 176, 190, 198 } },
	{ name = "Rennrot", color = { 192, 62, 77 } },
	{ name = "Violett", color = { 117, 82, 177 } },
	{ name = "Gold", color = { 224, 172, 60 } },
	{ name = "Eisblau", color = { 107, 199, 210 } },
	{ name = "Schneeweiß", color = { 236, 238, 240 } },
	{ name = "Tiefschwarz", color = { 28, 30, 34 } },
	{ name = "Graphit", color = { 74, 80, 88 } },
}
CarCatalog.Rims = {
	{ name = "Silber", color = { 97, 112, 124 } },
	{ name = "Schwarz matt", color = { 30, 32, 36 } },
	{ name = "Gold", color = { 212, 168, 72 } },
	{ name = "Weiß", color = { 230, 232, 235 } },
	{ name = "Bronze", color = { 150, 110, 70 } },
	{ name = "Rot", color = { 190, 50, 50 } },
	{ name = "Chrom", color = { 205, 210, 216 }, reflectance = 0.3 },
	{ name = "Petrol", color = { 47, 169, 163 } },
}
-- Index 0 = aus
CarCatalog.Glows = {
	{ name = "Petrol", color = { 47, 169, 163 } },
	{ name = "Blau", color = { 60, 120, 255 } },
	{ name = "Violett", color = { 160, 80, 255 } },
	{ name = "Rot", color = { 255, 60, 60 } },
	{ name = "Grün", color = { 60, 255, 120 } },
	{ name = "Bernstein", color = { 247, 176, 63 } },
}

---------------------------------------------------------------- Tuning (Leistung)
CarCatalog.TuneParts = { "engine", "gearbox", "tires", "suspension", "nitro" }
-- share: Kosten der Stufe 1 als Anteil am Autowert; levels[n] = Spielerlevel für Stufe n
CarCatalog.Tune = {
	engine = { name = "Motor", max = 5, share = 0.08, levels = { 1, 3, 6, 10, 15 } },
	gearbox = { name = "Getriebe", max = 5, share = 0.06, levels = { 2, 4, 7, 11, 16 } },
	tires = { name = "Reifen", max = 5, share = 0.04, levels = { 1, 2, 5, 8, 12 } },
	suspension = { name = "Fahrwerk", max = 5, share = 0.05, levels = { 1, 3, 6, 9, 13 } },
	nitro = { name = "Nitro", max = 3, share = 0.10, levels = { 5, 10, 15 } },
}
CarCatalog.TuneGrowth = 1.45 -- Kosten je weiterer Stufe × 1,45 (skaliert mit dem Autowert)
CarCatalog.TuneMinCost = 100

-- Wirkung je Stufe
CarCatalog.Effects = {
	enginePower = 0.08, -- +8 % PS
	engineTop = 0.025, -- +2,5 % Höchstgeschwindigkeit
	gearboxTop = 0.035, -- +3,5 % Höchstgeschwindigkeit
	gearboxAccel = 0.03, -- +3 % Beschleunigung
	tiresGrip = 0.07, -- +0,07 Reibwert
	gripMax = 1.6,
	suspStiffness = 0.12, -- +12 % Federrate
	suspDamping = 0.04, -- +0,04 Dämpfungsmaß
	suspSteer = 0.6, -- +0,6° Lenkeinschlag
	gearsFromGearbox = 3, -- ab Getriebe-Stufe 3 ein Gang mehr (Anzeige)
}
-- Nitro-Stufen 1..3: Schub-Faktor (Höchstgeschwindigkeit und Drehmoment), Dauer, Abklingzeit in Sekunden
CarCatalog.Nitro = {
	{ boost = 1.25, seconds = 2.0, cooldown = 14 },
	{ boost = 1.35, seconds = 2.6, cooldown = 11 },
	{ boost = 1.45, seconds = 3.2, cooldown = 8 },
}

---------------------------------------------------------------- Optik (Preise für Änderungen)
CarCatalog.Style = {
	paint = { name = "Lackierung", share = 0.03, min = 150, level = 1 },
	rims = { name = "Felgenfarbe", share = 0.02, min = 100, level = 1 },
	glow = { name = "Unterbodenlicht", share = 0.04, min = 250, level = 5 },
	spoiler = { name = "Spoiler", share = 0.015, min = 80, level = 1 },
}

---------------------------------------------------------------- Handel, XP, Abklingzeiten
CarCatalog.SellShare = 0.5 -- Rückkauf durch den Händler: 50 % von Autowert + Tuning
CarCatalog.BuyRepeatSeconds = 5 -- gleiches Modell innerhalb 5 s erneut gekauft = Doppelklick, verworfen
CarCatalog.BuyXp = 60
CarCatalog.TuneXp = 15
CarCatalog.StyleXp = 5
CarCatalog.SpawnCooldown = 3
CarCatalog.IdleDespawnSeconds = 600 -- unbenutztes Auto (niemand am Steuer) verschwindet nach 10 Min.
CarCatalog.Testdrive = { seconds = 60, cooldown = 15 }
CarCatalog.Carwash = { price = 150, shineSeconds = 900, range = 70, cooldown = 10, reflectance = 0.18 }
-- Spawn-Schlüssel für mini_car_spawn (City.CarSpawns.<key>; "workshop" = eigener Werkstatt-Parkplatz)
CarCatalog.SpawnKeys = { "workshop", "dealer", "testdrive", "track", "carwash", "plaza", "scrapyard", "tuning" }

---------------------------------------------------------------- Zeitfahren (TrackRules)
CarCatalog.Track = {
	countdown = 3, -- Sekunden bis zum Start (Startampel)
	maxRunSeconds = 240, -- danach verfällt der Lauf
	-- Balance: eine Runde auf dem Oval (~780 Studs) dauert je nach Auto etwa 8–16 s. Der ganze Topf je Spieler
	-- (erste Runde + alle Verbesserungen unter der Basiszeit) liegt bei ~400 Cr × Level-Bonus.
	firstReward = 100, -- erste gültige Runde
	perSecond = 15, -- Cr je Sekunde Verbesserung der belohnten Bestzeit
	baselineSeconds = 30, -- Verbesserungen zählen erst unterhalb dieser Zeit (langsame erste Runde bringt nichts)
	maxReward = 250, -- Deckel je Lauf (vor Level-Bonus)
	levelBonus = 0.1, -- +10 % je Spielerlevel über 1 (Level 40: ×4,9)
	minImprovement = 0.05, -- Sekunden
	xp = 15, -- XP für eine neue Bestzeit
	speedMargin = 1.3, -- Plausibilität: schneller als (schnellstes Auto × Nitro × 1,3) gilt als Teleport
	segmentFloor = 0.5, -- Mindestzeit je Abschnitt in Sekunden
	minLapSeconds = 6, -- Mindestzeit einer ganzen Runde
	touchSlack = 25, -- Chassis muss so nah (Studs, zusätzlich zur halben Checkpoint-Größe) am Checkpoint sein
}

---------------------------------------------------------------- Physik der VehicleFactory
CarCatalog.Physics = {
	wheelDensity = 0.5,
	knuckleDensity = 2,
	knuckleSize = 1,
	driverMass = 10, -- geschätzte Masse der Figur am Steuer (für Federvorspannung und Drehmoment)
	rideDeflection = 0.35, -- statischer Federweg in Studs bei Fahrwerk 0
	travel = 0.6, -- Federweg ± in Studs (Grenzen der CylindricalConstraint)
	springLength = 2.0, -- Abstand Federbein oben (Chassis) zur Radmitte
	dampingRatio = 0.38, -- Dämpfungsmaß bei Fahrwerk 0
	lossFactor = 1.25, -- Drehmoment-Reserve für Rollwiderstand
	brakeDecel = 40, -- Bremsverzögerung in Studs/s²
	coastShare = 0.08, -- Motorbremse ohne Gas (Anteil des Bremsmoments)
	parkShare = 1.5, -- Parkbremse ohne Fahrer
	steerSpeed = 5, -- Servo-Lenkgeschwindigkeit (rad/s)
	steerTorque = 50000, -- ServoMaxTorque der Lenkung
	hullBottom = 1.45, -- Kollisionsrumpf (Chassis) Y-Bereich über dem Boden
	hullTop = 3.2,
	hullHalfWidth = 3.45, -- innerhalb der Reifen (Reifen-Innenkante bei X ±3,52)
	seatTop = 2.6, -- Sitzfläche des (unsichtbaren) VehicleSeat (tief, damit Figuren möglichst im Auto sitzen)
	spawnLift = 0.4, -- Abstand über dem Boden beim Spawnen
	spawnSpacing = 11, -- seitlicher Versatz, wenn der Spawnpunkt belegt ist
	plotFallback = { 0, -1, 62 }, -- Werkstatt ohne Part CarSpawn: plotlokal (X, Y, Z), Nase zur Straße (+Z)
}

---------------------------------------------------------------- Aufbau der Modell-Liste (aus C.Cars)
CarCatalog.Models = {} -- Händlermodelle in C.Cars-Reihenfolge, dann Sondermodelle
CarCatalog.ModelById = {}
CarCatalog.DealerModels = {}

local function add(def)
	table.insert(CarCatalog.Models, def)
	CarCatalog.ModelById[def.id] = def
	if def.dealer then
		table.insert(CarCatalog.DealerModels, def)
	end
end

for _, car in ipairs(C.Cars) do
	local d = CarCatalog.Dealer[car.id] or CarCatalog.DealerFallback
	add({
		id = car.id, name = car.name, brand = car.brand, body = car.body,
		level = Unlocks.CarLevel(car.id) or car.level, -- Händler-Level aus GameConfig.Unlocks (Elys 90)
		price = d.price or car.value, value = d.price or car.value,
		power = d.power, top = d.top, weight = d.weight, grip = d.grip, steer = d.steer, drive = d.drive,
		paint = d.paint, rims = 1, glow = 0, spoiler = CarCatalog.BodySpoiler[car.body] == true,
		dealer = true, special = false,
	})
end
for _, s in ipairs(CarCatalog.Specials) do
	if not CarCatalog.ModelById[s.id] then
		add({
			id = s.id, name = s.name, brand = s.brand, body = s.body,
			level = Unlocks.CarLevel(s.id) or s.level, -- Auktions-Level aus GameConfig.Unlocks ("car:<id>")
			price = s.value, value = s.value,
			power = s.power, top = s.top, weight = s.weight, grip = s.grip, steer = s.steer, drive = s.drive,
			paint = s.paint, rims = s.rims or 1, glow = s.glow or 0, spoiler = s.spoiler == true,
			dealer = false, special = true,
		})
	end
end

-- DLC-Modelle (Dlc-Abschnitt): Werte vom Basismodell, eigene Optik; dealer = false, special = false, dlc = true
for _, x in ipairs(CarCatalog.Dlc) do
	local base = CarCatalog.ModelById[x.base]
	if base and not CarCatalog.ModelById[x.id] then
		add({
			id = x.id, name = x.name, brand = x.brand or base.brand, body = x.body or base.body,
			level = base.level, -- ab dem Level des Basismodells (Unlocks "car:<base>")
			price = base.price, value = base.value, -- Credits-Preis im Shop: price × GameConfig.Shop.DlcPriceFactor
			power = base.power, top = base.top, weight = base.weight, grip = base.grip, steer = base.steer, drive = base.drive,
			paint = x.paint or base.paint, rims = x.rims or 1, glow = x.glow or 0, spoiler = x.spoiler == true,
			dealer = false, special = false, dlc = true, base = base.id, wrap = x.wrap,
		})
		CarCatalog.DlcById[x.id] = x
	end
end

function CarCatalog.Model(id)
	if type(id) ~= "string" then
		return nil
	end
	-- 3.x: das Startauto liegt nicht in ModelById (Händler/Auktion/Shop kennen es nicht), ist aber ein gültiges Modell
	return CarCatalog.ModelById[id] or (id == CarCatalog.StarterId and CarCatalog.Starter or nil)
end

-- Ist das Modell das Startauto „Flitzer“?
function CarCatalog.IsStarter(id)
	return id == CarCatalog.StarterId
end

-- Physik-Maße einer Karosserie: CarCatalog.Physics, überschrieben von CarCatalog.BodyPhysics[body]
function CarCatalog.PhysicsFor(body)
	local over = type(body) == "string" and CarCatalog.BodyPhysics[body] or nil
	if not over then
		return CarCatalog.Physics
	end
	local out = {}
	for k, v in pairs(CarCatalog.Physics) do
		out[k] = v
	end
	for k, v in pairs(over) do
		out[k] = v
	end
	return out
end

local function rgb(t)
	return Color3.fromRGB(t[1], t[2], t[3])
end
function CarCatalog.PaintColor(i)
	local e = CarCatalog.Paints[i] or CarCatalog.Paints[1]
	return rgb(e.color)
end
function CarCatalog.RimColor(i)
	local e = CarCatalog.Rims[i] or CarCatalog.Rims[1]
	return rgb(e.color), e.reflectance or 0
end
function CarCatalog.GlowColor(i)
	local e = CarCatalog.Glows[i]
	return e and rgb(e.color) or nil
end

return CarCatalog
