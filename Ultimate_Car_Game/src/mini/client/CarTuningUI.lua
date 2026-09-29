-- CarTuningUI: Abschnitt "Mein Auto tunen" im Tab "tuning" (von TuningUI eingebettet).
-- Leistung in Stufen (Motor, Getriebe, Reifen, Fahrwerk 0..5, Nitro 0..3) und Optik (Lack, Felgen,
-- Unterbodenlicht, Spoiler) mit Live-Vorschau. Die Optik-Auswahl ist nur lokal, bis "Übernehmen" sie sendet.
-- Absichten: mini_car_tune {id, part, level = gesehene Stufe}, mini_car_style {id, paint, rims, glow, spoiler}.
-- Preise und Grenzen prüft der Server; angezeigt werden sie aus dem Snapshot (cars[i].tuneCost, styleCost).
--
-- Einbettung (TuningUI):  CarTuningUI.Build(page, ctx, order) -> Frame;  CarTuningUI.Render(s);  CarTuningUI.Step()
local CarTuningUI = {}

local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local Lib = require(script.Parent:WaitForChild("DealerUI")).Lib

local UI, Remote, T, ctx
local refs = {}
local state
local selectedId -- ausgewähltes Auto
local baseline -- gespeicherte Optik des ausgewählten Autos (zuletzt gesehen)
local pending -- lokale Auswahl {paint, rims, glow, spoiler}

local SWATCH = 44

local function num(v)
	return Lib.Num(v)
end

local function styleOf(car)
	return {
		paint = num(car and car.paint) or 0,
		rims = num(car and car.rims) or 0,
		glow = num(car and car.glow) or 0,
		spoiler = car and car.spoiler == true or false,
	}
end

local function sameStyle(a, b)
	return a and b and a.paint == b.paint and a.rims == b.rims and a.glow == b.glow and a.spoiler == b.spoiler
end

local function selectedCar()
	return state and selectedId and Lib.FindCar(state, selectedId) or nil
end

