-- Workshop UI: compact HUD, confirmed purchases, responsive panels and protected QTE input.
local Players=game:GetService("Players")
local StarterGui=game:GetService("StarterGui")
local Marketplace=game:GetService("MarketplaceService")
local Tween=game:GetService("TweenService")
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local PromptService=game:GetService("ProximityPromptService")
local Lighting=game:GetService("Lighting")
local player=Players.LocalPlayer
local Shared=game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
-- A replicated folder can arrive before its children. Wait for each dependency.
local C,R,L=require(Shared:WaitForChild("Config")),require(Shared:WaitForChild("Rules")),require(Shared:WaitForChild("Locale"))
local Remotes=Shared:WaitForChild("Remotes")
local Command,Event=Remotes:WaitForChild("Command"),Remotes:WaitForChild("Event")
local language="de" -- Switch after completing the corresponding Locale catalogue.
local function t(s,args) return L.t(s,args,language) end
local function send(action,args) Command:FireServer(action,args or {}) end
local Effects=require(script.Parent:WaitForChild("ClientEffects"))
local InputController=require(script.Parent:WaitForChild("InputController"))
local effects=Effects.new(player,t)
-- 3.0: Minispiele (StarterPlayerScripts.Mini.MiniClient). Begrenztes Warten und pcall: fehlen die Minispiele, bleibt die Werkstatt spielbar.
local MiniClient do
    local ok,mod=pcall(function() return require(script.Parent:WaitForChild("Mini",10):WaitForChild("MiniClient",10)) end)
    if ok and type(mod)=="table" then MiniClient=mod else warn("[3.0] Minispiele nicht geladen: "..tostring(mod));MiniClient={IsOpen=function() return false end,Open=function() end,Toggle=function() end,Start=function() end} end
end
local inputControl
local productInfo={}
local productLoading={}
local colors={bg=Color3.fromRGB(11,16,25),panel=Color3.fromRGB(20,29,43),card=Color3.fromRGB(28,40,57),line=Color3.fromRGB(49,67,87),
    text=Color3.fromRGB(235,243,250),muted=Color3.fromRGB(156,176,199),green=Color3.fromRGB(50,192,137),blue=Color3.fromRGB(59,134,218),red=Color3.fromRGB(212,65,89),yellow=Color3.fromRGB(235,184,72),purple=Color3.fromRGB(143,82,214),purpleDark=Color3.fromRGB(79,47,124)}
local function make(class,parent,props)
    local obj=Instance.new(class)
    for k,v in pairs(props or {}) do obj[k]=v end
    obj.Parent=parent;return obj
end
local function corner(obj,r) make("UICorner",obj,{CornerRadius=UDim.new(0,r or 10)}) end
local function frame(parent,size,pos,color)
    local f=make("Frame",parent,{Size=size,Position=pos or UDim2.new(),BackgroundColor3=color or colors.card,BorderSizePixel=0});corner(f);return f
end
local function text(parent,value,x,y,w,h,size,color)
    return make("TextLabel",parent,{Text=t(value),Position=UDim2.fromOffset(x,y),Size=UDim2.new(1,w,0,h),BackgroundTransparency=1,
        Font=Enum.Font.Gotham,TextSize=size or 17,TextColor3=color or colors.text,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center})
