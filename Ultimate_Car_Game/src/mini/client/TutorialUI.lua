-- TutorialUI: Tutorial-Karte, Welt-Marker, Beginner-Hinweiskarte und Freischaltungs-Karte auf dem Client
-- (docs/PHASE4_CONTRACT.md §6). Kein Tab: MiniClient ruft TutorialUI.Start(ctx) (oder Build(nil, ctx)),
-- OnSnapshot(s), OnNotice(data) und Step(dt) aus dem Heartbeat. Der Client zeigt nur an und sendet Absichten
-- (tutorial_next {step} für „Weiter“-Schritte, tutorial_skip); den Fortschritt bestätigt der Server.
--
-- Eigene ScreenGui "Tutorial" (DisplayOrder 17: UNTER dem 2.4.0-UI (20) – Dialoge, QTE, Tablet und Fahrzeugknöpfe
-- liegen immer darüber und bekommen jeden Klick; unter dem Minispiel-Panel (30)). Die Rahmen sind nicht Active, nur
-- die Knöpfe schlucken Klicks; leere Kartenflächen lassen Weltklicks (GarageClient) durch.
--   Card       unten Mitte über der 2.4.0-Leiste (Leiste 132 px hoch, 6 px Rand): Schritt-Text, „Schritt n von m“,
--              Fortschrittsbalken, „Weiter“ (nur next-Schritte), „Überspringen“ (immer). Touch-Flächen 44 px.
--              Überschneidet sie die Fahrzeugknöpfe E/F/H, rückt sie darüber; passt das nicht (Handy quer), steht sie
--              rechts neben den Knöpfen (notfalls schmaler). Niedrige Bildschirme (< CompactHeight): kompakte Karte.
--   Marker     BillboardGui am Zielteil (zone plot: PlayerWorkshops.Plot_<UserId>.Stations.<key>,
--              zone city: workspace.City.Stations.<key>), AlwaysOnTop, leicht wippend.
--   HintCard   Beginner-Hinweis oben rechts, unter dem ProgressHUD-Abzeichen und unter der Toast-Zone (tatsächliche Lage
--              über PrestigeUI.OverlayTop, bei jeder Größenänderung neu; liegt dort gerade die Karte „Neu freigeschaltet“
--              (UnlocksUI), rückt der Hinweis darunter). Mehrere Hinweise hintereinander laufen als Warteschlange
--              (je HintSeconds), damit keiner den anderen im selben Moment überschreibt.
--   UnlockCard „Freigeschaltet: <Titel>“ bei mini_notice { kind = "unlock" } mit kurzem Effekt – nur, wenn nicht schon
--              UnlocksUI (ScreenGui "UnlockCards") die Karte zeigt (sonst gäbe es sie doppelt).
-- Sichtbarkeit wie beim ProgressHUD: weg, solange Minispiel-Panel, 2.4.0-Tablet, QTE/Diagnose oder Tacho zu sehen sind –
-- das gilt für alle Karten (auch Hinweis/Freischaltung; deren Anzeigezeit läuft erst ab, wenn sie zu sehen waren).
-- MiniClient ruft TutorialUI.Refresh() sofort, wenn sich 2.4.0-Dialog, Tablet oder Panel öffnen/schließen.
-- Komfort: der Schritt „menu“ gilt als gelesen, sobald das Minispiel-Panel offen war; der Schritt „move“, sobald die
-- Figur ein Stück gelaufen ist (beides sendet tutorial_next – der Server prüft den Schritt).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(Mini:WaitForChild("GameConfig"))
local TutorialRules = require(Mini:WaitForChild("TutorialRules"))
local PrestigeUI = require(script.Parent:WaitForChild("PrestigeUI"))

local TutorialUI = {}

TutorialUI.DisplayOrder = 17 -- unter dem 2.4.0-UI (20): dessen Dialoge/Knöpfe liegen immer darüber
TutorialUI.CardWidth = 440
TutorialUI.CardBottom = 150 -- Abstand zur Unterkante (2.4.0-Leiste: 132 px + 6 px Rand + Luft)
TutorialUI.CardTopMin = 62 -- Oberkante nicht über die 2.4.0-Fortschrittsleiste (y 8..54)
TutorialUI.CardMinWidth = 260 -- schmaler wird die Karte neben den Fahrzeugknöpfen nicht
TutorialUI.CardMargin = 12
TutorialUI.CompactHeight = PrestigeUI.CompactHeight -- darunter (Handy quer): kompakte Karte ohne Balken, kleinere Schrift
TutorialUI.HintWidth = 300
TutorialUI.HintTop = 62 + 60 + 8 -- Mindestabstand: unter der Toast-Zone; tatsächlich PrestigeUI.OverlayTop() (Abzeichen)
TutorialUI.HintSeconds = 8
TutorialUI.UnlockSeconds = 6
TutorialUI.QueueMax = 8
TutorialUI.FinishSeconds = 5
TutorialUI.MoveSeconds = 0.6 -- so lange muss die Figur laufen, bis „move“ als erledigt gilt

