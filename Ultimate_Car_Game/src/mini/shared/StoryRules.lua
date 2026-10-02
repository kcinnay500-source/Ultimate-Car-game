-- StoryRules: Story „Vom Kiesplatzhändler zum Mega-Verkäufer“, Kiesplatz-Verkauf, Nebenmissionen und Co-op-Regeln
-- (docs/PHASE4_CONTRACT.md §2, §7). Rein: keine Instanzen, keine Dienste, keine Zeit (now kommt immer von außen).
-- Daten: d.games.story = { chapter, step, done = { [missionId] = true }, side = { [id] = { n, day, claimed } },
--                          active = false | { id, progress, startedAt, party }, sales = { n, best, special, serial, nextAt }, title }
-- sales.nextAt = Serverzeit (os.time) des nächsten Kiesplatz-Kunden: der Takt (OfferInterval/FailInterval) überlebt
-- Moduswechsel und Rejoin (StoryService setzt ihn nur über ScheduleNext/OfferGone).
-- chapter/step werden beim Laden und nach jeder Abholung aus `done` neu bestimmt (Kapitel der Reihe nach, step = erste
-- offene Mission). Zahlen und Texte: GameConfig.Story.
-- Geld/XP ändern nur Claim, SideClaim und Sell (über MiniRules.AddMoney/AddIncome/GainXP); MiniRules wird erst beim
-- Aufruf geladen (MiniRules lädt dieses Modul für Default/Load – kein Ring beim require).
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local Unlocks = require(script.Parent:WaitForChild("Unlocks"))
local C = require(script.Parent.Parent:WaitForChild("Config"))
local MiniLocale = require(script.Parent:WaitForChild("MiniLocale"))

local StoryRules = {}

export type Reward = { credits: number, xp: number?, cosmetic: string?, title: string? }
export type Mission = {
	id: string, title: string, text: string, kind: string, target: number, reward: Reward?, minutes: number?,
	stat: string?, absolute: boolean?, event: string?, events: { string }?, maxTime: number?,
	tier: number?, special: boolean?, typ: string?, stage: number?, money: number?, bays: number?, cars: { string }?,
	equipmentAll: boolean?, credits: number?, xp: number?, chapter: number?, index: number?, side: boolean?, legend: boolean?,
	unlock: string?, needsCar: boolean?,
}
export type Chapter = { id: number, title: string, intro: string, unlockLevel: number, Missions: { Mission } }
export type Active = { id: string, progress: number, startedAt: number, party: number }
export type SideEntry = { n: number, day: string, claimed: boolean }
export type Story = {
	chapter: number, step: number, done: { [string]: boolean }, side: { [string]: SideEntry }, active: Active | boolean,
	sales: { n: number, best: number, special: number, serial: number, nextAt: number }, title: string,
}
export type Change = { id: string, progress: number, target: number, done: boolean, side: boolean, delta: number, title: string }
export type Offer = {
	serial: number, customer: string, wants: string, wantsName: string, line: string, special: boolean, roll: number,
	tiers: { { tier: number, label: string, profit: number, price: number, chance: number, hint: string } },
}
export type SellResult = { sold: boolean, credits: number, xp: number, text: string, tier: number, special: boolean, changed: { Change } }

local MAX_SAFE = 2 ^ 53
local DAY_PATTERN = "^%d%d%d%d%-%d%d%-%d%d$"
local LEGEND_DAY = "legend"

---------------------------------------------------------------- Hilfen
local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function loadInt(v: any, default: number, min: number, max: number): number
	if not finite(v) or v < min then
		return default
	end
	return math.floor(math.min(v, max))
end

local MiniRules = nil
local function mini(): any
	if not MiniRules then
		MiniRules = require(script.Parent:WaitForChild("MiniRules"))
	end
	return MiniRules
end

local function hash(s: string): number
	local h = 5381
	for i = 1, #s do
		h = (h * 33 + string.byte(s, i)) % 2147483647
	end
	return h
end

-- Nicht-lineare Mischung von Tages-Hash und Ziehungsnummer k (Quadrat modulo 2^31−1, exakt unter 2^53): ein affiner
-- Schritt (hash(day .. k)) ergäbe nur benachbarte Pool-Indizes und damit nur #Pool verschiedene Tagesauswahlen.
local function scramble(h: number, k: number): number
	for _ = 1, 2 do
		h = h % 67108864 -- 2^26: das Quadrat bleibt unter 2^53
		h = (h * h + k * 7919 + 104729) % 2147483647
	end
	return h
end

local function dayKey(now: number): string
	return os.date("!%Y-%m-%d", math.floor(now))
end
StoryRules.DayKey = dayKey

---------------------------------------------------------------- Konfiguration (GameConfig.Story)
local cache = nil
local function config(): any
	return GameConfig.Story
end
StoryRules.Config = config

-- Nachschlagetabellen (einmal je Konfigurationstabelle)
local function index(): any
	local S = config()
	if cache and cache.S == S then
		return cache
	end
	local ix = { S = S, missionById = {}, chapterOf = {}, sideById = {}, legendIds = {}, poolIds = {} }
	for ci, ch in ipairs(S.Chapters) do
		for mi, m in ipairs(ch.Missions) do
			m.chapter = ci
			m.index = mi
			ix.missionById[m.id] = m
			ix.chapterOf[m.id] = ci
		end
	end
	for _, m in ipairs(S.Side.Pool or {}) do
		m.side = true
		ix.sideById[m.id] = m
		table.insert(ix.poolIds, m.id)
	end
	for _, m in ipairs(S.Side.Legend or {}) do
		m.side = true
		m.legend = true
		ix.sideById[m.id] = m
		table.insert(ix.legendIds, m.id)
	end
	cache = ix
	return ix