---------------------------------------------------------------- Bausteine
local function swatchGrid(parent, order)
	local f = UI.Frame(parent, { BackgroundTransparency = 1, LayoutOrder = order or 0 })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0, SWATCH, 0, SWATCH)
	gl.CellPadding = UDim2.new(0, 8, 0, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = f
	return f
end

-- Farbfeld (lokale Auswahl, keine Entprellung nötig: sendet nichts)
local function swatch(parent, index, color, name, onPick, label)
	local b = Instance.new("TextButton")
	b.Name = "Farbe_" .. index
	b.AutoButtonColor = true
	b.BackgroundColor3 = color or T.bg
	b.BorderSizePixel = 0
	b.Size = UDim2.new(0, SWATCH, 0, SWATCH)
	b.LayoutOrder = index + 1
	b.Font = UI.FontBold
	b.TextSize = 13
	b.TextColor3 = T.text
	b.Text = label or ""
	b:SetAttribute("colorName", name)
	UI.Corner(b, 8)
	local stroke = Instance.new("UIStroke")
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Color = T.yellow
	stroke.Thickness = 3
	stroke.Enabled = false
	stroke.Parent = b
	b.Activated:Connect(function()
		onPick(index)
	end)
	b.Parent = parent
	return { button = b, stroke = stroke, index = index, name = name }
end

local function markSelected(list, index)
	for _, sw in ipairs(list or {}) do
		sw.stroke.Enabled = sw.index == index
	end
end

---------------------------------------------------------------- Aufbau
local function refreshPreview()
	local car = selectedCar()
	if not car or not refs.preview then
		return
	end
	refs.preview:Set(Lib.CarBody(state, car), Lib.Style(state, car, pending))
end

local function pickerNames()
	local pal = Lib.Palettes(state)
	local function nameOf(list, i, zeroText)
		if i == 0 then
			return zeroText
		end
		return list[i] and list[i].name or zeroText
	end
	return pal, nameOf
end

local function renderStyle()
	local car = selectedCar()
	if not car or not pending then
		return
	end
	local pal, nameOf = pickerNames()
	markSelected(refs.paintSwatches, pending.paint)
	markSelected(refs.rimSwatches, pending.rims)
	markSelected(refs.glowSwatches, pending.glow)
	refs.paintName.Text = "Lackfarbe: " .. nameOf(pal.paint, pending.paint, "Werksfarbe")
	refs.rimName.Text = "Felgen: " .. nameOf(pal.rims, pending.rims, "Serie")
	refs.glowName.Text = "Unterbodenlicht: " .. nameOf(pal.glow, pending.glow, "Aus")
	refs.spoiler.Text = pending.spoiler and "Spoiler: An" or "Spoiler: Aus"
	UI.SetEnabled(refs.spoiler, not car.locked, pending.spoiler and T.green or T.card)
	local changed = not sameStyle(pending, baseline)
	local cost = num(car.styleCost) or num(state and state.carStyleCost)
	refs.apply.Text = changed and (cost and ("Übernehmen · " .. MiniLocale.Credits(cost)) or "Übernehmen") or "Keine Änderung"
	UI.SetEnabled(refs.apply, changed and not car.locked and (not cost or (num(state.credits) or 0) >= cost), T.green)
	UI.SetEnabled(refs.reset, changed, T.card)
	refreshPreview()
end

local function setPending(field, value)
	if not pending then
		return
	end
	local car = selectedCar()
	if not car or car.locked then
		return
	end
	pending[field] = value
	renderStyle()
end

local function buildSwatches(parent, list, field, withOff)
	local out = {}
	if withOff then
		table.insert(out, swatch(parent, 0, T.bg, "Aus", function(i)
			setPending(field, i)
		end, "Aus"))
	end
	for i, entry in ipairs(list) do
		table.insert(out, swatch(parent, i, entry.color, entry.name, function(idx)
			setPending(field, idx)
		end))
	end
	return out
end

-- Palettenfelder neu anlegen, wenn sich die Palette ändert (z. B. erste Paletten vom Server)
local builtPalette
local function ensureSwatches()
	local pal = Lib.Palettes(state)
	if pal == builtPalette then
		return
	end
	builtPalette = pal
	for _, key in ipairs({ "paintGrid", "rimGrid", "glowGrid" }) do
		for _, child in ipairs(refs[key]:GetChildren()) do
			if child:IsA("GuiObject") then
				child:Destroy()
			end
		end
	end
	refs.paintSwatches = buildSwatches(refs.paintGrid, pal.paint, "paint", false)
	refs.rimSwatches = buildSwatches(refs.rimGrid, pal.rims, "rims", false)
	refs.glowSwatches = buildSwatches(refs.glowGrid, pal.glow, "glow", true)
end

local function selectCar(id)
	selectedId = id
	local car = selectedCar()
	baseline = car and styleOf(car) or nil
	pending = car and styleOf(car) or nil
end

local function cycle(dir)
	local cars = Lib.Cars(state)
	if #cars < 2 then
		return
	end
	local index = 1
	for i, car in ipairs(cars) do
		if car.id == selectedId then
			index = i
		end
	end
	index = (index - 1 + dir) % #cars + 1
	selectCar(cars[index].id)
	CarTuningUI.Render(state)
end

function CarTuningUI.Build(parent, c, order)
	ctx = c
	UI, Remote = c.UI, c.Remote
	T = UI.Theme
	refs = {}
	builtPalette = nil

	local root = UI.Frame(parent, { Name = "MeinAutoTunen", BackgroundTransparency = 1, LayoutOrder = order or 0 })
	UI.List(root, 12)
	refs.root = root

	-- Auto, Vorschau, Fahrwerte
	local head = UI.Card(root, 1)
	UI.Title(head, "Mein Auto tunen", 1)
	UI.Small(head, "Leistung und Optik deines eigenen Autos. Änderungen wirken sofort auf das Auto, das du fährst.", 2)
	refs.empty = UI.Small(head, "Du hast noch kein eigenes Auto. Im Autohaus findest du dein erstes.", 3)
	refs.toDealer = UI.Button(head, "Zum Autohaus", T.blue, function()
		if UI.Pages and UI.Pages.dealer then
			UI.Show("dealer")
		else
			Remote.Send("mini_travel", { key = "dealer" })
		end
	end, { Name = "ZumAutohaus", LayoutOrder = 4 })
	local selector = UI.Frame(head, { BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, UI.MinTouch), LayoutOrder = 5 })
	refs.selector = selector
	refs.prev = UI.Button(selector, "◀", T.card, function()
		cycle(-1)
	end, { Name = "Zurueck", Size = UDim2.new(0, UI.MinTouch, 0, UI.MinTouch) })
	refs.next = UI.Button(selector, "▶", T.card, function()
		cycle(1)
	end, { Name = "Weiter", Size = UDim2.new(0, UI.MinTouch, 0, UI.MinTouch), Position = UDim2.new(1, -UI.MinTouch, 0, 0) })
	refs.carName = UI.Label(selector, "", {
		Font = UI.FontBold, TextSize = 17, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -2 * UI.MinTouch - 16, 1, 0),
		Position = UDim2.new(0, UI.MinTouch + 8, 0, 0), TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center,
		TextWrapped = false, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.preview = Lib.Preview(head, 150, 6)
	refs.status = UI.Label(head, "", { TextSize = 14, LayoutOrder = 7 })
	refs.stats = Lib.StatBlock(head, 8)

	-- Leistung
	local perf = UI.Card(root, 2)
	refs.perf = perf
	UI.Title(perf, "Leistung", 1)
	UI.Small(perf, "Jede Stufe kostet mehr, je wertvoller das Auto ist.", 2)
	refs.parts = {}
	for i, key in ipairs(Lib.PartKeys) do
		local row, left, right = UI.Row(perf, 2 + i)
		row.Name = "Teil_" .. key
		local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
		UI.Small(left, Lib.PartDesc[key], 2)
		local _, fill = UI.Progress(left, key == "nitro" and T.purple or T.blue, 3)
		local item = { key = key, name = name, fill = fill }
		item.button = UI.Button(right, "", T.blue, function()
			local car = selectedCar()
			if car and item.level ~= nil then
				Remote.Send("mini_car_tune", { id = car.id, part = key, level = item.level })
			end
		end, { Name = "Tune_" .. key, TextSize = 14 })
		refs.parts[key] = item
	end

	-- Optik
	local look = UI.Card(root, 3)
	refs.look = look
	UI.Title(look, "Optik", 1)
	UI.Small(look, "Wähle Farben und sieh dir das Ergebnis oben in der Vorschau an. Erst „Übernehmen“ ändert dein Auto.", 2)
	refs.paintName = UI.Label(look, "Lackfarbe", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 3 })
	refs.paintGrid = swatchGrid(look, 4)
	refs.rimName = UI.Label(look, "Felgen", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 5 })
	refs.rimGrid = swatchGrid(look, 6)
	refs.glowName = UI.Label(look, "Unterbodenlicht", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 7 })
	refs.glowGrid = swatchGrid(look, 8)
	refs.spoiler = UI.Button(look, "Spoiler: Aus", T.card, function()
		if pending then
			setPending("spoiler", not pending.spoiler)
		end
	end, { Name = "Spoiler", LayoutOrder = 9 })
	local buttons = Lib.Grid(look, 10)
	refs.apply = UI.Button(buttons, "Übernehmen", T.green, function()
		local car = selectedCar()
		if not car or not pending or sameStyle(pending, baseline) then
			return
		end
		Remote.Send("mini_car_style", { id = car.id, paint = pending.paint, rims = pending.rims, glow = pending.glow, spoiler = pending.spoiler })
	end, { Name = "Uebernehmen", LayoutOrder = 1, TextSize = 14 })
	refs.reset = UI.Button(buttons, "Zurücksetzen", T.card, function()
		if baseline then
			pending = table.clone(baseline)
			renderStyle()
		end
	end, { Name = "Zuruecksetzen", LayoutOrder = 2, TextSize = 14 })
	return root
