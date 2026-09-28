-- ParkingUI: Parkplatz-Chaos als 2D-Rätsel. Die Lösung prüft der Server (mini_parking_tap).
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(Mini:WaitForChild("MiniConfig"))

local ParkingUI = {}

local UI, Remote, T
local refs = {}
local SIZE = MiniConfig.ParkingSize or 4

local function dec(n)
	return (string.format("%.2f", n or 0):gsub("%.", ","))
end

function ParkingUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Parkplatz-Chaos", 1)
	UI.Small(card, "Dein Auto (gelb) muss zur Ausfahrt: erst nach rechts, dann nach unten. Tippe blockierende Autos an, um sie wegzufahren, dann dein Auto. Ist der Weg noch blockiert, gibt es Blechschaden und die Serie endet.", 2)
	refs.info = UI.Small(card, "", 3)

	local holder = UI.Frame(card, { Name = "Grid", BackgroundTransparency = 1, LayoutOrder = 4 })
	local limit = Instance.new("UISizeConstraint")
	limit.MaxSize = Vector2.new(360, math.huge)
	limit.Parent = holder
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.new(1 / SIZE, -6, 0, 64)
	grid.CellPadding = UDim2.new(0, 6, 0, 6)
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = holder
	refs.cells = {}
	for cell = 0, SIZE * SIZE - 1 do
		refs.cells[cell] = UI.Button(holder, "", T.bg, function()
			Remote.Send("mini_parking_tap", { cell = cell })
		end, { Name = "Cell" .. cell, LayoutOrder = cell, TextSize = 12 })
	end
	refs.status = UI.Label(card, "", { LayoutOrder = 5 })
	refs.new = UI.Button(card, "Neue Runde", T.blue, function()
		Remote.Send("mini_parking_new")
	end, { LayoutOrder = 6 })
end

function ParkingUI.Render(s)
	local pk = s.parking
	if not pk then
		return
	end
	local paid = (pk.paidLeft or 0) > 0
	refs.info.Text = string.format(
		"Serie: %d · Beste Serie: %d · Auftragsqualität ×%s (höchstens ×%s) · %s",
		pk.streak or 0, pk.best or 0, dec(pk.customerBonus or 1), dec(MiniConfig.CustomerBonusCap or 1.7),
		paid and string.format("Nächste Lösung: %d Cr (heute noch %d bezahlt)", pk.nextReward or 0, pk.paidLeft or 0)
			or "Heute keine Credits mehr, die Serie zählt weiter"
	)
	local pz = pk.puzzle
	local cars, path = {}, {}
	if pz then
		for _, c in ipairs(pz.cars or {}) do
			cars[c] = true
		end
		for _, c in ipairs(pz.path or {}) do
			path[c] = true
		end
	end
	for cell, b in pairs(refs.cells) do
		local text, color, textColor = "", T.bg, T.text
		if pz and cell == pz.exit then
			text, color, textColor = "AUSFAHRT", T.line, T.muted
		elseif pz and cars[cell] then
			if cell == pz.target then
				text, color, textColor = "DEIN AUTO", T.yellow, T.bg
			else
				text, color = "AUTO", path[cell] and T.red or T.card
			end
		elseif pz and path[cell] then
			color = T.path
		end
		b.Text = text
		b.BackgroundColor3 = color
		b.TextColor3 = textColor
		b.AutoButtonColor = pz ~= nil and cars[cell] == true
		b:SetAttribute("disabled", not (pz and cars[cell] and not pz.solved and not pz.crashed))
	end
	if not pz then
		refs.status.Text = "Starte eine neue Runde."
	elseif pz.solved then
		refs.status.Text = "Geschafft in " .. tostring(pz.moves or 0) .. " Zügen! Serie " .. tostring(pk.streak or 0) .. "."
	elseif pz.crashed then
		refs.status.Text = "Blechschaden! Die Serie ist beendet."
	else
		refs.status.Text = tostring(pz.moves or 0) .. " Züge · " .. (pz.blocked and "Weg noch blockiert (rot markiert)" or "Weg frei – jetzt dein Auto!")
	end
	refs.new.Text = (pz and not pz.solved and not pz.crashed and (pz.moves or 0) > 0) and "Neue Runde (beendet die Serie)" or "Neue Runde"
end

return ParkingUI
