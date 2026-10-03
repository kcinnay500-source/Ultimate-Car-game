-- B-007: Zu Ende gespielte, gewertete Spielhallen-Runden zählen für die Nebenmission „Dreimal Spielhalle“ (s_arcade).
-- Vorher: MiniService.storyEventOf prüfte `not data.rejected`; rejected ist ein Zähler (gedrosselte Eingaben) und in Luau
-- ist die Zahl 0 wahr – das Ereignis arcade_round kam nie an.
local rid = 7000
local function act(T, g, pl, action, payload, msg)
	g:Advance(1.1) -- Abklingzeit je Aktion
	rid += 1
	payload = payload or {}
	payload.rid = rid
	local res = g:Act(pl, action, payload)
	T.eq(res, "ok", msg or action)
	return res
end

-- Springt (vor dem Beitritt) auf einen Tag, an dem s_arcade für dieses Level in der Tagesauswahl ist
local function arcadeDay(T, g, level)
	local SR = g:MiniShared("StoryRules")
	for k = 0, 60 do
		local ids = SR.DailyIds(SR.DayKey(g:Now() + k * 86400), level)
		if table.find(ids, "s_arcade") then
			if k > 0 then
				g.env.clock:Jump(k * 86400)
				g:Advance(1.1)
			end
			return true
		end
	end
	T.check(false, "kein Tag mit s_arcade in der Auswahl gefunden")
	return false
end

local function sideN(g, pl)
	local e = g:D(pl).games.story.side.s_arcade
	return e and e.n or 0
end

-- Startet eine Runde; Rückgabe: Rundenpaket (token, endAt)
local function startRound(T, g, pl, what)
	g:Advance(1.5) -- ArcadeRules.StartCooldown
	local m = g:Mark()
	act(T, g, pl, "mini_arcade_start", { game = "arcade_1" }, what .. ": Runde starten")
	local rounds = g:Notices(pl, "arcade_round", m)
	local round = rounds[#rounds]
	T.check(round ~= nil and round.token ~= nil and type(round.endAt) == "number", what .. ": Rundenpaket")
	return round
end

-- Spielt die Runde bis zum Ende (wartet bis endAt) und rechnet ab; Rückgabe: Ergebnis-Hinweis
local function playOut(T, g, pl, what)
	local round = startRound(T, g, pl, what)
	if not round then
		return nil
	end
	local wait = round.endAt - g:Now()
	while wait > 0 do
		local step = math.min(wait, 5)
		g:Advance(step)
		wait -= step
	end
	local m = g:Mark()
	act(T, g, pl, "mini_arcade_finish", { token = round.token }, what .. ": abrechnen")
	local results = g:Notices(pl, "arcade_result", m)
	return results[#results], round
end

return {
	{ "B-007: drei zu Ende gespielte Runden ergeben s_arcade n = 3; abgebrochen, wiederholt und abgelaufen zählt nicht", function(T, H)
		local g = H.Garage({ placeKind = "openworld" })
		if not arcadeDay(T, g, 12) then
			return
		end
		local pl = g:Join(7301, { name = "Arkadia", level = 12 })
		g:Advance(1.2)
		g:Send(pl, "hello")
		g:Advance(1.1)
		T.eq(g:Session(pl).mode, "openworld", "Open World")
		T.eq(sideN(g, pl), 0, "Start: 0")

		-- abgebrochen (sofort beendet): zählt nicht
		local r0 = startRound(T, g, pl, "Abbruch")
		local m = g:Mark()
		act(T, g, pl, "mini_arcade_finish", { token = r0.token }, "sofort beenden")
		local res0 = g:Notices(pl, "arcade_result", m)
		T.check(#res0 == 1 and res0[1].aborted == true, "Runde abgebrochen")
		T.eq(sideN(g, pl), 0, "abgebrochene Runde zählt nicht")

		-- erste gewertete Runde
		local res, round = playOut(T, g, pl, "Runde 1")
		T.check(res ~= nil and res.aborted == false and not res.expired and not res.replay, "Runde 1 regulär gewertet")
		T.eq(res and res.rejected, 0, "keine gedrosselten Eingaben (Zähler 0)")
		T.eq(sideN(g, pl), 1, "Runde 1 zählt")

		-- dasselbe Ergebnis noch einmal (Doppeltipp): zählt nicht
		m = g:Mark()
		act(T, g, pl, "mini_arcade_finish", { token = round.token }, "Ergebnis wiederholen")
		local again = g:Notices(pl, "arcade_result", m)
		T.check(#again == 1 and again[1].replay == true, "Wiederholung gemeldet")
		T.eq(sideN(g, pl), 1, "wiederholtes Ergebnis zählt nicht")

		-- abgelaufen (nach endAt + FinishGrace): zählt nicht
		local AR = g:MiniShared("ArcadeRules")
		local r2 = startRound(T, g, pl, "Ablauf")
		g:Advance(math.max(0, r2.endAt - g:Now()) + AR.FinishGrace + 2)
		m = g:Mark()
		act(T, g, pl, "mini_arcade_finish", { token = r2.token }, "zu spät abrechnen")
		local late = g:Notices(pl, "arcade_result", m)
		T.check(#late == 1 and late[1].expired == true, "Runde abgelaufen")
		T.eq(sideN(g, pl), 1, "abgelaufene Runde zählt nicht")

		-- Runden 2 und 3
		playOut(T, g, pl, "Runde 2")
		T.eq(sideN(g, pl), 2, "Runde 2 zählt")
		m = g:Mark()
		playOut(T, g, pl, "Runde 3")
		T.eq(sideN(g, pl), 3, "drei gewertete Runden: n = 3")
		local done = false
		for _, n in ipairs(g:Notices(pl, "mission", m)) do
			if n.id == "s_arcade" and n.done == true and n.side == true then
				done = true
			end
		end
		T.check(done, "Hinweis: Nebenmission „Dreimal Spielhalle“ geschafft")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },
}
