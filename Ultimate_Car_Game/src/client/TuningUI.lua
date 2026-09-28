-- TuningUI: Idle Tuning Garage (Echtzeit-Projekte, passive Einnahmen).
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local TuningUI = {}

local UI, Remote, T
local refs = {}
local state
local snapClock = 0

function TuningUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme

	local head = UI.Card(page, 1)
	UI.Title(head, "Idle Tuning Garage", 1)
	UI.Small(head, "Tuning-Projekte laufen in Echtzeit weiter, auch wenn du offline bist. Längere Projekte bringen überproportional mehr.", 2)
	refs.info = UI.Small(head, "", 3)

	local idle = UI.Card(page, 2)
	UI.Title(idle, "Passive Einnahmen", 1)
	refs.idleText = UI.Small(idle, "", 2)
	local _, idleFill = UI.Progress(idle, T.accent2, 3)
	refs.idleFill = idleFill
	refs.idleButton = UI.Button(idle, "Einnahmen abholen", T.accent2, function()
		Remote.Send("tuning_idle")
	end, { LayoutOrder = 4 })

	local running = UI.Card(page, 3)
	UI.Title(running, "Laufende Projekte", 1)
	refs.none = UI.Small(running, "Kein Projekt aktiv. Starte unten eins.", 2)
	refs.projects = UI.Pool(running, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = Enum.Font.GothamBold, TextSize = 15, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local _, fill = UI.Progress(left, T.accent2, 3)
		local item = { root = row, name = name, sub = sub, fill = fill }
		item.button = UI.Button(right, "", T.accent, function()
			if item.slot then
				Remote.Send("tuning_collect", { slot = item.slot })
			end
		end, { TextSize = 14 })
		return item
	end)

	local catalog = UI.Card(page, 4)
	UI.Title(catalog, "Projekt starten", 1)
	refs.catalog = UI.Pool(catalog, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = Enum.Font.GothamBold, TextSize = 15, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local item = { root = row, name = name, sub = sub }
		item.button = UI.Button(right, "", T.accent2, function()
			if item.id then
				Remote.Send("tuning_start", { id = item.id })
			end
		end, { TextSize = 14 })
		return item
	end)
end

function TuningUI.Step()
	if not state then
		return
	end
	local elapsed = os.clock() - snapClock
	for i, pj in ipairs(state.tuning.projects) do
		local item = refs.projects.items[i]
		if item then
			local remaining = math.max(0, pj.remaining - elapsed)
			UI.SetProgress(item.fill, 1 - remaining / pj.duration)
			if remaining > 0 then
				item.button.Text = Locale.Duration(remaining)
				UI.SetEnabled(item.button, false)
			else
				item.button.Text = "Abholen"
				UI.SetEnabled(item.button, true)
			end
		end
	end
end

function TuningUI.Render(s)
	state = s
	snapClock = os.clock()
	local tu = s.tuning
	refs.info.Text = string.format("Tuning-Stufe %d · Plätze %d · Abgeschlossene Projekte %d · Presse-Bonus +%s", tu.level, tu.slots, tu.completed, Locale.Percent(s.press.tuningMultiplier - 1))
	refs.idleText.Text = string.format("%s Cr pro Minute. Bereit: %s. Es werden höchstens %s gesammelt.", Locale.Number(tu.idleRate), Locale.Credits(tu.pendingIdle), Locale.Duration(tu.idleCapSeconds))
	UI.SetProgress(refs.idleFill, tu.idleSeconds / tu.idleCapSeconds)
	UI.SetEnabled(refs.idleButton, tu.pendingIdle >= 1, T.accent2)

	refs.none.Visible = #tu.projects == 0
	refs.projects:Ensure(#tu.projects)
	for i, pj in ipairs(tu.projects) do
		local item = refs.projects.items[i]
		item.slot = pj.slot
		item.name.Text = "Platz " .. pj.slot .. ": " .. pj.name
		item.sub.Text = "Belohnung: " .. Locale.Credits(pj.reward)
	end

	local free = #tu.projects < tu.slots
	refs.catalog:Ensure(#tu.catalog)
	for i, def in ipairs(tu.catalog) do
		local item = refs.catalog.items[i]
		item.id = def.id
		item.name.Text = def.name .. " · " .. Locale.Duration(def.minutes * 60)
		if def.locked then
			item.sub.Text = "Ab Tuning-Stufe " .. def.unlock .. " (Ausbau in der Werkstatt)"
		else
			item.sub.Text = "Kosten " .. Locale.Credits(def.cost) .. " · Belohnung " .. Locale.Credits(def.reward)
		end
		item.button.Text = def.locked and "Gesperrt" or "Starten"
		UI.SetEnabled(item.button, free and not def.locked and s.credits >= def.cost, T.accent2)
	end
	TuningUI.Step()
end

return TuningUI
