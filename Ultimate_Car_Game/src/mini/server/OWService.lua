-- OWService: Open-World-Gebäude, Perks und Passiv-Modus auf dem Server (docs/PHASE4_CONTRACT.md §5, §7, §10–§12).
-- Regeln und Zahlen: OWRules (rein) und GameConfig.OW. Hier nur Modelle am Grundstück, Baustellen-Countdown,
-- Hinweise und Snapshot. Credits ändern sich nur über OWRules (MiniRules.AddMoney/AddIncome).
--
-- Schnittstelle für MiniService:
--   Register(Actions, api)           ow_build {typ}, ow_collect {typ}, ow_passive {on}
--   Init(ctx)                        ctx aus MiniService.Init (now, getSession)
--   OnJoin(ms, d, now)               d.games.ow sicherstellen, fertige Bauten verbuchen (offline), Modelle aufbauen
--   Tick(ms, d, now) -> changed      1×/s: Settle (fertig -> Modell tauschen + mini_notice ow_ready), Countdown der
--                                    Baustelle, Snapshot höchstens 1×/s solange eine Baustelle läuft
--   OnLeave(ms)                      Modelle abbauen (das Grundstück verschwindet ohnehin mit World.Remove)
--   OnCharacter/OnMode               nicht nötig (das Grundstück existiert in jedem Place/Modus)
--   SnapshotFields(ms, d, now, full) { ow = { buildings { [typ] = { stage, built, readyAt, remaining, building, yield,
--                                    effect, next { stage, cost, seconds, level, ok, reason }, perk } }, passive, perks, capHours } }
--   IsPassive(d)                     Passiv-Modus (für den Integrator: Missionen/Story/Auktionen blocken)
--   BlockIfPassive(ms, d, now)       true + gedrosselter deutscher Hinweis, wenn der Spieler im Passiv-Modus ist
-- Welt: Grundstück workspace.PlayerWorkshops.Plot_<UserId> (World.Create); Anker Plot.OWAnchors.<typ> (unsichtbare
-- Parts, Weltteam); Vorlagen ServerStorage.OWBuildings.<typ>_<stufe> und OWBuildings.baustelle (Model, PrimaryPart
-- am Anker-Pivot; die Baustelle trägt eine SurfaceGui mit TextLabel "Countdown" bzw. dem ersten TextLabel).
-- Klone liegen in Plot.OWBuildings (Ordner, vom Dienst angelegt). Fehlen Anker oder Vorlagen, läuft alles ohne
-- Modelle (eine Warnung je Server). Alle Instanz-Arbeit in pcall.
local ServerStorage = game:GetService("ServerStorage")
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local OWRules = require(MiniShared:WaitForChild("OWRules"))
local CarRules = require(MiniShared:WaitForChild("CarRules"))
local CarCatalog = require(MiniShared:WaitForChild("CarCatalog"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))

local OWService = {}

local OW = GameConfig.OW
local COUNTDOWN_INTERVAL = OW.CountdownInterval or 1
local SNAPSHOT_INTERVAL = OW.SnapshotInterval or 1
local TOAST_THROTTLE = OW.ReadyToastSeconds or 2
local PASSIVE_TOAST_SECONDS = 3
local FOLDER_NAME = "OWBuildings"

export type Site = { typ: string, model: Instance?, stage: number, isSite: boolean, labelAt: number }
export type Session = { ms: any, sites: { [string]: Site }, warned: boolean?, snapAt: number, toastAt: { [string]: number } }

OWService.Sessions = setmetatable({}, { __mode = "k" }) :: { [Player]: Session }
OWService.PassiveHint = OW.PassiveHint or "Du bist im Passiv-Modus: nur zuschauen und handeln."

local api -- MiniService-api: now, toast, notice, dirty, alive, changed, writable
local ctx
local warnedMissing = {} :: { [string]: boolean }

