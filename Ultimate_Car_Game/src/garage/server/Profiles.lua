-- Version 2 stores warehouse, deliveries, active jobs and the shared career.
local DataStoreService = game:GetService("DataStoreService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared")
local Config = require(Shared:WaitForChild("Config"))
local Rules = require(Shared:WaitForChild("Rules"))
local MiniRules = require(Shared:WaitForChild("Mini"):WaitForChild("MiniRules")) -- 3.0: Speicherschutz
local GameConfig = require(Shared:WaitForChild("Mini"):WaitForChild("GameConfig")) -- 3.0: Sperre beim Ortswechsel abwarten
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
    local lockTries = 0 -- 3.0: Sperre einer anderen Sitzung (Ortswechsel: der alte Server gibt sie gleich frei)
    local attempt = 0
    while attempt < 3 do
        attempt = attempt + 1
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
            -- 3.0: nach einem Teleport hält der alte Server die Sperre noch, bis sein PlayerRemoving gespeichert hat:
            -- warten und erneut versuchen, statt sofort eine temporäre Sitzung (alles Verdiente ginge verloren)
            lockTries = lockTries + 1
            if lockTries > GameConfig.ProfileLockRetries or not player.Parent then
                profile.status = "Andere Sitzung aktiv · temporär"
                return profile
            end
            attempt = attempt - 1 -- 3.0: Wartezeit auf die Sperre zählt nicht als Ladefehler
            profile.status = "Warte auf andere Sitzung …"
            task.wait(GameConfig.ProfileLockRetryWait)
        elseif attempt < 3 then task.wait(attempt) end
    end
    profile.status = "Laden fehlgeschlagen · temporär"
    return profile -- Never overwrite a profile that failed to load.
end

