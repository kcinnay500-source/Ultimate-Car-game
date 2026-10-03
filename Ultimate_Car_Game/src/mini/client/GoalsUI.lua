-- GoalsUI: Tagesauftrag, drei Tagesziele und Meilensteine mit Fortschrittsbalken.
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local GoalsUI = {}

local UI, Remote, T
local refs = {}
local TIER_NAMES = { "Kurz", "Mittel", "Lang" }

local function goalRow(parent, i, onClaim)
	local row, left, right = UI.Row(parent, 10 + i)
	local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
	local sub = UI.Small(left, "", 2)
	local _, fill = UI.Progress(left, T.green, 3)
	local item = { root = row, name = name, sub = sub, fill = fill }
	item.button = UI.Button(right, "Abholen", T.green, function()
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
	refs.dailyButton = UI.Button(daily, "Tagesauftrag abholen", T.green, function()
		Remote.Send("mini_daily_claim")
	end, { LayoutOrder = 3 })

	local goals = UI.Card(page, 2)
	UI.Title(goals, "Tagesziele (neu um 0 Uhr UTC)", 1)
	refs.daily = UI.Pool(goals, function(parent, i)
		return goalRow(parent, i, function(id)
			Remote.Send("mini_daily_goal_claim", { id = id })
		end)
	end)

	local ms = UI.Card(page, 3)
	UI.Title(ms, "Meilensteine", 1)
	refs.milestones = UI.Pool(ms, function(parent, i)
		return goalRow(parent, i, function(id)
			Remote.Send("mini_milestone_claim", { id = id })
		end)
	end)
end

local function fill(item, id, name, sub, value, target, claimed)
	value, target = tonumber(value) or 0, math.max(1, tonumber(target) or 1)
	item.id = id
	item.name.Text = name
	item.sub.Text = sub
	UI.SetProgress(item.fill, value / target)
	if claimed then
		item.button.Text = "Erledigt ✓"
		UI.SetEnabled(item.button, false)
	else
		item.button.Text = value >= target and "Abholen" or (MiniLocale.Number(math.min(value, target)) .. " / " .. MiniLocale.Number(target))
		UI.SetEnabled(item.button, value >= target, T.green)
	end
end

function GoalsUI.Render(s)
	local goals = s.goals
	if not goals then
		return
	end
	local d = goals.daily or {}
	refs.dailyText.Text = string.format(
		"Spiele heute einen beliebigen Bereich und erhalte %s, %d Altteile und %d XP.%s",
		MiniLocale.Credits(d.credits or 0), d.parts or 0, d.xp or 0, d.claimed and " Heute bereits abgeholt." or ""
	)
	refs.dailyButton.Text = d.claimed and "Heute erledigt ✓" or "Tagesauftrag abholen"
	UI.SetEnabled(refs.dailyButton, d.active == true and not d.claimed, T.green)

	local list = d.goals or {}
	refs.daily:Ensure(#list)
	for i, g in ipairs(list) do
		fill(refs.daily.items[i], g.id, (TIER_NAMES[g.tier] or "") .. ": " .. tostring(g.text), "Belohnung: " .. MiniLocale.Credits(g.credits or 0), g.value, g.target, g.claimed)
	end
	local ms = goals.milestones or {}
	refs.milestones:Ensure(#ms)
	for i, m in ipairs(ms) do
		fill(refs.milestones.items[i], m.id, tostring(m.text), "Belohnung: " .. MiniLocale.Credits(m.credits or 0), m.value, m.target, m.claimed)
	end
end

return GoalsUI
