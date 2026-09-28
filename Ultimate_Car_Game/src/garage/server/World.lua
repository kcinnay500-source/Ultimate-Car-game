local SS=game:GetService("ServerStorage")
local TweenService=game:GetService("TweenService")
local C=require(game:GetService("ReplicatedStorage").GarageShared.Config)
local R=require(game:GetService("ReplicatedStorage").GarageShared.Rules)
local F=require(script.Parent.CarFactory)
local W={plots={},slots={}}
local template=workspace:WaitForChild("Werkstatt"):Clone()
template.Name="PlotTemplate";template.Parent=SS
workspace.Werkstatt:Destroy()
local folder=Instance.new("Folder");folder.Name="PlayerWorkshops";folder.Parent=workspace
local function clear(parent) for _,v in ipairs(parent:GetChildren()) do v:Destroy() end end
local function label(model,text)
    local gui=model:FindFirstChildWhichIsA("SurfaceGui",true)
    if gui then local t=gui:FindFirstChildWhichIsA("TextLabel",true);if t then t.Text=text end end
end
local function bindBay(w,bay)
    local prompt=bay.LiftControl:FindFirstChildOfClass("ProximityPrompt")
    if prompt then
        prompt.Style=Enum.ProximityPromptStyle.Custom;prompt.MaxActivationDistance=8;prompt:SetAttribute("VehicleAction","lift")
        prompt.Triggered:Connect(function(p) if p==w.owner then w.callback("lift",tonumber(bay.Name:match("%d+"))) end end)
    end
end
local function layout(w,d)
    if w.stage~=d.bays then
        for i=2,d.bays do
            if not W.Bay(w,i) then
                local section=SS.WorkshopExtensions["Stage_"..i]:Clone()
                section:PivotTo(w.model:GetPivot());section.Parent=w.model.Extensions
                local bay=section["Bay_"..i];bay.Parent=w.model.Bays;bindBay(w,bay)
            end
        end
        w.model.EndWall:PivotTo(w.model:GetPivot()*CFrame.new(-32+(d.bays-1)*22,0,0))
        local point=w.model:FindFirstChild("ExpansionPoint")
        if point then
            if d.bays>=C.MaxBays then point:Destroy()
            else point:PivotTo(w.model:GetPivot()*CFrame.new((d.bays-1)*22,0,0)) end
        end
        w.stage=d.bays
    end
    local point=w.model:FindFirstChild("ExpansionPoint")
    if point then
        local cost=R.UpgradeCost(d,"bays");local level=C.BayLevels[d.bays+1]
        local ready=d.money>=cost and d.level>=level
        local status=d.money<cost and "Es fehlen "..math.ceil(cost-d.money).." Cr" or "Guthaben reicht"
        status=status..(d.level<level and " · ab Level "..level or " · E zum Kaufdialog")
        label(point.Sign,"HALLENANBAU + BÜHNE "..(d.bays+1).."\n"..cost.." Cr · Guthaben "..math.floor(d.money).." Cr\n"..status)
        point.Activate.ProximityPrompt.ObjectText="Anbau + Bühne "..(d.bays+1).." · "..cost.." Cr"
        point.Ring.Color=ready and Color3.fromRGB(62,217,166) or Color3.fromRGB(247,176,63)
    end
end
function W.Create(player,callback)
    local slot;for i=1,C.MaxPlots do if not W.slots[i] then slot=i;break end end
    if not slot then return end
    W.slots[slot]=player
    local model=template:Clone();model.Name="Plot_"..player.UserId;model:SetAttribute("OwnerUserId",player.UserId)
    -- 3.0: Grundstück aus C.PlotSlots (x, z, rot in Grad); ohne Eintrag gilt das 2.4.0-Raster.
    local s=C.PlotSlots and C.PlotSlots[slot]
    local pivot=s and CFrame.new(s.x,0,s.z)*CFrame.Angles(0,math.rad(s.rot or 0),0) or CFrame.new(((slot-1)%4)*330,0,math.floor((slot-1)/4)*260)
    model:PivotTo(pivot);model.Parent=folder
    -- 3.0: Gibt es den globalen Stadt-Spawn, bleibt er der einzige; die Plot-Spawns sind aus.
    local city=workspace:FindFirstChild("City");local start=model:FindFirstChild("Start")
    if city and city:FindFirstChild("CitySpawn") and start and start:IsA("SpawnLocation") then start.Enabled=false end
    local w={model=model,slot=slot,cars={},callback=callback,owner=player,doorOpen=true};W.plots[player]=w
    model.RollerDoor:SetAttribute("Open",true)
    model.RollerDoor.Control.ProximityPrompt.Triggered:Connect(function(p) if p==player then callback("door") end end)
    for _,station in ipairs(model.Stations:GetChildren()) do
        local prompt=station:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt.Triggered:Connect(function(p) if p==player then callback("station",station.Name) end end) end
    end
    for _,bay in ipairs(model.Bays:GetChildren()) do bindBay(w,bay) end
    model.ExpansionPoint.Activate.ProximityPrompt.Triggered:Connect(function(p) if p==player then callback("expand") end end)
    local yard=model:FindFirstChild("YardActivities")
    if yard then for _,point in ipairs(yard:GetChildren()) do
        local prompt=point:FindFirstChildOfClass("ProximityPrompt")
        if prompt then prompt.Triggered:Connect(function(p) if p==player then callback("yard",point.Name) end end) end
    end end
    return w
