-- LobbyService: Lobby-Aktionen, Einstellungen, Party und Reise (docs/PHASE4_CONTRACT.md §1, §5).
-- Aktionen (über MiniService.Handle, also innerhalb von request()):
--   lobby_mode {mode}                        Modus für die nächste Reise wählen ("tycoon" | "openworld"), Sitzungsauswahl
--   lobby_settings {single, passive, beginner}  Einstellungen (MetaRules.SetSettings, sofort wirksam, in d.games.meta gespeichert)
--   lobby_go                                 Reise mit der Auswahl (PlaceRouter.Go); Party: nur der Leiter, Mitglieder reisen mit
--   lobby_return                             aus jedem Modus zurück in die Lobby
--   party_create / party_join {code} / party_leave / party_kick {userId}
-- Party = serverlokal (Code 4 Zeichen aus GameConfig.Party.CodeAlphabet, höchstens MaxMembers, der Leiter startet die Reise;
-- Verlassen des Servers entfernt aus der Party, der nächste wird Leiter). Mitglieder erhalten mini_notice { kind = "party",
-- event = "created" | "joined" | "left" | "kicked" | "leader" | "dissolved" | "travel", code, userId, name, mode }.
-- Schnittstelle für MiniService:
--   LobbyService.Register(Actions, api)      Aktionen registrieren (api wie bei PressService: now, toast, notice, dirty, alive)
--   LobbyService.Init(ctx)                   ctx aus MiniService.Init (emit, toast, moveTo, now, getSession) -> PlaceRouter.Init
--   LobbyService.OnJoin(ms, d, now)          Anfangsmodus (PlaceRouter.InitialMode aus PlaceKind + Player:GetJoinData()),
--                                            MetaRules.Touch, Party-Code aus TeleportData (Leiter legt sie neu an, Mitglieder treten bei)
--   LobbyService.OnCharacter(ms)             Figur erschienen: außerhalb der Open World zur Zonen-Ankunft versetzen (nach GarageServer.moveTo)
--   LobbyService.OnStation(ms, station)      Lobby-Station geöffnet (Attribut LobbyAction): Beginner-Hinweis + mini_notice { kind = "lobby" }
--   LobbyService.Tick(ms, d, now)            Spielzeit (MetaRules.AddPlaySeconds), höchstens 1x/s
--   LobbyService.OnLeave(ms)                 Party verlassen
--   LobbyService.SnapshotFields(ms, d, now, full) -> { mode, placeKind, single, simulated, choice, meta = {...}, party = {...} | false }
-- Kein Geld. Der Client sendet nur Absichten; Modus, Party und Einstellungen bestimmt der Server.
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))
local Unlocks = require(MiniShared:WaitForChild("Unlocks"))
local PlaceRouter = require(script.Parent:WaitForChild("PlaceRouter"))

local LobbyService = {}

export type Party = { code: string, leader: Player, members: { Player }, createdAt: number }

LobbyService.Parties = {} :: { [string]: Party } -- [code] = Party (serverlokal)
LobbyService.MemberOf = setmetatable({}, { __mode = "k" }) :: { [Player]: Party }
LobbyService.Sessions = setmetatable({}, { __mode = "k" }) -- [Player] = ms (für Hinweise an Mitglieder)

local api -- MiniService-api: now, toast, notice, dirty, alive
local ctx -- GarageServer-Kontext (emit, toast, moveTo, now, getSession)

