--!nonstrict
-- DevUI: Entwickler-Menü auf dem Client (ScreenGui "DevMenu", DisplayOrder 45). Kein Tab: MiniClient ruft
-- DevUI.Start(ctx) einmal auf; das Modul hört selbst am 2.4.0-Remote GarageShared.Remotes.Event auf
-- mini_notice { kind = "dev" } (event = "open" öffnet, "update" zeigt neue Werte) – MiniClient muss "dev" also NICHT
-- weiterleiten. Öffnen: Chat „/dev“ (der Server antwortet nur Entwicklern) oder Strg+Umschalt+D (sendet dev_open).
-- Der Client zeigt nur an und sendet Absichten dev_set { field, value }; ob der Spieler das darf und welche Werte
-- gelten (Deckel, ganze Zahlen), entscheidet allein der Server (DevService). Nicht-Entwickler bekommen keine Antwort,
-- das Menü bleibt für sie unsichtbar.
--
-- ctx (alle optional): Remote (MiniRemote; sonst wird es geladen), Toast(text), Listen = false (kein eigener Listener,
-- dann ruft der Aufrufer DevUI.OnNotice(data) selbst).
-- Aufbau: Kopfzeile (Titel, ×), Werte (Level, XP, Credits, Prestige-Rang, im Tycoon Bargeld), Zahlenfelder mit
-- „Level setzen“, „XP setzen“, „Credits setzen“, „+10.000 Credits“, „Bargeld setzen“ (nur im Tycoon),
-- „Startweg zurücksetzen“, „Schließen“. Breite ≤ 420 px (16 px Rand), Touch-Flächen 44 px, Inhalt scrollt bei
-- kleinen Bildschirmen.
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevUI = {}

DevUI.DisplayOrder = 45
DevUI.Width = 420
DevUI.MaxHeight = 600
DevUI.Margin = 16
DevUI.RowHeight = 44
DevUI.KeyCooldown = 0.5

local C = {
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
}
DevUI.Colors = C

local ctx: any = {}
local Remote: any = nil
local gui: any = nil
local refs: any = {}
local state: any = nil -- letzte Werte vom Server (mini_notice dev)
local isOpen = false
local requestedAt = -math.huge
local started = false