end

-- Ausgewähltes Auto (für Tests und DealerUI "Tunen")
function CarTuningUI.Selected()
	return selectedId, pending and table.clone(pending) or nil
end

function CarTuningUI.Select(id)
	selectCar(id)
	if state then
		CarTuningUI.Render(state)
	end
end

function CarTuningUI.Render(s)
	if type(s) ~= "table" or not refs.root then
		return
	end
	state = s
	local cars = Lib.Cars(s)
	-- Auswahl: Wunsch aus "Meine Autos" > bisherige Auswahl > aktives Auto > erstes Auto
	if Lib.TuneRequest ~= nil then
		local want = Lib.TuneRequest
		Lib.TuneRequest = nil
		if Lib.FindCar(s, want) then
			selectCar(want)
		end
	end
	if not selectedCar() then
		local active = Lib.FindCar(s, Lib.ActiveId(s))
		selectCar(active and active.id or (cars[1] and cars[1].id) or nil)
	end
	local car = selectedCar()
	local has = car ~= nil
	refs.empty.Visible = not has
	refs.toDealer.Visible = not has
	refs.selector.Visible = has
	refs.preview.frame.Visible = has
	refs.status.Visible = has
	refs.stats.root.Visible = has
	refs.perf.Visible = has
	refs.look.Visible = has
	if not has then
		return
	end
	-- gespeicherte Optik geändert (Server hat übernommen oder anderswo geändert): Auswahl nachziehen
	local saved = styleOf(car)
	if not sameStyle(saved, baseline) then
		baseline = saved
		pending = table.clone(saved)
	end

	refs.prev.Visible = #cars > 1
	refs.next.Visible = #cars > 1
	local index = 1
	for i, c in ipairs(cars) do
		if c.id == car.id then
			index = i
		end
	end
	refs.carName.Text = Lib.CarName(s, car) .. (#cars > 1 and (" (" .. index .. "/" .. #cars .. ")") or "")
	if car.locked then
		refs.status.Text = "Dieses Auto ist in einer Auktion und kann gerade nicht getunt werden."
		refs.status.TextColor3 = T.yellow
	elseif Lib.IsOut(s, car) then
		refs.status.Text = "Unterwegs · Änderungen wirken sofort."
		refs.status.TextColor3 = T.green
	else
		refs.status.Text = Lib.ActiveId(s) == car.id and "Aktives Auto · abgestellt" or "In der Garage"
		refs.status.TextColor3 = T.muted
	end
	refs.stats.Set(Lib.Stats(car), Lib.StatMaxima(s))

	local max = Lib.TuneMax(s)
	local costs = type(car.tuneCost) == "table" and car.tuneCost or (type(car.costs) == "table" and car.costs) or {}
	local credits = num(s.credits) or 0
	for _, key in ipairs(Lib.PartKeys) do
		local item = refs.parts[key]
		local level = num(car[key]) or 0
		local top = max[key] or 5
		item.level = level
		item.name.Text = Lib.PartNames[key] .. " · Stufe " .. level .. "/" .. top
		UI.SetProgress(item.fill, level / math.max(1, top))
		local cost = num(costs[key])
		if level >= top then
			item.button.Text = "Voll ausgebaut"
			UI.SetEnabled(item.button, false)
		else
			item.button.Text = cost and MiniLocale.Credits(cost) or ("Stufe " .. (level + 1))
			UI.SetEnabled(item.button, not car.locked and (not cost or credits >= cost), T.blue)
		end
	end

	ensureSwatches()
	renderStyle()
end

function CarTuningUI.Step() end

return CarTuningUI
