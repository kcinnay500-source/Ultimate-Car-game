-- UI: Grundgerüst der 2D-Oberfläche (ScreenGui, HUD, Menü mit Tabs, Toasts, Bestätigungsdialog)
-- und kleine Bausteine. Touch-Flächen sind mindestens 44 px hoch.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local UI = {}

UI.Theme = {
	bg = Color3.fromRGB(9, 13, 18),
	panel = Color3.fromRGB(18, 25, 35),
	panel2 = Color3.fromRGB(24, 34, 49),
	text = Color3.fromRGB(238, 244, 251),
	muted = Color3.fromRGB(145, 161, 181),
	accent = Color3.fromRGB(53, 208, 127),
	accent2 = Color3.fromRGB(74, 163, 255),
	warn = Color3.fromRGB(255, 189, 62),
	danger = Color3.fromRGB(255, 90, 103),
	line = Color3.fromRGB(39, 52, 70),
	purple = Color3.fromRGB(180, 120, 255),
}
local T = UI.Theme
UI.MinTouch = 44

UI.Tabs = {
	{ key = "overview", label = "Übersicht" },
	{ key = "press", label = "Schrottpresse" },
	{ key = "tuning", label = "Tuning" },
	{ key = "workshop", label = "Werkstatt" },
	{ key = "scrapyard", label = "Schrottplatz" },
	{ key = "quiz", label = "Quiz" },
	{ key = "parking", label = "Parkplatz" },
	{ key = "goals", label = "Ziele" },
	{ key = "leaderboard", label = "Bestenliste" },
	{ key = "shop", label = "Shop" },
}

UI.Pages = {} -- [key] = Frame
UI.TabButtons = {}
UI.CurrentTab = nil
UI.IsOpen = false
UI.OnTabShown = nil -- function(key)

---------------------------------------------------------------- Bausteine
function UI.Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

function UI.Padding(parent, px)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, px)
	p.PaddingRight = UDim.new(0, px)
	p.PaddingTop = UDim.new(0, px)
	p.PaddingBottom = UDim.new(0, px)
	p.Parent = parent
	return p
end

function UI.List(parent, gap, horizontal)
	local l = Instance.new("UIListLayout")
	l.Padding = UDim.new(0, gap or 8)
	l.SortOrder = Enum.SortOrder.LayoutOrder
	l.FillDirection = horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical
	l.Parent = parent
	return l
end

function UI.Frame(parent, props)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = T.panel2
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

function UI.Card(parent, order)
	local f = UI.Frame(parent, { LayoutOrder = order or 0 })
	UI.Corner(f, 12)
	UI.Padding(f, 10)
	UI.List(f, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Color = T.line
	stroke.Thickness = 1
	stroke.Parent = f
	return f
end

function UI.Label(parent, text, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = Enum.Font.GothamMedium
	l.TextSize = 16
	l.TextColor3 = T.text
	l.TextWrapped = true
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.RichText = false
	l.Text = text or ""
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	l.Parent = parent
	return l
end

function UI.Title(parent, text, order)
	return UI.Label(parent, text, { Font = Enum.Font.GothamBold, TextSize = 19, LayoutOrder = order or 0 })
end

function UI.Small(parent, text, order)
	return UI.Label(parent, text, { TextSize = 14, TextColor3 = T.muted, LayoutOrder = order or 0 })
end

-- Button mit Entprellung (0,3 s), damit ein Doppeltipp nur eine Absicht erzeugt.
function UI.Button(parent, text, color, onClick, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color or T.accent
	b.BorderSizePixel = 0
	b.Size = UDim2.new(1, 0, 0, UI.MinTouch)
	b.Font = Enum.Font.GothamBold
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(7, 17, 27)
	b.TextWrapped = true
	b.Text = text
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	UI.Corner(b, 10)
	local last = 0
	b.Activated:Connect(function()
		local t = os.clock()
		if t - last < 0.3 or b:GetAttribute("disabled") then
			return
		end
		last = t
		if onClick then
			onClick()
		end
	end)
	b.Parent = parent
	return b
end

function UI.SetEnabled(button, enabled, color)
	button:SetAttribute("disabled", not enabled)
	button.BackgroundColor3 = enabled and (color or T.accent) or T.line
	button.TextColor3 = enabled and Color3.fromRGB(7, 17, 27) or T.muted
	button.AutoButtonColor = enabled
end

function UI.Progress(parent, color, order)
	local bar = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 10), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = T.bg, LayoutOrder = order or 0 })
	UI.Corner(bar, 5)
	local fill = UI.Frame(bar, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = color or T.accent })
	UI.Corner(fill, 5)
	return bar, fill
