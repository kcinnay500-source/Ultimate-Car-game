-- ShopRules: Shop & Monetarisierung als reine, serverautoritative Funktionen (docs/PHASE4_CONTRACT.md §2, §9).
-- Daten: d.games.shop = { owned = { [cosmeticId] = true }, equipped = { wrap = id|"", rims = id|"", horn = id|"",
--                          trail = id|"" }, dlcCars = { [modelId] = true } }
-- Alle Zahlen und Texte in GameConfig.Shop, DLC-Modelle in CarCatalog.Dlc. Geld nur über MiniRules.AddMoney,
-- XP über MiniRules.GainXP, Autos über CarRules.AddCar. Keine Instanzen, keine Dienste: nutzbar auf Server
-- (ShopService, Purchases/Profiles.GrantReceipt über ApplyReceipt) und Client (Katalogtexte).
-- Grundsätze (§9): kein Pay-to-win (DLC-Autos = Werte des Basismodells), alles auch für Credits oder als
-- Belohnung, Produkt-/Pass-Ids 0 = „noch nicht eingerichtet“ (CanPrompt lehnt ab), ein Auto-Produkt ist
-- genau einmal kaufbar (dlcCars[model]), Gutschriften sind idempotent (Grant überspringt Vorhandenes).
-- MiniRules wird erst beim ersten Aufruf geladen (MiniRules.LoadGames lädt dieses Modul; keine Ringabhängigkeit).
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local CarCatalog = require(script.Parent:WaitForChild("CarCatalog"))
local CarRules = require(script.Parent:WaitForChild("CarRules"))

local ShopRules = {}

local SHOP = GameConfig.Shop
local TEXT = SHOP.Text

export type Shop = { owned: { [string]: boolean }, equipped: { [string]: string }, dlcCars: { [string]: boolean } }
export type Grants = { cosmetics: { string }?, cars: { string }?, credits: number? }
export type GrantResult = { cosmetics: { string }, cars: { any }, credits: number, changed: boolean }

local MiniRules
local function mini()
	if not MiniRules then
		MiniRules = require(script.Parent:WaitForChild("MiniRules"))
	end
	return MiniRules
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function money(d: any): number
	return type(d) == "table" and finite(d.money) and d.money or 0
end

local function carCount(d: any): number
	local g = type(d) == "table" and d.games or nil
	local cars = type(g) == "table" and g.cars or nil
	return type(cars) == "table" and #cars or 0
end

local function level(d: any): number
	local l = type(d) == "table" and d.level or nil
	return finite(l) and math.max(1, math.floor(l)) or 1
end

---------------------------------------------------------------- Nachschlagen
function ShopRules.Cosmetic(id: any): any
	return type(id) == "string" and SHOP.CosmeticById[id] or nil
end

-- DLC-Modell aus CarCatalog (dlc = true), nil für andere Modelle
function ShopRules.DlcModel(id: any): any
	local m = CarCatalog.Model(id)
	return (m and m.dlc == true) and m or nil
end

function ShopRules.DlcModels(): { any }
	local out = {}
	for _, x in ipairs(CarCatalog.Dlc) do
		local m = ShopRules.DlcModel(x.id)
		if m then
			table.insert(out, m)
		end
	end
	return out
end

function ShopRules.Product(key: any): any
	return type(key) == "string" and SHOP.ProductByKey[key] or nil
end

function ShopRules.Pass(key: any): any
	return type(key) == "string" and SHOP.PassByKey[key] or nil
end

-- Produkt-Id eines Developer Products (Credits-Pakete zeigen auf C.CreditProducts; Platzhalter 0)
function ShopRules.ProductId(product: any): number
	if type(product) ~= "table" then
		return 0
	end
	local id = type(product.pack) == "table" and product.pack.productId or product.productId
	return finite(id) and id > 0 and math.floor(id) or 0
end

