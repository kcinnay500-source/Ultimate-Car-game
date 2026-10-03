-- MissionClient: Story und Missionen außerhalb des Panels (docs/PHASE4_CONTRACT.md §7). Kein Tab: MiniClient ruft
-- MissionClient.Start(ctx), danach OnSnapshot(s) je Snapshot, OnNotice(data) je mini_notice und Step(dt) aus dem Heartbeat
-- (wie TutorialUI/TycoonClient). Der Client zeigt nur an; nichts hier ist spielrelevant, alles läuft in pcall.
--
-- Eigene ScreenGui "Missionen" (DisplayOrder 16: UNTER dem 2.4.0-UI (20) – Dialoge, QTE, Tablet und Fahrzeugknöpfe
-- bekommen immer den Klick; Rahmen nicht Active, nur Knöpfe schlucken Klicks; Karten nie über der 2.4.0-HUD-Leiste oder
-- den Fahrzeugknöpfen E/F/H (PrestigeUI.FreeRect)):
--   Marker        BillboardGuis am Ziel der aktiven Mission (aus der Missionsdefinition: Kiesplatz, Werkstatt-Empfang,
--                 Autohaus, Teststrecke, …; zone city: workspace.City.Stations.<key>, zone plot:
--                 PlayerWorkshops.Plot_<UserId>.Stations.<key>) und an Start/Ziel der Lieferroute (City.Missions.Delivery_<n>,
--                 Teile mit Attribut Role="start"/"end" oder Namen Start/Ziel): Startmarker, solange die heutige
--                 Nebenmission „Lieferung“ offen ist; Zielmarker der laufenden Lieferung (mini_notice story/delivery).
--                 AlwaysOnTop, leicht wippend, Entfernung in Studs.
--   MissionCard   „Mission geschafft!“ oben Mitte (unter der Toast-Zone) bei mini_notice { kind = "mission", done = true },
--                 Abholung (story/claimed, side_claimed) und Lieferung (gestartet/abgeliefert); kurzer Tween, Warteschlange.
--                 Auf schmalen Bildschirmen (Breite < CardWidth + HintWidth + Ränder, also Handy/Tablet) rückt sie unter die
--                 Karten oben rechts („Tipp“/„Neu freigeschaltet“ aus TutorialUI/UnlocksUI), solange die zu sehen sind.
--   ChapterCard   Kapitel-Intro (Titel + Erzähltext, „Los geht's!“) beim Kapitelwechsel im Snapshot und beim Story-Ende.
--   NPC           Kunden am Kiesplatz: Modelle/Parts mit Attribut Anim="npc_idle" unter City.Animated.Kiesplatz (worldgen:
--                 Kunde_1..3, Attribut Period) oder City.Districts.Kiesplatz wippen und drehen sich dezent (prozedural,
--                 Serverzeit, eigener Takt je Figur; nur bis 150 Studs von der Kamera). CityClient kennt die Art nicht und
--                 soll sie überspringen (wie conveyor/stamp), sonst meldet er sie einmal als unbekannt.
--   Tracker     3.x: Karte „Deine Mission“ (Frame "MissionTracker"), immer zu sehen, solange eine Story-Mission läuft
--                 (die Story startet nach der Startwahl von selbst): Kapitel, Missionstitel, Text mit dem Ort, Fortschritt,
--                 „Abholen“ (story_claim {id}) sobald erfüllt, sonst „Hinreisen“ (mini_travel {key}, Ziel aus
--                 StoryRules.TargetOf). Ist das nächste Kapitel noch gesperrt, nennt sie das Level. Lage: oben links neben
--                 der 2.4.0-Leiste (CompactProgress); ist dort zu wenig Platz (Handy), unter Toast-Zone und Karten oben rechts,
--                 nie in HUD-Leiste/Fahrzeugknöpfen (PrestigeUI.FreeRect). Niedrige Bildschirme: ohne Text.
-- Karten (Mission, Kapitel, Tracker) verschwinden, solange das Minispiel-Panel, das 2.4.0-Tablet, QTE/Diagnose
-- (ctx.IsBlocked) oder der Tacho (ScreenGui "Fahren") zu sehen sind; die Welt-Marker bleiben beim Fahren an (Lieferfahrt,
-- Ziel der Mission), nur Panel/Tablet/QTE schalten die ganze ScreenGui aus. Prüfung alle 0,2 s und sofort über
-- MissionClient.Refresh (MiniClient). Handy: Karten höchstens Bildschirmbreite − 24 px, Knöpfe 44 px.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local StoryRules = require(Mini:WaitForChild("StoryRules"))
local PrestigeUI -- Freiraum-Regeln der 2.4.0-Oberfläche (FreeRect); optional
pcall(function()
	PrestigeUI = require(script.Parent:WaitForChild("PrestigeUI", 5))
end)

local MissionClient = {}

MissionClient.DisplayOrder = 16 -- unter dem 2.4.0-UI (20)
MissionClient.CardWidth = 420
MissionClient.CardTop = 62 + 60 + 8 -- Mindestabstand: unter der Toast-Zone (Toast y 62, 60 hoch); tatsächlich UI.ToastTop()
MissionClient.HintWidth = 300 -- Breite der Karten oben rechts (TutorialUI.HintWidth / UnlocksUI), für die Schmal-Prüfung
MissionClient.CardSeconds = 4
MissionClient.ChapterSeconds = 15
MissionClient.QueueMax = 6
MissionClient.MarkerDistance = 600
MissionClient.NpcCull = 150
MissionClient.NpcBob = 0.12 -- Studs
MissionClient.NpcTurn = 0.3 -- rad
MissionClient.Kinds = { npc_idle = true }
MissionClient.TrackerWidth = 300 -- Karte „Deine Mission“ (3.x)
MissionClient.TrackerMinWidth = 220 -- schmaler wird sie oben links nicht (sonst rückt sie unter die Karten oben)
MissionClient.TrackerNear = 40 -- Studs: so nah am Ziel gibt es keinen „Hinreisen“-Knopf
MissionClient.TrackerTextLines = 3

-- Ziel je Missionsart (zone, Stationsschlüssel, Beschriftung, Schnellreise): eine Tabelle für Server und Client
-- (StoryRules.Targets / StoryRules.TargetOf; 3.x: zone "anchor" = Open-World-Gebäude am eigenen Grundstück)
local CITY, PLOT, ANCHOR = "city", "plot", "anchor"
MissionClient.Targets = StoryRules.Targets

local ctx, UI, T
local gui = nil
local markers = {} -- { gui, label, bounce, name }
local card = {} -- frame, title, text, scale
local chapter = {} -- frame, title, text, button, scale
local latest = nil
local lastChapter = nil
local cardQueue = {}
local cardShowing = false
local cardSerial, chapterSerial = 0, 0
local chapterPending = nil -- { title, text } wartet, bis Overlays erlaubt sind
local delivery = nil -- { route, until_ }
local tracker = {} -- frame, kicker, title, text, bar, fill, count, button, mode ("claim" | "travel" | nil), id, travel
local cardOn, chapterOn = false, false -- Karte bzw. Kapitel-Intro gerade „an“ (sichtbar, sobald Overlays erlaubt sind)
local stepTimer, cullTimer, npcSlow = 0, 0, 0
local npcs = setmetatable({}, { __mode = "k" }) -- [inst] = Datensatz
local npcList = {}
local warned = {}
local started = false
local heartbeat = nil

local function warnOnce(key: string, text: string)
	if not warned[key] then
		warned[key] = true
		warn("[Missionen] " .. text)
	end
end

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v or default
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.clock()
end

local function playerGui(): Instance?
	local player = Players.LocalPlayer
	return player and player:FindFirstChild("PlayerGui") or nil
end

local function story(s: any): any
	return type(s) == "table" and type(s.story) == "table" and s.story or {}
end

local function hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

---------------------------------------------------------------- Sichtbarkeit (wie TutorialUI)
local function driveHudVisible(): boolean
	local pg = playerGui()
	local drive = pg and pg:FindFirstChild("Fahren")
	return drive ~= nil and drive:IsA("LayerCollector") and drive.Enabled == true
end

-- Welt-Marker: aus bei Panel, Tablet und QTE/Diagnose – beim Fahren bleiben sie an (Lieferfahrt, Ziel der Mission)
local function markersAllowed(): boolean
	if UI and UI.IsOpen then
		return false
	end
	if ctx and ctx.IsTabletOpen and ctx.IsTabletOpen() == true then
		return false
	end
	if ctx and ctx.IsBlocked and ctx.IsBlocked() == true then
		return false
	end
	return true
end

-- Karten (Mission, Kapitel, Tracker): zusätzlich aus, solange der Tacho zu sehen ist
local function overlaysAllowed(): boolean
	return markersAllowed() and not driveHudVisible()
end

---------------------------------------------------------------- Aufbau
local function buildMarker(name: string, color: Color3)
	local bb = Instance.new("BillboardGui")
	bb.Name = name
	bb.Size = UDim2.fromOffset(200, 48)
	bb.StudsOffset = Vector3.new(0, 5, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = MissionClient.MarkerDistance
	bb.Enabled = false
	bb.Parent = gui
	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = UI.FontBold
	label.TextSize = 14
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.4
	label.TextWrapped = true
	label.Text = ""
	label.Parent = bb
	local m = { gui = bb, label = label, bounce = math.random() * 6, name = name }
	table.insert(markers, m)
	return m
end

-- Unterkante der sichtbaren Karten oben rechts (Tutorial „Tipp“/„Neu freigeschaltet“, UnlocksUI „Neu freigeschaltet“),
-- relativ zur eigenen ScreenGui; 0 ohne sichtbare Karte. AutomaticSize-Karten ohne gemessene Höhe zählen 80 px.
local RIGHT_CARDS = { { "Tutorial", "HintCard" }, { "Tutorial", "UnlockCard" }, { "UnlockCards", "UnlockCard" } }
local function rightCardsBottom(): number
	local pg = playerGui()
	if not pg or not gui then
		return 0
	end
	local bottom = 0
	local base = gui.AbsolutePosition.Y
	for _, pair in ipairs(RIGHT_CARDS) do
		local sg = pg:FindFirstChild(pair[1])
		local frame = sg and sg:IsA("LayerCollector") and sg.Enabled and sg:FindFirstChild(pair[2]) or nil
		if frame and frame:IsA("GuiObject") and frame.Visible then
			local h = frame.AbsoluteSize.Y > 0 and frame.AbsoluteSize.Y or 80
			bottom = math.max(bottom, frame.AbsolutePosition.Y - base + h)
		end
	end
	return bottom
end

-- Schmal: Karte in der Mitte (420) und Karte rechts (300) passen nicht nebeneinander
local function narrowScreen(): boolean
	local w = gui and gui.AbsoluteSize.X or 0
	return w > 0 and w < MissionClient.CardWidth + 24 + MissionClient.HintWidth + 32
end

local function cardTop(): number
	local top = MissionClient.CardTop
	if UI and type(UI.ToastTop) == "function" then
		local ok, t = pcall(UI.ToastTop)
		if ok and type(t) == "number" and t == t then
			top = math.max(top, t + 60 + 8)
		end
	end
	if narrowScreen() then
		local okB, bottom = pcall(rightCardsBottom)
		if okB and type(bottom) == "number" and bottom > 0 then
			top = math.max(top, bottom + 8)
		end
	end
	return top
end

-- Lage einer Karte (Ankerpunkt x 0.5) mit Wunsch-Oberkante top: nie in der 2.4.0-HUD-Leiste oder den Fahrzeugknöpfen
-- (PrestigeUI.FreeRect); bleibt die Karte in der Mitte, bleibt auch die Position mittig (Skala 0.5)
local function freePosition(frame: GuiObject, top: number, fallbackH: number): UDim2
	local w, h = gui and gui.AbsoluteSize.X or 0, gui and gui.AbsoluteSize.Y or 0
	if not PrestigeUI or w <= 0 or h <= 0 then
		return UDim2.new(0.5, 0, 0, top)
	end
	local cw = frame.AbsoluteSize.X > 0 and frame.AbsoluteSize.X or math.min(MissionClient.CardWidth, w - 24)
	local ch = frame.AbsoluteSize.Y > 0 and frame.AbsoluteSize.Y or fallbackH
	local x0 = (w - cw) / 2
	local ok, x, y = pcall(PrestigeUI.FreeRect, w, h, x0, top, cw, ch)
	if not ok then
		return UDim2.new(0.5, 0, 0, top)
	end
	if math.abs(x - x0) < 0.5 then
		return UDim2.new(0.5, 0, 0, y)
	end
	return UDim2.new(0, x + cw / 2, 0, y)
end

local function placeCard()
	if card.frame then
		card.frame.Position = freePosition(card.frame, cardTop(), 80)
	end
end

local function placeChapter()
	if not chapter.frame or not gui then
		return
	end
	local h = gui.AbsoluteSize.Y
	local ch = chapter.frame.AbsoluteSize.Y > 0 and chapter.frame.AbsoluteSize.Y or 200
	local pos = freePosition(chapter.frame, h * 0.42 - ch / 2, ch)
	-- Ankerpunkt der Kapitel-Karte ist die Mitte (0.5, 0.5)
	chapter.frame.Position = UDim2.new(pos.X.Scale, pos.X.Offset, 0, pos.Y.Offset + ch / 2)
end

local function buildCard()
	local frame = UI.Frame(gui, {
		Name = "MissionCard", BackgroundColor3 = T.panel, AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, MissionClient.CardTop),
		Size = UDim2.new(0, MissionClient.CardWidth, 0, 0), Visible = false,
	})
	UI.Corner(frame, 12)
	card.padding = UI.Padding(frame, 16, 12)
	card.list = UI.List(frame, 4)
	local stripe = UI.Frame(frame, { Name = "Stripe", BackgroundColor3 = T.green, Size = UDim2.new(1, 0, 0, 3), AutomaticSize = Enum.AutomaticSize.None, LayoutOrder = 0 })
	UI.Corner(stripe, 2)
	card.frame = frame
	card.stripe = stripe
	card.title = UI.Label(frame, "", { Name = "Title", Font = UI.FontBold, TextSize = 18, LayoutOrder = 1, TextXAlignment = Enum.TextXAlignment.Center })
	card.text = UI.Label(frame, "", { Name = "Text", TextSize = 14, TextColor3 = T.muted, LayoutOrder = 2, TextXAlignment = Enum.TextXAlignment.Center })
	card.style = { padding = card.padding, list = card.list, title = card.title, text = card.text, titleSize = 18, textSize = 14, padX = 16, padY = 12, gap = 4 }
	card.scale = Instance.new("UIScale")
	card.scale.Scale = 1
	card.scale.Parent = frame
end

local function hideChapter()
	chapterSerial += 1
	chapterOn = false
	if chapter.frame then
		chapter.frame.Visible = false
	end
end

local function buildChapterCard()
	local frame = UI.Frame(gui, {
		Name = "ChapterCard", BackgroundColor3 = T.panel, AutomaticSize = Enum.AutomaticSize.Y,
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.42, 0),
		Size = UDim2.new(0, MissionClient.CardWidth, 0, 0), Visible = false, Active = false,
	})
	UI.Corner(frame, 14)
	UI.Padding(frame, 20, 16)
	UI.List(frame, 8)
	chapter.frame = frame
	chapter.kicker = UI.Label(frame, "Neues Kapitel", { Name = "Kicker", Font = UI.FontBold, TextSize = 13, TextColor3 = T.yellow, LayoutOrder = 1 })
	chapter.title = UI.Label(frame, "", { Name = "Title", Font = UI.FontBig, TextSize = 22, LayoutOrder = 2 })
	chapter.text = UI.Label(frame, "", { Name = "Text", TextSize = 15, TextColor3 = T.muted, LayoutOrder = 3 })
	chapter.button = UI.Button(frame, "Los geht's!", T.green, hideChapter, { Name = "ChapterOk", LayoutOrder = 4 })
	chapter.scale = Instance.new("UIScale")
	chapter.scale.Scale = 1
	chapter.scale.Parent = frame
