-- Ausbaustufen 2 und 3 Ende-zu-Ende im echten Server (H.Garage, echte Verkabelung über Remotes.Command,
-- generierte Stadt aus der Fixture): Autos kaufen/holen/tunen/abstellen, Probefahrt, Zeitfahren auf der echten
-- Teststrecke, NPC- und Spieler-Auktionen, Spielhalle mit Tageslimit, Credit-Center, Speichern/Laden, Veteranen.
local NOW = 1760000000

---------------------------------------------------------------- Hilfen
local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, (what or "keine Laufzeitfehler") .. ": " .. g:ErrorText())
	for _, w in ipairs(g:Warnings()) do
		local text = tostring(w)
		T.check(not text:find("[Minispiele]", 1, true) and not text:find("[Autos]", 1, true)
			and not text:find("[Auktion]", 1, true), "Warnung: " .. text)
	end
end

local function join(g, userId, name)
	local pl = g:Join(userId, { name = name })
	g:Advance(0.5)
	g:Send(pl, "hello")
	g:Advance(0.5)
	return pl, g:D(pl)
end

local rid = 0
local function act(g, pl, action, payload)
	rid += 1
	payload = payload or {}
	payload.rid = rid
	return g:Act(pl, action, payload)
end

local function car(g, pl, prefix)
	local folder = g.env.workspace:FindFirstChild("PlayerCars")
	return folder and folder:FindFirstChild((prefix or "Car_") .. pl.UserId)
end

local function sit(g, pl, model)
	g:Activate()
	local humanoid = pl.Character and pl.Character:FindFirstChildOfClass("Humanoid")
	model.DriverSeat.Occupant = humanoid
	g:Flush()
end

local function horizontal(a, b)
	local d = a - b
	return Vector3.new(d.X, 0, d.Z).Magnitude
end

local function cityPart(g, path)
	return g:Find("Workspace.City." .. path)
end

-- Fährt die echte Teststrecke ab (City.Track: CP1..CPn, Ziel). secondsPerSection: Zeit je Abschnitt
local function driveLap(g, CS, model, secondsPerSection)
	local list = CS.TrackSequence()
	for _, part in ipairs(list) do
		g:Advance(secondsPerSection)
		g:Activate()
		model:PivotTo(CFrame.new(part.Position))
		part.Touched:Fire(model.Chassis)
		g:Flush()
	end
	return list
end

local function lotOf(AS, kind, state)
	local found
	for _, id in ipairs(AS.State().order) do
		local l = AS.Lot(id)
		if l.kind == kind and (state == nil or l.state == state) then
			found = l
		end
	end
	return found
end

