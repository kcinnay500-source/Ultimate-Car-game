-- MiniConfig: alle Werte der Minispiele an einer Stelle (Quelle der Formeln: reference/Ultimate_Car_Game.html).
-- Karriere, Geld, Level, Ruf, Werkzeugqualität, DataStore und Remote-Budget gehören 2.4.0 (GarageShared.Config).
local MiniConfig = {}

-- Bestenliste (eigener OrderedDataStore, nur Schreiben bei beschreibbarem Profil, in Studio nie)
MiniConfig.LeaderboardStoreName = "UltimateCarGame_ScrapLeaderboard_v1"
MiniConfig.LeaderboardWriteInterval = 120 -- Sekunden pro Spieler
MiniConfig.LeaderboardReadInterval = 60 -- Sekunden serverweit
MiniConfig.LeaderboardTopCount = 50
MiniConfig.LeaderboardScanPages = 5 -- je 100 Einträge, für die eigene Platzierung außerhalb der Top 50
MiniConfig.LeaderboardBoardRows = 10
MiniConfig.DataStoreRetries = 3

-- Eingang (das Budget selbst gehört GarageServer.request)
MiniConfig.RecentRequestIds = 64
MiniConfig.StationRangeSlack = 4 -- Reichweite der Stadt-Stationen: Prompt-Reichweite + Spielraum
MiniConfig.TravelCooldown = 3

-- Snapshot an den Client: höchstens 2×/s, bei laufender Produktion spätestens alle 1 s
MiniConfig.SnapshotMinInterval = 0.5
MiniConfig.SnapshotIdleInterval = 1

-- Altteile (games.parts)
MiniConfig.StartParts = 3

-- Schrottpresse (HTML: Auto Clicker)
MiniConfig.MaxClicksPerSecond = 20
MiniConfig.ClickBurstSeconds = 2
MiniConfig.ClickBatchInterval = 0.5
MiniConfig.PressBaseClick = 5 -- HTML clickPower
MiniConfig.PressBaseMachine = 1 -- HTML autoPower
MiniConfig.PressStartScrap = 0
MiniConfig.PressUpgradeCostGrowth = 1.145
MiniConfig.PressUpgradeCostBase = 8
MiniConfig.PressUpgradeCostStep = 1.19
MiniConfig.PressGlobalPerLevel = 0.0025
MiniConfig.PressMachineEffectFactor = 0.35
MiniConfig.PressComboStep = 0.25
MiniConfig.PressComboMax = 25
MiniConfig.PressComboWindow = 1.8
MiniConfig.PressOfflineCapHours = 8
MiniConfig.PressTickCapSeconds = 10
MiniConfig.PressWorkshopShare = 0.6 -- HTML clickerWorkshopMultiplier
MiniConfig.PressTuningShare = 0.8 -- HTML clickerTuningMultiplier
MiniConfig.PressUpgradeCount = 100

-- Schrotthändler: Schrott -> Credits (Kurs 4 : 1 mit 20 % Abschlag), keine Gegenrichtung
MiniConfig.ScrapPerCredit = 4
MiniConfig.ScrapExchangePayout = 0.8
MiniConfig.ScrapExchangePackages = { 100, 1000, 10000, 100000, 1000000, 10000000 }

-- Rebirth der Schrottpresse
MiniConfig.RebirthBaseThreshold = 1000000
MiniConfig.RebirthThresholdGrowth = 3
MiniConfig.RebirthMultiplierPerRebirth = 0.10

-- Game Passes (0 = nicht eingerichtet, kein Kauf möglich)
MiniConfig.GamePasses = {
	DoubleScrap = { id = 0, multiplier = 2 },
	PressPlus = { id = 0, machineMultiplier = 1.5 },
}

-- Minispiel-Ausbau (liegt in d.games; Hebebühnen, Auftragsannahme und Werkzeugqualität gehören 2.4.0)
MiniConfig.Upgrades = {
	{ key = "tuningLevel", name = "Tuning-Abteilung", desc = "Mehr Tuning-Ertrag und +4,5 % Werkstatt-Vergütung je Stufe.", base = 850, growth = 1.38, max = 100, start = 1 },
	{ key = "scrapyardLevel", name = "Schrottplatz-Ausbau", desc = "Mehr Altteile und öfter seltene Funde.", base = 650, growth = 1.35, max = 100, start = 1 },
}
MiniConfig.UpgradeXp = 25

