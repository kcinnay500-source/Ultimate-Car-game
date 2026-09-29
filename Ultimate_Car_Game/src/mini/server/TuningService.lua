-- TuningService: Idle Tuning Garage auf dem Server. Echtzeit über die Serverzeit, läuft offline weiter.
-- Freischaltung (PHASE4_CONTRACT §3, §12): Tuning-Projekte gibt es ab feature:tuning (Level 6). Vorher sammeln sich
-- keine passiven Einnahmen an (die Uhr lastIdle bleibt auf jetzt), die Aktionen sperrt MiniService (ACTION_UNLOCK).
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local TuningRules = require(MiniShared:WaitForChild("TuningRules"))
local Unlocks = require(MiniShared:WaitForChild("Unlocks"))

local TuningService = {}

function TuningService.Unlocked(d): boolean
	return Unlocks.Has(d, "feature:tuning")
end

function TuningService.OnJoin(ms, d, now)
	local tu = d.games.tuning
	-- Erstes Spiel, Zeitstempel in der Zukunft oder Tuning noch gesperrt: Sammeln beginnt (frühestens) jetzt
	if tu.lastIdle <= 0 or tu.lastIdle > now or not TuningService.Unlocked(d) then
		tu.lastIdle = now
	end
end

-- 0,5-s-Tick: ohne Freischaltung läuft die Uhr der passiven Einnahmen mit (nichts wird angespart)
function TuningService.Tick(ms, d, now)
	local tu = d.games and d.games.tuning
	if type(tu) ~= "table" then
		return
	end
	if not TuningService.Unlocked(d) then
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
