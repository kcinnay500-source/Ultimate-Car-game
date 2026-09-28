-- QuizUI: Mechaniker-Quiz. Auswertung passiert ausschließlich auf dem Server.
local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Locale = require(Shared:WaitForChild("Locale"))

local QuizUI = {}

local UI, Remote, T
local refs = {}
local shownToken = nil
local answered = false

function QuizUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Mechaniker-Quiz", 1)
	refs.info = UI.Small(card, "", 2)
	refs.question = UI.Label(card, "Starte eine Frage. Richtige Antworten geben Diagnosepunkte, die alle Reparaturen verkürzen.", { LayoutOrder = 3, TextSize = 17 })
	refs.answers = {}
	for i = 1, 4 do
		refs.answers[i] = UI.Button(card, "", T.panel, function()
			if shownToken and not answered then
				answered = true
				for _, b in ipairs(refs.answers) do
					UI.SetEnabled(b, false)
				end
				Remote.Send("quiz_answer", { token = shownToken, choice = i })
			end
		end, { LayoutOrder = 3 + i, TextColor3 = T.text, Visible = false })
	end
	refs.next = UI.Button(card, "Neue Frage", T.purple, function()
		Remote.Send("quiz_new")
	end, { LayoutOrder = 9 })
end

function QuizUI.OnResult(res)
	for i, b in ipairs(refs.answers) do
		if i == res.correctPos then
			b.BackgroundColor3 = T.accent
			b.TextColor3 = Color3.fromRGB(7, 17, 27)
		elseif i == res.choice then
			b.BackgroundColor3 = T.danger
		end
	end
	UI.Toast(res.correct and ("Richtig! +" .. Locale.Credits(res.credits) .. " und ein Diagnosepunkt") or "Nicht ganz. Die richtige Antwort ist grün markiert.")
end

function QuizUI.Render(s)
	local q = s.quiz
	refs.info.Text = string.format("Diagnosepunkte: %d · Reparaturzeit −%s (höchstens 35 %%)", q.diagPoints, Locale.Percent(q.reduction))
	local view = q.question
	if view and view.token ~= shownToken then
		shownToken = view.token
		answered = false
		refs.question.Text = view.text
		for i, b in ipairs(refs.answers) do
			b.Text = view.answers[i] or ""
			b.Visible = true
			b:SetAttribute("disabled", false)
			b.BackgroundColor3 = T.panel
			b.TextColor3 = T.text
			b.AutoButtonColor = true
		end
	end
	refs.next.Text = (view and not answered) and "Andere Frage" or "Neue Frage"
end

return QuizUI
