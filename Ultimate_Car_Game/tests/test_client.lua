-- Client: Oberfläche aufbauen, alle Bereiche rendern, Tasten bedienen, Klick-Pooling, Touch-Größen
local function clientEnv(H, snapshotHook)
	local env = H.Env()
	local S = H.Shared(env)
	-- Remotes wie vom Server angelegt
	local folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, n in ipairs({ "Action", "Sync", "Notice" }) do
		local r = Instance.new("RemoteEvent")
		r.Name = n
		r.Parent = folder
	end
	folder.Parent = env.services.ReplicatedStorage
	local player = H.Mock.NewPlayer(env, 900, "Tester")
	env.services.Players.__data.LocalPlayer = player
	local sps = env.services.StarterPlayer.StarterPlayerScripts
	H.Mock.RunScript(env, sps.Main)
	return env, S, player, folder
end

local function richProfile(S, now)
	local p = S.Rules.LoadData(nil)
	p.credits = 50000
	p.level = 12
	p.games.press.scrap = 123456
	p.games.press.runScrap = 2e6
	p.games.press.upgrades = { pu0 = 3, pu1 = 2, pu7 = 1 }
	p.games.tuningLevel = 6
	p.games.tuning.lastIdle = now - 1800
	p.games.tuning.projects = { { slot = 1, id = "folie", startedAt = now - 100, duration = 300 } }
	p.games.jobs = { { id = 90, name = "Ölwechsel", reward = 150, xp = 16, parts = 1, cost = 40, time = 18, startedAt = now - 5, endsAt = now + 13 } }
	p.games.scrapyard.vehicle = true
	p.games.quiz.current = { index = 2, order = { 3, 1, 4, 2 }, token = 7 }
	p.games.parking.puzzle = { cars = { 0, 1, 2, 3, 5, 9, 12 }, target = 0, exit = 15, moves = 1, solved = false, crashed = false }
	S.GoalRules.EnsureDay(p, now)
	S.WorkshopRules.RefreshOffers(p, Random.new(5))
	return p
end

local function findButton(root, text)
	for _, d in ipairs(root:GetDescendants()) do
		if d.ClassName == "TextButton" and d.Text == text then
			return d
		end
	end
	return nil
end

local function actionsSent(folder)
	return folder.Action.__data.sentToServer or {}
end

