-- Studio-Spieltest (Fehlerbericht „Ölwechsel und Fahrzeug-Check funktionieren nicht“): ein NEUES Profil im
-- kombinierten Place (placeKind "all") spielt wie ein Mensch im Studio-Fenster – jeder GUI-Klick läuft durch den
-- Treffertest (tests/lib/gui_hit.lua): Lobby -> „Open World“ -> „Los geht's“, (Startwahl, falls vorhanden),
-- Tutorial aktiv, dann (3.0) drei Werkstatt-Aufträge komplett über den 2.4.0-Client: Fahrzeug-Check mit Befund
-- (OBD-Tester, Fehlerspeicher, Kunde per Handy anrufen, Freigabe, Ölwechsel, Endkontrolle bei gehobener Bühne und offener
-- Haube), Fahrzeug-Check ohne Befund (Weltklicks) und Ölwechsel ohne einen Werkzeugwechsel – nur E/Weltklick, Werkzeug,
-- Bühne, Haube und Gerät stellt der Server; freie Hand über den Hotbar-Platz „Hand“; QTE-Knopf „STOPP“ zur richtigen
-- Serverzeit; Abrechnen im Tablet. Dazu: kein Phase-4-Element (Tutorial-/Hinweis-/Freischaltungs-/
-- Missionskarten, Abzeichen) liegt über einem 2.4.0-Knopf oder schluckt dessen Klick.
local VIEWPORTS = {
	{ 1280, 650 },
	{ 1100, 600 },
	{ 1366, 768 },
	{ 1920, 1080 },
	{ 844, 390 },
	{ 390, 844 },
}

-- 2.4.0-ScreenGui und die Phase-4-ScreenGuis, die in der Open World gleichzeitig zu sehen sein können
local GARAGE_GUI = "UltimateCarGame"
local PHASE4_GUIS = { "Tutorial", "UnlockCards", "Missionen", "ProgressHUD", "TycoonHUD", "Handy" }

local function prefixed(T, prefix)
	local P = {}
	function P.check(cond, msg)
		return T.check(cond, prefix .. tostring(msg))
	end
	function P.eq(a, e, msg)
		return T.check(a == e, prefix .. (msg or "Wert") .. " – erwartet " .. tostring(e) .. ", erhalten " .. tostring(a))
	end
	return P
end

local function C_TUTORIAL_STEPS(g, path)
	return g:MiniShared("GameConfig").Tutorial.ByPath[path]
end

