-- OWRules: Open-World-Gebäude, Perks und Passiv-Modus als reine Regeln (docs/PHASE4_CONTRACT.md §2, §5, §7).
-- Daten: d.games.ow = { buildings = { [typ] = { stage, built, readyAt, collectedAt, carAt, partsCarry, packs, partsTotal,
--                        collects, gift } }, passive, lastPassiveAt }
--   stage       = gekaufte Zielstufe (0 = nichts gebaut), readyAt = Serverzeit (unix), ab der diese Stufe fertig ist
--   built       = fertig gebaute Stufe (≤ stage); nur sie zählt für Erträge und Perks. Nur Settle(d, now) hebt built auf
--                 stage, sobald readyAt erreicht ist – auch für offline fertig gewordene Bauten: Load lässt built wie
--                 gespeichert, der Dienst ruft Settle beim Beitritt (dann gibt es ow_ready + Toast) und im Tick.
--   collectedAt = Beginn des laufenden Ertragszeitraums (unix, mit Nachkommastellen – nie abrunden, B-001); carAt = Beginn des Gutschein-Zeitraums (Produktion 4)
--   partsCarry  = angebrochener Altteil-Rest (0 ≤ x < 1) aus partsPerHour, damit häufiges Abholen keine Teile verliert
--   packs/partsTotal/collects = Lebenszeit-Zähler (abgeholte Bauteil-Pakete, abgeholte Altteile, Abholungen mit Ertrag)
--                 für Story-Missionen (kind own, owTyp/owStat); gift = Stufe 1 kam aus der Startwahl (GrantStart)
-- werkstatt ist das 2.4.0-Grundstück: Stufe = d.bays, kein Kaufweg hier (CanBuild -> "werkstatt").
-- Zahlen nur aus GameConfig.OW. Keine Instanzen, kein Zufall. Geld ändert sich nur über MiniRules.AddMoney/AddIncome
-- (lazy require wie CarRules: MiniRules lädt OWRules, darum kein require am Dateikopf).
-- Schnittstelle: Default/Load/ApplyDefault/ApplyLoad, CanBuild(d, typ, now) -> ok, reason, cost; Build(d, typ, now);
-- Settle(d, now) -> { typ... } fertig geworden; Ready(d, typ, now); Remaining(d, typ, now); Collectable(d, typ, now) ->
-- amounts; Collect(d, typ, now) -> { credits, scrap, parts, car } | nil; Perk(d, kind) -> Faktor ≥ 1; Discount(d);
-- PassiveSet(d, on, now); IsPassive(d); Summary(d, now) (Snapshot-Felder);
-- GrantStart(d, typ, now) -> ok, Grund: Startwahl (GameConfig.Start) – Stufe 1 geschenkt und sofort fertig.
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local Unlocks = require(script.Parent:WaitForChild("Unlocks"))
local C = require(script.Parent.Parent:WaitForChild("Config"))

local OWRules = {}

local OW = GameConfig.OW
local MAX_SAFE = 2 ^ 53
local HOUR = 3600

export type Building = {
	stage: number, built: number, readyAt: number, collectedAt: number, carAt: number, partsCarry: number,
	packs: number, partsTotal: number, collects: number, gift: boolean,
}
export type OW = { buildings: { [string]: Building }, passive: boolean, lastPassiveAt: number }
export type Amounts = { credits: number, scrap: number, parts: number, car: string?, hours: number }

local MiniRules
local function mini()
	if not MiniRules then
		MiniRules = require(script.Parent:WaitForChild("MiniRules"))
	end
	return MiniRules
end

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function loadInt(v: any, default: number, min: number, max: number): number
	if not finite(v) or v < min then
		return default
	end
	return math.floor(math.min(v, max))
end

-- Zeitpunkt mit Nachkommastellen (Serverzeit): wird NICHT abgerundet – ein abgerundeter Beginn des Ertragszeitraums
-- würde den schon bezahlten Sekundenbruchteil beim nächsten Abholen noch einmal auszahlen (B-001).
local function loadTime(v: any, default: number, min: number, max: number): number
	if not finite(v) or v < min then
		return default
	end
	return math.min(v, max)
end

