-- OBD-Tester „UCG-Tester 3000“ (GarageClient, Overlay der ScreenGui UltimateCarGame) und Werkzeugleiste mit festem
-- Slot „Hand“: Seiten aus Ereignissen (auch erfundenen), Tasten senden die richtigen 2.4.0-Aktionen über Command,
-- Treffertest (tests/lib/gui_hit.lua) in 6 Bildschirmgrößen, Tasten ≥ 44 px, Taste 1 = Hand, 2–6 = Leiste,
-- MiniClient-Optionen getState/onEvent und Weitergabe des Server-Ereignisses "call".
local VIEWPORTS = {
	{ 390, 844 },
	{ 844, 390 },
	{ 1100, 600 },
	{ 1280, 650 },
	{ 1366, 768 },
	{ 1920, 1080 },
}
local GUI = "UltimateCarGame"
local KEYS = { "codes", "values", "finding", "verify", "close" }

local function sent(g)
	return g:Remote("Command").__data.sentToServer
end

-- Letzte Client-Aktion `action` seit Index `since`
local function lastSent(g, action, since)
	local list = sent(g)
	for i = #list, (since or 0) + 1, -1 do
		if list[i][1] == action then
			return list[i][2]
		end
	end
	return nil
end

local function setup(H, vp, id)
	local g = H.Garage({ viewport = vp and H.Mock.Vector2.new(vp[1], vp[2]) or nil })
	local p = g:Join(id or 7001)
	g:Advance(0.5)
	g:StartClient(p)
	g:Advance(1.5)
	-- Neues Profil: Tablet zu, dann die Startwahl (StartUI) erledigen, sonst liegt ihr Hintergrund über dem HUD
	local x = g:FindGui(p, function(o)
		return o:IsA("TextButton") and o.Text == "×"
	end)
	if x then
		g:Click(x)
		g:Advance(0.6)
	end
	local choice = g:FindGui(p, function(o)
		return o.Name == "Choice_werkstatt"
	end)
	if choice then
		g:Click(choice)
		g:Advance(1)
	end
	return g, p
end

-- Kopie des letzten state ohne Instanzen tief zu kopieren (data tief, visuals flach)
local function copyState(H, s)
	local out = {}
	for k, v in pairs(s) do
		out[k] = v
	end
	out.data = H.Copy(s.data)
	out.visuals = {}
	for id, v in pairs(s.visuals or {}) do
		out.visuals[id] = v
	end
	return out
end

local function tester(p)
	local gui = p.PlayerGui:FindFirstChild(GUI)
	local overlay = gui and gui:FindFirstChild("InteractionOverlay")
	return overlay and overlay:FindFirstChild("ObdTester"), overlay
end

local function find(root, name)
	return root and root:FindFirstChild(name, true)
end

local function closeTablet(g, p)
	local Hit = nil
	local x = g:FindGui(p, function(o)
		return o:IsA("TextButton") and o.Text == "×"
	end)
	if x then
		g:Click(x)
		g:Advance(0.3)
	end
	return Hit
end

local cases = {}

