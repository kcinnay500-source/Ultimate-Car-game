-- Ausbaustufe 4, Meilenstein 8 (Team shop-rules): ShopRules als reines Modul gegen die echte GameConfig.Shop und
-- CarCatalog.Dlc, ohne Server. Konfiguration (Richtlinien: alles ohne Robux erreichbar, Platzhalter-Ids 0),
-- kein Pay-to-win (DLC-Werte = Basismodell), Default/Load idempotent + Müll + Nachtragen, Kauf-/Anlege-Regeln,
-- Gutschriften idempotent, ApplyReceipt auf dem Schnappschuss, Resolve für die VehicleFactory, Katalog-Ansicht.
local NOW = 1760000000

local function modules(H)
	local g = H.Garage({ noServer = true })
	return g, g:MiniShared("GameConfig"), g:MiniShared("ShopRules"), g:MiniShared("CarRules"), g:MiniShared("CarCatalog")
end

-- Profil wie R.NewData, dazu games.cars/meta/prestige/story/shop (bis MiniRules.DefaultGames ShopRules aufruft)
local function profile(g, SR, level, money)
	local d = g:Rules().NewData(NOW)
	d.level = level or 1
	d.money = money or 0
	g:MiniShared("CarRules").ApplyDefault(d.games)
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	g:MiniShared("StoryRules").ApplyDefault(d.games)
	SR.ApplyDefault(d.games)
	return d
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

local STAT_KEYS = { "power", "topSpeed", "topSpeedStuds", "accel", "grip", "weight", "mass", "steerAngle", "springRate", "damping", "drive", "gears", "rating" }