-- Produkt zu einer Developer-Product-Id (für Purchases.ProcessReceipt; nur Auto/Kosmetik/Bündel – Credits-Pakete
-- laufen weiter über Profiles.GrantCredits). nil für 0/unbekannt.
function ShopRules.ProductForId(productId: any): any
	if not finite(productId) or productId <= 0 then
		return nil
	end
	for _, p in ipairs(SHOP.Products) do
		if p.kind ~= "credits" and ShopRules.ProductId(p) == productId then
			return p
		end
	end
	return nil
end

-- Credits-Preis eines DLC-Autos für dieses Profil (Basispreis × DlcPriceFactor, dann Rabatte wie im Autohaus)
function ShopRules.DlcPrice(d: any, m: any): number
	if type(m) ~= "table" or not finite(m.price) then
		return 0
	end
	local factor = finite(SHOP.DlcPriceFactor) and SHOP.DlcPriceFactor or CarCatalog.DlcPriceFactor
	local listed = math.floor(m.price * factor + 0.5)
	return CarRules.DealerPrice(d, { price = listed })
end

---------------------------------------------------------------- Daten
function ShopRules.Default(): Shop
	local equipped = {}
	for _, slot in ipairs(SHOP.Slots) do
		equipped[slot] = ""
	end
	return { owned = {}, equipped = equipped, dlcCars = {} }
end

-- Belohnungen, die laut anderen Modulen bereits verdient sind (Prestige claimed, Story done, DLC-Autos in der
-- Garage): werden beim Laden nachgetragen, damit Profile von vor Meilenstein 8 nichts verlieren.
local function backfill(shop: Shop, games: any)
	if type(games) ~= "table" then
		return
	end
	local pr = games.prestige
	if type(pr) == "table" and type(pr.claimed) == "table" then
		for rank, v in pairs(pr.claimed) do
			local r = v == true and GameConfig.Prestige.Rewards[rank] or nil
			if r and SHOP.CosmeticById[r.cosmetic] then
				shop.owned[r.cosmetic] = true
			end
		end
	end
	local st = games.story
	if type(st) == "table" and type(st.done) == "table" then
		for _, ch in ipairs(GameConfig.Story.Chapters) do
			for _, m in ipairs(ch.Missions) do
				local cos = type(m.reward) == "table" and m.reward.cosmetic or nil
				if cos and st.done[m.id] == true and SHOP.CosmeticById[cos] then
					shop.owned[cos] = true
				end
			end
		end
	end
	if type(games.cars) == "table" then
		for _, car in ipairs(games.cars) do
			local m = type(car) == "table" and ShopRules.DlcModel(car.model) or nil
			if m then
				shop.dlcCars[m.id] = true
				if m.wrap and SHOP.CosmeticById[m.wrap] then
					shop.owned[m.wrap] = true
				end
			end
		end
	end
end

-- raw = gespeichertes d.games.shop (oder nil), games = bereits geladenes d.games (für das Nachtragen). Idempotent,
-- Whitelist: nur bekannte Kosmetik-/DLC-Ids, equipped nur Besitz im passenden Platz, höchstens MaxOwned Einträge.
function ShopRules.Load(raw: any, d: any, now: any, games: any): Shop
	local shop = ShopRules.Default()
	local r = type(raw) == "table" and raw or {}
	if type(r.owned) == "table" then
		local n = 0
		for id, v in pairs(r.owned) do
			if v == true and type(id) == "string" and SHOP.CosmeticById[id] then
				n += 1
				if n > SHOP.MaxOwned then
					break
				end
				shop.owned[id] = true
			end
		end
	end
	if type(r.dlcCars) == "table" then
		for id, v in pairs(r.dlcCars) do
			if v == true and ShopRules.DlcModel(id) then
				shop.dlcCars[id] = true
			end
		end
	end
	backfill(shop, games)
	if type(r.equipped) == "table" then
		for _, slot in ipairs(SHOP.Slots) do
			local id = r.equipped[slot]
			local c = ShopRules.Cosmetic(id)
			if c and c.slot == slot and shop.owned[id] then
				shop.equipped[slot] = id
			end
		end
	end
	return shop
