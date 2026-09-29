-- Ausbaustufe 4, Meilenstein 1 (Team prestige): PrestigeService im echten Server (eigene Aktionen-Tabelle wie
-- test_cars, unabhängig von der MiniService-Verkabelung), CrossBonus-Deckel, CarCatalog-Level aus GameConfig.Unlocks,
-- PrestigeUI/UnlocksUI im Mock-Client. Der Fall „echter Weg“ prüft Remotes.Command, sobald MiniNet die Aktionen kennt.
local NOW = 1760000000

---------------------------------------------------------------- Hilfen
-- meta/prestige im Profil sicherstellen (bis MiniRules.DefaultGames/LoadGames MetaRules aufrufen)
local function ensureMeta(g, d)
	if type(d.games.prestige) ~= "table" or type(d.games.meta) ~= "table" then
		g:MiniShared("MetaRules").ApplyDefault(d.games)
	end
end

-- Server mit PrestigeService über eine eigene Aktionen-Tabelle und eine protokollierende api
local function setup(H, opts)
	local g = H.Garage(opts)
	local PS = g:MiniServer("PrestigeService")
	local log = { notices = {}, toasts = {}, dirty = 0 }
	local handlers = {}
	local fakeApi = {
		now = function()
			return g:Now()
		end,
		toast = function(ms, text)
			table.insert(log.toasts, { player = ms.player, text = text })
		end,
		notice = function(ms, kind, data)
			table.insert(log.notices, { player = ms.player, kind = kind, data = data })
		end,
		dirty = function(ms)
			log.dirty += 1
			ms.dirty = true
		end,
		worldChanged = function() end,
		writable = function()
			return false
		end,
		alive = function()
			return true
		end,
	}
	PS.Register({
		Register = function(name, fn)
			handlers[name] = fn
		end,
	}, fakeApi)
	local S = { g = g, PS = PS, log = log, handlers = handlers }
	function S.join(userId, name)
		local pl = g:Join(userId, { name = name })
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		local d = g:D(pl)
		ensureMeta(g, d)
		ms.greeted = true
		PS.OnJoin(ms, d, g:Now())
		return pl, ms, d
	end
	function S.act(pl, action, data)
		g:Activate()
		handlers[action](g:MiniState(pl), data or {}, g:D(pl), g:Now())
	end
	function S.tick(pl)
		g:Activate()
		return PS.Tick(g:MiniState(pl), g:D(pl), g:Now())
	end
	function S.notices(pl, kind)
		local out = {}
		for _, n in ipairs(log.notices) do
			if n.player == pl and n.kind == kind then
				table.insert(out, n.data)
			end
		end
		return out
	end
	function S.hasToast(pl, pattern)
		for _, t in ipairs(log.toasts) do
			if t.player == pl and string.find(t.text, pattern, 1, true) then
				return true
			end
		end
		return false
	end
	function S.clear()
		log.notices, log.toasts = {}, {}
	end
	return S
end

-- Level über den Server-Weg (MiniRules.GainXP -> R.GainXP) bis mindestens `target` treiben
local function levelTo(g, d, target)
	local MR = g:MiniShared("MiniRules")
	local guard = 0
	while d.level < target and guard < 50 do
		MR.GainXP(d, 200000)
		guard += 1
	end
	return d.level
end

local function hasKey(v, key, depth)
	depth = depth or 0
	if type(v) ~= "table" or depth > 8 then
		return false
	end
	for k, x in pairs(v) do
		if k == key or hasKey(x, key, depth + 1) then
			return true
		end
	end
	return false
end

-- Nur speicher-/sendbare Werte (keine Funktionen, keine unendlichen Zahlen, keine gemischten Tabellen)
local function sendable(v, depth)
	depth = depth or 0
	local t = type(v)
	if t == "number" then
		return v == v and v ~= math.huge and v ~= -math.huge
	elseif t == "string" or t == "boolean" then
		return true
	elseif t ~= "table" or depth > 10 then
		return false
	end
	local n = #v
	for k, x in pairs(v) do
		if n > 0 and type(k) ~= "number" then
			return false
		end
		if n == 0 and type(k) ~= "string" then
			return false
		end
		if not sendable(x, depth + 1) then
			return false
		end
	end
	return true
end

---------------------------------------------------------------- Client-Hilfen (wie test_cars_ui)
local FORBIDDEN = { amount = true, price = true, cost = true, credits = true, reward = true, money = true, cash = true, xp = true, level = true }

local function recorder(T)
	local r = { sent = {} }
	function r.Send(action, payload)
		payload = payload or {}
		local n = 0
		for k, v in pairs(payload) do
			n += 1
			local t = type(v)
			T.check(type(k) == "string" and (t == "string" or t == "number" or t == "boolean"), action .. ": flaches Feld " .. tostring(k))
			T.check(not FORBIDDEN[k], action .. ": kein Betrag/Level im Feld " .. tostring(k))
		end
		T.check(n <= 9, action .. ": höchstens 9 Felder")
		table.insert(r.sent, { action, payload })
		return #r.sent
	end
	function r.Count(name)
		local c = 0
		for _, a in ipairs(r.sent) do
			if a[1] == name then
				c += 1
			end
		end
		return c
	end
	function r.Last(name)
		for i = #r.sent, 1, -1 do
			if r.sent[i][1] == name then
				return r.sent[i][2]
			end
		end
		return nil
	end
	return r
end

