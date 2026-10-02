-- Ausbaustufe 4, Meilenstein 8 (Team client): ShopUI (Tab „shop“) im Mock-Client mit einem Katalog-Snapshot aus den
-- echten Regeln (ShopRules.SnapshotFields(d, true)) und VehicleFactory.ApplyCosmetics auf gebauten Fahrzeugen.
-- Der Client sendet nur Absichten (shop_prompt/shop_buy/shop_equip/mini_pass_prompt); geprüft werden Aufbau,
-- Nutzlasten, Zustände (Belohnung, Level, Guthaben, Besitz, Platzhalter-Ids) und die Kosmetik am Auto
-- (≤ 40 Parts, Massless, CanCollide false, verschweißt, Trail, sauberes Entfernen).
local NOW = 1760000000

---------------------------------------------------------------- Hilfen (wie test_tycoon_ui)
local FORBIDDEN = { amount = true, cost = true, credits = true, reward = true, money = true, cash = true, xp = true, level = true, price = true }

local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
			T.check(not FORBIDDEN[k], action .. ": Client sendet verbotenes Feld " .. tostring(k))
		end
		T.check(n <= 10, action .. ": höchstens 10 Felder")
		table.insert(r.sent, { action = action, payload = payload })
		return #r.sent
	end
	r.SendRaw = r.Send
	function r.Last(action)
		for i = #r.sent, 1, -1 do
			if r.sent[i].action == action then
				return r.sent[i].payload
			end
		end
		return nil
	end
	function r.Count(action)
		local n = 0
		for _, s in ipairs(r.sent) do
			if s.action == action then
				n += 1
			end
		end
		return n
	end
	return r
end

local function startClient(H)
	local g = H.Garage()
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1.5)
	return g, p
end

local function build(g, p, rec, ctxExtra)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini.ShopUI")
	local toasts = {}
	local page = g:InClient(p, function()
		if not MiniUI.Gui then
			MiniUI.Build()
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "ShopTest"
		gui.ResetOnSpawn = false
		gui.Parent = p.PlayerGui
		local frame = MiniUI.Frame(gui, { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(0, 338, 0, 0) })
		MiniUI.List(frame, 12)
		local ctx = {
			UI = MiniUI, Remote = rec,
			Toast = function(text)
				table.insert(toasts, text)
			end,
			Close = function()
				MiniUI.Close()
			end,
			IsTabletOpen = function()
				return false
			end,
			IsBlocked = function()
				return false
			end,
		}
		for k, v in pairs(ctxExtra or {}) do
			ctx[k] = v
		end
		mod.Build(frame, ctx)
		return frame
	end)
	return mod, page, MiniUI, toasts
end

local function render(g, p, mod, s)
	g:InClient(p, function()
		mod.Render(s)
	end)
end

local function find(root, pred)
	for _, x in ipairs(root:GetDescendants()) do
		if pred(x) then
			return x
		end
	end
	return nil
end

local function byName(root, name)
	return find(root, function(x)
		return x.Name == name
	end)
end

local function withText(root, text)
	return find(root, function(x)
		local t = x.Text
		return type(t) == "string" and t:find(text, 1, true) ~= nil
	end)
end

local function enabled(b)
	return b ~= nil and b:GetAttribute("disabled") ~= true
end

local function press(g, button, opts)
	g:Advance(0.35)
	local ok = g:Click(button, opts)
	g:Advance(0.05)
	return ok
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

-- Profil mit Shop-Daten (wie test_shop_rules) und Snapshot aus den echten Regeln
local function profile(g, level, money)
	local SR = g:MiniShared("ShopRules")
	local d = g:Rules().NewData(NOW)
	d.level = level or 1
	d.money = money or 0
	g:MiniShared("CarRules").ApplyDefault(d.games)
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	g:MiniShared("StoryRules").ApplyDefault(d.games)
	SR.ApplyDefault(d.games)
	return d, SR
end

