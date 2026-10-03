-- TutorialRules: reine Regeln für das Tutorial und die Beginner-Hinweise (docs/PHASE4_CONTRACT.md §6).
-- Liest GameConfig.Tutorial.Steps und GameConfig.Hints; der Stand liegt in d.games.meta (MetaRules):
--   tutorialStep (1..Anzahl Schritte), tutorialDone, tutorialSkipped, beginner, hintsSeen.
-- Keine Instanzen, kein Geld, keine Dienste: Server (TutorialService) und Client (TutorialUI) nutzen dasselbe Modul.
--
-- Ereignisse (GameConfig.Tutorial.Steps[n].event), die der SERVER aus echten Vorgängen meldet:
--   "next"           reiner Lese-Schritt, der Client sendet tutorial_next {step}
--   "station:<key>"  2.4.0-Plot-Station geöffnet (Empfang = "workshop")
--   "tab:<tab>"      Stadt-Station mit MiniTab = <tab> geöffnet
--   "job:accepted"   ein Auftrag liegt in d.jobs           (TutorialRules.JobEvents(d))
--   "job:repair"     ein Auftrag hat die Diagnose hinter sich
--   "job:invoice"    ein Auftrag ist fertig und geprüft
--   "settled"        Abrechnung (Mini.OnSettled)
--   "action:<name>"  eine Mini-Aktion war erfolgreich (z. B. mini_travel)
-- Startwahl (GameConfig.Start): die Schritte hängen vom Startweg ab (meta.startPath -> GameConfig.Tutorial.ByPath[typ];
-- ohne Weg der klassische Weg werkstatt = GameConfig.Tutorial.Steps). Solange ein neues Profil in der Open World noch
-- wählen muss (MetaRules.StartPending), wartet das Tutorial (Waiting: nicht aktiv, Karte verborgen). Steps/Count ohne
-- Profil liefern den klassischen Weg (Abwärtskompatibilität).
local GameConfig = require(script.Parent:WaitForChild("GameConfig"))
local MetaRules = require(script.Parent:WaitForChild("MetaRules"))

local TutorialRules = {}

export type Step = GameConfig.TutorialStep
export type View = {
	step: number, count: number, id: string?, text: string, target: string?, zone: string?, event: string?,
	next: boolean, done: boolean, skipped: boolean, active: boolean, path: string, waiting: boolean, openTab: string?,
}

-- Phasen eines 2.4.0-Auftrags (Rules.Accept/Diagnose/StartWork/Advance) -> erfüllte job:-Ereignisse
local JOB_PHASES = {
	diagnose = { accepted = true },
	approval = { accepted = true }, -- Fahrzeug-Check mit Befund: Kunde muss per Handy freigeben (noch keine Reparatur)
	repair = { accepted = true, repair = true },
	working = { accepted = true, repair = true },
	verify = { accepted = true, repair = true },
	invoice = { accepted = true, repair = true, invoice = true },
}

TutorialRules.Text = {
	notNext = "Dieser Schritt wird automatisch erledigt – mach einfach weiter!",
	wrongStep = "Erledige zuerst den aktuellen Schritt.",
	alreadyDone = "Das Tutorial ist schon fertig.",
	skipped = "Tutorial übersprungen. Am Tutorial-Kiosk in der Lobby kannst du es jederzeit neu starten.",
	notHere = "Das Tutorial läuft in der Werkstattmeile – reise zuerst in die Open World.",
	restarted = "Tutorial neu gestartet! Es geht in der Werkstattmeile (Open World) weiter.",
	restartRunning = "Das Tutorial läuft schon – du findest die Karte in der Werkstattmeile.",
	finishedAgain = "Tutorial noch einmal geschafft! Die Belohnung hattest du schon – viel Spaß in der Werkstattmeile!",
	finished = "Tutorial geschafft! Du bekommst %d Credits und %d XP.",
	progress = "Schritt %d von %d",
	waiting = "Wähle zuerst, womit du startest – dann geht das Tutorial los.",
}

local function finite(v: any): boolean
	return type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge
end

---------------------------------------------------------------- Schritte
-- Weg des Profils für das Tutorial (gewählter Startweg, sonst werkstatt); ohne Profil werkstatt
function TutorialRules.Path(d: any?): string
	if d == nil then
		return GameConfig.Tutorial.DefaultPath or "werkstatt"
	end
	return MetaRules.EffectivePath(d)
