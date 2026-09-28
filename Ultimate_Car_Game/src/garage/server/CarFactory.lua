local ServerStorage = game:GetService("ServerStorage")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local Config = require(Shared.Config)
local Factory = {}

function Factory.Spawn(def, bay, userId, parent, jobId)
    local template = ServerStorage.CarTemplates:FindFirstChild(def.body)
    assert(template, "Missing car template: " .. def.body)
    local car = template:Clone()
    car.Name = jobId or ("Kundenauto_" .. userId)
    car:SetAttribute("OwnerUserId", userId)
    car:SetAttribute("JobId", jobId)
    for _, part in ipairs(car:GetDescendants()) do
        if part:IsA("BasePart") and (part.Name == "Paint" or part.Name == "Hood" or part.Name == "Mirror") then
            part.Color = Color3.fromRGB(def.color[1], def.color[2], def.color[3])
        end
    end
    car:PivotTo(bay.CarOrigin.CFrame)
    car.Parent = parent
    Factory.SetHood(car, false)
    return car
end

function Factory.SetHood(car, open)
    local hood = car:FindFirstChild("Hood")
    if not hood then return end
    local root = car.PrimaryPart.CFrame
    hood.CFrame = root * CFrame.new(0, 3.9, -3.55) * CFrame.Angles(open and math.rad(65) or 0, 0, 0) * CFrame.new(0,0,-1.95)
end

function Factory.AddPrompt(part, callback)
    local prompt = Instance.new("ProximityPrompt")
    prompt.Name = "WorkPrompt"
    prompt.ActionText = "Arbeiten"
    prompt.ObjectText = "Kundenauto"
    prompt.MaxActivationDistance = 8
    prompt.HoldDuration = 0.12
    prompt.Exclusivity = Enum.ProximityPromptExclusivity.OnePerButton
    prompt.Style = Enum.ProximityPromptStyle.Custom
    prompt:SetAttribute("VehicleAction","work")
    prompt.RequiresLineOfSight = false
    prompt.ClickablePrompt = true
    prompt.KeyboardKeyCode = Enum.KeyCode.E
    prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
    prompt.Enabled = false
    prompt.Parent = part
    prompt.Triggered:Connect(callback)
    return prompt
end

