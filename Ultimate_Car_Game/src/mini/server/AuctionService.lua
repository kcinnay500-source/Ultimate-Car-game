-- AuctionService: Auktionshaus auf dem Server (PHASE2_CONTRACT §1, §3, §4, §6).
-- * NPC-Versteigerungen: serverweiter Zeitplan (ein Sondermodell nach dem anderen, Pause dazwischen), 2–3 NPC-Bieter
--   mit festen, offen beschriebenen Limits (AuctionRules). Neue Lose nur, solange Spieler auf dem Server sind.
-- * Spieler-Auktionen: eigene Autos an Spieler auf demselben Server (Einliefern sperrt das Auto, locked = true).
-- * Zuschlag im globalen Tick: nächsthöheres gültiges Gebot (Guthaben, Garage, Level, schreibbares Profil erneut
--   geprüft); wartet, solange ein beteiligtes Profil transacting ist (höchstens SettleWaitMax, dann nächstes Gebot bzw.
--   Abbruch). Fällt das HÖCHSTE Gebot weg, läuft das Los ReopenSeconds weiter (Scheingebot-Schutz, AuctionRules.Reopen),
--   der Bieter darf bei "nicht gedeckt" DropBanSeconds nicht bieten. Beim Bieten zählt nur das freie Guthaben.
--   Auto + Geld wechseln in einem Server-Schritt (AuctionRules.Handover), dann wird die Übergabe ins Auktionsbuch
--   geschrieben (api.recordTransfer, AuctionLedger) und danach beide Profile gespeichert. Speichert nur eines, gleicht
--   das Laden über das Auktionsbuch ab (kein doppeltes Auto, keine Credits aus dem Nichts).
-- * Verkäufer verlässt den Server: Auktion abgebrochen, Auto entsperrt (vor dem letzten Speichern). Bieter verlässt den
--   Server: seine Gebote fallen weg.
-- * Öffentlicher Zustand an alle Spieler des Servers: mini_notice auction_update (gedrosselt), dazu auction_won /
--   auction_sold an Käufer/Verkäufer. In-World-Bildschirm City…AuctionScreen (Labels Title, Lot, Bid, Time), falls vorhanden.
--
-- Schnittstelle (Verkabelung in MiniService):
--   AuctionService.Register(Actions, api)   Aktionen mini_auction_bid / _consign / _cancel
--   AuctionService.OnJoin(ms)               Mini.OnJoin (Sitzung bekannt machen)
--   AuctionService.Hello(ms)                Mini.Hello und mini_sync (Zustand erneut senden)
--   AuctionService.OnLeave(ms)              Mini.OnLeave, VOR P.Save (Verkäufer-Lose abbrechen, Gebote entfernen)
--   AuctionService.Tick(now)                global; darf je Sitzung aus Mini.Tick kommen (Mehrfachaufrufe < 0,2 s entfallen)
--   AuctionService.SnapshotFields(d)        Snapshot-Feld `auction` = { won, sold }
-- api (MiniService): now, toast, notice, dirty, writable (vorhanden) und neu:
--   api.changed(ms)          Geld/Autos außerhalb von request() geändert: ctx.changed(ms.p) (Revision + Push)
--   api.save(ms)             sofort speichern (P.Save(ms.p.profile), wartet auf ein laufendes Speichern)
--   api.releaseCar(ms, id)   optional: gespawntes Auto abbauen (CarService.ReleaseCar)
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local AuctionRules = require(MiniShared:WaitForChild("AuctionRules"))
local CarRules = require(MiniShared:WaitForChild("CarRules"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))

local AuctionService = {}

local TICK_MIN = 0.2 -- mehrere Aufrufe im selben 0,5-s-Tick zählen einmal
local BROADCAST_MIN = 0.25 -- auction_update höchstens 4×/s
local SCREEN_INTERVAL = 1
local SCREEN_SEARCH = 15

local api
local S -- Zustand des Auktionshauses (AuctionService.Reset)

