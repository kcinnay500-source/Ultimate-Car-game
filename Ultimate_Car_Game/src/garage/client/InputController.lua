-- Own the input before Roblox's movement bindings; keep jump suppressed until key-up.
local CAS=game:GetService("ContextActionService")
local UIS=game:GetService("UserInputService")
local Run=game:GetService("RunService")
local I={}
function I.new(player,callbacks)
    local control={locked=false,releaseAt=nil,sent=false,held=false}
    local humanoid,wasEnabled,wasAuto
    local function restore()
        if humanoid and humanoid.Parent then
            humanoid.Jump=false;humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,wasEnabled)
            if wasAuto~=nil then humanoid.AutoJumpEnabled=wasAuto end
        end
        humanoid=nil;control.locked=false;control.releaseAt=nil;control.held=false
    end
    function control.Lock()
        if not control.locked then
            local ch=player.Character;humanoid=ch and ch:FindFirstChildOfClass("Humanoid")
            if humanoid then wasEnabled=humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping);wasAuto=humanoid.AutoJumpEnabled;humanoid:SetStateEnabled(Enum.HumanoidStateType.Jumping,false);humanoid.AutoJumpEnabled=false;humanoid.Jump=false end
        end
        control.locked=true;control.sent=false;control.releaseAt=nil
    end
    function control.Unlock()
        -- Do not pass the very Space press that closes the QTE to the jump controller.
        if control.locked then control.releaseAt=os.clock()+0.15 end
    end
    CAS:BindActionAtPriority("UCG_QTEStop",function(_,state)
        if not control.locked then return Enum.ContextActionResult.Pass end
        if humanoid then humanoid.Jump=false end
        if state==Enum.UserInputState.Begin then
            control.held=true
            if not control.sent then control.sent=true;callbacks.StopQTE() end
        elseif state==Enum.UserInputState.End or state==Enum.UserInputState.Cancel then control.held=false end
        return Enum.ContextActionResult.Sink
    end,false,10000,Enum.KeyCode.Space,Enum.KeyCode.ButtonA,Enum.PlayerActions.CharacterJump)
    CAS:BindActionAtPriority("UCG_WorkshopMenu",function(_,state)
        if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if state==Enum.UserInputState.Begin and not control.locked then callbacks.ToggleMenu() end
        return Enum.ContextActionResult.Sink
    end,false,10000,Enum.KeyCode.Tab)
    local keys={Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five}
    CAS:BindActionAtPriority("UCG_Hotbar",function(_,state,input)
        if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
        if state==Enum.UserInputState.Begin and not control.locked and callbacks.SelectTool then
            for slot,key in ipairs(keys) do if input.KeyCode==key then callbacks.SelectTool(slot);break end end
        end
        return Enum.ContextActionResult.Sink
    end,false,3000,Enum.KeyCode.One,Enum.KeyCode.Two,Enum.KeyCode.Three,Enum.KeyCode.Four,Enum.KeyCode.Five)
    -- 3.0: Taste M schaltet die Minispiele um (optional; Tab, 1–5, Leertaste und E/F/H bleiben unverändert)
    if callbacks.ToggleMini then
        CAS:BindActionAtPriority("UCG_Minigames",function(_,state)
            if UIS:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
            if state==Enum.UserInputState.Begin and not control.locked then callbacks.ToggleMini() end
            return Enum.ContextActionResult.Sink
        end,false,5000,Enum.KeyCode.M)
    end
    UIS.InputEnded:Connect(function(input)
        if input.KeyCode==Enum.KeyCode.Space or input.KeyCode==Enum.KeyCode.ButtonA then control.held=false end
    end)
    Run.RenderStepped:Connect(function()
        if not control.locked then return end
        if humanoid then humanoid.Jump=false end
        local holdingSpace=UIS:IsKeyDown(Enum.KeyCode.Space)
        if control.releaseAt and os.clock()>=control.releaseAt and not control.held and not holdingSpace then restore() end
    end)
    player.CharacterAdded:Connect(function() restore() end)
    return control
end
return I
