-- MiniService: bindet Minispiele und Stadt an GarageServer (ein Eingang, eine Sitzung, ein Profil).
-- GarageServer ruft (MERGE_CONTRACT §3):
--   Init(ctx)          nach dem Laden: ctx = { emit, toast, changed, push, getSession, moveTo, now, callCustomer }
--                      (callCustomer(p, jobId) -> ok, msg: Kundenanruf des Handys, PhoneService/phone_call)
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
--   OnCharacter(p)     Ausbaustufe 4: nach dem Erscheinen der Figur (GarageServer.character, nach moveTo(home)):
--                      außerhalb der Open World zur Zonen-Ankunft (Lobby/Tycoon) versetzen
--   OnStation(p, key)  Ausbaustufe 4: 2.4.0-Plot-Station geöffnet (Tutorial-Schritt, Beginner-Hinweis)
-- Ausbaustufe 4 (PHASE4_CONTRACT §10–§12): Lobby/Party/Reise (LobbyService, PlaceRouter), Tutorial und
-- Beginner-Hinweise (TutorialService), Level & Prestige, Freischaltungen (PrestigeService), Tycoon
-- (TycoonService), Open-World-Gebäude und Passiv-Modus (OWService, Meilenstein 6), Story/Nebenmissionen/Co-op
-- (StoryService, Meilenstein 7). Jede Aktion, die etwas Freischaltbares nutzt, prüft Mini.Handle zentral über
-- Unlocks (ACTION_UNLOCK); Stationen über Unlocks.TabAllowed. Im Passiv-Modus (§5) blockt Mini.Handle Story-Start,
-- Kiesplatz-Verkauf und Auktionen (PASSIVE_BLOCKED, Hinweis über OWService.BlockIfPassive). Story-Ereignisse:
-- Statistiken über MiniRules.StatHook, Ereignisse aus Hinweisen der Dienste (notice -> storyEventOf; Spielhallen-Runden
-- nur gewertet, nicht abgebrochen/abgelehnt) und api.event; "action:<name>" nur, wenn der Handler true zurückgibt
-- (gelungener Tausch, gültiges Gebot, Wäsche, Tuning) – abgelehnte Absichten zählen nicht für Nebenmissionen.
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
local Unlocks = require(MiniShared:WaitForChild("Unlocks"))
local TutorialRules = require(MiniShared:WaitForChild("TutorialRules"))

local Server = script.Parent
local PressService = require(Server:WaitForChild("PressService"))
local TuningService = require(Server:WaitForChild("TuningService"))
local SideGamesService = require(Server:WaitForChild("SideGamesService"))
local GoalsService = require(Server:WaitForChild("GoalsService"))
local LeaderboardService = require(Server:WaitForChild("LeaderboardService"))
local MiniPasses = require(Server:WaitForChild("MiniPasses"))
local CityService = require(Server:WaitForChild("CityService"))
local AuctionService = require(Server:WaitForChild("AuctionService"))
local AuctionLedger = require(Server:WaitForChild("AuctionLedger"))
local CarService = require(Server:WaitForChild("CarService"))
local ArcadeService = require(Server:WaitForChild("ArcadeService"))
local PrestigeService = require(Server:WaitForChild("PrestigeService"))
local LobbyService = require(Server:WaitForChild("LobbyService"))
local PlaceRouter = require(Server:WaitForChild("PlaceRouter"))
local TutorialService = require(Server:WaitForChild("TutorialService"))
local TycoonService = require(Server:WaitForChild("TycoonService")) -- Meilenstein 4: Tycoon
local OWService = require(Server:WaitForChild("OWService")) -- Meilenstein 6: Open-World-Gebäude, Passiv-Modus
local StoryService = require(Server:WaitForChild("StoryService")) -- Meilenstein 7: Story, Kiesplatz, Nebenmissionen, Co-op
local ShopService = require(Server:WaitForChild("ShopService")) -- Meilenstein 8: Shop (Kosmetik, DLC-Autos, Pässe, Quittungen)
local StartService = require(Server:WaitForChild("StartService")) -- Startwahl in der Open World (vier Startwege)
local PhoneService = require(Server:WaitForChild("PhoneService")) -- Handy: Kunden eines Fahrzeug-Checks anrufen (phone_call)
local PublicWorkshopService = require(Server:WaitForChild("PublicWorkshopService")) -- 3.x: Große Werkstatt (pw_*)
local DevService = require(Server:WaitForChild("DevService")) -- 3.x: Entwickler-Menü (/dev, dev_open, dev_set)
local StoryRules = require(MiniShared:WaitForChild("StoryRules"))
local Profiles = require(Server.Parent:WaitForChild("Profiles"))

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

