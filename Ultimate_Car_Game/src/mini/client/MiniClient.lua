-- MiniClient: Einstieg der Minispiele auf dem Client. Ein ModuleScript, das GarageClient (2.4.0) lädt und mit
-- MiniClient.Start(opts) startet. Eigene ScreenGui "Minispiele" (DisplayOrder 30), eigener Listener am
-- 2.4.0-Remote GarageShared.Remotes.Event für die Kinds "mini", "mini_open" und "mini_notice".
-- Der Client zeigt nur an und sendet Absichten (mini_* über Remotes.Command); alle Ergebnisse kommen vom Server.
--
-- opts (alle optional, von GarageClient):
--   isBlocked()      true, solange QTE/Diagnose (2.4.0-Overlay) läuft: dann öffnet das Panel nicht bzw. schließt sich
--   isTabletOpen()   true, solange das 2.4.0-Tablet offen ist: öffnet der Spieler das Tablet, schließt sich das Panel
--   closeTablet()    schließt das 2.4.0-Tablet (beim Öffnen des Panels)
--   openTablet(key)  öffnet eine Tablet-Seite (z. B. "workshop", "shop")
--   hideHud(isOpen)  wird bei jedem Öffnen/Schließen gerufen, damit 2.4.0-HUD und Fahrzeug-Knöpfe sich aus-/einblenden
--   toast(text)      der 2.4.0-Toast (für Hinweise, die nur der Client erzeugt)
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local MiniClient = {}

-- Gemeinsame Zahlenformatierung (auch für GarageClient.fmt). Begrenztes Warten: fehlt etwas, bleibt die Werkstatt spielbar.
local MiniLocale
do
	local ok, mod = pcall(function()
		local shared = ReplicatedStorage:WaitForChild("GarageShared", 10)
		local mini = shared and shared:WaitForChild("Mini", 10)
		local m = mini and mini:WaitForChild("MiniLocale", 10)
		return m and require(m)
	end)
	if ok and type(mod) == "table" and type(mod.Number) == "function" then
		MiniLocale = mod
	end
end
MiniClient.Number = MiniLocale and MiniLocale.Number or nil

local PAGES = {
	overview = "OverviewUI",
	press = "PressUI",
	tuning = "TuningUI",
	scrapyard = "ScrapyardUI",
	quiz = "QuizUI",
	parking = "ParkingUI",
	goals = "GoalsUI",
	leaderboard = "LeaderboardUI",
	map = "MapUI",
	shop = "ShopUI",
}

local opts = {}
local started, starting = false, false
local UI, Remote, Effects, City
local Modules = {}
local latest, latestAt = nil, 0
local warned = {}

local function warnOnce(key, msg)
	if not warned[key] then
		warned[key] = true
		warn("[Minispiele] " .. msg)
	end
end

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, result = pcall(fn, ...)
	if ok then
		return result
	end
	warnOnce(tostring(fn), tostring(result))
	return nil
end

local function dec(n)
	return (string.format("%.2f", tonumber(n) or 1):gsub("%.", ","))
end

---------------------------------------------------------------- Öffnen / Schließen
function MiniClient.IsOpen()
	return UI ~= nil and UI.IsOpen == true
end

function MiniClient.IsBlocked()
	return call(opts.isBlocked) == true
end

-- Öffnet das Panel (optional auf einem Tab). Verweigert während QTE/Diagnose; schließt vorher das Tablet.
function MiniClient.Open(tab)
	if not started or not UI then
		return false
	end
	if MiniClient.IsBlocked() then
		return false
	end
	call(opts.closeTablet)
	if type(tab) ~= "string" or not UI.Pages[tab] then
		tab = nil
	end
	UI.Open(tab)
	return true
end

function MiniClient.Close()
	if UI then
		UI.Close()
	end
end

function MiniClient.Toggle(tab)
	if MiniClient.IsOpen() then
		MiniClient.Close()
		return false
	end
	return MiniClient.Open(tab)
end

-- Hinweis, den nur der Client erzeugt: 2.4.0-Toast (bei offenem Panel zusätzlich der deckungsgleiche Spiegel)
function MiniClient.Toast(text)
	if type(text) ~= "string" or text == "" then
		return
	end
	if opts.toast then
		call(opts.toast, text)
		if UI then
			UI.MirrorToast(text)
		end
	elseif UI then
		UI.MirrorToast(text, true)
	end
end

function MiniClient.Snapshot()
	return latest
end

---------------------------------------------------------------- Anzeige
local function renderVisible()
	if not latest or not MiniClient.IsOpen() then
		return
	end
	local m = Modules[UI.CurrentTab]
	if m and m.Render then
		local ok, err = pcall(m.Render, latest)
		if not ok then
			warnOnce("render_" .. tostring(UI.CurrentTab), "Anzeige " .. tostring(UI.CurrentTab) .. ": " .. tostring(err))
		end
	end
end

local function renderHeader()
	if not latest or not UI or not UI.HeaderInfo then
		return
	end
	local scrap = Modules.press and Modules.press.DisplayScrap and call(Modules.press.DisplayScrap) or (latest.press and latest.press.scrap) or 0
	UI.HeaderInfo.Text = MiniLocale.Credits(latest.credits or 0) .. " · " .. MiniLocale.Scrap(scrap) .. " · Level " .. tostring(latest.level or 1)
end

local function onSnapshot(s)
	if type(s) ~= "table" then
		return
	end
	latest, latestAt = s, os.clock()
	if Modules.press and Modules.press.OnSnapshot then
		call(Modules.press.OnSnapshot, s)
	end
	renderHeader()
	renderVisible()
end

