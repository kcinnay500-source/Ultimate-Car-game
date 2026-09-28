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
			LeaderboardService.Push(session)
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
Actions.Register("ui_ready", function(session)
	Core.MarkDirty(session)
	LeaderboardService.Push(session)
	if not session.persistent then
		Core.Toast(session.player, Locale.T("studio_nosave"))
	end
end)
Actions.Connect(Core.Remotes.Action)

local function sendSync(session)
	session.dirty = false
	Core.Remotes.Sync:FireClient(session.player, Snapshot.Build(session.profile, Core.Now(), session.passes))
end

local function onPlayerAdded(player)
	if Core.Sessions[player] then
		return
	end
	local session = Core.NewSession(player)
	local profile, persistent, status = Profiles.Load(player.UserId)
	if player.Parent == nil or Core.Sessions[player] ~= session then
		-- Spieler hat während des Ladens verlassen: Sperre sofort freigeben
		if persistent and profile then
			session.profile = profile
			session.persistent = true
			Profiles.Save(session, true)
		end
		Core.Sessions[player] = nil
		return
	end
	if status == "locked" then
		Core.Remove(player)
		player:Kick(Locale.T("profile_locked"))
		return
	end
	session.profile = profile
	session.persistent = persistent
	session.lastSave = Core.Now()
	GoalRules.EnsureDay(profile, Core.Now())
	Purchases.OnJoin(session)
	PressService.OnJoin(session)
	WorkshopService.OnJoin(session)
	TuningService.OnJoin(session)
	session.leaderboardWrittenCode = -1
	session.loaded = true
	Core.MarkDirty(session)
end

local function onPlayerRemoving(player)
	local session = Core.Sessions[player]
	if not session or session.closing then
		return
	end
	session.closing = true
	if session.loaded then
		PressService.Tick(session, Core.Now())
		LeaderboardService.Write(session, true)
		Profiles.Save(session, true)
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
	local pending = 0
	for _, session in pairs(Core.Sessions) do
		if session.loaded and not session.closing then
			session.closing = true
			pending += 1
			task.spawn(function()
				LeaderboardService.Write(session, true)
				Profiles.Save(session, true)
				pending -= 1
			end)
		end
	end
	-- höchstens etwa 25 s warten (Roblox beendet nach 30 s)
	for _ = 1, 100 do
		if pending <= 0 then
			break
		end
		task.wait(0.25)
	end
end)

-- Server-Tick: Maschinen, Tageswechsel, Autosave, Bestenliste
task.spawn(function()
	while true do
		task.wait(Config.TickInterval)
		local now = Core.Now()
		for _, session in pairs(Core.Sessions) do
			if session.loaded and not session.closing then
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
		end
		task.spawn(LeaderboardService.Refresh, false)
	end
end)

-- Sync: geänderte Zustände gebündelt an die Besitzer
task.spawn(function()
	while true do
		task.wait(Config.SyncInterval)
		for _, session in pairs(Core.Sessions) do
			if session.loaded and not session.closing and session.dirty and session.player.Parent ~= nil then
				sendSync(session)
			end
		end
	end
end)
