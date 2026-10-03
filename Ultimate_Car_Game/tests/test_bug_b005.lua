-- B-005: Robux-Kauf während eines langsamen Speicherns. GrantReceipt gibt nach 10 s auf (profile.saving), ohne
-- receiptPending zu setzen; der Server muss die Quittung trotzdem in der Sitzung erneut versuchen.
local PRODUCT = 525252

local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
end

-- Spieler mit 800 Credits; ein Autosave hängt `seconds` im DataStore (nur dieser eine Aufruf ist langsam).
local function setup(H, userId, name, seconds)
	local g = H.Garage()
	local C = g:Config()
	local product = C.CreditProducts[1]
	product.productId = PRODUCT
	local ds = g:DataStoreMock()
	local p = g:Join(userId, { name = name })
	g:Advance(1)
	g:D(p).money = 800
	local before = ds.calls.update
	ds.updateYield = seconds
	local guard = 0
	while ds.calls.update == before and guard < C.AutosaveSeconds * 4 + 8 do
		g:Advance(0.25)
		guard += 1
	end
	ds.updateYield = 0
	return g, p, product, ds
end

return {
	{ "Kauf während eines 15 s langsamen Autosave: Gutschrift und Beleg ohne Wiederbeitritt, genau einmal", function(T, H)
		local g, p, product = setup(H, 9051, "Olaf", 15)
		T.eq(g:Profile(p).saving, true, "Autosave hängt im DataStore")
		local m = g:Mark()
		local decision, done = g:Purchase(p, PRODUCT, "kauf-b005")
		T.eq(done, false, "Kauf wartet auf das laufende Speichern")
		g:Advance(11)
		T.eq(g:D(p).money, 800, "noch keine Gutschrift (Speichern läuft)")
		T.eq(g:Record(9051).receipts["kauf-b005"], nil, "noch kein Beleg")
		g:Advance(25) -- der DataStore antwortet wieder; der Server versucht die Quittung selbst erneut
		T.eq(g:D(p).money, 800 + product.credits, "Credits in der Sitzung gutgeschrieben")
		T.eq(g:Record(9051).receipts["kauf-b005"], true, "Beleg gespeichert")
		T.eq(g:Record(9051).data.money, 800 + product.credits, "gespeicherter Stand stimmt")
		T.eq(#g:Events(p, "purchaseFX", m), 1, "eine Kaufmeldung")
		T.eq(g:Profile(p).transacting, false, "nicht mehr gesperrt")
		-- Roblox stellt die Quittung später von sich aus erneut zu: gewährt, nichts doppelt
		T.eq(g:Purchase(p, PRODUCT, "kauf-b005"), Enum.ProductPurchaseDecision.PurchaseGranted, "Wiederholung von Roblox gewährt")
		g:Advance(20)
		T.eq(g:D(p).money, 800 + product.credits, "keine Doppelgutschrift")
		T.eq(#g:Events(p, "purchaseFX", m), 1, "weiter nur eine Kaufmeldung")
		local _ = decision
		noErrors(T, g)
	end },

	{ "ProcessReceipt meldet während des langsamen Speicherns nicht 'PurchaseGranted'", function(T, H)
		local g, p = setup(H, 9052, "Pia", 15)
		local result
		g:Activate()
		local cb = g.env.services.MarketplaceService.__data.ProcessReceipt
		g.env.scheduler:spawnIn(g.env.serverCtx, function()
			result = cb({ PlayerId = p.UserId, ProductId = PRODUCT, PurchaseId = "kauf-b005-b", CurrencySpent = 0 })
		end)
		g:Advance(11)
		T.eq(result, Enum.ProductPurchaseDecision.NotProcessedYet, "ohne gespeicherten Beleg nicht gewährt")
		T.eq(g:Record(9052).receipts["kauf-b005-b"], nil, "Beleg steht noch nicht im Datensatz")
		noErrors(T, g)
	end },

	{ "Verlassen während der Wiederholung: keine Doppelgutschrift, Beleg und Credits nur zusammen", function(T, H)
		local g, p, product, ds = setup(H, 9053, "Rosa", 15)
		g:Purchase(p, PRODUCT, "kauf-b005-c")
		g:Advance(15.5) -- Autosave fertig, Wiederholung steht kurz bevor
		ds.updateYield = 4 -- die Wiederholung schreibt langsam
		local guard = 0
		while not g:Profile(p).transacting and guard < 80 do
			g:Advance(0.25)
			guard += 1
		end
		T.eq(g:Profile(p).transacting, true, "Wiederholung der Quittung läuft")
		g:Leave(p)
		g:Advance(20)
		ds.updateYield = 0
		local rec = g:Record(9053)
		T.eq(rec.lock, nil, "Sperre frei")
		T.eq(rec.receipts["kauf-b005-c"] == true, rec.data.money == 800 + product.credits, "Beleg und Credits nur zusammen")
		local again = g:Join(9053, { name = "Rosa" })
		g:Advance(1)
		T.eq(g:Profile(again) and g:Profile(again).writable, true, "Wiederbeitritt schreibbar")
		T.eq(g:Purchase(again, PRODUCT, "kauf-b005-c"), Enum.ProductPurchaseDecision.PurchaseGranted, "Roblox-Wiederholung gewährt")
		g:Advance(20)
		T.eq(g:D(again).money, 800 + product.credits, "genau eine Gutschrift")
		T.eq(g:Record(9053).receipts["kauf-b005-c"], true, "Beleg gespeichert")
		noErrors(T, g)
	end },
}
