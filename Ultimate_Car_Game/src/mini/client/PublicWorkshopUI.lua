--!nonstrict
-- PublicWorkshopUI: Bereich "grosswerkstatt" im Minispiel-Panel (ScreenGui "Minispiele", DisplayOrder 30) – die
-- „Große Werkstatt“ am Westende der Spielermeile. Öffnet sich wie jede Station: Prompt an City.Stations.grosswerkstatt
-- bzw. City.Stations.teileankauf -> Server "mini_open" { tab = "grosswerkstatt" } -> OnShow sendet pw_open {} ->
-- Server antwortet mit mini_notice { kind = "pw", event, … Ansicht } (PublicWorkshopService.View).
-- Zwei Reiter: „Auto reparieren“ (pw_repair { car }) und „Teile verkaufen“ (pw_sell_parts { part, count }).
-- Der Client zeigt nur an und sendet Absichten; Preise, Zustand, Bonus, Abstand und Bestand prüft der Server.
-- Seiten-Schnittstelle wie die anderen Bereiche: Build(page, ctx), Render(snapshot), OnShow(), OnNotice(data), Step().
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiniLocale
do
	local ok, mod = pcall(function()
		local mini = ReplicatedStorage:WaitForChild("GarageShared", 10):WaitForChild("Mini", 10)
		return require(mini:WaitForChild("MiniLocale", 10))
	end)
	if ok and type(mod) == "table" then
		MiniLocale = mod
	end
end

local PublicWorkshopUI = {}
PublicWorkshopUI.Tab = "grosswerkstatt"
PublicWorkshopUI.NoticeKind = "pw"

local UI, Remote, T, ctx
local refs = {}
local view = nil -- letzte Ansicht vom Server
local credits = nil -- Kontostand aus dem Snapshot (aktueller als die Ansicht)
local sub = "repair" -- "repair" | "parts"
local autoFocus = true -- nach dem Öffnen einmal den passenden Reiter wählen (Server: focus)
local counts = {} -- [part] = gewählte Stückzahl
local jobEnds, jobTotal = nil, 1 -- os.clock() des Endes der laufenden Reparatur
local shownLeft = -1

local PATH_TIPS = {
	autohaus = "Tipp für Verkäufer: Lass deine Autos hier reparieren – repariert bringen sie beim Verkauf mehr Geld.",
	schrottplatz = "Tipp für Schrotthändler: Verkauf deine Altteile hier – die Große Werkstatt zahlt besser als der Schrotthändler.",
	werkstatt = "Tipp für Mechaniker: Du bekommst hier Rabatt auf jede Reparatur.",
	produktion = "Tipp: Reparierte Autos bringen beim Verkauf mehr, Altteile bringen hier gutes Geld.",
}

local function fmtCredits(n)
	if MiniLocale then
		return MiniLocale.Credits(tonumber(n) or 0)
	end
	return tostring(math.floor(tonumber(n) or 0)) .. " Cr"
end

local function money()
	if type(credits) == "number" then
		return credits
	end
	return view and tonumber(view.credits) or 0
end

local function recommended()
	local path = view and view.path or ""
	if path == "schrottplatz" then
		return "parts"
	end
	return "repair"
end

---------------------------------------------------------------- Aufbau
local function createCarItem(parent, i)
	local card = UI.Card(parent, i)
	card.Name = "CarCard"
	local row, left, right = UI.Row(card, 1)
	local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 17, LayoutOrder = 1 })
	local detail = UI.Small(left, "", 2)
	local item = { root = card, name = name, detail = detail }
	item.button = UI.Button(right, "", T.green, function()
		if item.id then
			Remote.Send("pw_repair", { car = item.id })
		end
	end, { Name = "Repair" })
	row.Name = "CarRow"
	local _, fill = UI.Progress(card, T.green, 2)
	item.bar = fill.Parent
	item.fill = fill
	return item
end

