-- BuildingsUI: Tab „Gebäude“ (buildings) der Open World (docs/PHASE4_CONTRACT.md §5, §7, §10, §11).
-- Vier Gebäude-Karten (Werkstatt = Bühnen des Grundstücks, Autohaus, Schrottplatz, Produktion): Stufe, Wirkung,
-- nächste Stufe (Kosten, Bauzeit, Level), Knöpfe „Bauen“ (ow_build {typ}) und „Abholen“ (ow_collect {typ}),
-- Countdown der Baustelle (lokal aus remaining + os.clock, der Snapshot kommt 1×/s nach), Perk-Zeile.
-- Dazu der Passiv-Modus (ow_passive {on}) mit Erklärung. Der Client zeigt nur an und sendet Absichten.
-- Erwartete Snapshot-Felder (OWService.SnapshotFields / OWRules.Summary):
--   s.ow = { buildings { [typ] = { name, stage, built, maxStage, readyAt, remaining, building, yield = false | { credits, scrap,
--            parts, car, hours }, effect = false | { credits, scrap, parts, partsEveryHours, partsPerPack, car, carEveryHours },
--            next = false | { stage, cost, seconds, level, ok, reason, effect }, perk } }, passive, perks, capHours }
-- Schnittstelle wie die anderen Bereiche: Build(page, ctx), Render(s), OnShow(), OnNotice(data), Step().
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(Mini:WaitForChild("GameConfig"))
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local BuildingsUI = {}

local OW = GameConfig.OW
local UI, Remote, T, ctx
local refs = {}
local latest = nil
local snapAt = 0 -- os.clock beim letzten Snapshot (lokaler Countdown)
local lastTick = 0

local REASONS = {
	werkstatt = "Ausbau am Hallenanbau auf dem Grundstück",
	max = "Höchste Stufe erreicht",
	building = "Wird gerade gebaut",
	level = "Level fehlt",
	credits = "Nicht genug Credits",
	unknown = "Nicht verfügbar",
	ok = "",
}

local function num(v: any, default: number): number
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge and v or default
end

local function toast(text: string)
	if ctx and type(ctx.Toast) == "function" and text ~= "" then
		ctx.Toast(text)
	end
end

local function pct(factor: any): string
	local v = (num(factor, 1) - 1) * 100
	return "+" .. MiniLocale.Decimal(v, 0) .. " %"
end

local function hours(h: any): string
	local v = num(h, 0)
	if v == math.floor(v) then
		return tostring(v) .. " Std."
	end
	return MiniLocale.Decimal(v, 1) .. " Std."
end

-- Wirkung einer Stufe als Satz
local function effectText(typ: string, e: any): string
	if type(e) ~= "table" then
		return ""
	end
	local parts = {}
	if num(e.credits, 0) > 0 then
		table.insert(parts, MiniLocale.Credits(e.credits) .. " je Stunde")
	end
	if num(e.scrap, 0) > 0 then
		table.insert(parts, MiniLocale.Scrap(e.scrap) .. " je Stunde")
	end
	if num(e.parts, 0) > 0 then
		table.insert(parts, tostring(e.parts) .. " Altteile je Stunde")
	end
	if num(e.partsEveryHours, 0) > 0 then
		table.insert(parts, "alle " .. hours(e.partsEveryHours) .. " ein Paket mit " .. tostring(num(e.partsPerPack, 0)) .. " Altteilen")
	end
	if e.car == true then
		table.insert(parts, "alle " .. hours(e.carEveryHours) .. " ein Auto-Gutschein (Kompaktwagen)")
	end
	if #parts == 0 then
		return ""
	end
	return "Bringt: " .. table.concat(parts, ", ") .. "."
end

