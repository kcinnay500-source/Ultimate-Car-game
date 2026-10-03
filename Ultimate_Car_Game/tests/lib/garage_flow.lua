-- Gemeinsame Abläufe der Werkstatt für Tests (über den echten Server): Annehmen, OBD-Scan (Fehlerspeicher),
-- Diagnose, Kundenanruf (Fahrzeug-Check mit Befund), Reparaturschritte mit QTE-Treffer, Endkontrolle, Abrechnen.
-- Laden mit: local Flow = H.Load("tests/lib/garage_flow.lua")
--
-- 3.0-Ablauf: Werkzeug, Hebebühne, Motorhaube und Gerät stellt der Server beim E-Druck selbst passend
-- (GarageServer prepare/autoTool). Der Fahrzeug-Check liest den Fehlerspeicher: ohne Befund geht es nach dem
-- Scan direkt zur Sichtprüfung, mit Befund in die Phase "approval" (Kunde per Handy anrufen, Aktion "call").
-- Flow.AcceptInspection erzwingt standardmäßig "kein Befund" (deterministische Tests anderer Bereiche);
-- opts.finding = "natural" behält die Entscheidung des Servers, opts.finding = "<kind>" erzwingt einen Befund.
local Flow = {}

function Flow.FindOffer(g, p, kind)
	for _, o in ipairs(g:Data(p).offers) do
		if o.kind == kind then
			return o
		end
	end
end

function Flow.Job(g, p, id)
	for _, j in ipairs(g:Data(p).jobs) do
		if j.id == id then
			return j
		end
	end
end

-- Live-Auftrag auf dem Server (nur mit Minispiel-Sitzung, also nicht im Basismodus)
function Flow.LiveJob(g, p, id)
	local ok, d = pcall(function()
		return g:D(p)
	end)
	if not ok or not d then
		return nil
	end
	for _, j in ipairs(d.jobs) do
		if j.id == id then
			return j
		end
	end
end

local function toasts(g, p, m)
	return table.concat(g:Toasts(p, m), " | ")
end

-- Befund eines frisch angenommenen Fahrzeug-Checks festlegen (Testkontrolle, nur Phase diagnose)
function Flow.ForceFinding(g, p, id, finding)
	local live = Flow.LiveJob(g, p, id)
	if live and live.kind == "inspection" and live.phase == "diagnose" then
		live.finding = finding or nil
		g:Send(p, "select", { id = id }) -- frischer state
		return true
	end
	return false
end

-- Am Empfang einen Auftrag der Art `kind` annehmen; liefert die Job-Tabelle aus dem letzten state
function Flow.AcceptKind(T, g, p, kind)
	g:Advance(0.2)
	g:Teleport(p, g:Station(p, "workshop"), Vector3.new(0, 0, 3))
	local offer = Flow.FindOffer(g, p, kind)
	if not T.check(offer ~= nil, "Auftrag '" .. kind .. "' im Angebot") then
		return nil
	end
	local before = {}
	for _, j in ipairs(g:Data(p).jobs) do
		before[j.id] = true
	end
	local m = g:Mark()
	g:Send(p, "accept", { id = offer.id })
	T.check(g:HasToast(p, "Auftrag angenommen", m), "Toast 'Auftrag angenommen' (" .. toasts(g, p, m) .. ")")
	for _, j in ipairs(g:Data(p).jobs) do
		if j.kind == kind and not before[j.id] then
			return j
		end
	end
	return nil
end

-- Am Empfang die Inspektion annehmen; opts.finding: nil/false = kein Befund (Standard), "natural", "<kind>"
function Flow.AcceptInspection(T, g, p, opts)
	opts = opts or {}
	local j = Flow.AcceptKind(T, g, p, "inspection")
	if j and opts.finding ~= "natural" then
		Flow.ForceFinding(g, p, j.id, type(opts.finding) == "string" and opts.finding or nil)
		j = Flow.Job(g, p, j.id) or j
	end
	return j
end