-- Client ohne GarageClient/MiniClient (run = false): die UI-Bausteine bekommen hier ihren eigenen Kontext und
-- eigene Snapshots; die echte Verkabelung im laufenden Client prüft test_phase4.
local function startClient(H, opts)
	local g = H.Garage(opts)
	local p = g:Join(1001, { name = "Tester" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1.5)
	return g, p
end

local function build(g, p, modName, rec, ctxExtra)
	local MiniUI = g:ClientModule(p, "Mini.MiniUI")
	local mod = g:ClientModule(p, "Mini." .. modName)
	local toasts = {}
	local state = { tablet = false, blocked = false }
	local page = g:InClient(p, function()
		if not MiniUI.Gui then
			MiniUI.Build()
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "PrestigeTest_" .. modName
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
		mod.Build(frame, ctx)
		return frame
	end)
	return mod, page, MiniUI, toasts, state
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

local function enabled(b)
	return b ~= nil and b:GetAttribute("disabled") ~= true
end

local function press(g, button)
	g:Advance(0.35)
	local ok = g:Click(button)
	g:Advance(0.05)
	return ok
end

-- Test-Snapshot wie PrestigeService.SnapshotFields + 2.4.0-Felder
local function snapshot(g, level, opts)
	opts = opts or {}
	local PR = g:MiniShared("PrestigeRules")
	local U = g:MiniShared("Unlocks")
	local d = g:Rules().NewData(NOW)
	d.level = level
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	for _, r in ipairs(opts.claimed or {}) do
		d.games.prestige.claimed[r] = true
		d.games.prestige.titleRank = r
	end
	local PS = g:MiniServer("PrestigeService")
	local s = PS.SnapshotFields(nil, d, NOW, opts.full)
	s.level = level
	s.credits = 0
	s.xp = 0
	s.xpNeeded = 100
	s.prestige.rank = PR.Rank(d)
	s.unlocks.next = U.NextFor(d) and { key = U.NextFor(d).key, title = U.NextFor(d).title, level = U.NextFor(d).level } or false
	return s
end

---------------------------------------------------------------- Fälle
return {
	{ "CarCatalog: Händler-/Auktions-Level aus GameConfig.Unlocks (Elys 90), C.Cars unverändert", function(T, H)
		local g = H.Garage({ noServer = true })
		local CC, U, GC = g:MiniShared("CarCatalog"), g:MiniShared("Unlocks"), g:MiniShared("GameConfig")
		local C = g:Config()
		T.eq(CC.ModelById.elys.level, 90, "Elys 90")
		T.eq(CC.ModelById.komet.level, 3, "Komet 3")
		T.eq(CC.ModelById.komet_s2.level, 8, "Komet S2 8")
		T.eq(CC.ModelById.nord.level, 14, "Nord 14")
		T.eq(CC.ModelById.komet_urban.level, 22, "Urban 22")
		T.eq(CC.ModelById.atlas.level, 32, "Atlas 32")
		T.eq(CC.ModelById.vektor.level, 45, "Vektor 45")
		T.eq(CC.ModelById.vektor_gtx.level, 58, "GTX 58")
		T.eq(CC.ModelById.aureon.level, 72, "Aureon 72")
		T.eq(CC.ModelById.komet_rally.level, 10, "Rallye 10 (Sondermodell über car:<id>)")
		T.eq(CC.ModelById.nord_classic.level, 18, "Classic 18")
		T.eq(CC.ModelById.vektor_gold.level, 50, "Goldstück 50")
		T.eq(CC.ModelById.aureon_nero.level, 78, "Nero 78")
		T.eq(CC.ModelById.elys_proto.level, 95, "Prototyp 95")
		for _, m in ipairs(CC.Models) do
			T.eq(m.level, U.CarLevel(m.id), "Level = Unlocks.CarLevel " .. m.id)
			T.check(GC.UnlockByKey["car:" .. m.id] ~= nil, "Eintrag in GameConfig.Unlocks " .. m.id)
		end
		-- 2.4.0-Kundenautos: C.Cars[].level bleibt (Elys 38 wie in Config)
		T.eq(C.CarById.elys.level, 38, "C.Cars Elys unverändert")
		T.eq(C.CarById.komet.level, 1, "C.Cars Komet unverändert")
		for _, car in ipairs(C.Cars) do
			T.check(CC.ModelById[car.id].level >= car.level, "Händler später als Kundenauto " .. car.id)
		end
		-- Händlerkatalog (CarRules.SnapshotFields) übernimmt das neue Level
		local CR = g:MiniShared("CarRules")
		local d = g:Rules().NewData(NOW)
		d.level = 89
		local fields = CR.SnapshotFields(d)
		local elysUnlocked
		for _, e in ipairs(fields.catalog or {}) do
			if e.id == "elys" then
				elysUnlocked = e.unlocked
				T.eq(e.level, 90, "Katalog Elys 90")
			end
		end
		T.eq(elysUnlocked, false, "Elys auf Level 89 gesperrt")
		local ok = CR.Buy(d, "elys")
		T.eq(ok, false, "Kauf Elys auf 89 abgelehnt")
	end },

	{ "CrossBonus: PrestigeIncome, TycoonWorkshop nil-sicher, OWPerk neutral, Deckel ×1,6 nur auf Tycoon × OW, Prestige wirkt immer", function(T, H)
		local g = H.Garage({ noServer = true })
		local CB, PR, GC = g:MiniShared("CrossBonus"), g:MiniShared("PrestigeRules"), g:MiniShared("GameConfig")
		local d = g:Rules().NewData(NOW)
		g:MiniShared("MetaRules").ApplyDefault(d.games)
		T.eq(CB.PrestigeIncome(nil), 1, "ohne Profil neutral")
		T.eq(CB.PrestigeIncome({}), 1, "leeres Profil neutral")
		T.eq(CB.TycoonWorkshop(d), 1, "ohne games.tycoon neutral")
		T.eq(CB.TycoonWorkshop({ games = { tycoon = { runsDone = { werkstatt = 0 / 0 } } } }), 1, "NaN neutral")
		T.eq(CB.OWPerk(d, "werkstatt"), 1, "OW-Perk Platzhalter")
		T.eq(CB.WorkshopReward(d), 1, "Grundfaktor 1")
		d.level = 1
		T.eq(CB.PrestigeIncome(d), 1, "Rang 0")
		d.level = PR.Threshold(1)
		T.near(CB.PrestigeIncome(d), 1.02, 1e-9, "Rang 1: +2 %")
		d.level = PR.Threshold(5)
		T.near(CB.PrestigeIncome(d), 1.10, 1e-9, "Rang 5: +10 %")
		d.level = PR.Threshold(20)
		T.near(CB.PrestigeIncome(d), 1.30, 1e-9, "Rang 20: Deckel +30 %")
		T.eq(PR.IncomeBonus(d), CB.PrestigeIncome(d), "= PrestigeRules.IncomeBonus")
		d.games.tycoon = { runsDone = { werkstatt = 3 } }
		T.near(CB.TycoonWorkshop(d), 1.06, 1e-9, "3 Durchläufe +6 %")
		d.games.tycoon.runsDone.werkstatt = 12
		T.near(CB.TycoonWorkshop(d), 1.10, 1e-9, "Deckel 5 Durchläufe +10 %")
		T.near(CB.CareerBonus(d), 1.30 * 1.10, 1e-9, "Karriere-Faktor")
		-- Die 2.4.0/3.x-Querboni (Presse, Tuning-Abteilung, Kundenbonus) bleiben ungedeckelt: ein bestehendes Profil
		-- mit Tuning-Stufe 30 (×2,305) verliert durch die Ausbaustufe 4 nichts (Deckel ×1,6 nur auf Tycoon × OW-Perk)
		d.level = 1
		d.games.tycoon.runsDone.werkstatt = 5
		d.games.tuningLevel = 30
		d.games.parking.streak = 20
		d.games.press.upgrades = { pu1 = 20, pu2 = 20 }
		local legacy = CB.PressWorkshop(d) * CB.TuningWorkshop(d) * CB.CustomerBonus(d)
		T.check(legacy > 2.3, "3.x-Querboni über 2,3: " .. tostring(legacy))
		T.near(CB.CareerCapped(d), 1.10, 1e-9, "Tycoon-Faktor unter dem Deckel: ×1,10")
		T.near(CB.WorkshopReward(d), legacy * 1.10, 1e-9, "3.x-Boni ungedeckelt × Tycoon")
		T.eq(CB.WorkshopCap(), GC.WorkshopRewardCap or 1.6, "Deckel aus GameConfig (Standard 1,6)")
		-- Deckel greift nur auf Tycoon × OW-Perk (Platzhalter OW = 1 -> nie über 1,10; künstlich hoher Deckel-Test)
		local savedCap = GC.WorkshopRewardCap
		GC.WorkshopRewardCap = 1.05
		T.near(CB.CareerCapped(d), 1.05, 1e-9, "Tycoon × OW auf den Deckel gekappt")
		T.near(CB.WorkshopReward(d), legacy * 1.05, 1e-9, "Deckel wirkt nur auf den Ausbaustufe-4-Faktor")
		GC.WorkshopRewardCap = savedCap
		-- unter dem Deckel: alle Faktoren multiplizieren sich, Prestige außerhalb des Deckels
		d.games.press.upgrades = {}
		d.games.parking.streak = 0
		d.games.tuningLevel = 2
		d.level = PR.Threshold(1)
		T.near(CB.WorkshopReward(d), CB.PressWorkshop(d) * CB.TuningWorkshop(d) * CB.CustomerBonus(d) * 1.02 * 1.10, 1e-9, "Produkt unter dem Deckel")
		-- Prestige wirkt messbar, auch wenn Tycoon × OW den Deckel erreicht (Rang 1 = +2 %)
		GC.WorkshopRewardCap = 1.05
		d.level = 1
		local atCap = CB.WorkshopReward(d)
		d.level = PR.Threshold(1)
		T.near(CB.WorkshopReward(d), atCap * 1.02, 1e-9, "Rang 1: +2 % trotz Deckel")
		d.level = PR.Threshold(20)
		T.near(CB.WorkshopReward(d), atCap * 1.30, 1e-9, "Rang 20: +30 % trotz Deckel")
		GC.WorkshopRewardCap = savedCap
		-- 2.4.0-Vergütung (R.Reward) nutzt genau diesen Faktor; MiniRules.AddIncome den Prestige-Bonus
		local R = g:Rules()
		local C = g:Config()
		local MR = g:MiniShared("MiniRules")
		d.level = PR.Threshold(5)
		d.games.press.upgrades = {}
		d.games.parking.streak = 0
		d.games.tuningLevel = 1
		local job = { kind = C.Jobs[1].id, carId = C.Cars[1].id, quality = 100, usedParts = {} }
		local def, car = C.JobById[job.kind], C.CarById[job.carId]
		T.eq(R.Reward(d, job), math.floor(def.reward * car.reward * 1.10 * 1.10 * (1 + 100 * 0.0025) + 0.5), "R.Reward: Tycoon ×1,10 × Prestige ×1,10")
		d.money = 0
		T.eq(MR.AddIncome(d, 1000), 1100, "AddIncome: Rang 5 = +10 % auf Minispiel-Einnahmen")
		T.eq(d.money, 1100, "gutgeschrieben")
		d.level = 1
		T.eq(MR.AddIncome(d, 1000), 1000, "AddIncome ohne Rang: unverändert")
		T.eq(MR.AddIncome(d, -500), -500, "AddIncome mit negativem Betrag = AddMoney (kein Bonus)")
	end },

	{ "PrestigeService: Abholen nur einmal, nur erreichte Ränge, in Reihenfolge; Statistik", function(T, H)
		local S = setup(H)
		local g, PS, PR = S.g, S.PS, S.g:MiniShared("PrestigeRules")
		local pl, ms, d = S.join(601, "Pia")
		local money = d.money
		S.act(pl, "prestige_claim", { rank = 1 })
		T.eq(d.games.prestige.claimed[1], nil, "Rang 1 auf Level 1 nicht abholbar")
		T.check(S.hasToast(pl, "Rang 1 gibt es ab Level 100"), "Hinweis mit Schwelle")
		T.eq(#S.notices(pl, "prestige"), 0, "kein Hinweis")
		levelTo(g, d, PR.Threshold(2))
		T.check(d.level >= 250, "Level 250 erreicht: " .. tostring(d.level))
		S.clear()
		S.act(pl, "prestige_claim", { rank = 2 })
		T.eq(d.games.prestige.claimed[2], nil, "Rang 2 nicht vor Rang 1")
		T.check(S.hasToast(pl, "Hol zuerst Rang 1 ab"), "Reihenfolge-Hinweis")
		S.act(pl, "prestige_claim", { rank = 1 })
		T.eq(d.games.prestige.claimed[1], true, "Rang 1 abgeholt")
		T.eq(d.games.prestige.titleRank, 1, "Titel Rang 1")
		T.eq(d.games.stats.prestigeClaims, 1, "Statistik prestigeClaims")
		local n = S.notices(pl, "prestige")
		T.eq(#n, 1, "ein prestige-Hinweis")
		T.eq(n[1] and n[1].claimed, true, "claimed = true")
		T.eq(n[1] and n[1].rank, 1, "Rang im Hinweis")
		T.eq(n[1] and n[1].title, "Meisterschrauber I", "Titel im Hinweis")
		T.eq(n[1] and n[1].cosmetic, "wrap_prestige_1", "Kosmetik-Id im Hinweis")
		T.eq(n[1] and n[1].cosmeticGranted, false, "ohne games.shop noch nicht eingetragen")
		T.check(S.hasToast(pl, "Rang 1 abgeholt"), "Toast")
		S.clear()
		S.act(pl, "prestige_claim", { rank = 1 })
		S.act(pl, "prestige_claim", { rank = 1 })
		T.eq(d.games.stats.prestigeClaims, 1, "nur einmal (Doppelklick still)")
		T.eq(#S.notices(pl, "prestige"), 0, "kein zweiter Hinweis")
		T.eq(#S.log.toasts, 0, "Doppelklick ohne Toast")
		S.act(pl, "prestige_claim", { rank = 2 })
		T.eq(d.games.prestige.claimed[2], true, "Rang 2 danach abholbar")
		T.eq(d.games.stats.prestigeClaims, 2, "zwei Abholungen")
		S.act(pl, "prestige_claim", { rank = 3 })
		T.eq(d.games.prestige.claimed[3], nil, "Rang 3 (Level 500) noch nicht")
		S.act(pl, "prestige_claim", { rank = 0 })
		S.act(pl, "prestige_claim", { rank = 99 })
		S.act(pl, "prestige_claim", { rank = 1.5 })
		T.eq(d.games.stats.prestigeClaims, 2, "ungültige Ränge ohne Wirkung")
		T.eq(#PR.Claimable(d), 0, "nichts mehr offen")
		T.eq(d.money >= money, true, "kein Geld verloren")
		-- Kosmetik landet in shop.owned, sobald es die Tabelle gibt (Meilenstein 8)
		levelTo(g, d, PR.Threshold(3))
		d.games.shop = { owned = {} }
		S.clear()
		S.act(pl, "prestige_claim", { rank = 3 })
		T.eq(d.games.shop.owned.wrap_prestige_3, true, "Kosmetik eingetragen")
		T.eq(S.notices(pl, "prestige")[1].cosmeticGranted, true, "cosmeticGranted")
		-- Daten sind dicht und speicherbar (Vorgabe PrestigeRules)
		T.eq(#d.games.prestige.claimed, 3, "claimed dicht 1..3")
		local MR = g:MiniShared("MiniRules")
		T.check(MR.IsClean(d.games.prestige, 0) ~= false, "prestige speicherbar")
	end },

	{ "PrestigeService.Tick: Hinweise beim Level-Aufstieg (unlock je Freischaltung, prestige je neuem Rang), Beginner-Hinweis", function(T, H)
		local S = setup(H)
		local g, PS, U, PR, GC = S.g, S.PS, S.g:MiniShared("Unlocks"), S.g:MiniShared("PrestigeRules"), S.g:MiniShared("GameConfig")
		local pl, ms, d = S.join(602, "Tom")
		T.eq(S.tick(pl), false, "ohne Änderung nichts")
		T.eq(#S.notices(pl, "unlock"), 0, "keine Hinweise beim Beitritt")
		-- Level 1 -> 3 über den Server-Weg (MiniRules.GainXP): feature:press (2), feature:scrapyard, feature:dealer, car:komet (3)
		local MR = g:MiniShared("MiniRules")
		local R = g:Rules()
		while d.level < 3 do
			MR.GainXP(d, R.XPNeeded(d))
		end
		T.eq(d.level, 3, "Level 3")
		T.eq(S.tick(pl), true, "Aufstieg erkannt")
		local n = S.notices(pl, "unlock")
		local expect = U.NewlyReached(1, 3)
		T.eq(#n, #expect, "ein Hinweis je erreichter Freischaltung (" .. #expect .. ")")
		for i, u in ipairs(expect) do
			T.eq(n[i] and n[i].key, u.key, "Reihenfolge " .. u.key)
			T.eq(n[i] and n[i].title, u.title, "Titel " .. u.key)
			T.eq(n[i] and n[i].level, u.level, "Level " .. u.key)
			T.check(sendable(n[i]), "sendbar " .. u.key)
		end
		-- Beginner-Hinweis reist im unlock-Hinweis mit und gilt danach als gesehen
		local pressNotice
		for _, x in ipairs(n) do
			if x.key == "feature:press" then
				pressNotice = x
			end
		end
		T.eq(pressNotice and pressNotice.hint, GC.HintById.h_press.text, "Hinweistext h_press")
		T.eq(d.games.meta.hintsSeen.h_press, true, "Hinweis als gesehen markiert")
		T.eq(#S.notices(pl, "prestige"), 0, "kein Rang-Hinweis unter Level 100")
		T.eq(S.tick(pl), false, "zweiter Tick still")
		T.eq(#S.notices(pl, "unlock"), #expect, "keine Wiederholung")
		-- Sprung bis Rang 1 (Level 100): alle Freischaltungen 4..100 und ein prestige-Hinweis (reached)
		S.clear()
		levelTo(g, d, PR.Threshold(1))
		T.eq(S.tick(pl), true, "Aufstieg erkannt")
		local n2 = S.notices(pl, "unlock")
		T.eq(#n2, #U.NewlyReached(3, d.level), "alle dazwischen erreichten Freischaltungen")
		local p2 = S.notices(pl, "prestige")
		T.eq(#p2, 1, "ein Rang-Hinweis")
		T.eq(p2[1] and p2[1].reached, true, "reached = true")
		T.eq(p2[1] and p2[1].rank, 1, "Rang 1")
		T.eq(p2[1] and p2[1].title, "Meisterschrauber I", "Titel")
		T.eq(p2[1] and p2[1].claimable[1], 1, "claimable [1]")
		T.check(S.hasToast(pl, "Neuer Prestige-Rang 1"), "Toast zum neuen Rang")
		-- Beginner aus: kein Hinweistext mehr, unlock-Hinweise weiterhin
		S.clear()
		d.games.meta.beginner = false
		d.level = 0 / 0 -- NaN: LevelOf = 1, Tick darf nicht abstürzen und meldet den (Rück-)Wechsel ohne Hinweise
		T.check(pcall(S.tick, pl), "NaN-Level ohne Fehler")
		T.eq(#S.notices(pl, "unlock"), 0, "keine Hinweise bei Rückgang")
		d.level = 12
		S.tick(pl)
		local n3 = S.notices(pl, "unlock")
		T.eq(#n3, #U.NewlyReached(1, 12), "nach Rückgang: Aufstieg ab dem gemerkten Level")
		for _, x in ipairs(n3) do
			T.eq(x.hint, nil, "ohne Beginner kein Hinweistext " .. x.key)
		end
		-- Hinweise warten, bis der Client zuhört (ms.greeted)
		S.clear()
		ms.greeted = false
		d.level = 20
		S.tick(pl)
		T.eq(#S.notices(pl, "unlock"), 0, "vor hello zurückgehalten")
		ms.greeted = true
		PS.Flush(ms)
		T.eq(#S.notices(pl, "unlock"), #U.NewlyReached(12, 20), "nach hello nachgeliefert")
		PS.Flush(ms)
		T.eq(#S.notices(pl, "unlock"), #U.NewlyReached(12, 20), "nicht doppelt")
	end },

	{ "PrestigeService.SnapshotFields: prestige/unlocks, list nur bei full, unlocks_seen", function(T, H)
		local S = setup(H)
		local g, PS, U, PR, GC = S.g, S.PS, S.g:MiniShared("Unlocks"), S.g:MiniShared("PrestigeRules"), S.g:MiniShared("GameConfig")
		local pl, ms, d = S.join(603, "Uta")
		local f = PS.SnapshotFields(ms, d, g:Now(), true)
		T.check(sendable(f), "sendbar")
		T.eq(f.prestige.rank, 0, "Rang 0")
		T.eq(f.prestige.next, 100, "nächste Schwelle 100")
		T.eq(f.prestige.title, "", "kein Titel")
		T.eq(#f.prestige.claimable, 0, "nichts abholbar")
		T.eq(#f.prestige.claimed, 0, "nichts abgeholt")
		T.eq(f.prestige.maxRank, 20, "MaxRank")
		T.near(f.prestige.incomeBonus, 1, 1e-9, "Bonus 1")
		T.eq(f.unlocks.level, 1, "Level")
		T.eq(f.unlocks.next.key, "feature:press", "nächste Freischaltung press")
		T.eq(f.unlocks.next.level, 2, "Level 2")
		T.eq(#f.unlocks.list, #GC.Unlocks, "volle Liste")
		T.eq(f.unlocks.total, #GC.Unlocks, "total")
		T.eq(f.unlocks.unseen, 0, "nichts neu")
		local fp = PS.SnapshotFields(ms, d, g:Now(), false)
		T.eq(fp.unlocks.list, nil, "ohne full keine Liste")
		T.eq(fp.unlocks.next.key, "feature:press", "next bleibt")
		T.eq(PS.SnapshotFields(ms, d, g:Now()).unlocks.list ~= nil, true, "full = nil gilt als voll")
		-- Level 250: Rang 2, zwei abholbar; nach Abholen von 1: claimed {1}, claimable {2}
		levelTo(g, d, PR.Threshold(2))
		S.tick(pl)
		f = PS.SnapshotFields(ms, d, g:Now(), true)
		T.eq(f.prestige.rank, 2, "Rang 2")
		T.eq(f.prestige.next, 500, "nächste Schwelle 500")
		T.eq(f.prestige.claimable[1], 1, "abholbar 1")
		T.eq(f.prestige.claimable[2], 2, "abholbar 2")
		T.eq(f.prestige.nextClaim, 1, "nextClaim 1")
		T.check(f.unlocks.unseen > 0, "neue Freischaltungen seit dem Beitritt")
		T.eq(f.unlocks.unseen, #U.NewlyReached(1, d.level), "Anzahl neu")
		S.act(pl, "unlocks_seen", {})
		f = PS.SnapshotFields(ms, d, g:Now(), true)
		T.eq(f.unlocks.unseen, 0, "nach unlocks_seen nichts neu")
		S.act(pl, "prestige_claim", { rank = 1 })
		f = PS.SnapshotFields(ms, d, g:Now(), true)
		T.eq(#f.prestige.claimed, 1, "claimed 1")
		T.eq(f.prestige.claimed[1], 1, "claimed[1] = 1")
		T.eq(f.prestige.claimable[1], 2, "claimable 2")
		T.eq(f.prestige.title, "Meisterschrauber I", "Titel")
		T.eq(f.prestige.titleRank, 1, "titleRank")
		T.near(f.prestige.incomeBonus, 1.04, 1e-9, "Bonus Rang 2")
		T.near(f.prestige.discount, 0.02, 1e-9, "Rabatt Rang 2")
		local reached = 0
		for _, e in ipairs(f.unlocks.list) do
			if e.reached then
				reached += 1
			end
		end
		T.eq(reached, #GC.Unlocks, "auf Level 250 alles erreicht")
		T.eq(f.unlocks.next, false, "keine nächste Freischaltung")
		-- ohne ms (z. B. Tests, Bestenliste) nil-sicher
		T.check(pcall(PS.SnapshotFields, nil, d, g:Now(), true), "ohne ms")
		-- keine Betragsfelder aus Client-Sicht relevant, aber keine Funktionen/Instanzen
		T.check(not hasKey(f, "claimedSet"), "keine internen Felder")
	end },

	{ "Speichern/Laden: abgeholte Ränge überleben Rejoin, Rang folgt dem Level, zwei Spieler getrennt", function(T, H)
		local S = setup(H)
		local g, PR = S.g, S.g:MiniShared("PrestigeRules")
		local pl, ms, d = S.join(604, "Vera")
		local p2, ms2, d2 = S.join(605, "Willi")
		levelTo(g, d, PR.Threshold(2))
		S.tick(pl)
		S.act(pl, "prestige_claim", { rank = 1 })
		S.act(pl, "prestige_claim", { rank = 2 })
		T.eq(#d.games.prestige.claimed, 2, "zwei abgeholt")
		T.eq(#S.notices(p2, "prestige"), 0, "zweiter Spieler ohne Hinweise")
		T.eq(#(d2.games.prestige.claimed), 0, "zweiter Spieler ohne Abholung")
		S.act(p2, "prestige_claim", { rank = 1 })
		T.eq(d2.games.prestige.claimed[1], nil, "zweiter Spieler Level 1: nichts")
		g:Leave(pl)
		g:Advance(1)
		local rec = g:Record(604)
		T.check(rec ~= nil and rec.data ~= nil, "Datensatz gespeichert")
		local savedPrestige = rec and rec.data.games and rec.data.games.prestige
		if savedPrestige then
			T.eq(savedPrestige.claimed[1], true, "claimed[1] im Datensatz")
			T.eq(savedPrestige.claimed[2], true, "claimed[2] im Datensatz")
		else
			-- MiniRules.LoadGames kennt prestige erst nach der Verkabelung (Integrator, Schritt 1)
			T.check(true, "prestige noch nicht in LoadGames verkabelt")
		end
		local pl3, ms3, d3 = S.join(604, "Vera")
		T.eq(d3.level, d.level, "Level bleibt (kein Reset)")
		if savedPrestige and d3.games.prestige and #d3.games.prestige.claimed == 2 then
			T.eq(PR.Title(d3), "Meisterschrauber II", "Titel nach Rejoin")
			S.act(pl3, "prestige_claim", { rank = 1 })
			T.eq(d3.games.stats.prestigeClaims, (rec.data.games.stats and rec.data.games.stats.prestigeClaims) or d3.games.stats.prestigeClaims, "nicht erneut")
		end
		T.eq(PR.Rank(d3), 2, "Rang aus dem Level")
	end },

	{ "Echter Weg über Remotes.Command (sobald MiniNet prestige_claim/unlocks_seen kennt)", function(T, H)
		local g = H.Garage()
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.Actions.prestige_claim or not MiniNet.Actions.unlocks_seen then
			T.check(true, "MiniNet kennt die Aktionen noch nicht (Integrator, Schritt 4)")
			return
		end
		local PR = g:MiniShared("PrestigeRules")
		local pl = g:Join(606, { name = "Xenia" })
		g:Advance(1)
		g:Send(pl, "hello") -- Hinweise warten bis zum ersten 'hello' (ms.greeted)
		local d = g:D(pl)
		ensureMeta(g, d)
		T.eq(g:Act(pl, "prestige_claim", { rank = "1" }), "invalid", "rank muss number sein")
		T.eq(g:Act(pl, "prestige_claim", { rank = 1, rid = 1 }), "ok", "Aktion angenommen")
		T.eq(d.games.prestige.claimed[1], nil, "auf Level 1 nichts")
		levelTo(g, d, PR.Threshold(1))
		local m = g:Mark()
		g:Advance(1.2) -- Tick erkennt den Aufstieg
		T.check(#g:Notices(pl, "unlock", m) > 0, "unlock-Hinweise über den echten Weg")
		T.eq(#g:Notices(pl, "prestige", m), 1, "prestige-Hinweis (reached)")
		g:Advance(0.5)
		T.eq(g:Act(pl, "prestige_claim", { rank = 1, rid = 2 }), "ok", "Abholen")
		T.eq(d.games.prestige.claimed[1], true, "abgeholt")
		g:Advance(0.5)
		T.eq(g:Act(pl, "prestige_claim", { rank = 1, rid = 3 }), "ok", "Doppelklick angenommen, aber wirkungslos")
		T.eq(d.games.stats.prestigeClaims, 1, "nur einmal")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and type(snap.prestige) == "table" and snap.prestige.rank == 1, "Snapshot prestige.rank")
		T.check(snap and type(snap.unlocks) == "table", "Snapshot unlocks")
		T.eq(g:Act(pl, "unlocks_seen", { rid = 4 }), "ok", "unlocks_seen")
	end },

	{ "PrestigeUI: Rang, Schwelle, Balken, Belohnungsliste mit „Abholen“ (nur der nächste Rang), Abzeichen ProgressHUD", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI, _, state = build(g, p, "PrestigeUI", rec)
		local PR = g:MiniShared("PrestigeRules")
		-- Abzeichen: eigene ScreenGui, oben rechts, 16 px Rand, unter dem 2.4.0-UI (DisplayOrder < 20)
		local hudGui = p.PlayerGui:FindFirstChild("ProgressHUD")
		T.check(hudGui ~= nil and hudGui.ClassName == "ScreenGui", "ScreenGui ProgressHUD")
		local badge = hudGui and hudGui:FindFirstChild("Badge")
		T.check(badge ~= nil, "Badge")
		if badge then
			T.eq(badge.AnchorPoint.X, 1, "rechts verankert")
			T.eq(badge.Position.X.Offset, -16, "16 px Rand")
			T.eq(badge.Position.X.Scale, 1, "am rechten Rand")
		end
		T.check(hudGui and hudGui.DisplayOrder < 20, "unter dem 2.4.0-UI")
		T.eq(mod.HudVisible(), true, "vor dem ersten Snapshot: Gui an, aber ohne Inhalt")
		g:InClient(p, function()
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), false, "ohne Snapshot ausgeblendet")

		local s = snapshot(g, 12, { full = true })
		render(g, p, mod, s)
		g:InClient(p, function()
			mod.Step(1)
		end)
		T.eq(mod.HudVisible(), true, "mit Snapshot sichtbar")
		local line1, line2 = byName(hudGui, "RankLevel"), byName(hudGui, "NextUnlock")
		T.eq(line1 and line1.Text, "Rang 0 · Level 12", "Abzeichen Rang/Level")
		T.check(line2 and line2.Text:find("Nächste Freischaltung: Nord R4 (Lv 14)", 1, true), "Abzeichen nächste Freischaltung: " .. tostring(line2 and line2.Text))
		-- Tab-Inhalt
		local rankText = byName(page, "RankText")
		T.eq(rankText and rankText.Text, "Rang 0 von 20", "Rang-Zeile")
		local nextText = byName(page, "NextText")
		T.check(nextText and nextText.Text:find("ab Level 100", 1, true), "nächste Schwelle")
		local claim1 = byName(page, "Claim_1")
		T.check(claim1 ~= nil and not enabled(claim1), "Rang 1 nicht abholbar")
		T.check(claim1 and claim1.Text:find("Ab Level 100", 1, true), "Knopftext Schwelle")
		press(g, claim1)
		T.eq(rec.Count("prestige_claim"), 0, "gesperrter Knopf sendet nichts")

		-- Level 250: Rang 2, Rang 1 abholbar, Rang 2 wartet auf Rang 1
		s = snapshot(g, PR.Threshold(2), { full = true })
		render(g, p, mod, s)
		T.eq(line1 and line1.Text, "Rang 2 · Level 250 · Belohnung bereit!", "Abzeichen mit Belohnung")
		T.eq(rankText and rankText.Text, "Rang 2 von 20", "Rang 2")
		claim1 = byName(page, "Claim_1")
		local claim2 = byName(page, "Claim_2")
		T.check(enabled(claim1), "Rang 1 abholbar")
		T.check(claim2 ~= nil and not enabled(claim2), "Rang 2 erst nach Rang 1")
		T.check(press(g, claim1), "Klick Abholen")
		T.eq(rec.Count("prestige_claim"), 1, "prestige_claim gesendet")
		T.eq(rec.Last("prestige_claim").rank, 1, "rank = 1")
		press(g, claim2)
		T.eq(rec.Count("prestige_claim"), 1, "Rang 2 nicht gesendet")

		-- nach Abholen: Rang 1 „Abgeholt“, Rang 2 abholbar; Titel
		s = snapshot(g, PR.Threshold(2), { full = true, claimed = { 1 } })
		render(g, p, mod, s)
		claim1, claim2 = byName(page, "Claim_1"), byName(page, "Claim_2")
		T.check(claim1 and not enabled(claim1) and claim1.Text:find("Abgeholt", 1, true), "Rang 1 abgeholt")
		T.check(enabled(claim2), "Rang 2 abholbar")
		local titleText = byName(page, "TitleText")
		T.check(titleText and titleText.Text:find("Meisterschrauber I", 1, true), "Titel angezeigt")
		press(g, claim2)
		T.eq(rec.Last("prestige_claim").rank, 2, "rank = 2")
		-- Reihenfolge der Belohnungsliste = Ränge 1..20
		for i = 1, 20 do
			T.check(byName(page, "Claim_" .. i) ~= nil, "Zeile Rang " .. i)
		end

		-- Sichtbarkeit: Panel offen, Tablet offen, QTE, Tacho -> Abzeichen weg
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
		local fahren = p.PlayerGui:FindFirstChild("Fahren")
		if fahren then
			g:InClient(p, function()
				fahren.Enabled = true
				mod.Step(1)
			end)
			T.eq(mod.HudVisible(), false, "bei sichtbarem Tacho weg")
			g:InClient(p, function()
				fahren.Enabled = false
				mod.Step(1)
			end)
		else
			g:InClient(p, function()
				local fake = Instance.new("ScreenGui")
				fake.Name = "Fahren"
				fake.Enabled = true
				fake.Parent = p.PlayerGui
				mod.Step(1)
			end)
			T.eq(mod.HudVisible(), false, "bei sichtbarem Tacho (Ersatz) weg")
			g:InClient(p, function()
				p.PlayerGui.Fahren.Enabled = false
				mod.Step(1)
			end)
		end
		T.eq(mod.HudVisible(), true, "nach der Fahrt wieder da")
		-- Hinweis vom Server: nur Effekt, kein Fehler
		T.check(pcall(function()
			g:InClient(p, function()
				mod.OnNotice({ kind = "prestige", reached = true, rank = 1, title = "Meisterschrauber I" })
				mod.OnNotice({ kind = "prestige", claimed = true, rank = 1 })
				mod.OnNotice({ kind = "unlock" })
			end)
		end), "OnNotice ohne Fehler")
		T.check(#g:Errors() == 0, "keine Client-Fehler: " .. g:ErrorText())
	end },

	{ "Karten oben rechts: unter dem Abzeichen (auch bei y 60 auf schmalen Bildschirmen) und unter der Toast-Zone; Warteschlange statt Überschreiben; Prozentwerte ganzzahlig", function(T, H)
		local GC0 = nil
		for _, vp in ipairs({ Vector2.new(390, 844), Vector2.new(844, 390), Vector2.new(1280, 720) }) do
			local g, p = startClient(H, { viewport = vp })
			local rec = recorder(T)
			local prestige, _, MiniUI = build(g, p, "PrestigeUI", rec)
			local unlocks = build(g, p, "UnlocksUI", rec)
			local tutorial = build(g, p, "TutorialUI", rec)
			local GC = g:MiniShared("GameConfig")
			GC0 = GC
			local label = string.format("%dx%d", vp.X, vp.Y)
			render(g, p, prestige, snapshot(g, 12, { full = true }))
			g:InClient(p, function()
				prestige.Step(1)
			end)
			local hudGui = p.PlayerGui:FindFirstChild("ProgressHUD")
			local badge = hudGui and byName(hudGui, "Badge")
			T.check(badge ~= nil and hudGui.Enabled, label .. ": Abzeichen sichtbar")
			local narrow = vp.X < prestige.CompactProgressWidth + 2 * (prestige.HudWidth + prestige.HudMargin + 8)
			T.eq(badge and badge.Position.Y.Offset, narrow and prestige.HudTopNarrow or prestige.HudTop, label .. ": Abzeichen-Lage (schmal: y 60)")
			local badgeBottom = badge.AbsolutePosition.Y + badge.AbsoluteSize.Y
			local toastBottom = hudGui.AbsolutePosition.Y + 62 + 60
			-- Unlock-Karte
			g:InClient(p, function()
				unlocks.OnNotice({ kind = "unlock", key = "feature:scrapyard", title = "Schrottplatz", level = 3, hint = "Neu: der Schrottplatz!" })
				unlocks.OnNotice({ kind = "unlock", key = "feature:dealer", title = "Autohaus", level = 3 })
				unlocks.OnNotice({ kind = "unlock", key = "car:komet", title = "Komet C1", level = 3 })
			end)
			local cardGui = p.PlayerGui:FindFirstChild("UnlockCards")
			local card = cardGui and byName(cardGui, "UnlockCard")
			T.check(card ~= nil and card.Visible, label .. ": Unlock-Karte sichtbar")
			T.check(card.AbsolutePosition.Y >= badgeBottom + 8, label .. ": Unlock-Karte unter dem Abzeichen (" .. tostring(card.AbsolutePosition.Y) .. " vs " .. tostring(badgeBottom) .. ")")
			T.check(card.AbsolutePosition.Y >= toastBottom + 8, label .. ": Unlock-Karte unter der Toast-Zone")
			T.check(card.AbsolutePosition.X + card.AbsoluteSize.X <= vp.X and card.AbsoluteSize.X > 0, label .. ": Karte im Bild")
			-- Warteschlange: erst Schrottplatz, dann Autohaus, dann Komet – nichts geht verloren
			local title = byName(cardGui, "Title")
			T.check(title and title.Text:find("Schrottplatz", 1, true), label .. ": erste Karte Schrottplatz: " .. tostring(title and title.Text))
			T.eq(unlocks.QueuedCards(), 2, label .. ": zwei Karten warten")
			g:Advance(unlocks.CardSeconds + 0.3)
			T.check(title and title.Text:find("Autohaus", 1, true), label .. ": zweite Karte Autohaus")
			g:Advance(unlocks.CardSeconds + 0.3)
			T.check(title and title.Text:find("Komet C1", 1, true), label .. ": dritte Karte Komet C1")
			T.check(card.Visible, label .. ": dritte Karte sichtbar")
			g:Advance(unlocks.CardSeconds + 0.3)
			T.eq(card.Visible, false, label .. ": Warteschlange leer, Karte weg")
			-- Hinweiskarte (TutorialUI): ebenfalls unter Abzeichen und Toast; Warteschlange
			g:InClient(p, function()
				tutorial.ShowHint("Neu: der Schrottplatz!", "h_scrapyard")
				tutorial.ShowHint("Neu: das Autohaus!", "h_dealer")
			end)
			local tGui = p.PlayerGui:FindFirstChild("Tutorial")
			local hintCard = tGui and byName(tGui, "HintCard")
			T.check(hintCard ~= nil and hintCard.Visible, label .. ": Hinweiskarte sichtbar")
			T.check(hintCard.AbsolutePosition.Y >= badgeBottom + 8, label .. ": Hinweiskarte unter dem Abzeichen")
			T.check(hintCard.AbsolutePosition.Y >= toastBottom + 8, label .. ": Hinweiskarte unter der Toast-Zone")
			local hintText = byName(hintCard, "Text")
			T.check(hintText and hintText.Text:find("Schrottplatz", 1, true), label .. ": erster Hinweis zuerst")
			T.eq(tutorial.QueuedHints(), 1, label .. ": zweiter Hinweis wartet")
			g:Advance(tutorial.HintSeconds + 0.3)
			T.check(hintText and hintText.Text:find("Autohaus", 1, true) and hintCard.Visible, label .. ": zweiter Hinweis danach")
			-- Größenwechsel: Karte folgt dem Abzeichen
			local other = vp.X < 818 and Vector2.new(1280, 720) or Vector2.new(390, 844)
			H.Mock.SetViewport(g.env, other)
			g:InClient(p, function()
				hudGui:GetPropertyChangedSignal("AbsoluteSize"):Fire()
				cardGui:GetPropertyChangedSignal("AbsoluteSize"):Fire()
				tGui:GetPropertyChangedSignal("AbsoluteSize"):Fire()
				unlocks.OnNotice({ kind = "unlock", key = "feature:quiz", title = "Quiz", level = 4 })
			end)
			local badgeBottom2 = badge.AbsolutePosition.Y + badge.AbsoluteSize.Y
			T.check(card.AbsolutePosition.Y >= badgeBottom2 + 8, label .. " -> " .. tostring(other.X) .. ": Karte nach Größenwechsel unter dem Abzeichen")
			T.check(hintCard.AbsolutePosition.Y >= badgeBottom2 + 8, label .. " -> " .. tostring(other.X) .. ": Hinweis nach Größenwechsel unter dem Abzeichen")
			T.check(#g:Errors() == 0, label .. ": keine Client-Fehler: " .. g:ErrorText())
		end
		-- Belohnungstexte ohne Gleitkomma-Müll (Rang 7: 14 %, nicht 14.000000000000002 %)
		local g = H.Garage({ noServer = true })
		local GC = g:MiniShared("GameConfig")
		for _, r in ipairs(GC.Prestige.Rewards) do
			T.check(r.incomePct == math.floor(r.incomePct) and r.discountPct == math.floor(r.discountPct), "Rang " .. r.rank .. ": ganzzahlige Prozentwerte")
		end
		T.eq(GC.Prestige.Rewards[7].incomePct, 14, "Rang 7: 14 %")
		T.eq(GC.Prestige.Rewards[14].incomePct, 28, "Rang 14: 28 %")
		T.eq(GC.Prestige.Rewards[7].discountPct, 7, "Rang 7: 7 % Rabatt")
		local g2, p2 = startClient(H)
		local PUI = g2:ClientModule(p2, "Mini.PrestigeUI")
		T.check(type(PUI.RewardText) == "function", "PrestigeUI.RewardText")
		for _, r in ipairs(GC.Prestige.Rewards) do
			local text = PUI.RewardText(r)
			T.check(not text:find("0000", 1, true), "Rang " .. r.rank .. ": Text ohne Gleitkomma-Müll: " .. text)
		end
		T.check(PUI.RewardText({ incomePct = 14.000000000000002, discountPct = 7.000000000000001, tycoonRebirthPct = 5 }):find("+14 % Einnahmen · 7 % Rabatt", 1, true) ~= nil, "RewardText rundet")
	end },

	{ "UnlocksUI: nächste Freischaltung oben, Tabelle Level -> Freischaltung mit Hervorhebung, Karte bei unlock-Hinweis, unlocks_seen", function(T, H)
		local g, p = startClient(H)
		local rec = recorder(T)
		local mod, page, MiniUI = build(g, p, "UnlocksUI", rec)
		local GC, U = g:MiniShared("GameConfig"), g:MiniShared("Unlocks")
		local s = snapshot(g, 7, { full = true })
		s.unlocks.unseen = 2
		render(g, p, mod, s)
		local nextTitle = byName(page, "NextTitle")
		T.check(nextTitle and nextTitle.Text:find("Teststrecke", 1, true) and nextTitle.Text:find("Level 8", 1, true), "nächste Freischaltung: " .. tostring(nextTitle and nextTitle.Text))
		local rows = {}
		for i = 1, #GC.Unlocks do
			rows[i] = byName(page, "Unlock_" .. i)
			T.check(rows[i] ~= nil, "Zeile " .. i)
		end
		local T_ = MiniUI.Theme
		for i, e in ipairs(GC.Unlocks) do
			local r = rows[i]
			if r then
				local lvl = byName(r, "Level")
				local title = byName(r, "Title")
				T.eq(lvl and lvl.Text, "Lv " .. e.level, "Level-Spalte " .. i)
				T.check(title and title.Text:find(e.title, 1, true), "Titel " .. i)
				local reached = e.level <= 7
				T.eq(lvl and lvl.TextColor3 == T_.green, reached, "Hervorhebung " .. e.key)
				T.eq(title and title.Text:find("✓", 1, true) ~= nil, reached, "Haken " .. e.key)
			end
		end
		-- Tab geöffnet mit neuen Einträgen -> unlocks_seen genau einmal je Level-Stand
		g:InClient(p, function()
			mod.OnShow()
			mod.Render(s)
			mod.OnShow()
			mod.Render(s)
		end)
		T.eq(rec.Count("unlocks_seen"), 1, "unlocks_seen einmal")
		s.unlocks.unseen = 0
		g:InClient(p, function()
			mod.OnShow()
			mod.Render(s)
		end)
		T.eq(rec.Count("unlocks_seen"), 1, "ohne neue Einträge nicht erneut")
		-- Produktions-Snapshot ohne Liste: Tabelle bleibt (Client rechnet aus GameConfig nach)
		local s2 = snapshot(g, 90, { full = false })
		T.eq(s2.unlocks.list, nil, "Testsnapshot ohne Liste")
		render(g, p, mod, s2)
		local lvl1 = byName(rows[#GC.Unlocks - 1], "Level") -- Elys (90) erreicht, Prototyp (95) offen
		T.eq(lvl1 and lvl1.TextColor3 == T_.green, true, "Elys erreicht (Liste aus GameConfig)")
		local lvlLast = byName(rows[#GC.Unlocks], "Level")
		T.eq(lvlLast and lvlLast.TextColor3 == T_.green, false, "Prototyp offen")
		nextTitle = byName(page, "NextTitle")
		T.check(nextTitle and nextTitle.Text:find("Prototyp", 1, true), "nächste: Prototyp")
		local s3 = snapshot(g, 95, { full = true })
		render(g, p, mod, s3)
		T.check(nextTitle and nextTitle.Text:find("Alles freigeschaltet", 1, true), "alles erreicht")
		-- Karte bei mini_notice unlock
		local cardGui = p.PlayerGui:FindFirstChild("UnlockCards")
		T.check(cardGui ~= nil, "ScreenGui UnlockCards")
		T.eq(mod.CardVisible(), false, "Karte anfangs weg")
		g:InClient(p, function()
			mod.OnNotice({ kind = "unlock", key = "feature:press", title = "Schrottpresse", level = 2, hint = "Neu: die Schrottpresse!" })
		end)
		T.eq(mod.CardVisible(), true, "Karte sichtbar")
		local ct = cardGui and byName(cardGui, "Title")
		T.check(ct and ct.Text:find("Neu freigeschaltet: Schrottpresse", 1, true), "Kartentitel")
		local ctx_ = cardGui and byName(cardGui, "Text")
		T.eq(ctx_ and ctx_.Text, "Neu: die Schrottpresse!", "Hinweistext auf der Karte")
		g:Advance(mod.CardSeconds + 0.5)
		T.eq(mod.CardVisible(), false, "Karte verschwindet")
		g:InClient(p, function()
			mod.OnNotice({ kind = "unlock", key = "car:komet", title = "Komet C1", level = 3 })
		end)
		T.eq(ctx_ and ctx_.Text, "Ab jetzt verfügbar (Level 3).", "ohne Hinweis Standardtext")
		T.check(#g:Errors() == 0, "keine Client-Fehler: " .. g:ErrorText())
	end },
}
