-- LobbyUI: Tab „Lobby“ (docs/PHASE4_CONTRACT.md §5): große Modus-Karten „Tycoon“ / „Open World“,
-- Einstellungen (Einzelspieler/Mehrspieler, Passiv-Modus, Beginner-Modus) mit Erklärungen, Party-Tafel (Code,
-- Mitglieder, erstellen/beitreten/verlassen, Entfernen für den Leiter), „Los geht's“ und – außerhalb der Lobby –
-- „Zurück zur Lobby“. Der Client zeigt nur an und sendet Absichten (lobby_mode, lobby_settings, lobby_go, lobby_return,
-- party_*); Modus, Party und Einstellungen kommen vom Server (Snapshot-Felder aus LobbyService.SnapshotFields).
-- Schnittstelle wie die anderen Bereiche: Build(page, ctx), Render(s), OnShow(), OnNotice(data) für
-- mini_notice { kind = "mode" | "party" | "lobby" }. Handy-tauglich: eine Spalte, Knöpfe mindestens 44 px.
-- Abschnitt „Tutorial“ (Tutorial-Kiosk): die Schritte als Liste und „Tutorial erneut starten“ (tutorial_restart,
-- nur nach Ende/Überspringen; die Belohnung gibt es nicht noch einmal). Solange GameConfig.Tycoon leer ist
-- (Meilenstein 4), zeigt die Karte „Tycoon“ den Zustand „Eröffnet bald“.
local Players = game:GetService("Players")
local Mini = game:GetService("ReplicatedStorage"):WaitForChild("GarageShared"):WaitForChild("Mini")
local GameConfig = require(Mini:WaitForChild("GameConfig"))

local LobbyUI = {}

LobbyUI.ModeCardHeight = 132 -- Mindesthöhe der Modus-Karten (AutomaticSize.Y wächst bei längeren Texten)

local UI, Remote, T, ctx
local refs = {}
local latest = nil
local pendingChoice = nil -- lokal gewählter Modus, bis der Snapshot ihn bestätigt
local settingsRows = {}

local MODES = {
	{
		key = "tycoon", title = "Tycoon", color = nil,
		desc = "Eine Tycoon-Runde mit Bargeld: Wähle ein Gebäude, kauf Upgrades und bau es bis Stufe 5 aus. Fertige Runden bringen Boni für die Werkstattmeile.",
	},
	{
		key = "openworld", title = "Open World", color = nil,
		desc = "Die Werkstattmeile: deine Werkstatt, die Stadt mit Autohaus, Teststrecke, Auktion und Spielhalle – und die Story vom Kiesplatzhändler zum Mega-Verkäufer.",
	},
}

local SETTINGS = {
	{ key = "single", title = "Einzelspieler", onText = "Einzelspieler", offText = "Mehrspieler", desc = "Einzelspieler: Du reist in einen eigenen Server ohne andere Spieler. Mehrspieler: Du triffst andere in der Stadt und im Tycoon." },
	{ key = "passive", title = "Passiv-Modus", onText = "An", offText = "Aus", desc = "An: In der Open World nur zuschauen und handeln – keine Missionen, keine Story, keine Auktionen. Tuning-Projekte und Gebäude verdienen weiter." },
	{ key = "beginner", title = "Beginner-Modus", onText = "An", offText = "Aus", desc = "An: Hinweise zu neuen Bereichen, Tutorial-Erinnerung und einfachere Erklärungen. Keine Vorteile im Spiel – nur mehr Hilfe." },
}

local MODE_TEXT = {
	lobby = "Du bist in der Lobby.",
	openworld = "Du bist in der Werkstattmeile (Open World).",
	tycoon = "Du bist im Tycoon.",
}

-- Gibt es den Tycoon schon (TycoonService, Meilenstein 4)? Solange GameConfig.Tycoon leer ist: nein.
local function tycoonOpen(): boolean
	local t = GameConfig.Tycoon
	return type(t) == "table" and next(t) ~= nil
end

local function toast(text: string)
	if ctx and type(ctx.Toast) == "function" and type(text) == "string" and text ~= "" then
		ctx.Toast(text)
	end
end