end
function W.Bay(w,index) return w.model.Bays:FindFirstChild("Bay_"..index) end
local function doorwayOccupied(w)
    -- 3.0: im Plotsystem gerechnet, damit gedrehte Grundstücke (rot=180) dieselbe Torzone prüfen.
    local toPlot=w.model:GetPivot():Inverse()
    local origin=toPlot*w.model.RollerDoor.ClosedOrigin.Position
    for _,player in ipairs(game:GetService("Players"):GetPlayers()) do
        local character=player.Character;local root=character and character:FindFirstChild("HumanoidRootPart")
        if root then
            local delta=toPlot*root.Position-origin
            if math.abs(delta.X)<11 and math.abs(delta.Z)<2 and math.abs(delta.Y)<7 then return true end
        end
    end
    return false
end
function W.RollDoor(w,done)
    if w.doorMoving then return false,"Warte, bis das Rolltor stillsteht." end
    local opening=not w.doorOpen
    if not opening and doorwayOccupied(w) then return false,"Der Torbereich ist belegt." end
    local door=w.model.RollerDoor;local panel=door.Panel;local prompt=door.Control.ProximityPrompt
    w.doorMoving=true;prompt.Enabled=false;panel.CanCollide=false
    local height=opening and 0.3 or 11.8
    local target=door.ClosedOrigin.CFrame*CFrame.new(0,(11.8-height)/2,0)
    local tween=TweenService:Create(panel,TweenInfo.new(1.8,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Size=Vector3.new(19.8,height,0.25),CFrame=target})
    w.doorTween=tween
    local link
    link=tween.Completed:Connect(function(result)
        link:Disconnect()
        if w.doorTween~=tween or result~=Enum.PlaybackState.Completed or not w.model.Parent then return end
        w.doorTween=nil;w.doorMoving=false;w.doorOpen=opening
        if not opening and doorwayOccupied(w) then
            W.RollDoor(w,done);return
        end
        panel.CanCollide=not opening;door:SetAttribute("Open",opening)
        prompt.ActionText=opening and "Rolltor schließen" or "Rolltor öffnen";prompt.Enabled=true
        if done then done() end
    end)
    tween:Play();return true
end
function W.SafeArrival(w,target)
    for _,v in pairs(w.cars) do
        if target:IsDescendantOf(v.model) or target:IsDescendantOf(v.bay) then
            local arrival=v.bay:FindFirstChild("PlayerArrival")
            local pos=arrival and arrival.Position or (v.origin*CFrame.new(-6.4,3.5,6)).Position
            local toward=Vector3.new(v.origin.Position.X,pos.Y,v.origin.Position.Z)
            return CFrame.lookAt(pos,toward)
        end
    end
