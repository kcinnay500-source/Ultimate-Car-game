-- UnlocksUI: Tab „Freischaltungen“ (docs/PHASE4_CONTRACT.md §6): oben die nächste Freischaltung, darunter die
-- Tabelle Level -> Freischaltung; erreichte Zeilen sind hervorgehoben, offene gedämpft. Dazu die Karte
-- „Neu freigeschaltet“ (mini_notice { kind = "unlock" }) oben rechts unter dem Fortschritts-Abzeichen, mit
-- kurzem Effekt und – im Beginner-Modus – dem Hinweistext des Servers (Feld hint).
-- Die Tabelle kommt aus dem Snapshot (unlocks.list, nur bei vollen Snapshots); fehlt sie, rechnet der Client sie
-- aus der replizierten GameConfig.Unlocks und s.level selbst nach (Unlocks.ListFor). Absicht: unlocks_seen beim
-- Öffnen des Tabs, wenn es neue Einträge gibt.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local Unlocks = require(Mini:WaitForChild("Unlocks"))

local UnlocksUI = {}

UnlocksUI.CardWidth = 300
UnlocksUI.CardTop = 8 + 56 + 8 -- unter dem ProgressHUD-Abzeichen (y 8, 56 hoch)
UnlocksUI.CardSeconds = 6
UnlocksUI.CardDisplayOrder = 21 -- über dem 2.4.0-HUD, unter dem Minispiel-Panel (30)

local KIND_NAMES = {
	feature = "Bereich",
	car = "Auto",
	building = "Gebäude",
	story = "Story",
	mode = "Modus",
}

local UI, Remote, T, ctx
local refs = {}
local card = {} -- gui, frame, title, text
local lastList = nil
local lastLevel = nil
local sentSeenFor = nil
local showPending = false
local cardSerial = 0

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v or default
end

