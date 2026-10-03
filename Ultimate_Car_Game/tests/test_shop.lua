-- Shop & Monetarisierung im echten Server (docs/PHASE4_CONTRACT.md §9, Meilenstein 8): Robux-Quittungen für
-- DLC-Autos/Kosmetik über Purchases -> Profiles.GrantReceipt (atomar mit dem Profil, idempotent, DataStore-Ausfall),
-- Credits-Käufe (shop_buy), Anlegen (shop_equip), Game Passes (Besitz beim Beitritt, Kaufereignis, idempotent),
-- shop_prompt (Platzhalter 0 -> „noch nicht eingerichtet“, sonst purchasePrompt), Speichern/Laden, Snapshot-Felder.
--
-- Verkabelung: Ist ShopService schon in MiniService eingetragen (Mini.Handlers.shop_buy), läuft alles über den echten
-- Weg. Sonst (Teamarbeit vor der Integration) registriert wire() den Dienst selbst mit einer MiniService-gleichen api,
-- ergänzt MiniNet.Actions um shop_* und hängt ShopRules an MiniRules.DefaultGames/LoadGames – die Prüfungen sind in
-- beiden Fällen dieselben (bis auf w.integrated-Markierungen: Hinweise aus dem GarageServer-Rückruf).
local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
end

local CAR_PRODUCT = 515151
local COS_PRODUCT = 515152
local BUNDLE_PRODUCT = 515153
local PASS_NEON = 7001
local PASS_DEKO = 7002

-- Vor dem Serverstart: Aktionen, Datenmodul, Produkt-Ids (nur im Test gesetzt; Modulinstanzen gelten je Testumgebung)
local function prepare(g, ids)
	local MR = g:MiniShared("MiniRules")
	local SR = g:MiniShared("ShopRules")
	if not MR.DefaultGames().shop then
		local od, ol = MR.DefaultGames, MR.LoadGames
		MR.DefaultGames = function()
			return SR.ApplyDefault(od())
		end
		MR.LoadGames = function(raw, d, now)
			return SR.ApplyLoad(ol(raw, d, now), raw, d, now)
		end
	end
	local GC = g:MiniShared("GameConfig")
	for key, id in pairs(ids or {}) do
		if GC.Shop.ProductByKey[key] then
			GC.Shop.ProductByKey[key].productId = id
		elseif GC.Shop.PassByKey[key] then
			GC.Shop.PassByKey[key].id = id
		end
	end
end

-- Nach dem Serverstart: echten Weg nutzen oder den Dienst selbst anbinden
local function wire(g)
	local Mini = g:Mini()
	local w = { integrated = Mini.Handlers.shop_buy ~= nil, Shop = g:MiniServer("ShopService") }
	if not w.integrated then
		-- erst nach dem Serverstart: MiniService verlangt beim Laden einen Handler je MiniNet-Aktion
		local Net = g:MiniShared("MiniNet")
		Net.Actions.shop_buy = { item = "string" }
		Net.Actions.shop_equip = { slot = "string", item = "string" }
		Net.Actions.shop_prompt = { product = "string" }
		Net.Targets.shop_buy = "item"
		Net.Targets.shop_equip = "slot"
		Net.Targets.shop_prompt = "product"
		local Event = g:Remote("Event")
		local api = {
			now = function()
				return g:Now()
			end,
			toast = function(ms, text)
				if ms.player.Parent and type(text) == "string" and text ~= "" then
					Event:FireClient(ms.player, "toast", text)
				end
			end,
			notice = function(ms, kind, data)
				data = type(data) == "table" and data or {}
				data.kind = kind
				if ms.player.Parent then
					Event:FireClient(ms.player, "mini_notice", data)
				end
			end,
			dirty = function(ms)
				ms.dirty = true
			end,
			worldChanged = function(ms)
				ms.worldChanged = true
			end,
			changed = function(ms)
				ms.dirty = true
			end,
			writable = function(ms)
				return ms.p.profile.writable == true
			end,
			alive = function(ms)
				return Mini.Sessions[ms.player] == ms and not ms.p.closing and ms.player.Parent ~= nil
			end,
		}
		w.Shop.Register({
			Register = function(name, handler)
				Mini.Handlers[name] = handler
			end,
		}, api)
		w.Shop.Init(nil)
	end
	function w.join(userId, opts)
		local p = g:Join(userId, opts)
		g:Advance(0.5)
		local ms = g:MiniState(p)
		if ms and ms.shopPasses == nil then
			w.Shop.OnJoin(ms, g:D(p), g:Now())
			g:Flush()
		end
		return p
	end
	-- Aktion über den echten Weg; vorher 0,3 s, damit die Abklingzeit je Aktion/Ziel (MiniNet) nicht greift
	function w.act(p, action, payload)
		g:Advance(0.3)
		return g:Act(p, action, payload)
	end
	function w.shop(p)
		return g:D(p).games.shop
	end
	function w.cars(p, model)
		local n = 0
		for _, car in ipairs(g:D(p).games.cars) do
			if not model or car.model == model then
				n += 1
			end
		end
		return n
	end
	function w.storedCars(userId, model)
		local rec = g:Record(userId)
		local n = 0
		for _, car in ipairs(rec and rec.data and rec.data.games and rec.data.games.cars or {}) do
			if not model or car.model == model then
				n += 1
			end
		end
		return n
	end
	function w.snapshot(p, full)
		return w.Shop.SnapshotFields(g:MiniState(p), g:D(p), g:Now(), full).shop
	end
	return w
end

