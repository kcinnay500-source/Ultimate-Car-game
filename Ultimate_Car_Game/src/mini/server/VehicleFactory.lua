-- VehicleFactory: baut aus ServerStorage.CarTemplates.<body> ein fahrbares Roblox-Fahrzeug (Server).
-- Die Vorlagen bleiben unverändert (2.4.0-Aufträge und PreviewCars brauchen sie); gebaut wird ein Klon.
--
-- Aufbau des Modells (Name z. B. "Car_<UserId>", PrimaryPart = Root der Vorlage, Nase zeigt nach -Z):
--   Chassis            unsichtbarer Kollisionsrumpf mit der Fahrzeugmasse (CustomPhysicalProperties.Density),
--                      Wurzel der Baugruppe (RootPriority 10). Das sichtbare Bodenblech der Vorlage heißt "Underbody".
--   alle Karosserieteile per WeldConstraint am Chassis, Massless, CanCollide/CanTouch false (nur Optik)
--   Wheel_FL/FR/RL/RR  unsichtbare Zylinder-Räder (Reibung = Grip), Reifen/Felge/Nabe/Speichen/Bremse daran geschweißt
--   Knuckle_FL/FR      Achsschenkel (Lenkung) vorne
--   DriverSeat         VehicleSeat (unsichtbar, auf Höhe der Sitzfläche) mit ProximityPrompt "EnterPrompt"
--   Underglow          Neon-Platte unter dem Auto mit PointLight "UnderglowLight" (aus bei glow = 0)
--   Drive (Folder)     Axle_XX   CylindricalConstraint: Federweg senkrecht (Limits ± travel), Drehung um die Radachse
--                                 (InclinationAngle 90), Winkel-Motor (AngularActuatorType Motor);
--                                 positive AngularVelocity = vorwärts
--                      Steer_FL/FR HingeConstraint Servo (Achse senkrecht nach unten): positiver TargetAngle = rechts
--                      Spring_XX SpringConstraint Chassis -> Radmitte (Federrate/Dämpfung aus den Fahrwerten)
--                      NoCollide_XX NoCollisionConstraint Rad <-> Chassis
--   Attribute (für DriveClient): siehe VehicleFactory.ApplyStats
-- Keine Asset-IDs: Partikel nutzen die eingebaute Standardtextur.
local ServerStorage = game:GetService("ServerStorage")
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local CarCatalog = require(MiniShared:WaitForChild("CarCatalog"))

local VehicleFactory = {}

local registry = setmetatable({}, { __mode = "k" }) -- [Model] = info

VehicleFactory.Corners = { "FL", "FR", "RL", "RR" }
local CORNERS = VehicleFactory.Corners
local CORNER_SET = { FL = true, FR = true, RL = true, RR = true }
local FRONT = { FL = true, FR = true }
local PAINT = { Paint = true, Hood = true, Mirror = true }
local SPOILER = { Spoiler = true, SpoilerMount = true, RoofSpoiler = true, RearWingEnd = true }
local TRIM = Color3.fromRGB(22, 26, 31)

-- Ausrichtung der Attachments im Fahrzeug-Koordinatensystem (X rechts, Y oben, -Z vorn):
-- Achse: X zeigt nach oben (Federweg), Y nach links (Drehachse bei InclinationAngle 90), Z nach hinten.
-- Drehung um "links" mit positivem Winkel rollt das Rad vorwärts (Auflagepunkt bewegt sich nach hinten).
local AXLE_ROT = CFrame.fromMatrix(Vector3.new(), Vector3.new(0, 1, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1))
-- Lenkung: X zeigt nach unten (Scharnierachse), Y nach vorn. Positiver Winkel um "unten" = Rechtseinschlag.
local STEER_ROT = CFrame.fromMatrix(Vector3.new(), Vector3.new(0, -1, 0), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0))

local function phys()
	return CarCatalog.Physics
end

function VehicleFactory.Template(body)
	local folder = ServerStorage:FindFirstChild("CarTemplates")
	local t = folder and type(body) == "string" and folder:FindFirstChild(body)
	if t and t:IsA("Model") then
		return t
	end
	return nil
end

local function cornerOf(name)
	local c = string.match(name, "^Wheel(%u%u)")
	if c and CORNER_SET[c] then
		return c
	end
	c = string.match(name, "^Brake(%u%u)$")
	if c and CORNER_SET[c] then
		return c
	end
	return nil
end

-- Halbe Ausdehnung eines gedrehten Quaders entlang der Achsen von `frame`
local function extents(frame, part)
	local lc = frame:ToObjectSpace(part.CFrame)
	local s = part.Size / 2
	local r, u, l = lc.RightVector, lc.UpVector, lc.LookVector
	local ex = math.abs(r.X) * s.X + math.abs(u.X) * s.Y + math.abs(l.X) * s.Z
	local ey = math.abs(r.Y) * s.X + math.abs(u.Y) * s.Y + math.abs(l.Y) * s.Z
	local ez = math.abs(r.Z) * s.X + math.abs(u.Z) * s.Y + math.abs(l.Z) * s.Z
	return lc.Position, Vector3.new(ex, ey, ez)
end

local function weld(part0, part1)
	local w = Instance.new("WeldConstraint")
	w.Name = "Weld"
	w.Part0 = part0
	w.Part1 = part1
	w.Parent = part1
	return w
end

local function attach(part, name, world)
	local a = Instance.new("Attachment")
	a.Name = name
	a.CFrame = part.CFrame:ToObjectSpace(world)
	a.Parent = part
	return a
end

