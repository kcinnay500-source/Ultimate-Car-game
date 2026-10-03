-- Ausbaustufe 4, Meilenstein 3 (Team tutorial): TutorialRules (rein), TutorialService im echten Server (eigene
-- Aktionen-Tabelle wie test_prestige, unabhängig von der MiniService-Verkabelung; die Ereignisse kommen aus dem
-- echten 2.4.0-Auftragsablauf über tests/lib/garage_flow.lua) und TutorialUI im Mock-Client.
-- Geprüft: komplettes Tutorial über echte Ereignisse, Überspringen an jeder Stelle, Belohnung genau einmal (auch bei
-- transacting), Hinweise nur im Beginner-Modus und je einmal, Hinweis-Nutzlasten, Speichern/Laden des Schritts.
local NOW = 1760000000

---------------------------------------------------------------- Hilfen
local function ensureMeta(g, d)
	if type(d.games.prestige) ~= "table" or type(d.games.meta) ~= "table" then
		g:MiniShared("MetaRules").ApplyDefault(d.games)
	end
end

local function newProfile(g)
	local d = g:Rules().NewData(NOW)
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	return d
end

-- Server mit TutorialService über eine eigene Aktionen-Tabelle und eine protokollierende api
local function setup(H, opts)
	local g = H.Garage(opts)
	local TS = g:MiniServer("TutorialService")
	local log = { notices = {}, toasts = {}, dirty = 0, changed = 0 }
	local handlers = {}
	local fakeApi = {
		now = function()
			return g:Now()
		end,
		toast = function(ms, text)
			table.insert(log.toasts, { player = ms.player, text = text })
		end,
		notice = function(ms, kind, data)
			table.insert(log.notices, { player = ms.player, kind = kind, data = data })
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
		writable = function()
			return false
		end,
		alive = function()
			return true
		end,
	}
	TS.Register({
		Register = function(name, fn)
			handlers[name] = fn
		end,
	}, fakeApi)
	local S = { g = g, TS = TS, log = log, handlers = handlers }
	function S.join(userId, name)
		local pl = g:Join(userId, { name = name })
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		ensureMeta(g, d)
		-- Startwahl (StartService, test_start.lua): diese Tests prüfen den klassischen Weg; ein neues Profil wählt ihn
		-- hier wie mit start_choose {path = "werkstatt"}, sonst wartet das Tutorial in der Open World auf die Wahl
		local MR = g:MiniShared("MetaRules")
		if MR.StartPending(d) then
			MR.SetStartPath(d, "werkstatt")
		end
		ms.greeted = true
		TS.OnJoin(ms, d, g:Now())
		return pl, ms, d
	end
	function S.act(pl, action, data)
		g:Activate()
		handlers[action](g:MiniState(pl), data or {}, g:D(pl), g:Now())
	end
	function S.event(pl, event)
		g:Activate()
		return TS.OnEvent(g:MiniState(pl), g:D(pl), event)
	end
	function S.tick(pl)
		g:Activate()
		return TS.Tick(g:MiniState(pl), g:D(pl), g:Now())
	end
	function S.notices(pl, kind)
		local out = {}
		for _, n in ipairs(log.notices) do
			if n.player == pl and n.kind == kind then
				table.insert(out, n.data)
			end
		end
		return out
	end
	function S.hasToast(pl, pattern)
		for _, t in ipairs(log.toasts) do
			if t.player == pl and string.find(t.text, pattern, 1, true) then
				return true
			end
		end
		return false
	end
	function S.clear()
		log.notices, log.toasts = {}, {}
	end
	return S
end

local function step(g, d)
	return g:MiniShared("TutorialRules").StepIndex(d)
end

-- Nur speicher-/sendbare Werte (keine Funktionen, keine unendlichen Zahlen, keine gemischten Tabellen)
local function sendable(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "number" then
		return v == v and v ~= math.huge and v ~= -math.huge
	elseif t == "string" or t == "boolean" then
		return true
	elseif t ~= "table" or depth > 10 then
		return false
	end
	local n = #v
	for k, x in pairs(v) do
		if n > 0 and type(k) ~= "number" then
			return false
		end
		if n == 0 and type(k) ~= "string" then
			return false
		end
		if not sendable(x, depth + 1) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- Client-Hilfen (wie test_prestige)
local FORBIDDEN = { amount = true, price = true, cost = true, credits = true, reward = true, money = true, cash = true, xp = true, level = true }

local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
			T.check(not FORBIDDEN[k], action .. ": kein Betrag/Level im Feld " .. tostring(k))
		end
		T.check(n <= 9, action .. ": höchstens 9 Felder")
		table.insert(r.sent, { action, payload })
		return #r.sent
	end
	function r.Count(name)
		local c = 0
		for _, a in ipairs(r.sent) do
			if a[1] == name then
				c += 1
			end
		end
		return c
	end
	function r.Last(name)
		for i = #r.sent, 1, -1 do
			if r.sent[i][1] == name then
				return r.sent[i][2]
			end
		end
		return nil
	end
	return r
end

-- Client ohne GarageClient/MiniClient (run = false): TutorialUI bekommt hier seinen eigenen Kontext und eigene
-- Snapshots; die echte Verkabelung im laufenden Client prüft test_phase4.
local function startClient(H, opts)
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1.5)
	return g, p
end

local function buildUI(g, p, rec)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini.TutorialUI")
	local state = { tablet = false, blocked = false }
	g:InClient(p, function()
		if not MiniUI.Gui then
			MiniUI.Build()
		end
		mod.Start({
			UI = MiniUI, Remote = rec,
			Toast = function() end,
			Close = function()
				MiniUI.Close()
			end,
			IsTabletOpen = function()
				return state.tablet
			end,
			IsBlocked = function()
				return state.blocked
			end,
		})
	end)
	return mod, MiniUI, state
end

local function byName(root, name)
	for _, x in ipairs(root:GetDescendants()) do
		if x.Name == name then
			return x
		end
	end
	return nil
end

local function press(g, button)
	g:Advance(0.35)
	local ok = g:Click(button)
	g:Advance(0.05)
	return ok
end

local function tutorialSnapshot(g, d)
	local TS = g:MiniServer("TutorialService")
	local s = TS.SnapshotFields(nil, d, NOW, true)
	s.level = d.level
	s.credits = 0
	return s
end

