-- StartService: Startwahl in der Open World (wie im Tycoon) auf dem Server. Zahlen und Texte: GameConfig.Start.
-- Beim ersten Open-World-Beitritt eines NEUEN Profils (meta.startPath = "") wählt der Spieler einen von vier Startwegen
-- – werkstatt, autohaus, produktion, schrottplatz – in StartUI; erst danach beginnt das Tutorial (TutorialRules.Waiting).
-- Veteranen (abgerechnete Aufträge, Tutorial beendet, ein Open-World-Gebäude …) bekommen automatisch "werkstatt" und
-- sehen die Wahl nie (MetaRules.Load / MetaRules.ResolveStartPath).
--
-- Schnittstelle für MiniService:
--   Register(Actions, api)            start_choose {path} (einmalig; MiniNet.Actions: start_choose = { path = "string" })
--   Init(ctx)                         ctx aus MiniService.Init (now)
--   OnJoin(ms, d, now)                Veteranen ohne Weg -> werkstatt; Sitzung zurücksetzen
--   OnMode(ms, d, mode)               Open World betreten und Wahl offen: mini_notice { kind = "start", event = "offer" }
--   SnapshotFields(ms, d, now, full)  { start = { path, pending, choices[] } } (choices nur, solange die Wahl offen ist)
--   Choices()                         die vier Karten (sendbar) – auch für Tests
-- Wirkung von start_choose {path}:
--   meta.startPath = path (MetaRules.SetStartPath, Whitelist, nur einmal); autohaus/produktion/schrottplatz:
--   OWRules.GrantStart schenkt Stufe 1 (sofort fertig, ohne Preis und Level-Sperre); direkt danach OWService.Tick
--   (Settle -> Stufenmodell am Anker, mini_notice ow_ready + Toast), sonst holt es der nächste Tick nach.
--   Danach startet das Tutorial des Wegs (TutorialService.OnStartChosen). Die Story wählt die erste Mission von
--   Kapitel 1 nach dem Weg (StoryRules.MissionAt). Kein Geld, keine XP (das geschenkte Gebäude ist der Bonus).
-- Hinweise: mini_notice { kind = "start", event = "offer", choices } | { kind = "start", event = "chosen", path, name, gift }
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(MiniShared:WaitForChild("GameConfig"))
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))
local OWRules = require(MiniShared:WaitForChild("OWRules"))

local Server = script.Parent
local TutorialService = require(Server:WaitForChild("TutorialService"))
local OWService = require(Server:WaitForChild("OWService"))

local StartService = {}

local api -- MiniService-api: now, toast, notice, dirty, alive, changed, worldChanged, writable
local ctx

local function S(): any
	return GameConfig.Start
end

StartService.Text = S().Texts

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

local function dirty(ms: any)
	if api and ms then
		api.dirty(ms)
	end
end

-- Modus der Sitzung (nil ohne Lobby-Verkabelung = Open World)
local function modeOf(ms: any): string?
	local p = ms and ms.p
	local mode = p and p.mode
	return type(mode) == "string" and mode or nil
end

local function inOpenWorld(ms: any): boolean
	local mode = modeOf(ms)
	return mode == nil or mode == "openworld"
end

---------------------------------------------------------------- Karten
-- Die vier Startwege in fester Reihenfolge (GameConfig.Start.Order), flach und sendbar
function StartService.Choices(): { any }
	local out = {}
	for _, typ in ipairs(S().Order) do
		local p = S().Paths[typ]
		if p then
			table.insert(out, {
				id = typ, name = p.name, short = p.short, desc = p.desc, first = p.first, bonus = p.bonus,
				color = p.color, building = p.building or false, gift = p.building ~= nil,
			})
		end
	end
	return out
end

-- Muss dieser Spieler noch wählen? (ändert nichts)
function StartService.Pending(d: any): boolean
	return MetaRules.StartPending(d)
end

---------------------------------------------------------------- Aktion
local function choose(ms: any, data: any, d: any, t: number?): boolean?
	t = finite(t) and t or now()
	MetaRules.ResolveStartPath(d) -- Veteranen: werkstatt
	if not MetaRules.StartPending(d) then
		toast(ms, S().Texts.already)
		dirty(ms)
		return nil
	end
	if not inOpenWorld(ms) then
		toast(ms, S().Texts.notHere)
		return nil
	end
	local path = type(data) == "table" and data.path or nil
	if not MetaRules.IsStartPath(path) then
		toast(ms, S().Texts.invalid)
		return nil
	end
	local ok = MetaRules.SetStartPath(d, path)
	if not ok then
		toast(ms, S().Texts.already)
		return nil
	end
	local def = S().Paths[path]
	-- Geschenk: Stufe 1 des Gebäudes (sofort fertig); OWService verbucht es gleich (Settle, Modell, ow_ready)
	local granted = OWRules.GrantStart(d, path, t)
	toast(ms, string.format(S().Texts.chosen, def.name))
	if granted then
		local okTick, err = pcall(OWService.Tick, ms, d, t)
		if not okTick then
			warn("[Startwahl] Gebäude aufstellen: " .. tostring(err))
		end
	end
	if api then
		api.notice(ms, "start", { event = "chosen", path = path, name = def.name, gift = granted == true })
	end
	local okT, errT = pcall(TutorialService.OnStartChosen, ms, d)
	if not okT then
		warn("[Startwahl] Tutorial: " .. tostring(errT))
	end
	dirty(ms)
	return true
end
StartService.Choose = choose

function StartService.Register(Actions: any, a: any)
	api = a
	Actions.Register("start_choose", choose)
end

function StartService.Init(c: any)
	ctx = type(c) == "table" and c or nil
end

---------------------------------------------------------------- Sitzung
function StartService.OnJoin(ms: any, d: any, _t: number?)
	if ms then
		ms.startOffered = nil
	end
	MetaRules.ResolveStartPath(d)
end

-- Open World betreten und Wahl offen: Hinweis an StartUI (die Karte öffnet auch aus dem Snapshot-Feld start.pending)
function StartService.OnMode(ms: any, d: any, mode: any): boolean
	if not ms or (mode ~= nil and mode ~= "openworld") then
		return false
	end
	MetaRules.ResolveStartPath(d)
	if not MetaRules.StartPending(d) then
		return false
	end
	dirty(ms)
	if ms.startOffered then
		return false
	end
	ms.startOffered = true
	if api and ms.greeted ~= false then
		api.notice(ms, "start", { event = "offer", choices = StartService.Choices() })
	end
	return true
end

---------------------------------------------------------------- Snapshot
function StartService.SnapshotFields(_ms: any, d: any, _t: number?, _full: boolean?): { [string]: any }
	local pending = MetaRules.StartPending(d)
	return {
		start = {
			path = MetaRules.StartPath(d),
			pending = pending,
			choices = pending and StartService.Choices() or {},
		},
	}
end

return StartService