local function snapshot(g, d, extra)
	local SR = g:MiniShared("ShopRules")
	local shop = SR.SnapshotFields(d, true)
	shop.passes = { neon = false, deko = false }
	local s = {
		credits = d.money, level = d.level, mode = "openworld", placeKind = "all", simulated = true,
		shop = shop,
		passes = { doubleScrap = false, pressPlus = false, doubleScrapConfigured = true, pressPlusConfigured = false },
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

-- Katalog-Einträge nach Schlüssel
local function product(cat, key)
	for _, p in ipairs(cat.products) do
		if p.key == key then
			return p
		end
	end
	return nil
end
local function pass(cat, key)
	for _, p in ipairs(cat.passes) do
		if p.key == key then
			return p
		end
	end
	return nil
end

---------------------------------------------------------------- Fahrzeuge
local function vehicle(g, modelId)
	local CR = g:MiniShared("CarRules")
	local CC = g:MiniShared("CarCatalog")
	local VF = g:MiniServer("VehicleFactory")
	local car = CR.NewCar(modelId, 0)
	car.id = 3
	local m = CC.Model(modelId)
	local model, err = VF.Build({ body = m.body, car = car, stats = CR.Stats(car), name = "T_" .. modelId, ownerId = 5, carId = 3,
		modelId = modelId, cframe = CFrame.new(50, 0, 20) * CFrame.Angles(0, math.rad(20), 0), plate = "UCG · 03" })
	return model, err, VF, car
end

local function partsIn(folder)
	local out = {}
	if folder then
		for _, x in ipairs(folder:GetDescendants()) do
			if x:IsA("BasePart") then
				table.insert(out, x)
			end
		end
	end
	return out
end

local function weldedTo(part, model)
	for _, x in ipairs(part:GetChildren()) do
		if x:IsA("WeldConstraint") and x.Part1 == part and x.Part0 and x.Part0:IsDescendantOf(model) then
			return true
		end
	end
	return false
end

return {
	---------------------------------------------------------------- ShopUI
	{ "ShopUI: Seite baut aus dem Katalog (Credits, Autos mit Vorschau, Kosmetik-Kacheln je Platz, Pässe, Fußzeile)", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page = build(g, p, rec)
		local d = profile(g, 5, 5000)
		local s = snapshot(g, d)
		local cat = s.shop.catalog
		render(g, p, mod, s)
		T.eq(g:ErrorText(), "", "keine Fehler beim Rendern")

		T.check(withText(page, "Shop") ~= nil, "Titel Shop")
		T.check(withText(page, "Credits") ~= nil, "Abschnitt Credits")
		T.check(withText(page, "Autos") ~= nil, "Abschnitt Autos")
		T.check(withText(page, "Kosmetik") ~= nil, "Abschnitt Kosmetik")
		T.check(withText(page, "Pässe") ~= nil, "Abschnitt Pässe")
		local policy = byName(page, "Policy")
		T.check(policy and policy.Text == "Alle Inhalte sind auch ohne Robux erreichbar. Keine Zufallskisten.", "Richtlinien-Fußzeile")
		T.check(withText(page, "Guthaben: ") ~= nil, "Guthaben-Zeile")
		T.check(withText(page, "wird geladen") == nil or not withText(page, "wird geladen").Visible, "Ladehinweis aus")

		-- Credits-Pakete: eines je Produkt kind=credits
		local packs = 0
		for _, pr in ipairs(cat.products) do
			if pr.kind == "credits" then
				packs += 1
				T.check(byName(page, "Buy_" .. pr.key) ~= nil, "Knopf für Paket " .. pr.key)
			end
		end
		T.check(packs == 5, "fünf Credits-Pakete im Katalog (" .. packs .. ")")

		-- DLC-Autos mit ViewportFrame-Vorschau aus PreviewCars
		T.check(#cat.cars >= 3, "mindestens drei DLC-Autos")
		for _, e in ipairs(cat.cars) do
			local card = byName(page, "Car_" .. e.id)
			if T.check(card ~= nil, "Karte " .. e.id) then
				local view = card:FindFirstChildOfClass("ViewportFrame")
				T.check(view ~= nil, "ViewportFrame " .. e.id)
				local world = view and view:FindFirstChildOfClass("WorldModel")
				local clone = world and world:FindFirstChild(e.body)
				T.check(clone ~= nil, "Karosserie " .. tostring(e.body) .. " aus PreviewCars geklont")
				T.check(byName(card, "Robux_" .. e.id) ~= nil and byName(card, "Buy_" .. e.id) ~= nil, "Robux- und Credits-Knopf " .. e.id)
				T.check(withText(card, "Level") ~= nil, "Level am Auto " .. e.id)
				T.check(withText(card, "PS") ~= nil, "Fahrwerte am Auto " .. e.id)
			end
		end

		-- Kosmetik: je Platz ein Block, je Eintrag eine Kachel mit Vorschau
		for _, slot in ipairs(cat.slots) do
			T.check(byName(page, "Slot_" .. slot) ~= nil, "Block für Platz " .. slot)
		end
		local tiles = 0
		for _, c in ipairs(cat.cosmetics) do
			local tile = byName(page, "Cos_" .. c.id)
			if T.check(tile ~= nil, "Kachel " .. c.id) then
				tiles += 1
				T.check(tile:FindFirstChild("Swatch") ~= nil, "Vorschau " .. c.id)
				T.check(byName(tile, "Act_" .. c.id) ~= nil, "Aktionsknopf " .. c.id)
			end
		end
		T.eq(tiles, #cat.cosmetics, "eine Kachel je Kosmetik")
		-- Folierungen als Muster: Streifen (2 Balken), Karo (12 Felder), Flammen (5 Zungen)
		local streifen = byName(page, "Cos_wrap_streifen")
		local n = 0
		for _, x in ipairs(streifen.Swatch:GetChildren()) do
			if x.Name == "Streifen" then
				n += 1
			end
		end
		T.eq(n, 2, "Rennstreifen: zwei Streifen in der Kachel")
		local karo = byName(page, "Cos_wrap_karo")
		n = 0
		for _, x in ipairs(karo.Swatch:GetChildren()) do
			if x.Name == "Karo" then
				n += 1
			end
		end
		T.eq(n, 12, "Zielflagge: Karofelder in der Kachel")
		local flammen = byName(page, "Cos_wrap_flammen")
		T.check(byName(flammen, "Flamme") ~= nil, "Flammen-Muster in der Kachel")
		local neon = byName(page, "Cos_rims_neon")
		local ring = byName(neon, "Ring")
		T.check(ring ~= nil and ring.Thickness >= 3, "Neonfelgen: Leuchtring in der Kachel")
		local horn = byName(page, "Cos_horn_melodie")
		T.check(withText(horn, "Tü-dü") ~= nil, "Hupe: Text in der Kachel")
		local trail = byName(page, "Cos_trail_regenbogen")
		T.check(byName(trail, "Spur") ~= nil and byName(trail, "Spur"):FindFirstChildOfClass("UIGradient") ~= nil, "Regenbogenspur: Verlauf")
		-- Pakete (Bündel) mit Robux-Knopf
		T.check(byName(page, "Bundles") ~= nil and byName(page, "Robux_bundle_starter") ~= nil, "Starter-Set als Paket")

		-- Pässe: zwei neue + Presse-Pässe
		T.check(byName(page, "Pass_neon") ~= nil and byName(page, "Pass_deko") ~= nil, "Neon-Paket und Werkstatt-Deko")
		T.check(withText(page, "2× Schrott") ~= nil and withText(page, "Schrottpresse+") ~= nil, "Presse-Pässe weiterhin da")
		T.eq(#rec.sent, 0, "Aufbau sendet nichts")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "ShopUI: Knöpfe senden shop_prompt / shop_buy / shop_equip / mini_pass_prompt mit den richtigen Nutzlasten", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI = build(g, p, rec)
		local d = profile(g, 20, 50000)
		local s = snapshot(g, d)
		local cat = s.shop.catalog
		-- Platzhalter-Ids 0: kein Prompt. Für den Test ein paar Produkte als „eingerichtet“ markieren.
		local packKey = nil
		for _, pr in ipairs(cat.products) do
			if pr.kind == "credits" and not packKey then
				packKey = pr.key
				pr.ready = true
			end
		end
		product(cat, "car_komet_sunset").ready = true
		product(cat, "cos_rims_gold").ready = true
		product(cat, "bundle_starter").ready = true
		pass(cat, "neon").ready = true
		render(g, p, mod, s)

		-- Credits-Paket -> shop_prompt {product}
		local packBtn = byName(page, "Buy_" .. packKey)
		T.check(enabled(packBtn), "eingerichtetes Paket kaufbar")
		press(g, packBtn)
		T.check(H.DeepEqual(rec.Last("shop_prompt"), { product = packKey }), "Paket: shop_prompt {product}")
		-- nicht eingerichtetes Paket: Knopf aus, kein Prompt
		local other = nil
		for _, pr in ipairs(cat.products) do
			if pr.kind == "credits" and pr.key ~= packKey then
				other = byName(page, "Buy_" .. pr.key)
				break
			end
		end
		T.check(other ~= nil and not enabled(other) and other.Text:find("Noch nicht", 1, true), "Platzhalter-Paket: aus, Hinweis")
		local before = #rec.sent
		press(g, other)
		T.eq(#rec.sent, before, "Platzhalter-Paket sendet nichts")

		-- DLC-Auto: Robux -> shop_prompt {product}, Credits -> Bestätigung -> shop_buy {item}
		local robux = byName(page, "Robux_dlc_komet_sunset")
		T.check(enabled(robux), "Robux-Knopf des eingerichteten Autos an")
		press(g, robux)
		T.check(H.DeepEqual(rec.Last("shop_prompt"), { product = "car_komet_sunset" }), "Auto: shop_prompt {product=car_komet_sunset}")
		local buy = byName(page, "Buy_dlc_komet_sunset")
		T.check(enabled(buy) and buy.Text:find("Level", 1, true), "Credits-Knopf mit Level")
		press(g, buy)
		T.eq(rec.Last("shop_buy"), nil, "erst Bestätigung")
		T.check(MiniUI.Shade.Visible and MiniUI.ConfirmText.Text:find("Komet S2 Sunset", 1, true), "Dialog nennt das Auto")
		press(g, MiniUI.ConfirmYes)
		T.check(H.DeepEqual(rec.Last("shop_buy"), { item = "dlc_komet_sunset" }), "Auto: shop_buy {item=dlc_komet_sunset}")
		-- nicht eingerichtetes Auto: Robux-Knopf aus
		local nacht = byName(page, "Robux_dlc_nord_nacht")
		T.check(nacht ~= nil and not enabled(nacht), "Platzhalter-Auto: Robux-Knopf aus")

		-- Kosmetik kaufen (Credits) -> shop_buy {item}
		local act = byName(page, "Act_wrap_streifen")
		T.check(enabled(act) and act.Text == "Kaufen", "Rennstreifen kaufbar")
		press(g, act)
		T.check(H.DeepEqual(rec.Last("shop_buy"), { item = "wrap_streifen" }), "Kosmetik: shop_buy {item=wrap_streifen}")
		-- Kosmetik per Robux (Einzelprodukt) -> shop_prompt
		local goldRobux = byName(page, "Robux_rims_gold")
		T.check(enabled(goldRobux), "Goldfelgen: Robux-Knopf an")
		press(g, goldRobux)
		T.check(H.DeepEqual(rec.Last("shop_prompt"), { product = "cos_rims_gold" }), "Kosmetik: shop_prompt {product=cos_rims_gold}")
		-- Paket -> shop_prompt
		press(g, byName(page, "Robux_bundle_starter"))
		T.check(H.DeepEqual(rec.Last("shop_prompt"), { product = "bundle_starter" }), "Paket: shop_prompt {product=bundle_starter}")

		-- Besitz: Anlegen -> shop_equip {slot, item}; angelegt: Ablegen -> shop_equip {slot, item=""}
		s.shop.owned = { "wrap_streifen", "rims_gold" }
		render(g, p, mod, s)
		act = byName(page, "Act_wrap_streifen")
		T.check(enabled(act) and act.Text == "Anlegen", "gekauft -> Anlegen")
		press(g, act)
		T.check(H.DeepEqual(rec.Last("shop_equip"), { slot = "wrap", item = "wrap_streifen" }), "shop_equip {slot=wrap, item=wrap_streifen}")
		T.check(byName(page, "Robux_rims_gold").Visible == false, "Robux-Knopf verschwindet bei Besitz")
		s.shop.equipped.wrap = "wrap_streifen"
		render(g, p, mod, s)
		act = byName(page, "Act_wrap_streifen")
		T.check(enabled(act) and act.Text == "Ablegen", "angelegt -> Ablegen")
		T.check(withText(byName(page, "Cos_wrap_streifen"), "Angelegt") ~= nil, "Kachel zeigt Angelegt")
		press(g, act)
		T.check(H.DeepEqual(rec.Last("shop_equip"), { slot = "wrap", item = "" }), "shop_equip {slot=wrap, item=\"\"}")
		local unequip = byName(page, "Unequip_wrap")
		T.check(unequip.Visible and enabled(unequip), "Ablegen-Knopf des Platzes sichtbar")
		local n = rec.Count("shop_equip")
		press(g, unequip)
		T.eq(rec.Count("shop_equip"), n + 1, "Platz-Ablegen sendet")
		T.check(H.DeepEqual(rec.Last("shop_equip"), { slot = "wrap", item = "" }), "Platz-Ablegen: item leer")
		T.check(byName(page, "Unequip_rims").Visible == false, "Ablegen nur bei angelegtem Platz")

		-- Pässe: neu -> shop_prompt {product=key}; Presse -> mini_pass_prompt {pass}
		local neonBtn = byName(page, "Robux_neon")
		T.check(enabled(neonBtn), "Neon-Paket eingerichtet -> kaufbar")
		press(g, neonBtn)
		T.check(H.DeepEqual(rec.Last("shop_prompt"), { product = "neon" }), "Pass: shop_prompt {product=neon}")
		local deko = byName(page, "Robux_deko")
		T.check(deko ~= nil and not enabled(deko), "Werkstatt-Deko (Platzhalter) aus")
		local double = withText(page, "2× Schrott kaufen")
		T.check(enabled(double), "2× Schrott eingerichtet")
		press(g, double)
		T.check(H.DeepEqual(rec.Last("mini_pass_prompt"), { pass = "DoubleScrap" }), "mini_pass_prompt {pass=DoubleScrap}")
		local plus = withText(page, "Schrottpresse+ kaufen")
		T.check(plus ~= nil and not enabled(plus), "Schrottpresse+ (nicht eingerichtet) aus")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "ShopUI: Zustände – Belohnung, Level, Guthaben, Gekauft, Pass aktiv, Snapshot ohne Katalog", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page = build(g, p, rec)
		-- Snapshot ohne Katalog zuerst: Ladehinweis, keine Fehler, Presse-Pässe trotzdem gerendert
		render(g, p, mod, { credits = 10, level = 1, shop = { owned = {}, equipped = {}, dlcCars = {} }, passes = { doubleScrap = true, doubleScrapConfigured = true } })
		T.check(withText(page, "wird geladen").Visible, "Ladehinweis ohne Katalog")
		T.check(withText(page, "Bereits aktiv") ~= nil, "Presse-Pass aktiv ohne Katalog")

		local d = profile(g, 1, 100)
		local s = snapshot(g, d)
		render(g, p, mod, s)
		-- Belohnungen: nicht kaufbar, Herkunft sichtbar
		local mega = byName(page, "Cos_wrap_mega")
		T.check(withText(mega, "Kapitel 5") ~= nil, "wrap_mega zeigt die Story-Herkunft")
		T.check(not enabled(byName(page, "Act_wrap_mega")), "Belohnung nicht kaufbar")
		local pr = byName(page, "Cos_wrap_prestige_1")
		T.check(pr ~= nil and withText(pr, "Prestige-Rang 1") ~= nil, "Prestige-Folierung zeigt den Rang")
		local sunset = byName(page, "Cos_wrap_sunset")
		T.check(withText(sunset, "Beigabe") ~= nil, "DLC-Beigabe zeigt das Auto")
		-- Level zu niedrig: Kaufen aus, Hinweis in Gelb; Guthaben zu klein: aus
		local flammen = byName(page, "Act_wrap_flammen")
		T.check(not enabled(flammen), "Flammen (Level 3) bei Level 1 aus")
		T.check(withText(byName(page, "Cos_wrap_flammen"), "ab Level 3") ~= nil, "Level-Hinweis")
		T.check(not enabled(byName(page, "Act_rims_gold")), "Goldfelgen bei 100 Credits aus")
		-- Autos: Level und Guthaben
		local buy = byName(page, "Buy_dlc_vektor_blitz")
		T.check(not enabled(buy), "Vektor RS Blitz bei Level 1 nicht für Credits")
		T.check(withText(byName(page, "Car_dlc_vektor_blitz"), "ab Level") ~= nil, "Level-Hinweis am Auto")

		-- Reich und hoch im Level: alles kaufbar; dann Besitz/Gekauft
		d.level, d.money = 90, 10000000
		s = snapshot(g, d)
		render(g, p, mod, s)
		T.check(enabled(byName(page, "Act_wrap_flammen")) and enabled(byName(page, "Act_rims_gold")), "mit Level und Guthaben kaufbar")
		T.check(enabled(byName(page, "Buy_dlc_vektor_blitz")), "Auto für Credits kaufbar")
		s.shop.dlcCars = { "dlc_vektor_blitz" }
		s.shop.owned = { "wrap_blitz" }
		s.shop.passes.neon = true
		render(g, p, mod, s)
		local card = byName(page, "Car_dlc_vektor_blitz")
		T.check(withText(card, "Garage ✓") ~= nil, "gekauftes Auto: in der Garage")
		T.check(not enabled(byName(page, "Buy_dlc_vektor_blitz")) and not enabled(byName(page, "Robux_dlc_vektor_blitz")), "gekauftes Auto: beide Knöpfe aus")
		T.check(enabled(byName(page, "Act_wrap_blitz")) and byName(page, "Act_wrap_blitz").Text == "Anlegen", "Beigabe-Folierung anlegbar")
		local neon = byName(page, "Pass_neon")
		T.check(withText(neon, "Bereits aktiv") ~= nil and not enabled(byName(page, "Robux_neon")), "Pass aktiv: Knopf aus")
		-- Katalog bleibt erhalten, wenn ein Snapshot ohne Katalog folgt (sticky)
		s.shop.catalog = nil
		s.shop.equipped.wrap = "wrap_blitz"
		render(g, p, mod, s)
		T.check(byName(page, "Act_wrap_blitz").Text == "Ablegen", "Katalog bleibt, Zustand aktualisiert")
		T.eq(#rec.sent, 0, "Rendern sendet nichts")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	---------------------------------------------------------------- VehicleFactory.ApplyCosmetics
	{ "VehicleFactory.ApplyCosmetics: Folierung, Felgen, Hupe, Spur – ≤ 40 Parts, Massless, verschweißt, Trail, Entfernen", function(T, H)
		local g = H.Garage({ noServer = true })
		g:Activate()
		local GC = g:MiniShared("GameConfig")
		local model, err, VF = vehicle(g, "komet_s2")
		if not T.check(model ~= nil, "gebaut: " .. tostring(err)) then
			return
		end
		local function descendantsCount()
			local n = 0
			for _, x in ipairs(model:GetDescendants()) do
				if x:IsA("BasePart") then
					n += 1
				end
			end
			return n
		end
		local baseParts = descendantsCount()
		local rimBefore = nil
		for _, x in ipairs(model:GetDescendants()) do
			if x:IsA("BasePart") and x.Name == "WheelFLRim" then
				rimBefore = x.Color
			end
		end
		local C = GC.Shop.CosmeticById
		local cos = { wrap = C.wrap_flammen, rims = C.rims_neon, horn = C.horn_melodie, trail = C.trail_regenbogen }
		local n = VF.ApplyCosmetics(model, cos)
		T.check(type(n) == "number" and n > 0 and n <= VF.MaxCosmeticParts, "Parts angelegt: " .. tostring(n) .. " ≤ 40")
		local folder = model:FindFirstChild("Cosmetics")
		T.check(folder ~= nil, "Ordner Cosmetics im Modell")
		local parts = partsIn(folder)
		T.eq(#parts, n, "alle neuen Parts im Ordner")
		T.eq(descendantsCount(), baseParts + n, "keine Parts außerhalb des Ordners")
		local wraps, rings = 0, 0
		for _, part in ipairs(parts) do
			T.check(part.Massless == true, "Massless: " .. part.Name)
			T.check(part.CanCollide == false and part.CanTouch == false and part.CanQuery == false, "keine Kollision: " .. part.Name)
			T.check(part.Anchored == false, "unverankert: " .. part.Name)
			T.check(weldedTo(part, model), "verschweißt: " .. part.Name)
			if part.Name == "Wrap" then
				wraps += 1
				T.check(part.Transparency == 0, "Wrap sichtbar")
			elseif part.Name:sub(1, 7) == "RimNeon" then
				rings += 1
				T.check(part.Material == Enum.Material.Neon, "Leuchtring Neon")
				T.check(part:FindFirstChild("Weld").Part0 == model:FindFirstChild("Wheel_" .. part.Name:sub(-2)), "Leuchtring am Rad")
			end
		end
		T.check(wraps >= 8, "Flammen: mehrere Teile (" .. wraps .. ")")
		T.eq(rings, 4, "vier Leuchtringe")
		-- Felgenfarbe überdeckt
		local rim = nil
		for _, x in ipairs(model:GetDescendants()) do
			if x:IsA("BasePart") and x.Name == "WheelFLRim" then
				rim = x
			end
		end
		if rim then
			local want = C.rims_neon.style.color
			T.check(rim.Color == Color3.fromRGB(want[1], want[2], want[3]), "Felgenfarbe aus dem Set")
		end
		-- Hupe: Schild mit Text, Lichthupe, Attribute
		local plate = folder:FindFirstChild("HornPlate")
		T.check(plate ~= nil and plate:FindFirstChild("HornText") ~= nil, "Hupen-Schild mit SurfaceGui")
		local label = plate and plate.HornText:FindFirstChild("Label")
		T.check(label and label.Text == C.horn_melodie.style.text, "Hupentext auf dem Schild")
		local bar = folder:FindFirstChild("Lichthupe")
		T.check(bar ~= nil and bar.Transparency == 1 and bar:FindFirstChild("FlashLight") ~= nil, "Lichthupe vorhanden, aus")
		T.eq(model:GetAttribute("HornText"), C.horn_melodie.style.text, "Attribut HornText")
		T.check(typeof(model:GetAttribute("HornLight")) == "Color3", "Attribut HornLight")
		T.check(VF.Flash(model, 0.2), "Flash blitzt")
		T.eq(bar.Transparency, 0, "Lichthupe an")
		T.eq(bar.FlashLight.Enabled, true, "Licht an")
		g:Advance(0.5)
		T.eq(bar.Transparency, 1, "Lichthupe wieder aus")
		T.eq(bar.FlashLight.Enabled, false, "Licht wieder aus")
		-- Spur: Trails an beiden Hinterrädern mit Attachments am Chassis
		local trails = {}
		for _, x in ipairs(folder:GetChildren()) do
			if x:IsA("Trail") then
				table.insert(trails, x)
			end
		end
		T.eq(#trails, 2, "zwei Trails (RL, RR)")
		for _, t in ipairs(trails) do
			T.check(t.Attachment0 ~= nil and t.Attachment1 ~= nil and t.Attachment0.Parent == model.Chassis and t.Attachment1.Parent == model.Chassis, "Trail-Attachments am Chassis: " .. t.Name)
			T.check(t.Enabled == true, "Trail an")
		end
		local info = VF.Cosmetics(model)
		T.check(info and info.ids.wrap == "wrap_flammen" and info.ids.trail == "trail_regenbogen", "Cosmetics(): Ids")
		T.eq(model:GetAttribute("Cosmetic_wrap"), "wrap_flammen", "Attribut Cosmetic_wrap")
		T.eq(model:GetAttribute("Cosmetic_rims"), "rims_neon", "Attribut Cosmetic_rims")

		-- Waschstraße/Tuning (ApplyStyle) überschreibt das Felgen-Set nicht
		local CR = g:MiniShared("CarRules")
		local car = CR.NewCar("komet_s2", 0)
		VF.ApplyStyle(model, car, true)
		if rim then
			local want = C.rims_neon.style.color
			T.check(rim.Color == Color3.fromRGB(want[1], want[2], want[3]), "Felgen-Set bleibt nach ApplyStyle")
		end

		-- Ersetzen: anderes Set -> alte Teile weg, Anzahl bleibt im Rahmen
		local n2 = VF.ApplyCosmetics(model, { wrap = "wrap_karo", rims = C.rims_gold })
		T.check(n2 > 0 and n2 <= VF.MaxCosmeticParts, "Ersetzen: " .. tostring(n2) .. " Parts")
		T.check(folder.Parent == nil, "alter Ordner entfernt")
		folder = model:FindFirstChild("Cosmetics")
		T.eq(descendantsCount(), baseParts + n2, "nur die neuen Parts im Modell")
		T.eq(model:FindFirstChild("HornPlate", true), nil, "Hupen-Schild entfernt")
		T.eq(#(function()
			local out = {}
			for _, x in ipairs(model:GetDescendants()) do
				if x:IsA("Trail") then
					table.insert(out, x)
				end
			end
			return out
		end)(), 0, "Trails entfernt")
		local att = 0
		for _, x in ipairs(model.Chassis:GetChildren()) do
			if x:IsA("Attachment") and x.Name:sub(1, 5) == "Trail" then
				att += 1
			end
		end
		T.eq(att, 0, "Trail-Attachments entfernt")
		T.eq(model:GetAttribute("HornText"), nil, "HornText-Attribut weg")
		T.eq(model:GetAttribute("Cosmetic_wrap"), "wrap_karo", "Id per String nachgeschlagen")
		if rim then
			local want = C.rims_gold.style.color
			T.check(rim.Color == Color3.fromRGB(want[1], want[2], want[3]), "Goldfelgen")
		end

		-- Alles ablegen: Felgen zurück auf die Palettenfarbe, keine Parts mehr
		T.eq(VF.ApplyCosmetics(model, {}), 0, "leer -> 0 Parts")
		T.eq(descendantsCount(), baseParts, "keine Kosmetik-Parts mehr")
		if rim and rimBefore then
			T.check(rim.Color == rimBefore, "Felgen wieder in Palettenfarbe")
		end

		-- Entfernen mit dem Modell
		VF.ApplyCosmetics(model, cos)
		local keep = partsIn(model:FindFirstChild("Cosmetics"))
		model:Destroy()
		for _, part in ipairs(keep) do
			T.check(part.Parent == nil, "Part mit dem Auto weg: " .. part.Name)
		end
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "VehicleFactory.ApplyCosmetics: alle Muster auf allen Karosserien ≤ 40 Parts, Ids/Müll, zweite Form (model, car, cosmetics)", function(T, H)
		local g = H.Garage({ noServer = true })
		g:Activate()
		local GC = g:MiniShared("GameConfig")
		local CC = g:MiniShared("CarCatalog")
		local VF = g:MiniServer("VehicleFactory")
		local bodies = {}
		for _, m in ipairs(CC.Models) do
			if not bodies[m.body] then
				bodies[m.body] = m.id
			end
		end
		local wraps, rims, horns, trails = {}, {}, {}, {}
		for _, c in ipairs(GC.Shop.Cosmetics) do
			if c.slot == "wrap" then
				table.insert(wraps, c)
			elseif c.slot == "rims" then
				table.insert(rims, c)
			elseif c.slot == "horn" then
				table.insert(horns, c)
			else
				table.insert(trails, c)
			end
		end
		local checked = 0
		for body, modelId in pairs(bodies) do
			local model = vehicle(g, modelId)
			if T.check(model ~= nil, "gebaut " .. body) then
				for i, w in ipairs(wraps) do
					local cos = { wrap = w, rims = rims[(i % #rims) + 1], horn = horns[(i % #horns) + 1], trail = trails[(i % #trails) + 1] }
					local n = VF.ApplyCosmetics(model, cos)
					checked += 1
					T.check(type(n) == "number" and n <= VF.MaxCosmeticParts, w.id .. " auf " .. body .. ": " .. tostring(n) .. " Parts ≤ 40")
					local parts = partsIn(model:FindFirstChild("Cosmetics"))
					T.eq(#parts, n, "Zahl stimmt " .. w.id .. "/" .. body)
					for _, part in ipairs(parts) do
						if not (part.Massless and not part.CanCollide and weldedTo(part, model)) then
							T.check(false, "Part-Regeln verletzt: " .. part.Name .. " (" .. w.id .. "/" .. body .. ")")
							break
						end
					end
				end
				model:Destroy()
			end
		end
		T.check(checked >= 20, "viele Kombinationen geprüft (" .. checked .. ")")

		-- Müll und zweite Form
		local model = vehicle(g, "vektor")
		local CR = g:MiniShared("CarRules")
		local car = CR.NewCar("vektor", 0)
		T.eq(VF.ApplyCosmetics(model, car, { wrap = "gibtsnicht", rims = 42, horn = { style = "x" }, trail = { slot = "wrap", style = {} } }), 0, "Müll -> nichts")
		T.eq(VF.ApplyCosmetics(model, car, { wrap = GC.Shop.CosmeticById.wrap_streifen }), 16, "Form (model, car, cosmetics): Streifen = 16 Segmente")
		T.eq(VF.ApplyCosmetics(model, nil), 0, "nil -> leer")
		T.eq(VF.ApplyCosmetics(Instance.new("Model"), {}), nil, "fremdes Modell -> nil")
		T.check(VF.Flash(model) == true, "Flash ohne Hupe: Scheinwerfer blitzen")
		g:Advance(1)
		model:Destroy()
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },
}
