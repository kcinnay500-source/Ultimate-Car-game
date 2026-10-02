-- GameConfig: die eine Stelle für alle Zahlen und Tabellen der Ausbaustufe 4 (docs/PHASE4_CONTRACT.md §3):
-- Places, Zonen, Freischaltungen, Prestige, Party, Tutorial, Beginner-Hinweise und die XP-Regler.
-- Tycoon (Meilenstein 4), Open World (Meilenstein 6) und Story (Meilenstein 7) sind gefüllt; Shop ist als leere Tabelle
-- vorbereitet (Meilenstein 8). 2.4.0-Zahlen bleiben in GarageShared.Config, Minispiel-Zahlen in MiniConfig,
-- Autos in CarCatalog (das nimmt die Händler-Level aus Unlocks.CarLevel).
-- Rein (keine Instanzen, keine Dienste), auf Server und Client nutzbar (ReplicatedStorage.GarageShared.Mini).
-- Balance-Änderungen anderer Teams gehen nur über diese Datei, nie über Zahlen im Code.
local C = require(script.Parent.Parent:WaitForChild("Config"))

local GameConfig = {}

export type UnlockEntry = {
	level: number, key: string, kind: string, title: string, hint: string, tab: string?, special: boolean?, order: number,
}
export type PrestigeReward = {
	rank: number, title: string, incomePct: number, discountPct: number, cosmetic: string, tycoonRebirthPct: number,
}
export type TutorialStep = { id: string, text: string, target: string?, zone: string?, event: string }
export type Hint = { id: string, text: string, when: string }

---------------------------------------------------------------- Places und Modi (§1)
-- Place-IDs: Platzhalter 0 = nichts veröffentlicht. 0 (oder Studio, oder Ziel im selben Place) -> Simulation.
GameConfig.Places = { lobby = 0, openworld = 0, tycoon = 0 }
GameConfig.PlaceKinds = { "all", "lobby", "openworld", "tycoon" } -- Attribut PlaceKind an GarageShared
GameConfig.Modes = { "lobby", "openworld", "tycoon" } -- p.mode, d.games.meta.lastMode, Snapshot mode
GameConfig.DefaultMode = "lobby" -- allererster Beitritt im all-Place
GameConfig.SimulationNotice = "Studio-Simulation: Ortswechsel ohne Teleport"
-- TeleportData (nur Strings/Zahlen/Booleans, geprüft): erlaubte Schlüssel und Längen
GameConfig.TeleportDataKeys = { mode = "string", single = "boolean", party = "string" }
GameConfig.TeleportDataMaxLength = 32

---------------------------------------------------------------- Zonen (Modelle und Ankunftsschlüssel im all-Place)
-- model = Name unter workspace, arrival = Schlüssel unter <model>.Arrivals, spawn = SpawnLocation der Zone,
-- stations = Stationsschlüssel der Zone (Attribut MiniTab = tab). Die Stadt behält ihre Stationen aus
-- tools/worldgen/contract.py. Geometrie (Lobby bei Z -700, Tycoon ab Z +700) liegt allein bei worldgen.
GameConfig.Zones = {
	lobby = {
		model = "Lobby", arrival = "hub", spawn = "LobbySpawn", tab = "lobby",
		stations = { "mode_tycoon", "mode_openworld", "settings", "party", "tutorial" },
	},
	openworld = { model = "City", arrival = "hub", spawn = "CitySpawn", tab = "map", stations = {} },
	tycoon = { model = "Tycoon", arrival = "hub", spawn = "TycoonSpawn", tab = "tycoon", stations = { "tycoon_market", "tycoon" } },
}

---------------------------------------------------------------- Freischaltungen (§3)
-- Schlüssel: "feature:<tab>", "car:<modelId>", "building:<typ>", "story:<kapitel>", "mode:<modus>", "auction:player".
-- kind: feature | car | building | story | mode. tab = Tab der Minispiel-Oberfläche, den die Freischaltung öffnet.
-- Das Balance-Team darf Level verschieben; Nord Elys E9 bleibt 90. Sondermodelle (special) gibt es nur in
-- NPC-Auktionen; ihr Level ist die Voraussetzung zum Mitbieten.
GameConfig.UnlockKinds = { "mode", "feature", "building", "car", "story" }

local function carName(id: string, fallback: string): string
	local car = C.CarById and C.CarById[id]
	return car and car.name or fallback
end

local function entry(level: number, key: string, kind: string, title: string, hint: string, tab: string?, special: boolean?): UnlockEntry
	return { level = level, key = key, kind = kind, title = title, hint = hint, tab = tab, special = special, order = 0 }
end

local function car(level: number, id: string, fallbackName: string, special: boolean?): UnlockEntry
	local hint = special and "Sondermodell: nur im Auktionshaus bei NPC-Auktionen zu gewinnen."
		or "Ab jetzt beim Händler im Autohaus kaufbar."
	return entry(level, "car:" .. id, "car", carName(id, fallbackName), hint, special and "auction" or "dealer", special)
end

GameConfig.Unlocks = {
	entry(1, "mode:openworld", "mode", "Open World", "Die Werkstattmeile: deine Werkstatt, die Stadt und alle Minispiele.", "lobby"),
	entry(1, "mode:tycoon", "mode", "Schnelles Spiel", "Eine Tycoon-Runde mit Bargeld: bau dein Gebäude bis Stufe 5 aus.", "lobby"),
	entry(1, "story:1", "story", "Kapitel 1: Der Kiesplatz", "Verkaufe am Kiesplatz deine ersten Gebrauchtwagen.", "story"),
	entry(2, "feature:press", "feature", "Schrottpresse", "Klick Schrott zusammen und tausch ihn beim Schrotthändler gegen Credits.", "press"),
	entry(3, "feature:scrapyard", "feature", "Schrottplatz", "Kauf alte Autos, zerleg sie und verkauf die Teile.", "scrapyard"),
	entry(3, "feature:dealer", "feature", "Autohaus", "Autos ansehen, Probefahrt machen und das erste eigene Auto kaufen.", "dealer"),
	car(3, "komet", "Komet C1"),
	entry(4, "feature:quiz", "feature", "Mechaniker-Quiz", "Richtige Antworten bringen Diagnosepunkte, die Reparaturen verkürzen.", "quiz"),
	entry(5, "feature:parking", "feature", "Parkplatz-Chaos", "Räum Parkplätze frei; eine lange Serie bringt Kundenbonus in der Werkstatt.", "parking"),
	entry(5, "story:2", "story", "Kapitel 2: Die erste Werkstatt", "Aufträge abrechnen, Hebebühne 2 kaufen, das Mechaniker-Quiz bestehen.", "story"),
	entry(6, "feature:tuning", "feature", "Tuning-Projekte", "Projekte laufen weiter, auch wenn du nicht da bist – später abholen.", "tuning"),
	entry(8, "feature:track", "feature", "Teststrecke", "Zeitfahren mit Checkpoints; nur neue Bestzeiten bringen Credits.", "track"),
	entry(8, "feature:carwash", "feature", "Waschstraße", "Lass dein Auto glänzen.", "carwash"),
	car(8, "komet_s2", "Komet S2"),
	entry(10, "feature:arcade", "feature", "Spielhalle", "Acht Automaten mit Geschicklichkeitsspielen, Credits nur nach Leistung.", "arcade"),
	entry(10, "building:autohaus", "building", "Gebäude: Autohaus", "Ein eigenes Autohaus auf deinem Grundstück: passive Verkaufserlöse und Händlerrabatt.", "buildings"),
	car(10, "komet_rally", "Komet C1 Rallye", true),
	entry(12, "feature:auction", "feature", "Auktionshaus", "Biete bei NPC-Auktionen auf seltene Sondermodelle.", "auction"),
	car(14, "nord", "Nord R4"),
	entry(15, "story:3", "story", "Kapitel 3: Das Autohaus", "Autohaus bauen, ein Auto kaufen und einfahren, eine Auktion gewinnen oder einliefern.", "story"),
	entry(18, "building:schrottplatz", "building", "Gebäude: Schrottplatz", "Ein eigener Schrottplatz: passiver Schrott und Altteile.", "buildings"),
	car(18, "nord_classic", "Nord R4 Classic", true),
	entry(20, "auction:player", "feature", "Spieler-Auktionen", "Gib eigene Autos in die Auktion und biete auf Autos anderer Spieler.", "auction"),
	car(22, "komet_urban", "Komet Urban"),
	entry(30, "story:4", "story", "Kapitel 4: Die Produktion", "Schrottplatz und Produktion bauen, Sondermodelle verkaufen.", "story"),
	car(32, "atlas", "Nord Atlas Tourer"),
	entry(30, "building:produktion", "building", "Gebäude: Produktion", "Deine Automobil-Produktion: Bauteil-Pakete, ab Stufe 4 ein Auto-Gutschein.", "buildings"), -- wie Kapitel 4 (c4_m2 baut sie)
	car(45, "vektor", "Vektor RS"),
	entry(50, "story:5", "story", "Kapitel 5: Der Mega-Verkäufer", "Produktion Stufe 4, zehn Bestpreis-Verkäufe, ein Traumwagen in der Garage.", "story"),
	car(50, "vektor_gold", "Vektor RS Goldstück", true),
	car(58, "vektor_gtx", "Vektor GTX"),
	car(72, "aureon", "Vektor Aureon V12"),
	car(78, "aureon_nero", "Vektor Aureon Nero", true),
	car(90, "elys", "Nord Elys E9"),
	car(95, "elys_proto", "Nord Elys Prototyp", true),
}

