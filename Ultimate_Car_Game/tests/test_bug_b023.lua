-- B-023: Der zweite Kundenanruf direkt nach der Antwort des ersten wurde abgelehnt („Einen Moment – du hast gerade
-- erst angerufen.“): Die Abklingzeit des Handys (3 s ab Anrufbeginn) war länger als die Klingelzeit (2,5 s).
-- Parallele Anrufe verhindert schon GarageServer (p.calling).
local NOW = 1760000000

local function callEvents(g, p, since, state, job)
	local out = {}
	for _, e in ipairs(g:Events(p, "call", since)) do
		if e.state == state and (job == nil or e.job == job) then
			table.insert(out, e)
		end
	end
	return out
end

return {
	{ "B-023 Handy: Mindestabstand zwischen Anruf-Starts ist kürzer als die Klingelzeit, aber weiter vorhanden", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW })
		local PS = g:MiniServer("PhoneService")
		local MiniNet = g:MiniShared("MiniNet")
		local C = g:Config()
		T.check(PS.Cooldown < C.Inspection.RingSeconds, "Abklingzeit " .. tostring(PS.Cooldown) .. " s < Klingelzeit " .. tostring(C.Inspection.RingSeconds) .. " s")
		T.check(PS.Cooldown >= MiniNet.Cooldowns.phone_call and PS.Cooldown >= 1, "weiter ein Mindestabstand zwischen Anruf-Starts (kein Spam-Loch)")
		g:Close()
	end },

	{ "B-023 Handy end-to-end: Anruf B direkt nach der Antwort von A startet; während eines laufenden Anrufs bleibt ein zweiter abgelehnt", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW, level = 12 })
		local Flow = H.Load("tests/lib/garage_flow.lua")
		local PS = g:MiniServer("PhoneService")
		local C = g:Config()
		local p = g:Join(1305, { name = "Vieltelefonierer" })
		g:Advance(1)
		-- zwei Fahrzeug-Checks mit Befund in der Freigabe
		local a = Flow.AcceptInspection(T, g, p, { finding = "brakes" })
		T.check(a ~= nil, "Fahrzeug-Check A angenommen")
		if not a then
			g:Close()
			return
		end
		Flow.Scan(T, g, p, a.id)
		local d = g:D(p)
		local b = H.Copy(Flow.LiveJob(g, p, a.id))
		b.id = "job_b023"
		table.insert(d.jobs, b) -- zweiter Auftrag in derselben Phase (gleiche Daten, eigene Id)
		T.eq(Flow.LiveJob(g, p, a.id).phase, "approval", "A: Freigabe offen")
		T.eq(Flow.LiveJob(g, p, b.id).phase, "approval", "B: Freigabe offen")
		-- Anruf A
		local m = g:Mark()
		T.eq(g:Act(p, "phone_call", { id = a.id, rid = 81 }), "ok", "Anruf A angenommen")
		T.eq(#callEvents(g, p, m, "ringing", a.id), 1, "A klingelt")
		-- während A läuft: B abgelehnt (Server: „Du telefonierst gerade.“ bzw. Abklingzeit), kein zweites Klingeln
		g:Advance(1.2)
		local m1 = g:Mark()
		g:Act(p, "phone_call", { id = b.id, rid = 82 })
		T.eq(#callEvents(g, p, m1, "ringing"), 0, "während des Anrufs kein zweiter")
		T.check(#g:Toasts(p, m1) >= 1, "Ablehnung als Toast")
		-- A wird beantwortet
		g:Advance(C.Inspection.RingSeconds - 1.2 + 0.1)
		T.eq(#callEvents(g, p, m, "answer", a.id), 1, "Kunde A antwortet nach der Klingelzeit")
		T.check(Flow.LiveJob(g, p, a.id).phase ~= "approval", "A entschieden")
		-- direkt danach (0,1 s nach der Antwort, innerhalb der alten 3 s): Anruf B startet
		local m2 = g:Mark()
		T.eq(g:Act(p, "phone_call", { id = b.id, rid = 83 }), "ok", "Anruf B angenommen")
		T.check(not g:HasToast(p, PS.Text.cooldown, m2), "kein „du hast gerade erst angerufen“ (" .. table.concat(g:Toasts(p, m2), " | ") .. ")")
		T.eq(#callEvents(g, p, m2, "ringing", b.id), 1, "B klingelt")
		g:Advance(C.Inspection.RingSeconds + 0.3)
		T.eq(#callEvents(g, p, m2, "answer", b.id), 1, "Kunde B antwortet")
		T.eq(g:ErrorText(), "", "keine Fehler")
		g:Close()
	end },
}
