-- Ausbaustufe 4, Meilenstein 4 (Team service): TycoonService im echten Server (H.Garage, Zone workspace.Tycoon aus der
-- Fixture, eigene Aktionen-Tabelle wie test_lobby). Vorlagen ServerStorage.TycoonTemplates baut der Test selbst
-- (minimal, gleiche Struktur wie tools/worldgen). Grundstücke, Start-Pad, Gebäudewahl, Kaufpads (Touched), Sammeln,
-- Stufen bis 5, Rebirth (runsDone, XP, CrossBonus), Abbruch, Handel zwischen zwei Spielern, Fortsetzen nach dem
-- Verlassen, fremde Pads, Moduswechsel über die Lobby.
local NOW = 1760000000

---------------------------------------------------------------- Vorlagen (ServerStorage.TycoonTemplates.<typ>.Stage_n)
local BUTTON_LOCAL = { 6, 0.5, -20 } -- plotlokal: u1 bei x=6, u2 bei 12, ... (für die Rotationsprüfung)

local function buildTemplates(g, GC)
	g:Activate()
	local SS = g.env.services.ServerStorage
	local old = SS:FindFirstChild("TycoonTemplates")
	if old then
		old:Destroy()
	end
	local root = Instance.new("Folder")
	root.Name = "TycoonTemplates"
	root.Parent = SS
	local function label(part, name, price)
		local gui = Instance.new("SurfaceGui")
		gui.Name = "Label"
		gui.Parent = part
		local n = Instance.new("TextLabel")
		n.Name = "Name"
		n.Text = name
		n.Parent = gui
		local p = Instance.new("TextLabel")
		p.Name = "Price"
		p.Text = price
		p.Parent = gui
	end
	for _, typ in ipairs(GC.Tycoon.Types) do
		local b = GC.Tycoon.Buildings[typ]
		local folder = Instance.new("Folder")
		folder.Name = typ
		folder.Parent = root
		for s = 1, GC.Tycoon.MaxStage do
			local st = b.Stages[s]
			local m = Instance.new("Model")
			m.Name = "Stage_" .. s
			local rootPart = Instance.new("Part")
			rootPart.Name = "Root"
			rootPart.Anchored = true
			rootPart.Size = Vector3.new(1, 1, 1)
			rootPart.CFrame = CFrame.new(0, 0, 0)
			rootPart.Parent = m
			m.PrimaryPart = rootPart
			local halle = Instance.new("Part")
			halle.Name = "Halle"
			halle.Anchored = true
			halle.Size = Vector3.new(10 + 4 * s, 4 + 2 * s, 10 + 4 * s)
			halle.CFrame = CFrame.new(0, 2 + s, 0)
			halle.Parent = m
			local buttons = Instance.new("Folder")
			buttons.Name = "Buttons"
			buttons.Parent = m
			for k, u in ipairs(st.Upgrades) do
				local pad = Instance.new("Part")
				pad.Name = "Button_" .. k
				pad.Anchored = true
				pad.Size = Vector3.new(4, 0.5, 4)
				pad.CFrame = CFrame.new(BUTTON_LOCAL[1] * k, BUTTON_LOCAL[2], BUTTON_LOCAL[3] - 3 * s)
				pad:SetAttribute("TycoonButton", u.id)
				label(pad, u.name, tostring(u.cost))
				pad.Parent = buttons
			end
			if st.stageId then
				local pad = Instance.new("Part")
				pad.Name = "StagePad"
				pad.Anchored = true
				pad.Size = Vector3.new(6, 0.5, 6)
				pad.CFrame = CFrame.new(-20, 0.5, -20 - 3 * s)
				pad:SetAttribute("TycoonButton", st.stageId)
				label(pad, "Stufe " .. (s + 1), tostring(b.Stages[s + 1].price))
				pad.Parent = m
			end
			local hidden = Instance.new("Folder")
			hidden.Name = "Hidden"
			hidden.Parent = m
			local producer = Instance.new("Model")
			producer.Name = "Producer_1"
			local pp = Instance.new("Part")
			pp.Name = "Maschine"
			pp.Anchored = true
			pp.CFrame = CFrame.new(-10, 2, 5)
			pp.Parent = producer
			producer.Parent = hidden
			local cash = Instance.new("Part")
			cash.Name = "CashDisplay"
			cash.Anchored = true
			cash.CFrame = CFrame.new(0, 6, 8)
			cash.Parent = m
			local gui = Instance.new("SurfaceGui")
			gui.Name = "CashGui"
			gui.Parent = cash
			local tl = Instance.new("TextLabel")
			tl.Name = "Bargeld"
			tl.Text = "Bargeld"
			tl.Parent = gui
			m.Parent = folder
		end
	end
	return root
end

---------------------------------------------------------------- Server mit TycoonService (eigene Aktionen-Tabelle)
local function setup(H, opts)
	opts = opts or {}
	opts.placeKind = opts.placeKind or "tycoon" -- Tycoon-Place: Anfangsmodus tycoon
	local g = H.Garage(opts)
	local GC = g:MiniShared("GameConfig")
	local TR = g:MiniShared("TycoonRules")
	local TS = g:MiniServer("TycoonService")
	local Event = g:Remote("Event")
	if not opts.noTemplates then
		buildTemplates(g, GC)
	end
	local handlers = {}
	local log = { dirty = 0, changed = 0 }
	local function emit(p, kind, data)
		if p.player.Parent then
			Event:FireClient(p.player, kind, data)
		end
	end
	local ctx = {
		emit = emit,
		toast = function(p, text)
			emit(p, "toast", text)
		end,
		now = function()
			return g:Now()
		end,
		getSession = function(player)
			return g:Session(player)
		end,
	}
	local fakeApi = {
		now = function()
			return g:Now()
		end,
		toast = function(ms, text)
			ctx.toast(ms.p, text)
		end,
		notice = function(ms, kind, data)
			data = type(data) == "table" and data or {}
			data.kind = kind
			emit(ms.p, "mini_notice", data)
		end,
		dirty = function(ms)
			log.dirty += 1
			ms.dirty = true
		end,
		changed = function(ms)
			log.changed += 1
			ms.dirty = true
		end,
		worldChanged = function() end,
		writable = function(ms)
			return ms.p.profile.writable == true
		end,
		alive = function(ms)
			return ms ~= nil and ms.player.Parent ~= nil
		end,
	}
	TS.Register({
		Register = function(name, fn)
			handlers[name] = fn
		end,
	}, fakeApi)
	TS.Init(ctx)
	local S = { g = g, GC = GC, TR = TR, TS = TS, log = log, handlers = handlers, ctx = ctx, sessions = {} }
	function S.join(userId, name, mode)
		-- Rohdatensatz vor dem Beitritt: bis MiniRules.LoadGames TycoonRules.ApplyLoad aufruft, lädt der Test
		-- d.games.tycoon selbst aus dem gespeicherten Datensatz (wie der Integrator es verkabelt)
		local raw = g:Record(userId)
		raw = raw and raw.data and raw.data.games or nil
		local pl = g:Join(userId, { name = name })
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		ms.greeted = true
		if type(raw) == "table" and type(raw.tycoon) == "table" and type(d.games.tycoon) ~= "table" then
			TR.ApplyLoad(d.games, raw, d, g:Now())
		end
		if mode then
			ms.p.mode = mode -- wie PlaceRouter.Simulate (Moduswechsel), OnJoin unten übernimmt den Rest
		end
		TS.OnJoin(ms, d, g:Now())
		g:Flush()
		table.insert(S.sessions, pl)
		return pl, ms, d
	end
	function S.act(pl, action, data)
		g:Activate()
		local ms = g:MiniState(pl)
		local ok, err = pcall(handlers[action], ms, data or {}, g:D(pl), g:Now())
		g:Flush()
		if not ok then
			error(action .. ": " .. tostring(err))
		end
		return ok
	end
	-- Zeit in Schritten laufen lassen und dabei den Dienst ticken (wie MiniService.Tick)
	function S.tick(seconds, step)
		step = step or 0.5
		local n = math.max(1, math.floor(seconds / step + 0.5))
		for _ = 1, n do
			g:Advance(step)
			for _, pl in ipairs(S.sessions) do
				local ms = g:MiniState(pl)
				if ms and pl.Parent then
					TS.Tick(ms, g:D(pl), g:Now())
				end
			end
		end
		g:Flush()
	end
	function S.leave(pl)
		local ms = g:MiniState(pl)
		if ms then
			TS.OnLeave(ms)
		end
		g:Leave(pl)
		for i, x in ipairs(S.sessions) do
			if x == pl then
				table.remove(S.sessions, i)
				break
			end
		end
	end
	function S.snapshot(pl)
		local ms = g:MiniState(pl)
		return TS.SnapshotFields(ms, g:D(pl), g:Now(), true).tycoon
	end
	function S.run(pl)
		return TR.RunOf(g:D(pl))
	end
	function S.plot(pl)
		return TS.PlotOf(pl)
	end
	function S.slotModel(n)
		return g:Find("Workspace.Tycoon.Plots.Slot_" .. n)
	end
	-- Pad-Teil mit Attribut TycoonButton = id im Grundstück des Spielers
	function S.pad(pl, id)
		local plot = TS.PlotOf(pl)
		for part, pid in pairs(plot and plot.buttons or {}) do
			if pid == id then
				return part
			end
		end
		return nil
	end
	-- Berührung des Pads durch die Figur des Spielers (wie Touched auf dem Server)
	function S.touch(pl, part, who)
		g:Activate()
		local ch = (who or pl).Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		assert(root, "keine Figur")
		root.CFrame = part.CFrame * CFrame.new(0, 3, 0)
		part.Touched:Fire(root)
		g:Flush()
	end
	function S.prompt(pl, part)
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		assert(prompt, "kein Prompt an " .. part.Name)
		g:Teleport(pl, part, Vector3.new(0, 3, 0))
		return g:Trigger(pl, prompt)
	end
	function S.labelText(part, name)
		local gui = part:FindFirstChild("Label")
		local tl = gui and gui:FindFirstChild(name)
		return tl and tl.Text or nil
	end
	return S
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, what .. ": keine Fehler: " .. g:ErrorText())
end