local function newPart(name, size, cf, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function decorate(part)
	part.Anchored = false
	part.CanCollide = false
	part.CanTouch = false
	part.Massless = true
end

---------------------------------------------------------------- Bauen
-- opts = { body, car (paint, rims, glow, spoiler), stats = CarRules.Stats(car), name, ownerId, ownerName,
--          carId, modelId, displayName, testdrive, cframe (Ziel des Root, Boden unter den Reifen), plate, shine }
-- Rückgabe: model (Parent = nil, alle Teile unverankert) | nil, Fehlertext
function VehicleFactory.Build(opts)
	local template = VehicleFactory.Template(opts.body)
	if not template then
		return nil, "Fahrzeugvorlage fehlt: " .. tostring(opts.body)
	end
	local P = phys()
	local model = template:Clone()
	model.Name = opts.name or "Car"
	local root = model.PrimaryPart or model:FindFirstChild("Root")
	if not root or not root:IsA("BasePart") then
		model:Destroy()
		return nil, "Fahrzeugvorlage ohne Root: " .. tostring(opts.body)
	end
	model.PrimaryPart = root
	if opts.cframe then
		model:PivotTo(opts.cframe)
	end
	local rootCF = root.CFrame

	local info = {
		model = model, root = root, paint = {}, rims = {}, spoilers = {}, spoilerAlpha = {}, reflect = {},
		wheelParts = { FL = {}, FR = {}, RL = {}, RR = {} }, tires = {}, wheels = {}, knuckles = {},
		axles = {}, steers = {}, springs = {}, body = {},
	}
	local minX, maxX, minY, maxY, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
	local driverSeat, driverX = nil, math.huge

	local parts = {}
	for _, x in ipairs(model:GetDescendants()) do
		if x:IsA("BasePart") then
			table.insert(parts, x)
		end
	end
	for _, part in ipairs(parts) do
		if part == root or not part:IsDescendantOf(model) then
			continue
		end
		local name = part.Name
		local corner = cornerOf(name)
		if part.Transparency >= 0.99 then
			part:Destroy() -- unsichtbare Arbeitspunkte der Werkstatt (DiagnosticPoint, EnginePoint, ...)
		elseif corner then
			table.insert(info.wheelParts[corner], part)
			if name == "Wheel" .. corner .. "Tire" then
				info.tires[corner] = part
			elseif string.sub(name, -3) == "Rim" or string.sub(name, -5) == "Spoke" then
				table.insert(info.rims, part)
			end
		else
			table.insert(info.body, part)
			local c, e = extents(rootCF, part)
			minX, maxX = math.min(minX, c.X - e.X), math.max(maxX, c.X + e.X)
			minY, maxY = math.min(minY, c.Y - e.Y), math.max(maxY, c.Y + e.Y)
			minZ, maxZ = math.min(minZ, c.Z - e.Z), math.max(maxZ, c.Z + e.Z)
			if PAINT[name] then
				table.insert(info.paint, part)
				info.reflect[part] = part.Reflectance
			end
			if SPOILER[name] then
				table.insert(info.spoilers, part)
				info.spoilerAlpha[part] = part.Transparency
			end
			if name == "Seat" and c.X < driverX then
				driverSeat, driverX = part, c.X -- Linkslenker: Fahrersitz links (-X)
			elseif name == "Chassis" then
				part.Name = "Underbody"
			elseif name == "Plate" then
				local label = part:FindFirstChild("Label", true)
				if label and label:IsA("TextLabel") and opts.plate then
					label.Text = opts.plate
				end
			end
		end
	end
	if minX == math.huge then
		minX, maxX, minY, maxY, minZ, maxZ = -3.9, 3.9, 0, 5, -7, 7
	end
	info.bounds = { minX = minX, maxX = maxX, minY = minY, maxY = maxY, minZ = minZ, maxZ = maxZ }

	-- Kollisionsrumpf mit der Masse
	local halfW = math.min(P.hullHalfWidth, (maxX - minX) / 2)
	local z0, z1 = minZ + 0.2, maxZ - 0.2
	local chassis = newPart("Chassis", Vector3.new(halfW * 2, P.hullTop - P.hullBottom, z1 - z0),
		rootCF * CFrame.new(0, (P.hullTop + P.hullBottom) / 2, (z0 + z1) / 2), model)
	chassis.CanCollide = true
	chassis.CanTouch = true
	chassis.CanQuery = true
	chassis.Massless = false
	chassis.RootPriority = 10
	info.chassis = chassis

	root.Anchored = false
	root.CanCollide = false
	root.CanTouch = false
	root.Massless = true
	weld(chassis, root)
	for _, part in ipairs(info.body) do
		decorate(part)
		weld(chassis, part)
	end

	-- Fahrersitz (VehicleSeat), dazu der Einstiegs-Prompt
	local seatPos = driverSeat and rootCF:ToObjectSpace(driverSeat.CFrame).Position or Vector3.new(-1.7, 3.5, 1.1)
	local seat = Instance.new("VehicleSeat")
	seat.Name = "DriverSeat"
	seat.Size = Vector3.new(2, 0.4, 1.6)
	seat.CFrame = rootCF * CFrame.new(seatPos.X, P.seatTop - 0.2, seatPos.Z)
	seat.Transparency = 1
	seat.Anchored = false
	seat.CanCollide = false
	seat.CanTouch = true
	seat.CanQuery = false
	seat.CastShadow = false
	seat.Massless = true
	seat.HeadsUpDisplay = false
	seat.Disabled = false
	seat.TurnSpeed = 1
	seat.Parent = model
	weld(chassis, seat)
	info.seat = seat
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "EnterPrompt"
	prompt.ActionText = "Einsteigen"
	prompt.ObjectText = opts.displayName or ""
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = seat
	info.prompt = prompt

	-- Räder, Achsschenkel, Federung, Antrieb, Lenkung
	local drive = Instance.new("Folder")
	drive.Name = "Drive"
	drive.Parent = model
	info.drive = drive
	local radius = 0
	for _, c in ipairs(CORNERS) do
		local tire = info.tires[c]
		local center, r, w
		if tire then
			center = rootCF:ToObjectSpace(tire.CFrame).Position
			r = math.max(tire.Size.Y, tire.Size.Z) / 2
			w = tire.Size.X
		else
			local left = c == "FL" or c == "RL"
			center = Vector3.new(left and -4.02 or 4.02, 1.3, FRONT[c] and -4.5 or math.max(2, maxZ - 3.5))
			r, w = 1.3, 1
		end
		radius += r / 4
		local hub = rootCF * CFrame.new(center)
		local wheel = newPart("Wheel_" .. c, Vector3.new(w, r * 2, r * 2), hub, model)
		wheel.Shape = Enum.PartType.Cylinder -- Zylinderachse = X = Radachse
		wheel.CanCollide = true
		wheel.CanTouch = true
		wheel.CustomPhysicalProperties = PhysicalProperties.new(P.wheelDensity, 1, 0, 100, 100)
		info.wheels[c] = wheel
		for _, v in ipairs(info.wheelParts[c]) do
			decorate(v)
			weld(wheel, v)
		end

		local base = chassis
		if FRONT[c] then
			local k = newPart("Knuckle_" .. c, Vector3.new(P.knuckleSize, P.knuckleSize, P.knuckleSize), hub, model)
			k.CustomPhysicalProperties = PhysicalProperties.new(P.knuckleDensity, 0.3, 0, 1, 1)
			info.knuckles[c] = k
			local s0 = attach(chassis, "SteerBase_" .. c, hub * STEER_ROT)
			local s1 = attach(k, "SteerKnuckle_" .. c, hub * STEER_ROT)
			local steer = Instance.new("HingeConstraint")
			steer.Name = "Steer_" .. c
			steer.Attachment0 = s0
			steer.Attachment1 = s1
			steer.ActuatorType = Enum.ActuatorType.Servo
			steer.AngularSpeed = P.steerSpeed
			steer.ServoMaxTorque = P.steerTorque
			steer.TargetAngle = 0
			steer.LimitsEnabled = true
			steer.LowerAngle = -40
			steer.UpperAngle = 40
			steer.Parent = drive
			info.steers[c] = steer
			base = k
		end
		local a0 = attach(base, "AxleBase_" .. c, hub * AXLE_ROT)
		local a1 = attach(wheel, "AxleHub_" .. c, hub * AXLE_ROT)
		local axle = Instance.new("CylindricalConstraint")
		axle.Name = "Axle_" .. c
		axle.Attachment0 = a0
		axle.Attachment1 = a1
		axle.InclinationAngle = 90 -- Drehachse = Y des Attachment0 (links), Gleitachse = X (oben)
		axle.LimitsEnabled = true
		axle.LowerLimit = -P.travel
		axle.UpperLimit = P.travel
		axle.Restitution = 0
		axle.ActuatorType = Enum.ActuatorType.None
		axle.AngularActuatorType = Enum.ActuatorType.Motor
		axle.AngularVelocity = 0
		axle.MotorMaxTorque = 0
		axle.Parent = drive
		info.axles[c] = axle

		local top = attach(chassis, "SpringTop_" .. c, hub * CFrame.new(0, P.springLength, 0))
		local spring = Instance.new("SpringConstraint")
		spring.Name = "Spring_" .. c
		spring.Attachment0 = top
		spring.Attachment1 = a1
		spring.LimitsEnabled = false
		spring.Visible = false
		spring.Parent = drive
		info.springs[c] = spring

		local nc = Instance.new("NoCollisionConstraint")
		nc.Name = "NoCollide_" .. c
		nc.Part0 = wheel
		nc.Part1 = chassis
		nc.Parent = drive
	end
	info.radius = radius

	-- Unterbodenlicht (immer vorhanden, bei glow = 0 unsichtbar und aus)
	local glow = newPart("Underglow", Vector3.new(math.max(1, halfW * 2 - 0.6), 0.08, math.max(1, (z1 - z0) * 0.8)),
		rootCF * CFrame.new(0, P.hullBottom - 0.1, (z0 + z1) / 2), model)
	glow.Material = Enum.Material.Neon
	glow.Massless = true
	weld(chassis, glow)
	local light = Instance.new("PointLight")
	light.Name = "UnderglowLight"
	light.Brightness = 2.5
	light.Range = 14
	light.Shadows = false
	light.Enabled = false
	light.Parent = glow
	info.glow, info.glowLight = glow, light

	-- Spoiler zum Nachrüsten, wenn die Karosserie keinen hat
	if #info.spoilers == 0 then
		local yTop = 0
		for _, part in ipairs(info.paint) do
			local c, e = extents(rootCF, part)
			if c.Z + e.Z >= maxZ - 1.8 then
				yTop = math.max(yTop, c.Y + e.Y)
			end
		end
		if yTop <= 0 then
			yTop = 3.6
		end
		local z = maxZ - 0.9
		local wing = newPart("Spoiler", Vector3.new(math.min(7.4, maxX - minX - 0.4), 0.15, 0.9),
			rootCF * CFrame.new(0, yTop + 0.75, z), model)
		wing.Color = TRIM
		wing:SetAttribute("Addon", true)
		for _, sx in ipairs({ -2.5, 2.5 }) do
			local mount = newPart("SpoilerMount", Vector3.new(0.18, 0.75, 0.35), rootCF * CFrame.new(sx, yTop + 0.375, z), model)
			mount.Color = TRIM
			mount:SetAttribute("Addon", true)
			table.insert(info.spoilers, mount)
			info.spoilerAlpha[mount] = 0
		end
		table.insert(info.spoilers, wing)
		info.spoilerAlpha[wing] = 0
		for _, part in ipairs(info.spoilers) do
			part.Massless = true
			weld(chassis, part)
		end
	end

	-- Nitro-Flamme (hinten) und Glanz-Funkeln (Waschstraße)
	local exhaust = attach(chassis, "Exhaust", rootCF * CFrame.new(0, 1.6, maxZ + 0.2))
	local flame = Instance.new("ParticleEmitter")
	flame.Name = "NitroFlame"
	flame.Enabled = false
	flame.Rate = 90
	flame.Lifetime = NumberRange.new(0.12, 0.25)
	flame.Speed = NumberRange.new(18, 28)
	flame.SpreadAngle = Vector2.new(10, 10)
	flame.LightEmission = 1
	flame.Color = ColorSequence.new(Color3.fromRGB(120, 190, 255), Color3.fromRGB(255, 150, 60))
	flame.Size = NumberSequence.new(0.7, 0.1)
	flame.EmissionDirection = Enum.NormalId.Back
	flame.Parent = exhaust
	info.flame = flame
	local sparkle = Instance.new("ParticleEmitter")
	sparkle.Name = "ShineSparkles"
	sparkle.Enabled = false
	sparkle.Rate = 0
	sparkle.Lifetime = NumberRange.new(0.6, 1.2)
	sparkle.Speed = NumberRange.new(1, 3)
	sparkle.LightEmission = 1
	sparkle.Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(180, 230, 255))
	sparkle.Size = NumberSequence.new(0.35, 0)
	sparkle.Parent = chassis
	info.sparkle = sparkle

	-- alles unverankert (Physik startet, sobald das Modell im Workspace hängt)
	for _, x in ipairs(model:GetDescendants()) do
		if x:IsA("BasePart") then
			x.Anchored = false
		end
	end

	model:SetAttribute("OwnerId", opts.ownerId or 0)
	model:SetAttribute("OwnerName", opts.ownerName or "")
	model:SetAttribute("CarId", opts.carId or 0)
	model:SetAttribute("Model", opts.modelId or "")
	model:SetAttribute("Body", opts.body)
	model:SetAttribute("Testdrive", opts.testdrive == true)
	model:SetAttribute("KmhPerStud", CarCatalog.KmhPerStud)
	model:SetAttribute("DriveSign", 1)
	model:SetAttribute("SteerSign", 1)
	model:SetAttribute("NitroUntil", 0)
	model:SetAttribute("NitroReadyAt", 0)

	registry[model] = info
	if opts.stats then
		VehicleFactory.ApplyStats(model, opts.stats, true)
	end
	if opts.car then
		VehicleFactory.ApplyStyle(model, opts.car, opts.shine)
	end
	return model