end

function StoryRules.Chapter(n: any): Chapter?
	local S = config()
	return type(n) == "number" and S.Chapters[n] or nil
end

function StoryRules.ChapterCount(): number
	return #config().Chapters
end

function StoryRules.Mission(id: any): Mission?
	return type(id) == "string" and index().missionById[id] or nil
end

function StoryRules.SideDef(id: any): Mission?
	return type(id) == "string" and index().sideById[id] or nil
end

function StoryRules.Target(def: Mission): number
	return finite(def.target) and math.max(1, def.target) or 1
end

-- Level, ab dem ein Kapitel offen ist: Freischalt-Tabelle "story:<n>" (GameConfig.Unlocks), sonst unlockLevel
function StoryRules.ChapterLevel(n: number): number
	local lvl = Unlocks.Level("story:" .. tostring(n))
	if finite(lvl) then
		return lvl
	end
	local ch = StoryRules.Chapter(n)
	return ch and finite(ch.unlockLevel) and ch.unlockLevel or 1
end

local function levelOf(d: any, level: any): number
	if finite(level) then
		return level
	end
	return finite(type(d) == "table" and d.level) and d.level or 1
end

function StoryRules.ChapterOpen(d: any, n: number, level: any): boolean
	return levelOf(d, level) >= StoryRules.ChapterLevel(n)
end

-- Level, das eine Mission wirklich braucht (Freischaltungen GameConfig.Unlocks über Story.Requires / unlock / build / cars /
-- bays). Alternativen zählen mit der niedrigsten Voraussetzung. 1, wenn nichts freizuschalten ist.
function StoryRules.RequiredLevel(def: Mission): number
	local S = config()
	local req = type(S.Requires) == "table" and S.Requires or { stat = {}, event = {} }
	local function keyLevel(key: any): number
		local lvl = type(key) == "string" and Unlocks.Level(key) or nil
		return finite(lvl) and lvl or 1
	end
	local need = 1
	if type(def.unlock) == "string" then
		need = math.max(need, keyLevel(def.unlock))
	end
	if def.kind == "stat" then
		need = math.max(need, keyLevel((req.stat or {})[def.stat or ""]))
	elseif def.kind == "event" then
		local events = type(def.events) == "table" and def.events or { def.event }
		local best = math.huge
		for _, e in ipairs(events) do
			best = math.min(best, keyLevel((req.event or {})[e]))
		end
		need = math.max(need, best == math.huge and 1 or best)
	elseif def.kind == "build" then
		need = math.max(need, keyLevel("building:" .. tostring(def.typ)))
	elseif def.kind == "own" then
		if type(def.cars) == "table" then
			local best = math.huge
			for _, id in ipairs(def.cars) do
				best = math.min(best, keyLevel("car:" .. tostring(id)))
			end
			need = math.max(need, best == math.huge and 1 or best)
		elseif finite(def.bays) then
			local levels = type(C.BayLevels) == "table" and C.BayLevels or {}
			local lvl = levels[math.floor(def.bays)]
			need = math.max(need, finite(lvl) and lvl or 1)
		end
	end
	return need
end

-- Kapitel-Missionen, deren Voraussetzung über dem Kapitel-Level liegt (leer = alles erreichbar); für den Test
function StoryRules.UnlockCheck(): { string }
	local out = {}
	for ci, ch in ipairs(config().Chapters) do
		local open = StoryRules.ChapterLevel(ci)
		for _, m in ipairs(ch.Missions) do
			local need = StoryRules.RequiredLevel(m)
			if need > open then
				table.insert(out, string.format("%s: braucht Level %d, Kapitel %d öffnet ab %d", m.id, need, ci, open))
			end
		end
	end
	return out
end

---------------------------------------------------------------- Standardwerte und Laden (§2)
function StoryRules.Default(): Story
	return {
		chapter = 1, step = 1, done = {}, side = {}, active = false,
		sales = { n = 0, best = 0, special = 0, serial = 0, nextAt = 0 }, title = "",
	}
end

-- chapter/step aus done: Kapitel der Reihe nach; step = erste offene Mission; nach dem letzten Kapitel step = Anzahl + 1
local function recompute(st: Story)
	local S = config()
	local chapter = 1
	while chapter < #S.Chapters do
		local all = true
		for _, m in ipairs(S.Chapters[chapter].Missions) do
			if not st.done[m.id] then
				all = false
				break
			end
		end
		if not all then
			break
		end
		chapter += 1
	end
	st.chapter = chapter
	local missions = S.Chapters[chapter].Missions
	st.step = #missions + 1
	for i, m in ipairs(missions) do
		if not st.done[m.id] then
			st.step = i
			break
		end
	end
end
StoryRules.Recompute = recompute