end

-- Für MiniRules.DefaultGames / LoadGames (ApplyLoad nach CarRules/MetaRules/StoryRules, damit das Nachtragen
-- die geladenen Autos, Prestige-Ränge und Missionen sieht)
function ShopRules.ApplyDefault(g: any)
	g.shop = ShopRules.Default()
	return g
end
function ShopRules.ApplyLoad(g: any, raw: any, d: any, now: any)
	local r = type(raw) == "table" and raw or {}
	g.shop = ShopRules.Load(r.shop, d, now, g)
	return g
end

-- Shop-Daten eines Profils (legt Standard an, falls ein Profil ohne shop in der Sitzung ist)
function ShopRules.Shop(d: any): Shop
	local g = d.games
	if type(g.shop) ~= "table" or type(g.shop.owned) ~= "table" or type(g.shop.equipped) ~= "table" or type(g.shop.dlcCars) ~= "table" then
		ShopRules.ApplyDefault(g)
	end
	return g.shop
end

function ShopRules.Owns(d: any, id: any): boolean
	return type(id) == "string" and ShopRules.Shop(d).owned[id] == true
end

function ShopRules.HasDlc(d: any, modelId: any): boolean
	return type(modelId) == "string" and ShopRules.Shop(d).dlcCars[modelId] == true
end

---------------------------------------------------------------- Kaufen mit Credits
-- Rückgabe: ok, Meldung (nil bei ok), Preis, Art ("cosmetic"|"car"), Eintrag
function ShopRules.CanBuy(d: any, itemId: any): (boolean, string?, number, string?, any)
	local c = ShopRules.Cosmetic(itemId)
	if c then
		if ShopRules.Owns(d, c.id) then
			return false, TEXT.owned, 0, "cosmetic", c
		end
		if c.rewardOnly or not finite(c.creditsPrice) then
			return false, string.format(TEXT.rewardOnly, c.rewardText or "Belohnung"), 0, "cosmetic", c
		end
		local need = finite(c.level) and c.level or 1
		if level(d) < need then
			return false, string.format(TEXT.level, need), c.creditsPrice, "cosmetic", c
		end
		if money(d) < c.creditsPrice then
			return false, TEXT.money, c.creditsPrice, "cosmetic", c
		end
		return true, nil, c.creditsPrice, "cosmetic", c
	end
	local m = ShopRules.DlcModel(itemId)
	if m then
		local price = ShopRules.DlcPrice(d, m)
		if ShopRules.HasDlc(d, m.id) then
			return false, TEXT.owned, price, "car", m
		end
		if level(d) < m.level then
			return false, string.format(TEXT.level, m.level), price, "car", m
		end
		if carCount(d) >= CarCatalog.MaxCars then
			return false, string.format(TEXT.garageFull, CarCatalog.MaxCars), price, "car", m
		end
		if money(d) < price then
			return false, TEXT.money, price, "car", m
		end
		return true, nil, price, "car", m
	end
	return false, TEXT.unknown, 0, nil, nil
end

-- Kauf mit Credits. Rückgabe: true, { kind, item, price, car?, text } | false, Meldung
function ShopRules.Buy(d: any, itemId: any, now: any): (boolean, any)
	local ok, msg, price, kind, item = ShopRules.CanBuy(d, itemId)
	if not ok then
		return false, msg
	end
	local shop = ShopRules.Shop(d)
	if kind == "cosmetic" then
		mini().AddMoney(d, -price)
		shop.owned[item.id] = true
		mini().GainXP(d, SHOP.BuyXp)
		return true, { kind = kind, item = item, price = price, text = string.format(TEXT.bought, item.name) }
	end
	-- DLC-Auto: erst das Auto anlegen (Garage voll -> nichts abbuchen), dann bezahlen
	local car = CarRules.AddCar(d, CarRules.NewCar(item.id, now))
	if not car then
		return false, string.format(TEXT.garageFull, CarCatalog.MaxCars)
	end
	mini().AddMoney(d, -price)
	shop.dlcCars[item.id] = true
	if item.wrap and SHOP.CosmeticById[item.wrap] then
		shop.owned[item.wrap] = true
	end
	mini().GainXP(d, CarCatalog.BuyXp)
	return true, { kind = kind, item = item, price = price, car = car, text = string.format(TEXT.boughtCar, item.name) }
