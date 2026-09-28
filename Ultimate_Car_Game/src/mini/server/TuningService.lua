-- TuningService: Idle Tuning Garage auf dem Server. Echtzeit über die Serverzeit, läuft offline weiter.
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local TuningRules = require(MiniShared:WaitForChild("TuningRules"))

local TuningService = {}

function TuningService.OnJoin(ms, d, now)
	local tu = d.games.tuning
	-- Erstes Spiel oder Zeitstempel in der Zukunft: Sammeln beginnt jetzt
	if tu.lastIdle <= 0 or tu.lastIdle > now then
		tu.lastIdle = now
	end
end

function TuningService.Register(Actions, api)
	Actions.Register("mini_tuning_start", function(ms, data, d, now)
		local ok, res = TuningRules.Start(d, data.id, now)
		api.toast(ms, ok and ("Tuning-Projekt gestartet (Platz " .. res .. ").") or res)
	end)

	Actions.Register("mini_tuning_collect", function(ms, data, d, now)
		local ok, res = TuningRules.Collect(d, data.slot, now)
		if ok then
			api.toast(ms, "Tuning abgeholt: +" .. MiniLocale.Credits(res))
		else
			api.toast(ms, res)
		end
	end)

	Actions.Register("mini_tuning_idle", function(ms, _, d, now)
		local ok, res = TuningRules.CollectIdle(d, now)
		api.toast(ms, ok and ("Passive Einnahmen: +" .. MiniLocale.Credits(res)) or res)
	end)
end

return TuningService