return {
	---------------------------------------------------------------- Autos
	{ "Ende-zu-Ende: Auto kaufen, am Autohaus holen, tunen (wirkt sofort), stylen, abstellen", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local CC = g:MiniShared("CarCatalog")
		local pl, d = join(g, 7001, "Anna")
		d.money, d.level = 200000, 30
		local model = CC.DealerModels[1]
		T.eq(act(g, pl, "mini_car_buy", { model = model.id }), "ok", "mini_car_buy über Remotes.Command")
		T.eq(#d.games.cars, 1, "Auto in d.games.cars")
		T.eq(d.money, 200000 - model.price, "Kaufpreis abgezogen (Katalogpreis)")
		T.eq(d.games.activeCar, d.games.cars[1].id, "erstes Auto ist aktiv")
		T.eq(#g:Notices(pl, "car_bought"), 1, "car_bought")
		local id = d.games.cars[1].id
		-- holen am Autohaus-Spawn der generierten Stadt
		g:Advance(1.1)
		T.eq(act(g, pl, "mini_car_spawn", { id = id, at = "dealer" }), "ok", "mini_car_spawn")
		local m = car(g, pl)
		T.check(m ~= nil, "Auto unter workspace.PlayerCars")
		local spot = cityPart(g, "CarSpawns.dealer")
		T.check(spot ~= nil, "City.CarSpawns.dealer in der Fixture")
		if not m or not spot then
			return
		end
		T.check(horizontal(m:GetPivot().Position, spot.Position) < 1, "am Spawnpunkt dealer")
		T.check(m:GetPivot().LookVector:Dot(spot.CFrame.LookVector) > 0.99, "Nase in Abfahrtsrichtung")
		T.eq(m:GetAttribute("OwnerId"), 7001, "Besitzer-Attribut")
		T.eq(m.PrimaryPart and m.PrimaryPart.Name, "Root", "PrimaryPart Root")
		T.check(m:FindFirstChild("DriverSeat") and m.DriverSeat:IsA("VehicleSeat"), "VehicleSeat")
		local spawned = g:Notices(pl, "car_spawned")
		T.check(#spawned == 1 and spawned[1].at == "dealer" and spawned[1].testdrive == false, "car_spawned")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and snap.spawnedCar == true and snap.spawnedId == id, "Snapshot: Auto draußen")
		T.check(snap and #snap.cars == 1 and snap.cars[1].tune and snap.cars[1].stats, "Snapshot: cars mit tune/stats")
		T.check(snap and type(snap.catalog) == "table" and #snap.catalog == #CC.DealerModels, "Snapshot: Katalog")
		T.check(snap and snap.activeCar == id and snap.garageMax == CC.MaxCars, "Snapshot: activeCar, garageMax")
		-- Tuning (gesehene Stufe 0 -> 1): Geld, Stufe, sofort am gefahrenen Auto
		local view = snap.cars[1]
		local torque, cost = m:GetAttribute("Torque"), view.tune.engine.cost
		local money = d.money
		g:Advance(0.2)
		T.eq(act(g, pl, "mini_car_tune", { id = id, part = "engine", level = 0 }), "ok", "mini_car_tune")
		T.eq(d.games.cars[1].engine, 1, "Motor Stufe 1")
		T.eq(d.money, money - cost, "Tuning-Preis aus dem Snapshot")
		local m2 = car(g, pl)
		T.check(m2 ~= nil and m2:GetAttribute("Torque") > torque, "mehr Drehmoment am gefahrenen Auto")
		g:Advance(0.2)
		money = d.money
		T.eq(act(g, pl, "mini_car_tune", { id = id, part = "engine", level = 0 }), "ok", "veraltete Stufe")
		T.eq(d.games.cars[1].engine, 1, "Doppelklick mit alter Stufe tunt nicht doppelt")
		T.eq(d.money, money, "und kostet nichts")
		-- Optik
		g:Advance(0.6)
		local c1 = d.games.cars[1]
		local paint = c1.paint % #CC.Paints + 1
		T.eq(act(g, pl, "mini_car_style", { id = id, paint = paint, rims = c1.rims, glow = c1.glow, spoiler = c1.spoiler }), "ok", "mini_car_style")
		T.eq(d.games.cars[1].paint, paint, "Lack geändert")
		T.eq((car(g, pl) or m):GetAttribute("Paint"), paint, "Lack am Auto")
		-- abstellen
		g:Advance(1.1)
		T.eq(act(g, pl, "mini_car_despawn"), "ok", "mini_car_despawn")
		T.eq(car(g, pl), nil, "abgestellt")
		T.check(#g:Notices(pl, "car_despawned") >= 1, "car_despawned")
		g:Advance(0.6)
		snap = g:MiniSnapshot(pl)
		T.eq(snap and snap.spawnedCar, false, "Snapshot: kein Auto draußen")
		-- fremde Spieler dürfen nicht einsteigen
		g:Advance(3.1)
		act(g, pl, "mini_car_spawn", { id = id, at = "workshop" })
		local other = join(g, 7002, "Bert")
		local m3 = car(g, pl)
		T.check(m3 ~= nil, "wieder draußen (Werkstatt)")
		if m3 then
			local plotSpot = g:Plot(pl):FindFirstChild("CarSpawn", true)
			T.check(plotSpot ~= nil and horizontal(m3:GetPivot().Position, plotSpot.Position) < 1, "auf Werkstatt.CarSpawn")
			sit(g, other, m3)
			local humanoid = other.Character:FindFirstChildOfClass("Humanoid")
			T.eq(humanoid.Sit, false, "fremder Insasse fliegt sofort raus")
			T.eq(m3.DriverSeat:FindFirstChild("SeatWeld"), nil, "Sitz-Schweißnaht gelöst")
			T.check(g:HasToast(other, "nicht dein Auto"), "Hinweis an den Fremden")
		end
		g:Leave(pl)
		g:Advance(0.5)
		T.eq(car(g, pl), nil, "Verlassen baut das Auto ab")
		noErrors(T, g)
	end },

	{ "Ende-zu-Ende: Probefahrt an der Übergabe, endet nach 60 s", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local pl, d = join(g, 7011, "Carla")
		d.money, d.level = 0, 1
		T.eq(act(g, pl, "mini_car_testdrive", { model = "aureon" }), "ok", "mini_car_testdrive")
		local m = car(g, pl, "Probe_")
		T.check(m ~= nil, "Probefahrt ohne Geld und über dem eigenen Level")
		local spot = cityPart(g, "CarSpawns.testdrive")
		if m and spot then
			T.check(horizontal(m:GetPivot().Position, spot.Position) < 1, "am Spawnpunkt testdrive")
			T.eq(m:GetAttribute("Testdrive"), true, "als Probefahrt markiert")
		end
		local n = g:Notices(pl, "car_spawned")[1]
		T.check(n and n.testdrive == true and math.abs(n.endsAt - (g:Now() + 60)) < 0.6, "endsAt in 60 s")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and type(snap.testdrive) == "table" and snap.testdrive.model == "aureon", "Snapshot: testdrive")
		T.eq(#d.games.cars, 0, "Probefahrt kauft kein Auto")
		g:Advance(58)
		T.check(car(g, pl, "Probe_") ~= nil, "nach 59 s noch da")
		g:Advance(1.5)
		T.eq(car(g, pl, "Probe_"), nil, "nach 60 s weg (Mini.Tick)")
		local ends = g:Notices(pl, "testdrive_end")
		T.eq(#ends, 1, "testdrive_end")
		T.eq(ends[1] and ends[1].reason, "time", "Grund: Zeit")
		g:Advance(0.6)
		snap = g:MiniSnapshot(pl)
		T.eq(snap and snap.testdrive, false, "Snapshot: keine Probefahrt mehr")
		T.eq(d.money, 0, "kostenlos")
		noErrors(T, g)
	end },

	{ "Ende-zu-Ende: Zeitfahren auf der echten Teststrecke (Checkpoints, Serverzeit, Belohnung, Bestzeit)", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local CC = g:MiniShared("CarCatalog")
		local CS = g:MiniServer("CarService")
		local pl, d = join(g, 7021, "Dirk")
		d.money, d.level = 100000, 1
		local list = CS.TrackSequence()
		T.check(list ~= nil and #list >= 2, "City.Track aus der Stadt: " .. tostring(list and #list))
		T.eq(list and list[#list].Name, "Ziel", "Ziel ist der letzte Checkpoint")
		T.eq(act(g, pl, "mini_track_start"), "ok", "ohne Auto")
		T.check(g:HasToast(pl, "Auto"), "Zeitfahren braucht ein eigenes Auto")
		act(g, pl, "mini_car_buy", { model = "komet" })
		g:Advance(3.1)
		T.eq(act(g, pl, "mini_track_start"), "ok", "mini_track_start")
		local m = car(g, pl)
		local spot = cityPart(g, "CarSpawns.track")
		T.check(m ~= nil and spot ~= nil and horizontal(m:GetPivot().Position, spot.Position) < 1, "Auto an der Startlinie")
		local start = g:Notices(pl, "track_start")[1]
		T.check(start and math.abs(start.startAt - (g:Now() + CC.Track.countdown)) < 0.6, "Startampel")
		T.eq(start and start.total, #list, "Anzahl Checkpoints")
		if not m or not start then
			return
		end
		sit(g, pl, m)
		g:AdvanceTo(start.startAt)
		local money = d.money
		driveLap(g, CS, m, 8)
		local cps = g:Notices(pl, "track_checkpoint")
		T.eq(#cps, #list - 1, "track_checkpoint je Zwischenpunkt")
		local fin = g:Notices(pl, "track_finish")[1]
		T.check(fin ~= nil, "track_finish")
		if fin then
			T.check(math.abs(fin.time - 8 * #list) < 0.6, "Zeit aus der Serveruhr: " .. tostring(fin.time))
			T.eq(fin.newBest, true, "erste Bestzeit")
			T.eq(fin.reward, CC.Track.firstReward, "erste gültige Runde: firstReward")
			T.eq(d.money, money + fin.reward, "Belohnung gutgeschrieben")
			T.eq(d.games.track.best, fin.time, "Bestzeit gespeichert")
			T.eq(d.games.track.runs, 1, "Läufe gezählt")
		end
		-- zweiter Lauf langsamer: keine Belohnung
		g:Advance(3.1)
		act(g, pl, "mini_track_start")
		m = car(g, pl)
		sit(g, pl, m)
		start = g:Notices(pl, "track_start")[2]
		g:AdvanceTo(start.startAt)
		money = d.money
		driveLap(g, CS, m, 9)
		local fin2 = g:Notices(pl, "track_finish")[2]
		T.check(fin2 ~= nil and fin2.newBest == false and fin2.reward == 0, "langsamere Runde: nichts")
		T.eq(d.money, money, "kein Geld")
		-- Teleport (zu schnell) ist ungültig
		g:Advance(3.1)
		act(g, pl, "mini_track_start")
		m = car(g, pl)
		sit(g, pl, m)
		start = g:Notices(pl, "track_start")[3]
		g:AdvanceTo(start.startAt)
		driveLap(g, CS, m, 0.01)
		local aborts = g:Notices(pl, "track_abort")
		T.eq(aborts[#aborts] and aborts[#aborts].reason, "tooFast", "Teleport: ungültig")
		T.eq(d.games.track.runs, 2, "ungültige Runde zählt nicht")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and snap.track and snap.track.best == d.games.track.best and snap.track.rewardedBest > 0, "Snapshot: track")
		noErrors(T, g)
	end },

	---------------------------------------------------------------- Auktion
	{ "Ende-zu-Ende: NPC-Auktion gewinnen und verlieren", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local AS = g:MiniServer("AuctionService")
		local AR = g:MiniShared("AuctionRules")
		local CC = g:MiniShared("CarCatalog")
		local winner, wd = join(g, 7031, "Emma")
		local loser, ld = join(g, 7032, "Finn")
		wd.money, wd.level = 5000000, 60
		ld.money, ld.level = 5000000, 60
		AS.Reset(7)
		local special = CC.Specials[1]
		-- Los 1: Emma bietet über allen NPC-Limits und gewinnt
		local lot = AS.StartNpcLot(special.id, g:Now())
		T.check(lot ~= nil, "NPC-Los geöffnet")
		local highest = 0
		for _, n in ipairs(lot.npcs) do
			highest = math.max(highest, n.limit)
		end
		local bid = math.min(lot.maxBid, highest + 1000)
		T.eq(act(g, winner, "mini_auction_bid", { lot = lot.id, amount = bid }), "ok", "mini_auction_bid")
		T.eq(AR.Top(lot).userId, 7031, "Emma führt")
		T.eq(wd.money, 5000000, "Bieten kostet noch nichts")
		T.check(#g:Notices(loser, "auction_update") >= 1, "auction_update an alle")
		g:Advance(AR.Npc.duration + AR.MaxExtend + 5)
		T.eq(lot.state, "sold", "zugeschlagen")
		T.eq(AR.Top(lot).userId, 7031, "kein NPC über seinem Limit")
		T.eq(wd.money, 5000000 - bid, "Emma zahlt ihr Gebot")
		T.eq(#wd.games.cars, 1, "Sondermodell in Emmas Garage")
		T.eq(wd.games.cars[1] and wd.games.cars[1].model, special.id, "richtiges Modell")
		T.eq(wd.games.auction.won, 1, "won gezählt")
		T.eq(#g:Notices(winner, "auction_won"), 1, "auction_won")
		g:Advance(3)
		local rec = g:Record(7031)
		T.check(rec and #rec.data.games.cars == 1 and rec.data.money == wd.money, "sofort gespeichert")
		-- Los 2: Finn bietet das Minimum, die NPCs überbieten ihn, er verliert (und zahlt nichts)
		g:Advance(AR.Npc.breakSeconds + 5)
		AS.Reset(8)
		local lot2 = AS.StartNpcLot(special.id, g:Now())
		T.check(lot2 ~= nil, "zweites Los")
		T.eq(act(g, loser, "mini_auction_bid", { lot = lot2.id, amount = AR.MinBid(lot2) }), "ok", "Mindestgebot")
		g:Advance(AR.Npc.duration + AR.MaxExtend + 5)
		T.eq(lot2.state, "sold", "an einen NPC")
		T.check(AR.Top(lot2).npc ~= nil, "NPC hat das Höchstgebot")
		T.eq(ld.money, 5000000, "Finn zahlt nichts")
		T.eq(#ld.games.cars, 0, "Finn bekommt kein Auto")
		T.eq(#g:Notices(loser, "auction_won"), 0, "kein auction_won")
		noErrors(T, g)
	end },

	{ "Ende-zu-Ende: Spieler-Auktion zwischen zwei Spielern, dann verlässt der Verkäufer den Server", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local AS = g:MiniServer("AuctionService")
		local AR = g:MiniShared("AuctionRules")
		AS.Reset(3)
		local seller, sd = join(g, 7041, "Gero")
		local buyer, bd = join(g, 7042, "Hanna")
		sd.money, sd.level = 100000, 20
		bd.money, bd.level = 100000, 20
		act(g, seller, "mini_car_buy", { model = "komet" })
		local id = sd.games.cars[1].id
		g:Advance(3.1)
		act(g, seller, "mini_car_spawn", { id = id, at = "workshop" })
		T.check(car(g, seller) ~= nil, "Auto draußen")
		local price = AR.StartOptions(sd.games.cars[1])[1]
		g:Advance(1)
		T.eq(act(g, seller, "mini_auction_consign", { id = id, start = price, duration = 120 }), "ok", "mini_auction_consign")
		T.eq(sd.games.cars[1].locked, true, "eingeliefert = gesperrt")
		T.eq(car(g, seller), nil, "eingeliefertes Auto von der Straße geholt")
		g:Advance(3.1)
		act(g, seller, "mini_car_spawn", { id = id, at = "workshop" })
		T.eq(car(g, seller), nil, "gesperrtes Auto nicht holbar")
		local lot = lotOf(AS, "player", "open")
		T.check(lot ~= nil and lot.sellerId == 7041, "Spieler-Los")
		T.eq(act(g, seller, "mini_auction_bid", { lot = lot.id, amount = price }), "ok", "eigenes Los")
		T.eq(#lot.bids, 0, "kein Gebot aufs eigene Auto")
		T.eq(act(g, buyer, "mini_auction_bid", { lot = lot.id, amount = price }), "ok", "Hanna bietet")
		T.eq(AR.Top(lot).userId, 7042, "Hanna führt")
		local sellerMoney = sd.money
		g:Advance(125)
		T.eq(lot.state, "sold", "verkauft")
		T.eq(#sd.games.cars, 0, "Auto beim Verkäufer weg")
		T.eq(#bd.games.cars, 1, "Auto bei der Käuferin")
		T.eq(bd.games.cars[1].locked, false, "entsperrt bei der Käuferin")
		T.eq(bd.money, 100000 - price, "Käuferin zahlt")
		T.eq(sd.money, sellerMoney + price - AR.Fee(price), "Verkäufer bekommt Preis minus 5 %")
		T.eq(#g:Notices(seller, "auction_sold"), 1, "auction_sold")
		g:Advance(3)
		T.check(g:Record(7041) and #g:Record(7041).data.games.cars == 0, "Verkäufer gespeichert")
		T.check(g:Record(7042) and #g:Record(7042).data.games.cars == 1, "Käuferin gespeichert")
		-- Hanna liefert weiter ein, Gero bietet, Hanna verlässt den Server: Abbruch, Auto entsperrt gespeichert
		local mine = bd.games.cars[1]
		g:Advance(11)
		T.eq(act(g, buyer, "mini_auction_consign", { id = mine.id, start = AR.StartOptions(mine)[1], duration = 300 }), "ok", "weiter eingeliefert")
		local lot2 = lotOf(AS, "player", "open")
		T.check(lot2 ~= nil and lot2.sellerId == 7042, "zweites Los")
		sd.money = 100000
		T.eq(act(g, seller, "mini_auction_bid", { lot = lot2.id, amount = lot2.start }), "ok", "Gero bietet")
		T.eq(#lot2.bids, 0, "Gero hat gerade an Hanna verkauft: 24 h kein Handel zwischen beiden (Geldschieben)")
		g:Leave(buyer)
		g:Advance(3)
		T.eq(lot2.state, "canceled", "Verkäuferin weg: abgebrochen")
		local rec = g:Record(7042)
		T.check(rec and rec.data.games.cars[1] and rec.data.games.cars[1].locked == false, "Auto entsperrt gespeichert")
		T.eq(sd.money, 100000, "Gero zahlt nichts")
		T.eq(#sd.games.cars, 0, "Gero bekommt nichts")
		noErrors(T, g)
	end },

	---------------------------------------------------------------- Spielhalle
	{ "Ende-zu-Ende: Spielhalle über die Station, Auszahlung nach Punkten, Tageslimit", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local A = g:MiniShared("ArcadeRules")
		local pl, d = join(g, 7051, "Ida")
		-- Station arcade_1 in der generierten Stadt öffnet den Tab mit dem Automaten
		local station = cityPart(g, "Stations.arcade_1")
		T.check(station ~= nil, "Station arcade_1")
		if station then
			T.eq(station:GetAttribute("Soon"), nil, "nicht mehr 'eröffnet bald'")
			g:Teleport(pl, station.Arrival.WorldPosition)
			local m = g:Mark()
			g:Trigger(pl, station:FindFirstChildOfClass("ProximityPrompt"), { force = true })
			local open = g:Events(pl, "mini_open", m)[1]
			T.check(open and open.tab == "arcade" and A.Resolve(open.game) and A.Resolve(open.game).key == "arcade_1", "Tab arcade mit Automat")
		end
		local function play()
			T.eq(act(g, pl, "mini_arcade_start", { game = "arcade_1" }), "ok", "mini_arcade_start")
			local rounds = g:Notices(pl, "arcade_round")
			local view = rounds[#rounds]
			for _, a in ipairs(g:MiniServer("ArcadeService").Round(g:MiniState(pl)).p.attempts) do
				g:AdvanceTo(view.startAt + a.g + 0.18)
				local at = g:Now()
				g:Advance(0.03)
				act(g, pl, "mini_arcade_input", { token = view.token, at = at, value = 1 })
			end
			g:AdvanceTo(view.endAt)
			act(g, pl, "mini_arcade_finish", { token = view.token })
			local results = g:Notices(pl, "arcade_result")
			return results[#results]
		end
		local money = d.money
		local res = play()
		local reward = A.GameByKey.arcade_1.reward
		T.eq(res and res.score, 1000, "perfekte Runde")
		T.eq(res and res.credits, reward, "Credits nach Punkten")
		T.eq(d.money, money + reward, "ausgezahlt")
		T.eq(d.games.arcade.best.arcade_1, 1000, "Rekord gespeichert")
		-- kurz vor dem Tageslimit: nur der Rest
		d.games.arcade.earned = A.DailyCap - 5
		money = d.money
		g:Advance(0.2)
		res = play()
		T.eq(res and res.credits, 5, "Tageslimit: nur der Rest")
		T.eq(res and res.capped, true, "capped")
		T.eq(d.money, money + 5, "höchstens bis zum Limit")
		money = d.money
		g:Advance(0.2)
		res = play()
		T.eq(res and res.credits, 0, "Limit erreicht: nichts mehr")
		T.eq(d.money, money, "kein Geld über dem Limit")
		g:Advance(0.6)
		local snap = g:MiniSnapshot(pl)
		T.check(snap and snap.arcade and snap.arcade.earnedToday == A.DailyCap and snap.arcade.left == 0, "Snapshot: arcade")
		-- nächster UTC-Tag (gespeicherter Tag liegt zurück): Limit wieder frei
		d.games.arcade.day = A.DayKey(g:Now() - 86400)
		g:Advance(0.2)
		money = d.money
		res = play()
		T.eq(res and res.credits, reward, "neuer Tag: wieder Credits")
		T.eq(d.money, money + reward, "ausgezahlt")
		noErrors(T, g)
	end },

	---------------------------------------------------------------- Stationen
	{ "Credit-Center öffnet den 2.4.0-Credits-Shop mit Game Passes; neue Stationen öffnen ihre Tabs", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local p = g:Join(7061, { name = "Jana" })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(2)
		local function trigger(key)
			local st = cityPart(g, "Stations." .. key)
			T.check(st ~= nil, "Station " .. key)
			if not st then
				return nil
			end
			T.eq(st:GetAttribute("Soon"), nil, key .. ": ohne Soon")
			g:Teleport(p, st.Arrival.WorldPosition)
			local m = g:Mark()
			g:Trigger(p, st:FindFirstChildOfClass("ProximityPrompt"), { force = true })
			g:Advance(0.3)
			T.check(not g:HasToast(p, "eröffnet bald", m), key .. ": kein 'eröffnet bald'")
			return g:Events(p, "mini_open", m)[1]
		end
		local open = trigger("shop")
		T.check(open and open.tab == "shop" and open.page == "credits", "Credit-Center: mini_open page=credits")
		T.check(g:FindGui(p, "Credits für deine Werkstatt") ~= nil, "2.4.0-Credits-Shop im Tablet sichtbar")
		T.check(g:FindGui(p, "Game Pass · 2× Schrott") ~= nil, "Game Pass 2× Schrott im Credit-Center")
		T.check(g:FindGui(p, "Game Pass · Schrottpresse+") ~= nil, "Game Pass Schrottpresse+ im Credit-Center")
		local MiniClient = g:ClientModule(p, "Mini.MiniClient")
		T.eq(g:InClient(p, function()
			return MiniClient.IsOpen()
		end), false, "Minispiel-Panel bleibt zu")
		local expect = { dealer = "dealer", testdrive = "dealer", track = "track", carwash = "carwash", auction = "auction",
			auction_consign = "auction", arcade = "arcade" }
		for key, tab in pairs(expect) do
			open = trigger(key)
			T.eq(open and open.tab, tab, key .. " öffnet " .. tab)
			local current = g:InClient(p, function()
				local UI = require(p.PlayerScripts.Mini.MiniUI)
				return UI.IsOpen and UI.CurrentTab
			end)
			T.eq(current, tab, key .. ": Tab im Panel offen")
		end
		noErrors(T, g)
	end },

	{ "Snapshot: Garage-Liste und Katalog nur bei Änderungen, der Client behält sie dazwischen", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local p = g:Join(7065, { name = "Lars" })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(2)
		local d = g:D(p)
		d.money = 100000
		act(g, p, "mini_car_buy", { model = "komet" })
		g:Advance(0.6)
		local m = g:Mark()
		g:Advance(12)
		local light, full = 0, 0
		for _, snap in ipairs(g:Events(p, "mini", m)) do
			if snap.cars == nil and snap.catalog == nil then
				light += 1
				T.check(snap.spawnedCar ~= nil and snap.track ~= nil and snap.credits ~= nil, "kleine Felder immer dabei")
			else
				full += 1
			end
		end
		T.check(light >= 8, "Produktions-Snapshots ohne cars/catalog: " .. light)
		T.check(full >= 1, "spätestens alle 10 s vollständig: " .. full)
		local MiniClient = g:ClientModule(p, "Mini.MiniClient")
		local cars, catalog = g:InClient(p, function()
			local s = MiniClient.Snapshot()
			return s and s.cars, s and s.catalog
		end)
		T.check(type(cars) == "table" and #cars == 1, "Client behält die Garage-Liste")
		T.check(type(catalog) == "table" and #catalog > 0, "Client behält den Katalog")
		-- eine Aktion (dirty) schickt sofort alles
		m = g:Mark()
		act(g, p, "mini_car_buy", { model = "komet" })
		local snap = g:Last(p, "mini", m)
		T.check(snap and snap.cars and #snap.cars == 2, "nach dem Kauf sofort vollständig")
		noErrors(T, g)
	end },

	---------------------------------------------------------------- Daten
	{ "Speichern/Laden: Autos, Teststrecke, Spielhalle, Auktion überleben den Neustart (locked wird frei)", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local pl, d = join(g, 7071, "Kai")
		d.money, d.level = 500000, 30
		act(g, pl, "mini_car_buy", { model = "komet" })
		g:Advance(1.1)
		act(g, pl, "mini_car_buy", { model = "vektor" })
		T.eq(#d.games.cars, 2, "zwei Autos")
		g:Advance(0.2)
		act(g, pl, "mini_car_tune", { id = d.games.cars[2].id, part = "nitro", level = 0 })
		T.eq(d.games.cars[2].nitro, 1, "Nitro eingebaut")
		d.games.cars[1].locked = true -- mitten in einer Auktion gespeichert
		d.games.track = { best = 71.5, rewardedBest = 71.5, runs = 4 }
		d.games.arcade.best.arcade_3 = 812
		d.games.auction.won, d.games.auction.sold = 2, 1
		local expected = table.clone(d.games.cars[2])
		g:Leave(pl)
		g:Advance(15)
		local rec = g:Record(7071)
		T.check(rec ~= nil and #rec.data.games.cars == 2, "gespeichert")
		local g2 = H.Garage({ startTime = NOW + 100, shareDataStoresWith = g })
		local pl2, d2 = join(g2, 7071, "Kai")
		T.eq(#d2.games.cars, 2, "Autos geladen")
		T.eq(d2.games.cars[1].locked, false, "Auktions-Sperre nach Neustart frei")
		for k, v in pairs(expected) do
			T.eq(d2.games.cars[2][k], v, "Auto 2: " .. k)
		end
		T.eq(d2.games.carSerial, d.games.carSerial, "carSerial")
		T.eq(d2.games.activeCar, d.games.activeCar, "activeCar")
		T.eq(d2.games.track.best, 71.5, "track.best")
		T.eq(d2.games.track.runs, 4, "track.runs")
		T.eq(d2.games.arcade.best.arcade_3, 812, "arcade.best")
		T.eq(d2.games.auction.won, 2, "auction.won")
		T.eq(d2.games.auction.sold, 1, "auction.sold")
		g2:Advance(3.1)
		T.eq(act(g2, pl2, "mini_car_spawn", { id = d2.games.cars[1].id, at = "workshop" }), "ok", "entsperrtes Auto holbar")
		T.check(car(g2, pl2) ~= nil, "Auto draußen")
		noErrors(T, g2)
	end },

	{ "Veteranen: 2.4.0-Profil und 3.0-Profil ohne neue Felder laden sauber und können Autos kaufen", function(T, H)
		local g = H.Garage({ startTime = NOW, before = function(g)
			-- 2.4.0: kein games
			g:Seed(7081, { version = 2, data = { version = 2, money = 50000, level = 8, completed = 3 }, receipts = {} })
			-- 3.0 (Ausbaustufe 1): games ohne cars/track/arcade/auction, dafür Müll in unbekannten Feldern
			local d = g:Rules().NewData(NOW - 86400)
			d.money, d.level = 50000, 8
			for _, key in ipairs({ "cars", "carSerial", "activeCar", "track", "arcade", "auction" }) do
				d.games[key] = nil
			end
			d.games.unbekannt = { x = 1 }
			g:Seed(7082, { version = 2, data = d, receipts = {} })
		end })
		for _, uid in ipairs({ 7081, 7082 }) do
			local pl, d = join(g, uid, "V" .. uid)
			T.check(d ~= nil, uid .. ": geladen")
			T.eq(type(d.games.cars), "table", uid .. ": cars")
			T.eq(#d.games.cars, 0, uid .. ": keine Autos")
			T.eq(d.games.carSerial, 0, uid .. ": carSerial")
			T.eq(d.games.activeCar, 0, uid .. ": activeCar")
			T.eq(d.games.track.best, 0, uid .. ": track")
			T.eq(d.games.arcade.earned, 0, uid .. ": arcade")
			T.eq(d.games.auction.won, 0, uid .. ": auction")
			T.eq(d.games.unbekannt, nil, uid .. ": Unbekanntes verworfen")
			T.eq(d.money, 50000, uid .. ": Geld unverändert")
			local snap = g:MiniSnapshot(pl)
			T.check(snap and type(snap.cars) == "table" and type(snap.catalog) == "table" and snap.arcade and snap.auction, uid .. ": Snapshot")
			T.eq(act(g, pl, "mini_car_buy", { model = "komet" }), "ok", uid .. ": kauft")
			T.eq(#d.games.cars, 1, uid .. ": erstes Auto")
			g:Leave(pl)
			g:Advance(15)
			local rec = g:Record(uid)
			T.check(rec and rec.data.games and #rec.data.games.cars == 1 and rec.data.games.track and rec.data.games.arcade, uid .. ": neue Felder gespeichert")
		end
		noErrors(T, g)
	end },

	{ "Auktionsbuch: speichert nur ein Profil nach der Übergabe, gleicht das Laden ab (kein Duplikat, kein Geld aus dem Nichts)", function(T, H)
		local g = H.Garage({ startTime = NOW })
		local AS = g:MiniServer("AuctionService")
		local AR = g:MiniShared("AuctionRules")
		AS.Reset(5)
		local seller, sd = join(g, 7061, "Jana")
		local buyer, bd = join(g, 7062, "Kurt")
		sd.money, sd.level = 50000, 20
		bd.money, bd.level = 100000, 20
		act(g, seller, "mini_car_buy", { model = "komet" })
		local id = sd.games.cars[1].id
		local price = AR.StartOptions(sd.games.cars[1])[1]
		g:Advance(1)
		T.eq(act(g, seller, "mini_auction_consign", { id = id, start = price, duration = 120 }), "ok", "eingeliefert")
		local lot = lotOf(AS, "player", "open")
		T.eq(act(g, buyer, "mini_auction_bid", { lot = lot.id, amount = price }), "ok", "Kurt bietet")
		-- Stand VOR der Übergabe (so bliebe er gespeichert, wenn das Speichern danach ausfällt)
		local staleSeller, staleBuyer = H.Copy(sd), H.Copy(bd)
		g:Advance(125)
		T.eq(lot.state, "sold", "verkauft")
		local sellerMoney, buyerMoney = sd.money, bd.money
		g:Advance(3)
		local ds = g:DataStoreMock()
		local book = ds.stores["UCG_Auktionsbuch_v1"]
		T.check(book ~= nil, "Auktionsbuch-DataStore angelegt")
		local sEntry = book and book.data.U_7061 and book.data.U_7061.sold and book.data.U_7061.sold[1]
		local bEntry = book and book.data.U_7062 and book.data.U_7062.bought and book.data.U_7062.bought[1]
		T.check(sEntry and sEntry.carId == id and sEntry.model == "komet", "Verkäufer-Eintrag")
		T.check(bEntry and bEntry.amount == price and bEntry.car and bEntry.car.model == "komet", "Käufer-Eintrag")
		T.check(sEntry and bEntry and sEntry.tid == bEntry.tid, "gleiche Übergabe-Id")
		-- beide verlassen den Server; danach "fällt" das Speichern des Verkäufers aus: alter Stand im Store
		g:Leave(seller)
		g:Leave(buyer)
		g:Advance(3)
		g:Seed(7061, { version = 2, data = staleSeller, receipts = {} })
		local seller2, sd2 = join(g, 7061, "Jana")
		T.eq(#sd2.games.cars, 0, "Verkäuferin: übergebenes Auto beim Laden entfernt (kein Duplikat)")
		T.eq(sd2.money, staleSeller.money + (sellerMoney - staleSeller.money), "Auszahlung nachgeholt")
		-- nochmal laden: nichts doppelt
		g:Leave(seller2)
		g:Advance(3)
		local seller3, sd3 = join(g, 7061, "Jana")
		T.eq(#sd3.games.cars, 0, "idempotent: kein Auto")
		T.eq(sd3.money, sellerMoney, "idempotent: Geld einmal")
		g:Leave(seller3)
		-- Käufer-Speichern "fällt aus": alter Stand ohne Auto und mit dem vollen Geld
		g:Seed(7062, { version = 2, data = staleBuyer, receipts = {} })
		local buyer2, bd2 = join(g, 7062, "Kurt")
		T.eq(#bd2.games.cars, 1, "Käufer: Auto beim Laden nachgeliefert")
		T.eq(bd2.money, buyerMoney, "Preis beim Laden abgezogen")
		g:Leave(buyer2)
		g:Advance(3)
		local buyer3, bd3 = join(g, 7062, "Kurt")
		T.eq(#bd3.games.cars, 1, "idempotent: ein Auto")
		T.eq(bd3.money, buyerMoney, "idempotent: einmal bezahlt")
		-- Profil, das ordentlich gespeichert wurde: unverändert
		T.eq(bd3.games.cars[1].model, "komet", "richtiges Modell")
		noErrors(T, g)
	end },
}
