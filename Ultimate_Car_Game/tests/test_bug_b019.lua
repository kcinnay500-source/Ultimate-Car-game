-- B-019: Game-Pass-Vorteile dürfen nicht allein auf PromptGamePassPurchaseFinished(purchased = true) hin vergeben
-- werden – das Signal lässt sich von manipulierten Clients auslösen. Gutschrift (shop.owned / ms.passes) nur, wenn
-- MarketplaceService:UserOwnsGamePassAsync danach den Besitz bestätigt (kurze Wiederholung wegen Cache).
local PASS_NEON = 7901 -- Shop-Pass (Kosmetik -> shop.owned)
local PASS_PRESS = 7902 -- Minispiel-Pass "Schrottpresse+" (ms.passes.pressPlus)

local function setup(H, after)
	return H.Garage({ level = 12, before = function(g)
		local GC = g:MiniShared("GameConfig")
		GC.Shop.PassByKey.neon.id = PASS_NEON
		g:MiniShared("MiniConfig").GamePasses.PressPlus.id = PASS_PRESS
		if after then
			after(g)
		end
	end })
end

-- zählt die Besitz-Abfragen je "userId:passId"
local function countCalls(g)
	local mp = g.env.services.MarketplaceService.__data
	local calls = {}
	local real = mp.UserOwnsGamePassAsync
	mp.UserOwnsGamePassAsync = function(self, userId, passId)
		local k = userId .. ":" .. passId
		calls[k] = (calls[k] or 0) + 1
		return real(self, userId, passId)
	end
	return calls
end

local function neonCount(g, p)
	local GC = g:MiniShared("GameConfig")
	local owned = g:D(p).games.shop.owned
	local n = 0
	for _, id in ipairs(GC.Shop.PassByKey.neon.grants.cosmetics) do
		if owned[id] then
			n += 1
		end
	end
	return n, #GC.Shop.PassByKey.neon.grants.cosmetics
end

local function fire(g, p, id, purchased)
	g.env.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(p, id, purchased)
	g:Flush()
end

