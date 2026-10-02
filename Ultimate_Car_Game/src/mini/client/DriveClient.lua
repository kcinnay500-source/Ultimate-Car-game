-- DriveClient: Fahren mit dem eigenen Auto (Client). Gestartet von MiniClient: DriveClient.Start(ctx).
--
-- Sobald die eigene Figur in einem VehicleSeat eines eigenen Autos sitzt (Vorfahre-Model mit Attribut
-- OwnerId bzw. OwnerUserId == LocalPlayer.UserId), laufen Fahrregler und Tacho-HUD:
--   * Fahrregler: VehicleSeat.ThrottleFloat/SteerFloat (Tastatur, Gamepad und Roblox-Standard-Touchsteuerung
--     setzen sie über das PlayerModule) -> Achs-Motoren (AngularVelocity, MotorMaxTorque) und Lenk-Servos
--     (TargetAngle). Der Fahrer ist Netzwerk-Besitzer (Server: SetNetworkOwner), daher wirken die lokal gesetzten
--     Werte ohne Verzögerung. Der Server stellt beim Bau nur die Parkbremse ein.
--   * Tacho (km/h, Gang), Nitro-Taste N / Gamepad X / Handy-Knopf (sendet nur mini_car_nitro; der Server setzt
--     NitroUntil/NitroReadyAt), Zeitfahren-Anzeige (mini_notice track_*), Probefahrt-Restzeit.
--   * Lichthupe: Taste H / Gamepad L1 / Handy-Knopf HUPE sendet mini_car_horn; der Server lässt Scheinwerfer und
--     (mit Hupen-Kosmetik) die Lichtleiste in der Hupenfarbe aufblitzen und zeigt die Sprechblase (für alle sichtbar).
--   * Auto aufrichten: liegt das Auto auf der Seite/dem Dach (UpVector.Y < FlipUp) und steht fast (< FlipSpeed)
--     länger als FlipDelay, erscheint „Auto aufrichten [R]“ (Handy: Knopf). Der Fahrer ist Netzwerk-Besitzer, daher
--     setzt der Client das Auto selbst 4 Studs höher aufrecht hin (gleiche Stelle, gleiche Blickrichtung).
--   * Tuning wirkt sofort: Torque/BrakeTorque/MaxSpeed usw. werden jedes Frame aus den Modell-Attributen gelesen.
--   * Das HUD weicht dem 2.4.0-Tablet und QTE/Diagnose (ctx.IsTabletOpen/ctx.IsBlocked).
--   * Die Kamera bleibt Roblox-Standard.
--
-- Fahrzeug-Aufbau (VehicleFactory), zwei Namensschemata werden erkannt:
--   Folder "Drive": Axle_FL/FR/RL/RR (CylindricalConstraint, Winkel-Motor) + Steer_FL/FR (HingeConstraint Servo)
--                   oder MotorRL/MotorRR[/MotorFL/MotorFR] + SteerFL/SteerFR (Constraint oder ObjectValue darauf).
--   Vorzeichen: positive AngularVelocity rollt vorwärts, positiver TargetAngle lenkt nach RECHTS. Korrektur über
--   Modell-Attribute DriveSign/SteerSign oder Attribut Direction (±1) am Constraint bzw. ObjectValue.
--   Angetrieben: Attribut DriveWheels ("RL,RR", "FL,FR", "FL,FR,RL,RR"); Motor*-Constraints sind immer angetrieben.
--   Nicht angetriebene Achsen rollen frei und bremsen beim Bremsen/Halten mit.
-- Modell-Attribute: OwnerId|OwnerUserId, CarId, MaxSpeed|TopSpeed (Studs/s), ReverseSpeed (Studs/s), Torque (je
-- angetriebenem Rad), BrakeTorque, CoastTorque, ParkTorque (je Rad), SteerAngle (Grad), WheelRadius, Gears,
-- KmhPerStud, NitroLevel|Nitro (0..3), NitroBoost, NitroSeconds, NitroCooldown, NitroUntil, NitroReadyAt
-- (Serverzeit, workspace:GetServerTimeNow), Testdrive|TestDrive (bool), TestdriveEnds|ExpiresAt (Serverzeit).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local DriveClient = {}

