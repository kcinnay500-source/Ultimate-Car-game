-- TycoonClient: Client-Seite des Schnellen Spiels außerhalb des Panels (docs/PHASE4_CONTRACT.md §8).
-- Gestartet von MiniClient: TycoonClient.Start(ctx); danach TycoonClient.OnSnapshot(s) je Snapshot und
-- TycoonClient.OnNotice(data) je mini_notice (MiniClient reicht beides durch, wie bei DriveClient).
--   Abzeichen   eigene ScreenGui "TycoonHUD" (DisplayOrder 19, wie ProgressHUD) oben rechts UNTER dem Prestige-Abzeichen
--               (PrestigeUI.HudBottom + 8): „Bargeld: n“ und „Behälter x % · Rate/s“ bzw. „Kein Durchlauf – Grundstück
--               wählen“. Nur im Modus tycoon; weg, solange das Minispiel-Panel, das 2.4.0-Tablet, QTE/Diagnose
--               (ctx.IsBlocked) oder der Tacho (ScreenGui "Fahren") zu sehen sind. Sichtbarkeit alle 0,2 s (Step).
--   Hinweise    mini_notice { kind = "tycoon", event = "choose" } (Startpad ohne Durchlauf) öffnet den Tab „tycoon“
--               (ctx.Open, sonst UI.Open); kind = "tycoon_stage" lässt das Abzeichen aufblitzen.
--   Pads        Touched der Kaufpads/Stufen-Pads/Sammelpads (Attribute TycoonButton, TycoonPad, TycoonSlot unter
--               Workspace.Tycoon.Plots) durch die eigene Figur → kurzer Blitz am Pad (Farbe) und an seinem Schild
--               (SurfaceGui: UIScale-Stoß, Schrift kurz gelb). Rein optisch, 0,5 s Entprellung je Pad; die Wirkung
--               (Kauf/Sammeln) entscheidet allein der Server über sein eigenes Touched.
--   Produzenten Anim-Arten, die CityClient nicht kennt, für Modelle unter Workspace.Tycoon.Plots (Attribut Anim oder
--               TycoonAnim):
--                 conveyor  Förderband: Kisten wandern über das Band (Kind mit Mover=true oder Band/Belt/Gurt im Namen,
--                           sonst das Objekt/PrimaryPart). Fracht = Kinder mit Cargo=true oder Kiste/Paket/Karton/Teil
--                           im Namen; fehlt sie, legt der Client 3 kleine Kisten an (nur lokal). Attribute: Speed
--                           (Studs/s, 3), Axis ("X"|"Z", "X"), Cargo (Anzahl, 3), CargoColor
--                 stamp     Stempel/Presse: Mover (Mover=true oder Stempel/Ram/Platen/Kolben/Pressplatte/Platte im
--                           Namen, sonst das Objekt) fährt periodisch herunter. Attribute: Stroke (Studs, 60 % der
--                           Mover-Höhe), Period (2.4), Down (0.5), Hold (0.2), Up (0.8)
--               Lage relativ zum Modell-Pivot, damit versetzte Vorlagen (PivotTo durch den Server) stimmen.
--               Serverzeit als Takt (alle sehen dasselbe), Objekte weiter als 300 Studs von der Kamera pausieren.
-- Nichts hier ist spielrelevant; alles läuft in pcall und stoppt bei Fehlern nur das betroffene Objekt.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TycoonClient = {}

TycoonClient.HudWidth = 230
TycoonClient.HudHeight = 56
TycoonClient.HudMargin = 16
TycoonClient.HudGap = 8
TycoonClient.HudDisplayOrder = 19
TycoonClient.Cull = 300
TycoonClient.PadDebounce = 0.5
TycoonClient.Kinds = { conveyor = true, stamp = true }

local MiniLocale, GameConfig
pcall(function()
	local Mini = ReplicatedStorage:WaitForChild("GarageShared", 10):WaitForChild("Mini", 10)
	MiniLocale = require(Mini:WaitForChild("MiniLocale", 10))
	GameConfig = require(Mini:WaitForChild("GameConfig", 10))
end)

