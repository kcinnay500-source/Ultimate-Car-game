-- MiniRemote: sendet Minispiel-Absichten über den einen 2.4.0-Eingang (GarageShared.Remotes.Command).
-- Nutzlast flach (≤ 10 Schlüssel, nur string/number/boolean). Jede Nutzeraktion bekommt eine Anfrage-ID (`rid`),
-- damit Wiederholungen (Lag, Doppeltipp) auf dem Server nur einmal wirken. Der Client sendet nie Beträge,
-- Preise, Ergebnisse oder Zeitstempel (Serverautorität).
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MiniRemote = {}

local Command = ReplicatedStorage:WaitForChild("GarageShared"):WaitForChild("Remotes"):WaitForChild("Command")
MiniRemote.Command = Command

local nextRid = math.floor((os.clock() * 1000) % 1000000) * 1000

local function flat(payload)
	local out, count = {}, 0
	for k, v in pairs(payload or {}) do
		local t = type(v)
		if type(k) == "string" and (t == "string" or t == "number" or t == "boolean") and count < 9 then
			out[k] = v
			count += 1
		end
	end
	return out
end

-- Mit Anfrage-ID (Kaufen, Abholen, Antworten, Klickpakete …). Liefert die rid.
-- rid (optional): eine frühere ID erneut senden (Wiederholung, wirkt auf dem Server höchstens einmal).
function MiniRemote.Send(action, payload, rid)
	local data = flat(payload)
	if type(rid) ~= "number" then
		nextRid += 1
		rid = nextRid
	end
	data.rid = rid
	Command:FireServer(action, data)
	return rid
end

-- Ohne Anfrage-ID (z. B. Klickpakete, die der Server zählt und deckelt)
function MiniRemote.SendRaw(action, payload)
	Command:FireServer(action, flat(payload))
end

return MiniRemote
