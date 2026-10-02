-- Ausbaustufe 4, Meilenstein 6 (Team ow): Open-World-Gebäude, Perks und Passiv-Modus (PHASE4_CONTRACT §5, §7).
-- Teil 1: OWRules rein (Default/Load idempotent, Müll, Bau-Sperren, Zeitraffer, Abholen, Offline-Fortschritt, Perks).
-- Teil 2: OWService im echten Server (H.Garage): ow_build/ow_collect/ow_passive über Remotes.Command -> Mini.Handle,
-- Modelle am Grundstück (Baustelle mit Countdown -> Stufenmodell), mini_notice ow_ready, Snapshot ow, Speichern/Laden,
-- Passiv-Modus blockt (OWService.BlockIfPassive) und bleibt nach Verlassen/Beitritt erhalten.
-- Teil 3: BuildingsUI im Mock-Client mit echtem Snapshot (sendet nur Absichten).
-- Solange der Integrator OWService noch nicht in MiniService/MiniNet eingetragen hat, setzt `before` genau die
-- Verkabelungszeilen aus dem Teambericht in die Quelltexte der Fixture ein (Quelltext-Patch, nur im Test).
local NOW = 1760000000
local HOUR = 3600

---------------------------------------------------------------- Verkabelung (nur, falls noch nicht integriert)
local function patchSource(inst, edits, marker)
	if not inst or type(inst.Source) ~= "string" or inst.Source:find(marker, 1, true) then
		return false
	end
	local src = inst.Source
	for _, e in ipairs(edits) do
		local at = src:find(e[1], 1, true)
		assert(at, "Patch-Anker fehlt in " .. inst.Name .. ": " .. e[1])
		if e[3] == "before" then
			src = src:sub(1, at - 1) .. e[2] .. src:sub(at)
		else
			src = src:sub(1, at - 1 + #e[1]) .. e[2] .. src:sub(at + #e[1])
		end
	end
	inst.Source = src
	return true
end

local function wire(g)
	local byName = {}
	for _, s in ipairs(g.scripts) do
		byName[s.Name] = s
	end
	patchSource(byName.MiniNet, {
		{ 'tycoon_trade_cancel = { id = "number" },', '\n\tow_build = { typ = "string" }, ow_collect = { typ = "string" }, ow_passive = { on = "boolean" },' },
		{ "tycoon_trade_cancel = 0.5,", "\n\tow_build = 1, ow_collect = 0.5, ow_passive = 1," },
		{ '"prestige", "tycoon"', ', "buildings"' },
	}, "ow_build")
	patchSource(byName.MiniService, {
		{ 'local TycoonService = require(Server:WaitForChild("TycoonService"))', '\nlocal OWService = require(Server:WaitForChild("OWService"))' },
		{ '{ "Tycoon", TycoonService.SnapshotFields },', '\n\t{ "OW", OWService.SnapshotFields },' },
		{ 'mini_auction_consign = "auction:player",', '\n\tow_build = function(clean)\n\t\tlocal key = "building:" .. tostring(clean.typ)\n\t\treturn Unlocks.Known(key) and key or nil\n\tend,' },
		{ "TycoonService.OnJoin(ms, d, t)", "\n\t\tOWService.OnJoin(ms, d, t)" },
		{ "\t\t-- Schrottplatz: sobald das Fahrzeug zerlegt werden darf", "\t\t-- Open World: Bauten fertig (Modell, ow_ready), Baustellen-Countdown; true = Snapshot fällig\n\t\tlocal okO, resO = pcall(OWService.Tick, ms, d, t)\n\t\tif okO then\n\t\t\tif resO then\n\t\t\t\tms.dirty = true\n\t\t\tend\n\t\telse\n\t\t\twarn(\"[Minispiele] Gebäude: \" .. tostring(resO))\n\t\tend\n", "before" },
		{ "pcall(TycoonService.OnLeave, ms)", "\n\tpcall(OWService.OnLeave, ms)" },
		{ "TycoonService.Register(Actions, api)", "\nOWService.Register(Actions, api)" },
		{ "TycoonService.Init(c)", "\n\tOWService.Init(c)" },
	}, "OWService")
	patchSource(byName.MiniRules, {
		{ 'local TycoonRules = require(script.Parent:WaitForChild("TycoonRules"))', '\nlocal OWRules = require(script.Parent:WaitForChild("OWRules"))' },
		{ "TycoonRules.ApplyDefault(g)", "\n\tOWRules.ApplyDefault(g)" },
		{ "TycoonRules.ApplyLoad(g, raw, d, now)", "\n\tOWRules.ApplyLoad(g, raw, d, now)" },
	}, "OWRules")
end

-- Anker im Plot-Template und Vorlagen in ServerStorage (wie das Weltteam sie baut): nur, wenn sie fehlen
local function world(g)
	local env = g.env
	local ws = env.workspace
	local tpl = ws:FindFirstChild("Werkstatt")
	if tpl and not tpl:FindFirstChild("OWAnchors") then
		local anchors = env.Instance.new("Folder")
		anchors.Name = "OWAnchors"
		anchors.Parent = tpl
		local off = { autohaus = 30, produktion = 42, schrottplatz = 54 }
		for typ, z in pairs(off) do
			local a = env.Instance.new("Part")
			a.Name = typ
			a.Anchored = true
			a.Transparency = 1
			a.CanCollide = false
			a.Size = Vector3.new(2, 1, 2)
			a.CFrame = tpl:GetPivot() * CFrame.new(20, 0.5, z)
			a.Parent = anchors
		end
	end
	local ss = env.services.ServerStorage
	if not ss:FindFirstChild("OWBuildings") then
		local folder = env.Instance.new("Folder")
		folder.Name = "OWBuildings"
		folder.Parent = ss
		local function model(name, withGui)
			local m = env.Instance.new("Model")
			m.Name = name
			local root = env.Instance.new("Part")
			root.Name = "Root"
			root.Anchored = true
			root.Size = Vector3.new(10, 6, 10)
			root.Parent = m
			m.PrimaryPart = root
			if withGui then
				local gui = env.Instance.new("SurfaceGui")
				gui.Name = "Schild"
				gui.Parent = root
				local tl = env.Instance.new("TextLabel")
				tl.Name = "Countdown"
				tl.Text = ""
				tl.Parent = gui
			end
			m.Parent = folder
		end
		model("baustelle", true)
		for _, typ in ipairs({ "autohaus", "produktion", "schrottplatz" }) do
			for st = 1, 4 do
				model(typ .. "_" .. st, false)
			end
		end
	end
end

local function garage(H, opts)
	opts = opts or {}
	opts.placeKind = opts.placeKind or "openworld"
	local userBefore = opts.before
	opts.before = function(g)
		wire(g)
		world(g)
		if userBefore then
			userBefore(g)
		end
	end
	return H.Garage(opts)
end

local rid = 500
local function act(T, g, pl, action, payload, expect, msg)
	g:Advance(1.1) -- Abklingzeit je Aktion (MiniNet.Cooldowns)
	rid += 1
	payload = payload or {}
	payload.rid = rid
	local res = g:Act(pl, action, payload)
	if expect then
		T.eq(res, expect, msg or (action .. " -> " .. expect))
	end
	return res
end

local function join(g, userId, name, level)
	local pl = g:Join(userId, { name = name, level = level or 12 })
	g:Advance(1.1)
	g:Send(pl, "hello")
	g:Advance(1.1)
	return pl, g:D(pl)
end

-- Zeitraffer ohne Zwischen-Ticks (Wanduhr springt wie offline), danach ein paar Server-Ticks
local function lapse(g, seconds)
	g.env.clock:Jump(seconds)
	g:Advance(2.1)
end

local function noErrors(T, g, what)
	T.eq(#g:Errors(), 0, what .. ": keine Fehler: " .. g:ErrorText())
end

local function countdownText(model)
	if not model then
		return nil
	end
	for _, x in ipairs(model:GetDescendants()) do
		if x:IsA("TextLabel") and x.Name == "Countdown" then
			return x.Text
		end
	end
	return nil
end

---------------------------------------------------------------- Teil 1: reine Regeln
local function modules(H)
	local g = H.Garage({ noServer = true })
	return g, g:MiniShared("GameConfig"), g:MiniShared("OWRules")
end

local function profile(g, OWR, level, money)
	local d = g:Rules().NewData(NOW)
	d.level = level or 1
	d.money = money or 0
	g:MiniShared("MetaRules").ApplyDefault(d.games)
	g:MiniShared("TycoonRules").ApplyDefault(d.games)
	OWR.ApplyDefault(d.games)
	return d
end

return {
	{ "GameConfig.OW: feste IDs, 4 Stufen je Gebäude, Bauzeiten/Preise steigen, Perks ≤ +25 %, Unlock-Level", function(T, H)
		local g, GC, OWR = modules(H)
		local OW = GC.OW
		local MiniRules = g:MiniShared("MiniRules")
		local Unlocks = g:MiniShared("Unlocks")
		T.check(MiniRules.IsClean(OW), "OW-Konfiguration ohne NaN/Instanzen")
		T.eq(#OW.Types, 4, "vier Gebäudetypen")
		T.eq(OW.MaxStage, 4, "vier Stufen")
		T.eq(OW.PassiveCapHours, 12, "PassiveCapHours 12")
		for _, typ in ipairs({ "autohaus", "produktion", "schrottplatz" }) do
			local b = OW.Buildings[typ]
			T.check(b ~= nil and #b.Stages == 4, typ .. ": 4 Stufen")
			T.check(Unlocks.Known(b.unlock), typ .. ": Unlock-Schlüssel bekannt (" .. tostring(b.unlock) .. ")")
			for i, st in ipairs(b.Stages) do
				T.eq(st.stage, i, typ .. " Stufe " .. i .. ": stage")
				T.check(st.price > 0 and st.buildSeconds > 0, typ .. " Stufe " .. i .. ": Preis und Bauzeit > 0")
				if i > 1 then
					T.check(st.price > b.Stages[i - 1].price and st.buildSeconds > b.Stages[i - 1].buildSeconds, typ .. " Stufe " .. i .. ": teurer und länger als Stufe " .. (i - 1))
				end
				T.eq(st.level, Unlocks.Level(b.unlock), typ .. " Stufe " .. i .. ": Level = Unlock-Level")
			end
		end
		local ah = OW.Buildings.autohaus.Stages
		T.check(ah[1].buildSeconds == 600 and ah[2].buildSeconds == 2700 and ah[3].buildSeconds == 10800 and ah[4].buildSeconds == 28800, "Autohaus-Bauzeiten 10 Min / 45 Min / 3 Std / 8 Std")
		for i = 1, 4 do
			T.check(OW.Buildings.produktion.Stages[i].buildSeconds > ah[i].buildSeconds, "Produktion baut länger (Stufe " .. i .. ")")
			T.check(OW.Buildings.schrottplatz.Stages[i].buildSeconds < ah[i].buildSeconds, "Schrottplatz baut kürzer (Stufe " .. i .. ")")
			T.check(ah[i].yieldPerHour > 0, "Autohaus Stufe " .. i .. ": Credits je Stunde")
			T.check(OW.Buildings.schrottplatz.Stages[i].scrapPerHour > 0, "Schrottplatz Stufe " .. i .. ": Schrott je Stunde")
			T.check(OW.Buildings.produktion.Stages[i].partsEveryHours > 0, "Produktion Stufe " .. i .. ": Paket alle n Stunden")
		end
		T.eq(OW.Buildings.produktion.Stages[4].carModel, "komet", "Produktion Stufe 4: Auto-Gutschein Kompaktwagen")
		T.check(OW.Buildings.produktion.Stages[3].carModel == nil, "Produktion Stufe 3: kein Gutschein")
		T.check(g:MiniShared("CarCatalog").Model("komet") ~= nil, "Gutschein-Modell im Katalog")
		-- Balance: Autohaus-Ertrag ≤ 25 % der Werkstatt (docs/BALANCE.md: Lv 10 ≈ 803, Lv 30 ≈ 2.850 Cr/Min)
		T.check(ah[1].yieldPerHour / 60 <= 803 * 0.25, "Autohaus Stufe 1 ≤ 25 % der Werkstatt auf Level 10")
		T.check(ah[4].yieldPerHour / 60 <= 2850 * 0.25, "Autohaus Stufe 4 ≤ 25 % der Werkstatt auf Level 30")
		for typ, p in pairs(OW.Perks) do
			T.check(p.cap <= 0.25 and p.per > 0, "Perk " .. typ .. " gedeckelt ≤ +25 %")
			T.check(OWR.Perk({}, typ) == 1, "Perk " .. typ .. " neutral ohne Profil")
		end
		T.check(type(OW.PassiveHint) == "string" and OW.PassiveHint:find("Passiv", 1, true) ~= nil, "Passiv-Hinweis vorhanden")
	end },

	{ "OWRules.Default/Load: idempotent, Whitelist, NaN/negativ -> Standard, Offline-Fertigstellung beim Laden", function(T, H)
		local g, GC, OWR = modules(H)
		local MiniRules = g:MiniShared("MiniRules")
		local def = OWR.Default()
		T.check(def.buildings.autohaus and def.buildings.produktion and def.buildings.schrottplatz, "drei baubare Gebäude")
		T.check(def.buildings.werkstatt == nil, "werkstatt ohne Datensatz (Stufe = d.bays)")
		T.eq(def.passive, false, "passive aus")
		T.check(MiniRules.IsClean(def), "Default sauber")
		local once = OWR.Load(def, {}, NOW)
		local twice = OWR.Load(once, {}, NOW)
		T.check(H.DeepEqual(once, twice), "Load idempotent")
		T.check(H.DeepEqual(OWR.Load(nil, {}, NOW), OWR.Default()), "Load(nil) = Default")
		local garbage = OWR.Load({
			buildings = {
				autohaus = { stage = 0 / 0, readyAt = -5, built = 99, collectedAt = "x", carAt = math.huge, extra = 1 },
				produktion = { stage = 99, readyAt = NOW + 100, built = 2 },
				schrottplatz = { stage = 2, readyAt = NOW - 1, built = 1, collectedAt = NOW - 50 },
				bogus = { stage = 1 },
			},
			passive = "ja", lastPassiveAt = -1, foo = {},
		}, {}, NOW)
		T.eq(garbage.buildings.autohaus.stage, 0, "NaN-Stufe -> 0")
		T.eq(garbage.buildings.autohaus.built, 0, "built ≤ stage")
		T.eq(garbage.buildings.autohaus.readyAt, 0, "negatives readyAt -> 0")
		T.eq(garbage.buildings.autohaus.collectedAt, 0, "collectedAt ohne Gebäude -> 0")
		T.check(garbage.buildings.autohaus.extra == nil and garbage.buildings.bogus == nil and garbage.foo == nil, "Whitelist der Schlüssel")
		T.eq(garbage.buildings.produktion.stage, 4, "Stufe über Maximum -> Maximum")
		T.eq(garbage.buildings.produktion.built, 2, "laufender Bau (readyAt in der Zukunft) bleibt built 2")
		T.eq(garbage.buildings.schrottplatz.built, 2, "readyAt erreicht -> beim Laden fertig (Offline-Bauzeit)")
		T.eq(garbage.buildings.schrottplatz.collectedAt, NOW - 1, "collectedAt nie vor readyAt (Umbau stand still)")
		T.eq(garbage.passive, false, "passive nur bei echtem true")
		T.eq(garbage.lastPassiveAt, 0, "lastPassiveAt negativ -> 0")
		T.check(MiniRules.IsClean(garbage), "geladene Daten sauber")
		-- Tiefe ≤ 5 unter games: games.ow.buildings.autohaus.stage
		local d = profile(g, OWR, 1, 0)
		T.check(MiniRules.IsClean(d.games.ow), "ow im Profil sauber")
		T.check(OWR.Data(d) ~= nil and OWR.Entry(d, "autohaus") ~= nil, "Data/Entry")
		T.check(OWR.Entry(d, "werkstatt") == nil and OWR.Entry(d, "x") == nil, "Entry nil für werkstatt/unbekannt")
		T.eq(OWR.Built(d, "werkstatt"), 1, "Werkstatt-Stufe = Bühnen (1)")
		d.bays = 3
		T.eq(OWR.Built(d, "werkstatt"), 3, "Werkstatt-Stufe = Bühnen (3)")
		-- Ensure legt ow für alte Profile an
		d.games.ow = nil
		T.check(OWR.Ensure(d) ~= nil and d.games.ow.buildings.autohaus.stage == 0, "Ensure legt ow an")
	end },

	{ "OWRules.CanBuild/Build: Level, Credits, laufender Bau, Maximum, werkstatt; Ready/Remaining im Zeitraffer", function(T, H)
		local g, GC, OWR = modules(H)
		local Unlocks = g:MiniShared("Unlocks")
		local st = GC.OW.Buildings.autohaus.Stages
		local lvl = Unlocks.Level("building:autohaus")
		local d = profile(g, OWR, lvl - 1, 10 ^ 9)
		local ok, reason, cost = OWR.CanBuild(d, "autohaus", NOW)
		T.check(not ok and reason == "level" and cost == st[1].price, "unter Level: level + Kosten")
		T.check(not OWR.Build(d, "autohaus", NOW), "Build unter Level schlägt fehl")
		T.eq(d.money, 10 ^ 9, "kein Geld abgezogen")
		d.level = lvl
		d.money = st[1].price - 1
		ok, reason = OWR.CanBuild(d, "autohaus", NOW)
		T.check(not ok and reason == "credits", "zu wenig Credits")
		T.check(select(2, OWR.CanBuild(d, "werkstatt", NOW)) == "werkstatt", "werkstatt: kein Kaufweg")
		T.check(select(2, OWR.CanBuild(d, "nix", NOW)) == "unknown", "unbekannt")
		d.money = st[1].price + 500
		ok, reason, cost = OWR.CanBuild(d, "autohaus", NOW)
		T.check(ok and reason == "ok" and cost == st[1].price, "baubar")
		local built, r2, paid = OWR.Build(d, "autohaus", NOW)
		T.check(built and r2 == "ok" and paid == st[1].price, "gebaut")
		T.eq(d.money, 500, "Credits abgezogen")
		local e = OWR.Entry(d, "autohaus")
		T.check(e.stage == 1 and e.built == 0 and e.readyAt == NOW + st[1].buildSeconds, "stage 1, built 0, readyAt = now + Bauzeit")
		T.check(not OWR.Ready(d, "autohaus", NOW) and OWR.InProgress(d, "autohaus"), "Bau läuft")
		T.eq(OWR.Remaining(d, "autohaus", NOW + 100), st[1].buildSeconds - 100, "Restzeit")
		d.money = 10 ^ 9
		ok, reason = OWR.CanBuild(d, "autohaus", NOW + 10)
		T.check(not ok and reason == "building", "während des Baus kein zweiter Kauf")
		T.check(OWR.Collectable(d, "autohaus", NOW + 10) == nil, "nichts abzuholen während des ersten Baus")
		T.check(OWR.Perk(d, "autohaus") == 1, "Baustelle gibt noch keinen Perk")
		-- Zeitraffer bis fertig
		local tReady = NOW + st[1].buildSeconds
		T.check(OWR.Ready(d, "autohaus", tReady), "fertig bei readyAt")
		T.eq(#OWR.Settle(d, tReady - 1), 0, "Settle vorher: nichts")
		local done = OWR.Settle(d, tReady)
		T.check(#done == 1 and done[1] == "autohaus", "Settle meldet autohaus")
		T.eq(OWR.Entry(d, "autohaus").built, 1, "built 1")
		T.eq(OWR.Entry(d, "autohaus").collectedAt, tReady, "Ertrag läuft ab readyAt")
		T.eq(#OWR.Settle(d, tReady + 5), 0, "Settle idempotent")
		T.near(OWR.Perk(d, "autohaus"), 1 + GC.OW.Perks.autohaus.per, 1e-9, "Perk Stufe 1")
		-- nächste Stufen bis zum Maximum
		local t = tReady
		for s = 2, 4 do
			ok = OWR.Build(d, "autohaus", t)
			T.check(ok, "Stufe " .. s .. " gekauft")
			t += st[s].buildSeconds
			OWR.Settle(d, t)
			T.eq(OWR.Built(d, "autohaus"), s, "Stufe " .. s .. " fertig")
		end
		ok, reason = OWR.CanBuild(d, "autohaus", t)
		T.check(not ok and reason == "max", "Maximum erreicht")
		T.near(OWR.Perk(d, "autohaus"), 1 + GC.OW.Perks.autohaus.cap, 1e-9, "Perk Stufe 4 = Deckel")
		-- Umbau: der angesammelte Ertrag wird beim Kauf abgeholt, während der Bauzeit steht die Anlage still,
		-- danach zählt der neue Stufensatz ab readyAt
		local d2 = profile(g, OWR, 50, 10 ^ 9)
		OWR.Build(d2, "autohaus", NOW)
		OWR.Settle(d2, NOW + st[1].buildSeconds)
		local t0 = NOW + st[1].buildSeconds + 2 * HOUR
		local money2 = d2.money
		local ok2, _, cost2, pre = OWR.Build(d2, "autohaus", t0)
		T.check(ok2 and pre and pre.credits == st[1].yieldPerHour * 2, "Umbau holt 2 Std. Ertrag der alten Stufe ab")
		T.eq(d2.money - money2, st[1].yieldPerHour * 2 - cost2, "Ertrag gutgeschrieben, Kosten abgezogen")
		T.check(not OWR.HasYield(OWR.Collectable(d2, "autohaus", t0 + st[2].buildSeconds - 10)), "während des Umbaus kein Ertrag")
		OWR.Settle(d2, t0 + st[2].buildSeconds)
		local a = OWR.Collectable(d2, "autohaus", t0 + st[2].buildSeconds + HOUR)
		T.eq(a and a.credits, st[2].yieldPerHour, "nach dem Umbau: neuer Stufensatz ab readyAt")
	end },

	{ "OWRules.Collectable/Collect: Erträge je Stunde, Deckel 12 Std., nur einmal abholen, Pakete und Gutschein der Produktion", function(T, H)
		local g, GC, OWR = modules(H)
		local OW = GC.OW
		local d = profile(g, OWR, 90, 10 ^ 12)
		local function finish(typ, stage, t)
			for _ = OWR.StageOf(d, typ) + 1, stage do
				assert(OWR.Build(d, typ, t))
				t = OWR.Entry(d, typ).readyAt
				OWR.Settle(d, t)
			end
			return t
		end
		-- Autohaus Stufe 2: 2,5 Std. -> floor(yield × 2,5)
		local t = finish("autohaus", 2, NOW)
		local y = OW.Buildings.autohaus.Stages[2].yieldPerHour
		local a = OWR.Collectable(d, "autohaus", t + 2.5 * HOUR)
		T.eq(a.credits, math.floor(y * 2.5), "Autohaus: Credits für 2,5 Std.")
		T.eq(a.scrap, 0, "Autohaus: kein Schrott")
		T.check(a.car == nil, "Autohaus: kein Auto")
		-- Deckel: 30 Std. zählen wie 12
		a = OWR.Collectable(d, "autohaus", t + 30 * HOUR)
		T.eq(a.credits, y * OW.PassiveCapHours, "Autohaus: Deckel PassiveCapHours")
		T.eq(a.hours, OW.PassiveCapHours, "Stunden gedeckelt")
		local money = d.money
		local got = OWR.Collect(d, "autohaus", t + 30 * HOUR)
		T.eq(got.credits, y * OW.PassiveCapHours, "Collect: Credits (Prestige-Rang 0 -> Faktor 1)")
		T.eq(d.money - money, y * OW.PassiveCapHours, "Credits gutgeschrieben")
		T.check(OWR.Collect(d, "autohaus", t + 30 * HOUR) == nil, "zweites Abholen im selben Moment: nichts")
		T.eq(OWR.Entry(d, "autohaus").collectedAt, t + 30 * HOUR, "collectedAt = jetzt")
		a = OWR.Collectable(d, "autohaus", t + 31 * HOUR)
		T.eq(a.credits, y, "eine Stunde später wieder eine Stunde Ertrag")
		-- Schrottplatz: Schrott in die Presse, Altteile ins Lager
		t = finish("schrottplatz", 1, NOW)
		local sp = OW.Buildings.schrottplatz.Stages[1]
		local scrap0, parts0 = d.games.press.scrap, d.games.parts
		got = OWR.Collect(d, "schrottplatz", t + 2 * HOUR)
		T.eq(got.scrap, sp.scrapPerHour * 2, "Schrott für 2 Std.")
		T.eq(got.parts, sp.partsPerHour * 2, "Altteile für 2 Std.")
		T.eq(d.games.press.scrap - scrap0, sp.scrapPerHour * 2, "Schrott in der Presse")
		T.eq(d.games.parts - parts0, sp.partsPerHour * 2, "Altteile im Lager")
		-- Produktion Stufe 1: Paket alle n Stunden, angebrochener Zeitraum bleibt
		t = finish("produktion", 1, NOW)
		local pr = OW.Buildings.produktion.Stages[1]
		local every = pr.partsEveryHours
		a = OWR.Collectable(d, "produktion", t + (every - 0.5) * HOUR)
		T.eq(a.parts, 0, "Produktion: vor dem ersten Paket nichts")
		parts0 = d.games.parts
		got = OWR.Collect(d, "produktion", t + (every + 0.5) * HOUR)
		T.eq(got.parts, pr.partsPerPack, "Produktion: ein Paket")
		T.eq(d.games.parts - parts0, pr.partsPerPack, "Paket im Lager")
		T.eq(OWR.Entry(d, "produktion").collectedAt, t + every * HOUR, "angebrochene halbe Stunde bleibt erhalten")
		T.check(OWR.Collect(d, "produktion", t + (every + 0.5) * HOUR) == nil, "kein zweites Paket")
		-- Produktion Stufe 4: Gutschein alle carEveryHours (unabhängig vom 12-Std.-Deckel), skipCar lässt ihn stehen
		t = finish("produktion", 4, t + (every + 0.5) * HOUR)
		local p4 = OW.Buildings.produktion.Stages[4]
		local e = OWR.Entry(d, "produktion")
		T.check(e.carAt > 0, "carAt gesetzt")
		a = OWR.Collectable(d, "produktion", e.carAt + p4.carEveryHours * HOUR - 1)
		T.check(a.car == nil, "Gutschein noch nicht fällig")
		local tCar = e.carAt + p4.carEveryHours * HOUR
		a = OWR.Collectable(d, "produktion", tCar)
		T.eq(a.car, p4.carModel, "Gutschein fällig")
		got = OWR.Collect(d, "produktion", tCar, { skipCar = true })
		T.check(got ~= nil and got.car == nil, "skipCar: Pakete abgeholt, Gutschein bleibt")
		T.eq(OWR.Collectable(d, "produktion", tCar).car, p4.carModel, "Gutschein steht noch")
		got = OWR.Collect(d, "produktion", tCar + 1)
		T.eq(got and got.car, p4.carModel, "Gutschein abgeholt (Modell-Id, Auto gibt der Dienst aus)")
		T.eq(e.carAt, tCar + 1, "Gutschein-Uhr neu")
		T.check(OWR.Collectable(d, "produktion", tCar + 2).car == nil, "kein zweiter Gutschein")
		T.check(g:MiniShared("MiniRules").IsClean(d.games.ow), "ow nach allem sauber")
	end },

	{ "OWRules.Perk: Werkstatt je Bühne, Gebäude je fertiger Stufe, alles gedeckelt ≤ +25 %; Discount; Summary", function(T, H)
		local g, GC, OWR = modules(H)
		local P = GC.OW.Perks
		local d = profile(g, OWR, 90, 10 ^ 12)
		T.eq(OWR.Perk(d, "werkstatt"), 1, "1 Bühne: neutral")
		d.bays = 2
		T.near(OWR.Perk(d, "werkstatt"), 1 + P.werkstatt.per, 1e-9, "2 Bühnen: +per")
		d.bays = 4
		T.near(OWR.Perk(d, "werkstatt"), 1 + math.min(P.werkstatt.cap, 3 * P.werkstatt.per), 1e-9, "4 Bühnen: 3 × per, gedeckelt")
		d.bays = 99
		T.check(OWR.Perk(d, "werkstatt") <= 1.25, "Perk nie über +25 %")
		d.bays = 0 / 0
		T.eq(OWR.Perk(d, "werkstatt"), 1, "NaN-Bühnen: neutral")
		T.eq(OWR.Perk(nil, "werkstatt"), 1, "ohne Profil neutral")
		T.eq(OWR.Perk(d, "quatsch"), 1, "unbekannter Perk neutral")
		-- Gebäude: nur fertige Stufen
		local e = OWR.Entry(d, "schrottplatz")
		e.stage, e.built, e.readyAt = 3, 2, NOW + 999
		T.near(OWR.Perk(d, "schrottplatz"), 1 + 2 * P.schrottplatz.per, 1e-9, "Schrottplatz: built 2 zählt, Baustelle nicht")
		e.built = 4
		e.stage = 4
		T.near(OWR.Perk(d, "schrottplatz"), 1 + P.schrottplatz.cap, 1e-9, "Schrottplatz Stufe 4: Deckel")
		local p = OWR.Entry(d, "produktion")
		p.stage, p.built = 4, 4
		T.near(OWR.Perk(d, "produktion"), 1 + P.produktion.cap, 1e-9, "Produktion Stufe 4: Deckel")
		local a = OWR.Entry(d, "autohaus")
		a.stage, a.built = 4, 4
		T.near(OWR.Discount(d), P.autohaus.cap, 1e-9, "Händlerrabatt = Deckel")
		local perks = OWR.Perks(d)
		for typ, f in pairs(perks) do
			T.check(f >= 1 and f <= 1.25, "Perks[" .. typ .. "] in 1..1,25")
		end
		-- Summary (Snapshot-Felder)
		local s = OWR.Summary(d, NOW)
		T.check(s.buildings.werkstatt and s.buildings.autohaus and s.buildings.produktion and s.buildings.schrottplatz, "Summary: vier Gebäude")
		T.eq(s.buildings.autohaus.built, 4, "Summary: built")
		T.eq(s.buildings.autohaus.next, false, "Summary: next = false auf Stufe 4")
		T.eq(s.buildings.werkstatt.next, false, "Summary: werkstatt ohne next")
		local fresh = OWR.Summary(profile(g, OWR, 90, 10 ^ 12), NOW).buildings.schrottplatz
		T.check(fresh.next and fresh.next.reason == "ok" and fresh.next.stage == 1 and fresh.next.cost == GC.OW.Buildings.schrottplatz.Stages[1].price, "Summary: next {stage, cost, reason} eines neuen Gebäudes")
		T.check(OWR.Summary(profile(g, OWR, 1, 0), NOW).buildings.schrottplatz.next.reason == "level", "Summary: next.reason level")
		T.eq(s.passive, false, "Summary: passive")
		T.eq(s.capHours, 12, "Summary: capHours")
		T.check(g:MiniShared("MiniRules").IsClean(s), "Summary sauber (nur Zahlen/Strings/Booleans)")
	end },

	{ "OWRules.PassiveSet/IsPassive: eine Quelle (meta.passive), ow.passive spiegelt; lobby_settings-Weg bleibt gültig", function(T, H)
		local g, GC, OWR = modules(H)
		local MetaRules = g:MiniShared("MetaRules")
		local d = profile(g, OWR, 5, 0)
		T.eq(OWR.IsPassive(d), false, "Standard aus")
		T.check(OWR.PassiveSet(d, true, NOW), "einschalten -> geändert")
		T.check(OWR.IsPassive(d) and MetaRules.IsPassive(d) and d.games.ow.passive == true, "meta.passive und ow.passive an")
		T.eq(d.games.ow.lastPassiveAt, NOW, "lastPassiveAt")
		T.check(not OWR.PassiveSet(d, true, NOW + 1), "noch einmal an -> nichts geändert")
		T.check(not OWR.PassiveSet(d, "ja", NOW), "kein Boolean -> nichts")
		MetaRules.SetSettings(d, { passive = false })
		T.eq(OWR.IsPassive(d), false, "lobby_settings (meta) schaltet aus, ow.passive darf das nicht überstimmen")
		T.check(not OWR.PassiveSet(d, false, NOW + 2), "ausschalten: schon aus (meta), nichts geändert")
		T.eq(d.games.ow.passive, false, "ow.passive trotzdem gespiegelt")
		-- ohne meta gilt ow.passive
		d.games.meta = nil
		d.games.ow.passive = true
		T.eq(OWR.IsPassive(d), true, "ohne meta: ow.passive")
	end },

	---------------------------------------------------------------- Teil 2: echter Server
	{ "OWService: ow_build gesperrt (Level, Credits, Baustelle), Baustelle mit Countdown, ow_ready im Zeitraffer, Modell-Tausch, Abholen einmal", function(T, H)
		local g = garage(H, {})
		local GC = g:MiniShared("GameConfig")
		local OWR = g:MiniShared("OWRules")
		local OWS = g:MiniServer("OWService")
		local Unlocks = g:MiniShared("Unlocks")
		local st = GC.OW.Buildings.autohaus.Stages
		local lvl = Unlocks.Level("building:autohaus")
		local pl, d = join(g, 7001, "Bauherr", lvl - 1)
		T.check(d.games.ow ~= nil, "d.games.ow nach dem Beitritt vorhanden")
		T.check(g:Plot(pl) ~= nil, "Grundstück vorhanden")
		d.money = 10 ^ 9
		-- Level-Sperre zentral (ACTION_UNLOCK -> "locked", Toast)
		local mark = g:Mark()
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "locked", "unter Level: locked")
		T.check(g:HasToast(pl, "Ab Level " .. lvl, mark), "Sperr-Toast nennt das Level")
		T.eq(OWR.StageOf(d, "autohaus"), 0, "nichts gebaut")
		act(T, g, pl, "ow_build", { typ = "quatsch" }, "ok", "unbekannter Typ: ok (Toast)")
		T.check(g:HasToast(pl, "gibt es nicht", mark), "Toast für unbekannten Typ")
		act(T, g, pl, "ow_build", { typ = "werkstatt" }, "ok")
		T.check(g:HasToast(pl, "Hallenanbau", mark), "werkstatt: Hinweis auf den Hallenanbau")
		-- Level reicht, Credits nicht
		d.level = lvl
		d.money = st[1].price - 1
		mark = g:Mark()
		g:Advance(1.1)
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok")
		T.check(g:HasToast(pl, "Nicht genug Credits", mark), "Credits-Toast")
		T.eq(OWR.StageOf(d, "autohaus"), 0, "immer noch nichts gebaut")
		-- Bauen
		d.money = st[1].price + 1000
		mark = g:Mark()
		g:Advance(1.1)
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok", "ow_build autohaus")
		T.eq(d.money, 1000, "Credits abgezogen (Server)")
		local e = OWR.Entry(d, "autohaus")
		T.check(e.stage == 1 and e.built == 0, "Baustelle Stufe 1")
		T.check(g:HasToast(pl, "Baustelle eröffnet", mark), "Baustellen-Toast")
		T.check(#g:Notices(pl, "ow_build", mark) == 1, "mini_notice ow_build")
		local site = OWS.ModelOf(pl, "autohaus")
		T.check(site ~= nil and site.Name == "baustelle" and site:GetAttribute("OWSite") == true, "Baustellen-Modell am Grundstück")
		T.check(site and site.Parent and site.Parent.Name == "OWBuildings" and site.Parent.Parent == g:Plot(pl), "Modell liegt in Plot.OWBuildings")
		local anchor = g:Plot(pl).OWAnchors.autohaus
		local pos = site:GetPivot().Position
		T.check((pos - anchor.Position).Magnitude < 0.5, "Modell steht am Anker")
		g:Advance(1.1)
		local text = countdownText(site)
		T.check(type(text) == "string" and text:find("Autohaus", 1, true) ~= nil and text:find("Fertig in", 1, true) ~= nil, "Countdown-Text: " .. tostring(text))
		-- zweiter Kauf während des Baus
		d.money = 10 ^ 9
		mark = g:Mark()
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok")
		T.check(g:HasToast(pl, "wird gerade gebaut", mark), "Baustelle: kein zweiter Kauf")
		T.eq(e.stage, 1, "Stufe bleibt 1")
		-- Snapshot
		local snap = g:MiniSnapshot(pl)
		T.check(snap and type(snap.ow) == "table", "Snapshot ow")
		local b = snap.ow.buildings.autohaus
		T.check(b.building == true and b.remaining > 0 and b.remaining <= st[1].buildSeconds, "Snapshot: Baustelle mit Restzeit")
		T.check(snap.ow.buildings.werkstatt.built == d.bays, "Snapshot: Werkstatt = Bühnen")
		T.eq(snap.ow.perks.autohaus, 1, "Snapshot: Perk noch neutral")
		-- Zeitraffer: Countdown läuft, ow_ready, Modell-Tausch
		mark = g:Mark()
		lapse(g, st[1].buildSeconds / 2)
		local mid = countdownText(OWS.ModelOf(pl, "autohaus"))
		T.check(mid ~= text, "Countdown hat sich geändert")
		T.eq(#g:Notices(pl, "ow_ready", mark), 0, "noch nicht fertig")
		lapse(g, st[1].buildSeconds / 2)
		local ready = g:Notices(pl, "ow_ready", mark)
		T.eq(#ready, 1, "genau ein ow_ready")
		T.check(ready[1] and ready[1].typ == "autohaus" and ready[1].stage == 1, "ow_ready {typ, stage}")
		T.eq(e.built, 1, "built 1")
		local model = OWS.ModelOf(pl, "autohaus")
		T.check(model ~= nil and model.Name == "autohaus_1" and model:GetAttribute("OWStage") == 1, "Stufenmodell autohaus_1")
		T.check(site.Parent == nil, "Baustelle entfernt")
		T.check(g:HasToast(pl, "fertig gebaut", mark), "Fertig-Toast")
		snap = g:MiniSnapshot(pl)
		T.near(snap.ow.perks.autohaus, 1 + GC.OW.Perks.autohaus.per, 1e-9, "Snapshot: Perk Stufe 1")
		-- Abholen: 2 Std. später, dann sofort noch einmal (nichts)
		lapse(g, 2 * HOUR)
		local money = d.money
		mark = g:Mark()
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok", "ow_collect")
		local got = d.money - money
		T.check(got >= math.floor(st[1].yieldPerHour * 2) and got <= math.floor(st[1].yieldPerHour * 2.01), "2 Std. Ertrag gutgeschrieben: " .. tostring(got))
		T.check(g:HasToast(pl, "abgeholt", mark), "Abhol-Toast")
		T.eq(#g:Notices(pl, "ow_collect", mark), 1, "mini_notice ow_collect")
		money = d.money
		mark = g:Mark()
		g:Advance(1.1)
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok")
		T.check(d.money - money <= 2, "zweites Abholen gleich danach: höchstens die paar Sekunden seit dem ersten (" .. tostring(d.money - money) .. ")")
		act(T, g, pl, "ow_collect", { typ = "produktion" }, "ok")
		T.check(g:HasToast(pl, "noch kein", mark), "Abholen ohne Gebäude: Hinweis")
		-- Deckel: 20 Std. -> 12 Std.
		lapse(g, 20 * HOUR)
		money = d.money
		act(T, g, pl, "ow_collect", { typ = "autohaus" }, "ok")
		T.eq(d.money - money, st[1].yieldPerHour * GC.OW.PassiveCapHours, "Deckel 12 Std.")
		noErrors(T, g, "OWService")
		g:Close()
	end },

	{ "OWService: Offline-Fortschritt (readyAt) über Verlassen/Beitritt, Ertrag ab readyAt, Modelle nach dem Laden, Perk wirkt in CarRules/Snapshot", function(T, H)
		local g = garage(H, {})
		local GC = g:MiniShared("GameConfig")
		local OWR = g:MiniShared("OWRules")
		local OWS = g:MiniServer("OWService")
		local st = GC.OW.Buildings.schrottplatz.Stages
		local pl, d = join(g, 7002, "Pendler", 40)
		d.money = 10 ^ 9
		act(T, g, pl, "ow_build", { typ = "schrottplatz" }, "ok", "Schrottplatz bauen")
		local readyAt = OWR.Entry(d, "schrottplatz").readyAt
		g:Advance(5)
		g:Leave(pl)
		g:Advance(1)
		local rec = g:Record(7002)
		T.check(rec and rec.data.games.ow.buildings.schrottplatz.stage == 1 and rec.data.games.ow.buildings.schrottplatz.built == 0, "Baustelle gespeichert")
		-- offline: Bauzeit + 3 Std. Ertrag vergehen
		g.env.clock:Jump(st[1].buildSeconds + 3 * HOUR)
		g:Advance(1)
		local mark = g:Mark()
		local pl2, d2 = join(g, 7002, "Pendler", 40)
		local e = OWR.Entry(d2, "schrottplatz")
		T.check(e.stage == 1 and e.built == 1, "beim Laden fertig (readyAt lag in der Vergangenheit)")
		T.eq(e.readyAt, readyAt, "readyAt unverändert")
		T.eq(e.collectedAt, readyAt, "Ertrag läuft ab readyAt")
		local model = OWS.ModelOf(pl2, "schrottplatz")
		T.check(model ~= nil and model.Name == "schrottplatz_1", "Stufenmodell nach dem Laden")
		local a = OWR.Collectable(d2, "schrottplatz", g:Now())
		T.check(a and a.scrap >= st[1].scrapPerHour * 3 and a.scrap <= st[1].scrapPerHour * 3.1, "3 Std. Schrott angesammelt (offline)")
		local scrap0 = d2.games.press.scrap
		act(T, g, pl2, "ow_collect", { typ = "schrottplatz" }, "ok")
		T.check(d2.games.press.scrap - scrap0 >= st[1].scrapPerHour * 3, "Schrott gutgeschrieben")
		-- Perk über OWRules; CrossBonus.OWPerk liefert dieselbe Zahl, sobald der Integrator ihn verdrahtet hat
		T.near(OWR.Perk(d2, "schrottplatz"), 1 + GC.OW.Perks.schrottplatz.per, 1e-9, "Schrottplatz-Perk Stufe 1")
		local CB = g:MiniShared("CrossBonus")
		local cbPerk = CB.OWPerk(d2, "schrottplatz")
		T.check(cbPerk == 1 or math.abs(cbPerk - OWR.Perk(d2, "schrottplatz")) < 1e-9, "CrossBonus.OWPerk: Platzhalter (1) oder gleich OWRules.Perk")
		-- Autohaus bis Stufe 2 im Zeitraffer, Rabatt im Snapshot/CarRules sobald verdrahtet
		local ah = GC.OW.Buildings.autohaus.Stages
		act(T, g, pl2, "ow_build", { typ = "autohaus" }, "ok")
		lapse(g, ah[1].buildSeconds)
		act(T, g, pl2, "ow_build", { typ = "autohaus" }, "ok")
		lapse(g, ah[2].buildSeconds)
		T.eq(OWR.Built(d2, "autohaus"), 2, "Autohaus Stufe 2 fertig")
		T.near(OWR.Discount(d2), 2 * GC.OW.Perks.autohaus.per, 1e-9, "Händlerrabatt Stufe 2")
		local snap = g:MiniSnapshot(pl2)
		T.near(snap.ow.perks.autohaus, 1 + 2 * GC.OW.Perks.autohaus.per, 1e-9, "Snapshot: Autohaus-Perk")
		T.eq(snap.ow.buildings.autohaus.next.stage, 3, "Snapshot: nächste Stufe 3")
		T.eq(snap.ow.buildings.autohaus.next.cost, ah[3].price, "Snapshot: Kosten Stufe 3")
		T.eq(snap.ow.buildings.autohaus.next.seconds, ah[3].buildSeconds, "Snapshot: Bauzeit Stufe 3")
		T.eq(#g:Notices(pl2, "ow_ready", mark), 2, "zwei ow_ready (Autohaus 1 und 2)")
		-- Verlassen räumt die Modelle weg
		g:Leave(pl2)
		g:Advance(1)
		T.check(model.Parent == nil, "Modell nach dem Verlassen entfernt")
		noErrors(T, g, "Offline")
		g:Close()
	end },

	{ "OWService: Passiv-Modus über ow_passive schaltet um, blockt (BlockIfPassive mit Hinweis), bleibt nach Verlassen/Beitritt; lobby_settings bleibt gültig", function(T, H)
		local g = garage(H, { placeKind = "all" })
		local OWS = g:MiniServer("OWService")
		local OWR = g:MiniShared("OWRules")
		local pl, d = join(g, 7003, "Ruhig", 20)
		local ms = g:MiniState(pl)
		T.eq(OWS.IsPassive(d), false, "Standard: nicht passiv")
		T.eq(OWS.BlockIfPassive(ms, d, g:Now()), false, "nicht geblockt")
		local mark = g:Mark()
		act(T, g, pl, "ow_passive", { on = true }, "ok", "ow_passive an")
		T.check(OWS.IsPassive(d) and d.games.meta.passive == true and d.games.ow.passive == true, "passiv an (meta + ow)")
		T.check(g:HasToast(pl, "Passiv-Modus an", mark), "Toast an")
		T.eq(#g:Notices(pl, "ow_passive", mark), 1, "mini_notice ow_passive")
		local snap = g:MiniSnapshot(pl)
		T.eq(snap.ow.passive, true, "Snapshot ow.passive")
		T.eq(snap.meta.passive, true, "Snapshot meta.passive")
		-- Stub-Prüfung des Integrators: BlockIfPassive -> true + deutscher Hinweis (gedrosselt)
		mark = g:Mark()
		T.eq(OWS.BlockIfPassive(ms, d, g:Now()), true, "geblockt")
		g:Flush()
		T.check(g:HasToast(pl, "Passiv-Modus", mark), "Hinweis beim Blocken")
		local toasts = #g:Toasts(pl, mark)
		T.eq(OWS.BlockIfPassive(ms, d, g:Now()), true, "weiter geblockt")
		g:Flush()
		T.eq(#g:Toasts(pl, mark), toasts, "Hinweis gedrosselt")
		-- doppelt einschalten: nichts geändert
		mark = g:Mark()
		g:Advance(1.1)
		act(T, g, pl, "ow_passive", { on = true }, "ok")
		T.check(g:HasToast(pl, "schon an", mark), "schon an")
		act(T, g, pl, "ow_passive", { on = "ja" }, "invalid", "kein Boolean -> invalid")
		-- bleibt nach Verlassen/Beitritt
		g:Advance(1)
		g:Leave(pl)
		g:Advance(1)
		local pl2, d2 = join(g, 7003, "Ruhig", 20)
		T.check(OWS.IsPassive(d2) and d2.games.ow.passive == true, "passiv nach dem Laden")
		-- lobby_settings schaltet aus (eine Quelle: meta.passive)
		g:Advance(1.1)
		act(T, g, pl2, "lobby_settings", { single = false, passive = false, beginner = true }, "ok")
		T.eq(OWS.IsPassive(d2), false, "lobby_settings passive=false wirkt")
		local ms2 = g:MiniState(pl2)
		T.eq(OWS.BlockIfPassive(ms2, d2, g:Now()), false, "nicht mehr geblockt")
		g:Advance(1.1)
		act(T, g, pl2, "ow_passive", { on = false }, "ok")
		T.check(g:HasToast(pl2, "schon aus"), "ow_passive aus: schon aus")
		T.eq(d2.games.ow.passive, false, "ow.passive gespiegelt")
		noErrors(T, g, "Passiv")
		g:Close()
	end },

	{ "OWService: zwei Spieler bauen unabhängig, Produktion Stufe 4 gibt im Zeitraffer einen Auto-Gutschein (Auto in der Garage), volle Garage lässt ihn stehen", function(T, H)
		local g = garage(H, {})
		local GC = g:MiniShared("GameConfig")
		local OWR = g:MiniShared("OWRules")
		local OWS = g:MiniServer("OWService")
		local CarCatalog = g:MiniShared("CarCatalog")
		local pr = GC.OW.Buildings.produktion.Stages
		local a, da = join(g, 7004, "Anna", 90)
		local b, db = join(g, 7005, "Ben", 90)
		da.money = 10 ^ 12
		db.money = 10 ^ 12
		act(T, g, a, "ow_build", { typ = "produktion" }, "ok", "Anna baut Produktion")
		act(T, g, b, "ow_build", { typ = "autohaus" }, "ok", "Ben baut Autohaus")
		T.check(OWR.StageOf(da, "autohaus") == 0 and OWR.StageOf(db, "produktion") == 0, "Bauten getrennt")
		T.check(OWS.ModelOf(a, "produktion") ~= nil and OWS.ModelOf(b, "autohaus") ~= nil, "beide Modelle")
		T.check(OWS.ModelOf(a, "produktion").Parent.Parent == g:Plot(a) and OWS.ModelOf(b, "autohaus").Parent.Parent == g:Plot(b), "je auf dem eigenen Grundstück")
		-- Anna: Produktion bis Stufe 4 im Zeitraffer (Bauzeiten aus GameConfig)
		for s = 1, 4 do
			if s > 1 then
				act(T, g, a, "ow_build", { typ = "produktion" }, "ok", "Produktion Stufe " .. s)
			end
			lapse(g, pr[s].buildSeconds)
			T.eq(OWR.Built(da, "produktion"), s, "Produktion Stufe " .. s .. " fertig")
		end
		T.check(OWS.ModelOf(a, "produktion").Name == "produktion_4", "Modell produktion_4")
		local cars0 = #da.games.cars
		lapse(g, pr[4].carEveryHours * HOUR + 5)
		local mark = g:Mark()
		act(T, g, a, "ow_collect", { typ = "produktion" }, "ok", "Gutschein abholen")
		T.eq(#da.games.cars, cars0 + 1, "ein Auto mehr in der Garage")
		local newest = da.games.cars[#da.games.cars]
		T.eq(newest and newest.model, pr[4].carModel, "Kompaktwagen aus dem Gutschein")
		T.check(g:HasToast(a, "Auto-Gutschein", mark), "Toast nennt den Gutschein")
		local n = g:Notices(a, "ow_collect", mark)
		T.check(#n == 1 and n[1].car == pr[4].carModel and n[1].parts > 0, "mini_notice ow_collect mit Auto und Paketen")
		-- volle Garage: Gutschein bleibt stehen, Pakete werden abgeholt
		lapse(g, pr[4].carEveryHours * HOUR + 5)
		while #da.games.cars < CarCatalog.MaxCars do
			g:MiniShared("CarRules").GrantModel(da, "komet", g:Now())
		end
		local parts0 = da.games.parts
		mark = g:Mark()
		act(T, g, a, "ow_collect", { typ = "produktion" }, "ok", "Abholen bei voller Garage")
		T.eq(#da.games.cars, CarCatalog.MaxCars, "kein Auto dazu")
		T.check(da.games.parts > parts0, "Pakete trotzdem abgeholt")
		T.check(g:HasToast(a, "Garage ist voll", mark), "Hinweis: Garage voll")
		T.eq(OWR.Collectable(da, "produktion", g:Now()).car, pr[4].carModel, "Gutschein steht noch")
		-- Ben: Autohaus-Ertrag unabhängig
		local money = db.money
		act(T, g, b, "ow_collect", { typ = "autohaus" }, "ok", "Ben holt ab")
		T.check(db.money > money, "Ben bekommt Credits")
		T.check(OWR.StageOf(db, "produktion") == 0, "Ben hat keine Produktion")
		noErrors(T, g, "Zwei Spieler")
		g:Close()
	end },

	---------------------------------------------------------------- Teil 3: Client
	{ "BuildingsUI: vier Karten aus echtem Snapshot, Bauen/Abholen senden nur Absichten {typ}, Passiv-Schalter sendet ow_passive {on}, Countdown", function(T, H)
		local g = garage(H, {})
		local GC = g:MiniShared("GameConfig")
		local st = GC.OW.Buildings.autohaus.Stages
		local pl, d = join(g, 7006, "Klick", 20)
		d.money = 10 ^ 9
		act(T, g, pl, "ow_build", { typ = "autohaus" }, "ok")
		g:Advance(1.1)
		local snap = g:MiniSnapshot(pl)
		g:StartClient(pl, { run = false })
		g:Advance(1.5)
		local sent = {}
		local rec = {
			Send = function(action, payload)
				payload = payload or {}
				local n = 0
				for k, v in pairs(payload) do
					n += 1
					T.check(type(k) == "string" and (type(v) == "string" or type(v) == "number" or type(v) == "boolean"), action .. ": flaches Feld " .. tostring(k))
					T.check(k ~= "cost" and k ~= "credits" and k ~= "amount" and k ~= "stage", action .. ": kein Wertfeld " .. tostring(k))
				end
				T.check(n <= 10, action .. ": höchstens 10 Felder")
				table.insert(sent, { action = action, payload = payload })
			end,
		}
		local toasts = {}
		local MiniUI = g:ClientModule(pl, "Mini.MiniUI")
		local mod = g:ClientModule(pl, "Mini.BuildingsUI")
		local page = g:InClient(pl, function()
			if not MiniUI.Gui then
				MiniUI.Build()
			end
			local gui = Instance.new("ScreenGui")
			gui.Name = "BuildingsTest"
			gui.ResetOnSpawn = false
			gui.Parent = pl.PlayerGui
			local frame = MiniUI.Frame(gui, { Name = "Page", BackgroundTransparency = 1, Size = UDim2.new(0, 338, 0, 0) })
			MiniUI.List(frame, 12)
			mod.Build(frame, { UI = MiniUI, Remote = rec, Toast = function(text)
				table.insert(toasts, text)
			end })
			mod.Render(snap)
			return frame
		end)
		local items = g:InClient(pl, function()
			return mod.Items()
		end)
		T.check(items.werkstatt and items.autohaus and items.produktion and items.schrottplatz, "vier Karten")
		T.check(items.werkstatt.stage.Text:find("Hebebühnen", 1, true) ~= nil, "Werkstatt-Karte zeigt Bühnen: " .. items.werkstatt.stage.Text)
		T.eq(items.werkstatt.buildButton.Visible, false, "Werkstatt: kein Bauen-Knopf (Hallenanbau)")
		T.check(items.autohaus.countdown.Visible and items.autohaus.countdown.Text:find("Fertig in", 1, true) ~= nil, "Autohaus: Countdown sichtbar")
		T.check(items.autohaus.stage.Text:find("Baustelle", 1, true) ~= nil, "Autohaus: Baustelle in der Stufenzeile")
		T.eq(items.autohaus.buildButton.Text, "Baustelle läuft", "Autohaus: Knopf während des Baus")
		T.check(items.autohaus.buildButton:GetAttribute("disabled") == true, "Autohaus: Bauen gesperrt während des Baus")
		T.check(items.produktion.next.Text:find(GC.OW.Buildings.produktion.Stages[1].buildSeconds >= 60 and "Bauzeit" or "x", 1, true) ~= nil, "Produktion: Kosten/Bauzeit der Stufe 1")
		T.check(items.produktion.buildButton.Text:find("Ab Level", 1, true) ~= nil, "Produktion unter Level: Knopf nennt das Level")
		-- Schrottplatz ab Level 18: Spieler ist 20, Geld reicht -> Bauen sendet ow_build {typ}
		T.eq(items.schrottplatz.buildButton.Text, "Bauen", "Schrottplatz: Bauen")
		g:Click(items.schrottplatz.buildButton)
		T.check(#sent == 1 and sent[1].action == "ow_build" and sent[1].payload.typ == "schrottplatz", "ow_build {typ = schrottplatz} gesendet")
		g:Click(items.produktion.buildButton)
		T.eq(#sent, 1, "gesperrter Knopf sendet nichts")
		T.eq(#toasts, 0, "gesperrter Knopf (UI.SetEnabled) löst nichts aus")
		-- Passiv-Schalter
		g:Click(page.PassiveCard.PassiveButton)
		T.check(#sent == 2 and sent[2].action == "ow_passive" and sent[2].payload.on == true, "ow_passive {on = true}")
		-- Zeitraffer auf dem Server: fertig, Erträge -> Abholen sendet ow_collect
		lapse(g, st[1].buildSeconds + 2 * HOUR)
		local snap2 = g:MiniSnapshot(pl)
		T.eq(snap2.ow.buildings.autohaus.built, 1, "Server: Stufe 1 fertig")
		g:InClient(pl, function()
			mod.Render(snap2)
		end)
		T.eq(items.autohaus.countdown.Visible, false, "Countdown weg")
		T.check(items.autohaus.yield.Text:find("Abholbereit", 1, true) ~= nil, "Ertrag angezeigt: " .. items.autohaus.yield.Text)
		T.check(items.autohaus.collectButton.Visible and items.autohaus.collectButton:GetAttribute("disabled") ~= true, "Abholen aktiv")
		g:Click(items.autohaus.collectButton)
		T.check(#sent == 3 and sent[3].action == "ow_collect" and sent[3].payload.typ == "autohaus", "ow_collect {typ = autohaus}")
		T.check(items.autohaus.buildButton.Text:find("Stufe 2", 1, true) ~= nil, "Ausbau auf Stufe 2 angeboten")
		T.check(items.autohaus.perk.Text:find("Händlerrabatt", 1, true) ~= nil, "Perk-Zeile")
		-- ow_passive-Hinweis vom Server (Notice) zeichnet neu, ow_ready toastet
		g:InClient(pl, function()
			mod.Render({ ow = { buildings = snap2.ow.buildings, passive = true, perks = snap2.ow.perks, capHours = 12 } })
			mod.OnNotice({ kind = "ow_ready", typ = "autohaus", stage = 2, name = "Autohaus" })
		end)
		T.check(page.PassiveCard.PassiveButton.Text:find("ausschalten", 1, true) ~= nil, "Passiv an: Knopf zum Ausschalten")
		T.check(toasts[#toasts]:find("fertig", 1, true) ~= nil, "ow_ready-Toast")
		noErrors(T, g, "BuildingsUI")
		g:Close()
	end },
}