return {
	{ "Konfiguration: Kosmetik je Platz, Preis oder Belohnung, Belohnungs-Ids bekannt, Produkte/Pässe mit Platzhalter 0", function(T, H)
		local g, GC, SR = modules(H)
		local S = GC.Shop
		local perSlot = { wrap = 0, rims = 0, horn = 0, trail = 0 }
		local buyable = 0
		for _, c in ipairs(S.Cosmetics) do
			T.check(type(c.id) == "string" and c.id:sub(1, #c.slot + 1) == c.slot .. "_", "Id-Schema <slot>_<name>: " .. tostring(c.id))
			T.check(S.SlotSet[c.slot], "Platz bekannt " .. c.id)
			T.check(type(c.name) == "string" and #c.name > 0 and type(c.desc) == "string" and #c.desc > 0, "Name/Beschreibung " .. c.id)
			T.check(type(c.style) == "table", "style " .. c.id)
			local priced = type(c.creditsPrice) == "number" and c.creditsPrice > 0
			T.check(priced ~= (c.rewardOnly == true), "Credits-Preis ODER Belohnung: " .. c.id)
			if c.rewardOnly then
				T.check(type(c.rewardText) == "string", "Belohnungstext " .. c.id)
			else
				perSlot[c.slot] += 1
				buyable += 1
			end
			T.eq(S.CosmeticById[c.id], c, "CosmeticById " .. c.id)
		end
		T.check(buyable >= 12, "mindestens 12 kaufbare Kosmetik-Teile: " .. buyable)
		T.check(perSlot.wrap >= 4 and perSlot.rims >= 4 and perSlot.horn >= 2 and perSlot.trail >= 2, "4 Folierungen, 4 Felgen, 2 Hupen, 2 Spuren kaufbar")
		-- Belohnungs-Ids aus Prestige und Story sind im Shop bekannt und rewardOnly
		for _, r in ipairs(GC.Prestige.Rewards) do
			local c = SR.Cosmetic(r.cosmetic)
			T.check(c ~= nil and c.rewardOnly, "Prestige-Kosmetik bekannt " .. r.cosmetic)
		end
		local storyCos = 0
		for _, ch in ipairs(GC.Story.Chapters) do
			for _, m in ipairs(ch.Missions) do
				if m.reward and m.reward.cosmetic then
					storyCos += 1
					local c = SR.Cosmetic(m.reward.cosmetic)
					T.check(c ~= nil and c.rewardOnly, "Story-Kosmetik bekannt " .. m.reward.cosmetic)
				end
			end
		end
		T.check(storyCos >= 1, "Story vergibt Kosmetik")
		-- Produkte
		local C = g:Config()
		local kinds = { credits = 0, car = 0, cosmetic = 0, bundle = 0 }
		for i, p in ipairs(S.Products) do
			kinds[p.kind] += 1
			T.eq(SR.ProductId(p), 0, "Platzhalter-Id " .. p.key)
			T.eq(p.robuxHint, nil, "kein ausgedachter Robux-Preis " .. p.key)
			T.check(type(p.name) == "string" and type(p.desc) == "string", "Texte " .. p.key)
			if p.kind == "credits" then
				T.eq(p.pack, C.CreditProducts[i], "Credits-Paket per Referenz " .. p.key)
			else
				for _, id in ipairs(p.grants.cosmetics or {}) do
					T.check(SR.Cosmetic(id) ~= nil, "Produkt-Kosmetik bekannt " .. id)
				end
				for _, id in ipairs(p.grants.cars or {}) do
					T.check(SR.DlcModel(id) ~= nil, "Produkt-Auto bekannt " .. id)
				end
			end
			if p.kind == "cosmetic" or p.kind == "bundle" then
				T.check(type(p.creditsPrice) == "number", "Credits-Preis am Produkt " .. p.key)
				for _, id in ipairs(p.grants.cosmetics) do
					T.check(not SR.Cosmetic(id).rewardOnly, "Produkt-Kosmetik auch für Credits " .. id)
				end
			end
			T.eq(S.ProductByKey[p.key], p, "ProductByKey " .. p.key)
		end
		T.eq(kinds.credits, #C.CreditProducts, "alle Credits-Pakete")
		T.check(kinds.car >= 3 and kinds.cosmetic >= 4 and kinds.bundle >= 1, "3 Autos, 4 Kosmetik, 1 Bündel")
		T.eq(#S.Passes, 2, "zwei Pässe")
		for _, p in ipairs(S.Passes) do
			T.eq(p.id, 0, "Pass-Platzhalter " .. p.key)
			for _, id in ipairs(p.grants.cosmetics) do
				local c = SR.Cosmetic(id)
				T.check(c ~= nil and not c.rewardOnly, "Pass-Kosmetik auch für Credits " .. id)
			end
		end
		T.check(S.PassByKey.neon ~= nil and S.PassByKey.deko ~= nil, "Neon-Paket und Werkstatt-Deko")
		T.check(SR.ProductForId(0) == nil and SR.ProductForId(nil) == nil, "ProductForId 0 -> nil")
		-- Keine externen Assets in Shop-Texten/Stilen
		local function scan(t, path)
			for k, v in pairs(t) do
				if type(v) == "string" then
					T.check(not v:find("rbxassetid"), "kein rbxassetid in " .. path .. "." .. tostring(k))
				elseif type(v) == "table" and k ~= "pack" then
					scan(v, path .. "." .. tostring(k))
				end
			end
		end
		scan(S.Cosmetics, "Cosmetics")
		scan(S.Text, "Text")
	end },

	{ "DLC-Autos: registriert, nicht beim Händler, kein Pay-to-win (Werte = Basismodell), feste Optik, exklusive Folierung", function(T, H)
		local g, GC, SR, CR, CC = modules(H)
		T.check(#CC.Dlc >= 3, "mindestens drei DLC-Autos")
		local d = profile(g, SR, 99, 1e9)
		for _, x in ipairs(CC.Dlc) do
			local m = CC.Model(x.id)
			T.check(m ~= nil and m.dlc == true and m.dealer == false and m.special == false, "Modell registriert " .. x.id)
			T.eq(CC.DlcById[x.id], x, "DlcById " .. x.id)
			local base = CC.Model(x.base)
			T.check(base ~= nil and base.dealer, "Basismodell beim Händler " .. x.id)
			T.eq(m.body, x.body, "Karosserie aus bestehender Vorlage " .. x.id)
			T.eq(m.level, base.level, "Level wie Basismodell " .. x.id)
			T.eq(m.value, base.value, "Wert wie Basismodell " .. x.id)
			local sd, sb = CR.Stats(CR.NewCar(m.id, 0)), CR.Stats(CR.NewCar(base.id, 0))
			for _, k in ipairs(STAT_KEYS) do
				T.eq(sd[k], sb[k], "Fahrwert " .. k .. " gleich " .. x.id)
			end
			T.eq(sd.nitro.boost, sb.nitro.boost, "Nitro gleich " .. x.id)
			-- auch voll getunt identisch
			local td, tb = CR.NewCar(m.id, 0), CR.NewCar(base.id, 0)
			for _, part in ipairs(CC.TuneParts) do
				td[part], tb[part] = CC.Tune[part].max, CC.Tune[part].max
			end
			T.eq(CR.Stats(td).rating, CR.Stats(tb).rating, "voll getunt gleich " .. x.id)
			local car = CR.NewCar(m.id, NOW)
			T.check(car.paint == x.paint and car.rims == x.rims and car.glow == x.glow and car.spoiler == x.spoiler, "feste Optik " .. x.id)
			local w = SR.Cosmetic(x.wrap)
			T.check(w ~= nil and w.slot == "wrap" and w.rewardOnly, "exklusive Folierung " .. x.id)
			T.check(CR.NormalizeCar(car) ~= nil, "NormalizeCar kennt das Modell " .. x.id)
			local ok = CR.Buy(d, m.id, NOW)
			T.eq(ok, false, "Händler verkauft kein DLC " .. x.id)
			T.check(SR.DlcPrice(d, m) > m.price, "Credits-Preis über dem Basispreis " .. x.id)
		end
		T.eq(#SR.DlcModels(), #CC.Dlc, "DlcModels vollständig")
		T.check(SR.DlcModel("komet") == nil and SR.DlcModel(nil) == nil, "DlcModel nur für DLC")
	end },

	{ "Default/Load: idempotent, Whitelist, Müll, equipped nur Besitz im passenden Platz, Deckel", function(T, H)
		local g, GC, SR = modules(H)
		local d = profile(g, SR)
		local def = SR.Default()
		T.check(count(def.owned) == 0 and count(def.dlcCars) == 0, "leer")
		for _, slot in ipairs(GC.Shop.Slots) do
			T.eq(def.equipped[slot], "", "Platz frei " .. slot)
		end
		T.check(H.DeepEqual(SR.Load(nil, d, NOW), def), "Load(nil) = Default")
		T.check(H.DeepEqual(SR.Load("müll", d, NOW), def), "Load(string) = Default")
		local raw = {
			owned = { wrap_flammen = true, rims_gold = true, wrap_unbekannt = true, [5] = true, horn_melodie = "ja", trail_blau = false },
			equipped = { wrap = "wrap_flammen", rims = "rims_neon", horn = "rims_gold", trail = 7, extra = "x" },
			dlcCars = { dlc_komet_sunset = true, komet = true, dlc_nix = true },
			fremd = {},
		}
		local s1 = SR.Load(raw, d, NOW)
		T.check(s1.owned.wrap_flammen and s1.owned.rims_gold and count(s1.owned) == 2, "owned Whitelist")
		T.eq(s1.equipped.wrap, "wrap_flammen", "angelegt, besessen")
		T.eq(s1.equipped.rims, "", "nicht besessen -> frei")
		T.eq(s1.equipped.horn, "", "falscher Platz -> frei")
		T.eq(s1.equipped.trail, "", "Müll -> frei")
		T.eq(s1.equipped.extra, nil, "fremder Platz fällt weg")
		T.check(s1.dlcCars.dlc_komet_sunset and count(s1.dlcCars) == 1, "dlcCars Whitelist")
		T.eq(s1.fremd, nil, "fremde Felder fallen weg")
		local s2 = SR.Load(s1, d, NOW)
		T.check(H.DeepEqual(s1, s2), "Load idempotent")
		-- Deckel
		local many = { owned = {} }
		for _, c in ipairs(GC.Shop.Cosmetics) do
			many.owned[c.id] = true
		end
		local s3 = SR.Load(many, d, NOW)
		T.check(count(s3.owned) <= GC.Shop.MaxOwned and count(s3.owned) == math.min(#GC.Shop.Cosmetics, GC.Shop.MaxOwned), "Deckel MaxOwned")
		-- ApplyLoad/ApplyDefault
		local gm = { shop = raw, cars = {}, prestige = { claimed = {} }, story = { done = {} } }
		SR.ApplyLoad(gm, gm, d, NOW)
		T.check(H.DeepEqual(gm.shop, s1), "ApplyLoad = Load(raw.shop)")
		SR.ApplyDefault(gm)
		T.check(H.DeepEqual(gm.shop, def), "ApplyDefault")
		-- Shop(d) legt Standard an, wenn das Profil keinen hat
		d.games.shop = nil
		T.check(H.DeepEqual(SR.Shop(d), def), "Shop(d) ohne Daten -> Standard")
		d.games.shop = { owned = {} }
		T.check(H.DeepEqual(SR.Shop(d), def), "Shop(d) unvollständig -> Standard")
	end },

	{ "Load trägt nach: Prestige-Ränge, Story-Finale, DLC-Autos in der Garage (Profile vor Meilenstein 8)", function(T, H)
		local g, GC, SR, CR = modules(H)
		local d = profile(g, SR, 50)
		local gm = d.games
		gm.prestige.claimed[1] = true
		gm.prestige.claimed[2] = true
		gm.prestige.claimed[7] = "nein"
		gm.story.done.c5_m3 = true
		gm.story.done.c1_m1 = true
		CR.AddCar(d, CR.NewCar("dlc_nord_nacht", NOW))
		CR.AddCar(d, CR.NewCar("komet", NOW))
		local s = SR.Load(nil, d, NOW, gm)
		T.check(s.owned[GC.Prestige.Rewards[1].cosmetic] and s.owned[GC.Prestige.Rewards[2].cosmetic], "Prestige-Kosmetik nachgetragen")
		T.check(not s.owned[GC.Prestige.Rewards[7].cosmetic], "nur claimed == true")
		T.check(s.owned.wrap_mega, "Story-Folierung nachgetragen")
		T.check(s.dlcCars.dlc_nord_nacht and s.owned.wrap_nacht, "DLC-Auto + Beigabe nachgetragen")
		T.check(not s.dlcCars.komet, "Händlerauto kein DLC")
		T.eq(count(s.owned), 4, "genau vier nachgetragen")
		-- equipped darf die nachgetragene Kosmetik nutzen
		local s2 = SR.Load({ equipped = { wrap = "wrap_mega" } }, d, NOW, gm)
		T.eq(s2.equipped.wrap, "wrap_mega", "angelegt aus Nachtrag")
		-- ohne games-Table nichts nachgetragen, kein Fehler
		T.eq(count(SR.Load(nil, d, NOW, nil).owned), 0, "ohne games nichts")
	end },

	{ "Kauf mit Credits: unbekannt, Belohnung, Level, Geld, schon da; Erfolg bucht ab und gibt XP", function(T, H)
		local g, GC, SR = modules(H)
		local d = profile(g, SR, 1, 100)
		local ok, msg = SR.Buy(d, "nix", NOW)
		T.check(not ok and msg == GC.Shop.Text.unknown, "unbekannt")
		ok, msg = SR.Buy(d, "wrap_mega", NOW)
		T.check(not ok and msg:find("Belohnung", 1, true), "nur Belohnung: " .. tostring(msg))
		ok, msg = SR.Buy(d, "wrap_flammen", NOW)
		T.check(not ok and msg == string.format(GC.Shop.Text.level, 3), "Level: " .. tostring(msg))
		ok, msg = SR.Buy(d, "wrap_streifen", NOW)
		T.check(not ok and msg == GC.Shop.Text.money, "Geld")
		T.eq(d.money, 100, "nichts abgebucht")
		d.money = 1500
		local xp = d.xp
		local ok2, res = SR.Buy(d, "wrap_streifen", NOW)
		T.check(ok2 and res.kind == "cosmetic" and res.item.id == "wrap_streifen" and res.price == 1500, "gekauft")
		T.eq(d.money, 0, "abgebucht")
		T.check(d.xp > xp, "XP")
		T.check(SR.Owns(d, "wrap_streifen"), "Besitz")
		d.money = 5000
		ok, msg = SR.Buy(d, "wrap_streifen", NOW)
		T.check(not ok and msg == GC.Shop.Text.owned, "nicht doppelt")
		T.eq(d.money, 5000, "nichts abgebucht beim Doppelkauf")
		local can, reason, price = SR.CanBuy(d, "rims_gold")
		T.check(can and reason == nil and price == 1200, "CanBuy")
		local _, _, _, kind = SR.CanBuy(d, "wrap_flammen")
		T.eq(kind, "cosmetic", "CanBuy Art")
	end },

	{ "DLC-Auto mit Credits: Level, Garage voll ohne Abbuchung, Kauf legt Auto mit Optik + Folierung an, nur einmal", function(T, H)
		local g, GC, SR, CR, CC = modules(H)
		local m = CC.Model("dlc_vektor_blitz")
		local d = profile(g, SR, m.level - 1, 1e9)
		local ok, msg = SR.Buy(d, m.id, NOW)
		T.check(not ok and msg == string.format(GC.Shop.Text.level, m.level), "Level: " .. tostring(msg))
		d.level = m.level
		local price = SR.DlcPrice(d, m)
		T.check(price > 0 and price < 1e9, "Preis")
		d.money = price - 1
		ok, msg = SR.Buy(d, m.id, NOW)
		T.check(not ok and msg == GC.Shop.Text.money, "Geld")
		d.money = price
		-- Garage voll
		for _ = 1, CC.MaxCars do
			CR.AddCar(d, CR.NewCar("komet", NOW))
		end
		ok, msg = SR.Buy(d, m.id, NOW)
		T.check(not ok and msg == string.format(GC.Shop.Text.garageFull, CC.MaxCars), "Garage voll: " .. tostring(msg))
		T.eq(d.money, price, "nichts abgebucht")
		T.check(not SR.HasDlc(d, m.id), "nicht als gekauft markiert")
		CR.RemoveCar(d, d.games.cars[1].id)
		local ok2, res = SR.Buy(d, m.id, NOW)
		T.check(ok2 and res.kind == "car" and res.car and res.car.model == m.id, "gekauft")
		T.eq(d.money, 0, "abgebucht")
		T.check(res.car.paint == m.paint and res.car.rims == m.rims and res.car.glow == m.glow and res.car.spoiler == m.spoiler, "Optik")
		T.check(SR.HasDlc(d, m.id) and SR.Owns(d, m.wrap), "dlcCars + Folierung")
		d.money = 1e9
		ok, msg = SR.Buy(d, m.id, NOW)
		T.check(not ok and msg == GC.Shop.Text.owned, "nur einmal")
		T.eq(d.money, 1e9, "Doppelkauf bucht nichts ab")
		-- Besitz folgt der Garage: nach dem Verkauf ist das Sondermodell wieder kaufbar (Credits und Robux)
		CR.Sell(d, res.car.id)
		T.check(not SR.HasDlc(d, m.id), "nach Verkauf nicht mehr im Besitz")
		T.eq(SR.Shop(d).dlcCars[m.id], true, "Kauf-Historie bleibt")
		T.check(SR.Owns(d, m.wrap), "exklusive Folierung bleibt")
		local okAgain = SR.CanBuy(d, m.id)
		T.eq(okAgain, true, "nach Verkauf wieder kaufbar (CanBuy)")
		local fakeKey = "x_dlc_rebuy"
		GC.Shop.ProductByKey[fakeKey] = { key = fakeKey, kind = "car", name = "X", productId = 4242, grants = { cars = { m.id }, cosmetics = { m.wrap } } }
		local canP, msgP = SR.CanPrompt(d, fakeKey)
		T.check(canP, "nach Verkauf wieder per Robux kaufbar (CanPrompt): " .. tostring(msgP))
		GC.Shop.ProductByKey[fakeKey] = nil
		ok = SR.Buy(d, m.id, NOW)
		T.eq(ok, true, "nach Verkauf erneut gekauft")
		T.check(SR.HasDlc(d, m.id), "wieder in der Garage")
		-- Preis mit Prestige-Rabatt kleiner, nie unter 1
		local rich = profile(g, SR, 300, 0)
		T.check(SR.DlcPrice(rich, m) < SR.DlcPrice(profile(g, SR, m.level, 0), m), "Rabatt wirkt")
	end },

	{ "Anlegen: Platz, Besitz, passender Platz, Doppelklick still, Ablegen", function(T, H)
		local g, GC, SR = modules(H)
		local d = profile(g, SR, 10, 1e6)
		local ok, msg = SR.Equip(d, "hut", "wrap_flammen")
		T.check(not ok and msg == GC.Shop.Text.badSlot, "unbekannter Platz")
		ok, msg = SR.Equip(d, "wrap", "wrap_flammen")
		T.check(not ok and msg == GC.Shop.Text.notOwned, "nicht besessen")
		ok, msg = SR.Equip(d, "wrap", "nix")
		T.check(not ok and msg == GC.Shop.Text.unknown, "unbekannt")
		SR.Buy(d, "wrap_flammen", NOW)
		ok, msg = SR.Equip(d, "rims", "wrap_flammen")
		T.check(not ok and msg == GC.Shop.Text.wrongSlot, "falscher Platz")
		ok, msg = SR.Equip(d, "wrap", "wrap_flammen")
		T.check(ok and msg:find("Flammen", 1, true), "angelegt")
		T.eq(SR.Shop(d).equipped.wrap, "wrap_flammen", "gespeichert")
		ok, msg = SR.Equip(d, "wrap", "wrap_flammen")
		T.check(not ok and msg == nil, "Doppelklick still")
		ok, msg = SR.Equip(d, "wrap", "")
		T.check(ok and SR.Shop(d).equipped.wrap == "", "abgelegt")
		ok, msg = SR.Equip(d, "wrap", nil)
		T.check(not ok and msg == nil, "nochmal ablegen still")
		T.eq(SR.Equip(d, 5, "x"), false, "Platz kein String")
	end },

	{ "Gutschrift (Grant): idempotent, Auto nur einmal, Garage voll ändert nichts, Credits gedeckelt", function(T, H)
		local g, GC, SR, CR, CC = modules(H)
		local d = profile(g, SR, 1, 0)
		local p = GC.Shop.ProductByKey.car_komet_sunset
		local ok, res = SR.Grant(d, p.grants, NOW)
		T.check(ok and #res.cars == 1 and res.changed, "Auto gutgeschrieben")
		T.check(res.cars[1].model == "dlc_komet_sunset" and SR.HasDlc(d, "dlc_komet_sunset"), "Modell + dlcCars")
		T.check(SR.Owns(d, "wrap_sunset"), "Beigabe")
		T.eq(#d.games.cars, 1, "ein Auto")
		ok, res = SR.Grant(d, p.grants, NOW)
		T.check(ok and #res.cars == 0 and #res.cosmetics == 0 and not res.changed, "zweite Gutschrift ändert nichts")
		T.eq(#d.games.cars, 1, "kein zweites Auto")
		-- Bündel
		local b = GC.Shop.ProductByKey.bundle_starter
		ok, res = SR.Grant(d, b.grants, NOW)
		T.check(ok and #res.cosmetics == #b.grants.cosmetics, "Bündel komplett")
		SR.Shop(d).owned.rims_gold = nil
		ok, res = SR.Grant(d, b.grants, NOW)
		T.check(ok and #res.cosmetics == 1 and res.cosmetics[1] == "rims_gold", "nur das Fehlende")
		-- Garage voll: nichts ändern, false
		for _ = 1, CC.MaxCars do
			CR.AddCar(d, CR.NewCar("komet", NOW))
		end
		local p2 = GC.Shop.ProductByKey.car_nord_nacht
		ok, res = SR.Grant(d, p2.grants, NOW)
		T.check(not ok and type(res) == "string", "Garage voll -> false: " .. tostring(res))
		T.check(not SR.HasDlc(d, "dlc_nord_nacht") and not SR.Owns(d, "wrap_nacht"), "nichts geändert")
		-- Credits (gedeckelt), Müll
		d.money = 1000
		ok, res = SR.Grant(d, { credits = 100.7 }, NOW)
		T.check(ok and res.credits == 100 and d.money == 1100 and res.changed, "Credits ganzzahlig gutgeschrieben")
		d.money = g:Config().NumberCap
		ok, res = SR.Grant(d, { credits = 100 }, NOW)
		T.check(ok and res.credits == 0 and d.money == g:Config().NumberCap and not res.changed, "Credits gedeckelt")
		ok, res = SR.Grant(d, { credits = 0 / 0, cosmetics = { "nix", 5 }, cars = { "komet", "nix" } }, NOW)
		T.check(ok and not res.changed, "Müll ignoriert")
		T.eq(#d.games.cars, CC.MaxCars, "Händlermodell nicht über Grant")
		T.check(select(1, SR.Grant(d, nil, NOW)), "Grant(nil) ok")
		-- Pass-Gutschrift
		local pass = GC.Shop.PassByKey.neon
		ok, res = SR.Grant(d, pass.grants, NOW)
		T.check(ok and SR.ProductOwned(d, pass), "Pass-Kosmetik gutgeschrieben, ProductOwned")
	end },

	{ "ApplyReceipt auf dem Schnappschuss (Profiles.GrantReceipt), CanPrompt mit Platzhalter 0", function(T, H)
		local g, GC, SR, CR = modules(H)
		local d = profile(g, SR, 20, 500)
		CR.AddCar(d, CR.NewCar("komet", NOW))
		local snapshot = g:Rules().Snapshot(d)
		local p = GC.Shop.ProductByKey.car_vektor_blitz
		local ok, res = SR.ApplyReceipt(snapshot, p, NOW)
		T.check(ok and res.changed and #res.cars == 1 and res.product == p, "angewendet")
		T.check(type(res.text) == "string" and res.text:find(p.name, 1, true), "Text")
		T.eq(#snapshot.games.cars, 2, "Auto im Schnappschuss")
		T.eq(#d.games.cars, 1, "Original unverändert")
		T.check(snapshot.games.shop.dlcCars.dlc_vektor_blitz and not SR.HasDlc(d, "dlc_vektor_blitz"), "dlcCars nur im Schnappschuss")
		T.eq(snapshot.money, 500, "kein Geld verändert")
		-- Neue bezahlte Quittung für ein Auto, das schon in der Garage steht: das Auto wird trotzdem geliefert
		-- (eine Robux-Quittung verfällt nie ohne Gegenwert; doppelte Belege fängt Profiles über receipts ab)
		ok, res = SR.ApplyReceipt(snapshot, p, NOW)
		T.check(ok and res.changed and #res.cars == 1, "zweites Exemplar geliefert")
		T.eq(#snapshot.games.cars, 3, "zwei Sondermodelle in der Garage")
		-- Kosmetik-Produkt
		ok, res = SR.ApplyReceipt(snapshot, GC.Shop.ProductByKey.cos_rims_gold, NOW)
		T.check(ok and res.cosmetics[1] == "rims_gold", "Kosmetik-Produkt")
		T.eq(res.refund, 0, "keine Rückerstattung bei Neuem")
		-- Schon vorhandene Kosmetik (Wettlauf Prompt/Credits-Kauf): Credits-Preis wird gutgeschrieben
		local money0 = snapshot.money
		ok, res = SR.ApplyReceipt(snapshot, GC.Shop.ProductByKey.cos_rims_gold, NOW)
		T.check(ok and #res.cosmetics == 0, "nichts Neues")
		T.eq(res.refund, GC.Shop.CosmeticById.rims_gold.creditsPrice, "Credits-Preis erstattet")
		T.eq(snapshot.money, money0 + res.refund, "Credits im Schnappschuss")
		T.check(res.changed and type(res.refundText) == "string" and res.refundText:find("Goldfelgen", 1, true) ~= nil, "Erstattungstext")
		-- Bündel teilweise vorhanden: Fehlendes gutgeschrieben, Vorhandenes erstattet
		money0 = snapshot.money
		ok, res = SR.ApplyReceipt(snapshot, GC.Shop.ProductByKey.bundle_starter, NOW)
		T.check(ok and #res.cosmetics == 3, "fehlende Bündelteile")
		T.eq(snapshot.money - money0, GC.Shop.CosmeticById.rims_gold.creditsPrice, "vorhandener Teil erstattet")
		-- Credits-Pakete laufen nicht über ApplyReceipt
		ok = SR.ApplyReceipt(snapshot, GC.Shop.Products[1], NOW)
		T.eq(ok, false, "Credits-Paket abgelehnt")
		T.eq(SR.ApplyReceipt({}, p, NOW), false, "ohne games")
		T.eq(SR.ApplyReceipt(snapshot, nil, NOW), false, "ohne Produkt")
		-- Garage voll -> false (NotProcessedYet)
		for _ = 1, 25 do
			CR.AddCar(snapshot, CR.NewCar("komet", NOW))
		end
		ok, res = SR.ApplyReceipt(snapshot, GC.Shop.ProductByKey.car_nord_nacht, NOW)
		T.check(not ok and type(res) == "string", "Garage voll -> später")
		-- CanPrompt: Platzhalter 0 -> noch nicht eingerichtet, kein Prompt
		local can, msg, id = SR.CanPrompt(d, "car_vektor_blitz")
		T.check(not can and msg == GC.Shop.Text.notReady and id == 0, "noch nicht eingerichtet")
		can, msg = SR.CanPrompt(d, "nix")
		T.check(not can and msg == GC.Shop.Text.unknown, "unbekanntes Produkt")
		-- mit (simulierter) Id: schon gekauftes Auto -> kein Prompt
		local fake = { key = "x", kind = "car", name = "X", productId = 123456, grants = { cars = { "dlc_vektor_blitz" } } }
		GC.Shop.ProductByKey.x = fake
		can, msg, id = SR.CanPrompt(snapshot, "x")
		T.check(not can and msg == GC.Shop.Text.owned and id == 123456, "schon gekauft -> kein Prompt")
		can, msg, id = SR.CanPrompt(d, "x")
		T.check(can and id == 123456, "Prompt erlaubt")
		GC.Shop.ProductByKey.x = nil
		-- Garage voll -> kein Robux-Prompt für ein Auto-Produkt (sonst bezahlt und nicht lieferbar)
		local full = profile(g, SR, 20, 0)
		for _ = 1, g:MiniShared("CarCatalog").MaxCars do
			CR.AddCar(full, CR.NewCar("komet", NOW))
		end
		GC.Shop.ProductByKey.x = fake
		can, msg = SR.CanPrompt(full, "x")
		T.check(not can and msg == string.format(GC.Shop.Text.garageFull, g:MiniShared("CarCatalog").MaxCars), "Garage voll -> kein Prompt: " .. tostring(msg))
		T.check(SR.PromptBlock(full, fake) ~= nil, "PromptBlock nennt den Grund")
		GC.Shop.ProductByKey.x = nil
		-- Kosmetik schon vorhanden -> kein Prompt; Bündel teilweise vorhanden -> kein Prompt mit Hinweis
		local cosP = GC.Shop.ProductByKey.cos_wrap_flammen
		local bundle = GC.Shop.ProductByKey.bundle_starter
		local id0, idB = cosP.productId, bundle.productId
		cosP.productId, bundle.productId = 5551, 5552
		local own = profile(g, SR, 20, 1e6)
		T.eq((SR.CanPrompt(own, "cos_wrap_flammen")), true, "Kosmetik nicht im Besitz -> Prompt")
		T.eq((SR.CanPrompt(own, "bundle_starter")), true, "Bündel ohne Teile -> Prompt")
		SR.Buy(own, "wrap_flammen", NOW)
		can, msg = SR.CanPrompt(own, "cos_wrap_flammen")
		T.check(not can and msg == GC.Shop.Text.owned, "Kosmetik im Besitz -> kein Prompt")
		SR.Buy(own, "rims_gold", NOW)
		can, msg = SR.CanPrompt(own, "bundle_starter")
		T.check(not can and msg == string.format(GC.Shop.Text.partlyOwned, 1, 4, "Goldfelgen"), "Bündel teilweise -> kein Prompt: " .. tostring(msg))
		local have, total = SR.ProductParts(own, bundle)
		T.check(have == 1 and total == 4, "ProductParts 1/4")
		for _, id in ipairs(bundle.grants.cosmetics) do
			SR.Shop(own).owned[id] = true
		end
		can, msg = SR.CanPrompt(own, "bundle_starter")
		T.check(not can and msg == GC.Shop.Text.owned, "Bündel komplett -> owned")
		cosP.productId, bundle.productId = id0, idB
		T.eq(SR.ProductId({ pack = { productId = 77 }, productId = 0 }), 77, "ProductId aus Paket-Referenz")
	end },

	{ "Resolve: angelegte Kosmetik profilweit, DLC-Folierung als Rückfall, nur Besitz", function(T, H)
		local g, GC, SR, CR = modules(H)
		local d = profile(g, SR, 10, 1e6)
		local komet = CR.AddCar(d, CR.NewCar("komet", NOW))
		SR.Grant(d, GC.Shop.ProductByKey.car_nord_nacht.grants, NOW)
		local nacht = d.games.cars[2]
		local r = SR.Resolve(d, komet)
		T.check(r.wrap == nil and r.rims == nil and r.horn == nil and r.trail == nil, "nichts angelegt")
		r = SR.Resolve(d, nacht)
		T.check(r.wrap and r.wrap.id == "wrap_nacht", "DLC trägt exklusive Folierung")
		SR.Buy(d, "wrap_flammen", NOW)
		SR.Buy(d, "rims_gold", NOW)
		SR.Buy(d, "horn_melodie", NOW)
		SR.Buy(d, "trail_blau", NOW)
		SR.Equip(d, "wrap", "wrap_flammen")
		SR.Equip(d, "rims", "rims_gold")
		SR.Equip(d, "horn", "horn_melodie")
		SR.Equip(d, "trail", "trail_blau")
		r = SR.Resolve(d, nacht)
		T.check(r.wrap.id == "wrap_flammen" and r.rims.id == "rims_gold" and r.horn.id == "horn_melodie" and r.trail.id == "trail_blau", "angelegt gewinnt")
		T.check(type(r.wrap.style.pattern) == "string" and type(r.rims.style.color) == "table" and type(r.horn.style.text) == "string" and type(r.trail.style.color) == "table", "style vorhanden")
		local ids = SR.ResolveIds(d, komet)
		T.check(ids.wrap == "wrap_flammen" and ids.rims == "rims_gold" and ids.horn == "horn_melodie" and ids.trail == "trail_blau", "ResolveIds")
		-- Besitz manipuliert -> nicht mehr aufgelöst
		SR.Shop(d).owned.wrap_flammen = nil
		T.check(SR.Resolve(d, komet).wrap == nil, "ohne Besitz nichts")
		T.eq(SR.ResolveIds(d, komet).wrap, "", "ResolveIds leer")
		T.check(count(SR.Resolve(nil, nil)) == 0 and SR.ResolveIds({}, nil).wrap == "", "nil-sicher")
	end },

	{ "Katalog und Snapshot-Felder: Gründe, Besitz, Produkte nicht bereit", function(T, H)
		local g, GC, SR, CR = modules(H)
		local d = profile(g, SR, 2, 3300)
		SR.Buy(d, "rims_gold", NOW)
		SR.Equip(d, "rims", "rims_gold")
		local cat = SR.Catalog(d)
		T.eq(#cat.cosmetics, #GC.Shop.Cosmetics, "alle Kosmetik")
		T.eq(#cat.cars, #SR.DlcModels(), "alle DLC-Autos")
		T.eq(#cat.products, #GC.Shop.Products, "alle Produkte")
		T.eq(#cat.passes, #GC.Shop.Passes, "alle Pässe")
		local byId = {}
		for _, c in ipairs(cat.cosmetics) do
			byId[c.id] = c
		end
		T.check(byId.rims_gold.owned and byId.rims_gold.equipped and byId.rims_gold.reason == nil, "gekauft + angelegt")
		T.check(byId.wrap_flammen.available == false and byId.wrap_flammen.reason == string.format(GC.Shop.Text.level, 3), "Level-Grund")
		T.check(byId.wrap_karo.available == true and byId.wrap_karo.price == 2000, "kaufbar")
		d.money = 100
		local poor = SR.Catalog(d).cosmetics
		for _, c in ipairs(poor) do
			if c.id == "wrap_streifen" then
				T.check(c.available == false and c.reason == GC.Shop.Text.money, "Geld-Grund")
			end
		end
		T.check(byId.wrap_mega.rewardOnly and byId.wrap_mega.price == nil and byId.wrap_mega.reason:find("Story", 1, true), "Belohnung mit Text")
		for _, c in ipairs(cat.cars) do
			T.check(c.price > c.basePrice and c.available == false and c.reason ~= nil and c.rating > 0, "DLC-Auto gesperrt mit Grund " .. c.id)
		end
		for _, p in ipairs(cat.products) do
			T.check(p.ready == false and p.productId == 0, "Produkt nicht bereit " .. p.key)
			T.eq(p.owned, p.key == "cos_rims_gold", "Produkt gekauft nur bei Goldfelgen " .. p.key)
			if p.kind == "credits" then
				T.check(type(p.credits) == "number" and p.credits > 0, "Credits-Menge " .. p.key)
			end
		end
		for _, p in ipairs(cat.passes) do
			T.check(p.ready == false and p.id == 0, "Pass nicht bereit " .. p.key)
		end
		T.check(type(cat.hint) == "string", "Hinweis")
		local f = SR.SnapshotFields(d)
		T.check(#f.owned == 1 and f.owned[1] == "rims_gold" and f.equipped.rims == "rims_gold" and #f.dlcCars == 0 and f.catalog == nil, "Snapshot klein")
		local full = SR.SnapshotFields(d, true)
		T.check(type(full.catalog) == "table" and #full.catalog.cosmetics == #GC.Shop.Cosmetics, "Snapshot full mit Katalog")
		-- Snapshot-Felder sind nur Strings/Zahlen/Booleans/Tabellen (keine Funktionen, keine Instanzen)
		local function plain(t, path)
			for k, v in pairs(t) do
				local tv = type(v)
				if tv == "table" then
					plain(v, path .. "." .. tostring(k))
				else
					T.check(tv == "string" or tv == "number" or tv == "boolean", "Snapshot-Typ " .. path .. "." .. tostring(k))
				end
			end
		end
		plain(full, "shop")
	end },

	{ "MiniRules.DefaultGames/LoadGames behalten shop (sobald ShopRules dort verkabelt ist)", function(T, H)
		local g, GC, SR, CR = modules(H)
		local MR = g:MiniShared("MiniRules")
		local g0 = MR.DefaultGames()
		if g0.shop == nil then
			T.check(true, "ShopRules noch nicht in MiniRules verkabelt (Integrator: ApplyDefault/ApplyLoad nach StoryRules)")
			return
		end
		T.check(H.DeepEqual(g0.shop, SR.Default()), "DefaultGames.shop = Default")
		local d = g:Rules().NewData(NOW)
		d.level = 100 -- Prestige-Rang 1 ab Level 100 (PrestigeRules.Load behält claimed nur bis RankFor(level))
		d.games = MR.DefaultGames()
		d.money = 1e9
		SR.Buy(d, "rims_gold", NOW)
		SR.Equip(d, "rims", "rims_gold")
		SR.Buy(d, "dlc_komet_sunset", NOW)
		d.games.prestige.claimed[1] = true
		local loaded = MR.LoadGames(H.Copy(d.games), d, NOW)
		T.check(loaded.shop.owned.rims_gold and loaded.shop.equipped.rims == "rims_gold", "Besitz/angelegt bleibt")
		T.check(loaded.shop.dlcCars.dlc_komet_sunset and loaded.shop.owned.wrap_sunset, "DLC bleibt")
		T.check(loaded.shop.owned[GC.Prestige.Rewards[1].cosmetic], "Prestige nachgetragen")
		T.check(H.DeepEqual(MR.LoadGames(H.Copy(loaded), d, NOW).shop, loaded.shop), "LoadGames idempotent für shop")
	end },
}
