-- GoalsUI: Tagesauftrag, drei Tagesziele und Meilensteine mit Fortschrittsbalken.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local GoalsUI = {}

local UI, Remote, T
local refs = {}
local TIER_NAMES = { "Kurz", "Mittel", "Lang" }

local function goalRow(parent, i, onClaim)
	local row, left, right = UI.Row(parent, 10 + i)
	local name = UI.Label(left, "", { Font = Enum.Font.GothamBold, TextSize = 15, LayoutOrder = 1 })
	local sub = UI.Small(left, "", 2)
	local _, fill = UI.Progress(left, T.accent, 3)
	local item = { root = row, name = name, sub = sub, fill = fill }
	item.button = UI.Button(right, "Abholen", T.accent, function()
		if item.id then
			onClaim(item.id)
		end
	end, { TextSize = 14 })
	return item
end

function GoalsUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme

	local daily = UI.Card(page, 1)
	UI.Title(daily, "Tagesauftrag", 1)
	refs.dailyText = UI.Small(daily, "", 2)
	refs.dailyButton = UI.Button(daily, "Tagesauftrag abholen", T.accent, function()
		Remote.Send("daily_claim")
	end, { LayoutOrder = 3 })

	local goals = UI.Card(page, 2)
	UI.Title(goals, "Tagesziele (setzen sich um 0 Uhr UTC zurück)", 1)
	refs.daily = UI.Pool(goals, function(parent, i)
		return goalRow(parent, i, function(id)
			Remote.Send("daily_goal_claim", { id = id })
		end)
	end)

	local ms = UI.Card(page, 3)
	UI.Title(ms, "Meilensteine", 1)
	refs.milestones = UI.Pool(ms, function(parent, i)
		return goalRow(parent, i, function(id)
			Remote.Send("milestone_claim", { id = id })
		end)
	end)
end

local function fill(item, id, name, sub, value, target, claimed)
	item.id = id
	item.name.Text = name
	item.sub.Text = sub
	UI.SetProgress(item.fill, value / target)
	if claimed then
		item.button.Text = "Erledigt ✓"
		UI.SetEnabled(item.button, false)
	else
		item.button.Text = value >= target and "Abholen" or (Locale.Number(math.min(value, target)) .. " / " .. Locale.Number(target))
		UI.SetEnabled(item.button, value >= target)
	end
end

function GoalsUI.Render(s)
	local d = s.goals.daily
	refs.dailyText.Text = string.format("Spiele heute einen beliebigen Bereich und erhalte %s, %d Teile und %d XP.%s", Locale.Credits(d.credits), d.parts, d.xp, d.claimed and " Heute bereits abgeholt." or "")
	refs.dailyButton.Text = d.claimed and "Heute erledigt ✓" or "Tagesauftrag abholen"
	UI.SetEnabled(refs.dailyButton, d.active and not d.claimed)

	refs.daily:Ensure(#d.goals)
	for i, g in ipairs(d.goals) do
		fill(refs.daily.items[i], g.id, (TIER_NAMES[g.tier] or "") .. ": " .. g.text, "Belohnung: " .. Locale.Credits(g.credits), g.value, g.target, g.claimed)
	end
	refs.milestones:Ensure(#s.goals.milestones)
	for i, m in ipairs(s.goals.milestones) do
		fill(refs.milestones.items[i], m.id, m.text, "Belohnung: " .. Locale.Credits(m.credits), m.value, m.target, m.claimed)
	end
end

return GoalsUI