local function nowOr(now: any): number
	return finite(now) and now or os.time()
end

local function games(d: any): any
	local g = type(d) == "table" and d.games or nil
	return type(g) == "table" and g or nil
end

---------------------------------------------------------------- Konfiguration
function OWRules.IsType(typ: any): boolean
	return type(typ) == "string" and OW.TypeSet[typ] == true
end

function OWRules.Building(typ: any): GameConfig.OWBuilding?
	return OWRules.IsType(typ) and OW.Buildings[typ] or nil
end

-- Stufen-Eintrag (nil für werkstatt oder außerhalb 1..MaxStage)
function OWRules.Stage(typ: any, stage: any): GameConfig.OWStage?
	local b = OWRules.Building(typ)
	if not b or not finite(stage) then
		return nil
	end
	return b.Stages[math.floor(stage)]
end

function OWRules.MaxStage(typ: any): number
	local b = OWRules.Building(typ)
	return b and #b.Stages or 0
end

function OWRules.Name(typ: any): string
	local b = OWRules.Building(typ)
	return b and b.name or tostring(typ)
end

---------------------------------------------------------------- Standardwerte und Laden
local function newBuilding(): Building
	return {
		stage = 0, built = 0, readyAt = 0, collectedAt = 0, carAt = 0, partsCarry = 0,
		packs = 0, partsTotal = 0, collects = 0, gift = false,
	}
end

function OWRules.Default(): OW
	local buildings = {}
	for _, typ in ipairs(OW.Types) do
		if typ ~= "werkstatt" then
			buildings[typ] = newBuilding()
		end
	end
	return { buildings = buildings, passive = false, lastPassiveAt = 0 }
end

-- raw = gespeichertes d.games.ow (oder nil). Idempotent, Whitelist, NaN/negativ -> Standard. built bleibt wie gespeichert
-- (≤ stage): einen offline fertig gewordenen Bau verbucht erst Settle (OWService.OnJoin), damit der Spieler den Hinweis
-- ow_ready und den Toast bekommt. now wird nicht mehr gebraucht (Signatur wie die anderen ApplyLoad).
function OWRules.Load(raw: any, d: any, _now: any): OW
	local o = OWRules.Default()
	local r = type(raw) == "table" and raw or {}
	local rb = type(r.buildings) == "table" and r.buildings or {}
	for typ, b in pairs(o.buildings) do
		local src = type(rb[typ]) == "table" and rb[typ] or {}
		local max = OWRules.MaxStage(typ)
		b.stage = loadInt(src.stage, 0, 0, max)
		b.readyAt = loadInt(src.readyAt, 0, 0, MAX_SAFE)
		local built = loadInt(src.built, src.built == nil and b.stage or 0, 0, b.stage)
		b.built = math.min(built, b.stage)
		if b.stage == 0 then
			b.readyAt = 0
			b.built = 0
		end
		b.collectedAt = loadTime(src.collectedAt, 0, 0, MAX_SAFE)
		b.carAt = loadInt(src.carAt, 0, 0, MAX_SAFE)
		local carry = src.partsCarry
		b.partsCarry = finite(carry) and carry >= 0 and carry < 1 and carry or 0
		b.packs = loadInt(src.packs, 0, 0, MAX_SAFE)
		b.partsTotal = loadInt(src.partsTotal, 0, 0, MAX_SAFE)
		b.collects = loadInt(src.collects, 0, 0, MAX_SAFE)
		b.gift = src.gift == true and b.stage > 0
		if b.built == 0 then
			b.collectedAt = 0
			b.carAt = 0
			b.partsCarry = 0
		else
			-- Ertrag nie vor der Fertigstellung der aktuellen Stufe rechnen (Umbau: Anlage stand still)
			b.collectedAt = math.max(b.collectedAt, b.readyAt)
			b.carAt = math.max(b.carAt, b.readyAt)
		end
	end
	o.passive = r.passive == true
	o.lastPassiveAt = loadInt(r.lastPassiveAt, 0, 0, MAX_SAFE)
	return o
end

-- Für MiniRules.DefaultGames / LoadGames
function OWRules.ApplyDefault(g: any)
	g.ow = OWRules.Default()
