-- Core: gemeinsame Server-Infrastruktur (Sitzungen, Uhr, Hinweise, Sync-Markierung).
-- Jede Sitzung gehört genau einem Spieler; kein Handler greift auf fremde Sitzungen zu.
local Core = {}

Core.Sessions = {} -- [Player] = Session
Core.Remotes = nil -- { Action, Sync, Notice }
Core.PendingSaves = 0 -- laufende Speichervorgänge beim Verlassen/Herunterfahren
local lockCounter = 0

-- Uhr (in Tests ersetzbar)
function Core.Now()
	return os.time()
end

function Core.Precise()
	return os.clock()
end

function Core.NewRandom()
	return Random.new()
end

function Core.NewSession(player)
	lockCounter += 1
	local session = {
		player = player,
		userId = player.UserId,
		-- eindeutig pro Sitzung: ein schneller Wiederbeitritt auf demselben Server wartet so auf das Speichern der alten Sitzung
		lockId = tostring(game.JobId) .. ":" .. tostring(player.UserId) .. ":" .. tostring(lockCounter) .. ":" .. tostring(math.floor(os.clock() * 1000)),
		profile = nil,
		loaded = false,
		persistent = false,
		closing = false,
		passes = { doubleScrap = false, pressPlus = false },
		rng = Core.NewRandom(),
		-- Remote-Budget (Token-Bucket)
		actionTokens = 0,
		actionAt = 0,
		-- Klick-Budget
		clickTokens = 0,
		clickAt = 0,
		recent = {}, -- zuletzt verarbeitete Anfrage-IDs
		recentOrder = {},
		dirty = true,
		lastTickPrecise = 0,
		lastSave = 0,
		leaderboardWrittenAt = 0,
		leaderboardWrittenCode = -1,
		connections = {},
	}
	Core.Sessions[player] = session
	return session
end

function Core.Get(player)
	local s = Core.Sessions[player]
	if s and s.loaded and not s.closing then
		return s
	end
	return nil
end

function Core.Remove(player)
	local s = Core.Sessions[player]
	if not s then
		return
	end
	for _, c in ipairs(s.connections) do
		if typeof(c) == "RBXScriptConnection" then
			c:Disconnect()
		elseif typeof(c) == "thread" then
			pcall(task.cancel, c)
		end
	end
	s.connections = {}
	Core.Sessions[player] = nil
end

function Core.MarkDirty(session)
	session.dirty = true
end

-- Hinweis an genau einen Spieler
function Core.Notify(player, kind, data)
	if Core.Remotes and player.Parent ~= nil then
		Core.Remotes.Notice:FireClient(player, kind, data)
	end
end

function Core.Toast(player, text)
	if text then
		Core.Notify(player, "toast", { text = text })
	end
end

-- Level-Aufstieg melden (xp = Ergebnis von Rules.GainXP)
function Core.ReportXp(session, xp)
	if xp and xp.levels and xp.levels > 0 then
		Core.Notify(session.player, "levelup", { level = session.profile.level, credits = xp.credits })
	end
end

return Core
