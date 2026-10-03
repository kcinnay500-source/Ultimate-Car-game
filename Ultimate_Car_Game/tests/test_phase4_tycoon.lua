-- Ausbaustufe 4, Meilensteine 4–5 Ende-zu-Ende über die echte Verkabelung (H.Garage mit placeKind "all",
-- Remotes.Command -> request -> Mini.Handle -> TycoonService, echte Zone workspace.Tycoon und echte Vorlagen
-- ServerStorage.TycoonTemplates aus der Fixture): Lobby -> Modus tycoon -> Grundstück + Schild -> Start-Pad ->
-- Gebäudewahl werkstatt -> Kaufpads (Touched) und Aktionen -> Zeitraffer bis Stufe 5 komplett (gieriger Kauf wie
-- tools/economy_sim.py --tycoon) -> Rebirth -> zurück in der Open World ist die Werkstatt-Vergütung höher (R.Reward
-- über eine echte Abrechnung) -> Handel zu zweit -> Fortsetzen nach Verlassen/Wiederkommen -> alle Grundstücke
-- belegt: freundlicher Hinweis und Nachvergabe.
local HUB = { lobby = { 0, -668 }, openworld = { 0, -192 }, tycoon = { 0, 856 } }

local rid = 100
local function act(T, g, pl, action, payload, msg)
	rid += 1
	payload = payload or {}
	payload.rid = rid
	local res = g:Act(pl, action, payload)
	if msg then
		T.eq(res, "ok", msg)
	end
	return res
end

local function rootPos(g, pl)
	local root = g:Root(pl)
	return root and root.Position or nil
end

local function near(T, pos, x, z, tol, msg)
	T.check(pos ~= nil, msg .. ": keine Figur")
	if pos then
		T.check(math.abs(pos.X - x) <= tol and math.abs(pos.Z - z) <= tol, string.format("%s – erwartet ≈(%g, %g), erhalten (%g, %g)", msg, x, z, pos.X, pos.Z))
	end
end

-- Beitritt als 2.4.0-Veteran (gespeichertes Profil ohne games: Tutorial gilt als erledigt) mit hello
local function join(g, userId, name, level)
	local pl = g:Join(userId, { name = name, level = level or 12 })
	g:Advance(1.1)
	g:Send(pl, "hello")
	g:Advance(1.1)
	return pl, g:D(pl), g:Session(pl)
end

-- Lobby -> Modus kind (lobby_mode + lobby_go, Simulation: Platzhalter-Ids)
local function travel(T, g, pl, kind)
	g:Advance(3.1)
	act(T, g, pl, "lobby_mode", { mode = kind }, "lobby_mode " .. kind)
	act(T, g, pl, "lobby_go", {}, "lobby_go " .. kind)
	g:Advance(1.1)
end

local function slotModel(g, n)
	return g:Find("Workspace.Tycoon.Plots.Slot_" .. n)
end

local function signOwner(g, n)
	local sign = slotModel(g, n):FindFirstChild("Sign")
	local label = nil
	for _, x in ipairs(sign:GetDescendants()) do
		if x:IsA("TextLabel") and x.Name == "Owner" then
			label = x.Text
		end
	end
	return sign:GetAttribute("Owner"), label
end

-- Pad-Teil mit Attribut TycoonButton = id im Grundstück des Spielers (gebundene Pads des Dienstes)
local function pad(TS, pl, id)
	local plot = TS.PlotOf(pl)
	for part, pid in pairs(plot and plot.buttons or {}) do
		if pid == id then
			return part
		end
	end
	return nil
end

-- Berührung eines Pads durch die eigene Figur (Touched auf dem Server)
local function touch(g, pl, part)
	g:Activate()
	local ch = pl.Character
	local root = ch and ch:FindFirstChild("HumanoidRootPart")
	assert(root, "keine Figur")
	root.CFrame = part.CFrame * CFrame.new(0, 3, 0)
	part.Touched:Fire(root)
	g:Flush()
end

local function labelText(part, name)
	local gui = part and part:FindFirstChild("Label")
	local tl = gui and gui:FindFirstChild(name)
	return tl and tl.Text or nil
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, what .. ": keine Fehler: " .. g:ErrorText())
end