-- OBD-Scan am DiagnosticPoint; wartet 2,5 s und liefert das diagnose-Event.
-- opts.auto = true: kein Werkzeugwechsel vorher (der Server nimmt den OBD-Tester selbst)
function Flow.Scan(T, g, p, jobId, opts)
	opts = opts or {}
	local car = g:Car(p, jobId)
	g:Advance(0.2)
	if not opts.auto then
		g:Send(p, "tool", { id = "scanner" })
	end
	g:Teleport(p, car.DiagnosticPoint, Vector3.new(0, 0, 1.5))
	g:Advance(0.2)
	local m = g:Mark()
	g:Send(p, "scan", { id = jobId })
	T.check(g:Last(p, "scan", m) ~= nil, "scan-Event gesendet (" .. toasts(g, p, m) .. ")")
	g:Advance(2.7)
	return g:Last(p, "diagnose", m)
end

-- Multiple-Choice-Diagnose nur, wenn der Auftrag sie noch braucht (normale Aufträge; der Fahrzeug-Check nicht mehr)
function Flow.Diagnose(T, g, p, jobId)
	local C = g:Config()
	local j = Flow.Job(g, p, jobId)
	if j and j.phase == "diagnose" then
		g:Send(p, "diagnose", { id = jobId, choice = C.JobById[j.kind].cause })
	end
	return Flow.Job(g, p, jobId)
end

-- Kunden anrufen (Aktion "call"). opts.decision = true/false erzwingt die Antwort (patcht R.CustomerDecision kurz).
-- Liefert das "answer"-Event (oder nil) und das "ringing"-Event.
function Flow.Call(T, g, p, jobId, opts)
	opts = opts or {}
	local C, R = g:Config(), g:Rules()
	local original = R.CustomerDecision
	if opts.decision ~= nil then
		R.CustomerDecision = function()
			return opts.decision
		end
	end
	local m = g:Mark()
	g:Send(p, "call", { id = jobId })
	local ringing
	for _, e in ipairs(g:Events(p, "call", m)) do
		if e.state == "ringing" then
			ringing = e
		end
	end
	T.check(ringing ~= nil, "Anruf klingelt (" .. toasts(g, p, m) .. ")")
	g:Advance(C.Inspection.RingSeconds + 0.2)
	R.CustomerDecision = original
	local answer
	for _, e in ipairs(g:Events(p, "call", m)) do
		if e.state == "answer" then
			answer = e
		end
	end
	return answer, ringing
end

-- E am Arbeitspunkt drücken (echter ProximityPrompt "WorkPrompt"); liefert ok, Grund, Marke vor dem Druck
function Flow.PressE(g, p, jobId, point)
	local car = g:Car(p, jobId)
	local part = car and car:FindFirstChild(point)
	if not part then
		return false, "Punkt fehlt: " .. tostring(point), g:Mark()
	end
	g:Teleport(p, part, Vector3.new(0, 0, 1.5))
	g:Advance(0.15)
	local prompt = part:FindFirstChild("WorkPrompt")
	local m = g:Mark()
	if not prompt then
		return false, "kein WorkPrompt", m
	end
	local ok, why = g:Trigger(p, prompt)
	return ok, why, m
end

-- QTE-Treffer in der Mitte der grünen Zone und Arbeit abwarten
function Flow.Hit(T, g, p, jobId, c, label)
	g:AdvanceTo(c.startAt + c.center * c.period)
	local m = g:Mark()
	g:Send(p, "hit", { token = c.token, at = g:Now() })
	if not T.check(g:HasToast(p, "Arbeit läuft", m), label .. ": Treffer (Toasts: " .. toasts(g, p, m) .. ")") then
		return false
	end
	local j = Flow.Job(g, p, jobId)
	g:AdvanceTo(j.workUntil + 0.6)
	return true, j
end

