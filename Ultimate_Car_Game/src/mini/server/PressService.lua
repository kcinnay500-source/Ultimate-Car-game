-- PressService: Schrottpresse auf dem Server (Klicks, Maschinen-Tick, Offline-Ertrag, Händler, Rebirth).
-- Erträge der Presse sind Schrott, nie Geld. Geld gibt es nur beim Händler (innerhalb von request()).
-- Freischaltung (PHASE4_CONTRACT §3, §12): die Presse gibt es ab feature:press (Level 2). Vorher produzieren die
-- Maschinen nicht (Tick und Offline), lastTick läuft mit; die Aktionen sperrt MiniService (ACTION_UNLOCK).
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(MiniShared:WaitForChild("MiniConfig"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))
local PressRules = require(MiniShared:WaitForChild("PressRules"))
local Unlocks = require(MiniShared:WaitForChild("Unlocks"))

local PressService = {}

function PressService.Unlocked(d): boolean
	return Unlocks.Has(d, "feature:press")
end

-- Klick-Budget: höchstens MaxClicksPerSecond je vergangener Sekunde, kleiner Puffer für gebündelte Pakete.
function PressService.AcceptClicks(ms, count, t)
	local cap = MiniConfig.MaxClicksPerSecond * MiniConfig.ClickBurstSeconds
	if ms.clickAt == 0 then
		ms.clickTokens = MiniConfig.MaxClicksPerSecond
	else
		local dt = math.max(0, t - ms.clickAt)
		ms.clickTokens = math.min(cap, ms.clickTokens + dt * MiniConfig.MaxClicksPerSecond)
	end
	ms.clickAt = t
	local wanted = math.floor(math.clamp(count, 0, 1000))
	local accepted = math.min(wanted, math.floor(ms.clickTokens))
	ms.clickTokens -= accepted
	return accepted
end

-- Beim Beitritt: Offline-Sekunden bestimmen und die Uhr der Presse auf jetzt setzen.
-- Der Ertrag selbst wird nach der Game-Pass-Prüfung mit ApplyOffline gutgeschrieben.
function PressService.OnJoin(ms, d, now)
	local seconds = PressRules.OfflineSeconds(d.games.press.lastTick, now)
	d.games.press.lastTick = now
	ms.lastTickAt = now
	return seconds
end

-- Rückgabe: Hinweis-Daten für mini_notice (kind "offline") oder nil
function PressService.ApplyOffline(ms, d, seconds, now)
	if not PressService.Unlocked(d) then
		return nil -- Presse noch gesperrt: keine Offline-Produktion
	end
	local gain = PressRules.Produce(d, seconds, now, ms.passes)
	if gain >= 1 then
		return { text = MiniLocale.T("offline_press", MiniLocale.Scrap(gain)), scrap = gain, seconds = seconds }
	end
	return nil
end

-- Maschinen produzieren ausschließlich hier (0,5-s-Tick von GarageServer, auch während transacting).
function PressService.Tick(ms, d, now)
	local dt = now - ms.lastTickAt
	ms.lastTickAt = now
	if dt > 0 and PressService.Unlocked(d) then
		PressRules.Produce(d, math.min(dt, MiniConfig.PressTickCapSeconds), now, ms.passes)
	end
	d.games.press.lastTick = now
end

-- Bestätigung eines Klickpakets (rid) für den Client: die letzten ClickAckCount rids stehen im Snapshot
-- (press.clickAcks). Auch Wiederholungen einer schon gezählten rid werden bestätigt.
local ACK_COUNT = 16
function PressService.Ack(ms, rid)
	if type(rid) ~= "number" then
		return
	end
	ms.clickAcks = ms.clickAcks or {}
	for _, r in ipairs(ms.clickAcks) do
		if r == rid then
			return
		end
	end
	table.insert(ms.clickAcks, rid)
	while #ms.clickAcks > ACK_COUNT do
		table.remove(ms.clickAcks, 1)
	end
end

function PressService.Register(Actions, api)
	Actions.Register("mini_press_click", function(ms, data, d, now)
		PressService.Ack(ms, data.rid)
		local accepted = PressService.AcceptClicks(ms, data.count, now)
		if accepted > 0 then
			PressRules.ApplyClicks(d, accepted, now, now, ms.passes)
		end
	end)

	Actions.Register("mini_press_buy", function(ms, data, d, now)
		local ok, res = PressRules.BuyUpgrade(d, data.id, data.level, now)
		if not ok then
			api.toast(ms, res)
		end
	end)

	-- Rückgabe true nur bei gelungenem Tausch (MiniService zählt dann "action:mini_press_exchange" für Nebenmissionen)
	Actions.Register("mini_press_exchange", function(ms, data, d)
		local ok, res = PressRules.Exchange(d, data.index)
		api.toast(ms, ok and ("Schrotthändler: +" .. MiniLocale.Credits(res)) or res)
		return ok == true
	end)

	Actions.Register("mini_press_rebirth", function(ms, data, d, now)
		local ok, res = PressRules.Rebirth(d, data.rebirths, now)
		if ok then
			api.notice(ms, "rebirth", { multiplier = res })
		else
			api.toast(ms, res)
		end
	end)
end

return PressService