local TEXT = {
	gone = "Diese Auktion gibt es nicht mehr.",
	not_found = "Auto nicht gefunden.",
	locked = "Dieses Auto ist schon in einer Auktion.",
	duration = "Bitte eine Laufzeit von 2, 5 oder 10 Minuten wählen.",
	start = "Dieses Startgebot ist nicht (mehr) möglich. Bitte neu wählen.",
	per_seller = "Du hast schon ein Auto in der Auktion.",
	full = "Das Auktionshaus ist gerade voll. Versuche es gleich noch einmal.",
	wait = "Bitte einen Moment warten.",
	not_yours = "Diese Auktion gehört dir nicht.",
	has_bids = "Es gibt schon Gebote – die Auktion läuft bis zum Ende.",
	ended = "Diese Auktion ist schon beendet.",
}
-- Bieter fällt beim Zuschlag heraus (Toast an ihn); %s = Modellname
local SKIP_TEXT = {
	money = "Dein Gebot für den %s war beim Zuschlag nicht gedeckt und wurde gestrichen. Du kannst 10 Minuten lang nicht bieten.",
	garage = "Deine Garage war beim Zuschlag voll – dein Gebot für den %s wurde gestrichen.",
	level = "Für den %s fehlt dir das nötige Level – dein Gebot wurde gestrichen.",
	busy = "Dein Kauf wurde gerade gespeichert – dein Gebot für den %s wurde gestrichen.",
	writable = "Dein Profil wird gerade nicht gespeichert – dein Gebot für den %s wurde gestrichen.",
}
local CANCEL_TEXT = {
	seller_left = "Der Verkäufer hat den Server verlassen.",
	seller_busy = "Der Verkäufer war zu lange beschäftigt.",
	seller_writable = "Das Profil des Verkäufers wird nicht gespeichert.",
	car = "Das Auto ist nicht mehr verfügbar.",
	seller = "Der Verkäufer hat sie zurückgezogen.",
}

local function newState(seed)
	return {
		sessions = {}, -- [userId] = ms
		lots = {}, -- [id] = lot
		order = {}, -- Los-Ids in Anlage-Reihenfolge
		serial = 0,
		npcSerial = 0,
		seed = seed or (os.time() % 1000003 + 1),
		npcNext = nil, -- { at, model }
		lastNpcModel = nil,
		lastTickAt = -math.huge,
		lastConsign = {}, -- [userId] = Zeit
		banned = {}, -- [userId] = Zeit, bis zu der nicht geboten werden darf (Höchstgebot war nicht gedeckt)
		dirty = true,
		lastBroadcast = -math.huge,
		screen = { lastFind = -math.huge, lastAt = -math.huge, labels = nil, gui = nil },
		warned = {},
	}
end
S = newState()

---------------------------------------------------------------- Hilfen
local function finite(v)
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function now()
	if api and api.now then
		return api.now()
	end
	return workspace:GetServerTimeNow()
end

local function warnOnce(key, msg)
	if not S.warned[key] then
		S.warned[key] = true
		warn("[Auktion] " .. msg)
	end
end

local function uidOf(ms)
	return ms and (ms.userId or (ms.player and ms.player.UserId)) or nil
end

local function nameOf(ms)
	local pl = ms and ms.player
	local n = pl and pl.DisplayName
	if type(n) ~= "string" or n == "" then
		n = pl and pl.Name
	end
	return type(n) == "string" and n ~= "" and n or ("Spieler " .. tostring(uidOf(ms)))
end

local function profileOf(ms)
	return ms and ms.p and ms.p.profile or nil
end

local function dataOf(ms)
	local prof = profileOf(ms)
	return prof and prof.data or nil
end

-- Sitzung endet gerade (PlayerRemoving/BindToClose) oder der Spieler ist weg
local function gone(ms)
	return ms == nil or (ms.p ~= nil and ms.p.closing == true) or (ms.player ~= nil and ms.player.Parent == nil)
end

-- Robux-Kauf läuft (Profiles.GrantCredits): Geld nicht anfassen
local function busy(ms)
	local prof = profileOf(ms)
	return prof ~= nil and (prof.transacting == true or prof.receiptPending ~= nil)
end

local function writable(ms)
	if api and api.writable then
		return api.writable(ms) == true
	end
	local prof = profileOf(ms)
	return prof ~= nil and prof.writable == true
end

local function toast(ms, text)
	if api and ms and not gone(ms) and type(text) == "string" and text ~= "" then
		api.toast(ms, text)
	end
end

local function notice(ms, kind, data)
	if api and ms and not gone(ms) then
		api.notice(ms, kind, data or {})
	end
end

