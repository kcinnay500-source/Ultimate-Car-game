-- Welt: Grundstücke aus C.PlotSlots (auch um 180° gedreht), Reisen in der Stadt, Stadt-Spawn, Ankunftspunkte.
local Flow

local function localPos(plot, pos)
	return plot:GetPivot():Inverse() * pos
end

-- Achsparallele Hülle aller BaseParts eines Modells (Weltkoordinaten)
local function bounds(model)
	local lo, hi
	for _, x in ipairs(model:GetDescendants()) do
		if x:IsA("BasePart") and x.Transparency < 1 then
			local half = x.Size / 2
			local cf = x.CFrame
			for _, sx in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local corner = cf * Vector3.new(half.X * sx, 0, half.Z * sz)
					lo = lo and Vector3.new(math.min(lo.X, corner.X), 0, math.min(lo.Z, corner.Z)) or corner
					hi = hi and Vector3.new(math.max(hi.X, corner.X), 0, math.max(hi.Z, corner.Z)) or corner
				end
			end
		end
	end
	return lo, hi
end

local function overlap(aLo, aHi, bLo, bHi)
	return aLo.X < bHi.X and bLo.X < aHi.X and aLo.Z < bHi.Z and bLo.Z < aHi.Z
end

local function rotated(slot)
	return function(g)
		local C = g:Config()
		C.PlotSlots[slot] = { x = C.PlotSlots[slot].x, z = C.PlotSlots[slot].z, rot = 180 }
	end
end