end

function VehicleFactory.Info(model)
	return registry[model]
end

local function driveWheels(drive)
	if drive == "FWD" then
		return { "FL", "FR" }
	elseif drive == "AWD" then
		return { "FL", "FR", "RL", "RR" }
	end
	return { "RL", "RR" }
end
VehicleFactory.DriveWheels = driveWheels

local function gravity()
	local ok, g = pcall(function()
		return workspace.Gravity
	end)
	return (ok and type(g) == "number" and g > 0) and g or 196.2
end

---------------------------------------------------------------- Fahrwerte (sofort wirksam, auch während der Fahrt)
-- Setzt Masse, Grip, Federn und die Attribute, die DriveClient liest:
--   MaxSpeed (Studs/s), ReverseSpeed (Studs/s), Torque (Motormoment je angetriebenem Rad), BrakeTorque (je Rad),
--   CoastTorque, ParkTorque, SteerAngle (Grad), SteerSpeed (rad/s), WheelRadius, DriveWheels ("RL,RR"),
--   Gears, TopSpeedKmh, NitroLevel, NitroBoost, NitroSeconds, NitroCooldown
-- initial = true: Achsen in den Parkzustand (Motor hält mit ParkTorque). Später nie (der Fahrer-Client steuert sie).
function VehicleFactory.ApplyStats(model, stats, initial)
	local info = registry[model]
	if not info or not stats then
		return false
	end
	local P = phys()
	local chassis = info.chassis
	local size = chassis.Size
	local bodyMass = math.max(1, stats.mass)
	chassis.CustomPhysicalProperties = PhysicalProperties.new(math.clamp(bodyMass / (size.X * size.Y * size.Z), 0.01, 100), 0.3, 0.05, 1, 1)
	local wheelMass = 0
	for _, c in ipairs(CORNERS) do
		local wheel = info.wheels[c]
		local s = wheel.Size
		wheelMass += P.wheelDensity * math.pi * (s.Y / 2) ^ 2 * s.X
		wheel.CustomPhysicalProperties = PhysicalProperties.new(P.wheelDensity, math.clamp(stats.grip, 0, 2), 0, 100, 100)
	end
	local knuckleMass = 0
	for _ in pairs(info.knuckles) do
		knuckleMass += P.knuckleDensity * P.knuckleSize ^ 3
	end
	local sprung = bodyMass + knuckleMass + P.driverMass
	local total = sprung + wheelMass
	-- Federn: statischer Federweg rideDeflection / springRate, Dämpfung als Dämpfungsmaß der Viertel-Masse
	local cornerLoad = sprung * gravity() / 4
	local deflection = P.rideDeflection / math.max(0.1, stats.springRate)
	local stiffness = cornerLoad / deflection
	local damping = 2 * stats.damping * math.sqrt(stiffness * sprung / 4)
	for _, spring in pairs(info.springs) do
		spring.Stiffness = stiffness
		spring.Damping = damping
		spring.FreeLength = P.springLength + deflection
	end
	local radius = info.radius
	local driven = driveWheels(stats.drive)
	local torque = total * stats.accel * radius * P.lossFactor / #driven
	local brake = total * P.brakeDecel * radius / 4
	for _, steer in pairs(info.steers) do
		steer.LowerAngle = -(stats.steerAngle + 5)
		steer.UpperAngle = stats.steerAngle + 5
	end
	local seat = info.seat
	seat.MaxSpeed = stats.topSpeedStuds
	seat.Torque = torque
	model:SetAttribute("MaxSpeed", stats.topSpeedStuds)
	model:SetAttribute("ReverseSpeed", stats.reverseSpeedStuds)
	model:SetAttribute("TopSpeedKmh", stats.topSpeed)
	model:SetAttribute("Torque", torque)
	model:SetAttribute("BrakeTorque", brake)
	model:SetAttribute("CoastTorque", brake * P.coastShare)
	model:SetAttribute("ParkTorque", brake * P.parkShare)
	model:SetAttribute("SteerAngle", stats.steerAngle)
	model:SetAttribute("SteerSpeed", P.steerSpeed)
	model:SetAttribute("WheelRadius", radius)
	model:SetAttribute("DriveWheels", table.concat(driven, ","))
	model:SetAttribute("Gears", stats.gears)
	model:SetAttribute("NitroLevel", stats.nitro.level)
	model:SetAttribute("NitroBoost", stats.nitro.boost)
	model:SetAttribute("NitroSeconds", stats.nitro.seconds)
	model:SetAttribute("NitroCooldown", stats.nitro.cooldown)
	model:SetAttribute("Mass", total)
	if initial then
		for _, axle in pairs(info.axles) do
			axle.AngularVelocity = 0
			axle.MotorMaxTorque = brake * P.parkShare
		end
	end
	return true
