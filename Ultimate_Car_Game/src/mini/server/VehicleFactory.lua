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
