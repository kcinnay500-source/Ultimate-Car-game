-- MetaRules: Spieler-Einstellungen, Tutorial-Stand, Modus und Beginner-Hinweise im Profil
-- (docs/PHASE4_CONTRACT.md §2): d.games.meta, dazu Default/Load für d.games.prestige (aus PrestigeRules).
-- Reine Funktionen, keine Instanzen, kein Geld. MiniRules.DefaultGames/LoadGames rufen ApplyDefault/ApplyLoad.
-- meta = { tutorialDone, tutorialStep (1..Anzahl Schritte), tutorialSkipped, beginner, passive, single,
--          lastMode ("lobby"|"openworld"|"tycoon"), firstSeen (unix), playSeconds, hintsSeen = { [hintId] = true },
--          startPath ("" = Startwahl offen | "werkstatt" | "autohaus" | "produktion" | "schrottplatz", GameConfig.Start),
--          startOffered (true = die Startwahl wurde diesem Profil schon gezeigt bzw. mit ResetStart neu verlangt: sie bleibt
--          offen, bis der Spieler wählt – auch wenn er inzwischen Aufträge abrechnet oder ein Gebäude besitzt) }
-- Startwahl: neue Profile haben startPath = "" und MÜSSEN beim ersten Open-World-Beitritt wählen (StartService,
-- start_choose; 3.x: kein „Später entscheiden“). Veteranen (d.completed > 0, Tutorial beendet/übersprungen, schon im
-- Tutorial weiter als Schritt 1 oder ein Open-World-Gebäude mit Stufe > 0 – jeweils bevor die Wahl je gezeigt wurde)
-- bekommen beim Laden bzw. über ResolveStartPath automatisch GameConfig.Start.Default.
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local PrestigeRules = require(script.Parent:WaitForChild("PrestigeRules"))

local MetaRules = {}

export type Meta = {
	tutorialDone: boolean, tutorialStep: number, tutorialSkipped: boolean, tutorialRewarded: boolean,
	beginner: boolean, passive: boolean, single: boolean,
	lastMode: string, firstSeen: number, playSeconds: number, hintsSeen: { [string]: boolean },
	startPath: string, startOffered: boolean,
}
export type Settings = { single: boolean, passive: boolean, beginner: boolean }

local MAX_SAFE = 2 ^ 53
local SETTING_KEYS = { "single", "passive", "beginner" }

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function loadInt(v: any, default: number, min: number, max: number): number
	if not finite(v) or v < min then
		return default
	end
	return math.floor(math.min(v, max))
end

local function startConfig(): any
	return type(GameConfig.Start) == "table" and GameConfig.Start or { Order = {}, PathSet = {}, Default = "werkstatt" }
end

-- Gültiger Startweg (Whitelist GameConfig.Start.Order)?
function MetaRules.IsStartPath(typ: any): boolean
	return type(typ) == "string" and startConfig().PathSet[typ] == true
end

-- Schritte des Tutorials für einen Weg ("" / unbekannt = klassischer Weg)
local function stepsFor(path: any): { any }
	local tu = GameConfig.Tutorial
	local list = type(tu.ByPath) == "table" and MetaRules.IsStartPath(path) and tu.ByPath[path] or nil
	return list or tu.Steps
end
MetaRules.TutorialSteps = stepsFor

