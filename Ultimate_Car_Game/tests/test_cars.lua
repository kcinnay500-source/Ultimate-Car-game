-- Eigene Autos: CarCatalog, CarRules, TrackRules (rein) und CarService/VehicleFactory im echten Server (Mock).
-- CarService wird hier über eine eigene Aktionen-Tabelle registriert (unabhängig von der MiniService-Verkabelung);
-- der letzte Fall prüft den echten Weg über Remotes.Command, sobald MiniNet die Aktionen kennt.
local NOW = 1760000000

---------------------------------------------------------------- Hilfen
local function modules(g)
	return g:MiniShared("CarCatalog"), g:MiniShared("CarRules"), g:MiniShared("TrackRules")
end

local function freshData(g)
	local d = g:Rules().NewData(NOW)
	d.money = 0
	d.level = 1
	return d
end

-- Server mit CarService über eine eigene Aktionen-Tabelle und eine protokollierende api
local function setup(H)
	local g = H.Garage()
	local CS = g:MiniServer("CarService")
	local log = { notices = {}, toasts = {}, changed = 0, moves = {} }
	local handlers = {}
	local fakeApi = {
		now = function()
			return g.env.workspace:GetServerTimeNow()
		end,
		toast = function(ms, text)
			table.insert(log.toasts, { player = ms.player, text = text })
		end,
		notice = function(ms, kind, data)
			table.insert(log.notices, { player = ms.player, kind = kind, data = data })
		end,
		dirty = function(ms)
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
	CS.Register({
		Register = function(name, fn)
			handlers[name] = fn
		end,
	}, fakeApi)
	CS.Init({
		changed = function()
			log.changed += 1
		end,
		push = function() end,
		toast = function(p, text)
			table.insert(log.toasts, { player = p.player, text = text })
		end,
		getSession = function(player)
			return g:Session(player)
		end,
		moveTo = function(_, part)
			table.insert(log.moves, part)
		end,
		now = fakeApi.now,
	})
	g:Flush()
	local S = { g = g, CS = CS, log = log, handlers = handlers }
	function S.join(userId, name)
		local pl = g:Join(userId, { name = name })
		g:Advance(0.5)
		local ms = g:MiniState(pl)
		CS.OnJoin(ms, g:D(pl), g:Now())
		g:Flush()
		return pl, ms
	end
	function S.act(pl, action, data)
		g:Activate()
		handlers[action](g:MiniState(pl), data or {}, g:D(pl), g:Now())
		g:Flush()
	end
	function S.tick(pl)
		g:Activate()
		CS.Tick(g:MiniState(pl), g:D(pl), g:Now())
		g:Flush()
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
	function S.car(pl, prefix)
		local folder = g.env.workspace:FindFirstChild("PlayerCars")
		return folder and folder:FindFirstChild((prefix or "Car_") .. pl.UserId)
	end
	function S.humanoid(pl)
		return pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
	end
	-- Besitzer "sitzt" (im Mock gibt es kein VehicleSeat:Sit): Occupant setzen löst den Sitzschutz aus
	function S.sit(pl, model, who)
		g:Activate()
		model.DriverSeat.Occupant = S.humanoid(who or pl)
		g:Flush()
	end
	return S
end

-- Entfernt Teile der generierten Stadt (Fixture), damit ein Fall seine eigene Strecke/Spawns aufbauen
-- oder den Rückfall ohne sie prüfen kann. Die echten Teile prüft test_phase2.lua.
local function removeGenerated(g, names)
	g:Activate()
	local city = g.env.workspace:FindFirstChild("City")
	for _, name in ipairs(names) do
		local x = city and city:FindFirstChild(name)
		if x then
			x:Destroy()
		end
	end
end

local function removePlotSpawn(g, pl)
	g:Activate()
	local plot = g:Plot(pl)
	local sp = plot and plot:FindFirstChild("CarSpawn", true)
	if sp then
		sp:Destroy()
	end
end

local function countOwned(S, pl)
	local folder = S.g.env.workspace:FindFirstChild("PlayerCars")
	local n = 0
	for _, m in ipairs(folder and folder:GetChildren() or {}) do
		if m:GetAttribute("OwnerId") == pl.UserId then
			n += 1
		end
	end
	return n
end

return {
	---------------------------------------------------------------- Katalog
	{ "Katalog übernimmt die neun 2.4.0-Modelle, Preise steigen, Sondermodelle nur per Auktion", function(T, H)
		local g = H.Garage({ noServer = true })
		local C = g:Config()
		local CC, CR = modules(g)
		T.eq(#CC.DealerModels, #C.Cars, "ein Händlermodell je C.Cars-Eintrag")
		local templates = g:Find("ServerStorage.CarTemplates")
		local prev = 0
		for i, car in ipairs(C.Cars) do
			local m = CC.DealerModels[i]
			T.eq(m.id, car.id, "Id " .. i)
			T.eq(m.name, car.name, "Name " .. car.id)
			T.eq(m.body, car.body, "Karosserie " .. car.id)
			-- Ausbaustufe 4: das Händler-Level kommt aus GameConfig.Unlocks (Unlocks.CarLevel), C.Cars[].level bleibt Kundenauto
			T.eq(m.level, g:MiniShared("Unlocks").CarLevel(car.id), "Level " .. car.id)
			T.check(m.level >= car.level, "Händler-Level nie unter dem 2.4.0-Kundenlevel: " .. car.id)
			T.check(m.price > prev, "Preis steigt: " .. car.id)
			prev = m.price
			T.check(templates and templates:FindFirstChild(m.body) ~= nil, "Vorlage vorhanden: " .. m.body)
			T.check(CC.Paints[m.paint] ~= nil, "Standardlack gültig: " .. car.id)
		end
		T.check(CC.DealerModels[1].price >= 3500 and CC.DealerModels[1].price <= 6500, "Kompakt nach etwa 20–30 Min. Werkstatt")
		T.eq(#CC.Paints, 12, "12 Lackfarben")
		T.eq(#CC.Rims, 8, "8 Felgenfarben")
		T.eq(#CC.Glows, 6, "6 Unterbodenfarben")
		T.check(#CC.Specials >= 3, "Sondermodelle für NPC-Auktionen")
		for _, s in ipairs(CC.Specials) do
			local m = CC.Model(s.id)
			T.check(m and m.special and not m.dealer, "Sondermodell nicht beim Händler: " .. s.id)
			T.check(templates and templates:FindFirstChild(s.body) ~= nil, "Sondermodell-Vorlage: " .. s.body)
		end
		-- Fahrwerte: schnellere Klassen sind schneller
		local compact = CR.Stats(CR.NewCar("komet", 0))
		local super = CR.Stats(CR.NewCar("aureon", 0))
		T.check(super.topSpeed > compact.topSpeed and super.accel > compact.accel, "Supersportwagen schneller als Kompakt")
		T.check(super.zeroTo100 ~= nil and super.zeroTo100 < 5, "0–100 unter 5 s beim Supersportwagen")
	end },

	---------------------------------------------------------------- Laden
	{ "Laden normalisiert, ist idempotent und verwirft Unbekanntes", function(T, H)
		local g = H.Garage({ noServer = true })
		local CC, CR = modules(g)
		local d = freshData(g)
		local raw = {
			carSerial = 3,
			activeCar = 99,
			cars = {
				{ id = 2, model = "komet", paint = 6, rims = 3, glow = 2, spoiler = true, engine = 3, gearbox = 9, tires = -1,
					suspension = 0 / 0, nitro = 2, bought = 123, locked = true, junk = "x" },
				{ id = 2, model = "nord", paint = 99 }, -- doppelte Id -> neue Id
				{ id = 5, model = "gibtsnicht" }, -- unbekanntes Modell -> weg
				"kaputt",
				{ model = "vektor_gold" }, -- Sondermodell ohne Id
			},
		}
		local a = CR.Load(raw, d, NOW)
		T.eq(#a.cars, 3, "drei gültige Autos")
		T.eq(a.cars[1].id, 2, "Id 2 bleibt")
		T.eq(a.cars[1].gearbox, 0, "Getriebe 9 > max -> Standard")
		T.eq(a.cars[1].tires, 0, "negative Stufe -> 0")
		T.eq(a.cars[1].suspension, 0, "NaN -> 0")
		T.eq(a.cars[1].engine, 3, "Motor 3 bleibt")
		T.eq(a.cars[1].locked, false, "Auktions-Sperre wird beim Laden aufgehoben (sitzungsgebunden)")
		T.eq(a.cars[1].junk, nil, "unbekannte Felder fallen weg")
		T.eq(a.cars[2].id, 4, "doppelte Id bekommt neue Id")
		T.eq(a.cars[2].paint, CC.Model("nord").paint, "ungültige Farbe -> Standardfarbe")
		T.eq(a.cars[3].id, 5, "fehlende Id bekommt neue Id")
		T.eq(a.carSerial, 5, "Serie fortgeschrieben")
		T.eq(a.activeCar, 2, "ungültiges aktives Auto -> erstes Auto")
		local b = CR.Load(a, d, NOW)
		T.check(H.DeepEqual(a, b), "Load(Load(x)) == Load(x)")
		local many = { cars = {} }
		for i = 1, 30 do
			many.cars[i] = { id = i, model = "komet" }
		end
		T.eq(#CR.Load(many, d, NOW).cars, CC.MaxCars, "höchstens 20 Autos")
		local empty = CR.Load(nil, d, NOW)
		T.eq(#empty.cars, 0, "ohne Daten leer")
		T.eq(empty.activeCar, 0, "kein aktives Auto")
		-- ApplyDefault/ApplyLoad schreiben in ein games-Table
		local gTable = {}
		CR.ApplyLoad(gTable, raw, d, NOW)
		T.eq(#gTable.cars, 3, "ApplyLoad setzt cars")
		T.eq(gTable.carSerial, 5, "ApplyLoad setzt carSerial")
	end },

	---------------------------------------------------------------- Kaufen, Tunen, Optik, Verkaufen
	{ "Kaufen: Level, Guthaben, Doppelklick, Garage voll", function(T, H)
		local g = H.Garage({ noServer = true })
		local CC, CR = modules(g)
		local d = freshData(g)
		local price = CC.Model("komet").price
		local ok, msg = CR.Buy(d, "komet", NOW)
		T.eq(ok, false, "ohne Geld kein Kauf")
		T.check(type(msg) == "string", "Meldung")
		d.money = price + 10
		T.eq((CR.Buy(d, "komet", NOW)), false, "Komet ab Level 3 (Ausbaustufe 4)")
		d.level = 3
		T.eq((CR.Buy(d, "vektor", NOW)), false, "Level 45 nötig")
		T.eq((CR.Buy(d, "vektor_gold", NOW)), false, "Sondermodell nicht beim Händler")
		local ok2, car = CR.Buy(d, "komet", NOW)
		T.eq(ok2, true, "Kauf klappt")
		T.eq(d.money, 10, "Preis exakt abgezogen")
		T.eq(car.id, 1, "erste Id")
		T.eq(d.games.activeCar, 1, "erstes Auto wird aktiv")
		d.money = 1e9
		local ok3, msg3 = CR.Buy(d, "komet", NOW + 1)
		T.eq(ok3, false, "gleiches Modell sofort erneut = Doppelklick")
		T.eq(msg3, nil, "still verworfen")
		T.eq(#d.games.cars, 1, "nur ein Auto")
		T.eq((CR.Buy(d, "komet", NOW + CC.BuyRepeatSeconds + 1)), true, "später ein zweites erlaubt")
		for i = 1, CC.MaxCars do
			CR.Buy(d, "komet", NOW + 100 * i)
		end
		T.eq(#d.games.cars, CC.MaxCars, "Garage voll bei 20")
		local okFull, msgFull = CR.Buy(d, "komet", NOW + 99999)
		T.eq(okFull, false, "kein 21. Auto")
		T.check(type(msgFull) == "string" and msgFull:find("voll", 1, true) ~= nil, "Meldung Garage voll")
		T.eq((CR.GrantModel(d, "aureon_nero", NOW)), nil, "auch Auktionsgewinn scheitert bei voller Garage")
	end },

	{ "Tuning: gesehene Stufe, Level, Kosten skalieren mit dem Autowert, gesperrte Autos", function(T, H)
		local g = H.Garage({ noServer = true })
		local CC, CR = modules(g)
		local d = freshData(g)
		d.money = 1e9
		d.level = 50
		local _, compact = CR.Buy(d, "komet", NOW)
		local _, sport = CR.Buy(d, "vektor", NOW)
		T.check(CR.TuneCost(sport, "engine", 1) > CR.TuneCost(compact, "engine", 1) * 10, "Tuning-Kosten skalieren mit dem Autowert")
		T.check(CR.TuneCost(compact, "engine", 2) > CR.TuneCost(compact, "engine", 1), "höhere Stufe teurer")
		local before = CR.Stats(compact)
		local money = d.money
		local cost = CR.TuneCost(compact, "engine", 1)
		local ok, lvl = CR.Tune(d, compact.id, "engine", 0)
		T.eq(ok, true, "Motor Stufe 1")
		T.eq(lvl, 1, "neue Stufe")
		T.eq(d.money, money - cost, "Kosten abgezogen")
		local ok2, msg2 = CR.Tune(d, compact.id, "engine", 0)
		T.eq(ok2, false, "gleiche gesehene Stufe nochmal = Doppelklick")
		T.eq(msg2, nil, "still")
		T.eq(compact.engine, 1, "nicht doppelt getunt")
		for l = 1, 4 do
			CR.Tune(d, compact.id, "engine", l)
		end
		T.eq(compact.engine, 5, "Motor voll")
		T.eq((CR.Tune(d, compact.id, "engine", 5)), false, "über max. nicht möglich")
		for l = 0, 4 do
			CR.Tune(d, compact.id, "gearbox", l)
			CR.Tune(d, compact.id, "tires", l)
			CR.Tune(d, compact.id, "suspension", l)
		end
		for l = 0, 2 do
			CR.Tune(d, compact.id, "nitro", l)
		end
		local after = CR.Stats(compact)
		T.check(after.topSpeed > before.topSpeed, "schneller")
		T.check(after.accel > before.accel, "beschleunigt besser")
		T.check(after.grip > before.grip, "mehr Grip")
		T.check(after.springRate > before.springRate, "straffer")
		T.eq(after.nitro.level, 3, "Nitro 3")
		T.check(after.nitro.boost > 1 and after.nitro.cooldown > 0, "Nitro-Werte")
		-- Level-Voraussetzung
		local d2 = freshData(g)
		d2.money = 1e9
		d2.level = 3 -- Komet ab Level 3 (Ausbaustufe 4)
		local _, c2 = CR.Buy(d2, "komet", NOW)
		local okLvl, msgLvl = CR.Tune(d2, c2.id, "engine", 0)
		T.eq(okLvl, true, "Motor 1 ab Level 1")
		d2.level = 1
		okLvl, msgLvl = CR.Tune(d2, c2.id, "engine", 1)
		T.eq(okLvl, false, "Motor 2 braucht Level 3")
		T.check(type(msgLvl) == "string" and msgLvl:find("Level", 1, true) ~= nil, "Meldung nennt das Level")
		T.eq((CR.Tune(d2, c2.id, "nitro", 0)), false, "Nitro erst ab Level 5")
		T.eq((CR.Tune(d2, c2.id, "turbo", 0)), false, "unbekanntes Bauteil")
		-- gesperrt (Auktion)
		CR.SetLocked(d2, c2.id, true)
		T.eq((CR.Tune(d2, c2.id, "tires", 0)), false, "gesperrtes Auto nicht tunen")
		T.eq((CR.CanSpawn(d2, c2.id)), false, "gesperrtes Auto nicht spawnen")
		T.eq((CR.Sell(d2, c2.id)), false, "gesperrtes Auto nicht verkaufen")
		T.eq((CR.Style(d2, c2.id, 1, 1, 0, false)), false, "gesperrtes Auto nicht umlackieren")
		T.eq((CR.SetActive(d2, c2.id)), false, "gesperrtes Auto nicht aktiv setzen")
		CR.SetLocked(d2, c2.id, false)
		T.eq((CR.CanSpawn(d2, c2.id)), true, "entsperrt wieder fahrbar")
	end },

	{ "Optik: nur Änderungen kosten, gleiche Werte sind gratis, Grenzen", function(T, H)
		local g = H.Garage({ noServer = true })
		local CC, CR = modules(g)
		local d = freshData(g)
		d.money = 100000
		d.level = 3 -- Komet ab Level 3
		local _, car = CR.Buy(d, "komet", NOW)
		local money = d.money
		local ok, cost, changes = CR.Style(d, car.id, car.paint, car.rims, car.glow, car.spoiler)
		T.eq(ok, true, "gleiche Werte ok")
		T.eq(cost, 0, "gleiche Werte kosten nichts")
		T.eq(#changes, 0, "keine Änderung")
		T.eq(d.money, money, "Geld unverändert")
		ok, cost = CR.Style(d, car.id, 6, 3, car.glow, true)
		T.eq(ok, true, "Lack, Felgen, Spoiler")
		T.eq(cost, CR.StyleCost(car, "paint") + CR.StyleCost(car, "rims") + CR.StyleCost(car, "spoiler"), "Summe der Änderungen")
		T.eq(d.money, money - cost, "abgezogen")
		T.eq(car.paint, 6, "Lack gesetzt")
		T.eq(car.spoiler, true, "Spoiler an")
		local okGlow, msgGlow = CR.Style(d, car.id, 6, 3, 2, true)
		T.eq(okGlow, false, "Unterbodenlicht erst ab Level 5")
		T.check(type(msgGlow) == "string", "Meldung")
		d.level = 5
		T.eq((CR.Style(d, car.id, 6, 3, 2, true)), true, "ab Level 5")
		T.eq((CR.Style(d, car.id, 13, 3, 2, true)), false, "Lack 13 ungültig")
		T.eq((CR.Style(d, car.id, 6, 9, 2, true)), false, "Felge 9 ungültig")
		T.eq((CR.Style(d, car.id, 6, 3, 7, true)), false, "Unterboden 7 ungültig")
		T.eq((CR.Style(d, car.id, 1.5, 3, 2, true)), false, "Kommazahl ungültig")
		T.eq((CR.Style(d, 999, 1, 1, 0, false)), false, "fremdes Auto")
		d.money = 0
		T.eq((CR.Style(d, car.id, 1, 3, 2, true)), false, "ohne Geld keine Änderung")
		T.eq(car.paint, 6, "Lack unverändert")
		T.eq(CR.Paint, CR.Style, "Paint = Style")
	end },

	{ "Verkaufen: 50 % von Wert + Tuning, aktives Auto wechselt, kein Doppelverkauf", function(T, H)
		local g = H.Garage({ noServer = true })
		local CC, CR = modules(g)
		local d = freshData(g)
		d.money = 1e6
		d.level = 20
		local _, a = CR.Buy(d, "komet", NOW)
		local _, b = CR.Buy(d, "nord", NOW)
		CR.Tune(d, a.id, "engine", 0)
		local expected = math.floor((CC.Model("komet").price + CR.TuneCost(a, "engine", 1)) * 0.5 + 0.5)
		T.eq(CR.SellValue(a), expected, "Rückkaufwert")
		local money = d.money
		local ok, value = CR.Sell(d, a.id)
		T.eq(ok, true, "verkauft")
		T.eq(value, expected, "Erlös")
		T.eq(d.money, money + expected, "gutgeschrieben")
		T.eq(d.games.activeCar, b.id, "aktives Auto wechselt auf das verbleibende")
		local ok2, msg2 = CR.Sell(d, a.id)
		T.eq(ok2, false, "zweiter Verkauf scheitert")
		T.eq(msg2, nil, "still (Doppelklick)")
		T.eq(d.money, money + expected, "kein doppelter Erlös")
		-- Auktions-Hilfen
		local removed = CR.RemoveCar(d, b.id)
		T.eq(removed.model, "nord", "RemoveCar liefert den Datensatz")
		T.eq(d.games.activeCar, 0, "kein Auto mehr aktiv")
		local added = CR.AddCar(d, removed)
		T.check(added and added.id > b.id, "AddCar vergibt neue Id")
		T.eq(d.games.activeCar, added.id, "einziges Auto wird aktiv")
		local granted = CR.GrantModel(d, "vektor_gold", NOW)
		T.eq(granted.model, "vektor_gold", "Sondermodell gutgeschrieben")
		T.eq(granted.spoiler, true, "Auslieferungszustand des Sondermodells")
	end },

	---------------------------------------------------------------- Zeitfahren (rein)
	{ "TrackRules: Reihenfolge, Frühstart, Teleport, Ziel, Belohnung gedeckelt", function(T, H)
		local g = H.Garage({ noServer = true })
		local CC, _, TR = modules(g)
		local c = CC.Track
		T.check(H.DeepEqual(TR.Load(TR.Load({ best = 30, rewardedBest = 31, runs = 4 })), TR.Load({ best = 30, rewardedBest = 31, runs = 4 })), "Load idempotent")
		local l = TR.Load({ best = 0 / 0, rewardedBest = -5, runs = 1.7 })
		T.eq(l.best, 0, "NaN -> 0")
		T.eq(l.rewardedBest, 0, "negativ -> 0")
		T.eq(l.runs, 1, "runs ganzzahlig")
		T.eq(TR.Load({ best = 50, rewardedBest = 40 }).best, 40, "Bestzeit nie schlechter als belohnte")
		local points = { Vector3.new(0, 0, 100), Vector3.new(0, 0, 400), Vector3.new(0, 0, 700) }
		local mins = TR.MinTimes(Vector3.new(0, 0, 0), points)
		T.eq(#mins, 3, "eine Mindestzeit je Checkpoint")
		T.check(mins[2] >= 300 / TR.MaxSpeed() - 1e-9 and mins[2] >= c.segmentFloor, "Luftlinie / Höchsttempo")
		local run = TR.NewRun(mins, 1000)
		T.eq(run.startAt, 1000 + c.countdown, "Startampel")
		T.eq((TR.Touch(run, 2, 1010)), "ignored", "falscher Checkpoint zählt nicht")
		T.eq((TR.Touch(run, 1, 1002)), "early", "Frühstart")
		T.eq((TR.Touch(run, 1, 1010)), "ignored", "Lauf nach Frühstart erledigt")
		run = TR.NewRun(mins, 1000)
		local res, info = TR.Touch(run, 1, 1005)
		T.eq(res, "checkpoint", "CP1")
		T.near(info.time, 2, 1e-9, "Zeit ab Start")
		T.eq((TR.Touch(run, 1, 1005.5)), "ignored", "CP1 doppelt")
		T.eq((TR.Touch(run, 2, 1005 + mins[2] * 0.5)), "tooFast", "Teleport erkannt")
		run = TR.NewRun(mins, 1000)
		TR.Touch(run, 1, 1005)
		TR.Touch(run, 2, 1009)
		local fin, finfo = TR.Touch(run, 3, 1013)
		T.eq(fin, "finish", "Ziel")
		T.near(finfo.time, 10, 1e-9, "Rundenzeit")
		-- zu kurze Runde insgesamt
		local short = TR.NewRun({ 0.5 }, 0, 0)
		T.eq((TR.Touch(short, 1, c.minLapSeconds - 1)), "tooFast", "Mindestrundenzeit")
		-- Belohnung
		-- Zeiten relativ zur Basiszeit (Verbesserungen zählen nur darunter)
		local B = c.baselineSeconds
		T.check(B > 12 and c.perSecond * (B - 1) > c.maxReward, "Konfiguration: Deckel erreichbar")
		local track = TR.Default()
		local r1 = TR.Complete(track, B - 1, 1)
		T.eq(r1.reward, c.firstReward, "erste Runde")
		T.eq(track.best, B - 1, "Bestzeit")
		T.eq(track.runs, 1, "Läufe")
		local r2 = TR.Complete(track, B + 4, 1)
		T.eq(r2.reward, 0, "langsamer: nichts")
		T.eq(track.best, B - 1, "Bestzeit bleibt")
		local r3 = TR.Complete(track, B - 1.01, 1)
		T.eq(r3.reward, 0, "unter der Mindestverbesserung: nichts")
		local r4 = TR.Complete(track, B - 6, 1)
		T.eq(r4.reward, math.floor(math.min(c.maxReward, c.perSecond * 5) + 0.5), "je Sekunde Verbesserung")
		T.check(r4.newBest and r4.xp > 0, "neue Bestzeit gibt XP")
		local track5 = TR.Default()
		TR.Complete(track5, B, 1)
		local r5 = TR.Complete(track5, 1, 1)
		T.eq(r5.reward, c.maxReward, "gedeckelt")
		T.eq(track5.rewardedBest, 1, "belohnte Bestzeit")
		-- langsame erste Runde bringt kein Polster
		local t2 = TR.Default()
		TR.Complete(t2, 500, 1)
		T.eq(TR.Complete(t2, 100, 1).reward, 0, "Verbesserung oberhalb der Basiszeit bringt nichts")
		T.eq(TR.Complete(t2, c.baselineSeconds - 2, 1).reward, math.floor(c.perSecond * 2 + 0.5), "erst unterhalb der Basiszeit")
		T.check(TR.Reward(TR.Default(), 30, 21) > c.firstReward, "Level-Bonus")
	end },

	---------------------------------------------------------------- Fahrzeugbau
	{ "VehicleFactory: alle Karosserien fahrbar aufgebaut (Chassis, Schweißnähte, Räder, Federung, Sitz)", function(T, H)
		local g = H.Garage({ noServer = true })
		g:Activate()
		local CC, CR = modules(g)
		local VF = g:MiniServer("VehicleFactory")
		local P = CC.Physics
		local models = {}
		for _, m in ipairs(CC.Models) do
			if not models[m.body] then
				models[m.body] = m
			end
		end
		local bodies = 0
		for body, m in pairs(models) do
			bodies += 1
			local car = CR.NewCar(m.id, 0)
			car.id = 7
			local stats = CR.Stats(car)
			local target = CFrame.new(120, 0, 40) * CFrame.Angles(0, math.rad(30), 0)
			local model, err = VF.Build({ body = body, car = car, stats = stats, name = "Test_" .. body, ownerId = 5,
				carId = 7, modelId = m.id, cframe = target, plate = "UCG · 07" })
			if not T.check(model ~= nil, "gebaut: " .. body .. " " .. tostring(err)) then
				continue
			end
			local tag = " (" .. body .. ")"
			T.check((model.PrimaryPart.Position - target.Position).Magnitude < 1e-6, "Root am Ziel" .. tag)
			local chassis = model:FindFirstChild("Chassis")
			T.check(chassis and chassis:IsA("BasePart"), "Chassis" .. tag)
			T.eq(chassis.Transparency, 1, "Chassis unsichtbar" .. tag)
			T.eq(chassis.CanCollide, true, "Chassis = Kollisionsrumpf" .. tag)
			T.eq(chassis.Massless, false, "Chassis trägt die Masse" .. tag)
			local pp = chassis.CustomPhysicalProperties
			local mass = pp.Density * chassis.Size.X * chassis.Size.Y * chassis.Size.Z
			T.near(mass, stats.mass, 0.01, "Chassis-Masse aus dem Gewicht" .. tag)
			T.check(model:FindFirstChild("Underbody") ~= nil, "Vorlagen-Chassis umbenannt" .. tag)
			T.eq(model:FindFirstChild("DiagnosticPoint"), nil, "Werkstatt-Arbeitspunkte entfernt" .. tag)
			-- Schweißnähte
			local welded = {}
			for _, w in ipairs(model:GetDescendants()) do
				if w:IsA("WeldConstraint") then
					welded[w.Part1] = w.Part0
					T.check(w.Part0 and w.Part1 and w.Part0:IsDescendantOf(model) and w.Part1:IsDescendantOf(model), "Naht im Modell" .. tag)
				end
			end
			local physical = { Chassis = true }
			for _, c in ipairs(VF.Corners) do
				physical["Wheel_" .. c] = true
				physical["Knuckle_" .. c] = true
			end
			local unwelded, anchored, collide, heavy = 0, 0, 0, 0
			for _, x in ipairs(model:GetDescendants()) do
				if x:IsA("BasePart") then
					if x.Anchored then
						anchored += 1
					end
					if not physical[x.Name] then
						local to = welded[x]
						if not to or not (to == chassis or physical[to.Name]) then
							unwelded += 1
						end
						if x.CanCollide then
							collide += 1
						end
						if not x.Massless then
							heavy += 1
						end
					end
				end
			end
			T.eq(anchored, 0, "alles unverankert" .. tag)
			T.eq(unwelded, 0, "jedes Karosserieteil verschweißt" .. tag)
			T.eq(collide, 0, "Zierteile ohne Kollision" .. tag)
			T.eq(heavy, 0, "Zierteile Massless" .. tag)
			-- Räder und Aufhängung
			local drive = model:FindFirstChild("Drive")
			T.check(drive ~= nil, "Drive-Ordner" .. tag)
			local chassisUp = chassis.CFrame.UpVector
			local chassisLeft = -chassis.CFrame.RightVector
			for _, c in ipairs(VF.Corners) do
				local wheel = model:FindFirstChild("Wheel_" .. c)
				T.check(wheel and wheel.Shape == Enum.PartType.Cylinder, "Rad " .. c .. tag)
				T.eq(wheel.CanCollide, true, "Rad kollidiert " .. c .. tag)
				T.near(wheel.CustomPhysicalProperties.Friction, stats.grip, 1e-9, "Grip = Reibung " .. c .. tag)
				T.eq(wheel.CustomPhysicalProperties.FrictionWeight, 100, "Reifen-Reibung dominiert " .. c .. tag)
				local tire = model:FindFirstChild("Wheel" .. c .. "Tire")
				T.check(tire and welded[tire] == wheel, "Reifen am Rad verschweißt " .. c .. tag)
				local axle = drive:FindFirstChild("Axle_" .. c)
				T.check(axle and axle.ClassName == "CylindricalConstraint", "Achse " .. c .. tag)
				local base = (c == "FL" or c == "FR") and model:FindFirstChild("Knuckle_" .. c) or chassis
				T.eq(axle.Attachment0.Parent, base, "Achse sitzt am Achsschenkel/Chassis " .. c .. tag)
				T.eq(axle.Attachment1.Parent, wheel, "Achse am Rad " .. c .. tag)
				T.eq(axle.InclinationAngle, 90, "Drehachse quer " .. c .. tag)
				T.check(axle.LimitsEnabled and axle.LowerLimit < 0 and axle.UpperLimit > 0, "Federweg begrenzt " .. c .. tag)
				T.eq(axle.AngularActuatorType, Enum.ActuatorType.Motor, "Winkel-Motor " .. c .. tag)
				T.near(axle.MotorMaxTorque, model:GetAttribute("ParkTorque"), 1e-6, "Parkbremse " .. c .. tag)
				local w0, w1 = axle.Attachment0.WorldCFrame, axle.Attachment1.WorldCFrame
				T.check((w0.Position - w1.Position).Magnitude < 1e-6 and w0.RightVector:Dot(w1.RightVector) > 0.9999
					and w0.UpVector:Dot(w1.UpVector) > 0.9999, "Achs-Attachments deckungsgleich " .. c .. tag)
				T.check(w0.RightVector:Dot(chassisUp) > 0.9999, "Gleitachse senkrecht " .. c .. tag)
				T.check(w0.UpVector:Dot(chassisLeft) > 0.9999, "Drehachse nach links (positiv = vorwärts) " .. c .. tag)
				T.check((w0.Position - wheel.Position).Magnitude < 1e-6, "Achse in Radmitte " .. c .. tag)
				local spring = drive:FindFirstChild("Spring_" .. c)
				T.check(spring and spring.ClassName == "SpringConstraint", "Feder " .. c .. tag)
				T.eq(spring.Attachment0.Parent, chassis, "Feder oben am Chassis " .. c .. tag)
				T.eq(spring.Attachment1.Parent, wheel, "Feder unten am Rad " .. c .. tag)
				T.check(spring.Stiffness > 0 and spring.Damping > 0 and spring.FreeLength > P.springLength, "Feder vorgespannt " .. c .. tag)
				local nc = drive:FindFirstChild("NoCollide_" .. c)
				T.check(nc and nc.Part0 == wheel and nc.Part1 == chassis, "Rad kollidiert nicht mit dem Rumpf " .. c .. tag)
				if c == "FL" or c == "FR" then
					local steer = drive:FindFirstChild("Steer_" .. c)
					T.check(steer and steer.ClassName == "HingeConstraint", "Lenkung " .. c .. tag)
					T.eq(steer.ActuatorType, Enum.ActuatorType.Servo, "Servo " .. c .. tag)
					T.eq(steer.Attachment0.Parent, chassis, "Lenkung am Chassis " .. c .. tag)
					T.eq(steer.Attachment1.Parent, base, "Lenkung am Achsschenkel " .. c .. tag)
					T.check(steer.Attachment0.WorldCFrame.RightVector:Dot(chassisUp) < -0.9999, "Lenkachse nach unten (positiv = rechts) " .. c .. tag)
					T.check(steer.UpperAngle > stats.steerAngle, "Lenkanschlag " .. c .. tag)
				end
			end
			-- Sitz
			local seat = model:FindFirstChild("DriverSeat")
			T.check(seat and seat.ClassName == "VehicleSeat", "VehicleSeat" .. tag)
			T.eq(welded[seat], chassis, "Sitz am Chassis" .. tag)
			T.check(chassis.CFrame:PointToObjectSpace(seat.Position).X < 0, "Fahrersitz links" .. tag)
			T.near(seat.MaxSpeed, stats.topSpeedStuds, 1e-9, "MaxSpeed" .. tag)
			T.check(seat:FindFirstChild("EnterPrompt") and seat.EnterPrompt.ActionText == "Einsteigen", "Einsteigen-Prompt" .. tag)
			-- Attribute für DriveClient
			T.eq(model:GetAttribute("OwnerId"), 5, "OwnerId" .. tag)
			T.eq(model:GetAttribute("CarId"), 7, "CarId" .. tag)
			T.check(model:GetAttribute("Torque") > 0 and model:GetAttribute("BrakeTorque") > 0, "Momente" .. tag)
			T.near(model:GetAttribute("WheelRadius"), 1.3, 1e-6, "Radradius" .. tag)
			T.eq(model:GetAttribute("DriveWheels"), table.concat(VF.DriveWheels(stats.drive), ","), "Antriebsräder" .. tag)
			T.eq(model:GetAttribute("DriveSign"), 1, "DriveSign" .. tag)
			-- Optik
			local glow = model:FindFirstChild("Underglow")
			T.check(glow and glow.Material == Enum.Material.Neon, "Unterboden-Neon" .. tag)
			T.eq(glow.UnderglowLight.Enabled, false, "Licht aus bei glow 0" .. tag)
			local spoilers = 0
			for _, x in ipairs(model:GetDescendants()) do
				if (x.Name == "Spoiler" or x.Name == "RoofSpoiler") and x:IsA("BasePart") then
					spoilers += 1
					T.eq(x.Transparency, car.spoiler and 0 or 1, "Spoiler sichtbar wie gewählt" .. tag)
				end
			end
			T.check(spoilers >= 1, "Spoiler vorhanden (Vorlage oder nachgerüstet)" .. tag)
			local style = { paint = 6, rims = 3, glow = 4, spoiler = not car.spoiler }
			VF.ApplyStyle(model, style, true)
			local paint = CC.PaintColor(6)
			for _, x in ipairs(model:GetDescendants()) do
				if x:IsA("BasePart") and (x.Name == "Paint" or x.Name == "Hood" or x.Name == "Mirror") then
					T.check(x.Color == paint, "Lack übernommen " .. x.Name .. tag)
					T.check(x.Reflectance >= CC.Carwash.reflectance, "Glanz" .. tag)
				end
				if x:IsA("BasePart") and (x.Name == "Spoiler" or x.Name == "RoofSpoiler") then
					T.eq(x.Transparency, style.spoiler and 0 or 1, "Spoiler umgeschaltet" .. tag)
				end
			end
			T.check(model:FindFirstChild("WheelRLRim").Color == CC.RimColor(3), "Felgenfarbe" .. tag)
			T.eq(glow.Transparency, 0, "Unterboden an" .. tag)
			T.eq(glow.UnderglowLight.Enabled, true, "Licht an" .. tag)
			model:Destroy()
		end
		T.eq(bodies, 9, "alle neun Karosserien gebaut")
		T.eq(VF.Build({ body = "gibtsnicht" }), nil, "fehlende Vorlage -> nil")
		-- Keine Asset-IDs in den Auto-Modulen
		for _, f in ipairs({ "src/mini/server/VehicleFactory.lua", "src/mini/server/CarService.lua", "src/mini/shared/CarCatalog.lua" }) do
			local src = readfile(H.ROOT .. "/" .. f)
			T.check(not src:find("rbxassetid", 1, true), "keine Asset-IDs: " .. f)
		end
	end },

	{ "Fahrwerte: Tuning wirkt sofort auf Masse, Federn, Momente und Tacho-Attribute", function(T, H)
		local g = H.Garage({ noServer = true })
		g:Activate()
		local _, CR = modules(g)
		local VF = g:MiniServer("VehicleFactory")
		local car = CR.NewCar("vektor", 0)
		local model = VF.Build({ body = "sport", car = car, stats = CR.Stats(car), name = "T" })
		local maxSpeed, torque = model:GetAttribute("MaxSpeed"), model:GetAttribute("Torque")
		local stiff = model.Drive.Spring_RL.Stiffness
		local park = model.Drive.Axle_RL.MotorMaxTorque
		car.engine, car.gearbox, car.suspension, car.tires, car.nitro = 5, 5, 5, 5, 2
		VF.ApplyStats(model, CR.Stats(car))
		T.check(model:GetAttribute("MaxSpeed") > maxSpeed, "Höchstgeschwindigkeit steigt")
		T.check(model:GetAttribute("Torque") > torque, "Drehmoment steigt")
		T.check(model.Drive.Spring_RL.Stiffness > stiff, "Federn straffer")
		T.eq(model.Drive.Axle_RL.MotorMaxTorque, park, "Achs-Motoren gehören dem Fahrer-Client (unverändert)")
		T.eq(model:GetAttribute("NitroLevel"), 2, "Nitro-Stufe")
		T.check(model:GetAttribute("NitroBoost") > 1, "Nitro-Schub")
		T.near(model.Wheel_FL.CustomPhysicalProperties.Friction, CR.Stats(car).grip, 1e-9, "Grip")
		model:Destroy()
	end },

	---------------------------------------------------------------- CarService im echten Server
	{ "CarService: kaufen, holen (Rückfall Werkstatt), Sitzschutz, abstellen, Respawn räumt ab", function(T, H)
		local S = setup(H)
		local g = S.g
		local pl = S.join(601, "Alex")
		removeGenerated(g, { "CarSpawns" })
		local d = g:D(pl)
		d.money = 100000
		d.level = 5
		S.act(pl, "mini_car_buy", { model = "komet" })
		T.eq(#d.games.cars, 1, "gekauft")
		S.act(pl, "mini_car_buy", { model = "komet" })
		T.eq(#d.games.cars, 1, "Doppelklick kauft nicht doppelt")
		T.check(S.hasToast(pl, "gekauft"), "Kauf-Hinweis")
		local id = d.games.cars[1].id
		S.act(pl, "mini_car_spawn", { id = id, at = "../../x" })
		T.eq(S.car(pl), nil, "ungültiger Stellplatz")
		S.act(pl, "mini_car_spawn", { id = 999, at = "workshop" })
		T.eq(S.car(pl), nil, "fremdes Auto nicht holbar")
		S.act(pl, "mini_car_spawn", { id = id, at = "dealer" })
		local model = S.car(pl)
		T.check(model ~= nil, "Auto unter workspace.PlayerCars")
		T.eq(model:GetAttribute("OwnerId"), 601, "Besitzer")
		T.eq(#S.notices(pl, "car_spawned"), 1, "car_spawned")
		-- ohne City.CarSpawns: Rückfall auf den eigenen Werkstatt-Parkplatz
		local plot = g:Plot(pl)
		local here = plot:GetPivot():PointToObjectSpace(model:GetPivot().Position)
		T.check(math.abs(here.X) < 40 and here.Z > 30 and here.Z < 90, "vor der eigenen Werkstatt (plotlokal " .. tostring(here) .. ")")
		local plotSpot = plot:FindFirstChild("CarSpawn", true)
		T.check(plotSpot ~= nil, "Plot-Vorlage hat einen Parkplatz CarSpawn")
		if plotSpot then
			local dx = model:GetPivot().Position - plotSpot.Position
			T.check(Vector3.new(dx.X, 0, dx.Z).Magnitude < 1, "genau auf Werkstatt.CarSpawn")
			T.check(model:GetPivot().LookVector:Dot(plotSpot.CFrame.LookVector) > 0.99, "Nase wie CarSpawn")
		end
		local snap = S.CS.SnapshotFields(g:MiniState(pl), d, g:Now())
		T.eq(snap.spawnedCar, true, "Snapshot: Auto draußen")
		T.eq(snap.spawnedId, id, "Snapshot: Id")
		T.eq(#snap.cars, 1, "Snapshot: cars")
		T.check(snap.cars[1].stats and snap.cars[1].tune and snap.cars[1].styleCost, "Snapshot: Werte, Tuning, Optikpreise")
		T.check(#snap.catalog == 9, "Snapshot: Katalog")
		-- Sitzschutz
		local other = S.join(602, "Bea")
		S.sit(pl, model, other)
		T.eq(S.humanoid(other).Sit, false, "fremder Insasse fliegt raus")
		T.check(S.hasToast(other, "nicht dein Auto"), "Hinweis an den Fremden")
		local seat = model.DriverSeat
		seat.Occupant = nil
		g:Flush()
		g:Trigger(other, seat.EnterPrompt, { force = true })
		T.check(#S.log.toasts > 0 and S.hasToast(other, "nicht dein Auto"), "Prompt für Fremde gesperrt")
		S.sit(pl, model)
		local v = S.CS.States[pl].car
		T.eq(v.occupied, true, "Besitzer sitzt")
		T.eq(seat.EnterPrompt.Enabled, false, "Prompt aus, solange besetzt")
		seat.Occupant = nil
		g:Flush()
		T.eq(v.occupied, false, "ausgestiegen")
		-- erneutes Holen ersetzt das Auto (max. 1)
		g:Advance(3.1)
		S.act(pl, "mini_car_spawn", { id = id, at = "workshop" })
		T.eq(countOwned(S, pl), 1, "höchstens ein eigenes Auto")
		T.check(S.car(pl) ~= model and model.Parent == nil, "altes Auto abgebaut")
		-- Probefahrt zusätzlich: 1 Auto + 1 Probefahrt
		S.act(pl, "mini_car_testdrive", { model = "vektor" })
		T.eq(countOwned(S, pl), 2, "Auto + Probefahrt")
		T.check(S.car(pl, "Probe_") ~= nil, "Probefahrt-Modell")
		-- Abstellen
		S.act(pl, "mini_car_despawn")
		T.eq(S.car(pl), nil, "abgestellt")
		T.eq(#S.notices(pl, "car_despawned"), 2, "car_despawned (ersetzt + abgestellt)")
		S.act(pl, "mini_car_despawn")
		T.check(S.hasToast(pl, "kein Auto draußen"), "nichts abzustellen")
		-- Respawn/Tod räumt ab
		g:Advance(3.1)
		S.act(pl, "mini_car_spawn", { id = id, at = "workshop" })
		T.check(S.car(pl) ~= nil, "wieder draußen")
		g:Respawn(pl)
		g:Advance(0.5)
		T.eq(S.car(pl), nil, "Respawn baut das Auto ab")
		T.eq(S.car(pl, "Probe_"), nil, "und die Probefahrt")
		T.eq(countOwned(S, pl), 0, "nichts mehr draußen")
		-- ohne CarSpawn in der Plot-Vorlage: Einfahrt vor der Halle (Physics.plotFallback)
		removePlotSpawn(g, pl)
		g:Advance(3.1)
		S.act(pl, "mini_car_spawn", { id = id, at = "workshop" })
		model = S.car(pl)
		T.check(model ~= nil, "Rückfall ohne CarSpawn")
		if model then
			local f = g:MiniShared("CarCatalog").Physics.plotFallback
			local local2 = plot:GetPivot():PointToObjectSpace(model:GetPivot().Position)
			T.check(math.abs(local2.X - f[1]) < 12 and math.abs(local2.Z - f[3]) < 1, "Einfahrt plotlokal " .. tostring(local2))
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "CarService: Spawnpunkt aus City.CarSpawns, Probefahrt endet nach 60 s", function(T, H)
		local S = setup(H)
		local g = S.g
		local pl = S.join(611, "Cem")
		removeGenerated(g, { "CarSpawns" })
		g:Activate()
		local city = g.env.workspace:FindFirstChild("City")
		local spawns = Instance.new("Folder")
		spawns.Name = "CarSpawns"
		spawns.Parent = city
		local sp = Instance.new("Part")
		sp.Name = "testdrive"
		sp.Anchored = true
		sp.CanCollide = false
		sp.Transparency = 1
		sp.Size = Vector3.new(2, 1, 2)
		sp.CFrame = CFrame.lookAt(Vector3.new(90, 0, 60), Vector3.new(90, 0, 100))
		sp.Parent = spawns
		S.act(pl, "mini_car_testdrive", { model = "gibtsnicht" })
		T.eq(S.car(pl, "Probe_"), nil, "unbekanntes Modell")
		S.act(pl, "mini_car_testdrive", { model = "aureon" })
		local model = S.car(pl, "Probe_")
		T.check(model ~= nil, "Probefahrt auch über dem eigenen Level")
		T.check((model:GetPivot().Position - Vector3.new(90, 0, 60)).Magnitude < 2, "am Spawnpunkt testdrive")
		T.check(model:GetPivot().LookVector:Dot(Vector3.new(0, 0, 1)) > 0.99, "Nase in Spawn-Richtung")
		T.eq(model:GetAttribute("Testdrive"), true, "als Probefahrt markiert")
		local n = S.notices(pl, "car_spawned")[1]
		T.check(n and n.testdrive == true and n.endsAt and math.abs(n.endsAt - (g:Now() + 60)) < 0.01, "Ende in 60 s")
		T.eq(model:GetAttribute("TestdriveEnds"), n.endsAt, "Ende als Attribut")
		S.act(pl, "mini_car_testdrive", { model = "komet" })
		T.check(S.hasToast(pl, "nächste Probefahrt"), "Abklingzeit")
		S.sit(pl, model)
		g:Advance(59)
		S.tick(pl)
		T.check(S.car(pl, "Probe_") ~= nil, "nach 59 s noch da")
		g:Advance(1.5)
		S.tick(pl)
		T.eq(S.car(pl, "Probe_"), nil, "nach 60 s weg")
		local ends = S.notices(pl, "testdrive_end")
		T.eq(#ends, 1, "testdrive_end")
		T.eq(ends[1].reason, "time", "Grund: Zeit")
		local arrivals = city:FindFirstChild("Arrivals")
		local dealer = arrivals and arrivals:FindFirstChild("dealer")
		if dealer then
			local root = pl.Character.HumanoidRootPart
			T.check((root.Position - dealer.Position).Magnitude < 6, "Fahrer zurück am Autohaus")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "CarService: Tuning und Optik sofort am Auto, gesperrte Autos, Nitro, Waschstraße", function(T, H)
		local S = setup(H)
		local g = S.g
		local pl = S.join(621, "Dana")
		local d = g:D(pl)
		d.money = 1e6
		d.level = 20
		S.act(pl, "mini_car_buy", { model = "komet" })
		local car = d.games.cars[1]
		S.act(pl, "mini_car_spawn", { id = car.id, at = "workshop" })
		local model = S.car(pl)
		local top = model:GetAttribute("MaxSpeed")
		S.act(pl, "mini_car_tune", { id = car.id, part = "engine", level = 0 })
		T.eq(car.engine, 1, "Motor 1")
		T.check(model:GetAttribute("MaxSpeed") > top, "sofort schneller")
		local money = d.money
		S.act(pl, "mini_car_tune", { id = car.id, part = "engine", level = 0 })
		T.eq(car.engine, 1, "veraltete Stufe: kein zweites Tuning")
		T.eq(d.money, money, "und keine Kosten")
		S.act(pl, "mini_car_style", { id = car.id, paint = 6, rims = 2, glow = 3, spoiler = true })
		T.eq(car.paint, 6, "Lack gespeichert")
		T.check(model.Hood.Color == g:MiniShared("CarCatalog").PaintColor(6), "sofort umlackiert")
		T.eq(model.Underglow.UnderglowLight.Enabled, true, "Unterbodenlicht an")
		money = d.money
		S.act(pl, "mini_car_style", { id = car.id, paint = 6, rims = 2, glow = 3, spoiler = true })
		T.eq(d.money, money, "gleiche Optik kostet nichts")
		-- Nitro
		S.act(pl, "mini_car_nitro")
		T.check(S.hasToast(pl, "während der Fahrt"), "Nitro nur am Steuer")
		S.sit(pl, model)
		S.act(pl, "mini_car_nitro")
		T.check(S.hasToast(pl, "kein Nitro"), "ohne Nitro-Tuning kein Nitro")
		for l = 0, 1 do
			S.act(pl, "mini_car_tune", { id = car.id, part = "nitro", level = l })
		end
		T.eq(car.nitro, 2, "Nitro 2")
		S.act(pl, "mini_car_nitro")
		local untilAt = model:GetAttribute("NitroUntil")
		T.check(untilAt > g:Now(), "Nitro aktiv")
		T.eq(model.Chassis.Exhaust.NitroFlame.Enabled, true, "Flamme an")
		local ready = model:GetAttribute("NitroReadyAt")
		S.act(pl, "mini_car_nitro")
		T.eq(model:GetAttribute("NitroReadyAt"), ready, "Abklingzeit: kein zweiter Schub")
		g:Advance(3)
		T.eq(model.Chassis.Exhaust.NitroFlame.Enabled, false, "Flamme aus nach Ablauf")
		T.eq(#S.notices(pl, "car_nitro"), 1, "car_nitro einmal")
		-- Waschstraße (ohne Waschstraßen-Anker keine Reichweitenprüfung)
		local city = g.env.workspace:FindFirstChild("City")
		local st = city and city:FindFirstChild("Stations")
		local anchor = st and st:FindFirstChild("carwash")
		if anchor then
			S.act(pl, "mini_carwash")
			T.check(S.hasToast(pl, "Waschstraße"), "Auto zu weit weg von der Waschstraße")
			g:Activate()
			model:PivotTo(CFrame.new(anchor.Position + Vector3.new(0, 0, 10)))
		end
		money = d.money
		S.act(pl, "mini_carwash")
		T.eq(d.money, money - g:MiniShared("CarCatalog").Carwash.price, "Wäsche bezahlt")
		T.eq(model:GetAttribute("Shine"), true, "Glanz")
		S.act(pl, "mini_carwash")
		T.eq(d.money, money - g:MiniShared("CarCatalog").Carwash.price, "Abklingzeit: nicht doppelt bezahlt")
		-- gesperrt (Auktion)
		local CR = g:MiniShared("CarRules")
		CR.SetLocked(d, car.id, true)
		g:Advance(3.1)
		S.act(pl, "mini_car_spawn", { id = car.id, at = "workshop" })
		T.check(S.hasToast(pl, "Auktion"), "gesperrtes Auto nicht holbar")
		S.act(pl, "mini_car_sell", { id = car.id })
		T.eq(#d.games.cars, 1, "gesperrtes Auto nicht verkaufbar")
		T.check(S.car(pl) ~= nil, "Auto bleibt draußen")
		CR.SetLocked(d, car.id, false)
		money = d.money
		S.act(pl, "mini_car_sell", { id = car.id })
		T.eq(#d.games.cars, 0, "verkauft")
		T.eq(S.car(pl), nil, "verkauftes Auto verschwindet")
		T.check(d.money > money, "Erlös")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "CarService: Zeitfahren mit Checkpoints, Serverzeit, Belohnung nur für Bestzeit, transacting", function(T, H)
		local S = setup(H)
		local g = S.g
		local pl = S.join(631, "Emil")
		removeGenerated(g, { "CarSpawns", "Track" })
		local d = g:D(pl)
		d.money = 100000
		d.level = 1
		S.act(pl, "mini_track_start")
		T.check(S.hasToast(pl, "Teststrecke"), "ohne Strecke kein Zeitfahren")
		g:Activate()
		local city = g.env.workspace:FindFirstChild("City")
		local track = Instance.new("Folder")
		track.Name = "Track"
		track.Parent = city
		local cps = Instance.new("Folder")
		cps.Name = "Checkpoints"
		cps.Parent = track
		local function trigger(name, z, parent)
			local p = Instance.new("Part")
			p.Name = name
			p.Anchored = true
			p.CanCollide = false
			p.Transparency = 1
			p.Size = Vector3.new(24, 10, 4)
			p.CFrame = CFrame.new(0, 4, z)
			p.Parent = parent
			return p
		end
		local list = { trigger("CP1", 1200, cps), trigger("CP2", 1400, cps), trigger("CP3", 1600, cps) }
		local ziel = trigger("Ziel", 1800, track)
		table.insert(list, ziel)
		local spawns = Instance.new("Folder")
		spawns.Name = "CarSpawns"
		spawns.Parent = city
		local sp = trigger("track", 1100, spawns)
		sp.CFrame = CFrame.lookAt(Vector3.new(0, 0, 1100), Vector3.new(0, 0, 1200))
		T.eq(#S.CS.TrackSequence(), 4, "CP1..CP3 + Ziel")
		S.act(pl, "mini_track_start")
		T.check(S.hasToast(pl, "eigenes Auto"), "Zeitfahren braucht ein eigenes Auto")
		d.level = 8 -- Komet ab 3, Teststrecke ab 8 (GameConfig.Unlocks)
		S.act(pl, "mini_car_buy", { model = "komet" })
		g:Advance(0.1)
		S.act(pl, "mini_track_start")
		local model = S.car(pl)
		T.check(model ~= nil, "Auto an der Startlinie")
		T.check((model:GetPivot().Position - Vector3.new(0, 0, 1100)).Magnitude < 2, "am Spawnpunkt track")
		local start = S.notices(pl, "track_start")[1]
		T.check(start and math.abs(start.startAt - (g:Now() + 3)) < 1e-6 and start.total == 4, "track_start mit Startampel")
		local function drive(i)
			g:Activate()
			local part = list[i]
			model:PivotTo(CFrame.new(part.Position))
			part.Touched:Fire(model.Chassis)
			g:Flush()
		end
		S.sit(pl, model)
		drive(1)
		T.eq(#S.notices(pl, "track_abort"), 1, "Frühstart vor dem Startsignal")
		T.eq(S.notices(pl, "track_abort")[1].reason, "early", "Grund early")
		-- neuer Lauf
		g:Advance(3.1)
		S.act(pl, "mini_track_start")
		model = S.car(pl)
		S.sit(pl, model)
		g:Advance(3)
		g:Advance(2)
		-- Figur (nicht das Auto) zählt nicht
		g:Activate()
		list[1].Touched:Fire(pl.Character.HumanoidRootPart)
		g:Flush()
		T.eq(#S.notices(pl, "track_checkpoint"), 0, "Figur löst keinen Checkpoint aus")
		drive(2)
		T.eq(#S.notices(pl, "track_checkpoint"), 0, "Reihenfolge: CP2 vor CP1 zählt nicht")
		drive(1)
		T.eq(#S.notices(pl, "track_checkpoint"), 1, "CP1")
		g:Advance(0.05)
		drive(2)
		T.eq(S.notices(pl, "track_abort")[2].reason, "tooFast", "Teleport zu CP2 erkannt")
		-- sauberer Lauf: 8 s
		g:Advance(3.1)
		S.act(pl, "mini_track_start")
		model = S.car(pl)
		S.sit(pl, model)
		local startAt = S.notices(pl, "track_start")[3].startAt
		local money = d.money
		local changed = S.log.changed
		g:AdvanceTo(startAt + 2)
		drive(1)
		g:AdvanceTo(startAt + 4)
		drive(2)
		g:AdvanceTo(startAt + 6)
		drive(3)
		g:AdvanceTo(startAt + 8)
		drive(4)
		local fin = S.notices(pl, "track_finish")
		T.eq(#fin, 1, "track_finish")
		T.near(fin[1].time, 8, 1e-6, "Rundenzeit aus der Serverzeit")
		local c = g:MiniShared("CarCatalog").Track
		local bonus = 1 + c.levelBonus * (d.level - 1) -- Level-Bonus der Teststrecke (Level 8 wegen der Freischaltung)
		local first = math.floor(c.firstReward * bonus + 0.5)
		T.eq(fin[1].reward, first, "erste Runde belohnt")
		T.eq(d.money, money + first, "gutgeschrieben")
		T.check(S.log.changed > changed, "ctx.changed nach der Gutschrift")
		T.near(d.games.track.best, 8, 1e-6, "Bestzeit gespeichert")
		T.eq(d.games.track.runs, 1, "ein Lauf")
		-- langsamer: keine Belohnung
		g:Advance(3.1)
		S.act(pl, "mini_track_start")
		model = S.car(pl)
		S.sit(pl, model)
		startAt = S.notices(pl, "track_start")[4].startAt
		money = d.money
		for i = 1, 4 do
			g:AdvanceTo(startAt + 3 * i)
			drive(i)
		end
		T.eq(S.notices(pl, "track_finish")[2].reward, 0, "langsamer: keine Belohnung")
		T.eq(d.money, money, "Geld unverändert")
		T.near(d.games.track.best, 8, 1e-6, "Bestzeit bleibt")
		-- schneller während eines Robux-Kaufs (transacting): Gutschrift erst danach
		g:Advance(3.1)
		S.act(pl, "mini_track_start")
		model = S.car(pl)
		S.sit(pl, model)
		startAt = S.notices(pl, "track_start")[5].startAt
		money = d.money
		-- Abschnitte so schnell, wie ein Komet (Spitze × Reserve) es erlaubt: 100 Studs in 1 s, dann je 200 Studs in 2 s
		g:AdvanceTo(startAt + 1)
		drive(1)
		g:AdvanceTo(startAt + 3)
		drive(2)
		g:AdvanceTo(startAt + 5)
		drive(3)
		local profile = g:Profile(pl)
		profile.transacting = true
		g:AdvanceTo(startAt + 7)
		drive(4)
		local reward = S.notices(pl, "track_finish")[3].reward
		T.eq(reward, math.floor(c.perSecond * 1 * bonus + 0.5), "1 s schneller")
		T.eq(d.money, money, "während transacting kein Geld")
		S.tick(pl)
		T.eq(d.money, money, "auch im Tick nicht")
		profile.transacting = false
		S.tick(pl)
		T.check(d.money >= money + reward, "danach gutgeschrieben (plus evtl. Level-Bonus aus den XP)")
		-- Aussteigen bricht ab
		g:Advance(3.1)
		S.act(pl, "mini_track_start")
		model = S.car(pl)
		S.sit(pl, model)
		model.DriverSeat.Occupant = nil
		g:Flush()
		T.eq(S.notices(pl, "track_abort")[3].reason, "left", "Aussteigen bricht ab")
		-- Zeitlimit
		g:Advance(3.1)
		S.act(pl, "mini_track_start")
		g:Advance(c.maxRunSeconds + c.countdown + 1)
		S.tick(pl)
		local aborts = S.notices(pl, "track_abort")
		T.eq(aborts[#aborts].reason, "expired", "Zeitlimit")
		local snap = S.CS.SnapshotFields(g:MiniState(pl), d, g:Now())
		T.eq(snap.track.active, false, "Snapshot: kein Lauf")
		T.near(snap.track.best, 7, 1e-6, "Snapshot: Bestzeit")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "CarService: Verlassen baut alles ab, Leerlauf-Despawn, verlorenes Auto", function(T, H)
		local S = setup(H)
		local g = S.g
		local pl = S.join(641, "Finn")
		local d = g:D(pl)
		d.money = 100000
		d.level = 3
		S.act(pl, "mini_car_buy", { model = "komet" })
		local id = d.games.cars[1].id
		S.act(pl, "mini_car_spawn", { id = id, at = "workshop" })
		T.check(S.car(pl) ~= nil, "draußen")
		-- verloren (z. B. in die Tiefe gefallen)
		g:Activate()
		S.car(pl).Chassis:Destroy()
		S.tick(pl)
		T.eq(S.car(pl), nil, "verlorenes Auto wird aufgeräumt")
		T.eq(S.notices(pl, "car_despawned")[1].reason, "lost", "Grund lost")
		-- Auktions-Hook: eingeliefertes Auto verlässt die Straße
		g:Advance(3.1)
		S.act(pl, "mini_car_spawn", { id = id, at = "workshop" })
		T.eq(S.CS.SpawnedCarId(pl), id, "SpawnedCarId")
		T.eq(S.CS.ReleaseCar(pl, id + 1), false, "anderes Auto: nichts zu tun")
		T.eq(S.CS.ReleaseCar(pl, id), true, "ReleaseCar holt das Auto von der Straße")
		T.eq(S.car(pl), nil, "weg")
		T.eq(S.CS.SpawnedCarId(pl), 0, "kein Auto mehr draußen")
		-- Leerlauf
		g:Advance(3.1)
		S.act(pl, "mini_car_spawn", { id = id, at = "workshop" })
		g:Advance(g:MiniShared("CarCatalog").IdleDespawnSeconds + 1)
		S.tick(pl)
		T.eq(S.car(pl), nil, "unbenutztes Auto verschwindet")
		-- Verlassen
		S.act(pl, "mini_car_spawn", { id = id, at = "workshop" })
		S.act(pl, "mini_car_testdrive", { model = "nord" })
		T.eq(countOwned(S, pl), 2, "Auto + Probefahrt")
		g:Leave(pl)
		g:Advance(0.5)
		T.eq(countOwned(S, pl), 0, "beim Verlassen alles weg")
		T.eq(S.CS.States[pl], nil, "Zustand gelöscht")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Verkabelung (sobald MiniNet die Auto-Aktionen kennt): Kauf und Holen über Remotes.Command", function(T, H)
		local g = H.Garage()
		local MiniNet = g:MiniShared("MiniNet")
		if not MiniNet.Actions.mini_car_buy then
			T.check(true, "noch nicht verkabelt")
			return
		end
		local pl = g:Join(651, { name = "Gina" })
		g:Advance(0.5)
		local d = g:D(pl)
		d.money = 100000
		T.eq(g:Act(pl, "mini_car_buy", { model = "komet", rid = 0 }), "locked", "Komet erst ab Level 3 (Unlocks)")
		d.level = 3
		g:Advance(1.1)
		T.eq(g:Act(pl, "mini_car_buy", { model = "komet", rid = 1 }), "ok", "mini_car_buy")
		T.eq(#d.games.cars, 1, "gekauft")
		g:Advance(0.2)
		T.eq(g:Act(pl, "mini_car_spawn", { id = d.games.cars[1].id, at = "workshop", rid = 2 }), "ok", "mini_car_spawn")
		local folder = g.env.workspace:FindFirstChild("PlayerCars")
		T.check(folder and folder:FindFirstChild("Car_651") ~= nil, "Auto draußen")
		g:Advance(1)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and type(snap.cars) == "table" and #snap.cars == 1, "Snapshot enthält cars")
		T.eq(snap and snap.spawnedCar, true, "Snapshot: spawnedCar")
		T.check(snap and type(snap.track) == "table", "Snapshot: track")
		g:Leave(pl)
		g:Advance(0.5)
		T.check(folder:FindFirstChild("Car_651") == nil, "Verlassen räumt ab")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Sitzender Fahrer: Reise, Werkstatt und Probefahrt lösen die SeatWeld vor PivotTo (Auto bleibt stehen)", function(T, H)
		local g = H.Garage()
		local pl = g:Join(641, { name = "Fritz" })
		g:Advance(0.5)
		local d = g:D(pl)
		d.money = 200000
		d.level = 10
		T.eq(g:Act(pl, "mini_car_buy", { model = "komet" }), "ok", "kaufen")
		local id = d.games.cars[1].id
		T.eq(g:Act(pl, "mini_car_spawn", { id = id, at = "dealer" }), "ok", "holen")
		g:Activate()
		local model = g.env.workspace.PlayerCars:FindFirstChild("Car_641")
		T.check(model ~= nil, "Auto draußen")
		if not model then
			return
		end
		local seat = model.DriverSeat
		-- wie Roblox: Sitzen = SeatWeld (Part0 Sitz, Part1 HumanoidRootPart), Humanoid.SeatPart, Occupant.
		-- Humanoid.Sit = false löst die SeatWeld auf einem Live-Server NICHT sofort (der Mock ebenso).
		local function seatIn(target)
			g:Activate()
			local ch = pl.Character
			local hum = ch:FindFirstChildOfClass("Humanoid")
			local w = Instance.new("Weld")
			w.Name = "SeatWeld"
			w.Part0 = target
			w.Part1 = ch.HumanoidRootPart
			w.C0 = CFrame.new(0, 1.5, 0)
			w.Parent = target
			ch:PivotTo(target.CFrame * CFrame.new(0, 3, 0))
			hum.SeatPart = target
			hum.Sit = true
			target.Occupant = hum
			g:Flush()
			return w, hum
		end
		-- Gegenprobe: der Mock zieht das Auto mit, solange die SeatWeld besteht
		local w0 = seatIn(seat)
		local pivot0 = model:GetPivot()
		g:Activate()
		pl.Character:PivotTo(pl.Character:GetPivot() + Vector3.new(0, 0, 50))
		T.check((model:GetPivot().Position - pivot0.Position).Magnitude > 40, "Mock: SeatWeld verbindet Figur und Auto")
		model:PivotTo(pivot0)
		w0:Destroy()
		g:Flush()

		local function check(label, fn)
			local weld = seatIn(seat)
			local before = model:GetPivot()
			local status = fn()
			g:Activate()
			T.eq(status, "ok", label .. ": Aktion angenommen")
			T.eq(weld.Parent, nil, label .. ": SeatWeld zerstört")
			local moved = (model:GetPivot().Position - before.Position).Magnitude
			T.check(moved < 0.01, label .. ": Auto bleibt stehen (verschoben um " .. string.format("%.1f", moved) .. ")")
			T.check((pl.Character:GetPivot().Position - before.Position).Magnitude > 3, label .. ": Figur ist woanders")
			seat.Occupant = nil
			pl.Character:FindFirstChildOfClass("Humanoid").SeatPart = nil
			g:Flush()
			g:Advance(3.2)
		end
		local arrivals = g.env.workspace.City:FindFirstChild("Arrivals")
		local key
		for _, x in ipairs(arrivals and arrivals:GetChildren() or {}) do
			if (x:IsA("BasePart") or x:IsA("Model")) and x.Name ~= "dealer" then
				key = x.Name
				break
			end
		end
		T.check(key ~= nil, "Ankunftspunkt in der Stadt")
		check("Karte (CityService.Travel)", function()
			return g:Act(pl, "mini_travel", { key = key })
		end)
		check("Werkstatt (GarageServer.moveTo)", function()
			return g:Act(pl, "mini_travel", { key = "workshop" })
		end)
		check("Probefahrt aus dem eigenen Auto", function()
			return g:Act(pl, "mini_car_testdrive", { model = "nord" })
		end)
		local probe = g.env.workspace.PlayerCars:FindFirstChild("Probe_641")
		T.check(probe ~= nil, "Probewagen steht bereit")
		if probe then
			T.check((probe:GetPivot().Position - model:GetPivot().Position).Magnitude > 6, "eigenes Auto nicht in den Probewagen geschoben")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Zeitfahren: Plausibilität mit dem Tempo des gefahrenen Autos (Kompakt kann keine Supersportwagen-Runde)", function(T, H)
		local g = H.Garage({ noServer = true })
		local _, CarRules, TR = modules(g)
		local c = g:MiniShared("CarCatalog").Track
		local komet = CarRules.Stats(CarRules.NewCar("komet", NOW))
		local speed = TR.CarSpeed(komet)
		T.near(speed, komet.topSpeedStuds * komet.nitro.boost * c.speedMargin, 1e-6, "Spitze × Nitro × Reserve")
		T.check(speed < TR.MaxSpeed() * 0.6, "Komet deutlich langsamer als das schnellste Auto des Katalogs")
		-- Oval ~780 Studs: 4 Abschnitte à 195 Studs
		local points = { Vector3.new(0, 0, 195), Vector3.new(0, 0, 390), Vector3.new(0, 0, 585), Vector3.new(0, 0, 780) }
		local minLap = TR.MinLap(Vector3.new(0, 0, 0), points, speed)
		T.near(minLap, 780 / speed, 1e-6, "Mindestrunde = Strecke / Tempo")
		T.check(minLap > c.minLapSeconds + 1, "mehr als die feste Untergrenze")
		-- Teleport-Runde in 6,5 s: mit Katalog-Höchsttempo gültig, mit dem Komet nicht
		local function lap(maxSpeed, total)
			local run = TR.NewRun(TR.MinTimes(Vector3.new(0, 0, 0), points, maxSpeed), 0, 0, TR.MinLap(Vector3.new(0, 0, 0), points, maxSpeed), maxSpeed)
			local res
			for i = 1, 4 do
				res = TR.Touch(run, i, total * i / 4)
				if res ~= "checkpoint" then
					break
				end
			end
			return res, run
		end
		T.eq((lap(TR.MaxSpeed(), 6.5)), "finish", "alte Prüfung (Katalog) hätte 6,5 s angenommen")
		T.eq((lap(speed, 6.5)), "tooFast", "Komet: 6,5 s als Teleport erkannt")
		T.eq((lap(speed, minLap + 0.5)), "finish", "ehrliche Runde des Komet gültig")
		-- Tuning während des Laufs macht das Auto schneller: offene Abschnitte werden angepasst, nie verlängert
		local run = TR.NewRun(TR.MinTimes(Vector3.new(0, 0, 0), points, speed), 0, 0, minLap, speed)
		local before = run.minTimes[3]
		T.eq(TR.Rescale(run, speed * 0.5), false, "langsamer: keine Änderung")
		T.eq(TR.Rescale(run, speed * 1.25), true, "schneller: angepasst")
		T.near(run.minTimes[3], math.max(c.segmentFloor, before / 1.25), 1e-6, "Abschnitt kürzer")
		T.near(run.minLap, math.max(c.minLapSeconds, minLap / 1.25), 1e-6, "Runde kürzer")
	end },

	{ "CarService: mini_track_start nutzt das Tempo des gespawnten Autos", function(T, H)
		local S = setup(H)
		local g = S.g
		local pl = S.join(651, "Gerd")
		local d = g:D(pl)
		d.money = 100000
		d.level = 8
		S.act(pl, "mini_car_buy", { model = "komet" })
		g:Advance(0.1)
		S.act(pl, "mini_track_start")
		local run = S.CS.States[pl].run
		T.check(run ~= nil, "Lauf gestartet")
		if run then
			local _, CarRules, TR = modules(g)
			local speed = TR.CarSpeed(CarRules.Stats(d.games.cars[1]))
			T.near(run.maxSpeed, speed, 1e-6, "Höchsttempo des Komet")
			T.check(run.minLap >= g:MiniShared("CarCatalog").Track.minLapSeconds, "Mindestrunde gesetzt")
			-- Motor-Tuning während des Laufs: Mindestzeiten passen sich an
			d.money = 1e7
			d.level = 50
			local lvl = d.games.cars[1].engine
			S.act(pl, "mini_car_tune", { id = d.games.cars[1].id, part = "engine", level = lvl })
			T.check(run.maxSpeed > speed, "schnelleres Auto: Lauf angepasst")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