function Profiles.Save(profile, release)
    if not profile.writable or not store then return false end
    -- 3.0: Beim Verlassen auch auf eine offene Quittung warten (GrantReceipt schreibt gerade bzw. wiederholt),
    -- damit die Sitzungssperre danach freigegeben wird; ein Autosave wartet wie bisher nicht.
    if profile.saving or profile.receiptPending then
        if not release then return false end
        -- 3.0: Ein laufendes Speichern (z. B. ein langsamer Autosave) endet immer von selbst (höchstens 3 Versuche);
        -- 3.0: darauf wird ohne Frist gewartet, sonst bliebe sein älterer Stand der letzte und die Sperre hinge bis zum
        -- 3.0: Ablauf. Die 12-s-Frist gilt nur noch für eine offene Quittung, die niemand mehr auflöst.
        -- 3.0: (BindToClose begrenzt die Wartezeit selbst; nach einer verlorenen Sperre endet die Schleife über writable.)
        local deadline
        while (profile.saving or profile.receiptPending) and profile.writable do -- 3.0: auch auf eine offene Quittung warten
            if not profile.saving then
                deadline = deadline or os.clock() + 12
                if os.clock() >= deadline then break end
            end
            task.wait(0.1)
        end
        if profile.saving or profile.receiptPending then return false end
    end
    -- Another concurrent close/save may have released the lease while we waited.
    if not profile.writable or profile.receiptPending then return false end
    local snapshot = Rules.Snapshot(profile.data)
    -- 3.0: Nie NaN/inf oder nicht speicherbare Werte schreiben; dieser Speicherlauf fällt dann aus.
    if not MiniRules.IsClean(snapshot) then
        profile.status = "Speichern ausgesetzt · ungültige Werte"
        warn("[Profiles] Speichern abgelehnt: Profil enthält ungültige Werte")
        return false
    end
    profile.saving = true -- 3.0: erst nach der Prüfung oben gesetzt
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
-- 3.0: Allgemeine Quittungs-Gutschrift (PHASE4_CONTRACT §9): apply(snapshot) ändert eine Kopie des Profils
-- (Credits, DLC-Auto, Kosmetik); sie wird zusammen mit receipts[purchaseId] in EINEM UpdateAsync geschrieben.
-- Erst wenn beides zusammen gespeichert ist, gilt der Kauf; dann überträgt commit(profile.data, gespeicherteDaten)
-- die Änderung auf das lebende Profil (Standard: apply(profile.data) noch einmal – transacting hält alle anderen
-- Geld-/Auto-Änderungen so lange an). Rückgabe wie GrantCredits: granted, new.
--   apply(data: table) -> boolean   false = Kauf jetzt nicht anwendbar (Deckel, Garage voll): nichts geschrieben,
--                                    Roblox wiederholt den Beleg später (NotProcessedYet)
--   Dritter Rückgabewert "busy" (nur bei granted=false): ein anderes Speichern lief nach 10 s noch.
--   receiptPending = { id, snapshot, amount? } bleibt bis zur Auflösung (Save/Autosave warten; Purchases wiederholt).
function Profiles.GrantReceipt(profile,purchaseId,apply,commit)
    if not profile.writable or not store or type(purchaseId)~="string" or #purchaseId>160 or type(apply)~="function" then return false end
    if profile.receipts and profile.receipts[purchaseId] then return true,false end
    if profile.receiptPending and profile.receiptPending.id~=purchaseId then return false end
    local deadline=os.clock()+10
    while profile.saving and os.clock()<deadline do task.wait(0.1) end
    -- 3.0: Dritter Rückgabewert "busy": ein anderes Speichern läuft noch (langsamer DataStore). Nichts wurde
    -- 3.0: geschrieben und receiptPending ist nicht gesetzt – Purchases wiederholt die Quittung in der Sitzung.
    if profile.saving and profile.writable then return false,nil,"busy" end
    if profile.saving or not profile.writable then return false end
    if profile.receipts and profile.receipts[purchaseId] then return true,false end
    if not profile.receiptPending then
        local snapshot=Rules.Snapshot(profile.data)
        local okApply,applied=pcall(apply,snapshot) -- 3.0: GrantReceipt: apply auf dem Schnappschuss
        if not okApply then warn("[Profiles] Quittung "..purchaseId..": "..tostring(applied));return false end
        if applied~=true or not MiniRules.IsClean(snapshot) then return false end
        profile.receiptPending={id=purchaseId,snapshot=snapshot,amount=type(snapshot.money)=="number" and type(profile.data.money)=="number" and (snapshot.money-profile.data.money) or nil}
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
            profile.receipts=result.receipts -- 3.0: GrantReceipt
            -- Erst jetzt ins lebende Profil übernehmen (nie profile.data ersetzen: Dienste halten Verweise darauf)
            local okCommit,errCommit=pcall(commit or apply,profile.data,result.data)
            if not okCommit then warn("[Profiles] Quittung "..purchaseId.." übernehmen: "..tostring(errCommit)) end
            profile.receiptPending=nil;profile.transacting=false;profile.saving=false;profile.status="Gespeichert"
            return true,true
        end
        if lost then profile.writable=false;profile.status="Kaufbestätigung wartet auf erneuten Beitritt";break end
        if attempt<3 then task.wait(attempt) end
    end
    profile.saving=false;profile.status="Kaufbestätigung wird erneut versucht"
    return false
end

-- 3.0: dünne Hülle um GrantReceipt (gleiche Semantik wie 2.4.0: Deckel C.NumberCap, ganzzahliger Betrag,
-- nach dem Schreiben gilt der gespeicherte Kontostand).
function Profiles.GrantCredits(profile,purchaseId,amount)
    if type(amount)~="number" or amount<=0 or amount%1~=0 then return false end
    return Profiles.GrantReceipt(profile,purchaseId,function(snapshot)
        local balance=snapshot.money+amount
        if balance>Config.NumberCap or balance-snapshot.money~=amount then return false end
        snapshot.money=balance
        return true
    end,function(data,stored)
        data.money=stored.money
    end)
end

return Profiles
