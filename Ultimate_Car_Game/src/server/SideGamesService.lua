-- SideGamesService: Schrottplatz, Mechaniker-Quiz und Parkplatz-Chaos auf dem Server.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local SideGameRules = require(Shared:WaitForChild("SideGameRules"))
local Core = require(script.Parent:WaitForChild("Core"))

local SideGamesService = {}

function SideGamesService.Register(Actions)
	Actions.Register("scrapyard_buy", function(session)
		local ok, res = SideGameRules.BuyVehicle(session.profile)
		Core.Toast(session.player, ok and "Fahrzeug gekauft. Jetzt zerlegen!" or res)
	end)

	Actions.Register("scrapyard_dismantle", function(session)
		local ok, res = SideGameRules.Dismantle(session.profile, session.rng, Core.Now())
		if ok then
			Core.Notify(session.player, "scrapyard", res)
			Core.ReportXp(session, res.xp)
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("scrapyard_sell", function(session)
		local ok, res, xp = SideGameRules.SellParts(session.profile)
		if ok then
			Core.Toast(session.player, "Teile verkauft: +" .. Locale.Credits(res))
			Core.ReportXp(session, xp)
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("quiz_new", function(session)
		SideGameRules.NewQuestion(session.profile, session.rng, Core.Precise())
	end)

	Actions.Register("quiz_answer", function(session, data)
		local ok, res = SideGameRules.Answer(session.profile, data.token, data.choice, Core.Now())
		if ok then
			Core.Notify(session.player, "quiz", { correct = res.correct, correctPos = res.correctPos, choice = data.choice, credits = res.credits })
			Core.ReportXp(session, res.xp)
		end
	end)

	Actions.Register("parking_new", function(session)
		SideGameRules.NewPuzzle(session.profile, session.rng)
	end)

	Actions.Register("parking_tap", function(session, data)
		local ok, res = SideGameRules.Tap(session.profile, data.cell, Core.Now())
		if ok then
			if res.crashed then
				Core.Toast(session.player, "Blechschaden! Der Weg war blockiert. Serie beendet.")
			elseif res.solved then
				Core.Toast(session.player, "Parkplatz frei! +" .. Locale.Credits(res.credits))
				Core.ReportXp(session, res.xp)
			end
		end
	end)
end

return SideGamesService