end

function OWRules.ApplyLoad(g: any, raw: any, d: any, now: any)
	local r = type(raw) == "table" and raw or {}
	g.ow = OWRules.Load(r.ow, d, now)
end

---------------------------------------------------------------- Zugriff (nil-sicher)
function OWRules.Data(d: any): OW?
	local g = games(d)
	local o = g and g.ow or nil
	return type(o) == "table" and type(o.buildings) == "table" and o or nil
end

-- Sorgt dafür, dass d.games.ow existiert (Profile von vor Meilenstein 6 in einer laufenden Sitzung)
function OWRules.Ensure(d: any): OW?
	local g = games(d)
	if not g then
		return nil
	end
	local o = OWRules.Data(d)
	if not o then
		g.ow = OWRules.Load(g.ow, d, nil)
		o = g.ow
	end
	for _, typ in ipairs(OW.Types) do
		if typ ~= "werkstatt" and type(o.buildings[typ]) ~= "table" then
			o.buildings[typ] = newBuilding()
		end
	end
	-- Profile aus einer laufenden Sitzung vor den Lebenszeit-Zählern
	for _, b in pairs(o.buildings) do
		if type(b) == "table" then
			b.packs = finite(b.packs) and b.packs or 0
			b.partsTotal = finite(b.partsTotal) and b.partsTotal or 0
			b.collects = finite(b.collects) and b.collects or 0
			b.gift = b.gift == true
		end
	end
	return o
end

function OWRules.Entry(d: any, typ: any): Building?
	local o = OWRules.Data(d)
	local b = o and OWRules.IsType(typ) and o.buildings[typ] or nil
	return type(b) == "table" and b or nil
end

-- Bühnenzahl des 2.4.0-Grundstücks (Stufe der Werkstatt), 1..C.MaxBays
function OWRules.Bays(d: any): number
	local bays = type(d) == "table" and d.bays or nil
	if not finite(bays) or bays < 1 then
		return 1
	end
	return math.floor(math.min(bays, C.MaxBays or 4))
end

-- Fertig gebaute Stufe (werkstatt: Bühnen); 0 ohne Gebäude
function OWRules.Built(d: any, typ: any): number
	if typ == "werkstatt" then
		return OWRules.Bays(d)
	end
	local b = OWRules.Entry(d, typ)
	return b and b.built or 0
end

-- Gekaufte Zielstufe (werkstatt: Bühnen)
function OWRules.StageOf(d: any, typ: any): number
	if typ == "werkstatt" then
		return OWRules.Bays(d)
	end
	local b = OWRules.Entry(d, typ)
	return b and b.stage or 0
end

-- Läuft gerade ein Bau? (stage > built)
function OWRules.Building_(d: any, typ: any): boolean
	local b = OWRules.Entry(d, typ)
	return b ~= nil and b.stage > b.built
end
OWRules.InProgress = OWRules.Building_

-- true, wenn kein Bau läuft bzw. der laufende Bau bei now fertig ist (noch ohne Settle)
function OWRules.Ready(d: any, typ: any, now: any): boolean
	local b = OWRules.Entry(d, typ)
	if not b or b.stage == 0 then
		return false
	end
	if b.built >= b.stage then
		return true
	end
	return nowOr(now) >= b.readyAt
end

-- Restliche Bausekunden (0 ohne laufenden Bau)
function OWRules.Remaining(d: any, typ: any, now: any): number
	local b = OWRules.Entry(d, typ)
	if not b or b.stage <= b.built then
		return 0
	end
	return math.max(0, b.readyAt - nowOr(now))
end

-- Hebt fertige Bauten auf ihre Stufe (built = stage). Rückgabe: Liste der Typen, die gerade fertig wurden.
function OWRules.Settle(d: any, now: any): { string }
	local done = {}
	local o = OWRules.Data(d)
	if not o then
		return done
	end
	local t = nowOr(now)
	for _, typ in ipairs(OW.Types) do
		local b = o.buildings[typ]
		if type(b) == "table" and b.stage > b.built and t >= b.readyAt then
			b.built = b.stage
			-- Build setzt collectedAt/carAt schon auf readyAt; alte Profile ohne diese Felder starten hier
			if b.collectedAt < b.readyAt then
				b.collectedAt = b.readyAt
			end
			if b.carAt < b.readyAt then
				b.carAt = b.readyAt
			end
			table.insert(done, typ)
		end
	end
	return done
