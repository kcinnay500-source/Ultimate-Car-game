-- PrestigeRules: Level & Prestige als reine Funktionen (docs/PHASE4_CONTRACT.md §4).
-- Prestige = Rang ohne Reset. Der Rang wird immer aus d.level berechnet (RankFor), gespeichert sind nur die
-- abgeholten Belohnungen: d.games.prestige = { claimed = { [rank] = true }, titleRank = int }.
-- claimed ist immer ein dichtes Feld 1..k (Abholen nur in Rang-Reihenfolge, Load behält nur den dichten
-- Anfang): ein lückenhaftes Feld wie { [1]=true, [3]=true } überlebt die JSON-Speicherung des DataStore nicht
-- (wird als Liste kodiert, Rang 3 ginge verloren; { [2]=true } käme als Zeichenketten-Schlüssel zurück).
-- Kein Geld, keine Instanzen: Credits-Bonus, Rabatt und Rebirth-Bonus sind Faktoren, die andere Module anwenden
-- (CrossBonus.PrestigeIncome -> IncomeBonus, Autohaus -> Discount, Tycoon -> RebirthBonus).
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))

local PrestigeRules = {}

export type Prestige = { claimed: { boolean }, titleRank: number }
export type Reward = GameConfig.PrestigeReward

local P = GameConfig.Prestige
local MAX_SAFE = 2 ^ 53

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---------------------------------------------------------------- Schwellen
-- Einmal berechnet: 100, 250, 500, dann ceil(vorherige × 1,8 / 50) × 50 (900, 1.650, 3.000, ...), Deckel MaxRank.
local THRESHOLDS: { number } = {}
for n = 1, P.MaxRank do
	local base = P.BaseThresholds[n]
	if base then
		THRESHOLDS[n] = base
	else
		-- kleine Toleranz gegen Gleitkomma-Reste (z. B. 900,0000000001 / 50 -> 18, nicht 19)
		THRESHOLDS[n] = math.ceil(THRESHOLDS[n - 1] * P.Growth / P.RoundTo - 1e-9) * P.RoundTo
	end
end
PrestigeRules.Thresholds = THRESHOLDS
PrestigeRules.MaxRank = P.MaxRank

-- Level, ab dem Rang n gilt; nil außerhalb 1..MaxRank
function PrestigeRules.Threshold(n: any): number?
	if type(n) ~= "number" or n ~= math.floor(n) then
		return nil
	end
	return THRESHOLDS[n]
end

-- Rang zu einem Level (0 = kein Rang); NaN/negativ -> 0
function PrestigeRules.RankFor(level: any): number
	if not finite(level) then
		return 0
	end
	local rank = 0
	for n = 1, P.MaxRank do
		if level >= THRESHOLDS[n] then
			rank = n
		else
			break
		end
	end
	return rank
end

-- Level für den nächsten Rang; nil auf dem höchsten Rang
function PrestigeRules.NextThreshold(level: any): number?
	local rank = PrestigeRules.RankFor(level)
	return THRESHOLDS[rank + 1]
end

-- Für das HUD: Rang, aktuelle und nächste Schwelle, Anteil 0..1 auf dem Weg zum nächsten Rang
function PrestigeRules.Progress(level: any): { rank: number, from: number, next: number?, pct: number }
	local lvl = finite(level) and math.max(0, level) or 0
	local rank = PrestigeRules.RankFor(lvl)
	local from = rank > 0 and THRESHOLDS[rank] or 0
	local nextAt = THRESHOLDS[rank + 1]
	local pct = 1
	if nextAt then
		pct = math.clamp((lvl - from) / (nextAt - from), 0, 1)
	end
	return { rank = rank, from = from, next = nextAt, pct = pct }
end

---------------------------------------------------------------- Profil
local function levelOf(d: any): number
	local lvl = type(d) == "table" and d.level or nil
	return finite(lvl) and lvl or 1
end

local function prestigeOf(d: any): Prestige?
	local g = type(d) == "table" and d.games or nil
	local pr = type(g) == "table" and g.prestige or nil
	return type(pr) == "table" and pr or nil
end

-- Anzahl der abgeholten Ränge = Länge des dichten Anfangs
local function claimedCount(pr: Prestige): number
	local n = 0
	local claimed = pr.claimed
	if type(claimed) ~= "table" then
		return 0
	end
	while n < P.MaxRank and claimed[n + 1] == true do
		n += 1
	end
	return n
end

function PrestigeRules.Default(): Prestige
	return { claimed = {}, titleRank = 0 }
end

