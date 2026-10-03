-- B-008: Eine heute erfüllte (oder angefangene) Nebenmission darf nicht verschwinden, wenn sich mit einem Levelaufstieg
-- die Tagesauswahl ändert (StoryRules.DailyIds wählt aus einem levelabhängigen Pool).
local rid = 8800
local function act(g, pl, action, payload)
	g:Advance(1.1) -- Abklingzeit je Aktion
	rid += 1
	payload = payload or {}
	payload.rid = rid
	return g:Act(pl, action, payload)
end

local function join(g, userId, name, level)
	local pl = g:Join(userId, { name = name, level = level })
	g:Advance(1.2)
	g:Send(pl, "hello")
	g:Advance(1.1)
	return pl
end

local function has(list, id)
	return table.find(list, id) ~= nil
end

-- Sucht ab jetzt einen Tag, an dem die Auswahl für Level `from` mindestens zwei Missionen hat, von denen eine (lost)
-- auf Level `to` nicht mehr dabei ist. Rückgabe: Tage ab jetzt, lost, andere Mission (kept)
local function findDay(SR, now, from, to)
	for k = 0, 400 do
		local day = SR.DayKey(now + k * 86400)
		local a, b = SR.DailyIds(day, from), SR.DailyIds(day, to)
		if #a >= 2 then
			for _, lost in ipairs(a) do
				if not has(b, lost) then
					for _, other in ipairs(a) do
						if other ~= lost then
							return k, lost, other
						end
					end
				end
			end
		end
	end
	return nil
end

-- Erfüllt eine Nebenmission von heute (Zähler wie nach echten Ereignissen)
local function fulfil(SR, d, id, now)
	local def = SR.SideDef(id)
	d.games.story.side[id] = { n = SR.Target(def), day = SR.DayKey(now), claimed = false }
end

local function listed(SR, d, now, id)
	for _, v in ipairs(SR.SideList(d, now, d.level)) do
		if v.id == id then
			return v
		end
	end
	return nil
end