local function modeTitle(mode: any): string
	for _, m in ipairs(MODES) do
		if m.key == mode then
			return m.title
		end
	end
	return mode == "lobby" and "Lobby" or tostring(mode)
end

local function currentSettings(): { single: boolean, passive: boolean, beginner: boolean }
	local m = latest and type(latest.meta) == "table" and latest.meta or {}
	return { single = m.single == true, passive = m.passive == true, beginner = m.beginner == true }
end

---------------------------------------------------------------- Bausteine
local function modeCard(parent, spec, order: number)
	local color = spec.key == "tycoon" and T.blue or T.green
	local button = UI.Button(parent, "", color, function()
		pendingChoice = spec.key
		Remote.Send("lobby_mode", { mode = spec.key })
		LobbyUI.Render(latest)
	end, { Name = "ModeCard_" .. spec.key, LayoutOrder = order, Size = UDim2.new(1, 0, 0, LobbyUI.ModeCardHeight), AutomaticSize = Enum.AutomaticSize.Y, Text = "" })
	local inner = UI.Frame(button, { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 0) })
	UI.Padding(inner, 14, 12)
	UI.List(inner, 4)
	local title = UI.Label(inner, spec.title, { Font = UI.FontBig, TextSize = 22, LayoutOrder = 1, Name = "Title" })
	local desc = UI.Label(inner, spec.desc, { TextSize = 15, LayoutOrder = 2, Name = "Desc" })
	local state = UI.Label(inner, "", { Font = UI.FontBold, TextSize = 14, LayoutOrder = 3, Name = "State" })
	return { root = button, title = title, desc = desc, state = state, key = spec.key, color = color }
end

local function settingRow(parent, spec, order: number)
	local row, left, right = UI.Row(parent, order)
	row.Name = "Setting_" .. spec.key
	UI.Label(left, spec.title, { Font = UI.FontBold, TextSize = 16, LayoutOrder = 1 })
	UI.Small(left, spec.desc, 2)
	local item = { key = spec.key, spec = spec, root = row }
	item.button = UI.Button(right, spec.offText, T.line, function()
		local s = currentSettings()
		s[spec.key] = not s[spec.key]
		Remote.Send("lobby_settings", { single = s.single, passive = s.passive, beginner = s.beginner })
	end, { Name = "Toggle_" .. spec.key, TextSize = 14 })
	return item
end

local function memberRow(parent, i: number)
	local row, left, right = UI.Row(parent, 20 + i)
	row.Name = "Member_" .. i
	local name = UI.Label(left, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 1 })
	local sub = UI.Small(left, "", 2)
	local item = { root = row, name = name, sub = sub, userId = nil }
	item.button = UI.Button(right, "Entfernen", T.red or T.line, function()
		if item.userId then
			Remote.Send("party_kick", { userId = item.userId })
		end
	end, { Name = "Kick_" .. i, TextSize = 14 })
	return item
end

