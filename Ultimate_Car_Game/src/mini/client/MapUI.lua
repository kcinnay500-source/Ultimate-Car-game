-- MapUI: Schnellreise zu allen Ankunftspunkten der Stadt (Workspace.City.Arrivals) und zur eigenen Werkstatt.
-- Sendet nur den Schlüssel (mini_travel {key}); Ziel, Reichweite und Abklingzeit (3 s) prüft der Server.
-- Fehlt die Stadt (z. B. noch nicht geladen), bleibt nur "Eigene Werkstatt".
local Players = game:GetService("Players")

local MapUI = {}

local UI, Remote, T, ctx
local refs = {}
local dirty = true
local watched = nil -- beobachteter Arrivals-Ordner
local cooldownUntil = 0
local COOLDOWN = 3

-- Anzeigenamen bekannter Schlüssel (Ankunftspunkte dürfen eigene Namen über das Attribut DisplayName tragen)
local NAMES = {
	workshop = "Eigene Werkstatt",
	home = "Eigene Werkstatt",
	press = "Schrottpresse",
	tuning = "Tuning-Garage",
	scrapyard = "Schrottplatz",
	quiz = "Mechaniker-Quiz",
	parking = "Parkplatz",
	goals = "Ziele-Tafel",
	leaderboard = "Bestenliste",
	shop = "Game-Pass-Laden",
	map = "Stadtplan",
	overview = "Minispiel-Zentrale",
	dealer = "Autohaus",
	auction = "Auktion",
	arcade = "Spielhalle",
	spawn = "Stadtplatz",
	center = "Stadtzentrum",
	plaza = "Stadtplatz",
	-- CITY_SPEC §7 (weitere Ankunftspunkte der Stadt)
	hub = "Minispiel-Zentrale",
	carwash = "Waschanlage",
	park = "Stadtpark",
	track = "Teststrecke",
	scrapyard_gate = "Schrottplatz-Tor",
	kiesplatz = "Kiesplatz (Gebrauchtwagen)", -- PHASE4_CONTRACT §7: Story-Stand am Stadtrand
	scrap_trader = "Schrotthändler",
	dyno = "Leistungsprüfstand",
	testdrive = "Probefahrt",
	meile_map = "Spielermeile",
}
MapUI.Names = NAMES
MapUI.FallbackName = "Weiteres Reiseziel"

local warnedKeys = {}

local function displayName(inst)
	for _, attr in ipairs({ "DisplayName", "Label", "Title" }) do
		local v = inst:GetAttribute(attr)
		if type(v) == "string" and v ~= "" then
			return v
		end
	end
	local known = NAMES[inst.Name]
	if known then
		return known
	end
	-- Nie den rohen (englischen/internen) Schlüssel zeigen; Worldgen soll DisplayName setzen.
	if not warnedKeys[inst.Name] then
		warnedKeys[inst.Name] = true
		warn("[MapUI] Ankunftspunkt ohne deutschen Namen (Attribut DisplayName fehlt): " .. inst.Name)
	end
	return MapUI.FallbackName
end

local function positionOf(inst)
	if inst:IsA("BasePart") then
		return inst.Position
	elseif inst:IsA("Model") then
		return inst:GetPivot().Position
	end
	return nil -- der Server reist nur zu Parts und Models
end

local function arrivalsFolder()
	local city = workspace:FindFirstChild("City")
	return city and city:FindFirstChild("Arrivals")
end

local function watch(folder)
	if watched == folder then
		return
	end
	watched = folder
	if refs.conns then
		for _, c in ipairs(refs.conns) do
			c:Disconnect()
		end
	end
	refs.conns = {}
	if folder then
		table.insert(refs.conns, folder.ChildAdded:Connect(function()
			dirty = true
		end))
		table.insert(refs.conns, folder.ChildRemoved:Connect(function()
			dirty = true
		end))
	end
end

-- Liste der Ziele: eigene Werkstatt zuerst, dann die Ankunftspunkte (Attribut Order, sonst alphabetisch)
function MapUI.Destinations()
	local list = { { key = "workshop", name = NAMES.workshop, sub = "Zurück in deine eigene Werkstatt.", order = -1 } }
	local folder = arrivalsFolder()
	watch(folder)
	if folder then
		local seen = { workshop = true }
		local found = {}
		for _, child in ipairs(folder:GetChildren()) do
			if not seen[child.Name] and positionOf(child) then
				seen[child.Name] = true
				local order = child:GetAttribute("Order")
				local district = child:GetAttribute("District")
				local desc = child:GetAttribute("Description")
				table.insert(found, {
					key = child.Name, name = displayName(child), inst = child,
					order = type(order) == "number" and order or 1000,
					sub = (type(desc) == "string" and desc) or (type(district) == "string" and ("Viertel: " .. district)) or "",
				})
			end
		end
		table.sort(found, function(a, b)
			if a.order ~= b.order then
				return a.order < b.order
			end
			return a.name < b.name
		end)
		for _, d in ipairs(found) do
			table.insert(list, d)
		end
	end
	return list, folder ~= nil
end

local function travel(key)
	if os.clock() < cooldownUntil then
		return
	end
	cooldownUntil = os.clock() + COOLDOWN
	Remote.Send("mini_travel", { key = key })
	-- Nach dem Abschicken das Panel schließen, damit der Spieler den neuen Ort sieht
	if ctx.Close then
		ctx.Close()
	end
end

function MapUI.Build(page, context)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local head = UI.Card(page, 1)
	UI.Title(head, "Schnellreise", 1)
	UI.Small(head, "Reise sofort zu jedem Ort der Stadt oder zurück in deine Werkstatt. Zwischen zwei Reisen liegen 3 Sekunden.", 2)
	refs.status = UI.Label(head, "", { LayoutOrder = 3, TextColor3 = T.yellow, Visible = false })

	local list = UI.Card(page, 2)
	UI.Title(list, "Ziele", 1)
	refs.rows = UI.Pool(list, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local item = { root = row, name = name, sub = sub }
		item.button = UI.Button(right, "Reisen", T.blue, function()
			if item.key then
				travel(item.key)
			end
		end)
		return item
	end)
end

function MapUI.Refresh()
	if not refs.rows then
		return
	end
	local list, hasCity = MapUI.Destinations()
	dirty = false
	refs.status.Visible = not hasCity
	refs.status.Text = "Die Stadt wird noch geladen …"
	local char = Players.LocalPlayer and Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	refs.rows:Ensure(#list)
	for i, d in ipairs(list) do
		local item = refs.rows.items[i]
		item.key = d.key
		item.name.Text = d.name
		local here = false
		if root and d.inst then
			local pos = positionOf(d.inst)
			here = pos ~= nil and (pos - root.Position).Magnitude < 25
		end
		item.sub.Text = here and "Du bist hier." or d.sub
		item.sub.Visible = item.sub.Text ~= ""
		item.button.Text = here and "Hier" or "Reisen"
		UI.SetEnabled(item.button, not here, T.blue)
	end
end

function MapUI.OnShow()
	MapUI.Refresh()
end

function MapUI.Render(_)
	MapUI.Refresh()
end

-- Leichtes Nachziehen, falls die Stadt nach dem Öffnen erscheint
function MapUI.Step()
	if dirty or (watched == nil and arrivalsFolder() ~= nil) then
		MapUI.Refresh()
	end
end

return MapUI
