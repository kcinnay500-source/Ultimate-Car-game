-- Client: echter GarageClient (2.4.0) + Minispiele (StarterPlayerScripts.Mini) gegen den echten Server.
-- Oberfläche, Einstiege (Taste M, HUD, Tablet), alle Bereiche mit echten Snapshots, Absichten ohne Beträge,
-- Klick-Bündelung, gegenseitiger Ausschluss mit Tablet/QTE, Layout auf dem Handy, Stadt-Animationen.
local FORBIDDEN = { amount = true, price = true, cost = true, credits = true, scrap = true, reward = true, time = true, now = true, timestamp = true, gain = true }

local function start(H, opts)
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p)
	g:Advance(1.5)
	return g, p
end

local function mods(g, p)
	return g:ClientModule(p, "Mini.MiniClient"), g:ClientModule(p, "Mini.MiniUI")
end

local function findButton(root, text, prefix)
	for _, x in ipairs(root:GetDescendants()) do
		if x.ClassName == "TextButton" and x:GetAttribute("disabled") ~= true then
			local t = tostring(x.Text)
			if t == text or (prefix and t:sub(1, #text) == text) then
				return x
			end
		end
	end
	return nil
end

-- Klick mit Abstand zur 0,3-s-Entprellung der Minispiel-Knöpfe
local function press(g, button)
	g:Advance(0.35)
	local ok = g:Click(button)
	g:Advance(0.1)
	return ok
end

local function sentFrom(g, index)
	local list = g:Remote("Command").__data.sentToServer or {}
	local out = {}
	for i = (index or 0) + 1, #list do
		table.insert(out, list[i])
	end
	return out, #list
end

local function sentCount(g)
	return #(g:Remote("Command").__data.sentToServer or {})
end

local function lastAction(g, since, name)
	local found
	for _, a in ipairs((sentFrom(g, since))) do
		if a[1] == name then
			found = a[2]
		end
	end
	return found
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
	T.eq(#g:Warnings(), 0, (what or "keine Warnungen") .. ": " .. table.concat(g:Warnings(), " | "))
end

local function open(g, p, tab)
	local MiniClient = g:ClientModule(p, "Mini.MiniClient")
	local ok = g:InClient(p, function()
		return MiniClient.Open(tab)
	end)
	g:Advance(0.6)
	return ok
end

return {
	{ "Oberfläche: Aufbau, Einstiege (M, HUD, Tablet), alle Bereiche mit echtem Snapshot", function(T, H)
		local g, p = start(H)
		noErrors(T, g, "Client-Start")
		local MiniClient, MiniUI = mods(g, p)
		local gui = p.PlayerGui:FindFirstChild("Minispiele")
		T.check(gui ~= nil, "ScreenGui Minispiele")
		T.eq(gui and gui.DisplayOrder, 30, "DisplayOrder 30")
		T.eq(gui and gui.ResetOnSpawn, false, "überlebt Respawn")
		local snap = g:InClient(p, function()
			return MiniClient.Snapshot()
		end)
		T.check(type(snap) == "table" and snap.press ~= nil, "erster Snapshot vom Server angekommen")
		-- Tablet ist beim Start offen; Taste M öffnet die Minispiele und schließt das Tablet
		T.check(g:FindGui(p, "/ ULTIMATE CAR GAME") ~= nil, "Tablet anfangs offen")
		T.eq(g:Key(p, Enum.KeyCode.M), true, "Taste M wird geschluckt")
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, true, "Taste M öffnet die Minispiele")
		T.check(g:FindGui(p, "/ ULTIMATE CAR GAME") == nil, "Tablet geschlossen")
		T.check(g:FindGui(p, "Menü [Tab]") == nil, "2.4.0-HUD ausgeblendet")
		T.eq(g.env.services.GuiService.TouchControlsEnabled, false, "Touch-Steuerung aus bei offenem Panel")
		-- alle Bereiche mit dem echten Snapshot rendern
		for _, tab in ipairs(MiniUI.Tabs) do
			g:InClient(p, function()
				MiniUI.Show(tab.key)
			end)
			g:Advance(0.6)
			T.eq(MiniUI.CurrentTab, tab.key, "Bereich " .. tab.key)
			T.check(MiniUI.Pages[tab.key].Visible, "Seite " .. tab.key .. " sichtbar")
		end
		noErrors(T, g, "alle Bereiche")
		-- Touch-Flächen ≥ 44 px (Knöpfe im Raster haben feste Zellen von 64 px)
		local small = {}
		for _, x in ipairs(gui:GetDescendants()) do
			if x.ClassName == "TextButton" then
				local inGrid = x.Parent and x.Parent:FindFirstChildOfClass("UIGridLayout") ~= nil
				if not inGrid and x.Size.Y.Scale == 0 and x.Size.Y.Offset < 44 then
					table.insert(small, x.Name .. ":" .. tostring(x.Text))
				end
			end
		end
		T.eq(#small, 0, "alle Knöpfe ≥ 44 px: " .. table.concat(small, ", "))
		-- M schließt, HUD kommt zurück
		g:Key(p, Enum.KeyCode.M)
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, false, "Taste M schließt")
		T.check(g:FindGui(p, "Menü [Tab]") ~= nil, "HUD wieder sichtbar")
		T.eq(g.env.services.GuiService.TouchControlsEnabled, true, "Touch-Steuerung wieder an")
		-- HUD-Knopf und Tablet-Knopf öffnen ebenfalls
		local hudButton = g:FindGui(p, "Minispiele [M]", { class = "TextButton" })
		T.check(hudButton ~= nil, "HUD-Knopf 'Minispiele [M]'")
		g:Click(hudButton)
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, true, "HUD-Knopf öffnet")
		g:Key(p, Enum.KeyCode.M)
		g:Advance(0.3)
		g:Key(p, Enum.KeyCode.Tab)
		g:Advance(0.3)
		local nav = g:FindGui(p, function(x)
			return x.Name == "Nav_minigames"
		end)
		T.check(nav ~= nil, "Tablet-Knopf 'Minispiele'")
		g:Click(nav)
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, true, "Tablet-Knopf öffnet")
		T.check(g:FindGui(p, "/ ULTIMATE CAR GAME") == nil, "Tablet dabei geschlossen")
		noErrors(T, g)
	end },

	{ "Knöpfe senden Absichten ohne Beträge; der Server wertet aus", function(T, H)
		local g, p = start(H)
		local MiniNet = g:MiniShared("MiniNet")
		local PR = g:MiniShared("PressRules")
		local _, MiniUI = mods(g, p)
		local d = g:D(p)
		d.money = 200000
		d.games.press.upgrades = {}
		d.games.press.scrap = 5e6
		d.games.press.runScrap = PR.RebirthThreshold(d) + 1
		d.games.tuningLevel = 12
		d.games.tuning.lastIdle = g:Now() - 1800
		d.games.daily.active = true
		g:Advance(1.6)
		local start0 = sentCount(g)
		-- Presse: Upgrade kaufen (Doppeltipp innerhalb der Entprellung = eine Absicht)
		open(g, p, "press")
		local page = MiniUI.Pages.press
		local buy
		for _, x in ipairs(page:GetDescendants()) do
			if x.ClassName == "TextButton" and tostring(x.Text):find("Schrott$") and x:GetAttribute("disabled") ~= true then
				buy = x
				break
			end
		end
		if T.check(buy ~= nil, "Upgrade-Knopf") then
			local n = sentCount(g)
			g:Advance(0.35)
			g:Click(buy)
			g:Click(buy)
			g:Advance(0.2)
			local buys = 0
			local payload
			for _, a in ipairs((sentFrom(g, n))) do
				if a[1] == "mini_press_buy" then
					buys += 1
					payload = a[2]
				end
			end
			T.eq(buys, 1, "Doppeltipp sendet eine Absicht")
			T.check(payload and type(payload.id) == "string" and payload.level == 0 and type(payload.rid) == "number", "id, gesehene Stufe, rid")
			T.eq(payload and payload.cost, nil, "kein Preis gesendet")
			T.eq(payload and d.games.press.upgrades[payload.id], 1, "Server hat gekauft")
		end
		-- Rebirth erst nach Bestätigung
		g:Advance(1.6)
		local rb = findButton(page, "Rebirth durchführen")
		if T.check(rb ~= nil, "Rebirth-Knopf aktiv") then
			local n = sentCount(g)
			press(g, rb)
			T.eq(lastAction(g, n, "mini_press_rebirth"), nil, "noch nicht gesendet")
			T.eq(MiniUI.Shade.Visible, true, "Bestätigungsdialog")
			press(g, MiniUI.ConfirmYes)
			local a = lastAction(g, n, "mini_press_rebirth")
			T.eq(a and a.rebirths, 0, "gesehene Rebirth-Zahl")
			T.eq(d.games.press.rebirths, 1, "Server: Rebirth durchgeführt")
		end
		-- Umtausch
		d.games.press.scrap = 5e6
		g:Advance(1.6) -- nächster Snapshot kommt spätestens nach 1 s + einem Tick
		local ex
		for _, x in ipairs(page:GetDescendants()) do
			if x.ClassName == "TextButton" and tostring(x.Text):find("→") and x:GetAttribute("disabled") ~= true then
				ex = x
				break
			end
		end
		if T.check(ex ~= nil, "Umtausch-Knopf") then
			local money = d.money
			local n = sentCount(g)
			press(g, ex)
			T.check(type(lastAction(g, n, "mini_press_exchange").index) == "number", "Umtausch nach Paketnummer")
			T.check(d.money > money, "Server: Credits gutgeschrieben")
		end
		-- Tuning: passive Einnahmen und Projekt starten
		open(g, p, "tuning")
		local tpage = MiniUI.Pages.tuning
		local money = d.money
		local idle = findButton(tpage, "Einnahmen abholen", true)
		if T.check(idle ~= nil, "Einnahmen-Knopf") then
			press(g, idle)
			T.check(d.money > money, "Server: passive Einnahmen")
		end
		local startBtn = findButton(tpage, "Starten", true)
		if T.check(startBtn ~= nil, "Start-Knopf") then
			press(g, startBtn)
			T.eq(#d.games.tuning.projects, 1, "Server: Projekt läuft")
		end
		-- Schrottplatz
		open(g, p, "scrapyard")
		local spage = MiniUI.Pages.scrapyard
		press(g, findButton(spage, "Fahrzeug kaufen", true))
		T.eq(d.games.scrapyard.vehicle, true, "Server: Fahrzeug gekauft")
		g:Advance(0.6)
		-- Vorbereitungszeit: Knopf zählt herunter und ist gesperrt, danach zerlegen
		T.eq(findButton(spage, "Fahrzeug zerlegen"), nil, "Zerlegen während der Vorbereitung gesperrt")
		T.check(findButton(spage, "Wird vorbereitet", true) == nil, "Countdown-Knopf ist nicht anklickbar")
		local countdown
		for _, x in ipairs(spage:GetDescendants()) do
			if x.ClassName == "TextButton" and tostring(x.Text):find("Wird vorbereitet", 1, true) then
				countdown = x
			end
		end
		T.check(countdown ~= nil, "Countdown sichtbar")
		g:Advance(g:MiniShared("MiniConfig").ScrapyardDismantleSeconds)
		press(g, findButton(spage, "Fahrzeug zerlegen"))
		T.eq(d.games.scrapyard.vehicle, false, "Server: zerlegt")
		g:Advance(0.6)
		-- Quiz: neue Frage, Antwort anklicken
		open(g, p, "quiz")
		local qpage = MiniUI.Pages.quiz
		press(g, findButton(qpage, "Neue Frage"))
		g:Advance(0.6)
		local ms = g:MiniState(p)
		local q = ms.quiz.current
		if T.check(q ~= false and q ~= nil, "Server: Frage gestellt") then
			local Bank = g:MiniServer("QuizBank")
			local text = Bank.Questions[q.index].a[q.order[2]]
			T.eq(g:MiniShared("MiniCatalog").Questions, nil, "kein Antwortschlüssel in ReplicatedStorage")
			local n = sentCount(g)
			press(g, findButton(qpage, text))
			local a = lastAction(g, n, "mini_quiz_answer")
			T.eq(a and a.choice, 2, "angezeigte Position")
			T.eq(a and a.token, q.token, "Token der Frage")
			T.eq(#g:Notices(p, "quiz"), 1, "Server hat ausgewertet")
		end
		-- Parkplatz: neue Runde, Feld antippen
		open(g, p, "parking")
		local ppage = MiniUI.Pages.parking
		press(g, findButton(ppage, "Neue Runde", true))
		g:Advance(0.6)
		local pz = d.games.parking.puzzle
		if T.check(pz, "Server: Rätsel") then
			local cell = ppage:FindFirstChild("Cell" .. pz.cars[2], true)
			press(g, cell)
			T.eq(pz.moves, 1, "Server: Zug gezählt")
		end
		-- Ziele: Tagesauftrag
		open(g, p, "goals")
		local daily = findButton(MiniUI.Pages.goals, "Tagesauftrag abholen", true)
		if T.check(daily ~= nil, "Tagesauftrag-Knopf") then
			press(g, daily)
			T.eq(d.games.daily.claimed, true, "Server: Tagesauftrag abgeholt")
		end
		-- Alle gesendeten Absichten: bekannt, flach, ohne Beträge
		local count = 0
		for _, a in ipairs((sentFrom(g, start0))) do
			if type(a[1]) == "string" and a[1]:sub(1, 5) == "mini_" then
				count += 1
				T.check(MiniNet.IsAction(a[1]), "bekannte Aktion " .. a[1])
				local keys = 0
				for k, v in pairs(a[2] or {}) do
					keys += 1
					T.check(not FORBIDDEN[k], a[1] .. ": kein Feld " .. k)
					T.check(type(v) ~= "table", a[1] .. ": flache Nutzlast")
				end
				T.check(keys <= 10, a[1] .. ": höchstens 10 Schlüssel")
			end
		end
		T.check(count >= 10, "Absichten gesendet (" .. count .. ")")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Klicks werden gebündelt, höchstens 20/s, Effekte gepoolt (10.000 Klicks)", function(T, H)
		local g, p = start(H)
		local _, MiniUI = mods(g, p)
		open(g, p, "press")
		local area = MiniUI.Pages.press:FindFirstChild("Presse", true)
		if not T.check(area ~= nil, "Klickfläche") then
			return
		end
		local n0 = sentCount(g)
		local clicks0 = g:D(p).games.press.clicks
		local before = g.env.instanceCount
		local input = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(10, 10, 0) }
		for i = 1, 10000 do
			area.InputBegan:Fire(input)
			if i % 20 == 0 then
				g:Advance(0.1)
			end
		end
		g:Advance(1)
		local grown = g.env.instanceCount - before
		T.check(grown < 50, "keine Instanzflut bei 10.000 Klicks (" .. grown .. " neue Instanzen)")
		-- Klickpakete tragen eine rid (Bestätigung/Wiederholung, PressUI); Wiederholungen derselben rid zählen einmal
		local batches, total, rids = 0, 0, {}
		for _, a in ipairs((sentFrom(g, n0))) do
			if a[1] == "mini_press_click" then
				T.check(type(a[2].rid) == "number", "Klickpaket mit rid")
				T.eq(a[2].scrap, nil, "kein Betrag im Klickpaket")
				if not rids[a[2].rid] then
					rids[a[2].rid] = a[2].count
					batches += 1
					total += a[2].count
				else
					T.eq(a[2].count, rids[a[2].rid], "Wiederholung mit gleicher Anzahl")
				end
			end
		end
		T.check(batches > 0 and batches <= 110, "Klicks gebündelt (" .. batches .. " Pakete)")
		T.check(total <= 20 * 51 + 20, "Client zählt höchstens 20 Klicks/s (" .. total .. ")")
		local accepted = g:D(p).games.press.clicks - clicks0
		T.check(accepted > 0 and accepted <= total, "Server hat Klicks angenommen (" .. accepted .. ")")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Gegenseitiger Ausschluss: Tablet, QTE und Diagnose; Stationen öffnen Bereiche; Toast-Spiegel", function(T, H)
		local g, p = start(H)
		local MiniClient, MiniUI = mods(g, p)
		open(g, p, "overview")
		T.eq(MiniUI.IsOpen, true, "offen")
		-- Tab öffnet das Tablet, das Panel weicht
		g:Key(p, Enum.KeyCode.Tab)
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, false, "Tablet öffnen schließt die Minispiele")
		T.check(g:FindGui(p, "/ ULTIMATE CAR GAME") ~= nil, "Tablet offen")
		-- mini_open vom Server (Station) öffnet den Bereich und schließt das Tablet
		g:FireClient(p, "mini_open", { tab = "tuning" })
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, true, "mini_open öffnet")
		T.eq(MiniUI.CurrentTab, "tuning", "richtiger Bereich")
		-- Server-Toast bei offenem Panel wird gespiegelt
		g:FireClient(p, "toast", "Nicht genug Credits.")
		g:Advance(0.1)
		T.eq(MiniUI.ToastPanel.Visible, true, "Toast-Spiegel sichtbar")
		T.eq(MiniUI.ToastLabel.Text, "Nicht genug Credits.", "gleicher Text")
		g:Advance(5)
		T.eq(MiniUI.ToastPanel.Visible, false, "Toast-Spiegel verschwindet")
		-- QTE (challenge) sperrt und schließt
		g:FireClient(p, "challenge", { token = "t1", kind = "gauge", startAt = g:Now() + 0.7, period = 1.5, center = 0.62, width = 0.3, expires = g:Now() + 12 })
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, false, "QTE schließt die Minispiele")
		T.eq(g:InClient(p, function()
			return MiniClient.Open("press")
		end), false, "während QTE gesperrt")
		g:Key(p, Enum.KeyCode.M)
		g:Advance(0.2)
		T.eq(MiniUI.IsOpen, false, "Taste M während QTE wirkungslos")
		g:FireClient(p, "interactionReset", { token = "t1" })
		g:Advance(0.5)
		T.eq(g:InClient(p, function()
			return MiniClient.Open("press")
		end), true, "nach dem QTE wieder offen")
		-- Diagnose-Dialog schließt das Panel
		g:FireClient(p, "diagnose", { job = "job_1", car = "Test", report = "Test", answers = { "A" }, phase = "diagnose" })
		g:Advance(0.3)
		T.eq(MiniUI.IsOpen, false, "Diagnose schließt die Minispiele")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Hinweise vom Server: Offline, Rebirth, Quiz, Schrottplatz, Bestenliste", function(T, H)
		local g, p = start(H)
		local _, MiniUI = mods(g, p)
		open(g, p, "leaderboard")
		for _, n in ipairs({
			{ kind = "offline", text = "Während du weg warst: +5 kg Schrott", scrap = 5, seconds = 60 },
			{ kind = "rebirth", multiplier = 1.2 },
			{ kind = "quiz", correct = true, correctPos = 2, choice = 2, credits = 90 },
			{ kind = "scrapyard", parts = 5, rare = true, rarePart = "Nexra Reifen (Kompakt)", rareSku = "nexra_C_tire", credits = 20, scrap = 40 },
			{ kind = "leaderboard", available = true, rows = { { rank = 1, name = "A", value = 5, self = true } }, own = { rank = 1, value = 5 } },
			{ kind = "leaderboard", available = false },
			{ kind = "leaderboard", available = "loading" },
			{ kind = "leaderboard", available = true, rows = {}, own = { atLeast = 501, value = 1 } },
			{ kind = "unbekannt" },
		}) do
			g:FireClient(p, "mini_notice", n)
			g:Advance(0.1)
		end
		g:FireClient(p, "mini_notice", "kaputt")
		g:FireClient(p, "mini", "kaputt")
		g:Advance(0.3)
		T.check(MiniUI.ToastLabel.Text:find("Rebirth") ~= nil, "Rebirth-Hinweis gespiegelt: " .. MiniUI.ToastLabel.Text)
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
		T.eq(#g:Warnings(), 0, "keine Warnungen: " .. table.concat(g:Warnings(), " | "))
	end },

	{ "Offline-Ertrag erscheint nach dem Start als Hinweis beim Spieler", function(T, H)
		local g = H.Garage({ before = function(g)
			local R = g:Rules()
			local d = R.NewData(g:Now())
			d.games.press.upgrades = { pu1 = 10 }
			d.games.press.lastTick = g:Now() - 3600
			g:Seed(1001, { version = 2, data = d, receipts = {} })
		end })
		local p = g:Join(1001, { name = "Tester" })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(1.5)
		T.eq(#g:Notices(p, "offline"), 1, "Server hat den Hinweis nach hello gesendet")
		T.check(g:FindGui(p, "Während du weg warst") ~= nil, "Hinweis im 2.4.0-Toast sichtbar")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Handy quer (844×390) kompakt, hoch (390×844) normal; HUD-Knopf passt", function(T, H)
		local g, p = start(H, { viewport = Vector2.new(844, 390) })
		local _, MiniUI = mods(g, p)
		open(g, p, "press")
		T.eq(MiniUI.Compact, true, "Kompakt-Modus bei 844×390")
		T.eq(MiniUI.Header.Visible, false, "Tabs in der Kopfzeile")
		T.eq(MiniUI.Panel.Active, true, "Panel schluckt Eingaben")
		T.eq(MiniUI.Shade.Active, true, "Dialog schluckt Eingaben")
		H.Mock.SetViewport(g.env, Vector2.new(390, 844))
		MiniUI.Gui:GetPropertyChangedSignal("AbsoluteSize"):Fire()
		g:Advance(0.3)
		T.eq(MiniUI.Compact, false, "Hochformat: normales Layout")
		g:InClient(p, function()
			MiniUI.Close()
		end)
		g:Advance(0.3)
		local mini = g:FindGui(p, function(x)
			return x.Name == "MiniGames"
		end)
		if T.check(mini ~= nil, "HUD-Knopf") then
			local right = mini.Position.X.Offset + mini.Size.X.Offset
			T.check(right <= 390 * 0.96, "HUD-Knopf passt bei 390 px (rechts " .. right .. ")")
			T.check(mini.Size.X.Offset >= 70, "HUD-Knopf breit genug (" .. mini.Size.X.Offset .. ")")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Schnellreise und Stadt-Animationen", function(T, H)
		local g, p = start(H, { before = function(g)
			local city = g:BuildCity({ arrivals = { { key = "press", pos = Vector3.new(50, 0.5, -320) }, { key = "dealer", pos = Vector3.new(100, 0.5, -320) } } })
			city.Arrivals.dealer:SetAttribute("DisplayName", "Autohaus Nord")
			local animated = Instance.new("Folder")
			animated.Name = "Animated"
			animated.Parent = city
			local function part(name, parent, pos, props)
				local x = Instance.new("Part")
				x.Name = name
				x.Anchored = true
				x.Size = Vector3.new(4, 4, 4)
				x.CFrame = CFrame.new(pos)
				for k, v in pairs(props or {}) do
					x[k] = v
				end
				x.Parent = parent
				return x
			end
			local pressModel = Instance.new("Model")
			pressModel.Name = "Presse"
			pressModel:SetAttribute("Anim", "press")
			part("Ram", pressModel, Vector3.new(10, 8, -330))
			pressModel.Parent = animated
			part("Kran", animated, Vector3.new(30, 10, -330)):SetAttribute("Anim", "crane")
			part("Tor", animated, Vector3.new(60, 4, -330)):SetAttribute("Anim", "door")
			part("Drehteller", animated, Vector3.new(80, 0.5, -330)):SetAttribute("Anim", "turntable")
			part("Schild", animated, Vector3.new(5, 5, -330), { Material = Enum.Material.Neon }):SetAttribute("Anim", "neon")
			for i = 1, 10 do
				local car = part("Auto" .. i, animated, Vector3.new(0, 1, -300 + i * 2))
				car:SetAttribute("Anim", "traffic")
				car:SetAttribute("WP1", Vector3.new(0, 0, -300))
				car:SetAttribute("WP2", Vector3.new(0, 0, -100))
				car:SetAttribute("Phase", i / 10)
			end
		end })
		local _, MiniUI = mods(g, p)
		local City = g:ClientModule(p, "Mini.CityClient")
		local counts = g:InClient(p, function()
			return City.Counts()
		end)
		T.eq(counts.press, 1, "Presse erkannt")
		T.eq(counts.traffic, 10, "Verkehr erkannt")
		local ram = g:Find("Workspace.City.Animated.Presse.Ram")
		local crane = g:Find("Workspace.City.Animated.Kran")
		local car = g:Find("Workspace.City.Animated.Auto1")
		local c0, k0, a0 = ram.CFrame, crane.CFrame, car.Position
		-- Animationen laufen nur bis 300 Studs von der Kamera (CITY_SPEC); Kamera zur Szene
		g.env.workspace.CurrentCamera.CFrame = CFrame.new(30, 20, -290)
		g:Advance(3)
		T.check((ram.CFrame.Position - c0.Position).Magnitude > 0.01 or ram.CFrame ~= c0, "Presse bewegt")
		T.check(crane.CFrame ~= k0, "Kran bewegt")
		T.check((car.Position - a0).Magnitude > 1, "Verkehr fährt")
		T.eq(car.CanCollide, false, "Verkehr lokal ohne Kollision")
		-- Schnellreise
		open(g, p, "map")
		local names = {}
		for _, x in ipairs(MiniUI.Pages.map:GetDescendants()) do
			if x.ClassName == "TextLabel" then
				names[x.Text] = true
			end
		end
		T.check(names["Eigene Werkstatt"], "Karte: eigene Werkstatt")
		T.check(names["Autohaus Nord"], "Karte: Anzeigename aus Attribut")
		local rows = {}
		for _, x in ipairs(MiniUI.Pages.map:GetDescendants()) do
			if x.ClassName == "TextButton" and x.Text == "Reisen" then
				table.insert(rows, x)
			end
		end
		T.check(#rows >= 3, "Reise-Knöpfe (" .. #rows .. ")")
		local n = sentCount(g)
		press(g, rows[#rows])
		local a = lastAction(g, n, "mini_travel")
		T.check(a and type(a.key) == "string", "mini_travel gesendet")
		T.eq(MiniUI.IsOpen, false, "Panel nach Reise geschlossen")
		g:Advance(0.5)
		local arrival = a and g:Find("Workspace.City.Arrivals." .. a.key)
		if arrival then
			T.check((g:Root(p).Position - arrival.Position).Magnitude < 6, "Server hat gereist")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
	{ "Stadt-Animationen nach CITY_SPEC: Presse, Ampel, Uhr, Hebebühne, Schranke, Warnleuchte, Haltelinie, Sichtweite", function(T, H)
		local g, p = start(H, { before = function(g)
			local city = g:BuildCity({})
			local animated = Instance.new("Folder")
			animated.Name = "Animated"
			animated.Parent = city
			local function part(name, parent, pos, props)
				local x = Instance.new("Part")
				x.Name = name
				x.Anchored = true
				x.Size = Vector3.new(4, 4, 4)
				x.CFrame = CFrame.new(pos)
				for k, v in pairs(props or {}) do
					x[k] = v
				end
				x.Parent = parent
				return x
			end
			local function model(name, kind, attrs)
				local m = Instance.new("Model")
				m.Name = name
				m:SetAttribute("Anim", kind)
				for k, v in pairs(attrs or {}) do
					m:SetAttribute(k, v)
				end
				m.Parent = animated
				return m
			end
			-- Presse wie CITY_SPEC §Schrottpresse: Crosshead steht vor der Platen in GetChildren
			local press = model("Schrottpresse", "press")
			part("Bed", press, Vector3.new(0, 1.5, 0))
			part("Columns", press, Vector3.new(0, 13, 6))
			part("Crosshead", press, Vector3.new(0, 26, 0))
			part("Cylinders", press, Vector3.new(0, 21, 0))
			part("Platen", press, Vector3.new(0, 18, 0))
			press.PrimaryPart = press.Bed
			-- Worldgen-Presse: Kind-Model "Ram", Zeiten als Attribute (Periode 6 s: 1,2 runter, 0,4 halten, 2 hoch, Rest oben)
			local wp = model("WorldgenPresse", "press", { Stroke = 12.5, Period = 6, Down = 1.2, Hold = 0.4, Up = 2 })
			local ram = Instance.new("Model")
			ram.Name = "Ram"
			part("Plate", ram, Vector3.new(-30, 17, 0))
			ram.Parent = wp
			part("Querhaupt", wp, Vector3.new(-30, 26, 0))
			-- Presse ohne Pressplatte, nur "Frame"/"Rahmen": nichts darf sich bewegen
			local bad = model("Presse2", "press")
			part("Frame", bad, Vector3.new(20, 5, 0))
			part("Rahmenhead", bad, Vector3.new(20, 9, 0))
			-- Ampel (Meile)
			local sig = model("Ampel", "signal", { Serves = "Meile", Group = "K-West" })
			part("Red", sig, Vector3.new(40, 8, 0), { Material = Enum.Material.Neon })
			part("Amber", sig, Vector3.new(40, 7, 0), { Material = Enum.Material.Neon, Transparency = 0.7 })
			part("Green", sig, Vector3.new(40, 6, 0), { Material = Enum.Material.Neon, Transparency = 0.7 })
			part("PedRed", sig, Vector3.new(41, 4, 0), { Material = Enum.Material.Neon })
			part("PedGreen", sig, Vector3.new(41, 3, 0), { Material = Enum.Material.Neon, Transparency = 0.7 })
			-- Uhr: Minutenzeiger, Pivot = Uhrmitte, Grundstellung 12 Uhr
			local clock = model("Uhrturm", "clock")
			part("Minutenzeiger", clock, Vector3.new(60, 40, 0), { Size = Vector3.new(0.4, 4, 0.2) })
			part("Stundenzeiger", clock, Vector3.new(60, 40, 0.3), { Size = Vector3.new(0.5, 3, 0.2) })
			-- Hebebühne, Schranke, Hammer, Tresorrad, Zahnradkrone, Warnleuchte, Startampel, unbekannte Art
			part("Buehne", animated, Vector3.new(80, 1, 0)):SetAttribute("Anim", "lift")
			part("Schlagbaum", animated, Vector3.new(90, 3, 0)):SetAttribute("Anim", "barrier")
			part("Hammer", animated, Vector3.new(100, 3, 0)):SetAttribute("Anim", "gavel")
			part("Tresorrad", animated, Vector3.new(110, 9, 0)):SetAttribute("Anim", "vault")
			local gear = part("Zahnradkrone", animated, Vector3.new(120, 17, 0))
			gear:SetAttribute("Anim", "spin")
			gear:SetAttribute("YawPeriod", 30)
			part("Warnleuchte", animated, Vector3.new(130, 5, 0), { Material = Enum.Material.Neon }):SetAttribute("Anim", "beacon")
			local tree = model("Startampel", "startlight")
			for i = 1, 5 do
				part("L" .. i, tree, Vector3.new(140, 2 + i, 0), { Material = Enum.Material.Neon, Transparency = 0.8 })
			end
			part("Raetsel", animated, Vector3.new(150, 1, 0)):SetAttribute("Anim", "voellig_unbekannt")
			-- Worldgen-Uhr: Zeiger mit Nabe (Pivot) in Ruhestellung 10:10, Turmmitte (Hub) am Model
			local tower = model("Uhrzeiger", "clock", { Hub = Vector3.new(200, 46, 0), Faces = 1 })
			local hub = Vector3.new(200, 46, 7.76)
			local out, up = Vector3.new(0, 0, 1), Vector3.new(0, 1, 0)
			local right = up:Cross(out)
			local a = math.rad(60)
			local d = right * math.sin(a) + up * math.cos(a)
			local hand = part("Minute_S", tower, hub + d * 1.8, { Size = Vector3.new(0.34, 4.4, 0.1) })
			hand.CFrame = CFrame.fromMatrix(hub + d * 1.8, d:Cross(out), d, out)
			hand:SetAttribute("Hand", "minute")
			hand:SetAttribute("Pivot", hub)
			hand:SetAttribute("Offset", 1.8)
			-- Worldgen-Brunnen: Fontänen pulsieren, die Zahnradkrone dreht sich um Center
			local fountain = model("Zahnradbrunnen", "fountain", { Crown = "Zahnradkrone", Center = Vector3.new(220, 17, 0), YawPeriod = 30, SpinPeriod = 12, Period = 2.4 })
			part("Jet1", fountain, Vector3.new(232, 4, 0), { Size = Vector3.new(0.6, 6, 0.6) })
			local crown = Instance.new("Model")
			crown.Name = "Zahnradkrone"
			part("Zahnrad", crown, Vector3.new(220, 17, 0), { Size = Vector3.new(1.2, 8, 8) })
			part("Zahn", crown, Vector3.new(220, 21, 0), { Size = Vector3.new(1, 1.6, 1) })
			crown.Parent = fountain
			-- Verkehr auf einem Rundkurs mit Haltelinie an der Meile-Ampel
			local loop = Instance.new("Folder")
			loop.Name = "Loop_Test"
			loop:SetAttribute("Stops", "0,-40,Meile")
			loop.Parent = animated
			local pts = { Vector3.new(-40, 0, -60), Vector3.new(40, 0, -60), Vector3.new(40, 0, 60), Vector3.new(-40, 0, 60) }
			for i, v in ipairs(pts) do
				part("WP" .. i, loop, v, { Transparency = 1, Size = Vector3.new(1, 1, 1) })
			end
			local car = part("Stadtauto", animated, Vector3.new(0, 1, -60))
			car:SetAttribute("Anim", "traffic")
			car:SetAttribute("Path", "Loop_Test")
			car:SetAttribute("Speed", 40)
			car:SetAttribute("StartOffset", 0)
			-- weit entfernt (500 Studs): steht still
			part("FernerKran", animated, Vector3.new(0, 10, 500)):SetAttribute("Anim", "crane")
		end })
		g.env.workspace.CurrentCamera.CFrame = CFrame.new(60, 30, 20)
		local City = g:ClientModule(p, "Mini.CityClient")
		local A = g:Find("Workspace.City.Animated")
		local press = A.Schrottpresse
		local base = {}
		for _, c in ipairs(press:GetChildren()) do
			base[c.Name] = c.CFrame
		end
		local bad0 = { A.Presse2.Frame.CFrame, A.Presse2.Rahmenhead.CFrame }
		-- Zeitpunkt im Programm: kurz nach Beginn des Meile-Grüns
		local function toPhase(target)
			local now = g:Now()
			g:Advance(((target - now % 32) % 32) + 0.01)
		end
		toPhase(0.4)
		local lowest = math.huge
		for _ = 1, 20 do
			g:Advance(0.1)
			lowest = math.min(lowest, press.Platen.Position.Y)
		end
		T.check(lowest < 18 - 5, "Platen fährt herunter (tiefster Punkt " .. lowest .. ")")
		T.check(lowest >= 18 - 12.5 - 0.01, "höchstens 12,5 Studs Hub")
		for _, name in ipairs({ "Bed", "Columns", "Crosshead", "Cylinders" }) do
			T.check(press[name].CFrame == base[name], name .. " bleibt stehen")
		end
		-- Worldgen-Presse: in 6 s genau ein Hub, ca. 2,4 s oben in Ruhe
		local plate, head0 = A.WorldgenPresse.Ram.Plate, A.WorldgenPresse.Querhaupt.CFrame
		local restSamples, samples, low = 0, 0, math.huge
		for _ = 1, 24 do
			g:Advance(0.25)
			samples += 1
			low = math.min(low, plate.Position.Y)
			if math.abs(plate.Position.Y - 17) < 1e-3 then
				restSamples += 1
			end
		end
		T.check(low < 17 - 10, "Worldgen-Presse fährt ganz herunter (" .. low .. ")")
		T.check(restSamples >= 7 and restSamples <= 12, "Worldgen-Presse ruht oben etwa 2,4 s von 6 s (" .. restSamples .. "/" .. samples .. ")")
		T.check(A.WorldgenPresse.Querhaupt.CFrame == head0, "Querhaupt bleibt stehen")
		T.check(A.Presse2.Frame.CFrame == bad0[1] and A.Presse2.Rahmenhead.CFrame == bad0[2], "\"Frame\"/\"...head\" bewegen sich nie")
		-- Ampel: Meile grün bei 0–14 s, rot ab 16 s; Fußgänger gegenläufig
		toPhase(5)
		g:Advance(0.6)
		T.eq(A.Ampel.Green.Transparency, 0, "Meile grün")
		T.eq(A.Ampel.Red.Transparency, 0.7, "Rot aus")
		T.eq(A.Ampel.PedGreen.Transparency, 0.7, "Fußgänger rot, solange die Meile grün hat")
		local car = A.Stadtauto
		toPhase(20)
		g:Advance(0.6)
		T.eq(A.Ampel.Red.Transparency, 0, "Meile rot")
		T.eq(A.Ampel.Green.Transparency, 0.7, "Grün aus")
		T.eq(A.Ampel.PedGreen.Transparency, 0, "Fußgänger grün")
		T.eq(City.SignalState("Markt", g:Now()), "green", "Markt grün, während die Meile rot hat")
		-- Haltelinie "0,-40,Meile" liegt auf der Kante z = -60 bei x = 0: bei Rot (16–32 s) hält das Auto dort
		toPhase(17)
		g:Advance(9) -- 320 Studs Rundkurs bei 40 Studs/s: spätestens nach 8 s an der Linie
		local stopped = car.Position
		T.check((stopped - Vector3.new(0, 1, -60)).Magnitude < 2, "hält an der Haltelinie (" .. tostring(stopped) .. ")")
		g:Advance(3)
		T.check((car.Position - stopped).Magnitude < 0.01, "wartet bei Rot")
		toPhase(0.5)
		g:Advance(1)
		T.check((car.Position - stopped).Magnitude > 5, "fährt bei Grün weiter")
		-- Uhr nach Lighting.ClockTime
		local Lighting = g.env.services.Lighting
		g:Advance(0.6)
		local minute = A.Uhrturm.Minutenzeiger
		local up = minute.CFrame.UpVector
		local turns = (Lighting.ClockTime % 1)
		local expected = Vector3.new(math.sin(turns * 2 * math.pi), math.cos(turns * 2 * math.pi), 0)
		T.check((up - expected).Magnitude < 0.08, "Minutenzeiger zeigt die Minute der Tageszeit")
		-- Worldgen-Uhr: Minutenzeiger zeigt absolut die Minute (Ruhestellung 10:10 spielt keine Rolle)
		local wm = A.Uhrzeiger.Minute_S
		local dir = (wm.Position - Vector3.new(200, 46, 7.76)).Unit
		local tt = (Lighting.ClockTime % 1) * 2 * math.pi
		local want = Vector3.new(1, 0, 0) * math.sin(tt) + Vector3.new(0, 1, 0) * math.cos(tt)
		T.check((dir - want).Magnitude < 0.08, "Worldgen-Zeiger: absoluter Winkel (" .. tostring(dir) .. " statt " .. tostring(want) .. ")")
		T.near((wm.Position - Vector3.new(200, 46, 7.76)).Magnitude, 1.8, 0.01, "Worldgen-Zeiger bleibt an der Nabe")
		-- Zahnradkrone dreht sich um ihre Mitte, schrumpft und wippt nicht
		local gear, tooth = A.Zahnradbrunnen.Zahnradkrone.Zahnrad, A.Zahnradbrunnen.Zahnradkrone.Zahn
		local tooth0 = tooth.Position
		g:Advance(3)
		T.near((gear.Position - Vector3.new(220, 17, 0)).Magnitude, 0, 0.01, "Kronenmitte bleibt stehen")
		T.eq(gear.Size, Vector3.new(1.2, 8, 8), "Krone wird nicht wie ein Wasserstrahl gestaucht")
		T.check((tooth.Position - tooth0).Magnitude > 0.5, "Krone dreht sich")
		T.near((tooth.Position - Vector3.new(220, 17, 0)).Magnitude, 4, 0.01, "Zahn bleibt auf dem Kranz")
		-- Hebebühne, Schranke, Hammer, Tresorrad, Zahnradkrone bewegen sich über eine Periode
		local watch = { "Buehne", "Schlagbaum", "Hammer", "Tresorrad", "Zahnradkrone" }
		local start0 = {}
		for _, n in ipairs(watch) do
			start0[n] = A[n].CFrame
		end
		local moved = {}
		for _ = 1, 280 do
			g:Advance(0.25)
			for _, n in ipairs(watch) do
				if A[n].CFrame ~= start0[n] then
					moved[n] = true
				end
			end
		end
		for _, n in ipairs(watch) do
			T.check(moved[n], n .. " animiert")
		end
		local counts = g:InClient(p, function()
			return City.Counts()
		end)
		for _, kind in ipairs({ "press", "signal", "clock", "lift", "barrier", "gavel", "vault", "spin", "beacon", "startlight", "traffic" }) do
			T.check((counts.kinds[kind] or 0) >= 1, "Art erkannt: " .. kind)
		end
		local litSeen = {}
		for _ = 1, 40 do
			g:Advance(0.25)
			local n = 0
			for i = 1, 5 do
				if A.Startampel["L" .. i].Transparency == 0 then
					n += 1
				end
			end
			litSeen[n] = true
		end
		T.check(litSeen[0] and litSeen[3] and litSeen[5], "Startampel: Lampen gehen nacheinander an und wieder aus")
		-- Unbekannte Art: einmal gewarnt
		local warnedUnknown = false
		for _, w in ipairs(g:Warnings()) do
			if tostring(w):find("voellig_unbekannt", 1, true) then
				warnedUnknown = true
			end
		end
		T.check(warnedUnknown, "unbekannte Anim-Art wird gemeldet")
		local warnedPress = false
		for _, w in ipairs(g:Warnings()) do
			if tostring(w):find("Presse2", 1, true) then
				warnedPress = true
			end
		end
		T.check(warnedPress, "Presse ohne Pressplatte wird gemeldet")
		-- Sichtweite: 500 Studs entfernter Kran bewegt sich nicht
		T.check(A.FernerKran.CFrame == CFrame.new(0, 10, 500), "jenseits von 300 Studs keine Animation")
		T.eq(City.Cull, 300, "Sichtweite 300 Studs")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Stadt-Animationen: Sichtweite 300, Nah-/Ferntakt, Prüfstand rüttelt nur aus der Nähe", function(T, H)
		local g, p = start(H, { frameStep = 1 / 30, before = function(g)
			local city = g:BuildCity({})
			local animated = Instance.new("Folder")
			animated.Name = "Animated"
			animated.Parent = city
			local function part(name, parent, pos)
				local x = Instance.new("Part")
				x.Name = name
				x.Anchored = true
				x.Size = Vector3.new(4, 4, 4)
				x.CFrame = CFrame.new(pos)
				x.Parent = parent
				return x
			end
			part("Nah", animated, Vector3.new(0, 5, 50)):SetAttribute("Anim", "turntable")
			part("Mittel", animated, Vector3.new(0, 5, 200)):SetAttribute("Anim", "turntable")
			part("Fern", animated, Vector3.new(0, 5, 400)):SetAttribute("Anim", "turntable")
			local dyno = Instance.new("Model")
			dyno.Name = "Pruefstand"
			dyno:SetAttribute("Anim", "dyno")
			part("Rolle", dyno, Vector3.new(0, 0.5, 150))
			local carBody = Instance.new("Model")
			carBody.Name = "Auto"
			part("Karosse", carBody, Vector3.new(0, 2, 150))
			carBody.Parent = dyno
			dyno.Parent = animated
		end })
		g.env.workspace.CurrentCamera.CFrame = CFrame.new(0, 10, 0)
		local City = g:ClientModule(p, "Mini.CityClient")
		local A = g:Find("Workspace.City.Animated")
		local far0, body0 = A.Fern.CFrame, A.Pruefstand.Auto.Karosse.CFrame
		local changes = { Nah = 0, Mittel = 0 }
		local last = { Nah = A.Nah.CFrame, Mittel = A.Mittel.CFrame }
		local rollerMoved = false
		local roller0 = A.Pruefstand.Rolle.CFrame
		for _ = 1, 120 do
			g:Advance(1 / 30)
			for n in pairs(changes) do
				if A[n].CFrame ~= last[n] then
					changes[n] += 1
					last[n] = A[n].CFrame
				end
			end
			if A.Pruefstand.Rolle.CFrame ~= roller0 then
				rollerMoved = true
			end
			T.check(A.Pruefstand.Auto.Karosse.CFrame == body0, "Prüfstand-Auto rüttelt nicht aus 150 Studs")
		end
		T.check(changes.Nah > 60, "nah: jedes Frame (" .. changes.Nah .. ")")
		T.check(changes.Mittel > 5 and changes.Mittel <= 20, "150–300 Studs: nur im 0,25-s-Takt (" .. changes.Mittel .. ")")
		T.check(A.Fern.CFrame == far0, "jenseits von 300 Studs keine Animation")
		for _ = 1, 52 do -- eine volle Prüfstand-Periode (12 s) im Ferntakt
			g:Advance(0.25)
			if A.Pruefstand.Rolle.CFrame ~= roller0 then
				rollerMoved = true
			end
		end
		T.check(rollerMoved, "Rollen drehen (Ferntakt)")
		T.check(A.Pruefstand.Auto.Karosse.CFrame == body0, "aus 150 Studs kein Rütteln")
		local counts = g:InClient(p, function()
			return City.Counts()
		end)
		T.eq(counts.active, 3, "aktiv: nah, mittel, Prüfstand")
		T.eq(counts.fast, 1, "jedes Frame nur der nahe Drehteller")
		-- Kamera nah am Prüfstand: jetzt rüttelt das Auto (sobald die Rollen laufen)
		g.env.workspace.CurrentCamera.CFrame = CFrame.new(0, 10, 140)
		local shook = false
		for _ = 1, 400 do
			g:Advance(1 / 30)
			if A.Pruefstand.Auto.Karosse.CFrame ~= body0 then
				shook = true
				break
			end
		end
		T.check(shook, "aus der Nähe rüttelt das Auto")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
	{ "Schnellreise: deutsche Namen für alle Ankunftspunkte der Stadt, nie der rohe Schlüssel", function(T, H)
		local keys = { "hub", "plaza", "arcade", "quiz", "auction", "shop", "parking", "dealer", "tuning", "press", "scrap_trader", "scrapyard", "carwash", "track", "scrapyard_gate", "park", "xyz_intern" }
		local g, p = start(H, { before = function(g)
			local arrivals = {}
			for i, k in ipairs(keys) do
				table.insert(arrivals, { key = k, pos = Vector3.new(i * 10, 0.5, -320) })
			end
			g:BuildCity({ arrivals = arrivals })
		end })
		local MapUI = g:ClientModule(p, "Mini.MapUI")
		open(g, p, "map")
		local _, MiniUI = mods(g, p)
		local texts = {}
		for _, x in ipairs(MiniUI.Pages.map:GetDescendants()) do
			if x.ClassName == "TextLabel" then
				texts[x.Text] = true
			end
		end
		for _, k in ipairs(keys) do
			T.check(not texts[k], "roher Schlüssel sichtbar: " .. k)
		end
		for k, name in pairs({ hub = "Minispiel-Zentrale", carwash = "Waschanlage", park = "Stadtpark", track = "Teststrecke", scrapyard_gate = "Schrottplatz-Tor", scrap_trader = "Schrotthändler" }) do
			T.check(texts[name], "Name für " .. k .. ": " .. name)
			T.eq(MapUI.Names[k], name, "Namenstabelle " .. k)
		end
		T.check(texts[MapUI.FallbackName], "unbekannter Schlüssel: deutscher Ersatzname")
		-- Die echten Ankunftspunkte aus tools/worldgen haben alle einen Namen
		local fixture = H.Garage({ noServer = true })
		local real = fixture:Find("Workspace.City.Arrivals")
		if real then
			for _, a in ipairs(real:GetChildren()) do
				T.check(MapUI.Names[a.Name] ~= nil or type(a:GetAttribute("DisplayName")) == "string", "Stadt-Ankunft ohne deutschen Namen: " .. a.Name)
			end
		end
	end },

	{ "Spielerliste (CoreGui) ist über dem Minispiel-Panel aus", function(T, H)
		local g, p = start(H)
		local MiniClient, MiniUI = mods(g, p)
		local function listOn()
			return g:InClient(p, function()
				return game:GetService("StarterGui"):GetCoreGuiEnabled(Enum.CoreGuiType.PlayerList)
			end)
		end
		g:Key(p, Enum.KeyCode.Tab) -- Tablet zu
		g:Advance(0.6)
		T.eq(MiniUI.IsOpen, false, "Panel zu")
		T.eq(listOn(), true, "Spielerliste bei freier Sicht an")
		open(g, p, "press")
		T.eq(MiniUI.IsOpen, true, "Panel offen")
		T.eq(listOn(), false, "Spielerliste über dem Panel aus")
		g:Advance(1)
		T.eq(listOn(), false, "bleibt aus (0,25-s-Schleife schaltet sie nicht wieder an)")
		g:InClient(p, function()
			MiniClient.Close()
		end)
		g:Advance(0.6)
		T.eq(listOn(), true, "nach dem Schließen wieder an")
	end },

	{ "Presse: gesendete Klicks bleiben in der Anzeige, bis der Server sie bestätigt; Kauf-Speicherung verliert keine Klicks", function(T, H)
		local g, p = start(H)
		local MiniClient = mods(g, p)
		open(g, p, "press")
		local PressUI = g:ClientModule(p, "Mini.PressUI")
		local _, MiniUI = mods(g, p)
		local area = MiniUI.Pages.press:FindFirstChild("Presse", true)
		local d = g:D(p)
		d.games.press.upgrades = {}
		g:Advance(1.2)
		local input = { UserInputType = Enum.UserInputType.MouseButton1, Position = Vector3.new(10, 10, 0) }
		-- Snapshot vor dem Senden merken (so sieht ein Tick-Snapshot aus, der vor dem Klickpaket gebaut wurde)
		local stale = g:InClient(p, function()
			local snap = MiniClient.Snapshot()
			local copy = table.clone(snap)
			copy.press = table.clone(snap.press)
			return copy
		end)
		for _ = 1, 10 do
			area.InputBegan:Fire(input)
		end
		local before = g:InClient(p, function()
			return PressUI.PredictedGain()
		end)
		T.check(before > 0, "Vorhersage nach 10 Klicks")
		local gainAfterStale = g:InClient(p, function()
			PressUI.Flush()
			PressUI.OnSnapshot(stale) -- älterer Snapshot ohne Bestätigung
			return PressUI.PredictedGain()
		end)
		T.near(gainAfterStale, before, 1e-6, "gesendete, unbestätigte Klicks bleiben in der Vorhersage")
		g:Advance(1.5)
		local inFlight = g:InClient(p, function()
			return PressUI.InFlight()
		end)
		T.eq(inFlight, 0, "bestätigtes Paket fällt aus der Vorhersage")
		-- Robux-Kauf wird gespeichert (transacting): Klickpakete werden still verworfen und später wiederholt
		local profile = g:Profile(p)
		local clicks0 = d.games.press.clicks
		local m = g:Mark()
		profile.transacting = true
		for i = 1, 30 do
			area.InputBegan:Fire(input)
			if i % 5 == 0 then
				g:Advance(0.25)
			end
		end
		g:Advance(1)
		T.eq(d.games.press.clicks, clicks0, "während transacting keine Klicks gezählt")
		local toasts = 0
		for _, msg in ipairs(g:Toasts(p, m)) do
			if tostring(msg):find("Kauf wird sicher gespeichert", 1, true) then
				toasts += 1
			end
		end
		T.eq(toasts, 0, "kein Toast pro Klickpaket während transacting")
		local waiting = g:InClient(p, function()
			return PressUI.InFlight()
		end)
		T.check(waiting > 0, "Pakete warten auf Bestätigung")
		profile.transacting = false
		g:Advance(4)
		T.eq(d.games.press.clicks - clicks0, 30, "alle 30 Klicks nach dem Kauf gezählt (einmal)")
		g:Advance(4)
		T.eq(d.games.press.clicks - clicks0, 30, "Wiederholungen zählen nicht doppelt")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
