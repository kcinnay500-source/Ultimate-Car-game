-- GoalsService: Tagesauftrag, Tagesziele und Meilensteine auf dem Server.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local GoalRules = require(Shared:WaitForChild("GoalRules"))
local Core = require(script.Parent:WaitForChild("Core"))

local GoalsService = {}

function GoalsService.Tick(session, now)
	GoalRules.EnsureDay(session.profile, now)
end

function GoalsService.Register(Actions)
	Actions.Register("daily_claim", function(session)
		local ok, res = GoalRules.ClaimDaily(session.profile, Core.Now())
		if ok then
			Core.Toast(session.player, "Tagesauftrag erledigt! Belohnung erhalten.")
			Core.ReportXp(session, res)
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("daily_goal_claim", function(session, data)
		local ok, res = GoalRules.ClaimDailyGoal(session.profile, data.id, Core.Now())
		if ok then
			Core.Toast(session.player, "Tagesziel erledigt: +" .. Locale.Credits(res.credits))
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("milestone_claim", function(session, data)
		local ok, res, xp = GoalRules.ClaimMilestone(session.profile, data.id)
		if ok then
			Core.Toast(session.player, "Meilenstein: " .. res.text .. " (+" .. Locale.Credits(res.credits) .. ")")
			Core.ReportXp(session, xp)
		else
			Core.Toast(session.player, res)
		end
	end)
end

return GoalsService
