-- StartUI: Startwahl in der Open World (wie im Tycoon) auf dem Client. Kein Tab: MiniClient ruft StartUI.Start(ctx),
-- OnSnapshot(s) und OnNotice(data) (kind = "start"). Der Client zeigt nur an und sendet die Absicht
-- start_choose {path}; was der Weg bewirkt (Gebäude, Tutorial, Story), entscheidet der Server (StartService).
--
-- Eigene ScreenGui "StartChoice" (DisplayOrder 40: über HUD (20), Tutorial/Karten (16–19) und Minispiel-Panel (30);
-- solange ein 2.4.0-Dialog (QTE/Diagnose), das Tablet oder das Minispiel-Panel offen ist, bleibt sie aus – ctx.IsGarageBusy),
-- IgnoreGuiInset = true: ein dunkler Hintergrund über dem ganzen Bildschirm (Active, schluckt Klicks – solange die Wahl
-- offen ist, soll nichts darunter reagieren) und in der Mitte eine scrollbare Tafel:
--   Titel, Einleitung, vier große Karten im Stil der Tycoon-Karten: gezeichnetes Symbol (nur Frames: Schraubenschlüssel,
--   Auto mit Preisschild, Fabrik, Schrotthaufen), Name (Werkstatt, Verkaufshaus, Herstellung, Schrottplatz), Kurzzeile,
--   zwei Zeilen „was du machst“, der Titel von Story-Kapitel 1 des Wegs, der Bonus und „Das wähle ich!“.
-- 3.x: Die Wahl ist Pflicht – es gibt kein „Später entscheiden“ mehr. Die Tafel steht, solange snapshot.start.pending gilt
-- und der Modus die Open World ist (oder kein Modus bekannt ist); nur 2.4.0-Dialoge, Tablet und Panel verdecken sie kurz.
-- Breite ≥ 700 px: zwei Spalten, sonst eine (Handy). Touch-Flächen ≥ 44 px, Schrift ≥ 14 px; die Tafel passt sich bei
-- jeder Größenänderung an (16 px Rand, nie breiter als 760 px). Nach dem Tippen auf eine Karte warten die Karten auf den
-- Server; kommt nach WaitSeconds keine Antwort, sind sie wieder frei. Direkt nach der Wahl läuft die Story (Karte
-- „Deine Mission“, MissionClient).
local Players = game:GetService("Players")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(Mini:WaitForChild("GameConfig"))

local StartUI = {}

StartUI.DisplayOrder = 40
StartUI.MaxWidth = 760
StartUI.Margin = 16
StartUI.TwoColumnsFrom = 700 -- Bildschirmbreite (px), ab der die Karten zweispaltig stehen
StartUI.WaitSeconds = 8
StartUI.CardMinHeight = 180
StartUI.IconSize = 72

local START = GameConfig.Start
local UI, Remote, T, ctx
local gui, refs = nil, { cards = {} }
local latest = nil -- letztes Snapshot-Feld start
local mode = nil -- letzter Modus aus dem Snapshot
local pendingPath = nil -- gewählter Weg, bis der Server antwortet
local sentAt = 0
local columns = 0

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return player and player:FindFirstChild("PlayerGui")
end

local function texts(): any
	return START and START.Texts or {}
end

local function color(name: any): Color3
	return (type(name) == "string" and T and T[name]) or (T and T.blue) or Color3.fromRGB(70, 130, 220)
end

local function darker(c: Color3, f: number): Color3
	return Color3.new(c.R * f, c.G * f, c.B * f)
end

-- Karten-Daten: aus dem Snapshot (choices), sonst aus der replizierten Konfiguration
local function choices(): { any }
	if type(latest) == "table" and type(latest.choices) == "table" and #latest.choices > 0 then
		return latest.choices
	end
	local out = {}
	for _, typ in ipairs(START and START.Order or {}) do
		local p = START.Paths[typ]
		if p then
			table.insert(out, {
				id = typ, name = p.name, short = p.short, desc = p.desc, first = p.first, bonus = p.bonus, color = p.color,
				icon = p.icon or typ, chapter = p.chapter or "",
			})
		end
	end
	return out
