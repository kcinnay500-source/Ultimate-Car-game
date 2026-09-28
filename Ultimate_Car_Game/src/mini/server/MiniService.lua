-- MiniService: bindet Minispiele und Stadt an GarageServer (ein Eingang, eine Sitzung, ein Profil).
-- GarageServer ruft (MERGE_CONTRACT §3):
--   Init(ctx)          nach dem Laden: ctx = { emit, toast, changed, push, getSession, moveTo, now }
--   Handles(action)    true für jede Aktion aus MiniNet.Actions
--   Handle(p, a, args) in request() vor act(): Budget, transacting-Sperre und Arg-Filter sind schon geprüft
--   Hello(p)           act 'hello'
--   OnJoin(p)          join() nach Profil und Plot
--   Tick(p, now)       0,5-s-Tick je Sitzung (auch während transacting: nur Schrott, nie Geld)
--   OnSettled(p)       nach erfolgreichem 'settle'
--   OnActivity(p)      nach erfolgreichem 'yard'
--   OnLeave(p, wasWritable)  PlayerRemoving / BindToClose, vor P.Save; blockiert nicht
--   OnSaved(p, saved)  nach P.Save(release): Bestenliste nur, wenn dieses letzte Speichern gelang
--   Pending()          laufende Bestenlisten-Schreibvorgänge (für BindToClose)
-- Geld (d.money) ändern Minispiele nur in Handle (also innerhalb von request()); danach ruft
-- MiniService ctx.changed(p) (höchstens 2×/s, dazwischen ctx.push und ein nachgeholtes changed im Tick).
-- Sonst wird nur der Minispiel-Snapshot als geändert markiert.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local MiniShared = Shared:WaitForChild("Mini")
local MiniConfig = require(MiniShared:WaitForChild("MiniConfig"))
local MiniNet = require(MiniShared:WaitForChild("MiniNet"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))
local MiniSnapshot = require(MiniShared:WaitForChild("MiniSnapshot"))
local PressRules = require(MiniShared:WaitForChild("PressRules"))
local SideGameRules = require(MiniShared:WaitForChild("SideGameRules"))

local Server = script.Parent
local PressService = require(Server:WaitForChild("PressService"))
local TuningService = require(Server:WaitForChild("TuningService"))
local SideGamesService = require(Server:WaitForChild("SideGamesService"))
local GoalsService = require(Server:WaitForChild("GoalsService"))
local LeaderboardService = require(Server:WaitForChild("LeaderboardService"))
local MiniPasses = require(Server:WaitForChild("MiniPasses"))
local CityService = require(Server:WaitForChild("CityService"))

local Mini = {}
Mini.Handlers = {}
Mini.Sessions = {} -- [Player] = Minispiel-Sitzung (ms)

local ctx = nil
local MAX_COOLDOWN_KEYS = 256
-- Spielraum für Zeitvergleiche: der Tick läuft alle 0,5 s, die Serverzeit ist eine große Gleitkommazahl.
-- Ohne ihn fiele "alle 1 s" durch Rundung (0,9999998 < 1) regelmäßig auf 1,5 s.
local EPSILON = 0.02

local function now()
	return ctx and ctx.now() or os.time()
end

---------------------------------------------------------------- Registrierung
local Actions = {}
function Actions.Register(name, handler)
	assert(MiniNet.Actions[name], "Aktion nicht in MiniNet.Actions: " .. tostring(name))
	assert(Mini.Handlers[name] == nil, "Aktion doppelt registriert: " .. name)
	Mini.Handlers[name] = handler
end

---------------------------------------------------------------- Sitzungszustand
local function newState(p)
	local t = now()
	return {
		p = p,
		player = p.player,
		userId = p.player.UserId,
		passes = { doubleScrap = false, pressPlus = false },
		rng = Random.new(),
		clickTokens = 0,
		clickAt = 0,
		recent = {},
		recentOrder = {},
		cooldowns = {},
		cooldownCount = 0,
		dirty = true,
		lastSent = 0,
		lastTickAt = t,
		quiz = SideGameRules.NewQuizState(),
		notices = {},
		greeted = false,
		boardSent = false,
		worldChanged = false,
		lastChanged = 0,
		changePending = false,
		leaderboardWrittenAt = 0,
		leaderboardWrittenCode = -1,
	}
