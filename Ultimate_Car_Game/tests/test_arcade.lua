-- Spielhalle: ArcadeRules (rein), ArcadeService im echten Server (Mock, eigene Aktionen-Tabelle wie test_cars)
-- und ArcadeUI im Mock-Client. Geprüft: Bewertung aller 8 Automaten, Zeitfenster [now − 0,5; now + 0,06],
-- Reihenfolge, eine Auszahlung je Token (Wiederholung zahlt nichts), Tageslimit, ungültige/abgelaufene Tokens,
-- keine Lösungen im Rundenpaket. Der letzte Server-Fall prüft den echten Weg über Remotes.Command, sobald
-- MiniNet die Spielhallen-Aktionen kennt.
local NOW = 1760000000
local LAT = 0.05 -- simulierte Laufzeit Client -> Server

---------------------------------------------------------------- Hilfen
local function rules(H)
	local g = H.Garage({ noServer = true })
	return g:MiniShared("ArcadeRules"), g
end

-- Eingabe t (relativ zum Start) mit Wert v, Ankunft LAT später
local function send(A, round, t, v, lat)
	local at = round.startAt + t
	return A.Input(round, at, v, at + (lat or LAT))
end

local function finishAt(A, round, t)
	return A.Finish(round, round.startAt + t)
end

local function hasKey(v, key, depth)
	depth = depth or 0
	if type(v) ~= "table" or depth > 8 then
		return false
	end
	for k, x in pairs(v) do
		if k == key or hasKey(x, key, depth + 1) then
			return true
		end
	end
	return false
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

-- Kürzester Weg (Richtungsfolge) für eine Parkaufgabe
local function parkPath(A, p, task)
	local function id(x, y, h)
		return (y * p.w + x) * 4 + h
	end
	local prev = { [id(task.sx, task.sy, task.sh)] = false }
	local queue, head = { { task.sx, task.sy, task.sh } }, 1
	while queue[head] do
		local c = queue[head]
		head += 1
		if c[1] == task.tx and c[2] == task.ty and c[3] == task.th then
			local path, k = {}, id(c[1], c[2], c[3])
			while prev[k] do
				table.insert(path, 1, prev[k].d)
				k = prev[k].from
			end
			return path
		end
		for d = 1, 4 do
			local nx, ny, nh, blocked = A.ParkMove(p, task, c[1], c[2], c[3], d)
			local k = id(nx, ny, nh)
			if not blocked and prev[k] == nil then
				prev[k] = { from = id(c[1], c[2], c[3]), d = d }
				table.insert(queue, { nx, ny, nh })
			end
		end
	end
	return nil
end

-- Sicherer Fahrer: vor jeder Reihe in eine freie Spur (Pokal bevorzugt, Öl gemieden), Spurwechsel einzeln
local function raceDriver(A, round, opts)
	opts = opts or {}
	local p = round.p
	local lane = p.startLane
	local last = -1
	local log = {}
	for k, tk in ipairs(p.times) do
		local row = p.rows[k]
		local best, bestScore
		for l = 1, p.lanes do
			local o = string.sub(row, l, l)
			if o ~= "1" and (o ~= "3" or opts.oil) then
				local s = math.abs(l - lane) + (o == "2" and -3 or 0) + (o == "3" and -5 or 0)
				if not bestScore or s < bestScore then
					best, bestScore = l, s
				end
			end
		end
		local steps = math.abs(best - lane)
		local dir = best > lane and 1 or -1
		for s = 1, steps do
			local t = tk - 0.3 + (s - 1) * 0.12
			t = math.max(t, last + 0.12)
			lane += dir
			local ok, info = send(A, round, t, lane)
			table.insert(log, { t = t, lane = lane, ok = ok, info = info })
			last = t
		end
	end
	return log
end

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
	local g = H.Garage()
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

