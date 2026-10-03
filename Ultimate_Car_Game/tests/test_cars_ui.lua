-- Autos (Client): DealerUI, CarTuningUI, DriveClient, TrackUI, CarwashUI im Mock mit echtem Client (MiniUI, MiniLocale,
-- PreviewCars aus dem Basisbaum) und einem Test-Snapshot. Knöpfe werden geklickt, gesendete Absichten und Nutzlasten
-- geprüft (ein Aufzeichnungs-Remote, zusätzlich einmal der echte MiniRemote). Unabhängig von der Server-Anbindung.
local FORBIDDEN = { amount = true, price = true, cost = true, credits = true, reward = true, time = true, now = true, timestamp = true, speed = true, value = true }
local OWN = { "DealerUI", "CarTuningUI", "DriveClient", "TrackUI", "CarwashUI", "test_cars_ui" }

local function start(H, opts)
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p)
	g:Advance(1.5)
	return g, p
end

-- Aufzeichnungs-Remote: prüft jede Nutzlast (flach, nur string/number/boolean, ≤ 9 Felder, keine Beträge)
local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
			T.check(not FORBIDDEN[k], action .. ": kein Betrag/Zeitstempel im Feld " .. tostring(k))
		end
		T.check(n <= 9, action .. ": höchstens 9 Felder")
		table.insert(r.sent, { action, payload })
		return #r.sent
	end
	r.SendRaw = r.Send
	function r.Count(name)
		local c = 0
		for _, a in ipairs(r.sent) do
			if a[1] == name then
				c += 1
			end
		end
		return c
	end
	function r.Last(name)
		for i = #r.sent, 1, -1 do
			if r.sent[i][1] == name then
				return r.sent[i][2]
			end
		end
		return nil
	end
	function r.Clear()
		r.sent = {}
	end
	return r
end

-- Seite in eigener ScreenGui aufbauen (unabhängig davon, ob MiniClient die Tabs schon kennt)
local function build(g, p, modName, rec, width)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini." .. modName)
	local toasts = {}
	local page = g:InClient(p, function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "AutoTest_" .. modName
		gui.ResetOnSpawn = false
		gui.Parent = p.PlayerGui
		local frame = MiniUI.Frame(gui, { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(0, width or 338, 0, 0) })
		MiniUI.List(frame, 12)
		local ctx = {
			UI = MiniUI, Remote = rec,
			Toast = function(text)
				table.insert(toasts, text)
			end,
			Close = function()
				MiniUI.Close()
			end,
		}
		if modName == "CarTuningUI" then
			mod.Build(frame, ctx, 0)
		else
			mod.Build(frame, ctx)
		end
		return frame
	end)
	return mod, page, MiniUI, toasts
end

local function render(g, p, mod, s)
	g:InClient(p, function()
		mod.Render(s)
	end)
end

local function press(g, button)
	g:Advance(0.35)
	local ok = g:Click(button)
	g:Advance(0.05)
	return ok
end

local function find(root, pred)
	for _, x in ipairs(root:GetDescendants()) do
		if pred(x) then
			return x
		end
	end
	return nil
end

local function byName(root, name, class)
	return find(root, function(x)
		return x.Name == name and (not class or x.ClassName == class)
	end)
end

local function enabled(b)
	return b ~= nil and b:GetAttribute("disabled") ~= true
end

local function visible(H, x)
	return x ~= nil and H.Mock.IsGuiVisible(x)
end

local function colorEq(a, b)
	return a and b and math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end

local function ownErrors(g)
	local out = {}
	for _, e in ipairs(g:Errors()) do
		for _, name in ipairs(OWN) do
			if tostring(e):find(name, 1, true) then
				table.insert(out, e)
				break
			end
		end
	end
	for _, w in ipairs(g:Warnings()) do
		for _, name in ipairs(OWN) do
			if tostring(w):find(name, 1, true) or tostring(w):find("[Fahren]", 1, true) then
				table.insert(out, w)
				break
			end
		end
	end
	return out
end

