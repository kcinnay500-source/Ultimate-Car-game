-- DriveClient: Fahren mit dem eigenen Auto (Client). Gestartet von MiniClient: DriveClient.Start(ctx).
--
-- Sobald die eigene Figur in einem VehicleSeat eines eigenen Autos sitzt (Vorfahre-Model mit Attribut
-- OwnerUserId == LocalPlayer.UserId), läuft der Fahrregler und das Tacho-HUD erscheint:
--   * Fahrregler: VehicleSeat.ThrottleFloat/SteerFloat (Tastatur, Gamepad und Roblox-Standard-Touchsteuerung)
--     -> Antrieb (MotorRL/MotorRR, optional MotorFL/MotorFR: AngularVelocity + MotorMaxTorque) und Lenkung
--     (SteerFL/SteerFR: HingeConstraint Servo, TargetAngle). Der Fahrer ist Netzwerk-Besitzer (Server:
--     SetNetworkOwner), daher wirken die lokal gesetzten Werte ohne Verzögerung.
--   * Tacho (km/h, Gang), Nitro-Taste N / Gamepad X / Handy-Knopf (sendet nur mini_car_nitro, der Server
--     setzt NitroUntil), Zeitfahren-Anzeige (track_* Hinweise), Probefahrt-Restzeit.
--   * Die Kamera bleibt Roblox-Standard.
--
-- Modell-Attribute (VehicleFactory/CarService): OwnerUserId, CarId, TopSpeed (Studs/s), Torque (MotorMaxTorque),
-- SteerAngle (Grad), optional WheelRadius (Studs, Standard 1,3), Gears, Nitro (Stufe 0..3), NitroUntil,
-- NitroReadyAt (Serverzeit, workspace:GetServerTimeNow), NitroBoost (Faktor, Standard 1,35), TestDrive (bool),
-- ExpiresAt (Serverzeit, Ende der Probefahrt).
-- Folder "Drive" im Modell mit den Constraints (oder ObjectValues darauf) MotorRL, MotorRR, [MotorFL, MotorFR],
-- SteerFL, SteerFR. Attribut Direction (1/-1) am Constraint bzw. ObjectValue: positive AngularVelocity × Direction
-- rollt vorwärts; die Lenkung setzt TargetAngle = -SteerFloat × Lenkwinkel × Direction (Direction 1: Hinge-Achse
-- zeigt nach oben, positiver Winkel lenkt nach links).
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local DriveClient = {}

DriveClient.KmhPerStud = 0.28 * 3.6 -- 1 Stud = 0,28 m (Roblox-Maßstab): Studs/s -> km/h
DriveClient.WheelRadius = 1.3 -- Reifen der 2.4.0-Vorlagen: Zylinder 2,6 Durchmesser
DriveClient.SteerAngle = 30
DriveClient.ReverseFactor = 0.35 -- Rückwärts höchstens 35 % der Spitze
DriveClient.BrakeFactor = 2.5 -- Bremsmoment = 2,5 × Antriebsmoment
DriveClient.CoastFactor = 0.08 -- Motorbremse beim Rollen ohne Gas
DriveClient.HighSpeedSteer = 0.45 -- bei Spitze nur noch 45 % Lenkeinschlag
DriveClient.NitroBoost = 1.35
DriveClient.NitroSendGap = 0.75
DriveClient.Action = "UCG_Nitro"

local MOTORS = { "MotorRL", "MotorRR", "MotorFL", "MotorFR" }
local STEERS = { "SteerFL", "SteerFR" }
local MOTOR_CLASSES = { HingeConstraint = true, CylindricalConstraint = true }
local STEER_CLASSES = { HingeConstraint = true, CylindricalConstraint = true }

local player = Players.LocalPlayer
local UI, Remote, ctx
local started = false
local gui, refs = nil, {}

