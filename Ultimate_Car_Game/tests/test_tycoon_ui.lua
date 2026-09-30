-- Ausbaustufe 4, Meilenstein 4 (Team client): TycoonUI (Tab „tycoon“) und TycoonClient (Bargeld-Abzeichen, Pad-Blitz,
-- Produzenten-Animationen) im Mock-Client mit gefälschten Snapshots. Der Client sendet nur Absichten
-- (tycoon_choose/buy/collect/trade_*/rebirth/abandon, lobby_return); geprüft werden die gesendeten Aktionen
-- und Nutzlasten sowie die Sichtbarkeit des Abzeichens je Modus.
local NOW = 1760000000

---------------------------------------------------------------- Hilfen (wie test_lobby / test_prestige)
local FORBIDDEN = { amount = true, cost = true, credits = true, reward = true, money = true, cash = true, xp = true, level = true }

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
	opts.placeKind = opts.placeKind or "tycoon"
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1.5)
	return g, p
end

-- Baut die Seite des Bereichs in einer eigenen ScreenGui (338 px breit wie das Panel bei 390 px Bildschirmbreite)
local function build(g, p, modName, rec, ctxExtra)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini." .. modName)
	local toasts = {}
	local state = { tablet = false, blocked = false }
	local ctxOut
	local page = g:InClient(p, function()
		if not MiniUI.Gui then
			MiniUI.Build()
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "TycoonTest_" .. modName
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
		return type(t) == "string" and t:find(text, 1, true) ~= nil
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

-- Gefälschte Snapshots. Ohne Durchlauf / Stufe 1 frisch / Stufe 5 komplett / mit Handelsangeboten.
local function base(mode, extra)
	local s = {
		credits = 1000, level = 3, mode = mode or "tycoon", placeKind = "all", simulated = true,
		meta = { beginner = false, passive = false, single = false, tutorialDone = true, tutorialStep = 10 },
		party = false,
		tycoon = {
			run = false, rebirths = 0, boost = 0, slot = 1,
			runsDone = { werkstatt = 0, autohaus = 0, produktion = 0, schrottplatz = 0 },
			bonus = {
				werkstatt = { runs = 0, pct = 0, text = "Werkstatt-Vergütung" },
				autohaus = { runs = 0, pct = 0, text = "Händlerrabatt" },
				produktion = { runs = 0, pct = 0, text = "Tuning-Tempo" },
				schrottplatz = { runs = 0, pct = 0, text = "Schrott" },
			},
			offers = {},
		},
	}
	for k, v in pairs(extra or {}) do
		s[k] = v
	end
	return s
end

-- Durchlauf über die echten Regeln (TycoonRules.Summary), damit Ids/Kosten/Gründe stimmen
local function runSnapshot(g, typ, mutate, mode, extra)
	local TR = g:MiniShared("TycoonRules")
	local d = g:Rules().NewData(NOW)
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	TR.ApplyDefault(d.games)
	local run = TR.NewRun(d, typ, NOW)
	if mutate then
		mutate(run, d)
	end
	local s = base(mode, extra)
	local sum = TR.Summary(d)
	s.tycoon.run = sum.run
	s.tycoon.boost = sum.boost
	s.tycoon.bonus = sum.bonus
	s.tycoon.runsDone = sum.runsDone
	s.tycoon.rebirths = sum.rebirths
	return s, d
end

local function completeStage5(run, GC)
	local b = GC.Tycoon.Buildings[run.building]
	run.stage = 5
	for s = 1, 5 do
		for _, u in ipairs(b.Stages[s].Upgrades) do
			run.upgrades[u.id] = 1
		end
	end
	run.cash = 5000
	run.container = 120
	run.storage.bauteile = 12
	run.storage.reifen = 3
end

---------------------------------------------------------------- Fälle
return {
	{ "TycoonUI: ohne Durchlauf vier Gebäude-Karten mit Beschreibung, Spielweise und Open-World-Bonus; Antippen sendet tycoon_choose", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI, toasts = build(g, p, "TycoonUI", rec)
		local GC = g:MiniShared("GameConfig")
		render(g, p, mod, base("tycoon"))
		T.eq(byName(page, "ChooseCard").Visible, true, "Gebäudewahl sichtbar")
		T.eq(byName(page, "RunCard").Visible, false, "kein Durchlauf-Kopf")
		T.eq(byName(page, "TradeCard").Visible, false, "kein Handel ohne Durchlauf")
		T.eq(byName(page, "RebirthCard").Visible, false, "kein Rebirth ohne Durchlauf")
		for _, typ in ipairs(GC.Tycoon.Types) do
			local card = byName(page, "Choose_" .. typ)
			T.check(card ~= nil and card.AbsoluteSize.Y >= 44, "Karte " .. typ)
			T.check(withText(card, GC.Tycoon.Buildings[typ].name) ~= nil, "Name " .. typ)
			T.check(withText(card, GC.Tycoon.Buildings[typ].desc) ~= nil, "Beschreibung " .. typ)
			T.check(withText(card, "Spielweise") ~= nil, "Spielweise " .. typ)
			T.check(withText(card, "Fertige Runde") ~= nil and withText(card, GC.Tycoon.Bonus[typ].text) ~= nil, "Open-World-Bonus " .. typ)
		end
		T.check(withText(byName(page, "Choose_werkstatt"), "+2 % Werkstatt-Vergütung") ~= nil, "Bonus-Text Werkstatt")
		T.check(withText(byName(page, "Choose_autohaus"), "−1,5 % Händlerrabatt") ~= nil, "Bonus-Text Autohaus als Rabatt")
		T.check(withText(page, "wird nie zu Credits") ~= nil, "Hinweis: Bargeld ist nie Credits")
		T.eq(byName(page, "ReturnButton").Visible, true, "Zurück zur Lobby im Tycoon sichtbar")
		-- Antippen sendet tycoon_choose {building}
		press(g, byName(page, "Choose_produktion"))
		local sent = rec.Last("tycoon_choose")
		T.check(sent ~= nil and sent.building == "produktion", "tycoon_choose produktion")
		T.eq(rec.Count("tycoon_choose"), 1, "genau einmal")
		T.check(withText(byName(page, "Choose_produktion"), "Wird gebaut") ~= nil, "Karte zeigt „Wird gebaut“")
		T.check(not enabled(byName(page, "Choose_werkstatt")), "andere Karten bis zum Snapshot gesperrt")
		press(g, byName(page, "Choose_werkstatt"))
		T.eq(rec.Count("tycoon_choose"), 1, "keine zweite Wahl vor dem Snapshot")
		-- Zurück zur Lobby
		press(g, byName(page, "ReturnButton"))
		T.eq(rec.Count("lobby_return"), 1, "lobby_return gesendet")
		-- außerhalb des Tycoon-Geländes: Karten gesperrt, Hinweis
		render(g, p, mod, base("openworld"))
		T.check(not enabled(byName(page, "Choose_werkstatt")), "Open World: Wahl gesperrt")
		T.check(withText(page, "Tycoon-Gelände") ~= nil, "Hinweis auf das Gelände")
		render(g, p, mod, base("lobby"))
		T.eq(byName(page, "ReturnButton").Visible, false, "in der Lobby kein Zurück")
		-- Bonus-Karte immer da
		T.eq(byName(page, "BonusCard").Visible, true, "Bonus-Karte")
		local s = base("tycoon")
		s.tycoon.bonus.werkstatt = { runs = 3, pct = 6, text = "Werkstatt-Vergütung" }
		render(g, p, mod, s)
		T.check(byName(page, "BonusText").Text:find("Werkstatt: 3 Runden → +6 % Werkstatt-Vergütung", 1, true) ~= nil, "Bonus-Zeile: " .. byName(page, "BonusText").Text)
		T.check(byName(page, "BonusText").Text:find("Autohaus: 0 Runden → 0 % Händlerrabatt", 1, true) ~= nil, "ohne Runden kein Vorzeichen")
		T.eq(#toasts, 0, "keine Toasts")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "TycoonUI: Durchlauf Stufe 1 – Kopf, Sammeln, Upgrades mit Kaufen/Gekauft/Sperrgrund, Stufen-Karte, Lager, Abbruch mit Bestätigung", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI, toasts = build(g, p, "TycoonUI", rec)
		local GC = g:MiniShared("GameConfig")
		local b = GC.Tycoon.Buildings.werkstatt
		local u1, u2 = b.Stages[1].Upgrades[1], b.Stages[1].Upgrades[2]
		-- frisch: 50 Bargeld, nichts gekauft, Behälter leer
		local s = runSnapshot(g, "werkstatt", function(run)
			run.container = 0
		end)
		render(g, p, mod, s)
		T.eq(byName(page, "ChooseCard").Visible, false, "keine Gebäudewahl")
		T.eq(byName(page, "RunCard").Visible, true, "Kopf da")
		T.eq(byName(page, "RunTitle").Text, "Werkstatt · Stufe 1/5", "Kopf: Typ und Stufe")
		T.check(byName(page, "Cash").Text:find("50 Bargeld", 1, true), "Bargeld: " .. byName(page, "Cash").Text)
		T.check(byName(page, "Container").Text:find("Behälter: 0 / " .. tostring(b.Stages[1].capacity), 1, true), "Behälter x/Kapazität: " .. byName(page, "Container").Text)
		T.check(byName(page, "Rate").Text:find("Bargeld/s", 1, true), "Rate/s")
		T.check(not enabled(byName(page, "CollectButton")), "Sammeln bei leerem Behälter gesperrt")
		press(g, byName(page, "CollectButton"))
		T.eq(rec.Count("tycoon_collect"), 0, "gesperrt: nichts gesendet")
		-- Upgrades der Stufe 1: 4 Zeilen, alle mit Kosten; zu teuer -> Sperrgrund
		T.check(byName(page, "UpgradesCard").Visible, "Upgrades-Karte")
		T.check(withText(page, u1.name) ~= nil and withText(page, u2.name) ~= nil, "Upgrade-Namen")
		local buy1 = byName(page, "Buy_" .. u1.id)
		T.check(buy1 ~= nil and buy1.AbsoluteSize.Y >= 44, "Kaufknopf u1 (≥ 44 px)")
		T.check(not enabled(buy1) and buy1.Text == "Nicht genug Bargeld", "u1 zu teuer: " .. tostring(buy1 and buy1.Text))
		press(g, buy1)
		T.eq(rec.Count("tycoon_buy"), 0, "gesperrt: kein tycoon_buy")
		-- Stufen-Karte: gesperrt, weil Upgrades fehlen
		T.check(byName(page, "StageTitle").Text == "Stufe 2 ausbauen", "Stufen-Karte Titel")
		T.check(withText(byName(page, "StageCard"), tostring(b.Stages[2].price)) ~= nil or withText(byName(page, "StageCard"), "Bargeld") ~= nil, "Stufenpreis")
		T.check(not enabled(byName(page, "StageButton")), "Stufe 2 gesperrt")
		press(g, byName(page, "StageButton"))
		T.eq(rec.Count("tycoon_buy") + rec.Count("tycoon_stage"), 0, "Stufe gesperrt: nichts gesendet")
		-- Lager leer
		T.check(withText(byName(page, "StorageCard"), "Noch leer") ~= nil, "Lager leer")

		-- Mit Bargeld und vollem Behälter: Sammeln, Kaufen sendet tycoon_buy {id}, gekauftes Upgrade zeigt „Gekauft“
		s = runSnapshot(g, "werkstatt", function(run)
			run.cash = 100000
			run.container = b.Stages[1].capacity
			run.upgrades[u2.id] = 1
			run.storage.bauteile = 7
		end)
		render(g, p, mod, s)
		T.check(byName(page, "Container").Text:find("voll", 1, true), "Behälter voll markiert")
		T.check(enabled(byName(page, "CollectButton")), "Sammeln möglich")
		press(g, byName(page, "CollectButton"))
		T.eq(rec.Count("tycoon_collect"), 1, "tycoon_collect gesendet")
		T.eq(next(rec.Last("tycoon_collect")), nil, "tycoon_collect ohne Felder")
		buy1 = byName(page, "Buy_" .. u1.id)
		T.check(enabled(buy1) and buy1.Text == "Kaufen", "u1 kaufbar")
		press(g, buy1)
		local sent = rec.Last("tycoon_buy")
		T.check(sent ~= nil and sent.id == u1.id, "tycoon_buy id = " .. u1.id)
		T.eq(sent and sent.cost, nil, "kein Kostenfeld vom Client")
		local buy2 = byName(page, "Buy_" .. u2.id)
		T.check(buy2 ~= nil and not enabled(buy2) and buy2.Text:find("Gekauft", 1, true), "u2 gekauft")
		press(g, buy2)
		T.eq(rec.Count("tycoon_buy"), 1, "Gekauft sendet nichts")
		T.check(withText(byName(page, "StorageCard"), "Bauteile: 7") ~= nil, "Lager: Bauteile 7")
		T.check(withText(byName(page, "UpgradesCard"), "1 von 4 gekauft") ~= nil, "Zähler gekauft")

		-- Stufe 1 komplett + Bargeld: Stufen-Pad frei, sendet tycoon_buy {id = werkstatt_stage2}
		s = runSnapshot(g, "werkstatt", function(run)
			run.cash = 1000000
			for _, u in ipairs(b.Stages[1].Upgrades) do
				run.upgrades[u.id] = 1
			end
		end)
		render(g, p, mod, s)
		local stageBtn = byName(page, "StageButton")
		T.check(enabled(stageBtn) and stageBtn.Text:find("Ausbauen", 1, true), "Stufe 2 frei: " .. stageBtn.Text)
		press(g, stageBtn)
		T.eq(rec.Count("tycoon_stage"), 1, "tycoon_stage gesendet (Vertrag §10)")
		T.eq(next(rec.Last("tycoon_stage")), nil, "tycoon_stage ohne Felder")
		T.eq(rec.Count("tycoon_buy"), 1, "kein zweites tycoon_buy")
		-- alternativ: tycoon_buy {id = "<typ>_stage<n>"} (TycoonUI.StageAction), falls der Dienst nur Ids kennt
		mod.StageAction = "tycoon_buy"
		press(g, stageBtn)
		sent = rec.Last("tycoon_buy")
		T.check(sent ~= nil and sent.id == "werkstatt_stage2", "tycoon_buy werkstatt_stage2")
		mod.StageAction = "tycoon_stage"
		-- Stufe 3 braucht Waren: fehlende Waren werden angezeigt
		s = runSnapshot(g, "werkstatt", function(run)
			run.stage = 2
			run.cash = 1e7
			for st = 1, 2 do
				for _, u in ipairs(b.Stages[st].Upgrades) do
					run.upgrades[u.id] = 1
				end
			end
			run.storage.bauteile = 5
		end)
		render(g, p, mod, s)
		T.check(byName(page, "StageItems").Text:find("Bauteile: 5/15 (fehlt 10)", 1, true) ~= nil, "Warenbedarf mit Fehlmenge: " .. byName(page, "StageItems").Text)
		stageBtn = byName(page, "StageButton")
		T.check(not enabled(stageBtn) and stageBtn.Text == "Waren fehlen", "Stufe 3 wegen Waren gesperrt: " .. stageBtn.Text)
		-- Abbruch: erst Bestätigung, dann tycoon_abandon
		T.check(byName(page, "AbandonCard").Visible, "Abbruch-Karte")
		press(g, byName(page, "AbandonButton"))
		T.eq(rec.Count("tycoon_abandon"), 0, "vor der Bestätigung nichts gesendet")
		T.eq(MiniUI.Shade.Visible, true, "Bestätigungsdialog offen")
		T.check(MiniUI.ConfirmText.Text:find("verloren", 1, true), "Dialogtext")
		press(g, MiniUI.ConfirmYes)
		T.eq(rec.Count("tycoon_abandon"), 1, "tycoon_abandon nach Bestätigung")
		T.eq(MiniUI.Shade.Visible, false, "Dialog zu")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "TycoonUI: Stufe 5 komplett – Rebirth-Karte mit Voraussetzung, Boost-Vorschau und Bestätigung (tycoon_rebirth); vorher gesperrt", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI, toasts = build(g, p, "TycoonUI", rec)
		local GC = g:MiniShared("GameConfig")
		-- Stufe 5, aber ein Upgrade fehlt: gesperrt mit Grund
		local s = runSnapshot(g, "autohaus", function(run)
			completeStage5(run, GC)
			run.upgrades[GC.Tycoon.Buildings.autohaus.Stages[5].Upgrades[4].id] = nil
		end)
		render(g, p, mod, s)
		T.eq(byName(page, "RunTitle").Text, "Autohaus · Stufe 5/5", "Stufe 5")
		T.eq(byName(page, "StageTitle").Text, "Höchste Stufe erreicht", "keine Stufe 6")
		T.check(not enabled(byName(page, "StageButton")), "Stufen-Knopf aus")
		local rb = byName(page, "RebirthButton")
		T.check(rb ~= nil and not enabled(rb), "Rebirth gesperrt")
		T.check(withText(byName(page, "RebirthCard"), "Noch: Erst alle Upgrades der Stufe 5") ~= nil, "Grund: Upgrades fehlen")
		press(g, rb)
		T.eq(rec.Count("tycoon_rebirth"), 0, "gesperrt: nichts gesendet")
		T.eq(MiniUI.Shade.Visible, false, "kein Dialog")
		-- komplett: frei, Vorschau, Bestätigung -> tycoon_rebirth
		s = runSnapshot(g, "autohaus", function(run, d)
			completeStage5(run, GC)
			run.rebirthBoost = 0.15
			d.games.tycoon.runsDone.autohaus = 1
			d.games.tycoon.rebirths = 1
		end)
		render(g, p, mod, s)
		T.check(withText(byName(page, "RunCard"), "Stufe 5 komplett") ~= nil, "Kopf meldet komplett")
		T.check(withText(byName(page, "RunCard"), "Rebirth-Boost: +15 %") ~= nil, "aktueller Boost im Kopf")
		rb = byName(page, "RebirthButton")
		T.check(enabled(rb), "Rebirth frei")
		local preview = byName(page, "RebirthPreview").Text
		T.check(preview:find("Nach dem Rebirth: +30 %", 1, true) ~= nil, "Boost-Vorschau: " .. preview)
		T.check(preview:find("Händlerrabatt", 1, true) ~= nil and preview:find("1 → 2", 1, true) ~= nil, "Open-World-Vorschau: " .. preview)
		T.check(withText(byName(page, "RebirthCard"), "Erfüllt") ~= nil, "Voraussetzung erfüllt")
		press(g, rb)
		T.eq(rec.Count("tycoon_rebirth"), 0, "vor der Bestätigung nichts")
		T.eq(MiniUI.Shade.Visible, true, "Bestätigungsdialog")
		T.check(MiniUI.ConfirmText.Text:find("Bargeld verfällt", 1, true), "Dialog erklärt den Verlust des Bargelds")
		-- Zurück schließt ohne Senden
		local back = find(MiniUI.Shade, function(x)
			return x:IsA("TextButton") and x.Text == "Zurück"
		end)
		press(g, back)
		T.eq(rec.Count("tycoon_rebirth"), 0, "Zurück sendet nichts")
		press(g, rb)
		press(g, MiniUI.ConfirmYes)
		T.eq(rec.Count("tycoon_rebirth"), 1, "tycoon_rebirth nach Bestätigung")
		T.eq(next(rec.Last("tycoon_rebirth")), nil, "ohne Felder")
		-- Hinweise
		local nT = #toasts
		g:InClient(p, function()
			mod.OnNotice({ kind = "tycoon", event = "rebirth", boost = 0.3 })
			mod.OnNotice({ kind = "tycoon_stage", event = "stage", stage = 3, building = "autohaus" })
			mod.OnNotice({ kind = "tycoon_stage", event = "upgrade", id = "autohaus_s3_u1", stage = 3 })
		end)
		T.eq(#toasts, nT + 1, "nur der Rebirth-Hinweis als Toast (Stufen-Toasts kommen vom Server)")
		T.check(toasts[#toasts]:find("Rebirth geschafft", 1, true), "Rebirth-Hinweis")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "TycoonUI: Handel – Angebote an mich (Annehmen), meine Angebote (Zurückziehen), neues Angebot mit Spielerwahl, Ware, Menge/Preis-Steppern (≥ 44 px); Marktplatz-Tafel", function(T, H)
		local g, p = startClient(H)
		local ben = g:Join(2002, { name = "Ben" })
		g:Advance(0.5)
		local rec = recorder(T)
		local mod, page, MiniUI, toasts = build(g, p, "TycoonUI", rec)
		local GC = g:MiniShared("GameConfig")
		local s = runSnapshot(g, "produktion", function(run)
			run.cash = 500
			run.storage.bauteile = 30
			run.storage.lack = 2
		end, "tycoon")
		s.tycoon.offers = {
			{ id = 7, from = 2002, fromName = "Ben", to = 1001, toName = "Tester", item = "reifen", qty = 4, price = 200, expiresAt = NOW + 100 },
			{ id = 8, from = 3003, fromName = "Cleo", to = 1001, toName = "Tester", item = "lack", qty = 2, price = 900, expiresAt = NOW + 100 },
			{ id = 9, from = 1001, fromName = "Tester", to = 2002, toName = "Ben", item = "bauteile", qty = 10, price = 350, expiresAt = NOW + 100 },
		}
		s.tycoonPlayers = { { userId = 2002, name = "Ben" }, { userId = 3003, name = "Cleo" }, { userId = 1001, name = "Tester" } }
		render(g, p, mod, s)
		T.eq(byName(page, "TradeCard").Visible, true, "Handel sichtbar")
		-- Angebote an mich
		local in1, in2 = byName(page, "Incoming_1"), byName(page, "Incoming_2")
		T.check(in1 and in1.Visible and withText(in1, "Ben: 4 × Reifen für 200 Bargeld") ~= nil, "Angebot von Ben")
		T.check(in2 and in2.Visible and withText(in2, "Cleo: 2 × Lack für 900 Bargeld") ~= nil, "Angebot von Cleo")
		T.check(enabled(byName(page, "Accept_1")), "Ben annehmbar (500 ≥ 200)")
		T.check(not enabled(byName(page, "Accept_2")), "Cleo zu teuer (500 < 900)")
		T.eq(byName(page, "IncomingEmpty").Visible, false, "kein Leer-Hinweis")
		press(g, byName(page, "Accept_1"))
		local sent = rec.Last("tycoon_trade_accept")
		T.check(sent ~= nil and sent.id == 7, "tycoon_trade_accept id 7")
		press(g, byName(page, "Accept_2"))
		T.eq(rec.Count("tycoon_trade_accept"), 1, "zu teuer: nichts gesendet")
		-- meine Angebote
		local out1 = byName(page, "Outgoing_1")
		T.check(out1 and out1.Visible and withText(out1, "An Ben: 10 × Bauteile für 350 Bargeld") ~= nil, "mein Angebot an Ben")
		press(g, byName(page, "Cancel_1"))
		sent = rec.Last("tycoon_trade_cancel")
		T.check(sent ~= nil and sent.id == 9, "tycoon_trade_cancel id 9")
		-- neues Angebot: ohne Spieler nichts senden, Liste öffnet sich
		local offerBtn = byName(page, "OfferButton")
		T.check(not enabled(offerBtn), "ohne Spieler gesperrt")
		T.eq(byName(page, "PlayerList").Visible, false, "Liste zu")
		press(g, byName(page, "PlayerPick"))
		T.eq(byName(page, "PlayerList").Visible, true, "Liste offen")
		local p1, p2 = byName(page, "Player_1"), byName(page, "Player_2")
		T.check(p1 and p1.Text == "Ben" and p2 and p2.Text == "Cleo", "Spieler alphabetisch, ohne mich: " .. tostring(p1 and p1.Text) .. ", " .. tostring(p2 and p2.Text))
		T.eq(byName(page, "Player_3"), nil, "ich selbst nicht in der Liste")
		T.check(p1.AbsoluteSize.Y >= 44, "Spielerknopf ≥ 44 px")
		press(g, p1)
		T.eq(byName(page, "PlayerList").Visible, false, "Liste schließt nach Auswahl")
		T.check(byName(page, "PlayerPick").Text:find("An: Ben", 1, true), "Ben gewählt")
		-- Ware: bauteile (30 im Lager) ist Standard; Menge über Stepper
		for _, item in ipairs(GC.Tycoon.ItemList) do
			local b = byName(page, "Item_" .. item)
			T.check(b ~= nil and b.AbsoluteSize.Y >= 44, "Warenknopf " .. item)
		end
		T.check(byName(page, "Item_bauteile").Text:find("(30)", 1, true), "Lagerstand am Warenknopf")
		local qPlus, qMinus, pPlus, pMinus = byName(page, "QtyPlus"), byName(page, "QtyMinus"), byName(page, "PricePlus"), byName(page, "PriceMinus")
		for _, b in ipairs({ qPlus, qMinus, pPlus, pMinus }) do
			T.check(b ~= nil and b.AbsoluteSize.X >= 44 and b.AbsoluteSize.Y >= 44, "Stepper-Knopf ≥ 44 px")
		end
		T.check(byName(page, "QtyValue").Text == "Menge: 1", "Menge 1")
		T.check(byName(page, "PriceValue").Text:find("40 Bargeld", 1, true), "Richtpreis 40 je Bauteil: " .. byName(page, "PriceValue").Text)
		press(g, qPlus)
		press(g, qPlus)
		press(g, qPlus)
		T.eq(mod.TradeState().qty, 4, "Menge 4")
		T.eq(mod.TradeState().price, 160, "Richtpreis folgt der Menge (4 × 40)")
		press(g, qMinus)
		T.eq(mod.TradeState().qty, 3, "Menge 3")
		press(g, pPlus)
		T.check(mod.TradeState().price > 120, "Preis erhöht: " .. tostring(mod.TradeState().price))
		local raised = mod.TradeState().price
		press(g, pMinus)
		press(g, pMinus)
		T.check(mod.TradeState().price < raised and mod.TradeState().price >= 1, "Preis gesenkt")
		press(g, qPlus)
		T.eq(mod.TradeState().qty, 4, "Menge 4 (Preis bleibt, weil von Hand geändert)")
		press(g, byName(page, "GuideButton"))
		T.eq(mod.TradeState().price, 160, "Richtpreis übernommen")
		-- senden: tycoon_trade_offer {to, item, qty, price}
		T.check(enabled(offerBtn), "Angebot möglich")
		press(g, offerBtn)
		sent = rec.Last("tycoon_trade_offer")
		T.check(sent ~= nil, "tycoon_trade_offer gesendet")
		if sent then
			T.eq(sent.to, 2002, "to = Ben")
			T.eq(sent.item, "bauteile", "item")
			T.eq(sent.qty, 4, "qty")
			T.eq(sent.price, 160, "price (Absicht in Bargeld)")
			local n = 0
			for _ in pairs(sent) do
				n += 1
			end
			T.eq(n, 4, "genau vier Felder")
		end
		-- andere Ware ohne Lager: gesperrt mit Hinweis
		press(g, byName(page, "Item_reifen"))
		T.check(not enabled(offerBtn), "Reifen: keine im Lager")
		T.check(byName(page, "OfferHint").Text:find("nur 0 × Reifen", 1, true), "Hinweis Lager: " .. byName(page, "OfferHint").Text)
		press(g, offerBtn, { force = true })
		T.eq(rec.Count("tycoon_trade_offer"), 1, "ohne Ware nichts gesendet")
		-- Menge über den Lagerstand (Lack 2): gesperrt
		press(g, byName(page, "Item_lack"))
		T.check(not enabled(offerBtn), "Lack 2 < Menge 4")
		press(g, qMinus)
		press(g, qMinus)
		T.check(enabled(offerBtn), "Lack 2 = Menge 2")
		-- Spieler verschwindet aus dem Snapshot: Auswahl fällt zurück
		s.tycoonPlayers = { { userId = 3003, name = "Cleo" } }
		render(g, p, mod, s)
		T.check(not enabled(offerBtn) and byName(page, "PlayerPick").Text:find("wählen", 1, true), "Ben weg: Auswahl zurückgesetzt")
		-- ohne Snapshot-Liste: KEIN Rückfall auf Players:GetPlayers() (Ben ist im Server, aber ohne Durchlauf nicht handelbar)
		s.tycoonPlayers = nil
		render(g, p, mod, s)
		press(g, byName(page, "PlayerPick"))
		local row1 = byName(page, "Player_1")
		T.check(row1 == nil or not row1.Visible, "ohne Liste kein Spieler aus Players:GetPlayers()")
		T.check(byName(page, "PlayersEmpty") and byName(page, "PlayersEmpty").Visible, "Hinweis „Niemand da“")
		-- Serverliste tycoon.players (Tycoon-Spieler mit Durchlauf)
		s.tycoon.players = { { userId = 2002, name = "Ben" } }
		render(g, p, mod, s)
		press(g, byName(page, "PlayerPick"))
		row1 = byName(page, "Player_1")
		T.check(row1 and row1.Visible and row1.Text == "Ben", "Spielerliste aus tycoon.players: " .. tostring(row1 and row1.Text))
		s.tycoon.players = nil
		-- Marktplatz-Tafel (nur Client): Text aus mini_notice tycoon_market
		local label = g:Find("Workspace.Tycoon.Markt.Tafel.MarketScreen.Offers")
		T.check(label ~= nil, "Tafel-Label in der Fixture")
		g:InClient(p, function()
			mod.OnNotice({ kind = "tycoon_market", offers = {
				{ id = 1, from = 2002, fromName = "Ben", toName = "Cleo", item = "reifen", qty = 4, price = 200 },
				{ id = 2, from = 3003, fromName = "Cleo", item = "schrott", qty = 50, price = 1000 },
			} })
		end)
		T.check(label.Text:find("Ben → Cleo: 4 × Reifen für 200", 1, true) ~= nil, "Tafel Zeile 1: " .. label.Text)
		T.check(label.Text:find("Cleo: 50 × Schrott für 1.000", 1, true) ~= nil, "Tafel Zeile 2")
		g:InClient(p, function()
			mod.OnNotice({ kind = "tycoon_market", offers = {} })
		end)
		T.check(label.Text:find("noch keine", 1, true) ~= nil, "Tafel leer")
		-- Handels-Hinweise: keine eigenen Toasts (der Server meldet Angebot/Annahme selbst), kein Fehler
		local n = #toasts
		g:InClient(p, function()
			mod.OnNotice({ kind = "trade", event = "offered", id = 11, from = 2002, fromName = "Ben", to = 1001, toName = "Tester", item = "reifen", qty = 4, price = 200 })
			mod.OnNotice({ kind = "trade", event = "accepted", id = 11, item = "reifen", qty = 4 })
		end)
		T.eq(#toasts, n, "keine doppelten Handels-Toasts")
		-- außerhalb des Geländes kein Handel
		render(g, p, mod, runSnapshot(g, "produktion", nil, "openworld"))
		T.eq(byName(page, "TradeCard").Visible, false, "Open World: kein Handel")
		g:Leave(ben)
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "TycoonUI: Handy-Layouts 390×844 und 844×390 – eine Spalte, kein Überlauf, Knöpfe ≥ 44 px", function(T, H)
		for _, vp in ipairs({ Vector2.new(390, 844), Vector2.new(844, 390) }) do
			local g, p = startClient(H, { viewport = vp })
			local rec = recorder(T)
			local mod, page, MiniUI = build(g, p, "TycoonUI", rec)
			local GC = g:MiniShared("GameConfig")
			g:InClient(p, function()
				MiniUI.Open("overview")
				-- die echte Seite des Panels nutzen: Inhaltbreite wie im Panel
				page.Size = UDim2.new(0, MiniUI.Content.AbsoluteSize.X - 8, 0, 0)
			end)
			local s = runSnapshot(g, "schrottplatz", function(run)
				run.cash = 300
				run.storage.schrott = 9
			end)
			s.tycoonPlayers = { { userId = 5, name = "Dana" } }
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
							T.check(false, tag .. ": ragt heraus: " .. x:GetFullName() .. " (" .. tostring(right) .. " > " .. tostring(page.AbsolutePosition.X + width) .. ")")
						end
					end
					if x:IsA("TextButton") and x.AbsoluteSize.Y < 44 then
						T.check(false, tag .. ": Knopf unter 44 px: " .. x:GetFullName())
					end
				end
			end
			T.eq(bad, 0, tag .. ": nichts ragt heraus")
			T.check(byName(page, "ItemRow").AbsoluteSize.X <= width, tag .. ": Warenreihe passt")
			for _, item in ipairs(GC.Tycoon.ItemList) do
				T.check(byName(page, "Item_" .. item).AbsoluteSize.X >= 44, tag .. ": Warenknopf " .. item .. " breit genug")
			end
			g:InClient(p, function()
				MiniUI.Close()
			end)
			T.eq(g:ErrorText(), "", tag .. ": keine Fehler")
			g:Close()
		end
	end },

	{ "TycoonClient: Bargeld-Abzeichen nur im Modus tycoon, unter dem Prestige-Abzeichen, weg bei Panel/Tablet/QTE/Tacho; Blitz bei neuer Stufe; Hinweis „choose“ öffnet den Tab", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local PrestigeUI, _, MiniUI, _, state, ctx = build(g, p, "PrestigeUI", rec)
		local opened = {}
		ctx.Open = function(tab)
			table.insert(opened, tab)
		end
		local mod = g:ClientModule(p, "Mini.TycoonClient")
		g:InClient(p, function()
			mod.Start(ctx)
		end)
		local hudGui = p.PlayerGui:FindFirstChild("TycoonHUD")
		T.check(hudGui ~= nil and hudGui.ClassName == "ScreenGui", "ScreenGui TycoonHUD")
		T.check(hudGui and hudGui.DisplayOrder < 20, "unter dem 2.4.0-UI")
		local badge = hudGui and hudGui:FindFirstChild("Bargeld")
		T.check(badge ~= nil, "Abzeichen „Bargeld“")
		T.eq(mod.HudVisible(), false, "ohne Snapshot aus")
		-- Lobby / Open World: aus
		g:InClient(p, function()
			PrestigeUI.OnSnapshot(base("lobby"))
			PrestigeUI.Step(1)
			mod.OnSnapshot(base("lobby"))
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "Lobby: aus")
		g:InClient(p, function()
			mod.OnSnapshot(base("openworld"))
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "Open World: aus")
		-- Tycoon ohne Durchlauf: an, Text „Kein Durchlauf“
		g:InClient(p, function()
			mod.OnSnapshot(base("tycoon"))
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), true, "Tycoon: an")
		T.check(byName(hudGui, "Status").Text:find("Kein Durchlauf", 1, true), "ohne Durchlauf: Hinweis")
		-- Lage: rechts, unter dem Prestige-Abzeichen
		T.eq(badge.AnchorPoint.X, 1, "rechts verankert")
		T.eq(badge.Position.X.Offset, -16, "16 px Rand")
		local prestigeBottom = PrestigeUI.HudBottom()
		T.check(prestigeBottom > 0, "Prestige-Abzeichen hat eine Unterkante")
		T.check(badge.Position.Y.Offset >= prestigeBottom + 4, "unter dem Prestige-Abzeichen (" .. tostring(badge.Position.Y.Offset) .. " ≥ " .. tostring(prestigeBottom) .. ")")
		T.check(mod.HudBottom() > badge.Position.Y.Offset, "HudBottom unter der Oberkante")
		-- mit Durchlauf: Bargeld und Behälter
		local s = runSnapshot(g, "werkstatt", function(run)
			run.cash = 1234
			run.container = 100
		end)
		g:InClient(p, function()
			mod.OnSnapshot(s)
			mod.Step(1)
		end)
		T.eq(byName(hudGui, "Cash").Text, "Bargeld: 1.234", "Bargeld-Zeile")
		T.check(byName(hudGui, "Status").Text:find("Behälter", 1, true) and byName(hudGui, "Status").Text:find("Stufe 1", 1, true), "Statuszeile: " .. byName(hudGui, "Status").Text)
		-- Panel offen: weg; zu: wieder da
		g:InClient(p, function()
			MiniUI.Open("overview")
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "bei offenem Panel weg")
		g:InClient(p, function()
			MiniUI.Close()
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), true, "nach dem Schließen wieder da")
		state.tablet = true
		g:InClient(p, function()
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "bei offenem Tablet weg")
		state.tablet = false
		state.blocked = true
		g:InClient(p, function()
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "bei QTE/Diagnose weg")
		state.blocked = false
		g:InClient(p, function()
			local fahren = Instance.new("ScreenGui")
			fahren.Name = "Fahren"
			fahren.Enabled = true
			fahren.Parent = p.PlayerGui
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "bei sichtbarem Tacho weg")
		g:InClient(p, function()
			p.PlayerGui.Fahren.Enabled = false
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), true, "ohne Tacho wieder da")
		-- Stufenaufstieg im Snapshot: Blitz (UIScale springt)
		local _, hud = mod.Hud()
		local s2 = runSnapshot(g, "werkstatt", function(run)
			run.stage = 2
			run.cash = 10
		end)
		g:InClient(p, function()
			mod.OnSnapshot(s2)
		end)
		T.check(hud.scale.Scale > 1.05, "Blitz bei neuer Stufe")
		g:Advance(0.6)
		T.check(math.abs(hud.scale.Scale - 1) < 0.01, "Blitz klingt ab")
		-- Hinweis „choose“ öffnet den Tab tycoon (über ctx.Open)
		g:InClient(p, function()
			mod.OnNotice({ kind = "tycoon", event = "choose", slot = 1 })
			mod.OnNotice({ kind = "tycoon_choose" })
		end)
		T.eq(#opened, 2, "Tab zweimal geöffnet")
		T.eq(opened[1], "tycoon", "Tab tycoon")
		state.blocked = true
		g:InClient(p, function()
			mod.OnNotice({ kind = "tycoon", event = "choose" })
		end)
		T.eq(#opened, 2, "während QTE nicht geöffnet")
		state.blocked = false
		-- zurück in die Lobby: aus
		g:InClient(p, function()
			mod.OnSnapshot(base("lobby"))
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "Lobby: wieder aus")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "TycoonClient: Pad-Blitz (rein optisch, entprellt) und Produzenten-Animationen stamp/conveyor unter Tycoon.Plots", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local _, _, _, _, _, ctx = build(g, p, "PrestigeUI", rec)
		local mod = g:ClientModule(p, "Mini.TycoonClient")
		local plots = g:Find("Workspace.Tycoon.Plots")
		local slot = plots and plots:FindFirstChild("Slot_1")
		T.check(slot ~= nil, "Tycoon.Plots.Slot_1 in der Fixture")
		local startPad = slot and slot:FindFirstChild("StartPad")
		local collectPad = slot and slot:FindFirstChild("CollectPad")
		-- Vorlage nachstellen: Kaufpad mit Schild, Stempel-Produzent, Förderband (vor dem Start, wie eine gebaute Stufe)
		local buttons = slot:FindFirstChild("ButtonsRoot")
		local pad, stamp, mover, belt, conveyor
		g:InClient(p, function()
			pad = Instance.new("Part")
			pad.Name = "Pad_werkstatt_s1_u1"
			pad.Size = Vector3.new(4, 0.5, 4)
			pad.Anchored = true
			pad.Color = Color3.fromRGB(60, 120, 200)
			pad.CFrame = CFrame.new(-45, 0.25, 770)
			pad:SetAttribute("TycoonButton", "werkstatt_s1_u1")
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Label"
			gui.Parent = pad
			local name = Instance.new("TextLabel")
			name.Name = "Name"
			name.Text = "Hebebühne"
			name.TextColor3 = Color3.new(1, 1, 1)
			name.Parent = gui
			local price = Instance.new("TextLabel")
			price.Name = "Price"
			price.Text = "140 Bargeld"
			price.TextColor3 = Color3.new(1, 1, 1)
			price.Parent = gui
			pad.Parent = buttons or slot

			stamp = Instance.new("Model")
			stamp.Name = "Producer_1"
			stamp:SetAttribute("Anim", "stamp")
			local root = Instance.new("Part")
			root.Name = "Root"
			root.Size = Vector3.new(4, 1, 4)
			root.Anchored = true
			root.CFrame = CFrame.new(-50, 0.5, 750)
			root.Parent = stamp
			stamp.PrimaryPart = root
			mover = Instance.new("Part")
			mover.Name = "Stempel"
			mover.Size = Vector3.new(2, 2, 2)
			mover.Anchored = true
			mover.CFrame = CFrame.new(-50, 4, 750)
			mover.Parent = stamp
			stamp.Parent = slot

			conveyor = Instance.new("Model")
			conveyor.Name = "Producer_2"
			conveyor:SetAttribute("TycoonAnim", "conveyor")
			conveyor:SetAttribute("Speed", 2)
			belt = Instance.new("Part")
			belt.Name = "Band"
			belt.Size = Vector3.new(8, 0.5, 2)
			belt.Anchored = true
			belt.CFrame = CFrame.new(-40, 1, 750)
			belt.Parent = conveyor
			conveyor.PrimaryPart = belt
			conveyor.Parent = slot
		end)
		g:InClient(p, function()
			workspace.CurrentCamera.CFrame = CFrame.new(-45, 12, 775)
			mod.Start(ctx)
		end)
		g:Advance(0.1)
		local counts = mod.Counts()
		T.eq(counts.kinds.stamp, 1, "ein Stempel erkannt")
		T.eq(counts.kinds.conveyor, 1, "ein Förderband erkannt")
		T.check(counts.pads >= 3, "Pads beobachtet (Start, Sammeln, Kaufpad): " .. tostring(counts.pads))
		-- Stempel bewegt sich relativ zum Pivot; nach einer Periode wieder oben
		local y0 = mover.Position.Y
		g:Advance(0.3)
		local moved = math.abs(mover.Position.Y - y0) > 0.05
		g:Advance(0.3)
		moved = moved or math.abs(mover.Position.Y - y0) > 0.05
		T.check(moved, "Stempel fährt (Y " .. tostring(y0) .. " → " .. tostring(mover.Position.Y) .. ")")
		T.check(mover.Position.Y <= y0 + 0.01, "Stempel nie über der Ruhelage")
		T.check(math.abs(mover.Position.X + 50) < 0.01 and math.abs(mover.Position.Z - 750) < 0.01, "Stempel bleibt in der Spur")
		-- Versetzte Vorlage: Modell verschoben -> Stempel folgt dem Pivot
		g:InClient(p, function()
			stamp:PivotTo(CFrame.new(-50, 0.5, 760))
		end)
		g:Advance(0.1)
		T.check(math.abs(mover.Position.Z - 760) < 0.01, "Stempel folgt dem verschobenen Modell")
		-- Förderband: lokale Kisten angelegt, wandern in X und bleiben auf dem Band
		local cargo = conveyor:FindFirstChild("LocalCargo")
		T.check(cargo ~= nil and #cargo:GetChildren() == 3, "3 lokale Kisten")
		local box = cargo and cargo:GetChildren()[1]
		local x0 = box and box.Position.X
		g:Advance(0.5)
		T.check(box and math.abs(box.Position.X - x0) > 0.2, "Kiste wandert")
		local ok = true
		for _, b in ipairs(cargo:GetChildren()) do
			if math.abs(b.Position.X + 40) > 4.01 or math.abs(b.Position.Z - 750) > 0.01 or b.CanCollide or b.CanTouch then
				ok = false
			end
		end
		T.check(ok, "Kisten bleiben auf dem Band, ohne Kollision")
		-- Pad-Blitz: Farbe hell, Schild-UIScale springt, Schrift gelb; entprellt; Farbe kehrt zurück
		local baseColor = pad.Color
		g:InClient(p, function()
			mod.PadFlash(pad)
		end)
		T.check(pad.Color ~= baseColor, "Pad heller")
		local scale = pad.Label:FindFirstChild("PadFlashScale")
		T.check(scale ~= nil and scale.Scale > 1.05, "Schild stößt")
		T.check(pad.Label:FindFirstChild("Name").TextColor3 ~= Color3.new(1, 1, 1), "Schrift gelb")
		g:InClient(p, function()
			mod.PadFlash(pad)
		end)
		T.eq(mod.PadInfo(pad).flashes, 1, "entprellt: zweiter Blitz innerhalb 0,5 s ignoriert")
		g:Advance(0.8)
		T.check(pad.Color == baseColor, "Farbe zurück")
		T.check(pad.Label:FindFirstChild("Name").TextColor3 == Color3.new(1, 1, 1), "Schrift zurück")
		T.check(scale.Scale <= 1.001, "Schild wieder normal")
		g:InClient(p, function()
			mod.PadFlash(pad)
		end)
		T.eq(mod.PadInfo(pad).flashes, 2, "nach der Entprellzeit wieder ein Blitz")
		-- Touched durch die eigene Figur blitzt, fremde Teile nicht
		local root = g:Root(p)
		T.check(root ~= nil, "Figur da")
		g:Advance(0.6)
		local before = mod.PadInfo(startPad) and mod.PadInfo(startPad).flashes or 0
		g:InClient(p, function()
			local other = Instance.new("Part")
			other.Parent = workspace
			startPad.Touched:Fire(other)
		end)
		T.eq((mod.PadInfo(startPad) and mod.PadInfo(startPad).flashes or 0), before, "fremdes Teil: kein Blitz")
		g:InClient(p, function()
			startPad.Touched:Fire(root)
		end)
		T.eq((mod.PadInfo(startPad) and mod.PadInfo(startPad).flashes or 0), before + 1, "eigene Figur: Blitz am Startpad")
		g:Advance(0.6)
		g:InClient(p, function()
			collectPad.Touched:Fire(root)
		end)
		T.eq(mod.PadInfo(collectPad).flashes, 1, "Sammelpad blitzt")
		-- Spät hinzugefügter Produzent wird erkannt (DescendantAdded)
		g:InClient(p, function()
			local late = Instance.new("Model")
			late.Name = "Producer_3"
			late:SetAttribute("Anim", "stamp")
			local r = Instance.new("Part")
			r.Name = "Root"
			r.Anchored = true
			r.CFrame = CFrame.new(45, 0.5, 750)
			r.Parent = late
			late.PrimaryPart = r
			local m = Instance.new("Part")
			m.Name = "Kolben"
			m.Anchored = true
			m.Size = Vector3.new(1, 3, 1)
			m.CFrame = CFrame.new(45, 4, 750)
			m.Parent = late
			late.Parent = slot
		end)
		g:Advance(0.2)
		T.eq(mod.Counts().kinds.stamp, 2, "später Stempel erkannt")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "TycoonClient: Pad-Blitz kehrt auf die Server-Zustandsfarbe zurück (TycoonState), auch wenn der Zustand mitten im Blitz wechselt; Datensätze zerstörter Pads werden freigegeben", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local _, _, _, _, _, ctx = build(g, p, "PrestigeUI", rec)
		local mod = g:ClientModule(p, "Mini.TycoonClient")
		local GC = g:MiniShared("GameConfig")
		local PC = GC.Tycoon.PadColors
		local locked = Color3.fromRGB(PC.locked[1], PC.locked[2], PC.locked[3])
		local owned = Color3.fromRGB(PC.owned[1], PC.owned[2], PC.owned[3])
		local ready = Color3.fromRGB(PC.ready[1], PC.ready[2], PC.ready[3])
		local slot = g:Find("Workspace.Tycoon.Plots.Slot_1")
		local pad, price
		g:InClient(p, function()
			pad = Instance.new("Part")
			pad.Name = "Button_1"
			pad.Size = Vector3.new(5, 0.5, 5)
			pad.Anchored = true
			pad.Color = locked
			pad.CFrame = CFrame.new(-45, 0.25, 772)
			pad:SetAttribute("TycoonButton", "werkstatt_s1_u1")
			pad:SetAttribute("TycoonState", "locked")
			local gui = Instance.new("SurfaceGui")
			gui.Name = "Label"
			gui.Parent = pad
			price = Instance.new("TextLabel")
			price.Name = "Price"
			price.Text = "140 Bargeld"
			price.TextColor3 = locked
			price.Parent = gui
			pad.Parent = slot:FindFirstChild("ButtonsRoot") or slot
			workspace.CurrentCamera.CFrame = CFrame.new(-45, 12, 775)
			mod.Start(ctx)
		end)
		g:Advance(0.1)
		-- Blitz auf gesperrtem Pad, dann (wie der Server nach dem Kauf) Zustand + Farben auf „owned“ mitten im Tween
		g:InClient(p, function()
			mod.PadFlash(pad)
		end)
		T.check(pad.Color ~= locked, "Pad heller")
		g:Advance(0.1)
		pad:SetAttribute("TycoonState", "owned")
		pad.Color = owned
		price.TextColor3 = owned
		g:Advance(0.1)
		T.check(pad.Color == owned, "Zustandswechsel im Blitz: Pad sofort grün")
		g:Advance(0.8)
		T.check(pad.Color == owned, "nach dem Tween: Pad bleibt grün (nicht auf Grau zurück)")
		T.check(price.TextColor3 == owned, "Preisschild bleibt grün")
		-- späterer Blitz (Laufanimation) auf dem gekauften Pad: zurück auf die Zustandsfarbe, nicht auf die alte Sperrfarbe
		g:InClient(p, function()
			mod.PadFlash(pad)
		end)
		T.check(pad.Color ~= owned, "Blitz auf gekauftem Pad")
		g:Advance(0.8)
		T.check(pad.Color == owned, "zurück auf Grün")
		T.check(price.TextColor3 == owned, "Preisschild wieder grün")
		-- locked -> ready außerhalb eines Blitzes: der nächste Blitz endet auf Amber
		pad:SetAttribute("TycoonState", "ready")
		pad.Color = ready
		price.TextColor3 = ready
		g:Advance(0.6)
		g:InClient(p, function()
			mod.PadFlash(pad)
		end)
		g:Advance(0.8)
		T.check(pad.Color == ready and price.TextColor3 == ready, "Blitz endet auf der Ready-Farbe")
		-- Zerstörtes Pad (Stufenwechsel): Datensatz weg
		local padsBefore = mod.Counts().pads
		T.check(mod.PadInfo(pad) ~= nil, "Pad beobachtet")
		g:InClient(p, function()
			pad:Destroy()
		end)
		g:Advance(0.6)
		T.eq(mod.PadInfo(pad), nil, "Datensatz nach Destroy freigegeben")
		T.eq(mod.Counts().pads, padsBefore - 1, "Pad-Zähler kleiner")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },

	{ "TycoonClient: Handy hochkant – Freischaltungs- und Hinweiskarten liegen unter dem Bargeld-Abzeichen und rücken nach, wenn es verschwindet", function(T, H)
		local g, p = startClient(H, { viewport = Vector2.new(390, 844) })
		local rec = recorder(T)
		local PrestigeUI, _, MiniUI, _, _, ctx = build(g, p, "PrestigeUI", rec)
		local UnlocksUI = build(g, p, "UnlocksUI", rec)
		local TutorialUI = build(g, p, "TutorialUI", rec)
		local mod = g:ClientModule(p, "Mini.TycoonClient")
		g:InClient(p, function()
			mod.Start(ctx)
			PrestigeUI.OnSnapshot(base("tycoon"))
			PrestigeUI.Step(1)
			mod.OnSnapshot(base("tycoon"))
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), true, "Bargeld-Abzeichen sichtbar")
		local hudGui = p.PlayerGui:FindFirstChild("TycoonHUD")
		local badge = hudGui and hudGui:FindFirstChild("Bargeld")
		local prestigeBottom = PrestigeUI.HudBottom()
		T.check(badge and badge.Position.Y.Offset >= prestigeBottom, "Abzeichen unter dem Prestige-Abzeichen (schmal: y " .. tostring(badge and badge.Position.Y.Offset) .. ")")
		local tyBottom = mod.HudBottom()
		T.check(tyBottom > 130, "Bargeld-Unterkante unter der Toast-Zone (schmal): " .. tostring(tyBottom))
		-- Freischaltungskarte: unter dem Bargeld-Abzeichen
		g:InClient(p, function()
			UnlocksUI.ShowCard("Neu freigeschaltet", "Schnelles Spiel")
		end)
		local cardsGui = p.PlayerGui:FindFirstChild("UnlockCards")
		local card = cardsGui and cardsGui:FindFirstChild("UnlockCard")
		T.check(card ~= nil and card.Visible, "Karte sichtbar")
		local cardTop = card and (card.AbsolutePosition.Y - cardsGui.AbsolutePosition.Y) or 0
		T.check(cardTop >= tyBottom, "Karte unter dem Bargeld-Abzeichen (" .. tostring(cardTop) .. " ≥ " .. tostring(tyBottom) .. ")")
		local overlayTop = g:InClient(p, function()
			return PrestigeUI.OverlayTop()
		end)
		T.check(overlayTop >= tyBottom + PrestigeUI.CardGap, "PrestigeUI.OverlayTop rechnet das Bargeld-Abzeichen ein (" .. tostring(overlayTop) .. ")")
		-- Hinweiskarte: unter der Freischaltungskarte, also auch unter dem Abzeichen
		g:InClient(p, function()
			TutorialUI.ShowHint("Sammle Bargeld am Sammel-Pad.", "h_tycoon")
			TutorialUI.Step(0.3)
		end)
		local tutGui = p.PlayerGui:FindFirstChild("Tutorial")
		local hint = tutGui and tutGui:FindFirstChild("HintCard", true)
		T.check(hint ~= nil and hint.Visible, "Hinweiskarte sichtbar")
		local hintTop = hint and (hint.AbsolutePosition.Y - tutGui.AbsolutePosition.Y) or 0
		T.check(hintTop >= tyBottom, "Hinweiskarte unter dem Bargeld-Abzeichen (" .. tostring(hintTop) .. ")")
		T.check(hintTop >= cardTop + card.AbsoluteSize.Y, "Hinweiskarte unter der Freischaltungskarte")
		-- Abzeichen verschwindet (Panel offen): Karten rücken nach oben
		g:InClient(p, function()
			MiniUI.Open("overview")
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "Abzeichen weg")
		local cardTop2 = card.AbsolutePosition.Y - cardsGui.AbsolutePosition.Y
		T.check(cardTop2 < cardTop, "Karte rückt nach oben (" .. tostring(cardTop2) .. " < " .. tostring(cardTop) .. ")")
		T.check(cardTop2 >= prestigeBottom, "aber unter dem Prestige-Abzeichen")
		g:InClient(p, function()
			MiniUI.Close()
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), true, "Abzeichen wieder da")
		local cardTop3 = card.AbsolutePosition.Y - cardsGui.AbsolutePosition.Y
		T.check(cardTop3 >= mod.HudBottom(), "Karte wieder darunter")
		T.eq(g:ErrorText(), "", "keine Fehler")
	end },
}