for _, vp in ipairs(VIEWPORTS) do
	table.insert(cases, { string.format("OBD-Tester: Seiten, Aktionen und Treffertest [%dx%d]", vp[1], vp[2]), function(T0, H)
		local label = string.format("[%dx%d] ", vp[1], vp[2])
		local T = {
			check = function(c, m)
				return T0.check(c, label .. tostring(m))
			end,
			eq = function(a, e, m)
				return T0.check(a == e, label .. tostring(m) .. " – erwartet " .. tostring(e) .. ", erhalten " .. tostring(a))
			end,
		}
		local Hit = H.Load("tests/lib/gui_hit.lua")
		local g, p = setup(H, vp)
		closeTablet(g, p)
		local root, overlay = tester(p)
		if not T.check(root ~= nil, "ObdTester im Overlay") then
			return
		end
		T.check(not root.Visible and not overlay.Visible, "Tester anfangs zu")

		-- Erfundener Befund mit Antworten: Seite „Befund“, Codes, Messwerte
		g:FireClient(p, "diagnose", {
			job = "job_fake", car = "Testwagen", phase = "diagnose", kind = "ignition",
			report = "P0302: Zündaussetzer\nKompression: OK\nFehlerspeicher: 1 Eintrag",
			answers = { "Antwort Eins", "Antwort Zwei", "Antwort Drei" },
			codes = { { code = "P0302", text = "Zylinder 2: Zündaussetzer erkannt" } },
			live = { { name = "Motordrehzahl", value = "820 1/min" }, { name = "Zündaussetzer Zylinder 2", value = "47 pro Minute" } },
		})
		g:Advance(0.3)
		T.check(overlay.Visible and Hit.Visible(root), "Tester sichtbar")
		T.check(g:FindGui(p, "Fahrzeugdiagnose") ~= nil, "Titel „Fahrzeugdiagnose · OBD“")
		T.check(g:FindGui(p, "UCG-Tester 3000") ~= nil, "Marke „UCG-Tester 3000“")
		T.check(find(root, "TesterPage").Text:find("BEFUND", 1, true) ~= nil, "Startseite Befund bei offener Diagnose")
		T.eq(find(root, "TesterTitle").Font, Enum.Font.Code, "Monospace-Schrift im Bildschirm")
		for _, led in ipairs({ "Led_power", "Led_link", "Led_fault" }) do
			T.check(find(root, led) ~= nil, "LED " .. led)
		end
		-- Alle Gerätetasten: sichtbar, ≥ 44 px, im Bild, treffbar
		for _, key in ipairs(KEYS) do
			local b = find(root, "TesterBtn_" .. key)
			if T.check(b ~= nil and Hit.Visible(b), "Taste " .. key .. " sichtbar") then
				local x, y, w, h = Hit.Rect(p, b)
				T.check(w >= 44 and h >= 44, string.format("Taste %s ≥ 44 px (%dx%d)", key, w, h))
				T.check(x >= 0 and y >= 0 and x + w <= vp[1] and y + h <= vp[2], string.format("Taste %s im Bild (%d,%d %dx%d)", key, x, y, w, h))
			end
		end
		local rx, ry, rw, rh = Hit.Rect(p, root)
		T.check(rx >= -1 and ry >= -1 and rx + rw <= vp[1] + 1 and ry + rh <= vp[2] + 1, string.format("Gerät passt ins Bild (%d,%d %dx%d)", rx, ry, rw, rh))
		-- Antworttasten nach UIScale ≥ 44 px hoch (Handy quer)
		for i = 1, 3 do
			local a = find(root, "Answer_" .. i)
			if T.check(a ~= nil, "Answer_" .. i) then
				local _, _, aw, ah = Hit.Rect(p, a)
				T.check(ah >= 44 - 0.01, string.format("Answer_%d ≥ 44 px (%.1f × %.1f)", i, aw, ah))
			end
		end
		-- Antwort 2 per Treffertest -> diagnose {id, choice = 2}
		local answer = find(root, "Answer_2")
		T.eq(answer and answer.Text, "Antwort Zwei", "Antworttext exakt")
		local m = #sent(g)
		if Hit.Click(T, g, p, answer, { label = "Antwort 2" }) then
			g:Advance(0.2)
			local a = lastSent(g, "diagnose", m)
			T.check(a ~= nil and a.id == "job_fake" and a.choice == 2, "diagnose {id=job_fake, choice=2} gesendet")
		end
		-- Fehlerspeicher
		Hit.Click(T, g, p, find(root, "TesterBtn_codes"), { label = "Taste Fehlerspeicher" })
		g:Advance(0.2)
		T.check(find(root, "TesterPage").Text:find("FEHLERSPEICHER", 1, true) ~= nil, "Seite Fehlerspeicher")
		local code1 = find(root, "Code1")
		T.check(code1 and code1.Text:find("P0302", 1, true) and code1.Text:find("Zündaussetzer", 1, true), "Code P0302 mit Text")
		T.check(find(root, "CodesHead") and find(root, "CodesHead").Text:find("1 Fehler", 1, true), "Kopf „1 Fehler gespeichert“")
		T.check(find(root, "ApprovalHint") == nil, "kein Freigabe-Hinweis ohne Phase approval")
		-- Messwerte
		Hit.Click(T, g, p, find(root, "TesterBtn_values"), { label = "Taste Messwerte" })
		g:Advance(0.2)
		T.check(find(root, "TesterPage").Text:find("MESSWERTE", 1, true) ~= nil, "Seite Messwerte")
		T.check(find(root, "Value1") and find(root, "Value1").Text:find("Motordrehzahl", 1, true), "Live-Wert Motordrehzahl")
		T.check(find(root, "Value2") and find(root, "Value2").Text:find("47 pro Minute", 1, true), "Abweichender Wert")
		-- Befund
		Hit.Click(T, g, p, find(root, "TesterBtn_finding"), { label = "Taste Befund" })
		g:Advance(0.2)
		T.check(find(root, "Answer_1") ~= nil and find(root, "Answer_3") ~= nil, "Befund: drei Antworten")
		-- Endkontrolle ohne passenden Auftrag: Prüfliste, kein scan
		m = #sent(g)
		Hit.Click(T, g, p, find(root, "TesterBtn_verify"), { label = "Taste Endkontrolle" })
		g:Advance(1.5)
		T.check(find(root, "TesterPage").Text:find("ENDKONTROLLE", 1, true) ~= nil, "Seite Endkontrolle")
		T.check(find(root, "Check1") ~= nil and find(root, "Check4") ~= nil, "Prüfliste mit vier Punkten")
		T.check(lastSent(g, "scan", m) == nil, "Endkontrolle ohne fertigen Auftrag sendet keinen scan")
		-- Schließen: nur lokal (dismiss)
		m = #sent(g)
		Hit.Click(T, g, p, find(root, "TesterBtn_close"), { label = "Taste Schließen" })
		g:Advance(0.2)
		T.check(not overlay.Visible and not root.Visible, "Schließen blendet Tester und Overlay aus")
		T.eq(#sent(g), m, "Schließen sendet nichts")

		-- Fahrzeug-Check mit Befund (Phase approval): Codes + hervorgehobener Hinweis + Anruf
		g:FireClient(p, "diagnose", {
			job = "job_fake2", car = "Testwagen", phase = "approval", kind = "inspection", answers = {},
			report = "Druck: 1,1 bar", codes = { { code = "C0750", text = "Reifendruck vorne links: 1,1 bar" } },
			finding = "tire", findingName = "Reifen erneuern", customer = "Frau Becker", message = "1 Fehler gespeichert",
		})
		g:Advance(0.3)
		T.check(find(root, "TesterPage").Text:find("FEHLERSPEICHER", 1, true) ~= nil, "approval: Startseite Fehlerspeicher")
		local hint = find(root, "ApprovalHint")
		T.check(hint ~= nil and Hit.Visible(hint), "Freigabe-Hinweis sichtbar")
		T.check(hint and hint.Text.Text == "Kunde muss die Reparatur freigeben – ruf ihn mit dem Handy an (P)", "Hinweistext")
		T.check(find(root, "ApprovalWho") and find(root, "ApprovalWho").Text:find("Frau Becker", 1, true), "Kunde genannt")
		T.check(find(root, "Led_fault").BackgroundColor3 ~= find(root, "Led_power").Parent.BackgroundColor3, "Fehler-LED an")
		local callBtn = find(root, "CallCustomer")
		if T.check(callBtn ~= nil, "CallCustomer") then
			local _, _, cw, chh = Hit.Rect(p, callBtn)
			T.check(chh >= 44 - 0.01, string.format("„Kunden anrufen“ ≥ 44 px (%.1f × %.1f)", cw, chh))
		end
		m = #sent(g)
		local MiniClient = g:ClientModule(p, "Mini.MiniClient")
		if Hit.Click(T, g, p, callBtn, { label = "Kunden anrufen" }) then
			g:Advance(0.3)
			local c = lastSent(g, "call", m)
			T.check((c ~= nil and c.id == "job_fake2") or type(MiniClient.OpenPhone) == "function", "call {id} gesendet oder Handy geöffnet")
			T.check(not overlay.Visible, "Tester schließt für den Anruf")
		end

		-- Scan-Animation (erfundenes scan-Ereignis am DiagnosticPoint eines echten Autos)
		local jobs = g:Data(p).offers
		local station = g:Station(p, "workshop")
		g:Teleport(p, station, Vector3.new(0, 0, 3))
		g:Advance(0.2)
		local offer = jobs[1]
		g:Send(p, "accept", { id = offer.id })
		g:Advance(0.3)
		local job = g:Data(p).jobs[1]
		local car = job and g:Car(p, job.id)
		if T.check(car ~= nil and car:FindFirstChild("DiagnosticPoint") ~= nil, "Auto mit OBD-Anschluss") then
			g:FireClient(p, "scan", { tool = "scanner", point = car.DiagnosticPoint, duration = 2.5 })
			g:Advance(0.2)
			T.check(root.Visible and find(root, "TesterPage").Text:find("VERBINDUNG", 1, true) ~= nil, "Scan: Seite Verbindung")
			T.check(find(root, "ScanTrack") ~= nil, "Fortschrittsbalken")
			g:Advance(1.2)
			local fill = find(root, "ScanFill")
			T.check(fill and fill.Size.X.Scale > 0.2 and fill.Size.X.Scale < 1, "Balken läuft (" .. tostring(fill and fill.Size.X.Scale) .. ")")
			T.check(find(root, "ScanStep1").Text:find("✓", 1, true) ~= nil, "erster Schritt abgehakt")
			-- Seitentasten sind während des Scans gesperrt
			Hit.Click(T, g, p, find(root, "TesterBtn_values"), { label = "Messwerte während Scan" })
			g:Advance(0.1)
			T.check(find(root, "TesterPage").Text:find("VERBINDUNG", 1, true) ~= nil, "bleibt beim Scan")
			-- Ohne Antwort schließt der Tester von selbst (nie festhängen)
			g:Advance(6)
			T.check(not root.Visible and not overlay.Visible, "Scan ohne Ergebnis: Tester schließt nach Zeitlimit")
			T.check(g:FindGui(p, "Keine Antwort vom Fahrzeug") ~= nil, "Hinweis-Toast")
		end
		-- Hand-Slot: sichtbar, treffbar, erster Platz
		local hand = g:FindGui(p, function(o)
			return o.Name == "ToolSlotHand"
		end)
		if T.check(hand ~= nil, "Slot Hand sichtbar") then
			local hx, _, hw, hh = Hit.Rect(p, hand)
			T.check(find(hand, "HandLabel") ~= nil and find(hand, "HandLabel").Text == "Hand", "Slot Hand mit Wort „Hand“")
			if vp[1] < 900 then
				T.check(hh >= 44 - 0.01, string.format("Slot Hand ≥ 44 px auf schmalem Schirm (%.1f × %.1f)", hw, hh))
			end
			for i = 1, 5 do
				local s = g:FindGui(p, function(o)
					return o.Name == "ToolSlot" .. i
				end)
				T.check(s ~= nil and Hit.Rect(p, s) > hx, "ToolSlot" .. i .. " rechts von der Hand")
			end
			m = #sent(g)
			if Hit.Click(T, g, p, hand, { label = "Slot Hand" }) then
				g:Advance(0.2)
				local a = lastSent(g, "tool", m)
				T.check(a ~= nil and a.id == "hand", "tool {id=hand}")
			end
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end })
end

table.insert(cases, { "OBD-Tester im echten Ablauf: Scan, Befund-Antwort, Endkontrolle per Taste", function(T, H)
	local Hit = H.Load("tests/lib/gui_hit.lua")
	local Flow = H.Load("tests/lib/garage_flow.lua")
	local g, p = setup(H, { 1280, 650 }, 7101)
	closeTablet(g, p)
	local C = g:Config()
	local root, overlay = tester(p)
	local j = Flow.AcceptKind(T, g, p, "oil")
	if not T.check(j ~= nil, "Ölwechsel angenommen") then
		return
	end
	g:Advance(0.3)
	-- echter Scan: Verbindungsbild, dann Befund mit den drei Antworten
	local car = g:Car(p, j.id)
	g:Send(p, "tool", { id = "scanner" })
	g:Teleport(p, car.DiagnosticPoint, Vector3.new(0, 0, 1.5))
	g:Advance(0.3)
	g:Send(p, "scan", { id = j.id })
	g:Advance(0.3)
	T.check(root.Visible and find(root, "TesterPage").Text:find("VERBINDUNG", 1, true) ~= nil, "Verbindungsbild während des Scans")
	g:Advance(2.6)
	T.check(root.Visible and find(root, "TesterPage").Text:find("BEFUND", 1, true) ~= nil, "Befund nach dem Scan")
	local def = C.JobById["oil"]
	local right
	for i = 1, 3 do
		local b = find(root, "Answer_" .. i)
		if b and b.Text == def.answers[def.cause] then
			right = b
		end
	end
	if Hit.Click(T, g, p, right, { label = "richtige Antwort" }) then
		g:Advance(0.4)
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "Phase repair nach der Antwort")
		T.check(not overlay.Visible, "Tester nach diagnosisDone zu")
	end
	-- Reparatur über den Server, dann Endkontrolle über die Tester-Taste
	for i = 1, #def.steps do
		if not Flow.RepairStep(T, g, p, j.id, i) then
			return
		end
	end
	local cur = Flow.Job(g, p, j.id)
	T.eq(cur and cur.phase, "verify", "Phase verify")
	-- Haube zu / Bühne runter, dann OBD-Tester in die Hand
	local v = g:State(p).visuals[j.id]
	if v and v.hood then
		g:Teleport(p, car.HoodPoint, Vector3.new(0, 0, 1.5))
		g:Advance(0.2)
		g:Send(p, "hood", { id = j.id })
		g:Advance(0.3)
	end
	v = g:State(p).visuals[j.id]
	if v and v.lifted then
		local plot = g:Plot(p)
		g:Teleport(p, plot.Bays:FindFirstChild("Bay_" .. cur.bay).LiftControl, Vector3.new(0, 0, 1.5))
		g:Advance(0.2)
		g:Send(p, "lift", { id = j.id })
		g:Advance(3)
	end
	g:Send(p, "tool", { id = "scanner" })
	g:Teleport(p, car.DiagnosticPoint, Vector3.new(0, 0, 1.5))
	g:Advance(0.3)
	-- Tester mit dem aktuellen Bericht öffnen (wie nach einem Scan) und „Endkontrolle“ drücken
	g:FireClient(p, "diagnose", { job = j.id, car = "Test", report = def.report, answers = {}, phase = "verify", kind = "oil", codes = {} })
	g:Advance(0.2)
	local m = #sent(g)
	Hit.Click(T, g, p, find(root, "TesterBtn_verify"), { label = "Taste Endkontrolle" })
	g:Advance(0.3)
	T.check(find(root, "VerifyHead") and find(root, "VerifyHead").Text:find("Prüfe", 1, true), "Prüfliste animiert")
	g:Advance(1.5)
	local s = lastSent(g, "scan", m)
	T.check(s ~= nil and s.id == j.id, "Endkontrolle sendet den bestehenden scan")
	g:Advance(3)
	T.eq(Flow.Job(g, p, j.id) and Flow.Job(g, p, j.id).phase, "invoice", "Phase invoice")
	T.check(root.Visible and find(root, "VerifyHead") and find(root, "VerifyHead").Text:find("bestanden", 1, true), "Tester zeigt „Endkontrolle bestanden“")
	Hit.Click(T, g, p, find(root, "TesterBtn_close"), { label = "Schließen" })
	g:Advance(0.2)
	T.check(not overlay.Visible, "geschlossen")
	T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
end })