end

---------------------------------------------------------------- Anlegen
-- itemId = "" (oder nil) legt den Platz frei. Rückgabe: true, Meldung | false, Meldung (nil = unverändert, still)
function ShopRules.Equip(d: any, slot: any, itemId: any): (boolean, string?)
	if type(slot) ~= "string" or not SHOP.SlotSet[slot] then
		return false, TEXT.badSlot
	end
	local shop = ShopRules.Shop(d)
	if itemId == nil or itemId == "" then
		if shop.equipped[slot] == "" then
			return false, nil
		end
		shop.equipped[slot] = ""
		return true, string.format(TEXT.unequipped, SHOP.SlotNames[slot] or slot)
	end
	local c = ShopRules.Cosmetic(itemId)
	if not c then
		return false, TEXT.unknown
	end
	if c.slot ~= slot then
		return false, TEXT.wrongSlot
	end
	if not shop.owned[c.id] then
		return false, TEXT.notOwned
	end
	if shop.equipped[slot] == c.id then
		return false, nil
	end
	shop.equipped[slot] = c.id
	return true, string.format(TEXT.equipped, c.name)
end

---------------------------------------------------------------- Gutschrift (Produkte, Pässe, Belohnungen)
-- grants = { cosmetics = { id, ... }, cars = { modelId, ... }, credits = n }. Idempotent: vorhandene Kosmetik und
-- bereits gekaufte DLC-Autos werden übersprungen. Rückgabe: ok, Ergebnis | false, Meldung.
-- ok = false nur, wenn ein DLC-Auto nicht angelegt werden konnte (Garage voll): dann wird NICHTS geändert
-- (Quittung bleibt offen und wird später erneut versucht).
function ShopRules.Grant(d: any, grants: any, now: any): (boolean, any)
	local res: GrantResult = { cosmetics = {}, cars = {}, credits = 0, changed = false }
	if type(grants) ~= "table" then
		return true, res
	end
	local shop = ShopRules.Shop(d)
	-- Vorprüfung: Platz für alle neuen DLC-Autos
	local newCars = {}
	if type(grants.cars) == "table" then
		for _, id in ipairs(grants.cars) do
			local m = ShopRules.DlcModel(id)
			if m and not shop.dlcCars[m.id] then
				table.insert(newCars, m)
			end
		end
	end
	if #newCars > 0 and carCount(d) + #newCars > CarCatalog.MaxCars then
		return false, string.format(TEXT.garageFull, CarCatalog.MaxCars)
	end
	for _, m in ipairs(newCars) do
		local car = CarRules.AddCar(d, CarRules.NewCar(m.id, now))
		if car then
			shop.dlcCars[m.id] = true
			table.insert(res.cars, car)
			res.changed = true
			if m.wrap and SHOP.CosmeticById[m.wrap] and not shop.owned[m.wrap] then
				shop.owned[m.wrap] = true
				table.insert(res.cosmetics, m.wrap)
			end
		end
	end
	if type(grants.cosmetics) == "table" then
		for _, id in ipairs(grants.cosmetics) do
			local c = ShopRules.Cosmetic(id)
			if c and not shop.owned[c.id] then
				shop.owned[c.id] = true
				table.insert(res.cosmetics, c.id)
				res.changed = true
			end
		end
	end
	if finite(grants.credits) and grants.credits > 0 then
		res.credits = mini().AddMoney(d, math.floor(grants.credits))
		res.changed = res.changed or res.credits > 0
	end
	return true, res
end

