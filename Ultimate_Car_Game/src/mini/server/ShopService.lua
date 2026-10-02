-- ShopService: Shop & Monetarisierung auf dem Server (docs/PHASE4_CONTRACT.md §9, Meilenstein 8).
-- Regeln in ShopRules (rein), Zahlen/Texte in GameConfig.Shop, DLC-Modelle in CarCatalog.Dlc. Aufgaben:
--   Register(Actions, api)           shop_buy {item} (Credits: Kosmetik-Id oder DLC-Modell-Id, Freischaltung
--                                    "car:<basis>" über Unlocks), shop_equip {slot, item} ("" = ablegen),
--                                    shop_prompt {product} (Produkt-Schlüssel aus GameConfig.Shop.Products oder
--                                    Pass-Schlüssel aus GameConfig.Shop.Passes; Id 0 -> „noch nicht eingerichtet“,
--                                    kein Prompt; sonst purchasePrompt {productId} über den 2.4.0-Weg bzw.
--                                    PromptGamePassPurchase)
--   Init(ctx?)                       verbindet PromptGamePassPurchaseFinished (pcall); ctx.emit (MiniService-ctx) ist
--                                    optional – ohne ctx geht purchasePrompt direkt über GarageShared.Remotes.Event
--   OnJoin(ms, d, now)               Sitzung merken, Game-Pass-Besitz prüfen (UserOwnsGamePassAsync in pcall, kann
--                                    warten) und die Pass-Kosmetik idempotent gutschreiben (ShopRules.Grant)
--   OnLeave(ms)                      Sitzung vergessen
--   OnGranted(p, product)            nach einer Robux-Quittung (Purchases.Init-Rückruf): Toast + mini_notice
--                                    { kind="shop", event="receipt" } + api.changed (Autos/Kosmetik im Snapshot)
--   Apply(product, snapshot, now)    = ShopRules.ApplyReceipt (Name aus dem Vertrag §9; Purchases ruft ShopRules direkt)
--   SnapshotFields(ms, d, now, full) { shop = { owned[], equipped{}, dlcCars[], passes{}, catalog (nur full) } }
--   CosmeticsFor(d, car)             { wrap, rims, horn, trail } (Einträge mit style) für VehicleFactory.ApplyCosmetics
--   Restyle (Hook)                   ShopService.Restyle = function(ms, d) – vom Integrator gesetzt (CarService:
--                                    Optik der stehenden Autos nach shop_equip/Gutschrift neu anwenden); optional
-- Geld nur über ShopRules (MiniRules.AddMoney), Quittungen nur über Purchases/Profiles.GrantReceipt. ProcessReceipt
-- bleibt allein in Purchases. Keine Zufallskäufe, kein Handel für Robux. Texte Deutsch (GameConfig.Shop.Text).
local MarketplaceService = game:GetService("MarketplaceService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local MiniShared = Shared:WaitForChild("Mini")
local C = require(Shared:WaitForChild("Config"))
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local ShopRules = require(MiniShared:WaitForChild("ShopRules"))
local Unlocks = require(MiniShared:WaitForChild("Unlocks"))

local ShopService = {}

local SHOP = GameConfig.Shop
local TEXT = SHOP.Text
local PROMPT_SECONDS = 3 -- wie p.nextPurchasePrompt in GarageServer (buyCredits)

local api -- MiniService-api: now, toast, notice, dirty, changed, writable, alive
local ctx -- MiniService-ctx (emit) – optional
local sessions: { [any]: any } = {} -- [Player] = ms

ShopService.Restyle = nil :: ((any, any) -> ())?

local TEXT_LOCAL = {
	noRobux = "Robux-Käufe sind hier noch nicht verfügbar.",
	passOwned = "Du besitzt diesen Game Pass bereits.",
	passGranted = "Game Pass „%s“: %s freigeschaltet!",
	promptFailed = "Der Roblox-Kaufdialog konnte nicht geöffnet werden.",
	capped = "Dein Credit-Guthaben ist bereits zu hoch für dieses Paket.",
	shopClosed = "Der Shop ist gerade nicht erreichbar.",
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function now(): number
	return api and api.now() or os.time()
end

local function alive(ms: any): boolean
	return ms ~= nil and api ~= nil and api.alive(ms) == true and sessions[ms.player] == ms
end

local function toast(ms: any, text: any)
	if api and type(text) == "string" and text ~= "" then
		api.toast(ms, text)
	end
end

local function notice(ms: any, data: { [string]: any })
	if api then
		api.notice(ms, "shop", data)
	end
end

-- Kosmetik-Ids -> Namen (für Toasts)
local function names(ids: { string }): string
	local out = {}
	for _, id in ipairs(ids) do
		local c = ShopRules.Cosmetic(id)
		table.insert(out, c and c.name or tostring(id))
	end
	return table.concat(out, ", ")
end

local function restyle(ms: any, d: any)
	local hook = ShopService.Restyle
	if type(hook) == "function" then
		local ok, err = pcall(hook, ms, d)
		if not ok then
			warn("[Shop] Optik anwenden: " .. tostring(err))
		end
	end
end

-- Client-Prompt über den bestehenden 2.4.0-Weg (GarageClient: purchasePrompt -> PromptProductPurchase)
local function emitPrompt(ms: any, productId: number)
	if ctx and type(ctx.emit) == "function" then
		ctx.emit(ms.p, "purchasePrompt", { productId = productId })
		return
	end
	local remotes = Shared:FindFirstChild("Remotes")
	local event = remotes and remotes:FindFirstChild("Event")
	if event and ms.player.Parent then
		event:FireClient(ms.player, "purchasePrompt", { productId = productId })
	end
end

---------------------------------------------------------------- Game Passes (nur Kosmetik)
local function passId(pass: any): number
	local id = type(pass) == "table" and pass.id or 0
	return finite(id) and id > 0 and math.floor(id) or 0
end

local function passById(id: any): any
	if not finite(id) or id <= 0 then
		return nil
	end
	for _, pass in ipairs(SHOP.Passes) do
		if passId(pass) == id then
			return pass
		end
	end
	return nil
end

-- Pass-Kosmetik gutschreiben (idempotent). Rückgabe: ok, Ergebnis (ShopRules.Grant) – changed = true bei Neuem
function ShopService.GrantPass(d: any, pass: any, t: number?): (boolean, any)
	if type(pass) ~= "table" or type(pass.grants) ~= "table" then
		return false, TEXT.unknown
	end
	return ShopRules.Grant(d, pass.grants, t or now())
end

local function ownsPass(userId: number, id: number): boolean
	if id <= 0 then
		return false
	end
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, id)
	end)
	return ok and result == true