-- Große, selten geänderte Felder (Garage-Liste, Händlerkatalog) nur bei Änderungen (dirty), nach hello und
-- spätestens alle SnapshotFullInterval Sekunden; reine Produktions-Snapshots (Presse, 1×/s) lassen sie weg.
-- MiniClient übernimmt fehlende Felder aus dem vorigen Snapshot (MiniSnapshot.StickyKeys).
local SNAPSHOT_EXTRAS = {
	{ "Lobby", LobbyService.SnapshotFields },
	{ "Prestige", PrestigeService.SnapshotFields },
	{ "Tutorial", TutorialService.SnapshotFields },
	{ "Start", StartService.SnapshotFields }, -- start { path, pending, choices[] }
	{ "Tycoon", TycoonService.SnapshotFields }, -- tycoon { active, run, slot, offers, bonus, runsDone, rebirths, boost, plots }
	{ "OW", OWService.SnapshotFields }, -- ow { buildings{}, passive, perks, capHours }
	{ "Story", StoryService.SnapshotFields }, -- story { chapter, active, side[], sale, …; missions[]/chapters[] nur bei full }
	{ "Shop", ShopService.SnapshotFields }, -- shop { owned[], equipped{}, dlcCars[], passes{}; catalog nur bei full (§11 sticky) }
}

local function sendSnapshot(ms, t)
	local full = ms.dirty or t - (ms.fullSentAt or -math.huge) + EPSILON >= MiniConfig.SnapshotFullInterval
	ms.dirty = false
	ms.lastSent = t
	local snap = MiniSnapshot.Build(ms.p.profile.data, t, ms.passes, ms.quiz)
	if type(snap.press) == "table" then
		snap.press.clickAcks = table.clone(ms.clickAcks or {}) -- bestätigte Klickpakete (PressUI-Vorhersage)
	end
	-- Autos und Teststrecke (PHASE2_CONTRACT §5): cars, activeCar, catalog, spawnedCar, track, testdrive, …
	local okCars, fields = pcall(CarService.SnapshotFields, ms, ms.p.profile.data, t)
	if okCars and type(fields) == "table" then
		for k, v in pairs(fields) do
			snap[k] = v
		end
		if full then
			ms.fullSentAt = t
		else
			for _, key in ipairs(MiniSnapshot.StickyKeys) do
				snap[key] = nil
			end
		end
	elseif not okCars then
		warn("[Minispiele] Auto-Snapshot: " .. tostring(fields))
	end
	-- Ausbaustufe 4 (PHASE4_CONTRACT §11): mode/placeKind/meta/party, prestige/unlocks (unlocks.list nur bei full), tutorial
	for _, entry in ipairs(SNAPSHOT_EXTRAS) do
		local okX, extra = pcall(entry[2], ms, ms.p.profile.data, t, full)
		if okX and type(extra) == "table" then
			for k, v in pairs(extra) do
				snap[k] = v
			end
		elseif not okX then
			warn("[Minispiele] " .. entry[1] .. "-Snapshot: " .. tostring(extra))
		end
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

-- Story-Ereignis (StoryService.OnEvent) aus einem Hinweis eines Dienstes: Autokauf, Zeitfahren im Ziel, Zuschlag
-- in der Auktion (auch außerhalb von Handle, im Auktions-Tick), beendete Spielhallen-Runde, begonnener Gebäudebau.
local function storyEventOf(kind, data)
	if kind == "car_bought" then
		return "car_bought"
	elseif kind == "track_finish" and data.valid ~= false then
		return "track_finish"
	elseif kind == "auction_won" then
		return "auction_won"
	elseif kind == "arcade_result" and not data.replay and not data.expired and not data.aborted and not data.rejected then
		return "arcade_round" -- nur zu Ende gespielte, gewertete Runden (kein Sofort-Abbruch mit 0 Punkten)
	elseif kind == "ow_build" then
		return "ow_built:" .. tostring(data.typ)
	end
	return nil
end

local function notice(ms, kind, data)
	data = type(data) == "table" and data or {}
	data.kind = kind
	emit(ms, MiniNet.Events.Notice, data)
	-- 3.x: Willkommens-Flitzer steht neben dem neuen Spieler: Beginner-Hinweis „Taste G / Handy → Auto rufen“
	if kind == "car_spawned" and data.at == "intro" and ms.p and ms.p.profile then
		local okH, errH = pcall(TutorialService.Hint, ms, ms.p.profile.data, "car:intro")
		if not okH then
			warn("[Minispiele] Flitzer-Hinweis: " .. tostring(errH))
		end
	end
	local event = storyEventOf(kind, data)
	if event and ms.p and ms.p.profile then
		local ok, err = pcall(StoryService.OnEvent, ms, ms.p.profile.data, event, data)
		if not ok then
			warn("[Minispiele] Story-Ereignis " .. event .. ": " .. tostring(err))
		end
	end
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
	-- Hinweise, die Dienste vor 'hello' eingereiht haben (Freischaltungen, Tutorial-Schritt)
	pcall(PrestigeService.Flush, ms)
	pcall(TutorialService.Flush, ms)
	pcall(OWService.Flush, ms) -- offline fertig gewordene Bauten (ow_ready aus OnJoin)
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
-- Geld/Autos außerhalb von request() geändert (Auktions-Zuschlag im Tick): 2.4.0-Revision + Push
function api.changed(ms)
	ms.dirty = true
	if ctx and alive(ms) then
		ms.lastChanged = now()
		ms.changePending = false
		ctx.changed(ms.p)
	end