-- raw = gespeichertes d.games.story (oder nil). Idempotent, Whitelist, NaN/negativ -> Standard, Tiefe ≤ 3 unter story.
function StoryRules.Load(raw: any, d: any, now: any): Story
	local st = StoryRules.Default()
	local r = type(raw) == "table" and raw or {}
	local ix = index()
	for id, v in pairs(type(r.done) == "table" and r.done or {}) do
		if type(id) == "string" and ix.missionById[id] and v == true then
			st.done[id] = true
		end
	end
	recompute(st)
	for id, e in pairs(type(r.side) == "table" and r.side or {}) do
		local def = type(id) == "string" and ix.sideById[id] or nil
		if def and type(e) == "table" then
			local day = type(e.day) == "string" and (string.match(e.day, DAY_PATTERN) or (def.legend and e.day == LEGEND_DAY)) and e.day or ""
			local entry = { n = loadInt(e.n, 0, 0, MAX_SAFE), day = day, claimed = e.claimed == true }
			if def.legend then
				entry.day = entry.claimed and LEGEND_DAY or ""
				entry.n = 0
			end
			if entry.claimed or entry.n > 0 then
				st.side[id] = entry
			end
		end
	end
	local a = r.active
	if type(a) == "table" and type(a.id) == "string" then
		local def = ix.missionById[a.id]
		if def and def.chapter == st.chapter and not st.done[a.id] then
			st.active = {
				id = a.id,
				progress = loadInt(a.progress, 0, 0, StoryRules.Target(def)),
				startedAt = loadInt(a.startedAt, 0, 0, MAX_SAFE),
				party = loadInt(a.party, 0, 0, 8),
			}
		end
	end
	local s = type(r.sales) == "table" and r.sales or {}
	st.sales.n = loadInt(s.n, 0, 0, MAX_SAFE)
	st.sales.best = math.min(st.sales.n, loadInt(s.best, 0, 0, MAX_SAFE))
	st.sales.special = math.min(st.sales.n, loadInt(s.special, 0, 0, MAX_SAFE))
	st.sales.serial = loadInt(s.serial, 0, 0, MAX_SAFE)
	st.sales.nextAt = loadInt(s.nextAt, 0, 0, MAX_SAFE)
	st.title = type(r.title) == "string" and #r.title <= 40 and r.title or ""
	return st
end

-- Für MiniRules.DefaultGames / LoadGames
function StoryRules.ApplyDefault(g: any)
	g.story = StoryRules.Default()
end

function StoryRules.ApplyLoad(g: any, raw: any, d: any, now: any)
	local r = type(raw) == "table" and raw or {}
	g.story = StoryRules.Load(r.story, d, now)
end

-- Zugriff (nil-sicher); legt fehlende Daten an (Profile vor der Verkabelung von ApplyLoad)
function StoryRules.Data(d: any): Story?
	local g = type(d) == "table" and d.games or nil
	if type(g) ~= "table" then
		return nil
	end
	if type(g.story) ~= "table" then
		g.story = StoryRules.Default()
	end
	return g.story
end

---------------------------------------------------------------- Stand, Verfügbarkeit, Start
function StoryRules.Current(d: any): any
	local st = StoryRules.Data(d)
	if not st then
		return { chapter = 1, step = 1, active = false, mission = nil, finished = false }
	end
	local ch = StoryRules.Chapter(st.chapter)
	local mission = ch and ch.Missions[st.step] or nil
	return {
		chapter = st.chapter, step = st.step, active = st.active, mission = mission,
		finished = ch ~= nil and st.chapter == StoryRules.ChapterCount() and mission == nil,
	}
end

function StoryRules.Finished(d: any): boolean
	return StoryRules.Current(d).finished
end

-- Nächste startbare Mission (die aktuelle Stufe des aktuellen Kapitels) oder nil mit Grund:
-- "finished" | "active" | "locked" (dazu das nötige Level)
function StoryRules.Available(d: any, level: any): (Mission?, string?, number?)
	local cur = StoryRules.Current(d)
	if cur.finished or not cur.mission then
		return nil, "finished"
	end
	if type(cur.active) == "table" then
		return nil, "active"
	end
	if not StoryRules.ChapterOpen(d, cur.chapter, level) then
		return nil, "locked", StoryRules.ChapterLevel(cur.chapter)
	end
	return cur.mission
end

-- Mission starten (nur die aktuelle Stufe, Kapitel offen, keine andere aktiv). Rückgabe: ok, Mission | Fehlertext
function StoryRules.Start(d: any, id: any, now: any, party: any, level: any): (boolean, any)
	local T = config().Texts
	local st = StoryRules.Data(d)
	local def = StoryRules.Mission(id)
	if not st or not def then
		return false, T.unknown
	end
	local cur = StoryRules.Current(d)
	if cur.finished then
		return false, T.finished
	end
	if st.done[def.id] then
		return false, T.alreadyDone
	end
	if type(st.active) == "table" then
		local a = StoryRules.Mission(st.active.id)
		return false, string.format(T.alreadyActive, a and a.title or st.active.id)
	end
	if not StoryRules.ChapterOpen(d, cur.chapter, level) then
		local ch = StoryRules.Chapter(cur.chapter)
		return false, string.format(T.locked, cur.chapter, ch and ch.title or "", StoryRules.ChapterLevel(cur.chapter))
	end
	if not cur.mission or cur.mission.id ~= def.id then
		return false, string.format(T.notCurrent, cur.mission and cur.mission.title or "")
	end
	st.active = { id = def.id, progress = 0, startedAt = finite(now) and math.floor(now) or 0, party = loadInt(party, 0, 0, 8) }
	return true, def
end

---------------------------------------------------------------- Fortschritt
local function countEquipment(d: any): number
	local eq = type(d) == "table" and type(d.equipment) == "table" and d.equipment or {}
	local n = 0
	for _, e in ipairs(C.Equipment) do
		if finite(eq[e.id]) and eq[e.id] > 0 then
			n += 1
		end
	end
	return n
end

local function ownsAny(d: any, ids: { string }): boolean
	local cars = type(d) == "table" and type(d.games) == "table" and d.games.cars or nil
	if type(cars) ~= "table" then
		return false
	end
	local set = {}
	for _, id in ipairs(ids) do
		set[id] = true
	end
	for _, car in ipairs(cars) do
		if type(car) == "table" and set[car.model] then
			return true
		end
	end
	return false
end

local function buildingStage(d: any, typ: string): number
	local ow = type(d) == "table" and type(d.games) == "table" and d.games.ow or nil
	local b = type(ow) == "table" and type(ow.buildings) == "table" and ow.buildings[typ] or nil
	return type(b) == "table" and finite(b.stage) and b.stage or 0