end

---------------------------------------------------------------- Symbole (nur Frames, keine Bilder)
local function shape(parent: Instance, name: string, x: number, y: number, w: number, h: number, c: Color3, round: number?, rot: number?): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = c
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset(x, y)
	f.Size = UDim2.fromOffset(w, h)
	f.Rotation = rot or 0
	f.Active = false
	if round and round > 0 then
		local k = Instance.new("UICorner")
		k.CornerRadius = round >= 99 and UDim.new(1, 0) or UDim.new(0, round)
		k.Parent = f
	end
	f.Parent = parent
	return f
end

-- Zeichnet das Symbol eines Wegs in eine 72×72-Fläche (Mittelpunkt 36/36)
local DRAW = {}
function DRAW.wrench(box: Frame, c: Color3)
	local steel = Color3.fromRGB(214, 220, 228)
	shape(box, "Handle", 32, 40, 12, 46, steel, 6, 45)
	local head = shape(box, "Head", 50, 22, 26, 26, steel, 99, 0)
	shape(head, "Jaw", 13, 6, 10, 14, darker(c, 0.55), 2, 45)
	shape(box, "Grip", 21, 51, 10, 16, c, 4, 45)
end
function DRAW.car(box: Frame, c: Color3)
	shape(box, "Cabin", 34, 30, 30, 14, darker(c, 0.85), 6)
	shape(box, "Window", 34, 30, 22, 8, Color3.fromRGB(170, 210, 235), 3)
	shape(box, "Body", 34, 41, 52, 15, c, 6)
	shape(box, "WheelL", 21, 49, 13, 13, Color3.fromRGB(32, 34, 38), 99)
	shape(box, "WheelR", 47, 49, 13, 13, Color3.fromRGB(32, 34, 38), 99)
	local tag = shape(box, "PriceTag", 56, 18, 22, 14, Color3.fromRGB(235, 184, 72), 3, 20)
	local l = Instance.new("TextLabel")
	l.Name = "Cr"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 9
	l.Text = "Cr"
	l.TextColor3 = Color3.fromRGB(40, 32, 12)
	l.Parent = tag
end
function DRAW.factory(box: Frame, c: Color3)
	shape(box, "Chimney", 54, 26, 9, 30, darker(c, 0.6), 2)
	shape(box, "Smoke1", 57, 9, 10, 10, Color3.fromRGB(200, 204, 210), 99)
	shape(box, "Smoke2", 63, 4, 7, 7, Color3.fromRGB(170, 174, 180), 99)
	shape(box, "Hall", 34, 46, 50, 22, c, 3)
	for i = 0, 2 do
		shape(box, "Roof" .. (i + 1), 17 + i * 15, 33, 11, 11, darker(c, 0.8), 1, 45)
	end
	shape(box, "Door", 34, 51, 10, 12, darker(c, 0.5), 2)
	shape(box, "Gear", 20, 46, 8, 8, Color3.fromRGB(235, 238, 242), 99)
end
function DRAW.scrap(box: Frame, c: Color3)
	shape(box, "Plate1", 26, 48, 34, 10, Color3.fromRGB(140, 146, 154), 2, -12)
	shape(box, "Plate2", 44, 44, 30, 10, darker(c, 0.85), 2, 18)
	shape(box, "Plate3", 33, 37, 26, 9, Color3.fromRGB(176, 120, 72), 2, -4)
	local tire = shape(box, "Tire", 50, 26, 22, 22, Color3.fromRGB(32, 34, 38), 99)
	shape(tire, "Rim", 11, 11, 10, 10, Color3.fromRGB(190, 196, 204), 99)
	shape(box, "Spring", 20, 25, 6, 16, Color3.fromRGB(214, 220, 228), 3, 30)
