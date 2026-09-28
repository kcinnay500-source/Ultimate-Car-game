-- Main (Client): baut die Oberfläche, bindet die Spiel-Module ein und verarbeitet Sync und Hinweise.
-- Der Client zeigt nur an und sendet Absichten; alle Ergebnisse kommen vom Server.
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))

-- Place-Build: Module liegen im Ordner "Client" neben diesem Skript; Rojo: Skript liegt selbst im Ordner "Client"
local Client = script.Parent.Name == "Client" and script.Parent or script.Parent:WaitForChild("Client")
local UI = require(Client:WaitForChild("UI"))
local Remote = require(Client:WaitForChild("Remote"))
local Effects = require(Client:WaitForChild("Effects"))

local Modules = {
	overview = require(Client:WaitForChild("OverviewUI")),
	press = require(Client:WaitForChild("PressUI")),
	tuning = require(Client:WaitForChild("TuningUI")),
	workshop = require(Client:WaitForChild("WorkshopUI")),
	scrapyard = require(Client:WaitForChild("ScrapyardUI")),
	quiz = require(Client:WaitForChild("QuizUI")),
	parking = require(Client:WaitForChild("ParkingUI")),
	goals = require(Client:WaitForChild("GoalsUI")),
	leaderboard = require(Client:WaitForChild("LeaderboardUI")),
	shop = require(Client:WaitForChild("ShopUI")),
}

UI.Build()
local ctx = { UI = UI, Remote = Remote, Effects = Effects }
for _, tab in ipairs(UI.Tabs) do
	Modules[tab.key].Build(UI.Pages[tab.key], ctx)
end

local latest = nil

local function renderVisible()
	if not latest or not UI.IsOpen then
		return
	end
	local m = Modules[UI.CurrentTab]
	if m and m.Render then
		m.Render(latest)
	end
end

local function renderHud()
	if not latest then
		return
	end
	UI.HudCredits.Text = Locale.Credits(latest.credits)
	UI.HudScrap.Text = Locale.Scrap(Modules.press.DisplayScrap())
	UI.HudLevel.Text = "Level " .. latest.level .. " · Ruf " .. latest.reputation
	UI.SetProgress(UI.HudXp, latest.xp / latest.xpNeeded)
	UI.GoalText.Text = "Ziel: " .. latest.goals.next.text
	UI.GoalTab = latest.goals.next.tab
	UI.SetProgress(UI.GoalFill, latest.goals.next.progress)
	UI.HeaderInfo.Text = Locale.Credits(latest.credits) .. " · " .. Locale.Scrap(Modules.press.DisplayScrap()) .. " · Level " .. latest.level
end

UI.OnTabShown = function(key)
	renderVisible()
	if key == "leaderboard" then
		Remote.Send("leaderboard_refresh")
	end
end

Remote.Sync.OnClientEvent:Connect(function(snapshot)
	if type(snapshot) ~= "table" then
		return
	end
	latest = snapshot
	Modules.press.OnSnapshot(snapshot)
	renderHud()
	renderVisible()
end)

Remote.Notice.OnClientEvent:Connect(function(kind, data)
	data = type(data) == "table" and data or {}
	if kind == "toast" then
		UI.Toast(data.text)
	elseif kind == "open" then
		UI.Open(data.tab)
	elseif kind == "offline" then
		UI.Toast(data.text)
	elseif kind == "levelup" then
		UI.Toast(Locale.T("level_up", data.level, Locale.Credits(data.credits or 0)))
	elseif kind == "rebirth" then
		UI.Toast("Rebirth geschafft! Schrott-Multiplikator jetzt ×" .. string.format("%.2f", data.multiplier or 1):gsub("%.", ","))
	elseif kind == "quiz" then
		Modules.quiz.OnResult(data)
	elseif kind == "scrapyard" then
		Modules.scrapyard.OnResult(data)
	elseif kind == "leaderboard" then
		Modules.leaderboard.OnData(data)
	end
end)

-- Klickpakete etwa alle 0,5 s
task.spawn(function()
	while true do
		task.wait(Config.ClickBatchInterval)
		Modules.press.Flush()
	end
end)

-- Pro Frame: nur leichte Anzeige-Updates des sichtbaren Bereichs
local hudTimer = 0
RunService.Heartbeat:Connect(function(dt)
	if UI.IsOpen then
		local m = Modules[UI.CurrentTab]
		if m and m.Step then
			m.Step()
		end
	end
	hudTimer += dt
	if hudTimer >= 0.1 then
		hudTimer = 0
		renderHud()
	end
end)

Remote.Send("ui_ready")
