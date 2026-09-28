-- Version 2 stores warehouse, deliveries, active jobs and the shared career.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("Rules"))
local Profiles = {}
local store
local enabled = Config.EnableSaving and (not RunService:IsStudio() or Config.SaveInStudio)
if enabled then
    local ok, result = pcall(function()
        return DataStoreService:GetDataStore(RunService:IsStudio() and Config.StudioDataStoreName or Config.DataStoreName)
    end)
    if ok then store = result end
end

function Profiles.Load(player)
    local profile = {data = Rules.LoadData(nil, Config), writable = false, saving = false, status = "Nur diese Sitzung"}
    if not enabled then return profile end
    if not store then profile.status = "Speicher nicht erreichbar"; return profile end
    profile.key = "Player_" .. player.UserId
    profile.token = HttpService:GenerateGUID(false)
    for attempt = 1, 3 do
        local blocked = false
        local ok, result = pcall(function()
            return store:UpdateAsync(profile.key, function(old)
                old = type(old) == "table" and old or {}
                local lock = type(old.lock) == "table" and old.lock or {}
                if type(lock.expires) == "number" and lock.expires > os.time() and lock.token ~= profile.token then
                    blocked = true
                    return nil
                end
                blocked = false
                local data = Rules.LoadData(old.data, Config)
                return {version = 2, data = data, receipts=type(old.receipts)=="table" and old.receipts or {}, lock = {token = profile.token, expires = os.time() + Config.LeaseSeconds}}
            end)
        end)
        if ok and result and not blocked then
            profile.receipts = result.receipts or {}
            profile.data = result.data
            profile.writable = true
            profile.status = "Speicherung aktiv"
            return profile
        end
        if blocked then
            profile.status = "Andere Sitzung aktiv · temporär"
            return profile
        end
        if attempt < 3 then task.wait(attempt) end
    end
    profile.status = "Laden fehlgeschlagen · temporär"
    return profile -- Never overwrite a profile that failed to load.
end

function Profiles.Save(profile, release)
    if not profile.writable or not store or profile.receiptPending then return false end
    if profile.saving then
        if not release then return false end
        local deadline = os.clock() + 12
        while profile.saving and os.clock() < deadline do task.wait(0.1) end
        if profile.saving then return false end
    end
    -- Another concurrent close/save may have released the lease while we waited.
    if not profile.writable or profile.receiptPending then return false end
    profile.saving = true
    local snapshot = Rules.Snapshot(profile.data)
    local success = false
    for attempt = 1, 3 do
        local lostLock = false
        local ok, result = pcall(function()
            return store:UpdateAsync(profile.key, function(old)
                if type(old) ~= "table" or type(old.lock) ~= "table" or old.lock.token ~= profile.token then
                    lostLock = true
                    return nil
                end
                local lock
                if not release then lock = {token = profile.token, expires = os.time() + Config.LeaseSeconds} end
                return {version = 2, data = snapshot, receipts=old.receipts or {}, lock = lock}
            end)
        end)
        if ok and result and not lostLock then success = true; break end
        if lostLock then
            profile.writable = false
            profile.status = "Sitzung abgelaufen · temporär"
            break
        end
        if attempt < 3 then task.wait(attempt) end
    end
    profile.saving = false
    if success then
        profile.status = "Gespeichert"
        if release then profile.writable = false end
    elseif profile.writable then
        profile.status = "Speichern wartet auf Verbindung"
    end
    return success
end

-- Credit and receipt marker commit together under the profile lease. An uncertain write
-- keeps economy mutations/saves locked until the same immutable transaction is resolved.
function Profiles.GrantCredits(profile,purchaseId,amount)
    if not profile.writable or not store or type(purchaseId)~="string" or #purchaseId>160 or type(amount)~="number" or amount<=0 or amount%1~=0 then return false end
    if profile.receipts and profile.receipts[purchaseId] then return true,false end
    if profile.receiptPending and profile.receiptPending.id~=purchaseId then return false end
    local deadline=os.clock()+10
    while profile.saving and os.clock()<deadline do task.wait(0.1) end
    if profile.saving or not profile.writable then return false end
    if profile.receipts and profile.receipts[purchaseId] then return true,false end
    if not profile.receiptPending then
        local snapshot=Rules.Snapshot(profile.data)
        local balance=snapshot.money+amount
        if balance>Config.NumberCap or balance-snapshot.money~=amount then return false end
        snapshot.money=balance
        profile.receiptPending={id=purchaseId,amount=amount,snapshot=snapshot}
    end
    local pending=profile.receiptPending
    profile.saving=true;profile.transacting=true
    for attempt=1,3 do
        local lost=false
        local ok,result=pcall(function()
            return store:UpdateAsync(profile.key,function(old)
                if type(old)~="table" or type(old.lock)~="table" or old.lock.token~=profile.token then lost=true;return nil end
                local receipts=type(old.receipts)=="table" and Rules.Snapshot(old.receipts) or {}
                if receipts[purchaseId] then return old end
                receipts[purchaseId]=true
                return {version=2,data=pending.snapshot,receipts=receipts,lock={token=profile.token,expires=os.time()+Config.LeaseSeconds}}
            end)
        end)
        if ok and result and not lost and result.receipts and result.receipts[purchaseId] then
            profile.data.money=result.data.money;profile.receipts=result.receipts
            profile.receiptPending=nil;profile.transacting=false;profile.saving=false;profile.status="Gespeichert"
            return true,true
        end
        if lost then profile.writable=false;profile.status="Kaufbestätigung wartet auf erneuten Beitritt";break end
        if attempt<3 then task.wait(attempt) end
    end
    profile.saving=false;profile.status="Kaufbestätigung wird erneut versucht"
    return false
end

return Profiles
