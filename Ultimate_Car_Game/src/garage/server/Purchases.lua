local Marketplace=game:GetService("MarketplaceService")
local Players=game:GetService("Players")
local C=require(game:GetService("ReplicatedStorage").GarageShared.Config)
local Profiles=require(script.Parent.Profiles)
local Purchases={}
function Purchases.ByProduct(id)
    if type(id)~="number" or id<=0 then return nil end
    local found
    for _,p in ipairs(C.CreditProducts) do
        if p.productId==id then if found then return nil end;found=p end
    end
    return found
end
function Purchases.Init(getSession,onGranted)
    local retries={}
    local function grant(session,receipt,product)
        local granted,new=Profiles.GrantCredits(session.profile,receipt.PurchaseId,product.credits)
        if granted and new and not session.closing then onGranted(session,product) end
        return granted
    end
    Marketplace.ProcessReceipt=function(receipt)
        local product=Purchases.ByProduct(receipt.ProductId)
        local player=Players:GetPlayerByUserId(receipt.PlayerId)
        local session=player and getSession(player)
        if not product or not session or session.closing or type(receipt.PurchaseId)~="string" then return Enum.ProductPurchaseDecision.NotProcessedYet end
        if grant(session,receipt,product) then return Enum.ProductPurchaseDecision.PurchaseGranted end
        -- Roblox also retries receipts on rejoin. Resolve ambiguous store writes while
        -- the owner remains present so they do not have to spend Robux a second time.
        if not retries[receipt.PurchaseId] and session.profile.receiptPending then
            retries[receipt.PurchaseId]=true
            task.spawn(function()
                while getSession(player)==session and not session.closing and session.profile.writable do
                    task.wait(8)
                    if grant(session,receipt,product) then break end
                end
                retries[receipt.PurchaseId]=nil
            end)
        end
        return Enum.ProductPurchaseDecision.NotProcessedYet
    end
end
return Purchases