end

-- Schritte des Wegs (d = Profil oder nil = klassischer Weg)
function TutorialRules.Steps(d: any?): { Step }
	if d == nil then
		return GameConfig.Tutorial.Steps
	end
	return MetaRules.TutorialSteps(TutorialRules.Path(d))
end

-- Schritte eines Wegs nach Id ("werkstatt" | "autohaus" | …); unbekannt = klassischer Weg
function TutorialRules.StepsForPath(path: any): { Step }
	return MetaRules.TutorialSteps(path)
end

function TutorialRules.Count(d: any?): number
	return #TutorialRules.Steps(d)
end

function TutorialRules.Reward(): { credits: number, xp: number }
	local r = GameConfig.Tutorial.Reward
	return { credits = finite(r.credits) and r.credits or 0, xp = finite(r.xp) and r.xp or 0 }
end

-- Nummer des aktuellen Schritts (1..Count), auch nach Abschluss (dann der letzte Schritt)
function TutorialRules.StepIndex(d: any): number
	local m = MetaRules.Meta(d)
	local n = TutorialRules.Count(d)
	if not m or not finite(m.tutorialStep) then
		return 1
	end
	return math.clamp(math.floor(m.tutorialStep), 1, math.max(1, n))
end

function TutorialRules.Done(d: any): boolean
	local m = MetaRules.Meta(d)
	return m ~= nil and m.tutorialDone == true
end

function TutorialRules.Skipped(d: any): boolean
	local m = MetaRules.Meta(d)
	return m ~= nil and m.tutorialSkipped == true
end

-- Läuft das Tutorial hier? Wird ein Modus übergeben, ist es nur in der Open World aktiv (Vertrag §6: Pflicht beim
-- ersten Beitritt in der Open World; in Lobby und Schnellem Spiel ruht es). Ohne Modus: nur der Profilstand.
function TutorialRules.AllowedIn(mode: any): boolean
	return mode == nil or mode == "openworld"
end

-- Wartet das Tutorial auf die Startwahl? Nur in einer Open-World-Sitzung (mode == "openworld") eines neuen Profils
-- ohne Startweg; ohne Modus (Sitzung ohne Lobby-Verkabelung, reine Regeln) wartet es nicht.
function TutorialRules.Waiting(d: any, mode: any?): boolean
	return mode == "openworld" and MetaRules.StartPending(d)
end

-- Läuft das Tutorial (meta vorhanden, nicht beendet, Modus passt, Startwahl getroffen)?
function TutorialRules.Active(d: any, mode: any?): boolean
	local m = MetaRules.Meta(d)
	return m ~= nil and m.tutorialDone ~= true and TutorialRules.Count(d) > 0 and TutorialRules.AllowedIn(mode)
		and not TutorialRules.Waiting(d, mode)
end

-- Aktueller Schritt (nil, wenn beendet, ohne meta oder außerhalb der Open World) und seine Nummer
function TutorialRules.Current(d: any, mode: any?): (Step?, number)
	local i = TutorialRules.StepIndex(d)
	if not TutorialRules.Active(d, mode) then
		return nil, i
	end
	return TutorialRules.Steps(d)[i], i
end

-- Wurde die Belohnung schon einmal verbucht? (Neustart am Kiosk gibt sie nicht noch einmal.)
function TutorialRules.Rewarded(d: any): boolean
	local m = MetaRules.Meta(d)
	return m ~= nil and m.tutorialRewarded == true
end

function TutorialRules.MarkRewarded(d: any)
	local m = MetaRules.Meta(d)
	if m then
		m.tutorialRewarded = true
	end
end

-- Neustart (Tutorial-Kiosk in der Lobby): nur nach Ende/Überspringen; Schritt 1, ohne zweite Belohnung.
-- Rückgabe: ok, Meldung bei Ablehnung.
function TutorialRules.Restart(d: any): (boolean, string?)
	local m = MetaRules.Meta(d)
	if not m then
		return false, TutorialRules.Text.wrongStep
	end
	if m.tutorialDone ~= true then
		return false, TutorialRules.Text.restartRunning
	end
	-- beendet/übersprungen ohne Startwahl gilt als Veteran: den Weg jetzt festhalten (werkstatt), sonst wartete das
	-- neu gestartete Tutorial auf eine Startwahl, die der Spieler mit dem Überspringen schon hinter sich gelassen hat
	MetaRules.ResolveStartPath(d)
	m.tutorialDone = false
	m.tutorialSkipped = false
	m.tutorialStep = 1
	return true, nil
