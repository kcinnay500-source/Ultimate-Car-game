--!nonstrict
-- DevService: Entwickler-Menü auf dem Server (Level, XP, Credits, Tycoon-Bargeld setzen; Startweg zurücksetzen).
-- Nur für Entwickler (DevService.IsDev): in Roblox Studio, für UserIds aus GameConfig.Dev.AllowedUserIds, für den
-- Ersteller des Spiels (CreatorType User) bzw. den Besitzer der Gruppe (Gruppenspiel, GroupService im Hintergrund).
-- Alle anderen merken nichts: kein Toast, kein Hinweis, keine Antwort.
--
-- Öffnen:
--   * Chat „/dev“ (GameConfig.Dev.Command): Player.Chatted (OnJoin verbindet es je Spieler) UND ein vom Server
--     angelegter TextChatCommand (PrimaryAlias "/dev") unter TextChatService.TextChatCommands (Init, in pcall);
--     Triggered(textSource) -> Spieler über textSource.UserId.
--   * Aktion dev_open {} (DevUI: Strg+Umschalt+D).
--   Antwort an Entwickler: mini_notice { kind = "dev", event = "open", ...Werte } (DevUI öffnet sich).
-- Setzen: Aktion dev_set { field, value } – IsDev wird bei JEDEM Aufruf neu geprüft; Werte endlich, ganzzahlig,
--   gedeckelt (GameConfig.Dev). field:
--     "level"        1..MaxLevel; XP im Level = 0 (konsistent); Freischalt-Karten wie bei einem normalen Aufstieg
--                    (PrestigeService.Tick im nächsten Takt); springt das Level über mehr als MaxUnlockCards
--                    Freischaltungen, gibt es eine Sammel-Meldung statt einer Karten-Flut
--     "xp"           0..MaxXP: XP im aktuellen Level; was über die Schwelle geht, steigt über MiniRules.GainXP auf
--                    (wie gewohnt inkl. Level-Bonus)
--     "credits"      0..MaxCredits (d.money)
--     "credits_add"  +value (0..MaxCredits) Credits (Knopf „+10.000 Credits“), nie über max(MaxCredits, Kontostand)
--     "cash"         0..MaxCash: Bargeld des laufenden Tycoon-Durchlaufs (nur im Modus tycoon mit Durchlauf)
--     "start_reset"  Startweg zurücksetzen (value egal): StartService.DevReset(ms, d) falls vorhanden, sonst hier
--   Danach: api.worldChanged (MiniService ruft ctx.changed -> 2.4.0-Zustand/HUD), api.dirty (Minispiel-Snapshot),
--   mini_notice { kind = "dev", event = "update" } mit den neuen Werten und ein deutscher Toast.
--   Jede Änderung steht mit print("[Dev] …") im Server-Log.
--
-- Schnittstelle für MiniService:
--   Register(Actions, api)    dev_open, dev_set (api: now, toast, notice, dirty, worldChanged, changed)
--   Init(ctx)                 TextChatCommand anlegen, Gruppenbesitzer (Gruppenspiel) im Hintergrund nachschlagen
--   OnJoin(ms, d, now)        Sitzung merken, Player.Chatted verbinden
--   OnLeave(ms)               Verbindung lösen, Sitzung vergessen
--   IsDev(player) -> bool     Berechtigung (ohne zu warten)
--   OpenFor(player) -> bool   Menü öffnen (Chat-Weg; prüft IsDev)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local MiniShared = Shared:WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))
local TycoonRules = require(MiniShared:WaitForChild("TycoonRules"))
local PrestigeRules = require(MiniShared:WaitForChild("PrestigeRules"))
local Unlocks = require(MiniShared:WaitForChild("Unlocks"))
local Rules = require(Shared:WaitForChild("Rules"))

local DevService = {}

DevService.Sessions = {} -- [Player] = ms
DevService.CommandName = "UCGDevCommand"