end
local function button(parent,value,x,y,width,callback,color)
    local b=make("TextButton",parent,{Text=t(value),Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(width,38),BackgroundColor3=color or colors.green,
        TextColor3=colors.text,Font=Enum.Font.GothamBold,TextSize=15,TextWrapped=true,AutoButtonColor=true,BorderSizePixel=0});corner(b,8)
    local press=make("UIScale",b,{Scale=1})
    b.Activated:Connect(function()
        press.Scale=0.95
        Tween:Create(press,TweenInfo.new(0.18,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play()
        callback()
    end);return b
end
local function fmt(n)
    n=tonumber(n) or 0
    if MiniClient.Number then return MiniClient.Number(n) end -- 3.0: eine Zahlenformatierung für Werkstatt und Minispiele (MiniLocale.Number)
    for _,unit in ipairs({{1e18,"Tsd. Brd."},{1e15,"Brd."},{1e12,"Bio."},{1e9,"Mrd."},{1e6,"Mio."},{1e3,"Tsd."}}) do
        if math.abs(n)>=unit[1] then return string.format("%.1f %s",n/unit[1],unit[2]) end
    end
    return tostring(math.floor(n))
end
local state,page=nil,"home"
local visible=true
local bindings={}
local family,partIndex,quantity="C",1,1
local diagnosis,challenge=nil,nil
local overlay
local toolSlot=1
local rebuild,showPage,refresh,protectCoreUI
local width,height,scale=1060,700,1
local gui=make("ScreenGui",player:WaitForChild("PlayerGui"),{Name="UltimateCarGame",ResetOnSpawn=false,DisplayOrder=20,IgnoreGuiInset=false,ZIndexBehavior=Enum.ZIndexBehavior.Sibling})
local top=frame(gui,UDim2.fromOffset(310,46),UDim2.new(0.5,0,0,8),colors.bg);top.Name="CompactProgress";top.AnchorPoint=Vector2.new(0.5,0)
local headline=text(top,"ULTIMATE CAR GAME",10,2,-20,13,10,colors.muted);headline.TextXAlignment=Enum.TextXAlignment.Center
local stats=text(top,"Karriere wird geladen …",10,15,-20,21,13);stats.Font=Enum.Font.GothamBold;stats.TextXAlignment=Enum.TextXAlignment.Center
local xpTrack=frame(top,UDim2.new(1,-20,0,3),UDim2.fromOffset(10,39),colors.line)
local xpFill=frame(xpTrack,UDim2.new(0,0,1,0),UDim2.new(),colors.green)
local tablet=frame(gui,UDim2.fromOffset(width,height),UDim2.new(0.5,0,0.5,35),colors.bg);tablet.AnchorPoint=Vector2.new(0.5,0.5)
local tabletScale=make("UIScale",tablet,{Scale=1})
local title=text(tablet,"Ultimate Car Game",22,10,-100,34,24);title.Font=Enum.Font.GothamBold
local subtitle=text(tablet,"Deine Werkstatt. Dein nächster Auftrag.",22,45,-44,23,15,colors.muted)
local closeButton=button(tablet,"×",width-60,14,38,function() visible=false;tablet.Visible=false end,colors.card)
local nav=make("ScrollingFrame",tablet,{Position=UDim2.fromOffset(20,80),Size=UDim2.new(1,-40,0,48),CanvasSize=UDim2.fromOffset(600,0),ScrollingDirection=Enum.ScrollingDirection.X,ScrollBarThickness=3,BackgroundTransparency=1,BorderSizePixel=0})
local navButtons={}
local navOrder={};for _,key in ipairs(C.Stations) do table.insert(navOrder,key) end;table.insert(navOrder,2,"tools")
local navX=0
for i,key in ipairs(navOrder) do
    local shop=key=="shop";local w=shop and 172 or 112
    local b=button(nav,C.StationNames[key],navX,0,w,function() send("travel",{key=key}) end,shop and colors.purpleDark or colors.card)
    b.Name="Nav_"..key
    if shop then b.Size=UDim2.fromOffset(w,44);b.TextSize=18 end
    navButtons[key]=b;navX=navX+w+8
end
-- 3.0: Minispiele im Tablet (nur lokal, kein travel; öffnet das eigene Panel und schließt das Tablet)
do local b=button(nav,"Minispiele",navX,0,150,function() MiniClient.Open() end,colors.blue);b.Name="Nav_minigames";navX=navX+158 end
nav.CanvasSize=UDim2.fromOffset(navX,0)
local body=make("ScrollingFrame",tablet,{Position=UDim2.fromOffset(20,140),Size=UDim2.new(1,-40,1,-178),CanvasSize=UDim2.new(),ScrollBarThickness=5,BackgroundTransparency=1,BorderSizePixel=0,AutomaticCanvasSize=Enum.AutomaticSize.None})
local foot=text(tablet,"",22,height-30,-44,23,12,colors.muted)
local hud=frame(gui,UDim2.new(0.96,0,0,132),UDim2.new(0.02,0,1,-138),colors.bg)
hud.Visible=false
local objective=text(hud,"Lade deine Werkstatt …",12,5,-24,39,16)
local go=button(hud,"Zum Ziel",12,47,110,function() send("target",{id=state and state.selected}) end,colors.blue)
local workButton=button(hud,"Arbeiten [E]",130,47,140,function() if state then send("work",{id=state.selected}) end end)
local menu=button(hud,"Menü [Tab]",278,47,120,function() visible=not visible;tablet.Visible=visible;if visible and rebuild then rebuild() end end,colors.card)
local miniButton=button(hud,"Minispiele [M]",406,47,140,function() MiniClient.Toggle() end,colors.card);miniButton.Name="MiniGames" -- 3.0: Einstieg neben "Menü" (Größe in resize)
local toolButtons={}
for i=1,C.HotbarSize do
    toolButtons[i]=button(hud,i.." · —",12+(i-1)*98,90,92,function()
        if state and not overlay.Visible then send("tool",{id=state.data.loadout[i]}) end
    end,colors.card)
    toolButtons[i].Name="ToolSlot"..i;toolButtons[i].Size=UDim2.fromOffset(92,30)
end
local toastPanel=frame(gui,UDim2.fromOffset(330,60),UDim2.new(0.5,0,0,62),colors.panel);toastPanel.AnchorPoint=Vector2.new(0.5,0);toastPanel.Visible=false
local toastLabel=text(toastPanel,"",14,3,-28,54,14)
local toastSerial=0
local function toast(value)
    toastSerial=toastSerial+1;local serial=toastSerial
    toastLabel.Text=t(value);toastPanel.Visible=true
    task.delay(4,function() if serial==toastSerial then toastPanel.Visible=false end end)
end
overlay=make("Frame",gui,{Name="InteractionOverlay",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(),BackgroundTransparency=0.25,BorderSizePixel=0,Visible=false,ZIndex=10,Active=true})
local modal=frame(overlay,UDim2.fromOffset(580,440),UDim2.fromScale(0.5,0.5),colors.panel);modal.AnchorPoint=Vector2.new(0.5,0.5)
local modalScale=make("UIScale",modal,{Scale=1})
local function clearModal() for _,v in ipairs(modal:GetChildren()) do if not v:IsA("UIScale") and not v:IsA("UICorner") then v:Destroy() end end end
local function dismiss() challenge=nil;diagnosis=nil;overlay.Visible=false;effects.StopWork();if inputControl then inputControl.Unlock() end end
local function submitChallenge()
    if not challenge or challenge.submitted then return end
    challenge.submitted=true
    -- The server owns completion. Keep the dialog until its acknowledgement.
    send("hit",{token=challenge.token,at=workspace:GetServerTimeNow()})
end
local function modalTitle(value)
    clearModal();overlay.Visible=true;local h=text(modal,value,24,17,-48,40,24);h.Font=Enum.Font.GothamBold
end
local function bind(obj,getter) table.insert(bindings,{obj=obj,getter=getter});obj.Text=t(getter()) end
local y=0
local function card(h)
    local c=frame(body,UDim2.new(1,-8,0,h),UDim2.fromOffset(0,y),colors.card);y=y+h+12;return c
end
local function heading(c,value,sub,descriptionHeight)
    local h=text(c,value,16,8,-32,32,#t(value)>40 and 16 or 20);h.Font=Enum.Font.GothamBold
    if sub then text(c,sub,16,42,-32,descriptionHeight or 42,15,colors.muted) end
end
local function note(value)
    local c=card(70);text(c,value,16,8,-32,54,16,colors.muted);return c
end
local function d() return state and state.data end
local function job(id) return state and R.FindJob(d(),id or state.selected) end
local function timer(at) return math.max(0,math.ceil((at or 0)-workspace:GetServerTimeNow())) end
local function phase(j)
    if j.phase=="working" then return t("Arbeit läuft: {s} s",{s=timer(j.workUntil)}) end
    if j.phase=="repair" then return t(C.JobById[j.kind].steps[j.step].name) end
    return t(({diagnose="Diagnose offen",verify="Endkontrolle offen",invoice="Bereit zur Abrechnung"})[j.phase] or j.phase)
end
local function viewport(parent,carId,x,yy,w,h,paintId)
    local previews=Shared:FindFirstChild("PreviewCars")
    local template=previews and previews:FindFirstChild(C.CarById[carId].body)
    -- A late decorative preview must never abort state handling or hide the HUD.
    if not template or not template.PrimaryPart then return end
    local view=make("ViewportFrame",parent,{Position=UDim2.fromOffset(x,yy),Size=UDim2.fromOffset(w,h),BackgroundColor3=colors.bg,BorderSizePixel=0,
        Ambient=Color3.fromRGB(150,166,187),LightColor=Color3.fromRGB(245,246,255),LightDirection=Vector3.new(-1,-1,-1)})
    corner(view)
    local world=make("WorldModel",view,{})
    local car=template:Clone();car.Parent=world
    local rgb=C.CarById[carId].color
    for _,part in ipairs(car:GetDescendants()) do if part:IsA("BasePart") and (part.Name=="Paint" or part.Name=="Hood" or part.Name=="Mirror") then part.Color=Color3.fromRGB(rgb[1],rgb[2],rgb[3]) end end
    local camera=make("Camera",view,{CFrame=CFrame.lookAt(Vector3.new(18,11,-23),Vector3.new(0,2,0)),FieldOfView=40})
    view.CurrentCamera=camera;return view
end
local function homePage()
    local c=card(210);heading(c,"Deine Schrauberwerkstatt","Arbeite an mehreren Kundenautos, bestelle passende Teile und baue deine Geräte aus.")
    bind(text(c,"",16,84,-32,54,17),function() return t("Level {level} · {jobs} / {bays} Bühnen belegt\n{xp} / {need} XP · {done} Aufträge abgeschlossen",{level=d().level,jobs=#d().jobs,bays=d().bays,xp=fmt(d().xp),need=fmt(state.neededXP),done=d().completed}) end)
    button(c,"Werkstatt",16,151,128,function() send("travel",{key="workshop"}) end)
    button(c,"Speichern",152,151,112,function() send("save") end,colors.card)
    if d().parkedJobs and #d().parkedJobs>0 then note("Aufträge aus dem früheren Ausbau warten auf freie Bühnen. Sie werden mit ihrem bisherigen Fortschritt automatisch wieder eingesetzt.") end
    local nextCar
    for _,v in ipairs(C.Cars) do if v.level>d().level then nextCar=v;break end end
    if nextCar then
        c=card(200);heading(c,t("Nächstes Fahrzeug: {name}",{name=nextCar.name}),t("Ab Level {level} · Fahrzeugwert {value} Cr · mehr Vergütung und XP",{level=nextCar.level,value=fmt(nextCar.value)}))
        viewport(c,nextCar.id,16,88,math.min(width-88,390),100)
    else note("Alle Fahrzeugklassen sind freigeschaltet. Baue Geräte aus und übernimm anspruchsvolle Aufträge.") end
    note("Starte mit Ölservice oder Fahrzeug-Check. Kaufe Geräte im Ausbau, bestelle passende Teile und bearbeite mehrere Kundenautos parallel.")
    for _,car in ipairs(C.Cars) do
        local preview=card(178)
        heading(preview,car.name,t("{brand} · ab Level {level} · {family}",{brand=car.brand,level=car.level,family=C.Families[car.family]}))
        viewport(preview,car.id,16,84,math.min(width-88,390),85)
    end
end
local function workshopPage()
    note("Jedes Kundenauto hat eine eigene Bühne und eigene Arbeitsschritte. Wähle Zum Auto, bediene Bühne und Haube und arbeite mit dem passenden Werkzeug.")
    for _,j in ipairs(d().jobs) do
        local id=j.id;local def,car=C.JobById[j.kind],C.CarById[j.carId]
        local c=card(202);heading(c,t("Bühne {bay} · {car} · {name}",{bay=j.bay,car=car.name,name=def.name}))
        bind(text(c,"",16,44,-32,51,16,colors.muted),function() local cur=job(id);return cur and phase(cur).."\n"..t("Qualität {q}% · Teilefamilie {family}",{q=cur.quality,family=C.Families[car.family]}) or "" end)
        button(c,"Zum Auto",16,102,120,function() send("target",{id=id,car=true});visible=false;tablet.Visible=false end)
        button(c,"Teile wählen",144,102,130,function() send("select",{id=id});family=car.family;local cur=job(id);local step=cur and def.steps[cur.step];if step and step.part then for i,k in ipairs(C.PartTypes) do if k.id==step.part then partIndex=i end end end;send("travel",{key="parts"}) end,colors.blue)
        button(c,"Abrechnen",282,102,120,function() send("settle",{id=id}) end,colors.blue)
        button(c,"Auftrag abbrechen",16,150,190,function() send("confirm",{key="cancel",id=id}) end,colors.red)
        local expected=R.Reward(d(),j);text(c,t("Erwartet: {cr} Cr + {xp} XP",{cr=fmt(expected),xp=fmt(def.xp*car.xp)}),215,152,-230,40,14,colors.yellow)
    end
    if #d().jobs==0 then note("Noch kein Kundenauto in der Werkstatt. Nimm unten deinen ersten Auftrag an.") end
    for _,o in ipairs(d().offers) do
        local offerId=o.id;local def,car=C.JobById[o.kind],C.CarById[o.carId]
        local missing,level=R.RequiredEquipment(d(),def)
        local c=card(184);heading(c,def.name.." · "..car.name,def.complaint)
        text(c,t("Familie {family} · Basis {cr} Cr · {xp} XP",{family=C.Families[car.family],cr=fmt(def.reward*car.reward),xp=fmt(def.xp*car.xp)}),16,86,-32,25,14,colors.yellow)
        button(c,"Auftrag annehmen",16,128,176,function() send("accept",{id=offerId}) end)
        if missing then text(c,t("Benötigt: {device} Stufe {level}",{device=C.EquipmentById[missing].name,level=level}),207,119,-223,59,14,colors.muted) end
    end
end
local function toolsPage()
    note("Fünf aktive Werkzeuge: Wähle einen Platz und dann ein Werkzeug. Alles andere bleibt in der Kiste. Tauschen geht nur hier vor Ort.")
    local c=card(112);heading(c,"Deine Werkzeugleiste")
    local bw=math.min(176,(width-80)/5-6)
    for i=1,C.HotbarSize do
        local id=d().loadout[i]
        button(c,i.." · "..C.Tools[id].short,16+(i-1)*(bw+6),54,bw,function() toolSlot=i;rebuild() end,toolSlot==i and colors.green or colors.card)
    end
    for _,id in ipairs(C.ToolOrder) do
        local def=C.Tools[id];local unlocked=R.ToolUnlocked(d(),id)
        local status=R.ToolActive(d(),id) and "Aktiv in der Leiste" or "In der Werkzeugkiste"
        local description=def.description or ({scanner="Fehlerspeicher, Diagnose und Endkontrolle.",ratchet="Befestigungen und Reparaturen am Fahrzeug.",oil="Ölservice und Flüssigkeitswechsel.",tire="Reifenmontage mit der Montiermaschine.",meter="Elektrische Messungen und Fehlersuche."})[id]
        c=card(184);heading(c,def.name,description)
        text(c,unlocked and status or ("Benötigt: "..C.EquipmentById[def.equipment].name),16,89,-32,30,14,colors.muted)
        button(c,"Auf Platz "..toolSlot.." legen",16,132,220,function() send("swapTool",{slot=toolSlot,id=id}) end,unlocked and colors.green or colors.card)
    end
end
local function partsPage()
    local selectedJob=job()
    local c=card(215);heading(c,"Teilehandel · Lager & Bestellung","Nexra, Ferrovia und Orvex liefern passende Teile. Bessere Marken erhöhen den Qualitätsbonus bei der Abrechnung.")
    button(c,C.Families[family],16,99,182,function() family=({C="L",L="P",P="C"})[family];rebuild() end,colors.blue)
    button(c,C.PartTypes[partIndex].name,206,99,196,function() partIndex=partIndex%#C.PartTypes+1;rebuild() end,colors.blue)
    button(c,"Menge: "..quantity,16,149,125,function() quantity=quantity==1 and 3 or 1;rebuild() end,colors.card)
    for _,b in ipairs(C.Brands) do
        local sku=b.id.."_"..family.."_"..C.PartTypes[partIndex].id;local p=C.PartById[sku]
        c=card(174);heading(c,p.brand.." · "..p.name)
        bind(text(c,"",16,44,-32,52,15,colors.muted),function() return t("{price} Cr / Stück · Lager {stock} · Level {level}\n{eta} · Qualitätsbonus +{quality}",{price=fmt(p.price),stock=d().inventory[sku] or 0,level=p.level,eta=p.eta==0 and "Sofort verfügbar" or t("Lieferung in {s} s",{s=p.eta}),quality=p.quality}) end)
        button(c,"Bestellen",16,116,130,function() send("order",{sku=sku,qty=quantity}) end)
        if selectedJob and R.Compatible(sku,selectedJob,p.kind) then
            button(c,selectedJob.selectedParts[p.kind]==sku and "Ausgewählt" or "Für Auftrag wählen",154,116,210,function() send("partSelect",{job=selectedJob.id,sku=sku}) end,colors.blue)
        end
    end
    if selectedJob then note(t("Aktiver Auftrag: {name} · Familie {family}. Ein ausdrücklich gewählter Hersteller wird nicht automatisch ausgetauscht.",{name=C.CarById[selectedJob.carId].name,family=C.Families[C.CarById[selectedJob.carId].family]})) end
    for _,o in ipairs(d().orders) do
        local deliveryId=o.id;local c2=card(82)
        bind(text(c2,"",16,7,-32,66,17),function() for _,current in ipairs(d().orders) do if current.id==deliveryId then local p=C.PartById[current.sku];return t("{qty} × {brand} {name}\nAnkunft in {s} s",{qty=current.qty,brand=p.brand,name=p.name,s=timer(current.eta)}) end end;return t("Geliefert") end)
    end
    note("Service-Teile sind sofort verfügbar. Andere Teile benötigen 60–120 Sekunden.")
end
local function upgradesPage()
    note("Geräte hinten im Lager oder hier am PC einer Bühne zuweisen. Je Bühne ein Geräteplatz. Höhere Gerätestufen verkürzen die passenden Arbeiten.")
    for _,e in ipairs(C.Equipment) do
        local key=e.id;local level=d().equipment[key] or 0
        local c=card(level>0 and 230 or 174);heading(c,e.name,e.description)
        text(c,t("Stufe {n}/{max} · ab Level {level} · {cost} Cr",{n=level,max=e.max,level=e.level,cost=fmt(R.EquipmentCost(d(),key))}),16,87,-32,25,15,colors.yellow)
        button(c,level>=e.max and "Voll ausgebaut" or level==0 and "Gerät kaufen" or "Gerät verbessern",16,123,220,function() send("equipment",{id=key}) end,level>=e.max and colors.card or colors.green)
        if level>0 then
            local assigned=d().equipmentBays[key]
            text(c,assigned and "Bereit an Bühne "..assigned or "Standort: hinteres Gerätelager",16,154,-32,24,14,colors.muted)
            button(c,"Gerät zuweisen",16,184,220,function() send("deviceMenu",{id=key}) end,colors.blue)
        end
    end
    for _,u in ipairs(C.Upgrades) do
        local key=u.key;local c=card(210);heading(c,u.name,u.description,60)
        local full=d()[key]>=u.max
        local description=full and "Voll ausgebaut" or t("Stufe {n}/{max} · {cost} Cr",{n=d()[key],max=u.max,cost=fmt(R.UpgradeCost(d(),key))})
        if key=="bays" and not full then description=description..t(" · Anbau + Bühne {n} ab Level {level}",{n=d().bays+1,level=C.BayLevels[d().bays+1]}) end
        text(c,description,16,112,-32,37,15,colors.muted)
        button(c,full and "Voll ausgebaut" or "Ausbauen",16,160,180,function() if not full then send("upgrade",{id=key}) end end)
    end

end
local function shopPage()
    local hero=card(132);hero.BackgroundColor3=colors.purpleDark
    heading(hero,"Credits-Shop","Credits für deine Werkstatt. Roblox zeigt vor dem Kauf den verbindlichen Preis. Alle Geräte bleiben auch erspielbar.",70)
    for _,pack in ipairs(C.CreditProducts) do
        local product=pack;local c=card(181);heading(c,product.name)
        text(c,t("{credits} Credits",{credits=string.format("%.0f",product.credits)}),16,43,-32,36,25,colors.yellow)
        bind(text(c,"",16,81,-32,37,14,colors.muted),function()
            local info=productInfo[product.productId];local base=C.CreditProducts[1];local baseInfo=productInfo[base.productId]
            if product.key==base.key then return "Das Einstiegspaket für deine Werkstatt" end
            if info and baseInfo and info.PriceInRobux>0 and baseInfo.PriceInRobux>0 then
                local bonus=math.floor((product.credits/info.PriceInRobux/(base.credits/baseInfo.PriceInRobux)-1)*100+0.5)
                if bonus>0 then return t("{bonus}% mehr Credits pro Robux als im kleinsten Paket",{bonus=bonus}) end
            end
            return "Mehr Credits für deinen nächsten Werkstattausbau"
        end)
        local buy=button(c,"Preis wird geladen …",16,127,260,function()
            local info=productInfo[product.productId]
            if not state.shopReady or not info or not info.IsForSale or not info.PriceInRobux or info.PriceInRobux<=0 then return toast("Dieses Paket ist derzeit nicht verfügbar.") end
            send("buyCredits",{key=product.key})
        end,colors.purple)
        bind(buy,function()
            if product.productId<=0 then return "In Kürze verfügbar" end
            if Run:IsStudio() then return "Käufe im veröffentlichten Spiel" end
            if not state.shopReady then return "Speicherung wird benötigt" end
            local info=productInfo[product.productId]
            return info and info.IsForSale and (t("Kaufen").." · "..tostring(info.PriceInRobux).." Robux") or "Zurzeit nicht verfügbar"
        end)
        if product.productId>0 and not productInfo[product.productId] and not productLoading[product.productId] then
            productLoading[product.productId]=true
            task.spawn(function()
                local ok,info=pcall(function() return Marketplace:GetProductInfoAsync(product.productId,Enum.InfoType.Product) end)
                if ok and info and type(info.PriceInRobux)=="number" and info.PriceInRobux>0 then productInfo[product.productId]=info end
                productLoading[product.productId]=nil
            end)
        end
    end
end
local pages={home=homePage,workshop=workshopPage,parts=partsPage,upgrades=upgradesPage,shop=shopPage,tools=toolsPage}
rebuild=function(reset)
    if not state then return end
    local scroll=reset and 0 or body.CanvasPosition.Y
    for _,v in ipairs(body:GetChildren()) do v:Destroy() end
    bindings={};y=0;pages[page]();body.CanvasSize=UDim2.fromOffset(0,y+12);body.CanvasPosition=Vector2.new(0,math.min(scroll,math.max(0,y-body.AbsoluteSize.Y)))
    title.Text=t(C.StationNames[page]).." / ULTIMATE CAR GAME"
    for key,b in pairs(navButtons) do
        b.BackgroundColor3=key=="shop" and (key==page and colors.purple or colors.purpleDark) or (key==page and colors.green or colors.card)
    end
end
showPage=function(key)
    if not pages[key] then return end
    local different=page~=key;page=key;visible=true;tablet.Visible=true;rebuild(different)
end
refresh=function()
    hud.Visible=not visible and not overlay.Visible and not MiniClient.IsOpen() -- 3.0: HUD weicht dem Minispiel-Panel
    if not state then return end
    stats.Text=t("Lv. {level}  ·  {credits} Cr",{credits=fmt(d().money),level=d().level})
    local clock=R.DayClock(workspace:GetServerTimeNow(),state.dayEpoch)
    headline.Text=t("TAG {day} · {hour}:{minute}",{day=d().days+1,hour=string.format("%02d",math.floor(clock)),minute=string.format("%02d",math.floor(clock%1*60))})
    xpFill.Size=UDim2.new(math.clamp(d().xp/state.neededXP,0,1),0,1,0)
    objective.Text=t(state.objective);foot.Text=t(state.saveStatus).." · v"..C.Version.." · "..t("TAB Menü · 1–5 Werkzeug · E Arbeit · H Haube · F Bühne")
    local current=job();local visual=current and state.visuals[current.id]
    workButton.Text=t("Arbeiten [E]")
    if current then
        local aim=state.target
        if aim and aim.Name=="LiftControl" then workButton.Text=t("Bühne bedienen")
        elseif aim and aim.Name=="HoodPoint" then workButton.Text=t("Haube bedienen") end
        if aim and aim.Parent and aim.Parent:GetAttribute("EquipmentId") then workButton.Text=t("Gerät zuweisen") end
    end
    for i,b in ipairs(toolButtons) do
        local id=d().loadout[i];local unlocked=R.ToolUnlocked(d(),id)
        b.Text=i.." · "..C.Tools[id].short;b.BackgroundColor3=state.tool==id and colors.green or colors.card
        b.TextColor3=unlocked and colors.text or colors.muted
    end
    for _,binding in ipairs(bindings) do if binding.obj.Parent then binding.obj.Text=t(binding.getter()) end end
end
-- HUD action follows the currently marked station/part.
workButton:Destroy()
workButton=button(hud,"Arbeiten [E]",130,47,140,function()
    if not state then return end
    local aim=state.target
    if aim and aim.Name=="LiftControl" then send("lift",{id=state.selected})
    elseif aim and aim.Name=="HoodPoint" then send("hood",{id=state.selected})
    elseif aim and aim.Name=="parts" then send("travel",{key="parts"})
    elseif aim and aim.Name=="workshop" then send("travel",{key="workshop"})
    elseif aim and aim.Parent and aim.Parent:GetAttribute("EquipmentId") then send("deviceMenu",{id=aim.Parent:GetAttribute("EquipmentId")})
    else send("work",{id=state.selected}) end
end)
local marker=make("BillboardGui",gui,{Name="Ziel",Size=UDim2.fromOffset(170,38),StudsOffset=Vector3.new(0,2,0),AlwaysOnTop=true,Enabled=false})
local markerText=make("TextLabel",marker,{Size=UDim2.fromScale(1,1),Text=t("▼ DEIN NÄCHSTER SCHRITT"),Font=Enum.Font.GothamBold,TextSize=12,TextColor3=colors.green,BackgroundTransparency=1})
local highlight=make("Highlight",gui,{Name="WorkPartHighlight",Enabled=false,FillTransparency=0.75,OutlineColor=colors.green,FillColor=colors.green,DepthMode=Enum.HighlightDepthMode.AlwaysOnTop})
-- Reuse native prompt input/availability, but lay out E/F/H in fixed screen rows.
-- World-space billboards can overlap at any camera angle despite UI offsets.
local shownPrompts,vehicleButtons={},{ }
local vehicleActions=frame(gui,UDim2.fromOffset(360,126),UDim2.new(0,12,1,-276),colors.bg)
vehicleActions.Name="VehicleActions";vehicleActions.Visible=false
for index,entry in ipairs({{"E","work"},{"F","lift"},{"H","hood"}}) do
    local record={key=entry[1],action=entry[2]};vehicleButtons[index]=record
    record.button=button(vehicleActions,"",6,(index-1)*42,348,function()
        local prompt=record.prompt
        if not prompt or not prompt.Parent or not prompt.Enabled or overlay.Visible or visible then return end
        send(record.action,{id=prompt:GetAttribute("JobId"),point=record.action=="work" and prompt.Parent.Name or nil})
    end,entry[1]=="E" and colors.green or colors.card)
    record.button.Name="VehicleAction_"..entry[1];record.button.Size=UDim2.new(1,-12,0,36)
end
local function refreshVehicleActions()
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local count=0
    for _,record in ipairs(vehicleButtons) do
        local chosen,nearest=nil,math.huge
        for prompt in pairs(shownPrompts) do
            if not prompt.Parent or not prompt:IsDescendantOf(workspace) then shownPrompts[prompt]=nil
            elseif root and prompt.Enabled and prompt:GetAttribute("VehicleAction")==record.action then
                local distance=(root.Position-prompt.Parent.Position).Magnitude
                if distance<=prompt.MaxActivationDistance and distance<nearest then chosen=prompt;nearest=distance end
            end
        end
        record.prompt=chosen;record.button.Visible=chosen~=nil
        if chosen then
            record.button.Text=record.key.." · "..chosen.ActionText
            record.button.Position=UDim2.fromOffset(6,count*42);count=count+1
        end
    end
    local screen=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,800)
    vehicleActions.Size=UDim2.fromOffset(math.min(360,screen.X-24),count*42)
    vehicleActions.Position=UDim2.new(0,12,1,-150-count*42)
    vehicleActions.Visible=count>0 and not visible and not overlay.Visible and not MiniClient.IsOpen() -- 3.0: auch bei offenem Minispiel-Panel ausblenden
end
local function markTarget()
    local target=state and state.target
    marker.Adornee=target;marker.Enabled=target~=nil and not overlay.Visible
    markerText.Text="▼ "..(target and (C.PointNames[target.Name] or ({LiftControl="F · HEBEBÜHNE",tools="WERKZEUGKISTE"})[target.Name]) or "DEIN NÄCHSTER SCHRITT")
    local part=target
    if target and target.Parent then
        for _,candidate in ipairs(target.Parent:GetChildren()) do
            if candidate:IsA("BasePart") and candidate:GetAttribute("WorkPoint")==target.Name and candidate.Transparency<1 then part=candidate;break end
        end
    end
    highlight.Adornee=part;highlight.Enabled=part~=nil and not overlay.Visible
end
Event.OnClientEvent:Connect(function(kind,value)
    if kind=="state" then
        local oldRevision=state and state.revision;local first=not state;local oldLevel=state and state.data.level;state=value
        if challenge and (not state.interaction or state.interaction.token~=challenge.token) then dismiss() end
        if oldLevel and state.data.level>oldLevel then effects.Level(state.data.level,state.data.level-oldLevel) end
        markTarget()
        refresh()
        if first or oldRevision~=state.revision then rebuild() end
    elseif kind=="page" then showPage(value)
    elseif kind=="close" then visible=false;tablet.Visible=false
    elseif kind=="toast" then toast(value)
    elseif kind=="purchaseFX" then effects.Purchase(value)
    elseif kind=="workFX" then effects.Work(value)
    elseif kind=="purchasePrompt" then
        task.spawn(function()
            local ok,info=pcall(function() return Marketplace:GetProductInfoAsync(value.productId,Enum.InfoType.Product) end)
            if not ok or not info or not info.IsForSale then return toast("Der Kauf ist gerade nicht verfügbar.") end
            productInfo[value.productId]=info
            local prompted=pcall(function() Marketplace:PromptProductPurchase(player,value.productId) end)
            if not prompted then toast("Der Roblox-Kaufdialog konnte nicht geöffnet werden.") end
        end)
    elseif kind=="interactionReset" then
        if not challenge or not value or value.token==challenge.token then dismiss() end
    elseif kind=="diagnosisDone" then if diagnosis and diagnosis.job==value then dismiss() end
    elseif kind=="scan" then effects.Work(value);if value.tool=="scanner" then toast(t("Messwerte werden ausgelesen … Bleibe am Auto.")) end
    elseif kind=="diagnose" then
        effects.StopWork();diagnosis=value;visible=false;tablet.Visible=false;modalTitle("Fahrzeugdiagnose · OBD")
        text(modal,value.report,24,67,-48,130,18,colors.muted)
        for i,answer in ipairs(value.answers) do button(modal,answer,24,213+(i-1)*52,532,function() send("diagnose",{id=value.job,choice=i}) end,colors.blue) end
        if #value.answers==0 then text(modal,value.phase=="invoice" and "Endkontrolle bestanden. Rechnung am Empfang abschließen." or "Diagnose bestätigt. Folge den markierten Arbeitsschritten.",24,220,-48,104,18,colors.green) end
        button(modal,"Schließen",24,383,150,dismiss,colors.card)
    elseif kind=="challenge" then
        challenge=value;inputControl.Lock();effects.Work({tool=value.tool,point=value.point,duration=12});visible=false;tablet.Visible=false;modalTitle("Präzise arbeiten")
        text(modal,"Stoppe den Zeiger im grünen Bereich. Tippe auf STOPP oder drücke die Leertaste.",24,70,-48,70,19,colors.muted)
        local track=frame(modal,UDim2.fromOffset(532,48),UDim2.fromOffset(24,184),colors.bg)
        frame(track,UDim2.new(value.width,0,1,0),UDim2.new(value.center-value.width/2,0,0,0),colors.green)
        challenge.cursor=frame(track,UDim2.fromOffset(5,60),UDim2.new(0,-2,0,-6),colors.yellow)
        button(modal,"STOPP",24,264,532,submitChallenge)
        button(modal,"Abbrechen",24,366,180,function() send("abortInteraction",{token=value.token}) end,colors.card)
    elseif kind=="challengeEnd" then dismiss()
    elseif kind=="receipt" then
        modalTitle("Auftrag abgeschlossen")
        text(modal,value.name,24,76,-48,64,23,colors.muted)
        text(modal,t("+{credits} Credits\n+{xp} XP",{credits=fmt(value.money),xp=fmt(value.xp)}),24,151,-48,126,32,colors.green)
        button(modal,"Weiter",24,348,532,dismiss)
    elseif kind=="device" then
        local def=C.EquipmentById[value.id];if not def then return end
        modalTitle(def.name.." bereitstellen")
        text(modal,"Wähle einen freien Geräteplatz. Laufende Arbeiten und bewegte Bühnen sperren das Umstellen.",24,70,-48,70,18,colors.muted)
        for bay=1,C.MaxBays do
            local unlocked=bay<=d().bays;local occupant
            for key,assigned in pairs(d().equipmentBays) do if assigned==bay then occupant=key end end
            local available=unlocked and (not occupant or occupant==value.id)
            local status=not unlocked and "gesperrt" or occupant==value.id and "hier bereit" or occupant and "belegt" or "frei"
            button(modal,"Bühne "..bay.." · "..status,24+((bay-1)%2)*274,160+math.floor((bay-1)/2)*56,258,function()
                if available then send("assignEquipment",{id=value.id,bay=bay}) end
            end,available and colors.green or colors.card)
        end
        button(modal,"Zurück ins Lager",24,285,532,function() send("assignEquipment",{id=value.id,bay=0}) end,colors.blue)
        button(modal,"Schließen",24,366,180,dismiss,colors.card)
    elseif kind=="confirm" then
        local expansion=value.key=="bays"
        local ready=not expansion or (d().money>=value.cost and d().level>=value.level)
        modalTitle(expansion and t("Hallenanbau · Bühne {n}",{n=value.stage+1}) or "Auftrag abbrechen?")
        local description="Dieses Kundenauto wird entfernt. Bereits eingebaute Teile werden nicht erstattet. Andere Aufträge bleiben bestehen."
        if expansion then
            description=t("Neuer Hallenabschnitt mit Hebebühne {n}.\nPreis: {cost} Cr · Guthaben: {money} Cr\nAb Level {level} · Dein Level: {current}\n{status}",{n=value.stage+1,cost=fmt(value.cost),money=fmt(d().money),level=value.level,current=d().level,status=ready and "Kauf möglich" or "Noch nicht genug Credits oder Level"})
        end
        text(modal,description,24,83,-48,218,20,colors.muted)
        button(modal,"Zurück",24,330,248,dismiss,colors.card)
        button(modal,ready and "Bestätigen" or "Noch gesperrt",288,330,268,function() if ready then send("commit",{token=value.token});dismiss() end end,expansion and (ready and colors.green or colors.card) or colors.red)
    end
end)
inputControl=InputController.new(player,{
    ToggleMenu=function()
        if overlay.Visible then return end
        visible=not visible;tablet.Visible=visible;if visible then rebuild() end;if protectCoreUI then protectCoreUI() end
    end,
    StopQTE=submitChallenge,
    SelectTool=function(slot)
        if state and not overlay.Visible then send("tool",{id=state.data.loadout[slot]}) end
    end,
    ToggleMini=function() MiniClient.Toggle() end, -- 3.0: Taste M
})
-- 3.0: Minispiele starten (eigene ScreenGui "Minispiele", eigener Listener für mini*-Kinds). Gegenseitiger Ausschluss:
-- öffnet nicht während QTE/Diagnose, schließt beim Öffnen das Tablet, weicht dem Tablet; HUD blendet sich aus.
task.spawn(function()
    local ok,err=pcall(MiniClient.Start,{
        isBlocked=function() return overlay.Visible or (inputControl~=nil and inputControl.locked) end,
        isTabletOpen=function() return visible end,
        closeTablet=function() visible=false;tablet.Visible=false;if protectCoreUI then protectCoreUI() end end,
        openTablet=function(key) showPage(key) end,
        hideHud=function() refresh();refreshVehicleActions();if protectCoreUI then protectCoreUI() end end, -- 3.0: Spielerliste sofort mitschalten
        toast=toast,
    })
    if not ok then warn("[3.0] Minispiele-Start fehlgeschlagen: "..tostring(err)) end
end)
local originalPlayerList=true
pcall(function() originalPlayerList=StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList) end)
local lastListSetting
local backpackDisabled=false
protectCoreUI=function()
    if not backpackDisabled then backpackDisabled=pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack,false) end) end
    local desired=(not visible and not overlay.Visible and not MiniClient.IsOpen()) and originalPlayerList or false -- 3.0: auch über dem Minispiel-Panel aus
    if desired~=lastListSetting then
        local ok=pcall(function() StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList,desired) end)
        if ok then lastListSetting=desired end
    end
    local focused=UIS:GetFocusedTextBox()
    local editingChat=focused and not focused:IsDescendantOf(gui)
    local screen=workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280,800)
    local chatOpen=false
    if screen.X<900 then pcall(function() chatOpen=StarterGui:GetCore("ChatActive")==true end) end
    top.Visible=not editingChat and not chatOpen
end
local function resize()
    local camera=workspace.CurrentCamera;local screen=camera and camera.ViewportSize or Vector2.new(1280,800)
    width=screen.X<700 and 480 or 1060;height=screen.Y<500 and 520 or 700
    local progressWidth=screen.X>=900 and math.clamp(screen.X-840,180,310) or math.min(270,screen.X-30)
    top.Size=UDim2.fromOffset(progressWidth,46)
    stats.TextSize=progressWidth<240 and 12 or 13
    toastPanel.Size=UDim2.fromOffset(math.min(330,screen.X-28),60)
    scale=math.min(1.1,(screen.X-24)/width,(screen.Y-90)/height)
    tablet.Size=UDim2.fromOffset(width,height);tabletScale.Scale=scale
    closeButton.Position=UDim2.fromOffset(width-60,14);foot.Position=UDim2.fromOffset(22,height-30)
    modalScale.Scale=math.min(1,(screen.X-24)/580,(screen.Y-30)/440)
    local usable=screen.X*0.96-24;local tw=math.min(92,(usable-24)/5)
    for i,b in ipairs(toolButtons) do b.Position=UDim2.fromOffset(12+(i-1)*(tw+6),90);b.Size=UDim2.fromOffset(tw,30);b.TextSize=screen.X<500 and 11 or 14 end
    local first=math.min(110,usable*0.26);go.Size=UDim2.fromOffset(first,38)
    workButton.Position=UDim2.fromOffset(18+first,47);workButton.Size=UDim2.fromOffset(usable*0.35,38)
    menu.Position=UDim2.fromOffset(24+first+usable*0.35,47);menu.Size=UDim2.fromOffset(math.min(120,usable*0.3-12),38)
    -- 3.0: Minispiele-Knopf rechts neben "Menü"; ist die Zeile zu schmal (Handy hoch), teilen sich vier gleich breite Knöpfe die Zeile.
    local menuEnd=24+first+usable*0.35+math.min(120,usable*0.3-12);local room=usable+12-menuEnd-6
    if room>=110 then miniButton.Position=UDim2.fromOffset(menuEnd+6,47);miniButton.Size=UDim2.fromOffset(math.min(150,room),38);miniButton.TextSize=15
    else
        local w=(usable-18)/4
        go.Size=UDim2.fromOffset(w,38);workButton.Position=UDim2.fromOffset(18+w,47);workButton.Size=UDim2.fromOffset(w,38)
        menu.Position=UDim2.fromOffset(24+2*w,47);menu.Size=UDim2.fromOffset(w,38);miniButton.Position=UDim2.fromOffset(30+3*w,47);miniButton.Size=UDim2.fromOffset(w,38);miniButton.TextSize=13
    end
    if state then rebuild() end
end
if workspace.CurrentCamera then workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(resize) end
resize()
local mouse=player:GetMouse()
UIS.InputBegan:Connect(function(input,processed)
    if processed or UIS:GetFocusedTextBox() or visible or overlay.Visible or not state then return end
    if input.UserInputType~=Enum.UserInputType.MouseButton1 then return end
    local part=mouse.Target;if not part then return end
    local car=part
    while car and car~=workspace and not car:GetAttribute("JobId") do car=car.Parent end
    if not car or car==workspace or car:GetAttribute("OwnerUserId")~=player.UserId then return end
    local id=car:GetAttribute("JobId");local point=part:GetAttribute("WorkPoint")
    local current=job(id);local step=current and C.JobById[current.kind].steps[current.step]
    if state.tool=="scanner" and not (point and current and current.phase=="repair" and step and step.tool=="scanner" and step.point==point) then send("scan",{id=id})
    elseif point=="HoodPoint" then send("hood",{id=id})
    elseif point=="DiagnosticPoint" and not (current and current.phase=="repair" and step and step.point==point) then send("scan",{id=id,point=point})
    elseif point then send("work",{id=id,point=point})
    elseif state.tool=="scanner" then send("scan",{id=id}) end
end)
player.CharacterAdded:Connect(function() dismiss() end)
PromptService.PromptShown:Connect(function(prompt)
    local ancestor=prompt.Parent
    while ancestor and ancestor~=workspace do
        local owner=ancestor:GetAttribute("OwnerUserId")
        if owner and owner~=player.UserId then prompt.Enabled=false;return end
        ancestor=ancestor.Parent
    end
    if prompt:GetAttribute("VehicleAction") then shownPrompts[prompt]=true;refreshVehicleActions() end
end)
PromptService.PromptHidden:Connect(function(prompt) shownPrompts[prompt]=nil;refreshVehicleActions() end)
local nextLightUpdate=0
Run.RenderStepped:Connect(function()
    if state and os.clock()>=nextLightUpdate then
        -- Presentation interpolates the one server epoch; no client-owned days.
        Lighting.ClockTime=R.DayClock(workspace:GetServerTimeNow(),state.dayEpoch);nextLightUpdate=os.clock()+0.1
    end
    if challenge and challenge.cursor then challenge.cursor.Position=UDim2.new(R.GaugePosition(workspace:GetServerTimeNow(),challenge.startAt,challenge.period),-2,0,-6) end
end)
task.spawn(function() while gui.Parent do task.wait(0.25);protectCoreUI();if state then refresh();markTarget();refreshVehicleActions() end end end)
-- Retry only until the server has finished loading the profile. Same existing remote.
task.spawn(function()
    while gui.Parent and not state do send("hello");task.wait(1) end
end)
