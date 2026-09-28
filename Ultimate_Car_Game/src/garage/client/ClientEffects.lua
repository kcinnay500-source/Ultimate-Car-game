local Tween=game:GetService("TweenService")
local Run=game:GetService("RunService")
local E={}
function E.new(player,translate)
    local t=translate;local fx={};local work;local arm,armBase,grip,gripBase
    local layer=Instance.new("ScreenGui");layer.Name="GarageCelebrations";layer.ResetOnSpawn=false;layer.IgnoreGuiInset=false;layer.DisplayOrder=45;layer.Parent=player:WaitForChild("PlayerGui")
    local green=Color3.fromRGB(55,218,155);local gold=Color3.fromRGB(250,198,71)
    local function tween(obj,seconds,props,style)
        local tw=Tween:Create(obj,TweenInfo.new(seconds,style or Enum.EasingStyle.Quad,Enum.EasingDirection.Out),props);tw:Play();return tw
    end
    local function make(class,parent,props) local v=Instance.new(class);for k,x in pairs(props) do v[k]=x end;v.Parent=parent;return v end
    local function label(parent,value,pos,size,color,textSize)
        return make("TextLabel",parent,{Text=t(value),Position=pos,Size=size,TextColor3=color,TextSize=textSize,TextWrapped=true,Font=Enum.Font.GothamBold,BackgroundTransparency=1})
    end
    function fx.Purchase(data)
        local panel=make("Frame",layer,{Name="PurchaseFeedback",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.79),Size=UDim2.fromOffset(300,84),BackgroundColor3=Color3.fromRGB(16,39,35),BorderSizePixel=0})
        make("UICorner",panel,{CornerRadius=UDim.new(0,15)})
        make("UIStroke",panel,{Color=green,Thickness=1.5,Transparency=0.25})
        local scale=make("UIScale",panel,{Scale=0.75});tween(scale,0.3,{Scale=1},Enum.EasingStyle.Back)
        label(panel,"✓",UDim2.fromOffset(8,12),UDim2.fromOffset(46,52),green,36)
        label(panel,data.title or "Gekauft",UDim2.fromOffset(58,8),UDim2.fromOffset(228,37),Color3.fromRGB(235,250,246),16)
        label(panel,data.detail or "",UDim2.fromOffset(58,46),UDim2.fromOffset(228,28),green,14)
        task.delay(1.8,function() if panel.Parent then tween(panel,0.22,{Position=UDim2.fromScale(0.5,0.83),BackgroundTransparency=1});tween(scale,0.22,{Scale=0.85});task.delay(0.23,function() panel:Destroy() end) end end)
    end
    function fx.Level(level,gained)
        local panel=make("Frame",layer,{Name="LevelCelebration",AnchorPoint=Vector2.new(0.5,0.5),Position=UDim2.fromScale(0.5,0.26),Size=UDim2.fromOffset(340,124),BackgroundColor3=Color3.fromRGB(38,33,24),BorderSizePixel=0})
        make("UICorner",panel,{CornerRadius=UDim.new(0,18)});make("UIStroke",panel,{Color=gold,Thickness=2})
        local scale=make("UIScale",panel,{Scale=0.45});tween(scale,0.5,{Scale=1},Enum.EasingStyle.Back)
        label(panel,"LEVELAUFSTIEG",UDim2.fromOffset(12,9),UDim2.fromOffset(316,26),gold,16)
        label(panel,t("LEVEL {level}",{level=level}),UDim2.fromOffset(12,37),UDim2.fromOffset(316,48),Color3.fromRGB(255,245,218),34)
        label(panel,"Neue Möglichkeiten in deiner Werkstatt",UDim2.fromOffset(12,89),UDim2.fromOffset(316,24),gold,12)
        for i=1,22 do
            local bit=make("Frame",layer,{Name="Confetti",Size=UDim2.fromOffset(i%3+5,10),Position=UDim2.fromScale(0.5,0.26),BackgroundColor3=i%2==0 and gold or green,BorderSizePixel=0,Rotation=i*19})
            tween(bit,1.3+(i%4)*0.15,{Position=UDim2.fromScale(0.15+(i*37%70)/100,0.5+(i%4)*0.07),Rotation=i*53,BackgroundTransparency=1})
            task.delay(2,function() bit:Destroy() end)
        end
        task.delay(3,function() if panel.Parent then tween(scale,0.25,{Scale=0});task.delay(0.26,function() panel:Destroy() end) end end)
    end
    local function restore()
        if arm and arm.Parent and armBase then arm.C0=armBase end
        if grip and grip.Parent and gripBase then grip.C0=gripBase end
        arm,armBase,grip,gripBase=nil,nil,nil,nil
    end
    function fx.StopWork()
        restore();work=nil
        local ch=player.Character;local tool=ch and ch:FindFirstChild("GarageTool");local readout=tool and tool:FindFirstChild("Readout",true)
        if readout then readout.Text=tool:GetAttribute("ToolId")=="scanner" and "OBD READY" or "BEREIT" end
    end
    function fx.Work(data)
        fx.StopWork();work={tool=data.tool,untilTime=workspace:GetServerTimeNow()+(data.duration or 2.5),start=workspace:GetServerTimeNow(),point=data.point}
    end
    Run.RenderStepped:Connect(function()
        if not work then return end
        local ch=player.Character;local tool=ch and ch:FindFirstChild("GarageTool");local root=ch and ch:FindFirstChild("HumanoidRootPart")
        if workspace:GetServerTimeNow()>=work.untilTime or not tool or tool:GetAttribute("ToolId")~=work.tool or (root and work.point and (root.Position-work.point.Position).Magnitude>18) then fx.StopWork();return end
        local currentGrip=tool:FindFirstChild("ToolGrip",true)
        if currentGrip~=grip then restore();grip=currentGrip;gripBase=grip and grip.C0;arm=ch:FindFirstChild("RightShoulder",true) or ch:FindFirstChild("Right Shoulder",true);armBase=arm and arm.C0 end
        local elapsed=workspace:GetServerTimeNow()-work.start
        local turning=work.tool=="ratchet" or work.tool=="torque" or work.tool=="screwdriver"
        local swing=math.sin(elapsed*(turning and 18 or 6))
        local angle=work.tool=="oil" and -0.9 or turning and swing*0.45 or work.tool=="tire" and swing*0.65 or swing*0.08
        if grip and gripBase then grip.C0=gripBase*CFrame.Angles(0,0,angle) end
        if arm and armBase then arm.C0=armBase*CFrame.Angles(-0.35+swing*0.08,0,work.tool=="oil" and -0.2 or swing*0.12) end
        local readout=tool:FindFirstChild("Readout",true)
        if readout then readout.Text=work.tool=="scanner" and ("OBD SCAN\n"..math.floor(math.min(99,elapsed/(work.untilTime-work.start)*100)).."%") or string.format("%.2f V",12.4+math.sin(elapsed*9)*0.2) end
    end)
    player.CharacterAdded:Connect(function() fx.StopWork() end)
    return fx
end
return E