end

local function stateFor(p)
	if not p or not p.player then
		return nil
	end
	local ms = Mini.Sessions[p.player]
	if not ms or ms.p ~= p then
		ms = newState(p)
		Mini.Sessions[p.player] = ms
	end
	return ms
end

local function alive(ms)
	return ms ~= nil and Mini.Sessions[ms.player] == ms and not ms.p.closing and ms.player.Parent ~= nil
end

local function emit(ms, kind, data)
	if ctx and ms.player.Parent then
		ctx.emit(ms.p, kind, data)
	end
end

---------------------------------------------------------------- Snapshot (höchstens 2×/s)
local function producing(d)
	return PressRules.MachinePower(d) > 0 or #d.games.tuning.projects > 0
end

local function sendSnapshot(ms, t)
	ms.dirty = false
	ms.lastSent = t
	local snap = MiniSnapshot.Build(ms.p.profile.data, t, ms.passes, ms.quiz)
	if type(snap.press) == "table" then
		snap.press.clickAcks = table.clone(ms.clickAcks or {}) -- bestätigte Klickpakete (PressUI-Vorhersage)
	end
	emit(ms, MiniNet.Events.Snapshot, snap)
end

-- Sendet, wenn sich etwas geändert hat (oder bei Produktion alle SnapshotIdleInterval), nie öfter als 2×/s.
local function flush(ms, t)
	if not ctx or not ms.player.Parent then
		return
	end
	local since = t - ms.lastSent + EPSILON
	if since < MiniConfig.SnapshotMinInterval then
		return
	end
	if ms.dirty or (since >= MiniConfig.SnapshotIdleInterval and producing(ms.p.profile.data)) then
		sendSnapshot(ms, t)
	end
end

local function notice(ms, kind, data)
	data = type(data) == "table" and data or {}
	data.kind = kind
	emit(ms, MiniNet.Events.Notice, data)
end

-- Hinweise vor dem ersten 'hello' (z. B. Offline-Ertrag) warten, bis der Client zuhört.
local function queueNotice(ms, kind, data)
	if ms.greeted then
		notice(ms, kind, data)
	else
		table.insert(ms.notices, { kind = kind, data = data })
	end
end

local function flushNotices(ms)
	ms.greeted = true
	local list = ms.notices
	ms.notices = {}
	for _, n in ipairs(list) do
		notice(ms, n.kind, n.data)
	end
end

local function pushBoard(ms)
	ms.boardSent = true
	notice(ms, "leaderboard", LeaderboardService.View(ms))
end

---------------------------------------------------------------- Schnittstelle für die Dienste
local api = {}
function api.now()
	return now()
end
function api.toast(ms, text)
	if ctx and type(text) == "string" and text ~= "" then
		ctx.toast(ms.p, text) -- 2.4.0-Format: reiner String
	end
end
function api.notice(ms, kind, data)
	notice(ms, kind, data)
end
function api.dirty(ms)
	ms.dirty = true
end
function api.worldChanged(ms)
	ms.worldChanged = true
end
function api.writable(ms)
	return ms.p.profile.writable == true
end
function api.alive(ms)
	return alive(ms)
end

---------------------------------------------------------------- Prüfung der Nutzlast
local function validPayload(schema, payload)
	if type(payload) ~= "table" then
		payload = {}
	end
	local clean = {}
	for field, kind in pairs(schema) do
		local v = payload[field]
		if type(v) ~= kind then
			return nil
		end
		if kind == "number" and (v ~= v or v == math.huge or v == -math.huge) then
			return nil
		end
		if kind == "string" and #v > 64 then
			return nil
		end
		clean[field] = v
	end
	-- Anfrage-ID gegen Doppelausführung (optional, vom Client je Nutzeraktion erzeugt)
	local rid = payload.rid
	if type(rid) == "number" and rid == rid and rid ~= math.huge and rid ~= -math.huge then
		clean.rid = math.floor(rid)
	end
	return clean