end

---------------------------------------------------------------- Bauen
-- Rückgabe: ok, Grund ("unknown" | "werkstatt" | "max" | "building" | "level" | "credits" | "ok"), Kosten der nächsten Stufe
function OWRules.CanBuild(d: any, typ: any, now: any): (boolean, string, number)
	local b = OWRules.Building(typ)
	if not b then
		return false, "unknown", 0
	end
	if typ == "werkstatt" then
		return false, "werkstatt", 0
	end
	local e = OWRules.Entry(d, typ)
	if not e then
		return false, "unknown", 0
	end
	local nextStage = e.stage + 1
	local st = b.Stages[nextStage]
	if not st then
		return false, "max", 0
	end
	local cost = st.price
	if e.stage > e.built and not OWRules.Ready(d, typ, now) then
		return false, "building", cost
	end
	if b.unlock and not Unlocks.Has(d, b.unlock) then
		return false, "level", cost
	end
	local level = st.level or 1
	if Unlocks.LevelOf(d) < level then
		return false, "level", cost
	end
	local money = type(d) == "table" and finite(d.money) and d.money or 0
	if money < cost then
		return false, "credits", cost
	end
	return true, "ok", cost
end

-- Level, das die nächste Stufe verlangt (für Anzeige)
function OWRules.NextLevel(d: any, typ: any): number
	local b = OWRules.Building(typ)
	local e = OWRules.Entry(d, typ)
	local st = b and e and b.Stages[e.stage + 1] or nil
	if not st then
		return 0
	end
	local lvl = st.level or 1
	local u = b.unlock and Unlocks.Level(b.unlock) or nil
	return math.max(lvl, u or 1)
end

-- Kauft die nächste Stufe (nach CanBuild): zieht die Credits ab, setzt stage + readyAt. Während des Umbaus steht die
-- Anlage still: der bis dahin angesammelte Ertrag wird vorher abgeholt (Rückgabe 4: Beträge oder nil), danach läuft der
-- Ertrag erst ab readyAt (collectedAt = readyAt) – so wird kein Zeitraum zum falschen Stufensatz gerechnet (auch offline).
-- Rückgabe: ok, Grund, Kosten, vorher abgeholte Beträge
function OWRules.Build(d: any, typ: any, now: any): (boolean, string, number, Amounts?)
	local ok, reason, cost = OWRules.CanBuild(d, typ, now)
	if not ok then
		return false, reason, cost, nil
	end
	local e = OWRules.Entry(d, typ)
	local st = OWRules.Stage(typ, e.stage + 1)
	OWRules.Settle(d, now) -- ein fertiger Bau wird vorher verbucht (built = stage)
	local t = nowOr(now)
	local collected = e.built > 0 and OWRules.Collect(d, typ, t, { skipCar = true }) or nil
	mini().AddMoney(d, -cost)
	e.stage = e.stage + 1
	e.readyAt = math.floor(t + math.max(0, st.buildSeconds or 0))
	e.collectedAt = e.readyAt
	if e.built == 0 then
		e.carAt = e.readyAt
	end
	return true, "ok", cost, collected
end

