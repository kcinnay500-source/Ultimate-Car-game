-- PrestigeUI: Tab „Prestige“ (Rang, nächste Schwelle, Fortschrittsbalken, Belohnungsliste mit „Abholen“) und das
-- kleine, immer sichtbare Fortschritts-Abzeichen (eigene ScreenGui "ProgressHUD", oben rechts):
-- „Rang n · Level n“ und „Nächste Freischaltung: <Titel> (Lv n)“ (docs/PHASE4_CONTRACT.md §4, §6).
-- Der Client zeigt nur an und sendet Absichten (prestige_claim {rank}); Rang und Belohnungen kommen vom Server
-- (Snapshot-Feld prestige aus PrestigeService.SnapshotFields), die Belohnungstexte aus GameConfig.Prestige.Rewards.
--
-- Sichtbarkeit des Abzeichens wie bei den anderen Mini-Oberflächen: weg, solange das Minispiel-Panel, das
-- 2.4.0-Tablet, QTE/Diagnose (ctx.IsBlocked) oder der Tacho (ScreenGui "Fahren" aktiv) zu sehen sind.
-- Lage: 2.4.0-CompactProgress liegt zentriert oben (310 × 46 bei y 8); das Abzeichen sitzt rechts mit 16 px Rand.
-- Ist der Bildschirm dafür zu schmal (Handy hochkant), rückt es unter die Leiste (y 60). DisplayOrder 19: unter dem
-- 2.4.0-UI (20), damit Tablet, Dialoge und Toasts darüber liegen. Dazu die gemeinsamen Freiraum-Regeln (FreeRect) für
-- alle Phase-4-Karten: nie über der 2.4.0-HUD-Leiste oder den Fahrzeugknöpfen E/F/H.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local GameConfig = require(Mini:WaitForChild("GameConfig"))
local PrestigeRules = require(Mini:WaitForChild("PrestigeRules"))
local Unlocks = require(Mini:WaitForChild("Unlocks"))

local PrestigeUI = {}

PrestigeUI.HudWidth = 230
PrestigeUI.HudHeight = 56
PrestigeUI.HudMargin = 16
PrestigeUI.HudTop = 8 -- wie CompactProgress
PrestigeUI.HudTopNarrow = 60 -- unter CompactProgress (y 8..54), wenn beides nebeneinander nicht passt
PrestigeUI.HudDisplayOrder = 19
PrestigeUI.CompactProgressWidth = 310

local UI, Remote, T, ctx
local refs = {}
local hud = {} -- gui, frame, line1, line2
local heartbeat = nil -- eine Heartbeat-Verbindung, auch bei mehrfachem Build
local latest = nil -- letzter Snapshot (für Abzeichen und Tab)
local hudTimer = 0
local flashSerial = 0

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v or default
end

-- Prozentwert ganzzahlig gerundet (7 × 0,02 × 100 ergäbe sonst „14.000000000000002“)
local function pct(v: any): string
	return tostring(math.floor(num(v, 0) + 0.5))
end

local function rewardText(r: any): string
	if type(r) ~= "table" then
		return ""
	end
	local parts = { "+" .. pct(r.incomePct) .. " % Einnahmen", pct(r.discountPct) .. " % Rabatt im Autohaus", "Kosmetik" }
	if num(r.tycoonRebirthPct, 0) > 0 then
		table.insert(parts, "+" .. pct(r.tycoonRebirthPct) .. " % Tycoon-Rebirth")
	end
	return table.concat(parts, " · ")
end
PrestigeUI.RewardText = rewardText

---------------------------------------------------------------- Belohnungszeile
local function rewardRow(parent, i: number)
	local row, left, right = UI.Row(parent, 10 + i)
	row.Name = "Reward_" .. i
	local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
	local sub = UI.Small(left, "", 2)
	local item = { root = row, name = name, sub = sub, rank = i }
	item.button = UI.Button(right, "Abholen", T.green, function()
		if item.claimable and item.rank then
			Remote.Send("prestige_claim", { rank = item.rank })
		end
	end, { TextSize = 14, Name = "Claim_" .. i })
	return item
end

