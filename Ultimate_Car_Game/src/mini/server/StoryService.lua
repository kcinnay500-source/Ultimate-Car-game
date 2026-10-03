-- StoryService: Story „Vom Kiesplatzhändler zum Mega-Verkäufer“, Kiesplatz-Verkauf, Nebenmissionen, Lieferungen und
-- Co-op auf dem Server (docs/PHASE4_CONTRACT.md §7, §10–§12). Regeln und Zahlen: StoryRules (rein) und GameConfig.Story.
-- Geld/XP ändern nur StoryRules.Claim/SideClaim/Sell (innerhalb von Handle, also in request()).
--
-- Schnittstelle für MiniService:
--   Register(Actions, api)            story_start {id}, story_claim {id}, story_sell {offer, price}, side_claim {id}
--                                     (api wie bei PressService: now, toast, notice, dirty, alive, writable)
--   Init(ctx)                         ctx aus MiniService.Init (getSession, emit, now)
--   OnJoin(ms, d, now)                Sitzung merken, d.games.story sicherstellen, Tageswechsel, erster Kunde
--   OnMode(ms, d, mode)               Moduswechsel: außerhalb der Open World kein Kunde, keine Lieferung
--   OnStat(ms, d, key, delta)         Statistik gestiegen (MiniRules.AddStat; Integrator ruft es aus MiniService.OnSettled
--                                     und den Diensten bzw. zentral): Story-/Nebenmissionen, Co-op
--   OnEvent(ms, d, event, data?)      Ereignis: "settle", "car_bought", "auction_won", "auction_consigned", "track_finish" {time},
--                                     "arcade_round", "ow_built:<typ>", "action:<aktion>" (nach jeder gelungenen Aktion),
--                                     3.x: "pw_repair" {car, gain}, "pw_parts_sold" {part, count, value} (PublicWorkshopService
--                                     über api.storyEvent), "delivery" … Zu "settle" meldet der Dienst selbst die Art des
--                                     abgerechneten Auftrags ("settle:<art>", ein Fahrzeug-Check zusätzlich "settle:inspection").
--   Tick(ms, d, now) -> changed       alle 0,5 s: Tageswechsel, Kunden am Kiesplatz (nur solange die Figur in Reichweite der
--                                     Station ist), Bedingungs-Missionen, Lieferfahrten; 3.x: Story ohne „Starten“ (die
--                                     aktuelle Mission startet in der Open World von selbst, StoryRules.AutoStart) und die
--                                     Profil-Ereignisse "parts_bought" (Ersatzteile gekauft: Lager + Bestellungen wachsen) und
--                                     "equipment_bought" (Werkstattgerät gekauft: Summe d.equipment wächst)
--   OnStartChosen(ms, d, now)         3.x: Startwahl getroffen (StartService): Mission 1 des Wegs läuft sofort
--   ResetChapter1(ms, d)              3.x: Kapitel 1 von vorn (StartService.ResetStart, Entwickler-Menü)
--   OnLeave(ms)                       Sitzung vergessen
--   SnapshotFields(ms, d, now, full)  { story = StoryRules.View(...) } (missions/chapters nur bei full)
-- Co-op (§7): Fortschritt eines Party-Mitglieds (LobbyService.PartyOf) zählt für alle Mitglieder mit derselben aktiven
-- Mission im selben Server (StoryRules.CoopApply, geteilte Arten stat/event/sell). Belohnung holt jeder selbst.
-- Passiv-Modus (§5): story_start/story_sell abgelehnt, Ereignisse zählen nicht, Co-op überträgt nichts an Passive.
-- Welt: City.Stations.kiesplatz (Reichweite für Kunden und story_sell, optional), City.Missions.Delivery_<n> mit Teilen
-- Role="start"/"end" (sonst Namen Start/Ziel) – die Lieferung erkennt den Rumpf des eigenen Autos (workspace.PlayerCars.Car_<UserId>)
-- und prüft die Strecke seit dem letzten Tick (Segment gegen Teil + Slack), damit auch schnelle Durchfahrten zählen.
-- Kiesplatz-Wurf: der Seed enthält ein Server-Geheimnis (SALT je Serverstart) – aus Snapshot-Feldern (offer = Serial)
-- lässt sich der Wurf nicht nachrechnen. Der Kunden-Takt (sales.nextAt) liegt im Profil und überlebt Moduswechsel/Rejoin.
-- Alle Instanz-Arbeit läuft in pcall; ohne Welt läuft die Story trotzdem (nur ohne Lieferungen/Reichweite).
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local StoryRules = require(MiniShared:WaitForChild("StoryRules"))
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local LobbyService = require(script.Parent:WaitForChild("LobbyService"))
local CarService = require(script.Parent:WaitForChild("CarService"))