-- Pad-/Preisfarben je Server-Zustand (Attribut TycoonState: locked | ready | owned), dieselbe Tabelle wie TycoonService
local STATE_COLORS = {}
do
	local cfg = GameConfig and GameConfig.Tycoon and GameConfig.Tycoon.PadColors or nil
	local fallback = { owned = { 62, 217, 166 }, ready = { 247, 176, 63 }, locked = { 156, 170, 177 } }
	for state, rgb in pairs(fallback) do
		local c = type(cfg) == "table" and cfg[state] or rgb
		STATE_COLORS[state] = Color3.fromRGB(c[1], c[2], c[3])
	end
end

local ctx, UI
local hud = {} -- gui, frame, line1, line2, scale
local latest = nil
local started = false
local heartbeat = nil
local hudTimer = 0
local flashSerial = 0
-- Schwach verkettet: Stufenmodelle werden bei Stufenaufstieg/Rebirth zerstört und neu geklont; die Datensätze der
-- alten Pads/Produzenten dürfen die Instanzen nicht im Speicher halten (Destroying räumt zusätzlich sofort auf)
local records = setmetatable({}, { __mode = "k" }) -- [inst] = Datensatz (Produzenten)
local recList = {}
local pads = setmetatable({}, { __mode = "k" }) -- [part] = { last = clock, flashes, busy, color }
local warned = {}
local warnedInst = setmetatable({}, { __mode = "k" }) -- [inst] = { [key] = true }
local cullTimer = 0

local function warnOnce(key: string, text: string)
	if not warned[key] then
		warned[key] = true
		warn("[Tycoon] " .. text)
	end
end

local function warnOnceInst(inst: Instance, key: string, text: string)
	local set = warnedInst[inst]
	if not set then
		set = {}
		warnedInst[inst] = set
	end
	if not set[key] then
		set[key] = true
		warn("[Tycoon] " .. text)
	end
end

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v or default
end

local function fmt(n: any): string
	if MiniLocale and MiniLocale.Number then
		return MiniLocale.Number(num(n, 0))
	end
	return tostring(math.floor(num(n, 0)))
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

local function playerGui()
	local player = Players.LocalPlayer
	return player and player:FindFirstChild("PlayerGui") or nil
end

local function lower(s: any): string
	return type(s) == "string" and string.lower(s) or ""
end

local function nameHas(inst: Instance, words: { string }): boolean
	local n = lower(inst.Name)
	for _, w in ipairs(words) do
		if string.find(n, w, 1, true) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- Abzeichen
local function prestigeBottom(): number
	local ok, bottom = pcall(function()
		local node = script.Parent:FindFirstChild("PrestigeUI")
		return node and require(node).HudBottom() or nil
	end)
	if ok and type(bottom) == "number" and bottom == bottom and bottom > 0 then
		return bottom
	end
	return 8 + TycoonClient.HudHeight
end

local function layoutHud()
	if not hud.frame then
		return
	end
	hud.frame.Position = UDim2.new(1, -TycoonClient.HudMargin, 0, prestigeBottom() + TycoonClient.HudGap)
end

