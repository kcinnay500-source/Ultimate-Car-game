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
--   subscribe(fn)    meldet fn bei jedem Wechsel von 2.4.0-Dialog (InteractionOverlay), Tablet und Fahrzeugknöpfen an:
--                    dann blendet RefreshOverlays sofort alle Phase-4-Karten/-Abzeichen aus bzw. ein (nicht erst im
--                    nächsten 0,2-s-Takt), damit nie eine Karte im selben Moment über einem 2.4.0-Dialog liegt.
-- Alle Phase-4-Oberflächen außerhalb des Panels (Tutorial 17, Freischaltungen 18, Missionen 16, Abzeichen 19) liegen
-- UNTER dem 2.4.0-UI (20); nur das Panel selbst (30) liegt darüber.
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
	lobby = "LobbyUI",
	tycoon = "TycoonUI",
	buildings = "BuildingsUI", -- Meilenstein 6: Open-World-Gebäude, Passiv-Modus
	story = "StoryUI", -- Meilenstein 7: Story, Kiesplatz-Verkauf, Nebenmissionen
	unlocks = "UnlocksUI",
	prestige = "PrestigeUI",
	overview = "OverviewUI",
	press = "PressUI",
	tuning = "TuningUI",
	dealer = "DealerUI",
	track = "TrackUI",
	carwash = "CarwashUI",
	scrapyard = "ScrapyardUI",
	quiz = "QuizUI",
	parking = "ParkingUI",
	goals = "GoalsUI",
	leaderboard = "LeaderboardUI",
	map = "MapUI",
	shop = "ShopUI",
	auction = "AuctionUI",
	arcade = "ArcadeUI",
}

local opts = {}
local started, starting = false, false
local UI, Remote, Effects, City
local Drive -- DriveClient (Fahren: Tacho, Fahrregler, Nitro)
local Tutorial -- TutorialUI (Ausbaustufe 4: Tutorial-Karte, Beginner-Hinweise; kein Tab)
local Tycoon -- TycoonClient (Meilenstein 4: Bargeld-Abzeichen, Pad-Blitz, Produzenten-Animationen; kein Tab)
local Mission -- MissionClient (Meilenstein 7: Welt-Marker, Missions-/Kapitel-Karten, NPC-Kunden; eigener Heartbeat, kein Tab)
local Unlocks -- GarageShared.Mini.Unlocks (repliziert): Sperrhinweis je Tab
local StartChoice -- StartUI (Startwahl in der Open World, ScreenGui "StartChoice"; optional, nur wenn das Modul da ist)
local Modules = {}
local LockNotes = {} -- [tab] = TextLabel „Ab Level n: …“ über dem Bereich (Bereiche bleiben sichtbar, nur markiert)
local latest, latestAt = nil, 0
local lastMode = nil -- Snapshot-Feld mode des vorigen Snapshots (Lobby öffnet sich einmal je Moduswechsel)
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

-- Oberkante der Toasts (2.4.0-Toast und Spiegel): während der Fahrt unter dem Tacho, sonst 62
function MiniClient.ToastTop()
	local off = Drive and call(Drive.ToastOffset)
	return type(off) == "number" and off or 62
end

function MiniClient.Snapshot()
	return latest
end

-- Alle Karten/Abzeichen außerhalb des Panels sofort neu ein-/ausblenden (2.4.0-Dialog, Tablet, Panel, Tacho)
function MiniClient.RefreshOverlays()
	if Tutorial then
		call(Tutorial.Refresh)
	end
	call(Modules.unlocks and Modules.unlocks.Refresh)
	call(Modules.prestige and Modules.prestige.Refresh)
	if Tycoon then
		call(Tycoon.Refresh)
	end
	if Mission then
		call(Mission.Refresh)
	end
	if StartChoice then
		call(StartChoice.Render) -- Startwahl weicht 2.4.0-Dialog und Tablet aus (liegt sonst mit 40 darüber)
	end
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

-- Vom Server weggelassene große Felder (MiniSnapshot.StickyKeys: cars, catalog) aus dem vorigen Snapshot übernehmen;
-- unlocks.list (PHASE4_CONTRACT §11, nur bei vollen Snapshots) ebenso
local STICKY = { "cars", "catalog" }