DevService.Text = {
	level = "Entwickler: Level auf %s gesetzt.",
	xp = "Entwickler: XP gesetzt (Level %s, %s / %s XP).",
	credits = "Entwickler: Credits auf %s gesetzt.",
	creditsAdd = "Entwickler: +%s Credits (jetzt %s).",
	cash = "Entwickler: Bargeld auf %s gesetzt.",
	noRun = "Kein Tycoon-Durchlauf aktiv – starte zuerst einen Durchlauf auf deinem Grundstück.",
	onlyTycoon = "Bargeld gibt es nur im Tycoon.",
	startReset = "Entwickler: Startweg zurückgesetzt – die Startwahl erscheint in der Open World.",
	startNotPossible = "Startweg zurückgesetzt, aber die Startwahl kann nicht erscheinen: %s",
	unlocks = "%d Freischaltungen auf einmal erreicht – alle stehen im Tab „Freischaltungen“.",
	invalid = "Entwickler: ungültiger Wert.",
}

local api: any = nil
local ctx: any = nil
local groupOwnerId: number? = nil
local groupLookup = false

local function cfg(): any
	return GameConfig.Dev or {}
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function now(): number
	if api and type(api.now) == "function" then
		return api.now()
	end
	if ctx and type(ctx.now) == "function" then
		return ctx.now()
	end
	return os.time()
end

local function fmt(n: any): string
	if not finite(n) then
		return "0"
	end
	local s = string.format("%d", math.floor(n))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return (out:gsub("^%-%.", "-"))
end

local function toast(ms: any, text: string)
	if api and type(api.toast) == "function" and ms then
		api.toast(ms, text)
	end
end

local function userIdOf(player: any): number?
	local ok, id = pcall(function()
		return player.UserId
	end)
	return ok and finite(id) and id or nil
end

local function nameOf(player: any): string
	local ok, name = pcall(function()
		return player.Name
	end)
	return ok and type(name) == "string" and name or "?"
end

local function log(player: any, text: string)
	print("[Dev] " .. nameOf(player) .. " (" .. tostring(userIdOf(player)) .. "): " .. text)
end

---------------------------------------------------------------- Berechtigung
local function isStudio(): boolean
	local ok, res = pcall(function()
		return RunService:IsStudio()
	end)
	return ok and res == true
end

local function creator(): (any, number?)
	local ok, kind, id = pcall(function()
		return game.CreatorType, game.CreatorId
	end)
	if not ok then
		return nil, nil
	end
	return kind, finite(id) and id or nil
end

-- Gruppenspiel: Besitzer der Gruppe einmal im Hintergrund nachschlagen (IsDev wartet nie)
local function lookupGroupOwner()
	if groupLookup then
		return
	end
	local kind, id = creator()
	if kind ~= Enum.CreatorType.Group or not id or id <= 0 then
		return
	end
	groupLookup = true
	task.spawn(function()
		local ok, info = pcall(function()
			return game:GetService("GroupService"):GetGroupInfoAsync(id)
		end)
		local owner = ok and type(info) == "table" and type(info.Owner) == "table" and info.Owner.Id or nil
		if finite(owner) and owner > 0 then
			groupOwnerId = owner
		else
			groupLookup = false -- später erneut versuchen (z. B. API kurz nicht erreichbar)
		end
	end)
end

function DevService.IsDev(player: any): boolean
	if player == nil then
		return false
	end
	if isStudio() then
		return true
	end
	local id = userIdOf(player)
	if not id or id <= 0 then
		return false
	end
	for _, allowed in ipairs(cfg().AllowedUserIds or {}) do
		if allowed == id then
			return true
		end
	end
	local kind, creatorId = creator()
	if kind == Enum.CreatorType.User and creatorId == id then
		return true
	end
	if kind == Enum.CreatorType.Group then
		if groupOwnerId ~= nil then
			return groupOwnerId == id
		end
		lookupGroupOwner()
	end
	return false
end

---------------------------------------------------------------- Werte
local function maxLevel(): number
	local m = finite(cfg().MaxLevel) and math.floor(cfg().MaxLevel) or 1000
	for _, lv in ipairs(GameConfig.UnlockLevels or {}) do
		if finite(lv) and lv > m then
			m = math.floor(lv)
		end
	end
	return math.max(1, m)
end
DevService.MaxLevel = maxLevel

local function modeOf(ms: any): string?
	local p = ms and ms.p
	local mode = p and p.mode
	return type(mode) == "string" and mode or nil
end

