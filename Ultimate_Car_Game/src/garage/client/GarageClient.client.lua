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
local eventListeners={} -- 3.0: Abonnenten (MiniClient-Handy) für Server-Ereignisse "call"
local tester,nextHint,handButton -- 3.0: OBD-Tester, Hinweis zum nächsten Handgriff, Slot „Hand“
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
objective.Name="ObjectiveLine" -- 3.0: Ziel + nächster Handgriff immer direkt über der Werkzeugleiste
local go=button(hud,"Zum Ziel",12,47,110,function() send("target",{id=state and state.selected}) end,colors.blue)
local workButton=button(hud,"Arbeiten [E]",130,47,140,function() if state then send("work",{id=state.selected}) end end)
local menu=button(hud,"Menü [Tab]",278,47,120,function() visible=not visible;tablet.Visible=visible;if visible and rebuild then rebuild() end end,colors.card)
local miniButton=button(hud,"Minispiele [M]",406,47,140,function() MiniClient.Toggle() end,colors.card);miniButton.Name="MiniGames" -- 3.0: Einstieg neben "Menü" (Größe in resize)
local toolButtons={}
for i=1,C.HotbarSize do
    toolButtons[i]=button(hud,(i+1).." · —",12+i*98,90,92,function() -- 3.0: Platz i liegt auf Taste i+1 (Taste 1 = Hand)
        if state and not overlay.Visible then send("tool",{id=state.data.loadout[i]}) end
    end,colors.card)
    toolButtons[i].Name="ToolSlot"..i;toolButtons[i].Size=UDim2.fromOffset(92,30)
end
-- 3.0: fester erster Slot „Hand“ (Taste 1): freie Hand, kein Werkzeug. Gezeichnet aus Frames (keine Asset-IDs).
handButton=button(hud,"",12,90,92,function() -- 3.0
    if state and not overlay.Visible then send("tool",{id="hand"}) end -- 3.0
end,colors.card);handButton.Name="ToolSlotHand";handButton.Size=UDim2.fromOffset(92,30) -- 3.0
do -- 3.0: Symbol offene Hand (Handfläche, vier Finger, Daumen) + Tastenziffer
    local key=make("TextLabel",handButton,{Name="Key",Text="1",Position=UDim2.fromOffset(4,0),Size=UDim2.new(0,14,1,0),BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=colors.text}) -- 3.0
    local icon=make("Frame",handButton,{Name="HandIcon",AnchorPoint=Vector2.new(0,0.5),Position=UDim2.new(0,18,0.5,0),Size=UDim2.fromOffset(22,22),BackgroundTransparency=1,BorderSizePixel=0}) -- 3.0: links, daneben das Wort „Hand“
    make("TextLabel",handButton,{Name="HandLabel",Text=t("Hand"),Position=UDim2.fromOffset(42,0),Size=UDim2.new(1,-44,1,0),BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=13,TextColor3=colors.text,TextXAlignment=Enum.TextXAlignment.Left,TextScaled=false}) -- 3.0: Klartext statt nur Symbol
    local skin=Color3.fromRGB(246,214,178) -- 3.0
    local palm=make("Frame",icon,{Name="Palm",Position=UDim2.fromOffset(6,10),Size=UDim2.fromOffset(12,11),BackgroundColor3=skin,BorderSizePixel=0});corner(palm,4) -- 3.0
    for f,spec in ipairs({{6,3,8},{9,1,10},{12,1,10},{15,3,8}}) do -- 3.0: x, y, Höhe je Finger
        local finger=make("Frame",icon,{Name="Finger"..f,Position=UDim2.fromOffset(spec[1],spec[2]),Size=UDim2.fromOffset(3,spec[3]+2),BackgroundColor3=skin,BorderSizePixel=0});corner(finger,2) -- 3.0
    end
    local thumb=make("Frame",icon,{Name="Thumb",Position=UDim2.fromOffset(1,11),Size=UDim2.fromOffset(7,3),Rotation=-35,BackgroundColor3=skin,BorderSizePixel=0});corner(thumb,2) -- 3.0
    key.ZIndex=handButton.ZIndex -- 3.0
end
local toastPanel=frame(gui,UDim2.fromOffset(330,60),UDim2.new(0.5,0,0,62),colors.panel);toastPanel.AnchorPoint=Vector2.new(0.5,0);toastPanel.Visible=false
local toastLabel=text(toastPanel,"",14,3,-28,54,14)
local toastSerial=0
local function toast(value)
    toastSerial=toastSerial+1;local serial=toastSerial
    toastLabel.Text=t(value);toastPanel.Visible=true
    if MiniClient.ToastTop then local ok,top=pcall(MiniClient.ToastTop);toastPanel.Position=UDim2.new(0.5,0,0,ok and type(top)=="number" and top or 62) end -- 3.0: während der Fahrt unter dem Tacho
    task.delay(4,function() if serial==toastSerial then toastPanel.Visible=false end end)
end
overlay=make("Frame",gui,{Name="InteractionOverlay",Size=UDim2.fromScale(1,1),BackgroundColor3=Color3.new(),BackgroundTransparency=0.25,BorderSizePixel=0,Visible=false,ZIndex=10,Active=true})
local modal=frame(overlay,UDim2.fromOffset(580,440),UDim2.fromScale(0.5,0.5),colors.panel);modal.AnchorPoint=Vector2.new(0.5,0.5)
local modalScale=make("UIScale",modal,{Scale=1})
local function clearModal() for _,v in ipairs(modal:GetChildren()) do if not v:IsA("UIScale") and not v:IsA("UICorner") then v:Destroy() end end end
local function dismiss() challenge=nil;diagnosis=nil;overlay.Visible=false;effects.StopWork();if inputControl then inputControl.Unlock() end;if tester then tester.Hide() end end -- 3.0: schließt auch den OBD-Tester
local function submitChallenge()
    if not challenge or challenge.submitted then return end
    challenge.submitted=true
    -- The server owns completion. Keep the dialog until its acknowledgement.
    send("hit",{token=challenge.token,at=workspace:GetServerTimeNow()})