end

local function buildIcon(parent: Instance, kind: any, c: Color3): Frame
	local box = Instance.new("Frame")
	box.Name = "Icon"
	box.BorderSizePixel = 0
	box.BackgroundColor3 = darker(c, 0.32)
	box.Size = UDim2.fromOffset(StartUI.IconSize, StartUI.IconSize)
	box.LayoutOrder = 1
	box.ClipsDescendants = true
	box.Active = false
	local k = Instance.new("UICorner")
	k.CornerRadius = UDim.new(0, 14)
	k.Parent = box
	box:SetAttribute("Icon", tostring(kind))
	box.Parent = parent
	local fn = DRAW[kind] or DRAW.wrench
	local ok, err = pcall(fn, box, c)
	if not ok then
		warn("[Startwahl] Symbol: " .. tostring(err))
	end
	return box
end
StartUI.BuildIcon = buildIcon

---------------------------------------------------------------- Absichten
function StartUI.Choose(typ: string): boolean
	if not Remote or type(typ) ~= "string" or pendingPath ~= nil then
		return false
	end
	pendingPath = typ
	sentAt = os.clock()
	Remote.Send("start_choose", { path = typ })
	StartUI.Render()
	-- kommt keine Antwort (Verbindung, abgelehnt), werden die Karten wieder frei
	pcall(function()
		task.delay(StartUI.WaitSeconds + 0.1, function()
			StartUI.Render()
		end)
	end)
	return true
end

