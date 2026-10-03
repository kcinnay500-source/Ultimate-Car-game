-- Weltrand 3.0 (tools/worldgen/horizon.py) im Fixture: Vom Stadtzentrum aus in 16 Richtungen trifft man zu Fuß und
-- mit dem Auto immer zuerst auf den natürlichen Rand (Hügel/Fels/Baumstamm, sichtbar und kollidierend) und dahinter
-- auf die unsichtbare Sicherheitswand "Grenze", bevor der Boden endet - der Boden reicht noch weit dahinter (kein
-- sichtbares Nichts). Die Skyline ist reine Kulisse (keine Kollision/Abfrage/Berührung/Schatten) und steht auf Boden.

local STEP = 2
local R_MAX = 2400

local function inside(p, pos)
	local l = p.CFrame:PointToObjectSpace(pos)
	local h = p.Size / 2
	if p:IsA("Part") and p.Shape == Enum.PartType.Ball then
		return l.Magnitude <= h.X
	elseif p:IsA("Part") and p.Shape == Enum.PartType.Cylinder then
		return math.abs(l.X) <= h.X and (l.Y * l.Y + l.Z * l.Z) <= h.Y * h.Y
	end
	if math.abs(l.X) > h.X or math.abs(l.Y) > h.Y or math.abs(l.Z) > h.Z then
		return false
	end
	if p:IsA("WedgePart") then
		return l.Y * h.Z - l.Z * h.Y <= 1e-6
	end
	return true
end

-- Rasterschlüssel (ohne "-0": math.floor(-0 / 64) ergäbe -0)
local function key(gx, gz)
	return string.format("%d:%d", gx == 0 and 0 or gx, gz == 0 and 0 or gz)
end

-- Raster der Parts (XZ-Hülle) für schnelle Punktabfragen
local function index(parts)
	local grid = {}
	for _, p in ipairs(parts) do
		local cf, h = p.CFrame, p.Size / 2
		local ex = math.abs(cf.RightVector.X) * h.X + math.abs(cf.UpVector.X) * h.Y + math.abs(cf.LookVector.X) * h.Z
		local ez = math.abs(cf.RightVector.Z) * h.X + math.abs(cf.UpVector.Z) * h.Y + math.abs(cf.LookVector.Z) * h.Z
		local x0, x1 = math.floor((cf.Position.X - ex) / 64), math.floor((cf.Position.X + ex) / 64)
		local z0, z1 = math.floor((cf.Position.Z - ez) / 64), math.floor((cf.Position.Z + ez) / 64)
		for gx = x0, x1 do
			for gz = z0, z1 do
				local k = key(gx, gz)
				grid[k] = grid[k] or {}
				table.insert(grid[k], p)
			end
		end
	end
	return function(pos)
		local lst = grid[key(math.floor(pos.X / 64), math.floor(pos.Z / 64))]
		if lst then
			for _, p in ipairs(lst) do
				if inside(p, pos) then
					return p
				end
			end
		end
		return nil
	end
end

local function collect(g)
	local city = g:Find("Workspace.City")
	local floor, walls, natural, solid = {}, {}, {}, {}
	for _, p in ipairs(city:GetDescendants()) do
		if p:IsA("BasePart") then
			if p.Name == "Grasplatte" or p.Name == "Fernboden" then
				table.insert(floor, p)
			end
			if p.Name == "Grenze" and p.CanCollide then
				table.insert(walls, p)
			end
			-- 3.x: auch der Naturrand um Lobby/Tycoon (City.Horizon.Naturrand, Place "all")
			local zoneEdge = city:FindFirstChild("Horizon") and city.Horizon:FindFirstChild("Naturrand")
			if p.CanCollide and p.Transparency < 0.95 and p.Name ~= "Grasplatte"
				and (p:IsDescendantOf(city.Ground) or (zoneEdge ~= nil and p:IsDescendantOf(zoneEdge))) then
				table.insert(natural, p)
			end
		end
	end
	for _, zn in ipairs({ "Lobby", "Tycoon" }) do
		local z = g:Find("Workspace." .. zn)
		if z then
			for _, p in ipairs(z:GetDescendants()) do
				if p:IsA("BasePart") and p.Name == "Grasplatte" then
					table.insert(floor, p)
				end
			end
		end
	end
	return city, index(floor), index(walls), index(natural), #walls, #natural
end