end

local function seen(ms, rid)
	if rid == nil then
		return false
	end
	if ms.recent[rid] then
		return true
	end
	ms.recent[rid] = true
	table.insert(ms.recentOrder, rid)
	while #ms.recentOrder > MiniConfig.RecentRequestIds do
		ms.recent[table.remove(ms.recentOrder, 1)] = nil
	end
	return false
end

-- Abklingzeit je Aktion und Ziel (z. B. je Parkplatz-Feld), statt 0,12 s je Aktionsname
local function cooledDown(ms, action, clean, t)
	local cd = MiniNet.Cooldowns[action] or MiniNet.DefaultCooldown
	if cd <= 0 then
		return true
	end
	local field = MiniNet.Targets[action]
	local key = field and (action .. ":" .. tostring(clean[field])) or action
	local last = ms.cooldowns[key]
	if last and t - last < cd then
		return false
	end
	if not last then
		ms.cooldownCount += 1
		if ms.cooldownCount > MAX_COOLDOWN_KEYS then
			ms.cooldowns = {}
			ms.cooldownCount = 1
		end
	end
	ms.cooldowns[key] = t
	return true
end

---------------------------------------------------------------- Öffentliche Schnittstelle
function Mini.Handles(action)
	return MiniNet.IsAction(action)
end

-- Rückgabe (für Tests): "ok" | "invalid" | "cooldown" | "duplicate" | "error" | "dropped"
function Mini.Handle(p, action, args)
	local schema, handler = MiniNet.Actions[action], Mini.Handlers[action]
	if not ctx or not schema or not handler then
		return "invalid"
	end
	if not p or p.closing or p.profile.transacting then
		return "dropped" -- request() sperrt schon; doppelte Sicherung für Geld während eines Robux-Kaufs
	end
	local ms = stateFor(p)
	local clean = validPayload(schema, args)
	if not clean then
		return "invalid"
	end
	local t = now()
	if not cooledDown(ms, action, clean, t) then
		return "cooldown"
	end
	if seen(ms, clean.rid) then
		if action == "mini_press_click" then
			-- wiederholtes Klickpaket: schon gezählt, nur erneut bestätigen
			PressService.Ack(ms, clean.rid)
			ms.dirty = true
			flush(ms, t)
		end
		return "duplicate"
	end
	local d = p.profile.data
	local money = d.money
	ms.worldChanged = false
	local ok, err = pcall(handler, ms, clean, d, t)
	if not ok then
		warn("[Minispiele] " .. action .. ": " .. tostring(err))
	end
	ms.dirty = true
	if d.money ~= money or ms.worldChanged then
		ms.worldChanged = false
		-- Geld/Lager geändert: ctx.changed (Revision, W.Sync, 2.4.0-Zustand). Höchstens 2×/s, weil jede
		-- Revision das Tablet neu aufbaut; dazwischen zeigt push den neuen Kontostand sofort.
		if t - ms.lastChanged + EPSILON >= MiniConfig.SnapshotMinInterval then
			ms.lastChanged = t
			ms.changePending = false
			ctx.changed(p)
		else
			ms.changePending = true
			ctx.push(p)
		end
	end
	flush(ms, t)
	return ok and "ok" or "error"
end

function Mini.Hello(p)
	local ms = stateFor(p)
	if not ms then
		return
	end
	flushNotices(ms)
	ms.dirty = true
	flush(ms, now())
	if not ms.boardSent then
		pushBoard(ms)
	end
end

