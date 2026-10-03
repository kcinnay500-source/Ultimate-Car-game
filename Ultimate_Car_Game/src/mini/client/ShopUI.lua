-- ShopUI: Tab "shop" (Shop & Monetarisierung, docs/PHASE4_CONTRACT.md §9, Meilenstein 8). Ersetzt die alte Seite
-- „Game Passes“. Abschnitte: Credits (Pakete -> shop_prompt), Autos (DLC-Autos mit 3D-Vorschau wie im Autohaus,
-- Robux-Knopf -> shop_prompt, Credits-Knopf -> shop_buy mit Level), Kosmetik (Raster je Platz mit Vorschau-
-- Kacheln: Folierungen als kleines Streifen-/Karo-/Flammenmuster; Kaufen -> shop_buy, Anlegen/Ablegen ->
-- shop_equip; Belohnungen zeigen, wo es sie gibt), Pässe (Neon-Paket, Werkstatt-Deko -> shop_prompt; die
-- Presse-Pässe 2× Schrott und Schrottpresse+ -> mini_pass_prompt wie bisher) und eine Richtlinien-Fußzeile.
-- Der Client zeigt nur an und sendet Absichten: shop_prompt {product}, shop_buy {item}, shop_equip {slot, item},
-- mini_pass_prompt {pass}. Preise, Level, Guthaben, Besitz prüft der Server (ShopRules); Produkt-/Pass-Ids 0 =
-- „noch nicht eingerichtet“ (Knopf aus, kein Prompt). Keine Zufallskisten, kein Pay-to-win (Texte: GameConfig.Shop).
-- Snapshot-Felder (§11): shop { owned[], equipped{}, dlcCars[], passes{ [key]=bool }, catalog (nur full, wird
-- zwischengespeichert) }, passes { doubleScrap, pressPlus, *Configured } (MiniPasses), credits, level.
-- Mobile: Karten in voller Breite, Raster mit zwei Spalten (passt bei 338 px Panelbreite), Knöpfe ≥ 44 px bzw. 36 px
-- in den kleinen Kosmetik-Kacheln.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local Mini = Shared:WaitForChild("Mini")
local MiniConfig = require(Mini:WaitForChild("MiniConfig"))
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local Lib = require(script.Parent:WaitForChild("DealerUI")).Lib

local ShopUI = {}

local UI, Remote, T, ctx
local refs = {}
local state = nil -- letzter Snapshot
local catalog = nil -- zuletzt gesehener Katalog (nur in full-Snapshots)
local builtSig = nil -- Signatur (Ids + ready) des Katalogs, für den die Karten gebaut wurden
local lookup = { products = {}, cars = {}, cos = {}, passes = {} } -- aktuelle Katalogeinträge nach Schlüssel
local prices = {} -- ["product:<id>" | "pass:<id>"] = Robux-Preis aus MarketplaceService (nur bei Erfolg)
local pricePending = {}

local POLICY = "Alle Inhalte sind auch ohne Robux erreichbar. Keine Zufallskisten."
local HINT = "Alles im Shop gibt es auch für Credits oder als Belohnung – ganz ohne Robux."
local NOT_READY = "Noch nicht eingerichtet"
-- Kosmetik-Karte: Vorschau 44 + Name 18 + Info 30 + zwei Knöpfe à UI.MinTouch (44) = 180, dazu 4 Abstände à 4 px
-- (UI.List) und Innenabstand 2 × 8 px (UI.Padding) = 212 px
local COS_CARD_H = 212
local SLOT_ORDER = { "wrap", "rims", "horn", "trail" }
local SLOT_NAMES = { wrap = "Folierungen", rims = "Felgen-Sets", horn = "Hupen", trail = "Reifenspuren" }

---------------------------------------------------------------- Hilfen
local function num(v)
	return type(v) == "number" and v == v and v or nil
end

local function dec(n)
	local s = tostring(n)
	return (s:gsub("%.", ","))
end

local function credits(n)
	return MiniLocale.Credits(n or 0)
end

local function rgb(t, fallback)
	if typeof(t) == "Color3" then
		return t
	end
	if type(t) == "table" and num(t[1]) and num(t[2]) and num(t[3]) then
		return Color3.fromRGB(math.clamp(t[1], 0, 255), math.clamp(t[2], 0, 255), math.clamp(t[3], 0, 255))
	end
	return fallback
end

local function passValue(name, field, fallback)
	local passes = MiniConfig.GamePasses
	local entry = passes and passes[name]
	local v = entry and entry[field]
	return v ~= nil and v or fallback
end

local function setOf(list)
	local out = {}
	if type(list) == "table" then
		for _, id in ipairs(list) do
			out[id] = true
		end
	end
	return out
end