end

-- Fortschritt aus dem Profil (Bedingungsarten) – für own/build und Legende (absolute Statistik)
local function conditionProgress(d: any, def: Mission): number?
	local target = StoryRules.Target(def)
	if def.kind == "build" then
		return math.min(target, buildingStage(d, def.typ or ""))
	elseif def.kind == "own" then
		if finite(def.money) then
			return math.min(target, finite(d.money) and math.max(0, d.money) or 0)
		elseif finite(def.bays) then
			return math.min(target, finite(d.bays) and d.bays or 0)
		elseif type(def.cars) == "table" then
			return ownsAny(d, def.cars) and target or 0
		elseif def.equipmentAll then
			return math.min(target, countEquipment(d))
		end
		return 0
	elseif def.kind == "stat" and def.absolute then
		local stats = type(d.games) == "table" and type(d.games.stats) == "table" and d.games.stats or {}
		return math.min(target, finite(stats[def.stat or ""]) and stats[def.stat or ""] or 0)
	end
	return nil
end
StoryRules.ConditionProgress = conditionProgress

function StoryRules.IsCounter(def: Mission): boolean
	return conditionProgress({ games = {} }, def) == nil
end

-- Aktueller Fortschritt einer Story-Mission (aktiv: Zähler oder Bedingung; erledigt: Ziel; sonst 0)
function StoryRules.ProgressOf(d: any, def: Mission): number
	local st = StoryRules.Data(d)
	if not st then
		return 0
	end
	if st.done[def.id] then
		return StoryRules.Target(def)
	end
	if type(st.active) ~= "table" or st.active.id ~= def.id then
		return 0
	end
	local cond = conditionProgress(d, def)
	if cond ~= nil then
		return cond
	end
	return st.active.progress
end

local function change(def: Mission, progress: number, delta: number, side: boolean): Change
	local target = StoryRules.Target(def)
	return { id = def.id, title = def.title, progress = progress, target = target, done = progress >= target, side = side, delta = delta }
end

-- Zähler der aktiven Mission erhöhen (nur Zählerarten). Rückgabe: Change oder nil
local function bumpActive(st: Story, def: Mission, delta: number): Change?
	local a = st.active
	if type(a) ~= "table" or a.id ~= def.id or delta <= 0 then
		return nil
	end
	local target = StoryRules.Target(def)
	if a.progress >= target then
		return nil
	end
	a.progress = math.min(target, a.progress + delta)
	return change(def, a.progress, delta, false)
end

---------------------------------------------------------------- Nebenmissionen: Tag, Auswahl, Zähler
-- Level, ab dem eine Nebenmission machbar ist (unlock bzw. Story.Requires)
function StoryRules.SideLevel(def: Mission): number
	return StoryRules.RequiredLevel(def)
end

