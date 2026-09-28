-- MiniUI: Gerüst der Minispiel-Oberfläche (ScreenGui "Minispiele", DisplayOrder 30) und kleine Bausteine.
-- Farben und Schriften wie im 2.4.0-Tablet (GarageClient), Touch-Flächen mindestens 44 px.
-- Die Oberfläche liegt über dem 2.4.0-UI (DisplayOrder 20) und unter den Feiern (GarageCelebrations, 45).
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local GuiService = game:GetService("GuiService")

local UI = {}

-- 2.4.0-Palette (GarageClient `colors`), dazu die 3.0-Namen als Alias
local P = {
	bg = Color3.fromRGB(11, 16, 25),
	panel = Color3.fromRGB(20, 29, 43),
	card = Color3.fromRGB(28, 40, 57),
	line = Color3.fromRGB(49, 67, 87),
	text = Color3.fromRGB(235, 243, 250),
	muted = Color3.fromRGB(156, 176, 199),
	green = Color3.fromRGB(50, 192, 137),
	blue = Color3.fromRGB(59, 134, 218),
	red = Color3.fromRGB(212, 65, 89),
	yellow = Color3.fromRGB(235, 184, 72),
	purple = Color3.fromRGB(143, 82, 214),
	purpleDark = Color3.fromRGB(79, 47, 124),
}
UI.Theme = {
	bg = P.bg, panel = P.panel, card = P.card, panel2 = P.card, line = P.line,
	text = P.text, muted = P.muted,
	green = P.green, accent = P.green,
	blue = P.blue, accent2 = P.blue,
	yellow = P.yellow, warn = P.yellow,
	red = P.red, danger = P.red,
	purple = P.purple, purpleDark = P.purpleDark,
	path = Color3.fromRGB(36, 52, 72),
}
local T = UI.Theme
UI.MinTouch = 44
UI.Font = Enum.Font.Gotham
UI.FontBold = Enum.Font.GothamBold
UI.FontBig = Enum.Font.GothamBlack

UI.Tabs = {
	{ key = "overview", label = "Übersicht" },
	{ key = "press", label = "Schrottpresse" },
	{ key = "tuning", label = "Tuning" },
	{ key = "scrapyard", label = "Schrottplatz" },
	{ key = "quiz", label = "Quiz" },
	{ key = "parking", label = "Parkplatz" },
	{ key = "goals", label = "Ziele" },
	{ key = "leaderboard", label = "Bestenliste" },
	{ key = "map", label = "Schnellreise" },
	{ key = "shop", label = "Game Passes" },
}
UI.TabTitles = {
	overview = "Minispiele · Übersicht",
	press = "Schrottpresse",
	tuning = "Idle Tuning Garage",
	scrapyard = "Schrottplatz",
	quiz = "Mechaniker-Quiz",
	parking = "Parkplatz-Chaos",
	goals = "Ziele und Meilensteine",
	leaderboard = "Bestenliste",
	map = "Schnellreise",
	shop = "Game Passes",
}

UI.Pages = {} -- [key] = Frame
UI.TabButtons = {}
UI.CurrentTab = nil
UI.IsOpen = false
UI.Compact = false
UI.OnTabShown = nil -- function(key)
UI.OnOpenChanged = nil -- function(isOpen)

---------------------------------------------------------------- Bausteine
function UI.Corner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 10)
	c.Parent = parent
	return c
end