local function inTycoon(ms: any): boolean
	return modeOf(ms) == "tycoon"
end

local function xpNeeded(d: any): number
	local ok, n = pcall(Rules.XPNeeded, d)
	return ok and finite(n) and n or 0
end

-- Werte für DevUI (flach genug für den Client; nur Anzeige)
function DevService.State(ms: any, d: any, event: string?): { [string]: any }
	local run = TycoonRules.RunOf(d)
	local okRank, rank = pcall(PrestigeRules.Rank, d)
	local okTitle, title = pcall(PrestigeRules.Title, d)
	return {
		event = event or "update",
		level = finite(d.level) and d.level or 1,
		xp = finite(d.xp) and d.xp or 0,
		xpNeeded = xpNeeded(d),
		credits = finite(d.money) and d.money or 0,
		rank = okRank and finite(rank) and rank or 0,
		rankTitle = okTitle and type(title) == "string" and title or "",
		mode = modeOf(ms) or "openworld",
		inTycoon = inTycoon(ms),
		hasRun = run ~= nil,
		cash = run and finite(run.cash) and run.cash or 0,
		startPath = MetaRules.StartPath(d),
		startPending = MetaRules.StartPending(d),
		maxLevel = maxLevel(),
		maxCredits = cfg().MaxCredits or 1e9,
		maxCash = cfg().MaxCash or 1e12,
		maxXP = cfg().MaxXP or 1e9,
		addCredits = cfg().AddCredits or 10000,
	}
end

local function dataOf(ms: any): any
	local p = ms and ms.p
	local prof = p and p.profile
	return prof and prof.data
end

local function send(ms: any, d: any, event: string)
	if api and type(api.notice) == "function" then
		api.notice(ms, "dev", DevService.State(ms, d, event))
	end
end

---------------------------------------------------------------- Öffnen
local function open(ms: any, t: number?): boolean
	if not ms or not DevService.IsDev(ms.player) then
		return false
	end
	local d = dataOf(ms)
	if type(d) ~= "table" then
		return false
	end
	t = finite(t) and t or now()
	local cd = finite(cfg().OpenCooldown) and cfg().OpenCooldown or 0.5
	if finite(ms.devOpenAt) and t >= ms.devOpenAt and t - ms.devOpenAt < cd then
		return false -- Chatted und TextChatCommand zugleich: nur einmal öffnen
	end
	ms.devOpenAt = t
	send(ms, d, "open")
	log(ms.player, "Entwickler-Menü geöffnet")
	return true
end

function DevService.OpenFor(player: any): boolean
	local ms = player and DevService.Sessions[player]
	if not ms then
		return false
	end
	local ok, res = pcall(open, ms, nil)
	if not ok then
		warn("[Dev] Öffnen: " .. tostring(res))
		return false
	end
	return res == true
end

local function isCommand(text: any): boolean
	if type(text) ~= "string" or #text > 64 then
		return false
	end
	local cmd = string.lower(cfg().Command or "/dev")
	local s = string.lower((text:gsub("^%s+", ""):gsub("%s+$", "")))
	return s == cmd
end
DevService.IsCommand = isCommand

---------------------------------------------------------------- Setzen
local function clampInt(v: number, lo: number, hi: number): number
	return math.max(lo, math.min(hi, math.floor(v)))
end

-- Freischalt-Karten: wenige -> PrestigeService.Tick zeigt sie wie bei einem normalen Aufstieg; viele -> Sammel-Meldung
local function unlockCards(ms: any, d: any, old: number, new: number)
	if new <= old then
		return
	end
	local okN, list = pcall(Unlocks.NewlyReached, old, new)
	local n = okN and type(list) == "table" and #list or 0
	local limit = finite(cfg().MaxUnlockCards) and cfg().MaxUnlockCards or 5
	if n > limit then
		ms.lastLevel = new -- PrestigeService: diese Aufstiege nicht einzeln melden
		local okR, rank = pcall(PrestigeRules.Rank, d)
		if okR then
			ms.lastRank = rank
		end
		ms.unlocksSeenLevel = ms.unlocksSeenLevel or old
		toast(ms, string.format(DevService.Text.unlocks, n))
	end
end