end
-- Sofort speichern (nach einer Auktions-Übergabe). Ein laufendes Speichern (Autosave) enthält die Änderung
-- evtl. nicht: erst abwarten, dann selbst speichern. Beim Verlassen speichert PlayerRemoving (release).
function api.save(ms)
	local p = ms.p
	task.spawn(function()
		for _ = 1, 3 do
			local prof = p.profile
			local deadline = os.clock() + 15
			while prof.saving and os.clock() < deadline do
				task.wait(0.2)
			end
			if p.closing or not prof.writable or prof.receiptPending then
				return
			end
			if Profiles.Save(prof, false) then
				return
			end
			task.wait(2)
		end
	end)
end
-- Story-Ereignis eines Dienstes (z. B. AuctionService "auction_consigned"): Missionen und Co-op (StoryService.OnEvent)
function api.event(ms, event, data)
	if ms and ms.p and ms.p.profile then
		StoryService.OnEvent(ms, ms.p.profile.data, event, data)
	end
end
-- 3.x: Story-Ereignis der Großen Werkstatt ("pw_repair" { car, gain }, "pw_parts_sold" { part, count, value }) –
-- auch aus dem Tick (Reparatur fertig), also außerhalb von Handle: Snapshot als geändert markieren
function api.storyEvent(ms, name, data)
	api.event(ms, name, data)
	if ms then
		ms.dirty = true
	end
end
-- 3.x: Startweg zurücksetzen (Entwickler-Menü; nur nach DevService.IsDev): Rückgabe true/false
function api.resetStart(ms, d)
	return StartService.ResetStart(ms, d) == true
end
-- Auktions-Übergabe ins Auktionsbuch schreiben (vor dem Speichern beider Profile; darf warten)
function api.recordTransfer(transfer)
	return AuctionLedger.Record(transfer)
end
-- Handy (PhoneService): Kunden anrufen über GarageServer.callCustomer (ctx aus Mini.Init). Rückgabe ok, Meldung
function api.callCustomer(p, id)
	if ctx and type(ctx.callCustomer) == "function" then
		return ctx.callCustomer(p, id)
	end
	return false, nil
end
-- Eingeliefertes Auto von der Straße holen
function api.releaseCar(ms, id)
	return CarService.ReleaseCar(ms.player, id, "auction")
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

---------------------------------------------------------------- Freischaltungen (PHASE4_CONTRACT §3, §12)
-- Aktion -> Schlüssel in GameConfig.Unlocks (oder Funktion der geprüften Nutzlast). Eine Prüfung je Aktion:
-- fehlt die Freischaltung, antwortet der Server mit einem freundlichen Toast (höchstens alle LOCK_TOAST_SECONDS
-- je Aktion, damit Klickpakete der Presse nicht zweimal je Sekunde mahnen) und führt nichts aus.
local ACTION_UNLOCK = {
	mini_press_click = "feature:press",
	mini_press_buy = "feature:press", -- Maschinen, Händler und Rebirth der Presse erst mit der Presse (nicht nur der Klick)
	mini_press_exchange = "feature:press",
	mini_press_rebirth = "feature:press",
	mini_scrapyard_buy = "feature:scrapyard",
	mini_quiz_new = "feature:quiz",
	mini_parking_new = "feature:parking",
	mini_tuning_start = "feature:tuning",
	mini_tuning_collect = "feature:tuning",
	mini_tuning_idle = "feature:tuning", -- passive Einnahmen gehören zu den Tuning-Projekten (TuningService sammelt vorher nicht)
	mini_track_start = "feature:track",
	mini_carwash = "feature:carwash",
	mini_arcade_start = "feature:arcade",
	-- Auktion: NPC-Lose ab feature:auction (12), Lose anderer Spieler erst mit auction:player (20) – wie das Einliefern
	mini_auction_bid = function(clean)
		local lot = AuctionService.Lot and AuctionService.Lot(clean.lot) or nil
		if type(lot) == "table" and lot.kind == "player" then
			return "auction:player"
		end
		return "feature:auction"
	end,
	mini_auction_consign = "auction:player",
	mini_car_testdrive = "feature:dealer",
	-- Minispiel-Ausbau: Tuning-Abteilung mit den Tuning-Projekten, Schrottplatz-Ausbau mit dem Schrottplatz
	mini_upgrade = function(clean)
		if clean.key == "scrapyardLevel" then
			return "feature:scrapyard"
		elseif clean.key == "tuningLevel" then
			return "feature:tuning"
		end
		return nil -- unbekannte Schlüssel meldet MiniRules.BuyUpgrade selbst
	end,
	mini_car_buy = function(clean)
		local key = "car:" .. tostring(clean.model)
		return Unlocks.Known(key) and key or nil -- unbekannte Modelle meldet CarRules.Buy selbst
	end,
	-- Open-World-Gebäude (Meilenstein 6): building:<typ> (Autohaus 10, Schrottplatz 18, Produktion 30 – wie Kapitel 4);
	-- werkstatt und unbekannte Typen beantwortet OWService selbst
	ow_build = function(clean)
		local key = "building:" .. tostring(clean.typ)
		return Unlocks.Known(key) and key or nil
	end,
	-- Story (Meilenstein 7): Kapitel der Mission (story:<n>); unbekannte Ids meldet StoryRules.Start selbst
	story_start = function(clean)
		local def = StoryRules.Mission(clean.id)
		local key = def and ("story:" .. tostring(def.chapter)) or nil
		return key and Unlocks.Known(key) and key or nil
	end,
}
local LOCK_TOAST_SECONDS = 3

