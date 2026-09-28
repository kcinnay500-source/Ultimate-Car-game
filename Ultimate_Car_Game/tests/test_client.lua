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
			local Cat = g:MiniShared("MiniCatalog")
			local text = Cat.Questions[q.index].a[q.order[2]]
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
		local batches, total = 0, 0
		for _, a in ipairs((sentFrom(g, n0))) do
			if a[1] == "mini_press_click" then
				batches += 1
				total += a[2].count
				T.eq(a[2].rid, nil, "Klickpaket ohne rid")
				T.eq(a[2].scrap, nil, "kein Betrag im Klickpaket")
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
}
