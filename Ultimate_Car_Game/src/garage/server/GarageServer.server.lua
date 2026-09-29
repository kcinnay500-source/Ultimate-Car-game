local Players=game:GetService("Players")
local Http=game:GetService("HttpService")
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local C,R=require(Shared:WaitForChild("Config")),require(Shared:WaitForChild("Rules"))
local P,F,W=require(script.Parent.Profiles),require(script.Parent.CarFactory),require(script.Parent.World)
local Purchases=require(script.Parent.Purchases)
local Mini=require(script.Parent:WaitForChild("Mini"):WaitForChild("MiniService")) -- 3.0: Minispiele und Stadt
local RunService=game:GetService("RunService")
local Remotes=Shared:WaitForChild("Remotes")
local Command,Event=Remotes:WaitForChild("Command"),Remotes:WaitForChild("Event")
local sessions={}
local joining={}
local function now() return workspace:GetServerTimeNow() end
local Lighting=game:GetService("Lighting")
local dayEpoch=now()
Lighting.ClockTime=C.DayStartHour
local function advanceDays(p,at)
    if p.profile.transacting then return end
    local _,cycle=R.DayClock(at,dayEpoch)
    local elapsed=math.max(0,cycle-p.dayCycle)
    if elapsed>0 then p.profile.data.days=math.min(1000000000,p.profile.data.days+elapsed);p.revision=p.revision+1 end
    p.dayCycle=cycle
end
local function emit(p,kind,data) if p.player.Parent then Event:FireClient(p.player,kind,data) end end
local function toast(p,message) if message then emit(p,"toast",message) end end
local function near(p,part,distance)
    local ch=p.player.Character;local root=ch and ch:FindFirstChild("HumanoidRootPart")
    local humanoid=ch and ch:FindFirstChildOfClass("Humanoid")
    return root and humanoid and humanoid.Health>0 and part and (root.Position-part.Position).Magnitude<=(distance or 15)
end
local function station(p,key) return near(p,p.world.model.Stations:FindFirstChild(key),key=="tools" and 9 or 10) end
local function selected(p,id) return R.FindJob(p.profile.data,id or p.selected) end
local function resetInteraction(p,expected)
    local active=p.pending
    if expected and active~=expected then return false end
    p.pending=nil;p.world.interactionJob=nil
    W.Sync(p.world,p.profile.data)
    emit(p,"interactionReset",active and {token=active.token} or nil)
    return true
end
local function validateInteraction(p)
    local c=p.pending;if not c then return end
    local j=c.job and selected(p,c.job)
    local invalid=now()>c.expires or p.player.Character~=c.character or p.tool~=c.tool or not near(p,c.point,8)
    if c.job then invalid=invalid or not j or p.selected~=c.job or j.phase~=c.phase or j.step~=c.step end
    if invalid then resetInteraction(p,c) end
end
local function beginInteraction(p,c)
    c.character=p.player.Character;c.tool=p.tool
    p.confirm=nil
    p.pending=c;p.world.interactionJob=c.job
    W.Sync(p.world,p.profile.data)
    -- Register cleanup before notifying the client. Every kind has a deadline.
    task.delay(math.max(0,c.expires-now())+0.1,function()
        if sessions[p.player]==p and p.pending==c then resetInteraction(p,c) end
    end)
end
local function objectiveFor(p,job)
    local d=p.profile.data
    local objective,target=W.Objective(p.world,job)
    if job and job.phase=="repair" then
        local step=C.JobById[job.kind].steps[job.step]
        if step and step.equipment and d.equipmentBays[step.equipment]~=job.bay then
            local device=p.world.model.Equipment:FindFirstChild(step.equipment)
            objective="Stelle "..C.EquipmentById[step.equipment].name.." an Bühne "..job.bay.." bereit."
            target=device and device.Badge or p.world.model.Stations.upgrades
        end
        if step and step.part and not R.ChoosePart(d,job,step.part) then objective="Passendes Ersatzteil im Teilehandel bestellen oder eine andere Marke auswählen.";target=p.world.model.Stations.parts end
    end
    return objective,target