-- Passiv-Modus (PHASE4_CONTRACT §5, §7): nur Zuschauen/Handeln – keine Missionen, keine Story, keine Auktionen.
-- Abholen (story_claim, side_claim) und Gebäude bleiben erlaubt; der Hinweis kommt gedrosselt aus OWService.
local PASSIVE_BLOCKED = {
	story_start = true,
	story_sell = true,
	mini_auction_bid = true,
	mini_auction_consign = true,
}

local function lockedText(entry)
	return "Ab Level " .. tostring(entry.level) .. ": " .. tostring(entry.title) .. ". Bis dahin: Aufträge in der Werkstatt bringen XP!"
end

-- Rückgabe: true, wenn die Aktion erlaubt ist; sonst Toast (gedrosselt) und false
local function unlocked(ms, action, clean, d, t)
	local key = ACTION_UNLOCK[action]
	if type(key) == "function" then
		key = key(clean)
	end
	if not key then
		return true
	end
	local entry = Unlocks.Entry(key)
	if not entry then
		warn("[Minispiele] Unbekannte Freischaltung für " .. action .. ": " .. tostring(key))
		return false
	end
	if Unlocks.Has(d, key) then
		return true
	end
	ms.lockToastAt = ms.lockToastAt or {}
	local last = ms.lockToastAt[action]
	if not last or t - last >= LOCK_TOAST_SECONDS then
		ms.lockToastAt[action] = t
		if ctx then
			ctx.toast(ms.p, lockedText(entry))
		end
	end
	return false
end

-- Moduswechsel der Sitzung (PlaceRouter setzt p.mode): beim ersten Betreten der Open World startet das Tutorial
local function checkMode(ms, d)
	local mode = ms.p.mode
	if mode == ms.modeSeen then
		return
	end
	ms.modeSeen = mode
	if mode == "openworld" then
		-- Startwahl zuerst: ein neues Profil wählt seinen Startweg, das Tutorial wartet so lange (TutorialRules.Waiting)
		local okSt, errSt = pcall(StartService.OnMode, ms, d, mode)
		if not okSt then
			warn("[Minispiele] Startwahl: " .. tostring(errSt))
		end
		local ok, err = pcall(TutorialService.Start, ms, d, mode)
		if not ok then
			warn("[Minispiele] Tutorial-Start: " .. tostring(err))
		end
	end
	-- Tycoon: Grundstück belegen/freigeben, Durchlauf fortsetzen (TycoonService.Tick holt es sonst nach)
	local okY, errY = pcall(TycoonService.OnMode, ms, d, mode)
	if not okY then
		warn("[Minispiele] Tycoon-Modus: " .. tostring(errY))
	end
	-- Story: außerhalb der Open World kein Kunde am Kiesplatz, keine Lieferfahrt
	local okS, errS = pcall(StoryService.OnMode, ms, d, mode)
	if not okS then
		warn("[Minispiele] Story-Modus: " .. tostring(errS))
	end
end

-- Reisen in die Stadt aus Lobby oder Schnellem Spiel (Stadtplan, Autos, Strecke, Waschstraße, 2.4.0-Tablet
-- „Zum Ziel“/Stationen): ohne Moduswechsel stünde die Figur mit p.mode = "lobby"/"tycoon" in der Open World –
-- kein Tutorial, kein Kiesplatz-Kunde, Tycoon-Geld liefe weiter. Im all-Place wechselt der Server deshalb zuerst den
-- Modus (PlaceRouter.Simulate: Modus, lastMode, Ankunft, mini_notice "mode"), danach Tutorial/Tycoon/Story
-- (checkMode); die Aktion läuft dann normal weiter. In einzelnen Places (Lobby/Tycoon) gibt es die Stadt nicht:
-- Hinweis, die Aktion entfällt.
local CITY_ACTIONS = {
	mini_travel = true,
	mini_car_spawn = true,
	mini_car_testdrive = true,
	mini_track_start = true,
	mini_carwash = true,
}
Mini.CityActions = CITY_ACTIONS

-- mini_travel führt nur dann in die Stadt, wenn das Ziel die eigene Werkstatt oder ein Ankunftspunkt der Stadt ist
-- (Ankunftspunkte der Lobby/des Tycoon-Geländes bleiben in ihrer Zone, CityService.Travel)
local function needsOpenWorld(action, clean)
	if not CITY_ACTIONS[action] then
		return false
	end
	if action ~= "mini_travel" then
		return true
	end
	local key = clean.key
	if key == "workshop" or key == "home" then
		return true
	end
	local city = workspace:FindFirstChild("City")
	local arrivals = city and city:FindFirstChild("Arrivals")
	if arrivals and arrivals:FindFirstChild(key) then
		return true
	end
	-- Ziel nur in Lobby/Tycoon (oder unbekannt: CityService.Travel meldet selbst)
	return false
end
local TEXT_OPENWORLD_ONLY = "Das geht nur in der Open World – reise über die Lobby dorthin („Los geht's: Open World“)."

