-- Ende-zu-Ende (PHASE4_CONTRACT §9, §13, Meilenstein 8) im echten Server: Kosmetik für Credits kaufen -> anlegen ->
-- Auto holen -> Kosmetik-Teile am Modell; Robux-Quittung eines DLC-Autos -> Auto in der Garage mit den Werten des
-- Basismodells; Prestige-Belohnung landet in shop.owned; Game-Pass-Gutschrift; Speichern/Laden; Credit-Center
-- öffnet den Tab "shop". Produkt-/Pass-Ids werden nur im Test gesetzt (im Spiel 0 = Platzhalter).
local CAR_PRODUCT = 616161
local PASS_NEON = 7101

local function setIds(g, ids)
	local GC = g:MiniShared("GameConfig")
	for key, id in pairs(ids) do
		if GC.Shop.ProductByKey[key] then
			GC.Shop.ProductByKey[key].productId = id
		elseif GC.Shop.PassByKey[key] then
			GC.Shop.PassByKey[key].id = id
		end
	end
end

local function act(g, p, action, payload)
	g:Advance(0.3)
	return g:Act(p, action, payload)
end

local function spawned(g, p, prefix)
	local folder = g.env.workspace:FindFirstChild("PlayerCars")
	return folder and folder:FindFirstChild((prefix or "Car_") .. p.UserId)
end

local function cosmeticParts(model)
	local folder = model and model:FindFirstChild("Cosmetics")
	if not folder then
		return 0, nil
	end
	local n = 0
	for _, x in ipairs(folder:GetDescendants()) do
		if x:IsA("BasePart") then
			n += 1
		end
	end
	return n, folder
end

local function noErrors(T, g)
	T.eq(g:ErrorText(), "", "keine Skriptfehler")
end