local function hasNotice(g, p, event, since)
	for _, n in ipairs(g:Notices(p, "shop", since)) do
		if n.event == event then
			return n
		end
	end
	return nil
end

return {
	{ "Robux-Autoprodukt: Auto genau einmal, Beleg und Profil zusammen, Wiederholung ohne zweites Auto", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { car_komet_sunset = CAR_PRODUCT })
		end })
		local w = wire(g)
		local p = w.join(701, { name = "Ada" })
		local d = g:D(p)
		local money0 = d.money
		local m = g:Mark()
		local decision, done = g:Purchase(p, CAR_PRODUCT, "kauf-auto")
		T.check(done, "ProcessReceipt kehrt zurück")
		T.eq(decision, Enum.ProductPurchaseDecision.PurchaseGranted, "PurchaseGranted")
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "DLC-Auto in der Garage")
		T.eq(w.shop(p).dlcCars.dlc_komet_sunset, true, "dlcCars markiert")
		T.eq(w.shop(p).owned.wrap_sunset, true, "exklusive Folierung als Beigabe")
		T.eq(d.money, money0, "Credits unverändert")
		T.eq(g:Profile(p).transacting, false, "transacting wieder frei")
		T.eq(g:Profile(p).receiptPending, nil, "keine offene Quittung")
		local rec = g:Record(701)
		T.eq(rec.receipts["kauf-auto"], true, "Beleg im DataStore")
		T.eq(w.storedCars(701, "dlc_komet_sunset"), 1, "Auto sofort gespeichert (mit dem Beleg)")
		T.eq(rec.data.games.shop.dlcCars.dlc_komet_sunset, true, "dlcCars gespeichert")
		if w.integrated then
			T.check(hasNotice(g, p, "receipt", m) ~= nil, "mini_notice shop/receipt")
			T.check(g:Last(p, "purchaseFX", m) ~= nil, "purchaseFX gesendet")
		end
		-- Wiederholung desselben Belegs (Roblox wiederholt bei Unsicherheit): gewährt, aber kein zweites Auto
		decision = g:Purchase(p, CAR_PRODUCT, "kauf-auto")
		T.eq(decision, Enum.ProductPurchaseDecision.PurchaseGranted, "Wiederholung PurchaseGranted")
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "kein zweites Auto")
		T.eq(w.storedCars(701, "dlc_komet_sunset"), 1, "gespeichert weiterhin ein Auto")
		-- Neuer (bezahlter) Beleg für dasselbe Produkt: eine Robux-Quittung verfällt nie ohne Gegenwert – das Auto
		-- wird als zweites Exemplar geliefert (der Shop bietet den Prompt bei Besitz gar nicht erst an)
		decision = g:Purchase(p, CAR_PRODUCT, "kauf-auto-2")
		T.eq(decision, Enum.ProductPurchaseDecision.PurchaseGranted, "zweiter Beleg abgeschlossen")
		T.eq(w.cars(p, "dlc_komet_sunset"), 2, "bezahltes Auto geliefert")
		T.eq(g:Record(701).receipts["kauf-auto-2"], true, "zweiter Beleg gespeichert")
		-- Unbekanntes Produkt
		decision = g:Purchase(p, 999999, "kauf-x")
		T.eq(decision, Enum.ProductPurchaseDecision.NotProcessedYet, "unbekanntes Produkt nicht verarbeitet")
		noErrors(T, g)
	end },

	{ "Kosmetik- und Bündel-Produkt: Besitz, Beleg, Credits-Pakete weiter über GrantCredits", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { cos_rims_gold = COS_PRODUCT, bundle_starter = BUNDLE_PRODUCT })
			g:Config().CreditProducts[1].productId = 424242
		end })
		local w = wire(g)
		local p = w.join(702, { name = "Ben" })
		local d = g:D(p)
		local money0 = d.money
		T.eq(g:Purchase(p, COS_PRODUCT, "kauf-felgen"), Enum.ProductPurchaseDecision.PurchaseGranted, "Kosmetik gewährt")
		T.eq(w.shop(p).owned.rims_gold, true, "Goldfelgen im Besitz")
		T.eq(g:Record(702).receipts["kauf-felgen"], true, "Beleg gespeichert")
		T.eq(g:Record(702).data.games.shop.owned.rims_gold, true, "Besitz gespeichert")
		T.eq(d.money, money0, "Kosmetik kostet keine Credits")
		-- Bündel mit schon vorhandenen Goldfelgen (z. B. Wettlauf): Fehlendes gewährt, Vorhandenes in Credits erstattet
		local m = g:Mark()
		T.eq(g:Purchase(p, BUNDLE_PRODUCT, "kauf-set"), Enum.ProductPurchaseDecision.PurchaseGranted, "Bündel gewährt")
		local shop = w.shop(p)
		T.eq(shop.owned.wrap_streifen, true, "Bündel: Folierung")
		T.eq(shop.owned.horn_melodie, true, "Bündel: Hupe")
		T.eq(shop.owned.trail_blau, true, "Bündel: Spur")
		local refund = g:MiniShared("GameConfig").Shop.CosmeticById.rims_gold.creditsPrice
		T.eq(d.money, money0 + refund, "vorhandene Goldfelgen erstattet")
		T.eq(g:Record(702).data.money, money0 + refund, "Erstattung mit dem Beleg gespeichert")
		if w.integrated then
			T.check(g:HasToast(p, "dafür bekommst du", m), "Toast zur Erstattung")
		end
		money0 = d.money
		-- Credits-Paket (2.4.0-Weg über Purchases.ByProduct, beide Listen)
		local credits = g:Config().CreditProducts[1].credits
		T.eq(g:Purchase(p, 424242, "kauf-credits"), Enum.ProductPurchaseDecision.PurchaseGranted, "Credits gewährt")
		T.eq(d.money, money0 + credits, "Credits gutgeschrieben")
		T.eq(g:Record(702).data.money, money0 + credits, "Kontostand gespeichert")
		-- Purchases.ByProduct kennt beide Listen; Validate meldet keine Dubletten
		local Purchases = g:Require("ServerScriptService.Garage.Purchases")
		T.eq(Purchases.ByProduct(COS_PRODUCT) and Purchases.ByProduct(COS_PRODUCT).key, "cos_rims_gold", "ByProduct: Shop-Produkt")
		T.eq(Purchases.ByProduct(424242) and Purchases.ByProduct(424242).credits, credits, "ByProduct: Credits-Paket")
		T.eq(Purchases.ByProduct(0), nil, "Platzhalter 0 ist kein Produkt")
		T.eq(#Purchases.Validate(), 0, "keine doppelten Ids")
		T.eq(Purchases.FX(Purchases.ByProduct(COS_PRODUCT)).title, "Neue Optik!", "purchaseFX-Titel Kosmetik")
		T.eq(Purchases.FX(Purchases.ByProduct(424242)).title, "Credits erhalten", "purchaseFX-Titel Credits")
		noErrors(T, g)
	end },

	{ "Doppelte Produkt-Id über beide Listen: Warnung, keine Gutschrift", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { cos_rims_gold = 424242 })
			g:Config().CreditProducts[1].productId = 424242
		end })
		local w = wire(g)
		local p = w.join(703, { name = "Cem" })
		local Purchases = g:Require("ServerScriptService.Garage.Purchases")
		T.eq(Purchases.ByProduct(424242), nil, "mehrdeutige Id liefert kein Produkt")
		T.eq(#Purchases.Validate(), 1, "Validate meldet die Dublette")
		T.eq(g:Purchase(p, 424242, "kauf-dup"), Enum.ProductPurchaseDecision.NotProcessedYet, "keine Gutschrift bei Dublette")
		T.eq(w.shop(p).owned.rims_gold, nil, "nichts gewährt")
		noErrors(T, g)
	end },

	{ "DataStore-Ausfall während der Quittung: receiptPending bleibt, Minispiele gesperrt, Wiederholung gelingt", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { car_komet_sunset = CAR_PRODUCT })
		end })
		local w = wire(g)
		local ds = g:DataStoreMock()
		local p = w.join(704, { name = "Dora" })
		local d = g:D(p)
		d.money = 50000
		ds.fail = true
		local decision, done = g:Purchase(p, CAR_PRODUCT, "kauf-ausfall")
		T.eq(done, false, "Quittung wartet (Wiederholungen des Schreibens)")
		T.eq(g:Profile(p).transacting, true, "transacting gesetzt")
		T.eq(w.act(p, "shop_buy", { item = "rims_gold", rid = 1 }), "dropped", "Shop-Aktion während transacting gesperrt")
		T.eq(g:Act(p, "mini_scrapyard_sell", { rid = 2 }), "dropped", "Minispiel-Aktion gesperrt")
		g:Advance(4)
		T.eq(done, false, "noch nicht fertig (Entscheidung erst nach den Versuchen)")
		T.check(g:Profile(p).receiptPending ~= nil and g:Profile(p).receiptPending.id == "kauf-ausfall", "receiptPending bleibt")
		T.eq(w.cars(p, "dlc_komet_sunset"), 0, "Auto erst mit dem Beleg (nichts im lebenden Profil)")
		T.eq(g:Record(704).receipts["kauf-ausfall"], nil, "kein Beleg gespeichert")
		T.eq(d.money, 50000, "Geld unverändert")
		-- Autosave darf das offene Profil nicht überschreiben
		local updates = ds.calls.update
		g:Advance(g:Config().AutosaveSeconds + 1)
		T.eq(g:Profile(p).receiptPending.id, "kauf-ausfall", "offene Quittung überlebt den Autosave-Rhythmus")
		-- DataStore wieder da: Purchases wiederholt alle 8 s
		ds.fail = false
		g:Advance(12)
		T.eq(g:Profile(p).receiptPending, nil, "Quittung aufgelöst")
		T.eq(g:Profile(p).transacting, false, "transacting frei")
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "Auto genau einmal")
		T.eq(g:Record(704).receipts["kauf-ausfall"], true, "Beleg gespeichert")
		T.eq(w.storedCars(704, "dlc_komet_sunset"), 1, "Auto gespeichert")
		T.eq(g:Record(704).data.money, 50000, "Kontostand mitgespeichert")
		local _ = updates, decision
		-- Danach: Roblox wiederholt den Beleg -> sofort gewährt, nichts doppelt
		T.eq(g:Purchase(p, CAR_PRODUCT, "kauf-ausfall"), Enum.ProductPurchaseDecision.PurchaseGranted, "Wiederholung gewährt")
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "kein zweites Auto")
		T.eq(w.act(p, "shop_buy", { item = "rims_gold", rid = 3 }), "ok", "danach wieder spielbar")
		noErrors(T, g)
	end },

	{ "Langsamer DataStore: Auto und Beleg erscheinen zusammen; Verlassen mitten in der Quittung bleibt konsistent", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { car_komet_sunset = CAR_PRODUCT, cos_rims_gold = COS_PRODUCT })
		end })
		local w = wire(g)
		local ds = g:DataStoreMock()
		local p = w.join(705, { name = "Emil" })
		ds.updateYield = 2
		local _, done = g:Purchase(p, CAR_PRODUCT, "kauf-langsam")
		T.eq(done, false, "Kauf wartet auf den DataStore")
		T.eq(w.cars(p, "dlc_komet_sunset"), 0, "Auto noch nicht im lebenden Profil")
		g:Advance(3)
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "Auto nach dem Schreiben")
		T.eq(g:Record(705).receipts["kauf-langsam"], true, "Beleg geschrieben")
		T.eq(w.storedCars(705, "dlc_komet_sunset"), 1, "Auto gespeichert")
		-- Verlassen mitten in der nächsten Quittung
		local _, done2 = g:Purchase(p, COS_PRODUCT, "kauf-gehen")
		T.eq(done2, false, "zweite Quittung wartet")
		g:Leave(p)
		g:Advance(15)
		local rec = g:Record(705)
		T.eq(rec.lock, nil, "Sperre frei")
		T.eq(rec.receipts["kauf-gehen"] == true, rec.data.games.shop.owned.rims_gold == true, "Beleg und Besitz nur zusammen")
		T.eq(w.storedCars(705, "dlc_komet_sunset"), 1, "erstes Auto bleibt gespeichert")
		noErrors(T, g)
		ds.updateYield = 0
	end },

	{ "shop_buy mit Credits: zu wenig, ok, zweimal abgelehnt; DLC-Auto mit Level-Sperre und gleichen Werten", function(T, H)
		local g = H.Garage({ level = 5, before = prepare })
		local w = wire(g)
		local p = w.join(706, { name = "Fay" })
		local d = g:D(p)
		d.money = 0
		local m = g:Mark()
		T.eq(w.act(p, "shop_buy", { item = "rims_gold", rid = 1 }), "ok", "Aktion angenommen")
		T.check(g:HasToast(p, "Nicht genug Credits", m), "zu wenig Credits")
		T.eq(w.shop(p).owned.rims_gold, nil, "nichts gekauft")
		d.money = 10000
		m = g:Mark()
		w.act(p, "shop_buy", { item = "rims_gold", rid = 2 })
		T.eq(w.shop(p).owned.rims_gold, true, "Goldfelgen gekauft")
		T.eq(d.money, 10000 - 1200, "Preis abgebucht")
		T.check(g:HasToast(p, "Gekauft", m), "Toast")
		T.check(hasNotice(g, p, "bought", m) ~= nil, "mini_notice shop/bought")
		m = g:Mark()
		w.act(p, "shop_buy", { item = "rims_gold", rid = 3 })
		T.eq(d.money, 8800, "zweiter Kauf: nichts abgebucht")
		T.check(g:HasToast(p, "schon", m), "zweiter Kauf abgelehnt")
		-- Unbekannt, nur Belohnung, Level
		m = g:Mark()
		w.act(p, "shop_buy", { item = "wrap_nix", rid = 4 })
		T.check(g:HasToast(p, "gibt es nicht", m), "unbekannter Artikel")
		m = g:Mark()
		w.act(p, "shop_buy", { item = "wrap_mega", rid = 5 })
		T.check(g:HasToast(p, "nur als Belohnung", m), "Belohnungs-Kosmetik nicht kaufbar")
		T.eq(d.money, 8800, "nichts abgebucht")
		m = g:Mark()
		w.act(p, "shop_buy", { item = "rims_neon", rid = 6 }) -- Level 6
		T.check(g:HasToast(p, "Level 6", m), "Kosmetik mit Level-Sperre")
		-- DLC-Auto: Komet S2 Sunset ab Level 8 (car:komet_s2), 18.000 × 1,5 = 27.000 Cr
		d.money = 40000
		m = g:Mark()
		T.eq(w.act(p, "shop_buy", { item = "dlc_komet_sunset", rid = 7 }), "ok", "Aktion angenommen")
		T.check(g:HasToast(p, "Level 8", m), "DLC-Auto: Level des Basismodells")
		T.eq(w.cars(p, "dlc_komet_sunset"), 0, "kein Auto")
		d.level = 8
		g:Advance(1)
		m = g:Mark()
		w.act(p, "shop_buy", { item = "dlc_komet_sunset", rid = 8 })
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "DLC-Auto gekauft")
		T.eq(d.money, 40000 - 27000, "DLC-Preis = Basispreis × 1,5")
		T.eq(w.shop(p).dlcCars.dlc_komet_sunset, true, "dlcCars markiert")
		T.eq(w.shop(p).owned.wrap_sunset, true, "Folierung als Beigabe")
		T.check(g:HasToast(p, "Garage", m), "Toast neues Auto")
		local CarRules = g:MiniShared("CarRules")
		local base = CarRules.Stats(CarRules.NewCar("komet_s2", 0))
		local dlc = CarRules.Stats(CarRules.NewCar("dlc_komet_sunset", 0))
		T.eq(dlc.power, base.power, "gleiche PS wie das Basismodell")
		T.eq(dlc.topSpeed, base.topSpeed, "gleiche Höchstgeschwindigkeit")
		m = g:Mark()
		w.act(p, "shop_buy", { item = "dlc_komet_sunset", rid = 9 })
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "DLC-Auto nur einmal")
		T.eq(d.money, 13000, "zweiter Kauf: nichts abgebucht")
		T.check(g:HasToast(p, "schon", m), "zweiter Kauf abgelehnt")
		-- Händler verkauft keine DLC-Modelle
		w.act(p, "mini_car_buy", { model = "dlc_komet_sunset", rid = 10 })
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "Händler: kein DLC-Modell")
		noErrors(T, g)
	end },

	{ "shop_equip: nur Besitz, richtiger Platz, ablegen; Snapshot-Felder und CosmeticsFor", function(T, H)
		local g = H.Garage({ level = 8, before = prepare })
		local w = wire(g)
		local p = w.join(707, { name = "Gil" })
		local d = g:D(p)
		local m = g:Mark()
		w.act(p, "shop_equip", { slot = "rims", item = "rims_gold", rid = 1 })
		T.check(g:HasToast(p, "gehört dir noch nicht", m), "ohne Besitz nicht anlegbar")
		T.eq(w.shop(p).equipped.rims, "", "nichts angelegt")
		d.money = 10000
		w.act(p, "shop_buy", { item = "rims_gold", rid = 2 })
		w.act(p, "shop_buy", { item = "horn_melodie", rid = 3 })
		m = g:Mark()
		w.act(p, "shop_equip", { slot = "rims", item = "rims_gold", rid = 4 })
		T.eq(w.shop(p).equipped.rims, "rims_gold", "Felgen angelegt")
		T.check(g:HasToast(p, "Angelegt", m), "Toast")
		T.check(hasNotice(g, p, "equipped", m) ~= nil, "mini_notice shop/equipped")
		m = g:Mark()
		w.act(p, "shop_equip", { slot = "wrap", item = "rims_gold", rid = 5 })
		T.check(g:HasToast(p, "passt nicht", m), "falscher Platz")
		T.eq(w.shop(p).equipped.wrap, "", "Folierung leer")
		m = g:Mark()
		w.act(p, "shop_equip", { slot = "motor", item = "rims_gold", rid = 6 })
		T.check(g:HasToast(p, "Unbekannter Platz", m), "unbekannter Platz")
		w.act(p, "shop_equip", { slot = "horn", item = "horn_melodie", rid = 7 })
		T.eq(w.shop(p).equipped.horn, "horn_melodie", "Hupe angelegt")
		-- CosmeticsFor: angelegte Einträge mit style; DLC-Auto trägt seine Folierung
		local cos = w.Shop.CosmeticsFor(d, { model = "komet" })
		T.eq(cos.rims and cos.rims.id, "rims_gold", "CosmeticsFor: Felgen")
		T.eq(cos.horn and cos.horn.id, "horn_melodie", "CosmeticsFor: Hupe")
		T.eq(cos.wrap, nil, "CosmeticsFor: keine Folierung")
		T.check(type(cos.rims.style) == "table" and type(cos.rims.style.color) == "table", "style vorhanden")
		cos = w.Shop.CosmeticsFor(d, { model = "dlc_komet_sunset" })
		T.eq(cos.wrap and cos.wrap.id, "wrap_sunset", "DLC-Auto: exklusive Folierung")
		T.eq(next(w.Shop.CosmeticsFor(nil, nil)) == nil, true, "CosmeticsFor ohne Profil: leer")
		-- Ablegen
		m = g:Mark()
		w.act(p, "shop_equip", { slot = "rims", item = "", rid = 8 })
		T.eq(w.shop(p).equipped.rims, "", "Felgen abgelegt")
		T.check(g:HasToast(p, "abgelegt", m), "Toast abgelegt")
		T.eq(w.Shop.CosmeticsFor(d, { model = "komet" }).rims, nil, "CosmeticsFor ohne Felgen")
		-- Snapshot-Felder
		local full = w.snapshot(p, true)
		T.check(type(full.owned) == "table" and #full.owned == 2, "owned-Liste")
		T.eq(full.equipped.horn, "horn_melodie", "equipped")
		T.eq(type(full.dlcCars), "table", "dlcCars-Liste")
		T.check(type(full.catalog) == "table" and #full.catalog.cosmetics > 0 and #full.catalog.cars == 3, "Katalog nur bei full")
		T.eq(full.passes.neon, false, "Pass-Besitz im Snapshot")
		local small = w.snapshot(p, false)
		T.eq(small.catalog, nil, "kleiner Snapshot ohne Katalog")
		if w.integrated then
			g:Advance(1) -- MiniService sendet den Snapshot im nächsten Tick (dirty nach shop_equip)
			local snap = g:MiniSnapshot(p)
			T.check(snap and type(snap.shop) == "table" and snap.shop.equipped.horn == "horn_melodie", "shop im echten Snapshot")
		end
		noErrors(T, g)
	end },

	{ "Game Pass: Besitz beim Beitritt, Gutschrift idempotent, Kaufereignis, zweiter Spieler unberührt", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { neon = PASS_NEON, deko = PASS_DEKO })
			g.env.services.MarketplaceService.__data.owned["708:" .. PASS_NEON] = true
		end })
		local w = wire(g)
		local p = w.join(708, { name = "Hal" })
		local q = w.join(709, { name = "Ida" })
		g:Advance(1)
		local shop = w.shop(p)
		T.eq(shop.owned.rims_neon, true, "Neon-Paket: Felgen")
		T.eq(shop.owned.trail_neon, true, "Neon-Paket: Spur")
		T.eq(shop.owned.horn_laser, true, "Neon-Paket: Hupe")
		T.eq(w.shop(q).owned.rims_neon, nil, "zweiter Spieler ohne Pass")
		T.eq(w.snapshot(p, false).passes.neon, true, "Snapshot: Pass besessen")
		T.eq(w.snapshot(q, false).passes.neon, false, "Snapshot: zweiter Spieler ohne Pass")
		-- Idempotent: erneute Gutschrift ändert nichts
		local GC = g:MiniShared("GameConfig")
		local ok, res = w.Shop.GrantPass(g:D(p), GC.Shop.PassByKey.neon, g:Now())
		T.check(ok and res.changed == false, "zweite Gutschrift: nichts Neues")
		local n = 0
		for _ in pairs(shop.owned) do
			n += 1
		end
		T.eq(n, 3, "keine Dubletten")
		-- Prompt: besessener Pass -> Hinweis, kein Prompt; anderer Pass -> PromptGamePassPurchase
		local mp = g.env.services.MarketplaceService.__data
		local m = g:Mark()
		w.act(p, "shop_prompt", { product = "neon", rid = 1 })
		T.check(g:HasToast(p, "bereits", m), "besessener Pass: Hinweis")
		T.eq(#mp.prompts, 0, "kein Prompt")
		g:Advance(4)
		w.act(p, "shop_prompt", { product = "deko", rid = 2 })
		T.eq(#mp.prompts, 1, "Pass-Prompt")
		T.eq(mp.prompts[1] and mp.prompts[1].passId, PASS_DEKO, "richtige Pass-Id")
		-- Kauf in der Sitzung: Ereignis -> Kosmetik sofort, Toast; zweites Ereignis still
		m = g:Mark()
		g.env.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, PASS_DEKO, true)
		g:Flush()
		T.eq(shop.owned.wrap_karo, true, "Deko-Paket: Folierung")
		T.eq(shop.owned.rims_chrom_blau, true, "Deko-Paket: Felgen")
		T.check(g:HasToast(p, "Werkstatt-Deko", m), "Toast zum Pass")
		T.check(hasNotice(g, p, "pass", m) ~= nil, "mini_notice shop/pass")
		m = g:Mark()
		g.env.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, PASS_DEKO, true)
		g:Flush()
		T.eq(#g:Toasts(p, m), 0, "zweites Ereignis: nichts Neues, kein Toast")
		g.env.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(q, PASS_DEKO, false)
		g.env.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(q, 12345, true)
		g:Flush()
		T.eq(w.shop(q).owned.wrap_karo, nil, "Abbruch/unbekannter Pass: nichts")
		-- Speichern/Laden: Besitz bleibt
		w.act(p, "shop_equip", { slot = "rims", item = "rims_neon", rid = 3 })
		g:Leave(p)
		g:Advance(1)
		local rec = g:Record(708)
		T.eq(rec.data.games.shop.owned.rims_neon, true, "Besitz gespeichert")
		T.eq(rec.data.games.shop.equipped.rims, "rims_neon", "Anlegen gespeichert")
		local again = w.join(708, { name = "Hal" })
		T.eq(w.shop(again).equipped.rims, "rims_neon", "nach dem Laden angelegt")
		T.eq(w.shop(again).owned.wrap_karo, true, "nach dem Laden im Besitz")
		noErrors(T, g)
	end },

	{ "shop_prompt: Platzhalter 0 abgelehnt, unbekannt, eingerichtet -> purchasePrompt, Credits-Paket, Deckel", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { car_komet_sunset = CAR_PRODUCT })
			g:Config().CreditProducts[1].productId = 424242
		end })
		local w = wire(g)
		local p = w.join(710, { name = "Jo" })
		local d = g:D(p)
		local m = g:Mark()
		T.eq(w.act(p, "shop_prompt", { product = "car_nord_nacht", rid = 1 }), "ok", "Aktion angenommen")
		T.check(g:HasToast(p, "noch nicht eingerichtet", m), "Id 0: noch nicht eingerichtet")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "kein Prompt bei Id 0")
		g:Advance(4)
		m = g:Mark()
		w.act(p, "shop_prompt", { product = "gibt_es_nicht", rid = 2 })
		T.check(g:HasToast(p, "gibt es nicht", m), "unbekanntes Produkt")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "kein Prompt")
		g:Advance(4)
		m = g:Mark()
		w.act(p, "shop_prompt", { product = "car_komet_sunset", rid = 3 })
		local prompts = g:Events(p, "purchasePrompt", m)
		T.eq(#prompts, 1, "purchasePrompt gesendet")
		T.eq(prompts[1] and prompts[1].productId, CAR_PRODUCT, "richtige Produkt-Id")
		-- Drosselung: gleich noch einmal -> nichts
		w.act(p, "shop_prompt", { product = "car_komet_sunset", rid = 4 })
		T.eq(#g:Events(p, "purchasePrompt", m), 1, "kein zweiter Prompt innerhalb von 3 s")
		-- Nach dem Kauf: Auto-Produkt schon im Besitz -> Hinweis statt Prompt
		g:Purchase(p, CAR_PRODUCT, "kauf-prompt")
		g:Advance(4)
		m = g:Mark()
		w.act(p, "shop_prompt", { product = "car_komet_sunset", rid = 5 })
		T.check(g:HasToast(p, "schon", m), "besessenes Auto-Produkt")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "kein Prompt")
		-- Credits-Paket über den Shop (Id aus C.CreditProducts), Deckel
		g:Advance(4)
		m = g:Mark()
		local key = g:Config().CreditProducts[1].key
		w.act(p, "shop_prompt", { product = key, rid = 6 })
		prompts = g:Events(p, "purchasePrompt", m)
		T.eq(prompts[1] and prompts[1].productId, 424242, "Credits-Paket: Prompt mit der 2.4.0-Id")
		g:Advance(4)
		d.money = g:Config().NumberCap
		m = g:Mark()
		w.act(p, "shop_prompt", { product = key, rid = 7 })
		T.check(g:HasToast(p, "zu hoch", m), "Deckel: kein Prompt")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "kein Prompt am Deckel")
		noErrors(T, g)
	end },

	{ "Studio/nicht speicherbar: kein Robux-Prompt; Quittung ohne Speicher nicht verarbeitet", function(T, H)
		local g = H.Garage({ level = 8, studio = true, before = function(g)
			prepare(g, { car_komet_sunset = CAR_PRODUCT })
		end })
		local w = wire(g)
		local p = w.join(711, { name = "Kim" })
		g:D(p).level = 8 -- Studio lädt nicht aus dem Speicher: Level fürs Sondermodell setzen (Level-Riegel vor dem Prompt)
		local m = g:Mark()
		w.act(p, "shop_prompt", { product = "car_komet_sunset", rid = 1 })
		T.check(g:HasToast(p, "noch nicht verfügbar", m), "Studio: Hinweis")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "Studio: kein Prompt")
		T.eq(g:Purchase(p, CAR_PRODUCT, "kauf-studio"), Enum.ProductPurchaseDecision.NotProcessedYet, "ohne Speicher keine Gutschrift")
		T.eq(w.cars(p, "dlc_komet_sunset"), 0, "kein Auto")
		noErrors(T, g)
	end },
	{ "Garage voll: kein Robux-Prompt für Autos; Quittung aufgeschoben mit Hinweis, Verkauf -> Gutschrift in der Sitzung", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { car_komet_sunset = CAR_PRODUCT })
		end })
		local w = wire(g)
		local p = w.join(720, { name = "Lia" })
		local d = g:D(p)
		local CR = g:MiniShared("CarRules")
		local CC = g:MiniShared("CarCatalog")
		local TEXT = g:MiniShared("GameConfig").Shop.Text
		for _ = 1, CC.MaxCars do
			CR.AddCar(d, CR.NewCar("komet", g:Now()))
		end
		T.eq(#d.games.cars, CC.MaxCars, "Garage voll")
		local m = g:Mark()
		w.act(p, "shop_prompt", { product = "car_komet_sunset", rid = 1 })
		T.check(g:HasToast(p, string.format(TEXT.garageFull, CC.MaxCars), m), "Toast Garage voll")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "kein Robux-Prompt bei voller Garage")
		local view = w.snapshot(p, true).catalog
		local blocked
		for _, prod in ipairs(view.products) do
			if prod.key == "car_komet_sunset" then
				blocked = prod.blocked
			end
		end
		T.eq(blocked, string.format(TEXT.garageFull, CC.MaxCars), "Katalog: Robux-Knopf mit Grund gesperrt")
		-- Quittung trotzdem (z. B. Prompt vor dem Füllen der Garage): aufgeschoben, Hinweis, keine Gutschrift
		m = g:Mark()
		local decision = g:Purchase(p, CAR_PRODUCT, "kauf-voll")
		T.eq(decision, Enum.ProductPurchaseDecision.NotProcessedYet, "NotProcessedYet")
		T.eq(w.cars(p, "dlc_komet_sunset"), 0, "noch kein Auto")
		T.eq(g:Record(720) and g:Record(720).receipts and g:Record(720).receipts["kauf-voll"], nil, "kein Beleg")
		if w.integrated then
			T.check(g:HasToast(p, "sobald ein Platz frei ist", m), "Hinweis: Garage voll, Auto kommt später")
			T.check(hasNotice(g, p, "deferred", m) ~= nil, "mini_notice shop/deferred")
		end
		-- Wiederholung desselben Belegs durch Roblox: kein zweiter Hinweis
		local m2 = g:Mark()
		g:Purchase(p, CAR_PRODUCT, "kauf-voll")
		T.eq(g:HasToast(p, "sobald ein Platz frei ist", m2), false, "Hinweis nur einmal je Quittung")
		-- Auto verkaufen -> die Sitzung wiederholt die Quittung und liefert das Auto
		m = g:Mark()
		T.eq(w.act(p, "mini_car_sell", { id = d.games.cars[1].id, rid = 2 }), "ok", "Auto verkauft")
		T.eq(#d.games.cars, CC.MaxCars - 1, "Platz frei")
		g:Advance(10)
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "Auto in der Sitzung gutgeschrieben")
		T.eq(g:Record(720).receipts["kauf-voll"], true, "Beleg gespeichert")
		T.eq(w.storedCars(720, "dlc_komet_sunset"), 1, "Auto mit dem Beleg gespeichert")
		if w.integrated then
			T.check(g:HasToast(p, "Dein neues Auto steht in der Garage", m), "Danke-Toast nach der Gutschrift")
		end
		-- Roblox liefert den Beleg später erneut: sofort abgeschlossen, kein zweites Auto
		T.eq(g:Purchase(p, CAR_PRODUCT, "kauf-voll"), Enum.ProductPurchaseDecision.PurchaseGranted, "Wiederholung gewährt")
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "kein zweites Auto")
		noErrors(T, g)
	end },

	{ "Besitz: kein Robux-Prompt für vorhandene Kosmetik/teilweise vorhandene Bündel; Doppelkauf-Schutz nach dem Prompt", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { cos_rims_gold = COS_PRODUCT, bundle_starter = BUNDLE_PRODUCT, cos_wrap_flammen = 515154 })
		end })
		local w = wire(g)
		local p = w.join(721, { name = "Max" })
		local d = g:D(p)
		d.money = 100000
		local TEXT = g:MiniShared("GameConfig").Shop.Text
		T.eq(w.act(p, "shop_buy", { item = "rims_gold", rid = 1 }), "ok", "Goldfelgen mit Credits")
		g:Advance(4)
		local m = g:Mark()
		w.act(p, "shop_prompt", { product = "cos_rims_gold", rid = 2 })
		T.check(g:HasToast(p, TEXT.owned, m), "Toast: Das hast du schon.")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "kein Prompt für vorhandene Kosmetik")
		g:Advance(4)
		m = g:Mark()
		w.act(p, "shop_prompt", { product = "bundle_starter", rid = 3 })
		T.check(g:HasToast(p, "1 von 4 Teilen", m), "Toast: Bündel teilweise vorhanden")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "kein Prompt für teilweise vorhandenes Bündel")
		-- Doppelkauf-Schutz: nach dem Prompt ist dasselbe Teil eine Weile nicht für Credits kaufbar
		g:Advance(4)
		m = g:Mark()
		w.act(p, "shop_prompt", { product = "cos_wrap_flammen", rid = 4 })
		T.eq(#g:Events(p, "purchasePrompt", m), 1, "Prompt für Flammen")
		local money = d.money
		w.act(p, "shop_buy", { item = "wrap_flammen", rid = 5 })
		T.check(g:HasToast(p, TEXT.promptPending, m), "Toast: Robux-Kauf läuft")
		T.eq(w.shop(p).owned.wrap_flammen, nil, "nicht doppelt gekauft")
		T.eq(d.money, money, "nichts abgebucht")
		-- Dialog abgebrochen -> Sperre sofort aufgehoben
		g:Activate()
		g.env.game:GetService("MarketplaceService").PromptProductPurchaseFinished:Fire(p.UserId, 515154, false)
		g:Flush()
		T.eq(w.act(p, "shop_buy", { item = "wrap_flammen", rid = 6 }), "ok", "nach Abbruch für Credits kaufbar")
		T.eq(w.shop(p).owned.wrap_flammen, true, "gekauft")
		noErrors(T, g)
	end },

	{ "DLC-Auto: verkauft -> wieder kaufbar (Credits und Robux); Versteigern abgelehnt", function(T, H)
		local g = H.Garage({ level = 30, before = function(g)
			prepare(g, { car_komet_sunset = CAR_PRODUCT })
		end })
		local w = wire(g)
		local p = w.join(722, { name = "Nia" })
		local d = g:D(p)
		d.money = 10000000
		local TEXT = g:MiniShared("GameConfig").Shop.Text
		T.eq(w.act(p, "shop_buy", { item = "dlc_komet_sunset", rid = 1 }), "ok", "mit Credits gekauft")
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "in der Garage")
		local car
		for _, c in ipairs(d.games.cars) do
			if c.model == "dlc_komet_sunset" then
				car = c
			end
		end
		-- Versteigern: abgelehnt (kein Handel mit Robux-Ware zwischen Spielern)
		local m = g:Mark()
		w.act(p, "mini_auction_consign", { id = car.id, start = 1000, duration = 120, rid = 2 })
		T.check(g:HasToast(p, "nicht versteigert", m), "Toast: Sondermodell nicht versteigerbar")
		T.check(not car.locked, "Auto nicht gesperrt")
		T.eq(g:MiniShared("AuctionRules").NewPlayerLot(1, { userId = 1, name = "x" }, car, 1000, 120, g:Now()), nil, "NewPlayerLot lehnt Sondermodell ab")
		-- Kein Robux-Prompt, solange es in der Garage steht
		g:Advance(4)
		m = g:Mark()
		w.act(p, "shop_prompt", { product = "car_komet_sunset", rid = 3 })
		T.check(g:HasToast(p, TEXT.owned, m), "Besitz: kein Prompt")
		-- Verkaufen -> wieder kaufbar
		T.eq(w.act(p, "mini_car_sell", { id = car.id, rid = 4 }), "ok", "verkauft")
		T.eq(w.cars(p, "dlc_komet_sunset"), 0, "nicht mehr in der Garage")
		T.eq(w.shop(p).owned.wrap_sunset, true, "Folierung bleibt")
		local snap = w.snapshot(p, true)
		T.eq(#snap.dlcCars, 0, "Snapshot: kein Sondermodell in der Garage")
		g:Advance(4)
		m = g:Mark()
		w.act(p, "shop_prompt", { product = "car_komet_sunset", rid = 5 })
		T.eq(#g:Events(p, "purchasePrompt", m), 1, "Robux-Prompt wieder möglich")
		g:Advance(61) -- Doppelkauf-Schutz abgelaufen
		T.eq(w.act(p, "shop_buy", { item = "dlc_komet_sunset", rid = 6 }), "ok", "mit Credits erneut gekauft")
		T.eq(w.cars(p, "dlc_komet_sunset"), 1, "wieder in der Garage")
		noErrors(T, g)
	end },

	{ "Quittung: eine Revision, ein changed je Shop-Produkt; Credits-Paket wie 2.4.0", function(T, H)
		local g = H.Garage({ level = 8, before = function(g)
			prepare(g, { cos_rims_gold = COS_PRODUCT })
			g:Config().CreditProducts[1].productId = 424242
		end })
		local w = wire(g)
		local p = w.join(723, { name = "Ole" })
		if not w.integrated then
			T.check(true, "nur integriert prüfbar")
			return
		end
		local sess = g:Session(p)
		local rev = sess.revision
		g:Purchase(p, COS_PRODUCT, "kauf-rev")
		T.eq(sess.revision - rev, 1, "Shop-Quittung: genau eine Revision")
		rev = sess.revision
		g:Purchase(p, 424242, "kauf-rev-credits")
		T.eq(sess.revision - rev, 1, "Credits-Paket: genau eine Revision")
		noErrors(T, g)
	end },
}