-- Rückgabe: true, wenn die Aktion weiterlaufen darf (schon in der Open World oder gerade dorthin gewechselt)
local function ensureOpenWorld(ms, d)
	local p = ms.p
	local mode = p.mode
	if mode ~= "lobby" and mode ~= "tycoon" then
		return true
	end
	if PlaceRouter.PlaceKind() ~= "all" then
		if ctx then
			ctx.toast(p, TEXT_OPENWORLD_ONLY)
		end
		return false
	end
	local ok = PlaceRouter.Simulate(p, "openworld", { single = p.single == true })
	if not ok then
		return false -- Zone fehlt in diesem Place (Simulate zeigt den Hinweis)
	end
	ms.lobbyChoice = nil
	ms.arrivalPending = false
	if ctx then
		ctx.toast(p, PlaceRouter.ArrivedText("openworld"))
	end
	checkMode(ms, d) -- Tycoon verlassen, Tutorial starten, Story/Kiesplatz an
	ms.dirty = true
	return true
end

-- Für GarageServer (2.4.0-Tablet: travel/target): true = weiter, false = abgelehnt (Hinweis schon gezeigt)
function Mini.EnsureOpenWorld(p)
	if not ctx or not p or not p.profile or type(p.profile.data) ~= "table" then
		return true
	end
	local ms = stateFor(p)
	local ok, res = pcall(ensureOpenWorld, ms, p.profile.data)
	if not ok then
		warn("[Minispiele] Moduswechsel vor der Reise: " .. tostring(res))
		return true
	end
	if ms.p.mode == "openworld" then
		flush(ms, now())
	end
	return res
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
-- Für GarageServer.moveTo: Figur vor PivotTo aus einem Fahrzeugsitz lösen (SeatWeld sofort weg)
Mini.Unseat = CityService.Unseat

-- Für GarageServer.join direkt nach P.Load (vor dem Sitzungsstart; darf warten): Auktions-Übergaben abgleichen,
-- deren Speichern nur bei einem der beiden Profile gelandet ist (AuctionLedger). Nur schreibbare Profile.
function Mini.Reconcile(player, profile)
	if not profile or not profile.writable or type(profile.data) ~= "table" then
		return 0
	end
	local ok, n = pcall(AuctionLedger.Reconcile, player.UserId, profile.data)
	if not ok then
		warn("[Auktion] Abgleich beim Laden: " .. tostring(n))
		return 0
	end
	return n
end

function Mini.Handles(action)
	return MiniNet.IsAction(action)
end

