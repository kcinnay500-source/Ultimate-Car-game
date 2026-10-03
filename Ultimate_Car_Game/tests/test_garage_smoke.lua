-- Smoke-Tests: echter 2.4.0-Server (GarageServer + Module) im Mock, Basisbaum aus dem Place.
-- Jeder Fall läuft zweimal: "base" = unveränderte 2.4.0-Skripte (tests/fixtures/base_scripts.lua),
-- "src" = aktuelle Skripte aus src/** (Zuordnung wie tools/build_place.py). Beide müssen dasselbe
-- 2.4.0-Verhalten zeigen; die Werte (Zeiten, Belohnungen) werden aus Config/Rules bzw. den Events gelesen.

local MODES = { "base", "src" }

local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "Laufzeitfehler") .. ": " .. g:ErrorText())
end

local function findOffer(g, p, kind)
	for _, o in ipairs(g:Data(p).offers) do
		if o.kind == kind then
			return o
		end
	end
end

local function job(g, p, id)
	for _, j in ipairs(g:Data(p).jobs) do
		if j.id == id then
			return j
		end
	end
end

-- Am Empfang annehmen; liefert die Job-Tabelle aus dem letzten state
local function acceptInspection(T, g, p)
	g:Teleport(p, g:Station(p, "workshop"), Vector3.new(0, 0, 3))
	local offer = findOffer(g, p, "inspection")
	T.check(offer ~= nil, "Inspektionsauftrag im Angebot")
	if not offer then
		return nil
	end
	local m = g:Mark()
	g:Send(p, "accept", { id = offer.id })
	T.check(g:HasToast(p, "Auftrag angenommen", m), "Toast 'Auftrag angenommen'")
	local d = g:Data(p)
	T.eq(#d.jobs, 1, "ein Auftrag aktiv")
	-- 3.0: Befund des Fahrzeug-Checks hängt am server-geheimen Salz (zufällig): für diese Abläufe „kein Befund“
	local ok, live = pcall(function()
		return g:D(p)
	end)
	if ok and live and live.jobs[1] and live.jobs[1].kind == "inspection" and live.jobs[1].phase == "diagnose" then
		live.jobs[1].finding = nil
	end
	return d.jobs[1]
end

-- OBD-Scan am DiagnosticPoint; wartet 2,5 s und liefert das diagnose-Event
local function scan(T, g, p, car, jobId)
	g:Send(p, "tool", { id = "scanner" })
	g:Teleport(p, car.DiagnosticPoint, Vector3.new(0, 0, 1.5))
	local m = g:Mark()
	g:Send(p, "scan", { id = jobId })
	local s = g:Last(p, "scan", m)
	T.check(s ~= nil, "scan-Event gesendet")
	T.near(s and s.duration, 2.5, 1e-9, "Scan-Dauer")
	g:Advance(2.7)
	return g:Last(p, "diagnose", m), m
end

-- Ein Reparaturschritt: Werkzeug wählen, zum Punkt gehen, QTE starten, in der Mitte der grünen Zone treffen
local function repairStep(T, g, p, C, jobId, stepIndex)
	local car = g:Car(p, jobId)
	local step = C.JobById[job(g, p, jobId).kind].steps[stepIndex]
	g:Send(p, "tool", { id = step.tool })
	g:Teleport(p, car[step.point], Vector3.new(0, 0, 1.5))
	local m = g:Mark()
	g:Send(p, "work", { id = jobId, point = step.point })
	local c = g:Last(p, "challenge", m)
	if not T.check(c ~= nil, "Schritt " .. stepIndex .. ": challenge gesendet (Toasts: " .. table.concat(g:Toasts(p, m), " | ") .. ")") then
		return false
	end
	T.eq(c.kind, "gauge", "QTE-Art")
	-- Erster Durchlauf: Position = (t-startAt)/period -> Mitte bei startAt + center*period
	local at = c.startAt + c.center * c.period
	g:AdvanceTo(at)
	m = g:Mark()
	g:Send(p, "hit", { token = c.token, at = g:Now() })
	T.check(g:HasToast(p, "Arbeit läuft", m), "Schritt " .. stepIndex .. ": Treffer startet die Arbeit (Toasts: " .. table.concat(g:Toasts(p, m), " | ") .. ")")
	T.check(g:Last(p, "workFX", m) ~= nil, "workFX gesendet")
	local j = job(g, p, jobId)
	T.eq(j.phase, "working", "Phase nach Treffer")
	T.eq(j.quality, 100, "Qualität nach sauberem Treffer")
	-- Arbeit läuft im Hintergrund; der 0,5-s-Tick schaltet weiter
	g:AdvanceTo(j.workUntil + 0.6)
	return true
end

local cases = {}

for _, mode in ipairs(MODES) do
	local function case(name, fn)
		table.insert(cases, { name .. " [" .. mode .. "]", fn })
	end

	case("Serverstart, Beitritt: Plot, leaderstats, state", function(T, H)
		local g = H.Garage({ scripts = mode })
		noErrors(T, g, "Serverstart")
		T.check(g:Find("ServerStorage.PlotTemplate") ~= nil, "PlotTemplate in ServerStorage")
		T.check(g:Find("Workspace.Werkstatt") == nil, "Werkstatt-Vorlage aus dem Workspace entfernt")
		local p = g:Join(1001)
		g:Advance(1)
		noErrors(T, g, "nach Beitritt")
		local plot = g:Plot(p)
		T.check(plot ~= nil, "Plot_1001 erstellt")
		T.eq(plot and plot:GetAttribute("OwnerUserId"), 1001, "OwnerUserId am Plot")
		local st = g:State(p)
		T.check(st ~= nil and st.data ~= nil, "state gesendet")
		if not st then
			return
		end
		local C = g:Config()
		T.eq(st.data.version, 2, "data.version")
		T.eq(st.data.level, 1, "Startlevel")
		T.eq(st.data.money, C.StartMoney or st.data.money, "Startgeld")
		T.check(findOffer(g, p, "inspection") ~= nil, "Inspektion immer im Angebot")
		T.eq(st.plot, plot, "state.plot ist das eigene Modell")
		local ls = p:FindFirstChild("leaderstats")
		T.check(ls ~= nil and ls:FindFirstChild("Credits") ~= nil and ls:FindFirstChild("Level") ~= nil, "leaderstats Credits/Level")
		T.eq(ls and ls.Credits.Value, math.floor(st.data.money), "Credits = Geld")
		-- Figur steht nach dem Spawn am Empfang (moveTo Stations.home) und hält das Werkzeug
		local root = g:Root(p)
		local home = g:Station(p, "home")
		T.check(root and home and (root.Position - home.Position).Magnitude < 12, "Figur an Stations.home")
		if mode == "base" then
			T.check(p.Character:FindFirstChild("GarageTool") ~= nil, "Werkzeug in der Hand (F.Equip)")
		else
			-- 3.0: Start mit freier Hand (kein Werkzeug-Modell); Werkzeug erst bei Bedarf (Auswahl oder E)
			T.eq(st.tool, "hand", "state.tool = freie Hand")
			T.check(p.Character:FindFirstChild("GarageTool") == nil, "freie Hand: kein Werkzeug in der Hand")
			g:Send(p, "tool", { id = "scanner" })
			T.check(p.Character:FindFirstChild("GarageTool") ~= nil, "Werkzeug gewählt: in der Hand (F.Equip)")
			g:Advance(0.2)
			g:Send(p, "tool", { id = "hand" })
			T.eq(g:State(p).tool, "hand", "zurück zur freien Hand")
			T.check(p.Character:FindFirstChild("GarageTool") == nil, "Hand wieder frei")
		end
		-- Zweiter Spieler bekommt einen anderen Slot
		local p2 = g:Join(1002)
		g:Advance(0.6)
		local plot2 = g:Plot(p2)
		T.check(plot2 ~= nil and plot2 ~= plot, "zweiter Plot")
		T.check(plot2 and (plot2:GetPivot().Position - plot:GetPivot().Position).Magnitude > 200, "Plots liegen auseinander")
		noErrors(T, g, "zwei Spieler")
	end)

	case("Reise und Auswahl", function(T, H)
		local g = H.Garage({ scripts = mode })
		local p = g:Join(1001)
		g:Advance(0.6)
		for _, key in ipairs({ "tools", "parts", "upgrades", "workshop" }) do
			g:Advance(0.2) -- request() hat 0,12 s Abklingzeit je Aktionsname
			local m = g:Mark()
			g:Send(p, "travel", { key = key })
			T.eq(g:Last(p, "page", m), key, "page nach travel " .. key)
			local d = (g:Root(p).Position - g:Station(p, key).Position).Magnitude
			T.check(d <= (key == "tools" and 9 or 10), "travel " .. key .. " landet in Reichweite (" .. string.format("%.1f", d) .. ")")
		end
		g:Advance(0.2)
		local m = g:Mark()
		g:Send(p, "travel", { key = "nirgendwo" })
		T.eq(#g:Events(p, nil, m), 0, "unbekanntes Ziel wird ignoriert")
		-- Zwei Aufträge annehmen geht nur mit einer Bühne nicht -> select auf den einen
		local j = acceptInspection(T, g, p)
		if not j then
			return
		end
		g:Advance(0.2)
		g:Send(p, "select", { id = j.id })
		T.eq(g:State(p).selected, j.id, "select setzt selected")
		g:Send(p, "select", { id = "job_gibtsnicht" })
		g:Advance(0.2)
		T.eq(g:State(p).selected, j.id, "select auf fremde ID ändert nichts")
		-- target{car} teleportiert zum OBD-Anschluss
		g:Advance(0.2)
		g:Send(p, "target", { id = j.id, car = true })
		local car = g:Car(p, j.id)
		T.check((g:Root(p).Position - car.DiagnosticPoint.Position).Magnitude <= 8, "target{car} in OBD-Reichweite")
		noErrors(T, g)
	end)

	case("Annehmen nur am Empfang; Auto erscheint auf Bühne 1", function(T, H)
		local g = H.Garage({ scripts = mode })
		local p = g:Join(1001)
		g:Advance(0.6)
		-- Werkzeugkiste liegt > 50 Studs vom Empfang entfernt
		g:Teleport(p, g:Station(p, "tools"), Vector3.new(0, 0, 3))
		local offer = findOffer(g, p, "inspection")
		local m = g:Mark()
		g:Send(p, "accept", { id = offer.id })
		T.check(g:HasToast(p, "Gehe zuerst zum Empfang", m), "fern vom Empfang abgelehnt")
		T.eq(#g:Data(p).jobs, 0, "kein Auftrag")
		g:Advance(0.2)
		local j = acceptInspection(T, g, p)
		if not j then
			return
		end
		T.eq(j.bay, 1, "Bühne 1")
		T.eq(j.phase, "diagnose", "Phase diagnose")
		local car = g:Car(p, j.id)
		T.check(car ~= nil, "Auto-Modell in ActiveCars")
		local origin = g:Plot(p).Bays.Bay_1.CarOrigin
		T.check(car and (car:GetPivot().Position - origin.Position).Magnitude < 1, "Auto an CarOrigin")
		T.eq(car and car:GetAttribute("OwnerUserId"), 1001, "Auto-Besitzer")
		noErrors(T, g)
	end)

	case("Kompletter Reparaturablauf (Inspektion)", function(T, H)
		local g = H.Garage({ scripts = mode })
		local C = g:Config()
		local p = g:Join(1001)
		g:Advance(0.6)
		local money0, xp0, completed0 = g:Data(p).money, g:Data(p).xp, g:Data(p).completed
		local j = acceptInspection(T, g, p)
		if not j then
			return
		end
		local def = C.JobById[j.kind]
		local car = g:Car(p, j.id)
		-- Diagnose: falscher Scan-Ort, dann richtig
		g:Send(p, "tool", { id = "scanner" })
		g:Advance(0.2)
		local m = g:Mark()
		g:Send(p, "scan", { id = j.id })
		T.check(g:HasToast(p, "OBD-Anschluss", m), "Scan fern vom Auto abgelehnt")
		g:Advance(0.2)
		local diag = scan(T, g, p, car, j.id)
		T.check(diag ~= nil, "diagnose-Event nach 2,5 s")
		if not diag then
			return
		end
		T.eq(diag.job, j.id, "diagnose.job")
		if mode == "base" then
			T.eq(#diag.answers, #def.answers, "Antwortmöglichkeiten")
			T.eq(job(g, p, j.id).scanReady, true, "scanReady")
			-- falsche Antwort kostet 5 Qualität? Nein – im Smoke-Test richtig antworten, Qualität bleibt 100
			m = g:Mark()
			g:Send(p, "diagnose", { id = j.id, choice = def.cause })
			T.eq(g:Last(p, "diagnosisDone", m), j.id, "diagnosisDone")
		else
			-- 3.0: der Fahrzeug-Check liest den Fehlerspeicher (OBD-Tester), keine Multiple-Choice-Antworten
			T.eq(#diag.answers, 0, "Fahrzeug-Check ohne Antwortmöglichkeiten")
			T.check(type(diag.codes) == "table" and type(diag.live) == "table", "Fehlercodes und Messwerte")
			T.check(type(diag.message) == "string" and diag.message:find("gespeichert", 1, true) ~= nil, "Meldung Fehlerspeicher")
			if job(g, p, j.id).phase == "approval" then
				-- Fehler gespeichert: Kunde per Handy fragen (Antwort bestimmt der Server)
				T.check(#diag.codes > 0, "Befund hat Fehlercodes")
				g:Send(p, "call", { id = j.id })
				g:Advance(C.Inspection.RingSeconds + 0.3)
				j = job(g, p, j.id)
				def = C.JobById[j.kind]
			else
				T.eq(#diag.codes, 0, "kein Befund: Fehlerspeicher leer")
			end
		end
		T.eq(job(g, p, j.id).phase, "repair", "Phase repair")
		-- Reparaturschritte
		for i = 1, #def.steps do
			g:Advance(0.2)
			if not repairStep(T, g, p, C, j.id, i) then
				return
			end
			local cur = job(g, p, j.id)
			if i < #def.steps then
				T.eq(cur.phase, "repair", "nach Schritt " .. i .. " wieder repair")
				T.eq(cur.step, i + 1, "Schritt weitergezählt")
			else
				T.eq(cur.phase, "verify", "nach letztem Schritt verify")
			end
		end
		-- Endkontrolle
		local verify = scan(T, g, p, car, j.id)
		T.check(verify ~= nil, "Endkontrolle meldet Bericht")
		T.eq(job(g, p, j.id).phase, "invoice", "Phase invoice")
		-- Abrechnen am Empfang
		g:Send(p, "settle", { id = j.id })
		T.eq(job(g, p, j.id).phase, "invoice", "settle fern vom Empfang wirkt nicht")
		g:Teleport(p, g:Station(p, "workshop"), Vector3.new(0, 0, 3))
		g:Advance(0.2)
		m = g:Mark()
		g:Send(p, "settle", { id = j.id })
		local receipt = g:Last(p, "receipt", m)
		T.check(receipt ~= nil, "receipt-Event")
		if not receipt then
			return
		end
		T.eq(receipt.quality, 100, "Qualität 100")
		T.check(receipt.money > 0 and receipt.xp > 0, "Belohnung positiv")
		local d = g:Data(p)
		T.eq(#d.jobs, 0, "Auftrag abgeschlossen")
		T.eq(d.completed, completed0 + 1, "completed +1")
		T.check(d.money >= money0 + receipt.money, "Geld gutgeschrieben")
		T.check(d.level > 1 or d.xp == xp0 + receipt.xp, "XP gutgeschrieben")
		g:Advance(0.6)
		T.check(g:Car(p, j.id) == nil, "Auto nach Abrechnung entfernt")
		-- Replay ist wirkungslos
		m = g:Mark()
		g:Send(p, "settle", { id = j.id })
		T.eq(g:Last(p, "receipt", m), nil, "zweites settle ohne receipt")
		noErrors(T, g)
	end)

	case("QTE: Fehlschlag kostet Qualität, veraltetes Token wird ignoriert", function(T, H)
		local g = H.Garage({ scripts = mode })
		local C = g:Config()
		local p = g:Join(1001)
		g:Advance(0.6)
		local j = acceptInspection(T, g, p)
		if not j then
			return
		end
		local def = C.JobById[j.kind]
		local car = g:Car(p, j.id)
		scan(T, g, p, car, j.id)
		g:Send(p, "diagnose", { id = j.id, choice = def.cause })
		local step = def.steps[1]
		g:Send(p, "tool", { id = step.tool })
		g:Teleport(p, car[step.point], Vector3.new(0, 0, 1.5))
		g:Advance(0.2)
		local m = g:Mark()
		g:Send(p, "work", { id = j.id })
		local c = g:Last(p, "challenge", m)
		if not T.check(c ~= nil, "challenge") then
			return
		end
		-- Außerhalb der grünen Zone (Position 0 = ganz links)
		g:AdvanceTo(c.startAt + 0.15)
		m = g:Mark()
		g:Send(p, "hit", { token = "falsch", at = g:Now() })
		T.eq(job(g, p, j.id).quality, 100, "falsches Token ohne Wirkung")
		g:Send(p, "hit", { token = c.token, at = g:Now() })
		T.check(g:HasToast(p, "Knapp daneben", m), "Fehlschlag gemeldet")
		T.eq(job(g, p, j.id).quality, 98, "Qualität −2")
		T.eq(job(g, p, j.id).phase, "repair", "bleibt repair")
		-- Wegspringen bricht eine laufende Interaktion ab
		g:Advance(0.2)
		m = g:Mark()
		g:Send(p, "work", { id = j.id })
		T.check(g:Last(p, "challenge", m) ~= nil, "neue challenge")
		g:Teleport(p, g:Station(p, "workshop"), Vector3.new(0, 0, 3))
		g:Advance(0.6)
		T.check(#g:Events(p, "interactionReset", m) > 0, "interactionReset nach Entfernen")
		noErrors(T, g)
	end)

	case("Speichern beim Verlassen, Sperre frei, Wiederbeitritt stellt her", function(T, H)
		local g = H.Garage({ scripts = mode })
		local C = g:Config()
		local p = g:Join(1001)
		g:Advance(1)
		local rec0 = g:Record(1001)
		T.check(rec0 ~= nil, "Laden schreibt den normalisierten Datensatz sofort")
		T.check(rec0 and rec0.lock ~= nil and type(rec0.lock.token) == "string", "Sperre gesetzt während der Sitzung")
		-- Geld/Level über einen echten Auftrag ändern wäre lang; stattdessen gespeicherten Stand vorgeben
		g:Leave(p)
		g:Advance(15)
		noErrors(T, g, "Verlassen")
		local rec = g:Record(1001)
		T.check(rec ~= nil, "Datensatz vorhanden")
		if not rec then
			return
		end
		T.eq(rec.version, 2, "Hülle version")
		T.check(type(rec.data) == "table", "Hülle data")
		T.check(type(rec.receipts) == "table", "Hülle receipts")
		T.eq(rec.lock, nil, "Sperre freigegeben")
		T.eq(rec.data.version, 2, "data.version bleibt 2")
		T.check(g:Plot(p) == nil, "Plot nach Verlassen entfernt")
		for k in pairs(rec) do
			T.check(k == "version" or k == "data" or k == "receipts" or k == "lock", "keine fremden Hüllenfelder (" .. tostring(k) .. ")")
		end
		-- Veränderten Stand vorgeben und neu laden (gleiche "Cloud", neuer Server)
		rec.data.money = 4321
		rec.data.level = 3
		rec.data.xp = 10
		rec.data.completed = 7
		rec.receipts["kauf-1"] = true
		local g2 = H.Garage({ scripts = mode, shareDataStoresWith = g })
		local p2 = g2:Join(1001)
		g2:Advance(1)
		noErrors(T, g2, "Wiederbeitritt")
		local d = g2:Data(p2)
		T.check(d ~= nil, "state nach Wiederbeitritt")
		if not d then
			return
		end
		T.eq(d.money, 4321, "Geld wiederhergestellt")
		T.eq(d.level, 3, "Level wiederhergestellt")
		T.eq(d.completed, 7, "completed wiederhergestellt")
		T.eq(p2.leaderstats.Level.Value, 3, "leaderstats Level")
		local rec2 = g2:Record(1001)
		T.check(rec2.receipts["kauf-1"] == true, "receipts bleiben erhalten")
		T.check(rec2.lock ~= nil, "neue Sperre")
		T.eq(C.DataStoreName, "UltimateCarGame_v2", "DataStore-Name")
	end)

	case("Fremde, frische Sperre: temporäre Sitzung überschreibt nichts", function(T, H)
		local g = H.Garage({ scripts = mode })
		local record = { version = 2, data = { version = 2, money = 999, level = 2 }, receipts = {},
			lock = { token = "anderer-server", expires = os.time() + 170 } }
		g:Seed(1001, record)
		local p = g:Join(1001)
		g:Advance(16) -- 3.0: Profiles.Load wartet bis zu ProfileLockRetries Sekunden auf die fremde Sperre
		noErrors(T, g)
		local st = g:State(p)
		T.check(st ~= nil, "state trotz Sperre")
		g:Leave(p)
		g:Advance(15)
		local rec = g:Record(1001)
		T.eq(rec.lock and rec.lock.token, "anderer-server", "fremde Sperre unangetastet")
		T.eq(rec.data.money, 999, "gespeicherte Daten unangetastet")
	end)

	case("Robux-Kauf (ProcessReceipt): Gutschrift genau einmal, Beleg gespeichert", function(T, H)
		local g = H.Garage({ scripts = mode })
		local C = g:Config()
		local product = C.CreditProducts[1]
		product.productId = 424242 -- in 2.4.0 noch 0 (Platzhalter); nur für den Test gesetzt
		local p = g:Join(1001)
		g:Advance(1)
		local money0 = g:Data(p).money
		local m = g:Mark()
		local decision, done = g:Purchase(p, 424242, "kauf-A")
		T.check(done, "ProcessReceipt kehrt zurück")
		T.eq(decision, Enum.ProductPurchaseDecision.PurchaseGranted, "PurchaseGranted")
		T.eq(g:Data(p).money, money0 + product.credits, "Credits gutgeschrieben")
		T.check(g:Last(p, "purchaseFX", m) ~= nil, "purchaseFX gesendet")
		local rec = g:Record(1001)
		T.check(rec and rec.receipts["kauf-A"] ~= nil, "Beleg im DataStore")
		T.eq(rec and rec.data.money, money0 + product.credits, "Geld sofort gespeichert")
		-- Wiederholung desselben Belegs: gewährt, aber keine zweite Gutschrift
		decision = g:Purchase(p, 424242, "kauf-A")
		T.eq(decision, Enum.ProductPurchaseDecision.PurchaseGranted, "Wiederholung PurchaseGranted")
		T.eq(g:Data(p).money, money0 + product.credits, "keine Doppelgutschrift")
		-- Unbekanntes Produkt
		decision = g:Purchase(p, 999, "kauf-B")
		T.eq(decision, Enum.ProductPurchaseDecision.NotProcessedYet, "unbekanntes Produkt nicht verarbeitet")
		noErrors(T, g)
	end)

	case("BindToClose speichert alle und gibt Sperren frei", function(T, H)
		local g = H.Garage({ scripts = mode })
		local a = g:Join(1001)
		local b = g:Join(1002)
		g:Advance(1)
		g:Close()
		noErrors(T, g, "BindToClose")
		for _, id in ipairs({ 1001, 1002 }) do
			local rec = g:Record(id)
			T.check(rec ~= nil and rec.version == 2, "Datensatz " .. id)
			T.eq(rec and rec.lock, nil, "Sperre " .. id .. " frei")
		end
		local _ = a, b
	end)
end

return cases