DriveClient.KmhPerStud = 0.28 * 3.6 -- 1 Stud = 0,28 m (Roblox-Maßstab): Studs/s -> km/h
DriveClient.WheelRadius = 1.3 -- Reifen der 2.4.0-Vorlagen: Zylinder 2,6 Durchmesser
DriveClient.SteerAngle = 30
DriveClient.ReverseFactor = 0.3 -- Rückwärts höchstens 30 % der Spitze (CarCatalog.ReverseShare)
DriveClient.BrakeFactor = 2.5 -- Bremsmoment = 2,5 × Antriebsmoment, wenn BrakeTorque fehlt
DriveClient.CoastFactor = 0.08 -- Motorbremse beim Rollen ohne Gas: Anteil des Bremsmoments (CarCatalog.Physics.coastShare)
DriveClient.ParkFactor = 1.5 -- Parkbremse nach dem Aussteigen: Anteil des Bremsmoments (CarCatalog.Physics.parkShare)
DriveClient.Gears = 5 -- Gang-Anzeige ohne Attribut Gears (CarCatalog.BaseGears)
DriveClient.HighSpeedSteer = 0.45 -- bei Spitze nur noch 45 % Lenkeinschlag
DriveClient.NitroBoost = 1.35
DriveClient.NitroSendGap = 0.75
DriveClient.Action = "UCG_Nitro"
DriveClient.FlipAction = "UCG_Aufrichten"
DriveClient.HornAction = "UCG_Hupe"
DriveClient.HornSendGap = 0.5 -- höchstens alle 0,5 s eine Absicht (Server: GameConfig.Shop.HornCooldown)
DriveClient.FlipUp = 0.3 -- UpVector.Y darunter: Auto liegt auf der Seite oder dem Dach
DriveClient.FlipSpeed = 3 -- Studs/s: darunter gilt das Auto als liegen geblieben
DriveClient.FlipDelay = 2 -- Sekunden, bis „Auto aufrichten“ angeboten wird
DriveClient.FlipLift = 4 -- Studs über der aktuellen Stelle
DriveClient.FlipCooldown = 3
DriveClient.HudTop = 58 -- Tacho unter der 2.4.0-Fortschrittsleiste (y 8..54)
DriveClient.ToastTop = 118 -- Toasts während der Fahrt unter dem Tacho (sonst y 62)

local CORNERS = { "FL", "FR", "RL", "RR" }
local MOTOR_CLASSES = { HingeConstraint = true, CylindricalConstraint = true }
local STEER_CLASSES = { HingeConstraint = true, CylindricalConstraint = true }

local player = Players.LocalPlayer
local UI, Remote, ctx
local started = false
local gui, refs = nil, {}

local drive = nil -- { seat, model, motors = {{c, dir}}, steers = {{c, dir}}, baseTorque, last = {} }
local cachedChar, cachedHum
local lastNitroSent = -math.huge
local lastHornSent = -math.huge
local flipSince, lastFlip = nil, -math.huge
local shownSpeed = 0
local info = { driving = false, speed = 0, kmh = 0, gear = "N", nitro = false }

-- Zeitfahren (aus mini_notice track_* und dem Snapshot-Feld track)
local track = { active = false, startedAt = 0, index = 0, total = 0, localSince = 0 }
local result = nil -- { time, best, newBest, reward, cancelled, untilClock }
local lastNotice = nil

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

-- Grundwerte aus dem geteilten CarCatalog übernehmen (falls vorhanden), damit Client und Server gleich rechnen
local function loadCatalogDefaults()
	local ok, cat = pcall(function()
		local mini = game:GetService("ReplicatedStorage"):FindFirstChild("GarageShared")
		mini = mini and mini:FindFirstChild("Mini")
		local inst = mini and mini:FindFirstChild("CarCatalog")
		return inst and require(inst)
	end)
	if not ok or type(cat) ~= "table" then
		return
	end
	DriveClient.KmhPerStud = num(cat.KmhPerStud) or DriveClient.KmhPerStud
	DriveClient.ReverseFactor = num(cat.ReverseShare) or DriveClient.ReverseFactor
	DriveClient.Gears = num(cat.BaseGears) or DriveClient.Gears
	local phys = type(cat.Physics) == "table" and cat.Physics or {}
	DriveClient.CoastFactor = num(phys.coastShare) or DriveClient.CoastFactor
	DriveClient.ParkFactor = num(phys.parkShare) or DriveClient.ParkFactor
end

local function serverNow()
	return workspace:GetServerTimeNow()
end

local function lapTime(seconds)
	seconds = math.max(0, seconds or 0)
	local m = math.floor(seconds / 60)
	return (string.format("%d:%04.1f", m, seconds - m * 60):gsub("%.", ","))
end

-- Restzeit: 42.3 -> "0:43"
local function countdown(seconds)
	seconds = math.max(0, math.ceil(seconds or 0))
	return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function lapTimeFine(seconds)
	seconds = math.max(0, seconds or 0)
	local m = math.floor(seconds / 60)
	return (string.format("%d:%05.2f", m, seconds - m * 60):gsub("%.", ","))
end

