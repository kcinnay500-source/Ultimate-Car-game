-- 3.0 Verkehr und Ampeln (CityClient, Team Verkehr): Ampelprogramm (Gelb 3 s, Alles-Rot 1,5 s, nie zwei Ströme grün,
-- Fußgänger nur bei Rot des gekreuzten Stroms), Linsen (an = Neon, aus = dunkel, alle Köpfe synchron), kinematisches
-- Fahren (Halt 3-4 Studs vor der roten Haltelinie, sanftes Bremsen ohne Geschwindigkeitssprünge, Schlange mit
-- 5-6 Studs Lücke, Zeitlücke in Fahrt, Kurven langsamer), Halt vor Spielfiguren/Spielerautos in der Spur (nie
-- hindurch) und vor besetzten Zebras, Kollisionsbox der Autos. Die Logik läuft in einer eigenen Mock-Umgebung ohne
-- Fixture (CityClient._test); der letzte Test fährt die echte Stadt aus der Fixture (Haltelinien, Ampelköpfe,
-- Rotlicht-Disziplin, keine Überlappung, kein Stillstand).
local NOW = 1760000000
local Y = -0.95

---------------------------------------------------------------- Umgebung ohne Fixture
local function standalone(H)
	local Mock = H.Mock
	local env = Mock.NewEnv({ startTime = NOW, frameStep = 1 / 30 })
	Mock.Activate(env)
	local rs = env.services.ReplicatedStorage or Mock.CreateService(env, "ReplicatedStorage")
	local ms = env.Instance.new("ModuleScript")
	ms.Name = "CityClient"
	ms.Source = readfile(H.ROOT .. "/src/mini/client/CityClient.lua")
	rawget(ms, "__data").path = "src/mini/client/CityClient.lua"
	ms.Parent = rs
	local City = Mock.Require(env, ms)
	local city = env.Instance.new("Model")
	city.Name = "City"
	city.Parent = env.workspace
	local animated = env.Instance.new("Folder")
	animated.Name = "Animated"
	animated.Parent = city
	local S = { env = env, City = City, city = city, animated = animated, T = City._test }
	env.workspace.CurrentCamera.CFrame = CFrame.new(0, 60, 20)
	-- Serverzeit auf eine Stelle im 32-s-Umlauf setzen (vorwärts)
	function S.toCycle(target)
		local now = env.clock.wall
		local d = ((target - now % 32) % 32)
		if d > 1e-6 then
			env.clock:Advance(d)
		end
	end
	function S.cycle()
		return env.clock.wall % 32
	end
	-- n Frames à dt: Uhr und CityClient.Step; fn(i) nach jedem Frame
	function S.run(seconds, fn, dt)
		dt = dt or 1 / 30
		local n = math.floor(seconds / dt + 0.5)
		for i = 1, n do
			env.clock:Advance(dt)
			S.T.Step(dt)
			if fn then
				fn(i)
			end
		end
	end
	function S.loop(name, pts, attrs)
		local f = env.Instance.new("Folder")
		f.Name = name
		local list = {}
		for _, p in ipairs(pts) do
			table.insert(list, string.format("%.3f,%.2f,%.3f", p[1], Y, p[2]))
		end
		f:SetAttribute("Waypoints", table.concat(list, ";"))
		for k, v in pairs(attrs or {}) do
			f:SetAttribute(k, v)
		end
		f.Parent = animated
		return f
	end
	-- Auto wie aus der Worldgen: Model mit Root (PrimaryPart, Nase lokal -Z), Karosserie und Rädern
	function S.car(name, path, attrs)
		local m = env.Instance.new("Model")
		m.Name = name
		local function p(nm, size, offset)
			local x = env.Instance.new("Part")
			x.Name = nm
			x.Anchored = true
			x.CanCollide = true
			x.Size = size
			x.CFrame = CFrame.new(offset)
			x.Parent = m
			return x
		end
		local root = p("Root", Vector3.new(0.1, 0.1, 0.1), Vector3.new(0, Y, 0))
		root.Transparency = 1
		p("Paint", Vector3.new(7.8, 2.4, 16.05), Vector3.new(0, Y + 2.5, 0.425))
		p("WheelFLTire", Vector3.new(1, 2.6, 2.6), Vector3.new(-4, Y + 1.3, -4.5))
		p("WheelRRTire", Vector3.new(1, 2.6, 2.6), Vector3.new(4, Y + 1.3, 5.3))
		m.PrimaryPart = root
		m:SetAttribute("Anim", "traffic")
		m:SetAttribute("Path", path)
		m:SetAttribute("StartOffset", 0)
		m:SetAttribute("Front", 7.6)
		m:SetAttribute("Rear", 8.45)
		m:SetAttribute("Length", 16.05)
		m:SetAttribute("Width", 8)
		for k, v in pairs(attrs or {}) do
			m:SetAttribute(k, v)
		end
		m.Parent = animated
		return m
	end
	function S.attach()
		S.T.Attach(animated)
		env.scheduler:run()
	end
	function S.rec(m)
		return S.T.TrafficRecord(m)
	end
	return S
end

