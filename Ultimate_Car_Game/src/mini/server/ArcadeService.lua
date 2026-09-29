-- ArcadeService: die Spielhalle auf dem Server (PHASE2_CONTRACT §4 Spielhalle, §6 Sicherheit).
-- Aktionen (über MiniService.Handle, also innerhalb von request()):
--   mini_arcade_start  {game}               neue Runde: Token + Parameter aus einem Server-Seed (mini_notice "arcade_round")
--   mini_arcade_input  {token, at, value}   eine Eingabe; at = GetServerTimeNow() des Clients, nur in [now − 0,5; now + 0,06]
--   mini_arcade_finish {token}              Auswertung aus der Server-Zeitachse, genau eine Auszahlung je Token
-- Hinweise an den Client: "arcade_round" (Rundendaten), "arcade_step" (Rückmeldung zu einer Eingabe bzw. Ablehnung),
-- "arcade_result" (Punkte, Credits, Rekord). Eine erneute Abrechnung desselben Tokens sendet das Ergebnis noch einmal
-- (replay = true) und zahlt nichts. Die laufende Runde liegt nur in der Server-Sitzung, nie im Profil.
-- Schnittstelle für MiniService:
--   ArcadeService.Register(Actions, api)   Aktionen registrieren (api wie bei PressService: now, toast, notice, dirty, ...)
--   ArcadeService.OnJoin(ms, d, now)       Sitzungszustand, Tageswechsel
--   ArcadeService.OnLeave(ms)              laufende Runde verfällt (keine Auszahlung)
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local ArcadeRules = require(MiniShared:WaitForChild("ArcadeRules"))
local MiniRules = require(MiniShared:WaitForChild("MiniRules"))

local ArcadeService = {}
ArcadeService.States = setmetatable({}, { __mode = "k" }) -- [ms] = Zustand der Spielhalle

local api

local TEXT = {
	unknown = "Diesen Automaten gibt es nicht.",
	invalid = "Diese Runde ist nicht mehr gültig.",
	expired = "Die Runde ist abgelaufen und wird nicht mehr gewertet.",
}

local MAX_TOKEN = 2147483646

local function newState()
	return {
		round = nil,
		used = {}, -- [token] = Ergebnis (für erneutes Senden), höchstens ArcadeRules.RecentTokens
		usedOrder = {},
		lastStart = -math.huge,
		bucket = ArcadeRules.InputBurst,
		bucketAt = nil,
	}
end

local function stateOf(ms)
	local st = ArcadeService.States[ms]
	if not st then
		st = newState()
		ArcadeService.States[ms] = st
	end
	return st
end

local function rngOf(ms)
	if not ms.rng then
		ms.rng = Random.new()
	end
	return ms.rng
end

local function remember(st, token, result)
	if st.used[token] == nil then
		table.insert(st.usedOrder, token)
	end
	st.used[token] = result
	while #st.usedOrder > ArcadeRules.RecentTokens do
		st.used[table.remove(st.usedOrder, 1)] = nil
	end
end

local function newToken(st, rng)
	for _ = 1, 20 do
		local token = rng:NextInteger(1, MAX_TOKEN)
		if st.used[token] == nil and not (st.round and st.round.token == token) then
			return token
		end
	end
	return nil
end

-- Eingabe-Eimer je Sitzung (zusätzlich zum 2.4.0-Budget von request())
local function takeInput(st, now)
	if st.bucketAt then
		st.bucket = math.min(ArcadeRules.InputBurst, st.bucket + math.max(0, now - st.bucketAt) * ArcadeRules.InputRate)
	end
	st.bucketAt = now
	if st.bucket < 1 then
		return false
	end
	st.bucket -= 1
	return true
end

---------------------------------------------------------------- Aktionen
local function start(ms, data, d, now)
	local def = ArcadeRules.Resolve(data.game)
	if not def then
		api.toast(ms, TEXT.unknown)
		return
	end
	local st = stateOf(ms)
	if now - st.lastStart < ArcadeRules.StartCooldown then
		return -- Doppeltipp: die erste Runde läuft schon an
	end
	local rng = rngOf(ms)
	local token = newToken(st, rng)
	if not token then
		return
	end
	st.lastStart = now
	if st.round then
		-- Neue Runde ersetzt die laufende: die alte verfällt ohne Auszahlung
		local old = st.round
		remember(st, old.token, { token = old.token, game = old.key, abandoned = true, score = 0, credits = 0 })
		st.round = nil
	end
	local a = ArcadeRules.Data(d)
	ArcadeRules.EnsureDay(a, now)
	local seed = rng:NextInteger(1, MAX_TOKEN)
	local round = ArcadeRules.NewRound(def.key, seed, now, token)
	if not round then
		return
	end
	st.round = round
	st.bucket, st.bucketAt = ArcadeRules.InputBurst, now
	local view = ArcadeRules.View(round)
	view.capLeft = ArcadeRules.CapLeft(a, now)
	view.best = a.best[def.key] or 0
	view.reward = def.reward
	api.notice(ms, "arcade_round", view)
