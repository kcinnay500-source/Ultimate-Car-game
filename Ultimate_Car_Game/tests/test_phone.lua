-- Handy (PhoneUI + PhoneService): Öffnen/Schließen mit Taste P und dem Handy-Knopf, Apps aus einem gefälschten
-- 2.4.0-Zustand/Minispiel-Snapshot, App „Kunden“ (nur Freigabe-Aufträge, Anrufen -> phone_call {id}),
-- Anruf-Bildschirm (ringing/answer/ended, Zeitüberschreitung, Server-Toast als Absage), Ausblenden bei QTE/Diagnose,
-- Tablet, Panel und Fahrt, Layout an den sechs Studio-Viewports (Treffertest tests/lib/gui_hit.lua, nie über der
-- HUD-Leiste oder den Fahrzeugknöpfen) und die Server-Prüfung von phone_call mit einer Stub-api.
local NOW = 1760000000

local VIEWPORTS = {
	{ 1280, 650 },
	{ 1100, 600 },
	{ 1366, 768 },
	{ 1920, 1080 },
	{ 844, 390 },
	{ 390, 844 },
}

local FORBIDDEN = { amount = true, cost = true, credits = true, reward = true, money = true, price = true, xp = true, accepted = true }

local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
			T.check(not FORBIDDEN[k], action .. ": Client sendet verbotenes Feld " .. tostring(k))
		end
		T.check(n <= 10, action .. ": höchstens 10 Felder")
		table.insert(r.sent, { action = action, payload = payload })
		return #r.sent
	end
	r.SendRaw = r.Send
	function r.Last(action)
		for i = #r.sent, 1, -1 do
			if r.sent[i].action == action then
				return r.sent[i].payload
			end
		end
		return nil
	end
	function r.Count(action)
		local n = 0
		for _, s in ipairs(r.sent) do
			if s.action == action then
				n += 1
			end
		end
		return n
	end
	return r
end

local function fakeState(g)
	local C = g:Config()
	local car = C.Cars[1].id
	return {
		revision = 1,
		data = {
			jobs = {
				{ id = "job_1", kind = "inspection", carId = car, bay = 1, phase = "approval", step = 1, finding = "brakes" },
				{ id = "job_2", kind = "oil", carId = car, bay = 2, phase = "repair", step = 2 },
				{ id = "job_3", kind = "tire", carId = car, bay = 3, phase = "verify", step = 4 },
			},
			parkedJobs = { { id = "job_4", kind = "battery", carId = car } },
		},
	}
end

local function fakeSnapshot()
	return {
		mode = "openworld", credits = 12345, level = 7,
		prestige = { rank = 1, title = "Meisterschrauber I" },
		tycoon = { run = { cash = 4321 } },
		meta = { single = false, passive = false, beginner = true },
	}
end

