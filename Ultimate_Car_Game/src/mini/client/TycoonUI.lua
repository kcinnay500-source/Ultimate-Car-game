-- TycoonUI: Tab „Schnelles Spiel“ (tycoon) (docs/PHASE4_CONTRACT.md §8, §10, §11).
-- Ohne Durchlauf: vier Gebäude-Karten (Beschreibung, Spielweise, Open-World-Bonus einer fertigen Runde) → tycoon_choose.
-- Mit Durchlauf: Kopf (Typ, Stufe n/5, Bargeld, Behälter x/Kapazität, Rate/s), „Sammeln“ (tycoon_collect), Upgrades der
-- aktuellen Stufe (Name, Wirkung, Kosten, Kaufen/Gekauft, Sperrgrund) → tycoon_buy {id}, Stufen-Karte (Preis + Waren)
-- → tycoon_stage (Vertrag §10; TycoonUI.StageAction = "tycoon_buy" schickt stattdessen tycoon_buy {id = "<typ>_stage<n>"}), Lager, Handel (Angebote an mich → tycoon_trade_accept, meine Angebote →
-- tycoon_trade_cancel, neues Angebot → tycoon_trade_offer {to, item, qty, price}), Rebirth (Bestätigung →
-- tycoon_rebirth), Abbruch (Bestätigung → tycoon_abandon), „Zurück zur Lobby“ (lobby_return).
-- Marktplatz-Tafel (Workspace.Tycoon.Markt.Tafel.MarketScreen.Offers) wird nur auf dem Client aus
-- mini_notice { kind = "tycoon_market", offers = {...} } beschrieben.
-- Der Client zeigt nur an und sendet Absichten; Bargeld ist NIE Credits. Alle Zahlen aus GameConfig.Tycoon.
--
-- Erwartete Snapshot-Felder (TycoonService.SnapshotFields / TycoonRules.Summary):
--   s.mode, s.tycoon = { run = false | { building, name, stage, cash, container, capacity, rate, upgrades[] (Ids),
--                        storage { [item] = n }, items { [item] = je Min. }, offers[] { id, cost, ok, reason },
--                        missing { [item] = fehlend }, rebirthBoost, complete, canRebirth, rebirthReason },
--                        rebirths, runsDone { [typ] = n }, boost, bonus { [typ] = { runs, pct, text } },
--                        slot (optional), offers[] (Handel, optional: { id, from, fromName, to, toName, item, qty, price,
--                        expiresAt }), players[] (optional: { userId, name }) }
--   s.tycoonPlayers[] (optional, { userId, name }); ohne Liste nur Absender offener Marktangebote, nie Players:GetPlayers()
--   (Lobby-/Open-World-Spieler oder Tycoon-Spieler ohne Durchlauf könnten sonst gewählt werden).
-- Schnittstelle wie die anderen Bereiche: Build(page, ctx), Render(s), OnShow(), OnNotice(data).
local Players = game:GetService("Players")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(Mini:WaitForChild("GameConfig"))
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local TycoonUI = {}

local TY = GameConfig.Tycoon
local UI, Remote, T, ctx
local refs = {}
local latest = nil
local pendingChoice = nil -- lokal gewählter Typ, bis der Snapshot den Durchlauf zeigt
local trade = { to = nil, toName = nil, item = nil, qty = 1, price = 0, priceTouched = false, listOpen = false }
local marketOffers = {} -- letzte Marktplatz-Angebote (mini_notice tycoon_market), auch als Spielerquelle

TycoonUI.MaxQty = TY.TradeMaxQty or 999
TycoonUI.MinPrice = TY.TradeMinPrice or 1
TycoonUI.MaxPrice = TY.TradeMaxPrice or 999999999
TycoonUI.StageAction = "tycoon_stage" -- Stufen-Karte: Vertragsaktion; "tycoon_buy" sendet tycoon_buy {id = stageId}

-- Texte je Gebäudetyp: Spielweise (Karte ohne Durchlauf). Nur echte Unterschiede: alle Typen laufen mit derselben
-- Tuning-Tabelle (gleiche Stufenzeiten, ≈ 5 Std.); sie unterscheiden sich in den erzeugten Waren (GameConfig.Tycoon
-- .Buildings[typ].items) und im Open-World-Bonus einer fertigen Runde (Zeile „Fertige Runde“).
local STYLE_FLAVOUR = {
	werkstatt = "gut für den Einstieg",
	autohaus = "Lack für Lackierer",
	produktion = "Bauteile für alle",
	schrottplatz = "Schrott für den Marktplatz",
}
local function styleText(typ: string): string
	local b = TY.Buildings[typ]
	local names = {}
	for _, item in ipairs(b and b.items or {}) do
		local it = TY.Items[item]
		table.insert(names, it and it.name or item)
	end
	local flavour = STYLE_FLAVOUR[typ]
	return "Spielweise: 5 Stufen mit je " .. tostring(TY.UpgradesPerStage) .. " Upgrades, gleiches Tempo wie alle Gebäude. Dein Lager erzeugt "
		.. table.concat(names, " und ") .. " zum Handeln" .. (flavour and (" – " .. flavour) or "") .. "."
end
local STYLE = setmetatable({}, {
	__index = function(_, typ)
		return TY.Buildings[typ] and styleText(typ) or ""
	end,
})

local KIND_TEXT = { producer = "Produzent", tempo = "Tempo", lager = "Lager", deko = "Deko" }