---------------------------------------------------------------- Abzeichen (ProgressHUD)
local function buildHud()
	if hud.gui and hud.gui.Parent then
		return -- schon gebaut (zweites Build bindet nur den Kontext neu)
	end
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	if not playerGui then
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ProgressHUD"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = PrestigeUI.HudDisplayOrder
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = true
	gui.Parent = playerGui
	hud.gui = gui

	local frame = UI.Frame(gui, {
		Name = "Badge", BackgroundColor3 = T.bg, BackgroundTransparency = 0.1, AutomaticSize = Enum.AutomaticSize.None,
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -PrestigeUI.HudMargin, 0, PrestigeUI.HudTop),
		Size = UDim2.new(0, PrestigeUI.HudWidth, 0, PrestigeUI.HudHeight), Active = false,
	})
	UI.Corner(frame, 10)
	hud.frame = frame
	hud.line1 = UI.Label(frame, "Rang 0 · Level 1", {
		Name = "RankLevel", Font = UI.FontBold, TextSize = 14, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 10, 0, 6), Size = UDim2.new(1, -20, 0, 18), TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	hud.line2 = UI.Label(frame, "Nächste Freischaltung: …", {
		Name = "NextUnlock", TextSize = 12, TextColor3 = T.muted, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, 10, 0, 26), Size = UDim2.new(1, -20, 0, 26), TextWrapped = true, TextTruncate = Enum.TextTruncate.AtEnd,
		TextYAlignment = Enum.TextYAlignment.Top,
	})
	hud.scale = Instance.new("UIScale")
	hud.scale.Scale = 1
	hud.scale.Parent = frame

	local function layout()
		local width = gui.AbsoluteSize.X
		local fits = width <= 0 or width >= PrestigeUI.CompactProgressWidth + 2 * (PrestigeUI.HudWidth + PrestigeUI.HudMargin + 8)
		frame.Position = UDim2.new(1, -PrestigeUI.HudMargin, 0, fits and PrestigeUI.HudTop or PrestigeUI.HudTopNarrow)
	end
	gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(layout)
	layout()
end

-- Tacho sichtbar? (DriveClient: eigene ScreenGui "Fahren", Enabled nur während der Fahrt)
local function driveHudVisible(): boolean
	local player = Players.LocalPlayer
	local playerGui = player and player:FindFirstChild("PlayerGui")
	local drive = playerGui and playerGui:FindFirstChild("Fahren")
	return drive ~= nil and drive:IsA("LayerCollector") and drive.Enabled == true
end

local function hudShouldShow(): boolean
	if not latest then
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

function PrestigeUI.UpdateHud()
	if not hud.frame or not latest then
		return
	end
	local s = latest
	local pr = type(s.prestige) == "table" and s.prestige or {}
	local level = math.floor(num(s.level, 1))
	local rank = math.floor(num(pr.rank, PrestigeRules.RankFor(level)))
	local claimable = type(pr.claimable) == "table" and #pr.claimable or 0
	hud.line1.Text = "Rang " .. tostring(rank) .. " · Level " .. tostring(level) .. (claimable > 0 and " · Belohnung bereit!" or "")
	hud.line1.TextColor3 = claimable > 0 and T.yellow or T.text
	local nextU = type(s.unlocks) == "table" and s.unlocks.next or nil
	if type(nextU) ~= "table" then
		nextU = Unlocks.NextFor({ level = level })
	end
	if type(nextU) == "table" then
		hud.line2.Text = "Nächste Freischaltung: " .. tostring(nextU.title) .. " (Lv " .. tostring(nextU.level) .. ")"
	else
		hud.line2.Text = "Alle Freischaltungen erreicht!"
	end
end

function PrestigeUI.HudVisible(): boolean
	return hud.gui ~= nil and hud.gui.Enabled == true
end

-- Sichtbarkeit (alle 0,2 s aus dem Heartbeat, ohne Verkabelung in MiniClient)
function PrestigeUI.Step(dt: number?)
	if not hud.gui then
		return
	end
	hudTimer += num(dt, 0.2)
	if hudTimer < 0.2 then
		return
	end
	hudTimer = 0
	hud.gui.Enabled = hudShouldShow()
end

