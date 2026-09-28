-- Remote: sendet Absichten an den Server. Jede Nutzeraktion bekommt eine Anfrage-ID,
-- damit Wiederholungen (Lag, Doppeltipp) auf dem Server nur einmal wirken.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))

local Remote = {}

local folder = ReplicatedStorage:WaitForChild(Net.Folder)
Remote.Action = folder:WaitForChild(Net.Action)
Remote.Sync = folder:WaitForChild(Net.Sync)
Remote.Notice = folder:WaitForChild(Net.Notice)

local nextRid = math.floor((os.clock() * 1000) % 1000000) * 1000

function Remote.Send(action, payload)
	payload = payload or {}
	nextRid += 1
	payload.rid = nextRid
	Remote.Action:FireServer(action, payload)
end

-- Ohne Anfrage-ID (z. B. Klickpakete, die gezählt und gedeckelt werden)
function Remote.SendRaw(action, payload)
	Remote.Action:FireServer(action, payload or {})
end

return Remote