local function noOwnErrors(T, g, what)
	local list = ownErrors(g)
	T.eq(#list, 0, (what or "keine Fehler in den Auto-Modulen") .. ": " .. table.concat(list, "\n---\n"))
end

-- Snapshot in der Form von CarRules.SnapshotFields (cars = CarRules.View, catalog = CarRules.CatalogView)
local function tune(levels, costs, need)
	local out = {}
	for part, lvl in pairs(levels) do
		local max = part == "nitro" and 3 or 5
		out[part] = { level = lvl, max = max, cost = lvl < max and costs[part] or 0, needLevel = lvl < max and (need and need[part] or 1) or 0 }
	end
	return out
end

local function snapshot(extra)
	local s = {
		credits = 50000,
		level = 20,
		cars = {
			{
				id = 1, model = "komet", name = "Komet C1", brand = "Komet", body = "compact", special = false,
				paint = 6, rims = 3, glow = 0, spoiler = false,
				engine = 1, gearbox = 0, tires = 2, suspension = 0, nitro = 1, locked = false, bought = 0,
				value = 4500, sellValue = 2250,
				tune = tune({ engine = 1, gearbox = 0, tires = 2, suspension = 0, nitro = 1 },
					{ engine = 1200, gearbox = 900, tires = 800, suspension = 700, nitro = 1500 },
					{ engine = 3, gearbox = 2, tires = 5, suspension = 1, nitro = 10 }),
				styleCost = { paint = 150, rims = 100, glow = 250, spoiler = 80 },
				stats = { power = 97, topSpeed = 80, zeroTo100 = 9.1, grip = 1.09, weight = 1050, drive = "FWD", gears = 5, rating = 300, nitroLevel = 1 },
			},
			{
				id = 2, model = "vektor", name = "Vektor RS", brand = "Vektor", body = "sport", special = false,
				paint = 6, rims = 1, glow = 2, spoiler = true,
				engine = 5, gearbox = 5, tires = 5, suspension = 5, nitro = 3, locked = true, bought = 0,
				value = 95000, sellValue = 90000,
				tune = tune({ engine = 5, gearbox = 5, tires = 5, suspension = 5, nitro = 3 }, {}),
				styleCost = { paint = 2850, rims = 1900, glow = 3800, spoiler = 1425 },
				stats = { power = 532, topSpeed = 154, zeroTo100 = 3.2, grip = 1.43, weight = 1350, drive = "RWD", gears = 6, rating = 800, nitroLevel = 3 },
			},
		},
		activeCar = 1,
		spawnedCar = true,
		garageMax = 20,
		catalog = {
			{ id = "komet", name = "Komet C1", brand = "Komet", body = "compact", level = 1, price = 12000, power = 90, topSpeed = 78, zeroTo100 = 9.5, drive = "FWD", rating = 280 },
			{ id = "nord", name = "Nord R4", brand = "Nord", body = "sedan", level = 4, price = 40000, power = 150, topSpeed = 92, drive = "RWD" },
			{ id = "vektor", name = "Vektor RS", brand = "Vektor", body = "sport", level = 18, price = 150000, power = 380, topSpeed = 118, drive = "RWD" },
			{ id = "aureon", name = "Vektor Aureon V12", brand = "Vektor", body = "super", level = 30, price = 400000, power = 700, topSpeed = 140, drive = "AWD" },
			{ id = "sonder_x", name = "Sondermodell X", body = "super", price = 1, level = 1, special = true },
		},
		track = { best = 72.4, rewardedBest = 75, runs = 3 },
		carwash = { price = 250, shineLeft = 600 },
		__test = true,
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

-- Farben aus CarCatalog (Paints/Rims/Glows), wie der Client sie ohne Snapshot-Paletten nutzt
local function palette(g, list, i)
	local cat = g:MiniShared("CarCatalog")
	local e = cat[list][i]
	return Color3.fromRGB(e.color[1], e.color[2], e.color[3])
end

local function withCars(s, cars)
	s.cars = cars
	return s
end

---------------------------------------------------------------- Fahrzeug für DriveClient
local function makeVehicle(g, owner, opts)
	opts = opts or {}
	g:Activate()
	local model = Instance.new("Model")
	model.Name = "Auto_" .. tostring(owner)
	model:SetAttribute("OwnerUserId", owner)
	model:SetAttribute("CarId", 1)
	model:SetAttribute("TopSpeed", 80)
	model:SetAttribute("Torque", 5000)
	model:SetAttribute("SteerAngle", 30)
	model:SetAttribute("Nitro", opts.nitro or 1)
	model:SetAttribute("Gears", 6)
	if opts.testdrive then
		model:SetAttribute("TestDrive", true)
		model:SetAttribute("ExpiresAt", g:Now() + 45)
	end
	local chassis = Instance.new("Part")
	chassis.Name = "Chassis"
	chassis.Size = Vector3.new(7, 1, 12)
	chassis.CFrame = CFrame.new(0, 2, -40)
	chassis.Parent = model
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 1, 2)
	seat.CFrame = CFrame.new(-1.5, 3, -40)
	seat.MaxSpeed = 25
	seat.Parent = model
	local drive = Instance.new("Folder")
	drive.Name = "Drive"
	drive.Parent = model
	local function hinge(name, parent)
		local h = Instance.new("HingeConstraint")
		h.Name = name
		h.MotorMaxTorque = 1000
		h.Parent = parent
		return h
	end
	local rl = hinge("MotorRL", drive)
	local rr = hinge("MotorRR", drive)
	rr:SetAttribute("Direction", -1)
	local fl = hinge("SteerFL", drive)
	-- SteerFR über ObjectValue (Constraint liegt woanders im Modell)
	local frReal = hinge("SteerFR_Hinge", model)
	local ref = Instance.new("ObjectValue")
	ref.Name = "SteerFR"
	ref.Value = frReal
	ref.Parent = drive
	model.Parent = g.env.workspace
	return { model = model, seat = seat, rl = rl, rr = rr, fl = fl, fr = frReal }
end

local function sit(g, p, seat)
	g:Activate()
	local hum = p.Character:FindFirstChildOfClass("Humanoid")
	hum.SeatPart = seat
	hum.Sit = seat ~= nil
end

-- Startet DriveClient mit Aufzeichnungs-Remote. Ist MiniClient schon verkabelt (DriveClient läuft bereits), übernimmt
-- ein zweites Start(ctx) Remote und Toast. Echte Server-Snapshots (ohne __test) erreichen den Fahrzustand im Test
-- nicht, damit sie die simulierten Zeitfahren-Hinweise nicht überschreiben.
local function startDrive(g, p, rec)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local Drive = g:ClientModule(p, "Mini.DriveClient")
	local toasts = {}
	g:InClient(p, function()
		Drive.Start({
			UI = MiniUI, Remote = rec,
			Toast = function(t)
				table.insert(toasts, t)
			end,
		})
		if not Drive.__testFilter then
			local original = Drive.OnSnapshot
			Drive.OnSnapshot = function(s)
				if type(s) == "table" and s.__test then
					original(s)
				end
			end
			Drive.__testFilter = true
		end
	end)
	return Drive, toasts
end

-- Der Mock führt Frames (Heartbeat) alle 0,25 s aus: mindestens einen Frame laufen lassen
local function frame(g, n)
	g:Advance(0.3 * (n or 1))
end

local function driveInfo(g, p, Drive)
	return g:InClient(p, function()
		return Drive.Info()
	end)
end

return {
	{ "Autohaus: Katalog mit 3D-Vorschau, Balken, Kaufen mit Bestätigung, Probefahrt", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Dealer, page, MiniUI = build(g, p, "DealerUI", rec)
		render(g, p, Dealer, snapshot())
		local catalog = byName(page, "Katalog")
		local items = {}
		for _, x in ipairs(catalog:GetChildren()) do
			if x.Name == "Modell" and x.Visible then
				table.insert(items, x)
			end
		end
		T.eq(#items, 4, "vier kaufbare Modelle (Sondermodell ausgeblendet)")
		-- 3D-Vorschau: Klon aus PreviewCars mit eigener Kamera, Lack in Modellfarbe
		local C = g:Config()
		local first = items[1]
		local view = first and first:FindFirstChildOfClass("ViewportFrame")
		if T.check(view ~= nil, "ViewportFrame im Katalog") then
			local world = view:FindFirstChildOfClass("WorldModel")
			local car = world and world:FindFirstChild("compact")
			T.check(car ~= nil, "Karosserie compact aus PreviewCars geklont")
			T.check(view.CurrentCamera ~= nil and view.CurrentCamera.Parent == view, "eigene Kamera")
			local paint = car and car:FindFirstChild("Paint")
			local rgb = C.CarById.komet.color
			T.check(paint and colorEq(paint.Color, Color3.fromRGB(rgb[1], rgb[2], rgb[3])), "Lack in der Farbe von C.Cars")
			local shared = g:Find("ReplicatedStorage.GarageShared.PreviewCars.compact")
			T.check(shared and shared:FindFirstChild("Paint") and not colorEq(shared.Paint.Color, Color3.fromRGB(rgb[1], rgb[2], rgb[3])), "Vorlage bleibt unverändert")
		end
		local nordView = items[2]:FindFirstChildOfClass("ViewportFrame")
		local nordCar = nordView:FindFirstChildOfClass("WorldModel"):FindFirstChild("sedan")
		T.check(nordCar and colorEq(nordCar:FindFirstChild("Paint").Color, palette(g, "Paints", g:MiniShared("CarCatalog").Dealer.nord.paint)), "Standardlack des Modells aus CarCatalog")
		T.check(find(first, function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("Frontantrieb · 0–100 in 9,5 s", 1, true)
		end) ~= nil, "Antrieb und Beschleunigung")
		T.check(find(first, function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("^Grip %d")
		end) ~= nil, "Grip aus CarCatalog ergänzt")
		-- Preis, Level, Balken
		T.check(find(first, function(x)
			return x.ClassName == "TextLabel" and x.Text == "12.000 Cr"
		end) ~= nil, "Preis angezeigt")
		T.check(find(items[4], function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("ab Level 30", 1, true)
		end) ~= nil, "Level angezeigt")
		local powerText = find(items[4], function(x)
			return x.ClassName == "TextLabel" and x.Text == "Leistung 700 PS"
		end)
		if T.check(powerText ~= nil, "Leistung mit Einheit") then
			local fill = powerText.Parent:FindFirstChildOfClass("Frame"):FindFirstChildOfClass("Frame")
			T.near(fill.Size.X.Scale, 1, 1e-6, "stärkstes Modell: voller Balken")
		end
		local komPower = find(first, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Leistung 90 PS"
		end)
		T.near(komPower.Parent:FindFirstChildOfClass("Frame"):FindFirstChildOfClass("Frame").Size.X.Scale, 90 / 700, 1e-6, "Balken relativ")
		-- Kaufen: erst nach Bestätigung, nur das Modell
		local buy = byName(first, "Kaufen", "TextButton")
		T.check(enabled(buy), "Kaufen aktiv (Level und Guthaben reichen)")
		press(g, buy)
		T.eq(rec.Count("mini_car_buy"), 0, "noch nicht gesendet")
		T.eq(MiniUI.Shade.Visible, true, "Bestätigungsdialog")
		T.check(tostring(MiniUI.ConfirmText.Text):find("12.000 Cr", 1, true) ~= nil, "Dialog nennt den Preis")
		press(g, MiniUI.ConfirmYes)
		local a = rec.Last("mini_car_buy")
		T.eq(a and a.model, "komet", "Kauf: Modell")
		T.eq(rec.Count("mini_car_buy"), 1, "genau eine Absicht")
		-- gesperrt: Level zu niedrig, zu teuer
		local superBuy = byName(items[4], "Kaufen", "TextButton")
		T.check(not enabled(superBuy) and superBuy.Text == "Ab Level 30", "Level-Sperre")
		T.check(not enabled(byName(items[3], "Kaufen", "TextButton")), "zu teuer gesperrt")
		-- Probefahrt
		press(g, byName(items[2], "Probefahrt", "TextButton"))
		T.eq(rec.Last("mini_car_testdrive") and rec.Last("mini_car_testdrive").model, "nord", "Probefahrt: Modell")
		-- Katalog kommt nur einmal: späterer Snapshot ohne Katalog behält ihn
		local s2 = snapshot()
		s2.catalog = nil
		render(g, p, Dealer, s2)
		local count = 0
		for _, x in ipairs(catalog:GetChildren()) do
			if x.Name == "Modell" and x.Visible then
				count += 1
			end
		end
		T.eq(count, 4, "Katalog zwischengespeichert")
		-- laufende Probefahrt (Snapshot testdrive) und Hinweis car_bought
		render(g, p, Dealer, snapshot({ testdrive = { model = "nord", name = "Nord R4", endsAt = g:Now() + 42 } }))
		local tdLabel = byName(page, "Probefahrt", "TextLabel")
		T.check(tdLabel and tdLabel.Visible and tdLabel.Text == "Probefahrt läuft: Nord R4 · noch 0:42", "Probefahrt-Restzeit im Autohaus (" .. tostring(tdLabel and tdLabel.Text) .. ")")
		g:InClient(p, function()
			Dealer.OnNotice({ kind = "car_bought", id = 3, model = "nord", name = "Nord R4" })
		end)
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Visible and tostring(x.Text):find("Nord R4 gehört jetzt dir", 1, true)
		end) ~= nil, "Kauf bestätigt")
		render(g, p, Dealer, snapshot())
		T.check(not byName(page, "Probefahrt", "TextLabel").Visible, "ohne Probefahrt keine Restzeit")
		-- volle Garage
		local full = {}
		for i = 1, 20 do
			full[i] = { id = i, model = "komet", body = "compact", paint = 1, rims = 1 }
		end
		render(g, p, Dealer, withCars(snapshot(), full))
		T.eq(byName(first, "Kaufen", "TextButton").Text, "Garage voll", "Garage voll (20/20)")
		noOwnErrors(T, g)
	end },

	{ "Meine Autos: holen (Abholpunkt/Werkstatt), abstellen, tunen, verkaufen, Auktionssperre", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		-- Abholpunkt "dealer" direkt neben der Figur
		g:Activate()
		local city = g.env.workspace:FindFirstChild("City")
		if not city then
			city = Instance.new("Model")
			city.Name = "City"
			city.Parent = g.env.workspace
		end
		-- eigene Abholpunkte statt der generierten Stadt (deren Autohaus-Spawn läge sonst ebenfalls in der Nähe)
		local generated = city:FindFirstChild("CarSpawns")
		if generated then
			generated:Destroy()
		end
		local spawns = Instance.new("Folder")
		spawns.Name = "CarSpawns"
		spawns.Parent = city
		local spot = Instance.new("Part")
		spot.Name = "dealer"
		spot.Anchored = true
		spot.CFrame = CFrame.new(g:Root(p).Position + Vector3.new(4, 0, 0))
		spot.Parent = spawns
		local Dealer, page, MiniUI = build(g, p, "DealerUI", rec)
		local DealerLib = Dealer.Lib
		render(g, p, Dealer, snapshot())
		local mine = byName(page, "MeineAutos")
		local items = {}
		for _, x in ipairs(mine:GetChildren()) do
			if x.Name == "MeinAuto" and x.Visible then
				table.insert(items, x)
			end
		end
		T.eq(#items, 2, "zwei eigene Autos")
		local one, two = items[1], items[2]
		T.check(find(one, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Unterwegs · aktives Auto"
		end) ~= nil, "Status unterwegs")
		T.check(find(two, function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("Auktion", 1, true)
		end) ~= nil, "Status Auktion")
		-- Vorschau in eigener Optik: Lack Palette 2, Felgen Palette 3
		local car = one:FindFirstChildOfClass("Frame") and find(one, function(x)
			return x.ClassName == "Model" and x.Name == "compact"
		end)
		if T.check(car ~= nil, "Vorschau des eigenen Autos") then
			T.check(colorEq(car:FindFirstChild("Paint").Color, palette(g, "Paints", 6)), "Lack aus der Palette")
			T.check(colorEq(car:FindFirstChild("WheelFLRim").Color, palette(g, "Rims", 3)), "Felgen aus der Palette")
			T.check(colorEq(car:FindFirstChild("WheelRRSpoke").Color, palette(g, "Rims", 3)), "Speichen in Felgenfarbe")
		end
		local sport = find(two, function(x)
			return x.ClassName == "Model" and x.Name == "sport"
		end)
		T.check(sport and sport:FindFirstChild("PreviewGlow") ~= nil and colorEq(sport.PreviewGlow.Color, palette(g, "Glows", 2)), "Unterbodenlicht in der Vorschau")
		T.check(sport and sport:FindFirstChild("Spoiler") and sport.Spoiler.Transparency < 1 and sport:FindFirstChild("PreviewSpoiler") == nil, "eigener Spoiler bleibt, kein Zusatzflügel")
		-- Holen am nächsten Abholpunkt
		local holen = byName(one, "Holen", "TextButton")
		T.eq(holen.Text, "Holen: Autohaus", "Abholpunkt in der Nähe")
		press(g, holen)
		local a = rec.Last("mini_car_spawn")
		T.check(a and a.id == 1 and a.at == "dealer", "Holen: id und Abholpunkt")
		press(g, byName(one, "ZurWerkstatt", "TextButton"))
		a = rec.Last("mini_car_spawn")
		T.check(a and a.id == 1 and a.at == "workshop", "Zur Werkstatt")
		-- Abstellen nur für das Auto, das unterwegs ist
		local ab1, ab2 = byName(one, "Abstellen", "TextButton"), byName(two, "Abstellen", "TextButton")
		T.check(visible(H, ab1) and not visible(H, ab2), "Abstellen nur beim gefahrenen Auto")
		press(g, ab1)
		T.eq(rec.Count("mini_car_despawn"), 1, "Abstellen gesendet")
		-- Auktionssperre
		for _, name in ipairs({ "Holen", "Tunen", "Verkaufen" }) do
			T.check(not enabled(byName(two, name, "TextButton")), "gesperrtes Auto: " .. name .. " aus")
		end
		-- Verkaufen mit Bestätigung (Rückkaufpreis 50 % aus dem Katalog nur als Hinweis)
		press(g, byName(one, "Verkaufen", "TextButton"))
		T.eq(rec.Count("mini_car_sell"), 0, "Verkauf erst nach Bestätigung")
		T.check(tostring(MiniUI.ConfirmText.Text):find("2.250 Cr", 1, true) ~= nil, "Dialog nennt den Rückkaufpreis (sellValue)")
		press(g, MiniUI.ConfirmYes)
		T.eq(rec.Last("mini_car_sell") and rec.Last("mini_car_sell").id, 1, "Verkauf: id")
		-- Tunen merkt das Auto für den Tuning-Abschnitt vor
		press(g, byName(one, "Tunen", "TextButton"))
		T.eq(DealerLib.TuneRequest, 1, "Tuning-Wunsch vorgemerkt")
		g:InClient(p, function()
			DealerLib.TuneRequest = nil
		end)
		-- weit weg vom Abholpunkt: Holen liefert zur Werkstatt, "Zur Werkstatt" entfällt
		spot.CFrame = CFrame.new(g:Root(p).Position + Vector3.new(900, 0, 0))
		render(g, p, Dealer, snapshot())
		T.eq(byName(one, "Holen", "TextButton").Text, "Holen", "ohne Abholpunkt in der Nähe")
		T.check(not visible(H, byName(one, "ZurWerkstatt", "TextButton")), "doppelter Knopf ausgeblendet")
		press(g, byName(one, "Holen", "TextButton"))
		T.eq(rec.Last("mini_car_spawn").at, "workshop", "Holen zur Werkstatt")
		spot:Destroy()
		-- spawnedId (CarService) bestimmt, welches Auto draußen ist
		render(g, p, Dealer, snapshot({ spawnedId = 2, activeCar = 2 }))
		T.check(find(two, function(x)
			return x.ClassName == "TextLabel" and x.Text == "In einer Auktion · gesperrt"
		end) ~= nil, "gesperrt hat Vorrang")
		T.check(visible(H, byName(two, "Abstellen", "TextButton")) and not visible(H, byName(one, "Abstellen", "TextButton")), "Abstellen folgt spawnedId")
		-- leere Garage
		render(g, p, Dealer, withCars(snapshot(), {}))
		T.check(find(mine, function(x)
			return x.ClassName == "TextLabel" and x.Visible and tostring(x.Text):find("noch kein eigenes Auto", 1, true)
		end) ~= nil, "Hinweis ohne Autos")
		noOwnErrors(T, g)
	end },

	{ "Mein Auto tunen: Stufen, Live-Vorschau, Stil übernehmen, Auswahl, Sperre", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Tuning, page = build(g, p, "CarTuningUI", rec)
		local Dealer = g:ClientModule(p, "Mini.DealerUI")
		local s = snapshot()
		render(g, p, Tuning, s)
		local id = g:InClient(p, function()
			return (Tuning.Selected())
		end)
		T.eq(id, 1, "aktives Auto vorgewählt")
		-- Leistung: Stufe kaufen mit gesehener Stufe
		local engine = byName(page, "Tune_engine", "TextButton")
		T.eq(engine.Text, "1.200 Cr", "Preis der nächsten Stufe")
		press(g, engine)
		local a = rec.Last("mini_car_tune")
		T.check(a and a.id == 1 and a.part == "engine" and a.level == 1, "Tuning: id, Teil, gesehene Stufe")
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Nitro · Stufe 1/3"
		end) ~= nil, "Nitro bis Stufe 3")
		-- Live-Vorschau: Farbfeld wählt nur lokal
		local preview = find(page, function(x)
			return x.ClassName == "Model" and x.Name == "compact"
		end)
		T.check(preview and colorEq(preview.Paint.Color, palette(g, "Paints", 6)), "Vorschau in gespeicherter Farbe")
		local paintGrid = find(page, function(x)
			return x.Name == "Farbe_5" and x.Parent and x.Parent:FindFirstChild("Farbe_6")
		end)
		local n = #rec.sent
		g:Click(paintGrid)
		g:Advance(0.05)
		T.eq(#rec.sent, n, "Farbwahl sendet nichts")
		T.check(colorEq(preview.Paint.Color, palette(g, "Paints", 5)), "Vorschau sofort umgefärbt")
		T.check(colorEq(preview.Hood.Color, palette(g, "Paints", 5)), "Haube mitgefärbt")
		-- Unterbodenlicht und Spoiler (compact hat keinen eigenen Spoiler)
		local glowGrid = find(page, function(x)
			return x.Name == "Farbe_0" and x:GetAttribute("colorName") == "Aus"
		end).Parent
		g:Click(glowGrid:FindFirstChild("Farbe_1"))
		g:Advance(0.05)
		T.check(preview:FindFirstChild("PreviewGlow") and colorEq(preview.PreviewGlow.Color, palette(g, "Glows", 1)), "Unterbodenlicht in der Vorschau")
		local spoiler = byName(page, "Spoiler", "TextButton")
		press(g, spoiler)
		T.eq(spoiler.Text, "Spoiler: An", "Spoiler an")
		T.check(preview:FindFirstChild("PreviewSpoiler") ~= nil, "Heckflügel in der Vorschau")
		-- Übernehmen: eine Absicht mit allen Stilfeldern
		local apply = byName(page, "Uebernehmen", "TextButton")
		T.eq(apply.Text, "Übernehmen · 480 Cr", "Preis = Lack + Licht + Spoiler (nur Geändertes)")
		press(g, apply)
		a = rec.Last("mini_car_style")
		T.check(a and a.id == 1 and a.paint == 5 and a.rims == 3 and a.glow == 1 and a.spoiler == true, "Stil: id, paint, rims, glow, spoiler")
		-- Zurücksetzen stellt die gespeicherte Optik wieder her
		press(g, byName(page, "Zuruecksetzen", "TextButton"))
		T.check(colorEq(preview.Paint.Color, palette(g, "Paints", 6)), "zurückgesetzt")
		T.check(preview:FindFirstChild("PreviewSpoiler") == nil and preview:FindFirstChild("PreviewGlow") == nil, "Spoiler und Licht wieder aus")
		T.check(not enabled(byName(page, "Uebernehmen", "TextButton")), "ohne Änderung nichts zu übernehmen")
		-- Server hat übernommen: gespeicherte Optik wird neue Grundlage
		local s2 = snapshot()
		s2.cars[1].paint = 5
		render(g, p, Tuning, s2)
		T.check(colorEq(preview.Paint.Color, palette(g, "Paints", 5)), "neue gespeicherte Farbe")
		-- Level-Voraussetzungen: Tuning-Stufe (needLevel) und Unterbodenlicht (CarCatalog.Style.glow.level)
		local low = snapshot({ level = 2 })
		low.cars[1].paint = 5
		render(g, p, Tuning, low)
		local eng = byName(page, "Tune_engine", "TextButton")
		T.check(eng.Text == "Ab Level 3" and not enabled(eng), "Stufe erst ab Spielerlevel")
		g:Click(glowGrid:FindFirstChild("Farbe_2"))
		g:Advance(0.05)
		local applyLow = byName(page, "Uebernehmen", "TextButton")
		T.check(applyLow.Text == "Unterbodenlicht ab Level " .. g:MiniShared("CarCatalog").Style.glow.level and not enabled(applyLow), "Unterbodenlicht erst ab Level")
		press(g, byName(page, "Zuruecksetzen", "TextButton"))
		render(g, p, Tuning, s2)
		-- zweites Auto (Auktion, voll ausgebaut)
		press(g, byName(page, "Weiter", "TextButton"))
		id = g:InClient(p, function()
			return (Tuning.Selected())
		end)
		T.eq(id, 2, "Weiter wählt das nächste Auto")
		local e2 = byName(page, "Tune_engine", "TextButton")
		T.check(e2.Text == "Voll ausgebaut" and not enabled(e2), "Höchststufe")
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("Auktion", 1, true)
		end) ~= nil, "Hinweis Auktionssperre")
		T.check(find(page, function(x)
			return x.ClassName == "Model" and x.Name == "sport"
		end) ~= nil, "Vorschau wechselt die Karosserie")
		-- Wunsch aus "Meine Autos"
		g:InClient(p, function()
			Dealer.Lib.RequestTune(1)
		end)
		render(g, p, Tuning, s2)
		T.eq(g:InClient(p, function()
			return (Tuning.Selected())
		end), 1, "Tuning-Wunsch aus dem Autohaus")
		-- keine Autos
		render(g, p, Tuning, withCars(snapshot(), {}))
		T.check(visible(H, byName(page, "ZumAutohaus", "TextButton")), "Weg zum Autohaus ohne Autos")
		T.check(not visible(H, byName(page, "Tune_engine", "TextButton")), "Tuning ausgeblendet")
		noOwnErrors(T, g)
	end },

	{ "Fahren: Tacho, Regler (Gas, Bremse, Rückwärts, Lenkung), Nitro N + Knopf, Aussteigen, fremde Autos", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Drive, toasts = startDrive(g, p, rec)
		local v = makeVehicle(g, p.UserId)
		local gui = p.PlayerGui:FindFirstChild("Fahren")
		T.check(gui ~= nil and gui.Enabled == false, "HUD vorhanden, aber aus")
		sit(g, p, v.seat)
		v.seat.ThrottleFloat = 1
		v.seat.SteerFloat = 1
		frame(g)
		local info = driveInfo(g, p, Drive)
		T.eq(info.driving, true, "fährt im eigenen Auto")
		T.eq(gui.Enabled, true, "Tacho sichtbar")
		T.near(v.rl.AngularVelocity, 80 / 1.3, 1e-6, "Antrieb hinten links: Spitze / Radradius")
		T.near(v.rr.AngularVelocity, -80 / 1.3, 1e-6, "Direction -1 dreht um")
		T.eq(v.rl.MotorMaxTorque, 5000, "Antriebsmoment aus Torque")
		T.near(v.fl.TargetAngle, 30, 1e-6, "rechts lenken: positiver Winkel")
		T.near(v.fr.TargetAngle, 30, 1e-6, "Lenkung über ObjectValue")
		T.eq(v.seat.HeadsUpDisplay, false, "Standard-Tacho aus")
		-- Fahrt mit 40 Studs/s: km/h, Gang, weniger Lenkeinschlag
		v.seat.AssemblyLinearVelocity = Vector3.new(0, 0, -40)
		g:Advance(1.5)
		info = driveInfo(g, p, Drive)
		T.check(info.kmh >= 39 and info.kmh <= 41, "40 Studs/s ≈ 40 km/h (" .. tostring(info.kmh) .. ")")
		local _, refs = g:InClient(p, function()
			return Drive.Gui()
		end)
		T.eq(refs.speed.Text, tostring(info.kmh), "Tacho zeigt km/h")
		T.eq(refs.gear.Text, "4", "Gang 4 bei halber Spitze (6 Gänge)")
		T.near(v.fl.TargetAngle, 30 * (1 - 0.55 * 0.5), 1e-6, "Lenkeinschlag sinkt mit dem Tempo")
		-- Bremsen: Gas zurück bei Vorwärtsfahrt
		v.seat.ThrottleFloat = -1
		frame(g)
		T.eq(v.rl.AngularVelocity, 0, "Bremsen: Räder halten")
		T.eq(v.rl.MotorMaxTorque, 5000 * 2.5, "Bremsmoment")
		-- Rückwärts aus dem Stand
		v.seat.AssemblyLinearVelocity = Vector3.zero
		frame(g)
		T.near(v.rl.AngularVelocity, -80 * Drive.ReverseFactor / 1.3, 1e-6, "Rückwärts mit Anteil der Spitze (CarCatalog.ReverseShare)")
		T.near(Drive.ReverseFactor, g:MiniShared("CarCatalog").ReverseShare, 1e-9, "Rückwärts-Anteil aus CarCatalog")
		-- Nitro über Taste N: eine Absicht, Spam gebremst
		v.seat.ThrottleFloat = 1
		T.eq(g:Key(p, Enum.KeyCode.N), true, "Taste N wird geschluckt")
		g:Key(p, Enum.KeyCode.N)
		T.eq(rec.Count("mini_car_nitro"), 1, "Nitro: eine Absicht")
		-- Server gewährt Nitro: Schub
		v.model:SetAttribute("NitroUntil", g:Now() + 3)
		frame(g)
		T.near(v.rl.AngularVelocity, 80 * 1.35 / 1.3, 1e-6, "Nitro erhöht die Spitze")
		T.near(v.rl.MotorMaxTorque, 5000 * 1.35, 1e-6, "Nitro erhöht das Moment")
		T.eq(refs.nitro.Text, "NITRO!", "Knopf zeigt aktives Nitro")
		-- Abklingzeit: Knopf gesperrt
		v.model:SetAttribute("NitroUntil", 0)
		v.model:SetAttribute("NitroReadyAt", g:Now() + 5)
		g:Advance(1)
		T.check(not enabled(refs.nitro) and tostring(refs.nitro.Text):find("s", 1, true), "Abklingzeit sichtbar (" .. tostring(refs.nitro.Text) .. ")")
		press(g, refs.nitro)
		T.eq(rec.Count("mini_car_nitro"), 1, "während der Abklingzeit nichts senden")
		-- bereit: Handy-Knopf sendet
		v.model:SetAttribute("NitroReadyAt", 0)
		frame(g)
		T.check(enabled(refs.nitro), "Knopf wieder bereit")
		press(g, refs.nitro)
		T.eq(rec.Count("mini_car_nitro"), 2, "Handy-Knopf sendet Nitro")
		-- Lichthupe: Taste H und Handy-Knopf senden mini_car_horn (Spam gebremst)
		T.eq(g:Key(p, Enum.KeyCode.H), true, "Taste H wird geschluckt")
		g:Key(p, Enum.KeyCode.H)
		T.eq(rec.Count("mini_car_horn"), 1, "Hupe: eine Absicht")
		T.check(refs.horn ~= nil and refs.horn.Visible ~= false, "HUPE-Knopf sichtbar")
		g:Advance(0.6)
		press(g, refs.horn)
		T.eq(rec.Count("mini_car_horn"), 2, "Handy-Knopf hupt")
		-- kein Nitro eingebaut: Knopf weg, Hinweis
		v.model:SetAttribute("Nitro", 0)
		g:Advance(1)
		T.eq(refs.nitro.Visible, false, "ohne Nitro kein Knopf")
		g:Key(p, Enum.KeyCode.N)
		T.eq(rec.Count("mini_car_nitro"), 2, "ohne Nitro keine Absicht")
		T.check(#toasts == 1 and tostring(toasts[1]):find("Nitro", 1, true) ~= nil, "Hinweis ohne Nitro")
		-- Aussteigen: HUD weg, Parkbremse, Lenkung gerade, N frei
		sit(g, p, nil)
		frame(g)
		info = driveInfo(g, p, Drive)
		T.eq(info.driving, false, "ausgestiegen")
		T.eq(gui.Enabled, false, "Tacho aus")
		T.eq(v.rl.AngularVelocity, 0, "Parkbremse")
		T.eq(v.rl.MotorMaxTorque, 5000 * 2.5 * Drive.ParkFactor, "Parkbremse: Anteil des Bremsmoments")
		T.eq(v.fl.TargetAngle, 0, "Lenkung gerade")
		T.eq(g:Key(p, Enum.KeyCode.N), false, "N ist wieder frei")
		-- fremdes Auto: kein Regler
		local other = makeVehicle(g, 424242)
		sit(g, p, other.seat)
		other.seat.ThrottleFloat = 1
		frame(g)
		T.eq(driveInfo(g, p, Drive).driving, false, "fremdes Auto wird nicht gesteuert")
		T.eq(other.rl.AngularVelocity, nil, "fremde Motoren unberührt")
		sit(g, p, nil)
		frame(g)
		-- Auto verschwindet während der Fahrt (Despawn)
		sit(g, p, v.seat)
		frame(g)
		T.eq(driveInfo(g, p, Drive).driving, true, "wieder eingestiegen")
		v.model:Destroy()
		frame(g)
		T.eq(driveInfo(g, p, Drive).driving, false, "Despawn beendet das Fahren")
		T.eq(gui.Enabled, false, "Tacho aus nach Despawn")
		noOwnErrors(T, g)
	end },

	{ "Fahren mit VehicleFactory-Schema: Axle_XX, Steer_XX, DriveWheels, MaxSpeed, Coast/Park, OwnerId", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Drive = startDrive(g, p, rec)
		g:Activate()
		local model = Instance.new("Model")
		model.Name = "Car_" .. p.UserId
		model:SetAttribute("OwnerId", p.UserId)
		model:SetAttribute("CarId", 3)
		model:SetAttribute("MaxSpeed", 90)
		model:SetAttribute("ReverseSpeed", 20)
		model:SetAttribute("Torque", 800)
		model:SetAttribute("BrakeTorque", 1200)
		model:SetAttribute("CoastTorque", 96)
		model:SetAttribute("ParkTorque", 1800)
		model:SetAttribute("SteerAngle", 32)
		model:SetAttribute("WheelRadius", 1.25)
		model:SetAttribute("DriveWheels", "FL,FR")
		model:SetAttribute("Gears", 5)
		model:SetAttribute("NitroLevel", 2)
		model:SetAttribute("NitroBoost", 1.35)
		model:SetAttribute("KmhPerStud", 1.008)
		model:SetAttribute("DriveSign", 1)
		model:SetAttribute("SteerSign", 1)
		model:SetAttribute("Testdrive", true)
		model:SetAttribute("TestdriveEnds", g:Now() + 60)
		local seat = Instance.new("VehicleSeat")
		seat.Name = "DriverSeat"
		seat.CFrame = CFrame.new(0, 3, 0)
		seat.Parent = model
		local folder = Instance.new("Folder")
		folder.Name = "Drive"
		folder.Parent = model
		local axles, steers = {}, {}
		for _, c in ipairs({ "FL", "FR", "RL", "RR" }) do
			local a = Instance.new("CylindricalConstraint")
			a.Name = "Axle_" .. c
			a.MotorMaxTorque = 1800
			a.Parent = folder
			axles[c] = a
		end
		for _, c in ipairs({ "FL", "FR" }) do
			local h = Instance.new("HingeConstraint")
			h.Name = "Steer_" .. c
			h.Parent = folder
			steers[c] = h
		end
		model.Parent = g.env.workspace
		sit(g, p, seat)
		seat.ThrottleFloat = 1
		seat.SteerFloat = -1
		frame(g)
		T.eq(driveInfo(g, p, Drive).driving, true, "OwnerId erkannt")
		T.near(axles.FL.AngularVelocity, 90 / 1.25, 1e-6, "Frontantrieb: vorne angetrieben (MaxSpeed / WheelRadius)")
		T.eq(axles.FL.MotorMaxTorque, 800, "Antriebsmoment je Rad")
		T.eq(axles.RL.MotorMaxTorque, 0, "Hinterachse rollt frei")
		T.eq(axles.RL.AngularVelocity, 0, "Hinterachse ohne Motor-Sollwert")
		T.near(steers.FL.TargetAngle, -32, 1e-6, "links lenken: negativer Winkel")
		-- Bremsen: alle vier Räder
		seat.AssemblyLinearVelocity = Vector3.new(0, 0, -30)
		seat.ThrottleFloat = -1
		frame(g)
		for _, c in ipairs({ "FL", "FR", "RL", "RR" }) do
			T.eq(axles[c].MotorMaxTorque, 1200, "Bremsen " .. c)
			T.eq(axles[c].AngularVelocity, 0, "Bremsen Sollwert " .. c)
		end
		-- Rollen: Motorbremse nur an den angetriebenen Rädern
		seat.ThrottleFloat = 0
		frame(g)
		T.eq(axles.FL.MotorMaxTorque, 96, "CoastTorque vorne")
		T.eq(axles.RR.MotorMaxTorque, 0, "hinten frei beim Rollen")
		local info = driveInfo(g, p, Drive)
		T.eq(info.mode, "coast", "Betriebsart Rollen")
		-- Rückwärts mit ReverseSpeed
		seat.AssemblyLinearVelocity = Vector3.zero
		seat.ThrottleFloat = -1
		frame(g)
		T.near(axles.FR.AngularVelocity, -20 / 1.25, 1e-6, "Rückwärts mit ReverseSpeed")
		-- Probefahrt-Anzeige aus Testdrive/TestdriveEnds, Nitro aus NitroLevel
		local _, refs = g:InClient(p, function()
			return Drive.Gui()
		end)
		T.eq(refs.sideSub.Text, "Probefahrt", "Probefahrt im Tacho")
		T.eq(refs.nitro.Visible, true, "Nitro-Knopf bei NitroLevel 2")
		-- DriveSign/SteerSign drehen um
		model:SetAttribute("DriveSign", -1)
		model:SetAttribute("SteerSign", -1)
		seat.ThrottleFloat = 1
		seat.SteerFloat = 1
		frame(g)
		T.near(axles.FL.AngularVelocity, -90 / 1.25, 1e-6, "DriveSign -1")
		T.near(steers.FR.TargetAngle, -32, 1e-6, "SteerSign -1")
		-- Aussteigen: ParkTorque an allen Rädern
		sit(g, p, nil)
		frame(g)
		for _, c in ipairs({ "FL", "FR", "RL", "RR" }) do
			T.eq(axles[c].MotorMaxTorque, 1800, "ParkTorque " .. c)
		end
		noOwnErrors(T, g)
	end },

	{ "Fahren mit echtem VehicleFactory-Auto (Server baut, Client steuert)", function(T, H)
		local g, p = start(H)
		if not g:Find("ServerScriptService.Garage.Mini.VehicleFactory") then
			print("HINWEIS test_cars_ui: VehicleFactory fehlt, Test übersprungen")
			return
		end
		local rec = recorder(T)
		local Drive = startDrive(g, p, rec)
		local VF = g:MiniServer("VehicleFactory")
		local CarRules = g:MiniShared("CarRules")
		local car = CarRules.NewCar("komet", 0)
		car.id = 1
		car.nitro = 1
		local ok, model = pcall(VF.Build, {
			body = "compact", car = car, stats = CarRules.Stats(car), name = "Car_" .. p.UserId, ownerId = p.UserId,
			carId = 1, modelId = "komet", displayName = "Komet C1", cframe = CFrame.new(0, 0, -60),
		})
		if not ok or not model then
			print("HINWEIS test_cars_ui: VehicleFactory.Build im Mock nicht möglich: " .. tostring(model))
			return
		end
		model.Parent = g.env.workspace
		local seat = model:FindFirstChild("DriverSeat")
		local axle = model.Drive:FindFirstChild("Axle_FL")
		local rear = model.Drive:FindFirstChild("Axle_RL")
		local steer = model.Drive:FindFirstChild("Steer_FR")
		if not T.check(seat and axle and rear and steer, "Sitz, Achsen und Lenkung vorhanden") then
			return
		end
		sit(g, p, seat)
		seat.ThrottleFloat = 1
		seat.SteerFloat = 1
		frame(g)
		T.eq(driveInfo(g, p, Drive).driving, true, "eigenes VehicleFactory-Auto wird gesteuert")
		local stats = CarRules.Stats(car)
		local radius = model:GetAttribute("WheelRadius")
		local drivenFront = tostring(model:GetAttribute("DriveWheels")):find("FL", 1, true) ~= nil
		local drivenAxle = drivenFront and axle or rear
		T.near(drivenAxle.AngularVelocity, stats.topSpeedStuds / radius, 1e-6, "Sollwert aus MaxSpeed und WheelRadius")
		T.near(drivenAxle.MotorMaxTorque, model:GetAttribute("Torque"), 1e-6, "Moment aus Torque")
		T.near(steer.TargetAngle, stats.steerAngle, 1e-6, "Lenkwinkel aus SteerAngle (rechts positiv)")
		model:SetAttribute("NitroUntil", g:Now() + 2)
		frame(g)
		T.near(drivenAxle.AngularVelocity, stats.topSpeedStuds * model:GetAttribute("NitroBoost") / radius, 1e-6, "Nitro-Schub aus NitroBoost")
		sit(g, p, nil)
		frame(g)
		T.near(axle.MotorMaxTorque, model:GetAttribute("ParkTorque"), 1e-6, "Parkbremse aus ParkTorque")
		noOwnErrors(T, g)
	end },

	{ "Zeitfahren: Start, Checkpoints, Ziel im Tab und im Tacho; Probefahrt-Restzeit", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Drive = startDrive(g, p, rec)
		local Track, page = build(g, p, "TrackUI", rec)
		render(g, p, Track, snapshot())
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Bestzeit: 1:12,40"
		end) ~= nil, "Bestzeit angezeigt")
		local startButton = byName(page, "Starten", "TextButton")
		T.check(enabled(startButton), "Start möglich mit eigenem Auto")
		press(g, startButton)
		T.eq(rec.Count("mini_track_start"), 1, "Start gesendet")
		T.check(not enabled(startButton) and startButton.Text == "Wird gestartet …", "bis zur Antwort gesperrt")
		-- im Auto sitzen, damit der Tacho die Zeit zeigt
		local v = makeVehicle(g, p.UserId)
		sit(g, p, v.seat)
		frame(g)
		g:InClient(p, function()
			Track.OnNotice({ kind = "track_start", startedAt = workspace:GetServerTimeNow(), total = 8 })
		end)
		g:Advance(5)
		g:InClient(p, function()
			Track.Step()
		end)
		local running = byName(page, "Laufzeit", "TextLabel")
		T.check(running.Visible and running.Text == "0:05,00", "Laufzeit im Tab (" .. tostring(running.Text) .. ")")
		local _, refs = g:InClient(p, function()
			return Drive.Gui()
		end)
		T.check(refs.side.Visible and (refs.sideTime.Text == "0:05,0" or refs.sideTime.Text == "0:04,8"), "Laufzeit im Tacho (" .. tostring(refs.sideTime.Text) .. ")")
		local cp = { kind = "track_checkpoint", index = 3, total = 8, time = 5 }
		g:InClient(p, function()
			Track.OnNotice(cp)
			Drive.OnNotice(cp) -- dieselbe Tabelle zweimal wirkt einmal
			Track.Step()
		end)
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Checkpoint 3 von 8"
		end) ~= nil, "Checkpoint im Tab")
		frame(g)
		T.eq(refs.sideSub.Text, "Checkpoint 3/8", "Checkpoint im Tacho")
		T.eq(startButton.Text, "Läuft …", "Start gesperrt während der Runde")
		g:InClient(p, function()
			Track.OnNotice({ kind = "track_finish", time = 70.12, best = 70.12, newBest = true, reward = 500 })
			Track.Step()
		end)
		frame(g)
		local result = find(page, function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("Ziel in 1:10,12", 1, true)
		end)
		T.check(result and tostring(result.Text):find("Neue Bestzeit", 1, true) and tostring(result.Text):find("500 Cr", 1, true), "Ergebnis mit Belohnung")
		T.check(refs.sideTime.Text == "1:10,12" and refs.sideSub.Text == "Neue Bestzeit!", "Ergebnis im Tacho")
		T.check(enabled(startButton), "neuer Start möglich")
		-- Startampel: vor startAt zählt der Tacho herunter; Abbruch mit Grund
		g:InClient(p, function()
			Track.OnNotice({ kind = "track_start", startAt = workspace:GetServerTimeNow() + 3, total = 8, countdown = 3 })
		end)
		frame(g)
		T.check(tostring(refs.sideTime.Text):find("^Start in %d") ~= nil, "Startampel im Tacho (" .. tostring(refs.sideTime.Text) .. ")")
		g:InClient(p, function()
			Track.Step()
		end)
		T.check(tostring(running.Text):find("^Start in %d") ~= nil, "Startampel im Tab")
		g:InClient(p, function()
			Track.OnNotice({ kind = "track_abort", reason = "early", cause = "early" })
		end)
		frame(g)
		T.check(refs.sideTime.Text == "Ungültig" and refs.sideSub.Text == "Frühstart", "Abbruchgrund im Tacho")
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Visible and x.Text == "Lauf ungültig: Frühstart."
		end) ~= nil, "Abbruchgrund im Tab")
		-- Snapshot sagt: keine Runde aktiv (nach Karenzzeit)
		g:InClient(p, function()
			Track.OnNotice({ kind = "track_start", startedAt = workspace:GetServerTimeNow(), total = 8 })
		end)
		g:Advance(3)
		render(g, p, Track, snapshot({ track = { best = 70.12, rewardedBest = 70.12, active = false } }))
		T.eq(g:InClient(p, function()
			return Drive.Track().active
		end), false, "Snapshot beendet eine verwaiste Runde")
		-- Probefahrt-Restzeit im Tacho
		sit(g, p, nil)
		frame(g)
		local td = makeVehicle(g, p.UserId, { testdrive = true })
		sit(g, p, td.seat)
		g:Advance(10)
		T.check(refs.sideSub.Text == "Probefahrt" and (refs.sideTime.Text == "0:35" or refs.sideTime.Text == "0:36"), "Probefahrt-Restzeit (" .. tostring(refs.sideTime.Text) .. ")")
		-- aktives Auto in einer Auktion: kein Start
		render(g, p, Track, snapshot({ activeCar = 2, spawnedCar = false }))
		T.check(not enabled(startButton), "gesperrtes aktives Auto: kein Start")
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("gesperrt (Auktion)", 1, true)
		end) ~= nil, "Hinweis gesperrtes Auto")
		-- ohne Auto kein Start
		render(g, p, Track, withCars(snapshot(), {}))
		T.check(not enabled(startButton), "ohne Auto kein Start")
		T.check(visible(H, byName(page, "ZumAutohaus", "TextButton")), "Weg zum Autohaus")
		press(g, byName(page, "Reisen", "TextButton"))
		T.eq(rec.Last("mini_travel") and rec.Last("mini_travel").key, "track", "Schnellreise zur Teststrecke")
		noOwnErrors(T, g)
	end },

	{ "Waschstraße: Preis, Glanz-Restzeit, Waschen, Sperren", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Wash, page = build(g, p, "CarwashUI", rec)
		render(g, p, Wash, snapshot())
		local wash = byName(page, "Waschen", "TextButton")
		T.eq(wash.Text, "Waschen · 250 Cr", "Preis am Knopf")
		T.check(enabled(wash), "Waschen möglich")
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Glanz hält noch 10 Min. 00 Sek."
		end) ~= nil, "Glanz-Restzeit")
		T.check(find(page, function(x)
			return x.ClassName == "Model" and x.Name == "compact"
		end) ~= nil, "Vorschau des aktiven Autos")
		press(g, wash)
		T.eq(rec.Count("mini_carwash"), 1, "Waschen gesendet")
		g:InClient(p, function()
			Wash.OnNotice({ kind = "carwash", shineLeft = 900 })
		end)
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Visible and tostring(x.Text):find("Frisch gewaschen", 1, true)
		end) ~= nil, "Bestätigung")
		render(g, p, Wash, snapshot({ credits = 100 }))
		T.check(not enabled(wash), "zu wenig Guthaben")
		-- Auto steht in der Garage: Waschen gesperrt, Holen zur Waschstraße
		render(g, p, Wash, snapshot({ spawnedCar = false }))
		T.check(not enabled(wash), "Auto nicht draußen: Waschen gesperrt")
		local fetch = byName(page, "Holen", "TextButton")
		T.check(visible(H, fetch) and enabled(fetch), "Holen zur Waschstraße angeboten")
		press(g, fetch)
		local a = rec.Last("mini_car_spawn")
		T.check(a and a.id == 1 and a.at == "carwash", "Holen: id und Abholpunkt carwash")
		-- Glanz als Serverzeit (CarService: shineUntil)
		local s3 = snapshot({ spawnedId = 1 })
		s3.carwash = nil
		s3.shineUntil = g:Now() + 125
		render(g, p, Wash, s3)
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Glanz hält noch 2 Min. 05 Sek."
		end) ~= nil, "Glanz-Restzeit aus shineUntil")
		T.eq(wash.Text, "Waschen · " .. g:MiniShared("MiniLocale").Credits(g:MiniShared("CarCatalog").Carwash.price), "Preis aus CarCatalog")
		render(g, p, Wash, snapshot({ activeCar = 0, spawnedCar = false }))
		T.check(not enabled(wash), "ohne aktives Auto gesperrt")
		T.check(find(page, function(x)
			return x.ClassName == "TextLabel" and tostring(x.Text):find("Kein aktives Auto", 1, true)
		end) ~= nil, "Hinweis ohne aktives Auto")
		noOwnErrors(T, g)
	end },

	{ "Echter Weg: echter Snapshot ohne Autofelder bricht nichts; MiniRemote sendet flach mit rid", function(T, H)
		local g, p = start(H)
		local Remote = g:ClientModule(p, "Mini.MiniRemote")
		-- Snapshot, wie ihn der Server heute schickt (evtl. noch ohne cars/catalog): alles rendert, Kauf gesperrt.
		-- Zuerst, weil der Katalog pro Sitzung zwischengespeichert wird.
		local MiniClient = g:ClientModule(p, "Mini.MiniClient")
		local MiniLocale = g:MiniShared("MiniLocale")
		local real = g:InClient(p, function()
			return MiniClient.Snapshot()
		end)
		if T.check(type(real) == "table", "echter Snapshot vorhanden") then
			local Dealer0, page0 = build(g, p, "DealerUI", Remote)
			render(g, p, Dealer0, real)
			local C = g:Config()
			local models = 0
			for _, x in ipairs(byName(page0, "Katalog"):GetChildren()) do
				if x.Name == "Modell" and x.Visible then
					models += 1
				end
			end
			local hasModule = g:Find("ReplicatedStorage.GarageShared.Mini.CarCatalog") ~= nil
			if real.catalog then
				T.check(models > 0, "Katalog vom Server")
			elseif hasModule then
				T.eq(models, #g:MiniShared("CarCatalog").DealerModels, "Katalog aus dem geteilten CarCatalog")
				T.check(enabled(byName(page0, "Probefahrt", "TextButton")), "Probefahrt mit CarCatalog möglich")
				T.check(find(page0, function(x)
					return x.ClassName == "TextLabel" and x.Text == MiniLocale.Credits(g:MiniShared("CarCatalog").Dealer.komet.price)
				end) ~= nil, "Preis aus CarCatalog")
			else
				T.eq(models, #C.Cars, "Ausweich-Katalog aus C.Cars")
				T.check(not enabled(byName(page0, "Kaufen", "TextButton")), "ohne Server-Katalog kein Kauf")
				T.check(not enabled(byName(page0, "Probefahrt", "TextButton")), "ohne Server-Katalog keine Probefahrt")
			end
			for _, mod in ipairs({ "CarTuningUI", "TrackUI", "CarwashUI" }) do
				local m = build(g, p, mod, Remote)
				render(g, p, m, real)
			end
			noOwnErrors(T, g, "echter Snapshot")
		end
		-- echter MiniRemote: Remotes.Command mit flacher Nutzlast und rid
		local Dealer, page = build(g, p, "DealerUI", Remote)
		render(g, p, Dealer, snapshot())
		local before = #(g:Remote("Command").__data.sentToServer or {})
		local catalog = byName(page, "Katalog")
		press(g, byName(catalog, "Probefahrt", "TextButton"))
		local list = g:Remote("Command").__data.sentToServer or {}
		local found
		for i = before + 1, #list do
			if list[i][1] == "mini_car_testdrive" then
				found = list[i][2]
			end
		end
		T.check(found and found.model == "komet" and type(found.rid) == "number", "mini_car_testdrive {model, rid} über Remotes.Command")
		for k in pairs(found or {}) do
			T.check(k == "model" or k == "rid", "nur model und rid: " .. tostring(k))
		end
		noOwnErrors(T, g)
	end },

	{ "Snapshot aus CarRules.SnapshotFields: Autohaus und Tuning zeigen Server-Werte", function(T, H)
		local g, p = start(H)
		local CarRules = g:MiniShared("CarRules")
		local CarCatalog = g:MiniShared("CarCatalog")
		local MiniLocale = g:MiniShared("MiniLocale")
		if type(CarRules.SnapshotFields) ~= "function" then
			print("HINWEIS test_cars_ui: CarRules.SnapshotFields fehlt, Test übersprungen")
			return
		end
		local a, b = CarRules.NewCar("komet", 0), CarRules.NewCar("vektor", 0)
		a.id, b.id = 1, 2
		a.engine = 2
		local d = { money = 100000, level = 20, games = { cars = { a, b }, carSerial = 2, activeCar = 1 } }
		local s = CarRules.SnapshotFields(d)
		s.credits, s.level, s.spawnedCar = d.money, d.level, false
		local rec = recorder(T)
		local Dealer, page = build(g, p, "DealerUI", rec)
		render(g, p, Dealer, s)
		local models = {}
		for _, x in ipairs(byName(page, "Katalog"):GetChildren()) do
			if x.Name == "Modell" and x.Visible then
				table.insert(models, x)
			end
		end
		T.eq(#models, #CarCatalog.DealerModels, "alle Händlermodelle")
		T.check(find(models[1], function(x)
			return x.ClassName == "TextLabel" and x.Text == MiniLocale.Credits(CarCatalog.Dealer.komet.price)
		end) ~= nil, "Händlerpreis aus dem Server-Katalog")
		T.check(enabled(byName(models[1], "Kaufen", "TextButton")), "Kauf möglich")
		press(g, byName(models[1], "Kaufen", "TextButton"))
		press(g, g:ClientModule(p, "Mini.MiniUI").ConfirmYes)
		T.eq(rec.Last("mini_car_buy") and rec.Last("mini_car_buy").model, "komet", "Kauf mit C.Cars-Id")
		local mine = byName(page, "MeineAutos")
		T.check(find(mine, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Vektor RS"
		end) ~= nil, "Name aus CarRules.View")
		press(g, find(mine, function(x)
			return x.Name == "Verkaufen" and x.ClassName == "TextButton"
		end))
		local MiniUI = g:ClientModule(p, "Mini.MiniUI")
		T.check(tostring(MiniUI.ConfirmText.Text):find(MiniLocale.Credits(s.cars[1].sellValue), 1, true) ~= nil, "Rückkaufpreis aus sellValue")
		press(g, byName(MiniUI.Shade, "Zurück") or find(MiniUI.Shade, function(x)
			return x.ClassName == "TextButton" and x.Text == "Zurück"
		end))
		-- Tuning mit Server-Kosten
		local Tuning, tpage = build(g, p, "CarTuningUI", rec)
		render(g, p, Tuning, s)
		T.eq(byName(tpage, "Tune_engine", "TextButton").Text, MiniLocale.Credits(s.cars[1].tune.engine.cost), "Stufenpreis aus tune.engine.cost")
		T.check(find(tpage, function(x)
			return x.ClassName == "TextLabel" and x.Text == "Motor · Stufe 2/" .. CarCatalog.Tune.engine.max
		end) ~= nil, "Stufe und Höchststufe")
		local paintGrid = find(tpage, function(x)
			return x.Name == "Farbe_12" and x.Parent and x.Parent:FindFirstChild("Farbe_11")
		end)
		T.check(paintGrid ~= nil, "12 Lackfarben aus CarCatalog.Paints")
		g:Click(paintGrid.Parent:FindFirstChild("Farbe_3"))
		g:Advance(0.05)
		T.eq(byName(tpage, "Uebernehmen", "TextButton").Text, "Übernehmen · " .. MiniLocale.Credits(s.cars[1].styleCost.paint), "Preis nur für den Lack")
		press(g, byName(tpage, "Uebernehmen", "TextButton"))
		local st = rec.Last("mini_car_style")
		T.check(st and st.id == 1 and st.paint == 3 and st.rims == a.rims and st.glow == a.glow and st.spoiler == a.spoiler, "Stil mit unveränderten Werten")
		-- der Server prüft dieselben Werte
		local okStyle, cost = CarRules.Style(d, st.id, st.paint, st.rims, st.glow, st.spoiler)
		T.check(okStyle == true and cost == s.cars[1].styleCost.paint, "CarRules.Style akzeptiert die Absicht zum angezeigten Preis")
		noOwnErrors(T, g)
	end },

	{ "Handy: Knöpfe ≥ 44 px, Tacho und Nitro-Knopf passen auf 390×844 und 844×390", function(T, H)
		for _, vp in ipairs({ Vector2.new(390, 844), Vector2.new(844, 390) }) do
			local g, p = start(H, { viewport = vp })
			local rec = recorder(T)
			local small = {}
			for _, mod in ipairs({ "DealerUI", "CarTuningUI", "TrackUI", "CarwashUI" }) do
				local m, page = build(g, p, mod, rec, math.floor(vp.X * 0.97) - 40)
				render(g, p, m, snapshot())
				for _, x in ipairs(page:GetDescendants()) do
					if x.ClassName == "TextButton" then
						local grid = x.Parent and x.Parent:FindFirstChildOfClass("UIGridLayout")
						local h = grid and grid.CellSize.Y.Offset or x.Size.Y.Offset
						local w = grid and (grid.CellSize.X.Scale > 0 and 999 or grid.CellSize.X.Offset) or (x.Size.X.Scale > 0 and 999 or x.Size.X.Offset)
						if h < 44 or w < 44 then
							table.insert(small, mod .. "." .. x.Name)
						end
					end
				end
			end
			T.eq(#small, 0, "Touch-Flächen ≥ 44 px bei " .. vp.X .. "×" .. vp.Y .. ": " .. table.concat(small, ", "))
			local Drive = startDrive(g, p, rec)
			local v = makeVehicle(g, p.UserId)
			sit(g, p, v.seat)
			g:InClient(p, function()
				Drive.OnNotice({ kind = "track_start", startedAt = workspace:GetServerTimeNow(), total = 8 })
			end)
			frame(g)
			local gui, refs = g:InClient(p, function()
				return Drive.Gui()
			end)
			local screen = gui.AbsoluteSize
			for _, x in ipairs({ refs.panel, refs.nitro, refs.flip }) do
				local pos, size = x.AbsolutePosition, x.AbsoluteSize
				T.check(pos.X >= 0 and pos.Y >= 0 and pos.X + size.X <= screen.X and pos.Y + size.Y <= screen.Y,
					x.Name .. " liegt im Bild bei " .. vp.X .. "×" .. vp.Y)
			end
			T.check(refs.nitro.AbsoluteSize.X >= 44 and refs.nitro.AbsoluteSize.Y >= 44, "Nitro-Knopf ≥ 44 px")
			-- 2.4.0-Fortschrittsleiste CompactProgress (Level, XP, Credits) liegt bei y 8..54 oben mittig: Tacho darunter
			T.check(refs.panel.AbsolutePosition.Y >= 54, "Tacho unter der 2.4.0-Fortschrittsleiste")
			local toastTop = g:InClient(p, function()
				return Drive.ToastOffset()
			end)
			T.check(toastTop ~= nil and toastTop >= refs.panel.AbsolutePosition.Y + refs.panel.AbsoluteSize.Y, "Toasts rücken während der Fahrt unter den Tacho")
			T.check(refs.flip.AbsolutePosition.Y >= refs.panel.AbsolutePosition.Y + refs.panel.AbsoluteSize.Y, "Aufrichten-Knopf unter dem Tacho")
			T.check(refs.flip.AbsoluteSize.Y >= 44, "Aufrichten-Knopf ≥ 44 px")
			T.check(refs.nitro.AbsolutePosition.Y + refs.nitro.AbsoluteSize.Y <= screen.Y - 138, "Nitro-Knopf über dem 2.4.0-HUD")
			noOwnErrors(T, g)
		end
	end },

	{ "Fahren: Tuning während der Fahrt wirkt sofort auf das Antriebsmoment (Torque jedes Frame)", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Drive = startDrive(g, p, rec)
		local v = makeVehicle(g, p.UserId)
		sit(g, p, v.seat)
		v.seat.ThrottleFloat = 1
		frame(g)
		T.eq(v.rl.MotorMaxTorque, 5000, "Antriebsmoment beim Einsteigen")
		-- Server: VehicleFactory.ApplyStats nach mini_car_tune (Motor/Getriebe) setzt neue Attribute am Modell
		g:Activate()
		v.model:SetAttribute("Torque", 7200)
		frame(g)
		T.eq(v.rl.MotorMaxTorque, 7200, "neues Moment ohne Aus- und Einsteigen")
		T.eq(v.rr.MotorMaxTorque, 7200, "an allen angetriebenen Rädern")
		-- Bremsmoment ohne eigenes Attribut folgt dem neuen Antriebsmoment
		v.seat.AssemblyLinearVelocity = Vector3.new(0, 0, -30)
		v.seat.ThrottleFloat = -1
		frame(g)
		T.eq(v.rl.MotorMaxTorque, 7200 * 2.5, "Bremsmoment passt zum neuen Moment")
		noOwnErrors(T, g)
	end },

	{ "Fahren: umgekipptes Auto aufrichten (Taste R / Knopf), nur wenn es liegen bleibt", function(T, H)
		local g, p = start(H)
		local rec = recorder(T)
		local Drive = startDrive(g, p, rec)
		local v = makeVehicle(g, p.UserId)
		sit(g, p, v.seat)
		frame(g)
		local _, refs = g:InClient(p, function()
			return Drive.Gui()
		end)
		T.eq(refs.flip.Visible, false, "aufrecht: kein Aufrichten-Knopf")
		T.eq(g:Key(p, Enum.KeyCode.R), false, "R wird aufrecht nicht geschluckt")
		-- Auto liegt auf der Seite (Nase zeigt nach -X)
		g:Activate()
		local chassis = v.model.Chassis
		local side = CFrame.new(20, 1.5, -40) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, math.pi / 2)
		local rel = chassis.CFrame:Inverse() * v.model:GetPivot()
		v.model:PivotTo(side * rel)
		chassis.AssemblyLinearVelocity = Vector3.new(0.5, 0, 0)
		frame(g)
		T.eq(refs.flip.Visible, false, "noch nicht: erst nach FlipDelay")
		g:Advance(Drive.FlipDelay + 0.3)
		T.eq(refs.flip.Visible, true, "„Auto aufrichten“ erscheint")
		T.check(tostring(refs.flip.Text):find("aufrichten", 1, true) ~= nil, "Beschriftung")
		local before = chassis.Position
		T.eq(g:Key(p, Enum.KeyCode.R), true, "Taste R richtet auf (geschluckt)")
		g:Activate()
		T.check(chassis.CFrame.UpVector.Y > 0.99, "aufrecht (UpVector.Y " .. tostring(chassis.CFrame.UpVector.Y) .. ")")
		T.near(chassis.Position.Y, before.Y + Drive.FlipLift, 1e-3, "4 Studs höher")
		T.near(chassis.Position.X, before.X, 1e-3, "gleiche Stelle (X)")
		T.near(chassis.Position.Z, before.Z, 1e-3, "gleiche Stelle (Z)")
		T.check(chassis.CFrame.LookVector:Dot(Vector3.new(-1, 0, 0)) > 0.99, "Blickrichtung bleibt")
		T.eq(chassis.AssemblyLinearVelocity.Magnitude, 0, "Bewegung gestoppt")
		frame(g)
		T.eq(refs.flip.Visible, false, "Knopf wieder weg")
		-- fährt schnell auf der Seite (z. B. rutscht): kein Aufrichten
		g:Activate()
		v.model:PivotTo(side * rel)
		chassis.AssemblyLinearVelocity = Vector3.new(20, 0, 0)
		g:Advance(Drive.FlipDelay + 0.5)
		T.eq(refs.flip.Visible, false, "in Bewegung: kein Aufrichten")
		-- Handy-Knopf (Abklingzeit abgelaufen)
		chassis.AssemblyLinearVelocity = Vector3.zero
		g:Advance(Drive.FlipCooldown + Drive.FlipDelay)
		T.eq(refs.flip.Visible, true, "wieder angeboten")
		press(g, refs.flip)
		T.check(chassis.CFrame.UpVector.Y > 0.99, "Knopf richtet auf")
		-- Aussteigen: R wieder frei
		sit(g, p, nil)
		frame(g)
		T.eq(g.env.casBindings.UCG_Aufrichten, nil, "Taste R nach dem Aussteigen nicht mehr gebunden")
		noOwnErrors(T, g)
	end },

	{ "Fahren: Tacho weicht dem 2.4.0-Tablet, Toast rückt unter den Tacho", function(T, H)
		local g, p = start(H, { viewport = Vector2.new(390, 844) })
		local rec = recorder(T)
		local tabletOpen = false
		local MiniUI = g:ClientModule(p, "Mini.MiniUI")
		local Drive = g:ClientModule(p, "Mini.DriveClient")
		g:InClient(p, function()
			Drive.Start({
				UI = MiniUI, Remote = rec, Toast = function() end,
				IsTabletOpen = function()
					return tabletOpen
				end,
				IsBlocked = function()
					return false
				end,
			})
		end)
		local v = makeVehicle(g, p.UserId)
		sit(g, p, v.seat)
		frame(g)
		local gui = p.PlayerGui:FindFirstChild("Fahren")
		T.eq(gui.Enabled, true, "Tacho sichtbar")
		-- 2.4.0-Toast während der Fahrt: unter dem Tacho statt darunter verdeckt
		g:Activate()
		g.env.services.ReplicatedStorage.GarageShared.Remotes.Event:FireClient(p, "toast", "Probe-Hinweis")
		g:Advance(0.1)
		local toastPanel
		for _, x in ipairs(p.PlayerGui.UltimateCarGame:GetDescendants()) do
			if x:IsA("TextLabel") and x.Text == "Probe-Hinweis" then
				toastPanel = x.Parent
			end
		end
		T.check(toastPanel ~= nil, "2.4.0-Toast gefunden")
		if toastPanel then
			T.eq(toastPanel.Position.Y.Offset, Drive.ToastTop, "Toast unter dem Tacho (y " .. tostring(toastPanel.Position.Y.Offset) .. ")")
		end
		-- Tablet offen: Tacho, Nitro-Knopf aus (lägen sonst über dem Tablet)
		tabletOpen = true
		frame(g)
		T.eq(gui.Enabled, false, "Tacho und Nitro-Knopf weichen dem Tablet")
		T.eq(g:InClient(p, function()
			return Drive.ToastOffset()
		end), nil, "ohne Tacho wieder die 2.4.0-Stelle für Toasts")
		tabletOpen = false
		frame(g)
		T.eq(gui.Enabled, true, "danach wieder sichtbar")
		noOwnErrors(T, g)
	end },

	{ "Panel schließt, wenn der Server den Spieler ins Auto setzt (Zeitfahren, Waschstraße): Handy-Steuerung frei", function(T, H)
		local g, p = start(H, { viewport = Vector2.new(390, 844) })
		local MiniClient = g:ClientModule(p, "Mini.MiniClient")
		local GuiService = g.env.services.GuiService
		local function notice(data)
			g:Activate()
			g.env.services.ReplicatedStorage.GarageShared.Remotes.Event:FireClient(p, "mini_notice", data)
			g:Advance(0.1)
		end
		for _, case in ipairs({
			{ tab = "track", data = { kind = "track_start", startAt = g:Now() + 3, total = 4, countdown = 3 } },
			{ tab = "track", data = { kind = "car_spawned", id = 1, model = "komet", name = "Komet C1", testdrive = false, at = "track" } },
			{ tab = "carwash", data = { kind = "car_spawned", id = 1, model = "komet", name = "Komet C1", testdrive = false, at = "carwash" } },
		}) do
			g:InClient(p, function()
				MiniClient.Open(case.tab)
			end)
			g:Advance(0.1)
			T.eq(MiniClient.IsOpen(), true, "Panel offen (" .. case.tab .. ")")
			T.eq(GuiService.TouchControlsEnabled, false, "Touch-Steuerung aus, solange das Panel offen ist")
			notice(case.data)
			T.eq(MiniClient.IsOpen(), false, case.data.kind .. " auf Tab " .. case.tab .. " schließt das Panel")
			T.eq(GuiService.TouchControlsEnabled, true, "Stick wieder da")
		end
		noOwnErrors(T, g)
	end },
}
