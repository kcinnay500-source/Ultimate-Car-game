-- Actions: nimmt Absichten vom Client an, prüft Budget, Form und Wiederholungen und ruft den Handler.
-- Der Client sendet nie Beträge, Preise, Ergebnisse oder Zeitstempel.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local Core = require(script.Parent:WaitForChild("Core"))

local Actions = {}
Actions.Handlers = {}

function Actions.Register(name, handler)
	assert(Net.Actions[name], "Aktion nicht in Net.Actions: " .. tostring(name))
	assert(Actions.Handlers[name] == nil, "Aktion doppelt registriert: " .. name)
	Actions.Handlers[name] = handler
end

-- Token-Bucket: true, wenn die Aktion ins Budget passt
local function takeToken(session)
	local t = Core.Precise()
	if session.actionAt == 0 then
		session.actionTokens = Config.ActionBurst
	else
		local dt = math.max(0, t - session.actionAt)
		session.actionTokens = math.min(Config.ActionBurst, session.actionTokens + dt * Config.ActionRate)
	end
	session.actionAt = t
	if session.actionTokens < 1 then
		return false
	end
	session.actionTokens -= 1
	return true
end

local function validPayload(name, payload)
	local schema = Net.Actions[name]
	if payload == nil then
		payload = {}
	end
	if type(payload) ~= "table" then
		return nil
	end
	local clean = {}
	for field, kind in pairs(schema) do
		local v = payload[field]
		if type(v) ~= kind then
			return nil
		end
		if kind == "number" and (v ~= v or v == math.huge or v == -math.huge) then
			return nil
		end
		if kind == "string" and #v > 64 then
			return nil
		end
		clean[field] = v
	end
	-- Anfrage-ID gegen Doppelausführung (optional, vom Client je Nutzeraktion erzeugt)
	local rid = payload.rid
	if type(rid) == "number" and rid == rid and rid ~= math.huge and rid ~= -math.huge then
		clean.rid = math.floor(rid)
	end
	return clean
end

local function seen(session, rid)
	if rid == nil then
		return false
	end
	if session.recent[rid] then
		return true
	end
	session.recent[rid] = true
	table.insert(session.recentOrder, rid)
	while #session.recentOrder > Config.RecentRequestIds do
		local old = table.remove(session.recentOrder, 1)
		session.recent[old] = nil
	end
	return false
end

-- Rückgabe (für Tests): "ok" | "dropped" | "invalid" | "duplicate" | "error"
function Actions.Handle(player, name, payload)
	local session = Core.Get(player)
	if not session then
		return "dropped"
	end
	if type(name) ~= "string" or not Actions.Handlers[name] then
		return "invalid"
	end
	if not takeToken(session) then
		return "dropped"
	end
	local clean = validPayload(name, payload)
	if not clean then
		return "invalid"
	end
	if seen(session, clean.rid) then
		return "duplicate"
	end
	local ok, err = pcall(Actions.Handlers[name], session, clean)
	if not ok then
		warn("[Actions] " .. name .. ": " .. tostring(err))
		return "error"
	end
	Core.MarkDirty(session)
	return "ok"
end

function Actions.Connect(remote)
	return remote.OnServerEvent:Connect(function(player, name, payload)
		Actions.Handle(player, name, payload)
	end)
end

return Actions
