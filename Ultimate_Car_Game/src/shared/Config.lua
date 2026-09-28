-- Config: alle Spielwerte an einer Stelle. Quelle der Formeln: reference/Ultimate_Car_Game.html
local Config = {}

Config.Version = "3.0.0"

-- DataStore
Config.ProfileStoreName = "UltimateCarGame_v2"
Config.ProfileKeyPrefix = "player_"
Config.SessionLockTimeout = 600 -- Sekunden, danach gilt eine fremde Sperre als verwaist
Config.AutosaveInterval = 60
Config.LeaderboardStoreName = "UltimateCarGame_ScrapLeaderboard_v1"
Config.LeaderboardWriteInterval = 120 -- pro Spieler
Config.LeaderboardReadInterval = 60 -- serverweit
Config.LeaderboardTopCount = 50
Config.LeaderboardScanPages = 5 -- je 100 Einträge, für die eigene Platzierung außerhalb der Top 50
Config.LeaderboardBoardRows = 10
Config.DataStoreRetries = 3

-- Remote-Budget
Config.ActionRate = 25 -- Aktionen pro Sekunde (Nachfüllrate)
Config.ActionBurst = 40
Config.RecentRequestIds = 64
Config.StationRangeSlack = 6

-- Karriere (HTML: xpNeeded, gainXP)
Config.StartCredits = 800
Config.StartParts = 3
Config.LevelUpCreditsBase = 120
Config.LevelUpCreditsPerLevel = 18
Config.LevelUpReputation = 2

-- Schrottpresse (HTML: Auto Clicker)
Config.MaxClicksPerSecond = 20
Config.ClickBurstSeconds = 2
Config.ClickBatchInterval = 0.5
Config.PressBaseClick = 5 -- HTML clickPower
Config.PressBaseMachine = 1 -- HTML autoPower
Config.PressStartScrap = 0
Config.PressUpgradeCostGrowth = 1.145
Config.PressUpgradeCostBase = 8
Config.PressUpgradeCostStep = 1.19
Config.PressGlobalPerLevel = 0.0025
Config.PressMachineEffectFactor = 0.35
Config.PressComboStep = 0.25
Config.PressComboMax = 25
Config.PressComboWindow = 1.8
Config.PressOfflineCapHours = 8
Config.PressWorkshopShare = 0.6 -- HTML clickerWorkshopMultiplier
Config.PressTuningShare = 0.8 -- HTML clickerTuningMultiplier
Config.PressUpgradeCount = 100

-- Schrotthändler (HTML: sellCarPoints, Kurs 4 : 1 mit 20 % Abschlag, hier Schrott -> Credits)
Config.ScrapPerCredit = 4
Config.ScrapExchangePayout = 0.8
Config.ScrapExchangePackages = { 100, 1000, 10000, 100000, 1000000, 10000000 }

-- Rebirth (ersetzt HTML-Prestige für die Presse)
Config.RebirthBaseThreshold = 1000000 -- Schrott in diesem Durchlauf
Config.RebirthThresholdGrowth = 3
Config.RebirthMultiplierPerRebirth = 0.10 -- HTML prestigeApMultiplier

-- Game Passes (Platzhalter: 0 = nicht eingerichtet, kein Kauf möglich)
Config.GamePasses = {
	DoubleScrap = { id = 0, multiplier = 2 },
	PressPlus = { id = 0, machineMultiplier = 1.5 },
}

-- Werkstatt (HTML: jobsCatalog, acceptJob, finishJob)
Config.Jobs = {
	{ name = "Ölwechsel", time = 18, cost = 40, reward = 150, xp = 16, parts = 1 },
	{ name = "Bremsen vorne", time = 35, cost = 95, reward = 330, xp = 30, parts = 3 },
	{ name = "Zündspulen prüfen", time = 28, cost = 70, reward = 260, xp = 25, parts = 2 },
	{ name = "Fahrwerk reparieren", time = 55, cost = 180, reward = 620, xp = 55, parts = 5 },
	{ name = "Turbolader ersetzen", time = 85, cost = 420, reward = 1350, xp = 105, parts = 8 },
	{ name = "Steuerkette erneuern", time = 110, cost = 560, reward = 1850, xp = 145, parts = 10 },
	{ name = "HV-System Diagnose", time = 70, cost = 210, reward = 920, xp = 80, parts = 4 },
}
Config.JobTierNames = { "Flottenauftrag", "Motorrevision", "Rennwagen-Aufbau", "Oldtimer-Restauration", "HV-Batterie-Instandsetzung", "Komplettumbau", "Prototypen-Service" }
Config.MaxOffers = 35

