-- MiniLocale: deutsche Texte und die eine Zahlenformatierung (Tsd., Mio., Mrd., ...) für Minispiele und HUD.
local MiniLocale = {}

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
function MiniLocale.Group(n)
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

-- Dezimalzahl mit Komma, ohne überflüssige Nullen: 1.50 -> "1,5"
function MiniLocale.Decimal(n, places)
	if isBad(n) then
		return "0"
	end
	places = places or 1
	local s = string.format("%." .. places .. "f", n)
	s = s:gsub("%.", ",")
	if places > 0 then
		s = s:gsub(",?0+$", "")
	end
	return s
end

-- Große Zahlen kompakt: 1234 -> "1.234", 123456 -> "123,5 Tsd.", 1.2e6 -> "1,2 Mio."
function MiniLocale.Number(n)
	if isBad(n) then
		return "0"
	end
	local a = math.abs(n)
	if a < 100000 then
		return MiniLocale.Group(n)
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
			return (n < 0 and "-" or "") .. MiniLocale.Decimal(v, places) .. " " .. entry[2]
		end
	end
	local exponent = math.floor(math.log10(a))
	local mantissa = a / 10 ^ exponent
	return (n < 0 and "-" or "") .. MiniLocale.Decimal(mantissa, 2) .. "e" .. exponent
end

function MiniLocale.Credits(n)
	return MiniLocale.Number(n) .. " Cr"
end

function MiniLocale.Scrap(n)
	return MiniLocale.Number(n) .. " kg Schrott"
end

-- Multiplikator: 1.25 -> "×1,25"
function MiniLocale.Factor(n)
	if isBad(n) then
		return "×1"
	end
	return "×" .. MiniLocale.Decimal(n, 2)
end

function MiniLocale.Duration(seconds)
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

function MiniLocale.Percent(fraction)
	if isBad(fraction) then
		return "0 %"
	end
	return tostring(math.floor(fraction * 100 + 0.5)) .. " %"
end

MiniLocale.Strings = {
	menu_button = "Minispiele",
	tab_overview = "Übersicht",
	tab_press = "Schrottpresse",
	tab_tuning = "Tuning-Garage",
	tab_scrapyard = "Schrottplatz",
	tab_quiz = "Mechaniker-Quiz",
	tab_parking = "Parkplatz-Chaos",
	tab_goals = "Ziele",
	tab_leaderboard = "Bestenliste",
	tab_shop = "Shop",
	tab_map = "Stadtplan",
	tab_workshop = "Werkstatt",
	close = "Schließen",
	not_enough_credits = "Nicht genug Credits.",
	not_enough_scrap = "Nicht genug Schrott.",
	not_enough_parts = "Nicht genug Altteile.",
	offline_press = "Während du weg warst: +{1}",
	leaderboard_unavailable = "Bestenliste gerade nicht verfügbar",
	leaderboard_loading = "Bestenliste wird geladen …",
	leaderboard_title = "Bestenliste · Schrott gepresst",
	rebirth_confirm = "Rebirth durchführen? Schrott und Presse-Upgrades werden zurückgesetzt. Du erhältst dauerhaft ×{1} Schrott. Werkstatt, Credits, Level, Tuning und Meilensteine bleiben.",
	pass_not_configured = "Dieser Game Pass ist noch nicht eingerichtet.",
	pass_owned = "Du besitzt diesen Game Pass bereits.",
	pass_thanks = "Danke! Game Pass aktiv.",
	coming_soon = "{1} eröffnet bald.",
	travel_unknown = "Dieses Ziel ist gerade nicht erreichbar.",
	travel_blocked = "Reisen ist gerade nicht möglich.",
}

function MiniLocale.T(key, ...)
	local s = MiniLocale.Strings[key] or key
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

return MiniLocale
