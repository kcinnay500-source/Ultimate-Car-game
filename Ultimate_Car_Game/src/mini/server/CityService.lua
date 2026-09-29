-- CityService: bindet die globale Stadt (workspace.City) an die Minispiele.
-- * City.Stations.<key>: Part mit Attribut MiniTab und ProximityPrompt. Auslösen prüft die Reichweite
--   auf dem Server und öffnet den Tab (Event "mini_open"); unbekannte Tabs melden "eröffnet bald".
-- * City.Arrivals.<key>: Ankunftspunkte für mini_travel; "workshop" führt in die eigene Werkstatt.
-- * Optional City.<...>.LeaderboardBoard mit TextLabels "Status" und "Row1".."RowN": Bestenlisten-Tafel.
-- Fehlt die Stadt (z. B. Basisplace ohne worldgen), passiert nichts.
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(MiniShared:WaitForChild("MiniConfig"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))

local CityService = {}

-- Ersatz-Anzeigenamen für Stationen ohne MiniTitle, deren Tab (noch) nicht existiert ("eröffnet bald").
-- Seit Ausbaustufe 2/3 sind Autohaus, Teststrecke, Waschstraße, Auktion und Spielhalle echte Tabs.
CityService.ComingSoon = {
	dealer = "Das Autohaus", autohaus = "Das Autohaus",
	auction = "Die Auktion", auktion = "Die Auktion",
	arcade = "Die Spielhalle", spielhalle = "Die Spielhalle",
}

local api -- { getSession(player) -> p, onStation(p, tab, station) }
local bound = setmetatable({}, { __mode = "k" })

function CityService.City()
	return workspace:FindFirstChild("City")
end

local function promptOf(station)
	local prompt = station:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		return prompt
	end
	for _, x in ipairs(station:GetDescendants()) do
		if x:IsA("ProximityPrompt") then
			return x
		end
	end
	return nil
end

local function anchorPosition(prompt, station)
	local parent = prompt.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	elseif parent and parent:IsA("Attachment") then
		return parent.WorldPosition
	elseif station:IsA("BasePart") then
		return station.Position
	elseif station:IsA("Model") then
		return station:GetPivot().Position
	end
	return nil
end

local function inRange(player, prompt, station)
	local ch = player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
	local pos = anchorPosition(prompt, station)
	if not root or not humanoid or humanoid.Health <= 0 or not pos then
		return false
	end
	return (root.Position - pos).Magnitude <= prompt.MaxActivationDistance + MiniConfig.StationRangeSlack
end

function CityService.Title(station, tab)
	local title = station and station:GetAttribute("MiniTitle")
	if type(title) == "string" and title ~= "" then
		return title
	end
	return CityService.ComingSoon[string.lower(tostring(tab))]
		or (station and CityService.ComingSoon[string.lower(station.Name)])
		or "Dieser Bereich"
end

function CityService.BindStation(station)
	if bound[station] then
		return false
	end
	local tab = station:GetAttribute("MiniTab")
	if type(tab) ~= "string" or tab == "" then
		return false
	end
	local prompt = promptOf(station)
	if not prompt then
		return false
	end
	bound[station] = true
	prompt.Triggered:Connect(function(player)
		local p = api and api.getSession(player)
		if not p or p.closing or not inRange(player, prompt, station) then
			return
		end
		local current = station:GetAttribute("MiniTab")
		api.onStation(p, type(current) == "string" and current or tab, station)
	end)
	return true
end

function CityService.Bind(city)
	local stations = city:FindFirstChild("Stations") or city:WaitForChild("Stations", 5)
	if not stations then
		return
	end
	for _, station in ipairs(stations:GetChildren()) do
		CityService.BindStation(station)
	end
	pcall(function()
		stations.ChildAdded:Connect(function(station)
			CityService.BindStation(station)
		end)
	end)
end

function CityService.Init(a)
	api = a
	task.spawn(function()
		local ok, err = pcall(function()
			local city = CityService.City() or workspace:WaitForChild("City", 10)
			if city then
				CityService.Bind(city)
			end
		end)
		if not ok then
			warn("[Stadt] Stationen nicht gebunden: " .. tostring(err))
		end
	end)
end

-- Figur aus einem Sitz lösen, BEVOR sie per PivotTo versetzt wird. Humanoid.Sit = false ist auf einem
-- Live-Server nur eine Bitte (der Humanoid gehört dem Client, die SeatWeld verschwindet erst später). Solange
-- die SeatWeld existiert, ist die Figur Teil der Fahrzeug-Baugruppe und PivotTo würde das ganze Auto mitziehen.
-- Deshalb die SeatWeld unter dem Sitz sofort zerstören. Rückgabe: true, wenn die Figur gesessen hat.
function CityService.Unseat(humanoid)
	if not humanoid then
		return false
	end
	local was = false
	local ok = pcall(function()
		local sp = humanoid.SeatPart
		if sp then
			was = true
			local w = sp:FindFirstChild("SeatWeld")
			while w do
				w:Destroy()
				w = sp:FindFirstChild("SeatWeld")
			end
		end
		humanoid.Sit = false
	end)
	return ok and was
end

-- Reise: key = "workshop" (eigene Werkstatt, Stations.home) oder ein Kind von City.Arrivals.
-- moveTo = GarageServer.moveTo (plotlokal). Rückgabe: ok, Hinweistext
function CityService.Travel(p, key, moveTo)
	if key == "workshop" or key == "home" then
		local stations = p.world and p.world.model and p.world.model:FindFirstChild("Stations")
		local home = stations and stations:FindFirstChild("home")
		if not home then
			return false, MiniLocale.T("travel_unknown")
		end
		moveTo(p, home)
		return true
	end
	local city = CityService.City()
	local arrivals = city and city:FindFirstChild("Arrivals")
	local target = arrivals and arrivals:FindFirstChild(key)
	local destination
	if target and target:IsA("BasePart") then
		destination = target.CFrame * CFrame.new(0, target.Size.Y / 2 + 3, 0)
	elseif target and target:IsA("Model") then
		destination = target:GetPivot() * CFrame.new(0, 3, 0)
	end
	if not destination then
		return false, MiniLocale.T("travel_unknown")
	end
	local ch = p.player.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid or humanoid.Health <= 0 then
		return false, MiniLocale.T("travel_blocked")
	end
	CityService.Unseat(humanoid) -- SeatWeld weg, sonst reist das ganze Auto mit
	ch:PivotTo(destination)
	root.AssemblyLinearVelocity = Vector3.new()
	root.AssemblyAngularVelocity = Vector3.new()
	return true
end

-- Bestenlisten-Tafel in der Stadt (falls vorhanden)
function CityService.UpdateBoard(cache)
	local city = CityService.City()
	if not city then
		return
	end
	pcall(function()
		local board = city:FindFirstChild("LeaderboardBoard", true)
		if not board then
			return
		end
		local status = board:FindFirstChild("Status", true)
		if status and status:IsA("TextLabel") then
			if cache.available == false then
				status.Text = MiniLocale.T("leaderboard_unavailable")
			elseif cache.available == nil then
				status.Text = MiniLocale.T("leaderboard_loading")
			else
				status.Text = MiniLocale.T("leaderboard_title")
			end
		end
		for i = 1, MiniConfig.LeaderboardBoardRows do
			local row = board:FindFirstChild("Row" .. i, true)
			if row and row:IsA("TextLabel") then
				local e = cache.available == true and cache.entries[i]
				row.Text = e and string.format("%d. %s – %s", i, e.name or ("Spieler " .. e.userId), MiniLocale.Number(e.value)) or ""
			end
		end
	end)
end

return CityService