end
function W.Spawn(w,job)
    if w.cars[job.id] then return w.cars[job.id] end
    local bay=W.Bay(w,job.bay)
    local car=F.Spawn(C.CarById[job.carId],bay,w.owner.UserId,w.model.ActiveCars,job.id)
    local v={model=car,bay=bay,lifted=false,hood=false,moving=false,origin=bay.CarOrigin.CFrame,liftOrigin=bay.MovingLift:GetPivot()}
    w.cars[job.id]=v
    local def=C.JobById[job.kind]
    local completed=job.step-1+(job.phase=="working" and 1 or 0)
    for i=1,math.min(completed,#def.steps) do F.Effect(car,def.steps[i].effect) end
    for _,key in ipairs({"DiagnosticPoint","EnginePoint","BatteryPoint","WheelPoint","OilPort"}) do
        local prompt=F.AddPrompt(car[key],function(p) if p==w.owner then w.callback("work",job.id,key) end end)
        prompt:SetAttribute("JobId",job.id)
    end
    local hood=F.AddPrompt(car.HoodPoint,function(p) if p==w.owner then w.callback("hood",job.id) end end)
    hood.Name="HoodPrompt";hood.ActionText="Motorhaube öffnen";hood.Enabled=true
    hood.KeyboardKeyCode=Enum.KeyCode.H;hood.GamepadKeyCode=Enum.KeyCode.ButtonY
    hood:SetAttribute("VehicleAction","hood");hood:SetAttribute("JobId",job.id)
    return v
end
function W.Remove(w,id)
    local v=w.cars[id];if not v then return end
    w.cars[id]=nil
    if v.tween then v.tween:Cancel() end
    if v.link then v.link:Disconnect() end
    if v.value then v.value:Destroy() end
    v.bay.MovingLift:PivotTo(v.liftOrigin);v.model:Destroy()
end
function W.Hood(v)
    if v.moving then return false end
    v.hood=not v.hood;F.SetHood(v.model,v.hood);return true
end
function W.Lift(w,id,done)
    local v=w.cars[id];if not v or v.moving then return false end
    v.moving=true
    local value=Instance.new("NumberValue");v.value=value;value.Value=v.lifted and C.LiftHeight or 0
    local target=v.lifted and 0 or C.LiftHeight
    v.link=value.Changed:Connect(function(y)
        if w.cars[id]~=v then return end
        v.model:PivotTo(v.origin+Vector3.new(0,y,0));v.bay.MovingLift:PivotTo(v.liftOrigin+Vector3.new(0,y,0));F.SetHood(v.model,v.hood)
    end)
    v.tween=TweenService:Create(value,TweenInfo.new(2,Enum.EasingStyle.Sine,Enum.EasingDirection.InOut),{Value=target})
    v.tween.Completed:Connect(function()
        if w.cars[id]~=v then return end
        v.link:Disconnect();value:Destroy();v.value=nil;v.link=nil;v.tween=nil
        v.lifted=target>0;v.moving=false;done()
    end)
    v.tween:Play();return true
end
function W.Objective(w,job)
    if not job then return "Nimm am Empfang einen Auftrag an.",w.model.Stations.workshop end
    local v=w.cars[job.id];if not v then return "",nil end
    local step=C.JobById[job.kind].steps[job.step]
    if v.moving then return "Die Hebebühne bewegt sich.",v.bay.LiftControl end
    if job.phase=="working" then return "Arbeit läuft · andere Kundenautos können bearbeitet werden.",v.model.EnginePoint end
    if job.phase=="invoice" then return "Rechnung am Empfang abschließen.",w.model.Stations.workshop end
    if job.phase=="diagnose" then return "Mit dem OBD-Tester die Messwerte auslesen.",v.model.DiagnosticPoint end
    if job.phase=="verify" then
        if v.lifted then return "Bühne für die Endkontrolle absenken.",v.bay.LiftControl end
        if v.hood then return "Motorhaube für die Endkontrolle schließen.",v.model.HoodPoint end
        return "Endkontrolle mit dem OBD-Tester durchführen.",v.model.DiagnosticPoint
    end
    if step then
        if v.lifted~=step.lifted then return step.lifted and "Hebebühne anheben." or "Hebebühne absenken.",v.bay.LiftControl end
        if step.hood and not v.hood then return "Motorhaube öffnen.",v.model.HoodPoint end
        return step.name.." · "..C.Tools[step.tool].name,v.model[step.point]
    end
    return "",nil
end
function W.Sync(w,d)
    layout(w,d)
    for id in pairs(w.cars) do
        local exists=false;for _,j in ipairs(d.jobs) do if j.id==id then exists=true end end
        if not exists then W.Remove(w,id) end
    end
    for _,j in ipairs(d.jobs) do W.Spawn(w,j) end
    for i=1,d.bays do
        local bay=W.Bay(w,i)
        local name="Bühne "..i.." · frei"
        for _,j in ipairs(d.jobs) do if j.bay==i then name="Bühne "..i.." · "..C.CarById[j.carId].name end end
        label(bay.Sign,name)
        local control=bay.LiftControl:FindFirstChildOfClass("ProximityPrompt")
        if control then
            control:SetAttribute("JobId",nil)
            control.Enabled=false;control.KeyboardKeyCode=Enum.KeyCode.F;control.GamepadKeyCode=Enum.KeyCode.ButtonB
            for _,j in ipairs(d.jobs) do if j.bay==i then
                local v=w.cars[j.id];control.Enabled=not v.moving and j.phase~="working" and w.interactionJob~=j.id
                control:SetAttribute("JobId",j.id)
                control.ActionText=v.lifted and "Bühne absenken" or "Bühne anheben"
            end end
        end
    end
    for _,j in ipairs(d.jobs) do
        local v=w.cars[j.id];local _,target=W.Objective(w,j)
        local step=C.JobById[j.kind].steps[j.step]
        for _,part in ipairs(v.model:GetChildren()) do
            if part:IsA("BasePart") then part:SetAttribute("WorkPoint",nil) end
            local prompt=part:FindFirstChild("WorkPrompt")
            if prompt then
                prompt.Enabled=part==target and not v.moving and j.phase~="working" and w.interactionJob~=j.id
                prompt.ObjectText=C.CarById[j.carId].name.." · "..(C.PointNames[part.Name] or "")
                prompt.ActionText=j.phase=="diagnose" and "OBD: Diagnose öffnen" or (j.phase=="verify" and "OBD: Endkontrolle" or (step and step.name or "Arbeiten"))
            end
        end
        local hood=v.model.HoodPoint.HoodPrompt
        hood.Enabled=not v.moving and j.phase~="working" and w.interactionJob~=j.id;hood.ActionText=v.hood and "Motorhaube schließen" or "Motorhaube öffnen"
        local parts=F.TargetParts(v.model,j)
        if target and target:FindFirstChild("WorkPrompt") and not v.moving and j.phase~="working" then
            for _,part in ipairs(parts) do if part then part:SetAttribute("WorkPoint",target.Name) end end
        end
        v.model.Hood:SetAttribute("WorkPoint","HoodPoint")
        local port=v.model:FindFirstChild("OBDPort");if port then port:SetAttribute("WorkPoint","DiagnosticPoint") end
    end
end
function W.Equipment(w,d)
    for _,e in ipairs(C.Equipment) do
        local level=d.equipment[e.id] or 0
        if level>0 then
            local device=w.model.Equipment:FindFirstChild(e.id)
            if not device then
                device=SS.EquipmentTemplates[e.id]:Clone();device.Name=e.id;device.Parent=w.model.Equipment
                local lamp=Instance.new("Part");lamp.Name="LevelIndicator";lamp.Anchored=true;lamp.CanCollide=false;lamp.CanQuery=false;lamp.CanTouch=false
                lamp.Color=Color3.fromRGB(62,217,166);lamp.Material=Enum.Material.Neon;lamp.CFrame=device.PrimaryPart.CFrame*CFrame.new(1.1,2,0);lamp.Parent=device
                local mount=Instance.new("Part");mount.Name="IndicatorMount";mount.Anchored=true;mount.CanCollide=false;mount.CanQuery=false;mount.CanTouch=false;mount.Size=Vector3.new(0.12,1.6,0.12)
                mount.Color=Color3.fromRGB(100,116,124);mount.CFrame=device.PrimaryPart.CFrame*CFrame.new(1.1,1.22,0);mount.Parent=device
                local prompt=Instance.new("ProximityPrompt");prompt.Name="AssignPrompt";prompt.ActionText="Bühne zuweisen";prompt.ObjectText=e.name
                prompt.MaxActivationDistance=8;prompt.HoldDuration=0.25;prompt.RequiresLineOfSight=false;prompt.Parent=device.Badge
                prompt.Triggered:Connect(function(p) if p==w.owner then w.callback("deviceMenu",e.id) end end)
            end
            local assigned=d.equipmentBays[e.id];local bay=assigned and W.Bay(w,assigned)
            device:PivotTo(bay and bay.EquipmentSpot.CFrame or w.model.EquipmentPositions[e.id].CFrame)
            device.LevelIndicator.Size=Vector3.new(0.22,0.3+level*0.22,0.22)
            label(device,e.name.." · Stufe "..level..(assigned and " · Bühne "..assigned or " · Lager"))
            device:SetAttribute("AssignedBay",assigned)
            device:SetAttribute("EquipmentId",e.id)
        end
    end
end
function W.Deliver(w,count)
    local box=Instance.new("Part");box.Name="Teilelieferung";box.Size=Vector3.new(2.3,1.5,2);box.Color=Color3.fromRGB(175,125,66);box.Anchored=true
    box.CFrame=w.model.PartsArea.DeliveryOrigin.CFrame*CFrame.new((#w.model.PartsArea.DeliveryBoxes:GetChildren()%3)*2.5,0.75,0)
    box.Parent=w.model.PartsArea.DeliveryBoxes
    task.delay(40,function() if box.Parent then box:Destroy() end end)
end
function W.Destroy(player)
    local w=W.plots[player];if not w then return end
    if w.doorTween then local tween=w.doorTween;w.doorTween=nil;tween:Cancel() end
    for id in pairs(w.cars) do W.Remove(w,id) end
    w.model:Destroy();W.slots[w.slot]=nil;W.plots[player]=nil
end
return W