---------------------------------------------------------------- Aufbau
function LobbyUI.Build(page, c)
	ctx = c
	UI, Remote = c.UI, c.Remote
	T = UI.Theme

	-- Wo bin ich?
	local status = UI.Card(page, 1)
	status.Name = "StatusCard"
	UI.Title(status, "Lobby", 1)
	refs.where = UI.Label(status, MODE_TEXT.lobby, { LayoutOrder = 2, Name = "Where" })
	refs.simulation = UI.Small(status, GameConfig.SimulationNotice, 3)
	refs.simulation.Name = "Simulation"
	refs.returnButton = UI.Button(status, "Zurück zur Lobby", T.blue, function()
		Remote.Send("lobby_return")
	end, { Name = "ReturnButton", LayoutOrder = 4 })

	-- Modus-Karten
	local modes = UI.Card(page, 2)
	modes.Name = "ModeCardsCard"
	UI.Title(modes, "Wohin soll es gehen?", 1)
	UI.Small(modes, "Wähle einen Modus und drück „Los geht's“. Du kannst jederzeit in die Lobby zurück.", 2)
	refs.modes = {}
	for i, spec in ipairs(MODES) do
		refs.modes[spec.key] = modeCard(modes, spec, 10 + i)
	end
	refs.goButton = UI.Button(modes, "Los geht's", T.green, function()
		Remote.Send("lobby_go")
	end, { Name = "GoButton", LayoutOrder = 20, TextSize = 18, Size = UDim2.new(1, 0, 0, 52) })
	refs.goHint = UI.Small(modes, "", 21)
	refs.goHint.Name = "GoHint"

	-- Einstellungen
	local settings = UI.Card(page, 3)
	settings.Name = "SettingsCard"
	UI.Title(settings, "Einstellungen", 1)
	UI.Small(settings, "Wirken sofort und bleiben gespeichert.", 2)
	settingsRows = {}
	for i, spec in ipairs(SETTINGS) do
		settingsRows[spec.key] = settingRow(settings, spec, 10 + i)
	end

	-- Party
	local party = UI.Card(page, 4)
	party.Name = "PartyCard"
	UI.Title(party, "Party", 1)
	UI.Small(party, "Bis zu " .. tostring(GameConfig.Party.MaxMembers) .. " Spieler reisen zusammen. Der Leiter startet die Reise, Story-Missionen zählen für alle. Partys gelten nur im selben Server.", 2)
	refs.partyStatus = UI.Label(party, "Du bist in keiner Party.", { Font = UI.FontBold, TextSize = 16, LayoutOrder = 3, Name = "PartyStatus" })
	refs.partyCode = UI.Label(party, "", { Font = UI.FontBig, TextSize = 28, LayoutOrder = 4, Name = "PartyCode", TextXAlignment = Enum.TextXAlignment.Center })
	refs.members = UI.Pool(party, memberRow)

	local joinRow = UI.Frame(party, { BackgroundTransparency = 1, LayoutOrder = 40, Size = UDim2.new(1, 0, 0, UI.MinTouch), AutomaticSize = Enum.AutomaticSize.None })
	joinRow.Name = "JoinRow"
	local box = Instance.new("TextBox")
	box.Name = "PartyCodeBox"
	box.Size = UDim2.new(1, -(UI.RowButtonWidth + 10), 1, 0)
	box.BackgroundColor3 = T.bg
	box.BorderSizePixel = 0
	box.Font = UI.FontBold
	box.TextSize = 20
	box.TextColor3 = T.text
	box.PlaceholderText = "Party-Code"
	box.PlaceholderColor3 = T.muted
	box.Text = ""
	box.ClearTextOnFocus = false
	box.TextXAlignment = Enum.TextXAlignment.Center
	UI.Corner(box, 8)
	box.Parent = joinRow
	refs.codeBox = box
	local function sendJoin()
		local code = string.upper((string.gsub(box.Text or "", "%s", "")))
		if #code ~= GameConfig.Party.CodeLength then
			toast("Ein Party-Code hat " .. tostring(GameConfig.Party.CodeLength) .. " Zeichen.")
			return
		end
		Remote.Send("party_join", { code = code })
	end
	box.FocusLost:Connect(function(enterPressed)
		if enterPressed then
			sendJoin()
		end
	end)
	refs.joinButton = UI.Button(joinRow, "Beitreten", T.green, sendJoin, {
		Name = "PartyJoin", Size = UDim2.new(0, UI.RowButtonWidth, 1, 0), Position = UDim2.new(1, -UI.RowButtonWidth, 0, 0),
	})
	refs.createButton = UI.Button(party, "Party erstellen", T.blue, function()
		Remote.Send("party_create")
	end, { Name = "PartyCreate", LayoutOrder = 41 })
	refs.leaveButton = UI.Button(party, "Party verlassen", T.line, function()
		Remote.Send("party_leave")
	end, { Name = "PartyLeave", LayoutOrder = 42 })

	-- Tutorial (Tutorial-Kiosk): Schritte und Neustart
	local tutorial = UI.Card(page, 5)
	tutorial.Name = "TutorialCard"
	UI.Title(tutorial, "Tutorial", 1)
	refs.tutorialStatus = UI.Label(tutorial, "", { Font = UI.FontBold, TextSize = 15, LayoutOrder = 2, Name = "TutorialStatus" })
	local steps = {}
	for i, st in ipairs(GameConfig.Tutorial.Steps) do
		table.insert(steps, tostring(i) .. ". " .. tostring(st.text))
	end
	local stepList = UI.Small(tutorial, table.concat(steps, "\n"), 3)
	stepList.Name = "TutorialSteps"
	refs.tutorialRestart = UI.Button(tutorial, "Tutorial erneut starten", T.blue, function()
		Remote.Send("tutorial_restart")
	end, { Name = "TutorialRestart", LayoutOrder = 4 })
	refs.tutorialHint = UI.Small(tutorial, "", 5)
	refs.tutorialHint.Name = "TutorialHint"

	LobbyUI.Render(nil)
