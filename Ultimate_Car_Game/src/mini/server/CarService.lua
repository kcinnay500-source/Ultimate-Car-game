-- CarService: eigene Autos auf dem Server (PHASE2_CONTRACT §1, §4, §6).
-- * Aktionen: mini_car_buy, mini_car_sell, mini_car_spawn, mini_car_despawn, mini_car_testdrive, mini_car_tune,
--   mini_car_style, mini_car_nitro, mini_carwash, mini_track_start (Register).
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
local Players = game:GetService("Players")
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local CarCatalog = require(MiniShared:WaitForChild("CarCatalog"))
local CarRules = require(MiniShared:WaitForChild("CarRules"))
local TrackRules = require(MiniShared:WaitForChild("TrackRules"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local VehicleFactory = require(script.Parent:WaitForChild("VehicleFactory"))
local CityService = require(script.Parent:WaitForChild("CityService"))

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
	}
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
		MiniRules.AddMoney(d, amount)
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
local function spawnVehicle(cs, slot, car, keys, testdrive)
	local m = CarCatalog.Model(car.model)
	if not m then
		return nil, "Unbekanntes Modell."
	end
	despawn(cs, slot, "replaced")
	local cf = spawnCFrame(cs, keys)
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
		plate = testdrive and "PROBEFAHRT" or ("UCG · " .. string.format("%02d", car.id % 100)), shine = shine,
	})
	if not ok or not model then
		if ok == false then
			warn("[Autos] Bau fehlgeschlagen: " .. tostring(model))
		end
		return nil, (ok and err) or "Das Auto konnte nicht gebaut werden."
	end
	model.Parent = CarService.CarsFolder()
	VehicleFactory.Activate(model, player)
	local v = {
		slot = slot, model = model, info = VehicleFactory.Info(model), carId = testdrive and 0 or car.id,
		modelId = m.id, name = m.name, testdrive = testdrive == true, spawnedAt = t, lastOccupiedAt = t,
		occupied = false, conns = {},
	}
	cs[slot] = v
	bindVehicle(cs, v)
	seatOwner(cs, v)
	dirty(cs)
	return v
end

-- Tuning/Optik sofort auf das gefahrene Auto übertragen
local function refreshSpawned(cs, d, id)
	local v = cs.car
	if not v or v.carId ~= id or not vehicleAlive(v) then
		return
	end
	local car = CarRules.Find(d, id)
	if not car then
		return
	end
	local stats = CarRules.Stats(car)
	VehicleFactory.ApplyStats(v.model, stats)
	VehicleFactory.ApplyStyle(v.model, car, (cs.shine[id] or 0) > now())
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
		local car = CarRules.Find(d, v.carId)
		local stats = car and CarRules.Stats(car)
		if not stats or stats.nitro.level <= 0 then
			toast(cs, TEXT.nitro_none)
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

	Actions.Register("mini_carwash", function(ms, _, d, t)
		local cs = stateOf(ms)
		local v = cs.car
		local car = v and vehicleAlive(v) and CarRules.Find(d, v.carId)
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
	end)

	Actions.Register("mini_track_start", function(ms, _, d, t)
		local cs = stateOf(ms)
		local list = CarService.TrackSequence()
		if not list then
			toast(cs, TEXT.track_missing)
			return
		end
		local id = cs.car and cs.car.carId or d.games.activeCar
		local ok, car = CarRules.CanSpawn(d, id)
		if not ok then
			toast(cs, CarRules.Find(d, id) and car or TEXT.no_car)
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
end

---------------------------------------------------------------- Lebenszyklus
function CarService.Init(c)
	ctx = c
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
		local car = CarRules.Find(d, v.carId)
		if car then
			VehicleFactory.ApplyStyle(v.model, car, false)
		end
	end
	if cs.pendingReward > 0 or cs.pendingXp > 0 then
		payPending(cs)
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
	out.testdrive = false
	out.nitro = { readyAt = 0, untilAt = 0 }
	local cs = ms and states[ms.player]
	if cs and cs.p == ms.p then
		if cs.car then
			out.spawnedCar = true
			out.spawnedId = cs.car.carId
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
