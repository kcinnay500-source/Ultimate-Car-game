-- LeaderboardService: globale Bestenliste für lebenslang gepressten Schrott (eigener OrderedDataStore).
-- Schreiben nur, wenn das Profil beschreibbar ist (profile.writable bzw. beim Verlassen der Wert davor),
-- in Studio nie; höchstens alle 120 s pro Spieler und beim Verlassen. Lesen: serverweiter Cache,
-- höchstens alle 60 s. Werte werden log-skaliert kodiert (PressRules.EncodeScore).
local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(MiniShared:WaitForChild("MiniConfig"))
local PressRules = require(MiniShared:WaitForChild("PressRules"))

local LeaderboardService = {}

LeaderboardService.Store = nil
LeaderboardService.Cache = { available = nil, entries = {}, complete = false, fetchedAt = 0 }
LeaderboardService.Fetching = false
LeaderboardService.Names = {}
LeaderboardService.OnUpdated = nil -- function(cache)
LeaderboardService.Reads = 0
LeaderboardService.Writes = 0
LeaderboardService.Pending = 0 -- laufende Schreibvorgänge (BindToClose wartet darauf)
LeaderboardService.Now = function()
	return os.time()
end

local function retry(fn)
	local lastErr
	for i = 1, MiniConfig.DataStoreRetries do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		lastErr = result
		if i < MiniConfig.DataStoreRetries then
			task.wait(i)
		end
	end
	return false, lastErr
end

function LeaderboardService.Init(nowFn)
	if nowFn then
		LeaderboardService.Now = nowFn
	end
	local ok, store = pcall(function()
		return DataStoreService:GetOrderedDataStore(MiniConfig.LeaderboardStoreName)
	end)
	if ok and store then
		LeaderboardService.Store = store
	else
		warn("[Bestenliste] OrderedDataStore nicht verfügbar: " .. tostring(store))
	end
end

function LeaderboardService.CanWrite(writable)
	return writable == true and LeaderboardService.Store ~= nil and not RunService:IsStudio()
end

local function lifetime(ms)
	local d = ms.p and ms.p.profile and ms.p.profile.data
	local games = d and d.games
	return games and games.press.lifetime or 0
end

function LeaderboardService.WriteDue(ms, now)
	return now - ms.leaderboardWrittenAt >= MiniConfig.LeaderboardWriteInterval
		and PressRules.EncodeScore(lifetime(ms)) > ms.leaderboardWrittenCode
end

-- Schreibt den Wert eines Spielers, wenn er sich geändert hat und die Drosselung es erlaubt.
function LeaderboardService.Write(ms, force, writable)
	if not LeaderboardService.CanWrite(writable) then
		return false
	end
	local now = LeaderboardService.Now()
	if not force and now - ms.leaderboardWrittenAt < MiniConfig.LeaderboardWriteInterval then
		return false
	end
	local code = PressRules.EncodeScore(lifetime(ms))
	if code <= ms.leaderboardWrittenCode then
		return false
	end
	ms.leaderboardWrittenAt = now
	LeaderboardService.Writes += 1
	LeaderboardService.Pending += 1
	local ok, err = retry(function()
		LeaderboardService.Store:SetAsync(tostring(ms.userId), code)
	end)
	LeaderboardService.Pending -= 1
	if ok then
		ms.leaderboardWrittenCode = math.max(ms.leaderboardWrittenCode, code)
	else
		warn("[Bestenliste] Schreiben fehlgeschlagen: " .. tostring(err))
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

function LeaderboardService.RefreshDue(now)
	local cache = LeaderboardService.Cache
	return not LeaderboardService.Fetching and (cache.fetchedAt <= 0 or now - cache.fetchedAt >= MiniConfig.LeaderboardReadInterval)
end

-- Liest die Bestenliste neu, höchstens alle LeaderboardReadInterval Sekunden (serverweit).
function LeaderboardService.Refresh(force)
	local cache = LeaderboardService.Cache
	local now = LeaderboardService.Now()
	if LeaderboardService.Fetching then
		return false
	end
	if not force and cache.fetchedAt > 0 and now - cache.fetchedAt < MiniConfig.LeaderboardReadInterval then
		return false
	end
	cache.fetchedAt = now
	if not LeaderboardService.Store then
		cache.available = false
		if LeaderboardService.OnUpdated then
			LeaderboardService.OnUpdated(cache)
		end
		return false
	end
	LeaderboardService.Fetching = true
	LeaderboardService.Reads += 1
	local ok, result = retry(function()
		local entries = {}
		local complete = false
		local pages = LeaderboardService.Store:GetSortedAsync(false, 100)
		for page = 1, MiniConfig.LeaderboardScanPages do
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
			if page < MiniConfig.LeaderboardScanPages then
				pages:AdvanceToNextPageAsync()
			end
		end
		return { entries = entries, complete = complete }
	end)
	if ok then
		for i, e in ipairs(result.entries) do
			if i <= MiniConfig.LeaderboardTopCount then
				e.name = nameFor(e.userId)
			end
			e.value = PressRules.DecodeScore(e.code)
		end
		cache.entries = result.entries
		cache.complete = result.complete
		cache.available = true
	else
		warn("[Bestenliste] Lesen fehlgeschlagen: " .. tostring(result))
		cache.available = false
	end
	LeaderboardService.Fetching = false
	if LeaderboardService.OnUpdated then
		LeaderboardService.OnUpdated(cache)
	end
	return ok
end

-- Ansicht für einen Spieler: Top 50 und eigene Platzierung (auch außerhalb der Top 50).
-- available: true | false | "loading"
function LeaderboardService.View(ms)
	local cache = LeaderboardService.Cache
	if cache.available ~= true then
		return { available = cache.available == nil and "loading" or false }
	end
	local rows = {}
	for i = 1, math.min(MiniConfig.LeaderboardTopCount, #cache.entries) do
		local e = cache.entries[i]
		table.insert(rows, { rank = i, name = e.name or ("Spieler " .. e.userId), value = e.value, self = e.userId == ms.userId })
	end
	local ownValue = lifetime(ms)
	local ownCode = PressRules.EncodeScore(ownValue)
	local higher = 0
	for _, e in ipairs(cache.entries) do
		if e.userId ~= ms.userId and e.code > ownCode then
			higher += 1
		end
	end
	local own = { value = ownValue }
	if higher < #cache.entries or cache.complete then
		own.rank = higher + 1
	else
		own.atLeast = #cache.entries + 1
	end
	return { available = true, rows = rows, own = own }
end

function LeaderboardService.Register(Actions, api)
	Actions.Register("mini_leaderboard_refresh", function(ms)
		task.spawn(function()
			LeaderboardService.Write(ms, false, api.writable(ms))
			LeaderboardService.Refresh(false)
			if api.alive(ms) then
				api.notice(ms, "leaderboard", LeaderboardService.View(ms))
			end
		end)
	end)
end

return LeaderboardService