-- Für Purchases/Profiles.GrantReceipt: wendet ein Produkt (GameConfig.Shop.Products, kind car|cosmetic|bundle) auf
-- den Profil-Schnappschuss an (snapshot = Rules.Snapshot(profile.data); wird zusammen mit der Quittung
-- geschrieben). Rückgabe: true, Ergebnis (changed = false, wenn alles schon vorhanden war: Quittung trotzdem
-- abschließen) | false, Meldung (nicht anwendbar, z. B. Garage voll -> NotProcessedYet, später erneut).
function ShopRules.ApplyReceipt(snapshot: any, product: any, now: any): (boolean, any)
	if type(snapshot) ~= "table" or type(snapshot.games) ~= "table" then
		return false, "Profil nicht geladen."
	end
	if type(product) ~= "table" or product.kind == "credits" or type(product.grants) ~= "table" then
		return false, TEXT.unknown
	end
	local ok, res = ShopRules.Grant(snapshot, product.grants, now)
	if not ok then
		return false, res
	end
	res.product = product
	res.text = string.format(product.kind == "car" and TEXT.receiptCar or TEXT.receipt, product.name)
	return true, res
end

-- Darf der Client einen Robux-Prompt für dieses Produkt bekommen? Rückgabe: ok, Meldung, productId, Produkt
function ShopRules.CanPrompt(d: any, productKey: any): (boolean, string?, number, any)
	local p = ShopRules.Product(productKey)
	if not p then
		return false, TEXT.unknown, 0, nil
	end
	local id = ShopRules.ProductId(p)
	if id <= 0 then
		return false, TEXT.notReady, 0, p
	end
	if p.kind == "car" then
		for _, model in ipairs(p.grants.cars or {}) do
			if ShopRules.HasDlc(d, model) then
				return false, TEXT.owned, id, p
			end
		end
	end
	return true, nil, id, p
end

-- Alles, was dieses Produkt gewähren würde, hat das Profil schon (für die Anzeige „Gekauft“)
function ShopRules.ProductOwned(d: any, p: any): boolean
	if type(p) ~= "table" or type(p.grants) ~= "table" or p.kind == "credits" then
		return false
	end
	local any = false
	for _, model in ipairs(p.grants.cars or {}) do
		any = true
		if not ShopRules.HasDlc(d, model) then
			return false
		end
	end
	for _, id in ipairs(p.grants.cosmetics or {}) do
		any = true
		if not ShopRules.Owns(d, id) then
			return false
		end
	end
	return any
end

---------------------------------------------------------------- Optik eines Autos (VehicleFactory.ApplyCosmetics)
-- Rückgabe { wrap = Kosmetik|nil, rims = ..., horn = ..., trail = ... } (Einträge aus GameConfig.Shop.Cosmetics mit
-- style). Angelegt gilt profilweit für alle Autos; ein DLC-Auto trägt ohne angelegte Folierung seine exklusive.
function ShopRules.Resolve(d: any, car: any): { [string]: any }
	local out = {}
	local shop = type(d) == "table" and type(d.games) == "table" and ShopRules.Shop(d) or nil
	for _, slot in ipairs(SHOP.Slots) do
		local id = shop and shop.equipped[slot] or ""
		local c = ShopRules.Cosmetic(id)
		if c and c.slot == slot and shop and shop.owned[id] then
			out[slot] = c
		end
	end
	if not out.wrap and type(car) == "table" then
		local m = ShopRules.DlcModel(car.model)
		if m and m.wrap then
			out.wrap = ShopRules.Cosmetic(m.wrap)
		end
	end
	return out
end

-- Nur die Ids (für Snapshot/Client-Vorschau): { wrap = id|"", ... }
function ShopRules.ResolveIds(d: any, car: any): { [string]: string }
	local out = {}
	local r = ShopRules.Resolve(d, car)
	for _, slot in ipairs(SHOP.Slots) do
		out[slot] = r[slot] and r[slot].id or ""
	end
	return out
end

