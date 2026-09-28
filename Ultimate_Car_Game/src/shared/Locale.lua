-- Locale: deutsche Texte und Zahlenformatierung (Tsd., Mio., Mrd., ...)
local Locale = {}

local SUFFIXES = {
	{ 1e24, "Quadr." },
	{ 1e21, "Trd." },
	{ 1e18, "Trio." },
	{ 1e15, "Brd." },
	{ 1e12, "Bio." },
	{ 1e9, "Mrd." },
	{ 1e6, "Mio." },
	{ 1e3, "Tsd." },
}

local function isBad(n)
	return type(n) ~= "number" or n ~= n or n == math.huge or n == -math.huge
end

-- Ganzzahl mit Tausenderpunkten: 12345 -> "12.345"
function Locale.Group(n)
	if isBad(n) then
		return "0"
	end
	local negative = n < 0
	local s = string.format("%.0f", math.floor(math.abs(n)))
	local out = s:reverse():gsub("(%d%d%d)", "%1."):reverse()
	if out:sub(1, 1) == "." then
		out = out:sub(2)
	end
	return (negative and "-" or "") .. out
end

local function decimal(n, places)
	local s = string.format("%." .. places .. "f", n)
	s = s:gsub("%.", ",")
	if places > 0 then
		s = s:gsub(",?0+$", "")
	end
	return s
end

-- Große Zahlen kompakt: 1234 -> "1.234", 123456 -> "123,5 Tsd.", 1.2e6 -> "1,2 Mio."
function Locale.Number(n)
	if isBad(n) then
		return "0"
	end
	local a = math.abs(n)
	if a < 100000 then
		return Locale.Group(n)
	end
	for _, entry in ipairs(SUFFIXES) do
		if a >= entry[1] then
			local v = a / entry[1]
			if v >= 1000 and entry == SUFFIXES[1] then
				break
			end
			local places = v < 100 and 1 or 0
			if v >= 999.95 and places == 0 then
				v = 999
			end
			return (n < 0 and "-" or "") .. decimal(v, places) .. " " .. entry[2]
		end
	end
	local exponent = math.floor(math.log10(a))
	local mantissa = a / 10 ^ exponent
	return (n < 0 and "-" or "") .. decimal(mantissa, 2) .. "e" .. exponent
end

function Locale.Credits(n)
	return Locale.Number(n) .. " Cr"
end

function Locale.Scrap(n)
	return Locale.Number(n) .. " kg Schrott"
end

function Locale.Duration(seconds)
	if isBad(seconds) or seconds < 0 then
		seconds = 0
	end
	seconds = math.floor(seconds)
	local h = math.floor(seconds / 3600)
	local m = math.floor((seconds % 3600) / 60)
	local s = seconds % 60
	if h > 0 then
		return string.format("%d Std. %02d Min.", h, m)
	elseif m > 0 then
		return string.format("%d Min. %02d Sek.", m, s)
	end
	return string.format("%d Sek.", s)
end

function Locale.Percent(fraction)
	if isBad(fraction) then
		return "0 %"
	end
	return tostring(math.floor(fraction * 100 + 0.5)) .. " %"
end

Locale.Strings = {
	title = "Ultimate Car Game",
	tab_overview = "Übersicht",
	tab_press = "Schrottpresse",
	tab_tuning = "Tuning-Garage",
	tab_workshop = "Werkstatt",
	tab_scrapyard = "Schrottplatz",
	tab_quiz = "Mechaniker-Quiz",
	tab_parking = "Parkplatz-Chaos",
	tab_goals = "Ziele",
	tab_leaderboard = "Bestenliste",
	tab_shop = "Shop",
	menu_button = "Minispiele",
	close = "Schließen",
	not_enough_credits = "Nicht genug Credits.",
	not_enough_scrap = "Nicht genug Schrott.",
	not_enough_parts = "Nicht genug Teile.",
	offline_press = "Während du weg warst: +{1}",
	leaderboard_unavailable = "Bestenliste gerade nicht verfügbar",
	leaderboard_loading = "Bestenliste wird geladen …",
	studio_nosave = "Speichern nicht aktiv: In Studio unter Game Settings > Security den API-Zugriff erlauben.",
	profile_locked = "Dein Profil wird noch in einer anderen Sitzung verwendet. Bitte in einer Minute erneut beitreten.",
	profile_failed = "Dein Spielstand konnte gerade nicht geladen werden. Bitte gleich erneut beitreten – es ist nichts verloren.",
	save_lost = "Dein Profil wurde in einer anderen Sitzung geöffnet. Fortschritt in dieser Sitzung wird nicht mehr gespeichert.",
	rebirth_confirm = "Rebirth durchführen? Schrott und Presse-Upgrades werden zurückgesetzt. Du erhältst dauerhaft ×{1} Schrott. Werkstatt, Credits, Level, Tuning und Meilensteine bleiben.",
	level_up = "Level {1} erreicht! +{2}",
	pass_not_configured = "Dieser Game Pass ist noch nicht eingerichtet.",
}

function Locale.T(key, ...)
	local s = Locale.Strings[key] or key
	local args = { ... }
	s = s:gsub("{(%d+)}", function(i)
		local v = args[tonumber(i)]
		if v == nil then
			return ""
		end
		return tostring(v)
	end)
	return s
end

return Locale