-- Produkt (Developer Product) zu einer Kosmetik-/Modell-Id: einzelnes Produkt, das genau diese Id gewährt
local function productFor(kind, id)
	if not catalog then
		return nil
	end
	for _, p in ipairs(catalog.products or {}) do
		if p.kind == kind and type(p.grants) == "table" then
			local list = kind == "car" and p.grants.cars or p.grants.cosmetics
			if type(list) == "table" and #list == 1 and list[1] == id then
				return p
			end
		end
	end
	return nil
end

local function clear(frame)
	for _, x in ipairs(frame:GetChildren()) do
		if x:IsA("GuiObject") then
			x:Destroy()
		end
	end
end

local function grid(parent, order, height)
	local f = UI.Frame(parent, { BackgroundTransparency = 1, LayoutOrder = order or 0 })
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -4, 0, height or UI.MinTouch)
	gl.CellPadding = UDim2.new(0, 8, 0, 8)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = f
	return f
end

local function fixed(parent, name, height, order, color)
	local f = UI.Frame(parent, {
		Name = name, Size = UDim2.new(1, 0, 0, height), AutomaticSize = Enum.AutomaticSize.None,
		BackgroundTransparency = color and 0 or 1, LayoutOrder = order or 0,
	})
	if color then
		f.BackgroundColor3 = color
	end
	return f
end

-- Echter Robux-Preis (MarketplaceService:GetProductInfoAsync, pcall, im Hintergrund): nie ein ausgedachter Wert.
-- Bis er da ist (oder wenn die Abfrage scheitert) steht nur „Mit Robux“ ohne Zahl; Roblox zeigt den
-- verbindlichen Preis ohnehin im Kaufdialog.
local function priceKey(p)
	if type(p) ~= "table" or not p.ready then
		return nil, nil, nil
	end
	if num(p.productId) and p.productId > 0 then
		return "product:" .. p.productId, p.productId, "Product"
	end
	if num(p.id) and p.id > 0 then
		return "pass:" .. p.id, p.id, "GamePass"
	end
	return nil, nil, nil
end

local function robuxPrice(p)
	local key, id, infoType = priceKey(p)
	if not key then
		return nil
	end
	if prices[key] == nil and not pricePending[key] then
		pricePending[key] = true
		task.defer(function() -- nie mitten im Aufbau/Rendern zurückkehren (kein verschachteltes Render)
			local ok, info = pcall(function()
				return game:GetService("MarketplaceService"):GetProductInfoAsync(id, Enum.InfoType[infoType])
			end)
			local price = ok and type(info) == "table" and num(info.PriceInRobux) or nil
			prices[key] = (price and price > 0) and math.floor(price) or false
			if prices[key] and state then
				ShopUI.Render(state)
			end
		end)
	end
	return prices[key] or nil
end

-- Robux-Knopftext: nur mit dem echten Preis eine Zahl, sonst „Mit Robux“
local function robuxText(p)
	if not p or not p.ready then
		return NOT_READY
	end
	local price = robuxPrice(p)
	return price and ("Mit Robux (" .. price .. ")") or "Mit Robux"
end

---------------------------------------------------------------- Vorschau-Kacheln (Kosmetik)
-- Folierung: kleines Muster aus Frames (Streifen, Karo, Flammen, Wellen, Lorbeer, Fläche) auf Lackgrau
local function wrapSwatch(parent, style)
	local base = fixed(parent, "Swatch", 44, 1, Color3.fromRGB(120, 128, 140))
	UI.Corner(base, 6)
	local c1 = rgb(style.color, Color3.fromRGB(236, 238, 240))
	local c2 = rgb(style.color2, Color3.fromRGB(28, 30, 34))
	local pattern = style.pattern or "stripes"
	local function piece(name, pos, size, color)
		local f = Instance.new("Frame")
		f.Name = name
		f.BackgroundColor3 = color
		f.BorderSizePixel = 0
		f.Position = pos
		f.Size = size
		f.Parent = base
		return f
	end
	if pattern == "checker" then
		for r = 0, 1 do
			for c = 0, 5 do
				piece("Karo", UDim2.new(c / 6, 0, r / 2, 0), UDim2.new(1 / 6, 0, 0.5, 0), ((r + c) % 2 == 0) and c1 or c2)
			end
		end
	elseif pattern == "flames" then
		for i = 0, 4 do
			local h = 0.9 - i * 0.15
			piece("Flamme", UDim2.new(0.05 + i * 0.18, 0, 1 - h, 0), UDim2.new(0.14, 0, h, 0), (i % 2 == 0) and c1 or c2)
		end
	elseif pattern == "waves" then
		for i = 0, 5 do
			local up = (i % 2 == 0) and 0.2 or 0.45
			piece("Welle", UDim2.new(i / 6, 0, up, 0), UDim2.new(1 / 6, 0, 0.35, 0), (i % 2 == 0) and c1 or c2)
		end
	elseif pattern == "laurel" then
		piece("Leiste", UDim2.new(0, 0, 0.8, 0), UDim2.new(1, 0, 0.12, 0), c1)
		piece("Blatt", UDim2.new(0.2, 0, 0.15, 0), UDim2.new(0.18, 0, 0.45, 0), c1)
		piece("Blatt", UDim2.new(0.62, 0, 0.15, 0), UDim2.new(0.18, 0, 0.45, 0), c1)
		piece("Mitte", UDim2.new(0.46, 0, 0.1, 0), UDim2.new(0.08, 0, 0.6, 0), c2)
	elseif pattern == "solid" then
		piece("Fläche", UDim2.new(0.1, 0, 0.15, 0), UDim2.new(0.8, 0, 0.7, 0), c1)
	else -- stripes
		piece("Streifen", UDim2.new(0.3, 0, 0, 0), UDim2.new(0.14, 0, 1, 0), c1)
		piece("Streifen", UDim2.new(0.56, 0, 0, 0), UDim2.new(0.14, 0, 1, 0), c1)
	end
	return base
