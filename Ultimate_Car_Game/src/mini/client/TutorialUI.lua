-- TutorialUI: Tutorial-Karte, Welt-Marker, Beginner-Hinweiskarte und Freischaltungs-Karte auf dem Client
-- (docs/PHASE4_CONTRACT.md §6). Kein Tab: MiniClient ruft TutorialUI.Start(ctx) (oder Build(nil, ctx)),
-- OnSnapshot(s), OnNotice(data) und Step(dt) aus dem Heartbeat. Der Client zeigt nur an und sendet Absichten
-- (tutorial_next {step} für „Weiter“-Schritte, tutorial_skip); den Fortschritt bestätigt der Server.
--
-- Eigene ScreenGui "Tutorial" (DisplayOrder 21: über dem 2.4.0-HUD (20), unter dem Minispiel-Panel (30)):
--   Card       unten Mitte über der 2.4.0-Leiste (Leiste 132 px hoch, 6 px Rand): Schritt-Text, „Schritt n von m“,
--              Fortschrittsbalken, „Weiter“ (nur next-Schritte), „Überspringen“ (immer). Touch-Flächen 44 px.
--   Marker     BillboardGui am Zielteil (zone plot: PlayerWorkshops.Plot_<UserId>.Stations.<key>,
--              zone city: workspace.City.Stations.<key>), AlwaysOnTop, leicht wippend.
--   HintCard   Beginner-Hinweis oben rechts, unter dem ProgressHUD-Abzeichen (y 8 + 56 + 8 = 72; liegt dort gerade die
--              Karte „Neu freigeschaltet“ (UnlocksUI), rückt der Hinweis darunter).
--   UnlockCard „Freigeschaltet: <Titel>“ bei mini_notice { kind = "unlock" } mit kurzem Effekt – nur, wenn nicht schon
--              UnlocksUI (ScreenGui "UnlockCards") die Karte zeigt (sonst gäbe es sie doppelt).
-- Sichtbarkeit wie beim ProgressHUD: weg, solange Minispiel-Panel, 2.4.0-Tablet, QTE/Diagnose oder Tacho zu sehen sind.
-- Komfort: der Schritt „menu“ gilt als gelesen, sobald das Minispiel-Panel offen war; der Schritt „move“, sobald die
-- Figur ein Stück gelaufen ist (beides sendet tutorial_next – der Server prüft den Schritt).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(Mini:WaitForChild("GameConfig"))
local TutorialRules = require(Mini:WaitForChild("TutorialRules"))

local TutorialUI = {}

TutorialUI.DisplayOrder = 21
TutorialUI.CardWidth = 440
TutorialUI.CardBottom = 150 -- Abstand zur Unterkante (2.4.0-Leiste: 132 px + 6 px Rand + Luft)
TutorialUI.HintWidth = 300
TutorialUI.HintTop = 8 + 56 + 8 -- unter dem ProgressHUD-Abzeichen (y 8, 56 hoch)
TutorialUI.HintSeconds = 8
TutorialUI.UnlockSeconds = 6
TutorialUI.FinishSeconds = 5
TutorialUI.MoveSeconds = 0.6 -- so lange muss die Figur laufen, bis „move“ als erledigt gilt

local TARGET_TITLES = {
	workshop = "EMPFANG",
	map = "STADTPLAN",
	dealer = "AUTOHAUS",
	goals = "INFOTAFEL",
}

local UI, Remote, T, ctx
local gui, card, marker, hint, unlock = nil, {}, {}, {}, {}
local view = nil -- letzter Stand (Snapshot-Feld tutorial oder tutorial-Hinweis)
local stepTimer = 0
local hintSerial, unlockSerial, finishSerial = 0, 0, 0
local sentNextFor = nil -- Schrittnummer, für die der Client schon tutorial_next geschickt hat
local movedFor = 0
local finishedUntil = 0

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v or default
end

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return player and player:FindFirstChild("PlayerGui")
end