---------------------------------------------------------------- Fahrzeug erkennen
-- erstes vorhandene Attribut aus einer Liste (Namensschemata von VehicleFactory und Vertrag)
local function attr(model, a, b, c)
	local v = model:GetAttribute(a)
	if v == nil and b then
		v = model:GetAttribute(b)
	end
	if v == nil and c then
		v = model:GetAttribute(c)
	end
	return v
end

local function ownerOf(model)
	return num(attr(model, "OwnerId", "OwnerUserId"))
end

local function ownerModel(seat)
	local node = seat.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and ownerOf(node) ~= nil then
			return node
		end
		node = node.Parent
	end
	return nil
end

local function resolve(folder, model, name, classes)
	local x = folder and folder:FindFirstChild(name) or nil
	if x == nil then
		x = model:FindFirstChild(name, true)
	end
	if x == nil then
		return nil
	end
	local dir = num(x:GetAttribute("Direction"))
	if x:IsA("ObjectValue") then
		x = x.Value
		if x and dir == nil then
			dir = num(x:GetAttribute("Direction"))
		end
	end
	if not x or not classes[x.ClassName] then
		return nil
	end
	return { c = x, dir = (dir and dir < 0) and -1 or 1 }
end

local function humanoid()
	local char = player and player.Character
	if char ~= cachedChar then
		cachedChar = char
		cachedHum = char and char:FindFirstChildOfClass("Humanoid") or nil
	elseif char and (not cachedHum or cachedHum.Parent ~= char) then
		cachedHum = char:FindFirstChildOfClass("Humanoid")
	end
	return cachedHum
end

local function set(entry, prop, value)
	local last = entry.last
	if last[prop] ~= value then
		last[prop] = value
		entry.c[prop] = value
	end
end

---------------------------------------------------------------- HUD
local function isTouch()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function buildHud()
	local T = UI.Theme
	gui = Instance.new("ScreenGui")
	gui.Name = "Fahren"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 25 -- über dem 2.4.0-HUD (20), unter den Minispielen (30)
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	-- Tacho oben mittig UNTER der 2.4.0-Fortschrittsleiste (CompactProgress y 8..54, zeigt Level/XP/Credits);
	-- unten liegen das 2.4.0-HUD, Stick und Sprungknopf. Toasts rücken während der Fahrt unter den Tacho (ToastTop).
	local panel = UI.Frame(gui, {
		Name = "Tacho", BackgroundColor3 = T.bg, BackgroundTransparency = 0.12, AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, DriveClient.HudTop), Size = UDim2.new(0, 200, 0, 54),
	})
	UI.Corner(panel, 12)
	refs.panel = panel
	refs.speed = UI.Label(panel, "0", {
		Name = "Speed", Font = UI.FontBig, TextSize = 30, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 10, 0, 2), Size = UDim2.new(0, 80, 0, 34), TextWrapped = false, TextXAlignment = Enum.TextXAlignment.Right,
	})
	UI.Label(panel, "km/h", {
		TextSize = 12, TextColor3 = T.muted, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 10, 0, 34), Size = UDim2.new(0, 80, 0, 16), TextXAlignment = Enum.TextXAlignment.Right,
	})
	local gearBox = UI.Frame(panel, {
		BackgroundColor3 = T.card, AutomaticSize = Enum.AutomaticSize.None, Position = UDim2.new(0, 98, 0, 8), Size = UDim2.new(0, 38, 0, 38),
	})
	UI.Corner(gearBox, 8)
	refs.gear = UI.Label(gearBox, "N", {
		Name = "Gang", Font = UI.FontBig, TextSize = 22, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromScale(1, 1),
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = false,
	})
	refs.nitroLabel = UI.Label(panel, "Nitro", {
		TextSize = 12, TextColor3 = T.muted, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 144, 0, 9), Size = UDim2.new(0, 50, 0, 16), TextWrapped = false,
	})
	local bar = UI.Frame(panel, {
		BackgroundColor3 = T.card, AutomaticSize = Enum.AutomaticSize.None, Position = UDim2.new(0, 144, 0, 30), Size = UDim2.new(0, 46, 0, 8),
	})
	UI.Corner(bar, 4)
	refs.nitroFill = UI.Frame(bar, { BackgroundColor3 = T.purple, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(0, 0, 1, 0) })
	UI.Corner(refs.nitroFill, 4)

	-- rechter Teil: Zeitfahren oder Probefahrt
	local side = UI.Frame(panel, {
		Name = "Zeit", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 200, 0, 0), Size = UDim2.new(0, 124, 1, 0), Visible = false,
	})
	refs.side = side
	refs.sideTime = UI.Label(side, "", {
		Name = "Zeitwert", Font = UI.FontBold, TextSize = 20, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 0, 0, 6), Size = UDim2.new(1, -8, 0, 24), TextWrapped = false,
	})
	refs.sideSub = UI.Label(side, "", {
		TextSize = 12, TextColor3 = T.muted, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 0, 0, 31), Size = UDim2.new(1, -8, 0, 18), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- Nitro-Knopf rechts über dem Sprungknopf und dem 2.4.0-HUD (≥ 44 px, auf dem Handy 76 px)
	refs.nitro = UI.Button(gui, "NITRO", T.purple, function()
		DriveClient.Nitro()
	end, {
		Name = "Nitro", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -16, 1, -150), Size = UDim2.new(0, 76, 0, 76), TextSize = 15,
	})
	local corner = refs.nitro:FindFirstChildOfClass("UICorner")
	if corner then
		corner.CornerRadius = UDim.new(0.5, 0)
	end

	-- Lichthupe (Hupen-Kosmetik), links neben dem Nitro-Knopf
	refs.horn = UI.Button(gui, "HUPE", T.blue, function()
		DriveClient.Horn()
	end, {
		Name = "Hupe", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -100, 1, -150), Size = UDim2.new(0, 64, 0, 64), TextSize = 13,
	})
	local hornCorner = refs.horn:FindFirstChildOfClass("UICorner")
	if hornCorner then
		hornCorner.CornerRadius = UDim.new(0.5, 0)
	end

	-- Auto aufrichten (nur sichtbar, wenn das Auto umgekippt liegen bleibt)
	refs.flip = UI.Button(gui, "Auto aufrichten [R]", T.yellow, function()
		DriveClient.Flip()
	end, {
		Name = "Aufrichten", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, DriveClient.HudTop + 62),
		Size = UDim2.new(0, 200, 0, 48), TextSize = 16, Visible = false,
	})
