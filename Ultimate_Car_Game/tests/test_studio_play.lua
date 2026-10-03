-- Studio-Spieltest (Fehlerbericht „Ölwechsel und Fahrzeug-Check funktionieren nicht“): ein NEUES Profil im
-- kombinierten Place (placeKind "all") spielt wie ein Mensch im Studio-Fenster – jeder GUI-Klick läuft durch den
-- Treffertest (tests/lib/gui_hit.lua): Lobby -> „Open World“ -> „Los geht's“, (Startwahl, falls vorhanden),
-- Tutorial aktiv, dann Fahrzeug-Check und Ölwechsel komplett über den 2.4.0-Client: Empfang/Tablet, OBD-Scan über
-- die Fahrzeugknöpfe (E/F/H) bzw. den Weltklick, Diagnose-Antwort, Reparaturschritte, QTE-Knopf „STOPP“ zur
-- richtigen Serverzeit, Endkontrolle, Abrechnen. Dazu: kein Phase-4-Element (Tutorial-/Hinweis-/Freischaltungs-/
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
local PHASE4_GUIS = { "Tutorial", "UnlockCards", "Missionen", "ProgressHUD", "TycoonHUD" }

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

	---------------------------------------------------------------- Werkstatt-Auftrag über den 2.4.0-Client
	local function toolSlot(id)
		for i, t in ipairs(g:Data(p).loadout) do
			if t == id then
				return named(GARAGE_GUI, "ToolSlot" .. i)
			end
		end
	end
	local function selectTool(id)
		if g:State(p).tool == id then
			return true
		end
		click(toolSlot(id), "Werkzeugleiste " .. id)
		return T.eq(g:State(p).tool, id, "Werkzeug " .. id .. " gewählt")
	end
	local function goTo(part, offset)
		g:Teleport(p, part, offset or Vector3.new(0, 0, 1.5))
		g:Advance(0.4)
	end
	local function vehicleButton(key)
		return named(GARAGE_GUI, "VehicleAction_" .. key)
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
	-- Lift (F) bzw. Haube (H) in den gewünschten Zustand bringen
	local function ensure(jobId, field, want)
		local v = visuals(jobId)
		if (v[field] == true) == want then
			return true
		end
		local car = g:Car(p, jobId)
		local j = job(jobId)
		if field == "lifted" then
			local plot = g:Plot(p)
			goTo(plot.Bays:FindFirstChild("Bay_" .. j.bay).LiftControl, Vector3.new(0, 0, 1.5))
			click(vehicleButton("F"), "Fahrzeugknopf F (Bühne)")
			g:Advance(2.6)
		else
			goTo(car.HoodPoint, Vector3.new(0, 0, 1.5))
			click(vehicleButton("H"), "Fahrzeugknopf H (Haube)")
			g:Advance(0.6)
		end
		return T.eq(visuals(jobId)[field] == true, want, field .. " = " .. tostring(want))
	end
	local function checkTutorialHidden(stage)
		T.check(not Tut.CardVisible(), stage .. ": Tutorial-Karte ausgeblendet")
	end
	-- OBD am DiagnosticPoint über den Fahrzeugknopf E; liefert das Ergebnis-Dialog-Ereignis
	local function scan(jobId, what)
		local car = g:Car(p, jobId)
		selectTool("scanner")
		goTo(car.DiagnosticPoint)
		local m = g:Mark()
		click(vehicleButton("E"), what .. ": Fahrzeugknopf E (OBD)")
		g:Advance(2.8)
		local diag = g:Last(p, "diagnose", m)
		T.check(diag ~= nil, what .. ": OBD-Dialog")
		checkTutorialHidden(what .. " (Dialog)")
		checkOcclusion(what .. " (Dialog)")
		return diag
	end
	local function worldPart(car, point)
		for _, x in ipairs(car:GetDescendants()) do
			if x:IsA("BasePart") and x:GetAttribute("WorkPoint") == point then
				return x
			end
		end
		return car:FindFirstChild(point)
	end
	-- Reparaturschritt: Gerät bereitstellen, Lift/Haube, Werkzeug, E-Knopf oder Weltklick, QTE „STOPP“
	-- Alle Karten oben/unten gleichzeitig zeigen (Freischaltung, Hinweis, Mission), während die Fahrzeugknöpfe da sind
	local function showAllCards(stage)
		g:FireClient(p, "mini_notice", { kind = "unlock", key = "feature:press", title = "Schrottpresse", level = 2, hint = "Neu: die Schrottpresse! Klick Schrott zusammen und tausch ihn beim Schrotthändler gegen Credits." })
		g:FireClient(p, "mini_notice", { kind = "hint", id = "h_studio", text = "Am Empfang nimmst du Aufträge an und rechnest fertige Autos ab." })
		g:FireClient(p, "mini_notice", { kind = "mission", id = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", progress = 3, target = 3, done = true, side = false })
		g:Advance(0.4)
		checkOcclusion(stage)
	end
	local function repairStep(jobId, i, useWorld, cards)
		local j = job(jobId)
		local def = C.JobById[j.kind]
		local step = def.steps[i]
		local what = def.name .. " Schritt " .. i
		if step.equipment and g:Data(p).equipmentBays[step.equipment] ~= j.bay then
			local device = g:Plot(p).Equipment:FindFirstChild(step.equipment)
			goTo(device.Badge, Vector3.new(0, 0, 2))
			g:Trigger(p, device.Badge:FindFirstChild("AssignPrompt"))
			g:Advance(0.4)
			click(buttonText(GARAGE_GUI, "Bühne " .. j.bay .. " ·"), what .. ": Gerät an Bühne " .. j.bay)
			g:Advance(0.4)
			T.eq(g:Data(p).equipmentBays[step.equipment], j.bay, what .. ": Gerät bereit")
		end
		if step.lifted ~= nil then
			ensure(jobId, "lifted", step.lifted)
		end
		if step.hood then
			ensure(jobId, "hood", true)
		end
		selectTool(step.tool)
		local car = g:Car(p, jobId)
		goTo(car[step.point])
		if cards then
			T.check(named(GARAGE_GUI, "VehicleAction_E") ~= nil, what .. ": Fahrzeugknopf E sichtbar")
			showAllCards(what .. " (alle Karten + Fahrzeugknöpfe)")
		end
		local m = g:Mark()
		if useWorld then
			Hit.ClickWorld(T, g, p, worldPart(car, step.point), { label = what .. ": Weltklick" })
		else
			click(vehicleButton("E"), what .. ": Fahrzeugknopf E")
		end
		local c = g:Last(p, "challenge", m)
		if not T.check(c ~= nil, what .. ": QTE startet (Toasts: " .. table.concat(g:Toasts(p, m), " | ") .. ")") then
			return false
		end
		g:Advance(0.1)
		checkTutorialHidden(what .. " (QTE)")
		checkOcclusion(what .. " (QTE)")
		local stop = buttonText(GARAGE_GUI, "STOPP", true)
		g:AdvanceTo(c.startAt + c.center * c.period)
		m = g:Mark()
		Hit.Click(T, g, p, stop, { label = what .. ": QTE „STOPP“" })
		if not T.check(g:HasToast(p, "Arbeit läuft", m), what .. ": Treffer (Toasts: " .. table.concat(g:Toasts(p, m), " | ") .. ")") then
			return false
		end
		g:AdvanceTo(job(jobId).workUntil + 0.6)
		return true
	end

	local function playJob(kind, useWorld)
		local def
		for _, d in ipairs(C.Jobs) do
			if d.id == kind then
				def = d
			end
		end
		local what = def.name
		if not openReception() then
			return false
		end
		checkOcclusion(what .. ": Tablet")
		-- Auftrag dieser Art im Tablet annehmen (Karte mit Überschrift „<Auftrag> · <Auto>“)
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
			return false
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
			return false
		end
		closeTablet()
		checkOcclusion(what .. ": HUD")
		-- Diagnose
		local diag = scan(j.id, what .. " Diagnose")
		if not diag then
			return false
		end
		click(buttonText(GARAGE_GUI, def.answers[def.cause], true), what .. ": Diagnose-Antwort")
		g:Advance(0.4)
		if not T.eq(job(j.id).phase, "repair", what .. ": Phase repair") then
			return false
		end
		local close = buttonText(GARAGE_GUI, "Schließen", true)
		if close then
			click(close, what .. ": Dialog schließen")
		end
		-- Reparatur
		for i = 1, #def.steps do
			if not repairStep(j.id, i, useWorld, kind == "oil" and i == 1) then
				return false
			end
		end
		-- Endkontrolle: Haube zu, Bühne unten, OBD
		ensure(j.id, "hood", false)
		ensure(j.id, "lifted", false)
		scan(j.id, what .. " Endkontrolle")
		if not T.eq(job(j.id) and job(j.id).phase, "invoice", what .. ": Phase invoice") then
			return false
		end
		click(buttonText(GARAGE_GUI, "Schließen", true), what .. ": Endkontrolle schließen")
		-- Abrechnen am Empfang im Tablet
		local money = g:Data(p).money
		if not openReception() then
			return false
		end
		local settle = visibleIn(pg:FindFirstChild(GARAGE_GUI), function(x)
			if not (x:IsA("GuiButton") and x.Text == "Abrechnen") then
				return false
			end
			for _, s in ipairs(x.Parent:GetChildren()) do
				if s:IsA("TextLabel") and s.Text:find(def.name, 1, true) and s.Text:find("Bühne " .. j.bay, 1, true) then
					return true
				end
			end
			return false
		end)
		local m = g:Mark()
		click(settle, what .. ": „Abrechnen“")
		local receipt = g:Last(p, "receipt", m)
		T.check(receipt ~= nil, what .. ": Quittung")
		T.check(job(j.id) == nil, what .. ": Auftrag abgerechnet")
		T.check(g:Data(p).money > money, what .. ": Geld gestiegen (" .. tostring(money) .. " -> " .. tostring(g:Data(p).money) .. ")")
		checkOcclusion(what .. ": Quittung")
		click(buttonText(GARAGE_GUI, "Weiter", true), what .. ": Quittung „Weiter“")
		if hasText(GARAGE_GUI, "/ ULTIMATE CAR GAME") then
			closeTablet()
		end
		return receipt ~= nil
	end

	local okCheck = playJob("inspection", true)
	T.check(okCheck, "Fahrzeug-Check komplett")
	local okOil = playJob("oil", false)
	T.check(okOil, "Ölwechsel komplett")
	local v = Tut.View()
	T.check(v ~= nil and (v.step or 0) >= 8, "Tutorial bis nach dem Abrechnen weiter (Schritt " .. tostring(v and v.step) .. ")")
	T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
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
	table.insert(cases, { string.format("Studio-Spiel %dx%d: Lobby -> Open World, Startwahl Werkstatt, Tutorial, Fahrzeug-Check und Ölwechsel per Klick", vp[1], vp[2]), function(T, H)
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
return cases