end

local function layout()
	if not gui then
		return
	end
	local w = gui.AbsoluteSize.X
	if w <= 0 then
		return
	end
	local cw = math.min(MissionClient.CardWidth, w - 24)
	card.frame.Size = UDim2.new(0, cw, 0, 0)
	if PrestigeUI and card.style then
		pcall(PrestigeUI.StyleCard, card.style, PrestigeUI.IsCompact(gui.AbsoluteSize.Y)) -- Handy quer: kompakt
	end
	placeCard()
	chapter.frame.Size = UDim2.new(0, cw, 0, 0)
	placeChapter()
end

local function build()
	if gui then
		return
	end
	local pg = playerGui()
	if not pg then
		return
	end
	gui = Instance.new("ScreenGui")
	gui.Name = "Missionen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = MissionClient.DisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = pg
	buildMarker("MissionMarker", T.yellow)
	buildMarker("DeliveryStart", T.blue)
	buildMarker("DeliveryEnd", T.green)
	buildCard()
	buildChapterCard()
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
end

---------------------------------------------------------------- Ziele
local function partOf(inst: Instance?): BasePart?
	if not inst then
		return nil
	end
	if inst:IsA("Model") then
		local p = inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart")
		return p
	end
	return inst:IsA("BasePart") and inst or nil
