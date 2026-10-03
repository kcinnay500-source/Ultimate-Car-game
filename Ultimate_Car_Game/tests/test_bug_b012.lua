local NOW = 1760000000
---------------------------------------------------------------- Client (ArcadeUI im Mock)
-- Aufzeichnungs-Remote: flache Nutzlast, höchstens 9 Felder, nur string/number/boolean
local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
		end
		T.check(n <= 9, action .. ": höchstens 9 Felder")
		table.insert(r.sent, { action = action, payload = payload, rid = #r.sent + 1 })
		return #r.sent
	end
	r.SendRaw = r.Send
	function r.Of(name, since)
		local out = {}
		for i = (since or 0) + 1, #r.sent do
			if r.sent[i].action == name then
				table.insert(out, r.sent[i])
			end
		end
		return out
	end
	return r
end

local function find(root, name)
	for _, x in ipairs(root:GetDescendants()) do
		if x.Name == name then
			return x
		end
	end
	return nil
end

-- Client mit eigener ScreenGui für ArcadeUI; Server-Runden entstehen mit ArcadeRules (Server-Instanz)
local function uiSetup(T, H)
	local g = H.Garage({ level = 12 })
	local pl = g:Join(1101, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(pl)
	g:Advance(1.5)
	local rec = recorder(T)
	local MiniUI = g:ClientModule(pl, "Mini.MiniUI")
	local AUI = g:ClientModule(pl, "Mini.ArcadeUI")
	local toasts = {}
	local page, gui = g:InClient(pl, function()
		local sg = Instance.new("ScreenGui")
		sg.Name = "ArcadeTest"
		sg.ResetOnSpawn = false
		sg.Parent = pl.PlayerGui
		local f = MiniUI.Frame(sg, { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(0, 380, 0, 0) })
		MiniUI.List(f, 12)
		AUI.Build(f, {
			UI = MiniUI, Remote = rec,
			Toast = function(t)
				table.insert(toasts, t)
			end,
			Close = function() end,
		})
		return f, sg
	end)
	local S = { g = g, pl = pl, rec = rec, AUI = AUI, page = page, gui = gui, toasts = toasts, A = g:MiniShared("ArcadeRules"), H = H, T = T }
	function S.notice(data)
		local copy = H.Copy(data)
		g:InClient(pl, function()
			AUI.OnNotice(copy)
		end)
	end
	function S.render(snap)
		g:InClient(pl, function()
			AUI.Render(snap)
		end)
	end
	-- Runde wie ArcadeService: Server-Runde + Rundenpaket an den Client
	function S.round(key, seed, token, capLeft)
		local round = S.A.NewRound(key, seed, g:Now(), token)
		local view = S.A.View(round)
		view.kind = "arcade_round"
		view.capLeft = capLeft or 1400
		view.best = 0
		view.reward = S.A.GameByKey[key].reward
		S.mark = #rec.sent
		S.notice(view)
		return round
	end
	-- Gesendete Eingaben seit der letzten Weiterleitung an die Server-Runde geben (Ankunft 0,03 s später).
	-- Rückgabe: Liste { payload, ok, info }
	function S.forward(round)
		local out = {}
		for _, e in ipairs(rec.Of("mini_arcade_input", S.mark)) do
			local ok, info = S.A.Input(round, e.payload.at, e.payload.value, e.payload.at + 0.03)
			T.eq(e.payload.token, round.token, "Token der Runde")
			table.insert(out, { payload = e.payload, ok = ok, info = info, rid = e.rid })
		end
		S.mark = #rec.sent
		return out
	end
	function S.click(name)
		local b = find(page, name)
		T.check(b ~= nil, "Knopf " .. name)
		if b then
			g:Click(b)
		end
		return b
	end
	function S.visible(name)
		local x = find(page, name)
		return x ~= nil and H.Mock.IsGuiVisible(x)
	end
	-- wie ArcadeService: BLITZ-REAKTION meldet jedes Lampen-Aus erst in dem Moment (arcade_go)
	function S.at(round, t)
		g:AdvanceTo(round.startAt + t)
		round.goSent = round.goSent or {}
		for _, ev in ipairs(S.A.GoEvents(round)) do
			if not round.goSent[ev.attempt] and ev.at <= g:Now() + 1e-9 then
				round.goSent[ev.attempt] = true
				local go = S.A.GoView(round, ev.attempt)
				go.kind = "arcade_go"
				S.notice(go)
			end
		end
	end
	function S.finish(round)
		local fin = rec.Of("mini_arcade_finish")
		T.check(#fin >= 1, "mini_arcade_finish gesendet")
		local last = fin[#fin]
		T.eq(last and last.payload.token, round.token, "Abrechnung mit Token")
		local res = S.A.Finish(round, g:Now())
		S.notice({
			kind = "arcade_result", token = round.token, game = round.key, score = res.score,
			credits = S.A.Reward(round.key, res.score), rating = S.A.Rating(res.score), detail = table.concat(res.lines, " · "),
			newBest = true, capped = false,
		})
		return res
	end
	function S.errors()
		local out = {}
		for _, e in ipairs(g:Errors()) do
			table.insert(out, tostring(e))
		end
		for _, w in ipairs(g:Warnings()) do
			if tostring(w):find("Spielhalle", 1, true) or tostring(w):find("ArcadeUI", 1, true) then
				table.insert(out, tostring(w))
			end
		end
		return out
	end
	return S
end

-- B-012: Bleibt arcade_result aus (mini_arcade_finish und die eine Wiederholung nach 4 s verworfen, z. B. weil das
-- Profil gerade „transacting“ ist), blieb die Spielhalle auf „Auswertung …“ stehen: keine weitere Nachfrage,
-- „Runde beenden“ sendet nichts, Automaten-Liste unsichtbar, Select verweigert.
return {
	{ "B-012 ArcadeUI: ohne Ergebnis wird weiter nachgefragt; ein spätes Ergebnis wird normal angezeigt", function(T, H)
		local S = uiSetup(T, H)
		local g = S.g
		local round = S.round("arcade_6", 31337, 7)
		S.at(round, 0.5)
		S.click("Beenden")
		T.eq(#S.rec.Of("mini_arcade_finish", S.mark), 1, "Abrechnung gesendet")
		-- Server verwirft die Abrechnung und die erste Wiederholung (6 s lang beschäftigt)
		g:Advance(6)
		T.eq(#S.rec.Of("mini_arcade_finish", S.mark), 2, "eine Wiederholung nach 4 s")
		g:Advance(6)
		local n = #S.rec.Of("mini_arcade_finish", S.mark)
		T.check(n >= 3, "nach 12 s weiter nachgefragt (gesendet: " .. n .. ")")
		T.check(n <= 4, "kein Spam: höchstens alle 4 s (gesendet: " .. n .. ")")
		for _, e in ipairs(S.rec.Of("mini_arcade_finish", S.mark)) do
			T.eq(e.payload.token, round.token, "immer dasselbe Token")
		end
		-- jetzt antwortet der Server: Ergebnis wie gewohnt
		S.notice({ kind = "arcade_result", token = round.token, game = "arcade_6", score = 300, credits = 7, rating = "Solide." })
		T.check(S.AUI.Current().result ~= nil, "Ergebnis übernommen")
		T.check(S.visible("Uebersicht"), "Ergebnis-Karte mit „Übersicht“")
		local sentNow = #S.rec.Of("mini_arcade_finish", S.mark)
		g:Advance(10)
		T.eq(#S.rec.Of("mini_arcade_finish", S.mark), sentNow, "nach dem Ergebnis keine Nachfrage mehr")
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },

	{ "B-012 ArcadeUI: bleibt das Ergebnis ganz aus, ist die Übersicht nach spätestens 15 s wieder erreichbar", function(T, H)
		local S = uiSetup(T, H)
		local g = S.g
		local round = S.round("arcade_6", 31337, 7)
		S.at(round, 0.5)
		S.click("Beenden")
		g:Advance(10)
		T.check(not S.visible("Automaten"), "bis 15 s: noch Auswertung")
		T.eq(g:InClient(S.pl, function()
			return S.AUI.Select("MOTOR-OHR")
		end), false, "während der Auswertung kein Automatenwechsel")
		g:Advance(5.5)
		T.check(S.visible("Automaten"), "nach 15 s: Automaten-Liste wieder sichtbar")
		T.check(S.visible("Automat_arcade_8"), "alle Automaten wählbar")
		T.eq(S.AUI.IsPlaying(), false, "keine laufende Runde mehr")
		T.eq(g:InClient(S.pl, function()
			return S.AUI.Select("MOTOR-OHR")
		end), true, "Station wählt wieder einen Automaten")
		T.check(S.visible("Anleitung"), "Anleitung")
		-- es wird weiter (begrenzt) nachgefragt; das späte Ergebnis reißt die Anzeige nicht um, meldet aber die Credits
		local before = #S.rec.Of("mini_arcade_finish", S.mark)
		g:Advance(5)
		T.check(#S.rec.Of("mini_arcade_finish", S.mark) > before, "im Hintergrund weiter nachgefragt")
		local toasts = #S.toasts
		S.notice({ kind = "arcade_result", token = round.token, game = "arcade_6", score = 300, credits = 7, rating = "Solide." })
		T.check(S.visible("Anleitung"), "Anzeige bleibt auf der Anleitung")
		T.check(#S.toasts == toasts + 1 and S.toasts[#S.toasts]:find("7 Cr", 1, true) ~= nil, "Hinweis mit Credits")
		local after = #S.rec.Of("mini_arcade_finish", S.mark)
		g:Advance(10)
		T.eq(#S.rec.Of("mini_arcade_finish", S.mark), after, "nach dem Ergebnis keine Nachfrage mehr")
		-- Wiederholung desselben Ergebnisses (replay): kein zweiter Hinweis
		S.notice({ kind = "arcade_result", token = round.token, game = "arcade_6", score = 300, credits = 7, rating = "Solide.", replay = true })
		T.eq(#S.toasts, toasts + 1, "Wiederholung ohne zweiten Hinweis")
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },

	{ "B-012 ArcadeUI: ohne jede Antwort endet die Nachfrage nach 30 s; eine neue Runde startet normal", function(T, H)
		local S = uiSetup(T, H)
		local g = S.g
		local round = S.round("arcade_6", 31337, 7)
		S.at(round, 0.5)
		S.click("Beenden")
		g:Advance(66)
		T.check(S.visible("Automaten"), "66 s später: Übersicht")
		local n = #S.rec.Of("mini_arcade_finish", S.mark)
		T.check(n >= 3 and n <= 17, "begrenzt nachgefragt (gesendet: " .. n .. ")")
		g:Advance(20)
		T.eq(#S.rec.Of("mini_arcade_finish", S.mark), n, "danach Ruhe")
		local round2 = S.round("arcade_6", 4711, 8)
		T.eq(S.AUI.Current().token, round2.token, "neue Runde läuft")
		T.eq(S.AUI.IsPlaying(), true, "spielt")
		T.check(not S.visible("Automaten"), "Spielansicht")
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },
}
