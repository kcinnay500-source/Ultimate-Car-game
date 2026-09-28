-- Purchases: Game-Pass-Vorbereitung ("2× Schrott", "Schrottpresse+").
-- Ohne eingetragene ID (0) startet kein Kauf. Keine zufallsbasierten Bezahl-Belohnungen.
-- Game Passes wirken nur auf das Schrott-Guthaben, nie auf den Bestenlistenwert.
local MarketplaceService = game:GetService("MarketplaceService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))
local Core = require(script.Parent:WaitForChild("Core"))

local Purchases = {}

local PASS_FIELDS = {
	DoubleScrap = "doubleScrap",
	PressPlus = "pressPlus",
}

local function owns(userId, passId)
	if passId <= 0 then
		return false
	end
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	return ok and result == true
end

function Purchases.OnJoin(session)
	for name, field in pairs(PASS_FIELDS) do
		session.passes[field] = owns(session.userId, Config.GamePasses[name].id)
	end
end

function Purchases.Init()
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
		if not purchased then
			return
		end
		local session = Core.Get(player)
		if not session then
			return
		end
		for name, field in pairs(PASS_FIELDS) do
			local id = Config.GamePasses[name].id
			if id > 0 and id == passId then
				session.passes[field] = true
				Core.MarkDirty(session)
				Core.Toast(player, "Danke! Game Pass aktiv.")
			end
		end
	end)
end

function Purchases.Register(Actions)
	Actions.Register("pass_prompt", function(session, data)
		local def = Config.GamePasses[data.pass]
		if not def or not PASS_FIELDS[data.pass] then
			return
		end
		if def.id <= 0 then
			Core.Toast(session.player, Locale.T("pass_not_configured"))
			return
		end
		if session.passes[PASS_FIELDS[data.pass]] then
			Core.Toast(session.player, "Du besitzt diesen Game Pass bereits.")
			return
		end
		MarketplaceService:PromptGamePassPurchase(session.player, def.id)
	end)
end

return Purchases
