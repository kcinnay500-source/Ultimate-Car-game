-- Werkstatt 3.0 (Studio-Bericht „feststecken“): Ölwechsel und Endkontrolle nur mit E (Werkzeug, Bühne, Haube,
-- Gerät stellt der Server selbst), Fahrzeug-Check mit Fehlerspeicher und Kundenanruf (Ja/Nein/kein Befund),
-- OBD-Tester-Daten im diagnose-Event, robuster 0,5-s-Takt (eingeschleuster W.Sync-Fehler), freie Hand.
local Flow

local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "Laufzeitfehler") .. ": " .. g:ErrorText())
end

local function hasTool(p)
	local ch = p.Character
	local tool = ch and ch:FindFirstChild("GarageTool")
	return tool and tool:GetAttribute("ToolId") or nil
end

-- Angebot einer Art direkt ins Live-Profil legen (die Angebotsauswahl ist zufällig)
local function offer(g, p, kind, carId)
	local d = g:D(p)
	table.insert(d.offers, 1, { id = "offer_test_" .. kind .. "_" .. #d.offers, kind = kind, carId = carId or "komet" })
	g:Advance(0.6) -- Takt sendet state
end

local function toastText(g, p, m)
	return table.concat(g:Toasts(p, m), " | ")
end

-- Reparaturschritte nur mit E
local function repairAllE(T, g, p, jobId)
	local C = g:Config()
	local def = C.JobById[Flow.Job(g, p, jobId).kind]
	for i = 1, #def.steps do
		if not Flow.RepairStepE(T, g, p, jobId, i) then
			return false
		end
	end
	return true
end

return {
	{ "Ölwechsel nur mit E: Werkzeug, Gerät, Bühne und Haube automatisch", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local C = g:Config()
		local p = g:Join(2101)
		g:Advance(1)
		T.eq(g:State(p).tool, "hand", "Start mit freier Hand")
		offer(g, p, "oil")
		local j = Flow.AcceptKind(T, g, p, "oil")
		if not j then
			return
		end
		-- Diagnose: E am OBD-Anschluss nimmt den Tester selbst
		local ok, why, m = Flow.PressE(g, p, j.id, "DiagnosticPoint")
		T.check(ok, "E am OBD-Anschluss (" .. tostring(why) .. ")")
		T.check(g:HasToast(p, "Werkzeug: OBD-Tester", m), "Tester automatisch (" .. toastText(g, p, m) .. ")")
		T.check(g:Last(p, "scan", m) ~= nil, "Scan läuft")
		g:Advance(2.7)
		local diag = g:Last(p, "diagnose", m)
		T.check(diag ~= nil and #diag.answers == 3, "Diagnose mit Auswahl (normaler Auftrag)")
		T.check(diag and #diag.codes >= 1 and diag.codes[1].code == C.FaultCodes.oil[1].code, "Fehlercode Ölwechsel im Tester")
		T.check(diag and #diag.live >= #C.LiveValues, "Live-Daten im Tester")
		g:Send(p, "diagnose", { id = j.id, choice = C.JobById.oil.cause })
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "Phase repair")
		-- Schritt 1: Öl ablassen (Bühne oben, Ölauffanggerät an Bühne 1, Ölservice-Werkzeug)
		T.check(g:D(p).equipmentBays.oil_drain == nil, "Ölauffanggerät steht noch im Lager")
		m = g:Mark()
		T.check(Flow.RepairStepE(T, g, p, j.id, 1), "Schritt 1 nur mit E")
		T.check(g:HasToast(p, "Ölauffanggerät steht jetzt an Bühne 1", m), "Gerät automatisch bereitgestellt (" .. toastText(g, p, m) .. ")")
		T.check(g:HasToast(p, "Die Bühne fährt hoch", m), "Bühne automatisch hoch")
		T.check(g:HasToast(p, "Werkzeug: Ölservice", m), "Ölservice automatisch")
		-- Schritt 2: Ölfilter mit der Ratsche (früher: Feststecken mit Öl in der Hand)
		m = g:Mark()
		T.check(Flow.RepairStepE(T, g, p, j.id, 2), "Schritt 2 (Ölfilter) nur mit E")
		T.check(g:HasToast(p, "Werkzeug: Ratsche", m), "Ratsche automatisch (" .. toastText(g, p, m) .. ")")
		T.eq(hasTool(p), "ratchet", "Ratsche in der Hand")
		-- Schritt 3: Öl einfüllen (Bühne runter, Haube auf)
		m = g:Mark()
		T.check(Flow.RepairStepE(T, g, p, j.id, 3), "Schritt 3 nur mit E")
		T.check(g:HasToast(p, "Die Bühne fährt runter", m), "Bühne automatisch runter")
		T.check(g:HasToast(p, "Motorhaube geöffnet", m), "Haube automatisch auf")
		T.eq(Flow.Job(g, p, j.id).phase, "verify", "Phase verify")
		-- Endkontrolle mit offener Haube: E schließt sie und prüft
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Endkontrolle nur mit E")
		local receipt = Flow.Settle(T, g, p, j.id)
		T.check(receipt ~= nil and receipt.money > 0, "abgerechnet")
		noErrors(T, g)
	end },

	{ "Endkontrolle mit Bühne oben und Haube offen (automatisch)", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local p = g:Join(2102)
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p)
		if not j then
			return
		end
		Flow.Scan(T, g, p, j.id, { auto = true })
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "ohne Befund direkt zur Sichtprüfung")
		T.check(repairAllE(T, g, p, j.id), "Sichtprüfung nur mit E")
		T.eq(Flow.Job(g, p, j.id).phase, "verify", "Phase verify")
		-- Bühne hoch und Haube auf (von Hand), dann nur E am OBD-Anschluss
		local car = g:Car(p, j.id)
		local bay = car and g:Plot(p).Bays:FindFirstChild("Bay_" .. j.bay)
		g:Teleport(p, bay.LiftControl, Vector3.new(0, 0, 1.5))
		g:Advance(0.2)
		g:Send(p, "lift", { id = j.id })
		g:Advance(2.3)
		g:Teleport(p, car.HoodPoint, Vector3.new(0, 0, 1.5))
		g:Advance(0.2)
		g:Send(p, "hood", { id = j.id })
		local vis = g:State(p).visuals[j.id]
		T.check(vis.lifted and vis.hood, "Bühne oben, Haube offen")
		local diagPrompt = car.DiagnosticPoint:FindFirstChild("WorkPrompt")
		T.check(diagPrompt and diagPrompt.Enabled, "E-Prompt am OBD-Anschluss bleibt aktiv")
		local ok, _, m = Flow.PressE(g, p, j.id, "DiagnosticPoint")
		T.check(ok, "E gedrückt")
		T.check(g:HasToast(p, "gleich nochmal E", m), "Hinweis: gleich nochmal E (" .. toastText(g, p, m) .. ")")
		g:Advance(2.3)
		vis = g:State(p).visuals[j.id]
		T.check(not vis.lifted and not vis.hood, "Bühne unten, Haube zu")
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Endkontrolle bestanden")
		noErrors(T, g)
	end },

	{ "Fahrzeug-Check mit Befund: Fehlerspeicher, Anruf, Ja, Ölwechsel mit Check-Bonus", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local C, R = g:Config(), g:Rules()
		local p = g:Join(2103)
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p, { finding = "oil" })
		if not j then
			return
		end
		T.eq(Flow.LiveJob(g, p, j.id).finding, "oil", "Befund Ölwechsel (Server)")
		T.eq(Flow.Job(g, p, j.id).finding, nil, "Befund vor dem Scan nicht im Client-Schnappschuss")
		-- Anruf vor dem Scan ist nicht möglich
		local m = g:Mark()
		g:Send(p, "call", { id = j.id })
		T.eq(#g:Events(p, "call", m), 0, "kein Anruf vor dem Fehlerspeicher")
		T.check(g:HasToast(p, "kein Kunde angerufen", m), "Hinweis ohne Freigabe")
		local diag = Flow.Scan(T, g, p, j.id, { auto = true })
		T.check(diag ~= nil, "diagnose-Event")
		if not diag then
			return
		end
		T.eq(diag.phase, "approval", "Phase approval im Tester")
		T.eq(diag.finding, "oil", "Befund im Tester")
		T.eq(#diag.answers, 0, "keine Multiple-Choice beim Fahrzeug-Check")
		T.eq(#diag.codes, #C.FaultCodes.oil, "Fehlercodes des Befunds")
		T.check(diag.message:find("Fehler gespeichert", 1, true) ~= nil, "Meldung Fehlerspeicher")
		T.check(type(diag.customer) == "string", "Kundenname")
		T.check(g:State(p).objective:find("Ruf den Kunden", 1, true) ~= nil, "Ziel: Kunden anrufen")
		-- Arbeitspunkte gesperrt, bis der Kunde entschieden hat
		local car = g:Car(p, j.id)
		T.check(not car.EnginePoint.WorkPrompt.Enabled, "kein Arbeitsschritt vor der Freigabe")
		-- Anruf: klingelt, zweiter Anruf abgelehnt, dann Antwort
		local R0 = R.CustomerDecision
		R.CustomerDecision = function()
			return true
		end
		m = g:Mark()
		g:Send(p, "call", { id = j.id })
		g:Advance(0.2)
		g:Send(p, "call", { id = j.id })
		T.check(g:HasToast(p, "Du telefonierst gerade", m), "kein Doppelanruf")
		local ringing = g:Events(p, "call", m)
		T.check(#ringing == 1 and ringing[1].state == "ringing", "genau ein Klingeln")
		g:Advance(C.Inspection.RingSeconds)
		R.CustomerDecision = R0
		local answer = g:Last(p, "call", m)
		T.check(answer and answer.state == "answer" and answer.accepted == true, "Kunde sagt Ja")
		local job = Flow.Job(g, p, j.id)
		T.eq(job.kind, "oil", "weiter als Ölwechsel")
		T.eq(job.phase, "repair", "Phase repair")
		T.eq(job.step, 1, "Schritt 1")
		local bonus = math.floor(C.JobById.inspection.reward * C.CarById[job.carId].reward + 0.5)
		T.eq(job.inspectionBonus, bonus, "Check-Bonus")
		T.check(repairAllE(T, g, p, j.id), "Ölwechsel nur mit E")
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Endkontrolle")
		local live = Flow.LiveJob(g, p, j.id)
		local expected = R.Reward(g:D(p), live)
		local base = H.Copy(live)
		base.inspectionBonus = nil
		T.eq(expected - R.Reward(g:D(p), base), bonus, "R.Reward enthält den Check-Bonus")
		local receipt = Flow.Settle(T, g, p, j.id)
		T.check(receipt ~= nil, "Quittung")
		T.eq(receipt and receipt.money, expected, "Vergütung mit Bonus")
		T.eq(receipt and receipt.inspectionBonus, bonus, "Bonus auf der Quittung")
		noErrors(T, g)
	end },

	{ "Mini.Init-ctx enthält callCustomer (Handy aus einem Minispiel-Modul)", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local ctx
		local g = H.Garage({ before = function(g0)
			local Mini = g0:Mini()
			local init = Mini.Init
			Mini.Init = function(c)
				ctx = c
				return init(c)
			end
		end })
		T.check(ctx and type(ctx.callCustomer) == "function", "ctx.callCustomer vorhanden")
		if not (ctx and ctx.callCustomer) then
			return
		end
		local p = g:Join(2110)
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p, { finding = "oil" })
		if not j then
			return
		end
		local session = g:Session(p)
		local ok, msg = ctx.callCustomer(session, j.id)
		T.eq(ok, false, "vor dem Scan keine Freigabe offen")
		T.check(type(msg) == "string" and #msg > 0, "Meldung für das Handy")
		Flow.Scan(T, g, p, j.id, { auto = true })
		local m = g:Mark()
		ok = ctx.callCustomer(session, nil) -- ohne ID: der Auftrag in Phase approval
		T.eq(ok, true, "Anruf gestartet")
		T.eq(g:Last(p, "call", m).state, "ringing", "klingelt")
		g:Advance(g:Config().Inspection.RingSeconds + 0.2)
		local answer = g:Last(p, "call", m)
		T.eq(answer.state, "answer", "Antwort")
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "danach repair")
		noErrors(T, g)
	end },

	{ "Fahrzeug-Check mit Befund: Kunde sagt Nein", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local p = g:Join(2104)
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p, { finding = "oil" })
		if not j then
			return
		end
		Flow.Scan(T, g, p, j.id, { auto = true })
		local answer = Flow.Call(T, g, p, j.id, { decision = false })
		T.check(answer and answer.accepted == false, "Kunde sagt Nein")
		local job = Flow.Job(g, p, j.id)
		T.eq(job.kind, "inspection", "bleibt Fahrzeug-Check")
		T.eq(job.phase, "repair", "Sichtprüfung")
		T.eq(job.approved, false, "abgelehnt gespeichert")
		T.check(job.inspectionBonus == nil, "kein Bonus")
		T.check(repairAllE(T, g, p, j.id), "Sichtprüfung nur mit E")
		local diag
		local m = g:Mark()
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Endkontrolle")
		diag = g:Last(p, "diagnose", m)
		T.check(diag and #diag.codes > 0, "abgelehnter Fehler bleibt im Speicher")
		local receipt = Flow.Settle(T, g, p, j.id)
		T.check(receipt and receipt.inspectionBonus == nil and receipt.name == "Fahrzeug-Check", "Quittung nur Check")
		noErrors(T, g)
	end },

	{ "Fahrzeug-Check ohne Befund: Keine Fehler gespeichert, direkt Sichtprüfung", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local p = g:Join(2105)
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p)
		if not j then
			return
		end
		local diag = Flow.Scan(T, g, p, j.id, { auto = true })
		T.check(diag ~= nil, "diagnose-Event")
		T.eq(diag and #diag.codes, 0, "keine Codes")
		T.eq(diag and diag.message, "Keine Fehler gespeichert", "Meldung")
		T.eq(diag and #diag.answers, 0, "keine Auswahl")
		T.eq(diag and diag.phase, "repair", "direkt repair")
		local m = g:Mark()
		g:Send(p, "call", { id = j.id })
		T.eq(#g:Events(p, "call", m), 0, "kein Anruf ohne Befund")
		-- alter Client schickt noch eine Auswahl: wird ignoriert
		g:Advance(0.2)
		g:Send(p, "diagnose", { id = j.id, choice = 1 })
		T.eq(Flow.Job(g, p, j.id).quality, 100, "keine Strafe durch alte Auswahl")
		T.check(repairAllE(T, g, p, j.id), "Sichtprüfung")
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Endkontrolle")
		local receipt = Flow.Settle(T, g, p, j.id)
		T.check(receipt and receipt.money > 0, "abgerechnet")
		-- Gesamtablauf über den Helfer (Standard: kein Befund) und mit Befund + Ja
		T.check(Flow.CompleteInspection(T, g, p) ~= nil, "CompleteInspection ohne Befund")
		local r2 = Flow.CompleteInspection(T, g, p, { finding = "oil", decision = true })
		T.check(r2 and r2.inspectionBonus and r2.inspectionBonus > 0, "CompleteInspection mit Befund und Ja")
		noErrors(T, g)
	end },

	{ "Befund und Kundenentscheidung sind deterministisch und passen zum Level", function(T, H)
		local g = H.Garage({})
		local C, R = g:Config(), g:Rules()
		local d = R.NewData(0)
		local found, counts = 0, {}
		for i = 1, 400 do
			local id = "job_" .. i
			local f = R.InspectionFinding(d, id, "komet")
			T.eq(R.InspectionFinding(d, id, "komet"), f, "deterministisch " .. id)
			if f then
				found += 1
				counts[f] = (counts[f] or 0) + 1
			end
		end
		T.check(found > 400 * (C.Inspection.FindingChance - 0.1) and found < 400 * (C.Inspection.FindingChance + 0.1), "Befundquote ≈ FindingChance (" .. found .. "/400)")
		T.eq(counts.oil, found, "Level 1: nur Ölwechsel")
		-- Level 12 ohne Radheber/Diagnosewagen: keine Reifen-/Batterieaufträge; mit Geräten möglich
		d.level = 12
		local kinds = {}
		for _, c in ipairs(R.FindingCandidates(d, "komet")) do
			kinds[c.id] = c.weight
		end
		T.check(kinds.oil and not kinds.tire and not kinds.battery and not kinds.inspection, "nur machbare Befunde")
		d.equipment.wheel_jack, d.equipment.tire_machine = 1, 1
		kinds = {}
		for _, c in ipairs(R.FindingCandidates(d, "komet")) do
			kinds[c.id] = c.weight
		end
		T.check(kinds.tire ~= nil and kinds.oil > kinds.tire, "Reifen möglich, Öl häufiger (günstiger)")
		local elys = {}
		d.level = 40
		for _, c in ipairs(R.FindingCandidates(d, "elys")) do
			elys[c.id] = true
		end
		T.check(not elys.oil, "E-Auto: kein Ölwechsel")
		local yes = 0
		for i = 1, 400 do
			local job = { id = "job_" .. i }
			T.eq(R.CustomerDecision(job), R.CustomerDecision(job), "Entscheidung deterministisch")
			if R.CustomerDecision(job) then
				yes += 1
			end
			T.check(table.find(C.Inspection.Customers, R.CustomerName(job)) ~= nil, "Kundenname aus der Liste")
		end
		T.check(yes > 400 * (C.Inspection.ApproveChance - 0.1) and yes < 400 * (C.Inspection.ApproveChance + 0.1), "Zusagequote ≈ ApproveChance (" .. yes .. ")")
		-- Spielstand: approval und neue Felder bleiben, alte Inspektion ohne Befund = kein Befund
		local raw = R.NewData(0)
		raw.jobs = {
			{ id = "job_1", kind = "inspection", carId = "komet", bay = 1, phase = "approval", step = 1, finding = "oil", scanReady = true },
			{ id = "job_2", kind = "oil", carId = "komet", bay = 2, phase = "repair", step = 2, finding = "oil", approved = true, inspectionBonus = 155 },
			{ id = "job_3", kind = "inspection", carId = "komet", bay = 3, phase = "approval", step = 1 },
			{ id = "job_4", kind = "inspection", carId = "komet", bay = 4, phase = "diagnose", step = 1, finding = "nonsense" },
		}
		raw.bays = 4
		raw.loadout = { "hand", "scanner", "ratchet" }
		local loaded = R.LoadData(raw, nil, 0)
		local byId = {}
		for _, j in ipairs(loaded.jobs) do
			byId[j.id] = j
		end
		T.eq(byId.job_1.phase, "approval", "approval bleibt")
		T.eq(byId.job_1.finding, "oil", "Befund bleibt")
		T.eq(byId.job_2.inspectionBonus, 155, "Bonus bleibt")
		T.eq(byId.job_2.approved, true, "Zusage bleibt")
		T.eq(byId.job_3.phase, "repair", "approval ohne Befund -> Sichtprüfung")
		T.eq(byId.job_4.finding, nil, "ungültiger Befund verworfen")
		T.check(table.find(loaded.loadout, "hand") == nil, "Hand nicht in der Leiste")
		T.eq(#loaded.loadout, C.HotbarSize, "Leiste aufgefüllt")
		-- Tester-Daten
		local codes, live = R.Tester({ kind = "inspection", phase = "diagnose" })
		T.eq(#codes, 0, "kein Befund: keine Codes")
		T.eq(#live, #C.LiveValues, "Grund-Livewerte")
		codes = R.Tester({ kind = "oil", phase = "verify" })
		T.eq(#codes, 0, "nach der Reparatur gelöscht")
	end },

	{ "0,5-s-Takt überlebt W.Sync- und Tick-Fehler und holt den Abgleich nach", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local p = g:Join(2107)
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p)
		if not j then
			return
		end
		Flow.Scan(T, g, p, j.id, { auto = true })
		T.check(Flow.RepairStepE(T, g, p, j.id, 1), "Schritt 1 fertig")
		-- Schritt 2 hat begonnen und läuft; währenddessen bricht W.Sync
		local ok, _, m = Flow.PressE(g, p, j.id, "WheelPoint")
		local c = g:Last(p, "challenge", m)
		T.check(ok and c ~= nil, "Schritt 2 challenge")
		if not c then
			return
		end
		g:AdvanceTo(c.startAt + c.center * c.period)
		g:Send(p, "hit", { token = c.token, at = g:Now() })
		local job = Flow.Job(g, p, j.id)
		T.eq(job.phase, "working", "Schritt 2 läuft")
		local W = g:Require("ServerScriptService.Garage.World")
		local original = W.Sync
		local failures = 0
		W.Sync = function()
			failures += 1
			error("Testfehler im Abgleich")
		end
		local w0 = #g:Warnings()
		g:AdvanceTo(job.workUntil + 1.2)
		T.check(failures > 0, "W.Sync wurde aufgerufen und ist gescheitert")
		local warned = false
		for i = w0 + 1, #g:Warnings() do
			if g:Warnings()[i]:find("Abgleich der Werkstatt für", 1, true) then
				warned = true
			end
		end
		T.check(warned, "deutsche Warnung mit Spielername")
		T.eq(Flow.Job(g, p, j.id).step, 3, "Schritt weitergezählt (state trotz Fehler)")
		W.Sync = original
		g:Advance(1.1)
		local car = g:Car(p, j.id)
		T.check(car.DiagnosticPoint.WorkPrompt.Enabled, "nachgeholter Abgleich aktiviert den nächsten Arbeitspunkt")
		-- Fehler im ganzen Sitzungsrumpf (R.Advance) und im Minispiel-Takt: Takt läuft weiter
		local R = g:Rules()
		local advance = R.Advance
		R.Advance = function()
			error("Testfehler im Takt")
		end
		local Mini = g:Mini()
		local tick = Mini.Tick
		Mini.Tick = function()
			error("Testfehler im Minispiel-Takt")
		end
		w0 = #g:Warnings()
		g:Advance(1.1)
		R.Advance = advance
		Mini.Tick = tick
		local tickWarn, miniWarn = false, false
		for i = w0 + 1, #g:Warnings() do
			local text = g:Warnings()[i]
			tickWarn = tickWarn or text:find("Fehler im Takt für", 1, true) ~= nil
			miniWarn = miniWarn or text:find("Fehler im Minispiel-Takt für", 1, true) ~= nil
		end
		T.check(tickWarn and miniWarn, "Warnungen für Takt und Minispiel-Takt")
		local m2 = g:Mark()
		g:Advance(1.1)
		T.check(#g:Events(p, "state", m2) >= 1, "Takt sendet weiter state")
		T.check(Flow.RepairStepE(T, g, p, j.id, 3), "Schritt 3 danach möglich")
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Auftrag abschließbar")
		noErrors(T, g)
	end },

	{ "0,5-s-Takt: dauerhafter Fehler bei einem Spieler hält den anderen nicht an", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local p1 = g:Join(2111, { name = "Kaputt" })
		local p2 = g:Join(2112, { name = "Heil" })
		g:Advance(1)
		local j1 = Flow.AcceptInspection(T, g, p1)
		local j2 = Flow.AcceptInspection(T, g, p2)
		if not (j1 and j2) then
			return
		end
		Flow.Scan(T, g, p1, j1.id, { auto = true })
		Flow.Scan(T, g, p2, j2.id, { auto = true })
		-- ab jetzt scheitert jeder Abgleich und jeder Takt-Rumpf von Spieler 1 (z. B. kaputtes Modell)
		local W = g:Require("ServerScriptService.Garage.World")
		local R = g:Rules()
		local sync, advance = W.Sync, R.Advance
		local d1 = g:D(p1)
		W.Sync = function(w, d, ...)
			if w.owner == p1 then
				error("Testfehler: Modell von Spieler 1 kaputt")
			end
			return sync(w, d, ...)
		end
		R.Advance = function(d, ...)
			if d == d1 then
				error("Testfehler: Daten von Spieler 1")
			end
			return advance(d, ...)
		end
		local w0 = #g:Warnings()
		-- Spieler 2 arbeitet ganz normal weiter: drei Schritte, Endkontrolle
		for i = 1, 3 do
			T.check(Flow.RepairStepE(T, g, p2, j2.id, i), "Spieler 2: Schritt " .. i .. " trotz Fehler bei Spieler 1")
		end
		T.eq(Flow.VerifyE(T, g, p2, j2.id), "invoice", "Spieler 2: Auftrag abschließbar")
		local named = 0
		for i = w0 + 1, #g:Warnings() do
			if g:Warnings()[i]:find("Kaputt", 1, true) then
				named += 1
			end
		end
		T.check(named >= 1, "Warnung nennt Spieler 1")
		T.check(named <= 12, "Warnungen gedrosselt (" .. named .. ")")
		-- Fehler behoben: Spieler 1 kann ebenfalls weiter
		W.Sync, R.Advance = sync, advance
		g:Advance(1.1)
		T.check(Flow.RepairStepE(T, g, p1, j1.id, 1), "Spieler 1: nach der Behebung geht es weiter")
		noErrors(T, g)
	end },

	{ "Freie Hand: Start, Wechsel, Respawn, nicht in der Leiste", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local C, R = g:Config(), g:Rules()
		local p = g:Join(2108)
		g:Advance(1)
		T.eq(g:State(p).tool, "hand", "Start: freie Hand")
		T.eq(hasTool(p), nil, "nichts in der Hand")
		T.check(C.Tools.hand and C.Tools.hand.name == "Freie Hand", "Werkzeug-Eintrag")
		T.check(table.find(g:Data(p).loadout, "hand") == nil, "nicht in d.loadout")
		g:Send(p, "tool", { id = "scanner" })
		T.eq(hasTool(p), "scanner", "OBD-Tester in der Hand")
		g:Advance(0.2)
		g:Send(p, "tool", { id = "hand" })
		T.eq(g:State(p).tool, "hand", "zurück zur Hand")
		T.eq(hasTool(p), nil, "Werkzeug weggesteckt")
		g:Advance(0.2)
		g:Send(p, "tool", { id = "ratchet" })
		T.eq(hasTool(p), "ratchet", "Ratsche")
		g:Respawn(p)
		g:Advance(0.5)
		T.eq(g:State(p).tool, "hand", "Respawn: freie Hand")
		T.eq(hasTool(p), nil, "Respawn: nichts in der Hand")
		-- Hand lässt sich nicht in die Leiste legen
		local ok = R.SwapTool(H.Copy(g:D(p)), 1, "hand")
		T.eq(ok, false, "SwapTool lehnt Hand ab")
		T.check(R.ToolActive(g:D(p), "hand") and R.ToolUnlocked(g:D(p), "hand"), "Hand immer aktiv")
		-- Fehlt der OBD-Tester in der Leiste, sagt die Meldung, wo es ihn gibt
		g:Send(p, "travel", { key = "tools" })
		g:Advance(0.2)
		g:Send(p, "swapTool", { slot = 1, id = "lamp" })
		T.check(table.find(g:Data(p).loadout, "scanner") == nil, "Tester in der Kiste")
		local j = Flow.AcceptInspection(T, g, p)
		if not j then
			return
		end
		local okE, _, m = Flow.PressE(g, p, j.id, "DiagnosticPoint")
		T.check(okE, "E gedrückt")
		T.check(g:HasToast(p, "OBD-Tester", m) and g:HasToast(p, "Werkzeugkiste", m), "Meldung nennt Werkzeug und Ort (" .. toastText(g, p, m) .. ")")
		T.eq(g:Last(p, "scan", m), nil, "kein Scan ohne Tester")
		noErrors(T, g)
	end },
}
