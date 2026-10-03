-- B-020: In den Place-Varianten ohne Stadt (PlaceKind "lobby" / "tycoon") gab es beim ersten Erscheinen der Figur keinen
-- aktiven SpawnLocation: LobbySpawn/TycoonSpawn sind in der Welt abgeschaltet, die Plot-Vorlage (mit "Start") liegt in
-- ServerStorage und der Plot entsteht erst nach P.Load. Die Figur erschien am Ursprung über dem Nichts.
-- Jetzt schaltet der Server beim Start den Spawn der eigenen Zone ein, wenn es keinen aktiven CitySpawn gibt.
-- Der Basisbaum der Tests ist der all-Export (alle drei Zonen); die Varianten entstehen hier wie in
-- tools/build_place.py --place: nur die eigene Zone bleibt im Workspace.
local ZONES = { lobby = "Lobby", openworld = "City", tycoon = "Tycoon" }
local SPAWNS = { lobby = "LobbySpawn", openworld = "CitySpawn", tycoon = "TycoonSpawn" }

local function variant(H, kind, opts)
	opts = opts or {}
	opts.placeKind = kind
	local user = opts.before
	opts.before = function(g)
		if kind ~= "all" then
			for k, model in pairs(ZONES) do
				local m = g.env.workspace:FindFirstChild(model)
				if m and k ~= kind then
					m:Destroy()
				end
			end
		end
		if user then
			user(g)
		end
	end
	return H.Garage(opts)
end

local function zoneSpawn(g, kind)
	local m = g.env.workspace:FindFirstChild(ZONES[kind])
	return m and m:FindFirstChild(SPAWNS[kind])
end

local function activeSpawns(g)
	local out = {}
	for _, x in ipairs(g.env.workspace:GetDescendants()) do
		if x.ClassName == "SpawnLocation" and x.Enabled then
			table.insert(out, x.Name)
		end
	end
	table.sort(out)
	return table.concat(out, ",")
end

local function variantCase(kind)
	return function(T, H)
		local before
		-- Profil lädt langsam (5 s je DataStore-Aufruf): die Figur erscheint vor P.Load / W.Create
		local g = variant(H, kind, { dataStore = { updateYield = 5 }, before = function(g)
			local sp = zoneSpawn(g, kind)
			before = sp and sp.Enabled
		end })
		local sp = zoneSpawn(g, kind)
		T.check(sp ~= nil and sp.ClassName == "SpawnLocation", "Zonen-Spawn in der Fixture vorhanden")
		T.eq(before, false, "Welt: Zonen-Spawn ist abgeschaltet gebaut (tools/validate.py verlangt das)")
		T.eq(sp and sp.Enabled, true, "nach dem Serverstart aktiv – ohne Spieler, ohne geladenes Profil")
		T.eq(activeSpawns(g), SPAWNS[kind], "genau ein aktiver Spawn")
		local p = g:Join(2001, { name = "Neu" })
		T.eq(g:Session(p), nil, "Profil lädt noch")
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		T.check(root ~= nil, "Figur ist da")
		if root and sp then
			local delta = root.Position - sp.Position
			T.check(math.abs(delta.X) < 6 and math.abs(delta.Z) < 6 and delta.Y > 0 and delta.Y < 8,
				"Figur erscheint am Zonen-Spawn statt am Ursprung (Abstand " .. tostring(delta) .. ")")
		end
		g:Advance(120)
		T.check(g:Session(p) ~= nil, "Profil geladen")
		T.eq(sp and sp.Enabled, true, "bleibt aktiv")
		T.eq(#g:Errors(), 0, "keine Laufzeitfehler: " .. g:ErrorText())
	end
end

return {
	{ "Lobby-Variante: LobbySpawn ab Serverstart aktiv, Figur erscheint dort vor dem Profil", variantCase("lobby") },
	{ "Tycoon-Variante: TycoonSpawn ab Serverstart aktiv, Figur erscheint dort vor dem Profil", variantCase("tycoon") },

	{ "all-Place und Open-World-Variante unverändert: nur CitySpawn aktiv, Zonen-Spawns bleiben aus", function(T, H)
		local g = variant(H, "all")
		T.eq(activeSpawns(g), "CitySpawn", "all: nur CitySpawn aktiv")
		T.eq(zoneSpawn(g, "lobby").Enabled, false, "all: LobbySpawn aus")
		T.eq(zoneSpawn(g, "tycoon").Enabled, false, "all: TycoonSpawn aus")
		local p = g:Join(2002, { name = "Alt" })
		g:Advance(2)
		T.eq(zoneSpawn(g, "lobby").Enabled, false, "all nach Beitritt: LobbySpawn aus")
		T.eq(zoneSpawn(g, "tycoon").Enabled, false, "all nach Beitritt: TycoonSpawn aus")
		T.eq(g:Plot(p).Start.Enabled, false, "all: Plot-Spawn aus (CitySpawn ist der einzige)")
		T.eq(#g:Errors(), 0, "all: keine Laufzeitfehler: " .. g:ErrorText())
		local o = variant(H, "openworld")
		T.eq(activeSpawns(o), "CitySpawn", "openworld: nur CitySpawn aktiv")
		-- Test-Harness mit vollem Baum, aber PlaceKind lobby (so laufen bestehende Tests): Stadt-Spawn gewinnt
		local l = H.Garage({ placeKind = "lobby" })
		T.eq(activeSpawns(l), "CitySpawn", "PlaceKind lobby mit aktivem CitySpawn: kein zweiter Spawn")
	end },
}