local TEXT = {
	unknown = "Dieses Gebäude gibt es nicht.",
	werkstatt = "Die Werkstatt baust du am Hallenanbau auf deinem Grundstück aus (Hebebühnen).",
	max = "%s ist schon auf der höchsten Stufe.",
	building = "%s wird gerade gebaut – fertig in %s.",
	level = "%s Stufe %d gibt es ab Level %d.",
	credits = "Nicht genug Credits: %s Stufe %d kostet %s.",
	built = "Baustelle eröffnet: %s Stufe %d ist in %s fertig.",
	ready = "%s Stufe %d ist fertig!",
	readyFirst = "%s ist fertig gebaut! Erträge holst du im Tab „Gebäude“ ab.",
	nothing = "Bei %s gibt es gerade nichts abzuholen.",
	notBuilt = "Du hast noch kein %s. Bau eins im Tab „Gebäude“.",
	collected = "%s: %s abgeholt.",
	garageFull = "Der Auto-Gutschein wartet: deine Garage ist voll (%d Autos).",
	passiveOn = "Passiv-Modus an: nur zuschauen und handeln. Deine Gebäude verdienen weiter.",
	passiveOff = "Passiv-Modus aus: Missionen, Story und Auktionen sind wieder offen.",
	passiveSame = "Der Passiv-Modus ist schon %s.",
	notWritable = "Dein Profil wird gerade nicht gespeichert – bauen ist jetzt nicht möglich.",
	countdown = "BAUSTELLE\n%s · Stufe %d\nFertig in %s",
}
OWService.Text = TEXT

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

local function writable(ms: any): boolean
	if api and type(api.writable) == "function" then
		return api.writable(ms) == true
	end
	return ms and ms.p and ms.p.profile and ms.p.profile.writable == true
end

local function duration(seconds: any): string
	local ok, text = pcall(MiniLocale.Duration, math.max(0, math.floor(finite(seconds) and seconds or 0)))
	if ok and type(text) == "string" then
		return text
	end
	return tostring(math.floor(finite(seconds) and seconds or 0)) .. " s"
end

local function credits(n: any): string
	local ok, text = pcall(MiniLocale.Credits, finite(n) and n or 0)
	if ok and type(text) == "string" then
		return text
	end
	return tostring(n) .. " Cr"
end

local function scrapText(n: any): string
	local ok, text = pcall(MiniLocale.Scrap, finite(n) and n or 0)
	if ok and type(text) == "string" then
		return text
	end
	return tostring(n) .. " Schrott"
end

local function warnOnce(key: string, msg: string)
	if not warnedMissing[key] then
		warnedMissing[key] = true
		warn("[Gebäude] " .. msg)
	end
end

local function sessionOf(ms: any): Session?
	if not ms or not ms.player then
		return nil
	end
	local s = OWService.Sessions[ms.player]
	if not s or s.ms ~= ms then
		s = { ms = ms, sites = {}, snapAt = -math.huge, toastAt = {} }
		OWService.Sessions[ms.player] = s
	end
	return s
end

local function throttled(s: Session?, key: string, t: number): boolean
	if not s then
		return false
	end
	local last = s.toastAt[key]
	if last and t - last < TOAST_THROTTLE then
		return true
	end
	s.toastAt[key] = t
	return false
end

---------------------------------------------------------------- Welt: Grundstück, Anker, Vorlagen
local function plotOf(ms: any): Instance?
	local folder = workspace:FindFirstChild("PlayerWorkshops")
	local plot = folder and ms and ms.player and folder:FindFirstChild("Plot_" .. tostring(ms.player.UserId)) or nil
	return plot
end

local function anchorCFrame(plot: Instance?, typ: string): CFrame?
	local anchors = plot and plot:FindFirstChild("OWAnchors")
	local a = anchors and anchors:FindFirstChild(typ)
	if a and a:IsA("BasePart") then
		return a.CFrame
	elseif a and a:IsA("Model") then
		return a:GetPivot()
	end
	return nil
end

local function template(name: string): Instance?
	local root = ServerStorage:FindFirstChild(FOLDER_NAME)
	return root and root:FindFirstChild(name) or nil
end