-- Idle Tuning Garage (HTML: tuneCar, idleRate, collectIdle)
MiniConfig.TuningProjects = {
	{ id = "folie", name = "Folierung", minutes = 5, unlock = 1 },
	{ id = "fahrwerk", name = "Sportfahrwerk", minutes = 15, unlock = 1 },
	{ id = "abgas", name = "Sportabgasanlage", minutes = 30, unlock = 2 },
	{ id = "software", name = "Motorsoftware", minutes = 60, unlock = 3 },
	{ id = "turbo", name = "Turbo-Umbau", minutes = 120, unlock = 5 },
	{ id = "motor", name = "Motor-Revision", minutes = 240, unlock = 8 },
	{ id = "restomod", name = "Restomod-Komplettaufbau", minutes = 480, unlock = 12 },
}
MiniConfig.TuningRewardBase = 60
MiniConfig.TuningRewardExponent = 1.2
MiniConfig.TuningCostShare = 0.35
MiniConfig.TuningXpPerMinute = 0.6
MiniConfig.TuningSlotsBase = 1
MiniConfig.TuningSlotsEvery = 10
MiniConfig.TuningSlotsMax = 4
MiniConfig.TuningIdleCapHours = 8
MiniConfig.TuningLongMinutes = 480

-- Schrottplatz (HTML: buyScrap, sellParts)
MiniConfig.ScrapyardCarCost = 180
MiniConfig.ScrapyardSellParts = 5
MiniConfig.ScrapyardSellCredits = 220
MiniConfig.ScrapyardScrapPerPart = 40
MiniConfig.ScrapyardRareParts = 4 -- Ersatz, falls für das Level noch kein echtes Ersatzteil passt
MiniConfig.ScrapyardRareBrand = "nexra" -- seltene Funde sind gebrauchte Teile der Grundmarke
-- Kaufen → Zerlegen → Verkaufen bringt im Schnitt Gewinn. Damit das keine Endlosquelle wird, die nur das
-- Remote-Budget begrenzt: Zerlegen erst nach einer Vorbereitungszeit, und nur begrenzt viele Fahrzeuge pro Tag (UTC).
MiniConfig.ScrapyardDismantleSeconds = 8
MiniConfig.ScrapyardCarsPerDay = 25

-- Mechaniker-Quiz (HTML: answerQuestion)
MiniConfig.QuizCorrectCredits = 90
MiniConfig.QuizCorrectXp = 20
MiniConfig.QuizWrongXp = 4
MiniConfig.QuizCooldown = 1
-- Richtige Antworten bringen Credits und XP nur bis zu diesem Tageszähler (UTC); danach nur Diagnosepunkte.
MiniConfig.QuizPaidPerDay = 40
MiniConfig.DiagReductionPerPoint = 0.015
MiniConfig.DiagReductionCap = 0.35

-- Parkplatz-Chaos (HTML: startParking, tapSpot)
MiniConfig.ParkingSize = 4
MiniConfig.ParkingCars = 7
MiniConfig.ParkingRewardBase = 120
MiniConfig.ParkingRewardPerStreak = 15
MiniConfig.ParkingXp = 16
MiniConfig.CustomerBonusPerStreak = 0.03
MiniConfig.CustomerBonusCap = 1.7
MiniConfig.ParkingOfferBonusEvery = 5
MiniConfig.ParkingOfferBonusMax = 5
-- Der Serienanteil der Belohnung wächst nur bis zu der Serie, bei der auch der Kundenbonus gedeckelt ist
-- (ceil((1,7 − 1) / 0,03) = 24). Bezahlte Lösungen (Credits, XP, Ruf) höchstens ParkingPaidPerDay pro Tag (UTC).
MiniConfig.ParkingRewardStreakCap = math.ceil((MiniConfig.CustomerBonusCap - 1) / MiniConfig.CustomerBonusPerStreak - 1e-9)
MiniConfig.ParkingPaidPerDay = 40

-- Tagesauftrag (HTML: claimDaily)
MiniConfig.DailyCredits = 350
MiniConfig.DailyParts = 3
MiniConfig.DailyXp = 40