local drive = nil -- { seat, model, motors = {{c, dir}}, steers = {{c, dir}}, baseTorque, last = {} }
local cachedChar, cachedHum
local lastNitroSent = -math.huge
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
local function ownerModel(seat)
	local node = seat.Parent
	while node and node ~= workspace do
		if node:IsA("Model") and node:GetAttribute("OwnerUserId") ~= nil then
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

	-- Tacho oben mittig (unten liegen 2.4.0-HUD, Stick und Sprungknopf; Toasts beginnen bei y 62)
	local panel = UI.Frame(gui, {
		Name = "Tacho", BackgroundColor3 = T.bg, BackgroundTransparency = 0.12, AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 4), Size = UDim2.new(0, 200, 0, 54),
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
end

local function setSide(visible)
	refs.side.Visible = visible
	refs.panel.Size = UDim2.new(0, visible and 324 or 200, 0, 54)
end

---------------------------------------------------------------- Nitro
local function nitroState(model, now)
	local level = model and model:GetAttribute("Nitro")
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

---------------------------------------------------------------- Ein-/Aussteigen
local function enter(seat, model)
	local folder = model:FindFirstChild("Drive")
	local d = { seat = seat, model = model, motors = {}, steers = {} }
	for _, name in ipairs(MOTORS) do
		local e = resolve(folder, model, name, MOTOR_CLASSES)
		if e then
			e.last = {}
			table.insert(d.motors, e)
		end
	end
	for _, name in ipairs(STEERS) do
		local e = resolve(folder, model, name, STEER_CLASSES)
		if e then
			e.last = {}
			table.insert(d.steers, e)
		end
	end
	-- Grundmoment: Attribut Torque, sonst was der Server am ersten Motor eingestellt hat
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
	if not d then
		return
	end
	-- Parkbremse: Räder halten, Lenkung gerade
	for _, m in ipairs(d.motors) do
		set(m, "AngularVelocity", 0)
		if d.baseTorque > 0 then
			set(m, "MotorMaxTorque", d.baseTorque)
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
	local topSpeed = num(model:GetAttribute("TopSpeed")) or num(seat.MaxSpeed) or 60
	local radius = num(model:GetAttribute("WheelRadius")) or DriveClient.WheelRadius
	local steerMax = num(model:GetAttribute("SteerAngle")) or DriveClient.SteerAngle
	local torque = d.baseTorque

	local velocity = seat.AssemblyLinearVelocity
	local forward = seat.CFrame.LookVector
	local fwd = velocity:Dot(forward)

	local maxFwd = topSpeed * boost
	local maxRev = topSpeed * DriveClient.ReverseFactor
	local target, motorTorque
	if throttle > 0.05 then
		if fwd < -2 then
			target, motorTorque = 0, torque * DriveClient.BrakeFactor -- rollt rückwärts: erst bremsen
		else
			target, motorTorque = maxFwd * throttle, torque * boost
		end
	elseif throttle < -0.05 then
		if fwd > 2 then
			target, motorTorque = 0, torque * DriveClient.BrakeFactor -- fährt vorwärts: bremsen
		else
			target, motorTorque = -maxRev * -throttle, torque
		end
	elseif math.abs(fwd) < 1 then
		target, motorTorque = 0, torque -- steht: halten
	else
		target, motorTorque = 0, torque * DriveClient.CoastFactor -- rollen lassen, leichte Motorbremse
	end
	local angular = target / math.max(0.1, radius)
	for _, m in ipairs(d.motors) do
		set(m, "AngularVelocity", angular * m.dir)
		if torque > 0 then
			set(m, "MotorMaxTorque", motorTorque)
		end
	end
	local speedRatio = math.clamp(math.abs(fwd) / math.max(1, topSpeed), 0, 1)
	local angle = -steer * steerMax * (1 - (1 - DriveClient.HighSpeedSteer) * speedRatio)
	for _, s in ipairs(d.steers) do
		set(s, "TargetAngle", angle * s.dir)
	end

	-- Anzeige-Werte
	local speed = math.abs(fwd)
	shownSpeed += (speed - shownSpeed) * math.clamp(dt * 8, 0, 1)
	local gears = math.max(1, math.floor(num(model:GetAttribute("Gears")) or 6))
	local gear
	if fwd < -1 then
		gear = "R"
	elseif speed < 0.5 and math.abs(throttle) < 0.05 then
		gear = "N"
	else
		gear = tostring(math.clamp(1 + math.floor(speed / math.max(1, topSpeed) * gears), 1, gears))
	end
	info.speed = speed
	info.kmh = math.floor(shownSpeed * DriveClient.KmhPerStud + 0.5)
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
		local dur = num(d.model:GetAttribute("NitroDuration")) or 3
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
	if track.active then
		setSide(true)
		refs.sideTime.Text = lapTime(now - track.startedAt)
		refs.sideTime.TextColor3 = T.text
		refs.sideSub.Text = track.total > 0 and ("Checkpoint " .. track.index .. "/" .. track.total) or "Zeitfahren"
	elseif result and os.clock() < result.untilClock then
		setSide(true)
		if result.cancelled then
			refs.sideTime.Text = "Abbruch"
			refs.sideTime.TextColor3 = T.red
			refs.sideSub.Text = "Zeitfahren beendet"
		else
			refs.sideTime.Text = lapTimeFine(result.time)
			refs.sideTime.TextColor3 = result.newBest and T.green or T.text
			refs.sideSub.Text = result.newBest and "Neue Bestzeit!" or (result.best and ("Bestzeit " .. lapTimeFine(result.best)) or "Ziel")
		end
	elseif d.model:GetAttribute("TestDrive") == true then
		local ends = num(d.model:GetAttribute("ExpiresAt"))
		setSide(true)
		refs.sideTime.Text = ends and countdown(ends - now) or "–"
		refs.sideTime.TextColor3 = ends and ends - now < 10 and T.red or T.text
		refs.sideSub.Text = "Probefahrt"
	else
		setSide(false)
	end
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
		if model and model:GetAttribute("OwnerUserId") == player.UserId then
			enter(seat, model)
		end
	end
	if drive then
		control(drive, dt)
		render(drive)
	end
end

---------------------------------------------------------------- Server-Hinweise und Snapshot
-- mini_notice: track_start {startedAt, total}, track_checkpoint {index, total, time}, track_finish {time, best,
-- newBest, reward}, track_cancel. Gleiche Tabelle zweimal (z. B. über TrackUI weitergereicht) wirkt einmal.
function DriveClient.OnNotice(data)
	if type(data) ~= "table" or data == lastNotice then
		return
	end
	lastNotice = data
	local kind = data.kind
	if kind == "track_start" then
		track.active = true
		track.startedAt = num(data.startedAt) or serverNow()
		track.index = 0
		track.total = num(data.total) or track.total
		track.localSince = os.clock()
		result = nil
	elseif kind == "track_checkpoint" then
		if not track.active then
			track.active = true
			track.startedAt = num(data.startedAt) or (serverNow() - (num(data.time) or 0))
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
	elseif kind == "track_cancel" or kind == "track_abort" then
		track.active = false
		result = { cancelled = true, untilClock = os.clock() + 4 }
	end
end

-- Snapshot-Feld track {active, startedAt, checkpoint, total}: hält die Anzeige nach einem Rejoin/Lag im Takt
function DriveClient.OnSnapshot(s)
	local tr = type(s) == "table" and s.track
	if type(tr) ~= "table" then
		return
	end
	if tr.active == true and num(tr.startedAt) then
		if not track.active then
			track.localSince = os.clock()
			result = nil
		end
		track.active = true
		track.startedAt = num(tr.startedAt)
		track.index = num(tr.checkpoint) or num(tr.index) or track.index
		track.total = num(tr.total) or track.total
	elseif tr.active == false and track.active and os.clock() - track.localSince > 2 then
		track.active = false
	end
end

-- Zustand des Zeitfahrens (für TrackUI): {active, startedAt, index, total, elapsed, result}
function DriveClient.Track()
	return {
		active = track.active,
		startedAt = track.startedAt,
		index = track.index,
		total = track.total,
		elapsed = track.active and math.max(0, serverNow() - track.startedAt) or 0,
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
function DriveClient.Start(c)
	if started then
		return
	end
	started = true
	ctx = type(c) == "table" and c or {}
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
			warn("[Fahren] " .. tostring(err))
		end
	end)
end

function DriveClient.Gui()
	return gui, refs
end

return DriveClient