local StoryService = {}

export type Session = {
	sale: any, nextAt: number, delivery: any, seen: { [string]: number }, routesAt: number, routes: { any }, checkAt: number,
	lastPos: Vector3?, jobs: { [string]: any }?, partsTotal: number?, equipTotal: number?,
}

StoryService.Sessions = setmetatable({}, { __mode = "k" }) :: { [Player]: any } -- [Player] = ms

local api -- MiniService-api: now, toast, notice, dirty, alive, writable
local ctx -- GarageServer-Kontext (getSession, emit, now)
local CHECK_INTERVAL = 1 -- Bedingungs-Missionen und Legende höchstens 1×/s prüfen
local ROUTES_INTERVAL = 5 -- Lieferrouten höchstens alle 5 s neu suchen
-- Server-Geheimnis für den Kiesplatz-Seed (je Serverstart; nie im Snapshot, nie im Profil)
local SALT = tostring(Random.new():NextInteger(1, 2 ^ 31 - 1)) .. ":" .. tostring(math.floor((os.clock() % 1) * 1e6))

---------------------------------------------------------------- Hilfen
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

local function S(): any
	return StoryRules.Config()
end

local function toast(ms: any, text: string?)
	if api and ms and type(text) == "string" and text ~= "" then
		api.toast(ms, text)
	end
end

local function notice(ms: any, kind: string, data: { [string]: any })
	if api and ms then
		api.notice(ms, kind, data)
	end
end

local function dirty(ms: any)
	if api and ms then
		api.dirty(ms)
	end
end

local function alive(ms: any): boolean
	if not ms or not ms.player then
		return false
	end
	if api and type(api.alive) == "function" then
		return api.alive(ms) == true
	end
	return ms.player.Parent ~= nil
end

local function dataOf(ms: any): any
	local p = ms and ms.p
	local prof = p and p.profile
	return prof and prof.data or nil
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

local function inOpenWorld(ms: any): boolean
	local mode = ms and ms.p and ms.p.mode or nil
	return mode == nil or mode == "openworld"
end

local function passive(d: any): boolean
	return MetaRules.IsPassive(d)
end

local function session(ms: any): Session
	if type(ms.story) ~= "table" then
		ms.story = { sale = false, nextAt = 0, delivery = false, seen = {}, routesAt = -math.huge, routes = {}, checkAt = -math.huge, lastPos = nil,
			jobs = nil, partsTotal = nil, equipTotal = nil }
	end
	return ms.story
end

local function levelOf(d: any): number
	return finite(d and d.level) and d.level or 1
end

---------------------------------------------------------------- Hinweise und Co-op
-- Änderungen an Missionen melden: mini_notice { kind = "mission", id, progress, target, done, side }, Toast bei Erfüllung
local function announce(ms: any, changes: { any })
	local any = false
	for _, c in ipairs(changes) do
		if type(c) == "table" then
			any = true
			notice(ms, "mission", { id = c.id, title = c.title, progress = c.progress, target = c.target, done = c.done, side = c.side == true })
			if c.done then
				toast(ms, (c.side and "Nebenmission geschafft: „" or "Mission geschafft: „") .. c.title .. "“ – hol dir die Belohnung im Tab „Story“!")
			end
		end
	end
	if any then
		dirty(ms)
	end
end

