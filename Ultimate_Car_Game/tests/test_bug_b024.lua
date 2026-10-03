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
			ReopenStart = function()
				flags.reopened = (flags.reopened or 0) + 1
				return true
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


-- B-024: „Auflegen“ während des Klingelns setzte nur Client-Zustand. Der Server wertete den Anruf nach RingSeconds
-- trotzdem aus (Auftrag wechselte auf freigegeben/abgelehnt) und meldete bis dahin „Du telefonierst gerade.“
local function callEvents(g, p, since, state)
	local out = {}
	for _, e in ipairs(g:Events(p, "call", since)) do
		if e.state == state then
			table.insert(out, e)
		end
	end
	return out
end

return {
	{ "B-024 Handy (Client): „Auflegen“ beim Wählen/Klingeln sendet phone_hangup ohne Nutzlast, „Fertig“ nach der Antwort nicht", function(T, H)
		local S = setup(H, T)
		local g, p = S.g, S.p
		g:InClient(p, function()
			S.Phone.Open({ app = "kunden" })
		end)
		g:Advance(0.5)
		click(T, S, visibleNamed(S, "Call_job_1"), "Anrufen")
		T.eq(S.rec.Count("phone_call"), 1, "Anruf gesendet")
		fireCall(S, { job = "job_1", state = "ringing", customer = "Frau Becker", car = "Testauto", findingName = "Bremsen" })
		T.eq(visibleNamed(S, "HangUp").Text, "Auflegen", "Knopf „Auflegen“ beim Klingeln")
		click(T, S, visibleNamed(S, "HangUp"), "Auflegen")
		T.eq(S.rec.Count("phone_hangup"), 1, "phone_hangup gesendet")
		local n = 0
		for _ in pairs(S.rec.Last("phone_hangup") or { x = 1 }) do
			n += 1
		end
		T.eq(n, 0, "ohne Nutzlast (reine Absicht)")
		T.eq(S.Phone.App(), "home", "zurück auf dem Startbildschirm")
		-- der Server meldet das Ende: kein neuer Anruf-Bildschirm
		fireCall(S, { job = "job_1", state = "ended" })
		T.eq(S.Phone.App(), "home", "bleibt auf dem Startbildschirm")
		-- neuer Anruf sofort möglich; Auflegen schon beim Wählen (vor „ringing“)
		g:InClient(p, function()
			S.Phone.Call("job_1")
		end)
		g:Advance(0.3)
		T.eq(S.rec.Count("phone_call"), 2, "neuer Anruf gesendet")
		click(T, S, visibleNamed(S, "HangUp"), "Auflegen beim Wählen")
		T.eq(S.rec.Count("phone_hangup"), 2, "auch beim Wählen: phone_hangup")
		-- nach der Antwort heißt der Knopf „Fertig“ und sendet nichts
		g:InClient(p, function()
			S.Phone.Call("job_1")
		end)
		g:Advance(0.3)
		fireCall(S, { job = "job_1", state = "ringing", customer = "Frau Becker" })
		fireCall(S, { job = "job_1", state = "answer", accepted = true, text = "Ja, bitte gleich mitmachen. Danke!", result = "Freigegeben", customer = "Frau Becker" })
		T.eq(visibleNamed(S, "HangUp").Text, "Fertig", "nach der Antwort „Fertig“")
		click(T, S, visibleNamed(S, "HangUp"), "Fertig")
		T.eq(S.rec.Count("phone_hangup"), 2, "„Fertig“ sendet kein phone_hangup")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "B-024 Handy (Server): Auflegen bricht den Anruf ab – Auftrag bleibt in approval, neuer Anruf sofort möglich", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW })
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local C = g:Config()
		local p = g:Join(1304, { name = "Aufleger" })
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p, { finding = "brakes" })
		T.check(j ~= nil, "Fahrzeug-Check angenommen")
		if not j then
			g:Close()
			return
		end
		Flow.Scan(T, g, p, j.id)
		T.eq(Flow.Job(g, p, j.id).phase, "approval", "Freigabe offen")
		local sess = g:Session(p)
		-- Auflegen ohne Anruf: nichts passiert (kein Toast, kein Ereignis)
		local m = g:Mark()
		T.eq(g:Act(p, "phone_hangup", { rid = 70 }), "ok", "phone_hangup ist eine bekannte Aktion")
		T.eq(#g:Events(p, "call", m), 0, "ohne Anruf kein Ereignis")
		T.eq(#g:Toasts(p, m), 0, "ohne Anruf kein Toast")
		-- anrufen, es klingelt, auflegen
		m = g:Mark()
		T.eq(g:Act(p, "phone_call", { id = j.id, rid = 71 }), "ok", "phone_call angenommen")
		T.eq(#callEvents(g, p, m, "ringing"), 1, "es klingelt")
		T.check(sess.calling ~= nil, "Server: Anruf läuft")
		g:Advance(0.5)
		g:Act(p, "phone_hangup", { rid = 72 })
		T.eq(sess.calling, nil, "Server: Anruf beendet")
		local ended = callEvents(g, p, m, "ended")
		T.check(#ended == 1 and ended[1].job == j.id, "Server meldet ended für den Auftrag")
		-- neuer Anruf sofort möglich (Werkstatt-Weg ohne Handy-Abklingzeit): kein „Du telefonierst gerade.“
		local m2 = g:Mark()
		g:Send(p, "call", { id = j.id })
		T.eq(#callEvents(g, p, m2, "ringing"), 1, "sofort wieder anrufbar")
		T.check(not g:HasToast(p, "Du telefonierst gerade", m2), "kein „Du telefonierst gerade.“")
		g:Advance(0.3)
		T.eq(g:Act(p, "phone_hangup", { rid = 73 }), "ok", "zweites Auflegen angenommen")
		T.eq(sess.calling, nil, "zweiter Anruf ebenfalls aufgelegt")
		-- weit über die Klingelzeit hinaus: keine Auswertung, Auftrag bleibt in der Freigabe
		g:Advance(C.Inspection.RingSeconds + 1.5)
		T.eq(#callEvents(g, p, m, "answer"), 0, "aufgelegte Anrufe werden nicht ausgewertet")
		T.eq(Flow.Job(g, p, j.id).phase, "approval", "Auftrag bleibt in approval")
		T.eq(Flow.Job(g, p, j.id).approved, nil, "keine Entscheidung gespeichert")
		-- ohne Auflegen bleibt der Ablauf unverändert: Kunde antwortet nach der Klingelzeit
		m = g:Mark()
		T.eq(g:Act(p, "phone_call", { id = j.id, rid = 74 }), "ok", "dritter Anruf")
		g:Advance(C.Inspection.RingSeconds + 0.3)
		T.eq(#callEvents(g, p, m, "answer"), 1, "Kunde antwortet")
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "nach der Antwort geht es weiter")
		-- Auflegen nach der Antwort ändert nichts mehr
		g:Act(p, "phone_hangup", { rid = 75 })
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "Auflegen nach der Antwort ohne Wirkung")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },
}