---------------------------------------------------------------- Startwahl (GameConfig.Start, StartService)
-- Schenkt Stufe 1 des Gebäudes eines Startwegs: ohne Level-Sperre, ohne Preis, ohne Bauzeit. readyAt liegt yieldHours
-- (GameConfig.Start.Paths[typ].yieldHours, höchstens PassiveCapHours) in der Vergangenheit, darum ist die Stufe sofort
-- fertig (Ready = true) und der Startertrag wartet schon zum Abholen. built bleibt bis zum nächsten Settle auf 0:
-- OWService verbucht den Bau dann im nächsten Tick (Settle -> Stufenmodell am Anker, mini_notice ow_ready + Toast) –
-- genau wie einen offline fertig gewordenen Bau. Idempotent: nie zweimal, nie über eine schon gebaute Stufe.
-- Rückgabe: ok, Grund ("ok" | "werkstatt" (klassischer Start, nichts zu schenken) | "unknown" | "already" | "nodata")
function OWRules.GrantStart(d: any, typ: any, now: any): (boolean, string)
	local S = GameConfig.Start
	local path = type(S) == "table" and type(S.Paths) == "table" and type(typ) == "string" and S.Paths[typ] or nil
	if not path then
		return false, "unknown"
	end
	local btyp = path.building
	if btyp == nil or btyp == "werkstatt" then
		return false, "werkstatt"
	end
	if not OWRules.Building(btyp) or OWRules.MaxStage(btyp) < 1 then
		return false, "unknown"
	end
	if not OWRules.Ensure(d) then
		return false, "nodata"
	end
	local e = OWRules.Entry(d, btyp)
	if not e then
		return false, "nodata"
	end
	if e.stage > 0 or e.gift == true then
		return false, "already"
	end
	local t = math.floor(nowOr(now))
	local hours = finite(path.yieldHours) and math.max(0, path.yieldHours) or 0
	local cap = finite(OW.PassiveCapHours) and OW.PassiveCapHours > 0 and OW.PassiveCapHours or 12
	hours = math.min(hours, cap)
	local readyAt = math.max(0, t - math.floor(hours * HOUR))
	e.stage = 1
	e.built = 0 -- Settle (OWService-Tick) hebt built auf 1 und stellt das Modell auf
	e.readyAt = readyAt
	e.collectedAt = readyAt
	e.carAt = readyAt
	e.partsCarry = 0
	e.gift = true
	return true, "ok"
end

---------------------------------------------------------------- Erträge
local function capHours(): number
	local h = OW.PassiveCapHours
	return finite(h) and h > 0 and h or 12
end

-- Ertrag seit collectedAt (höchstens PassiveCapHours), ohne Änderung. nil ohne fertiges Gebäude.
function OWRules.Collectable(d: any, typ: any, now: any): Amounts?
	local e = OWRules.Entry(d, typ)
	if not e or e.built <= 0 then
		return nil
	end
	local st = OWRules.Stage(typ, e.built)
	if not st then
		return nil
	end
	local t = nowOr(now)
	-- während eines Umbaus steht die Anlage still (Build setzt collectedAt = readyAt der neuen Stufe)
	local elapsed = math.max(0, t - e.collectedAt)
	local capped = math.min(elapsed, capHours() * HOUR)
	local hours = capped / HOUR
	local out: Amounts = { credits = 0, scrap = 0, parts = 0, car = nil, hours = hours }
	if finite(st.yieldPerHour) then
		out.credits = math.floor(st.yieldPerHour * hours)
	end
	if finite(st.scrapPerHour) then
		out.scrap = math.floor(st.scrapPerHour * hours)
	end
	if finite(st.partsPerHour) then
		-- angebrochener Rest aus früheren Abholungen zählt mit (partsCarry), sonst gingen bei häufigem Abholen alle Teile verloren
		out.parts += math.floor(st.partsPerHour * hours + (finite(e.partsCarry) and e.partsCarry or 0))
	end
	if finite(st.partsEveryHours) and st.partsEveryHours > 0 then
		local packs = math.floor(hours / st.partsEveryHours)
		out.parts += packs * (finite(st.partsPerPack) and st.partsPerPack or 0)
	end
	if type(st.carModel) == "string" and finite(st.carEveryHours) and st.carEveryHours > 0 then
		if t - e.carAt >= st.carEveryHours * HOUR then
			out.car = st.carModel
		end
	end
	return out
end

-- Gibt es etwas abzuholen?
function OWRules.HasYield(a: Amounts?): boolean
	return a ~= nil and (a.credits > 0 or a.scrap > 0 or a.parts > 0 or a.car ~= nil)
end

