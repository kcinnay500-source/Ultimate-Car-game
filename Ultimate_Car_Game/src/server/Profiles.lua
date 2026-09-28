-- Profiles: Laden und Speichern über den DataStore "UltimateCarGame_v2" mit Sitzungssperre.
-- Ohne DataStore-Zugriff (z. B. Studio ohne API-Freigabe) läuft das Spiel mit einem
-- nicht gespeicherten Sitzungsprofil weiter; ein solches Profil überschreibt nie echte Daten.
local DataStoreService = game:GetService("DataStoreService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("Rules"))
local DataUtil = require(script.Parent:WaitForChild("DataUtil"))
local Core = require(script.Parent:WaitForChild("Core"))

local Profiles = {}

Profiles.Store = nil
Profiles.Available = false
Profiles.JobId = "server"
Profiles.LockRetries = 5
Profiles.LockWait = 3

function Profiles.Init()
	Profiles.JobId = (game.JobId ~= nil and game.JobId ~= "") and game.JobId or ("studio-" .. tostring(math.floor(os.clock() * 1000)))
	local ok, store = pcall(function()
		return DataStoreService:GetDataStore(Config.ProfileStoreName)
	end)
	if ok and store then
		Profiles.Store = store
		Profiles.Available = true
	else
		warn("[Profiles] DataStore nicht verfügbar: " .. tostring(store))
		Profiles.Available = false
	end
end

function Profiles.Key(userId)
	return Config.ProfileKeyPrefix .. tostring(userId)
end

local function lockIsForeign(lock, now)
	return type(lock) == "table" and lock.job ~= Profiles.JobId and type(lock.t) == "number" and now - lock.t < Config.SessionLockTimeout and now >= lock.t
end

-- Rückgabe: profile, persistent, status ("ok" | "unavailable" | "locked")
function Profiles.Load(userId)
	if not Profiles.Available then
		return Rules.LoadData(nil), false, "unavailable"
	end
	local key = Profiles.Key(userId)
	for attempt = 1, Profiles.LockRetries do
		local lockedByOther = false
		local ok, result = DataUtil.Retry(function()
			return Profiles.Store:UpdateAsync(key, function(old)
				local now = Core.Now()
				local data = type(old) == "table" and old or {}
				if lockIsForeign(data._lock, now) then
					lockedByOther = true
					return nil
				end
				data._lock = { job = Profiles.JobId, t = now }
				return data
			end)
		end)
		if not ok then
			warn("[Profiles] Laden fehlgeschlagen: " .. tostring(result))
			return Rules.LoadData(nil), false, "unavailable"
		end
		if not lockedByOther then
			return Rules.LoadData(result), true, "ok"
		end
		if attempt < Profiles.LockRetries then
			DataUtil.Wait(Profiles.LockWait)
		end
	end
	return nil, false, "locked"
end

-- Speichert das Profil einer Sitzung. release = Sperre freigeben (beim Verlassen).
-- Speichervorgänge einer Sitzung laufen nacheinander; nach der Freigabe wird nie wieder gesperrt.
function Profiles.Save(session, release)
	if not session.persistent or not session.profile then
		return true
	end
	while session.saving do
		DataUtil.Wait(0.1)
	end
	if session.released then
		return true
	end
	session.saving = true
	local ok, result = pcall(Profiles.SaveNow, session, release)
	session.saving = false
	if release then
		session.released = true
	end
	return ok and result == true
end

function Profiles.SaveNow(session, release)
	local data = Rules.LoadData(DataUtil.DeepCopy(session.profile))
	if not Rules.IsClean(data) then
		warn("[Profiles] Profil enthält ungültige Zahlen, Speichern übersprungen")
		return false
	end
	local key = Profiles.Key(session.userId)
	local stolen = false
	local ok, err = DataUtil.Retry(function()
		return Profiles.Store:UpdateAsync(key, function(old)
			local now = Core.Now()
			if type(old) == "table" and lockIsForeign(old._lock, now) then
				stolen = true
				return nil
			end
			data._lock = (not release) and { job = Profiles.JobId, t = now } or nil
			return data
		end)
	end)
	if not ok then
		warn("[Profiles] Speichern fehlgeschlagen: " .. tostring(err))
		return false
	end
	if stolen then
		warn("[Profiles] Sperre gehört einer anderen Sitzung, nicht gespeichert")
		session.persistent = false
		return false
	end
	session.lastSave = Core.Now()
	return true
end

return Profiles
