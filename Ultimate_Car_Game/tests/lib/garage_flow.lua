-- Gemeinsame Abläufe der 2.4.0-Werkstatt für Tests (über den echten Server): Annehmen, OBD-Scan,
-- Diagnose, Reparaturschritte mit QTE-Treffer, Endkontrolle, Abrechnen.
-- Laden mit: local Flow = H.Load("tests/lib/garage_flow.lua")
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

-- Am Empfang die Inspektion annehmen; liefert die Job-Tabelle aus dem letzten state
function Flow.AcceptInspection(T, g, p)
	g:Advance(0.2)
	g:Teleport(p, g:Station(p, "workshop"), Vector3.new(0, 0, 3))
	local offer = Flow.FindOffer(g, p, "inspection")
	if not T.check(offer ~= nil, "Inspektionsauftrag im Angebot") then
		return nil
	end
	local m = g:Mark()
	g:Send(p, "accept", { id = offer.id })
	T.check(g:HasToast(p, "Auftrag angenommen", m), "Toast 'Auftrag angenommen'")
	for _, j in ipairs(g:Data(p).jobs) do
		if j.kind == "inspection" then
			return j
		end
	end
	return nil
end

-- OBD-Scan am DiagnosticPoint; wartet 2,5 s und liefert das diagnose-Event
function Flow.Scan(T, g, p, jobId)
	local car = g:Car(p, jobId)
	g:Advance(0.2)
	g:Send(p, "tool", { id = "scanner" })
	g:Teleport(p, car.DiagnosticPoint, Vector3.new(0, 0, 1.5))
	g:Advance(0.2)
	local m = g:Mark()
	g:Send(p, "scan", { id = jobId })
	T.check(g:Last(p, "scan", m) ~= nil, "scan-Event gesendet")
	g:Advance(2.7)
	return g:Last(p, "diagnose", m)
end

-- Ein Reparaturschritt: Werkzeug, Punkt, QTE-Treffer in der Mitte der grünen Zone, Arbeit abwarten
function Flow.RepairStep(T, g, p, jobId, stepIndex)
	local C = g:Config()
	local car = g:Car(p, jobId)
	local step = C.JobById[Flow.Job(g, p, jobId).kind].steps[stepIndex]
	g:Advance(0.2)
	g:Send(p, "tool", { id = step.tool })
	g:Teleport(p, car[step.point], Vector3.new(0, 0, 1.5))
	local m = g:Mark()
	g:Send(p, "work", { id = jobId, point = step.point })
	local c = g:Last(p, "challenge", m)
	if not T.check(c ~= nil, "Schritt " .. stepIndex .. ": challenge (Toasts: " .. table.concat(g:Toasts(p, m), " | ") .. ")") then
		return false
	end
	g:AdvanceTo(c.startAt + c.center * c.period)
	m = g:Mark()
	g:Send(p, "hit", { token = c.token, at = g:Now() })
	if not T.check(g:HasToast(p, "Arbeit läuft", m), "Schritt " .. stepIndex .. ": Treffer (Toasts: " .. table.concat(g:Toasts(p, m), " | ") .. ")") then
		return false
	end
	local j = Flow.Job(g, p, jobId)
	g:AdvanceTo(j.workUntil + 0.6)
	return true, j
end

-- Kompletter Ablauf bis zur Abrechnung; liefert das receipt-Event (oder nil)
function Flow.CompleteInspection(T, g, p)
	local C = g:Config()
	local j = Flow.AcceptInspection(T, g, p)
	if not j then
		return nil
	end
	local def = C.JobById[j.kind]
	local diag = Flow.Scan(T, g, p, j.id)
	if not T.check(diag ~= nil, "diagnose-Event") then
		return nil
	end
	g:Send(p, "diagnose", { id = j.id, choice = def.cause })
	for i = 1, #def.steps do
		if not Flow.RepairStep(T, g, p, j.id, i) then
			return nil
		end
	end
	Flow.Scan(T, g, p, j.id)
	if not T.eq(Flow.Job(g, p, j.id) and Flow.Job(g, p, j.id).phase, "invoice", "Phase invoice") then
		return nil
	end
	g:Teleport(p, g:Station(p, "workshop"), Vector3.new(0, 0, 3))
	g:Advance(0.2)
	local m = g:Mark()
	g:Send(p, "settle", { id = j.id })
	return g:Last(p, "receipt", m), j
end

return Flow
