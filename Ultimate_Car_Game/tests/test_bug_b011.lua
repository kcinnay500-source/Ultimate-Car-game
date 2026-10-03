local NOW = 1760000000

---------------------------------------------------------------- Hilfen (wie test_lobby / test_prestige)
local FORBIDDEN = { amount = true, cost = true, credits = true, reward = true, money = true, cash = true, xp = true, level = true }

local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
			T.check(not FORBIDDEN[k], action .. ": Client sendet verbotenes Feld " .. tostring(k))
		end
		T.check(n <= 10, action .. ": höchstens 10 Felder")
		table.insert(r.sent, { action = action, payload = payload })
		return #r.sent
	end
	r.SendRaw = r.Send
	function r.Last(action)
		for i = #r.sent, 1, -1 do
			if r.sent[i].action == action then
				return r.sent[i].payload
			end
		end
		return nil
	end
	function r.Count(action)
		local n = 0
		for _, s in ipairs(r.sent) do
			if s.action == action then
				n += 1
			end
		end
		return n
	end
	return r
end

local function startClient(H, opts)
	opts = opts or {}
	opts.placeKind = opts.placeKind or "tycoon"
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1.5)
	return g, p
end

-- Baut die Seite des Bereichs in einer eigenen ScreenGui (338 px breit wie das Panel bei 390 px Bildschirmbreite)
local function build(g, p, modName, rec, ctxExtra)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini." .. modName)
	local toasts = {}
	local state = { tablet = false, blocked = false }
	local ctxOut
	local page = g:InClient(p, function()
		if not MiniUI.Gui then
			MiniUI.Build()
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "TycoonTest_" .. modName
		gui.ResetOnSpawn = false
		gui.Parent = p.PlayerGui
		local frame = MiniUI.Frame(gui, { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(0, 338, 0, 0) })
		MiniUI.List(frame, 12)
		local ctx = {
			UI = MiniUI, Remote = rec,
			Toast = function(text)
				table.insert(toasts, text)
			end,
			Close = function()
				MiniUI.Close()
			end,
			IsTabletOpen = function()
				return state.tablet
			end,
			IsBlocked = function()
				return state.blocked
			end,
		}
		for k, v in pairs(ctxExtra or {}) do
			ctx[k] = v
		end
		ctxOut = ctx
		if mod.Build then
			mod.Build(frame, ctx)
		end
		return frame
	end)
	return mod, page, MiniUI, toasts, state, ctxOut
end

local function render(g, p, mod, s)
	g:InClient(p, function()
		mod.Render(s)
	end)
end

local function find(root, pred)
	for _, x in ipairs(root:GetDescendants()) do
		if pred(x) then
			return x
		end
	end
	return nil
end

local function byName(root, name)
	return find(root, function(x)
		return x.Name == name
	end)
end

local function withText(root, text)
	return find(root, function(x)
		local t = x.Text
		return type(t) == "string" and t:find(text, 1, true) ~= nil
	end)
end

local function enabled(b)
	return b ~= nil and b:GetAttribute("disabled") ~= true
end

local function press(g, button, opts)
	g:Advance(0.35)
	local ok = g:Click(button, opts)
	g:Advance(0.05)
	return ok
end