-- Geteilten Fortschritt an die Party-Mitglieder übertragen (gleiche aktive Mission, nicht passiv, im Server)
local function share(ms: any, d: any, changes: { any })
	local party = LobbyService.PartyOf and LobbyService.PartyOf(ms.player) or nil
	if type(party) ~= "table" or type(party.members) ~= "table" then
		return
	end
	for _, c in ipairs(changes) do
		if type(c) == "table" and not c.side and finite(c.delta) and c.delta > 0 then
			for _, member in ipairs(party.members) do
				local other = member ~= ms.player and StoryService.Sessions[member] or nil
				local d2 = other and alive(other) and dataOf(other) or nil
				if d2 and d2 ~= d and not passive(d2) then
					local change = StoryRules.CoopApply(d, d2, c.id, c.delta, now())
					if change then
						notice(other, "mission", { id = change.id, title = change.title, progress = change.progress, target = change.target, done = change.done, side = false, coop = true, from = playerName(ms.player) })
						toast(other, string.format(S().Texts.coop, playerName(ms.player), change.title, change.progress, change.target))
						dirty(other)
					end
				end
			end
		end
	end
end

local function progressWith(ms: any, d: any, fn: () -> { any })
	if type(d) ~= "table" or passive(d) then
		return
	end
	local changes = fn()
	announce(ms, changes)
	share(ms, d, changes)
end

---------------------------------------------------------------- Story ohne „Starten“ (3.x)
local function partySize(ms: any): number
	local party = LobbyService.PartyOf and LobbyService.PartyOf(ms.player) or nil
	return type(party) == "table" and type(party.members) == "table" and #party.members or 0
end

-- Mission gestartet (von Hand oder automatisch): Hinweis, Toast, Bedingungen gleich prüfen (z. B. schon erfüllt)
local function announceStart(ms: any, d: any, def: any, auto: boolean)
	local cur = StoryRules.Current(d)
	notice(ms, "story", { event = "started", chapter = cur.chapter, mission = def.id, title = def.title, text = def.text, auto = auto })
	if auto then
		toast(ms, string.format(S().Texts.autoStarted or "Neue Mission: „%s“", def.title))
	else
		toast(ms, string.format(S().Texts.started, def.title, def.text))
	end
	local view = StoryRules.MissionView(d, def, levelOf(d))
	session(ms).seen[def.id] = view.progress
	if view.claimable then
		announce(ms, { { id = def.id, title = def.title, progress = view.progress, target = view.target, done = true, side = false, delta = 0 } })
	end
	dirty(ms)
end

-- Aktuelle Mission von selbst starten: nur in der Open World, nicht im Passiv-Modus, nicht vor der Startwahl.
-- Rückgabe: die gestartete Mission oder nil
local function autoStart(ms: any, d: any, t: number): any
	if type(d) ~= "table" or not inOpenWorld(ms) or passive(d) or MetaRules.StartPending(d) then
		return nil
	end
	local def = StoryRules.AutoStart(d, t, partySize(ms), levelOf(d))
	if def then
		announceStart(ms, d, def, true)
	end
	return def
end
StoryService.AutoStart = autoStart

---------------------------------------------------------------- Profil-Ereignisse (3.x): Auftragsart beim Abrechnen, Teile-/Gerätekauf
local function jobMap(d: any): { [string]: any }
	local out = {}
	for _, j in ipairs(type(d) == "table" and type(d.jobs) == "table" and d.jobs or {}) do
		if type(j) == "table" and type(j.id) == "string" and type(j.kind) == "string" then
			-- Fahrzeug-Check: Art "inspection", nach der Kundenfreigabe die Art des Befunds (mit Salz/Check-Vergütung)
			local check = j.kind == "inspection" or type(j.salt) == "number" or j.inspectionBonus ~= nil or j.finding ~= nil
			out[j.id] = { kind = j.kind, phase = j.phase, check = check }
		end
	end
	return out
end

local function sumValues(t: any): number
	local n = 0
	for _, v in pairs(type(t) == "table" and t or {}) do
		if finite(v) and v > 0 then
			n += v
		end
	end
	return n
end

local function partsTotal(d: any): number
	local n = sumValues(type(d) == "table" and d.inventory or nil)
	for _, o in ipairs(type(d) == "table" and type(d.orders) == "table" and d.orders or {}) do
		if type(o) == "table" and finite(o.qty) and o.qty > 0 then
			n += o.qty
		end
	end
	return n
end

local function equipTotal(d: any): number
	return sumValues(type(d) == "table" and d.equipment or nil)
end

