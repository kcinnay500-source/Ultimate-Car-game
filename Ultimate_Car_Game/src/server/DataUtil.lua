-- DataUtil: pcall mit Wiederholung und Tiefenkopie.
local Config = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Config"))

local DataUtil = {}

DataUtil.Wait = function(seconds)
	task.wait(seconds)
end

-- Führt fn bis zu attempts-mal aus. Rückgabe: ok, Ergebnis oder letzter Fehler
function DataUtil.Retry(fn, attempts)
	attempts = attempts or Config.DataStoreRetries
	local lastErr
	for i = 1, attempts do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if i < attempts then
			DataUtil.Wait(i)
		end
	end
	return false, lastErr
end

function DataUtil.DeepCopy(v, depth)
	depth = depth or 0
	if type(v) ~= "table" or depth > 30 then
		return v
	end
	local out = {}
	for k, x in pairs(v) do
		out[DataUtil.DeepCopy(k, depth + 1)] = DataUtil.DeepCopy(x, depth + 1)
	end
	return out
end

return DataUtil
