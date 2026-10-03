-- B-021: Startweg Produktion – wer die geschenkten Pakete schon im Schritt „Gebäude ansehen“ (pr_buildings) abholt,
-- darf im Schritt „Abholen“ (pr_collect) nicht bis zum nächsten Paket (6 Std.) festhängen.
local rid = 9000
local function act(g, pl, action, payload)
	g:Advance(1.1) -- Abklingzeit je Aktion
	rid += 1
	payload = payload or {}
	payload.rid = rid
	return g:Act(pl, action, payload)
end

local function join(g, userId, name)
	local pl = g:Join(userId, { name = name })
	g:Advance(1.2)
	g:Send(pl, "hello")
	g:Advance(1.1)
	return pl
end

local function stepId(g, pl)
	local TR = g:MiniShared("TutorialRules")
	local step = TR.Current(g:D(pl))
	return step and step.id or nil
end

-- „Weiter“ für den aktuellen Schritt
local function nextStep(g, pl)
	local TR = g:MiniShared("TutorialRules")
	return act(g, pl, "tutorial_next", { step = TR.StepIndex(g:D(pl)) })
end

-- Neues Profil, Weg gewählt, bis zum Schritt „Gebäude ansehen“ (Schritte 1 und 2 mit „Weiter“)
local function toBuildings(T, g, userId, path, prefix)
	local pl = join(g, userId, "Neu" .. userId)
	T.eq(act(g, pl, "start_choose", { path = path }), "ok", path .. ": start_choose")
	nextStep(g, pl)
	nextStep(g, pl)
	T.eq(stepId(g, pl), prefix .. "_buildings", path .. ": Schritt 3 = Gebäude ansehen")
	return pl
end

return {
	{ "B-021: Pakete vor dem Schritt „Abholen“ geholt -> der Schritt ist sofort erledigt (Produktion)", function(T, H)
		local g = H.Garage({ placeKind = "openworld" })
		local pl = toBuildings(T, g, 8101, "produktion", "pr")
		local d = g:D(pl)
		local parts0 = d.games.parts
		T.eq(act(g, pl, "ow_collect", { typ = "produktion" }), "ok", "Abholen im Schritt 3")
		T.check(d.games.parts > parts0, "Altteile gutgeschrieben")
		T.eq(stepId(g, pl), "pr_buildings", "Abholen erledigt Schritt 3 nicht")
		nextStep(g, pl)
		g:Advance(1.1)
		T.check(stepId(g, pl) ~= "pr_collect", "Schritt „Abholen“ ist schon erledigt (jetzt: " .. tostring(stepId(g, pl)) .. ")")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "B-021: gilt auch nach Rejoin zwischen Abholen und Schritt „Abholen“ – und für ein Profil, das dort schon festhängt", function(T, H)
		local g = H.Garage({ placeKind = "openworld" })
		local pl = toBuildings(T, g, 8102, "produktion", "pr")
		T.eq(act(g, pl, "ow_collect", { typ = "produktion" }), "ok", "Abholen im Schritt 3")
		g:Advance(1.1)
		g:Leave(pl)
		g:Advance(2)
		pl = join(g, 8102, "Neu8102")
		T.eq(stepId(g, pl), "pr_buildings", "nach Rejoin weiter Schritt 3")
		nextStep(g, pl)
		g:Advance(1.1)
		T.check(stepId(g, pl) ~= "pr_collect", "nach Rejoin: Schritt „Abholen“ erledigt (jetzt: " .. tostring(stepId(g, pl)) .. ")")

		-- Profil, das vor dem Fix im Schritt „Abholen“ hängen geblieben ist: der nächste Tick erledigt ihn
		local TR = g:MiniShared("TutorialRules")
		local pl2 = toBuildings(T, g, 8103, "produktion", "pr")
		T.eq(act(g, pl2, "ow_collect", { typ = "produktion" }), "ok", "Abholen im Schritt 3")
		local d2 = g:D(pl2)
		d2.games.meta.tutorialStep = TR.StepIndex(d2) + 1
		g:Advance(2.1)
		T.check(stepId(g, pl2) ~= "pr_collect", "hängendes Profil kommt weiter (jetzt: " .. tostring(stepId(g, pl2)) .. ")")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },

	{ "B-021: ohne früheren Ertrag bleibt der Schritt stehen – abgelehntes Abholen erledigt ihn nicht", function(T, H)
		local g = H.Garage({ placeKind = "openworld" })
		local OWR = g:MiniShared("OWRules")
		local pl = toBuildings(T, g, 8104, "produktion", "pr")
		local d = g:D(pl)
		-- Geschenk ohne abholbaren Ertrag (Zeitraum beginnt jetzt, noch nie abgeholt)
		local e = OWR.Entry(d, "produktion")
		e.collectedAt = g:Now()
		T.eq(e.collects, 0, "noch nie abgeholt")
		nextStep(g, pl)
		T.eq(stepId(g, pl), "pr_collect", "Schritt „Abholen“ erreicht")
		act(g, pl, "ow_collect", { typ = "produktion" })
		g:Advance(2.1)
		T.eq(e.collects, 0, "Abholen abgelehnt (nichts da)")
		T.eq(stepId(g, pl), "pr_collect", "abgelehntes Abholen erledigt den Schritt nicht")
		T.eq(g:ErrorText(), "", "keine Skriptfehler")
	end },
}