-- Stand merken (Tick) bzw. Käufe melden; Rückgabe: Liste { event, data }
local function trackProfile(ms: any, d: any): { any }
	local ss = session(ms)
	local out = {}
	local parts, equip = partsTotal(d), equipTotal(d)
	if ss.partsTotal ~= nil and parts > ss.partsTotal then
		table.insert(out, { "parts_bought", { count = parts - ss.partsTotal } })
	end
	if ss.equipTotal ~= nil and equip > ss.equipTotal then
		table.insert(out, { "equipment_bought", { count = equip - ss.equipTotal } })
	end
	ss.partsTotal, ss.equipTotal = parts, equip
	ss.jobs = jobMap(d)
	return out
end

-- Abgerechneter Auftrag (Mini.OnSettled -> OnEvent "settle"): der Auftrag, der seit dem letzten Tick aus d.jobs
-- verschwunden ist (bevorzugt einer in Phase invoice). Rückgabe: Ereignisse "settle:<art>" (+ "settle:inspection")
local function settledEvents(ms: any, d: any): { string }
	local ss = session(ms)
	local before = ss.jobs
	if type(before) ~= "table" then
		return {}
	end
	local now = jobMap(d)
	local pick, pickId = nil, nil
	for id, j in pairs(before) do
		if not now[id] and (pick == nil or (j.phase == "invoice" and pick.phase ~= "invoice")) then
			pick, pickId = j, id
		end
	end
	if not pick then
		return {}
	end
	before[pickId] = nil -- nie doppelt zählen
	local out = { "settle:" .. tostring(pick.kind) }
	if pick.check and pick.kind ~= "inspection" then
		table.insert(out, "settle:inspection")
	end
	return out
end

---------------------------------------------------------------- Kiesplatz
local function station(key: string): Instance?
	local city = workspace:FindFirstChild("City")
	local stations = city and city:FindFirstChild("Stations")
	return stations and stations:FindFirstChild(key) or nil
end

-- Reichweite zur Kiesplatz-Station (nur geprüft, wenn es sie gibt)
local function nearKiesplatz(ms: any): boolean
	local ok, res = pcall(function()
		local st = station("kiesplatz")
		if not st then
			return true
		end
		local ch = ms.player.Character
		local root = ch and ch:FindFirstChild("HumanoidRootPart")
		if not root then
			return false
		end
		local pos
		if st:IsA("BasePart") then
			pos = st.Position
		elseif st:IsA("Model") then
			pos = st:GetPivot().Position
		else
			return true
		end
		return (pos - root.Position).Magnitude <= (S().Sale.Range or 45)
	end)
	return ok and res == true
end

local function newOffer(ms: any, d: any, t: number)
	local ss = session(ms)
	local st = StoryRules.Data(d)
	local serial = st and st.sales.serial + 1 or 1
	local offer = StoryRules.NextSale(d, SALT .. ":" .. tostring(ms.userId or (ms.player and ms.player.UserId) or 0) .. ":" .. tostring(serial), levelOf(d))
	offer.at = t
	ss.sale = offer
	ss.nextAt = t
	dirty(ms)
end

local storyStart -- unten definiert (storySell startet eine Verkaufsmission automatisch)

local function storySell(ms: any, data: any, d: any, t: number)
	local ss = session(ms)
	local T = S().Sale.Texts
	if passive(d) then
		toast(ms, S().Texts.passive)
		return
	end
	if not inOpenWorld(ms) then
		toast(ms, T.notOpenWorld)
		return
	end
	local offer = ss.sale
	if type(offer) ~= "table" then
		toast(ms, T.noOffer)
		return
	end
	if data.offer ~= offer.serial then
		toast(ms, T.wrongOffer)
		return
	end
	local tier = data.price
	if type(tier) ~= "number" or tier ~= math.floor(tier) or tier < 1 or tier > 3 then
		toast(ms, T.badTier)
		return
	end
	if not nearKiesplatz(ms) then
		toast(ms, T.notHere)
		return
	end
	-- Verkauf vor „Starten“: ist die aktuelle Story-Mission eine Verkaufsmission (Kapitel offen, nichts aktiv),
	-- startet sie jetzt automatisch – sonst zählten die ersten Verkäufe nicht (c1_m1 „Drei Gebrauchtwagen verkaufen“)
	local cur = StoryRules.Current(d)
	if type(cur.active) ~= "table" and cur.mission and cur.mission.kind == "sell" and StoryRules.ChapterOpen(d, cur.chapter) then
		storyStart(ms, { id = cur.mission.id, auto = true }, d, t)
	end
	local res = StoryRules.Sell(d, offer, tier, t)
	if not res then
		toast(ms, T.badTier)
		return
	end
	ss.sale = false
	ss.nextAt = t + (res.sold and (S().Sale.OfferInterval or 45) or (S().Sale.FailInterval or 20))
	StoryRules.ScheduleNext(d, ss.nextAt)
	notice(ms, "story", {
		event = "sale", offer = offer.serial, customer = offer.customer, sold = res.sold, tier = tier,
		credits = res.credits, xp = res.xp, special = res.special, text = res.text, chapter = StoryRules.Current(d).chapter,
	})
	toast(ms, res.text)
	announce(ms, res.changed)
	share(ms, d, res.changed)
	dirty(ms)
	return true -- Angebot beantwortet (verkauft oder nicht): Tutorial-Schritt "action:story_sell"