function Mini.OnJoin(p)
	local ms = newState(p)
	Mini.Sessions[p.player] = ms
	local d = p.profile.data
	local ok, err = pcall(function()
		local t = now()
		MiniRules.EnsureDay(d, t)
		-- Die Presse-Uhr springt hier auf jetzt; die Offline-Sekunden merkt sich ms.offlinePending, bis sie
		-- gutgeschrieben sind (nach der Game-Pass-Prüfung oder spätestens in OnLeave, falls der Spieler
		-- während der Prüfung geht – sonst wäre die Offline-Zeit mit dem neuen lastTick endgültig verloren).
		ms.offlinePending = PressService.OnJoin(ms, d, t)
		TuningService.OnJoin(ms, d, t)
		-- Game Passes (kann warten), danach den Offline-Ertrag gutschreiben: nur Schrott, nie Geld.
		task.spawn(function()
			local passes = MiniPasses.Check(ms.userId)
			if Mini.Sessions[p.player] ~= ms or not ctx or ctx.getSession(p.player) ~= p then
				return -- OnLeave hat den Offline-Ertrag schon (ohne Pass-Bonus) gutgeschrieben
			end
			ms.passes = passes
			local offline = ms.offlinePending
			ms.offlinePending = nil
			if not offline then
				return
			end
			local info = PressService.ApplyOffline(ms, d, offline, now())
			if info then
				queueNotice(ms, "offline", info)
			end
			ms.dirty = true
		end)
	end)
	if not ok then
		warn("[Minispiele] Beitritt: " .. tostring(err))
	end
end

function Mini.Tick(p, t)
	local ms = Mini.Sessions[p.player]
	if not ms or ms.p ~= p then
		return
	end
	local ok, err = pcall(function()
		local d = p.profile.data
		if ms.changePending and t - ms.lastChanged + EPSILON >= MiniConfig.SnapshotMinInterval then
			ms.changePending = false
			ms.lastChanged = t
			ctx.changed(p) -- nachgeholte, gedrosselte Revision (siehe Handle)
		end
		PressService.Tick(ms, d, t)
		if GoalsService.Tick(ms, d, t) then
			ms.dirty = true
		end
		-- Schrottplatz: sobald das Fahrzeug zerlegt werden darf, einmal neuen Snapshot senden
		local sy = d.games.scrapyard
		if sy.vehicle and ms.scrapReadySent ~= sy.readyAt and SideGameRules.DismantleIn(d, t) <= 0 then
			ms.scrapReadySent = sy.readyAt
			ms.dirty = true
		end
		if api.writable(ms) and LeaderboardService.CanWrite(true) and LeaderboardService.WriteDue(ms, t) then
			task.spawn(LeaderboardService.Write, ms, false, true)
		end
		if LeaderboardService.RefreshDue(t) then
			task.spawn(LeaderboardService.Refresh, false)
		end
		flush(ms, t)
	end)
	if not ok then
		warn("[Minispiele] Tick: " .. tostring(err))
	end
end

function Mini.OnSettled(p)
	local ms = stateFor(p)
	local ok, err = pcall(function()
		MiniRules.AddStat(p.profile.data, "jobsDone", 1, now())
	end)
	if not ok then
		warn("[Minispiele] Abrechnung: " .. tostring(err))
	end
	if ms then
		ms.dirty = true
	end
end

function Mini.OnActivity(p)
	local ms = stateFor(p)
	local ok, err = pcall(function()
		MiniRules.MarkActive(p.profile.data, now())
	end)
	if not ok then
		warn("[Minispiele] Außenarbeit: " .. tostring(err))
	end
	if ms then
		ms.dirty = true
	end
end

-- Sitzungen, die gerade verlassen werden und auf das Ergebnis des letzten Speicherns warten.
Mini.Leaving = setmetatable({}, { __mode = "k" }) -- [p] = { ms, writable }

