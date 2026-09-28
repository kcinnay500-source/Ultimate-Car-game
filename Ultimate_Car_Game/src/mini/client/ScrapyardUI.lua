-- ScrapyardUI: Unfallfahrzeug kaufen, zerlegen, Altteile verkaufen, Schrottplatz ausbauen.
-- Funde landen als Altteile im Lager (d.games.parts), das Blech als Schrott bei der Presse.
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local ScrapyardUI = {}

local UI, Remote, T
local refs = {}

function ScrapyardUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Schrottplatz", 1)
	UI.Small(card, "Kaufe ein Unfallfahrzeug und zerlege es. Gefundene Teile landen als Altteile im Lager, das Blech als Schrott bei der Presse.", 2)
	refs.info = UI.Small(card, "", 3)
	refs.buy = UI.Button(card, "Fahrzeug kaufen", T.green, function()
		Remote.Send("mini_scrapyard_buy")
	end, { LayoutOrder = 4 })
	refs.dismantle = UI.Button(card, "Fahrzeug zerlegen", T.blue, function()
		Remote.Send("mini_scrapyard_dismantle")
	end, { LayoutOrder = 5 })
	refs.result = UI.Label(card, "", { LayoutOrder = 6, TextColor3 = T.green, Visible = false })

	local sell = UI.Card(page, 2)
	UI.Title(sell, "Altteile verkaufen", 1)
	refs.sellInfo = UI.Small(sell, "", 2)
	refs.sell = UI.Button(sell, "Verkaufen", T.green, function()
		Remote.Send("mini_scrapyard_sell")
	end, { LayoutOrder = 3 })

	refs.upgrade = UI.UpgradeCard(page, 3, "scrapyardLevel", Remote)
end

-- mini_notice {kind="scrapyard", parts, rare, rarePart, rareSku, scrap, credits}
function ScrapyardUI.OnResult(res)
	if not refs.result then
		return
	end
	local rare = ""
	if type(res.rarePart) == "string" and res.rarePart ~= "" then
		rare = " inklusive seltenem Teil „" .. res.rarePart .. "“ (liegt jetzt im Werkstatt-Lager)"
	elseif res.rare then
		rare = " inklusive seltenem Fund"
	end
	local text = string.format(
		"Ausgebaut: %d Altteile%s, %s Schrott und %s im Handschuhfach.",
		tonumber(res.parts) or 0, rare, MiniLocale.Number(tonumber(res.scrap) or 0), MiniLocale.Credits(tonumber(res.credits) or 0)
	)
	-- nur in der Karte anzeigen (kein eigener Toast, damit Server-Toasts nicht doppelt erscheinen)
	refs.result.Text = text
	refs.result.Visible = true
end

function ScrapyardUI.Render(s)
	local sy = s.scrapyard
	if not sy then
		return
	end
	refs.info.Text = string.format(
		"Lager: %d Altteile · Werkzeugbonus +%s · Chance auf seltene Funde %s",
		s.parts or 0, MiniLocale.Percent((sy.toolBonus or 1) - 1), MiniLocale.Percent(sy.rareChance or 0)
	)
	refs.buy.Text = "Fahrzeug kaufen (" .. MiniLocale.Credits(sy.carCost or 0) .. ")"
	UI.SetEnabled(refs.buy, not sy.vehicle and (s.credits or 0) >= (sy.carCost or math.huge), T.green)
	UI.SetEnabled(refs.dismantle, sy.vehicle == true, T.blue)
	refs.sellInfo.Text = string.format("%d Altteile für %s verkaufen.", sy.sellParts or 0, MiniLocale.Credits(sy.sellCredits or 0))
	refs.sell.Text = "Verkaufen (+" .. MiniLocale.Credits(sy.sellCredits or 0) .. ")"
	UI.SetEnabled(refs.sell, (s.parts or 0) >= (sy.sellParts or math.huge), T.green)
	refs.upgrade.Render(s, MiniLocale.Credits)
end

return ScrapyardUI