return {
	{ "E2E: Kosmetik mit Credits kaufen, anlegen, Auto holen -> Kosmetik-Teile; Umstylen ohne Neubau", function(T, H)
		local g = H.Garage({ level = 12 })
		local p = g:Join(801, { name = "Ada" })
		local d = g:D(p)
		local VF = g:MiniServer("VehicleFactory")
		local CR = g:MiniShared("CarRules")
		local CC = g:MiniShared("CarCatalog")
		T.check(type(d.games.shop) == "table" and type(d.games.shop.owned) == "table", "games.shop über MiniRules.DefaultGames")
		d.money = 200000
		-- Auto kaufen (Händler) und Kosmetik für Credits
		act(g, p, "mini_car_buy", { model = "komet" })
		T.eq(#d.games.cars, 1, "Händlerauto gekauft")
		local money = d.money
		local m = g:Mark()
		act(g, p, "shop_buy", { item = "wrap_streifen", rid = 1 })
		act(g, p, "shop_buy", { item = "rims_gold", rid = 2 })
		local shop = d.games.shop
		T.eq(shop.owned.wrap_streifen, true, "Folierung gekauft")
		T.eq(shop.owned.rims_gold, true, "Felgen gekauft")
		T.check(d.money < money, "Credits abgebucht")
		T.check(g:HasToast(p, "Gekauft", m), "Kauf-Toast")
		-- Anlegen (nur Besitz, richtiger Platz)
		act(g, p, "shop_equip", { slot = "wrap", item = "wrap_streifen", rid = 3 })
		act(g, p, "shop_equip", { slot = "rims", item = "rims_gold", rid = 4 })
		act(g, p, "shop_equip", { slot = "horn", item = "horn_fanfare", rid = 5 })
		T.eq(shop.equipped.wrap, "wrap_streifen", "Folierung angelegt")
		T.eq(shop.equipped.rims, "rims_gold", "Felgen angelegt")
		T.eq(shop.equipped.horn, "", "nicht besessene Hupe nicht angelegt")
		-- Auto holen: Kosmetik-Teile am Modell
		local car = d.games.cars[1]
		act(g, p, "mini_car_spawn", { id = car.id, at = "workshop" })
		local model = spawned(g, p)
		if T.check(model ~= nil, "Auto unter workspace.PlayerCars") then
			local n, folder = cosmeticParts(model)
			T.check(folder ~= nil, "Ordner Cosmetics am Modell")
			T.check(n > 0 and n <= VF.MaxCosmeticParts, "Folierungs-Teile vorhanden (" .. n .. " ≤ " .. tostring(VF.MaxCosmeticParts) .. ")")
			T.eq(model:GetAttribute("Cosmetic_wrap"), "wrap_streifen", "Attribut Cosmetic_wrap")
			T.eq(model:GetAttribute("Cosmetic_rims"), "rims_gold", "Attribut Cosmetic_rims")
			T.eq(model:GetAttribute("Cosmetic_horn"), "", "Attribut Cosmetic_horn leer")
			local cos = VF.Cosmetics(model)
			T.check(type(cos) == "table" and cos.ids and cos.ids.wrap == "wrap_streifen", "VehicleFactory.Cosmetics kennt die Folierung")
			-- Umstylen ohne Neubau: ShopService.Restyle (CarService) wendet die neue Kosmetik auf das stehende Auto an
			act(g, p, "shop_buy", { item = "wrap_karo", rid = 6 })
			act(g, p, "shop_equip", { slot = "wrap", item = "wrap_karo", rid = 7 })
			T.eq(spawned(g, p), model, "Auto steht weiter (kein Neubau)")
			T.eq(model:GetAttribute("Cosmetic_wrap"), "wrap_karo", "Folierung live gewechselt")
			-- Ablegen entfernt die Teile
			act(g, p, "shop_equip", { slot = "wrap", item = "", rid = 8 })
			act(g, p, "shop_equip", { slot = "rims", item = "", rid = 9 })
			T.eq(model:GetAttribute("Cosmetic_wrap"), "", "Folierung abgelegt")
			T.eq(cosmeticParts(model), 0, "keine Kosmetik-Teile mehr")
			-- mini_car_style (Lack) setzt die Optik neu: angelegte Kosmetik bleibt
			act(g, p, "shop_equip", { slot = "wrap", item = "wrap_karo", rid = 10 })
			local paint = (car.paint or 1) % #CC.Paints + 1
			act(g, p, "mini_car_style", { id = car.id, paint = paint, rims = car.rims or 1, glow = car.glow or 0, spoiler = car.spoiler == true })
			T.eq(car.paint, paint, "umlackiert")
			T.eq(model:GetAttribute("Cosmetic_wrap"), "wrap_karo", "Folierung nach Umlackieren vorhanden")
			T.check(cosmeticParts(model) > 0, "Teile nach Umlackieren vorhanden")
		end
		-- Snapshot: shop mit owned/equipped, Katalog nur bei full (sticky)
		g:Advance(1)
		local snap = g:MiniSnapshot(p)
		T.check(snap and type(snap.shop) == "table" and snap.shop.equipped.wrap == "wrap_karo", "shop im Snapshot")
		T.check(snap and type(snap.shop.owned) == "table" and #snap.shop.owned >= 3, "owned-Liste im Snapshot")
		T.eq(CR.Find(d, car.id) ~= nil, true, "Auto weiterhin in der Garage")
		noErrors(T, g)
	end },

	{ "E2E: Robux-Quittung DLC-Auto -> Garage, gleiche Werte wie das Basismodell, exklusive Folierung am Modell", function(T, H)
		local g = H.Garage({ level = 10, before = function(g)
			setIds(g, { car_komet_sunset = CAR_PRODUCT })
		end })
		local p = g:Join(802, { name = "Ben" })
		local d = g:D(p)
		local CR = g:MiniShared("CarRules")
		local CC = g:MiniShared("CarCatalog")
		local money0 = d.money
		local m = g:Mark()
		local decision, done = g:Purchase(p, CAR_PRODUCT, "e2e-auto")
		T.check(done, "ProcessReceipt kehrt zurück")
		T.eq(decision, Enum.ProductPurchaseDecision.PurchaseGranted, "PurchaseGranted")
		local car
		for _, c in ipairs(d.games.cars) do
			if c.model == "dlc_komet_sunset" then
				car = c
			end
		end
		T.check(car ~= nil, "DLC-Auto in der Garage")
		T.eq(d.money, money0, "Credits unverändert")
		T.eq(d.games.shop.dlcCars.dlc_komet_sunset, true, "dlcCars markiert")
		T.eq(d.games.shop.owned.wrap_sunset, true, "exklusive Folierung im Besitz")
		local fx = g:Last(p, "purchaseFX", m)
		T.check(fx and fx.title == "Neues Auto!", "purchaseFX 'Neues Auto!'")
		T.check(#g:Notices(p, "shop", m) >= 1, "mini_notice shop (receipt)")
		-- Gleiche Fahrwerte wie das Basismodell (kein Pay-to-win)
		local dlc = CC.Model("dlc_komet_sunset")
		T.check(dlc and dlc.dlc == true and dlc.base == "komet_s2", "Katalog: DLC mit Basis komet_s2")
		if car and dlc then
			local a = CR.Stats(car)
			local b = CR.Stats(CR.NewCar(dlc.base, 0))
			for k, v in pairs(b) do
				if type(v) == "table" then
					T.check(H.DeepEqual(a[k], v), "Fahrwert " .. tostring(k) .. " = Basismodell")
				else
					T.eq(a[k], v, "Fahrwert " .. tostring(k) .. " = Basismodell")
				end
			end
			T.eq(dlc.level, CC.Model(dlc.base).level, "gleiches Level wie das Basismodell")
			-- Holen: exklusive Folierung ohne Anlegen
			act(g, p, "mini_car_spawn", { id = car.id, at = "workshop" })
			local model = spawned(g, p)
			if T.check(model ~= nil, "DLC-Auto draußen") then
				T.eq(model:GetAttribute("Cosmetic_wrap"), "wrap_sunset", "exklusive Folierung am Modell")
				T.check(cosmeticParts(model) > 0, "Folierungs-Teile vorhanden")
			end
		end
		-- Händler verkauft keine DLC-Modelle; Credits-Kauf desselben DLC-Autos ist nach der Quittung abgelehnt
		local before = #d.games.cars
		d.money = 1e7
		act(g, p, "mini_car_buy", { model = "dlc_komet_sunset" })
		T.eq(#d.games.cars, before, "Händler verkauft kein DLC-Modell")
		m = g:Mark()
		act(g, p, "shop_buy", { item = "dlc_komet_sunset", rid = 1 })
		T.eq(#d.games.cars, before, "bereits besessenes DLC-Auto nicht noch einmal")
		-- Quittung wiederholt: kein zweites Auto, Beleg bleibt
		g:Purchase(p, CAR_PRODUCT, "e2e-auto")
		T.eq(#d.games.cars, before, "Wiederholte Quittung ohne zweites Auto")
		T.eq(g:Record(802).receipts["e2e-auto"], true, "Beleg gespeichert")
		noErrors(T, g)
	end },

	{ "E2E: Prestige-Belohnung in shop.owned, Game-Pass-Gutschrift, Speichern/Laden, Credit-Center öffnet 'shop'", function(T, H)
		local g = H.Garage({ level = 100, before = function(g)
			setIds(g, { neon = PASS_NEON })
			g.env.services.MarketplaceService.__data.owned["803:" .. PASS_NEON] = true
		end })
		local p = g:Join(803, { name = "Cleo" })
		g:Advance(1)
		local d = g:D(p)
		local GC = g:MiniShared("GameConfig")
		-- Game Pass beim Beitritt
		local shop = d.games.shop
		for _, id in ipairs(GC.Shop.PassByKey.neon.grants.cosmetics) do
			T.eq(shop.owned[id], true, "Neon-Paket: " .. id)
		end
		-- Prestige Rang 1 (Level 100): Kosmetik-Belohnung landet in shop.owned
		local m = g:Mark()
		act(g, p, "prestige_claim", { rank = 1 })
		local reward = GC.Prestige.Rewards[1].cosmetic
		T.eq(d.games.prestige.claimed[1], true, "Rang 1 abgeholt")
		T.eq(shop.owned[reward], true, "Prestige-Kosmetik im Besitz (" .. tostring(reward) .. ")")
		local n = g:Notices(p, "prestige", m)
		T.check(n[1] and n[1].cosmeticGranted == true, "Hinweis: cosmeticGranted")
		act(g, p, "shop_equip", { slot = "wrap", item = reward, rid = 1 })
		T.eq(shop.equipped.wrap, reward, "Prestige-Folierung angelegt")
		act(g, p, "shop_equip", { slot = "rims", item = "rims_neon", rid = 2 })
		T.eq(shop.equipped.rims, "rims_neon", "Pass-Felgen angelegt")
		-- Belohnungen sind nicht käuflich
		m = g:Mark()
		act(g, p, "shop_buy", { item = "wrap_prestige_3", rid = 3 })
		T.eq(shop.owned.wrap_prestige_3, nil, "Belohnungs-Kosmetik nicht käuflich")
		-- Credit-Center (Station mit MiniTab "shop") öffnet den Tab "shop" (ohne Tablet-Umleitung)
		local city = g.env.workspace:FindFirstChild("City")
		local stations = city and city:FindFirstChild("Stations")
		local station
		for _, s in ipairs(stations and stations:GetChildren() or {}) do
			if s:GetAttribute("MiniTab") == "shop" then
				station = s
			end
		end
		if T.check(station ~= nil, "Credit-Center-Station in der Stadt") then
			m = g:Mark()
			g:Teleport(p, station)
			g:Advance(0.5)
			g:Trigger(p, station:FindFirstChildOfClass("ProximityPrompt"), { force = true })
			g:Advance(0.5)
			local open = g:Last(p, "mini_open", m)
			T.eq(open and open.tab, "shop", "mini_open: Tab shop")
			T.eq(open and open.page, nil, "mini_open: keine Tablet-Seite")
		end
		-- Speichern/Laden: Besitz, Anlegen, Pass-Kosmetik bleiben
		g:Leave(p)
		local rec = g:Record(803)
		T.check(rec and rec.data.games.shop and rec.data.games.shop.owned[reward] == true, "gespeichert: Prestige-Kosmetik")
		T.eq(rec.data.games.shop.equipped.wrap, reward, "gespeichert: angelegt")
		local p2 = g:Join(803, { name = "Cleo" })
		g:Advance(1)
		local d2 = g:D(p2)
		T.eq(d2.games.shop.owned[reward], true, "geladen: Prestige-Kosmetik")
		T.eq(d2.games.shop.owned.rims_neon, true, "geladen: Pass-Kosmetik")
		T.eq(d2.games.shop.equipped.wrap, reward, "geladen: angelegt")
		T.eq(d2.games.shop.equipped.rims, "rims_neon", "geladen: Felgen angelegt")
		-- Älteres Profil ohne shop: Nachtragen aus prestige.claimed beim Laden
		g:Leave(p2)
		local rec2 = g:Record(803)
		rec2.data.games.shop = nil
		local p3 = g:Join(803, { name = "Cleo" })
		g:Advance(1)
		local d3 = g:D(p3)
		T.eq(d3.games.shop.owned[reward], true, "ohne gespeichertes shop: Prestige-Kosmetik nachgetragen")
		T.eq(d3.games.shop.equipped.wrap, "", "ohne gespeichertes shop: nichts angelegt")
		noErrors(T, g)
	end },
}
