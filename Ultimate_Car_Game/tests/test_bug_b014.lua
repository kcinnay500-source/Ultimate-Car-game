-- B-014: shop_prompt prüfte bei Robux-Produkten erst ShopRules.CanPrompt (Besitz, Level-Riegel der DLC-Autos) und
-- danach, ob hier überhaupt Robux-Käufe möglich sind (Studio / Profil nicht speicherbar). In Studio – und bei einem
-- temporären Profil nach einem Ladefehler, das immer Level 1 hat – kam deshalb „erst ab Level …“ statt des Hinweises,
-- dass Robux-Käufe hier nicht verfügbar sind. Jetzt kommt die Studio-/writable-Prüfung vor dem Riegel.
local CAR_PRODUCT = 515951

local function setIds(g)
	local GC = g:MiniShared("GameConfig")
	GC.Shop.ProductByKey.car_komet_sunset.productId = CAR_PRODUCT
end

local function prompt(g, p, product, rid)
	g:Advance(4)
	local m = g:Mark()
	g:Act(p, "shop_prompt", { product = product, rid = rid })
	g:Flush()
	return m
end

local function texts(g, p, m)
	local out = {}
	for _, msg in ipairs(g:Toasts(p, m)) do
		out[#out + 1] = tostring(msg)
	end
	return table.concat(out, " | ")
end

return {
	{ "Studio, Level 1: Robux-Hinweis statt Level-Meldung; unbekannt / nicht eingerichtet bleiben", function(T, H)
		local g = H.Garage({ studio = true, before = setIds })
		local p = g:Join(1401, { name = "Kim" })
		g:Advance(1)
		T.check(g:D(p).level < 8, "Studio-Profil unter dem Level des Sondermodells (Level " .. tostring(g:D(p).level) .. ")")
		local m = prompt(g, p, "car_komet_sunset", 1)
		T.check(g:HasToast(p, "noch nicht verfügbar", m), "Studio: Robux-Hinweis (" .. texts(g, p, m) .. ")")
		T.check(not g:HasToast(p, "Level", m), "Studio: keine Level-Meldung (" .. texts(g, p, m) .. ")")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "Studio: kein Prompt")
		-- Reihenfolge davor bleibt: unbekanntes Produkt, Platzhalter-Id 0
		m = prompt(g, p, "gibt_es_nicht", 2)
		T.check(g:HasToast(p, "gibt es nicht", m), "unbekanntes Produkt: eigener Hinweis (" .. texts(g, p, m) .. ")")
		g:MiniShared("GameConfig").Shop.ProductByKey.car_komet_sunset.productId = 0
		m = prompt(g, p, "car_komet_sunset", 3)
		T.check(g:HasToast(p, "noch nicht eingerichtet", m), "Id 0: noch nicht eingerichtet (" .. texts(g, p, m) .. ")")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Temporäres Profil nach Ladefehler (kein Studio): Robux-Hinweis statt Level-Meldung", function(T, H)
		local g = H.Garage({ before = function(g)
			setIds(g)
			g.env.services.DataStoreService.__data.fail = true -- Laden schlägt fehl -> Sitzung nur temporär
		end })
		local p = g:Join(1402, { name = "Lea" })
		g:Advance(60)
		local prof = g:Profile(p)
		T.check(prof ~= nil, "Sitzung besteht")
		T.eq(prof and prof.writable == true, false, "Profil nicht speicherbar")
		local m = prompt(g, p, "car_komet_sunset", 1)
		T.check(g:HasToast(p, "noch nicht verfügbar", m), "temporär: Robux-Hinweis (" .. texts(g, p, m) .. ")")
		T.check(not g:HasToast(p, "Level", m), "temporär: keine Level-Meldung (" .. texts(g, p, m) .. ")")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "temporär: kein Prompt")
	end },

	{ "Echter Server, speicherbares Profil: Level-Riegel greift weiter, ab dem Level kommt der Prompt", function(T, H)
		local g = H.Garage({ level = 5, before = setIds })
		local p = g:Join(1403, { name = "Mia" })
		g:Advance(1)
		local m = prompt(g, p, "car_komet_sunset", 1)
		T.check(g:HasToast(p, "Level 8", m), "unter dem Level: Level-Meldung (" .. texts(g, p, m) .. ")")
		T.eq(#g:Events(p, "purchasePrompt", m), 0, "unter dem Level: kein Prompt")
		g:D(p).level = 8
		m = prompt(g, p, "car_komet_sunset", 2)
		T.eq(#g:Events(p, "purchasePrompt", m), 1, "ab dem Level: Prompt")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