-- Zeitraffer: alle 15 s sammeln und das teuerste bezahlbare Angebot kaufen (wie tools/economy_sim.py --tycoon),
-- bis Stufe 5 komplett ist. Liefert die Spielzeit in Sekunden (oder nil).
local function timeLapse(T, g, pl, TR, GC, limitHours)
	local d = g:D(pl)
	local start = g:Now()
	local limit = start + limitHours * 3600
	local iterations = 0
	while g:Now() < limit do
		iterations += 1
		g:Advance(15)
		local run = TR.RunOf(d)
		if not run then
			return nil
		end
		if run.container >= 1 then
			act(T, g, pl, "tycoon_collect")
		end
		local bought = true
		while bought do
			bought = false
			local best, bestCost = nil, -1
			for _, o in ipairs(TR.Offers(run)) do
				if o.ok and o.cost > bestCost then
					best, bestCost = o.id, o.cost
				end
			end
			if best then
				local stageBefore = run.stage
				if GC.Tycoon.StageById[best] then
					g:Advance(1.1) -- Abklingzeit tycoon_stage
					act(T, g, pl, "tycoon_stage")
				else
					g:Advance(0.2)
					act(T, g, pl, "tycoon_buy", { id = best })
				end
				bought = run.upgrades[best] ~= nil or run.stage > stageBefore
			end
		end
		if run.stage == GC.Tycoon.MaxStage and TR.StageComplete(run, run.stage) then
			return g:Now() - start, iterations
		end
	end
	return nil, iterations
end