-- Rückgabe (für Tests): "ok" | "invalid" | "cooldown" | "duplicate" | "error" | "dropped" | "locked" | "passive" | "mode"
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
	if not unlocked(ms, action, clean, p.profile.data, t) then
		return "locked" -- Freischaltung fehlt (Toast gedrosselt), nichts ausgeführt
	end
	if PASSIVE_BLOCKED[action] and OWService.BlockIfPassive(ms, p.profile.data, t) then
		return "passive" -- Passiv-Modus (Hinweis gedrosselt), nichts ausgeführt
	end
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
	if needsOpenWorld(action, clean) and not ensureOpenWorld(ms, d) then
		ms.dirty = true
		flush(ms, t)
		return "mode" -- nur in der Open World (einzelner Lobby-/Tycoon-Place), nichts ausgeführt
	end
	local money = d.money
	ms.worldChanged = false
	local ok, err = pcall(handler, ms, clean, d, t)
	if not ok then
		warn("[Minispiele] " .. action .. ": " .. tostring(err))
	else
		local succeeded = err == true -- Rückgabe true = Aktion wirklich gelungen (Tausch, Gebot, Wäsche, Tuning …)
		-- Tutorial-Schritte "action:<name>" nur nach einer gelungenen Aktion (Handler gibt true zurück, wie bei den
		-- Nebenmissionen): ein abgelehntes Abholen/Verkaufen erledigt keinen Schritt. mini_travel meldet sich selbst
		-- (nur bei gelungener Reise). Dazu der Beginner-Hinweis "first:dismantled"; danach ein eventueller Moduswechsel.
		local okT, errT = pcall(function()
			if succeeded and action ~= "mini_travel" then
				TutorialService.OnEvent(ms, d, "action:" .. action)
			end
			if action == "mini_scrapyard_dismantle" then
				TutorialService.OnStat(ms, d, "dismantled")
			end
			-- Nebenmissionen "action:<name>" (Gebote, Waschstraße, Tauschgeschäfte, Tuning am Auto): nur nach einer
			-- gelungenen Aktion (Handler gibt true zurück) – abgelehnte Absichten (kein Schrott, kein Auto, ungültiges
			-- Gebot) melden sich nur per Toast und zählen nicht (Vertrag §7)
			if succeeded then
				StoryService.OnEvent(ms, d, "action:" .. action, clean)
			end
			checkMode(ms, d)
		end)
		if not okT then
			warn("[Minispiele] Tutorial nach " .. action .. ": " .. tostring(errT))
		end
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
	AuctionService.Hello(ms)
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
		CarService.OnJoin(ms, d, t)
		ArcadeService.OnJoin(ms, d, t)
		AuctionService.OnJoin(ms)
		-- Ausbaustufe 4: Level/Rang merken, Tutorial-Stand, Anfangsmodus (PlaceKind, lastMode, TeleportData)
		PrestigeService.OnJoin(ms, d, t)
		local mode = LobbyService.OnJoin(ms, d, t) -- setzt p.mode (das Tutorial richtet sich danach)
		StartService.OnJoin(ms, d, t) -- Veteranen ohne Startweg -> werkstatt, bevor das Tutorial den Weg liest
		TutorialService.OnJoin(ms, d, t)
		TycoonService.OnJoin(ms, d, t) -- Sitzung merken; im Modus tycoon sofort Grundstück + Modelle
		OWService.OnJoin(ms, d, t) -- Gebäude am Grundstück, offline fertige Bauten
		StoryService.OnJoin(ms, d, t) -- Story-Sitzung, Tageswechsel der Nebenmissionen, erster Kunde
		PublicWorkshopService.OnJoin(ms, d, t) -- 3.x: Große Werkstatt (games.pw normalisieren, Erstattungen)
		DevService.OnJoin(ms, d, t) -- 3.x: Entwickler-Menü (Sitzung, Player.Chatted „/dev“)
		ShopService.OnJoin(ms, d, t) -- Shop-Sitzung, Pass-Besitz (kann warten) -> Kosmetik gutschreiben
		ms.modeSeen = nil
		checkMode(ms, d) -- Open World: Pflicht-Tutorial beim ersten Beitritt (TutorialRules.ShouldStart)
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
		TuningService.Tick(ms, d, t) -- ohne Tuning-Freischaltung sammeln sich keine passiven Einnahmen an
		-- Autos: Probefahrt-Ende, Leerlauf/verlorene Autos, Zeitfahren-Timeout, Nitro, zurückgehaltene Belohnung
		local okCars, errCars = pcall(CarService.Tick, ms, d, t)
		if not okCars then
			warn("[Minispiele] Autos: " .. tostring(errCars))
		end
		AuctionService.Tick(t) -- global; Mehrfachaufrufe im selben Tick entfallen
		if GoalsService.Tick(ms, d, t) then
			ms.dirty = true
		end
		-- Ausbaustufe 4: Level-Aufstiege (Freischaltungen, Prestige-Rang), Tutorial-Auftragsschritte, Spielzeit
		local okP, resP = pcall(PrestigeService.Tick, ms, d, t)
		if okP then
			if resP then
				ms.dirty = true
			end
		else
			warn("[Minispiele] Prestige: " .. tostring(resP))
		end
		local okT, resT = pcall(TutorialService.Tick, ms, d, t)
		if okT then
			if resT then
				ms.dirty = true
			end
		else
			warn("[Minispiele] Tutorial: " .. tostring(resT))
		end
		pcall(LobbyService.Tick, ms, d, t)
		checkMode(ms, d)
		-- Tycoon: Produktion (0,5 s), Anzeigen, Angebots-Ablauf; true = Snapshot fällig (höchstens 1×/s)
		local okY, resY = pcall(TycoonService.Tick, ms, d, t)
		if okY then
			if resY then
				ms.dirty = true
			end
		else
			warn("[Minispiele] Tycoon: " .. tostring(resY))
		end
		-- Open World: Bauten fertig (Modell, ow_ready), Baustellen-Countdown; true = Snapshot fällig (höchstens 1×/s)
		local okO, resO = pcall(OWService.Tick, ms, d, t)
		if okO then
			if resO then
				ms.dirty = true
			end
		else
			warn("[Minispiele] Gebäude: " .. tostring(resO))
		end
		-- Story: Tageswechsel, Kunden am Kiesplatz, Bedingungs-Missionen, Lieferfahrten
		local okS, resS = pcall(StoryService.Tick, ms, d, t)
		if okS then
			if resS then
				ms.dirty = true
			end
		else
			warn("[Minispiele] Story: " .. tostring(resS))
		end
		-- 3.x: Große Werkstatt: laufende Reparatur (Abstand, Abschluss; nie Geld)
		local okW, resW = pcall(PublicWorkshopService.Tick, ms, d, t)
		if okW then
			if resW then
				ms.dirty = true
			end
		else
			warn("[Minispiele] Große Werkstatt: " .. tostring(resW))
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
		local d = p.profile.data
		MiniRules.AddStat(d, "jobsDone", 1, now())
		if ms then
			TutorialService.OnEvent(ms, d, "settled") -- Tutorial-Schritt „Abrechnen“
			TutorialService.OnStat(ms, d, "jobsDone") -- Beginner-Hinweis zum ersten Auftrag
			StoryService.OnEvent(ms, d, "settle") -- Story-Mission „Zurück in die Werkstatt“ (jobsDone kommt über StatHook)
		end
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
	pcall(TutorialService.OnLeave, ms, p.profile.data) -- zurückgehaltene Tutorial-Belohnung vor P.Save
	pcall(LobbyService.OnLeave, ms) -- Party verlassen (Leiterwechsel)
	pcall(TycoonService.OnLeave, ms) -- Grundstück frei, Angebote weg (der Durchlauf bleibt im Profil)
	pcall(OWService.OnLeave, ms) -- Gebäude-Modelle abbauen (Bauzeit läuft im Profil weiter)
	pcall(StoryService.OnLeave, ms) -- Story-Sitzung vergessen (Kunde, Lieferung)
	pcall(ShopService.OnLeave, ms) -- Shop-Sitzung vergessen
	pcall(PublicWorkshopService.OnLeave, ms) -- 3.x: laufende Reparatur pausieren (bezahlt bleibt bezahlt)
	pcall(DevService.OnLeave, ms) -- 3.x: Chat-Verbindung lösen
	local okAuction, errAuction = pcall(AuctionService.OnLeave, ms) -- vor P.Save: Verkäufer-Lose abbrechen
	if not okAuction then
		warn("[Minispiele] Auktion verlassen: " .. tostring(errAuction))
	end
	pcall(ArcadeService.OnLeave, ms)
	local okCars, errCars = pcall(CarService.OnLeave, ms) -- Autos abbauen, zurückgehaltene Belohnung vor P.Save
	if not okCars then
		warn("[Minispiele] Autos verlassen: " .. tostring(errCars))
	end
	if ms.offlinePending then
		-- Verlassen vor Ende der Game-Pass-Prüfung: Offline-Ertrag jetzt (ohne Pass-Bonus) verbuchen.
		local offline = ms.offlinePending
		ms.offlinePending = nil
		pcall(PressService.ApplyOffline, ms, p.profile.data, offline, now())
	end
	pcall(PressService.Tick, ms, p.profile.data, now())
	Mini.Leaving[p] = { ms = ms, writable = wasWritable == true and not p.profile.receiptPending }