local TEXT = {
	modeUnknown = "Diesen Modus gibt es nicht.",
	modeChosen = { tycoon = "Schnelles Spiel ausgewählt. Drück „Los geht's“, wenn du bereit bist.", openworld = "Open World ausgewählt. Drück „Los geht's“, wenn du bereit bist." },
	settingsSaved = "Einstellungen gespeichert.",
	settingsSame = "Das ist schon so eingestellt.",
	alreadyThere = "Du bist schon hier.",
	alreadyLobby = "Du bist schon in der Lobby.",
	notLeader = "Nur der Party-Leiter startet die Reise. Frag ihn, wenn ihr loswollt!",
	partyExists = "Du bist schon in einer Party. Verlasse sie zuerst.",
	partyCreated = "Party erstellt! Dein Code: %s",
	partyCode = "Ein Party-Code hat %d Zeichen (Buchstaben und Zahlen).",
	partyUnknown = "Diese Party gibt es hier nicht. Prüf den Code – Partys gelten nur im selben Server.",
	partyFull = "Diese Party ist schon voll (höchstens %d Spieler).",
	partyJoined = "Du bist der Party von %s beigetreten.",
	partyNone = "Du bist in keiner Party.",
	partyLeft = "Du hast die Party verlassen.",
	partyOnlyLeader = "Nur der Party-Leiter darf Mitglieder entfernen.",
	partySelfKick = "Dich selbst kannst du nicht entfernen – verlass die Party stattdessen.",
	partyNotMember = "Dieser Spieler ist nicht in deiner Party.",
	partyKicked = "Du wurdest aus der Party entfernt.",
	partyLeader = "%s ist jetzt Party-Leiter.",
	partyNoCode = "Es ist gerade kein Party-Code frei. Versuch es gleich noch einmal.",
	partyTooSoon = "Einen Moment, bitte.",
	arrived = PlaceRouter.Text.arrived,
	stationHint = { mode_tycoon = "Schnelles Spiel", mode_openworld = "Open World", settings = "Einstellungen", party = "Party", tutorial = "Tutorial" },
}
LobbyService.Text = TEXT

local function now(): number
	if api and type(api.now) == "function" then
		return api.now()
	end
	if ctx and type(ctx.now) == "function" then
		return ctx.now()
	end
	return os.time()
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function toast(ms: any, text: string?)
	if api and type(text) == "string" and text ~= "" then
		api.toast(ms, text)
	end
end

local function dirty(ms: any)
	if api and ms then
		api.dirty(ms)
	end
end

local function msOf(player: Player): any
	return LobbyService.Sessions[player]
end

local function playerName(player: any): string
	local ok, name = pcall(function()
		return player.DisplayName
	end)
	if ok and type(name) == "string" and name ~= "" then
		return name
	end
	return tostring(player and player.Name or "Spieler")
end

