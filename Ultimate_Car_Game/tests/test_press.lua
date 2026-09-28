-- Phase 2: Schrottpresse (Klicks, Budget, Kauf, Offline, Umtausch, Rebirth)
local function joined(H, opts)
	local srv = H.Server(opts)
	local p = H.Join(srv, 101, "Anna")
	return srv, p, H.Profile(srv, p)
end

return {
	{ "Kostenformel und Multiplikatoren wie HTML", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local u = S.Catalog.PressUpgrades[1]
		T.eq(S.PressRules.UpgradeCost(u, 0), 8, "erstes Upgrade kostet 8")
		T.eq(S.PressRules.UpgradeCost(u, 10), math.max(1, math.floor(8 * 1.145 ^ 10)), "Stufe 10")
		local u50 = S.Catalog.PressUpgrades[51]
		T.eq(S.PressRules.UpgradeCost(u50, 3), math.floor(u50.baseCost * 1.145 ^ 3), "Upgrade 51, Stufe 3")
		local p = S.Rules.LoadData(nil)
		T.eq(S.PressRules.ClickPower(p), 5, "Grund-Klickstärke 5")
		T.eq(S.PressRules.MachinePower(p), 1, "Grund-Maschine 1/s")
		p.games.press.upgrades = { pu0 = 2, pu1 = 4, pu2 = 1 }
		local global = 1 + 7 * 0.0025
		T.near(S.PressRules.GlobalMultiplier(p), global, 1e-9, "globaler Multiplikator")
		T.near(S.PressRules.ClickPower(p), (5 + 2 * 1) * global, 1e-9, "Klickstärke mit Upgrades")
		T.near(S.PressRules.MachinePower(p), (1 + 4 * 1 * 0.35) * global, 1e-9, "Maschine mit Upgrades")
		T.near(S.PressRules.WorkshopMultiplier(p), 1 + (global - 1) * 0.6, 1e-9, "Werkstatt-Querbonus 0,6")
		T.near(S.PressRules.TuningMultiplier(p), 1 + (global - 1) * 0.8, 1e-9, "Tuning-Querbonus 0,8")
	end },

	{ "Erstes Upgrade in höchstens 15 s Klicken", function(T, H)
		local srv, player, prof = joined(H)
		local cost = srv.S.PressRules.UpgradeCost(srv.S.Catalog.PressUpgrades[1], 0)
		local seconds = 0
		while prof.games.press.scrap < cost and seconds < 15 do
			H.Advance(srv, 0.5)
			seconds += 0.5
			H.Act(srv, player, "press_click", { count = 3 }) -- gemütliche 6 Klicks/s
		end
		T.check(prof.games.press.scrap >= cost, "Upgrade nach " .. seconds .. " s bezahlbar")
		T.check(seconds <= 15, "innerhalb 15 s")
		T.eq(H.Act(srv, player, "press_buy", { id = "pu0", level = 0, rid = 1 }), "ok", "Kauf angenommen")
		T.eq(prof.games.press.upgrades.pu0, 1, "Stufe 1")
	end },

	{ "Klicks über dem Limit werden verworfen", function(T, H)
		local srv, player, prof = joined(H)
		local cfg = srv.S.Config
		H.Advance(srv, 1)
		local before = prof.games.press.clicks
		H.Act(srv, player, "press_click", { count = 10000 })
		local accepted = prof.games.press.clicks - before
		T.check(accepted <= cfg.MaxClicksPerSecond * cfg.ClickBurstSeconds, "höchstens Puffer akzeptiert (" .. accepted .. ")")
		-- Dauerfeuer über 10 s: nie mehr als MaxClicksPerSecond × Zeit (+ Puffer)
		local start = prof.games.press.clicks
		for _ = 1, 40 do
			H.Advance(srv, 0.25)
			H.Act(srv, player, "press_click", { count = 500 })
		end
		local total = prof.games.press.clicks - start
		T.check(total <= cfg.MaxClicksPerSecond * 10 + cfg.MaxClicksPerSecond * cfg.ClickBurstSeconds, "10 s Dauerfeuer gedeckelt (" .. total .. ")")
		T.check(total >= cfg.MaxClicksPerSecond * 9, "legitime Klicks kommen an (" .. total .. ")")
		-- negative / kaputte Anzahl
		local c = prof.games.press.clicks
		H.Advance(srv, 1)
		H.Act(srv, player, "press_click", { count = -50 })
		H.Act(srv, player, "press_click", { count = 0 / 0 })
		H.Act(srv, player, "press_click", { count = "20" })
		T.eq(prof.games.press.clicks, c, "negative/NaN/Text-Anzahl ohne Wirkung")
	end },

	{ "Gefälschte Beträge, Preise und Zeitstempel ohne Wirkung", function(T, H)
		local srv, player, prof = joined(H)
		H.Advance(srv, 2)
		local scrap = prof.games.press.scrap
		local credits = prof.credits
		H.Act(srv, player, "press_click", { count = 1, scrap = 1e12, gain = 1e12, time = 0, now = 1 })
		T.check(prof.games.press.scrap - scrap < 100, "Klick mit gefälschtem Betrag bringt nur regulären Ertrag")
		prof.games.press.scrap = 5
		H.Act(srv, player, "press_buy", { id = "pu0", level = 0, cost = 0, price = 0 })
		T.eq(prof.games.press.upgrades.pu0, nil, "gefälschter Preis: kein Kauf ohne genug Schrott")
		T.eq(prof.games.press.scrap, 5, "kein Abzug")
		H.Act(srv, player, "press_exchange", { index = 1, credits = 1e9 })
		T.eq(prof.credits, credits, "Umtausch mit zu wenig Schrott und gefälschtem Betrag: nichts")
		H.Act(srv, player, "tuning_collect", { slot = 1, now = 1e12 })
		T.eq(prof.credits, credits, "gefälschter Zeitstempel beim Abholen: nichts")
		T.eq(H.Act(srv, player, "hack_money", { amount = 1e9 }), "invalid", "unbekannte Aktion abgelehnt")
		T.eq(H.Act(srv, player, "press_buy", "kaputt"), "invalid", "Nutzlast kein Table")
		T.eq(H.Act(srv, player, "press_buy", { id = 5, level = 0 }), "invalid", "falscher Typ")
	end },

	{ "Upgrade-Kauf zieht genau einmal ab (Doppelklick, Wiederholung, gleichzeitig)", function(T, H)
		local srv, player, prof = joined(H)
		prof.games.press.scrap = 1000
		local cost = srv.S.PressRules.UpgradeCost(srv.S.Catalog.PressUpgrades[1], 0)
		-- Doppelklick: zwei Anfragen mit derselben gesehenen Stufe
		H.Act(srv, player, "press_buy", { id = "pu0", level = 0, rid = 11 })
		H.Act(srv, player, "press_buy", { id = "pu0", level = 0, rid = 12 })
		T.eq(prof.games.press.upgrades.pu0, 1, "nur eine Stufe")
		T.eq(prof.games.press.scrap, 1000 - cost, "genau einmal abgezogen")
		-- Wiederholung derselben Anfrage (Lag)
		local scrap = prof.games.press.scrap
		T.eq(H.Act(srv, player, "press_buy", { id = "pu0", level = 1, rid = 13 }), "ok", "zweite Stufe")
		T.eq(H.Act(srv, player, "press_buy", { id = "pu0", level = 1, rid = 13 }), "duplicate", "Wiederholung erkannt")
		T.eq(prof.games.press.upgrades.pu0, 2, "Stufe 2")
		T.eq(prof.games.press.scrap, scrap - srv.S.PressRules.UpgradeCost(srv.S.Catalog.PressUpgrades[1], 1), "einmal abgezogen")
		-- Gleichzeitig über das Remote (Handler laufen nacheinander, ohne Yield)
		local remote = srv.env.services.ReplicatedStorage.Remotes.Action
		scrap = prof.games.press.scrap
		remote.OnServerEvent:Fire(player, "press_buy", { id = "pu0", level = 2, rid = 20 })
		remote.OnServerEvent:Fire(player, "press_buy", { id = "pu0", level = 2, rid = 21 })
		remote.OnServerEvent:Fire(player, "press_buy", { id = "pu0", level = 2, rid = 22 })
		T.eq(prof.games.press.upgrades.pu0, 3, "gleichzeitige Anfragen: eine Stufe")
		T.eq(prof.games.press.scrap, scrap - srv.S.PressRules.UpgradeCost(srv.S.Catalog.PressUpgrades[1], 2), "einmal abgezogen")
		T.check(prof.games.press.scrap >= 0, "nie negativ")
	end },

	{ "Maschinen produzieren nur im Server-Tick", function(T, H)
		local srv, player, prof = joined(H)
		prof.games.press.upgrades = { pu1 = 10 }
		local rate = srv.S.PressRules.MachinePower(prof)
		local before = prof.games.press.scrap
		H.Advance(srv, 10)
		T.near(prof.games.press.scrap - before, rate * 10, rate * 1.05, "etwa 10 s Produktion")
		T.near(prof.games.press.lifetime, prof.games.press.scrap, 1e-6, "Bestenlistenwert wächst mit (ohne Pass)")
		-- Aktionen ohne Tick erzeugen keine Maschinenproduktion
		local s2 = prof.games.press.scrap
		H.Act(srv, player, "leaderboard_refresh")
		T.eq(prof.games.press.scrap, s2, "keine Produktion außerhalb des Ticks")
	end },

	{ "Offline-Ertrag: 1 h korrekt, 24 h gedeckelt, negative Zeit 0", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local R = S.PressRules
		T.eq(R.OfflineSeconds(1000, 4600), 3600, "1 h")
		T.eq(R.OfflineSeconds(1000, 1000 + 24 * 3600), S.Config.PressOfflineCapHours * 3600, "24 h gedeckelt")
		T.eq(R.OfflineSeconds(5000, 1000), 0, "negative Zeit")
		T.eq(R.OfflineSeconds(0, 1000), 0, "kein Zeitstempel")
		T.eq(R.OfflineSeconds(0 / 0, 1000), 0, "NaN")
		T.eq(R.OfflineSeconds(1000, math.huge), 0, "inf")

		-- Ganzer Ablauf mit Rejoin über den Server
		local srv = H.Server()
		local player = H.Join(srv, 202, "Ben")
		local prof = H.Profile(srv, player)
		prof.games.press.upgrades = { pu1 = 20 }
		local rate = R.MachinePower(prof)
		H.Advance(srv, 1)
		H.Leave(srv, player)
		H.Advance(srv, 1)
		srv.env.clock:Jump(3600)
		local p2 = H.Join(srv, 202, "Ben")
		local prof2 = H.Profile(srv, p2)
		T.check(prof2 ~= nil, "Profil nach Rejoin geladen")
		local offline = H.Notices(srv, p2, "offline")
		T.eq(#offline, 1, "Hinweis beim Beitritt")
		T.near(offline[1] and offline[1].scrap or 0, rate * 3601, rate * 2, "1 h Offline-Ertrag")
		T.check(offline[1] and offline[1].text:find("Während du weg warst") ~= nil, "Hinweistext")

		H.Leave(srv, p2)
		srv.env.clock:Jump(24 * 3600)
		local p3 = H.Join(srv, 202, "Ben")
		local o3 = H.Notices(srv, p3, "offline")
		T.near(o3[1] and o3[1].scrap or 0, rate * 8 * 3600, rate * 2, "24 h -> 8 h gedeckelt")

		H.Leave(srv, p3)
		local store = H.Store(srv)
		local key = srv.Profiles.Key(202)
		store.data[key].games.press.lastTick = srv.env.clock.now + 5000 -- Uhr in der Zukunft
		local p4 = H.Join(srv, 202, "Ben")
		T.eq(#H.Notices(srv, p4, "offline"), 0, "negative Differenz: kein Ertrag")
	end },

	{ "Umtausch: Kurs, zu wenig Schrott, keine Gegenrichtung, Bestenliste bleibt", function(T, H)
		local srv, player, prof = joined(H)
		local cfg = srv.S.Config
		prof.games.press.scrap = 150
		prof.games.press.lifetime = 150
		local credits = prof.credits
		H.Act(srv, player, "press_exchange", { index = 1, rid = 1 })
		T.eq(prof.credits, credits + math.floor(100 / cfg.ScrapPerCredit * cfg.ScrapExchangePayout), "Kurs 100 Schrott -> 20 Cr")
		T.eq(prof.games.press.scrap, 50, "Schrott abgezogen")
		T.eq(prof.games.press.lifetime, 150, "Bestenlistenwert sinkt nicht")
		H.Act(srv, player, "press_exchange", { index = 1, rid = 2 })
		T.eq(prof.games.press.scrap, 50, "zu wenig Schrott: nichts")
		H.Act(srv, player, "press_exchange", { index = 99, rid = 3 })
		H.Act(srv, player, "press_exchange", { index = -1, rid = 4 })
		T.eq(prof.games.press.scrap, 50, "ungültiges Paket: nichts")
		local net = srv.S.Net
		for name in pairs(net.Actions) do
			T.check(not (name:find("credit") and name:find("scrap")), "keine Aktion Credits -> Schrott: " .. name)
		end
		T.eq(H.Act(srv, player, "buy_scrap", { credits = 100 }), "invalid", "keine Aktion Credits -> Schrott")
	end },

	{ "Rebirth: Schwelle, genau Schrott und Upgrades zurück, Rest bleibt", function(T, H)
		local srv, player, prof = joined(H)
		local R = srv.S.PressRules
		prof.games.press.upgrades = { pu0 = 5, pu1 = 3 }
		prof.games.press.scrap = 500
		prof.games.press.runScrap = 500
		prof.games.press.lifetime = 12345
		prof.games.tuningLevel = 4
		prof.games.milestones.m_jobs_10 = true
		prof.games.stats.jobsDone = 10
		prof.credits = 777
		prof.level = 9
		prof.games.bays = 3
		H.Act(srv, player, "press_rebirth", { rebirths = 0, rid = 1 })
		T.eq(prof.games.press.rebirths, 0, "unter der Schwelle nicht möglich")
		prof.games.press.runScrap = R.RebirthThreshold(prof)
		prof.games.press.scrap = 5e6
		H.Act(srv, player, "press_rebirth", { rebirths = 0, rid = 2 })
		T.eq(prof.games.press.rebirths, 1, "Rebirth durchgeführt")
		T.eq(prof.games.press.scrap, srv.S.Config.PressStartScrap, "Schrott zurückgesetzt")
		T.eq(next(prof.games.press.upgrades), nil, "Presse-Upgrades zurückgesetzt")
		T.eq(prof.games.press.lifetime, 12345, "Bestenlistenwert bleibt")
		T.eq(prof.credits, 777, "Credits bleiben")
		T.eq(prof.level, 9, "Level bleibt")
		T.eq(prof.games.tuningLevel, 4, "Tuning bleibt")
		T.eq(prof.games.bays, 3, "Werkstatt bleibt")
		T.eq(prof.games.milestones.m_jobs_10, true, "Meilensteine bleiben")
		T.near(R.RebirthMultiplier(prof), 1.1, 1e-9, "Multiplikator dauerhaft")
		T.near(R.ClickPower(prof), 5 * 1.1, 1e-9, "Multiplikator wirkt")
		-- doppelte Anfrage (gleiche gesehene Anzahl) wirkt nicht erneut
		prof.games.press.runScrap = 1e12
		H.Act(srv, player, "press_rebirth", { rebirths = 0, rid = 3 })
		T.eq(prof.games.press.rebirths, 1, "Doppel-Rebirth verhindert")
		-- Multiplikator überlebt Speichern und Laden
		H.Leave(srv, player)
		local p2 = H.Join(srv, 101, "Anna")
		T.eq(H.Profile(srv, p2).games.press.rebirths, 1, "Rebirth gespeichert")
	end },

	{ "Game Pass wirkt aufs Guthaben, nicht auf die Bestenliste", function(T, H)
		local srv, player, prof = joined(H)
		local session = H.Session(srv, player)
		session.passes.doubleScrap = true
		session.passes.pressPlus = true
		H.Advance(srv, 1)
		local s0, l0 = prof.games.press.scrap, prof.games.press.lifetime
		H.Act(srv, player, "press_click", { count = 1 })
		local paid = prof.games.press.scrap - s0
		local ranked = prof.games.press.lifetime - l0
		T.near(paid, ranked * 2, 1e-6, "2× Schrott aufs Guthaben")
		T.near(ranked, 5, 1e-6, "Bestenliste zählt Grundertrag")
		local s1, l1 = prof.games.press.scrap, prof.games.press.lifetime
		srv.PressService.Tick(session, srv.env.clock.now)
		H.Advance(srv, 0) -- nichts
		session.lastTickPrecise = srv.env.clock.precise - 1
		srv.PressService.Tick(session, srv.env.clock.now)
		T.near((prof.games.press.scrap - s1) / math.max(1e-9, prof.games.press.lifetime - l1), 3, 1e-6, "Maschinen ×2 ×1,5 nur im Guthaben")
		-- ohne ID kein Kauf
		H.Act(srv, player, "pass_prompt", { pass = "DoubleScrap", rid = 5 })
		T.eq(#srv.env.services.MarketplaceService.__data.prompts, 0, "Platzhalter-ID startet keinen Kauf")
	end },
}
