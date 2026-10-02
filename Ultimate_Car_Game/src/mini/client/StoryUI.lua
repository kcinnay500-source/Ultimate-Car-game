-- StoryUI: Tab „Story“ (story) – „Vom Kiesplatzhändler zum Mega-Verkäufer“ (docs/PHASE4_CONTRACT.md §7, §10, §11).
-- Kapitel-Kopf mit Intro-Text (Erzählstimme), Missionskarten (Fortschrittsbalken, Starten/Abholen, Sperrgrund),
-- Nebenmissionen (täglich 3 + Werkstatt-Legende, Tageszähler, Lieferungs-Uhr), Kiesplatz-Verkaufskarte (Kunde mit
-- Name, Wunsch, Spruch, drei Preisknöpfe mit erwartetem Preis/Gewinn und Risiko „sicher / wahrscheinlich / riskant“,
-- Ergebnis-Animation) und der Story-Wegweiser („Gehe zum Kiesplatz“ mit Schnellreise → mini_travel {key = "kiesplatz"}).
-- Der Client zeigt nur an und sendet Absichten: story_start {id}, story_claim {id}, story_sell {offer, price}
-- (price = Preisstufe 1..3, nie ein Betrag), side_claim {id}, mini_travel {key}. Alle Ergebnisse kommen vom Server.
--
-- Erwartete Snapshot-Felder (StoryService.SnapshotFields / StoryRules.View):
--   s.mode, s.level, s.story = { title, chapter, chapterTitle, intro, step, count, active = false | MissionView + party,
--     locked, levelNeeded, finished, next, side[] { id, title, text, progress, target, done, claimable, legend, credits, xp },
--     sale = false | { offer, customer, wants, wantsName, line, special, tiers[] { tier, label, profit, price, hint } },
--     saleIn, sales { n, best, special }, passive, titleEarned,
--     missions[] (nur bei vollen Snapshots, sticky) { id, title, text, kind, progress, target, done, active, claimable,
--     current, startable, credits, xp, cosmetic, titleReward }, chapters[] (voll) { id, title, level, done, open } }
--   Fehlen missions/chapters (kleiner Snapshot), bleibt die letzte volle Liste; ganz ohne Liste rechnet der Client sie
--   aus der replizierten Konfiguration (StoryRules.Chapter) nach.
-- Hinweise: mini_notice { kind = "story", event = "sale" | "started" | "claimed" | "side_claimed" | "delivery" },
--           mini_notice { kind = "mission", id, progress, target, done, side }.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local StoryRules = require(Mini:WaitForChild("StoryRules"))

local StoryUI = {}

StoryUI.ResultSeconds = 5 -- Ergebnis eines Verkaufs bleibt so lange sichtbar
StoryUI.PendingSeconds = 3 -- Preisknöpfe nach dem Senden gesperrt, bis der Snapshot antwortet (höchstens so lange)
StoryUI.NearStation = 25 -- Studs: „Du bist am Kiesplatz“
StoryUI.TravelKey = "kiesplatz"
StoryUI.RiskLabels = { "sicher", "wahrscheinlich", "riskant" }

local UI, Remote, T, ctx
local refs = {}
local latest = nil -- letzter Snapshot
local lastMissions, lastMissionsChapter = nil, nil -- sticky (story.missions nur bei vollen Snapshots)
local lastChapters = nil
local pendingOffer, pendingUntil = nil, 0 -- gesendetes Angebot (Serial), bis der Snapshot antwortet
local resultSerial = 0
local saleInAt, saleInBase = 0, 0 -- Countdown „Nächster Kunde“ (Serverzeit beim Snapshot)
local delivery = nil -- { route, until } laufende Lieferung (aus mini_notice)
local tickTimer = 0

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v or default
end

local function serverNow(): number
	local ok, t = pcall(function()
		return workspace:GetServerTimeNow()
	end)
	if ok and type(t) == "number" then
		return t
	end
	return os.time()
end

local function story(s: any): any
	return type(s) == "table" and type(s.story) == "table" and s.story or {}
end

local function inOpenWorld(s: any): boolean
	return type(s) == "table" and (s.mode == nil or s.mode == "openworld")
end