-- Tagesziele: je Stufe ein Ziel, pro UTC-Tag deterministisch gewählt
MiniConfig.DailyGoalPool = {
	short = {
		{ id = "d_clicks", text = "Presse {1}-mal klicken", stat = "clicks", target = 300, credits = 250 },
		{ id = "d_scrap", text = "{1} Schrott pressen", stat = "pressed", target = 20000, credits = 300 },
		{ id = "d_upg", text = "{1} Presse-Upgrades kaufen", stat = "pressUpgrades", target = 5, credits = 250 },
	},
	mid = {
		{ id = "d_jobs", text = "{1} Werkstatt-Aufträge abrechnen", stat = "jobsDone", target = 3, credits = 450 },
		{ id = "d_quiz", text = "{1} Quizfragen richtig beantworten", stat = "quizCorrect", target = 3, credits = 350 },
		{ id = "d_park", text = "{1} Parkplätze freiräumen", stat = "parkingSolved", target = 2, credits = 350 },
		{ id = "d_yard", text = "{1} Fahrzeuge zerlegen", stat = "dismantled", target = 2, credits = 400 },
	},
	long = {
		{ id = "d_tune_start", text = "{1} Tuning-Projekt starten", stat = "tuningStarted", target = 1, credits = 300 },
		{ id = "d_tune_collect", text = "{1} Tuning-Projekte abholen", stat = "tuningCollected", target = 1, credits = 500 },
		{ id = "d_idle", text = "Passive Tuning-Einnahmen {1}-mal abholen", stat = "idleCollected", target = 2, credits = 300 },
	},
}

-- Meilensteine (einmalige Belohnung)
MiniConfig.Milestones = {
	{ id = "m_scrap_10k", text = "10 Tsd. Schrott gepresst", stat = "lifetimeScrap", target = 10000, credits = 500, xp = 50 },
	{ id = "m_scrap_1m", text = "1 Mio. Schrott gepresst", stat = "lifetimeScrap", target = 1000000, credits = 5000, xp = 300 },
	{ id = "m_scrap_1b", text = "1 Mrd. Schrott gepresst", stat = "lifetimeScrap", target = 1000000000, credits = 50000, xp = 2000 },
	{ id = "m_press_upg_25", text = "25 Presse-Upgrades gekauft", stat = "pressUpgrades", target = 25, credits = 1500, xp = 120 },
	{ id = "m_rebirth_1", text = "Erstes Rebirth", stat = "rebirths", target = 1, credits = 10000, xp = 500 },
	{ id = "m_jobs_10", text = "10 Aufträge abgerechnet", stat = "jobsDone", target = 10, credits = 1500, xp = 150 },
	{ id = "m_jobs_100", text = "100 Aufträge abgerechnet", stat = "jobsDone", target = 100, credits = 12000, xp = 900 },
	{ id = "m_tune_first", text = "Erstes Tuning-Projekt abgeholt", stat = "tuningCollected", target = 1, credits = 600, xp = 60 },
	{ id = "m_tune_8h", text = "Erstes 8-Std.-Tuning abgeholt", stat = "longTuning", target = 1, credits = 8000, xp = 600 },
	{ id = "m_park_5", text = "5er-Parkplatz-Serie", stat = "bestParkingStreak", target = 5, credits = 1200, xp = 120 },
	{ id = "m_quiz_25", text = "25 Quizfragen richtig", stat = "quizCorrect", target = 25, credits = 2000, xp = 200 },
	{ id = "m_yard_10", text = "10 Fahrzeuge zerlegt", stat = "dismantled", target = 10, credits = 1500, xp = 150 },
	{ id = "m_level_25", text = "Level 25 erreicht", stat = "level", target = 25, credits = 5000, xp = 0 },
}

-- Nachschlagetabellen
MiniConfig.UpgradeByKey = {}
for _, u in ipairs(MiniConfig.Upgrades) do
	MiniConfig.UpgradeByKey[u.key] = u
end
MiniConfig.TuningProjectById = {}
for _, def in ipairs(MiniConfig.TuningProjects) do
	MiniConfig.TuningProjectById[def.id] = def
end
MiniConfig.MilestoneById = {}
for _, m in ipairs(MiniConfig.Milestones) do
	MiniConfig.MilestoneById[m.id] = m
end
MiniConfig.DailyGoalById = {}
for _, tier in pairs(MiniConfig.DailyGoalPool) do
	for _, def in ipairs(tier) do
		MiniConfig.DailyGoalById[def.id] = def
	end
end

return MiniConfig