local function buildHud()
	if hud.gui and hud.gui.Parent then
		return
	end
	local pg = playerGui()
	if not pg then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "TycoonHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = TycoonClient.HudDisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = pg
	hud.gui = gui
	local T = UI.Theme
	local frame = UI.Frame(gui, {
		Name = "Bargeld", BackgroundColor3 = T.bg, BackgroundTransparency = 0.1, AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -TycoonClient.HudMargin, 0, 8 + TycoonClient.HudHeight + TycoonClient.HudGap),
		Size = UDim2.new(0, TycoonClient.HudWidth, 0, TycoonClient.HudHeight), Active = false,
	})
	UI.Corner(frame, 10)
	local stripe = UI.Frame(frame, { BackgroundColor3 = T.yellow, Size = UDim2.new(0, 4, 1, -12), Position = UDim2.new(0, 0, 0, 6), AutomaticSize = Enum.AutomaticSize.None })
	UI.Corner(stripe, 2)
	hud.frame = frame
	hud.line1 = UI.Label(frame, "Bargeld: 0", {
		Name = "Cash", Font = UI.FontBold, TextSize = 15, TextColor3 = T.yellow, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 12, 0, 6), Size = UDim2.new(1, -22, 0, 18), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	hud.line2 = UI.Label(frame, "", {
		Name = "Status", TextSize = 12, TextColor3 = T.muted, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 12, 0, 26), Size = UDim2.new(1, -22, 0, 26), TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	hud.scale = Instance.new("UIScale")
	hud.scale.Scale = 1
	hud.scale.Parent = frame
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layoutHud)
	layoutHud()
end

local function driveHudVisible(): boolean
	local pg = playerGui()
	local drive = pg and pg:FindFirstChild("Fahren")
	return drive ~= nil and drive:IsA("LayerCollector") and drive.Enabled == true
end

local function hudShouldShow(): boolean
	if not latest or latest.mode ~= "tycoon" then
		return false
	end
	if UI and UI.IsOpen then
		return false
	end
	if ctx and ctx.IsTabletOpen and ctx.IsTabletOpen() == true then
		return false
	end
	if ctx and ctx.IsBlocked and ctx.IsBlocked() == true then
		return false
	end
	if driveHudVisible() then
		return false
	end
	return true
end

function TycoonClient.UpdateHud()
	if not hud.frame or not latest then
		return
	end
	local t = type(latest.tycoon) == "table" and latest.tycoon or {}
	local r = type(t.run) == "table" and t.run or nil
	local T = UI.Theme
	if r then
		hud.line1.Text = "Bargeld: " .. fmt(r.cash)
		local capacity = math.max(1, num(r.capacity, 1))
		local container = num(r.container, 0)
		local pct = math.floor(math.clamp(container / capacity, 0, 1) * 100 + 0.5)
		local full = container >= capacity
		hud.line2.Text = (full and "Behälter voll – Sammeln!" or ("Behälter " .. tostring(pct) .. " %")) .. " · " .. (MiniLocale and MiniLocale.Decimal(num(r.rate, 0), 2) or tostring(num(r.rate, 0))) .. "/s · Stufe " .. tostring(r.stage or 1)
		hud.line2.TextColor3 = full and T.yellow or T.muted
	else
		hud.line1.Text = "Bargeld: –"
		hud.line2.Text = "Kein Durchlauf – Grundstück wählen"
		hud.line2.TextColor3 = T.muted
	end
end

function TycoonClient.HudVisible(): boolean
	return hud.gui ~= nil and hud.gui.Enabled == true
end

-- Hinweis- und Freischaltungskarten (TutorialUI/UnlocksUI) rechnen über PrestigeUI.OverlayTop mit der Unterkante des
-- Bargeld-Abzeichens: beim Ein-/Ausblenden nachrücken lassen
local function nudgeCards()
	pcall(function()
		local node = script.Parent:FindFirstChild("TutorialUI")
		if node then
			require(node).PlaceHintCard()
		end
	end)
	pcall(function()
		local node = script.Parent:FindFirstChild("UnlocksUI")
		if node then
			require(node).PlaceCard()
		end
	end)
end

local function setHudEnabled(show: boolean)
	if not hud.gui then
		return
	end
	if show and not hud.gui.Enabled then
		layoutHud()
	end
	if hud.gui.Enabled ~= show then
		hud.gui.Enabled = show
		nudgeCards()
	end
end

-- Unterkante des Bargeld-Abzeichens (0, wenn unsichtbar): Karten oben rechts können sich darunter legen
function TycoonClient.HudBottom(): number
	if not TycoonClient.HudVisible() or not hud.frame then
		return 0
	end
	local ok, bottom = pcall(function()
		return hud.frame.AbsolutePosition.Y - hud.gui.AbsolutePosition.Y + hud.frame.AbsoluteSize.Y
	end)
	if ok and type(bottom) == "number" and bottom == bottom and bottom > 0 then
		return bottom
	end
	return hud.frame.Position.Y.Offset + TycoonClient.HudHeight
end

function TycoonClient.Flash()
	if not hud.scale then
		return
	end
	flashSerial += 1
	hud.scale.Scale = 1.12
	TweenService:Create(hud.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- Pads (rein optisch)
local function localCharacterHit(hit: Instance?): boolean
	local player = Players.LocalPlayer
	local char = player and player.Character
	return hit ~= nil and char ~= nil and (hit == char or hit:IsDescendantOf(char))
end

-- Zielfarbe eines Pads/Preisschilds aus dem Server-Zustand (Attribut TycoonState), sonst nil
local function stateColor(part: Instance): Color3?
	local state = part:GetAttribute("TycoonState")
	return type(state) == "string" and STATE_COLORS[state] or nil
end

local function cancelFlash(rec)
	for _, tw in ipairs(rec.tweens or {}) do
		pcall(function()
			tw:Cancel()
		end)
	end
	rec.tweens = nil
	rec.busy = nil
	rec.color = nil
	rec.labelBase = nil
end

-- Blitz am Pad: Farbe kurz heller, Schild (SurfaceGui) stößt (UIScale) und die Schrift wird kurz gelb.
-- Zurückgeblitzt wird auf die Farbe des Server-Zustands (TycoonState → STATE_COLORS; Preisschild ebenso); ohne Zustand
-- auf die Farbe vor dem Blitz. Nichts wird dauerhaft gecacht: ein neuer Zustand (gekauft, bezahlbar) gilt sofort.
function TycoonClient.PadFlash(part: Instance)
	if not (part and part:IsA("BasePart")) then
		return
	end
	local rec = pads[part] or {}
	pads[part] = rec
	local now = os.clock()
	if rec.last and now - rec.last < TycoonClient.PadDebounce then
		return
	end
	rec.last = now
	rec.flashes = (rec.flashes or 0) + 1
	local wasBusy = rec.busy == true
	local base = stateColor(part) or (not wasBusy and part.Color) or rec.color or part.Color
	cancelFlash(rec)
	rec.color = base
	rec.busy = true
	rec.tweens = {}
	rec.labelBase = {}
	local bright = Color3.new(math.min(1, base.R + 0.35), math.min(1, base.G + 0.35), math.min(1, base.B + 0.25))
	part.Color = bright
	local tween = TweenService:Create(part, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Color = base })
	table.insert(rec.tweens, tween)
	tween.Completed:Connect(function()
		if rec.tweens and rec.tweens[1] == tween then
			rec.tweens = nil
			rec.busy = nil
			rec.color = nil
			rec.labelBase = nil
		end
	end)
	tween:Play()
	for _, gui in ipairs(part:GetChildren()) do
		if gui:IsA("SurfaceGui") then
			local scale = gui:FindFirstChild("PadFlashScale")
			if not scale then
				scale = Instance.new("UIScale")
				scale.Name = "PadFlashScale"
				scale.Parent = gui
			end
			scale.Scale = 1.12
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			for _, label in ipairs(gui:GetDescendants()) do
				if label:IsA("TextLabel") then
					local target = (label.Name == "Price" and stateColor(part)) or (not wasBusy and label.TextColor3) or nil
					if not target then
						target = label.TextColor3
					end
					rec.labelBase[label] = target
					label.TextColor3 = UI and UI.Theme.yellow or Color3.fromRGB(235, 184, 72)
					local lt = TweenService:Create(label, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { TextColor3 = target })
					table.insert(rec.tweens, lt)
					lt:Play()
				end
			end
		end
	end
end

-- Server-Zustand wechselt mitten im Blitz (Kauf, „bezahlbar“): laufende Tweens abbrechen und die Zustandsfarbe setzen,
-- sonst endet der Tween auf der alten Farbe und das gekaufte Pad sieht gesperrt aus
local function onPadStateChanged(part: Instance)
	local rec = pads[part]
	if not rec or not rec.busy then
		return
	end
	cancelFlash(rec)
	local color = stateColor(part)
	if color then
		part.Color = color
		for _, gui in ipairs(part:GetChildren()) do
			if gui:IsA("SurfaceGui") then
				for _, label in ipairs(gui:GetDescendants()) do
					if label:IsA("TextLabel") and label.Name == "Price" then
						label.TextColor3 = color
					end
				end
			end
		end
	end
end

local function isPad(inst: Instance): boolean
	return inst:IsA("BasePart") and (inst:GetAttribute("TycoonButton") ~= nil or inst:GetAttribute("TycoonPad") ~= nil or inst:GetAttribute("TycoonSlot") ~= nil)
end

local function watchPad(part: Instance)
	if pads[part] or not isPad(part) then
		return
	end
	pads[part] = { last = nil, flashes = 0 }
	part.Touched:Connect(function(hit)
		if localCharacterHit(hit) then
			pcall(TycoonClient.PadFlash, part)
		end
	end)
	part:GetAttributeChangedSignal("TycoonState"):Connect(function()
		pcall(onPadStateChanged, part)
	end)
	part.Destroying:Connect(function()
		local rec = pads[part]
		if rec then
			cancelFlash(rec)
		end
		pads[part] = nil
		records[part] = nil
		warnedInst[part] = nil
	end)
end

---------------------------------------------------------------- Produzenten-Animationen
local function findMover(inst: Instance, names: { string }): Instance?
	if inst:IsA("BasePart") then
		return inst
	end
	for _, c in ipairs(inst:GetChildren()) do
		if c:IsA("BasePart") and c:GetAttribute("Mover") == true then
			return c
		end
	end
	for _, c in ipairs(inst:GetDescendants()) do
		if c:IsA("BasePart") and nameHas(c, names) then
			return c
		end
	end
	if inst:IsA("Model") then
		return inst.PrimaryPart
	end
	return nil
end

-- Pivot des Modells (oder das Part selbst) als Bezug, damit versetzte Vorlagen stimmen
local function pivotOf(inst: Instance): CFrame
	if inst:IsA("Model") then
		return inst:GetPivot()
	end
	return (inst :: BasePart).CFrame
end

local function setupStamp(inst: Instance)
	local mover = findMover(inst, { "stempel", "ram", "platen", "kolben", "pressplatte", "platte" })
	if not mover then
		error("kein Stempel (Mover=true oder Stempel/Ram/Platen/Kolben im Namen)")
	end
	local stroke = num(inst:GetAttribute("Stroke"), math.max(0.5, (mover :: BasePart).Size.Y * 0.6))
	local down = num(inst:GetAttribute("Down"), 0.5)
	local hold = num(inst:GetAttribute("Hold"), 0.2)
	local up = num(inst:GetAttribute("Up"), 0.8)
	local period = math.max(down + hold + up + 0.1, num(inst:GetAttribute("Period"), 2.4))
	local pivot = pivotOf(inst)
	local offset = pivot:ToObjectSpace((mover :: BasePart).CFrame)
	local rec = { inst = inst, mover = mover, offset = offset, stroke = stroke, period = period, down = down, hold = hold, up = up }
	function rec.update(r, t: number)
		local phase = t % r.period
		local f
		if phase < r.down then
			local x = phase / r.down
			f = x * x -- beschleunigt nach unten
		elseif phase < r.down + r.hold then
			f = 1
		elseif phase < r.down + r.hold + r.up then
			local x = (phase - r.down - r.hold) / r.up
			f = 1 - x
		else
			f = 0
		end
		local base = (r.inst:IsA("Model") and r.inst:GetPivot() or pivotOf(r.inst)) * r.offset
		r.mover.CFrame = base * CFrame.new(0, -r.stroke * f, 0)
	end
	return rec
end

local function setupConveyor(inst: Instance)
	local belt = findMover(inst, { "band", "belt", "gurt" })
	if not belt then
		error("kein Band (Mover=true oder Band/Belt/Gurt im Namen)")
	end
	local axis = string.upper(tostring(inst:GetAttribute("Axis") or "X"))
	local size = (belt :: BasePart).Size
	local length = axis == "Z" and size.Z or size.X
	local speed = num(inst:GetAttribute("Speed"), 3)
	local cargo = {}
	if inst:IsA("Model") then
		for _, c in ipairs(inst:GetChildren()) do
			if c:IsA("BasePart") and c ~= belt and (c:GetAttribute("Cargo") == true or nameHas(c, { "kiste", "paket", "karton", "teil", "cargo" })) then
				table.insert(cargo, c)
			end
		end
	end
	if #cargo == 0 then
		local n = math.clamp(math.floor(num(inst:GetAttribute("Cargo"), 3)), 1, 8)
		local color = inst:GetAttribute("CargoColor")
		local cargoFolder = Instance.new("Folder")
		cargoFolder.Name = "LocalCargo"
		for i = 1, n do
			local box = Instance.new("Part")
			box.Name = "Kiste_" .. i
			box.Size = Vector3.new(math.min(1.2, length / 4), 0.8, math.min(1.2, (axis == "Z" and size.X or size.Z) * 0.6))
			box.Anchored = true
			box.CanCollide = false
			box.CanQuery = false
			box.CanTouch = false
			box.CastShadow = false
			box.Material = Enum.Material.Wood
			box.Color = typeof(color) == "Color3" and color or Color3.fromRGB(176, 128, 72)
			box.Parent = cargoFolder
			table.insert(cargo, box)
		end
		cargoFolder.Parent = inst:IsA("Model") and inst or workspace
	end
	local pivot = pivotOf(inst)
	local beltOffset = pivot:ToObjectSpace((belt :: BasePart).CFrame)
	local rec = { inst = inst, belt = belt, beltOffset = beltOffset, cargo = cargo, length = length, speed = speed, axis = axis, top = size.Y / 2 }
	function rec.update(r, t: number)
		local base = (r.inst:IsA("Model") and r.inst:GetPivot() or pivotOf(r.inst)) * r.beltOffset
		local n = #r.cargo
		for i, box in ipairs(r.cargo) do
			if box.Parent then
				local travel = (t * r.speed + (i - 1) * r.length / n) % r.length - r.length / 2
				local y = r.top + box.Size.Y / 2
				local local_ = r.axis == "Z" and CFrame.new(0, y, travel) or CFrame.new(travel, y, 0)
				box.CFrame = base * local_
			end
		end
	end
	return rec
end

local SETUP = { stamp = setupStamp, conveyor = setupConveyor }

local function animKind(inst: Instance): string?
	local kind = inst:GetAttribute("TycoonAnim")
	if type(kind) ~= "string" then
		kind = inst:GetAttribute("Anim")
	end
	if type(kind) ~= "string" then
		return nil
	end
	kind = lower(kind)
	return TycoonClient.Kinds[kind] and kind or nil
end

local function consider(inst: Instance)
	if records[inst] or not (inst:IsA("BasePart") or inst:IsA("Model")) then
		return
	end
	local kind = animKind(inst)
	if not kind then
		return
	end
	records[inst] = kind
	local ok, rec = pcall(SETUP[kind], inst)
	if not ok then
		warnOnceInst(inst, "setup", inst:GetFullName() .. ": " .. tostring(rec))
		return
	end
	rec.kind = kind
	rec.active = true
	records[inst] = rec
	table.insert(recList, rec)
	inst.Destroying:Connect(function()
		records[inst] = nil
		warnedInst[inst] = nil
		rec.dead = true
	end)
end

local function attachPlots(plots: Instance)
	for _, d in ipairs(plots:GetDescendants()) do
		pcall(watchPad, d)
		consider(d)
	end
	plots.DescendantAdded:Connect(function(d)
		task.defer(function()
			if d.Parent then
				pcall(watchPad, d)
				consider(d)
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

local function camPos(): Vector3?
	local cam = workspace.CurrentCamera
	return cam and cam.CFrame.Position or nil
end

local function refreshActivity()
	local cam = camPos()
	for part in pairs(pads) do
		if not part.Parent then
			pads[part] = nil -- zerstörte/abgehängte Pads (Stufenwechsel) nicht festhalten
		end
	end
	for i = #recList, 1, -1 do
		local r = recList[i]
		if not r.inst.Parent then
			records[r.inst] = nil
			warnedInst[r.inst] = nil
			table.remove(recList, i)
		elseif cam then
			local pos = r.inst:IsA("Model") and r.inst:GetPivot().Position or (r.inst :: BasePart).Position
			r.active = (pos - cam).Magnitude < TycoonClient.Cull
		end
	end
end

local function stepAnimations(dt: number)
	cullTimer += dt
	if cullTimer >= 0.5 then
		cullTimer = 0
		refreshActivity()
	end
	local t = serverNow()
	for _, r in ipairs(recList) do
		if r.active and not r.dead and r.inst.Parent then
			local ok, err = pcall(r.update, r, t, dt)
			if not ok then
				r.dead = true
				warnOnceInst(r.inst, "update", "Animation gestoppt (" .. tostring(r.kind) .. "): " .. tostring(err))
			end
		end
	end
end

---------------------------------------------------------------- Schnittstelle
-- Sichtbarkeit des Abzeichens (alle 0,2 s) und Produzenten-Animationen (jedes Frame)
function TycoonClient.Step(dt: number?)
	local d = num(dt, 0.2)
	if hud.gui then
		hudTimer += d
		if hudTimer >= 0.2 then
			hudTimer = 0
			setHudEnabled(hudShouldShow())
		end
	end
	stepAnimations(d)
end

function TycoonClient.OnSnapshot(s)
	if type(s) ~= "table" then
		return
	end
	local before = latest
	latest = s
	TycoonClient.UpdateHud()
	if hud.gui then
		setHudEnabled(hudShouldShow())
		hudTimer = 0
	end
	local r = type(s.tycoon) == "table" and type(s.tycoon.run) == "table" and s.tycoon.run or nil
	local rb = before and type(before.tycoon) == "table" and type(before.tycoon.run) == "table" and before.tycoon.run or nil
	if r and rb and num(r.stage, 1) > num(rb.stage, 1) then
		TycoonClient.Flash()
	end
end

local function openTab()
	if ctx and ctx.IsBlocked and ctx.IsBlocked() == true then
		return
	end
	if ctx and type(ctx.Open) == "function" then
		ctx.Open("tycoon")
	elseif UI and UI.Pages and UI.Pages.tycoon then
		UI.Open("tycoon")
	end
end

-- mini_notice { kind = "tycoon", event = "choose" } | { kind = "tycoon_choose" } | { kind = "tycoon_stage" }
function TycoonClient.OnNotice(data)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "tycoon_choose" or (kind == "tycoon" and (data.event == "choose" or data.choose == true)) then
		openTab()
	elseif kind == "tycoon_stage" and (data.event == nil or data.event == "stage" or data.event == "start") then
		TycoonClient.Flash()
	elseif kind == "tycoon" and data.event == "collect" and data.pad then
		pcall(TycoonClient.PadFlash, data.pad)
	end
end

function TycoonClient.Start(context)
	ctx = context or {}
	UI = ctx.UI
	if started then
		return
	end
	started = true
	local ok, err = pcall(buildHud)
	if not ok then
		warnOnce("hud", "Abzeichen: " .. tostring(err))
	end
	whenChild(workspace, "Tycoon", function(zone)
		whenChild(zone, "Plots", function(plots)
			local okA, errA = pcall(attachPlots, plots)
			if not okA then
				warnOnce("plots", "Grundstücke: " .. tostring(errA))
			end
			refreshActivity()
		end)
	end)
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function(dt)
			local okS, errS = pcall(TycoonClient.Step, dt)
			if not okS then
				warnOnce("step", tostring(errS))
			end
		end)
	end
end

-- Für Tests und Fehlersuche
function TycoonClient.Hud()
	return hud.gui, hud
end

function TycoonClient.Record(inst: Instance)
	local r = records[inst]
	return type(r) == "table" and r or nil
end

function TycoonClient.Counts()
	local byKind, nPads = {}, 0
	for _, r in ipairs(recList) do
		byKind[r.kind] = (byKind[r.kind] or 0) + 1
	end
	for _ in pairs(pads) do
		nPads += 1
	end
	return { anims = #recList, kinds = byKind, pads = nPads }
end

function TycoonClient.PadInfo(part: Instance)
	return pads[part]
end

return TycoonClient