local function createPartItem(parent, i)
	local card = UI.Card(parent, i)
	card.Name = "PartCard"
	local item = { root = card }
	item.title = UI.Title(card, "", 1)
	item.info = UI.Small(card, "", 2)
	local stepper = UI.Frame(card, { Name = "Stepper", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, UI.MinTouch), LayoutOrder = 3 })
	local function step(delta)
		if not item.id then
			return
		end
		local max = item.max or 0
		local n = (counts[item.id] or 1) + delta
		counts[item.id] = math.clamp(n, math.min(1, max), math.max(1, max))
		PublicWorkshopUI.RenderParts()
	end
	item.minus = UI.Button(stepper, "−", T.card, function()
		step(-1)
	end, { Name = "Minus", Size = UDim2.new(0.2, -6, 0, UI.MinTouch), Position = UDim2.new(0, 0, 0, 0), TextSize = 22 })
	item.count = UI.Label(stepper, "1", {
		Name = "Count", AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(0.25, -6, 0, UI.MinTouch), Position = UDim2.new(0.2, 0, 0, 0),
		TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Center, Font = UI.FontBold, TextSize = 20,
	})
	item.plus = UI.Button(stepper, "+", T.card, function()
		step(1)
	end, { Name = "Plus", Size = UDim2.new(0.2, -6, 0, UI.MinTouch), Position = UDim2.new(0.45, 0, 0, 0), TextSize = 22 })
	item.all = UI.Button(stepper, "Alle", T.blue, function()
		if item.id then
			counts[item.id] = math.max(1, item.max or 1)
			PublicWorkshopUI.RenderParts()
		end
	end, { Name = "Max", Size = UDim2.new(0.35, 0, 0, UI.MinTouch), Position = UDim2.new(0.65, 0, 0, 0) })
	item.sell = UI.Button(card, "Verkaufen", T.green, function()
		if item.id and (item.max or 0) >= 1 then
			local n = math.clamp(counts[item.id] or 1, 1, item.max)
			Remote.Send("pw_sell_parts", { part = item.id, count = n })
		end
	end, { Name = "Sell", LayoutOrder = 4 })
	return item
end

function PublicWorkshopUI.Build(page, c)
	ctx = c
	UI, Remote = c.UI, c.Remote
	T = UI.Theme
	page.Name = page.Name ~= "" and page.Name or "Page_" .. PublicWorkshopUI.Tab

	local head = UI.Card(page, 1)
	head.Name = "PwHeader"
	refs.title = UI.Title(head, "Große Werkstatt", 1)
	UI.Small(head, "Eigene Autos reparieren (mehr Geld beim Verkauf) und Teile verkaufen. Jeder darf hier rein!", 2)
	refs.tip = UI.Label(head, "", { LayoutOrder = 3, TextSize = 15, TextColor3 = T.green, Name = "Tip" })
	refs.info = UI.Small(head, "Lade die Werkstatt …", 4)
	refs.info.Name = "Info"
	refs.hint = UI.Label(head, "", { LayoutOrder = 5, TextSize = 15, TextColor3 = T.yellow, Name = "Hint", Visible = false })

	local tabs = UI.Frame(page, { Name = "PwTabs", BackgroundTransparency = 1, AutomaticSize = Enum.AutomaticSize.None, Size = UDim2.new(1, 0, 0, UI.MinTouch), LayoutOrder = 2 })
	refs.tabRepair = UI.Button(tabs, "Auto reparieren", T.green, function()
		PublicWorkshopUI.ShowSub("repair")
	end, { Name = "PwTab_repair", Size = UDim2.new(0.5, -4, 0, UI.MinTouch), Position = UDim2.new(0, 0, 0, 0) })
	refs.tabParts = UI.Button(tabs, "Teile verkaufen", T.card, function()
		PublicWorkshopUI.ShowSub("parts")
	end, { Name = "PwTab_parts", Size = UDim2.new(0.5, -4, 0, UI.MinTouch), Position = UDim2.new(0.5, 4, 0, 0) })

	-- Reiter „Auto reparieren“
	local repair = UI.Frame(page, { Name = "PwRepair", BackgroundTransparency = 1, LayoutOrder = 3 })
	UI.List(repair, 10)
	refs.repair = repair
	local job = UI.Card(repair, 1)
	job.Name = "Job"
	refs.job = job
	refs.jobTitle = UI.Title(job, "In der Halle", 1)
	refs.jobName = UI.Label(job, "", { LayoutOrder = 2, Name = "JobName" })
	local _, jobFill = UI.Progress(job, T.green, 3)
	refs.jobFill = jobFill
	refs.jobFill.Name = "JobFill"
	refs.jobLeft = UI.Small(job, "", 4)
	refs.jobLeft.Name = "JobLeft"
	job.Visible = false
	refs.empty = UI.Label(repair, "", { LayoutOrder = 2, TextColor3 = T.muted, Name = "Empty", Visible = false })
	local list = UI.Frame(repair, { Name = "Cars", BackgroundTransparency = 1, LayoutOrder = 3 })
	UI.List(list, 8)
	refs.cars = UI.Pool(list, createCarItem)

	-- Reiter „Teile verkaufen“
	local parts = UI.Frame(page, { Name = "PwParts", BackgroundTransparency = 1, LayoutOrder = 4, Visible = false })
	UI.List(parts, 10)
	refs.parts = parts
	refs.partsInfo = UI.Small(parts, "", 1)
	refs.partsInfo.Name = "PartsInfo"
	local plist = UI.Frame(parts, { Name = "PartList", BackgroundTransparency = 1, LayoutOrder = 2 })
	UI.List(plist, 8)
	refs.partPool = UI.Pool(plist, createPartItem)
	refs.partsEmpty = UI.Label(parts, "", { LayoutOrder = 3, TextColor3 = T.muted, Name = "PartsEmpty", Visible = false })
	PublicWorkshopUI.ShowSub(sub)