end

---------------------------------------------------------------- Optik (sofort wirksam)
-- car = { paint, rims, glow, spoiler }; shine = Glanz nach der Waschstraße
function VehicleFactory.ApplyStyle(model, car, shine)
	local info = registry[model]
	if not info or type(car) ~= "table" then
		return false
	end
	local paint = CarCatalog.PaintColor(car.paint)
	local gloss = CarCatalog.Carwash.reflectance
	for _, part in ipairs(info.paint) do
		part.Color = paint
		part.Reflectance = shine and math.max(gloss, info.reflect[part] or 0) or (info.reflect[part] or 0)
	end
	local rim, reflect = CarCatalog.RimColor(car.rims)
	for _, part in ipairs(info.rims) do
		part.Color = rim
		part.Reflectance = reflect
	end
	for _, part in ipairs(info.spoilers) do
		part.Transparency = car.spoiler and (info.spoilerAlpha[part] or 0) or 1
	end
	local glow = CarCatalog.GlowColor(car.glow)
	if glow then
		info.glow.Transparency = 0
		info.glow.Color = glow
		info.glowLight.Color = glow
		info.glowLight.Enabled = true
	else
		info.glow.Transparency = 1
		info.glowLight.Enabled = false
	end
	model:SetAttribute("Paint", car.paint)
	model:SetAttribute("Rims", car.rims)
	model:SetAttribute("Glow", car.glow)
	model:SetAttribute("Spoiler", car.spoiler == true)
	model:SetAttribute("Shine", shine == true)
	-- Kosmetik (Meilenstein 8): ein angelegtes Felgen-Set überdeckt die Palettenfarbe auch nach Waschstraße/Tuning
	if info.cosmetics and info.cosmetics.rims then
		VehicleFactory.ApplyRimCosmetic(model, info.cosmetics.rims)
	end
	return true