end

---------------------------------------------------------------- Aktionen
function storyStart(ms: any, data: any, d: any, t: number)
	if passive(d) then
		toast(ms, S().Texts.passive)
		return
	end
	-- 3.x: die Story startet ihre Missionen selbst; ein „Starten“ der schon laufenden Mission ist kein Fehler
	local st = StoryRules.Data(d)
	if st and type(st.active) == "table" and st.active.id == data.id then
		dirty(ms)
		return true
	end
	local ok, res = StoryRules.Start(d, data.id, t, partySize(ms))
	if not ok then
		if not data.auto then
			toast(ms, res)
		end
		return
	end
	-- Bedingungs-Missionen können sofort erfüllt sein (z. B. Hebebühne 2 schon gekauft)
	announceStart(ms, d, res, data.auto == true)
	return true
end

local function storyClaim(ms: any, data: any, d: any, t: number)
	local ok, res = StoryRules.Claim(d, data.id, t)
	if not ok then
		if type(res) == "string" then
			toast(ms, res)
		end
		return
	end
	local T = S().Texts
	notice(ms, "story", {
		event = "claimed", chapter = res.chapter, mission = res.mission.id, title = res.mission.title, credits = res.credits, xp = res.xp,
		cosmetic = res.cosmetic, cosmeticGranted = res.cosmeticGranted, titleReward = res.title,
		chapterDone = res.chapterDone, chapterXp = res.chapterXp, nextChapter = res.nextChapter, nextLevel = res.nextLevel, finished = res.finished,
		text = res.chapterDone and (res.finished and T.storyDone or string.format(T.chapterDone, res.chapter, (StoryRules.ChapterInfo(d, res.chapter)), res.chapterXp, res.nextChapter, res.nextLevel)) or "",
	})
	toast(ms, string.format(T.claimed, res.mission.title, MiniLocale.Credits(res.credits), res.xp))
	if res.chapterDone then
		if res.finished then
			toast(ms, T.storyDone)
		else
			toast(ms, string.format(T.chapterDone, res.chapter, (StoryRules.ChapterInfo(d, res.chapter)), res.chapterXp, res.nextChapter, res.nextLevel))
		end
	end
	session(ms).seen = {}
	autoStart(ms, d, t) -- 3.x: die nächste Mission läuft gleich an (Kapitel offen, Open World, nicht passiv)
	dirty(ms)
	return true
end

local function sideClaim(ms: any, data: any, d: any, t: number)
	local ok, res = StoryRules.SideClaim(d, data.id, t, levelOf(d))
	if not ok then
		if type(res) == "string" then
			toast(ms, res)
		end
		return
	end
	notice(ms, "story", { event = "side_claimed", mission = res.def.id, title = res.def.title, credits = res.credits, xp = res.xp, legend = res.def.legend == true })
	toast(ms, string.format(S().Texts.sideClaimed, res.def.title, MiniLocale.Credits(res.credits), res.xp))
	dirty(ms)
end

function StoryService.Register(Actions: any, a: any)
	api = a
	Actions.Register("story_start", storyStart)
	Actions.Register("story_claim", storyClaim)
	Actions.Register("story_sell", storySell)
	Actions.Register("side_claim", sideClaim)
end

function StoryService.Init(c: any)
	ctx = type(c) == "table" and c or nil
end