end

function UI.SetProgress(fill, fraction)
	if fraction ~= fraction then
		fraction = 0
	end
	fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
end

-- Zeile: Text links, Button rechts
function UI.Row(parent, order)
	local row = UI.Frame(parent, { BackgroundTransparency = 1, LayoutOrder = order or 0 })
	local left = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(1, -150, 0, 0) })
	UI.List(left, 2)
	local right = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(0, 140, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.None, Position = UDim2.new(1, -140, 0, 0) })
	return row, left, right
end

-- Wiederverwendbare Liste: Zeilen werden nur neu angelegt, wenn mehr gebraucht werden.
function UI.Pool(parent, create)
	local pool = { items = {}, parent = parent }
	function pool:Ensure(n)
		for i = #self.items + 1, n do
			self.items[i] = create(self.parent, i)
		end
		for i, item in ipairs(self.items) do
			item.root.Visible = i <= n
		end
	end
	return pool
end

---------------------------------------------------------------- Gerüst
function UI.Build()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "UltimateCarGame"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.Gui = gui

	-- HUD
	local hud = UI.Frame(gui, {
		Name = "HUD", BackgroundColor3 = T.panel, BackgroundTransparency = 0.1,
		Size = UDim2.new(0, 260, 0, 0), Position = UDim2.new(0, 10, 0, 10),
	})
	UI.Corner(hud, 12)
	UI.Padding(hud, 8)
	UI.List(hud, 4)
	UI.HudCredits = UI.Label(hud, "0 Cr", { Font = Enum.Font.GothamBold, TextSize = 18, LayoutOrder = 1 })
	UI.HudScrap = UI.Label(hud, "0 kg Schrott", { TextSize = 15, TextColor3 = T.warn, LayoutOrder = 2 })
	UI.HudLevel = UI.Label(hud, "Level 1", { TextSize = 14, TextColor3 = T.muted, LayoutOrder = 3 })
	local _, xpFill = UI.Progress(hud, T.accent2, 4)
	UI.HudXp = xpFill
	UI.Hud = hud

	-- Nächstes Ziel (antippbar)
	local goal = Instance.new("TextButton")
	goal.Name = "NextGoal"
	goal.AutoButtonColor = true
	goal.BackgroundColor3 = T.panel
	goal.BackgroundTransparency = 0.1
	goal.Size = UDim2.new(0, 300, 0, 56)
	goal.AnchorPoint = Vector2.new(1, 0)
	goal.Position = UDim2.new(1, -10, 0, 10)
	goal.Text = ""
	goal.Parent = gui
	UI.Corner(goal, 12)
	UI.Padding(goal, 8)
	UI.List(goal, 4)
	UI.GoalText = UI.Label(goal, "Nächstes Ziel", { TextSize = 14, LayoutOrder = 1, TextTruncate = Enum.TextTruncate.AtEnd, TextWrapped = false, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, 18) })
	local _, goalFill = UI.Progress(goal, T.accent, 2)
	UI.GoalFill = goalFill
	UI.GoalButton = goal
	goal.Activated:Connect(function()
		UI.Open(UI.GoalTab or "overview")
	end)

	-- Menü-Knopf
	UI.MenuButton = UI.Button(gui, "Minispiele", T.accent, function()
		if UI.IsOpen then
			UI.Close()
		else
			UI.Open(UI.CurrentTab or "overview")
		end
	end, { Size = UDim2.new(0, 170, 0, 52), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -12), TextSize = 18 })

	-- Panel
	local panel = UI.Frame(gui, {
		Name = "Panel", BackgroundColor3 = T.bg, AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0.97, 0, 0.94, 0), Visible = false, ZIndex = 5,
	})
	UI.Corner(panel, 14)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(820, 700)
	limit.Parent = panel
	UI.Panel = panel

	local header = UI.Frame(panel, { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -20, 0, 48), Position = UDim2.new(0, 10, 0, 6) })
	UI.HeaderInfo = UI.Label(header, "", { Font = Enum.Font.GothamBold, TextSize = 16, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -60, 1, 0), TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Center })
	UI.Button(header, "✕", T.danger, function()
		UI.Close()
	end, { Size = UDim2.new(0, 48, 0, 48), Position = UDim2.new(1, -48, 0, 0), TextSize = 20 })

	local tabs = Instance.new("ScrollingFrame")
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.Size = UDim2.new(1, -20, 0, 54)
	tabs.Position = UDim2.new(0, 10, 0, 58)
	tabs.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.ScrollBarThickness = 4
	tabs.Parent = panel
	UI.List(tabs, 6, true)

	local content = Instance.new("ScrollingFrame")
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.Size = UDim2.new(1, -20, 1, -124)
	content.Position = UDim2.new(0, 10, 0, 116)
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ScrollBarThickness = 6
	content.Parent = panel
	UI.Content = content

	for i, tab in ipairs(UI.Tabs) do
		local b = UI.Button(tabs, tab.label, T.panel2, function()
			UI.Show(tab.key)
		end, { Size = UDim2.new(0, 0, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i, TextColor3 = T.text })
		UI.Padding(b, 12)
		UI.TabButtons[tab.key] = b
		local page = UI.Frame(content, { BackgroundTransparency = 1, Visible = false, Size = UDim2.new(1, -8, 0, 0) })
		UI.List(page, 10)
		UI.Pages[tab.key] = page
	end

	-- Toasts
	local toasts = UI.Frame(gui, {
		BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, Size = UDim2.new(0, 360, 0, 0),
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -76), ZIndex = 20,
	})
	local tl = UI.List(toasts, 6)
	tl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	tl.VerticalAlignment = Enum.VerticalAlignment.Bottom
	UI.ToastHost = toasts

	-- Bestätigungsdialog
	local shade = UI.Frame(gui, { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.4, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30 })
	local box = UI.Card(shade)
	box.ZIndex = 31
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Position = UDim2.fromScale(0.5, 0.5)
	box.Size = UDim2.new(0.9, 0, 0, 0)
	local boxLimit = Instance.new("UISizeConstraint")
	boxLimit.MaxSize = Vector2.new(460, 600)
	boxLimit.Parent = box
	UI.ConfirmText = UI.Label(box, "", { LayoutOrder = 1, ZIndex = 32 })
	UI.ConfirmYes = UI.Button(box, "Ja", T.warn, function()
		shade.Visible = false
		local cb = UI.ConfirmCallback
		UI.ConfirmCallback = nil
		if cb then
			cb()
		end
	end, { LayoutOrder = 2, ZIndex = 32 })
	UI.Button(box, "Abbrechen", T.line, function()
		shade.Visible = false
		UI.ConfirmCallback = nil
	end, { LayoutOrder = 3, ZIndex = 32, TextColor3 = T.text })
	UI.Shade = shade

	return gui
