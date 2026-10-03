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
-- 3.0: W.Sync darf nie den 0,5-s-Takt oder eine Aktion abbrechen. Schlägt er fehl, holt der Takt ihn nach.
local function safeSync(p)
    local ok,err=pcall(W.Sync,p.world,p.profile.data)
    if not ok then p.syncPending=true;if now()>=(p.syncWarnAt or 0) then p.syncWarnAt=now()+5;warn("[Werkstatt] Abgleich der Werkstatt für "..p.player.Name.." fehlgeschlagen: "..tostring(err)) end else p.syncPending=nil end -- 3.0: Warnung höchstens alle 5 s
    return ok
end
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
    safeSync(p) -- 3.0
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
    safeSync(p) -- 3.0
    -- Register cleanup before notifying the client. Every kind has a deadline.
    task.delay(math.max(0,c.expires-now())+0.1,function()
        if sessions[p.player]==p and p.pending==c then resetInteraction(p,c) end
    end)
end
local function partName(kind) -- 3.0
    for _,t in ipairs(C.PartTypes) do if t.id==kind then return t.name end end
    return "Ersatzteil"
end
local function objectiveFor(p,job)
    local d=p.profile.data
    local objective,target=W.Objective(p.world,job)
    if job and job.phase=="approval" and p.calling then objective="Der Kunde wird angerufen …" end -- 3.0
    if job and job.phase=="repair" then
        local step=C.JobById[job.kind].steps[job.step]
        -- 3.0: Ein gekauftes Gerät stellt der Server beim E-Druck selbst bereit; nur ein fehlendes Gerät führt zum Ausbau.
        if step and step.equipment and (d.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) then
            objective="Kaufe "..C.EquipmentById[step.equipment].name.." an der Ausbau-Werkbank.";target=p.world.model.Stations.upgrades
        elseif step and step.equipment and d.equipmentBays[step.equipment]~=job.bay then
            objective=step.name..": E drücken · "..C.EquipmentById[step.equipment].name.." kommt automatisch an Bühne "..job.bay.."."
        end
        if step and step.part and not R.ChoosePart(d,job,step.part) then objective="Ersatzteil fehlt: "..partName(step.part).." im Teilehandel kaufen oder eine andere Marke wählen.";target=p.world.model.Stations.parts end -- 3.0
    end
    return objective,target
end
local function push(p)
    local d=p.profile.data;local job=selected(p)
    if not job then p.selected=d.jobs[1] and d.jobs[1].id;job=selected(p) end
    local objective,target=objectiveFor(p,job)
    -- 3.0: ClientSnapshot: Befund und Salz des Fahrzeug-Checks bleiben bis zum Scan auf dem Server
    local visuals={};for id,v in pairs(p.world.cars) do visuals[id]={lifted=v.lifted,hood=v.hood,moving=v.moving,model=v.model} end
    emit(p,"state",{data=R.ClientSnapshot(d),revision=p.revision,selected=p.selected,tool=p.tool,objective=objective,target=target,
        time=now(),dayEpoch=dayEpoch,interaction=p.pending and {token=p.pending.token,kind=p.pending.kind,expires=p.pending.expires},neededXP=R.XPNeeded(d),shopReady=p.profile.writable and not RunService:IsStudio() and not p.profile.transacting,saveStatus=p.profile.status,visuals=visuals,plot=p.world.model})
    p.player.leaderstats.Credits.Value=math.floor(d.money);p.player.leaderstats.Level.Value=d.level
    p.lastPush=now();p.dirty=false