---------------------------------------------------------------- Aufbau
local function buildCard(parent: Instance, c: any, order: number)
	local item = { id = c.id }
	local col = color(c.color)
	local button = UI.Button(parent, "", T.card, function()
		StartUI.Choose(item.id)
	end, {
		Name = "Choice_" .. tostring(c.id), LayoutOrder = order, Text = "",
		Size = UDim2.new(1, 0, 0, StartUI.CardMinHeight), AutomaticSize = Enum.AutomaticSize.Y, -- Mindesthöhe, wächst mit dem Text
	})
	item.root = button
	local stripe = UI.Frame(button, {
		Name = "Stripe", BackgroundColor3 = col, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(0, 8, 1, 0), Position = UDim2.new(0, 0, 0, 0),
	})
	UI.Corner(stripe, 4)
	item.stripe = stripe
	local inner = UI.Frame(button, { Name = "Inner", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), Position = UDim2.new(0, 8, 0, 0) })
	UI.Padding(inner, 14, 12)
	UI.List(inner, 6)
	-- Kopf: Symbol links, Name und Kurzzeile rechts
	local head = UI.Frame(inner, {
		Name = "Head", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y, -- mindestens Symbolhöhe
		Size = UDim2.new(1, 0, 0, StartUI.IconSize), LayoutOrder = 1,
	})
	local row = UI.List(head, 12, true)
	row.VerticalAlignment = Enum.VerticalAlignment.Center
	item.icon = buildIcon(head, c.icon or c.id, col)
	local names = UI.Frame(head, {
		Name = "Names", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.Y,
		Size = UDim2.new(1, -(StartUI.IconSize + 12), 0, 0), LayoutOrder = 2,
	})
	UI.List(names, 2)
	item.title = UI.Label(names, c.name or c.id, { Name = "Title", Font = UI.FontBig, TextSize = 24, LayoutOrder = 1, TextColor3 = col })
	item.short = UI.Label(names, c.short or "", { Name = "Short", Font = UI.FontBold, TextSize = 16, LayoutOrder = 2 })
	item.desc = UI.Label(inner, c.desc or "", { Name = "Desc", TextSize = 15, LayoutOrder = 3, TextColor3 = T.muted })
	item.chapter = UI.Label(inner, c.chapter or "", { Name = "Chapter", Font = UI.FontBold, TextSize = 15, LayoutOrder = 4, TextColor3 = T.text })
	item.bonus = UI.Label(inner, c.bonus or "", { Name = "Bonus", Font = UI.FontBold, TextSize = 15, LayoutOrder = 5, TextColor3 = T.yellow })
	local pill = UI.Frame(inner, {
		Name = "Pick", BackgroundColor3 = col, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, UI.MinTouch), LayoutOrder = 6,
	})
	UI.Corner(pill, 8)
	item.pick = UI.Label(pill, texts().choose or "Das wähle ich!", {
		Name = "Text", Font = UI.FontBold, TextSize = 17, Size = UDim2.new(1, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.None,
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
	})
	item.pill = pill
	return item
end

local function placeCards()
	if not gui or not refs.panel then
		return
	end
	local size = gui.AbsoluteSize
	local w = size.X > 0 and size.X or 1280
	local h = size.Y > 0 and size.Y or 720
	local width = math.max(200, math.min(StartUI.MaxWidth, w - 2 * StartUI.Margin))
	local height = math.max(200, h - 2 * StartUI.Margin)
	refs.panel.Size = UDim2.new(0, width, 0, height)
	local want = w >= StartUI.TwoColumnsFrom and 2 or 1
	if want == columns then
		return
	end
	columns = want
	refs.colA.Size = want == 2 and UDim2.new(0.5, -6, 0, 0) or UDim2.new(1, 0, 0, 0)
	refs.colB.Visible = want == 2
	for i, item in ipairs(refs.cards) do
		item.root.Parent = (want == 2 and i % 2 == 0) and refs.colB or refs.colA
		item.root.LayoutOrder = i
	end
end

function StartUI.Build(_page: any, context: any)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	if gui then
		return
	end
	local pg = playerGui()
	if not pg then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "StartChoice"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = StartUI.DisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = pg

	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.BackgroundColor3 = Color3.new(0, 0, 0)
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.Active = true
	backdrop.Parent = gui
	refs.backdrop = backdrop

	local panel = Instance.new("ScrollingFrame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.new(0, StartUI.MaxWidth, 0, 600)
	panel.BackgroundColor3 = T.panel
	panel.BorderSizePixel = 0
	panel.ScrollBarThickness = 6
	panel.ScrollingDirection = Enum.ScrollingDirection.Y
	panel.CanvasSize = UDim2.new(0, 0, 0, 0)
	panel.AutomaticCanvasSize = Enum.AutomaticSize.Y
	panel.Active = true
	panel.Parent = gui
	UI.Corner(panel, 14)
	UI.Padding(panel, 18, 16)
	UI.List(panel, 10)
	refs.panel = panel

	refs.title = UI.Label(panel, START.Title or "Wie willst du starten?", { Name = "Title", Font = UI.FontBig, TextSize = 28, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center })
	refs.intro = UI.Label(panel, START.Intro or "", { Name = "Intro", TextSize = 16, LayoutOrder = 2, TextColor3 = T.muted, TextXAlignment = Enum.TextXAlignment.Center })

	local grid = UI.Frame(panel, { Name = "Cards", BackgroundTransparency = 1, LayoutOrder = 3 })
	refs.grid = grid
	local row = UI.List(grid, 12, true)
	row.VerticalAlignment = Enum.VerticalAlignment.Top
	refs.colA = UI.Frame(grid, { Name = "ColumnA", BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0), LayoutOrder = 1 })
	UI.List(refs.colA, 12)
	refs.colB = UI.Frame(grid, { Name = "ColumnB", BackgroundTransparency = 1, Size = UDim2.new(0.5, -6, 0, 0), LayoutOrder = 2, Visible = false })
	UI.List(refs.colB, 12)
	for i, c in ipairs(choices()) do
		table.insert(refs.cards, buildCard(refs.colA, c, i))
	end

	refs.status = UI.Label(panel, "", { Name = "Status", Font = UI.FontBold, TextSize = 16, LayoutOrder = 4, TextXAlignment = Enum.TextXAlignment.Center, Visible = false })

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCards)
	placeCards()