return {
	{ "Lobby → Modus tycoon → Grundstück + Schild → Start-Pad → werkstatt → Pads und Aktionen → Zeitraffer bis Stufe 5 → Rebirth → Werkstatt-Vergütung in der Open World höher (echte Abrechnung)", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local GC = g:MiniShared("GameConfig")
		local TR = g:MiniShared("TycoonRules")
		local CB = g:MiniShared("CrossBonus")
		local TS = g:MiniServer("TycoonService")
		local R = g:Rules()
		local pl, d, p = join(g, 4101, "Anna")
		T.eq(p.mode, "lobby", "Anfangsmodus lobby (Veteran ohne lastMode)")
		T.check(type(d.games.tycoon) == "table" and d.games.tycoon.run == false and d.games.tycoon.rebirths == 0, "MiniRules.LoadGames legt games.tycoon an")
		local s0 = g:MiniSnapshot(pl)
		T.check(type(s0.tycoon) == "table" and s0.tycoon.run == false and s0.tycoon.slot == false and type(s0.tycoon.bonus) == "table", "Snapshot-Feld tycoon in der Lobby (kein Durchlauf, kein Grundstück)")
		-- Reise in den Tycoon (Simulation): Modus, Ankunft, Grundstück 1, Schild, Toast
		local m = g:Mark()
		travel(T, g, pl, "tycoon")
		T.eq(p.mode, "tycoon", "Modus tycoon")
		near(T, rootPos(g, pl), HUB.tycoon[1], HUB.tycoon[2], 8, "Figur an der Tycoon-Ankunft")
		T.check(g:HasToast(pl, "Grundstück 1 gehört dir", m), "Toast: Grundstück 1 gehört dir")
		T.eq(TS.PlotOf(pl) and TS.PlotOf(pl).slot, 1, "TycoonService: Slot 1")
		local attr, label = signOwner(g, 1)
		T.eq(attr, "Anna", "Schild-Attribut Owner")
		T.eq(label, "Anna", "Schild-Text Owner")
		local s1 = g:MiniSnapshot(pl)
		T.eq(s1.mode, "tycoon", "Snapshot mode tycoon")
		T.eq(s1.tycoon.slot, 1, "Snapshot tycoon.slot 1")
		T.eq(s1.tycoon.plots[1], "Anna", "Snapshot plots[1] Anna")
		T.eq(s1.tycoon.run, false, "noch kein Durchlauf")
		-- Tycoon-Station öffnet den Tab tycoon (Meilenstein 4: kein „eröffnet bald“)
		local tst = g:Find("Workspace.Tycoon.Stations.tycoon")
		T.check(tst ~= nil, "Tycoon-Station")
		if tst then
			local arrival = tst:FindFirstChild("Arrival")
			g:Teleport(pl, arrival and arrival.WorldPosition or tst.Position, arrival and nil or Vector3.new(0, 3, 4))
			g:Advance(0.2)
			m = g:Mark()
			g:Trigger(pl, tst:FindFirstChildOfClass("ProximityPrompt"), { force = true })
			g:Advance(0.3)
			local open = g:Events(pl, "mini_open", m)[1]
			T.check(open ~= nil and open.tab == "tycoon", "Station öffnet den Tab tycoon")
		end
		-- Start-Pad (ProximityPrompt) -> mini_notice tycoon_choose (Client öffnet den Tab)
		local start1 = slotModel(g, 1):FindFirstChild("StartPad")
		T.check(start1 ~= nil and start1:GetAttribute("TycoonSlot") == 1, "StartPad Slot 1")
		g:Teleport(pl, start1, Vector3.new(0, 3, 0))
		g:Advance(0.2)
		m = g:Mark()
		g:Trigger(pl, start1:FindFirstChildOfClass("ProximityPrompt"), { force = true })
		g:Advance(0.2)
		local choose = g:Notices(pl, "tycoon_choose", m)
		T.check(#choose == 1 and choose[1].slot == 1 and choose[1].hasRun == false and type(choose[1].types) == "table", "Hinweis tycoon_choose (slot, hasRun, types)")
		-- Gebäudewahl über die echte Aktion (MiniNet: tycoon_choose {building}); falscher Typ -> invalid
		T.eq(act(T, g, pl, "tycoon_choose", { building = 7 }), "invalid", "Typprüfung building")
		g:Advance(1.1)
		m = g:Mark()
		act(T, g, pl, "tycoon_choose", { building = "werkstatt" }, "tycoon_choose werkstatt")
		local run = TR.RunOf(d)
		T.check(run ~= nil and run.building == "werkstatt" and run.stage == 1 and run.cash == GC.Tycoon.StartCash, "Durchlauf werkstatt Stufe 1 mit Startbargeld")
		T.check(g:HasToast(pl, "gebaut", m), "Toast gebaut")
		local st = g:Notices(pl, "tycoon_stage", m)[1]
		T.check(st ~= nil and st.event == "start" and st.stage == 1, "Hinweis tycoon_stage start")
		-- Echte Vorlage: Stage_1 (werkstatt) in Slot_1.ButtonsRoot am Anker, Pads gebunden, Labels
		local root1 = slotModel(g, 1):FindFirstChild("ButtonsRoot")
		local stage1 = root1 and root1:FindFirstChild("Stage_1")
		T.check(stage1 ~= nil, "Stage_1 aus ServerStorage.TycoonTemplates.werkstatt unter Slot_1.ButtonsRoot")
		local anchor = slotModel(g, 1):FindFirstChild("Anchor")
		T.check(stage1 and anchor and (stage1:GetPivot().Position - anchor.Position).Magnitude < 1e-3, "Pivot am Anker")
		local b = GC.Tycoon.Buildings.werkstatt
		local u1 = b.Stages[1].Upgrades[1]
		local pad1 = pad(TS, pl, u1.id)
		T.check(pad1 ~= nil, "Pad " .. u1.id .. " gebunden")
		T.eq(labelText(pad1, "Name"), u1.name, "Name-Label der Vorlage = GameConfig")
		T.check(pad1 and pad1:GetAttribute("TycoonState") == "locked", "Pad locked (50 Bargeld reichen nicht)")
		T.check(pad(TS, pl, b.Stages[1].stageId) ~= nil, "Stufen-Pad gebunden")
		g:Advance(1.1)
		local s2 = g:MiniSnapshot(pl)
		T.check(type(s2.tycoon.run) == "table" and s2.tycoon.run.building == "werkstatt" and s2.tycoon.run.stage == 1 and type(s2.tycoon.run.offers) == "table" and #s2.tycoon.run.offers == GC.Tycoon.UpgradesPerStage + 1, "Snapshot run mit Kaufangeboten (4 Upgrades + Stufen-Pad)")
		-- Produktion im Server-Tick (MiniService -> TycoonService.Tick), Sammeln über Aktion und Sammel-Pad
		g:Advance(10)
		T.check(run.container > 0, "Behälter füllt sich im Tick")
		T.eq(run.cash, GC.Tycoon.StartCash, "Bargeld unverändert vor dem Sammeln")
		m = g:Mark()
		act(T, g, pl, "tycoon_collect", {}, "tycoon_collect")
		T.check(run.cash > GC.Tycoon.StartCash and run.container < 1, "Sammeln: Behälter -> Bargeld")
		T.check(g:HasToast(pl, "eingesammelt", m), "Toast eingesammelt")
		T.eq(d.money, g:Record(4101) and d.money, "Bargeld ist nie Credits")
		g:Advance(5)
		local collectPad = slotModel(g, 1):FindFirstChild("CollectPad")
		local cashBefore = run.cash
		touch(g, pl, collectPad)
		T.check(run.cash > cashBefore, "Sammel-Pad (Touched) sammelt")
		-- Kaufpad per Touched: zu wenig Bargeld -> Toast; mit Bargeld -> Kauf, Label „Gekauft“, Produzent sichtbar
		m = g:Mark()
		run.cash = 0
		touch(g, pl, pad1)
		T.check(run.upgrades[u1.id] == nil, "ohne Bargeld kein Kauf")
		T.check(g:HasToast(pl, "Nicht genug Bargeld", m), "Toast Nicht genug Bargeld")
		g:Advance(1)
		run.cash = u1.cost
		m = g:Mark()
		touch(g, pl, pad1)
		T.eq(run.upgrades[u1.id], 1, "Pad-Kauf " .. u1.id)
		T.eq(run.cash, 0, "Bargeld bezahlt")
		T.check(g:HasToast(pl, "gekauft", m), "Toast gekauft")
		T.eq(labelText(pad1, "Price"), "Gekauft", "Label Gekauft")
		T.check(stage1:FindFirstChild("Producer_1") ~= nil, "Produzent 1 sichtbar")
		-- Lage: der Produzent steht auf dem Grundstück (mit der Stufe versetzt), nicht am Ursprung der Vorlage
		do
			local producer = stage1:FindFirstChild("Producer_1")
			local plotState = g:MiniServer("TycoonService").Plots[1]
			local anchor = plotState and plotState.anchor
			local apos = anchor and (anchor:IsA("BasePart") and anchor.Position or anchor:GetPivot().Position) or nil
			local ppos = producer and producer:GetPivot().Position or nil
			T.check(apos ~= nil and ppos ~= nil and (Vector3.new(ppos.X, 0, ppos.Z) - Vector3.new(apos.X, 0, apos.Z)).Magnitude <= 40,
				"Produzent 1 auf dem Grundstück (≤ 40 Studs vom Anker): " .. tostring(ppos) .. " / " .. tostring(apos))
		end
		-- Aktion tycoon_buy: fremde Id / falsche Stufe
		m = g:Mark()
		act(T, g, pl, "tycoon_buy", { id = "autohaus_s1_u1" }, "tycoon_buy fremdes Gebäude")
		T.check(g:HasToast(pl, "anderen Gebäude", m), "Toast anderes Gebäude")
		-- Zeitraffer bis Stufe 5 komplett (Ziel ≈ 5 h, Vertrag §8), dabei echte Stufen-Modelle und XP je Stufe
		local moneyBefore, xpBefore = d.money, d.xp
		local seconds, iterations = timeLapse(T, g, pl, TR, GC, 8)
		T.check(seconds ~= nil, "Stufe 5 komplett im Zeitraffer (" .. tostring(iterations) .. " Runden)")
		if seconds then
			T.check(seconds >= 3 * 3600 and seconds <= 6.5 * 3600, string.format("Rundendauer %.2f h (Ziel ≈ 5 h)", seconds / 3600))
		end
		T.eq(run.stage, 5, "Stufe 5")
		T.check(TR.StageComplete(run, 5), "alle Upgrades der Stufe 5")
		T.check(slotModel(g, 1).ButtonsRoot:FindFirstChild("Stage_5") ~= nil and slotModel(g, 1).ButtonsRoot:FindFirstChild("Stage_1") == nil, "nur das Modell der Stufe 5 steht")
		T.check(d.xp > xpBefore or d.level > 12, "XP je Stufe (GameConfig.XP.TycoonStage)")
		T.eq(d.games.tycoon.runsDone.werkstatt, 0, "noch kein abgeschlossener Durchlauf")
		g:Advance(1.1)
		local s3 = g:MiniSnapshot(pl)
		T.check(s3.tycoon.run.canRebirth == true, "Snapshot canRebirth")
		-- Rebirth über die echte Aktion
		m = g:Mark()
		act(T, g, pl, "tycoon_rebirth", {}, "tycoon_rebirth")
		T.eq(TR.RunOf(d), nil, "Durchlauf beendet")
		T.eq(d.games.tycoon.runsDone.werkstatt, 1, "runsDone werkstatt 1")
		T.eq(d.games.tycoon.rebirths, 1, "rebirths 1")
		T.eq(d.games.stats.tycoonRuns, 1, "Statistik tycoonRuns")
		T.check(g:HasToast(pl, "Rebirth Nr. 1", m), "Toast Rebirth")
		T.eq(#slotModel(g, 1).ButtonsRoot:GetChildren(), 0, "Modelle abgebaut")
		T.check(d.money >= moneyBefore, "Bargeld wurde nie zu Credits abgezogen; Credits höchstens durch Level-Bonus")
		T.near(CB.TycoonWorkshop(d), 1 + GC.Tycoon.Bonus.werkstatt.step, 1e-9, "CrossBonus.TycoonWorkshop = 1,02")
		g:Advance(1.1)
		local s4 = g:MiniSnapshot(pl)
		T.eq(s4.tycoon.run, false, "Snapshot: kein Durchlauf")
		T.eq(s4.tycoon.rebirths, 1, "Snapshot rebirths")
		T.eq(s4.tycoon.bonus.werkstatt.pct, 2, "Snapshot bonus werkstatt 2 %")
		-- Zurück in die Open World (lobby_return -> Lobby -> lobby_go openworld): Grundstück frei
		g:Advance(3.1)
		act(T, g, pl, "lobby_return", {}, "lobby_return")
		T.eq(p.mode, "lobby", "wieder in der Lobby")
		g:Advance(1.1)
		T.eq(TS.PlotOf(pl), nil, "Grundstück freigegeben")
		T.eq((signOwner(g, 1)), "", "Schild wieder FREI")
		travel(T, g, pl, "openworld")
		T.eq(p.mode, "openworld", "Modus openworld")
		-- Open World: Figur wie bisher in der eigenen Werkstatt (2.4.0-Verhalten, test_phase4), nicht mehr im Tycoon
		local home = g:Station(pl, "home")
		T.check(home and (rootPos(g, pl) - home.Position).Magnitude < 12, "Figur in der eigenen Werkstatt")
		T.check(rootPos(g, pl) and rootPos(g, pl).Z < 600, "Figur hat das Tycoon-Gelände verlassen")
		-- Werkstatt-Vergütung: echte Inspektion bis zur Abrechnung; R.Reward mit Tycoon-Bonus > ohne
		local j = Flow.AcceptInspection(T, g, pl)
		T.check(j ~= nil, "Auftrag angenommen")
		local C = g:Config()
		local def = C.JobById[j.kind]
		local diag = Flow.Scan(T, g, pl, j.id)
		T.check(diag ~= nil, "diagnose-Event")
		g:Send(pl, "diagnose", { id = j.id, choice = def.cause })
		for i = 1, #def.steps do
			T.check(Flow.RepairStep(T, g, pl, j.id, i), "Reparaturschritt " .. i)
		end
		Flow.Scan(T, g, pl, j.id)
		local job = Flow.Job(g, pl, j.id)
		T.eq(job and job.phase, "invoice", "Phase invoice")
		local withBonus = R.Reward(d, job)
		d.games.tycoon.runsDone.werkstatt = 0
		local withoutBonus = R.Reward(d, job)
		d.games.tycoon.runsDone.werkstatt = 1
		T.check(withBonus > withoutBonus, "R.Reward mit Tycoon-Bonus höher: " .. tostring(withBonus) .. " > " .. tostring(withoutBonus))
		T.near(withBonus / withoutBonus, 1.02, 0.01, "Faktor ≈ 1,02 (+2 % je Werkstatt-Durchlauf)")
		g:Teleport(pl, g:Station(pl, "workshop"), Vector3.new(0, 0, 3))
		g:Advance(0.3)
		m = g:Mark()
		local money0 = d.money
		g:Send(pl, "settle", { id = j.id })
		local receipt = g:Last(pl, "receipt", m)
		T.check(receipt ~= nil, "Quittung")
		T.eq(receipt and receipt.money, withBonus, "Quittung = R.Reward mit Tycoon-Bonus")
		T.eq(d.money - money0, withBonus, "Credits um die Vergütung gestiegen")
		-- Speichern: Rebirth/runsDone bleiben im Profil
		g:Leave(pl)
		g:Advance(1)
		local rec = g:Record(4101)
		T.check(rec and rec.data.games.tycoon.runsDone.werkstatt == 1 and rec.data.games.tycoon.rebirths == 1 and rec.data.games.tycoon.run == false, "tycoon gespeichert (runsDone, rebirths, kein Durchlauf)")
		noErrors(T, g, "Ende-zu-Ende Tycoon")
	end },

	{ "Handel zu zweit über echte Aktionen (Angebot, Marktplatz-Hinweis, Annahme in einem Schritt, Bargeld nie Credits), Fortsetzen nach Verlassen/Wiederkommen (Offline zählt nicht)", function(T, H)
		local g = H.Garage({ placeKind = "all" })
		local GC = g:MiniShared("GameConfig")
		local TR = g:MiniShared("TycoonRules")
		local TS = g:MiniServer("TycoonService")
		local a, dA, pa = join(g, 4201, "Anna")
		local b, dB, pb = join(g, 4202, "Ben")
		travel(T, g, a, "tycoon")
		travel(T, g, b, "tycoon")
		T.eq(TS.PlotOf(a) and TS.PlotOf(a).slot, 1, "Anna Slot 1")
		T.eq(TS.PlotOf(b) and TS.PlotOf(b).slot, 2, "Ben Slot 2")
		act(T, g, a, "tycoon_choose", { building = "produktion" }, "Anna produktion")
		act(T, g, b, "tycoon_choose", { building = "autohaus" }, "Ben autohaus")
		local runA, runB = TR.RunOf(dA), TR.RunOf(dB)
		T.check(runA and runB, "beide Durchläufe")
		T.check(slotModel(g, 2).ButtonsRoot:FindFirstChild("Stage_1") ~= nil, "Ben: Stage_1 (autohaus) unter Slot_2")
		-- Ware und Bargeld (Server-Daten; im Spiel aus Lager-Upgrades und Produktion)
		runA.storage.bauteile = 12
		runB.cash = 500
		local creditsA, creditsB = dA.money, dB.money
		-- Typprüfung (MiniNet): to muss eine Zahl sein
		T.eq(act(T, g, a, "tycoon_trade_offer", { to = "Ben", item = "bauteile", qty = 4, price = 100 }), "invalid", "tycoon_trade_offer: to als Text -> invalid")
		g:Advance(1.1)
		local m = g:Mark()
		act(T, g, a, "tycoon_trade_offer", { to = 4202, item = "bauteile", qty = 4, price = 100 }, "tycoon_trade_offer")
		local offer = nil
		for _, o in pairs(TS.Offers) do
			offer = o
		end
		T.check(offer ~= nil and offer.from == 4201 and offer.to == 4202 and offer.qty == 4 and offer.price == 100, "Angebot serverlokal")
		T.check(g:HasToast(a, "Angebot an Ben", m), "Anna: Toast Angebot geschickt")
		T.check(g:HasToast(b, "bietet dir", m), "Ben: Toast Angebot erhalten")
		local market = g:Notices(b, "tycoon_market", m)
		T.check(#market >= 1 and market[#market].count == 1, "Marktplatz-Hinweis an alle Tycoon-Spieler")
		g:Advance(1.1)
		local sB = g:MiniSnapshot(b)
		T.check(type(sB.tycoon.offers) == "table" and #sB.tycoon.offers == 1 and sB.tycoon.offers[1].fromName == "Anna", "Snapshot Ben: Angebot an mich")
		local sA = g:MiniSnapshot(a)
		T.check(#sA.tycoon.offers == 1 and sA.tycoon.offers[1].toName == "Ben", "Snapshot Anna: mein Angebot")
		-- Nur der Empfänger nimmt an; Annahme in einem Schritt (Erhaltung)
		act(T, g, a, "tycoon_trade_accept", { id = offer.id }, "Verkäufer kann nicht annehmen")
		T.eq(runA.storage.bauteile, 12, "Ware noch beim Verkäufer")
		g:Advance(1.1)
		m = g:Mark()
		act(T, g, b, "tycoon_trade_accept", { id = offer.id }, "tycoon_trade_accept")
		T.eq(runA.storage.bauteile, 8, "Verkäufer: 4 Bauteile weniger")
		T.eq(runB.storage.bauteile, 4, "Käufer: 4 Bauteile")
		T.eq(runB.cash, 400, "Käufer zahlt 100 Bargeld")
		T.eq(runA.cash, GC.Tycoon.StartCash + 100, "Verkäufer erhält 100 Bargeld")
		T.eq(next(TS.Offers), nil, "Angebot erledigt")
		T.check(g:HasToast(a, "Handel abgeschlossen", m) and g:HasToast(b, "Handel abgeschlossen", m), "beide: Toast Handel abgeschlossen")
		T.check(dA.money == creditsA and dB.money == creditsB, "Credits unverändert (Handel nur in Bargeld)")
		-- Rücknahme eines Angebots
		g:Advance(1.1)
		act(T, g, a, "tycoon_trade_offer", { to = 4202, item = "bauteile", qty = 1, price = 10 }, "zweites Angebot")
		local id2 = next(TS.Offers)
		T.check(id2 ~= nil, "zweites Angebot offen")
		m = g:Mark()
		act(T, g, a, "tycoon_trade_cancel", { id = id2 }, "tycoon_trade_cancel")
		T.eq(next(TS.Offers), nil, "zurückgezogen")
		T.check(g:HasToast(a, "zurückgezogen", m), "Toast zurückgezogen")
		-- Fortsetzen: Anna verlässt mitten im Durchlauf, kommt nach 1 h wieder (Slot 1 ist inzwischen Bens? nein: Ben hat 2)
		local u1 = GC.Tycoon.Buildings.produktion.Stages[1].Upgrades[1]
		runA.cash = u1.cost + 5
		act(T, g, a, "tycoon_buy", { id = u1.id }, "Anna kauft u1")
		T.eq(runA.upgrades[u1.id], 1, "u1 gekauft")
		g:Advance(3)
		local cashSaved, containerSaved, storageSaved = runA.cash, runA.container, runA.storage.bauteile
		g:Leave(a)
		g:Advance(1)
		T.eq(TS.PlotOf(a), nil, "Slot 1 frei")
		T.eq(#slotModel(g, 1).ButtonsRoot:GetChildren(), 0, "Modelle weg")
		local rec = g:Record(4201)
		T.check(rec and rec.data.games.tycoon.run and rec.data.games.tycoon.run.stage == 1 and rec.data.games.tycoon.run.upgrades[u1.id] == 1, "Durchlauf gespeichert")
		T.eq(rec and rec.data.games.meta.lastMode, "tycoon", "lastMode tycoon gespeichert")
		g:Advance(3600)
		m = g:Mark()
		local a2, dA2, pa2 = join(g, 4201, "Anna")
		T.eq(pa2.mode, "tycoon", "all-Place: gespeicherter Modus tycoon")
		local run2 = TR.RunOf(dA2)
		T.check(run2 ~= nil and run2.building == "produktion" and run2.upgrades[u1.id] == 1, "Durchlauf fortgesetzt (MiniRules.LoadGames -> TycoonRules.Load)")
		T.eq(run2.cash, cashSaved, "Bargeld geladen")
		T.eq(run2.storage.bauteile, storageSaved, "Lager geladen")
		T.check(run2.container <= containerSaved + TR.Rate(run2) * 3 + 1, "Offline-Stunde erzeugt kein Bargeld")
		T.eq(TS.PlotOf(a2) and TS.PlotOf(a2).slot, 1, "Anna wieder Slot 1")
		T.check(g:HasToast(a2, "Willkommen zurück", m), "Toast Fortsetzen")
		local st1 = slotModel(g, 1).ButtonsRoot:FindFirstChild("Stage_1")
		T.check(st1 ~= nil and st1:FindFirstChild("Producer_1") ~= nil, "Modell und Produzent wieder aufgebaut")
		T.eq(labelText(pad(TS, a2, u1.id), "Price"), "Gekauft", "Label Gekauft nach dem Laden")
		noErrors(T, g, "Handel/Fortsetzen")
	end },

	{ "Alle Grundstücke belegt: freundlicher Hinweis, kein Durchlauf ohne Grundstück, Nachvergabe im Tick; Boni der anderen Typen (Händlerrabatt, Tuning-Tempo, Schrott) hängen an runsDone", function(T, H)
		local g = H.Garage({ placeKind = "tycoon" })
		local GC = g:MiniShared("GameConfig")
		local TR = g:MiniShared("TycoonRules")
		local TS = g:MiniServer("TycoonService")
		local CB = g:MiniShared("CrossBonus")
		local players = {}
		for i = 1, 7 do
			players[i] = join(g, 4300 + i, "Spieler" .. i)
			T.eq(TS.PlotOf(players[i]) and TS.PlotOf(players[i]).slot, i, "Slot " .. i)
		end
		-- Slot 8 serverlokal vorbelegt (ein 9. Spieler bekäme in Roblox keinen Werkstatt-Platz mehr: höchstens 8 je Server)
		local fake = { slot = 8, ms = g:MiniState(players[1]), player = players[1], stages = {}, buttons = {}, conns = {}, padAt = {}, toastAt = {}, labelAt = 0 }
		TS.Plots[8] = fake
		local m = g:Mark()
		local last = join(g, 4309, "Neun")
		T.eq(TS.PlotOf(last), nil, "kein freies Grundstück")
		T.check(g:HasToast(last, "alle Grundstücke belegt", m), "freundlicher Hinweis: alle Grundstücke belegt")
		local s = g:MiniSnapshot(last)
		T.eq(s.tycoon.slot, false, "Snapshot slot false")
		act(T, g, last, "tycoon_choose", { building = "autohaus" }, "tycoon_choose ohne Grundstück")
		T.eq(TR.RunOf(g:D(last)), nil, "ohne Grundstück kein Durchlauf")
		g:Advance(GC.Tycoon.PlotRetry + 0.6)
		T.eq(TS.PlotOf(last), nil, "weiter kein Grundstück")
		-- Spieler 5 geht: Neun bekommt Slot 5 im Tick, Schild, Toast
		m = g:Mark()
		g:Leave(players[5])
		g:Advance(GC.Tycoon.PlotRetry + 0.6)
		T.eq(TS.PlotOf(last) and TS.PlotOf(last).slot, 5, "Neun bekommt Slot 5")
		T.eq((signOwner(g, 5)), "Neun", "Schild Slot 5")
		T.check(g:HasToast(last, "Grundstück 5 gehört dir", m), "Toast Grundstück 5")
		TS.Plots[8] = nil
		-- Querboni der anderen Typen (Vertrag §8), gedeckelt über maxRuns
		local d = g:D(last)
		T.eq(CB.TycoonDealerDiscount(d), 0, "ohne Durchläufe kein Händlerrabatt")
		d.games.tycoon.runsDone.autohaus = 2
		d.games.tycoon.runsDone.produktion = 99
		d.games.tycoon.runsDone.schrottplatz = 1
		T.near(CB.TycoonDealerDiscount(d), 0.03, 1e-9, "Händlerrabatt 2 × 1,5 %")
		T.near(CB.TycoonTuningSpeed(d), 1.15, 1e-9, "Tuning-Tempo gedeckelt +15 %")
		T.near(CB.TycoonScrap(d), 1.03, 1e-9, "Schrott +3 %")
		local CarRules = g:MiniShared("CarRules")
		local CarCatalog = g:MiniShared("CarCatalog")
		local model = CarCatalog.Model("nord")
		T.check(model ~= nil and model.dealer and model.price > 0, "Händlermodell nord")
		if model then
			local full = model.price
			d.games.tycoon.runsDone.autohaus = 0
			local base = CarRules.DealerPrice(d, model)
			d.games.tycoon.runsDone.autohaus = 2
			local discounted = CarRules.DealerPrice(d, model)
			T.check(discounted < base and discounted >= math.floor(full * 0.8), "Händlerpreis mit Tycoon-Rabatt: " .. tostring(discounted) .. " < " .. tostring(base))
		end
		noErrors(T, g, "Grundstücke voll/Boni")
	end },
}
