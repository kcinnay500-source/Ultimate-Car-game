-- Übergänge: Beitritt/Verlassen, Sitzungssperre, Studio ohne DataStore, Herunterfahren, Aufräumen, Stationen
return {
	{ "Profil wird gespeichert, Sperre beim Verlassen freigegeben", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 601, "Quinn")
		local store = H.Store(srv)
		local key = srv.Profiles.Key(601)
		T.eq(type(store.data[key]._lock), "table", "Sperre beim Laden gesetzt")
		T.eq(store.data[key]._lock.job, "job-A", "Sperre gehört diesem Server")
		H.Profile(srv, player).credits = 4242
		H.Leave(srv, player)
		T.eq(store.data[key].credits, 4242, "beim Verlassen gespeichert")
		T.eq(store.data[key]._lock, nil, "Sperre freigegeben")
		T.eq(srv.Core.Sessions[player], nil, "Sitzung entfernt")
		T.eq(#H.Errors(srv.env), 0, "keine Laufzeitfehler")
	end },

	{ "Fremde Sitzungssperre: warten, dann Hinweis; verwaiste Sperre wird übernommen", function(T, H)
		local srv = H.Server()
		local store = H.Store(srv)
		local ds = srv.env.services.DataStoreService.__data
		local store2 = store or ds.stores[srv.S.Config.ProfileStoreName]
		local key = srv.Profiles.Key(602)
		store2.data[key] = { credits = 99, level = 3, _lock = { job = "job-B", t = srv.env.clock.now } }
		local player = H.Join(srv, 602, "Rosa")
		T.eq(srv.Core.Get(player), nil, "noch nicht geladen, solange gesperrt")
		H.Advance(srv, 20)
		T.check(player.__data.kicked ~= nil, "nach Wartezeit mit Hinweis getrennt")
		T.eq(store2.data[key].credits, 99, "fremde Daten unverändert")
		T.eq(store2.data[key]._lock.job, "job-B", "fremde Sperre unverändert")
		-- verwaiste Sperre
		local key3 = srv.Profiles.Key(603)
		store2.data[key3] = { credits = 55, _lock = { job = "job-B", t = srv.env.clock.now - 10000 } }
		local p3 = H.Join(srv, 603, "Sam")
		T.check(srv.Core.Get(p3) ~= nil, "verwaiste Sperre übernommen")
		T.eq(H.Profile(srv, p3).credits, 55, "Daten geladen")
		T.eq(store2.data[key3]._lock.job, "job-A", "Sperre übernommen")
	end },

	{ "Verlassen während des Ladens gibt die Sperre frei", function(T, H)
		local srv = H.Server()
		local ds = srv.env.services.DataStoreService.__data
		ds.updateYield = 2
		local player = H.Join(srv, 604, "Tina")
		H.Advance(srv, 0.5)
		H.Leave(srv, player)
		H.Advance(srv, 10)
		local store = H.Store(srv)
		local key = srv.Profiles.Key(604)
		T.eq(store.data[key] and store.data[key]._lock, nil, "keine hängende Sperre")
		T.eq(srv.Core.Sessions[player], nil, "keine hängende Sitzung")
		T.eq(#H.Errors(srv.env), 0, "keine Laufzeitfehler")
		ds.updateYield = 0
		local again = H.Join(srv, 604, "Tina")
		T.check(srv.Core.Get(again) ~= nil, "sofortiger Wiederbeitritt möglich")
	end },

	{ "Autosave gleichzeitig mit Verlassen sperrt nicht erneut", function(T, H)
		local srv = H.Server()
		local ds = srv.env.services.DataStoreService.__data
		local player = H.Join(srv, 605, "Uwe")
		ds.updateYield = 1
		-- Autosave startet (nach 60 s), Spieler verlässt, während er läuft
		H.Advance(srv, 60.25)
		H.Leave(srv, player)
		H.Advance(srv, 10)
		local store = H.Store(srv)
		T.eq(store.data[srv.Profiles.Key(605)]._lock, nil, "Sperre nach beiden Speichervorgängen frei")
		T.eq(#H.Errors(srv.env), 0, "keine Laufzeitfehler")
	end },

	{ "Autosave-Rhythmus", function(T, H)
		local srv = H.Server()
		local ds = srv.env.services.DataStoreService.__data
		H.Join(srv, 606, "Vera")
		local before = ds.calls.update
		H.Advance(srv, 300)
		local saves = ds.calls.update - before
		T.check(saves >= 4 and saves <= 6, "etwa alle 60 s gespeichert (" .. saves .. ")")
	end },

	{ "Studio ohne DataStore: spielbar, nicht gespeichert, Hinweis", function(T, H)
		local srv = H.Server({ dataStoreGetFail = true })
		local player = H.Join(srv, 607, "Wim")
		local session = srv.Core.Get(player)
		T.check(session ~= nil, "Sitzung geladen")
		T.eq(session.persistent, false, "nicht persistent")
		H.Act(srv, player, "ui_ready", { rid = 1 })
		local toasts = H.Notices(srv, player, "toast")
		local found = false
		for _, t in ipairs(toasts) do
			found = found or t.text == srv.S.Locale.T("studio_nosave")
		end
		T.check(found, "Hinweis auf fehlendes Speichern")
		H.Act(srv, player, "press_click", { count = 5 })
		H.Advance(srv, 120)
		H.Leave(srv, player)
		T.eq(#H.Errors(srv.env), 0, "keine Laufzeitfehler")
	end },

	{ "DataStore-Ausfall beim Laden überschreibt keine echten Daten", function(T, H)
		local srv = H.Server()
		local ds = srv.env.services.DataStoreService.__data
		local store = ds.stores[srv.S.Config.ProfileStoreName] or H.Store(srv)
		H.Join(srv, 699, "Init")
		store = H.Store(srv)
		local key = srv.Profiles.Key(608)
		store.data[key] = { credits = 123456, level = 40 }
		ds.fail = true
		local player = H.Join(srv, 608, "Xaver")
		T.eq(srv.Core.Get(player), nil, "während der Wiederholungen noch nicht geladen")
		H.Advance(srv, 5)
		local session = srv.Core.Get(player)
		T.eq(session.persistent, false, "temporäres Profil")
		ds.fail = false
		H.Advance(srv, 120)
		H.Leave(srv, player)
		T.eq(store.data[key].credits, 123456, "echte Daten unverändert")
		T.eq(store.data[key].level, 40, "Level unverändert")
	end },

	{ "Keine NaN/inf im gespeicherten Profil", function(T, H)
		local srv = H.Server()
		local player = H.Join(srv, 609, "Yara")
		local prof = H.Profile(srv, player)
		prof.credits = 0 / 0
		prof.games.press.scrap = math.huge
		H.Leave(srv, player)
		local stored = H.Store(srv).data[srv.Profiles.Key(609)]
		T.check(srv.S.Rules.IsClean(stored), "gespeichertes Profil sauber")
		T.eq(stored.credits, srv.S.Config.StartCredits, "NaN-Credits normalisiert")
	end },

	{ "Herunterfahren speichert alle und gibt Sperren frei", function(T, H)
		local srv = H.Server()
		local a = H.Join(srv, 610, "Anton")
		local b = H.Join(srv, 611, "Berta")
		H.Profile(srv, a).credits = 1111
		H.Profile(srv, b).credits = 2222
		H.Close(srv)
		local store = H.Store(srv)
		T.eq(store.data[srv.Profiles.Key(610)].credits, 1111, "A gespeichert")
		T.eq(store.data[srv.Profiles.Key(611)].credits, 2222, "B gespeichert")
		T.eq(store.data[srv.Profiles.Key(610)]._lock, nil, "A freigegeben")
		T.eq(store.data[srv.Profiles.Key(611)]._lock, nil, "B freigegeben")
		-- danach verlassen: kein erneutes Sperren
		H.Leave(srv, a)
		T.eq(store.data[srv.Profiles.Key(610)]._lock, nil, "bleibt frei")
	end },

	{ "Keine doppelten Verbindungen, Aktionen nach Verlassen wirkungslos", function(T, H)
		local srv = H.Server()
		local remotes = srv.env.services.ReplicatedStorage.Remotes
		local players = srv.env.services.Players
		local promptCounts = {}
		for i, e in ipairs(srv.World.Prompts) do
			promptCounts[i] = e.prompt.Triggered:ConnectionCount()
		end
		local actionCount = remotes.Action.OnServerEvent:ConnectionCount()
		for round = 1, 5 do
			local p = H.Join(srv, 612, "Carl")
			H.Act(srv, p, "press_click", { count = 1 })
			H.Leave(srv, p)
			T.eq(H.Act(srv, p, "press_buy", { id = "pu0", level = 0, rid = round }), "dropped", "Aktion nach Verlassen verworfen")
		end
		T.eq(remotes.Action.OnServerEvent:ConnectionCount(), actionCount, "Remote-Verbindungen konstant")
		T.eq(players.PlayerAdded:ConnectionCount(), 1, "eine PlayerAdded-Verbindung")
		T.eq(players.PlayerRemoving:ConnectionCount(), 1, "eine PlayerRemoving-Verbindung")
		for i, e in ipairs(srv.World.Prompts) do
			T.eq(e.prompt.Triggered:ConnectionCount(), promptCounts[i], "Prompt-Verbindungen konstant")
		end
		local count = 0
		for _ in pairs(srv.Core.Sessions) do
			count += 1
		end
		T.eq(count, 0, "keine Sitzungen übrig")
		-- doppeltes PlayerAdded erzeugt keine zweite Sitzung
		local p = H.Join(srv, 613, "Dana")
		local s1 = srv.Core.Get(p)
		srv.env.services.Players.PlayerAdded:Fire(p)
		T.eq(srv.Core.Get(p), s1, "gleiche Sitzung")
	end },

	{ "Remote-Budget verwirft Flut still", function(T, H)
		local srv = H.Server()
		local p = H.Join(srv, 614, "Ede")
		local dropped = 0
		for i = 1, 200 do
			if H.Act(srv, p, "quiz_new", { rid = i }) == "dropped" then
				dropped += 1
			end
		end
		T.check(dropped >= 150, "Flut verworfen (" .. dropped .. ")")
		H.Advance(srv, 2)
		T.eq(H.Act(srv, p, "quiz_new", { rid = 1000 }), "ok", "danach wieder Budget")
	end },

	{ "Stationen: Reichweite, nur eigene Oberfläche", function(T, H)
		local srv = H.Server()
		local a = H.Join(srv, 615, "Fee")
		local b = H.Join(srv, 616, "Gus")
		local entry = srv.World.Prompts[1]
		T.eq(#srv.World.Prompts, 8, "8 Stationen mit Prompt")
		local anchor = entry.prompt.Parent
		local function character(pos)
			local c = Instance.new("Model")
			local root = Instance.new("Part")
			root.Name = "HumanoidRootPart"
			root.Position = pos
			root.Parent = c
			return c
		end
		anchor.Position = Vector3.new(0, 2, -43)
		a.Character = character(Vector3.new(0, 3, -40))
		b.Character = character(Vector3.new(0, 3, 40))
		entry.prompt.Triggered:Fire(a)
		entry.prompt.Triggered:Fire(b)
		T.eq(#H.Notices(srv, a, "open"), 1, "A in Reichweite: öffnet")
		T.eq(H.Notices(srv, a, "open")[1].tab, entry.tab, "richtiger Bereich")
		T.eq(#H.Notices(srv, b, "open"), 0, "B außer Reichweite: nichts")
	end },
}
