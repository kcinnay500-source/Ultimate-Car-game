-- Entwickler-Menü (DevService + DevUI): Berechtigung (Studio, Ersteller, AllowedUserIds; alle anderen bekommen nichts),
-- dev_open/dev_set mit Stub-api (Level/XP/Credits/Bargeld/Startweg, Deckel, ungültige Werte), Chat-Weg „/dev“
-- (Player.Chatted und TextChatCommand), echter Weg über Remotes.Command (falls verkabelt), DevUI (Anzeige, Knöpfe senden
-- die richtigen Absichten, Strg+Umschalt+D) und Treffertest an 390x844, 1280x650 und 1920x1080.
local NOW = 1760000000

local VIEWPORTS = { { 390, 844 }, { 1280, 650 }, { 1920, 1080 } }

local FORBIDDEN = { amount = true, cost = true, credits = true, reward = true, money = true, price = true, xp = true }

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

-- Server-Seite: DevService mit Stub-Actions/api; ms = eigene Stub-Sitzung mit dem echten Spieler und Profil
local function serverSetup(H, T, opts)
	opts = opts or {}
	local g = H.Garage({ placeKind = opts.placeKind or "openworld", startTime = NOW, studio = opts.studio })
	local p = g:Join(opts.userId or 1401, { name = "Entwickler" })
	g:Advance(0.5)
	local Dev = g:MiniServer("DevService")
	local S = { g = g, p = p, Dev = Dev, handlers = {}, notices = {}, toasts = {}, flags = { world = 0, dirty = 0 } }
	local Actions = {
		Register = function(name, fn)
			S.handlers[name] = fn
		end,
	}
	local t = 1000
	S.api = {
		now = function()
			return t
		end,
		toast = function(_, text)
			table.insert(S.toasts, text)
		end,
		notice = function(_, kind, data)
			data = type(data) == "table" and data or {}
			data.kind = kind
			table.insert(S.notices, data)
		end,
		dirty = function()
			S.flags.dirty += 1
		end,
		worldChanged = function()
			S.flags.world += 1
		end,
	}
	function S.Tick(dt)
		t += dt
	end
	g:Activate()
	Dev.Register(Actions, S.api)
	Dev.Init({ now = S.api.now })
	S.d = g:D(p)
	S.ms = { p = { mode = opts.mode or "openworld", profile = { data = S.d } }, player = p }
	Dev.OnJoin(S.ms, S.d, t)
	function S.Set(field, value)
		g:Activate()
		return S.handlers.dev_set(S.ms, { field = field, value = value }, S.d, t)
	end
	function S.Open()
		g:Activate()
		return S.handlers.dev_open(S.ms, {}, S.d, t)
	end
	function S.LastNotice()
		return S.notices[#S.notices]
	end
	return S
end

local function find(root, name)
	if not root then
		return nil
	end
	for _, x in ipairs(root:GetDescendants()) do
		if x.Name == name then
			return x
		end
	end
	return nil
end

local function stateNotice(over)
	local s = {
		kind = "dev", event = "open", level = 12, xp = 34, xpNeeded = 400, credits = 12345, rank = 1, rankTitle = "Meisterschrauber I",
		mode = "openworld", inTycoon = false, hasRun = false, cash = 0, startPath = "werkstatt", startPending = false,
		maxLevel = 1000, maxCredits = 1e9, maxCash = 1e12, maxXP = 1e9, addCredits = 10000,
	}
	for k, v in pairs(over or {}) do
		s[k] = v
	end
	return s
end

-- Client-Seite: DevUI mit Recorder (eigener Listener am echten Remotes.Event)
local function clientSetup(H, T, vp)
	local g = H.Garage({ placeKind = "openworld", startTime = NOW, viewport = vp and H.Mock.Vector2.new(vp[1], vp[2]) or nil })
	local p = g:Join(1411, { name = "Klicker" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1)
	local rec = recorder(T)
	local S = { g = g, p = p, rec = rec, toasts = {} }
	S.UI = g:ClientModule(p, "Mini.DevUI")
	g:InClient(p, function()
		S.UI.Start({
			Remote = rec,
			Toast = function(text)
				table.insert(S.toasts, text)
			end,
		})
	end)
	g:Advance(0.3)
	S.gui = p.PlayerGui:FindFirstChild("DevMenu")
	S.Hit = H.Load("tests/lib/gui_hit.lua")
	function S.Fire(data)
		g:FireClient(p, "mini_notice", data)
		g:Advance(0.2)
	end
	function S.Click(obj, label)
		local ok = S.Hit.Click(T, g, p, obj, { label = label })
		g:Advance(0.2)
		return ok
	end
	function S.Type(boxName, text)
		local box = find(S.gui, boxName)
		g:InClient(p, function()
			box.Text = text
		end)
	end
	return S
end

return {
	{ "DevService: ohne Berechtigung (kein Studio, nicht Ersteller) – Öffnen, Setzen und Chat tun nichts, kein Hinweis", function(T, H)
		local S = serverSetup(H, T, { studio = false })
		local g, p, Dev = S.g, S.p, S.Dev
		T.check(type(S.handlers.dev_open) == "function" and type(S.handlers.dev_set) == "function", "dev_open/dev_set registriert")
		T.eq(Dev.IsDev(p), false, "kein Entwickler")
		local level, money, xp = S.d.level, S.d.money, S.d.xp
		S.Open()
		S.Set("level", 50)
		S.Set("credits", 999999)
		S.Set("xp", 5000)
		S.Set("start_reset", 0)
		S.Set("cash", 5)
		T.eq(S.d.level, level, "Level unverändert")
		T.eq(S.d.money, money, "Credits unverändert")
		T.eq(S.d.xp, xp, "XP unverändert")
		T.eq(#S.notices, 0, "kein Hinweis")
		T.eq(#S.toasts, 0, "kein Toast (kein Hinweis, dass es das Menü gibt)")
		T.eq(S.flags.world + S.flags.dirty, 0, "nichts als geändert markiert")
		-- Chat „/dev“
		g:Activate()
		p.Chatted:Fire("/dev")
		g:Advance(0.2)
		T.eq(#S.notices, 0, "Chat „/dev“ öffnet nichts")
		T.eq(Dev.OpenFor(p), false, "OpenFor verweigert")
		Dev._OnCommand({ UserId = p.UserId })
		T.eq(#S.notices, 0, "TextChatCommand öffnet nichts")
		-- Gruppenspiel ohne erreichbaren GroupService: kein Fehler, keine Berechtigung
		g.env.game.CreatorType = Enum.CreatorType.Group
		g.env.game.CreatorId = 4242
		T.eq(Dev.IsDev(p), false, "Gruppenspiel: nicht der Besitzer")
		g:Advance(0.5)
		T.eq(Dev.IsDev(p), false, "Gruppenspiel nach dem Nachschlagen: weiterhin nicht")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "DevService: Ersteller und AllowedUserIds sind Entwickler, auch ohne Studio", function(T, H)
		local S = serverSetup(H, T, { studio = false, userId = 1402 })
		local g, p, Dev = S.g, S.p, S.Dev
		T.eq(Dev.IsDev(p), false, "anfangs nicht")
		g.env.game.CreatorType = Enum.CreatorType.User
		g.env.game.CreatorId = 1402
		T.eq(Dev.IsDev(p), true, "Ersteller (CreatorType User) ist Entwickler")
		S.Open()
		T.eq(#S.notices, 1, "Ersteller: Menü öffnet")
		g.env.game.CreatorId = 99
		T.eq(Dev.IsDev(p), false, "anderer Ersteller: nicht mehr")
		local GameConfig = g:MiniShared("GameConfig")
		T.check(type(GameConfig.Dev) == "table" and type(GameConfig.Dev.AllowedUserIds) == "table", "GameConfig.Dev.AllowedUserIds vorhanden")
		T.eq(#GameConfig.Dev.AllowedUserIds, 0, "Liste ist ab Werk leer")
		table.insert(GameConfig.Dev.AllowedUserIds, 1402)
		T.eq(Dev.IsDev(p), true, "UserId in AllowedUserIds ist Entwickler")
		table.remove(GameConfig.Dev.AllowedUserIds)
		T.eq(Dev.IsDev(p), false, "wieder entfernt")
		T.eq(Dev.IsDev(nil), false, "nil ist kein Entwickler")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "DevService (Studio): Öffnen liefert Werte; Level/XP/Credits setzen mit Deckeln, ungültige Werte abgelehnt", function(T, H)
		local S = serverSetup(H, T, { studio = true })
		local g, Dev, d = S.g, S.Dev, S.d
		local GameConfig = g:MiniShared("GameConfig")
		local R = g:Rules()
		T.eq(Dev.IsDev(S.p), true, "Studio: Entwickler")
		S.Open()
		local n = S.LastNotice()
		T.check(n ~= nil and n.kind == "dev" and n.event == "open", "Hinweis dev/open")
		T.eq(n.level, d.level, "Level im Hinweis")
		T.eq(n.credits, d.money, "Credits im Hinweis")
		T.eq(n.inTycoon, false, "nicht im Tycoon")
		T.eq(n.maxLevel, Dev.MaxLevel(), "max. Level")
		T.check(n.maxLevel >= GameConfig.UnlockLevels[#GameConfig.UnlockLevels], "max. Level deckt alle Freischaltungen ab")
		-- Level
		S.Set("level", 30)
		T.eq(d.level, 30, "Level 30")
		T.eq(d.xp, 0, "XP 0 nach Level setzen")
		T.check(S.flags.world >= 1 and S.flags.dirty >= 1, "worldChanged + dirty (2.4.0-Zustand und Snapshot)")
		T.eq(S.LastNotice().event, "update", "Hinweis dev/update")
		T.eq(S.LastNotice().level, 30, "neue Werte im Hinweis")
		T.check(string.find(S.toasts[#S.toasts], "Level", 1, true) ~= nil, "deutscher Toast")
		S.Set("level", 10 ^ 9)
		T.eq(d.level, Dev.MaxLevel(), "Level gedeckelt")
		S.Set("level", -5)
		T.eq(d.level, 1, "Level mindestens 1")
		S.Set("level", 7.9)
		T.eq(d.level, 7, "Level ganzzahlig")
		-- XP
		S.Set("xp", 25)
		T.eq(d.level, 7, "XP unter der Schwelle: Level bleibt")
		T.eq(d.xp, 25, "XP 25")
		local need = R.XPNeeded(d)
		local before = d.money
		S.Set("xp", need + 3)
		T.eq(d.level, 8, "XP über der Schwelle: ein Aufstieg")
		T.eq(d.xp, 3, "Rest-XP")
		T.check(d.money > before, "Level-Bonus wie bei einem normalen Aufstieg")
		S.Set("xp", -10)
		T.eq(d.xp, 0, "XP mindestens 0")
		-- Credits
		S.Set("credits", 5000)
		T.eq(d.money, 5000, "Credits 5000")
		S.Set("credits", 5e12)
		T.eq(d.money, GameConfig.Dev.MaxCredits, "Credits gedeckelt")
		S.Set("credits", -1)
		T.eq(d.money, 0, "Credits mindestens 0")
		S.Set("credits_add", 10000)
		T.eq(d.money, 10000, "+10.000 Credits")
		S.Set("credits_add", -500)
		T.eq(d.money, 10000, "negatives Plus ändert nichts")
		-- ungültig
		local level, money = d.level, d.money
		local toasts = #S.toasts
		S.Set("money", 5)
		S.Set("level", 0 / 0)
		S.Set("credits", math.huge)
		S.Set("level", "12")
		S.g:Activate()
		S.handlers.dev_set(S.ms, {}, d, 1000)
		S.handlers.dev_set(S.ms, nil, d, 1000)
		T.eq(d.level, level, "Level nach ungültigen Werten unverändert")
		T.eq(d.money, money, "Credits nach ungültigen Werten unverändert")
		T.eq(#S.toasts, toasts + 6, "je ein Toast für ungültige Werte")
		T.eq(S.toasts[#S.toasts], Dev.Text.invalid, "Toast: ungültiger Wert")
		-- Bargeld außerhalb des Tycoon: abgelehnt
		S.Set("cash", 100)
		T.eq(S.toasts[#S.toasts], Dev.Text.onlyTycoon, "Bargeld nur im Tycoon")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "DevService (Studio): Bargeld im Tycoon, Freischalt-Karten (wenige einzeln, viele gesammelt), Startweg zurücksetzen", function(T, H)
		local S = serverSetup(H, T, { studio = true, mode = "tycoon", placeKind = "tycoon" })
		local g, Dev, d = S.g, S.Dev, S.d
		local TycoonRules = g:MiniShared("TycoonRules")
		local MetaRules = g:MiniShared("MetaRules")
		local GameConfig = g:MiniShared("GameConfig")
		local Unlocks = g:MiniShared("Unlocks")
		S.Open()
		T.eq(S.LastNotice().inTycoon, true, "im Tycoon")
		T.eq(S.LastNotice().hasRun, false, "noch kein Durchlauf")
		S.Set("cash", 500)
		T.eq(S.toasts[#S.toasts], Dev.Text.noRun, "ohne Durchlauf: Hinweis")
		g:Activate()
		if type(d.games.tycoon.run) ~= "table" then
			TycoonRules.NewRun(d, "werkstatt", NOW)
		end
		local run = TycoonRules.RunOf(d)
		T.check(run ~= nil, "Durchlauf angelegt")
		S.Set("cash", 123456)
		T.eq(run.cash, 123456, "Bargeld gesetzt")
		T.eq(S.LastNotice().cash, 123456, "Bargeld im Hinweis")
		S.Set("cash", 1e20)
		T.eq(run.cash, GameConfig.Dev.MaxCash, "Bargeld gedeckelt")
		S.Set("cash", -3)
		T.eq(run.cash, 0, "Bargeld mindestens 0")
		-- Freischaltungen: wenige -> PrestigeService meldet sie (lastLevel bleibt), viele -> Sammel-Meldung
		S.Set("level", 1)
		S.ms.lastLevel = 1
		S.Set("level", 3)
		T.eq(S.ms.lastLevel, 1, "wenige Freischaltungen: PrestigeService.Tick meldet sie einzeln")
		S.Set("level", 1)
		S.ms.lastLevel = 1
		local count = #Unlocks.NewlyReached(1, 90)
		T.check(count > GameConfig.Dev.MaxUnlockCards, "Level 90 überspringt viele Freischaltungen (" .. count .. ")")
		S.Set("level", 90)
		T.eq(S.ms.lastLevel, 90, "viele Freischaltungen: keine Karten-Flut")
		T.eq(S.toasts[#S.toasts - 1], string.format(Dev.Text.unlocks, count), "Sammel-Meldung")
		-- Startweg zurücksetzen
		g:Activate()
		local m = d.games.meta
		m.startPath = "werkstatt"
		m.tutorialDone = true
		T.eq(MetaRules.StartPending(d), false, "Weg gewählt")
		S.ms.p.mode = "openworld"
		S.Set("start_reset", 0)
		T.eq(MetaRules.StartPath(d), "", "Startweg geleert")
		T.eq(MetaRules.StartPending(d), true, "Startwahl wieder offen")
		T.eq(S.LastNotice().startPending, true, "Hinweis: Wahl offen")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "DevService: Chat „/dev“ (Player.Chatted) und TextChatCommand öffnen nur für Entwickler, einmal je Moment", function(T, H)
		local S = serverSetup(H, T, { studio = true })
		local g, p, Dev = S.g, S.p, S.Dev
		T.eq(Dev.IsCommand("/dev"), true, "/dev")
		T.eq(Dev.IsCommand("  /DEV  "), true, "Groß/Leerzeichen egal")
		T.eq(Dev.IsCommand("/devx"), false, "/devx nicht")
		T.eq(Dev.IsCommand("dev"), false, "ohne Schrägstrich nicht")
		T.eq(Dev.IsCommand(nil), false, "nil nicht")
		g:Activate()
		p.Chatted:Fire("hallo")
		g:Advance(0.1)
		T.eq(#S.notices, 0, "normale Nachricht öffnet nichts")
		p.Chatted:Fire("/dev")
		g:Advance(0.1)
		T.eq(#S.notices, 1, "Chat „/dev“ öffnet")
		T.eq(S.notices[1].event, "open", "event open")
		-- Chatted und TextChatCommand im selben Moment: nur einmal
		Dev._OnCommand({ UserId = p.UserId })
		T.eq(#S.notices, 1, "zweiter Befehl im selben Moment entfällt")
		S.Tick(1)
		Dev._OnCommand({ UserId = p.UserId })
		T.eq(#S.notices, 2, "TextChatCommand öffnet (Spieler über UserId)")
		Dev._OnCommand({ UserId = 987654 })
		Dev._OnCommand({})
		T.eq(#S.notices, 2, "unbekannte UserId: nichts")
		-- TextChatCommand angelegt (falls die Umgebung die Klasse kennt)
		local tcs = g.env.game:GetService("TextChatService")
		local folder = tcs:FindFirstChild("TextChatCommands")
		local cmd = folder and folder:FindFirstChild(Dev.CommandName)
		if cmd then
			T.eq(cmd.PrimaryAlias, "/dev", "PrimaryAlias /dev")
		else
			T.check(true, "TextChatCommand in dieser Umgebung nicht verfügbar (Player.Chatted reicht)")
		end
		-- Verlassen: Verbindung gelöst
		Dev.OnLeave(S.ms)
		S.Tick(1)
		p.Chatted:Fire("/dev")
		g:Advance(0.1)
		T.eq(#S.notices, 2, "nach OnLeave öffnet der Chat nichts mehr")
		T.eq(Dev.Sessions[p], nil, "Sitzung vergessen")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "Entwickler-Menü end-to-end (falls verkabelt): dev_open/dev_set über Remotes.Command, 2.4.0-Zustand, Nicht-Entwickler", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW, studio = true })
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.Actions.dev_set or not MiniNet.Actions.dev_open then
			T.check(true, "dev_open/dev_set noch nicht in MiniNet.Actions (Integrator verkabelt) – übersprungen")
			g:Close()
			return
		end
		local p = g:Join(1421, { name = "Dev" })
		g:Advance(1)
		local m = g:Mark()
		T.eq(g:Act(p, "dev_open", { rid = 1 }), "ok", "dev_open angenommen")
		local open = g:Notices(p, "dev", m)
		T.check(#open >= 1 and open[#open].event == "open", "Menü öffnet (mini_notice dev)")
		m = g:Mark()
		T.eq(g:Act(p, "dev_set", { field = "level", value = 25, rid = 2 }), "ok", "dev_set angenommen")
		T.eq(g:D(p).level, 25, "Level 25 im Profil")
		g:Advance(1)
		local st = g:State(p)
		T.check(st ~= nil and st.data ~= nil and st.data.level == 25, "2.4.0-Zustand zeigt Level 25")
		T.check(#g:Notices(p, "unlock", m) >= 1 or #g:Toasts(p, m) >= 1, "Freischaltungen gemeldet")
		g:Advance(1)
		T.eq(g:Act(p, "dev_set", { field = "credits", value = 777777, rid = 3 }), "ok", "Credits setzen")
		T.eq(g:D(p).money, 777777, "Credits im Profil")
		g:Advance(1)
		T.eq(g:State(p).data.money, 777777, "2.4.0-Zustand zeigt die Credits")
		-- echter Client (GarageClient -> MiniClient -> DevUI): Strg+Umschalt+D öffnet das Menü über den Server
		g:StartClient(p)
		g:Advance(2)
		local gui = p.PlayerGui:FindFirstChild("DevMenu")
		if gui then
			g:Key(p, Enum.KeyCode.LeftControl, "Begin")
			g:Key(p, Enum.KeyCode.LeftShift, "Begin")
			g:Key(p, Enum.KeyCode.D)
			g:Key(p, Enum.KeyCode.LeftShift, "End")
			g:Key(p, Enum.KeyCode.LeftControl, "End")
			g:Advance(1)
			T.eq(gui.Enabled, true, "echter Client: Strg+Umschalt+D öffnet das Entwickler-Menü")
			local info = gui:FindFirstChild("Info_Credits", true)
			T.check(info ~= nil and string.find(info.Text, "777.777", 1, true) ~= nil, "echter Client: Credits angezeigt")
		else
			T.check(true, "DevUI noch nicht in MiniClient gestartet (Integrator verkabelt) – Client-Teil übersprungen")
		end
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
		-- ohne Studio: nichts
		local g2 = H.Garage({ placeKind = "openworld", startTime = NOW, studio = false })
		local p2 = g2:Join(1422, { name = "Gast" })
		g2:Advance(1)
		local level = g2:D(p2).level
		local m2 = g2:Mark()
		g2:Act(p2, "dev_open", { rid = 1 })
		g2:Act(p2, "dev_set", { field = "level", value = 50, rid = 2 })
		T.eq(#g2:Notices(p2, "dev", m2), 0, "Nicht-Entwickler: kein Menü")
		T.eq(g2:D(p2).level, level, "Nicht-Entwickler: Level unverändert")
		g2:Close()
	end },

	{ "DevUI: ScreenGui DevMenu (45), öffnet auf mini_notice dev, Knöpfe senden dev_set, Bargeld nur im Tycoon, Strg+Umschalt+D", function(T, H)
		local S = clientSetup(H, T)
		local g, p, rec = S.g, S.p, S.rec
		T.check(S.gui ~= nil, "ScreenGui DevMenu angelegt")
		T.eq(S.gui.DisplayOrder, 45, "DisplayOrder 45")
		T.eq(S.gui.ResetOnSpawn, false, "ResetOnSpawn aus")
		T.eq(S.gui.Enabled, false, "anfangs zu")
		-- fremder Hinweis öffnet nichts
		S.Fire({ kind = "story", event = "open" })
		T.eq(S.gui.Enabled, false, "anderer Hinweis: zu")
		S.Fire(stateNotice())
		T.eq(S.gui.Enabled, true, "dev/open öffnet")
		T.eq(S.UI.IsOpen(), true, "IsOpen")
		T.eq(find(S.gui, "Title").Text, "Entwickler-Menü", "Titel")
		T.check(string.find(find(S.gui, "Info_Level").Text, "12", 1, true) ~= nil, "Level angezeigt")
		T.check(string.find(find(S.gui, "Info_Credits").Text, "12.345", 1, true) ~= nil, "Credits angezeigt (12.345)")
		T.check(string.find(find(S.gui, "Info_Rank").Text, "Meisterschrauber", 1, true) ~= nil, "Prestige-Rang angezeigt")
		T.check(string.find(find(S.gui, "Info_XP").Text, "34 / 400", 1, true) ~= nil, "XP angezeigt")
		T.eq(find(S.gui, "LevelBox").Text, "12", "Feld Level vorbelegt")
		T.eq(S.Hit.Visible(find(S.gui, "Row_Cash")), false, "Bargeld nur im Tycoon")
		-- Knöpfe
		S.Type("LevelBox", "30")
		S.Click(find(S.gui, "SetLevel"), "Level setzen")
		T.eq(rec.Last("dev_set").field, "level", "Level setzen -> field level")
		T.eq(rec.Last("dev_set").value, 30, "Wert 30")
		S.Type("XPBox", "250")
		S.Click(find(S.gui, "SetXP"), "XP setzen")
		T.eq(rec.Last("dev_set").field, "xp", "XP setzen")
		T.eq(rec.Last("dev_set").value, 250, "Wert 250")
		S.Type("CreditsBox", "1.000.000")
		S.Click(find(S.gui, "SetCredits"), "Credits setzen")
		T.eq(rec.Last("dev_set").field, "credits", "Credits setzen")
		T.eq(rec.Last("dev_set").value, 1000000, "1.000.000 gelesen")
		S.Click(find(S.gui, "AddCredits"), "+10.000 Credits")
		T.eq(rec.Last("dev_set").field, "credits_add", "+10.000 Credits")
		T.eq(rec.Last("dev_set").value, 10000, "Wert 10000")
		T.check(string.find(find(S.gui, "AddCredits").Text, "10.000", 1, true) ~= nil, "Knopftext +10.000 Credits")
		local sent = rec.Count("dev_set")
		S.Type("LevelBox", "abc")
		S.Click(find(S.gui, "SetLevel"), "Level setzen (ungültig)")
		T.eq(rec.Count("dev_set"), sent, "ungültige Eingabe sendet nichts")
		T.check(#S.toasts >= 1, "Hinweis bei ungültiger Eingabe")
		S.Click(find(S.gui, "ResetStart"), "Startweg zurücksetzen")
		T.eq(rec.Last("dev_set").field, "start_reset", "Startweg zurücksetzen")
		-- Tycoon: Bargeld-Zeile
		S.Fire(stateNotice({ event = "update", inTycoon = true, hasRun = true, cash = 4321, mode = "tycoon" }))
		T.eq(S.Hit.Visible(find(S.gui, "Row_Cash")), true, "Bargeld-Zeile im Tycoon")
		T.check(string.find(find(S.gui, "Info_Cash").Text, "4.321", 1, true) ~= nil, "Bargeld angezeigt")
		T.eq(find(S.gui, "CashBox").Text, "4321", "Bargeld-Feld vorbelegt")
		S.Type("CashBox", "99999")
		S.Click(find(S.gui, "SetCash"), "Bargeld setzen")
		T.eq(rec.Last("dev_set").field, "cash", "Bargeld setzen")
		T.eq(rec.Last("dev_set").value, 99999, "Wert 99999")
		-- Schließen
		S.Click(find(S.gui, "Close"), "Schließen")
		T.eq(S.gui.Enabled, false, "Schließen schließt")
		S.Fire(stateNotice({ event = "update" }))
		T.eq(S.gui.Enabled, false, "update öffnet nicht")
		-- Tastenkombination
		local opens = rec.Count("dev_open")
		g:Key(p, Enum.KeyCode.D)
		T.eq(rec.Count("dev_open"), opens, "D allein: nichts")
		g:Key(p, Enum.KeyCode.LeftControl, "Begin")
		g:Key(p, Enum.KeyCode.D)
		T.eq(rec.Count("dev_open"), opens, "Strg+D: nichts")
		g:Key(p, Enum.KeyCode.LeftShift, "Begin")
		g:Key(p, Enum.KeyCode.D)
		T.eq(rec.Count("dev_open"), opens + 1, "Strg+Umschalt+D sendet dev_open")
		g:Key(p, Enum.KeyCode.D)
		T.eq(rec.Count("dev_open"), opens + 1, "Abklingzeit")
		g:Key(p, Enum.KeyCode.LeftShift, "End")
		g:Key(p, Enum.KeyCode.LeftControl, "End")
		-- Kreuz oben schließt ebenfalls
		S.Fire(stateNotice())
		T.eq(S.gui.Enabled, true, "wieder offen")
		S.Click(find(S.gui, "CloseX"), "×")
		T.eq(S.gui.Enabled, false, "× schließt")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },

	{ "DevUI: Treffertest an 390x844, 1280x650 und 1920x1080 – Tafel im Bild, alle Knöpfe und Felder treffbar", function(T, H)
		for _, vp in ipairs(VIEWPORTS) do
			local tag = string.format("[%dx%d] ", vp[1], vp[2])
			local S = clientSetup(H, T, vp)
			local p = S.p
			S.Fire(stateNotice({ inTycoon = true, hasRun = true, cash = 50, mode = "tycoon" }))
			T.eq(S.gui.Enabled, true, tag .. "offen")
			local panel = find(S.gui, "Panel")
			local x, y, w, h = S.Hit.Rect(p, panel)
			T.check(x >= 0 and y >= S.Hit.Inset and x + w <= vp[1] + 0.5 and y + h <= vp[2] + 0.5, tag .. string.format("Tafel im Bild (%d,%d %dx%d)", x, y, w, h))
			for _, name in ipairs({ "CloseX", "LevelBox", "SetLevel", "XPBox", "SetXP", "CreditsBox", "SetCredits", "AddCredits", "CashBox", "SetCash", "ResetStart", "Close" }) do
				local obj = find(S.gui, name)
				if T.check(obj ~= nil, tag .. name .. " vorhanden") then
					S.Hit.ScrollIntoView(p, obj)
					local cx, cy = S.Hit.Center(p, obj)
					T.eq(S.Hit.At(p, cx, cy), obj, tag .. name .. " treffbar")
					local _, _, rw, rh = S.Hit.Rect(p, obj)
					T.check(rh >= 44 - 0.01, tag .. name .. " ≥ 44 px hoch (" .. string.format("%.0f", rh) .. ")")
					T.check(rw >= 44 - 0.01, tag .. name .. " breit genug (" .. string.format("%.0f", rw) .. ")")
				end
			end
			S.Hit.ScrollIntoView(p, find(S.gui, "SetLevel"))
			S.Type("LevelBox", "5")
			S.Click(find(S.gui, "SetLevel"), tag .. "Level setzen")
			T.eq(S.rec.Last("dev_set") and S.rec.Last("dev_set").value, 5, tag .. "Klick sendet dev_set")
			T.eq(S.g:ErrorText(), "", tag .. "keine Fehler")
			S.g:Close()
		end
	end },
}