local function signOwner(S, slot)
	local sign = S.slotModel(slot) and S.slotModel(slot):FindFirstChild("Sign")
	local owner, welcome = nil, nil
	for _, x in ipairs(sign:GetDescendants()) do
		if x:IsA("TextLabel") and x.Name == "Owner" then
			owner = x.Text
		elseif x:IsA("TextLabel") and x.Name == "Welcome" then
			welcome = x.Text
		end
	end
	return sign:GetAttribute("Owner"), owner, welcome
end

-- Alle Upgrades der aktuellen Stufe und das Stufen-Pad über Pads/Aktion kaufen (Bargeld/Waren werden vorher gestellt)
local function buyStage(S, T, pl, viaPads)
	local run = S.run(pl)
	local b = S.GC.Tycoon.Buildings[run.building]
	local st = b.Stages[run.stage]
	for _, u in ipairs(st.Upgrades) do
		run.cash = math.max(run.cash, u.cost + 1)
		if viaPads then
			local pad = S.pad(pl, u.id)
			T.check(pad ~= nil, "Pad für " .. u.id)
			S.touch(pl, pad)
			S.g:Advance(0.6)
		else
			S.act(pl, "tycoon_buy", { id = u.id })
		end
		T.check(run.upgrades[u.id] == 1, "gekauft: " .. u.id)
	end
	if st.stageId then
		local nxt = b.Stages[run.stage + 1]
		for item, need in pairs(nxt.items) do
			run.storage[item] = math.max(run.storage[item] or 0, need)
		end
		run.cash = math.max(run.cash, nxt.price + 1)
		if viaPads then
			local pad = S.pad(pl, st.stageId)
			T.check(pad ~= nil, "Stufen-Pad " .. st.stageId)
			S.touch(pl, pad)
			S.g:Advance(0.6)
		else
			S.act(pl, "tycoon_stage")
		end
		T.eq(run.stage, nxt.stage, "Stufe " .. nxt.stage)
	end
end