local function visible(car, prefix, show)
    for _, part in ipairs(car:GetDescendants()) do
        if part:IsA("BasePart") and part.Name:sub(1, #prefix) == prefix and part.Name:sub(-5)~="Point" then
            part.Transparency = show and 0 or 1
            part.CanCollide = show
            part.CanQuery = show
        end
    end
end
function Factory.TargetParts(car,job)
    if job.phase=="diagnose" or job.phase=="verify" then return {car:FindFirstChild("OBDPort")} end
    local step=Config.JobById[job.kind].steps[job.step]
    if not step then return {} end
    if step.part=="filter" then return {car.OilFilter,car.OilPan} end
    if step.point=="OilPort" then return {car.OilPan,car.DrainBolt,car.Turbo} end
    if step.point=="BatteryPoint" then return {car.Battery,car.EngineBayFloor} end
    if step.point=="WheelPoint" then return {car.WheelFLTire,car.WheelFLRim,car.BrakeFL} end
    if step.point=="DiagnosticPoint" then return {car:FindFirstChild("OBDPort")} end
    if step.point=="EnginePoint" then return {car.Engine,car.Ignition,car.Hose,car.EngineBayFloor} end
    return {}
end

function Factory.Effect(car, effect)
    if effect == "wheelOut" or effect == "frontOut" then visible(car, "WheelFL", false) end
    if effect == "frontOut" then visible(car, "WheelFR", false) end
    if effect == "wheelIn" or effect == "frontIn" then visible(car, "WheelFL", true) end
    if effect == "frontIn" then visible(car, "WheelFR", true) end
    if effect == "batteryOut" then visible(car, "Battery", false) end
    if effect == "batteryIn" then visible(car, "Battery", true); car.Battery.Color = Color3.fromRGB(70, 172, 132) end
    if effect == "coilOut" then visible(car, "Ignition", false) end
    if effect == "coilIn" then visible(car, "Ignition", true); car.Ignition.Color = Color3.fromRGB(75, 176, 132) end
    if effect == "hoseOut" then visible(car, "Hose", false) end
    if effect == "hoseIn" then visible(car, "Hose", true); car.Hose.Color = Color3.fromRGB(56, 153, 194) end
    if effect == "filter" then car.OilFilter.Color = Color3.fromRGB(241, 186, 69) end
    if effect == "brakes" then
        car.BrakeFL.Color = Color3.fromRGB(220, 229, 236)
        car.BrakeFR.Color = Color3.fromRGB(220, 229, 236)
    end
    if effect == "turboOut" then visible(car,"Turbo",false) end
    if effect == "turboIn" then visible(car,"Turbo",true) end
    if effect == "drain" then car.OilPan.Color=Color3.fromRGB(88,97,105) end
end

function Factory.Equip(player, toolId)
    local character = player.Character
    if not character then return end
    local previous = character:FindFirstChild("GarageTool")
    if previous then previous:Destroy() end
    local hand = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
    if not hand then return end
    local tool = Instance.new("Model")
    tool.Name = "GarageTool"
    tool:SetAttribute("ToolId",toolId)
    local color = Config.Tools[toolId].color
    local handle = Instance.new("Part")
    handle.Name = "Handle"
    handle.Size = Vector3.new(0.16,1.3,0.16)
    if toolId=="scanner" then handle.Size=Vector3.new(0.94,1.24,0.28)
    elseif toolId=="meter" then handle.Size=Vector3.new(0.65,0.95,0.22)
    elseif toolId=="oil" then handle.Size=Vector3.new(1.05,1.2,0.52)
    elseif toolId=="tire" or toolId=="torque" then handle.Size=Vector3.new(0.18,1.65,0.16)
    elseif toolId=="screwdriver" then handle.Size=Vector3.new(0.11,1.2,0.11)
    elseif toolId=="lamp" then handle.Size=Vector3.new(0.25,0.65,0.22) end
    handle.Color = Color3.fromRGB(color[1], color[2], color[3])
    handle.Material = Enum.Material.SmoothPlastic
    handle.CanCollide = false
    handle.CanTouch = false
    handle.CanQuery = false
    handle.Massless = true
    local attachment=hand:FindFirstChild("RightGripAttachment")
    local handGrip=attachment and attachment.CFrame or CFrame.new(0,-hand.Size.Y/2,0)
    local offset=CFrame.Angles(math.rad(-65),0,0)*CFrame.new(0,0.38,0)
    if toolId=="scanner" or toolId=="ratchet" or toolId=="oil" then
        -- Use the attachment's palm position, not its rig-specific tool rotation.
        -- These models are built upright along local Y (R6 and R15 alike).
        handGrip=CFrame.new(handGrip.Position)
    end
    if toolId=="scanner" then
        offset=CFrame.new(0,0,-hand.Size.Z/2-0.04)*CFrame.Angles(math.rad(-55),math.pi,0)*CFrame.new(0,0.4,-0.14)
    elseif toolId=="meter" then
        offset=CFrame.new(0,0.05,-0.28)*CFrame.Angles(math.rad(-25),math.pi,0)
    elseif toolId=="ratchet" then
        offset=CFrame.new(0,-0.02,-hand.Size.Z/2-0.04)*CFrame.Angles(math.rad(-45),0,0)*CFrame.new(0,0.36,0)
    elseif toolId=="oil" then
        offset=CFrame.new(0,0,-0.18)*CFrame.Angles(math.rad(-5),math.pi,0)*CFrame.new(0,-0.79,0)
    elseif toolId=="lamp" then offset=CFrame.Angles(math.rad(-45),0,0)*CFrame.new(0,0.18,0) end
    handle.CFrame=hand.CFrame*handGrip*offset
    handle.Parent = tool
    local weld = Instance.new("Weld")
    weld.Name="ToolGrip"
    weld.C0=handGrip*offset
    weld.Part0 = hand
    weld.Part1 = handle
    weld.Parent = handle
    local function detail(name,size,offset,rgb,shape)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.Color=Color3.fromRGB(rgb[1],rgb[2],rgb[3]);p.Material=Enum.Material.SmoothPlastic
        p.Massless=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
        if shape then p.Shape=shape end
        p.CFrame=handle.CFrame*offset;p.Parent=tool
        local link=Instance.new("WeldConstraint");link.Part0=handle;link.Part1=p;link.Parent=p
        return p
    end
    if toolId=="meter" then
        -- Keep the existing multimeter geometry exactly; only its hand grip changed.
        local screen=detail("Screen",Vector3.new(0.52,0.45,0.025),CFrame.new(0,0.12,-0.125),{23,55,59})
        local surface=Instance.new("SurfaceGui");surface.Face=Enum.NormalId.Front;surface.CanvasSize=Vector2.new(240,160);surface.Parent=screen
        local readout=Instance.new("TextLabel");readout.Name="Readout";readout.Size=UDim2.fromScale(1,1);readout.BackgroundTransparency=1;readout.Text="0.00 V";readout.TextColor3=Color3.fromRGB(86,241,177);readout.TextScaled=true;readout.Font=Enum.Font.Code;readout.Parent=surface
        for i=-1,1 do detail("Key",Vector3.new(0.09,0.09,0.025),CFrame.new(i*0.16,-0.25,-0.13),{37,45,57}) end
        detail("RedProbe",Vector3.new(0.06,0.65,0.06),CFrame.new(0.42,-0.2,0),{219,62,72})
        detail("BlackProbe",Vector3.new(0.06,0.65,0.06),CFrame.new(-0.42,-0.2,0),{25,30,37})
    elseif toolId=="scanner" then
        detail("RubberCase",Vector3.new(1.02,1.32,0.24),CFrame.new(0,0,0.025),{28,40,46})
        local screen=detail("Screen",Vector3.new(0.76,0.64,0.04),CFrame.new(0,0.18,-0.16),{16,47,54})
        local surface=Instance.new("SurfaceGui");surface.Face=Enum.NormalId.Front;surface.CanvasSize=Vector2.new(285,240);surface.Parent=screen
        local readout=Instance.new("TextLabel");readout.Name="Readout";readout.Size=UDim2.fromScale(1,1);readout.BackgroundTransparency=1;readout.Text="OBD READY";readout.TextColor3=Color3.fromRGB(90,238,190);readout.TextScaled=true;readout.Font=Enum.Font.Code;readout.Parent=surface
        for i=-1,1 do detail("Key",Vector3.new(0.14,0.12,0.05),CFrame.new(i*0.24,-0.33,-0.17),{70,192,189}) end
        detail("Connector",Vector3.new(0.35,0.16,0.18),CFrame.new(0,0.72,0),{39,44,49})
        detail("Cable",Vector3.new(0.08,0.38,0.08),CFrame.new(0.08,0.93,0)*CFrame.Angles(0,0,-0.4),{28,31,35})
        detail("OBDPlug",Vector3.new(0.34,0.22,0.18),CFrame.new(0.18,1.16,0),{46,51,58})
    elseif toolId=="ratchet" or toolId=="torque" then
        handle.Material=Enum.Material.Metal;handle.Color=Color3.fromRGB(188,204,215)
        local y=toolId=="torque" and 0.87 or 0.69
        local head=detail("RatchetHead",Vector3.new(0.18,0.48,0.48),CFrame.new(0,y,0)*CFrame.Angles(0,math.pi/2,0),{184,199,210},Enum.PartType.Cylinder);head.Material=Enum.Material.Metal
        detail("Socket",Vector3.new(0.34,0.23,0.23),CFrame.new(0,y,-0.25)*CFrame.Angles(0,math.pi/2,0),{203,213,223},Enum.PartType.Cylinder)
        detail("DirectionSwitch",Vector3.new(0.13,0.07,0.08),CFrame.new(0,y,0.12),{40,54,64})
        detail("Grip",Vector3.new(0.29,0.64,0.28),CFrame.new(0,-0.36,0),toolId=="torque" and {47,131,180} or {38,55,66})
        for i=1,4 do detail("GripBand",Vector3.new(0.30,0.035,0.29),CFrame.new(0,-0.64+i*0.12,0),{28,37,43}) end
        if toolId=="ratchet" then
            local release=detail("QuickRelease",Vector3.new(0.045,0.18,0.18),CFrame.new(0,y,0.12)*CFrame.Angles(0,math.pi/2,0),{226,234,238},Enum.PartType.Cylinder)
            release.Material=Enum.Material.Metal
            local neck=detail("PolishedNeck",Vector3.new(0.22,0.27,0.17),CFrame.new(0,0.43,0),{207,220,229});neck.Material=Enum.Material.Metal
        end
        if toolId=="torque" then detail("TorqueScale",Vector3.new(0.2,0.3,0.04),CFrame.new(0,0.13,-0.10),{239,220,158}) end
    elseif toolId=="oil" then
        detail("HandleLeft",Vector3.new(0.12,0.27,0.18),CFrame.new(-0.2,0.66,0),{47,53,58})
        detail("HandleRight",Vector3.new(0.12,0.27,0.18),CFrame.new(0.2,0.66,0),{47,53,58})
        detail("CarryHandle",Vector3.new(0.5,0.13,0.18),CFrame.new(0,0.79,0),{47,53,58})
        detail("Spout",Vector3.new(0.18,0.55,0.18),CFrame.new(0.45,0.6,0)*CFrame.Angles(0,0,-0.65),{237,195,71})
        detail("Cap",Vector3.new(0.25,0.12,0.25),CFrame.new(0.61,0.83,0)*CFrame.Angles(0,0,-0.65),{35,40,47})
        local label=detail("OilLabel",Vector3.new(0.7,0.55,0.03),CFrame.new(0,-0.06,-0.28),{35,74,89})
        local surface=Instance.new("SurfaceGui");surface.Face=Enum.NormalId.Front;surface.CanvasSize=Vector2.new(280,220);surface.Parent=label
        local title=Instance.new("TextLabel");title.Name="OilTitle";title.Size=UDim2.fromScale(1,1);title.BackgroundTransparency=1
        title.Text="Öl";title.TextColor3=Color3.fromRGB(255,235,164);title.TextScaled=true;title.Font=Enum.Font.GothamBold;title.Parent=surface
    elseif toolId=="tire" then
        handle.Material=Enum.Material.Metal;handle.Color=Color3.fromRGB(177,192,204)
        detail("CurvedNeck",Vector3.new(0.18,0.36,0.14),CFrame.new(0,0.88,-0.08)*CFrame.Angles(-0.55,0,0),{190,202,212})
        detail("PryTip",Vector3.new(0.38,0.25,0.08),CFrame.new(0,1.10,-0.16),{194,203,213})
        detail("Grip",Vector3.new(0.29,0.65,0.28),CFrame.new(0,-0.38,0),{92,73,133})
    elseif toolId=="screwdriver" then
        handle.Material=Enum.Material.Metal;handle.Color=Color3.fromRGB(196,208,215)
        detail("Grip",Vector3.new(0.32,0.6,0.32),CFrame.new(0,-0.35,0),{215,68,58})
        detail("Blade",Vector3.new(0.19,0.22,0.045),CFrame.new(0,0.66,0),{206,218,223})
    elseif toolId=="lamp" then
        detail("LampBody",Vector3.new(0.38,0.85,0.24),CFrame.new(0,0.65,0),{39,63,60})
        local lens=detail("Lens",Vector3.new(0.27,0.68,0.04),CFrame.new(0,0.66,-0.14),{223,255,236});lens.Material=Enum.Material.Neon
        local light=Instance.new("PointLight");light.Range=8;light.Brightness=0.6;light.Parent=lens
    end
    tool.Parent = character
end

function Factory.WorkEffect(car,toolId,point,duration,effect)
    local old=car:FindFirstChild("WorkEffect");if old then old:Destroy() end
    if not point then return end
    local fx=Instance.new("Model");fx.Name="WorkEffect";fx.Parent=car
    local Tween=game:GetService("TweenService")
    local function part(name,size,position,rgb,shape)
        local p=Instance.new("Part");p.Name=name;p.Size=size;p.CFrame=CFrame.new(position);p.Anchored=true;p.CanCollide=false;p.CanQuery=false;p.CanTouch=false
        p.Material=Enum.Material.Neon;p.Color=Color3.fromRGB(rgb[1],rgb[2],rgb[3]);if shape then p.Shape=shape end;p.Parent=fx;return p
    end
    if toolId=="oil" then
        local origin=effect=="drain" and car.OilPan.Position or point.Position+Vector3.new(0,0.6,0)
        local stream=part("OilStream",Vector3.new(0.13,1.7,0.13),origin-Vector3.new(0,0.85,0),effect=="drain" and {87, 60,35} or {224,177,57})
        stream.Material=Enum.Material.SmoothPlastic
        Tween:Create(stream,TweenInfo.new(duration),{Transparency=0.7}):Play()
    elseif toolId=="tire" then
        -- 3.0: Versatz zur Fahrzeugseite im Fahrzeugsystem statt entlang der Welt-X-Achse (gedrehte Grundstücke).
        local root=car:GetPivot();local side=root*Vector3.new(-1,0,0)-root.Position
        local wheel=part("RotatingWheel",Vector3.new(0.7,2.2,2.2),point.Position+side,{49,55,65},Enum.PartType.Cylinder)
        wheel.Material=Enum.Material.SmoothPlastic
        local spoke=part("WheelStripe",Vector3.new(0.08,1.8,0.12),wheel.Position+side*0.4,{203,218,224}) -- 3.0: side statt Welt-X
        spoke.Anchored=false;spoke.Massless=true
        local link=Instance.new("WeldConstraint");link.Part0=wheel;link.Part1=spoke;link.Parent=spoke
        Tween:Create(wheel,TweenInfo.new(math.min(2,duration),Enum.EasingStyle.Linear,Enum.EasingDirection.InOut,2),{CFrame=wheel.CFrame*CFrame.Angles(math.pi,0,0)}):Play()
    elseif toolId=="ratchet" or toolId=="torque" or toolId=="screwdriver" then
        local socket=part("TurningSocket",Vector3.new(0.2,0.75,0.2),point.Position,{202,213,220})
        Tween:Create(socket,TweenInfo.new(0.22,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,math.floor(duration/0.44),true),{CFrame=socket.CFrame*CFrame.Angles(0,0,0.8)}):Play()
    else
        local orb=part("TestPulse",Vector3.new(0.4,0.4,0.4),point.Position,toolId=="scanner" and {67,222,211} or {249,206,83},Enum.PartType.Ball)
        Tween:Create(orb,TweenInfo.new(0.4,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut,math.floor(duration/0.8),true),{Size=Vector3.new(0.85,0.85,0.85),Transparency=0.65}):Play()
    end
    task.delay(duration+0.1,function() if fx.Parent then fx:Destroy() end end)
end

return Factory