end

-- Felgen: runde Scheibe in Felgenfarbe, bei Neon ein Leuchtrand
local function rimsSwatch(parent, style)
	local base = fixed(parent, "Swatch", 44, 1)
	local disc = Instance.new("Frame")
	disc.Name = "Felge"
	disc.BackgroundColor3 = rgb(style.color, Color3.fromRGB(200, 200, 200))
	disc.BorderSizePixel = 0
	disc.Size = UDim2.new(0, 40, 0, 40)
	disc.Position = UDim2.new(0.5, -20, 0, 2)
	disc.Parent = base
	UI.Corner(disc, 20)
	local ring = Instance.new("UIStroke")
	ring.Name = "Ring"
	ring.Thickness = style.neon and 3 or 1.5
	ring.Color = style.neon and rgb(style.neon, T.green) or Color3.fromRGB(60, 64, 72)
	ring.Parent = disc
	local hub = Instance.new("Frame")
	hub.Name = "Nabe"
	hub.BackgroundColor3 = Color3.fromRGB(40, 42, 48)
	hub.BorderSizePixel = 0
	hub.Size = UDim2.new(0, 12, 0, 12)
	hub.Position = UDim2.new(0.5, -6, 0.5, -6)
	hub.Parent = disc
	UI.Corner(hub, 6)
	return base
end

-- Hupe: Sprechblase mit dem Text in der Lichtfarbe
local function hornSwatch(parent, style)
	local base = fixed(parent, "Swatch", 44, 1, T.bg)
	UI.Corner(base, 12)
	UI.Label(base, type(style.text) == "string" and style.text or "Tuut!", {
		AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center, Font = UI.FontBold, TextSize = 15, TextColor3 = rgb(style.light, T.yellow),
		Name = "Text",
	})
	return base
end

-- Reifenspur: Farbbalken (bei zwei Farben als Verlauf)
local function trailSwatch(parent, style)
	local base = fixed(parent, "Swatch", 44, 1)
	local c1 = rgb(style.color, T.blue)
	local bar = Instance.new("Frame")
	bar.Name = "Spur"
	bar.BackgroundColor3 = c1
	bar.BorderSizePixel = 0
	bar.Size = UDim2.new(0.9, 0, 0, math.clamp(math.floor((num(style.width) or 0.6) * 20), 8, 20))
	bar.Position = UDim2.new(0.05, 0, 0.5, -6)
	bar.Parent = base
	UI.Corner(bar, 6)
	if style.color2 then
		local g = Instance.new("UIGradient")
		g.Color = ColorSequence.new(c1, rgb(style.color2, c1))
		g.Parent = bar
	end
	return base
end

local function swatch(parent, item)
	local style = type(item.style) == "table" and item.style or {}
	if item.slot == "wrap" then
		return wrapSwatch(parent, style)
	elseif item.slot == "rims" then
		return rimsSwatch(parent, style)
	elseif item.slot == "horn" then
		return hornSwatch(parent, style)
	end
	return trailSwatch(parent, style)
end