-- mini_notice {kind=..., ...}
local function onNotice(data)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "offline" then
		local text = data.text
		if type(text) ~= "string" and tonumber(data.scrap) then
			text = MiniLocale.T("offline_press", MiniLocale.Scrap(tonumber(data.scrap)))
		end
		MiniClient.Toast(text)
	elseif kind == "rebirth" then
		MiniClient.Toast("Rebirth geschafft! Schrott-Multiplikator jetzt ×" .. dec(data.multiplier))
	elseif kind == "quiz" then
		call(Modules.quiz and Modules.quiz.OnResult, data)
	elseif kind == "scrapyard" then
		call(Modules.scrapyard and Modules.scrapyard.OnResult, data)
	elseif kind == "leaderboard" then
		call(Modules.leaderboard and Modules.leaderboard.OnData, type(data.view) == "table" and data.view or data)
	end
end

---------------------------------------------------------------- Start
function MiniClient.Start(o)
	if started or starting then
		return
	end
	starting = true
	opts = type(o) == "table" and o or {}
	assert(MiniLocale, "MiniLocale fehlt (ReplicatedStorage.GarageShared.Mini)")
	local folder = script.Parent
	UI = require(folder:WaitForChild("MiniUI"))
	Remote = require(folder:WaitForChild("MiniRemote"))
	Effects = require(folder:WaitForChild("MiniEffects"))
	City = require(folder:WaitForChild("CityClient"))

	UI.Build()
	local ctx = {
		UI = UI,
		Remote = Remote,
		Effects = Effects,
		City = City,
		Locale = MiniLocale,
		Toast = MiniClient.Toast,
		Close = MiniClient.Close,
		OpenTablet = opts.openTablet and function(key)
			MiniClient.Close()
			call(opts.openTablet, key)
		end or nil,
	}
	-- Jeder Bereich für sich: ein defekter Bereich darf die anderen nicht mitreißen
	for _, tab in ipairs(UI.Tabs) do
		local page = UI.Pages[tab.key]
		local ok, err = pcall(function()
			local m = require(folder:WaitForChild(PAGES[tab.key], 10))
			m.Build(page, ctx)
			Modules[tab.key] = m
		end)
		if not ok then
			warnOnce("build_" .. tab.key, "Bereich " .. tab.key .. " nicht geladen: " .. tostring(err))
			UI.Small(page, "Dieser Bereich konnte nicht geladen werden.", 1)
		end
	end

	UI.OnTabShown = function(key)
		local m = Modules[key]
		if m and m.OnShow then
			call(m.OnShow)
		end
		renderVisible()
		if key == "leaderboard" then
			Remote.Send("mini_leaderboard_refresh")
		end
	end
	UI.OnOpenChanged = function(isOpen)
		if isOpen and (not latest or os.clock() - latestAt > 5) then
			Remote.Send("mini_sync")
		end
		call(opts.hideHud, isOpen)
	end

	local Event = ReplicatedStorage:WaitForChild("GarageShared"):WaitForChild("Remotes"):WaitForChild("Event")
	Event.OnClientEvent:Connect(function(kind, value)
		if kind == "mini" then
			onSnapshot(value)
		elseif kind == "mini_open" then
			local tab = type(value) == "table" and value.tab or value
			if type(tab) == "string" and UI.Pages[tab] then
				MiniClient.Open(tab)
			end
		elseif kind == "mini_notice" then
			onNotice(value)
		elseif kind == "toast" then
			-- Den Server-Toast zeigt 2.4.0 selbst; bei offenem Panel läge er verdeckt darunter, daher der Spiegel.
			if type(value) == "string" and UI.IsOpen then
				UI.MirrorToast(value)
			end
		end
	end)
	started = true

	-- Klickpakete der Presse etwa alle 0,5 s
	local MiniConfig
	pcall(function()
		MiniConfig = require(ReplicatedStorage.GarageShared.Mini:WaitForChild("MiniConfig", 10))
	end)
	local interval = MiniConfig and MiniConfig.ClickBatchInterval or 0.5
	task.spawn(function()
		while UI.Gui and UI.Gui.Parent do
			task.wait(interval)
			if Modules.press and Modules.press.Flush then
				call(Modules.press.Flush)
			end
		end
	end)

	-- Pro Frame: nur leichte Anzeige-Updates des sichtbaren Bereichs und der gegenseitige Ausschluss
	local headerTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		if not UI.IsOpen then
			return
		end
		-- QTE/Diagnose begonnen oder Tablet geöffnet: Panel weicht (beides liegt sonst verdeckt darunter)
		if MiniClient.IsBlocked() or call(opts.isTabletOpen) == true then
			MiniClient.Close()
			return
		end
		local m = Modules[UI.CurrentTab]
		if m and m.Step then
			local ok, err = pcall(m.Step)
			if not ok then
				warnOnce("step_" .. tostring(UI.CurrentTab), tostring(err))
			end
		end
		headerTimer += dt
		if headerTimer >= 0.1 then
			headerTimer = 0
			renderHeader()
		end
	end)

	-- Stadt-Animationen (rein optisch; wartet still, falls Workspace.City fehlt)
	local ok, err = pcall(City.Start)
	if not ok then
		warnOnce("city", "Stadt-Animationen: " .. tostring(err))
	end

	-- Erster Snapshot: kommt normalerweise nach "hello"; falls er vor dem Listener eintraf, nachfragen
	task.spawn(function()
		local tries = 0
		task.wait(3)
		while not latest and tries < 10 and UI.Gui and UI.Gui.Parent do
			tries += 1
			Remote.Send("mini_sync")
			task.wait(3)
		end
	end)
end

return MiniClient