local function dirty(ms)
	if api and ms and api.dirty then
		api.dirty(ms)
	end
end

-- Geld/Autos außerhalb von request() geändert: 2.4.0-Revision + Push (sonst nur Minispiel-Snapshot)
local function changed(ms)
	if not api or not ms or gone(ms) then
		return
	end
	if api.changed then
		local ok, err = pcall(api.changed, ms)
		if not ok then
			warnOnce("changed", "api.changed: " .. tostring(err))
		end
	else
		warnOnce("changed_missing", "api.changed fehlt (nur Minispiel-Snapshot aktualisiert)")
		dirty(ms)
	end
end

-- Sofort speichern (nach der Übergabe beide Profile)
local function save(ms)
	if not api or not ms then
		return
	end
	if api.save then
		local ok, err = pcall(api.save, ms)
		if not ok then
			warn("[Auktion] Speichern: " .. tostring(err))
		end
	else
		warnOnce("save_missing", "api.save fehlt: Übergabe wird erst mit dem nächsten Speichern gesichert")
	end
end

-- Übergabe ins Auktionsbuch schreiben (darf warten), danach beide Profile speichern. Ohne api.recordTransfer
-- (Tests, Studio) nur speichern.
local function recordAndSave(seller, buyer, transfer)
	task.spawn(function()
		if api and api.recordTransfer and transfer then
			local ok, err = pcall(api.recordTransfer, transfer)
			if not ok then
				warn("[Auktion] Auktionsbuch: " .. tostring(err))
			end
		end
		save(seller)
		save(buyer)
	end)
end

local function credits(n)
	return MiniLocale.Credits(n)
end

-- Sitzung bekannt machen (auch, falls OnJoin fehlte)
local function track(ms)
	local uid = uidOf(ms)
	if uid and S.sessions[uid] ~= ms then
		S.sessions[uid] = ms
		ms.auctionSent = nil
	end
end

local function hasSessions()
	for _, ms in pairs(S.sessions) do
		if not gone(ms) then
			return true
		end
	end
	return false
end

local function isLive(lot)
	return lot.state == "open" or lot.state == "closing"
end

local function addLot(lot)
	S.lots[lot.id] = lot
	table.insert(S.order, lot.id)
	S.dirty = true
end

local function countLots(pred)
	local n = 0
	for _, id in ipairs(S.order) do
		local lot = S.lots[id]
		if lot and isLive(lot) and pred(lot) then
			n += 1
		end
	end
	return n
end

local function carCount(d)
	local g = d and d.games
	return g and type(g.cars) == "table" and #g.cars or 0
end

---------------------------------------------------------------- Öffentlicher Zustand
function AuctionService.PublicState(t)
	t = t or now()
	local lots = {}
	for _, id in ipairs(S.order) do
		local lot = S.lots[id]
		if lot then
			table.insert(lots, AuctionRules.LotView(lot, t))
		end
	end
	local nextView = S.npcNext and AuctionRules.NextView(S.npcNext.model, S.npcNext.at) or nil
	return { now = t, lots = lots, next = nextView, rules = AuctionRules.RulesView() }
end

local function ready(ms)
	return ms.greeted ~= false -- MiniService: erst nach 'hello' hört der Client zu
end

local function sendTo(ms, view)
	local data = table.clone(view)
	data.you = { userId = uidOf(ms) or 0, writable = writable(ms) }
	notice(ms, "auction_update", data)
	ms.auctionSent = view.now
end

-- Sendet den öffentlichen Zustand: an alle bei Änderung (gedrosselt), an neue Sitzungen sofort.
local function flushPublic(t, force)
	local due = S.dirty and (force or t - S.lastBroadcast >= BROADCAST_MIN)
	local view
	for _, ms in pairs(S.sessions) do
		if not gone(ms) and ready(ms) and (due or ms.auctionSent == nil) then
			view = view or AuctionService.PublicState(t)
			sendTo(ms, view)
		end
	end
	if due then
		S.dirty = false
		S.lastBroadcast = t
		S.screen.force = true
	end
end