---------------------------------------------------------------- Fälle
return {
	{ "TutorialRules: Schritte, Weiter, Ereignisse, Aufträge, Überspringen, Ansicht", function(T, H)
		local g = H.Garage({ noServer = true })
		local TR, GC = g:MiniShared("TutorialRules"), g:MiniShared("GameConfig")
		local d = newProfile(g)
		T.eq(TR.Count(), 11, "11 Schritte (Meilenstein 7: Kiesplatz)")
		T.eq(TR.Count(), GC.Tutorial.Count, "Count = GameConfig")
		T.check(TR.Active(d), "neues Profil: aktiv")
		T.check(not TR.Done(d) and not TR.Skipped(d), "nicht beendet")
		local s, i = TR.Current(d)
		T.eq(i, 1, "Schritt 1")
		T.eq(s and s.id, "move", "erster Schritt move")
		T.check(TR.IsNextStep(s), "move ist Lese-Schritt")
		-- neues Profil ohne Startweg: in der Open World wartet das Tutorial auf die Startwahl, danach Pflicht
		T.check(TR.Waiting(d, "openworld") and not TR.ShouldStart(d, "openworld"), "wartet auf die Startwahl")
		T.check(g:MiniShared("MetaRules").SetStartPath(d, "werkstatt"), "Startweg werkstatt")
		T.check(not TR.Waiting(d, "openworld"), "Wahl getroffen: wartet nicht mehr")
		T.check(TR.ShouldStart(d, "openworld"), "Pflicht in der Open World")
		T.check(not TR.ShouldStart(d, "lobby"), "nicht in der Lobby")
		T.check(not TR.ShouldStart(d, "tycoon"), "nicht im Tycoon")
		-- falsches Ereignis bewegt nichts
		local adv = TR.Advance(d, "station:workshop")
		T.eq(adv, false, "station:workshop erledigt move nicht")
		T.eq(step(g, d), 1, "bleibt bei 1")
		-- Weiter: falscher Schritt / richtiger Schritt / Doppeltipp
		local ok, res = TR.Next(d, 2)
		T.check(not ok and res == TR.Text.wrongStep, "Weiter für Schritt 2 abgelehnt (Meldung)")
		ok, res = TR.Next(d, "1")
		T.check(not ok and type(res) == "string", "Weiter ohne Zahl abgelehnt")
		ok, res = TR.Next(d, 1)
		T.check(ok and res == false, "Weiter Schritt 1")
		T.eq(step(g, d), 2, "jetzt Schritt 2")
		ok, res = TR.Next(d, 1)
		T.check(not ok and res == nil, "Doppeltipp auf Schritt 1: still")
		ok = TR.Next(d, 2)
		T.check(ok, "Weiter Schritt 2 (menu)")
		T.eq(step(g, d), 3, "Schritt 3 reception")
		ok, res = TR.Next(d, 3)
		T.check(not ok and res == TR.Text.notNext, "Schritt 3 ist kein Lese-Schritt")
		-- Stationsbesuch
		local advanced, finished, done = TR.Advance(d, "station:workshop")
		T.check(advanced and not finished and done and done.id == "reception", "station:workshop erledigt reception")
		T.eq(step(g, d), 4, "Schritt 4 accept")
		-- Aufträge (2.4.0-Phasen)
		T.eq(next(TR.JobEvents(d)), nil, "ohne Aufträge keine job:-Ereignisse")
		d.jobs = { { id = "job_1", phase = "diagnose" } }
		local ev = TR.JobEvents(d)
		T.check(ev["job:accepted"] and not ev["job:repair"] and not ev["job:invoice"], "diagnose = accepted")
		T.eq(TR.PendingJobEvent(d), "job:accepted", "Schritt 4 wartet auf job:accepted, erfüllt")
		T.check(TR.Advance(d, "job:accepted"), "accept erledigt")
		T.eq(TR.PendingJobEvent(d), nil, "Schritt 5 (job:repair) noch nicht erfüllt")
		d.jobs[1].phase = "working"
		T.eq(TR.PendingJobEvent(d), "job:repair", "working = repair")
		T.check(TR.Advance(d, "job:repair"), "obd erledigt")
		d.jobs[1].phase = "verify"
		T.eq(TR.PendingJobEvent(d), nil, "verify ist noch nicht invoice")
		d.jobs[1].phase = "invoice"
		T.eq(TR.PendingJobEvent(d), "job:invoice", "invoice")
		T.check(TR.Advance(d, "job:invoice"), "repair erledigt")
		T.eq(step(g, d), 7, "Schritt 7 settle")
		d.jobs = {}
		T.check(TR.Advance(d, "settled"), "settled")
		T.check(TR.Advance(d, "action:mini_travel"), "mini_travel")
		T.check(not TR.Advance(d, "tab:goals"), "tab:goals erledigt dealer nicht")
		T.check(TR.Advance(d, "tab:dealer"), "tab:dealer")
		T.check(not TR.Advance(d, "tab:story"), "tab:story erledigt goals nicht")
		advanced, finished = TR.Advance(d, "tab:goals")
		T.check(advanced and not finished, "Infotafel ist nicht der letzte Schritt")
		advanced, finished = TR.Advance(d, "tab:story")
		T.check(advanced and finished, "letzter Schritt (Kiesplatz) beendet das Tutorial")
		T.check(TR.Done(d) and not TR.Skipped(d), "beendet, nicht übersprungen")
		T.check(not TR.Active(d), "nicht mehr aktiv")
		T.eq(TR.Current(d), nil, "kein aktueller Schritt")
		T.eq(step(g, d), 11, "Schrittzähler bleibt beim letzten Schritt")
		T.check(not TR.Advance(d, "tab:story"), "nach dem Ende nichts mehr")
		T.check(not TR.Skip(d), "Überspringen nach dem Ende: false")
		local v = TR.View(d)
		T.check(v.done and v.active == false and v.step == 11 and v.count == 11, "View nach dem Ende")
		T.check(sendable(v), "View sendbar")
		-- Überspringen mitten drin
		local d2 = newProfile(g)
		TR.Next(d2, 1)
		T.check(TR.Skip(d2), "Überspringen bei Schritt 2")
		T.check(TR.Done(d2) and TR.Skipped(d2) and not TR.Active(d2), "übersprungen = beendet")
		T.eq(TR.View(d2).skipped, true, "View skipped")
		T.eq(TR.ProgressText(3, 10), "Schritt 3 von 10", "Fortschrittstext")
		local r = TR.Reward()
		T.eq(r.credits, 500, "Belohnung 500 Credits")
		T.eq(r.xp, 60, "Belohnung 60 XP")
		-- ohne meta: nil-sicher
		T.check(not TR.Active({}), "ohne meta nicht aktiv")
		T.check(not TR.Advance({}, "next"), "ohne meta kein Fortschritt")
		T.eq(TR.View({ games = {} }).step, 1, "View ohne meta")
	end },

	{ "TutorialRules: Hinweise nur im Beginner-Modus, je einmal, Vorschau ohne Merken", function(T, H)
		local g = H.Garage({ noServer = true })
		local TR, MR = g:MiniShared("TutorialRules"), g:MiniShared("MetaRules")
		local d = newProfile(g)
		T.eq(#TR.PeekHints(d, "station:workshop"), 1, "Vorschau: ein Hinweis")
		T.eq(#TR.PeekHints(d, "station:workshop"), 1, "Vorschau merkt nichts")
		local hints = TR.HintsFor(d, "station:workshop")
		T.eq(#hints, 1, "ein Hinweis")
		T.eq(hints[1] and hints[1].id, "h_workshop", "h_workshop")
		T.eq(d.games.meta.hintsSeen.h_workshop, true, "als gesehen gemerkt")
		T.eq(#TR.HintsFor(d, "station:workshop"), 0, "zweites Mal nichts")
		T.eq(#TR.HintsFor(d, "station:unbekannt"), 0, "unbekannter Auslöser nichts")
		T.eq(#TR.HintsFor(d, nil), 0, "nil-sicher")
		T.eq(#TR.HintsFor(d, "first:jobsDone"), 1, "first:jobsDone")
		T.eq(#TR.HintsFor(d, "unlock:feature:press"), 1, "unlock:feature:press")
		MR.SetSettings(d, { beginner = false })
		T.eq(#TR.HintsFor(d, "station:map"), 0, "ohne Beginner-Modus nichts")
		T.eq(d.games.meta.hintsSeen.h_map, nil, "und nichts gemerkt")
		T.eq(#TR.PeekHints(d, "station:map"), 0, "Vorschau ohne Beginner leer")
		MR.SetSettings(d, { beginner = true })
		T.eq(#TR.HintsFor(d, "station:map"), 1, "wieder an: Hinweis kommt")
	end },

	{ "TutorialService: komplettes Tutorial über echte Ereignisse (2.4.0-Auftrag), Belohnung genau einmal", function(T, H)
		local S = setup(H)
		local g, TS = S.g, S.TS
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local pl, ms, d = S.join(701, "Anna")
		T.eq(#S.notices(pl, "tutorial"), 1, "OnJoin: Hinweis mit dem aktuellen Schritt")
		T.eq(S.notices(pl, "tutorial")[1].step, 1, "Schritt 1")
		T.check(sendable(S.notices(pl, "tutorial")[1]), "Hinweis sendbar")
		S.clear()
		-- Pflicht-Start in der Open World
		T.check(TS.ShouldStart(d, "openworld"), "ShouldStart openworld")
		T.check(TS.Start(ms, d, "openworld"), "Start")
		T.check(not TS.Start(ms, d, "openworld"), "Start nur einmal je Sitzung")
		T.eq(S.notices(pl, "tutorial")[1].started, true, "started-Hinweis")
		S.clear()
		-- 1, 2: Weiter (Client); falscher Schritt wird abgelehnt
		S.act(pl, "tutorial_next", { step = 2 })
		T.eq(step(g, d), 1, "Schritt 2 vorzeitig: nichts")
		T.check(S.hasToast(pl, "Erledige zuerst"), "Toast bei falschem Schritt")
		S.act(pl, "tutorial_next", { step = 1 })
		T.eq(step(g, d), 2, "Weiter -> 2")
		S.act(pl, "tutorial_next", { step = 1 })
		T.eq(step(g, d), 2, "Doppeltipp wirkungslos")
		S.act(pl, "tutorial_next", { step = 2 })
		T.eq(step(g, d), 3, "Weiter -> 3")
		S.act(pl, "tutorial_next", { step = 3 })
		T.eq(step(g, d), 3, "Schritt 3 nicht per Weiter")
		T.check(S.hasToast(pl, "automatisch"), "Toast: kein Lese-Schritt")
		-- 3: Empfang (Plot-Station) + Beginner-Hinweis
		T.check(S.event(pl, "station:workshop"), "station:workshop")
		T.eq(step(g, d), 4, "-> 4 accept")
		T.eq(#S.notices(pl, "hint"), 1, "Hinweis zum Empfang")
		T.eq(S.notices(pl, "hint")[1].id, "h_workshop", "h_workshop")
		-- 4..6: echter Auftrag
		local money0 = d.money
		-- Fahrzeug-Check mit Befund (Ölwechsel): der OBD-Tester findet Fehler, der Kunde muss per Handy freigeben
		local j = Flow.AcceptInspection(T, g, pl, { finding = "oil" })
		T.check(j ~= nil, "Auftrag angenommen")
		T.eq(step(g, d), 4, "vor dem Tick noch 4")
		T.check(S.tick(pl), "Tick erkennt job:accepted")
		T.eq(step(g, d), 5, "-> 5 obd")
		T.check(not S.tick(pl), "nichts Neues")
		local C = g:Config()
		local diag = Flow.Scan(T, g, pl, j.id, { auto = true })
		T.check(diag ~= nil, "diagnose-Event")
		T.eq(diag and diag.phase, "approval", "Fehler gespeichert: Freigabe nötig")
		S.tick(pl)
		T.eq(step(g, d), 5, "Scan allein reicht nicht (Phase approval: Kunde anrufen)")
		local answer = Flow.Call(T, g, pl, j.id, { decision = true })
		T.eq(answer and answer.accepted, true, "Kunde gibt frei")
		T.check(S.tick(pl) or step(g, d) == 6, "Tick erkennt job:repair")
		T.eq(step(g, d), 6, "-> 6 repair")
		local def = C.JobById[Flow.Job(g, pl, j.id).kind]
		T.eq(def.id, "oil", "freigegebener Befund: Ölwechsel")
		for i = 1, #def.steps do
			T.check(Flow.RepairStep(T, g, pl, j.id, i), "Reparaturschritt " .. i)
			S.tick(pl)
		end
		T.eq(step(g, d), 6, "vor der Endkontrolle noch 6")
		Flow.Scan(T, g, pl, j.id)
		T.eq(Flow.Job(g, pl, j.id) and Flow.Job(g, pl, j.id).phase, "invoice", "Phase invoice")
		-- (der echte Mini.Tick kann den Schritt schon erkannt haben, seit MiniService TutorialService.Tick ruft)
		T.check(S.tick(pl) or step(g, d) == 7, "Tick erkennt job:invoice")
		T.eq(step(g, d), 7, "-> 7 settle")
		-- 7: Abrechnen (GarageServer -> Mini.OnSettled -> Integrator -> OnEvent 'settled')
		g:Teleport(pl, g:Station(pl, "workshop"), Vector3.new(0, 0, 3))
		g:Advance(0.2)
		local m = g:Mark()
		g:Send(pl, "settle", { id = j.id })
		T.check(g:Last(pl, "receipt", m) ~= nil, "Quittung")
		-- Mini.OnSettled meldet 'settled' schon selbst; die Kurzform ist dann wirkungslos (kein zweiter Schritt)
		T.check(S.event(pl, "settle") or step(g, d) == 8, "settle (Kurzform)")
		T.eq(step(g, d), 8, "-> 8 map")
		-- 8..10: Stadt
		T.check(not S.event(pl, "action:mini_sync"), "andere Aktion zählt nicht")
		T.check(S.event(pl, "action:mini_travel"), "action:mini_travel")
		T.eq(step(g, d), 9, "-> 9 dealer")
		T.check(not TS.OnStation(ms, d, "goals", "goals"), "Infotafel zu früh")
		T.check(TS.OnStation(ms, d, "dealer", "dealer"), "Autohaus (Stadt-Station)")
		T.eq(step(g, d), 10, "-> 10 goals")
		T.check(not TS.OnStation(ms, d, "kiesplatz", "story"), "Kiesplatz zu früh")
		T.check(TS.OnStation(ms, d, "goals", "goals"), "Infotafel (Stadt-Station)")
		T.eq(step(g, d), 11, "-> 11 kiesplatz")
		local moneyBefore, xpBefore, levelBefore = d.money, d.xp, d.level
		S.log.changed = 0
		T.check(TS.OnStation(ms, d, "kiesplatz", "story"), "Kiesplatz beendet das Tutorial")
		T.check(d.games.meta.tutorialDone and not d.games.meta.tutorialSkipped, "beendet")
		local gained = d.money - moneyBefore
		T.check(gained >= 500, "mindestens 500 Credits (" .. tostring(gained) .. ")")
		T.check(d.level > levelBefore or d.xp == xpBefore + 60, "60 XP verbucht")
		T.check(S.log.changed >= 1, "api.changed für die 2.4.0-Revision")
		T.check(S.hasToast(pl, "Tutorial geschafft"), "Toast Tutorial geschafft")
		local list = S.notices(pl, "tutorial")
		local last = list[#list]
		T.check(last and last.finished == true and last.done == true and last.active == false, "letzter Hinweis finished/done")
		T.eq(last and last.step, 11, "Schritt 11")
		for _, n in ipairs(list) do
			T.check(sendable(n), "tutorial-Hinweis sendbar")
		end
		-- kein zweites Mal
		local moneyDone = d.money
		T.check(not TS.OnStation(ms, d, "kiesplatz", "story"), "nach dem Ende nichts")
		S.act(pl, "tutorial_next", { step = 11 })
		S.act(pl, "tutorial_skip")
		T.check(not S.tick(pl), "Tick nach dem Ende ruhig")
		T.eq(d.money, moneyDone, "Belohnung nur einmal")
		T.eq(d.games.meta.tutorialSkipped, false, "Überspringen nach dem Ende ohne Wirkung")
		local f = TS.SnapshotFields(ms, d, g:Now(), true)
		T.check(f.tutorial and f.tutorial.done == true and f.tutorial.active == false, "Snapshot done")
		T.check(sendable(f), "Snapshot sendbar")
		T.check(#g:Errors() == 0, "keine Serverfehler: " .. g:ErrorText())
	end },

	{ "TutorialService: Überspringen an jeder Stelle, ohne Belohnung; danach still", function(T, H)
		for _, at in ipairs({ 1, 2, 4, 7, 10, 11 }) do
			local S = setup(H)
			local g = S.g
			local pl, ms, d = S.join(710 + at, "Skip" .. at)
			local TR = g:MiniShared("TutorialRules")
			-- bis zum Schritt `at` vorspulen (über die echten Ereignisse der Schritte)
			while step(g, d) < at do
				local s = TR.Current(d)
				if s.event == "next" then
					S.act(pl, "tutorial_next", { step = step(g, d) })
				else
					S.event(pl, s.event)
				end
			end
			T.eq(step(g, d), at, "bei Schritt " .. at)
			local money = d.money
			S.clear()
			S.act(pl, "tutorial_skip")
			T.check(d.games.meta.tutorialDone and d.games.meta.tutorialSkipped, "übersprungen bei " .. at)
			T.eq(d.money, money, "keine Belohnung bei " .. at)
			local n = S.notices(pl, "tutorial")
			T.check(n[1] and n[1].skipped == true and n[1].done == true and n[1].active == false, "skipped-Hinweis bei " .. at)
			T.check(S.hasToast(pl, "übersprungen"), "Toast bei " .. at)
			S.clear()
			S.act(pl, "tutorial_skip")
			S.act(pl, "tutorial_next", { step = at })
			T.eq(#S.notices(pl, "tutorial"), 0, "danach still bei " .. at)
			T.eq(#S.log.toasts, 0, "kein Toast mehr bei " .. at)
			T.check(not S.event(pl, "station:workshop"), "Ereignisse wirkungslos bei " .. at)
			T.eq(step(g, d), at, "Schritt bleibt stehen bei " .. at)
			local f = S.TS.SnapshotFields(ms, d, g:Now(), false)
			T.check(f.tutorial.skipped == true and f.tutorial.done == true, "Snapshot skipped bei " .. at)
		end
	end },

	{ "TutorialService: Hinweise nur im Beginner-Modus und je einmal (Station, Stadt, first:<stat>)", function(T, H)
		local S = setup(H)
		local g, TS = S.g, S.TS
		local MR, MiniRules = g:MiniShared("MetaRules"), g:MiniShared("MiniRules")
		local pl, ms, d = S.join(721, "Ben")
		local p2, ms2, d2 = S.join(722, "Cleo")
		S.clear()
		T.eq(TS.Hint(ms, d, "station:workshop"), 1, "Hinweis zum Empfang")
		T.eq(TS.Hint(ms, d, "station:workshop"), 0, "nicht noch einmal")
		local h = S.notices(pl, "hint")[1]
		T.check(h and h.id == "h_workshop" and type(h.text) == "string" and h.trigger == "station:workshop", "Nutzlast id/text/trigger")
		T.eq(#S.notices(p2, "hint"), 0, "anderer Spieler ohne Hinweis")
		-- Stadt-Station: Hinweis station:<key> + Tutorial-Ereignis tab:<tab>
		TS.OnStation(ms, d, "map", "map")
		T.eq(#S.notices(pl, "hint"), 2, "Hinweis zum Stadtplan")
		T.eq(S.notices(pl, "hint")[2].id, "h_map", "h_map")
		TS.OnStation(ms, d, "shop", "shop")
		T.eq(S.notices(pl, "hint")[3] and S.notices(pl, "hint")[3].id, "h_shop", "h_shop")
		-- Statistik: erst > 0 löst aus, und nur einmal
		T.eq(TS.OnStat(ms, d, "jobsDone"), 0, "jobsDone 0: kein Hinweis")
		MiniRules.AddStat(d, "jobsDone", 1, g:Now())
		T.eq(TS.OnStat(ms, d, "jobsDone"), 1, "erster Auftrag")
		MiniRules.AddStat(d, "jobsDone", 1, g:Now())
		T.eq(TS.OnStat(ms, d, "jobsDone"), 0, "zweiter Auftrag: nichts")
		T.eq(TS.OnStat(ms, d, "unbekannt"), 0, "unbekannte Statistik")
		-- kein Beginner: nichts, auch nicht gemerkt
		MR.SetSettings(d2, { beginner = false })
		T.eq(TS.Hint(ms2, d2, "station:workshop"), 0, "ohne Beginner-Modus nichts")
		TS.OnEvent(ms2, d2, "station:workshop")
		T.eq(#S.notices(p2, "hint"), 0, "auch über OnEvent nichts")
		T.eq(d2.games.meta.hintsSeen.h_workshop, nil, "nicht als gesehen gemerkt")
		T.eq(step(g, d2), 1, "Tutorial-Schritt bleibt (station:workshop passt nicht zu move)")
		-- Hinweise vor 'hello' warten in der Warteschlange
		ms.greeted = false
		S.clear()
		TS.Hint(ms, d, "first:dismantled")
		T.eq(#S.notices(pl, "hint"), 0, "vor hello nichts gesendet")
		MiniRules.AddStat(d, "dismantled", 1, g:Now())
		T.eq(TS.OnStat(ms, d, "dismantled"), 0, "schon gemerkt (Warteschlange zählt)")
		ms.greeted = true
		TS.Flush(ms)
		T.eq(#S.notices(pl, "hint"), 1, "nach hello nachgeliefert")
		T.check(sendable(S.notices(pl, "hint")[1]), "sendbar")
	end },

	{ "TutorialService: Belohnung wird während transacting zurückgehalten und im Tick nachgeholt; OnLeave verbucht", function(T, H)
		local S = setup(H)
		local g, TS = S.g, S.TS
		local TR = g:MiniShared("TutorialRules")
		local function toLast(pl, d)
			while step(g, d) < TR.Count() do
				local s = TR.Current(d)
				if s.event == "next" then
					S.act(pl, "tutorial_next", { step = step(g, d) })
				else
					S.event(pl, s.event)
				end
			end
		end
		local pl, ms, d = S.join(731, "Dana")
		toLast(pl, d)
		local prof = g:Profile(pl)
		prof.transacting = true
		local money, xp, level = d.money, d.xp, d.level
		S.clear()
		T.check(S.event(pl, "tab:story"), "Ende während transacting")
		T.check(d.games.meta.tutorialDone, "beendet")
		T.eq(d.money, money, "Geld noch nicht verbucht")
		T.eq(ms.tutorialRewardPending, true, "Belohnung wartet")
		T.eq(TS.SnapshotFields(ms, d, g:Now()).tutorial.rewardPending, true, "Snapshot rewardPending")
		T.check(not S.tick(pl), "Tick während transacting: nichts")
		T.eq(d.money, money, "immer noch nichts")
		prof.transacting = false
		T.check(S.tick(pl), "Tick verbucht")
		T.check(d.money - money >= 500, "500 Credits")
		T.check(d.level > level or d.xp == xp + 60, "60 XP")
		T.eq(ms.tutorialRewardPending, nil, "nichts mehr offen")
		local after = d.money
		T.check(not S.tick(pl), "kein zweites Mal")
		T.eq(d.money, after, "nur einmal")
		-- OnLeave verbucht eine offene Belohnung vor dem Speichern
		local p2, ms2, d2 = S.join(732, "Emil")
		toLast(p2, d2)
		local prof2 = g:Profile(p2)
		prof2.transacting = true
		local money2 = d2.money
		S.event(p2, "tab:story")
		T.eq(d2.money, money2, "zurückgehalten")
		prof2.transacting = false
		TS.OnLeave(ms2, d2)
		T.check(d2.money - money2 >= 500, "OnLeave verbucht")
		TS.OnLeave(ms2, d2)
		T.eq(ms2.tutorialRewardPending, nil, "OnLeave nur einmal")
	end },

	{ "Speichern/Laden: Schritt und Hinweise überleben Rejoin (sobald MiniRules meta lädt), zwei Spieler getrennt", function(T, H)
		local S = setup(H)
		local g, TS = S.g, S.TS
		local pl, ms, d = S.join(741, "Finn")
		local p2, ms2, d2 = S.join(742, "Gina")
		S.act(pl, "tutorial_next", { step = 1 })
		S.act(pl, "tutorial_next", { step = 2 })
		S.event(pl, "station:workshop")
		T.eq(step(g, d), 4, "Finn bei 4")
		T.eq(step(g, d2), 1, "Gina bei 1")
		T.eq(#S.notices(p2, "hint"), 0, "Gina ohne Hinweis")
		g:Leave(pl)
		g:Advance(1)
		local rec = g:Record(741)
		T.check(rec ~= nil and rec.data ~= nil, "Datensatz gespeichert")
		local savedMeta = rec and rec.data.games and rec.data.games.meta
		local MR, MiniRules = g:MiniShared("MetaRules"), g:MiniShared("MiniRules")
		T.check(type(savedMeta) == "table", "meta im Datensatz")
		if type(savedMeta) == "table" then
			T.eq(savedMeta.tutorialStep, 4, "tutorialStep im Datensatz")
			T.eq(savedMeta.hintsSeen and savedMeta.hintsSeen.h_workshop, true, "hintsSeen im Datensatz")
		end
		-- Lädt MiniRules.LoadGames meta schon (Integrator, Schritt 1)? Sonst Rundreise nur über MetaRules.Load.
		local reloaded = MiniRules.LoadGames(rec and rec.data.games, rec and rec.data, g:Now())
		local wired = type(reloaded) == "table" and type(reloaded.meta) == "table" and reloaded.meta.tutorialStep == 4
		if wired then
			local pl3, ms3, d3 = S.join(741, "Finn")
			T.eq(step(g, d3), 4, "nach Rejoin bei 4")
			T.eq(d3.games.meta.hintsSeen.h_workshop, true, "Hinweis bleibt gesehen")
			T.eq(S.notices(pl3, "tutorial")[1] and S.notices(pl3, "tutorial")[1].step, 4, "OnJoin meldet Schritt 4")
			S.clear()
			T.eq(TS.Hint(ms3, d3, "station:workshop"), 0, "nach Rejoin nicht erneut")
		else
			-- MiniRules.LoadGames kennt meta erst nach der Verkabelung (Integrator, Schritt 1): Rundreise über MetaRules
			T.check(true, "meta noch nicht in LoadGames verkabelt")
			local loaded = MR.Load(savedMeta, rec and rec.data or d, g:Now())
			T.eq(loaded.tutorialStep, 4, "MetaRules.Load hält den Schritt")
			T.eq(loaded.hintsSeen.h_workshop, true, "MetaRules.Load hält die Hinweise")
		end
		-- 2.4.0-Veteran: Tutorial gilt als beendet, kein Zwang
		local vet = g:Rules().NewData(NOW)
		vet.completed = 12
		local m = MR.Load(nil, vet, NOW)
		vet.games.meta = m
		T.check(not TS.ShouldStart(vet, "openworld"), "Veteran ohne Tutorial-Pflicht")
	end },

	{ "Echter Weg über Remotes.Command (sobald MiniNet tutorial_next/tutorial_skip kennt)", function(T, H)
		local g = H.Garage()
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.Actions.tutorial_next or not MiniNet.Actions.tutorial_skip then
			T.check(true, "MiniNet kennt die Aktionen noch nicht (Integrator, Schritt 4)")
			return
		end
		local pl = g:Join(751, { name = "Hanna" })
		g:Advance(1)
		local d = g:D(pl)
		ensureMeta(g, d)
		T.eq(g:Act(pl, "tutorial_next", { step = "1" }), "invalid", "step muss number sein")
		T.eq(g:Act(pl, "start_choose", { path = "werkstatt", rid = 100 }), "ok", "Startwahl werkstatt")
		T.eq(g:MiniShared("MetaRules").StartPath(d), "werkstatt", "Startweg gespeichert")
		g:Advance(0.2)
		T.eq(g:Act(pl, "tutorial_next", { step = 1, rid = 1 }), "ok", "Weiter angenommen")
		T.eq(step(g, d), 2, "Schritt 2")
		g:Advance(0.5)
		T.eq(g:Act(pl, "tutorial_next", { step = 1, rid = 1 }), "duplicate", "gleiche rid")
		g:Advance(0.5)
		T.eq(g:Act(pl, "tutorial_skip", { rid = 2 }), "ok", "Überspringen")
		T.check(d.games.meta.tutorialDone and d.games.meta.tutorialSkipped, "übersprungen")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and type(snap.tutorial) == "table" and snap.tutorial.skipped == true, "Snapshot tutorial.skipped")
	end },

	{ "TutorialUI: Karte über der Leiste, Weiter/Überspringen, Marker am Ziel, Hinweis- und Freischaltungskarte", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, MiniUI, state = buildUI(g, p, rec)
		local gui = p.PlayerGui:FindFirstChild("Tutorial")
		T.check(gui ~= nil and gui.ClassName == "ScreenGui", "ScreenGui Tutorial")
		T.check(gui and gui.DisplayOrder == 17, "DisplayOrder 17: unter dem 2.4.0-UI (20), damit Dialoge, Tablet und Fahrzeugknöpfe immer den Klick bekommen")
		local cardFrame = byName(gui, "Card")
		T.check(cardFrame ~= nil and cardFrame.Visible == false, "Karte anfangs unsichtbar")
		if cardFrame then
			T.eq(cardFrame.AnchorPoint.X, 0.5, "mittig")
			T.eq(cardFrame.AnchorPoint.Y, 1, "unten verankert")
			T.eq(cardFrame.Position.Y.Scale, 1, "an der Unterkante")
			T.check(cardFrame.Position.Y.Offset <= -138, "über der 2.4.0-Leiste (132 px + Rand): " .. tostring(cardFrame.Position.Y.Offset))
		end
		-- Snapshot: Schritt 1 (Lese-Schritt)
		local d = newProfile(g)
		g:InClient(p, function()
			mod.Render(tutorialSnapshot(g, d))
		end)
		T.check(mod.CardVisible(), "Karte sichtbar")
		local progress, text = byName(gui, "Progress"), byName(gui, "Text")
		T.eq(progress and progress.Text, "Schritt 1 von " .. tostring(g:MiniShared("TutorialRules").Count()), "Fortschritt")
		T.check(text and text.Text:find("Willkommen", 1, true), "Schritt-Text")
		local nextB, skipB = byName(gui, "Next"), byName(gui, "Skip")
		T.check(nextB and nextB.Visible and skipB and skipB.Visible, "Weiter und Überspringen sichtbar")
		T.check(nextB and nextB.AbsoluteSize.Y >= 44 and skipB.AbsoluteSize.Y >= 44, "Touch-Flächen 44 px")
		T.check(press(g, nextB), "Klick Weiter")
		T.eq(rec.Count("tutorial_next"), 1, "tutorial_next gesendet")
		T.eq(rec.Last("tutorial_next").step, 1, "step = 1")
		-- Schritt 3 (Empfang): kein Weiter, Marker am Empfang des eigenen Grundstücks
		local TR = g:MiniShared("TutorialRules")
		TR.Next(d, 1)
		TR.Next(d, 2)
		g:InClient(p, function()
			mod.OnNotice({ kind = "tutorial", step = 3, count = 10, id = "reception", text = "Geh zum Empfang", target = "workshop", zone = "plot", next = false, done = false, skipped = false, active = true })
			mod.Step(0.3)
		end)
		T.eq(progress and progress.Text, "Schritt 3 von 10", "Fortschritt 3")
		T.check(nextB and not nextB.Visible, "kein Weiter bei Ereignis-Schritt")
		T.check(skipB and skipB.Visible, "Überspringen immer")
		local target = mod.MarkerTarget()
		T.check(target ~= nil and target == g:Station(p, "workshop"), "Marker am Empfang: " .. tostring(target and target:GetFullName()))
		local markerGui = byName(gui, "TutorialMarker")
		T.check(markerGui and markerGui.AlwaysOnTop == true and markerGui.Enabled == true, "BillboardGui AlwaysOnTop")
		T.check(press(g, skipB), "Klick Überspringen")
		T.eq(rec.Count("tutorial_skip"), 1, "tutorial_skip gesendet")
		-- Stadt-Ziel
		g:BuildCity({ stations = { { key = "dealer", tab = "dealer", pos = Vector3.new(50, 1, -200) } } })
		g:InClient(p, function()
			mod.OnNotice({ kind = "tutorial", step = 9, count = 10, id = "dealer", text = "Schau im Autohaus vorbei.", target = "dealer", zone = "city", next = false, done = false, skipped = false, active = true })
			mod.Step(0.3)
		end)
		local city = g:Find("Workspace.City") or g.env.workspace:FindFirstChild("City")
		T.check(mod.MarkerTarget() ~= nil and mod.MarkerTarget().Name == "dealer" and city and mod.MarkerTarget():IsDescendantOf(city), "Marker am Autohaus der Stadt")
		-- Hinweis-Karte oben rechts, unter dem Abzeichen (mind. 60 px Abstand zur Oberkante)
		g:InClient(p, function()
			mod.OnNotice({ kind = "hint", id = "h_workshop", text = "Am Empfang nimmst du Aufträge an." })
		end)
		T.check(mod.HintVisible(), "Hinweis sichtbar")
		local hintCard = byName(gui, "HintCard")
		T.check(hintCard and hintCard.AnchorPoint.X == 1 and hintCard.Position.X.Offset == -16, "oben rechts, 16 px Rand")
		T.check(hintCard and hintCard.Position.Y.Offset >= 60, "unter dem Abzeichen: " .. tostring(hintCard and hintCard.Position.Y.Offset))
		T.check(byName(hintCard, "Text").Text:find("Empfang", 1, true), "Hinweistext")
		g:Advance(mod.HintSeconds + 0.5)
		T.check(not mod.HintVisible(), "Hinweis blendet aus")
		-- Freischaltungs-Karte (UnlocksUI nicht geladen -> TutorialUI zeigt sie)
		g:InClient(p, function()
			mod.OnNotice({ kind = "unlock", key = "feature:press", title = "Schrottpresse", level = 2, kind2 = nil })
		end)
		T.check(mod.UnlockVisible(), "Freischaltungs-Karte sichtbar")
		local unlockCard = byName(gui, "UnlockCard")
		T.check(unlockCard and byName(unlockCard, "Title").Text == "Freigeschaltet: Schrottpresse", "Titel")
		g:Advance(mod.UnlockSeconds + 0.5)
		T.check(not mod.UnlockVisible(), "Freischaltungs-Karte blendet aus")
		-- Ende: kurze Erfolgskarte, danach weg
		g:InClient(p, function()
			mod.OnNotice({ kind = "tutorial", step = 10, count = 10, id = "goals", text = "…", next = false, done = true, skipped = false, active = false, finished = true })
		end)
		T.check(mod.CardVisible() and progress.Text:find("geschafft", 1, true), "Erfolgskarte")
		T.check(nextB and not nextB.Visible and skipB and not skipB.Visible, "keine Knöpfe mehr")
		T.eq(mod.MarkerTarget(), nil, "Marker weg")
		g:Advance(mod.FinishSeconds + 0.5)
		g:InClient(p, function()
			mod.Step(0.3)
		end)
		T.check(not mod.CardVisible(), "Karte nach dem Ende weg")
		-- übersprungen: sofort weg
		g:InClient(p, function()
			mod.OnNotice({ kind = "tutorial", step = 4, count = 10, id = "accept", text = "…", next = false, done = true, skipped = true, active = false })
		end)
		T.check(not mod.CardVisible(), "nach Überspringen keine Karte")
		-- Tablet/Panel/QTE: Karte weicht
		g:InClient(p, function()
			mod.Render(tutorialSnapshot(g, newProfile(g)))
		end)
		T.check(mod.CardVisible(), "wieder sichtbar")
		state.tablet = true
		g:InClient(p, function()
			mod.Step(0.3)
		end)
		T.check(not mod.CardVisible(), "Tablet offen: Karte weg")
		state.tablet = false
		state.blocked = true
		g:InClient(p, function()
			mod.Step(0.3)
		end)
		T.check(not mod.CardVisible(), "QTE: Karte weg")
		state.blocked = false
		g:InClient(p, function()
			mod.Step(0.3)
		end)
		T.check(mod.CardVisible(), "danach wieder da")
		T.check(#g:Errors() == 0, "keine Clientfehler: " .. g:ErrorText())
	end },

	{ "TutorialUI: Handy hochkant – Karte passt in die Breite, Knöpfe teilen sich die Zeile; menu-Schritt per Panel", function(T, H)
		local g, p = startClient(H, { viewport = Vector2.new(390, 844) })
		local rec = recorder(T)
		local mod, MiniUI = buildUI(g, p, rec)
		local gui = p.PlayerGui:FindFirstChild("Tutorial")
		local d = newProfile(g)
		g:InClient(p, function()
			mod.Render(tutorialSnapshot(g, d))
			mod.Step(0.3)
		end)
		local cardFrame = byName(gui, "Card")
		T.check(cardFrame and cardFrame.AbsoluteSize.X <= 390 - 24 and cardFrame.AbsoluteSize.X > 0, "Karte schmaler als der Bildschirm: " .. tostring(cardFrame and cardFrame.AbsoluteSize.X))
		local nextB, skipB = byName(gui, "Next"), byName(gui, "Skip")
		T.check(nextB and skipB and nextB.AbsoluteSize.X + skipB.AbsoluteSize.X <= cardFrame.AbsoluteSize.X, "Knöpfe passen nebeneinander")
		T.check(nextB.AbsoluteSize.Y >= 44, "Touch-Höhe")
		-- Schritt 2 „menu“: sobald das Minispiel-Panel offen war, sendet der Client Weiter – genau einmal
		local TR = g:MiniShared("TutorialRules")
		TR.Next(d, 1)
		g:InClient(p, function()
			mod.Render(tutorialSnapshot(g, d))
			MiniUI.Open("overview")
			mod.Step(0.3)
			mod.Step(0.3)
		end)
		T.eq(rec.Count("tutorial_next"), 1, "menu-Schritt automatisch")
		T.eq(rec.Last("tutorial_next").step, 2, "step = 2")
		T.check(not mod.CardVisible(), "bei offenem Panel keine Karte")
		g:InClient(p, function()
			MiniUI.Close()
			mod.Step(0.3)
		end)
		T.check(mod.CardVisible(), "nach dem Schließen wieder da")
		T.check(#g:Errors() == 0, "keine Clientfehler: " .. g:ErrorText())
	end },
	{ "TutorialUI: Karte rückt über die 2.4.0-Fahrzeugknöpfe (E/F/H), wenn sie sich überschneiden; Endkarte nach Neustart ohne Belohnungs-Versprechen", function(T, H)
		local g, p = startClient(H, { viewport = Vector2.new(1000, 700) })
		local rec = recorder(T)
		local mod = buildUI(g, p, rec)
		local gui = p.PlayerGui:FindFirstChild("Tutorial")
		local d = newProfile(g)
		g:InClient(p, function()
			mod.Render(tutorialSnapshot(g, d))
			mod.Step(0.3)
		end)
		local cardFrame = byName(gui, "Card")
		T.eq(cardFrame.Position.Y.Offset, -mod.CardBottom, "ohne Fahrzeugknöpfe: Standardlage")
		-- 2.4.0-Leiste der Fahrzeugknöpfe (GarageClient: 360×126 bei x 12, Unterkante 150 px über dem Rand)
		local va
		g:InClient(p, function()
			local sg = Instance.new("ScreenGui")
			sg.Name = "GarageUI"
			sg.Parent = p.PlayerGui
			va = Instance.new("Frame")
			va.Name = "VehicleActions"
			va.Size = UDim2.fromOffset(360, 126)
			va.Position = UDim2.new(0, 12, 1, -276)
			va.Visible = true
			va.Parent = sg
			mod.Step(0.3)
		end)
		T.check(cardFrame.Position.Y.Offset <= -(mod.CardBottom + 126 + 8), "Karte über den Fahrzeugknöpfen: " .. tostring(cardFrame.Position.Y.Offset))
		local cardBottom = cardFrame.AbsolutePosition.Y + cardFrame.AbsoluteSize.Y
		T.check(cardBottom <= va.AbsolutePosition.Y + 1, "keine Überdeckung: Karte endet bei " .. tostring(cardBottom) .. ", Knöpfe beginnen bei " .. tostring(va.AbsolutePosition.Y))
		g:InClient(p, function()
			va.Visible = false
			mod.Step(0.3)
		end)
		T.eq(cardFrame.Position.Y.Offset, -mod.CardBottom, "Knöpfe weg: Karte zurück")
		-- Endkarte: erster Abschluss nennt die Belohnung, nach einem Neustart (again = true) nicht
		local text = byName(gui, "Text")
		g:InClient(p, function()
			mod.OnNotice({ kind = "tutorial", step = 11, count = 11, id = "kiesplatz", text = "…", next = false, done = true, skipped = false, active = false, finished = true })
		end)
		T.check(text.Text:find("Belohnung", 1, true) ~= nil, "erste Endkarte mit Belohnung")
		g:Advance(mod.FinishSeconds + 0.5)
		g:InClient(p, function()
			mod.OnNotice({ kind = "tutorial", step = 11, count = 11, id = "kiesplatz", text = "…", next = false, done = true, skipped = false, active = false, finished = true, again = true })
		end)
		T.check(mod.CardVisible() and text.Text:find("noch einmal geschafft", 1, true) ~= nil and text.Text:find("Belohnung", 1, true) == nil, "Endkarte nach Neustart ohne Belohnung: " .. tostring(text.Text))
		T.check(#g:Errors() == 0, "keine Clientfehler: " .. g:ErrorText())
	end },
	{ "Tutorial-Schritt action:<name> nur nach gelungener Aktion (abgelehntes Abholen zählt nicht)", function(T, H)
		local g = H.Garage({})
		local p = g:Join(7411, { name = "Abholer" })
		g:Advance(1)
		local TR = g:MiniShared("TutorialRules")
		local d = g:D(p)
		T.eq(g:Act(p, "start_choose", { path = "autohaus" }), "ok", "Startweg Autohaus")
		g:Advance(0.5)
		local guard = 0
		while TR.Current(d, "openworld") and TR.Current(d, "openworld").event == "next" and guard < 5 do
			guard += 1
			g:Act(p, "tutorial_next", { step = d.games.meta.tutorialStep })
			g:Advance(0.2)
		end
		local cur = TR.Current(d, "openworld")
		if not T.eq(cur and cur.id, "ah_collect", "beim Schritt Abholen") then
			return
		end
		local step = d.games.meta.tutorialStep
		-- abgelehnt: Gebäude nicht gebaut / unbekannt -> nur Toast, kein Schritt
		g:Act(p, "ow_collect", { typ = "produktion" })
		g:Advance(1.1)
		T.eq(d.games.meta.tutorialStep, step, "Abholen ohne Gebäude erledigt den Schritt nicht")
		g:Act(p, "ow_collect", { typ = "mars" })
		g:Advance(1.1)
		T.eq(d.games.meta.tutorialStep, step, "unbekanntes Gebäude erledigt den Schritt nicht")
		-- gelungen: Ertrag des geschenkten Autohauses
		local money = d.money
		T.eq(g:Act(p, "ow_collect", { typ = "autohaus" }), "ok", "Abholen beim Autohaus")
		T.check(d.money > money, "Credits abgeholt")
		T.eq(d.games.meta.tutorialStep, step + 1, "gelungenes Abholen erledigt den Schritt")
		T.eq(#g:Errors(), 0, "keine Fehler: " .. g:ErrorText())
	end },
}
