-- MiniNet: Aktionen und Ereignisse der Minispiele. Es gibt keine eigenen Remotes:
-- Client -> Server über GarageShared.Remotes.Command:FireServer(aktion, flacheNutzlast),
-- Server -> Client über GarageShared.Remotes.Event (kind, data).
local MiniNet = {}

MiniNet.Prefix = "mini_"

-- Aktion -> Felder der Nutzlast (Typprüfung auf dem Server). Zusätzlich optional rid (number).
-- Ausbaustufe 4: Aktionen der Lobby/Tutorial/Prestige tragen kein mini_-Präfix (Vertragsnamen); Mini.Handles
-- prüft nur die Mitgliedschaft in dieser Tabelle.
MiniNet.Actions = {
	mini_press_click = { count = "number" },
	mini_press_buy = { id = "string", level = "number" },
	mini_press_exchange = { index = "number" },
	mini_press_rebirth = { rebirths = "number" },
	mini_tuning_start = { id = "string" },
	mini_tuning_collect = { slot = "number" },
	mini_tuning_idle = {},
	mini_upgrade = { key = "string", level = "number" },
	mini_scrapyard_buy = {},
	mini_scrapyard_dismantle = {},
	mini_scrapyard_sell = {},
	mini_quiz_new = {},
	mini_quiz_answer = { token = "number", choice = "number" },
	mini_parking_new = {},
	mini_parking_tap = { cell = "number" },
	mini_daily_claim = {},
	mini_daily_goal_claim = { id = "string" },
	mini_milestone_claim = { id = "string" },
	mini_leaderboard_refresh = {},
	mini_pass_prompt = { pass = "string" },
	mini_travel = { key = "string" },
	mini_sync = {},
	mini_auction_bid = { lot = "number", amount = "number" },
	mini_auction_consign = { id = "number", start = "number", duration = "number" },
	mini_auction_cancel = { lot = "number" },
	mini_car_buy = { model = "string" },
	mini_car_sell = { id = "number" },
	mini_car_spawn = { id = "number", at = "string" },
	mini_car_despawn = {},
	mini_car_testdrive = { model = "string" },
	mini_car_tune = { id = "number", part = "string", level = "number" },
	mini_car_style = { id = "number", paint = "number", rims = "number", glow = "number", spoiler = "boolean" },
	mini_car_nitro = {},
	mini_car_horn = {}, -- Lichthupe (Hupen-Kosmetik): Server blitzt das gefahrene Auto für alle sichtbar auf
	mini_carwash = {},
	mini_track_start = {},
	mini_arcade_start = { game = "string" },
	mini_arcade_input = { token = "number", at = "number", value = "number" },
	mini_arcade_finish = { token = "number" },
	-- Ausbaustufe 4 (PHASE4_CONTRACT §10): Lobby, Party, Tutorial, Prestige, Freischaltungen (keine Beträge)
	lobby_mode = { mode = "string" },
	lobby_settings = { single = "boolean", passive = "boolean", beginner = "boolean" },
	lobby_go = {},
	lobby_return = {},
	party_create = {},
	party_join = { code = "string" },
	party_leave = {},
	party_kick = { userId = "number" },
	tutorial_next = { step = "number" },
	tutorial_skip = {},
	tutorial_restart = {}, -- Tutorial-Kiosk in der Lobby: noch einmal von vorn (ohne zweite Belohnung)
	prestige_claim = { rank = "number" },
	unlocks_seen = {},
	-- Meilenstein 4 (PHASE4_CONTRACT §8, §10): Tycoon. qty/price sind Absichten in Bargeld
	-- (validate.py INTENT_FIELDS), to = UserId des Handelspartners, id der Angebote = Server-Laufnummer.
	tycoon_choose = { building = "string" },
	tycoon_collect = {},
	tycoon_buy = { id = "string" },
	tycoon_stage = {},
	tycoon_rebirth = {},
	tycoon_abandon = {},
	tycoon_trade_offer = { to = "number", item = "string", qty = "number", price = "number" },
	tycoon_trade_accept = { id = "number" },
	tycoon_trade_cancel = { id = "number" },
	-- Meilenstein 6 (PHASE4_CONTRACT §7, §10): Open-World-Gebäude und Passiv-Modus (typ = Gebäude-Id, on = Schalter)
	ow_build = { typ = "string" },
	ow_collect = { typ = "string" },
	ow_passive = { on = "boolean" },
	-- Meilenstein 7 (§7, §10): Story, Kiesplatz-Verkauf (price = Preisstufe 1..3, eine Absicht: validate.py INTENT_FIELDS),
	-- Nebenmissionen
	story_start = { id = "string" },
	story_claim = { id = "string" },
	story_sell = { offer = "number", price = "number" },
	side_claim = { id = "string" },
	-- Meilenstein 8 (§9, §10): Shop – Kosmetik/DLC-Auto für Credits kaufen, Kosmetik anlegen (item="" legt ab),
	-- Robux-Prompt anfordern (product = Produkt- oder Pass-Schlüssel aus GameConfig.Shop; Antwort über purchasePrompt)
	shop_buy = { item = "string" },
	shop_equip = { slot = "string", item = "string" },
	shop_prompt = { product = "string" },
	-- Startwahl in der Open World (PHASE4_CONTRACT §10): path = einer der vier Startwege (GameConfig.Start.Order)
	start_choose = { path = "string" },
	-- Handy (PhoneService): Kunden eines Fahrzeug-Checks anrufen (id = 2.4.0-Auftrags-Id "job_<n>", kein Betrag)
	phone_call = { id = "string" },
	-- 3.x: Auto rufen (Flitzer/Lieblingsauto an die nächste Fahrbahn, nur Open World) und Lieblingsauto wählen (CarService;
	-- id = Auto-Id, CarCatalog.StarterCarId = -1 = Flitzer)
	car_call = {},
	car_favourite = { id = "number" },
	-- 3.x: Große Werkstatt (PublicWorkshopService): car = Auto-Id als Text, part = Teile-Art ("altteile"),
	-- count = Stückzahl 1..50 (Absicht; der Server prüft Lager, Tageslimit und Preis selbst)
	pw_open = {},
	pw_repair = { car = "string" },
	pw_sell_parts = { part = "string", count = "number" },
	-- 3.x: Entwickler-Menü (DevService): nur für Entwickler, der Server prüft DevService.IsDev bei jedem Aufruf
	-- (field = level | xp | credits | credits_add | cash | start_reset; value wird gerundet und gedeckelt)
	dev_open = {},
	dev_set = { field = "string", value = "number" },
}

