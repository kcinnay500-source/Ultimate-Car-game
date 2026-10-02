-- Übergänge im echten Server: Beitritt/Verlassen, Sitzungssperre (2.4.0-Profiles), Studio, DataStore-Ausfall,
-- Herunterfahren, Aufräumen, Remote-Budget, Robux-Kauf während Minispielen, transacting-Sperre, Stationen der Stadt.
local function noErrors(T, g, what)
	return T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
end

return {
	{ "Profil samt games wird beim Verlassen gespeichert, Sperre frei, Sitzungen entfernt", function(T, H)
		local g = H.Garage()
		local player = g:Join(601, { name = "Quinn" })
		g:Advance(1)
		local rec = g:Record(601)
		T.eq(type(rec.lock), "table", "Sperre beim Laden gesetzt")
		local d = g:D(player)
		d.money = 4242
		d.games.parts = 13
		d.games.press.rebirths = 2
		g:Leave(player)
		g:Advance(1)
		rec = g:Record(601)
		T.eq(rec.data.money, 4242, "beim Verlassen gespeichert")
		T.eq(rec.data.games.parts, 13, "Altteile gespeichert")
		T.eq(rec.data.games.press.rebirths, 2, "Rebirths gespeichert")
		T.eq(rec.lock, nil, "Sperre freigegeben")
		T.eq(g:Mini().Sessions[player], nil, "Minispiel-Sitzung entfernt")
		T.check(g:Plot(player) == nil, "Grundstück entfernt")
		noErrors(T, g)
	end },

	{ "Fremde Sitzungssperre: temporär spielbar, nichts überschrieben; abgelaufene Sperre wird übernommen", function(T, H)
		local g = H.Garage({ level = 12 })
		local MiniRules = g:MiniShared("MiniRules")
		local games = MiniRules.DefaultGames()
		games.parts = 77
		g:Seed(602, { version = 2, data = { version = 2, money = 99, level = 12, games = games }, receipts = {},
			lock = { token = "anderer-server", expires = g:Now() + 170 } })
		local player = g:Join(602, { name = "Rosa" })
		g:Advance(16) -- Profiles.Load wartet bis zu ProfileLockRetries Sekunden auf die fremde Sperre
		T.check(g:Session(player) ~= nil, "Sitzung trotz Sperre")
		T.eq(g:Profile(player).writable, false, "nicht beschreibbar")
		g:D(player).level = 12 -- Sitzung unter fremder Sperre spielt mit Ersatzdaten: Presse ab Level 2 (GameConfig.Unlocks)
		T.eq(g:Act(player, "mini_press_click", { count = 3 }), "ok", "Minispiele spielbar")
		g:Advance(100)
		g:Leave(player)
		g:Advance(2)
		local rec = g:Record(602)
		T.eq(rec.data.money, 99, "fremde Daten unverändert")
		T.eq(rec.data.games.parts, 77, "fremde Minispiel-Daten unverändert")
		T.eq(rec.lock.token, "anderer-server", "fremde Sperre unverändert")
		-- verwaiste (abgelaufene) Sperre
		g:Seed(603, { version = 2, data = { version = 2, money = 55, level = 2 }, receipts = {},
			lock = { token = "abgestuerzt", expires = g:Now() - 10 } })
		local p3 = g:Join(603, { name = "Sam" })
		g:Advance(1)
		T.eq(g:Profile(p3).writable, true, "verwaiste Sperre übernommen")
		T.eq(g:D(p3).money, 55, "Daten geladen")
		T.check(g:Record(603).lock.token ~= "abgestuerzt", "Sperre übernommen")
		noErrors(T, g)
	end },

	{ "Ortswechsel: Sperre des alten Servers wird kurz danach frei -> Laden wartet und die Sitzung speichert (nicht temporär)", function(T, H)
		local g = H.Garage({ level = 12 })
		g:Seed(604, { version = 2, data = { version = 2, money = 321, level = 5 }, receipts = {},
			lock = { token = "alter-server", expires = g:Now() + 170 } })
		local player = g:Join(604, { name = "Tim" })
		g:Advance(3)
		T.eq(g:Session(player), nil, "noch keine Sitzung, solange die fremde Sperre gilt")
		-- alter Server speichert beim Verlassen und gibt die Sperre frei
		g:Record(604).lock = nil
		g:Advance(3)
		T.check(g:Session(player) ~= nil, "Sitzung nach freigegebener Sperre")
		T.eq(g:Profile(player).writable, true, "beschreibbar (keine temporäre Sitzung)")
		T.eq(g:D(player).money, 321, "Daten geladen")
		T.check(g:Record(604).lock and g:Record(604).lock.token ~= "alter-server", "eigene Sperre gesetzt")
		noErrors(T, g)
	end },

	{ "Verlassen während des Ladens gibt die Sperre frei", function(T, H)
		local g = H.Garage({ dataStore = { updateYield = 2 } })
		local player = g:Join(604, { name = "Tina" })
		g:Advance(0.5)
		g:Leave(player)
		g:Advance(10)
		local rec = g:Record(604)
		T.eq(rec and rec.lock, nil, "keine hängende Sperre")
		T.eq(g:Mini().Sessions[player], nil, "keine hängende Minispiel-Sitzung")
		noErrors(T, g)
		g:DataStoreMock().updateYield = 0
		local again = g:Join(604, { name = "Tina" })
		g:Advance(1)
		T.eq(g:Profile(again) and g:Profile(again).writable, true, "sofortiger Wiederbeitritt möglich")
	end },

	{ "Autosave gleichzeitig mit Verlassen sperrt nicht erneut; Autosave-Rhythmus", function(T, H)
		local g = H.Garage()
		local C = g:Config()
		local ds = g:DataStoreMock()
		local player = g:Join(605, { name = "Uwe" })
		g:Advance(1)
		ds.updateYield = 1
		g:Advance(C.AutosaveSeconds - 0.75) -- Autosave läuft gerade
		g:Leave(player)
		g:Advance(10)
		T.eq(g:Record(605).lock, nil, "Sperre nach beiden Speichervorgängen frei")
		noErrors(T, g)
		ds.updateYield = 0
		g:Join(606, { name = "Vera" })
		g:Advance(1)
		local before = ds.calls.update
		g:Advance(300)
		local saves = ds.calls.update - before
		local expected = 300 / C.AutosaveSeconds
		T.check(saves >= math.floor(expected) - 1 and saves <= math.ceil(expected) + 1, "etwa alle " .. C.AutosaveSeconds .. " s gespeichert (" .. saves .. ")")
	end },

	{ "Studio ohne Speichern: spielbar, nichts geschrieben", function(T, H)
		local g = H.Garage({ level = 12,  studio = true })
		local ds = g:DataStoreMock()
		local player = g:Join(607, { name = "Wim" })
		g:Advance(1)
		T.check(g:Session(player) ~= nil, "Sitzung geladen")
		g:D(player).level = 12 -- Studio lädt keinen Datensatz: Presse ab Level 2 (GameConfig.Unlocks)
		T.eq(g:Profile(player).writable, false, "nicht beschreibbar")
		T.eq(g:State(player).saveStatus, "Nur diese Sitzung", "Status für den Client")
		T.eq(g:Act(player, "mini_press_click", { count = 5 }), "ok", "Minispiele laufen")
		g:Advance(120)
		g:Leave(player)
		g:Advance(2)
		T.eq(ds.calls.update + ds.calls.set + ds.calls.ordered, 0, "kein DataStore-Schreiben in Studio")
		noErrors(T, g)
	end },

	{ "DataStore-Ausfall beim Laden überschreibt keine echten Daten; später lädt der echte Stand", function(T, H)
		local g = H.Garage()
		local ds = g:DataStoreMock()
		g:Seed(608, { version = 2, data = { version = 2, money = 123456, level = 40 }, receipts = {} })
		ds.fail = true
		local player = g:Join(608, { name = "Xaver" })
		g:Advance(5)
		T.check(g:Session(player) ~= nil, "temporäre Sitzung (spielbar)")
		T.eq(g:Profile(player).writable, false, "temporäres Profil")
		T.eq(g:Profile(player).status, "Laden fehlgeschlagen · temporär", "Status")
		ds.fail = false
		g:D(player).money = 5
		g:Advance(120)
		g:Leave(player)
		g:Advance(2)
		local rec = g:Record(608)
		T.eq(rec.data.money, 123456, "echte Daten unverändert")
		T.eq(rec.data.level, 40, "Level unverändert")
		local again = g:Join(608, { name = "Xaver" })
		g:Advance(1)
		T.eq(g:D(again).money, 123456, "Wiederbeitritt lädt echte Daten")
		T.eq(type(g:D(again).games), "table", "games angelegt")
	end },

	{ "Keine NaN/inf im gespeicherten Profil", function(T, H)
		local g = H.Garage({ level = 2 }) -- Presse ab Level 2 (GameConfig.Unlocks)
		local MiniRules = g:MiniShared("MiniRules")
		local player = g:Join(609, { name = "Yara" })
		g:Advance(1)
		g:D(player).games.parts = 21
		g:Send(player, "save")
		g:Advance(1)
		T.eq(g:Record(609).data.games.parts, 21, "sauberer Stand gespeichert")
		g:D(player).games.press.scrap = math.huge
		g:D(player).money = 0 / 0
		g:Leave(player)
		g:Advance(2)
		local rec = g:Record(609)
		T.check(MiniRules.IsClean(rec), "gespeicherter Datensatz sauber")
		T.eq(rec.data.games.parts, 21, "letzter sauberer Stand bleibt")
		local warned = false
		for _, w in ipairs(g:Warnings()) do
			warned = warned or w:find("ungültige Werte", 1, true) ~= nil
		end
		T.check(warned, "Speichern abgelehnt und protokolliert")
		noErrors(T, g)
	end },

	{ "Herunterfahren: alle gespeichert, Sperren frei, Bestenliste geschrieben", function(T, H)
		local g = H.Garage({ level = 2 }) -- Presse ab Level 2 (GameConfig.Unlocks)
		local MC = g:MiniShared("MiniConfig")
		local a = g:Join(610, { name = "Anton" })
		local b = g:Join(611, { name = "Berta" })
		g:Advance(1)
		g:D(a).money = 1111
		g:D(b).money = 2222
		g:Advance(5)
		g:Close()
		noErrors(T, g, "BindToClose")
		T.eq(g:Record(610).data.money, 1111, "A gespeichert")
		T.eq(g:Record(611).data.money, 2222, "B gespeichert")
		T.eq(g:Record(610).lock, nil, "A freigegeben")
		T.eq(g:Record(611).lock, nil, "B freigegeben")
		local ordered = g:DataStoreMock().ordered[MC.LeaderboardStoreName].data
		T.check(ordered["610"] ~= nil and ordered["611"] ~= nil, "Bestenliste beim Herunterfahren geschrieben")
		g:Leave(a)
		g:Advance(2)
		T.eq(g:Record(610).lock, nil, "bleibt frei")
	end },

	{ "Letzter Spieler verlässt, Server fährt herunter: Speichern wird abgewartet", function(T, H)
		local g = H.Garage()
		local ds = g:DataStoreMock()
		local player = g:Join(622, { name = "Ines" })
		g:Advance(1)
		g:D(player).money = 3333
		ds.updateYield = 2
		g:Leave(player) -- Speichern läuft noch (wartet auf den DataStore)
		local done = false
		g:Activate()
		g.env.scheduler:spawnIn(g.env.serverCtx, function()
			for _, fn in ipairs(g.env.game.__data.closeCallbacks) do
				fn()
			end
			done = true
		end)
		g:Flush()
		T.eq(done, false, "BindToClose wartet auf laufendes Speichern")
		g:Advance(5)
		T.eq(done, true, "BindToClose endet danach")
		local rec = g:Record(622)
		T.eq(rec.data.money, 3333, "gespeichert")
		T.eq(rec.lock, nil, "Sperre freigegeben")
	end },

	{ "Schneller Wiederbeitritt auf demselben Server lädt den neuesten Stand", function(T, H)
		local g = H.Garage()
		local ds = g:DataStoreMock()
		local player = g:Join(623, { name = "Jonas" })
		g:Advance(1)
		g:D(player).money = 4444
		g:D(player).games.parts = 44
		ds.updateYield = 1
		g:Leave(player)
		local again = g:Join(623, { name = "Jonas" }) -- während das Freigabe-Speichern noch läuft
		g:Advance(15)
		T.eq(g:Profile(again) and g:Profile(again).writable, true, "keine temporäre Sitzung")
		T.eq(g:D(again).money, 4444, "neuester Stand geladen")
		T.eq(g:D(again).games.parts, 44, "neueste Minispiel-Daten geladen")
		g:Advance(70) -- Autosave der neuen Sitzung
		T.eq(g:Record(623).data.money, 4444, "nichts überschrieben")
		noErrors(T, g)
	end },

	{ "Verlassen während der Game-Pass-Prüfung hinterlässt keine Sperre und keine Sitzung", function(T, H)
		local g = H.Garage({ before = function(g)
			g:MiniShared("MiniConfig").GamePasses.DoubleScrap.id = 111
			g.env.services.MarketplaceService.__data.yield = 2
		end })
		local player = g:Join(624, { name = "Kim" })
		g:Advance(0.5)
		g:Leave(player)
		g:Advance(10)
		T.eq(g:Mini().Sessions[player], nil, "keine Minispiel-Sitzung")
		local rec = g:Record(624)
		T.eq(rec and rec.lock, nil, "keine Sperre")
		T.eq(#g:Notices(player, "offline"), 0, "kein Hinweis nach dem Verlassen")
		noErrors(T, g)
	end },

	{ "Verlassen während der Game-Pass-Prüfung verliert den Offline-Ertrag nicht", function(T, H)
		local function run(leaveEarly)
			local g = H.Garage({ before = function(g)
				g:MiniShared("MiniConfig").GamePasses.DoubleScrap.id = 111
				g.env.services.MarketplaceService.__data.yield = 2
			end })
			g:Seed(625, { version = 2, data = { version = 2, money = 500, level = 3, games = {
				press = { scrap = 0, lifetime = 0, upgrades = { pu1 = 10, pu4 = 5 }, lastTick = g:Now() - 3600 },
			} }, receipts = {} })
			local player = g:Join(625, { name = "Lars" })
			if leaveEarly then
				g:Advance(0.5) -- Prüfung läuft noch (2 s)
			else
				g:Advance(3) -- Prüfung fertig, Offline-Ertrag gutgeschrieben
			end
			g:Leave(player)
			g:Advance(5)
			local rec = g:Record(625)
			return rec.data.games.press, g
		end
		local early, g1 = run(true)
		local normal, g2 = run(false)
		T.check(normal.scrap > 1000, "Offline-Ertrag im Normalfall (" .. tostring(normal.scrap) .. ")")
		T.check(early.scrap >= normal.scrap * 0.95, "frühes Verlassen behält den Offline-Ertrag (" .. tostring(early.scrap) .. " vs. " .. tostring(normal.scrap) .. ")")
		T.check(early.lastTick > g1:Now() - 60, "Presse-Uhr gespeichert")
		T.eq(#g1:Errors() + #g2:Errors(), 0, "keine Laufzeitfehler: " .. g1:ErrorText() .. g2:ErrorText())
	end },

	{ "Keine doppelten Verbindungen, Aktionen nach Verlassen wirkungslos", function(T, H)
		local g = H.Garage({ before = function(g)
			g:BuildCity({ stations = { { key = "presse", tab = "press", pos = Vector3.new(0, 1, -350) } } })
		end })
		g:Advance(1)
		local command = g:Remote("Command")
		local players = g.env.services.Players
		local prompt = g:Find("Workspace.City.Stations.presse"):FindFirstChildOfClass("ProximityPrompt")
		local promptCount = prompt.Triggered:ConnectionCount()
		local actionCount = command.OnServerEvent:ConnectionCount()
		local added, removing = players.PlayerAdded:ConnectionCount(), players.PlayerRemoving:ConnectionCount()
		for round = 1, 5 do
			local p = g:Join(612, { name = "Carl" })
			g:Advance(0.5)
			g:Act(p, "mini_press_click", { count = 1 })
			g:Leave(p)
			g:Advance(0.5)
			T.eq(g:Act(p, "mini_press_buy", { id = "pu0", level = 0, rid = round }), "dropped", "Aktion nach Verlassen verworfen")
		end
		T.eq(command.OnServerEvent:ConnectionCount(), actionCount, "Remote-Verbindungen konstant")
		T.eq(players.PlayerAdded:ConnectionCount(), added, "PlayerAdded-Verbindungen konstant")
		T.eq(players.PlayerRemoving:ConnectionCount(), removing, "PlayerRemoving-Verbindungen konstant")
		T.eq(prompt.Triggered:ConnectionCount(), promptCount, "Stations-Prompt-Verbindungen konstant")
		T.eq(promptCount, 1, "Station genau einmal gebunden")
		T.eq(next(g:Mini().Sessions), nil, "keine Minispiel-Sitzungen übrig")
		-- doppeltes PlayerAdded erzeugt keine zweite Sitzung
		local p = g:Join(613, { name = "Dana" })
		g:Advance(0.5)
		local s1 = g:Session(p)
		players.PlayerAdded:Fire(p)
		g:Advance(0.5)
		T.eq(g:Session(p), s1, "gleiche Sitzung")
		noErrors(T, g)
	end },

	{ "Remote-Budget verwirft Flut still", function(T, H)
		local g = H.Garage({ level = 12 })
		local p = g:Join(614, { name = "Ede" })
		g:Advance(3)
		local dropped = 0
		for i = 1, 200 do
			if g:Act(p, "mini_quiz_new", { rid = i }) == "dropped" then
				dropped += 1
			end
		end
		T.check(dropped >= 150, "Flut verworfen (" .. dropped .. ")")
		g:Advance(2)
		T.eq(g:Act(p, "mini_quiz_new", { rid = 1000 }), "ok", "danach wieder Budget")
	end },

	{ "Robux-Kauf während Minispiel-Aktionen: kein Geldverlust, transacting sperrt Minispiele", function(T, H)
		local g = H.Garage({ level = 2 }) -- Presse ab Level 2 (GameConfig.Unlocks)
		local C = g:Config()
		local product = C.CreditProducts[1]
		product.productId = 424242
		local ds = g:DataStoreMock()
		local p = g:Join(615, { name = "Fee" })
		g:Advance(1)
		local d = g:D(p)
		d.games.parts = 12
		d.games.press.upgrades = { pu1 = 10 }
		-- Minispiel-Geld vor dem Kauf
		g:Act(p, "mini_scrapyard_sell", { rid = 1 })
		local before = d.money
		T.eq(d.games.parts, 7, "Altteile verkauft")
		-- Kauf startet, DataStore antwortet langsam
		ds.updateYield = 2
		local decision, done = g:Purchase(p, 424242, "kauf-race")
		T.eq(done, false, "Kauf wartet auf den DataStore")
		T.eq(g:Profile(p).transacting, true, "transacting gesetzt")
		local scrap0 = d.games.press.scrap
		local m = g:Mark()
		T.eq(g:Act(p, "mini_scrapyard_sell", { rid = 2 }), "dropped", "Minispiel-Aktion während transacting gesperrt")
		T.eq(g:Act(p, "mini_press_exchange", { index = 1, rid = 3 }), "dropped", "Umtausch gesperrt")
		T.check(g:HasToast(p, "Dein Kauf wird sicher gespeichert", m), "Hinweis an den Spieler")
		T.eq(d.games.parts, 7, "keine Altteile verkauft")
		-- Direkter Aufruf (doppelte Sicherung in MiniService)
		T.eq(g:Mini().Handle(g:Session(p), "mini_scrapyard_sell", { rid = 4 }), "dropped", "MiniService sperrt selbst")
		g:Advance(1.2)
		T.check(d.games.press.scrap > scrap0, "Presse produziert während transacting weiter (Schrott)")
		T.eq(d.money, before, "Geld während transacting unverändert")
		g:Advance(3)
		T.eq(g:Profile(p).transacting, false, "Kauf abgeschlossen")
		T.eq(d.money, before + product.credits, "Credits gutgeschrieben, Minispiel-Geld erhalten")
		T.eq(g:Record(615).data.money, before + product.credits, "gespeicherter Stand stimmt")
		T.eq(g:Record(615).receipts["kauf-race"], true, "Beleg gespeichert")
		ds.updateYield = 0
		g:Advance(0.2)
		T.eq(g:Act(p, "mini_scrapyard_sell", { rid = 5 }), "ok", "danach wieder spielbar")
		T.eq(d.money, before + product.credits + g:MiniShared("MiniConfig").ScrapyardSellCredits, "Verkauf nach dem Kauf")
		local _ = decision
		noErrors(T, g)
	end },

	{ "Fehler einer Sitzung stoppt Tick und Snapshots der anderen nicht", function(T, H)
		local g = H.Garage()
		local a = g:Join(625, { name = "Lars" })
		local b = g:Join(626, { name = "Mona" })
		g:Advance(1)
		g:D(a).games.press = nil -- kaputte Sitzung
		g:Advance(3)
		local m = g:Mark()
		g:Advance(3)
		T.check(#g:Events(b, "mini", m) > 0, "B erhält weiter Snapshots")
		T.check(#g:Events(a, "state", m) > 0, "A erhält weiter den 2.4.0-Zustand")
		T.check(#g:Warnings() > 0, "Fehler protokolliert")
		noErrors(T, g, "Schleifen laufen weiter")
	end },

	{ "Stationen der Stadt: Reichweite, Tab öffnen, eröffnet bald, eigene Werkstatt", function(T, H)
		local g = H.Garage({ level = 12, before = function(g)
			g:BuildCity({ stations = {
				{ key = "presse", tab = "press", pos = Vector3.new(0, 1, -350) },
				{ key = "autohaus", tab = "dealer", pos = Vector3.new(40, 1, -350) },
				{ key = "heim", tab = "workshop", pos = Vector3.new(80, 1, -350) },
				{ key = "dragstrecke", tab = "dragstrip", title = "Die Dragstrecke", pos = Vector3.new(120, 1, -350) },
			} })
		end })
		local a = g:Join(615, { name = "Fee" })
		local b = g:Join(616, { name = "Gus" })
		g:Advance(1)
		local function prompt(key)
			return g:Find("Workspace.City.Stations." .. key):FindFirstChildOfClass("ProximityPrompt")
		end
		g:Teleport(a, Vector3.new(0, 3, -345))
		g:Teleport(b, Vector3.new(0, 3, -300))
		local m = g:Mark()
		g:Trigger(a, prompt("presse"), { force = true })
		g:Trigger(b, prompt("presse"), { force = true })
		local opened = g:Events(a, "mini_open", m)
		T.eq(#opened, 1, "A in Reichweite: öffnet")
		T.eq(opened[1] and opened[1].tab, "press", "richtiger Bereich")
		T.eq(#g:Events(b, "mini_open", m), 0, "B außer Reichweite: nichts")
		g:Teleport(a, Vector3.new(40, 3, -345))
		m = g:Mark()
		g:Trigger(a, prompt("autohaus"), { force = true })
		opened = g:Events(a, "mini_open", m)
		T.eq(opened[1] and opened[1].tab, "dealer", "Autohaus ist seit Ausbaustufe 2 ein echter Tab")
		T.check(not g:HasToast(a, "eröffnet bald", m), "Autohaus: kein 'eröffnet bald' mehr")
		g:Teleport(a, Vector3.new(120, 3, -345))
		m = g:Mark()
		g:Trigger(a, prompt("dragstrecke"), { force = true })
		T.check(g:HasToast(a, "Die Dragstrecke eröffnet bald.", m), "unbekannter Bereich: eröffnet bald")
		T.eq(#g:Events(a, "mini_open", m), 0, "unbekannter Bereich öffnet keinen Tab")
		g:Teleport(a, Vector3.new(80, 3, -345))
		g:Trigger(a, prompt("heim"), { force = true })
		local home = g:Station(a, "home")
		T.check((g:Root(a).Position - home.Position).Magnitude < 12, "Station 'workshop' bringt in die eigene Werkstatt")
		noErrors(T, g)
	end },
}