end

-- Pass in dieser Sitzung als besessen merken und die Kosmetik gutschreiben; announce = Toast/Hinweis bei Neuem
local function applyPass(ms: any, d: any, pass: any, announce: boolean)
	ms.shopPasses = ms.shopPasses or {}
	ms.shopPasses[pass.key] = true
	local ok, res = ShopService.GrantPass(d, pass, now())
	if not ok or type(res) ~= "table" or not res.changed then
		return
	end
	api.dirty(ms)
	if announce then
		toast(ms, string.format(TEXT_LOCAL.passGranted, pass.name, names(res.cosmetics)))
		notice(ms, { event = "pass", pass = pass.key, name = pass.name, cosmetics = res.cosmetics })
	end
	restyle(ms, d)
end

---------------------------------------------------------------- Aktionen
local function buy(ms: any, data: any, d: any, t: number): boolean
	-- Freischaltung (§12): DLC-Auto ab dem Level des Basismodells ("car:<basis>" aus GameConfig.Unlocks)
	local m = ShopRules.DlcModel(data.item)
	if m and m.base then
		local key = "car:" .. tostring(m.base)
		if Unlocks.Known(key) then
			local okU, msg = Unlocks.Gate(d, key)
			if not okU then
				toast(ms, msg)
				return false
			end
		end
	end
	local ok, res = ShopRules.Buy(d, data.item, t)
	if not ok then
		toast(ms, res)
		return false
	end
	toast(ms, res.text)
	notice(ms, {
		event = "bought", kind = res.kind, item = res.item.id, name = res.item.name,
		price = res.price, carId = res.car and res.car.id or nil,
	})
	api.dirty(ms)
	if res.kind == "car" then
		api.worldChanged(ms) -- Garage-Liste (2.4.0-Revision + voller Snapshot)
	end
	restyle(ms, d)
	return true
end

local function equip(ms: any, data: any, d: any): boolean
	local ok, msg = ShopRules.Equip(d, data.slot, data.item)
	if not ok then
		toast(ms, msg) -- nil = unverändert (Doppelklick), still
		return false
	end
	toast(ms, msg)
	notice(ms, { event = "equipped", slot = data.slot, item = ShopRules.Shop(d).equipped[data.slot] or "" })
	api.dirty(ms)
	restyle(ms, d)
	return true
end

local function prompt(ms: any, data: any, d: any, t: number): boolean
	if t < (ms.shopPromptAt or 0) then
		return false
	end
	local pass = ShopRules.Pass(data.product)
	if pass then
		local id = passId(pass)
		if id <= 0 then
			toast(ms, TEXT.notReady)
			return false
		end
		if (ms.shopPasses and ms.shopPasses[pass.key]) or ShopRules.ProductOwned(d, pass) then
			toast(ms, TEXT_LOCAL.passOwned)
			return false
		end
		if RunService:IsStudio() or not api.writable(ms) then
			toast(ms, TEXT_LOCAL.noRobux)
			return false
		end
		ms.shopPromptAt = t + PROMPT_SECONDS
		local ok = pcall(function()
			MarketplaceService:PromptGamePassPurchase(ms.player, id)
		end)
		if not ok then
			toast(ms, TEXT_LOCAL.promptFailed)
			return false
		end
		return true
	end
	local ok, msg, productId, product = ShopRules.CanPrompt(d, data.product)
	if not ok then
		toast(ms, msg)
		return false
	end
	if RunService:IsStudio() or not api.writable(ms) then
		toast(ms, TEXT_LOCAL.noRobux)
		return false
	end
	if product.kind == "credits" then
		local credits = type(product.pack) == "table" and product.pack.credits or (product.grants and product.grants.credits) or 0
		if not finite(credits) or credits <= 0 or d.money + credits > C.NumberCap or d.money + credits - d.money ~= credits then
			toast(ms, TEXT_LOCAL.capped)
			return false
		end
	end
	ms.shopPromptAt = t + PROMPT_SECONDS
	emitPrompt(ms, productId)
	return true
