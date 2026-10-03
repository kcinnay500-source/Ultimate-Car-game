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

-- B-015: Der Server setzt die Frage beim Beantworten auf false (SideGameRules: qs.current = false). QuizUI.Render
-- blendete die vier Antwortknöpfe aus, sobald quiz.question fehlte – die grün/rot gefärbte Auflösung war nie zu sehen.
local function snap(question)
	return { quiz = { diagPoints = 0, reduction = 0, paidLeft = 5, question = question or false } }
end

local function question(token)
	return { token = token, text = "Frage " .. tostring(token) .. "?", answers = { "Antwort A", "Antwort B", "Antwort C", "Antwort D" } }
end

local function answers(page)
	local out = {}
	for _, x in ipairs(page:GetDescendants()) do
		if x:IsA("TextButton") and type(x.Text) == "string" and x.Text:find("Antwort ", 1, true) == 1 then
			table.insert(out, x)
		end
	end
	table.sort(out, function(a, b)
		return a.Text < b.Text
	end)
	return out
end

local function sameColor(a, b)
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end

return {
	{ "B-015 QuizUI: nach der Antwort bleiben die vier Knöpfe gesperrt und gefärbt sichtbar, bis eine neue Frage kommt", function(T, H)
		local g, p = startClient(H, { placeKind = "openworld" })
		local rec = recorder(T)
		local mod, page, MiniUI = build(g, p, "QuizUI", rec)
		local Theme = MiniUI.Theme
		render(g, p, mod, snap(question(11)))
		local btn = answers(page)
		T.eq(#btn, 4, "vier Antwortknöpfe")
		for i, b in ipairs(btn) do
			T.check(b.Visible and enabled(b), "Antwort " .. i .. " sichtbar und aktiv")
		end
		-- antworten (falsch: Knopf 2, richtig wäre 3)
		press(g, btn[2])
		local sent = rec.Last("mini_quiz_answer")
		T.check(sent ~= nil and sent.token == 11 and sent.choice == 2, "mini_quiz_answer {token, choice}")
		-- Server: Auswertung (Hinweis quiz) und Snapshot ohne Frage
		g:InClient(p, function()
			mod.OnResult({ correct = false, correctPos = 3, choice = 2, credits = 0 })
		end)
		render(g, p, mod, snap(false))
		for i, b in ipairs(btn) do
			T.check(b.Visible, "nach der Auswertung: Antwort " .. i .. " bleibt sichtbar")
			T.check(not enabled(b), "nach der Auswertung: Antwort " .. i .. " gesperrt")
		end
		T.check(sameColor(btn[3].BackgroundColor3, Theme.green), "richtige Antwort grün")
		T.check(sameColor(btn[2].BackgroundColor3, Theme.red), "gewählte falsche Antwort rot")
		T.check(withText(page, "Die richtige Antwort ist grün markiert") ~= nil, "Ergebniszeile")
		-- weitere Snapshots ohne Frage ändern nichts; Tippen sendet nichts
		render(g, p, mod, snap(false))
		g:Advance(2)
		render(g, p, mod, snap(false))
		T.check(btn[1].Visible and btn[4].Visible, "bleibt über weitere Snapshots sichtbar")
		T.check(sameColor(btn[3].BackgroundColor3, Theme.green), "Färbung bleibt")
		press(g, btn[1], { force = true })
		T.eq(rec.Count("mini_quiz_answer"), 1, "gesperrt: keine zweite Antwort")
		T.check(withText(page, "Neue Frage") ~= nil, "Knopf „Neue Frage“")
		-- neue Frage (neues Token): Knöpfe frisch, aktiv, ohne Färbung
		render(g, p, mod, snap(question(12)))
		for i, b in ipairs(btn) do
			T.check(b.Visible and enabled(b), "neue Frage: Antwort " .. i .. " aktiv")
			T.check(sameColor(b.BackgroundColor3, Theme.blue), "neue Frage: Antwort " .. i .. " wieder blau")
		end
		T.check(withText(page, "Frage 12?") ~= nil, "neuer Fragetext")
		press(g, btn[4])
		T.eq(rec.Count("mini_quiz_answer"), 2, "neue Frage beantwortbar")
		T.eq(rec.Last("mini_quiz_answer").token, 12, "mit dem neuen Token")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "B-015 QuizUI: Snapshot vor dem Hinweis (andere Reihenfolge) – Knöpfe bleiben stehen; unbeantwortet verschwundene Frage blendet aus", function(T, H)
		local g, p = startClient(H, { placeKind = "openworld" })
		local rec = recorder(T)
		local mod, page, MiniUI = build(g, p, "QuizUI", rec)
		local Theme = MiniUI.Theme
		render(g, p, mod, snap(question(21)))
		local btn = answers(page)
		press(g, btn[1])
		render(g, p, mod, snap(false)) -- Snapshot zuerst
		T.check(btn[1].Visible and btn[2].Visible and btn[3].Visible and btn[4].Visible, "Knöpfe bleiben bis zur Auswertung stehen")
		g:InClient(p, function()
			mod.OnResult({ correct = true, correctPos = 1, choice = 1, credits = 5 })
		end)
		T.check(btn[1].Visible and sameColor(btn[1].BackgroundColor3, Theme.green), "richtige Antwort grün und sichtbar")
		T.check(not enabled(btn[2]), "gesperrt")
		-- Frage ohne Antwort verschwunden (z. B. Sitzung neu): Knöpfe wie bisher ausgeblendet
		render(g, p, mod, snap(question(22)))
		T.check(btn[1].Visible and enabled(btn[1]), "neue Frage sichtbar")
		render(g, p, mod, snap(false))
		for i, b in ipairs(btn) do
			T.eq(b.Visible, false, "unbeantwortet verschwunden: Antwort " .. i .. " ausgeblendet")
		end
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },
}