---------------------------------------------------------------- In-World-Bildschirm (City…AuctionScreen)
local function findScreen(t)
	local sc = S.screen
	if sc.gui and sc.gui.Parent then
		return sc.labels
	end
	sc.gui, sc.labels = nil, nil
	if t - sc.lastFind < SCREEN_SEARCH then
		return nil
	end
	sc.lastFind = t
	local city = workspace:FindFirstChild("City")
	local gui = city and city:FindFirstChild("AuctionScreen", true)
	if not gui then
		return nil
	end
	local labels = {}
	for _, key in ipairs({ "Title", "Lot", "Bid", "Time" }) do
		local l = gui:FindFirstChild(key, true)
		if l and (l:IsA("TextLabel") or l:IsA("TextButton") or l:IsA("TextBox")) then
			labels[key] = l
		end
	end
	sc.gui, sc.labels = gui, labels
	return labels
end

-- Hauptlos für den Bildschirm: NPC-Los (laufend oder eben beendet), sonst die neueste laufende Spieler-Auktion
local function featured()
	local npc, player
	for i = #S.order, 1, -1 do
		local lot = S.lots[S.order[i]]
		if lot then
			if lot.kind == "npc" and not npc then
				npc = lot
			elseif lot.kind == "player" and not player and isLive(lot) then
				player = lot
			end
		end
	end
	if npc and (isLive(npc) or not player) then
		return npc
	end
	return player or npc
end

function AuctionService.ScreenTexts(t)
	t = t or now()
	local lot = featured()
	if lot then
		local title = (lot.kind == "npc" and "SONDERMODELL" or "SPIELER-AUKTION") .. " · LOS " .. string.format("%03d", lot.id)
		local lotText = lot.name .. (lot.kind == "player" and (" · von " .. lot.sellerName) or (" · ab Level " .. lot.level))
		local top = AuctionRules.Top(lot)
		local bid, time
		if lot.state == "sold" and lot.result then
			bid = "Zuschlag: " .. credits(lot.result.amount) .. " · " .. lot.result.name
		elseif lot.state == "unsold" then
			bid = "Nicht verkauft"
		elseif lot.state == "canceled" then
			bid = "Abgebrochen"
		elseif top then
			bid = "Gebot: " .. credits(top.amount) .. " · " .. top.name
		else
			bid = "Startgebot: " .. credits(lot.start)
		end
		if lot.state == "open" then
			time = "Restzeit " .. AuctionRules.Clock(lot.endsAt - t)
		elseif lot.state == "closing" then
			time = "Zuschlag folgt …"
		elseif S.npcNext and not isLive(lot) then
			time = "Nächstes Los in " .. AuctionRules.Clock(S.npcNext.at - t)
		else
			time = "Beendet"
		end
		return title, lotText, bid, time
	end
	local nx = S.npcNext and AuctionRules.NextView(S.npcNext.model, S.npcNext.at)
	if nx then
		return "AUKTIONSHAUS", "Als Nächstes: " .. nx.name, "Startgebot: " .. credits(nx.start),
			"Beginn in " .. AuctionRules.Clock(nx.at - t)
	end
	return "AUKTIONSHAUS", "Gerade keine Versteigerung", "Einliefern am Schalter rechts", ""
end

local function updateScreen(t)
	local sc = S.screen
	if t - sc.lastAt < SCREEN_INTERVAL and not sc.force then
		return
	end
	sc.lastAt = t
	sc.force = false
	local labels = findScreen(t)
	if not labels then
		return
	end
	local title, lotText, bid, time = AuctionService.ScreenTexts(t)
	for key, text in pairs({ Title = title, Lot = lotText, Bid = bid, Time = time }) do
		local l = labels[key]
		if l and l.Parent and l.Text ~= text then
			l.Text = text
		end
	end
end

---------------------------------------------------------------- Lose beenden
local function scheduleNext(at)
	S.npcSerial += 1
	local model = AuctionRules.PickNpcModel(S.npcSerial, S.seed, S.lastNpcModel)
	S.lastNpcModel = model
	S.npcNext = model and { at = at, model = model } or nil
end

local function notifyBidders(lot, text, except)
	local told = {}
	for _, b in ipairs(lot.bids) do
		if not b.npc and b.userId ~= except and not told[b.userId] then
			told[b.userId] = true
			toast(S.sessions[b.userId], text)
		end
	end
end

