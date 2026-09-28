-- ShopUI: Game Passes (Platzhalter-IDs in Config; ohne ID startet kein Kauf).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))

local ShopUI = {}

local UI, Remote, T
local refs = {}

function ShopUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Game Passes", 1)
	UI.Small(card, "Game Passes wirken nur auf dein Schrott-Guthaben, nie auf die Bestenliste. Keine Zufallsbelohnungen.", 2)
	refs.double = UI.Label(card, "", { LayoutOrder = 3 })
	refs.doubleButton = UI.Button(card, "2× Schrott kaufen", T.warn, function()
		Remote.Send("pass_prompt", { pass = "DoubleScrap" })
	end, { LayoutOrder = 4 })
	refs.plus = UI.Label(card, "", { LayoutOrder = 5 })
	refs.plusButton = UI.Button(card, "Schrottpresse+ kaufen", T.warn, function()
		Remote.Send("pass_prompt", { pass = "PressPlus" })
	end, { LayoutOrder = 6 })
end

function ShopUI.Render(s)
	local p = s.passes
	refs.double.Text = "2× Schrott: Klicks und Maschinen ×" .. Config.GamePasses.DoubleScrap.multiplier .. (p.doubleScrap and " · aktiv ✓" or "") .. (p.doubleScrapConfigured and "" or " · noch nicht eingerichtet")
	refs.plus.Text = "Schrottpresse+: Maschinen ×" .. tostring(Config.GamePasses.PressPlus.machineMultiplier):gsub("%.", ",") .. (p.pressPlus and " · aktiv ✓" or "") .. (p.pressPlusConfigured and "" or " · noch nicht eingerichtet")
	UI.SetEnabled(refs.doubleButton, p.doubleScrapConfigured and not p.doubleScrap, T.warn)
	UI.SetEnabled(refs.plusButton, p.pressPlusConfigured and not p.pressPlus, T.warn)
end

return ShopUI
