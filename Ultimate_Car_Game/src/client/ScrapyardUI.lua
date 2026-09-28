-- ScrapyardUI: Fahrzeug kaufen, zerlegen, Teile verkaufen. Funde landen im Lager, dazu etwas Schrott.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local ScrapyardUI = {}

local UI, Remote, T
local refs = {}

function ScrapyardUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Schrottplatz", 1)
	UI.Small(card, "Kaufe ein Unfallfahrzeug und zerlege es. Gefundene Teile landen im Lager der Werkstatt, das Blech als Schrott bei der Presse.", 2)
	refs.info = UI.Small(card, "", 3)
	refs.buy = UI.Button(card, "", T.danger, function()
		Remote.Send("scrapyard_buy")
	end, { LayoutOrder = 4 })
	refs.dismantle = UI.Button(card, "Fahrzeug zerlegen", T.warn, function()
		Remote.Send("scrapyard_dismantle")
	end, { LayoutOrder = 5 })
	refs.result = UI.Label(card, "", { LayoutOrder = 6, TextColor3 = T.accent })

	local sell = UI.Card(page, 2)
	UI.Title(sell, "Teile verkaufen", 1)
	refs.sellInfo = UI.Small(sell, "", 2)
	refs.sell = UI.Button(sell, "", T.accent, function()
		Remote.Send("scrapyard_sell")
	end, { LayoutOrder = 3 })
end

function ScrapyardUI.OnResult(res)
	if not refs.result then
		return
	end
	local text = string.format("Ausgebaut: %d Teile%s, %s Schrott und %s im Handschuhfach.", res.parts, res.rare and " inklusive seltenem Turboteil" or "", Locale.Number(res.scrap), Locale.Credits(res.credits))
	refs.result.Text = text
	UI.Toast(text)
end

function ScrapyardUI.Render(s)
	local sy = s.scrapyard
	refs.info.Text = string.format("Lager: %d Teile · Werkzeugbonus +%s · Chance auf seltene Funde %s", s.parts, Locale.Percent(sy.toolBonus - 1), Locale.Percent(sy.rareChance))
	refs.buy.Text = "Fahrzeug kaufen (" .. Locale.Credits(sy.carCost) .. ")"
	UI.SetEnabled(refs.buy, not sy.vehicle and s.credits >= sy.carCost, T.danger)
	UI.SetEnabled(refs.dismantle, sy.vehicle, T.warn)
	refs.sellInfo.Text = string.format("%d Teile für %s verkaufen.", sy.sellParts, Locale.Credits(sy.sellCredits))
	refs.sell.Text = "Verkaufen (+" .. Locale.Credits(sy.sellCredits) .. ")"
	UI.SetEnabled(refs.sell, s.parts >= sy.sellParts)
end

return ScrapyardUI
