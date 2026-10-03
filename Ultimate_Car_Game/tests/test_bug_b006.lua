-- B-006: Auktionsbuch (Fenster von 20 Einträgen) und received-Liste im Profil (ebenfalls 20) liefen auseinander:
-- ein Buch-Eintrag, dessen tid das Profil schon aus received verdrängt hatte, galt beim Laden als „nicht gespeichert“
-- und wurde bei JEDEM Beitritt erneut nachgeholt (Auto dazu, Preis ab). Rein (AuctionRules), Stil wie test_auction.lua.
local NOW = 1760000000

local function newData(g, money)
	local d = g:Rules().NewData(NOW)
	d.money = money or 0
	d.level = 10
	if type(d.games.cars) ~= "table" then
		g:MiniShared("CarRules").ApplyDefault(d.games)
	end
	d.games.auction = g:MiniShared("AuctionRules").Default()
	return d
end

-- Übergabe Nr. i (Verkäufer 1, Auto-Id i, eine Minute Abstand): Buch-Eintrag der Käufer-Seite
local function entry(g, i)
	local AR, CR = g:MiniShared("AuctionRules"), g:MiniShared("CarRules")
	local at = NOW + i * 60
	local car = CR.NewCar("komet", NOW - 3600)
	car.locked = false
	return { tid = AR.TransferId(1, i, at), car = car, amount = 1000, at = at }
end

-- Buch-Liste wie AuctionLedger.append: gleiche tid ersetzen, hinten anfügen, auf MaxReceived kürzen
local function ledgerAppend(g, list, e)
	local AR = g:MiniShared("AuctionRules")
	for i = #list, 1, -1 do
		if list[i].tid == e.tid then
			table.remove(list, i)
		end
	end
	table.insert(list, e)
	while #list > AR.MaxReceived do
		table.remove(list, 1)
	end
end

-- Profil speichern und wieder laden (Normalisierung wie MiniRules.LoadGames), dann abgleichen
local function rejoin(H, g, d, bought)
	local AR = g:MiniShared("AuctionRules")
	d.games.auction = AR.Load(H.Copy(d.games.auction), d, NOW + 100000)
	return AR.ReconcileBuyer(d, H.Copy(bought))
end