-- Ein Reparaturschritt nur mit E (Werkzeug, Bühne, Haube, Gerät automatisch); bis zu 3 E-Drücke
function Flow.RepairStepE(T, g, p, jobId, stepIndex)
	local C = g:Config()
	local step = C.JobById[Flow.Job(g, p, jobId).kind].steps[stepIndex]
	local label = "Schritt " .. stepIndex .. " (" .. step.name .. ")"
	local log = {}
	for _ = 1, 3 do
		local ok, why, m = Flow.PressE(g, p, jobId, step.point)
		if not ok then
			table.insert(log, "E: " .. tostring(why))
			g:Advance(2.3)
		else
			local c = g:Last(p, "challenge", m)
			table.insert(log, toasts(g, p, m))
			if c then
				return Flow.Hit(T, g, p, jobId, c, label)
			end
			g:Advance(2.3) -- Bühne fährt
		end
	end
	T.check(false, label .. ": keine challenge nach E (" .. table.concat(log, " || ") .. ")")
	return false
end

-- Ein Reparaturschritt (klassisch: Werkzeug wählen, Punkt, work); fährt die Bühne, wiederholt der Helfer
function Flow.RepairStep(T, g, p, jobId, stepIndex)
	local C = g:Config()
	local car = g:Car(p, jobId)
	local step = C.JobById[Flow.Job(g, p, jobId).kind].steps[stepIndex]
	g:Advance(0.2)
	g:Send(p, "tool", { id = step.tool })
	local c, m
	for _ = 1, 3 do
		g:Teleport(p, car[step.point], Vector3.new(0, 0, 1.5))
		m = g:Mark()
		g:Send(p, "work", { id = jobId, point = step.point })
		c = g:Last(p, "challenge", m)
		if c or not g:HasToast(p, "Die Bühne fährt", m) then
			break
		end
		g:Advance(2.3)
	end
	if not T.check(c ~= nil, "Schritt " .. stepIndex .. ": challenge (Toasts: " .. toasts(g, p, m) .. ")") then
		return false
	end
	return Flow.Hit(T, g, p, jobId, c, "Schritt " .. stepIndex)
end

-- Endkontrolle nur mit E am OBD-Anschluss (Haube/Bühne automatisch); liefert die Phase danach
function Flow.VerifyE(T, g, p, jobId)
	for _ = 1, 3 do
		local ok, why, m = Flow.PressE(g, p, jobId, "DiagnosticPoint")
		if ok and g:Last(p, "scan", m) then
			g:Advance(2.7)
			break
		end
		T.check(ok or why ~= "kein WorkPrompt", "Endkontrolle: Prompt (" .. tostring(why) .. ")")
		g:Advance(2.3)
	end
	local j = Flow.Job(g, p, jobId)
	return j and j.phase
end

function Flow.Settle(T, g, p, jobId)
	g:Teleport(p, g:Station(p, "workshop"), Vector3.new(0, 0, 3))
	g:Advance(0.2)
	local m = g:Mark()
	g:Send(p, "settle", { id = jobId })
	return g:Last(p, "receipt", m)
end

-- Kompletter Ablauf bis zur Abrechnung; liefert das receipt-Event (oder nil).
-- opts.finding wie AcceptInspection; opts.decision für den Anruf (Standard true)
function Flow.CompleteInspection(T, g, p, opts)
	opts = opts or {}
	local C = g:Config()
	local j = Flow.AcceptInspection(T, g, p, opts)
	if not j then
		return nil
	end
	local diag = Flow.Scan(T, g, p, j.id)
	if not T.check(diag ~= nil, "diagnose-Event") then
		return nil
	end
	j = Flow.Diagnose(T, g, p, j.id)
	if j and j.phase == "approval" then
		local decision = opts.decision
		if decision == nil then
			decision = true
		end
		Flow.Call(T, g, p, j.id, { decision = decision })
		j = Flow.Job(g, p, j.id)
	end
	if not T.check(j and j.phase == "repair", "Phase repair nach Scan (" .. tostring(j and j.phase) .. ")") then
		return nil
	end
	local def = C.JobById[j.kind]
	for i = 1, #def.steps do
		if not Flow.RepairStep(T, g, p, j.id, i) then
			return nil
		end
	end
	Flow.Scan(T, g, p, j.id)
	if not T.eq(Flow.Job(g, p, j.id) and Flow.Job(g, p, j.id).phase, "invoice", "Phase invoice") then
		return nil
	end
	return Flow.Settle(T, g, p, j.id), j
end

return Flow