-- Rechteck-Rundkurs: unten von (-200,0) nach (200,0) (+X), dann zurück auf Z 40 (scharfe Ecken bremsen nicht)
local RECT = { { -200, 0 }, { 200, 0 }, { 200, 40 }, { -200, 40 } }

-- Geschwindigkeitsverlauf eines Autos aufzeichnen und Beschleunigungsgrenzen prüfen
local function watcher(rec)
	local w = { maxAcc = 0, maxDec = 0, last = nil, lastT = nil }
	function w.sample(t)
		if w.last and t > w.lastT then
			local a = (rec.v - w.last) / (t - w.lastT)
			w.maxAcc = math.max(w.maxAcc, a)
			w.maxDec = math.max(w.maxDec, -a)
		end
		w.last, w.lastT = rec.v, t
	end
	return w
end

return {
	{ "Ampelprogramm: Gelb 3 s, Alles-Rot 1,5 s, nie zwei Ströme gleichzeitig, Fußgänger nur bei Rot des gekreuzten Stroms", function(T, H)
		local S = standalone(H)
		local City = S.City
		T.eq(City.SignalCycle, 32, "Umlauf 32 s")
		local prev = {}
		local runs = { Meile = {}, Markt = {} }
		local step = 0.05
		local pedNS, pedWE, both = 0, 0, 0
		local lastChange = { Meile = nil, Markt = nil }
		for i = 0, math.floor(64 / step) do
			local t = NOW + i * step + 0.001
			local a, b = City.SignalState("Meile", t), City.SignalState("Markt", t)
			T.check(a == "red" or b == "red", "nie Meile und Markt gleichzeitig grün/gelb (t=" .. (t % 32) .. ")")
			for serves, st in pairs({ Meile = a, Markt = b }) do
				local p = prev[serves]
				if p and p ~= st then
					-- erlaubte Folge: grün -> gelb -> rot -> grün
					local okSeq = (p == "green" and st == "amber") or (p == "amber" and st == "red") or (p == "red" and st == "green")
					T.check(okSeq, serves .. ": Wechsel " .. p .. " -> " .. st)
					if lastChange[serves] then
						table.insert(runs[serves], { state = p, dur = t - lastChange[serves] })
					end
					lastChange[serves] = t
				end
				prev[serves] = st
			end
			local ns, we = City.PedGreen("NS", t), City.PedGreen("WE", t)
			if ns then
				pedNS += 1
				T.check(b == "red", "Fußgänger NS (über die Marktstraße) nur bei Markt rot")
				-- Räumzeit: noch mindestens 4 s Markt rot
				T.eq(City.SignalState("Markt", t + 4), "red", "Fußgänger NS: 4 s Räumzeit vor Markt grün")
			end
			if we then
				pedWE += 1
				T.check(a == "red", "Fußgänger WE (über die Meile) nur bei Meile rot")
				T.eq(City.SignalState("Meile", t + 4), "red", "Fußgänger WE: 4 s Räumzeit vor Meile grün")
			end
			if ns and we then
				both += 1
			end
		end
		T.check(pedNS > 100 and pedWE > 100, "beide Fußgängerphasen kommen vor")
		T.eq(both, 0, "Fußgängerphasen getrennt")
		for serves, list in pairs(runs) do
			local amberSeen = false
			for _, r in ipairs(list) do
				if r.state == "amber" then
					amberSeen = true
					T.near(r.dur, 3, 0.06, serves .. ": Gelb 3 s")
				elseif r.state == "green" then
					T.check(r.dur >= 8, serves .. ": Grün mindestens 8 s (" .. r.dur .. ")")
				end
			end
			T.check(amberSeen, serves .. ": Gelbphase vorhanden")
		end
		-- Alles-Rot-Räumzeit 1,5 s zwischen Gelb-Ende des einen und Grün des anderen Stroms
		local function firstFrom(serves, state, from)
			for i = 0, 3200 do
				local t = from + i * 0.01
				if City.SignalState(serves, t) == state then
					return t
				end
			end
			return nil
		end
		local base = NOW - NOW % 32
		local meileRed = firstFrom("Meile", "red", base + 0.01)
		local marktGreen = firstFrom("Markt", "green", meileRed)
		T.near(marktGreen - meileRed, 1.5, 0.02, "Alles-Rot nach der Meile 1,5 s")
		local marktRed = firstFrom("Markt", "red", marktGreen)
		local meileGreen = firstFrom("Meile", "green", marktRed)
		T.near(meileGreen - marktRed, 1.5, 0.02, "Alles-Rot nach dem Markt 1,5 s")
		T.eq(City.SignalState("Unbekannt", NOW), "red", "unbekannter Strom: rot")
	end },

	{ "Ampel-Linsen: an = Neon, aus = dunkel (SmoothPlastic, Transparenz 0,7), genau eine Lampe je Kopf, alle Köpfe einer Kreuzung synchron", function(T, H)
		local S = standalone(H)
		local env = S.env
		local function mast(name, serves, ped, pos)
			local m = env.Instance.new("Model")
			m.Name = name
			m:SetAttribute("Anim", "signal")
			m:SetAttribute("Group", "K-West")
			m:SetAttribute("Serves", serves)
			m:SetAttribute("PedPhase", ped)
			local colors = { Red = Color3.new(1, 0.2, 0.15), Amber = Color3.new(1, 0.66, 0.12), Green = Color3.new(0.24, 0.9, 0.35), PedRed = Color3.new(1, 0.24, 0.2), PedGreen = Color3.new(0.24, 0.9, 0.35) }
			for nm, c in pairs(colors) do
				local x = env.Instance.new("Part")
				x.Name = nm
				x.Anchored = true
				x.Material = Enum.Material.Neon
				x.Color = c
				x.Transparency = (nm == "Red" or nm == "PedRed") and 0 or 0.7
				x.CFrame = CFrame.new(pos)
				x.Parent = m
			end
			m.Parent = S.animated
			return m, colors
		end
		-- ein Mast nah an der Kamera, einer 200 Studs weg (langsamer Takt für andere Arten) - beide schalten sofort
		local a, colors = mast("NW", "Markt", "NS", Vector3.new(-20, 6, -20))
		local b = mast("SW", "Meile", "WE", Vector3.new(-20, 6, 20))
		local c = mast("Fern NO", "Meile", "WE", Vector3.new(200, 6, -100))
		S.attach()
		local function lit(m)
			local on = {}
			for _, nm in ipairs({ "Red", "Amber", "Green" }) do
				local x = m:FindFirstChild(nm)
				if x.Material == Enum.Material.Neon and x.Transparency == 0 then
					table.insert(on, nm)
				else
					T.eq(x.Material, Enum.Material.SmoothPlastic, m.Name .. "." .. nm .. " aus: kein Neon")
					T.eq(x.Transparency, S.City.LensOff, m.Name .. "." .. nm .. " aus: Transparenz")
					local base = colors[nm]
					T.check(x.Color.R <= base.R * 0.25 + 1e-6 and x.Color.G <= base.G * 0.25 + 1e-6, m.Name .. "." .. nm .. " aus: abgedunkelt")
				end
			end
			return on
		end
		local function check(at, meile, markt, walkNS, walkWE)
			S.toCycle(at)
			S.run(1 / 30)
			for _, m in ipairs({ a, b, c }) do
				local on = lit(m)
				T.eq(#on, 1, m.Name .. ": genau eine Lampe an (t=" .. at .. ")")
				local want = m:GetAttribute("Serves") == "Meile" and meile or markt
				T.eq(on[1], want, m.Name .. " bei t=" .. at)
				local walk = walkWE
				if m:GetAttribute("PedPhase") == "NS" then
					walk = walkNS
				end
				local pg, pr = m.PedGreen, m.PedRed
				T.eq(pg.Transparency == 0 and pg.Material == Enum.Material.Neon, walk, m.Name .. ": Fußgänger grün bei t=" .. at)
				T.eq(pr.Transparency == 0 and pr.Material == Enum.Material.Neon, not walk, m.Name .. ": Fußgänger rot bei t=" .. at)
			end
			T.eq(lit(a)[1] ~= "Red" and lit(b)[1] ~= "Red", false, "nie beide Ströme einer Kreuzung offen (t=" .. at .. ")")
		end
		check(5, "Green", "Red", true, false)
		check(12, "Amber", "Red", false, false)
		check(15, "Red", "Red", false, false)
		check(20, "Red", "Green", false, true)
		check(29, "Red", "Amber", false, false)
		check(31, "Red", "Red", false, false)
		-- Synchron: genau beim Wechsel (11,5 s) schalten nahe und ferne Köpfe im selben Frame
		S.toCycle(11.44)
		S.run(1 / 30)
		T.eq(lit(b)[1], "Green", "kurz vor dem Wechsel grün")
		S.run(1 / 30)
		T.eq(lit(b)[1], "Amber", "naher Kopf gelb im ersten Frame nach 11,5 s")
		T.eq(lit(c)[1], "Amber", "ferner Kopf derselben Phase im selben Frame gelb")
		T.eq(#S.env.scheduler.errors, 0, "keine Laufzeitfehler")
	end },

	{ "Verkehr: gleitet bei Rot sanft bis 3-4 Studs vor die Haltelinie, wartet, fährt bei Grün mit <= 6 st/s² an", function(T, H)
		local S = standalone(H)
		S.loop("Loop_R", RECT, { StopLines = "0,0,Meile" })
		local car = S.car("Auto", "Loop_R", { Speed = 26 })
		S.attach()
		local r = S.rec(car)
		T.check(r ~= nil, "Auto registriert")
		S.toCycle(14.6) -- Meile rot bis 32
		r.u, r.fresh = 50, true -- Mitte 150 Studs vor der Linie (Linie bei u 200)
		S.run(1 / 30)
		T.near(r.v, 26, 0.01, "fährt mit Reisetempo heran")
		local w = watcher(r)
		local minFrontGap = math.huge
		S.run(14, function()
			w.sample(S.env.clock.wall)
			minFrontGap = math.min(minFrontGap, 200 - (r.u + r.front))
		end)
		local gap = 200 - (r.u + r.front)
		T.eq(r.v, 0, "steht bei Rot")
		T.check(gap >= 3 and gap <= 4, "Front 3-4 Studs vor der Haltelinie (" .. gap .. ")")
		T.check(minFrontGap >= 3 - 1e-6, "nie über den Haltepunkt hinaus (" .. minFrontGap .. ")")
		T.check(w.maxDec <= 12 + 1e-4, "Bremsen höchstens 12 st/s² (" .. w.maxDec .. ")")
		T.check(w.maxDec <= 5.6, "komfortables Bremsen ~5 st/s² (" .. w.maxDec .. ")")
		-- Modell auf der Strecke: Pivot bei der Mitte, Box fährt mit
		local box = car:FindFirstChild("Kollision")
		T.check(box ~= nil, "Kollisionsbox vorhanden")
		T.near(car:GetPivot().Position.X, -200 + r.u, 0.05, "Model steht dort, wo die Logik es hält")
		local want = car:GetPivot() * CFrame.new(0, 0, 0.425)
		T.check(box and math.abs(box.Position.X - want.Position.X) < 0.1 and math.abs(box.Position.Z - want.Position.Z) < 0.1, "Box fährt mit dem Auto")
		local u0 = r.u
		S.run(2)
		T.near(r.u, u0, 1e-6, "wartet bei Rot")
		S.toCycle(0.02) -- grün
		w = watcher(r)
		S.run(4, function()
			w.sample(S.env.clock.wall)
		end)
		T.check(r.u - u0 > 20, "fährt bei Grün weiter")
		T.check(w.maxAcc <= 6 + 1e-4, "Anfahren höchstens 6 st/s² (" .. w.maxAcc .. ")")
		T.check(r.v > 15 and r.v <= 26 + 1e-6, "beschleunigt Richtung Reisetempo (" .. r.v .. ")")
	end },

	{ "Verkehr: Gelb - anhalten, wenn es sanft geht, sonst durchfahren; nie bei Rot über die Linie", function(T, H)
		local S = standalone(H)
		S.loop("Loop_R", RECT, { StopLines = "0,0,Meile" })
		local near = S.car("Nah", "Loop_R", { Speed = 26 })
		local far = S.car("Fern", "Loop_R", { Speed = 26 })
		S.attach()
		local rn, rf = S.rec(near), S.rec(far)
		S.toCycle(11.45) -- 0,05 s vor Gelb
		rn.u, rn.fresh = 200 - 7.6 - 3.5 - 15, true -- 15 Studs vor dem Haltepunkt: Anhalten bräuchte ~22 st/s²
		rf.u, rf.fresh = 200 - 7.6 - 3.5 - 110, true -- 110 Studs: sanft möglich
		local crossedAt, minFar = nil, math.huge
		S.run(10, function()
			if not crossedAt and rn.u + rn.front > 200 then
				crossedAt = S.cycle()
			end
			minFar = math.min(minFar, 200 - (rf.u + rf.front))
		end)
		T.check(crossedAt ~= nil and crossedAt >= 11.5 and crossedAt < 14.5, "nahes Auto fährt bei Gelb durch (" .. tostring(crossedAt) .. ")")
		T.eq(rf.v, 0, "fernes Auto hält an")
		T.check(minFar >= 3 - 1e-6 and minFar <= 4, "fernes Auto: Front 3-4 Studs vor der Linie (" .. minFar .. ")")
	end },

	{ "Verkehr: Schlange mit 5-6 Studs Lücke im Stand, Zeitlücke in Fahrt, keine Überlappung", function(T, H)
		local S = standalone(H)
		S.loop("Loop_R", RECT, { StopLines = "0,0,Meile" })
		local cars = { S.car("A1", "Loop_R", { Speed = 26 }), S.car("A2", "Loop_R", { Speed = 26 }), S.car("A3", "Loop_R", { Speed = 26 }) }
		S.attach()
		local recs = {}
		for i, m in ipairs(cars) do
			recs[i] = S.rec(m)
			recs[i].u, recs[i].fresh = 120 - (i - 1) * 40, true
		end
		S.toCycle(14.6)
		local minGap = math.huge
		local function gaps()
			local out = {}
			for i = 2, 3 do
				local lead, f = recs[i - 1], recs[i]
				table.insert(out, (lead.u - lead.rear) - (f.u + f.front))
			end
			return out
		end
		S.run(15, function()
			for _, g in ipairs(gaps()) do
				minGap = math.min(minGap, g)
			end
		end)
		for i, g in ipairs(gaps()) do
			T.check(g >= 5 and g <= 6.01, "Lücke im Stand " .. i .. ": 5-6 Studs (" .. g .. ")")
		end
		for _, r in ipairs(recs) do
			T.eq(r.v, 0, r.inst.Name .. " steht")
		end
		local first = 200 - (recs[1].u + recs[1].front)
		T.check(first >= 3 and first <= 4, "erstes Auto 3-4 vor der Linie (" .. first .. ")")
		T.check(minGap >= 5 - 1e-6, "nie näher als 5 Studs (" .. minGap .. ")")
		-- Grün: Zeitlücke in Fahrt mindestens ~1 s, Lücke nie unter 5
		S.toCycle(0.02)
		local worstHeadway, minMoving = math.huge, math.huge
		local ws = { watcher(recs[2]), watcher(recs[3]) }
		S.run(10, function()
			for i, g in ipairs(gaps()) do
				local f = recs[i + 1]
				minMoving = math.min(minMoving, g)
				if f.v > 8 then
					worstHeadway = math.min(worstHeadway, (g - 5.5) / f.v)
				end
			end
			ws[1].sample(S.env.clock.wall)
			ws[2].sample(S.env.clock.wall)
		end)
		T.check(minMoving >= 5 - 1e-6, "in Fahrt nie näher als 5 Studs (" .. minMoving .. ")")
		T.check(worstHeadway >= 1.0, "Zeitlücke in Fahrt >= 1 s (" .. worstHeadway .. ")")
		T.check(recs[3].v > 10, "Schlange löst sich auf")
		for i, w in ipairs(ws) do
			T.check(w.maxAcc <= 6 + 1e-4 and w.maxDec <= 12 + 1e-4, "Folgeauto " .. i .. " ohne Sprünge (+" .. w.maxAcc .. "/-" .. w.maxDec .. ")")
		end
	end },

	{ "Verkehr: hält vor Spielfigur und Spielerauto in der Spur, nie hindurch, fährt danach sanft weiter; Figur neben der Spur stört nicht", function(T, H)
		local S = standalone(H)
		S.loop("Loop_P", RECT) -- ohne Ampeln
		local car = S.car("Auto", "Loop_P", { Speed = 26 })
		S.attach()
		local r = S.rec(car)
		local actors = {}
		S.T.SetActors(function()
			return actors
		end)
		-- Figur mitten auf der Spur bei X 0 (u 200)
		actors = { { pos = Vector3.new(0, 2, 0.5), r = 1.5, char = true } }
		r.u, r.fresh = 40, true
		local w = watcher(r)
		local closest = math.huge
		S.run(12, function()
			w.sample(S.env.clock.wall)
			closest = math.min(closest, 200 - 1.5 - (r.u + r.front))
		end)
		T.eq(r.v, 0, "hält vor der Figur")
		T.check(closest >= 3 - 1e-6 and closest <= 6.5, "Front 3-6,5 Studs vor der Figur (" .. closest .. ")")
		T.check(w.maxDec <= 12 + 1e-4, "Bremsen <= 12 st/s²")
		local u0 = r.u
		S.run(3)
		T.near(r.u, u0, 1e-6, "wartet, solange die Figur steht")
		-- Figur geht weg: sanft weiter
		actors = {}
		w = watcher(r)
		S.run(4, function()
			w.sample(S.env.clock.wall)
		end)
		T.check(r.u > u0 + 20, "fährt weiter")
		T.check(w.maxAcc <= 6 + 1e-4, "Anfahren <= 6 st/s²")
		-- Figur taucht plötzlich 3 Studs vor der Front auf: Auto kommt nie an sie heran
		local front = -200 + r.u + r.front
		actors = { { pos = Vector3.new(front + 4.5, 2, 0), r = 1.5, char = true } }
		local px = front + 4.5
		local worst = math.huge
		S.run(3, function()
			worst = math.min(worst, (px - 1.5) - (-200 + r.u + r.front))
		end)
		T.check(worst >= -1e-6, "nie durch die Figur (Abstand " .. worst .. ")")
		T.eq(r.v, 0, "steht vor der plötzlich aufgetauchten Figur")
		-- Figur neben der Spur (12 Studs seitlich): kein Halt
		actors = { { pos = Vector3.new(px + 60, 2, -12), r = 1.5, char = true } }
		S.run(8)
		T.check(r.v > 20, "Figur neben der Spur bremst nicht (" .. r.v .. ")")
		-- Spielerauto auf der Spur (Kreise r 3,5 längs)
		local cx = -200 + ((r.u + 120) % 880)
		if cx > 150 then
			r.u = 0
			cx = -80
		end
		actors = { { pos = Vector3.new(cx - 5, 2, 0), r = 3.5 }, { pos = Vector3.new(cx, 2, 0), r = 3.5 }, { pos = Vector3.new(cx + 5, 2, 0), r = 3.5 } }
		local minCar = math.huge
		S.run(10, function()
			minCar = math.min(minCar, (cx - 5 - 3.5) - (-200 + r.u + r.front))
		end)
		T.eq(r.v, 0, "hält vor dem Spielerauto")
		T.check(minCar >= 2.5, "Abstand zum Spielerauto (" .. minCar .. ")")
		S.T.SetActors(nil)
	end },

	{ "Verkehr 3.x: leeres, stehendes Spielerauto in der Spur hält höchstens ~4 s auf, besetztes Auto bleibt Hindernis", function(T, H)
		local S = standalone(H)
		S.loop("Loop_P", RECT)
		local car = S.car("Auto", "Loop_P", { Speed = 26 })
		S.attach()
		local r = S.rec(car)
		local actors = {}
		S.T.SetActors(function()
			return actors
		end)
		r.u, r.fresh = 40, true
		local function carAt(cx, parked)
			return { { pos = Vector3.new(cx - 5, 2, 0), r = 3.5, parked = parked }, { pos = Vector3.new(cx, 2, 0), r = 3.5, parked = parked },
				{ pos = Vector3.new(cx + 5, 2, 0), r = 3.5, parked = parked } }
		end
		-- geparktes Auto bei X 0 (u 200): erst anhalten, dann nach der Wartezeit weiterfahren
		actors = carAt(0, true)
		S.run(10)
		T.eq(r.v, 0, "hält zuerst vor dem leeren Auto")
		local u0 = r.u
		S.run(6)
		T.check(r.u > u0 + 20, "fährt nach der Wartezeit weiter (" .. (r.u - u0) .. " Studs)")
		-- Auto weg, neues besetztes Auto weiter vorn: wartet unbegrenzt
		actors = {}
		S.run(2)
		local cx = -200 + ((r.u + 100) % 880)
		if cx > 150 then
			r.u, r.fresh = 0, true
			cx = -100
		end
		actors = carAt(cx, nil)
		S.run(30)
		T.eq(r.v, 0, "besetztes Auto: wartet weiter")
		T.check((cx - 8.5) - (-200 + r.u + r.front) >= 2.5, "nie hindurch")
		S.T.SetActors(nil)
		-- echte Akteure: leeres Auto = parked, besetztes = Hindernis
		local folder = S.env.Instance.new("Folder")
		folder.Name = "PlayerCars"
		folder.Parent = S.env.workspace
		local m = S.env.Instance.new("Model")
		m.Name = "Car_1"
		local body = S.env.Instance.new("Part")
		body.Size = Vector3.new(4, 2, 8)
		body.CFrame = CFrame.new(10, 1, 0)
		body.Parent = m
		m.PrimaryPart = body
		local seat = S.env.Instance.new("VehicleSeat")
		seat.CFrame = CFrame.new(10, 2, 0)
		seat.Parent = m
		m.Parent = folder
		local list = S.T.Actors()
		local n, parked = 0, 0
		for _, a in ipairs(list) do
			if not a.char then
				n += 1
				parked += a.parked and 1 or 0
			end
		end
		T.eq(n, 3, "Spielerauto als 3 Kreise")
		T.eq(parked, 3, "leeres, stehendes Auto gilt als geparkt")
		local hum = S.env.Instance.new("Humanoid")
		seat.Occupant = hum
		list = S.T.Actors()
		parked = 0
		for _, a in ipairs(list) do
			parked += a.parked and 1 or 0
		end
		T.eq(parked, 0, "besetztes Auto ist ein echtes Hindernis")
	end },

	{ "Verkehr: Zebrastreifen mit Fußgänger - Auto hält vor dem Band, auch wenn die Figur auf der Gegenspur steht", function(T, H)
		local S = standalone(H)
		local env = S.env
		local roads = env.Instance.new("Folder")
		roads.Name = "Roads"
		roads.Parent = S.city
		local zf = env.Instance.new("Folder")
		zf.Name = "Zebrastreifen"
		zf.Parent = roads
		local z = env.Instance.new("Model")
		z.Name = "Z9"
		z:SetAttribute("Axis", "x")
		z:SetAttribute("Center", 0)
		z:SetAttribute("BandLo", 96)
		z:SetAttribute("BandHi", 104)
		z:SetAttribute("Control", "zebra")
		z.Parent = zf
		S.loop("Loop_Z", { { -200, 6.5 }, { 200, 6.5 }, { 200, 46.5 }, { -200, 46.5 } })
		local car = S.car("Auto", "Loop_Z", { Speed = 24 })
		S.attach()
		local r = S.rec(car)
		local actors = { { pos = Vector3.new(100, 2, -8), r = 1.5, char = true } } -- Gegenspur
		S.T.SetActors(function()
			return actors
		end)
		r.u, r.fresh = 150, true
		local minGap = math.huge
		S.run(10, function()
			minGap = math.min(minGap, 296 - (r.u + r.front))
		end)
		T.eq(r.v, 0, "hält vor dem besetzten Zebra")
		T.check(minGap >= 1.5 - 1e-6 and minGap <= 3, "Front 1,5-3 Studs vor dem Band (" .. minGap .. ")")
		actors = {}
		S.run(3)
		T.check(r.v > 5, "fährt weiter, wenn das Zebra frei ist")
		S.T.SetActors(nil)
	end },

	{ "Verkehr: Kurven (Bögen) langsamer und vorausschauend angebremst", function(T, H)
		local S = standalone(H)
		local pts = { { -100, 0 }, { 100, 0 } }
		for k = 1, 11 do
			local a = math.rad(-90 + 15 * k)
			table.insert(pts, { 100 + 25 * math.cos(a), 25 + 25 * math.sin(a) })
		end
		table.insert(pts, { 100, 50 })
		table.insert(pts, { -100, 50 })
		for k = 1, 11 do
			local a = math.rad(90 + 15 * k)
			table.insert(pts, { -100 + 25 * math.cos(a), 25 + 25 * math.sin(a) })
		end
		S.loop("Loop_K", pts)
		local car = S.car("Auto", "Loop_K", { Speed = 30 })
		S.attach()
		local r = S.rec(car)
		r.u, r.fresh = 0, true
		local w = watcher(r)
		local maxArc, maxStraight = 0, 0
		S.run(20, function()
			w.sample(S.env.clock.wall)
			local p = r.pos
			if p.X > 104 or p.X < -104 then
				maxArc = math.max(maxArc, r.v)
			elseif math.abs(p.X) < 40 then
				maxStraight = math.max(maxStraight, r.v)
			end
		end)
		local vc = math.sqrt(S.City.Traffic.LatAccel * 25)
		T.check(maxArc > 5 and maxArc <= vc * 1.06, "im Bogen r 25 höchstens ~" .. string.format("%.1f", vc) .. " (" .. maxArc .. ")")
		T.check(maxStraight > 27, "auf der Geraden fast Reisetempo (" .. maxStraight .. ")")
		T.check(w.maxDec <= 5.6, "Kurve sanft angebremst (" .. w.maxDec .. ")")
		T.check(w.maxAcc <= 6 + 1e-4, "Beschleunigung <= 6")
	end },

	{ "Verkehr: Kollisionsbox CanCollide=true (kein Query/Touch), übrige Teile ohne Kollision; Bus hält an der Haltestelle", function(T, H)
		local S = standalone(H)
		S.loop("Loop_R", RECT)
		local car = S.car("Auto", "Loop_R", { Speed = 26 })
		local bus = S.car("Bus", "Loop_R", { Speed = 20, Dwell = 3, DwellAt = "-100,0", Front = 12.4, Rear = 12.4, Length = 24.8 })
		S.attach()
		local box = car:FindFirstChild("Kollision")
		T.check(box ~= nil and box:IsA("BasePart"), "Kollisionsbox")
		T.eq(box.CanCollide, true, "Box: CanCollide")
		T.eq(box.CanQuery, false, "Box: kein CanQuery (Kamera/Raycasts)")
		T.eq(box.CanTouch, false, "Box: kein CanTouch")
		T.eq(box.Transparency, 1, "Box unsichtbar")
		T.eq(box.Anchored, true, "Box verankert")
		T.check(box.Size.X >= 7.8 and box.Size.Z >= 16 and box.Size.Y >= 2.4, "Box umfasst die Karosserie (" .. tostring(box.Size) .. ")")
		for _, d in ipairs(car:GetDescendants()) do
			if d:IsA("BasePart") and d ~= box then
				T.eq(d.CanCollide, false, d.Name .. ": keine eigene Kollision")
			end
		end
		T.eq(box:GetAttribute("Anim"), nil, "Box ist keine Animation")
		-- Bus: hält an der Haltestelle (Mitte bei X -100) ~3 s
		local rb = S.rec(bus)
		local rc = S.rec(car)
		rc.u = 600 -- Auto weit weg
		rb.u, rb.fresh = 0, true
		local stopT, leftT
		S.run(20, function()
			if not stopT and rb.dwellUntil then
				stopT = S.env.clock.wall
				T.near(rb.u, 100, 0.1, "Bus hält genau an der Haltestelle")
			end
			if stopT and not leftT and rb.u > 100.5 then
				leftT = S.env.clock.wall
			end
		end)
		T.check(stopT ~= nil, "Bus hält an")
		T.check(leftT ~= nil and leftT - stopT >= 2.9 and leftT - stopT < 4.5, "Bus wartet ~3 s (" .. tostring(leftT and stopT and leftT - stopT) .. ")")
	end },

	{ "Echte Stadt (Fixture): Haltelinien mit Ampelköpfen, Kollisionsboxen, Rotlicht-Disziplin, keine Überlappung, kein Stillstand", function(T, H)
		local g = H.Garage({ placeKind = "openworld", startTime = NOW })
		local p = g:Join(1001, { name = "Tester" })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(1.5)
		local A = g:Find("Workspace.City.Animated")
		T.check(A ~= nil, "City.Animated")
		local loops = A.TrafficLoops
		local masts = A.Ampeln:GetChildren()
		T.eq(#masts, 16, "Ampelmasten (K-West 4, K-Ost 4, Plaza 4, Querachse 4)")
		-- Ampelköpfe: Linsenseite = lokales +Z des Signalkopfs
		local heads = {}
		for _, m in ipairs(masts) do
			T.check(m:GetAttribute("PedPhase") == "NS" or m:GetAttribute("PedPhase") == "WE", m.Name .. ": PedPhase")
			local head = m:FindFirstChild("Signalkopf")
			if head then
				T.check(m:FindFirstChild("Red") and m:FindFirstChild("Amber") and m:FindFirstChild("Green"), m.Name .. ": drei Linsen")
				table.insert(heads, { pos = head.Position, face = head.CFrame.ZVector, serves = m:GetAttribute("Serves"), name = m.Name })
			end
		end
		local lines = 0
		for _, key in ipairs({ "A", "B1", "B2" }) do
			local f = loops:FindFirstChild("Loop_" .. key)
			T.check(f and type(f:GetAttribute("Waypoints")) == "string", key .. ": Wegpunkte als Attribut")
			local s = f and f:GetAttribute("StopLines")
			T.check(type(s) == "string", key .. ": StopLines")
			local pts = {}
			for x, y, z in string.gmatch(f:GetAttribute("Waypoints"), "(%-?[%d%.]+),(%-?[%d%.]+),(%-?[%d%.]+)") do
				table.insert(pts, Vector3.new(tonumber(x), tonumber(y), tonumber(z)))
			end
			for x, z, serves in string.gmatch(s or "", "(%-?[%d%.]+),(%-?[%d%.]+),(%a+)") do
				lines += 1
				local pt = Vector3.new(tonumber(x), Y, tonumber(z))
				-- Fahrtrichtung am Haltepunkt
				local dir
				for i = 1, #pts do
					local a, b = pts[i], pts[i % #pts + 1]
					local ab = b - a
					local f2 = ab:Dot(pt - a) / ab:Dot(ab)
					if f2 >= -1e-6 and f2 <= 1 + 1e-6 and ((a + ab * f2) - pt).Magnitude < 0.05 then
						dir = Vector3.new(ab.X, 0, ab.Z).Unit
						break
					end
				end
				T.check(dir ~= nil, key .. ": Haltelinie (" .. x .. "," .. z .. ") liegt auf der Schleife")
				if dir then
					local ok = false
					for _, h in ipairs(heads) do
						local d = h.pos - pt
						if h.serves == serves and h.face:Dot(dir) < -0.9 and Vector3.new(d.X, 0, d.Z).Magnitude < 45 and d:Dot(dir) > -1 then
							ok = true
						end
					end
					T.check(ok, key .. ": Haltelinie (" .. x .. "," .. z .. ", " .. serves .. ") hat einen Fahrzeugkopf, der dem Verkehr entgegenblickt")
				end
			end
		end
		T.eq(lines, 14, "14 Haltelinien (Meile 6, Marktstraße 8)")
		-- Laufzeit: alle Verkehrsautos mit Kollisionsbox, Disziplin über drei Umläufe
		local City = g:ClientModule(p, "Mini.CityClient")
		local recs = g:InClient(p, function()
			return City._test.TrafficRecords()
		end)
		T.check(#recs >= 13, "Verkehrsautos registriert (" .. #recs .. ")")
		for _, r in ipairs(recs) do
			local box = r.inst:FindFirstChild("Kollision")
			T.check(box and box.CanCollide == true and box.CanQuery == false, r.inst.Name .. ": Kollisionsbox")
		end
		local u0, travelled = {}, {}
		local prevS = {}
		local violations, overlaps = {}, {}
		for _, r in ipairs(recs) do
			u0[r] = r.u
			travelled[r] = 0
		end
		local last = {}
		for _, r in ipairs(recs) do
			last[r] = r.u
		end
		local redStart = { Meile = 14.5, Markt = 30.5 }
		local boxConflicts = {}
		local function inBox(pos, cx)
			return pos and math.abs(pos.X - cx) < 13 and math.abs(pos.Z) < 13
		end
		for _ = 1, math.floor(96 / 0.25) do
			g:Advance(0.25)
			local tt = g:Now() % 32
			for _, r in ipairs(recs) do
				local L = r.path.total
				local du = (r.u - last[r]) % L
				if du < L / 2 then
					travelled[r] += du
				end
				last[r] = r.u
				for _, st in ipairs(r.path.lines) do
					local gline = (st.d - r.u) % L
					local s = gline < L / 2 and gline - r.front or -1
					local key = tostring(r) .. tostring(st)
					local ps = prevS[key]
					if ps and ps >= 0 and ps < 40 and s < 0 then
						local state = City.SignalState(st.serves, g:Now())
						local since = (tt - redStart[st.serves]) % 32
						if state == "red" and since > 1.75 then
							table.insert(violations, string.format("%s bei %.1f s (%s)", r.inst.Name, tt, st.serves))
						end
					end
					prevS[key] = s
				end
				for _, cx in ipairs({ -152, 152 }) do
					if inBox(r.pos, cx) and r.inst:GetAttribute("Loop") == "A" then
						for _, o in ipairs(recs) do
							local lk = o.inst:GetAttribute("Loop")
							if (lk == "B1" or lk == "B2") and inBox(o.pos, cx) then
								table.insert(boxConflicts, string.format("%s/%s bei %.1f s", r.inst.Name, o.inst.Name, tt))
							end
						end
					end
				end
				for _, o in ipairs(r.path.cars) do
					if o ~= r then
						local gap = (o.u - r.u) % L
						if gap < L / 2 and gap - r.front - o.rear < 1 then
							table.insert(overlaps, r.inst.Name .. "/" .. o.inst.Name)
						end
					end
				end
			end
		end
		T.eq(#violations, 0, "kein Auto fährt bei Rot über die Haltelinie: " .. table.concat(violations, ", "))
		T.eq(#overlaps, 0, "keine Überlappung auf derselben Schleife: " .. table.concat(overlaps, ", "))
		T.eq(#boxConflicts, 0, "nie Meile- und Marktauto zugleich im Kreuzungsfeld: " .. table.concat(boxConflicts, ", "))
		for _, r in ipairs(recs) do
			if r.inst:GetAttribute("Loop") == "A" and r.path.crossings then
				T.eq(#r.path.crossings, 14, "Schleife A: 14 Zebra-Eintritte (Z1-Z5, Z8, Z9 je Richtung)")
				break
			end
		end
		for _, r in ipairs(recs) do
			T.check(travelled[r] > 150, r.inst.Name .. ": fährt (kein Stillstand, " .. math.floor(travelled[r]) .. " Studs in 96 s)")
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