end
local function push(p)
    local d=p.profile.data;local job=selected(p)
    if not job then p.selected=d.jobs[1] and d.jobs[1].id;job=selected(p) end
    local objective,target=objectiveFor(p,job)
    local visuals={};for id,v in pairs(p.world.cars) do visuals[id]={lifted=v.lifted,hood=v.hood,moving=v.moving,model=v.model} end
    emit(p,"state",{data=R.Snapshot(d),revision=p.revision,selected=p.selected,tool=p.tool,objective=objective,target=target,
        time=now(),dayEpoch=dayEpoch,interaction=p.pending and {token=p.pending.token,kind=p.pending.kind,expires=p.pending.expires},neededXP=R.XPNeeded(d),shopReady=p.profile.writable and not RunService:IsStudio() and not p.profile.transacting,saveStatus=p.profile.status,visuals=visuals,plot=p.world.model})
    p.player.leaderstats.Credits.Value=math.floor(d.money);p.player.leaderstats.Level.Value=d.level
    p.lastPush=now();p.dirty=false
end
local function changed(p)
    p.revision=p.revision+1;W.Sync(p.world,p.profile.data);push(p)
end
local function messageResult(p,ok,message)
    toast(p,message);if ok then changed(p) else push(p) end
end
local function moveTo(p,part)
    if not part or not p.player.Character then return end
    -- 3.0: drehsicher im Plotsystem (6 Studs vor dem Ziel, 3,5 über dem Plotboden); ein Kind-Part
    -- "Arrival" am Ziel legt die Ankunft fest (z. B. für erhöhte Stationen).
    local plot=p.world.model:GetPivot();local here=plot:Inverse()*part.Position
    local arrival=part:FindFirstChild("Arrival")
    local destination=W.SafeArrival(p.world,part) or (arrival and arrival:IsA("BasePart") and arrival.CFrame*CFrame.new(0,3.5,0))
    local ch=p.player.Character;local root=ch:FindFirstChild("HumanoidRootPart")
    local humanoid=ch:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health<=0 then return end
    Mini.Unseat(humanoid) -- 3.0: SeatWeld sofort lösen, sonst zieht PivotTo ein gefahrenes Auto mit
    ch:PivotTo(destination or plot*CFrame.new(here.X,3.5,here.Z+6)) -- 3.0: plotlokal statt Welt-X/Z
    root.AssemblyLinearVelocity=Vector3.new();root.AssemblyAngularVelocity=Vector3.new()
end
local function jobConditions(p,j,v)
    if v.moving then return false,"Warte, bis die Bühne stillsteht." end
    local step=C.JobById[j.kind].steps[j.step]
    if not step or j.phase~="repair" then return false,"Dieser Arbeitsschritt ist gerade nicht verfügbar." end
    if v.lifted~=step.lifted then return false,step.lifted and "Hebebühne zuerst anheben." or "Hebebühne zuerst absenken." end
    if step.hood and not v.hood then return false,"Öffne zuerst die Motorhaube." end
    if not R.ToolActive(p.profile.data,p.tool) or not R.ToolMatches(step,p.tool) then return false,"Wähle das passende Werkzeug: "..C.Tools[step.tool].name end
    if step.equipment and (p.profile.data.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) then return false,"Das benötigte Gerät fehlt." end
    if step.equipment and p.profile.data.equipmentBays[step.equipment]~=j.bay then return false,"Stelle zuerst "..C.EquipmentById[step.equipment].name.." an Bühne "..j.bay.." bereit." end
    if step.equipment then
        for _,other in ipairs(p.profile.data.jobs) do
            local otherStep=C.JobById[other.kind].steps[other.step]
            if other.id~=j.id and other.phase=="working" and otherStep and otherStep.equipment==step.equipment then
                return false,"Dieses Gerät ist gerade an einem anderen Auto im Einsatz."
            end
        end
    end
    if step.part and not R.ChoosePart(p.profile.data,j,step.part) then return false,"Bestelle zuerst das passende Ersatzteil oder wähle einen vorhandenen Hersteller." end
    if not near(p,v.model[step.point],8) then return false,"Gehe zum markierten Bauteil am Fahrzeug." end
    return true