---------------------------------------------------------------- Ereignisse (vom Integrator aufgerufen)
function StoryService.OnStat(ms: any, d: any, key: any, delta: any)
	if not ms or type(key) ~= "string" then
		return
	end
	delta = finite(delta) and delta or 1
	progressWith(ms, d, function()
		return StoryRules.OnStat(d, key, delta, now())
	end)
end

function StoryService.OnEvent(ms: any, d: any, event: any, data: any)
	if not ms or type(event) ~= "string" then
		return
	end
	local t = now()
	progressWith(ms, d, function()
		local changes = StoryRules.OnEvent(d, event, data, t)
		-- 3.x: Art des abgerechneten Auftrags (Ölwechsel, Fahrzeug-Check …) für Kapitel 1 „Werkstatt“
		if event == "settle" then
			for _, ev in ipairs(settledEvents(ms, d)) do
				for _, c in ipairs(StoryRules.OnEvent(d, ev, data, t)) do
					table.insert(changes, c)
				end
			end
		end
		return changes
	end)
	if event == "pw_repair" and type(d) == "table" and not passive(d) then
		toast(ms, S().Sale.Texts.repairedReady)
		dirty(ms)
	end
end

-- 3.x: Startwahl getroffen (StartService nach start_choose): Kapitel 1 des Wegs läuft sofort mit Mission 1.
-- Rückgabe: die gestartete Mission oder nil
function StoryService.OnStartChosen(ms: any, d: any, t: number?): any
	if not ms or type(d) ~= "table" then
		return nil
	end
	StoryService.Sessions[ms.player] = ms
	session(ms).seen = {}
	return autoStart(ms, d, finite(t) and t or now())
end

-- 3.x: Kapitel 1 von vorn (StartService.ResetStart): erledigte Kapitel-1-Missionen und die laufende sind weg; die
-- erste Mission startet wieder nach der neuen Startwahl. Rückgabe: true, wenn sich etwas geändert hat
function StoryService.ResetChapter1(ms: any, d: any): boolean
	local changed = StoryRules.ResetChapter1(d)
	if ms then
		local ss = session(ms)
		ss.seen = {}
		dirty(ms)
	end
	return changed
end

---------------------------------------------------------------- Lieferungen (City.Missions.Delivery_<n>)
local function routePart(folder: Instance, role: string, names: { string }): Instance?
	for _, x in ipairs(folder:GetChildren()) do
		if x:IsA("BasePart") and x:GetAttribute("Role") == role then
			return x
		end
	end
	for _, n in ipairs(names) do
		local x = folder:FindFirstChild(n)
		if x and x:IsA("BasePart") then
			return x
		end
	end
	return nil
end

local function findRoutes(): { any }
	local out = {}
	local city = workspace:FindFirstChild("City")
	local missions = city and city:FindFirstChild("Missions")
	if not missions then
		return out
	end
	for _, x in ipairs(missions:GetChildren()) do
		local n = tonumber(string.match(x.Name, "^Delivery_(%d+)$"))
		if n then
			local start = routePart(x, "start", { "Start" })
			local finish = routePart(x, "end", { "Ziel", "End", "Finish" })
			if start and finish then
				table.insert(out, { n = n, start = start, finish = finish })
			end
		end
	end
	table.sort(out, function(a, b)
		return a.n < b.n
	end)
	return out
end

local function routes(ss: Session, t: number): { any }
	if t - ss.routesAt >= ROUTES_INTERVAL then
		ss.routesAt = t
		local ok, res = pcall(findRoutes)
		ss.routes = ok and res or {}
	end
	return ss.routes
end

-- Rumpf des eigenen gespawnten Autos (CarService: workspace.PlayerCars.Car_<UserId>, Chassis)
local function carChassis(ms: any): BasePart?
	local okId, id = pcall(CarService.SpawnedCarId, ms.player)
	if okId and id == 0 then
		return nil
	end
	local folder = workspace:FindFirstChild("PlayerCars")
	local model = folder and folder:FindFirstChild("Car_" .. tostring(ms.player.UserId))
	if not model then
		return nil
	end
	local chassis = model:FindFirstChild("Chassis") or model.PrimaryPart
	return chassis and chassis:IsA("BasePart") and chassis or nil
end