table.insert(cases, { "Werkzeugleiste: Taste 1 = Hand, Tasten 2–6 = Leistenplätze, Hervorhebung", function(T, H)
	local g, p = setup(H, nil, 7201)
	closeTablet(g, p)
	local loadout = g:Data(p).loadout
	local keys = { Enum.KeyCode.One, Enum.KeyCode.Two, Enum.KeyCode.Three, Enum.KeyCode.Four, Enum.KeyCode.Five, Enum.KeyCode.Six }
	for i, key in ipairs(keys) do
		local m = #sent(g)
		T.eq(g:Key(p, key), true, "Taste " .. i .. " wird geschluckt")
		g:Advance(0.3)
		local a = lastSent(g, "tool", m)
		local want = i == 1 and "hand" or loadout[i - 1]
		T.check(a ~= nil and a.id == want, "Taste " .. i .. " -> tool " .. tostring(want) .. " (gesendet " .. tostring(a and a.id) .. ")")
	end
	local gui = p.PlayerGui[GUI]
	local hand = gui:FindFirstChild("ToolSlotHand", true)
	T.check(hand ~= nil and hand:FindFirstChild("HandIcon") ~= nil, "Hand-Symbol aus Frames")
	for i = 1, 5 do
		local b = gui:FindFirstChild("ToolSlot" .. i, true)
		T.check(b ~= nil and b.Text:sub(1, #tostring(i + 1)) == tostring(i + 1), "ToolSlot" .. i .. " zeigt Taste " .. (i + 1) .. " (" .. tostring(b and b.Text) .. ")")
	end
	-- Hervorhebung folgt state.tool
	g:Key(p, Enum.KeyCode.Two)
	g:Advance(0.6)
	local green = Color3.fromRGB(50, 192, 137)
	if g:State(p).tool == loadout[1] then
		T.check(gui:FindFirstChild("ToolSlot1", true).BackgroundColor3 == green, "Platz 1 hervorgehoben")
		T.check(hand.BackgroundColor3 ~= green, "Hand nicht hervorgehoben")
	end
	g:Key(p, Enum.KeyCode.One)
	g:Advance(0.6)
	if g:State(p).tool == "hand" then
		T.check(hand.BackgroundColor3 == green, "Hand hervorgehoben")
		T.check(gui:FindFirstChild("ToolSlot1", true).BackgroundColor3 ~= green, "Platz 1 nicht mehr hervorgehoben")
	end
	-- Ohne Hand-Unterstützung des Servers (alter state.tool): Hand-Slot hebt sich bei fremdem Werkzeug nicht hervor
	local fake = copyState(H, g:State(p))
	fake.tool = loadout[2]
	g:FireClient(p, "state", fake)
	T.check(hand.BackgroundColor3 ~= green, "fremdes Werkzeug: Hand aus")
	-- Zielzeile über der Leiste
	local line = gui:FindFirstChild("ObjectiveLine", true)
	T.check(line ~= nil and line.Text ~= "", "Zielzeile gefüllt: " .. tostring(line and line.Text))
	T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
end })

table.insert(cases, { "Zielzeile: nächster Handgriff aus dem Zustand (Bühne, Haube, Werkzeug)", function(T, H)
	local Flow = H.Load("tests/lib/garage_flow.lua")
	local g, p = setup(H, { 1280, 650 }, 7301)
	closeTablet(g, p)
	local j = Flow.AcceptKind(T, g, p, "oil")
	if not j then
		return
	end
	local gui = p.PlayerGui[GUI]
	local line = gui:FindFirstChild("ObjectiveLine", true)
	g:Send(p, "select", { id = j.id })
	g:Send(p, "tool", { id = "hand" })
	g:Advance(0.6)
	T.check(line.Text:find("→", 1, true) ~= nil, "Hinweiszeile mit Pfeil: " .. line.Text)
	T.check(line.Text:find("OBD", 1, true) ~= nil, "Diagnose: OBD-Tester-Hinweis: " .. line.Text)
	-- Erfundener Zustand: Reparatur, Bühne unten, Schritt 1 braucht die Bühne oben
	local s = copyState(H, g:State(p))
	for _, x in ipairs(s.data.jobs) do
		if x.id == j.id then
			x.phase = "repair"
			x.step = 1
		end
	end
	s.visuals[j.id] = { lifted = false, hood = false, moving = false }
	s.selected = j.id
	g:FireClient(p, "state", s)
	-- 3.0: E stellt Bühne, Haube und Werkzeug selbst: keine F/H/Taste-N-Anweisungen mehr
	T.check(line.Text:find("E drücken", 1, true) ~= nil and line.Text:find("automatisch", 1, true) ~= nil, "Bühne unten: trotzdem nur E: " .. line.Text)
	T.check(line.Text:find("(F)", 1, true) == nil and line.Text:find("(H)", 1, true) == nil, "kein F/H: " .. line.Text)
	s.visuals[j.id] = { lifted = true, hood = false, moving = false }
	s.tool = "hand"
	g:FireClient(p, "state", s)
	T.check(line.Text:find("E drücken", 1, true) ~= nil and line.Text:find("Taste", 1, true) == nil, "freie Hand: nur E, keine Taste: " .. line.Text)
	-- Werkzeug fehlt in der Leiste: das kann E nicht lösen -> Werkzeugkiste
	local saved = s.data.loadout
	s.data.loadout = { "scanner", "ratchet", "tire", "meter", "torque" }
	g:FireClient(p, "state", s)
	T.check(line.Text:find("Ölservice", 1, true) ~= nil and line.Text:find("Werkzeugkiste", 1, true) ~= nil, "Werkzeug nicht in der Leiste: " .. line.Text)
	s.data.loadout = saved
	s.tool = "oil"
	g:FireClient(p, "state", s)
	T.check(line.Text:find("E drücken", 1, true) ~= nil, "dann E: " .. line.Text)
	-- Endkontrolle mit Bühne oben und Haube offen: trotzdem nur E am OBD-Anschluss
	for _, x in ipairs(s.data.jobs) do
		if x.id == j.id then
			x.phase = "verify"
		end
	end
	s.visuals[j.id] = { lifted = true, hood = true, moving = false }
	g:FireClient(p, "state", s)
	T.check(line.Text:find("Endkontrolle: am OBD-Anschluss E drücken", 1, true) ~= nil, "verify: nur E: " .. line.Text)
	for _, x in ipairs(s.data.jobs) do
		if x.id == j.id then
			x.phase = "approval"
		end
	end
	g:FireClient(p, "state", s)
	T.check(line.Text:find("Handy", 1, true) ~= nil, "approval: Handy: " .. line.Text)
	T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
end })

table.insert(cases, { "MiniClient.Start: getState, onEvent und Weitergabe von \"call\"", function(T, H)
	local g = H.Garage({})
	local p = g:Join(7401)
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	-- MiniClient.Start abfangen, bevor GarageClient startet
	local captured
	g:InClient(p, function()
		local M = require(p.PlayerScripts.Mini.MiniClient)
		local original = M.Start
		M.Start = function(o)
			captured = o
			return original(o)
		end
	end)
	local client = g.env.clients[p]
	for _, x in ipairs(p.PlayerScripts:GetDescendants()) do
		if x.ClassName == "LocalScript" and not x.Disabled then
			H.Mock.RunScript(g.env, x, client.ctx)
		end
	end
	g:Advance(2)
	if not T.check(type(captured) == "table", "MiniClient.Start mit Optionen aufgerufen") then
		return
	end
	T.check(type(captured.getState) == "function" and type(captured.onEvent) == "function", "getState und onEvent vorhanden")
	local s = g:InClient(p, function()
		return captured.getState()
	end)
	T.check(type(s) == "table" and type(s.data) == "table" and type(s.data.jobs) == "table", "getState liefert den 2.4.0-Zustand")
	local got = {}
	g:InClient(p, function()
		captured.onEvent(function(kind, value)
			table.insert(got, { kind, value })
		end)
		captured.onEvent(function()
			error("Abonnent kaputt")
		end)
	end)
	g:FireClient(p, "call", { job = "job_1", state = "ringing", customer = "Frau Becker" })
	g:Advance(0.2)
	T.eq(#got, 1, "ein call-Ereignis weitergereicht")
	T.check(got[1] and got[1][1] == "call" and got[1][2].customer == "Frau Becker", "Art und Daten")
	T.eq(#g:Errors(), 0, "kaputter Abonnent bricht nichts (pcall): " .. g:ErrorText())
end })

return cases