end

function UI.Confirm(text, onYes)
	UI.ConfirmText.Text = text
	UI.ConfirmCallback = onYes
	UI.Shade.Visible = true
end

function UI.Toast(text)
	if not UI.ToastHost or type(text) ~= "string" or text == "" then
		return
	end
	local children = UI.ToastHost:GetChildren()
	local count = 0
	for _, c in ipairs(children) do
		if c:IsA("TextLabel") then
			count += 1
		end
	end
	if count >= 4 then
		for _, c in ipairs(children) do
			if c:IsA("TextLabel") then
				c:Destroy()
				break
			end
		end
	end
	local l = UI.Label(UI.ToastHost, text, {
		BackgroundTransparency = 0, BackgroundColor3 = T.text, TextColor3 = Color3.fromRGB(7, 17, 27),
		Font = Enum.Font.GothamBold, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 21,
	})
	UI.Corner(l, 12)
	UI.Padding(l, 8)
	task.delay(2.4, function()
		if l.Parent then
			l:Destroy()
		end
	end)
end

function UI.Show(key)
	if not UI.Pages[key] then
		key = "overview"
	end
	UI.CurrentTab = key
	for k, page in pairs(UI.Pages) do
		page.Visible = k == key
		UI.TabButtons[k].BackgroundColor3 = k == key and T.accent2 or T.panel2
	end
	UI.Content.CanvasPosition = Vector2.new(0, 0)
	if UI.OnTabShown then
		UI.OnTabShown(key)
	end
end

function UI.Open(key)
	UI.IsOpen = true
	UI.Panel.Visible = true
	UI.Hud.Visible = false
	UI.GoalButton.Visible = false
	UI.MenuButton.Visible = false
	UI.Show(key or UI.CurrentTab or "overview")
	UI.Panel.Size = UDim2.new(0.9, 0, 0.88, 0)
	TweenService:Create(UI.Panel, TweenInfo.new(0.12), { Size = UDim2.new(0.97, 0, 0.94, 0) }):Play()
end

function UI.Close()
	UI.IsOpen = false
	UI.Panel.Visible = false
	UI.Hud.Visible = true
	UI.GoalButton.Visible = true
	UI.MenuButton.Visible = true
end

return UI