-- Gefälschte Snapshots. Ohne Durchlauf / Stufe 1 frisch / Stufe 5 komplett / mit Handelsangeboten.
local function base(mode, extra)
	local s = {
		credits = 1000, level = 3, mode = mode or "tycoon", placeKind = "all", simulated = true,
		meta = { beginner = false, passive = false, single = false, tutorialDone = true, tutorialStep = 10 },
		party = false,
		tycoon = {
			run = false, rebirths = 0, boost = 0, slot = 1,
			runsDone = { werkstatt = 0, autohaus = 0, produktion = 0, schrottplatz = 0 },
			bonus = {
				werkstatt = { runs = 0, pct = 0, text = "Werkstatt-Vergütung" },
				autohaus = { runs = 0, pct = 0, text = "Händlerrabatt" },
				produktion = { runs = 0, pct = 0, text = "Tuning-Tempo" },
				schrottplatz = { runs = 0, pct = 0, text = "Schrott" },
			},
			offers = {},
		},
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

-- Durchlauf über die echten Regeln (TycoonRules.Summary), damit Ids/Kosten/Gründe stimmen
local function runSnapshot(g, typ, mutate, mode, extra)
	local TR = g:MiniShared("TycoonRules")
	local d = g:Rules().NewData(NOW)
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	TR.ApplyDefault(d.games)
	local run = TR.NewRun(d, typ, NOW)
	if mutate then
		mutate(run, d)
	end
	local s = base(mode, extra)
	local sum = TR.Summary(d)
	s.tycoon.run = sum.run
	s.tycoon.boost = sum.boost
	s.tycoon.bonus = sum.bonus
	s.tycoon.runsDone = sum.runsDone
	s.tycoon.rebirths = sum.rebirths
	return s, d
end

local function completeStage5(run, GC)
	local b = GC.Tycoon.Buildings[run.building]
	run.stage = 5
	for s = 1, 5 do
		for _, u in ipairs(b.Stages[s].Upgrades) do
			run.upgrades[u.id] = 1
		end
	end
	run.cash = 5000
	run.container = 120
	run.storage.bauteile = 12
	run.storage.reifen = 3
end

---------------------------------------------------------------- Fälle
-- B-011: Der Server verwirft tycoon_choose (transacting, Rate-Budget, „alle Grundstücke belegt“) nur per Toast –
-- es kommt weder ein Durchlauf im Snapshot noch ein tycoon/tycoon_stage-Hinweis. Die Karten dürfen dann nicht
-- bis zum Rejoin auf „Wird gebaut …“ gesperrt bleiben.
return {
	{ "B-011 TycoonUI: abgelehnte Gebäudewahl gibt die Karten nach wenigen Sekunden wieder frei, zweites Tippen sendet erneut", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page = build(g, p, "TycoonUI", rec)
		render(g, p, mod, base("tycoon"))
		press(g, byName(page, "Choose_produktion"))
		T.eq(rec.Count("tycoon_choose"), 1, "erste Wahl gesendet")
		T.check(withText(byName(page, "Choose_produktion"), "Wird gebaut") ~= nil, "Karte zeigt „Wird gebaut“")
		-- schneller Doppelklick und ein sofortiger Snapshot ohne Durchlauf: weiter gesperrt (kein Doppel-Senden)
		press(g, byName(page, "Choose_werkstatt"))
		render(g, p, mod, base("tycoon"))
		T.check(not enabled(byName(page, "Choose_werkstatt")), "direkt danach: Karten gesperrt")
		press(g, byName(page, "Choose_werkstatt"))
		T.eq(rec.Count("tycoon_choose"), 1, "kein Doppel-Senden direkt nach der Wahl")
		-- Server hat verworfen: kein Durchlauf, kein Hinweis. 18 s später OHNE neuen Snapshot
		g:Advance(18)
		T.check(withText(byName(page, "Choose_produktion"), "Wird gebaut") == nil, "nach 18 s kein „Wird gebaut“ mehr")
		for _, typ in ipairs({ "werkstatt", "autohaus", "produktion", "schrottplatz" }) do
			T.check(enabled(byName(page, "Choose_" .. typ)), "Karte wieder aktiv: " .. typ)
		end
		press(g, byName(page, "Choose_werkstatt"))
		T.eq(rec.Count("tycoon_choose"), 2, "zweites Tippen sendet erneut tycoon_choose")
		local sent = rec.Last("tycoon_choose")
		T.check(sent ~= nil and sent.building == "werkstatt", "zweite Wahl: werkstatt")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "B-011 TycoonUI: nach abgelehnter Wahl gibt der nächste Snapshot ohne Durchlauf die Karten frei; mit Durchlauf bleibt alles wie bisher", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page = build(g, p, "TycoonUI", rec)
		render(g, p, mod, base("tycoon"))
		press(g, byName(page, "Choose_autohaus"))
		T.eq(rec.Count("tycoon_choose"), 1, "Wahl gesendet")
		-- Seite war zu (kein Neuzeichnen durch den Timer nötig): der nächste Snapshot ohne Durchlauf reicht
		g:Advance(6)
		render(g, p, mod, base("tycoon"))
		T.check(enabled(byName(page, "Choose_autohaus")) and enabled(byName(page, "Choose_werkstatt")), "Snapshot ohne Durchlauf: Karten aktiv")
		T.check(withText(byName(page, "ChooseCard"), "Wird gebaut") == nil, "kein „Wird gebaut“")
		-- angenommene Wahl: Durchlauf im Snapshot -> Gebäudewahl weg; nach Abbruch sofort wieder wählbar
		press(g, byName(page, "Choose_autohaus"))
		T.eq(rec.Count("tycoon_choose"), 2, "erneut gesendet")
		render(g, p, mod, (runSnapshot(g, "autohaus")))
		T.eq(byName(page, "ChooseCard").Visible, false, "Durchlauf da: keine Gebäudewahl")
		render(g, p, mod, base("tycoon"))
		T.check(enabled(byName(page, "Choose_produktion")), "nach dem Durchlauf sofort wieder wählbar")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },
}