end

local function setSide(visible)
	refs.side.Visible = visible
	refs.panel.Size = UDim2.new(0, visible and 324 or 200, 0, 54)
end

---------------------------------------------------------------- Nitro
local function nitroState(model, now)
	local level = model and attr(model, "NitroLevel", "Nitro")
	level = level == nil and nil or (num(level) or 0)
	local untilT = num(model and model:GetAttribute("NitroUntil")) or 0
	local readyAt = num(model and model:GetAttribute("NitroReadyAt")) or 0
	return level, untilT > now, untilT, readyAt
end

-- Nitro-Absicht (Taste N, Gamepad X, Handy-Knopf). Der Server entscheidet und setzt NitroUntil am Auto.
function DriveClient.Nitro()
	if not drive then
		return false
	end
	local now = serverNow()
	local level, active, _, readyAt = nitroState(drive.model, now)
	if level == 0 then
		if ctx and ctx.Toast then
			ctx.Toast("Kein Nitro eingebaut. Im Tuning-Zentrum kannst du es nachrüsten.")
		end
		return false
	end
	if active or readyAt > now or os.clock() - lastNitroSent < DriveClient.NitroSendGap then
		return false
	end
	lastNitroSent = os.clock()
	Remote.Send("mini_car_nitro")
	return true
end

local function onNitroAction(_, inputState)
	if inputState == Enum.UserInputState.Begin then
		DriveClient.Nitro()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

---------------------------------------------------------------- Lichthupe
-- Hupen-Absicht (Taste H, Gamepad L1, Handy-Knopf). Der Server blitzt das Auto auf (VehicleFactory.Flash).
function DriveClient.Horn()
	if not drive or os.clock() - lastHornSent < DriveClient.HornSendGap then
		return false
	end
	lastHornSent = os.clock()
	Remote.Send("mini_car_horn")
	return true
end

local function onHornAction(_, inputState)
	if inputState == Enum.UserInputState.Begin and drive then
		DriveClient.Horn()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

---------------------------------------------------------------- Auto aufrichten
local function chassisOf(d)
	return d.model:FindFirstChild("Chassis") or d.model.PrimaryPart or d.seat
end

-- Liegt das Auto seit FlipDelay auf der Seite/dem Dach und steht fast? (clock = os.clock())
function DriveClient.Flippable(d, clock)
	d = d or drive
	if not d then
		return false
	end
	local body = chassisOf(d)
	local up = body.CFrame.UpVector.Y
	local speed = body.AssemblyLinearVelocity.Magnitude
	if up < DriveClient.FlipUp and speed < DriveClient.FlipSpeed then
		flipSince = flipSince or clock
	else
		flipSince = nil
	end
	return flipSince ~= nil and clock - flipSince >= DriveClient.FlipDelay
end