end
local function report(p,j)
    local def=C.JobById[j.kind]
    emit(p,"diagnose",{job=j.id,car=C.CarById[j.carId].name,report=def.report,answers=j.phase=="diagnose" and def.answers or {},phase=j.phase})
end
local function work(p,id,point,scanOnly)
    local j=selected(p,id);if not j then return end
    local v=p.world.cars[j.id];if not v then return end
    if p.pending then return toast(p,"Schließe zuerst die laufende Interaktion ab.") end
    p.selected=j.id
    if scanOnly or j.phase=="diagnose" or j.phase=="verify" then
        if j.phase=="working" then return toast(p,"Warte, bis der Arbeitsschritt beendet ist.") end
        if point and point~="DiagnosticPoint" then return toast(p,"Nutze den OBD-Anschluss an der Fahrerseite.") end
        if v.moving or not near(p,v.model.DiagnosticPoint,8) then return toast(p,"Gehe zum OBD-Anschluss an der Fahrerseite.") end
        if p.tool~="scanner" or not R.ToolActive(p.profile.data,"scanner") then return toast(p,"Wähle den OBD-Tester aus deiner Werkzeugleiste.") end
        if j.phase=="verify" and (v.lifted or v.hood) then return toast(p,"Senke die Bühne ab und schließe die Motorhaube.") end
        if j.scanReady and j.phase~="verify" then report(p,j);return push(p) end
        local pending={kind="scan",job=j.id,phase=j.phase,step=j.step,token=Http:GenerateGUID(false),point=v.model.DiagnosticPoint,expires=now()+3}
        beginInteraction(p,pending)
        emit(p,"scan",{duration=2.5,tool="scanner",point=v.model.DiagnosticPoint})
        F.WorkEffect(v.model,"scanner",v.model.DiagnosticPoint,2.5)
        task.delay(2.5,function()
            if sessions[p.player]~=p or p.pending~=pending then return end
            resetInteraction(p,pending)
            if p.player.Character~=pending.character or selected(p,j.id)~=j or not near(p,v.model.DiagnosticPoint,8) or v.moving or p.tool~="scanner" then
                emit(p,"interactionReset");return toast(p,"Prüfung abgebrochen: Gehe zurück zum Fahrzeug.")
            end
            if j.phase=="diagnose" then
                j.scanReady=true;report(p,j)
            elseif j.phase=="verify" and not v.lifted and not v.hood then
                j.phase="invoice";toast(p,"Endkontrolle bestanden. Rechnung am Empfang abschließen.");report(p,j)
            else report(p,j) end
            changed(p)
        end)
    elseif j.phase=="repair" then
        if point and point~=C.JobById[j.kind].steps[j.step].point then return toast(p,"Wähle das markierte Bauteil für diesen Arbeitsschritt.") end
        local ok,msg=jobConditions(p,j,v);if not ok then return toast(p,msg) end
        local c={kind="gauge",job=j.id,step=j.step,token=Http:GenerateGUID(false),startAt=now()+0.7,period=1.5,
            center=0.62,width=math.min(0.48,0.28+(p.profile.data.toolLevel-1)*0.006),expires=now()+12}
        c.phase=j.phase;c.point=v.model[C.JobById[j.kind].steps[j.step].point]
        beginInteraction(p,c);emit(p,"challenge",c)
    elseif j.phase=="invoice" then toast(p,"Hole die Vergütung am Empfang über Abrechnen ab.")
    else toast(p,"Dieser Arbeitsschritt läuft bereits.") end
    push(p)
end
local function token(p,key,job)
    p.confirm={token=Http:GenerateGUID(false),key=key,job=job,expires=now()+30}
    emit(p,"confirm",p.confirm)
end
local function expansionAccess(p)
    local point=p.world.model:FindFirstChild("ExpansionPoint")
    return station(p,"upgrades") or (point and near(p,point.Activate,10))