local function perkText(typ: string, factor: any): string
	local p = OW.Perks and OW.Perks[typ] or nil
	if not p then
		return ""
	end
	local capPct = MiniLocale.Decimal(num(p.cap, 0) * 100, 0)
	if typ == "werkstatt" then
		return p.label .. " " .. pct(factor) .. " (je Hebebühne +" .. MiniLocale.Decimal(num(p.per, 0) * 100, 0) .. " %, höchstens +" .. capPct .. " %)"
	end
	return p.label .. " " .. pct(factor) .. " (je Stufe +" .. MiniLocale.Decimal(num(p.per, 0) * 100, 0) .. " %, höchstens +" .. capPct .. " %)"
end

local function yieldText(y: any): string
	if type(y) ~= "table" then
		return ""
	end
	local parts = {}
	if num(y.credits, 0) > 0 then
		table.insert(parts, MiniLocale.Credits(y.credits))
	end
	if num(y.scrap, 0) > 0 then
		table.insert(parts, MiniLocale.Scrap(y.scrap))
	end
	if num(y.parts, 0) > 0 then
		table.insert(parts, tostring(y.parts) .. " Altteile")
	end
	if y.car and y.car ~= false then
		table.insert(parts, "1 Auto-Gutschein")
	end
	if #parts == 0 then
		return "Noch nichts abzuholen – die Anlage arbeitet."
	end
	return "Abholbereit: " .. table.concat(parts, ", ") .. "."
end

---------------------------------------------------------------- Karten
local function buildingCard(page, typ: string, order: number)
	local b = OW.Buildings[typ]
	local card = UI.Card(page, order)
	card.Name = "Building_" .. typ
	local item = { root = card, typ = typ }
	item.title = UI.Title(card, b and b.name or typ, 1)
	item.title.Name = "Title"
	item.desc = UI.Small(card, b and b.desc or "", 2)
	item.stage = UI.Label(card, "", { Name = "Stage", Font = UI.FontBold, TextSize = 16, LayoutOrder = 3 })
	item.effect = UI.Small(card, "", 4)
	item.effect.Name = "Effect"
	item.perk = UI.Small(card, "", 5)
	item.perk.Name = "Perk"
	local _, fill = UI.Progress(card, T.yellow, 6)
	item.fill = fill
	item.countdown = UI.Label(card, "", { Name = "Countdown", LayoutOrder = 7 })
	item.yield = UI.Label(card, "", { Name = "Yield", LayoutOrder = 8 })
	item.collectButton = UI.Button(card, "Abholen", T.green, function()
		Remote.Send("ow_collect", { typ = typ })
	end, { Name = "CollectButton", LayoutOrder = 9 })
	item.next = UI.Label(card, "", { Name = "Next", LayoutOrder = 10 })
	item.buildButton = UI.Button(card, "Bauen", T.blue, function()
		if item.buildOk then
			Remote.Send("ow_build", { typ = typ })
		elseif item.buildReason and item.buildReason ~= "" then
			toast(item.buildReason)
		end
	end, { Name = "BuildButton", LayoutOrder = 11 })
	return item
end