-- Hat der Rumpf das Teil berührt? Geprüft wird die Strecke vom letzten Tick (prev) bis jetzt (pos) gegen eine Kugel um
-- das Teil (halbe Diagonale + Slack): nächster Punkt des Segments zur Teilmitte. So zählt eine Durchfahrt mit 70 Studs
-- je Tick genauso wie ein Stillstand im Teil. Sprünge über MaxStep (Schnellreise, Spawn) prüfen nur den Endpunkt.
local function touching(part: BasePart, pos: Vector3, prev: Vector3?): boolean
	local D = S().Side.Delivery
	local radius = part.Size.Magnitude / 2 + (D.Slack or 6)
	local centre = part.Position
	if prev and (pos - prev).Magnitude <= (D.MaxStep or 120) then
		local ab = pos - prev
		local len2 = ab:Dot(ab)
		local k = len2 > 0 and math.clamp((centre - prev):Dot(ab) / len2, 0, 1) or 0
		local nearest = prev + ab * k
		return (centre - nearest).Magnitude <= radius
	end
	return (centre - pos).Magnitude <= radius
end

local function tickDelivery(ms: any, d: any, t: number): boolean
	local ss = session(ms)
	local D = S().Side.Delivery
	if not inOpenWorld(ms) or passive(d) or not StoryRules.WantsEvent(d, "delivery", t) then
		ss.lastPos = nil
		if ss.delivery then
			ss.delivery = false
			return true
		end
		return false
	end
	local list = routes(ss, t)
	if #list == 0 then
		ss.lastPos = nil
		return false
	end
	local chassis = carChassis(ms)
	if not chassis then
		ss.lastPos = nil
		return false
	end
	local pos = chassis.Position
	local prev = ss.lastPos
	ss.lastPos = pos
	local run = ss.delivery
	if type(run) == "table" then
		if t - run.startedAt > (D.TimeLimit or 240) then
			ss.delivery = false
			toast(ms, D.Texts.expired)
			notice(ms, "story", { event = "delivery", state = "expired", route = run.n })
			return true
		end
		if touching(run.finish, pos, prev) then
			ss.delivery = false
			local took = math.floor(t - run.startedAt)
			toast(ms, string.format(D.Texts.done, run.n, took))
			notice(ms, "story", { event = "delivery", state = "done", route = run.n, time = took })
			progressWith(ms, d, function()
				return StoryRules.OnEvent(d, "delivery", { route = run.n, time = took }, t)
			end)
			return true
		end
		return false
	end
	for _, r in ipairs(list) do
		if touching(r.start, pos, prev) then
			ss.delivery = { n = r.n, finish = r.finish, startedAt = t }
			toast(ms, string.format(D.Texts.started, r.n, D.TimeLimit or 240))
			notice(ms, "story", { event = "delivery", state = "started", route = r.n, limit = D.TimeLimit or 240 })
			return true
		end
	end
	return false
end

---------------------------------------------------------------- Sitzung
function StoryService.OnJoin(ms: any, d: any, t: number?)
	t = finite(t) and t or now()
	StoryService.Sessions[ms.player] = ms
	local ss = session(ms)
	StoryRules.Data(d)
	StoryRules.EnsureSideDay(d, t)
	trackProfile(ms, d) -- Stand für Teile-/Gerätekauf und Auftragsart merken (nichts melden)
	-- Der Takt nach einem Verkauf (OfferInterval/FailInterval) steht im Profil: ein Rejoin bringt keinen früheren Kunden
	ss.nextAt = math.max(StoryRules.NextOfferAt(d), t + (S().Sale.FirstOfferDelay or 2))
end

function StoryService.OnMode(ms: any, d: any, mode: any)
	StoryService.Sessions[ms.player] = ms
	local ss = session(ms)
	if mode ~= "openworld" then
		if type(ss.sale) == "table" then
			StoryRules.OfferGone(d, ss.sale) -- der Kunde kommt nicht mit demselben Wurf zurück
		end
		ss.sale = false
		ss.delivery = false
		ss.lastPos = nil
		ss.nextAt = math.max(ss.nextAt, StoryRules.NextOfferAt(d), now() + (S().Sale.FirstOfferDelay or 2))
		dirty(ms)
	end
end

