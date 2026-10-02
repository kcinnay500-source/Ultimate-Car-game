local Marketplace=game:GetService("MarketplaceService")
local Players=game:GetService("Players")
local C=require(game:GetService("ReplicatedStorage").GarageShared.Config)
local Profiles=require(script.Parent.Profiles)
local Purchases={}
-- 3.0: Shop-Produkte (DLC-Autos, Kosmetik, Bündel) aus GameConfig.Shop.Products (PHASE4_CONTRACT §9). Die Module
-- werden erst bei Bedarf geladen (ohne Minispiel-Ordner, z. B. im reinen 2.4.0-Test, bleibt alles wie 2.4.0).
local shopLoaded,ShopRules,ShopConfig=false,nil,nil
local function shop()
    if shopLoaded then return ShopRules,ShopConfig end
    shopLoaded=true
    local mini=game:GetService("ReplicatedStorage").GarageShared:FindFirstChild("Mini")
    local rulesInst=mini and mini:FindFirstChild("ShopRules")
    local configInst=mini and mini:FindFirstChild("GameConfig")
    if rulesInst and configInst then
        local ok,rules=pcall(require,rulesInst)
        local okC,config=pcall(require,configInst)
        if ok and okC and type(rules)=="table" and type(config)=="table" and type(config.Shop)=="table" then ShopRules=rules;ShopConfig=config.Shop end
        if not ok then warn("[Purchases] ShopRules: "..tostring(rules)) end
    end
    return ShopRules,ShopConfig
end
-- 3.0: Alle Developer Products (Credits-Pakete aus C.CreditProducts, Shop-Produkte mit productId > 0).
-- Credits-Pakete tragen kind="credits"; Shop-Produkte kommen unverändert aus GameConfig.Shop.Products.
local function allProducts()
    local list={}
    for _,p in ipairs(C.CreditProducts) do table.insert(list,p) end
    local rules,config=shop()
    if rules and config then
        for _,p in ipairs(config.Products or {}) do
            if p.kind~="credits" then table.insert(list,p) end -- Credits-Pakete zeigen auf C.CreditProducts (pack)
        end
    end
    return list
end
local function idOf(p)
    local rules=shop()
    if p.kind and p.kind~="credits" and rules then return rules.ProductId(p) end
    return type(p.productId)=="number" and p.productId or 0
end
function Purchases.ByProduct(id)
    if type(id)~="number" or id<=0 then return nil end
    local found
    for _,p in ipairs(allProducts()) do -- 3.0: beide Listen (C.CreditProducts + GameConfig.Shop.Products)
        if idOf(p)==id then if found then return nil end;found=p end
    end
    return found
end
-- 3.0: Produkt-Ids müssen über beide Listen eindeutig sein (Platzhalter 0 zählen nicht). Rückgabe: Liste der Dubletten.
function Purchases.Validate()
    local seen,dupes={},{}
    for _,p in ipairs(allProducts()) do -- 3.0: beide Listen (C.CreditProducts + GameConfig.Shop.Products)
        local id=idOf(p)
        if id>0 then
            if seen[id] then table.insert(dupes,id);warn("[Purchases] Produkt-Id "..id.." doppelt: "..tostring(seen[id].key).." und "..tostring(p.key).." (beide bleiben ohne Gutschrift)") end
            seen[id]=p
        end
    end
    return dupes
end
-- 3.0: Art eines Produkts ("credits" | "car" | "cosmetic" | "bundle")
function Purchases.Kind(product)
    return type(product)=="table" and type(product.kind)=="string" and product.kind or "credits"
end
-- 3.0: Titel/Detail für purchaseFX je Art (Deutsch, junges Publikum); GarageServer: emit(p,"purchaseFX",Purchases.FX(product))
local FX_TITLE={credits="Credits erhalten",car="Neues Auto!",cosmetic="Neue Optik!",bundle="Paket erhalten!"}
function Purchases.FX(product)
    local kind=Purchases.Kind(product)
    local detail
    if kind=="credits" then detail="+"..tostring(product.credits).." Credits"
    else detail=tostring(product.name or product.key or "").." · Danke für deinen Einkauf!" end
    return {title=FX_TITLE[kind] or FX_TITLE.credits,detail=detail}