end

---------------------------------------------------------------- Kosmetik (Shop, Meilenstein 8; docs/PHASE4_CONTRACT.md §9)
-- VehicleFactory.ApplyCosmetics(model, cosmetics) bzw. (model, car, cosmetics) – beide Formen; cosmetics =
-- ShopService.CosmeticsFor(d, car) = ShopRules.Resolve(d, car) = { wrap = Eintrag|nil, rims = ..., horn = ..., trail = ... }
-- (Einträge aus GameConfig.Shop.Cosmetics mit `style`; Ids als Strings werden nachgeschlagen). Alles prozedural,
-- keine Assets:
--   wrap   Folierung als dünne Parts (Streifen/Flammen/Karo/Wellen/Lorbeer/Fläche) auf Haube/Dach/Flanken entlang
--          der Karosserie-Hülle (info.bounds, Lackteile), Massless, CanCollide/CanTouch/CanQuery false, am Chassis
--          geschweißt, Ordner "Cosmetics" im Modell, höchstens MAX_COSMETIC_PARTS (40) Parts insgesamt.
--   rims   Farbe/Reflexion der Felgenteile (überdeckt die Palettenfarbe, bleibt nach ApplyStyle erhalten),
--          neon = Leuchtring (Neon-Zylinder) an jedem Rad, mitgeschweißt am Rad.
--   horn   Schild "HornPlate" mit SurfaceGui-Text am Heck + „Lichthupe“ (Neon-Leiste in der Lichtfarbe vorn, normal
--          unsichtbar); VehicleFactory.Flash(model, seconds) blitzt sie und die Scheinwerfer kurz auf
--          (Taste H: der Fahrer-Client darf dasselbe lokal tun, Attribute HornText/HornLight am Modell).
--   trail  Trail-Instanzen an beiden Hinterrädern (Attachments am Chassis, Farbe/Breite aus style), Enabled.
-- Erneutes Anwenden ersetzt alles Alte (Ordner wird neu gebaut); ApplyCosmetics(model, {}) entfernt alles; mit dem
-- Modell verschwindet die Kosmetik (alles Nachkommen des Modells).
local MAX_COSMETIC_PARTS = 40
VehicleFactory.MaxCosmeticParts = MAX_COSMETIC_PARTS
local COSMETIC_SLOTS = { "wrap", "rims", "horn", "trail" }
local SLOT_SET = { wrap = true, rims = true, horn = true, trail = true }

local shopConfig = nil
local function cosmeticById(id: any): any
	if type(id) ~= "string" then
		return nil
	end
	if shopConfig == nil then
		local ok, cfg = pcall(function()
			return require(MiniShared:WaitForChild("GameConfig", 5))
		end)
		shopConfig = (ok and type(cfg) == "table" and type(cfg.Shop) == "table") and cfg.Shop or false
	end
	return shopConfig and shopConfig.CosmeticById and shopConfig.CosmeticById[id] or nil
end

local function rgb(t: any, fallback: Color3): Color3
	if typeof(t) == "Color3" then
		return t
	end
	if type(t) == "table" and type(t[1]) == "number" and type(t[2]) == "number" and type(t[3]) == "number" then
		return Color3.fromRGB(math.clamp(t[1], 0, 255), math.clamp(t[2], 0, 255), math.clamp(t[3], 0, 255))
	end
	return fallback
end

-- Normalisiert die Eingabe: Einträge (mit style) oder Ids je Platz; falscher Platz / Unbekanntes wird ignoriert
local function normalizeCosmetics(input: any): { [string]: any }
	local out = {}
	if type(input) ~= "table" then
		return out
	end
	for _, slot in ipairs(COSMETIC_SLOTS) do
		local v = input[slot]
		if type(v) == "string" then
			v = cosmeticById(v)
		end
		if type(v) == "table" and type(v.style) == "table" and (v.slot == nil or v.slot == slot) then
			out[slot] = v
		end
	end
	return out
end

-- Karosserie-Profil aus den Lackteilen (Root-Koordinaten): Oberkante und halbe Breite an einer Z-Position
local function bodyProfile(info: any)
	local rootCF = info.root.CFrame
	local boxes = {}
	for _, part in ipairs(info.paint) do
		if part.Parent then
			local c, e = extents(rootCF, part)
			table.insert(boxes, { c = c, e = e })
		end
	end
	if #boxes == 0 then
		for _, part in ipairs(info.body) do
			if part.Parent then
				local c, e = extents(rootCF, part)
				table.insert(boxes, { c = c, e = e })
			end
		end
	end
	local b = info.bounds
	local function topAt(z: number): number
		local top = -math.huge
		for _, x in ipairs(boxes) do
			if z >= x.c.Z - x.e.Z - 0.05 and z <= x.c.Z + x.e.Z + 0.05 then
				top = math.max(top, x.c.Y + x.e.Y)
			end
		end
		if top == -math.huge then
			top = (b.minY + b.maxY) / 2
		end
		return top
	end
	local function halfWidthAt(z: number): number
		local w = 0
		for _, x in ipairs(boxes) do
			if z >= x.c.Z - x.e.Z - 0.05 and z <= x.c.Z + x.e.Z + 0.05 then
				w = math.max(w, math.abs(x.c.X) + x.e.X)
			end
		end
		if w <= 0 then
			w = (b.maxX - b.minX) / 2
		end
		return w
	end
	return { topAt = topAt, halfWidthAt = halfWidthAt, minZ = b.minZ, maxZ = b.maxZ, minY = b.minY, maxY = b.maxY, rootCF = rootCF }
end

local function cosmeticPart(info: any, state: any, name: string, size: Vector3, localCF: CFrame, color: Color3, parent: Instance): BasePart?
	if state.parts >= MAX_COSMETIC_PARTS then
		return nil
	end
	local p = newPart(name, size, info.root.CFrame * localCF, parent)
	p.Transparency = 0
	p.Massless = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p:SetAttribute("Cosmetic", state.id or "")
	state.parts += 1
	return p
end