---------------------------------------------------------------- Absichten
function TutorialUI.Next()
	if not view or not view.active or not view.next or not Remote then
		return false
	end
	Remote.Send("tutorial_next", { step = view.step })
	return true
end

function TutorialUI.Skip()
	if not view or not view.active or not Remote then
		return false
	end
	Remote.Send("tutorial_skip", {})
	return true
end

---------------------------------------------------------------- Aufbau
local function buildCard()
	local frame = UI.Frame(gui, {
		Name = "Card", BackgroundColor3 = T.panel, AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -TutorialUI.CardBottom),
		Size = UDim2.new(0, TutorialUI.CardWidth, 0, 0), Visible = false, Active = true,
	})
	UI.Corner(frame, 12)
	UI.Padding(frame, 16, 12)
	UI.List(frame, 8)
	card.frame = frame
	card.progress = UI.Label(frame, "", { Name = "Progress", Font = UI.FontBold, TextSize = 14, TextColor3 = T.green, LayoutOrder = 1 })
	card.text = UI.Label(frame, "", { Name = "Text", TextSize = 16, LayoutOrder = 2 })
	local bar, fill = UI.Progress(frame, T.green, 3)
	bar.Name = "Bar"
	card.fill = fill
	local buttons = UI.Frame(frame, { Name = "Buttons", BackgroundTransparency = 1, LayoutOrder = 4, Size = UDim2.new(1, 0, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.None })
	local list = UI.List(buttons, 8, true)
	list.HorizontalAlignment = Enum.HorizontalAlignment.Right
	card.skip = UI.Button(buttons, "Überspringen", T.line, TutorialUI.Skip, { Name = "Skip", Size = UDim2.new(0, 150, 0, UI.MinTouch), LayoutOrder = 1 })
	card.next = UI.Button(buttons, "Weiter", T.green, TutorialUI.Next, { Name = "Next", Size = UDim2.new(0, 130, 0, UI.MinTouch), LayoutOrder = 2 })
	card.scale = Instance.new("UIScale")
	card.scale.Scale = 1
	card.scale.Parent = frame
end

local function buildMarker()
	local bb = Instance.new("BillboardGui")
	bb.Name = "TutorialMarker"
	bb.Size = UDim2.fromOffset(190, 44)
	bb.StudsOffset = Vector3.new(0, 4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 400
	bb.Enabled = false
	bb.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = UI.FontBold
	label.TextSize = 14
	label.TextColor3 = T.yellow
	label.TextStrokeTransparency = 0.4
	label.Text = "▼ TUTORIAL"
	label.Parent = bb
	marker.gui = bb
	marker.label = label
	marker.bounce = 0
end

local function buildHintCard()
	local frame = UI.Frame(gui, {
		Name = "HintCard", BackgroundColor3 = T.panel, AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, TutorialUI.HintTop),
		Size = UDim2.new(0, TutorialUI.HintWidth, 0, 0), Visible = false,
	})
	UI.Corner(frame, 10)
	UI.Padding(frame, 14, 10)
	UI.List(frame, 4)
	local stripe = UI.Frame(frame, { BackgroundColor3 = T.blue, Size = UDim2.new(1, 0, 0, 3), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 0 })
	UI.Corner(stripe, 2)
	hint.frame = frame
	hint.title = UI.Label(frame, "Tipp", { Name = "Title", Font = UI.FontBold, TextSize = 15, TextColor3 = T.blue, LayoutOrder = 1 })
	hint.text = UI.Label(frame, "", { Name = "Text", TextSize = 14, LayoutOrder = 2 })
	hint.scale = Instance.new("UIScale")
	hint.scale.Scale = 1
	hint.scale.Parent = frame
end

local function buildUnlockCard()
	local frame = UI.Frame(gui, {
		Name = "UnlockCard", BackgroundColor3 = T.panel, AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, TutorialUI.HintTop),
		Size = UDim2.new(0, TutorialUI.HintWidth, 0, 0), Visible = false,
	})
	UI.Corner(frame, 10)
	UI.Padding(frame, 14, 10)
	UI.List(frame, 4)
	local stripe = UI.Frame(frame, { BackgroundColor3 = T.green, Size = UDim2.new(1, 0, 0, 3), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 0 })
	UI.Corner(stripe, 2)
	unlock.frame = frame
	unlock.title = UI.Label(frame, "", { Name = "Title", Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	unlock.text = UI.Label(frame, "", { Name = "Text", TextSize = 14, TextColor3 = T.muted, LayoutOrder = 2 })
	unlock.scale = Instance.new("UIScale")
	unlock.scale.Scale = 1
	unlock.scale.Parent = frame
end

local function layout()
	if not gui then
		return
	end
	local w = gui.AbsoluteSize.X
	if w <= 0 then
		return
	end
	card.frame.Size = UDim2.new(0, math.min(TutorialUI.CardWidth, w - 24), 0, 0)
	local hw = math.min(TutorialUI.HintWidth, w - 32)
	hint.frame.Size = UDim2.new(0, hw, 0, 0)
	unlock.frame.Size = UDim2.new(0, hw, 0, 0)
	-- Handy hochkant: die Knöpfe teilen sich die Breite
	local narrow = w < 480
	card.skip.Size = UDim2.new(narrow and 0.5 or 0, narrow and -4 or 150, 0, UI.MinTouch)
	card.next.Size = UDim2.new(narrow and 0.5 or 0, narrow and -4 or 130, 0, UI.MinTouch)
end

function TutorialUI.Build(_page: any, context: any)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	if gui then
		return -- schon gebaut: nur der Kontext (UI, Remote, Sperren) wurde neu gebunden
	end
	local pg = playerGui()
	if not pg then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "Tutorial"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = TutorialUI.DisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg
	buildCard()
	buildMarker()
	buildHintCard()
	buildUnlockCard()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
end

function TutorialUI.Start(context: any)
	TutorialUI.Build(nil, context)
end

---------------------------------------------------------------- Sichtbarkeit (wie PrestigeUI-Abzeichen)
local function driveHudVisible(): boolean
	local pg = playerGui()
	local drive = pg and pg:FindFirstChild("Fahren")
	return drive ~= nil and drive:IsA("LayerCollector") and drive.Enabled == true
end

local function overlaysAllowed(): boolean
	if UI and UI.IsOpen then
		return false
	end
	if ctx and ctx.IsTabletOpen and ctx.IsTabletOpen() == true then
		return false
	end
	if ctx and ctx.IsBlocked and ctx.IsBlocked() == true then
		return false
	end
	return not driveHudVisible()
end

---------------------------------------------------------------- Zielteil des Schritts
local function findTarget(): BasePart?
	if not view or not view.active or type(view.target) ~= "string" then
		return nil
	end
	local player = Players.LocalPlayer
	local folder = nil
	if view.zone == "plot" then
		local plots = workspace:FindFirstChild("PlayerWorkshops")
		local plot = plots and player and plots:FindFirstChild("Plot_" .. tostring(player.UserId))
		folder = plot and plot:FindFirstChild("Stations")
	elseif view.zone == "city" then
		local city = workspace:FindFirstChild("City")
		folder = city and city:FindFirstChild("Stations")
	end
	local part = folder and folder:FindFirstChild(view.target)
	if part and part:IsA("Model") then
		part = part.PrimaryPart or part:FindFirstChildWhichIsA("BasePart")
	end
	return part and part:IsA("BasePart") and part or nil
end

local function updateMarker()
	if not marker.gui then
		return
	end
	local part = findTarget()
	if part and overlaysAllowed() and not TutorialUI.Finished() then
		marker.gui.Adornee = part
		local title = TARGET_TITLES[view.target] or string.upper(tostring(view.target))
		marker.label.Text = "▼ " .. title
		marker.gui.Enabled = true
	else
		marker.gui.Adornee = nil
		marker.gui.Enabled = false
	end
end

---------------------------------------------------------------- Karte
function TutorialUI.Finished(): boolean
	return os.clock() < finishedUntil
end

local function renderCard()
	if not card.frame then
		return
	end
	local show = view ~= nil and (view.active == true or TutorialUI.Finished()) and overlaysAllowed()
	card.frame.Visible = show
	if not show then
		return
	end
	local count = math.max(1, math.floor(num(view.count, TutorialRules.Count())))
	local step = math.clamp(math.floor(num(view.step, 1)), 1, count)
	if TutorialUI.Finished() and not view.active then
		card.progress.Text = "Tutorial geschafft!"
		card.text.Text = "Belohnung: " .. tostring(GameConfig.Tutorial.Reward.credits) .. " Credits und " .. tostring(GameConfig.Tutorial.Reward.xp) .. " XP. Viel Spaß!"
		UI.SetProgress(card.fill, 1)
		card.next.Visible = false
		card.skip.Visible = false
		return
	end
	card.progress.Text = TutorialRules.ProgressText(step, count)
	card.text.Text = tostring(view.text or "")
	UI.SetProgress(card.fill, (step - 1) / count)
	card.next.Visible = view.next == true
	card.skip.Visible = true
end

local function pop(scale: UIScale)
	scale.Scale = 0.85
	TweenService:Create(scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

-- Neuer Stand aus Snapshot (s.tutorial) oder tutorial-Hinweis
local function apply(v: any, animate: boolean?)
	if type(v) ~= "table" then
		return
	end
	local before = view and view.step or nil
	local wasActive = view and view.active
	view = {
		step = math.floor(num(v.step, 1)),
		count = math.floor(num(v.count, TutorialRules.Count())),
		id = v.id,
		text = v.text,
		target = v.target,
		zone = v.zone,
		next = v.next == true,
		done = v.done == true,
		skipped = v.skipped == true,
		active = v.active == true and v.done ~= true,
	}
	if view.step ~= before then
		sentNextFor = nil
		movedFor = 0
	end
	if v.finished == true and not view.skipped then
		finishSerial += 1
		finishedUntil = os.clock() + TutorialUI.FinishSeconds
		local serial = finishSerial
		task.delay(TutorialUI.FinishSeconds + 0.05, function()
			if serial == finishSerial then
				renderCard()
				updateMarker()
			end
		end)
	end
	renderCard()
	updateMarker()
	if animate and card.frame and card.frame.Visible and (view.step ~= before or wasActive ~= view.active) then
		pop(card.scale)
	end
end

function TutorialUI.OnSnapshot(s: any)
	if type(s) == "table" and type(s.tutorial) == "table" then
		apply(s.tutorial, false)
	end
end
TutorialUI.Render = TutorialUI.OnSnapshot

---------------------------------------------------------------- Hinweis- und Freischaltungs-Karten
local function placeHintCard()
	-- unter der Karte „Neu freigeschaltet“ (UnlocksUI oder eigene), falls die gerade zu sehen ist
	local top = TutorialUI.HintTop
	local pg = playerGui()
	local other = pg and pg:FindFirstChild("UnlockCards")
	local otherCard = other and other:FindFirstChild("UnlockCard")
	local candidates = { otherCard, unlock.frame }
	for _, c in ipairs(candidates) do
		if c and c.Visible and c.AbsoluteSize.Y > 0 then
			top = math.max(top, c.AbsolutePosition.Y - (gui and gui.AbsolutePosition.Y or 0) + c.AbsoluteSize.Y + 8)
		elseif c and c.Visible then
			top = math.max(top, TutorialUI.HintTop + 80)
		end
	end
	hint.frame.Position = UDim2.new(1, -16, 0, top)
end

function TutorialUI.ShowHint(text: string, id: string?)
	if not hint.frame or type(text) ~= "string" or text == "" then
		return
	end
	hintSerial += 1
	local serial = hintSerial
	hint.text.Text = text
	hint.frame:SetAttribute("hintId", id or "")
	placeHintCard()
	hint.frame.Visible = true
	pop(hint.scale)
	task.delay(TutorialUI.HintSeconds, function()
		if serial == hintSerial and hint.frame then
			hint.frame.Visible = false
		end
	end)
end

-- Zeigt UnlocksUI die Karte schon (ScreenGui "UnlockCards")? Dann keine zweite.
local function unlockCardHandledElsewhere(): boolean
	local pg = playerGui()
	local other = pg and pg:FindFirstChild("UnlockCards")
	return other ~= nil and other:FindFirstChild("UnlockCard") ~= nil
end

function TutorialUI.ShowUnlock(title: string, text: string?)
	if not unlock.frame or type(title) ~= "string" or title == "" then
		return
	end
	unlockSerial += 1
	local serial = unlockSerial
	unlock.title.Text = "Freigeschaltet: " .. title
	unlock.text.Text = text or ""
	unlock.text.Visible = text ~= nil and text ~= ""
	unlock.frame.Visible = true
	pop(unlock.scale)
	task.delay(TutorialUI.UnlockSeconds, function()
		if serial == unlockSerial and unlock.frame then
			unlock.frame.Visible = false
		end
	end)
end

function TutorialUI.OnNotice(data: any)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "tutorial" then
		apply(data, true)
		if data.started == true and card.frame and card.frame.Visible then
			pop(card.scale)
		end
	elseif kind == "hint" then
		TutorialUI.ShowHint(data.text, data.id)
	elseif kind == "unlock" then
		if not unlockCardHandledElsewhere() then
			local title = type(data.title) == "string" and data.title or nil
			local level = num(data.level, 0)
			local sub = type(data.hint) == "string" and data.hint or nil
			if level > 0 then
				sub = "Ab Level " .. tostring(math.floor(level)) .. (sub and (" · " .. sub) or "")
			end
			TutorialUI.ShowUnlock(title or tostring(data.key), sub)
		end
		-- sonst zeigt UnlocksUI Karte und Hinweistext (Feld hint) selbst
	end
end

---------------------------------------------------------------- Heartbeat
local function autoNext()
	if not view or not view.active or not view.next or sentNextFor == view.step or not Remote then
		return
	end
	if view.id == "menu" then
		if UI and UI.IsOpen then
			sentNextFor = view.step
			Remote.Send("tutorial_next", { step = view.step })
		end
	elseif view.id == "move" then
		local player = Players.LocalPlayer
		local ch = player and player.Character
		local hum = ch and ch:FindFirstChildOfClass("Humanoid")
		if hum and hum.MoveDirection.Magnitude > 0.1 then
			movedFor += stepTimer
			if movedFor >= TutorialUI.MoveSeconds then
				sentNextFor = view.step
				Remote.Send("tutorial_next", { step = view.step })
			end
		end
	end
end

function TutorialUI.Step(dt: number?)
	if not gui then
		return
	end
	stepTimer += num(dt, 0.2)
	if marker.gui and marker.gui.Enabled then
		marker.bounce = (marker.bounce or 0) + num(dt, 0.2)
		marker.gui.StudsOffset = Vector3.new(0, 4 + 0.4 * math.sin(marker.bounce * 3), 0)
	end
	if stepTimer < 0.2 then
		return
	end
	local ok, err = pcall(autoNext)
	if not ok then
		warn("[Tutorial] " .. tostring(err))
	end
	stepTimer = 0
	renderCard()
	updateMarker()
	if hint.frame and hint.frame.Visible then
		placeHintCard()
	end
end

---------------------------------------------------------------- Zugriff (Tests)
function TutorialUI.View()
	return view
end

function TutorialUI.CardVisible(): boolean
	return card.frame ~= nil and card.frame.Visible == true
end

function TutorialUI.HintVisible(): boolean
	return hint.frame ~= nil and hint.frame.Visible == true
end

function TutorialUI.UnlockVisible(): boolean
	return unlock.frame ~= nil and unlock.frame.Visible == true
end

function TutorialUI.MarkerTarget(): Instance?
	return marker.gui and marker.gui.Enabled and marker.gui.Adornee or nil
end

function TutorialUI.Gui()
	return gui
end

return TutorialUI
