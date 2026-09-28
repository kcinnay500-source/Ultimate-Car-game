-- World: baut den Hof mit allen Stationen aus nativen Parts (keine externen Assets).
-- Jede Station hat einen ProximityPrompt, der die passende 2D-Oberfläche öffnet.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local Config = require(Shared:WaitForChild("Config"))

local World = {}

World.Root = nil
World.Prompts = {} -- { {prompt = ProximityPrompt, tab = string} }
World.BoardRows = {}
World.BoardStatus = nil

local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do
		p[k] = v
	end
	p.Parent = parent
	return p
end

local function label(parent, face, text, textColor, bgColor, ppS)
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppS or 30
	gui.LightInfluence = 0
	gui.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundColor3 = bgColor or Color3.fromRGB(18, 25, 35)
	t.BackgroundTransparency = bgColor and 0 or 1
	t.TextColor3 = textColor or Color3.fromRGB(238, 244, 251)
	t.Font = Enum.Font.GothamBold
	t.TextScaled = true
	t.Text = text
	t.Parent = gui
	return t
end

-- Auto aus Parts. cf zeigt mit LookVector in Fahrtrichtung.
local function car(parent, cf, color, wrecked)
	local model = Instance.new("Model")
	model.Name = wrecked and "Schrottauto" or "Auto"
	local bodyColor = color or Color3.fromRGB(53, 208, 127)
	local mat = wrecked and Enum.Material.CorrodedMetal or Enum.Material.SmoothPlastic
	local body = part(model, { Name = "Karosserie", Size = Vector3.new(4.4, 1.4, 9), CFrame = cf * CFrame.new(0, 1.5, 0), Color = bodyColor, Material = mat })
	part(model, { Name = "Kabine", Size = Vector3.new(4, 1.3, 4.6), CFrame = cf * CFrame.new(0, 2.85, 0.4) * (wrecked and CFrame.Angles(0.05, 0, 0.08) or CFrame.new()), Color = bodyColor:Lerp(Color3.new(0, 0, 0), 0.25), Material = mat })
	part(model, { Name = "Scheibe", Size = Vector3.new(3.6, 1, 0.2), CFrame = cf * CFrame.new(0, 2.9, -1.95), Color = Color3.fromRGB(120, 170, 210), Material = Enum.Material.Glass, Transparency = wrecked and 0.6 or 0.2 })
	for _, x in ipairs({ -2.2, 2.2 }) do
		for _, z in ipairs({ -3, 3 }) do
			part(model, {
				Name = "Rad",
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(0.9, 2, 2),
				CFrame = cf * CFrame.new(x, 1, z),
				Color = Color3.fromRGB(25, 25, 28),
			})
		end
	end
	model.PrimaryPart = body
	model.Parent = parent
	return model
end

local function sign(parent, cf, text, color)
	local board = part(parent, { Name = "Schild", Size = Vector3.new(12, 3, 0.4), CFrame = cf, Color = Color3.fromRGB(18, 25, 35) })
	label(board, Enum.NormalId.Front, text, Color3.fromRGB(238, 244, 251), color, 25)
	for _, x in ipairs({ -5.5, 5.5 }) do
		part(parent, { Name = "Pfosten", Size = Vector3.new(0.4, cf.Position.Y, 0.4), CFrame = CFrame.new((cf * CFrame.new(x, 0, 0)).Position.X, cf.Position.Y / 2, (cf * CFrame.new(x, 0, 0)).Position.Z), Color = Color3.fromRGB(60, 70, 85) })
	end
	return board
end

local function prompt(parent, tab, objectText)
	local p = Instance.new("ProximityPrompt")
	p.ActionText = "Öffnen"
	p.ObjectText = objectText
	p.HoldDuration = 0
	p.MaxActivationDistance = 12
	p.RequiresLineOfSight = false
	p.KeyboardKeyCode = Enum.KeyCode.E
	p.Parent = parent
	table.insert(World.Prompts, { prompt = p, tab = tab })
	return p
