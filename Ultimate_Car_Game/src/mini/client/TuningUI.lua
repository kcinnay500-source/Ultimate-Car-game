-- TuningUI: Idle Tuning Garage (Echtzeit-Projekte, passive Einnahmen, Ausbau der Tuning-Abteilung).
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))
local Unlocks = require(Mini:WaitForChild("Unlocks"))

local TuningUI = {}

-- Autos: Abschnitt "Mein Auto tunen" (CarTuningUI); fehlt er, bleibt die Idle-Garage nutzbar
local CarTuning
do
	local ok, mod = pcall(function()
		return require(script.Parent:WaitForChild("CarTuningUI", 10))
	end)
	if ok and type(mod) == "table" then
		CarTuning = mod
	end
end

local UI, Remote, T
local refs = {}
local state
local snapClock = 0

function TuningUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	if CarTuning then
		refs.carTuning = CarTuning.Build(page, ctx, 0)
	end

	local head = UI.Card(page, 1)
	UI.Title(head, "Idle Tuning Garage", 1)
	UI.Small(head, "Tuning-Projekte laufen in Echtzeit weiter, auch wenn du offline bist. Längere Projekte bringen überproportional mehr.", 2)
	refs.info = UI.Small(head, "", 3)

	local idle = UI.Card(page, 2)
	UI.Title(idle, "Passive Einnahmen", 1)
	refs.idleText = UI.Small(idle, "", 2)
	local _, idleFill = UI.Progress(idle, T.blue, 3)
	refs.idleFill = idleFill
	refs.idleButton = UI.Button(idle, "Einnahmen abholen", T.blue, function()
		Remote.Send("mini_tuning_idle")
	end, { LayoutOrder = 4 })

	local running = UI.Card(page, 3)
	UI.Title(running, "Laufende Projekte", 1)
	refs.none = UI.Small(running, "Kein Projekt aktiv. Starte unten eins.", 2)
	refs.projects = UI.Pool(running, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local _, fill = UI.Progress(left, T.blue, 3)
		local item = { root = row, name = name, sub = sub, fill = fill }
		item.button = UI.Button(right, "", T.green, function()
			if item.slot then
				Remote.Send("mini_tuning_collect", { slot = item.slot })
			end
		end, { TextSize = 14 })
		return item
	end)

	local catalog = UI.Card(page, 4)
	UI.Title(catalog, "Projekt starten", 1)
	refs.catalog = UI.Pool(catalog, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local item = { root = row, name = name, sub = sub }
		item.button = UI.Button(right, "", T.blue, function()
			if item.id then
				Remote.Send("mini_tuning_start", { id = item.id })
			end
		end, { TextSize = 14 })
		return item
	end)

	refs.upgrade = UI.UpgradeCard(page, 5, "tuningLevel", Remote)
end

function TuningUI.Step()
	if CarTuning then
		CarTuning.Step()
	end
	if not state or not state.tuning then
		return
	end
	local elapsed = os.clock() - snapClock
	for i, pj in ipairs(state.tuning.projects or {}) do
		local item = refs.projects.items[i]
		if item then
			local remaining = math.max(0, (pj.remaining or 0) - elapsed)
			UI.SetProgress(item.fill, 1 - remaining / math.max(1, pj.duration or 1))
			if remaining > 0 then
				item.button.Text = MiniLocale.Duration(remaining)
				UI.SetEnabled(item.button, false)
			else
				item.button.Text = "Abholen"
				UI.SetEnabled(item.button, true)
			end
		end
	end
end

function TuningUI.Render(s)
	if CarTuning then
		CarTuning.Render(s)
	end
	local tu = s.tuning
	if not tu then
		return
	end
	state = s
	snapClock = os.clock()
	local pressBonus = s.press and s.press.tuningMultiplier or 1
	refs.info.Text = string.format(
		"Tuning-Stufe %d · Plätze %d · Abgeschlossene Projekte %d · Presse-Bonus +%s",
		tu.level or 1, tu.slots or 1, tu.completed or 0, MiniLocale.Percent(pressBonus - 1)
	)
	refs.idleText.Text = string.format(
		"%s Cr pro Minute. Bereit: %s. Es werden höchstens %s gesammelt.",
		MiniLocale.Number(tu.idleRate or 0), MiniLocale.Credits(tu.pendingIdle or 0), MiniLocale.Duration(tu.idleCapSeconds or 0)
	)
	UI.SetProgress(refs.idleFill, (tu.idleSeconds or 0) / math.max(1, tu.idleCapSeconds or 1))
	-- Tuning-Projekte (und ihre passiven Einnahmen) gibt es erst ab der Freischaltung (Level 6): vorher bleibt der
	-- Knopf aus – der Server sperrt mini_tuning_idle ohnehin und sammelt nichts an
	local unlocked = Unlocks.TabAllowed({ level = s.level }, "tuning")
	if not unlocked then
		local entry = Unlocks.ForTab("tuning")
		refs.idleText.Text = "Passive Einnahmen gibt es ab Level " .. tostring(entry and entry.level or "?") .. " mit den Tuning-Projekten."
		refs.idleButton.Text = "Ab Level " .. tostring(entry and entry.level or "?")
	else
		refs.idleButton.Text = "Einnahmen abholen"
	end
	UI.SetEnabled(refs.idleButton, unlocked and (tu.pendingIdle or 0) >= 1, T.blue)

	local projects = tu.projects or {}
	refs.none.Visible = #projects == 0
	refs.projects:Ensure(#projects)
	for i, pj in ipairs(projects) do
		local item = refs.projects.items[i]
		item.slot = pj.slot
		item.name.Text = "Platz " .. tostring(pj.slot) .. ": " .. tostring(pj.name)
		item.sub.Text = "Belohnung: " .. MiniLocale.Credits(pj.reward or 0)
	end

	local free = #projects < (tu.slots or 1)
	local list = tu.catalog or {}
	refs.catalog:Ensure(#list)
	for i, def in ipairs(list) do
		local item = refs.catalog.items[i]
		item.id = def.id
		item.name.Text = tostring(def.name) .. " · " .. MiniLocale.Duration((def.minutes or 0) * 60)
		if def.locked then
			item.sub.Text = "Ab Tuning-Stufe " .. tostring(def.unlock) .. " (Ausbau unten)"
		else
			item.sub.Text = "Kosten " .. MiniLocale.Credits(def.cost or 0) .. " · Belohnung " .. MiniLocale.Credits(def.reward or 0)
		end
		item.button.Text = def.locked and "Gesperrt" or (free and "Starten" or "Kein Platz frei")
		UI.SetEnabled(item.button, free and not def.locked and (s.credits or 0) >= (def.cost or 0), T.blue)
	end
	refs.upgrade.Render(s, MiniLocale.Credits)
	TuningUI.Step()
end

return TuningUI
