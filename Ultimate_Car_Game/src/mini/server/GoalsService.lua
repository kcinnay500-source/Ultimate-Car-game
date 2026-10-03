-- GoalsService: Tagesauftrag, Tagesziele und Meilensteine auf dem Server.
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(MiniShared:WaitForChild("MiniConfig"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local GoalRules = require(MiniShared:WaitForChild("GoalRules"))

local GoalsService = {}

-- Tageswechsel (UTC). true, wenn ein neuer Tag begann.
function GoalsService.Tick(_, d, now)
	return GoalRules.EnsureDay(d, now)
end

function GoalsService.Register(Actions, api)
	Actions.Register("mini_daily_claim", function(ms, _, d, now)
		local ok, res = GoalRules.ClaimDaily(d, now)
		if ok then
			api.toast(ms, "Tagesauftrag erledigt: +" .. MiniLocale.Credits(MiniConfig.DailyCredits) .. " und " .. MiniConfig.DailyParts .. " Altteile.")
		else
			api.toast(ms, res)
		end
	end)

	Actions.Register("mini_daily_goal_claim", function(ms, data, d, now)
		local ok, res = GoalRules.ClaimDailyGoal(d, data.id, now)
		api.toast(ms, ok and ("Tagesziel erledigt: +" .. MiniLocale.Credits(res.credits)) or res)
	end)

	Actions.Register("mini_milestone_claim", function(ms, data, d)
		local ok, res = GoalRules.ClaimMilestone(d, data.id)
		api.toast(ms, ok and ("Meilenstein: " .. res.text .. " (+" .. MiniLocale.Credits(res.credits) .. ")") or res)
	end)
end

return GoalsService
