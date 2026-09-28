-- LeaderboardService: globale Bestenliste für lebenslang gepressten Schrott (A4).
-- Schreiben: höchstens alle 120 s pro Spieler und beim Verlassen. Lesen: serverweiter Cache, höchstens alle 60 s.
-- Werte werden log-skaliert kodiert (PressRules.EncodeScore), damit auch Werte > 2^53 korrekt sortieren.
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PressRules = require(Shared:WaitForChild("PressRules"))
local DataUtil = require(script.Parent:WaitForChild("DataUtil"))
local Core = require(script.Parent:WaitForChild("Core"))

local LeaderboardService = {}

LeaderboardService.Store = nil
LeaderboardService.Cache = { available = nil, entries = {}, complete = false, fetchedAt = 0 }
LeaderboardService.Fetching = false
LeaderboardService.Names = {}
LeaderboardService.OnUpdated = nil -- function(cache), z. B. für die Tafel auf dem Hof
LeaderboardService.Reads = 0
LeaderboardService.Writes = 0

function LeaderboardService.Init()
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(Config.LeaderboardStoreName)
	end)
	if ok and store then
		LeaderboardService.Store = store
	else
		warn("[Leaderboard] OrderedDataStore nicht verfügbar: " .. tostring(store))
	end
end

local function keyFor(userId)
	return tostring(userId)
end

-- Schreibt den Wert eines Spielers, wenn er sich geändert hat und die Drosselung es erlaubt.
function LeaderboardService.Write(session, force)
	if not LeaderboardService.Store or not session.persistent then
		return false
	end
	local now = Core.Now()
	if not force and now - session.leaderboardWrittenAt < Config.LeaderboardWriteInterval then
		return false
	end
	local code = PressRules.EncodeScore(session.profile.games.press.lifetime)
	if code <= session.leaderboardWrittenCode then
		return false
	end
	session.leaderboardWrittenAt = now
	LeaderboardService.Writes += 1
	local ok, err = DataUtil.Retry(function()
		LeaderboardService.Store:SetAsync(keyFor(session.userId), code)
	end)
	if ok then
		session.leaderboardWrittenCode = code
	else
		warn("[Leaderboard] Schreiben fehlgeschlagen: " .. tostring(err))
	end
	return ok
end

local function nameFor(userId)
	local cached = LeaderboardService.Names[userId]
	if cached then
		return cached
	end
	local player = Players:GetPlayerByUserId(userId)
	if player then
		LeaderboardService.Names[userId] = player.DisplayName
		return player.DisplayName
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local result = (ok and type(name) == "string") and name or ("Spieler " .. tostring(userId))
	LeaderboardService.Names[userId] = result
	return result
end

-- Liest die Bestenliste neu, höchstens alle LeaderboardReadInterval Sekunden (serverweit).
function LeaderboardService.Refresh(force)
	local cache = LeaderboardService.Cache
	local now = Core.Now()
	if LeaderboardService.Fetching then
		return false
	end
	if not force and cache.fetchedAt > 0 and now - cache.fetchedAt < Config.LeaderboardReadInterval then
		return false
	end
	cache.fetchedAt = now
	if not LeaderboardService.Store then
		cache.available = false
		return false
	end
	LeaderboardService.Fetching = true
	LeaderboardService.Reads += 1
	local ok, result = DataUtil.Retry(function()
		local entries = {}
		local complete = false
		local pages = LeaderboardService.Store:GetSortedAsync(false, 100)
		for page = 1, Config.LeaderboardScanPages do
			for _, item in ipairs(pages:GetCurrentPage()) do
				local userId = tonumber(item.key)
				if userId and type(item.value) == "number" then
					table.insert(entries, { userId = userId, code = item.value })
				end
			end
			if pages.IsFinished then
				complete = true
				break
			end
			if page < Config.LeaderboardScanPages then
				pages:AdvanceToNextPageAsync()
			end
		end
		return { entries = entries, complete = complete }
	end)
	LeaderboardService.Fetching = false
	if ok then
		for i, e in ipairs(result.entries) do
			if i <= Config.LeaderboardTopCount then
				e.name = nameFor(e.userId)
			end
			e.value = PressRules.DecodeScore(e.code)
		end
		cache.entries = result.entries
		cache.complete = result.complete
		cache.available = true
	else
		warn("[Leaderboard] Lesen fehlgeschlagen: " .. tostring(result))
		cache.available = false
	end
	if LeaderboardService.OnUpdated then
		LeaderboardService.OnUpdated(cache)
	end
	return ok
end

-- Ansicht für einen Spieler: Top 50 und eigene Platzierung (auch außerhalb der Top 50).
function LeaderboardService.View(session)
	local cache = LeaderboardService.Cache
	if cache.available ~= true then
		return { available = cache.available == nil and "loading" or false }
	end
	local rows = {}
	for i = 1, math.min(Config.LeaderboardTopCount, #cache.entries) do
		local e = cache.entries[i]
		table.insert(rows, { rank = i, name = e.name or ("Spieler " .. e.userId), value = e.value, self = e.userId == session.userId })
	end
	-- Eigene Platzierung aus dem aktuellen Wert: Einträge mit höherem Wert zählen (ohne sich selbst)
	local ownValue = session.profile.games.press.lifetime
	local ownCode = PressRules.EncodeScore(ownValue)
	local higher = 0
	for _, e in ipairs(cache.entries) do
		if e.userId ~= session.userId and e.code > ownCode then
			higher += 1
		end
	end
	local own = { value = ownValue }
	if higher < #cache.entries or cache.complete then
		own.rank = higher + 1
	else
		own.rank = nil
		own.atLeast = #cache.entries + 1
	end
	return { available = true, rows = rows, own = own }
end

function LeaderboardService.Push(session)
	Core.Notify(session.player, "leaderboard", LeaderboardService.View(session))
end

function LeaderboardService.Register(Actions)
	Actions.Register("leaderboard_refresh", function(session)
		task.spawn(function()
			LeaderboardService.Write(session, false)
			LeaderboardService.Refresh(false)
			if Core.Get(session.player) then
				LeaderboardService.Push(session)
			end
		end)
	end)
end

return LeaderboardService
