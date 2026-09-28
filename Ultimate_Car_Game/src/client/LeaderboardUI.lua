-- LeaderboardUI: globale Bestenliste (Top 50) und eigene Platzierung.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Locale = require(Shared:WaitForChild("Locale"))

local LeaderboardUI = {}

local UI, Remote, T
local refs = {}

function LeaderboardUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Bestenliste · lebenslang gepresster Schrott", 1)
	UI.Small(card, "Gezählt wird Schrott aus Klicks und Maschinen. Umtausch und Rebirth senken den Wert nicht, Game Passes erhöhen ihn nicht. Aktualisierung höchstens einmal pro Minute.", 2)
	refs.status = UI.Label(card, Locale.T("leaderboard_loading"), { LayoutOrder = 3, TextColor3 = T.warn })
	refs.own = UI.Label(card, "", { LayoutOrder = 4, Font = Enum.Font.GothamBold })
	refs.refresh = UI.Button(card, "Aktualisieren", T.accent2, function()
		Remote.Send("leaderboard_refresh")
	end, { LayoutOrder = 5 })
	local list = UI.Card(page, 2)
	refs.rows = {}
	for i = 1, Config.LeaderboardTopCount do
		refs.rows[i] = UI.Label(list, "", { LayoutOrder = i, TextSize = 15, Visible = false })
	end
end

function LeaderboardUI.OnData(view)
	if not refs.status then
		return
	end
	if view.available ~= true then
		refs.status.Visible = true
		refs.status.Text = view.available == "loading" and Locale.T("leaderboard_loading") or Locale.T("leaderboard_unavailable")
		refs.own.Text = ""
		for _, r in ipairs(refs.rows) do
			r.Visible = false
		end
		return
	end
	refs.status.Visible = #view.rows == 0
	refs.status.Text = "Noch keine Einträge."
	local own = view.own
	if own.rank then
		refs.own.Text = string.format("Dein Platz: %d · %s", own.rank, Locale.Scrap(own.value))
	else
		refs.own.Text = string.format("Dein Platz: jenseits von %d · %s", own.atLeast - 1, Locale.Scrap(own.value))
	end
	for i, r in ipairs(refs.rows) do
		local row = view.rows[i]
		r.Visible = row ~= nil
		if row then
			r.Text = string.format("%d. %s – %s", row.rank, row.name, Locale.Number(row.value))
			r.TextColor3 = row.self and T.warn or T.text
		end
	end
end

return LeaderboardUI
