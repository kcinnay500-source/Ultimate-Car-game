-- PressUI: Schrottpresse (Klickfläche, Schrotthändler, Rebirth, 100 Upgrades).
-- Klicks werden gesammelt und etwa alle 0,5 s als Anzahl gesendet (mini_press_click). Die Anzeige interpoliert nur;
-- den echten Stand bestimmt der Server. Eigene Klicks lassen zusätzlich die Presse in der Stadt stampfen (CityClient).
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(Mini:WaitForChild("MiniConfig"))
local MiniCatalog = require(Mini:WaitForChild("MiniCatalog"))
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local PressRules = require(Mini:WaitForChild("PressRules"))

local PressUI = {}

local UI, Effects, Remote, City
local T
local refs = {}
local state = nil -- letzter Snapshot
local snapAt = 0
local localGain = 0 -- vorhergesagter Klick-Ertrag seit dem letzten Snapshot
local pending = 0 -- noch nicht gesendete Klicks
local combo, comboUntil = 1, 0
local clickWindowStart, clickWindowCount = 0, 0

local COMBO_MAX = MiniConfig.PressComboMax or 25
local COMBO_STEP = MiniConfig.PressComboStep or 0.25
local COMBO_WINDOW = MiniConfig.PressComboWindow or 1.8
local MAX_CPS = MiniConfig.MaxClicksPerSecond or 20
local BASE_CLICK = MiniConfig.PressBaseClick or 5
-- Snapshots kommen höchstens alle 0,5–1 s; bis zu 5 s weiter hochzählen, falls einer ausbleibt
local INTERPOLATE_SECONDS = 5

local function dec(n, places)
	local s = string.format("%." .. (places or 2) .. "f", n or 0)
	return (s:gsub("%.", ","))
end

local function effectText(u)
	if u.type == 0 or u.type == 3 then
		return "+" .. u.baseEffect .. " Klickstärke je Stufe"
	elseif u.type == 1 or u.type == 4 then
		return "+" .. dec(u.baseEffect * (MiniConfig.PressMachineEffectFactor or 0.35), 2) .. " Schrott/Sek. je Stufe"
	end
	return "+1 Ruf und +" .. math.max(1, math.floor(u.baseEffect * 0.5)) .. " Cr je Kauf"
end

local function buildCar(parent)
	local car = Instance.new("Frame")
	car.Name = "Schrottauto"
	car.BackgroundTransparency = 1
	car.Size = UDim2.new(0, 220, 0, 110)
	car.AnchorPoint = Vector2.new(0.5, 0.5)
	car.Position = UDim2.fromScale(0.5, 0.55)
	car.Parent = parent
	local body = Instance.new("Frame")
	body.BackgroundColor3 = Color3.fromRGB(150, 80, 50)
	body.BorderSizePixel = 0
	body.Size = UDim2.new(1, 0, 0, 45)
	body.Position = UDim2.new(0, 0, 0, 40)
	body.Parent = car
	UI.Corner(body, 14)
	local cabin = Instance.new("Frame")
	cabin.BackgroundColor3 = Color3.fromRGB(120, 65, 40)
	cabin.BorderSizePixel = 0
	cabin.Size = UDim2.new(0.5, 0, 0, 38)
	cabin.Position = UDim2.new(0.22, 0, 0, 8)
	cabin.Rotation = 4
	cabin.Parent = car
	UI.Corner(cabin, 10)
	local window = Instance.new("Frame")
	window.BackgroundColor3 = Color3.fromRGB(120, 170, 210)
	window.BackgroundTransparency = 0.4
	window.BorderSizePixel = 0
	window.Size = UDim2.new(0.8, 0, 0, 20)
	window.Position = UDim2.new(0.1, 0, 0, 7)
	window.Parent = cabin
	UI.Corner(window, 6)
	for _, x in ipairs({ 0.2, 0.8 }) do
		local wheel = Instance.new("Frame")
		wheel.BackgroundColor3 = Color3.fromRGB(25, 25, 28)
		wheel.BorderSizePixel = 0
		wheel.Size = UDim2.new(0, 42, 0, 42)
		wheel.AnchorPoint = Vector2.new(0.5, 0.5)
		wheel.Position = UDim2.new(x, 0, 0, 86)
		wheel.Parent = car
		UI.Corner(wheel, 21)
		local hub = Instance.new("Frame")
		hub.BackgroundColor3 = T.muted
		hub.BorderSizePixel = 0
		hub.Size = UDim2.new(0, 14, 0, 14)
		hub.AnchorPoint = Vector2.new(0.5, 0.5)
		hub.Position = UDim2.fromScale(0.5, 0.5)
		hub.Parent = wheel
		UI.Corner(hub, 7)
	end
	return car