end

-- Ist der Schritt ein reiner Lese-Schritt („Weiter“)?
function TutorialRules.IsNextStep(step: any): boolean
	return type(step) == "table" and step.event == "next"
end

-- Passt das Ereignis zum Schritt? "next" nur exakt; sonst exakter Vergleich des Ereignisnamens.
function TutorialRules.Matches(step: any, event: any): boolean
	return type(step) == "table" and type(event) == "string" and step.event == event
end

-- Pflicht beim ersten Beitritt in der Open World: noch nicht beendet und Modus openworld
function TutorialRules.ShouldStart(d: any, mode: any): boolean
	return mode == "openworld" and TutorialRules.Active(d, mode) -- wartet, solange die Startwahl offen ist
end

---------------------------------------------------------------- Fortschritt (nur der Server ruft Advance/Next/Skip)
-- Ereignis anwenden. Rückgabe: advanced (bool), finished (bool), erledigter Schritt (Step?).
-- Ein Ereignis erledigt höchstens einen Schritt; der nächste Schritt wartet auf sein eigenes Ereignis.
function TutorialRules.Advance(d: any, event: any): (boolean, boolean, Step?)
	local m = MetaRules.Meta(d)
	local step, i = TutorialRules.Current(d)
	if not m or not step or not TutorialRules.Matches(step, event) then
		return false, false, nil
	end
	local n = TutorialRules.Count(d)
	if i >= n then
		m.tutorialStep = n
		m.tutorialDone = true
		return true, true, step
	end
	m.tutorialStep = i + 1
	return true, false, step
end

-- „Weiter“ vom Client (tutorial_next {step}): nur für next-Schritte und nur für den aktuellen Schritt.
-- Rückgabe: ok, finished | Meldung (String) bei Ablehnung; nil bei stiller Ablehnung (Tutorial beendet / Doppeltipp).
function TutorialRules.Next(d: any, stepNumber: any): (boolean, any)
	local step, i = TutorialRules.Current(d)
	if not step then
		return false, nil -- beendet: still (Doppeltipp nach dem Ende)
	end
	if not finite(stepNumber) then
		return false, TutorialRules.Text.wrongStep
	end
	if math.floor(stepNumber) < i then
		return false, nil -- alter Doppeltipp (Schritt schon erledigt): still
	elseif math.floor(stepNumber) > i then
		return false, TutorialRules.Text.wrongStep
	end
	if not TutorialRules.IsNextStep(step) then
		return false, TutorialRules.Text.notNext
	end
	local _, finished = TutorialRules.Advance(d, "next")
	return true, finished
end

-- Überspringen: jederzeit; setzt tutorialSkipped und tutorialDone (keine Belohnung). false, wenn schon beendet.
function TutorialRules.Skip(d: any): boolean
	local m = MetaRules.Meta(d)
	if not m or m.tutorialDone == true then
		return false
	end
	m.tutorialSkipped = true
	m.tutorialDone = true
	MetaRules.ResolveStartPath(d) -- übersprungen = Veteran der Startwahl (werkstatt, wenn noch keiner gewählt ist)
	return true
end

---------------------------------------------------------------- Aufträge (2.4.0: d.jobs[].phase)
-- Erfüllte job:-Ereignisse aus den laufenden Aufträgen: { ["job:accepted"] = true, ... }
function TutorialRules.JobEvents(d: any): { [string]: boolean }
	local out = {}
	local jobs = type(d) == "table" and d.jobs or nil
	if type(jobs) ~= "table" then
		return out
	end
	for _, j in ipairs(jobs) do
		local set = type(j) == "table" and JOB_PHASES[j.phase] or nil
		if set then
			for k in pairs(set) do
				out["job:" .. k] = true
			end
		end
	end
	return out
end