local REASONS = {
	cash = "Nicht genug Bargeld",
	items = "Waren fehlen",
	stage_incomplete = "Erst alle Upgrades dieser Stufe kaufen",
	wrong_stage = "Andere Stufe",
	wrong_building = "Anderes Gebäude",
	owned = "Gekauft",
	unknown = "Unbekannt",
	no_run = "Kein Durchlauf",
	stage = "Erst Stufe " .. tostring(TY.Rebirth.requiresStage) .. " erreichen",
	upgrades = "Erst alle Upgrades der Stufe " .. tostring(TY.Rebirth.requiresStage) .. " kaufen",
}

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v or default
end

local function cash(n: any): string
	return MiniLocale.Number(num(n, 0)) .. " Bargeld"
end

local function pctText(fraction: any): string
	local v = num(fraction, 0) * 100
	return MiniLocale.Decimal(v, 1) .. " %"
end

local function itemName(item: any): string
	local it = type(item) == "string" and TY.Items[item] or nil
	return it and it.name or tostring(item)
end

local function guidePrice(item: any): number
	local it = type(item) == "string" and TY.Items[item] or nil
	return it and num(it.guide, 10) or 10
end

local function toast(text: string)
	if ctx and type(ctx.Toast) == "function" and text ~= "" then
		ctx.Toast(text)
	end
end

local function localUserId(): number
	local me = Players.LocalPlayer
	return me and me.UserId or 0
end

-- Bonus-Text einer fertigen Runde: „+2 % Werkstatt-Vergütung je Runde (max +10 %)“ bzw. Rabatt als Minus
local function bonusText(typ: string): string
	local b = TY.Bonus[typ]
	if not b then
		return ""
	end
	local sign = typ == "autohaus" and "−" or "+"
	return sign .. pctText(b.step) .. " " .. tostring(b.text) .. " je fertiger Runde (max " .. sign .. pctText(b.step * b.maxRuns) .. ")"
end
TycoonUI.BonusText = bonusText

-- Wirkung eines Upgrades als kurzer Text
local function effectText(u: any): string
	if type(u) ~= "table" then
		return ""
	end
	if u.kind == "producer" then
		return "+" .. MiniLocale.Decimal(num(u.rate, 0), 2) .. " Bargeld/s"
	elseif u.kind == "tempo" then
		return "Rate " .. MiniLocale.Factor(num(u.mult, 1))
	elseif u.kind == "lager" then
		return "+" .. MiniLocale.Number(num(u.cap, 0)) .. " Behälter · " .. MiniLocale.Decimal(num(u.perMin, 0), 1) .. " " .. itemName(u.item) .. "/Min."
	elseif u.kind == "deko" then
		return "+" .. pctText(num(u.bonus, 0)) .. " auf alles"
	end
	return ""
end
TycoonUI.EffectText = effectText

local function run(): any
	local t = latest and type(latest.tycoon) == "table" and latest.tycoon or nil
	local r = t and t.run or nil
	return type(r) == "table" and r or nil
end

local function tycoon(): any
	return latest and type(latest.tycoon) == "table" and latest.tycoon or {}
end

local function inTycoon(): boolean
	return latest == nil or latest.mode == nil or latest.mode == "tycoon"
end

-- Spieler für das Angebot: Snapshot-Liste (tycoon.players: im Schnellen Spiel mit Durchlauf), sonst Absender offener
-- Marktangebote (ohne mich). Kein Players:GetPlayers(): der Server lehnt Spieler ohne Durchlauf ohnehin ab.
local function candidates(): { { userId: number, name: string } }
	local out, seen = {}, {}
	local me = localUserId()
	local function add(userId: any, name: any)
		userId = tonumber(userId)
		if not userId or userId == me or seen[userId] then
			return
		end
		seen[userId] = true
		table.insert(out, { userId = userId, name = type(name) == "string" and name or ("Spieler " .. tostring(userId)) })
	end
	-- beide Quellen ausdrücklich (kein ipairs über eine Liste mit nil-Lücke: fehlt tycoonPlayers, fiele players weg)
	for _, list in pairs({ latest and latest.tycoonPlayers or false, tycoon().players or false }) do
		if type(list) == "table" then
			for _, pl in ipairs(list) do
				if type(pl) == "table" then
					add(pl.userId or pl.id, pl.name)
				end
			end
		end
	end
	if #out == 0 then
		for _, o in ipairs(marketOffers) do
			if type(o) == "table" then
				add(o.from, o.fromName)
			end
		end
	end
	table.sort(out, function(a, b)
		return a.name < b.name
	end)
	return out
end

---------------------------------------------------------------- Bausteine
local function typeCard(parent, typ: string, order: number)
	local b = TY.Buildings[typ]
	local button = UI.Button(parent, "", T.blue, function()
		if not inTycoon() then
			toast("Das Schnelle Spiel startest du auf dem Tycoon-Gelände: Lobby → „Schnelles Spiel“.")
			return
		end
		pendingChoice = typ
		Remote.Send("tycoon_choose", { building = typ })
		TycoonUI.Render(latest)
	end, { Name = "Choose_" .. typ, LayoutOrder = order, Size = UDim2.new(1, 0, 0, 120), AutomaticSize = Enum.AutomaticSize.Y, Text = "" })
	local inner = UI.Frame(button, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0) })
	UI.Padding(inner, 14, 12)
	UI.List(inner, 4)
	UI.Label(inner, b and b.name or typ, { Font = UI.FontBig, TextSize = 22, LayoutOrder = 1, Name = "Title" })
	UI.Label(inner, b and b.desc or "", { TextSize = 15, LayoutOrder = 2, Name = "Desc" })
	UI.Label(inner, STYLE[typ] or "", { TextSize = 14, LayoutOrder = 3, Name = "Style" })
	UI.Label(inner, "Fertige Runde: " .. bonusText(typ), { Font = UI.FontBold, TextSize = 14, LayoutOrder = 4, Name = "Bonus" })
	local state = UI.Label(inner, "", { Font = UI.FontBold, TextSize = 14, LayoutOrder = 5, Name = "State" })
	return { root = button, state = state, typ = typ }