return {
	{ "Weltrand: in 16 Richtungen erst Naturrand, dann Grenze, Boden reicht weit dahinter", function(T, H)
		local g = H.Garage({ noServer = true })
		local city, floorAt, wallAt, naturalAt, nWalls, nNatural = collect(g)
		T.check(city ~= nil and city:FindFirstChild("Ground") ~= nil, "City.Ground")
		T.check(nWalls >= 4, "Grenz-Wände " .. nWalls)
		T.check(nNatural >= 100, "natürliche Randteile " .. nNatural)
		T.check(city.Ground:FindFirstChild("Naturrand") ~= nil, "Ground.Naturrand")
		for k = 0, 15 do
			local a = 2 * math.pi * k / 16
			local ux, uz = math.cos(a), math.sin(a)
			local lastWall, groundEnd, firstWall
			local r = 0
			while r < R_MAX do
				local x, z = ux * r, uz * r
				if not floorAt(Vector3.new(x, -1.2, z)) then
					groundEnd = r
					break
				end
				-- Fußgänger (Kopfhöhe 5), Auto (3), Sprung (12) und hoch (90): die Grenze sperrt alles
				local w = wallAt(Vector3.new(x, 3, z)) and wallAt(Vector3.new(x, 12, z)) and wallAt(Vector3.new(x, 90, z))
				if w then
					lastWall = r
					firstWall = firstWall or r
				end
				r += STEP
			end
			local who = string.format("Richtung %d°: ", math.floor(math.deg(a) + 0.5))
			if T.check(lastWall ~= nil, who .. "Grenze vorhanden") then
				T.check(groundEnd == nil or groundEnd - lastWall >= 100, who .. "Boden reicht >= 100 hinter die Grenze ("
					.. tostring(groundEnd and groundEnd - lastWall) .. ")")
				T.check(lastWall > 500, who .. "Grenze außerhalb der Stadt (r " .. lastWall .. ")")
				-- vor der äußersten Grenze: sichtbares, kollidierendes Naturhindernis in Bein-/Stoßstangenhöhe
				local nat
				local rr = lastWall
				while rr > lastWall - 150 and not nat do
					for _, y in ipairs({ 1, 3, 5 }) do
						nat = nat or naturalAt(Vector3.new(ux * rr, y, uz * rr))
					end
					rr -= 1
				end
				T.check(nat ~= nil, who .. "natürliches Hindernis vor der Grenze")
			end
		end
	end },

	{ "3.x Zonenrand (Place all): von Lobby- und Tycoon-Spawn aus erst Boden, dann Hecke/Baum/Fels, dann Grenze - kein Weg auf den Fernboden oder ins Nichts", function(T, H)
		local g = H.Garage({ noServer = true })
		local city, floorAt, wallAt, naturalAt = collect(g)
		local edge = city:FindFirstChild("Horizon") and city.Horizon:FindFirstChild("Naturrand")
		T.check(edge ~= nil, "City.Horizon.Naturrand")
		local spawns = { Lobby = Vector3.new(0, 0, -676), Tycoon = Vector3.new(0, 0, 850) }
		for zn, origin in pairs(spawns) do
			local zone = g:Find("Workspace." .. zn)
			if T.check(zone ~= nil, zn .. " im Place") then
				local cf, size = zone:GetBoundingBox()
				local function inZone(x, z)
					return math.abs(x - cf.Position.X) <= size.X / 2 and math.abs(z - cf.Position.Z) <= size.Z / 2
				end
				for k = 0, 15 do
					local a = 2 * math.pi * k / 16
					local ux, uz = math.cos(a), math.sin(a)
					local who = string.format("%s Richtung %d°: ", zn, math.floor(math.deg(a) + 0.5))
					local r, firstWall, void = 0, nil, nil
					while r < 1200 do
						local x, z = origin.X + ux * r, origin.Z + uz * r
						if not inZone(x, z) and not floorAt(Vector3.new(x, -1.2, z)) then
							void = r
							break
						end
						if not firstWall and wallAt(Vector3.new(x, 3, z)) and wallAt(Vector3.new(x, 12, z)) and wallAt(Vector3.new(x, 90, z)) then
							firstWall = r
						end
						if firstWall and r >= firstWall + 50 then
							break
						end
						r += STEP
					end
					T.check(void == nil, who .. "kein Bodenende vor der Grenze (" .. tostring(void) .. ")")
					if T.check(firstWall ~= nil, who .. "Grenze vorhanden") then
						T.check(firstWall < 260, who .. "Grenze dicht an der Zone (r " .. firstWall .. ")")
						local nat
						local rr = firstWall
						while rr > firstWall - 30 and not nat do
							for _, y in ipairs({ 1, 3, 5 }) do
								nat = nat or naturalAt(Vector3.new(origin.X + ux * rr, y, origin.Z + uz * rr))
							end
							rr -= 1
						end
						T.check(nat ~= nil, who .. "Hecke/Baum/Fels vor der Grenze")
					end
				end
			end
		end
	end },

	{ "Weltrand: Grasplatte unter allem Befahrbaren, Hügel kollidieren, Grenze unsichtbar", function(T, H)
		local g = H.Garage({ noServer = true })
		local city = g:Find("Workspace.City")
		local grass = city.Ground:FindFirstChild("Grasplatte")
		T.check(grass ~= nil and grass.Size.X >= 1500 and grass.Size.Z >= 1200, "große Grasplatte")
		-- Teststrecke (bis Z 560) und Große Werkstatt (bis X -647) liegen auf der Grasplatte
		local function onGrass(x, z)
			return math.abs(x - grass.Position.X) <= grass.Size.X / 2 and math.abs(z - grass.Position.Z) <= grass.Size.Z / 2
		end
		T.check(onGrass(-650, 0) and onGrass(0, 560) and onGrass(300, 560) and onGrass(-300, 560), "Gelände auf der Grasplatte")
		local hills, walls = 0, 0
		for _, p in ipairs(city.Ground.Naturrand:GetDescendants()) do
			if p:IsA("BasePart") then
				if p.Name == "Huegel" or p.Name == "Kuppe" then
					hills += 1
					T.check(p.CanCollide and p.Material == Enum.Material.Grass, "Hügel kollidiert, Gras")
				elseif p.Name == "Grenze" then
					walls += 1
					T.check(p.Transparency >= 1 and p.CanCollide and not p.CastShadow, "Grenze unsichtbar")
				end
			end
		end
		T.check(hills >= 40, "Hügelkette " .. hills)
		T.eq(walls, 4, "4 Grenz-Wände")
	end },

	{ "Skyline: reine Kulisse rundum, auf Boden, außerhalb von Lobby und Tycoon, Budget", function(T, H)
		local g = H.Garage({ noServer = true })
		local city = g:Find("Workspace.City")
		local sky = g:Find("Workspace.City.Horizon.Skyline")
		if not T.check(sky ~= nil, "City.Horizon.Skyline") then
			return
		end
		local floor = {}
		for _, p in ipairs(city:GetDescendants()) do
			if p:IsA("BasePart") and (p.Name == "Grasplatte" or p.Name == "Fernboden") then
				table.insert(floor, p)
			end
		end
		local floorAt = index(floor)
		local n, towers, quad = 0, 0, {}
		local zones = {}
		for _, zn in ipairs({ "Lobby", "Tycoon" }) do
			local z = g:Find("Workspace." .. zn)
			if z then
				local cf, size = z:GetBoundingBox()
				table.insert(zones, { cf.Position, size })
			end
		end
		for _, m in ipairs(sky:GetChildren()) do
			towers += 1
			local body = m:FindFirstChild("Koerper")
			if T.check(body ~= nil, m.Name .. ": Körper") then
				local base = Vector3.new(body.Position.X, -1.2, body.Position.Z)
				T.check(floorAt(base) ~= nil, m.Name .. " steht auf Boden")
				local top = body.Position.Y + body.Size.Y / 2
				T.check(top >= 60 and top <= 265, m.Name .. ": Höhe " .. math.floor(top))
				local q = (body.Position.X > 0 and "O" or "W") .. (body.Position.Z > 0 and "S" or "N")
				quad[q] = (quad[q] or 0) + 1
				for _, zz in ipairs(zones) do
					local c, s = zz[1], zz[2]
					local apart = math.abs(body.Position.X - c.X) > (s.X + body.Size.X) / 2
						or math.abs(body.Position.Z - c.Z) > (s.Z + body.Size.Z) / 2
					T.check(apart, m.Name .. " außerhalb der Zonen")
				end
			end
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then
					n += 1
					T.check(not p.CanCollide and not p.CanQuery and not p.CanTouch and not p.CastShadow, p:GetFullName() .. ": reine Kulisse")
				end
			end
		end
		T.check(n <= 700, "Skyline-Budget: " .. n .. " Parts")
		T.check(towers >= 60, "Türme: " .. towers)
		for _, q in ipairs({ "ON", "OS", "WN", "WS" }) do
			T.check((quad[q] or 0) >= 10, "Türme im Viertel " .. q .. ": " .. tostring(quad[q]))
		end
	end },
}