local function fiveJoins(T, H, g, d, bought, label)
	local cars, money, won = #d.games.cars, d.money, d.games.auction.won
	for n = 1, 5 do
		T.eq(rejoin(H, g, d, bought), 0, label .. ": Beitritt " .. n .. " holt nichts nach")
	end
	T.eq(#d.games.cars, cars, label .. ": 0 zusätzliche Autos")
	T.eq(d.money, money, label .. ": Geld unverändert")
	T.eq(d.games.auction.won, won, label .. ": Zähler unverändert")
end

return {
	{ "B-006: 21 Käufe, Buch-Eintrag des 21. fehlt – 5 Beitritte holen nichts nach", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local d = newData(g, 50000)
		local bought = {}
		for i = 1, 21 do
			local e = entry(g, i)
			AR.NoteReceived(d, e.tid) -- wie AuctionRules.Handover (das Auto wurde längst weiterverkauft)
			d.games.auction.won += 1
			if i <= 20 then
				ledgerAppend(g, bought, e) -- der 21. Schreibversuch schlägt dreimal fehl
			end
		end
		T.eq(#d.games.auction.received, AR.MaxReceived, "received hält 20 Einträge")
		T.eq(#bought, 20, "Buch hält 20 Einträge")
		T.eq(bought[1].tid, entry(g, 1).tid, "Buch hält noch den 1. Kauf, den das Profil verdrängt hat")
		fiveJoins(T, H, g, d, bought, "fehlender Eintrag")
	end },

	{ "B-006: zwei Buch-Einträge in anderer Reihenfolge geschrieben – 5 Beitritte holen nichts nach", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local d = newData(g, 50000)
		local bought = {}
		for i = 1, 21 do
			AR.NoteReceived(d, entry(g, i).tid)
		end
		ledgerAppend(g, bought, entry(g, 2)) -- 2 landet vor 1
		ledgerAppend(g, bought, entry(g, 1))
		for i = 3, 21 do
			ledgerAppend(g, bought, entry(g, i))
		end
		T.eq(bought[1].tid, entry(g, 1).tid, "Buch hält den 1. Kauf, das Profil nicht mehr")
		fiveJoins(T, H, g, d, bought, "vertauschte Einträge")
	end },

	{ "B-006: altes Profil ohne die Marke (volles received-Fenster) lädt korrekt und holt nichts doppelt nach", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		local d = newData(g, 50000)
		local raw = { won = 21, sold = 0, partners = {}, received = {} } -- Stand vor dem Fix gespeichert
		local bought = {}
		for i = 1, 21 do
			if i >= 2 then
				table.insert(raw.received, entry(g, i).tid)
			end
			if i <= 20 then
				ledgerAppend(g, bought, entry(g, i))
			end
		end
		d.games.auction = AR.Load(raw, d, NOW + 100000)
		T.eq(d.games.auction.won, 21, "Zähler übernommen")
		T.eq(#d.games.auction.received, 20, "received übernommen")
		T.check(H.DeepEqual(AR.Load(H.Copy(d.games.auction), d, NOW + 100000), d.games.auction), "Load idempotent")
		fiveJoins(T, H, g, d, bought, "altes Profil")
		-- Normalisierung der Marke
		T.eq(AR.Default().doneAt, 0, "Standard: keine Marke")
		T.eq(AR.Load({ won = 1 }).doneAt, 0, "Feld fehlt, Fenster nicht voll -> 0")
		T.eq(AR.Load({ doneAt = 0 / 0 }).doneAt, 0, "NaN -> 0")
		T.eq(AR.Load({ doneAt = -5 }).doneAt, 0, "negativ -> 0")
		T.eq(AR.Load({ doneAt = "x" }).doneAt, 0, "kein Zahlwert -> 0")
		T.eq(AR.Load({ doneAt = 1234.7 }).doneAt, 1234, "ganzzahlig")
		local few = AR.Load({ won = 3, received = { entry(g, 1).tid, entry(g, 2).tid, entry(g, 3).tid } })
		T.eq(few.doneAt, 0, "wenige Käufe: keine Marke")
	end },

	{ "B-006: echte offene Übergabe (Absturz vor dem Speichern) wird weiter genau einmal nachgeholt", function(T, H)
		local g = H.Garage({ noServer = true })
		local AR = g:MiniShared("AuctionRules")
		-- neues Profil: 25 gespeicherte Käufe, der 26. steht nur im Buch
		local d = newData(g, 50000)
		local bought = {}
		for i = 1, 26 do
			local e = entry(g, i)
			if i <= 25 then
				AR.NoteReceived(d, e.tid)
			end
			ledgerAppend(g, bought, e)
		end
		local cars, money = #d.games.cars, d.money
		T.eq(rejoin(H, g, d, bought), 1, "offene Übergabe nachgeholt")
		T.eq(#d.games.cars, cars + 1, "genau ein Auto dazu")
		T.eq(d.money, money - 1000, "Preis einmal abgezogen")
		fiveJoins(T, H, g, d, bought, "nach dem Nachholen")

		-- altes Profil ohne Marke: Käufe 2..21 gespeichert, der 22. steht nur im Buch
		local d2 = newData(g, 50000)
		local raw = { won = 21, sold = 0, partners = {}, received = {} }
		local bought2 = {}
		for i = 1, 22 do
			if i >= 2 and i <= 21 then
				table.insert(raw.received, entry(g, i).tid)
			end
			ledgerAppend(g, bought2, entry(g, i))
		end
		d2.games.auction = raw
		local cars2, money2 = #d2.games.cars, d2.money
		T.eq(rejoin(H, g, d2, bought2), 1, "altes Profil: offene Übergabe nachgeholt")
		T.eq(#d2.games.cars, cars2 + 1, "altes Profil: genau ein Auto dazu")
		T.eq(d2.money, money2 - 1000, "altes Profil: Preis einmal abgezogen")
		fiveJoins(T, H, g, d2, bought2, "altes Profil nach dem Nachholen")

		-- erster Kauf überhaupt, nichts gespeichert
		local d3 = newData(g, 50000)
		T.eq(rejoin(H, g, d3, { entry(g, 1) }), 1, "erster Kauf: nachgeholt")
		T.eq(rejoin(H, g, d3, { entry(g, 1) }), 0, "erster Kauf: nicht doppelt")
	end },
}