local function renderBuilding(item, data: any, capHours: number)
	local typ = item.typ
	local b = OW.Buildings[typ]
	local name = type(data) == "table" and data.name or (b and b.name) or typ
	if type(data) ~= "table" then
		item.stage.Text = "Noch keine Daten."
		item.effect.Text = ""
		item.perk.Text = ""
		UI.SetProgress(item.fill, 0)
		item.fill.Parent.Visible = false
		item.countdown.Visible = false
		item.yield.Visible = false
		item.collectButton.Visible = false
		item.next.Text = ""
		item.buildButton.Visible = false
		return
	end
	local built = num(data.built, 0)
	local stage = num(data.stage, 0)
	local maxStage = num(data.maxStage, OW.MaxStage)
	local building = data.building == true
	if typ == "werkstatt" then
		item.stage.Text = "Stufe " .. tostring(built) .. "/" .. tostring(maxStage) .. " (Hebebühnen)"
	elseif built <= 0 and not building then
		item.stage.Text = "Noch nicht gebaut"
	elseif building then
		item.stage.Text = "Stufe " .. tostring(built) .. "/" .. tostring(maxStage) .. " · Baustelle: Stufe " .. tostring(stage)
	else
		item.stage.Text = "Stufe " .. tostring(built) .. "/" .. tostring(maxStage)
	end
	local eff = effectText(typ, data.effect)
	item.effect.Text = eff
	item.effect.Visible = eff ~= ""
	item.perk.Text = perkText(typ, data.perk)
	item.perk.Visible = item.perk.Text ~= ""

	-- Baustelle: Countdown (lokal weitergezählt)
	item.remaining = num(data.remaining, 0)
	item.seconds = type(data.next) == "table" and num(data.next.seconds, 0) or 0
	item.fill.Parent.Visible = building
	item.countdown.Visible = building
	if building then
		item.countdown.Text = "Fertig in " .. MiniLocale.Duration(item.remaining)
		local total = 0
		local st = b and b.Stages and b.Stages[stage] or nil
		total = st and num(st.buildSeconds, 0) or 0
		UI.SetProgress(item.fill, total > 0 and 1 - item.remaining / total or 0)
	end

	-- Erträge
	local hasYield = type(data.yield) == "table"
	item.yield.Visible = typ ~= "werkstatt" and built > 0
	item.yield.Text = hasYield and yieldText(data.yield) or ""
	if typ ~= "werkstatt" and built > 0 and hasYield then
		local y = data.yield
		local any = num(y.credits, 0) > 0 or num(y.scrap, 0) > 0 or num(y.parts, 0) > 0 or (y.car and y.car ~= false)
		item.collectButton.Visible = true
		item.collectButton.Text = any and "Abholen" or ("Abholen (sammelt bis " .. tostring(capHours) .. " Std.)")
		UI.SetEnabled(item.collectButton, any, T.green)
	else
		item.collectButton.Visible = false
	end

	-- Nächste Stufe
	local nx = type(data.next) == "table" and data.next or nil
	if typ == "werkstatt" then
		item.next.Text = built >= maxStage and "Alle Hebebühnen gebaut." or "Nächste Bühne: Hallenanbau auf deinem Grundstück (E am Schild)."
		item.buildButton.Visible = false
	elseif nx then
		local lines = { "Stufe " .. tostring(nx.stage) .. ": " .. MiniLocale.Credits(nx.cost) .. " · Bauzeit " .. MiniLocale.Duration(nx.seconds) .. " · ab Level " .. tostring(nx.level) }
		local e2 = effectText(typ, nx.effect)
		if e2 ~= "" then
			table.insert(lines, e2)
		end
		item.next.Text = table.concat(lines, "\n")
		item.buildButton.Visible = true
		item.buildOk = nx.ok == true
		item.buildReason = REASONS[nx.reason] or REASONS.unknown
		if nx.reason == "level" then
			item.buildReason = "Ab Level " .. tostring(nx.level) .. ": " .. name .. " Stufe " .. tostring(nx.stage) .. "."
		elseif nx.reason == "credits" then
			item.buildReason = "Nicht genug Credits: " .. name .. " Stufe " .. tostring(nx.stage) .. " kostet " .. MiniLocale.Credits(nx.cost) .. "."
		elseif nx.reason == "building" then
			item.buildReason = name .. " wird gerade gebaut."
		end
		local label = built <= 0 and "Bauen" or "Ausbauen auf Stufe " .. tostring(nx.stage)
		if nx.reason == "building" then
			label = "Baustelle läuft"
		elseif nx.reason == "level" then
			label = "Ab Level " .. tostring(nx.level)
		elseif nx.reason == "credits" then
			label = "Es fehlen Credits"
		end
		item.buildButton.Text = label
		UI.SetEnabled(item.buildButton, item.buildOk, T.blue)
	else
		item.next.Text = "Höchste Stufe erreicht."
		item.buildButton.Visible = false
	end
end

