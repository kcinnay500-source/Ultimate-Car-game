-- MiniPasses: Game Passes der Minispiele ("2× Schrott", "Schrottpresse+").
-- Nur UserOwnsGamePassAsync und PromptGamePassPurchaseFinished; MarketplaceService.ProcessReceipt gehört
-- allein 2.4.0 Purchases. Ohne eingetragene ID (0) startet kein Kauf. Game Passes wirken nur auf das
-- Schrott-Guthaben, nie auf den Bestenlistenwert und nie auf Geld.
local MarketplaceService = game:GetService("MarketplaceService")
local MiniShared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(MiniShared:WaitForChild("MiniConfig"))
local MiniLocale = require(MiniShared:WaitForChild("MiniLocale"))

local MiniPasses = {}

MiniPasses.Fields = {
	DoubleScrap = "doubleScrap",
	PressPlus = "pressPlus",
}

local function owns(userId, passId)
	if type(passId) ~= "number" or passId <= 0 then
		return false
	end
	local ok, result = pcall(function()
		return MarketplaceService:UserOwnsGamePassAsync(userId, passId)
	end)
	return ok and result == true
end

-- Kann warten (UserOwnsGamePassAsync); ohne eingetragene IDs kehrt es sofort zurück.
function MiniPasses.Check(userId)
	local passes = { doubleScrap = false, pressPlus = false }
	for name, field in pairs(MiniPasses.Fields) do
		passes[field] = owns(userId, MiniConfig.GamePasses[name].id)
	end
	return passes
end

-- onPurchased(player, field) wird nach einem erfolgreichen Kauf in dieser Sitzung aufgerufen.
function MiniPasses.Init(onPurchased)
	local ok, err = pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
			if not purchased then
				return
			end
			for name, field in pairs(MiniPasses.Fields) do
				local id = MiniConfig.GamePasses[name].id
				if id > 0 and id == passId then
					onPurchased(player, field)
				end
			end
		end)
	end)
	if not ok then
		warn("[Game Passes] Kaufereignis nicht verfügbar: " .. tostring(err))
	end
end

-- Rückgabe: ok, Hinweistext (oder nil)
function MiniPasses.Prompt(player, passName, passes)
	local def = MiniConfig.GamePasses[passName]
	local field = MiniPasses.Fields[passName]
	if not def or not field then
		return false, nil
	end
	if def.id <= 0 then
		return false, MiniLocale.T("pass_not_configured")
	end
	if passes and passes[field] then
		return false, MiniLocale.T("pass_owned")
	end
	local ok = pcall(function()
		MarketplaceService:PromptGamePassPurchase(player, def.id)
	end)
	return ok, nil
end

return MiniPasses