---------------------------------------------------------------- Aufbau
function ShopUI.Build(page, context)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme

	local hero = UI.Card(page, 1)
	hero.BackgroundColor3 = T.purpleDark
	UI.Title(hero, "Shop", 1)
	refs.hint = UI.Label(hero, HINT, { LayoutOrder = 2, TextSize = 15, TextColor3 = T.text })
	refs.wallet = UI.Small(hero, "", 3)
	refs.loading = UI.Small(hero, "Der Katalog wird geladen …", 4)

	-- Credits
	local cr = UI.Card(page, 2)
	UI.Title(cr, "Credits", 1)
	UI.Small(cr, "Credits für Autos, Tuning und Kosmetik. Roblox zeigt vor dem Kauf den verbindlichen Preis.", 2)
	refs.creditsList = UI.Frame(cr, { BackgroundTransparency = 1, LayoutOrder = 3 })
	UI.List(refs.creditsList, 6)
	UI.Button(cr, "Zum Credits-Shop des Tablets", T.blue, function()
		if ctx.OpenTablet then
			ctx.OpenTablet("shop")
		end
	end, { LayoutOrder = 4, Visible = ctx.OpenTablet ~= nil })

	-- Autos
	local cars = UI.Card(page, 3)
	UI.Title(cars, "Autos", 1)
	UI.Small(cars, "Sondermodelle mit eigener Optik und exklusiver Folierung. Sie fahren genau wie das Basismodell – kein Vorteil auf der Strecke. Mit Credits ab dem passenden Level ebenfalls kaufbar.", 2)
	refs.carsList = UI.Frame(cars, { BackgroundTransparency = 1, LayoutOrder = 3 })
	UI.List(refs.carsList, 10)

	-- Kosmetik
	local cos = UI.Card(page, 4)
	UI.Title(cos, "Kosmetik", 1)
	UI.Small(cos, "Folierungen, Felgen-Sets, Hupen und Reifenspuren gelten für alle deine Autos. Angelegtes siehst du sofort am Auto.", 2)
	refs.cosList = UI.Frame(cos, { BackgroundTransparency = 1, LayoutOrder = 3 })
	UI.List(refs.cosList, 8)

	-- Pässe
	local pa = UI.Card(page, 5)
	UI.Title(pa, "Pässe", 1)
	UI.Small(pa, "Game Passes gelten dauerhaft. Sie enthalten nur Optik oder wirken auf dein Schrott-Guthaben, nie auf die Bestenliste.", 2)
	refs.passList = UI.Frame(pa, { BackgroundTransparency = 1, LayoutOrder = 3 })
	UI.List(refs.passList, 8)
	local press = UI.Frame(pa, { BackgroundTransparency = 1, LayoutOrder = 4 })
	UI.List(press, 8)
	UI.Small(press, "Schrottpresse", 1)
	local double = UI.Frame(press, { BackgroundColor3 = T.bg, LayoutOrder = 2 })
	UI.Corner(double, 8)
	UI.Padding(double, 10, 8)
	UI.List(double, 4)
	UI.Label(double, "2× Schrott", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	refs.double = UI.Small(double, "", 2)
	refs.doubleButton = UI.Button(double, "2× Schrott kaufen", T.purple, function()
		Remote.Send("mini_pass_prompt", { pass = "DoubleScrap" })
	end, { LayoutOrder = 3 })
	local plus = UI.Frame(press, { BackgroundColor3 = T.bg, LayoutOrder = 3 })
	UI.Corner(plus, 8)
	UI.Padding(plus, 10, 8)
	UI.List(plus, 4)
	UI.Label(plus, "Schrottpresse+", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	refs.plus = UI.Small(plus, "", 2)
	refs.plusButton = UI.Button(plus, "Schrottpresse+ kaufen", T.purple, function()
		Remote.Send("mini_pass_prompt", { pass = "PressPlus" })
	end, { LayoutOrder = 3 })

	-- Richtlinien-Fußzeile
	local foot = UI.Card(page, 6)
	refs.policy = UI.Label(foot, POLICY, { Name = "Policy", TextSize = 14, TextColor3 = T.muted, LayoutOrder = 1 })
	UI.Small(foot, "Kein Pay-to-win: Sondermodelle fahren wie ihr Basismodell. Roblox zeigt vor jedem Kauf den verbindlichen Preis.", 2)

	refs.products, refs.cars, refs.cos, refs.passes = {}, {}, {}, {}
end

---------------------------------------------------------------- Karten aus dem Katalog
local function buildCredits()
	clear(refs.creditsList)
	local n = 0
	for _, p in ipairs(catalog.products or {}) do
		if p.kind == "credits" then
			n += 1
			local row, left = UI.Row(refs.creditsList, n)
			UI.Label(left, p.name or "Credits", { Font = UI.FontBold, TextSize = 16 })
			UI.Small(left, p.desc or "")
			local small = UI.Small(left, "")
			local button = UI.Button(row, "Kaufen", T.purple, function()
				Remote.Send("shop_prompt", { product = p.key })
			end, { Size = UDim2.new(0, UI.RowButtonWidth, 0, UI.MinTouch), Position = UDim2.new(1, -UI.RowButtonWidth, 0, 0), Name = "Buy_" .. p.key })
			refs.products[p.key] = { button = button, small = small, product = p }
		end
	end
	if n == 0 then
		UI.Small(refs.creditsList, "Zurzeit keine Credits-Pakete.", 1)
	end
end

local function carStats(e)
	local parts = {}
	if num(e.power) then
		table.insert(parts, math.floor(e.power) .. " PS")
	end
	if num(e.topSpeed) then
		table.insert(parts, math.floor(e.topSpeed) .. " km/h")
	end
	if e.drive and Lib.DriveNames[e.drive] then
		table.insert(parts, Lib.DriveNames[e.drive])
	end
	return table.concat(parts, " · ")
end

local function buildCars()
	clear(refs.carsList)
	local n = 0
	for _, e in ipairs(catalog.cars or {}) do
		n += 1
		local card = UI.Frame(refs.carsList, { Name = "Car_" .. e.id, BackgroundColor3 = T.bg, LayoutOrder = n })
		UI.Corner(card, 8)
		UI.Padding(card, 10, 8)
		UI.List(card, 6)
		local preview = Lib.Preview(card, 130, 1)
		UI.Label(card, e.name or e.id, { Font = UI.FontBold, TextSize = 17, LayoutOrder = 2 })
		local product = productFor("car", e.id)
		local baseName = Lib.ModelDef(e.base)
		baseName = type(baseName) == "table" and baseName.name or e.base
		UI.Small(card, (product and product.desc) or ("Fährt wie " .. tostring(baseName) .. "."), 3)
		UI.Small(card, carStats(e) .. " · ab Level " .. tostring(num(e.level) or 1), 4)
		local status = UI.Label(card, "", { TextSize = 14, TextColor3 = T.green, LayoutOrder = 5 })
		local buttons = grid(card, 6, UI.MinTouch)
		local robux = UI.Button(buttons, robuxText(product), T.purple, function()
			if product then
				Remote.Send("shop_prompt", { product = product.key })
			end
		end, { LayoutOrder = 1, Name = "Robux_" .. e.id })
		local buy = UI.Button(buttons, "Für Credits", T.green, function()
			local price = num(e.price) or 0
			UI.Confirm(e.name .. " für " .. credits(price) .. " kaufen? Das Auto steht danach in deiner Garage.", function()
				Remote.Send("shop_buy", { item = e.id })
			end, "Auto kaufen?", "Kaufen", T.green)
		end, { LayoutOrder = 2, Name = "Buy_" .. e.id })
		refs.cars[e.id] = { entry = e, product = product, preview = preview, status = status, robux = robux, buy = buy }
	end
	if n == 0 then
		UI.Small(refs.carsList, "Zurzeit keine Sondermodelle.", 1)
	end
end

local function buildCosmetics()
	clear(refs.cosList)
	local bySlot = {}
	for _, c in ipairs(catalog.cosmetics or {}) do
		bySlot[c.slot] = bySlot[c.slot] or {}
		table.insert(bySlot[c.slot], c)
	end
	local order = 0
	for _, slot in ipairs(catalog.slots or SLOT_ORDER) do
		local items = bySlot[slot]
		if items and #items > 0 then
			order += 1
			local block = UI.Frame(refs.cosList, { Name = "Slot_" .. slot, BackgroundTransparency = 1, LayoutOrder = order })
			UI.List(block, 6)
			local head = UI.Label(block, SLOT_NAMES[slot] or items[1].slotName or slot, { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
			local unequip = UI.Button(block, "Ablegen", T.line, function()
				Remote.Send("shop_equip", { slot = slot, item = "" })
			end, { LayoutOrder = 2, Size = UDim2.new(0, 120, 0, UI.MinTouch), Name = "Unequip_" .. slot })
			local g = grid(block, 3, COS_CARD_H)
			for i, c in ipairs(items) do
				local card = fixed(g, "Cos_" .. c.id, COS_CARD_H, i, T.bg)
				UI.Corner(card, 8)
				UI.Padding(card, 8, 8)
				UI.List(card, 4)
				swatch(card, c)
				UI.Label(card, c.name or c.id, { Font = UI.FontBold, TextSize = 14, LayoutOrder = 2, Size = UDim2.new(1, 0, 0, 18), AutomaticSize = Enum.AutomaticSize.None, TextTruncate = Enum.TextTruncate.AtEnd })
				local info = UI.Label(card, "", { TextSize = 12, TextColor3 = T.muted, LayoutOrder = 3, Size = UDim2.new(1, 0, 0, 30), AutomaticSize = Enum.AutomaticSize.None, TextYAlignment = Enum.TextYAlignment.Top })
				local button = UI.Button(card, "", T.green, function()
					local r = refs.cos[c.id]
					if not r or not r.mode then
						return
					end
					if r.mode == "buy" then
						Remote.Send("shop_buy", { item = c.id })
					elseif r.mode == "equip" then
						Remote.Send("shop_equip", { slot = c.slot, item = c.id })
					elseif r.mode == "unequip" then
						Remote.Send("shop_equip", { slot = c.slot, item = "" })
					end
				end, { LayoutOrder = 4, Size = UDim2.new(1, 0, 0, UI.MinTouch), Name = "Act_" .. c.id })
				local product = productFor("cosmetic", c.id)
				local robux = nil
				if product then
					robux = UI.Button(card, "", T.purple, function()
						Remote.Send("shop_prompt", { product = product.key })
					end, { LayoutOrder = 5, Size = UDim2.new(1, 0, 0, UI.MinTouch), TextSize = 13, Name = "Robux_" .. c.id })
				end
				refs.cos[c.id] = { item = c, info = info, button = button, robux = robux, product = product, mode = nil }
			end
			refs.cos["slot_" .. slot] = { head = head, unequip = unequip }
		end
	end
	-- Pakete (Bündel): nur per Robux als Paket, einzeln gibt es alles für Credits
	local bundles = {}
	for _, p in ipairs(catalog.products or {}) do
		if p.kind == "bundle" then
			table.insert(bundles, p)
		end
	end
	if #bundles > 0 then
		order += 1
		local block = UI.Frame(refs.cosList, { Name = "Bundles", BackgroundTransparency = 1, LayoutOrder = order })
		UI.List(block, 6)
		UI.Label(block, "Pakete", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
		for i, p in ipairs(bundles) do
			local row, left = UI.Row(block, i + 1)
			UI.Label(left, p.name or p.key, { Font = UI.FontBold, TextSize = 15 })
			UI.Small(left, p.desc or "")
			local small = UI.Small(left, "Alle Teile gibt es einzeln auch für Credits.")
			local button = UI.Button(row, robuxText(p), T.purple, function()
				Remote.Send("shop_prompt", { product = p.key })
			end, { Size = UDim2.new(0, UI.RowButtonWidth, 0, UI.MinTouch), Position = UDim2.new(1, -UI.RowButtonWidth, 0, 0), Name = "Robux_" .. p.key, TextSize = 13 })
			refs.products[p.key] = { button = button, small = small, product = p }
		end
	end
end

local function buildPasses()
	clear(refs.passList)
	local n = 0
	for _, p in ipairs(catalog.passes or {}) do
		n += 1
		local card = UI.Frame(refs.passList, { Name = "Pass_" .. p.key, BackgroundColor3 = T.bg, LayoutOrder = n })
		UI.Corner(card, 8)
		UI.Padding(card, 10, 8)
		UI.List(card, 4)
		UI.Label(card, p.name or p.key, { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
		UI.Small(card, p.desc or "", 2)
		local status = UI.Small(card, "", 3)
		local button = UI.Button(card, robuxText(p), T.purple, function()
			Remote.Send("shop_prompt", { product = p.key })
		end, { LayoutOrder = 4, Name = "Robux_" .. p.key })
		refs.passes[p.key] = { pass = p, status = status, button = button }
	end
end

-- Struktur-Signatur des Katalogs: Ids und ready-Flags (nur das ändert die Karten). Jeder full-Snapshot bringt eine
-- neue Katalog-Tabelle mit; Preise, Besitz und Gründe aktualisieren die render*-Funktionen ohne Neubau, damit
-- Scrollposition und Knöpfe unter dem Finger erhalten bleiben.
function ShopUI.Signature(cat)
	if type(cat) ~= "table" then
		return ""
	end
	local parts = {}
	for _, slot in ipairs(cat.slots or {}) do
		table.insert(parts, "s:" .. tostring(slot))
	end
	for _, c in ipairs(cat.cosmetics or {}) do
		table.insert(parts, "c:" .. tostring(c.id) .. ":" .. tostring(c.slot))
	end
	for _, e in ipairs(cat.cars or {}) do
		table.insert(parts, "a:" .. tostring(e.id))
	end
	for _, p in ipairs(cat.products or {}) do
		table.insert(parts, "p:" .. tostring(p.key) .. ":" .. tostring(p.kind) .. ":" .. tostring(p.ready == true))
	end
	for _, p in ipairs(cat.passes or {}) do
		table.insert(parts, "g:" .. tostring(p.key) .. ":" .. tostring(p.ready == true))
	end
	return table.concat(parts, "|")
end

-- Aktuelle Einträge nach Schlüssel (für die Anzeige; die Karten halten nur Schlüssel/Ids fest)
local function index()
	lookup = { products = {}, cars = {}, cos = {}, passes = {} }
	for _, p in ipairs(catalog.products or {}) do
		lookup.products[p.key] = p
	end
	for _, e in ipairs(catalog.cars or {}) do
		lookup.cars[e.id] = e
	end
	for _, c in ipairs(catalog.cosmetics or {}) do
		lookup.cos[c.id] = c
	end
	for _, p in ipairs(catalog.passes or {}) do
		lookup.passes[p.key] = p
	end
end

local function rebuild()
	builtSig = ShopUI.Signature(catalog) -- vor dem Aufbau: ein erneuter Render-Aufruf baut nicht noch einmal
	refs.products, refs.cars, refs.cos, refs.passes = {}, {}, {}, {}
	buildCredits()
	buildCars()
	buildCosmetics()
	buildPasses()
	ShopUI.Builds += 1
	refs.loading.Visible = false
	if type(catalog.hint) == "string" and catalog.hint ~= "" then
		refs.hint.Text = catalog.hint
	end
end

-- Für Tests: wie oft die Karten neu gebaut wurden
ShopUI.Builds = 0

---------------------------------------------------------------- Anzeige
local function renderCredits(s)
	for key, r in pairs(refs.products) do
		local p = lookup.products[key] or r.product
		r.product = p
		if p.kind == "credits" then
			local price = p.ready and robuxPrice(p) or nil
			r.small.Text = not p.ready and NOT_READY or (price and (price .. " Robux") or "Preis zeigt Roblox im Kaufdialog.")
			r.button.Text = p.ready and "Kaufen" or NOT_READY
			UI.SetEnabled(r.button, p.ready == true, T.purple)
		else
			-- Bündel: schon (teilweise) vorhanden -> kein Robux-Kauf, Hinweis auf die Einzelteile
			local have, parts = num(p.have) or 0, num(p.parts) or 0
			if p.owned then
				r.button.Text = "Gekauft ✓"
				r.small.Text = "Alle Teile gehören dir schon."
			elseif have > 0 then
				r.button.Text = "Teilweise da"
				r.small.Text = "Du hast schon " .. have .. " von " .. parts .. " Teilen – die fehlenden gibt es einzeln für Credits."
			else
				r.button.Text = robuxText(p)
				r.small.Text = "Alle Teile gibt es einzeln auch für Credits."
			end
			UI.SetEnabled(r.button, p.ready == true and not p.owned and p.blocked == nil, T.purple)
		end
	end
end

local function renderCars(s, dlc)
	local level = num(s.level) or 1
	local money = num(s.credits) or 0
	for id, r in pairs(refs.cars) do
		local e = lookup.cars[id] or r.entry
		r.entry = e
		if r.product then
			r.product = lookup.products[r.product.key] or r.product
		end
		local owned = dlc[id] == true
		r.preview:Set(e.body, Lib.Style(s, nil, { paint = e.paint, rims = e.rims, glow = e.glow, spoiler = e.spoiler }))
		local price = num(e.price) or 0
		local need = num(e.level) or 1
		if owned then
			r.status.Text = "Steht in deiner Garage ✓"
			r.status.TextColor3 = T.green
			r.status.Visible = true
			r.buy.Text = "Gekauft ✓"
			UI.SetEnabled(r.buy, false, T.green)
			r.robux.Text = "Gekauft ✓"
			UI.SetEnabled(r.robux, false, T.purple)
		else
			r.buy.Text = credits(price) .. " · Level " .. need
			local canLevel = level >= need
			local canPay = money >= price
			UI.SetEnabled(r.buy, canLevel and canPay, T.green)
			if not canLevel then
				r.status.Text = "Für Credits ab Level " .. need .. "."
				r.status.TextColor3 = T.yellow
				r.status.Visible = true
			elseif not canPay then
				r.status.Text = "Nicht genug Credits für den Credits-Kauf."
				r.status.TextColor3 = T.muted
				r.status.Visible = true
			else
				r.status.Visible = false
			end
			-- Robux-Knopf aus, wenn der Server den Prompt ablehnen würde (z. B. Garage voll)
			local blocked = r.product and r.product.blocked or nil
			if blocked and r.product.ready then
				r.robux.Text = "Garage voll"
				r.status.Text = blocked
				r.status.TextColor3 = T.yellow
				r.status.Visible = true
			else
				r.robux.Text = robuxText(r.product)
			end
			UI.SetEnabled(r.robux, r.product ~= nil and r.product.ready == true and blocked == nil, T.purple)
		end
	end
end

local function renderCosmetics(s, owned, equipped)
	local level = num(s.level) or 1
	local money = num(s.credits) or 0
	for key, r in pairs(refs.cos) do
		if r.item then
			local c = lookup.cos[key] or r.item
			r.item = c
			if r.product then
				r.product = lookup.products[r.product.key] or r.product
			end
			local has = owned[c.id] == true
			local on = equipped[c.slot] == c.id
			local price = num(c.price)
			local need = num(c.level) or 1
			if on then
				r.mode = "unequip"
				r.info.Text = "Angelegt ✓"
				r.info.TextColor3 = T.green
				r.button.Text = "Ablegen"
				UI.SetEnabled(r.button, true, T.line)
			elseif has then
				r.mode = "equip"
				r.info.Text = "In deinem Besitz"
				r.info.TextColor3 = T.muted
				r.button.Text = "Anlegen"
				UI.SetEnabled(r.button, true, T.blue)
			elseif c.rewardOnly or not price then
				r.mode = nil
				r.info.Text = "Belohnung: " .. tostring(c.rewardText or "Belohnung")
				r.info.TextColor3 = T.yellow
				r.button.Text = "Nur als Belohnung"
				UI.SetEnabled(r.button, false, T.green)
			else
				r.mode = "buy"
				r.info.Text = credits(price) .. (need > 1 and (" · ab Level " .. need) or "")
				r.info.TextColor3 = T.muted
				r.button.Text = "Kaufen"
				local ok = level >= need and money >= price
				UI.SetEnabled(r.button, ok, T.green)
				if level < need then
					r.info.TextColor3 = T.yellow
				end
			end
			if r.robux then
				local p = r.product
				r.robux.Text = has and "Gekauft ✓" or robuxText(p)
				r.robux.Visible = not has
				UI.SetEnabled(r.robux, p ~= nil and p.ready == true and not has and p.blocked == nil, T.purple)
			end
		elseif r.unequip then
			local slot = key:sub(6)
			local on = equipped[slot] ~= nil and equipped[slot] ~= ""
			r.unequip.Visible = on
			UI.SetEnabled(r.unequip, on, T.line)
		end
	end
end

local function renderPasses(s, shop)
	local passes = type(shop.passes) == "table" and shop.passes or {}
	for key, r in pairs(refs.passes) do
		local p = lookup.passes[key] or r.pass
		r.pass = p
		local owned = passes[key] == true or p.owned == true
		if owned then
			r.status.Text = "Bereits aktiv ✓ – die Teile liegen unter Kosmetik."
			r.button.Text = "Bereits aktiv ✓"
			UI.SetEnabled(r.button, false, T.purple)
		else
			r.status.Text = p.ready and "Dauerhaft, nur Optik." or (NOT_READY .. " – alle Teile gibt es auch für Credits.")
			r.button.Text = robuxText(p)
			UI.SetEnabled(r.button, p.ready == true, T.purple)
		end
	end
	local p = s.passes or {}
	refs.double.Text = "Klicks und Maschinen ×" .. dec(passValue("DoubleScrap", "multiplier", 2))
		.. (p.doubleScrap and " · aktiv ✓" or "") .. (p.doubleScrapConfigured and "" or " · noch nicht eingerichtet")
	refs.plus.Text = "Maschinen ×" .. dec(passValue("PressPlus", "machineMultiplier", 1.5))
		.. (p.pressPlus and " · aktiv ✓" or "") .. (p.pressPlusConfigured and "" or " · noch nicht eingerichtet")
	refs.doubleButton.Text = p.doubleScrap and "Bereits aktiv ✓" or "2× Schrott kaufen"
	refs.plusButton.Text = p.pressPlus and "Bereits aktiv ✓" or "Schrottpresse+ kaufen"
	UI.SetEnabled(refs.doubleButton, p.doubleScrapConfigured == true and not p.doubleScrap, T.purple)
	UI.SetEnabled(refs.plusButton, p.pressPlusConfigured == true and not p.pressPlus, T.purple)
end

function ShopUI.Render(s)
	if type(s) ~= "table" then
		return
	end
	state = s
	local shop = type(s.shop) == "table" and s.shop or {}
	if type(shop.catalog) == "table" then
		catalog = shop.catalog
	end
	refs.wallet.Text = "Guthaben: " .. credits(num(s.credits) or 0) .. " · Level " .. tostring(num(s.level) or 1)
	if catalog then
		index()
		if ShopUI.Signature(catalog) ~= builtSig then
			rebuild()
		end
	end
	if not catalog then
		refs.loading.Visible = true
		renderPasses(s, shop)
		return
	end
	local owned = setOf(shop.owned)
	local equipped = type(shop.equipped) == "table" and shop.equipped or {}
	local dlc = setOf(shop.dlcCars)
	renderCredits(s)
	renderCars(s, dlc)
	renderCosmetics(s, owned, equipped)
	renderPasses(s, shop)
end

-- Für Tests: zuletzt gebauter Katalog
function ShopUI.Catalog()
	return catalog
end

return ShopUI