end

local function stationPart(zone: string, key: string): BasePart?
	local folder = nil
	if zone == PLOT or zone == ANCHOR then
		local player = Players.LocalPlayer
		local plots = workspace:FindFirstChild("PlayerWorkshops")
		local plot = plots and player and plots:FindFirstChild("Plot_" .. tostring(player.UserId))
		folder = plot and plot:FindFirstChild(zone == ANCHOR and "OWAnchors" or "Stations")
	else
		local city = workspace:FindFirstChild("City")
		folder = city and city:FindFirstChild("Stations")
	end
	return partOf(folder and folder:FindFirstChild(key))
end

-- Zielbeschreibung einer Missionsdefinition (StoryRules.Mission / SideDef): { zone, key, title, travel } oder nil
-- (eine Tabelle für Server und Client: StoryRules.TargetOf)
function MissionClient.TargetOf(def: any): any
	local ok, t = pcall(StoryRules.TargetOf, def)
	return ok and t or nil
end

local function activeDef(): any
	local st = story(latest)
	local a = type(st.active) == "table" and st.active or nil
	if not a or type(a.id) ~= "string" then
		return nil
	end
	if a.claimable == true then
		return nil -- erfüllt: Belohnung im Tab, kein Ziel mehr
	end
	local ok, def = pcall(StoryRules.Mission, a.id)
	return ok and def or nil