-- Risiko je Preisstufe aus der Erfolgschance (GameConfig.Story.Sale.Tiers), sonst nach Stufe
function StoryUI.RiskOf(tier: number): string
	local chance = nil
	local ok, S = pcall(StoryRules.Config)
	if ok and type(S) == "table" and type(S.Sale) == "table" and type(S.Sale.Tiers) == "table" then
		local t = S.Sale.Tiers[tier]
		if type(t) == "table" and type(t.chance) == "number" and t.chance == t.chance then
			chance = t.chance
		end
	end
	if type(chance) == "number" then
		if chance >= 0.999 then
			return StoryUI.RiskLabels[1]
		elseif chance >= 0.7 then
			return StoryUI.RiskLabels[2]
		end
		return StoryUI.RiskLabels[3]
	end
	return StoryUI.RiskLabels[math.clamp(tier, 1, 3)]
end

local function riskColor(risk: string): Color3
	if risk == StoryUI.RiskLabels[1] then
		return T.green
	elseif risk == StoryUI.RiskLabels[2] then
		return T.yellow
	end
	return T.red
end

---------------------------------------------------------------- Zeilen
local function missionRow(parent, i: number)
	local row, left, right = UI.Row(parent, 10 + i)
	row.Name = "Mission_" .. i
	local title = UI.Label(left, "", { Name = "Title", Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
	local text = UI.Small(left, "", 2)
	text.Name = "Text"
	local reward = UI.Small(left, "", 3)
	reward.Name = "Reward"
	local bar, fill = UI.Progress(left, T.green, 4)
	bar.Name = "Bar"
	local reason = UI.Small(left, "", 5)
	reason.Name = "Reason"
	reason.TextColor3 = T.yellow
	local item = { root = row, title = title, text = text, reward = reward, fill = fill, reason = reason, action = nil, id = nil }
	item.button = UI.Button(right, "", T.green, function()
		-- Absichten mit festem Namen (tools/validate.py prüft die gesendeten Aktionen am Namen)
		if item.action == "story_claim" and item.id then
			Remote.Send("story_claim", { id = item.id })
		elseif item.action == "story_start" and item.id then
			Remote.Send("story_start", { id = item.id })
		end
	end, { TextSize = 14, Name = "MissionButton_" .. i })
	return item
end

local function sideRow(parent, i: number)
	local row, left, right = UI.Row(parent, 10 + i)
	row.Name = "Side_" .. i
	local title = UI.Label(left, "", { Name = "Title", Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
	local text = UI.Small(left, "", 2)
	text.Name = "Text"
	local reward = UI.Small(left, "", 3)
	reward.Name = "Reward"
	local bar, fill = UI.Progress(left, T.blue, 4)
	bar.Name = "Bar"
	local item = { root = row, title = title, text = text, reward = reward, fill = fill, id = nil, claimable = false }
	item.button = UI.Button(right, "", T.blue, function()
		if item.claimable and item.id then
			Remote.Send("side_claim", { id = item.id })
		end
	end, { TextSize = 14, Name = "SideButton_" .. i })
	return item
end

local function chapterRow(parent, i: number)
	local label = UI.Small(parent, "", 10 + i)
	label.Name = "Chapter_" .. i
	return { root = label, label = label }
end

---------------------------------------------------------------- Kiesplatz-Verkauf
local function sendSell(tier: number)
	local st = story(latest)
	local sale = type(st.sale) == "table" and st.sale or nil
	if not sale or not inOpenWorld(latest) or st.passive == true then
		return
	end
	if pendingOffer ~= nil and os.clock() < pendingUntil then
		return
	end
	pendingOffer = sale.offer
	pendingUntil = os.clock() + StoryUI.PendingSeconds
	Remote.Send("story_sell", { offer = sale.offer, price = tier })
	StoryUI.RenderSale(latest)
end

local function buildSaleCard(page)
	local card = UI.Card(page, 3)
	card.Name = "SaleCard"
	UI.Title(card, "Kiesplatz · Gebrauchtwagen", 1)
	refs.saleIntro = UI.Small(card, "Ein Kunde steht am Kiesplatz. Nenne deinen Preis – günstig klappt immer, teuer braucht Verhandlungsglück.", 2)
	local customer = UI.Frame(card, { Name = "Customer", BackgroundColor3 = T.panel, LayoutOrder = 3 })
	UI.Corner(customer, 8)
	UI.Padding(customer, 12, 10)
	UI.List(customer, 4)
	refs.customerName = UI.Label(customer, "", { Name = "CustomerName", Font = UI.FontBold, TextSize = 18, LayoutOrder = 1 })
	refs.customerWish = UI.Label(customer, "", { Name = "CustomerWish", TextSize = 15, TextColor3 = T.blue, LayoutOrder = 2 })
	refs.customerLine = UI.Label(customer, "", { Name = "CustomerLine", TextSize = 15, TextColor3 = T.muted, LayoutOrder = 3 })
	refs.customerSpecial = UI.Label(customer, "Sammler – zahlt für Sondermodelle das Dreifache!", { Name = "CustomerSpecial", TextSize = 14, TextColor3 = T.yellow, LayoutOrder = 4, Visible = false })
	refs.prices = {}
	for tier = 1, 3 do
		local box = UI.Frame(card, { Name = "PriceBox_" .. tier, BackgroundTransparency = 1, LayoutOrder = 3 + tier })
		UI.List(box, 3)
		local button = UI.Button(box, "", T.green, function()
			sendSell(tier)
		end, { Name = "Price_" .. tier, LayoutOrder = 1, TextSize = 15 })
		local info = UI.Small(box, "", 2)
		info.Name = "PriceInfo_" .. tier
		refs.prices[tier] = { box = box, button = button, info = info }
	end
	refs.salePending = UI.Small(card, "Angebot gesendet – der Kunde überlegt …", 8)
	refs.salePending.Name = "SalePending"
	refs.salePending.Visible = false
	-- Ergebnis (Animation: springt auf, bleibt ResultSeconds)
	local result = UI.Frame(card, { Name = "SaleResult", BackgroundColor3 = T.panel, LayoutOrder = 9, Visible = false })
	UI.Corner(result, 8)
	UI.Padding(result, 12, 10)
	UI.List(result, 2)
	refs.resultTitle = UI.Label(result, "", { Name = "ResultTitle", Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	refs.resultText = UI.Label(result, "", { Name = "ResultText", TextSize = 14, TextColor3 = T.muted, LayoutOrder = 2 })
	refs.resultScale = Instance.new("UIScale")
	refs.resultScale.Scale = 1
	refs.resultScale.Parent = result
	refs.saleResult = result
	refs.saleWait = UI.Label(card, "", { Name = "SaleWait", TextSize = 15, TextColor3 = T.muted, LayoutOrder = 10 })
	refs.saleStats = UI.Small(card, "", 11)
	refs.saleStats.Name = "SaleStats"
	refs.saleCard = card
end

-- Verkaufskarte aus dem Snapshot (und dem Sende-Zustand)
function StoryUI.RenderSale(s: any)
	if not refs.saleCard then
		return
	end
	local st = story(s)
	local open = inOpenWorld(s)
	local sale = open and type(st.sale) == "table" and st.sale or nil
	local show = open and st.passive ~= true and (sale ~= nil or num(st.saleIn, 0) > 0 or refs.saleResult.Visible or (st.sales and num(st.sales.n, 0) > 0))
	refs.saleCard.Visible = show
	if not show then
		return
	end
	local pending = sale ~= nil and pendingOffer == sale.offer and os.clock() < pendingUntil
	local hasCustomer = sale ~= nil
	refs.customerName.Parent.Visible = hasCustomer
	for tier = 1, 3 do
		refs.prices[tier].box.Visible = hasCustomer
	end
	refs.saleIntro.Visible = hasCustomer
	refs.salePending.Visible = hasCustomer and pending
	if sale then
		refs.customerName.Text = tostring(sale.customer or "Kunde")
		refs.customerWish.Text = "Wunsch: " .. tostring(sale.wantsName or sale.wants or "ein Auto")
		refs.customerLine.Text = "„" .. tostring(sale.line or "Was soll der kosten?") .. "“"
		refs.customerSpecial.Visible = sale.special == true
		local tiers = type(sale.tiers) == "table" and sale.tiers or {}
		for tier = 1, 3 do
			local t = tiers[tier]
			local p = refs.prices[tier]
			local risk = StoryUI.RiskOf(tier)
			if type(t) == "table" then
				p.button.Text = tostring(t.label or ("Stufe " .. tier)) .. " · " .. MiniLocale.Credits(num(t.price, 0))
				p.info.Text = "Gewinn " .. MiniLocale.Credits(num(t.profit, 0)) .. " · " .. risk .. (type(t.hint) == "string" and (" – " .. t.hint) or "")
			else
				p.button.Text = "Stufe " .. tier
				p.info.Text = risk
			end
			p.info.TextColor3 = riskColor(risk)
			UI.SetEnabled(p.button, not pending, riskColor(risk))
		end
		refs.saleWait.Text = ""
		refs.saleWait.Visible = false
	else
		local wait = math.max(0, saleInBase - (serverNow() - saleInAt))
		refs.saleWait.Text = wait > 0 and ("Nächster Kunde in " .. MiniLocale.Duration(wait)) or "Der nächste Kunde kommt gleich."
		refs.saleWait.Visible = true
	end
	local sales = type(st.sales) == "table" and st.sales or {}
	refs.saleStats.Text = "Verkäufe: " .. MiniLocale.Number(num(sales.n, 0)) .. " · Bestpreis: " .. MiniLocale.Number(num(sales.best, 0)) .. " · Sondermodelle: " .. MiniLocale.Number(num(sales.special, 0))
end

-- mini_notice { kind = "story", event = "sale", sold, customer, text, credits, xp, tier }
local function showSaleResult(data: any)
	if not refs.saleResult then
		return
	end
	resultSerial += 1
	local serial = resultSerial
	local sold = data.sold == true
	refs.resultTitle.Text = sold and "Verkauft!" or "Nicht verkauft"
	refs.resultTitle.TextColor3 = sold and T.green or T.red
	local text = type(data.text) == "string" and data.text or ""
	if sold and num(data.xp, 0) > 0 then
		text = text .. " +" .. tostring(math.floor(num(data.xp, 0))) .. " XP."
	end
	refs.resultText.Text = text
	refs.saleResult.Visible = true
	refs.saleResult.BackgroundColor3 = T.panel
	refs.resultScale.Scale = 0.8
	TweenService:Create(refs.resultScale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	pendingOffer = nil
	task.delay(StoryUI.ResultSeconds, function()
		if serial == resultSerial and refs.saleResult then
			refs.saleResult.Visible = false
			if latest then
				StoryUI.RenderSale(latest)
			end
		end
	end)
end

---------------------------------------------------------------- Wegweiser
local function kiesplatzStation(): BasePart?
	local city = workspace:FindFirstChild("City")
	local stations = city and city:FindFirstChild("Stations")
	local st = stations and stations:FindFirstChild(StoryUI.TravelKey)
	if st and st:IsA("Model") then
		st = st.PrimaryPart or st:FindFirstChildWhichIsA("BasePart")
	end
	return st and st:IsA("BasePart") and st or nil
end

local function nearKiesplatz(): boolean
	local st = kiesplatzStation()
	local player = Players.LocalPlayer
	local ch = player and player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	if not st or not root then
		return false
	end
	return (st.Position - root.Position).Magnitude < StoryUI.NearStation
end

local function travel()
	Remote.Send("mini_travel", { key = StoryUI.TravelKey })
	if ctx and ctx.Close then
		ctx.Close()
	end
end

-- Zielmission des Wegweisers: aktive Mission oder die nächste startbare, wenn sie am Kiesplatz spielt (kind sell)
local function currentMission(st: any, missions: { any }): any
	if type(st.active) == "table" then
		return st.active
	end
	for _, m in ipairs(missions) do
		if m.current or m.startable then
			return m
		end
	end
	return nil
end

local function renderMapHint(s: any, missions: { any })
	local st = story(s)
	local cur = currentMission(st, missions)
	local wantsKiesplatz = (cur ~= nil and cur.kind == "sell") or type(st.sale) == "table"
	local show = wantsKiesplatz and st.finished ~= true and st.passive ~= true
	refs.mapCard.Visible = show
	if not show then
		return
	end
	if not inOpenWorld(s) then
		refs.mapText.Text = "Der Kiesplatz liegt in der Open World. Reise über die Lobby dorthin."
		refs.travelButton.Text = "Nur in der Open World"
		UI.SetEnabled(refs.travelButton, false)
	elseif nearKiesplatz() then
		refs.mapText.Text = "Du bist am Kiesplatz. Sprich mit dem Kunden und nenne deinen Preis."
		refs.travelButton.Text = "Du bist hier"
		UI.SetEnabled(refs.travelButton, false)
	else
		refs.mapText.Text = "Gehe zum Kiesplatz am Stadtrand – dort warten deine Kunden."
		refs.travelButton.Text = "Schnellreise zum Kiesplatz"
		UI.SetEnabled(refs.travelButton, true, T.blue)
	end
end

---------------------------------------------------------------- Missionsliste (sticky, sonst aus der Konfiguration)
local function missionsFor(s: any): { any }
	local st = story(s)
	local chapter = math.floor(num(st.chapter, 1))
	if type(st.missions) == "table" and #st.missions > 0 then
		lastMissions, lastMissionsChapter = st.missions, chapter
		return st.missions
	end
	if lastMissions and lastMissionsChapter == chapter then
		-- aktive Mission/Fortschritt aus dem kleinen Snapshot nachziehen
		if type(st.active) == "table" then
			for _, m in ipairs(lastMissions) do
				if m.id == st.active.id then
					m.active = true
					m.progress = num(st.active.progress, m.progress)
					m.claimable = st.active.claimable == true
				end
			end
		end
		return lastMissions
	end
	-- Rückfall: Konfiguration (replizierte GameConfig.Story)
	local out = {}
	local ok, ch = pcall(StoryRules.Chapter, chapter)
	if ok and type(ch) == "table" then
		local step = math.floor(num(st.step, 1))
		for i, m in ipairs(ch.Missions) do
			local active = type(st.active) == "table" and st.active.id == m.id
			local r = m.reward or {}
			table.insert(out, {
				id = m.id, title = m.title, text = m.text, kind = m.kind, target = num(m.target, 1),
				progress = active and num(st.active.progress, 0) or (i < step and num(m.target, 1) or 0),
				done = i < step, active = active, claimable = active and st.active.claimable == true,
				current = i == step, startable = i == step and type(st.active) ~= "table" and st.locked ~= true,
				credits = num(r.credits, 0), xp = num(r.xp, 0), cosmetic = r.cosmetic, titleReward = r.title,
			})
		end
	end
	lastMissions, lastMissionsChapter = out, chapter
	return out
end

local function rewardText(m: any): string
	local parts = { MiniLocale.Credits(num(m.credits, 0)) }
	if num(m.xp, 0) > 0 then
		table.insert(parts, tostring(math.floor(num(m.xp, 0))) .. " XP")
	end
	if type(m.titleReward) == "string" and m.titleReward ~= "" then
		table.insert(parts, "Titel „" .. m.titleReward .. "“")
	end
	if type(m.cosmetic) == "string" and m.cosmetic ~= "" then
		table.insert(parts, "Kosmetik")
	end
	return "Belohnung: " .. table.concat(parts, " · ")
end

local function renderMissions(s: any, missions: { any })
	local st = story(s)
	local locked = st.locked == true
	local passive = st.passive == true
	refs.missions:Ensure(#missions)
	local activeTitle = type(st.active) == "table" and st.active.title or nil
	for i, m in ipairs(missions) do
		local item = refs.missions.items[i]
		item.id = m.id
		item.action = nil
		local target = math.max(1, num(m.target, 1))
		local progress = math.clamp(num(m.progress, 0), 0, target)
		item.title.Text = tostring(i) .. ". " .. tostring(m.title or m.id) .. (m.done and " ✓" or "")
		item.title.TextColor3 = (m.done or m.active or m.startable) and T.text or T.muted
		item.text.Text = tostring(m.text or "")
		item.reward.Text = rewardText(m)
		UI.SetProgress(item.fill, progress / target)
		item.reason.Text = ""
		if m.done then
			item.button.Text = "Erledigt ✓"
			UI.SetEnabled(item.button, false)
		elseif passive then
			item.button.Text = "Passiv"
			UI.SetEnabled(item.button, false)
			item.reason.Text = "Im Passiv-Modus ruht die Story."
		elseif m.active then
			if m.claimable then
				item.button.Text = "Abholen"
				item.action = "story_claim"
				UI.SetEnabled(item.button, true, T.green)
			else
				item.button.Text = MiniLocale.Number(progress) .. " / " .. MiniLocale.Number(target)
				UI.SetEnabled(item.button, false)
				item.reason.Text = "Läuft – " .. (type(st.active) == "table" and num(st.active.party, 0) > 1 and "zusammen mit deiner Party." or "du schaffst das!")
			end
		elseif locked then
			item.button.Text = "Ab Level " .. tostring(math.floor(num(st.levelNeeded, 1)))
			UI.SetEnabled(item.button, false)
			item.reason.Text = (m.current or m.startable) and ("Kapitel " .. tostring(math.floor(num(st.chapter, 1))) .. " gibt es ab Level " .. tostring(math.floor(num(st.levelNeeded, 1))) .. ". Aufträge und Nebenmissionen bringen XP!") or ""
		elseif m.startable then
			item.button.Text = "Starten"
			item.action = "story_start"
			UI.SetEnabled(item.button, true, T.green)
		else
			item.button.Text = "Später"
			UI.SetEnabled(item.button, false)
			item.reason.Text = activeTitle and ("Erst „" .. activeTitle .. "“ erledigen.") or "Die Story geht der Reihe nach."
		end
		item.reason.Visible = item.reason.Text ~= ""
	end
	refs.missionsEmpty.Visible = #missions == 0
end

---------------------------------------------------------------- Nebenmissionen
local function secondsToMidnight(): number
	local t = serverNow()
	return 86400 - (math.floor(t) % 86400)
end

local function renderSide(s: any)
	local st = story(s)
	local list = type(st.side) == "table" and st.side or {}
	local daily, legend = {}, {}
	for _, e in ipairs(list) do
		table.insert(e.legend and legend or daily, e)
	end
	local all = {}
	for _, e in ipairs(daily) do
		table.insert(all, e)
	end
	for _, e in ipairs(legend) do
		table.insert(all, e)
	end
	refs.side:Ensure(#all)
	local claimedToday = 0
	for i, e in ipairs(all) do
		local item = refs.side.items[i]
		item.id = e.id
		local target = math.max(1, num(e.target, 1))
		local progress = math.clamp(num(e.progress, 0), 0, target)
		item.title.Text = (e.legend and "★ " or "") .. tostring(e.title or e.id) .. (e.done and " ✓" or "")
		item.title.TextColor3 = e.done and T.muted or T.text
		item.text.Text = tostring(e.text or "")
		item.reward.Text = "Belohnung: " .. MiniLocale.Credits(num(e.credits, 0)) .. (num(e.xp, 0) > 0 and (" · " .. tostring(math.floor(num(e.xp, 0))) .. " XP") or "")
		UI.SetProgress(item.fill, progress / target)
		item.claimable = e.claimable == true and st.passive ~= true
		if e.done then
			item.button.Text = "Erledigt ✓"
			UI.SetEnabled(item.button, false)
			if not e.legend then
				claimedToday += 1
			end
		elseif item.claimable then
			item.button.Text = "Abholen"
			UI.SetEnabled(item.button, true, T.blue)
		else
			item.button.Text = MiniLocale.Number(progress) .. " / " .. MiniLocale.Number(target)
			UI.SetEnabled(item.button, false)
		end
	end
	refs.sideEmpty.Visible = #all == 0
	refs.sideInfo.Text = "Heute abgeholt: " .. tostring(claimedToday) .. " von " .. tostring(math.max(#daily, claimedToday)) .. " · Neue Nebenmissionen in " .. MiniLocale.Duration(secondsToMidnight())
	StoryUI.RenderDelivery()
end

function StoryUI.RenderDelivery()
	if not refs.deliveryStatus then
		return
	end
	if delivery then
		local left = math.max(0, delivery.until_ - serverNow())
		if left <= 0 then
			delivery = nil
		else
			refs.deliveryStatus.Text = "Lieferung " .. tostring(delivery.route) .. " läuft – noch " .. MiniLocale.Duration(left) .. " bis zum Ziel!"
			refs.deliveryStatus.Visible = true
			return
		end
	end
	refs.deliveryStatus.Visible = false
end

---------------------------------------------------------------- Kapitel
local function renderChapter(s: any)
	local st = story(s)
	local chapter = math.floor(num(st.chapter, 1))
	refs.storyTitle.Text = tostring(st.title or "Vom Kiesplatzhändler zum Mega-Verkäufer")
	refs.chapterTitle.Text = "Kapitel " .. tostring(chapter) .. ": " .. tostring(st.chapterTitle or "")
	refs.intro.Text = tostring(st.intro or "")
	refs.intro.Visible = refs.intro.Text ~= ""
	local count = math.max(1, math.floor(num(st.count, 1)))
	local step = math.clamp(math.floor(num(st.step, 1)), 1, count + 1)
	if st.finished == true then
		refs.chapterProgress.Text = "Story abgeschlossen – du bist der Mega-Verkäufer!"
		UI.SetProgress(refs.chapterFill, 1)
	else
		refs.chapterProgress.Text = "Mission " .. tostring(math.min(step, count)) .. " von " .. tostring(count) .. (type(st.active) == "table" and (" · läuft: „" .. tostring(st.active.title) .. "“") or "")
		UI.SetProgress(refs.chapterFill, (step - 1) / count)
	end
	if st.passive == true then
		refs.chapterNote.Text = "Passiv-Modus: Die Story ruht. Schalte ihn in den Einstellungen (Lobby) aus, wenn du weiterspielen willst."
		refs.chapterNote.Visible = true
	elseif st.locked == true then
		refs.chapterNote.Text = "Dieses Kapitel gibt es ab Level " .. tostring(math.floor(num(st.levelNeeded, 1))) .. " (du bist Level " .. tostring(math.floor(num(s.level, 1))) .. "). Bis dahin: Aufträge und Nebenmissionen bringen XP!"
		refs.chapterNote.Visible = true
	else
		refs.chapterNote.Visible = false
	end
	local earned = type(st.titleEarned) == "string" and st.titleEarned or ""
	refs.titleEarned.Text = earned ~= "" and ("Dein Titel: „" .. earned .. "“") or ""
	refs.titleEarned.Visible = earned ~= ""
	-- Kapitelübersicht (nur volle Snapshots, sticky)
	local chapters = type(st.chapters) == "table" and #st.chapters > 0 and st.chapters or lastChapters
	lastChapters = chapters
	local list = chapters or {}
	refs.chapters:Ensure(#list)
	for i, c in ipairs(list) do
		local item = refs.chapters.items[i]
		local mark = c.done and "✓ " or (c.open and "▶ " or "○ ")
		item.label.Text = mark .. "Kapitel " .. tostring(c.id) .. ": " .. tostring(c.title) .. (c.done and "" or (" (ab Level " .. tostring(c.level) .. ")"))
		item.label.TextColor3 = c.done and T.green or (c.id == chapter and T.text or T.muted)
	end
	refs.chaptersCard.Visible = #list > 0
end

---------------------------------------------------------------- Aufbau
function StoryUI.Build(page, context)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme

	local head = UI.Card(page, 1)
	head.Name = "ChapterCard"
	refs.storyTitle = UI.Small(head, "", 1)
	refs.storyTitle.Name = "StoryTitle"
	refs.chapterTitle = UI.Title(head, "", 2)
	refs.chapterTitle.Name = "ChapterTitle"
	refs.intro = UI.Label(head, "", { Name = "Intro", TextSize = 15, TextColor3 = T.muted, LayoutOrder = 3 })
	refs.chapterProgress = UI.Label(head, "", { Name = "ChapterProgress", Font = UI.FontBold, TextSize = 14, TextColor3 = T.green, LayoutOrder = 4 })
	local _, fill = UI.Progress(head, T.green, 5)
	refs.chapterFill = fill
	refs.chapterNote = UI.Label(head, "", { Name = "ChapterNote", TextSize = 14, TextColor3 = T.yellow, LayoutOrder = 6, Visible = false })
	refs.titleEarned = UI.Label(head, "", { Name = "TitleEarned", Font = UI.FontBold, TextSize = 14, TextColor3 = T.yellow, LayoutOrder = 7, Visible = false })

	local map = UI.Card(page, 2)
	map.Name = "MapHintCard"
	map.Visible = false
	UI.Title(map, "Wegweiser", 1)
	refs.mapText = UI.Small(map, "", 2)
	refs.mapText.Name = "MapText"
	refs.travelButton = UI.Button(map, "Schnellreise zum Kiesplatz", T.blue, travel, { Name = "TravelButton", LayoutOrder = 3 })
	refs.mapCard = map

	buildSaleCard(page)

	local missions = UI.Card(page, 4)
	missions.Name = "MissionsCard"
	UI.Title(missions, "Missionen", 1)
	refs.missionsEmpty = UI.Small(missions, "Keine Missionen in diesem Kapitel.", 2)
	refs.missionsEmpty.Visible = false
	refs.missions = UI.Pool(missions, missionRow)

	local side = UI.Card(page, 5)
	side.Name = "SideCard"
	UI.Title(side, "Nebenmissionen", 1)
	UI.Small(side, "Jeden Tag drei neue Aufgaben aus der Stadt (neu um 0 Uhr UTC) – dazu der Strang „Werkstatt-Legende“.", 2)
	refs.sideInfo = UI.Small(side, "", 3)
	refs.sideInfo.Name = "SideInfo"
	refs.deliveryStatus = UI.Label(side, "", { Name = "DeliveryStatus", Font = UI.FontBold, TextSize = 14, TextColor3 = T.yellow, LayoutOrder = 4, Visible = false })
	refs.sideEmpty = UI.Small(side, "Heute gibt es keine Nebenmissionen.", 5)
	refs.sideEmpty.Visible = false
	refs.side = UI.Pool(side, sideRow)

	local chapters = UI.Card(page, 6)
	chapters.Name = "ChaptersCard"
	chapters.Visible = false
	UI.Title(chapters, "Alle Kapitel", 1)
	refs.chapters = UI.Pool(chapters, chapterRow)
	refs.chaptersCard = chapters
end

---------------------------------------------------------------- Anzeige
function StoryUI.OnSnapshot(s: any)
	if type(s) ~= "table" then
		return
	end
	local st = story(s)
	-- Countdown „Nächster Kunde“ ab Snapshot-Zeit
	saleInAt, saleInBase = serverNow(), num(st.saleIn, 0)
	-- Antwort auf ein gesendetes Angebot: der Kunde ist weg oder ein anderer da
	if pendingOffer ~= nil and (type(st.sale) ~= "table" or st.sale.offer ~= pendingOffer) then
		pendingOffer = nil
	end
	latest = s
end

function StoryUI.Render(s: any)
	if type(s) ~= "table" then
		return
	end
	StoryUI.OnSnapshot(s)
	local missions = missionsFor(s)
	renderChapter(s)
	renderMapHint(s, missions)
	StoryUI.RenderSale(s)
	renderMissions(s, missions)
	renderSide(s)
end

-- mini_notice { kind = "story" | "mission", ... }
function StoryUI.OnNotice(data: any)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "story" then
		if data.event == "sale" then
			showSaleResult(data)
		elseif data.event == "delivery" then
			if data.state == "started" then
				delivery = { route = math.floor(num(data.route, 1)), until_ = serverNow() + num(data.limit, 240) }
			else
				delivery = nil
			end
			StoryUI.RenderDelivery()
		elseif data.event == "started" or data.event == "claimed" or data.event == "side_claimed" then
			lastMissions = nil -- Liste beim nächsten vollen Snapshot neu übernehmen
		end
	elseif kind == "mission" then
		-- Fortschritt sofort in die sichtbare Zeile schreiben (der Snapshot folgt)
		if refs.missions then
			for _, item in ipairs(refs.missions.items) do
				if item.root.Visible and item.id == data.id and not data.side then
					local target = math.max(1, num(data.target, 1))
					UI.SetProgress(item.fill, math.clamp(num(data.progress, 0), 0, target) / target)
				end
			end
		end
		if refs.side and data.side then
			for _, item in ipairs(refs.side.items) do
				if item.root.Visible and item.id == data.id then
					local target = math.max(1, num(data.target, 1))
					UI.SetProgress(item.fill, math.clamp(num(data.progress, 0), 0, target) / target)
				end
			end
		end
	else
		return
	end
	if UI and UI.IsOpen and UI.CurrentTab == "story" and latest then
		StoryUI.Render(latest)
	end
end

function StoryUI.OnShow()
	if latest then
		StoryUI.Render(latest)
	end
end

-- Jedes Frame bei sichtbarem Tab: Countdowns (Kunde, Tageswechsel, Lieferung) und Wegweiser einmal je Sekunde
function StoryUI.Step(dt: number?)
	tickTimer += num(dt, 1 / 60)
	if tickTimer < 1 then
		return
	end
	tickTimer = 0
	if not latest then
		return
	end
	local st = story(latest)
	if refs.saleCard and refs.saleCard.Visible and type(st.sale) ~= "table" then
		StoryUI.RenderSale(latest)
	end
	if refs.saleCard and type(st.sale) == "table" and pendingOffer ~= nil and os.clock() >= pendingUntil then
		pendingOffer = nil
		StoryUI.RenderSale(latest)
	end
	if refs.sideInfo then
		refs.sideInfo.Text = string.gsub(refs.sideInfo.Text, "Neue Nebenmissionen in .*$", "Neue Nebenmissionen in " .. MiniLocale.Duration(secondsToMidnight()))
	end
	StoryUI.RenderDelivery()
	if refs.mapCard and refs.mapCard.Visible then
		renderMapHint(latest, missionsFor(latest))
	end
end

-- Für Tests
function StoryUI.Refs()
	return refs
end

function StoryUI.Pending(): any
	return pendingOffer
end

function StoryUI.DeliveryState(): any
	return delivery
end

return StoryUI