-- Sperrhinweis über einem Bereich, dessen Freischaltung noch fehlt (der Bereich bleibt sichtbar)
local function renderLockNotes(s)
	if not Unlocks then
		return
	end
	for tab, label in pairs(LockNotes) do
		local entry = Unlocks.ForTab(tab)
		local locked = entry ~= nil and not Unlocks.TabAllowed({ level = s.level }, tab)
		if locked then
			label.Text = "Ab Level " .. tostring(entry.level) .. ": " .. tostring(entry.title) .. ". Bis dahin bringen Aufträge in der Werkstatt XP."
		end
		label.Visible = locked
	end
end

local function onSnapshot(s)
	if type(s) ~= "table" then
		return
	end
	if latest then
		for _, key in ipairs(STICKY) do
			if s[key] == nil and latest[key] ~= nil then
				s[key] = latest[key]
			end
		end
		if type(s.unlocks) == "table" and s.unlocks.list == nil and type(latest.unlocks) == "table" then
			s.unlocks.list = latest.unlocks.list
		end
		-- story.missions/chapters (PHASE4_CONTRACT §11: sticky, nur bei vollen Snapshots)
		if type(s.story) == "table" and type(latest.story) == "table" then
			if s.story.missions == nil then
				s.story.missions = latest.story.missions
			end
			if s.story.chapters == nil then
				s.story.chapters = latest.story.chapters
			end
		end
		-- shop.catalog (PHASE4_CONTRACT §11: sticky, nur bei vollen Snapshots)
		if type(s.shop) == "table" and s.shop.catalog == nil and type(latest.shop) == "table" then
			s.shop.catalog = latest.shop.catalog
		end
	end
	latest, latestAt = s, os.clock()
	if Modules.press and Modules.press.OnSnapshot then
		call(Modules.press.OnSnapshot, s)
	end
	if Drive then
		call(Drive.OnSnapshot, s)
	end
	call(Modules.prestige and Modules.prestige.OnSnapshot, s) -- Abzeichen (Rang/Level/nächste Freischaltung) auch bei geschlossenem Panel
	if Tutorial then
		call(Tutorial.OnSnapshot, s)
	end
	if Tycoon then
		call(Tycoon.OnSnapshot, s) -- Bargeld-Abzeichen im Modus tycoon, Blitz bei Stufenaufstieg
	end
	if Mission then
		call(Mission.OnSnapshot, s) -- Missions-Marker, Kapitel-Intro bei neuem Kapitel
	end
	if StartChoice then
		call(StartChoice.OnSnapshot, s) -- Startwahl (snapshot.start.pending)
	end
	if Modules.story and Modules.story.OnSnapshot then
		call(Modules.story.OnSnapshot, s) -- Preistafel am Kiesplatz und Kunden-Countdown auch bei geschlossenem Panel
	end
	renderLockNotes(s)
	renderHeader()
	renderVisible()
	-- Lobby: beim Ankommen (erster Snapshot oder Moduswechsel) öffnet sich der Lobby-Tab einmal von selbst
	local mode = s.mode
	if mode ~= lastMode then
		lastMode = mode
		if mode == "lobby" and UI and UI.Pages.lobby and not MiniClient.IsBlocked() then
			MiniClient.Open("lobby")
		end
	end
end