-- Holt den Ertrag ab: Credits über MiniRules.AddIncome (Prestige-Bonus), Schrott in die Presse, Altteile ins Lager;
-- das Auto (Gutschein) gibt der Dienst über CarRules.GrantModel aus (out.car = Modell-Id), wenn Platz in der Garage ist.
-- opts.skipCar = true lässt den Gutschein stehen (Garage voll): car = nil, carAt bleibt.
-- Rückgabe: Beträge oder nil (nichts fertig / nichts da). Idempotent: ein zweiter Aufruf im selben Moment liefert nil.
function OWRules.Collect(d: any, typ: any, now: any, opts: { skipCar: boolean? }?): Amounts?
	local a = OWRules.Collectable(d, typ, now)
	if a and opts and opts.skipCar then
		a.car = nil
	end
	if not OWRules.HasYield(a) then
		return nil
	end
	local e = OWRules.Entry(d, typ)
	local st = OWRules.Stage(typ, e.built)
	local t = nowOr(now)
	local g = games(d)
	if a.credits > 0 then
		a.credits = mini().AddIncome(d, a.credits)
	end
	if a.scrap > 0 and g and type(g.press) == "table" and finite(g.press.scrap) then
		g.press.scrap = math.min(MAX_SAFE, g.press.scrap + a.scrap)
	elseif a.scrap > 0 then
		a.scrap = 0
	end
	if a.parts > 0 and g and finite(g.parts) then
		g.parts = math.min(MAX_SAFE, g.parts + a.parts)
	elseif a.parts > 0 then
		a.parts = 0
	end
	-- Lebenszeit-Zähler (Story-Missionen der Startwege): Abholungen, Altteile, Bauteil-Pakete
	e.collects = math.min(MAX_SAFE, (finite(e.collects) and e.collects or 0) + 1)
	e.partsTotal = math.min(MAX_SAFE, (finite(e.partsTotal) and e.partsTotal or 0) + a.parts)
	if a.parts > 0 and finite(st.partsEveryHours) and st.partsEveryHours > 0 then
		local packs = math.floor(a.hours / st.partsEveryHours)
		e.packs = math.min(MAX_SAFE, (finite(e.packs) and e.packs or 0) + packs)
	end
	-- Altteile je Stunde (Schrottplatz): den Bruchteil eines Teils für das nächste Abholen aufheben
	if finite(st.partsPerHour) then
		local capped = math.min(math.max(0, t - e.collectedAt), capHours() * HOUR)
		local raw = st.partsPerHour * (capped / HOUR) + (finite(e.partsCarry) and e.partsCarry or 0)
		local carry = raw - math.floor(raw)
		e.partsCarry = (carry >= 0 and carry < 1) and carry or 0
	end
	-- Paketbau (Produktion): der angebrochene Zeitraum bleibt erhalten (collectedAt rückt um volle Pakete vor)
	if finite(st.partsEveryHours) and st.partsEveryHours > 0 and not finite(st.yieldPerHour) and not finite(st.scrapPerHour) then
		local capped = math.min(math.max(0, t - e.collectedAt), capHours() * HOUR)
		local packs = math.floor(capped / (st.partsEveryHours * HOUR))
		local leftover = capped - packs * st.partsEveryHours * HOUR
		-- nie abrunden und nie zurück: der neue Zeitraum beginnt frühestens am alten Beginn (B-001)
		e.collectedAt = math.max(e.collectedAt, t - leftover)
	else
		-- bezahlt ist genau bis t (Serverzeit mit Nachkommastellen); floor(t) würde den Bruchteil doppelt zahlen (B-001)
		e.collectedAt = t
	end
	if a.car then
		e.carAt = math.floor(t)
	end
	return a
end

---------------------------------------------------------------- Perks (§7)
-- Faktor ≥ 1 je Karriereweg: 1 + min(cap, Stufe × per); werkstatt: (Bühnen − 1) × per. Hart gedeckelt auf PerkCap.
-- Genau diese Rechnung übernimmt CrossBonus.OWPerk(d, typ) (liest GameConfig.OW.Perks + d.games.ow direkt).
function OWRules.Perk(d: any, kind: any): number
	local p = type(kind) == "string" and type(OW.Perks) == "table" and OW.Perks[kind] or nil
	if not p then
		return 1
	end
	local n
	if p.perBay then
		n = OWRules.Bays(d) - 1
	else
		n = OWRules.Built(d, kind)
	end
	local per = finite(p.per) and p.per or 0
	local cap = finite(p.cap) and p.cap or 0
	local hard = finite(OW.PerkCap) and OW.PerkCap or 0.25
	local bonus = math.min(cap, hard, math.max(0, n) * per)
	if bonus <= 0 then
		return 1
	end
	return 1 + bonus