end

local function onPress(inputPos)
	-- Lokal höchstens MaxClicksPerSecond zählen (der Server deckelt ohnehin)
	local t = os.clock()
	if t - clickWindowStart >= 1 then
		clickWindowStart, clickWindowCount = t, 0
	end
	if clickWindowCount >= MAX_CPS then
		return
	end
	clickWindowCount += 1
	pending += 1
	combo = (t < comboUntil) and math.min(COMBO_MAX, combo + COMBO_STEP) or 1
	comboUntil = t + COMBO_WINDOW
	local perClick = state and state.press and state.press.clickPower or BASE_CLICK
	local gain = perClick * combo
	localGain += gain

	local area = refs.area
	local x, y = 0.5, 0.4
	if inputPos and area.AbsoluteSize.X > 0 then
		x = math.clamp((inputPos.X - area.AbsolutePosition.X) / area.AbsoluteSize.X, 0.05, 0.95)
		y = math.clamp((inputPos.Y - area.AbsolutePosition.Y) / area.AbsoluteSize.Y, 0.1, 0.9)
	end
	Effects.Pop("+" .. MiniLocale.Number(gain), x, y)
	Effects.Sparks(x, y)
	Effects.Shake(refs.car)
	Effects.Click()
	if City and City.Stomp then
		City.Stomp()
	end
end

