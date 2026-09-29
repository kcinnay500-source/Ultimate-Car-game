-- TutorialService: Tutorial und Beginner-Hinweise auf dem Server (docs/PHASE4_CONTRACT.md §6).
-- Der Server bestätigt den Fortschritt aus echten Ereignissen; der Client sendet nur tutorial_next {step}
-- für reine Lese-Schritte („Weiter“) und tutorial_skip. Belohnung (GameConfig.Tutorial.Reward) einmalig am Ende.
--
-- Schnittstelle für MiniService:
--   Register(Actions, api)              tutorial_next {step}, tutorial_skip
--   OnJoin(ms, d, now)                  Sitzung vorbereiten (Hinweis mit dem aktuellen Schritt nach 'hello')
--   OnEvent(ms, d, event) -> advanced   Ereignis melden: "station:<key>" (Plot-Station, GarageServer act/World-Callback),
--                                       "tab:<tab>" (Stadt-Station, MiniService.openStation), "settled" (Mini.OnSettled),
--                                       "action:<name>" (Mini.Handle nach erfolgreichem Handler), "accept"/"scan"/"menu"
--                                       (Kurzformen: accept = job:accepted, scan = job:repair, menu = next-Schritt "menu").
--                                       Bei "station:<key>"/"tab:<tab>" laufen zusätzlich die Beginner-Hinweise "station:<key>".
--   OnStation(ms, d, key, tab)          Kurzform: Plot-Station (tab = nil) oder Stadt-Station (tab = MiniTab)
--   OnStat(ms, d, stat)                 Statistik gestiegen: Beginner-Hinweis "first:<stat>" (einmal, nur Beginner)
--   Hint(ms, d, trigger) -> n           Beginner-Hinweise zu einem Auslöser senden (mini_notice { kind = "hint" })
--   Tick(ms, d, now) -> changed         job:-Schritte aus d.jobs erkennen, zurückgehaltene Belohnung nachholen
--   Start(ms, d, mode) -> started       Pflicht-Start beim ersten Open-World-Beitritt (TutorialRules.ShouldStart)
--   ShouldStart(d, mode)                s. TutorialRules
--   OnLeave(ms, d)                      zurückgehaltene Belohnung noch vor P.Save verbuchen
--   Flush(ms)                           eingereihte Hinweise senden (sobald ms.greeted)
--   SnapshotFields(ms, d, now, full)    { tutorial = { step, count, text, target, zone, next, done, skipped, active } }
-- Hinweise: mini_notice { kind = "tutorial", step, count, text, target, zone, next, done, skipped, finished?, started? }
--           mini_notice { kind = "hint", id, text, trigger }
-- Geld: nur die einmalige Belohnung (MiniRules.AddMoney + MiniRules.GainXP); fällt sie außerhalb von request()
-- an (Stationsbesuch), meldet api.changed die 2.4.0-Revision. Während transacting wird sie zurückgehalten
-- (ms.tutorialRewardPending) und im Tick bzw. in OnLeave nachgeholt.
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))
local MetaRules = require(MiniShared:WaitForChild("MetaRules"))
local TutorialRules = require(MiniShared:WaitForChild("TutorialRules"))

local TutorialService = {}

local api -- MiniService-api: now, toast, notice, dirty, changed, alive

local TEXT = {
	finished = "Tutorial geschafft! +%s und +%d XP – viel Spaß in der Werkstattmeile!",
	skipped = TutorialRules.Text.skipped,
	started = "Willkommen! Das Tutorial zeigt dir die Werkstatt. Du kannst es jederzeit überspringen.",
}
TutorialService.Text = TEXT