return {
	{ "Gefälschtes Kaufereignis ohne Besitz: keine Gutschrift (shop.owned, ms.passes), kein Toast, Abfragen begrenzt", function(T, H)
		local g = setup(H)
		local p = g:Join(1901, { name = "Mallory" })
		g:Advance(1)
		local calls = countCalls(g)
		local m = g:Mark()
		for _ = 1, 20 do
			fire(g, p, PASS_NEON, true)
			fire(g, p, PASS_PRESS, true)
		end
		g:Advance(60)
		T.eq((neonCount(g, p)), 0, "Shop-Pass: keine Kosmetik ohne Besitz")
		T.eq(g:MiniState(p).shopPasses.neon, nil, "Shop-Pass: nicht als besessen gemerkt")
		local fields = g:MiniServer("ShopService").SnapshotFields(g:MiniState(p), g:D(p), g:Now(), false)
		T.eq(fields.shop.passes.neon, false, "Snapshot: Pass nicht besessen")
		T.eq(g:MiniState(p).passes.pressPlus, false, "Minispiel-Pass: kein Vorteil ohne Besitz")
		T.eq(#g:Toasts(p, m), 0, "kein Dankes-/Gutschrift-Toast")
		T.eq(#g:Notices(p, "shop", m), 0, "kein mini_notice shop/pass")
		local a, b = calls["1901:" .. PASS_NEON] or 0, calls["1901:" .. PASS_PRESS] or 0
		T.check(a >= 1 and b >= 1, "Besitz wurde beim Server nachgefragt (" .. a .. "/" .. b .. ")")
		T.check(a <= 3 and b <= 3, "20 Ereignisse: höchstens 3 Abfragen je Pass (" .. a .. "/" .. b .. ")")
		-- nach dem Speichern ist nichts im Profil gelandet
		g:Leave(p)
		g:Advance(1)
		local rec = g:Record(1901)
		local saved = rec.data.games.shop and rec.data.games.shop.owned or {}
		T.eq(next(saved), nil, "gespeichert: keine Pass-Kosmetik")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Echter Kauf: Besitz bestätigt -> Gutschrift sofort; Besitz erst nach Cache-Verzögerung -> Gutschrift beim Wiederholen", function(T, H)
		local g = setup(H)
		local mp = g.env.services.MarketplaceService.__data
		local p = g:Join(1902, { name = "Alice" })
		local q = g:Join(1903, { name = "Bob" })
		g:Advance(1)
		-- sofort bestätigt
		mp.owned["1902:" .. PASS_NEON] = true
		mp.owned["1902:" .. PASS_PRESS] = true
		local m = g:Mark()
		fire(g, p, PASS_NEON, true)
		fire(g, p, PASS_PRESS, true)
		local n, all = neonCount(g, p)
		T.eq(n, all, "Shop-Pass: Kosmetik gutgeschrieben")
		T.eq(g:MiniState(p).passes.pressPlus, true, "Minispiel-Pass wirkt in der Sitzung")
		T.check(#g:Toasts(p, m) >= 2, "Toasts zu beiden Pässen")
		T.eq((neonCount(g, q)), 0, "zweiter Spieler unberührt")
		T.eq(g:MiniState(q).passes.pressPlus, false, "zweiter Spieler ohne Minispiel-Pass")
		-- Besitz wird erst kurz nach dem Ereignis sichtbar (Cache)
		local calls = countCalls(g)
		fire(g, q, PASS_NEON, true)
		fire(g, q, PASS_PRESS, true)
		T.eq((neonCount(g, q)), 0, "vor der Bestätigung: nichts")
		T.eq(g:MiniState(q).passes.pressPlus, false, "vor der Bestätigung: kein Vorteil")
		g:Advance(1)
		mp.owned["1903:" .. PASS_NEON] = true
		mp.owned["1903:" .. PASS_PRESS] = true
		g:Advance(10)
		n, all = neonCount(g, q)
		T.eq(n, all, "nach der Bestätigung: Kosmetik gutgeschrieben")
		T.eq(g:MiniState(q).passes.pressPlus, true, "nach der Bestätigung: Minispiel-Pass wirkt")
		T.check((calls["1903:" .. PASS_NEON] or 0) <= 3, "höchstens 3 Abfragen")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Besitz-Abfrage wirft / Spieler geht während der Prüfung: keine Gutschrift, kein Fehler; späteres Ereignis prüft neu", function(T, H)
		local g = setup(H)
		local mp = g.env.services.MarketplaceService.__data
		local p = g:Join(1904, { name = "Carol" })
		local q = g:Join(1905, { name = "Dan" })
		g:Advance(1)
		local real = mp.UserOwnsGamePassAsync
		local broken = true
		mp.UserOwnsGamePassAsync = function(self, userId, passId)
			if broken then
				error("HTTP 503")
			end
			return real(self, userId, passId)
		end
		fire(g, p, PASS_NEON, true)
		fire(g, p, PASS_PRESS, true)
		g:Advance(60)
		T.eq((neonCount(g, p)), 0, "Abfrage wirft: keine Gutschrift")
		T.eq(g:MiniState(p).passes.pressPlus, false, "Abfrage wirft: kein Vorteil")
		-- nach dem Ausfall: neues Ereignis + Besitz -> Gutschrift (die Sperre gegen Doppel-Prüfung ist gelöst)
		broken = false
		mp.owned["1904:" .. PASS_NEON] = true
		fire(g, p, PASS_NEON, true)
		local n, all = neonCount(g, p)
		T.eq(n, all, "späteres Ereignis mit Besitz: gutgeschrieben")
		-- Spieler verlässt den Server während der Prüfung
		mp.yield = 2
		mp.owned["1905:" .. PASS_NEON] = true
		mp.owned["1905:" .. PASS_PRESS] = true
		fire(g, q, PASS_NEON, true)
		fire(g, q, PASS_PRESS, true)
		g:Leave(q)
		g:Advance(30)
		mp.yield = 0
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