---------------------------------------------------------------- Hilfen
local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function fmt(n: any): string
	if not finite(n) then
		return "0"
	end
	local s = string.format("%d", math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return out
end
DevUI.Format = fmt

-- „10.000“, „10 000“, „1e6“ -> Zahl; nil, wenn es keine Zahl ist
function DevUI.Parse(text: any): number?
	if type(text) ~= "string" then
		return nil
	end
	local s = text:gsub("[%s%.']", ""):gsub(",", ".")
	if s == "" or #s > 24 then
		return nil
	end
	local n = tonumber(s)
	if not finite(n) then
		return nil
	end
	return math.floor(n)
end

local function new(cls: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(cls)
	for k, v in pairs(props) do
		inst[k] = v
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(parent: Instance, r: number)
	new("UICorner", { CornerRadius = UDim.new(0, r) }, parent)
end

local function toast(text: string)
	if ctx and type(ctx.Toast) == "function" then
		pcall(ctx.Toast, text)
	end
	if refs.status then
		refs.status.Text = text
	end
end

local function label(parent: Instance, name: string, text: string, order: number, props: { [string]: any }?): any
	local l = new("TextLabel", {
		Name = name, Text = text, BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 16,
		TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.new(1, 0, 0, 22), LayoutOrder = order, TextWrapped = true,
	}, parent)
	for k, v in pairs(props or {}) do
		l[k] = v
	end
	return l
end

local function button(parent: Instance, name: string, text: string, color: Color3, order: number, onClick: () -> ()): any
	local b = new("TextButton", {
		Name = name, Text = text, AutoButtonColor = true, BackgroundColor3 = color, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.text, Size = UDim2.new(1, 0, 0, DevUI.RowHeight),
		LayoutOrder = order, TextWrapped = true,
	}, parent)
	corner(b, 8)
	b.Activated:Connect(function()
		local ok, err = pcall(onClick)
		if not ok then
			warn("[Dev] " .. tostring(err))
		end
	end)
	return b
end

-- Zeile: Zahlenfeld links, Knopf rechts
local function inputRow(parent: Instance, key: string, buttonText: string, color: Color3, order: number, onClick: (number) -> ()): any
	local row = new("Frame", {
		Name = "Row_" .. key, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, DevUI.RowHeight), LayoutOrder = order,
	}, parent)
	local box = new("TextBox", {
		Name = key .. "Box", Text = "", PlaceholderText = "Zahl", ClearTextOnFocus = false, BackgroundColor3 = C.card,
		BorderSizePixel = 0, Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.text, PlaceholderColor3 = C.muted,
		Size = UDim2.new(0.42, -4, 1, 0), Position = UDim2.new(0, 0, 0, 0), TextXAlignment = Enum.TextXAlignment.Center,
	}, row)
	corner(box, 8)
	local b = new("TextButton", {
		Name = "Set" .. key, Text = buttonText, AutoButtonColor = true, BackgroundColor3 = color, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 16, TextColor3 = C.text, Size = UDim2.new(0.58, -4, 1, 0),
		Position = UDim2.new(0.42, 4, 0, 0), TextWrapped = true,
	}, row)
	corner(b, 8)
	b.Activated:Connect(function()
		local n = DevUI.Parse(box.Text)
		if n == nil then
			toast("Bitte eine ganze Zahl eingeben.")
			return
		end
		local ok, err = pcall(onClick, n)
		if not ok then
			warn("[Dev] " .. tostring(err))
		end
	end)
	return row, box, b
end

---------------------------------------------------------------- Absichten
local function sendSet(field: string, value: number): boolean
	if not Remote then
		return false
	end
	Remote.Send("dev_set", { field = field, value = value })
	return true
end
DevUI.SendSet = sendSet

-- Menü beim Server anfordern (Strg+Umschalt+D). Der Server antwortet nur Entwicklern.
function DevUI.Request(): boolean
	if not Remote then
		return false
	end
	local t = os.clock()
	if t - requestedAt < DevUI.KeyCooldown then
		return false
	end
	requestedAt = t
	Remote.Send("dev_open")
	return true
end

---------------------------------------------------------------- Anzeige
local function setBox(box: any, value: any)
	if not box or not finite(value) then
		return
	end
	local okF, focused = pcall(function()
		return box:IsFocused()
	end)
	if not (okF and focused == true) then
		box.Text = tostring(math.floor(value))
	end
end

function DevUI.Render()
	if not gui then
		return
	end
	gui.Enabled = isOpen
	local s = type(state) == "table" and state or {}
	local inTycoon = s.inTycoon == true
	refs.level.Text = "Level: " .. fmt(s.level) .. (finite(s.maxLevel) and ("  (max. " .. fmt(s.maxLevel) .. ")") or "")
	refs.xp.Text = "XP: " .. fmt(s.xp) .. " / " .. fmt(s.xpNeeded)
	refs.credits.Text = "Credits: " .. fmt(s.credits)
	local rankText = "Prestige-Rang: " .. fmt(s.rank)
	if type(s.rankTitle) == "string" and s.rankTitle ~= "" then
		rankText ..= " (" .. s.rankTitle .. ")"
	end
	refs.rank.Text = rankText
	refs.cash.Visible = inTycoon
	refs.cash.Text = s.hasRun and ("Bargeld: " .. fmt(s.cash)) or "Bargeld: kein Durchlauf aktiv"
	refs.cashRow.Visible = inTycoon
	refs.addCredits.Text = "+" .. fmt(finite(s.addCredits) and s.addCredits or 10000) .. " Credits"
	local path = type(s.startPath) == "string" and s.startPath ~= "" and s.startPath or (s.startPending and "offen" or "–")
	refs.start.Text = "Startweg: " .. path .. "   ·   Modus: " .. tostring(s.mode or "–")
end

local function fillBoxes()
	local s = type(state) == "table" and state or {}
	setBox(refs.levelBox, s.level)
	setBox(refs.xpBox, s.xp)
	setBox(refs.creditsBox, s.credits)
	setBox(refs.cashBox, s.cash)
end

local function layout()
	if not gui or not refs.panel then
		return
	end
	local size = gui.AbsoluteSize
	local vw = size.X > 0 and size.X or 1280
	local vh = size.Y > 0 and size.Y or 720
	local w = math.max(200, math.min(DevUI.Width, vw - 2 * DevUI.Margin))
	local h = math.max(200, math.min(DevUI.MaxHeight, vh - 2 * DevUI.Margin))
	refs.panel.Size = UDim2.fromOffset(w, h)
end
DevUI.Layout = layout

function DevUI.IsOpen(): boolean
	return isOpen
end

function DevUI.Show()
	isOpen = true
	layout()
	fillBoxes()
	DevUI.Render()
end

function DevUI.Close()
	isOpen = false
	DevUI.Render()
end

-- mini_notice { kind = "dev", event = "open" | "update", level, xp, xpNeeded, credits, rank, rankTitle, inTycoon, hasRun, cash, … }
function DevUI.OnNotice(data: any)
	if type(data) ~= "table" or data.kind ~= "dev" then
		return
	end
	state = data
	if data.event == "open" then
		DevUI.Show()
	else
		fillBoxes()
		DevUI.Render()
	end
end

function DevUI.State(): any
	return state
end

---------------------------------------------------------------- Aufbau
local function build()
	local player = Players.LocalPlayer
	local pg = player and player:FindFirstChild("PlayerGui")
	if not pg then
		return
	end
	local old = pg:FindFirstChild("DevMenu")
	if old then
		old:Destroy()
	end
	gui = new("ScreenGui", {
		Name = "DevMenu", DisplayOrder = DevUI.DisplayOrder, ResetOnSpawn = false, IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling, Enabled = false,
	}, pg)
	local panel = new("Frame", {
		Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(DevUI.Width, DevUI.MaxHeight), BackgroundColor3 = C.panel, BorderSizePixel = 0, Active = true,
	}, gui)
	corner(panel, 12)
	new("UIStroke", { Color = C.purple, Thickness = 2 }, panel)
	refs.panel = panel

	local head = new("Frame", { Name = "Head", BackgroundColor3 = C.purple, BorderSizePixel = 0, Size = UDim2.new(1, 0, 0, 48) }, panel)
	corner(head, 12)
	new("TextLabel", {
		Name = "Title", Text = "Entwickler-Menü", BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 20,
		TextColor3 = C.text, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.new(1, -64, 1, 0), Position = UDim2.fromOffset(14, 0),
	}, head)
	local x = new("TextButton", {
		Name = "CloseX", Text = "×", AutoButtonColor = true, BackgroundColor3 = C.red, BorderSizePixel = 0,
		Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = C.text, Size = UDim2.fromOffset(44, 44),
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 2),
	}, head)
	corner(x, 8)
	x.Activated:Connect(DevUI.Close)

	local body = new("ScrollingFrame", {
		Name = "Body", BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 52),
		Size = UDim2.new(1, 0, 1, -52), CanvasSize = UDim2.new(0, 0, 0, 0), AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	new("UIPadding", {
		PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12), PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 12),
	}, body)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder, FillDirection = Enum.FillDirection.Vertical }, body)
	refs.body = body

	refs.level = label(body, "Info_Level", "Level: –", 1, { Font = Enum.Font.GothamBold })
	refs.xp = label(body, "Info_XP", "XP: –", 2)
	refs.credits = label(body, "Info_Credits", "Credits: –", 3)
	refs.rank = label(body, "Info_Rank", "Prestige-Rang: –", 4)
	refs.cash = label(body, "Info_Cash", "Bargeld: –", 5, { TextColor3 = C.yellow, Visible = false })
	refs.start = label(body, "Info_Start", "Startweg: –", 6, { TextColor3 = C.muted, TextSize = 14 })

	local _, levelBox = inputRow(body, "Level", "Level setzen", C.blue, 10, function(n)
		sendSet("level", n)
	end)
	refs.levelBox = levelBox
	local _, xpBox = inputRow(body, "XP", "XP setzen", C.blue, 11, function(n)
		sendSet("xp", n)
	end)
	refs.xpBox = xpBox
	local _, creditsBox = inputRow(body, "Credits", "Credits setzen", C.green, 12, function(n)
		sendSet("credits", n)
	end)
	refs.creditsBox = creditsBox
	refs.addCredits = button(body, "AddCredits", "+10.000 Credits", C.green, 13, function()
		local s = type(state) == "table" and state or {}
		sendSet("credits_add", finite(s.addCredits) and s.addCredits or 10000)
	end)
	local cashRow, cashBox = inputRow(body, "Cash", "Bargeld setzen", C.yellow, 14, function(n)
		sendSet("cash", n)
	end)
	cashRow.Visible = false
	refs.cashRow = cashRow
	refs.cashBox = cashBox
	refs.resetStart = button(body, "ResetStart", "Startweg zurücksetzen", C.card, 15, function()
		sendSet("start_reset", 0)
	end)
	refs.close = button(body, "Close", "Schließen", C.red, 16, DevUI.Close)
	refs.status = label(body, "Status", "Alle Änderungen prüft der Server.", 17, { TextColor3 = C.muted, TextSize = 14, Size = UDim2.new(1, 0, 0, 36) })

	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
	DevUI.Render()