local function resetStart(ms: any, d: any): (boolean, string?)
	local okS, StartService = pcall(function()
		return require(script.Parent:WaitForChild("StartService", 5))
	end)
	if okS and type(StartService) == "table" and type(StartService.DevReset) == "function" then
		local ok, res, msg = pcall(StartService.DevReset, ms, d)
		if not ok then
			warn("[Dev] StartService.DevReset: " .. tostring(res))
			return false, DevService.Text.invalid
		end
		return res == true, msg
	end
	-- Ersatz ohne StartService.DevReset: Weg leeren, Wahl als offen markieren, Tutorial des Wegs neu
	local m = MetaRules.Meta(d)
	if not m then
		return false, "Profil ohne Metadaten."
	end
	m.startPath = ""
	m.startOffered = true
	m.tutorialDone = false
	m.tutorialSkipped = false
	m.tutorialStep = 1
	ms.tutorialStarted = nil
	ms.startOffered = nil
	if not MetaRules.StartPending(d) then
		return false, string.format(DevService.Text.startNotPossible, "du besitzt schon ein Open-World-Gebäude.")
	end
	if okS and type(StartService) == "table" and type(StartService.OnMode) == "function" and (modeOf(ms) == nil or modeOf(ms) == "openworld") then
		pcall(StartService.OnMode, ms, d, "openworld")
	end
	return true, nil
end

local FIELDS = { level = true, xp = true, credits = true, credits_add = true, cash = true, start_reset = true }
DevService.Fields = FIELDS

-- Handler dev_set (ms, data, d, now). Rückgabe nil (keine Story-/Tutorial-Ereignisse für Entwickler-Änderungen).
function DevService.Set(ms: any, data: any, d: any, t: number?): nil
	if not ms or not DevService.IsDev(ms.player) or type(d) ~= "table" then
		return nil -- kein Hinweis für Nicht-Entwickler
	end
	local field = type(data) == "table" and data.field or nil
	local value = type(data) == "table" and data.value or nil
	if type(field) ~= "string" or not FIELDS[field] then
		toast(ms, DevService.Text.invalid)
		return nil
	end
	if field ~= "start_reset" and not finite(value) then
		toast(ms, DevService.Text.invalid)
		return nil
	end
	local player = ms.player
	if field == "level" then
		local old = finite(d.level) and d.level or 1
		local new = clampInt(value, 1, maxLevel())
		d.level = new
		d.xp = 0
		unlockCards(ms, d, old, new)
		log(player, string.format("Level %s -> %s (XP 0)", fmt(old), fmt(new)))
		toast(ms, string.format(DevService.Text.level, fmt(new)))
	elseif field == "xp" then
		local oldLevel = finite(d.level) and d.level or 1
		local amount = clampInt(value, 0, finite(cfg().MaxXP) and cfg().MaxXP or 1e9)
		d.xp = 0
		if amount > 0 then
			MiniRules.GainXP(d, amount)
		end
		unlockCards(ms, d, oldLevel, d.level)
		log(player, string.format("XP gesetzt: %s (Level %s -> %s, %s XP)", fmt(amount), fmt(oldLevel), fmt(d.level), fmt(d.xp)))
		toast(ms, string.format(DevService.Text.xp, fmt(d.level), fmt(d.xp), fmt(xpNeeded(d))))
	elseif field == "credits" then
		local old = finite(d.money) and d.money or 0
		d.money = clampInt(value, 0, finite(cfg().MaxCredits) and cfg().MaxCredits or 1e9)
		log(player, string.format("Credits %s -> %s", fmt(old), fmt(d.money)))
		toast(ms, string.format(DevService.Text.credits, fmt(d.money)))
	elseif field == "credits_add" then
		local old = finite(d.money) and d.money or 0
		local maxC = finite(cfg().MaxCredits) and cfg().MaxCredits or 1e9
		local add = clampInt(value, 0, maxC)
		d.money = math.floor(math.min(old + add, math.max(maxC, old)))
		log(player, string.format("Credits +%s: %s -> %s", fmt(add), fmt(old), fmt(d.money)))
		toast(ms, string.format(DevService.Text.creditsAdd, fmt(d.money - old), fmt(d.money)))
	elseif field == "cash" then
		if not inTycoon(ms) then
			toast(ms, DevService.Text.onlyTycoon)
			send(ms, d, "update")
			return nil
		end
		local run = TycoonRules.RunOf(d)
		if not run then
			toast(ms, DevService.Text.noRun)
			send(ms, d, "update")
			return nil
		end
		local old = finite(run.cash) and run.cash or 0
		run.cash = clampInt(value, 0, finite(cfg().MaxCash) and cfg().MaxCash or 1e12)
		log(player, string.format("Bargeld %s -> %s", fmt(old), fmt(run.cash)))
		toast(ms, string.format(DevService.Text.cash, fmt(run.cash)))
	elseif field == "start_reset" then
		local old = MetaRules.StartPath(d)
		local ok, msg = resetStart(ms, d)
		log(player, string.format("Startweg zurückgesetzt (vorher %q, Wahl offen: %s)", old, tostring(MetaRules.StartPending(d))))
		toast(ms, ok and (msg or DevService.Text.startReset) or (msg or DevService.Text.invalid))
	end
	if api then
		if type(api.worldChanged) == "function" then
			api.worldChanged(ms) -- MiniService.Handle ruft danach ctx.changed (2.4.0-Zustand: Level/XP/Credits im HUD)
		end
		if type(api.dirty) == "function" then
			api.dirty(ms)
		end
	end
	send(ms, d, "update")
	return nil
