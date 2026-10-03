-- StartUI: Startwahl in der Open World (wie im Tycoon) auf dem Client. Kein Tab: MiniClient ruft StartUI.Start(ctx),
-- OnSnapshot(s) und OnNotice(data) (kind = "start"). Der Client zeigt nur an und sendet die Absicht
-- start_choose {path}; was der Weg bewirkt (Gebäude, Tutorial, Story), entscheidet der Server (StartService).
--
-- Eigene ScreenGui "StartChoice" (DisplayOrder 40: über HUD (20), Tutorial/Karten (16–19) und Minispiel-Panel (30);
-- solange ein 2.4.0-Dialog (QTE/Diagnose), das Tablet oder das Minispiel-Panel offen ist, bleibt sie aus – ctx.IsGarageBusy),
-- IgnoreGuiInset = true: ein dunkler Hintergrund über dem ganzen Bildschirm (Active, schluckt Klicks – solange die Wahl
-- offen ist, soll nichts darunter reagieren) und in der Mitte eine scrollbare Tafel:
--   Titel, Einleitung, vier große Karten (Name, kurze Beschreibung, was du zuerst machst, welchen Bonus du bekommst,
--   „Das wähle ich!“) im Stil der Tycoon-Karten, darunter „Später entscheiden“.
-- Breite ≥ 700 px: zwei Spalten, sonst eine (Handy). Touch-Flächen ≥ 44 px, Schrift ≥ 14 px; die Tafel passt sich bei
-- jeder Größenänderung an (16 px Rand, nie breiter als 760 px).
-- Sichtbar, solange snapshot.start.pending = true und der Modus die Open World ist (oder kein Modus bekannt ist).
-- „Später entscheiden“ blendet die Wahl aus, bis der Spieler das nächste Mal in der Spielermeile ankommt (neue Figur
-- oder Moduswechsel: der Server schickt dann wieder mini_notice start/offer) oder sie im Handy unter „Einstellungen“
-- → „Startweg wählen“ öffnet (StartUI.Reopen). Der Server wartet mit dem Tutorial, bis gewählt ist; abgerechnete
-- Aufträge machen die Wahl nicht hinfällig (meta.startOffered). Nach dem Tippen auf eine Karte warten die Karten auf den Server; kommt nach
-- WaitSeconds keine Antwort, sind sie wieder frei.
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

local START = GameConfig.Start
local UI, Remote, T, ctx
local gui, refs = nil, { cards = {} }
local latest = nil -- letztes Snapshot-Feld start
local mode = nil -- letzter Modus aus dem Snapshot
local pendingPath = nil -- gewählter Weg, bis der Server antwortet
local sentAt = 0
local dismissed = false -- „Später entscheiden“ (bis zum nächsten Betreten der Open World)
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

-- Karten-Daten: aus dem Snapshot (choices), sonst aus der replizierten Konfiguration
local function choices(): { any }
	if type(latest) == "table" and type(latest.choices) == "table" and #latest.choices > 0 then
		return latest.choices
	end
	local out = {}
	for _, typ in ipairs(START and START.Order or {}) do
		local p = START.Paths[typ]
		if p then
			table.insert(out, { id = typ, name = p.name, short = p.short, desc = p.desc, first = p.first, bonus = p.bonus, color = p.color })
		end
	end
	return out
end

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

function StartUI.Later()
	dismissed = true
	pendingPath = nil
	if ctx and ctx.Toast and texts().laterHint then
		pcall(ctx.Toast, texts().laterHint)
	end
	StartUI.Render()
end

---------------------------------------------------------------- Aufbau
local function buildCard(parent: Instance, c: any, order: number)
	local item = { id = c.id }
	local button = UI.Button(parent, "", T.card, function()
		StartUI.Choose(item.id)
	end, {
		Name = "Choice_" .. tostring(c.id), LayoutOrder = order, Text = "",
		Size = UDim2.new(1, 0, 0, StartUI.CardMinHeight), AutomaticSize = Enum.AutomaticSize.Y, -- Mindesthöhe, wächst mit dem Text
	})
	item.root = button
	local stripe = UI.Frame(button, {
		Name = "Stripe", BackgroundColor3 = color(c.color), AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(0, 8, 1, 0), Position = UDim2.new(0, 0, 0, 0),
	})
	UI.Corner(stripe, 4)
	item.stripe = stripe
	local inner = UI.Frame(button, { Name = "Inner", BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 0), Position = UDim2.new(0, 8, 0, 0) })
	UI.Padding(inner, 14, 12)
	UI.List(inner, 6)
	item.title = UI.Label(inner, c.name or c.id, { Name = "Title", Font = UI.FontBig, TextSize = 24, LayoutOrder = 1, TextColor3 = color(c.color) })
	item.short = UI.Label(inner, c.short or "", { Name = "Short", Font = UI.FontBold, TextSize = 16, LayoutOrder = 2 })
	item.desc = UI.Label(inner, c.desc or "", { Name = "Desc", TextSize = 15, LayoutOrder = 3, TextColor3 = T.muted })
	item.first = UI.Label(inner, c.first or "", { Name = "First", TextSize = 15, LayoutOrder = 4 })
	item.bonus = UI.Label(inner, c.bonus or "", { Name = "Bonus", Font = UI.FontBold, TextSize = 15, LayoutOrder = 5, TextColor3 = T.yellow })
	local pill = UI.Frame(inner, {
		Name = "Pick", BackgroundColor3 = color(c.color), AutomaticSize = Enum.AutomaticSize.None,
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
	refs.later = UI.Button(panel, texts().later or "Später entscheiden", T.line, StartUI.Later, {
		Name = "Later", LayoutOrder = 5, Size = UDim2.new(1, 0, 0, UI.MinTouch),
	})

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCards)
	placeCards()
end

function StartUI.Start(context: any)
	StartUI.Build(nil, context)
end

---------------------------------------------------------------- Anzeige
local function wanted(): boolean
	if dismissed or type(latest) ~= "table" or latest.pending ~= true then
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
			item.first.Text = c.first or ""
			item.bonus.Text = c.bonus or ""
		end
		local chosen = pendingPath == item.id
		item.pick.Text = chosen and (texts().waiting or "Einen Moment …") or (texts().choose or "Das wähle ich!")
		UI.SetEnabled(item.root, pendingPath == nil, T.card)
	end
	refs.later.Visible = pendingPath == nil
end

function StartUI.OnSnapshot(s: any)
	if type(s) ~= "table" then
		return
	end
	local newMode = type(s.mode) == "string" and s.mode or nil
	if newMode ~= mode then
		if newMode ~= "openworld" then
			dismissed = false -- beim nächsten Betreten der Open World fragt die Karte wieder
		end
		mode = newMode
	end
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
		dismissed = false
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
	end
	StartUI.Render()
end

-- Startwahl wieder zeigen (Handy-App „Einstellungen“ → „Startweg wählen“), solange sie offen ist.
-- Rückgabe: true, wenn die Karte jetzt zu sehen ist.
function StartUI.Reopen(): boolean
	if type(latest) ~= "table" or latest.pending ~= true then
		return false
	end
	dismissed = false
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