-- raw = gespeichertes d.games.prestige (oder nil), d = Profil mit geladenem d.level. Idempotent; NaN/Müll ->
-- Standard. Behalten wird nur der dichte Anfang 1..k der Abholungen (auch mit "1"-Zeichenketten-Schlüsseln aus
-- einer JSON-Kodierung), höchstens bis zum aus dem Level berechneten Rang. titleRank höchstens = k.
function PrestigeRules.Load(raw: any, d: any, now: any): Prestige
	local pr = PrestigeRules.Default()
	if type(raw) ~= "table" then
		return pr
	end
	local rc = type(raw.claimed) == "table" and raw.claimed or {}
	local limit = P.MaxRank
	if type(d) == "table" and finite(d.level) then
		limit = math.min(limit, PrestigeRules.RankFor(d.level))
	end
	local n = 0
	while n < limit do
		local v = rc[n + 1]
		if v == nil then
			v = rc[tostring(n + 1)]
		end
		if v ~= true then
			break
		end
		n += 1
		pr.claimed[n] = true
	end
	local title = raw.titleRank
	if finite(title) and title >= 1 then
		pr.titleRank = math.min(math.floor(math.min(title, MAX_SAFE)), n)
	end
	return pr
end

---------------------------------------------------------------- Rang und Boni
function PrestigeRules.Rank(d: any): number
	return PrestigeRules.RankFor(levelOf(d))
end

-- Faktor auf alle Credits-Einnahmen: 1 + 0,02 je Rang, Deckel +30 % (CrossBonus.PrestigeIncome)
function PrestigeRules.IncomeBonus(d: any): number
	return 1 + math.min(PrestigeRules.Rank(d) * P.IncomePerRank, P.IncomeCap)
end

-- Rabatt im Autohaus als Anteil 0..0,10 (1 % je Rang)
function PrestigeRules.Discount(d: any): number
	return math.min(PrestigeRules.Rank(d) * P.DiscountPerRank, P.DiscountCap)
end

-- Zusätzlicher Tycoon-Rebirth-Bonus als Anteil (ab Rang 3: +5 %)
function PrestigeRules.RebirthBonus(d: any): number
	if PrestigeRules.Rank(d) >= P.RebirthBonusFromRank then
		return P.RebirthBonus
	end
	return 0
end

function PrestigeRules.Reward(rank: any): Reward?
	if type(rank) ~= "number" or rank ~= math.floor(rank) then
		return nil
	end
	return P.Rewards[rank]
end

-- Angezeigter Titel ("" ohne abgeholten Rang)
function PrestigeRules.Title(d: any): string
	local pr = prestigeOf(d)
	local reward = pr and PrestigeRules.Reward(pr.titleRank)
	return reward and reward.title or ""
end

---------------------------------------------------------------- Abholen
-- Erreichte, noch nicht abgeholte Ränge (aufsteigend). Abgeholt wird in dieser Reihenfolge (NextClaim).
function PrestigeRules.Claimable(d: any): { number }
	local out = {}
	local pr = prestigeOf(d)
	if not pr then
		return out
	end
	local have = claimedCount(pr)
	for rank = have + 1, PrestigeRules.Rank(d) do
		table.insert(out, rank)
	end
	return out
end

-- Der Rang, der als Nächstes abgeholt werden kann; nil, wenn nichts offen ist
function PrestigeRules.NextClaim(d: any): number?
	local pr = prestigeOf(d)
	if not pr then
		return nil
	end
	local nextRank = claimedCount(pr) + 1
	if nextRank <= PrestigeRules.Rank(d) then
		return nextRank
	end
	return nil
end

-- Belohnung eines Rangs abholen (rein: kein Geld, keine Statistik – der Dienst zählt prestigeClaims und
-- trägt die Kosmetik ein). Rückgabe: ok, Belohnung | Meldung (nil = Doppelklick, still verwerfen).
function PrestigeRules.Claim(d: any, rank: any): (boolean, any)
	local pr = prestigeOf(d)
	if not pr then
		return false, "Prestige ist noch nicht geladen."
	end
	if type(rank) ~= "number" or rank ~= math.floor(rank) or rank < 1 or rank > P.MaxRank then
		return false, "Unbekannter Rang."
	end
	if pr.claimed[rank] == true then
		return false, nil
	end
	if rank > PrestigeRules.Rank(d) then
		return false, "Rang " .. rank .. " gibt es ab Level " .. THRESHOLDS[rank] .. "."
	end
	local nextRank = claimedCount(pr) + 1
	if rank ~= nextRank then
		return false, "Hol zuerst Rang " .. nextRank .. " ab."
	end
	pr.claimed[rank] = true
	if rank > pr.titleRank then
		pr.titleRank = rank
	end
	return true, P.Rewards[rank]
end

-- Angezeigten Titel wählen: 0 = keiner, sonst ein abgeholter Rang
function PrestigeRules.SetTitle(d: any, rank: any): boolean
	local pr = prestigeOf(d)
	if not pr or type(rank) ~= "number" or rank ~= math.floor(rank) or rank < 0 then
		return false
	end
	if rank > 0 and pr.claimed[rank] ~= true then
		return false
	end
	pr.titleRank = rank
	return true
end

return PrestigeRules