-- Stellt das Auto an derselben Stelle aufrecht hin (Blickrichtung waagerecht erhalten) und stoppt alle Bewegung.
-- Nur der Fahrer (Netzwerk-Besitzer) ruft das auf; die Änderung repliziert über den Netzwerk-Besitz.
function DriveClient.Flip()
	local d = drive
	local clock = os.clock()
	if not d or clock - lastFlip < DriveClient.FlipCooldown or not DriveClient.Flippable(d, clock) then
		return false
	end
	local body = chassisOf(d)
	local pos = body.Position
	local look = body.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.1 then
		-- steht auf der Nase/dem Heck: Richtung aus der Oberseite nehmen
		local upv = body.CFrame.UpVector
		flat = Vector3.new(upv.X, 0, upv.Z)
	end
	local yaw = flat.Magnitude >= 0.1 and math.atan2(-flat.X, -flat.Z) or 0
	lastFlip = clock
	flipSince = nil
	-- Ziel für das Chassis; der Modell-Pivot folgt mit seinem Versatz zum Chassis (PrimaryPart muss es nicht sein)
	local target = CFrame.new(pos + Vector3.new(0, DriveClient.FlipLift, 0)) * CFrame.Angles(0, yaw, 0)
	d.model:PivotTo(target * (body.CFrame:Inverse() * d.model:GetPivot()))
	for _, x in ipairs(d.model:GetDescendants()) do
		if x:IsA("BasePart") and not x.Anchored then
			x.AssemblyLinearVelocity = Vector3.zero
			x.AssemblyAngularVelocity = Vector3.zero
		end
	end
	refs.flip.Visible = false
	return true
end

local function onFlipAction(_, inputState)
	if inputState == Enum.UserInputState.Begin and drive and refs.flip.Visible then
		DriveClient.Flip()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

---------------------------------------------------------------- Ein-/Aussteigen
-- Achsen und Lenkung eines Fahrzeugs einsammeln (einmal beim Einsteigen)
function DriveClient.Collect(model)
	local folder = model:FindFirstChild("Drive")
	local d = { motors = {}, steers = {} }
	local driven = {}
	local list = attr(model, "DriveWheels")
	if type(list) == "string" and list ~= "" then
		for c in string.gmatch(list, "%u%u") do
			driven[c] = true
		end
	else
		driven.RL, driven.RR = true, true
	end
	for _, c in ipairs(CORNERS) do
		local e = resolve(folder, model, "Axle_" .. c, MOTOR_CLASSES)
		if e then
			e.driven = driven[c] == true
		else
			e = resolve(folder, model, "Motor" .. c, MOTOR_CLASSES)
			if e then
				e.driven = true
			end
		end
		if e then
			e.corner = c
			e.last = {}
			table.insert(d.motors, e)
		end
	end
	for _, c in ipairs({ "FL", "FR" }) do
		local e = resolve(folder, model, "Steer_" .. c, STEER_CLASSES) or resolve(folder, model, "Steer" .. c, STEER_CLASSES)
		if e then
			e.corner = c
			e.last = {}
			table.insert(d.steers, e)
		end
	end
	return d
end