-- Startweg mit geschenktem Gebäude (autohaus/produktion/schrottplatz): Gebäude steht fertig (Stufe 1, Modell am Anker,
-- Ertrag wartet), Tutorial des Wegs: Intro (laufen, Menü), Tab „Gebäude“ öffnen, Ertrag „Abholen“ – alles per Klick
local function playPath(T, g, p, path, U)
	local GC = g:MiniShared("GameConfig")
	local typ = GC.Start.Paths[path].building
	local e = g:D(p).games.ow.buildings[typ]
	T.check(e ~= nil and e.stage == 1 and e.built == 1, "Gebäude " .. typ .. " Stufe 1 fertig (stage " .. tostring(e and e.stage) .. ", built " .. tostring(e and e.built) .. ")")
	T.check(e ~= nil and e.gift == true, "Gebäude als Startgeschenk markiert")
	local model
	for _, x in ipairs(g:Plot(p):GetDescendants()) do
		if x:GetAttribute("OWType") == typ and x:GetAttribute("OWStage") == 1 and x:GetAttribute("OWSite") == false then
			model = x
		end
	end
	T.check(model ~= nil, "Modell " .. typ .. "_1 am Grundstück aufgestellt")
	local sb = U.snap() and U.snap().ow and U.snap().ow.buildings
	local found
	for _, b in ipairs(type(sb) == "table" and sb or {}) do
		if b.typ == typ or b.id == typ then
			found = b
		end
	end
	if type(sb) == "table" and sb[typ] then
		found = sb[typ]
	end
	T.check(found ~= nil, "Snapshot ow.buildings enthält " .. typ)
	-- Tutorial des Wegs Schritt für Schritt
	local steps = C_TUTORIAL_STEPS(g, path)
	local guard = 0
	while guard < 8 do
		guard += 1
		local v = U.Tut.View()
		if not (v and v.active) then
			break
		end
		local before = v.step
		if v.id == "move" then
			U.click(U.named("Tutorial", "Next"), "Tutorial „Weiter“ (move)")
		elseif v.id == "menu" then
			U.click(U.named(GARAGE_GUI, "MiniGames"), "HUD „Minispiele [M]“ (Tutorial: Menü)")
			g:Advance(0.8)
			if U.MiniUI.IsOpen then
				U.click(U.named("Minispiele", "Close"), "Panel schließen")
			end
		elseif v.openTab then
			T.eq(v.openTab, "buildings", "Schritt " .. v.id .. ": Tab Gebäude")
			U.click(U.named(GARAGE_GUI, "MiniGames"), "HUD „Minispiele [M]“ (" .. v.id .. ")")
			g:Advance(0.5)
			U.click(U.named("Minispiele", "Tab_buildings"), "Tab „Gebäude“ (" .. v.id .. ")")
			g:Advance(1)
		elseif v.event == "action:ow_collect" or v.id:match("_collect$") then
			if not U.MiniUI.IsOpen or U.MiniUI.CurrentTab ~= "buildings" then
				if not U.MiniUI.IsOpen then
					U.click(U.named(GARAGE_GUI, "MiniGames"), "HUD „Minispiele [M]“ (" .. v.id .. ")")
					g:Advance(0.5)
				end
				U.click(U.named("Minispiele", "Tab_buildings"), "Tab „Gebäude“ (" .. v.id .. ")")
				g:Advance(0.5)
			end
			local d = g:D(p)
			local money, parts, scrap = d.money, d.games.parts, d.games.press.scrap
			local card = U.named("Minispiele", "Building_" .. typ)
			local button = card and card:FindFirstChild("CollectButton", true)
			U.click(button, "„Abholen“ " .. typ)
			g:Advance(0.6)
			d = g:D(p)
			T.check(d.money > money or d.games.parts > parts or d.games.press.scrap > scrap,
				"Ertrag abgeholt (Credits " .. tostring(money) .. " -> " .. tostring(d.money) .. ", Altteile " .. tostring(parts) .. " -> " .. tostring(d.games.parts) .. ")")
			if U.MiniUI.IsOpen then
				U.click(U.named("Minispiele", "Close"), "Panel schließen")
			end
		else
			break
		end
		g:Advance(0.8)
		local after = U.Tut.View()
		if not T.check(after and after.step > before, "Tutorial-Schritt " .. tostring(v.id) .. " erledigt") then
			break
		end
	end
	local v = U.Tut.View()
	T.eq(v and v.id, "map", "Tutorial nach Gebäude und Abholen beim Stadtplan")
	T.eq(v and v.step, 5, "Schritt 5 von " .. #steps)
	U.checkOcclusion("Startweg " .. path .. ": nach dem Abholen")
end

local function play(T0, H, vp, path)
	path = path or "werkstatt"
	local label = string.format("[%dx%d%s] ", vp[1], vp[2], path ~= "werkstatt" and (" " .. path) or "")
	local T = prefixed(T0, label)
	local Hit = H.Load("tests/lib/gui_hit.lua")
	local g = H.Garage({ placeKind = "all", viewport = H.Mock.Vector2.new(vp[1], vp[2]) })
	local C = g:Config()
	local p = g:Join(5101, { name = "Studio" })
	g:Advance(0.5)
	g:StartClient(p)
	g:Advance(2)
	local pg = p.PlayerGui
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local Tut = g:ClientModule(p, "Mini.TutorialUI")

	---------------------------------------------------------------- Hilfen
	local function visibleIn(root, pred)
		if not root then
			return nil
		end
		for _, x in ipairs(root:GetDescendants()) do
			if x:IsA("GuiObject") and Hit.Visible(x) and pred(x) then
				return x
			end
		end
		return nil
	end
	local function named(guiName, name)
		return visibleIn(pg:FindFirstChild(guiName), function(x)
			return x.Name == name
		end)
	end
	local function buttonText(guiName, text, exact)
		return visibleIn(pg:FindFirstChild(guiName), function(x)
			local t = x:IsA("GuiButton") and x.Text
			return type(t) == "string" and (exact and t == text or (not exact and t:find(text, 1, true) ~= nil))
		end)
	end
	local function hasText(guiName, text)
		return visibleIn(pg:FindFirstChild(guiName), function(x)
			local t = x.Text
			return type(t) == "string" and t:find(text, 1, true) ~= nil
		end) ~= nil
	end
	local function click(button, what)
		local ok = Hit.Click(T, g, p, button, { label = what })
		g:Advance(0.35)
		return ok
	end
	local function snap()
		return g:MiniSnapshot(p)
	end
	local function job(id)
		for _, j in ipairs(g:Data(p).jobs) do
			if j.id == id then
				return j
			end
		end
	end
	local function visuals(id)
		local s = g:State(p)
		return s and s.visuals and s.visuals[id] or {}
	end

	-- Jeder sichtbare 2.4.0-Knopf muss in seiner Mitte selbst getroffen werden; kein Phase-4-Element darüber
	local function checkOcclusion(stage)
		local garage = pg:FindFirstChild(GARAGE_GUI)
		for _, b in ipairs(garage and garage:GetDescendants() or {}) do
			if b:IsA("GuiButton") and Hit.Visible(b) then
				local x, y, w, h = Hit.Rect(p, b)
				-- Knöpfe außerhalb eines ScrollingFrame-Ausschnitts (Tablet-Liste, Navigation) erreicht man erst durch Scrollen
				local clipped = false
				local cur = b.Parent
				while cur and cur:IsA("GuiObject") do
					if cur:IsA("ScrollingFrame") then
						local fx, fy, fw, fh = Hit.Rect(p, cur)
						local cx, cy = x + w / 2, y + h / 2
						if cx < fx or cx >= fx + fw or cy < fy or cy >= fy + fh then
							clipped = true
						end
					end
					cur = cur.Parent
				end
				if not clipped and w > 0 and h > 0 then
					local cx, cy = x + w / 2, y + h / 2
					if cx >= 0 and cy >= 0 and cx < vp[1] and cy < vp[2] then
						local hit, stack = Hit.At(p, cx, cy)
						if hit ~= b and not (hit and hit:IsDescendantOf(garage)) then
							T.check(false, stage .. ": 2.4.0-Knopf " .. Hit.Path(b) .. " verdeckt von " .. Hit.Path(hit) .. " (oben: " .. Hit.Path(stack[1]) .. ")")
						end
					end
				end
			end
		end
		-- Phase-4-Karten/-Abzeichen (egal in welcher Ebene) überdecken weder die HUD-Leiste noch die Fahrzeugknöpfe
		-- noch irgendeinen sichtbaren 2.4.0-Knopf
		local keep = {}
		local miniButton = named(GARAGE_GUI, "MiniGames")
		if miniButton then
			table.insert(keep, miniButton.Parent) -- HUD-Leiste (unten, 132 px)
		end
		local va = named(GARAGE_GUI, "VehicleActions")
		if va then
			table.insert(keep, va)
		end
		for _, b in ipairs(garage and garage:GetDescendants() or {}) do
			if b:IsA("GuiButton") and Hit.Visible(b) then
				table.insert(keep, b)
			end
		end
		for _, name in ipairs(PHASE4_GUIS) do
			local layer = pg:FindFirstChild(name)
			if layer and layer:IsA("ScreenGui") and layer.Enabled then
				for _, o in ipairs(layer:GetChildren()) do
					if o:IsA("GuiObject") and Hit.Visible(o) then
						local ox, oy, ow, oh = Hit.Rect(p, o)
						T.check(oy >= 0 and oy + oh <= vp[2] + 0.5 and ox >= -0.5 and ox + ow <= vp[1] + 0.5, string.format("%s: %s ragt aus dem Bild (%d, %d, %dx%d)", stage, Hit.Path(o), ox, oy, ow, oh))
						for _, k in ipairs(keep) do
							if Hit.Overlap(p, o, k) then
								T.check(false, stage .. ": " .. Hit.Path(o) .. " überdeckt 2.4.0 " .. Hit.Path(k))
							end
						end
					end
				end
			end
		end
		-- Phase-4-Elemente, die über dem 2.4.0-UI gezeichnet werden, dürfen keinen 2.4.0-Knopf überdecken
		for _, name in ipairs(PHASE4_GUIS) do
			local layer = pg:FindFirstChild(name)
			if layer and layer:IsA("ScreenGui") and layer.Enabled and garage and layer.DisplayOrder >= garage.DisplayOrder then
				for _, o in ipairs(layer:GetDescendants()) do
					if o:IsA("GuiObject") and Hit.Visible(o) and o.Parent == layer then
						for _, b in ipairs(garage:GetDescendants()) do
							if b:IsA("GuiButton") and Hit.Visible(b) and Hit.Overlap(p, o, b) then
								T.check(false, stage .. ": " .. Hit.Path(o) .. " (DisplayOrder " .. layer.DisplayOrder .. ") liegt über 2.4.0-Knopf " .. Hit.Path(b))
							end
						end
					end
				end
			end
		end
	end

	---------------------------------------------------------------- Lobby -> Open World
	T.eq(snap() and snap().mode, "lobby", "neues Profil startet in der Lobby")
	T.check(MiniUI.IsOpen and MiniUI.CurrentTab == "lobby", "Lobby-Tab offen")
	click(named("Minispiele", "ModeCard_openworld"), "Lobby: Karte „Open World“")
	g:Advance(3.2)
	click(named("Minispiele", "GoButton"), "Lobby: „Los geht's“")
	g:Advance(3.5)
	if not T.eq(snap() and snap().mode, "openworld", "nach „Los geht's“ in der Open World") then
		return
	end
	-- Startwahl: ein neues Profil sieht in der Open World die ScreenGui "StartChoice" (StartUI, DisplayOrder 40) mit den
	-- Karten Choice_<weg>. Das Tutorial wartet bis zur Wahl (keine Karte, inaktiv). Steht das Panel noch offen (Lobby-Tab),
	-- weicht die Startwahl aus und kommt nach dem Schließen wieder.
	g:Advance(0.5)
	local MR = g:MiniShared("MetaRules")
	T.check(MR.StartPending(g:D(p)), "neues Profil: Startwahl offen")
	T.check(snap() and type(snap().start) == "table" and snap().start.pending == true, "Snapshot start.pending")
	T.eq(snap() and snap().meta and snap().meta.startPath, "", "Snapshot meta.startPath leer")
	local Start = g:ClientModule(p, "Mini.StartUI")
	if MiniUI.IsOpen then
		T.check(not Start.IsOpen(), "Startwahl weicht dem offenen Panel aus")
		click(named("Minispiele", "Close"), "Panel schließen")
		g:Advance(0.4)
	end
	T.check(Start.IsOpen(), "Startwahl sichtbar")
	local tv = Tut.View()
	T.check(not (tv and tv.active), "Tutorial wartet auf die Startwahl")
	T.check(not Tut.CardVisible(), "keine Tutorial-Karte vor der Startwahl")
	-- Studio: die Startwahl darf keinen 2.4.0-Dialog überdecken – Tablet auf: sie weicht aus, Tablet zu: sie kommt wieder
	do
		local station = g:Station(p, "workshop")
		g:Teleport(p, station, Vector3.new(0, 0, 3))
		g:Advance(0.4)
		g:Trigger(p, station:FindFirstChildOfClass("ProximityPrompt"))
		g:Advance(0.5)
		if T.check(hasText(GARAGE_GUI, "/ ULTIMATE CAR GAME"), "Tablet trotz Startwahl erreichbar (E am Empfang)") then
			T.check(not Start.IsOpen(), "Startwahl blendet sich bei offenem Tablet aus")
			click(buttonText(GARAGE_GUI, "×", true), "Tablet schließen (×)")
			g:Advance(0.3)
		end
		T.check(Start.IsOpen(), "Startwahl nach dem Tablet wieder da")
	end
	local choice = named("StartChoice", "Choice_" .. path)
	click(choice, "Startwahl „" .. path .. "“")
	g:Advance(1.5)
	if not T.check(not MR.StartPending(g:D(p)), "Startwahl gespeichert") then
		return
	end
	T.eq(MR.StartPath(g:D(p)), path, "meta.startPath")
	T.check(not Start.IsOpen(), "Startwahl geschlossen")
	T.eq(snap() and snap().meta and snap().meta.startPath, path, "Snapshot meta.startPath")
	T.check(snap() and snap().start and snap().start.pending == false, "Snapshot start.pending = false")
	if MiniUI.IsOpen then
		click(named("Minispiele", "Close"), "Panel schließen")
	end
	g:Advance(0.6)
	local view = Tut.View()
	T.check(view ~= nil and view.active == true, "Tutorial aktiv")
	T.eq(view and view.path, path, "Tutorial-Weg")
	T.eq(view and view.count, #C_TUTORIAL_STEPS(g, path), "Schrittzahl des Wegs")
	checkOcclusion("Ankunft")
	if path ~= "werkstatt" then
		playPath(T, g, p, path, { named = named, click = click, snap = snap, Tut = Tut, MiniUI = MiniUI, checkOcclusion = checkOcclusion })
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
		return
	end

	---------------------------------------------------------------- Tutorial-Leseschritte über die Karte bzw. das Menü
	local guard = 0
	while Tut.View() and Tut.View().active and Tut.View().next and guard < 4 do
		guard += 1
		local id = Tut.View().id
		if id == "menu" then
			click(named(GARAGE_GUI, "MiniGames"), "HUD „Minispiele [M]“ (Tutorial: Menü)")
			g:Advance(0.8)
			if MiniUI.IsOpen then
				click(named("Minispiele", "Close"), "Panel schließen")
			end
		else
			click(named("Tutorial", "Next"), "Tutorial „Weiter“ (" .. tostring(id) .. ")")
		end
		g:Advance(0.8)
	end
	T.eq(Tut.View() and Tut.View().id, "reception", "Tutorial beim Schritt Empfang")

	---------------------------------------------------------------- Werkstatt-Aufträge über den 2.4.0-Client (3.0)
	-- Nur GUI-Klicks (Treffertest) und E-Knöpfe/Weltklicks: Werkzeug, Hebebühne, Motorhaube und Gerät stellt der
	-- Server beim E-Druck selbst (der Spieler wechselt nie von Hand). Drei Aufträge:
	--   A) Fahrzeug-Check MIT Befund: OBD-Tester -> Fehlerspeicher -> „Kunden anrufen“ -> Handy -> Freigabe ->
	--      Ölwechsel -> Endkontrolle bei wieder gehobener Bühne und offener Haube (beides automatisch) -> Abrechnen
	--   B) Fahrzeug-Check OHNE Befund (Weltklicks): Fehlerspeicher leer -> Sichtprüfung -> Endkontrolle -> Abrechnen
	--   C) Ölwechsel am Empfang angenommen: kein einziger tool/lift/hood/assignEquipment-Befehl vom Client
	local Flow = H.Load("tests/lib/garage_flow.lua")
	local sent = {} -- Absichten, die der Client an Remotes.Command schickt (Name)
	g:Activate()
	g:Remote("Command").OnServerEvent:Connect(function(pl, action)
		if pl == p then
			table.insert(sent, tostring(action))
		end
	end)
	local function goTo(part, offset)
		g:Teleport(p, part, offset or Vector3.new(0, 0, 1.5))
		g:Advance(0.4)
	end
	local function vehicleButton(key)
		return named(GARAGE_GUI, "VehicleAction_" .. key)
	end
	local function toastsSince(m)
		return table.concat(g:Toasts(p, m), " | ")
	end
	local function openReception()
		local station = g:Station(p, "workshop")
		goTo(station, Vector3.new(0, 0, 3))
		local prompt = station:FindFirstChildOfClass("ProximityPrompt")
		g:Trigger(p, prompt)
		g:Advance(0.5)
		return T.check(hasText(GARAGE_GUI, "/ ULTIMATE CAR GAME"), "Tablet am Empfang offen")
	end
	local function closeTablet()
		click(buttonText(GARAGE_GUI, "×", true), "Tablet schließen (×)")
		T.check(not hasText(GARAGE_GUI, "/ ULTIMATE CAR GAME"), "Tablet zu")
	end
	local function checkTutorialHidden(stage)
		T.check(not Tut.CardVisible(), stage .. ": Tutorial-Karte ausgeblendet")
	end
	local function worldPart(car, point)
		for _, x in ipairs(car:GetDescendants()) do
			if x:IsA("BasePart") and x:GetAttribute("WorkPoint") == point then
				return x
			end
		end
		return car:FindFirstChild(point)
	end
	-- Alle Karten oben/unten gleichzeitig zeigen (Freischaltung, Hinweis, Mission), während die Fahrzeugknöpfe da sind
	local function showAllCards(stage)
		g:FireClient(p, "mini_notice", { kind = "unlock", key = "feature:press", title = "Schrottpresse", level = 2, hint = "Neu: die Schrottpresse! Klick Schrott zusammen und tausch ihn beim Schrotthändler gegen Credits." })
		g:FireClient(p, "mini_notice", { kind = "hint", id = "h_studio", text = "Am Empfang nimmst du Aufträge an und rechnest fertige Autos ab." })
		g:FireClient(p, "mini_notice", { kind = "mission", id = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", progress = 3, target = 3, done = true, side = false })
		g:Advance(0.4)
		checkOcclusion(stage)
	end
	-- Am Arbeitspunkt E drücken: Fahrzeugknopf E (Treffertest) oder Weltklick auf das Bauteil
	local function pressAt(jobId, point, what, useWorld)
		local car = g:Car(p, jobId)
		goTo(car[point])
		local m = g:Mark()
		if useWorld then
			Hit.ClickWorld(T, g, p, worldPart(car, point), { label = what .. ": Weltklick" })
			g:Advance(0.35)
		else
			local b = vehicleButton("E")
			if T.check(b ~= nil, what .. ": Fahrzeugknopf E sichtbar") then
				click(b, what .. ": Fahrzeugknopf E")
			end
		end
		return m
	end

	-- Auftrag `kind` im Tablet annehmen (Karte „<Auftrag> · <Auto>“); liefert den Job
	local function acceptJob(kind)
		local def = C.JobById[kind]
		local what = def.name
		if not openReception() then
			return nil
		end
		checkOcclusion(what .. ": Tablet")
		local accept = visibleIn(pg:FindFirstChild(GARAGE_GUI), function(x)
			if not (x:IsA("GuiButton") and x.Text == "Auftrag annehmen") then
				return false
			end
			for _, s in ipairs(x.Parent:GetChildren()) do
				if s:IsA("TextLabel") and s.Text:find(def.name .. " · ", 1, true) == 1 then
					return true
				end
			end
			return false
		end)
		if not T.check(accept ~= nil, what .. ": Angebot im Tablet") then
			return nil
		end
		local before = #g:Data(p).jobs
		click(accept, what .. ": „Auftrag annehmen“")
		g:Advance(0.3)
		local j
		for _, x in ipairs(g:Data(p).jobs) do
			if x.kind == kind then
				j = x
			end
		end
		if not T.check(j ~= nil and #g:Data(p).jobs == before + 1, what .. ": angenommen") then
			return nil
		end
		closeTablet()
		checkOcclusion(what .. ": HUD")
		return j
	end

	-- OBD am DiagnosticPoint ohne Werkzeugwahl: E -> Tester „Verbinden“ -> Fehlerspeicher (diagnose-Ereignis)
	local function readFaultMemory(jobId, what, useWorld, withAnswers)
		local m = pressAt(jobId, "DiagnosticPoint", what .. " OBD", useWorld)
		if not T.check(g:Last(p, "scan", m) ~= nil, what .. ": Scan startet ohne Werkzeugwahl (" .. toastsSince(m) .. ")") then
			return nil
		end
		T.check(named(GARAGE_GUI, "ObdTester") ~= nil, what .. ": OBD-Tester verbindet")
		T.eq(g:State(p).tool, "scanner", what .. ": OBD-Tester automatisch in der Hand")
		g:Advance(2.8)
		local diag = g:Last(p, "diagnose", m)
		if not T.check(diag ~= nil, what .. ": Fehlerspeicher gelesen") then
			return nil
		end
		T.check(named(GARAGE_GUI, "ObdTester") ~= nil, what .. ": OBD-Tester zeigt das Ergebnis")
		T.check(hasText(GARAGE_GUI, "Fahrzeugdiagnose · OBD"), what .. ": Tester-Titel")
		if withAnswers then
			T.check(#(diag.answers or {}) > 0, what .. ": Befund mit Antwortmöglichkeiten")
		else
			T.eq(#(diag.answers or {}), 0, what .. ": Fahrzeug-Check ohne Multiple-Choice-Antworten")
		end
		checkTutorialHidden(what .. " (Tester)")
		checkOcclusion(what .. " (Tester)")
		-- Gerätetasten des Testers: Messwerte und zurück zum Fehlerspeicher
		click(named(GARAGE_GUI, "TesterBtn_values"), what .. ": Tester „Messwerte“")
		T.check(hasText(GARAGE_GUI, "Messwerte"), what .. ": Seite Messwerte")
		click(named(GARAGE_GUI, "TesterBtn_codes"), what .. ": Tester „Fehlerspeicher“")
		return diag
	end

	-- Reparaturschritt nur mit E (bzw. Weltklick): fährt die Bühne erst, drückt der Spieler einfach noch einmal
	local function repairStepE(jobId, i, useWorld, cards)
		local j = job(jobId)
		local def = C.JobById[j.kind]
		local step = def.steps[i]
		local what = def.name .. " Schritt " .. i
		if cards then
			goTo(g:Car(p, jobId)[step.point])
			T.check(vehicleButton("E") ~= nil, what .. ": Fahrzeugknopf E sichtbar")
			showAllCards(what .. " (alle Karten + Fahrzeugknöpfe)")
		end
		local c, log = nil, {}
		for _ = 1, 4 do
			local m = pressAt(jobId, step.point, what, useWorld)
			c = g:Last(p, "challenge", m)
			if c then
				break
			end
			table.insert(log, toastsSince(m))
			g:Advance(2.6) -- Bühne fährt / Haube geht auf
		end
		if not T.check(c ~= nil, what .. ": QTE startet nur mit E (" .. table.concat(log, " || ") .. ")") then
			return false
		end
		local tool = g:State(p).tool
		T.check(tool ~= "hand" and tool ~= nil, what .. ": Werkzeug automatisch in der Hand (" .. tostring(tool) .. ")")
		T.check(p.Character:FindFirstChild("GarageTool") ~= nil, what .. ": Werkzeug-Modell in der Hand")
		if step.equipment then
			T.eq(g:Data(p).equipmentBays[step.equipment], j.bay, what .. ": Gerät automatisch an Bühne " .. tostring(j.bay))
		end
		if step.lifted ~= nil then
			T.eq(visuals(jobId).lifted == true, step.lifted, what .. ": Bühne automatisch richtig")
		end
		g:Advance(0.1)
		checkTutorialHidden(what .. " (QTE)")
		checkOcclusion(what .. " (QTE)")
		local stop = buttonText(GARAGE_GUI, "STOPP", true)
		g:AdvanceTo(c.startAt + c.center * c.period)
		local m = g:Mark()
		Hit.Click(T, g, p, stop, { label = what .. ": QTE „STOPP“" })
		if not T.check(g:HasToast(p, "Arbeit läuft", m), what .. ": Treffer (Toasts: " .. toastsSince(m) .. ")") then
			return false
		end
		g:AdvanceTo(job(jobId).workUntil + 0.6)
		return true
	end

	-- Endkontrolle nur mit E am OBD-Anschluss: Haube zu und Bühne runter macht der Server (danach noch einmal E)
	local function finalCheckE(jobId, what, useWorld)
		local scanned, log = nil, {}
		for _ = 1, 4 do
			local m = pressAt(jobId, "DiagnosticPoint", what .. " Endkontrolle", useWorld)
			if g:Last(p, "scan", m) then
				scanned = m
				break
			end
			table.insert(log, toastsSince(m))
			g:Advance(2.6)
		end
		if not T.check(scanned ~= nil, what .. ": Endkontrolle startet mit E (" .. table.concat(log, " || ") .. ")") then
			return false
		end
		g:Advance(2.8)
		T.check(g:Last(p, "diagnose", scanned) ~= nil, what .. ": Endkontrolle meldet Bericht")
		local v = visuals(jobId)
		T.eq(v.lifted == true, false, what .. ": Bühne automatisch unten")
		T.eq(v.hood == true, false, what .. ": Haube automatisch zu")
		if not T.eq(job(jobId) and job(jobId).phase, "invoice", what .. ": Phase invoice") then
			return false
		end
		checkOcclusion(what .. ": Endkontrolle")
		click(buttonText(GARAGE_GUI, "Schließen", true), what .. ": Tester schließen")
		T.check(named(GARAGE_GUI, "ObdTester") == nil, what .. ": Tester zu")
		return true
	end

	-- Abrechnen am Empfang im Tablet (Karte mit „Bühne n“)
	local function settle(j, what)
		local money = g:Data(p).money
		if not openReception() then
			return nil
		end
		local btn = visibleIn(pg:FindFirstChild(GARAGE_GUI), function(x)
			if not (x:IsA("GuiButton") and x.Text == "Abrechnen") then
				return false
			end
			for _, s in ipairs(x.Parent:GetChildren()) do
				if s:IsA("TextLabel") and s.Text:find("Bühne " .. j.bay, 1, true) then
					return true
				end
			end
			return false
		end)
		local m = g:Mark()
		click(btn, what .. ": „Abrechnen“")
		local receipt = g:Last(p, "receipt", m)
		T.check(receipt ~= nil, what .. ": Quittung")
		T.check(job(j.id) == nil, what .. ": Auftrag abgerechnet")
		T.check(g:Data(p).money > money, what .. ": Geld gestiegen (" .. tostring(money) .. " -> " .. tostring(g:Data(p).money) .. ")")
		checkOcclusion(what .. ": Quittung")
		click(buttonText(GARAGE_GUI, "Weiter", true), what .. ": Quittung „Weiter“")
		if hasText(GARAGE_GUI, "/ ULTIMATE CAR GAME") then
			closeTablet()
		end
		return receipt
	end

	-- Befund des frisch angenommenen Fahrzeug-Checks festlegen (Testkontrolle statt Zufall: R.InspectionFinding)
	local function forceFinding(j, finding)
		local live = Flow.LiveJob(g, p, j.id)
		if T.check(live ~= nil and live.kind == "inspection", "Fahrzeug-Check live") then
			live.finding = finding
		end
	end

	-- A) Fahrzeug-Check mit Befund -> Handy -> Ölwechsel -> Endkontrolle (Bühne hoch, Haube offen) -> Abrechnen
	local function playCheckWithFinding()
		local what = "Fahrzeug-Check mit Befund"
		-- freie Hand: fester Hotbar-Platz (Taste 1), kein Werkzeug in der Hand
		T.check(named(GARAGE_GUI, "ToolSlotHand") ~= nil, "Hotbar: Platz „Hand“ sichtbar")
		click(named(GARAGE_GUI, "ToolSlotHand"), "Hotbar: freie Hand")
		T.eq(g:State(p).tool, "hand", "freie Hand gewählt")
		T.check(p.Character:FindFirstChild("GarageTool") == nil, "freie Hand: nichts in der Hand")
		local j = acceptJob("inspection")
		if not j then
			return false
		end
		forceFinding(j, "oil")
		local diag = readFaultMemory(j.id, what)
		if not diag then
			return false
		end
		T.eq(diag.phase, "approval", what .. ": Kunde muss freigeben")
		T.eq(job(j.id).phase, "approval", what .. ": Phase approval")
		T.check(type(diag.codes) == "table" and #diag.codes > 0, what .. ": Fehlercodes gespeichert")
		T.check(hasText(GARAGE_GUI, "Fehler gespeichert"), what .. ": Tester zeigt „Fehler gespeichert“")
		local code = diag.codes and diag.codes[1]
		local codeText = type(code) == "table" and code.code or code
		T.check(codeText ~= nil and hasText(GARAGE_GUI, tostring(codeText)), what .. ": Fehlercode " .. tostring(codeText) .. " im Tester")
		T.check(hasText(GARAGE_GUI, "ruf ihn mit dem Handy an"), what .. ": Hinweis aufs Handy")
		-- Kunden anrufen: Knopf im Tester -> Handy öffnet sich und wählt (Antwort: Testkontrolle „ja“)
		local Phone = g:ClientModule(p, "Mini.PhoneUI")
		local R = g:Rules()
		local original = R.CustomerDecision
		R.CustomerDecision = function()
			return true
		end
		local m = g:Mark()
		click(named(GARAGE_GUI, "CallCustomer"), what .. ": Tester „Kunden anrufen (P)“")
		g:Advance(0.3)
		T.check(named(GARAGE_GUI, "ObdTester") == nil, what .. ": Tester macht dem Handy Platz")
		T.check(Phone.IsOpen() and Phone.IsVisible(), what .. ": Handy offen")
		local ringing
		for _, e in ipairs(g:Events(p, "call", m)) do
			if e.state == "ringing" then
				ringing = e
			end
		end
		T.check(ringing ~= nil, what .. ": Es klingelt (" .. toastsSince(m) .. ")")
		T.check(named("Handy", "CallScreen") ~= nil, what .. ": Anruf-Bildschirm")
		checkOcclusion(what .. ": Anruf")
		g:Advance(C.Inspection.RingSeconds + 0.5)
		R.CustomerDecision = original
		local answer
		for _, e in ipairs(g:Events(p, "call", m)) do
			if e.state == "answer" then
				answer = e
			end
		end
		if not T.check(answer ~= nil and answer.accepted == true, what .. ": Kunde gibt frei") then
			return false
		end
		T.check(type(answer.text) == "string" and hasText("Handy", answer.text), what .. ": Antwort als Sprechblase im Handy")
		click(named("Handy", "HangUp"), what .. ": Handy „Fertig“")
		g:Advance(0.4)
		T.check(not Phone.IsOpen(), what .. ": „Fertig“ schließt das Handy (Werkstatt wieder frei)")
		T.check(not Phone.IsOpen(), what .. ": Handy zu")
		local live = job(j.id)
		T.eq(live and live.phase, "repair", what .. ": Phase repair nach der Freigabe")
		T.eq(live and live.kind, "oil", what .. ": Befund wird repariert (Ölwechsel)")
		T.eq(live and live.step, 1, what .. ": ab Schritt 1")
		local def = C.JobById.oil
		for i = 1, #def.steps do
			if not repairStepE(j.id, i, false, i == 1) then
				return false
			end
		end
		-- Endkontrolle mit gehobener Bühne und offener Haube: Bühne per Fahrzeugknopf F wieder hoch
		local plot = g:Plot(p)
		goTo(plot.Bays:FindFirstChild("Bay_" .. job(j.id).bay).LiftControl, Vector3.new(0, 0, 1.5))
		click(vehicleButton("F"), what .. ": Fahrzeugknopf F (Bühne hoch)")
		g:Advance(2.6)
		T.eq(visuals(j.id).lifted == true, true, what .. ": Bühne vor der Endkontrolle oben")
		T.eq(visuals(j.id).hood == true, true, what .. ": Haube vor der Endkontrolle offen")
		if not finalCheckE(j.id, what, false) then
			return false
		end
		local receipt = settle(j, what)
		T.check(receipt ~= nil and type(receipt.name) == "string" and receipt.name:find("Fahrzeug-Check", 1, true) ~= nil and receipt.name:find("Ölwechsel", 1, true) ~= nil,
			what .. ": Quittung „Fahrzeug-Check + Ölwechsel“ (" .. tostring(receipt and receipt.name) .. ")")
		return receipt ~= nil
	end

	-- B) Fahrzeug-Check ohne Befund, alles per Weltklick
	local function playCheckClean()
		local what = "Fahrzeug-Check ohne Befund"
		local j = acceptJob("inspection")
		if not j then
			return false
		end
		forceFinding(j, nil)
		local diag = readFaultMemory(j.id, what, true)
		if not diag then
			return false
		end
		T.eq(diag.phase, "repair", what .. ": ohne Fehler gleich zur Sichtprüfung")
		T.check(type(diag.codes) == "table" and #diag.codes == 0, what .. ": Fehlerspeicher leer")
		T.check(hasText(GARAGE_GUI, "Keine Fehler gespeichert"), what .. ": Tester zeigt „Keine Fehler gespeichert“")
		T.check(named(GARAGE_GUI, "CallCustomer") == nil, what .. ": kein Anruf nötig")
		click(buttonText(GARAGE_GUI, "Schließen", true), what .. ": Tester schließen")
		T.eq(job(j.id).phase, "repair", what .. ": Phase repair")
		local def = C.JobById.inspection
		for i = 1, #def.steps do
			if not repairStepE(j.id, i, true, false) then
				return false
			end
		end
		if not finalCheckE(j.id, what, true) then
			return false
		end
		return settle(j, what) ~= nil
	end

	-- C) Ölwechsel ohne einen einzigen Werkzeugwechsel des Spielers
	local function playOilNoToolSwitch()
		local what = "Ölwechsel ohne Werkzeugwechsel"
		local j = acceptJob("oil")
		if not j then
			return false
		end
		local from = #sent
		local def = C.JobById.oil
		-- Diagnose: E am OBD-Anschluss, im Tester unter „Befund“ die Ursache antippen
		local diag = readFaultMemory(j.id, what, false, true)
		if not diag then
			return false
		end
		click(named(GARAGE_GUI, "TesterBtn_finding"), what .. ": Tester „Befund“")
		click(named(GARAGE_GUI, "Answer_" .. def.cause), what .. ": Befund „" .. tostring(def.answers[def.cause]) .. "“")
		g:Advance(0.4)
		if not T.eq(job(j.id).phase, "repair", what .. ": Phase repair") then
			return false
		end
		local close = buttonText(GARAGE_GUI, "Schließen", true)
		if close then
			click(close, what .. ": Tester schließen")
		end
		for i = 1, #def.steps do
			if not repairStepE(j.id, i, false, false) then
				return false
			end
		end
		if not finalCheckE(j.id, what, false) then
			return false
		end
		local manual = {}
		for k = from + 1, #sent do
			local a = sent[k]
			if a == "tool" or a == "lift" or a == "hood" or a == "assignEquipment" then
				table.insert(manual, a)
			end
		end
		T.eq(#manual, 0, what .. ": keine Handgriffe nötig (" .. table.concat(manual, ", ") .. ")")
		return settle(j, what) ~= nil
	end

	local okA = playCheckWithFinding()
	T.check(okA, "Fahrzeug-Check mit Befund + Handy + Ölwechsel komplett")
	local v = Tut.View()
	T.check(v ~= nil and (v.step or 0) >= 8, "Tutorial bis nach dem Abrechnen weiter (Schritt " .. tostring(v and v.step) .. ")")
	local okB = okA and playCheckClean()
	T.check(okB, "Fahrzeug-Check ohne Befund komplett")
	local okC = okB and playOilNoToolSwitch()
	T.check(okC, "Ölwechsel ohne Werkzeugwechsel komplett")
	local toolCmds = 0
	for _, a in ipairs(sent) do
		if a == "tool" then
			toolCmds += 1
		end
	end
	T.eq(toolCmds, 1, "einziger tool-Befehl: die freie Hand")
	T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
end

-- 3.x: ein Server (all-Place, Studio), vier neue Profile nacheinander bei 1280x650: Lobby -> Open World per Klick, jeder
-- Startweg über die hit-getestete StartUI; Mission 1 des Wegs läuft sofort (Snapshot + Karte „Deine Mission“), der
-- Willkommens-Flitzer steht neben dem Spieler; danach öffnet „/dev“ (Studio = Entwickler) das Entwickler-Menü und
-- setzt per Klick Level 90 und Credits (Server-Profil und 2.4.0-Zustand).
local function playStartsAndDev(T0, H)
	local vp = VIEWPORTS[1]
	local Hit = H.Load("tests/lib/gui_hit.lua")
	local g = H.Garage({ placeKind = "all", viewport = H.Mock.Vector2.new(vp[1], vp[2]), studio = true })
	local GC = g:MiniShared("GameConfig")
	local MR = g:MiniShared("MetaRules")
	local SR = g:MiniShared("StoryRules")
	local firstPlayer, firstT
	for i, path in ipairs({ "werkstatt", "autohaus", "produktion", "schrottplatz" }) do
		local T = prefixed(T0, string.format("[%dx%d Start %s] ", vp[1], vp[2], path))
		local uid = 5300 + i
		local p = g:Join(uid, { name = "Start" .. i })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(2)
		local pg = p.PlayerGui
		local MiniUI = g:ClientModule(p, "Mini.MiniUI")
		local function visible(guiName, name)
			local root = pg:FindFirstChild(guiName)
			for _, x in ipairs(root and root:GetDescendants() or {}) do
				if x.Name == name and x:IsA("GuiObject") and Hit.Visible(x) then
					return x
				end
			end
			return nil
		end
		local function click(button, what)
			local ok = Hit.Click(T, g, p, button, { label = what })
			g:Advance(0.35)
			return ok
		end
		-- Lobby -> Open World
		T.check(MiniUI.IsOpen and MiniUI.CurrentTab == "lobby", "Lobby-Tab offen")
		click(visible("Minispiele", "ModeCard_openworld"), "Lobby: Karte „Open World“")
		g:Advance(3.2)
		click(visible("Minispiele", "GoButton"), "Lobby: „Los geht's“")
		g:Advance(3.5)
		local d = g:D(p)
		if not T.eq(g:Session(p).mode, "openworld", "in der Open World") then
			return
		end
		T.check(MR.StartPending(d), "Startwahl offen (Pflicht)")
		local Start = g:ClientModule(p, "Mini.StartUI")
		if MiniUI.IsOpen then
			click(visible("Minispiele", "Close"), "Panel schließen")
			g:Advance(0.4)
		end
		T.check(Start.IsOpen(), "Startwahl sichtbar")
		T.check(visible("StartChoice", "Later") == nil and visible("StartChoice", "LaterButton") == nil, "kein „Später entscheiden“")
		for _, other in ipairs(GC.Start.Order) do
			T.check(visible("StartChoice", "Choice_" .. other) ~= nil, "Karte " .. other .. " sichtbar")
		end
		local m = g:Mark()
		click(visible("StartChoice", "Choice_" .. path), "Startwahl „" .. path .. "“")
		g:Advance(1.5)
		T.eq(MR.StartPath(d), path, "Startweg gespeichert")
		T.check(not Start.IsOpen(), "Startwahl geschlossen")
		-- Mission 1 des Wegs läuft sofort
		local list = GC.Story.Chapters[1].Paths and GC.Story.Chapters[1].Paths[path] or GC.Story.Chapters[1].Missions
		local first = list[1]
		local active = d.games.story.active
		T.check(type(active) == "table" and active.id == first.id, "Mission 1 läuft sofort (" .. first.id .. ", erhalten " .. tostring(type(active) == "table" and active.id) .. ")")
		local started = nil
		for _, n in ipairs(g:Notices(p, "story", m)) do
			if n.event == "started" and n.mission == first.id then
				started = n
			end
		end
		T.check(started ~= nil, "Hinweis „Mission gestartet“")
		g:Advance(1.2)
		local sn = g:MiniSnapshot(p)
		T.check(sn and sn.story and type(sn.story.active) == "table" and sn.story.active.id == first.id, "Snapshot story.active = Mission 1")
		-- Kapitel-Karte „Deine Story beginnt“ wegklicken, dann zeigt die Karte „Deine Mission“ Mission 1
		local ok = visible("Missionen", "ChapterOk")
		if ok then
			click(ok, "Kapitel-Karte „Los geht's!“")
			g:Advance(0.5)
		end
		local tracker = visible("Missionen", "MissionTracker")
		T.check(tracker ~= nil, "Karte „Deine Mission“ sichtbar")
		local title = tracker and tracker:FindFirstChild("Title", true)
		T.eq(title and title.Text, first.title, "Karte zeigt Mission 1")
		-- Willkommens-Flitzer neben dem Spieler (Startauto, Open World)
		local car = nil
		for _ = 1, 20 do
			car = g:Find("Workspace.PlayerCars.Car_" .. uid)
			if car then
				break
			end
			g:Advance(0.5)
		end
		T.check(car ~= nil, "Flitzer erscheint (Workspace.PlayerCars.Car_" .. uid .. ")")
		local intro = nil
		for _, n in ipairs(g:Notices(p, "car_spawned", m)) do
			if n.at == "intro" then
				intro = n
			end
		end
		T.check(intro ~= nil and intro.model == "flitzer", "car_spawned intro: Flitzer")
		-- Platz: direkt neben dem Spieler (Raycast in Roblox) bzw. die nächste freie Fahrbahn (der Mock kennt keine
		-- Raycasts): in jedem Fall in Sichtweite und auf dem Boden
		local root = g:Root(p)
		if car and root then
			local dist = (car:GetPivot().Position - root.Position).Magnitude
			T.check(dist < 80, "Flitzer in Sichtweite (" .. math.floor(dist) .. " Studs)")
			T.check(math.abs(car:GetPivot().Position.Y - (root.Position.Y - 3)) < 6, "Flitzer steht auf dem Boden")
		end
		if i == 1 then
			firstPlayer, firstT = p, T
		end
	end
	T0.eq(#g:Errors(), 0, "keine Laufzeitfehler (Startwege): " .. g:ErrorText())

	---------------------------------------------------------------- Entwickler-Menü über „/dev“ (Studio)
	local p, T = firstPlayer, firstT
	if not p then
		return
	end
	local d = g:D(p)
	local gui = p.PlayerGui:FindFirstChild("DevMenu")
	T.check(gui ~= nil and gui.DisplayOrder == 45, "ScreenGui DevMenu (45)")
	T.check(gui ~= nil and not gui.Enabled, "Menü anfangs zu")
	local m = g:Mark()
	g:Activate()
	p.Chatted:Fire("/dev")
	g:Advance(0.8)
	local opened = g:Notices(p, "dev", m)
	T.check(#opened >= 1 and opened[#opened].event == "open", "„/dev“ im Studio: mini_notice dev/open")
	if not T.check(gui ~= nil and gui.Enabled, "Entwickler-Menü offen") then
		return
	end
	local function find(name)
		for _, x in ipairs(gui:GetDescendants()) do
			if x.Name == name then
				return x
			end
		end
		return nil
	end
	local function typeInto(name, text)
		local box = find(name)
		g:InClient(p, function()
			box.Text = text
		end)
	end
	typeInto("LevelBox", "90")
	Hit.Click(T, g, p, find("SetLevel"), { label = "„Level setzen“" })
	g:Advance(1.2)
	T.eq(d.level, 90, "Level 90 im Profil")
	typeInto("CreditsBox", "250.000")
	Hit.Click(T, g, p, find("SetCredits"), { label = "„Credits setzen“" })
	g:Advance(1.2)
	T.eq(d.money, 250000, "250.000 Credits im Profil")
	local st = g:State(p)
	T.check(st and st.data and st.data.level == 90 and st.data.money == 250000, "2.4.0-Zustand zeigt Level 90 und 250.000 Credits")
	local info = find("Info_Level")
	T.check(info ~= nil and string.find(info.Text, "90", 1, true) ~= nil, "Menü zeigt Level 90")
	local infoC = find("Info_Credits")
	T.check(infoC ~= nil and string.find(infoC.Text, "250.000", 1, true) ~= nil, "Menü zeigt 250.000 Credits")
	Hit.Click(T, g, p, find("Close"), { label = "„Schließen“" })
	g:Advance(0.3)
	T.check(not gui.Enabled, "Menü geschlossen")
	T0.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
end

local cases = {
	{ "gui_hit: DisplayOrder, ZIndex, Active/Knöpfe, ClipsDescendants, Topbar-Abstand, UIScale, Enabled/Visible", function(T, H)
		local Hit = H.Load("tests/lib/gui_hit.lua")
		local g = H.Garage({ viewport = H.Mock.Vector2.new(1000, 600) })
		local p = g:Join(5199, { name = "Hit" })
		g:StartClient(p, { run = false })
		local r = {}
		g:InClient(p, function()
			local function sg(name, order, ignore)
				local x = Instance.new("ScreenGui")
				x.Name, x.DisplayOrder, x.IgnoreGuiInset = name, order, ignore == true
				x.Parent = p.PlayerGui
				return x
			end
			local function obj(cls, parent, pos, size, props)
				local o = Instance.new(cls)
				o.Position, o.Size = pos, size
				for k, v in pairs(props or {}) do
					o[k] = v
				end
				o.Parent = parent
				return o
			end
			local low, high = sg("Low", 5), sg("High", 20)
			r.lowButton = obj("TextButton", low, UDim2.fromOffset(100, 100), UDim2.fromOffset(100, 50))
			r.passive = obj("Frame", high, UDim2.fromOffset(90, 90), UDim2.fromOffset(200, 100)) -- nicht Active: Klick geht durch
			r.active = obj("Frame", high, UDim2.fromOffset(400, 100), UDim2.fromOffset(100, 100), { Active = true })
			r.under = obj("TextButton", low, UDim2.fromOffset(410, 110), UDim2.fromOffset(50, 50))
			-- Geschwister: höherer ZIndex gewinnt, sonst die spätere
			r.z1 = obj("TextButton", low, UDim2.fromOffset(600, 100), UDim2.fromOffset(100, 100), { ZIndex = 3 })
			r.z2 = obj("TextButton", low, UDim2.fromOffset(600, 100), UDim2.fromOffset(100, 100), { ZIndex = 1 })
			-- ClipsDescendants: Knopf ragt aus dem Rahmen, außen nicht klickbar
			local clip = obj("Frame", low, UDim2.fromOffset(100, 300), UDim2.fromOffset(100, 100), { ClipsDescendants = true })
			r.clipped = obj("TextButton", clip, UDim2.fromOffset(50, 0), UDim2.fromOffset(100, 50))
			-- IgnoreGuiInset: dieselbe Position liegt 36 px höher
			local top = sg("Top", 1, true)
			r.noInset = obj("TextButton", top, UDim2.fromOffset(800, 0), UDim2.fromOffset(100, 30))
			-- UIScale um den Ankerpunkt
			r.scaled = obj("TextButton", low, UDim2.fromOffset(300, 450), UDim2.fromOffset(100, 100), { AnchorPoint = Vector2.new(0.5, 0.5) })
			local sc = Instance.new("UIScale")
			sc.Scale = 0.5
			sc.Parent = r.scaled
			-- unsichtbare Ebene
			r.hidden = obj("TextButton", sg("Off", 50), UDim2.fromOffset(800, 400), UDim2.fromOffset(100, 100))
			r.hidden.Parent.Enabled = false
			r.target = obj("TextButton", low, UDim2.fromOffset(800, 400), UDim2.fromOffset(100, 100))
		end)
		T.eq(Hit.At(p, 150, 125 + 36), r.lowButton, "nicht-aktiver Rahmen darüber lässt den Klick durch")
		T.eq(Hit.At(p, 430, 130 + 36), r.active, "Active-Rahmen darüber schluckt den Klick")
		local blocked = Hit.Click({ check = function() return true end }, g, p, r.under)
		T.eq(blocked, false, "Click meldet den verdeckten Knopf")
		T.eq(Hit.At(p, 650, 150 + 36), r.z1, "höherer ZIndex gewinnt")
		T.eq(Hit.At(p, 170, 320 + 36), r.clipped, "im Rahmen getroffen")
		T.eq(Hit.At(p, 220, 320 + 36), nil, "außerhalb des schneidenden Rahmens nicht")
		T.eq(Hit.At(p, 850, 15), r.noInset, "IgnoreGuiInset: ohne Topbar-Abstand")
		local x, y, w, h = Hit.Rect(p, r.scaled)
		T.check(math.abs(w - 50) < 0.01 and math.abs(h - 50) < 0.01 and math.abs(x - 275) < 0.01 and math.abs(y - (425 + 36)) < 0.01, "UIScale um den Ankerpunkt: " .. x .. "," .. y .. " " .. w .. "x" .. h)
		T.eq(Hit.At(p, 850, 450 + 36), r.target, "abgeschaltete ScreenGui zählt nicht")
	end },
}
for _, vp in ipairs(VIEWPORTS) do
	table.insert(cases, { string.format("Studio-Spiel %dx%d: Lobby -> Open World, Startwahl Werkstatt, Tutorial, Fahrzeug-Check mit Handy-Freigabe, ohne Befund, Ölwechsel nur mit E", vp[1], vp[2]), function(T, H)
		play(T, H, vp, "werkstatt")
	end })
	table.insert(cases, { string.format("Studio-Spiel %dx%d: Startwahl Autohaus – Gebäude fertig, Tutorial-Weg per Klick", vp[1], vp[2]), function(T, H)
		play(T, H, vp, "autohaus")
	end })
end
table.insert(cases, { "Studio-Spiel 1280x650: Startwahl Produktion – Bauteil-Pakete, Tutorial-Weg per Klick", function(T, H)
	play(T, H, VIEWPORTS[1], "produktion")
end })
table.insert(cases, { "Studio-Spiel 390x844: Startwahl Schrottplatz – Schrott abholen, Tutorial-Weg per Klick", function(T, H)
	play(T, H, VIEWPORTS[6], "schrottplatz")
end })
table.insert(cases, { "Studio-Spiel 1280x650 (all-Place): jeder Startweg per StartUI-Klick -> Mission 1 sofort, Flitzer erscheint; „/dev“ öffnet das Entwickler-Menü, Level 90 und Credits per Klick", function(T, H)
	playStartsAndDev(T, H)
end })
return cases
