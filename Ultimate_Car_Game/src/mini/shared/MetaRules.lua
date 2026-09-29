-- MetaRules: Spieler-Einstellungen, Tutorial-Stand, Modus und Beginner-Hinweise im Profil
-- (docs/PHASE4_CONTRACT.md §2): d.games.meta, dazu Default/Load für d.games.prestige (aus PrestigeRules).
-- Reine Funktionen, keine Instanzen, kein Geld. MiniRules.DefaultGames/LoadGames rufen ApplyDefault/ApplyLoad.
-- meta = { tutorialDone, tutorialStep (1..Anzahl Schritte), tutorialSkipped, beginner, passive, single,
--          lastMode ("lobby"|"openworld"|"tycoon"), firstSeen (unix), playSeconds, hintsSeen = { [hintId] = true } }
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local PrestigeRules = require(script.Parent:WaitForChild("PrestigeRules"))

local MetaRules = {}

export type Meta = {
	tutorialDone: boolean, tutorialStep: number, tutorialSkipped: boolean,
	beginner: boolean, passive: boolean, single: boolean,
	lastMode: string, firstSeen: number, playSeconds: number, hintsSeen: { [string]: boolean },
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

local function stepCount(): number
	return math.max(1, #GameConfig.Tutorial.Steps)
end

---------------------------------------------------------------- Standardwerte und Laden
-- Neue Spieler: Beginner-Modus an (Hinweise), Tutorial bei Schritt 1, erster Beitritt in der Lobby.
function MetaRules.Default(): Meta
	return {
		tutorialDone = false,
		tutorialStep = 1,
		tutorialSkipped = false,
		beginner = true,
		passive = false,
		single = false,
		lastMode = GameConfig.DefaultMode,
		firstSeen = 0,
		playSeconds = 0,
		hintsSeen = {},
	}
end

-- raw = gespeichertes d.games.meta (oder nil). Idempotent, Whitelist, NaN/negativ -> Standard.
-- firstSeen = 0 (oder in der Zukunft) wird auf now gesetzt, wenn now bekannt ist.
-- Veteranen (Profil ohne meta, aber mit abgerechneten Aufträgen d.completed) gelten als eingewiesen:
-- das Tutorial ist für sie beendet (wie MiniRules.LoadGames jobsDone = d.completed übernimmt).
function MetaRules.Load(raw: any, d: any, now: any): Meta
	local m = MetaRules.Default()
	local r = type(raw) == "table" and raw or {}
	local veteran = type(raw) ~= "table" and type(d) == "table" and finite(d.completed) and d.completed > 0
	m.tutorialSkipped = r.tutorialSkipped == true
	m.tutorialDone = r.tutorialDone == true or m.tutorialSkipped or veteran == true -- übersprungen = beendet
	m.tutorialStep = loadInt(r.tutorialStep, 1, 1, stepCount())
	m.beginner = r.beginner ~= false -- nur ein ausdrückliches false schaltet die Hinweise ab
	m.passive = r.passive == true
	m.single = r.single == true
	m.lastMode = (type(r.lastMode) == "string" and GameConfig.ModeSet[r.lastMode]) and r.lastMode or GameConfig.DefaultMode
	if veteran then
		m.lastMode = "openworld" -- 2.4.0-Veteranen landen wie bisher in ihrer Werkstatt (Open World), nicht in der Lobby
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
	g.meta = MetaRules.Load(r.meta, d, now)
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