---------------------------------------------------------------- Aufbau
function BuildingsUI.Build(page, c)
	ctx = c
	UI, Remote = c.UI, c.Remote
	T = UI.Theme
	refs.page = page

	local head = UI.Card(page, 1)
	head.Name = "HeadCard"
	UI.Title(head, "Gebäude auf deinem Grundstück", 1)
	refs.headText = UI.Small(head, "Jedes Gebäude verdient für dich, auch wenn du nicht da bist (höchstens " .. tostring(OW.PassiveCapHours) .. " Stunden am Stück – dann abholen!). Die Bauzeit läuft auch weiter, wenn du offline bist. Jeder Karriereweg bringt einen Vorteil in der Open World (höchstens +25 %).", 2)

	refs.items = {}
	for i, typ in ipairs(OW.Types) do
		refs.items[typ] = buildingCard(page, typ, 10 + i)
	end

	local passive = UI.Card(page, 30)
	passive.Name = "PassiveCard"
	UI.Title(passive, "Passiv-Modus", 1)
	UI.Small(passive, "Im Passiv-Modus schaust du nur zu und handelst: keine Missionen, keine Story, keine Auktionen. Deine Gebäude und Tuning-Projekte verdienen trotzdem weiter. Gut, wenn du nur entspannt durch die Stadt fahren willst.", 2)
	refs.passiveState = UI.Label(passive, "", { Name = "PassiveState", Font = UI.FontBold, TextSize = 16, LayoutOrder = 3 })
	refs.passiveButton = UI.Button(passive, "Passiv-Modus einschalten", T.blue, function()
		local on = latest and type(latest.ow) == "table" and latest.ow.passive == true
		Remote.Send("ow_passive", { on = not on })
	end, { Name = "PassiveButton", LayoutOrder = 4 })
	BuildingsUI.Render(latest)
end

function BuildingsUI.Render(s)
	if type(s) == "table" then
		latest = s
		snapAt = os.clock()
	end
	if not refs.items then
		return
	end
	local ow = latest and type(latest.ow) == "table" and latest.ow or nil
	local buildings = ow and type(ow.buildings) == "table" and ow.buildings or {}
	local capHours = ow and num(ow.capHours, OW.PassiveCapHours) or OW.PassiveCapHours
	for typ, item in pairs(refs.items) do
		renderBuilding(item, buildings[typ], capHours)
	end
	local on = ow and ow.passive == true
	refs.passiveState.Text = on and "Passiv-Modus ist AN." or "Passiv-Modus ist aus."
	refs.passiveButton.Text = on and "Passiv-Modus ausschalten" or "Passiv-Modus einschalten"
	refs.passiveButton:SetAttribute("baseColor", on and T.yellow or T.blue)
	refs.passiveButton.BackgroundColor3 = on and T.yellow or T.blue
end

function BuildingsUI.OnShow()
	BuildingsUI.Render(latest)
end

-- Baustellen-Countdown zwischen zwei Snapshots lokal weiterzählen (1×/s)
function BuildingsUI.Step()
	if not refs.items then
		return
	end
	local t = os.clock()
	if t - lastTick < 1 then
		return
	end
	lastTick = t
	local elapsed = t - snapAt
	for _, item in pairs(refs.items) do
		if item.countdown.Visible and item.remaining then
			local remaining = math.max(0, item.remaining - elapsed)
			item.countdown.Text = remaining > 0 and ("Fertig in " .. MiniLocale.Duration(math.ceil(remaining))) or "Gleich fertig …"
		end
	end
end

function BuildingsUI.OnNotice(data)
	if type(data) ~= "table" then
		return
	end
	if data.kind == "ow_ready" then
		toast((data.name or "Gebäude") .. " Stufe " .. tostring(data.stage or 1) .. " ist fertig!")
	end
	if data.kind == "ow_ready" or data.kind == "ow_build" or data.kind == "ow_collect" or data.kind == "ow_passive" then
		BuildingsUI.Render(latest)
	end
end

-- Für Tests
function BuildingsUI.Items()
	return refs.items
end

return BuildingsUI
