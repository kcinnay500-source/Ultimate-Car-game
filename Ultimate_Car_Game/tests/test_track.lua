-- Teststrecke 3.0 (Grand-Prix-Kurs): TrackRules.Layout passt zur gebauten Strecke (City.Track: Layout, Length,
-- Checkpoints in Fahrtrichtung, quer über die Fahrbahn, auf Asphalt), alte Oval-Bestzeiten verfallen beim Laden,
-- eine ehrliche Runde mit dem langsamsten Katalog-Auto ist gültig, eine Abkürzung (Checkpoint ausgelassen) zählt
-- nicht, und der Tab zeigt die Streckenführung.

local function cityTrack(g)
	return g:Find("Workspace.City.Track")
end

local function seq(track)
	local out = {}
	local cps = track:FindFirstChild("Checkpoints")
	local i = 1
	while cps and cps:FindFirstChild("CP" .. i) do
		table.insert(out, cps:FindFirstChild("CP" .. i))
		i += 1
	end
	table.insert(out, track:FindFirstChild("Ziel"))
	return out
end

local function flat(v)
	return Vector3.new(v.X, 0, v.Z)
end

return {
	{ "Grand-Prix-Kurs: TrackRules.Layout passt zu City.Track (Version, Länge, Checkpoints)", function(T, H)
		local g = H.Garage({ noServer = true })
		local TR = g:MiniShared("TrackRules")
		local L = TR.Layout
		T.check(type(L) == "table" and L.version == 2 and L.name == "Grand-Prix-Kurs", "Layout 2")
		local track = cityTrack(g)
		if not T.check(track ~= nil, "City.Track im Fixture") then
			return
		end
		T.eq(track:GetAttribute("Layout"), L.version, "Attribut Layout = TrackRules.Layout.version")
		T.check(math.abs((track:GetAttribute("Length") or 0) - L.length) <= 1, "Länge " .. tostring(track:GetAttribute("Length")))
		T.check(L.length > 1100, "länger als das alte Oval (~780)")
		local list = seq(track)
		T.eq(#list - 1, L.checkpoints, "Anzahl Zwischenpunkte")
		T.check(#list <= 20, "höchstens 20 Abschnitte (maxRunSeconds)")
		for _, cp in ipairs(list) do
			T.check(cp:IsA("BasePart") and cp.CanTouch and not cp.CanCollide and cp.Transparency >= 1, cp.Name .. ": unsichtbarer Auslöser")
			T.check(cp.Size.X >= 26 and cp.Size.Z >= 4 and cp.Size.Y >= 10, cp.Name .. ": quer über die Fahrbahn, dick genug")
		end
	end },

	{ "Grand-Prix-Kurs: Checkpoints liegen in Fahrtrichtung hintereinander auf Asphalt, Start vor dem Ziel", function(T, H)
		local g = H.Garage({ noServer = true })
		local track = cityTrack(g)
		local list = seq(track)
		local spawn = g:Find("Workspace.City.CarSpawns.track")
		T.check(spawn ~= nil, "CarSpawns.track")
		-- Asphalt unter jedem Checkpoint: ein Belag-Teil der Teststrecke enthält den Punkt knapp unter der Oberseite
		local belag = g:Find("Workspace.City.Districts.Teststrecke.Teststrecke.Belag")
		T.check(belag ~= nil, "Belag")
		local function onRoad(pos)
			for _, p in ipairs(belag:GetDescendants()) do
				if p:IsA("BasePart") then
					local l = p.CFrame:PointToObjectSpace(Vector3.new(pos.X, -1.0, pos.Z))
					local h = p.Size / 2
					if p:IsA("WedgePart") then
						if math.abs(l.X) <= h.X + 0.05 and math.abs(l.Y) <= h.Y + 0.05 and math.abs(l.Z) <= h.Z + 0.05
							and l.Y * h.Z - l.Z * h.Y <= 0.05 then
							return true
						end
					elseif math.abs(l.X) <= h.X + 0.05 and math.abs(l.Y) <= h.Y + 0.05 and math.abs(l.Z) <= h.Z + 0.05 then
						return true
					end
				end
			end
			return false
		end
		local total = 0
		local prev = spawn and spawn.Position
		for i, cp in ipairs(list) do
			T.check(onRoad(cp.Position), cp.Name .. " auf dem Belag")
			if prev then
				local d = flat(cp.Position - prev).Magnitude
				T.check(d > 20 and d < 400, cp.Name .. ": Abstand zum vorigen " .. math.floor(d))
				total += d
			end
			prev = cp.Position
			-- Fahrtrichtung: die Rückseite (LookVector) zeigt ungefähr zum nächsten Punkt
			local nxt = list[i + 1] or list[1]
			local dir = flat(nxt.Position - cp.Position).Unit
			T.check(cp.CFrame.LookVector:Dot(dir) > 0.2 or i == #list, cp.Name .. " zeigt in Fahrtrichtung")
		end
		T.check(total > 900, "Luftlinie der Runde " .. math.floor(total))
		local ziel = list[#list]
		T.check(spawn and spawn.CFrame.LookVector:Dot(flat(ziel.Position - spawn.Position).Unit) > 0.95, "Start schaut aufs Ziel")
		T.check(spawn and flat(ziel.Position - spawn.Position).Magnitude > 12, "Start berührt die Ziellinie nicht")
	end },

	{ "TrackRules.Load: Bestzeiten vom alten Oval verfallen, neue bleiben, idempotent", function(T, H)
		local g = H.Garage({ noServer = true })
		local TR = g:MiniShared("TrackRules")
		local v = TR.Layout.version
		T.eq(TR.Default().layout, v, "Default mit Layout")
		local old = TR.Load({ best = 9.4, rewardedBest = 9.4, runs = 7 })
		T.eq(old.best, 0, "Oval-Bestzeit (ohne layout, < legacyMin) verfällt")
		T.eq(old.rewardedBest, 0, "belohnte Oval-Bestzeit verfällt")
		T.eq(old.runs, 7, "Läufe bleiben")
		T.eq(old.layout, v, "jetzt mit Layout")
		local slow = TR.Load({ best = 71.5, rewardedBest = 71.5, runs = 4 })
		T.eq(slow.best, 71.5, "langsame Zeit ohne layout bleibt (auf dem neuen Kurs schlagbar)")
		local other = TR.Load({ best = 50, rewardedBest = 50, runs = 2, layout = 1 })
		T.eq(other.best, 0, "andere Streckenführung: Zeit verfällt")
		local cur = TR.Load({ best = 44, rewardedBest = 45, runs = 3, layout = v })
		T.eq(cur.best, 44, "aktuelle Streckenführung: Zeit bleibt")
		T.check(H.DeepEqual(TR.Load(cur), cur), "idempotent")
		T.check(H.DeepEqual(TR.Load(TR.Load({ best = 9, rewardedBest = 9, runs = 1 })), TR.Load({ best = 9, rewardedBest = 9, runs = 1 })), "idempotent (Altprofil)")
		local bad = TR.Load({ best = 30, rewardedBest = 30, runs = 1, layout = "x" })
		T.eq(bad.best, 0, "unsinniges layout -> Zeiten verfallen")
	end },

	{ "Zeitfahren auf dem Grand-Prix-Kurs: ehrliche Runde gültig, ausgelassener Checkpoint zählt nicht", function(T, H)
		local g = H.Garage({ noServer = true })
		local TR = g:MiniShared("TrackRules")
		local CR = g:MiniShared("CarRules")
		local list = seq(cityTrack(g))
		local spawn = g:Find("Workspace.City.CarSpawns.track")
		local positions = {}
		for i, cp in ipairs(list) do
			positions[i] = cp.Position
		end
		local speed = TR.CarSpeed(CR.Stats(CR.NewCar("komet", 1760000000)))
		local mins = TR.MinTimes(spawn.Position, positions, speed)
		local minLap = TR.MinLap(spawn.Position, positions, speed)
		-- ehrlich: jeder Abschnitt mit 60 % des Höchsttempos (Kurven), Bogenlänge ~ 1,15 × Luftlinie
		local run = TR.NewRun(table.clone(mins), 0, 0, minLap, speed)
		local t, prev, res = 0, spawn.Position, nil
		for i, p in ipairs(positions) do
			t += flat(p - prev).Magnitude * 1.15 / (speed * 0.6)
			prev = p
			res = TR.Touch(run, i, t)
		end
		T.eq(res, "finish", "ehrliche Runde")
		T.check(t < g:MiniShared("CarCatalog").Track.maxRunSeconds, "Runde unter maxRunSeconds (" .. math.floor(t) .. " s)")
		-- Abkürzung: CP der Haarnadel auslassen -> nächste Berührungen zählen nicht, kein Ziel
		local run2 = TR.NewRun(table.clone(mins), 0, 0, minLap, speed)
		local t2, res2 = 0, nil
		for i = 1, #positions do
			t2 += 6
			if i ~= 8 then
				res2 = TR.Touch(run2, i, t2)
			end
		end
		T.check(res2 ~= "finish" and run2.next == 8, "ohne Haarnadel-Checkpoint kein Ziel")
	end },

	{ "TrackUI zeigt die Streckenführung (Name, Abschnitte, Länge, Checkpoints)", function(T, H)
		local g = H.Garage()
		local p = g:Join(1001, { name = "Tester" })
		g:Advance(0.5)
		g:StartClient(p)
		g:Advance(1.5)
		local TrackUI = g:ClientModule(p, "Mini.TrackUI")
		local text = g:InClient(p, function()
			return TrackUI.LayoutText()
		end)
		T.check(type(text) == "string" and text:find("Grand-Prix-Kurs", 1, true) ~= nil, "Name: " .. tostring(text))
		T.check(text:find("Haarnadel", 1, true) and text:find("S-Kurve", 1, true) and text:find("lange Gerade", 1, true), "Abschnitte")
		T.check(text:find("Checkpoints", 1, true) ~= nil and text:find("Studs", 1, true) ~= nil, "Länge und Checkpoints")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end },
}
