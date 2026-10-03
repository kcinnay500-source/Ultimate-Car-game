-- B-018: Der Mock hängte jede FireClient-Nachricht als tiefe Kopie an RemoteEvent.__data.sent und kürzte nie. Ein
-- simulierter Tag (g:Advance(86400)) brauchte so rund 5 GB. Jetzt behält der Mock nur die jüngsten Nachrichten
-- (Mock.SentKeep bis 2 × Mock.SentKeep) und zählt die verworfenen in __data.sentBase mit: g:Mark() bleibt eine
-- fortlaufende Position, g:Events(..., since) liefert dieselben Nachrichten wie zuvor. Fragt ein Test nach einem
-- Bereich, der schon verworfen ist, gibt es einen Fehler statt einer stillen Lücke.
return {
	{ "FireClient-Verlauf ist begrenzt; Mark/Events/Last zählen fortlaufend weiter", function(T, H)
		local g = H.Garage({ level = 12 })
		local p = g:Join(1801, { name = "Uwe" })
		local q = g:Join(1802, { name = "Vera" })
		g:Advance(1)
		local event = g:Remote("Event")
		local keep = H.Mock.SentKeep
		T.check(type(keep) == "number" and keep >= 1000, "Mock.SentKeep gesetzt")
		keep = keep or 4000
		local start = g:Mark()
		local total = 3 * keep + 123
		local m1, m2
		for i = 1, total do
			if i == total - 50 then
				m1 = g:Mark()
			elseif i == total - 10 then
				m2 = g:Mark()
			end
			event:FireClient(i % 2 == 0 and p or q, "b018", { n = i, pad = string.rep("x", 64) })
		end
		g:Flush()
		local d = event.__data
		T.check(#d.sent <= 2 * keep, "Verlauf begrenzt: " .. #d.sent .. " Einträge (höchstens " .. 2 * keep .. ")")
		T.check(#d.sent >= keep, "die jüngsten " .. keep .. " Nachrichten bleiben (" .. #d.sent .. ")")
		T.eq(g:Mark(), start + total, "Mark zählt fortlaufend (nicht die gekürzte Länge)")
		T.eq(m1, start + total - 51, "Mark vor dem Kürzen bleibt gültig")
		-- Events ab einer Marke: genau die Nachrichten danach, in Reihenfolge, für den richtigen Spieler
		local list = g:Events(p, "b018", m1)
		local ok = #list == 25
		for k, e in ipairs(list) do
			ok = ok and e.n == total - 51 + 2 * k and e.n % 2 == 0
		end
		T.check(ok, "Events(p, since = m1): 25 Nachrichten mit geraden n in Reihenfolge (" .. #list .. ")")
		T.eq(#g:Events(q, "b018", m2), 6, "Events(q, since = m2)")
		T.eq(#g:Events(p, "b018", g:Mark()), 0, "ab der aktuellen Marke: nichts")
		local last = g:Last(q, "b018")
		T.eq(last and last.n, total % 2 == 1 and total or total - 1, "Last ohne Marke: jüngste Nachricht")
		T.eq(g:Last(p, "b018", m2).n, total % 2 == 0 and total or total - 1, "Last mit Marke")
		-- nach dem Kürzen weiter senden: Marke und Verlauf stimmen weiter
		local m3 = g:Mark()
		event:FireClient(p, "toast", "B-018 Hinweis")
		g:Flush()
		T.eq(g:Mark(), m3 + 1, "Marke wächst um eins")
		T.check(g:HasToast(p, "B-018 Hinweis", m3), "HasToast ab Marke")
		T.eq(#g:Toasts(p, m3), 1, "genau ein Toast ab Marke")
		-- verworfener Bereich: kein stilles Teilergebnis
		local okOld, err = pcall(function()
			return g:Events(p, "b018", start)
		end)
		T.check(not okOld and tostring(err):find("verworfen", 1, true) ~= nil, "Events ab einer verworfenen Marke: Fehler statt Lücke")
		local okAll = pcall(function()
			return g:Events(p, "b018")
		end)
		T.check(not okAll, "Events ohne Marke nach dem Kürzen: Fehler statt Lücke")
		-- HasToast ohne Marke: ein Treffer im behaltenen Verlauf gilt; „nicht gefunden“ wäre unbekannt -> Fehler
		T.eq(g:HasToast(p, "B-018 Hinweis"), true, "HasToast ohne Marke: Treffer im behaltenen Verlauf")
		local okMiss = pcall(function()
			return g:HasToast(p, "gibt es nicht")
		end)
		T.check(not okMiss, "HasToast ohne Marke, kein Treffer, Verlauf gekürzt: Fehler statt false")
		T.eq(g:HasToast(p, "gibt es nicht", m3), false, "HasToast mit gültiger Marke: false")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Zwei Stunden Spielzeit: Verlauf bleibt begrenzt, jüngster Snapshot lesbar", function(T, H)
		local g = H.Garage({ level = 12 })
		local p = g:Join(1803, { name = "Willi" })
		g:Advance(1)
		local m = g:Mark()
		g:Advance(7200)
		local d = g:Remote("Event").__data
		T.check(g:Mark() - m > 0, "es wurde gesendet")
		T.check(#d.sent <= 2 * (H.Mock.SentKeep or 4000), "Verlauf begrenzt (" .. #d.sent .. " von " .. g:Mark() .. ")")
		T.check(g:Last(p, "mini") ~= nil or g:Last(p, "sync") ~= nil or g:Mark() == #d.sent, "jüngster Stand lesbar")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
