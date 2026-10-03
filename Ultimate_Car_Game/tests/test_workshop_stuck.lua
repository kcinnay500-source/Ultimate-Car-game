-- Werkstatt 3.0 (Studio-Bericht „Endkontrolle/Ölfilter stecken fest“), Nachprüfung:
-- 1) Ein E-Druck löst in Roblox mehrere sichtbare E-Prompts aus (WorkPrompt + Stations-Prompt). Der Stations-Prompt
--    darf den laufenden OBD-Scan / die Endkontrolle nicht abbrechen.
-- 2) Steht ein anderes Gerät an der Bühne, stellt der Server es beim E-Druck selbst ins Lager (Reifen, Bremsen,
--    Ölwechsel nach Reifen).
-- 3) Befund und Kundenantwort des Fahrzeug-Checks stehen vor dem Scan nicht auf dem Client; Annehmen und Abbrechen
--    würfelt keinen neuen Befund.
local Flow

local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "Laufzeitfehler") .. ": " .. g:ErrorText())
end

local function offer(g, p, kind, carId)
	local d = g:D(p)
	table.insert(d.offers, 1, { id = "offer_stuck_" .. kind .. "_" .. #d.offers, kind = kind, carId = carId or "komet" })
	g:Advance(0.6)
end

local function toastText(g, p, m)
	return table.concat(g:Toasts(p, m), " | ")
end

-- Profil mit allen Geräten, vollem Teilelager und Level 10
local function richJoin(g, userId)
	local C = g:Config()
	g:SeedLevel(userId, 10, function(d)
		for _, e in ipairs(C.Equipment) do
			d.equipment[e.id] = math.max(d.equipment[e.id] or 0, 1)
		end
		for _, part in ipairs(C.Parts) do
			d.inventory[part.id] = 9
		end
		d.money = 100000
	end)
	local p = g:Join(userId)
	g:Advance(1)
	return p
end

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

-- WorkPrompt und gleich danach (wie Roblox bei einem E-Druck mit zwei sichtbaren Prompts) den Stations-Prompt
local function doubleE(g, p, workPrompt, stationKey)
	local m = g:Mark()
	local ok = g:Trigger(p, workPrompt)
	g:Advance(0.13)
	local station = g:Station(p, stationKey)
	local sp = station and station:FindFirstChildOfClass("ProximityPrompt")
	local okStation = sp and g:Trigger(p, sp, { force = true })
	return m, ok, okStation
end

local function pageEvents(g, p, m, key)
	local n = 0
	for _, e in ipairs(g:Events(p, "page", m)) do
		if e == key then
			n += 1
		end
	end
	return n
end

return {
	{ "Doppel-E (WorkPrompt + Stations-Prompt) bricht OBD-Scan und Endkontrolle nicht ab", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local C = g:Config()
		local p = g:Join(2301)
		g:Advance(1)
		local j = Flow.AcceptInspection(T, g, p)
		if not j then
			return
		end
		local car = g:Car(p, j.id)
		local prompt = car.DiagnosticPoint:FindFirstChild("WorkPrompt")
		T.eq(prompt and prompt.Exclusivity, Enum.ProximityPromptExclusivity.OnePerButton, "WorkPrompt: OnePerButton (kein Doppel-E)")
		-- Ankunft an Bühne 1 (dort reichen Stations- und OBD-Prompt beide hin)
		local arrival = g:Plot(p).Bays.Bay_1:FindFirstChild("PlayerArrival")
		g:Teleport(p, arrival or car.DiagnosticPoint, Vector3.new(0, 0, 0))
		g:Advance(0.2)
		local m, ok = doubleE(g, p, prompt, "upgrades")
		T.check(ok, "WorkPrompt ausgelöst")
		T.check(g:Last(p, "scan", m) ~= nil, "Scan gestartet (" .. toastText(g, p, m) .. ")")
		T.eq(#g:Events(p, "interactionReset", m), 0, "kein interactionReset durch den Stations-Prompt")
		T.eq(pageEvents(g, p, m, "upgrades"), 0, "Tablet geht nicht auf")
		g:Advance(2.7)
		T.check(g:Last(p, "diagnose", m) ~= nil, "Scan fertig: diagnose-Event")
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "weiter zur Sichtprüfung")
		-- Stationen funktionieren ohne laufende Interaktion weiter
		g:Advance(1)
		local m2 = g:Mark()
		g:Teleport(p, g:Station(p, "upgrades"), Vector3.new(0, 0, 3))
		g:Advance(0.2)
		g:Trigger(p, g:Station(p, "upgrades"):FindFirstChildOfClass("ProximityPrompt"))
		T.eq(pageEvents(g, p, m2, "upgrades"), 1, "Station öffnet ohne Interaktion")
		-- Sichtprüfung, dann Endkontrolle mit Doppel-E
		T.check(repairAllE(T, g, p, j.id), "Sichtprüfung nur mit E")
		T.eq(Flow.Job(g, p, j.id).phase, "verify", "Phase verify")
		local vis = g:State(p).visuals[j.id]
		if vis.lifted or vis.hood then
			Flow.PressE(g, p, j.id, "DiagnosticPoint")
			g:Advance(2.4)
		end
		g:Teleport(p, arrival or car.DiagnosticPoint, Vector3.new(0, 0, 0))
		g:Advance(0.8)
		m = doubleE(g, p, prompt, "upgrades")
		T.check(g:Last(p, "scan", m) ~= nil, "Endkontrolle gestartet (" .. toastText(g, p, m) .. ")")
		T.eq(#g:Events(p, "interactionReset", m), 0, "Endkontrolle nicht abgebrochen")
		g:Advance(2.7)
		T.eq(Flow.Job(g, p, j.id).phase, "invoice", "Endkontrolle bestanden trotz Doppel-E")
		noErrors(T, g)
	end },

	{ "Reifen nur mit E: Radheber und Montiermaschine tauschen den Geräteplatz selbst", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local p = richJoin(g, 2302)
		offer(g, p, "tire")
		local j = Flow.AcceptKind(T, g, p, "tire")
		if not j then
			return
		end
		Flow.Scan(T, g, p, j.id, { auto = true })
		Flow.Diagnose(T, g, p, j.id)
		T.eq(Flow.Job(g, p, j.id).phase, "repair", "Phase repair")
		T.check(Flow.RepairStepE(T, g, p, j.id, 1), "Schritt 1 (Radheber)")
		T.eq(g:D(p).equipmentBays.wheel_jack, 1, "Radheber an Bühne 1")
		local m = g:Mark()
		T.check(Flow.RepairStepE(T, g, p, j.id, 2), "Schritt 2 (Montiermaschine) nur mit E")
		T.check(g:HasToast(p, "Radheber ins Lager gestellt", m) or g:HasToast(p, "ins Lager gestellt", m), "Radheber automatisch ins Lager (" .. toastText(g, p, m) .. ")")
		T.eq(g:D(p).equipmentBays.tire_machine, 1, "Montiermaschine an Bühne 1")
		T.check(Flow.RepairStepE(T, g, p, j.id, 3), "Schritt 3 (Radheber wieder) nur mit E")
		T.eq(Flow.Job(g, p, j.id).phase, "verify", "Phase verify")
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Endkontrolle")
		T.check(Flow.Settle(T, g, p, j.id) ~= nil, "abgerechnet")
		-- Ölwechsel direkt danach: Radheber steht noch an Bühne 1
		T.check(g:D(p).equipmentBays.wheel_jack == 1, "Radheber steht noch an Bühne 1")
		offer(g, p, "oil")
		local o = Flow.AcceptKind(T, g, p, "oil")
		if not o then
			return
		end
		Flow.Scan(T, g, p, o.id, { auto = true })
		Flow.Diagnose(T, g, p, o.id)
		m = g:Mark()
		T.check(repairAllE(T, g, p, o.id), "Ölwechsel nach Reifen nur mit E")
		T.check(g:HasToast(p, "ins Lager gestellt", m), "Gerät automatisch ins Lager (" .. toastText(g, p, m) .. ")")
		T.eq(Flow.VerifyE(T, g, p, o.id), "invoice", "Endkontrolle Ölwechsel")
		noErrors(T, g)
	end },

	{ "Bremsen nur mit E: Entlüftungsgerät verdrängt den Radheber", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local p = richJoin(g, 2303)
		offer(g, p, "brakes")
		local j = Flow.AcceptKind(T, g, p, "brakes")
		if not j then
			return
		end
		Flow.Scan(T, g, p, j.id, { auto = true })
		Flow.Diagnose(T, g, p, j.id)
		T.check(repairAllE(T, g, p, j.id), "Bremsen alle Schritte nur mit E")
		T.eq(g:D(p).equipmentBays.brake_bleeder, 1, "Entlüftungsgerät an Bühne 1")
		T.eq(Flow.VerifyE(T, g, p, j.id), "invoice", "Endkontrolle")
		noErrors(T, g)
	end },

	{ "Arbeitendes Gerät wird nicht weggestellt; Meldung nennt es", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local C = g:Config()
		local p = richJoin(g, 2304)
		offer(g, p, "tire")
		local j = Flow.AcceptKind(T, g, p, "tire")
		if not j then
			return
		end
		Flow.Scan(T, g, p, j.id, { auto = true })
		Flow.Diagnose(T, g, p, j.id)
		T.check(Flow.RepairStepE(T, g, p, j.id, 1), "Schritt 1")
		-- künstlich: Radheber arbeitet an einem anderen Auftrag (Phase working, Schritt mit wheel_jack)
		local d = g:D(p)
		local fake = { id = "job_fake", kind = "tire", carId = "komet", bay = 2, phase = "working", step = 1, quality = 100,
			scanReady = true, selectedParts = {}, usedParts = {}, workUntil = g:Now() + 60 }
		table.insert(d.jobs, fake)
		local live = Flow.LiveJob(g, p, j.id)
		local ok, why, m = Flow.PressE(g, p, j.id, C.JobById.tire.steps[2].point)
		T.check(ok, "E gedrückt (" .. tostring(why) .. ")")
		T.check(g:HasToast(p, "Radheber", m) and g:HasToast(p, "arbeitet gerade", m), "Meldung nennt das arbeitende Gerät (" .. toastText(g, p, m) .. ")")
		T.eq(d.equipmentBays.wheel_jack, 1, "Radheber bleibt")
		T.eq(live.step, 2, "Schritt 2 wartet")
		for i, x in ipairs(d.jobs) do
			if x == fake then
				table.remove(d.jobs, i)
				break
			end
		end
		noErrors(T, g)
	end },

	{ "Fahrzeug-Check: Befund erst nach dem Scan auf dem Client, Abbrechen würfelt nicht neu", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({})
		local C, R = g:Config(), g:Rules()
		local p = g:Join(2305)
		g:Advance(1)
		-- Angebot hat ein Salz, der Client sieht es nie
		local d = g:D(p)
		local live
		for _, o in ipairs(d.offers) do
			if o.kind == "inspection" then
				live = o
			end
		end
		T.check(live and type(live.salt) == "number", "Server-Angebot mit Salz")
		for _, o in ipairs(g:Data(p).offers) do
			T.eq(o.salt, nil, "Client-Angebot ohne Salz")
		end
		local j = Flow.AcceptInspection(T, g, p, { finding = "natural" })
		if not j then
			return
		end
		local server = Flow.LiveJob(g, p, j.id)
		T.eq(server.salt, live.salt, "Auftrag übernimmt das Salz des Angebots")
		T.eq(server.finding, R.InspectionFinding(g:D(p), server.id, server.carId, server.salt), "Befund aus dem Salz")
		local client = Flow.Job(g, p, j.id)
		T.eq(client.finding, nil, "Befund vor dem Scan nicht auf dem Client")
		T.eq(client.salt, nil, "Salz nie auf dem Client")
		-- Abbrechen: dasselbe Salz kommt als Check-Angebot zurück
		local salt = server.salt
		g:Send(p, "confirm", { key = "cancel", id = j.id })
		local c = g:Last(p, "confirm")
		g:Send(p, "commit", { token = c and c.token })
		T.eq(Flow.LiveJob(g, p, j.id), nil, "Auftrag abgebrochen")
		local back = 0
		for _, o in ipairs(g:D(p).offers) do
			if o.kind == "inspection" then
				back += 1
				T.eq(o.salt, salt, "gleiches Salz nach dem Abbrechen")
			end
		end
		T.eq(back, 1, "genau ein Check-Angebot")
		-- Kundenentscheidung hängt am Salz (Client kann sie nicht aus der Auftrags-ID berechnen)
		local diff = 0
		for i = 1, 60 do
			local a = R.CustomerDecision({ id = "job_1", salt = i })
			if a ~= R.CustomerDecision({ id = "job_1", salt = i + 1000 }) then
				diff += 1
			end
		end
		T.check(diff > 0, "Entscheidung hängt vom Salz ab")
		-- Nach dem Scan sieht der Client den Befund
		local j2 = Flow.AcceptInspection(T, g, p, { finding = "oil" })
		if not j2 then
			return
		end
		T.eq(Flow.Job(g, p, j2.id).finding, nil, "erzwungener Befund vor dem Scan verborgen")
		Flow.Scan(T, g, p, j2.id, { auto = true })
		T.eq(Flow.Job(g, p, j2.id).finding, "oil", "Befund nach dem Scan sichtbar")
		-- Spielstand: Salz bleibt erhalten
		local raw = R.NewData(0)
		raw.jobs = { { id = "job_9", kind = "inspection", carId = "komet", bay = 1, phase = "diagnose", step = 1, salt = 4242 } }
		T.eq(R.LoadData(raw, nil, 0).jobs[1].salt, 4242, "Salz im Spielstand")
		T.check(C.Inspection ~= nil, "Config")
		noErrors(T, g)
	end },
}