return {
	{ "Grundstück beim Beitritt im Tycoon-Place, Schild, Start-Pad → tycoon_choose, Gebäudewahl baut Stufe 1 rotationssicher, Produktion und Sammeln", function(T, H)
		local S = setup(H)
		local g, TS, GC = S.g, S.TS, S.GC
		local a, msA, dA = S.join(5001, "Anna")
		T.eq(msA.p.mode, "tycoon", "Anfangsmodus tycoon (PlaceKind tycoon)")
		T.check(type(dA.games.tycoon) == "table" and dA.games.tycoon.run == false, "d.games.tycoon vorhanden, kein Durchlauf")
		local plot = S.plot(a)
		T.check(plot ~= nil and plot.slot == 1, "erstes freies Grundstück (Slot 1)")
		T.check(g:HasToast(a, "Grundstück 1 gehört dir"), "Toast Grundstück")
		local attr, owner, welcome = signOwner(S, 1)
		T.eq(attr, "Anna", "Schild-Attribut Owner")
		T.eq(owner, "Anna", "Schild Owner-Text")
		T.eq(welcome, "WILLKOMMEN, Anna", "Schild Willkommen")
		local snap = S.snapshot(a)
		T.eq(snap.slot, 1, "Snapshot slot")
		T.eq(snap.active, true, "Snapshot active")
		T.eq(snap.run, false, "Snapshot run false")
		T.eq(snap.plots[1], "Anna", "Snapshot plots[1]")
		T.eq(snap.plots[2], false, "Snapshot plots[2] frei")
		-- zweiter Spieler: Slot 2; dritter: Slot 3 (Reihe B, Rot 180)
		local b = S.join(5002, "Ben")
		local c = S.join(5003, "Cem")
		T.eq(S.plot(b).slot, 2, "Ben Slot 2")
		T.eq(S.plot(c).slot, 3, "Cem Slot 3")
		-- Start-Pad: Prompt am eigenen Grundstück -> mini_notice tycoon_choose; fremdes -> Toast
		local start1 = S.slotModel(1):FindFirstChild("StartPad")
		local mark = g:Mark()
		T.check(S.prompt(a, start1), "Prompt am Start-Pad ausgelöst")
		local choose = g:Notices(a, "tycoon_choose", mark)
		T.eq(#choose, 1, "ein tycoon_choose-Hinweis")
		T.eq(choose[1] and choose[1].slot, 1, "Hinweis slot")
		T.eq(choose[1] and choose[1].hasRun, false, "Hinweis hasRun false")
		mark = g:Mark()
		S.prompt(b, start1)
		T.eq(#g:Notices(b, "tycoon_choose", mark), 0, "fremdes Start-Pad: kein Hinweis")
		T.check(g:HasToast(b, "nicht dein Grundstück", mark), "fremdes Start-Pad: Toast")
		-- Gebäudewahl: unbekannt, dann werkstatt
		S.act(a, "tycoon_choose", { building = "raumstation" })
		T.eq(S.run(a), nil, "unbekanntes Gebäude: kein Durchlauf")
		T.check(g:HasToast(a, "gibt es nicht"), "Toast unbekanntes Gebäude")
		mark = g:Mark()
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		local run = S.run(a)
		T.check(run ~= nil and run.building == "werkstatt" and run.stage == 1, "Durchlauf werkstatt Stufe 1")
		T.eq(run and run.cash, GC.Tycoon.StartCash, "Startbargeld")
		local st = g:Notices(a, "tycoon_stage", mark)[1]
		T.check(st ~= nil and st.event == "start" and st.stage == 1, "Hinweis tycoon_stage start")
		-- Modelle: Stage_1 in ButtonsRoot, am Anker, Buttons gebunden, Produzent versteckt, CashDisplay beschriftet
		local root = S.slotModel(1):FindFirstChild("ButtonsRoot")
		local stage1 = root and root:FindFirstChild("Stage_1")
		T.check(stage1 ~= nil, "Stage_1 unter Slot_1.ButtonsRoot")
		T.eq(#plot.stages, 1, "ein Stufenmodell")
		local anchor = S.slotModel(1):FindFirstChild("Anchor")
		T.check(stage1 and (stage1:GetPivot().Position - anchor.Position).Magnitude < 1e-3, "Pivot am Anker")
		local nButtons = 0
		for _ in pairs(plot.buttons) do
			nButtons += 1
		end
		T.eq(nButtons, GC.Tycoon.UpgradesPerStage + 1, "4 Upgrade-Pads + Stufen-Pad gebunden")
		T.check(stage1 and stage1:FindFirstChild("Producer_1") == nil, "Produzent noch versteckt")
		-- Ein Ordner verbirgt im Workspace nichts: Hidden ist aus dem Klon gelöst (Parent nil) und hängt am Grundstück
		T.check(stage1 and stage1:FindFirstChild("Hidden") == nil, "kein Ordner Hidden im Stufenmodell")
		T.check(plot.hidden ~= nil and plot.hidden.Parent == nil and plot.hidden:FindFirstChild("Producer_1") ~= nil, "Produzent im abgetrennten Hidden (Parent nil)")
		local leaked = false
		for _, x in ipairs(g:Find("Workspace.Tycoon.Plots"):GetDescendants()) do
			if x.Name == "Hidden" or (x.Name:sub(1, 9) == "Producer_" and x.Name ~= "Producer_0") then
				leaked = true
			end
		end
		T.check(not leaked, "kein Hidden/Producer_k unter Workspace.Tycoon.Plots vor dem Kauf")
		-- Beschriftung „Name“ kommt aus GameConfig (die Vorlage trägt nur einen Platzhalter)
		local stagePad = S.pad(a, "werkstatt_stage2")
		T.eq(stagePad and S.labelText(stagePad, "Name"), "Stufe 2", "Stufen-Pad Name-Label")
		local cashLabel = stage1 and stage1.CashDisplay.CashGui.Bargeld
		T.check(cashLabel and cashLabel.Text:find("Bargeld " .. GC.Tycoon.StartCash, 1, true) ~= nil, "CashDisplay zeigt Bargeld: " .. tostring(cashLabel and cashLabel.Text))
		-- Beschriftung: u1 (Produzent, 60 s Wartezeit) ist mit 50 Bargeld nicht bezahlbar -> Preis grau
		local u1 = GC.Tycoon.Buildings.werkstatt.Stages[1].Upgrades[1]
		local pad1 = S.pad(a, u1.id)
		T.check(pad1 ~= nil, "Pad u1")
		T.eq(S.labelText(pad1, "Price"), tostring(u1.cost) .. " Bargeld", "Preis-Label")
		T.eq(S.labelText(pad1, "Name"), u1.name, "Name-Label aus der Vorlage")
		T.eq(pad1:GetAttribute("TycoonState"), "locked", "Pad-Zustand locked (zu wenig Bargeld)")
		-- Rotationssicher: Cem (Slot 3, Rot 180) baut autohaus; Pad u1 liegt bei Anker * lokal
		S.act(c, "tycoon_choose", { building = "autohaus" })
		local plotC = S.plot(c)
		T.eq(#plotC.stages, 1, "Cem: ein Stufenmodell")
		local anchorC = S.slotModel(3):FindFirstChild("Anchor")
		T.eq(anchorC:GetAttribute("Rot"), 180, "Slot 3 ist um 180° gedreht")
		local padC = S.pad(c, "autohaus_s1_u1")
		local expected = anchorC.CFrame * CFrame.new(BUTTON_LOCAL[1], BUTTON_LOCAL[2], BUTTON_LOCAL[3] - 3)
		T.check(padC ~= nil and (padC.Position - expected.Position).Magnitude < 1e-3, "Pad-Position rotationssicher (PivotTo)")
		T.check(padC ~= nil and padC.Position.X < anchorC.Position.X, "Rot 180: lokales +x zeigt nach Westen")
		local padA = S.pad(a, "werkstatt_s1_u1")
		T.check(padA ~= nil and padA.Position.X > anchor.Position.X, "Rot 0: lokales +x zeigt nach Osten")
		-- Produktion im Tick: 10 s -> Behälter ≈ baseRate × 10 (Rebirth-Boost 0)
		local before = run.container
		S.tick(10)
		local rate = S.TR.Rate(run)
		T.near(run.container - before, rate * 10, rate * 0.6, "Behälter nach 10 s")
		T.check(run.cash == GC.Tycoon.StartCash, "Bargeld unverändert vor dem Sammeln")
		-- Sammeln: Prompt am Sammel-Pad, danach Touched
		local collectPad = S.slotModel(1):FindFirstChild("CollectPad")
		mark = g:Mark()
		S.prompt(a, collectPad)
		T.check(run.cash > GC.Tycoon.StartCash, "Sammeln über den Prompt")
		T.check(run.container < 1, "Behälter geleert")
		T.check(g:HasToast(a, "Bargeld eingesammelt", mark), "Toast Sammeln")
		S.tick(6)
		local cashBefore = run.cash
		S.touch(a, collectPad)
		T.check(run.cash > cashBefore, "Sammeln über Touched")
		T.eq(collectPad:GetAttribute("TycoonState"), nil, "Sammel-Pad ist kein Kaufpad (keine Umfärbung)")
		-- Sammeln durch Ben auf Annas Pad: nichts
		S.tick(6)
		cashBefore = run.cash
		S.touch(a, collectPad, b)
		T.eq(run.cash, cashBefore, "fremde Figur sammelt nicht")
		-- Snapshot: run mit rate/capacity/container/upgrades/offers
		snap = S.snapshot(a)
		T.check(snap.run and snap.run.building == "werkstatt" and snap.run.stage == 1, "Snapshot run")
		T.check(snap.run and snap.run.capacity == S.TR.Capacity(run), "Snapshot capacity")
		T.check(snap.run and type(snap.run.offers) == "table" and #snap.run.offers == 5, "Snapshot Kaufangebote (4 + Stufe)")
		T.check(snap.bonus and snap.bonus.werkstatt and snap.bonus.werkstatt.runs == 0, "Snapshot bonus")
		-- Ein zweiter Durchlauf ist nicht möglich
		mark = g:Mark()
		S.act(a, "tycoon_choose", { building = "autohaus" })
		T.eq(S.run(a).building, "werkstatt", "tycoon_choose bei laufendem Durchlauf: nichts")
		T.check(g:HasToast(a, "läuft schon", mark), "Toast läuft schon")
		noErrors(T, g, "Grundstück/Start")
	end },

	{ "Kaufpads (Touched, Entprellung, nur Besitzer), Labels „Gekauft“, Produzent erscheint, Stufe 2 baut neu, Zeitraffer bis Stufe 5, Rebirth → runsDone/XP/CrossBonus, Abbruch", function(T, H)
		local S = setup(H)
		local g, GC, TR = S.g, S.GC, S.TR
		local a, msA, dA = S.join(5101, "Anna")
		local b = S.join(5102, "Ben")
		S.act(a, "tycoon_choose", { building = "produktion" })
		local run = S.run(a)
		local u1 = GC.Tycoon.Buildings.produktion.Stages[1].Upgrades[1]
		local pad = S.pad(a, u1.id)
		T.eq(S.labelText(pad, "Name"), u1.name, "Name-Label aus GameConfig")
		-- Schonfrist nach dem Aufbau (PadGrace): die erste Berührung direkt nach dem Bau zählt nicht
		local mark = g:Mark()
		S.touch(a, pad)
		T.eq(#g:Toasts(a, mark), 0, "innerhalb PadGrace keine Reaktion")
		g:Advance(GC.Tycoon.PadGrace)
		-- ohne Bargeld: Touched -> Toast (gedrosselt), kein Kauf
		mark = g:Mark()
		S.touch(a, pad)
		T.eq(run.upgrades[u1.id], nil, "zu wenig Bargeld: kein Kauf")
		T.check(g:HasToast(a, "Nicht genug Bargeld", mark), "Toast zu wenig Bargeld")
		mark = g:Mark()
		S.touch(a, pad)
		T.eq(#g:Toasts(a, mark), 0, "Toast gedrosselt (2 s)")
		-- Bargeld über Ticks verdienen: bis u1 bezahlbar (Rate 3/s -> ~35 s)
		local guard = 0
		while run.cash < u1.cost and guard < 200 do
			S.tick(5)
			S.act(a, "tycoon_collect")
			guard += 1
		end
		T.check(run.cash >= u1.cost, "genug Bargeld gesammelt")
		-- Ben berührt Annas Pad: nichts
		S.touch(a, pad, b)
		T.eq(run.upgrades[u1.id], nil, "fremde Figur kauft nicht")
		-- Anna kauft über das Pad
		mark = g:Mark()
		local cashBefore = run.cash
		S.touch(a, pad)
		T.eq(run.upgrades[u1.id], 1, "u1 über Pad gekauft")
		T.eq(run.cash, cashBefore - u1.cost, "Bargeld abgezogen")
		T.eq(S.labelText(pad, "Price"), "Gekauft", "Label Gekauft")
		T.eq(pad:GetAttribute("TycoonState"), "owned", "Pad-Zustand owned")
		local stage1 = S.plot(a).stages[1]
		T.check(stage1:FindFirstChild("Producer_1") ~= nil, "Produzent sichtbar (aus Hidden geholt)")
		T.check(S.plot(a).hidden:FindFirstChild("Producer_1") == nil, "Produzent nicht mehr in Hidden")
		local ev = g:Notices(a, "tycoon_stage", mark)[1]
		T.check(ev ~= nil and ev.event == "upgrade" and ev.id == u1.id, "Hinweis upgrade")
		-- Entprellung: zweite Berührung sofort danach (schon gekauft) -> Toast „schon gekauft“ erst nach 0,5 s
		mark = g:Mark()
		S.touch(a, pad)
		T.eq(#g:Toasts(a, mark), 0, "Entprellung 0,5 s: keine Reaktion")
		g:Advance(0.6)
		S.touch(a, pad)
		T.check(g:HasToast(a, "schon gekauft", mark), "nach der Entprellung: schon gekauft")
		T.check(TR.Rate(run) > GC.Tycoon.Buildings.produktion.baseRate, "Rate gestiegen")
		-- Stufe 1 komplett über Pads (Bargeld gestellt), Stufen-Pad -> Stufe 2, Modell neu (Vorlagen sind je Stufe
		-- vollständig: nur Stage_2 steht, Stage_1 ist abgebaut), XP
		local xpBefore = dA.xp
		mark = g:Mark()
		buyStage(S, T, a, true)
		T.eq(run.stage, 2, "Stufe 2")
		T.eq(#S.plot(a).stages, 1, "genau ein Stufenmodell (die aktuelle Stufe)")
		T.check(S.slotModel(1).ButtonsRoot:FindFirstChild("Stage_2") ~= nil, "Stage_2 aufgebaut")
		T.check(S.slotModel(1).ButtonsRoot:FindFirstChild("Stage_1") == nil, "Stage_1 abgebaut")
		T.eq(S.plot(a).stages[1]:GetAttribute("TycoonStage"), 2, "Modell trägt TycoonStage 2")
		T.eq(S.pad(a, GC.Tycoon.Buildings.produktion.Stages[1].Upgrades[1].id), nil, "Pads der Stufe 1 nicht mehr gebunden")
		T.check(dA.xp > xpBefore or dA.level > 1, "XP je Stufe")
		local stEv = nil
		for _, n in ipairs(g:Notices(a, "tycoon_stage", mark)) do
			if n.event == "stage" then
				stEv = n
			end
		end
		T.check(stEv ~= nil and stEv.stage == 2, "Hinweis tycoon_stage stage 2")
		-- Stufe-1-Pads (auch das alte Stufen-Pad) sind mit dem Modell der Stufe 1 abgebaut; das neue Stufen-Pad zeigt Stufe 3
		T.eq(S.pad(a, "produktion_stage2"), nil, "altes Stufen-Pad abgebaut")
		T.check(S.pad(a, "produktion_stage3") ~= nil, "Stufen-Pad zu Stufe 3 gebunden")
		-- Die Figur steht nach dem Stufenaufstieg auf dem neuen Stufen-Pad (gleiche Lage): innerhalb PadGrace kein
		-- „Kauf erst alle Upgrades …“, danach schon
		local hidden2 = S.plot(a).hidden
		T.check(hidden2 ~= nil and hidden2.Parent == nil and hidden2:FindFirstChild("Producer_1") ~= nil, "Hidden der Stufe 2 abgetrennt")
		mark = g:Mark()
		S.touch(a, S.pad(a, "produktion_stage3"))
		T.eq(#g:Toasts(a, mark), 0, "neues Stufen-Pad direkt nach dem Aufbau: kein Toast")
		g:Advance(GC.Tycoon.PadGrace)
		S.touch(a, S.pad(a, "produktion_stage3"))
		T.check(g:HasToast(a, "alle Upgrades", mark), "nach PadGrace: Toast Stufe unvollständig")
		g:Advance(GC.Tycoon.PadToastSeconds + 0.1)
		-- Stufen-Pad zu früh: Stufe 3 erst mit allen Upgrades der Stufe 2
		run.cash = 1e9
		mark = g:Mark()
		S.act(a, "tycoon_stage")
		T.eq(run.stage, 2, "Stufe 3 ohne komplette Stufe 2: nein")
		T.check(g:HasToast(a, "alle Upgrades", mark), "Toast Stufe unvollständig")
		-- Waren fehlen: Stufe 3 braucht Waren
		for _, u in ipairs(GC.Tycoon.Buildings.produktion.Stages[2].Upgrades) do
			S.act(a, "tycoon_buy", { id = u.id })
		end
		run.storage = {}
		mark = g:Mark()
		S.act(a, "tycoon_stage")
		T.eq(run.stage, 2, "ohne Waren keine Stufe 3")
		T.check(g:HasToast(a, "fehlen noch Waren", mark), "Toast Waren fehlen")
		-- Lager-Upgrade erzeugt Waren im Tick (perMin)
		local rates = TR.ItemRates(run)
		local item = next(rates)
		T.check(item ~= nil, "Lager-Upgrade erzeugt Ware " .. tostring(item))
		S.tick(120)
		T.check((run.storage[item] or 0) >= 1, "Ware nach 2 Minuten im Lager: " .. tostring(run.storage[item]))
		-- Zeitraffer bis Stufe 5 komplett (Bargeld/Waren gestellt, Aktionen)
		while run.stage < GC.Tycoon.MaxStage do
			buyStage(S, T, a, false)
		end
		T.eq(run.stage, 5, "Stufe 5")
		T.eq(#S.plot(a).stages, 1, "ein Stufenmodell (Stufe 5)")
		T.check(S.slotModel(1).ButtonsRoot:FindFirstChild("Stage_5") ~= nil, "Stage_5 aufgebaut")
		-- Rebirth vor komplett: nein
		mark = g:Mark()
		S.act(a, "tycoon_rebirth")
		T.check(S.run(a) ~= nil, "Rebirth vor allen Upgrades: nein")
		T.check(g:HasToast(a, "alle Upgrades der Stufe 5", mark), "Toast Rebirth gesperrt")
		buyStage(S, T, a, false)
		T.check(TR.StageComplete(run, 5), "Stufe 5 komplett")
		T.check(S.snapshot(a).run.canRebirth, "Snapshot canRebirth")
		-- Rebirth: runsDone, rebirths, XP, Bonus, Modelle weg, Bargeld weg (nie Credits)
		local moneyBefore = dA.money
		xpBefore = dA.xp
		local levelBefore = dA.level
		mark = g:Mark()
		S.act(a, "tycoon_rebirth")
		T.eq(S.run(a), nil, "Durchlauf beendet")
		T.eq(dA.games.tycoon.runsDone.produktion, 1, "runsDone produktion 1")
		T.eq(dA.games.tycoon.rebirths, 1, "rebirths 1")
		T.eq(dA.games.stats.tycoonRuns, 1, "Statistik tycoonRuns")
		T.check(dA.xp > xpBefore or dA.level > levelBefore, "XP je Durchlauf")
		T.eq(#S.plot(a).stages, 0, "Modelle abgebaut")
		T.eq(#S.slotModel(1).ButtonsRoot:GetChildren(), 0, "ButtonsRoot leer")
		local rb = nil
		for _, n in ipairs(g:Notices(a, "tycoon_stage", mark)) do
			if n.event == "rebirth" then
				rb = n
			end
		end
		T.check(rb ~= nil and rb.rebirths == 1 and rb.boostPct == 15, "Hinweis rebirth (Boost 15 %)")
		T.check(g:HasToast(a, "Rebirth Nr. 1", mark), "Toast Rebirth")
		-- Geld: nur der Level-Bonus von GainXP darf Credits bringen, nie Bargeld
		local R = g:Rules()
		T.check(dA.money >= moneyBefore, "kein Credits-Verlust")
		local CB = g:MiniShared("CrossBonus")
		T.eq(S.snapshot(a).bonus.produktion.pct, 3, "Bonus produktion +3 %")
		T.eq(CB.TycoonWorkshop(dA), 1, "TycoonWorkshop ohne Werkstatt-Durchlauf = 1")
		dA.games.tycoon.runsDone.werkstatt = 2
		T.near(CB.TycoonWorkshop(dA), 1.04, 1e-9, "CrossBonus.TycoonWorkshop > 1 nach Werkstatt-Durchläufen")
		-- Neuer Durchlauf mit Rebirth-Boost; Abbruch zählt nichts
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		run = S.run(a)
		T.near(run.rebirthBoost, 0.15, 1e-9, "Rebirth-Boost im neuen Durchlauf")
		T.eq(#S.plot(a).stages, 1, "Stufe 1 gebaut")
		mark = g:Mark()
		S.act(a, "tycoon_abandon")
		T.eq(S.run(a), nil, "abgebrochen")
		T.eq(dA.games.tycoon.runsDone.werkstatt, 2, "Abbruch zählt nicht")
		T.eq(#S.plot(a).stages, 0, "Modelle nach Abbruch weg")
		T.check(g:HasToast(a, "abgebrochen", mark), "Toast Abbruch")
		S.act(a, "tycoon_abandon")
		T.check(g:HasToast(a, "kein Durchlauf"), "zweiter Abbruch: Toast")
		noErrors(T, g, "Pads/Stufen/Rebirth")
	end },

	{ "Handel zwischen zwei Spielern: Angebot, Marktplatz-Hinweis, falscher Empfänger, Annahme in einem Schritt (Erhaltung), Ablauf, Rücknahme, Verkäufer geht", function(T, H)
		local S = setup(H)
		local g, GC, TS = S.g, S.GC, S.TS
		local a, msA, dA = S.join(5201, "Anna")
		local b, msB, dB = S.join(5202, "Ben")
		local c = S.join(5203, "Cem")
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		S.act(b, "tycoon_choose", { building = "autohaus" })
		local runA, runB = S.run(a), S.run(b)
		runA.storage.reifen = 20
		runB.cash = 1000
		-- ohne Durchlauf (Cem) kein Angebot; Ware fehlt; Menge/Preis-Grenzen; Partner ohne Durchlauf; selbst
		S.act(c, "tycoon_trade_offer", { to = 5201, item = "reifen", qty = 1, price = 10 })
		T.check(g:HasToast(c, "laufenden Durchlauf"), "Cem ohne Durchlauf")
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "lack", qty = 1, price = 10 })
		T.check(g:HasToast(a, "nicht im Lager"), "Ware fehlt")
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 0, price = 10 })
		T.check(g:HasToast(a, "Menge"), "Menge 0")
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 5, price = 0 })
		T.check(g:HasToast(a, "mindestens"), "Preis 0")
		S.act(a, "tycoon_trade_offer", { to = 5203, item = "reifen", qty = 5, price = 10 })
		T.check(g:HasToast(a, "keinen Durchlauf"), "Partner ohne Durchlauf")
		S.act(a, "tycoon_trade_offer", { to = 5201, item = "reifen", qty = 5, price = 10 })
		T.check(g:HasToast(a, "dir selbst"), "selbst")
		S.act(a, "tycoon_trade_offer", { to = 9999, item = "reifen", qty = 5, price = 10 })
		T.check(g:HasToast(a, "gibt es hier nicht"), "unbekannter Partner")
		T.eq(next(TS.Offers), nil, "noch kein Angebot")
		-- gültiges Angebot: 5 Reifen für 300 Bargeld
		local mark = g:Mark()
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 5, price = 300.7 })
		local offer = nil
		for _, o in pairs(TS.Offers) do
			offer = o
		end
		T.check(offer ~= nil and offer.from == 5201 and offer.to == 5202 and offer.qty == 5 and offer.price == 300, "Angebot serverlokal (Preis ganzzahlig)")
		T.eq(offer and offer.expires, g:Now() + GC.Tycoon.TradeTTL, "Ablauf nach TradeTTL")
		T.eq(runA.storage.reifen, 20, "Ware bleibt bis zur Annahme beim Verkäufer")
		local tA = g:Notices(a, "trade", mark)[1]
		local tB = g:Notices(b, "trade", mark)[1]
		T.check(tA and tA.event == "offered" and tA.id == offer.id, "Hinweis trade offered an Anna")
		T.check(tB and tB.event == "offered" and tB.fromName == "Anna", "Hinweis trade offered an Ben")
		T.check(g:HasToast(b, "bietet dir", mark), "Toast an Ben")
		local mA = g:Notices(a, "tycoon_market", mark)
		local mC = g:Notices(c, "tycoon_market", mark)
		T.check(#mA >= 1 and #mA[#mA].offers == 1, "tycoon_market an Anna")
		T.check(#mC >= 1 and #mC[#mC].offers == 1, "tycoon_market an alle Tycoon-Spieler (Cem)")
		local board = g:Find("Workspace.Tycoon.Markt")
		local offersLabel = nil
		for _, x in ipairs(board:GetDescendants()) do
			if x:IsA("TextLabel") and x.Name == "Offers" then
				offersLabel = x
			end
		end
		T.check(offersLabel and offersLabel.Text:find("Anna → Ben", 1, true) ~= nil, "Marktplatz-Tafel: " .. tostring(offersLabel and offersLabel.Text))
		T.eq(#S.snapshot(a).offers, 1, "Snapshot offers (meins)")
		T.eq(#S.snapshot(b).offers, 1, "Snapshot offers (an mich)")
		T.eq(#S.snapshot(c).offers, 0, "Snapshot offers Cem leer")
		-- falscher Empfänger (Cem) und Verkäufer selbst können nicht annehmen
		S.act(c, "tycoon_trade_accept", { id = offer.id })
		T.check(g:HasToast(c, "nicht für dich"), "Cem: nicht für dich")
		S.act(a, "tycoon_trade_accept", { id = offer.id })
		T.check(g:HasToast(a, "nicht für dich"), "Anna: nicht für dich")
		T.check(TS.Offers[offer.id] ~= nil, "Angebot noch da")
		-- Käufer ohne Bargeld: Annahme scheitert, Angebot weg, nichts bewegt
		runB.cash = 100
		mark = g:Mark()
		S.act(b, "tycoon_trade_accept", { id = offer.id })
		T.eq(TS.Offers[offer.id], nil, "gescheitertes Angebot entfernt")
		T.eq(runA.storage.reifen, 20, "Verkäufer-Lager unverändert")
		T.eq(runB.cash, 100, "Käufer-Bargeld unverändert")
		T.check(g:HasToast(b, "Nicht genug Bargeld", mark), "Toast Käufer")
		local fail = g:Notices(a, "trade", mark)[1]
		T.check(fail and fail.event == "failed" and fail.reason == "cash", "Hinweis failed an den Verkäufer")
		-- neues Angebot, Annahme: Erhaltung von Waren und Bargeld in einem Schritt
		runB.cash = 1000
		g:Advance(0.5)
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 5, price = 300 })
		local id = nil
		for k in pairs(TS.Offers) do
			id = k
		end
		local sumCash = runA.cash + runB.cash
		local sumItems = (runA.storage.reifen or 0) + (runB.storage.reifen or 0)
		mark = g:Mark()
		S.act(b, "tycoon_trade_accept", { id = id })
		S.tick(GC.Tycoon.MarketBroadcastInterval) -- Marktplatz-Hinweise werden gebündelt (höchstens 1×/s)
		T.eq(TS.Offers[id], nil, "Angebot nach Annahme weg")
		T.eq(runA.storage.reifen, 15, "Anna 15 Reifen")
		T.eq(runB.storage.reifen, 5, "Ben 5 Reifen")
		T.eq(runB.cash, 700, "Ben 700 Bargeld")
		T.eq(runA.cash, GC.Tycoon.StartCash + 300, "Anna +300 Bargeld")
		T.eq(runA.cash + runB.cash, sumCash, "Bargeld erhalten")
		T.eq((runA.storage.reifen or 0) + (runB.storage.reifen or 0), sumItems, "Waren erhalten")
		T.eq(dA.money, dB.money, "Credits unverändert (nie Credits)")
		local acc = g:Notices(b, "trade", mark)[1]
		T.check(acc and acc.event == "accepted", "Hinweis accepted")
		T.check(g:HasToast(a, "Handel abgeschlossen", mark), "Toast Verkäufer")
		T.check(#g:Notices(c, "tycoon_market", mark) >= 1 and #g:Last(c, "mini_notice").offers == 0, "Markt leer")
		-- zweite Annahme desselben Angebots: gibt es nicht mehr
		S.act(b, "tycoon_trade_accept", { id = id })
		T.check(g:HasToast(b, "nicht mehr"), "Angebot weg")
		-- Ablauf: nach TradeTTL entfernt der Tick das Angebot mit Hinweis expired
		g:Advance(0.5)
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 2, price = 50 })
		for k in pairs(TS.Offers) do
			id = k
		end
		mark = g:Mark()
		S.tick(GC.Tycoon.TradeTTL + 2, 5)
		T.eq(TS.Offers[id], nil, "abgelaufen")
		local ex = g:Notices(b, "trade", mark)
		T.check(#ex >= 1 and ex[#ex].event == "expired", "Hinweis expired")
		T.eq(runA.storage.reifen, 15, "nichts bewegt")
		-- Rücknahme durch den Verkäufer, Ablehnung durch den Käufer
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 2, price = 50 })
		for k in pairs(TS.Offers) do
			id = k
		end
		S.act(a, "tycoon_trade_cancel", { id = id })
		T.eq(TS.Offers[id], nil, "zurückgezogen")
		T.check(g:HasToast(a, "zurückgezogen"), "Toast zurückgezogen")
		g:Advance(GC.Tycoon.TradeOfferInterval) -- je Paar erst nach TradeOfferInterval wieder
		S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 2, price = 50 })
		for k in pairs(TS.Offers) do
			id = k
		end
		S.act(b, "tycoon_trade_cancel", { id = id })
		T.eq(TS.Offers[id], nil, "abgelehnt")
		T.check(g:HasToast(b, "abgelehnt"), "Toast abgelehnt")
		S.act(c, "tycoon_trade_cancel", { id = 12345 })
		T.check(g:HasToast(c, "nicht mehr"), "unbekannte Id")
		-- Höchstens TradeMaxOpen offene Angebote (nach der Ablehnung erst nach TradeDeclineBlock, je Angebot TradeOfferInterval)
		g:Advance(GC.Tycoon.TradeDeclineBlock)
		for i = 1, GC.Tycoon.TradeMaxOpen + 1 do
			g:Advance(GC.Tycoon.TradeOfferInterval)
			S.act(a, "tycoon_trade_offer", { to = 5202, item = "reifen", qty = 1, price = 5 })
		end
		local n = 0
		for _ in pairs(TS.Offers) do
			n += 1
		end
		T.eq(n, GC.Tycoon.TradeMaxOpen, "Deckel offene Angebote")
		T.check(g:HasToast(a, "offene Angebote"), "Toast Deckel")
		-- Verkäufer verlässt den Server: Angebote weg, Käufer erfährt es, Slot frei
		mark = g:Mark()
		S.leave(a)
		T.eq(next(TS.Offers), nil, "Angebote des Verkäufers weg")
		T.check(#g:Notices(b, "trade", mark) >= 1, "Käufer: Hinweis")
		T.check(g:HasToast(b, "Handelspartner ist weg", mark), "Toast Partner weg")
		T.eq(TS.Plots[1], nil, "Slot 1 frei")
		T.eq(signOwner(S, 1), "", "Schild wieder FREI")
		-- Angebot an einen Spieler, der danach die Zone verlässt: Annahme scheitert freundlich
		runB.storage.lack = 3
		local d2 = S.join(5204, "Dana")
		S.act(d2, "tycoon_choose", { building = "schrottplatz" })
		S.act(b, "tycoon_trade_offer", { to = 5204, item = "lack", qty = 1, price = 5 })
		for k in pairs(TS.Offers) do
			id = k
		end
		msB.p.mode = "lobby"
		S.tick(1)
		T.eq(TS.Offers[id], nil, "Moduswechsel des Verkäufers: Angebot weg")
		S.act(d2, "tycoon_trade_accept", { id = id })
		T.check(g:HasToast(d2, "nicht mehr"), "Dana: Angebot weg")
		noErrors(T, g, "Handel")
	end },

	{ "Handel: Spam-Bremse je Paar (Angebot/Rücknahme-Schleife: ein Toast), Sperre nach Ablehnung, Marktplatz-Hinweis gebündelt, nicht speicherbare Profile handeln nicht, Spielerliste im Snapshot", function(T, H)
		local S = setup(H)
		local g, GC, TS = S.g, S.GC, S.TS
		local a, msA = S.join(5301, "Anna")
		local b, msB = S.join(5302, "Ben")
		local c, msC = S.join(5303, "Cem")
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		S.act(b, "tycoon_choose", { building = "autohaus" })
		local runA, runB = S.run(a), S.run(b)
		runA.storage.schrott = 10
		runB.cash = 1000
		-- Spielerliste: nur Tycoon-Spieler mit Durchlauf, ohne mich (Cem hat keinen Durchlauf)
		local players = S.snapshot(a).players
		T.eq(#players, 1, "ein Handelspartner im Snapshot")
		T.check(players[1] and players[1].userId == 5302 and players[1].name == "Ben", "Ben in der Spielerliste")
		T.eq(#S.snapshot(b).players, 1, "Ben sieht Anna")
		T.eq(#S.snapshot(c).players, 2, "Cem sieht beide")
		-- Angebot/Rücknahme dreimal in 3 s: Ben bekommt genau einen Toast, kein Marktplatz-Spam
		local mark = g:Mark()
		local lastId = nil
		for i = 1, 3 do
			S.act(a, "tycoon_trade_offer", { to = 5302, item = "schrott", qty = 1, price = 1 })
			for k in pairs(TS.Offers) do
				lastId = k
			end
			if next(TS.Offers) then
				S.act(a, "tycoon_trade_cancel", { id = lastId })
			end
			g:Advance(1)
		end
		local toastsB = 0
		for _, t in ipairs(g:Toasts(b, mark)) do
			if type(t) == "string" and t:find("bietet dir", 1, true) then
				toastsB += 1
			end
		end
		T.eq(toastsB, 1, "Ben: genau ein Angebots-Toast")
		T.check(g:HasToast(a, "Warte kurz", mark), "Anna: Warte kurz")
		T.check(#g:Notices(c, "tycoon_market", mark) <= 3, "Marktplatz-Hinweise gebündelt (≤ 1/s): " .. tostring(#g:Notices(c, "tycoon_market", mark)))
		-- nach TradeOfferInterval wieder ein Angebot; Ben lehnt ab -> Sperre für TradeDeclineBlock
		g:Advance(GC.Tycoon.TradeOfferInterval)
		mark = g:Mark()
		S.act(a, "tycoon_trade_offer", { to = 5302, item = "schrott", qty = 1, price = 1 })
		T.check(next(TS.Offers) ~= nil, "Angebot nach der Wartezeit")
		for k in pairs(TS.Offers) do
			lastId = k
		end
		S.act(b, "tycoon_trade_cancel", { id = lastId })
		T.check(g:HasToast(b, "abgelehnt", mark), "Ben lehnt ab")
		g:Advance(GC.Tycoon.TradeOfferInterval + 1)
		mark = g:Mark()
		S.act(a, "tycoon_trade_offer", { to = 5302, item = "schrott", qty = 1, price = 1 })
		T.eq(next(TS.Offers), nil, "nach Ablehnung gesperrt")
		T.check(g:HasToast(a, "abgelehnt", mark), "Anna: Hinweis auf die Ablehnung")
		T.eq(#g:Toasts(b, mark), 0, "Ben bekommt nichts")
		g:Advance(GC.Tycoon.TradeDeclineBlock)
		S.act(a, "tycoon_trade_offer", { to = 5302, item = "schrott", qty = 1, price = 1 })
		T.check(next(TS.Offers) ~= nil, "nach TradeDeclineBlock wieder erlaubt")
		for k in pairs(TS.Offers) do
			lastId = k
		end
		-- Käufer nicht speicherbar: Annahme verweigert, Angebot bleibt; Verkäufer nicht speicherbar: Angebot weg
		msB.p.profile.writable = false
		mark = g:Mark()
		S.act(b, "tycoon_trade_accept", { id = lastId })
		T.check(g:HasToast(b, "nicht gespeichert", mark), "Käufer nicht speicherbar")
		T.check(TS.Offers[lastId] ~= nil, "Angebot bleibt")
		T.eq(runB.storage.schrott, nil, "nichts übergeben")
		-- im Tick verliert Ben (nicht speicherbar) seine Angebote als Empfänger
		S.tick(1)
		T.eq(TS.Offers[lastId], nil, "Angebote eines nicht speicherbaren Spielers im Tick entfernt")
		msB.p.profile.writable = true
		S.act(b, "tycoon_trade_offer", { to = 5301, item = "lack", qty = 1, price = 1 })
		T.check(g:HasToast(b, "nicht im Lager"), "Ben wieder speicherbar (normale Prüfung)")
		msA.p.profile.writable = false
		mark = g:Mark()
		g:Advance(GC.Tycoon.TradeOfferInterval)
		S.act(a, "tycoon_trade_offer", { to = 5302, item = "schrott", qty = 1, price = 1 })
		T.check(g:HasToast(a, "nicht gespeichert", mark), "nicht speicherbarer Verkäufer bietet nicht an")
		T.eq(next(TS.Offers), nil, "kein Angebot")
		msA.p.profile.writable = true
		-- Preisdeckel TradeMaxPrice
		g:Advance(GC.Tycoon.TradeOfferInterval)
		mark = g:Mark()
		S.act(a, "tycoon_trade_offer", { to = 5302, item = "schrott", qty = 1, price = GC.Tycoon.TradeMaxPrice + 1 })
		T.eq(next(TS.Offers), nil, "über TradeMaxPrice kein Angebot")
		T.check(g:HasToast(a, "höchstens", mark), "Toast Preisdeckel")
		noErrors(T, g, "Handel-Spam")
	end },

	{ "Stufen-XP nur einmal je Stufe seit dem letzten Rebirth (Abbruch + Neustart farmt keine Level-Credits); Rebirth setzt zurück", function(T, H)
		local S = setup(H)
		local g, GC, TR = S.g, S.GC, S.TR
		local a, _, dA = S.join(5401, "Anna")
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		local xp0 = dA.xp
		buyStage(S, T, a, false)
		T.eq(S.run(a).stage, 2, "Stufe 2")
		T.eq(dA.games.tycoon.xpStage, 2, "xpStage 2")
		local gained = dA.xp - xp0
		T.check(gained > 0 or dA.level > 1, "Stufen-XP beim ersten Aufstieg")
		-- Abbruch + Neustart + Stufe 2: keine XP mehr
		g:Advance(2.1)
		S.act(a, "tycoon_abandon")
		T.eq(dA.games.tycoon.xpStage, 2, "Abbruch setzt xpStage nicht zurück")
		g:Advance(1.1)
		S.act(a, "tycoon_choose", { building = "autohaus" })
		local xp1, lvl1 = dA.xp, dA.level
		local mark = g:Mark()
		buyStage(S, T, a, false)
		T.eq(S.run(a).stage, 2, "wieder Stufe 2")
		T.check(dA.xp == xp1 and dA.level == lvl1, "keine zweiten Stufen-XP nach Abbruch")
		local ev = nil
		for _, n in ipairs(g:Notices(a, "tycoon_stage", mark)) do
			if n.event == "stage" then
				ev = n
			end
		end
		T.check(ev ~= nil and ev.xp == 0, "Hinweis stage mit xp 0")
		-- Stufe 3 bringt wieder XP (höher als bisher)
		local xp2, lvl2 = dA.xp, dA.level
		buyStage(S, T, a, false)
		T.eq(S.run(a).stage, 3, "Stufe 3")
		T.check(dA.xp > xp2 or dA.level > lvl2, "Stufe 3: XP")
		T.eq(dA.games.tycoon.xpStage, 3, "xpStage 3")
		-- bis 5, Rebirth -> xpStage 0, neuer Durchlauf bringt wieder Stufen-XP
		while S.run(a).stage < GC.Tycoon.MaxStage do
			buyStage(S, T, a, false)
		end
		buyStage(S, T, a, false)
		g:Advance(2.1)
		S.act(a, "tycoon_rebirth")
		T.eq(S.run(a), nil, "Rebirth")
		T.eq(dA.games.tycoon.xpStage, 0, "Rebirth setzt xpStage zurück")
		g:Advance(1.1)
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		local xp3, lvl3 = dA.xp, dA.level
		buyStage(S, T, a, false)
		T.check(dA.xp > xp3 or dA.level > lvl3, "nach Rebirth wieder Stufen-XP")
		-- Laden: xpStage aus dem Datensatz (Whitelist 0..MaxStage)
		local t = TR.Load({ runsDone = {}, rebirths = 0, xpStage = 99 }, dA, g:Now())
		T.eq(t.xpStage, GC.Tycoon.MaxStage, "xpStage beim Laden gedeckelt")
		T.eq(TR.Load(nil, dA, g:Now()).xpStage, 0, "xpStage Standard 0")
		noErrors(T, g, "XP je Stufe")
	end },

	{ "Pads und Prompts während eines Robux-Kaufs (transacting): keine Änderung; Prompt-Drossel je Spieler und Reichweite", function(T, H)
		local S = setup(H)
		local g, GC = S.g, S.GC
		local a, msA = S.join(5501, "Anna")
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		local run = S.run(a)
		local u1 = GC.Tycoon.Buildings.werkstatt.Stages[1].Upgrades[1]
		local pad = S.pad(a, u1.id)
		run.cash = u1.cost + 5
		g:Advance(GC.Tycoon.PadGrace)
		-- transacting: Pad ohne Wirkung (Toast), Sammel-/Start-Prompt ohne Wirkung
		msA.p.profile.transacting = true
		local mark = g:Mark()
		S.touch(a, pad)
		T.eq(run.upgrades[u1.id], nil, "transacting: kein Kauf über das Pad")
		T.check(g:HasToast(a, "gespeichert", mark), "Toast: Kauf wird gespeichert")
		run.container = 40
		local collect = S.slotModel(1):FindFirstChild("CollectPad")
		S.prompt(a, collect)
		T.eq(run.container, 40, "transacting: Sammel-Prompt ohne Wirkung")
		local start = S.slotModel(1):FindFirstChild("StartPad")
		mark = g:Mark()
		S.prompt(a, start)
		T.eq(#g:Notices(a, "tycoon_choose", mark), 0, "transacting: Start-Prompt ohne Hinweis")
		msA.p.profile.transacting = false
		-- Prompt-Drossel: zwei Auslösungen kurz nacheinander -> ein Hinweis
		g:Advance(GC.Tycoon.PromptDebounce + 0.1)
		mark = g:Mark()
		S.prompt(a, start)
		S.prompt(a, start)
		T.eq(#g:Notices(a, "tycoon_choose", mark), 1, "Prompt-Drossel: ein Hinweis")
		g:Advance(GC.Tycoon.PromptDebounce + 0.1)
		S.prompt(a, start)
		T.eq(#g:Notices(a, "tycoon_choose", mark), 2, "nach PromptDebounce wieder")
		-- Reichweite: Prompt aus der Ferne (Exploit) ohne Wirkung
		g:Advance(GC.Tycoon.PromptDebounce + 0.1)
		local root = g:Root(a)
		root.CFrame = collect.CFrame * CFrame.new(0, 3, 200)
		local cashBefore = run.cash
		g:Trigger(a, collect:FindFirstChildOfClass("ProximityPrompt"))
		g:Flush()
		T.eq(run.cash, cashBefore, "Sammel-Prompt aus 200 Studs: nichts gesammelt")
		T.check(run.container >= 40, "Behälter bleibt gefüllt")
		g:Advance(GC.Tycoon.PromptDebounce + 0.1)
		S.prompt(a, collect)
		T.check(run.cash > cashBefore and run.container < 1, "in Reichweite: gesammelt")
		-- danach kauft das Pad normal
		g:Advance(1)
		S.touch(a, pad)
		T.eq(run.upgrades[u1.id], 1, "ohne transacting: Kauf")
		noErrors(T, g, "transacting/Prompts")
	end },

	{ "Speichern und Fortsetzen: Verlassen mitten im Durchlauf, Wiederkommen baut Stufen und Produzenten wieder auf (Offline zählt nicht), Slot wird neu vergeben", function(T, H)
		local S = setup(H)
		local g, GC, TR = S.g, S.GC, S.TR
		local a, msA, dA = S.join(5301, "Anna")
		S.act(a, "tycoon_choose", { building = "schrottplatz" })
		local run = S.run(a)
		buyStage(S, T, a, false)
		buyStage(S, T, a, false)
		T.eq(run.stage, 3, "Stufe 3")
		local u1 = GC.Tycoon.Buildings.schrottplatz.Stages[3].Upgrades[1]
		run.cash = u1.cost + 5
		S.act(a, "tycoon_buy", { id = u1.id })
		run.storage.schrott = 7
		S.tick(3)
		local cashSaved, containerSaved = run.cash, run.container
		-- Verlassen: Slot frei, Modelle weg, Profil gespeichert
		S.leave(a)
		g:Advance(1)
		T.eq(S.TS.Plots[1], nil, "Slot frei")
		T.eq(#S.slotModel(1).ButtonsRoot:GetChildren(), 0, "Modelle weg")
		local rec = g:Record(5301)
		T.check(rec and rec.data and rec.data.games and type(rec.data.games.tycoon) == "table", "tycoon gespeichert")
		T.check(rec.data.games.tycoon.run and rec.data.games.tycoon.run.stage == 3, "run gespeichert (Stufe 3)")
		-- Ben belegt inzwischen Slot 1
		local b = S.join(5302, "Ben")
		T.eq(S.plot(b).slot, 1, "Ben bekommt Slot 1")
		-- Anna kommt nach 1 Stunde wieder: Slot 2, Durchlauf fortgesetzt, Modell der Stufe 3, Produzent sichtbar
		g:Advance(3600)
		local mark = g:Mark()
		local a2, msA2, dA2 = S.join(5301, "Anna")
		local run2 = S.run(a2)
		T.check(run2 ~= nil and run2.building == "schrottplatz" and run2.stage == 3, "Durchlauf fortgesetzt")
		T.eq(run2.upgrades[u1.id], 1, "Upgrade geladen")
		T.eq(run2.storage.schrott, 7, "Lager geladen")
		T.eq(run2.cash, cashSaved, "Bargeld geladen")
		-- höchstens die Produktion seit dem Beitritt (MiniService tickt ab dem Beitritt, ≈ 1 s), nie die Offline-Stunde
		T.check(run2.container <= containerSaved + TR.Rate(run2) * 1.5 + 1, "Offline erzeugt kein Bargeld")
		T.eq(run2.lastTick, g:Now(), "lastTick = jetzt (Offline zählt nicht)")
		T.eq(S.plot(a2).slot, 2, "Anna: Slot 2 (Slot 1 belegt)")
		T.eq(#S.plot(a2).stages, 1, "Stufenmodell der Stufe 3 wieder aufgebaut")
		T.check(S.slotModel(2).ButtonsRoot:FindFirstChild("Stage_3") ~= nil, "Stage_3 unter Slot_2")
		T.check(S.plot(a2).stages[1]:FindFirstChild("Producer_1") ~= nil, "Produzent Stufe 3 sichtbar")
		T.eq(S.labelText(S.pad(a2, u1.id), "Price"), "Gekauft", "Label Gekauft nach dem Laden")
		T.check(g:HasToast(a2, "Willkommen zurück", mark), "Toast Fortsetzen")
		T.eq(signOwner(S, 2), "Anna", "Schild Slot 2")
		-- Produktion läuft weiter
		S.tick(10)
		T.check(run2.container > 0, "Behälter füllt sich wieder")
		noErrors(T, g, "Fortsetzen")
	end },

	{ "Moduswechsel: Lobby → lobby_mode/lobby_go (Simulation) belegt ein Grundstück, lobby_return gibt es frei; OnMode idempotent; ohne Vorlagen läuft der Durchlauf; alle Grundstücke belegt", function(T, H)
		local S = setup(H, { placeKind = "all" })
		local g, TS = S.g, S.TS
		local a, msA, dA = S.join(5401, "Anna")
		T.eq(msA.p.mode, "lobby", "Anfangsmodus lobby (all-Place)")
		T.eq(S.plot(a), nil, "in der Lobby kein Grundstück")
		T.eq(S.snapshot(a).active, false, "Snapshot active false")
		-- Aktionen außerhalb des Tycoon: freundlicher Toast
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		T.eq(S.run(a), nil, "kein Durchlauf in der Lobby")
		T.check(g:HasToast(a, "in der Lobby"), "Toast: Tycoon in der Lobby starten")
		-- echte Lobby-Aktionen (MiniService-Verkabelung), dann OnMode wie vom Integrator
		T.eq(g:Act(a, "lobby_mode", { mode = "tycoon", rid = 1 }), "ok", "lobby_mode")
		T.eq(g:Act(a, "lobby_go", { rid = 2 }), "ok", "lobby_go")
		T.eq(msA.p.mode, "tycoon", "Modus tycoon")
		TS.OnMode(msA, dA, "tycoon")
		T.eq(S.plot(a) and S.plot(a).slot, 1, "Slot 1 nach OnMode")
		TS.OnMode(msA, dA, "tycoon")
		T.eq(S.plot(a) and S.plot(a).slot, 1, "OnMode idempotent")
		S.act(a, "tycoon_choose", { building = "werkstatt" })
		T.eq(#S.plot(a).stages, 1, "Stufe 1 gebaut")
		-- Rückweg: lobby_return -> OnMode lobby -> Slot frei, Modelle weg, Durchlauf bleibt
		g:Advance(3.1)
		T.eq(g:Act(a, "lobby_return", { rid = 3 }), "ok", "lobby_return")
		T.eq(msA.p.mode, "lobby", "Modus lobby")
		TS.OnMode(msA, dA, "lobby")
		T.eq(S.plot(a), nil, "Slot frei")
		T.eq(TS.Plots[1], nil, "Plots[1] frei")
		T.check(S.run(a) ~= nil, "Durchlauf bleibt im Profil")
		T.eq(#S.slotModel(1).ButtonsRoot:GetChildren(), 0, "Modelle weg")
		-- Tick erkennt einen Moduswechsel auch ohne OnMode
		g:Advance(3.1)
		T.eq(g:Act(a, "lobby_mode", { mode = "tycoon", rid = 4 }), "ok", "lobby_mode 2")
		T.eq(g:Act(a, "lobby_go", { rid = 5 }), "ok", "lobby_go 2")
		S.tick(1)
		T.eq(S.plot(a) and S.plot(a).slot, 1, "Tick: Slot 1")
		T.eq(#S.plot(a).stages, 1, "Tick: Durchlauf wieder aufgebaut")
		msA.p.mode = "openworld"
		S.tick(1)
		T.eq(S.plot(a), nil, "Tick: Slot nach Moduswechsel frei")
		-- Ohne Vorlagen: Durchlauf und Pads laufen, nur ohne Modelle (Warnung, kein Fehler)
		g:Activate()
		g.env.services.ServerStorage.TycoonTemplates:Destroy()
		msA.p.mode = "tycoon"
		S.tick(1)
		T.eq(S.plot(a) and S.plot(a).slot, 1, "ohne Vorlagen: Slot")
		T.eq(#S.plot(a).stages, 0, "ohne Vorlagen: keine Modelle")
		local run = S.run(a)
		local u1 = S.GC.Tycoon.Buildings.werkstatt.Stages[1].Upgrades[1]
		run.cash = u1.cost
		S.act(a, "tycoon_buy", { id = u1.id })
		T.eq(run.upgrades[u1.id], 1, "ohne Vorlagen: Kauf über Aktion")
		S.tick(2)
		T.check(S.snapshot(a).run.container > 0, "ohne Vorlagen: Produktion")
		-- Alle 8 Grundstücke belegt (höchstens 8 Spieler je Server: Slot 8 wird serverlokal vorbelegt): der Nächste
		-- wartet und bekommt das nächste freie Grundstück im Tick
		buildTemplates(g, S.GC)
		local others = {}
		for i = 2, 7 do
			others[i] = S.join(5400 + i, "Spieler" .. i, "tycoon")
			T.eq(S.plot(others[i]).slot, i, "Slot " .. i)
		end
		local fake = { slot = 8, ms = g:MiniState(others[2]), player = others[2], stages = {}, buttons = {}, conns = {}, padAt = {}, toastAt = {}, labelAt = 0 }
		TS.Plots[8] = fake
		local mark = g:Mark()
		local nine = S.join(5409, "Neun", "tycoon")
		T.eq(S.plot(nine), nil, "kein freies Grundstück")
		T.check(g:HasToast(nine, "alle Grundstücke belegt", mark), "Toast alle belegt")
		T.eq(S.snapshot(nine).slot, false, "Snapshot slot false")
		S.act(nine, "tycoon_choose", { building = "autohaus" })
		T.eq(S.run(nine), nil, "ohne Grundstück kein Durchlauf")
		S.tick(S.GC.Tycoon.PlotRetry or 2.5)
		T.eq(S.plot(nine), nil, "weiter kein Grundstück")
		S.leave(others[5])
		S.tick(S.GC.Tycoon.PlotRetry or 2.5)
		T.eq(S.plot(nine) and S.plot(nine).slot, 5, "Neun bekommt den frei gewordenen Slot 5")
		T.eq(signOwner(S, 5), "Neun", "Schild Slot 5")
		T.check(g:HasToast(nine, "Grundstück 5 gehört dir"), "Toast Grundstück 5")
		S.act(nine, "tycoon_choose", { building = "autohaus" })
		T.check(S.run(nine) ~= nil and #S.plot(nine).stages == 1, "Neun baut Stufe 1")
		TS.Plots[8] = nil
		noErrors(T, g, "Moduswechsel")
	end },
}