-- Wartet der aktuelle Schritt auf ein job:-Ereignis, das die Aufträge schon erfüllen? -> dieses Ereignis
function TutorialRules.PendingJobEvent(d: any): string?
	local step = TutorialRules.Current(d)
	if not step or string.sub(step.event, 1, 4) ~= "job:" then
		return nil
	end
	return TutorialRules.JobEvents(d)[step.event] and step.event or nil
end

-- Beginner-Hinweise zu Werkstatt-Aufträgen ("job:accepted", "job:approval"), die gerade fällig und noch nicht gesehen
-- sind (TutorialService.Tick sendet sie; ändert nichts)
function TutorialRules.PendingJobHints(d: any): { string }
	local out = {}
	local jobs = type(d) == "table" and d.jobs or nil
	if type(jobs) ~= "table" or #jobs == 0 then
		return out
	end
	local approval = false
	for _, j in ipairs(jobs) do
		if type(j) == "table" and j.phase == "approval" then
			approval = true
		end
	end
	for _, trigger in ipairs({ "job:accepted", approval and "job:approval" or nil }) do
		if #TutorialRules.PeekHints(d, trigger) > 0 then
			table.insert(out, trigger)
		end
	end
	return out
end

-- Schritt, den der Passiv-Modus unmöglich macht (passiveSkip, z. B. Kiesplatz-Verkauf), bei aktivem Passiv-Modus:
-- -> sein Ereignis (TutorialService.Tick erledigt ihn damit, sonst säße der Spieler fest)
function TutorialRules.PendingPassiveEvent(d: any): string?
	local step = TutorialRules.Current(d)
	if not step or step.passiveSkip ~= true then
		return nil
	end
	local m = MetaRules.Meta(d)
	return m ~= nil and m.passive == true and step.event or nil
end

---------------------------------------------------------------- Beginner-Hinweise (je einmal, nur Beginner)
-- Alle noch nicht gezeigten Hinweise zu einem Auslöser ("station:<key>", "first:<stat>", "unlock:<key>");
-- sie gelten danach als gesehen (meta.hintsSeen). Leer ohne Beginner-Modus oder beim zweiten Aufruf.
function TutorialRules.HintsFor(d: any, trigger: any): { GameConfig.Hint }
	local out = {}
	local hint = MetaRules.HintFor(d, trigger)
	local guard = 0
	while hint and guard < 32 do
		guard += 1
		MetaRules.MarkHint(d, hint.id)
		table.insert(out, hint)
		hint = MetaRules.HintFor(d, trigger)
	end
	return out
end

-- Wie HintsFor, aber ohne etwas zu merken (Vorschau, Client)
function TutorialRules.PeekHints(d: any, trigger: any): { GameConfig.Hint }
	local out = {}
	local m = MetaRules.Meta(d)
	if not m or m.beginner ~= true or type(trigger) ~= "string" then
		return out
	end
	for _, h in ipairs(GameConfig.HintsByWhen[trigger] or {}) do
		if m.hintsSeen[h.id] ~= true then
			table.insert(out, h)
		end
	end
	return out
end

---------------------------------------------------------------- Anzeige (Snapshot-Feld tutorial, Client)
function TutorialRules.ProgressText(step: number, count: number): string
	return string.format(TutorialRules.Text.progress, step, count)
end

-- { step, count, id, text, target, zone, event, next, done, skipped, active, path, waiting, openTab } – flach, sendbar.
-- mode (optional): außerhalb der Open World ist active = false und der Schritt ohne Text/Ziel (die Karte ruht);
-- waiting = true, solange die Startwahl offen ist (dann ebenfalls inaktiv, die Karte bleibt verborgen).
function TutorialRules.View(d: any, mode: any?): View
	local step, i = TutorialRules.Current(d, mode)
	local n = TutorialRules.Count(d)
	local s = step or TutorialRules.Steps(d)[i]
	return {
		step = i,
		count = n,
		id = s and s.id or nil,
		text = (s and step) and s.text or "",
		target = (s and step) and s.target or nil,
		zone = (s and step) and s.zone or nil,
		event = s and s.event or nil,
		next = TutorialRules.IsNextStep(step),
		done = TutorialRules.Done(d),
		skipped = TutorialRules.Skipped(d),
		active = step ~= nil,
		path = TutorialRules.Path(d),
		waiting = TutorialRules.Waiting(d, mode),
		openTab = (s and step) and s.openTab or nil,
	}
end

return TutorialRules