-- Kurzformen der Ereignisse (Aufrufer des Integrators)
local ALIAS = {
	accept = "job:accepted",
	scan = "job:repair",
	repair = "job:invoice",
	settle = "settled",
	menu = "next",
	move = "next",
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

local function transacting(ms: any): boolean
	local p = ms and ms.p
	local prof = p and p.profile
	return prof ~= nil and prof.transacting == true
end

---------------------------------------------------------------- Hinweise (Warteschlange, bis der Client zuhört)
local function send(ms: any, kind: string, data: { [string]: any })
	if not api then
		return
	end
	if ms.greeted == false then
		ms.tutorialNotices = ms.tutorialNotices or {}
		table.insert(ms.tutorialNotices, { kind = kind, data = data })
		return
	end
	api.notice(ms, kind, data)
end

function TutorialService.Flush(ms: any)
	local list = ms and ms.tutorialNotices
	if not api or type(list) ~= "table" or #list == 0 or ms.greeted == false then
		return
	end
	ms.tutorialNotices = {}
	for _, n in ipairs(list) do
		api.notice(ms, n.kind, n.data)
	end
end

local function stepNotice(ms: any, d: any, extra: { [string]: any }?)
	local v = TutorialRules.View(d)
	local data = {
		step = v.step, count = v.count, id = v.id, text = v.text, target = v.target, zone = v.zone,
		next = v.next, done = v.done, skipped = v.skipped, active = v.active,
	}
	for k, x in pairs(extra or {}) do
		data[k] = x
	end
	send(ms, "tutorial", data)
	if api then
		api.dirty(ms)
	end
end

---------------------------------------------------------------- Belohnung (einmalig, nie beim Überspringen)
local function grantReward(ms: any, d: any): boolean
	if transacting(ms) then
		ms.tutorialRewardPending = true
		return false
	end
	ms.tutorialRewardPending = nil
	local r = TutorialRules.Reward()
	local credits = MiniRules.AddMoney(d, r.credits)
	MiniRules.GainXP(d, r.xp)
	if api then
		api.toast(ms, string.format(TEXT.finished, MiniLocale.Credits(credits), r.xp))
		if type(api.changed) == "function" then
			api.changed(ms) -- Geld/XP evtl. außerhalb von request() (Stationsbesuch): 2.4.0-Revision + Snapshot
		else
			api.dirty(ms)
		end
	end
	return true
end

local function afterAdvance(ms: any, d: any, finished: boolean)
	if finished then
		grantReward(ms, d)
		stepNotice(ms, d, { finished = true })
	else
		stepNotice(ms, d)
	end
end

---------------------------------------------------------------- Beginner-Hinweise
-- Sendet alle noch nicht gezeigten Hinweise zum Auslöser; Rückgabe: Anzahl
function TutorialService.Hint(ms: any, d: any, trigger: any): number
	local hints = TutorialRules.HintsFor(d, trigger)
	for _, h in ipairs(hints) do
		send(ms, "hint", { id = h.id, text = h.text, trigger = trigger })
	end
	if #hints > 0 and api then
		api.dirty(ms)
	end
	return #hints
end

-- Statistik gestiegen (MiniRules.AddStat): Hinweis "first:<stat>", sobald sie > 0 ist
function TutorialService.OnStat(ms: any, d: any, stat: any): number
	local g = type(d) == "table" and d.games or nil
	local stats = type(g) == "table" and g.stats or nil
	local v = type(stats) == "table" and stats[stat] or nil
	if type(stat) ~= "string" or not finite(v) or v <= 0 then
		return 0
	end
	return TutorialService.Hint(ms, d, "first:" .. stat)
end

---------------------------------------------------------------- Ereignisse
-- Rückgabe: true, wenn ein Tutorial-Schritt erledigt wurde
function TutorialService.OnEvent(ms: any, d: any, event: any): boolean
	if type(event) ~= "string" or not ms or type(d) ~= "table" then
		return false
	end
	event = ALIAS[event] or event
	if string.sub(event, 1, 8) == "station:" then
		TutorialService.Hint(ms, d, event)
	end
	if not TutorialRules.Active(d) then
		return false
	end
	local advanced, finished = TutorialRules.Advance(d, event)
	if not advanced then
		return false
	end
	afterAdvance(ms, d, finished)
	return true
end

-- Station geöffnet: Plot-Station (tab = nil -> "station:<key>") oder Stadt-Station (tab = MiniTab -> "tab:<tab>",
-- dazu der Beginner-Hinweis "station:<key>")
function TutorialService.OnStation(ms: any, d: any, key: any, tab: any): boolean
	if type(key) ~= "string" then
		return false
	end
	if type(tab) == "string" then
		TutorialService.Hint(ms, d, "station:" .. key)
		return TutorialService.OnEvent(ms, d, "tab:" .. tab)
	end
	return TutorialService.OnEvent(ms, d, "station:" .. key)
end

---------------------------------------------------------------- Aktionen
local function next_(ms: any, data: any, d: any)
	local ok, res = TutorialRules.Next(d, data.step)
	if ok then
		afterAdvance(ms, d, res == true)
	elseif type(res) == "string" then
		api.toast(ms, res)
	end
end

local function skip(ms: any, _: any, d: any)
	if not TutorialRules.Skip(d) then
		return -- schon beendet: still (Doppeltipp)
	end
	ms.tutorialRewardPending = nil
	api.toast(ms, TEXT.skipped)
	stepNotice(ms, d, { skipped = true })
end

function TutorialService.Register(Actions: any, a: any)
	api = a
	Actions.Register("tutorial_next", next_)
	Actions.Register("tutorial_skip", skip)
end

---------------------------------------------------------------- Sitzung
function TutorialService.ShouldStart(d: any, mode: any): boolean
	return TutorialRules.ShouldStart(d, mode)
end

-- Pflicht-Start beim ersten Open-World-Beitritt: Hinweis mit dem aktuellen Schritt (started = true)
function TutorialService.Start(ms: any, d: any, mode: any): boolean
	if not TutorialRules.ShouldStart(d, mode) then
		return false
	end
	if ms.tutorialStarted then
		return false
	end
	ms.tutorialStarted = true
	stepNotice(ms, d, { started = true })
	if api then
		api.toast(ms, TEXT.started)
	end
	return true
end

function TutorialService.OnJoin(ms: any, d: any, now: number?)
	ms.tutorialNotices = {}
	ms.tutorialRewardPending = nil
	ms.tutorialStarted = nil
	if TutorialRules.Active(d) then
		stepNotice(ms, d) -- wartet in der Warteschlange, bis der Client nach 'hello' zuhört
	end
end

-- job:-Schritte erkennen (Auftrag angenommen, Diagnose fertig, Endkontrolle bestanden) und die
-- zurückgehaltene Belohnung nachholen. Rückgabe: true, wenn sich etwas geändert hat (Snapshot senden).
function TutorialService.Tick(ms: any, d: any, now: number?): boolean
	local changed = false
	if ms.tutorialRewardPending and not transacting(ms) then
		changed = grantReward(ms, d) or changed
	end
	TutorialService.Flush(ms)
	if not TutorialRules.Active(d) then
		return changed
	end
	local event = TutorialRules.PendingJobEvent(d)
	if event and TutorialService.OnEvent(ms, d, event) then
		changed = true
	end
	return changed
end

-- Vor P.Save: eine zurückgehaltene Belohnung noch verbuchen (nicht während eines laufenden Robux-Kaufs)
function TutorialService.OnLeave(ms: any, d: any)
	if ms and ms.tutorialRewardPending and not transacting(ms) then
		local r = TutorialRules.Reward()
		ms.tutorialRewardPending = nil
		MiniRules.AddMoney(d, r.credits)
		MiniRules.GainXP(d, r.xp)
	end
end

---------------------------------------------------------------- Snapshot (§11)
function TutorialService.SnapshotFields(ms: any, d: any, now: number?, full: boolean?): { [string]: any }
	local v = TutorialRules.View(d)
	return {
		tutorial = {
			step = v.step, count = v.count, id = v.id, text = v.text, target = v.target, zone = v.zone,
			next = v.next, done = v.done, skipped = v.skipped, active = v.active,
			rewardPending = ms ~= nil and ms.tutorialRewardPending == true,
		},
	}
end

return TutorialService
