-- ParkingUI: Parkplatz-Chaos als 2D-Rätsel. Die Lösung prüft der Server.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))

local ParkingUI = {}

local UI, Remote, T
local refs = {}

function ParkingUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Parkplatz-Chaos", 1)
	UI.Small(card, "Das gelbe Auto 🚘 muss zur Ausfahrt: erst nach rechts, dann nach unten. Tippe blockierende Autos an, um sie wegzufahren, dann das gelbe Auto. Ist der Weg noch blockiert, gibt es Blechschaden und die Serie endet.", 2)
	refs.info = UI.Small(card, "", 3)

	local holder = UI.Frame(card, { BackgroundTransparency = 1, LayoutOrder = 4 })
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(360, math.huge)
	limit.Parent = holder
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / Config.ParkingSize, -6, 0, 64)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder
	refs.cells = {}
	for cell = 0, Config.ParkingSize * Config.ParkingSize - 1 do
		refs.cells[cell] = UI.Button(holder, "", T.panel, function()
			Remote.Send("parking_tap", { cell = cell })
		end, { LayoutOrder = cell, TextSize = 26, TextColor3 = T.text })
	end
	refs.status = UI.Label(card, "", { LayoutOrder = 5 })
	refs.new = UI.Button(card, "Neue Runde", T.accent2, function()
		Remote.Send("parking_new")
	end, { LayoutOrder = 6 })
end

function ParkingUI.Render(s)
	local pk = s.parking
	refs.info.Text = string.format("Serie: %d · Beste Serie: %d · Auftragsqualität ×%s (höchstens ×%s)", pk.streak, pk.best, (string.format("%.2f", pk.customerBonus):gsub("%.", ",")), (string.format("%.2f", Config.CustomerBonusCap):gsub("%.", ",")))
	local pz = pk.puzzle
	local cars, path = {}, {}
	if pz then
		for _, c in ipairs(pz.cars) do
			cars[c] = true
		end
		for _, c in ipairs(pz.path) do
			path[c] = true
		end
	end
	for cell, b in pairs(refs.cells) do
		local text, color = "", T.panel
		if pz and cell == pz.exit then
			text, color = "🚪", T.line
		elseif pz and cars[cell] then
			text = cell == pz.target and "🚘" or "🚙"
			color = cell == pz.target and T.warn or (path[cell] and T.danger or T.panel2)
		elseif pz and path[cell] then
			color = Color3.fromRGB(30, 45, 60)
		end
		b.Text = text
		b.BackgroundColor3 = color
		b:SetAttribute("disabled", not (pz and cars[cell] and not pz.solved and not pz.crashed))
	end
	if not pz then
		refs.status.Text = "Starte eine neue Runde."
	elseif pz.solved then
		refs.status.Text = "Geschafft in " .. pz.moves .. " Zügen! Serie " .. pk.streak .. "."
	elseif pz.crashed then
		refs.status.Text = "Blechschaden! Die Serie ist beendet."
	else
		refs.status.Text = pz.moves .. " Züge · " .. (pz.blocked and "Weg noch blockiert (rot markiert)" or "Weg frei – jetzt das gelbe Auto!")
	end
	refs.new.Text = (pz and not pz.solved and not pz.crashed and pz.moves > 0) and "Neue Runde (beendet die Serie)" or "Neue Runde"
end

return ParkingUI