return {
	{ "B-008 (Regeln): erfüllte Nebenmission bleibt nach dem Levelaufstieg am selben Tag abholbar", function(T, H)
		local g = H.Garage({ noServer = true })
		local SR = g:MiniShared("StoryRules")
		local MiniRules = g:MiniShared("MiniRules")
		local NOW = 1760000000
		local k, lost, other = findDay(SR, NOW, 2, 3)
		if not T.check(k ~= nil, "Tag gefunden, an dem die Auswahl mit Level 3 wechselt") then
			return
		end
		local now = NOW + k * 86400
		local d = g:Rules().NewData(now)
		d.level = 2
		d.games = MiniRules.DefaultGames()
		fulfil(SR, d, lost, now)
		fulfil(SR, d, other, now)
		local ok = SR.SideClaim(d, other, now, d.level)
		T.eq(ok, true, other .. " abgeholt")
		d.level = 3 -- Levelaufstieg durch die Belohnung
		T.check(not has(SR.DailyIds(SR.DayKey(now), 3), lost), lost .. " ist in der Level-3-Auswahl nicht mehr dabei")
		local view = listed(SR, d, now, lost)
		T.check(view ~= nil and view.claimable == true, lost .. " steht weiter in der Liste und ist abholbar")
		local money = d.money
		local ok2, res = SR.SideClaim(d, lost, now, d.level)
		T.eq(ok2, true, lost .. " nach dem Levelaufstieg abholbar: " .. tostring(res))
		T.eq(d.money - money, SR.SideCredits(SR.SideDef(lost), 3), "Credits von " .. lost)
		local okAgain = SR.SideClaim(d, lost, now, d.level)
		T.eq(okAgain, false, "nicht zweimal")
		-- nach Speichern/Laden unverändert (abgeholt bleibt abgeholt, Liste enthält die Mission weiter)
		d.games.story = SR.Load(H.Copy(d.games.story), d, now)
		local after = listed(SR, d, now, lost)
		T.check(after ~= nil and after.done == true, lost .. " nach dem Laden als abgeholt in der Liste")
		-- am nächsten Tag ist sie weg (neue Auswahl), eine nie angefangene Mission taucht nicht zusätzlich auf
		local tomorrow = now + 86400
		SR.EnsureSideDay(d, tomorrow)
		local ids = {}
		for _, v in ipairs(SR.SideList(d, tomorrow, d.level)) do
			if not v.legend then
				table.insert(ids, v.id)
			end
		end
		table.sort(ids)
		local want = SR.DailyIds(SR.DayKey(tomorrow), 3)
		table.sort(want)
		T.eq(table.concat(ids, ","), table.concat(want, ","), "Tageswechsel: nur die neue Auswahl")
	end },

	{ "B-008 (Regeln): angefangene Mission zählt nach dem Levelaufstieg weiter; ohne Fortschritt wechselt die Auswahl wie bisher", function(T, H)
		local g = H.Garage({ noServer = true })
		local SR = g:MiniShared("StoryRules")
		local MiniRules = g:MiniShared("MiniRules")
		local NOW = 1760000000
		local k, lost = findDay(SR, NOW, 2, 3)
		if not T.check(k ~= nil, "Tag gefunden") then
			return
		end
		local now = NOW + k * 86400
		local d = g:Rules().NewData(now)
		d.level = 2
		d.games = MiniRules.DefaultGames()
		-- ohne Fortschritt: nach dem Aufstieg genau die Level-3-Auswahl
		d.level = 3
		T.check(listed(SR, d, now, lost) == nil, lost .. " ohne Fortschritt: nicht mehr in der Liste")
		T.eq(SR.SideClaim(d, lost, now, d.level), false, "ohne Fortschritt nicht abholbar")
		-- mit Fortschritt (1 von n) auf Level 2 angefangen
		d.level = 2
		local def = SR.SideDef(lost)
		local changes
		if def.kind == "stat" then
			changes = SR.OnStat(d, def.stat, 1, now)
		else
			changes = SR.OnEvent(d, def.event, { time = 0 }, now)
		end
		T.check(#changes >= 1, lost .. ": erster Fortschritt auf Level 2")
		d.level = 3
		T.check(listed(SR, d, now, lost) ~= nil, lost .. " mit Fortschritt: bleibt in der Liste")
		local target = SR.Target(def)
		for _ = 2, target do
			if def.kind == "stat" then
				SR.OnStat(d, def.stat, 1, now)
			else
				SR.OnEvent(d, def.event, { time = 0 }, now)
			end
		end
		T.eq(SR.SideProgress(d, def, now), target, lost .. ": Fortschritt läuft nach dem Aufstieg weiter")
	end },

	{ "B-008 (Server): side_claim nach Levelaufstieg und Rejoin bringt die Credits; höchstens 3 Abholungen pro Tag", function(T, H)
		local g = H.Garage({ placeKind = "openworld" })
		local SR = g:MiniShared("StoryRules")
		local k, lost, other = findDay(SR, g:Now() + 60, 2, 3)
		if not T.check(k ~= nil, "Tag gefunden") then
			return
		end
		if k > 0 then
			g.env.clock:Jump(k * 86400)
			g:Advance(1.1)
		end
		local pl = join(g, 8801, "Nebenbei", 2)
		local d = g:D(pl)
		T.eq(d.level, 2, "Level 2")
		local today = SR.DayKey(g:Now())
		T.check(has(SR.DailyIds(today, 2), lost) and has(SR.DailyIds(today, 2), other), "beide in der heutigen Auswahl")
		fulfil(SR, d, lost, g:Now())
		fulfil(SR, d, other, g:Now())
		local m = g:Mark()
		T.eq(act(g, pl, "side_claim", { id = other }), "ok", "side_claim " .. other)
		T.eq(d.games.story.side[other].claimed, true, other .. " abgeholt")
		d.level = math.max(d.level, 3) -- Levelaufstieg
		g:Advance(1.1)
		g:Leave(pl)
		g:Advance(2)
		pl = join(g, 8801, "Nebenbei")
		d = g:D(pl)
		T.eq(SR.DayKey(g:Now()), today, "noch derselbe Tag")
		T.check(d.level >= 3, "Level 3 nach Rejoin")
		local money = d.money
		m = g:Mark()
		T.eq(act(g, pl, "side_claim", { id = lost }), "ok", "side_claim " .. lost)
		T.check(not g:HasToast(pl, "gibt es heute nicht", m), "kein „gibt es heute nicht“")
		T.eq(d.money - money, SR.SideCredits(SR.SideDef(lost), d.level), "Credits von " .. lost .. " gutgeschrieben")

		-- Tageslimit: alles, was jetzt gelistet ist, erfüllen und abholen – insgesamt höchstens DailyLimit
		d.level = 40
		local limit = SR.Config().Side.DailyLimit
		local tries = 0
		for _, v in ipairs(SR.SideList(d, g:Now(), d.level)) do
			if not v.legend and not v.done then
				fulfil(SR, d, v.id, g:Now())
				act(g, pl, "side_claim", { id = v.id })
				tries += 1
			end
		end
		local claims = 0
		for _, e in pairs(d.games.story.side) do
			if e.day == today and e.claimed then
				claims += 1
			end
		end
		T.check(tries + 2 > limit, "mehr Versuche als das Limit (" .. tries + 2 .. ")")
		T.eq(claims, limit, "höchstens " .. limit .. " Abholungen pro Tag")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },
}