-- Dünnes Teil auf der Oberseite: folgt der Oberkante zwischen z0 und z1 (Neigung um die X-Achse)
local function topPlate(info: any, state: any, prof: any, name: string, x: number, width: number, z0: number, z1: number, color: Color3, parent: Instance, lift: number?)
	local y0, y1 = prof.topAt(z0), prof.topAt(z1)
	local zm, ym = (z0 + z1) / 2, (y0 + y1) / 2 + (lift or 0.04)
	local len = math.max(0.2, z1 - z0)
	local tilt = math.atan2(y1 - y0, len)
	local cf = CFrame.new(x, ym, zm) * CFrame.Angles(-tilt, 0, 0)
	return cosmeticPart(info, state, name, Vector3.new(width, 0.06, math.sqrt(len * len + (y1 - y0) ^ 2)), cf, color, parent)
end

-- Dünnes Teil an der Flanke (links/rechts): Höhe h, Unterkante bei yBottom
local function sidePlate(info: any, state: any, prof: any, name: string, side: number, z0: number, z1: number, yBottom: number, h: number, color: Color3, parent: Instance)
	local zm = (z0 + z1) / 2
	local hw = prof.halfWidthAt(zm) + 0.04
	local cf = CFrame.new(side * hw, yBottom + h / 2, zm)
	return cosmeticPart(info, state, name, Vector3.new(0.06, h, math.max(0.2, z1 - z0)), cf, color, parent)
end

local WRAP_BUILDERS = {}

-- Zwei Rennstreifen über Haube und Dach (2 × 8 Segmente)
WRAP_BUILDERS.stripes = function(info, state, prof, style, folder)
	local c1 = rgb(style.color, Color3.fromRGB(236, 238, 240))
	local len = prof.maxZ - prof.minZ - 1.0
	local segs = 8
	local step = len / segs
	for _, x in ipairs({ -0.65, 0.65 }) do
		for i = 0, segs - 1 do
			local z0 = prof.minZ + 0.5 + i * step
			topPlate(info, state, prof, "Wrap", x, 0.55, z0, z0 + step, c1, folder)
		end
	end
end

-- Zielflagge: Karo über Haube und Dach (3 Spuren × 6 Reihen, nur die Felder beider Farben abwechselnd)
WRAP_BUILDERS.checker = function(info, state, prof, style, folder)
	local c1 = rgb(style.color, Color3.fromRGB(236, 238, 240))
	local c2 = rgb(style.color2, Color3.fromRGB(28, 30, 34))
	local len = prof.maxZ - prof.minZ - 1.2
	local rows, cols = 6, 3
	local step = len / rows
	local cell = 1.0
	for r = 0, rows - 1 do
		for col = 0, cols - 1 do
			local x = (col - 1) * cell
			local z0 = prof.minZ + 0.6 + r * step
			topPlate(info, state, prof, "Wrap", x, cell - 0.08, z0 + 0.04, z0 + step - 0.04, ((r + col) % 2 == 0) and c1 or c2, folder)
		end
	end
end

-- Flammen: Haubenband + je Seite sechs Zungen, die nach hinten kleiner werden
WRAP_BUILDERS.flames = function(info, state, prof, style, folder)
	local c1 = rgb(style.color, Color3.fromRGB(247, 120, 40))
	local c2 = rgb(style.color2, Color3.fromRGB(255, 210, 60))
	local len = prof.maxZ - prof.minZ
	local tongues = 6
	local span = len * 0.6
	local step = span / tongues
	local yBase = prof.minY + (prof.maxY - prof.minY) * 0.28
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, tongues - 1 do
			local z0 = prof.minZ + 0.6 + i * step
			local h = 1.3 - i * 0.16
			sidePlate(info, state, prof, "Wrap", side, z0, z0 + step - 0.08, yBase, h, (i % 2 == 0) and c1 or c2, folder)
		end
	end
	-- Haubenband vorn (zwei Felder in beiden Farben)
	topPlate(info, state, prof, "Wrap", 0, 2.4, prof.minZ + 0.5, prof.minZ + 1.7, c1, folder)
	topPlate(info, state, prof, "Wrap", 0, 1.4, prof.minZ + 1.7, prof.minZ + 2.6, c2, folder)
end

-- Wellen: je Seite sechs versetzte Felder in zwei Farben
WRAP_BUILDERS.waves = function(info, state, prof, style, folder)
	local c1 = rgb(style.color, Color3.fromRGB(48, 170, 157))
	local c2 = rgb(style.color2, Color3.fromRGB(107, 199, 210))
	local len = prof.maxZ - prof.minZ - 1.0
	local n = 6
	local step = len / n
	local yBase = prof.minY + (prof.maxY - prof.minY) * 0.22
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, n - 1 do
			local z0 = prof.minZ + 0.5 + i * step
			local lift = (i % 2 == 0) and 0 or 0.35
			sidePlate(info, state, prof, "Wrap", side, z0, z0 + step - 0.06, yBase + lift, 0.7, (i % 2 == 0) and c1 or c2, folder)
		end
	end
end

-- Lorbeer: Zierleiste rundum an den Schwellern, dazu zwei Blätter auf der Haube und ein Heckstreifen
WRAP_BUILDERS.laurel = function(info, state, prof, style, folder)
	local c1 = rgb(style.color, Color3.fromRGB(224, 172, 60))
	local c2 = rgb(style.color2, Color3.fromRGB(28, 30, 34))
	local yBase = prof.minY + (prof.maxY - prof.minY) * 0.12
	for _, side in ipairs({ -1, 1 }) do
		sidePlate(info, state, prof, "Wrap", side, prof.minZ + 0.4, prof.maxZ - 0.4, yBase, 0.35, c1, folder)
	end
	-- zwei Blätter (geneigte Felder) auf der Haube, ein dunkler Mittelstreifen dazwischen
	for _, x in ipairs({ -1.1, 1.1 }) do
		topPlate(info, state, prof, "Wrap", x, 0.8, prof.minZ + 0.8, prof.minZ + 2.4, c1, folder)
	end
	topPlate(info, state, prof, "Wrap", 0, 0.5, prof.minZ + 0.6, prof.minZ + 2.6, c2, folder)
	topPlate(info, state, prof, "Wrap", 0, 2.2, prof.maxZ - 1.6, prof.maxZ - 0.6, c1, folder)
end

-- Fläche: Haube und Dach in einer Farbe (4 Segmente)
WRAP_BUILDERS.solid = function(info, state, prof, style, folder)
	local c1 = rgb(style.color, Color3.fromRGB(236, 238, 240))
	local len = prof.maxZ - prof.minZ - 1.0
	local segs = 4
	local step = len / segs
	for i = 0, segs - 1 do
		local z0 = prof.minZ + 0.5 + i * step
		topPlate(info, state, prof, "Wrap", 0, 2.6, z0, z0 + step, c1, folder)
	end
end

