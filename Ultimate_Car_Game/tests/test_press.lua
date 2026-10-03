-- Schrottpresse im echten Server (GarageServer -> request -> MiniService): Klicks, Budget, Kauf, Offline,
-- Umtausch, Rebirth, Game Passes.
local function joined(H, opts)
	opts = opts or {}
	opts.level = opts.level or 12 -- Presse ab Level 2, Bestenliste/Boni unabhängig vom Level (GameConfig.Unlocks)
	local g = H.Garage(opts)
	local p = g:Join(101, { name = "Anna" })
	g:Advance(1)
	return g, p, g:D(p)
end

return {
	{ "Kostenformel und Multiplikatoren wie HTML", function(T, H)
		local g = H.Garage({ noServer = true })
		local R, Cat, PR = g:Rules(), g:MiniShared("MiniCatalog"), g:MiniShared("PressRules")
		local u = Cat.PressUpgrades[1]
		T.eq(PR.UpgradeCost(u, 0), 8, "erstes Upgrade kostet 8")
		T.eq(PR.UpgradeCost(u, 10), math.max(1, math.floor(8 * 1.145 ^ 10)), "Stufe 10")
		local u50 = Cat.PressUpgrades[51]
		T.eq(PR.UpgradeCost(u50, 3), math.floor(u50.baseCost * 1.145 ^ 3), "Upgrade 51, Stufe 3")
		local d = R.NewData(1760000000)
		T.eq(PR.ClickPower(d), 5, "Grund-Klickstärke 5")
		T.eq(PR.MachinePower(d), 1, "Grund-Maschine 1/s")
		d.games.press.upgrades = { pu0 = 2, pu1 = 4, pu2 = 1 }
		local global = 1 + 7 * 0.0025
		T.near(PR.GlobalMultiplier(d), global, 1e-9, "globaler Multiplikator")
		T.near(PR.ClickPower(d), (5 + 2 * 1) * global, 1e-9, "Klickstärke mit Upgrades")
		T.near(PR.MachinePower(d), (1 + 4 * 1 * 0.35) * global, 1e-9, "Maschine mit Upgrades")
		local MCfg = g:MiniShared("MiniConfig")
		T.near(PR.WorkshopMultiplier(d), 1 + (global - 1) * MCfg.PressWorkshopShare, 1e-9, "Werkstatt-Querbonus (Anteil aus MiniConfig)")
		T.near(PR.TuningMultiplier(d), 1 + (global - 1) * MCfg.PressTuningShare, 1e-9, "Tuning-Querbonus (Anteil aus MiniConfig)")
		T.check(MCfg.PressWorkshopShare > 0 and MCfg.PressWorkshopShare <= 0.1, "Presse-Querbonus klein (docs/BALANCE.md)")
	end },

	{ "Erstes Upgrade in höchstens 15 s Klicken", function(T, H)
		local g, p, d = joined(H)
		local PR, Cat = g:MiniShared("PressRules"), g:MiniShared("MiniCatalog")
		local cost = PR.UpgradeCost(Cat.PressUpgrades[1], 0)
		d.games.press.upgrades = {}
		d.games.press.scrap = 0
		local seconds = 0
		while d.games.press.scrap < cost and seconds < 15 do
			g:Advance(0.5)
			seconds += 0.5
			g:Act(p, "mini_press_click", { count = 3 }) -- gemütliche 6 Klicks/s
		end
		T.check(d.games.press.scrap >= cost, "Upgrade nach " .. seconds .. " s bezahlbar")
		T.check(seconds <= 15, "innerhalb 15 s")
		T.eq(g:Act(p, "mini_press_buy", { id = "pu0", level = 0, rid = 1 }), "ok", "Kauf angenommen")
		T.eq(d.games.press.upgrades.pu0, 1, "Stufe 1")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Klickpakete passieren den Cooldown, Klicks über dem Limit werden verworfen", function(T, H)
		local g, p, d = joined(H)
		local MC = g:MiniShared("MiniConfig")
		-- Zwei Pakete ohne Zeitabstand: kein 0,12-s-Namens-Cooldown für Klicks
		T.eq(g:Act(p, "mini_press_click", { count = 1 }), "ok", "erstes Paket")
		T.eq(g:Act(p, "mini_press_click", { count = 1 }), "ok", "zweites Paket sofort danach")
		g:Advance(1)
		local before = d.games.press.clicks
		g:Act(p, "mini_press_click", { count = 10000 })
		local accepted = d.games.press.clicks - before
		T.check(accepted > 0 and accepted <= MC.MaxClicksPerSecond * MC.ClickBurstSeconds, "höchstens Puffer akzeptiert (" .. accepted .. ")")
		-- Dauerfeuer über 10 s: nie mehr als MaxClicksPerSecond × Zeit (+ Puffer)
		local start = d.games.press.clicks
		for _ = 1, 40 do
			g:Advance(0.25)
			g:Act(p, "mini_press_click", { count = 500 })
		end
		local total = d.games.press.clicks - start
		T.check(total <= MC.MaxClicksPerSecond * 10 + MC.MaxClicksPerSecond * MC.ClickBurstSeconds, "10 s Dauerfeuer gedeckelt (" .. total .. ")")
		T.check(total >= MC.MaxClicksPerSecond * 9, "legitime Klicks kommen an (" .. total .. ")")
		-- negative / kaputte Anzahl
		local c = d.games.press.clicks
		g:Advance(1)
		g:Act(p, "mini_press_click", { count = -50 })
		T.eq(g:Act(p, "mini_press_click", { count = 0 / 0 }), "dropped", "NaN verwirft request()")
		T.eq(g:Act(p, "mini_press_click", { count = "20" }), "invalid", "Text-Anzahl ungültig")
		T.eq(g:Act(p, "mini_press_click", {}), "invalid", "fehlende Anzahl ungültig")
		T.eq(d.games.press.clicks, c, "negative/NaN/Text-Anzahl ohne Wirkung")
		-- Profil wird nicht pro Klick gespeichert
		local ds = g:DataStoreMock()
		local updates = ds.calls.update
		for _ = 1, 20 do
			g:Act(p, "mini_press_click", { count = 1 })
		end
		T.eq(ds.calls.update, updates, "kein Profil-Speichern pro Klick")
		-- Remote-Budget (2.4.0, 30 Anfragen, +20/s) gilt auch für Minispiele
		g:Advance(3)
		local dropped = 0
		for _ = 1, 60 do
			if g:Act(p, "mini_press_click", { count = 1 }) == "dropped" then
				dropped += 1
			end
		end
		T.check(dropped >= 25, "Flut vom Budget verworfen (" .. dropped .. ")")
		g:Advance(2)
		T.eq(g:Act(p, "mini_press_click", { count = 1 }), "ok", "danach wieder Budget")
	end },

	{ "Gefälschte Beträge, Preise und Zeitstempel ohne Wirkung", function(T, H)
		local g, p, d = joined(H)
		g:Advance(2)
		local scrap = d.games.press.scrap
		local money = d.money
		g:Act(p, "mini_press_click", { count = 1, scrap = 1e12, gain = 1e12, time = 0, now = 1 })
		T.check(d.games.press.scrap - scrap < 100, "Klick mit gefälschtem Betrag bringt nur regulären Ertrag")
		d.games.press.scrap = 5
		d.games.press.upgrades = {}
		g:Act(p, "mini_press_buy", { id = "pu0", level = 0, cost = 0, price = 0 })
		T.eq(d.games.press.upgrades.pu0, nil, "gefälschter Preis: kein Kauf ohne genug Schrott")
		T.check(d.games.press.scrap < 10, "kein Abzug")
		g:Act(p, "mini_press_exchange", { index = 1, credits = 1e9 })
		T.eq(d.money, money, "Umtausch mit zu wenig Schrott und gefälschtem Betrag: nichts")
		g:Act(p, "mini_tuning_collect", { slot = 1, now = 1e12 })
		T.eq(d.money, money, "gefälschter Zeitstempel beim Abholen: nichts")
		T.check(g:Act(p, "hack_money", { amount = 1e9 }) ~= "ok", "unbekannte Aktion nicht ausgeführt")
		T.eq(d.money, money, "unbekannte Aktion ohne Wirkung")
		g:Advance(0.2)
		T.eq(g:Act(p, "mini_press_buy", "kaputt"), "invalid", "Nutzlast kein Table")
		g:Advance(0.2)
		T.eq(g:Act(p, "mini_press_buy", { id = 5, level = 0 }), "invalid", "falscher Typ")
		T.eq(g:Act(p, "mini_press_buy", { id = string.rep("x", 80), level = 0 }), "invalid", "zu langer Text")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler")
	end },

	{ "Upgrade-Kauf zieht genau einmal ab (Doppelklick, Wiederholung, gleichzeitig)", function(T, H)
		local g, p, d = joined(H)
		local PR, Cat = g:MiniShared("PressRules"), g:MiniShared("MiniCatalog")
		local u = Cat.PressUpgrades[1]
		d.games.press.upgrades = {}
		d.games.press.scrap = 1000
		local function scrap()
			return d.games.press.scrap
		end
		-- Maschinen dürfen zwischendurch produzieren; gezählt wird nur der Abzug
		local cost = PR.UpgradeCost(u, 0)
		local s0 = scrap()
		g:Act(p, "mini_press_buy", { id = "pu0", level = 0, rid = 11 })
		g:Act(p, "mini_press_buy", { id = "pu0", level = 0, rid = 12 })
		T.eq(d.games.press.upgrades.pu0, 1, "Doppelklick: nur eine Stufe")
		T.near(scrap(), s0 - cost, 0.001, "genau einmal abgezogen")
		g:Advance(0.2)
		s0 = scrap()
		T.eq(g:Act(p, "mini_press_buy", { id = "pu0", level = 1, rid = 13 }), "ok", "zweite Stufe")
		local afterSecond = scrap()
		g:Advance(0.2)
		T.eq(g:Act(p, "mini_press_buy", { id = "pu0", level = 1, rid = 13 }), "duplicate", "Wiederholung (gleiche rid) erkannt")
		g:Advance(0.2)
		T.eq(g:Act(p, "mini_press_buy", { id = "pu0", level = 1, rid = 14 }), "ok", "veraltete Stufe: angenommen, aber still verworfen")
		T.eq(d.games.press.upgrades.pu0, 2, "Stufe 2")
		T.check(math.abs(s0 - PR.UpgradeCost(u, 1) - afterSecond) < 0.001, "einmal abgezogen")
		-- Gleichzeitig über das Remote (ohne Zeit dazwischen)
		g:Advance(0.2)
		local command = g:Remote("Command")
		local s1 = scrap()
		for i = 20, 22 do
			H.Mock.FireServerAs(g.env, command, p, "mini_press_buy", { id = "pu0", level = 2, rid = i })
		end
		g:Flush()
		T.eq(d.games.press.upgrades.pu0, 3, "gleichzeitige Anfragen: eine Stufe")
		T.near(scrap(), s1 - PR.UpgradeCost(u, 2), 0.001, "einmal abgezogen")
		T.check(scrap() >= 0, "nie negativ")
		-- Zwei verschiedene Upgrades direkt nacheinander: Abklingzeit gilt je Ziel
		d.games.press.scrap = 1000
		g:Advance(0.2)
		T.eq(g:Act(p, "mini_press_buy", { id = "pu1", level = 0, rid = 30 }), "ok", "pu1")
		T.eq(g:Act(p, "mini_press_buy", { id = "pu2", level = 0, rid = 31 }), "ok", "pu2 sofort danach")
		T.eq(d.games.press.upgrades.pu1, 1, "pu1 gekauft")
		T.eq(d.games.press.upgrades.pu2, 1, "pu2 gekauft")
	end },

	{ "Maschinen produzieren nur im Server-Tick", function(T, H)
		local g, p, d = joined(H)
		local PR = g:MiniShared("PressRules")
		d.games.press.upgrades = { pu1 = 10 }
		d.games.press.scrap = 0
		d.games.press.lifetime = 0
		local rate = PR.MachinePower(d)
		g:Advance(10)
		T.near(d.games.press.scrap, rate * 10, rate * 1.05, "etwa 10 s Produktion")
		T.near(d.games.press.lifetime, d.games.press.scrap, 1e-6, "Bestenlistenwert wächst mit (ohne Pass)")
		local s2 = d.games.press.scrap
		g:Act(p, "mini_leaderboard_refresh")
		T.eq(d.games.press.scrap, s2, "keine Produktion außerhalb des Ticks")
		-- Snapshot kommt bei laufender Produktion regelmäßig (höchstens 2×/s)
		local m = g:Mark()
		g:Advance(5)
		local snaps = g:Events(p, "mini", m)
		T.check(#snaps >= 4 and #snaps <= 11, "Snapshots während Produktion (" .. #snaps .. " in 5 s)")
		T.eq(snaps[#snaps].version, g:Config().Version, "Snapshot trägt die Version")
		T.eq(snaps[#snaps].credits, d.money, "Snapshot: credits = d.money")
	end },

	{ "Offline-Ertrag: 1 h korrekt, 24 h gedeckelt, negative Zeit 0", function(T, H)
		local g0 = H.Garage({ noServer = true })
		local PR, MC = g0:MiniShared("PressRules"), g0:MiniShared("MiniConfig")
		T.eq(PR.OfflineSeconds(1000, 4600), 3600, "1 h")
		T.eq(PR.OfflineSeconds(1000, 1000 + 24 * 3600), MC.PressOfflineCapHours * 3600, "24 h gedeckelt")
		T.eq(PR.OfflineSeconds(5000, 1000), 0, "negative Zeit")
		T.eq(PR.OfflineSeconds(0, 1000), 0, "kein Zeitstempel")
		T.eq(PR.OfflineSeconds(0 / 0, 1000), 0, "NaN")
		T.eq(PR.OfflineSeconds(1000, math.huge), 0, "inf")

		local g = H.Garage({ level = 12 })
		local player = g:Join(202, { name = "Ben" })
		g:Advance(1)
		local d = g:D(player)
		d.games.press.upgrades = { pu1 = 20 }
		local rate = PR.MachinePower(d)
		g:Advance(1)
		g:Leave(player)
		g:Advance(1)
		g.env.clock:Jump(3600)
		local p2 = g:Join(202, { name = "Ben" })
		g:Advance(0.2)
		T.eq(#g:Notices(p2, "offline"), 0, "Hinweis wartet auf hello")
		g:Send(p2, "hello")
		local offline = g:Notices(p2, "offline")
		T.eq(#offline, 1, "Hinweis nach hello")
		T.near(offline[1] and offline[1].scrap or 0, rate * 3601, rate * 2, "1 h Offline-Ertrag")
		T.check(offline[1] and offline[1].text:find("Während du weg warst") ~= nil, "Hinweistext")
		T.eq(g:D(p2).money, d.money, "Offline-Ertrag ist Schrott, kein Geld")

		g:Leave(p2)
		g.env.clock:Jump(24 * 3600)
		local p3 = g:Join(202, { name = "Ben" })
		g:Advance(0.2)
		g:Send(p3, "mini_sync", {})
		local o3 = g:Notices(p3, "offline")
		T.near(o3[1] and o3[1].scrap or 0, rate * MC.PressOfflineCapHours * 3600, rate * 2, "24 h -> 8 h gedeckelt (Hinweis per mini_sync)")

		g:Leave(p3)
		g:Advance(1)
		local rec = g:Record(202)
		rec.data.games.press.lastTick = g:Now() + 5000 -- Uhr in der Zukunft
		local p4 = g:Join(202, { name = "Ben" })
		g:Advance(0.2)
		g:Send(p4, "hello")
		T.eq(#g:Notices(p4, "offline"), 0, "negative Differenz: kein Ertrag")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Umtausch: Kurs, zu wenig Schrott, keine Gegenrichtung, Bestenliste bleibt", function(T, H)
		local g, p, d = joined(H)
		local MC, MiniNet = g:MiniShared("MiniConfig"), g:MiniShared("MiniNet")
		d.games.press.upgrades = {}
		local pack = MC.ScrapExchangePackages[1]
		d.games.press.scrap = pack * 1.5
		d.games.press.lifetime = pack * 1.5
		local money = d.money
		local m = g:Mark()
		g:Act(p, "mini_press_exchange", { index = 1, rid = 1 })
		T.eq(d.money, money + math.floor(pack / MC.ScrapPerCredit * MC.ScrapExchangePayout), "Kurs aus MiniConfig")
		T.check(math.floor(pack / MC.ScrapPerCredit * MC.ScrapExchangePayout) >= 1, "kleinstes Paket bringt mindestens 1 Cr")
		T.check(d.games.press.scrap < pack * 0.5 + 1, "Schrott abgezogen")
		T.check(d.games.press.lifetime >= pack * 1.5, "Bestenlistenwert sinkt nicht")
		T.check(g:HasToast(p, "Schrotthändler", m), "Toast als 2.4.0-String")
		T.eq(g:State(p).data.money, d.money, "2.4.0-Zustand zeigt den neuen Kontostand")
		T.eq(p.leaderstats.Credits.Value, math.floor(d.money), "leaderstats aktualisiert")
		g:Advance(0.2)
		money = d.money
		g:Act(p, "mini_press_exchange", { index = 1, rid = 2 })
		T.eq(d.money, money, "zu wenig Schrott: nichts")
		g:Act(p, "mini_press_exchange", { index = 99, rid = 3 })
		g:Act(p, "mini_press_exchange", { index = -1, rid = 4 })
		T.eq(d.money, money, "ungültiges Paket: nichts")
		for name in pairs(MiniNet.Actions) do
			T.check(not (name:find("credit") and name:find("scrap")), "keine Aktion Credits -> Schrott: " .. name)
		end
		T.check(g:Act(p, "buy_scrap", { credits = 100 }) ~= "ok", "keine Aktion Credits -> Schrott")
	end },

	{ "Rebirth: Schwelle, genau Schrott und Upgrades zurück, Rest bleibt", function(T, H)
		local g, p, d = joined(H)
		local PR, MC = g:MiniShared("PressRules"), g:MiniShared("MiniConfig")
		d.games.press.upgrades = { pu0 = 5, pu1 = 3 }
		d.games.press.scrap = 500
		d.games.press.runScrap = 500
		d.games.press.lifetime = 12345
		d.games.tuningLevel = 4
		d.games.milestones.m_jobs_10 = true
		d.games.stats.jobsDone = 10
		d.money = 777
		d.level = 9
		d.bays = 2
		g:Act(p, "mini_press_rebirth", { rebirths = 0, rid = 1 })
		T.eq(d.games.press.rebirths, 0, "unter der Schwelle nicht möglich")
		d.games.press.runScrap = PR.RebirthThreshold(d)
		d.games.press.scrap = 5e6
		g:Advance(0.2)
		local m = g:Mark()
		g:Act(p, "mini_press_rebirth", { rebirths = 0, rid = 2 })
		T.eq(d.games.press.rebirths, 1, "Rebirth durchgeführt")
		T.eq(d.games.press.scrap, MC.PressStartScrap, "Schrott zurückgesetzt")
		T.eq(next(d.games.press.upgrades), nil, "Presse-Upgrades zurückgesetzt")
		T.check(d.games.press.lifetime >= 12345, "Bestenlistenwert bleibt")
		T.eq(d.money, 777, "Credits bleiben")
		T.eq(d.level, 9, "Level bleibt")
		T.eq(d.games.tuningLevel, 4, "Tuning bleibt")
		T.eq(d.bays, 2, "Werkstatt bleibt")
		T.eq(d.games.milestones.m_jobs_10, true, "Meilensteine bleiben")
		T.near(PR.RebirthMultiplier(d), 1.1, 1e-9, "Multiplikator dauerhaft")
		T.near(PR.ClickPower(d), 5 * 1.1, 1e-9, "Multiplikator wirkt")
		local n = g:Notices(p, "rebirth", m)
		T.near(n[1] and n[1].multiplier or 0, 1.1, 1e-9, "Hinweis rebirth")
		-- doppelte Anfrage (gleiche gesehene Anzahl) wirkt nicht erneut
		d.games.press.runScrap = 1e12
		g:Advance(0.2)
		g:Act(p, "mini_press_rebirth", { rebirths = 0, rid = 3 })
		T.eq(d.games.press.rebirths, 1, "Doppel-Rebirth verhindert")
		-- Multiplikator überlebt Speichern und Laden
		g:Leave(p)
		g:Advance(1)
		local p2 = g:Join(101, { name = "Anna" })
		g:Advance(0.5)
		T.eq(g:D(p2).games.press.rebirths, 1, "Rebirth gespeichert")
	end },

	{ "Game Pass wirkt aufs Guthaben, nicht auf die Bestenliste", function(T, H)
		local g, p, d = joined(H)
		local ms = g:MiniState(p)
		ms.passes.doubleScrap = true
		ms.passes.pressPlus = true
		g:Advance(1)
		d.games.press.upgrades = {}
		local s0, l0 = d.games.press.scrap, d.games.press.lifetime
		g:Act(p, "mini_press_click", { count = 1 })
		local paid = d.games.press.scrap - s0
		local ranked = d.games.press.lifetime - l0
		T.near(paid, ranked * 2, 1e-6, "2× Schrott aufs Guthaben")
		T.near(ranked, 5, 1e-6, "Bestenliste zählt Grundertrag")
		local s1, l1 = d.games.press.scrap, d.games.press.lifetime
		ms.lastTickAt = g:Now() - 1
		g:MiniServer("PressService").Tick(ms, d, g:Now())
		T.near((d.games.press.scrap - s1) / math.max(1e-9, d.games.press.lifetime - l1), 3, 1e-6, "Maschinen ×2 ×1,5 nur im Guthaben")
		-- ohne ID kein Kauf
		local m = g:Mark()
		g:Act(p, "mini_pass_prompt", { pass = "DoubleScrap", rid = 5 })
		T.eq(#g.env.services.MarketplaceService.__data.prompts, 0, "Platzhalter-ID startet keinen Kauf")
		T.check(g:HasToast(p, "noch nicht eingerichtet", m), "Hinweis: Pass nicht eingerichtet")
		local snap = g:MiniSnapshot(p)
		T.eq(snap and snap.passes.doubleScrapConfigured, false, "Snapshot: nicht eingerichtet")
	end },

	{ "Game Pass mit ID: Besitz beim Beitritt, Kauf-Aufforderung, Kauf in der Sitzung", function(T, H)
		local g = H.Garage({ level = 12, 
			before = function(g)
				local MC = g:MiniShared("MiniConfig")
				MC.GamePasses.DoubleScrap.id = 111
				MC.GamePasses.PressPlus.id = 222
				g.env.services.MarketplaceService.__data.owned["301:111"] = true
			end,
		})
		local a = g:Join(301)
		local b = g:Join(302)
		g:Advance(1)
		T.eq(g:MiniState(a).passes.doubleScrap, true, "A besitzt 2× Schrott")
		T.eq(g:MiniState(a).passes.pressPlus, false, "A ohne Schrottpresse+")
		T.eq(g:MiniState(b).passes.doubleScrap, false, "B ohne Pass")
		local m = g:Mark()
		g:Act(a, "mini_pass_prompt", { pass = "DoubleScrap", rid = 1 })
		T.check(g:HasToast(a, "bereits", m), "Besitz: keine Kaufaufforderung")
		g:Act(b, "mini_pass_prompt", { pass = "PressPlus", rid = 2 })
		local prompts = g.env.services.MarketplaceService.__data.prompts
		T.eq(#prompts, 1, "eine Kaufaufforderung")
		T.eq(prompts[1] and prompts[1].passId, 222, "richtige Pass-ID")
		g.env.services.MarketplaceService.__data.owned["302:222"] = true -- B-019: echter Kauf = Besitz bestätigt
		g.env.services.MarketplaceService.PromptGamePassPurchaseFinished:Fire(b, 222, true)
		g:Flush()
		T.eq(g:MiniState(b).passes.pressPlus, true, "Kauf wirkt sofort in der Sitzung")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