end
local function expansionQuote(p)
    local d=p.profile.data
    if p.pending then return toast(p,"Beende zuerst die laufende Interaktion.") end
    if not expansionAccess(p) then return toast(p,"Gehe zum Ausbaukreis oder zum Büro-PC.") end
    if d.bays>=C.MaxBays then return toast(p,"Deine Werkstatt hat bereits alle vier Hebebühnen.") end
    -- Repeated input reuses one quote. The client never chooses the stage or price.
    local c=p.confirm
    if not c or c.key~="bays" or c.stage~=d.bays or now()>c.expires then
        c={token=Http:GenerateGUID(false),key="bays",stage=d.bays,cost=R.UpgradeCost(d,"bays"),
            level=C.BayLevels[d.bays+1],expires=now()+30};p.confirm=c
    end
    emit(p,"confirm",c)
end
local function act(p,action,a)
    local d=p.profile.data
    if action=="hello" then Mini.Hello(p);return push(p) end -- 3.0: Minispiel-Snapshot und Bestenliste
    if action=="travel" then
        if not C.StationNames[a.key] then return end
        if a.key=="shop" then resetInteraction(p);emit(p,"page","shop");return push(p) end
        resetInteraction(p);p.confirm=nil
        moveTo(p,p.world.model.Stations[a.key]);emit(p,"page",a.key);Mini.OnStation(p,a.key);return push(p) -- 3.0: Tablet-Navigation zählt als Stationsbesuch
    end
    if action=="select" then
        if selected(p,a.id) then
            if p.selected~=a.id then resetInteraction(p);p.confirm=nil end
            p.selected=a.id;push(p)
        end
        return
    end
    if action=="target" then
        local j=selected(p,a.id)
        if a.id and not j then return end
        resetInteraction(p);p.confirm=nil
        local _,target=objectiveFor(p,j);if j then p.selected=j.id end
        if a.car and j then target=p.world.cars[j.id].model.DiagnosticPoint end
        moveTo(p,target);emit(p,"close");return push(p)
    end
    if action=="swapTool" then
        if p.pending then return toast(p,"Beende zuerst die laufende Interaktion.") end
        if not station(p,"tools") then return toast(p,"Gehe zuerst zur Werkzeugkiste.") end
        local ok,msg=R.SwapTool(d,a.slot,a.id)
        if ok and not R.ToolActive(d,p.tool) then
            p.tool=a.id;F.Equip(p.player,p.tool)
        end
        return messageResult(p,ok,msg)
    end
    if action=="tool" then
        local t=C.Tools[a.id];if not t then return end
        if not R.ToolActive(d,a.id) then return toast(p,"Dieses Werkzeug liegt in der Werkzeugkiste.") end
        if not R.ToolUnlocked(d,a.id) then return toast(p,"Kaufe zuerst das zugehörige Werkstattgerät.") end
        if p.pending and a.id~=p.tool then resetInteraction(p) end
        if p.tool==a.id and p.player.Character and p.player.Character:FindFirstChild("GarageTool") then return push(p) end
        p.tool=a.id;F.Equip(p.player,p.tool);return push(p)
    end
    if action=="accept" then
        if not station(p,"workshop") then return toast(p,"Gehe zuerst zum Empfang.") end
        local j,msg=R.Accept(d,a.id)
        if j then resetInteraction(p);p.selected=j.id;R.RefreshOffers(d);toast(p,"Auftrag angenommen. Dein Fahrzeug steht auf Bühne "..j.bay..".") end
        return messageResult(p,j,msg)
    end
    if action=="work" or action=="scan" then return work(p,a.id or p.selected,a.point,action=="scan") end
    if action=="door" then
        if p.pending or not near(p,p.world.model.RollerDoor.Control,8) then return toast(p,"Gehe ohne laufende Interaktion zum Torschalter.") end
        local ok,msg=W.RollDoor(p.world,function() if sessions[p.player]==p then push(p) end end)
        toast(p,msg);if ok then push(p) end;return
    end
    if action=="lift" or action=="hood" then
        local j=selected(p,a.id);if not j then return end
        local v=p.world.cars[j.id]
        if p.pending or j.phase=="working" then return toast(p,"Beende zuerst die Arbeit an diesem Fahrzeug.") end
        if not v or not near(p,action=="lift" and v.bay.LiftControl or v.model.HoodPoint,8) then return toast(p,"Gehe zum Schalter oder zur Motorhaube.") end
        if action=="lift" then W.Lift(p.world,j.id,function() if sessions[p.player]==p then changed(p) end end) else W.Hood(v) end
        return changed(p)
    end
    if action=="diagnose" then
        local j=selected(p,a.id);if not j then return end
        local v=p.world.cars[j.id]
        if p.pending or not v or v.moving or p.tool~="scanner" or not near(p,v.model.DiagnosticPoint,8) then return end
        local ok,msg=R.Diagnose(j,a.choice)
        if ok then emit(p,"diagnosisDone",j.id) end
        return messageResult(p,ok,msg)
    end
    if action=="hit" then
        local c=p.pending
        if not c or c.kind~="gauge" or a.token~=c.token then return end
        resetInteraction(p,c)
        local j=selected(p,c.job);local v=j and p.world.cars[j.id]
        if not j or not v or j.step~=c.step then return end
        local ok,msg=jobConditions(p,j,v);if not ok then return toast(p,msg) end
        local at=a.at
        if type(at)~="number" or at~=at or at<now()-0.5 or at>now()+0.06 or not R.GaugeHit(at,c) then
            j.quality=math.max(0,j.quality-2);toast(p,"Knapp daneben. Versuche es erneut im grünen Bereich.");return changed(p)
        end
        local success,message=R.StartWork(d,j,now())
        if success then
            local step=C.JobById[j.kind].steps[j.step];F.Effect(v.model,step.effect)
            F.WorkEffect(v.model,p.tool,v.model[step.point],j.workUntil-now(),step.effect)
            emit(p,"workFX",{tool=p.tool,point=v.model[step.point],duration=j.workUntil-now()})
        end
        return messageResult(p,success,message)
    end
    if action=="abortInteraction" then
        -- A delayed abort from an old dialog must not cancel a newer interaction.
        if p.pending and a.token~=p.pending.token then return end
        resetInteraction(p);return push(p)
    end
    if action=="yard" then
        if type(a.id)~="string" or not C.YardTasks[a.id] then return end
        local def=C.YardTasks[a.id];local tasks=p.world.model:FindFirstChild("YardActivities")
        local point=tasks and tasks:FindFirstChild(a.id)
        if not def or not point or not near(p,point,8) or p.pending then return end
        if now()<(d.yardReady[a.id] or 0) then return toast(p,"Hier gibt es bald wieder Arbeit: "..math.ceil(d.yardReady[a.id]-now()).." s.") end
        -- The air station supplies its own gauge; a player need not own the diagnostic cart.
        local pending={kind="yard",token=Http:GenerateGUID(false),point=point,expires=now()+def.seconds+0.5}
        beginInteraction(p,pending)
        emit(p,"scan",{tool=def.tool or p.tool,point=point,duration=def.seconds});toast(p,def.name.." …")
        task.delay(def.seconds,function()
            if sessions[p.player]~=p or p.pending~=pending then return end
            resetInteraction(p,pending)
            if p.player.Character~=pending.character or not near(p,point,8) or p.profile.transacting then emit(p,"interactionReset");return toast(p,"Außenarbeit abgebrochen. Versuche es erneut an der Station.") end
            if R.FinishYard(p.profile.data,a.id,now()) then
                Mini.OnActivity(p) -- 3.0: zählt als "heute gespielt" für den Tagesauftrag
                emit(p,"purchaseFX",{title=def.name,detail="+"..def.reward.." Cr · +"..def.xp.." XP"});changed(p)
            end
        end)
        return
    end
    if action=="settle" then
        if not station(p,"workshop") then return toast(p,"Gehe zur Abrechnung an den Empfang.") end
        local receipt,msg=R.Settle(d,a.id,now())
        if receipt then emit(p,"receipt",receipt);R.RefreshOffers(d);Mini.OnSettled(p) end -- 3.0: jobsDone für Ziele
        return messageResult(p,receipt,msg)
    end
    if action=="confirm" then
        if a.key=="cancel" and selected(p,a.id) then token(p,"cancel",a.id)
        elseif a.key=="bays" then expansionQuote(p)
        end
        return
    end
    if action=="commit" then
        local c=p.confirm;if not c or c.token~=a.token or now()>c.expires then return end
        p.confirm=nil
        if c.key=="cancel" then resetInteraction(p);R.CancelJob(d,c.job)
        elseif c.key=="bays" then
            if p.pending or not expansionAccess(p) then return toast(p,"Gehe ohne laufende Interaktion zum Ausbaukreis oder Büro-PC.") end
            local ok,msg=R.BuyUpgrade(d,"bays",c.stage)
            if not ok then return messageResult(p,ok,msg) end
            emit(p,"purchaseFX",{title="Hallenanbau · Bühne "..d.bays,detail="−"..c.cost.." Cr · Ausbau abgeschlossen"})
            changed(p)
            task.spawn(function() P.Save(p.profile,false);if sessions[p.player]==p then push(p) end end)
            return
        end
        return changed(p)
    end
    if action=="partSelect" then
        local j=selected(p,a.job);if j then return messageResult(p,R.SelectPart(d,j,a.sku)) end;return
    end
    if action=="order" then
        if not station(p,"parts") then return toast(p,"Gehe zum Teilehandel.") end
        local before=d.money;local ok,msg=R.Order(d,a.sku,a.qty,now())
        if ok then local part=C.PartById[a.sku];emit(p,"purchaseFX",{title=part.eta==0 and "Teile gekauft" or "Teile bestellt",detail=a.qty.." × "..part.brand.." · −"..math.floor(before-d.money).." Cr"});return changed(p) end
        return messageResult(p,ok,msg)
    end
    if action=="deviceMenu" or action=="assignEquipment" then
        local device=type(a.id)=="string" and p.world.model.Equipment:FindFirstChild(a.id)
        if not device or not (station(p,"upgrades") or near(p,device.Badge,8)) then return toast(p,"Gehe zum Gerät oder zum Büro-PC.") end
        if p.pending then return toast(p,"Beende zuerst die laufende Interaktion.") end
        if action=="deviceMenu" then emit(p,"device",{id=a.id});return push(p) end
        for _,j in ipairs(d.jobs) do
            if (j.bay==a.bay or j.bay==d.equipmentBays[a.id]) and p.world.cars[j.id].moving then return toast(p,"Warte, bis die Bühne stillsteht.") end
        end
        local ok,msg=R.AssignEquipment(d,a.id,a.bay)
        if ok then W.Equipment(p.world,d);emit(p,"interactionReset") end
        return messageResult(p,ok,msg)
    end
    if action=="equipment" or action=="upgrade" then
        if action=="upgrade" and a.id=="bays" then return expansionQuote(p) end
        if not station(p,"upgrades") then return toast(p,"Gehe zur Ausbau-Werkbank.") end
        local before=d.money;local ok,msg
        if action=="equipment" then ok,msg=R.BuyEquipment(d,a.id) else ok,msg=R.BuyUpgrade(d,a.id) end
        if ok then
            W.Equipment(p.world,d);R.RefreshOffers(d)
            local def=action=="equipment" and C.EquipmentById[a.id] or C.UpgradeById[a.id]
            emit(p,"purchaseFX",{title=def.name,detail="Stufe "..(action=="equipment" and d.equipment[a.id] or d[a.id]).." · gekauft"})
            return changed(p)
        end
        return messageResult(p,ok,msg)
    end
    if action=="buyCredits" then
        if p.pending then return toast(p,"Beende zuerst die laufende Arbeit.") end
        if RunService:IsStudio() or not p.profile.writable or p.profile.transacting then return toast(p,"Robux-Käufe sind hier noch nicht verfügbar.") end
        if now()<(p.nextPurchasePrompt or 0) then return end
        local product
        for _,candidate in ipairs(C.CreditProducts) do if candidate.key==a.key then product=candidate end end
        if not product or not Purchases.ByProduct(product.productId) then return toast(p,"Dieses Credit-Paket ist noch nicht verfügbar.") end
        if d.money+product.credits>C.NumberCap or d.money+product.credits-d.money~=product.credits then return toast(p,"Dein Credit-Guthaben ist bereits zu hoch für dieses Paket.") end
        p.nextPurchasePrompt=now()+3;emit(p,"purchasePrompt",{productId=product.productId});return
    end
    if action=="save" and now()>(p.nextSave or 0) then
        p.nextSave=now()+30;task.spawn(function() P.Save(p.profile,false);if sessions[p.player]==p then push(p);toast(p,p.profile.status) end end)
    end
