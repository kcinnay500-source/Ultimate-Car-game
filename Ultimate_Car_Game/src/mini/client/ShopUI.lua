-- ShopUI: Game Passes der Minispiele (IDs in MiniConfig; ohne ID startet kein Kauf).
-- Der Kauf läuft über mini_pass_prompt; den Roblox-Dialog öffnet der Server (MiniPasses).
-- Credits-Pakete bleiben im 2.4.0-Credits-Shop des Tablets.
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(Mini:WaitForChild("MiniConfig"))

local ShopUI = {}

local UI, Remote, T, ctx
local refs = {}

local function passValue(name, field, fallback)
	local passes = MiniConfig.GamePasses
	local entry = passes and passes[name]
	local v = entry and entry[field]
	return v ~= nil and v or fallback
end

local function dec(n)
	local s = tostring(n)
	return (s:gsub("%.", ","))
end

function ShopUI.Build(page, context)
	ctx = context
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local hero = UI.Card(page, 1)
	hero.BackgroundColor3 = T.purpleDark
	UI.Title(hero, "Game Passes", 1)
	UI.Label(hero, "Game Passes wirken nur auf dein Schrott-Guthaben, nie auf die Bestenliste. Keine Zufallsbelohnungen. Roblox zeigt vor dem Kauf den verbindlichen Preis.", { LayoutOrder = 2, TextSize = 15, TextColor3 = T.text })

	local double = UI.Card(page, 2)
	UI.Title(double, "2× Schrott", 1)
	refs.double = UI.Small(double, "", 2)
	refs.doubleButton = UI.Button(double, "2× Schrott kaufen", T.purple, function()
		Remote.Send("mini_pass_prompt", { pass = "DoubleScrap" })
	end, { LayoutOrder = 3 })

	local plus = UI.Card(page, 3)
	UI.Title(plus, "Schrottpresse+", 1)
	refs.plus = UI.Small(plus, "", 2)
	refs.plusButton = UI.Button(plus, "Schrottpresse+ kaufen", T.purple, function()
		Remote.Send("mini_pass_prompt", { pass = "PressPlus" })
	end, { LayoutOrder = 3 })

	local credits = UI.Card(page, 4)
	UI.Title(credits, "Credits-Pakete", 1)
	UI.Small(credits, "Credits für deine Werkstatt gibt es im Credits-Shop des Tablets.", 2)
	UI.Button(credits, "Zum Credits-Shop", T.blue, function()
		if ctx.OpenTablet then
			ctx.OpenTablet("shop")
		end
	end, { LayoutOrder = 3, Visible = ctx.OpenTablet ~= nil })
end

function ShopUI.Render(s)
	local p = s.passes or {}
	refs.double.Text = "Klicks und Maschinen ×" .. dec(passValue("DoubleScrap", "multiplier", 2))
		.. (p.doubleScrap and " · aktiv ✓" or "") .. (p.doubleScrapConfigured and "" or " · noch nicht eingerichtet")
	refs.plus.Text = "Maschinen ×" .. dec(passValue("PressPlus", "machineMultiplier", 1.5))
		.. (p.pressPlus and " · aktiv ✓" or "") .. (p.pressPlusConfigured and "" or " · noch nicht eingerichtet")
	refs.doubleButton.Text = p.doubleScrap and "Bereits aktiv ✓" or "2× Schrott kaufen"
	refs.plusButton.Text = p.pressPlus and "Bereits aktiv ✓" or "Schrottpresse+ kaufen"
	UI.SetEnabled(refs.doubleButton, p.doubleScrapConfigured == true and not p.doubleScrap, T.purple)
	UI.SetEnabled(refs.plusButton, p.pressPlusConfigured == true and not p.pressPlus, T.purple)
end

return ShopUI
