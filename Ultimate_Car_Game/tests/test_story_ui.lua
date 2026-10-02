-- Ausbaustufe 4, Meilenstein 7 (Team client): StoryUI (Tab „story“) und MissionClient (Welt-Marker, Missions-Karte,
-- Kapitel-Intro, NPC-Kunden am Kiesplatz) im Mock-Client mit gefälschten Snapshots (Ansicht über die echten StoryRules).
-- Der Client sendet nur Absichten (story_start {id}, story_claim {id}, story_sell {offer, price = Stufe}, side_claim {id},
-- mini_travel {key = "kiesplatz"}); geprüft werden gesendete Aktionen/Nutzlasten, Sperrgründe und die Sichtbarkeit.
local DAY = 86400
local NOW = 1760000000 - (1760000000 % DAY) + 3600 -- 01:00 UTC

---------------------------------------------------------------- Hilfen (wie test_tycoon_ui)
local FORBIDDEN = { amount = true, cost = true, credits = true, reward = true, money = true, cash = true, xp = true, level = true, profit = true }

local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
			T.check(not FORBIDDEN[k], action .. ": Client sendet verbotenes Feld " .. tostring(k))
		end
		T.check(n <= 10, action .. ": höchstens 10 Felder")
		table.insert(r.sent, { action = action, payload = payload })
		return #r.sent
	end
	r.SendRaw = r.Send
	function r.Last(action)
		for i = #r.sent, 1, -1 do
			if r.sent[i].action == action then
				return r.sent[i].payload
			end
		end
		return nil
	end
	function r.Count(action)
		local n = 0
		for _, s in ipairs(r.sent) do
			if s.action == action then
				n += 1
			end
		end
		return n
	end
	return r
end

local function startClient(H, opts)
	opts = opts or {}
	opts.placeKind = opts.placeKind or "openworld"
	opts.startTime = opts.startTime or NOW
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1.5)
	return g, p
end

-- Seite des Bereichs in einer eigenen ScreenGui (338 px breit wie das Panel bei 390 px Bildschirmbreite)
local function build(g, p, modName, rec, ctxExtra)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini." .. modName)
	local toasts = {}
	local state = { tablet = false, blocked = false, closed = 0 }
	local ctxOut
	local page = g:InClient(p, function()
		if not MiniUI.Gui then
			MiniUI.Build()
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "StoryTest_" .. modName
		gui.ResetOnSpawn = false
		gui.Parent = p.PlayerGui
		local frame = MiniUI.Frame(gui, { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(0, 338, 0, 0) })
		MiniUI.List(frame, 12)
		local ctx = {
			UI = MiniUI, Remote = rec,
			Toast = function(text)
				table.insert(toasts, text)
			end,
			Close = function()
				state.closed += 1
				MiniUI.Close()
			end,
			IsTabletOpen = function()
				return state.tablet
			end,
			IsBlocked = function()
				return state.blocked
			end,
		}
		for k, v in pairs(ctxExtra or {}) do
			ctx[k] = v
		end
		ctxOut = ctx
		if mod.Build then
			mod.Build(frame, ctx)
		end
		return frame
	end)
	return mod, page, MiniUI, toasts, state, ctxOut
end

local function render(g, p, mod, s)
	g:InClient(p, function()
		mod.Render(s)
	end)
end

local function find(root, pred)
	for _, x in ipairs(root:GetDescendants()) do
		if pred(x) then
			return x
		end
	end
	return nil
end

local function byName(root, name)
	return find(root, function(x)
		return x.Name == name
	end)
end

local function withText(root, text)
	return find(root, function(x)
		local t = x.Text
		return type(t) == "string" and x.Visible and t:find(text, 1, true) ~= nil
	end)
end

local function enabled(b)
	return b ~= nil and b:GetAttribute("disabled") ~= true
end

local function press(g, button, opts)
	g:Advance(0.35)
	local ok = g:Click(button, opts)
	g:Advance(0.05)
	return ok
end

-- Snapshot über die echten Regeln (StoryRules.View), damit Ids, Texte und Zustände stimmen.
-- opts: level, mode, sale (Angebot erzeugen), saleIn, passive, full (Standard true), mutate(d, SR)
local function storySnapshot(g, opts)
	opts = opts or {}
	local SR = g:MiniShared("StoryRules")
	local d = g:Rules().NewData(NOW)
	d.level = opts.level or 3
	d.money = opts.money or 500
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	SR.ApplyDefault(d.games)
	if opts.mutate then
		opts.mutate(d, SR)
	end
	local sale = false
	if opts.sale then
		sale = SR.NextSale(d, "1001:" .. tostring(opts.saleSerial or 1), d.level)
	end
	local view = SR.View(d, NOW, d.level, { sale = sale, saleIn = opts.saleIn or 0, passive = opts.passive == true }, opts.full ~= false)
	local s = {
		credits = d.money, level = d.level, mode = opts.mode or "openworld", placeKind = "openworld",
		meta = { beginner = false, passive = opts.passive == true, single = false, tutorialDone = true, tutorialStep = 10 },
		story = view,
	}
	return s, d, sale
end

local function finishChapters(d, SR, upTo)
	for c = 1, upTo do
		for _, m in ipairs(SR.Chapter(c).Missions) do
			d.games.story.done[m.id] = true
		end
	end
	SR.Recompute(d.games.story)
end

