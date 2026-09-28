-- WorkshopService: Werkstatt-Aufträge und Ausbau auf dem Server.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local WorkshopRules = require(Shared:WaitForChild("WorkshopRules"))
local Core = require(script.Parent:WaitForChild("Core"))

local WorkshopService = {}

function WorkshopService.OnJoin(session)
	WorkshopRules.RefreshOffers(session.profile, session.rng)
end

function WorkshopService.Register(Actions)
	Actions.Register("workshop_accept", function(session, data)
		local ok, res = WorkshopRules.Accept(session.profile, data.id, Core.Now(), session.rng)
		if ok then
			Core.Toast(session.player, res.name .. " läuft auf der Hebebühne.")
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("workshop_finish", function(session, data)
		local ok, res, xp = WorkshopRules.Finish(session.profile, data.id, Core.Now(), session.rng)
		if ok then
			Core.Toast(session.player, "Auftrag abgerechnet: +" .. Locale.Credits(res))
			Core.ReportXp(session, xp)
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("upgrade_buy", function(session, data)
		local ok, res, xp = WorkshopRules.BuyUpgrade(session.profile, data.key, data.level, Core.Now(), session.rng)
		if ok then
			Core.Toast(session.player, res.name .. " verbessert.")
			Core.ReportXp(session, xp)
		else
			Core.Toast(session.player, res)
		end
	end)
end

return WorkshopService
