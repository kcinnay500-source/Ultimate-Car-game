-- Phase 1: Grundlage – Migration, Normalisierung, Zahlenformat, Karriere
local function deepEqual(a, b)
	if type(a) ~= type(b) then
		return false
	end
	if type(a) ~= "table" then
		return a == b
	end
	for k, v in pairs(a) do
		if not deepEqual(v, b[k]) then
			return false
		end
	end
	for k in pairs(b) do
		if a[k] == nil then
			return false
		end
	end
	return true
end

local function copy(v)
	if type(v) ~= "table" then
		return v
	end
	local o = {}
	for k, x in pairs(v) do
		o[k] = copy(x)
	end
	return o
end

-- Ein Profil im Stil von 2.4.0 (Werkstatt-Felder, die 3.0 nicht kennt)
local function legacyProfile()
	return {
		credits = 12345,
		level = 17,
		xp = 250,
		days = 42,
		equipmentBays = { { id = "lift1", device = "obd" }, { id = "lift2" } },
		lifts = 3,
		devices = { "obd", "compressor" },
		jobs = { { car = "Kombi", step = "diagnose" } },
		inventory = { oil = 5, brakePads = 2 },
		settings = { music = false },
	}
end

return {
	{ "2.4.0-Profil lädt ohne Verlust", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local old = legacyProfile()
		local p = S.Rules.LoadData(copy(old))
		T.eq(p.credits, 12345, "Credits")
		T.eq(p.level, 17, "Level")
		T.eq(p.xp, 250, "XP")
		T.eq(p.days, 42, "days")
		T.check(deepEqual(p.equipmentBays, old.equipmentBays), "equipmentBays unverändert")
		T.check(deepEqual(p.jobs, old.jobs), "Werkstatt-Aufträge 2.4.0 unverändert")
		T.check(deepEqual(p.inventory, old.inventory), "Lager 2.4.0 unverändert")
		T.check(deepEqual(p.devices, old.devices), "Geräte unverändert")
		T.eq(p.lifts, 3, "Bühnen unverändert")
		T.check(deepEqual(p.settings, old.settings), "Einstellungen unverändert")
		T.eq(type(p.games), "table", "neuer Bereich angelegt")
		T.eq(p.games.press.scrap, 0, "Schrott Standardwert")
		T.eq(p.games.press.lifetime, 0, "Bestenlistenwert Standardwert")
		T.eq(p.games.parts, S.Config.StartParts, "Teile Standardwert")
		T.eq(p.games.bays, 1, "Hebebühnen Standardwert")
		T.eq(p.games.tuningLevel, 1, "Tuning-Stufe Standardwert")
		T.eq(p.games.quiz.diagPoints, 0, "Diagnosepunkte Standardwert")
		T.eq(p.schema, 3, "Schema")
	end },

	{ "Doppeltes Laden verändert nichts", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local once = S.Rules.LoadData(copy(legacyProfile()))
		local twice = S.Rules.LoadData(copy(once))
		T.check(deepEqual(once, twice), "LoadData ist idempotent (Legacy)")
		local fresh = S.Rules.LoadData(nil)
		T.check(deepEqual(fresh, S.Rules.LoadData(copy(fresh))), "LoadData ist idempotent (neu)")
		-- mit Spielstand
		local p = S.Rules.LoadData(nil)
		p.games.press.upgrades = { pu0 = 3, pu1 = 2 }
		p.games.tuning.projects = { { slot = 1, id = "folie", startedAt = 100, duration = 300 } }
		p.games.jobs = { { id = 5, name = "Ölwechsel", reward = 10, xp = 1, parts = 1, cost = 1, time = 18, startedAt = 1, endsAt = 19 } }
		p.games.milestones = { m_jobs_10 = true }
		local a = S.Rules.LoadData(copy(p))
		T.check(deepEqual(a, S.Rules.LoadData(copy(a))), "LoadData ist idempotent (Spielstand)")
		T.eq(a.games.nextId, 6, "nextId hinter vorhandenen IDs")
	end },

	{ "Beschädigte neue Felder werden normalisiert", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local nan = 0 / 0
		local p = S.Rules.LoadData({
			credits = nan,
			level = -5,
			xp = math.huge,
			games = {
				parts = -3,
				bays = nan,
				toolLevel = 1e9,
				press = { scrap = nan, lifetime = -1, runScrap = math.huge, upgrades = { pu0 = nan, pu1 = -2, pu2 = 4, hack = 99, [5] = 1 }, rebirths = "x" },
				tuning = { projects = { { slot = 1, id = "folie", startedAt = nan, duration = -5 }, "kaputt" }, lastIdle = -100 },
				quiz = { diagPoints = nan },
				parking = { streak = -1, puzzle = { cars = { 1, 1, 99, "x" }, target = 99 } },
				stats = { jobsDone = nan },
				milestones = { m_jobs_10 = "ja" },
				daily = { day = 5, progress = { clicks = nan } },
				jobs = { "x", { id = nan, name = 5 } },
			},
		})
		T.eq(p.credits, S.Config.StartCredits, "NaN-Credits -> Standard")
		T.eq(p.level, 1, "negatives Level -> 1")
		T.eq(p.xp, 0, "inf-XP -> 0")
		T.eq(p.games.parts, 0, "negative Teile -> 0")
		T.eq(p.games.bays, 1, "NaN-Bühnen -> 1")
		T.eq(p.games.toolLevel, 100, "Werkzeug gedeckelt")
		T.eq(p.games.press.scrap, 0, "NaN-Schrott -> 0")
		T.eq(p.games.press.lifetime, 0, "negativer Bestenlistenwert -> 0")
		T.eq(p.games.press.runScrap, 0, "inf-Durchlauf -> 0")
		T.eq(p.games.press.upgrades.pu0, nil, "NaN-Upgrade entfernt")
		T.eq(p.games.press.upgrades.pu1, nil, "negatives Upgrade entfernt")
		T.eq(p.games.press.upgrades.pu2, 4, "gültiges Upgrade bleibt")
		T.eq(p.games.press.upgrades.hack, nil, "unbekannter Schlüssel entfernt")
		T.eq(p.games.press.rebirths, 0, "Text-Rebirths -> 0")
		T.eq(#p.games.tuning.projects, 0, "ungültige Projekte entfernt")
		T.eq(p.games.tuning.lastIdle, 0, "negative Zeit -> 0")
		T.eq(p.games.quiz.diagPoints, 0, "NaN-Diagnose -> 0")
		T.eq(p.games.parking.streak, 0, "negative Serie -> 0")
		T.eq(p.games.parking.puzzle, false, "kaputtes Rätsel verworfen")
		T.eq(p.games.stats.jobsDone, 0, "NaN-Statistik -> 0")
		T.eq(p.games.milestones.m_jobs_10, nil, "ungültiger Meilenstein-Eintrag entfernt")
		T.eq(p.games.daily.day, "", "ungültiger Tag -> leer")
		T.eq(p.games.daily.progress.clicks, 0, "NaN-Fortschritt -> 0")
		T.eq(#p.games.jobs, 0, "ungültige Aufträge entfernt")
		T.check(S.Rules.IsClean(p), "Profil enthält danach keine NaN/inf")
		T.check(not S.Rules.IsClean({ a = { b = 0 / 0 } }), "IsClean erkennt NaN")
		T.check(not S.Rules.IsClean({ a = math.huge }), "IsClean erkennt inf")
	end },

	{ "Zahlenformat", function(T, H)
		local env = H.Env()
		local L = H.Shared(env).Locale
		T.eq(L.Number(0), "0", "0")
		T.eq(L.Number(999), "999", "999")
		T.eq(L.Number(12345), "12.345", "Tausenderpunkt")
		T.eq(L.Number(99999), "99.999", "unter 100 Tsd.")
		T.eq(L.Number(123456), "123 Tsd.", "Tsd.")
		T.eq(L.Number(1200000), "1,2 Mio.", "Mio.")
		T.eq(L.Number(1000000), "1 Mio.", "glatte Mio.")
		T.eq(L.Number(3.5e9), "3,5 Mrd.", "Mrd.")
		T.eq(L.Number(7e12), "7 Bio.", "Bio.")
		T.eq(L.Number(2.26e15), "2,3 Brd.", "Brd.")
		T.eq(L.Number(-1500000), "-1,5 Mio.", "negativ")
		T.eq(L.Number(0 / 0), "0", "NaN")
		T.eq(L.Number(math.huge), "0", "inf")
		T.check(L.Number(1e30):find("e30") ~= nil, "sehr groß wissenschaftlich: " .. L.Number(1e30))
		T.eq(L.Duration(3725), "1 Std. 02 Min.", "Dauer Std.")
		T.eq(L.Duration(65), "1 Min. 05 Sek.", "Dauer Min.")
		T.eq(L.Duration(-5), "0 Sek.", "negative Dauer")
		T.eq(L.T("offline_press", "5"), "Während du weg warst: +5", "Platzhalter")
	end },

	{ "Karriere: XP-Kurve und Level-Belohnung wie HTML", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		T.eq(S.Rules.XpNeeded(1), math.floor(80 + 22 + 4), "xpNeeded(1)")
		T.eq(S.Rules.XpNeeded(10), math.floor(80 + 220 + 10 ^ 1.16 * 4), "xpNeeded(10)")
		local p = S.Rules.LoadData(nil)
		local r = S.Rules.GainXP(p, 106)
		T.eq(p.level, 2, "Levelaufstieg")
		T.eq(r.levels, 1, "ein Level")
		T.eq(r.credits, 120 + 2 * 18, "Level-Bonus")
		T.eq(p.credits, S.Config.StartCredits + 156, "Credits gutgeschrieben")
		T.eq(p.games.reputation, 2, "Ruf +2")
		local r2 = S.Rules.GainXP(p, 0 / 0)
		T.eq(r2.levels, 0, "NaN-XP ignoriert")
		T.check(S.Rules.IsClean(p), "Profil sauber")
	end },

	{ "Tageswechsel nach UTC", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		T.eq(S.Rules.DayKey(0), "1970-01-01", "Epoche")
		T.eq(S.Rules.DayKey(86399), "1970-01-01", "letzte Sekunde")
		T.eq(S.Rules.DayKey(86400), "1970-01-02", "nächster Tag")
	end },

	{ "Katalog: 100 Presse-Upgrades wie HTML, ohne Autopunkte", function(T, H)
		local env = H.Env()
		local S = H.Shared(env)
		local C = S.Catalog
		T.eq(#C.PressUpgrades, 100, "100 Upgrades")
		for i, u in ipairs(C.PressUpgrades) do
			local idx = i - 1
			if not (u.type == idx % 5 and u.baseCost == math.floor(8 * 1.19 ^ idx + 0.5) and u.baseEffect == 1 + math.floor(idx / 5) and type(u.name) == "string") then
				T.check(false, "Upgrade " .. i .. " weicht von der HTML-Formel ab")
			end
		end
		T.check(true, "alle Upgrades geprüft")
		local names = {}
		for _, u in ipairs(C.PressUpgrades) do
			T.check(not names[u.name], "Name eindeutig: " .. u.name)
			names[u.name] = true
		end
		T.eq(#C.Questions >= 7, true, "mindestens die 7 HTML-Fragen")
		for _, q in ipairs(C.Questions) do
			T.eq(#q.a, 4, "4 Antworten: " .. q.q)
		end
	end },
}