local TARGET_TITLES = {
	workshop = "EMPFANG",
	map = "STADTPLAN",
	dealer = "AUTOHAUS",
	goals = "INFOTAFEL",
	tuning = "TUNING-ZENTRUM",
	press = "SCHROTTPRESSE",
	kiesplatz = "KIESPLATZ",
}

local UI, Remote, T, ctx
local gui, card, marker, hint, unlock = nil, {}, {}, {}, {}
local view = nil -- letzter Stand (Snapshot-Feld tutorial oder tutorial-Hinweis)
local stepTimer = 0
local hintSerial, unlockSerial, finishSerial = 0, 0, 0
local sentNextFor = nil -- Schrittnummer, für die der Client schon tutorial_next geschickt hat
local movedFor = 0
local finishedUntil = 0
local finishedAgain = false -- Endkarte nach einem Neustart: die Belohnung gab es schon
local hintQueue, unlockQueue = {}, {} -- wartende Hinweise/Freischaltungen
local hintShowing, unlockShowing = false, false

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
		Size = UDim2.new(0, TutorialUI.CardWidth, 0, 0), Visible = false, Active = false,
	})
	UI.Corner(frame, 12)
	card.padding = UI.Padding(frame, 16, 12)
	card.list = UI.List(frame, 8)
	card.frame = frame
	card.progress = UI.Label(frame, "", { Name = "Progress", Font = UI.FontBold, TextSize = 14, TextColor3 = T.green, LayoutOrder = 1 })
	card.text = UI.Label(frame, "", { Name = "Text", TextSize = 16, LayoutOrder = 2 })
	local bar, fill = UI.Progress(frame, T.green, 3)
	bar.Name = "Bar"
	card.bar = bar
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
	local padding = UI.Padding(frame, 14, 10)
	local list = UI.List(frame, 4)
	local stripe = UI.Frame(frame, { BackgroundColor3 = T.blue, Size = UDim2.new(1, 0, 0, 3), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 0 })
	UI.Corner(stripe, 2)
	hint.frame = frame
	hint.title = UI.Label(frame, "Tipp", { Name = "Title", Font = UI.FontBold, TextSize = 15, TextColor3 = T.blue, LayoutOrder = 1 })
	hint.text = UI.Label(frame, "", { Name = "Text", TextSize = 14, LayoutOrder = 2 })
	hint.style = { padding = padding, list = list, title = hint.title, text = hint.text, titleSize = 15, textSize = 14, padX = 14, padY = 10, gap = 4 }
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
	local padding = UI.Padding(frame, 14, 10)
	local list = UI.List(frame, 4)
	local stripe = UI.Frame(frame, { BackgroundColor3 = T.green, Size = UDim2.new(1, 0, 0, 3), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 0 })
	UI.Corner(stripe, 2)
	unlock.frame = frame
	unlock.title = UI.Label(frame, "", { Name = "Title", Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	unlock.text = UI.Label(frame, "", { Name = "Text", TextSize = 14, TextColor3 = T.muted, LayoutOrder = 2 })
	unlock.style = { padding = padding, list = list, title = unlock.title, text = unlock.text, titleSize = 16, textSize = 14, padX = 14, padY = 10, gap = 4 }
	unlock.scale = Instance.new("UIScale")
	unlock.scale.Scale = 1
	unlock.scale.Parent = frame
end

-- 2.4.0-Fahrzeugknöpfe (E · Arbeiten, F · Hebebühne, H · Motorhaube) unten links: genau die Höhe der Karte. Auf
-- schmalen Bildschirmen (< ~1184 px) läge die Karte darüber – gerade in den Schritten OBD/Reparatur, die diese
-- Knöpfe brauchen. Sind sie zu sehen und überschneiden sich waagerecht, rückt die Karte darüber.
local function vehicleActionsFrame(): GuiObject?
	local pg = playerGui()
	local va = pg and pg:FindFirstChild("VehicleActions", true)
	if not va or not va:IsA("GuiObject") or not va.Visible then
		return nil
	end
	local layer = va:FindFirstAncestorWhichIsA("LayerCollector")
	if layer and layer.Enabled == false then
		return nil
	end
	return va
end

function TutorialUI.CardBottomFor(w: number): number
	local va = vehicleActionsFrame()
	if not va then
		return TutorialUI.CardBottom
	end
	local cw = math.min(TutorialUI.CardWidth, w - 24)
	local cardLeft = w / 2 - cw / 2
	local vaRight = va.AbsolutePosition.X + va.AbsoluteSize.X
	if va.AbsoluteSize.X > 0 and cardLeft >= vaRight + 8 then
		return TutorialUI.CardBottom -- breit genug: nebeneinander
	end
	local h = va.AbsoluteSize.Y > 0 and va.AbsoluteSize.Y or 126
	return TutorialUI.CardBottom + h + 8
end

-- Höhe der Karte; vor dem ersten Layout grob aus dem Text geschätzt
local function cardHeight(cw: number): number
	local h = card.frame.AbsoluteSize.Y
	if h > 0 then
		return h
	end
	local size = card.text.TextSize
	local text = tostring(card.text.Text or "")
	local okLen, chars = pcall(utf8.len, text)
	chars = okLen and chars or #text
	local lines = math.max(1, math.ceil(chars * size * 0.5 / math.max(1, cw - 32)))
	local pad = card.padding and card.padding.PaddingTop.Offset * 2 or 24
	local bar = card.bar and card.bar.Visible and 16 or 0
	return pad + 17 + 16 + lines * size * 1.2 + bar + UI.MinTouch
end

local function compact(h: number): boolean
	return h > 0 and h < TutorialUI.CompactHeight
end
TutorialUI.Compact = compact

local function placeCard()
	if not gui or not card.frame then
		return
	end
	local w, h = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	if w <= 0 then
		return
	end
	local small = compact(h)
	if card.small ~= small then
		card.small = small
		if card.bar then
			card.bar.Visible = not small
		end
		card.text.TextSize = small and 14 or 16
		if card.padding then
			card.padding.PaddingTop = UDim.new(0, small and 8 or 12)
			card.padding.PaddingBottom = UDim.new(0, small and 8 or 12)
		end
		if card.list then
			card.list.Padding = UDim.new(0, small and 4 or 8)
		end
	end
	local cw = math.min(TutorialUI.CardWidth, w - 2 * TutorialUI.CardMargin)
	local bottom = TutorialUI.CardBottomFor(w)
	local right = false
	if bottom > TutorialUI.CardBottom and h > 0 and h - bottom - cardHeight(cw) < TutorialUI.CardTopMin then
		-- über den Fahrzeugknöpfen ist kein Platz (Handy quer): rechts daneben, notfalls schmaler
		local _, _, zx1 = PrestigeUI.VehicleZone(w, h)
		local avail = w - TutorialUI.CardMargin - (zx1 + PrestigeUI.GarageGap)
		if avail >= TutorialUI.CardMinWidth then
			cw = math.min(cw, avail)
			bottom = TutorialUI.CardBottom
			right = true
		end
	end
	local size = UDim2.new(0, cw, 0, 0)
	if card.frame.Size ~= size then
		card.frame.Size = size
	end
	local anchor = Vector2.new(right and 1 or 0.5, 1)
	if card.frame.AnchorPoint ~= anchor then
		card.frame.AnchorPoint = anchor
	end
	local pos = right and UDim2.new(1, -TutorialUI.CardMargin, 1, -bottom) or UDim2.new(0.5, 0, 1, -bottom)
	if card.frame.Position ~= pos then
		card.frame.Position = pos
	end
end
TutorialUI.PlaceCard = placeCard

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
	local small = compact(gui.AbsoluteSize.Y)
	PrestigeUI.StyleCard(hint.style, small)
	PrestigeUI.StyleCard(unlock.style, small)
	-- Lage unter Abzeichen und Toast-Zone (Abzeichen rückt auf schmalen Bildschirmen auf y 60)
	unlock.frame.Position = UDim2.new(1, -16, 0, TutorialUI.FreeTop(unlock.frame, TutorialUI.OverlayTop()))
	TutorialUI.PlaceHintCard()
	-- Handy hochkant: die Knöpfe teilen sich die Breite
	local narrow = w < 480
	card.skip.Size = UDim2.new(narrow and 0.5 or 0, narrow and -4 or 150, 0, UI.MinTouch)
	card.next.Size = UDim2.new(narrow and 0.5 or 0, narrow and -4 or 130, 0, UI.MinTouch)
	placeCard()
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
	placeCard() -- über den 2.4.0-Fahrzeugknöpfen, falls die gerade zu sehen sind
	local count = math.max(1, math.floor(num(view.count, TutorialRules.Count())))
	local step = math.clamp(math.floor(num(view.step, 1)), 1, count)
	if TutorialUI.Finished() and not view.active then
		card.progress.Text = "Tutorial geschafft!"
		if finishedAgain then
			card.text.Text = "Tutorial noch einmal geschafft – viel Spaß!"
		else
			card.text.Text = "Belohnung: " .. tostring(GameConfig.Tutorial.Reward.credits) .. " Credits und " .. tostring(GameConfig.Tutorial.Reward.xp) .. " XP. Viel Spaß!"
		end
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
		rewarded = v.rewarded == true or (v.rewarded == nil and view ~= nil and view.rewarded == true),
		openTab = type(v.openTab) == "string" and v.openTab or nil, -- Startweg: Öffnen dieses Tabs erledigt den Schritt
		path = type(v.path) == "string" and v.path or nil,
		waiting = v.waiting == true, -- Startwahl offen: noch keine Karte
	}
	if view.step ~= before then
		sentNextFor = nil
		movedFor = 0
	end
	if v.finished == true and not view.skipped then
		-- Server meldet again = true, wenn die Belohnung schon vor diesem Durchlauf ausgezahlt war
		finishedAgain = v.again == true
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
-- Oberkante einer Karte oben rechts, die nicht in die 2.4.0-HUD-Leiste oder die Fahrzeugknöpfe ragt (gemessene Höhe)
function TutorialUI.FreeTop(frame: GuiObject, top: number): number
	if not gui then
		return top
	end
	local w, h = gui.AbsoluteSize.X, gui.AbsoluteSize.Y
	local fw, fh = frame.AbsoluteSize.X, frame.AbsoluteSize.Y
	if w <= 0 or h <= 0 or fh <= 0 then
		return top
	end
	local _, y = PrestigeUI.FreeRect(w, h, w - 16 - fw, top, fw, fh)
	return y
end
-- Oberkante der Karten oben rechts: unter dem Abzeichen (tatsächliche Lage) und unter der Toast-Zone
function TutorialUI.OverlayTop(): number
	local top = TutorialUI.HintTop
	local ok, t = pcall(PrestigeUI.OverlayTop)
	if ok and type(t) == "number" and t == t then
		top = math.max(top, t)
	end
	return top
end

local function placeHintCard()
	if not hint.frame then
		return
	end
	-- unter der Karte „Neu freigeschaltet“ (UnlocksUI oder eigene), falls die gerade zu sehen ist
	local top = TutorialUI.OverlayTop()
	local pg = playerGui()
	local other = pg and pg:FindFirstChild("UnlockCards")
	local otherCard = other and other:FindFirstChild("UnlockCard")
	local candidates = { otherCard, unlock.frame }
	for _, c in ipairs(candidates) do
		if c and c.Visible and c.AbsoluteSize.Y > 0 then
			top = math.max(top, c.AbsolutePosition.Y - (gui and gui.AbsolutePosition.Y or 0) + c.AbsoluteSize.Y + 8)
		elseif c and c.Visible then
			top = math.max(top, TutorialUI.OverlayTop() + 80)
		end
	end
	hint.frame.Position = UDim2.new(1, -16, 0, TutorialUI.FreeTop(hint.frame, top))
end
TutorialUI.PlaceHintCard = placeHintCard

-- Karte „Neu freigeschaltet“ (UnlocksUI oder eigene) gerade zu sehen?
local function unlockCardVisible(): boolean
	if unlock.frame and unlock.frame.Visible then
		return true
	end
	local pg = playerGui()
	local other = pg and pg:FindFirstChild("UnlockCards")
	local otherCard = other and other:IsA("LayerCollector") and other.Enabled and other:FindFirstChild("UnlockCard")
	return otherCard ~= nil and otherCard:IsA("GuiObject") and otherCard.Visible == true
end

-- Darf der Hinweis zu sehen sein? Wie alle Karten nicht über Dialog/Tablet/Panel; auf niedrigen Bildschirmen außerdem
-- nicht gleichzeitig mit der Freischaltungs-Karte (beide passen nicht zwischen Toast-Zone und HUD-Leiste)
local function hintAllowed(): boolean
	if not overlaysAllowed() then
		return false
	end
	return not (gui and compact(gui.AbsoluteSize.Y) and unlockCardVisible())
end

local function showNextHint()
	if hintShowing or #hintQueue == 0 or not hint.frame then
		return
	end
	if gui and compact(gui.AbsoluteSize.Y) and unlockCardVisible() then
		return -- niedriger Bildschirm: wartet, bis die Freischaltungs-Karte weg ist (Refresh versucht es erneut)
	end
	local entry = table.remove(hintQueue, 1)
	hintShowing = true
	hintSerial += 1
	local serial = hintSerial
	hint.text.Text = entry.text
	hint.frame:SetAttribute("hintId", entry.id or "")
	placeHintCard()
	hint.frame.Visible = hintAllowed()
	pop(hint.scale)
	local function expire()
		if serial ~= hintSerial or not hint.frame then
			return
		end
		if not hintAllowed() then
			task.delay(TutorialUI.HintSeconds, expire) -- verdeckt (Dialog/Tablet/Panel): später noch zeigen
			return
		end
		hint.frame.Visible = false
		hintShowing = false
		showNextHint()
	end
	task.delay(TutorialUI.HintSeconds, expire)
end

-- Hinweis einreihen: sofort, wenn keiner zu sehen ist, sonst nach dem laufenden (je HintSeconds)
function TutorialUI.ShowHint(text: string, id: string?)
	if not hint.frame or type(text) ~= "string" or text == "" then
		return
	end
	if #hintQueue >= TutorialUI.QueueMax then
		table.remove(hintQueue, 1)
	end
	table.insert(hintQueue, { text = text, id = id })
	showNextHint()
end

function TutorialUI.QueuedHints(): number
	return #hintQueue
end

-- Zeigt UnlocksUI die Karte schon (ScreenGui "UnlockCards")? Dann keine zweite.
local function unlockCardHandledElsewhere(): boolean
	local pg = playerGui()
	local other = pg and pg:FindFirstChild("UnlockCards")
	return other ~= nil and other:FindFirstChild("UnlockCard") ~= nil
end

local function showNextUnlock()
	if unlockShowing or #unlockQueue == 0 or not unlock.frame then
		return
	end
	local entry = table.remove(unlockQueue, 1)
	unlockShowing = true
	unlockSerial += 1
	local serial = unlockSerial
	unlock.title.Text = "Freigeschaltet: " .. entry.title
	unlock.text.Text = entry.text or ""
	unlock.text.Visible = entry.text ~= nil and entry.text ~= ""
	unlock.frame.Position = UDim2.new(1, -16, 0, TutorialUI.FreeTop(unlock.frame, TutorialUI.OverlayTop()))
	unlock.frame.Visible = overlaysAllowed()
	pop(unlock.scale)
	local function expire()
		if serial ~= unlockSerial or not unlock.frame then
			return
		end
		if not overlaysAllowed() then
			task.delay(TutorialUI.UnlockSeconds, expire)
			return
		end
		unlock.frame.Visible = false
		unlockShowing = false
		showNextUnlock()
	end
	task.delay(TutorialUI.UnlockSeconds, expire)
end

function TutorialUI.ShowUnlock(title: string, text: string?)
	if not unlock.frame or type(title) ~= "string" or title == "" then
		return
	end
	if #unlockQueue >= TutorialUI.QueueMax then
		table.remove(unlockQueue, 1)
	end
	table.insert(unlockQueue, { title = title, text = text })
	showNextUnlock()
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
	elseif type(view.openTab) == "string" then
		-- Startweg-Schritt „Tab öffnen“ (z. B. Gebäude): erledigt, sobald das Panel auf diesem Tab steht
		if UI and UI.IsOpen and UI.CurrentTab == view.openTab then
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
	TutorialUI.Refresh()
end

-- Sichtbarkeit aller Karten sofort neu (Heartbeat alle 0,2 s und MiniClient.RefreshOverlays bei jedem Wechsel von
-- 2.4.0-Dialog, Tablet oder Panel – damit nie eine Karte im selben Moment über einem Dialog liegt)
function TutorialUI.Refresh()
	if not gui then
		return
	end
	renderCard()
	updateMarker()
	local allowed = overlaysAllowed()
	if unlock.frame and unlock.frame.Visible ~= (unlockShowing and allowed) then
		unlock.frame.Visible = unlockShowing and allowed
	end
	local hintOk = hintAllowed()
	if hint.frame and hint.frame.Visible ~= (hintShowing and hintOk) then
		hint.frame.Visible = hintShowing and hintOk
	end
	if not hintShowing and hintOk then
		showNextHint()
	end
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