-- Spieler-Auktion abbrechen (sellerMs darf nil sein: dann entsperrt CarRules.Load beim nächsten Laden)
local function cancelLot(lot, sellerMs, t, reason)
	if not AuctionRules.Cancel(lot, dataOf(sellerMs), t, reason) then
		return false
	end
	S.dirty = true
	if sellerMs then
		dirty(sellerMs)
	end
	local why = CANCEL_TEXT[reason] or ""
	notifyBidders(lot, "Die Auktion für den " .. lot.name .. " wurde abgebrochen. " .. why, lot.sellerId)
	if sellerMs and reason ~= "seller" and reason ~= "seller_left" then
		toast(sellerMs, "Deine Auktion für den " .. lot.name .. " wurde abgebrochen. " .. why .. " Das Auto ist wieder frei.")
	end
	return true
end

-- Prüfung eines Gebots beim Zuschlag (für AuctionRules.PickWinner)
local function checker(lot, t)
	return function(b)
		local bms = S.sessions[b.userId]
		if not bms or gone(bms) then
			return "gone"
		end
		local verdict
		if busy(bms) then
			if t - (lot.closingSince or t) < AuctionRules.SettleWaitMax then
				return "wait"
			end
			verdict = "busy"
		elseif lot.kind == "player" and not writable(bms) then
			verdict = "writable"
		else
			verdict = AuctionRules.BuyerCheck(dataOf(bms), lot, b.amount)
		end
		if verdict ~= "ok" and SKIP_TEXT[verdict] then
			toast(bms, string.format(SKIP_TEXT[verdict], lot.name))
		end
		return verdict
	end
end

local function lotList()
	local list = {}
	for _, id in ipairs(S.order) do
		local lot = S.lots[id]
		if lot then
			table.insert(list, lot)
		end
	end
	return list
end

-- Höchstgebot beim Zuschlag weggefallen: Los läuft weiter (AuctionRules.Reopen), bei "nicht gedeckt" Bietsperre
local function reopen(lot, bid, reason, t)
	if not AuctionRules.Reopen(lot, bid.userId, t) then
		return false
	end
	if reason == "money" then
		S.banned[bid.userId] = t + AuctionRules.DropBanSeconds
	end
	S.dirty = true
	local text = "Das Höchstgebot für den " .. lot.name .. " war beim Zuschlag nicht gültig. Die Auktion läuft noch "
		.. AuctionRules.ReopenSeconds .. " Sekunden – jetzt kannst du nachbieten!"
	notifyBidders(lot, text, bid.userId)
	if lot.kind == "player" then
		toast(S.sessions[lot.sellerId], text)
	end
	return true
end

