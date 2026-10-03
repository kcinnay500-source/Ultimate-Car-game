-- AuctionUI: Tab "auction" (Auktionshaus). Laufende NPC-Versteigerung (Sondermodell, NPC-Bieter mit Stil und
-- Limit-Spanne, Verlauf, Restzeit), Spieler-Auktionen auf diesem Server, Einliefern eigener Autos, eigene Bilanz.
-- Der Client zeigt nur an und sendet Absichten: mini_auction_bid {lot, amount} (Gebot = Absicht; Mindestgebot,
-- Höchstgrenze, Guthaben prüft der Server), mini_auction_consign {id, start, duration} (start = erlaubte Stufe aus
-- AuctionRules.StartOptions), mini_auction_cancel {lot}, mini_travel {key = "auction"}.
-- Daten: mini_notice auction_update (öffentlicher Zustand aus AuctionService.PublicState + you), auction_won,
-- auction_sold (OnNotice) und der Minispiel-Snapshot (credits, level, cars, garageMax, auction {won, sold}).
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Mini = ReplicatedStorage:WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local AuctionRules = require(Mini:WaitForChild("AuctionRules"))

local AuctionUI = {}

local UI, Remote, T
local refs = {}
local pub -- letzter öffentlicher Zustand (auction_update)
local pubAt = 0 -- os.clock beim Empfang
local snap -- letzter Snapshot
local lastResult -- { text, good }
local npcSel = { lot = nil, amount = nil }
local sel = { carId = nil, start = 2, duration = 300 }
local pending = { at = -math.huge, lot = nil }
local PENDING_SECONDS = 2.5
local stepAt = 0
local Lib -- DealerUI.Lib (3D-Vorschau), optional

local INTRO = "Hier kommen seltene Sondermodelle unter den Hammer – für alle Spieler auf diesem Server, eine "
	.. "Versteigerung nach der anderen. NPC-Bieter bieten immer genau das Mindestgebot und höchstens bis zu ihrem "
	.. "Limit (Spanne steht dabei). Ein Gebot in den letzten 15 Sekunden verlängert die Restzeit wieder auf 15 Sekunden. "
	.. "Bezahlt wird erst beim Zuschlag – dann muss dein Guthaben noch reichen. Deine Höchstgebote auf mehreren Losen "
	.. "müssen zusammen gedeckt sein. Platzt das Höchstgebot, läuft die Auktion 30 Sekunden weiter."

local function num(v)
	v = tonumber(v)
	if v == nil or v ~= v or v == math.huge or v == -math.huge then
		return nil
	end
	return v
end

local function credits(n)
	return MiniLocale.Credits(num(n) or 0)
end

local function myId()
	local you = pub and type(pub.you) == "table" and num(pub.you.userId)
	if you and you > 0 then
		return you
	end
	local lp = Players.LocalPlayer
	return lp and lp.UserId or 0
end

local function writable()
	if pub and type(pub.you) == "table" and pub.you.writable == false then
		return false
	end
	return true
end

-- Serverzeit (Restzeiten kommen als Serverzeit-Zeitpunkte)
local function serverNow()
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and num(t) then
		return t
	end
	return (pub and num(pub.now) or 0) + (os.clock() - pubAt)
end

local function lots()
	return pub and type(pub.lots) == "table" and pub.lots or {}
end

local function snapCredits()
	return snap and num(snap.credits) or 0
end

local function snapLevel()
	return snap and num(snap.level) or 1
end

local function carList()
	return snap and type(snap.cars) == "table" and snap.cars or {}
end

local function garageFull()
	local max = snap and num(snap.garageMax) or 20
	return #carList() >= max
end

local function isLive(lot)
	return lot.state == "open" or lot.state == "closing"
end

local function remaining(lot)
	return math.max(0, (num(lot.endsAt) or 0) - serverNow())
end

local function leading(lot)
	return lot.topNpc ~= true and num(lot.topUserId) == myId() and (num(lot.top) or 0) > 0
end

