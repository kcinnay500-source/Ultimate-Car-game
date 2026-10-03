-- B-004: Verlassen während eines langsamen Autosave. Der Autosave schreibt noch den alten Stand; das
-- Freigabe-Speichern muss danach den letzten Stand schreiben und die Sitzungssperre freigeben.
local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
end

-- Spieler tritt bei; kurz vor dem nächsten Autosave wird der DataStore langsam (nur dieser eine Aufruf).
local function slowAutosave(g, userId, name, seconds)
	local C = g:Config()
	local ds = g:DataStoreMock()
	local player = g:Join(userId, { name = name })
	g:Advance(1)
	g:D(player).money = 1111
	local before = ds.calls.update
	ds.updateYield = seconds
	local guard = 0
	while ds.calls.update == before and guard < C.AutosaveSeconds * 4 + 8 do -- bis der Autosave unterwegs ist
		g:Advance(0.25)
		guard += 1
	end
	ds.updateYield = 0 -- alle weiteren Aufrufe antworten sofort
	return player, ds.calls.update > before
end

return {
	{ "15 s langsamer Autosave + Verlassen: letzter Stand gespeichert, Sperre frei, Wiederbeitritt schreibbar", function(T, H)
		local g = H.Garage()
		local player, started = slowAutosave(g, 9041, "Lena", 15)
		T.check(started, "Autosave läuft")
		T.eq(g:Profile(player).saving, true, "Autosave hängt im DataStore")
		g:D(player).money = 9999 -- Fortschritt nach dem Schnappschuss des Autosave
		g:Leave(player)
		g:Advance(20)
		local rec = g:Record(9041)
		T.eq(rec.data.money, 9999, "letzter Stand gespeichert")
		T.eq(rec.lock, nil, "Sperre freigegeben")
		T.eq(g:Mini().Sessions[player], nil, "Minispiel-Sitzung entfernt")
		T.check(g:Plot(player) == nil, "Grundstück entfernt")
		local again = g:Join(9041, { name = "Lena" })
		g:Advance(1)
		T.eq(g:Profile(again) and g:Profile(again).writable, true, "Wiederbeitritt schreibbar")
		T.eq(g:D(again) and g:D(again).money, 9999, "Wiederbeitritt mit dem letzten Stand")
		noErrors(T, g)
	end },

	{ "Wiederbeitritt noch während des langsamen Speicherns: wartet, bekommt den letzten Stand, behält seine Sperre", function(T, H)
		local g = H.Garage()
		local player, started = slowAutosave(g, 9042, "Mats", 8)
		T.check(started, "Autosave läuft")
		g:D(player).money = 9999
		g:Leave(player)
		g:Advance(2)
		local again = g:Join(9042, { name = "Mats" }) -- alter Autosave ist noch unterwegs
		g:Advance(12)
		local prof = g:Profile(again)
		T.eq(prof and prof.writable, true, "neue Sitzung schreibbar")
		T.eq(g:D(again) and g:D(again).money, 9999, "neue Sitzung hat den letzten Stand")
		if g:D(again) then
			g:D(again).money = 12345
		end
		g:Advance(g:Config().AutosaveSeconds + 2)
		local rec = g:Record(9042)
		T.eq(rec.data.money, 12345, "neuer Stand nicht vom alten überschrieben")
		T.check(prof and type(rec.lock) == "table" and rec.lock.token == prof.token, "Sperre der neuen Sitzung bleibt")
		noErrors(T, g)
	end },

	{ "Herunterfahren während eines langsamen Autosave bleibt unter 30 s", function(T, H)
		local g = H.Garage()
		local player, started = slowAutosave(g, 9043, "Nora", 60)
		T.check(started, "Autosave läuft")
		g:D(player).money = 9999
		local finished = false
		g:Activate()
		local t0 = g:Now()
		local took
		for _, fn in ipairs(g.env.game.__data.closeCallbacks or {}) do
			g.env.scheduler:spawnIn(g.env.serverCtx, function()
				fn()
				finished = true
				took = g:Now() - t0
			end)
		end
		g:Advance(29.5)
		T.check(finished, "BindToClose kehrt innerhalb von 30 s zurück")
		T.check(took ~= nil and took < 30, "Dauer unter 30 s (" .. tostring(took) .. ")")
		noErrors(T, g)
	end },
}