-- Kurzer Effekt am Abzeichen (neue Freischaltung / neuer Rang)
function PrestigeUI.Flash()
	if not hud.scale then
		return
	end
	flashSerial += 1
	hud.scale.Scale = 1.12
	TweenService:Create(hud.scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

---------------------------------------------------------------- Tab
function PrestigeUI.Build(page, context)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme

	local rankCard = UI.Card(page, 1)
	UI.Title(rankCard, "Dein Prestige-Rang", 1)
	refs.rank = UI.Label(rankCard, "", { Name = "RankText", Font = UI.FontBold, TextSize = 24, LayoutOrder = 2 })
	refs.title = UI.Label(rankCard, "", { Name = "TitleText", LayoutOrder = 3 })
	refs.next = UI.Small(rankCard, "", 4)
	refs.next.Name = "NextText"
	local _, fill = UI.Progress(rankCard, T.yellow, 5)
	refs.fill = fill
	refs.bonus = UI.Small(rankCard, "", 6)
	refs.bonus.Name = "BonusText"
	UI.Small(rankCard, "Prestige ist ein Rang ohne Neustart: Level, Credits und Autos bleiben. Jeder Rang bringt dauerhafte Belohnungen.", 7)

	local rewards = UI.Card(page, 2)
	UI.Title(rewards, "Belohnungen", 1)
	refs.rewardsInfo = UI.Small(rewards, "", 2)
	refs.rewards = UI.Pool(rewards, rewardRow)

	local ok, err = pcall(buildHud)
	if not ok then
		warn("[Prestige] Abzeichen: " .. tostring(err))
	end
	if not heartbeat then
		heartbeat = RunService.Heartbeat:Connect(function(dt)
			pcall(PrestigeUI.Step, dt)
		end)
	end
end

-- Jeder Snapshot (MiniClient ruft OnSnapshot; ohne Verkabelung reicht Render beim sichtbaren Tab)
function PrestigeUI.OnSnapshot(s)
	if type(s) ~= "table" then
		return
	end
	latest = s
	PrestigeUI.UpdateHud()
end

function PrestigeUI.Render(s)
	if type(s) ~= "table" then
		return
	end
	PrestigeUI.OnSnapshot(s)
	local pr = type(s.prestige) == "table" and s.prestige or {}
	local level = math.floor(num(s.level, 1))
	local progress = PrestigeRules.Progress(level)
	local rank = math.floor(num(pr.rank, progress.rank))
	local nextAt = pr.next
	if nextAt == nil and rank == progress.rank then
		nextAt = progress.next
	end
	refs.rank.Text = "Rang " .. tostring(rank) .. " von " .. tostring(PrestigeRules.MaxRank)
	local title = type(pr.title) == "string" and pr.title or ""
	refs.title.Text = title ~= "" and ("Titel: " .. title) or "Noch kein Titel – hol dir Rang 1 ab Level " .. tostring(PrestigeRules.Threshold(1)) .. "."
	if type(nextAt) == "number" then
		refs.next.Text = "Nächster Rang ab Level " .. MiniLocale.Number(nextAt) .. " (du bist Level " .. MiniLocale.Number(level) .. ")."
		UI.SetProgress(refs.fill, num(pr.pct, progress.pct))
	else
		refs.next.Text = "Höchster Rang erreicht – du bist eine Auto-Legende!"
		UI.SetProgress(refs.fill, 1)
	end
	local income = num(pr.incomeBonus, PrestigeRules.IncomeBonus({ level = level }))
	local discount = num(pr.discount, 0)
	refs.bonus.Text = "Aktive Boni: +" .. MiniLocale.Percent(income - 1) .. " auf alle Einnahmen · " .. MiniLocale.Percent(discount) .. " Rabatt im Autohaus"

	local claimedSet = {}
	for _, r in ipairs(type(pr.claimed) == "table" and pr.claimed or {}) do
		claimedSet[r] = true
	end
	local claimableSet = {}
	local nClaimable = 0
	for _, r in ipairs(type(pr.claimable) == "table" and pr.claimable or {}) do
		claimableSet[r] = true
		nClaimable += 1
	end
	local nextClaim = type(pr.nextClaim) == "number" and pr.nextClaim or nil
	refs.rewardsInfo.Text = nClaimable > 0 and (tostring(nClaimable) .. " Belohnung(en) warten auf dich – in Reihenfolge abholen.")
		or "Belohnungen holst du je Rang einmal ab, in Reihenfolge."

	local list = GameConfig.Prestige.Rewards
	refs.rewards:Ensure(#list)
	for i, r in ipairs(list) do
		local item = refs.rewards.items[i]
		item.rank = r.rank
		item.name.Text = "Rang " .. tostring(r.rank) .. " · " .. tostring(r.title) .. " (ab Level " .. MiniLocale.Number(PrestigeRules.Threshold(r.rank) or 0) .. ")"
		item.sub.Text = rewardText(r)
		local claimed = claimedSet[r.rank] == true
		local claimable = claimableSet[r.rank] == true and (nextClaim == nil or nextClaim == r.rank)
		item.claimable = claimable
		if claimed then
			item.button.Text = "Abgeholt ✓"
			UI.SetEnabled(item.button, false)
		elseif claimable then
			item.button.Text = "Abholen"
			UI.SetEnabled(item.button, true, T.green)
		elseif claimableSet[r.rank] then
			item.button.Text = "Erst Rang " .. tostring(nextClaim)
			UI.SetEnabled(item.button, false)
		else
			item.button.Text = "Ab Level " .. tostring(PrestigeRules.Threshold(r.rank) or "?")
			UI.SetEnabled(item.button, false)
		end
		item.name.TextColor3 = (claimed or claimable) and T.text or T.muted
	end
end

-- mini_notice { kind = "prestige", reached = true | claimed = true }
function PrestigeUI.OnNotice(data)
	if type(data) ~= "table" or data.kind ~= "prestige" then
		return
	end
	-- Den Server-Toast zeigt 2.4.0 selbst; hier nur der Effekt am Abzeichen und die Tab-Aktualisierung
	PrestigeUI.Flash()
	if UI and UI.IsOpen and UI.CurrentTab == "prestige" and latest then
		PrestigeUI.Render(latest)
	end
end

function PrestigeUI.Hud()
	return hud.gui, hud
end

-- Unterkante des Abzeichens (in Pixeln ab der Oberkante der ScreenGui, Inset eingerechnet); 0 ohne Abzeichen.
-- Hinweis-/Freischaltungskarten (TutorialUI, UnlocksUI) legen sich darunter – auch wenn das Abzeichen auf schmalen
-- Bildschirmen unter die 2.4.0-Leiste (y 60) rückt.
function PrestigeUI.HudBottom(): number
	local gui, frame = hud.gui, hud.frame
	if not gui or not frame or not gui.Parent then
		return 0
	end
	local ok, bottom = pcall(function()
		return frame.AbsolutePosition.Y - gui.AbsolutePosition.Y + frame.AbsoluteSize.Y
	end)
	if ok and type(bottom) == "number" and bottom == bottom and bottom > 0 then
		return bottom
	end
	return frame.Position.Y.Offset + PrestigeUI.HudHeight
end

-- Oberkante für Karten oben rechts: unter dem Abzeichen UND unter der Toast-Zone (2.4.0-Toast 330 × 60 zentriert
-- ab UI.ToastTop bzw. y 62; auf Bildschirmen unter ≈ 960 px überlappen Toast und rechte Karte).
PrestigeUI.ToastHeight = 60
PrestigeUI.CardGap = 8
function PrestigeUI.OverlayTop(): number
	local top = PrestigeUI.HudBottom() + PrestigeUI.CardGap
	-- Bargeld-Abzeichen des Tycoons (TycoonClient) hängt unter dem Prestige-Abzeichen: Karten darunter legen
	-- (auf schmalen Bildschirmen rückt beides unter die 2.4.0-Leiste; HudBottom ist 0, solange es unsichtbar ist)
	local okT, tyBottom = pcall(function()
		local node = script.Parent:FindFirstChild("TycoonClient")
		return node and require(node).HudBottom() or 0
	end)
	if okT and type(tyBottom) == "number" and tyBottom == tyBottom and tyBottom > 0 then
		top = math.max(top, tyBottom + PrestigeUI.CardGap)
	end
	local toastTop = 62
	if UI and type(UI.ToastTop) == "function" then
		local ok, t = pcall(UI.ToastTop)
		if ok and type(t) == "number" and t == t then
			toastTop = t
		end
	end
	return math.max(top, toastTop + PrestigeUI.ToastHeight + PrestigeUI.CardGap)
end

---------------------------------------------------------------- Freiräume der 2.4.0-Oberfläche
-- Alle Phase-4-Karten (Tutorial, Hinweise, Freischaltungen, Missionen) liegen UNTER dem 2.4.0-UI (DisplayOrder 16–19)
-- und halten dessen Bedienelemente frei: die HUD-Leiste unten (GarageClient: 132 px hoch, 6 px Rand) und die
-- Fahrzeugknöpfe E/F/H unten links (bis 3 Zeilen à 42 px, Unterkante 150 px über dem Rand, 360 px breit bei x 12).
-- Koordinaten wie AbsolutePosition in einer ScreenGui mit IgnoreGuiInset = false (w × h = deren AbsoluteSize).
PrestigeUI.GarageHud = 138
PrestigeUI.GarageGap = 8
PrestigeUI.VehicleLeft = 12
PrestigeUI.VehicleWidth = 360
PrestigeUI.VehicleBottom = 150
PrestigeUI.VehicleRow = 42
PrestigeUI.VehicleRows = 3
PrestigeUI.ScreenMargin = 8

-- Bereich der Fahrzeugknöpfe (immer in voller Höhe reserviert, damit eine Karte nicht erst nach dem Auftauchen weicht)
function PrestigeUI.VehicleZone(w: number, h: number): (number, number, number, number)
	local x0 = PrestigeUI.VehicleLeft
	local x1 = x0 + math.min(PrestigeUI.VehicleWidth, math.max(0, w - 24))
	local y1 = h - PrestigeUI.VehicleBottom
	local y0 = y1 - PrestigeUI.VehicleRows * PrestigeUI.VehicleRow
	return x0, y0, x1, y1
end

-- Unterste erlaubte Kante einer Karte (über der 2.4.0-HUD-Leiste)
function PrestigeUI.FreeBottom(h: number): number
	return h - PrestigeUI.GarageHud - PrestigeUI.GarageGap
end

-- Schneidet das Rechteck (x, y, cw × ch) die HUD-Leiste oder die Fahrzeugknöpfe?
function PrestigeUI.HitsGarage(w: number, h: number, x: number, y: number, cw: number, ch: number): boolean
	if y + ch > PrestigeUI.FreeBottom(h) + 0.5 then
		return true
	end
	local g = PrestigeUI.GarageGap
	local zx0, zy0, zx1, zy1 = PrestigeUI.VehicleZone(w, h)
	return x < zx1 + g and x + cw > zx0 - g and y < zy1 + g and y + ch > zy0 - g
end

-- Verschiebt eine Karte (linke obere Ecke x, y; Größe cw × ch) so wenig wie möglich aus HUD-Leiste und Fahrzeugknöpfen:
-- erst über die Leiste, dann rechts neben die Knöpfe, sonst darüber. Liefert x, y.
function PrestigeUI.FreeRect(w: number, h: number, x: number, y: number, cw: number, ch: number): (number, number)
	local m = PrestigeUI.ScreenMargin
	local bottom = PrestigeUI.FreeBottom(h)
	if y + ch > bottom then
		y = math.max(m, bottom - ch)
	end
	if not PrestigeUI.HitsGarage(w, h, x, y, cw, ch) then
		return x, y
	end
	local g = PrestigeUI.GarageGap
	local _, zy0, zx1 = PrestigeUI.VehicleZone(w, h)
	local rx = zx1 + g
	if rx + cw <= w - PrestigeUI.VehicleLeft then
		return math.max(x, rx), y
	end
	if zy0 - g - ch >= m then
		return x, zy0 - g - ch
	end
	return math.max(rx, w - PrestigeUI.VehicleLeft - cw), y
end

-- Niedrige Bildschirme (Handy quer, ScreenGui-Höhe < CompactHeight): zwischen Toast-Zone (bis y 130) und HUD-Leiste
-- bleiben ~80 px. Karten oben werden dann kompakt (kleinere Schrift, weniger Rand, Text höchstens 2 Zeilen) und
-- stehen einzeln (eine wartet, solange die andere zu sehen ist).
PrestigeUI.CompactHeight = 450
PrestigeUI.CompactTextSize = 13
PrestigeUI.CompactLines = 2

function PrestigeUI.IsCompact(h: number): boolean
	return h > 0 and h < PrestigeUI.CompactHeight
end

-- c = { padding = UIPadding, list = UIListLayout, title = TextLabel, text = TextLabel, titleSize, textSize, padX, padY, gap }
function PrestigeUI.StyleCard(c: any, small: boolean)
	if type(c) ~= "table" or not c.title or not c.text then
		return
	end
	c.title.TextSize = small and math.max(14, c.titleSize - 2) or c.titleSize
	c.text.TextSize = small and PrestigeUI.CompactTextSize or c.textSize
	if c.padding then
		c.padding.PaddingTop = UDim.new(0, small and 6 or c.padY)
		c.padding.PaddingBottom = UDim.new(0, small and 6 or c.padY)
		c.padding.PaddingLeft = UDim.new(0, small and 10 or c.padX)
		c.padding.PaddingRight = UDim.new(0, small and 10 or c.padX)
	end
	if c.list then
		c.list.Padding = UDim.new(0, small and 2 or c.gap)
	end
	if small then
		c.text.AutomaticSize = Enum.AutomaticSize.None
		c.text.Size = UDim2.new(1, 0, 0, math.ceil(PrestigeUI.CompactLines * PrestigeUI.CompactTextSize * 1.2))
		c.text.TextTruncate = Enum.TextTruncate.AtEnd
	else
		c.text.AutomaticSize = Enum.AutomaticSize.Y
		c.text.Size = UDim2.new(1, 0, 0, 0)
		c.text.TextTruncate = Enum.TextTruncate.None
	end
end

-- Sofort neu prüfen (MiniClient.RefreshOverlays: 2.4.0-Dialog/Tablet/Panel auf oder zu), nicht erst im nächsten Takt
function PrestigeUI.Refresh()
	if hud.gui then
		hud.gui.Enabled = hudShouldShow()
	end
end

return PrestigeUI
