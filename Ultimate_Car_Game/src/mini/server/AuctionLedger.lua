-- AuctionLedger: Auktionsbuch für Spieler-Auktionen (PHASE2_CONTRACT §6 Übergabe).
-- Eine Übergabe ändert zwei Profile (zwei DataStore-Schlüssel), die nicht gemeinsam geschrieben werden können.
-- Deshalb landet jede Übergabe nach dem Server-Schritt zusätzlich hier, bevor beide Profile gespeichert werden:
--   Schlüssel "U_<userId>" = { sold = { {tid, carId, model, bought, payout, at} }, bought = { {tid, car, amount, at} } }
-- Beim Laden eines Profils (GarageServer.join -> Mini.Reconcile) gleicht AuctionRules.ReconcileSeller/-Buyer ab:
--   * Verkäufer-Profil ohne die Übergabe gespeichert (Auto noch da): Auto entfernen, Auszahlung gutschreiben.
--   * Käufer-Profil ohne die Übergabe gespeichert (tid fehlt in received): Auto hinzufügen, Preis abziehen.
-- Beides ist idempotent (Auto-Id + Modell + Kaufzeit bzw. tid). Je Liste höchstens AuctionRules.MaxReceived Einträge.
-- Restrisiko: Absturz zwischen Übergabe im Speicher und Schreiben des Buchs, wenn in genau diesem Moment ein
-- Autosave eines der beiden Profile landet (Millisekunden; siehe PHASE2_CONTRACT §6).
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local Config = require(Shared:WaitForChild("Config"))
local AuctionRules = require(Shared:WaitForChild("Mini"):WaitForChild("AuctionRules"))

local AuctionLedger = {}
AuctionLedger.StoreName = "UCG_Auktionsbuch_v1"
AuctionLedger.Attempts = 3

local store, resolved = nil, false

local function getStore()
	if resolved then
		return store
	end
	resolved = true
	local enabled = Config.EnableSaving and (not RunService:IsStudio() or Config.SaveInStudio)
	if not enabled then
		return nil
	end
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore((RunService:IsStudio() and "Studio_" or "") .. AuctionLedger.StoreName)
	end)
	if ok then
		store = result
	end
	return store
end

function AuctionLedger.Available()
	return getStore() ~= nil
end

local function keyOf(userId)
	return "U_" .. tostring(math.floor(tonumber(userId) or 0))
end

local function append(list, entry)
	list = type(list) == "table" and list or {}
	for i = #list, 1, -1 do
		if type(list[i]) ~= "table" or list[i].tid == entry.tid then
			table.remove(list, i)
		end
	end
	table.insert(list, entry)
	while #list > AuctionRules.MaxReceived do
		table.remove(list, 1)
	end
	return list
end

local function update(userId, field, entry)
	local s = getStore()
	if not s then
		return false
	end
	for attempt = 1, AuctionLedger.Attempts do
		local ok = pcall(function()
			s:UpdateAsync(keyOf(userId), function(old)
				old = type(old) == "table" and old or {}
				return {
					sold = field == "sold" and append(old.sold, entry) or (type(old.sold) == "table" and old.sold or {}),
					bought = field == "bought" and append(old.bought, entry) or (type(old.bought) == "table" and old.bought or {}),
				}
			end)
		end)
		if ok then
			return true
		end
		if attempt < AuctionLedger.Attempts then
			task.wait(attempt * 0.5)
		end
	end
	return false
end

-- Übergabe eintragen (transfer aus AuctionRules.Handover). Darf warten. Rückgabe: true, wenn beide Seiten stehen.
function AuctionLedger.Record(transfer)
	if type(transfer) ~= "table" or not getStore() then
		return false
	end
	local okSeller = update(transfer.sellerId, "sold", transfer.seller)
	local okBuyer = update(transfer.buyerId, "bought", transfer.buyer)
	if not (okSeller and okBuyer) then
		warn("[Auktion] Auktionsbuch nicht vollständig geschrieben (tid " .. tostring(transfer.tid) .. ")")
	end
	return okSeller and okBuyer
end

-- Profil beim Laden abgleichen (d = frisch geladenes Profil). Darf warten. Rückgabe: Anzahl nachgeholter Übergaben
function AuctionLedger.Reconcile(userId, d)
	local s = getStore()
	if not s or type(d) ~= "table" or type(d.games) ~= "table" then
		return 0
	end
	local record
	for attempt = 1, AuctionLedger.Attempts do
		local ok, result = pcall(function()
			return s:GetAsync(keyOf(userId))
		end)
		if ok then
			record = result
			break
		end
		if attempt < AuctionLedger.Attempts then
			task.wait(attempt * 0.5)
		end
	end
	if type(record) ~= "table" then
		return 0
	end
	return AuctionRules.ReconcileSeller(d, record.sold) + AuctionRules.ReconcileBuyer(d, record.bought)
end

-- Tests: Store neu auflösen (nach geänderter Konfiguration)
function AuctionLedger.Reset()
	store, resolved = nil, false
end

return AuctionLedger