local function enter(seat, model)
	local d = DriveClient.Collect(model)
	d.seat, d.model = seat, model
	-- Antriebsmoment: Attribut Torque, sonst was der Server am ersten Motor eingestellt hat
	d.baseTorque = num(model:GetAttribute("Torque")) or (d.motors[1] and num(d.motors[1].c.MotorMaxTorque)) or 0
	pcall(function()
		seat.HeadsUpDisplay = false -- eigener Tacho statt Roblox-Standardanzeige
	end)
	drive = d
	shownSpeed = 0
	info.driving = true
	gui.Enabled = true
	refs.nitro.Text = isTouch() and "NITRO" or "NITRO\n[N]"
	ContextActionService:BindActionAtPriority(DriveClient.Action, onNitroAction, false, 3000, Enum.KeyCode.N, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority(DriveClient.FlipAction, onFlipAction, false, 3000, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority(DriveClient.HornAction, onHornAction, false, 3000, Enum.KeyCode.H, Enum.KeyCode.ButtonL1)
	refs.horn.Text = isTouch() and "HUPE" or "HUPE\n[H]"
	flipSince = nil
	refs.flip.Visible = false
	refs.flip.Text = isTouch() and "Auto aufrichten" or "Auto aufrichten [R]"
end

local function exit()
	local d = drive
	drive = nil
	info.driving = false
	info.speed, info.kmh, info.gear, info.nitro = 0, 0, "N", false
	if gui then
		gui.Enabled = false
	end
	ContextActionService:UnbindAction(DriveClient.Action)
	ContextActionService:UnbindAction(DriveClient.FlipAction)
	ContextActionService:UnbindAction(DriveClient.HornAction)
	flipSince = nil
	if refs.flip then
		refs.flip.Visible = false
	end
	if not d then
		return
	end
	-- Parkbremse: alle Räder halten, Lenkung gerade
	local brake = num(d.model:GetAttribute("BrakeTorque")) or d.baseTorque * DriveClient.BrakeFactor
	local park = num(d.model:GetAttribute("ParkTorque")) or brake * DriveClient.ParkFactor
	for _, m in ipairs(d.motors) do
		set(m, "AngularVelocity", 0)
		if park > 0 then
			set(m, "MotorMaxTorque", park)
		end
	end
	for _, s in ipairs(d.steers) do
		set(s, "TargetAngle", 0)
	end
end

---------------------------------------------------------------- Regler und Anzeige
local function control(d, dt)
	local seat, model = d.seat, d.model
	local throttle = num(seat.ThrottleFloat) or num(seat.Throttle) or 0
	local steer = num(seat.SteerFloat) or num(seat.Steer) or 0
	throttle = math.clamp(throttle, -1, 1)
	steer = math.clamp(steer, -1, 1)
	local now = serverNow()
	local _, nitro = nitroState(model, now)
	local boost = nitro and (num(model:GetAttribute("NitroBoost")) or DriveClient.NitroBoost) or 1
	local topSpeed = num(attr(model, "MaxSpeed", "TopSpeed")) or num(seat.MaxSpeed) or 60
	local radius = num(model:GetAttribute("WheelRadius")) or DriveClient.WheelRadius
	local steerMax = num(model:GetAttribute("SteerAngle")) or DriveClient.SteerAngle
	local driveSign = (num(model:GetAttribute("DriveSign")) or 1) < 0 and -1 or 1
	local steerSign = (num(model:GetAttribute("SteerSign")) or 1) < 0 and -1 or 1
	-- Jedes Frame aus dem Attribut: Tuning (VehicleFactory.ApplyStats) wirkt sofort, auch während der Fahrt
	local torque = num(model:GetAttribute("Torque")) or d.baseTorque
	local brake = num(model:GetAttribute("BrakeTorque")) or torque * DriveClient.BrakeFactor
	local coast = num(model:GetAttribute("CoastTorque")) or brake * DriveClient.CoastFactor

	local velocity = seat.AssemblyLinearVelocity
	local forward = seat.CFrame.LookVector
	local fwd = velocity:Dot(forward)

	local maxFwd = topSpeed * boost
	local maxRev = num(model:GetAttribute("ReverseSpeed")) or topSpeed * DriveClient.ReverseFactor
	-- Betriebsart: drive (Gas in Fahrtrichtung), brake (Gegengas), hold (steht ohne Gas), coast (rollt ohne Gas)
	local mode, target = "coast", 0
	if throttle > 0.05 then
		if fwd < -2 then
			mode = "brake" -- rollt rückwärts: erst bremsen
		else
			mode, target = "drive", maxFwd * throttle
		end
	elseif throttle < -0.05 then
		if fwd > 2 then
			mode = "brake" -- fährt vorwärts: bremsen
		else
			mode, target = "drive", -maxRev * -throttle
		end
	elseif math.abs(fwd) < 1 then
		mode = "hold"
	end
	local angular = target / math.max(0.1, radius) * driveSign
	for _, m in ipairs(d.motors) do
		local velocityOut, torqueOut
		if mode == "drive" then
			if m.driven then
				velocityOut, torqueOut = angular, torque * boost
			else
				velocityOut, torqueOut = 0, 0 -- frei rollen
			end
		elseif mode == "coast" then
			velocityOut, torqueOut = 0, m.driven and coast or 0
		else
			velocityOut, torqueOut = 0, brake -- bremsen bzw. halten: alle Räder
		end
		set(m, "AngularVelocity", velocityOut * m.dir)
		set(m, "MotorMaxTorque", torqueOut)
	end
	local speedRatio = math.clamp(math.abs(fwd) / math.max(1, topSpeed), 0, 1)
	-- positiver Winkel = rechts (VehicleFactory: Scharnierachse nach unten); SteerFloat +1 = rechts
	local angle = steer * steerMax * (1 - (1 - DriveClient.HighSpeedSteer) * speedRatio) * steerSign
	for _, s in ipairs(d.steers) do
		set(s, "TargetAngle", angle * s.dir)
	end
	info.mode = mode

	-- Anzeige-Werte
	local speed = math.abs(fwd)
	shownSpeed += (speed - shownSpeed) * math.clamp(dt * 8, 0, 1)
	local gears = math.max(1, math.floor(num(model:GetAttribute("Gears")) or DriveClient.Gears))
	local gear
	if fwd < -1 then
		gear = "R"
	elseif speed < 0.5 and math.abs(throttle) < 0.05 then
		gear = "N"
	else
		gear = tostring(math.clamp(1 + math.floor(speed / math.max(1, topSpeed) * gears), 1, gears))
	end
	info.speed = speed
	info.kmh = math.floor(shownSpeed * (num(model:GetAttribute("KmhPerStud")) or DriveClient.KmhPerStud) + 0.5)
	info.gear = gear
	info.nitro = nitro
	info.throttle, info.steer, info.target, info.angle = throttle, steer, target, angle
end

local function render(d)
	local T = UI.Theme
	refs.speed.Text = tostring(info.kmh)
	refs.gear.Text = info.gear
	local now = serverNow()
	local level, active, untilT, readyAt = nitroState(d.model, now)
	refs.nitro.Visible = level ~= 0
	refs.nitroLabel.Text = level == 0 and "–" or "Nitro"
	if active then
		local dur = num(attr(d.model, "NitroSeconds", "NitroDuration")) or 3
		UI.SetProgress(refs.nitroFill, (untilT - now) / math.max(0.1, dur))
		refs.nitro.Text = "NITRO!"
		UI.SetEnabled(refs.nitro, false, T.purple)
		refs.nitro.BackgroundColor3 = T.yellow
	elseif readyAt > now then
		local cd = num(d.model:GetAttribute("NitroCooldown")) or 10
		UI.SetProgress(refs.nitroFill, 1 - (readyAt - now) / math.max(0.1, cd))
		refs.nitro.Text = "NITRO\n" .. math.ceil(readyAt - now) .. " s"
		UI.SetEnabled(refs.nitro, false, T.purple)
	else
		UI.SetProgress(refs.nitroFill, level == 0 and 0 or 1)
		refs.nitro.Text = isTouch() and "NITRO" or "NITRO\n[N]"
		UI.SetEnabled(refs.nitro, true, T.purple)
	end

	-- Zeitfahren > Ergebnis > Probefahrt
	if track.active and now < track.startedAt then
		setSide(true)
		refs.sideTime.Text = "Start in " .. math.ceil(track.startedAt - now - 1e-6)
		refs.sideTime.TextColor3 = T.yellow
		refs.sideSub.Text = "Zeitfahren"
	elseif track.active then
		setSide(true)
		refs.sideTime.Text = lapTime(now - track.startedAt)
		refs.sideTime.TextColor3 = T.text
		refs.sideSub.Text = track.total > 0 and ("Checkpoint " .. track.index .. "/" .. track.total) or "Zeitfahren"
	elseif result and os.clock() < result.untilClock then
		setSide(true)
		if result.cancelled then
			refs.sideTime.Text = "Ungültig"
			refs.sideTime.TextColor3 = T.red
			refs.sideSub.Text = DriveClient.ReasonText(result.reason)
		else
			refs.sideTime.Text = lapTimeFine(result.time)
			refs.sideTime.TextColor3 = result.newBest and T.green or T.text
			refs.sideSub.Text = result.newBest and "Neue Bestzeit!" or (result.best and ("Bestzeit " .. lapTimeFine(result.best)) or "Ziel")
		end
	elseif attr(d.model, "Testdrive", "TestDrive") == true then
		local ends = num(attr(d.model, "TestdriveEnds", "ExpiresAt", "TestdriveUntil"))
		setSide(true)
		refs.sideTime.Text = ends and countdown(ends - now) or "–"
		refs.sideTime.TextColor3 = ends and ends - now < 10 and T.red or T.text
		refs.sideSub.Text = "Probefahrt"
	else
		setSide(false)
	end
end

-- 2.4.0-Tablet oder QTE/Diagnose offen: Tacho und Knöpfe ausblenden (sonst lägen sie über dem Tablet)
local function hudHidden()
	if not ctx then
		return false
	end
	for _, key in ipairs({ "IsTabletOpen", "IsBlocked" }) do
		local fn = ctx[key]
		if type(fn) == "function" then
			local ok, res = pcall(fn)
			if ok and res == true then
				return true
			end
		end
	end
	return false
end
DriveClient.HudHidden = hudHidden

-- Oberkante für Toasts: während der Fahrt (Tacho sichtbar) unter dem Tacho, sonst die 2.4.0-Stelle
function DriveClient.ToastOffset()
	if drive and gui and gui.Enabled then
		return DriveClient.ToastTop
	end
	return nil
end

local function step(dt)
	local hum = humanoid()
	local seat = hum and hum.SeatPart or nil
	if drive then
		if seat ~= drive.seat or not drive.seat.Parent or not drive.model.Parent or (hum and hum.Health <= 0) then
			exit()
		end
	end
	if not drive and seat and seat:IsA("VehicleSeat") then
		local model = ownerModel(seat)
		if model and ownerOf(model) == player.UserId then
			enter(seat, model)
		end
	end
	if drive then
		control(drive, dt)
		gui.Enabled = not hudHidden()
		render(drive)
		refs.flip.Visible = DriveClient.Flippable(drive, os.clock())
	end
end

---------------------------------------------------------------- Server-Hinweise und Snapshot
-- Gründe für ungültige Läufe (TrackRules: early, tooFast; CarService: expired, left, despawn)
DriveClient.Reasons = {
	early = "Frühstart",
	tooFast = "Abkürzung erkannt",
	expired = "Zeit abgelaufen",
	left = "Auto verlassen",
	despawn = "Auto abgestellt",
}
function DriveClient.ReasonText(reason)
	return DriveClient.Reasons[reason] or "Lauf abgebrochen"
end

local CANCEL = { track_cancel = true, track_abort = true, track_invalid = true, track_fail = true }

-- mini_notice: track_start {startAt|startedAt (Serverzeit, nach der Startampel), total}, track_checkpoint {index,
-- total, time}, track_finish {time, best, newBest, reward}, track_cancel|track_invalid {reason}.
-- Gleiche Tabelle zweimal (z. B. über TrackUI weitergereicht) wirkt einmal.
function DriveClient.OnNotice(data)
	if type(data) ~= "table" or data == lastNotice then
		return
	end
	lastNotice = data
	local kind = data.kind
	if kind == "track_start" then
		track.active = true
		track.startedAt = num(data.startAt) or num(data.startedAt) or serverNow()
		track.index = 0
		track.total = num(data.total) or track.total
		track.localSince = os.clock()
		result = nil
	elseif kind == "track_checkpoint" then
		if not track.active then
			track.active = true
			track.startedAt = num(data.startAt) or num(data.startedAt) or (serverNow() - (num(data.time) or 0))
			track.localSince = os.clock()
			result = nil
		end
		track.index = num(data.index) or (track.index + 1)
		track.total = num(data.total) or track.total
	elseif kind == "track_finish" then
		track.active = false
		result = {
			time = num(data.time), best = num(data.best), newBest = data.newBest == true, reward = num(data.reward),
			untilClock = os.clock() + 8,
		}
	elseif CANCEL[kind] then
		track.active = false
		result = { cancelled = true, reason = data.reason, untilClock = os.clock() + 5 }
	end
end

-- Snapshot-Feld track {active, startedAt, checkpoint, total}: hält die Anzeige nach einem Rejoin/Lag im Takt
function DriveClient.OnSnapshot(s)
	local tr = type(s) == "table" and s.track
	if type(tr) ~= "table" then
		return
	end
	local startAt = num(tr.startAt) or num(tr.startedAt)
	if tr.active == true and startAt then
		if not track.active then
			track.localSince = os.clock()
			result = nil
		end
		track.active = true
		track.startedAt = startAt
		track.index = num(tr.checkpoint) or num(tr.index) or (num(tr.next) and num(tr.next) - 1) or track.index
		track.total = num(tr.total) or track.total
	elseif tr.active == false and track.active and os.clock() - track.localSince > 2 then
		track.active = false
	end
end

-- Zustand des Zeitfahrens (für TrackUI): {active, startedAt, index, total, elapsed, countdown, result}
function DriveClient.Track()
	return {
		active = track.active,
		startedAt = track.startedAt,
		index = track.index,
		total = track.total,
		elapsed = track.active and math.max(0, serverNow() - track.startedAt) or 0,
		countdown = track.active and math.max(0, track.startedAt - serverNow()) or 0,
		result = result and table.clone(result) or nil,
	}
end

-- Fahrzustand (für Tests/Anzeigen): {driving, speed, kmh, gear, nitro, throttle, steer, target, angle, model}
function DriveClient.Info()
	local out = table.clone(info)
	out.model = drive and drive.model or nil
	out.seat = drive and drive.seat or nil
	return out
end

DriveClient.LapTime = lapTimeFine

---------------------------------------------------------------- Start
-- Erneuter Aufruf (bereits gestartet) übernimmt nur Remote und Toast aus dem neuen ctx; das HUD bleibt.
function DriveClient.Start(c)
	if started then
		if type(c) == "table" then
			ctx = c
			Remote = c.Remote or Remote
		end
		return
	end
	started = true
	ctx = type(c) == "table" and c or {}
	loadCatalogDefaults()
	UI = ctx.UI or require(script.Parent:WaitForChild("MiniUI"))
	Remote = ctx.Remote or require(script.Parent:WaitForChild("MiniRemote"))
	buildHud()
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(step, dt)
		if not ok and drive then
			-- ein defektes Fahrzeug darf das HUD nicht in einer Fehlerschleife halten
			drive = nil
			info.driving = false
			gui.Enabled = false
			ContextActionService:UnbindAction(DriveClient.Action)
			ContextActionService:UnbindAction(DriveClient.FlipAction)
			ContextActionService:UnbindAction(DriveClient.HornAction)
			warn("[Fahren] " .. tostring(err))
		end
	end)
end

function DriveClient.Gui()
	return gui, refs
end

return DriveClient