local function tuningText(lot)
	local parts = {}
	local names = { engine = "Motor", gearbox = "Getriebe", tires = "Reifen", suspension = "Fahrwerk", nitro = "Nitro" }
	for _, key in ipairs({ "engine", "gearbox", "tires", "suspension", "nitro" }) do
		local lvl = num(lot[key]) or 0
		if lvl > 0 then
			table.insert(parts, names[key] .. " " .. lvl)
		end
	end
	return #parts > 0 and ("Tuning: " .. table.concat(parts, ", ")) or "Serienzustand"
end

-- Warum darf ich (noch) nicht bieten? nil = darf
local function blocker(lot, amount)
	if lot.state ~= "open" or remaining(lot) <= 0 then
		return lot.state == "closing" and "Zuschlag folgt …" or "Beendet"
	end
	if lot.capped then
		return "Höchstgebot erreicht"
	end
	if lot.kind == "player" and num(lot.sellerId) == myId() then
		return "Deine Auktion"
	end
	if leading(lot) then
		return "Du führst"
	end
	if lot.kind == "player" and not writable() then
		return "Nur mit Speicherprofil"
	end
	if snapLevel() < (num(lot.level) or 1) then
		return "Ab Level " .. tostring(lot.level)
	end
	if garageFull() then
		return "Garage voll"
	end
	if snapCredits() < (amount or 0) then
		return "Zu wenig Credits"
	end
	return nil
end

---------------------------------------------------------------- Absichten
local redraw -- vorwärts

local function sendBid(lot, amount)
	Remote.Send("mini_auction_bid", { lot = lot.id, amount = amount })
	pending = { at = os.clock(), lot = lot.id }
	redraw()
end

local function confirmBid(lot, amount)
	local minBid = num(lot.minBid) or 0
	if amount > minBid or amount >= snapCredits() * 0.5 then
		UI.Confirm(
			credits(amount) .. " für den " .. tostring(lot.name) .. " bieten? Bezahlt wird erst beim Zuschlag – dann muss dein Guthaben noch reichen.",
			function()
				sendBid(lot, amount)
			end,
			"Gebot bestätigen",
			"Bieten"
		)
	else
		sendBid(lot, amount)
	end
end

local function npcLot()
	local found
	for _, lot in ipairs(lots()) do
		if lot.kind == "npc" and (not found or (num(lot.id) or 0) > (num(found.id) or 0)) then
			found = lot
		end
	end
	return found
end

local function npcAmount(lot)
	local minBid = num(lot.minBid) or 0
	if npcSel.lot ~= lot.id or not npcSel.amount or npcSel.amount < minBid then
		npcSel.lot, npcSel.amount = lot.id, minBid
	end
	npcSel.amount = math.min(npcSel.amount, num(lot.maxBid) or npcSel.amount)
	return npcSel.amount
end

local function adjust(dir)
	local lot = npcLot()
	if not lot or lot.state ~= "open" then
		return
	end
	local amount = npcAmount(lot)
	if dir > 0 then
		amount += AuctionRules.Step(amount)
	else
		local down = amount
		local minBid = num(lot.minBid) or 0
		-- einen Schritt zurück (Schritt des kleineren Betrags), nie unter das Mindestgebot
		local candidate = minBid
		while candidate + AuctionRules.Step(candidate) < down do
			candidate += AuctionRules.Step(candidate)
		end
		amount = candidate
	end
	npcSel.amount = math.clamp(amount, num(lot.minBid) or 0, num(lot.maxBid) or amount)
	redraw()
end

local function eligibleCars()
	local out = {}
	for _, car in ipairs(carList()) do
		if type(car) == "table" and not car.locked and num(car.id) and car.dlc ~= true then -- Shop-Sondermodelle nicht versteigerbar
			table.insert(out, car)
		end
	end
	return out
end

local function selectedCar()
	local list = eligibleCars()
	for _, car in ipairs(list) do
		if car.id == sel.carId then
			return car, list
		end
	end
	sel.carId = list[1] and list[1].id or nil
	return list[1], list
end

local function cycleCar(dir)
	local car, list = selectedCar()
	if not car or #list < 2 then
		return
	end
	local index = table.find(list, car) or 1
	index = (index - 1 + dir) % #list + 1
	sel.carId = list[index].id
	redraw()
end

