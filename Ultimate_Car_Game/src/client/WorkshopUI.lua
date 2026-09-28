-- WorkshopUI: Werkstatt-Aufträge (Hebebühnen) und Ausbau.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local WorkshopUI = {}

local UI, Remote, T
local refs = {}
local state

local function serverNow()
	return workspace:GetServerTimeNow()
end

function WorkshopUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme

	local head = UI.Card(page, 1)
	UI.Title(head, "Werkstatt", 1)
	refs.info = UI.Small(head, "", 2)

	local active = UI.Card(page, 2)
	UI.Title(active, "Auf den Hebebühnen", 1)
	refs.noJobs = UI.Small(active, "Noch keine laufenden Reparaturen.", 2)
	refs.jobs = UI.Pool(active, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = Enum.Font.GothamBold, TextSize = 15, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local _, fill = UI.Progress(left, T.accent, 3)
		local item = { root = row, name = name, sub = sub, fill = fill }
		item.button = UI.Button(right, "", T.accent, function()
			if item.id then
				Remote.Send("workshop_finish", { id = item.id })
			end
		end, { TextSize = 14 })
		return item
	end)

	local offers = UI.Card(page, 3)
	UI.Title(offers, "Auftragsangebote", 1)
	UI.Small(offers, "Teile aus dem Lager ersetzen Reparaturkosten. Diagnosepunkte verkürzen die Reparaturzeit, Parkplatz-Serien verbessern die Angebote.", 2)
	refs.offers = UI.Pool(offers, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = Enum.Font.GothamBold, TextSize = 15, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local item = { root = row, name = name, sub = sub }
		item.button = UI.Button(right, "Annehmen", T.accent, function()
			if item.id then
				Remote.Send("workshop_accept", { id = item.id })
			end
		end, { TextSize = 14 })
		return item
	end)

	local upgrades = UI.Card(page, 4)
	UI.Title(upgrades, "Ausbau", 1)
	refs.upgrades = UI.Pool(upgrades, function(parent, i)
		local row, left, right = UI.Row(parent, 10 + i)
		local name = UI.Label(left, "", { Font = Enum.Font.GothamBold, TextSize = 15, LayoutOrder = 1 })
		local sub = UI.Small(left, "", 2)
		local item = { root = row, name = name, sub = sub }
		item.button = UI.Button(right, "", T.accent2, function()
			if item.key then
				Remote.Send("upgrade_buy", { key = item.key, level = item.level })
			end
		end, { TextSize = 14 })
		return item
	end)
end

function WorkshopUI.Step()
	if not state then
		return
	end
	local now = serverNow()
	for i, job in ipairs(state.workshop.jobs) do
		local item = refs.jobs.items[i]
		if item then
			local remaining = math.max(0, job.endsAt - now)
			local total = math.max(1, job.endsAt - job.startedAt)
			UI.SetProgress(item.fill, 1 - remaining / total)
			if remaining > 0 then
				item.button.Text = Locale.Duration(remaining)
				UI.SetEnabled(item.button, false)
			else
				item.button.Text = "Abrechnen"
				UI.SetEnabled(item.button, true)
			end
		end
	end
end

function WorkshopUI.Render(s)
	state = s
	local w = s.workshop
	refs.info.Text = string.format("Hebebühnen frei: %d von %d · Lager: %d Teile · Reparaturtempo ×%s", math.max(0, w.available), w.bays, s.parts, (string.format("%.2f", w.repairSpeed):gsub("%.", ",")))

	refs.noJobs.Visible = #w.jobs == 0
	refs.jobs:Ensure(#w.jobs)
	for i, job in ipairs(w.jobs) do
		local item = refs.jobs.items[i]
		item.id = job.id
		item.name.Text = job.name
		item.sub.Text = "Vergütung: " .. Locale.Credits(job.reward)
	end

	refs.offers:Ensure(#w.offers)
	for i, o in ipairs(w.offers) do
		local item = refs.offers.items[i]
		item.id = o.id
		item.name.Text = o.name .. " · " .. Locale.Duration(o.time)
		item.sub.Text = string.format("Vergütung: %s · %d XP\nKosten: %s + %d Lagerteil(e)", Locale.Credits(o.reward), o.xp, Locale.Credits(o.cash), o.partUse)
		UI.SetEnabled(item.button, w.available > 0 and s.credits >= o.cash)
	end

	refs.upgrades:Ensure(#s.upgrades)
	for i, u in ipairs(s.upgrades) do
		local item = refs.upgrades.items[i]
		item.key = u.key
		item.level = u.level
		item.name.Text = u.name .. " · Stufe " .. u.level
		item.sub.Text = u.desc
		local max = u.level >= u.max
		item.button.Text = max and "MAX" or Locale.Credits(u.cost)
		UI.SetEnabled(item.button, not max and s.credits >= u.cost, T.accent2)
	end
	WorkshopUI.Step()
end

return WorkshopUI
