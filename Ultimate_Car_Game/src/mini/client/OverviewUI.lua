-- OverviewUI: Karriere (2.4.0-Profil), nächstes Ziel, Kurzüberblick aller Minispiele und der Werkstatt, aktive Boni.
-- Die 2D-Werkstatt gibt es nicht mehr: die Werkstatt-Zeile zeigt die echten 2.4.0-Aufträge (Snapshot `workshopJobs`).
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local OverviewUI = {}

local UI, T, ctx
local refs = {}

local function pct(x)
	return MiniLocale.Percent(x)
end

function OverviewUI.Build(page, context)
	ctx = context
	UI = ctx.UI
	T = UI.Theme

	local career = UI.Card(page, 1)
	UI.Title(career, "Deine Karriere", 1)
	refs.career = UI.Label(career, "", { LayoutOrder = 2 })
	local _, xpFill = UI.Progress(career, T.green, 3)
	refs.xpFill = xpFill

	local nextCard = UI.Card(page, 2)
	UI.Title(nextCard, "Nächstes Ziel", 1)
	refs.next = UI.Label(nextCard, "", { LayoutOrder = 2 })
	local _, nextFill = UI.Progress(nextCard, T.green, 3)
	refs.nextFill = nextFill
	refs.nextButton = UI.Button(nextCard, "Öffnen", T.green, function()
		local tab = refs.nextTab or "goals"
		if UI.Pages[tab] then
			UI.Show(tab)
		elseif ctx.OpenTablet then
			-- Ziele der 2.4.0-Werkstatt (z. B. "workshop") öffnen das Tablet
			ctx.OpenTablet(tab)
		else
			UI.Show("goals")
		end
	end, { LayoutOrder = 4 })

	local workshop = UI.Card(page, 3)
	UI.Title(workshop, "Deine Werkstatt", 1)
	refs.workshop = UI.Label(workshop, "", { LayoutOrder = 2 })
	refs.workshopButton = UI.Button(workshop, "Aufträge ansehen", T.blue, function()
		if ctx.OpenTablet then
			ctx.OpenTablet("workshop")
		end
	end, { LayoutOrder = 3, Visible = ctx.OpenTablet ~= nil })

	local games = UI.Card(page, 4)
	UI.Title(games, "Minispiele", 1)
	UI.Small(games, "Kurz: Schrottpresse · Mittel: Schrottplatz, Quiz, Parkplatz · Lang: Tuning-Garage, Tagesziele, Meilensteine, Rebirth", 2)
	refs.games = UI.Label(games, "", { LayoutOrder = 3, TextSize = 15 })
	UI.Button(games, "Schnellreise", T.blue, function()
		UI.Show("map")
	end, { LayoutOrder = 4 })

	local boni = UI.Card(page, 5)
	UI.Title(boni, "Aktive Boni", 1)
	refs.boni = UI.Label(boni, "", { LayoutOrder = 2, TextSize = 15 })
end

function OverviewUI.Render(s)
	local N = MiniLocale.Number
	local need = math.max(1, s.xpNeeded or 1)
	refs.career.Text = string.format(
		"Level %d · %s / %s XP · Ruf %s\n%s · %s · %d Altteile",
		s.level or 1, N(s.xp or 0), N(need), N(s.reputation or 0),
		MiniLocale.Credits(s.credits or 0), MiniLocale.Scrap(s.press and s.press.scrap or 0), s.parts or 0
	)
	UI.SetProgress(refs.xpFill, (s.xp or 0) / need)

	local n = s.goals and s.goals.next
	if n then
		refs.next.Text = n.text or ""
		refs.nextTab = n.tab
		UI.SetProgress(refs.nextFill, n.progress or 0)
	else
		refs.next.Text = "Alle Ziele erledigt."
		refs.nextTab = "goals"
		UI.SetProgress(refs.nextFill, 1)
	end

	local wj = s.workshopJobs or {}
	local total, ready = wj.total or 0, wj.ready or 0
	if total == 0 then
		refs.workshop.Text = "Keine Kundenautos in Arbeit. Neue Aufträge nimmst du am Empfang deiner Werkstatt an."
	else
		refs.workshop.Text = string.format("%d %s in Arbeit · %d bereit zur Abrechnung", total, total == 1 and "Auftrag" or "Aufträge", ready)
	end

	local lines = {}
	local p = s.press
	if p then
		table.insert(lines, string.format("Schrottpresse: %s pro Sek. · Rebirths %d", N(p.machinePerSecond or 0), p.rebirths or 0))
	end
	local tu = s.tuning
	if tu then
		local tuningReady = 0
		for _, pj in ipairs(tu.projects or {}) do
			if (pj.remaining or 0) <= 0 then
				tuningReady += 1
			end
		end
		table.insert(lines, string.format("Tuning: %d/%d Plätze belegt, %d abholbereit, passiv %s bereit", #(tu.projects or {}), tu.slots or 0, tuningReady, MiniLocale.Credits(tu.pendingIdle or 0)))
	end
	if s.scrapyard then
		table.insert(lines, "Schrottplatz: " .. (s.scrapyard.vehicle and "Fahrzeug wartet aufs Zerlegen" or "kein Fahrzeug"))
	end
	if s.quiz then
		table.insert(lines, string.format("Quiz: %d Diagnosepunkte · Reparaturzeit −%s", s.quiz.diagPoints or 0, pct(s.quiz.reduction or 0)))
	end
	if s.parking then
		table.insert(lines, string.format("Parkplatz: Serie %d (beste %d)", s.parking.streak or 0, s.parking.best or 0))
	end
	refs.games.Text = table.concat(lines, "\n")

	local boni = s.goals and s.goals.boni
	if type(boni) == "table" and #boni > 0 then
		refs.boni.Text = "· " .. table.concat(boni, "\n· ")
	else
		refs.boni.Text = "Noch keine Boni aktiv."
	end
end

return OverviewUI
