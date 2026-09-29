-- GameConfig: die eine Stelle für alle Zahlen und Tabellen der Ausbaustufe 4 (docs/PHASE4_CONTRACT.md §3):
-- Places, Zonen, Freischaltungen, Prestige, Party, Tutorial, Beginner-Hinweise und die XP-Regler.
-- Tycoon, Open World, Story und Shop sind hier als leere Tabellen vorbereitet und werden in den späteren
-- Meilensteinen gefüllt. 2.4.0-Zahlen bleiben in GarageShared.Config, Minispiel-Zahlen in MiniConfig,
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
	entry(5, "story:2", "story", "Kapitel 2: Die erste Werkstatt", "Aufträge abrechnen, Hebebühne 2 kaufen, Zeitfahren fahren.", "story"),
	entry(6, "feature:tuning", "feature", "Tuning-Projekte", "Projekte laufen weiter, auch wenn du nicht da bist – später abholen.", "tuning"),
	entry(8, "feature:track", "feature", "Teststrecke", "Zeitfahren mit Checkpoints; nur neue Bestzeiten bringen Credits.", "track"),
	entry(8, "feature:carwash", "feature", "Waschstraße", "Lass dein Auto glänzen.", "carwash"),
	car(8, "komet_s2", "Komet S2"),
	entry(10, "feature:arcade", "feature", "Spielhalle", "Acht Automaten mit Geschicklichkeitsspielen, Credits nur nach Leistung.", "arcade"),
	entry(10, "building:autohaus", "building", "Gebäude: Autohaus", "Ein eigenes Autohaus auf deinem Grundstück: passive Verkaufserlöse und Händlerrabatt.", "buildings"),
	car(10, "komet_rally", "Komet C1 Rallye", true),
	entry(12, "feature:auction", "feature", "Auktionshaus", "Biete bei NPC-Auktionen auf seltene Sondermodelle.", "auction"),
	car(14, "nord", "Nord R4"),
	entry(15, "story:3", "story", "Kapitel 3: Das Autohaus", "Autohaus bauen, ein Auto kaufen, eine Auktion gewinnen oder einliefern.", "story"),
	entry(18, "building:schrottplatz", "building", "Gebäude: Schrottplatz", "Ein eigener Schrottplatz: passiver Schrott und Altteile.", "buildings"),
	car(18, "nord_classic", "Nord R4 Classic", true),
	entry(20, "auction:player", "feature", "Spieler-Auktionen", "Gib eigene Autos in die Auktion und biete auf Autos anderer Spieler.", "auction"),
	car(22, "komet_urban", "Komet Urban"),
	entry(30, "story:4", "story", "Kapitel 4: Die Produktion", "Schrottplatz und Produktion bauen, Sondermodelle verkaufen.", "story"),
	car(32, "atlas", "Nord Atlas Tourer"),
	entry(35, "building:produktion", "building", "Gebäude: Produktion", "Deine Automobil-Produktion: Bauteil-Pakete, ab Stufe 4 ein Auto-Gutschein.", "buildings"),
	car(45, "vektor", "Vektor RS"),
	entry(50, "story:5", "story", "Kapitel 5: Der Mega-Verkäufer", "Produktion Stufe 4, zehn Bestpreis-Verkäufe, ein Supersportwagen.", "story"),
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
		{ id = "goals", text = "Sieh dir an der Infotafel deine Tagesziele an. Viel Spaß in der Werkstattmeile!", target = "goals", zone = "city", event = "tab:goals" },
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

---------------------------------------------------------------- Spätere Meilensteine (leer, nichts liest daraus)
GameConfig.Tycoon = {} -- wird in Meilenstein 4 gefüllt (Slots, Gebäudetypen, Stufen, Upgrades, Items, Handel, Rebirth, Bonus-Tabelle)
GameConfig.OW = {} -- wird in Meilenstein 6 gefüllt (Gebäude, Bauzeiten, Preise, Perks, Passiv-Modus)
GameConfig.Story = {} -- wird in Meilenstein 7 gefüllt (Kapitel, Missionen, Nebenmissionen, Belohnungen)
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