end
local function request(player,action,a)
    local p=sessions[player];if not p or p.closing or type(action)~="string" or #action>32 then return end
    if p.profile.transacting and action~="hello" and action~="abortInteraction" then
        if action=="mini_press_click" then return end -- 3.0: Klickpakete still verwerfen (der Client wiederholt sie), kein Toast 2×/s
        return toast(p,"Dein Kauf wird sicher gespeichert. Bitte einen Moment warten.")
    end
    a=type(a)=="table" and a or {}
    local count=0;for k,v in pairs(a) do count=count+1;if count>10 or type(k)~="string" or #k>24 or (type(v)~="string" and type(v)~="number" and type(v)~="boolean") or (type(v)=="string" and #v>100) or (type(v)=="number" and (v~=v or math.abs(v)>1e25)) then return end end
    validateInteraction(p)
    local finishing=p.pending and a.token==p.pending.token and (action=="hit" or action=="abortInteraction")
    local time=now();p.budget=math.min(30,(p.budget or 30)+(time-(p.budgetTime or time))*20);p.budgetTime=time
    if not finishing then if p.budget<1 then return end;p.budget=p.budget-1 end
    -- 3.0: Minispiel-Aktionen haben eigene Abklingzeiten je Aktion und Ziel (Budget und Sperren gelten weiter).
    if action~="hello" and action~="hit" and action~="abortInteraction" and not Mini.Handles(action) then
        if time-(p.cooldowns[action] or -10)<0.12 then return end;p.cooldowns[action]=time
    end
    local changedTime,arrived=R.Advance(p.profile.data,time)
    advanceDays(p,time)
    if arrived>0 then W.Deliver(p.world,arrived);toast(p,"Deine Teilelieferung ist angekommen.") end
    if changedTime then p.revision=p.revision+1;W.Sync(p.world,p.profile.data) end
    if Mini.Handles(action) then return Mini.Handle(p,action,a) end -- 3.0
    act(p,action,a)
