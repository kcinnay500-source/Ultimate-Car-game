-- LeaderboardUI: globale Bestenliste (Top 50) und eigene Platzierung.
-- Daten kommen als mini_notice {kind="leaderboard", available, rows, own}; angefordert mit mini_leaderboard_refresh.
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniConfig = require(Mini:WaitForChild("MiniConfig"))
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local LeaderboardUI = {}

local UI, Remote, T
local refs = {}
local TOP = MiniConfig.LeaderboardTopCount or 50

local function loadingText(state)
	if state == "loading" then
		return MiniLocale.T("leaderboard_loading")
	end
	return MiniLocale.T("leaderboard_unavailable")
end

function LeaderboardUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Bestenliste · lebenslang gepresster Schrott", 1)
	UI.Small(card, "Gezählt wird Schrott aus Klicks und Maschinen. Umtausch und Rebirth senken den Wert nicht, Game Passes erhöhen ihn nicht. Aktualisierung höchstens einmal pro Minute.", 2)
	refs.status = UI.Label(card, loadingText("loading"), { LayoutOrder = 3, TextColor3 = T.yellow })
	refs.own = UI.Label(card, "", { LayoutOrder = 4, Font = UI.FontBold })
	refs.refresh = UI.Button(card, "Aktualisieren", T.blue, function()
		Remote.Send("mini_leaderboard_refresh")
	end, { LayoutOrder = 5 })
	local list = UI.Card(page, 2)
	refs.rows = {}
	for i = 1, TOP do
		refs.rows[i] = UI.Label(list, "", { LayoutOrder = i, TextSize = 15, Visible = false })
	end
end

function LeaderboardUI.OnData(view)
	if not refs.status or type(view) ~= "table" then
		return
	end
	if view.available ~= true then
		refs.status.Visible = true
		refs.status.Text = loadingText(view.available)
		refs.own.Text = ""
		for _, r in ipairs(refs.rows) do
			r.Visible = false
		end
		return
	end
	local rows = type(view.rows) == "table" and view.rows or {}
	refs.status.Visible = #rows == 0
	refs.status.Text = "Noch keine Einträge."
	local own = type(view.own) == "table" and view.own or {}
	if own.rank then
		refs.own.Text = string.format("Dein Platz: %d · %s", own.rank, MiniLocale.Scrap(own.value or 0))
	elseif own.atLeast then
		refs.own.Text = string.format("Dein Platz: jenseits von %d · %s", math.max(0, own.atLeast - 1), MiniLocale.Scrap(own.value or 0))
	else
		refs.own.Text = ""
	end
	for i, r in ipairs(refs.rows) do
		local row = rows[i]
		r.Visible = row ~= nil
		if row then
			r.Text = string.format("%d. %s – %s", row.rank or i, tostring(row.name or "?"), MiniLocale.Number(row.value or 0))
			r.TextColor3 = row.self and T.yellow or T.text
			r.Font = row.self and UI.FontBold or UI.Font
		end
	end
end

return LeaderboardUI