-- Letzter Presse-Tick. wasWritable = profile.writable vor P.Save(release).
-- Die Bestenliste wird erst in OnSaved geschrieben: nur ein tatsächlich gespeicherter Lebenszeit-Wert
-- darf in die globale Liste (sonst zeigte sie nach verweigertem Speichern – offener Robux-Beleg,
-- verlorene Sperre – einen Wert, den das Profil nicht hat, und fiele beim nächsten Besuch zurück).
-- Mehrfacher Aufruf (BindToClose + PlayerRemoving) ist harmlos.
function Mini.OnLeave(p, wasWritable)
	local ms = Mini.Sessions[p.player]
	if not ms or ms.p ~= p then
		return
	end
	Mini.Sessions[p.player] = nil
	if ms.offlinePending then
		-- Verlassen vor Ende der Game-Pass-Prüfung: Offline-Ertrag jetzt (ohne Pass-Bonus) verbuchen.
		local offline = ms.offlinePending
		ms.offlinePending = nil
		pcall(PressService.ApplyOffline, ms, p.profile.data, offline, now())
	end
	pcall(PressService.Tick, ms, p.profile.data, now())
	Mini.Leaving[p] = { ms = ms, writable = wasWritable == true and not p.profile.receiptPending }
end

-- Nach P.Save(release): saved = Rückgabe von P.Save. Blockiert nicht (Schreiben in eigenem Task,
-- BindToClose wartet über Mini.Pending()).
function Mini.OnSaved(p, saved)
	local entry = Mini.Leaving[p]
	if not entry or saved ~= true then
		return
	end
	Mini.Leaving[p] = nil
	if entry.writable and LeaderboardService.CanWrite(true) then
		task.spawn(LeaderboardService.Write, entry.ms, true, true)
	end
end

function Mini.Pending()
	return LeaderboardService.Pending
end

---------------------------------------------------------------- Stationen, Reisen, Ausbau
local function openStation(p, tab, station)
	local ms = stateFor(p)
	if not ms or p.closing then
		return
	end
	if MiniNet.TabSet[tab] then
		emit(ms, MiniNet.Events.Open, { tab = tab })
	elseif tab == "workshop" or tab == "home" then
		CityService.Travel(p, "workshop", ctx.moveTo)
	else
		api.toast(ms, MiniLocale.T("coming_soon", CityService.Title(station, tab)))
	end
end

Actions.Register("mini_upgrade", function(ms, data, d)
	local ok, res = MiniRules.BuyUpgrade(d, data.key, data.level)
	api.toast(ms, ok and (res.name .. " verbessert.") or res)
end)

Actions.Register("mini_travel", function(ms, data)
	local ok, msg = CityService.Travel(ms.p, data.key, ctx.moveTo)
	if not ok then
		api.toast(ms, msg)
	end
end)

Actions.Register("mini_pass_prompt", function(ms, data)
	local _, msg = MiniPasses.Prompt(ms.player, data.pass, ms.passes)
	api.toast(ms, msg)
end)

Actions.Register("mini_sync", function(ms)
	flushNotices(ms)
	if not ms.boardSent then
		pushBoard(ms)
	end
end)

PressService.Register(Actions, api)
TuningService.Register(Actions, api)
SideGamesService.Register(Actions, api)
GoalsService.Register(Actions, api)
LeaderboardService.Register(Actions, api)

for name in pairs(MiniNet.Actions) do
	assert(Mini.Handlers[name], "Kein Handler für " .. name)
end

function Mini.Init(c)
	ctx = c
	LeaderboardService.Init(c.now)
	LeaderboardService.OnUpdated = function(cache)
		CityService.UpdateBoard(cache)
		for _, ms in pairs(Mini.Sessions) do
			if alive(ms) and ms.greeted then
				local ok, err = pcall(pushBoard, ms)
				if not ok then
					warn("[Bestenliste] Senden: " .. tostring(err))
				end
			end
		end
	end
	MiniPasses.Init(function(player, field)
		local ms = Mini.Sessions[player]
		if not ms or not alive(ms) then
			return
		end
		ms.passes[field] = true
		ms.dirty = true
		api.toast(ms, MiniLocale.T("pass_thanks"))
	end)
	CityService.Init({ getSession = c.getSession, onStation = openStation })
end

return Mini