end

-- Robux-Quittung verbucht (Purchases.Init-Rückruf in GarageServer): Hinweis, Snapshot, Optik (Credits-Pakete
-- meldet GarageServer über purchaseFX; ShopService ignoriert kind "credits"). result = ShopRules.ApplyReceipt-
-- Ergebnis (Rückerstattung). Rückgabe true = ShopService hat die Änderung gemeldet (api.changed) – GarageServer
-- ruft changed(p) dann nicht noch einmal auf (eine Revision, ein Push je Quittung).
function Mini.OnGranted(p, product, result): boolean
	local ok, res = pcall(ShopService.OnGranted, p, product, result)
	if not ok then
		warn("[Shop] Quittung melden: " .. tostring(res))
		return false
	end
	return res == true
end

-- Robux-Quittung aufgeschoben (Garage voll): einmaliger Hinweis an den Spieler (Purchases wiederholt selbst)
function Mini.OnDeferred(p, product, reason)
	local ok, err = pcall(ShopService.OnDeferred, p, product, reason)
	if not ok then
		warn("[Shop] Aufgeschobene Quittung melden: " .. tostring(err))
	end
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

-- Figur erschienen (GarageServer.character nach moveTo(home)): Lobby/Tycoon-Spieler zur Zonen-Ankunft.
function Mini.OnCharacter(p)
	local ms = Mini.Sessions[p.player]
	if not ms or ms.p ~= p or p.closing then
		return
	end
	local ok, err = pcall(LobbyService.OnCharacter, ms)
	if not ok then
		warn("[Minispiele] Figur: " .. tostring(err))
	end
	-- Startwahl offen: bei der nächsten Ankunft in der Spielermeile kommt die Startwahl wieder
	local okS, errS = pcall(StartService.OnArrive, ms, p.profile.data)
	if not okS then
		warn("[Minispiele] Startwahl: " .. tostring(errS))
	end
end

-- 2.4.0-Plot-Station geöffnet (World.Create-Rückruf "station" bzw. act 'travel'): Tutorial-Schritt
-- "station:<key>" (Empfang) und Beginner-Hinweis (z. B. h_workshop). Kein Geld, nur Hinweise.
function Mini.OnStation(p, key)
	local ms = stateFor(p)
	if not ms or p.closing or type(key) ~= "string" then
		return
	end
	local ok, err = pcall(TutorialService.OnStation, ms, p.profile.data, key, nil)
	if not ok then
		warn("[Minispiele] Station " .. key .. ": " .. tostring(err))
	end
	flush(ms, now())
end

