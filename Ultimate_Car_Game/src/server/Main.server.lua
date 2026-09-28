-- Main: startet den Server. Baut die Welt, legt Remotes an, verwaltet Beitritt/Verlassen,
-- Server-Tick (Maschinen, Tageswechsel), Sync an die Clients, Autosave und Bestenliste.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))
local Net = require(Shared:WaitForChild("Net"))
local Snapshot = require(Shared:WaitForChild("Snapshot"))
local GoalRules = require(Shared:WaitForChild("GoalRules"))

local Server = script.Parent
local Core = require(Server:WaitForChild("Core"))
local Profiles = require(Server:WaitForChild("Profiles"))
local Actions = require(Server:WaitForChild("Actions"))
local World = require(Server:WaitForChild("World"))
local PressService = require(Server:WaitForChild("PressService"))
local WorkshopService = require(Server:WaitForChild("WorkshopService"))
local TuningService = require(Server:WaitForChild("TuningService"))
local SideGamesService = require(Server:WaitForChild("SideGamesService"))
local GoalsService = require(Server:WaitForChild("GoalsService"))
local LeaderboardService = require(Server:WaitForChild("LeaderboardService"))
local Purchases = require(Server:WaitForChild("Purchases"))

-- Welt zuerst, damit Spieler auf festem Boden erscheinen
World.Build()

-- Remotes
local folder = Instance.new("Folder")
folder.Name = Net.Folder
local function remote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = folder
	return r
end
Core.Remotes = {
	Action = remote(Net.Action),
	Sync = remote(Net.Sync),
	Notice = remote(Net.Notice),
}
folder.Parent = ReplicatedStorage

Profiles.Init()
LeaderboardService.Init()
LeaderboardService.OnUpdated = function(cache)
	World.UpdateBoard(cache)
	for _, session in pairs(Core.Sessions) do
		if session.loaded and not session.closing then
			local ok, err = pcall(LeaderboardService.Push, session)
			if not ok then
				warn("[Main] Bestenliste für " .. tostring(session.userId) .. ": " .. tostring(err))
			end
		end
	end
end
Purchases.Init()

PressService.Register(Actions)
WorkshopService.Register(Actions)
TuningService.Register(Actions)
SideGamesService.Register(Actions)
GoalsService.Register(Actions)
LeaderboardService.Register(Actions)
Purchases.Register(Actions)
local function welcome(session)
	LeaderboardService.Push(session)
	if not session.persistent then
		Core.Toast(session.player, Locale.T("studio_nosave"))
	end
end

Actions.Register("ui_ready", function(session)
	Core.MarkDirty(session)
	welcome(session)
end)
Actions.Connect(Core.Remotes.Action)

local function sendSync(session)
	session.dirty = false
	Core.Remotes.Sync:FireClient(session.player, Snapshot.Build(session.profile, Core.Now(), session.passes))
end

-- Speichert beim Verlassen/Herunterfahren: Profil zuerst (gibt die Sperre frei), dann Bestenliste.
-- Core.PendingSaves hält BindToClose offen, bis alle laufenden Speichervorgänge fertig sind.
local function finalSave(session)
	Core.PendingSaves += 1
	local ok, err = pcall(function()
		Profiles.Save(session, true)
		LeaderboardService.Write(session, true)
	end)
	Core.PendingSaves -= 1
	if not ok then
		warn("[Main] Speichern beim Verlassen fehlgeschlagen: " .. tostring(err))
	end
end

local function leftDuringJoin(player, session)
	return player.Parent == nil or Core.Sessions[player] ~= session or session.closing
end

