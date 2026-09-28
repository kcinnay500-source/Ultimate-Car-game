-- Smoke-Tests: echter 2.4.0-Server (GarageServer + Module) im Mock, Basisbaum aus dem Place.
return {
	{ "Serverstart ohne Fehler (base)", function(T, H)
		local g = H.Garage({ scripts = "base" })
		T.eq(#g:Errors(), 0, "Laufzeitfehler: " .. g:ErrorText())
		local p = g:Join(1001)
		g:Advance(2)
		T.eq(#g:Errors(), 0, "Laufzeitfehler nach Beitritt: " .. g:ErrorText())
		T.check(g:Plot(p) ~= nil, "Plot erstellt")
		T.check(g:State(p) ~= nil, "state gesendet")
	end },
}
