-- Startauto „Flitzer“ (3.x, Team Autos): Besitz für neue und alte Profile (idempotent, nicht in d.games.cars),
-- unverkäuflich/nicht tunebar, Fahrwerte ohne Pay-to-win, Bau aus Parts (VehicleFactory), car_call (Open World,
-- Fahrbahn neben dem Spieler, einsetzen, Abklingzeit, Lieblingsauto, Sperren in Lobby/Tycoon/Probefahrt/Zeitfahren),
-- Begrüßungs-Flitzer nach der Startwahl, Taste G (DriveClient) und Handy-App „Auto rufen“ (PhoneUI).
-- car_call/car_favourite verkabelt der Integrator in MiniNet; hier trägt der Test sie vor dem Serverstart selbst in
-- MiniNet.Actions ein (wie die Verkabelung), damit der echte Weg Remotes.Command -> request -> Mini.Handle läuft.
local NOW = 1760000000

---------------------------------------------------------------- Hilfen
local function wire(g)
	local net = g:MiniShared("MiniNet")
	net.Actions.car_call = net.Actions.car_call or {}
	net.Actions.car_favourite = net.Actions.car_favourite or { id = "number" }
	net.Cooldowns.car_call = net.Cooldowns.car_call or 1
	net.Cooldowns.car_favourite = net.Cooldowns.car_favourite or 0.3
end

local function garage(H, opts)
	opts = opts or {}
	local before = opts.before
	opts.before = function(g)
		wire(g)
		if before then
			before(g)
		end
	end
	opts.startTime = opts.startTime or NOW
	return H.Garage(opts)
end

local function join(g, userId, name, opts)
	local pl = g:Join(userId, { name = name, level = opts and opts.level })
	g:Advance(0.5)
	g:Send(pl, "hello")
	g:Advance(0.5)
	return pl, g:D(pl)
end

local rid = 0
local function act(g, pl, action, payload)
	rid += 1
	payload = payload or {}
	payload.rid = rid
	return g:Act(pl, action, payload)
end

local function carModel(g, pl)
	local folder = g.env.workspace:FindFirstChild("PlayerCars")
	return folder and folder:FindFirstChild("Car_" .. pl.UserId)
end

local function carCount(g, pl)
	local folder = g.env.workspace:FindFirstChild("PlayerCars")
	local n = 0
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		if m.Name == "Car_" .. pl.UserId then
			n += 1
		end
	end
	return n
end

local function horizontal(a, b)
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

-- Liegt der Punkt (waagerecht) auf einem Fahrbahnstück der Stadt?
local function onRoad(CS, pos)
	for _, part in ipairs(CS.RoadParts()) do
		local lp = part.CFrame:PointToObjectSpace(pos)
		if math.abs(lp.X) <= part.Size.X / 2 + 0.01 and math.abs(lp.Z) <= part.Size.Z / 2 + 0.01 then
			return part
		end
	end
	return nil
end

local function standAt(g, pl, pos)
	g:Activate()
	pl.Character:PivotTo(CFrame.new(pos))
	g:Flush()
end

local function leaveSeat(g, pl)
	g:Activate()
	local CityService = g:MiniServer("CityService")
	local hum = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		CityService.Unseat(hum)
	end
	g:Flush()
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
	for _, w in ipairs(g:Warnings()) do
		local text = tostring(w)
		T.check(not text:find("[Autos]", 1, true) and not text:find("[Minispiele]", 1, true), "Warnung: " .. text)
	end
end

-- Spieler mit getroffener Startwahl (kein Begrüßungs-Flitzer, keine Startwahl-Karte)
local function veteran(g, uid, level)
	g:SeedLevel(uid, level or 5, function(data)
		data.completed = 3
	end)
end