return {
	{ "Oberfläche baut und rendert alle Bereiche fehlerfrei", function(T, H)
		local env, S, player, folder = clientEnv(H)
		T.eq(#H.Errors(env), 0, "Start ohne Fehler: " .. table.concat(H.Errors(env), " | "))
		local gui = player.PlayerGui:FindFirstChild("UltimateCarGame")
		T.check(gui ~= nil, "ScreenGui angelegt")
		T.eq(gui.ResetOnSpawn, false, "überlebt Respawn")
		local now = env.clock.now
		local snap = S.Snapshot.Build(richProfile(S, now), now, { doubleScrap = true })
		folder.Sync.OnClientEvent:Fire(snap)
		local sent = actionsSent(folder)
		T.eq(sent[1] and sent[1][1], "ui_ready", "meldet sich beim Server")
		-- jeden Bereich öffnen und rendern
		local UI = require(env.services.StarterPlayer.StarterPlayerScripts.Client.UI)
		for _, tab in ipairs(UI.Tabs) do
			UI.Open(tab.key)
			folder.Sync.OnClientEvent:Fire(snap)
			env.services.RunService.Heartbeat:Fire(0.1)
			T.eq(UI.CurrentTab, tab.key, "Bereich geöffnet: " .. tab.key)
		end
		T.eq(#H.Errors(env), 0, "Rendern ohne Fehler: " .. table.concat(H.Errors(env), " | "))
		-- Hinweise
		for _, n in ipairs({
			{ "toast", { text = "Hallo" } },
			{ "open", { tab = "press" } },
			{ "offline", { text = "Während du weg warst: +5", scrap = 5 } },
			{ "levelup", { level = 5, credits = 200 } },
			{ "rebirth", { multiplier = 1.1 } },
			{ "quiz", { correct = true, correctPos = 2, choice = 2, credits = 90 } },
			{ "scrapyard", { parts = 5, rare = true, credits = 20, scrap = 40 } },
			{ "leaderboard", { available = true, rows = { { rank = 1, name = "A", value = 5, self = true } }, own = { rank = 1, value = 5 } } },
			{ "leaderboard", { available = false } },
			{ "leaderboard", { available = true, rows = {}, own = { atLeast = 501, value = 1 } } },
			{ "unbekannt", "kaputt" },
		}) do
			folder.Notice.OnClientEvent:Fire(n[1], n[2])
		end
		T.eq(UI.CurrentTab, "press", "Station öffnet den richtigen Bereich")
		T.eq(#H.Errors(env), 0, "Hinweise ohne Fehler: " .. table.concat(H.Errors(env), " | "))
		folder.Sync.OnClientEvent:Fire("kaputt")
		T.eq(#H.Errors(env), 0, "kaputter Snapshot ignoriert")
		-- Schließen/Öffnen wechselt sauber
		UI.Close()
		T.eq(UI.Panel.Visible, false, "geschlossen")
		T.eq(UI.MenuButton.Visible, true, "Menü-Knopf sichtbar")
		UI.Open("quiz")
		UI.Show("parking")
		T.eq(UI.Pages.quiz.Visible, false, "nur ein Bereich sichtbar")
		T.eq(UI.Pages.parking.Visible, true, "Parkplatz sichtbar")
	end },

	{ "Tasten senden Absichten (ohne Beträge)", function(T, H)
		local env, S, player, folder = clientEnv(H)
		local now = env.clock.now
		local prof = richProfile(S, now)
		local snap = S.Snapshot.Build(prof, now, {})
		local UI = require(env.services.StarterPlayer.StarterPlayerScripts.Client.UI)
		UI.Open("press")
		folder.Sync.OnClientEvent:Fire(snap)
		local gui = player.PlayerGui.UltimateCarGame
		local buy = findButton(gui, H.Mock and require(env.services.ReplicatedStorage.Shared.Locale).Number(S.PressRules.UpgradeCost(S.Catalog.PressUpgrades[1], 3)) .. " Schrott")
		T.check(buy ~= nil, "Upgrade-Knopf gefunden")
		if buy then
			buy.Activated:Fire()
			buy.Activated:Fire() -- Doppeltipp innerhalb 0,3 s
		end
		local sent = actionsSent(folder)
		local buys = {}
		for _, a in ipairs(sent) do
			if a[1] == "press_buy" then
				table.insert(buys, a[2])
			end
		end
		T.eq(#buys, 1, "Doppeltipp sendet eine Absicht")
		T.eq(buys[1] and buys[1].id, "pu0", "Upgrade-ID")
		T.eq(buys[1] and buys[1].level, 3, "gesehene Stufe")
		T.eq(buys[1] and buys[1].cost, nil, "kein Preis gesendet")
		T.check(buys[1] and type(buys[1].rid) == "number", "Anfrage-ID")
		-- Rebirth fragt nach
		local rb = findButton(gui, "Rebirth durchführen")
		rb.Activated:Fire()
		T.eq(UI.Shade.Visible, true, "Bestätigungsdialog")
		UI.ConfirmYes.Activated:Fire()
		local rebirths = 0
		for _, a in ipairs(actionsSent(folder)) do
			if a[1] == "press_rebirth" then
				rebirths += 1
				T.eq(a[2].rebirths, 0, "gesehene Rebirth-Zahl")
			end
		end
		T.eq(rebirths, 1, "Rebirth erst nach Bestätigung gesendet")
		-- Quiz-Antwort
		UI.Show("quiz")
		folder.Sync.OnClientEvent:Fire(snap)
		local view = S.SideGameRules.QuestionView(prof)
		local answerButton = findButton(gui, view.answers[2])
		answerButton.Activated:Fire()
		local answers = {}
		for _, a in ipairs(actionsSent(folder)) do
			if a[1] == "quiz_answer" then
				table.insert(answers, a[2])
			end
		end
		T.eq(#answers, 1, "Antwort gesendet")
		T.eq(answers[1].token, 7, "Token")
		T.eq(answers[1].choice, 2, "Position")
		T.eq(#H.Errors(env), 0, "keine Fehler: " .. table.concat(H.Errors(env), " | "))
	end },

	{ "Klicks werden gebündelt, Effekte gepoolt (10.000 Klicks)", function(T, H)
		local env, S, player, folder = clientEnv(H)
		local now = env.clock.now
		local snap = S.Snapshot.Build(richProfile(S, now), now, {})
		local UI = require(env.services.StarterPlayer.StarterPlayerScripts.Client.UI)
		UI.Open("press")
		folder.Sync.OnClientEvent:Fire(snap)
		local area = player.PlayerGui.UltimateCarGame:GetDescendants()
		local press
		for _, d in ipairs(area) do
			if d.Name == "Presse" then
				press = d
			end
		end
		T.check(press ~= nil, "Klickfläche gefunden")
		local input = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(10, 10, 0) }
		local before = env.instanceCount
		for i = 1, 10000 do
			press.InputBegan:Fire(input)
			if i % 20 == 0 then
				env.clock:Advance(0.1)
			end
		end
		env.clock:Advance(1)
		local grown = env.instanceCount - before
		T.check(grown < 50, "keine Instanzflut bei 10.000 Klicks (" .. grown .. " neue Instanzen)")
		local batches, total = 0, 0
		for _, a in ipairs(actionsSent(folder)) do
			if a[1] == "press_click" then
				batches += 1
				total += a[2].count
				T.eq(a[2].scrap, nil, "kein Betrag im Klickpaket")
			end
		end
		T.check(batches > 0 and batches <= 110, "Klicks gebündelt (" .. batches .. " Pakete)")
		T.check(total <= 20 * 51 + 20, "Client zählt höchstens 20 Klicks/s (" .. total .. ")")
		T.eq(#H.Errors(env), 0, "keine Fehler")
	end },

	{ "Touch-Flächen mindestens 44 px, keine externen Assets", function(T, H)
		local env, S, player = clientEnv(H)
		local gui = player.PlayerGui.UltimateCarGame
		local small = 0
		for _, d in ipairs(gui:GetDescendants()) do
			if d.ClassName == "TextButton" and d.Size and d.Size.Y and d.Size.Y.Scale == 0 then
				if d.Size.Y.Offset < 44 then
					small += 1
				end
			end
		end
		T.eq(small, 0, "alle Knöpfe ≥ 44 px hoch")
		-- keine externen Asset-IDs in der Welt
		local srv = H.Server()
		local bad = 0
		for _, d in ipairs(srv.env.workspace:GetDescendants()) do
			for k, v in pairs(d.__data) do
				if type(v) == "string" and v:find("rbxassetid://", 1, true) then
					bad += 1
				end
			end
		end
		T.eq(bad, 0, "keine externen Asset-IDs")
		T.check(srv.env.workspace.Hof ~= nil, "Hof gebaut")
		T.check(srv.env.workspace.Hof:FindFirstChild("Start") ~= nil, "Spawn vorhanden")
		T.eq(#srv.World.BoardRows, srv.S.Config.LeaderboardBoardRows, "Tafel-Zeilen")
	end },
}