function UI.Padding(parent, x, y)
	local p = Instance.new("UIPadding")
	p.PaddingLeft = UDim.new(0, x)
	p.PaddingRight = UDim.new(0, x)
	p.PaddingTop = UDim.new(0, y or x)
	p.PaddingBottom = UDim.new(0, y or x)
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
	f.BackgroundColor3 = T.card
	f.BorderSizePixel = 0
	f.Size = UDim2.new(1, 0, 0, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	for k, v in pairs(props or {}) do
		f[k] = v
	end
	f.Parent = parent
	return f
end

-- Karte wie im 2.4.0-Tablet: Ecke 10, 16 px Innenabstand seitlich, kein Rahmen
function UI.Card(parent, order)
	local f = UI.Frame(parent, { LayoutOrder = order or 0 })
	UI.Corner(f, 10)
	UI.Padding(f, 16, 12)
	UI.List(f, 8)
	return f
end

function UI.Label(parent, text, props)
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.Font = UI.Font
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
	return UI.Label(parent, text, { Font = UI.FontBold, TextSize = 20, LayoutOrder = order or 0 })
end

function UI.Small(parent, text, order)
	return UI.Label(parent, text, { TextSize = 15, TextColor3 = T.muted, LayoutOrder = order or 0 })
end

-- Knopf wie im 2.4.0-UI (GothamBold 15, helle Schrift, Ecke 8, kurzer Druck-Effekt),
-- aber mindestens 44 px hoch und mit 0,3 s Entprellung (Doppeltipp = eine Absicht).
function UI.Button(parent, text, color, onClick, props)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color or T.green
	b.BorderSizePixel = 0
	b.Size = UDim2.new(1, 0, 0, UI.MinTouch)
	b.Font = UI.FontBold
	b.TextSize = 15
	b.TextColor3 = T.text
	b.TextWrapped = true
	b.Text = text or ""
	for k, v in pairs(props or {}) do
		b[k] = v
	end
	b:SetAttribute("baseColor", b.BackgroundColor3)
	UI.Corner(b, 8)
	local press = Instance.new("UIScale")
	press.Scale = 1
	press.Parent = b
	local last = 0
	b.Activated:Connect(function()
		local now = os.clock()
		if now - last < 0.3 or b:GetAttribute("disabled") then
			return
		end
		last = now
		press.Scale = 0.95
		TweenService:Create(press, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if onClick then
			onClick()
		end
	end)
	b.Parent = parent
	return b
end

-- Deaktiviert: dezente Fläche (line) mit gedämpfter Schrift, damit der Knopf auf der Karte sichtbar bleibt
function UI.SetEnabled(button, enabled, color)
	button:SetAttribute("disabled", not enabled)
	if color then
		button:SetAttribute("baseColor", color)
	end
	button.BackgroundColor3 = enabled and (button:GetAttribute("baseColor") or T.green) or T.line
	button.TextColor3 = enabled and T.text or T.muted
	button.AutoButtonColor = enabled
end

function UI.Progress(parent, color, order)
	local bar = UI.Frame(parent, { Size = UDim2.new(1, 0, 0, 8), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = T.bg, LayoutOrder = order or 0 })
	UI.Corner(bar, 4)
	local fill = UI.Frame(bar, { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None, BackgroundColor3 = color or T.green })
	UI.Corner(fill, 4)
	return bar, fill
end

function UI.SetProgress(fill, fraction)
	if type(fraction) ~= "number" or fraction ~= fraction then
		fraction = 0
	end
	fill.Size = UDim2.new(math.clamp(fraction, 0, 1), 0, 1, 0)
end

-- Zeile: Text links, Knopf rechts (130 px, passt auch bei 390 px Bildschirmbreite)
UI.RowButtonWidth = 130
function UI.Row(parent, order)
	local w = UI.RowButtonWidth
	local row = UI.Frame(parent, { BackgroundTransparency = 1, LayoutOrder = order or 0 })
	local left = UI.Frame(row, { BackgroundTransparency = 1, Size = UDim2.new(1, -(w + 10), 0, 0) })
	UI.List(left, 3)
	local right = UI.Frame(row, {
		BackgroundTransparency = 1, Size = UDim2.new(0, w, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(1, -w, 0, 0),
	})
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

-- Ausbau-Zeile für tuningLevel / scrapyardLevel (Snapshot-Feld `upgrades`)
function UI.UpgradeCard(parent, order, key, remote)
	local card = UI.Card(parent, order)
	local title = UI.Title(card, "Ausbau", 1)
	local row, left, right = UI.Row(card, 2)
	local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	local desc = UI.Small(left, "", 2)
	local item = { key = key, level = nil }
	local button = UI.Button(right, "", T.blue, function()
		if item.level then
			remote.Send("mini_upgrade", { key = key, level = item.level })
		end
	end)
	item.root, item.title, item.name, item.desc, item.button = card, title, name, desc, button
	function item.Render(s, fmtCredits)
		local u
		for _, entry in ipairs(s.upgrades or {}) do
			if entry.key == key then
				u = entry
				break
			end
		end
		card.Visible = u ~= nil
		if not u then
			item.level = nil
			return
		end
		item.level = u.level
		name.Text = (u.name or key) .. " · Stufe " .. tostring(u.level)
		desc.Text = u.desc or ""
		local max = u.max and u.level >= u.max
		button.Text = max and "Voll ausgebaut" or fmtCredits(u.cost or 0)
		UI.SetEnabled(button, (not max) and (s.credits or 0) >= (u.cost or math.huge), T.blue)
	end
	row.Name = "Upgrade_" .. key
	return item
end

---------------------------------------------------------------- Gerüst
local function setTouchControls(enabled)
	pcall(function()
		GuiService.TouchControlsEnabled = enabled
	end)
end

function UI.Build()
	local player = Players.LocalPlayer
	local gui = Instance.new("ScreenGui")
	gui.Name = "Minispiele"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 30
	gui.Parent = player:WaitForChild("PlayerGui")
	UI.Gui = gui

	-- Panel (schluckt Touch und Klicks, damit Kamera und Welt-Klicks darunter ruhig bleiben)
	local panel = UI.Frame(gui, {
		Name = "Panel", BackgroundColor3 = T.bg, AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, 0), Size = UDim2.new(0.97, 0, 0.94, 0),
		Visible = false, Active = true, ZIndex = 5,
	})
	UI.Corner(panel, 10)
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(860, 720)
	limit.Parent = panel
	UI.Panel = panel

	local header = UI.Frame(panel, {
		Name = "Header", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, -32, 0, 50), Position = UDim2.new(0, 16, 0, 10),
	})
	UI.Header = header
	UI.HeaderTitle = UI.Label(header, "Minispiele", {
		Font = UI.FontBold, TextSize = 22, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -60, 0, 26),
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.HeaderInfo = UI.Label(header, "", {
		TextSize = 14, TextColor3 = T.muted, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -60, 0, 22),
		Position = UDim2.new(0, 0, 0, 27), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.CloseButton = UI.Button(panel, "×", T.card, function()
		UI.Close()
	end, { Name = "Close", Size = UDim2.new(0, 48, 0, 48), Position = UDim2.new(1, -60, 0, 10), TextSize = 24 })

	local tabs = Instance.new("ScrollingFrame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.BorderSizePixel = 0
	tabs.CanvasSize = UDim2.new(0, 0, 0, 0)
	tabs.AutomaticCanvasSize = Enum.AutomaticSize.X
	tabs.ScrollingDirection = Enum.ScrollingDirection.X
	tabs.ScrollBarThickness = 3
	tabs.Parent = panel
	UI.TabBar = tabs
	UI.List(tabs, 8, true)

	local content = Instance.new("ScrollingFrame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.BorderSizePixel = 0
	content.CanvasSize = UDim2.new(0, 0, 0, 0)
	content.AutomaticCanvasSize = Enum.AutomaticSize.Y
	content.ScrollingDirection = Enum.ScrollingDirection.Y
	content.ScrollBarThickness = 5
	content.Parent = panel
	UI.Content = content

	for i, tab in ipairs(UI.Tabs) do
		local b = UI.Button(tabs, tab.label, T.card, function()
			UI.Show(tab.key)
		end, { Name = "Tab_" .. tab.key, Size = UDim2.new(0, 0, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = i })
		UI.Padding(b, 14, 0)
		UI.TabButtons[tab.key] = b
		local page = UI.Frame(content, { Name = "Page_" .. tab.key, BackgroundTransparency = 1, Visible = false, Size = UDim2.new(1, -8, 0, 0) })
		UI.List(page, 12)
		UI.Pages[tab.key] = page
	end

	-- Spiegel des 2.4.0-Toasts: gleiche Stelle, gleiche Größe, gleicher Stil. Nur sichtbar, solange das
	-- Panel offen ist (sonst läge der 2.4.0-Toast verdeckt unter dem Panel). Er deckt den 2.4.0-Toast
	-- exakt ab, daher sieht der Spieler immer genau einen Hinweis.
	local toast = UI.Frame(gui, {
		Name = "ToastMirror", BackgroundColor3 = T.panel, AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 62), Size = UDim2.new(0, 330, 0, 60),
		Visible = false, ZIndex = 20,
	})
	UI.Corner(toast, 10)
	UI.ToastLabel = UI.Label(toast, "", {
		AutomaticSize = Enum.AutomaticSize.None, Position = UDim2.new(0, 14, 0, 3), Size = UDim2.new(1, -28, 0, 54),
		TextSize = 14, ZIndex = 21, TextYAlignment = Enum.TextYAlignment.Center,
	})
	UI.ToastPanel = toast

	-- Bestätigungsdialog (eigener, damit ein 2.4.0-interactionReset ihn nicht schließt)
	local shade = UI.Frame(gui, {
		Name = "Confirm", BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.fromScale(1, 1), Visible = false, ZIndex = 30, Active = true,
	})
	local box = UI.Frame(shade, {
		BackgroundColor3 = T.panel, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.new(0.9, 0, 0, 0), ZIndex = 31,
	})
	UI.Corner(box, 10)
	UI.Padding(box, 20, 18)
	UI.List(box, 10)
	local boxLimit = Instance.new("UISizeConstraint")
	boxLimit.MaxSize = Vector2.new(480, 600)
	boxLimit.Parent = box
	UI.ConfirmTitle = UI.Label(box, "Bitte bestätigen", { Font = UI.FontBold, TextSize = 22, LayoutOrder = 1, ZIndex = 32 })
	UI.ConfirmText = UI.Label(box, "", { LayoutOrder = 2, ZIndex = 32, TextColor3 = T.muted, TextSize = 17 })
	UI.ConfirmYes = UI.Button(box, "Bestätigen", T.green, function()
		shade.Visible = false
		local cb = UI.ConfirmCallback
		UI.ConfirmCallback = nil
		if cb then
			cb()
		end
	end, { LayoutOrder = 3, ZIndex = 32 })
	UI.Button(box, "Zurück", T.card, function()
		shade.Visible = false
		UI.ConfirmCallback = nil
	end, { LayoutOrder = 4, ZIndex = 32 })
	UI.Shade = shade

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(UI.ApplyLayout)
	UI.ApplyLayout()
	return gui
end

-- Kompakt-Layout für niedrige Bildschirme (Handy quer, z. B. 844×390): Tabs in die Kopfzeile,
-- damit für den Inhalt genug Höhe bleibt. Hochformat (390×844) nutzt das normale Layout.
function UI.ApplyLayout()
	if not UI.Gui then
		return
	end
	local size = UI.Gui.AbsoluteSize
	local compact = size.Y > 0 and size.Y < 500
	UI.Compact = compact
	if compact then
		UI.Header.Visible = false
		UI.CloseButton.Position = UDim2.new(1, -54, 0, 6)
		UI.TabBar.Position = UDim2.new(0, 10, 0, 6)
		UI.TabBar.Size = UDim2.new(1, -72, 0, 50)
		UI.Content.Position = UDim2.new(0, 10, 0, 62)
		UI.Content.Size = UDim2.new(1, -20, 1, -68)
	else
		UI.Header.Visible = true
		UI.CloseButton.Position = UDim2.new(1, -60, 0, 10)
		UI.TabBar.Position = UDim2.new(0, 16, 0, 66)
		UI.TabBar.Size = UDim2.new(1, -32, 0, 50)
		UI.Content.Position = UDim2.new(0, 16, 0, 124)
		UI.Content.Size = UDim2.new(1, -32, 1, -136)
	end
	if UI.IsOpen then
		UI.Panel.Size = compact and UDim2.new(0.99, 0, 0.98, 0) or UDim2.new(0.97, 0, 0.94, 0)
	end
	if size.X > 0 then
		UI.ToastPanel.Size = UDim2.new(0, math.min(330, size.X - 28), 0, 60)
	end
end

function UI.Confirm(text, onYes, title, yesText, yesColor)
	UI.ConfirmTitle.Text = title or "Bitte bestätigen"
	UI.ConfirmText.Text = text or ""
	UI.ConfirmYes.Text = yesText or "Bestätigen"
	UI.SetEnabled(UI.ConfirmYes, true, yesColor or T.green)
	UI.ConfirmCallback = onYes
	UI.Shade.Visible = true
end

-- Zeigt einen Hinweis im Spiegel des 2.4.0-Toasts (nur bei offenem Panel, außer `force`).
local toastSerial = 0
function UI.MirrorToast(text, force)
	if not UI.ToastPanel or type(text) ~= "string" or text == "" then
		return
	end
	if not UI.IsOpen and not force then
		return
	end
	toastSerial += 1
	local serial = toastSerial
	UI.ToastLabel.Text = text
	UI.ToastPanel.Visible = true
	task.delay(4, function()
		if serial == toastSerial and UI.ToastPanel then
			UI.ToastPanel.Visible = false
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
		UI.TabButtons[k].BackgroundColor3 = k == key and T.green or T.card
		UI.TabButtons[k]:SetAttribute("baseColor", UI.TabButtons[k].BackgroundColor3)
	end
	UI.HeaderTitle.Text = UI.TabTitles[key] or "Minispiele"
	UI.Content.CanvasPosition = Vector2.new(0, 0)
	-- aktiven Tab in den sichtbaren Bereich der Tab-Leiste schieben (z. B. beim Öffnen über eine Station)
	local b = UI.TabButtons[key]
	local bar = UI.TabBar
	if b and bar.AbsoluteSize.X > 0 then
		local x = b.AbsolutePosition.X - bar.AbsolutePosition.X + bar.CanvasPosition.X
		if x < bar.CanvasPosition.X or x + b.AbsoluteSize.X > bar.CanvasPosition.X + bar.AbsoluteSize.X then
			bar.CanvasPosition = Vector2.new(math.max(0, x - 16), 0)
		end
	end
	if UI.OnTabShown then
		UI.OnTabShown(key)
	end
end

function UI.Open(key)
	local wasOpen = UI.IsOpen
	UI.IsOpen = true
	UI.ApplyLayout()
	UI.Panel.Visible = true
	setTouchControls(false)
	UI.Show(key or UI.CurrentTab or "overview")
	if not wasOpen then
		local full = UI.Compact and UDim2.new(0.99, 0, 0.98, 0) or UDim2.new(0.97, 0, 0.94, 0)
		UI.Panel.Size = UDim2.new(full.X.Scale - 0.04, 0, full.Y.Scale - 0.04, 0)
		TweenService:Create(UI.Panel, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = full }):Play()
		if UI.OnOpenChanged then
			UI.OnOpenChanged(true)
		end
	end
end

function UI.Close()
	if not UI.IsOpen then
		return
	end
	UI.IsOpen = false
	UI.Panel.Visible = false
	UI.Shade.Visible = false
	UI.ConfirmCallback = nil
	UI.ToastPanel.Visible = false
	setTouchControls(true)
	if UI.OnOpenChanged then
		UI.OnOpenChanged(false)
	end
end

return UI
