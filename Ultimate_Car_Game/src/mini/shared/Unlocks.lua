-- Unlocks: Freischaltungen nach Level (docs/PHASE4_CONTRACT.md §3). Reine Funktionen über GameConfig.Unlocks.
-- d = 2.4.0-Profildaten (d.level); nil-sicher: ohne d oder ohne gültiges Level gilt Level 1.
-- Server: Unlocks.Has / Unlocks.Gate vor jeder Aktion, die etwas Freischaltbares nutzt. Client: NextFor/ListFor
-- für HUD und den Tab „Freischaltungen“. CarCatalog nimmt die Händler-Level aus Unlocks.CarLevel.
-- Unbekannte Schlüssel gelten als NICHT freigeschaltet (Tippfehler fallen sofort auf, statt still zu öffnen);
-- Tabs ohne Eintrag (overview, map, goals, ...) sind dagegen immer offen (TabAllowed).
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local C = require(script.Parent.Parent:WaitForChild("Config"))

local Unlocks = {}

export type Entry = GameConfig.UnlockEntry
export type Row = { key: string, level: number, kind: string, title: string, hint: string, tab: string?, special: boolean?, reached: boolean }

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

-- Level eines Profils (ganzzahlig, mindestens 1); nil-sicher
function Unlocks.LevelOf(d: any): number
	local lvl = type(d) == "table" and d.level or nil
	if not finite(lvl) or lvl < 1 then
		return 1
	end
	return math.floor(lvl)
end

---------------------------------------------------------------- Tabelle
function Unlocks.Entry(key: any): Entry?
	if type(key) ~= "string" then
		return nil
	end
	return GameConfig.UnlockByKey[key]
end

function Unlocks.Known(key: any): boolean
	return Unlocks.Entry(key) ~= nil
end

-- Level einer Freischaltung; nil für unbekannte Schlüssel
function Unlocks.Level(key: any): number?
	local e = Unlocks.Entry(key)
	return e and e.level or nil
end

-- Händler-/Auktions-Level eines Automodells: Eintrag "car:<id>", sonst das 2.4.0-Feld C.Cars[].level;
-- nil für unbekannte Modelle (CarCatalog nimmt dann sein eigenes Level, z. B. bei Sondermodellen ohne Eintrag).
function Unlocks.CarLevel(modelId: any): number?
	if type(modelId) ~= "string" then
		return nil
	end
	local lvl = Unlocks.Level("car:" .. modelId)
	if lvl then
		return lvl
	end
	local car = C.CarById and C.CarById[modelId]
	if car and finite(car.level) then
		return car.level
	end
	return nil
end

---------------------------------------------------------------- Prüfungen
-- true, wenn das Profil die Freischaltung erreicht hat. Unbekannter Schlüssel -> false.
function Unlocks.Has(d: any, key: any): boolean
	local lvl = Unlocks.Level(key)
	if not lvl then
		return false
	end
	return Unlocks.LevelOf(d) >= lvl
end

-- Meldung für den Spieler, wenn eine Freischaltung fehlt
function Unlocks.Message(entry: Entry): string
	return entry.title .. " gibt es ab Level " .. entry.level .. "."
end

-- Für Server-Handler: ok, Meldung. Unbekannter Schlüssel -> false + Hinweis (Tippfehler fällt auf).
function Unlocks.Gate(d: any, key: any): (boolean, string?)
	local e = Unlocks.Entry(key)
	if not e then
		return false, "Unbekannte Freischaltung: " .. tostring(key)
	end
	if Unlocks.LevelOf(d) >= e.level then
		return true, nil
	end
	return false, Unlocks.Message(e)
end

-- Eintrag (Art feature) zu einem Tab der Minispiel-Oberfläche; nil = Tab ohne Level-Voraussetzung
function Unlocks.ForTab(tab: any): Entry?
	if type(tab) ~= "string" then
		return nil
	end
	return GameConfig.UnlockByTab[tab]
end

-- Darf das Profil diesen Tab / diese Station öffnen? Tabs ohne Eintrag sind immer offen.
function Unlocks.TabAllowed(d: any, tab: any): boolean
	local e = Unlocks.ForTab(tab)
	if not e then
		return true
	end
	return Unlocks.LevelOf(d) >= e.level
end

---------------------------------------------------------------- Anzeige
-- Nächste Freischaltung über dem aktuellen Level (für HUD und Beginner-Hinweis); nil, wenn alles erreicht ist.
-- Rückgabe ist der Eintrag aus GameConfig (nur lesen, nicht verändern).
function Unlocks.NextFor(d: any): Entry?
	local lvl = Unlocks.LevelOf(d)
	for _, u in ipairs(GameConfig.Unlocks) do
		if u.level > lvl then
			return u
		end
	end
	return nil
end

-- Tabelle Level -> Freischaltung mit erreicht/offen (für den Tab „Freischaltungen“), nach Level sortiert
function Unlocks.ListFor(d: any): { Row }
	local lvl = Unlocks.LevelOf(d)
	local out = {}
	for _, u in ipairs(GameConfig.Unlocks) do
		table.insert(out, {
			key = u.key, level = u.level, kind = u.kind, title = u.title, hint = u.hint, tab = u.tab,
			special = u.special, reached = lvl >= u.level,
		})
	end
	return out
end

-- Freischaltungen, die zwischen oldLevel (ausschließlich) und newLevel (einschließlich) erreicht wurden
-- (für mini_notice { kind = "unlock" } beim Level-Aufstieg)
function Unlocks.NewlyReached(oldLevel: any, newLevel: any): { Entry }
	local from = finite(oldLevel) and oldLevel or 0
	local to = finite(newLevel) and newLevel or 0
	local out = {}
	if to <= from then
		return out
	end
	for _, u in ipairs(GameConfig.Unlocks) do
		if u.level > from and u.level <= to then
			table.insert(out, u)
		end
	end
	return out
end

-- Alle Einträge einer Art (sortiert), z. B. "car" für den Händlerkatalog
function Unlocks.OfKind(kind: any): { Entry }
	return type(kind) == "string" and GameConfig.UnlocksByKind[kind] or {}
end

return Unlocks