end

---------------------------------------------------------------- Anzeige
function PublicWorkshopUI.ShowSub(which)
	if which ~= "parts" then
		which = "repair"
	end
	sub = which
	if not refs.repair then
		return
	end
	refs.repair.Visible = which == "repair"
	refs.parts.Visible = which == "parts"
	local rec = recommended()
	refs.tabRepair.Text = (rec == "repair" and view and "★ " or "") .. "Auto reparieren"
	refs.tabParts.Text = (rec == "parts" and view and "★ " or "") .. "Teile verkaufen"
	UI.SetEnabled(refs.tabRepair, true, which == "repair" and T.green or T.card)
	UI.SetEnabled(refs.tabParts, true, which == "parts" and T.green or T.card)
end

function PublicWorkshopUI.Sub()
	return sub
end

function PublicWorkshopUI.View()
	return view
end

local STATE_BUTTON = {
	working = "Läuft …",
	repaired = "Top in Schuss",
}

function PublicWorkshopUI.RenderCars()
	if not refs.cars or not view then
		return
	end
	local cars = type(view.cars) == "table" and view.cars or {}
	refs.cars:Ensure(#cars)
	local busy = type(view.job) == "table"
	for i, car in ipairs(cars) do
		local item = refs.cars.items[i]
		item.id = car.id
		item.root.Name = "Car_" .. tostring(car.id)
		item.button.Name = "Repair_" .. tostring(car.id)
		item.name.Text = tostring(car.name or "Auto")
		local state = car.state
		local detail
		if state == "repaired" then
			detail = string.format("Zustand 100 %% · Verkaufswert +%d %% (+%s)", car.bonus or 0, fmtCredits(car.gain))
		elseif state == "blocked" then
			detail = tostring(car.reason or "Gerade nicht möglich.")
		elseif state == "paid" then
			detail = string.format("Zustand %d %% · schon bezahlt – weitermachen bringt +%d %% (+%s)", car.cond or 0, car.bonus or 0, fmtCredits(car.gain))
		else
			detail = string.format("Zustand %d %% → 100 %% · Verkaufswert +%d %% (+%s)", car.cond or 0, car.bonus or 0, fmtCredits(car.gain))
		end
		item.detail.Text = detail
		local text, enabled, color = "", false, T.green
		if state == "ready" then
			text = "Reparieren " .. fmtCredits(car.cost)
			enabled = not busy and money() >= (car.cost or math.huge)
			if not busy and money() < (car.cost or 0) then
				text = "Zu teuer (" .. fmtCredits(car.cost) .. ")"
			end
		elseif state == "paid" then
			text, enabled, color = "Weitermachen", not busy, T.blue
		elseif state == "working" then
			text = STATE_BUTTON.working
		elseif state == "repaired" then
			text = STATE_BUTTON.repaired
		else
			text = "Nicht möglich"
		end
		item.button.Text = text
		UI.SetEnabled(item.button, enabled, color)
		item.bar.Visible = state ~= "blocked"
		UI.SetProgress(item.fill, (state == "repaired") and 1 or ((car.cond or 0) / 100))
	end
	if #cars == 0 then
		refs.empty.Text = "Du hast noch kein eigenes Auto. Kauf eins im Autohaus – repariert bringt es beim Verkauf mehr. Oder verkaufe hier deine Altteile!"
	end
	refs.empty.Visible = #cars == 0
end

function PublicWorkshopUI.RenderParts()
	if not refs.partPool or not view then
		return
	end
	local parts = type(view.parts) == "table" and view.parts or {}
	refs.partPool:Ensure(#parts)
	for i, p in ipairs(parts) do
		local item = refs.partPool.items[i]
		item.id = p.id
		item.max = math.max(0, math.floor(tonumber(p.max) or 0))
		item.root.Name = "Part_" .. tostring(p.id)
		item.sell.Name = "Sell_" .. tostring(p.id)
		local n = counts[p.id]
		if type(n) ~= "number" then
			n = item.max
		end
		n = math.clamp(n, math.min(1, item.max), math.max(1, item.max))
		counts[p.id] = n
		local price = tonumber(p.price) or 0
		item.title.Text = tostring(p.name or p.id)
		item.info.Text = string.format("Im Lager: %d · %s je Stück", tonumber(p.have) or 0, fmtCredits(price))
		item.count.Text = tostring(item.max >= 1 and n or 0)
		UI.SetEnabled(item.minus, item.max >= 1 and n > 1, T.card)
		UI.SetEnabled(item.plus, item.max >= 1 and n < item.max, T.card)
		UI.SetEnabled(item.all, item.max >= 1 and n < item.max, T.blue)
		if item.max >= 1 then
			item.sell.Text = string.format("%d verkaufen (+%s)", n, fmtCredits(math.floor(n * price + 0.5)))
		elseif (tonumber(p.have) or 0) <= 0 then
			item.sell.Text = "Keine " .. tostring(p.name or "Teile") .. " im Lager"
		else
			item.sell.Text = "Heute nichts mehr"
		end
		UI.SetEnabled(item.sell, item.max >= 1, T.green)
	end
	local left = tonumber(view.dailyLeft) or 0
	local bonus = tonumber(view.partsBonus) or 0
	refs.partsInfo.Text = string.format("Heute nimmt der Ankauf noch %d Teile von dir an%s. Jeder Verkauf füllt den Teile-Vorrat – damit werden Reparaturen für alle billiger.",
		left, bonus > 0 and string.format(" (+%d %% für dich)", bonus) or "")
	refs.partsEmpty.Visible = #parts == 0
	refs.partsEmpty.Text = "Gerade werden keine Teile angekauft."
end

local function renderHeader()
	if not refs.info or not view then
		return
	end
	refs.title.Text = tostring(view.title or "Große Werkstatt")
	refs.tip.Text = PATH_TIPS[view.path or ""] or "Tipp: Repariere deine Autos vor dem Verkauf – oder verkaufe hier deine Altteile."
	local bits = { string.format("Teile-Vorrat: %d/%d", tonumber(view.stock) or 0, tonumber(view.stockCap) or 0) }
	if (tonumber(view.stockDiscount) or 0) > 0 then
		table.insert(bits, string.format("Vorrat-Rabatt −%d %%", view.stockDiscount))
	end
	if (tonumber(view.pathDiscount) or 0) > 0 then
		table.insert(bits, string.format("dein Rabatt −%d %%", view.pathDiscount))
	end
	table.insert(bits, string.format("Bonus bis +%d %%", tonumber(view.maxBonus) or 0))
	refs.info.Text = table.concat(bits, " · ")
	local hint = ""
	if view.hasCity == false then
		hint = "Die Große Werkstatt steht in der Open World am Westende der Spielermeile."
	elseif sub == "repair" and not view.nearRepair then
		hint = "Du bist nicht an der Großen Werkstatt. Fahr zum Westende der Spielermeile, um zu reparieren."
	elseif sub == "parts" and not view.nearParts then
		hint = "Zum Verkaufen an den Schalter „Teile-Ankauf“ neben der Halle gehen."
	end
	refs.hint.Text = hint
	refs.hint.Visible = hint ~= ""
end

local function renderJob()
	if not refs.job then
		return
	end
	local job = view and view.job
	refs.job.Visible = type(job) == "table"
	if type(job) == "table" then
		refs.jobName.Text = tostring(job.name or "Auto") .. " wird repariert – bleib in der Nähe!"
	end
	shownLeft = -1
	PublicWorkshopUI.Step()
end

function PublicWorkshopUI.RenderAll()
	if not view then
		return
	end
	renderHeader()
	PublicWorkshopUI.ShowSub(sub)
	renderJob()
	PublicWorkshopUI.RenderCars()
	PublicWorkshopUI.RenderParts()
end

-- Snapshot (MiniClient: bei offenem Bereich): nur der Kontostand für „Zu teuer“
function PublicWorkshopUI.Render(s)
	if type(s) == "table" and type(s.credits) == "number" then
		credits = s.credits
	end
	if view then
		PublicWorkshopUI.RenderCars()
	end
end

-- mini_notice { kind = "pw", event = "open" | "started" | "resumed" | "done" | "paused" | "aborted" | "sold" | "rejected", … }
function PublicWorkshopUI.OnNotice(data)
	if type(data) ~= "table" or data.kind ~= PublicWorkshopUI.NoticeKind then
		return
	end
	view = data
	if type(data.credits) == "number" then
		credits = data.credits
	end
	if type(data.job) == "table" then
		jobTotal = math.max(1, tonumber(data.job.total) or 1)
		jobEnds = os.clock() + math.max(0, tonumber(data.job.left) or 0)
	else
		jobEnds = nil
	end
	if autoFocus then
		autoFocus = false
		sub = data.focus == "parts" and "parts" or "repair"
	end
	if data.event == "sold" and type(data.part) == "string" then
		counts[data.part] = nil -- nach dem Verkauf wieder „alle“ vorschlagen
	end
	PublicWorkshopUI.RenderAll()
end

function PublicWorkshopUI.OnShow()
	autoFocus = true
	if Remote then
		Remote.Send("pw_open", {})
	end
end

-- Pro Frame (sichtbarer Bereich): Fortschritt der laufenden Reparatur lokal herunterzählen
function PublicWorkshopUI.Step()
	if not refs.jobFill or not jobEnds then
		return
	end
	local left = math.max(0, jobEnds - os.clock())
	UI.SetProgress(refs.jobFill, 1 - left / jobTotal)
	local whole = math.ceil(left)
	if whole == shownLeft then
		return
	end
	shownLeft = whole
	refs.jobLeft.Text = whole > 0 and string.format("Noch %d s – nicht weggehen, sonst pausiert die Reparatur.", whole) or "Wird abgeschlossen …"
end

-- Nur für Tests: Zustand zurücksetzen
function PublicWorkshopUI._Reset()
	view, credits, sub, autoFocus, counts, jobEnds, shownLeft = nil, nil, "repair", true, {}, nil, -1
end

return PublicWorkshopUI