end

---------------------------------------------------------------- Eingabe
local function ctrlShift(): boolean
	local ctrl = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
	local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift) or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
	return ctrl and shift
end

local function onInput(input: any, processed: boolean)
	if processed or input.KeyCode ~= Enum.KeyCode.D or not ctrlShift() then
		return
	end
	if isOpen then
		DevUI.Close()
	else
		DevUI.Request()
	end
end
DevUI._OnInput = onInput

---------------------------------------------------------------- Start
function DevUI.Start(c: any)
	if started then
		return
	end
	started = true
	ctx = type(c) == "table" and c or {}
	Remote = ctx.Remote
	if not Remote then
		local ok, mod = pcall(function()
			return require(script.Parent:WaitForChild("MiniRemote", 10))
		end)
		Remote = ok and mod or nil
	end
	build()
	UserInputService.InputBegan:Connect(onInput)
	if ctx.Listen ~= false then
		local ok, err = pcall(function()
			local event = ReplicatedStorage:WaitForChild("GarageShared"):WaitForChild("Remotes"):WaitForChild("Event")
			event.OnClientEvent:Connect(function(kind, value)
				if kind == "mini_notice" and type(value) == "table" and value.kind == "dev" then
					DevUI.OnNotice(value)
				end
			end)
		end)
		if not ok then
			warn("[Dev] Listener: " .. tostring(err))
		end
	end
end

function DevUI.Gui(): any
	return gui
end

return DevUI
