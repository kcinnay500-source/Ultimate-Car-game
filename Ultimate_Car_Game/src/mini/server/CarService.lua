-- CarService: eigene Autos auf dem Server (PHASE2_CONTRACT §1, §4, §6).
-- * Aktionen: mini_car_buy, mini_car_sell, mini_car_spawn, mini_car_despawn, mini_car_testdrive, mini_car_tune,
--   mini_car_style, mini_car_nitro, mini_car_horn, mini_carwash, mini_track_start (Register).
--   mini_car_horn: Lichthupe des gefahrenen Autos (VehicleFactory.Flash mit HornText-Sprechblase, für alle sichtbar;
--   Abstand GameConfig.Shop.HornCooldown) – Taste H / HUPE-Knopf im DriveClient.
-- * Fahrzeuge unter workspace.PlayerCars: höchstens 1 eigenes Auto ("Car_<UserId>") + 1 Probefahrt ("Probe_<UserId>").
--   Spawn an City.CarSpawns.<key> (fehlt er: Werkstatt-Parkplatz, Part "CarSpawn" im Plot bzw. Einfahrt).
--   Netzwerk-Besitz beim Besitzer, nur er darf einsteigen (fremde Insassen fliegen sofort raus).
--   Despawn beim Verlassen, bei Tod/Neuspawn der Figur, beim erneuten Holen, nach Leerlauf, wenn das Auto verloren ist.
-- * Probefahrt 60 s, Nitro (kurzer Schub mit Abklingzeit), Waschstraße (Glanz, Session), Zeitfahren mit
--   Checkpoints (City.Track.Checkpoints.CP1..CPn, Ziel optional), gemessen per Touched + Serverzeit.
-- Geld ändert sich in Handlern (innerhalb von request()); die Zeitfahren-Belohnung entsteht außerhalb (Touched)
-- und wird nur ohne laufenden Robux-Kauf (transacting) gutgeschrieben, sonst im nächsten Tick.
--
-- Schnittstelle für MiniService (siehe Verkabelung):
--   CarService.Register(Actions, api)    Aktionen registrieren (api wie bei PressService)
--   CarService.Init(ctx)                 ctx aus Mini.Init (changed, toast, getSession, moveTo, now)
--   CarService.OnJoin(ms, d, now)        Sitzungszustand, Figur-Hooks
--   CarService.Tick(ms, d, now)          0,5-s-Tick: Probefahrt-Ende, Leerlauf, Zeitfahren-Timeout, Nitro, Belohnung
--   CarService.OnLeave(ms)               alles abbauen
--   CarService.SnapshotFields(ms, d, now) Felder für den Minispiel-Snapshot (§5)
--
-- 3.x Startauto „Flitzer“ (CarCatalog.Starter, Daten d.games.flitzer über CarRules):
--   car_call {}            Auto rufen (Taste G / Handy-App „Auto rufen“): nur in der Open World, Abklingzeit
--                          GameConfig.StarterCar.CallCooldown (5 s); baut das vorige eigene Auto ab und stellt das
--                          Lieblingsauto (Standard: Flitzer) an die nächste freie Fahrbahnstelle neben dem Spieler
--                          (City.Roads, Asphalt; Rückfall: eigener Werkstatt-Parkplatz / City.CarSpawns) und setzt ihn
--                          hinein. Nicht während Zeitfahren, Probefahrt, Spielhallen-Runde, Reparatur in der Großen
--                          Werkstatt oder einer Lieferfahrt mit schon draußen stehendem Auto.
--   car_favourite {id}     Lieblingsauto wählen (CarCatalog.StarterCarId = Flitzer, sonst eigene Auto-Id)
--   Beide Aktionen registriert Register nur, wenn MiniNet.Actions sie kennt (Verkabelung durch den Integrator).
--   Begrüßung: wer in dieser Sitzung seinen Startweg wählt (meta.startPath "" -> Weg), bekommt in der Open World
--   einmal den Flitzer neben sich gestellt (flitzer.due/intro) mit Toast GameConfig.StarterCar.Text.intro.
local Players = game:GetService("Players")
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local CarCatalog = require(MiniShared:WaitForChild("CarCatalog"))
local CarRules = require(MiniShared:WaitForChild("CarRules"))
local TrackRules = require(MiniShared:WaitForChild("TrackRules"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local VehicleFactory = require(script.Parent:WaitForChild("VehicleFactory"))
local CityService = require(script.Parent:WaitForChild("CityService"))
local ShopService = require(script.Parent:WaitForChild("ShopService")) -- Meilenstein 8: Kosmetik je Auto (CosmeticsFor)
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local MiniNet = require(MiniShared:WaitForChild("MiniNet")) -- 3.x: car_call/car_favourite nur registrieren, wenn verkabelt

local CarService = {}
CarService.States = {} -- [Player] = Auto-Zustand der Sitzung (cs)
local states = CarService.States

local api -- MiniService-api: now, toast, notice, dirty, ...
local ctx -- MiniService-ctx: changed, toast, getSession, moveTo, now

local SPAWN_KEYS = {}
for _, k in ipairs(CarCatalog.SpawnKeys) do
	SPAWN_KEYS[k] = true
end

local TEXT = {
	not_owner = "Das ist nicht dein Auto.",
	no_car = "Du hast noch kein eigenes Auto. Im Autohaus findest du eins.",
	no_spot = "Kein freier Stellplatz gefunden.",
	wait = "Bitte einen Moment warten.",
	unknown_spot = "Unbekannter Stellplatz.",
	track_missing = "Die Teststrecke ist noch nicht bereit.",
	nitro_none = "Dein Auto hat noch kein Nitro. Rüste es im Tuning-Zentrum nach.",
	nitro_drive = "Nitro geht nur während der Fahrt im eigenen Auto.",
	despawn_none = "Du hast gerade kein Auto draußen.",
	wash_none = "Du brauchst ein eigenes Auto für die Waschstraße.",
	wash_fetch = "Hol dein Auto zuerst zur Waschstraße (Meine Autos: Holen an der Waschstraße).",
	wash_range = "Fahre dein Auto in die Waschstraße.",
	no_money = "Nicht genug Credits.",
}

-- 3.x: Startauto/Auto rufen. Zahlen und Texte aus GameConfig.StarterCar (Rückfall hier, falls der Abschnitt fehlt).
local STARTER_DEFAULTS = {
	CallCooldown = 5, -- Sekunden zwischen zwei car_call eines Spielers
	SearchRadius = 300, -- Studs: so weit wird die nächste Fahrbahn gesucht
	RoadMargin = 5, -- Abstand der Wagenmitte zum Fahrbahnrand
	RoadCandidates = 8, -- so viele nächstgelegene Fahrbahnstücke werden geprüft
	SlideStep = 9, -- Ausweichen entlang der Fahrbahn (Studs)
	IntroDelay = 2, -- Sekunden in der Open World, bevor der Begrüßungs-Flitzer kommt
	IntroRetry = 5, -- erneuter Versuch, wenn gerade kein Platz war
	NearRoad = 24, -- liegt die nächste Fahrbahn weiter weg: erst ein freier, ebener Platz direkt neben dem Spieler
	BesideOffset = 8, -- so weit neben/vor den Spieler (Studs)
	Text = {
		intro = "Dein Flitzer! Ruf ihn jederzeit mit dem Handy (P) → „Auto rufen“ oder Taste G",
		called = "%s ist da – gute Fahrt!",
		cooldown = "Dein Auto ist gleich wieder rufbar (noch %d s).",
		openWorld = "Auto rufen geht nur in der Open World.",
		track = "Während des Zeitfahrens kannst du kein Auto rufen.",
		testdrive = "Beende zuerst die Probefahrt.",
		arcade = "Beende zuerst deine Runde in der Spielhalle.",
		repair = "Warte, bis die Reparatur in der Großen Werkstatt fertig ist.",
		delivery = "Während einer Lieferfahrt bleibt dein Auto draußen – steig wieder ein!",
		seated = "Du sitzt schon in deinem Auto.",
		noCharacter = "Warte, bis deine Figur wieder da ist.",
		favourite = "Lieblingsauto: %s. Ruf es mit Taste G oder im Handy.",
		favouriteMissing = "Dein Lieblingsauto steht gerade nicht bereit – der Flitzer kommt.",
		nitro = "Der Flitzer hat kein Nitro – dafür ist er super wendig!",
		trackStarter = "Zeitfahren fährst du mit einem Auto aus dem Autohaus – der Flitzer fährt außer Konkurrenz.",
	},
}
local function starterCfg(key)
	local sc = type(GameConfig.StarterCar) == "table" and GameConfig.StarterCar or nil
	local v = sc and sc[key]
	if v == nil then
		v = STARTER_DEFAULTS[key]
	end
	return v
end
local function starterText(key)
	local sc = type(GameConfig.StarterCar) == "table" and GameConfig.StarterCar or nil
	local t = sc and type(sc.Text) == "table" and sc.Text[key]
	return type(t) == "string" and t or STARTER_DEFAULTS.Text[key]
end
CarService.StarterText = starterText
-- Abbruchgründe (mini_notice track_abort {reason, cause}): early, tooFast, expired, left, despawn
local ABORT = {
	early = "Frühstart! Das Zeitfahren wurde abgebrochen.",
	tooFast = "Ungültige Runde: zu schnell zwischen zwei Checkpoints.",
	left = "Zeitfahren abgebrochen: Du bist ausgestiegen.",
	expired = "Zeitfahren abgebrochen: Zeit abgelaufen.",
	despawn = "Zeitfahren abgebrochen.",
}

local function now()
	if api then
		return api.now()
	end
	if ctx and ctx.now then
		return ctx.now()
	end
	return workspace:GetServerTimeNow()
end

local function toast(cs, text)
	if api and cs.ms and type(text) == "string" and text ~= "" then
		api.toast(cs.ms, text)
	end
end

local function notice(cs, kind, data)
	if api and cs.ms then
		api.notice(cs.ms, kind, data or {})
	end
end

local function dirty(cs)
	if api and cs.ms then
		api.dirty(cs.ms)
	end
end

-- Hinweis an einen beliebigen Spieler (z. B. fremder Insasse)
local function toastPlayer(player, text)
	local cs = states[player]
	if cs and cs.ms then
		toast(cs, text)
		return
	end
	local p = ctx and ctx.getSession and ctx.getSession(player)
	if p and ctx.toast then
		ctx.toast(p, text)
	end
end

local function credits(n)
	return MiniLocale.Credits(n)
end

-- d.games.track fehlt nur in Profilen ohne TrackRules.Load (vor der Verkabelung)
local function trackData(d)
	if type(d.games.track) ~= "table" then
		d.games.track = TrackRules.Default()
	end
	return d.games.track
end

---------------------------------------------------------------- Welt
local function city()
	return workspace:FindFirstChild("City")
end

function CarService.CarsFolder()
	local f = workspace:FindFirstChild("PlayerCars")
	if not f then
		f = Instance.new("Folder")
		f.Name = "PlayerCars"
		f.Parent = workspace
	end
	return f
end

local function anchorCFrame(x)
	if not x then
		return nil
	end
	if x:IsA("BasePart") then
		return x.CFrame
	elseif x:IsA("Model") then
		return x:GetPivot()
	elseif x:IsA("Attachment") then
		return x.WorldCFrame
	end
	return nil
end

local function citySpawnPart(key)
	local c = city()
	local folder = c and c:FindFirstChild("CarSpawns")
	return folder and folder:FindFirstChild(key)
end

local function citySpawn(key)
	return anchorCFrame(citySpawnPart(key))
end

-- Seitliche Ausweichplätze (Vielfache von Physics.spawnSpacing, rechts = +): Attribut AltSteps der Spawn-Parts
-- (worldgen prüft genau diese Plätze auf freie Fläche, z. B. Waschstraße nur "-1"), sonst 1, -1, 2, -2.
local DEFAULT_STEPS = { 0, 1, -1, 2, -2 }
local function spawnSteps(anchor)
	local raw = anchor and anchor:GetAttribute("AltSteps")
	if type(raw) ~= "string" then
		return DEFAULT_STEPS
	end
	local steps = { 0 }
	for token in string.gmatch(raw, "[^,%s]+") do
		local n = tonumber(token)
		if n and n == math.floor(n) and n ~= 0 and math.abs(n) <= 4 and not table.find(steps, n) then
			table.insert(steps, n)
		end
	end
	return steps
end

-- Werkstatt-Parkplatz: Part "CarSpawn" im eigenen Plot, sonst die Einfahrt vor der Halle (Nase zur Straße, +Z)
local function plotSpawn(cs)
	local world = cs.p and cs.p.world
	local model = world and world.model
	if not model then
		return nil
	end
	local sp = model:FindFirstChild("CarSpawn", true)
	local cf = anchorCFrame(sp)
	if cf then
		return cf, sp
	end
	local f = CarCatalog.Physics.plotFallback
	return model:GetPivot() * CFrame.new(f[1], f[2], f[3]) * CFrame.Angles(0, math.pi, 0)
end

local function ignoreList()
	local list = { CarService.CarsFolder() }
	local c = city()
	if c then
		for _, name in ipairs({ "CarSpawns", "Track", "Arrivals", "Stations" }) do
			local f = c:FindFirstChild(name)
			if f then
				table.insert(list, f)
			end
		end
	end
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then
			table.insert(list, pl.Character)
		end
	end
	return list
end

local function groundY(pos)
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList()
		params.IgnoreWater = true
		return workspace:Raycast(pos + Vector3.new(0, 8, 0), Vector3.new(0, -30, 0), params)
	end)
	if ok and hit then
		return hit.Position.Y
	end
	return nil
end

local function occupied(pos)
	for _, m in ipairs(CarService.CarsFolder():GetChildren()) do
		if m:IsA("Model") then
			local ok, pv = pcall(function()
				return m:GetPivot()
			end)
			if ok and pv then
				local dx, dz = pv.Position.X - pos.X, pv.Position.Z - pos.Z
				if dx * dx + dz * dz < 81 then
					return true
				end
			end
		end
	end
	return false
end

-- Ziel-CFrame (Boden unter den Reifen, nur Gierwinkel) für einen Spawn-Schlüssel mit Rückfallkette
local function spawnCFrame(cs, keys)
	local base, anchor
	for _, key in ipairs(keys) do
		if key == "workshop" then
			base, anchor = plotSpawn(cs)
		else
			anchor = citySpawnPart(key)
			base = anchorCFrame(anchor)
		end
		if base then
			break
		end
	end
	if not base then
		base, anchor = plotSpawn(cs)
	end
	if not base then
		local ch = cs.player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not root then
			return nil
		end
		base = root.CFrame * CFrame.new(0, -3, -12)
	end
	local look = base.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	flat = flat.Magnitude > 1e-3 and flat.Unit or Vector3.new(0, 0, -1)
	local right = Vector3.new(-flat.Z, 0, flat.X)
	local P = CarCatalog.Physics
	local chosen = base.Position
	for _, step in ipairs(spawnSteps(anchor)) do
		local pos = base.Position + right * (step * P.spawnSpacing)
		if not occupied(pos) then
			chosen = pos
			break
		end
	end
	local y = groundY(chosen) or chosen.Y
	local at = Vector3.new(chosen.X, y + P.spawnLift, chosen.Z)
	return CFrame.lookAt(at, at + flat)
end

---------------------------------------------------------------- Sitzungszustand
local function characterParts(player)
	local ch = player.Character
	local humanoid = ch and ch:FindFirstChildOfClass("Humanoid")
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	return ch, humanoid, root
end

local despawn -- vorwärts deklariert

local function despawnAll(cs, reason)
	despawn(cs, "car", reason)
	despawn(cs, "test", reason)
end

local function hookHumanoid(cs, ch)
	if cs.diedConn then
		cs.diedConn:Disconnect()
		cs.diedConn = nil
	end
	local humanoid = ch and (ch:FindFirstChildOfClass("Humanoid") or ch:WaitForChild("Humanoid", 5))
	if humanoid and states[cs.player] == cs then
		cs.diedConn = humanoid.Died:Connect(function()
			if states[cs.player] == cs then
				despawnAll(cs, "died")
			end
		end)
	end
end

local function newState(ms)
	local player = ms.player
	local cs = {
		player = player, p = ms.p, ms = ms, conns = {},
		lastSpawnAt = { car = -math.huge, test = -math.huge }, testdriveReadyAt = 0, nitroUntil = nil, nitroReadyAt = 0,
		washReadyAt = 0, shine = {}, pendingReward = 0, pendingXp = 0,
		lastCallAt = -math.huge, introTryAt = -math.huge, owSince = nil, -- 3.x: Auto rufen / Begrüßungs-Flitzer
		pathAtJoin = nil,
	}
	-- 3.x: Startweg beim Sitzungsbeginn ("" = Startwahl offen -> nach der Wahl kommt der Begrüßungs-Flitzer)
	pcall(function()
		local meta = ms.p.profile.data.games.meta
		cs.pathAtJoin = type(meta) == "table" and type(meta.startPath) == "string" and meta.startPath or nil
	end)
	states[player] = cs
	local ok, conn = pcall(function()
		return player.CharacterAdded:Connect(function(ch)
			if states[player] ~= cs then
				return
			end
			despawnAll(cs, "respawn")
			task.spawn(hookHumanoid, cs, ch)
		end)
	end)
	if ok and conn then
		table.insert(cs.conns, conn)
	end
	if player.Character then
		task.spawn(hookHumanoid, cs, player.Character)
	end
	return cs
end

local function stateOf(ms)
	local cs = states[ms.player]
	if cs and cs.p ~= ms.p then
		-- neue Sitzung desselben Spielers (OnLeave verpasst): alte Fahrzeuge und Verbindungen abbauen
		CarService.Cleanup(cs, "leave")
		cs = nil
	end
	cs = cs or newState(ms)
	cs.ms = ms
	return cs
end

---------------------------------------------------------------- Zeitfahren
local trackIndex = setmetatable({}, { __mode = "k" }) -- [Part] = Position in der Reihenfolge
local trackBound = setmetatable({}, { __mode = "k" })
local handleTouch -- vorwärts deklariert

local function onCheckpointTouched(part, hit)
	local index = trackIndex[part]
	if not index or typeof(hit) ~= "Instance" then
		return
	end
	local folder = workspace:FindFirstChild("PlayerCars")
	if not folder then
		return
	end
	local car = hit
	while car and car.Parent ~= folder do
		car = car.Parent
	end
	if not car then
		return
	end
	for _, cs in pairs(states) do
		local v = cs.car
		if v and v.model == car and cs.run and cs.run.vehicle == v then
			if not v.occupied then
				return
			end
			-- Plausibilität: das Chassis muss wirklich am Checkpoint sein
			local reach = part.Size.Magnitude / 2 + CarCatalog.Track.touchSlack
			if (v.info.chassis.Position - part.Position).Magnitude > reach then
				return
			end
			handleTouch(cs, index, now())
			return
		end
	end
end

-- Reihenfolge der Checkpoints: City.Track.Checkpoints.CP1..CPn, danach das Ziel (City.Track.Ziel | Finish |
-- StartZiel | Start bzw. dieselben Namen im Checkpoints-Ordner), sonst ist CPn das Ziel. Bindet Touched einmal.
function CarService.TrackSequence()
	local c = city()
	local track = c and c:FindFirstChild("Track")
	local folder = track and track:FindFirstChild("Checkpoints")
	if not folder then
		return nil
	end
	local list = {}
	for i = 1, 200 do
		local cp = folder:FindFirstChild("CP" .. i)
		if not cp or not cp:IsA("BasePart") then
			break
		end
		table.insert(list, cp)
	end
	for _, name in ipairs({ "Ziel", "Finish", "StartZiel", "Start" }) do
		local f = track:FindFirstChild(name) or folder:FindFirstChild(name)
		if f and f:IsA("BasePart") then
			if not table.find(list, f) then
				table.insert(list, f)
			end
			break
		end
	end
	if #list == 0 then
		return nil
	end
	for part in pairs(trackIndex) do
		trackIndex[part] = nil
	end
	for i, part in ipairs(list) do
		trackIndex[part] = i
		if not trackBound[part] then
			trackBound[part] = true
			part.Touched:Connect(function(hit)
				onCheckpointTouched(part, hit)
			end)
		end
	end
	return list
end

local function abortRun(cs, reason, cause)
	if not cs.run then
		return
	end
	cs.run = nil
	notice(cs, "track_abort", { reason = reason, cause = cause or reason })
	toast(cs, ABORT[reason] or ABORT.despawn)
	dirty(cs)
end

-- Belohnung gutschreiben: nur ohne laufenden Robux-Kauf (transacting). Beim Verlassen (closing, vor P.Save)
-- wird noch gebucht, aber kein Zustand mehr an den Client geschickt.
local function payPending(cs)
	local p = cs.p
	if (cs.pendingReward or 0) <= 0 and (cs.pendingXp or 0) <= 0 then
		return true
	end
	if not p or not p.profile or p.profile.transacting then
		return false
	end
	local d = p.profile.data
	local amount, xp = cs.pendingReward, cs.pendingXp
	cs.pendingReward, cs.pendingXp = 0, 0
	if amount > 0 then
		MiniRules.AddIncome(d, amount) -- Teststrecke: Prestige-Einnahmenbonus (PHASE4_CONTRACT §4)
	end
	if xp > 0 then
		MiniRules.GainXP(d, xp)
	end
	if ctx and ctx.changed and not p.closing then
		pcall(ctx.changed, p)
	end
	dirty(cs)
	return true
end
CarService.PayPending = payPending

local function finishRun(cs, time)
	cs.run = nil
	local p = cs.p
	if not p or p.closing or not p.profile or not p.player.Parent then
		return
	end
	local d = p.profile.data
	local result = TrackRules.Complete(trackData(d), time, d.level)
	MiniRules.MarkActive(d, now())
	cs.pendingReward += result.reward
	cs.pendingXp += result.xp
	payPending(cs)
	notice(cs, "track_finish", {
		time = time, best = result.best, newBest = result.newBest, reward = result.reward,
		rewardedBest = result.rewardedBest, valid = true,
	})
	local text = "Zeitfahren: " .. MiniLocale.Decimal(time, 2) .. " s"
	if result.newBest then
		text ..= " – neue Bestzeit!"
	end
	if result.reward > 0 then
		text ..= " +" .. credits(result.reward)
	end
	toast(cs, text)
	dirty(cs)
end

handleTouch = function(cs, index, t)
	local run = cs.run
	if not run then
		return
	end
	local res, info = TrackRules.Touch(run, index, t)
	if res == "checkpoint" then
		notice(cs, "track_checkpoint", { index = info.index, total = info.total, time = info.time, split = info.split })
	elseif res == "finish" then
		finishRun(cs, info.time)
	elseif res == "early" then
		abortRun(cs, "early")
	elseif res == "tooFast" then
		abortRun(cs, "tooFast")
	end
end
CarService.HandleTouch = handleTouch

---------------------------------------------------------------- Fahrzeuge
local function vehicleAlive(v)
	local m = v.model
	return m ~= nil and m.Parent ~= nil and v.info ~= nil and v.info.chassis.Parent ~= nil
		and v.info.seat.Parent ~= nil and m:IsDescendantOf(workspace)
end

local function eject(seat, humanoid)
	humanoid.Sit = false
	local w = seat:FindFirstChild("SeatWeld")
	if w then
		w:Destroy()
	end
	local ch = humanoid.Parent
	if ch and ch:IsA("Model") then
		pcall(function()
			ch:PivotTo(CFrame.new(seat.Position - seat.CFrame.RightVector * 5 + Vector3.new(0, 3, 0)))
		end)
	end
end

-- Den Besitzer aus dem Sitz eines seiner Fahrzeuge (slot) lösen; SeatWeld wird sofort zerstört.
function CarService.UnseatFrom(cs, slot)
	local v = cs[slot]
	local seat = v and v.info and v.info.seat
	local _, humanoid = characterParts(cs.player)
	if not seat or not humanoid then
		return false
	end
	if seat.Occupant ~= humanoid and humanoid.SeatPart ~= seat then
		return false
	end
	return CityService.Unseat(humanoid)
end

-- Besitzer neben die Fahrertür stellen und in den Sitz setzen
local function seatOwner(cs, v)
	local ch, humanoid, root = characterParts(cs.player)
	if not ch or not humanoid or not root or humanoid.Health <= 0 then
		return false
	end
	local seat = v.info.seat
	if seat.Occupant then
		return false
	end
	-- Sitzt die Figur noch in einem anderen Auto: SeatWeld zuerst lösen, sonst zieht PivotTo das alte Auto mit
	CityService.Unseat(humanoid)
	pcall(function()
		ch:PivotTo(CFrame.new(seat.Position - seat.CFrame.RightVector * 3 + Vector3.new(0, 2, 0)))
	end)
	local ok = pcall(function()
		seat:Sit(humanoid)
	end)
	return ok
end

local function bindVehicle(cs, v)
	local seat, prompt = v.info.seat, v.info.prompt
	table.insert(v.conns, seat:GetPropertyChangedSignal("Occupant"):Connect(function()
		if cs[v.slot] ~= v then
			return
		end
		local humanoid = seat.Occupant
		if humanoid then
			local who = Players:GetPlayerFromCharacter(humanoid.Parent)
			if who ~= cs.player then
				-- Sitzschutz: fremde Insassen sofort entfernen
				eject(seat, humanoid)
				if who then
					toastPlayer(who, TEXT.not_owner)
				end
				return
			end
			v.occupied = true
			v.lastOccupiedAt = now()
			prompt.Enabled = false
			VehicleFactory.SetOwner(v.model, cs.player)
		else
			local was = v.occupied
			v.occupied = false
			v.lastOccupiedAt = now()
			prompt.Enabled = true
			if was then
				if cs.run and cs.run.vehicle == v then
					abortRun(cs, "left")
				end
				-- Aussteigen: neben die Fahrertür (nicht nach einem Teleport weg vom Auto)
				-- Nicht, wenn die Figur inzwischen in einem anderen Sitz sitzt (z. B. Probefahrt): PivotTo würde
				-- sonst das neue Auto mitziehen.
				local ch, hum, root = characterParts(cs.player)
				local other = hum and hum.SeatPart
				if ch and root and (other == nil or other == seat) and (root.Position - seat.Position).Magnitude < 8 then
					pcall(function()
						ch:PivotTo(CFrame.new(seat.Position - seat.CFrame.RightVector * 4.5 + Vector3.new(0, 2.5, 0)))
					end)
				end
			end
		end
	end))
	table.insert(v.conns, prompt.Triggered:Connect(function(who)
		if cs[v.slot] ~= v then
			return
		end
		if who ~= cs.player then
			toastPlayer(who, TEXT.not_owner)
			return
		end
		local _, _, root = characterParts(who)
		if not root or (root.Position - seat.Position).Magnitude > prompt.MaxActivationDistance + 6 then
			return
		end
		seatOwner(cs, v)
	end))
end

despawn = function(cs, slot, reason)
	local v = cs[slot]
	if not v then
		return false
	end
	cs[slot] = nil
	for _, c in ipairs(v.conns) do
		c:Disconnect()
	end
	if cs.run and cs.run.vehicle == v then
		abortRun(cs, "despawn", reason)
	end
	if slot == "car" and cs.nitroUntil then
		cs.nitroUntil = nil
	end
	local seat = v.info and v.info.seat
	local occupant = seat and seat.Occupant
	if occupant then
		pcall(function()
			occupant.Sit = false
		end)
	end
	if v.model then
		v.model:Destroy()
	end
	if slot == "test" then
		notice(cs, "testdrive_end", { model = v.modelId, reason = reason })
	else
		notice(cs, "car_despawned", { id = v.carId, reason = reason })
	end
	dirty(cs)
	return true, occupant ~= nil
end

-- Baut und platziert ein Fahrzeug. slot = "car" | "test"; keys = Spawn-Schlüssel mit Rückfall
-- Kosmetik (Meilenstein 8): angelegte Folierung/Felgen/Hupe/Spur bzw. die exklusive Folierung eines DLC-Autos
-- (ShopService.CosmeticsFor -> ShopRules.Resolve) auf das gebaute Modell anwenden; idempotent, ersetzt alles.
local function applyCosmetics(cs, model, car)
	local d = cs.p and cs.p.profile and cs.p.profile.data
	if not d or not model then
		return
	end
	local ok, err = pcall(function()
		VehicleFactory.ApplyCosmetics(model, car, ShopService.CosmeticsFor(d, car))
	end)
	if not ok then
		warn("[Autos] Kosmetik: " .. tostring(err))
	end
end

-- 3.x: opts = { cframe = Ziel (statt keys), noSeat = true (nicht einsetzen, z. B. Begrüßungs-Flitzer) }
local function spawnVehicle(cs, slot, car, keys, testdrive, opts)
	local m = CarCatalog.Model(car.model)
	if not m then
		return nil, "Unbekanntes Modell."
	end
	opts = opts or {}
	despawn(cs, slot, "replaced")
	local cf = opts.cframe or spawnCFrame(cs, keys)
	if not cf then
		return nil, TEXT.no_spot
	end
	local player = cs.player
	local t = now()
	local shine = not testdrive and (cs.shine[car.id] or 0) > t
	local ok, model, err = pcall(VehicleFactory.Build, {
		body = m.body, car = car, stats = CarRules.Stats(car),
		name = (testdrive and "Probe_" or "Car_") .. player.UserId,
		ownerId = player.UserId, ownerName = player.Name, carId = testdrive and 0 or car.id, modelId = m.id,
		displayName = m.name, testdrive = testdrive, cframe = cf,
		plate = testdrive and "PROBEFAHRT" or (m.starter and "FLITZER" or ("UCG · " .. string.format("%02d", car.id % 100))), shine = shine,
	})
	if not ok or not model then
		if ok == false then
			warn("[Autos] Bau fehlgeschlagen: " .. tostring(model))
		end
		return nil, (ok and err) or "Das Auto konnte nicht gebaut werden."
	end
	model.Parent = CarService.CarsFolder()
	VehicleFactory.Activate(model, player)
	applyCosmetics(cs, model, car) -- Probefahrt eines DLC-Autos trägt so seine exklusive Folierung
	local v = {
		slot = slot, model = model, info = VehicleFactory.Info(model), carId = testdrive and 0 or car.id,
		modelId = m.id, name = m.name, testdrive = testdrive == true, spawnedAt = t, lastOccupiedAt = t,
		occupied = false, conns = {},
	}
	cs[slot] = v
	if m.starter then
		model:SetAttribute("Starter", true) -- 3.x: Flitzer (Startauto)
	end
	bindVehicle(cs, v)
	if not opts.noSeat then
		seatOwner(cs, v)
	end
	dirty(cs)
	return v
end

-- Tuning/Optik sofort auf das gefahrene Auto übertragen
local function refreshSpawned(cs, d, id)
	local v = cs.car
	if not v or v.carId ~= id or not vehicleAlive(v) then
		return
	end
	local car = CarRules.Owned(d, id) -- 3.x: auch der Flitzer
	if not car then
		return
	end
	local stats = CarRules.Stats(car)
	VehicleFactory.ApplyStats(v.model, stats)
	VehicleFactory.ApplyStyle(v.model, car, (cs.shine[id] or 0) > now())
	applyCosmetics(cs, v.model, car) -- mini_car_style setzt die Optik neu: Kosmetik danach erneut anwenden
	-- Zeitfahren läuft: schnelleres Auto -> Mindestzeiten der offenen Abschnitte anpassen
	if cs.run and cs.run.vehicle == v then
		TrackRules.Rescale(cs.run, TrackRules.CarSpeed(stats))
	end
end

local function validKey(at)
	if type(at) ~= "string" or #at > 32 or not string.match(at, "^[%w_]+$") then
		return false
	end
	if SPAWN_KEYS[at] then
		return true
	end
	local c = city()
	local folder = c and c:FindFirstChild("CarSpawns")
	return folder ~= nil and folder:FindFirstChild(at) ~= nil
end

-- Waschstraße: City.CarSpawns.carwash bzw. City.Stations.carwash (fehlt beides: keine Reichweitenprüfung)
local function carwashAnchor()
	local cf = citySpawn("carwash")
	if cf then
		return cf.Position
	end
	local c = city()
	local st = c and c:FindFirstChild("Stations")
	local anchor = anchorCFrame(st and st:FindFirstChild("carwash"))
	return anchor and anchor.Position or nil
end

local function endTestdrive(cs, reason)
	local v = cs.test
	if not v then
		return
	end
	local _, wasSeated = despawn(cs, "test", reason)
	if reason == "time" then
		toast(cs, "Probefahrt beendet. Den " .. v.name .. " gibt es im Autohaus.")
		if wasSeated and cs.p and ctx then
			pcall(CityService.Travel, cs.p, "dealer", ctx.moveTo)
		end
	end
end

---------------------------------------------------------------- 3.x: Auto rufen (Fahrbahn neben dem Spieler)
-- Fahrbahnstücke der Stadt: flache Asphalt-Quader unter City.Roads (Fahrbahn, Knoten, Absenkungen, Vorfelder) und
-- jedes Teil der Stadt mit Attribut CarRoad = true (z. B. Zufahrten anderer Bezirke). Einmal gesammelt.
local roadCache = nil
local function isRoadPart(x)
	if not x:IsA("BasePart") or x:IsA("WedgePart") or x:IsA("CornerWedgePart") then
		return false
	end
	if x:IsA("Part") and x.Shape ~= Enum.PartType.Block then
		return false
	end
	local up = x.CFrame.UpVector
	if math.abs(up.Y) < 0.98 then
		return false
	end
	if x:GetAttribute("CarRoad") == true then
		return true
	end
	return x.Material == Enum.Material.Asphalt and x.Size.X >= 10 and x.Size.Z >= 10
end

function CarService.RoadParts()
	if roadCache and #roadCache > 0 and roadCache[1].Parent ~= nil then
		return roadCache
	end
	local list = {}
	local c = city()
	if c then
		local roads = c:FindFirstChild("Roads")
		if roads then
			for _, x in ipairs(roads:GetDescendants()) do
				if isRoadPart(x) then
					table.insert(list, x)
				end
			end
		end
		local districts = c:FindFirstChild("Districts")
		if districts then
			for _, x in ipairs(districts:GetDescendants()) do
				if x:IsA("BasePart") and x:GetAttribute("CarRoad") == true and isRoadPart(x) then
					table.insert(list, x)
				end
			end
		end
	end
	roadCache = list
	return list
end

-- Nächster Punkt auf der Oberseite eines Fahrbahnstücks (mit Randabstand), dazu die Fahrtrichtung (lange Achse)
local function nearestOnRoad(part, pos, margin)
	local cf, size = part.CFrame, part.Size
	local lp = cf:PointToObjectSpace(pos)
	local hx, hz = size.X / 2, size.Z / 2
	local mx, mz = math.max(0, hx - margin), math.max(0, hz - margin)
	local x = math.clamp(lp.X, -mx, mx)
	local z = math.clamp(lp.Z, -mz, mz)
	local top = (cf.UpVector.Y >= 0) and size.Y / 2 or -size.Y / 2
	local world = cf:PointToWorldSpace(Vector3.new(x, top, z))
	local axis = size.X >= size.Z and cf.RightVector or cf.LookVector
	axis = Vector3.new(axis.X, 0, axis.Z)
	axis = axis.Magnitude > 1e-3 and axis.Unit or Vector3.new(0, 0, -1)
	return world, axis, { x = x, z = z, mx = mx, mz = mz, top = top }
end

-- Steht dort nichts Festes (Laterne, Ampel, Baum, Gebäude, Verkehr)? Autos der Spieler prüft occupied().
local function spotFree(cf)
	local ok, blocked = pcall(function()
		local params = OverlapParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList()
		local hits = workspace:GetPartBoundsInBox(cf * CFrame.new(0, 3.1, 0), Vector3.new(6.5, 4.4, 9.5), params)
		for _, h in ipairs(hits) do
			if h.CanCollide and h.Transparency < 1 then
				return true
			end
		end
		return false
	end)
	return not ok or not blocked
end

-- 3.x: Fahrspuren des Stadtverkehrs (City.Animated.TrafficLoops.*.Waypoints) einmal lesen. Ein gerufenes Auto darf
-- nicht in einer Spur stehen, sonst wartet die ganze Schleife dahinter. Je Schleife: Segmente und die halbe Breite des
-- breitesten Verkehrsfahrzeugs (Attribut Width der Modelle unter City.Animated.Verkehr, Bus 8,3).
local laneCache = nil
local function trafficLanes()
	if laneCache and laneCache.folder ~= nil and laneCache.folder.Parent ~= nil then
		return laneCache.segs
	end
	local segs = {}
	local c = city()
	local anim = c and c:FindFirstChild("Animated")
	local loops = anim and anim:FindFirstChild("TrafficLoops")
	local widths = {}
	local verkehr = anim and anim:FindFirstChild("Verkehr")
	if verkehr then
		for _, m in ipairs(verkehr:GetChildren()) do
			local key, w = m:GetAttribute("Loop"), m:GetAttribute("Width")
			if type(key) == "string" and type(w) == "number" then
				widths[key] = math.max(widths[key] or 0, w)
			end
		end
	end
	if loops then
		for _, f in ipairs(loops:GetChildren()) do
			local wp = f:GetAttribute("Waypoints")
			if type(wp) == "string" then
				local key = string.gsub(f.Name, "^Loop_", "")
				local half = (widths[key] or 8.3) / 2
				local pts = {}
				for x, y, z in string.gmatch(wp, "(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)") do
					table.insert(pts, Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
				end
				for i = 1, #pts do
					table.insert(segs, { a = pts[i], b = pts[i % #pts + 1], half = half })
				end
			end
		end
	end
	-- ohne TrafficLoops-Ordner (z. B. Tests ohne Stadt) wird beim nächsten Mal neu gelesen
	laneCache = { folder = loops, segs = segs }
	return segs
end
CarService._resetLanes = function()
	laneCache = nil
end

-- Liegt die Wagenmitte so nah an einer Verkehrsspur, dass Verkehr dort anhalten müsste?
-- Abstand zur Spurmitte < halbe Verkehrsbreite + halbe Autobreite (StarterCar.CarHalfWidth) + LaneGap
function CarService.InTrafficLane(spot)
	local extra = (starterCfg("CarHalfWidth") or 3.25) + (starterCfg("LaneGap") or 1)
	for _, sg in ipairs(trafficLanes()) do
		local a, b = sg.a, sg.b
		if math.abs(spot.Y - a.Y) < 12 then
			local abx, abz = b.X - a.X, b.Z - a.Z
			local len2 = abx * abx + abz * abz
			local t = len2 > 1e-6 and math.clamp(((spot.X - a.X) * abx + (spot.Z - a.Z) * abz) / len2, 0, 1) or 0
			local dx, dz = spot.X - (a.X + abx * t), spot.Z - (a.Z + abz * t)
			local lim = sg.half + extra
			if dx * dx + dz * dz < lim * lim then
				return true
			end
		end
	end
	return false
end

-- Ziel-CFrame (Boden unter den Reifen) auf der nächsten freien Fahrbahnstelle neben dem Spieler, oder nil.
-- 3.x: nie in einer Verkehrsspur (CarService.InTrafficLane); quer zur Fahrbahn wird auch der Randstreifen probiert.
function CarService.RoadSpot(cs, pos, look)
	local margin = starterCfg("RoadMargin")
	local radius = starterCfg("SearchRadius")
	local cands = {}
	for _, part in ipairs(CarService.RoadParts()) do
		if part.Parent then
			local world, axis, info = nearestOnRoad(part, pos, margin)
			local dx, dz = world.X - pos.X, world.Z - pos.Z
			local dist = math.sqrt(dx * dx + dz * dz)
			if dist <= radius then
				-- kleine Asphaltflächen (Bordsteinabsenkungen, Einfahrten) nur, wenn keine Straße deutlich näher liegt
				local small = math.min(part.Size.X, part.Size.Z) < 20
				table.insert(cands, { part = part, world = world, axis = axis, info = info, dist = dist, rank = dist + (small and 20 or 0) })
			end
		end
	end
	table.sort(cands, function(a, b)
		return a.rank < b.rank
	end)
	local step = starterCfg("SlideStep")
	local P = CarCatalog.Physics
	local tried = 0
	for i = 1, #cands do
		if tried >= starterCfg("RoadCandidates") then
			break
		end
		local c = cands[i]
		local axis = c.axis
		if look and axis:Dot(look) < 0 then
			axis = -axis -- Nase grob in Blickrichtung des Spielers
		end
		local cf0 = c.part.CFrame
		local localAxis = cf0:VectorToObjectSpace(c.axis)
		-- Querlage: nächster Punkt, dann die beiden Randstreifen (Wagenmitte RoadMargin vom Rand)
		local crossX = math.abs(localAxis.X) < 0.5
		local base = { { x = c.info.x, z = c.info.z } }
		if crossX then
			table.insert(base, { x = (c.info.x >= 0) and c.info.mx or -c.info.mx, z = c.info.z })
			table.insert(base, { x = (c.info.x >= 0) and -c.info.mx or c.info.mx, z = c.info.z })
		else
			table.insert(base, { x = c.info.x, z = (c.info.z >= 0) and c.info.mz or -c.info.mz })
			table.insert(base, { x = c.info.x, z = (c.info.z >= 0) and -c.info.mz or c.info.mz })
		end
		local any = false
		for _, b0 in ipairs(base) do
			for _, k in ipairs({ 0, 1, -1, 2, -2, 3, -3 }) do
				-- entlang der Fahrbahn verschieben, im Stück bleiben
				local x = math.clamp(b0.x + localAxis.X * k * step, -c.info.mx, c.info.mx)
				local z = math.clamp(b0.z + localAxis.Z * k * step, -c.info.mz, c.info.mz)
				local at = cf0:PointToWorldSpace(Vector3.new(x, c.info.top, z))
				if (k == 0 or math.abs(x - b0.x) + math.abs(z - b0.z) > 1) and not CarService.InTrafficLane(at) then
					any = true
					local y = groundY(at) or at.Y
					if math.abs(y - at.Y) > 3 then
						y = at.Y -- Strahl traf etwas anderes (Dach, Brücke): Fahrbahnhöhe nehmen
					end
					local spot = Vector3.new(at.X, y + P.spawnLift, at.Z)
					local cf = CFrame.lookAt(spot, spot + axis)
					if not occupied(spot) and spotFree(cf) then
						local dx, dz = spot.X - pos.X, spot.Z - pos.Z
						return cf, math.max(c.dist, math.sqrt(dx * dx + dz * dz))
					end
				end
			end
		end
		if any then
			tried += 1 -- Stücke, die ganz in Verkehrsspuren liegen, zählen nicht als Versuch
		end
	end
	return nil
end

-- Freier Himmel über dem Platz (kein Dach, keine Halle): sonst stünde das Auto z. B. in der eigenen Werkstatt
local function skyClear(spot)
	local ok, hit = pcall(function()
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = ignoreList()
		params.IgnoreWater = true
		params.RespectCanCollide = true
		return workspace:Raycast(spot + Vector3.new(0, 1, 0), Vector3.new(0, 40, 0), params)
	end)
	return ok and hit == nil
end

-- 3.x: freier, ebener Platz direkt neben dem Spieler (rechts, links, vor ihm), wenn die nächste Fahrbahn weit weg ist
-- (z. B. vor der eigenen Werkstatt). Boden höchstens knapp unter den Füßen, nichts Festes im Weg, kein Dach darüber,
-- kein Auto dort.
function CarService.BesideSpot(pos, look)
	local off = starterCfg("BesideOffset")
	look = look or Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local P = CarCatalog.Physics
	for _, dir in ipairs({ right, -right, look }) do
		local at = pos + dir * off
		local y = groundY(at)
		-- Boden unter dem Platz: nicht höher als die Hüfte, nicht tiefer als 6 Studs unter den Füßen
		if y and y <= pos.Y and y >= pos.Y - 9 then
			local spot = Vector3.new(at.X, y + P.spawnLift, at.Z)
			local cf = CFrame.lookAt(spot, spot + look)
			-- 3.x: nie in eine Verkehrsspur (Spieler steht auf der Straße)
			if not occupied(spot) and not CarService.InTrafficLane(spot) and spotFree(cf) and skyClear(spot) then
				return cf
			end
		end
	end
	return nil
end

-- Wohin kommt das gerufene Auto? Nächste freie Fahrbahn (ist sie weiter als NearRoad weg: erst ein Platz direkt neben
-- dem Spieler); liegt der eigene Werkstatt-Parkplatz näher, dorthin; sonst der nächste City.CarSpawns-Punkt bzw. die
-- Werkstatt (Rückfallkette von spawnCFrame).
function CarService.CallSpot(cs)
	local _, _, root = characterParts(cs.player)
	if not root then
		return nil
	end
	local pos = root.Position
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z)
	look = look.Magnitude > 1e-3 and look.Unit or nil
	local cf, dist = CarService.RoadSpot(cs, pos, look)
	if not cf or dist > starterCfg("NearRoad") then
		local beside = CarService.BesideSpot(pos, look)
		if beside then
			return beside
		end
	end
	local plotCf = plotSpawn(cs)
	if plotCf then
		local d2 = Vector3.new(plotCf.Position.X - pos.X, 0, plotCf.Position.Z - pos.Z).Magnitude
		if not cf or d2 < dist then
			return spawnCFrame(cs, { "workshop" })
		end
	end
	if cf then
		return cf
	end
	-- keine Fahrbahn in Reichweite: nächster Stellplatz der Stadt
	local c = city()
	local folder = c and c:FindFirstChild("CarSpawns")
	local best, bestD = nil, math.huge
	if folder then
		for _, sp in ipairs(folder:GetChildren()) do
			local acf = anchorCFrame(sp)
			if acf then
				local d = (acf.Position - pos).Magnitude
				if d < bestD then
					best, bestD = sp.Name, d
				end
			end
		end
	end
	return spawnCFrame(cs, best and { best } or { "workshop" })
end

-- Lieferfahrt läuft (StoryService: ms.story.delivery)?
local function deliveryRunning(ms)
	local ss = ms and ms.story
	return type(ss) == "table" and type(ss.delivery) == "table"
end

-- Spielhallen-Runde läuft? (ArcadeService.Round; lazy, da ArcadeService später geladen werden kann)
local function arcadeRunning(ms)
	local ok, round = pcall(function()
		local mod = script.Parent:FindFirstChild("ArcadeService")
		local A = mod and require(mod)
		return A and A.Round and A.Round(ms)
	end)
	return ok and round ~= nil and round ~= false
end

-- Grund, warum gerade kein Auto gerufen werden darf (Text) oder nil
function CarService.CallBlock(cs, ms)
	local mode = ms and ms.p and ms.p.mode
	if mode ~= nil and mode ~= "openworld" then
		return starterText("openWorld")
	end
	if cs.run then
		return starterText("track")
	end
	if cs.test then
		return starterText("testdrive")
	end
	if arcadeRunning(ms) then
		return starterText("arcade")
	end
	if type(ms.pw) == "table" and ms.pw.job then
		return starterText("repair")
	end
	if deliveryRunning(ms) and cs.car and vehicleAlive(cs.car) then
		return starterText("delivery")
	end
	local _, humanoid, root = characterParts(cs.player)
	if not humanoid or not root or humanoid.Health <= 0 then
		return starterText("noCharacter")
	end
	local v = cs.car
	if v and vehicleAlive(v) and v.info.seat.Occupant == humanoid then
		return starterText("seated")
	end
	return nil
end

-- car_call: Lieblingsauto (Standard Flitzer) neben den Spieler rufen. Rückgabe true = Auto steht da.
function CarService.CallCar(ms, _, d, t)
	local cs = stateOf(ms)
	t = t or now()
	local block = CarService.CallBlock(cs, ms)
	if block then
		toast(cs, block)
		return nil
	end
	local cd = starterCfg("CallCooldown")
	if t - cs.lastCallAt < cd then
		toast(cs, string.format(starterText("cooldown"), math.max(1, math.ceil(cd - (t - cs.lastCallAt)))))
		return nil
	end
	local car, isStarter = CarRules.Favourite(d)
	local f = CarRules.StarterData(d)
	if isStarter and f.fav > 0 then
		toast(cs, starterText("favouriteMissing"))
		if not CarRules.Find(d, f.fav) then
			f.fav = 0 -- verkauft/versteigert: wieder der Flitzer (nur in einer Auktion gesperrt: Wahl bleibt)
		end
	end
	local ok, checked = CarRules.CanSpawn(d, car.id)
	if not isStarter and not ok then
		toast(cs, checked)
		return nil
	end
	despawn(cs, "car", "replaced") -- vorher abbauen: sein Platz ist dann wieder frei
	local cf = CarService.CallSpot(cs)
	if not cf then
		toast(cs, TEXT.no_spot)
		return nil
	end
	cs.lastCallAt = t
	cs.lastSpawnAt.car = t
	local v, err = spawnVehicle(cs, "car", car, nil, false, { cframe = cf })
	if not v then
		toast(cs, err)
		return nil
	end
	if not isStarter then
		CarRules.SetActive(d, car.id)
	end
	MiniRules.MarkActive(d, t)
	notice(cs, "car_spawned", { id = car.id, model = car.model, name = v.name, testdrive = false, at = "call", starter = isStarter })
	toast(cs, string.format(starterText("called"), v.name))
	return true
end

-- car_favourite {id}: Lieblingsauto für car_call (CarCatalog.StarterCarId = Flitzer)
function CarService.SetFavourite(ms, data, d)
	local cs = stateOf(ms)
	local ok, res = CarRules.SetFavourite(d, type(data) == "table" and data.id or nil)
	if not ok then
		toast(cs, res)
		return nil
	end
	local m = CarCatalog.Model(res.model)
	toast(cs, string.format(starterText("favourite"), m and m.name or "Auto"))
	dirty(cs)
	return true
end

-- Begrüßung: nach der Startwahl in dieser Sitzung einmal den Flitzer neben den Spieler stellen (nicht einsetzen)
local function tickIntro(cs, ms, d, t)
	local mode = ms.p.mode
	if mode ~= nil and mode ~= "openworld" then -- ohne Modus gilt die Sitzung als Open World (wie TutorialService)
		cs.owSince = nil
		return
	end
	cs.owSince = cs.owSince or t
	local f = CarRules.StarterData(d)
	if f.intro then
		return
	end
	if not f.due then
		local meta = d.games.meta
		local path = type(meta) == "table" and meta.startPath or nil
		if cs.pathAtJoin == "" and type(path) == "string" and path ~= "" then
			f.due = true
		else
			return
		end
	end
	if t - cs.owSince < starterCfg("IntroDelay") or t - cs.introTryAt < starterCfg("IntroRetry") then
		return
	end
	if ms.greeted ~= true then
		return -- erst wenn der Client zuhört ('hello'), sonst ginge der Toast verloren
	end
	cs.introTryAt = t
	if cs.car or cs.test or cs.run then
		f.due, f.intro = false, true -- hat schon ein Auto draußen: Begrüßung entfällt
		return
	end
	local _, humanoid, root = characterParts(cs.player)
	if not humanoid or not root or humanoid.Health <= 0 or humanoid.SeatPart ~= nil then
		return
	end
	local cf = CarService.CallSpot(cs)
	if not cf then
		return
	end
	local v = spawnVehicle(cs, "car", CarRules.StarterCar(t), nil, false, { cframe = cf, noSeat = true })
	if not v then
		return
	end
	f.due, f.intro = false, true
	notice(cs, "car_spawned", { id = CarCatalog.StarterCarId, model = CarCatalog.StarterId, name = v.name, testdrive = false, at = "intro", starter = true })
	toast(cs, starterText("intro"))
end
CarService.TickIntro = tickIntro

---------------------------------------------------------------- Aktionen
function CarService.Register(Actions, a)
	api = a

	Actions.Register("mini_car_buy", function(ms, data, d, t)
		local cs = stateOf(ms)
		local ok, res = CarRules.Buy(d, data.model, t)
		if ok then
			MiniRules.MarkActive(d, t)
			local m = CarCatalog.Model(res.model)
			toast(cs, m.name .. " gekauft! Du findest ihn unter „Meine Autos“.")
			notice(cs, "car_bought", { id = res.id, model = res.model, name = m.name })
		elseif res then
			toast(cs, res)
		end
	end)

	Actions.Register("mini_car_sell", function(ms, data, d)
		local cs = stateOf(ms)
		if CarRules.IsStarterId(data.id) then
			toast(cs, CarRules.Text.starterSell) -- 3.x: Flitzer ist unverkäuflich (bleibt auch draußen stehen)
			return
		end
		local car = CarRules.Find(d, data.id)
		if car and car.locked then
			toast(cs, "Dieses Auto ist gerade in einer Auktion.")
			return
		end
		if cs.car and cs.car.carId == data.id then
			despawn(cs, "car", "sold")
		end
		local ok, value, sold = CarRules.Sell(d, data.id)
		if ok then
			cs.shine[data.id] = nil
			toast(cs, CarCatalog.Model(sold.model).name .. " verkauft: +" .. credits(value))
			return true -- 3.x: gelungener Verkauf -> Story-Ereignis action:mini_car_sell (Verkaufshaus c1_ah4)
		elseif value then
			toast(cs, value)
		end
	end)

	Actions.Register("mini_car_spawn", function(ms, data, d, t)
		local cs = stateOf(ms)
		if not validKey(data.at) then
			toast(cs, TEXT.unknown_spot)
			return
		end
		if t - cs.lastSpawnAt.car < CarCatalog.SpawnCooldown then
			toast(cs, TEXT.wait)
			return
		end
		local ok, car = CarRules.CanSpawn(d, data.id)
		if not ok then
			toast(cs, car)
			return
		end
		cs.lastSpawnAt.car = t
		despawn(cs, "test", "replaced")
		local v, err = spawnVehicle(cs, "car", car, { data.at }, false)
		if not v then
			toast(cs, err)
			return
		end
		CarRules.SetActive(d, car.id)
		notice(cs, "car_spawned", { id = car.id, model = car.model, name = v.name, testdrive = false, at = data.at })
	end)

	Actions.Register("mini_car_despawn", function(ms)
		local cs = stateOf(ms)
		if not despawn(cs, "car", "player") then
			toast(cs, TEXT.despawn_none)
		end
	end)

	Actions.Register("mini_car_testdrive", function(ms, data, _, t)
		local cs = stateOf(ms)
		local m = CarCatalog.Model(data.model)
		if not m or not m.dealer then
			toast(cs, "Dieses Modell gibt es beim Händler nicht.")
			return
		end
		if t < cs.testdriveReadyAt then
			toast(cs, "Die nächste Probefahrt ist in " .. math.ceil(cs.testdriveReadyAt - t) .. " s möglich.")
			return
		end
		if t - cs.lastSpawnAt.test < CarCatalog.SpawnCooldown then
			toast(cs, TEXT.wait)
			return
		end
		cs.lastSpawnAt.test = t
		cs.testdriveReadyAt = t + CarCatalog.Testdrive.cooldown
		-- Sitzt der Spieler noch im eigenen Auto: erst aussteigen (SeatWeld weg), sonst reist das eigene Auto
		-- beim Umsetzen zum Probewagen mit.
		CarService.UnseatFrom(cs, "car")
		local v, err = spawnVehicle(cs, "test", CarRules.NewCar(m.id, t), { "testdrive", "dealer" }, true)
		if not v then
			toast(cs, err)
			return
		end
		v.endsAt = t + CarCatalog.Testdrive.seconds
		v.model:SetAttribute("TestdriveEnds", v.endsAt)
		toast(cs, "Probefahrt im " .. m.name .. ": " .. CarCatalog.Testdrive.seconds .. " Sekunden. Viel Spaß!")
		notice(cs, "car_spawned", { id = 0, model = m.id, name = m.name, testdrive = true, endsAt = v.endsAt })
	end)

	Actions.Register("mini_car_tune", function(ms, data, d)
		local cs = stateOf(ms)
		local ok, res, cost = CarRules.Tune(d, data.id, data.part, data.level)
		if ok then
			toast(cs, CarCatalog.Tune[data.part].name .. " Stufe " .. res .. " eingebaut (−" .. credits(cost) .. ").")
			refreshSpawned(cs, d, data.id)
			return true -- eingebaut: zählt für Nebenmissionen ("action:mini_car_tune")
		elseif res then
			toast(cs, res)
		end
	end)

	Actions.Register("mini_car_style", function(ms, data, d)
		local cs = stateOf(ms)
		local ok, cost, changes = CarRules.Style(d, data.id, data.paint, data.rims, data.glow, data.spoiler)
		if ok then
			if #changes > 0 then
				toast(cs, "Optik geändert (−" .. credits(cost) .. ").")
				refreshSpawned(cs, d, data.id)
			end
		elseif cost then
			toast(cs, cost)
		end
	end)

	Actions.Register("mini_car_nitro", function(ms, _, d, t)
		local cs = stateOf(ms)
		local v = cs.car
		if not v or not v.occupied or not vehicleAlive(v) then
			toast(cs, TEXT.nitro_drive)
			return
		end
		local car = CarRules.Owned(d, v.carId) -- 3.x: auch der Flitzer (ohne Nitro)
		local stats = car and CarRules.Stats(car)
		if not stats or stats.nitro.level <= 0 then
			toast(cs, CarRules.IsStarterId(v.carId) and starterText("nitro") or TEXT.nitro_none)
			return
		end
		if t < cs.nitroReadyAt then
			return -- Abklingzeit (der Tacho zeigt sie an)
		end
		local untilAt = t + stats.nitro.seconds
		cs.nitroUntil = untilAt
		cs.nitroReadyAt = t + stats.nitro.cooldown
		v.model:SetAttribute("NitroUntil", untilAt)
		v.model:SetAttribute("NitroReadyAt", cs.nitroReadyAt)
		VehicleFactory.SetNitro(v.model, true)
		notice(cs, "car_nitro", { untilAt = untilAt, readyAt = cs.nitroReadyAt, boost = stats.nitro.boost })
		task.delay(stats.nitro.seconds, function()
			if cs.car == v and cs.nitroUntil == untilAt then
				cs.nitroUntil = nil
				VehicleFactory.SetNitro(v.model, false)
			end
		end)
	end)

	-- Lichthupe: nur im eigenen, gefahrenen Auto; Abstand HornCooldown (still während der Abklingzeit)
	Actions.Register("mini_car_horn", function(ms, _, d, t)
		local cs = stateOf(ms)
		local v = cs.car
		if not v or not v.occupied or not vehicleAlive(v) then
			toast(cs, GameConfig.Shop.Text.horn)
			return
		end
		if t < (cs.hornReadyAt or 0) then
			return
		end
		cs.hornReadyAt = t + GameConfig.Shop.HornCooldown
		VehicleFactory.Flash(v.model, GameConfig.Shop.HornSeconds)
	end)

	Actions.Register("mini_carwash", function(ms, _, d, t)
		local cs = stateOf(ms)
		local v = cs.car
		local car = v and vehicleAlive(v) and CarRules.Owned(d, v.carId) -- 3.x: der Flitzer darf auch glänzen
		if not car then
			toast(cs, CarRules.Find(d, d.games.activeCar) and TEXT.wash_fetch or TEXT.wash_none)
			return
		end
		if t < cs.washReadyAt then
			return
		end
		local w = CarCatalog.Carwash
		local anchor = carwashAnchor()
		if anchor and (v.info.chassis.Position - anchor).Magnitude > w.range then
			toast(cs, TEXT.wash_range)
			return
		end
		if d.money < w.price then
			toast(cs, TEXT.no_money)
			return
		end
		MiniRules.AddMoney(d, -w.price)
		cs.washReadyAt = t + w.cooldown
		cs.shine[car.id] = t + w.shineSeconds
		VehicleFactory.ApplyStyle(v.model, car, true)
		VehicleFactory.Sparkle(v.model)
		v.model:SetAttribute("ShineUntil", cs.shine[car.id])
		toast(cs, "Glanzwäsche fertig! Dein " .. CarCatalog.Model(car.model).name .. " strahlt (−" .. credits(w.price) .. ").")
		return true -- gewaschen: zählt für Nebenmissionen ("action:mini_carwash")
	end)

	Actions.Register("mini_track_start", function(ms, _, d, t)
		local cs = stateOf(ms)
		local list = CarService.TrackSequence()
		if not list then
			toast(cs, TEXT.track_missing)
			return
		end
		local id = cs.car and cs.car.carId or d.games.activeCar
		if CarRules.IsStarterId(id) then
			id = d.games.activeCar -- 3.x: der Flitzer fährt außer Konkurrenz – Zeitfahren mit dem aktiven eigenen Auto
		end
		local ok, car = CarRules.CanSpawn(d, id)
		if not ok then
			toast(cs, CarRules.Find(d, id) and car or (cs.car and CarRules.IsStarterId(cs.car.carId) and starterText("trackStarter") or TEXT.no_car))
			return
		end
		if t - cs.lastSpawnAt.car < CarCatalog.SpawnCooldown then
			toast(cs, TEXT.wait)
			return
		end
		cs.lastSpawnAt.car = t
		cs.run = nil -- Neustart: der alte Lauf verfällt still
		despawn(cs, "test", "replaced")
		local v, err = spawnVehicle(cs, "car", car, { "track" }, false)
		if not v then
			toast(cs, err)
			return
		end
		CarRules.SetActive(d, car.id)
		local positions = {}
		for i, part in ipairs(list) do
			positions[i] = part.Position
		end
		-- Plausibilität mit dem Tempo DIESES Autos (nicht dem schnellsten des Katalogs): sonst schafft ein
		-- verschobenes Kompakt-Chassis die Mindestzeiten des Supersportwagens
		local maxSpeed = TrackRules.CarSpeed(CarRules.Stats(car))
		local start = v.info.chassis.Position
		local run = TrackRules.NewRun(TrackRules.MinTimes(start, positions, maxSpeed), t, nil,
			TrackRules.MinLap(start, positions, maxSpeed), maxSpeed)
		run.vehicle = v
		cs.run = run
		notice(cs, "car_spawned", { id = car.id, model = car.model, name = v.name, testdrive = false, at = "track" })
		notice(cs, "track_start", {
			startAt = run.startAt, total = run.total, best = trackData(d).best, countdown = CarCatalog.Track.countdown,
		})
	end)

	-- 3.x: Auto rufen / Lieblingsauto – nur registrieren, wenn MiniNet.Actions sie kennt (Verkabelung durch den
	-- Integrator; vorher würde Actions.Register die Aktion ablehnen)
	if MiniNet.Actions.car_call then
		Actions.Register("car_call", CarService.CallCar)
	end
	if MiniNet.Actions.car_favourite then
		Actions.Register("car_favourite", CarService.SetFavourite)
	end
end

---------------------------------------------------------------- Lebenszyklus
function CarService.Init(c)
	ctx = c
	-- Meilenstein 8: nach shop_equip/shop_buy/Quittung/Pass die Optik der stehenden Autos ohne Neubau erneuern
	ShopService.Restyle = function(ms, d)
		local cs = ms and states[ms.player]
		if not cs or cs.ms ~= ms then
			return
		end
		local v = cs.car
		if v and vehicleAlive(v) then
			local car = CarRules.Owned(d, v.carId) -- 3.x: auch der Flitzer trägt angelegte Kosmetik
			if car then
				applyCosmetics(cs, v.model, car)
			end
		end
		local tv = cs.test
		if tv and vehicleAlive(tv) then
			applyCosmetics(cs, tv.model, CarRules.NewCar(tv.modelId, 0))
		end
	end
	pcall(function()
		Players.PlayerRemoving:Connect(function(player)
			local cs = states[player]
			if cs then
				CarService.Cleanup(cs, "leave")
			end
		end)
	end)
	task.spawn(function()
		local ok, err = pcall(function()
			local c2 = city() or workspace:WaitForChild("City", 10)
			local track = c2 and (c2:FindFirstChild("Track") or c2:WaitForChild("Track", 5))
			if track then
				CarService.TrackSequence()
			end
		end)
		if not ok then
			warn("[Autos] Teststrecke nicht gebunden: " .. tostring(err))
		end
	end)
end

function CarService.OnJoin(ms)
	stateOf(ms)
end

-- Für AuctionService: ein eingeliefertes (locked) oder übergebenes Auto von der Straße holen.
-- Rückgabe: true, wenn es gespawnt war.
function CarService.ReleaseCar(player, id, reason)
	local cs = states[player]
	if not cs or not cs.car or cs.car.carId ~= id then
		return false
	end
	return (despawn(cs, "car", reason or "auction"))
end

-- Id des gespawnten eigenen Autos (0 = keins)
function CarService.SpawnedCarId(player)
	local cs = states[player]
	return cs and cs.car and cs.car.carId or 0
end

function CarService.Cleanup(cs, reason)
	if states[cs.player] == cs then
		states[cs.player] = nil
	end
	payPending(cs)
	cs.run = nil
	despawnAll(cs, reason or "leave")
	for _, c in ipairs(cs.conns) do
		c:Disconnect()
	end
	cs.conns = {}
	if cs.diedConn then
		cs.diedConn:Disconnect()
		cs.diedConn = nil
	end
end

function CarService.OnLeave(ms)
	local cs = states[ms.player]
	if cs and cs.p == ms.p then
		CarService.Cleanup(cs, "leave")
	end
end

function CarService.Tick(ms, d, t)
	local cs = states[ms.player]
	if not cs or cs.p ~= ms.p then
		return
	end
	cs.ms = ms
	for _, slot in ipairs({ "car", "test" }) do
		local v = cs[slot]
		if v and not vehicleAlive(v) then
			despawn(cs, slot, "lost")
		end
	end
	local test = cs.test
	if test and test.endsAt and t >= test.endsAt then
		endTestdrive(cs, "time")
	end
	local v = cs.car
	if v and not v.occupied and t - v.lastOccupiedAt > CarCatalog.IdleDespawnSeconds then
		despawn(cs, "car", "idle")
	end
	if cs.run and TrackRules.Expired(cs.run, t) then
		abortRun(cs, "expired")
	end
	if cs.nitroUntil and t >= cs.nitroUntil then
		cs.nitroUntil = nil
		if cs.car then
			VehicleFactory.SetNitro(cs.car.model, false)
		end
	end
	v = cs.car
	if v and v.model:GetAttribute("Shine") and (cs.shine[v.carId] or 0) <= t then
		local car = CarRules.Owned(d, v.carId)
		if car then
			VehicleFactory.ApplyStyle(v.model, car, false)
		end
	end
	if cs.pendingReward > 0 or cs.pendingXp > 0 then
		payPending(cs)
	end
	-- 3.x: Begrüßungs-Flitzer nach der Startwahl
	local okIntro, errIntro = pcall(tickIntro, cs, ms, d, t)
	if not okIntro then
		warn("[Autos] Begrüßungs-Flitzer: " .. tostring(errIntro))
	end
end

---------------------------------------------------------------- Snapshot (PHASE2_CONTRACT §5)
-- Alle Auto-Felder für den Minispiel-Snapshot: cars, activeCar, catalog, garageMax (aus d) und
-- spawnedCar, spawnedId, testdrive, track, nitro (Sitzung). ms darf nil sein (dann ohne Sitzungsteil).
function CarService.SnapshotFields(ms, d, t)
	t = t or now()
	local out = CarRules.SnapshotFields(d)
	local tr = d.games.track or TrackRules.Default()
	out.track = { best = tr.best, rewardedBest = tr.rewardedBest, runs = tr.runs, running = false, active = false }
	out.spawnedCar = false
	out.spawnedId = 0
	out.spawnedStarter = false
	out.testdrive = false
	out.nitro = { readyAt = 0, untilAt = 0 }
	local cs = ms and states[ms.player]
	if cs and cs.p == ms.p then
		if cs.car then
			-- 3.x: der Flitzer ist kein Garagenauto: spawnedCar bleibt false (DealerUI.IsOut würde sonst das aktive
			-- eigene Auto als „draußen“ zeigen), spawnedId = CarCatalog.StarterCarId, spawnedStarter = true
			local starter = CarRules.IsStarterId(cs.car.carId)
			out.spawnedCar = not starter
			out.spawnedId = cs.car.carId
			out.spawnedStarter = starter
		end
		if cs.test then
			out.testdrive = { model = cs.test.modelId, name = cs.test.name, endsAt = cs.test.endsAt or 0 }
		end
		if cs.run then
			out.track.running = true
			out.track.active = true
			out.track.startAt = cs.run.startAt
			out.track.startedAt = cs.run.startAt
			out.track.next = cs.run.next
			out.track.checkpoint = cs.run.next - 1
			out.track.total = cs.run.total
		end
		out.nitro = { readyAt = cs.nitroReadyAt, untilAt = cs.nitroUntil or 0 }
		out.shineUntil = cs.car and (cs.shine[cs.car.carId] or 0) or 0
	end
	return out
end

return CarService