end

local function upgradeRow(parent, i: number)
	local row, left, right = UI.Row(parent, 10 + i)
	row.Name = "Upgrade_" .. i
	local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	local desc = UI.Small(left, "", 2)
	local effect = UI.Small(left, "", 3)
	local item = { root = row, name = name, desc = desc, effect = effect, id = nil, ok = false }
	item.button = UI.Button(right, "Kaufen", T.green, function()
		if item.id and item.ok then
			Remote.Send("tycoon_buy", { id = item.id })
		elseif item.id then
			toast(item.reasonText or "Noch gesperrt.")
		end
	end, { TextSize = 14, Name = "Buy_" .. i })
	return item
end

local function offerRow(parent, i: number, action: string, buttonText: string, color)
	local row, left, right = UI.Row(parent, 10 + i)
	row.Name = action == "accept" and ("Incoming_" .. i) or ("Outgoing_" .. i)
	local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
	local sub = UI.Small(left, "", 2)
	local item = { root = row, name = name, sub = sub, id = nil }
	item.button = UI.Button(right, buttonText, color, function()
		if item.id == nil then
			return
		end
		if action == "accept" then
			Remote.Send("tycoon_trade_accept", { id = item.id })
		else
			Remote.Send("tycoon_trade_cancel", { id = item.id })
		end
	end, { TextSize = 14, Name = (action == "accept" and "Accept_" or "Cancel_") .. i })
	return item
end

local function playerRow(parent, i: number)
	local item = {}
	item.root = UI.Button(parent, "", T.card, function()
		if item.userId then
			trade.to, trade.toName = item.userId, item.name
			trade.listOpen = false
			TycoonUI.Render(latest)
		end
	end, { Name = "Player_" .. i, LayoutOrder = i, TextXAlignment = Enum.TextXAlignment.Left })
	UI.Padding(item.root, 12, 0)
	return item
end