end

-- Handler dev_open (ms, data, d, now)
function DevService.Open(ms: any, _data: any, _d: any, t: number?): nil
	open(ms, t)
	return nil
end

function DevService.Register(Actions: any, a: any)
	api = a
	Actions.Register("dev_open", DevService.Open)
	Actions.Register("dev_set", DevService.Set)
end

-- Nur für Tests: api ohne Actions setzen
function DevService._SetApi(a: any)
	api = a
end

---------------------------------------------------------------- Chat-Befehl
local function onCommand(textSource: any)
	local id = nil
	pcall(function()
		id = textSource.UserId
	end)
	if not finite(id) then
		return
	end
	local player = Players:GetPlayerByUserId(id)
	if player then
		DevService.OpenFor(player)
	end
end
DevService._OnCommand = onCommand

local function createCommand()
	local TextChatService = game:GetService("TextChatService")
	local parent = TextChatService:FindFirstChild("TextChatCommands")
	if not parent then
		parent = Instance.new("Folder")
		parent.Name = "TextChatCommands"
		parent.Parent = TextChatService
	end
	local cmd = parent:FindFirstChild(DevService.CommandName)
	if cmd then
		return cmd
	end
	cmd = Instance.new("TextChatCommand")
	cmd.Name = DevService.CommandName
	cmd.PrimaryAlias = cfg().Command or "/dev"
	local okSig = pcall(function()
		cmd.Triggered:Connect(onCommand)
	end)
	if not okSig then
		cmd:Destroy() -- Umgebung ohne TextChatCommand-Ereignis (Tests): Player.Chatted reicht
		return nil
	end
	cmd.Parent = parent
	return cmd
end

function DevService.Init(c: any)
	ctx = type(c) == "table" and c or nil
	-- Ohne TextChatService (Legacy-Chat, Tests) bleibt Player.Chatted: kein Fehler, keine Warnung
	pcall(createCommand)
	pcall(lookupGroupOwner)
end

---------------------------------------------------------------- Sitzung
function DevService.OnJoin(ms: any, _d: any, _t: number?)
	local player = ms and ms.player
	if not player then
		return
	end
	if ms.devChatConn then
		pcall(function()
			ms.devChatConn:Disconnect()
		end)
	end
	DevService.Sessions[player] = ms
	local ok, conn = pcall(function()
		return player.Chatted:Connect(function(message)
			if isCommand(message) then
				DevService.OpenFor(player)
			end
		end)
	end)
	ms.devChatConn = ok and conn or nil
end

function DevService.OnLeave(ms: any)
	if not ms then
		return
	end
	if ms.devChatConn then
		pcall(function()
			ms.devChatConn:Disconnect()
		end)
		ms.devChatConn = nil
	end
	local player = ms.player
	if player and DevService.Sessions[player] == ms then
		DevService.Sessions[player] = nil
	end
end

return DevService