local function ownLiveLot()
	for _, lot in ipairs(lots()) do
		if lot.kind == "player" and num(lot.sellerId) == myId() and isLive(lot) then
			return lot
		end
	end
	return nil
end

local function consign()
	local car = selectedCar()
	if not car or not writable() or ownLiveLot() then
		return
	end
	local options = AuctionRules.StartOptions(car)
	local start = options[math.clamp(sel.start, 1, #options)]
	if not start then
		return
	end
	local id, duration = car.id, sel.duration
	local name = type(car.name) == "string" and car.name or "Auto"
	UI.Confirm(
		string.format(
			"Den %s für %d Min. versteigern? Startgebot %s. Bis zum Ende ist das Auto gesperrt (nicht fahrbar, nicht tunebar). "
				.. "Beim Verkauf gehen 5 %% Gebühr ab. Verlässt du den Server, wird die Auktion abgebrochen.",
			name, math.floor(duration / 60), credits(start)
		),
		function()
			Remote.Send("mini_auction_consign", { id = id, start = start, duration = duration })
		end,
		"Auto einliefern",
		"Einliefern"
	)
end

local function onRowButton(item)
	local lot = item.lot
	if not lot then
		return
	end
	if lot.kind == "player" and num(lot.sellerId) == myId() then
		if lot.state == "open" and (num(lot.bidCount) or 0) == 0 then
			UI.Confirm("Auktion für den " .. tostring(lot.name) .. " zurückziehen? Das Auto ist danach wieder frei.", function()
				Remote.Send("mini_auction_cancel", { lot = lot.id })
			end, "Zurückziehen", "Zurückziehen", T.red)
		end
		return
	end
	local amount = num(lot.minBid) or 0
	if blocker(lot, amount) then
		return
	end
	confirmBid(lot, amount)
end

---------------------------------------------------------------- Aufbau
local function hRow(parent, order, name)
	local row = UI.Frame(parent, {
		Name = name, BackgroundTransparency = 1, LayoutOrder = order, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, UI.MinTouch),
	})
	local l = UI.List(row, 6, true)
	l.VerticalAlignment = Enum.VerticalAlignment.Center
	return row
end

local function share(n)
	return UDim2.new(1 / n, -math.ceil(6 * (n - 1) / n), 1, 0)
end

local function createRow(parent, i)
	local root, left, right = UI.Row(parent, i)
	local item = { root = root }
	item.name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	item.info = UI.Small(left, "", 2)
	item.time = UI.Small(left, "", 3)
	item.button = UI.Button(right, "", T.green, function()
		onRowButton(item)
	end, { Name = "Bieten", TextSize = 14 })
	return item
end

function AuctionUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	refs = {}
	local okLib, lib = pcall(function()
		local m = script.Parent:FindFirstChild("DealerUI")
		return m and require(m).Lib
	end)
	Lib = okLib and type(lib) == "table" and lib or nil

	-- Kopf
	local head = UI.Card(page, 1)
	UI.Title(head, "Auktionshaus", 1)
	UI.Small(head, INTRO, 2)
	refs.stats = UI.Label(head, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 3 })
	refs.result = UI.Label(head, "", { Name = "Ergebnis", TextSize = 15, LayoutOrder = 4, Visible = false })
	UI.Button(head, "Zum Auktionshaus reisen", T.blue, function()
		Remote.Send("mini_travel", { key = "auction" })
	end, { Name = "Reisen", LayoutOrder = 5 })

	-- NPC-Versteigerung
	local npc = UI.Card(page, 2)
	refs.npcCard = npc
	UI.Title(npc, "Versteigerung · Sondermodell", 1)
	if Lib and Lib.Preview then
		local okPreview, preview = pcall(Lib.Preview, npc, 140, 2)
		refs.preview = okPreview and preview or nil
	end
	refs.npcName = UI.Label(npc, "", { Name = "LosName", Font = UI.FontBold, TextSize = 18, LayoutOrder = 3 })
	refs.npcInfo = UI.Small(npc, "", 4)
	refs.npcBid = UI.Label(npc, "", { Name = "Gebot", Font = UI.FontBig, TextSize = 22, TextColor3 = T.yellow, LayoutOrder = 5 })
	refs.npcTime = UI.Label(npc, "", { Name = "Restzeit", Font = UI.FontBold, TextSize = 16, LayoutOrder = 6 })
	refs.npcBidders = UI.Small(npc, "", 7)
	refs.npcHistory = UI.Small(npc, "", 8)
	local amountRow = UI.Frame(npc, {
		Name = "Betrag", BackgroundTransparency = 1, LayoutOrder = 9, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, UI.MinTouch),
	})
	refs.amountRow = amountRow
	refs.npcMinus = UI.Button(amountRow, "−", T.card, function()
		adjust(-1)
	end, { Name = "NpcMinus", Size = UDim2.new(0, 52, 1, 0), TextSize = 22 })
	refs.npcAmount = UI.Label(amountRow, "", {
		Name = "NpcBetrag", AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -116, 1, 0), Position = UDim2.new(0, 58, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Font = UI.FontBold, TextSize = 17,
	})
	refs.npcPlus = UI.Button(amountRow, "+", T.card, function()
		adjust(1)
	end, { Name = "NpcPlus", Size = UDim2.new(0, 52, 1, 0), Position = UDim2.new(1, -52, 0, 0), TextSize = 22 })
	refs.npcButton = UI.Button(npc, "Bieten", T.green, function()
		local lot = npcLot()
		if not lot then
			return
		end
		local amount = npcAmount(lot)
		if blocker(lot, amount) or os.clock() - pending.at < PENDING_SECONDS then
			return
		end
		confirmBid(lot, amount)
	end, { Name = "NpcBieten", LayoutOrder = 10 })

	-- Spieler-Auktionen
	local pl = UI.Card(page, 3)
	UI.Title(pl, "Spieler-Auktionen", 1)
	UI.Small(pl, "Autos anderer Spieler auf diesem Server, samt Tuning und Lack. Du zahlst dein Gebot erst beim Zuschlag. "
		.. "Verlässt der Verkäufer den Server, wird die Auktion abgebrochen; verlässt du ihn, verfällt dein Gebot.", 2)
	refs.plEmpty = UI.Small(pl, "Gerade keine Spieler-Auktionen. Liefere selbst ein Auto ein!", 3)
	local list = UI.Frame(pl, { Name = "Liste", BackgroundTransparency = 1, LayoutOrder = 4 })
	UI.List(list, 10)
	refs.pool = UI.Pool(list, createRow)

	-- Einliefern
	local cs = UI.Card(page, 4)
	UI.Title(cs, "Auto einliefern", 1)
	refs.csInfo = UI.Small(cs, "", 2)
	local carRow = UI.Frame(cs, {
		Name = "AutoWahl", BackgroundTransparency = 1, LayoutOrder = 3, AutomaticSize = Enum.AutomaticSize.None,
		Size = UDim2.new(1, 0, 0, UI.MinTouch),
	})
	refs.carPrev = UI.Button(carRow, "◀", T.card, function()
		cycleCar(-1)
	end, { Name = "AutoZurueck", Size = UDim2.new(0, 48, 1, 0) })
	refs.csCar = UI.Label(carRow, "", {
		Name = "AutoName", AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, -108, 1, 0), Position = UDim2.new(0, 54, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Font = UI.FontBold, TextSize = 16,
	})
	refs.carNext = UI.Button(carRow, "▶", T.card, function()
		cycleCar(1)
	end, { Name = "AutoWeiter", Size = UDim2.new(0, 48, 1, 0), Position = UDim2.new(1, -48, 0, 0) })
	refs.csCarInfo = UI.Small(cs, "", 4)
	UI.Label(cs, "Startgebot", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 5 })
	local startRow = hRow(cs, 6, "Startgebote")
	refs.startButtons = {}
	for i = 1, #AuctionRules.StartShares do
		refs.startButtons[i] = UI.Button(startRow, "", T.card, function()
			sel.start = i
			redraw()
		end, { Name = "Start" .. i, Size = share(#AuctionRules.StartShares), TextSize = 13, LayoutOrder = i })
	end
	UI.Label(cs, "Laufzeit", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 7 })
	local durRow = hRow(cs, 8, "Laufzeiten")
	refs.durButtons = {}
	for i, seconds in ipairs(AuctionRules.Durations) do
		refs.durButtons[i] = UI.Button(durRow, math.floor(seconds / 60) .. " Min.", T.card, function()
			sel.duration = seconds
			redraw()
		end, { Name = "Dauer" .. seconds, Size = share(#AuctionRules.Durations), TextSize = 14, LayoutOrder = i })
	end
	refs.csSummary = UI.Small(cs, "", 9)
	refs.consign = UI.Button(cs, "Einliefern", T.green, consign, { Name = "Einliefern", LayoutOrder = 10 })
	redraw()
end

---------------------------------------------------------------- Anzeige
local function drawHead()
	local st = snap and type(snap.auction) == "table" and snap.auction or {}
	refs.stats.Text = string.format("Ersteigert: %s · Verkauft: %s", MiniLocale.Group(num(st.won) or 0), MiniLocale.Group(num(st.sold) or 0))
	if lastResult then
		refs.result.Text = lastResult.text
		refs.result.TextColor3 = lastResult.good and T.green or T.text
		refs.result.Visible = true
	else
		refs.result.Visible = false
	end
end

local function npcBiddersText(lot)
	local lines = {}
	for _, n in ipairs(type(lot.npcs) == "table" and lot.npcs or {}) do
		local state = n.leading and " · führt" or (n.out and " · ausgestiegen" or "")
		table.insert(lines, string.format("• %s (%s): %s%s", tostring(n.name), tostring(n.styleName or ""), tostring(n.hint or ""), state))
	end
	return #lines > 0 and ("NPC-Bieter:\n" .. table.concat(lines, "\n")) or ""
end

local function historyText(lot)
	local parts = {}
	for i, b in ipairs(type(lot.history) == "table" and lot.history or {}) do
		if i > 4 then
			break
		end
		table.insert(parts, credits(b.amount) .. " " .. tostring(b.name))
	end
	return #parts > 0 and ("Verlauf: " .. table.concat(parts, " · ")) or "Noch keine Gebote."
end

local function setPreview(lot)
	if not refs.preview or not Lib then
		return
	end
	pcall(function()
		local style = Lib.Style and Lib.Style(snap or {}, { model = lot.model, paint = lot.paint, rims = lot.rims, glow = lot.glow, spoiler = lot.spoiler })
		refs.preview:Set(lot.body, style)
	end)
end

local function timeText(lot)
	if lot.state == "open" then
		return "Restzeit " .. AuctionRules.Clock(remaining(lot))
	elseif lot.state == "closing" then
		return "Zuschlag folgt …"
	end
	local nx = pub and pub.next
	if type(nx) == "table" and num(nx.at) then
		return "Nächstes Los in " .. AuctionRules.Clock(nx.at - serverNow()) .. ": " .. tostring(nx.name)
	end
	return "Beendet"
end

local function drawNpc()
	local lot = npcLot()
	local controls = lot ~= nil and lot.state == "open"
	refs.amountRow.Visible = controls
	refs.npcButton.Visible = controls
	if not lot then
		local nx = pub and pub.next
		if type(nx) == "table" then
			refs.npcName.Text = "Als Nächstes: " .. tostring(nx.name)
			refs.npcInfo.Text = string.format("Sondermodell · ab Level %s · Richtwert %s · Startgebot %s",
				tostring(nx.level or 1), credits(nx.value), credits(nx.start))
			refs.npcBid.Text = ""
			refs.npcTime.Text = "Beginn in " .. AuctionRules.Clock((num(nx.at) or 0) - serverNow())
			setPreview(nx)
		else
			refs.npcName.Text = pub and "Gerade keine Versteigerung" or "Lade Auktionen …"
			refs.npcInfo.Text = ""
			refs.npcBid.Text = ""
			refs.npcTime.Text = ""
		end
		refs.npcBidders.Text = ""
		refs.npcHistory.Text = ""
		return
	end
	setPreview(lot)
	refs.npcName.Text = tostring(lot.name) .. " · Los " .. string.format("%03d", num(lot.id) or 0)
	refs.npcInfo.Text = string.format("Sondermodell · ab Level %s · Richtwert %s · Startgebot %s",
		tostring(lot.level or 1), credits(lot.value), credits(lot.start))
	if lot.state == "sold" and type(lot.result) == "table" then
		refs.npcBid.Text = "Zuschlag: " .. credits(lot.result.amount) .. " · " .. tostring(lot.result.name)
	elseif lot.state == "unsold" then
		refs.npcBid.Text = "Nicht verkauft"
	elseif (num(lot.top) or 0) > 0 then
		refs.npcBid.Text = "Aktuelles Gebot: " .. credits(lot.top) .. " · " .. tostring(lot.topName)
	else
		refs.npcBid.Text = "Noch kein Gebot · Start " .. credits(lot.start)
	end
	refs.npcTime.Text = timeText(lot)
	refs.npcBidders.Text = npcBiddersText(lot)
	refs.npcHistory.Text = historyText(lot)
	if controls then
		local amount = npcAmount(lot)
		refs.npcAmount.Text = credits(amount)
		local reason = blocker(lot, amount)
		local waiting = os.clock() - pending.at < PENDING_SECONDS and pending.lot == lot.id
		refs.npcButton.Text = waiting and "Gebot wird geprüft …" or reason or ("Bieten: " .. credits(amount))
		UI.SetEnabled(refs.npcButton, reason == nil and not waiting, T.green)
		UI.SetEnabled(refs.npcPlus, amount < (num(lot.maxBid) or amount), T.card)
		UI.SetEnabled(refs.npcMinus, amount > (num(lot.minBid) or amount), T.card)
	end
end

local function drawPlayers()
	local list = {}
	for _, lot in ipairs(lots()) do
		if lot.kind == "player" then
			table.insert(list, lot)
		end
	end
	table.sort(list, function(a, b)
		local la, lb = isLive(a), isLive(b)
		if la ~= lb then
			return la
		end
		return (num(a.endsAt) or 0) < (num(b.endsAt) or 0)
	end)
	refs.plEmpty.Visible = #list == 0
	refs.pool:Ensure(#list)
	for i, lot in ipairs(list) do
		local item = refs.pool.items[i]
		item.lot = lot
		item.root.Name = "Los_" .. tostring(lot.id)
		local mine = num(lot.sellerId) == myId()
		item.name.Text = tostring(lot.name) .. (mine and " (dein Auto)" or "")
		local price = (num(lot.top) or 0) > 0 and ("Gebot " .. credits(lot.top) .. " · " .. tostring(lot.topName)) or ("Start " .. credits(lot.start))
		item.info.Text = "von " .. tostring(lot.sellerName) .. " · " .. price .. " · ab Level " .. tostring(lot.level or 1) .. "\n" .. tuningText(lot)
		if lot.state == "sold" and type(lot.result) == "table" then
			item.time.Text = "Verkauft an " .. tostring(lot.result.name) .. " für " .. credits(lot.result.amount)
		elseif lot.state == "unsold" then
			item.time.Text = "Nicht verkauft"
		elseif lot.state == "canceled" then
			item.time.Text = "Abgebrochen"
		else
			item.time.Text = timeText(lot)
		end
		local b = item.button
		if mine then
			local canCancel = lot.state == "open" and (num(lot.bidCount) or 0) == 0
			b.Text = canCancel and "Zurückziehen" or "Deine Auktion"
			UI.SetEnabled(b, canCancel, T.red)
		else
			local amount = num(lot.minBid) or 0
			local reason = blocker(lot, amount)
			local waiting = os.clock() - pending.at < PENDING_SECONDS and pending.lot == lot.id
			b.Text = waiting and "Wird geprüft …" or reason or ("Bieten " .. credits(amount))
			UI.SetEnabled(b, reason == nil and not waiting, T.green)
		end
	end
end

local function drawConsign()
	local car, list = selectedCar()
	local own = ownLiveLot()
	local info
	if not writable() then
		info = AuctionRules.Text.writable
	elseif own then
		info = "Du hast schon ein Auto in der Auktion (" .. tostring(own.name) .. "). Warte das Ende ab oder ziehe es zurück, solange es keine Gebote gibt."
	elseif not car then
		info = #carList() > 0 and "Keines deiner Autos kann gerade versteigert werden (in einer Auktion oder Sondermodell aus dem Shop)." or "Du hast noch kein eigenes Auto. Autos gibt es im Autohaus."
	else
		info = "Wähle Auto, Startgebot und Laufzeit. Bis zum Ende ist das Auto gesperrt. Beim Verkauf gehen 5 % Gebühr ab."
	end
	refs.csInfo.Text = info
	UI.SetEnabled(refs.carPrev, #list > 1, T.card)
	UI.SetEnabled(refs.carNext, #list > 1, T.card)
	local options = car and AuctionRules.StartOptions(car) or {}
	sel.start = math.clamp(sel.start, 1, math.max(1, #options))
	if car then
		refs.csCar.Text = tostring(car.name or car.model)
		refs.csCarInfo.Text = "Richtwert " .. credits(AuctionRules.RefValue(car)) .. " (Wert + Tuning) · " .. tuningText(car)
	else
		refs.csCar.Text = "–"
		refs.csCarInfo.Text = ""
	end
	for i, b in ipairs(refs.startButtons) do
		local v = options[i]
		b.Visible = v ~= nil
		b.Text = v and credits(v) or ""
		UI.SetEnabled(b, v ~= nil, i == sel.start and T.blue or T.card)
	end
	for i, b in ipairs(refs.durButtons) do
		UI.SetEnabled(b, true, AuctionRules.Durations[i] == sel.duration and T.blue or T.card)
	end
	local start = options[sel.start]
	if car and start then
		local fee, payout = AuctionRules.Fee(start)
		refs.csSummary.Text = string.format("Startgebot %s · %d Min. · Verkauf zum Startgebot: du erhältst %s (Gebühr %s).",
			credits(start), math.floor(sel.duration / 60), credits(payout), credits(fee))
	else
		refs.csSummary.Text = ""
	end
	UI.SetEnabled(refs.consign, car ~= nil and start ~= nil and writable() and own == nil, T.green)
end

redraw = function()
	if not refs.stats then
		return
	end
	drawHead()
	drawNpc()
	drawPlayers()
	drawConsign()
end

-- Snapshot (credits, level, cars, auction)
function AuctionUI.Render(s)
	if type(s) ~= "table" then
		return
	end
	snap = s
	redraw()
end

function AuctionUI.OnShow()
	redraw()
end

-- mini_notice auction_update / auction_won / auction_sold
function AuctionUI.OnNotice(data)
	if type(data) ~= "table" then
		return
	end
	if data.kind == "auction_update" then
		pub = data
		pubAt = os.clock()
		pending.at = -math.huge
	elseif data.kind == "auction_won" then
		lastResult = { text = "Zuschlag! Der " .. tostring(data.name) .. " gehört jetzt dir (" .. credits(data.amount) .. ").", good = true }
	elseif data.kind == "auction_sold" then
		lastResult = {
			text = "Verkauft: dein " .. tostring(data.name) .. " an " .. tostring(data.buyer) .. " für " .. credits(data.amount)
				.. " (Gutschrift " .. credits(data.payout) .. ").",
			good = true,
		}
	else
		return
	end
	redraw()
end

-- Pro Frame (sichtbarer Tab): Restzeiten, gedrosselt
function AuctionUI.Step()
	local t = os.clock()
	if t - stepAt < 0.2 then
		return
	end
	stepAt = t
	if not refs.npcTime then
		return
	end
	local lot = npcLot()
	if lot then
		refs.npcTime.Text = timeText(lot)
		if lot.state == "open" and remaining(lot) <= 0 then
			refs.npcTime.Text = "Zuschlag folgt …"
		end
	else
		local nx = pub and pub.next
		if type(nx) == "table" and num(nx.at) then
			refs.npcTime.Text = "Beginn in " .. AuctionRules.Clock(nx.at - serverNow())
		end
	end
	for _, item in ipairs(refs.pool.items) do
		local l = item.lot
		if item.root.Visible and l and l.state == "open" then
			item.time.Text = timeText(l)
		end
	end
	-- Warten auf die Server-Antwort vorbei: Knöpfe wieder freigeben
	if pending.lot and t - pending.at >= PENDING_SECONDS then
		pending.lot = nil
		redraw()
	end
end

return AuctionUI
