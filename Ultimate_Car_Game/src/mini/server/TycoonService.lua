-- TycoonService: Schnelles Spiel (Tycoon) auf dem Server (docs/PHASE4_CONTRACT.md §8, §10–§12).
-- Regeln und Zahlen: TycoonRules (rein) und GameConfig.Tycoon. Hier nur Grundstücke, Modelle, Pads, Handel und Hinweise.
-- Bargeld (run.cash/run.container) ist NIE Credits: es verlässt den Durchlauf nie. Credits ändern sich hier nur über
-- den Level-Bonus von MiniRules.GainXP (XP je Stufe/Durchlauf), nie aus Bargeld.
--
-- Schnittstelle für MiniService:
--   Register(Actions, api)              tycoon_choose {building}, tycoon_collect, tycoon_buy {id}, tycoon_stage, tycoon_rebirth,
--                                       tycoon_abandon, tycoon_trade_offer {to, item, qty, price}, tycoon_trade_accept {id},
--                                       tycoon_trade_cancel {id}  (api wie bei PressService: now, toast, notice, dirty, alive, changed)
--   Init(ctx)                           ctx aus MiniService.Init (getSession, emit, now); bindet Start-/Sammel-Pads aller Grundstücke
--   OnJoin(ms, d, now)                  Sitzung merken, d.games.tycoon sicherstellen; im Modus tycoon sofort Grundstück + Modelle
--   OnMode(ms, d, mode)                 Moduswechsel (LobbyService/PlaceRouter): tycoon -> Grundstück belegen, Durchlauf fortsetzen;
--                                       anderer Modus -> Grundstück frei, eigene Angebote weg. Tick erkennt den Wechsel auch selbst.
--   Tick(ms, d, now) -> changed         alle 0,5 s: TycoonRules.Tick, Anzeigen (höchstens 1×/s), Angebote ablaufen lassen
--   OnLeave(ms)                         Grundstück frei, Angebote weg (der Durchlauf bleibt im Profil: Fortsetzen)
--   SnapshotFields(ms, d, now, full)    { tycoon = { active, run, slot, offers, bonus, runsDone, rebirths, boost, plots } }
--   Buy(ms, d, id, now, source)         Kaufweg der Pads und Aktionen (Upgrade-Id oder Stufen-Pad-Id)
--   Collect(ms, d, now)                 Sammel-Pad / tycoon_collect
-- Welt: workspace.Tycoon.Plots.Slot_1..8 (Base, Sign, StartPad TycoonSlot=n, CollectPad TycoonPad="collect", Anchor, ButtonsRoot).
-- Stufenmodelle ServerStorage.TycoonTemplates.<typ>.Stage_<n> (PrimaryPart Root am Anker-Pivot; Ordner Buttons mit Parts
-- TycoonButton=<id> (SurfaceGui Label: TextLabels Name/Price), Part StagePad (TycoonButton="<typ>_stage<n+1>"), Ordner Hidden
-- mit Producer_<k>, Part CashDisplay mit SurfaceGui-Text "Bargeld"). Die Klone liegen in Slot_n.ButtonsRoot.
-- Alle Instanz-Arbeit läuft in pcall: ohne Zone/Vorlagen läuft der Durchlauf trotzdem (nur ohne Modelle).
local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local TycoonRules = require(MiniShared:WaitForChild("TycoonRules"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))

local TycoonService = {}

local TY = GameConfig.Tycoon
-- Zeiten (Sekunden); GameConfig.Tycoon darf sie überschreiben (PadDebounce, LabelInterval, SnapshotInterval, PlotRetry)
local PAD_DEBOUNCE = TY.PadDebounce or 0.5
local LABEL_INTERVAL = TY.LabelInterval or 1
local SNAPSHOT_INTERVAL = TY.SnapshotInterval or 1
local PLOT_RETRY = TY.PlotRetry or 2
local TOAST_THROTTLE = TY.PadToastSeconds or 2
local OFFER_SWEEP = 1

export type Plot = {
	slot: number, ms: any, player: Player, model: Instance?, anchor: Instance?, root: Instance?,
	stages: { Instance }, buttons: { [Instance]: string }, conns: { RBXScriptConnection }, padAt: { [Instance]: number },
	toastAt: { [string]: number }, labelAt: number, noTemplates: boolean?,
}
export type Offer = {
	id: number, from: number, fromName: string, to: number, toName: string, item: string, qty: number, price: number,
	expires: number, createdAt: number,
}

TycoonService.Plots = {} :: { [number]: Plot } -- [slot] = Grundstück (serverlokal)
TycoonService.SlotOf = setmetatable({}, { __mode = "k" }) :: { [Player]: number }
TycoonService.Sessions = setmetatable({}, { __mode = "k" }) -- [Player] = ms
TycoonService.Offers = {} :: { [number]: Offer } -- [id] = Angebot (serverlokal, nur Bargeld/Waren)
local offerSerial = 0
local lastSweep = -math.huge

local api -- MiniService-api: now, toast, notice, dirty, alive, changed
local ctx -- GarageServer-Kontext (getSession, emit, now)
local padConns = {} :: { RBXScriptConnection }
local padsBound = false

local COLORS = {
	owned = Color3.fromRGB(62, 217, 166),
	ready = Color3.fromRGB(247, 176, 63),
	locked = Color3.fromRGB(156, 170, 177),
	free = Color3.fromRGB(247, 176, 63),
	taken = Color3.fromRGB(47, 169, 163),
}