end
local function modalTitle(value)
    if tester then tester.Hide() end;modal.Visible=true -- 3.0: andere Dialoge ersetzen den OBD-Tester
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
    return t(({diagnose="Diagnose offen",verify="Endkontrolle offen",invoice="Bereit zur Abrechnung",approval="Freigabe offen: Kunden mit dem Handy anrufen (P)"})[j.phase] or j.phase) -- 3.0: Phase approval (Kundenfreigabe)
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
    note("Taste 1 ist deine freie Hand. Die Tasten 2–6 sind fünf Werkzeugplätze: Wähle einen Platz und dann ein Werkzeug. Tauschen geht nur hier vor Ort.") -- 3.0: Hand-Slot
    local c=card(112);heading(c,"Deine Werkzeugleiste")
    local bw=math.min(176,(width-80)/5-6)
    for i=1,C.HotbarSize do
        local id=d().loadout[i]
        button(c,(i+1).." · "..C.Tools[id].short,16+(i-1)*(bw+6),54,bw,function() toolSlot=i;rebuild() end,toolSlot==i and colors.green or colors.card) -- 3.0: Tastenziffer (Taste 1 = Hand)
    end
    for _,id in ipairs(C.ToolOrder) do
        local def=C.Tools[id];local unlocked=R.ToolUnlocked(d(),id)
        local status=R.ToolActive(d(),id) and "Aktiv in der Leiste" or "In der Werkzeugkiste"
        local description=def.description or ({scanner="Fehlerspeicher, Diagnose und Endkontrolle.",ratchet="Befestigungen und Reparaturen am Fahrzeug.",oil="Ölservice und Flüssigkeitswechsel.",tire="Reifenmontage mit der Montiermaschine.",meter="Elektrische Messungen und Fehlersuche."})[id]
        c=card(184);heading(c,def.name,description)
        text(c,unlocked and status or ("Benötigt: "..C.EquipmentById[def.equipment].name),16,89,-32,30,14,colors.muted)
        button(c,"Auf Taste "..(toolSlot+1).." legen",16,132,220,function() send("swapTool",{slot=toolSlot,id=id}) end,unlocked and colors.green or colors.card) -- 3.0: Taste statt Platznummer
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
    -- 3.0: Credit-Center: auch die Game Passes der Minispiele (Kauf über mini_pass_prompt, den Roblox-Dialog öffnet der Server)
    local function passes() local s=MiniClient.Snapshot and MiniClient.Snapshot();return type(s)=="table" and type(s.passes)=="table" and s.passes or {} end -- 3.0
    for _,pass in ipairs({{key="DoubleScrap",field="doubleScrap",name="Game Pass · 2× Schrott",sub="Doppelter Schrott aus Klicks und Maschinen der Schrottpresse. Kein Einfluss auf die Bestenliste."},{key="PressPlus",field="pressPlus",name="Game Pass · Schrottpresse+",sub="Stärkere Maschinen in der Schrottpresse. Kein Einfluss auf die Bestenliste."}}) do -- 3.0
        local c=card(170);heading(c,pass.name,pass.sub,60) -- 3.0
        bind(button(c,"",16,112,260,function() local ps=passes();if ps[pass.field] then return toast("Diesen Game Pass hast du bereits.") end;send("mini_pass_prompt",{pass=pass.key}) end,colors.purple),function() -- 3.0
            local ps=passes();if ps[pass.field] then return "Bereits aktiv ✓" end;if ps[pass.field.."Configured"]==false then return "In Kürze verfügbar" end;return "Game Pass kaufen" end) -- 3.0
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
-- 3.0: Klartext für den nächsten Handgriff (Bühne, Haube, Werkzeug) aus dem Server-Zustand. Zeigt, woran ein
-- Arbeitsschritt gerade scheitert (sonst nur ein kurzer Toast) – gegen „ich stecke fest“.
nextHint=function() -- 3.0
    -- 3.0: Werkzeug, Hebebühne, Motorhaube und Gerät stellt der Server beim E-Druck selbst (prepare/autoTool).
    -- 3.0: Der Hinweis nennt darum nur Hürden, die E nicht lösen kann (Werkzeug nicht in der Leiste, Gerät/Teil fehlt).
    local j=job();if not j then return nil end
    local def=C.JobById[j.kind];local v=state.visuals and state.visuals[j.id] or {}
    local data=d()
    local function inBar(id) -- 3.0
        if id==C.HandTool then return true end
        for _,x in ipairs(data.loadout or {}) do if x==id then return true end end
        return false
    end
    local function toolBlocker(step) -- 3.0: nil = Server nimmt das Werkzeug selbst
        if R.ToolMatches(step,state.tool) and inBar(state.tool) then return nil end
        if inBar(step.tool) and R.ToolUnlocked(data,step.tool) then return nil end
        for key in pairs(step.alternatives or {}) do if inBar(key) and R.ToolUnlocked(data,key) then return nil end end
        local tool=C.Tools[step.tool];local name=tool and tool.name or tostring(step.tool)
        if tool and not R.ToolUnlocked(data,step.tool) and tool.equipment and C.EquipmentById[tool.equipment] then
            return t("{tool} fehlt: Kaufe {device} an der Ausbau-Werkbank",{tool=name,device=C.EquipmentById[tool.equipment].name})
        end
        return t("{tool} an der Werkzeugkiste in die Leiste legen",{tool=name})
    end
    if v.moving then return t("Warte, bis die Bühne stillsteht.") end
    if j.phase=="approval" then return t("Kunden mit dem Handy anrufen (P) und die Reparatur freigeben lassen") end
    if j.phase=="diagnose" then return toolBlocker({tool="scanner"}) or t("Am OBD-Anschluss (Fahrerseite) E drücken") end
    if j.phase=="verify" then return toolBlocker({tool="scanner"}) or t("Endkontrolle: am OBD-Anschluss E drücken") end -- 3.0: Bühne/Haube macht E selbst
    if j.phase=="repair" then
        local step=def and def.steps[j.step];if not step then return nil end
        if step.equipment and (data.equipment[step.equipment] or 0)<(step.equipmentLevel or 1) and C.EquipmentById[step.equipment] then
            return t("{device} fehlt: an der Ausbau-Werkbank kaufen",{device=C.EquipmentById[step.equipment].name})
        end
        local blocker=toolBlocker(step);if blocker then return blocker end
        if step.part and not R.ChoosePart(data,j,step.part) then return t("Ersatzteil fehlt: im Teilehandel kaufen oder eine andere Marke wählen") end
        return t("Am markierten Bauteil E drücken – Werkzeug, Bühne und Haube kommen automatisch")
    end
    return nil
