-- QuizUI: Mechaniker-Quiz. Auswertung ausschließlich auf dem Server (mini_notice kind "quiz").
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local MiniLocale = require(Mini:WaitForChild("MiniLocale"))

local QuizUI = {}

local UI, Remote, T
local refs = {}
local shownToken = nil
local answered = false

local function resetAnswer(b, text)
	b.Text = text or ""
	b.Visible = text ~= nil and text ~= ""
	UI.SetEnabled(b, true, T.blue)
end

function QuizUI.Build(page, ctx)
	UI, Remote = ctx.UI, ctx.Remote
	T = UI.Theme
	local card = UI.Card(page, 1)
	UI.Title(card, "Mechaniker-Quiz", 1)
	refs.info = UI.Small(card, "", 2)
	refs.question = UI.Label(card, "Starte eine Frage. Richtige Antworten geben Diagnosepunkte, die alle Reparaturen in deiner Werkstatt verkürzen.", { LayoutOrder = 3, TextSize = 17 })
	refs.answers = {}
	for i = 1, 4 do
		refs.answers[i] = UI.Button(card, "", T.blue, function()
			if shownToken and not answered then
				answered = true
				for _, b in ipairs(refs.answers) do
					UI.SetEnabled(b, false)
				end
				Remote.Send("mini_quiz_answer", { token = shownToken, choice = i })
			end
		end, { LayoutOrder = 3 + i, Visible = false, TextXAlignment = Enum.TextXAlignment.Left, AutomaticSize = Enum.AutomaticSize.Y })
		UI.Padding(refs.answers[i], 14, 8)
	end
	refs.result = UI.Label(card, "", { LayoutOrder = 8, Font = UI.FontBold, Visible = false })
	refs.next = UI.Button(card, "Neue Frage", T.purple, function()
		Remote.Send("mini_quiz_new")
	end, { LayoutOrder = 9 })
end

-- mini_notice {kind="quiz", correct, correctPos, choice, credits}
function QuizUI.OnResult(res)
	if not refs.answers then
		return
	end
	for i, b in ipairs(refs.answers) do
		if i == res.correctPos then
			b.BackgroundColor3 = T.green
			b.TextColor3 = T.text
		elseif i == res.choice then
			b.BackgroundColor3 = T.red
			b.TextColor3 = T.text
		end
	end
	refs.result.Visible = true
	if res.correct and res.capped then
		refs.result.Text = "Richtig! Ein Diagnosepunkt. Credits gibt es heute für das Quiz keine mehr."
		refs.result.TextColor3 = T.green
	elseif res.correct then
		refs.result.Text = "Richtig! +" .. MiniLocale.Credits(tonumber(res.credits) or 0) .. " und ein Diagnosepunkt."
		refs.result.TextColor3 = T.green
	else
		refs.result.Text = "Nicht ganz. Die richtige Antwort ist grün markiert."
		refs.result.TextColor3 = T.yellow
	end
end

function QuizUI.Render(s)
	local q = s.quiz
	if not q then
		return
	end
	refs.info.Text = string.format("Diagnosepunkte: %d · Reparaturzeit −%s (höchstens 35 %%) · Heute noch %d bezahlte Antworten", q.diagPoints or 0, MiniLocale.Percent(q.reduction or 0), q.paidLeft or 0)
	local view = q.question
	if view and view.token ~= shownToken then
		shownToken = view.token
		answered = false
		refs.question.Text = view.text or ""
		refs.result.Visible = false
		for i, b in ipairs(refs.answers) do
			resetAnswer(b, view.answers and view.answers[i])
		end
	elseif not view and shownToken then
		shownToken = nil
		for _, b in ipairs(refs.answers) do
			b.Visible = false
		end
	end
	refs.next.Text = (view and not answered) and "Andere Frage" or "Neue Frage"
end

return QuizUI
