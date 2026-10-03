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

-- B-019: Besitz nach einem Kaufereignis beim Server bestätigen. PromptGamePassPurchaseFinished(purchased = true)
-- allein ist kein Beleg (manipulierte Clients können das Signal auslösen). onOwned() läuft nur, wenn
-- UserOwnsGamePassAsync den Besitz bestätigt; wegen des Besitz-Caches bis zu ConfirmTries Versuche mit Pause.
-- Läuft in einem eigenen Task (blockiert den Ereignis-Handler nicht). Je Spieler und Pass höchstens eine laufende
-- Prüfung: weitere Ereignisse hängen sich an, statt neue Abfragen auszulösen (Budget).
MiniPasses.ConfirmTries = 3
MiniPasses.ConfirmWait = 2 -- Sekunden zwischen den Versuchen

local confirming = {} -- ["<userId>:<passId>"] = { onOwned, ... }

function MiniPasses.Confirm(userId, passId, onOwned)
	if type(userId) ~= "number" or type(passId) ~= "number" or passId <= 0 then
		return
	end
	local key = userId .. ":" .. passId
	if confirming[key] then
		table.insert(confirming[key], onOwned)
		return
	end
	confirming[key] = { onOwned }
	task.spawn(function()
		local owned = false
		for try = 1, MiniPasses.ConfirmTries do
			if owns(userId, passId) then
				owned = true
				break
			end
			if try < MiniPasses.ConfirmTries then
				task.wait(MiniPasses.ConfirmWait)
			end
		end
		local waiting = confirming[key]
		confirming[key] = nil
		if not owned then
			return
		end
		for _, fn in ipairs(waiting) do
			local ok, err = pcall(fn)
			if not ok then
				warn("[Game Passes] Gutschrift nach Kauf: " .. tostring(err))
			end
		end
	end)
end

-- Kann warten (UserOwnsGamePassAsync); ohne eingetragene IDs kehrt es sofort zurück.
function MiniPasses.Check(userId)
	local passes = { doubleScrap = false, pressPlus = false }
	for name, field in pairs(MiniPasses.Fields) do
		passes[field] = owns(userId, MiniConfig.GamePasses[name].id)
	end
	return passes
end

-- onPurchased(player, field) wird nach einem erfolgreichen Kauf in dieser Sitzung aufgerufen –
-- erst nachdem der Server den Besitz bestätigt hat (B-019, MiniPasses.Confirm).
function MiniPasses.Init(onPurchased)
	local ok, err = pcall(function()
		MarketplaceService.PromptGamePassPurchaseFinished:Connect(function(player, passId, purchased)
			if not purchased then
				return
			end
			for name, field in pairs(MiniPasses.Fields) do
				local id = MiniConfig.GamePasses[name].id
				if id > 0 and id == passId then
					MiniPasses.Confirm(player.UserId, id, function()
						onPurchased(player, field)
					end)
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
