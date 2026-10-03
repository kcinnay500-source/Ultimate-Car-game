-- TrackUI: Tab "track" (Teststrecke). Bestzeit, belohnte Bestzeit, Start des Zeitfahrens (mini_track_start),
-- laufende Zeit und Checkpoints (Zustand aus DriveClient, gespeist von mini_notice track_* und Snapshot track).
-- Die Zeit misst allein der Server (Checkpoints über Berührung + Serverzeit); Credits gibt es nur für eine
-- neue Bestzeit, gedeckelt. Der Client sendet nur die Absicht zu starten.
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local Lib = require(script.Parent:WaitForChild("DealerUI")).Lib
local DriveClient = require(script.Parent:WaitForChild("DriveClient"))
local okRules, TrackRules = pcall(require, Mini:WaitForChild("TrackRules"))
if not okRules then
	TrackRules = nil
end

local TrackUI = {}

local UI, Remote, T
local ctxRef
local refs = {}
local state
local startSentAt = -math.huge
local START_GAP = 3 -- Sekunden: nach dem Senden kurz sperren, bis der Server antwortet
local shownRunning = nil

local function num(v)
	return Lib.Num(v)
end

function TrackUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	ctxRef = ctx
	T = UI.Theme
	refs = {}

	local head = UI.Card(page, 1)
	UI.Title(head, "Teststrecke · Zeitfahren", 1)
	UI.Small(head, "Fahre mit deinem eigenen Auto alle Checkpoints der Strecke in der richtigen Reihenfolge ab. Die Zeit misst der Server. Credits gibt es nur, wenn du deine belohnte Bestzeit verbesserst.", 2)
	refs.best = UI.Label(head, "", { Font = UI.FontBold, TextSize = 17, LayoutOrder = 3 })
	refs.info = UI.Small(head, "", 4)
	refs.layout = UI.Small(head, TrackUI.LayoutText(), 5)
	refs.layout.Name = "Streckenfuehrung"

	local run = UI.Card(page, 2)
	UI.Title(run, "Zeitfahren", 1)
	refs.running = UI.Label(run, "", { Name = "Laufzeit", Font = UI.FontBig, TextSize = 28, TextColor3 = T.yellow, LayoutOrder = 2, Visible = false })
	refs.checkpoint = UI.Small(run, "", 3)
	local _, fill = UI.Progress(run, T.yellow, 4)
	refs.fill = fill
	refs.result = UI.Label(run, "", { TextSize = 15, LayoutOrder = 5, Visible = false })
	refs.hint = UI.Small(run, "", 6)
	refs.start = UI.Button(run, "Zeitfahren starten", T.green, function()
		startSentAt = os.clock()
		Remote.Send("mini_track_start")
		TrackUI.Step()
	end, { Name = "Starten", LayoutOrder = 7 })
	refs.travel = UI.Button(run, "Zur Teststrecke reisen", T.blue, function()
		Remote.Send("mini_travel", { key = "track" })
	end, { Name = "Reisen", LayoutOrder = 8 })
	refs.toDealer = UI.Button(run, "Zum Autohaus", T.card, function()
		if UI.Pages and UI.Pages.dealer then
			UI.Show("dealer")
		else
			Remote.Send("mini_travel", { key = "dealer" })
		end
	end, { Name = "ZumAutohaus", LayoutOrder = 9, Visible = false })
end

