-- Ausbaustufe 4, Meilenstein 2 (Team lobby): PlaceRouter und LobbyService im echten Server (eigene Aktionen-Tabelle wie
-- test_prestige, unabhängig von der MiniService-Verkabelung), TeleportService-Mock, LobbyUI im Mock-Client.
-- Zonen kommen aus der Fixture (tools/worldgen: Lobby bei Z -700, Stadt, Tycoon ab Z +700).
local NOW = 1760000000

---------------------------------------------------------------- Hilfen
-- meta/prestige im Profil sicherstellen (bis MiniRules.DefaultGames/LoadGames MetaRules aufrufen)
local function ensureMeta(g, d, raw)
	if type(d.games.meta) ~= "table" then
		local MR = g:MiniShared("MetaRules")
		if type(raw) == "table" then
			MR.ApplyLoad(d.games, raw, d, g:Now())
		else
			MR.ApplyDefault(d.games)
		end
	end
end

-- Server mit LobbyService über eine eigene Aktionen-Tabelle; Hinweise/Toasts laufen über das echte Remote Event,
-- damit g:Notices / g:HasToast funktionieren.
local function setup(H, opts)
	opts = opts or {}
	opts.placeKind = opts.placeKind or "all" -- all-Place: Anfangsmodus aus dem Profil (erster Beitritt Lobby)
	local g = H.Garage(opts)
	local LS = g:MiniServer("LobbyService")
	local PR = g:MiniServer("PlaceRouter")
	local Event = g:Remote("Event")
	local handlers = {}
	local log = { dirty = 0 }
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
		moveTo = function(p, part)
			H.Mock.Teleport(g.env, p.player, part, Vector3.new(0, 3.5, 6))
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
		worldChanged = function() end,
		writable = function()
			return false
		end,
		alive = function()
			return true
		end,
	}
	LS.Register({
		Register = function(name, fn)
			handlers[name] = fn
		end,
	}, fakeApi)
	LS.Init(ctx)
	local S = { g = g, LS = LS, PR = PR, log = log, handlers = handlers, ctx = ctx }
	function S.join(userId, name, joinData)
		-- Rohdatensatz vor dem Beitritt lesen: P.Load schreibt das (noch ohne MetaRules geladene) Profil sofort zurück
		local raw = g:Record(userId)
		raw = raw and raw.data and raw.data.games or nil
		local pl = H.Mock.NewPlayer(g.env, userId, name)
		if joinData then
			H.Mock.SetJoinData(g.env, pl, joinData)
		end
		table.insert(g.players, pl)
		H.Mock.Join(g.env, pl)
		H.Mock.Flush(g.env)
		H.Mock.SpawnCharacter(g.env, pl)
		H.Mock.Flush(g.env)
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		ensureMeta(g, d, raw)
		ms.greeted = true
		LS.OnJoin(ms, d, g:Now())
		LS.OnCharacter(ms)
		g:Flush()
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
	function S.leave(pl)
		local ms = g:MiniState(pl)
		if ms then
			LS.OnLeave(ms)
		end
		g:Leave(pl)
	end
	function S.snapshot(pl)
		local ms = g:MiniState(pl)
		return LS.SnapshotFields(ms, g:D(pl), g:Now(), true)
	end
	function S.teleports()
		return g.env.services.TeleportService.__calls
	end
	return S
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

-- Zonen-Ankünfte aus der Fixture (tools/worldgen): Lobby hub (0,0,-668), Stadt hub (0,0,-192), Tycoon hub (0,-0.45,856)
local HUB = { lobby = { 0, -668 }, openworld = { 0, -192 }, tycoon = { 0, 856 } }

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
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p)
	g:Advance(1.5)
	return g, p
end

local function build(g, p, rec, ctxExtra)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini.LobbyUI")
	local toasts = {}
	local state = { tablet = false, blocked = false }
	local page = g:InClient(p, function()
		local gui = Instance.new("ScreenGui")
		gui.Name = "LobbyTest"
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
		mod.Build(frame, ctx)
		return frame
	end)
	return mod, page, MiniUI, toasts, state
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

local function press(g, button)
	g:Advance(0.35)
	local ok = g:Click(button)
	g:Advance(0.05)
	return ok
end