return {
	---------------------------------------------------------------- Katalog und Daten
	{ "Katalog: 8 Automaten wie in contract.py, Auflösung über Schlüssel und Namen", function(T, H)
		local A = rules(H)
		local expected = {
			arcade_1 = "BLITZ-REAKTION", arcade_2 = "BREMSWEG-PROFI", arcade_3 = "BOXENSTOPP", arcade_4 = "DREHMOMENT",
			arcade_5 = "MOTOR-OHR", arcade_6 = "EINPARK-PROFI", arcade_7 = "RENNSIMULATOR 1", arcade_8 = "RENNSIMULATOR 2",
		}
		T.eq(#A.Games, 8, "8 Automaten")
		for key, name in pairs(expected) do
			local def = A.GameByKey[key]
			T.check(def ~= nil, "Automat " .. key)
			T.eq(def and def.name, name, "Name " .. key)
			T.eq(A.Resolve(key), def, "Resolve(key) " .. key)
			T.eq(A.Resolve(name), def, "Resolve(Name) " .. name)
			T.check(def and A.Kinds[def.kind] ~= nil, "Spielart " .. key)
			T.check(def and type(def.howto) == "string" and #def.howto > 40, "Anleitung " .. key)
			T.check(def and def.reward > 0 and def.reward <= 60, "Belohnung klein " .. key)
		end
		T.eq(A.Resolve("boxenstopp"), A.GameByKey.arcade_3, "Name ohne Großschreibung")
		T.eq(A.Resolve("arcade_9"), nil, "unbekannt")
		T.eq(A.Resolve(5), nil, "keine Zahl")
	end },

	{ "Daten: Default/Load normalisiert, idempotent, unbekannte Automaten verworfen", function(T, H)
		local A = rules(H)
		T.check(H.DeepEqual(A.Load(nil), A.Default()), "nil -> Standard")
		T.check(H.DeepEqual(A.Load("x"), A.Default()), "kein Table -> Standard")
		local raw = {
			day = "2025-10-09", earned = 432.7, junk = 5,
			best = { arcade_1 = 812.4, arcade_2 = -5, arcade_9 = 100, arcade_3 = 0 / 0, arcade_4 = 5000, [1] = 3 },
		}
		local a = A.Load(raw)
		T.eq(a.day, "2025-10-09", "Tag")
		T.eq(a.earned, 432, "earned ganzzahlig")
		T.eq(a.best.arcade_1, 812, "Rekord ganzzahlig")
		T.eq(a.best.arcade_2, nil, "negativ verworfen")
		T.eq(a.best.arcade_9, nil, "unbekannter Automat verworfen")
		T.eq(a.best.arcade_3, nil, "NaN verworfen")
		T.eq(a.best.arcade_4, 1000, "über 1000 gedeckelt")
		T.eq(a.junk, nil, "unbekanntes Feld weg")
		T.check(H.DeepEqual(A.Load(a), a), "idempotent")
		T.eq(A.Load({ day = "gestern", earned = 50 }).day, "", "ungültiges Datum")
		T.eq(A.Load({ day = "gestern", earned = 50 }).earned, 0, "earned ohne Tag verworfen")
		T.eq(A.Load({ day = "2025-10-09", earned = 1 / 0 }).earned, 0, "unendlich verworfen")
		-- Data legt fehlendes games.arcade an
		local d = { games = {} }
		local got = A.Data(d)
		T.check(d.games.arcade == got and H.DeepEqual(got, A.Default()), "Data legt an")
		T.eq(A.Data(d), got, "Data liefert dasselbe")
		-- Snapshot-Feld
		got.day = A.DayKey(NOW)
		got.earned = 300
		got.best.arcade_2 = 640
		local view = A.SnapshotView(d, NOW)
		T.eq(view.earnedToday, 300, "earnedToday")
		T.eq(view.cap, A.DailyCap, "cap")
		T.eq(view.left, A.DailyCap - 300, "left")
		T.eq(view.best.arcade_2, 640, "best")
		T.eq(A.SnapshotView(d, NOW + 86400).earnedToday, 0, "neuer Tag: 0")
	end },

	{ "Seed: gleiche Parameter bei gleichem Seed, Rundenpaket ohne Seed und ohne Lösungen", function(T, H)
		local A = rules(H)
		for _, def in ipairs(A.Games) do
			local r1 = A.NewRound(def.key, 4242, NOW, 7)
			local r2 = A.NewRound(def.key, 4242, NOW + 50, 8)
			local r3 = A.NewRound(def.key, 99991, NOW, 9)
			T.check(r1 ~= nil, "Runde " .. def.key)
			T.check(H.DeepEqual(r1.p, r2.p), "deterministisch " .. def.key)
			T.check(not H.DeepEqual(r1.p, r3.p), "anderer Seed, andere Runde " .. def.key)
			T.eq(r1.startAt, NOW + A.Countdown, "Start nach Countdown " .. def.key)
			T.check(r1.duration >= 20 and r1.duration <= 60, "20–60 s: " .. def.key .. " " .. tostring(r1.duration))
			local view = A.View(r1)
			T.check(sendable(view), "Rundenpaket sendbar " .. def.key)
			T.eq(view.seed, nil, "kein Seed im Paket " .. def.key)
			T.eq(view.kind, nil, "kein Feld kind (mini_notice) " .. def.key)
			T.eq(view.gameKind, def.kind, "gameKind " .. def.key)
			T.check(not hasKey(view, "answers") and not hasKey(view, "secret") and not hasKey(view, "kinds"), "keine Lösungen " .. def.key)
		end
		T.eq(A.NewRound("arcade_x", 1, NOW, 1), nil, "unbekannter Automat")
		T.eq(A.NewRound("arcade_1", 0 / 0, NOW, 1), nil, "NaN-Seed")
		-- MOTOR-OHR: die Lösung steht nur im Geheimteil
		local r = A.NewRound("arcade_5", 777, NOW, 1)
		T.eq(#r.p.questions, A.Engine.questions, "6 Fragen")
		for q, question in ipairs(r.p.questions) do
			T.eq(#question.waves, 4, "4 Klangbilder")
			for _, w in ipairs(question.waves) do
				T.check(#w == A.Engine.samples and string.match(w, "^%d+$") ~= nil, "Klangbild aus 64 Ziffern")
			end
			local ans = r.secret.answers[q]
			T.check(ans >= 1 and ans <= 4, "Antwort 1..4")
			local target = r.secret.kinds[q][ans]
			T.check(string.find(question.text, A.Engine.names[target] == "Gesunder Motor" and "Gesunder Motor" or A.Engine.names[target], 1, true) ~= nil, "Text beschreibt die Lösung")
		end
	end },

	{ "Klangbilder: Fehler sind sichtbar verschieden", function(T, H)
		local A = rules(H)
		local function peaks(w)
			local n = 0
			for i = 1, #w do
				if tonumber(string.sub(w, i, i)) >= 8 then
					n += 1
				end
			end
			return n
		end
		local r = A.Rng(5)
		local healthy = A.EngineWave("healthy", r)
		local misfire = A.EngineWave("misfire", A.Rng(5))
		T.check(peaks(misfire) < peaks(healthy), "Zündaussetzer: weniger Takte")
		T.check(string.find(A.EngineWave("knock", A.Rng(6)), "9", 1, true) ~= nil, "Klopfen: spitze Ausschläge")
		T.check(string.find(healthy, "9", 1, true) == nil, "gesund: keine Spitzen")
		T.check(string.find(A.EngineWave("belt", A.Rng(7)), "3131", 1, true) ~= nil or string.find(A.EngineWave("belt", A.Rng(7)), "1313", 1, true) ~= nil, "Keilriemen: Zittern")
		T.check(string.find(A.EngineWave("bearing", A.Rng(8)), "1", 1, true) == nil, "Lager: Grundlinie brummt")
	end },

	---------------------------------------------------------------- Zeitfenster und Reihenfolge
	{ "Zeitfenster [now − 0,5; now + 0,06], Reihenfolge, ungültige Werte", function(T, H)
		local A = rules(H)
		T.eq(A.AcceptTime(100, 100.5), true, "genau 0,5 s alt")
		T.eq(A.AcceptTime(100, 100.51), false, "0,51 s alt")
		T.eq(A.AcceptTime(100.06, 100), true, "genau 0,06 s voraus")
		T.eq(A.AcceptTime(100.07, 100), false, "0,07 s voraus")
		T.eq(A.AcceptTime(0 / 0, 100), false, "NaN")
		local round = A.NewRound("arcade_1", 11, NOW, 1)
		local g1 = round.p.attempts[1].g
		-- zu spät angekommen: at liegt 0,6 s vor der Ankunft
		local ok, info = send(A, round, g1 + 0.25, 1, 0.6)
		T.eq(ok, false, "zu alt abgelehnt")
		T.eq(info and info.reject, "late", "Grund late")
		T.eq(round.st.res[1], nil, "nicht gewertet")
		-- Zeitstempel aus der Zukunft
		ok, info = send(A, round, g1 + 0.25, 1, -0.2)
		T.eq(info and info.reject, "early", "Grund early")
		-- gültig
		ok, info = send(A, round, g1 + 0.25, 1)
		T.eq(ok, true, "gültig")
		T.eq(info.attempt, 1, "Start 1")
		-- Reihenfolge: älterer Zeitstempel nach einem neueren
		local g2 = round.p.attempts[2].g
		ok, info = send(A, round, g1 + 0.2, 1)
		T.eq(info and info.reject, "order", "rückwärts abgelehnt")
		ok, info = send(A, round, g2 + 0.25, 1.5)
		T.eq(info and info.reject, "invalid", "Kommazahl abgelehnt")
		T.eq(round.rejected, 4, "4 Ablehnungen gezählt")
		local fresh = A.NewRound("arcade_1", 11, NOW, 2)
		ok, info = send(A, fresh, -1, 1)
		T.eq(ok, false, "vor dem Start ignoriert")
		T.eq(info, nil, "still")
		T.eq(fresh.inputs, 0, "nicht gezählt")
		-- geschlossene Runde nimmt nichts mehr an
		A.Finish(round, round.startAt + 5)
		T.eq((send(A, round, g2 + 0.25, 1)), false, "geschlossen")
	end },

	---------------------------------------------------------------- Bewertung je Automat
	{ "BLITZ-REAKTION: Reaktionszeit, Frühstart, doppelt, verpasst", function(T, H)
		local A = rules(H)
		local round = A.NewRound("arcade_1", 321, NOW, 1)
		local at = round.p.attempts
		for i = 1, 5 do
			T.check(at[i].g - at[i].l >= 2.5 and at[i].g - at[i].l <= 4.5, "Pause nach allen Lampen " .. i)
			if i > 1 then
				T.check(at[i].l > at[i - 1].g + round.p.window, "Starts überlappen nicht " .. i)
			end
		end
		for i = 1, 5 do
			send(A, round, at[i].g + 0.18, 1)
		end
		T.eq(finishAt(A, round, round.duration).score, 1000, "5 × perfekt = 1000")

		round = A.NewRound("arcade_1", 321, NOW, 2)
		local _, info = send(A, round, at[1].g - 0.3, 1)
		T.eq(info.early, true, "vor dem Erlöschen: Frühstart")
		T.eq((send(A, round, at[1].g + 0.2, 1)), false, "zweiter Druck im selben Start ignoriert")
		_, info = send(A, round, at[2].g + 0.05, 1)
		T.eq(info.early, true, "schneller als 0,1 s: Frühstart")
		_, info = send(A, round, at[3].g + 0.4, 1)
		T.eq(info.points, 127, "0,4 s -> 127 Punkte")
		T.eq(A.ReactionPoints(0.75), 0, "0,75 s -> 0")
		T.eq(A.ReactionPoints(0.2), 200, "0,2 s -> 200")
		_, info = send(A, round, at[4].g + 1.1, 1)
		T.eq(info.points, 0, "sehr langsam -> 0")
		local res = finishAt(A, round, round.duration)
		T.eq(res.score, 127, "Summe")
		T.eq(res.stats.early, 2, "2 Frühstarts")
		T.eq(res.stats.missed, 1, "1 verpasst")
		-- Abbruch mitten in der Runde: spätere Starts zählen nicht als verpasst
		round = A.NewRound("arcade_1", 321, NOW, 3)
		send(A, round, at[1].g + 0.2, 1)
		res = finishAt(A, round, at[2].l + 0.1)
		T.eq(res.score, 200, "nur Start 1")
		T.eq(res.stats.missed, 0, "nichts verpasst")
	end },

	{ "BREMSWEG-PROFI: Haltepunkt an der Linie, zu früh, darüber, nicht gebremst", function(T, H)
		local A = rules(H)
		local round = A.NewRound("arcade_2", 55, NOW, 1)
		local runs = round.p.runs
		T.eq(#runs, 4, "4 Anfahrten")
		local function ideal(run)
			local v = run.kmh / 3.6
			return run.at + (run.line - v * v / (2 * run.a)) / v
		end
		for i, run in ipairs(runs) do
			T.check(run.kmh >= 40 and run.kmh <= 130, "Tempo " .. i)
			T.check(ideal(run) - run.at >= 1.9, "Anlauf " .. i)
			T.near(A.BrakeError(run, ideal(run) - run.at), 0, 1e-6, "Idealpunkt " .. i)
			T.near(A.BrakePosition(run, ideal(run) - run.at, ideal(run) - run.at + 20), run.line, 1e-6, "Auto steht an der Linie " .. i)
			send(A, round, ideal(run), 1)
		end
		T.eq(finishAt(A, round, round.duration).score, 1000, "4 × perfekt")

		round = A.NewRound("arcade_2", 55, NOW, 2)
		local _, info = send(A, round, ideal(runs[1]) - 0.3, 1)
		T.check(info.err < 0, "zu früh: vor der Linie")
		T.eq(info.points, 142, "0,3 s zu früh -> 142")
		_, info = send(A, round, ideal(runs[2]) + 0.1, 1)
		T.check(info.err > 0, "zu spät: über der Linie")
		T.eq(info.points, 100, "0,1 s zu spät -> 100 (halbe Wertung)")
		_, info = send(A, round, ideal(runs[3]) + 0.5, 1)
		T.eq(info.points, 0, "weit drüber -> 0")
		T.eq((send(A, round, ideal(runs[3]) + 0.6, 1)), false, "zweite Bremsung ignoriert")
		local res = finishAt(A, round, round.duration)
		T.eq(res.score, 242, "Summe")
		T.eq(res.stats.over, 2, "2 × über die Linie")
		T.eq(res.stats.missed, 1, "1 × nicht gebremst")
	end },

	{ "BOXENSTOPP: über Kreuz, Richtung frei ab Rad 3, Strafsekunden, Radwechsel, Zeit", function(T, H)
		local A = rules(H)
		local round = A.NewRound("arcade_3", 808, NOW, 1)
		local wheels = round.p.wheels
		T.eq(#wheels, 4, "4 Räder")
		T.eq(wheels[1].numbered and wheels[2].numbered, true, "Rad 1–2 nummeriert")
		T.eq(wheels[3].numbered or wheels[4].numbered, false, "Rad 3–4 ohne Nummern")
		-- Kreuzmuster trifft jede Mutter genau einmal
		local seen = {}
		for k = 0, 4 do
			seen[A.NutAt(3, k, 1)] = true
		end
		T.eq(#seen, 5, "alle 5 Muttern")
		local t = 0.3
		local function tap(pos, dt)
			t += dt or 0.3
			return send(A, round, t, pos)
		end
		-- Rad 1: vorgegebene Reihenfolge
		for k = 0, 4 do
			local ok, info = tap(A.NutAt(wheels[1].start, k, wheels[1].dir))
			T.eq(ok and info.ok, true, "Rad 1 Mutter " .. (k + 1))
		end
		-- während des Radwechsels ignoriert (kein Fehler)
		local ok = tap(A.NutAt(wheels[2].start, 0, wheels[2].dir), 0.1)
		T.eq(ok, false, "Radwechsel läuft")
		T.eq(round.st.mistakes, 0, "kein Fehler")
		t += 0.6
		-- Rad 2 mit einem Fehler (Nachbarmutter statt über Kreuz)
		tap(A.NutAt(wheels[2].start, 0, wheels[2].dir))
		local _, info = tap(A.NutAt(wheels[2].start, 0, wheels[2].dir) % 5 + 1)
		T.eq(info.ok, false, "Nachbarmutter ist falsch")
		T.eq(info.mistakes, 1, "1 Fehler")
		for k = 1, 4 do
			tap(A.NutAt(wheels[2].start, k, wheels[2].dir))
		end
		t += 0.6
		-- zu schnell hintereinander: ignoriert
		tap(wheels[3].start)
		T.eq((tap(A.NutAt(wheels[3].start, 1, 1), 0.03)), false, "unter 0,06 s ignoriert")
		-- Rad 3 gegen den Uhrzeigersinn, Rad 4 im Uhrzeigersinn: beide Richtungen gelten
		for k = 1, 4 do
			local ok3, i3 = tap(A.NutAt(wheels[3].start, k, -1))
			T.eq(ok3 and i3.ok, true, "Rad 3 links herum " .. k)
		end
		t += 0.6
		for k = 0, 4 do
			local _, i4 = tap(A.NutAt(wheels[4].start, k, 1))
			T.eq(i4.ok, true, "Rad 4 rechts herum " .. k)
			if k == 4 then
				T.eq(i4.finished, true, "fertig")
			end
		end
		local res = finishAt(A, round, round.duration)
		T.near(res.stats.time, t, 1e-3, "Zeit = letzte Mutter")
		T.eq(res.stats.mistakes, 1, "1 Fehler")
		T.eq(res.score, A.PitstopScore(t, 1, 20), "Punkte aus Zeit + Strafsekunde")
		T.check(res.score > 400, "fertig > 400")
		T.eq(A.PitstopScore(6.5, 0, 20), 1000, "Idealzeit = 1000")
		T.eq(A.PitstopScore(nil, 2, 12), 220, "nicht fertig: 20 je Mutter − 10 je Fehler")
		T.check(A.PitstopScore(27.9, 0, 20) > A.PitstopScore(nil, 0, 19), "fertig schlägt unfertig")
	end },

	{ "DREHMOMENT: Sollbereich halten, Überdrehen, untätig = 0, Client-Rechnung gleich Server", function(T, H)
		local A = rules(H)
		local round = A.NewRound("arcade_4", 2024, NOW, 1)
		local p = round.p
		-- Regler: unter der Mitte drücken, darüber loslassen (alle 0,05 s)
		local events, hold = {}, false
		local t = 0
		while t < A.Torque.duration - 0.05 do
			local tau = A.TorqueAt(p, events, t)
			local center = A.TorqueBand(p, t + 0.1)
			local want = tau < center
			if want ~= hold then
				hold = want
				local ok = send(A, round, t, hold and 1 or 0)
				T.check(ok, "Wechsel angenommen")
				table.insert(events, { t = t, v = hold and 1 or 0 })
			end
			t += 0.05
		end
		local res = finishAt(A, round, round.duration)
		T.check(res.score >= 850, "gut gehalten: " .. res.score)
		T.eq(res.stats.over, 0, "nie überdreht")
		T.eq(#round.st.events, #events, "Server-Wechsel = Client-Wechsel")
		for i, e in ipairs(events) do
			T.near(round.st.events[i].t, e.t, 1e-6, "Wechselzeit " .. i)
			T.eq(round.st.events[i].v, e.v, "Wechsel " .. i)
		end
		-- doppelte Meldung ändert nichts
		local r2 = A.NewRound("arcade_4", 2024, NOW, 2)
		send(A, r2, 1, 1)
		T.eq((send(A, r2, 1.2, 1)), true, "doppelt: angenommen, aber ohne Wirkung")
		T.eq(#r2.st.events, 1, "ein Wechsel")
		T.eq((send(A, r2, 1.3, 2)), false, "Wert 2 ungültig")
		-- dauerhaft gedrückt: überdreht, 0 Punkte
		local r3 = A.NewRound("arcade_4", 2024, NOW, 3)
		send(A, r3, 0, 1)
		local res3 = finishAt(A, r3, r3.duration)
		T.check(res3.stats.over > 15, "überdreht")
		T.eq(res3.score, 0, "überdreht = 0")
		-- untätig
		local r4 = A.NewRound("arcade_4", 2024, NOW, 4)
		T.eq(finishAt(A, r4, r4.duration).score, 0, "untätig = 0")
		-- Band
		local c, half = A.TorqueBand(p, 0)
		T.eq(c, A.Torque.first, "Start-Mitte")
		T.eq(half, 9, "anfangs breit")
		local _, half2 = A.TorqueBand(p, 20)
		T.eq(half2, 6, "am Ende eng")
		T.eq((A.TorqueAt(p, { { t = 0, v = 1 } }, 1)), 40, "40 je Sekunde")
		T.eq((A.TorqueAt(p, { { t = 0, v = 1 }, { t = 1, v = 0 } }, 2)), 10, "30 je Sekunde zurück")
		T.eq((A.TorqueAt(p, { { t = 0, v = 1 } }, 10)), 100, "gedeckelt")
	end },

	{ "MOTOR-OHR: richtig/falsch, Tempo, Zeitablauf, Antwort erst nach der Wahl", function(T, H)
		local A = rules(H)
		local round = A.NewRound("arcade_5", 9090, NOW, 1)
		local ans = round.secret.answers
		local qAt = 0
		for q = 1, 6 do
			local ok, info = send(A, round, qAt + 0.5, ans[q])
			T.eq(ok and info.correct, true, "Frage " .. q .. " richtig")
			T.eq(info.answer, ans[q], "Antwort im Schritt")
			T.eq(info.q, q, "Fragennummer")
			qAt = info.nextAt
			if q == 6 then
				T.eq(info.done, true, "fertig")
			end
		end
		local res = finishAt(A, round, qAt)
		T.eq(res.score, 1000, "6 × schnell und richtig = 1000")
		T.eq(res.stats.correct, 6, "6 richtig")

		round = A.NewRound("arcade_5", 9090, NOW, 2)
		local wrong = ans[1] % 4 + 1
		local _, info = send(A, round, 0.5, wrong)
		T.eq(info.correct, false, "falsch")
		T.eq(info.points, 0, "0 Punkte")
		T.eq(info.answer, ans[1], "richtige Antwort wird gezeigt")
		T.eq((send(A, round, 0.6, ans[1])), false, "Pause nach der Antwort: ignoriert")
		qAt = info.nextAt
		-- langsam, aber richtig
		_, info = send(A, round, qAt + 4, ans[2])
		T.eq(info.correct, true, "richtig")
		T.eq(info.points, math.floor(A.EnginePoints(4) + 0.5), "Tempo-Anteil")
		T.check(A.EnginePoints(4) < A.EnginePoints(0.5), "schneller = mehr")
		qAt = info.nextAt
		-- Frage 3 läuft ab: Client meldet "Zeit abgelaufen" (Wert 0)
		T.eq((send(A, round, qAt + 3, 0)), false, "Wert 0 vor Ablauf ignoriert")
		_, info = send(A, round, qAt + round.p.limit + 0.01, 0)
		T.eq(info.timeout, true, "Zeitablauf")
		T.eq(info.q, 3, "Frage 3")
		T.eq(info.answer, ans[3], "Lösung nach Ablauf")
		qAt = info.nextAt
		-- Frage 4 und 5 laufen ohne Meldung ab, Antwort auf Frage 6
		local q6 = qAt + 2 * (round.p.limit + round.p.pause)
		_, info = send(A, round, q6 + 1, ans[6])
		T.eq(info.q, 6, "direkt Frage 6")
		T.eq(info.correct, true, "richtig")
		local res2 = finishAt(A, round, q6 + 5)
		T.eq(res2.stats.correct, 2, "2 richtig")
		T.eq(res2.score, math.floor(A.EnginePoints(4) + A.EnginePoints(1) + 1e-6), "Summe")
	end },

	{ "EINPARK-PROFI: lösbar, bestmögliche Züge, Rückwärts-Aufgabe, Blechschaden", function(T, H)
		local A = rules(H)
		for seed = 1, 40 do
			local round = A.NewRound("arcade_6", seed * 7919, NOW, seed)
			for i, task in ipairs(round.p.tasks) do
				local path = parkPath(A, round.p, task)
				T.check(path ~= nil and #path == task.par and task.par >= 3, "Seed " .. seed .. " Aufgabe " .. i .. " lösbar")
			end
			T.eq(round.p.tasks[1].mode, "forward", "Aufgabe 1 vorwärts")
			T.eq(round.p.tasks[2].mode, "reverse", "Aufgabe 2 rückwärts")
		end
		local round = A.NewRound("arcade_6", 31337, NOW, 1)
		local p = round.p
		local t = 0
		for i, task in ipairs(p.tasks) do
			local path = parkPath(A, p, task)
			local info
			for _, d in ipairs(path) do
				t += 0.3
				local ok
				ok, info = send(A, round, t, d)
				T.check(ok and not info.bump, "Zug angenommen")
			end
			T.eq(info.parked, true, "Aufgabe " .. i .. " eingeparkt")
			T.eq(info.points, 333, "Idealweg = volle Punkte")
			if i == 2 then
				-- rückwärts: Auto schaut aus der Lücke heraus
				T.eq(info.h, task.ty == 0 and 3 or 1, "Rückwärts eingeparkt")
			end
			t = info.nextAt
		end
		local res = finishAt(A, round, t + 1)
		T.eq(res.score, 1000, "3 × ideal = 1000")
		-- Blechschaden: gegen den Rand fahren
		round = A.NewRound("arcade_6", 31337, NOW, 2)
		local task = round.p.tasks[1]
		local outward = task.sx == 0 and 4 or 2
		local _, info = send(A, round, 0.3, outward)
		T.eq(info.bump, true, "Rand = Blechschaden")
		T.eq(info.x, task.sx, "bleibt stehen")
		T.eq((send(A, round, 0.33, outward)), false, "unter 0,08 s ignoriert")
		-- Züge: vorwärts, rückwärts, einlenken
		local x, y, h = A.ParkMove(round.p, { grid = string.rep(".", 48) }, 3, 2, 2, 4)
		T.eq(x, 2, "rückwärts nach links")
		T.eq(h, 2, "Ausrichtung bleibt beim Rückwärtsfahren")
		x, y, h = A.ParkMove(round.p, { grid = string.rep(".", 48) }, 3, 2, 2, 1)
		T.eq(y, 1, "einlenken nach oben")
		T.eq(h, 1, "Ausrichtung folgt")
		local _, _, _, blocked = A.ParkMove(round.p, { grid = string.rep(".", 48) }, 3, 0, 1, 2)
		T.eq(blocked, true, "Buchten seitlich getrennt")
		local res2 = finishAt(A, round, 5)
		T.eq(res2.score, 0, "nichts eingeparkt")
		T.eq(res2.stats.bumps, 1, "1 Blechschaden")
		T.check(A.ParkTaskPoints(task, task.par + 4, 2, 20) < A.ParkTaskPoints(task, task.par, 0, 1), "Umwege und Schäden kosten")
	end },

	{ "RENNSIMULATOR: sicherer Fahrer, untätig, Spurspringen, zu schnell, Ölspur", function(T, H)
		local A = rules(H)
		for _, key in ipairs({ "arcade_7", "arcade_8" }) do
			local round = A.NewRound(key, 4711, NOW, 1)
			local p = round.p
			T.check(#p.times >= 40, key .. ": genug Reihen")
			for k, row in ipairs(p.rows) do
				T.eq(#row, p.lanes, "Reihenbreite")
				local free = 0
				for l = 1, p.lanes do
					local o = string.sub(row, l, l)
					if o == "0" or o == "2" then
						free += 1
					end
				end
				T.check(free >= 1, key .. " Reihe " .. k .. " hat eine freie Spur")
				if k > 1 then
					T.check(p.times[k] - p.times[k - 1] >= 0.44, "Abstand")
				end
			end
			local log = raceDriver(A, round)
			for _, e in ipairs(log) do
				T.check(e.ok, key .. ": Spurwechsel angenommen bei " .. e.t)
			end
			local res = finishAt(A, round, round.duration)
			T.eq(res.stats.crashes, 0, key .. ": unfallfrei")
			T.eq(res.stats.passed, #p.times, key .. ": alle Reihen")
			T.check(res.score >= 900, key .. ": Punkte " .. res.score)
			-- untätig
			local idle = A.NewRound(key, 4711, NOW, 2)
			local r2 = finishAt(A, idle, idle.duration)
			T.eq(r2.stats.dead, true, key .. ": untätig -> Totalschaden")
			T.check(r2.score < 300, key .. ": untätig wenig Punkte " .. r2.score)
		end
		local round = A.NewRound("arcade_8", 99, NOW, 4)
		local _, info = send(A, round, 0.2, 4)
		T.eq(info and info.reject, "lane", "zwei Spuren auf einmal abgelehnt")
		T.eq(info.lane, 2, "Server-Spur zum Abgleich")
		T.eq((send(A, round, 0.3, 3)), true, "eine Spur")
		_, info = send(A, round, 0.35, 4)
		T.eq(info and info.reject, "fast", "zweiter Wechsel nach 0,05 s abgelehnt")
		T.eq((send(A, round, 0.45, 4)), true, "nach 0,15 s erlaubt")
		T.eq((send(A, round, 0.9, 4)), true, "Meldung der gleichen Spur (Takt) angenommen")
		-- Ölspur: hinfahren, dann ist Lenken kurz gesperrt
		local oilRound, oilRow, oilLane
		for seed = 1, 200 do
			local r = A.NewRound("arcade_8", seed, NOW, 10)
			for k, row in ipairs(r.p.rows) do
				local l = string.find(row, "3", 1, true)
				if l and k > 1 then
					oilRound, oilRow, oilLane = r, k, l
					break
				end
			end
			if oilRound then
				break
			end
		end
		T.check(oilRound ~= nil, "Ölspur kommt vor")
		local p = oilRound.p
		local tk = p.times[oilRow]
		-- Autopilot bis kurz vor der Ölreihe, dann auf die Ölspur
		local lane, last = p.startLane, -1
		local function go(target, t0)
			while lane ~= target do
				t0 = math.max(t0, last + 0.12)
				lane += target > lane and 1 or -1
				send(A, oilRound, t0, lane)
				last = t0
				t0 += 0.12
			end
		end
		go(oilLane, tk - 0.4)
		T.eq(oilRound.st.lane, oilLane, "auf der Ölspur")
		local nextLane = oilLane > 1 and oilLane - 1 or 2
		_, info = send(A, oilRound, tk + 0.2, nextLane)
		T.eq(info and info.reject, "slide", "rutscht: Lenken gesperrt")
		T.eq(oilRound.st.slides, 1, "Ölspur gezählt")
		T.eq((send(A, oilRound, tk + p.slide + 0.01, nextLane)), true, "danach wieder lenkbar")
		-- Kollisionszeitpunkt: Wechsel genau zur Reihe zählt schon
		local st = A.RaceNew(p)
		st.lane = 1
		A.RaceAdvance(p, st, p.times[1], false)
		T.eq(st.row, 1, "Reihe bei t noch offen (exklusiv)")
		A.RaceAdvance(p, st, p.times[1], true)
		T.eq(st.row, 2, "inklusiv ausgewertet")
	end },

	---------------------------------------------------------------- Belohnung und Tageslimit
	{ "Belohnung nur aus Punkten, Tageslimit, Tageswechsel, Rekord", function(T, H)
		local A = rules(H)
		for _, def in ipairs(A.Games) do
			T.eq(A.Reward(def.key, 1000), def.reward, "1000 Punkte = volle Belohnung " .. def.key)
			T.eq(A.Reward(def.key, 99), 0, "unter 100 nichts " .. def.key)
			local prev = -1
			for s = 100, 1000, 50 do
				local r = A.Reward(def.key, s)
				T.check(r >= prev, "monoton " .. def.key)
				prev = r
			end
		end
		T.eq(A.Reward("arcade_1", 1e9), A.GameByKey.arcade_1.reward, "gedeckelt")
		T.eq(A.Reward("arcade_x", 1000), 0, "unbekannt")
		T.eq(A.Reward("arcade_1", 0 / 0), 0, "NaN")
		T.eq(A.Xp(1000), A.MaxXp, "XP bei 1000")
		T.eq(A.Xp(50), 0, "keine XP unter 100")
		-- Tageslimit
		local a = A.Default()
		local total, capped = 0, false
		for i = 1, 100 do
			local pay = A.Payout(a, "arcade_8", 1000, NOW + i)
			total += pay.credits
			if pay.capped then
				capped = true
				T.eq(pay.capLeft, 0, "danach nichts mehr")
				T.eq(pay.credits, A.DailyCap - (total - pay.credits), "Rest bis zum Limit")
				local after = A.Payout(a, "arcade_8", 1000, NOW + i + 1)
				T.eq(after.credits, 0, "Limit erreicht: 0 Cr")
				T.eq(after.xp, 0, "Limit erreicht: keine XP")
				T.eq(after.want, A.GameByKey.arcade_8.reward, "gewollt bleibt sichtbar")
				break
			end
		end
		T.eq(capped, true, "Limit greift")
		T.eq(total, A.DailyCap, "genau das Tageslimit")
		T.eq(a.earned, A.DailyCap, "earned")
		T.eq(A.CapLeft(a, NOW + 200), 0, "nichts übrig")
		-- neuer UTC-Tag
		local tomorrow = NOW + 86400
		T.eq(A.CapLeft(a, tomorrow), A.DailyCap, "neuer Tag: volles Limit")
		local pay = A.Payout(a, "arcade_8", 1000, tomorrow)
		T.eq(pay.credits, A.GameByKey.arcade_8.reward, "neuer Tag zahlt")
		T.eq(a.earned, A.GameByKey.arcade_8.reward, "Zähler neu")
		-- Rekord
		local b = A.Default()
		T.eq(A.Payout(b, "arcade_2", 600, NOW).newBest, true, "erster Rekord")
		T.eq(A.Payout(b, "arcade_2", 500, NOW).newBest, false, "schlechter: kein Rekord")
		T.eq(b.best.arcade_2, 600, "Rekord bleibt")
		T.eq(A.Payout(b, "arcade_2", 0, NOW).newBest, false, "0 Punkte: kein Rekord")
	end },

	---------------------------------------------------------------- Server (ArcadeService im Mock)
	{ "Dienst: Start, Eingaben, Abrechnung, Wiederholung, ungültige Tokens, Limit, Ablauf", function(T, H)
		local g = H.Garage()
		local AS = g:MiniServer("ArcadeService")
		local A = g:MiniShared("ArcadeRules")
		local log = { notices = {}, toasts = {} }
		local handlers = {}
		local fakeApi = {
			now = function()
				return g.env.workspace:GetServerTimeNow()
			end,
			toast = function(ms, text)
				table.insert(log.toasts, { player = ms.player, text = text })
			end,
			notice = function(ms, kind, data)
				data = type(data) == "table" and data or {}
				data.kind = kind
				table.insert(log.notices, { player = ms.player, kind = kind, data = data })
			end,
			dirty = function(ms)
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
		AS.Register({
			Register = function(name, fn)
				T.check(handlers[name] == nil, "einmal registriert: " .. name)
				handlers[name] = fn
			end,
		}, fakeApi)
		T.check(handlers.mini_arcade_start and handlers.mini_arcade_input and handlers.mini_arcade_finish, "3 Aktionen")
		local pl = g:Join(701, { name = "Ada" })
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		AS.OnJoin(ms, d, g:Now())
		local function act(name, data)
			g:Activate()
			handlers[name](ms, data or {}, d, g:Now())
		end
		local function last(kind)
			for i = #log.notices, 1, -1 do
				if log.notices[i].kind == kind then
					return log.notices[i].data
				end
			end
			return nil
		end
		local function count(kind)
			local n = 0
			for _, e in ipairs(log.notices) do
				if e.kind == kind then
					n += 1
				end
			end
			return n
		end
		local function toasted(pattern)
			for _, t in ipairs(log.toasts) do
				if string.find(t.text, pattern, 1, true) then
					return true
				end
			end
			return false
		end
		-- Eingabe wie der Client: at = Serverzeit jetzt, kommt LAT später an
		local function input(token, value)
			local at = g:Now()
			g:Advance(LAT)
			act("mini_arcade_input", { token = token, at = at, value = value, rid = math.random(1, 1e9) })
		end
		T.check(type(d.games.arcade) == "table", "games.arcade angelegt")

		-- Unbekannter Automat
		act("mini_arcade_start", { game = "flipper" })
		T.check(toasted("gibt es nicht"), "unbekannter Automat")
		T.eq(count("arcade_round"), 0, "keine Runde")

		-- Runde BLITZ-REAKTION
		act("mini_arcade_start", { game = "BLITZ-REAKTION" })
		local view = last("arcade_round")
		T.check(view ~= nil, "Rundenpaket")
		T.eq(view.game, "arcade_1", "Schlüssel aus dem Namen")
		T.eq(view.gameKind, "reaction", "Spielart")
		T.eq(view.kind, "arcade_round", "Hinweisart")
		T.eq(view.seed, nil, "kein Seed")
		T.eq(view.capLeft, A.DailyCap, "Limit")
		T.near(view.startAt, g:Now() + A.Countdown, 1e-6, "Start nach Countdown")
		local token = view.token
		T.eq(AS.Round(ms).token, token, "Runde in der Sitzung")
		-- Die Ausgeh-Zeitpunkte bleiben geheim, bis die Lampen wirklich ausgehen (arcade_go)
		T.eq(view.params.attempts[1].g, nil, "kein g im Rundenpaket")
		T.check(view.params.attempts[2].l ~= nil, "Beginn der Starts bekannt")
		local secret = AS.Round(ms).p.attempts
		-- zweiter Start sofort: ignoriert (Doppeltipp)
		act("mini_arcade_start", { game = "arcade_1" })
		T.eq(count("arcade_round"), 1, "Doppeltipp startet nicht neu")

		-- fremdes Token: still verworfen
		local steps = count("arcade_step")
		input(token + 1, 1)
		T.eq(count("arcade_step"), steps, "fremdes Token ohne Wirkung")
		-- zu spät angekommene Eingabe
		T.eq(count("arcade_go"), 0, "vor dem ersten Lampen-Aus kein arcade_go")
		g:AdvanceTo(view.startAt + secret[1].g + 0.2)
		T.eq(count("arcade_go"), 1, "arcade_go im Moment des Lampen-Aus")
		T.near(last("arcade_go").g, secret[1].g, 1e-9, "arcade_go nennt g")
		local stale = g:Now() - 0.7
		act("mini_arcade_input", { token = token, at = stale, value = 1, rid = 1 })
		T.eq(last("arcade_step").reject, "late", "zu alt: abgelehnt mit Grund")
		-- gültige Reaktionen
		for i, a in ipairs(secret) do
			g:AdvanceTo(view.startAt + a.g + 0.18)
			input(token, 1)
			local s = last("arcade_step")
			T.eq(s.attempt, i, "Start " .. i)
			T.eq(s.points, 200, "perfekt " .. i)
			T.eq(s.token, token, "Token im Schritt")
		end
		local money = d.money
		g:AdvanceTo(view.endAt)
		act("mini_arcade_finish", { token = token })
		local res = last("arcade_result")
		T.eq(res.score, 1000, "1000 Punkte")
		T.eq(res.credits, A.GameByKey.arcade_1.reward, "volle Belohnung")
		T.eq(d.money, money + res.credits, "Geld gutgeschrieben")
		T.eq(res.newBest, true, "Rekord")
		T.eq(d.games.arcade.best.arcade_1, 1000, "Rekord gespeichert")
		T.eq(d.games.arcade.earned, res.credits, "Tageszähler")
		T.eq(res.aborted, false, "regulär beendet")
		T.eq(AS.Round(ms), nil, "Runde geschlossen")
		-- Wiederholung: gleiches Ergebnis, keine zweite Auszahlung
		money = d.money
		act("mini_arcade_finish", { token = token })
		local again = last("arcade_result")
		T.eq(again.replay, true, "als Wiederholung markiert")
		T.eq(again.credits, res.credits, "gleiches Ergebnis")
		T.eq(d.money, money, "keine zweite Auszahlung")
		T.eq(d.games.arcade.earned, res.credits, "Tageszähler unverändert")
		-- Eingaben mit abgerechnetem Token: ohne Wirkung
		steps = count("arcade_step")
		input(token, 1)
		T.eq(count("arcade_step"), steps, "abgerechnetes Token nimmt nichts an")
		-- ausgedachtes Token
		act("mini_arcade_finish", { token = 123456 })
		T.check(toasted("nicht mehr gültig"), "ungültiges Token")
		T.eq(d.money, money, "kein Geld")

		-- Abbruch mitten in der Runde zählt nur das Gespielte
		g:Advance(1.1)
		act("mini_arcade_start", { game = "arcade_1" })
		view = last("arcade_round")
		g:AdvanceTo(view.startAt + AS.Round(ms).p.attempts[1].g + 0.18)
		input(view.token, 1)
		act("mini_arcade_finish", { token = view.token })
		res = last("arcade_result")
		T.eq(res.score, 200, "nur ein Start gewertet")
		T.eq(res.aborted, true, "abgebrochen")
		T.eq(res.credits, A.Reward("arcade_1", 200), "Credits nach Punkten")

		-- Neue Runde ersetzt die laufende: die alte zahlt nie
		g:Advance(1.1)
		act("mini_arcade_start", { game = "arcade_1" })
		local old = last("arcade_round")
		g:AdvanceTo(old.startAt + AS.Round(ms).p.attempts[1].g + 0.18)
		input(old.token, 1)
		g:Advance(1.1)
		act("mini_arcade_start", { game = "arcade_4" })
		local newer = last("arcade_round")
		T.check(newer.token ~= old.token, "neues Token")
		money = d.money
		act("mini_arcade_finish", { token = old.token })
		res = last("arcade_result")
		T.eq(res.abandoned, true, "alte Runde verworfen")
		T.eq(res.credits, 0, "0 Cr")
		T.eq(d.money, money, "kein Geld für die alte Runde")
		T.eq(AS.Round(ms).token, newer.token, "neue Runde läuft weiter")

		-- Ablauf: zu spät abgerechnet
		g:AdvanceTo(newer.endAt + A.FinishGrace + 1)
		act("mini_arcade_finish", { token = newer.token })
		res = last("arcade_result")
		T.eq(res.expired, true, "abgelaufen")
		T.eq(d.money, money, "kein Geld")
		T.check(toasted("abgelaufen"), "Hinweis")

		-- Eingabe-Eimer: Flut wird gedeckelt
		g:Advance(1.1)
		act("mini_arcade_start", { game = "arcade_4" })
		view = last("arcade_round")
		g:AdvanceTo(view.startAt + 1)
		local round = AS.Round(ms)
		for i = 1, 60 do
			act("mini_arcade_input", { token = view.token, at = g:Now(), value = i % 2, rid = 1000 + i })
		end
		T.eq(round.inputs, A.InputBurst, "höchstens der Eimer auf einmal")
		T.eq(round.rejected, 60 - A.InputBurst, "Rest abgelehnt")
		g:Advance(1)
		act("mini_arcade_input", { token = view.token, at = g:Now(), value = 1, rid = 2000 })
		T.eq(round.inputs, A.InputBurst + 1, "nach einer Sekunde wieder frei")

		-- Tageslimit: fast voll
		act("mini_arcade_finish", { token = view.token })
		local a = d.games.arcade
		a.earned = A.DailyCap - 5
		g:Advance(1.1)
		act("mini_arcade_start", { game = "arcade_1" })
		view = last("arcade_round")
		T.eq(view.capLeft, 5, "Rest im Rundenpaket")
		for _, at in ipairs(AS.Round(ms).p.attempts) do
			g:AdvanceTo(view.startAt + at.g + 0.18)
			input(view.token, 1)
		end
		money = d.money
		g:AdvanceTo(view.endAt)
		act("mini_arcade_finish", { token = view.token })
		res = last("arcade_result")
		T.eq(res.credits, 5, "nur der Rest")
		T.eq(res.capped, true, "gedeckelt")
		T.eq(res.want, A.GameByKey.arcade_1.reward, "gewollt")
		T.eq(d.money, money + 5, "Geld")
		T.eq(a.earned, A.DailyCap, "Limit voll")
		-- Übungsrunde bei vollem Limit: 0 Cr, aber Wertung und Rekord
		g:Advance(1.1)
		act("mini_arcade_start", { game = "arcade_2" })
		view = last("arcade_round")
		T.eq(view.capLeft, 0, "Limit voll im Paket")
		local run = view.params.runs[1]
		local v = run.kmh / 3.6
		g:AdvanceTo(view.startAt + run.at + (run.line - v * v / (2 * run.a)) / v)
		input(view.token, 1)
		money = d.money
		g:AdvanceTo(view.endAt)
		act("mini_arcade_finish", { token = view.token })
		res = last("arcade_result")
		T.check(res.score >= 240, "gewertet")
		T.eq(res.credits, 0, "keine Credits")
		T.eq(d.money, money, "Geld unverändert")
		T.eq(res.newBest, true, "Rekord trotzdem")

		-- Verlassen: Zustand weg
		AS.OnLeave(ms)
		T.eq(AS.States[ms], nil, "Zustand gelöscht")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Dienst: Rennen mit Takt-Meldungen, Abgleich bei Ablehnung, MOTOR-OHR-Rückmeldung", function(T, H)
		local g = H.Garage()
		local AS = g:MiniServer("ArcadeService")
		local log = {}
		local handlers = {}
		AS.Register({
			Register = function(name, fn)
				handlers[name] = fn
			end,
		}, {
			now = function()
				return g.env.workspace:GetServerTimeNow()
			end,
			toast = function() end,
			notice = function(_, kind, data)
				data.kind = kind
				table.insert(log, data)
			end,
			dirty = function() end,
		})
		local pl = g:Join(702, { name = "Ben" })
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		AS.OnJoin(ms, d, g:Now())
		local function act(name, data)
			g:Activate()
			handlers[name](ms, data, d, g:Now())
		end
		local function last(kind)
			for i = #log, 1, -1 do
				if log[i].kind == kind then
					return log[i]
				end
			end
		end
		act("mini_arcade_start", { game = "arcade_7" })
		local view = last("arcade_round")
		T.eq(view.gameKind, "race", "Rennen")
		g:AdvanceTo(view.startAt + 0.5)
		act("mini_arcade_input", { token = view.token, at = g:Now(), value = view.params.startLane, rid = 1 })
		T.eq(last("arcade_step"), nil, "Takt mit gleicher Spur: keine Rückmeldung")
		g:Advance(0.2)
		act("mini_arcade_input", { token = view.token, at = g:Now(), value = view.params.startLane + 2, rid = 2 })
		local s = last("arcade_step")
		T.eq(s and s.reject, "lane", "Sprung über zwei Spuren abgelehnt")
		T.eq(s and s.lane, view.params.startLane, "Server-Spur zum Abgleich")
		T.eq(s and s.rid, 2, "rid im Schritt")
		act("mini_arcade_finish", { token = view.token })
		-- MOTOR-OHR: Rückmeldung mit Lösung erst nach der Antwort
		g:Advance(1.1)
		act("mini_arcade_start", { game = "arcade_5" })
		view = last("arcade_round")
		local round = AS.Round(ms)
		g:AdvanceTo(view.startAt + 0.8)
		act("mini_arcade_input", { token = view.token, at = g:Now(), value = round.secret.answers[1], rid = 3 })
		s = last("arcade_step")
		T.eq(s.correct, true, "richtig")
		T.eq(s.answer, round.secret.answers[1], "Lösung nach der Antwort")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Verkabelung (sobald MiniNet die Spielhallen-Aktionen kennt): Runde über Remotes.Command", function(T, H)
		local g = H.Garage()
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.Actions.mini_arcade_start then
			T.check(true, "noch nicht verkabelt")
			return
		end
		local A = g:MiniShared("ArcadeRules")
		local pl = g:Join(703, { name = "Cleo" })
		g:Advance(0.5)
		local d = g:D(pl)
		T.eq(g:Act(pl, "mini_arcade_start", { game = "arcade_1", rid = 1 }), "ok", "mini_arcade_start")
		local view = g:Notices(pl, "arcade_round")[1]
		T.check(view ~= nil and type(view.token) == "number", "arcade_round kommt an")
		if not view then
			return
		end
		local rid = 10
		local secret = g:MiniServer("ArcadeService").Round(g:MiniState(pl)).p.attempts
		for i, a in ipairs(secret) do
			g:AdvanceTo(view.startAt + a.g + 0.18)
			local go = g:Notices(pl, "arcade_go")
			T.eq(#go, i, "arcade_go über den echten Weg " .. i)
			rid += 1
			local at = g:Now()
			g:Advance(0.03)
			T.eq(g:Act(pl, "mini_arcade_input", { token = view.token, at = at, value = 1, rid = rid }), "ok", "mini_arcade_input")
		end
		local money = d.money
		g:AdvanceTo(view.endAt)
		T.eq(g:Act(pl, "mini_arcade_finish", { token = view.token, rid = 99 }), "ok", "mini_arcade_finish")
		local res = g:Notices(pl, "arcade_result")[1]
		T.eq(res and res.score, 1000, "1000 Punkte")
		T.eq(d.money, money + A.GameByKey.arcade_1.reward, "Geld")
		g:Advance(0.6)
		T.eq(g:Act(pl, "mini_arcade_finish", { token = view.token, rid = 100 }), "ok", "zweite Abrechnung")
		T.eq(d.money, money + A.GameByKey.arcade_1.reward, "keine zweite Auszahlung")
		local snap = g:MiniSnapshot(pl)
		if snap and snap.arcade then
			T.eq(snap.arcade.earnedToday, A.GameByKey.arcade_1.reward, "Snapshot: earnedToday")
			T.eq(snap.arcade.cap, A.DailyCap, "Snapshot: cap")
			T.eq(snap.arcade.best.arcade_1, 1000, "Snapshot: best")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
	{ "Client: Auswahl, Anleitung, Start, BLITZ-REAKTION bis zum Ergebnis", function(T, H)
		local S = uiSetup(T, H)
		local g, rec = S.g, S.rec
		S.render({ arcade = { earnedToday = 100, cap = 1500, left = 1400, best = { arcade_1 = 500 } } })
		T.check(S.visible("Automat_arcade_1"), "Automat sichtbar")
		T.check(S.visible("Automat_arcade_8"), "alle 8 Automaten")
		S.click("Automat_arcade_1")
		T.check(S.visible("Anleitung"), "Anleitung sichtbar")
		T.check(not S.visible("Automat_arcade_1"), "Übersicht ausgeblendet")
		g:Advance(0.4)
		S.click("Spielen")
		local starts = rec.Of("mini_arcade_start")
		T.eq(#starts, 1, "Start gesendet")
		T.eq(starts[1] and starts[1].payload.game, "arcade_1", "Automat im Start")
		g:Advance(0.4)
		S.click("Spielen")
		T.eq(#rec.Of("mini_arcade_start"), 1, "Doppeltipp: kein zweiter Start")

		local round = S.round("arcade_1", 1234, 555)
		T.check(S.visible("Bildschirm"), "Spielbildschirm")
		T.check(S.visible("Countdown"), "Countdown")
		T.check(S.AUI.IsPlaying(), "läuft")
		T.check(g.env.casBindings.UCG_ArcadeControls ~= nil, "Tasten gebunden")
		-- vor dem Start drücken: nichts gesendet
		S.click("Druecken")
		T.eq(#rec.Of("mini_arcade_input", S.mark), 0, "vor dem Start nichts")
		for i, a in ipairs(round.p.attempts) do
			S.at(round, a.g + 0.2)
			if i == 3 then
				T.eq(g:Key(S.pl, Enum.KeyCode.Space), true, "Leertaste wird geschluckt")
			else
				S.click("Druecken")
			end
			S.click("Druecken") -- zweiter Druck im selben Start: nicht gesendet
		end
		local sent = S.forward(round)
		T.eq(#sent, 5, "genau 5 Eingaben")
		for _, e in ipairs(sent) do
			T.eq(e.ok, true, "Server nimmt an")
			T.near(e.info.reaction, 0.2, 0.02, "Reaktion ≈ 0,2 s")
		end
		for i = 1, 5 do
			local res = S.AUI.Current().st.res[i]
			T.check(res and not res.early and res.points == 200, "Client wertet Start " .. i .. " nach arcade_go wie der Server")
		end
		S.at(round, round.duration + 0.5)
		local res = S.finish(round)
		T.eq(res.score, 1000, "Server: 1000")
		T.check(S.visible("Ergebnis"), "Ergebnis sichtbar")
		local score = find(S.page, "Ergebnis")
		local hit = false
		for _, x in ipairs(score:GetDescendants()) do
			if x:IsA("TextLabel") and x.Text == "1000 Punkte" then
				hit = true
			end
		end
		T.check(hit, "1000 Punkte angezeigt")
		T.eq(g.env.casBindings.UCG_ArcadeControls, nil, "Tasten wieder frei")
		T.eq(S.AUI.IsPlaying(), false, "Runde vorbei")
		-- Nochmal
		g:Advance(3)
		S.click("Nochmal")
		T.eq(#rec.Of("mini_arcade_start"), 2, "Nochmal startet")
		-- Übersicht
		S.click("Uebersicht")
		T.check(S.visible("Automat_arcade_1"), "zurück in der Übersicht")
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },

	{ "Client: alle Automaten spielbar, Eingaben landen gültig beim Server", function(T, H)
		local S = uiSetup(T, H)
		local g, A = S.g, S.A
		-- BREMSWEG-PROFI
		local round = S.round("arcade_2", 77, 1)
		for _, run in ipairs(round.p.runs) do
			local v = run.kmh / 3.6
			S.at(round, run.at + (run.line - v * v / (2 * run.a)) / v)
			S.click("Bremsen")
		end
		local sent = S.forward(round)
		T.eq(#sent, 4, "4 Bremsungen")
		for _, e in ipairs(sent) do
			T.check(e.ok and e.info.points >= 200, "gut gebremst: " .. tostring(e.info and e.info.points))
		end
		S.at(round, round.duration + 0.5)
		T.check(S.finish(round).score >= 850, "Bremsweg-Punkte")

		-- BOXENSTOPP
		g:Advance(1)
		round = S.round("arcade_3", 99, 2)
		local t = 0.2
		for w, wheel in ipairs(round.p.wheels) do
			for k = 0, 4 do
				t += 0.25
				S.at(round, t)
				S.click("Mutter" .. A.NutAt(wheel.start, k, wheel.dir ~= 0 and wheel.dir or 1))
			end
			t += 0.65
		end
		sent = S.forward(round)
		T.eq(#sent, 20, "20 Muttern gesendet")
		for _, e in ipairs(sent) do
			T.check(e.ok and e.info.ok, "Mutter richtig")
		end
		g:Advance(0.5)
		T.check(#S.rec.Of("mini_arcade_finish", S.mark) >= 1, "nach der letzten Mutter sofort abgerechnet")
		T.check(S.finish(round).score > 900, "schneller Boxenstopp")

		-- DREHMOMENT: Leertaste halten/loslassen
		g:Advance(1)
		round = S.round("arcade_4", 5, 3)
		S.at(round, 0.1)
		g:Key(S.pl, Enum.KeyCode.Space, "Begin")
		S.at(round, 1.0)
		g:Key(S.pl, Enum.KeyCode.Space, "End")
		S.at(round, 1.5)
		S.click("Anziehen") -- Klick = drücken + loslassen
		sent = S.forward(round)
		T.eq(#sent, 4, "Wechsel: drücken, loslassen, drücken, loslassen")
		T.eq(sent[1].payload.value, 1, "gedrückt")
		T.eq(sent[2].payload.value, 0, "losgelassen")
		for _, e in ipairs(sent) do
			T.eq(e.ok, true, "angenommen")
		end
		S.at(round, round.duration + 0.5)
		S.finish(round)

		-- MOTOR-OHR: Antwort wählen, Rückmeldung vom Server
		g:Advance(1)
		round = S.round("arcade_5", 12, 4)
		S.at(round, 0.5)
		local ans = round.secret.answers[1]
		S.click("Motor" .. ans)
		sent = S.forward(round)
		T.eq(#sent, 1, "eine Antwort")
		T.eq(sent[1].payload.value, ans, "gewählter Motor")
		local step = sent[1].info
		step.kind, step.token, step.rid = "arcade_step", round.token, sent[1].rid
		S.notice(step)
		local fb = find(S.page, "Rueckmeldung")
		T.eq(fb and fb.Text, "Richtig!", "Rückmeldung")
		-- Frage 2 läuft ab: Client meldet Wert 0, Server löst auf
		S.at(round, step.nextAt + round.p.limit + 0.4)
		sent = S.forward(round)
		T.eq(#sent, 1, "Zeitablauf gemeldet")
		T.eq(sent[1].payload.value, 0, "Wert 0")
		T.eq(sent[1].info and sent[1].info.timeout, true, "Server: Zeit abgelaufen")
		S.at(round, 20)
		S.click("Beenden")
		T.check(#S.rec.Of("mini_arcade_finish", S.mark) >= 1, "vorzeitig beendet")
		S.finish(round)

		-- EINPARK-PROFI: Pfeilknöpfe und Pfeiltasten
		g:Advance(1)
		round = S.round("arcade_6", 31337, 5)
		local task = round.p.tasks[1]
		local path = parkPath(A, round.p, task)
		t = 0.2
		for i, d in ipairs(path) do
			t += 0.3
			S.at(round, t)
			if i % 2 == 0 then
				local key = ({ Enum.KeyCode.Up, Enum.KeyCode.Right, Enum.KeyCode.Down, Enum.KeyCode.Left })[d]
				g:Key(S.pl, key)
			else
				S.click("Pfeil" .. d)
			end
		end
		sent = S.forward(round)
		T.eq(#sent, #path, "alle Züge gesendet")
		T.eq(sent[#sent].info and sent[#sent].info.parked, true, "Server: eingeparkt")
		S.at(round, t + 2)
		S.click("Beenden")
		T.eq(S.finish(round).score, 333, "eine Aufgabe ideal")

		-- RENNSIMULATOR 2: Takt und Spurwechsel
		g:Advance(1)
		round = S.round("arcade_8", 4711, 6)
		S.at(round, 0.3)
		g:Key(S.pl, Enum.KeyCode.Right)
		S.at(round, 1.2)
		sent = S.forward(round)
		local changes, beats = 0, 0
		for _, e in ipairs(sent) do
			T.eq(e.ok, true, "angenommen")
			if e.payload.value == round.p.startLane + 1 and changes == 0 then
				changes += 1
			else
				beats += 1
			end
		end
		T.eq(changes, 1, "Spurwechsel")
		T.check(beats >= 1, "Takt-Meldungen")
		T.eq(round.st.lane, round.p.startLane + 1, "Server-Spur")
		S.at(round, round.duration + 0.5)
		S.finish(round)
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },

	{ "Client: Ablehnung baut den Zustand neu auf, Schließen beendet die Runde, Station wählt Automaten", function(T, H)
		local S = uiSetup(T, H)
		local g = S.g
		local round = S.round("arcade_6", 31337, 7)
		local task = round.p.tasks[1]
		local path = parkPath(S.A, round.p, task)
		S.at(round, 0.5)
		S.click("Pfeil" .. path[1])
		local cur = S.AUI.Current()
		T.check(cur.st.x ~= task.sx or cur.st.y ~= task.sy or cur.st.h ~= task.sh, "lokal gefahren")
		local sent = S.forward(round)
		S.notice({ kind = "arcade_step", token = round.token, reject = "late", rid = sent[1].rid })
		T.eq(cur.st.x, task.sx, "zurück auf Start (x)")
		T.eq(cur.st.y, task.sy, "zurück auf Start (y)")
		T.eq(cur.st.moves, 0, "Zug verworfen")
		T.eq(#cur.inputs, 0, "Eingabe entfernt")
		-- Panel zu: Runde wird abgerechnet
		g:Activate()
		S.gui.Enabled = false
		g:Advance(0.5)
		T.eq(#S.rec.Of("mini_arcade_finish", S.mark), 1, "Schließen rechnet ab")
		-- Ergebnis kommt, während das Panel zu ist: Hinweis
		S.notice({ kind = "arcade_result", token = round.token, game = "arcade_6", score = 300, credits = 7, rating = "Solide." })
		T.check(#S.toasts == 1 and S.toasts[1]:find("7 Cr", 1, true) ~= nil, "Hinweis mit Credits")
		g:Activate()
		S.gui.Enabled = true
		-- Station: Automat über Anzeigenamen
		local ok = g:InClient(S.pl, function()
			return S.AUI.Select("MOTOR-OHR")
		end)
		T.eq(ok, true, "Select")
		T.check(S.visible("Anleitung"), "Anleitung")
		local title = find(S.page, "Anleitung")
		local hit = false
		for _, x in ipairs(title:GetDescendants()) do
			if x:IsA("TextLabel") and x.Text == "MOTOR-OHR" then
				hit = true
			end
		end
		T.check(hit, "richtiger Automat")
		T.eq(g:InClient(S.pl, function()
			return S.AUI.Select("flipper")
		end), false, "unbekannt")
		-- Tageslimit: Hinweis im Spiel
		S.round("arcade_1", 3, 8, 0)
		local hint = false
		for _, x in ipairs(S.page:GetDescendants()) do
			if x:IsA("TextLabel") and x.Text:find("Tageslimit erreicht", 1, true) then
				hint = true
			end
		end
		T.check(hint, "Limit-Hinweis")
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },
	{ "Verkabelung Client (sobald Tab arcade existiert): Station → Anleitung → Runde → Ergebnis im echten Panel", function(T, H)
		local g = H.Garage()
		if not g:MiniShared("MiniNet").Actions.mini_arcade_start then
			T.check(true, "noch nicht verkabelt")
			return
		end
		local pl = g:Join(1201, { name = "Wira" })
		g:Advance(0.5)
		g:StartClient(pl)
		g:Advance(2)
		local MiniUI = g:ClientModule(pl, "Mini.MiniUI")
		if not MiniUI.Pages.arcade then
			T.check(true, "Tab arcade noch nicht verkabelt")
			return
		end
		local city = g.env.workspace:FindFirstChild("City")
		local station = city and city:FindFirstChild("Stations") and city.Stations:FindFirstChild("arcade_3")
		if not T.check(station ~= nil, "Station arcade_3 in der Stadt") then
			return
		end
		T.eq(station:GetAttribute("Game"), "BOXENSTOPP", "Stadt: Attribut Game")
		g:Teleport(pl, station)
		g:Advance(0.5)
		g:Trigger(pl, station:FindFirstChildOfClass("ProximityPrompt"), { force = true })
		g:Advance(0.5)
		local open = g:Last(pl, "mini_open")
		T.eq(open and open.tab, "arcade", "mini_open: Tab")
		T.eq(open and open.game, "BOXENSTOPP", "mini_open: Automat")
		T.eq(MiniUI.CurrentTab, "arcade", "Tab offen")
		local page = MiniUI.Pages.arcade
		local intro = page:FindFirstChild("Anleitung", true)
		T.check(intro and H.Mock.IsGuiVisible(intro), "Anleitung des Automaten")
		g:Advance(0.4)
		g:Click(page:FindFirstChild("Spielen", true))
		g:Advance(0.5)
		local round = g:Notices(pl, "arcade_round")[1]
		if not T.check(round ~= nil, "Runde vom Server") then
			return
		end
		T.eq(round.game, "arcade_3", "Boxenstopp")
		local A = g:MiniShared("ArcadeRules")
		local t = 0.3
		for _, wheel in ipairs(round.params.wheels) do
			for k = 0, 4 do
				t += 0.3
				g:AdvanceTo(round.startAt + t)
				g:Click(page:FindFirstChild("Mutter" .. A.NutAt(wheel.start, k, wheel.dir ~= 0 and wheel.dir or 1), true))
			end
			t += 0.7
		end
		g:Advance(1.5)
		local res = g:Notices(pl, "arcade_result")[1]
		T.check(res ~= nil and res.score > 800, "Ergebnis " .. tostring(res and res.score))
		T.check(res ~= nil and res.credits > 0, "Credits")
		local shown = page:FindFirstChild("Ergebnis", true)
		T.check(shown and H.Mock.IsGuiVisible(shown), "Ergebnis angezeigt")
		local snap = g:MiniSnapshot(pl)
		T.check(snap and snap.arcade and res and snap.arcade.earnedToday == res.credits, "Snapshot arcade")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
		for _, w in ipairs(g:Warnings()) do
			T.check(not tostring(w):find("Spielhalle", 1, true), "Warnung: " .. tostring(w))
		end
	end },

	{ "Rückdatieren begrenzt: Skript mit at = g + 0,2 nach dem Lampen-Aus bekommt keine 1000 Punkte", function(T, H)
		local A = rules(H)
		local lat = A.Latency(0.1) -- 100 ms Round-Trip -> 50 ms Einweg
		T.near(lat, 0.05, 1e-9, "Einweg-Latenz = halbe Round-Trip-Zeit")
		T.eq(A.Latency(2), A.LatencyCap, "gedeckelt")
		T.eq(A.Latency(nil), A.DefaultLatency, "ohne Messung: Standard")
		local round = A.NewRound("arcade_1", 4711, 1000, 1, lat)
		-- Rundenpaket ohne Ausgeh-Zeitpunkte, nichts daraus ableitbar
		local view = A.View(round)
		for i, a in ipairs(view.params.attempts) do
			T.eq(a.g, nil, "kein g in Start " .. i)
		end
		T.eq(round.p.attempts[1].g ~= nil, true, "Server kennt g")
		local period = A.ReactionPeriod()
		for i, a in ipairs(view.params.attempts) do
			T.near(a.l, (i - 1) * period, 1e-9, "feste Taktung verrät g nicht (Start " .. i .. ")")
		end
		local r2 = A.NewRound("arcade_1", 99, 1000, 2, lat)
		T.eq(r2.duration, round.duration, "Dauer unabhängig von den Pausen")
		-- Angriff: nach dem (gesehenen) Lampen-Aus 0,6 s warten, dann at = g + 0,2 behaupten
		local total = 0
		for _, a in ipairs(round.p.attempts) do
			local arrive = round.startAt + a.g + 0.6
			local ok, info = A.Input(round, round.startAt + a.g + 0.2, 1, arrive)
			T.eq(ok, true, "angenommen, aber …")
			T.check(info.reaction >= 0.6 - lat - A.LatencySlack - lat - 1e-6, "… gewertet ab Ankunft − Latenz (" .. tostring(info.reaction) .. ")")
			total += info.points
		end
		T.check(total < 700, "keine Höchstpunktzahl durch Rückdatieren (" .. total .. ")")
		-- ehrlicher Spieler mit Latenz: at = Druckzeitpunkt, kommt lat später an -> volle Punkte bei 0,2 s echter Reaktion
		local fair = A.NewRound("arcade_1", 4711, 1000, 3, lat)
		local sum = 0
		for _, a in ipairs(fair.p.attempts) do
			local seen = fair.startAt + a.g + lat -- arcade_go kommt lat später an
			local press = seen + 0.2
			local _, info = A.Input(fair, press, 1, press + lat)
			sum += info.points
		end
		T.eq(sum, 1000, "ehrlich mit Latenz: 1000")
		-- andere Automaten: Rückdatierung ebenso begrenzt
		local brake = A.NewRound("arcade_2", 5, 1000, 4, lat)
		local now = brake.startAt + 5
		T.near(A.InputTime(now - 0.45, now, lat), now - lat - A.LatencySlack, 1e-9, "0,45 s alt -> auf Ankunft − Latenz angehoben")
		T.near(A.InputTime(now - 0.05, now, lat), now - 0.05, 1e-9, "innerhalb der Latenz unverändert")
	end },

	{ "Client: Druck vor arcade_go gilt lokal als Frühstart, die Server-Bewertung gewinnt", function(T, H)
		local S = uiSetup(T, H)
		local g = S.g
		local round = S.round("arcade_1", 321, 777)
		local a = round.p.attempts[1]
		-- arcade_go ist unterwegs (Server ist schon bei g + 0,25), der Spieler drückt: lokal noch Lampen an
		g:AdvanceTo(round.startAt + a.g + 0.25)
		S.click("Druecken")
		local cur = S.AUI.Current()
		T.check(cur.st.res[1] and cur.st.res[1].early, "lokal Frühstart (Lampen noch an)")
		local sent = S.forward(round)
		T.eq(#sent, 1, "gesendet")
		local info = sent[1].info
		T.check(info and not info.early and info.points > 0, "Server: gültige Reaktion")
		info.kind = "arcade_step"
		info.token = round.token
		S.notice(info)
		T.check(cur.st.res[1] and not cur.st.res[1].early and cur.st.res[1].points == info.points, "Server-Bewertung übernommen")
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },

	{ "Client: Panel mitten in der Runde zu -> Tasten sofort frei, auch ohne Antwort des Servers", function(T, H)
		local S = uiSetup(T, H)
		local g = S.g
		local round = S.round("arcade_7", 55, 888)
		S.at(round, 1)
		T.check(g.env.casBindings.UCG_ArcadeControls ~= nil, "Tasten gebunden")
		T.eq(g:Key(S.pl, Enum.KeyCode.A), true, "A wird während der Runde geschluckt")
		-- Panel geschlossen (× / M / Tablet / QTE): Seite unsichtbar
		g:Activate()
		S.gui.Enabled = false
		g:Advance(0.5)
		T.eq(#S.rec.Of("mini_arcade_finish"), 1, "Abrechnung angefragt")
		T.eq(g.env.casBindings.UCG_ArcadeControls, nil, "Tasten sofort frei (vor arcade_result)")
		T.eq(g:Key(S.pl, Enum.KeyCode.W), false, "W erreicht die Figur wieder")
		T.eq(g:Key(S.pl, Enum.KeyCode.Space), false, "Leertaste springt wieder")
		-- Server antwortet nie: bleibt frei
		g:Advance(10)
		T.eq(g.env.casBindings.UCG_ArcadeControls, nil, "bleibt frei")
		T.eq(#S.errors(), 0, "keine Fehler: " .. table.concat(S.errors(), "\n"))
	end },
}