---------------------------------------------------------------- Stationen, Reisen, Ausbau
local function openStation(p, tab, station)
	local ms = stateFor(p)
	if not ms or p.closing then
		return
	end
	local d = p.profile.data
	local key = station and station.Name or tab
	if tab == "lobby" then
		-- Lobby-Station (Attribut LobbyAction = mode_tycoon | mode_openworld | settings | party | tutorial):
		-- LobbyService wählt den Modus vor und schickt mini_notice { kind = "lobby", action, hint? }; der Tab öffnet
		-- mit der gedrückten Aktion (LobbyUI springt zum Abschnitt).
		local action = station and station:GetAttribute("LobbyAction")
		pcall(LobbyService.OnStation, ms, station or tab)
		pcall(TutorialService.OnEvent, ms, d, "tab:lobby")
		emit(ms, MiniNet.Events.Open, { tab = tab, action = type(action) == "string" and action or nil })
		flush(ms, now())
		return
	end
	-- Tutorial-Schritte "tab:<tab>" (Autohaus, Infotafel) und Beginner-Hinweise "station:<key>" (Stadtplan, Credit-Center).
	-- Verlangt der aktuelle Tutorial-Schritt genau diese Station, öffnet der Tab auch ohne Level-Freischaltung
	-- (nur ansehen; Kauf/Probefahrt bleiben über ACTION_UNLOCK gesperrt) – sonst bekäme ein Level-1-Spieler am
	-- Autohaus nur den Sperr-Toast, während der Schritt abgehakt wird.
	local wanted = TutorialRules.Current(d, p.mode)
	local tutorialWants = wanted ~= nil and wanted.event == "tab:" .. tostring(tab)
	pcall(TutorialService.OnStation, ms, d, key, tab)
	if tab == "shop" then
		-- Credit-Center: Tab "shop" (Meilenstein 8: Credits-Pakete, DLC-Autos, Kosmetik, Pässe); der 2.4.0-Credits-Shop
		-- bleibt als Tablet-Seite "shop" erreichbar (ShopUI verlinkt ihn, Tablet-Navigation).
		emit(ms, MiniNet.Events.Open, { tab = tab })
	elseif MiniNet.TabSet[tab] and not Unlocks.TabAllowed(d, tab) and not tutorialWants then
		api.toast(ms, lockedText(Unlocks.ForTab(tab)))
	elseif MiniNet.TabSet[tab] then
		-- Spielhalle: der Automat (Attribut GameKey/Game bzw. Stationsname arcade_N) wird gleich ausgewählt
		local game = nil
		if tab == "arcade" and station then
			game = station:GetAttribute("Game") or station:GetAttribute("GameKey")
			if type(game) ~= "string" and string.match(station.Name, "^arcade_%d+$") then
				game = station.Name
			end
		end
		emit(ms, MiniNet.Events.Open, { tab = tab, game = type(game) == "string" and game or nil })
	elseif tab == "workshop" or tab == "home" then
		CityService.Travel(p, "workshop", ctx.moveTo)
	else
		api.toast(ms, MiniLocale.T("coming_soon", CityService.Title(station, tab)))
	end
	flush(ms, now())
end

Actions.Register("mini_upgrade", function(ms, data, d)
	local ok, res = MiniRules.BuyUpgrade(d, data.key, data.level)
	api.toast(ms, ok and (res.name .. " verbessert.") or res)
end)

Actions.Register("mini_travel", function(ms, data, d)
	local ok, msg = CityService.Travel(ms.p, data.key, ctx.moveTo)
	if not ok then
		api.toast(ms, msg)
	else
		TutorialService.OnEvent(ms, d, "action:mini_travel") -- Tutorial-Schritt „Stadtplan“ nur bei gelungener Reise
	end
end)

Actions.Register("mini_pass_prompt", function(ms, data)
	local _, msg = MiniPasses.Prompt(ms.player, data.pass, ms.passes)
	api.toast(ms, msg)
end)

Actions.Register("mini_sync", function(ms)
	flushNotices(ms)
	AuctionService.Hello(ms)
	if not ms.boardSent then
		pushBoard(ms)
	end
end)

PressService.Register(Actions, api)
TuningService.Register(Actions, api)
SideGamesService.Register(Actions, api)
GoalsService.Register(Actions, api)
LeaderboardService.Register(Actions, api)
AuctionService.Register(Actions, api)
CarService.Register(Actions, api)
ArcadeService.Register(Actions, api)
PrestigeService.Register(Actions, api)
LobbyService.Register(Actions, api)
TutorialService.Register(Actions, api)
TycoonService.Register(Actions, api)
OWService.Register(Actions, api)
StoryService.Register(Actions, api)
ShopService.Register(Actions, api)
StartService.Register(Actions, api)
PhoneService.Register(Actions, api)
PublicWorkshopService.Register(Actions, api) -- 3.x: pw_open, pw_repair, pw_sell_parts (ab Level 1, jeder Startweg)
DevService.Register(Actions, api) -- 3.x: dev_open, dev_set (DevService.IsDev bei jedem Aufruf)

for name in pairs(MiniNet.Actions) do
	assert(Mini.Handlers[name], "Kein Handler für " .. name)
end

-- Statistiken (MiniRules.AddStat aus Regeln und Diensten) -> Story-/Nebenmissionen und Co-op. Die Sitzung wird über
-- das Profil gefunden (höchstens 8 Sitzungen je Server); Profile ohne Sitzung (Tests der reinen Regeln) bleiben still.
MiniRules.StatHook = function(d, key, amount)
	for _, ms in pairs(Mini.Sessions) do
		if ms.p and ms.p.profile and ms.p.profile.data == d then
			StoryService.OnStat(ms, d, key, amount)
			return
		end
	end
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
	CarService.Init(c)
	LobbyService.Init(c) -- PlaceRouter (Teleport/Simulation) bekommt emit/toast/moveTo/now
	TycoonService.Init(c) -- Start-/Sammel-Pads aller Grundstücke (workspace.Tycoon.Plots)
	OWService.Init(c)
	StoryService.Init(c)
	ShopService.Init(c) -- PromptGamePassPurchaseFinished; purchasePrompt über c.emit
	StartService.Init(c)
	PublicWorkshopService.Init(c)
	DevService.Init(c) -- TextChatCommand „/dev“, Gruppenbesitzer im Hintergrund
end

return Mini