local function buildWrap(info: any, state: any, entry: any, folder: Instance)
	local style = entry.style
	local builder = WRAP_BUILDERS[style.pattern] or WRAP_BUILDERS.stripes
	local prof = bodyProfile(info)
	state.id = entry.id or ""
	builder(info, state, prof, style, folder)
	for _, p in ipairs(folder:GetChildren()) do
		if p:IsA("BasePart") and p.Name == "Wrap" then
			weld(info.chassis, p)
		end
	end
end

-- Felgenfarbe/-reflexion und Leuchtring; ohne entry: Palettenfarbe aus ApplyStyle (Attribut Rims) zurück
function VehicleFactory.ApplyRimCosmetic(model: Model, entry: any): boolean
	local info = registry[model]
	if not info then
		return false
	end
	local style = type(entry) == "table" and entry.style or nil
	if style then
		local color = rgb(style.color, Color3.fromRGB(200, 200, 200))
		local reflect = type(style.reflectance) == "number" and math.clamp(style.reflectance, 0, 1) or 0
		for _, part in ipairs(info.rims) do
			part.Color = color
			part.Reflectance = reflect
		end
	else
		local rim, reflect = CarCatalog.RimColor(model:GetAttribute("Rims"))
		for _, part in ipairs(info.rims) do
			part.Color = rim
			part.Reflectance = reflect
		end
	end
	return true
end

local function buildRims(info: any, state: any, entry: any, folder: Instance)
	VehicleFactory.ApplyRimCosmetic(info.model, entry)
	local neon = entry.style.neon
	if type(neon) == "table" then
		state.id = entry.id or ""
		local color = rgb(neon, Color3.fromRGB(60, 255, 120))
		for _, c in ipairs(CORNERS) do
			local wheel = info.wheels[c]
			if wheel then
				local r = wheel.Size.Y / 2 * 0.72
				local w = wheel.Size.X + 0.16
				local left = c == "FL" or c == "RL"
				local ring = cosmeticPart(info, state, "RimNeon_" .. c, Vector3.new(w, r * 2, r * 2),
					info.root.CFrame:ToObjectSpace(wheel.CFrame), color, folder)
				if ring then
					ring.Shape = Enum.PartType.Cylinder
					ring.Material = Enum.Material.Neon
					ring.Transparency = 0.15
					ring:SetAttribute("Side", left and "L" or "R")
					weld(wheel, ring)
				end
			end
		end
	end
end

local function buildHorn(info: any, state: any, entry: any, folder: Instance)
	local style = entry.style
	local b = info.bounds
	local text = type(style.text) == "string" and style.text or "Tuut!"
	local light = rgb(style.light, Color3.fromRGB(255, 220, 120))
	state.id = entry.id or ""
	-- Schild am Heck mit dem Hupentext (SurfaceGui, keine Assets)
	local plate = cosmeticPart(info, state, "HornPlate", Vector3.new(2.2, 0.5, 0.08),
		CFrame.new(0, b.minY + (b.maxY - b.minY) * 0.42, b.maxZ + 0.06), Color3.fromRGB(28, 30, 34), folder)
	if plate then
		weld(info.chassis, plate)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "HornText"
		gui.Face = Enum.NormalId.Back
		gui.AlwaysOnTop = false
		gui.LightInfluence = 0
		gui.PixelsPerStud = 50
		gui.Parent = plate
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.BackgroundTransparency = 1
		label.Size = UDim2.fromScale(1, 1)
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = light
		label.Text = text
		label.Parent = gui
	end
	-- Lichthupe: Neon-Leiste vorn in der Lichtfarbe, normal unsichtbar; blitzt über VehicleFactory.Flash
	local bar = cosmeticPart(info, state, "Lichthupe", Vector3.new(math.max(1.5, (b.maxX - b.minX) * 0.7), 0.18, 0.1),
		CFrame.new(0, b.minY + (b.maxY - b.minY) * 0.42, b.minZ - 0.06), light, folder)
	if bar then
		bar.Material = Enum.Material.Neon
		bar.Transparency = 1
		weld(info.chassis, bar)
		local pl = Instance.new("PointLight")
		pl.Name = "FlashLight"
		pl.Color = light
		pl.Brightness = 3
		pl.Range = 16
		pl.Shadows = false
		pl.Enabled = false
		pl.Parent = bar
		info.cosmetics.flashBar = bar
	end
	info.model:SetAttribute("HornText", text)
	info.model:SetAttribute("HornLight", light)
end

local function buildTrail(info: any, state: any, entry: any, folder: Instance)
	local style = entry.style
	local c1 = rgb(style.color, Color3.fromRGB(60, 120, 255))
	local c2 = rgb(style.color2, c1)
	local width = type(style.width) == "number" and math.clamp(style.width, 0.2, 2) or 0.6
	local rootCF = info.root.CFrame
	for _, c in ipairs({ "RL", "RR" }) do
		local wheel = info.wheels[c]
		if wheel then
			local hub = rootCF:ToObjectSpace(wheel.CFrame)
			local r = wheel.Size.Y / 2
			local y = hub.Position.Y - r + 0.08
			local a0 = attach(info.chassis, "Trail0_" .. c, rootCF * CFrame.new(hub.Position.X - width / 2, y, hub.Position.Z))
			local a1 = attach(info.chassis, "Trail1_" .. c, rootCF * CFrame.new(hub.Position.X + width / 2, y, hub.Position.Z))
			local trail = Instance.new("Trail")
			trail.Name = "Trail_" .. c
			trail.Attachment0 = a0
			trail.Attachment1 = a1
			trail.Color = ColorSequence.new(c1, c2)
			trail.Transparency = NumberSequence.new(0.2, 1)
			trail.Lifetime = 0.8
			trail.MinLength = 0.1
			trail.WidthScale = NumberSequence.new(1, 0.4)
			trail.LightEmission = 0.6
			trail.FaceCamera = false
			trail.Enabled = true
			trail:SetAttribute("Cosmetic", entry.id or "")
			trail.Parent = folder
			table.insert(info.cosmetics.trails, trail)
			table.insert(info.cosmetics.attachments, a0)
			table.insert(info.cosmetics.attachments, a1)
		end
	end
	info.model:SetAttribute("TrailColor", c1)
end