-- Rückgabe: true, wenn der Snapshot gesendet werden soll
function StoryService.Tick(ms: any, d: any, t: number?): boolean
	t = finite(t) and t or now()
	if type(d) ~= "table" then
		return false
	end
	local ss = session(ms)
	local changed = false
	if StoryRules.EnsureSideDay(d, t) then
		changed = true
	end
	-- 3.x: Teile-/Gerätekauf aus dem Profil (2.4.0-Aktionen laufen nicht über MiniService) und Auftragsliste merken
	for _, e in ipairs(trackProfile(ms, d)) do
		StoryService.OnEvent(ms, d, e[1], e[2])
		changed = true
	end
	-- Kiesplatz: Kunde kommt (Open World, nicht passiv, Figur in Reichweite der Station), zieht nach Patience weiter;
	-- den Abschieds-Hinweis gibt es nur, wenn der Spieler gerade dort steht (sonst hat er den Kunden nie gesehen)
	local sale = ss.sale
	if type(sale) == "table" then
		if not inOpenWorld(ms) or passive(d) then
			StoryRules.OfferGone(d, sale)
			ss.sale = false
			changed = true
		elseif t - (sale.at or t) > (S().Sale.Patience or 180) then
			StoryRules.OfferGone(d, sale)
			ss.sale = false
			ss.nextAt = t + (S().Sale.FailInterval or 20)
			StoryRules.ScheduleNext(d, ss.nextAt)
			if nearKiesplatz(ms) then
				toast(ms, string.format(S().Sale.Texts.gone, sale.customer))
			end
			changed = true
		end
	elseif inOpenWorld(ms) and not passive(d) and t >= ss.nextAt and nearKiesplatz(ms) then
		newOffer(ms, d, t)
		changed = true
	end
	-- Bedingungs-Missionen (own/build) und Legende: Fortschritt aus dem Profil, höchstens 1×/s; 3.x: dazu startet die
	-- aktuelle Mission von selbst (z. B. nach einem Levelaufstieg, der das nächste Kapitel öffnet)
	if t - ss.checkAt >= CHECK_INTERVAL then
		ss.checkAt = t
		if autoStart(ms, d, t) then
			changed = true
		end
		local st = StoryRules.Data(d)
		if st and type(st.active) == "table" and not passive(d) then
			local def = StoryRules.Mission(st.active.id)
			if def and not StoryRules.IsCounter(def) then
				local progress = StoryRules.ProgressOf(d, def)
				if ss.seen[def.id] ~= progress then
					local was = ss.seen[def.id]
					ss.seen[def.id] = progress
					if was ~= nil then
						announce(ms, { { id = def.id, title = def.title, progress = progress, target = StoryRules.Target(def), done = progress >= StoryRules.Target(def), side = false, delta = 0 } })
					end
					changed = true
				end
			end
		end
		for _, v in ipairs(StoryRules.SideList(d, t, levelOf(d))) do
			if v.legend and v.claimable and ss.seen[v.id] ~= v.progress then
				ss.seen[v.id] = v.progress
				announce(ms, { { id = v.id, title = v.title, progress = v.progress, target = v.target, done = true, side = true, delta = 0 } })
				changed = true
			end
		end
	end
	local okD, resD = pcall(tickDelivery, ms, d, t)
	if okD then
		if resD then
			changed = true
		end
	else
		warn("[Story] Lieferung: " .. tostring(resD))
	end
	return changed
end

function StoryService.OnLeave(ms: any)
	if ms and ms.player then
		StoryService.Sessions[ms.player] = nil
	end
	if ms then
		ms.story = nil
	end
end

function StoryService.SnapshotFields(ms: any, d: any, t: number?, full: boolean?): { [string]: any }
	t = finite(t) and t or now()
	local ss = ms and session(ms) or nil
	local sale = ss and ss.sale or false
	local saleIn = ss and type(sale) ~= "table" and math.max(0, ss.nextAt - t) or 0
	return {
		story = StoryRules.View(d, t, levelOf(d), { sale = sale, saleIn = saleIn, passive = passive(d) }, full),
	}
end

-- Für Tests/Integrator: aktuelles Kiesplatz-Angebot (mit Wurf) und laufende Lieferung
function StoryService.Offer(ms: any): any
	local ss = ms and ms.story or nil
	return ss and ss.sale or false
end

function StoryService.Delivery(ms: any): any
	local ss = ms and ms.story or nil
	return ss and ss.delivery or false
end

return StoryService
