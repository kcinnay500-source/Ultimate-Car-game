-- PrestigeService: Level & Prestige und Freischaltungen auf dem Server (docs/PHASE4_CONTRACT.md §4, §6).
-- Prestige = Rang ohne Reset (PrestigeRules.RankFor(d.level)); gespeichert sind nur die abgeholten Belohnungen.
-- Aufgaben:
--   Register(Actions, api)          Aktionen prestige_claim {rank} und unlocks_seen
--   OnJoin(ms, d, now)              merkt Level/Rang der Sitzung (keine Hinweise für alte Aufstiege)
--   Tick(ms, d, now) -> changed     erkennt Level-Aufstiege seit dem letzten Tick (ms.lastLevel) und reiht
--                                   mini_notice { kind="unlock" } je erreichter Freischaltung und
--                                   { kind="prestige", reached=true } je neuem Rang ein; true = Snapshot senden
--   Flush(ms)                       schickt eingereihte Hinweise (erst, wenn der Client zuhört: ms.greeted)
--   SnapshotFields(ms, d, now, full) -> { prestige = {...}, unlocks = {...} } für den Minispiel-Snapshot (§11)
-- Kein Geld: prestige_claim trägt nur claimed/titleRank (PrestigeRules.Claim), die Statistik prestigeClaims und –
-- sobald es d.games.shop gibt (Meilenstein 8) – die Kosmetik in shop.owned ein. Beginner-Hinweise zu
-- Freischaltungen ("unlock:<key>") reisen im unlock-Hinweis mit (Feld hint) und gelten dann als gesehen.
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local Unlocks = require(MiniShared:WaitForChild("Unlocks"))
local PrestigeRules = require(MiniShared:WaitForChild("PrestigeRules"))
local ShopRules = require(MiniShared:WaitForChild("ShopRules")) -- Meilenstein 8: Belohnungs-Kosmetik
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))

local PrestigeService = {}

local api -- MiniService-api: now, toast, notice, dirty, alive

