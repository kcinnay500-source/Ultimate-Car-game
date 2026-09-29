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
	prestige_claim = { rank = "number" },
	unlocks_seen = {},
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
	mini_carwash = 2,
	mini_track_start = 3,
	mini_arcade_input = 0, -- eigenes Budget in ArcadeService (25/s); 0,12 s verwürfe schnelle Eingaben
	lobby_go = 3,
	lobby_return = 3,
	party_create = 3, -- = GameConfig.Party.CreateCooldown (LobbyService prüft zusätzlich selbst)
	party_join = 2, -- = GameConfig.Party.JoinCooldown
	party_kick = 1,
	tutorial_skip = 1,
	prestige_claim = 0.5,
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
}

-- Ereignisse Server -> Client
MiniNet.Events = {
	Snapshot = "mini", -- data = MiniSnapshot.Build(...)
	Open = "mini_open", -- data = { tab = string }
	Notice = "mini_notice", -- data = { kind = string, ... }
}

-- Tabs der Minispiel-Oberfläche (auch Werte des Attributs MiniTab an City.Stations.<key>)
MiniNet.Tabs = { "overview", "press", "tuning", "scrapyard", "quiz", "parking", "goals", "leaderboard", "shop", "map", "dealer", "track", "carwash", "auction", "arcade", "lobby", "unlocks", "prestige" }
MiniNet.TabSet = {}
for _, tab in ipairs(MiniNet.Tabs) do
	MiniNet.TabSet[tab] = true
end

function MiniNet.IsAction(name)
	return type(name) == "string" and MiniNet.Actions[name] ~= nil
end

return MiniNet