end

local function input(ms, data, _, now)
	local st = ArcadeService.States[ms]
	local round = st and st.round
	if not round or round.token ~= data.token or round.closed then
		return -- veraltetes oder fremdes Token: still verwerfen
	end
	if not takeInput(st, now) then
		round.rejected += 1
		return
	end
	local _, info = ArcadeRules.Input(round, data.at, data.value, now)
	if info then
		info.token = round.token
		info.rid = data.rid
		api.notice(ms, "arcade_step", info)
	end
end

local function finish(ms, data, d, now)
	local st = stateOf(ms)
	local token = data.token
	local prev = st.used[token]
	if prev then
		-- Schon abgerechnet (Wiederholung, Doppeltipp, zweiter Versuch): nur das Ergebnis erneut senden
		local again = table.clone(prev)
		again.replay = true
		api.notice(ms, "arcade_result", again)
		return
	end
	local round = st.round
	if not round or round.token ~= token then
		api.toast(ms, TEXT.invalid)
		return
	end
	st.round = nil
	if now > round.endAt + ArcadeRules.FinishGrace then
		round.closed = true
		local res = { token = token, game = round.key, expired = true, score = 0, credits = 0 }
		remember(st, token, res)
		api.toast(ms, TEXT.expired)
		api.notice(ms, "arcade_result", res)
		return
	end
	local ev = ArcadeRules.Finish(round, now)
	local a = ArcadeRules.Data(d)
	local pay = ArcadeRules.Payout(a, round.key, ev.score, now)
	local paid = 0
	if pay.credits > 0 then
		paid = MiniRules.AddMoney(d, pay.credits)
	end
	if pay.xp > 0 then
		MiniRules.GainXP(d, pay.xp)
	end
	pcall(MiniRules.MarkActive, d, now) -- "heute gespielt" (schaltet den Tagesauftrag frei)
	local res = {
		token = token,
		game = round.key,
		score = ev.score,
		credits = paid,
		want = pay.want,
		capped = pay.capped,
		capLeft = pay.capLeft,
		best = pay.best,
		newBest = pay.newBest,
		xp = pay.xp,
		rating = ArcadeRules.Rating(ev.score),
		detail = table.concat(ev.lines, " · "),
		rejected = round.rejected,
		aborted = now < round.endAt - 0.25 and not ArcadeService.Complete(round),
	}
	remember(st, token, res)
	api.notice(ms, "arcade_result", res)
	api.dirty(ms)
end

-- Endet die Runde vor endAt regulär? (MOTOR-OHR: alle Fragen beantwortet, BOXENSTOPP: fertig, EINPARK: alle
-- Aufgaben, Rennen: kein Leben mehr). Nur für die Anzeige ("abgebrochen"), nicht für die Bewertung.
function ArcadeService.Complete(round)
	local st = round.st
	if round.kind == "engine" then
		return st.q > #round.p.questions
	elseif round.kind == "pitstop" then
		return st.finish ~= nil
	elseif round.kind == "park" then
		return st.i > #round.p.tasks
	elseif round.kind == "race" then
		return st.dead == true
	end
	return false
end

function ArcadeService.Register(Actions, a)
	api = a
	Actions.Register("mini_arcade_start", start)
	Actions.Register("mini_arcade_input", input)
	Actions.Register("mini_arcade_finish", finish)
end

function ArcadeService.OnJoin(ms, d, now)
	ArcadeService.States[ms] = newState()
	local a = ArcadeRules.Data(d)
	ArcadeRules.EnsureDay(a, now)
end

function ArcadeService.OnLeave(ms)
	ArcadeService.States[ms] = nil
end

-- Laufende Runde (für Tests und Diagnose)
function ArcadeService.Round(ms)
	local st = ArcadeService.States[ms]
	return st and st.round
end

-- Snapshot-Feld arcade (für MiniSnapshot.Build)
function ArcadeService.Snapshot(d, now)
	return ArcadeRules.SnapshotView(d, now)
end

return ArcadeService