end
local function changed(p)
    p.revision=p.revision+1;safeSync(p);push(p) -- 3.0: Abgleich geschützt
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
-- 3.0: Jede Absage sagt genau, was zu tun ist.
local function pointName(key) return C.PointNames[key] or "markierter Punkt" end
local function jobConditions(p,j,v)
    if v.moving then return false,"Warte kurz, bis die Hebebühne stillsteht, und drücke dann nochmal E." end -- 3.0
    local step=C.JobById[j.kind].steps[j.step]
    if not step or j.phase~="repair" then return false,"Dieser Arbeitsschritt ist gerade nicht dran. Folge dem Ziel oben im Bild." end -- 3.0
    if v.lifted~=step.lifted then return false,step.lifted and "Die Bühne muss oben sein: drücke E am Arbeitspunkt oder F am Bühnenschalter." or "Die Bühne muss unten sein: drücke E am Arbeitspunkt oder F am Bühnenschalter." end -- 3.0
    if step.hood and not v.hood then return false,"Die Motorhaube muss offen sein: drücke E am Arbeitspunkt oder H an der Haube." end -- 3.0
    if not R.ToolActive(p.profile.data,p.tool) or not R.ToolMatches(step,p.tool) then return false,"Nimm „"..C.Tools[step.tool].name.."“ in die Hand und drücke nochmal E." end -- 3.0
    if step.equipment and (p.profile.data.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) then return false,"Dir fehlt „"..C.EquipmentById[step.equipment].name.."“. Kaufe es an der Ausbau-Werkbank." end -- 3.0
    if step.equipment and p.profile.data.equipmentBays[step.equipment]~=j.bay then return false,"Stelle zuerst "..C.EquipmentById[step.equipment].name.." an Bühne "..j.bay.." bereit: am Gerät E drücken." end -- 3.0
    if step.equipment then
        for _,other in ipairs(p.profile.data.jobs) do
            local otherStep=C.JobById[other.kind].steps[other.step]
            if other.id~=j.id and other.phase=="working" and otherStep and otherStep.equipment==step.equipment then
                return false,"„"..C.EquipmentById[step.equipment].name.."“ arbeitet gerade an einem anderen Auto. Warte, bis der Schritt dort fertig ist." -- 3.0
            end
        end
    end
    if step.part and not R.ChoosePart(p.profile.data,j,step.part) then return false,"Ersatzteil fehlt: Kaufe „"..partName(step.part).."“ im Teilehandel oder wähle eine vorhandene Marke." end -- 3.0
    if not near(p,v.model[step.point],8) then return false,"Gehe näher an „"..pointName(step.point).."“ (markiert am Auto) und drücke E." end -- 3.0
    return true
end
-- 3.0: Passendes Werkzeug automatisch aus der aktiven Leiste nehmen (step.tool oder erlaubte Alternative).
local function pickTool(d,step)
    if R.ToolActive(d,step.tool) and R.ToolUnlocked(d,step.tool) then return step.tool end
    for _,key in ipairs(d.loadout) do
        if step.alternatives and step.alternatives[key] and R.ToolUnlocked(d,key) then return key end
    end
end
local function autoTool(p,step) -- 3.0
    local d=p.profile.data
    if R.ToolActive(d,p.tool) and R.ToolUnlocked(d,p.tool) and R.ToolMatches(step,p.tool) then return true end
    local key=pickTool(d,step)
    if not key then
        local tool=C.Tools[step.tool]
        if not R.ToolUnlocked(d,step.tool) then
            return false,"Dir fehlt „"..tool.name.."“: Kaufe zuerst "..C.EquipmentById[tool.equipment].name.." an der Ausbau-Werkbank."
        end
        return false,"„"..tool.name.."“ liegt in der Werkzeugkiste. Geh zur Werkzeugkiste und lege es in deine Werkzeugleiste."
    end
    p.tool=key;F.Equip(p.player,key)
    if p.pending then p.pending.tool=key end -- automatischer Wechsel bricht nichts ab
    toast(p,"Werkzeug: "..C.Tools[key].name)
    return true
end
local function startLift(p,j) -- 3.0: genau wie die Aktion 'lift'
    return W.Lift(p.world,j.id,function() if sessions[p.player]==p then changed(p) end end)
