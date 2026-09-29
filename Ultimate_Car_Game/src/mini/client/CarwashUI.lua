-- CarwashUI: Tab "carwash" (Waschstraße). Rein kosmetisch: Glanz-Effekt fürs aktive Auto gegen einen kleinen Preis.
-- Absicht: mini_carwash (ohne Felder). Preis, Guthaben und ob das aktive Auto in Reichweite ist, prüft der Server.
-- Snapshot (optional): carwash {price, shineLeft (Sekunden)}; sonst cars[i].shineLeft.
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local Lib = require(script.Parent:WaitForChild("DealerUI")).Lib

local CarwashUI = {}

local UI, Remote, T
local refs = {}
local shineUntil = 0 -- os.clock(), bis zu dem der Glanz hält (aus shineLeft)
local shownShine = -1

local function num(v)
	return Lib.Num(v)
end

function CarwashUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	refs = {}

	local card = UI.Card(page, 1)
	UI.Title(card, "Waschstraße", 1)
	UI.Small(card, "Wäsche, Politur und Wachs für dein aktives Auto. Danach glänzt es eine Weile. Rein optisch, ohne Einfluss auf die Fahrwerte.", 2)
	refs.car = UI.Label(card, "", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 3 })
	refs.preview = Lib.Preview(card, 120, 4)
	refs.shine = UI.Small(card, "", 5)
	refs.result = UI.Label(card, "", { TextSize = 15, TextColor3 = T.green, LayoutOrder = 6, Visible = false })
	refs.wash = UI.Button(card, "Waschen", T.green, function()
		Remote.Send("mini_carwash")
	end, { Name = "Waschen", LayoutOrder = 7 })
	refs.travel = UI.Button(card, "Zur Waschstraße reisen", T.blue, function()
		Remote.Send("mini_travel", { key = "carwash" })
	end, { Name = "Reisen", LayoutOrder = 8 })
end

-- mini_notice {kind="carwash", shineLeft?}: kurze Bestätigung in der Karte (Server-Toast zeigt 2.4.0)
function CarwashUI.OnNotice(data)
	if type(data) ~= "table" or data.kind ~= "carwash" or not refs.result then
		return
	end
	refs.result.Text = "Frisch gewaschen – dein Auto glänzt!"
	refs.result.Visible = true
	local left = num(data.shineLeft)
	if left then
		shineUntil = os.clock() + left
		shownShine = -1
	end
end

function CarwashUI.Step()
	if not refs.shine then
		return
	end
	local left = math.max(0, math.ceil(shineUntil - os.clock()))
	if left == shownShine then
		return
	end
	shownShine = left
	refs.shine.Text = left > 0 and ("Glanz hält noch " .. MiniLocale.Duration(left) .. ".") or "Kein Glanz aktiv."
end

function CarwashUI.Render(s)
	if type(s) ~= "table" or not refs.car then
		return
	end
	local wash = type(s.carwash) == "table" and s.carwash or {}
	local price = num(wash.price) or num(s.carwashPrice)
	local car = Lib.FindCar(s, Lib.ActiveId(s))
	if car then
		refs.car.Text = "Aktives Auto: " .. Lib.CarName(s, car) .. (Lib.IsOut(s, car) and " (unterwegs)" or " (abgestellt)")
		refs.preview.frame.Visible = true
		refs.preview:Set(Lib.CarBody(s, car), Lib.Style(s, car))
	else
		refs.car.Text = "Kein aktives Auto. Hol zuerst eins im Autohaus („Meine Autos“)."
		refs.preview.frame.Visible = false
	end
	local left = num(wash.shineLeft) or num(car and car.shineLeft)
	if left then
		shineUntil = os.clock() + left
		shownShine = -1
	end
	refs.wash.Text = price and ("Waschen · " .. MiniLocale.Credits(price)) or "Waschen"
	local locked = car and car.locked
	UI.SetEnabled(refs.wash, car ~= nil and not locked and (not price or (num(s.credits) or 0) >= price), T.green)
	CarwashUI.Step()
end

return CarwashUI