---------------------------------------------------------------- Ansicht (Snapshot, Client)
local function cosmeticView(d: any, c: any, shop: Shop): any
	local ok, reason, price = ShopRules.CanBuy(d, c.id)
	local owned = shop.owned[c.id] == true
	return {
		id = c.id, kind = "cosmetic", slot = c.slot, slotName = SHOP.SlotNames[c.slot], name = c.name, desc = c.desc,
		price = (not c.rewardOnly and finite(c.creditsPrice)) and c.creditsPrice or nil,
		level = finite(c.level) and c.level or 1, rewardOnly = c.rewardOnly == true, rewardText = c.rewardText,
		owned = owned, equipped = shop.equipped[c.slot] == c.id,
		available = ok, reason = (not ok and not owned) and reason or nil, style = c.style,
	}
end

local function carView(d: any, m: any, shop: Shop): any
	local ok, reason, price = ShopRules.CanBuy(d, m.id)
	local s = CarRules.Stats(CarRules.NewCar(m.id, 0))
	local owned = shop.dlcCars[m.id] == true
	return {
		id = m.id, kind = "car", name = m.name, brand = m.brand, body = m.body, base = m.base, level = m.level,
		price = price, basePrice = m.price, paint = m.paint, rims = m.rims, glow = m.glow, spoiler = m.spoiler, wrap = m.wrap,
		owned = owned, available = ok, reason = (not ok and not owned) and reason or nil,
		power = s.power, topSpeed = s.topSpeed, zeroTo100 = s.zeroTo100, drive = s.drive, rating = s.rating,
	}
end

-- Katalog fürs Client-UI (nur bei full-Snapshots, §11): Kosmetik je Platz, DLC-Autos, Produkte, Pässe
function ShopRules.Catalog(d: any): any
	local shop = ShopRules.Shop(d)
	local cosmetics = {}
	for _, c in ipairs(SHOP.Cosmetics) do
		table.insert(cosmetics, cosmeticView(d, c, shop))
	end
	local cars = {}
	for _, m in ipairs(ShopRules.DlcModels()) do
		table.insert(cars, carView(d, m, shop))
	end
	local products = {}
	for _, p in ipairs(SHOP.Products) do
		local id = ShopRules.ProductId(p)
		table.insert(products, {
			key = p.key, kind = p.kind, name = p.name, desc = p.desc, productId = id, ready = id > 0, robuxHint = p.robuxHint,
			creditsPrice = p.creditsPrice, credits = p.kind == "credits" and p.pack and p.pack.credits or nil,
			grants = p.grants, owned = ShopRules.ProductOwned(d, p),
		})
	end
	local passes = {}
	for _, p in ipairs(SHOP.Passes) do
		local id = finite(p.id) and p.id > 0 and math.floor(p.id) or 0
		table.insert(passes, {
			key = p.key, name = p.name, desc = p.desc, id = id, ready = id > 0, robuxHint = p.robuxHint,
			grants = p.grants, owned = ShopRules.ProductOwned(d, p),
		})
	end
	return { cosmetics = cosmetics, cars = cars, products = products, passes = passes, slots = SHOP.Slots, hint = TEXT.hint }
end

-- Felder für MiniSnapshot (§11): shop = { owned[], equipped{}, dlcCars[] }; catalog nur bei full (ShopService)
function ShopRules.SnapshotFields(d: any, full: boolean?): any
	local shop = ShopRules.Shop(d)
	local owned = {}
	for id in pairs(shop.owned) do
		table.insert(owned, id)
	end
	table.sort(owned)
	local dlc = {}
	for id in pairs(shop.dlcCars) do
		table.insert(dlc, id)
	end
	table.sort(dlc)
	local equipped = {}
	for _, slot in ipairs(SHOP.Slots) do
		equipped[slot] = shop.equipped[slot] or ""
	end
	local out = { owned = owned, equipped = equipped, dlcCars = dlc }
	if full then
		out.catalog = ShopRules.Catalog(d)
	end
	return out
end

return ShopRules