end

---------------------------------------------------------------- Anzeige
function LobbyUI.Render(s)
	if type(s) == "table" then
		latest = s
	end
	s = latest or {}
	if not refs.where then
		return
	end
	local mode = type(s.mode) == "string" and s.mode or "lobby"
	local inLobby = mode == "lobby"
	refs.where.Text = MODE_TEXT[mode] or MODE_TEXT.lobby
	refs.simulation.Visible = s.simulated == true
	refs.returnButton.Visible = not inLobby

	-- Auswahl: Snapshot-Auswahl gewinnt, sonst die lokale, bis der Server sie bestätigt
	local choice = type(s.choice) == "string" and s.choice or nil
	if choice then
		pendingChoice = nil
	else
		choice = pendingChoice
	end
	for key, card in pairs(refs.modes) do
		local selected = choice == key
		local here = mode == key
		card.root.BackgroundColor3 = selected and card.color or T.card
		card.root:SetAttribute("baseColor", card.root.BackgroundColor3)
		local state = here and "Du bist hier." or (selected and "Ausgewählt" or "Antippen zum Auswählen")
		if key == "tycoon" and not tycoonOpen() then
			state = "Eröffnet bald – das Gelände kannst du schon ansehen. " .. state
		end
		card.state.Text = state
	end
	local target = choice or ((mode ~= "lobby") and mode) or "openworld"
	local party = type(s.party) == "table" and s.party or nil
	local isLeader = party == nil or party.isLeader == true
	-- Mitglied, dessen Leiter schon in Open World/Tycoon ist: „Los geht's“ bringt es zum Leiter (Server prüft)
	local leaderMode = party and type(party.leaderMode) == "string" and party.leaderMode or "lobby"
	local toLeader = not isLeader and leaderMode ~= "lobby" and leaderMode ~= mode
	-- Leiter am Ziel, Mitglieder woanders: „Los geht's“ holt sie nach
	local fetch = isLeader and party ~= nil and party.away == true and target == mode and mode ~= "lobby"
	if toLeader then
		target = leaderMode
	end
	refs.goButton.Text = fetch and "Party zu mir holen" or ("Los geht's: " .. modeTitle(target))
	UI.SetEnabled(refs.goButton, (isLeader and (target ~= mode or fetch)) or toLeader, T.green)
	if toLeader then
		refs.goHint.Text = "Dein Party-Leiter ist schon dort – du reist zu ihm."
	elseif fetch then
		refs.goHint.Text = "Deine Party ist noch woanders. Hol sie zu dir!"
	elseif not isLeader then
		refs.goHint.Text = "Nur der Party-Leiter startet die Reise – du reist automatisch mit."
	elseif target == mode then
		refs.goHint.Text = "Du bist schon hier. Wähle einen anderen Modus."
	elseif party then
		refs.goHint.Text = "Deine Party reist mit dir."
	else
		refs.goHint.Text = ""
	end
	refs.goHint.Visible = refs.goHint.Text ~= ""

	-- Einstellungen
	local settings = currentSettings()
	for key, item in pairs(settingsRows) do
		local on = settings[key] == true
		item.button.Text = on and item.spec.onText or item.spec.offText
		UI.SetEnabled(item.button, true, on and T.green or T.line)
	end

	-- Party
	if party then
		refs.partyStatus.Text = party.isLeader and "Du leitest die Party." or ("Party von " .. tostring(party.leaderName or "?") .. ".")
		refs.partyCode.Text = "Code: " .. tostring(party.code or "") .. "  ·  " .. tostring(#(party.members or {})) .. "/" .. tostring(party.max or GameConfig.Party.MaxMembers)
		refs.partyCode.Visible = true
		local members = party.members or {}
		refs.members:Ensure(#members)
		for i, m in ipairs(members) do
			local item = refs.members.items[i]
			item.userId = m.userId
			item.name.Text = tostring(m.name or ("Spieler " .. tostring(m.userId)))
			item.sub.Text = m.leader and "Party-Leiter" or "Mitglied"
			item.button.Visible = party.isLeader == true and not m.leader
		end
	else
		refs.partyStatus.Text = "Du bist in keiner Party."
		refs.partyCode.Text = ""
		refs.partyCode.Visible = false
		refs.members:Ensure(0)
	end
	refs.createButton.Visible = party == nil
	refs.codeBox.Parent.Visible = party == nil
	refs.leaveButton.Visible = party ~= nil

	-- Tutorial
	if refs.tutorialStatus then
		local meta = type(s.meta) == "table" and s.meta or {}
		local tut = type(s.tutorial) == "table" and s.tutorial or {}
		local done = meta.tutorialDone == true or tut.done == true
		local count = #GameConfig.Tutorial.Steps
		if done then
			refs.tutorialStatus.Text = tut.skipped and "Du hast das Tutorial übersprungen." or "Du hast das Tutorial geschafft."
			refs.tutorialHint.Text = tut.rewarded and "Noch einmal von vorn – die Belohnung hattest du schon."
				or "Noch einmal von vorn: Am Ende warten " .. tostring(GameConfig.Tutorial.Reward.credits) .. " Credits und " .. tostring(GameConfig.Tutorial.Reward.xp) .. " XP."
		else
			refs.tutorialStatus.Text = "Das Tutorial läuft: Schritt " .. tostring(meta.tutorialStep or tut.step or 1) .. " von " .. tostring(count) .. (inLobby and " – es geht in der Werkstattmeile weiter." or ".")
			refs.tutorialHint.Text = "Die Tutorial-Karte siehst du in der Open World."
		end
		UI.SetEnabled(refs.tutorialRestart, done, T.blue)
	end
end

function LobbyUI.OnShow()
	LobbyUI.Render(latest)
end

-- mini_notice { kind = "mode" | "party" | "lobby" }
function LobbyUI.OnNotice(data)
	if type(data) ~= "table" then
		return
	end
	local kind = data.kind
	if kind == "mode" then
		pendingChoice = nil
		if data.simulated then
			toast(GameConfig.SimulationNotice)
		end
		if ctx and type(ctx.Close) == "function" and data.mode ~= "lobby" then
			ctx.Close() -- Reise: Panel weg, damit die Ankunft zu sehen ist
		end
	elseif kind == "party" then
		local name = tostring(data.name or "Ein Spieler")
		local ev = data.event
		if ev == "joined" then
			toast(name .. " ist der Party beigetreten.")
		elseif ev == "left" then
			toast(name .. " hat die Party verlassen.")
		elseif ev == "kicked" then
			local me = Players.LocalPlayer
			if not (me and data.userId == me.UserId) then
				toast(name .. " wurde aus der Party entfernt.") -- den eigenen Rauswurf meldet der Server per Toast
			end
		elseif ev == "leader" then
			toast(name .. " ist jetzt Party-Leiter.")
		elseif ev == "travel" then
			toast("Party-Leiter " .. name .. " startet: " .. modeTitle(data.mode) .. ". Du reist mit!")
		elseif ev == "created" and refs.codeBox then
			refs.codeBox.Text = ""
		end
	elseif kind == "lobby" then
		local action = data.action
		if action == "mode_tycoon" or action == "mode_openworld" then
			pendingChoice = string.sub(action, 6)
			LobbyUI.Render(latest)
		elseif action == "tutorial" then
			-- Tutorial-Kiosk: zum Abschnitt „Tutorial“ blättern (Inhalt ist eine ScrollingFrame)
			LobbyUI.Render(latest)
			local card = refs.tutorialStatus and refs.tutorialStatus.Parent
			local content = UI and UI.Content
			if card and content and content:IsA("ScrollingFrame") then
				pcall(function()
					local y = card.AbsolutePosition.Y - content.AbsolutePosition.Y + content.CanvasPosition.Y
					content.CanvasPosition = Vector2.new(0, math.max(0, y - 8))
				end)
			end
		end
	end
end

return LobbyUI
