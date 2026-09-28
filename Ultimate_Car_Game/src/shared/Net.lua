-- Net: Namen der Remotes und Aktionen. Ein RemoteEvent für alle Absichten (Client -> Server),
-- eines für den Zustand (Server -> Client) und eines für Hinweise (Server -> Client).
local Net = {}

Net.Folder = "Remotes"
Net.Action = "Action"
Net.Sync = "Sync"
Net.Notice = "Notice"

-- Aktion -> erwartete Felder der Nutzlast (Typprüfung auf dem Server)
Net.Actions = {
	press_click = { count = "number" },
	press_buy = { id = "string", level = "number" },
	press_exchange = { index = "number" },
	press_rebirth = { rebirths = "number" },
	workshop_accept = { id = "number" },
	workshop_finish = { id = "number" },
	upgrade_buy = { key = "string", level = "number" },
	tuning_start = { id = "string" },
	tuning_collect = { slot = "number" },
	tuning_idle = {},
	scrapyard_buy = {},
	scrapyard_dismantle = {},
	scrapyard_sell = {},
	quiz_new = {},
	quiz_answer = { token = "number", choice = "number" },
	parking_new = {},
	parking_tap = { cell = "number" },
	daily_claim = {},
	daily_goal_claim = { id = "string" },
	milestone_claim = { id = "string" },
	leaderboard_refresh = {},
	pass_prompt = { pass = "string" },
	ui_ready = {},
}

return Net