local function stepCount(path: any): number
	return math.max(1, #stepsFor(path))
end

-- Hat das (rohe) Open-World-Datum ein Gebäude mit Stufe > 0? (Veteranen-Erkennung beim Laden und zur Laufzeit)
local function hasBuilding(ow: any): boolean
	local b = type(ow) == "table" and ow.buildings or nil
	if type(b) ~= "table" then
		return false
	end
	for typ, e in pairs(b) do
		if type(typ) == "string" and type(e) == "table" and finite(e.stage) and e.stage > 0 then
			return true
		end
	end
	return false
end

---------------------------------------------------------------- Standardwerte und Laden
-- Neue Spieler: Beginner-Modus an (Hinweise), Tutorial bei Schritt 1, erster Beitritt in der Lobby.
function MetaRules.Default(): Meta
	return {
		tutorialDone = false,
		tutorialStep = 1,
		tutorialSkipped = false,
		tutorialRewarded = false, -- Belohnung verbucht (ein Neustart am Kiosk gibt sie nicht noch einmal)
		beginner = true,
		passive = false,
		single = false,
		lastMode = GameConfig.DefaultMode,
		firstSeen = 0,
		playSeconds = 0,
		hintsSeen = {},
		startPath = "", -- Startwahl offen (StartService fragt beim ersten Open-World-Beitritt)
		startOffered = false, -- Wahl schon gezeigt (dann machen Aufträge/Gebäude das Profil nicht mehr zum Veteranen)
	}
end

-- raw = gespeichertes d.games.meta (oder nil). Idempotent, Whitelist, NaN/negativ -> Standard.
-- firstSeen = 0 (oder in der Zukunft) wird auf now gesetzt, wenn now bekannt ist.
-- Veteranen (Profil ohne meta, aber mit abgerechneten Aufträgen d.completed) gelten als eingewiesen:
-- das Tutorial ist für sie beendet (wie MiniRules.LoadGames jobsDone = d.completed übernimmt).
-- rawGames (optional) = gespeichertes d.games (MetaRules.ApplyLoad): ein gespeichertes Open-World-Gebäude macht das
-- Profil zum Veteranen der Startwahl (OWRules.Load läuft erst nach MetaRules).
function MetaRules.Load(raw: any, d: any, now: any, rawGames: any?): Meta
	local m = MetaRules.Default()
	local r = type(raw) == "table" and raw or {}
	local veteran = type(raw) ~= "table" and type(d) == "table" and finite(d.completed) and d.completed > 0
	m.tutorialSkipped = r.tutorialSkipped == true
	m.tutorialDone = r.tutorialDone == true or m.tutorialSkipped or veteran == true -- übersprungen = beendet
	-- Startweg: gespeicherter Weg (Whitelist); sonst Veteranen automatisch der klassische Weg, neue Profile "" (Wahl offen)
	-- Wurde die Wahl schon gezeigt (startOffered, auch nach ResetStart), zählen abgerechnete Aufträge, der Tutorial-Schritt
	-- und Gebäude nicht: die Wahl bleibt offen, bis der Spieler wählt.
	if MetaRules.IsStartPath(r.startPath) then
		m.startPath = r.startPath
	else
		local offered = r.startOffered == true and not veteran
		local played = not offered and type(d) == "table" and finite(d.completed) and d.completed > 0
		local midTutorial = not offered and finite(r.tutorialStep) and r.tutorialStep >= 2 -- im klassischen Tutorial schon unterwegs
		local rawOw = type(rawGames) == "table" and rawGames.ow or nil
		if played or m.tutorialDone or midTutorial or (not offered and hasBuilding(rawOw)) then
			m.startPath = startConfig().Default
		else
			m.startOffered = offered
		end
	end
	m.tutorialStep = loadInt(r.tutorialStep, 1, 1, stepCount(m.startPath))
	-- Belohnung: gespeichertes Flag; Profile von vor dem Flag, die das Tutorial regulär beendet haben, gelten als
	-- belohnt (sonst gäbe es sie beim Neustart am Kiosk ein zweites Mal). Veteranen ebenso.
	m.tutorialRewarded = r.tutorialRewarded == true or (r.tutorialRewarded == nil and r.tutorialDone == true and r.tutorialSkipped ~= true) or veteran == true
	m.beginner = r.beginner ~= false -- nur ein ausdrückliches false schaltet die Hinweise ab
	m.passive = r.passive == true
	m.single = r.single == true
	m.lastMode = (type(r.lastMode) == "string" and GameConfig.ModeSet[r.lastMode]) and r.lastMode or GameConfig.DefaultMode
	if veteran then
		m.lastMode = "openworld" -- 2.4.0-Veteranen landen wie bisher in ihrer Werkstatt (Open World), nicht in der Lobby
		-- Erstlings-Hinweise („Super, dein erster Auftrag!“, Empfang erklärt) passen nicht zu jemandem mit
		-- abgerechneten Aufträgen: first:jobsDone und station:workshop gelten als gesehen.
		for _, h in ipairs(GameConfig.Hints) do
			if h.when == "first:jobsDone" or h.when == "station:workshop" then
				m.hintsSeen[h.id] = true
			end
		end
	end
	m.firstSeen = loadInt(r.firstSeen, 0, 0, MAX_SAFE)
	if finite(now) and now > 0 and (m.firstSeen == 0 or m.firstSeen > now) then
		m.firstSeen = math.floor(now)
	end
	m.playSeconds = loadInt(r.playSeconds, 0, 0, MAX_SAFE)
	if type(r.hintsSeen) == "table" then
		for id, v in pairs(r.hintsSeen) do
			if type(id) == "string" and GameConfig.HintById[id] and v == true then
				m.hintsSeen[id] = true
			end
		end
	end
	return m
end

MetaRules.DefaultPrestige = PrestigeRules.Default
MetaRules.LoadPrestige = PrestigeRules.Load

-- Für MiniRules.DefaultGames: legt meta und prestige in g (= d.games) an
function MetaRules.ApplyDefault(g: any)
	g.meta = MetaRules.Default()
	g.prestige = PrestigeRules.Default()
end

-- Für MiniRules.LoadGames: raw = gespeichertes d.games, d = Profil mit geladenem d.level
function MetaRules.ApplyLoad(g: any, raw: any, d: any, now: any)
	local r = type(raw) == "table" and raw or {}
	g.meta = MetaRules.Load(r.meta, d, now, r)
	g.prestige = PrestigeRules.Load(r.prestige, d, now)
end

---------------------------------------------------------------- Zugriff (nil-sicher)
function MetaRules.Meta(d: any): Meta?
	local g = type(d) == "table" and d.games or nil
	local m = type(g) == "table" and g.meta or nil
	return type(m) == "table" and m or nil
end

-- Einstellungen für Snapshot/Client (Standardwerte ohne meta)
function MetaRules.Settings(d: any): Settings
	local m = MetaRules.Meta(d)
	if not m then
		local def = MetaRules.Default()
		return { single = def.single, passive = def.passive, beginner = def.beginner }
	end
	return { single = m.single == true, passive = m.passive == true, beginner = m.beginner == true }
end

function MetaRules.IsBeginner(d: any): boolean
	return MetaRules.Settings(d).beginner
end

function MetaRules.IsPassive(d: any): boolean
	return MetaRules.Settings(d).passive
end

function MetaRules.Mode(d: any): string
	local m = MetaRules.Meta(d)
	return m and m.lastMode or GameConfig.DefaultMode
end

---------------------------------------------------------------- Ändern (lobby_settings, lobby_mode)
-- settings = { single = bool?, passive = bool?, beginner = bool? }; nur Booleans werden übernommen, alles
-- andere bleibt. Rückgabe: true, wenn sich etwas geändert hat.
function MetaRules.SetSettings(d: any, settings: any): boolean
	local m = MetaRules.Meta(d)
	if not m or type(settings) ~= "table" then
		return false
	end
	local changed = false
	for _, key in ipairs(SETTING_KEYS) do
		local v = settings[key]
		if type(v) == "boolean" and m[key] ~= v then
			m[key] = v
			changed = true
		end
	end
	return changed
end

-- Modus merken ("lobby" | "openworld" | "tycoon"); unbekannt -> false, nichts geändert
function MetaRules.SetMode(d: any, mode: any): boolean
	local m = MetaRules.Meta(d)
	if not m or type(mode) ~= "string" or not GameConfig.ModeSet[mode] then
		return false
	end
	m.lastMode = mode
	return true
end

-- Ersten Beitritt festhalten (firstSeen), wenn noch nicht gesetzt
function MetaRules.Touch(d: any, now: any)
	local m = MetaRules.Meta(d)
	if m and finite(now) and now > 0 and m.firstSeen == 0 then
		m.firstSeen = math.floor(now)
	end
end

function MetaRules.AddPlaySeconds(d: any, seconds: any)
	local m = MetaRules.Meta(d)
	if m and finite(seconds) and seconds > 0 then
		m.playSeconds = math.min(MAX_SAFE, m.playSeconds + math.floor(seconds))
	end
end

---------------------------------------------------------------- Startwahl (GameConfig.Start, StartService)
-- Gewählter Startweg ("" = noch offen oder ohne meta)
function MetaRules.StartPath(d: any): string
	local m = MetaRules.Meta(d)
	return m and MetaRules.IsStartPath(m.startPath) and m.startPath or ""
end

-- Weg für Tutorial und Story: gewählter Weg, sonst der klassische (werkstatt)
function MetaRules.EffectivePath(d: any): string
	local p = MetaRules.StartPath(d)
	return p ~= "" and p or startConfig().Default
end

-- Veteran der Startwahl zur Laufzeit (wie beim Laden): abgerechnete Aufträge, Tutorial beendet/übersprungen,
-- Tutorial schon über Schritt 1 hinaus oder ein Open-World-Gebäude mit Stufe > 0. Hat das Profil die Wahl schon
-- gesehen (startOffered), zählen Aufträge, Tutorial-Schritt und Gebäude nicht – die Wahl ist Pflicht und bleibt offen,
-- bis der Spieler wählt (auch wenn er zwischendurch über das Tablet Aufträge abrechnet).
function MetaRules.IsStartVeteran(d: any): boolean
	if type(d) ~= "table" then
		return false
	end
	local m = MetaRules.Meta(d)
	local offered = m ~= nil and m.startOffered == true
	if not offered and finite(d.completed) and d.completed > 0 then
		return true
	end
	if m and (m.tutorialDone == true or (not offered and finite(m.tutorialStep) and m.tutorialStep >= 2)) then
		return true
	end
	local g = d.games
	return not offered and type(g) == "table" and hasBuilding(g.ow)
end

-- Veteranen ohne Weg bekommen den klassischen Weg (idempotent). Rückgabe: Weg ("" = Wahl offen)
function MetaRules.ResolveStartPath(d: any): string
	local m = MetaRules.Meta(d)
	if not m then
		return ""
	end
	if not MetaRules.IsStartPath(m.startPath) then
		m.startPath = MetaRules.IsStartVeteran(d) and startConfig().Default or ""
	end
	return m.startPath
end

-- Muss der Spieler noch wählen? (meta vorhanden, kein Weg, kein Veteran) – ändert nichts
function MetaRules.StartPending(d: any): boolean
	local m = MetaRules.Meta(d)
	return m ~= nil and not MetaRules.IsStartPath(m.startPath) and not MetaRules.IsStartVeteran(d)
end

-- Die Wahl wurde gezeigt (StartService.OnMode): ab jetzt bleibt sie offen, bis der Spieler wählt (idempotent).
-- Nur für Profile, die gerade wählen müssen. Rückgabe: true, wenn sich etwas geändert hat.
function MetaRules.MarkStartOffered(d: any): boolean
	local m = MetaRules.Meta(d)
	if not m or m.startOffered == true or not MetaRules.StartPending(d) then
		return false
	end
	m.startOffered = true
	return true
end

-- Weg einmalig setzen. Rückgabe: ok, Grund ("ok" | "invalid" | "already" | "nometa")
function MetaRules.SetStartPath(d: any, typ: any): (boolean, string)
	local m = MetaRules.Meta(d)
	if not m then
		return false, "nometa"
	end
	if not MetaRules.IsStartPath(typ) then
		return false, "invalid"
	end
	if MetaRules.IsStartPath(m.startPath) then
		return false, "already"
	end
	m.startPath = typ
	m.startOffered = false -- gewählt: nichts mehr offen
	return true, "ok"
end

-- Startwahl zurücksetzen (Entwickler-Menü über StartService.ResetStart): Weg wieder offen, die Wahl gilt als gezeigt
-- (startOffered – sonst machten Aufträge/Gebäude das Profil sofort wieder zum Veteranen), das Tutorial wartet wieder
-- auf die Wahl und beginnt danach mit Schritt 1 (die Belohnung bleibt verbucht: tutorialRewarded wird nicht
-- zurückgesetzt). Rückgabe: true, wenn meta da war.
function MetaRules.ResetStart(d: any): boolean
	local m = MetaRules.Meta(d)
	if not m then
		return false
	end
	m.startPath = ""
	m.startOffered = true
	m.tutorialStep = 1
	m.tutorialDone = false
	m.tutorialSkipped = false
	return true
end

---------------------------------------------------------------- Beginner-Hinweise
-- Erster noch nicht gezeigter Hinweis zu einem Auslöser ("unlock:<key>", "station:<key>", "first:<stat>");
-- nil ohne Beginner-Modus. Nach dem Anzeigen MarkHint aufrufen.
function MetaRules.HintFor(d: any, when: any): GameConfig.Hint?
	local m = MetaRules.Meta(d)
	if not m or m.beginner ~= true or type(when) ~= "string" then
		return nil
	end
	for _, h in ipairs(GameConfig.HintsByWhen[when] or {}) do
		if m.hintsSeen[h.id] ~= true then
			return h
		end
	end
	return nil
end

-- Hinweis als gesehen merken; true nur beim ersten Mal (unbekannte Ids werden nicht gespeichert)
function MetaRules.MarkHint(d: any, id: any): boolean
	local m = MetaRules.Meta(d)
	if not m or type(id) ~= "string" or not GameConfig.HintById[id] or m.hintsSeen[id] == true then
		return false
	end
	m.hintsSeen[id] = true
	return true
end

return MetaRules