---------------------------------------------------------------- Zeile der Tabelle
local function row(parent, i: number)
	local root = UI.Frame(parent, { Name = "Unlock_" .. i, LayoutOrder = 10 + i, BackgroundColor3 = T.card })
	UI.Corner(root, 8)
	UI.Padding(root, 12, 8)
	local level = UI.Label(root, "", {
		Name = "Level", Font = UI.FontBold, TextSize = 15, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(0, 64, 0, 22), TextWrapped = false,
	})
	local right = UI.Frame(root, { BackgroundTransparency = 1, Position = UDim2.new(0, 72, 0, 0), Size = UDim2.new(1, -72, 0, 0) })
	UI.List(right, 2)
	local title = UI.Label(right, "", { Name = "Title", Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
	local hint = UI.Small(right, "", 2)
	hint.Name = "Hint"
	return { root = root, level = level, title = title, hint = hint }
end

---------------------------------------------------------------- Karte „Neu freigeschaltet“
local function buildCard()
	if card.gui and card.gui.Parent then
		return -- schon gebaut (zweites Build bindet nur den Kontext neu)
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "UnlockCards"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = UnlocksUI.CardDisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui
	card.gui = gui
	local frame = UI.Frame(gui, {
		Name = "UnlockCard", BackgroundColor3 = T.panel, AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, UnlocksUI.CardTop),
		Size = UDim2.new(0, UnlocksUI.CardWidth, 0, 0), Visible = false,
	})
	UI.Corner(frame, 10)
	UI.Padding(frame, 14, 10)
	UI.List(frame, 4)
	local stripe = UI.Frame(frame, { BackgroundColor3 = T.green, Size = UDim2.new(1, 0, 0, 3), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 0 })
	UI.Corner(stripe, 2)
	card.stripe = stripe
	card.frame = frame
	card.title = UI.Label(frame, "", { Name = "Title", Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	card.text = UI.Label(frame, "", { Name = "Text", TextSize = 14, TextColor3 = T.muted, LayoutOrder = 2 })
	card.scale = Instance.new("UIScale")
	card.scale.Scale = 1
	card.scale.Parent = frame
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		local w = gui.AbsoluteSize.X
		if w > 0 then
			frame.Size = UDim2.new(0, math.min(UnlocksUI.CardWidth, w - 32), 0, 0)
		end
	end)
end

function UnlocksUI.ShowCard(title: string, text: string?, color: Color3?)
	if not card.frame then
		return
	end
	cardSerial += 1
	local serial = cardSerial
	card.title.Text = title
	card.text.Text = text or ""
	card.text.Visible = text ~= nil and text ~= ""
	card.stripe.BackgroundColor3 = color or T.green
	card.frame.Visible = true
	card.scale.Scale = 0.85
	TweenService:Create(card.scale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(UnlocksUI.CardSeconds, function()
		if serial == cardSerial and card.frame then
			card.frame.Visible = false
		end
	end)
end

function UnlocksUI.CardVisible(): boolean
	return card.frame ~= nil and card.frame.Visible == true
end

---------------------------------------------------------------- Tab
function UnlocksUI.Build(page, context)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme

	local nextCard = UI.Card(page, 1)
	UI.Title(nextCard, "Nächste Freischaltung", 1)
	refs.nextTitle = UI.Label(nextCard, "", { Name = "NextTitle", Font = UI.FontBold, TextSize = 18, LayoutOrder = 2 })
	refs.nextHint = UI.Small(nextCard, "", 3)
	refs.nextHint.Name = "NextHint"
	refs.nextLevel = UI.Small(nextCard, "", 4)
	refs.nextLevel.Name = "NextLevel"
	local _, fill = UI.Progress(nextCard, T.green, 5)
	refs.fill = fill

	local table_ = UI.Card(page, 2)
	UI.Title(table_, "Level → Freischaltung", 1)
	refs.info = UI.Small(table_, "", 2)
	refs.rows = UI.Pool(table_, row)

	local ok, err = pcall(buildCard)
	if not ok then
		warn("[Freischaltungen] Karte: " .. tostring(err))
	end
end

local function listFor(s): { any }
	local u = type(s.unlocks) == "table" and s.unlocks or nil
	local list = u and u.list
	if type(list) == "table" and #list > 0 then
		lastList, lastLevel = list, s.level
		return list
	end
	if lastList and lastLevel == s.level then
		return lastList
	end
	lastList, lastLevel = Unlocks.ListFor({ level = s.level }), s.level
	return lastList
end

function UnlocksUI.Render(s)
	if type(s) ~= "table" then
		return
	end
	local level = math.floor(num(s.level, 1))
	local u = type(s.unlocks) == "table" and s.unlocks or {}
	local nextU = u.next
	if type(nextU) ~= "table" then
		nextU = Unlocks.NextFor({ level = level })
	end
	if type(nextU) == "table" then
		refs.nextTitle.Text = tostring(nextU.title) .. " (Level " .. tostring(nextU.level) .. ")"
		refs.nextHint.Text = tostring(nextU.hint or "")
		local prev = 0
		for _, e in ipairs(listFor(s)) do
			if e.level <= level and e.level > prev then
				prev = e.level
			end
		end
		local span = math.max(1, num(nextU.level, level + 1) - prev)
		refs.nextLevel.Text = "Du bist Level " .. MiniLocale.Number(level) .. " – noch " .. MiniLocale.Number(math.max(0, num(nextU.level, level) - level)) .. " Level."
		UI.SetProgress(refs.fill, (level - prev) / span)
	else
		refs.nextTitle.Text = "Alles freigeschaltet!"
		refs.nextHint.Text = "Du hast jede Freischaltung erreicht. Jetzt zählt nur noch dein Prestige-Rang."
		refs.nextLevel.Text = "Level " .. MiniLocale.Number(level)
		UI.SetProgress(refs.fill, 1)
	end

	local list = listFor(s)
	local reached = 0
	refs.rows:Ensure(#list)
	for i, e in ipairs(list) do
		local item = refs.rows.items[i]
		local isReached = e.reached == true or level >= num(e.level, math.huge)
		if isReached then
			reached += 1
		end
		item.level.Text = "Lv " .. tostring(e.level)
		item.level.TextColor3 = isReached and T.green or T.muted
		item.title.Text = tostring(e.title) .. (isReached and " ✓" or "") .. (e.special and " · Sondermodell" or "")
		item.title.TextColor3 = isReached and T.text or T.muted
		item.hint.Text = (KIND_NAMES[e.kind] and (KIND_NAMES[e.kind] .. ": ") or "") .. tostring(e.hint or "")
		item.root.BackgroundColor3 = isReached and T.card or T.panel
	end
	local unseen = num(u.unseen, 0)
	refs.info.Text = tostring(reached) .. " von " .. tostring(#list) .. " erreicht" .. (unseen > 0 and (" · " .. tostring(unseen) .. " neu") or "")
	if showPending then
		showPending = false
		if unseen > 0 and sentSeenFor ~= level then
			sentSeenFor = level
			Remote.Send("unlocks_seen")
		end
	end
end

-- Tab geöffnet (MiniClient ruft OnShow, gleich danach Render): neue Einträge als gesehen melden, einmal je Level-Stand
function UnlocksUI.OnShow()
	showPending = true
end

-- mini_notice { kind = "unlock", key, title, level, kind, tab, hint? }
function UnlocksUI.OnNotice(data)
	if type(data) ~= "table" or data.kind ~= "unlock" then
		return
	end
	local title = "Neu freigeschaltet: " .. tostring(data.title or data.key)
	local text = type(data.hint) == "string" and data.hint or ("Ab jetzt verfügbar (Level " .. tostring(data.level) .. ").")
	UnlocksUI.ShowCard(title, text, T.green)
	lastList = nil -- Tabelle beim nächsten Render neu übernehmen
end

function UnlocksUI.Card()
	return card.gui, card
end

return UnlocksUI