-- Entfernt die aktuelle Kosmetik (Ordner, Trails, Attachments), Felgen zurück auf die Palettenfarbe
local function clearCosmetics(info: any)
	local cos = info.cosmetics
	if cos then
		for _, a in ipairs(cos.attachments or {}) do
			a:Destroy()
		end
		if cos.folder then
			cos.folder:Destroy()
		end
		if cos.rims then
			cos.rims = nil
			VehicleFactory.ApplyRimCosmetic(info.model, nil)
		end
	end
	info.cosmetics = { folder = nil, parts = 0, trails = {}, attachments = {}, rims = nil, ids = {}, flashBar = nil }
	local model = info.model
	model:SetAttribute("HornText", nil)
	model:SetAttribute("HornLight", nil)
	model:SetAttribute("TrailColor", nil)
	for _, slot in ipairs(COSMETIC_SLOTS) do
		model:SetAttribute("Cosmetic_" .. slot, "")
	end
end

-- ApplyCosmetics(model, cosmetics) | ApplyCosmetics(model, car, cosmetics). Rückgabe: Anzahl neuer Parts | nil
function VehicleFactory.ApplyCosmetics(model: Model, a: any, b: any): number?
	local info = registry[model]
	if not info then
		return nil
	end
	local input = b
	if input == nil then
		input = a
	end
	local cos = normalizeCosmetics(input)
	clearCosmetics(info)
	local state = info.cosmetics
	local folder = Instance.new("Folder")
	folder.Name = "Cosmetics"
	folder.Parent = model
	state.folder = folder
	local st = { parts = 0, id = "" }
	for _, slot in ipairs(COSMETIC_SLOTS) do
		local entry = cos[slot]
		if entry then
			state.ids[slot] = entry.id or ""
			model:SetAttribute("Cosmetic_" .. slot, entry.id or "")
			local ok, err = pcall(function()
				if slot == "wrap" then
					buildWrap(info, st, entry, folder)
				elseif slot == "rims" then
					state.rims = entry
					buildRims(info, st, entry, folder)
				elseif slot == "horn" then
					buildHorn(info, st, entry, folder)
				elseif slot == "trail" then
					buildTrail(info, st, entry, folder)
				end
			end)
			if not ok then
				warn("[Fahrzeug] Kosmetik " .. slot .. ": " .. tostring(err))
			end
		end
	end
	state.parts = st.parts
	return st.parts
end

-- Angewandte Kosmetik: { ids = { wrap = id, ... }, parts = n, trails = { Trail }, folder = Folder|nil }
function VehicleFactory.Cosmetics(model: Model): any
	local info = registry[model]
	return info and info.cosmetics or nil
end

-- Lichthupe: Leiste und Scheinwerfer kurz aufleuchten lassen (seconds, Standard 0,35 s). Ohne Hupen-Kosmetik
-- blitzen nur die Scheinwerfer (weiß). Rückgabe: true, wenn etwas geblitzt hat.
function VehicleFactory.Flash(model: Model, seconds: number?): boolean
	local info = registry[model]
	if not info then
		return false
	end
	local cos = info.cosmetics
	local bar = cos and cos.flashBar
	local color = model:GetAttribute("HornLight")
	if typeof(color) ~= "Color3" then
		color = Color3.fromRGB(255, 250, 230)
	end
	local lamps = {}
	for _, part in ipairs(info.body) do
		if part.Parent and part.Name == "Headlamp" then
			table.insert(lamps, { part = part, color = part.Color, material = part.Material })
			part.Color = color
			part.Material = Enum.Material.Neon
		end
	end
	if bar and bar.Parent then
		bar.Transparency = 0
		local pl = bar:FindFirstChild("FlashLight")
		if pl then
			pl.Enabled = true
		end
	elseif #lamps == 0 then
		return false
	end
	-- Sprechblase mit dem Hupentext über dem Auto (nur mit Hupen-Kosmetik; BillboardGui, keine Assets)
	local text = model:GetAttribute("HornText")
	local bubble = nil
	if type(text) == "string" and text ~= "" then
		local old = model:FindFirstChild("HornBubble")
		if old then
			old:Destroy()
		end
		bubble = Instance.new("BillboardGui")
		bubble.Name = "HornBubble"
		bubble.Size = UDim2.new(0, 160, 0, 40)
		bubble.StudsOffset = Vector3.new(0, 5, 0)
		bubble.AlwaysOnTop = false
		bubble.MaxDistance = 120
		bubble.Adornee = info.chassis
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundColor3 = Color3.fromRGB(28, 30, 34)
		label.BackgroundTransparency = 0.2
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = color
		label.Text = text
		label.Parent = bubble
		bubble.Parent = model
	end
	task.delay(math.clamp(type(seconds) == "number" and seconds or 0.35, 0.05, 2), function()
		if bubble and bubble.Parent then
			bubble:Destroy()
		end
		if bar and bar.Parent then
			bar.Transparency = 1
			local pl = bar:FindFirstChild("FlashLight")
			if pl then
				pl.Enabled = false
			end
		end
		for _, l in ipairs(lamps) do
			if l.part.Parent then
				l.part.Color = l.color
				l.part.Material = l.material
			end
		end
	end)
	return true
end

function VehicleFactory.Sparkle(model)
	local info = registry[model]
	if info and info.sparkle then
		pcall(function()
			info.sparkle:Emit(40)
		end)
	end
end

function VehicleFactory.SetNitro(model, active)
	local info = registry[model]
	if info and info.flame then
		info.flame.Enabled = active == true
	end
end

---------------------------------------------------------------- Aktivieren (nach dem Einhängen in den Workspace)
-- Drehrichtung der Achsen prüfen (positive AngularVelocity = vorwärts) und Netzwerk-Besitz setzen.
function VehicleFactory.CheckAxles(model)
	local info = registry[model]
	if not info then
		return
	end
	local left = -info.chassis.CFrame.RightVector
	for _, axle in pairs(info.axles) do
		pcall(function()
			local axis = axle.WorldRotationAxis
			if typeof(axis) == "Vector3" and axis:Dot(left) < -0.5 then
				axle.InclinationAngle = -axle.InclinationAngle
			end
		end)
	end
end

-- Netzwerk-Besitz aller Baugruppen (Chassis, Achsschenkel, Räder) an den Spieler
function VehicleFactory.SetOwner(model, player)
	local roots = {}
	for _, x in ipairs(model:GetDescendants()) do
		if x:IsA("BasePart") and not x.Anchored then
			local ok, r = pcall(function()
				return x.AssemblyRootPart
			end)
			r = (ok and r) or x
			if not roots[r] then
				roots[r] = true
				pcall(function()
					if r:CanSetNetworkOwnership() then
						r:SetNetworkOwner(player)
					end
				end)
			end
		end
	end
end

function VehicleFactory.Activate(model, player)
	VehicleFactory.CheckAxles(model)
	if player then
		VehicleFactory.SetOwner(model, player)
	end
end

return VehicleFactory