local TEXT = {
	claimed = "Rang %d abgeholt: %s! Dein Credits-Bonus liegt jetzt bei +%d %%.",
	reached = "Neuer Prestige-Rang %d erreicht! Hol dir deine Belohnung im Tab „Prestige“.",
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function pctText(pct: any): number
	return finite(pct) and math.floor(pct + 0.5) or 0
end

---------------------------------------------------------------- Hinweise (Warteschlange je Sitzung)
local function queue(ms: any, kind: string, data: { [string]: any })
	ms.progressNotices = ms.progressNotices or {}
	table.insert(ms.progressNotices, { kind = kind, data = data })
end

-- Eingereihte Hinweise senden, sobald der Client nach 'hello' zuhört (ms.greeted setzt MiniService.Hello).
function PrestigeService.Flush(ms: any)
	local list = ms.progressNotices
	if not api or type(list) ~= "table" or #list == 0 then
		return
	end
	if ms.greeted == false then
		return
	end
	ms.progressNotices = {}
	for _, n in ipairs(list) do
		api.notice(ms, n.kind, n.data)
	end
end

---------------------------------------------------------------- Kosmetik (Meilenstein 8: d.games.shop.owned)
-- Belohnungs-Kosmetik über ShopRules.Grant (idempotent, nur bekannte Ids aus GameConfig.Shop.Cosmetics);
-- ShopRules.Load holt sie aus prestige.claimed bei älteren Profilen ebenfalls nach.
local function grantCosmetic(d: any, id: any): boolean
	if type(id) ~= "string" or id == "" then
		return false
	end
	local ok, res = ShopRules.Grant(d, { cosmetics = { id } }, api.now())
	return ok == true and type(res) == "table" and res.changed == true
end

---------------------------------------------------------------- Aktionen
local function claim(ms: any, data: any, d: any, now: number)
	local ok, res = PrestigeRules.Claim(d, data.rank)
	if not ok then
		if type(res) == "string" then
			api.toast(ms, res)
		end
		return -- nil = schon abgeholt (Doppelklick), still verwerfen
	end
	MiniRules.AddStat(d, "prestigeClaims", 1, now)
	local granted = grantCosmetic(d, res.cosmetic)
	api.notice(ms, "prestige", {
		claimed = true, rank = res.rank, title = res.title, cosmetic = res.cosmetic, cosmeticGranted = granted,
		incomePct = res.incomePct, discountPct = res.discountPct, tycoonRebirthPct = res.tycoonRebirthPct,
	})
	api.toast(ms, string.format(TEXT.claimed, res.rank, res.title, pctText(res.incomePct)))
	api.dirty(ms)
end

-- Der Spieler hat den Tab „Freischaltungen“ gesehen: neue Einträge (seit dem letzten Blick) gelten als gesehen.
local function unlocksSeen(ms: any, _: any, d: any)
	ms.unlocksSeenLevel = Unlocks.LevelOf(d)
	api.dirty(ms)
end

function PrestigeService.Register(Actions: any, a: any)
	api = a
	Actions.Register("prestige_claim", claim)
	Actions.Register("unlocks_seen", unlocksSeen)
end

---------------------------------------------------------------- Sitzung
function PrestigeService.OnJoin(ms: any, d: any, now: number?)
	ms.lastLevel = Unlocks.LevelOf(d)
	ms.lastRank = PrestigeRules.Rank(d)
	ms.unlocksSeenLevel = ms.lastLevel
	ms.progressNotices = {}
end

-- Level-Aufstieg seit dem letzten Tick (auch außerhalb der Minispiele: 2.4.0-Abrechnung, Quiz, Teststrecke …).
-- Rückgabe: true, wenn sich Level oder Rang geändert haben (Snapshot senden).
function PrestigeService.Tick(ms: any, d: any, now: number?): boolean
	local level = Unlocks.LevelOf(d)
	local rank = PrestigeRules.Rank(d)
	local last = ms.lastLevel
	if not finite(last) then
		-- ohne OnJoin (z. B. Sitzung vor der Verkabelung): nur merken, keine Hinweise für alte Aufstiege
		ms.lastLevel, ms.lastRank = level, rank
		ms.unlocksSeenLevel = ms.unlocksSeenLevel or level
		return false
	end
	if level == last and rank == (ms.lastRank or 0) then
		return false
	end
	if level > last then
		for _, u in ipairs(Unlocks.NewlyReached(last, level)) do
			local data = { key = u.key, title = u.title, level = u.level, kind = u.kind, tab = u.tab }
			local hint = MetaRules.HintFor(d, "unlock:" .. u.key)
			if hint then
				data.hint = hint.text
				data.hintId = hint.id
				MetaRules.MarkHint(d, hint.id)
			end
			queue(ms, "unlock", data)
		end
		local lastRank = finite(ms.lastRank) and ms.lastRank or 0
		if rank > lastRank then
			local reward = PrestigeRules.Reward(rank)
			queue(ms, "prestige", {
				reached = true, rank = rank, title = reward and reward.title or "",
				threshold = PrestigeRules.Threshold(rank), claimable = PrestigeRules.Claimable(d),
			})
			api.toast(ms, string.format(TEXT.reached, rank))
		end
	end
	ms.lastLevel, ms.lastRank = level, rank
	PrestigeService.Flush(ms)
	return true
end

---------------------------------------------------------------- Snapshot (§11)
-- full = false: reine Produktions-Snapshots lassen die große Tabelle unlocks.list weg (Client rechnet sie
-- notfalls selbst aus GameConfig.Unlocks und s.level nach); alles andere ist klein und immer dabei.
function PrestigeService.SnapshotFields(ms: any, d: any, now: number?, full: boolean?): { [string]: any }
	local level = Unlocks.LevelOf(d)
	local progress = PrestigeRules.Progress(level)
	local claimed = {}
	local pr = type(d.games) == "table" and d.games.prestige or nil
	if type(pr) == "table" and type(pr.claimed) == "table" then
		local n = 1
		while pr.claimed[n] == true do
			table.insert(claimed, n)
			n += 1
		end
	end
	local nextEntry = Unlocks.NextFor(d)
	local seenLevel = ms and finite(ms.unlocksSeenLevel) and ms.unlocksSeenLevel or level
	local unseen = 0
	if seenLevel < level then
		unseen = #Unlocks.NewlyReached(seenLevel, level)
	end
	local out = {
		prestige = {
			rank = progress.rank,
			maxRank = PrestigeRules.MaxRank,
			from = progress.from,
			next = progress.next, -- Level für den nächsten Rang; nil auf dem höchsten Rang
			pct = progress.pct,
			title = PrestigeRules.Title(d),
			titleRank = type(pr) == "table" and finite(pr.titleRank) and pr.titleRank or 0,
			claimable = PrestigeRules.Claimable(d),
			nextClaim = PrestigeRules.NextClaim(d),
			claimed = claimed,
			incomeBonus = PrestigeRules.IncomeBonus(d),
			discount = PrestigeRules.Discount(d),
		},
		unlocks = {
			level = level,
			next = nextEntry and { key = nextEntry.key, title = nextEntry.title, level = nextEntry.level, kind = nextEntry.kind, tab = nextEntry.tab, hint = nextEntry.hint } or false,
			unseen = unseen,
			total = #GameConfig.Unlocks,
		},
	}
	if full ~= false then
		out.unlocks.list = Unlocks.ListFor(d)
	end
	return out
end

return PrestigeService