end
-- 3.0: Vor einem Arbeitsschritt: Abstand, Gerät (automatisch bereitstellen), Teil, Werkzeug, Bühne, Haube.
-- Liefert ready, message, dirty (dirty = Zustand geändert, changed statt push).
local function prepare(p,j,v)
    local d=p.profile.data;local step=C.JobById[j.kind].steps[j.step]
    if v.moving then return false,"Warte kurz, bis die Hebebühne stillsteht, und drücke dann nochmal E." end
    if not step then return false,"Dieser Arbeitsschritt ist gerade nicht dran. Folge dem Ziel oben im Bild." end
    if not near(p,v.model[step.point],8) then return false,"Gehe näher an „"..pointName(step.point).."“ (markiert am Auto) und drücke E." end
    local dirty=false
    if step.equipment then
        local e=C.EquipmentById[step.equipment]
        if (d.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) then
            return false,"Dir fehlt „"..e.name.."“"..((step.equipmentLevel or 1)>1 and " (Stufe "..step.equipmentLevel..")" or "")..". Kaufe es an der Ausbau-Werkbank."
        end
        if d.equipmentBays[step.equipment]~=j.bay then
            local oldBay=d.equipmentBays[step.equipment]
            for _,other in ipairs(d.jobs) do
                if other.bay==oldBay and p.world.cars[other.id] and p.world.cars[other.id].moving then return false,"Warte kurz, bis die andere Bühne stillsteht, und drücke dann nochmal E." end
            end
            -- 3.0: Steht ein anderes Gerät an dieser Bühne, stellt der Mechaniker es selbst ins Lager (sonst blieben Reifen-,
            -- 3.0: Bremsen- und Ölaufträge nacheinander mit „Geräteplatz belegt“ stecken). Nur ein gerade arbeitendes Gerät bleibt.
            for other,bay in pairs(d.equipmentBays) do
                if other~=step.equipment and bay==j.bay then
                    local otherName=C.EquipmentById[other] and C.EquipmentById[other].name or "Das andere Gerät"
                    local busy=false
                    for _,o in ipairs(d.jobs) do
                        local oStep=o.phase=="working" and C.JobById[o.kind].steps[o.step]
                        if oStep and oStep.equipment==other then busy=true end
                    end
                    if busy then return false,"„"..otherName.."“ arbeitet gerade an Bühne "..j.bay..". Warte, bis der Schritt fertig ist, und drücke dann nochmal E." end
                    local okStore=R.AssignEquipment(d,other,0)
                    if not okStore then return false,"„"..otherName.."“ steht an Bühne "..j.bay..". Stelle es am Gerät mit E ins Lager und drücke dann nochmal E." end
                    toast(p,otherName.." ins Lager gestellt.");dirty=true
                end
            end
            local ok,msg=R.AssignEquipment(d,step.equipment,j.bay)
            if not ok then if dirty then W.Equipment(p.world,d) end;return false,msg.." Danach „"..e.name.."“ am Gerät mit E an Bühne "..j.bay.." stellen.",dirty end -- 3.0
            W.Equipment(p.world,d);dirty=true
            toast(p,e.name.." steht jetzt an Bühne "..j.bay..".")
        end
    end
    if step.part and not R.ChoosePart(d,j,step.part) then return false,"Ersatzteil fehlt: Kaufe „"..partName(step.part).."“ im Teilehandel oder wähle eine vorhandene Marke.",dirty end
    local ok,msg=autoTool(p,step);if not ok then return false,msg,dirty end
    if v.lifted~=step.lifted then
        if not startLift(p,j) then return false,"Warte kurz, bis die Hebebühne stillsteht, und drücke dann nochmal E.",dirty end
        return false,"Die Bühne fährt "..(step.lifted and "hoch" or "runter").." … gleich nochmal E drücken.",true
    end
    if step.hood and not v.hood then W.Hood(v);dirty=true;toast(p,"Motorhaube geöffnet.") end
    return true,nil,dirty
