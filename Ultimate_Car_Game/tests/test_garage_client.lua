-- Client-Smoke-Test: echter 2.4.0-GarageClient (LocalScripts aus StarterPlayerScripts) gegen den echten Server.
-- Läuft für die unveränderten 2.4.0-Skripte ("base") und für src/** ("src").
local MODES = { "base", "src" }

local function tabletTitle(g, p)
	return g:FindGui(p, "/ ULTIMATE CAR GAME")
end

local cases = {}
for _, mode in ipairs(MODES) do
	table.insert(cases, { "Client: Tablet, Diagnose, Fahrzeugaktion E, QTE per Leertaste [" .. mode .. "]", function(T, H)
		local g = H.Garage({ scripts = mode })
		local C = g:Config()
		local p = g:Join(1001)
		g:StartClient(p)
		g:Advance(1)
		T.eq(#g:Errors(), 0, "Client-Start ohne Laufzeitfehler: " .. g:ErrorText())
		-- Tablet ist zu Beginn offen; Tab schließt und öffnet es wieder
		T.check(tabletTitle(g, p) ~= nil, "Tablet anfangs offen")
		T.eq(g:Key(p, Enum.KeyCode.Tab), true, "Tab wird geschluckt (ContextActionService)")
		g:Advance(0.3)
		T.check(tabletTitle(g, p) == nil, "Tab schließt das Tablet")
		T.check(g:FindGui(p, "Menü [Tab]") ~= nil, "HUD-Knopf 'Menü [Tab]' sichtbar")
		g:Key(p, Enum.KeyCode.Tab)
		g:Advance(0.3)
		T.check(tabletTitle(g, p) ~= nil, "Tab öffnet das Tablet")

		-- Auftrag annehmen (Figur steht nach dem Spawn am Empfang), diagnostizieren
		local offer
		for _, o in ipairs(g:Data(p).offers) do
			if o.kind == "inspection" then
				offer = o
			end
		end
		if not T.check(offer ~= nil, "Inspektion im Angebot") then
			return
		end
		g:Send(p, "accept", { id = offer.id })
		g:Advance(0.2)
		local job = g:Data(p).jobs[1]
		if not T.check(job ~= nil, "Auftrag angenommen") then
			return
		end
		local def = C.JobById[job.kind]
		-- 3.0: Befund des Fahrzeug-Checks hängt am server-geheimen Salz (zufällig): hier „kein Befund“
		local okLive, live = pcall(function()
			return g:D(p)
		end)
		if okLive and live and live.jobs[1] and live.jobs[1].kind == "inspection" then
			live.jobs[1].finding = nil
		end
		g:Send(p, "target", { id = job.id, car = true })
		g:Send(p, "scan", { id = job.id })
		g:Advance(3)
		T.check(g:FindGui(p, "Fahrzeugdiagnose") ~= nil, "Diagnose-Dialog sichtbar")
		g:Send(p, "diagnose", { id = job.id, choice = def.cause })
		g:Advance(0.3)
		local closeBtn = g:FindGui(p, "Schließen", { class = "TextButton" })
		if closeBtn then
			g:Click(closeBtn)
		end
		T.eq(g:Data(p).jobs[1].phase, "repair", "Phase repair")

		-- Am ersten Reparaturpunkt erscheint die Fahrzeugaktion E; Klick startet den QTE
		local step = def.steps[1]
		g:Send(p, "tool", { id = step.tool })
		local car = g:Car(p, job.id)
		g:Teleport(p, car[step.point], Vector3.new(0, 0, 2))
		g:Advance(0.5)
		local va = g:FindGui(p, function(x)
			return x.Name == "VehicleAction_E"
		end)
		if not T.check(va ~= nil, "Knopf VehicleAction_E sichtbar") then
			return
		end
		local m = g:Mark()
		g:Click(va)
		local ch = g:Last(p, "challenge", m)
		if not T.check(ch ~= nil, "challenge nach Klick") then
			return
		end
		T.check(g:FindGui(p, "Präzise arbeiten") ~= nil, "QTE-Dialog 'Präzise arbeiten'")
		-- In der Mitte der grünen Zone die Leertaste drücken
		g:AdvanceTo(ch.startAt + ch.center * ch.period)
		m = g:Mark()
		T.eq(g:Key(p, Enum.KeyCode.Space), true, "Leertaste wird im QTE geschluckt")
		local hitAt
		for _, a in ipairs(g:Remote("Command").__data.sentToServer) do
			if a[1] == "hit" then
				hitAt = a[2].at
			end
		end
		T.check(hitAt ~= nil, "Client sendet hit")
		T.check(g:HasToast(p, "Arbeit läuft", m), "Treffer startet die Arbeit")
		g:Advance(0.5)
		T.eq(g:Data(p).jobs[1].phase, "working", "Phase working")
		T.eq(g:Data(p).jobs[1].quality, 100, "Qualität 100")
		T.check(g:FindGui(p, "Präzise arbeiten") == nil, "QTE-Dialog geschlossen")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
		T.eq(#g:Warnings(), 0, "keine Warnungen: " .. table.concat(g:Warnings(), " | "))
	end })
end
return cases
