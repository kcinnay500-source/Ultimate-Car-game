-- OverviewUI: Karriere, nächstes Ziel, Kurzüberblick aller Spiele und aktive Boni.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local OverviewUI = {}

local UI, T
local refs = {}

function OverviewUI.Build(page, ctx)
	UI = ctx.UI
	T = UI.Theme

	local career = UI.Card(page, 1)
	UI.Title(career, "Deine Karriere", 1)
	refs.career = UI.Label(career, "", { LayoutOrder = 2 })
	local _, xpFill = UI.Progress(career, T.accent2, 3)
	refs.xpFill = xpFill

	local nextCard = UI.Card(page, 2)
	UI.Title(nextCard, "Nächstes Ziel", 1)
	refs.next = UI.Label(nextCard, "", { LayoutOrder = 2 })
	local _, nextFill = UI.Progress(nextCard, T.accent, 3)
	refs.nextFill = nextFill
	refs.nextButton = UI.Button(nextCard, "Hingehen", T.accent, function()
		UI.Show(refs.nextTab or "overview")
	end, { LayoutOrder = 4 })

	local games = UI.Card(page, 3)
	UI.Title(games, "Spiele", 1)
	UI.Small(games, "Kurz: Schrottpresse · Mittel: Werkstatt, Schrottplatz, Quiz, Parkplatz · Lang: Tuning-Garage, Tagesziele, Meilensteine, Rebirth", 2)
	refs.games = UI.Label(games, "", { LayoutOrder = 3, TextSize = 15 })

	local boni = UI.Card(page, 4)
	UI.Title(boni, "Aktive Boni", 1)
	refs.boni = UI.Label(boni, "", { LayoutOrder = 2, TextSize = 15 })
end

function OverviewUI.Render(s)
	refs.career.Text = string.format("Level %d · %s XP von %s · Ruf %d\n%s · %s · Lager %d Teile", s.level, Locale.Number(s.xp), Locale.Number(s.xpNeeded), s.reputation, Locale.Credits(s.credits), Locale.Scrap(s.press.scrap), s.parts)
	UI.SetProgress(refs.xpFill, s.xp / s.xpNeeded)
	local n = s.goals.next
	refs.next.Text = n.text
	refs.nextTab = n.tab
	UI.SetProgress(refs.nextFill, n.progress)

	local ready = 0
	for _, j in ipairs(s.workshop.jobs) do
		if s.now >= j.endsAt then
			ready += 1
		end
	end
	local tuningReady = 0
	for _, pj in ipairs(s.tuning.projects) do
		if pj.remaining <= 0 then
			tuningReady += 1
		end
	end
	refs.games.Text = table.concat({
		string.format("🚘 Schrottpresse: %s/Sek. · Rebirths %d", Locale.Number(s.press.machinePerSecond), s.press.rebirths),
		string.format("🔧 Werkstatt: %d Aufträge laufen, %d fertig, %d Bühne(n) frei", #s.workshop.jobs, ready, math.max(0, s.workshop.available)),
		string.format("🏁 Tuning: %d/%d Plätze belegt, %d abholbereit, passiv %s bereit", #s.tuning.projects, s.tuning.slots, tuningReady, Locale.Credits(s.tuning.pendingIdle)),
		string.format("♻️ Schrottplatz: %s", s.scrapyard.vehicle and "Fahrzeug wartet aufs Zerlegen" or "kein Fahrzeug"),
		string.format("🧠 Quiz: %d Diagnosepunkte", s.quiz.diagPoints),
		string.format("🚙 Parkplatz: Serie %d", s.parking.streak),
	}, "\n")
	refs.boni.Text = "• " .. table.concat(s.goals.boni, "\n• ")
end

return OverviewUI