function PressUI.Build(page, ctx)
	UI, Effects, Remote, City = ctx.UI, ctx.Effects, ctx.Remote, ctx.City
	T = UI.Theme

	local press = UI.Card(page, 1)
	refs.scrap = UI.Label(press, "0 kg Schrott", { Font = UI.FontBig, TextSize = 26, TextColor3 = T.yellow, LayoutOrder = 3 })
	refs.stats = UI.Small(press, "", 4)
	UI.Small(press, "Tippe auf das Schrottauto. Jeder Tipp presst Schrott, schnelle Serien erhöhen die Combo bis ×" .. COMBO_MAX .. ".", 8)

	local area = Instance.new("TextButton")
	area.Name = "Presse"
	area.Text = ""
	area.AutoButtonColor = false
	area.BackgroundColor3 = T.bg
	area.BorderSizePixel = 0
	area.Size = UDim2.new(1, 0, 0, 170)
	area.LayoutOrder = 5
	area.ClipsDescendants = true
	area.Parent = press
	UI.Corner(area, 10)
	refs.area = area
	refs.car = buildCar(area)
	area.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			onPress(input.Position)
		end
	end)
	Effects.Init(area)

	refs.combo = UI.Small(press, "Combo ×1,00", 6)
	local _, comboFill = UI.Progress(press, T.yellow, 7)
	refs.comboFill = comboFill

	-- Schrotthändler
	local dealer = UI.Card(page, 2)
	UI.Title(dealer, "Schrotthändler", 1)
	UI.Small(dealer, "Verkaufe Schrott in festen Paketen gegen Credits. Credits lassen sich nicht in Schrott tauschen.", 2)
	local grid = UI.Frame(dealer, { BackgroundTransparency = 1, LayoutOrder = 3 })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -4, 0, UI.MinTouch + 6)
	gl.CellPadding = UDim2.new(0, 8, 0, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	refs.exchange = {}
	for i, amount in ipairs(MiniConfig.ScrapExchangePackages or {}) do
		refs.exchange[i] = UI.Button(grid, MiniLocale.Number(amount) .. " → " .. MiniLocale.Credits(PressRules.ExchangeCredits(amount)), T.green, function()
			Remote.Send("mini_press_exchange", { index = i })
		end, { LayoutOrder = i, TextSize = 14 })
	end

	-- Rebirth
	local rebirth = UI.Card(page, 3)
	UI.Title(rebirth, "Rebirth", 1)
	refs.rebirthText = UI.Small(rebirth, "", 2)
	local _, rebirthFill = UI.Progress(rebirth, T.purple, 3)
	refs.rebirthFill = rebirthFill
	refs.rebirthButton = UI.Button(rebirth, "Rebirth durchführen", T.purple, function()
		if not state or not state.press or not state.press.canRebirth then
			return
		end
		local expected = state.press.rebirths
		UI.Confirm(MiniLocale.T("rebirth_confirm", dec(state.press.nextRebirthMultiplier or 1, 2)), function()
			Remote.Send("mini_press_rebirth", { rebirths = expected })
		end, "Rebirth durchführen?", "Rebirth durchführen", T.purple)
	end, { LayoutOrder = 4 })

	-- Upgrades
	local ups = UI.Card(page, 4)
	UI.Title(ups, "Presse-Upgrades", 1)
	UI.Small(ups, "Werkzeuge erhöhen die Klickstärke, Maschinen und Mitarbeiter pressen automatisch. Jede Stufe erhöht zusätzlich alle Erträge um 0,25 %.", 2)
	refs.upgradeRows = {}
	for i, u in ipairs(MiniCatalog.PressUpgrades or {}) do
		local row, left, right = UI.Row(ups, 2 + i)
		local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
		UI.Small(left, (MiniCatalog.PressUpgradeTypeLabel and MiniCatalog.PressUpgradeTypeLabel[u.type] or "") .. " · " .. effectText(u), 2)
		local button = UI.Button(right, "", T.green, function()
			if state and state.press then
				Remote.Send("mini_press_buy", { id = u.id, level = (state.press.levels and state.press.levels[u.id]) or 0 })
			end
		end, { TextSize = 14 })
		refs.upgradeRows[i] = { row = row, name = name, button = button, u = u }
	end
end

-- Aktuelle Anzeige: Server-Wert + Maschinen seit dem Snapshot + vorhergesagte Klicks
function PressUI.DisplayScrap()
	if not state or not state.press then
		return 0
	end
	local p = state.press
	return (p.scrap or 0) + (p.machinePerSecond or 0) * math.min(INTERPOLATE_SECONDS, os.clock() - snapAt) + localGain
end

function PressUI.OnSnapshot(s)
	if type(s.press) ~= "table" then
		return
	end
	state = s
	snapAt = os.clock()
	-- Bereits gesendete Klicks sind im Server-Wert enthalten; nur noch nicht gesendete bleiben vorhergesagt
	localGain = pending * ((s.press.clickPower or BASE_CLICK) * combo)
end

function PressUI.Flush()
	if pending > 0 and Remote then
		Remote.SendRaw("mini_press_click", { count = pending })
		pending = 0
	end
end

-- Jedes Frame (nur wenn sichtbar): Zahl und Combo aktualisieren
function PressUI.Step()
	if not state or not refs.scrap then
		return
	end
	if os.clock() > comboUntil then
		combo = 1
	end
	refs.scrap.Text = MiniLocale.Scrap(PressUI.DisplayScrap())
	refs.combo.Text = "Combo ×" .. dec(combo, 2)
	UI.SetProgress(refs.comboFill, combo / COMBO_MAX)
end

function PressUI.Render(s)
	local p = s.press
	if not p then
		return
	end
	refs.stats.Text = MiniLocale.Number(p.clickPower or 0) .. " pro Klick · " .. MiniLocale.Number(p.machinePerSecond or 0) .. " pro Sek. · Gesamt-Multiplikator ×" .. dec(p.globalMultiplier or 1, 3)

	for i, amount in ipairs(MiniConfig.ScrapExchangePackages or {}) do
		if refs.exchange[i] then
			UI.SetEnabled(refs.exchange[i], (p.scrap or 0) >= amount, T.green)
		end
	end

	refs.rebirthText.Text = string.format(
		"Rebirths: %d · Schrott-Multiplikator ×%s. Nächstes Rebirth ab %s Schrott in diesem Durchlauf (aktuell %s). Setzt Schrott und Presse-Upgrades zurück; Werkstatt, Credits, Level, Tuning, Meilensteine und die Bestenliste bleiben.",
		p.rebirths or 0, dec(p.rebirthMultiplier or 1, 2), MiniLocale.Number(p.rebirthThreshold or 0), MiniLocale.Number(p.runScrap or 0)
	)
	UI.SetProgress(refs.rebirthFill, (p.runScrap or 0) / math.max(1, p.rebirthThreshold or 1))
	UI.SetEnabled(refs.rebirthButton, p.canRebirth == true, T.purple)

	local scrap = PressUI.DisplayScrap()
	local levels = p.levels or {}
	for _, r in ipairs(refs.upgradeRows) do
		local lvl = levels[r.u.id] or 0
		local cost = PressRules.UpgradeCost(r.u, lvl)
		r.name.Text = r.u.index .. ". " .. r.u.name .. " · Stufe " .. lvl
		r.button.Text = MiniLocale.Number(cost) .. " Schrott"
		UI.SetEnabled(r.button, scrap >= cost, T.green)
	end
end

return PressUI