local function snapshot(mode, extra)
	local s = {
		credits = 1000, level = 3,
		mode = mode or "lobby", placeKind = "all", single = false, simulated = true, choice = false,
		meta = { beginner = true, passive = false, single = false, tutorialDone = false, tutorialStep = 1 },
		party = false,
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

---------------------------------------------------------------- Fälle
return {
	{ "PlaceRouter: Anfangsmodus aus PlaceKind, gespeichertem Modus und geprüften TeleportData", function(T, H)
		local S = setup(H)
		local g, PR, LS = S.g, S.PR, S.LS
		local GC = g:MiniShared("GameConfig")
		T.eq(PR.PlaceKind(), "all", "ohne Attribut: all")
		-- erster Beitritt im all-Place: Lobby, Figur an der Lobby-Ankunft
		local a, msA, dA = S.join(1, "Anna")
		T.eq(msA.p.mode, "lobby", "erster Beitritt: Lobby")
		T.eq(dA.games.meta.lastMode, "lobby", "lastMode lobby")
		T.eq(dA.games.meta.firstSeen, math.floor(g:Now()), "firstSeen gesetzt")
		near(T, rootPos(g, a), HUB.lobby[1], HUB.lobby[2], 6, "Anna an der Lobby-Ankunft")
		local snap = S.snapshot(a)
		T.eq(snap.mode, "lobby", "Snapshot mode")
		T.eq(snap.placeKind, "all", "Snapshot placeKind")
		T.eq(snap.simulated, true, "Snapshot simulated (Platzhalter-Ids)")
		T.eq(snap.party, false, "Snapshot ohne Party")
		T.eq(snap.meta.beginner, true, "Snapshot meta.beginner")
		T.eq(snap.meta.tutorialStep, 1, "Snapshot meta.tutorialStep")
		-- gespeicherter Modus tycoon -> Beitritt im Tycoon
		local rec = { version = 2, data = g:Rules().NewData(NOW), receipts = {} }
		g:MiniShared("MetaRules").ApplyDefault(rec.data.games)
		rec.data.games.meta.lastMode = "tycoon"
		g:Seed(2, rec)
		local b, msB = S.join(2, "Ben")
		T.eq(msB.p.mode, "tycoon", "gespeicherter Modus tycoon")
		near(T, rootPos(g, b), HUB.tycoon[1], HUB.tycoon[2], 6, "Ben an der Tycoon-Ankunft")
		-- Open World: Figur bleibt an der Werkstatt (GarageServer.moveTo home), kein Versetzen
		local rec2 = { version = 2, data = g:Rules().NewData(NOW), receipts = {} }
		g:MiniShared("MetaRules").ApplyDefault(rec2.data.games)
		rec2.data.games.meta.lastMode = "openworld"
		g:Seed(3, rec2)
		local c, msC = S.join(3, "Cem")
		T.eq(msC.p.mode, "openworld", "gespeicherter Modus openworld")
		T.eq(msC.arrivalPending, false, "Open World: kein Versetzen nötig")
		local plot = g:Plot(c)
		local home = plot and plot.Stations.home
		local pc = rootPos(g, c)
		T.check(home and pc and (pc - home.Position).Magnitude < 12, "Cem bleibt an seiner Werkstatt")
		-- TeleportData: mode/single übernommen, Müll ignoriert
		local d1, msD = S.join(4, "Dana", { TeleportData = { mode = "tycoon", single = true, party = "ab12", junk = "x", amount = 999 } })
		T.eq(msD.p.mode, "tycoon", "TeleportData.mode übernommen")
		-- Snapshot-Feld single folgt der Sitzung (p.single), auch wenn TeleportData single = false und das Profil
		-- single = true sagt (Operatorpräzedenz-Falle `p and p.single == true or settings.single`)
		local dS, msS, ddS = S.join(9, "Solo", { TeleportData = { mode = "tycoon", single = false } })
		ddS.games.meta.single = true
		T.eq(msS.p.single, false, "Sitzung nicht als Einzelspieler markiert")
		T.eq(S.snapshot(dS).single, false, "Snapshot single = false (Sitzung), nicht die gespeicherte Einstellung")
		T.eq(S.snapshot(dS).meta.single, true, "meta.single zeigt die gespeicherte Einstellung")
		T.eq(LS.SnapshotFields(nil, ddS, g:Now(), true).single, true, "ohne Sitzung: gespeicherte Einstellung")
		T.eq(msD.p.single, true, "TeleportData.single übernommen")
		T.eq(msD.p.partyCode, "AB12", "TeleportData.party großgeschrieben")
		near(T, rootPos(g, d1), HUB.tycoon[1], HUB.tycoon[2], 6, "Dana an der Tycoon-Ankunft")
		local e, msE = S.join(5, "Eli", { TeleportData = { mode = 42, single = "ja", party = string.rep("Z", 60) } })
		T.eq(msE.p.mode, "lobby", "ungültige TeleportData: Standard")
		T.eq(msE.p.single, false, "single bleibt false")
		T.eq(msE.p.partyCode, nil, "zu langer Party-Code verworfen")
		local clean = PR.SanitizeTeleportData({ mode = "openworld", single = false, party = "QQQQ", extra = true, mode2 = "x" })
		T.eq(clean.mode, "openworld", "Sanitize mode")
		T.eq(clean.single, false, "Sanitize single false bleibt")
		T.eq(clean.party, "QQQQ", "Sanitize party")
		T.eq(clean.extra, nil, "Sanitize: fremde Schlüssel weg")
		T.eq(next(PR.SanitizeTeleportData("nix")), nil, "Sanitize: kein Table -> leer")
		-- fester Place-Kind: TeleportData.mode zählt nicht
		local mode, info = PR.InitialMode(msE.p, "tycoon", { TeleportData = { mode = "openworld" } })
		T.eq(mode, "tycoon", "tycoon-Place erzwingt tycoon")
		T.eq(info.source, "place", "Quelle place")
		mode = PR.InitialMode(msE.p, "lobby", nil)
		T.eq(mode, "lobby", "lobby-Place -> lobby")
		mode = PR.InitialMode(msE.p, "openworld", nil)
		T.eq(mode, "openworld", "openworld-Place -> openworld")
		-- Attribut PlaceKind an GarageShared
		g:Find("ReplicatedStorage.GarageShared"):SetAttribute("PlaceKind", "lobby")
		T.eq(PR.PlaceKind(), "lobby", "Attribut PlaceKind gelesen")
		T.eq(S.snapshot(e).placeKind, "lobby", "Snapshot placeKind aus Attribut")
		g:Find("ReplicatedStorage.GarageShared"):SetAttribute("PlaceKind", "quatsch")
		T.eq(PR.PlaceKind(), "all", "unbekanntes Attribut -> all")
		T.eq(#S.teleports(), 0, "kein Teleport bei Platzhalter-Ids")
		T.eq(#g:Errors(), 0, "keine Fehler: " .. g:ErrorText())
	end },

	{ "Simulation: lobby_mode + lobby_go versetzen die Figur, lobby_return zurück, fehlende Zone bleibt", function(T, H)
		local S = setup(H)
		local g, LS = S.g, S.LS
		local a, msA, dA = S.join(1, "Anna")
		-- falscher Modus
		S.act(a, "lobby_mode", { mode = "lobby" })
		T.check(g:HasToast(a, "gibt es nicht"), "lobby_mode lobby abgelehnt")
		T.eq(msA.lobbyChoice, nil, "keine Auswahl")
		-- tycoon wählen und los
		local mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		T.eq(msA.lobbyChoice, "tycoon", "Auswahl tycoon")
		T.eq(S.snapshot(a).choice, "tycoon", "Snapshot choice")
		S.act(a, "lobby_go")
		T.eq(msA.p.mode, "tycoon", "Modus tycoon")
		T.eq(dA.games.meta.lastMode, "tycoon", "lastMode gespeichert")
		near(T, rootPos(g, a), HUB.tycoon[1], HUB.tycoon[2], 6, "Anna an der Tycoon-Ankunft")
		local notices = g:Notices(a, "mode", mark)
		T.eq(#notices, 1, "ein mode-Hinweis")
		T.eq(notices[1] and notices[1].mode, "tycoon", "Hinweis mode")
		T.eq(notices[1] and notices[1].simulated, true, "Hinweis simulated")
		T.eq(msA.lobbyChoice, nil, "Auswahl nach Reise leer")
		T.check(g:HasToast(a, "Tycoon", mark), "Ankunftstoast")
		-- noch einmal dorthin: schon da
		mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		S.act(a, "lobby_go")
		T.check(g:HasToast(a, "schon hier", mark), "schon hier")
		T.eq(#g:Notices(a, "mode", mark), 0, "kein zweiter Hinweis")
		-- zurück in die Lobby
		mark = g:Mark()
		S.act(a, "lobby_return")
		T.eq(msA.p.mode, "lobby", "zurück in der Lobby")
		near(T, rootPos(g, a), HUB.lobby[1], HUB.lobby[2], 6, "Anna an der Lobby-Ankunft")
		T.eq(#g:Notices(a, "mode", mark), 1, "mode-Hinweis lobby")
		mark = g:Mark()
		S.act(a, "lobby_return")
		T.check(g:HasToast(a, "schon in der Lobby", mark), "schon in der Lobby")
		-- Open World mit laufendem Tutorial: Ankunft in der eigenen Werkstatt (dort beginnt Schritt 1/3);
		-- ohne Auswahl fällt lobby_go auf openworld zurück
		mark = g:Mark()
		S.act(a, "lobby_go")
		T.eq(msA.p.mode, "openworld", "ohne Auswahl: Open World")
		local homeA = g:Plot(a).Stations.home
		local posA = rootPos(g, a)
		T.check(posA and (posA - homeA.Position).Magnitude < 12, "Tutorial läuft: Ankunft in der eigenen Werkstatt statt am Stadt-Hub")
		-- Tutorial erledigt: Stadt-Ankunft
		S.act(a, "lobby_return")
		dA.games.meta.tutorialDone = true
		S.act(a, "lobby_mode", { mode = "openworld" })
		S.act(a, "lobby_go")
		near(T, rootPos(g, a), HUB.openworld[1], HUB.openworld[2], 6, "Anna an der Stadt-Ankunft")
		-- Figur im Sitz: Unseat vor PivotTo
		S.act(a, "lobby_return")
		local seat = Instance.new("VehicleSeat")
		seat.Parent = workspace
		local humanoid = a.Character:FindFirstChildOfClass("Humanoid")
		humanoid.SeatPart = seat
		local weld = Instance.new("Weld")
		weld.Name = "SeatWeld"
		weld.Parent = seat
		S.act(a, "lobby_mode", { mode = "openworld" })
		S.act(a, "lobby_go")
		T.eq(seat:FindFirstChild("SeatWeld"), nil, "SeatWeld vor dem Versetzen entfernt")
		near(T, rootPos(g, a), HUB.openworld[1], HUB.openworld[2], 6, "aus dem Sitz zur Stadt")
		-- fehlende Zone: bleiben + Toast, Modus unverändert
		S.act(a, "lobby_return")
		local tycoon = workspace:FindFirstChild("Tycoon")
		tycoon:Destroy()
		mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		S.act(a, "lobby_go")
		T.eq(msA.p.mode, "lobby", "Modus bleibt lobby")
		T.eq(dA.games.meta.lastMode, "lobby", "lastMode bleibt")
		T.check(g:HasToast(a, "nicht vorhanden", mark), "Toast: Bereich fehlt")
		T.eq(#g:Notices(a, "mode", mark), 0, "kein mode-Hinweis")
		near(T, rootPos(g, a), HUB.lobby[1], HUB.lobby[2], 6, "Anna bleibt in der Lobby")
		-- Open World ohne Stadt: Werkstatt als Ankunft
		workspace:FindFirstChild("City"):Destroy()
		mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "openworld" })
		S.act(a, "lobby_go")
		T.eq(msA.p.mode, "openworld", "Open World ohne Stadt möglich")
		local home = g:Plot(a).Stations.home
		local pa = rootPos(g, a)
		T.check(pa and (pa - home.Position).Magnitude < 12, "ohne Stadt: eigene Werkstatt")
		-- Level-Sperre greift (mode:tycoon ist ab Level 1 frei; unbekannter Schlüssel scheitert laut)
		local U = g:MiniShared("Unlocks")
		T.eq(U.Has(dA, "mode:tycoon"), true, "mode:tycoon frei")
		-- OnCharacter: nach dem Erscheinen außerhalb der Open World zur Zone
		S.act(a, "lobby_return")
		g:Respawn(a)
		g:Advance(0.5)
		LS.OnCharacter(msA)
		near(T, rootPos(g, a), HUB.lobby[1], HUB.lobby[2], 6, "nach Respawn wieder an der Lobby-Ankunft")
		-- Spielzeit
		LS.Tick(msA, dA, g:Now())
		g:Advance(5)
		LS.Tick(msA, dA, g:Now())
		T.check(dA.games.meta.playSeconds >= 4 and dA.games.meta.playSeconds <= 6, "playSeconds ≈ 5: " .. tostring(dA.games.meta.playSeconds))
		T.eq(#g:Errors(), 0, "keine Fehler: " .. g:ErrorText())
	end },

	{ "Einstellungen: lobby_settings wirkt sofort, wird gespeichert und nach Verlassen/Beitritt geladen", function(T, H)
		local S = setup(H)
		local g, LS = S.g, S.LS
		local a, msA, dA = S.join(7, "Anna")
		local mark = g:Mark()
		S.act(a, "lobby_settings", { single = true, passive = true, beginner = false })
		T.eq(dA.games.meta.single, true, "single gesetzt")
		T.eq(dA.games.meta.passive, true, "passive gesetzt")
		T.eq(dA.games.meta.beginner, false, "beginner aus")
		T.eq(msA.p.single, true, "p.single folgt der Einstellung")
		T.check(g:HasToast(a, "gespeichert", mark), "Toast gespeichert")
		local snap = S.snapshot(a)
		T.eq(snap.meta.single, true, "Snapshot meta.single")
		T.eq(snap.meta.passive, true, "Snapshot meta.passive")
		T.eq(snap.meta.beginner, false, "Snapshot meta.beginner")
		T.eq(snap.single, true, "Snapshot single")
		mark = g:Mark()
		S.act(a, "lobby_settings", { single = true, passive = true, beginner = false })
		T.check(g:HasToast(a, "schon so", mark), "unverändert gemeldet")
		-- Hinweise nur im Beginner-Modus: Station settings ohne Beginner -> kein Hinweis
		local MR = g:MiniShared("MetaRules")
		T.eq(MR.HintFor(dA, "station:mode_tycoon"), nil, "ohne Beginner kein Hinweis")
		S.act(a, "lobby_settings", { single = true, passive = true, beginner = true })
		mark = g:Mark()
		local station = workspace.Lobby.Stations:FindFirstChild("mode_tycoon")
		T.check(station ~= nil, "Lobby-Station mode_tycoon in der Fixture")
		LS.OnStation(msA, station)
		g:Flush()
		local lobbyNotices = g:Notices(a, "lobby", mark)
		T.eq(#lobbyNotices, 1, "lobby-Hinweis")
		T.eq(lobbyNotices[1] and lobbyNotices[1].action, "mode_tycoon", "action mode_tycoon")
		T.check(lobbyNotices[1] and type(lobbyNotices[1].hint) == "string", "Beginner-Hinweis zur Station")
		T.eq(msA.lobbyChoice, "tycoon", "Portal-Station wählt den Modus vor")
		mark = g:Mark()
		LS.OnStation(msA, station)
		g:Flush()
		lobbyNotices = g:Notices(a, "lobby", mark)
		T.eq(lobbyNotices[1] and lobbyNotices[1].hint, nil, "Hinweis nur einmal")
		-- Verlassen (Speichern) und mit demselben DataStore wieder beitreten
		S.leave(a)
		g:Advance(1)
		local rec = g:Record(7)
		T.check(rec and rec.data and rec.data.games and type(rec.data.games.meta) == "table", "meta im Datensatz gespeichert")
		local saved = rec and rec.data and rec.data.games and rec.data.games.meta or {}
		T.eq(saved.single, true, "gespeichert single")
		T.eq(saved.passive, true, "gespeichert passive")
		T.eq(saved.beginner, true, "gespeichert beginner")
		T.check(type(saved.hintsSeen) == "table" and saved.hintsSeen.h_mode_tycoon == true or (function()
			for id in pairs(saved.hintsSeen or {}) do
				if type(id) == "string" then
					return true
				end
			end
			return false
		end)(), "gesehener Hinweis gespeichert")
		local a2, msA2, dA2 = S.join(7, "Anna")
		T.eq(dA2.games.meta.single, true, "nach Beitritt single geladen")
		T.eq(dA2.games.meta.passive, true, "nach Beitritt passive geladen")
		T.eq(msA2.p.single, true, "p.single aus dem Profil")
		T.eq(msA2.p.mode, "lobby", "Modus lobby (nie verreist)")
		T.eq(MR.HintFor(dA2, "station:mode_tycoon"), nil, "Hinweis bleibt gesehen")
		T.eq(#g:Errors(), 0, "keine Fehler: " .. g:ErrorText())
	end },

	{ "Party: erstellen, beitreten (Code), voll, entfernen, Leiter verlässt den Server, Reise gemeinsam", function(T, H)
		local S = setup(H)
		local g, LS = S.g, S.LS
		local GC = g:MiniShared("GameConfig")
		local a, msA = S.join(1, "Anna")
		local b, msB = S.join(2, "Ben")
		local c, msC = S.join(3, "Cem")
		local d1, msD = S.join(4, "Dana")
		local e, msE = S.join(5, "Eli")
		-- erstellen
		local mark = g:Mark()
		S.act(a, "party_create")
		local party = LS.PartyOf(a)
		T.check(party ~= nil, "Party angelegt")
		local code = party and party.code or ""
		T.eq(#code, GC.Party.CodeLength, "Code hat 4 Zeichen")
		T.check(code:match("^[" .. GC.Party.CodeAlphabet .. "]+$") ~= nil, "Code nur aus dem Alphabet: " .. code)
		local created = g:Notices(a, "party", mark)
		T.eq(created[1] and created[1].event, "created", "Hinweis created")
		T.eq(created[1] and created[1].code, code, "Hinweis mit Code")
		T.check(g:HasToast(a, code, mark), "Toast mit Code")
		mark = g:Mark()
		S.act(a, "party_create")
		T.check(g:HasToast(a, "schon in einer Party", mark), "keine zweite Party")
		-- beitreten: Kleinschreibung und Leerzeichen erlaubt, falscher Code abgelehnt
		mark = g:Mark()
		S.act(b, "party_join", { code = "zz" })
		T.check(g:HasToast(b, "4 Zeichen", mark), "Codeformat geprüft")
		S.act(b, "party_join", { code = "ZZZZ" })
		T.check(g:HasToast(b, "gibt es hier nicht", mark), "unbekannter Code")
		mark = g:Mark()
		S.act(b, "party_join", { code = " " .. string.lower(code) .. " " })
		T.eq(LS.PartyOf(b), party, "Ben in der Party")
		T.check(g:HasToast(b, "beigetreten", mark), "Toast beigetreten")
		local joinedA = g:Notices(a, "party", mark)
		T.check(#joinedA >= 1 and joinedA[#joinedA].event == "joined" and joinedA[#joinedA].userId == 2, "Anna sieht Bens Beitritt")
		g:Advance(GC.Party.JoinCooldown + 0.1)
		S.act(c, "party_join", { code = code })
		g:Advance(GC.Party.JoinCooldown + 0.1)
		S.act(d1, "party_join", { code = code })
		T.eq(#party.members, 4, "vier Mitglieder")
		mark = g:Mark()
		g:Advance(GC.Party.JoinCooldown + 0.1)
		S.act(e, "party_join", { code = code })
		T.eq(LS.PartyOf(e), nil, "Eli passt nicht mehr hinein")
		T.check(g:HasToast(e, "voll", mark), "Toast voll")
		-- Snapshot
		local snap = S.snapshot(b)
		T.eq(snap.party.code, code, "Snapshot party.code")
		T.eq(snap.party.leader, 1, "Snapshot party.leader")
		T.eq(snap.party.isLeader, false, "Ben ist nicht Leiter")
		T.eq(#snap.party.members, 4, "Snapshot Mitglieder")
		T.eq(snap.party.members[1].userId, 1, "erstes Mitglied Anna")
		T.eq(snap.party.members[1].name, "Anna", "Name")
		T.eq(snap.party.members[1].leader, true, "Leiter markiert")
		T.eq(S.snapshot(a).party.isLeader, true, "Anna ist Leiter")
		-- entfernen: nur der Leiter, nicht sich selbst
		mark = g:Mark()
		S.act(b, "party_kick", { userId = 3 })
		T.check(g:HasToast(b, "Nur der Party-Leiter", mark), "Ben darf nicht entfernen")
		S.act(a, "party_kick", { userId = 1 })
		T.check(g:HasToast(a, "selbst", mark), "Leiter entfernt sich nicht selbst")
		S.act(a, "party_kick", { userId = 99 })
		T.check(g:HasToast(a, "nicht in deiner Party", mark), "unbekanntes Mitglied")
		mark = g:Mark()
		S.act(a, "party_kick", { userId = 4 })
		T.eq(LS.PartyOf(d1), nil, "Dana entfernt")
		T.eq(#party.members, 3, "drei Mitglieder")
		local kicked = g:Notices(d1, "party", mark)
		T.check(#kicked >= 1 and kicked[1].event == "kicked", "Dana erhält kicked")
		T.check(g:HasToast(d1, "entfernt", mark), "Toast entfernt")
		T.eq(S.snapshot(d1).party, false, "Danas Snapshot ohne Party")
		-- nur der Leiter reist; Mitglieder reisen mit (Simulation)
		mark = g:Mark()
		S.act(b, "lobby_mode", { mode = "tycoon" })
		S.act(b, "lobby_go")
		T.eq(msB.p.mode, "lobby", "Ben reist nicht allein")
		T.check(g:HasToast(b, "Party-Leiter", mark), "Toast nur Leiter")
		mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		S.act(a, "lobby_go")
		T.eq(msA.p.mode, "tycoon", "Anna im Tycoon")
		T.eq(msB.p.mode, "tycoon", "Ben mitgereist")
		T.eq(msC.p.mode, "tycoon", "Cem mitgereist")
		T.eq(msD.p.mode, "lobby", "Dana (entfernt) bleibt")
		near(T, rootPos(g, b), HUB.tycoon[1], HUB.tycoon[2], 6, "Ben an der Tycoon-Ankunft")
		local travel = g:Notices(b, "party", mark)
		T.check(#travel >= 1 and travel[#travel].event == "travel" and travel[#travel].mode == "tycoon", "Ben erhält travel")
		T.eq(#g:Notices(b, "mode", mark), 1, "Ben erhält mode-Hinweis")
		T.eq(#g:Notices(a, "party", mark), 0, "Leiter bekommt keinen travel-Hinweis")
		-- Leiter verlässt den Server: Ben wird Leiter
		mark = g:Mark()
		S.leave(a)
		T.eq(party.leader, b, "Ben ist neuer Leiter")
		T.eq(#party.members, 2, "zwei Mitglieder")
		local ev = g:Notices(c, "party", mark)
		local sawLeft, sawLeader = false, false
		for _, n in ipairs(ev) do
			if n.event == "left" and n.userId == 1 then
				sawLeft = true
			elseif n.event == "leader" and n.userId == 2 then
				sawLeader = true
			end
		end
		T.check(sawLeft and sawLeader, "Cem sieht left + leader")
		T.eq(S.snapshot(c).party.leader, 2, "Snapshot neuer Leiter")
		-- Mitglied verlässt die Party; letzter verlässt -> Party weg, Code frei
		mark = g:Mark()
		S.act(c, "party_leave")
		T.eq(LS.PartyOf(c), nil, "Cem draußen")
		T.check(g:HasToast(c, "verlassen", mark), "Toast verlassen")
		S.act(c, "party_leave")
		T.check(g:HasToast(c, "keiner Party", mark), "keine Party mehr")
		S.act(b, "party_leave")
		T.eq(LS.Parties[code], nil, "Party aufgelöst")
		mark = g:Mark()
		g:Advance(GC.Party.JoinCooldown + 0.1)
		S.act(e, "party_join", { code = code })
		T.check(g:HasToast(e, "gibt es hier nicht", mark), "alter Code ungültig")
		-- Party-Code aus TeleportData: Leiter legt neu an, Mitglied tritt bei
		local f, msF = S.join(6, "Finn", { TeleportData = { mode = "tycoon", party = "KLMN" } })
		T.check(LS.Parties.KLMN ~= nil and LS.Parties.KLMN.leader == f, "Finn legt Party KLMN neu an")
		local h, msH = S.join(8, "Hana", { TeleportData = { mode = "tycoon", party = "klmn" } })
		T.eq(LS.PartyOf(h), LS.Parties.KLMN, "Hana tritt KLMN bei")
		T.eq(#g:Errors(), 0, "keine Fehler: " .. g:ErrorText())
	end },

	{ "Teleport: TeleportAsync mit Place-Id, TeleportData und Party; Einzelspieler reserviert; Fehler -> Simulation", function(T, H)
		local S = setup(H)
		local g, LS, PR = S.g, S.LS, S.PR
		local GC = g:MiniShared("GameConfig")
		local a, msA, dA = S.join(1, "Anna")
		local b, msB = S.join(2, "Ben")
		local c = S.join(3, "Cem")
		-- Party: Anna + Ben
		S.act(a, "party_create")
		local code = LS.PartyOf(a).code
		S.act(b, "party_join", { code = code })
		-- Place-Ids setzen (Modul-Tabelle patchen), kein Studio, game.PlaceId 0
		GC.Places.tycoon = 12345
		GC.Places.openworld = 23456
		GC.Places.lobby = 34567
		T.eq(PR.WouldTeleport("tycoon"), true, "Teleport erwartet")
		T.eq(S.snapshot(a).simulated, false, "Snapshot: nicht simuliert")
		local mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		S.act(a, "lobby_go")
		local calls = S.teleports()
		T.eq(#calls, 1, "ein TeleportService-Aufruf")
		local call = calls[1] or {}
		T.eq(call.method, "TeleportAsync", "TeleportAsync")
		T.eq(call.placeId, 12345, "Place-Id tycoon")
		T.eq(#(call.players or {}), 2, "Party reist gemeinsam")
		T.check(call.players and call.players[1] == a and call.players[2] == b, "Leiter zuerst, dann Mitglied")
		T.eq(call.teleportData and call.teleportData.mode, "tycoon", "TeleportData.mode")
		T.eq(call.teleportData and call.teleportData.single, false, "TeleportData.single")
		T.eq(call.teleportData and call.teleportData.party, code, "TeleportData.party")
		T.eq(call.code, "", "kein reservierter Server (Party)")
		T.eq(msA.p.mode, "lobby", "kein lokaler Moduswechsel bei echtem Teleport")
		T.eq(dA.games.meta.lastMode, "tycoon", "lastMode für das Ziel gemerkt")
		T.eq(#g:Notices(a, "mode", mark), 0, "kein Simulations-Hinweis")
		-- Einzelspieler: ReserveServer + Zugangscode
		S.act(c, "lobby_settings", { single = true, passive = false, beginner = true })
		S.act(c, "lobby_mode", { mode = "openworld" })
		S.act(c, "lobby_go")
		calls = S.teleports()
		T.eq(#calls, 3, "ReserveServer + TeleportAsync")
		T.eq(calls[2] and calls[2].method, "ReserveServer", "ReserveServer zuerst")
		T.eq(calls[2] and calls[2].placeId, 23456, "ReserveServer für openworld")
		T.eq(calls[3] and calls[3].method, "TeleportAsync", "dann TeleportAsync")
		T.eq(calls[3] and calls[3].code, calls[2] and calls[2].code, "ReservedServerAccessCode aus ReserveServer")
		T.eq(calls[3] and calls[3].teleportData.single, true, "TeleportData.single true")
		T.eq(calls[3] and calls[3].teleportData.party, "", "ohne Party leerer Code")
		T.eq(#(calls[3] and calls[3].players or {}), 1, "allein")
		-- gleicher Place: Simulation statt Teleport
		g.env.game.PlaceId = 12345
		T.eq(PR.WouldTeleport("tycoon"), false, "Ziel im selben Place")
		mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		S.act(a, "lobby_go")
		T.eq(#S.teleports(), 3, "kein weiterer Teleport")
		T.eq(msA.p.mode, "tycoon", "lokal gewechselt")
		T.eq(msB.p.mode, "tycoon", "Ben lokal mitgereist")
		T.eq(#g:Notices(a, "mode", mark), 1, "Simulations-Hinweis")
		g.env.game.PlaceId = 0
		-- Studio: nie Teleport
		g.env.studio = true
		T.eq(PR.WouldTeleport("lobby"), false, "Studio simuliert")
		g.env.studio = false
		-- Fehler: TeleportAsync wirft -> Toast + Simulation
		g.env.teleportFails = true
		mark = g:Mark()
		S.act(a, "lobby_return")
		T.eq(#S.teleports(), 4, "Teleport versucht")
		T.eq(msA.p.mode, "lobby", "nach Fehler lokal in der Lobby")
		T.eq(msB.p.mode, "lobby", "Ben nach Fehler lokal in der Lobby")
		near(T, rootPos(g, a), 0, -668, 6, "Anna an der Lobby-Ankunft")
		T.check(g:HasToast(a, "nicht geklappt", mark), "Toast Teleport-Fehler")
		T.eq(#g:Notices(a, "mode", mark), 1, "Simulations-Hinweis nach Fehler")
		T.check(#g:Warnings() > 0, "Fehler protokolliert (warn)")
		-- Fehler beim ReserveServer (Einzelspieler)
		mark = g:Mark()
		S.act(c, "lobby_mode", { mode = "tycoon" })
		S.act(c, "lobby_go")
		local last = S.teleports()[#S.teleports()]
		T.eq(last and last.method, "ReserveServer", "ReserveServer versucht")
		T.eq(last and last.failed, true, "ReserveServer fehlgeschlagen")
		T.eq(g:MiniState(c).p.mode, "tycoon", "Cem lokal im Tycoon")
		g.env.teleportFails = nil
		-- Asynchroner Fehler: TeleportAsync gelingt, danach feuert TeleportService.TeleportInitFailed je Spieler
		-- (GameFull, Flooded, Failure …) -> Toast + Simulation, lastMode stimmt, Party-Mitglied ebenfalls
		S.act(a, "lobby_return")
		g.env.teleportFails = "signal"
		mark = g:Mark()
		local warnBefore = #g:Warnings()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		S.act(a, "lobby_go")
		g:Advance(0.5)
		T.eq(msA.p.mode, "tycoon", "nach TeleportInitFailed: simuliert (Anna)")
		T.eq(msB.p.mode, "tycoon", "nach TeleportInitFailed: simuliert (Ben, eigenes Ereignis)")
		T.eq(dA.games.meta.lastMode, "tycoon", "lastMode = Ziel der Simulation")
		near(T, rootPos(g, a), HUB.tycoon[1], HUB.tycoon[2], 6, "Anna an der Tycoon-Ankunft")
		T.check(g:HasToast(a, "nicht geklappt", mark), "Toast Teleport-Fehler (Anna)")
		T.check(g:HasToast(b, "nicht geklappt", mark), "Toast Teleport-Fehler (Ben)")
		T.eq(#g:Notices(a, "mode", mark), 1, "Simulations-Hinweis (Anna)")
		T.eq(#g:Notices(b, "mode", mark), 1, "Simulations-Hinweis (Ben)")
		T.check(#g:Warnings() > warnBefore, "TeleportInitFailed protokolliert (warn)")
		T.eq(msA.lobbyChoice, nil, "Vorauswahl verbraucht")
		T.check(S.log.dirty > 0, "Snapshot als geändert markiert")
		-- fehlendes Ziel im Place: Modus bleibt, lastMode zurück auf den aktuellen Modus
		S.act(a, "lobby_return")
		g:Advance(0.5)
		T.eq(msA.p.mode, "lobby", "zurück in der Lobby")
		workspace:FindFirstChild("Tycoon"):Destroy()
		mark = g:Mark()
		S.act(a, "lobby_mode", { mode = "tycoon" })
		S.act(a, "lobby_go")
		g:Advance(0.5)
		T.eq(msA.p.mode, "lobby", "ohne Zone: Modus bleibt lobby")
		T.eq(dA.games.meta.lastMode, "lobby", "lastMode zurückgesetzt (Reise kam nicht zustande)")
		T.check(g:HasToast(a, "nicht geklappt", mark), "Toast Teleport-Fehler")
		g.env.teleportFails = nil
		-- TeleportOptions-Klasse im Mock
		local opts = Instance.new("TeleportOptions")
		T.eq(opts.ReservedServerAccessCode, "", "Standard leer")
		T.eq(opts.ShouldReserveServer, false, "Standard false")
		opts:SetTeleportData({ mode = "lobby" })
		T.eq(opts:GetTeleportData().mode, "lobby", "TeleportData rund")
		T.eq(#g:Errors(), 0, "keine Fehler: " .. g:ErrorText())
	end },

	{ "LobbyUI: Modus-Karten, Los geht's, Zurück, Einstellungs-Schalter, Party-Tafel – nur Absichten", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI, toasts = build(g, p, rec)
		local GC = g:MiniShared("GameConfig")
		-- Lobby, keine Auswahl, keine Party
		render(g, p, mod, snapshot("lobby"))
		T.check(withText(page, "Tycoon") ~= nil, "Karte Tycoon")
		T.check(withText(page, "Open World") ~= nil, "Karte Open World")
		T.check(withText(page, "Tycoon-Runde") ~= nil, "Beschreibung Tycoon")
		T.check(withText(page, "Werkstattmeile") ~= nil, "Beschreibung Open World")
		T.eq(byName(page, "ReturnButton").Visible, false, "in der Lobby kein Zurück")
		T.eq(byName(page, "Simulation").Visible, true, "Simulationshinweis sichtbar")
		T.check(byName(page, "Simulation").Text == GC.SimulationNotice, "Simulationstext aus GameConfig")
		T.eq(byName(page, "PartyCreate").Visible, true, "Party erstellen sichtbar")
		T.eq(byName(page, "PartyLeave").Visible, false, "Verlassen unsichtbar")
		local go = byName(page, "GoButton")
		T.check(enabled(go), "Los geht's aktiv (Standard Open World)")
		T.check(go.Text:find("Open World", 1, true) ~= nil, "Standardziel Open World: " .. go.Text)
		-- Modus wählen
		local tycoonCard = byName(page, "ModeCard_tycoon")
		T.check(tycoonCard ~= nil and tycoonCard.AbsoluteSize.Y >= 44, "Modus-Karte groß genug")
		press(g, tycoonCard)
		T.eq(rec.Count("lobby_mode"), 1, "lobby_mode gesendet")
		T.eq(rec.Last("lobby_mode").mode, "tycoon", "mode tycoon")
		T.check(go.Text:find("Tycoon", 1, true) ~= nil, "Ziel nach Auswahl: " .. go.Text)
		T.check(withText(page, "Ausgewählt") ~= nil, "Karte als ausgewählt markiert")
		render(g, p, mod, snapshot("lobby", { choice = "tycoon" }))
		T.check(go.Text:find("Tycoon", 1, true) ~= nil, "Server bestätigt Auswahl")
		press(g, go)
		T.eq(rec.Count("lobby_go"), 1, "lobby_go gesendet")
		T.eq(next(rec.Last("lobby_go")), nil, "lobby_go ohne Felder")
		-- Einstellungen: alle drei Booleans, nur der geschaltete kippt
		render(g, p, mod, snapshot("lobby", { meta = { beginner = true, passive = false, single = false, tutorialDone = false, tutorialStep = 1 } }))
		local tSingle = byName(page, "Toggle_single")
		T.eq(tSingle.Text, "Mehrspieler", "Schalter zeigt Mehrspieler")
		press(g, tSingle)
		local sent = rec.Last("lobby_settings")
		T.check(sent ~= nil, "lobby_settings gesendet")
		T.eq(sent and sent.single, true, "single gekippt")
		T.eq(sent and sent.passive, false, "passive bleibt")
		T.eq(sent and sent.beginner, true, "beginner bleibt")
		render(g, p, mod, snapshot("lobby", { meta = { beginner = true, passive = false, single = true, tutorialDone = false, tutorialStep = 1 } }))
		T.eq(tSingle.Text, "Einzelspieler", "Schalter zeigt Einzelspieler")
		press(g, byName(page, "Toggle_passive"))
		sent = rec.Last("lobby_settings")
		T.eq(sent and sent.passive, true, "passive gekippt")
		T.eq(sent and sent.single, true, "single bleibt an")
		press(g, byName(page, "Toggle_beginner"))
		sent = rec.Last("lobby_settings")
		T.eq(sent and sent.beginner, false, "beginner aus")
		T.check(withText(page, "Passiv-Modus") ~= nil and withText(page, "Beginner-Modus") ~= nil, "Erklärtexte da")
		-- Party: erstellen, Code eingeben, beitreten
		press(g, byName(page, "PartyCreate"))
		T.eq(rec.Count("party_create"), 1, "party_create gesendet")
		local box = byName(page, "PartyCodeBox")
		g:InClient(p, function()
			box.Text = " ab12 "
		end)
		press(g, byName(page, "PartyJoin"))
		T.eq(rec.Last("party_join") and rec.Last("party_join").code, "AB12", "party_join mit großgeschriebenem Code")
		g:InClient(p, function()
			box.Text = "ab"
		end)
		local before = rec.Count("party_join")
		press(g, byName(page, "PartyJoin"))
		T.eq(rec.Count("party_join"), before, "zu kurzer Code wird nicht gesendet")
		T.check(#toasts > 0 and toasts[#toasts]:find("Zeichen", 1, true) ~= nil, "Hinweis zum Codeformat")
		-- Party als Leiter: Mitglieder, Entfernen nur bei anderen, Verlassen
		render(g, p, mod, snapshot("lobby", {
			party = { code = "KLMN", leader = 1001, leaderName = "Tester", isLeader = true, max = 4, members = {
				{ userId = 1001, name = "Tester", leader = true }, { userId = 2, name = "Ben", leader = false },
			} },
		}))
		T.check(withText(page, "KLMN") ~= nil, "Code angezeigt")
		T.check(withText(page, "2/4") ~= nil, "Mitgliederzahl")
		T.check(withText(page, "Ben") ~= nil, "Mitglied Ben")
		T.eq(byName(page, "PartyCreate").Visible, false, "Erstellen weg")
		T.eq(byName(page, "PartyLeave").Visible, true, "Verlassen da")
		T.eq(byName(page, "Kick_1").Visible, false, "Leiter nicht entfernbar")
		T.eq(byName(page, "Kick_2").Visible, true, "Ben entfernbar")
		press(g, byName(page, "Kick_2"))
		T.eq(rec.Last("party_kick") and rec.Last("party_kick").userId, 2, "party_kick userId")
		press(g, byName(page, "PartyLeave"))
		T.eq(rec.Count("party_leave"), 1, "party_leave gesendet")
		-- Party als Mitglied: kein Entfernen, Los geht's gesperrt
		render(g, p, mod, snapshot("lobby", {
			party = { code = "KLMN", leader = 2, leaderName = "Ben", isLeader = false, max = 4, members = {
				{ userId = 2, name = "Ben", leader = true }, { userId = 1001, name = "Tester", leader = false },
			} },
		}))
		T.eq(byName(page, "Kick_1").Visible, false, "Mitglied entfernt niemanden")
		T.eq(byName(page, "Kick_2").Visible, false, "Mitglied entfernt niemanden (2)")
		T.check(not enabled(go), "Mitglied startet nicht")
		T.check(withText(page, "Party-Leiter startet") ~= nil, "Hinweis nur Leiter")
		-- außerhalb der Lobby: Zurück sichtbar, Los geht's zum anderen Modus
		render(g, p, mod, snapshot("tycoon", { simulated = false }))
		T.eq(byName(page, "ReturnButton").Visible, true, "Zurück zur Lobby sichtbar")
		T.eq(byName(page, "Simulation").Visible, false, "ohne Simulation kein Hinweis")
		T.check(withText(page, "Du bist hier") ~= nil, "aktueller Modus markiert")
		press(g, byName(page, "ReturnButton"))
		T.eq(rec.Count("lobby_return"), 1, "lobby_return gesendet")
		-- Hinweise
		g:InClient(p, function()
			mod.OnNotice({ kind = "mode", mode = "tycoon", simulated = true })
			mod.OnNotice({ kind = "party", event = "joined", name = "Ben" })
			mod.OnNotice({ kind = "party", event = "travel", name = "Ben", mode = "openworld" })
			mod.OnNotice({ kind = "lobby", action = "mode_openworld" })
		end)
		local sawSim, sawJoin, sawTravel = false, false, false
		for _, t in ipairs(toasts) do
			if t == GC.SimulationNotice then
				sawSim = true
			elseif t:find("beigetreten", 1, true) then
				sawJoin = true
			elseif t:find("Open World", 1, true) and t:find("reist", 1, true) then
				sawTravel = true
			end
		end
		T.check(sawSim, "Simulationshinweis als Toast")
		-- Tycoon mit Tycoon-Dienst (Meilenstein 4, GameConfig.Tycoon gefüllt): Karte ohne „Eröffnet bald“
		T.check(next(GC.Tycoon) ~= nil, "GameConfig.Tycoon gefüllt (Meilenstein 4)")
		T.check(withText(page, "Eröffnet bald") == nil, "Modus-Karte: kein „Eröffnet bald“ mehr")
		-- kicked-Ereignis: die übrigen erfahren es, der eigene Rauswurf kommt vom Server als Toast
		local nToasts = #toasts
		g:InClient(p, function()
			mod.OnNotice({ kind = "party", event = "kicked", name = "Ben", userId = 2 })
			mod.OnNotice({ kind = "party", event = "kicked", name = "Tester", userId = 1001 })
		end)
		T.eq(#toasts, nToasts + 1, "genau ein Toast (Ben entfernt, eigener Rauswurf nicht doppelt)")
		T.check(toasts[#toasts]:find("Ben", 1, true) and toasts[#toasts]:find("entfernt", 1, true), "Toast: Ben wurde entfernt")
		-- Tutorial-Abschnitt (Kiosk): Schritte, Neustart nur nach Ende/Überspringen, sendet tutorial_restart
		local restart = byName(page, "TutorialRestart")
		T.check(restart ~= nil and restart.AbsoluteSize.Y >= 44, "Knopf Tutorial erneut starten")
		T.check(byName(page, "TutorialSteps") ~= nil and byName(page, "TutorialSteps").Text:find("1. ", 1, true), "Schritt-Liste")
		render(g, p, mod, snapshot("lobby", { meta = { beginner = true, passive = false, single = false, tutorialDone = false, tutorialStep = 4 } }))
		T.check(not enabled(restart), "läuft: kein Neustart")
		T.check(withText(page, "Schritt 4 von") ~= nil, "Stand angezeigt")
		press(g, restart)
		T.eq(rec.Count("tutorial_restart"), 0, "gesperrt: nichts gesendet")
		render(g, p, mod, snapshot("lobby", { meta = { beginner = true, passive = false, single = false, tutorialDone = true, tutorialStep = 10 }, tutorial = { done = true, skipped = true, rewarded = false } }))
		T.check(enabled(restart), "übersprungen: Neustart möglich")
		T.check(withText(page, "übersprungen") ~= nil, "Status übersprungen")
		press(g, restart)
		T.eq(rec.Count("tutorial_restart"), 1, "tutorial_restart gesendet")
		T.eq(next(rec.Last("tutorial_restart")), nil, "ohne Felder")
		render(g, p, mod, snapshot("lobby", { meta = { beginner = true, passive = false, single = false, tutorialDone = true, tutorialStep = 10 }, tutorial = { done = true, skipped = false, rewarded = true } }))
		T.check(withText(page, "hattest du schon") ~= nil, "Hinweis: Belohnung hattest du schon")
		T.check(sawJoin and sawTravel, "Party-Hinweise als Toast")
		render(g, p, mod, snapshot("lobby"))
		T.check(go.Text:find("Open World", 1, true) ~= nil, "Portal-Station wählt Open World vor")
		-- keine Beträge, keine unerlaubten Felder (recorder prüft jede Sendung), keine Fehler
		T.eq(#g:Errors(), 0, "keine Client-Fehler: " .. g:ErrorText())
	end },

	{ "LobbyUI: Handy-Layout (390 px breit) ohne Überlauf, Knöpfe mindestens 44 px", function(T, H)
		local g, p = startClient(H, { viewport = Vector2.new(390, 844) })
		local rec = recorder(T)
		local mod, page = build(g, p, rec)
		render(g, p, mod, snapshot("lobby", {
			party = { code = "KLMN", leader = 1001, leaderName = "Tester", isLeader = true, max = 4, members = {
				{ userId = 1001, name = "Tester", leader = true }, { userId = 2, name = "Ben", leader = false },
			} },
		}))
		g:Advance(0.3)
		local width = page.AbsoluteSize.X
		local buttons, tooSmall, overflow = 0, 0, 0
		for _, x in ipairs(page:GetDescendants()) do
			if x:IsA("TextButton") and x.Visible then
				buttons += 1
				if x.AbsoluteSize.Y < 44 then
					tooSmall += 1
				end
			end
			if x:IsA("GuiObject") and x.Visible and x.AbsolutePosition.X + x.AbsoluteSize.X > page.AbsolutePosition.X + width + 1 then
				overflow += 1
			end
		end
		T.check(buttons >= 8, "Knöpfe gefunden: " .. buttons)
		T.eq(tooSmall, 0, "alle Knöpfe mindestens 44 px hoch")
		T.eq(overflow, 0, "kein Element ragt über die Seitenbreite hinaus")
		T.eq(#g:Errors(), 0, "keine Client-Fehler: " .. g:ErrorText())
	end },
}