-- Ausbau (HTML: upgrades)
Config.Upgrades = {
	{ key = "bays", name = "Hebebühne", desc = "Mehr Aufträge gleichzeitig.", base = 1100, growth = 1.42, max = 50 },
	{ key = "offerSlots", name = "Auftragsannahme", desc = "Mehr gleichzeitig sichtbare Aufträge.", base = 900, growth = 1.48, max = 30 },
	{ key = "toolLevel", name = "Werkzeugqualität", desc = "Schnellere Reparaturen und mehr Schrottplatz-Teile.", base = 700, growth = 1.34, max = 100 },
	{ key = "tuningLevel", name = "Tuning-Abteilung", desc = "Mehr Tuning-Ertrag und Werkstatt-Vergütung.", base = 850, growth = 1.38, max = 100 },
	{ key = "scrapyardLevel", name = "Schrottplatz-Ausbau", desc = "Mehr Teile und seltene Funde.", base = 650, growth = 1.35, max = 100 },
}
Config.UpgradeXp = 25

-- Idle Tuning Garage (HTML: tuneCar, idleRate, collectIdle)
Config.TuningProjects = {
	{ id = "folie", name = "Folierung", minutes = 5, unlock = 1 },
	{ id = "fahrwerk", name = "Sportfahrwerk", minutes = 15, unlock = 1 },
	{ id = "abgas", name = "Sportabgasanlage", minutes = 30, unlock = 2 },
	{ id = "software", name = "Motorsoftware", minutes = 60, unlock = 3 },
	{ id = "turbo", name = "Turbo-Umbau", minutes = 120, unlock = 5 },
	{ id = "motor", name = "Motor-Revision", minutes = 240, unlock = 8 },
	{ id = "restomod", name = "Restomod-Komplettaufbau", minutes = 480, unlock = 12 },
}
Config.TuningRewardBase = 60 -- Credits bei 1 Minute
Config.TuningRewardExponent = 1.2 -- überproportional zur Laufzeit
Config.TuningCostShare = 0.35
Config.TuningXpPerMinute = 0.6
Config.TuningSlotsBase = 1
Config.TuningSlotsEvery = 10 -- +1 Slot je 10 Tuning-Stufen
Config.TuningSlotsMax = 4
Config.TuningIdleCapHours = 8
Config.TuningLongMinutes = 480

-- Schrottplatz (HTML: buyScrap, sellParts)
Config.ScrapyardCarCost = 180
Config.ScrapyardSellParts = 5
Config.ScrapyardSellCredits = 220
Config.ScrapyardScrapPerPart = 40 -- A8: Schrott beim Zerlegen
Config.ScrapyardRareParts = 4

-- Mechaniker-Quiz (HTML: answerQuestion)
Config.QuizCorrectCredits = 90
Config.QuizCorrectXp = 20
Config.QuizWrongXp = 4
Config.QuizCooldown = 1
Config.DiagReductionPerPoint = 0.015
Config.DiagReductionCap = 0.35

-- Parkplatz-Chaos (HTML: startParking, tapSpot)
Config.ParkingSize = 4
Config.ParkingCars = 7
Config.ParkingRewardBase = 120
Config.ParkingRewardPerStreak = 15
Config.ParkingXp = 16
Config.CustomerBonusPerStreak = 0.03
Config.CustomerBonusCap = 1.7
Config.ParkingOfferBonusEvery = 5
Config.ParkingOfferBonusMax = 5

-- Tagesauftrag (HTML: claimDaily)
Config.DailyCredits = 350
Config.DailyParts = 3
Config.DailyXp = 40

-- Tagesziele: je Stufe ein Ziel, pro UTC-Tag deterministisch gewählt
Config.DailyGoalPool = {
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
Config.Milestones = {
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

-- Server-Tick
Config.TickInterval = 1
Config.SyncInterval = 0.25

return Config