return {
	{ "C.PlotSlots: 8 Einträge, 0 oder 180 Grad; Plots aller 8 Slots überlappen sich nicht", function(T, H)
		local g = H.Garage()
		local C = g:Config()
		T.eq(#C.PlotSlots, C.MaxPlots, "ein Eintrag je Grundstück")
		for i, s in ipairs(C.PlotSlots) do
			T.check(type(s.x) == "number" and type(s.z) == "number", "Slot " .. i .. " hat x und z")
			T.check(s.rot == 0 or s.rot == 180, "Slot " .. i .. " rot 0 oder 180")
		end
		local players = {}
		for i = 1, C.MaxPlots do
			players[i] = g:Join(900 + i)
		end
		g:Advance(1)
		local boxes = {}
		for i, p in ipairs(players) do
			local plot = g:Plot(p)
			if T.check(plot ~= nil, "Plot " .. i) then
				local s = C.PlotSlots[i]
				local pivot = plot:GetPivot()
				T.check((pivot.Position - Vector3.new(s.x, 0, s.z)).Magnitude < 0.01, "Plot " .. i .. " steht am Slot")
				local lo, hi = bounds(plot)
				boxes[i] = { lo = lo, hi = hi }
			end
		end
		for i = 1, #boxes do
			for j = i + 1, #boxes do
				T.check(not overlap(boxes[i].lo, boxes[i].hi, boxes[j].lo, boxes[j].hi), "Plots " .. i .. " und " .. j .. " überlappen nicht")
			end
		end
		-- Mit Stadt (worldgen): keine Plot-Hülle schneidet ein Stadtgebäude (Boden und Straßen ausgenommen)
		local city = g:Find("Workspace.City")
		if city then
			local ignore = {}
			for _, name in ipairs({ "Ground", "Roads", "Arrivals", "Lights" }) do
				local f = city:FindFirstChild(name)
				if f then
					ignore[f] = true
				end
			end
			for _, x in ipairs(city:GetDescendants()) do
				if x:IsA("BasePart") and x.CanCollide then
					local skip = false
					for folder in pairs(ignore) do
						skip = skip or x:IsDescendantOf(folder)
					end
					if not skip then
						for i, b in ipairs(boxes) do
							local half = x.Size / 2
							local lo = x.Position - Vector3.new(half.X, 0, half.Z)
							local hi = x.Position + Vector3.new(half.X, 0, half.Z)
							T.check(not overlap(b.lo, b.hi, lo, hi), "Plot " .. i .. " überlappt Stadtteil " .. x:GetFullName())
						end
					end
				end
			end
		end
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Grundstück um 180° gedreht: Ankunft, Stationen, Reparaturablauf", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({ before = rotated(1) })
		local p = g:Join(1001)
		g:Advance(1)
		local plot = g:Plot(p)
		T.check(plot:GetPivot().LookVector:Dot(Vector3.new(0, 0, 1)) > 0.99, "Plot zeigt in die Gegenrichtung (rot 180)")
		-- Ankunft am Empfang: 6 Studs vor der Station im Plotsystem, über dem Plotboden
		local home = g:Station(p, "home")
		local rootLocal = localPos(plot, g:Root(p).Position)
		local homeLocal = localPos(plot, home.Position)
		T.near(rootLocal.Z - homeLocal.Z, 6, 0.01, "6 Studs vor der Station (plotlokal)")
		T.near(rootLocal.X, homeLocal.X, 0.01, "gleiche Querposition (plotlokal)")
		T.check(rootLocal.Y > 3 and rootLocal.Y < 4, "über dem Plotboden")
		for _, key in ipairs({ "tools", "parts", "upgrades", "workshop" }) do
			g:Advance(0.2)
			g:Send(p, "travel", { key = key })
			local dist = (g:Root(p).Position - g:Station(p, key).Position).Magnitude
			T.check(dist <= (key == "tools" and 9 or 10), "travel " .. key .. " landet in Reichweite (" .. string.format("%.1f", dist) .. ")")
		end
		-- Kompletter 2.4.0-Ablauf auf dem gedrehten Grundstück
		local receipt = Flow.CompleteInspection(T, g, p)
		T.check(receipt ~= nil and receipt.money > 0, "Auftrag auf gedrehtem Grundstück abgerechnet")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Grundstück um 180° gedreht: Hebebühne und Rolltor", function(T, H)
		Flow = Flow or H.Load("tests/lib/garage_flow.lua")
		local g = H.Garage({ before = rotated(1) })
		local C = g:Config()
		local p = g:Join(1001)
		local other = g:Join(1002)
		g:Advance(1)
		local plot = g:Plot(p)
		local j = Flow.AcceptInspection(T, g, p)
		if not j then
			return
		end
		local car = g:Car(p, j.id)
		local bay = plot.Bays.Bay_1
		local origin = bay.CarOrigin.CFrame
		T.check((car:GetPivot().Position - origin.Position).Magnitude < 1, "Auto an CarOrigin")
		local lift0 = bay.MovingLift:GetPivot()
		g:Teleport(p, bay.LiftControl, Vector3.new(0, 0, 1))
		g:Advance(0.2)
		g:Send(p, "lift", { id = j.id })
		g:Advance(2.5)
		local pos = car:GetPivot().Position
		T.near(pos.Y - origin.Position.Y, C.LiftHeight, 0.01, "Auto angehoben")
		T.near((Vector3.new(pos.X, 0, pos.Z) - Vector3.new(origin.Position.X, 0, origin.Position.Z)).Magnitude, 0, 0.01, "Auto bleibt über der Bühne")
		T.near(bay.MovingLift:GetPivot().Position.Y - lift0.Position.Y, C.LiftHeight, 0.01, "Bühne angehoben")
		T.check(car:GetPivot().LookVector:Dot(origin.LookVector) > 0.999, "Ausrichtung bleibt")
		g:Advance(0.2)
		g:Send(p, "lift", { id = j.id })
		g:Advance(2.5)
		T.near(car:GetPivot().Position.Y, origin.Position.Y, 0.01, "Auto abgesenkt")
		-- Rolltor: anderer Spieler steht im Tor (plotlokal im Torbereich) -> Schließen verweigert
		local door = plot.RollerDoor
		local closed = door.ClosedOrigin
		g:Teleport(other, closed.Position + Vector3.new(0, 2, 0))
		-- vor dem Schalter stehen (plotlokal 3 Studs hallenseitig, außerhalb des Torbereichs)
		g:Teleport(p, plot:GetPivot() * (localPos(plot, door.Control.Position) + Vector3.new(0, 0, -3)))
		g:Advance(0.2)
		local m = g:Mark()
		g:Send(p, "door")
		T.check(g:HasToast(p, "Torbereich ist belegt", m), "Torbereich belegt erkannt (gedreht)")
		T.eq(door:GetAttribute("Open"), true, "Tor bleibt offen")
		-- plotlokal 5 Studs vor dem Tor ist frei
		g:Teleport(other, plot:GetPivot() * (localPos(plot, closed.Position) + Vector3.new(0, 2, 5)))
		g:Advance(0.2)
		m = g:Mark()
		g:Send(p, "door")
		g:Advance(2.5)
		T.eq(door:GetAttribute("Open"), false, "Tor geschlossen")
		T.near(door.Panel.Size.Y, 11.8, 0.01, "Torblatt unten")
		T.check(door.Panel.CanCollide, "geschlossenes Tor kollidiert")
		g:Advance(0.2)
		g:Send(p, "door")
		g:Advance(2.5)
		T.eq(door:GetAttribute("Open"), true, "Tor wieder offen")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },

	{ "Stadt: Spawn am CitySpawn, Plot-Spawn aus, Reise zu Ankunftspunkten und zurück", function(T, H)
		local g = H.Garage({ before = function(g)
			g:BuildCity({ arrivals = { { key = "presse", pos = Vector3.new(30, 0.5, -320) } }, spawnAt = Vector3.new(0, 0.5, -300) })
			local model = Instance.new("Model")
			model.Name = "tuning"
			local base = Instance.new("Part")
			base.Name = "Boden"
			base.CFrame = CFrame.new(60, 1, -320)
			base.Parent = model
			model.PrimaryPart = base
			model.Parent = g:Find("Workspace.City.Arrivals")
		end })
		local L = g:MiniShared("MiniLocale")
		local p = g:Join(1001)
		g:Advance(1)
		local plot = g:Plot(p)
		T.eq(plot.Start.Enabled, false, "Plot-Spawn aus, wenn es den Stadt-Spawn gibt")
		local home = g:Station(p, "home")
		T.check((g:Root(p).Position - home.Position).Magnitude < 12, "nach dem Spawn in der eigenen Werkstatt")
		local arrival = g:Find("Workspace.City.Arrivals.presse")
		T.eq(g:Act(p, "mini_travel", { key = "presse", rid = 1 }), "ok", "Reise")
		local expected = (arrival.CFrame * CFrame.new(0, arrival.Size.Y / 2 + 3, 0)).Position
		T.near((g:Root(p).Position - expected).Magnitude, 0, 0.01, "am Ankunftspunkt")
		T.eq(g:Act(p, "mini_travel", { key = "workshop", rid = 2 }), "cooldown", "Abklingzeit 3 s")
		g:Advance(3.1)
		g:Act(p, "mini_travel", { key = "tuning", rid = 3 })
		T.near((g:Root(p).Position - Vector3.new(60, 4, -320)).Magnitude, 0, 0.01, "Model-Ankunft: Pivot + 3")
		g:Advance(3.1)
		local m = g:Mark()
		g:Act(p, "mini_travel", { key = "gibtsnicht", rid = 4 })
		T.check(g:HasToast(p, L.T("travel_unknown"), m), "unbekanntes Ziel: Hinweis")
		g:Advance(3.1)
		g:Act(p, "mini_travel", { key = "workshop", rid = 5 })
		T.check((g:Root(p).Position - home.Position).Magnitude < 12, "zurück in der eigenen Werkstatt")
		-- ohne Stadt bleibt der Plot-Spawn aktiv (2.4.0)
		local g2 = H.Garage()
		local p2 = g2:Join(1002)
		g2:Advance(1)
		T.eq(g2:Plot(p2).Start.Enabled, true, "ohne Stadt: Plot-Spawn aktiv")
		T.eq(#g:Errors() + #g2:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText() .. g2:ErrorText())
	end },

	{ "Station mit Kind-Part 'Arrival' legt die Ankunft fest", function(T, H)
		local g = H.Garage({ before = function(g)
			local template = g:Find("Workspace.Werkstatt")
			local station = template.Stations.parts
			local arrival = Instance.new("Part")
			arrival.Name = "Arrival"
			arrival.Transparency = 1
			arrival.CanCollide = false
			arrival.CFrame = station.CFrame * CFrame.new(0, 0, -4)
			arrival.Parent = station
		end })
		local p = g:Join(1001)
		g:Advance(1)
		g:Send(p, "travel", { key = "parts" })
		local arrival = g:Station(p, "parts").Arrival
		T.near((g:Root(p).Position - (arrival.CFrame * CFrame.new(0, 3.5, 0)).Position).Magnitude, 0, 0.01, "Ankunft am Arrival-Part")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