end

-- Lieferung gewünscht? Heutige Nebenmission „Lieferung“ offen (kind event, event delivery, nicht abgeholt, nicht erfüllt)
-- oder 3.x die laufende Story-Mission ist eine Lieferfahrt (Kapitel 1 „Herstellung“)
local function deliveryWanted(): boolean
	local st = story(latest)
	local a = type(st.active) == "table" and st.active or nil
	if a and a.claimable ~= true and type(a.id) == "string" then
		local okA, defA = pcall(StoryRules.Mission, a.id)
		if okA and type(defA) == "table" and defA.kind == "event" and defA.event == "delivery" then
			return true
		end
	end
	for _, e in ipairs(type(st.side) == "table" and st.side or {}) do
		if not e.done and not e.claimable then
			local ok, def = pcall(StoryRules.SideDef, e.id)
			if ok and type(def) == "table" and def.kind == "event" and def.event == "delivery" then
				return true
			end
		end
	end
	return false
end

local function routePart(folder: Instance, role: string, names: { string }): BasePart?
	for _, x in ipairs(folder:GetChildren()) do
		if x:IsA("BasePart") and x:GetAttribute("Role") == role then
			return x
		end
	end
	for _, n in ipairs(names) do
		local x = folder:FindFirstChild(n)
		if x and x:IsA("BasePart") then
			return x
		end
	end
	return nil