end
refresh=function()
    hud.Visible=not visible and not overlay.Visible and not MiniClient.IsOpen() -- 3.0: HUD weicht dem Minispiel-Panel
    if not state then return end
    stats.Text=t("Lv. {level}  ·  {credits} Cr",{credits=fmt(d().money),level=d().level})
    local clock=R.DayClock(workspace:GetServerTimeNow(),state.dayEpoch)
    headline.Text=t("TAG {day} · {hour}:{minute}",{day=d().days+1,hour=string.format("%02d",math.floor(clock)),minute=string.format("%02d",math.floor(clock%1*60))})
    xpFill.Size=UDim2.new(math.clamp(d().xp/state.neededXP,0,1),0,1,0)
    local okHint,hint=pcall(nextHint) -- 3.0: Ziel + nächster Handgriff (pcall: ein Anzeigefehler darf refresh nicht abbrechen)
    local goal=t(state.objective or "");if okHint and type(hint)=="string" and hint~="" and hint~=goal then goal=goal.."\n→ "..hint end -- 3.0
    objective.Text=goal;objective.TextSize=(#goal>95 or hud.AbsoluteSize.X<520) and 12 or #goal>60 and 14 or 16 -- 3.0: passt immer in die Zeile
    foot.Text=t(state.saveStatus).." · v"..C.Version.." · "..t("TAB Menü · 1 Hand · 2–6 Werkzeug · E Arbeit · H Haube · F Bühne") -- 3.0: Hand-Slot
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
        b.Text=(i+1).." · "..(C.Tools[id] and C.Tools[id].short or "—");b.BackgroundColor3=state.tool==id and colors.green or colors.card -- 3.0: Taste i+1
        b.TextColor3=unlocked and colors.text or colors.muted
    end
    for _,binding in ipairs(bindings) do if binding.obj.Parent then binding.obj.Text=t(binding.getter()) end end
    local handOn=state.tool==nil or state.tool=="hand" or not C.Tools[state.tool] -- 3.0: Hand-Slot hervorheben
    handButton.BackgroundColor3=handOn and colors.green or colors.card -- 3.0
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
marker.Active=false;markerText.Active=false -- 3.0: Zielmarke über dem Auto schluckt nie Klicks/Touches
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
-- 3.0: Roblox blendet einen Prompt bei RequiresLineOfSight/Exclusivity (z. B. unter der gehobenen Bühne) gar nicht ein;
-- dann käme kein PromptShown und es gäbe keinen E/F/H-Knopf. Darum zusätzlich die Fahrzeug-Prompts des eigenen
-- Grundstücks (state.plot) direkt prüfen (Liste alle 1,5 s neu, Reichweite/Enabled wie beim eingeblendeten Prompt).
local plotPrompts,plotPromptsAt,plotPromptsFor={},0,nil -- 3.0
local function candidatePrompts() -- 3.0
    local plot=state and state.plot
    if typeof(plot)=="Instance" and plot.Parent and (os.clock()>=plotPromptsAt or plotPromptsFor~=plot) then
        plotPrompts={};plotPromptsAt=os.clock()+1.5;plotPromptsFor=plot
        local cars=plot:FindFirstChild("ActiveCars");local bays=plot:FindFirstChild("Bays")
        for _,folder in ipairs({cars,bays}) do
            if folder then for _,x in ipairs(folder:GetDescendants()) do if x:IsA("ProximityPrompt") and x:GetAttribute("VehicleAction") then table.insert(plotPrompts,x) end end end
        end
    end
    local out={};for prompt in pairs(shownPrompts) do out[prompt]=true end
    for _,prompt in ipairs(plotPrompts) do if prompt.Parent then out[prompt]=true end end
    return out
end
local function refreshVehicleActions()
    local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    local count=0
    local candidates=candidatePrompts() -- 3.0
    for _,record in ipairs(vehicleButtons) do
        local chosen,nearest=nil,math.huge
        for prompt in pairs(candidates) do -- 3.0: eingeblendete + eigene Fahrzeug-Prompts
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
-- 3.0: OBD-Tester „UCG-Tester 3000“: robustes Handgerät im selben Overlay (ScreenGui UltimateCarGame, DisplayOrder 20).
-- 3.0: Seiten Fehlerspeicher, Messwerte, Befund (Antworten der Diagnose), Endkontrolle (Prüfliste, danach der bisherige
-- 3.0: scan) und „Verbinden/Auslesen“, solange der Server-Scan läuft. Aktionen unverändert: scan, diagnose, abortInteraction.
-- 3.0: Felder im diagnose-Ereignis (Server 3.0): codes = {{code, text} | "P0302: …"}, live (oder values) = {{name, value, unit?} |
-- 3.0: "Name: Wert"}, message, finding/findingName, customer, approved, phase "approval" (Kunde muss freigeben).
-- 3.0: Fehlen codes/live, liest der Tester Codes und Werte aus report (Zeilen „P0302: …“ bzw. „Name: Wert“).
tester=(function() -- 3.0
    local api={page=nil,data=nil,jobId=nil,scanStart=nil,scanDuration=2.5,scanSerial=0,verifyAnim=nil} -- 3.0
    local mono=Enum.Font.RobotoMono -- 3.0
    local G={green=Color3.fromRGB(96,255,150),dim=Color3.fromRGB(58,168,98),amber=Color3.fromRGB(255,196,64),red=Color3.fromRGB(255,96,96), -- 3.0
        screen=Color3.fromRGB(8,22,13),body=Color3.fromRGB(44,47,53),key=Color3.fromRGB(64,69,78),keyOn=Color3.fromRGB(236,152,32),bumper=Color3.fromRGB(236,152,32),dark=Color3.fromRGB(20,22,26)} -- 3.0
    local W,H,portrait=640,440,false -- 3.0
    local root=make("Frame",overlay,{Name="ObdTester",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.5),Size=UDim2.fromOffset(W,H),BackgroundColor3=G.body,BorderSizePixel=0,Visible=false,Active=true,ZIndex=11}) -- 3.0
    local scaleObj=make("UIScale",root,{Scale=1}) -- 3.0
    corner(root,26);make("UIStroke",root,{Color=G.bumper,Thickness=5}) -- 3.0: gummierter Rahmen
    make("UIGradient",root,{Rotation=90,Color=ColorSequence.new(Color3.fromRGB(255,255,255),Color3.fromRGB(170,170,170))}) -- 3.0
    local pads={} -- 3.0: Eckpuffer
    for i=1,4 do pads[i]=make("Frame",root,{Name="Bumper"..i,Size=UDim2.fromOffset(30,30),BackgroundColor3=G.bumper,BorderSizePixel=0});corner(pads[i],10) end -- 3.0
    local brand=make("TextLabel",root,{Name="Brand",Text="UCG-Tester 3000",Position=UDim2.fromOffset(28,10),Size=UDim2.fromOffset(240,22),BackgroundTransparency=1,Font=Enum.Font.GothamBlack,TextSize=19,TextColor3=G.bumper,TextXAlignment=Enum.TextXAlignment.Left}) -- 3.0
    local model=make("TextLabel",root,{Name="Model",Text="OBD-II · Profi-Diagnose",Position=UDim2.fromOffset(28,30),Size=UDim2.fromOffset(240,14),BackgroundTransparency=1,Font=Enum.Font.Gotham,TextSize=11,TextColor3=Color3.fromRGB(170,176,186),TextXAlignment=Enum.TextXAlignment.Left}) -- 3.0
    local leds=make("Frame",root,{Name="Leds",Size=UDim2.fromOffset(200,24),BackgroundTransparency=1,BorderSizePixel=0}) -- 3.0
    local led={} -- 3.0
    for i,spec in ipairs({{"power","PWR"},{"link","LINK"},{"fault","FEHLER"}}) do -- 3.0
        local dot=make("Frame",leds,{Name="Led_"..spec[1],Position=UDim2.fromOffset((i-1)*68,6),Size=UDim2.fromOffset(12,12),BackgroundColor3=G.dark,BorderSizePixel=0});corner(dot,6) -- 3.0
        make("UIStroke",dot,{Color=Color3.fromRGB(12,12,14),Thickness=1}) -- 3.0
        make("TextLabel",leds,{Name="LedLabel_"..spec[1],Text=spec[2],Position=UDim2.fromOffset((i-1)*68+16,0),Size=UDim2.fromOffset(50,24),BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=10,TextColor3=Color3.fromRGB(170,176,186),TextXAlignment=Enum.TextXAlignment.Left}) -- 3.0
        led[spec[1]]=dot -- 3.0
    end
    local screen=make("Frame",root,{Name="TesterScreen",BackgroundColor3=G.screen,BorderSizePixel=0,ClipsDescendants=true}) -- 3.0: grün auf dunkel
    corner(screen,8);make("UIStroke",screen,{Color=Color3.fromRGB(18,20,22),Thickness=4}) -- 3.0: Display-Einfassung
    local function mlabel(parent,name,value,x,y,w,h,size,color) -- 3.0: Monospace-Zeile
        return make("TextLabel",parent,{Name=name,Text=value,Position=UDim2.fromOffset(x,y),Size=UDim2.new(1,w,0,h),BackgroundTransparency=1,Font=mono,TextSize=size or 15,TextColor3=color or G.green,TextWrapped=true,TextXAlignment=Enum.TextXAlignment.Left,TextYAlignment=Enum.TextYAlignment.Center}) -- 3.0
    end
    local titleLabel=mlabel(screen,"TesterTitle","Fahrzeugdiagnose · OBD",10,4,-20,22,16,G.green);titleLabel.Font=Enum.Font.Code -- 3.0
    local subLabel=mlabel(screen,"TesterPage","",10,26,-20,18,13,G.dim) -- 3.0
    local rule=make("Frame",screen,{Name="Rule",Position=UDim2.fromOffset(8,47),Size=UDim2.new(1,-16,0,1),BackgroundColor3=G.dim,BorderSizePixel=0}) -- 3.0
    local content=make("ScrollingFrame",screen,{Name="TesterContent",Position=UDim2.fromOffset(8,52),Size=UDim2.new(1,-16,1,-82),BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,ScrollBarImageColor3=G.dim,CanvasSize=UDim2.new()}) -- 3.0
    local status=mlabel(screen,"TesterStatus","",10,0,-20,24,12,G.amber);status.AnchorPoint=Vector2.new(0,1);status.Position=UDim2.new(0,10,1,-4) -- 3.0
    local keys,keyOrder={}, {"codes","values","finding","verify","close"} -- 3.0
    local keyNames={codes="Fehlerspeicher",values="Messwerte",finding="Befund",verify="Endkontrolle",close="Schließen"} -- 3.0
    local function tkey(parent,name,value,callback,color) -- 3.0: große Gerätetaste (≥ 44 px auch auf dem Handy)
        local b=make("TextButton",parent,{Name=name,Text=t(value),BackgroundColor3=color or G.key,TextColor3=colors.text,Font=Enum.Font.GothamBold,TextSize=14,TextWrapped=true,AutoButtonColor=true,BorderSizePixel=0}) -- 3.0
        corner(b,10);make("UIStroke",b,{Color=Color3.fromRGB(16,17,20),Thickness=2,ApplyStrokeMode=Enum.ApplyStrokeMode.Border}) -- 3.0
        local press=make("UIScale",b,{Scale=1}) -- 3.0
        b.Activated:Connect(function() press.Scale=0.94;Tween:Create(press,TweenInfo.new(0.16,Enum.EasingStyle.Back,Enum.EasingDirection.Out),{Scale=1}):Play();callback() end) -- 3.0
        return b -- 3.0
    end
    local render -- 3.0
    local function now() return workspace:GetServerTimeNow() end -- 3.0
    local function currentJob() return state and api.jobId and R.FindJob(d(),api.jobId) or nil end -- 3.0
    local function codesOf(v) -- 3.0: Fehlercodes aus codes oder aus report
        local out={}
        if type(v)~="table" then return out end
        if type(v.codes)=="table" then
            for _,c in ipairs(v.codes) do
                if type(c)=="string" then local code,txt=c:match("^(%u%d%d%d%d)%s*[:%-]?%s*(.*)$");table.insert(out,{code=code or "",text=code and txt or c})
                elseif type(c)=="table" then table.insert(out,{code=tostring(c.code or c.id or ""),text=tostring(c.text or c.name or c.description or "")}) end
            end
            return out
        end
        for line in tostring(v.report or ""):gmatch("[^\n]+") do
            local code,txt=line:match("^([PBCU]%d%d%d%d)%s*:%s*(.*)$")
            if code then table.insert(out,{code=code,text=txt}) end
        end
        return out
    end
    local function memoryNote(v) -- 3.0: „Fehlerspeicher: …“-Zeile des Berichts
        for line in tostring(type(v)=="table" and v.report or ""):gmatch("[^\n]+") do local rest=line:match("^Fehlerspeicher:%s*(.*)$");if rest then return rest end end
        return nil
    end
    local function valuesOf(v) -- 3.0: Messwerte aus values oder den übrigen Berichtszeilen
        local out={}
        if type(v)~="table" then return out end
        local list=type(v.live)=="table" and v.live or v.values -- 3.0: Server liefert live
        if type(list)=="table" then
            for _,x in ipairs(list) do
                if type(x)=="string" then local n,val=x:match("^(.-):%s*(.*)$");table.insert(out,{name=n or x,value=n and val or ""})
                elseif type(x)=="table" then table.insert(out,{name=tostring(x.name or ""),value=tostring(x.value or "")..(x.unit and (" "..tostring(x.unit)) or "")}) end
            end
        end
        return out
    end
    local function reportLines(v) -- 3.0: Prüfbericht ohne Codes und Fehlerspeicher-Zeile
        local out={}
        for line in tostring(type(v)=="table" and v.report or ""):gmatch("[^\n]+") do
            local n,val=line:match("^(.-):%s*(.*)$")
            if n and not n:match("^[PBCU]%d%d%d%d$") and n~="Fehlerspeicher" then table.insert(out,{name=n,value=val}) elseif not n then table.insert(out,{name=line,value=""}) end
        end
        return out
    end
    function api.NeedsCall() -- 3.0: Befund mit Fehlern -> Kunde muss am Handy freigeben
        local v=api.data;if type(v)~="table" then return false end
        if v.needsApproval==true or v.phase=="approval" then return true end
        local j=currentJob();return j~=nil and j.phase=="approval"
    end
    local function setLed(name,color) led[name].BackgroundColor3=color or G.dark end -- 3.0
    local function clearContent() for _,c in ipairs(content:GetChildren()) do if c:IsA("GuiObject") then c:Destroy() end end end -- 3.0
    local cy=0 -- 3.0: Schreibposition im Inhalt
    local function line(name,value,color,size,h) -- 3.0
        local l=mlabel(content,name,value,0,cy,-8,h or 22,size or (portrait and 14 or 15),color);cy=cy+(h or 22)+2;return l
    end
    local function contentWidth() return (W-36)-16-8 end -- 3.0
    local function contentKey(name,value,callback,color,h) -- 3.0: Taste im Bildschirm (Antworten, Handy, Abbrechen)
        local hh=math.max(h or 56,math.ceil(44/math.max(0.1,scaleObj.Scale))+2) -- 3.0: nach UIScale immer ≥ 44 px (Handy quer)
        local b=tkey(content,name,value,callback,color);b.Position=UDim2.fromOffset(0,cy);b.Size=UDim2.fromOffset(contentWidth(),hh);cy=cy+hh+8;return b
    end
    local function hint(name,value,color) -- 3.0: hervorgehobener Hinweis (z. B. Kundenfreigabe)
        local f=make("Frame",content,{Name=name,Position=UDim2.fromOffset(0,cy),Size=UDim2.fromOffset(contentWidth(),portrait and 74 or 56),BackgroundColor3=Color3.fromRGB(64,46,8),BorderSizePixel=0});corner(f,8) -- 3.0
        make("UIStroke",f,{Color=color or G.amber,Thickness=2}) -- 3.0
        local l=make("TextLabel",f,{Name="Text",Text=t(value),Position=UDim2.fromOffset(10,4),Size=UDim2.new(1,-20,1,-8),BackgroundTransparency=1,Font=Enum.Font.GothamBold,TextSize=15,TextWrapped=true,TextColor3=color or G.amber,TextXAlignment=Enum.TextXAlignment.Left}) -- 3.0
        cy=cy+f.Size.Y.Offset+8;return f,l -- 3.0
    end
    local function verifyChecks() -- 3.0: Prüfliste der Endkontrolle aus dem Server-Zustand
        local j=currentJob();local v=j and state.visuals and state.visuals[j.id] or {}
        local phaseName=j and j.phase or (api.data and api.data.phase)
        local done=phaseName=="verify" or phaseName=="invoice"
        return {
            {ok=done,text=done and "Alle Arbeitsschritte erledigt" or "Arbeitsschritte noch offen",fix=j and phaseName=="repair" and t(C.JobById[j.kind].steps[j.step] and C.JobById[j.kind].steps[j.step].name or "") or nil},
            -- 3.0: Bühne, Haube und Tester stellt der Server beim Start der Endkontrolle selbst (work scanOnly): kein Blocker
            {ok=not v.lifted,auto=true,text="Hebebühne unten",fix="wird automatisch abgesenkt"},
            {ok=not v.hood,auto=true,text="Motorhaube geschlossen",fix="wird automatisch geschlossen"},
            {ok=state and state.tool=="scanner",auto=true,text="OBD-Tester angeschlossen",fix="wird automatisch angeschlossen"},
        },phaseName -- 3.0
    end
    local liveLabels={} -- 3.0
    local function liveValues(at) -- 3.0: simulierte Live-Daten (Leerlauf)
        return {
            {"Motordrehzahl",string.format("%4d 1/min",math.floor(790+math.sin(at*2.1)*22+math.sin(at*7.3)*6))},
            {"Bordspannung",string.format("%.2f V",14.05+math.sin(at*1.3)*0.06)},
            {"Kühlmittel",string.format("%d °C",math.floor(89+math.sin(at*0.4)*1.5))},
            {"Öltemperatur",string.format("%d °C",math.floor(94+math.sin(at*0.3)*1.2))},
            {"Ansaugluft",string.format("%d °C",math.floor(27+math.sin(at*0.7)))},
            {"Lambda",string.format("%.3f",1+math.sin(at*5)*0.012)},
        }
    end
    local function pad(s,n) s=tostring(s);return s..string.rep(" ",math.max(1,n-utf8.len(s))) end -- 3.0
    local pageTitles={codes="FEHLERSPEICHER",values="MESSWERTE (LIVE)",finding="BEFUND",verify="ENDKONTROLLE",scan="VERBINDUNG"} -- 3.0
    render=function() -- 3.0
        clearContent();cy=0;liveLabels={}
        local v=api.data;local j=currentJob()
        local car=(type(v)=="table" and v.car) or (j and C.CarById[j.carId] and C.CarById[j.carId].name) or ""
        subLabel.Text="» "..(pageTitles[api.page] or "").."  ·  "..t(car)
        for _,key in ipairs(keyOrder) do local b=keys[key];if b then local on=key==api.page;b.BackgroundColor3=key=="close" and Color3.fromRGB(150,52,60) or on and G.keyOn or G.key;b.TextColor3=on and G.dark or colors.text end end
        local codes=codesOf(v);local call=api.NeedsCall()
        setLed("power",G.green);setLed("link",api.page=="scan" and G.amber or (v and G.green) or G.dark);setLed("fault",(#codes>0 or call) and G.red or nil)
        if api.page=="scan" then
            local verify=api.scanVerify
            line("ScanHead",verify and "Endkontrolle läuft …" or "Verbinde mit Fahrzeug …",G.green,16,24)
            local track=make("Frame",content,{Name="ScanTrack",Position=UDim2.fromOffset(0,cy+4),Size=UDim2.fromOffset(contentWidth(),18),BackgroundColor3=Color3.fromRGB(16,44,26),BorderSizePixel=0});corner(track,4)
            api.scanFill=make("Frame",track,{Name="ScanFill",Size=UDim2.fromScale(0,1),BackgroundColor3=G.green,BorderSizePixel=0});corner(api.scanFill,4)
            cy=cy+30;api.scanPercent=line("ScanPercent","  0 %",G.green,14,20)
            api.scanSteps={}
            for i,s in ipairs(verify and {"Steuergeräte abfragen","Hebebühne unten","Motorhaube geschlossen","Fehlerspeicher leer","Messwerte im Sollbereich"} or {"Verbindung aufbauen","Steuergeräte suchen: Motor, ABS, Airbag","Fehlerspeicher lesen","Messwerte erfassen"}) do
                api.scanSteps[i]={label=line("ScanStep"..i,"[ ] "..s,G.dim,14,20),text=s}
            end
        elseif api.page=="codes" then
            line("CodesHead",#codes>0 and t("{n} Fehler gespeichert",{n=#codes}) or "Keine Fehler gespeichert",#codes>0 and G.red or G.green,16,24)
            for i,c in ipairs(codes) do line("Code"..i,pad(c.code,7)..t(c.text),G.amber,15,portrait and 40 or 24) end
            if #codes==0 then line("CodesNote",memoryNote(v) and ("Status: "..memoryNote(v)) or "Status: 0 Einträge",G.dim,14,22) end
            if type(v)=="table" and v.findingName and v.approved==true then line("Approved",t("Freigegeben: {name}",{name=v.findingName}),G.green,14,portrait and 40 or 22) end
            if type(v)=="table" and v.findingName and v.approved==false then line("Declined","Kunde hat abgelehnt: nur den Check fertig machen.",G.amber,14,portrait and 40 or 22) end
            if call then
                cy=cy+4;hint("ApprovalHint","Kunde muss die Reparatur freigeben – ruf ihn mit dem Handy an (P)")
                if type(v)=="table" and (v.findingName or v.customer) then line("ApprovalWho",t("Befund: {f} · Kunde: {c}",{f=v.findingName or "–",c=v.customer or "–"}),G.amber,13,portrait and 40 or 22) end
                -- 3.0: Handy der Minispiele, falls vorhanden; sonst direkt die bestehende Aktion call über Command
                contentKey("CallCustomer","Kunden anrufen (P)",function()
                    local id=api.jobId;dismiss()
                    local okPhone,opened=false,false;if type(MiniClient.OpenPhone)=="function" then okPhone,opened=pcall(MiniClient.OpenPhone,{job=id}) end -- 3.0: nur wenn das Handy wirklich offen ist
                    if okPhone and opened==true then return end -- 3.0: sonst den Anruf selbst senden
                    send("call",{id=id})
                end,Color3.fromRGB(46,98,170),48)
            end
        elseif api.page=="values" then
            local list=valuesOf(v) -- 3.0: Werte des Servers; ohne sie simulierte Leerlauf-Werte (live)
            if #list>0 then
                local base=C.LiveValues and {} or nil;for _,x in ipairs(C.LiveValues or {}) do base[x.name]=x.value end
                for i,x in ipairs(list) do local off=base and base[x.name]~=nil and base[x.name]~=x.value or (base and base[x.name]==nil);line("Value"..i,x.value~="" and (pad(x.name,22)..x.value) or x.name,off and G.amber or G.green,14,portrait and 38 or 20) end
            else
                for i,x in ipairs(liveValues(now())) do liveLabels[i]=line("Live"..i,pad(x[1],16)..x[2],G.green,14,20) end
            end
            local lines=reportLines(v)
            if #lines>0 then cy=cy+4;line("ReportHead","PRÜFBERICHT",G.dim,12,16);for i,x in ipairs(lines) do line("Report"..i,x.value~="" and (x.name..": "..x.value) or x.name,G.dim,13,portrait and 36 or 20) end end
        elseif api.page=="finding" then
            local answers=type(v)=="table" and v.phase=="diagnose" and type(v.answers)=="table" and v.answers or {}
            if #answers>0 then
                line("FindingHead","Welche Ursache passt zum Befund?",G.green,15,portrait and 40 or 24)
                for i,answer in ipairs(answers) do contentKey("Answer_"..i,answer,function() send("diagnose",{id=v.job,choice=i}) end,colors.blue,portrait and 54 or 56) end
            else
                for i,x in ipairs(reportLines(v)) do line("Report"..i,x.value~="" and (x.name..": "..x.value) or x.name,G.dim,14,portrait and 38 or 22) end
                cy=cy+4
                local done="Diagnose bestätigt. Folge den markierten Arbeitsschritten." -- 3.0: Text je Phase
                if type(v)=="table" and v.phase=="invoice" then done="Endkontrolle bestanden. Rechnung am Empfang abschließen."
                elseif call then done=t("Befund: {f}. Erst reparieren, wenn der Kunde zustimmt.",{f=v.findingName or "Fehler gespeichert"})
                elseif type(v)=="table" and v.kind=="inspection" and not v.finding then done="Keine Fehler gespeichert. Jetzt die Sichtprüfung am Auto durchführen." end
                line("FindingDone",done,G.green,15,48)
                if call then hint("ApprovalHint","Kunde muss die Reparatur freigeben – ruf ihn mit dem Handy an (P)") end
            end
        elseif api.page=="verify" then
            local checks,phaseName=verifyChecks()
            if phaseName=="invoice" then
                line("VerifyHead","Endkontrolle bestanden ✓",G.green,16,24)
                line("VerifyDone","Endkontrolle bestanden. Rechnung am Empfang abschließen.",G.green,14,44)
            else
                local anim=api.verifyAnim;local shown=anim and math.floor((now()-anim.start)/0.25) or #checks
                line("VerifyHead",anim and "Prüfe …" or "Prüfliste vor der Endkontrolle",G.green,16,24)
                for i,c in ipairs(checks) do
                    local mark=(anim and i>shown) and "[ ]" or (c.ok and "[✓]" or c.auto and "[»]" or "[✗]") -- 3.0: [»] = macht E automatisch
                    line("Check"..i,mark.." "..t(c.text)..((not c.ok and c.fix and c.fix~="" and not (anim and i>shown)) and ("  → "..t(c.fix)) or ""),(anim and i>shown) and G.dim or c.ok and G.green or c.auto and G.amber or G.red,14,portrait and 40 or 22) -- 3.0
                end
                if phaseName~="verify" and not anim then line("VerifyNote","Die Endkontrolle startet, wenn alle Arbeitsschritte erledigt sind.",G.amber,13,40) end
            end
        end
        content.CanvasSize=UDim2.fromOffset(0,cy+4)
        local s=""
        if api.page=="scan" then s="Bleibe am OBD-Anschluss …"
        elseif api.page=="codes" and call then s="Nächster Schritt: Kunden anrufen (P)"
        elseif type(v)=="table" and v.phase=="diagnose" and type(v.answers)=="table" and #v.answers>0 then s="Wähle unter „Befund“ die passende Ursache."
        else local ok,h=pcall(nextHint);s=ok and h and ("Nächster Schritt: "..h) or "" end
        status.Text=t(s)
    end
    local function show() -- 3.0
        overlay.Visible=true;modal.Visible=false;root.Visible=true;api.Layout()
    end
    function api.Page(name) -- 3.0
        if name=="close" then return api.Close() end
        api.page=name;api.verifyAnim=nil;render()
    end
    function api.Cancel() -- 3.0: laufenden Scan abbrechen (gleiche Aktion wie der QTE-Abbruch)
        local token=state and state.interaction and state.interaction.kind=="scan" and state.interaction.token
        if token then send("abortInteraction",{token=token}) end
        dismiss()
    end
    function api.Close() -- 3.0: Schließen = bisheriges dismiss; während des Scans zusätzlich abbrechen
        if api.page=="scan" then return api.Cancel() end
        dismiss()
    end
    function api.Verify(retry) -- 3.0: Prüfliste animieren, dann den bisherigen scan senden (retry: höchstens ein Nachstart)
        api.page="verify";api.verifyAnim=nil
        local checks,phaseName=verifyChecks();local j=currentJob()
        local ready=j and phaseName=="verify"
        for _,c in ipairs(checks) do if not c.ok and not c.auto then ready=false end end -- 3.0: Bühne/Haube/Tester regelt der Server
        if not ready then return render() end
        api.scanSerial=api.scanSerial+1;local serial=api.scanSerial;local jobId=j.id
        api.verifyAnim={start=now()};render()
        task.delay(#checks*0.25+0.3,function()
            if api.scanSerial~=serial or not root.Visible or api.page~="verify" then return end
            api.verifyAnim=nil;send("scan",{id=jobId})
            local vis=state and state.visuals and state.visuals[jobId]
            if vis and vis.lifted and not retry then -- 3.0: Server senkt erst die Bühne ab; danach die Endkontrolle selbst noch einmal starten
                local again=api.scanSerial
                task.delay(2.8,function() if api.scanSerial==again and root.Visible and api.page=="verify" and not api.verifyAnim then api.Verify(true) end end)
            end
        end)
    end
    for _,key in ipairs(keyOrder) do -- 3.0
        keys[key]=tkey(root,"TesterBtn_"..key,keyNames[key],function()
            if key=="close" then api.Close() elseif api.page=="scan" then return elseif key=="verify" then api.Verify() else api.Page(key) end -- 3.0: während des Scans nur Schließen
        end)
    end
    function api.ShowScan(jobId,duration) -- 3.0: Verbinden/Auslesen, solange der Server scannt
        api.jobId=jobId or api.jobId;api.scanStart=now();api.scanDuration=tonumber(duration) or 2.5;api.verifyAnim=nil
        local j=currentJob();api.scanVerify=j~=nil and j.phase=="verify"
        api.scanSerial=api.scanSerial+1;local serial=api.scanSerial
        api.page="scan";show();render()
        task.delay(api.scanDuration+4.5,function() -- 3.0: nie im Verbindungsbild hängen bleiben
            if api.scanSerial==serial and api.page=="scan" and root.Visible then dismiss();toast("Keine Antwort vom Fahrzeug. Bleibe am OBD-Anschluss und versuche es noch einmal.") end
        end)
    end
    function api.ShowReport(v) -- 3.0: Ergebnis des Scans
        api.data=v;api.jobId=v.job or api.jobId;api.scanStart=nil;api.verifyAnim=nil;api.scanSerial=api.scanSerial+1
        if type(v.answers)=="table" and #v.answers>0 and v.phase=="diagnose" then api.page="finding"
        elseif v.phase=="invoice" then api.page="verify"
        else api.page="codes" end
        show();render()
    end
    function api.Hide() -- 3.0
        root.Visible=false;modal.Visible=true;api.page=nil;api.verifyAnim=nil;api.scanSerial=api.scanSerial+1
    end
    function api.Visible() return root.Visible end -- 3.0
    function api.OnState() -- 3.0: Prüfliste und Statuszeile mit dem Zustand nachführen
        if root.Visible and api.page and api.page~="scan" and not api.verifyAnim then render() end
    end
    function api.Layout() -- 3.0: Hochformat (Handy) eigene Anordnung; Maßstab wie modalScale aus der nutzbaren Fläche
        local size=gui.AbsoluteSize
        if not size or size.X<=0 or size.Y<=0 then local cam=workspace.CurrentCamera;local vp=cam and cam.ViewportSize or Vector2.new(1280,800);size=Vector2.new(vp.X,vp.Y-36) end
        local wasPortrait=portrait
        portrait=size.X<600;W,H=portrait and 360 or 640,portrait and 600 or 440
        local wasScale=scaleObj.Scale -- 3.0: Tastenhöhen hängen vom Maßstab ab
        root.Size=UDim2.fromOffset(W,H);scaleObj.Scale=math.max(0.3,math.min(1,(size.X-24)/W,(size.Y-12)/H))
        pads[1].Position=UDim2.fromOffset(-8,-8);pads[2].Position=UDim2.fromOffset(W-22,-8);pads[3].Position=UDim2.fromOffset(-8,H-22);pads[4].Position=UDim2.fromOffset(W-22,H-22)
        leds.Position=UDim2.fromOffset(W-24-(portrait and 150 or 200),14);leds.Size=UDim2.fromOffset(portrait and 150 or 200,24)
        for i,name in ipairs({"power","link","fault"}) do local step=portrait and 50 or 68;led[name].Position=UDim2.fromOffset((i-1)*step,6);leds:FindFirstChild("LedLabel_"..name).Position=UDim2.fromOffset((i-1)*step+15,0) end
        model.Visible=not portrait
        local keysTop
        if portrait then
            keysTop=H-14-3*52-2*8;local cw=(W-36-8)/2
            for i,key in ipairs(keyOrder) do
                local b=keys[key];local row,col=math.floor((i-1)/2),(i-1)%2
                if key=="close" then b.Position=UDim2.fromOffset(18,keysTop+2*60);b.Size=UDim2.fromOffset(W-36,52)
                else b.Position=UDim2.fromOffset(18+col*(cw+8),keysTop+row*60);b.Size=UDim2.fromOffset(cw,52) end
                b.TextSize=15
            end
        else
            keysTop=H-14-62;local bw=(W-36-4*8)/5
            for i,key in ipairs(keyOrder) do local b=keys[key];b.Position=UDim2.fromOffset(18+(i-1)*(bw+8),keysTop);b.Size=UDim2.fromOffset(bw,62);b.TextSize=13 end
        end
        screen.Position=UDim2.fromOffset(18,48);screen.Size=UDim2.fromOffset(W-36,keysTop-8-48)
        if root.Visible and (wasPortrait~=portrait or wasScale~=scaleObj.Scale) and api.page and api.page~="scan" then render() end -- 3.0
    end
    local nextTick=0 -- 3.0
    Run.RenderStepped:Connect(function() -- 3.0: Fortschritt, Prüfliste, Live-Werte, blinkende LED (10 Hz)
        if not root.Visible or os.clock()<nextTick then return end
        nextTick=os.clock()+0.1
        local at=now()
        if api.page=="scan" and api.scanStart and api.scanFill and api.scanFill.Parent then
            local f=math.clamp((at-api.scanStart)/math.max(0.1,api.scanDuration),0,1)
            api.scanFill.Size=UDim2.fromScale(f,1);api.scanPercent.Text=string.format("%3d %%",math.floor(f*99))
            for i,s in ipairs(api.scanSteps or {}) do local reached=f>=(i-1)/#api.scanSteps;s.label.Text=(f>=i/#api.scanSteps and "[✓] " or reached and "[»] " or "[ ] ")..t(s.text);s.label.TextColor3=reached and G.green or G.dim end
            setLed("link",math.floor(at*6)%2==0 and G.amber or G.dark)
        elseif api.page=="verify" and api.verifyAnim then render()
        elseif api.page=="values" then for i,x in ipairs(liveValues(at)) do local l=liveLabels[i];if l and l.Parent then l.Text=pad(x[1],16)..x[2] end end end
    end)
    return api -- 3.0
end)() -- 3.0
Event.OnClientEvent:Connect(function(kind,value)
    if kind=="state" then
        local oldRevision=state and state.revision;local first=not state;local oldLevel=state and state.data.level;state=value
        if challenge and (not state.interaction or state.interaction.token~=challenge.token) then dismiss() end
        if oldLevel and state.data.level>oldLevel then effects.Level(state.data.level,state.data.level-oldLevel) end
        markTarget()
        refresh()
        if first or oldRevision~=state.revision then rebuild() end
        if tester then tester.OnState() end -- 3.0: Prüfliste/Status im offenen OBD-Tester nachführen
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
    elseif kind=="diagnosisDone" then if diagnosis and diagnosis.job==value then local call=tester and tester.NeedsCall();dismiss();if call then toast("Kunde muss die Reparatur freigeben – ruf ihn mit dem Handy an (P).") end end -- 3.0: Hinweis aufs Handy
    elseif kind=="scan" then effects.Work(value);if value.tool=="scanner" then toast(t("Messwerte werden ausgelesen … Bleibe am Auto.")) end
        -- 3.0: OBD-Scan am DiagnosticPoint: Tester zeigt „Verbinden/Auslesen“ (2,5 s), bis das diagnose-Ereignis kommt
        local point=type(value)=="table" and value.point
        if value.tool=="scanner" and typeof(point)=="Instance" and point.Name=="DiagnosticPoint" and not challenge then -- 3.0
            local jobId=point.Parent and point.Parent:GetAttribute("JobId") or (state and state.selected) -- 3.0
            visible=false;tablet.Visible=false;diagnosis={job=jobId,scanning=true} -- 3.0: sperrt Minispiele wie der Dialog
            local ok,err=pcall(tester.ShowScan,jobId,value.duration) -- 3.0
            if not ok then warn("[3.0] OBD-Tester: "..tostring(err));dismiss() end -- 3.0
        end
    elseif kind=="diagnose" then -- 3.0: Handgerät „UCG-Tester 3000“ statt einfachem Dialog (gleiche Aktionen diagnose/scan, Schließen = dismiss)
        if type(value)~="table" then return end -- 3.0
        effects.StopWork();diagnosis=value;visible=false;tablet.Visible=false -- 3.0
        local ok,err=pcall(tester.ShowReport,value) -- 3.0
        if not ok then warn("[3.0] OBD-Tester: "..tostring(err));dismiss();toast(value.report or "Diagnose fertig.") end -- 3.0: nie ein halber Dialog
    elseif kind=="call" then -- 3.0: Kundenanruf (Freigabe) an das Handy der Minispiele weiterreichen
        for _,fn in ipairs(eventListeners) do local ok,err=pcall(fn,kind,value);if not ok then warn("[3.0] call-Abonnent: "..tostring(err)) end end -- 3.0
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
    SelectTool=function(slot) -- 3.0: Taste 1 = freie Hand, Tasten 2–6 = Werkzeugplätze 1–5
        if state and not overlay.Visible then
            if slot==1 then send("tool",{id="hand"}) elseif state.data.loadout[slot-1] then send("tool",{id=state.data.loadout[slot-1]}) end -- 3.0
        end
    end,
    ToggleMini=function() MiniClient.Toggle() end, -- 3.0: Taste M
})
-- 3.0: Minispiele starten (eigene ScreenGui "Minispiele", eigener Listener für mini*-Kinds). Gegenseitiger Ausschluss:
-- öffnet nicht während QTE/Diagnose, schließt beim Öffnen das Tablet, weicht dem Tablet; HUD blendet sich aus.
task.spawn(function()
    local ok,err=pcall(MiniClient.Start,{
        isBlocked=function() return overlay.Visible or (inputControl~=nil and inputControl.locked) or challenge~=nil or diagnosis~=nil end, -- 3.0: auch während QTE/Diagnose (Phase-4-Karten weichen)
        isTabletOpen=function() return visible end,
        closeTablet=function() visible=false;tablet.Visible=false;if protectCoreUI then protectCoreUI() end end,
        openTablet=function(key) showPage(key) end,
        hideHud=function() refresh();refreshVehicleActions();if protectCoreUI then protectCoreUI() end end, -- 3.0: Spielerliste sofort mitschalten
        toast=toast,
        getState=function() return state end, -- 3.0: 2.4.0-Zustand (state.data.jobs inkl. phase "approval") fürs Handy
        onEvent=function(fn) if type(fn)=="function" then table.insert(eventListeners,fn) end end, -- 3.0: fn(kind, value) für Server-Ereignis "call"
        subscribe=function(fn) for _,o in ipairs({overlay,tablet,vehicleActions}) do o:GetPropertyChangedSignal("Visible"):Connect(fn) end end, -- 3.0: Dialog/Tablet/E-F-H auf oder zu -> Phase-4-Karten sofort neu
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
    local usable=screen.X*0.96-24;local tw=math.min(92,(usable-30)/6) -- 3.0: sechs Plätze (Hand + fünf Werkzeuge)
    -- 3.0: Touch/Handy (schmal oder quer): Werkzeugleiste ≥ 44 px hoch. Die HUD bleibt 132 px (PrestigeUI.GarageHud);
    -- 3.0: Zielzeile und Knopfzeile rücken dafür etwas nach oben.
    local big=screen.X*0.96<600 or screen.Y<500 or UIS.TouchEnabled
    local rowH,rowY,btnY=big and 44 or 30,big and 86 or 90,big and 43 or 47 -- 3.0
    objective.Position=UDim2.fromOffset(12,big and 3 or 5);objective.Size=UDim2.new(1,-24,0,big and 36 or 39) -- 3.0
    for _,b in ipairs({go,workButton,menu,miniButton}) do b.Position=UDim2.fromOffset(b.Position.X.Offset,btnY) end -- 3.0
    handButton.Position=UDim2.fromOffset(12,rowY);handButton.Size=UDim2.fromOffset(tw,rowH) -- 3.0: Hand zuerst
    do local key,label,icon=handButton:FindFirstChild("Key"),handButton:FindFirstChild("HandLabel"),handButton:FindFirstChild("HandIcon") -- 3.0: schmal: Ziffer weg, „Hand“ bleibt lesbar
        local narrow=tw<70
        if key then key.Visible=not narrow end
        if icon then icon.Position=UDim2.new(0,narrow and 3 or 18,0.5,0) end
        if label then label.Position=UDim2.fromOffset(narrow and 26 or 42,0);label.Size=UDim2.new(1,narrow and -27 or -44,1,0);label.TextSize=narrow and 11 or 13 end
    end
    for i,b in ipairs(toolButtons) do b.Position=UDim2.fromOffset(12+i*(tw+6),rowY);b.Size=UDim2.fromOffset(tw,rowH);b.TextSize=screen.X<500 and 11 or 14 end -- 3.0: ab dem zweiten Platz
    local first=math.min(110,usable*0.26);go.Size=UDim2.fromOffset(first,38)
    workButton.Position=UDim2.fromOffset(18+first,btnY);workButton.Size=UDim2.fromOffset(usable*0.35,38)
    menu.Position=UDim2.fromOffset(24+first+usable*0.35,btnY);menu.Size=UDim2.fromOffset(math.min(120,usable*0.3-12),38)
    -- 3.0: Minispiele-Knopf rechts neben "Menü"; ist die Zeile zu schmal (Handy hoch), teilen sich vier gleich breite Knöpfe die Zeile.
    local menuEnd=24+first+usable*0.35+math.min(120,usable*0.3-12);local room=usable+12-menuEnd-6
    if room>=110 then miniButton.Position=UDim2.fromOffset(menuEnd+6,btnY);miniButton.Size=UDim2.fromOffset(math.min(150,room),38);miniButton.TextSize=15
    else
        local w=(usable-18)/4
        go.Size=UDim2.fromOffset(w,38);workButton.Position=UDim2.fromOffset(18+w,btnY);workButton.Size=UDim2.fromOffset(w,38)
        menu.Position=UDim2.fromOffset(24+2*w,btnY);menu.Size=UDim2.fromOffset(w,38);miniButton.Position=UDim2.fromOffset(30+3*w,btnY);miniButton.Size=UDim2.fromOffset(w,38);miniButton.TextSize=13
    end
    if tester then tester.Layout() end -- 3.0: OBD-Tester skaliert mit
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
    local stepHere=point and current and current.phase=="repair" and step and step.point==point -- 3.0: Punkt des aktuellen Schritts
    if stepHere then send("work",{id=id,point=point}) -- 3.0: egal welches Werkzeug in der Hand ist – das passende nimmt der Server
    elseif point=="HoodPoint" then send("hood",{id=id})
    elseif point=="DiagnosticPoint" then send("scan",{id=id,point=point}) -- 3.0: OBD-Anschluss = Fehlerspeicher/Endkontrolle
    elseif state.tool=="scanner" then send("scan",{id=id}) -- 3.0: Scanner auf anderem Teil: Bericht wie bisher
    elseif point then send("work",{id=id,point=point}) end -- 3.0: Server erklärt, was gerade dran ist
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