---------------------------------------------------------------- Prestige (§4)
-- Rang = PrestigeRules.RankFor(d.level), nie gespeichert. Schwellen: 100, 250, 500, danach
-- ceil(vorherige × Growth / RoundTo) × RoundTo (900, 1.650, 3.000, ...), Deckel MaxRank.
-- Kein Reset: Level, XP, Credits, Autos bleiben. Belohnungen sind dauerhaft und werden je Rang einmal abgeholt.
GameConfig.Prestige = {
	MaxRank = 20,
	BaseThresholds = { 100, 250, 500 },
	Growth = 1.8,
	RoundTo = 50,
	IncomePerRank = 0.02, -- Credits-Bonus auf alle Einnahmen je Rang (CrossBonus.PrestigeIncome)
	IncomeCap = 0.30,
	DiscountPerRank = 0.01, -- Rabatt im Autohaus je Rang
	DiscountCap = 0.10,
	RebirthBonusFromRank = 3, -- ab diesem Rang ein zusätzlicher Tycoon-Rebirth-Bonus
	RebirthBonus = 0.05,
	TitleTiers = { "Meisterschrauber", "Schrauber-Champion", "Motor-Meister", "Auto-Legende" }, -- je 5 Ränge
	Rewards = {} :: { PrestigeReward },
}
do
	local P = GameConfig.Prestige
	local roman = { "I", "II", "III", "IV", "V" }
	for rank = 1, P.MaxRank do
		local tier = P.TitleTiers[math.min(#P.TitleTiers, math.floor((rank - 1) / 5) + 1)]
		P.Rewards[rank] = {
			rank = rank,
			title = tier .. " " .. roman[(rank - 1) % 5 + 1],
			-- Gesamtbonus auf diesem Rang in % (ganzzahlig gerundet: 7 × 0,02 × 100 wäre sonst 14,000000000000002)
			incomePct = math.floor(math.min(rank * P.IncomePerRank, P.IncomeCap) * 100 + 0.5),
			discountPct = math.floor(math.min(rank * P.DiscountPerRank, P.DiscountCap) * 100 + 0.5),
			cosmetic = (rank % 2 == 1) and ("wrap_prestige_" .. rank) or ("rims_prestige_" .. rank), -- Shop-Kosmetik-Id (Meilenstein 8)
			tycoonRebirthPct = rank >= P.RebirthBonusFromRank and P.RebirthBonus * 100 or 0,
		}
	end
end

---------------------------------------------------------------- Party (§5)
GameConfig.Party = {
	MaxMembers = 4,
	CodeLength = 4,
	CodeAlphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", -- ohne I, O, 0, 1 (Verwechslung)
	CodeTries = 20, -- Versuche für einen freien Code
	InviteSeconds = 120, -- Beitrittsangebot (Code) gültig, danach muss der Leiter neu einladen
	TravelOfferSeconds = 30, -- Reiseangebot des Leiters an die Mitglieder (lobby_go)
	CreateCooldown = 3,
	JoinCooldown = 2,
	NoticeSeconds = 5, -- Anzeige von mini_notice { kind = "party" } auf dem Client
}

---------------------------------------------------------------- Tutorial (§6)
-- Fortschritt bestätigt der Server aus echten Ereignissen. Das Tutorial läuft nur in der Open World (Modus
-- openworld); in Lobby und Schnellem Spiel ruht es (TutorialService). Neustart am Tutorial-Kiosk der Lobby
-- (tutorial_restart), die Belohnung gibt es nur einmal (meta.tutorialRewarded). event:
--   "next"            reiner Lese-Schritt, der Client sendet tutorial_next {step}
--   "station:<key>"   2.4.0-Plot-Station geöffnet (World.Create -> callback("station", key)); zone = "plot"
--   "tab:<tab>"       Stadt-Station mit Attribut MiniTab = <tab> geöffnet (MiniService-Prompt); zone = "city"
--   "job:accepted"    ein Auftrag liegt in d.jobs (Phase diagnose oder später)
--   "job:repair"      ein Auftrag hat die Diagnose hinter sich (Phase repair, working, verify oder invoice)
--   "job:invoice"     ein Auftrag ist fertig repariert und geprüft (Phase invoice)
--   "settled"         Mini.OnSettled (Abrechnung)
--   "action:<name>"   eine Mini-Aktion war erfolgreich (z. B. mini_travel)
-- target = Stationsschlüssel für den Pfeil/Marker im Client (zone plot: Plot.Stations.<key>, zone city: City.Stations.<key>).
GameConfig.Tutorial = {
	Reward = { credits = 500, xp = 60 }, -- einmalig am Ende (nicht beim Überspringen, nicht nach einem Neustart)
	Steps = {
		{ id = "move", text = "Willkommen in deiner Werkstatt! Lauf ein paar Schritte – mit WASD oder dem Joystick.", target = nil, zone = nil, event = "next" },
		{ id = "menu", text = "Öffne das Menü mit der Taste M oder dem Knopf „Minispiele“. Dort findest du alles Wichtige.", target = nil, zone = nil, event = "next" },
		{ id = "reception", text = "Geh zum Empfang deiner Werkstatt und drück E.", target = "workshop", zone = "plot", event = "station:workshop" },
		{ id = "accept", text = "Nimm am Empfang einen Auftrag an. Ein Kunde bringt dir sein Auto.", target = "workshop", zone = "plot", event = "job:accepted" },
		{ id = "obd", text = "Steck das OBD-Gerät ans Auto und finde den Fehler.", target = nil, zone = nil, event = "job:repair" },
		{ id = "repair", text = "Repariere das Auto Schritt für Schritt bis zur Endkontrolle.", target = nil, zone = nil, event = "job:invoice" },
		{ id = "settle", text = "Rechne den Auftrag am Empfang ab – die Credits gehören dir!", target = "workshop", zone = "plot", event = "settled" },
		{ id = "map", text = "Drück M (oder den Knopf „Minispiele“) und öffne den Tab „Stadtplan“ – reise damit in die Stadt.", target = nil, zone = nil, event = "action:mini_travel" },
		{ id = "dealer", text = "Schau im Autohaus vorbei und drück dort E. Kaufen kannst du ab Level 3 – ansehen darfst du jetzt schon.", target = "dealer", zone = "city", event = "tab:dealer" },
		{ id = "goals", text = "Sieh dir an der Infotafel deine Tagesziele an – jeden Tag gibt es neue.", target = "goals", zone = "city", event = "tab:goals" },
		-- Meilenstein 7: Anschluss an die Story (Kapitel 1 „Der Kiesplatz“, Station City.Stations.kiesplatz, Tab story)
		{ id = "kiesplatz", text = "Zum Schluss: Reise mit dem Stadtplan zum Kiesplatz am Stadtrand und drück dort E. Da beginnt deine Story – vom Kiesplatzhändler zum Mega-Verkäufer. Viel Spaß in der Werkstattmeile!", target = "kiesplatz", zone = "city", event = "tab:story" },
	} :: { TutorialStep },
	EventKinds = { "next", "station", "tab", "job", "settled", "action" },
}

---------------------------------------------------------------- Beginner-Hinweise (§6)
-- when: "unlock:<key>" (Level mit Freischaltung erreicht), "station:<key>" (Station geöffnet, Plot oder Stadt
-- oder Lobby), "first:<stat>" (Statistik aus MiniRules.STAT_KEYS zum ersten Mal > 0). Je einmal
-- (meta.hintsSeen), nur bei meta.beginner = true, Anzeige als Karte oben rechts.
GameConfig.Hints = {
	{ id = "h_workshop", when = "station:workshop", text = "Am Empfang nimmst du Aufträge an und rechnest fertige Autos ab." },
	{ id = "h_first_job", when = "first:jobsDone", text = "Super, dein erster Auftrag! Jeder Auftrag bringt Credits und XP – mit XP steigst du im Level auf." },
	{ id = "h_first_dismantle", when = "first:dismantled", text = "Zerlegte Autos bringen Altteile. Altteile brauchst du für Tuning-Projekte." },
	{ id = "h_press", when = "unlock:feature:press", text = "Neu: die Schrottpresse! Klick Schrott zusammen und tausch ihn beim Schrotthändler gegen Credits." },
	{ id = "h_scrapyard", when = "unlock:feature:scrapyard", text = "Neu: der Schrottplatz! Kauf ein altes Auto, zerleg es und verkauf die Teile." },
	{ id = "h_dealer", when = "unlock:feature:dealer", text = "Neu: das Autohaus! Mach eine Probefahrt – dein erstes eigenes Auto ist nicht mehr weit." },
	{ id = "h_quiz", when = "unlock:feature:quiz", text = "Neu: das Mechaniker-Quiz! Richtige Antworten bringen Diagnosepunkte, die deine Reparaturen verkürzen." },
	{ id = "h_parking", when = "unlock:feature:parking", text = "Neu: Parkplatz-Chaos! Eine lange Serie bringt dir mehr Kundenbonus in der Werkstatt." },
	{ id = "h_tuning", when = "unlock:feature:tuning", text = "Neu: Tuning-Projekte! Sie laufen weiter, auch wenn du nicht da bist – hol sie später ab." },
	{ id = "h_track", when = "unlock:feature:track", text = "Neu: die Teststrecke! Nur neue Bestzeiten bringen Credits, also übe die Kurven." },
	{ id = "h_arcade", when = "unlock:feature:arcade", text = "Neu: die Spielhalle! Punkte gibt es nur für Geschick, und pro Tag gibt es ein Limit." },
	{ id = "h_building", when = "unlock:building:autohaus", text = "Neu: Bau auf deinem Grundstück ein Autohaus. Es verdient Credits, während du unterwegs bist." },
	{ id = "h_auction", when = "unlock:feature:auction", text = "Neu: das Auktionshaus! Biete nur so viel, wie du wirklich ausgeben willst." },
	{ id = "h_player_auction", when = "unlock:auction:player", text = "Neu: Du kannst jetzt eigene Autos in die Auktion geben." },
	{ id = "h_story2", when = "unlock:story:2", text = "Neues Story-Kapitel! Öffne den Tab „Story“ und schau, was als Nächstes ansteht." },
	{ id = "h_map", when = "station:map", text = "Mit dem Stadtplan reist du schnell durch die Stadt – und jederzeit zurück zu deiner Werkstatt." },
	{ id = "h_shop", when = "station:shop", text = "Im Credit-Center gibt es Credits und Pässe. Alles im Spiel schaffst du auch ohne Robux." },
	{ id = "h_tycoon", when = "station:mode_tycoon", text = "Schnelles Spiel: eine Tycoon-Runde mit Bargeld. Fertige Runden bringen dauerhafte Boni in der Open World." },
} :: { Hint }

---------------------------------------------------------------- XP-Regler (§3)
-- Platzhalter für das Balance-Team: Ziel Level 50 nach etwa 8 Std., Level 90 nach etwa 25–35 Std. gemischtem
-- Spiel. Nachgeregelt wird nur hier, nie in Rules.XPNeeded. Story/Missionen: Meilenstein 7, Tycoon: Meilenstein 4.
GameConfig.XP = {
	Tutorial = 60, -- = Tutorial.Reward.xp
	StoryMission = { 60, 120, 250, 500, 900 }, -- je Mission nach Kapitel (Platzhalter)
	StoryChapter = { 150, 300, 600, 1200, 2500 }, -- Abschluss je Kapitel (Platzhalter)
	SideMission = 50, -- Nebenmission (Platzhalter)
	TycoonStage = 40, -- je erreichter Tycoon-Stufe (Platzhalter)
	TycoonRun = 300, -- je abgeschlossenem Durchlauf / Rebirth (Platzhalter)
	OwBuild = 30, -- je gebauter Gebäudestufe in der Open World (Platzhalter)
}

---------------------------------------------------------------- Schnelles Spiel / Tycoon (§8, Meilenstein 4)
-- Alle Zahlen des Tycoon-Modus. Bargeld ist NIE Credits und verlässt den Durchlauf nie.
-- Feste IDs (Teams arbeiten parallel): Gebäudetypen werkstatt|autohaus|produktion|schrottplatz, Stufen 1..5,
-- Upgrade-Ids "<typ>_s<stufe>_u<k>" mit k=1 Produzent (+Bargeld/s), k=2 Tempo (×Rate), k=3 Lager (+Behälter,
-- erzeugt Handelsware), k=4 Deko (kosmetisch + kleiner Bonus); Stufen-Pad "<typ>_stage<n>" (n = 2..5).
-- Vorlagen: ServerStorage.TycoonTemplates.<typ>.Stage_<n>.
-- Balance: Kosten = Rate zum Kaufzeitpunkt × Wartezeit (Tuning.Waits) × Tuning.Scale, auf runde Zahlen gerundet.
-- Ziel: ein aufmerksamer Spieler braucht ≈ 5 Std. bis Stufe 5 komplett (tests/test_tycoon_rules.lua simuliert das
-- gierig und prüft 4 h ≤ Zeit ≤ 6,5 h je Gebäudetyp). Nachregeln nur hier (Tuning), nie im Code.
export type TycoonUpgrade = {
	id: string, typ: string, stage: number, k: number, kind: string, name: string, desc: string, cost: number,
	rate: number?, mult: number?, cap: number?, item: string?, perMin: number?, bonus: number?,
}
export type TycoonStage = {
	stage: number, price: number, items: { [string]: number }, capacity: number, Upgrades: { TycoonUpgrade }, stageId: string?,
}
export type TycoonBuilding = {
	typ: string, name: string, desc: string, baseRate: number, items: { string }, Stages: { TycoonStage },
}

GameConfig.Tycoon = {
	Types = { "werkstatt", "autohaus", "produktion", "schrottplatz" },
	MaxStage = 5,
	UpgradesPerStage = 4,
	UpgradeKinds = { "producer", "tempo", "lager", "deko" }, -- k = 1..4
	TickSeconds = 0.5, -- Server-Tick (TycoonService)
	MaxTickSeconds = 5, -- längster angerechneter Abstand zwischen zwei Ticks (Offline zählt nicht)
	StartCash = 50, -- Bargeld beim Rundenstart
	ItemCap = 999, -- Lagerdeckel je Ware
	TradeTTL = 120, -- Angebot gültig (s)
	TradeMaxOpen = 5, -- offene Angebote je Spieler
	TradeMaxQty = 999,
	TradeMinPrice = 1,
	TradeMaxPrice = 999999999, -- höchster Angebotspreis (Server prüft, Client deckelt die Stepper)
	TradeOfferInterval = 15, -- s zwischen zwei Angeboten desselben Absenders an denselben Empfänger (Toast-Spam)
	TradeDeclineBlock = 300, -- s Sperre für neue Angebote an einen Empfänger, der abgelehnt hat
	MarketBroadcastInterval = 1, -- Marktplatz-Hinweis (tycoon_market) höchstens so oft je s; Rest im Tick gebündelt
	-- Zeiten des TycoonService (s): Pad-Entprellung je Pad, Toast-Drossel je Grund, Beschriftungen und Snapshot
	-- höchstens 1×/s im laufenden Durchlauf, Nachvergabe eines Grundstücks alle 2 s
	PadDebounce = 0.5,
	PadGrace = 1.5, -- Schonfrist neuer Pads nach dem Aufbau (Figur steht beim Stufenaufstieg schon auf dem nächsten Pad)
	PromptDebounce = 0.5, -- Start-/Sammel-Pad-Prompt je Spieler höchstens so oft (s)
	PromptRangeSlack = 4, -- Prompt nur, wenn die Figur höchstens MaxActivationDistance + Slack vom Pad entfernt ist
	PadToastSeconds = 2,
	-- Pad-Farben je Zustand (Server färbt die Pads/Preise, der Client blitzt darauf zurück)
	PadColors = { owned = { 62, 217, 166 }, ready = { 247, 176, 63 }, locked = { 156, 170, 177 } },
	StageRequiresAllUpgrades = true, -- Stufen-Pad erst, wenn alle Upgrades der aktuellen Stufe gekauft sind
	LabelInterval = 1,
	SnapshotInterval = 1,
	PlotRetry = 2,
	Rebirth = { boostPct = 15, capPct = 150, requiresStage = 5, requiresAllUpgrades = true },
	-- Bonus-Tabelle Open World (§8): min(n, maxRuns) × step je abgeschlossenem Durchlauf des Typs
	Bonus = {
		werkstatt = { step = 0.02, maxRuns = 5, text = "Werkstatt-Vergütung" },
		autohaus = { step = 0.015, maxRuns = 5, text = "Händlerrabatt" },
		produktion = { step = 0.03, maxRuns = 5, text = "Tuning-Tempo" },
		schrottplatz = { step = 0.03, maxRuns = 5, text = "Schrott" },
	},
	-- XP je Durchlauf/Stufe: der Regler liegt in GameConfig.XP (TycoonRun, TycoonStage), hier nur der Verweis
	XP = { run = GameConfig.XP.TycoonRun, stage = GameConfig.XP.TycoonStage },
	-- Grundstücke: Pivot x/z/rot wie tools/worldgen/tycoon.py SLOTS (Reihe A Z 760 Front Süd, Reihe B Z 940 Front Nord)
	Slots = {
		{ slot = 1, x = -45, z = 760, rot = 0 },
		{ slot = 2, x = 45, z = 760, rot = 0 },
		{ slot = 3, x = -45, z = 940, rot = 180 },
		{ slot = 4, x = 45, z = 940, rot = 180 },
		{ slot = 5, x = -135, z = 760, rot = 0 },
		{ slot = 6, x = 135, z = 760, rot = 0 },
		{ slot = 7, x = -135, z = 940, rot = 180 },
		{ slot = 8, x = 135, z = 940, rot = 180 },
	},
	-- Handelsware (nur Tycoon, nur Bargeld). guide = Richtpreis je Stück für die Marktplatz-Anzeige
	Items = {
		bauteile = { name = "Bauteile", guide = 40 },
		reifen = { name = "Reifen", guide = 60 },
		lack = { name = "Lack", guide = 90 },
		schrott = { name = "Schrott", guide = 25 },
	},
	ItemList = { "bauteile", "reifen", "lack", "schrott" },
	-- Balance-Tuning (Erzeuger der Tabellen unten)
	Tuning = {
		Scale = 1.15,
		CapSeconds = 240, -- Behälter der Stufe fasst so viele Sekunden Einkommen (Rate bei Stufenbeginn)
		LagerCapSeconds = 300, -- Lager-Upgrade: zusätzlicher Behälter in Sekunden Einkommen
		-- je Stufe: prod = Rate des Produzenten als Vielfaches der Grundrate, tempo = Faktor, deko = Bonus,
		-- waits = Wartezeit (s) bei aktueller Rate für u1..u4, stageWait = Wartezeit für das Stufen-Pad,
		-- perMin = Warenausstoß des Lagers je Minute, itemIndex = 1 (Hauptware) | 2 (Zweitware)
		Stages = {
			{ prod = 2, tempo = 1.5, deko = 0.05, waits = { 60, 120, 150, 150 }, stageWait = 300, perMin = 1.0, itemIndex = 1 },
			{ prod = 6, tempo = 1.5, deko = 0.05, waits = { 240, 300, 300, 300 }, stageWait = 600, perMin = 1.5, itemIndex = 1 },
			{ prod = 18, tempo = 1.5, deko = 0.05, waits = { 420, 480, 480, 480 }, stageWait = 900, perMin = 1.0, itemIndex = 2 },
			{ prod = 54, tempo = 1.5, deko = 0.05, waits = { 600, 720, 720, 720 }, stageWait = 1500, perMin = 2.0, itemIndex = 2 },
			{ prod = 160, tempo = 1.5, deko = 0.05, waits = { 1200, 1500, 1500, 1800 }, stageWait = 0, perMin = 2.0, itemIndex = 1 },
		},
		-- Warenbedarf für die Stufen-Pads ab Stufe 3: { Hauptware, Zweitware }
		StageItems = { [3] = { 15, 0 }, [4] = { 40, 10 }, [5] = { 80, 30 } },
	},
	Buildings = {} :: { [string]: TycoonBuilding },
	UpgradeById = {} :: { [string]: TycoonUpgrade },
	StageById = {} :: { [string]: { typ: string, stage: number } },
}

do
	local TY = GameConfig.Tycoon
	local flavour = {
		werkstatt = {
			name = "Werkstatt", desc = "Von der Garage zur Meisterwerkstatt: Hebebühnen, Werkzeug und viele Kunden.",
			baseRate = 2, items = { "bauteile", "reifen" },
			producers = { "Hebebühne", "Zweite Bühne", "Motorenprüfstand", "Lackierkabine", "Meisterhalle" },
			tempo = { "Akkuschrauber", "Werkzeugwagen", "Schnellheber", "Diagnose-Computer", "Roboterarm" },
			lager = { "Regal", "Teilelager", "Reifenlager", "Hochregal", "Logistikhalle" },
			deko = { "Firmenschild", "Blumenkübel", "Neonschrift", "Kundencafé", "Pokalvitrine" },
		},
		autohaus = {
			name = "Autohaus", desc = "Vom Kiesplatz zum Glaspalast: mehr Ausstellungsfläche, mehr Verkäufe.",
			baseRate = 2.5, items = { "lack", "reifen" },
			producers = { "Verkaufsstand", "Showroom", "Glashalle", "Probefahrt-Strecke", "Luxus-Etage" },
			tempo = { "Prospekte", "Verkaufstraining", "Online-Anzeigen", "Finanzierungsbüro", "Drehbühne" },
			lager = { "Stellplätze", "Parkdeck", "Lackdepot", "Reifenhotel", "Auslieferungshalle" },
			deko = { "Fahnenmast", "Ballonbogen", "Lichtband", "Kaffeebar", "Springbrunnen" },
		},
		produktion = {
			name = "Produktion", desc = "Deine eigene Autofabrik: Band, Presse, Roboter – und Bauteile für alle.",
			baseRate = 3, items = { "bauteile", "lack" },
			producers = { "Montageband", "Karosseriepresse", "Schweißroboter", "Lackierstraße", "Endmontage" },
			tempo = { "Schichtplan", "Förderband", "Roboterzelle", "Just-in-time", "Vollautomatik" },
			lager = { "Kistenlager", "Bauteilelager", "Lackdepot", "Hochregallager", "Verladehof" },
			deko = { "Werkslogo", "Schornstein", "Testparcours", "Kantine", "Aussichtsturm" },
		},
		schrottplatz = {
			name = "Schrottplatz", desc = "Aus Altmetall wird Bargeld: Presse, Kran und Berge von Schrott.",
			baseRate = 1.5, items = { "schrott", "bauteile" },
			producers = { "Schrottpresse", "Greifkran", "Shredder", "Sortieranlage", "Schmelzofen" },
			tempo = { "Brechstange", "Gabelstapler", "Magnetkran", "Förderschnecke", "Laserschneider" },
			lager = { "Schrottberg", "Container", "Teilecontainer", "Lagerhalle", "Verladerampe" },
			deko = { "Wachhund-Hütte", "Reifenstapel", "Autoturm", "Graffiti-Wand", "Leuchtreklame" },
		},
	}
	local kindNames = { "producer", "tempo", "lager", "deko" }
	local descs = {
		producer = "Erzeugt mehr Bargeld je Sekunde.",
		tempo = "Alle Produzenten arbeiten schneller.",
		lager = "Größerer Sammelbehälter – und erzeugt Handelsware fürs Lager.",
		deko = "Schmückt dein Grundstück und bringt einen kleinen Bonus.",
	}
	local function nice(x: number): number
		if x < 100 then
			return math.max(5, math.floor(x / 5 + 0.5) * 5)
		end
		local m = 10 ^ (math.floor(math.log10(x)) - 1)
		return math.floor(x / m + 0.5) * m
	end
	for _, typ in ipairs(TY.Types) do
		local f = flavour[typ]
		local b: TycoonBuilding = { typ = typ, name = f.name, desc = f.desc, baseRate = f.baseRate, items = f.items, Stages = {} }
		local prodSum, tempo, deko = f.baseRate, 1, 1
		for s = 1, TY.MaxStage do
			local t = TY.Tuning.Stages[s]
			local startRate = prodSum * tempo * deko
			local st: TycoonStage = {
				stage = s, price = 0, items = {}, capacity = nice(startRate * TY.Tuning.CapSeconds), Upgrades = {},
				stageId = s < TY.MaxStage and (typ .. "_stage" .. (s + 1)) or nil,
			}
			for k = 1, TY.UpgradesPerStage do
				local rate = prodSum * tempo * deko
				local kind = kindNames[k]
				local u: TycoonUpgrade = {
					id = typ .. "_s" .. s .. "_u" .. k, typ = typ, stage = s, k = k, kind = kind,
					name = f[kind == "producer" and "producers" or kind][s], desc = descs[kind],
					cost = nice(rate * t.waits[k] * TY.Tuning.Scale),
				}
				if kind == "producer" then
					u.rate = f.baseRate * t.prod
					prodSum += u.rate
				elseif kind == "tempo" then
					u.mult = t.tempo
					tempo *= t.tempo
				elseif kind == "lager" then
					u.cap = nice(rate * TY.Tuning.LagerCapSeconds)
					u.item = f.items[t.itemIndex]
					u.perMin = t.perMin
				else
					u.bonus = t.deko
					deko += t.deko
				end
				st.Upgrades[k] = u
				TY.UpgradeById[u.id] = u
			end
			b.Stages[s] = st
		end
		-- Stufen-Pads: Preis und Warenbedarf der Stufe n stehen an Stages[n] (bezahlt aus Stufe n-1 mit der Rate
		-- nach allen Upgrades der Vorstufe)
		local ps, tm, dk = f.baseRate, 1, 1
		for s = 2, TY.MaxStage do
			local t = TY.Tuning.Stages[s - 1]
			ps += f.baseRate * t.prod
			tm *= t.tempo
			dk += t.deko
			b.Stages[s].price = nice(ps * tm * dk * t.stageWait * TY.Tuning.Scale)
			local need = TY.Tuning.StageItems[s]
			for idx = 1, 2 do
				if need and need[idx] > 0 then
					b.Stages[s].items[f.items[idx]] = need[idx]
				end
			end
			TY.StageById[typ .. "_stage" .. s] = { typ = typ, stage = s }
		end
		TY.Buildings[typ] = b
	end
	TY.TypeSet = {}
	for _, typ in ipairs(TY.Types) do
		TY.TypeSet[typ] = true
	end
	TY.SlotByNumber = {}
	for _, sl in ipairs(TY.Slots) do
		TY.SlotByNumber[sl.slot] = sl
	end
end

---------------------------------------------------------------- Open World: Gebäude, Perks, Passiv-Modus (§5, §7, Meilenstein 6)
-- Feste IDs: Gebäudetypen werkstatt|autohaus|produktion|schrottplatz, Stufen 1..4. Modelle
-- ServerStorage.OWBuildings.<typ>_<stufe> und OWBuildings.baustelle (Weltteam), Anker Plot.OWAnchors.<typ>.
-- werkstatt = das 2.4.0-Grundstück (Stufe = Bühnenzahl d.bays, Kauf nur über den Hallenanbau; hier nur Anzeige + Perk).
-- Balance (docs/BALANCE.md: Werkstatt Lv 10 ≈ 800 Cr/Min, Lv 20 ≈ 1.470, Lv 30 ≈ 2.850, Lv 40 ≈ 5.770; passive
-- Einnahmen zusammen ≤ 25 %): Autohaus Stufe 1 = 25 Cr/Min (3 % auf Level 10), Stufe 4 = 300 Cr/Min (≈ 10 % auf Level 30).
-- Schrott: 1 Credit = 10 Mio. Schrott (MiniConfig.ScrapPerCredit), darum die großen Schrottzahlen. Erträge sammeln sich
-- höchstens PassiveCapHours an (danach steht die Anlage still, bis abgeholt wird). Bauzeit läuft offline weiter (readyAt).
export type OWStage = {
	stage: number, price: number, buildSeconds: number, level: number?,
	yieldPerHour: number?, scrapPerHour: number?, partsPerHour: number?,
	partsEveryHours: number?, partsPerPack: number?, carEveryHours: number?, carModel: string?,
}
export type OWBuilding = { typ: string, name: string, desc: string, unlock: string?, display: boolean?, Stages: { OWStage } }
export type OWPerk = { kind: string, label: string, per: number, cap: number, perBay: boolean? }

GameConfig.OW = {
	Types = { "werkstatt", "autohaus", "produktion", "schrottplatz" },
	MaxStage = 4,
	PassiveCapHours = 12, -- Erträge sammeln sich höchstens 12 Std. an (abholen!)
	CountdownInterval = 1, -- Baustellen-Countdown (SurfaceGui) höchstens 1×/s vom Server beschriftet; der Client zählt lokal (kein Snapshot je Sekunde)
	ReadyToastSeconds = 2, -- Toast-Drossel je Grund (ow_build/ow_collect)
	Buildings = {
		werkstatt = {
			typ = "werkstatt", name = "Werkstatt", display = true,
			desc = "Dein 2.4.0-Grundstück. Die Stufe ist die Zahl deiner Hebebühnen – ausbauen am Hallenanbau auf dem Grundstück.",
			Stages = {}, -- kein zweiter Kaufweg (Stufe = d.bays, Preise in GarageShared.Config)
		},
		autohaus = {
			typ = "autohaus", name = "Autohaus", unlock = "building:autohaus",
			desc = "Dein eigener Verkaufsstand auf dem Grundstück: verkauft Autos, während du unterwegs bist (Credits je Stunde, abholen) und bringt dir Rabatt beim Händler.",
			Stages = {
				{ stage = 1, price = 12000, buildSeconds = 600, yieldPerHour = 1500 },
				{ stage = 2, price = 50000, buildSeconds = 2700, yieldPerHour = 4000 },
				{ stage = 3, price = 180000, buildSeconds = 10800, yieldPerHour = 9000 },
				{ stage = 4, price = 600000, buildSeconds = 28800, yieldPerHour = 18000 },
			},
		},
		schrottplatz = {
			typ = "schrottplatz", name = "Schrottplatz", unlock = "building:schrottplatz",
			desc = "Dein eigener Schrottplatz: sammelt Schrott für die Presse und Altteile, auch wenn du nicht da bist. Dazu ein Bonus auf die Schrottpresse.",
			Stages = {
				{ stage = 1, price = 40000, buildSeconds = 300, scrapPerHour = 2000000000, partsPerHour = 2 },
				{ stage = 2, price = 140000, buildSeconds = 1800, scrapPerHour = 6000000000, partsPerHour = 4 },
				{ stage = 3, price = 400000, buildSeconds = 7200, scrapPerHour = 15000000000, partsPerHour = 8 },
				{ stage = 4, price = 1100000, buildSeconds = 18000, scrapPerHour = 40000000000, partsPerHour = 15 },
			},
		},
		produktion = {
			typ = "produktion", name = "Produktion", unlock = "building:produktion",
			desc = "Deine Automobil-Produktion: alle paar Stunden ein Bauteil-Paket (Altteile), ab Stufe 4 außerdem alle zwei Tage ein Auto-Gutschein für einen Kompaktwagen. Macht deine Tuning-Projekte schneller.",
			Stages = {
				{ stage = 1, price = 150000, buildSeconds = 900, partsEveryHours = 6, partsPerPack = 10 },
				{ stage = 2, price = 500000, buildSeconds = 3600, partsEveryHours = 4, partsPerPack = 15 },
				{ stage = 3, price = 1500000, buildSeconds = 14400, partsEveryHours = 3, partsPerPack = 20 },
				{ stage = 4, price = 4000000, buildSeconds = 36000, partsEveryHours = 2, partsPerPack = 30, carEveryHours = 48, carModel = "komet" },
			},
		},
	},
	-- Perks (§7): Faktor = 1 + min(cap, Stufe × per); werkstatt zählt Bühnen über der ersten (d.bays − 1). Alles ≤ +25 %.
	-- CrossBonus.OWPerk(d, typ) liest genau diese Tabelle (werkstatt -> Auftragswert, autohaus -> Händlerrabatt-Anteil,
	-- schrottplatz -> Presse-Schrott, produktion -> Tuning-Tempo). Stufe = fertig gebaute Stufe (built), nie die Baustelle.
	Perks = {
		werkstatt = { kind = "werkstatt", label = "Auftragswert", per = 0.08, cap = 0.24, perBay = true },
		autohaus = { kind = "autohaus", label = "Händlerrabatt", per = 0.03, cap = 0.12 },
		schrottplatz = { kind = "schrottplatz", label = "Presse-Schrott", per = 0.05, cap = 0.20 },
		produktion = { kind = "produktion", label = "Tuning-Tempo", per = 0.05, cap = 0.20 },
	},
	PerkCap = 0.25, -- harte Obergrenze aller Perks (Vertrag §7)
	-- Passiv-Modus (§5): nur Zuschauen/Handeln, keine Missionen/Story/Auktionen; passive Einnahmen laufen weiter
	PassiveHint = "Du bist im Passiv-Modus: nur zuschauen und handeln. Missionen, Story und Auktionen pausieren – deine Gebäude und Tuning-Projekte verdienen weiter. Umschalten im Tab „Gebäude“ oder in der Lobby.",
}

---------------------------------------------------------------- Story „Vom Kiesplatzhändler zum Mega-Verkäufer“ (§7, Meilenstein 7)
-- Alle Zahlen und Texte der Story, des Kiesplatz-Verkaufs, der Nebenmissionen und der Lieferfahrten (StoryRules liest nur hier).
--
-- Missionen (feste Ids "c<kapitel>_m<n>", Nebenmissionen "s_<name>", Legende "l_<name>"):
--   kind = "stat"   stat = Statistik (MiniRules.STAT_KEYS), target = n   (zählt den Zuwachs seit dem Start; absolute = true: Gesamtwert)
--   kind = "event"  event = Ereignis-Schlüssel (StoryService.OnEvent), target = n, maxTime = s (nur mit data.time ≤ maxTime)
--   kind = "sell"   target = n Verkäufe am Kiesplatz; tier = Mindest-Preisstufe (3 = Bestpreis); special = true: nur Sondermodell-Kunden
--   kind = "build"  typ = OW-Gebäude, stage = Stufe (gelesen aus d.games.ow.buildings[typ].stage)
--   kind = "own"    money = n (Kontostand) | bays = n (Hebebühnen) | cars = { modelIds } (eins davon in der Garage) |
--                   equipmentAll = true (alle Geräte der Werkstatt mindestens Stufe 1)
--   Voraussetzung (Freischaltung): Story.Requires (stat/event -> Unlocks-Schlüssel), build -> building:<typ>, cars -> car:<id>;
--   StoryRules.RequiredLevel(def) muss ≤ Kapitel-Level sein (tests/test_story.lua), sonst sitzt der Spieler in einer Sackgasse.
--   reward = { credits = n, xp = n?, cosmetic = id?, title = string? }; fehlt xp, gilt GameConfig.XP.StoryMission[kapitel]
--   minutes = erwarteter Aufwand (Balance: credits / minutes ≤ Balance.Share × Werkstatt-Cr/Min des Kapitel-Levels)
local Story = {}

Story.Title = "Vom Kiesplatzhändler zum Mega-Verkäufer"

---------------------------------------------------------------- Kapitel (§7: 5 Kapitel à 3 Missionen; Level wie GameConfig.Unlocks "story:<n>")
Story.Chapters = {
	{
		id = 1, title = "Der Kiesplatz", unlockLevel = 1,
		intro = "Neben deiner Werkstatt hast du einen kleinen Kiesplatz am Stadtrand gepachtet: drei alte Autos und ein handgemaltes Schild. "
			.. "Die Kunden kommen schon, jetzt brauchst du nur noch den richtigen Preis. "
			.. "Jeder Verkauf bringt dich deinem Traum vom eigenen Autohaus ein Stück näher.",
		Missions = {
			{ id = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", kind = "sell", target = 3, minutes = 4,
				text = "Geh zum Kiesplatz, sprich mit den Kunden und nenne deinen Preis. Günstig klappt immer, teuer braucht Verhandlungsglück.",
				reward = { credits = 150 } },
			{ id = "c1_m2", title = "Zurück in die Werkstatt", kind = "event", event = "settle", target = 1, minutes = 3,
				text = "Deine Kunden wollen auch reparieren lassen. Nimm in deiner Werkstatt noch einen Auftrag an und rechne ihn am Empfang ab.",
				reward = { credits = 120 } },
			-- Startgeld 800 + Tutorial 500 + c1_m1/c1_m2 ≈ 1.700 Cr: 2.500 verlangt echtes Spiel (≈ 4 Min. Werkstatt auf Level 1–3)
			{ id = "c1_m3", title = "Die ersten 2.500 Credits", kind = "own", money = 2500, target = 2500, minutes = 4,
				text = "Bring deinen Kontostand auf 2.500 Credits – mit Verkäufen am Kiesplatz oder Aufträgen in der Werkstatt.",
				reward = { credits = 200 } },
		},
	},
	{
		id = 2, title = "Die erste Werkstatt", unlockLevel = 5,
		intro = "Mit den ersten Credits wird deine Werkstatt zum richtigen Betrieb. "
			.. "Deine Kunden wollen nicht nur kaufen, sondern auch reparieren lassen. "
			.. "Zeig, was du kannst – an der Hebebühne und im Mechaniker-Quiz.",
		Missions = {
			{ id = "c2_m1", title = "Fünf Aufträge abrechnen", kind = "stat", stat = "jobsDone", target = 5, minutes = 10,
				text = "Fünf Kundenautos reparieren und am Empfang abrechnen. Jeder Auftrag bringt Credits, XP und Ruf.",
				reward = { credits = 800 } },
			{ id = "c2_m2", title = "Hebebühne Nummer zwei", kind = "own", bays = 2, target = 2, minutes = 5,
				text = "Kauf im Hallenanbau deiner Werkstatt eine zweite Hebebühne. Zwei Aufträge gleichzeitig – doppelt so schnell.",
				reward = { credits = 500 } },
			{ id = "c2_m3", title = "Mechaniker-Quiz bestehen", kind = "stat", stat = "quizCorrect", target = 10, minutes = 3,
				text = "Beantworte im Mechaniker-Quiz (Stadt) zehn Fragen richtig. Diagnosepunkte machen deine Reparaturen schneller.",
				reward = { credits = 400 } },
		},
	},
	{
		id = 3, title = "Das Autohaus", unlockLevel = 15,
		intro = "Die ganze Stadt redet über dich! Zeit für ein eigenes Autohaus auf deinem Grundstück. "
			.. "Kauf dein erstes Auto beim Händler, fahr es auf der Teststrecke ein und mach dir im Auktionshaus einen Namen.",
		Missions = {
			{ id = "c3_m1", title = "Das eigene Autohaus", kind = "build", typ = "autohaus", stage = 1, target = 1, minutes = 10,
				text = "Bau auf deinem Grundstück das Gebäude „Autohaus“ (Tab „Gebäude“). Es bringt passive Verkaufserlöse und Händler-Rabatt.",
				reward = { credits = 2500 } },
			{ id = "c3_m2", title = "Der erste Neuwagen", kind = "event", event = "car_bought", target = 1, minutes = 8,
				text = "Kauf beim Händler in der Stadt ein Auto für deine Garage. Mit Rabatt aus deinem Autohaus wird's günstiger.",
				reward = { credits = 2000 } },
			{ id = "c3_m3", title = "Ab auf die Teststrecke", kind = "event", event = "track_finish", target = 1, minutes = 4,
				text = "Fahr mit deinem eigenen Auto ein Zeitfahren auf der Teststrecke bis ins Ziel. Die Zeit ist egal – Hauptsache ankommen!",
				reward = { credits = 400 } },
			{ id = "c3_m4", title = "Unter dem Hammer", kind = "event", events = { "auction_won", "auction_consigned" }, target = 1, minutes = 10,
				text = "Gewinne eine NPC-Auktion im Auktionshaus – oder (ab Level 20) gib ein eigenes Auto in die Auktion.",
				reward = { credits = 3000 } },
		},
	},
	{
		id = 4, title = "Die Produktion", unlockLevel = 30,
		intro = "Große Verkäufer bauen ihre Autos selbst. Mit Schrottplatz und Produktion wird aus Altteilen Neues – "
			.. "und am Kiesplatz warten jetzt Kunden mit besonderen Wünschen und dickem Geldbeutel.",
		Missions = {
			{ id = "c4_m1", title = "Der eigene Schrottplatz", kind = "build", typ = "schrottplatz", stage = 1, target = 1, minutes = 10,
				text = "Bau das Gebäude „Schrottplatz“ auf deinem Grundstück. Es liefert passiv Schrott und Altteile.",
				reward = { credits = 6000 } },
			{ id = "c4_m2", title = "Die Produktion läuft an", kind = "build", typ = "produktion", stage = 1, target = 1, minutes = 15,
				text = "Bau die „Automobil-Produktion“ auf deinem Grundstück. Sie produziert Bauteil-Pakete – und später ganze Autos.",
				reward = { credits = 9000 } },
			{ id = "c4_m3", title = "Drei Sondermodelle verkaufen", kind = "sell", target = 3, special = true, minutes = 6,
				text = "Am Kiesplatz fragen jetzt Sammler nach Sondermodellen. Verkauf drei davon – die Preisstufen gelten wie immer.",
				reward = { credits = 5000 } },
		},
	},
	{
		id = 5, title = "Der Mega-Verkäufer", unlockLevel = 50,
		intro = "Der letzte Schritt: Deine Produktion läuft auf Hochtouren, deine Kunden zahlen Bestpreise, "
			.. "und in deiner Garage steht ein Traumwagen. Dann kennt die ganze Stadt deinen Namen – Mega-Verkäufer!",
		Missions = {
			{ id = "c5_m1", title = "Produktion auf Stufe 4", kind = "build", typ = "produktion", stage = 4, target = 4, minutes = 30,
				text = "Bau deine Produktion bis Stufe 4 aus. Ab dann rollt alle zwei Tage ein Auto-Gutschein für einen Kompaktwagen vom Band.",
				reward = { credits = 20000 } },
			{ id = "c5_m2", title = "Zehn Verkäufe zum Bestpreis", kind = "sell", target = 10, tier = 3, minutes = 15,
				text = "Verkauf am Kiesplatz zehn Autos zur Preisstufe „teuer“. Nur erfolgreiche Verhandlungen zählen.",
				reward = { credits = 15000 } },
			{ id = "c5_m3", title = "Der Traumwagen", kind = "own", cars = { "vektor_gold", "vektor_gtx", "aureon", "elys", "aureon_nero", "elys_proto" }, target = 1, minutes = 30,
				text = "Besitze einen Traumwagen: das Vektor RS Goldstück (Auktion, ab Level 50), einen Vektor GTX (Händler, ab Level 58) "
					.. "oder später einen Vektor Aureon V12 (ab Level 72) bzw. Nord Elys E9 (ab Level 90). Dann bist du der Mega-Verkäufer!",
				reward = { credits = 25000, cosmetic = "wrap_mega", title = "Mega-Verkäufer" } },
		},
	},
}

---------------------------------------------------------------- Kiesplatz-Verkauf (story_sell {offer, price}; price = Preisstufe 1..3)
-- Der Spieler kauft den Gebrauchtwagen gedanklich aus dem Erlös: gutgeschrieben wird nur der Reingewinn (profit) je Stufe,
-- skaliert mit dem Level (×(1 + LevelFactor × (Level − 1)), Deckel LevelFactorCap) und bei Sondermodell-Kunden ×SpecialMultiplier.
-- Stufe 1 klappt immer, Stufe 2 meistens, Stufe 3 verhandelt der Kunde: Erfolg, wenn der beim Angebot festgelegte
-- Zufallswurf (Seed, Server) unter chance liegt. Kein Wurf je Klick – wer denselben Kunden zweimal fragt, bekommt dieselbe Antwort.
Story.Sale = {
	FirstOfferDelay = 2, -- Sekunden nach dem Beitritt bis zum ersten Kunden
	OfferInterval = 45, -- Sekunden bis zum nächsten Kunden nach einem Verkauf
	FailInterval = 20, -- Sekunden bis zum nächsten Kunden nach einer geplatzten Verhandlung
	Patience = 180, -- Sekunden, die ein Kunde wartet, bevor er weiterzieht
	Range = 45, -- Studs: so nah muss die Figur an City.Stations.kiesplatz sein (ohne Station keine Prüfung)
	LevelFactor = 0.04,
	LevelFactorCap = 3, -- höchstens ×3 (ab Level 51)
	SpecialMultiplier = 3,
	SpecialChapter = 4, -- ab diesem Kapitel kommen Sondermodell-Kunden (jeder dritte Kunde)
	SpecialEvery = 3,
	Xp = { 8, 12, 20 }, -- XP je gelungenem Verkauf nach Preisstufe
	Tiers = {
		{ tier = 1, label = "günstig", profit = 40, chance = 1, hint = "Sicherer Verkauf, kleiner Gewinn." },
		{ tier = 2, label = "fair", profit = 75, chance = 0.85, hint = "Klappt meistens." },
		{ tier = 3, label = "teuer", profit = 130, chance = 0.5, hint = "Der Kunde feilscht – mit etwas Glück ein dicker Gewinn." },
	},
	-- Fiktiver Verkaufspreis je Karosserie (nur Anzeige: Preis = Basis + Gewinn); Gewinn ist das, was wirklich ankommt
	BasePrice = { compact = 3200, sedan = 5800, sport = 14000, super = 60000, electric = 42000 },
	Bodies = { compact = "Kompaktwagen", sedan = "Limousine", sport = "Sportwagen", super = "Supersportwagen", electric = "Elektroauto" },
	Customers = {
		{ name = "Lena", wants = "compact", line = "Ich brauche was Kleines für die Stadt. Was soll der kosten?" },
		{ name = "Familie Berg", wants = "sedan", line = "Wir sind zu fünft – da muss schon eine Limousine her!" },
		{ name = "Jonas", wants = "sport", line = "Hauptsache, er ist schnell. Nenn mir deinen Preis!" },
		{ name = "Oma Hilde", wants = "compact", line = "Zum Einkaufen und zum Enkel fahren – mehr brauch ich nicht." },
		{ name = "Mia", wants = "electric", line = "Ich will was mit Stecker. Was kostet mich das?" },
		{ name = "Herr Kowalski", wants = "sedan", line = "Für die Arbeit, bequem und zuverlässig. Und der Preis?" },
		{ name = "Tarek", wants = "sport", line = "Ich hab lange gespart. Mach mir ein faires Angebot!" },
		{ name = "Frau Özdemir", wants = "compact", line = "Mein erstes eigenes Auto! Was muss ich hinlegen?" },
		{ name = "Ben und Paul", wants = "sedan", line = "Wir teilen uns das Auto. Was rufst du auf?" },
		{ name = "Sofia", wants = "electric", line = "Leise, sauber, schick. Was verlangst du dafür?" },
		{ name = "Herr Vogt", wants = "super", line = "Ich sammle Besonderes. Geld spielt keine Rolle – fast.", special = true },
		{ name = "Lady Amara", wants = "sport", line = "Etwas Seltenes für meine Garage, bitte. Ihr Preis?", special = true },
		{ name = "Dr. Quint", wants = "electric", line = "Ein Prototyp? Das wäre mein Traum. Was kostet er?", special = true },
	},
	Texts = {
		sold = { "%s nickt: „Abgemacht!“ Du verdienst %s.", "„Super Preis!“ freut sich %s. Gewinn: %s.", "%s schlägt ein. Dein Gewinn: %s." },
		failed = { "%s schüttelt den Kopf: „Das ist mir zu teuer.“ Der nächste Kunde kommt gleich.", "„Nee, so viel nicht“, sagt %s und geht weiter." },
		gone = "%s hatte keine Lust mehr zu warten. Der nächste Kunde kommt gleich.",
		noOffer = "Gerade ist kein Kunde da. Der nächste kommt in Kürze.",
		wrongOffer = "Dieser Kunde ist schon weg. Schau dir den aktuellen an.",
		badTier = "Wähle eine Preisstufe: günstig, fair oder teuer.",
		notHere = "Zum Verkaufen geh an den Kiesplatz am Stadtrand.",
		notOpenWorld = "Der Kiesplatz liegt in der Open World.",
	},
}

---------------------------------------------------------------- Nebenmissionen (§7: täglich 3 aus dem Pool; dazu der Strang „Werkstatt-Legende“)
Story.Side = {
	Daily = 3, -- Nebenmissionen je UTC-Tag (deterministisch wie GoalRules.DailyGoals)
	DailyLimit = 3, -- Tageslimit abgeholter Nebenmissionen
	LevelScale = 0.03, -- Credits × (1 + LevelScale × (Level − 1)), Deckel LevelScaleCap
	LevelScaleCap = 3,
	TimeTrialTarget = 75, -- Sekunden: Zeitfahren unter dieser Zeit
	Delivery = {
		Routes = 3, -- City.Missions.Delivery_1..3 (Start/Ziel-Teile, Attribut Role = "start" | "end")
		TimeLimit = 240, -- Sekunden vom Start bis zum Ziel
		Slack = 6, -- Studs Zugabe auf die halbe Teilgröße (Berührung des Fahrzeugrumpfs)
		MaxStep = 120, -- Studs: längere Sprünge des Rumpfs zwischen zwei Ticks (Schnellreise, Spawn) gelten nicht als Durchfahrt
		Texts = {
			started = "Lieferung %d gestartet! Fahr mit deinem Auto zum Ziel – du hast %d Sekunden.",
			done = "Lieferung %d abgeliefert! Das war in %d Sekunden.",
			expired = "Die Lieferung hat zu lange gedauert. Fahr noch einmal zum Start.",
		},
	},
	-- Tagesauswahl (StoryRules.DailyIds(day, level)): nur Einträge, deren Freischaltung (unlock bzw. Story.Requires) das Level
	-- des Spielers erreicht hat; needsCar = eigenes Auto nötig (Hinweis im Text). s_jobs geht immer, also gibt es jeden Tag
	-- mindestens eine machbare Nebenmission. Die "action:<aktion>"-Ereignisse feuert MiniService nur bei gelungener Aktion.
	Pool = {
		{ id = "s_delivery", title = "Lieferung", kind = "event", event = "delivery", target = 1, credits = 150, unlock = "feature:dealer", needsCar = true,
			text = "Fahr mit deinem eigenen Auto zum Lieferstart in der Stadt (Schild „Lieferung“) und bring es rechtzeitig zum Ziel." },
		{ id = "s_timetrial", title = "Zeitfahren unter Zielzeit", kind = "event", event = "track_finish", maxTime = 75, target = 1, credits = 150, unlock = "feature:track", needsCar = true,
			text = "Fahr mit deinem eigenen Auto auf der Teststrecke ein Zeitfahren unter 75 Sekunden." },
		{ id = "s_arcade", title = "Dreimal Spielhalle", kind = "event", event = "arcade_round", target = 3, credits = 120, unlock = "feature:arcade",
			text = "Spiel in der Spielhalle drei Runden an den Automaten – bis zum Ende, abgebrochene Runden zählen nicht." },
		{ id = "s_dismantle", title = "Fünf Fahrzeuge zerlegen", kind = "stat", stat = "dismantled", target = 5, credits = 150, unlock = "feature:scrapyard",
			text = "Zerlege auf dem Schrottplatz fünf Fahrzeuge in Altteile." },
		{ id = "s_auction", title = "Zweimal mitbieten", kind = "event", event = "action:mini_auction_bid", target = 2, credits = 120, unlock = "feature:auction",
			text = "Gib im Auktionshaus zwei gültige Gebote ab – gewinnen musst du nicht." },
		{ id = "s_wash", title = "Autowäsche", kind = "event", event = "action:mini_carwash", target = 1, credits = 80, unlock = "feature:carwash", needsCar = true,
			text = "Fahr mit deinem eigenen Auto durch die Waschstraße." },
		{ id = "s_press", title = "Zehn Schrott-Tauschgeschäfte", kind = "event", event = "action:mini_press_exchange", target = 10, credits = 120, unlock = "feature:press",
			text = "Tausche an der Schrottpresse zehnmal Schrott beim Händler." },
		{ id = "s_tune", title = "Ein Auto tunen", kind = "event", event = "action:mini_car_tune", target = 1, credits = 120, unlock = "feature:dealer", needsCar = true,
			text = "Verbessere in deiner Garage ein Teil an einem deiner eigenen Autos." },
		{ id = "s_quiz", title = "Fünf Quizfragen", kind = "stat", stat = "quizCorrect", target = 5, credits = 100, unlock = "feature:quiz",
			text = "Beantworte im Mechaniker-Quiz fünf Fragen richtig." },
		{ id = "s_parking", title = "Drei Parkrätsel", kind = "stat", stat = "parkingSolved", target = 3, credits = 100, unlock = "feature:parking",
			text = "Löse drei Rätsel im Parkplatz-Chaos." },
		{ id = "s_jobs", title = "Drei Aufträge", kind = "stat", stat = "jobsDone", target = 3, credits = 150,
			text = "Rechne in deiner Werkstatt drei Aufträge ab." },
	},
	-- Zweiter Strang „Werkstatt-Legende“: dauerhaft, einmal abholbar, Fortschritt aus dem Profil (nicht täglich)
	Legend = {
		{ id = "l_jobs100", title = "Werkstatt-Legende: 100 Aufträge", kind = "stat", stat = "jobsDone", absolute = true, target = 100, credits = 5000, xp = 400,
			text = "Rechne insgesamt 100 Aufträge in deiner Werkstatt ab." },
		{ id = "l_equipment", title = "Werkstatt-Legende: Alle Geräte", kind = "own", equipmentAll = true, target = 8, credits = 8000, xp = 600,
			text = "Besitze jedes Gerät der Werkstatt mindestens einmal." },
		{ id = "l_bays4", title = "Werkstatt-Legende: Vier Bühnen", kind = "own", bays = 4, target = 4, credits = 6000, xp = 500,
			text = "Bau deine Werkstatt auf vier Hebebühnen aus." },
	},
}

---------------------------------------------------------------- Voraussetzungen (Freischaltung je Statistik/Ereignis; StoryRules.RequiredLevel)
-- Fehlt ein Eintrag, braucht die Mission keine Freischaltung (z. B. settle/jobsDone). Alternativen (events = { … }) zählen mit
-- der niedrigsten Voraussetzung; eigene Autos (own cars) mit dem günstigsten Modell; Hebebühnen mit C.BayLevels.
Story.Requires = {
	stat = { quizCorrect = "feature:quiz", parkingSolved = "feature:parking", dismantled = "feature:scrapyard",
		tuningStarted = "feature:tuning", tuningCollected = "feature:tuning", pressed = "feature:press", clicks = "feature:press" },
	event = { track_finish = "feature:track", car_bought = "feature:dealer", auction_won = "feature:auction", auction_consigned = "auction:player",
		arcade_round = "feature:arcade", delivery = "feature:dealer",
		["action:mini_auction_bid"] = "feature:auction", ["action:mini_carwash"] = "feature:carwash",
		["action:mini_press_exchange"] = "feature:press", ["action:mini_car_tune"] = "feature:dealer" },
}

---------------------------------------------------------------- Co-op (§7)
-- Geteilte Missionsarten: Fortschritt eines Party-Mitglieds zählt für alle Mitglieder mit derselben aktiven Mission.
-- Bedingungen am eigenen Profil (own, build) teilt niemand. Nebenmissionen sind persönlich.
Story.Coop = { SharedKinds = { stat = true, event = true, sell = true }, Text = "Party: %s hat „%s“ weitergebracht (%d/%d)." }

---------------------------------------------------------------- Balance (§7: Missions-Belohnung ≤ 40 % der Werkstatt-Einnahme/Minute)
-- Werkstatt-Credits je Minute nach docs/BALANCE.md (Zeile „Werkstatt (2.4.0-Aufträge)“), dazwischen linear, darüber fortgesetzt
Story.Balance = { Share = 0.4, WorkshopPerMinute = { { 1, 214 }, { 5, 531 }, { 10, 803 }, { 20, 1468 }, { 30, 2850 }, { 40, 5765 } } }

---------------------------------------------------------------- Texte
Story.Texts = {
	unknown = "Diese Mission gibt es nicht.",
	finished = "Du hast die ganze Story geschafft – Mega-Verkäufer!",
	locked = "Kapitel %d „%s“ gibt es ab Level %d. Bis dahin: Aufträge und Nebenmissionen bringen XP!",
	notCurrent = "Erst kommt „%s“ dran – die Story geht der Reihe nach.",
	alreadyActive = "Du bist schon bei „%s“. Erledige sie zuerst.",
	alreadyDone = "Die hast du schon geschafft.",
	notActive = "Starte die Mission zuerst im Tab „Story“.",
	notDone = "Noch nicht geschafft: %d von %d.",
	started = "Mission gestartet: „%s“. %s",
	claimed = "Mission geschafft: „%s“ – +%s und %d XP!",
	chapterDone = "Kapitel %d abgeschlossen: „%s“! +%d XP. Weiter geht's mit Kapitel %d ab Level %d.",
	storyDone = "Du bist jetzt offiziell Mega-Verkäufer! Die ganze Stadt kennt deinen Namen.",
	passive = "Im Passiv-Modus ruht die Story. Schalte ihn in den Einstellungen (Lobby) aus, wenn du weiterspielen willst.",
	sideUnknown = "Diese Nebenmission gibt es heute nicht.",
	sideNotDone = "Noch nicht geschafft: %d von %d.",
	sideClaimed = "Nebenmission geschafft: „%s“ – +%s und %d XP!",
	sideAlready = "Schon abgeholt.",
	sideLimit = "Für heute hast du alle Nebenmissionen abgeholt. Morgen gibt es neue!",
	coop = "Party: %s hat „%s“ weitergebracht (%d/%d).",
}
GameConfig.Story = Story

---------------------------------------------------------------- Spätere Meilensteine (leer, nichts liest daraus; Tycoon/OW/Story siehe oben)
GameConfig.Shop = {} -- wird in Meilenstein 8 gefüllt (Produkte, DLC-Autos, Kosmetik, Game Passes)

---------------------------------------------------------------- Nachschlagetabellen
GameConfig.ModeSet = {}
for _, mode in ipairs(GameConfig.Modes) do
	GameConfig.ModeSet[mode] = true
end
GameConfig.PlaceKindSet = {}
for _, kind in ipairs(GameConfig.PlaceKinds) do
	GameConfig.PlaceKindSet[kind] = true
end

-- Unlocks bleiben nach Level sortiert (bei gleichem Level in Tabellenreihenfolge); order = Platz in der Liste
for i, u in ipairs(GameConfig.Unlocks) do
	u.order = i
end
table.sort(GameConfig.Unlocks, function(a, b)
	if a.level ~= b.level then
		return a.level < b.level
	end
	return a.order < b.order
end)
GameConfig.UnlockByKey = {} -- key -> Eintrag
GameConfig.UnlocksByKind = {} -- kind -> Liste (sortiert)
GameConfig.UnlockByTab = {} -- tab -> Eintrag der Art feature (Stationen/Tabs mit Level-Voraussetzung)
GameConfig.UnlockLevels = {} -- aufsteigende Liste der Level mit mindestens einer Freischaltung
for i, u in ipairs(GameConfig.Unlocks) do
	u.order = i
	GameConfig.UnlockByKey[u.key] = u
	GameConfig.UnlocksByKind[u.kind] = GameConfig.UnlocksByKind[u.kind] or {}
	table.insert(GameConfig.UnlocksByKind[u.kind], u)
	if u.kind == "feature" and u.tab and not GameConfig.UnlockByTab[u.tab] then
		GameConfig.UnlockByTab[u.tab] = u
	end
	local last = GameConfig.UnlockLevels[#GameConfig.UnlockLevels]
	if last ~= u.level then
		table.insert(GameConfig.UnlockLevels, u.level)
	end
end

GameConfig.OW.TypeSet = {}
GameConfig.OW.BuildingList = {} -- in Reihenfolge von Types
for _, typ in ipairs(GameConfig.OW.Types) do
	GameConfig.OW.TypeSet[typ] = true
	local b = GameConfig.OW.Buildings[typ]
	if b then
		b.typ = typ
		table.insert(GameConfig.OW.BuildingList, b)
		for i, st in ipairs(b.Stages) do
			st.stage = i
			if st.level == nil then
				local e = b.unlock and GameConfig.UnlockByKey[b.unlock] or nil
				st.level = e and e.level or 1
			end
		end
	end
end

GameConfig.HintById = {}
GameConfig.HintsByWhen = {} -- Auslöser -> Liste
for _, h in ipairs(GameConfig.Hints) do
	GameConfig.HintById[h.id] = h
	GameConfig.HintsByWhen[h.when] = GameConfig.HintsByWhen[h.when] or {}
	table.insert(GameConfig.HintsByWhen[h.when], h)
end

GameConfig.TutorialStepById = {}
GameConfig.TutorialStepIndex = {} -- id -> Nummer (1-basiert)
for i, s in ipairs(GameConfig.Tutorial.Steps) do
	GameConfig.TutorialStepById[s.id] = s
	GameConfig.TutorialStepIndex[s.id] = i
end
GameConfig.Tutorial.Count = #GameConfig.Tutorial.Steps

return GameConfig
