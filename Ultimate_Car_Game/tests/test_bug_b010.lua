-- B-010: Voller Server (8 Werkstätten). Ein Spieler geht, sein Speichern dauert; der Nachrücker lädt schneller
-- und darf nicht mit "Alle Werkstätten sind belegt." gekickt werden.
local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
end

local function full(H)
	local g = H.Garage()
	local ps = {}
	for i = 1, g:Config().MaxPlots do
		ps[i] = g:Join(9100 + i, { name = "Spieler" .. i })
	end
	g:Advance(1)
	for i, p in ipairs(ps) do
		assert(g:Plot(p) ~= nil, "Spieler " .. i .. " hat eine Werkstatt")
	end
	return g, ps
end

local function joined(T, g, player, what)
	T.eq(player.__data.kicked, nil, what .. ": kein Kick")
	T.check(g:Plot(player) ~= nil, what .. ": Werkstatt zugeteilt")
	T.check(g:Session(player) ~= nil, what .. ": Sitzung entstanden")
	T.eq(g:Profile(player) and g:Profile(player).writable, true, what .. ": Profil schreibbar")
end

return {
	{ "Vorgänger speichert im zweiten Versuch (1 s Pause): Nachrücker bekommt die frei werdende Werkstatt", function(T, H)
		local g, ps = full(H)
		local ds = g:DataStoreMock()
		g:D(ps[1]).money = 7777
		ds.failNext = 1 -- erster Speicherversuch des Vorgängers schlägt fehl
		g:Leave(ps[1])
		T.eq(g:Record(9101).lock ~= nil, true, "Vorgänger speichert noch")
		local ninth = g:Join(9109, { name = "Nachrücker" })
		g:Advance(3)
		joined(T, g, ninth, "Nachrücker")
		T.eq(g:Record(9101).data.money, 7777, "Vorgänger gespeichert")
		T.eq(g:Record(9101).lock, nil, "Sperre des Vorgängers frei")
		T.check(g:Plot(ps[1]) == nil, "Werkstatt des Vorgängers abgebaut")
		noErrors(T, g)
	end },

	{ "Speichern des Vorgängers dauert mehrere Sekunden: Nachrücker wird trotzdem nicht gekickt", function(T, H)
		local g, ps = full(H)
		local ds = g:DataStoreMock()
		g:D(ps[2]).money = 8888
		ds.updateYield = 6
		g:Leave(ps[2])
		ds.updateYield = 0 -- der Nachrücker lädt schnell
		local ninth = g:Join(9110, { name = "Nachrücker2" })
		g:Advance(2)
		joined(T, g, ninth, "Nachrücker")
		g:Advance(6)
		T.eq(g:Record(9102).data.money, 8888, "Vorgänger gespeichert")
		T.eq(g:Record(9102).lock, nil, "Sperre des Vorgängers frei")
		T.eq(g:Mini().Sessions[ps[2]], nil, "Minispiel-Sitzung des Vorgängers entfernt")
		-- Wirklich voll: ein weiterer Spieler wird weiterhin abgewiesen
		local tenth = g:Join(9111, { name = "Zuviel" })
		g:Advance(1)
		T.check(tenth.__data.kicked ~= nil, "weiterer Spieler bei 8 anwesenden abgewiesen")
		T.check(g:Plot(tenth) == nil, "keine Werkstatt für den abgewiesenen Spieler")
		noErrors(T, g)
	end },
}