local TEXT = {
	notTycoon = "Das Schnelle Spiel startest du in der Lobby: Portal „Schnelles Spiel“.",
	noPlot = "Gerade sind alle Grundstücke belegt. Sobald eins frei wird, gehört es dir.",
	plotAssigned = "Grundstück %d gehört dir! Geh zum Start-Pad und wähle dein Gebäude.",
	notMine = "Das ist nicht dein Grundstück. Deins ist Nr. %d.",
	notMineNone = "Das ist nicht dein Grundstück.",
	chooseFirst = "Wähle am Start-Pad ein Gebäude – dann geht's los.",
	unknownBuilding = "Dieses Gebäude gibt es nicht.",
	runExists = "Dein Durchlauf läuft schon: %s, Stufe %d. Weiter geht's am Grundstück!",
	started = "%s gebaut! Sammle Bargeld am Sammel-Pad und kauf die Upgrades auf den Pads.",
	resumed = "Willkommen zurück! Dein Durchlauf geht weiter: %s, Stufe %d.",
	collected = "+%d Bargeld eingesammelt.",
	nothingToCollect = "Der Behälter ist noch leer. Warte einen Moment.",
	bought = "%s gekauft!",
	stageUp = "Stufe %d erreicht! Dein Gebäude wächst.",
	rebirth = "Durchlauf abgeschlossen! Rebirth Nr. %d: ab jetzt +%d %% Einkommen. Bonus in der Open World: %s +%s %%.",
	rebirthLocked = { no_run = "Es läuft kein Durchlauf.", stage = "Rebirth gibt es erst ab Stufe 5.", upgrades = "Kauf erst alle Upgrades der Stufe 5." },
	maxStage = "Stufe 5 ist die höchste Stufe. Kauf alle Upgrades – dann Rebirth!",
	abandoned = "Durchlauf abgebrochen. Am Start-Pad kannst du neu beginnen.",
	noRunToAbandon = "Es läuft kein Durchlauf.",
	reason = {
		no_run = "Starte erst einen Durchlauf am Start-Pad.",
		unknown = "Diesen Kauf gibt es nicht.",
		wrong_building = "Das gehört zu einem anderen Gebäude.",
		wrong_stage = "Das kommt erst in einer anderen Stufe dran.",
		owned = "Das hast du schon gekauft.",
		stage_incomplete = "Kauf erst alle Upgrades dieser Stufe.",
		items = "Dafür fehlen noch Waren im Lager – Lager-Upgrades erzeugen sie, oder handle auf dem Marktplatz.",
		cash = "Nicht genug Bargeld. Sammle weiter!",
	},
	trade = {
		item = "Diese Ware gibt es nicht.",
		qty = "Menge: 1 bis " .. tostring(TY.TradeMaxQty) .. " Stück.",
		price = "Der Preis muss mindestens " .. tostring(TY.TradeMinPrice) .. " Bargeld sein.",
		storage = "So viel hast du nicht im Lager.",
		no_run = "Dafür brauchst du einen laufenden Durchlauf.",
		partnerMissing = "Diesen Spieler gibt es hier nicht.",
		partnerNotTycoon = "Dieser Spieler ist gerade nicht im Schnellen Spiel oder hat keinen Durchlauf.",
		self = "Mit dir selbst kannst du nicht handeln.",
		tooMany = "Du hast schon " .. tostring(TY.TradeMaxOpen) .. " offene Angebote.",
		offered = "Angebot an %s geschickt: %d× %s für %d Bargeld (gültig %d s).",
		received = "%s bietet dir %d× %s für %d Bargeld an. Marktplatz öffnen!",
		unknown = "Dieses Angebot gibt es nicht mehr.",
		notForYou = "Dieses Angebot ist nicht für dich.",
		expired = "Das Angebot ist abgelaufen.",
		accepted = "Handel abgeschlossen: %d× %s für %d Bargeld.",
		cancelled = "Angebot zurückgezogen.",
		declined = "Angebot abgelehnt.",
		failed = { storage = "Der Verkäufer hat die Ware nicht mehr.", cash = "Nicht genug Bargeld für dieses Angebot.", full = "Dafür ist kein Platz mehr (Lager voll).", same = "Mit dir selbst kannst du nicht handeln.", no_run = "Ein Durchlauf fehlt." },
		gone = "Das Angebot gilt nicht mehr – der Handelspartner ist weg.",
	},
}
TycoonService.Text = TEXT

---------------------------------------------------------------- Hilfen
local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function now(): number
	if api and type(api.now) == "function" then
		return api.now()
	end
	if ctx and type(ctx.now) == "function" then
		return ctx.now()
	end
	return os.time()
end

local function toast(ms: any, text: string?)
	if api and ms and type(text) == "string" and text ~= "" then
		api.toast(ms, text)
	end
end

local function notice(ms: any, kind: string, data: { [string]: any })
	if api and ms then
		api.notice(ms, kind, data)
	end
end

local function dirty(ms: any)
	if api and ms then
		api.dirty(ms)
	end
end

local function alive(ms: any): boolean
	if not ms or not ms.player then
		return false
	end
	if api and type(api.alive) == "function" then
		return api.alive(ms) == true
	end
	return ms.player.Parent ~= nil
end