end

function ShopService.Register(Actions: any, a: any)
	api = a
	Actions.Register("shop_buy", buy)
	Actions.Register("shop_equip", equip)
	Actions.Register("shop_prompt", prompt)
end

function ShopService.Init(c: any?)
	ctx = c
	local ok, err = pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, id, purchased)
			if not purchased then
				return
			end
			local pass = passById(id)
			local ms = sessions[player]
			if not pass or not ms or not alive(ms) then
				return
			end
			local okA, errA = pcall(applyPass, ms, ms.p.profile.data, pass, true)
			if not okA then
				warn("[Shop] Game Pass " .. tostring(pass.key) .. ": " .. tostring(errA))
			end
		end)
	end)
	if not ok then
		warn("[Shop] Game-Pass-Kaufereignis nicht verfügbar: " .. tostring(err))
	end
end

---------------------------------------------------------------- Sitzung
function ShopService.OnJoin(ms: any, d: any, t: number?)
	sessions[ms.player] = ms
	ms.shopPasses = {}
	ms.shopPromptAt = 0
	ShopRules.Shop(d) -- Standard anlegen, falls ein Profil ohne shop in der Sitzung ist
	-- Pass-Besitz prüfen (kann warten); ohne eingetragene Ids (0) kehrt es sofort zurück
	local toCheck = {}
	for _, pass in ipairs(SHOP.Passes) do
		if passId(pass) > 0 then
			table.insert(toCheck, pass)
		end
	end
	if #toCheck == 0 then
		return
	end
	task.spawn(function()
		local owned = {}
		for _, pass in ipairs(toCheck) do
			if ownsPass(ms.userId, passId(pass)) then
				table.insert(owned, pass)
			end
		end
		if not alive(ms) then
			return
		end
		for _, pass in ipairs(owned) do
			local okA, errA = pcall(applyPass, ms, ms.p.profile.data, pass, false)
			if not okA then
				warn("[Shop] Game Pass " .. tostring(pass.key) .. ": " .. tostring(errA))
			end
		end
	end)
end

function ShopService.OnLeave(ms: any)
	if ms and sessions[ms.player] == ms then
		sessions[ms.player] = nil
	end
end

-- Nach einer Robux-Quittung (Purchases.Init-Rückruf in GarageServer): Hinweis an den Spieler, Snapshot/Revision.
-- product = Eintrag aus GameConfig.Shop.Products (Credits-Pakete meldet GarageServer weiter selbst).
function ShopService.OnGranted(p: any, product: any)
	local ms = p and sessions[p.player] or nil
	if not ms or not alive(ms) or type(product) ~= "table" or product.kind == "credits" then
		return
	end
	local d = p.profile.data
	local text = string.format(product.kind == "car" and TEXT.receiptCar or TEXT.receipt, tostring(product.name or product.key))
	toast(ms, text)
	notice(ms, { event = "receipt", product = product.key, kind = product.kind, name = product.name, grants = product.grants })
	api.changed(ms) -- neue Autos/Kosmetik: 2.4.0-Revision + Snapshot
	restyle(ms, d)
end

-- Vertrag §9: Apply(product, snapshot) – Purchases ruft ShopRules.ApplyReceipt direkt (gleiche Funktion)
function ShopService.Apply(product: any, snapshot: any, t: number?): (boolean, any)
	return ShopRules.ApplyReceipt(snapshot, product, t or now())
end

---------------------------------------------------------------- Snapshot und Optik
-- shop = { owned[], equipped{}, dlcCars[], passes{ [key]=true }, catalog (nur full, sticky) }
function ShopService.SnapshotFields(ms: any, d: any, t: number?, full: boolean?): { [string]: any }
	local shop = ShopRules.SnapshotFields(d, full ~= false)
	local passes = {}
	for _, pass in ipairs(SHOP.Passes) do
		passes[pass.key] = (ms and ms.shopPasses and ms.shopPasses[pass.key] == true) or ShopRules.ProductOwned(d, pass)
	end
	shop.passes = passes
	return { shop = shop }
end

-- Für VehicleFactory.ApplyCosmetics(model, car, ShopService.CosmeticsFor(d, car)): angelegte Kosmetik je Platz
-- (nur Besitz), DLC-Autos tragen ohne angelegte Folierung ihre exklusive (ShopRules.Resolve).
function ShopService.CosmeticsFor(d: any, car: any): { [string]: any }
	local ok, res = pcall(ShopRules.Resolve, d, car)
	if ok and type(res) == "table" then
		return res
	end
	return {}
end

-- Für Tests/Integrator: Sitzung eines Spielers
function ShopService.Session(player: any): any
	return sessions[player]
end

return ShopService