local function settlePlayerLot(lot, t)
	local seller = S.sessions[lot.sellerId]
	if not seller or gone(seller) then
		cancelLot(lot, nil, t, "seller_left")
		return
	end
	if busy(seller) then
		if t - (lot.closingSince or t) < AuctionRules.SettleWaitMax then
			return -- warten, bis der Robux-Kauf des Verkäufers gespeichert ist
		end
		cancelLot(lot, seller, t, "seller_busy")
		return
	end
	if not writable(seller) then
		cancelLot(lot, seller, t, "seller_writable")
		return
	end
	local sd = dataOf(seller)
	local car = CarRules.Find(sd, lot.carId)
	if not car or not car.locked then
		cancelLot(lot, seller, t, "car")
		return
	end
	local winner, wait, dropped, why = AuctionRules.PickWinner(lot, checker(lot, t), true)
	if wait == "reopen" then
		reopen(lot, dropped, why, t)
		return
	end
	if wait then
		return
	end
	if not winner then
		CarRules.SetLocked(sd, lot.carId, false)
		AuctionRules.Finish(lot, "unsold", t, nil, #lot.bids > 0 and "invalid" or "nobids")
		dirty(seller)
		toast(seller, "Kein gültiges Gebot für deinen " .. lot.name .. ". Das Auto ist wieder frei.")
		S.dirty = true
		return
	end
	local buyer = S.sessions[winner.userId]
	local ok, info = AuctionRules.Handover(lot, winner, dataOf(buyer), sd, t)
	if not ok then
		lot.skipped[winner.userId] = info or "invalid" -- nächster Tick: nächstes Gebot
		return
	end
	-- Übergabe ist geschehen (ein Schritt): Auktionsbuch, dann beide Profile speichern; danach melden
	recordAndSave(seller, buyer, info.transfer)
	changed(seller)
	changed(buyer)
	S.dirty = true
	notice(buyer, "auction_won", {
		lot = lot.id, model = lot.model, name = lot.name, amount = info.amount, carId = info.car.id, seller = lot.sellerName,
	})
	notice(seller, "auction_sold", {
		lot = lot.id, model = lot.model, name = lot.name, amount = info.amount, fee = info.fee, payout = info.payout,
		buyer = winner.name,
	})
	toast(buyer, "Zuschlag! Der " .. lot.name .. " gehört jetzt dir (−" .. credits(info.amount) .. "). Du findest ihn unter „Meine Autos“.")
	toast(seller, "Verkauft: dein " .. lot.name .. " an " .. winner.name .. " für " .. credits(info.amount)
		.. ". Gutschrift nach 5 % Gebühr: " .. credits(info.payout) .. ".")
	notifyBidders(lot, "Auktion beendet: Der " .. lot.name .. " ging an " .. winner.name .. " für " .. credits(info.amount) .. ".", winner.userId)
end

local function settleNpcLot(lot, t)
	local winner, wait, dropped, why = AuctionRules.PickWinner(lot, checker(lot, t), true)
	if wait == "reopen" then
		reopen(lot, dropped, why, t)
		return
	end
	if wait then
		return
	end
	if not winner then
		AuctionRules.Finish(lot, "unsold", t, nil, #lot.bids > 0 and "invalid" or "nobids")
	elseif winner.npc then
		AuctionRules.Finish(lot, "sold", t, { userId = 0, name = winner.name, amount = winner.amount, npc = true })
		notifyBidders(lot, "Zuschlag an " .. winner.name .. " für " .. credits(winner.amount) .. ". Beim nächsten Los klappt es vielleicht!")
	else
		local buyer = S.sessions[winner.userId]
		local ok, info = AuctionRules.GrantNpcLot(lot, winner, dataOf(buyer), t)
		if not ok then
			lot.skipped[winner.userId] = info or "invalid"
			return
		end
		save(buyer)
		changed(buyer)
		notice(buyer, "auction_won", { lot = lot.id, model = lot.model, name = lot.name, amount = info.amount, carId = info.car.id, seller = "" })
		toast(buyer, "Zuschlag! Das Sondermodell " .. lot.name .. " gehört jetzt dir (−" .. credits(info.amount) .. "). Du findest es unter „Meine Autos“.")
		notifyBidders(lot, "Zuschlag an " .. winner.name .. " für " .. credits(info.amount) .. ".", winner.userId)
	end
	S.dirty = true
	scheduleNext(t + AuctionRules.Npc.breakSeconds)
end

-- Zuschlag eines Loses im Zustand "closing". Mehrfachaufrufe sind harmlos (beendete Lose bleiben beendet).
function AuctionService.Settle(lot, t)
	if not lot or lot.state ~= "closing" then
		return false
	end
	t = t or now()
	if lot.kind == "player" then
		settlePlayerLot(lot, t)
	else
		settleNpcLot(lot, t)
	end
	return lot.state ~= "closing"
end

---------------------------------------------------------------- Ablauf je Tick
local function outbid(prev, lot, bid)
	if prev and not prev.npc and prev.userId ~= bid.userId then
		toast(S.sessions[prev.userId], "Überboten: " .. bid.name .. " bietet " .. credits(bid.amount) .. " für den " .. lot.name .. ".")
	end
end

local function stepLot(lot, t)
	if lot.state == "open" then
		local i, amount = AuctionRules.NpcDecide(lot, t)
		if i then
			local prev = AuctionRules.Top(lot)
			local bid = AuctionRules.PlaceBid(lot, 0, lot.npcs[i].name, amount, t, i)
			outbid(prev, lot, bid)
			S.dirty = true
		end
		if t >= lot.endsAt then
			lot.state = "closing"
			lot.closingSince = t
			S.dirty = true
		end
	end
	if lot.state == "closing" then
		AuctionService.Settle(lot, t)
	end
end

local function schedule(t)
	if not S.npcNext and countLots(function(l)
		return l.kind == "npc"
	end) == 0 then
		scheduleNext(t + AuctionRules.Npc.firstDelay)
	end
	local nx = S.npcNext
	if not nx or t < nx.at or not hasSessions() then
		return
	end
	if countLots(function(l)
		return l.kind == "npc"
	end) > 0 then
		return
	end
	S.serial += 1
	local lot = AuctionRules.NewNpcLot(S.serial, nx.model, S.seed, t)
	S.npcNext = nil
	if lot then
		addLot(lot)
	else
		scheduleNext(t + AuctionRules.Npc.breakSeconds)
	end
end

local function cleanup(t)
	for i = #S.order, 1, -1 do
		local id = S.order[i]
		local lot = S.lots[id]
		if not lot or (not isLive(lot) and t - (lot.endedAt or t) >= AuctionRules.ResultSeconds) then
			S.lots[id] = nil
			table.remove(S.order, i)
			S.dirty = true
		end
	end
end

function AuctionService.Tick(t)
	if not api then
		return
	end
	t = finite(t) and t or now()
	if t >= S.lastTickAt and t - S.lastTickAt < TICK_MIN then
		return
	end
	S.lastTickAt = t
	local ok, err = pcall(schedule, t)
	if not ok then
		warn("[Auktion] Zeitplan: " .. tostring(err))
	end
	for _, id in ipairs(table.clone(S.order)) do
		local lot = S.lots[id]
		if lot then
			local ok2, err2 = pcall(stepLot, lot, t)
			if not ok2 then
				warn("[Auktion] Los " .. tostring(id) .. ": " .. tostring(err2))
			end
		end
	end
	cleanup(t)
	flushPublic(t)
	local ok3, err3 = pcall(updateScreen, t)
	if not ok3 then
		warnOnce("screen", "Bildschirm: " .. tostring(err3))
	end
end

---------------------------------------------------------------- Sitzungen
function AuctionService.OnJoin(ms)
	if ms then
		track(ms)
	end
end

-- Client hört zu ('hello' / mini_sync): Zustand erneut senden
function AuctionService.Hello(ms)
	if not ms then
		return
	end
	track(ms)
	ms.auctionSent = nil
	flushPublic(now())
end

-- Vor P.Save(release): Verkäufer-Lose abbrechen (Auto entsperren, landet so im letzten Speichern),
-- Gebote des Spielers entfernen. Mehrfachaufruf (BindToClose + PlayerRemoving) ist harmlos.
function AuctionService.OnLeave(ms)
	local uid = uidOf(ms)
	if not uid then
		return
	end
	local current = S.sessions[uid]
	if current and current ~= ms then
		return -- eine neuere Sitzung desselben Spielers ist schon da
	end
	S.sessions[uid] = nil
	local t = now()
	for _, id in ipairs(S.order) do
		local lot = S.lots[id]
		if lot and isLive(lot) then
			if lot.kind == "player" and lot.sellerId == uid then
				cancelLot(lot, ms, t, "seller_left")
			elseif AuctionRules.RemoveBidder(lot, uid, t) > 0 then
				S.dirty = true
			end
		end
	end
	flushPublic(t)
end

function AuctionService.SnapshotFields(d)
	return AuctionRules.SnapshotFields(d)
end

---------------------------------------------------------------- Aktionen
function AuctionService.Register(Actions, a)
	api = a

	-- mini_auction_bid {lot, amount}: Betrag = Absicht; Mindestgebot, Höchstgrenze, Guthaben prüft der Server
	Actions.Register("mini_auction_bid", function(ms, data, d, t)
		track(ms)
		local lot = S.lots[data.lot]
		if not lot then
			toast(ms, TEXT.gone)
			return
		end
		local uid = uidOf(ms)
		local bannedUntil = S.banned[uid]
		if bannedUntil and t < bannedUntil then
			toast(ms, "Dein letztes Höchstgebot war beim Zuschlag nicht gedeckt. Bieten ist wieder in "
				.. AuctionRules.Clock(bannedUntil - t) .. " Min. möglich.")
			return
		end
		local bidder = {
			userId = uid, level = finite(d.level) and d.level or 1, money = d.money, cars = carCount(d),
			writable = writable(ms), committed = AuctionRules.Committed(lotList(), uid, lot.id),
			partner = lot.kind == "player" and AuctionRules.RecentPartner(d, lot.sellerId, t),
		}
		local ok, err = AuctionRules.CheckBid(lot, bidder, data.amount, t)
		if not ok then
			toast(ms, err)
			return
		end
		local prev = AuctionRules.Top(lot)
		local bid = AuctionRules.PlaceBid(lot, bidder.userId, nameOf(ms), data.amount, t)
		outbid(prev, lot, bid)
		toast(ms, "Gebot abgegeben: " .. credits(bid.amount) .. " für den " .. lot.name .. ". Bezahlt wird erst beim Zuschlag.")
		S.dirty = true
		flushPublic(t)
	end)

	-- mini_auction_consign {id, start, duration}: eigenes Auto einliefern (sperrt es)
	Actions.Register("mini_auction_consign", function(ms, data, d, t)
		track(ms)
		local uid = uidOf(ms)
		if not writable(ms) then
			toast(ms, AuctionRules.Text.writable)
			return
		end
		local car = CarRules.Find(d, data.id)
		if not car then
			toast(ms, TEXT.not_found)
			return
		end
		if car.locked then
			toast(ms, TEXT.locked)
			return
		end
		local duration = AuctionRules.ValidDuration(data.duration)
		if not duration then
			toast(ms, TEXT.duration)
			return
		end
		local start = AuctionRules.ValidStart(car, data.start)
		if not start then
			toast(ms, TEXT.start)
			return
		end
		if countLots(function(l)
			return l.kind == "player" and l.sellerId == uid
		end) >= AuctionRules.MaxLotsPerSeller then
			toast(ms, TEXT.per_seller)
			return
		end
		if countLots(function(l)
			return l.kind == "player"
		end) >= AuctionRules.MaxPlayerLots then
			toast(ms, TEXT.full)
			return
		end
		if t - (S.lastConsign[uid] or -math.huge) < AuctionRules.ConsignCooldown then
			toast(ms, TEXT.wait)
			return
		end
		local lot = AuctionRules.NewPlayerLot(S.serial + 1, { userId = uid, name = nameOf(ms) }, car, start, duration, t)
		if not lot then
			toast(ms, TEXT.not_found)
			return
		end
		S.serial += 1
		-- erst sperren (CanSpawn/Tune/Sell verweigern ab jetzt), dann ein gespawntes Auto abbauen
		CarRules.SetLocked(d, car.id, true)
		if api.releaseCar then
			local okRelease, errRelease = pcall(api.releaseCar, ms, car.id)
			if not okRelease then
				warn("[Auktion] Auto abbauen: " .. tostring(errRelease))
			end
		end
		S.lastConsign[uid] = t
		addLot(lot)
		toast(ms, "Dein " .. lot.name .. " ist jetzt in der Auktion: Startgebot " .. credits(start) .. ", "
			.. math.floor(duration / 60) .. " Min. Gebühr beim Verkauf: 5 %.")
		flushPublic(t)
	end)

	-- mini_auction_cancel {lot}: nur der Verkäufer, nur ohne Gebote
	Actions.Register("mini_auction_cancel", function(ms, data, d, t)
		track(ms)
		local lot = S.lots[data.lot]
		if not lot or lot.kind ~= "player" or lot.sellerId ~= uidOf(ms) then
			toast(ms, TEXT.not_yours)
			return
		end
		if lot.state ~= "open" then
			toast(ms, TEXT.ended)
			return
		end
		if #lot.bids > 0 then
			toast(ms, TEXT.has_bids)
			return
		end
		AuctionRules.Cancel(lot, d, t, "seller")
		S.dirty = true
		toast(ms, "Auktion zurückgezogen. Dein " .. lot.name .. " ist wieder frei.")
		flushPublic(t)
	end)
end

---------------------------------------------------------------- Tests / Diagnose
function AuctionService.Reset(seed)
	S = newState(seed)
end

function AuctionService.State()
	return S
end

function AuctionService.Lot(id)
	return S.lots[id]
end

-- Öffnet sofort ein NPC-Los (Tests, Admin). Rückgabe: lot oder nil
function AuctionService.StartNpcLot(modelId, t)
	t = t or now()
	if countLots(function(l)
		return l.kind == "npc"
	end) > 0 then
		return nil
	end
	S.serial += 1
	local lot = AuctionRules.NewNpcLot(S.serial, modelId, S.seed, t)
	if lot then
		S.npcNext = nil
		S.lastNpcModel = lot.model
		addLot(lot)
	end
	return lot
end

return AuctionService