local function playerName(player: any): string
	local ok, name = pcall(function()
		return player.DisplayName
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return tostring(player and player.Name or "Spieler")
end

local function inTycoon(ms: any): boolean
	return ms ~= nil and ms.p ~= nil and ms.p.mode == "tycoon"
end

local function dataOf(ms: any): any
	local p = ms and ms.p
	local prof = p and p.profile
	return prof and prof.data or nil
end

-- d.games.tycoon sicherstellen (bis MiniRules.DefaultGames/LoadGames TycoonRules aufrufen; danach ein No-op)
local function ensureData(d: any): any
	if type(d) ~= "table" or type(d.games) ~= "table" then
		return nil
	end
	if type(d.games.tycoon) ~= "table" or type(d.games.tycoon.runsDone) ~= "table" then
		TycoonRules.ApplyLoad(d.games, { tycoon = d.games.tycoon }, d, now())
	end
	return d.games.tycoon
end

local function runOf(d: any): any
	return TycoonRules.RunOf(d)
end

local function buildingName(typ: any): string
	local b = type(typ) == "string" and TY.Buildings[typ] or nil
	return b and b.name or tostring(typ)
end

local function itemName(item: any): string
	local it = type(item) == "string" and TY.Items[item] or nil
	return it and it.name or tostring(item)
end

local function fmt(n: any): string
	return tostring(math.floor(finite(n) and n or 0))
end

---------------------------------------------------------------- Welt: Zone, Grundstücke, Vorlagen
local function zone(): Instance?
	return workspace:FindFirstChild(GameConfig.Zones.tycoon.model or "Tycoon")
end

local function slotModel(slot: number): Instance?
	local z = zone()
	local plots = z and z:FindFirstChild("Plots")
	return plots and plots:FindFirstChild("Slot_" .. tostring(slot)) or nil
end

local function template(typ: string, stage: number): Instance?
	local root = ServerStorage:FindFirstChild("TycoonTemplates")
	local folder = root and root:FindFirstChild(typ)
	return folder and folder:FindFirstChild("Stage_" .. tostring(stage)) or nil
end

local function anchorCFrame(plot: Plot): CFrame?
	local anchor = plot.anchor
	if anchor and anchor:IsA("BasePart") then
		return anchor.CFrame
	elseif anchor and anchor:IsA("Model") then
		return anchor:GetPivot()
	end
	local s = TY.SlotByNumber and TY.SlotByNumber[plot.slot]
	if s then
		return CFrame.new(s.x, 0.5, s.z) * CFrame.Angles(0, math.rad(s.rot or 0), 0)
	end
	return nil
end

local function setLabel(gui: Instance?, name: string, text: string?, color: Color3?)
	if not gui then
		return
	end
	for _, x in ipairs(gui:GetDescendants()) do
		if x:IsA("TextLabel") and x.Name == name then
			if text then
				x.Text = text
			end
			if color then
				x.TextColor3 = color
			end
		end
	end
end

-- Schild wie World.dressSlot: Owner-Attribut, TextLabels Owner/Welcome, Kappe in Frei-/Besitzfarbe
local function dressSign(slot: number, player: Player?)
	local model = slotModel(slot)
	local sign = model and model:FindFirstChild("Sign")
	if not sign then
		return
	end
	local name = player and playerName(player) or nil
	sign:SetAttribute("Owner", name or "")
	setLabel(sign, "Owner", name or "FREI")
	setLabel(sign, "Welcome", name and ("WILLKOMMEN, " .. name) or ("FREI – Grundstück " .. tostring(slot)), name and COLORS.taken or COLORS.free)
	local cap = sign:FindFirstChild("Cap")
	if cap and cap:IsA("BasePart") then
		local color = cap:GetAttribute(name and "OwnedColor" or "FreeColor")
		cap.Color = typeof(color) == "Color3" and color or (name and COLORS.taken or COLORS.free)
	end
end

local function plotOf(ms: any): Plot?
	local slot = ms and ms.player and TycoonService.SlotOf[ms.player]
	local plot = slot and TycoonService.Plots[slot]
	if plot and plot.ms == ms then
		return plot
	end
	return nil
end

---------------------------------------------------------------- Modelle: Aufbau, Produzenten, Beschriftung
local function stageOfId(id: string): (number?, boolean)
	local u = TY.UpgradeById[id]
	if u then
		return u.stage, false
	end
	local s = TY.StageById[id]
	if s then
		return s.stage, true
	end
	return nil, false
end

local function clearModels(plot: Plot)
	for _, c in ipairs(plot.conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	plot.conns = {}
	plot.buttons = {}
	plot.padAt = {}
	for _, m in ipairs(plot.stages) do
		pcall(function()
			m:Destroy()
		end)
	end
	plot.stages = {}
	if plot.root then
		for _, c in ipairs(plot.root:GetChildren()) do
			pcall(function()
				c:Destroy()
			end)
		end
	end
end

-- Produzenten der gekauften Upgrades aus "Hidden" ins Modell holen (bleiben sonst unsichtbar in der Vorlage)
local function revealProducers(plot: Plot, run: any)
	for _, model in ipairs(plot.stages) do
		local stage = model:GetAttribute("TycoonStage")
		local hidden = model:FindFirstChild("Hidden")
		if hidden and finite(stage) then
			for k = 1, TY.UpgradesPerStage do
				local id = run.building .. "_s" .. tostring(stage) .. "_u" .. tostring(k)
				if run.upgrades[id] then
					local producer = hidden:FindFirstChild("Producer_" .. tostring(k))
					if producer then
						producer.Parent = model
					end
				end
			end
		end
	end
end

local function priceText(id: string, cost: number, reason: string): string
	local sid = TY.StageById[id]
	if sid and reason == "items" then
		return fmt(cost) .. " Bargeld + Waren"
	end
	return fmt(cost) .. " Bargeld"
end

local function updateLabels(plot: Plot, run: any)
	for part, id in pairs(plot.buttons) do
		local stage, isStage = stageOfId(id)
		local owned = (run.upgrades and run.upgrades[id] ~= nil) or (isStage and stage ~= nil and stage <= run.stage)
		local ok, reason, cost = TycoonRules.CanBuy(run, id)
		local state = owned and "owned" or (ok and "ready" or "locked")
		part:SetAttribute("TycoonState", state)
		local label = part:FindFirstChild("Label")
		if owned then
			setLabel(label, "Price", "Gekauft", COLORS.owned)
		else
			setLabel(label, "Price", priceText(id, cost, reason), ok and COLORS.ready or COLORS.locked)
		end
		if part:IsA("BasePart") then
			part.Color = COLORS[state]
		end
	end
end

local function updateCash(plot: Plot, run: any?)
	local text = run and string.format("Bargeld %s\nBehälter %s / %s", fmt(run.cash), fmt(run.container), fmt(TycoonRules.Capacity(run))) or "Bargeld 0"
	for _, model in ipairs(plot.stages) do
		local display = model:FindFirstChild("CashDisplay", true)
		if display then
			local gui = display:FindFirstChildOfClass("SurfaceGui")
			local set = false
			if gui then
				for _, x in ipairs(gui:GetDescendants()) do
					if x:IsA("TextLabel") and (x.Name == "Bargeld" or not set) then
						x.Text = text
						set = true
					end
				end
			end
		end
	end
end

local function refreshVisuals(plot: Plot, run: any)
	pcall(function()
		revealProducers(plot, run)
		updateLabels(plot, run)
		updateCash(plot, run)
	end)
end

local onPadTouched -- vorwärts

local function bindButtons(plot: Plot, model: Instance)
	for _, part in ipairs(model:GetDescendants()) do
		if part:IsA("BasePart") then
			local id = part:GetAttribute("TycoonButton")
			if type(id) == "string" and id ~= "" then
				plot.buttons[part] = id
				local conn = part.Touched:Connect(function(hit)
					onPadTouched(plot, part, hit)
				end)
				table.insert(plot.conns, conn)
			end
		end
	end
end

-- Das Stufenmodell der aktuellen Stufe aus der Vorlage am Anker aufbauen (rotationssicher über PivotTo).
-- Die Vorlagen sind je Stufe vollständig (tools/worldgen/tycoon_templates.py): Stage_n enthält das ganze Grundstück
-- dieser Stufe samt ihren Kaufpads; die Pads niedrigerer Stufen sind dann längst gekauft und werden nicht gebraucht.
local function rebuild(plot: Plot, run: any?)
	pcall(clearModels, plot)
	if not run then
		return
	end
	local ok, err = pcall(function()
		local pivot = anchorCFrame(plot)
		if not pivot then
			return
		end
		for s = run.stage, run.stage do
			local tpl = template(run.building, s)
			if not tpl then
				if not plot.noTemplates then
					plot.noTemplates = true
					warn("[Tycoon] Vorlage fehlt: ServerStorage.TycoonTemplates." .. run.building .. ".Stage_" .. tostring(s))
				end
			else
				local clone = tpl:Clone()
				clone.Name = "Stage_" .. tostring(s)
				clone:SetAttribute("TycoonStage", s)
				clone:SetAttribute("TycoonSlot", plot.slot)
				clone:PivotTo(pivot)
				clone.Parent = plot.root or plot.model
				table.insert(plot.stages, clone)
				bindButtons(plot, clone)
			end
		end
	end)
	if not ok then
		warn("[Tycoon] Aufbau: " .. tostring(err))
	end
	refreshVisuals(plot, run)
end

---------------------------------------------------------------- Grundstücke
local function assignPlot(ms: any): Plot?
	local existing = plotOf(ms)
	if existing then
		return existing
	end
	for _, s in ipairs(TY.Slots) do
		local slot = s.slot
		if not TycoonService.Plots[slot] then
			local model = slotModel(slot)
			local plot: Plot = {
				slot = slot, ms = ms, player = ms.player, model = model,
				anchor = model and model:FindFirstChild("Anchor") or nil,
				root = model and model:FindFirstChild("ButtonsRoot") or nil,
				stages = {}, buttons = {}, conns = {}, padAt = {}, toastAt = {}, labelAt = -math.huge,
			}
			TycoonService.Plots[slot] = plot
			TycoonService.SlotOf[ms.player] = slot
			pcall(dressSign, slot, ms.player)
			return plot
		end
	end
	return nil
end

local function releasePlot(ms: any)
	local plot = plotOf(ms)
	if not plot then
		if ms and ms.player then
			TycoonService.SlotOf[ms.player] = nil
		end
		return
	end
	pcall(clearModels, plot)
	TycoonService.Plots[plot.slot] = nil
	TycoonService.SlotOf[ms.player] = nil
	pcall(dressSign, plot.slot, nil)
end

---------------------------------------------------------------- Handel: Angebote (serverlokal)
local function sessionByUserId(userId: number): any
	for player, ms in pairs(TycoonService.Sessions) do
		if player.UserId == userId and alive(ms) then
			return ms
		end
	end
	return nil
end

local function offerView(o: Offer): { [string]: any }
	return {
		id = o.id, from = o.from, fromName = o.fromName, to = o.to, toName = o.toName, item = o.item,
		itemName = itemName(o.item), qty = o.qty, price = o.price, expires = o.expires,
	}
end

local function sortedOffers(): { Offer }
	local list = {}
	for _, o in pairs(TycoonService.Offers) do
		table.insert(list, o)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

local function marketViews(list: { Offer }?): { { [string]: any } }
	local views = {}
	for _, o in ipairs(list or sortedOffers()) do
		table.insert(views, offerView(o))
	end
	return views
end

local function myOffers(userId: number): { { [string]: any } }
	local out = {}
	for _, o in ipairs(sortedOffers()) do
		if o.from == userId or o.to == userId then
			table.insert(out, offerView(o))
		end
	end
	return out
end

local function openCount(userId: number): number
	local n = 0
	for _, o in pairs(TycoonService.Offers) do
		if o.from == userId then
			n += 1
		end
	end
	return n
end

-- Marktplatz-Tafel (workspace.Tycoon.Markt ... TextLabel "Offers") beschriften
local function updateBoard(list: { Offer })
	local z = zone()
	local market = z and z:FindFirstChild("Markt")
	if not market then
		return
	end
	local lines = {}
	for i, o in ipairs(list) do
		if i > 6 then
			table.insert(lines, "…")
			break
		end
		table.insert(lines, string.format("%s → %s: %d× %s für %d Bargeld", o.fromName, o.toName, o.qty, itemName(o.item), o.price))
	end
	setLabel(market, "Offers", #lines > 0 and table.concat(lines, "\n") or "Angebote der Spieler (Bargeld): noch keine")
end

-- mini_notice { kind = "tycoon_market", offers } an alle Tycoon-Spieler, dazu die Tafel
local function broadcastMarket()
	local list = sortedOffers()
	local views = marketViews(list)
	for _, ms in pairs(TycoonService.Sessions) do
		if alive(ms) and inTycoon(ms) then
			notice(ms, "tycoon_market", { offers = views, count = #views })
			dirty(ms)
		end
	end
	pcall(updateBoard, list)
end

local function tradeNotice(userId: number, event: string, o: Offer, extra: { [string]: any }?)
	local ms = sessionByUserId(userId)
	if not ms then
		return
	end
	local data = offerView(o)
	data.event = event
	for k, v in pairs(extra or {}) do
		data[k] = v
	end
	notice(ms, "trade", data)
	dirty(ms)
end

local function removeOffer(o: Offer, event: string, extra: { [string]: any }?)
	TycoonService.Offers[o.id] = nil
	tradeNotice(o.from, event, o, extra)
	tradeNotice(o.to, event, o, extra)
end

-- Alle Angebote eines Spielers (als Verkäufer oder Käufer) zurücknehmen
local function dropOffersOf(userId: number, event: string)
	local any = false
	for _, o in ipairs(sortedOffers()) do
		if o.from == userId or o.to == userId then
			removeOffer(o, event)
			local other = sessionByUserId(o.from == userId and o.to or o.from)
			if other then
				toast(other, TEXT.trade.gone)
			end
			any = true
		end
	end
	if any then
		broadcastMarket()
	end
end

local function sweepOffers(t: number)
	if t - lastSweep < OFFER_SWEEP then
		return
	end
	lastSweep = t
	local any = false
	for _, o in ipairs(sortedOffers()) do
		if t >= o.expires then
			removeOffer(o, "expired")
			any = true
		end
	end
	if any then
		broadcastMarket()
	end
end

---------------------------------------------------------------- Durchlauf: betreten, verlassen
local function enter(ms: any, d: any)
	if ms.tycoonActive then
		return
	end
	ms.tycoonActive = true
	ms.tycoonSnapAt = -math.huge
	ms.tycoonPlotAt = -math.huge
	TycoonService.Sessions[ms.player] = ms
	ensureData(d)
	local plot = assignPlot(ms)
	local run = runOf(d)
	if run then
		run.lastTick = now() -- Offline zählt nicht (Vertrag §8)
	end
	if plot then
		rebuild(plot, run)
		if run then
			toast(ms, string.format(TEXT.resumed, buildingName(run.building), run.stage))
		else
			toast(ms, string.format(TEXT.plotAssigned, plot.slot))
		end
	else
		toast(ms, TEXT.noPlot)
	end
	local views = marketViews()
	notice(ms, "tycoon_market", { offers = views, count = #views })
	dirty(ms)
end

local function leave(ms: any)
	if not ms then
		return
	end
	ms.tycoonActive = false
	if ms.player then
		dropOffersOf(ms.player.UserId, "cancelled")
	end
	releasePlot(ms)
	dirty(ms)
end

---------------------------------------------------------------- Kaufen und Sammeln
local function throttledToast(ms: any, plot: Plot?, key: string, text: string, t: number)
	if plot then
		local last = plot.toastAt[key]
		if last and t - last < TOAST_THROTTLE then
			return
		end
		plot.toastAt[key] = t
	end
	toast(ms, text)
end

-- Kaufweg (Pads und Aktionen). source = "pad" (außerhalb von request(): Credits-Änderungen über api.changed) | "action"
function TycoonService.Buy(ms: any, d: any, id: any, t: number?, source: string?): (boolean, string)
	t = finite(t) and t or now()
	local plot = plotOf(ms)
	local run = runOf(d)
	if not run then
		throttledToast(ms, plot, "no_run", TEXT.reason.no_run, t)
		return false, "no_run"
	end
	local ok, reason, cost = TycoonRules.Buy(run, id)
	if not ok then
		throttledToast(ms, plot, reason, TEXT.reason[reason] or TEXT.reason.unknown, t)
		return false, reason
	end
	local money = d.money
	local u = TY.UpgradeById[id]
	if u then
		toast(ms, string.format(TEXT.bought, u.name))
		if plot then
			refreshVisuals(plot, run)
		end
		notice(ms, "tycoon_stage", { event = "upgrade", id = id, name = u.name, stage = run.stage, building = run.building, cost = cost })
	else
		local xp = MiniRules.GainXP(d, TycoonRules.XPForStage())
		toast(ms, string.format(TEXT.stageUp, run.stage))
		if plot then
			rebuild(plot, run)
		end
		notice(ms, "tycoon_stage", { event = "stage", stage = run.stage, building = run.building, cost = cost, xp = TycoonRules.XPForStage(), levels = xp.levels })
	end
	if source == "pad" and d.money ~= money and api and type(api.changed) == "function" then
		api.changed(ms) -- Level-Bonus außerhalb von request(): Revision + Push
	else
		dirty(ms)
	end
	return true, ""
end

function TycoonService.Collect(ms: any, d: any, t: number?): number
	t = finite(t) and t or now()
	local plot = plotOf(ms)
	local run = runOf(d)
	if not run then
		throttledToast(ms, plot, "no_run", TEXT.reason.no_run, t)
		return 0
	end
	TycoonRules.Tick(run, t)
	local amount = TycoonRules.Collect(run)
	if amount <= 0 then
		throttledToast(ms, plot, "empty", TEXT.nothingToCollect, t)
		return 0
	end
	throttledToast(ms, plot, "collected", string.format(TEXT.collected, amount), t)
	if plot then
		refreshVisuals(plot, run)
	end
	dirty(ms)
	return amount
end

-- Kaufpad berührt: nur der Besitzer, nur lebende Figuren, 0,5 s Entprellung je Pad
onPadTouched = function(plot: Plot, part: Instance, hit: any, padId: string?)
	local ok, err = pcall(function()
		if typeof(hit) ~= "Instance" then
			return
		end
		local ch = hit.Parent
		if ch and not ch:FindFirstChildOfClass("Humanoid") then
			ch = ch.Parent -- Accessoire/Werkzeug
		end
		local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
		if not humanoid or humanoid.Health <= 0 then
			return
		end
		local player = Players:GetPlayerFromCharacter(ch)
		if not player or player ~= plot.player then
			return
		end
		local ms = plot.ms
		if not alive(ms) or TycoonService.Plots[plot.slot] ~= plot or not inTycoon(ms) then
			return
		end
		local t = now()
		local last = plot.padAt[part]
		if last and t - last < PAD_DEBOUNCE then
			return
		end
		plot.padAt[part] = t
		local id = padId or plot.buttons[part]
		local d = dataOf(ms)
		if not id or not d then
			return
		end
		if id == "collect" then
			TycoonService.Collect(ms, d, t)
		else
			TycoonService.Buy(ms, d, id, t, "pad")
		end
	end)
	if not ok then
		warn("[Tycoon] Pad: " .. tostring(err))
	end
end

---------------------------------------------------------------- Start-/Sammel-Pads der Grundstücke (Prompts + Touched)
local function sessionOf(player: Player): any
	local ms = TycoonService.Sessions[player]
	if ms and alive(ms) then
		return ms
	end
	return nil
end

local function onStartPrompt(slot: number, player: Player)
	local ms = sessionOf(player)
	if not ms then
		return
	end
	local d = dataOf(ms)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	local mine = TycoonService.SlotOf[player]
	if mine ~= slot then
		if mine then
			toast(ms, string.format(TEXT.notMine, mine))
		else
			-- noch ohne Grundstück (alle belegt): jetzt noch einmal versuchen
			local plot = assignPlot(ms)
			if plot then
				rebuild(plot, d and runOf(d) or nil)
				toast(ms, string.format(TEXT.plotAssigned, plot.slot))
				dirty(ms)
			else
				toast(ms, TEXT.noPlot)
			end
		end
		return
	end
	local run = d and runOf(d) or nil
	if run then
		toast(ms, string.format(TEXT.runExists, buildingName(run.building), run.stage))
	end
	notice(ms, "tycoon_choose", { slot = slot, hasRun = run ~= nil, building = run and run.building or nil, types = TY.Types })
	dirty(ms)
end

local function onCollectPrompt(slot: number, player: Player)
	local ms = sessionOf(player)
	if not ms or not inTycoon(ms) then
		return
	end
	if TycoonService.SlotOf[player] ~= slot then
		local mine = TycoonService.SlotOf[player]
		toast(ms, mine and string.format(TEXT.notMine, mine) or TEXT.notMineNone)
		return
	end
	local d = dataOf(ms)
	if d then
		TycoonService.Collect(ms, d, now())
	end
end

local function bindPads()
	if padsBound then
		return
	end
	padsBound = true
	for _, s in ipairs(TY.Slots) do
		local slot = s.slot
		local model = slotModel(slot)
		if model then
			local start = model:FindFirstChild("StartPad")
			local prompt = start and start:FindFirstChildOfClass("ProximityPrompt")
			if prompt then
				table.insert(padConns, prompt.Triggered:Connect(function(player)
					local ok, err = pcall(onStartPrompt, slot, player)
					if not ok then
						warn("[Tycoon] Start-Pad: " .. tostring(err))
					end
				end))
			end
			local collect = model:FindFirstChild("CollectPad")
			local cprompt = collect and collect:FindFirstChildOfClass("ProximityPrompt")
			if cprompt then
				table.insert(padConns, cprompt.Triggered:Connect(function(player)
					local ok, err = pcall(onCollectPrompt, slot, player)
					if not ok then
						warn("[Tycoon] Sammel-Pad: " .. tostring(err))
					end
				end))
			end
			if collect and collect:IsA("BasePart") then
				-- Sammeln auch durch Betreten (Touched, entprellt über plot.padAt, nur der Besitzer)
				table.insert(padConns, collect.Touched:Connect(function(hit)
					local plot = TycoonService.Plots[slot]
					if plot then
						onPadTouched(plot, collect, hit, "collect")
					end
				end))
			end
		end
	end
end

---------------------------------------------------------------- Aktionen
local function choose(ms: any, data: any, d: any, t: number)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	ensureData(d)
	local run = runOf(d)
	if run then
		toast(ms, string.format(TEXT.runExists, buildingName(run.building), run.stage))
		return
	end
	if not TycoonRules.IsType(data.building) then
		toast(ms, TEXT.unknownBuilding)
		return
	end
	local plot = assignPlot(ms)
	if not plot then
		toast(ms, TEXT.noPlot)
		return
	end
	run = TycoonRules.NewRun(d, data.building, t)
	if not run then
		toast(ms, TEXT.unknownBuilding)
		return
	end
	rebuild(plot, run)
	notice(ms, "tycoon_stage", { event = "start", stage = 1, building = run.building, name = buildingName(run.building), slot = plot.slot })
	toast(ms, string.format(TEXT.started, buildingName(run.building)))
	dirty(ms)
end

local function collect(ms: any, _: any, d: any, t: number)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	TycoonService.Collect(ms, d, t)
end

local function buy(ms: any, data: any, d: any, t: number)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	TycoonService.Buy(ms, d, data.id, t, "action")
end

local function stage(ms: any, _: any, d: any, t: number)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	local run = runOf(d)
	if not run then
		toast(ms, TEXT.reason.no_run)
		return
	end
	local b = TY.Buildings[run.building]
	local st = b and b.Stages[run.stage]
	if not st or not st.stageId then
		toast(ms, TEXT.maxStage)
		return
	end
	TycoonService.Buy(ms, d, st.stageId, t, "action")
end

local function rebirth(ms: any, _: any, d: any, t: number)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	ensureData(d)
	local ok, reason, typ = TycoonRules.Rebirth(d, t)
	if not ok then
		toast(ms, TEXT.rebirthLocked[reason] or TEXT.reason.no_run)
		return
	end
	local tycoon = d.games.tycoon
	MiniRules.AddStat(d, "tycoonRuns", 1, t)
	local xp = MiniRules.GainXP(d, TycoonRules.XPForRun())
	dropOffersOf(ms.player.UserId, "cancelled")
	local plot = plotOf(ms)
	if plot then
		rebuild(plot, nil)
	end
	local boost = math.floor(TycoonRules.BoostFor(d) * 100 + 0.5)
	local bonus = TY.Bonus[typ]
	local pct = math.floor(TycoonRules.BonusFor(d, typ) * 1000 + 0.5) / 10
	notice(ms, "tycoon_stage", {
		event = "rebirth", building = typ, name = buildingName(typ), rebirths = tycoon.rebirths, runsDone = tycoon.runsDone[typ],
		boostPct = boost, bonusPct = pct, bonusText = bonus and bonus.text or "", xp = TycoonRules.XPForRun(), levels = xp.levels,
	})
	toast(ms, string.format(TEXT.rebirth, tycoon.rebirths, boost, bonus and bonus.text or "", tostring(pct)))
	dirty(ms)
end

local function abandon(ms: any, _: any, d: any)
	ensureData(d)
	if not TycoonRules.Abandon(d) then
		toast(ms, TEXT.noRunToAbandon)
		return
	end
	dropOffersOf(ms.player.UserId, "cancelled")
	local plot = plotOf(ms)
	if plot then
		rebuild(plot, nil)
	end
	notice(ms, "tycoon_stage", { event = "abandon" })
	toast(ms, TEXT.abandoned)
	dirty(ms)
end

local function tradeOffer(ms: any, data: any, d: any, t: number)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	local run = runOf(d)
	if not run then
		toast(ms, TEXT.trade.no_run)
		return
	end
	local qty = finite(data.qty) and math.floor(data.qty) or 0
	local price = finite(data.price) and math.floor(data.price) or 0
	local ok, reason = TycoonRules.TradeValid(run, data.item, qty, price)
	if not ok then
		toast(ms, TEXT.trade[reason] or TEXT.trade.item)
		return
	end
	local to = finite(data.to) and math.floor(data.to) or 0
	if to == ms.player.UserId then
		toast(ms, TEXT.trade.self)
		return
	end
	local other = sessionByUserId(to)
	if not other then
		toast(ms, TEXT.trade.partnerMissing)
		return
	end
	local od = dataOf(other)
	if not inTycoon(other) or not od or not runOf(od) then
		toast(ms, TEXT.trade.partnerNotTycoon)
		return
	end
	if openCount(ms.player.UserId) >= TY.TradeMaxOpen then
		toast(ms, TEXT.trade.tooMany)
		return
	end
	offerSerial += 1
	local offer: Offer = {
		id = offerSerial, from = ms.player.UserId, fromName = playerName(ms.player), to = to, toName = playerName(other.player),
		item = data.item, qty = qty, price = price, expires = t + TY.TradeTTL, createdAt = t,
	}
	TycoonService.Offers[offer.id] = offer
	tradeNotice(offer.from, "offered", offer)
	tradeNotice(offer.to, "offered", offer)
	toast(ms, string.format(TEXT.trade.offered, offer.toName, qty, itemName(data.item), price, TY.TradeTTL))
	toast(other, string.format(TEXT.trade.received, offer.fromName, qty, itemName(data.item), price))
	broadcastMarket()
end

local function tradeAccept(ms: any, data: any, d: any, t: number)
	if not inTycoon(ms) then
		toast(ms, TEXT.notTycoon)
		return
	end
	local id = finite(data.id) and math.floor(data.id) or -1
	local offer = TycoonService.Offers[id]
	if not offer then
		toast(ms, TEXT.trade.unknown)
		return
	end
	if offer.to ~= ms.player.UserId then
		toast(ms, TEXT.trade.notForYou)
		return
	end
	if t >= offer.expires then
		removeOffer(offer, "expired")
		toast(ms, TEXT.trade.expired)
		broadcastMarket()
		return
	end
	local seller = sessionByUserId(offer.from)
	local sd = seller and dataOf(seller) or nil
	local sellerRun = sd and runOf(sd) or nil
	if not seller or not inTycoon(seller) or not sellerRun then
		removeOffer(offer, "cancelled")
		toast(ms, TEXT.trade.gone)
		broadcastMarket()
		return
	end
	local buyerRun = runOf(d)
	if not buyerRun then
		toast(ms, TEXT.trade.no_run)
		return
	end
	-- Übergabe in einem Schritt (Lager und Bargeld werden jetzt erneut geprüft)
	local ok, reason = TycoonRules.ApplyTrade(sellerRun, buyerRun, offer.item, offer.qty, offer.price)
	if not ok then
		removeOffer(offer, "failed", { reason = reason })
		toast(ms, TEXT.trade.failed[reason] or TEXT.trade.unknown)
		toast(seller, TEXT.trade.failed[reason] or TEXT.trade.unknown)
		broadcastMarket()
		return
	end
	removeOffer(offer, "accepted")
	toast(ms, string.format(TEXT.trade.accepted, offer.qty, itemName(offer.item), offer.price))
	toast(seller, string.format(TEXT.trade.accepted, offer.qty, itemName(offer.item), offer.price))
	local sp = plotOf(seller)
	if sp then
		refreshVisuals(sp, sellerRun)
	end
	local bp = plotOf(ms)
	if bp then
		refreshVisuals(bp, buyerRun)
	end
	broadcastMarket()
end

local function tradeCancel(ms: any, data: any)
	local id = finite(data.id) and math.floor(data.id) or -1
	local offer = TycoonService.Offers[id]
	if not offer then
		toast(ms, TEXT.trade.unknown)
		return
	end
	local me = ms.player.UserId
	if offer.from ~= me and offer.to ~= me then
		toast(ms, TEXT.trade.notForYou)
		return
	end
	removeOffer(offer, offer.from == me and "cancelled" or "declined")
	toast(ms, offer.from == me and TEXT.trade.cancelled or TEXT.trade.declined)
	broadcastMarket()
end

function TycoonService.Register(Actions: any, a: any)
	api = a
	Actions.Register("tycoon_choose", choose)
	Actions.Register("tycoon_collect", collect)
	Actions.Register("tycoon_buy", buy)
	Actions.Register("tycoon_stage", stage)
	Actions.Register("tycoon_rebirth", rebirth)
	Actions.Register("tycoon_abandon", abandon)
	Actions.Register("tycoon_trade_offer", tradeOffer)
	Actions.Register("tycoon_trade_accept", tradeAccept)
	Actions.Register("tycoon_trade_cancel", tradeCancel)
end

function TycoonService.Init(c: any)
	ctx = type(c) == "table" and c or nil
	local ok, err = pcall(bindPads)
	if not ok then
		warn("[Tycoon] Pads: " .. tostring(err))
	end
end

---------------------------------------------------------------- Sitzung
function TycoonService.OnJoin(ms: any, d: any, t: number?)
	TycoonService.Sessions[ms.player] = ms
	ms.tycoonActive = false
	ensureData(d)
	if inTycoon(ms) then
		enter(ms, d)
	end
end

-- Moduswechsel (LobbyService/PlaceRouter setzen p.mode). Idempotent; Tick holt einen verpassten Wechsel nach.
function TycoonService.OnMode(ms: any, d: any, mode: any)
	TycoonService.Sessions[ms.player] = ms
	if mode == "tycoon" then
		enter(ms, d)
	elseif ms.tycoonActive then
		leave(ms)
	end
end

-- Rückgabe: true, wenn der Snapshot gesendet werden soll (höchstens 1×/s im laufenden Durchlauf)
function TycoonService.Tick(ms: any, d: any, t: number?): boolean
	t = finite(t) and t or now()
	sweepOffers(t)
	local active = inTycoon(ms)
	if active ~= (ms.tycoonActive == true) then
		if active then
			enter(ms, d)
		else
			leave(ms)
		end
		return true
	end
	if not active then
		return false
	end
	local plot = plotOf(ms)
	if not plot and t - (ms.tycoonPlotAt or -math.huge) >= PLOT_RETRY then
		ms.tycoonPlotAt = t
		plot = assignPlot(ms)
		if plot then
			rebuild(plot, runOf(d))
			toast(ms, string.format(TEXT.plotAssigned, plot.slot))
			return true
		end
	end
	local run = runOf(d)
	if not run then
		return false
	end
	TycoonRules.Tick(run, t)
	local changed = false
	if plot and t - plot.labelAt >= LABEL_INTERVAL then
		plot.labelAt = t
		refreshVisuals(plot, run)
	end
	if t - (ms.tycoonSnapAt or -math.huge) >= SNAPSHOT_INTERVAL then
		ms.tycoonSnapAt = t
		changed = true
	end
	return changed
end

function TycoonService.OnLeave(ms: any)
	if not ms then
		return
	end
	leave(ms)
	if ms.player then
		TycoonService.Sessions[ms.player] = nil
	end
end

function TycoonService.SnapshotFields(ms: any, d: any, t: number?, full: boolean?): { [string]: any }
	ensureData(d)
	local summary = TycoonRules.Summary(d)
	local slot = ms and ms.player and TycoonService.SlotOf[ms.player] or nil
	local plots = {}
	for _, s in ipairs(TY.Slots) do
		local plot = TycoonService.Plots[s.slot]
		plots[s.slot] = plot and playerName(plot.player) or false
	end
	return {
		tycoon = {
			active = inTycoon(ms),
			run = summary.run,
			slot = slot or false,
			offers = ms and ms.player and myOffers(ms.player.UserId) or {},
			bonus = summary.bonus,
			runsDone = summary.runsDone,
			rebirths = summary.rebirths,
			boost = summary.boost,
			plots = plots,
			tradeTTL = TY.TradeTTL,
		},
	}
end

-- Für Tests/Integrator
function TycoonService.PlotOf(player: Player): Plot?
	local slot = TycoonService.SlotOf[player]
	return slot and TycoonService.Plots[slot] or nil
end

return TycoonService
