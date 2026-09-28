-- MiniNet: Aktionen und Ereignisse der Minispiele. Es gibt keine eigenen Remotes:
-- Client -> Server über GarageShared.Remotes.Command:FireServer(aktion, flacheNutzlast),
-- Server -> Client über GarageShared.Remotes.Event (kind, data).
local MiniNet = {}

MiniNet.Prefix = "mini_"

-- Aktion -> Felder der Nutzlast (Typprüfung auf dem Server). Zusätzlich optional rid (number).
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
}

-- Ereignisse Server -> Client
MiniNet.Events = {
	Snapshot = "mini", -- data = MiniSnapshot.Build(...)
	Open = "mini_open", -- data = { tab = string }
	Notice = "mini_notice", -- data = { kind = string, ... }
}

-- Tabs der Minispiel-Oberfläche (auch Werte des Attributs MiniTab an City.Stations.<key>)
MiniNet.Tabs = { "overview", "press", "tuning", "scrapyard", "quiz", "parking", "goals", "leaderboard", "shop", "map" }
MiniNet.TabSet = {}
for _, tab in ipairs(MiniNet.Tabs) do
	MiniNet.TabSet[tab] = true
end

function MiniNet.IsAction(name)
	return type(name) == "string" and MiniNet.Actions[name] ~= nil
end

return MiniNet