end
-- 3.0: Minispiele an dieselben Wege anbinden (ein Eingang, ein Profil, keine neuen Remotes).
Mini.Init({emit=emit,toast=toast,changed=changed,push=push,getSession=function(player) return sessions[player] end,moveTo=moveTo,now=now})
Command.OnServerEvent:Connect(request)
Purchases.Init(function(player) return sessions[player] end,function(p,product)
    emit(p,"purchaseFX",{title="Credits erhalten",detail="+"..product.credits.." Credits"});changed(p)
end)
local function join(player)
    if sessions[player] or joining[player] then return end
    joining[player]=true
    local profile=P.Load(player)
    Mini.Reconcile(player,profile) -- 3.0: Auktions-Übergaben abgleichen, falls nur ein Profil gespeichert wurde
    if not player.Parent then joining[player]=nil;P.Save(profile,true);return end
    local p={player=player,profile=profile,tool="scanner",revision=1,cooldowns={},lastPush=0}
    local _,cycle=R.DayClock(now(),dayEpoch);p.dayCycle=cycle
    p.world=W.Create(player,function(kind,value,point)
        if sessions[player]~=p then return end
        if kind=="station" then if station(p,value) then resetInteraction(p);emit(p,"page",value);push(p);Mini.OnStation(p,value) end -- 3.0: Tutorial-Schritt/Hinweis zur Station
        elseif kind=="expand" then request(player,"confirm",{key="bays"})
        elseif kind=="lift" then for _,j in ipairs(p.profile.data.jobs) do if j.bay==value then request(player,"lift",{id=j.id});break end end
        else request(player,kind,{id=value,point=point}) end
    end)
    if not p.world then joining[player]=nil;P.Save(profile,true);player:Kick("Alle Werkstätten sind belegt. Bitte nutze einen anderen Server.");return end
    sessions[player]=p
    joining[player]=nil
    local stats=Instance.new("Folder");stats.Name="leaderstats";stats.Parent=player
    for _,name in ipairs({"Credits","Level"}) do local n=Instance.new("NumberValue");n.Name=name;n.Parent=stats end
    R.RefreshOffers(profile.data);W.Sync(p.world,profile.data);W.Equipment(p.world,profile.data)
    Mini.OnJoin(p) -- 3.0: Offline-Presse, Tageswechsel, Game Passes
    local function character(ch)
        local root=ch:WaitForChild("HumanoidRootPart",10)
        local humanoid=ch:WaitForChild("Humanoid",10)
        local hand=ch:FindFirstChild("Right Arm") or ch:WaitForChild("RightHand",10)
        if not root or not humanoid or not hand or sessions[player]~=p or player.Character~=ch then return end
        resetInteraction(p);p.confirm=nil
        if not R.ToolActive(profile.data,p.tool) or not R.ToolUnlocked(profile.data,p.tool) then
            for _,key in ipairs(profile.data.loadout) do if R.ToolUnlocked(profile.data,key) then p.tool=key;break end end
        end
        moveTo(p,p.world.model.Stations.home);F.Equip(player,p.tool);push(p)
        Mini.OnCharacter(p) -- 3.0: Lobby/Tycoon-Spieler zur Zonen-Ankunft (Open World bleibt in der Werkstatt)
    end
    player.CharacterAdded:Connect(character)
    if player.Character then task.spawn(character,player.Character) end
    push(p)