---------------------------------------------------------------- Fälle
return {
	{ "StoryUI: Kapitel 1 – Kopf mit Intro, Missionskarten (Starten → story_start, Fortschritt, Abholen → story_claim, Später), Wegweiser (mini_travel kiesplatz)", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI, toasts, state = build(g, p, "StoryUI", rec)
		local SR = g:MiniShared("StoryRules")
		local ch1 = SR.Chapter(1)
		local s = storySnapshot(g, { level = 2 })
		render(g, p, mod, s)
		T.check(byName(page, "ChapterTitle").Text == "Kapitel 1: " .. ch1.title, "Kapitel-Kopf: " .. byName(page, "ChapterTitle").Text)
		T.check(byName(page, "Intro").Visible and byName(page, "Intro").Text == ch1.intro, "Intro-Text (Erzählstimme)")
		T.check(byName(page, "ChapterProgress").Text:find("Mission 1 von 3", 1, true) ~= nil, "Fortschritt: " .. byName(page, "ChapterProgress").Text)
		T.eq(byName(page, "ChapterNote").Visible, false, "kein Sperrhinweis in Kapitel 1")
		-- Missionskarten
		for i, m in ipairs(ch1.Missions) do
			local row = byName(page, "Mission_" .. i)
			T.check(row ~= nil and row.Visible, "Zeile " .. i)
			T.check(withText(row, m.title) ~= nil, "Titel " .. m.id)
			T.check(withText(row, m.text) ~= nil, "Text " .. m.id)
			T.check(withText(row, "Belohnung: " .. tostring(m.reward.credits)) ~= nil, "Belohnung " .. m.id)
			local b = byName(page, "MissionButton_" .. i)
			T.check(b ~= nil and b.AbsoluteSize.Y >= 44, "Knopf ≥ 44 px " .. m.id)
		end
		local b1, b2, b3 = byName(page, "MissionButton_1"), byName(page, "MissionButton_2"), byName(page, "MissionButton_3")
		T.check(enabled(b1) and b1.Text == "Starten", "Mission 1 startbar: " .. b1.Text)
		T.check(not enabled(b2) and b2.Text == "Später", "Mission 2 wartet: " .. b2.Text)
		T.check(not enabled(b3) and b3.Text == "Später", "Mission 3 später: " .. b3.Text)
		T.check(withText(byName(page, "Mission_3"), "der Reihe nach") ~= nil, "Sperrgrund Reihenfolge")
		press(g, b2)
		press(g, b3)
		T.eq(#rec.sent, 0, "gesperrte Knöpfe senden nichts")
		press(g, b1)
		local sent = rec.Last("story_start")
		T.check(sent ~= nil and sent.id == "c1_m1", "story_start c1_m1")
		T.eq(rec.Count("story_start"), 1, "genau einmal")
		-- Wegweiser: Mission 1 spielt am Kiesplatz → Karte sichtbar, Schnellreise sendet mini_travel {key = kiesplatz} und schließt
		local mapCard = byName(page, "MapHintCard")
		T.check(mapCard.Visible, "Wegweiser sichtbar")
		T.check(withText(mapCard, "Gehe zum Kiesplatz") ~= nil, "Text „Gehe zum Kiesplatz“")
		local travel = byName(page, "TravelButton")
		T.check(enabled(travel) and travel.AbsoluteSize.Y >= 44, "Schnellreise-Knopf")
		press(g, travel)
		sent = rec.Last("mini_travel")
		T.check(sent ~= nil and sent.key == "kiesplatz", "mini_travel {key = kiesplatz}")
		T.eq(state.closed, 1, "Panel geschlossen (ctx.Close)")
		-- aktiv mit Fortschritt 1/3: Knopf zeigt den Stand, nichts sendbar
		s = storySnapshot(g, { level = 2, mutate = function(d, R)
			R.Start(d, "c1_m1", NOW, 0, 2)
			d.games.story.active.progress = 1
		end })
		render(g, p, mod, s)
		b1 = byName(page, "MissionButton_1")
		T.check(not enabled(b1) and b1.Text == "1 / 3", "läuft 1/3: " .. b1.Text)
		T.check(withText(byName(page, "Mission_1"), "Läuft") ~= nil, "Hinweis läuft")
		T.check(withText(byName(page, "Mission_2"), "Erst „Drei Gebrauchtwagen verkaufen“ erledigen") ~= nil, "Sperrgrund nennt die laufende Mission")
		T.check(byName(page, "ChapterProgress").Text:find("läuft", 1, true) ~= nil, "Kopf nennt die laufende Mission")
		press(g, b1)
		T.eq(rec.Count("story_claim"), 0, "unfertig: kein story_claim")
		-- Fortschritt per mini_notice sofort in den Balken (ohne Snapshot)
		local fill = byName(page, "Mission_1"):FindFirstChild("Bar", true):GetChildren()[2]
		g:InClient(p, function()
			mod.OnNotice({ kind = "mission", id = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", progress = 2, target = 3, done = false, side = false })
		end)
		T.check(fill and math.abs(fill.Size.X.Scale - 2 / 3) < 0.01, "Balken 2/3 nach Hinweis")
		-- erfüllt: Abholen → story_claim {id}
		s = storySnapshot(g, { level = 2, mutate = function(d, R)
			R.Start(d, "c1_m1", NOW, 0, 2)
			d.games.story.active.progress = 3
		end })
		render(g, p, mod, s)
		b1 = byName(page, "MissionButton_1")
		T.check(enabled(b1) and b1.Text == "Abholen", "Abholen: " .. b1.Text)
		press(g, b1)
		sent = rec.Last("story_claim")
		T.check(sent ~= nil and sent.id == "c1_m1", "story_claim c1_m1")
		-- kleiner Snapshot ohne missions: Liste bleibt (sticky), Zustand aus active nachgezogen
		local small = storySnapshot(g, { level = 2, full = false, mutate = function(d, R)
			R.Start(d, "c1_m1", NOW, 0, 2)
			d.games.story.active.progress = 2
		end })
		T.eq(small.story.missions, nil, "kleiner Snapshot ohne Liste")
		render(g, p, mod, small)
		T.check(byName(page, "Mission_1").Visible and byName(page, "Mission_3").Visible, "Zeilen bleiben (sticky)")
		T.check(byName(page, "MissionButton_1").Text == "2 / 3", "Stand aus dem kleinen Snapshot: " .. byName(page, "MissionButton_1").Text)
		-- Mission 1 erledigt: Erledigt ✓, Mission 2 startbar (kind event, Werkstatt) → Wegweiser weg
		s = storySnapshot(g, { level = 2, mutate = function(d)
			d.games.story.done.c1_m1 = true
			d.games.story.step = 2
		end })
		render(g, p, mod, s)
		T.check(byName(page, "MissionButton_1").Text == "Erledigt ✓" and not enabled(byName(page, "MissionButton_1")), "Mission 1 erledigt")
		T.check(enabled(byName(page, "MissionButton_2")) and byName(page, "MissionButton_2").Text == "Starten", "Mission 2 startbar")
		T.eq(byName(page, "MapHintCard").Visible, false, "Wegweiser nur für Kiesplatz-Missionen")
		T.eq(byName(page, "ChaptersCard").Visible, true, "Kapitelübersicht (voller Snapshot)")
		T.check(withText(byName(page, "ChaptersCard"), "Kapitel 2: " .. SR.Chapter(2).title) ~= nil, "Übersicht nennt Kapitel 2")
		T.eq(#toasts, 0, "keine eigenen Toasts")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "StoryUI: Kiesplatz-Verkauf – Kunde (Name, Wunsch, Spruch), drei Preisknöpfe mit Preis/Gewinn und Risiko, story_sell {offer, price}, Sperre bis zur Antwort, Ergebnis-Animation, Countdown", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI, toasts = build(g, p, "StoryUI", rec)
		local s, _, offer = storySnapshot(g, { level = 2, sale = true })
		render(g, p, mod, s)
		local card = byName(page, "SaleCard")
		T.check(card.Visible, "Verkaufskarte sichtbar")
		T.eq(byName(page, "CustomerName").Text, offer.customer, "Kundenname")
		T.check(byName(page, "CustomerWish").Text:find(offer.wantsName, 1, true) ~= nil, "Wunsch: " .. byName(page, "CustomerWish").Text)
		T.check(byName(page, "CustomerLine").Text:find(offer.line, 1, true) ~= nil, "Spruch des Kunden")
		T.eq(byName(page, "CustomerSpecial").Visible, offer.special, "Sammler-Hinweis nur bei Sondermodell-Kunden")
		local risks = { "sicher", "wahrscheinlich", "riskant" }
		local MiniLocale = g:MiniShared("MiniLocale")
		for tier = 1, 3 do
			local b = byName(page, "Price_" .. tier)
			local info = byName(page, "PriceInfo_" .. tier)
			local t = offer.tiers[tier]
			T.check(b ~= nil and enabled(b) and b.AbsoluteSize.Y >= 44, "Preisknopf " .. tier)
			T.check(b.Text:find(t.label, 1, true) ~= nil and b.Text:find(MiniLocale.Number(t.price), 1, true) ~= nil, "Knopf " .. tier .. ": " .. b.Text)
			T.check(info.Text:find("Gewinn " .. MiniLocale.Number(t.profit), 1, true) ~= nil, "Gewinn " .. tier .. ": " .. info.Text)
			T.check(info.Text:find(risks[tier], 1, true) ~= nil, "Risiko " .. tier .. " = " .. risks[tier] .. ": " .. info.Text)
		end
		-- Stufe 2 wählen: story_sell {offer = Serial, price = 2} – genau zwei Felder, kein Betrag
		press(g, byName(page, "Price_2"))
		local sent = rec.Last("story_sell")
		T.check(sent ~= nil, "story_sell gesendet")
		if sent then
			T.eq(sent.offer, offer.serial, "offer = Serial des Angebots")
			T.eq(sent.price, 2, "price = Preisstufe 2")
			local n = 0
			for _ in pairs(sent) do
				n += 1
			end
			T.eq(n, 2, "genau zwei Felder")
		end
		-- bis zur Antwort gesperrt (kein Doppelklick)
		T.check(not enabled(byName(page, "Price_1")) and not enabled(byName(page, "Price_3")), "Preisknöpfe gesperrt")
		T.eq(byName(page, "SalePending").Visible, true, "Hinweis „gesendet“")
		press(g, byName(page, "Price_3"))
		T.eq(rec.Count("story_sell"), 1, "kein zweites Angebot")
		-- Antwort des Servers: Ergebnis-Karte mit Text, springt auf (UIScale), Kunde weg, Countdown
		g:InClient(p, function()
			mod.OnNotice({ kind = "story", event = "sale", offer = offer.serial, customer = offer.customer, sold = true, tier = 2, credits = 75, xp = 12, special = false, text = offer.customer .. " schlägt ein. Dein Gewinn: 75 Cr.", chapter = 1 })
		end)
		local result = byName(page, "SaleResult")
		T.check(result.Visible, "Ergebnis sichtbar")
		T.eq(byName(page, "ResultTitle").Text, "Verkauft!", "Ergebnis-Titel")
		T.check(byName(page, "ResultText").Text:find("schlägt ein", 1, true) ~= nil and byName(page, "ResultText").Text:find("+12 XP", 1, true) ~= nil, "Ergebnis-Text: " .. byName(page, "ResultText").Text)
		T.check(result:FindFirstChildOfClass("UIScale").Scale < 1, "Animation startet klein")
		g:Advance(0.5)
		T.check(math.abs(result:FindFirstChildOfClass("UIScale").Scale - 1) < 0.01, "Animation klingt ab")
		s = storySnapshot(g, { level = 2, sale = false, saleIn = 45 })
		render(g, p, mod, s)
		T.check(card.Visible, "Karte bleibt (Countdown)")
		T.eq(byName(page, "Customer").Visible, false, "kein Kunde")
		T.eq(byName(page, "PriceBox_1").Visible, false, "keine Preisknöpfe")
		T.check(byName(page, "SaleWait").Text:find("Nächster Kunde in 45 Sek.", 1, true) ~= nil, "Countdown: " .. byName(page, "SaleWait").Text)
		g:Advance(10)
		g:InClient(p, function()
			mod.Step(1)
		end)
		T.check(byName(page, "SaleWait").Text:find("35 Sek.", 1, true) ~= nil, "Countdown läuft: " .. byName(page, "SaleWait").Text)
		g:Advance(5)
		T.eq(result.Visible, false, "Ergebnis nach ResultSeconds weg")
		-- geplatzte Verhandlung
		s, _, offer = storySnapshot(g, { level = 2, sale = true, saleSerial = 2 })
		render(g, p, mod, s)
		T.check(enabled(byName(page, "Price_3")), "neuer Kunde: Knöpfe frei")
		press(g, byName(page, "Price_3"))
		T.eq(rec.Last("story_sell").price, 3, "Stufe 3")
		g:InClient(p, function()
			mod.OnNotice({ kind = "story", event = "sale", offer = offer.serial, customer = offer.customer, sold = false, tier = 3, credits = 0, xp = 0, text = offer.customer .. " schüttelt den Kopf.", chapter = 1 })
		end)
		T.eq(byName(page, "ResultTitle").Text, "Nicht verkauft", "Pleite-Titel")
		-- Sondermodell-Kunde (Kapitel 4, jeder dritte): Sammler-Hinweis
		s, _, offer = storySnapshot(g, { level = 35, sale = true, saleSerial = 3, mutate = function(d, R)
			finishChapters(d, R, 3)
			d.games.story.sales.serial = 2
		end })
		T.eq(offer.special, true, "dritter Kunde ab Kapitel 4 ist Sammler")
		render(g, p, mod, s)
		T.eq(byName(page, "CustomerSpecial").Visible, true, "Sammler-Hinweis")
		-- Lobby/Tycoon: keine Verkaufskarte, Wegweiser erklärt die Open World
		s = storySnapshot(g, { level = 2, sale = true, mode = "lobby" })
		render(g, p, mod, s)
		T.eq(card.Visible, false, "Lobby: keine Verkaufskarte")
		T.check(byName(page, "MapHintCard").Visible and withText(byName(page, "MapHintCard"), "Open World") ~= nil, "Wegweiser: Open World")
		T.check(not enabled(byName(page, "TravelButton")), "Schnellreise außerhalb gesperrt")
		press(g, byName(page, "TravelButton"))
		T.eq(rec.Count("mini_travel"), 0, "nichts gesendet")
		-- Passiv-Modus: keine Verkaufskarte, Missionen gesperrt mit Hinweis
		s = storySnapshot(g, { level = 2, sale = true, passive = true })
		render(g, p, mod, s)
		T.eq(card.Visible, false, "Passiv: keine Verkaufskarte")
		T.check(byName(page, "ChapterNote").Visible and byName(page, "ChapterNote").Text:find("Passiv", 1, true) ~= nil, "Passiv-Hinweis im Kopf")
		T.check(not enabled(byName(page, "MissionButton_1")) and byName(page, "MissionButton_1").Text == "Passiv", "Passiv: Starten gesperrt")
		T.eq(#toasts, 0, "keine eigenen Toasts")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "StoryUI: Kapitel 3 gesperrt (Level 10) – Sperrhinweis „Ab Level 15“, keine Absicht; nach Level 15 startbar (Gebäude-Mission ohne Wegweiser)", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page = build(g, p, "StoryUI", rec)
		local SR = g:MiniShared("StoryRules")
		local s = storySnapshot(g, { level = 10, mutate = function(d, R)
			finishChapters(d, R, 2)
		end })
		T.eq(s.story.chapter, 3, "Kapitel 3")
		T.eq(s.story.locked, true, "gesperrt")
		render(g, p, mod, s)
		T.check(byName(page, "ChapterTitle").Text == "Kapitel 3: " .. SR.Chapter(3).title, "Kopf Kapitel 3")
		local note = byName(page, "ChapterNote")
		T.check(note.Visible and note.Text:find("ab Level 15", 1, true) ~= nil and note.Text:find("Level 10", 1, true) ~= nil, "Sperrhinweis: " .. note.Text)
		local b1 = byName(page, "MissionButton_1")
		T.check(not enabled(b1) and b1.Text == "Ab Level 15", "Mission 1: " .. b1.Text)
		T.check(withText(byName(page, "Mission_1"), "ab Level 15") ~= nil, "Sperrgrund an der Mission")
		T.check(not enabled(byName(page, "MissionButton_2")) and not enabled(byName(page, "MissionButton_3")), "übrige gesperrt")
		press(g, b1)
		press(g, byName(page, "MissionButton_2"))
		T.eq(#rec.sent, 0, "gesperrt: nichts gesendet")
		T.eq(byName(page, "SaleCard").Visible, false, "kein Kunde")
		T.eq(byName(page, "MapHintCard").Visible, false, "kein Wegweiser (Gebäude-Mission)")
		local over = byName(page, "ChaptersCard")
		T.check(withText(over, "✓ Kapitel 1") ~= nil and withText(over, "✓ Kapitel 2") ~= nil, "Kapitel 1–2 erledigt in der Übersicht")
		T.check(withText(over, "Kapitel 3") ~= nil and withText(over, "ab Level 15") ~= nil, "Kapitel 3 mit Level")
		-- Level 15: frei
		s = storySnapshot(g, { level = 15, mutate = function(d, R)
			finishChapters(d, R, 2)
		end })
		render(g, p, mod, s)
		T.eq(note.Visible, false, "kein Sperrhinweis mehr")
		b1 = byName(page, "MissionButton_1")
		T.check(enabled(b1) and b1.Text == "Starten", "ab Level 15 startbar")
		press(g, b1)
		T.check(rec.Last("story_start") and rec.Last("story_start").id == "c3_m1", "story_start c3_m1")
		-- Story fertig: Kopf meldet den Abschluss, Titel
		s = storySnapshot(g, { level = 60, mutate = function(d, R)
			finishChapters(d, R, 5)
			d.games.story.title = "Mega-Verkäufer"
		end })
		T.eq(s.story.finished, true, "fertig")
		render(g, p, mod, s)
		T.check(byName(page, "ChapterProgress").Text:find("abgeschlossen", 1, true) ~= nil, "Abschluss im Kopf")
		T.check(byName(page, "TitleEarned").Visible and byName(page, "TitleEarned").Text:find("Mega-Verkäufer", 1, true) ~= nil, "Titel angezeigt")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "StoryUI: Nebenmissionen – drei des Tages plus Werkstatt-Legende, Fortschritt, Abholen → side_claim {id}, Erledigt, Tageszähler, Lieferungs-Uhr", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page = build(g, p, "StoryUI", rec)
		local SR = g:MiniShared("StoryRules")
		local Story = SR.Config()
		local today = SR.DayKey(NOW)
		local daily = SR.DailyDefs(today)
		T.eq(#daily, 3, "drei Tagesmissionen")
		local first, second = daily[1], daily[2]
		local s = storySnapshot(g, { level = 4, mutate = function(d)
			-- erste erfüllt (Zähler oder Bedingung), zweite halb, Legende „100 Aufträge“ mit 40
			d.games.story.side[first.id] = { n = first.target, day = today, claimed = false }
			d.games.story.side[second.id] = { n = math.floor(second.target / 2), day = today, claimed = false }
			d.games.stats.jobsDone = 40
			d.bays = 1
		end })
		render(g, p, mod, s)
		local nLegend = #Story.Side.Legend
		for i = 1, 3 + nLegend do
			local row = byName(page, "Side_" .. i)
			T.check(row ~= nil and row.Visible, "Nebenmission-Zeile " .. i)
			T.check(byName(page, "SideButton_" .. i).AbsoluteSize.Y >= 44, "Knopf ≥ 44 px " .. i)
		end
		T.eq(byName(page, "Side_" .. (4 + nLegend)), nil, "nicht mehr Zeilen")
		local r1 = byName(page, "Side_1")
		T.check(withText(r1, first.title) ~= nil and withText(r1, first.text) ~= nil, "Titel/Text der ersten")
		T.check(withText(r1, "Belohnung: " .. tostring(SR.SideCredits(first, 4))) ~= nil, "Belohnung auf Level 4 skaliert")
		local b1 = byName(page, "SideButton_1")
		if SR.IsCounter(first) then
			T.check(enabled(b1) and b1.Text == "Abholen", "erste abholbar: " .. b1.Text)
			press(g, b1)
			local sent = rec.Last("side_claim")
			T.check(sent ~= nil and sent.id == first.id, "side_claim " .. first.id)
		end
		local b2 = byName(page, "SideButton_2")
		if SR.IsCounter(second) then
			T.check(not enabled(b2) and b2.Text == tostring(math.floor(second.target / 2)) .. " / " .. tostring(second.target), "zweite halb: " .. b2.Text)
			press(g, b2)
			T.eq(rec.Count("side_claim"), SR.IsCounter(first) and 1 or 0, "unfertig: kein side_claim")
		end
		-- Legende: 100 Aufträge mit 40/100, Vier Bühnen 1/4
		local legendRow = withText(page, "Werkstatt-Legende: 100 Aufträge")
		T.check(legendRow ~= nil, "Legende sichtbar")
		local legendBtn = find(page, function(x)
			return x:IsA("TextButton") and x.Name:find("SideButton_", 1, true) ~= nil and x.Text == "40 / 100"
		end)
		T.check(legendBtn ~= nil, "Legende zeigt 40 / 100")
		T.check(withText(page, "Heute abgeholt: 0 von 3") ~= nil, "Tageszähler: " .. byName(page, "SideInfo").Text)
		local untilMidnight = g:MiniShared("MiniLocale").Duration(DAY - (math.floor(g:Now()) % DAY))
		T.check(byName(page, "SideInfo").Text:find("Neue Nebenmissionen in " .. untilMidnight, 1, true) ~= nil, "Zeit bis Mitternacht (" .. untilMidnight .. "): " .. byName(page, "SideInfo").Text)
		-- abgeholt: Erledigt ✓, Zähler 1 von 3
		s = storySnapshot(g, { level = 4, mutate = function(d)
			d.games.story.side[first.id] = { n = first.target, day = today, claimed = true }
		end })
		render(g, p, mod, s)
		b1 = byName(page, "SideButton_1")
		T.check(not enabled(b1) and b1.Text == "Erledigt ✓", "erledigt: " .. b1.Text)
		press(g, b1)
		T.eq(rec.Count("side_claim"), SR.IsCounter(first) and 1 or 0, "Erledigt sendet nichts")
		T.check(withText(page, "Heute abgeholt: 1 von 3") ~= nil, "Zähler 1 von 3")
		-- Lieferung: Uhr aus mini_notice, zählt herunter, verschwindet am Ziel
		local status = byName(page, "DeliveryStatus")
		T.eq(status.Visible, false, "ohne Lieferung keine Uhr")
		g:InClient(p, function()
			mod.OnNotice({ kind = "story", event = "delivery", state = "started", route = 2, limit = 240 })
		end)
		T.check(status.Visible and status.Text:find("Lieferung 2", 1, true) ~= nil and status.Text:find("4 Min. 00 Sek.", 1, true) ~= nil, "Lieferungs-Uhr: " .. status.Text)
		g:Advance(30)
		g:InClient(p, function()
			mod.Step(1)
		end)
		T.check(status.Text:find("3 Min. 30 Sek.", 1, true) ~= nil, "Uhr läuft: " .. status.Text)
		g:InClient(p, function()
			mod.OnNotice({ kind = "story", event = "delivery", state = "done", route = 2, time = 31 })
		end)
		T.eq(status.Visible, false, "am Ziel: Uhr weg")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "MissionClient: Marker am Missionsziel und an Start/Ziel der Lieferroute, Missions-Karte oben Mitte, Kapitel-Intro, NPC-Kunden wippen; alles weg bei QTE/Tablet/Panel", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		-- synthetische Stadt: Stationen, Lieferroute 1, Kiesplatz-Viertel mit NPC-Kunde
		local city = g:BuildCity({
			stations = {
				{ key = "kiesplatz", tab = "story", pos = Vector3.new(300, 3, -250), title = "Kiesplatz · Gebrauchtwagen" },
				{ key = "dealer", tab = "dealer", pos = Vector3.new(-20, 3, 100) },
			},
			arrivals = { { key = "kiesplatz", pos = Vector3.new(290, 0, -250) } },
		})
		local env = g.env
		local startPart, endPart, npc, npcRoot, spot
		g:InClient(p, function()
			local missions = Instance.new("Folder")
			missions.Name = "Missions"
			missions.Parent = city
			local route = Instance.new("Folder")
			route.Name = "Delivery_1"
			route.Parent = missions
			startPart = Instance.new("Part")
			startPart.Name = "Start"
			startPart.Anchored = true
			startPart.Transparency = 1
			startPart.CFrame = CFrame.new(40, 1, -200)
			startPart:SetAttribute("Role", "start")
			startPart.Parent = route
			endPart = Instance.new("Part")
			endPart.Name = "Ziel"
			endPart.Anchored = true
			endPart.Transparency = 1
			endPart.CFrame = CFrame.new(200, 1, 100)
			endPart:SetAttribute("Role", "end")
			endPart.Parent = route
			local districts = Instance.new("Folder")
			districts.Name = "Districts"
			districts.Parent = city
			local district = Instance.new("Model")
			district.Name = "Kiesplatz"
			district.Parent = districts
			local spots = Instance.new("Folder")
			spots.Name = "Spots"
			spots.Parent = district
			spot = Instance.new("Part")
			spot.Name = "Spot_1"
			spot.Anchored = true
			spot.CFrame = CFrame.new(300, 0.5, -240)
			spot.Parent = spots
			npc = Instance.new("Model")
			npc.Name = "Kunde_1"
			npc:SetAttribute("Anim", "npc_idle")
			npcRoot = Instance.new("Part")
			npcRoot.Name = "Torso"
			npcRoot.Anchored = true
			npcRoot.Size = Vector3.new(2, 2, 1)
			npcRoot.CFrame = CFrame.new(300, 3, -240)
			npcRoot.Parent = npc
			local head = Instance.new("Part")
			head.Name = "Head"
			head.Anchored = true
			head.Size = Vector3.new(1, 1, 1)
			head.CFrame = CFrame.new(300, 4.5, -240)
			head.Parent = npc
			npc.PrimaryPart = npcRoot
			npc.Parent = district
		end)
		local _, _, MiniUI, _, state, ctx = build(g, p, "PrestigeUI", rec)
		local mod = g:ClientModule(p, "Mini.MissionClient")
		g:InClient(p, function()
			workspace.CurrentCamera.CFrame = CFrame.new(300, 10, -230)
			mod.Start(ctx)
		end)
		g:Advance(0.1)
		local gui = p.PlayerGui:FindFirstChild("Missionen")
		T.check(gui ~= nil and gui.ClassName == "ScreenGui" and gui.DisplayOrder == 21, "ScreenGui Missionen (DisplayOrder 21)")
		T.eq(mod.MarkerTarget(), nil, "ohne Snapshot kein Marker")
		-- aktive Kiesplatz-Mission: Marker an City.Stations.kiesplatz, mit Kundenname
		local s, _, offer = storySnapshot(g, { level = 2, sale = true, mutate = function(d, R)
			R.Start(d, "c1_m1", NOW, 0, 2)
		end })
		s.story.side = { { id = "s_delivery", title = "Lieferung", text = "", progress = 0, target = 1, done = false, claimable = false, legend = false, credits = 150, xp = 50 } }
		g:InClient(p, function()
			mod.OnSnapshot(s)
			mod.Step(0.3)
		end)
		local station = g:Find("Workspace.City.Stations.kiesplatz")
		T.eq(mod.MarkerTarget(), station, "Marker am Kiesplatz")
		local marker = gui:FindFirstChild("MissionMarker")
		T.check(marker and marker.AlwaysOnTop and marker.Text.Text:find("KIESPLATZ", 1, true) ~= nil, "Marker-Text: " .. tostring(marker and marker.Text.Text))
		T.check(marker.Text.Text:find(offer.customer .. " wartet", 1, true) ~= nil, "Marker nennt den wartenden Kunden")
		T.check(marker.Text.Text:find(" m", 1, true) ~= nil, "Entfernung in Studs")
		-- Lieferung offen: Startmarker an Delivery_1.Start; nach „gestartet“ der Zielmarker
		T.eq(mod.MarkerTarget("DeliveryStart"), startPart, "Startmarker der Lieferroute")
		T.eq(mod.MarkerTarget("DeliveryEnd"), nil, "noch kein Zielmarker")
		g:InClient(p, function()
			mod.OnNotice({ kind = "story", event = "delivery", state = "started", route = 1, limit = 240 })
			mod.Step(0.3)
		end)
		T.eq(mod.MarkerTarget("DeliveryStart"), nil, "Start weg")
		T.eq(mod.MarkerTarget("DeliveryEnd"), endPart, "Zielmarker")
		T.check(mod.CardVisible() and gui.MissionCard.Title.Text == "Lieferung gestartet", "Karte „Lieferung gestartet“")
		g:Advance(4.5)
		T.eq(mod.CardVisible(), false, "Karte nach CardSeconds weg")
		g:InClient(p, function()
			mod.OnNotice({ kind = "story", event = "delivery", state = "done", route = 1, time = 50 })
			mod.Step(0.3)
		end)
		T.eq(mod.MarkerTarget("DeliveryEnd"), nil, "Ziel erreicht: Marker weg")
		T.check(mod.CardVisible() and gui.MissionCard.Title.Text:find("abgeliefert", 1, true) ~= nil, "Karte „abgeliefert“")
		g:Advance(4.5)
		-- Marker wippt (StudsOffset ändert sich)
		local y0 = marker.StudsOffset.Y
		g:Advance(0.4)
		T.check(math.abs(marker.StudsOffset.Y - y0) > 0.01, "Marker wippt")
		-- Missions-Karte oben Mitte bei done=true, kurzer Tween; Warteschlange
		g:InClient(p, function()
			mod.OnNotice({ kind = "mission", id = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", progress = 3, target = 3, done = true, side = false })
			mod.OnNotice({ kind = "story", event = "claimed", chapter = 1, mission = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", credits = 150, xp = 60, chapterDone = false })
		end)
		local cardFrame = gui:FindFirstChild("MissionCard")
		T.check(cardFrame and cardFrame.Visible, "Missions-Karte sichtbar")
		T.eq(cardFrame.Title.Text, "Mission geschafft!", "Titel")
		T.check(cardFrame.Text.Text:find("Drei Gebrauchtwagen verkaufen", 1, true) ~= nil, "Missionstitel in der Karte")
		T.eq(cardFrame.AnchorPoint.X, 0.5, "oben Mitte verankert")
		T.check(cardFrame.Position.Y.Offset >= 62 + 60, "unter der Toast-Zone: " .. tostring(cardFrame.Position.Y.Offset))
		T.check(cardFrame:FindFirstChildOfClass("UIScale").Scale < 1, "Tween startet klein")
		g:Advance(0.5)
		T.check(math.abs(cardFrame:FindFirstChildOfClass("UIScale").Scale - 1) < 0.01, "Tween klingt ab")
		T.eq(mod.QueuedCards(), 1, "Belohnungs-Karte wartet")
		g:Advance(4.2)
		T.check(cardFrame.Visible and cardFrame.Title.Text == "Belohnung abgeholt" and cardFrame.Text.Text:find("150 Cr", 1, true) ~= nil, "zweite Karte: " .. cardFrame.Title.Text .. " / " .. cardFrame.Text.Text)
		g:Advance(4.5)
		T.eq(mod.CardVisible(), false, "Warteschlange leer")
		-- erfüllte Mission: kein Ziel-Marker mehr (Belohnung im Tab)
		s = storySnapshot(g, { level = 2, mutate = function(d, R)
			R.Start(d, "c1_m1", NOW, 0, 2)
			d.games.story.active.progress = 3
		end })
		g:InClient(p, function()
			mod.OnSnapshot(s)
			mod.Step(0.3)
		end)
		T.eq(mod.MarkerTarget(), nil, "erfüllt: kein Marker")
		-- Kapitelwechsel: Intro-Karte mit Titel und Text, „Los geht's!“ schließt
		local SR = g:MiniShared("StoryRules")
		s = storySnapshot(g, { level = 6, mutate = function(d, R)
			finishChapters(d, R, 1)
		end })
		g:InClient(p, function()
			mod.OnSnapshot(s)
		end)
		T.check(mod.ChapterVisible(), "Kapitel-Intro sichtbar")
		local chapterCard = gui:FindFirstChild("ChapterCard")
		T.check(chapterCard.Title.Text == "Kapitel 2: " .. SR.Chapter(2).title, "Intro-Titel: " .. chapterCard.Title.Text)
		T.eq(chapterCard.Text.Text, SR.Chapter(2).intro, "Intro-Text")
		T.check(chapterCard.ChapterOk.AbsoluteSize.Y >= 44, "Knopf ≥ 44 px")
		press(g, chapterCard.ChapterOk)
		T.eq(mod.ChapterVisible(), false, "Intro geschlossen")
		g:InClient(p, function()
			mod.OnSnapshot(s)
		end)
		T.eq(mod.ChapterVisible(), false, "gleiches Kapitel: kein zweites Intro")
		-- Kapitel 2, Mission 1 (Aufträge abrechnen): Marker am Werkstatt-Empfang des eigenen Grundstücks
		s = storySnapshot(g, { level = 6, mutate = function(d, R)
			finishChapters(d, R, 1)
			R.Start(d, "c2_m1", NOW, 0, 6)
		end })
		g:InClient(p, function()
			mod.OnSnapshot(s)
			mod.Step(0.3)
		end)
		local reception = g:Station(p, "workshop")
		T.check(reception ~= nil, "Empfang im eigenen Grundstück")
		T.eq(mod.MarkerTarget(), reception, "Marker am Werkstatt-Empfang")
		T.check(gui.MissionMarker.Text.Text:find("WERKSTATT", 1, true) ~= nil, "Beschriftung Werkstatt")
		-- NPC: wippt und dreht sich dezent um den eigenen Pivot (X/Z bleiben, Y ≥ Ruhelage, klein)
		T.eq(mod.NpcCount(), 1, "ein NPC erkannt")
		local base = Vector3.new(300, 3, -240)
		local moved = false
		local okPos = true
		for _ = 1, 6 do
			g:Advance(0.25)
			local pos = npcRoot.Position
			if math.abs(pos.Y - base.Y) > 0.01 then
				moved = true
			end
			if math.abs(pos.X - base.X) > 0.01 or math.abs(pos.Z - base.Z) > 0.01 or pos.Y < base.Y - 0.001 or pos.Y > base.Y + 0.2 then
				okPos = false
			end
		end
		T.check(moved, "NPC wippt")
		T.check(okPos, "NPC bleibt auf seinem Platz (nur Wippen/Drehen)")
		local yaw = select(2, npc:GetPivot():ToEulerAnglesYXZ())
		T.check(math.abs(yaw) <= 0.31, "Drehung dezent: " .. tostring(yaw))
		-- QTE/Tablet/Panel: alles weg, danach wieder da
		state.blocked = true
		g:InClient(p, function()
			mod.Step(0.3)
		end)
		T.eq(gui.Enabled, false, "QTE: ScreenGui aus")
		T.eq(mod.MarkerTarget(), nil, "QTE: kein Marker")
		state.blocked = false
		state.tablet = true
		g:InClient(p, function()
			mod.Step(0.3)
		end)
		T.eq(gui.Enabled, false, "Tablet: aus")
		state.tablet = false
		g:InClient(p, function()
			MiniUI.Open("overview")
			mod.Step(0.3)
		end)
		T.eq(gui.Enabled, false, "Panel offen: aus")
		g:InClient(p, function()
			MiniUI.Close()
			mod.Step(0.3)
		end)
		T.eq(gui.Enabled, true, "wieder an")
		T.eq(mod.MarkerTarget(), reception, "Marker wieder da")
		-- Karte während QTE: wartet, erscheint danach
		state.blocked = true
		g:InClient(p, function()
			mod.Step(0.3)
			mod.OnNotice({ kind = "mission", id = "c2_m1", title = "Fünf Aufträge abrechnen", progress = 5, target = 5, done = true, side = false })
		end)
		T.eq(mod.CardVisible(), false, "QTE: Karte wartet")
		T.eq(mod.QueuedCards(), 1, "in der Warteschlange")
		state.blocked = false
		g:InClient(p, function()
			mod.Step(0.3)
		end)
		T.check(mod.CardVisible() and gui.Enabled, "nach QTE: Karte da")
		-- Lobby: keine Marker
		s.mode = "lobby"
		g:InClient(p, function()
			mod.OnSnapshot(s)
			mod.Step(0.3)
		end)
		T.eq(mod.MarkerTarget(), nil, "Lobby: kein Marker")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "MissionClient: echte Stadt (worldgen) – drei NPC-Kunden unter City.Animated.Kiesplatz wippen, Marker an City.Stations.kiesplatz und an Delivery_1..3", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local _, _, _, _, _, ctx = build(g, p, "PrestigeUI", rec)
		local mod = g:ClientModule(p, "Mini.MissionClient")
		local station = g:Find("Workspace.City.Stations.kiesplatz")
		local kunde = g:Find("Workspace.City.Animated.Kiesplatz.Kunde_1")
		T.check(station ~= nil, "Station kiesplatz in der Fixture")
		T.check(kunde ~= nil and kunde:GetAttribute("Anim") == "npc_idle", "NPC-Kunde in der Fixture")
		T.eq(station and station:GetAttribute("MiniTab"), "story", "Station öffnet den Tab story")
		g:InClient(p, function()
			workspace.CurrentCamera.CFrame = CFrame.new(300, 10, 290)
			mod.Start(ctx)
		end)
		g:Advance(0.1)
		T.eq(mod.NpcCount(), 3, "drei NPC-Kunden erkannt")
		local base = kunde:GetPivot().Position
		local moved = false
		for _ = 1, 6 do
			g:Advance(0.25)
			local pos = kunde:GetPivot().Position
			if math.abs(pos.Y - base.Y) > 0.01 then
				moved = true
			end
			T.check(math.abs(pos.X - base.X) < 0.01 and math.abs(pos.Z - base.Z) < 0.01 and pos.Y >= base.Y - 0.001 and pos.Y <= base.Y + 0.2, "Kunde bleibt am Platz")
		end
		T.check(moved, "Kunde wippt")
		local s = storySnapshot(g, { level = 2, sale = true, mutate = function(d, R)
			R.Start(d, "c1_m1", NOW, 0, 2)
		end })
		s.story.side = { { id = "s_delivery", title = "Lieferung", text = "", progress = 0, target = 1, done = false, claimable = false, legend = false, credits = 150, xp = 50 } }
		g:InClient(p, function()
			mod.OnSnapshot(s)
			mod.Step(0.3)
		end)
		T.eq(mod.MarkerTarget(), station, "Marker an der echten Kiesplatz-Station")
		local startMarker = mod.MarkerTarget("DeliveryStart")
		T.check(startMarker ~= nil and startMarker:IsDescendantOf(g:Find("Workspace.City.Missions")), "Startmarker an einer echten Lieferroute")
		for n = 1, 3 do
			g:InClient(p, function()
				mod.OnNotice({ kind = "story", event = "delivery", state = "started", route = n, limit = 240 })
				mod.Step(0.3)
			end)
			local finish = mod.MarkerTarget("DeliveryEnd")
			T.check(finish ~= nil and finish.Parent and finish.Parent.Name == "Delivery_" .. n, "Zielmarker Route " .. n)
		end
		T.eq(g:ErrorText(), "", "keine Fehler")
		T.eq(#g:Warnings(), 0, "keine Warnungen")
	end },

	{ "StoryUI: Handy-Layouts 390×844 und 844×390 – eine Spalte, kein Überlauf, Knöpfe ≥ 44 px", function(T, H)
		for _, vp in ipairs({ Vector2.new(390, 844), Vector2.new(844, 390) }) do
			local g, p = startClient(H, { viewport = vp })
			local rec = recorder(T)
			local mod, page, MiniUI = build(g, p, "StoryUI", rec)
			g:InClient(p, function()
				MiniUI.Open("overview")
				page.Size = UDim2.new(0, MiniUI.Content.AbsoluteSize.X - 8, 0, 0)
			end)
			local s = storySnapshot(g, { level = 2, sale = true, mutate = function(d, R)
				R.Start(d, "c1_m1", NOW, 0, 2)
			end })
			render(g, p, mod, s)
			local width = page.AbsoluteSize.X
			local tag = tostring(vp.X) .. "×" .. tostring(vp.Y)
			T.check(width > 0 and width <= vp.X, tag .. ": Seitenbreite " .. tostring(width))
			local bad = 0
			for _, x in ipairs(page:GetDescendants()) do
				if x:IsA("GuiObject") and x.Visible then
					local right = x.AbsolutePosition.X + x.AbsoluteSize.X
					if right > page.AbsolutePosition.X + width + 1 then
						bad += 1
						if bad <= 3 then
							T.check(false, tag .. ": ragt heraus: " .. x:GetFullName())
						end
					end
					if x:IsA("TextButton") and x.AbsoluteSize.Y < 44 then
						T.check(false, tag .. ": Knopf unter 44 px: " .. x:GetFullName())
					end
				end
			end
			T.eq(bad, 0, tag .. ": nichts ragt heraus")
			T.check(byName(page, "SaleCard").Visible and byName(page, "MissionsCard").Visible and byName(page, "SideCard").Visible, tag .. ": alle Karten sichtbar")
			-- Missions-Karte des MissionClient: höchstens Bildschirmbreite − 24
			local _, _, _, _, _, ctx = build(g, p, "PrestigeUI", rec)
			local mc = g:ClientModule(p, "Mini.MissionClient")
			g:InClient(p, function()
				MiniUI.Close()
				mc.Start(ctx)
				mc.Step(0.3)
				mc.OnNotice({ kind = "mission", id = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", progress = 3, target = 3, done = true, side = false })
				mc.Step(0.3)
			end)
			local gui = p.PlayerGui:FindFirstChild("Missionen")
			local cardFrame = gui and gui:FindFirstChild("MissionCard")
			T.check(cardFrame and cardFrame.Visible and cardFrame.AbsoluteSize.X <= vp.X - 24, tag .. ": Missions-Karte passt (" .. tostring(cardFrame and cardFrame.AbsoluteSize.X) .. ")")
			T.eq(g:ErrorText(), "", tag .. ": keine Fehler")
			g:Close()
		end
	end },
}
