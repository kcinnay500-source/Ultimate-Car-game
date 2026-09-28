-- TuningService: Idle Tuning Garage auf dem Server. Echtzeit über os.time(), läuft offline weiter.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))
local TuningRules = require(Shared:WaitForChild("TuningRules"))
local Core = require(script.Parent:WaitForChild("Core"))

local TuningService = {}

function TuningService.OnJoin(session)
	local tu = session.profile.games.tuning
	local now = Core.Now()
	-- Erstes Spiel oder Serveruhr in der Vergangenheit: Sammeln beginnt jetzt
	if tu.lastIdle <= 0 or tu.lastIdle > now then
		tu.lastIdle = now
	end
end

function TuningService.Register(Actions)
	Actions.Register("tuning_start", function(session, data)
		local ok, res = TuningRules.Start(session.profile, data.id, Core.Now())
		if ok then
			Core.Toast(session.player, "Tuning-Projekt gestartet (Platz " .. res .. ").")
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("tuning_collect", function(session, data)
		local ok, res, xp = TuningRules.Collect(session.profile, data.slot, Core.Now())
		if ok then
			Core.Toast(session.player, "Tuning abgeholt: +" .. Locale.Credits(res))
			Core.ReportXp(session, xp)
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("tuning_idle", function(session)
		local ok, res, xp = TuningRules.CollectIdle(session.profile, Core.Now())
		if ok then
			Core.Toast(session.player, "Passive Einnahmen: +" .. Locale.Credits(res))
			Core.ReportXp(session, xp)
		else
			Core.Toast(session.player, res)
		end
	end)
end

return TuningService