---------------------------------------------------------------- Party
local function newCode(rng: Random?): string?
	local P = GameConfig.Party
	local alphabet = P.CodeAlphabet
	for _ = 1, P.CodeTries do
		local chars = {}
		for i = 1, P.CodeLength do
			local n = rng and rng:NextInteger(1, #alphabet) or math.random(1, #alphabet)
			chars[i] = string.sub(alphabet, n, n)
		end
		local code = table.concat(chars)
		if not LobbyService.Parties[code] then
			return code
		end
	end
	return nil
end

-- Code aus einer Eingabe: Großschreibung, nur Zeichen des Alphabets, genau CodeLength Zeichen; sonst nil
function LobbyService.NormalizeCode(raw: any): string?
	if type(raw) ~= "string" then
		return nil
	end
	local code = string.upper((string.gsub(raw, "%s", "")))
	if #code ~= GameConfig.Party.CodeLength then
		return nil
	end
	for i = 1, #code do
		if not string.find(GameConfig.Party.CodeAlphabet, string.sub(code, i, i), 1, true) then
			return nil
		end
	end
	return code
end

function LobbyService.PartyOf(player: Player): Party?
	return LobbyService.MemberOf[player]
end

-- Hinweis an alle Mitglieder (außer `except`), dazu Snapshot der Mitglieder als geändert markieren
local function notifyParty(party: Party, data: { [string]: any }, except: Player?)
	for _, member in ipairs(party.members) do
		local ms = msOf(member)
		if ms and member ~= except then
			if api then
				local copy = table.clone(data)
				copy.code = party.code
				api.notice(ms, "party", copy)
			end
			dirty(ms)
		end
	end
end

local function memberIndex(party: Party, player: Player): number?
	for i, m in ipairs(party.members) do
		if m == player then
			return i
		end
	end
	return nil
end

local function createParty(leader: Player, code: string?, t: number): Party?
	code = code or newCode()
	if not code or LobbyService.Parties[code] then
		return nil
	end
	local party = { code = code, leader = leader, members = { leader }, createdAt = t }
	LobbyService.Parties[code] = party
	LobbyService.MemberOf[leader] = party
	return party
end

local function joinParty(party: Party, player: Player): (boolean, string?)
	if #party.members >= GameConfig.Party.MaxMembers then
		return false, string.format(TEXT.partyFull, GameConfig.Party.MaxMembers)
	end
	if memberIndex(party, player) then
		return true
	end
	table.insert(party.members, player)
	LobbyService.MemberOf[player] = party
	return true
end

-- Spieler aus seiner Party entfernen (reason = "left" | "kicked" | "gone"); Leiterwechsel, leere Party auflösen
local function removeFromParty(player: Player, reason: string)
	local party = LobbyService.MemberOf[player]
	if not party then
		return nil
	end
	LobbyService.MemberOf[player] = nil
	local i = memberIndex(party, player)
	if i then
		table.remove(party.members, i)
	end
	if #party.members == 0 then
		LobbyService.Parties[party.code] = nil
		return party
	end
	notifyParty(party, { event = reason == "kicked" and "kicked" or "left", userId = player.UserId, name = playerName(player) })
	if party.leader == player then
		party.leader = party.members[1]
		notifyParty(party, { event = "leader", userId = party.leader.UserId, name = playerName(party.leader) })
		local leaderMs = msOf(party.leader)
		if leaderMs then
			toast(leaderMs, string.format(TEXT.partyLeader, "Du"))
		end
	end
	return party
end

-- Mitglieder, die noch im Spiel sind (für Teleport/Simulation)
local function livingMembers(party: Party): { Player }
	local out = {}
	for _, m in ipairs(party.members) do
		if m.Parent then
			table.insert(out, m)
		end
	end
	return out
end

---------------------------------------------------------------- Reise
local function travel(ms: any, mode: string, fromAction: string): boolean
	local p, d = ms.p, ms.p.profile.data
	local party = LobbyService.PartyOf(ms.player)
	if party and party.leader ~= ms.player then
		toast(ms, TEXT.notLeader)
		return false
	end
	local settings = MetaRules.Settings(d)
	local members = party and livingMembers(party) or nil
	local ok, res = PlaceRouter.Go(p, mode, { single = settings.single, party = party and party.code or nil, players = members })
	if not ok then
		if type(res) == "string" then
			toast(ms, res)
		end
		return false
	end
	dirty(ms)
	if type(res) == "table" and res.teleported then
		return true
	end
	-- Simulation: Mitglieder reisen mit (jeder mit seinen eigenen Einstellungen)
	if party then
		for _, member in ipairs(members or {}) do
			if member ~= ms.player then
				local mms = msOf(member)
				if mms and mms.p and mms.p.profile then
					local ms2 = MetaRules.Settings(mms.p.profile.data)
					local ok2 = PlaceRouter.Simulate(mms.p, mode, { single = ms2.single, party = party.code })
					if ok2 then
						mms.lobbyChoice = nil
						dirty(mms)
					end
				end
			end
		end
		notifyParty(party, { event = "travel", mode = mode, userId = ms.player.UserId, name = playerName(ms.player) }, ms.player)
	end
	ms.lobbyChoice = nil
	toast(ms, TEXT.arrived[mode])
	return true
end

---------------------------------------------------------------- Aktionen
local function lobbyMode(ms: any, data: any, d: any)
	local mode = data.mode
	if mode ~= "tycoon" and mode ~= "openworld" then
		toast(ms, TEXT.modeUnknown)
		return
	end
	local ok, msg = Unlocks.Gate(d, "mode:" .. mode)
	if not ok then
		toast(ms, msg)
		return
	end
	ms.lobbyChoice = mode
	dirty(ms)
	toast(ms, TEXT.modeChosen[mode])
end

local function lobbySettings(ms: any, data: any, d: any)
	local changed = MetaRules.SetSettings(d, { single = data.single, passive = data.passive, beginner = data.beginner })
	ms.p.single = MetaRules.Settings(d).single
	dirty(ms)
	toast(ms, changed and TEXT.settingsSaved or TEXT.settingsSame)
end

local function lobbyGo(ms: any, _: any, d: any)
	local mode = ms.lobbyChoice
	if not mode then
		local last = MetaRules.Mode(d)
		mode = (last ~= "lobby" and last) or "openworld"
	end
	if mode == "lobby" or not GameConfig.ModeSet[mode] then
		mode = "openworld"
	end
	local ok, msg = Unlocks.Gate(d, "mode:" .. mode)
	if not ok then
		toast(ms, msg)
		return
	end
	if ms.p.mode == mode then
		toast(ms, TEXT.alreadyThere)
		return
	end
	travel(ms, mode, "lobby_go")
end

local function lobbyReturn(ms: any)
	if ms.p.mode == "lobby" then
		toast(ms, TEXT.alreadyLobby)
		return
	end
	travel(ms, "lobby", "lobby_return")
end

local function partyCreate(ms: any, _: any, _d: any, t: number)
	if LobbyService.PartyOf(ms.player) then
		toast(ms, TEXT.partyExists)
		return
	end
	if finite(ms.partyActionAt) and t - ms.partyActionAt < GameConfig.Party.CreateCooldown then
		toast(ms, TEXT.partyTooSoon)
		return
	end
	local party = createParty(ms.player, nil, t)
	if not party then
		toast(ms, TEXT.partyNoCode)
		return
	end
	ms.partyActionAt = t
	dirty(ms)
	if api then
		api.notice(ms, "party", { event = "created", code = party.code, userId = ms.player.UserId, name = playerName(ms.player) })
	end
	toast(ms, string.format(TEXT.partyCreated, party.code))
end

local function partyJoin(ms: any, data: any, _d: any, t: number)
	if LobbyService.PartyOf(ms.player) then
		toast(ms, TEXT.partyExists)
		return
	end
	local code = LobbyService.NormalizeCode(data.code)
	if not code then
		toast(ms, string.format(TEXT.partyCode, GameConfig.Party.CodeLength))
		return
	end
	if finite(ms.partyActionAt) and t - ms.partyActionAt < GameConfig.Party.JoinCooldown then
		toast(ms, TEXT.partyTooSoon)
		return
	end
	local party = LobbyService.Parties[code]
	if not party then
		toast(ms, TEXT.partyUnknown)
		return
	end
	local ok, msg = joinParty(party, ms.player)
	if not ok then
		toast(ms, msg)
		return
	end
	ms.partyActionAt = t
	notifyParty(party, { event = "joined", userId = ms.player.UserId, name = playerName(ms.player) })
	toast(ms, string.format(TEXT.partyJoined, playerName(party.leader)))
end

local function partyLeave(ms: any)
	if not LobbyService.PartyOf(ms.player) then
		toast(ms, TEXT.partyNone)
		return
	end
	removeFromParty(ms.player, "left")
	dirty(ms)
	toast(ms, TEXT.partyLeft)
end

local function partyKick(ms: any, data: any)
	local party = LobbyService.PartyOf(ms.player)
	if not party then
		toast(ms, TEXT.partyNone)
		return
	end
	if party.leader ~= ms.player then
		toast(ms, TEXT.partyOnlyLeader)
		return
	end
	local userId = math.floor(data.userId)
	if userId == ms.player.UserId then
		toast(ms, TEXT.partySelfKick)
		return
	end
	local target = nil
	for _, m in ipairs(party.members) do
		if m.UserId == userId then
			target = m
			break
		end
	end
	if not target then
		toast(ms, TEXT.partyNotMember)
		return
	end
	local targetMs = msOf(target)
	if targetMs then
		if api then
			api.notice(targetMs, "party", { event = "kicked", code = party.code, userId = userId, name = playerName(target) })
		end
		toast(targetMs, TEXT.partyKicked)
	end
	removeFromParty(target, "kicked")
	if targetMs then
		dirty(targetMs)
	end
	dirty(ms)
end

function LobbyService.Register(Actions: any, a: any)
	api = a
	Actions.Register("lobby_mode", lobbyMode)
	Actions.Register("lobby_settings", lobbySettings)
	Actions.Register("lobby_go", lobbyGo)
	Actions.Register("lobby_return", lobbyReturn)
	Actions.Register("party_create", partyCreate)
	Actions.Register("party_join", partyJoin)
	Actions.Register("party_leave", partyLeave)
	Actions.Register("party_kick", partyKick)
end

function LobbyService.Init(c: any)
	ctx = type(c) == "table" and c or nil
	PlaceRouter.Init(c)
end

---------------------------------------------------------------- Sitzung
function LobbyService.OnJoin(ms: any, d: any, t: number?)
	t = finite(t) and t or now()
	LobbyService.Sessions[ms.player] = ms
	ms.lobbyChoice = nil
	ms.playAt = t
	local okJoin, joinData = pcall(function()
		return ms.player:GetJoinData()
	end)
	local mode, info = PlaceRouter.InitialMode(ms.p, PlaceRouter.PlaceKind(), okJoin and joinData or nil)
	MetaRules.Touch(d, t)
	ms.arrivalPending = mode ~= "openworld" -- Figur nach dem Erscheinen zur Zone (OnCharacter)
	-- Party aus dem Teleport: der Leiter legt sie mit demselben Code neu an, Mitglieder treten bei (gleicher Server)
	local code = info.party and LobbyService.NormalizeCode(info.party) or nil
	if code and not LobbyService.PartyOf(ms.player) then
		local party = LobbyService.Parties[code]
		if party then
			if joinParty(party, ms.player) then
				notifyParty(party, { event = "joined", userId = ms.player.UserId, name = playerName(ms.player) })
			end
		else
			createParty(ms.player, code, t)
		end
	end
	dirty(ms)
	return mode
end

-- Nach dem Erscheinen der Figur (GarageServer.character -> moveTo(home) -> hier): außerhalb der Open World zur Zone.
function LobbyService.OnCharacter(ms: any): boolean
	if not ms or not ms.p or not ms.player.Character then
		return false
	end
	local mode = ms.p.mode
	if not GameConfig.ModeSet[mode] or mode == "openworld" then
		ms.arrivalPending = false
		return false
	end
	local ok = PlaceRouter.MoveToZone(ms.p, mode)
	if ok then
		ms.arrivalPending = false
	end
	return ok == true
end

-- Lobby-Station geöffnet (Attribut LobbyAction = mode_tycoon | mode_openworld | settings | party | tutorial):
-- Beginner-Hinweis ("station:<key>") einmalig, dazu mini_notice { kind = "lobby", action } für den Abschnitt in LobbyUI.
function LobbyService.OnStation(ms: any, station: any)
	local key = nil
	if typeof(station) == "Instance" then
		key = station:GetAttribute("LobbyAction")
		if type(key) ~= "string" then
			key = station.Name
		end
	elseif type(station) == "string" then
		key = station
	end
	if type(key) ~= "string" or key == "" then
		return
	end
	local d = ms.p.profile.data
	if key == "mode_tycoon" or key == "mode_openworld" then
		local mode = string.sub(key, 6)
		if Unlocks.Has(d, "mode:" .. mode) then
			ms.lobbyChoice = mode
		end
	end
	local data = { action = key }
	local hint = MetaRules.HintFor(d, "station:" .. key)
	if hint then
		data.hint = hint.text
		data.hintId = hint.id
		MetaRules.MarkHint(d, hint.id)
	end
	if api then
		api.notice(ms, "lobby", data)
	end
	dirty(ms)
end

function LobbyService.Tick(ms: any, d: any, t: number)
	if not finite(ms.playAt) then
		ms.playAt = t
		return
	end
	local dt = t - ms.playAt
	if dt >= 1 then
		local whole = math.floor(dt)
		MetaRules.AddPlaySeconds(d, whole)
		ms.playAt += whole
	end
end

function LobbyService.OnLeave(ms: any)
	if not ms then
		return
	end
	if LobbyService.Sessions[ms.player] == ms then
		LobbyService.Sessions[ms.player] = nil
	end
	removeFromParty(ms.player, "gone")
end

---------------------------------------------------------------- Snapshot (§11)
function LobbyService.SnapshotFields(ms: any, d: any, _t: number?, _full: boolean?): { [string]: any }
	local p = ms and ms.p or nil
	local mode = p and GameConfig.ModeSet[p.mode] and p.mode or MetaRules.Mode(d)
	local m = MetaRules.Meta(d)
	local settings = MetaRules.Settings(d)
	local party = ms and LobbyService.PartyOf(ms.player) or nil
	local partyField: any = false
	if party then
		local members = {}
		for _, member in ipairs(party.members) do
			table.insert(members, { userId = member.UserId, name = playerName(member), leader = member == party.leader })
		end
		partyField = {
			code = party.code,
			leader = party.leader.UserId,
			leaderName = playerName(party.leader),
			isLeader = ms ~= nil and party.leader == ms.player,
			members = members,
			max = GameConfig.Party.MaxMembers,
		}
	end
	return {
		mode = mode,
		placeKind = PlaceRouter.PlaceKind(),
		single = p and p.single == true or settings.single,
		-- true, wenn Reisen in diesem Place simuliert werden (Platzhalter-Ids, Studio oder alles in einem Place)
		simulated = not (PlaceRouter.WouldTeleport("tycoon") or PlaceRouter.WouldTeleport("openworld") or PlaceRouter.WouldTeleport("lobby")),
		choice = ms and ms.lobbyChoice or false,
		meta = {
			beginner = settings.beginner,
			passive = settings.passive,
			single = settings.single,
			tutorialDone = m and m.tutorialDone == true or false,
			tutorialStep = m and m.tutorialStep or 1,
		},
		party = partyField,
	}
end

return LobbyService