-- Stepper: [−][ Wert ][+] mit 44-px-Knöpfen; step(sign) verändert den Wert
local function stepper(parent, order: number, prefix: string, step: (number) -> ())
	local w = UI.MinTouch + 8
	local row = UI.Frame(parent, { BackgroundTransparency = 1, LayoutOrder = order, Size = UDim2.new(1, 0, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.None })
	row.Name = prefix .. "Row"
	local minus = UI.Button(row, "−", T.line, function()
		step(-1)
	end, { Name = prefix .. "Minus", Size = UDim2.new(0, w, 1, 0), TextSize = 22 })
	local value = UI.Label(row, "", {
		Name = prefix .. "Value", Font = UI.FontBold, TextSize = 16, AutomaticSize = Enum.AutomaticSize.None,
		Position = UDim2.new(0, w + 6, 0, 0), Size = UDim2.new(1, -2 * (w + 6), 1, 0), TextXAlignment = Enum.TextXAlignment.Center,
	})
	local plus = UI.Button(row, "+", T.line, function()
		step(1)
	end, { Name = prefix .. "Plus", Size = UDim2.new(0, w, 1, 0), Position = UDim2.new(1, -w, 0, 0), TextSize = 22 })
	return { root = row, minus = minus, plus = plus, value = value }
end

local function clampQty(q: number): number
	return math.clamp(math.floor(q + 0.5), 1, TycoonUI.MaxQty)
end

local function clampPrice(p: number): number
	return math.clamp(math.floor(p + 0.5), TycoonUI.MinPrice, TycoonUI.MaxPrice)
end

-- Preisschritt: 5 % des Richtpreises der Menge, auf 5 gerundet, mindestens 5
local function priceStep(): number
	local base = guidePrice(trade.item) * trade.qty
	return math.max(5, math.floor(base * 0.05 / 5 + 0.5) * 5)
end

local function resetPriceToGuide()
	trade.price = clampPrice(guidePrice(trade.item) * trade.qty)
	trade.priceTouched = false
end

---------------------------------------------------------------- Aufbau
function TycoonUI.Build(page, c)
	ctx = c
	UI, Remote = c.UI, c.Remote
	T = UI.Theme
	refs.page = page
	trade.item = trade.item or TY.ItemList[1]
	resetPriceToGuide()

	-- Status / Rückweg
	local status = UI.Card(page, 1)
	status.Name = "StatusCard"
	UI.Title(status, "Schnelles Spiel", 1)
	refs.where = UI.Label(status, "", { LayoutOrder = 2, Name = "Where" })
	refs.modeHint = UI.Small(status, "", 3)
	refs.modeHint.Name = "ModeHint"
	refs.returnButton = UI.Button(status, "Zurück zur Lobby", T.blue, function()
		Remote.Send("lobby_return")
	end, { Name = "ReturnButton", LayoutOrder = 4 })

	-- Gebäudewahl (ohne Durchlauf)
	local choose = UI.Card(page, 2)
	choose.Name = "ChooseCard"
	UI.Title(choose, "Welches Gebäude baust du aus?", 1)
	UI.Small(choose, "Du startest sofort auf Stufe 1 mit " .. cash(TY.StartCash) .. ". Bargeld gibt es nur in dieser Runde – es wird nie zu Credits. Bis Stufe 5 komplett, dann Rebirth: die fertige Runde bringt dauerhafte Boni in der Open World.", 2)
	refs.types = {}
	for i, typ in ipairs(TY.Types) do
		refs.types[typ] = typeCard(choose, typ, 10 + i)
	end

	-- Kopf des Durchlaufs
	local head = UI.Card(page, 3)
	head.Name = "RunCard"
	refs.runTitle = UI.Title(head, "", 1)
	refs.runTitle.Name = "RunTitle"
	refs.cash = UI.Label(head, "", { Name = "Cash", Font = UI.FontBig, TextSize = 24, LayoutOrder = 2 })
	refs.container = UI.Label(head, "", { Name = "Container", LayoutOrder = 3 })
	local _, fill = UI.Progress(head, T.yellow, 4)
	refs.fill = fill
	refs.rate = UI.Small(head, "", 5)
	refs.rate.Name = "Rate"
	refs.collectButton = UI.Button(head, "Sammeln", T.green, function()
		Remote.Send("tycoon_collect")
	end, { Name = "CollectButton", LayoutOrder = 6, TextSize = 18, Size = UDim2.new(1, 0, 0, 52) })
	refs.boost = UI.Small(head, "", 7)
	refs.boost.Name = "Boost"

	-- Upgrades der aktuellen Stufe
	local ups = UI.Card(page, 4)
	ups.Name = "UpgradesCard"
	refs.upgradesTitle = UI.Title(ups, "Upgrades", 1)
	refs.upgradesInfo = UI.Small(ups, "", 2)
	refs.upgrades = UI.Pool(ups, upgradeRow)

	-- Stufenaufstieg
	local stage = UI.Card(page, 5)
	stage.Name = "StageCard"
	refs.stageTitle = UI.Title(stage, "", 1)
	refs.stageTitle.Name = "StageTitle"
	refs.stageInfo = UI.Label(stage, "", { Name = "StageInfo", LayoutOrder = 2 })
	refs.stageItems = UI.Small(stage, "", 3)
	refs.stageItems.Name = "StageItems"
	refs.stageButton = UI.Button(stage, "Ausbauen", T.blue, function()
		local r = run()
		if r and refs.stageId and refs.stageOk then
			if TycoonUI.StageAction == "tycoon_buy" then
				Remote.Send("tycoon_buy", { id = refs.stageId })
			else
				Remote.Send("tycoon_stage")
			end
		elseif refs.stageId then
			toast(refs.stageReason or "Noch gesperrt.")
		end
	end, { Name = "StageButton", LayoutOrder = 4 })

	-- Lager
	local store = UI.Card(page, 6)
	store.Name = "StorageCard"
	UI.Title(store, "Lager", 1)
	refs.storage = UI.Label(store, "", { Name = "StorageText", LayoutOrder = 2 })
	refs.storageHint = UI.Small(store, "Lager-Upgrades erzeugen Handelsware. Ab Stufe 3 brauchst du Waren für den Stufenaufstieg – oder du handelst mit anderen.", 3)

	-- Handel
	local tr = UI.Card(page, 7)
	tr.Name = "TradeCard"
	UI.Title(tr, "Handel · Marktplatz", 1)
	UI.Small(tr, "Nur Bargeld, nur im Schnellen Spiel. Ein Angebot gilt " .. tostring(TY.TradeTTL) .. " Sekunden.", 2)
	refs.incomingTitle = UI.Label(tr, "Angebote an dich", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 3, Name = "IncomingTitle" })
	refs.incoming = UI.Pool(tr, function(parent, i)
		return offerRow(parent, i, "accept", "Annehmen", T.green)
	end)
	refs.incomingEmpty = UI.Small(tr, "Keine Angebote an dich.", 30)
	refs.incomingEmpty.Name = "IncomingEmpty"
	refs.outgoingTitle = UI.Label(tr, "Deine Angebote", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 31, Name = "OutgoingTitle" })
	local outgoingBox = UI.Frame(tr, { BackgroundTransparency = 1, LayoutOrder = 32 })
	UI.List(outgoingBox, 8)
	refs.outgoing = UI.Pool(outgoingBox, function(parent, i)
		return offerRow(parent, i, "cancel", "Zurückziehen", T.red)
	end)
	refs.outgoingEmpty = UI.Small(tr, "Du hast kein offenes Angebot.", 33)
	refs.outgoingEmpty.Name = "OutgoingEmpty"

	-- Neues Angebot
	UI.Label(tr, "Neues Angebot", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 40 })
	refs.playerButton = UI.Button(tr, "An: – auswählen –", T.card, function()
		trade.listOpen = not trade.listOpen
		TycoonUI.Render(latest)
	end, { Name = "PlayerPick", LayoutOrder = 41, TextXAlignment = Enum.TextXAlignment.Left })
	UI.Padding(refs.playerButton, 12, 0)
	local list = UI.Frame(tr, { BackgroundColor3 = T.bg, LayoutOrder = 42, Visible = false })
	list.Name = "PlayerList"
	UI.Corner(list, 8)
	UI.Padding(list, 6, 6)
	UI.List(list, 4)
	refs.playerList = list
	refs.players = UI.Pool(list, playerRow)
	refs.playersEmpty = UI.Small(list, "Niemand da – andere Spieler müssen im Schnellen Spiel sein.", 99)
	refs.playersEmpty.Name = "PlayersEmpty"

	local items = UI.Frame(tr, { BackgroundTransparency = 1, LayoutOrder = 43, Size = UDim2.new(1, 0, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.None })
	items.Name = "ItemRow"
	UI.List(items, 6, true)
	refs.items = {}
	local n = #TY.ItemList
	for i, item in ipairs(TY.ItemList) do
		refs.items[item] = UI.Button(items, itemName(item), T.line, function()
			trade.item = item
			if not trade.priceTouched then
				resetPriceToGuide()
			end
			TycoonUI.Render(latest)
		end, { Name = "Item_" .. item, LayoutOrder = i, Size = UDim2.new(1 / n, -math.floor(6 * (n - 1) / n), 1, 0), TextSize = 14 })
	end

	refs.qty = stepper(tr, 44, "Qty", function(sign)
		trade.qty = clampQty(trade.qty + sign * (trade.qty >= 20 and 10 or 1))
		if not trade.priceTouched then
			resetPriceToGuide()
		end
		TycoonUI.Render(latest)
	end)
	refs.price = stepper(tr, 45, "Price", function(sign)
		trade.price = clampPrice(trade.price + sign * priceStep())
		trade.priceTouched = true
		TycoonUI.Render(latest)
	end)
	refs.guideButton = UI.Button(tr, "Richtpreis übernehmen", T.card, function()
		resetPriceToGuide()
		TycoonUI.Render(latest)
	end, { Name = "GuideButton", LayoutOrder = 46, TextSize = 14 })
	refs.offerHint = UI.Small(tr, "", 47)
	refs.offerHint.Name = "OfferHint"
	refs.offerButton = UI.Button(tr, "Angebot senden", T.green, function()
		local r = run()
		if not r then
			toast("Ohne Durchlauf kein Handel.")
			return
		end
		if not trade.to then
			toast("Wähle zuerst einen Spieler.")
			trade.listOpen = true
			TycoonUI.Render(latest)
			return
		end
		local have = type(r.storage) == "table" and num(r.storage[trade.item], 0) or 0
		if have < trade.qty then
			toast("Du hast nur " .. tostring(have) .. " × " .. itemName(trade.item) .. " im Lager.")
			return
		end
		Remote.Send("tycoon_trade_offer", { to = trade.to, item = trade.item, qty = clampQty(trade.qty), price = clampPrice(trade.price) })
	end, { Name = "OfferButton", LayoutOrder = 48 })

	-- Rebirth
	local rb = UI.Card(page, 8)
	rb.Name = "RebirthCard"
	UI.Title(rb, "Rebirth", 1)
	refs.rebirthReq = UI.Label(rb, "", { Name = "RebirthReq", LayoutOrder = 2 })
	refs.rebirthPreview = UI.Small(rb, "", 3)
	refs.rebirthPreview.Name = "RebirthPreview"
	refs.rebirthButton = UI.Button(rb, "Rebirth", T.purple, function()
		local r = run()
		if not r or r.canRebirth ~= true then
			toast(refs.rebirthReasonText or "Rebirth noch nicht möglich.")
			return
		end
		UI.Confirm(
			"Rebirth: Dein Gebäude wird zurückgesetzt, das Bargeld verfällt. Dafür bekommst du dauerhaft +"
				.. tostring(TY.Rebirth.boostPct) .. " % Einkommen im Schnellen Spiel und die Runde zählt für den Open-World-Bonus.",
			function()
				Remote.Send("tycoon_rebirth")
			end,
			"Rebirth starten?", "Rebirth!", T.purple
		)
	end, { Name = "RebirthButton", LayoutOrder = 4 })

	-- Abbruch
	local ab = UI.Card(page, 9)
	ab.Name = "AbandonCard"
	UI.Title(ab, "Durchlauf abbrechen", 1)
	UI.Small(ab, "Bricht die Runde ab: Gebäude und Bargeld sind weg, es zählt nicht als fertige Runde. Verlassen ohne Abbruch ist okay – die Runde wartet auf dich.", 2)
	refs.abandonButton = UI.Button(ab, "Abbrechen", T.red, function()
		if not run() then
			return
		end
		UI.Confirm("Wirklich abbrechen? Gebäude und Bargeld dieser Runde gehen verloren.", function()
			Remote.Send("tycoon_abandon")
		end, "Durchlauf abbrechen?", "Ja, abbrechen", T.red)
	end, { Name = "AbandonButton", LayoutOrder = 3 })

	-- Boni (immer sichtbar)
	local bo = UI.Card(page, 10)
	bo.Name = "BonusCard"
	UI.Title(bo, "Deine Boni für die Open World", 1)
	refs.bonusText = UI.Label(bo, "", { Name = "BonusText", LayoutOrder = 2 })
	refs.bonusHint = UI.Small(bo, "Je fertiger Runde eines Typs (Rebirth) wächst der Bonus, bis zu " .. tostring(TY.Bonus.werkstatt.maxRuns) .. " Runden je Typ zählen.", 3)

	TycoonUI.Render(nil)
end

---------------------------------------------------------------- Anzeige
local function renderChoose(s)
	local t = tycoon()
	local runsDone = type(t.runsDone) == "table" and t.runsDone or {}
	for typ, card in pairs(refs.types) do
		local n = num(runsDone[typ], 0)
		local state = pendingChoice == typ and "Wird gebaut …" or "Antippen: sofort Stufe 1"
		if n > 0 then
			state = state .. " · " .. tostring(math.floor(n)) .. " fertige Runde" .. (n == 1 and "" or "n")
		end
		card.state.Text = state
		card.root.BackgroundColor3 = pendingChoice == typ and T.green or T.blue
		card.root:SetAttribute("baseColor", card.root.BackgroundColor3)
		UI.SetEnabled(card.root, inTycoon() and pendingChoice == nil, card.root.BackgroundColor3)
	end
end

local function renderRun(r)
	local b = TY.Buildings[r.building]
	local stage = math.floor(num(r.stage, 1))
	local name = b and b.name or tostring(r.name or r.building)
	refs.runTitle.Text = name .. " · Stufe " .. tostring(stage) .. "/" .. tostring(TY.MaxStage)
	refs.cash.Text = cash(r.cash)
	local capacity = math.max(1, num(r.capacity, 1))
	local container = num(r.container, 0)
	refs.container.Text = "Behälter: " .. MiniLocale.Number(container) .. " / " .. MiniLocale.Number(capacity) .. (container >= capacity and " – voll! Sammeln!" or "")
	refs.container.TextColor3 = container >= capacity and T.yellow or T.text
	UI.SetProgress(refs.fill, container / capacity)
	refs.rate.Text = "Rate: " .. MiniLocale.Decimal(num(r.rate, 0), 2) .. " Bargeld/s" .. (r.complete and stage >= TY.MaxStage and " · Stufe 5 komplett!" or "")
	UI.SetEnabled(refs.collectButton, container > 0, T.green)
	refs.collectButton.Text = container > 0 and ("Sammeln (" .. MiniLocale.Number(container) .. ")") or "Sammeln"
	local boost = num(r.rebirthBoost, 0)
	refs.boost.Text = boost > 0 and ("Rebirth-Boost: +" .. pctText(boost) .. " Einkommen") or "Noch kein Rebirth-Boost."

	-- Upgrades der Stufe
	local st = b and b.Stages[stage] or nil
	local owned = {}
	for _, id in ipairs(type(r.upgrades) == "table" and r.upgrades or {}) do
		owned[id] = true
	end
	local offers = {}
	for _, o in ipairs(type(r.offers) == "table" and r.offers or {}) do
		if type(o) == "table" and type(o.id) == "string" then
			offers[o.id] = o
		end
	end
	local list = st and st.Upgrades or {}
	refs.upgradesTitle.Text = "Upgrades · Stufe " .. tostring(stage)
	local nOwned = 0
	refs.upgrades:Ensure(#list)
	for i, u in ipairs(list) do
		local item = refs.upgrades.items[i]
		item.id = u.id
		item.name.Text = (KIND_TEXT[u.kind] or "") .. ": " .. tostring(u.name)
		item.desc.Text = tostring(u.desc or "")
		item.effect.Text = effectText(u) .. " · " .. cash(u.cost)
		item.button.Name = "Buy_" .. u.id
		local o = offers[u.id]
		if owned[u.id] then
			nOwned += 1
			item.ok = false
			item.reasonText = nil
			item.button.Text = "Gekauft ✓"
			UI.SetEnabled(item.button, false)
			item.name.TextColor3 = T.muted
		else
			local ok = o and o.ok == true or (o == nil and num(r.cash, 0) >= u.cost)
			item.ok = ok
			item.reasonText = o and REASONS[o.reason] or (ok and nil or REASONS.cash)
			item.button.Text = ok and "Kaufen" or (item.reasonText or "Gesperrt")
			UI.SetEnabled(item.button, ok, T.green)
			item.name.TextColor3 = T.text
		end
	end
	refs.upgradesInfo.Text = tostring(nOwned) .. " von " .. tostring(#list) .. " gekauft. Kaufen geht hier oder an den Pads auf deinem Grundstück."

	-- Stufenaufstieg
	if stage < TY.MaxStage and b then
		local nextSt = b.Stages[stage + 1]
		local sid = st and st.stageId or (r.building .. "_stage" .. tostring(stage + 1))
		refs.stageId = sid
		refs.stageTitle.Text = "Stufe " .. tostring(stage + 1) .. " ausbauen"
		refs.stageInfo.Text = "Kosten: " .. cash(nextSt.price) .. ". Voraussetzung: alle Upgrades der Stufe " .. tostring(stage) .. "."
		local lines = {}
		local missing = type(r.missing) == "table" and r.missing or {}
		local storage = type(r.storage) == "table" and r.storage or {}
		for _, item in ipairs(TY.ItemList) do
			local need = nextSt.items[item]
			if need then
				local have = num(storage[item], 0)
				table.insert(lines, itemName(item) .. ": " .. tostring(math.floor(have)) .. "/" .. tostring(need) .. (num(missing[item], 0) > 0 and " (fehlt " .. tostring(math.floor(missing[item])) .. ")" or " ✓"))
			end
		end
		refs.stageItems.Text = #lines > 0 and ("Waren: " .. table.concat(lines, " · ")) or "Keine Waren nötig."
		local o = offers[sid]
		local ok = o and o.ok == true or false
		if o == nil then
			ok = nOwned >= #list and next(missing) == nil and num(r.cash, 0) >= nextSt.price
		end
		refs.stageOk = ok
		refs.stageReason = o and REASONS[o.reason] or (nOwned < #list and REASONS.stage_incomplete or next(missing) ~= nil and REASONS.items or REASONS.cash)
		refs.stageButton.Text = ok and ("Ausbauen: " .. cash(nextSt.price)) or refs.stageReason
		UI.SetEnabled(refs.stageButton, ok, T.blue)
	else
		refs.stageId = nil
		refs.stageOk = false
		refs.stageTitle.Text = "Höchste Stufe erreicht"
		refs.stageInfo.Text = r.complete and "Stufe 5 komplett – jetzt Rebirth!" or "Kauf die letzten Upgrades, dann ist der Rebirth frei."
		refs.stageItems.Text = ""
		refs.stageButton.Text = "Stufe 5/5"
		UI.SetEnabled(refs.stageButton, false)
	end

	-- Lager
	local lines = {}
	local storage = type(r.storage) == "table" and r.storage or {}
	local rates = type(r.items) == "table" and r.items or {}
	for _, item in ipairs(TY.ItemList) do
		local have = num(storage[item], 0)
		local perMin = num(rates[item], 0)
		if have > 0 or perMin > 0 then
			table.insert(lines, itemName(item) .. ": " .. tostring(math.floor(have)) .. (perMin > 0 and (" (+" .. MiniLocale.Decimal(perMin, 1) .. "/Min.)") or ""))
		end
	end
	refs.storage.Text = #lines > 0 and table.concat(lines, "\n") or "Noch leer – ein Lager-Upgrade füllt es."

	-- Rebirth
	local canRebirth = r.canRebirth == true
	refs.rebirthReasonText = REASONS[r.rebirthReason] or nil
	refs.rebirthReq.Text = "Voraussetzung: Stufe " .. tostring(TY.Rebirth.requiresStage) .. " mit allen Upgrades." .. (canRebirth and " Erfüllt!" or (" Noch: " .. (refs.rebirthReasonText or "…") .. "."))
	local nextBoost = math.min(boost + TY.Rebirth.boostPct / 100, TY.Rebirth.capPct / 100)
	local runs = num(tycoon().runsDone and tycoon().runsDone[r.building], 0)
	refs.rebirthPreview.Text = "Nach dem Rebirth: +" .. pctText(nextBoost) .. " Einkommen (jetzt +" .. pctText(boost) .. ", Deckel +" .. tostring(TY.Rebirth.capPct) .. " %) · Open World: " .. bonusText(r.building) .. " – fertige Runden: " .. tostring(math.floor(runs)) .. " → " .. tostring(math.floor(runs) + 1)
	refs.rebirthButton.Text = canRebirth and "Rebirth!" or "Rebirth (gesperrt)"
	UI.SetEnabled(refs.rebirthButton, canRebirth, T.purple)
end

local function renderTrade(r)
	local me = localUserId()
	local offers = tycoon().offers
	if type(offers) ~= "table" then
		offers = {}
	end
	local incoming, outgoing = {}, {}
	for _, o in ipairs(offers) do
		if type(o) == "table" then
			if o.from == me or o.mine == true then
				table.insert(outgoing, o)
			elseif o.to == me or o.incoming == true or o.to == nil then
				table.insert(incoming, o)
			end
		end
	end
	local function describe(o: any, who: string): string
		return tostring(who) .. ": " .. tostring(math.floor(num(o.qty, 0))) .. " × " .. itemName(o.item) .. " für " .. cash(o.price)
	end
	refs.incoming:Ensure(#incoming)
	for i, o in ipairs(incoming) do
		local item = refs.incoming.items[i]
		item.id = o.id
		item.name.Text = describe(o, tostring(o.fromName or ("Spieler " .. tostring(o.from))))
		local can = r and num(r.cash, 0) >= num(o.price, 0)
		item.sub.Text = can and "Du zahlst mit Bargeld, die Ware landet im Lager." or "Dir fehlt Bargeld für dieses Angebot."
		UI.SetEnabled(item.button, can, T.green)
	end
	refs.incomingEmpty.Visible = #incoming == 0
	refs.outgoing:Ensure(#outgoing)
	for i, o in ipairs(outgoing) do
		local item = refs.outgoing.items[i]
		item.id = o.id
		item.name.Text = describe(o, "An " .. tostring(o.toName or ("Spieler " .. tostring(o.to))))
		item.sub.Text = "Wartet auf Antwort."
	end
	refs.outgoingEmpty.Visible = #outgoing == 0

	-- neues Angebot
	local list = candidates()
	local stillThere = false
	for _, pl in ipairs(list) do
		if pl.userId == trade.to then
			stillThere = true
			trade.toName = pl.name
		end
	end
	if not stillThere then
		trade.to, trade.toName = nil, nil
	end
	refs.playerButton.Text = trade.to and ("An: " .. tostring(trade.toName) .. "  ▾") or "An: – Spieler wählen –  ▾"
	refs.playerList.Visible = trade.listOpen
	refs.players:Ensure(#list)
	for i, pl in ipairs(list) do
		local item = refs.players.items[i]
		item.userId, item.name = pl.userId, pl.name
		item.root.Text = pl.name
		UI.SetEnabled(item.root, true, pl.userId == trade.to and T.green or T.card)
	end
	refs.playersEmpty.Visible = #list == 0
	local storage = r and type(r.storage) == "table" and r.storage or {}
	for item, button in pairs(refs.items) do
		local have = math.floor(num(storage[item], 0))
		button.Text = itemName(item) .. " (" .. tostring(have) .. ")"
		UI.SetEnabled(button, true, item == trade.item and T.green or T.line)
	end
	refs.qty.value.Text = "Menge: " .. tostring(trade.qty)
	refs.price.value.Text = "Preis: " .. cash(trade.price)
	local guide = guidePrice(trade.item) * trade.qty
	refs.offerHint.Text = "Richtpreis: " .. cash(guide) .. " (" .. MiniLocale.Number(guidePrice(trade.item)) .. " je Stück)."
	local have = math.floor(num(storage[trade.item], 0))
	local canOffer = r ~= nil and trade.to ~= nil and have >= trade.qty
	UI.SetEnabled(refs.offerButton, canOffer, T.green)
	if r and have < trade.qty then
		refs.offerHint.Text = refs.offerHint.Text .. " Du hast nur " .. tostring(have) .. " × " .. itemName(trade.item) .. "."
	end
end

local function renderBonus()
	local t = tycoon()
	local bonus = type(t.bonus) == "table" and t.bonus or nil
	local lines = {}
	for _, typ in ipairs(TY.Types) do
		local b = TY.Buildings[typ]
		local e = bonus and bonus[typ] or nil
		local runs = e and num(e.runs, 0) or num(type(t.runsDone) == "table" and t.runsDone[typ], 0)
		local pct = e and num(e.pct, 0) or math.min(runs, TY.Bonus[typ].maxRuns) * TY.Bonus[typ].step * 100
		local sign = pct <= 0 and "" or (typ == "autohaus" and "−" or "+")
		table.insert(lines, (b and b.name or typ) .. ": " .. tostring(math.floor(runs)) .. " Runden → " .. sign .. MiniLocale.Decimal(pct, 1) .. " % " .. tostring(TY.Bonus[typ].text))
	end
	refs.bonusText.Text = table.concat(lines, "\n")
end

function TycoonUI.Render(s)
	if type(s) == "table" then
		latest = s
	end
	if not refs.where then
		return
	end
	local mode = latest and latest.mode or nil
	local here = inTycoon()
	local r = run()
	if r then
		pendingChoice = nil
	end
	refs.where.Text = r and ("Dein Durchlauf: " .. tostring(r.name or (TY.Buildings[r.building] and TY.Buildings[r.building].name) or r.building) .. ", Stufe " .. tostring(r.stage) .. "/" .. tostring(TY.MaxStage) .. ".")
		or "Kein Durchlauf – wähle unten ein Gebäude."
	if not here then
		refs.modeHint.Text = "Du bist gerade " .. (mode == "lobby" and "in der Lobby" or "in der Open World") .. ". Das Schnelle Spiel läuft auf dem Tycoon-Gelände (Lobby → „Schnelles Spiel“). Deine Runde wartet dort auf dich."
	elseif latest and latest.simulated == true then
		refs.modeHint.Text = GameConfig.SimulationNotice
	else
		refs.modeHint.Text = ""
	end
	refs.modeHint.Visible = refs.modeHint.Text ~= ""
	refs.returnButton.Visible = mode ~= "lobby"

	local page = refs.page
	local function show(name: string, visible: boolean)
		local card = page:FindFirstChild(name)
		if card then
			card.Visible = visible
		end
	end
	show("ChooseCard", r == nil)
	show("RunCard", r ~= nil)
	show("UpgradesCard", r ~= nil)
	show("StageCard", r ~= nil)
	show("StorageCard", r ~= nil)
	show("TradeCard", r ~= nil and here)
	show("RebirthCard", r ~= nil)
	show("AbandonCard", r ~= nil)
	if r then
		renderRun(r)
		renderTrade(r)
	else
		renderChoose(latest)
	end
	renderBonus()
end

function TycoonUI.OnShow()
	TycoonUI.Render(latest)
end

---------------------------------------------------------------- Marktplatz-Tafel (nur Client)
local function marketLabel()
	local zone = workspace:FindFirstChild("Tycoon")
	local markt = zone and zone:FindFirstChild("Markt")
	local board = markt and markt:FindFirstChild("Tafel")
	local gui = board and board:FindFirstChild("MarketScreen")
	return gui and gui:FindFirstChild("Offers") or nil
end

-- Text der Tafel aus der Angebotsliste (höchstens 6 Zeilen)
function TycoonUI.MarketText(offers: any): string
	if type(offers) ~= "table" or #offers == 0 then
		return "Angebote der Spieler (Bargeld): noch keine"
	end
	local lines = {}
	for i, o in ipairs(offers) do
		if i > 6 then
			table.insert(lines, "… und " .. tostring(#offers - 6) .. " weitere")
			break
		end
		if type(o) == "table" then
			local from = tostring(o.fromName or ("Spieler " .. tostring(o.from)))
			local to = o.toName and (" → " .. tostring(o.toName)) or ""
			table.insert(lines, from .. to .. ": " .. tostring(math.floor(num(o.qty, 0))) .. " × " .. itemName(o.item) .. " für " .. MiniLocale.Number(num(o.price, 0)))
		end
	end
	return "Angebote der Spieler (Bargeld):\n" .. table.concat(lines, "\n")
end

function TycoonUI.UpdateMarket(offers: any)
	marketOffers = type(offers) == "table" and offers or {}
	local label = marketLabel()
	if label then
		label.Text = TycoonUI.MarketText(marketOffers)
	end
end

-- mini_notice { kind = "tycoon_market" (offers) | "tycoon_stage" (event = start|upgrade|stage|abandon) | "trade" (event, Angebot)
--              | "tycoon" (event = rebirth|abandoned, optional) }
function TycoonUI.OnNotice(data)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "tycoon_market" then
		TycoonUI.UpdateMarket(data.offers)
	elseif kind == "tycoon_stage" then
		-- Server-Toasts (Start, Upgrade, Stufe, Abbruch) zeigt 2.4.0 selbst; hier nur der Zustand
		if data.event == "abandon" or data.event == "start" then
			pendingChoice = nil
		end
	elseif kind == "trade" then
		-- Angebot/Annahme/Rückzug: Toasts kommen vom Server, die Liste aus dem nächsten Snapshot
		if data.event == "offered" and trade.to ~= nil and data.from == localUserId() then
			trade.listOpen = false
		end
	elseif kind == "tycoon" then
		if data.event == "rebirth" then
			pendingChoice = nil
			toast("Rebirth geschafft! Boost jetzt +" .. pctText(num(data.boost, 0)) .. " Einkommen.")
		elseif data.event == "abandoned" then
			pendingChoice = nil
		end
	end
	if UI and UI.IsOpen and UI.CurrentTab == "tycoon" then
		TycoonUI.Render(latest)
	end
end

-- Für Tests: aktueller Zustand des Angebotsformulars
function TycoonUI.TradeState()
	return { to = trade.to, item = trade.item, qty = trade.qty, price = trade.price }
end

return TycoonUI