end

-- Händlerrabatt-Anteil (0..cap) des Autohauses (CarRules.DealerPrice addiert ihn)
function OWRules.Discount(d: any): number
	return OWRules.Perk(d, "autohaus") - 1
end

function OWRules.Perks(d: any): { [string]: number }
	local out = {}
	for _, typ in ipairs(OW.Types) do
		out[typ] = OWRules.Perk(d, typ)
	end
	return out
end

---------------------------------------------------------------- Passiv-Modus (§5)
-- Eine Quelle zur Laufzeit: d.games.meta.passive (lobby_settings schreibt nur dort); d.games.ow.passive spiegelt sie
-- (Vertrag §2). Ohne meta gilt ow.passive.
function OWRules.IsPassive(d: any): boolean
	local g = games(d)
	local m = g and g.meta or nil
	if type(m) == "table" then
		return m.passive == true
	end
	local o = OWRules.Data(d)
	return o ~= nil and o.passive == true
end

-- Rückgabe: true, wenn sich etwas geändert hat
function OWRules.PassiveSet(d: any, on: any, now: any): boolean
	if type(on) ~= "boolean" then
		return false
	end
	local o = OWRules.Ensure(d)
	if not o then
		return false
	end
	local g = games(d)
	local m = g and g.meta or nil
	local before = OWRules.IsPassive(d)
	o.passive = on
	if type(m) == "table" then
		m.passive = on
	end
	if before ~= on then
		o.lastPassiveAt = math.floor(nowOr(now))
		return true
	end
	return false
end

---------------------------------------------------------------- Anzeige (Snapshot)
export type Effect = { credits: number?, scrap: number?, parts: number?, partsEveryHours: number?, car: boolean? }

-- Wirkung einer Stufe als Zahlen je Stunde (für Karten und Tests)
function OWRules.Effect(typ: any, stage: any): Effect?
	local st = OWRules.Stage(typ, stage)
	if not st then
		return nil
	end
	return {
		credits = st.yieldPerHour, scrap = st.scrapPerHour, parts = st.partsPerHour,
		partsEveryHours = st.partsEveryHours, partsPerPack = st.partsPerPack,
		car = st.carModel ~= nil, carEveryHours = st.carEveryHours,
	}
end

function OWRules.Summary(d: any, now: any): { [string]: any }
	local t = nowOr(now)
	local buildings = {}
	for _, typ in ipairs(OW.Types) do
		local b = OWRules.Building(typ)
		if b then
			local built = OWRules.Built(d, typ)
			local stage = OWRules.StageOf(d, typ)
			local e = OWRules.Entry(d, typ)
			local ok, reason, cost = OWRules.CanBuild(d, typ, t)
			local st = OWRules.Stage(typ, stage + 1)
			local yield = OWRules.Collectable(d, typ, t)
			buildings[typ] = {
				name = b.name,
				stage = stage,
				built = built,
				maxStage = typ == "werkstatt" and (C.MaxBays or 4) or #b.Stages,
				readyAt = e and e.readyAt or 0,
				remaining = OWRules.Remaining(d, typ, t),
				building = e ~= nil and e.stage > e.built and t < e.readyAt,
				yield = yield and { credits = yield.credits, scrap = yield.scrap, parts = yield.parts, car = yield.car or false, hours = yield.hours } or false,
				effect = OWRules.Effect(typ, built) or false,
				next = st and { stage = st.stage, cost = cost, seconds = st.buildSeconds, level = OWRules.NextLevel(d, typ), ok = ok, reason = reason, effect = OWRules.Effect(typ, st.stage) } or false,
				perk = OWRules.Perk(d, typ),
			}
		end
	end
	return {
		buildings = buildings,
		passive = OWRules.IsPassive(d),
		perks = OWRules.Perks(d),
		capHours = capHours(),
	}
end

return OWRules