-- Streckenführung (TrackRules.Layout): Name, Abschnitte, Länge und Checkpoints als eine Zeile
function TrackUI.LayoutText()
	local L = TrackRules and type(TrackRules.Layout) == "table" and TrackRules.Layout or nil
	if not L then
		return ""
	end
	local parts = {}
	if type(L.sections) == "table" and #L.sections > 0 then
		table.insert(parts, table.concat(L.sections, " · "))
	end
	if type(L.length) == "number" then
		table.insert(parts, "ca. " .. MiniLocale.Group(math.floor(L.length / 10 + 0.5) * 10) .. " Studs")
	end
	if type(L.checkpoints) == "number" then
		table.insert(parts, L.checkpoints .. " Checkpoints + Ziel")
	end
	return "Strecke: " .. tostring(L.name or "Teststrecke") .. (#parts > 0 and (" – " .. table.concat(parts, " · ")) or "")
end

-- mini_notice track_*: Zustand in DriveClient (einmal je Hinweis), Ergebnis hier anzeigen
function TrackUI.OnNotice(data)
	if type(data) ~= "table" then
		return
	end
	DriveClient.OnNotice(data)
	if not refs.result then
		return
	end
	if data.kind == "track_finish" then
		local reward = num(data.reward) or 0
		local text = "Ziel in " .. Lib.LapTime(num(data.time)) .. "."
		if data.newBest then
			text ..= " Neue Bestzeit!"
		end
		if reward > 0 then
			text ..= " Belohnung: " .. MiniLocale.Credits(reward) .. "."
		end
		refs.result.Text = text
		refs.result.TextColor3 = data.newBest and T.green or T.text
		refs.result.Visible = true
		startSentAt = -math.huge
	elseif data.kind == "track_start" then
		refs.result.Visible = false
		startSentAt = -math.huge
		-- Panel schließen: der Countdown läuft, und auf dem Handy braucht der Spieler den Stick
		if UI.IsOpen and ctxRef and ctxRef.Close then
			ctxRef.Close()
		end
	elseif data.kind == "track_cancel" or data.kind == "track_abort" or data.kind == "track_invalid" or data.kind == "track_fail" then
		refs.result.Text = type(data.text) == "string" and data.text or ("Lauf ungültig: " .. DriveClient.ReasonText(data.reason) .. ".")
		refs.result.TextColor3 = T.red
		refs.result.Visible = true
		startSentAt = -math.huge
	end
end

function TrackUI.Step()
	if not refs.start then
		return
	end
	local tr = DriveClient.Track()
	local running = tr.active
	if running and tr.countdown > 0 then
		refs.running.Text = "Start in " .. math.ceil(tr.countdown - 1e-6)
		refs.checkpoint.Text = "Gleich geht's los: warte auf die Startampel."
		UI.SetProgress(refs.fill, 0)
	elseif running then
		refs.running.Text = Lib.LapTime(tr.elapsed)
		refs.checkpoint.Text = tr.total > 0 and ("Checkpoint " .. tr.index .. " von " .. tr.total) or "Unterwegs …"
		UI.SetProgress(refs.fill, tr.total > 0 and tr.index / tr.total or 0)
	end
	if running ~= shownRunning then
		shownRunning = running
		refs.running.Visible = running
		if not running then
			refs.checkpoint.Text = "Starte das Zeitfahren und fahre durch das Starttor."
			UI.SetProgress(refs.fill, 0)
		end
	end
	local hasCar = TrackUI.CanStart(state)
	local waiting = os.clock() - startSentAt < START_GAP
	if running then
		refs.start.Text = "Läuft …"
	elseif waiting then
		refs.start.Text = "Wird gestartet …"
	else
		refs.start.Text = "Zeitfahren starten"
	end
	UI.SetEnabled(refs.start, hasCar and not running and not waiting, T.green)
end

-- Start möglich: ein Auto ist draußen oder ein aktives, nicht gesperrtes Auto existiert (CarService nimmt dieses)
function TrackUI.CanStart(s)
	if type(s) ~= "table" then
		return false
	end
	local id = num(s.spawnedId)
	if not id or id <= 0 then
		id = Lib.ActiveId(s)
	end
	local car = Lib.FindCar(s, id)
	return car ~= nil and not car.locked
end

function TrackUI.Render(s)
	if type(s) ~= "table" or not refs.best then
		return
	end
	state = s
	DriveClient.OnSnapshot(s)
	local tr = type(s.track) == "table" and s.track or {}
	local best, rewarded = num(tr.best) or 0, num(tr.rewardedBest) or 0
	refs.best.Text = best > 0 and ("Bestzeit: " .. Lib.LapTime(best)) or "Noch keine Bestzeit"
	local parts = {}
	if rewarded > 0 then
		table.insert(parts, "Belohnte Bestzeit: " .. Lib.LapTime(rewarded))
	end
	if num(tr.runs) then
		table.insert(parts, "Läufe: " .. MiniLocale.Group(num(tr.runs)))
	end
	local reward = num(tr.reward) or num(tr.nextReward)
	if reward and reward > 0 then
		table.insert(parts, "Belohnung für eine neue Bestzeit: bis zu " .. MiniLocale.Credits(reward))
	end
	local text = #parts > 0 and table.concat(parts, " · ") or "Deine erste gültige Runde setzt die Bestzeit."
	local cat = Lib.CarCatalogModule()
	local rules = cat and type(cat.Track) == "table" and cat.Track or nil
	if rules and num(rules.firstReward) and num(rules.perSecond) and num(rules.maxReward) then
		text ..= string.format(
			"\nErste gültige Runde: %s. Danach %s je Sekunde Verbesserung der belohnten Bestzeit, höchstens %s je Lauf.",
			MiniLocale.Credits(num(rules.firstReward)), MiniLocale.Credits(num(rules.perSecond)), MiniLocale.Credits(num(rules.maxReward))
		)
	end
	refs.info.Text = text
	local hasCar = #Lib.Cars(s) > 0
	local canStart = TrackUI.CanStart(s)
	if canStart then
		local car = Lib.FindCar(s, num(s.spawnedId) and num(s.spawnedId) > 0 and num(s.spawnedId) or Lib.ActiveId(s))
		refs.hint.Text = Lib.CarName(s, car) .. " wird an den Start gebracht. Nach der Startampel läuft die Zeit. Abkürzungen zählen nicht: Jeder Abschnitt hat eine Mindestzeit."
	elseif hasCar then
		refs.hint.Text = "Dein aktives Auto ist gerade gesperrt (Auktion). Hol unter „Meine Autos“ ein anderes."
	else
		refs.hint.Text = "Für das Zeitfahren brauchst du ein eigenes Auto."
	end
	refs.toDealer.Visible = not canStart
	TrackUI.Step()
end

return TrackUI