end

function StartUI.Start(context: any)
	StartUI.Build(nil, context)
end

---------------------------------------------------------------- Anzeige
local function wanted(): boolean
	if type(latest) ~= "table" or latest.pending ~= true then
		return false
	end
	if mode ~= nil and mode ~= "openworld" then
		return false
	end
	-- 2.4.0-Dialog (QTE/Diagnose), Tablet oder Minispiel-Panel offen: ausblenden, bis alles zu ist (RefreshOverlays ruft Render)
	if ctx and type(ctx.IsGarageBusy) == "function" then
		local ok, busy = pcall(ctx.IsGarageBusy)
		if ok and busy == true then
			return false
		end
	end
	return true
end

function StartUI.Render()
	if not gui then
		return
	end
	if pendingPath and os.clock() - sentAt > StartUI.WaitSeconds then
		pendingPath = nil -- keine Antwort: wieder frei
	end
	local show = wanted()
	gui.Enabled = show
	if not show then
		return
	end
	-- Texte aus dem Snapshot nachziehen (Server ist die Quelle)
	local byId = {}
	for _, c in ipairs(choices()) do
		byId[c.id] = c
	end
	for _, item in ipairs(refs.cards) do
		local c = byId[item.id]
		if c then
			item.title.Text = c.name or item.id
			item.short.Text = c.short or ""
			item.desc.Text = c.desc or ""
			item.chapter.Text = c.chapter or ""
			item.chapter.Visible = item.chapter.Text ~= ""
			item.bonus.Text = c.bonus or ""
		end
		local chosen = pendingPath == item.id
		item.pick.Text = chosen and (texts().waiting or "Einen Moment …") or (texts().choose or "Das wähle ich!")
		UI.SetEnabled(item.root, pendingPath == nil, T.card)
	end
end

function StartUI.OnSnapshot(s: any)
	if type(s) ~= "table" then
		return
	end
	mode = type(s.mode) == "string" and s.mode or nil
	if type(s.start) == "table" then
		latest = s.start
		if latest.pending ~= true then
			pendingPath = nil
		end
	end
	StartUI.Render()
end

function StartUI.OnNotice(data: any)
	if type(data) ~= "table" or data.kind ~= "start" then
		return
	end
	if data.event == "offer" then
		latest = type(latest) == "table" and latest or {}
		latest.pending = true
		if type(data.choices) == "table" then
			latest.choices = data.choices
		end
	elseif data.event == "chosen" then
		latest = type(latest) == "table" and latest or {}
		latest.pending = false
		latest.path = data.path
		pendingPath = nil
	elseif data.event == "reset" then
		pendingPath = nil -- Entwickler-Menü: Wahl wieder offen (das Angebot bzw. der Snapshot zeigt die Karten)
	end
	StartUI.Render()
end

-- Startwahl zeigen, solange sie offen ist (Handy-App „Einstellungen“ ruft das noch auf; die Wahl steht ohnehin immer,
-- solange sie offen ist). Rückgabe: true, wenn die Karte jetzt zu sehen ist.
function StartUI.Reopen(): boolean
	if type(latest) ~= "table" or latest.pending ~= true then
		return false
	end
	StartUI.Render()
	return StartUI.IsOpen()
end

---------------------------------------------------------------- Zugriff (Tests, MiniClient)
function StartUI.IsOpen(): boolean
	return gui ~= nil and gui.Enabled == true
end

function StartUI.Gui(): ScreenGui?
	return gui
end

function StartUI.Card(typ: string): GuiObject?
	for _, item in ipairs(refs.cards) do
		if item.id == typ then
			return item.root
		end
	end
	return nil
end

return StartUI
