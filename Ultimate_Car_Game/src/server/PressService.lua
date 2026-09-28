-- PressService: Schrottpresse auf dem Server (Klicks, Maschinen-Tick, Offline-Ertrag, Händler, Rebirth).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))
local PressRules = require(Shared:WaitForChild("PressRules"))
local Core = require(script.Parent:WaitForChild("Core"))

local PressService = {}

-- Klick-Budget: höchstens MaxClicksPerSecond je vergangener Sekunde, kleiner Puffer für gebündelte Pakete.
function PressService.AcceptClicks(session, count, t)
	local cap = Config.MaxClicksPerSecond * Config.ClickBurstSeconds
	if session.clickAt == 0 then
		session.clickTokens = Config.MaxClicksPerSecond
	else
		local dt = math.max(0, t - session.clickAt)
		session.clickTokens = math.min(cap, session.clickTokens + dt * Config.MaxClicksPerSecond)
	end
	session.clickAt = t
	local wanted = math.floor(math.clamp(count, 0, 1000))
	local accepted = math.min(wanted, math.floor(session.clickTokens))
	session.clickTokens -= accepted
	return accepted
end

function PressService.OnJoin(session)
	local p = session.profile
	local now = Core.Now()
	local seconds = PressRules.OfflineSeconds(p.games.press.lastTick, now)
	local gain = PressRules.Produce(p, seconds, now, session.passes)
	p.games.press.lastTick = now
	session.lastTickPrecise = Core.Precise()
	if gain >= 1 then
		Core.Notify(session.player, "offline", { text = Locale.T("offline_press", Locale.Scrap(gain)), scrap = gain, seconds = seconds })
	end
end

-- Maschinen produzieren ausschließlich hier (Server-Tick).
function PressService.Tick(session, now)
	local t = Core.Precise()
	local dt = t - session.lastTickPrecise
	session.lastTickPrecise = t
	if dt > 0 then
		PressRules.Produce(session.profile, math.min(dt, 10), now, session.passes)
	end
	session.profile.games.press.lastTick = now
end

function PressService.Register(Actions)
	Actions.Register("press_click", function(session, data)
		local t = Core.Precise()
		local accepted = PressService.AcceptClicks(session, data.count, t)
		if accepted > 0 then
			PressRules.ApplyClicks(session.profile, accepted, t, Core.Now(), session.passes)
		end
	end)

	Actions.Register("press_buy", function(session, data)
		local ok, res = PressRules.BuyUpgrade(session.profile, data.id, data.level, Core.Now())
		if not ok then
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("press_exchange", function(session, data)
		local ok, res = PressRules.Exchange(session.profile, data.index)
		if ok then
			Core.Toast(session.player, "Schrotthändler: +" .. Locale.Credits(res))
		else
			Core.Toast(session.player, res)
		end
	end)

	Actions.Register("press_rebirth", function(session, data)
		local ok, res = PressRules.Rebirth(session.profile, data.rebirths)
		if ok then
			Core.Notify(session.player, "rebirth", { multiplier = res })
		else
			Core.Toast(session.player, res)
		end
	end)
end

return PressService