-- Mock-Client ohne GarageClient/MiniClient; das Handy bekommt einen eigenen ctx
local function setup(H, T, opts)
	opts = opts or {}
	local g = H.Garage({ placeKind = "openworld", startTime = NOW, viewport = opts.viewport and H.Mock.Vector2.new(opts.viewport[1], opts.viewport[2]) or nil })
	local p = g:Join(1301, { name = "Handy" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1)
	local rec = recorder(T)
	local flags = { blocked = false, tablet = false, panel = false, opened = {} }
	local S = { g = g, p = p, rec = rec, flags = flags, state = fakeState(g), snap = fakeSnapshot(), hooks = {} }
	S.Phone = g:ClientModule(p, "Mini.PhoneUI")
	g:InClient(p, function()
		S.Phone.Start({
			Remote = rec,
			IsBlocked = function()
				return flags.blocked
			end,
			IsTabletOpen = function()
				return flags.tablet
			end,
			IsPanelOpen = function()
				return flags.panel
			end,
			Open = function(tab)
				table.insert(flags.opened, tab)
				return true
			end,
			GetState = function()
				return S.state
			end,
			Snapshot = function()
				return S.snap
			end,
			OnEvent = function(fn)
				table.insert(S.hooks, fn)
			end,
		})
	end)
	g:Advance(0.5)
	S.gui = p.PlayerGui:FindFirstChild("Handy")
	S.Hit = H.Load("tests/lib/gui_hit.lua")
	return S
end

local function find(root, name)
	if not root then
		return nil
	end
	for _, x in ipairs(root:GetDescendants()) do
		if x.Name == name then
			return x
		end
	end
	return nil
end

local function visibleNamed(S, name)
	for _, x in ipairs(S.gui:GetDescendants()) do
		if x.Name == name and S.Hit.Visible(x) then
			return x
		end
	end
	return nil
end

local function textOf(root)
	local parts = {}
	for _, x in ipairs(root:GetDescendants()) do
		if x:IsA("TextLabel") or x:IsA("TextButton") then
			if x.Text ~= "" then
				table.insert(parts, x.Text)
			end
		end
	end
	return table.concat(parts, " | ")
end

local function click(T, S, obj, label)
	local ok = S.Hit.Click(T, S.g, S.p, obj, { label = label })
	S.g:Advance(0.3)
	return ok
end

local function phoneFrame(S)
	return S.gui and S.gui:FindFirstChild("Phone")
end

-- Bei Bedarf alle Hooks (GarageClient onEvent) mit einem "call"-Ereignis aufrufen
local function fireCall(S, value)
	S.g:InClient(S.p, function()
		for _, fn in ipairs(S.hooks) do
			fn("call", value)
		end
	end)
	S.g:Advance(0.3)
end

-- Rechtecke schneiden sich?
local function overlaps(ax, ay, aw, ah, bx, by, bw, bh)
	return ax < bx + bw and ax + aw > bx and ay < by + bh and ay + ah > by
end

---------------------------------------------------------------- Fälle
return {
	{ "Handy: Taste P und Handy-Knopf öffnen/schließen, Slide-Tween, Home mit sieben Apps (3.x: „Auto rufen“), Navigation", function(T, H)
		local S = setup(H, T)
		local g, p = S.g, S.p
		T.check(S.gui ~= nil, "ScreenGui „Handy“ angelegt")
		T.eq(S.gui.DisplayOrder, 19, "DisplayOrder 19 (unter dem 2.4.0-UI)")
		T.eq(S.gui.ResetOnSpawn, false, "ResetOnSpawn aus")
		local button = S.gui:FindFirstChild("PhoneButton")
		T.check(button ~= nil and S.Hit.Visible(button), "Handy-Knopf sichtbar")
		T.eq(S.Phone.IsOpen(), false, "anfangs zu")
		-- Taste P
		g:Key(p, Enum.KeyCode.P)
		g:Advance(0.5)
		T.eq(S.Phone.IsOpen(), true, "P öffnet")
		T.check(S.Phone.IsVisible(), "Handy sichtbar")
		T.eq(button.Visible, false, "Knopf weicht dem offenen Handy")
		-- wartet ein Kunde, öffnet sich gleich die Kunden-App
		T.eq(S.Phone.App(), "kunden", "Kunden-App zuerst, weil ein Kunde wartet")
		click(T, S, visibleNamed(S, "Back"), "Zurück")
		T.eq(S.Phone.App(), "home", "Zurück -> Home")
		for _, a in ipairs(S.Phone.Apps) do
			T.check(visibleNamed(S, "App_" .. a.key) ~= nil, "App " .. a.title .. " auf dem Home-Bildschirm")
		end
		local badge = find(visibleNamed(S, "App_kunden"), "Badge")
		T.check(badge ~= nil and badge.Visible, "Zähler am Kunden-Symbol")
		T.check(textOf(phoneFrame(S)):find("Kunden", 1, true) ~= nil, "Beschriftung Kunden")
		-- Statusleiste: Uhr aus Lighting.ClockTime
		g:InClient(p, function()
			game:GetService("Lighting").ClockTime = 9.5
		end)
		g:Advance(0.6)
		local expected = g:InClient(p, function()
			local t = game:GetService("Lighting").ClockTime % 24
			return string.format("%02d:%02d", math.floor(t), math.floor((t - math.floor(t)) * 60))
		end)
		T.eq(visibleNamed(S, "Clock").Text, expected, "Uhr aus Lighting.ClockTime")
		T.check(visibleNamed(S, "Signal") ~= nil and visibleNamed(S, "Battery") ~= nil, "Empfang und Akku in der Statusleiste")
		-- P schließt (Tween nach unten, dann unsichtbar)
		g:Key(p, Enum.KeyCode.P)
		g:Advance(0.5)
		T.eq(S.Phone.IsOpen(), false, "P schließt")
		T.eq(phoneFrame(S).Visible, false, "Handy nach dem Tween ausgeblendet")
		T.check(button.Visible, "Knopf wieder da")
		-- Knopf öffnet (Touch), Tween fährt von unten hoch
		click(T, S, button, "Handy-Knopf")
		local startY = phoneFrame(S).Position.Y.Offset
		g:Advance(0.5)
		T.eq(S.Phone.IsOpen(), true, "Knopf öffnet")
		T.check(phoneFrame(S).Position.Y.Offset < startY or startY < S.gui.AbsoluteSize.Y, "Handy fährt hoch")
		T.check(phoneFrame(S).Position.Y.Offset + phoneFrame(S).Size.Y.Offset <= S.gui.AbsoluteSize.Y, "Handy nach dem Tween im Bild")
		-- „Schließen“ in der Navigation
		click(T, S, visibleNamed(S, "NavClose"), "Schließen")
		g:Advance(0.4)
		T.eq(S.Phone.IsOpen(), false, "× schließt")
		-- P beim Tippen (verarbeitet) wirkt nicht
		g:InClient(p, function()
			S.Phone.Open({ app = "home" })
		end)
		g:Advance(0.4)
		click(T, S, visibleNamed(S, "NavHome"), "Home auf dem Home-Bildschirm")
		T.eq(S.Phone.IsOpen(), false, "Home auf Home schließt")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "Handy: Kunden-App zeigt nur Freigabe-Aufträge, Anrufen sendet phone_call {id}, Anruf-Bildschirm (ringing/answer/ended)", function(T, H)
		local S = setup(H, T)
		local g, p = S.g, S.p
		g:InClient(p, function()
			S.Phone.Open({ app = "kunden" })
		end)
		g:Advance(0.5)
		T.check(visibleNamed(S, "Customer_job_1") ~= nil, "Freigabe-Auftrag job_1 gelistet")
		T.eq(visibleNamed(S, "Customer_job_2"), nil, "Reparatur-Auftrag nicht gelistet")
		T.eq(visibleNamed(S, "Customer_job_3"), nil, "Endkontrolle nicht gelistet")
		local list = S.Phone.ApprovalJobs()
		T.eq(#list, 1, "ApprovalJobs: genau einer")
		local cardText = textOf(visibleNamed(S, "Customer_job_1"))
		T.check(cardText:find("Befund:", 1, true) ~= nil, "Befund steht in der Karte: " .. cardText)
		local R = g:Rules()
		local who = R.CustomerName(S.state.data.jobs[1])
		T.check(cardText:find(who, 1, true) ~= nil, "Kundenname " .. who .. " (Rules.CustomerName)")
		-- Anrufen
		click(T, S, visibleNamed(S, "Call_job_1"), "Anrufen")
		local sent = S.rec.Last("phone_call")
		T.check(sent ~= nil and sent.id == "job_1", "phone_call {id = job_1} gesendet")
		local n = 0
		for _ in pairs(sent or {}) do
			n += 1
		end
		T.eq(n, 1, "nur das Feld id")
		T.eq(S.Phone.App(), "call", "Anruf-Bildschirm")
		T.check(visibleNamed(S, "Avatar") ~= nil, "Avatar-Kreis")
		T.eq(visibleNamed(S, "CallName").Text, who, "Name im Anruf")
		T.check(visibleNamed(S, "CallStatus").Text:find("Wählt", 1, true) ~= nil, "Status „Wählt …“")
		-- Doppeltipp sendet nicht erneut
		g:InClient(p, function()
			S.Phone.Call("job_1")
		end)
		T.eq(S.rec.Count("phone_call"), 1, "kein zweiter Anruf, solange gewählt wird")
		-- Server: es klingelt (über den GarageClient-Hook)
		fireCall(S, { job = "job_1", state = "ringing", customer = who, car = "Testauto", findingName = "Bremsen" })
		T.check(visibleNamed(S, "CallStatus").Text:find("Es klingelt", 1, true) ~= nil, "„Es klingelt …“: " .. visibleNamed(S, "CallStatus").Text)
		T.check(visibleNamed(S, "Pulse") ~= nil, "Klingel-Animation (Ring)")
		local s1 = visibleNamed(S, "Pulse").Size.X.Offset
		g:Advance(0.31)
		T.check(visibleNamed(S, "Pulse").Size.X.Offset ~= s1, "Ring pulsiert")
		T.eq(visibleNamed(S, "Bubble"), nil, "noch keine Antwort")
		-- Antwort als Sprechblase
		fireCall(S, { job = "job_1", state = "answer", accepted = true, text = "Ja, bitte gleich mitmachen. Danke!", result = "Freigegeben: Bremsen", customer = who })
		local bubble = visibleNamed(S, "Bubble")
		T.check(bubble ~= nil, "Sprechblase sichtbar")
		T.eq(find(bubble, "Text").Text, "Ja, bitte gleich mitmachen. Danke!", "Antwort des Kunden")
		T.eq(visibleNamed(S, "CallStatus").Text, "Verbunden", "Status verbunden")
		T.eq(visibleNamed(S, "CallResult").Text, "Freigegeben: Bremsen", "Ergebnis")
		T.eq(visibleNamed(S, "Pulse"), nil, "Ring aus nach der Antwort")
		T.eq(S.Phone.Messages()[1].text, "Ja, bitte gleich mitmachen. Danke!", "Antwort in Nachrichten")
		T.eq(S.Phone.Messages()[1].from, who, "Absender = Kunde")
		-- Auflegen: „Fertig“ nach der Antwort schließt das Handy (Werkstatt und Tutorial wieder frei)
		click(T, S, visibleNamed(S, "HangUp"), "Auflegen/Fertig")
		T.eq(S.Phone.App(), "home", "nach dem Auflegen zurück zum Home-Bildschirm")
		T.eq(S.Phone.CallState(), nil, "Anruf beendet")
		g:Advance(0.4)
		T.eq(S.Phone.IsOpen(), false, "Fertig schließt das Handy")
		-- Zusage ohne Tippen: Handy legt nach AutoCloseSeconds selbst auf
		g:InClient(p, function()
			S.Phone.Call("job_1")
		end)
		g:Advance(0.3)
		fireCall(S, { job = "job_1", state = "ringing", customer = who })
		fireCall(S, { job = "job_1", state = "answer", accepted = true, text = "Ja.", result = "Freigegeben." })
		T.eq(S.Phone.IsOpen(), true, "Antwort sichtbar")
		g:Advance(S.Phone.AutoCloseSeconds + 0.4)
		T.eq(S.Phone.IsOpen(), false, "Handy schließt nach der Zusage von selbst")
		-- Ablehnung
		g:InClient(p, function()
			S.Phone.Call("job_1")
		end)
		g:Advance(0.3)
		fireCall(S, { job = "job_1", state = "ringing", customer = who })
		fireCall(S, { job = "job_1", state = "answer", accepted = false, text = "Nein danke, bitte nur den Check.", result = "Nur der Check wird gemacht." })
		T.eq(find(visibleNamed(S, "Bubble"), "Text").Text, "Nein danke, bitte nur den Check.", "Absage als Sprechblase")
		-- „ended“ ohne Antwort
		g:InClient(p, function()
			S.Phone.HangUp()
			S.Phone.Call("job_1")
		end)
		g:Advance(0.3)
		fireCall(S, { job = "job_1", state = "ended", customer = who })
		T.eq(visibleNamed(S, "CallStatus").Text, "Anruf beendet", "Status beendet")
		T.eq(visibleNamed(S, "HangUp").Text, "Fertig", "Knopf „Fertig“")
		-- Server lehnt ab (Toast während „Wählt …“) -> Status zeigt den Grund
		g:InClient(p, function()
			S.Phone.HangUp()
			S.Phone.Call("job_1")
		end)
		g:FireClient(p, "toast", "Gerade muss kein Kunde angerufen werden.")
		g:Advance(0.3)
		T.eq(S.Phone.CallState().state, "failed", "Absage erkannt")
		T.eq(visibleNamed(S, "CallStatus").Text, "Gerade muss kein Kunde angerufen werden.", "Grund im Status")
		-- keine Antwort -> Zeitüberschreitung
		g:InClient(p, function()
			S.Phone.HangUp()
			S.Phone.Call("job_1")
		end)
		g:Advance(S.Phone.DialTimeout + 1)
		T.eq(S.Phone.CallState().state, "failed", "Zeitüberschreitung ohne Serverantwort")
		T.check(visibleNamed(S, "CallStatus").Text:find("Keine Verbindung", 1, true) ~= nil, "„Keine Verbindung“")
		-- Anruf, den der OBD-Tester startet (ringing ohne vorherigen Wählvorgang): Handy geht auf
		g:InClient(p, function()
			S.Phone.HangUp()
			S.Phone.Close()
		end)
		g:Advance(0.5)
		fireCall(S, { job = "job_1", state = "ringing", customer = who })
		g:Advance(0.4)
		T.eq(S.Phone.IsOpen(), true, "ringing öffnet das Handy")
		T.eq(S.Phone.App(), "call", "Anruf-Bildschirm")
		-- ungültige IDs werden nicht gesendet
		local before = S.rec.Count("phone_call")
		g:InClient(p, function()
			S.Phone.HangUp()
			S.Phone.Call(42)
			S.Phone.Call("")
			S.Phone.Call(string.rep("x", 65))
		end)
		T.eq(S.rec.Count("phone_call"), before, "ungültige IDs nicht gesendet")
		-- Open({job}) (Taste „Kunden anrufen“ im OBD-Tester) ruft direkt an
		g:InClient(p, function()
			S.Phone.Close()
		end)
		g:Advance(0.4)
		g:InClient(p, function()
			S.Phone.Open({ job = "job_1" })
		end)
		g:Advance(0.4)
		T.eq(S.rec.Count("phone_call"), before + 1, "Open({job}) sendet phone_call")
		T.eq(S.Phone.App(), "call", "Open({job}) zeigt den Anruf")
		-- ohne Freigabe-Aufträge: Hinweis statt Liste
		S.state.data.jobs[1].phase = "repair"
		g:InClient(p, function()
			S.Phone.HangUp()
			S.Phone.ShowApp("kunden")
		end)
		g:Advance(0.3)
		T.check(visibleNamed(S, "Empty") ~= nil and visibleNamed(S, "Empty").Text:find("kein Kunde", 1, true) ~= nil, "Hinweis ohne Freigabe-Aufträge")
		T.eq(S.gui.PhoneButton.Badge.Visible, false, "kein Zähler ohne Freigabe")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "Handy: Nachrichten (neueste oben, max. 30), Aufträge (Phase + nächster Schritt), Karte, Konto, Einstellungen (lobby_settings)", function(T, H)
		local S = setup(H, T)
		local g, p = S.g, S.p
		-- Nachrichten über das Remote „Event“ (Toasts und Hinweise mit Text)
		for i = 1, 35 do
			g:FireClient(p, "toast", "Hinweis " .. i)
		end
		g:FireClient(p, "mini_notice", { kind = "story", text = "Mission geschafft!" })
		g:FireClient(p, "mini_notice", { kind = "leaderboard", text = "ignorieren" })
		local msgs = S.Phone.Messages()
		T.eq(#msgs, 30, "höchstens 30 Nachrichten")
		T.eq(msgs[1].text, "Mission geschafft!", "neueste oben (mini_notice mit Text)")
		T.eq(msgs[2].text, "Hinweis 35", "dann der letzte Toast")
		g:FireClient(p, "toast", "Mission geschafft!")
		T.eq(S.Phone.Messages()[1].text, "Mission geschafft!", "gleicher Text kurz hintereinander zählt einmal")
		T.eq(S.Phone.Messages()[2].text, "Hinweis 35", "keine Doppelung")
		g:InClient(p, function()
			S.Phone.Open({ app = "nachrichten" })
		end)
		g:Advance(0.5)
		T.check(visibleNamed(S, "Message1") ~= nil, "Nachricht 1 angezeigt")
		T.check(textOf(visibleNamed(S, "Message1")):find("Mission geschafft!", 1, true) ~= nil, "Text der neuesten Nachricht")
		-- Aufträge
		click(T, S, visibleNamed(S, "Back"), "Zurück")
		click(T, S, visibleNamed(S, "App_auftraege"), "App Aufträge")
		T.eq(S.Phone.App(), "auftraege", "App Aufträge offen")
		for _, id in ipairs({ "job_1", "job_2", "job_3" }) do
			T.check(visibleNamed(S, "Job_" .. id) ~= nil, "Auftrag " .. id)
		end
		local C = g:Config()
		local j2 = textOf(visibleNamed(S, "Job_job_2"))
		T.check(j2:find(C.JobById.oil.name, 1, true) ~= nil, "Name Ölwechsel")
		T.check(j2:find(C.JobById.oil.steps[2].name, 1, true) ~= nil, "nächster Schritt = Schritt 2 (Ölfilter): " .. j2)
		T.check(textOf(visibleNamed(S, "Job_job_3")):find("Endkontrolle", 1, true) ~= nil, "Endkontrolle offen")
		T.check(textOf(visibleNamed(S, "Job_job_1")):find("Kunden anrufen", 1, true) ~= nil, "Freigabe: Kunden anrufen")
		T.check(visibleNamed(S, "Parked") ~= nil, "wartende Aufträge auf dem Hof")
		-- Zustand ändert sich -> neu gezeichnet
		S.state.data.jobs[2].phase = "working"
		g:Advance(0.6)
		T.check(textOf(visibleNamed(S, "Job_job_2")):find("Arbeit läuft", 1, true) ~= nil, "Phase aktualisiert ohne Neuöffnen")
		-- Karte
		click(T, S, visibleNamed(S, "Back"), "Zurück")
		click(T, S, visibleNamed(S, "App_karte"), "App Karte")
		click(T, S, visibleNamed(S, "OpenMap"), "Stadtplan öffnen")
		T.eq(S.flags.opened[#S.flags.opened], "map", "Minispiel-Tab map geöffnet")
		g:Advance(0.4)
		T.eq(S.Phone.IsOpen(), false, "Handy schließt beim Stadtplan")
		-- Konto
		g:InClient(p, function()
			S.Phone.Open({ app = "konto" })
		end)
		g:Advance(0.5)
		local konto = textOf(phoneFrame(S))
		T.check(konto:find("12.345", 1, true) ~= nil, "Credits formatiert: " .. konto)
		T.check(konto:find("Meisterschrauber I", 1, true) ~= nil, "Prestige-Rang mit Titel")
		T.check(konto:find("4.321", 1, true) ~= nil, "Tycoon-Bargeld")
		T.eq(find(visibleNamed(S, "Level"), "Value").Text, "7", "Level")
		S.snap.tycoon = { run = false }
		S.snap.credits = 99
		g:Advance(0.6)
		T.check(textOf(phoneFrame(S)):find("kein Durchlauf", 1, true) ~= nil, "ohne Tycoon-Durchlauf")
		T.check(textOf(phoneFrame(S)):find("99 Cr", 1, true) ~= nil, "Credits aktualisiert")
		-- Einstellungen
		click(T, S, visibleNamed(S, "Back"), "Zurück")
		click(T, S, visibleNamed(S, "App_einstellungen"), "App Einstellungen")
		local passiveToggle = find(visibleNamed(S, "Setting_passive"), "Toggle")
		T.eq(passiveToggle:GetAttribute("On"), false, "Passiv aus")
		T.eq(find(visibleNamed(S, "Setting_beginner"), "Toggle"):GetAttribute("On"), true, "Beginner an")
		click(T, S, passiveToggle, "Passiv-Schalter")
		local ls = S.rec.Last("lobby_settings")
		T.check(ls ~= nil and ls.passive == true and ls.beginner == true and ls.single == false, "lobby_settings mit allen drei Werten (passive an)")
		T.eq(find(visibleNamed(S, "Setting_passive"), "Toggle"):GetAttribute("On"), true, "Schalter zeigt sofort an")
		S.snap.meta.passive = true -- Server bestätigt
		g:Advance(0.6)
		click(T, S, find(visibleNamed(S, "Setting_beginner"), "Toggle"), "Beginner-Schalter")
		ls = S.rec.Last("lobby_settings")
		T.check(ls.beginner == false and ls.passive == true, "Beginner aus, Passiv bleibt an")
		-- Startwahl ist Pflicht (StartUI zeigt sich selbst, kein „Später entscheiden“): das Handy bietet keinen Knopf
		-- „Startweg wählen“ mehr – weder ohne noch mit offener Startwahl
		T.check(visibleNamed(S, "ChooseStart") == nil, "ohne offene Startwahl kein Knopf")
		S.snap.start = { pending = true, path = "" }
		g:Advance(0.6)
		T.check(visibleNamed(S, "ChooseStart") == nil, "auch bei offener Startwahl kein Knopf (Startwahl ist Pflicht)")
		T.eq(S.flags.reopened, nil, "Handy öffnet die Startwahl nicht")
		T.check(visibleNamed(S, "Setting_passive") ~= nil, "Einstellungen bleiben bedienbar")
		S.snap.start = { pending = false, path = "werkstatt" }
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "Handy: blendet sich bei QTE/Diagnose/Tester, Tablet, Panel und Fahrt aus und kommt im selben Zustand wieder", function(T, H)
		local S = setup(H, T)
		local g, p = S.g, S.p
		g:InClient(p, function()
			S.Phone.Open({ app = "auftraege" })
		end)
		g:Advance(0.5)
		T.check(S.Phone.IsVisible(), "offen und sichtbar")
		for _, case in ipairs({ { "blocked", "QTE/Diagnose/Tester" }, { "tablet", "Tablet" }, { "panel", "Minispiel-Panel" } }) do
			S.flags[case[1]] = true
			g:Advance(0.4)
			T.eq(S.gui.Enabled, false, case[2] .. ": ScreenGui aus")
			T.eq(S.Phone.IsVisible(), false, case[2] .. ": Handy nicht sichtbar")
			T.eq(S.Phone.HiddenReason(), case[1], case[2] .. ": Grund")
			-- P öffnet/schließt währenddessen nicht
			g:Key(p, Enum.KeyCode.P)
			g:Advance(0.3)
			S.flags[case[1]] = false
			g:Advance(0.4)
			T.eq(S.gui.Enabled, true, case[2] .. " vorbei: wieder da")
			T.eq(S.Phone.App(), "auftraege", case[2] .. " vorbei: gleiche App")
		end
		-- Während eines Dialogs lässt sich das Handy nicht öffnen
		g:InClient(p, function()
			S.Phone.Close()
		end)
		g:Advance(0.4)
		S.flags.blocked = true
		g:Advance(0.3)
		g:Key(p, Enum.KeyCode.P)
		g:Advance(0.3)
		T.eq(S.Phone.IsOpen(), false, "P während QTE/Diagnose öffnet nicht")
		T.eq(S.Phone.IsVisible(), false, "nichts zu sehen")
		S.flags.blocked = false
		g:Advance(0.3)
		-- Fahrt: ScreenGui „Fahren“ aktiv
		g:InClient(p, function()
			S.Phone.Open({ app = "home" })
			local drive = Instance.new("ScreenGui")
			drive.Name = "Fahren"
			drive.Enabled = true
			drive.Parent = p.PlayerGui
		end)
		g:Advance(0.4)
		T.eq(S.Phone.HiddenReason(), "drive", "Fahrt erkannt")
		T.eq(S.gui.Enabled, false, "während der Fahrt ausgeblendet")
		g:InClient(p, function()
			p.PlayerGui.Fahren.Enabled = false
		end)
		g:Advance(0.4)
		T.eq(S.gui.Enabled, true, "nach der Fahrt wieder da")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "Handy: Layout an den sechs Studio-Viewports – im Bild, nie über HUD-Leiste/Fahrzeugknöpfen, alle Knöpfe treffbar", function(T, H)
		for _, vp in ipairs(VIEWPORTS) do
			local tag = string.format("[%dx%d] ", vp[1], vp[2])
			local S = setup(H, T, { viewport = vp })
			local g, p = S.g, S.p
			local PrestigeUI = g:ClientModule(p, "Mini.PrestigeUI")
			local w, h = S.gui.AbsoluteSize.X, S.gui.AbsoluteSize.Y
			local inset = S.Hit.Inset
			local function checkRect(label, obj)
				local x, y, rw, rh = S.Hit.Rect(p, obj)
				T.check(x >= 0 and y >= inset and x + rw <= vp[1] + 0.5 and y + rh <= vp[2] + 0.5, tag .. label .. " im Bild (" .. string.format("%d,%d %dx%d", x, y, rw, rh) .. ")")
				-- Koordinaten der ScreenGui (ohne Topbar) für PrestigeUI.HitsGarage
				T.check(not PrestigeUI.HitsGarage(w, h, x, y - inset, rw, rh), tag .. label .. " nicht über HUD-Leiste/Fahrzeugknöpfen (" .. string.format("%d,%d %dx%d", x, y - inset, rw, rh) .. ")")
				return x, y, rw, rh
			end
			checkRect("Handy-Knopf", S.gui.PhoneButton)
			local bx, by = S.Hit.Center(p, S.gui.PhoneButton)
			T.eq(S.Hit.At(p, bx, by), S.gui.PhoneButton, tag .. "Handy-Knopf bekommt den Klick")
			click(T, S, S.gui.PhoneButton, tag .. "Handy-Knopf")
			g:Advance(0.5)
			local o, sc = S.Phone.Orientation()
			local _, _, pw, ph = checkRect("Handy (" .. o .. ", " .. string.format("%.2f", sc) .. ")", phoneFrame(S))
			if vp[1] == 1920 then
				T.eq(o, "portrait", tag .. "hochkant")
				T.check(math.abs(pw - 260) < 1 and math.abs(ph - 500) < 1, tag .. "260 × 500 bei 1080p (" .. pw .. " × " .. ph .. ")")
			end
			if vp[1] == 844 then
				T.eq(o, "landscape", tag .. "Handy quer gelegt")
			end
			if vp[1] == 390 then
				T.eq(o, "portrait", tag .. "Handy hochkant")
			end
			T.check(sc >= 0.5, tag .. "Handy nicht winzig (Skala " .. tostring(sc) .. ")")
			-- Home: alle Apps treffbar und im Handy
			click(T, S, visibleNamed(S, "Back") or visibleNamed(S, "NavHome"), tag .. "zum Home-Bildschirm")
			if S.Phone.App() ~= "home" then
				g:InClient(p, function()
					S.Phone.ShowApp("home")
				end)
			end
			local px, py, pw2, ph2 = S.Hit.Rect(p, phoneFrame(S))
			for _, a in ipairs(S.Phone.Apps) do
				local icon = visibleNamed(S, "App_" .. a.key)
				local ix, iy, iw, ih = S.Hit.Rect(p, icon)
				T.check(ix >= px and iy >= py and ix + iw <= px + pw2 + 0.5 and iy + ih <= py + ph2 + 0.5, tag .. "App " .. a.key .. " im Handy")
				local cx, cy = S.Hit.Center(p, icon)
				T.eq(S.Hit.At(p, cx, cy), icon, tag .. "App " .. a.key .. " treffbar")
			end
			-- Touch-Flächen nach UIScale mindestens 44 px hoch
			local function tall(label, obj)
				if not T.check(obj ~= nil, tag .. label .. " vorhanden") then
					return
				end
				local _, _, rw, rh = S.Hit.Rect(p, obj)
				T.check(rh >= 44 - 0.01, tag .. label .. " ≥ 44 px hoch (" .. string.format("%.1f × %.1f", rw, rh) .. ")")
			end
			for _, name in ipairs({ "NavBack", "NavHome", "NavClose" }) do
				local nb = visibleNamed(S, name)
				local cx, cy = S.Hit.Center(p, nb)
				T.eq(S.Hit.At(p, cx, cy), nb, tag .. name .. " treffbar")
				tall(name, nb)
			end
			-- Kunden-App: Anrufen-Knopf treffbar; Anruf-Bildschirm: Auflegen treffbar
			click(T, S, visibleNamed(S, "App_kunden"), tag .. "App Kunden")
			tall("Back", visibleNamed(S, "Back"))
			tall("Anrufen", visibleNamed(S, "Call_job_1"))
			click(T, S, visibleNamed(S, "Call_job_1"), tag .. "Anrufen")
			fireCall(S, { job = "job_1", state = "answer", accepted = true, text = "Ja, bitte.", result = "Freigegeben." })
			local hang = visibleNamed(S, "HangUp")
			tall("Fertig", hang)
			local hx, hy, hw, hh = S.Hit.Rect(p, hang)
			T.check(hx >= px and hy >= py and hx + hw <= px + pw2 + 0.5 and hy + hh <= py + ph2 + 0.5, tag .. "Auflegen im Handy")
			local bub = visibleNamed(S, "Bubble")
			local ux, uy, uw, uh = S.Hit.Rect(p, bub)
			T.check(not overlaps(ux, uy, uw, uh, hx, hy, hw, hh), tag .. "Sprechblase überdeckt „Auflegen“ nicht")
			click(T, S, hang, tag .. "Auflegen")
			g:Advance(0.4)
			T.eq(S.Phone.IsOpen(), false, tag .. "Fertig schließt das Handy")
			click(T, S, S.gui.PhoneButton, tag .. "Handy wieder öffnen")
			g:Advance(0.5)
			if S.Phone.App() ~= "home" then
				g:InClient(p, function()
					S.Phone.ShowApp("home")
				end)
			end
			-- Einstellungen: Schalter treffbar
			click(T, S, visibleNamed(S, "App_einstellungen"), tag .. "App Einstellungen")
			tall("Schalter", find(visibleNamed(S, "Setting_passive"), "Toggle"))
			click(T, S, find(visibleNamed(S, "Setting_passive"), "Toggle"), tag .. "Passiv-Schalter")
			T.eq(g:ErrorText(), "", tag .. "keine Fehler")
			g:Close()
		end
	end },

	{ "Handy im echten Client: kein Knopf des 2.4.0-UI wird vom Handy oder Handy-Knopf überdeckt (sechs Viewports)", function(T, H)
		for _, vp in ipairs(VIEWPORTS) do
			local tag = string.format("[%dx%d] ", vp[1], vp[2])
			local Hit = H.Load("tests/lib/gui_hit.lua")
			local g = H.Garage({ placeKind = "openworld", startTime = NOW, viewport = H.Mock.Vector2.new(vp[1], vp[2]) })
			local p = g:Join(1302, { name = "Echt" })
			g:Advance(0.5)
			g:StartClient(p)
			g:Advance(2)
			local MiniClient = g:ClientModule(p, "Mini.MiniClient")
			local MiniRemote = g:ClientModule(p, "Mini.MiniRemote")
			local Phone = g:ClientModule(p, "Mini.PhoneUI")
			local garage = p.PlayerGui:FindFirstChild("UltimateCarGame")
			-- Tablet = Rahmen mit den Nav_*-Knöpfen (GarageClient-intern; MiniClient reicht opts.isTabletOpen weiter)
			local nav = garage and garage:FindFirstChild("Nav_workshop", true)
			local tablet = nav
			while tablet and tablet.Parent ~= garage do
				tablet = tablet.Parent
			end
			local function tabletOpen()
				return tablet ~= nil and Hit.Visible(tablet)
			end
			g:InClient(p, function()
				Phone.Start({
					Remote = MiniRemote, IsBlocked = MiniClient.IsBlocked, IsPanelOpen = MiniClient.IsOpen, Open = MiniClient.Open,
					Snapshot = MiniClient.Snapshot, IsTabletOpen = tabletOpen,
				})
			end)
			g:Advance(0.5)
			local gui = p.PlayerGui:FindFirstChild("Handy")
			T.check(gui ~= nil and garage ~= nil, tag .. "Handy und 2.4.0-UI vorhanden")
			if tabletOpen() then
				T.eq(gui.Enabled, false, tag .. "Handy weicht dem offenen Tablet")
				local close
				for _, x in ipairs(tablet:GetDescendants()) do
					if x:IsA("TextButton") and x.Text == "×" and Hit.Visible(x) then
						close = x
					end
				end
				Hit.Click(T, g, p, close, { label = tag .. "Tablet schließen" })
				g:Advance(0.5)
			end
			T.eq(tabletOpen(), false, tag .. "Tablet zu")
			local function covered(label, obj)
				local bad = {}
				for _, x in ipairs(garage:GetDescendants()) do
					if x:IsA("GuiObject") and Hit.Visible(x) and Hit.Sinks(x) and Hit.Overlap(p, obj, x) then
						table.insert(bad, Hit.Path(x))
					end
				end
				T.check(#bad == 0, tag .. label .. " liegt über 2.4.0-Bedienelementen: " .. table.concat(bad, ", "))
			end
			covered("Handy-Knopf", gui.PhoneButton)
			g:Key(p, Enum.KeyCode.P)
			g:Advance(0.6)
			T.eq(Phone.IsOpen(), true, tag .. "P öffnet im echten Client")
			covered("Handy", gui.Phone)
			-- Konto aus dem echten Snapshot
			g:InClient(p, function()
				Phone.ShowApp("konto")
			end)
			g:Advance(0.4)
			local credits = gui.Phone:FindFirstChild("Credits", true)
			T.check(credits ~= nil, tag .. "Konto zeigt Credits aus dem echten Snapshot")
			g:Key(p, Enum.KeyCode.P)
			g:Advance(0.5)
			T.eq(Phone.IsOpen(), false, tag .. "P schließt")
			T.eq(g:ErrorText(), "", tag .. "keine Fehler")
			g:Close()
		end
	end },

	{ "PhoneService: phone_call prüft Typ/Länge/Zeichen/Auftrag, Abklingzeit, ruft api.callCustomer(p, id), Toasts auf Deutsch", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW })
		local PS = g:MiniServer("PhoneService")
		local registered = {}
		local Actions = {
			Register = function(name, fn)
				registered[name] = fn
			end,
		}
		local toasts, calls = {}, {}
		local result = { true, nil }
		local api = {
			now = function()
				return 1000
			end,
			toast = function(ms, text)
				table.insert(toasts, text)
			end,
			callCustomer = function(p, id)
				table.insert(calls, { p = p, id = id })
				return result[1], result[2]
			end,
		}
		PS.Register(Actions, api)
		T.check(type(registered.phone_call) == "function", "phone_call registriert")
		local session = { name = "Sitzung" }
		local ms = { p = session }
		local d = { jobs = { { id = "job_7", phase = "approval" } } }
		local h = registered.phone_call
		-- ungültige Nutzlast
		for _, bad in ipairs({ { id = 7 }, { id = "" }, { id = string.rep("a", 65) }, { id = "job 7" }, { id = "job_7;drop" }, {}, { id = "job_99" } }) do
			local n = #toasts
			T.eq(h(ms, bad, d, 1000), nil, "ungültig: " .. tostring(bad.id))
			T.eq(#toasts, n + 1, "Toast bei ungültig: " .. tostring(bad.id))
		end
		T.eq(#calls, 0, "callCustomer nie mit ungültiger ID")
		T.eq(toasts[#toasts], PS.Text.invalid, "deutscher Toast")
		-- gültig
		T.eq(h(ms, { id = "job_7" }, d, 1000), true, "Anruf gestartet")
		T.eq(#calls, 1, "callCustomer gerufen")
		T.eq(calls[1].p, session, "mit der GarageServer-Sitzung (ms.p)")
		T.eq(calls[1].id, "job_7", "mit der ID")
		-- Abklingzeit
		T.eq(h(ms, { id = "job_7" }, d, 1001), nil, "Abklingzeit")
		T.eq(toasts[#toasts], PS.Text.cooldown, "Abklingzeit-Toast")
		T.eq(#calls, 1, "kein zweiter Anruf")
		-- nach der Abklingzeit, Server sagt nein -> Meldung als Toast, Abklingzeit freigegeben
		result = { false, "Du telefonierst gerade." }
		T.eq(h(ms, { id = "job_7" }, d, 1000 + PS.Cooldown + 0.1), nil, "abgelehnt")
		T.eq(toasts[#toasts], "Du telefonierst gerade.", "Meldung des Servers als Toast")
		result = { false, nil }
		T.eq(h(ms, { id = "job_7" }, d, 1000 + PS.Cooldown + 0.2), nil, "abgelehnt ohne Text")
		T.eq(toasts[#toasts], PS.Text.failed, "Standard-Text")
		-- Fehler im Rückruf -> kein Absturz, Toast
		api.callCustomer = function()
			error("kaputt")
		end
		local ms2 = { p = session }
		T.eq(h(ms2, { id = "job_7" }, d, 2000), nil, "Fehler abgefangen")
		T.eq(toasts[#toasts], PS.Text.noSignal, "kein Empfang")
		-- ohne callCustomer (nicht verkabelt)
		api.callCustomer = nil
		local ms3 = { p = session }
		T.eq(h(ms3, { id = "job_7" }, d, 3000), nil, "ohne callCustomer")
		T.eq(toasts[#toasts], PS.Text.noSignal, "Toast ohne Verkabelung")
		for _, text in ipairs(toasts) do
			T.check(type(text) == "string" and text ~= "", "Toast-Text vorhanden")
		end
		g:Close()
	end },

	{ "Handy end-to-end (falls verkabelt): Fahrzeug-Check mit Befund -> phone_call über Remotes.Command -> Kunde antwortet", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW })
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.Actions.phone_call then
			T.check(true, "phone_call noch nicht in MiniNet.Actions (Integrator verkabelt) – übersprungen")
			g:Close()
			return
		end
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local p = g:Join(1303, { name = "Kunde" })
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p, { finding = "brakes" })
		T.check(j ~= nil, "Fahrzeug-Check angenommen")
		if not j then
			g:Close()
			return
		end
		Flow.Scan(T, g, p, j.id)
		T.eq(Flow.Job(g, p, j.id).phase, "approval", "Fehlerspeicher mit Befund -> Freigabe offen")
		local C = g:Config()
		local m = g:Mark()
		local res = g:Act(p, "phone_call", { id = j.id, rid = 77 })
		T.eq(res, "ok", "phone_call angenommen (" .. table.concat(g:Toasts(p, m), " | ") .. ")")
		local ringing
		for _, e in ipairs(g:Events(p, "call", m)) do
			if e.state == "ringing" then
				ringing = e
			end
		end
		T.check(ringing ~= nil and ringing.job == j.id, "Server meldet ringing")
		g:Advance(C.Inspection.RingSeconds + 0.3)
		local answer
		for _, e in ipairs(g:Events(p, "call", m)) do
			if e.state == "answer" then
				answer = e
			end
		end
		T.check(answer ~= nil and type(answer.text) == "string", "Kunde antwortet")
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "nach der Antwort geht es weiter")
		-- ungültige ID über den echten Weg
		m = g:Mark()
		g:Act(p, "phone_call", { id = "job_nicht_da", rid = 78 })
		T.check(#g:Toasts(p, m) >= 1, "ungültige ID -> Toast")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },
}