local function onPlayerAdded(player)
	if Core.Sessions[player] then
		return
	end
	local session = Core.NewSession(player)
	-- Alle Schritte, die warten können, laufen vor dem Laden des Profils
	Purchases.OnJoin(session)
	if leftDuringJoin(player, session) then
		Core.Remove(player)
		return
	end
	local profile, persistent, status = Profiles.Load(player.UserId, session.lockId)
	if leftDuringJoin(player, session) then
		-- Spieler hat während des Ladens verlassen: Sperre sofort freigeben
		if persistent and profile then
			session.profile = profile
			session.persistent = true
			finalSave(session)
		end
		Core.Remove(player)
		return
	end
	if status == "locked" or status == "failed" then
		Core.Remove(player)
		player:Kick(Locale.T(status == "locked" and "profile_locked" or "profile_failed"))
		return
	end
	-- Ab hier wartet nichts mehr: die Sitzung ist sofort vollständig
	session.profile = profile
	session.persistent = persistent
	session.lastSave = Core.Now()
	GoalRules.EnsureDay(profile, Core.Now())
	PressService.OnJoin(session)
	WorkshopService.OnJoin(session)
	TuningService.OnJoin(session)
	session.leaderboardWrittenCode = -1
	session.loaded = true
	Core.MarkDirty(session)
	welcome(session)
end

local function onPlayerRemoving(player)
	local session = Core.Sessions[player]
	if not session or session.closing then
		return
	end
	session.closing = true
	if session.loaded then
		pcall(PressService.Tick, session, Core.Now())
		finalSave(session)
	end
	Core.Remove(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)
for _, player in ipairs(Players:GetPlayers()) do
	task.spawn(onPlayerAdded, player)
end

-- Prompts auf dem Hof öffnen die Oberfläche nur für den auslösenden Spieler (mit Reichweitenprüfung)
for _, entry in ipairs(World.Prompts) do
	entry.prompt.Triggered:Connect(function(player)
		if not Core.Get(player) then
			return
		end
		local character = player.Character
		local root = character and character:FindFirstChild("HumanoidRootPart")
		local anchor = entry.prompt.Parent
		if not root or not anchor:IsA("BasePart") then
			return
		end
		if (root.Position - anchor.Position).Magnitude > entry.prompt.MaxActivationDistance + Config.StationRangeSlack then
			return
		end
		Core.Notify(player, "open", { tab = entry.tab })
	end)
end

game:BindToClose(function()
	for _, session in pairs(Core.Sessions) do
		if session.loaded and not session.closing then
			session.closing = true
			task.spawn(finalSave, session)
		end
	end
	-- Auch Speichervorgänge von Spielern abwarten, die gerade verlassen haben (höchstens etwa 25 s)
	for _ = 1, 100 do
		if Core.PendingSaves <= 0 then
			break
		end
		task.wait(0.25)
	end
end)

-- Server-Tick: Maschinen, Tageswechsel, Autosave, Bestenliste. Fehler einer Sitzung stoppen nie die Schleife.
local function tickSession(session, now)
	PressService.Tick(session, now)
	GoalsService.Tick(session, now)
	Core.MarkDirty(session)
	if now - session.lastSave >= Config.AutosaveInterval then
		session.lastSave = now
		task.spawn(Profiles.Save, session, false)
	end
	if now - session.leaderboardWrittenAt >= Config.LeaderboardWriteInterval then
		task.spawn(LeaderboardService.Write, session, false)
	end
end

task.spawn(function()
	while true do
		task.wait(Config.TickInterval)
		local now = Core.Now()
		for _, session in pairs(Core.Sessions) do
			if session.loaded and not session.closing then
				local ok, err = pcall(tickSession, session, now)
				if not ok then
					warn("[Main] Tick für " .. tostring(session.userId) .. ": " .. tostring(err))
				end
			end
		end
		task.spawn(LeaderboardService.Refresh, false)
	end
end)

-- Sync: geänderte Zustände gebündelt an die Besitzer (höchstens alle SyncInterval Sekunden)
task.spawn(function()
	while true do
		task.wait(Config.SyncInterval)
		for _, session in pairs(Core.Sessions) do
			if session.loaded and not session.closing and session.dirty and session.player.Parent ~= nil then
				local ok, err = pcall(sendSync, session)
				if not ok then
					warn("[Main] Sync für " .. tostring(session.userId) .. ": " .. tostring(err))
				end
			end
		end
	end
end)