---------------------------------------------------------------- Fälle
return {
	{ "CarRules: Flitzer gehört jedem Profil (neu, 2.4.0, 3.0, idempotent), steht nicht in der Garage, unverkäuflich", function(T, H)
		local g = garage(H)
		local MR = g:MiniShared("MiniRules")
		local CR = g:MiniShared("CarRules")
		local CC = g:MiniShared("CarCatalog")
		local R = g:Rules()
		-- neues Profil
		local d = R.NewData(NOW)
		T.check(type(d.games) == "table" and type(d.games.flitzer) == "table", "neues Profil: games.flitzer")
		T.eq(d.games.flitzer.owned, true, "neues Profil besitzt den Flitzer")
		T.eq(#d.games.cars, 0, "Flitzer nicht in d.games.cars")
		T.eq(CR.OwnsStarter(d), true, "OwnsStarter")
		-- 2.4.0-Veteran ohne games
		local vet = { version = 2, money = 100, level = 8, completed = 4 }
		vet.games = MR.LoadGames(nil, vet, NOW)
		T.eq(vet.games.flitzer.owned, true, "2.4.0-Veteran besitzt den Flitzer")
		-- 3.0-Profil ohne flitzer-Feld, mit Autos
		local old = R.NewData(NOW)
		old.games.flitzer = nil
		old.games.cars = { { id = 3, model = "komet", paint = 2 }, { id = 7, model = "flitzer" } }
		old.games.carSerial = 7
		local loaded = MR.LoadGames(old.games, old, NOW)
		T.eq(loaded.flitzer.owned, true, "3.0-Profil: Flitzer gutgeschrieben")
		T.eq(#loaded.cars, 1, "Flitzer-Datensatz in cars wird verworfen (nie doppelt, nie handelbar)")
		T.eq(loaded.cars[1].model, "komet", "eigenes Auto bleibt")
		-- idempotent
		local again = MR.LoadGames(H.Copy(loaded), old, NOW)
		T.check(H.DeepEqual(CR.Load(again, old, NOW), CR.Load(loaded, old, NOW)), "CarRules.Load(Load(x)) == Load(x)")
		T.check(H.DeepEqual(again.flitzer, loaded.flitzer), "flitzer idempotent")
		-- Müll im flitzer-Feld
		local junk = CR.LoadStarter({ owned = false, fav = 0 / 0, due = "ja", intro = 5, extra = 1 })
		T.check(H.DeepEqual(junk, CR.StarterDefault()), "LoadStarter: Whitelist, NaN, owned immer true")
		local fav = CR.Load({ cars = { { id = 2, model = "nord" } }, carSerial = 2, flitzer = { fav = 2, intro = true, due = true } }, d, NOW)
		T.eq(fav.flitzer.fav, 2, "Lieblingsauto bleibt, solange es da ist")
		T.eq(fav.flitzer.due, false, "intro erledigt -> nicht mehr fällig")
		local gone = CR.Load({ cars = {}, flitzer = { fav = 9 } }, d, NOW)
		T.eq(gone.flitzer.fav, 0, "Lieblingsauto weg -> wieder der Flitzer")
		-- Katalog: kein Händler-/Auktions-/Shopmodell
		T.eq(CC.ModelById.flitzer, nil, "nicht in ModelById")
		for _, m in ipairs(CC.Models) do
			T.check(m.id ~= "flitzer", "nicht in Models")
		end
		for _, m in ipairs(CC.DealerModels) do
			T.check(m.id ~= "flitzer", "nicht beim Händler")
		end
		T.check(CC.Model("flitzer") ~= nil and CC.Model("flitzer").starter == true, "CarCatalog.Model kennt das Startauto")
		T.eq(CR.NormalizeCar({ id = 1, model = "flitzer" }), nil, "NormalizeCar lehnt den Flitzer ab")
		T.eq(CR.AddCar(d, { model = "flitzer" }), nil, "AddCar lehnt den Flitzer ab")
		T.eq(CR.GrantModel(d, "flitzer", NOW), nil, "GrantModel lehnt den Flitzer ab (Datensatz)")
		local okBuy, msgBuy = CR.Buy(d, "flitzer", NOW)
		T.check(not okBuy and type(msgBuy) == "string", "nicht kaufbar")
		-- unverkäuflich, nicht tunebar, nicht umlackierbar, Wert 0
		local car = CR.StarterCar(NOW)
		T.eq(car.id, CC.StarterCarId, "feste Id")
		T.eq(CR.SellValue(car), 0, "Verkaufswert 0")
		T.eq(CR.Value(car), 0, "Wert 0")
		local okSell, msg = CR.Sell(d, CC.StarterCarId)
		T.check(not okSell and msg == CR.Text.starterSell, "Sell: deutsche Absage")
		local okTune, msgTune = CR.Tune(d, CC.StarterCarId, "engine", 0)
		T.check(not okTune and msgTune == CR.Text.starterTune, "Tune: deutsche Absage")
		local okStyle, msgStyle = CR.Style(d, CC.StarterCarId, 1, 1, 0, false)
		T.check(not okStyle and msgStyle == CR.Text.starterStyle, "Style: deutsche Absage")
		T.eq(CR.Find(d, CC.StarterCarId), nil, "Find (Handel/Auktion) findet ihn nie")
		T.check(CR.OwnsStarter(d), "immer noch im Besitz")
		-- Lieblingsauto
		local fc, isStarter = CR.Favourite(d)
		T.check(isStarter and fc.model == "flitzer", "Standard-Lieblingsauto = Flitzer")
		local own = CR.GrantModel(d, "komet", NOW)
		T.check(CR.SetFavourite(d, own.id), "eigenes Auto als Favorit")
		T.eq(CR.Favourite(d).id, own.id, "Favorit gesetzt")
		local okMissing = CR.SetFavourite(d, 999)
		T.eq(okMissing, false, "fremde Id abgelehnt")
		own.locked = true
		T.eq(select(2, CR.Favourite(d)), true, "versteigertes Auto -> Flitzer")
		own.locked = false
		T.check(CR.SetFavourite(d, CC.StarterCarId), "Flitzer wieder Favorit")
		T.eq(d.games.flitzer.fav, 0, "fav = 0")
		local snap = CR.SnapshotFields(d)
		T.eq(snap.favCar, CC.StarterCarId, "Snapshot favCar")
		T.check(type(snap.starterCar) == "table" and snap.starterCar.name == "Flitzer" and snap.starterCar.sellValue == 0, "Snapshot starterCar")
		T.eq(#snap.cars, 1, "Snapshot cars ohne Flitzer")
	end },

	{ "CarCatalog: Flitzer flink und wendig, aber kein Pay-to-win (langsamer als die Mittelklasse, kein Nitro/Tuning)", function(T, H)
		local g = garage(H)
		local CR = g:MiniShared("CarRules")
		local CC = g:MiniShared("CarCatalog")
		local s = CR.Stats(CR.StarterCar(0))
		local komet = CR.Stats(CR.NewCar("komet", 0))
		local s2 = CR.Stats(CR.NewCar("komet_s2", 0))
		T.check(s.accel >= komet.accel, "beschleunigt mindestens wie der Komet C1 (" .. s.accel .. ")")
		T.check(s.steerAngle > komet.steerAngle, "wendiger als der Komet C1")
		T.check(s.topSpeed >= 85, "Spitze etwa Mittelklasse (" .. s.topSpeed .. " km/h)")
		for _, id in ipairs({ "komet_s2", "nord", "komet_urban", "atlas" }) do
			T.check(s.topSpeed < CR.Stats(CR.NewCar(id, 0)).topSpeed, "langsamer als " .. id)
		end
		T.check(s.rating < s2.rating, "Leistungsindex unter dem Komet S2")
		T.eq(s.nitro.level, 0, "kein Nitro")
		T.eq(CC.Starter.price, 0, "kostenlos")
		T.eq(CC.Starter.sellable, false, "unverkäuflich")
		-- Zeitfahren: Plausibilität nimmt das schnellste Katalogauto, der Flitzer verschiebt nichts
		local TR = g:MiniShared("TrackRules")
		local fastest = 0
		for _, m in ipairs(CC.Models) do
			fastest = math.max(fastest, TR.CarSpeed(CR.Stats(CR.NewCar(m.id, 0))))
		end
		T.check(TR.CarSpeed(s) < fastest, "Flitzer nicht das schnellste Auto")
	end },

	{ "VehicleFactory: Flitzer aus Parts (≈ 60 % des Kompaktwagens, 1 Sitz), fahrbar wie die anderen Autos, keine Assets", function(T, H)
		local g = garage(H)
		local VF = g:MiniServer("VehicleFactory")
		local CR = g:MiniShared("CarRules")
		local CC = g:MiniShared("CarCatalog")
		g:Activate()
		local car = CR.StarterCar(NOW)
		local model = VF.Build({
			body = "flitzer", car = car, stats = CR.Stats(car), name = "Car_1", ownerId = 1, ownerName = "A", carId = car.id,
			modelId = "flitzer", displayName = "Flitzer", cframe = CFrame.new(10, 0, 10), plate = "FLITZER",
		})
		T.check(model ~= nil, "gebaut")
		if not model then
			return
		end
		local compact = VF.Build({
			body = "compact", car = CR.NewCar("komet", 0), stats = CR.Stats(CR.NewCar("komet", 0)), name = "Car_2", ownerId = 2,
			carId = 1, modelId = "komet", cframe = CFrame.new(40, 0, 10),
		})
		local a, b = VF.Info(model).bounds, VF.Info(compact).bounds
		local lenRatio = (a.maxZ - a.minZ) / (b.maxZ - b.minZ)
		local widRatio = (a.maxX - a.minX) / (b.maxX - b.minX)
		T.check(lenRatio > 0.45 and lenRatio < 0.7, "Länge ≈ 60 % (" .. string.format("%.2f", lenRatio) .. ")")
		T.check(widRatio > 0.5 and widRatio < 0.8, "Breite ≈ 60–70 % (" .. string.format("%.2f", widRatio) .. ")")
		local seat = model:FindFirstChild("DriverSeat")
		T.check(seat ~= nil and seat:IsA("VehicleSeat"), "VehicleSeat")
		T.check(seat and seat:FindFirstChild("EnterPrompt") ~= nil, "Einsteigen-Prompt")
		local seats = 0
		for _, x in ipairs(model:GetDescendants()) do
			if x:IsA("VehicleSeat") or x:IsA("Seat") then
				seats += 1
			end
		end
		T.eq(seats, 1, "genau ein Sitz")
		T.eq(math.abs(seat.CFrame.Position.X - 10) < 0.01, true, "Sitz in der Mitte")
		T.check(model:FindFirstChild("Chassis") and model.Chassis.CanCollide, "Kollisionsrumpf")
		local info = VF.Info(model)
		for _, c in ipairs({ "FL", "FR", "RL", "RR" }) do
			T.check(info.wheels[c] ~= nil and info.axles[c] ~= nil, "Rad und Achse " .. c)
			T.check(info.wheels[c].Size.Y < 2.2, "kleines Rad " .. c)
		end
		T.check(info.steers.FL and info.steers.FR, "Lenkung vorn")
		T.check(#info.paint >= 3 and #info.rims == 4, "Lack- und Felgenteile erkannt")
		T.eq(model:GetAttribute("Body"), "flitzer", "Attribut Body")
		T.check(model:GetAttribute("MaxSpeed") > 0 and model:GetAttribute("Torque") > 0, "Fahrwerte gesetzt")
		T.eq(model:GetAttribute("DriveWheels"), "RL,RR", "Hinterradantrieb")
		T.check(info.phys.hullTop < CC.Physics.hullTop, "eigene, kleinere Rumpfmaße")
		local label = model:FindFirstChild("Label", true)
		T.check(label and label.Text == "FLITZER", "Kennzeichen")
		-- DriveClient erkennt Achsen/Lenkung (gleiches Namensschema)
		g:Activate()
		model.Parent = g.env.workspace
		local pl = g:Join(3101, { name = "Fahrer" })
		g:StartClient(pl, { run = false })
		local Drive = g:ClientModule(pl, "Mini.DriveClient")
		local collected = g:InClient(pl, function()
			return Drive.Collect(model)
		end)
		T.eq(#collected.motors, 4, "DriveClient: vier Achs-Motoren")
		T.eq(#collected.steers, 2, "DriveClient: zwei Lenk-Servos")
		local driven = 0
		for _, m in ipairs(collected.motors) do
			driven += m.driven and 1 or 0
		end
		T.eq(driven, 2, "zwei angetriebene Räder")
		-- keine Asset-IDs im Modell
		for _, x in ipairs(model:GetDescendants()) do
			for _, prop in ipairs({ "Texture", "TextureId", "MeshId", "Image" }) do
				local ok, v = pcall(function()
					return x[prop]
				end)
				T.check(not ok or type(v) ~= "string" or not v:find("rbxassetid", 1, true), "keine Asset-ID: " .. x.Name)
			end
		end
		-- Vorlage bleibt ohne Parent (ServerStorage unverändert)
		T.eq(VF.StarterTemplate().Parent, nil, "Vorlage nicht im Place")
		noErrors(T, g)
	end },

	{ "car_call: Flitzer an die nächste Fahrbahn neben dem Spieler, Spieler wird hineingesetzt, Abklingzeit 5 s", function(T, H)
		local g = garage(H, { before = function(g)
			veteran(g, 3201, 5)
		end })
		local CS = g:MiniServer("CarService")
		local CC = g:MiniShared("CarCatalog")
		local GC = g:MiniShared("GameConfig")
		local pl, d = join(g, 3201, "Rufer")
		T.check(#CS.RoadParts() > 10, "Fahrbahnstücke der Stadt gefunden (" .. #CS.RoadParts() .. ")")
		-- auf dem Gehweg südlich der Spielermeile West
		local stand = Vector3.new(-300, 3, 30)
		standAt(g, pl, stand)
		T.eq(act(g, pl, "car_call"), "ok", "car_call über Remotes.Command")
		local m = carModel(g, pl)
		T.check(m ~= nil, "Auto unter workspace.PlayerCars")
		if not m then
			return
		end
		T.eq(m:GetAttribute("Model"), "flitzer", "der Flitzer kommt")
		T.eq(m:GetAttribute("Starter"), true, "Attribut Starter")
		T.eq(m:GetAttribute("CarId"), CC.StarterCarId, "CarId des Flitzers")
		local pos = m:GetPivot().Position
		T.check(horizontal(pos, stand) < 40, "neben dem Spieler (" .. string.format("%.1f", horizontal(pos, stand)) .. " Studs)")
		T.check(onRoad(CS, pos) ~= nil, "steht auf einer Fahrbahn")
		T.check(math.abs(pos.Z) <= 13, "auf der Spielermeile (Z " .. string.format("%.1f", pos.Z) .. ")")
		local look = m:GetPivot().LookVector
		T.check(math.abs(look.Y) < 0.01 and math.abs(math.abs(look.X) - 1) < 0.01, "Nase entlang der Straße")
		-- Spieler wurde zum Sitz gebracht (seat:Sit setzt ihn in Roblox hinein)
		local root = g:Root(pl)
		T.check(root and horizontal(root.Position, m.DriverSeat.Position) < 6, "Figur an der Fahrertür/im Sitz")
		local spawned = g:Notices(pl, "car_spawned")
		T.check(#spawned == 1 and spawned[1].at == "call" and spawned[1].starter == true, "car_spawned at=call")
		T.check(g:HasToast(pl, "Flitzer ist da"), "Toast")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and snap.spawnedStarter == true and snap.spawnedId == CC.StarterCarId, "Snapshot: Flitzer draußen")
		T.eq(snap and snap.spawnedCar, false, "spawnedCar nur für Garagenautos (DealerUI.IsOut)")
		T.check(snap and snap.favCar == CC.StarterCarId and type(snap.starterCar) == "table", "Snapshot: favCar/starterCar")
		-- Abklingzeit: sofort nochmal -> Hinweis, kein zweites Auto
		leaveSeat(g, pl)
		g:Advance(1.2)
		local mark = g:Mark()
		act(g, pl, "car_call")
		T.check(g:HasToast(pl, "gleich wieder rufbar", mark), "Abklingzeit-Hinweis")
		T.eq(carModel(g, pl), m, "dasselbe Auto")
		-- nach 5 s: woanders rufen -> altes Auto weg, neues beim Spieler
		local stand2 = Vector3.new(200, 3, -30)
		standAt(g, pl, stand2)
		g:Advance(GC.StarterCar.CallCooldown)
		T.eq(act(g, pl, "car_call"), "ok", "zweiter Ruf")
		local m2 = carModel(g, pl)
		T.check(m2 ~= nil and m2 ~= m and m.Parent == nil, "altes Auto abgebaut, neues gebaut")
		T.eq(carCount(g, pl), 1, "höchstens ein eigenes Auto")
		T.check(m2 and horizontal(m2:GetPivot().Position, stand2) < 40, "neues Auto beim Spieler")
		T.check(m2 and onRoad(CS, m2:GetPivot().Position) ~= nil, "wieder auf der Fahrbahn")
		-- im eigenen Auto sitzend: kein Ruf
		g:Activate()
		local hum = pl.Character:FindFirstChildOfClass("Humanoid")
		m2.DriverSeat.Occupant = hum
		g:Flush()
		g:Advance(GC.StarterCar.CallCooldown + 0.1)
		mark = g:Mark()
		act(g, pl, "car_call")
		T.check(g:HasToast(pl, "sitzt schon", mark), "sitzt schon im Auto")
		T.eq(carModel(g, pl), m2, "Auto bleibt")
		-- Verkauf des Flitzers über die echte Aktion: Absage, Auto bleibt, Geld gleich
		local money = d.money
		mark = g:Mark()
		act(g, pl, "mini_car_sell", { id = CC.StarterCarId })
		T.check(g:HasToast(pl, "nicht verkaufen", mark), "Verkauf abgelehnt (deutsch)")
		T.eq(d.money, money, "kein Geld")
		T.eq(carModel(g, pl), m2, "Flitzer bleibt draußen")
		-- Nitro im Flitzer: freundlicher Hinweis
		mark = g:Mark()
		act(g, pl, "mini_car_nitro")
		T.check(g:HasToast(pl, "kein Nitro", mark), "Nitro-Hinweis für den Flitzer")
		noErrors(T, g)
	end },

	{ "car_call: Lieblingsauto aus der Garage (car_favourite), am Werkstatt-Parkplatz, Fahrbahn frei von Hindernissen", function(T, H)
		local g = garage(H, { before = function(g)
			veteran(g, 3301, 10)
		end })
		local CS = g:MiniServer("CarService")
		local CC = g:MiniShared("CarCatalog")
		local GC = g:MiniShared("GameConfig")
		local pl, d = join(g, 3301, "Favorit")
		d.money = 100000
		T.eq(act(g, pl, "mini_car_buy", { model = "komet" }), "ok", "Komet gekauft")
		local own = d.games.cars[1]
		T.check(own ~= nil, "eigenes Auto")
		T.eq(act(g, pl, "car_favourite", { id = own.id }), "ok", "car_favourite")
		T.eq(d.games.flitzer.fav, own.id, "Favorit gespeichert")
		T.check(g:HasToast(pl, "Lieblingsauto"), "Toast Lieblingsauto")
		standAt(g, pl, Vector3.new(-300, 3, 30))
		T.eq(act(g, pl, "car_call"), "ok", "car_call")
		local m = carModel(g, pl)
		T.check(m and m:GetAttribute("Model") == "komet", "Lieblingsauto kommt")
		T.eq(d.games.activeCar, own.id, "aktives Auto")
		-- unbekannte Id: Absage, Favorit bleibt
		local mark = g:Mark()
		g:Advance(0.5)
		act(g, pl, "car_favourite", { id = 4242 })
		T.check(g:HasToast(pl, "nicht gefunden", mark), "fremde Id abgelehnt")
		T.eq(d.games.flitzer.fav, own.id, "Favorit unverändert")
		-- zurück zum Flitzer
		g:Advance(0.5)
		T.eq(act(g, pl, "car_favourite", { id = CC.StarterCarId }), "ok", "Flitzer als Favorit")
		T.eq(d.games.flitzer.fav, 0, "fav = 0")
		-- in der eigenen Werkstatt: Parkplatz (CarSpawn) liegt näher als die Straße
		local plot = g:Plot(pl)
		local sp = plot and plot:FindFirstChild("CarSpawn", true)
		T.check(sp ~= nil, "Werkstatt-Parkplatz CarSpawn")
		if sp then
			leaveSeat(g, pl)
			standAt(g, pl, sp.Position + Vector3.new(3, 3, 0))
			g:Advance(GC.StarterCar.CallCooldown + 0.1)
			T.eq(act(g, pl, "car_call"), "ok", "Ruf in der Werkstatt")
			local m2 = carModel(g, pl)
			T.check(m2 and horizontal(m2:GetPivot().Position, sp.Position) < CC.Physics.spawnSpacing * 2 + 1, "am Werkstatt-Parkplatz")
			T.eq(m2 and m2:GetAttribute("Model"), "flitzer", "Flitzer")
		end
		-- belegte Fahrbahnstelle (fremdes Auto) wird übersprungen
		g:Activate()
		local stand = Vector3.new(-250, 3, 30)
		local spot = CS.RoadSpot(CS.States[pl], stand, Vector3.new(1, 0, 0))
		T.check(spot ~= nil, "Fahrbahnstelle gefunden")
		if spot then
			local blocker = Instance.new("Model")
			blocker.Name = "Car_99999"
			local part = Instance.new("Part")
			part.Size = Vector3.new(4, 4, 8)
			part.CFrame = spot
			part.Parent = blocker
			blocker.PrimaryPart = part
			blocker.Parent = CS.CarsFolder()
			local spot2 = CS.RoadSpot(CS.States[pl], stand, Vector3.new(1, 0, 0))
			T.check(spot2 ~= nil and horizontal(spot2.Position, spot.Position) >= 8.9, "belegte Stelle übersprungen")
			blocker:Destroy()
		end
		noErrors(T, g)
	end },

	{ "car_call: nicht in Lobby/Tycoon, nicht während Probefahrt oder Zeitfahren, ohne Figur kein Ruf", function(T, H)
		-- all-Place: neuer Spieler beginnt in der Lobby
		local g = garage(H, { placeKind = "all" })
		local pl = join(g, 3401, "Lobby")
		local ms = g:MiniState(pl)
		T.eq(ms.p.mode, "lobby", "in der Lobby")
		act(g, pl, "car_call")
		T.check(g:HasToast(pl, "nur in der Open World"), "Lobby: Hinweis")
		T.eq(carModel(g, pl), nil, "Lobby: kein Auto")
		ms.p.mode = "tycoon"
		g:Advance(1.1)
		local mark = g:Mark()
		act(g, pl, "car_call")
		T.check(g:HasToast(pl, "nur in der Open World", mark), "Tycoon: Hinweis")
		T.eq(carModel(g, pl), nil, "Tycoon: kein Auto")
		noErrors(T, g, "Lobby/Tycoon")

		-- Open World: Probefahrt / Zeitfahren sperren
		local g2 = garage(H, { before = function(g2)
			veteran(g2, 3402, 12)
		end })
		local p2, d2 = join(g2, 3402, "Probe")
		d2.money = 500000
		T.eq(act(g2, p2, "mini_car_testdrive", { model = "komet" }), "ok", "Probefahrt")
		T.check(g2:Find("Workspace.PlayerCars.Probe_3402") ~= nil, "Probewagen draußen")
		mark = g2:Mark()
		act(g2, p2, "car_call")
		T.check(g2:HasToast(p2, "Probefahrt", mark), "während der Probefahrt gesperrt")
		T.eq(carModel(g2, p2), nil, "kein Flitzer")
		g2:Advance(61)
		T.eq(act(g2, p2, "mini_car_buy", { model = "komet" }), "ok", "Komet gekauft")
		g2:Advance(3.1)
		T.eq(act(g2, p2, "mini_track_start"), "ok", "Zeitfahren")
		local CS = g2:MiniServer("CarService")
		T.check(CS.States[p2] and CS.States[p2].run ~= nil, "Lauf aktiv")
		mark = g2:Mark()
		act(g2, p2, "car_call")
		T.check(g2:HasToast(p2, "Zeitfahren", mark), "während des Zeitfahrens gesperrt")
		T.check(carModel(g2, p2) and carModel(g2, p2):GetAttribute("Model") == "komet", "Rennauto bleibt")
		noErrors(T, g2, "Probefahrt/Zeitfahren")

		-- Zeitfahren aus dem Flitzer heraus: läuft mit dem eigenen aktiven Auto, nie mit dem Flitzer
		local g3 = garage(H, { before = function(g3)
			veteran(g3, 3403, 12)
		end })
		local p3, d3 = join(g3, 3403, "Strecke")
		standAt(g3, p3, Vector3.new(-300, 3, 30))
		T.eq(act(g3, p3, "car_call"), "ok", "Flitzer gerufen")
		leaveSeat(g3, p3)
		g3:Advance(3.1)
		mark = g3:Mark()
		act(g3, p3, "mini_track_start")
		T.check(g3:HasToast(p3, "außer Konkurrenz", mark), "Flitzer fährt keine Zeitfahren")
		local CS3 = g3:MiniServer("CarService")
		T.check(CS3.States[p3].run == nil, "kein Lauf mit dem Flitzer")
		d3.money = 100000
		g3:Advance(0.5)
		act(g3, p3, "mini_car_buy", { model = "komet" })
		g3:Advance(3.1)
		T.eq(act(g3, p3, "mini_track_start"), "ok", "Zeitfahren")
		T.check(CS3.States[p3].run ~= nil and carModel(g3, p3):GetAttribute("Model") == "komet", "Lauf mit dem eigenen Auto")
		noErrors(T, g3, "Zeitfahren")
	end },

	{ "Begrüßung: nach der Startwahl steht einmal der Flitzer neben dem Spieler (nicht eingesetzt), Toast, nie doppelt", function(T, H)
		local g = garage(H)
		local GC = g:MiniShared("GameConfig")
		local pl, d = join(g, 3501, "Neu")
		T.eq(d.games.meta.startPath, "", "Startwahl offen")
		g:Advance(3)
		T.eq(carModel(g, pl), nil, "vor der Wahl kein Auto")
		T.eq(act(g, pl, "start_choose", { path = "autohaus" }), "ok", "start_choose")
		g:Advance(GC.StarterCar.IntroDelay + 1.1)
		local m = carModel(g, pl)
		T.check(m ~= nil and m:GetAttribute("Model") == "flitzer", "Begrüßungs-Flitzer steht da")
		if m then
			T.check(horizontal(m:GetPivot().Position, g:Root(pl).Position) < 60, "neben dem Spieler")
			T.check(m.DriverSeat.Occupant == nil, "nicht eingesetzt")
		end
		T.check(g:HasToast(pl, GC.StarterCar.Text.intro), "Toast „Dein Flitzer! …“")
		local intro = g:Notices(pl, "car_spawned")
		T.check(#intro == 1 and intro[1].at == "intro", "car_spawned at=intro")
		T.eq(d.games.flitzer.intro, true, "erledigt gespeichert")
		-- abbauen und warten: kommt nicht wieder
		act(g, pl, "mini_car_despawn")
		g:Advance(12)
		T.eq(carModel(g, pl), nil, "kein zweiter Begrüßungs-Flitzer")
		-- Speichern/Laden: erledigt bleibt erledigt
		g:Leave(pl)
		g:Advance(1)
		local rec = g:Record(3501)
		T.check(rec and rec.data.games.flitzer and rec.data.games.flitzer.intro == true, "intro gespeichert")
		noErrors(T, g)

		-- Veteran (Startweg schon gewählt): keine Begrüßung
		local g2 = garage(H, { before = function(g2)
			veteran(g2, 3502, 5)
		end })
		local p2, d2 = join(g2, 3502, "Alt")
		T.check(d2.games.meta.startPath ~= "", "Veteran hat einen Startweg")
		g2:Advance(10)
		T.eq(carModel(g2, p2), nil, "Veteran: kein Auto ungefragt")
		T.eq(#g2:Notices(p2, "car_spawned"), 0, "keine car_spawned")
		T.eq(d2.games.flitzer.owned, true, "besitzt den Flitzer trotzdem")
		noErrors(T, g2, "Veteran")
	end },

	{ "DriveClient: Taste G sendet car_call nur in der Open World, nicht beim Tippen, bei offener UI oder im Auto", function(T, H)
		local g = garage(H)
		local pl = g:Join(3601, { name = "Taste" })
		g:Advance(0.5)
		g:StartClient(pl, { run = false })
		local Drive = g:ClientModule(pl, "Mini.DriveClient")
		local sent, toasts = {}, {}
		local busy = false
		local rec = {
			Send = function(action, payload)
				table.insert(sent, { action = action, payload = payload or {} })
				return #sent
			end,
		}
		g:InClient(pl, function()
			Drive.Start({
				Remote = rec,
				Toast = function(text)
					table.insert(toasts, text)
				end,
				IsGarageBusy = function()
					return busy
				end,
			})
		end)
		local function count()
			local n = 0
			for _, s in ipairs(sent) do
				if s.action == "car_call" then
					n += 1
					T.eq(next(s.payload), nil, "car_call ohne Felder (keine Beträge)")
				end
			end
			return n
		end
		g:InClient(pl, function()
			Drive.OnSnapshot({ mode = "openworld", start = { pending = false } })
		end)
		g:Key(pl, Enum.KeyCode.G)
		g:Advance(0.1)
		T.eq(count(), 1, "G sendet car_call")
		g:Key(pl, Enum.KeyCode.G)
		T.eq(count(), 1, "höchstens 1× pro Sekunde")
		g:Advance(1.1)
		-- andere Taste
		g:Key(pl, Enum.KeyCode.F)
		T.eq(count(), 1, "nur Taste G")
		-- beim Tippen (TextBox fokussiert)
		g:Activate()
		g.env.focusedTextBox = {}
		g:Key(pl, Enum.KeyCode.G)
		g.env.focusedTextBox = nil
		T.eq(count(), 1, "nicht beim Tippen")
		-- Tablet/Panel/QTE offen
		busy = true
		g:Key(pl, Enum.KeyCode.G)
		busy = false
		T.eq(count(), 1, "nicht bei offener Oberfläche")
		-- Startwahl offen
		g:InClient(pl, function()
			Drive.OnSnapshot({ mode = "openworld", start = { pending = true } })
		end)
		g:Key(pl, Enum.KeyCode.G)
		T.eq(count(), 1, "nicht während der Startwahl")
		-- Lobby/Tycoon: Hinweis statt Absicht
		for _, mode in ipairs({ "lobby", "tycoon" }) do
			g:InClient(pl, function()
				Drive.OnSnapshot({ mode = mode, start = { pending = false } })
			end)
			g:Advance(1.1)
			local before = #toasts
			g:Key(pl, Enum.KeyCode.G)
			T.eq(count(), 1, mode .. ": nichts gesendet")
			T.check(#toasts == before + 1 and toasts[#toasts]:find("Open World", 1, true) ~= nil, mode .. ": Hinweis")
		end
		-- zurück in der Open World
		g:InClient(pl, function()
			Drive.OnSnapshot({ mode = "openworld", start = { pending = false } })
		end)
		g:Advance(1.1)
		T.eq(g:InClient(pl, function()
			return Drive.CallCar()
		end), true, "CallCar sendet")
		T.eq(count(), 2, "zweites car_call")
		T.eq(Drive.CallKey, Enum.KeyCode.G, "Taste G")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "Handy: App „Auto rufen“ (gezeichnetes Auto) sendet car_call, Garage listet Flitzer + Autos, Favorit -> car_favourite", function(T, H)
		local g = garage(H)
		local pl = g:Join(3701, { name = "Handy" })
		g:Advance(0.5)
		g:StartClient(pl, { run = false })
		g:Advance(1)
		local Phone = g:ClientModule(pl, "Mini.PhoneUI")
		local Hit = H.Load("tests/lib/gui_hit.lua")
		local sent = {}
		local rec = {
			Send = function(action, payload)
				payload = payload or {}
				for k, v in pairs(payload) do
					T.check(type(v) ~= "table" and k ~= "amount" and k ~= "price", action .. ": flaches Feld ohne Beträge")
				end
				table.insert(sent, { action = action, payload = payload })
				return #sent
			end,
		}
		function rec.Last(action)
			for i = #sent, 1, -1 do
				if sent[i].action == action then
					return sent[i].payload
				end
			end
			return nil
		end
		local snap = {
			mode = "openworld", credits = 100, level = 5, meta = { single = false, passive = false, beginner = false },
			favCar = -1,
			starterCar = { id = -1, name = "Flitzer", model = "flitzer", starter = true, topSpeed = 88 },
			cars = {
				{ id = 4, name = "Komet C1", model = "komet", locked = false, stats = { topSpeed = 78 } },
				{ id = 9, name = "Nord R4", model = "nord", locked = true, stats = { topSpeed = 92 } },
			},
		}
		local toasts = {}
		g:InClient(pl, function()
			Phone.Start({
				Remote = rec,
				Snapshot = function()
					return snap
				end,
				Toast = function(t)
					table.insert(toasts, t)
				end,
				IsBlocked = function()
					return false
				end,
				IsTabletOpen = function()
					return false
				end,
				IsPanelOpen = function()
					return false
				end,
			})
		end)
		g:Advance(0.5)
		local gui = pl.PlayerGui:FindFirstChild("Handy")
		local function visibleNamed(name)
			for _, x in ipairs(gui:GetDescendants()) do
				if x.Name == name and Hit.Visible(x) then
					return x
				end
			end
			return nil
		end
		local function click(obj, label)
			Hit.Click(T, g, pl, obj, { label = label })
			g:Advance(0.3)
		end
		local found = false
		for _, a in ipairs(Phone.Apps) do
			if a.key == "auto" then
				found = a.title == "Auto rufen"
			end
		end
		T.check(found, "App „Auto rufen“ in PhoneUI.Apps")
		g:Key(pl, Enum.KeyCode.P)
		g:Advance(0.5)
		T.eq(Phone.IsOpen(), true, "Handy offen")
		local icon = visibleNamed("App_auto")
		T.check(icon ~= nil, "Symbol auf dem Home-Bildschirm")
		local tile = icon and icon:FindFirstChild("Tile")
		T.check(tile and tile:FindFirstChild("Body") and tile:FindFirstChild("Wheel1") and tile:FindFirstChild("Wheel2"), "Auto aus Frames gezeichnet")
		click(icon, "App Auto rufen")
		T.eq(Phone.App(), "auto", "App offen")
		-- Garage: Flitzer zuerst, dann die eigenen Autos; Flitzer ist Favorit
		T.check(visibleNamed("Car_-1") ~= nil and visibleNamed("Car_4") ~= nil and visibleNamed("Car_9") ~= nil, "Garage listet Flitzer + Autos")
		local favStarter = visibleNamed("Fav_-1")
		T.check(favStarter and favStarter:GetAttribute("Favourite") == true, "Flitzer als Favorit markiert")
		-- versteigertes Auto: kein Favorit möglich
		click(visibleNamed("Fav_9"), "Favorit Nord (in Auktion)")
		T.eq(rec.Last("car_favourite"), nil, "Auto in Auktion: nichts gesendet")
		-- Favorit wählen
		click(visibleNamed("Fav_4"), "Favorit Komet")
		local fav = rec.Last("car_favourite")
		T.check(fav and fav.id == 4, "car_favourite {id = 4}")
		T.eq(Phone.Favourite(), 4, "Auswahl sofort sichtbar")
		g:Advance(0.5)
		T.check(visibleNamed("Fav_4") and visibleNamed("Fav_4"):GetAttribute("Favourite") == true, "Komet markiert")
		snap.favCar = 4
		g:Advance(0.5)
		-- Auto rufen
		local callButton = visibleNamed("CallCar")
		T.check(callButton ~= nil, "Knopf „Auto rufen“")
		local _, _, _, bh = Hit.Rect(pl, callButton)
		T.check(bh >= 44 - 0.01, "Knopf ≥ 44 px hoch")
		click(callButton, "Auto rufen")
		local call = rec.Last("car_call")
		T.check(call ~= nil and next(call) == nil, "car_call {} gesendet")
		g:Advance(0.5)
		T.eq(Phone.IsOpen(), false, "Handy schließt (man sieht das Auto kommen)")
		-- außerhalb der Open World: Hinweis statt Absicht
		snap.mode = "lobby"
		g:InClient(pl, function()
			Phone.Open({ app = "auto" })
		end)
		g:Advance(0.5)
		local n = #sent
		click(visibleNamed("CallCar"), "Auto rufen in der Lobby")
		T.eq(#sent, n, "Lobby: nichts gesendet")
		T.check(toasts[#toasts] and toasts[#toasts]:find("Open World", 1, true) ~= nil, "Lobby: Hinweis")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "Verkabelung: ohne MiniNet-Eintrag registriert CarService car_call nicht (Server startet trotzdem)", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local Mini = g:Mini()
		local net = g:MiniShared("MiniNet")
		if net.Actions.car_call then
			T.check(Mini.Handlers.car_call ~= nil, "verkabelt: Handler vorhanden")
			T.check(Mini.Handlers.car_favourite ~= nil or net.Actions.car_favourite == nil, "verkabelt: car_favourite")
		else
			T.eq(Mini.Handlers.car_call, nil, "unverkabelt: kein Handler")
		end
		local pl = g:Join(3801, { name = "Start" })
		g:Advance(1)
		T.check(g:MiniState(pl) ~= nil, "Server läuft")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },
}