-- Abklingzeit in Sekunden je Aktion und Ziel (Feld aus Targets). Standard 0,12 s wie in 2.4.0,
-- aber pro Ziel: zwei schnelle Tipps auf verschiedene Felder gehen beide durch.
MiniNet.DefaultCooldown = 0.12
MiniNet.Cooldowns = {
	mini_press_click = 0, -- eigenes Klick-Budget (20/s)
	mini_travel = 3,
	mini_leaderboard_refresh = 5,
	mini_pass_prompt = 3,
	mini_sync = 1,
	mini_auction_bid = 0.5,
	mini_auction_consign = 2,
	mini_auction_cancel = 1,
	mini_car_buy = 1,
	mini_car_sell = 1,
	mini_car_spawn = 3,
	mini_car_despawn = 1,
	mini_car_testdrive = 3,
	mini_car_style = 0.5,
	mini_car_nitro = 0.5,
	mini_car_horn = 0.5, -- CarService prüft zusätzlich GameConfig.Shop.HornCooldown
	mini_carwash = 2,
	mini_track_start = 3,
	mini_arcade_input = 0, -- eigenes Budget in ArcadeService (25/s); 0,12 s verwürfe schnelle Eingaben
	lobby_go = 3,
	lobby_return = 3,
	party_create = 3, -- = GameConfig.Party.CreateCooldown (LobbyService prüft zusätzlich selbst)
	party_join = 2, -- = GameConfig.Party.JoinCooldown
	party_kick = 1,
	tutorial_skip = 1,
	tutorial_restart = 2,
	prestige_claim = 0.5,
	tycoon_choose = 1,
	tycoon_collect = 0.3,
	tycoon_stage = 1,
	tycoon_rebirth = 2,
	tycoon_abandon = 2,
	tycoon_trade_offer = 1,
	tycoon_trade_accept = 0.5,
	tycoon_trade_cancel = 0.5,
	ow_build = 1,
	ow_collect = 0.5,
	ow_passive = 1,
	story_start = 0.5,
	story_claim = 0.5,
	story_sell = 1,
	side_claim = 0.5,
	shop_prompt = 3,
	start_choose = 1,
	phone_call = 1, -- PhoneService prüft zusätzlich 3 s je Spieler
	car_call = 1, -- CarService prüft zusätzlich GameConfig.StarterCar.CallCooldown (5 s) je Spieler
	car_favourite = 0.3,
	pw_open = 1,
	pw_repair = 1,
	pw_sell_parts = 0.5,
	dev_open = 0.5,
	dev_set = 0.2,
}
MiniNet.Targets = {
	mini_press_buy = "id",
	mini_press_exchange = "index",
	mini_tuning_start = "id",
	mini_tuning_collect = "slot",
	mini_upgrade = "key",
	mini_parking_tap = "cell",
	mini_daily_goal_claim = "id",
	mini_milestone_claim = "id",
	mini_auction_bid = "lot",
	mini_auction_cancel = "lot",
	mini_car_buy = "model",
	mini_car_sell = "id",
	mini_car_tune = "part",
	mini_car_style = "id",
	party_kick = "userId",
	prestige_claim = "rank",
	tycoon_buy = "id",
	tycoon_trade_accept = "id",
	tycoon_trade_cancel = "id",
	ow_build = "typ",
	ow_collect = "typ",
	story_start = "id",
	story_claim = "id",
	side_claim = "id",
	shop_buy = "item",
	shop_equip = "slot",
	shop_prompt = "product",
	phone_call = "id",
	car_favourite = "id",
	pw_repair = "car",
	dev_set = "field", -- je Feld: Level und gleich danach Credits setzen geht beides durch
}

-- Ereignisse Server -> Client
MiniNet.Events = {
	Snapshot = "mini", -- data = MiniSnapshot.Build(...)
	Open = "mini_open", -- data = { tab = string }
	Notice = "mini_notice", -- data = { kind = string, ... }
}

-- Tabs der Minispiel-Oberfläche (auch Werte des Attributs MiniTab an City.Stations.<key>)
MiniNet.Tabs = { "overview", "press", "tuning", "scrapyard", "quiz", "parking", "goals", "leaderboard", "shop", "map", "dealer", "track", "carwash", "auction", "arcade", "lobby", "unlocks", "prestige", "tycoon", "buildings", "story", "grosswerkstatt" }
MiniNet.TabSet = {}
for _, tab in ipairs(MiniNet.Tabs) do
	MiniNet.TabSet[tab] = true
end

function MiniNet.IsAction(name)
	return type(name) == "string" and MiniNet.Actions[name] ~= nil
end

return MiniNet
