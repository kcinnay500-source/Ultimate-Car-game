-- SideGamesService: Schrottplatz, Mechaniker-Quiz und Parkplatz-Chaos auf dem Server.
-- Schrottplatz-Funde: gewöhnliche Funde sind Altteile (d.games.parts), ein seltener Fund ist ein
-- echtes gebrauchtes Ersatzteil für das 2.4.0-Lager (d.inventory). Begründung in SideGameRules.
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local SideGameRules = require(MiniShared:WaitForChild("SideGameRules"))

local SideGamesService = {}

function SideGamesService.Register(Actions, api)
	Actions.Register("mini_scrapyard_buy", function(ms, _, d)
		local ok, res = SideGameRules.BuyVehicle(d)
		api.toast(ms, ok and "Fahrzeug gekauft. Jetzt zerlegen!" or res)
	end)

	Actions.Register("mini_scrapyard_dismantle", function(ms, _, d, now)
		local ok, res = SideGameRules.Dismantle(d, ms.rng, now)
		if not ok then
			api.toast(ms, res)
			return
		end
		if res.rareSku then
			api.worldChanged(ms) -- Lager der Werkstatt hat sich geändert
		end
		api.notice(ms, "scrapyard", {
			parts = res.parts, rare = res.rare, rarePart = res.rarePart, rareSku = res.rareSku,
			credits = res.credits, scrap = res.scrap,
		})
	end)

	Actions.Register("mini_scrapyard_sell", function(ms, _, d)
		local ok, res = SideGameRules.SellParts(d)
		api.toast(ms, ok and ("Altteile verkauft: +" .. MiniLocale.Credits(res)) or res)
	end)

	Actions.Register("mini_quiz_new", function(ms, _, _, now)
		SideGameRules.NewQuestion(ms.quiz, ms.rng, now)
	end)

	Actions.Register("mini_quiz_answer", function(ms, data, d, now)
		local ok, res = SideGameRules.Answer(d, ms.quiz, data.token, data.choice, now)
		if ok then
			api.notice(ms, "quiz", { correct = res.correct, correctPos = res.correctPos, choice = data.choice, credits = res.credits })
		end
	end)

	Actions.Register("mini_parking_new", function(ms, _, d)
		SideGameRules.NewPuzzle(d, ms.rng)
	end)

	Actions.Register("mini_parking_tap", function(ms, data, d, now)
		local ok, res = SideGameRules.Tap(d, data.cell, now)
		if ok then
			if res.crashed then
				api.toast(ms, "Blechschaden! Der Weg war blockiert. Serie beendet.")
			elseif res.solved then
				api.toast(ms, "Parkplatz frei! +" .. MiniLocale.Credits(res.credits))
			end
		end
	end)
end

return SideGamesService