end

-- Station: Bodenplatte, Schild, Prompt-Anker. cf schaut zur Hofmitte.
local function station(root, name, tab, cf, color)
	local folder = Instance.new("Model")
	folder.Name = name
	folder.Parent = root
	part(folder, { Name = "Platte", Size = Vector3.new(18, 0.3, 18), CFrame = cf * CFrame.new(0, 0.25, 0), Color = color:Lerp(Color3.fromRGB(30, 35, 45), 0.7), Material = Enum.Material.Concrete })
	sign(folder, cf * CFrame.new(0, 9, 7), name, color)
	local anchor = part(folder, { Name = "PromptAnker", Size = Vector3.new(1.5, 3, 1.5), CFrame = cf * CFrame.new(0, 1.9, -5), Color = color, Material = Enum.Material.Neon })
	prompt(anchor, tab, name)
	return folder
end

local function facing(pos)
	return CFrame.lookAt(pos, Vector3.new(0, pos.Y, 0))
end

function World.Build()
	if World.Root then
		return World.Root
	end
	local root = Instance.new("Folder")
	root.Name = "Hof"

	part(root, { Name = "Wiese", Size = Vector3.new(400, 2, 400), CFrame = CFrame.new(0, -1, 0), Color = Color3.fromRGB(70, 120, 60), Material = Enum.Material.Grass })
	part(root, { Name = "Asphalt", Size = Vector3.new(150, 0.2, 150), CFrame = CFrame.new(0, 0.1, 0), Color = Color3.fromRGB(45, 48, 54), Material = Enum.Material.Asphalt })

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "Start"
	spawn.Anchored = true
	spawn.Size = Vector3.new(8, 0.4, 8)
	spawn.CFrame = CFrame.new(0, 0.3, 0)
	spawn.Color = Color3.fromRGB(74, 163, 255)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.Parent = root

	-- Schrottpresse (kurz)
	do
		local cf = facing(Vector3.new(0, 0, -48))
		local m = station(root, "Schrottpresse", "press", cf, Color3.fromRGB(255, 189, 62))
		local steel = Color3.fromRGB(90, 96, 108)
		part(m, { Name = "Säule", Size = Vector3.new(1.5, 12, 1.5), CFrame = cf * CFrame.new(-4.5, 6, 1), Color = steel, Material = Enum.Material.DiamondPlate })
		part(m, { Name = "Säule", Size = Vector3.new(1.5, 12, 1.5), CFrame = cf * CFrame.new(4.5, 6, 1), Color = steel, Material = Enum.Material.DiamondPlate })
		part(m, { Name = "Traverse", Size = Vector3.new(11, 1.5, 3), CFrame = cf * CFrame.new(0, 12.5, 1), Color = Color3.fromRGB(255, 189, 62), Material = Enum.Material.Metal })
		part(m, { Name = "Pressplatte", Size = Vector3.new(8, 0.8, 10), CFrame = cf * CFrame.new(0, 8, 1), Color = steel, Material = Enum.Material.Metal })
		car(m, cf * CFrame.new(0, 0.3, 1) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(150, 80, 50), true)
	end

	-- Schrotthändler
	do
		local cf = facing(Vector3.new(34, 0, -38))
		local m = station(root, "Schrotthändler", "press", cf, Color3.fromRGB(255, 189, 62))
		part(m, { Name = "Tresen", Size = Vector3.new(8, 3, 2), CFrame = cf * CFrame.new(0, 1.8, 2), Color = Color3.fromRGB(120, 85, 55), Material = Enum.Material.Wood })
		part(m, { Name = "Dach", Size = Vector3.new(10, 0.5, 6), CFrame = cf * CFrame.new(0, 6, 3), Color = Color3.fromRGB(200, 60, 60) })
		part(m, { Name = "Waage", Size = Vector3.new(3, 0.3, 3), CFrame = cf * CFrame.new(-2, 3.45, 2), Color = Color3.fromRGB(160, 165, 175), Material = Enum.Material.Metal })
	end

	-- Idle Tuning Garage (lang)
	do
		local cf = facing(Vector3.new(50, 0, 0))
		local m = station(root, "Tuning-Garage", "tuning", cf, Color3.fromRGB(74, 163, 255))
		part(m, { Name = "Wand", Size = Vector3.new(16, 9, 1), CFrame = cf * CFrame.new(0, 4.6, 8), Color = Color3.fromRGB(30, 40, 60), Material = Enum.Material.Brick })
		part(m, { Name = "Dach", Size = Vector3.new(16, 0.8, 10), CFrame = cf * CFrame.new(0, 9.4, 3.5), Color = Color3.fromRGB(40, 50, 70) })
		car(m, cf * CFrame.new(0, 0.4, 2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(74, 163, 255), false)
		part(m, { Name = "Unterbodenlicht", Size = Vector3.new(9, 0.1, 4), CFrame = cf * CFrame.new(0, 0.45, 2) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(74, 163, 255), Material = Enum.Material.Neon })
	end

	-- Werkstatt (mittel)
	do
		local cf = facing(Vector3.new(-50, 0, 0))
		local m = station(root, "Werkstatt", "workshop", cf, Color3.fromRGB(53, 208, 127))
		part(m, { Name = "Wand", Size = Vector3.new(16, 9, 1), CFrame = cf * CFrame.new(0, 4.6, 8), Color = Color3.fromRGB(60, 70, 60), Material = Enum.Material.Brick })
		part(m, { Name = "Dach", Size = Vector3.new(16, 0.8, 10), CFrame = cf * CFrame.new(0, 9.4, 3.5), Color = Color3.fromRGB(50, 60, 55) })
		part(m, { Name = "Hebebühne", Size = Vector3.new(1, 4, 1), CFrame = cf * CFrame.new(-3.5, 2, 2), Color = Color3.fromRGB(200, 60, 60), Material = Enum.Material.Metal })
		part(m, { Name = "Hebebühne", Size = Vector3.new(1, 4, 1), CFrame = cf * CFrame.new(3.5, 2, 2), Color = Color3.fromRGB(200, 60, 60), Material = Enum.Material.Metal })
		car(m, cf * CFrame.new(0, 2, 2) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(220, 220, 225), false)
	end

	-- Schrottplatz (mittel)
	do
		local cf = facing(Vector3.new(-36, 0, -36))
		local m = station(root, "Schrottplatz", "scrapyard", cf, Color3.fromRGB(255, 90, 103))
		car(m, cf * CFrame.new(-3, 0.3, 3) * CFrame.Angles(0, math.rad(70), 0), Color3.fromRGB(110, 90, 70), true)
		car(m, cf * CFrame.new(3, 0.3, 4) * CFrame.Angles(0, math.rad(110), 0), Color3.fromRGB(80, 90, 110), true)
		car(m, cf * CFrame.new(0, 3.2, 3.5) * CFrame.Angles(0.1, math.rad(95), 0.12), Color3.fromRGB(130, 60, 50), true)
	end

	-- Mechaniker-Quiz (mittel)
	do
		local cf = facing(Vector3.new(36, 0, 36))
		local m = station(root, "Mechaniker-Quiz", "quiz", cf, Color3.fromRGB(180, 120, 255))
		part(m, { Name = "Terminal", Size = Vector3.new(4, 5, 1.5), CFrame = cf * CFrame.new(0, 2.8, 2), Color = Color3.fromRGB(35, 40, 55), Material = Enum.Material.Metal })
		local screen = part(m, { Name = "Bildschirm", Size = Vector3.new(3.4, 2.2, 0.2), CFrame = cf * CFrame.new(0, 3.8, 1.2), Color = Color3.fromRGB(20, 30, 45) })
		label(screen, Enum.NormalId.Front, "OBD?", Color3.fromRGB(180, 120, 255), Color3.fromRGB(10, 15, 25), 40)
	end

	-- Parkplatz-Chaos (mittel)
	do
		local cf = facing(Vector3.new(-36, 0, 36))
		local m = station(root, "Parkplatz-Chaos", "parking", cf, Color3.fromRGB(74, 163, 255))
		for i = -1, 1 do
			part(m, { Name = "Linie", Size = Vector3.new(0.3, 0.05, 7), CFrame = cf * CFrame.new(i * 5 - 2.5, 0.43, 3), Color = Color3.fromRGB(240, 240, 240) })
		end
		car(m, cf * CFrame.new(-5, 0.4, 3), Color3.fromRGB(255, 189, 62), false)
		car(m, cf * CFrame.new(5, 0.4, 3), Color3.fromRGB(255, 90, 103), false)
	end

	-- Bestenliste als Tafel auf dem Hof
	do
		local cf = facing(Vector3.new(0, 0, 50))
		local m = Instance.new("Model")
		m.Name = "Bestenliste"
		m.Parent = root
		local board = part(m, { Name = "Tafel", Size = Vector3.new(22, 16, 0.6), CFrame = cf * CFrame.new(0, 10, 0), Color = Color3.fromRGB(12, 17, 24) })
		for _, x in ipairs({ -10, 10 }) do
			part(m, { Name = "Stütze", Size = Vector3.new(0.8, 18, 0.8), CFrame = cf * CFrame.new(x, 9, 0.8), Color = Color3.fromRGB(60, 70, 85) })
		end
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 30
		gui.LightInfluence = 0
		gui.Parent = board
		local layout = Instance.new("UIListLayout")
		layout.Padding = UDim.new(0, 4)
		layout.SortOrder = Enum.SortOrder.LayoutOrder
		layout.Parent = gui
		local title = Instance.new("TextLabel")
		title.Size = UDim2.new(1, 0, 0, 60)
		title.BackgroundTransparency = 1
		title.Font = Enum.Font.GothamBlack
		title.TextScaled = true
		title.TextColor3 = Color3.fromRGB(255, 189, 62)
		title.Text = "Bestenliste · Schrott gepresst"
		title.LayoutOrder = 0
		title.Parent = gui
		World.BoardStatus = title
		for i = 1, Config.LeaderboardBoardRows do
			local row = Instance.new("TextLabel")
			row.Size = UDim2.new(1, 0, 0, 36)
			row.BackgroundTransparency = 1
			row.Font = Enum.Font.GothamMedium
			row.TextScaled = true
			row.TextXAlignment = Enum.TextXAlignment.Left
			row.TextColor3 = Color3.fromRGB(238, 244, 251)
			row.Text = ""
			row.LayoutOrder = i
			row.Parent = gui
			World.BoardRows[i] = row
		end
		local anchor = part(m, { Name = "PromptAnker", Size = Vector3.new(1.5, 3, 1.5), CFrame = cf * CFrame.new(0, 1.9, -3), Color = Color3.fromRGB(255, 189, 62), Material = Enum.Material.Neon })
		prompt(anchor, "leaderboard", "Bestenliste")
	end

	root.Parent = workspace
	World.Root = root
	World.UpdateBoard({ available = nil, entries = {} })
	return root
end

function World.UpdateBoard(cache)
	if not World.BoardStatus then
		return
	end
	if cache.available == false then
		World.BoardStatus.Text = Locale.T("leaderboard_unavailable")
	elseif cache.available == nil then
		World.BoardStatus.Text = Locale.T("leaderboard_loading")
	else
		World.BoardStatus.Text = "Bestenliste · Schrott gepresst"
	end
	for i, row in ipairs(World.BoardRows) do
		local e = cache.available and cache.entries[i]
		if e then
			row.Text = string.format("  %d. %s  –  %s", i, e.name or ("Spieler " .. e.userId), Locale.Number(e.value))
		else
			row.Text = ""
		end
	end
end

return World
