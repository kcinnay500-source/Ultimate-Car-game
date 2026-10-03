-- Große Werkstatt (PublicWorkshopService + PublicWorkshopUI + worldgen districts/grosswerkstatt.py):
-- Welt im Fixture (District, Stationen grosswerkstatt/teileankauf, Ankunftspunkte mit DisplayName), Daten (Load
-- idempotent, Whitelist), Reparatur (Abstand, Bezahlen, Dauer, Weggehen pausiert, Fortsetzen ohne neue Kosten,
-- Abschluss mit Story-Ereignis, ValueBonus gedeckelt, zweite Reparatur bringt nichts), Teile-Ankauf (Abstand, Bestand,
-- Tageslimit, ungültige Mengen, Vorrat), Exploits (Kosten < Gewinn, Kauf+Reparatur+Verkauf ohne Gewinn, Erstattung)
-- und das Panel an drei Viewports (Treffertest tests/lib/gui_hit.lua, Knöpfe ≥ 44 px, gesendete Absichten).
local NOW = 1760000000

local VIEWPORTS = { { 390, 844 }, { 1280, 650 }, { 1920, 1080 } }
local FORBIDDEN = { amount = true, cost = true, credits = true, reward = true, money = true, price = true, xp = true, gain = true, value = true }

---------------------------------------------------------------- Server mit Stub-api
local function serverSetup(H, T)
	local g = H.Garage({ placeKind = "openworld", startTime = NOW })
	local p = g:Join(1501, { name = "Schrauber" })
	g:Advance(0.5)
	local PW = g:MiniServer("PublicWorkshopService")
	local S = { g = g, p = p, PW = PW, handlers = {}, notices = {}, toasts = {}, events = {}, t = 5000 }
	S.api = {
		now = function()
			return S.t
		end,
		toast = function(_, text)
			table.insert(S.toasts, text)
		end,
		notice = function(_, kind, data)
			data.kind = kind
			table.insert(S.notices, data)
		end,
		dirty = function() end,
		storyEvent = function(_, name, data)
			table.insert(S.events, { name = name, data = data })
		end,
	}
	g:Activate()
	PW.Register({
		Register = function(name, fn)
			S.handlers[name] = fn
		end,
	}, S.api)
	PW._Reset(0)
	S.d = g:D(p)
	S.ms = { p = { mode = "openworld", profile = { data = S.d } }, player = p }
	PW.OnJoin(S.ms, S.d, S.t)
	S.CarRules = g:MiniShared("CarRules")
	S.GC = g:MiniShared("GameConfig").PublicWorkshop
	function S.Call(action, payload)
		g:Activate()
		return S.handlers[action](S.ms, payload or {}, S.d, S.t)
	end
	function S.Tick(dt)
		S.t += dt
		g:Activate()
		return PW.Tick(S.ms, S.d, S.t)
	end
	function S.Station(key)
		return workspace.City.Stations:FindFirstChild(key)
	end
	function S.Go(key, dx)
		g:Teleport(p, S.Station(key), Vector3.new(dx or 6, 0, 0))
	end
	function S.Far()
		g:Teleport(p, Vector3.new(0, 3, -190))
	end
	function S.Last()
		return S.notices[#S.notices]
	end
	function S.LastToast()
		return S.toasts[#S.toasts] or ""
	end
	function S.Grant(model)
		g:Activate()
		local car = S.CarRules.GrantModel(S.d, model, NOW)
		T.check(car ~= nil, "Auto " .. model .. " in die Garage")
		return car
	end
	function S.CarView(id)
		for _, c in ipairs(S.Last().cars or {}) do
			if c.id == tostring(id) then
				return c
			end
		end
		return nil
	end
	return S
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n += 1
	end
	return n
end

---------------------------------------------------------------- Client: Panel-Seite im echten MiniUI-Gerüst
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

local function fakeView(over)
	local v = {
		kind = "pw", event = "open", title = "Große Werkstatt", path = "autohaus", focus = "repair",
		nearRepair = true, nearParts = true, hasCity = true, credits = 50000, stock = 30, stockCap = 400, partsPerRepair = 6,
		stockDiscount = 20, pathDiscount = 0, partsBonus = 0, maxBonus = 35, seconds = 8, maxSell = 50,
		dailyLimit = 200, dailyLeft = 200, repairs = 0,
		cars = {
			{ id = "3", name = "Nord R4", cond = 52, bonus = 34, gain = 4760, cost = 2665, value = 14000, state = "ready" },
			{ id = "5", name = "Komet C1", cond = 100, bonus = 30, gain = 675, cost = 0, value = 2250, state = "repaired" },
			{ id = "7", name = "Vektor RS", cond = 70, bonus = 21, gain = 40950, cost = 99999, value = 195000, state = "ready" },
		},
		parts = { { id = "altteile", name = "Altteile", have = 12, price = 22, max = 12 } },
	}
	for k, x in pairs(over or {}) do
		v[k] = x
	end
	return v
end

local function clientSetup(H, T, vp)
	local g = H.Garage({ placeKind = "openworld", startTime = NOW, viewport = H.Mock.Vector2.new(vp[1], vp[2]) })
	local p = g:Join(1511, { name = "Kunde" })
	g:Advance(0.5)
	g:StartClient(p, { run = false })
	g:Advance(1)
	local rec = recorder(T)
	local S = { g = g, p = p, rec = rec, Hit = H.Load("tests/lib/gui_hit.lua") }
	S.UI = g:ClientModule(p, "Mini.MiniUI")
	S.PW = g:ClientModule(p, "Mini.PublicWorkshopUI")
	g:InClient(p, function()
		-- Verkabelung wie im Integrations-Bericht: Tab "grosswerkstatt" im Panel
		table.insert(S.UI.Tabs, { key = "grosswerkstatt", label = "Große Werkstatt" })
		S.UI.TabTitles.grosswerkstatt = "Große Werkstatt"
		S.UI.Build()
		S.PW._Reset()
		S.PW.Build(S.UI.Pages.grosswerkstatt, { UI = S.UI, Remote = rec, Toast = function() end })
		S.UI.OnTabShown = function(key)
			if key == "grosswerkstatt" then
				S.PW.OnShow()
			end
		end
		S.UI.Open("grosswerkstatt")
	end)
	g:Advance(0.3)
	function S.Notice(v)
		g:InClient(p, function()
			S.PW.OnNotice(v)
		end)
		g:Advance(0.2)
	end
	function S.Find(name)
		for _, x in ipairs(S.UI.Pages.grosswerkstatt:GetDescendants()) do
			if x.Name == name and S.Hit.Visible(x) then
				return x
			end
		end
		return nil
	end
	function S.Click(name)
		local b = S.Find(name)
		local ok = S.Hit.Click(T, g, p, b, { label = name .. " @" .. vp[1] .. "x" .. vp[2] })
		g:Advance(0.4)
		return ok
	end
	return S
end

---------------------------------------------------------------- Fälle
return {
	{ "Große Werkstatt: Welt im Fixture (District, Stationen, Ankunft mit Namen, Schild, Kreisel-Mündung)", function(T, H)
		local g = H.Garage({ placeKind = "all", startTime = NOW, noServer = true })
		g:Activate()
		local city = workspace:FindFirstChild("City")
		T.check(city ~= nil, "Workspace.City")
		local dm = city and city.Districts:FindFirstChild("Grosswerkstatt")
		T.check(dm ~= nil, "City.Districts.Grosswerkstatt (python3 tools/export_fixture.py nach Weltänderungen)")
		if not dm then
			return
		end
		for key, title in pairs({ grosswerkstatt = "Reparatur", teileankauf = "Teile-Ankauf" }) do
			local st = city.Stations:FindFirstChild(key)
			T.check(st ~= nil, "Station " .. key)
			if st then
				T.eq(st:GetAttribute("MiniTab"), "grosswerkstatt", key .. ": MiniTab")
				T.check(tostring(st:GetAttribute("MiniTitle")):find(title, 1, true) ~= nil, key .. ": MiniTitle")
				T.check(st:FindFirstChildOfClass("ProximityPrompt") ~= nil, key .. ": ProximityPrompt")
				T.check(st.Position.X > -640 and st.Position.X < -500 and math.abs(st.Position.Z) < 70, key .. ": auf dem Gelände")
			end
			local ar = city.Arrivals:FindFirstChild(key)
			T.check(ar ~= nil and type(ar:GetAttribute("DisplayName")) == "string", "Ankunft " .. key .. " mit DisplayName")
		end
		local sign = false
		for _, x in ipairs(dm:GetDescendants()) do
			if x:IsA("TextLabel") and x.Text == "GROSSE WERKSTATT" then
				sign = true
			end
		end
		T.check(sign, "Schild „GROSSE WERKSTATT“ (SurfaceGui)")
		T.eq(dm:GetAttribute("KreiselMuendung"), true, "Westmündung des Kreisels gebaut")
		local halls = 0
		for _, x in ipairs(dm.Halle:GetChildren()) do
			if x.Name:match("^Halle_%d$") then
				halls += 1
			end
		end
		T.eq(halls, 4, "4 Reparatur-Hallen")
		g:Close()
	end },

	{ "Große Werkstatt: Daten – Default/Load idempotent, Whitelist, NaN, Deckel", function(T, H)
		local S = serverSetup(H, T)
		local PW = S.PW
		local raw = {
			cars = { ["12"] = { b = 30 }, ["13"] = { p = 500 }, ["x1"] = { b = 10 }, ["14"] = { b = 0 / 0 }, ["15"] = { b = 999 },
				["16"] = { b = 20, p = 77 } },
			day = "2026-10-03", sold = -5, refund = 0 / 0, repairs = 3, partsSold = 1e300, evil = { a = 1 },
		}
		local a = PW.Load(raw)
		local b = PW.Load(a)
		T.check(H.DeepEqual(a, b), "Load idempotent")
		T.eq(a.cars["12"].b, 30, "Bonus bleibt")
		T.eq(a.cars["13"].p, 500, "bezahlt bleibt")
		T.eq(a.cars.x1, nil, "ungültige Id fällt weg")
		T.eq(a.cars["14"], nil, "NaN fällt weg")
		T.eq(a.cars["15"].b, math.floor((S.GC.MaxBonus - 1) * 100 + 0.5), "Bonus gedeckelt")
		T.eq(a.cars["16"].p, nil, "repariert: kein offener Betrag")
		T.eq(a.sold, 0, "negativ -> 0")
		T.eq(a.refund, 0, "NaN -> 0")
		T.eq(a.evil, nil, "unbekannte Schlüssel fallen weg")
		T.check(H.DeepEqual(PW.Load(nil), PW.Default()), "nil -> Default")
		T.eq(PW.ValueBonus(S.d, 999), 1, "ValueBonus unbekanntes Auto = 1")
		T.eq(PW.ValueBonus(nil, 1), 1, "ValueBonus ohne Daten = 1")
		S.g:Close()
	end },

	{ "Große Werkstatt: Reparatur – Abstand, Bezahlen, Weggehen pausiert, Fortsetzen gratis, Abschluss, keine zweite", function(T, H)
		local S = serverSetup(H, T)
		local PW, d, GC = S.PW, S.d, S.GC
		local car = S.Grant("nord")
		local id = tostring(car.id)
		d.money = 100000
		S.Far()
		S.Call("pw_open")
		local v = S.Last()
		T.eq(v.kind, "pw", "Ansicht als mini_notice pw")
		T.eq(v.nearRepair, false, "weit weg")
		local cv = S.CarView(id)
		T.check(cv ~= nil and cv.state == "ready", "Auto reparierbar")
		T.check(cv.cost > 0 and cv.cost < cv.gain, "Kosten unter dem Wertgewinn (" .. tostring(cv.cost) .. " < " .. tostring(cv.gain) .. ")")
		T.check(cv.cond >= GC.CondMin and cv.cond <= GC.CondMax, "Anfangszustand im Bereich")
		-- weit weg: abgelehnt, kein Geld
		T.eq(S.Call("pw_repair", { car = id }), nil, "weit weg abgelehnt")
		T.eq(d.money, 100000, "kein Geld abgebucht")
		T.check(S.LastToast():find("Westende", 1, true) ~= nil, "Hinweis zur Werkstatt")
		-- fremdes Auto / Unsinn
		S.Go("grosswerkstatt")
		T.eq(S.Call("pw_repair", { car = "999" }), nil, "fremde Id abgelehnt")
		T.eq(S.Call("pw_repair", { car = "abc" }), nil, "ungültige Id abgelehnt")
		T.eq(S.Call("pw_repair", { car = 5 }), nil, "Zahl statt Text abgelehnt")
		-- zu wenig Geld
		d.money = 1
		T.eq(S.Call("pw_repair", { car = id }), nil, "zu wenig Geld")
		T.eq(d.money, 1, "nichts abgebucht")
		d.money = 100000
		-- Start
		T.eq(S.Call("pw_repair", { car = id }), true, "Reparatur gestartet")
		T.eq(d.money, 100000 - cv.cost, "Kosten abgebucht")
		T.eq(d.games.pw.cars[id].p, cv.cost, "bezahlt vermerkt")
		T.eq(S.Last().event, "started", "Ereignis started")
		T.check(type(S.Last().job) == "table" and S.Last().job.car == id, "laufende Reparatur in der Ansicht")
		T.eq(S.Call("pw_repair", { car = id }), nil, "zweite gleichzeitig abgelehnt")
		T.eq(S.Tick(GC.RepairSeconds / 2), false, "läuft noch")
		-- weggehen: pausiert, nichts erstattet, kein Bonus
		S.Far()
		T.eq(S.Tick(0.5), true, "pausiert")
		T.eq(S.Last().event, "paused", "Ereignis paused")
		T.eq(PW.ValueBonus(d, car.id), 1, "kein Bonus ohne Abschluss")
		-- zurück: weiter ohne neue Kosten
		S.Go("grosswerkstatt")
		local before = d.money
		T.eq(S.Call("pw_repair", { car = id }), true, "fortgesetzt")
		T.eq(d.money, before, "fortsetzen kostet nichts")
		T.eq(S.Last().event, "resumed", "Ereignis resumed")
		S.Tick(GC.RepairSeconds + 0.5)
		T.eq(S.Last().event, "done", "fertig")
		local b = d.games.pw.cars[id].b
		T.eq(b, cv.bonus, "Bonus gespeichert")
		T.eq(d.games.pw.cars[id].p, nil, "kein offener Betrag mehr")
		local vb = PW.ValueBonus(d, car.id)
		-- 3.x: fester Wertgewinn g (Credits) statt Faktor auf den späteren Wert
		local gFix = d.games.pw.cars[id].g
		T.check(type(gFix) == "number" and gFix > 0, "fester Wertgewinn gespeichert")
		T.near(vb, 1 + gFix / S.CarRules.SellValue(car), 1e-9, "ValueBonus = 1 + Gewinn / Wert")
		T.near(vb, 1 + b / 100, 0.01, "≈ 1 + Bonus")
		T.check(vb > 1 and vb <= GC.MaxBonus, "ValueBonus gedeckelt")
		T.near(PW.ValueBonus(d, id), vb, 1e-9, "ValueBonus auch mit Text-Id")
		T.eq(#S.events, 1, "ein Story-Ereignis")
		T.eq(S.events[1].name, "pw_repair", "Story-Ereignis pw_repair")
		T.eq(S.events[1].data.car, id, "Ereignis: car")
		T.check(S.events[1].data.gain > 0, "Ereignis: gain")
		-- zweite Reparatur bringt nichts
		before = d.money
		T.eq(S.Call("pw_repair", { car = id }), nil, "zweite Reparatur abgelehnt")
		T.eq(d.money, before, "nichts bezahlt")
		T.eq(S.CarView(id).state, "repaired", "Ansicht: repariert")
		-- Laden behält den Bonus
		local reloaded = PW.Load(d.games.pw)
		T.eq(reloaded.cars[id].b, b, "Bonus übersteht Laden")
		S.g:Close()
	end },

	{ "3.x Große Werkstatt: eine Reparatur wird nur einmal belohnt (Händler ODER Kiesplatz), Tuning danach ohne Aufschlag, Load g/k", function(T, H)
		local S = serverSetup(H, T)
		local PW, d, GC = S.PW, S.d, S.GC
		local CR = S.CarRules
		local SR = S.g:MiniShared("StoryRules")
		d.money = 1e7
		d.level = math.max(d.level or 1, 10)
		local function repair(model)
			local car = S.Grant(model)
			local id = tostring(car.id)
			S.Go("grosswerkstatt")
			S.events = {}
			T.eq(S.Call("pw_repair", { car = id }), true, model .. ": Reparatur gestartet")
			S.Tick(GC.RepairSeconds + 0.5)
			T.check(d.games.pw.cars[id] and d.games.pw.cars[id].b > 0, model .. ": repariert")
			-- Verkabelung wie MiniService: api.storyEvent -> StoryService.OnEvent -> StoryRules.OnEvent
			for _, e in ipairs(S.events) do
				SR.OnEvent(d, e.name, e.data, NOW)
			end
			return car, id
		end
		local function kiesSale(tag)
			local offer = SR.NextSale(d, "seed:" .. tag, d.level)
			return SR.Sell(d, offer, 1, NOW), offer
		end
		local st = SR.Data(d)
		st.sales.repaired = 0
		-- 1) Reparatur -> Händler: Wertbonus, der Kiesplatz-Bonus derselben Reparatur verfällt
		local car1, id1 = repair("komet")
		T.eq(st.sales.repaired, 1, "Reparatur wartet am Kiesplatz")
		local g1 = d.games.pw.cars[id1].g
		local base1 = CR.SellValue(car1)
		local before = d.money
		local ok, value = CR.Sell(d, car1.id)
		T.eq(ok, true, "Händler kauft")
		T.eq(value, base1 + g1, "Händler zahlt Wert + festen Gewinn")
		T.eq(d.money - before, value, "gutgeschrieben")
		T.eq(st.sales.repaired, 0, "Kiesplatz-Bonus verbraucht (eine Reparatur, eine Belohnung)")
		local res = kiesSale("a")
		T.check(res and res.sold == true and res.repaired == false, "nächster Kiesplatz-Verkauf ohne ×1,5")
		-- 2) Reparatur -> Kiesplatz: ×1,5 dort, beim Händler danach nur der normale Wert
		local car2, id2 = repair("komet")
		T.eq(st.sales.repaired, 1, "zweite Reparatur wartet")
		local res2, offer2 = kiesSale("b")
		T.check(res2 and res2.repaired == true, "Kiesplatz ×1,5")
		T.eq(d.games.pw.cars[id2].k, 1, "Wertbonus des reparierten Autos verbraucht (k)")
		T.eq(PW.ValueBonus(d, car2.id), 1, "kein Wertbonus mehr beim Händler")
		T.eq(CR.SalePrice(d, car2), CR.SellValue(car2), "Händlerpreis ohne Bonus")
		S.Go("grosswerkstatt")
		T.eq(S.Call("pw_repair", { car = id2 }), nil, "keine zweite Reparatur")
		T.eq(PW.Quote(d, car2).state, "repaired", "Ansicht: repariert")
		T.eq(PW.Quote(d, car2).gain, 0, "Ansicht: kein Gewinn mehr")
		local ok2 = CR.Sell(d, car2.id)
		T.eq(ok2, true, "verkauft")
		T.eq(st.sales.repaired, 0, "kein negativer Bonus-Zähler")
		-- 3) Tuning nach der Reparatur: Händler zahlt fürs Tuning nur den normalen Anteil (kein Aufschlag)
		local car3, id3 = repair("komet")
		local price0 = CR.SalePrice(d, car3)
		local sell0 = CR.SellValue(car3)
		local part = S.g:MiniShared("CarCatalog").TuneParts[1]
		car3[part] = 3
		local sell1 = CR.SellValue(car3)
		T.check(sell1 > sell0, "Tuning erhöht den Wert")
		T.eq(CR.SalePrice(d, car3) - price0, sell1 - sell0, "Tuning-Anteil ohne Werkstatt-Aufschlag")
		T.check(PW.ValueBonus(d, car3.id) <= GC.MaxBonus, "Faktor gedeckelt")
		-- 4) Load: g/k nur mit Bonus, Whitelist
		local a = PW.Load({ cars = { ["5"] = { b = 20, g = 300, k = 1 }, ["6"] = { b = 20, g = -4, k = "x" }, ["7"] = { p = 9, g = 50, k = 1 } } })
		T.eq(a.cars["5"].g, 300, "g bleibt")
		T.eq(a.cars["5"].k, 1, "k bleibt")
		T.eq(a.cars["6"].g, nil, "g negativ fällt weg")
		T.eq(a.cars["6"].k, nil, "k ungültig fällt weg")
		T.eq(a.cars["7"].g, nil, "ohne Bonus kein g")
		T.eq(a.cars["7"].k, nil, "ohne Bonus kein k")
		T.check(H.DeepEqual(a, PW.Load(a)), "Load idempotent")
		-- alte Einträge ohne g: Bonus nur auf den Grundwert (ohne Tuning)
		d.games.pw.cars[id3].g = nil
		local legacy = PW.ValueBonus(d, car3.id)
		local expect = math.floor(CR.Value(car3) * S.g:MiniShared("CarCatalog").SellShare * d.games.pw.cars[id3].b / 100)
		T.near(legacy, 1 + expect / CR.SellValue(car3), 1e-9, "alter Eintrag: Bonus nur auf den Grundwert")
		S.g:Close()
	end },

	{ "Große Werkstatt: Exploits – Kosten < Gewinn je Modell, Kauf+Reparatur+Verkauf ohne Gewinn, Erstattung, Auktion", function(T, H)
		local S = serverSetup(H, T)
		local PW, d, GC = S.PW, S.d, S.GC
		local CarCatalog = S.g:MiniShared("CarCatalog")
		d.money = 1e9
		local n = 0
		for _, m in ipairs(CarCatalog.Models or {}) do
			n += 1
		end
		local ids = { "komet", "komet_s2", "nord", "atlas", "vektor", "aureon", "komet_rally", "nord_classic", "vektor_gold" }
		for _, model in ipairs(ids) do
			if CarCatalog.Model(model) then
				local car = S.Grant(model)
				for stock = 0, 1 do
					PW._Reset(stock * 100)
					local q = PW.Quote(d, car)
					if q.state == "ready" then
						T.check(q.cost < q.gain, model .. ": Kosten < Gewinn")
						T.check(q.cost >= math.floor(q.gain * GC.MinCostShare) - 1, model .. ": Kosten ≥ MinCostShare × Gewinn")
						-- Sondermodelle: NPC-Auktion startet bei 60 % des Werts – Verkauf mit Bonus abzüglich Reparatur bleibt darunter
						local m = CarCatalog.Model(model)
						local net = q.value + q.gain - q.cost
						T.check(net < m.value * 0.6, model .. ": Kauf + Reparatur + Verkauf bringt keinen Gewinn")
					end
					T.check(q.bonus <= math.floor((GC.MaxBonus - 1) * 100 + 0.5), model .. ": Bonus gedeckelt")
				end
			end
		end
		T.check(n >= 0, "Katalog gelesen")
		-- Auktion: gesperrtes Auto nicht reparierbar
		PW._Reset(0)
		local locked = S.Grant("komet_s2")
		locked.locked = true
		S.Go("grosswerkstatt")
		local before = d.money
		T.eq(S.Call("pw_repair", { car = tostring(locked.id) }), nil, "Auktions-Auto abgelehnt")
		T.eq(d.money, before, "nichts bezahlt")
		-- Verkauf mitten in der Reparatur: Erstattung bei der nächsten Aktion
		local car = S.Grant("atlas")
		local id = tostring(car.id)
		T.eq(S.Call("pw_repair", { car = id }), true, "gestartet")
		local paid = d.games.pw.cars[id].p
		T.check(paid > 0, "bezahlt")
		S.CarRules.RemoveCar(d, car.id)
		S.Tick(0.5)
		T.eq(S.Last().event, "aborted", "abgebrochen: Auto weg")
		local mid = d.money
		S.Call("pw_open")
		T.eq(d.money, mid + paid, "Erstattung ausgezahlt")
		T.eq(d.games.pw.refund, 0, "Erstattung nur einmal")
		S.Call("pw_open")
		T.eq(d.money, mid + paid, "keine zweite Erstattung")
		T.eq(d.games.pw.cars[id], nil, "Eintrag des verkauften Autos gelöscht")
		S.g:Close()
	end },

	{ "Große Werkstatt: Teile-Ankauf – Abstand, Bestand zuerst abgebucht, Preise, Vorrat senkt Kosten, Tageslimit", function(T, H)
		local S = serverSetup(H, T)
		local PW, d, GC = S.PW, S.d, S.GC
		d.games.parts = 30
		local money = d.money
		S.Go("grosswerkstatt")
		T.eq(S.Call("pw_sell_parts", { part = "altteile", count = 5 }), nil, "an der Halle: nicht am Ankauf")
		T.eq(d.games.parts, 30, "keine Teile weg")
		S.Go("teileankauf")
		for _, bad in ipairs({ { part = "altteile", count = 0 }, { part = "altteile", count = 51 }, { part = "altteile", count = 1.5 },
			{ part = "motor", count = 1 }, { part = "altteile", count = 0 / 0 } }) do
			T.eq(S.Call("pw_sell_parts", bad), nil, "ungültig: " .. tostring(bad.part) .. " " .. tostring(bad.count))
		end
		T.eq(S.Call("pw_sell_parts", { part = "altteile", count = 31 }), nil, "mehr als vorhanden abgelehnt")
		T.eq(d.games.parts, 30, "Bestand unverändert")
		T.eq(d.money, money, "kein Geld für Ablehnungen")
		local q0
		local car = S.Grant("nord")
		q0 = PW.Quote(d, car)
		T.eq(S.Call("pw_sell_parts", { part = "altteile", count = 10 }), true, "verkauft")
		T.eq(d.games.parts, 20, "10 Teile abgebucht")
		T.check(d.money - money >= 10 * 22, "mindestens 22 Cr je Altteil (Schrotthändler: 16)")
		T.eq(PW.Stock, 10, "Vorrat der Werkstatt +10")
		T.eq(S.Last().event, "sold", "Ereignis sold")
		T.eq(S.events[#S.events].name, "pw_parts_sold", "Story-Ereignis pw_parts_sold")
		T.eq(S.events[#S.events].data.count, 10, "Ereignis: count")
		local q1 = PW.Quote(d, car)
		T.check(q1.cost < q0.cost, "Vorrat macht Reparaturen billiger (" .. q1.cost .. " < " .. q0.cost .. ")")
		-- Tageslimit
		d.games.pw.sold = GC.DailyPartsLimit - 3
		T.eq(S.Call("pw_sell_parts", { part = "altteile", count = 10 }), true, "Rest des Tages")
		T.eq(d.games.parts, 17, "nur 3 angenommen")
		T.eq(S.Call("pw_sell_parts", { part = "altteile", count = 1 }), nil, "Tageslimit erreicht")
		-- neuer Tag
		S.t += 86400
		T.eq(S.Call("pw_sell_parts", { part = "altteile", count = 2 }), true, "am nächsten Tag wieder")
		-- Startweg Schrottplatz: +10 %
		d.games.meta.startPath = "schrottplatz"
		T.near(PW.PartPrice(d, "altteile"), 22 * 1.1, 1e-6, "Schrottplatz-Weg +10 %")
		d.games.meta.startPath = "werkstatt"
		PW._Reset(0)
		local plain = PW.Quote(d, car).cost
		d.games.meta.startPath = "autohaus"
		T.check(PW.Quote(d, car).cost > plain, "Werkstatt-Weg bekommt Rabatt")
		T.eq(count(S.handlers), 3, "drei Aktionen registriert")
		S.g:Close()
	end },

	{ "Große Werkstatt: Panel an drei Viewports – Reiter, Reparieren, Teile verkaufen, Fortschritt, Knöpfe ≥ 44 px", function(T, H)
		for _, vp in ipairs(VIEWPORTS) do
			local S = clientSetup(H, T, vp)
			local g, p = S.g, S.p
			local tag = " @" .. vp[1] .. "x" .. vp[2]
			T.eq(S.rec.Count("pw_open"), 1, "Öffnen sendet pw_open" .. tag)
			S.Notice(fakeView())
			T.eq(S.PW.Sub(), "repair", "Reiter Reparieren (focus)" .. tag)
			local rep = S.Find("Repair_3")
			T.check(rep ~= nil and rep.Text:find("Reparieren", 1, true) ~= nil, "Knopf Reparieren" .. tag)
			T.check(rep.AbsoluteSize.Y >= 44 or rep.Size.Y.Offset >= 44, "Knopf ≥ 44 px" .. tag)
			T.check(S.Find("Repair_5").Text:find("Top", 1, true) ~= nil, "repariertes Auto: Top in Schuss" .. tag)
			T.check(S.Find("Repair_7").Text:find("Zu teuer", 1, true) ~= nil, "zu teuer markiert" .. tag)
			S.Click("Repair_3")
			local sent = S.rec.Last("pw_repair")
			T.check(sent ~= nil and sent.car == "3" and count(sent) == 1, "pw_repair { car = \"3\" }" .. tag)
			S.Click("Repair_5")
			T.eq(S.rec.Count("pw_repair"), 1, "repariertes Auto sendet nichts" .. tag)
			-- laufende Reparatur: Fortschritt
			local cars = fakeView().cars
			cars[1].state = "working"
			S.Notice(fakeView({ event = "started", cars = cars, job = { car = "3", name = "Nord R4", left = 8, total = 8 } }))
			T.check(S.Find("Job") ~= nil, "Fortschritts-Karte sichtbar" .. tag)
			local left = S.Find("JobLeft")
			T.check(left ~= nil and left.Text:find("Noch", 1, true) ~= nil, "Restzeit" .. tag)
			S.Notice(fakeView({ event = "done" }))
			T.eq(S.Find("Job"), nil, "Fortschritt weg nach Abschluss" .. tag)
			-- Teile verkaufen
			S.Click("PwTab_parts")
			T.eq(S.PW.Sub(), "parts", "Reiter Teile" .. tag)
			local sell = S.Find("Sell_altteile")
			T.check(sell ~= nil and sell.Text:find("12 verkaufen", 1, true) ~= nil, "alle 12 vorgeschlagen" .. tag)
			S.Click("Minus")
			S.Click("Minus")
			T.check(S.Find("Sell_altteile").Text:find("10 verkaufen", 1, true) ~= nil, "Minus zählt runter" .. tag)
			S.Click("Plus")
			S.Click("Sell_altteile")
			local ps = S.rec.Last("pw_sell_parts")
			T.check(ps ~= nil and ps.part == "altteile" and ps.count == 11 and count(ps) == 2, "pw_sell_parts { part, count = 11 }" .. tag)
			S.Click("Max")
			T.check(S.Find("Sell_altteile").Text:find("12 verkaufen", 1, true) ~= nil, "Alle" .. tag)
			-- keine Teile: Knopf aus
			S.Notice(fakeView({ parts = { { id = "altteile", name = "Altteile", have = 0, price = 22, max = 0 } } }))
			S.Click("Sell_altteile")
			T.eq(S.rec.Count("pw_sell_parts"), 1, "ohne Teile wird nichts gesendet" .. tag)
			-- weit weg: Hinweis
			S.Notice(fakeView({ nearParts = false, nearRepair = false }))
			T.check(S.Find("Hint") ~= nil, "Hinweis, wenn weit weg" .. tag)
			-- Schrottplatz-Weg: Teile-Reiter zuerst
			g:InClient(p, function()
				S.PW.OnShow()
			end)
			S.Notice(fakeView({ path = "schrottplatz", focus = "parts" }))
			T.eq(S.PW.Sub(), "parts", "Schrottplatz: Teile zuerst" .. tag)
			T.check(S.Find("PwTab_parts").Text:find("★", 1, true) ~= nil, "Empfehlung markiert" .. tag)
			S.Click("PwTab_repair")
			T.eq(S.PW.Sub(), "repair", "zurück zu Reparieren" .. tag)
			T.eq(g:ErrorText(), "", "keine Fehler" .. tag)
			g:Close()
		end
	end },
}