end

local function routes(): { any }
	local out = {}
	local city = workspace:FindFirstChild("City")
	local missions = city and city:FindFirstChild("Missions")
	if not missions then
		return out
	end
	for _, x in ipairs(missions:GetChildren()) do
		local n = tonumber(string.match(x.Name, "^Delivery_(%d+)$"))
		if n then
			local start = routePart(x, "start", { "Start" })
			local finish = routePart(x, "end", { "Ziel", "End", "Finish" })
			if start and finish then
				table.insert(out, { n = n, start = start, finish = finish })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.n < b.n
	end)
	return out
end

local function rootPos(): Vector3?
	local player = Players.LocalPlayer
	local ch = player and player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return root and root.Position or nil
end

local function setMarker(m: any, part: BasePart?, title: string?)
	if not part or not title then
		m.gui.Adornee = nil
		m.gui.Enabled = false
		return
	end
	local pos = rootPos()
	local dist = pos and math.floor((part.Position - pos).Magnitude) or nil
	m.label.Text = "▼ " .. title .. (dist and (" · " .. MiniLocale.Number(dist) .. " m") or "")
	m.gui.Adornee = part
	m.gui.Enabled = true
end

local function updateMarkers()
	if not gui then
		return
	end
	local allowed = markersAllowed() and latest ~= nil and (latest.mode == nil or latest.mode == "openworld") and story(latest).passive ~= true
	local target, start, finish = markers[1], markers[2], markers[3]
	if not allowed then
		setMarker(target, nil, nil)
		setMarker(start, nil, nil)
		setMarker(finish, nil, nil)
		return
	end
	-- Ziel der aktiven Mission
	local def = activeDef()
	local tgt = def and MissionClient.TargetOf(def) or nil
	local part = tgt and stationPart(tgt.zone, tgt.key) or nil
	local title = tgt and tgt.title or nil
	local st = story(latest)
	if part and tgt.key == "kiesplatz" and type(st.sale) == "table" and type(st.sale.customer) == "string" then
		title = title .. " · " .. st.sale.customer .. " wartet"
	end
	setMarker(target, part, title)
	-- Lieferung: Zielmarker der laufenden Fahrt, sonst Startmarker der nächsten Route
	local list = routes()
	if delivery and serverNow() < delivery.until_ then
		local r = nil
		for _, x in ipairs(list) do
			if x.n == delivery.route then
				r = x
			end
		end
		setMarker(start, nil, nil)
		setMarker(finish, r and r.finish or nil, "LIEFERZIEL " .. tostring(delivery.route))
	else
		delivery = nil
		setMarker(finish, nil, nil)
		local best, bestD = nil, math.huge
		if deliveryWanted() then
			local pos = rootPos()
			for _, x in ipairs(list) do
				local dd = pos and (x.start.Position - pos).Magnitude or x.n
				if dd < bestD then
					best, bestD = x, dd
				end
			end
		end
		setMarker(start, best and best.start or nil, best and ("LIEFERUNG " .. tostring(best.n) .. " · START") or nil)
	end
end