-- Heutige Auswahl (deterministisch je UTC-Tag wie GoalRules.DailyGoals): Side.Daily verschiedene Ids aus dem Teil des
-- Pools, den der Spieler auf diesem Level schon kann (level nil = ganzer Pool). s_jobs ist immer dabei, darum gibt es
-- jeden Tag mindestens eine machbare Nebenmission; mit einem Levelaufstieg kann die Auswahl am selben Tag wechseln.
function StoryRules.DailyIds(day: string, level: any): { string }
	local ix = index()
	local pool = {}
	for _, id in ipairs(ix.poolIds) do
		local def = ix.sideById[id]
		if not finite(level) or StoryRules.SideLevel(def) <= level then
			table.insert(pool, id)
		end
	end
	if #pool == 0 then
		pool = ix.poolIds
	end
	local want = math.min(#pool, index().S.Side.Daily or 3)
	local out, used = {}, {}
	local k = 0
	local base = hash(day .. ":side")
	while #out < want and k < 64 do
		k += 1
		local idx = (scramble(base, k) % #pool) + 1
		if not used[idx] then
			used[idx] = true
			table.insert(out, pool[idx])
		end
	end
	return out
end

function StoryRules.DailyDefs(day: string, level: any): { Mission }
	local out = {}
	for _, id in ipairs(StoryRules.DailyIds(day, level)) do
		table.insert(out, StoryRules.SideDef(id))
	end
	return out
end

-- Einträge des heutigen Tages (alte Tageseinträge verschwinden). true, wenn sich etwas geändert hat
function StoryRules.EnsureSideDay(d: any, now: number): boolean
	local st = StoryRules.Data(d)
	if not st then
		return false
	end
	local today = dayKey(now)
	local changed = false
	for id, e in pairs(st.side) do
		local def = StoryRules.SideDef(id)
		if not def or (not def.legend and e.day ~= today) then
			st.side[id] = nil
			changed = true
		end
	end
	return changed
end

local function sideEntry(st: Story, def: Mission, today: string): SideEntry
	local e = st.side[def.id]
	if not e or (not def.legend and e.day ~= today) then
		e = { n = 0, day = def.legend and "" or today, claimed = false }
		st.side[def.id] = e
	end
	return e
end

-- Fortschritt einer Nebenmission (Tag oder Legende)
function StoryRules.SideProgress(d: any, def: Mission, now: number): number
	local st = StoryRules.Data(d)
	if not st then
		return 0
	end
	local cond = conditionProgress(d, def)
	if cond ~= nil then
		return cond
	end
	local e = st.side[def.id]
	if not e or (not def.legend and e.day ~= dayKey(now)) then
		return 0
	end
	return math.min(StoryRules.Target(def), e.n)
end

local function sideClaimed(st: Story, def: Mission, today: string): boolean
	local e = st.side[def.id]
	if not e then
		return false
	end
	if def.legend then
		return e.claimed
	end
	return e.day == today and e.claimed
end

-- Zähler einer heutigen Nebenmission erhöhen (Zählerarten, nicht abgeholt). Rückgabe: Change oder nil
local function bumpSide(d: any, st: Story, def: Mission, delta: number, now: number): Change?
	if delta <= 0 or def.legend then
		return nil
	end
	local today = dayKey(now)
	local e = sideEntry(st, def, today)
	local target = StoryRules.Target(def)
	if e.claimed or e.n >= target then
		return nil
	end
	e.n = math.min(target, e.n + delta)
	return change(def, e.n, delta, true)
end

-- Heutige Nebenmissionen des Spielers als Definitionsliste (Auswahl nach Tag und Level)
local function todaysDefs(d: any, now: number, level: any): { Mission }
	return StoryRules.DailyDefs(dayKey(now), levelOf(d, level))
end

---------------------------------------------------------------- Ereignisse (Statistik, Ereignis, Verkauf)
local function matchesEvent(def: Mission, event: string, data: any): boolean
	local hit = def.event == event
	if not hit and type(def.events) == "table" then
		for _, e in ipairs(def.events) do
			if e == event then
				hit = true
				break
			end
		end
	end
	if not hit then
		return false
	end
	if finite(def.maxTime) then
		local t = type(data) == "table" and data.time or nil
		return finite(t) and t <= def.maxTime
	end
	return true
end

-- Statistik um delta gestiegen (MiniRules.AddStat): aktive Mission (kind stat, nicht absolute) und heutige Nebenmissionen
function StoryRules.OnStat(d: any, key: any, delta: any, now: number): { Change }
	local out = {}
	local st = StoryRules.Data(d)
	if not st or type(key) ~= "string" or not finite(delta) or delta <= 0 then
		return out
	end
	if type(st.active) == "table" then
		local def = StoryRules.Mission(st.active.id)
		if def and def.kind == "stat" and not def.absolute and def.stat == key then
			table.insert(out, bumpActive(st, def, delta))
		end
	end
	for _, def in ipairs(todaysDefs(d, now)) do
		if def.kind == "stat" and not def.absolute and def.stat == key then
			table.insert(out, bumpSide(d, st, def, delta, now))
		end
	end
	return out
end

-- Ereignis (settle, car_bought, auction_won, auction_consigned, track_finish {time}, delivery, arcade_round,
-- action:<aktion>, ow_built:<typ>, …): aktive Mission (kind event) und heutige Nebenmissionen
function StoryRules.OnEvent(d: any, event: any, data: any, now: number): { Change }
	local out = {}
	local st = StoryRules.Data(d)
	if not st or type(event) ~= "string" then
		return out
	end
	if type(st.active) == "table" then
		local def = StoryRules.Mission(st.active.id)
		if def and def.kind == "event" and matchesEvent(def, event, data) then
			table.insert(out, bumpActive(st, def, 1))
		end
	end
	for _, def in ipairs(todaysDefs(d, now)) do
		if def.kind == "event" and matchesEvent(def, event, data) then
			table.insert(out, bumpSide(d, st, def, 1, now))
		end
	end
	return out
end

-- Gelungener Kiesplatz-Verkauf (Stufe tier, Sondermodell-Kunde special): aktive Mission (kind sell)
function StoryRules.OnSale(d: any, tier: number, special: boolean, now: number): { Change }
	local out = {}
	local st = StoryRules.Data(d)
	if not st then
		return out
	end
	st.sales.n += 1
	if tier >= 3 then
		st.sales.best += 1
	end
	if special then
		st.sales.special += 1
	end
	if type(st.active) == "table" then
		local def = StoryRules.Mission(st.active.id)
		if def and def.kind == "sell" then
			local ok = tier >= (finite(def.tier) and def.tier or 1) and (not def.special or special)
			if ok then
				table.insert(out, bumpActive(st, def, 1))
			end
		end
	end
	return out
end

-- Braucht der Spieler gerade dieses Ereignis (aktive Mission oder offene heutige Nebenmission)? Für den Lieferdienst.
function StoryRules.WantsEvent(d: any, event: string, now: number): boolean
	local st = StoryRules.Data(d)
	if not st then
		return false
	end
	if type(st.active) == "table" then
		local def = StoryRules.Mission(st.active.id)
		if def and def.kind == "event" and matchesEvent(def, event, { time = 0 }) and st.active.progress < StoryRules.Target(def) then
			return true
		end
	end
	local today = dayKey(now)
	for _, def in ipairs(todaysDefs(d, now)) do
		if def.kind == "event" and matchesEvent(def, event, { time = 0 }) and not sideClaimed(st, def, today)
			and StoryRules.SideProgress(d, def, now) < StoryRules.Target(def) then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- Abholen
local function missionXp(def: Mission): number
	local r = def.reward or {}
	if finite(r.xp) then
		return r.xp
	end
	local list = type(GameConfig.XP) == "table" and GameConfig.XP.StoryMission or nil
	local xp = type(list) == "table" and list[def.chapter or 1] or nil
	return finite(xp) and xp or 0
end

local function chapterXp(n: number): number
	local list = type(GameConfig.XP) == "table" and GameConfig.XP.StoryChapter or nil
	local xp = type(list) == "table" and list[n] or nil
	return finite(xp) and xp or 0
end

local function grantCosmetic(d: any, id: any): boolean
	if type(id) ~= "string" or id == "" then
		return false
	end
	local g = type(d) == "table" and d.games or nil
	local shop = type(g) == "table" and g.shop or nil
	local owned = type(shop) == "table" and shop.owned or nil
	if type(owned) ~= "table" then
		return false -- Shop-Daten gibt es erst ab Meilenstein 8 (die Kosmetik bleibt über done[id] nachholbar)
	end
	owned[id] = true
	return true
end

-- Story-Mission abholen: aktiv, Ziel erreicht. Rückgabe: ok, { mission, credits, xp, cosmetic, cosmeticGranted, title,
-- chapterDone, chapter, chapterXp, nextChapter, nextLevel, finished } | Fehlertext (nil = still verwerfen)
function StoryRules.Claim(d: any, id: any, now: number): (boolean, any)
	local T = config().Texts
	local st = StoryRules.Data(d)
	local def = StoryRules.Mission(id)
	if not st or not def then
		return false, T.unknown
	end
	if st.done[def.id] then
		return false, nil
	end
	if type(st.active) ~= "table" or st.active.id ~= def.id then
		return false, T.notActive
	end
	local progress = StoryRules.ProgressOf(d, def)
	local target = StoryRules.Target(def)
	if progress < target then
		return false, string.format(T.notDone, math.floor(progress), target)
	end
	local M = mini()
	local chapter = def.chapter or 1
	local r = def.reward or {}
	local credits = finite(r.credits) and r.credits or 0
	M.AddMoney(d, credits)
	local xp = missionXp(def)
	M.GainXP(d, xp)
	M.AddStat(d, "missionsDone", 1, now)
	local granted = grantCosmetic(d, r.cosmetic)
	if type(r.title) == "string" and r.title ~= "" then
		st.title = r.title
	end
	st.done[def.id] = true
	st.active = false
	local before = st.chapter
	recompute(st)
	local res = {
		mission = def, credits = credits, xp = xp, cosmetic = r.cosmetic, cosmeticGranted = granted, title = r.title,
		chapterDone = false, chapter = chapter, chapterXp = 0, nextChapter = st.chapter, nextLevel = StoryRules.ChapterLevel(st.chapter),
		finished = false,
	}
	local ch = StoryRules.Chapter(chapter)
	if (ch ~= nil and st.step > #ch.Missions) or st.chapter > before then
		res.chapterDone = true
		res.chapterXp = chapterXp(chapter)
		M.GainXP(d, res.chapterXp)
		res.finished = StoryRules.Current(d).finished
	end
	return true, res
end

-- Nebenmission abholen (heutige Auswahl oder Legende). Rückgabe: ok, { def, credits, xp } | Fehlertext (nil = still)
function StoryRules.SideClaim(d: any, id: any, now: number, level: any): (boolean, any)
	local S = config()
	local T = S.Texts
	local st = StoryRules.Data(d)
	local def = StoryRules.SideDef(id)
	if not st or not def then
		return false, T.sideUnknown
	end
	local today = dayKey(now)
	if not def.legend then
		local listed = false
		for _, x in ipairs(todaysDefs(d, now, level)) do
			if x.id == def.id then
				listed = true
			end
		end
		if not listed then
			return false, T.sideUnknown
		end
	end
	if sideClaimed(st, def, today) then
		return false, nil
	end
	local progress = StoryRules.SideProgress(d, def, now)
	local target = StoryRules.Target(def)
	if progress < target then
		return false, string.format(T.sideNotDone, math.floor(progress), target)
	end
	if not def.legend then
		local claims = 0
		for sid, e in pairs(st.side) do
			local x = StoryRules.SideDef(sid)
			if x and not x.legend and e.day == today and e.claimed then
				claims += 1
			end
		end
		if claims >= (S.Side.DailyLimit or 3) then
			return false, T.sideLimit
		end
	end
	local e = sideEntry(st, def, today)
	e.claimed = true
	if def.legend then
		e.day = LEGEND_DAY
	end
	local credits = StoryRules.SideCredits(def, levelOf(d, level))
	local xp = finite(def.xp) and def.xp or (type(GameConfig.XP) == "table" and finite(GameConfig.XP.SideMission) and GameConfig.XP.SideMission or 0)
	local M = mini()
	M.AddMoney(d, credits)
	M.GainXP(d, xp)
	M.AddStat(d, "missionsDone", 1, now)
	return true, { def = def, credits = credits, xp = xp }
end

-- Credits einer Nebenmission auf diesem Level (Legende: fest)
function StoryRules.SideCredits(def: Mission, level: number): number
	local base = finite(def.credits) and def.credits or 0
	if def.legend then
		return base
	end
	local S = config().Side
	local factor = math.min(S.LevelScaleCap or 3, 1 + (S.LevelScale or 0) * (math.max(1, level) - 1))
	return math.floor(base * factor + 0.5)
end

-- Ansicht der Nebenmissionen (heute + Legende) für Snapshot/Client
function StoryRules.SideList(d: any, now: number, level: any): { any }
	local st = StoryRules.Data(d)
	local out = {}
	if not st then
		return out
	end
	local today = dayKey(now)
	local lvl = levelOf(d, level)
	local function add(def: Mission)
		local progress = StoryRules.SideProgress(d, def, now)
		local target = StoryRules.Target(def)
		local claimed = sideClaimed(st, def, today)
		table.insert(out, {
			id = def.id, title = def.title, text = def.text, progress = progress, target = target,
			done = claimed, claimable = not claimed and progress >= target, legend = def.legend == true, needsCar = def.needsCar == true,
			credits = StoryRules.SideCredits(def, lvl), xp = finite(def.xp) and def.xp or (type(GameConfig.XP) == "table" and GameConfig.XP.SideMission or 0),
		})
	end
	for _, def in ipairs(todaysDefs(d, now, lvl)) do
		add(def)
	end
	for _, id in ipairs(index().legendIds) do
		add(StoryRules.SideDef(id) :: Mission)
	end
	return out
end

---------------------------------------------------------------- Kiesplatz: Angebot und Verkauf
function StoryRules.LevelFactor(level: number): number
	local S = config().Sale
	return math.min(S.LevelFactorCap or 3, 1 + (S.LevelFactor or 0) * (math.max(1, level) - 1))
end

-- Angebot des nächsten Kunden aus einem Seed (Server: "<Server-Geheimnis>:<userId>:<serial>" – das Geheimnis kennt nur
-- StoryService, der Client kann den Wurf nicht nachrechnen): Kunde, Wunsch, Wurf (0..1) und die drei Preisstufen mit
-- erwartetem Gewinn. Sondermodell-Kunden ab Kapitel SpecialChapter, jeder SpecialEvery-te Kunde.
function StoryRules.NextSale(d: any, seed: any, level: any): Offer
	local S = config().Sale
	local st = StoryRules.Data(d)
	local lvl = levelOf(d, level)
	local serial = st and st.sales.serial + 1 or 1
	-- Seed gut durchmischen (Park–Miller), damit Nachbar-Seeds ("7001:1", "7001:2") verschiedene Kunden und Würfe ergeben
	local h = hash(tostring(seed))
	for _ = 1, 3 do
		h = (h * 48271) % 2147483647
	end
	local chapter = st and st.chapter or 1
	local wantSpecial = chapter >= (S.SpecialChapter or 4) and serial % (S.SpecialEvery or 3) == 0
	local pool = {}
	for _, c in ipairs(S.Customers) do
		if (c.special == true) == wantSpecial then
			table.insert(pool, c)
		end
	end
	if #pool == 0 then
		pool = S.Customers
	end
	local c = pool[(h % #pool) + 1]
	local roll = (math.floor(h / 1009) % 1000) / 1000
	local factor = StoryRules.LevelFactor(lvl) * (c.special and (S.SpecialMultiplier or 1) or 1)
	local base = S.BasePrice[c.wants] or 0
	local tiers = {}
	for _, t in ipairs(S.Tiers) do
		local profit = math.floor(t.profit * factor + 0.5)
		table.insert(tiers, { tier = t.tier, label = t.label, profit = profit, price = math.floor(base * factor + 0.5) + profit, chance = t.chance, hint = t.hint })
	end
	return {
		serial = serial, customer = c.name, wants = c.wants, wantsName = S.Bodies[c.wants] or c.wants, line = c.line,
		special = c.special == true, roll = roll, tiers = tiers,
	}
end

-- Verkauf zur Preisstufe tier (1..3) gegen das Angebot: Erfolg, wenn roll < chance (Stufe 1 immer). Bei Erfolg Gewinn
-- als Einnahme (MiniRules.AddIncome, Prestige-Bonus) und XP; die Verkaufszähler und die aktive sell-Mission laufen mit.
-- Nichts Zufälliges hier: der Wurf stammt aus dem Angebot (Seed mit Server-Geheimnis).
function StoryRules.Sell(d: any, offer: Offer, tier: any, now: number): SellResult?
	local S = config().Sale
	local st = StoryRules.Data(d)
	if not st or type(offer) ~= "table" or type(tier) ~= "number" or tier ~= math.floor(tier) or not offer.tiers[tier] then
		return nil
	end
	st.sales.serial = math.max(st.sales.serial, offer.serial)
	local t = offer.tiers[tier]
	local roll = finite(offer.roll) and offer.roll or 0
	local sold = tier == 1 or roll < t.chance
	if not sold then
		local texts = S.Texts.failed
		return { sold = false, credits = 0, xp = 0, tier = tier, special = offer.special, changed = {},
			text = string.format(texts[(offer.serial % #texts) + 1], offer.customer) }
	end
	local M = mini()
	local credits = M.AddIncome(d, t.profit)
	local xp = finite(S.Xp[tier]) and S.Xp[tier] or 0
	M.GainXP(d, xp)
	M.MarkActive(d, now)
	local changed = StoryRules.OnSale(d, tier, offer.special, now)
	local texts = S.Texts.sold
	return { sold = true, credits = credits, xp = xp, tier = tier, special = offer.special, changed = changed,
		text = string.format(texts[(offer.serial % #texts) + 1], offer.customer, MiniLocale.Credits(credits)) }
end

-- Kunde weg ohne Verkauf (Geduld zu Ende, Moduswechsel): die laufende Nummer rückt vor, damit der nächste Kunde ein
-- anderer ist (neuer Seed) und nicht derselbe mit demselben Wurf zurückkommt.
function StoryRules.OfferGone(d: any, offer: any)
	local st = StoryRules.Data(d)
	if st and type(offer) == "table" and finite(offer.serial) then
		st.sales.serial = math.max(st.sales.serial, math.floor(offer.serial))
	end
end

-- Nächsten Kunden frühestens zur Serverzeit at (bleibt über Moduswechsel und Rejoin erhalten; nie rückwärts)
function StoryRules.ScheduleNext(d: any, at: any)
	local st = StoryRules.Data(d)
	if st and finite(at) then
		st.sales.nextAt = math.max(st.sales.nextAt, math.floor(at))
	end
end

function StoryRules.NextOfferAt(d: any): number
	local st = StoryRules.Data(d)
	return st and st.sales.nextAt or 0
end

---------------------------------------------------------------- Co-op (§7)
function StoryRules.CoopShared(def: Mission?): boolean
	local shared = config().Coop.SharedKinds
	return def ~= nil and shared[def.kind] == true and not def.absolute
end

-- Fortschritt delta von A auf B übertragen: nur, wenn B dieselbe Mission aktiv hat und die Art geteilt wird.
-- Rückgabe: Change für B oder nil. dA ist nur zur Prüfung da (gleiche Mission aktiv), nichts wird dort geändert.
function StoryRules.CoopApply(dA: any, dB: any, id: any, delta: any, now: number?): Change?
	local def = StoryRules.Mission(id)
	if not def or not StoryRules.CoopShared(def) or not finite(delta) or delta <= 0 then
		return nil
	end
	local sa, sb = StoryRules.Data(dA), StoryRules.Data(dB)
	if not sa or not sb or sa == sb then
		return nil
	end
	if type(sb.active) ~= "table" or sb.active.id ~= def.id then
		return nil
	end
	return bumpActive(sb, def, delta)
end

---------------------------------------------------------------- Ansicht (Snapshot)
function StoryRules.MissionView(d: any, def: Mission, level: any): any
	local st = StoryRules.Data(d)
	local progress = StoryRules.ProgressOf(d, def)
	local target = StoryRules.Target(def)
	local done = st ~= nil and st.done[def.id] == true
	local active = st ~= nil and type(st.active) == "table" and st.active.id == def.id
	local cur = StoryRules.Current(d)
	local r = def.reward or {}
	return {
		id = def.id, title = def.title, text = def.text, kind = def.kind, progress = progress, target = target,
		done = done, active = active, claimable = active and progress >= target,
		current = cur.mission ~= nil and cur.mission.id == def.id,
		startable = cur.mission ~= nil and cur.mission.id == def.id and type(cur.active) ~= "table" and StoryRules.ChapterOpen(d, def.chapter or 1, level),
		credits = finite(r.credits) and r.credits or 0, xp = missionXp(def), cosmetic = r.cosmetic, titleReward = r.title,
	}
end

-- story-Feld des Snapshots (§11). extra = { sale = Offer|false, saleIn = s, passive = bool }; full: Missionsliste des
-- Kapitels und die Kapitelübersicht (sticky, nur im vollen Snapshot)
function StoryRules.View(d: any, now: number, level: any, extra: any, full: boolean?): any
	local S = config()
	local st = StoryRules.Data(d)
	local cur = StoryRules.Current(d)
	local ch = StoryRules.Chapter(cur.chapter)
	local lvl = levelOf(d, level)
	local activeView: any = false
	if st and type(st.active) == "table" then
		local def = StoryRules.Mission(st.active.id)
		if def then
			activeView = StoryRules.MissionView(d, def, lvl)
			activeView.party = st.active.party
		end
	end
	local sale: any = false
	if type(extra) == "table" and type(extra.sale) == "table" then
		local o = extra.sale
		local tiers = {}
		for _, t in ipairs(o.tiers) do
			table.insert(tiers, { tier = t.tier, label = t.label, profit = t.profit, price = t.price, hint = t.hint })
		end
		sale = { offer = o.serial, customer = o.customer, wants = o.wants, wantsName = o.wantsName, line = o.line, special = o.special, tiers = tiers }
	end
	local view = {
		title = S.Title,
		chapter = cur.chapter,
		chapterTitle = ch and ch.title or "",
		intro = ch and ch.intro or "",
		step = cur.step,
		count = ch and #ch.Missions or 0,
		active = activeView,
		locked = not StoryRules.ChapterOpen(d, cur.chapter, lvl),
		levelNeeded = StoryRules.ChapterLevel(cur.chapter),
		finished = cur.finished,
		next = cur.mission and cur.mission.id or false,
		side = StoryRules.SideList(d, now, lvl),
		sale = sale,
		saleIn = type(extra) == "table" and finite(extra.saleIn) and math.max(0, math.floor(extra.saleIn)) or 0,
		sales = st and { n = st.sales.n, best = st.sales.best, special = st.sales.special } or { n = 0, best = 0, special = 0 },
		passive = type(extra) == "table" and extra.passive == true,
		titleEarned = st and st.title or "",
	}
	if full then
		local missions = {}
		for _, m in ipairs(ch and ch.Missions or {}) do
			table.insert(missions, StoryRules.MissionView(d, m, lvl))
		end
		view.missions = missions
		local chapters = {}
		for i, c in ipairs(S.Chapters) do
			local all = true
			for _, m in ipairs(c.Missions) do
				if not (st and st.done[m.id]) then
					all = false
				end
			end
			table.insert(chapters, { id = i, title = c.title, level = StoryRules.ChapterLevel(i), done = all, open = StoryRules.ChapterOpen(d, i, lvl) })
		end
		view.chapters = chapters
	end
	return view
end

---------------------------------------------------------------- Balance (§7: Belohnung ≤ Share × Werkstatt-Cr/Min)
function StoryRules.WorkshopPerMinute(level: number): number
	local rows = config().Balance.WorkshopPerMinute
	if level <= rows[1][1] then
		return rows[1][2]
	end
	for i = 2, #rows do
		local a, b = rows[i - 1], rows[i]
		if level <= b[1] then
			return a[2] + (b[2] - a[2]) * (level - a[1]) / (b[1] - a[1])
		end
	end
	local a, b = rows[#rows - 1], rows[#rows]
	return b[2] + (b[2] - a[2]) * (level - b[1]) / (b[1] - a[1])
end

-- Verstöße gegen die Regel (leer = alles in Ordnung); für den Test
function StoryRules.BalanceCheck(): { string }
	local S = config()
	local out = {}
	for ci, ch in ipairs(S.Chapters) do
		local cap = S.Balance.Share * StoryRules.WorkshopPerMinute(StoryRules.ChapterLevel(ci))
		for _, m in ipairs(ch.Missions) do
			local minutes = finite(m.minutes) and m.minutes or 1
			local perMin = ((m.reward and m.reward.credits) or 0) / minutes
			if perMin > cap + 1e-9 then
				table.insert(out, string.format("%s: %.1f Cr/Min > %.1f", m.id, perMin, cap))
			end
		end
	end
	return out
end

return StoryRules