end
local function report(p,j)
    local def=C.JobById[j.kind]
    local codes,live=R.Tester(j) -- 3.0: OBD-Tester (Fehlerspeicher und Live-Daten)
    local finding=j.finding and C.JobById[j.finding]
    local text=def.report
    if j.kind=="inspection" then text=finding and finding.report or "Fehlerspeicher: Keine Fehler gespeichert\n"..def.report end -- 3.0
    emit(p,"diagnose",{job=j.id,car=C.CarById[j.carId].name,report=text,answers=j.phase=="diagnose" and j.kind~="inspection" and def.answers or {},phase=j.phase,
        kind=j.kind,codes=codes,live=live,finding=j.finding,findingName=finding and finding.name or nil,approved=j.approved,
        message=#codes==0 and "Keine Fehler gespeichert" or (#codes.." Fehler gespeichert"),customer=j.finding and R.CustomerName(j) or nil}) -- 3.0
end
-- 3.0: Ergebnis eines Fahrzeug-Check-Scans: mit Befund -> Kundenfreigabe per Handy, sonst direkt die Sichtprüfung.
local function inspectionResult(p,j)
    if not R.InspectionScanned(j) then return false end
    if j.phase=="approval" then
        toast(p,"Fehler gefunden: "..C.JobById[j.finding].name..". Ruf den Kunden mit dem Handy an (Taste P).")
    else
        toast(p,"Keine Fehler gespeichert. Jetzt die Sichtprüfung am Auto durchführen.")
    end
    return true
end
local function work(p,id,point,scanOnly)
    local j=selected(p,id);if not j then return end
    local v=p.world.cars[j.id];if not v then return end
    if p.pending then return toast(p,"Schließe zuerst die laufende Interaktion ab.") end
    p.selected=j.id
    if scanOnly or j.phase=="diagnose" or j.phase=="verify" or j.phase=="approval" then -- 3.0: approval
        if j.phase=="working" then return toast(p,"Warte, bis der Arbeitsschritt beendet ist.") end
        if j.phase=="approval" and point and point~="DiagnosticPoint" then toast(p,"Ruf zuerst den Kunden mit dem Handy an (Taste P).");return push(p) end -- 3.0
        if point and point~="DiagnosticPoint" then return toast(p,"Nutze den OBD-Anschluss an der Fahrerseite.") end
        if v.moving then return toast(p,"Warte kurz, bis die Hebebühne stillsteht, und drücke dann nochmal E.") end -- 3.0
        if not near(p,v.model.DiagnosticPoint,8) then return toast(p,"Gehe zum OBD-Anschluss an der Fahrerseite (markiert) und drücke E.") end -- 3.0
        local okTool,toolMsg=autoTool(p,{tool="scanner"});if not okTool then toast(p,toolMsg);return push(p) end -- 3.0: Tester automatisch
        if j.phase=="verify" and (v.lifted or v.hood) then
            -- 3.0: Endkontrolle: Haube schließen und Bühne absenken (automatisch), dann nochmal E.
            if v.hood then W.Hood(v) end
            if v.lifted then
                if not startLift(p,j) then return toast(p,"Warte kurz, bis die Hebebühne stillsteht, und drücke dann nochmal E.") end
                toast(p,"Haube zu, die Bühne fährt runter … gleich nochmal E drücken.");return changed(p)
            end
            toast(p,"Motorhaube geschlossen.");p.revision=p.revision+1
        end
        if j.phase=="approval" then report(p,j);toast(p,"Ruf den Kunden mit dem Handy an (Taste P).");return push(p) end -- 3.0
        if j.scanReady and j.phase=="diagnose" and inspectionResult(p,j) then report(p,j);return changed(p) end -- 3.0: alter Spielstand
        if j.scanReady and j.phase~="verify" then report(p,j);return push(p) end
        local pending={kind="scan",job=j.id,phase=j.phase,step=j.step,token=Http:GenerateGUID(false),point=v.model.DiagnosticPoint,expires=now()+3}
        beginInteraction(p,pending)
        emit(p,"scan",{duration=2.5,tool="scanner",point=v.model.DiagnosticPoint})
        F.WorkEffect(v.model,"scanner",v.model.DiagnosticPoint,2.5)
        task.delay(2.5,function()
            if sessions[p.player]~=p or p.pending~=pending then return end
            resetInteraction(p,pending)
            if p.player.Character~=pending.character or selected(p,j.id)~=j or not near(p,v.model.DiagnosticPoint,8) or v.moving or p.tool~="scanner" then
                emit(p,"interactionReset");return toast(p,"Prüfung abgebrochen: Gehe zurück zum OBD-Anschluss und drücke nochmal E.") -- 3.0
            end
            if j.phase=="diagnose" then
                j.scanReady=true;inspectionResult(p,j);report(p,j) -- 3.0: Fahrzeug-Check ohne Multiple-Choice
            elseif j.phase=="verify" and not v.lifted and not v.hood then
                j.phase="invoice";toast(p,"Endkontrolle bestanden. Rechnung am Empfang abschließen.");report(p,j)
            else report(p,j) end
            changed(p)
        end)
    elseif j.phase=="repair" then
        local step=C.JobById[j.kind].steps[j.step]
        if point and step and point~=step.point then return toast(p,"Falscher Punkt: Gehe zu „"..pointName(step.point).."“ (markiert) und drücke E.") end -- 3.0
        local ready,msg,dirty=prepare(p,j,v) -- 3.0: Werkzeug, Gerät, Bühne und Haube automatisch
        if not ready then toast(p,msg);if dirty then return changed(p) end;return push(p) end
        if dirty then p.revision=p.revision+1 end
        local ok,msg2=jobConditions(p,j,v);if not ok then return toast(p,msg2) end
        local c={kind="gauge",job=j.id,step=j.step,token=Http:GenerateGUID(false),startAt=now()+0.7,period=1.5,
            center=0.62,width=math.min(0.48,0.28+(p.profile.data.toolLevel-1)*0.006),expires=now()+12}
        c.phase=j.phase;c.point=v.model[C.JobById[j.kind].steps[j.step].point]
        beginInteraction(p,c);emit(p,"challenge",c)
    elseif j.phase=="invoice" then toast(p,"Hole die Vergütung am Empfang über Abrechnen ab.")
    else toast(p,"Dieser Arbeitsschritt läuft bereits.") end
    push(p)
end
-- 3.0: Kunden per Handy anrufen (Fahrzeug-Check mit Befund). Liefert ok, Meldung.
local function callCustomer(p,jobId)
    local d=p.profile.data
    local j=jobId and R.FindJob(d,jobId)
    if not jobId then
        local current=selected(p)
        if current and current.phase=="approval" then j=current end
        if not j then for _,candidate in ipairs(d.jobs) do if candidate.phase=="approval" then j=candidate;break end end end
    end
    if not j or j.phase~="approval" or not j.finding then return false,"Gerade muss kein Kunde angerufen werden." end
    if p.calling then return false,"Du telefonierst gerade." end
    local call={job=j.id};p.calling=call;p.selected=j.id
    local customer=R.CustomerName(j)
    emit(p,"call",{job=j.id,state="ringing",customer=customer,car=C.CarById[j.carId].name,finding=j.finding,findingName=C.JobById[j.finding].name})
    push(p)
    task.delay(C.Inspection.RingSeconds,function()
        if sessions[p.player]~=p or p.calling~=call then return end
        p.calling=nil
        if p.closing or R.FindJob(p.profile.data,j.id)~=j or j.phase~="approval" then
            emit(p,"call",{job=j.id,state="ended",customer=customer});return push(p)
        end
        local accepted=R.CustomerDecision(j)
        local _,text=R.Approve(p.profile.data,j,accepted)
        local answer=accepted and "Ja, bitte gleich mitmachen. Danke!" or "Nein danke, bitte nur den Check."
        emit(p,"call",{job=j.id,state="answer",accepted=accepted,text=answer,result=text,customer=customer})
        toast(p,text)
        changed(p)
    end)
    return true,nil
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
    if action=="hello" then
        -- 3.0: Ein hello, das beim ersten state noch unterwegs war, begrüßt nicht ein zweites Mal (siehe join)
        if p.helloAtJoin and now()-p.helloAtJoin<2 then p.helloAtJoin=nil;return push(p) end
        p.helloAtJoin=nil
        Mini.Hello(p);return push(p) -- 3.0: Minispiel-Snapshot und Bestenliste
    end
    if action=="travel" then
        if not C.StationNames[a.key] then return end
        if a.key=="shop" then resetInteraction(p);emit(p,"page","shop");return push(p) end
        if not Mini.EnsureOpenWorld(p) then return push(p) end -- 3.0: aus Lobby/Tycoon zuerst Moduswechsel (sonst stockt Tutorial/Kiesplatz)
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
        if not Mini.EnsureOpenWorld(p) then return push(p) end -- 3.0: aus Lobby/Tycoon zuerst Moduswechsel
        resetInteraction(p);p.confirm=nil
        local _,target=objectiveFor(p,j);if j then p.selected=j.id end
        if a.car and j then target=p.world.cars[j.id].model.DiagnosticPoint end
        moveTo(p,target);emit(p,"close")
        -- 3.0: passendes Werkzeug gleich in die Hand (OBD-Tester für Diagnose/Endkontrolle, sonst das Schritt-Werkzeug)
        local step=j and j.phase=="repair" and C.JobById[j.kind].steps[j.step]
        if j and (j.phase=="diagnose" or j.phase=="verify" or (a.car and not step)) then autoTool(p,{tool="scanner"})
        elseif step then autoTool(p,step) end
        return push(p)
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
        if a.id==C.HandTool then -- 3.0: freie Hand (fester Extra-Platz)
            if p.pending and a.id~=p.tool then resetInteraction(p) end
            p.tool=a.id;F.Equip(p.player,p.tool);return push(p)
        end
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
        if p.pending or not v or v.moving or not near(p,v.model.DiagnosticPoint,8) then return end
        if j.phase~="diagnose" then return push(p) end -- 3.0: Fahrzeug-Check hat keine Auswahl mehr (alte Clients)
        if p.tool~="scanner" and not autoTool(p,{tool="scanner"}) then return push(p) end -- 3.0
        local ok,msg=R.Diagnose(j,a.choice)
        if ok then emit(p,"diagnosisDone",j.id) end
        return messageResult(p,ok,msg)
    end
    if action=="call" then -- 3.0: Handy (auch über ctx.callCustomer für Minispiel-Module)
        local ok,msg=callCustomer(p,type(a.id)=="string" and a.id or nil)
        if not ok then toast(p,msg);return push(p) end
        return
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
    local p=sessions[player]
    -- 3.0: hello während des Ladens (Sitzungssperre, langsamer DataStore) nicht verlieren: der Client hört schon zu,
    -- 3.0: sendet aber nach dem ersten state nichts mehr. join holt die Begrüßung nach, sobald die Sitzung steht.
    if not p and action=="hello" and joining[player] then joining[player]="hello" end
    if not p or p.closing or type(action)~="string" or #action>32 then return end
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
    if changedTime then p.revision=p.revision+1;safeSync(p) end -- 3.0: geschützt
    if Mini.Handles(action) then return Mini.Handle(p,action,a) end -- 3.0
    act(p,action,a)
end
-- 3.0: Minispiele an dieselben Wege anbinden (ein Eingang, ein Profil, keine neuen Remotes).
Mini.Init({emit=emit,toast=toast,changed=changed,push=push,getSession=function(player) return sessions[player] end,moveTo=moveTo,now=now,
    callCustomer=callCustomer}) -- 3.0: Handy-Anruf beim Kunden (Fahrzeug-Check)
Command.OnServerEvent:Connect(request)
Purchases.Init(function(player) return sessions[player] end,function(p,product,result)
    emit(p,"purchaseFX",Purchases.FX(product)) -- 3.0: Titel je Art (Credits/Auto/Optik/Paket)
    if not Mini.OnGranted(p,product,result) then changed(p) end -- 3.0: Shop-Produkte meldet ShopService (ein changed je Quittung), Credits-Pakete wie 2.4.0
end,function(p,product,reason)
    Mini.OnDeferred(p,product,reason) -- 3.0: Quittung aufgeschoben (Garage voll): Hinweis, Purchases wiederholt
end)
local function join(player)
    if sessions[player] or joining[player] then return end
    joining[player]=true
    local profile=P.Load(player)
    Mini.Reconcile(player,profile) -- 3.0: Auktions-Übergaben abgleichen, falls nur ein Profil gespeichert wurde
    if not player.Parent then joining[player]=nil;P.Save(profile,true);return end
    local p={player=player,profile=profile,tool=C.HandTool,revision=1,cooldowns={},lastPush=0} -- 3.0: Start mit freier Hand
    local _,cycle=R.DayClock(now(),dayEpoch);p.dayCycle=cycle
    p.world=W.Create(player,function(kind,value,point)
        if sessions[player]~=p then return end
        -- 3.0: Ein E-Druck löst in Roblox alle sichtbaren E-Prompts aus. Ein Stations-/Ausbau-Prompt darf darum weder
        -- 3.0: eine laufende Interaktion (OBD-Scan, Endkontrolle, QTE) abbrechen noch direkt nach einem Arbeits-E das Tablet öffnen.
        if kind=="work" or kind=="hood" or kind=="lift" then p.lastWorkPrompt=now() end -- 3.0
        local busy=p.pending~=nil or now()-(p.lastWorkPrompt or -10)<0.6 -- 3.0
        if kind=="station" then if busy then return end;if station(p,value) then resetInteraction(p);emit(p,"page",value);push(p);Mini.OnStation(p,value) end -- 3.0: Tutorial-Schritt/Hinweis zur Station; nie während einer Interaktion
        elseif kind=="expand" then if busy then return end;request(player,"confirm",{key="bays"}) -- 3.0: nie während einer Interaktion
        elseif kind=="lift" then for _,j in ipairs(p.profile.data.jobs) do if j.bay==value then request(player,"lift",{id=j.id});break end end
        else request(player,kind,{id=value,point=point}) end
    end)
    if not p.world then joining[player]=nil;P.Save(profile,true);player:Kick("Alle Werkstätten sind belegt. Bitte nutze einen anderen Server.");return end
    sessions[player]=p
    local helloEarly=joining[player]=="hello" -- 3.0: der Client hat schon während des Ladens hello gesendet
    joining[player]=nil
    local stats=Instance.new("Folder");stats.Name="leaderstats";stats.Parent=player
    for _,name in ipairs({"Credits","Level"}) do local n=Instance.new("NumberValue");n.Name=name;n.Parent=stats end
    R.RefreshOffers(profile.data);safeSync(p);W.Equipment(p.world,profile.data) -- 3.0: geschützter Abgleich
    Mini.OnJoin(p) -- 3.0: Offline-Presse, Tageswechsel, Game Passes
    local function character(ch)
        local root=ch:WaitForChild("HumanoidRootPart",10)
        local humanoid=ch:WaitForChild("Humanoid",10)
        local hand=ch:FindFirstChild("Right Arm") or ch:WaitForChild("RightHand",10)
        if not root or not humanoid or not hand or sessions[player]~=p or player.Character~=ch then return end
        resetInteraction(p);p.confirm=nil
        if p.calling then emit(p,"call",{job=p.calling.job,state="ended"});p.calling=nil end -- 3.0: Anruf endet beim Respawn
        p.tool=C.HandTool -- 3.0: nach jedem Respawn freie Hand
        moveTo(p,p.world.model.Stations.home);F.Equip(player,p.tool);push(p)
        Mini.OnCharacter(p) -- 3.0: Lobby/Tycoon-Spieler zur Zonen-Ankunft (Open World bleibt in der Werkstatt)
    end
    player.CharacterAdded:Connect(character)
    if player.Character then task.spawn(character,player.Character) end
    if helloEarly and sessions[player]==p and not p.closing then p.helloAtJoin=now();Mini.Hello(p) end -- 3.0: verpasste Begrüßung nachholen
    push(p)
end
Players.PlayerAdded:Connect(join)
for _,player in ipairs(Players:GetPlayers()) do task.spawn(join,player) end
Players.PlayerRemoving:Connect(function(player)
    local p=sessions[player];if not p then return end
    advanceDays(p,now());p.closing=true;p.pending=nil
    Mini.OnLeave(p,p.profile.writable) -- 3.0: vor P.Save (Save gibt writable frei); blockiert nicht
    -- 3.0: Werkstatt sofort abbauen, nicht erst nach dem Speichern: P.Save kann Sekunden dauern (zweiter Versuch,
    -- 3.0: langsamer DataStore, laufender Autosave) – so lange blieb der Slot belegt und ein Nachrücker wurde gekickt.
    -- 3.0: Die Sitzung bleibt bis nach dem Speichern eingetragen (closing), damit BindToClose darauf wartet.
    W.Destroy(player)
    local saved=P.Save(p.profile,true);Mini.OnSaved(p,saved) -- 3.0: Bestenliste nur nach gelungenem Speichern
    sessions[player]=nil
end)
task.spawn(function()
    while true do
        task.wait(0.5)
        pcall(function() Lighting.ClockTime=R.DayClock(now(),dayEpoch) end) -- 3.0: Takt darf nie sterben
        for _,p in pairs(sessions) do if not p.closing then
            -- 3.0: jede Sitzung geschützt; ein Fehler bei einem Spieler hält weder ihn noch andere an
            local ok,err=pcall(function()
                advanceDays(p,now())
                validateInteraction(p)
                local change,arrived=R.Advance(p.profile.data,now())
                if change then p.revision=p.revision+1 end
                if change or p.syncPending then safeSync(p) end -- 3.0: fehlgeschlagenen Abgleich nachholen
                if arrived>0 then W.Deliver(p.world,arrived);toast(p,"Teilelieferung angekommen. Die Ersatzteile liegen im Lager.") end
                push(p)
            end)
            if not ok and now()>=(p.tickWarnAt or 0) then p.tickWarnAt=now()+5;warn("[Werkstatt] Fehler im Takt für "..p.player.Name..": "..tostring(err)) end -- 3.0: höchstens alle 5 s
            local okMini,errMini=pcall(function() Mini.Tick(p,now()) end) -- 3.0: geschützt; auch während transacting (nur Schrott, nie Geld)
            if not okMini and now()>=(p.miniWarnAt or 0) then p.miniWarnAt=now()+5;warn("[Werkstatt] Fehler im Minispiel-Takt für "..p.player.Name..": "..tostring(errMini)) end
        end end
    end
end)
task.spawn(function()
    while true do task.wait(C.AutosaveSeconds);for _,p in pairs(sessions) do if not p.closing then task.spawn(function() -- 3.0: geschützt
        local ok,err=pcall(P.Save,p.profile,false)
        if not ok then warn("[Werkstatt] Automatisches Speichern für "..p.player.Name.." fehlgeschlagen: "..tostring(err)) end
    end) end end end
end)
game:BindToClose(function()
    local remaining=0
    for _,p in pairs(sessions) do remaining=remaining+1;advanceDays(p,now());p.closing=true;Mini.OnLeave(p,p.profile.writable);task.spawn(function() local saved=P.Save(p.profile,true);Mini.OnSaved(p,saved);remaining=remaining-1 end) end -- 3.0: OnLeave/OnSaved
    -- 3.0: auch auf laufende Bestenlisten-Schreibvorgänge warten
    local deadline=os.clock()+25;while (remaining>0 or Mini.Pending()>0) and os.clock()<deadline do task.wait(0.1) end
end)