---------------------------------------------------------------- Karten
-- Niedriger Bildschirm (Handy quer): zwischen Toast-Zone und HUD-Leiste passt nur eine Karte – solange oben rechts
-- „Tipp“/„Neu freigeschaltet“ zu sehen ist, wartet die Missions-Karte
local function shortAndBusy(): boolean
	if not PrestigeUI or not gui or not PrestigeUI.IsCompact(gui.AbsoluteSize.Y) then
		return false
	end
	local ok, bottom = pcall(rightCardsBottom)
	return ok and type(bottom) == "number" and bottom > 0
end

local function showNextCard()
	if cardShowing or #cardQueue == 0 or not card.frame or not overlaysAllowed() or shortAndBusy() then
		return
	end
	local entry = table.remove(cardQueue, 1)
	cardShowing = true
	cardSerial += 1
	local serial = cardSerial
	card.title.Text = entry.title
	card.text.Text = entry.text or ""
	card.text.Visible = entry.text ~= nil and entry.text ~= ""
	card.stripe.BackgroundColor3 = entry.color or T.green
	placeCard()
	card.frame.Visible = true
	card.scale.Scale = 0.8
	TweenService:Create(card.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(MissionClient.CardSeconds, function()
		if serial == cardSerial and card.frame then
			card.frame.Visible = false
			cardShowing = false
			showNextCard()
			MissionClient.Refresh() -- Tracker (Handy) wieder an seinen Platz
		end
	end)
end

function MissionClient.ShowCard(title: string, text: string?, color: Color3?)
	if type(title) ~= "string" or title == "" then
		return
	end
	if #cardQueue >= MissionClient.QueueMax then
		table.remove(cardQueue, 1)
	end
	table.insert(cardQueue, { title = title, text = text, color = color })
	showNextCard()
end

local function showChapterNow(entry: any)
	chapterSerial += 1
	local serial = chapterSerial
	chapter.kicker.Text = entry.kicker or "Neues Kapitel"
	chapter.title.Text = entry.title
	chapter.text.Text = entry.text or ""
	chapter.text.Visible = entry.text ~= nil and entry.text ~= ""
	placeChapter()
	chapterOn = true
	chapter.frame.Visible = true
	chapter.scale.Scale = 0.85
	TweenService:Create(chapter.scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(MissionClient.ChapterSeconds, function()
		if serial == chapterSerial and chapter.frame then
			chapterOn = false
			chapter.frame.Visible = false
		end
	end)
end

-- Kapitel-Intro (wartet, bis keine Sperre mehr aktiv ist)
function MissionClient.ShowChapter(title: string, text: string?, kicker: string?)
	if not chapter.frame or type(title) ~= "string" or title == "" then
		return
	end
	chapterPending = { title = title, text = text, kicker = kicker }
	if overlaysAllowed() then
		local e = chapterPending
		chapterPending = nil
		showChapterNow(e)
	end
end

---------------------------------------------------------------- NPC-Kunden (Anim="npc_idle")
local function npcKind(inst: Instance): string?
	local kind = inst:GetAttribute("Anim")
	if type(kind) ~= "string" then
		return nil
	end
	kind = string.lower(kind)
	return MissionClient.Kinds[kind] and kind or nil
end

local function considerNpc(inst: Instance)
	if npcs[inst] or not (inst:IsA("Model") or inst:IsA("BasePart")) or not npcKind(inst) then
		return
	end
	local ok, base = pcall(function()
		return inst:IsA("Model") and inst:GetPivot() or (inst :: BasePart).CFrame
	end)
	if not ok then
		return
	end
	local rec = {
		inst = inst, base = base, phase = (hash(inst:GetFullName()) % 1000) / 1000 * 2 * math.pi, active = true, dead = false,
		bobPeriod = num(inst:GetAttribute("Period"), 2.6), turnPeriod = num(inst:GetAttribute("TurnPeriod"), 7),
		bob = num(inst:GetAttribute("Bob"), MissionClient.NpcBob), turn = num(inst:GetAttribute("Turn"), MissionClient.NpcTurn),
	}
	npcs[inst] = rec
	table.insert(npcList, rec)
	inst.Destroying:Connect(function()
		rec.dead = true
		npcs[inst] = nil
	end)
end

local function attachKiesplatz(district: Instance)
	for _, d in ipairs(district:GetDescendants()) do
		pcall(considerNpc, d)
	end
	pcall(considerNpc, district)
	district.DescendantAdded:Connect(function(d)
		task.defer(function()
			if d.Parent then
				pcall(considerNpc, d)
			end
		end)
	end)
end

local function whenChild(parent: Instance, name: string, fn: (Instance) -> ())
	local existing = parent:FindFirstChild(name)
	if existing then
		fn(existing)
		return
	end
	local conn
	conn = parent.ChildAdded:Connect(function(c)
		if c.Name == name and conn then
			conn:Disconnect()
			conn = nil
			fn(c)
		end
	end)
end

local function npcUpdate(rec: any, t: number)
	local bob = rec.bob * math.sin(t * 2 * math.pi / rec.bobPeriod + rec.phase)
	local yaw = rec.turn * math.sin(t * 2 * math.pi / rec.turnPeriod + rec.phase * 0.5)
	local cf = rec.base * CFrame.Angles(0, yaw, 0) + Vector3.new(0, math.max(0, bob), 0)
	if rec.inst:IsA("Model") then
		rec.inst:PivotTo(cf)
	else
		(rec.inst :: BasePart).CFrame = cf
	end
end

local function npcRefresh()
	local cam = workspace.CurrentCamera
	local pos = cam and cam.CFrame.Position or nil
	for i = #npcList, 1, -1 do
		local r = npcList[i]
		if r.dead or not r.inst.Parent then
			npcs[r.inst] = nil
			table.remove(npcList, i)
		elseif pos then
			r.active = (r.base.Position - pos).Magnitude < MissionClient.NpcCull
		end
	end
end

local function npcStep(dt: number)
	cullTimer += dt
	if cullTimer >= 0.5 then
		cullTimer = 0
		npcRefresh()
	end
	if #npcList == 0 then
		return
	end
	local t = serverNow()
	for _, r in ipairs(npcList) do
		if r.active and not r.dead then
			local ok, err = pcall(npcUpdate, r, t)
			if not ok then
				r.dead = true
				warnOnce("npc_" .. r.inst:GetFullName(), "NPC-Animation gestoppt: " .. tostring(err))
			end
		end
	end
end

---------------------------------------------------------------- Schnittstelle
-- Sichtbarkeit, wartende Karten und Marker sofort neu (Heartbeat alle 0,2 s; MiniClient.RefreshOverlays bei jedem
-- Wechsel von 2.4.0-Dialog, Tablet oder Panel – damit keine Karte im selben Moment über einem Dialog liegt)
function MissionClient.Refresh()
	if not gui then
		return
	end
	-- ScreenGui: aus bei Panel/Tablet/QTE; beim Fahren bleibt sie an (Marker), nur die Karten tauchen ab
	local markers = markersAllowed()
	if gui.Enabled ~= markers then
		gui.Enabled = markers
	end
	local allowed = overlaysAllowed()
	if allowed then
		if chapterPending then
			local e = chapterPending
			chapterPending = nil
			showChapterNow(e)
		end
		showNextCard()
	end
	-- niedriger Bildschirm: taucht rechts eine Karte auf, weicht die Missions-Karte, bis sie weg ist
	if card.frame then
		local show = cardShowing and allowed and not shortAndBusy()
		if card.frame.Visible ~= show then
			card.frame.Visible = show
		end
		-- sichtbare Karte neu legen, falls rechts gerade eine Karte auf- oder abgetaucht ist (schmale Bildschirme)
		if card.frame.Visible then
			placeCard()
		end
	end
	if chapter.frame then
		local show = chapterOn and allowed
		if chapter.frame.Visible ~= show then
			chapter.frame.Visible = show
		end
	end
	local okT, errT = pcall(MissionClient.RenderTracker, allowed)
	if not okT then
		warnOnce("tracker", "Karte „Deine Mission“: " .. tostring(errT))
	end
	updateMarkers()
end

function MissionClient.OnSnapshot(s: any)
	if type(s) ~= "table" then
		return
	end
	local st = story(s)
	latest = s
	local ch = math.floor(num(st.chapter, 1))
	if lastChapter ~= nil and ch > lastChapter and st.finished ~= true then
		MissionClient.ShowChapter("Kapitel " .. tostring(ch) .. ": " .. tostring(st.chapterTitle or ""), st.intro, "Neues Kapitel")
	end
	lastChapter = ch
	updateMarkers()
end

-- mini_notice { kind = "mission", id, title, progress, target, done, side, coop?, from? }
--             { kind = "story", event = "claimed" | "side_claimed" | "delivery" | "sale" | "started", ... }
function MissionClient.OnNotice(data: any)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "mission" then
		if data.done == true then
			local title = tostring(data.title or data.id or "Mission")
			MissionClient.ShowCard((data.side and "Nebenmission geschafft!" or "Mission geschafft!"), "„" .. title .. "“ – hol dir die Belohnung im Tab „Story“.", T.green)
		elseif data.coop == true and type(data.from) == "string" then
			MissionClient.ShowCard("Party-Fortschritt", data.from .. " hat „" .. tostring(data.title or data.id) .. "“ weitergebracht (" .. tostring(math.floor(num(data.progress, 0))) .. "/" .. tostring(math.floor(num(data.target, 1))) .. ").", T.blue)
		end
	elseif kind == "story" then
		local ev = data.event
		if ev == "claimed" then
			local reward = MiniLocale.Credits(num(data.credits, 0)) .. (num(data.xp, 0) > 0 and (" · " .. tostring(math.floor(num(data.xp, 0))) .. " XP") or "")
			MissionClient.ShowCard("Belohnung abgeholt", "„" .. tostring(data.title or data.mission) .. "“: " .. reward, T.yellow)
			if data.finished == true then
				MissionClient.ShowChapter("Mega-Verkäufer!", type(data.text) == "string" and data.text or "Du hast die ganze Story geschafft – die ganze Stadt kennt deinen Namen.", "Story abgeschlossen")
			end
		elseif ev == "side_claimed" then
			local reward = MiniLocale.Credits(num(data.credits, 0)) .. (num(data.xp, 0) > 0 and (" · " .. tostring(math.floor(num(data.xp, 0))) .. " XP") or "")
			MissionClient.ShowCard("Nebenmission abgeholt", "„" .. tostring(data.title or data.mission) .. "“: " .. reward, T.blue)
		elseif ev == "delivery" then
			if data.state == "started" then
				delivery = { route = math.floor(num(data.route, 1)), until_ = serverNow() + num(data.limit, 240) }
				MissionClient.ShowCard("Lieferung gestartet", "Fahr zum Ziel – du hast " .. MiniLocale.Duration(num(data.limit, 240)) .. ".", T.blue)
			else
				delivery = nil
				if data.state == "done" then
					MissionClient.ShowCard("Lieferung abgeliefert!", "In " .. MiniLocale.Duration(num(data.time, 0)) .. " geschafft.", T.green)
				elseif data.state == "expired" then
					MissionClient.ShowCard("Lieferung abgelaufen", "Das hat zu lange gedauert – fahr noch einmal zum Start.", T.red)
				end
			end
			updateMarkers()
		elseif ev == "started" then
			updateMarkers()
		end
	end
end

-- Heartbeat: Sichtbarkeit, Marker (alle 0,2 s), Wippen der Marker und NPC-Figuren (jedes Frame)
function MissionClient.Step(dt: number?)
	local d = num(dt, 0.2)
	if gui then
		for _, m in ipairs(markers) do
			if m.gui.Enabled then
				m.bounce += d
				m.gui.StudsOffset = Vector3.new(0, 5 + 0.4 * math.sin(m.bounce * 3), 0)
			end
		end
		stepTimer += d
		if stepTimer >= 0.2 then
			stepTimer = 0
			MissionClient.Refresh()
		end
	end
	npcStep(d)
end

function MissionClient.Start(context: any)
	ctx = context or {}
	UI = ctx.UI
	T = UI and UI.Theme
	if started then
		return
	end
	started = true
	local ok, err = pcall(build)
	if not ok then
		warnOnce("gui", "Oberfläche: " .. tostring(err))
	end
	-- NPC-Kunden: worldgen legt sie unter City.Animated.Kiesplatz ab (Kunde_1..3), ältere Stände unter City.Districts.Kiesplatz
	whenChild(workspace, "City", function(city)
		for _, folderName in ipairs({ "Animated", "Districts" }) do
			whenChild(city, folderName, function(folder)
				whenChild(folder, "Kiesplatz", function(district)
					local okA, errA = pcall(attachKiesplatz, district)
					if not okA then
						warnOnce("npc", "Kiesplatz-Kunden: " .. tostring(errA))
					end
					npcRefresh()
				end)
			end)
		end
	end)
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function(dt)
			local okS, errS = pcall(MissionClient.Step, dt)
			if not okS then
				warnOnce("step", tostring(errS))
			end
		end)
	end
end

---------------------------------------------------------------- Zugriff (Tests)
function MissionClient.Gui()
	return gui
end

function MissionClient.Markers()
	return markers
end

function MissionClient.MarkerTarget(name: string?): Instance?
	for _, m in ipairs(markers) do
		if (name == nil and m.name == "MissionMarker") or m.name == name then
			return m.gui.Enabled and m.gui.Adornee or nil
		end
	end
	return nil
end

function MissionClient.CardVisible(): boolean
	return card.frame ~= nil and card.frame.Visible == true
end

function MissionClient.ChapterVisible(): boolean
	return chapter.frame ~= nil and chapter.frame.Visible == true
end

function MissionClient.QueuedCards(): number
	return #cardQueue
end

function MissionClient.NpcCount(): number
	return #npcList
end

function MissionClient.NpcRecord(inst: Instance): any
	return npcs[inst]
end

function MissionClient.DeliveryState(): any
	return delivery
end

return MissionClient