local function folderOf(plot: Instance): Instance
	local f = plot:FindFirstChild(FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = FOLDER_NAME
		f.Parent = plot
	end
	return f
end

local function removeModel(site: Site?)
	if site and site.model then
		pcall(function()
			site.model:Destroy()
		end)
		site.model = nil
	end
end

-- Countdown-Text in die SurfaceGui der Baustelle (TextLabel "Countdown", sonst das erste TextLabel)
local function setCountdown(model: Instance?, text: string)
	if not model then
		return
	end
	local first = nil
	for _, x in ipairs(model:GetDescendants()) do
		if x:IsA("TextLabel") then
			if x.Name == "Countdown" then
				x.Text = text
				return
			end
			first = first or x
		end
	end
	if first then
		first.Text = text
	end
end

-- Modell (Stufe oder Baustelle) am Anker aufbauen; tolerant gegenüber fehlenden Ankern/Vorlagen
local function place(s: Session, typ: string, stage: number, isSite: boolean)
	local site = s.sites[typ]
	if site and site.model and site.model.Parent and site.stage == stage and site.isSite == isSite then
		return
	end
	if not site then
		site = { typ = typ, model = nil, stage = 0, isSite = false, labelAt = -math.huge }
		s.sites[typ] = site
	end
	removeModel(site)
	site.stage = stage
	site.isSite = isSite
	local ok, err = pcall(function()
		local plot = plotOf(s.ms)
		if not plot then
			return
		end
		local pivot = anchorCFrame(plot, typ)
		if not pivot then
			warnOnce("anchor:" .. typ, "Anker fehlt: Plot.OWAnchors." .. typ .. " (Modelle werden nicht gezeigt)")
			return
		end
		local name = isSite and "baustelle" or (typ .. "_" .. tostring(stage))
		local tpl = template(name)
		if not tpl then
			warnOnce("template:" .. name, "Vorlage fehlt: ServerStorage." .. FOLDER_NAME .. "." .. name)
			return
		end
		local clone = tpl:Clone()
		clone.Name = name
		clone:SetAttribute("OWType", typ)
		clone:SetAttribute("OWStage", stage)
		clone:SetAttribute("OWSite", isSite)
		clone:PivotTo(pivot)
		clone.Parent = folderOf(plot)
		site.model = clone
	end)
	if not ok then
		warn("[Gebäude] Aufbau " .. typ .. ": " .. tostring(err))
	end
end

-- Alle Gebäude eines Spielers nach dem Profil aufbauen (Stufe fertig -> Stufenmodell; Bau läuft -> Baustelle)
local function rebuild(s: Session, d: any, t: number)
	for _, typ in ipairs(OW.Types) do
		if typ ~= "werkstatt" then
			local e = OWRules.Entry(d, typ)
			if e and e.stage > e.built then
				place(s, typ, e.stage, true)
			elseif e and e.built > 0 then
				place(s, typ, e.built, false)
			else
				removeModel(s.sites[typ])
			end
		end
	end
end

local function updateCountdowns(s: Session, d: any, t: number)
	for typ, site in pairs(s.sites) do
		if site.isSite and site.model and t - site.labelAt >= COUNTDOWN_INTERVAL then
			site.labelAt = t
			local remaining = OWRules.Remaining(d, typ, t)
			pcall(setCountdown, site.model, string.format(TEXT.countdown, OWRules.Name(typ), site.stage, duration(remaining)))
		end
	end
end

local function clearAll(s: Session)
	for _, site in pairs(s.sites) do
		removeModel(site)
	end
	s.sites = {}
end

---------------------------------------------------------------- Fertige Bauten
local function settle(ms: any, s: Session?, d: any, t: number): boolean
	local done = OWRules.Settle(d, t)
	if #done == 0 then
		return false
	end
	for _, typ in ipairs(done) do
		local e = OWRules.Entry(d, typ)
		local stage = e and e.built or 0
		if s then
			place(s, typ, stage, false)
		end
		notice(ms, "ow_ready", { typ = typ, stage = stage, name = OWRules.Name(typ) })
		toast(ms, stage == 1 and string.format(TEXT.readyFirst, OWRules.Name(typ)) or string.format(TEXT.ready, OWRules.Name(typ), stage))
	end
	dirty(ms)
	return true
end

-- Beträge als Aufzählung („1.500 Cr, 12 Altteile, Auto-Gutschein eingelöst: …“)
local function amountsText(a: any, car: any): string
	local parts = {}
	if a.credits > 0 then
		table.insert(parts, credits(a.credits))
	end
	if a.scrap > 0 then
		table.insert(parts, scrapText(a.scrap))
	end
	if a.parts > 0 then
		table.insert(parts, tostring(a.parts) .. " Altteile")
	end
	if car then
		table.insert(parts, "Auto-Gutschein eingelöst: " .. tostring(car.name or a.car))
	end
	return table.concat(parts, ", ")
end

---------------------------------------------------------------- Passiv-Modus
function OWService.IsPassive(d: any): boolean
	return OWRules.IsPassive(d)
end

-- true, wenn geblockt (Hinweis höchstens alle PASSIVE_TOAST_SECONDS je Sitzung)
function OWService.BlockIfPassive(ms: any, d: any, t: number?): boolean
	if not OWRules.IsPassive(d) then
		return false
	end
	t = finite(t) and t or now()
	if ms then
		local last = ms.owPassiveToastAt
		if not last or t - last >= PASSIVE_TOAST_SECONDS then
			ms.owPassiveToastAt = t
			toast(ms, OWService.PassiveHint)
		end
	end
	return true
end

---------------------------------------------------------------- Aktionen
local function build(ms: any, data: any, d: any, t: number)
	local typ = data.typ
	local s = sessionOf(ms)
	OWRules.Ensure(d)
	settle(ms, s, d, t)
	if not OWRules.IsType(typ) then
		toast(ms, TEXT.unknown)
		return
	end
	if not writable(ms) then
		toast(ms, TEXT.notWritable)
		return
	end
	local name = OWRules.Name(typ)
	local ok, reason, cost = OWRules.CanBuild(d, typ, t)
	if not ok then
		if throttled(s, "build:" .. tostring(typ) .. ":" .. reason, t) then
			return
		end
		local e = OWRules.Entry(d, typ)
		local nextStage = (e and e.stage or 0) + 1
		if reason == "werkstatt" then
			toast(ms, TEXT.werkstatt)
		elseif reason == "max" then
			toast(ms, string.format(TEXT.max, name))
		elseif reason == "building" then
			toast(ms, string.format(TEXT.building, name, duration(OWRules.Remaining(d, typ, t))))
		elseif reason == "level" then
			toast(ms, string.format(TEXT.level, name, nextStage, OWRules.NextLevel(d, typ)))
		elseif reason == "credits" then
			toast(ms, string.format(TEXT.credits, name, nextStage, credits(cost)))
		else
			toast(ms, TEXT.unknown)
		end
		return
	end
	local built, _, paid, pre = OWRules.Build(d, typ, t)
	if not built then
		toast(ms, TEXT.unknown)
		return
	end
	local e = OWRules.Entry(d, typ)
	if s then
		place(s, typ, e.stage, true)
		updateCountdowns(s, d, t)
	end
	if pre then
		toast(ms, string.format(TEXT.collected, name, amountsText(pre, nil)))
	end
	toast(ms, string.format(TEXT.built, name, e.stage, duration(OWRules.Remaining(d, typ, t))))
	notice(ms, "ow_build", { typ = typ, stage = e.stage, cost = paid, readyAt = e.readyAt })
	dirty(ms)
end

-- Abholen: Credits (Prestige-Bonus), Schrott, Altteile; Auto-Gutschein -> CarRules.GrantModel (nur mit Platz)
function OWService.Collect(ms: any, d: any, typ: any, t: number?): any
	t = finite(t) and t or now()
	local s = sessionOf(ms)
	OWRules.Ensure(d)
	settle(ms, s, d, t)
	if not OWRules.IsType(typ) or typ == "werkstatt" then
		toast(ms, TEXT.unknown)
		return nil
	end
	local name = OWRules.Name(typ)
	if OWRules.Built(d, typ) <= 0 then
		if not throttled(s, "collect:" .. typ .. ":none", t) then
			toast(ms, string.format(TEXT.notBuilt, name))
		end
		return nil
	end
	local a = OWRules.Collectable(d, typ, t)
	-- Auto-Gutschein nur einlösen, wenn die Garage Platz hat (sonst bleibt er stehen; der Rest wird abgeholt)
	local car = nil
	local skipCar = false
	if a and a.car then
		local g = d.games
		if type(g) == "table" and type(g.cars) == "table" and #g.cars >= CarCatalog.MaxCars then
			skipCar = true
			if not throttled(s, "collect:" .. typ .. ":full", t) then
				toast(ms, string.format(TEXT.garageFull, CarCatalog.MaxCars))
			end
		end
	end
	a = OWRules.Collect(d, typ, t, { skipCar = skipCar })
	if a and a.car then
		local granted = CarRules.GrantModel(d, a.car, t)
		if granted then
			car = granted
		else
			-- sollte nach der Platzprüfung nicht vorkommen; Gutschein nicht verfallen lassen
			local e = OWRules.Entry(d, typ)
			e.carAt = 0
			a.car = nil
		end
	end
	if not a then
		if not throttled(s, "collect:" .. typ .. ":nothing", t) then
			toast(ms, string.format(TEXT.nothing, name))
		end
		return nil
	end
	if car and api and type(api.worldChanged) == "function" then
		api.worldChanged(ms) -- Garage geändert (2.4.0-Revision)
	end
	toast(ms, string.format(TEXT.collected, name, amountsText(a, car)))
	notice(ms, "ow_collect", { typ = typ, credits = a.credits, scrap = a.scrap, parts = a.parts, car = car and car.model or false })
	dirty(ms)
	return a
end

local function collect(ms: any, data: any, d: any, t: number)
	OWService.Collect(ms, d, data.typ, t)
end

local function passive(ms: any, data: any, d: any, t: number)
	OWRules.Ensure(d)
	local before = OWRules.IsPassive(d)
	local changed = OWRules.PassiveSet(d, data.on, t)
	if not changed then
		toast(ms, string.format(TEXT.passiveSame, before and "an" or "aus"))
		return
	end
	toast(ms, data.on and TEXT.passiveOn or TEXT.passiveOff)
	notice(ms, "ow_passive", { on = data.on == true })
	dirty(ms)
end

function OWService.Register(Actions: any, a: any)
	api = a
	Actions.Register("ow_build", build)
	Actions.Register("ow_collect", collect)
	Actions.Register("ow_passive", passive)
end

function OWService.Init(c: any)
	ctx = type(c) == "table" and c or nil
end

---------------------------------------------------------------- Sitzung
function OWService.OnJoin(ms: any, d: any, t: number?)
	t = finite(t) and t or now()
	local s = sessionOf(ms)
	OWRules.Ensure(d)
	-- Offline fertig gewordene Bauten: Modell direkt als Stufe, Hinweis beim ersten Snapshot
	settle(ms, s, d, t)
	if s then
		rebuild(s, d, t)
		updateCountdowns(s, d, t)
	end
end

-- Rückgabe: true, wenn der Snapshot gesendet werden soll
function OWService.Tick(ms: any, d: any, t: number?): boolean
	t = finite(t) and t or now()
	local s = sessionOf(ms)
	if not s then
		return false
	end
	local o = OWRules.Data(d)
	if not o then
		return false
	end
	local changed = settle(ms, s, d, t)
	local building = false
	for _, typ in ipairs(OW.Types) do
		local e = o.buildings[typ]
		if type(e) == "table" and e.stage > e.built then
			building = true
			local site = s.sites[typ]
			if not site or not site.model or not site.model.Parent then
				place(s, typ, e.stage, true) -- Grundstück kam nach OnJoin (World.Create) oder Modell ging verloren
			end
		end
	end
	if building then
		updateCountdowns(s, d, t)
		if t - s.snapAt >= SNAPSHOT_INTERVAL then
			s.snapAt = t
			changed = true
		end
	end
	return changed
end

function OWService.OnLeave(ms: any)
	local s = ms and ms.player and OWService.Sessions[ms.player] or nil
	if s then
		clearAll(s)
		OWService.Sessions[ms.player] = nil
	end
end

function OWService.OnMode(_ms: any, _d: any, _mode: any)
	-- Gebäude stehen auf dem Grundstück, das in jedem Place/Modus existiert: nichts zu tun
end

function OWService.SnapshotFields(ms: any, d: any, t: number?, _full: boolean?): { [string]: any }
	t = finite(t) and t or now()
	OWRules.Ensure(d)
	return { ow = OWRules.Summary(d, t) }
end

-- Für Tests/Integrator: Modell eines Gebäudes des Spielers (nil ohne Modell)
function OWService.ModelOf(player: Player, typ: string): Instance?
	local s = OWService.Sessions[player]
	local site = s and s.sites[typ] or nil
	return site and site.model or nil
end

return OWService