-- mini_notice {kind=..., ...}
local function onNotice(data)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	-- Autos: jeder Bereich filtert selbst nach kind (car_*, testdrive_end, track_*, carwash)
	for _, key in ipairs({ "dealer", "track", "carwash" }) do
		local m = Modules[key]
		if m and m.OnNotice then
			call(m.OnNotice, data)
		end
	end
	if Drive then
		call(Drive.OnNotice, data)
	end
	-- Der Server hat den Spieler in ein Auto gesetzt (Autohaus, Probefahrt, Teststrecke, Waschstraße …) bzw. das
	-- Zeitfahren läuft an: Panel schließen, sonst verdeckt es Sicht und Countdown, und auf dem Handy bleibt die
	-- Touch-Steuerung (Stick) ausgeblendet, während die Uhr schon läuft.
	if (kind == "car_spawned" or kind == "track_start") and MiniClient.IsOpen() then
		MiniClient.Close()
	end
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
	elseif kind == "auction_update" or kind == "auction_won" or kind == "auction_sold" then
		call(Modules.auction and Modules.auction.OnNotice, data)
	elseif type(kind) == "string" and string.sub(kind, 1, 7) == "arcade_" then
		call(Modules.arcade and Modules.arcade.OnNotice, data)
	elseif kind == "leaderboard" then
		call(Modules.leaderboard and Modules.leaderboard.OnData, type(data.view) == "table" and data.view or data)
	elseif kind == "unlock" then
		-- Freischaltung erreicht: Karte (UnlocksUI, Hinweistext im Feld hint), Abzeichen blinkt, Tabelle neu
		call(Modules.unlocks and Modules.unlocks.OnNotice, data)
		call(Modules.prestige and Modules.prestige.Flash)
		if Tutorial then
			call(Tutorial.OnNotice, data) -- zeigt die Karte nur, wenn UnlocksUI keine hat
		end
	elseif kind == "prestige" then
		call(Modules.prestige and Modules.prestige.OnNotice, data)
	elseif kind == "tycoon_market" or kind == "tycoon_stage" or kind == "trade" or kind == "tycoon_choose" or kind == "tycoon" then
		-- Tycoon: Marktplatz-Tafel, Stufen/Handel (Neuzeichnen), Start-Pad öffnet den Tab (TycoonClient)
		call(Modules.tycoon and Modules.tycoon.OnNotice, data)
		if Tycoon then
			call(Tycoon.OnNotice, data)
		end
	elseif kind == "mode" or kind == "party" or kind == "lobby" then
		call(Modules.lobby and Modules.lobby.OnNotice, data)
		if kind == "lobby" and Tutorial and type(data.hint) == "string" then
			call(Tutorial.ShowHint, data.hint, data.hintId) -- Beginner-Hinweis der Lobby-Station als Karte
		end
	elseif kind == "tutorial" or kind == "hint" then
		if Tutorial then
			call(Tutorial.OnNotice, data)
		end
	elseif kind == "ow_ready" or kind == "ow_build" or kind == "ow_collect" or kind == "ow_passive" then
		call(Modules.buildings and Modules.buildings.OnNotice, data) -- Gebäude: Karten neu, Countdown, Passiv-Schalter
	elseif kind == "start" then
		if StartChoice then
			call(StartChoice.OnNotice, data) -- Startwahl bestätigt/abgelehnt
		end
	elseif kind == "story" or kind == "mission" then
		-- Story: Verkauf, Mission gestartet/geschafft/abgeholt, Lieferung, Co-op-Fortschritt (Tab + Welt-Karten)
		call(Modules.story and Modules.story.OnNotice, data)
		if Mission then
			call(Mission.OnNotice, data)
		end
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
	UI.ToastTop = MiniClient.ToastTop
	local ctx = {
		UI = UI,
		Remote = Remote,
		Effects = Effects,
		City = City,
		Locale = MiniLocale,
		Toast = MiniClient.Toast,
		Close = MiniClient.Close,
		IsTabletOpen = function()
			return call(opts.isTabletOpen) == true
		end,
		IsBlocked = MiniClient.IsBlocked,
		-- QTE/Diagnose läuft, das 2.4.0-Tablet oder das Minispiel-Panel ist offen: StartUI blendet sich dann aus, damit
		-- die Startwahl (DisplayOrder 40) nie über einem 2.4.0-Dialog oder dem Panel liegt; danach kommt sie wieder
		IsGarageBusy = function()
			return MiniClient.IsBlocked() or call(opts.isTabletOpen) == true or MiniClient.IsOpen()
		end,
		Open = MiniClient.Open, -- Tab öffnen (schließt das Tablet; TycoonClient nutzt es für das Start-Pad)
		OpenTablet = opts.openTablet and function(key)
			MiniClient.Close()
			call(opts.openTablet, key)
		end or nil,
	}
	pcall(function()
		Unlocks = require(ReplicatedStorage.GarageShared.Mini:WaitForChild("Unlocks", 10))
	end)
	-- Jeder Bereich für sich: ein defekter Bereich darf die anderen nicht mitreißen
	for _, tab in ipairs(UI.Tabs) do
		local page = UI.Pages[tab.key]
		if Unlocks and Unlocks.ForTab(tab.key) then
			-- Bereich mit Level-Voraussetzung: Sperrhinweis oben (sichtbar, sobald der Snapshot das Level kennt)
			local note = UI.Small(page, "", 0)
			note.Name = "LockNote"
			note.TextColor3 = UI.Theme.yellow
			note.Visible = false
			LockNotes[tab.key] = note
		end
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

	-- Tutorial-Karte, Marker und Hinweis-Karten (eigene ScreenGui "Tutorial", läuft unabhängig vom Panel)
	local okTut, errTut = pcall(function()
		Tutorial = require(folder:WaitForChild("TutorialUI", 10))
		Tutorial.Start(ctx)
	end)
	if not okTut then
		Tutorial = nil
		warnOnce("tutorial", "Tutorial nicht geladen: " .. tostring(errTut))
	end

	-- Fahren (eigene ScreenGui "Fahren", läuft unabhängig vom Panel)
	local okDrive, errDrive = pcall(function()
		Drive = require(folder:WaitForChild("DriveClient", 10))
		Drive.Start(ctx)
	end)
	if not okDrive then
		Drive = nil
		warnOnce("drive", "Fahren nicht geladen: " .. tostring(errDrive))
	end

	-- Tycoon (eigene ScreenGui "TycoonHUD", eigener Heartbeat; läuft unabhängig vom Panel)
	local okTy, errTy = pcall(function()
		Tycoon = require(folder:WaitForChild("TycoonClient", 10))
		Tycoon.Start(ctx)
	end)
	if not okTy then
		Tycoon = nil
		warnOnce("tycoon", "Tycoon nicht geladen: " .. tostring(errTy))
	end

	-- Story-Missionen in der Welt (eigene ScreenGui "Missionen", eigener Heartbeat – MiniClient ruft Step nicht auf)
	local okM, errM = pcall(function()
		Mission = require(folder:WaitForChild("MissionClient", 10))
		Mission.Start(ctx)
	end)
	if not okM then
		Mission = nil
		warnOnce("mission", "Missionen nicht geladen: " .. tostring(errM))
	end

	-- Startwahl (StartUI, optional): nur laden, wenn das Modul im Place ist – fehlt es, läuft alles wie bisher
	local startNode = folder:FindFirstChild("StartUI")
	if startNode then
		local okSt, errSt = pcall(function()
			StartChoice = require(startNode)
			StartChoice.Start(ctx)
		end)
		if not okSt then
			StartChoice = nil
			warnOnce("start", "Startwahl nicht geladen: " .. tostring(errSt))
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
		MiniClient.RefreshOverlays()
	end
	-- 2.4.0 meldet Dialog/Tablet/Fahrzeugknöpfe sofort (GarageClient, opts.subscribe)
	call(opts.subscribe, MiniClient.RefreshOverlays)

	local Event = ReplicatedStorage:WaitForChild("GarageShared"):WaitForChild("Remotes"):WaitForChild("Event")
	Event.OnClientEvent:Connect(function(kind, value)
		if kind == "mini" then
			onSnapshot(value)
		elseif kind == "mini_open" then
			local tab = type(value) == "table" and value.tab or value
			if type(value) == "table" and value.page == "credits" and opts.openTablet and not MiniClient.IsBlocked() then
				-- Credit-Center: 2.4.0-Credits-Shop im Tablet (dort auch die Game Passes)
				MiniClient.Close()
				call(opts.openTablet, "shop")
			elseif type(tab) == "string" and UI.Pages[tab] then
				MiniClient.Open(tab)
				if tab == "arcade" and type(value) == "table" and type(value.game) == "string" then
					call(Modules.arcade and Modules.arcade.Select, value.game)
				elseif tab == "lobby" and type(value) == "table" and type(value.action) == "string" then
					-- Lobby-Station: die gedrückte Aktion (Portal, Einstellungen, Party, Tutorial) ist vorgewählt
					call(Modules.lobby and Modules.lobby.OnNotice, { kind = "lobby", action = value.action })
				end
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
	local overlayTimer = 0
	RunService.Heartbeat:Connect(function(dt)
		if Tutorial then
			call(Tutorial.Step, dt) -- auch bei geschlossenem Panel (Marker, Sichtbarkeit; drosselt selbst auf 0,2 s)
		end
		overlayTimer += dt
		if overlayTimer >= 0.2 then
			overlayTimer = 0
			call(Modules.unlocks and Modules.unlocks.Refresh) -- Freischaltungs-Karte: eigener Takt fehlt dort
		end
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