end
Players.PlayerAdded:Connect(join)
for _,player in ipairs(Players:GetPlayers()) do task.spawn(join,player) end
Players.PlayerRemoving:Connect(function(player)
    local p=sessions[player];if not p then return end
    advanceDays(p,now());p.closing=true;p.pending=nil
    Mini.OnLeave(p,p.profile.writable) -- 3.0: vor P.Save (Save gibt writable frei); blockiert nicht
    local saved=P.Save(p.profile,true);Mini.OnSaved(p,saved) -- 3.0: Bestenliste nur nach gelungenem Speichern
    sessions[player]=nil;W.Destroy(player)
end)
task.spawn(function()
    while true do
        task.wait(0.5)
        Lighting.ClockTime=R.DayClock(now(),dayEpoch)
        for _,p in pairs(sessions) do if not p.closing then
            advanceDays(p,now())
            validateInteraction(p)
            local change,arrived=R.Advance(p.profile.data,now())
            if change then p.revision=p.revision+1;W.Sync(p.world,p.profile.data) end
            if arrived>0 then W.Deliver(p.world,arrived);toast(p,"Teilelieferung angekommen. Die Ersatzteile liegen im Lager.") end
            push(p)
            Mini.Tick(p,now()) -- 3.0: auch während transacting (nur Schrott, nie Geld)
        end end
    end
end)
task.spawn(function()
    while true do task.wait(C.AutosaveSeconds);for _,p in pairs(sessions) do if not p.closing then task.spawn(function() P.Save(p.profile,false) end) end end end
end)
game:BindToClose(function()
    local remaining=0
    for _,p in pairs(sessions) do remaining=remaining+1;advanceDays(p,now());p.closing=true;Mini.OnLeave(p,p.profile.writable);task.spawn(function() local saved=P.Save(p.profile,true);Mini.OnSaved(p,saved);remaining=remaining-1 end) end -- 3.0: OnLeave/OnSaved
    -- 3.0: auch auf laufende Bestenlisten-Schreibvorgänge warten
    local deadline=os.clock()+25;while (remaining>0 or Mini.Pending()>0) and os.clock()<deadline do task.wait(0.1) end
end)