end
-- 3.0: onDeferred(session, product, reason) (optional): eine Shop-Quittung ist gerade nicht anwendbar (z. B. Garage
-- voll); sie bleibt offen, wird in dieser Sitzung alle ShopConfig.ReceiptRetrySeconds erneut versucht und der
-- Spieler bekommt einmal je Quittung einen Hinweis. onGranted(session, product, result) – result = Ergebnis von
-- ShopRules.ApplyReceipt auf dem lebenden Profil (nil bei Credits-Paketen).
function Purchases.Init(getSession,onGranted,onDeferred)
    local retries={}
    local told={} -- 3.0: Hinweis auf eine aufgeschobene Quittung nur einmal je PurchaseId
    Purchases.Validate() -- 3.0: doppelte Produkt-Ids melden
    local function grant(session,receipt,product)
        local granted,new,result -- 3.0: result = ApplyReceipt-Ergebnis
        local deferred=nil -- 3.0: Grund, wenn ApplyReceipt die Quittung (noch) nicht anwenden konnte
        if Purchases.Kind(product)=="credits" then
            granted,new=Profiles.GrantCredits(session.profile,receipt.PurchaseId,product.credits)
        else
            -- 3.0: DLC-Auto/Kosmetik/Bündel: ShopRules.ApplyReceipt auf dem Schnappschuss, atomar mit der Quittung
            local rules=shop()
            if not rules then return false end
            granted,new=Profiles.GrantReceipt(session.profile,receipt.PurchaseId,function(snapshot)
                local ok,res=rules.ApplyReceipt(snapshot,product,os.time()) -- 3.0: Ergebnis/Grund merken
                if ok==true then result=res;deferred=nil else deferred=type(res)=="string" and res or "nicht anwendbar" end
                return ok==true
            end)
        end
        if granted and new and not session.closing then
            local ok,err=pcall(onGranted,session,product,result)
            if not ok then warn("[Purchases] onGranted: "..tostring(err)) end
        end
        if not granted and deferred and onDeferred and not told[receipt.PurchaseId] and not session.closing then
            told[receipt.PurchaseId]=true -- 3.0: einmal je Quittung erklären, was zu tun ist
            local ok,err=pcall(onDeferred,session,product,deferred)
            if not ok then warn("[Purchases] onDeferred: "..tostring(err)) end
        end
        if granted then told[receipt.PurchaseId]=nil end -- 3.0
        return granted,deferred~=nil -- 3.0: aufgeschoben (nicht anwendbar)?
    end
    Marketplace.ProcessReceipt=function(receipt)
        local product=Purchases.ByProduct(receipt.ProductId)
        local player=Players:GetPlayerByUserId(receipt.PlayerId)
        local session=player and getSession(player)
        if not product or not session or session.closing or type(receipt.PurchaseId)~="string" then return Enum.ProductPurchaseDecision.NotProcessedYet end
        local granted,deferred=grant(session,receipt,product) -- 3.0
        if granted then return Enum.ProductPurchaseDecision.PurchaseGranted end
        -- Roblox also retries receipts on rejoin. Resolve ambiguous store writes while
        -- the owner remains present so they do not have to spend Robux a second time.
        -- 3.0: auch aufgeschobene Shop-Quittungen (Garage voll) in der Sitzung wiederholen, damit ein frei
        -- gewordener Platz die Quittung sofort auflöst (nicht erst beim nächsten Beitritt).
        if not retries[receipt.PurchaseId] and (session.profile.receiptPending or (deferred and session.profile.writable)) then
            retries[receipt.PurchaseId]=true
            local _,config=shop()
            local every=config and type(config.ReceiptRetrySeconds)=="number" and config.ReceiptRetrySeconds or 8 -- 3.0
            task.spawn(function()
                while getSession(player)==session and not session.closing and session.profile.writable do
                    task.wait(every)
                    if getSession(player)~=session or session.closing then break end -- 3.0: nicht nach dem Verlassen
                    if grant(session,receipt,product) then break end
                end
                retries[receipt.PurchaseId]=nil
            end)
        end
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end
return Purchases
