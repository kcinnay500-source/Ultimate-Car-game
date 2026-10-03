-- GameConfig: die eine Stelle für alle Zahlen und Tabellen der Ausbaustufe 4 (docs/PHASE4_CONTRACT.md §3):
-- Places, Zonen, Freischaltungen, Prestige, Party, Tutorial, Beginner-Hinweise und die XP-Regler.
-- Tycoon (Meilenstein 4), Open World (Meilenstein 6), Story (Meilenstein 7) und Shop (Meilenstein 8) sind gefüllt. 2.4.0-Zahlen bleiben in GarageShared.Config, Minispiel-Zahlen in MiniConfig,
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
export type TutorialStep = {
	id: string, text: string, target: string?, zone: string?, event: string,
	at: string?, openTab: string?, passiveSkip: boolean?,
}
export type Hint = { id: string, text: string, when: string }

---------------------------------------------------------------- Places und Modi (§1)
-- Place-IDs: Platzhalter 0 = nichts veröffentlicht. 0 (oder Studio, oder Ziel im selben Place) -> Simulation.
GameConfig.Places = { lobby = 0, openworld = 0, tycoon = 0 }
GameConfig.PlaceKinds = { "all", "lobby", "openworld", "tycoon" } -- Attribut PlaceKind an GarageShared
GameConfig.Modes = { "lobby", "openworld", "tycoon" } -- p.mode, d.games.meta.lastMode, Snapshot mode
GameConfig.DefaultMode = "lobby" -- allererster Beitritt im all-Place
GameConfig.SimulationNotice = "Studio-Simulation: Ortswechsel ohne Teleport"
-- TeleportData (nur Strings/Zahlen/Booleans, geprüft): erlaubte Schlüssel und Längen
-- leader (B-016): UserId des Party-Leiters beim Gruppen-Teleport – wirkt nur innerhalb der Party mit demselben Code
GameConfig.TeleportDataKeys = { mode = "string", single = "boolean", party = "string", leader = "number" }
GameConfig.TeleportDataMaxLength = 32
-- Profil-Sperre beim Laden (Profiles.Load): nach einem Ortswechsel gibt der alte Server die Sperre erst beim
-- Verlassen frei – so oft (je ProfileLockRetryWait Sekunden) erneut versuchen, bevor die Sitzung nur temporär läuft
GameConfig.ProfileLockRetries = 12
GameConfig.ProfileLockRetryWait = 1

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
	entry(1, "mode:openworld", "mode", "Open World", "Die Spielermeile: deine Werkstatt, die Stadt und alle Minispiele.", "lobby"),
	entry(1, "mode:tycoon", "mode", "Tycoon", "Eine Tycoon-Runde mit Bargeld: bau dein Gebäude bis Stufe 5 aus.", "lobby"),
	entry(1, "story:1", "story", "Kapitel 1: Dein Start", "Deine erste Story – sie beginnt sofort mit deinem Startweg.", "story"),
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
	entry(10, "building:autohaus", "building", "Gebäude: Verkaufshaus", "Ein eigenes Verkaufshaus auf deinem Grundstück: passive Verkaufserlöse und Händlerrabatt.", "buildings"),
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
	entry(30, "building:produktion", "building", "Gebäude: Herstellung", "Deine Herstellung (Automobil-Produktion): Bauteil-Pakete, ab Stufe 4 ein Auto-Gutschein.", "buildings"), -- wie Kapitel 4 (c4_m2 baut sie)
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
	LeaderWaitSeconds = 120, -- B-016: so lange nach der Ankunft des Ersten kann der ursprüngliche Leiter noch übernehmen
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
--   "job:accepted"    ein Auftrag liegt in d.jobs (Phase diagnose, approval oder später)
--   "job:repair"      ein Auftrag hat Diagnose und Freigabe hinter sich (Phase repair, working, verify oder invoice);
--                     beim Fahrzeug-Check mit Fehlern im Fehlerspeicher erst nach dem Kundenanruf mit dem Handy (approval)
--   "job:invoice"     ein Auftrag ist fertig repariert und geprüft (Phase invoice)
--   "settled"         Mini.OnSettled (Abrechnung)
--   "action:<name>"   eine Mini-Aktion war erfolgreich (z. B. mini_travel)
-- target = Stationsschlüssel für den Pfeil/Marker im Client (zone plot: Plot.Stations.<key>, zone city: City.Stations.<key>).
-- Startwahl (GameConfig.Start, meta.startPath): Das Tutorial hat einen gemeinsamen Anfang (Intro: laufen, Menü M),
-- einen Mittelteil je Startweg (Paths[typ]) und ein gemeinsames Ende (End: Stadtplan, Kiesplatz). Ein Schritt im
-- Mittelteil trägt at = "start" (Standard: gleich nach dem Intro), "city" (nach dem Stadtplan-Schritt, vor dem Kiesplatz)
-- oder "end" (nach dem Kiesplatz). ByPath[typ] ist die fertige Liste je Weg; Steps = ByPath.werkstatt (der klassische
-- 2.4.0-Start, 11 Schritte, unverändert). Ohne gewählten Weg (startPath = "") gilt werkstatt.
-- openTab = Tab, dessen Öffnen den Lese-Schritt erledigt (TutorialUI: wie „menu“, sobald das Panel auf diesem Tab steht);
-- passiveSkip = Schritt, den der Passiv-Modus unmöglich macht (Kiesplatz-Verkauf): er gilt im Passiv-Modus als erledigt.
local TUTORIAL_STEPS: { [string]: TutorialStep } = {
	-- 3.x: die Story läuft ab der Startwahl (Karte „Deine Mission“ von MissionClient); das Tutorial erklärt die Bedienung
	move = { id = "move", text = "Willkommen in der Spielermeile! Deine Story hat schon begonnen: Die Karte „Deine Mission“ zeigt dir immer, was zu tun ist und wohin du musst. Lauf jetzt ein paar Schritte – mit WASD oder dem Joystick.", target = nil, zone = nil, event = "next" },
	menu = { id = "menu", text = "Öffne das Menü mit der Taste M oder dem Knopf „Minispiele“. Dort findest du alles Wichtige.", target = nil, zone = nil, event = "next" },
	-- werkstatt: die 2.4.0-Aufträge
	reception = { id = "reception", text = "Geh zum Empfang deiner Werkstatt und drück E.", target = "workshop", zone = "plot", event = "station:workshop" },
	accept = { id = "accept", text = "Nimm am Empfang einen Auftrag an – am besten einen „Ölwechsel“, das ist auch deine erste Story-Mission. Ein Kunde bringt dir sein Auto.", target = "workshop", zone = "plot", event = "job:accepted" },
	-- 3.0: OBD-Tester liest den Fehlerspeicher; Fehler gefunden -> Kunde per Handy (Taste P) fragen; Werkzeug kommt automatisch
	obd = { id = "obd", text = "Geh zum Auto und drück E am OBD-Anschluss: Der OBD-Tester liest den Fehlerspeicher. Findet er Fehler, ruf den Kunden mit dem Handy an (Taste P) und frag, ob du reparieren darfst.", target = nil, zone = nil, event = "job:repair" },
	repair = { id = "repair", text = "Repariere das Auto: Geh zum leuchtenden Punkt und drück E. Werkzeug, Hebebühne und Motorhaube macht dein Mechaniker selbst. Zum Schluss die Endkontrolle mit E am OBD-Anschluss. Mit Taste 1 hast du die Hände frei.", target = nil, zone = nil, event = "job:invoice" },
	settle = { id = "settle", text = "Rechne den Auftrag am Empfang ab – die Credits gehören dir!", target = "workshop", zone = "plot", event = "settled" },
	map = { id = "map", text = "Drück M (oder den Knopf „Minispiele“) und öffne den Tab „Stadtplan“ – reise damit in die Stadt.", target = nil, zone = nil, event = "action:mini_travel" },
	dealer = { id = "dealer", text = "Schau im Autohaus vorbei und drück dort E. Kaufen kannst du ab Level 3 – ansehen darfst du jetzt schon.", target = "dealer", zone = "city", event = "tab:dealer", at = "city" },
	goals = { id = "goals", text = "Sieh dir an der Infotafel deine Tagesziele an – jeden Tag gibt es neue.", target = "goals", zone = "city", event = "tab:goals", at = "city" },
	-- Meilenstein 7: gemeinsamer End-Schritt am Kiesplatz (Station City.Stations.kiesplatz, Tab story). 3.x: die Story
	-- beginnt schon bei der Startwahl – der Kiesplatz ist hier ein Extra-Verdienst für jeden Weg (beim Verkaufshaus
	-- folgt noch ah_sell, daher kein „Zum Schluss“; die Endkarte sagt „Viel Spaß!“)
	kiesplatz = { id = "kiesplatz", text = "Noch ein Tipp: Am Kiesplatz am Stadtrand warten Kunden auf Gebrauchtwagen – ein Extra-Verdienst für jeden Startweg. Reise mit dem Stadtplan zum „Kiesplatz (Gebrauchtwagen)“ und drück dort E.", target = "kiesplatz", zone = "city", event = "tab:story" },
	-- autohaus (Verkaufshaus): das geschenkte Verkaufshaus (OWRules.GrantStart), Händler, erster Verkauf am Kiesplatz
	ah_buildings = { id = "ah_buildings", text = "Dein Verkaufshaus steht schon fertig auf deinem Grundstück! Öffne mit M das Menü und dort den Tab „Gebäude“. Schau es dir an und tipp danach hier auf „Weiter“.", target = nil, zone = nil, event = "next", openTab = "buildings" },
	ah_collect = { id = "ah_collect", text = "Hol im Tab „Gebäude“ beim Verkaufshaus deine ersten Credits ab – tipp dort auf „Abholen“.", target = nil, zone = nil, event = "action:ow_collect" },
	ah_dealer = { id = "ah_dealer", text = "Schau beim Händler (Autohaus in der Stadt) vorbei und drück dort E. Dein eigenes Verkaufshaus bringt dir dort Rabatt – kaufen kannst du ab Level 3.", target = "dealer", zone = "city", event = "tab:dealer", at = "city" },
	ah_sell = { id = "ah_sell", text = "Jetzt dein erster Verkauf: Warte am Kiesplatz auf einen Kunden und nenne deinen Preis. „Günstig“ klappt immer!", target = "kiesplatz", zone = "city", event = "action:story_sell", at = "end", passiveSkip = true },
	-- produktion (Herstellung): die geschenkte Herstellung, Bauteil-Pakete, Tuning-Zentrum
	pr_buildings = { id = "pr_buildings", text = "Deine Herstellung steht schon fertig auf deinem Grundstück! Öffne mit M das Menü und dort den Tab „Gebäude“. Schau sie dir an und tipp danach hier auf „Weiter“.", target = nil, zone = nil, event = "next", openTab = "buildings" },
	pr_collect = { id = "pr_collect", text = "Hol im Tab „Gebäude“ deine ersten Bauteil-Pakete aus der Herstellung ab – tipp dort auf „Abholen“. Darin stecken Altteile.", target = nil, zone = nil, event = "action:ow_collect" },
	pr_tuning = { id = "pr_tuning", text = "Schau im Tuning-Zentrum in der Stadt vorbei und drück dort E. Hier machen deine Altteile später Autos schneller – Tuning-Projekte gibt es ab Level 6.", target = "tuning", zone = "city", event = "tab:tuning", at = "city" },
	-- schrottplatz: der geschenkte Schrottplatz, Schrott abholen, Schrottpresse
	sc_buildings = { id = "sc_buildings", text = "Dein Schrottplatz steht schon fertig auf deinem Grundstück! Öffne mit M das Menü und dort den Tab „Gebäude“. Schau ihn dir an und tipp danach hier auf „Weiter“.", target = nil, zone = nil, event = "next", openTab = "buildings" },
	sc_collect = { id = "sc_collect", text = "Hol im Tab „Gebäude“ Schrott und Altteile von deinem Schrottplatz ab – tipp dort auf „Abholen“. Der Schrott landet bei deiner Schrottpresse.", target = nil, zone = nil, event = "action:ow_collect" },
	sc_press = { id = "sc_press", text = "Schau an der Schrottpresse in der Stadt vorbei und drück dort E. Ab Level 2 presst du hier Schrott und tauschst ihn beim Schrotthändler gegen Credits.", target = "press", zone = "city", event = "tab:press", at = "city" },
}
local TS = TUTORIAL_STEPS

GameConfig.Tutorial = {
	Reward = { credits = 500, xp = 60 }, -- einmalig am Ende (nicht beim Überspringen, nicht nach einem Neustart), für jeden Weg gleich
	Intro = { TS.move, TS.menu } :: { TutorialStep },
	Paths = {
		werkstatt = { TS.reception, TS.accept, TS.obd, TS.repair, TS.settle, TS.dealer, TS.goals },
		autohaus = { TS.ah_buildings, TS.ah_collect, TS.ah_dealer, TS.ah_sell },
		produktion = { TS.pr_buildings, TS.pr_collect, TS.pr_tuning },
		schrottplatz = { TS.sc_buildings, TS.sc_collect, TS.sc_press },
	} :: { [string]: { TutorialStep } },
	End = { TS.map, TS.kiesplatz } :: { TutorialStep }, -- "city"-Schritte kommen zwischen End[1] und End[2]
	DefaultPath = "werkstatt", -- ohne Startwahl (startPath = "") und für Veteranen
	Steps = {} :: { TutorialStep }, -- = ByPath.werkstatt (unten gefüllt)
	ByPath = {} :: { [string]: { TutorialStep } },
	EventKinds = { "next", "station", "tab", "job", "settled", "action" },
}
do
	local TU = GameConfig.Tutorial
	for typ, middle in pairs(TU.Paths) do
		local list = {}
		local function add(st)
			table.insert(list, st)
		end
		for _, st in ipairs(TU.Intro) do
			add(st)
		end
		for _, st in ipairs(middle) do
			if st.at == nil or st.at == "start" then
				add(st)
			end
		end
		add(TU.End[1])
		for _, st in ipairs(middle) do
			if st.at == "city" then
				add(st)
			end
		end
		for i = 2, #TU.End do
			add(TU.End[i])
		end
		for _, st in ipairs(middle) do
			if st.at == "end" then
				add(st)
			end
		end
		TU.ByPath[typ] = list
	end
	TU.Steps = TU.ByPath[TU.DefaultPath]
end

---------------------------------------------------------------- Startwahl in der Open World (wie im Tycoon)
-- 3.x: Beim ersten Open-World-Beitritt MUSS ein NEUES Profil einen von vier Startwegen wählen (StartUI → Aktion
-- start_choose {path}, einmalig; StartService). Es gibt kein „Später entscheiden“ mehr: die Karte bleibt, bis gewählt
-- ist (nur 2.4.0-Dialoge, Tablet und Minispiel-Panel dürfen sie kurz verdecken). Gespeichert in d.games.meta.startPath
-- ("" = noch nicht gewählt). Veteranen (abgerechnete Aufträge, Tutorial beendet/übersprungen oder schon ein
-- Open-World-Gebäude, bevor die Wahl je gezeigt wurde) bekommen automatisch Default ("werkstatt") und sehen die Wahl
-- nie (MetaRules.Load / MetaRules.ResolveStartPath). Gleiche Namen wie die Gebäude im Tycoon (GameConfig.Tycoon).
-- werkstatt = der klassische 2.4.0-Start (das Werkstatt-Grundstück hat jeder). autohaus (Verkaufshaus) / produktion
-- (Herstellung) / schrottplatz: dieses Open-World-Gebäude steht sofort auf Stufe 1 – geschenkt, ohne Level-Sperre und
-- ohne Bauzeit (OWRules.GrantStart). yieldHours = so viele Stunden Ertrag warten beim Start schon zum Abholen
-- (Tutorial-Schritt „Abholen“ und die erste Story-Mission); höchstens OW.PassiveCapHours.
-- Direkt nach der Wahl läuft Kapitel 1 des Wegs (GameConfig.Story.Chapters[1].Paths[typ]); chapter = Kapiteltitel
-- auf der Karte (= Story.Chapters[1].PathInfo[typ].title).
-- Balance: Verkaufshaus Stufe 1 = 25 Cr/Min (≈ 12 % der Werkstatt auf Level 1, Grenze 25 %), Startertrag 300 Cr;
-- Herstellung: 2 Bauteil-Pakete (20 Altteile); Schrottplatz: 2 Mrd. Schrott (≈ 200 Cr an der Presse) + 2 Altteile.
-- icon = gezeichnetes Symbol der Karte (StartUI: wrench | car | factory | scrap; nur Frames, keine Bilder)
export type StartPath = {
	id: string, name: string, short: string, desc: string, first: string, bonus: string, color: string,
	building: string?, yieldHours: number, icon: string, chapter: string,
}
GameConfig.Start = {
	Order = { "werkstatt", "autohaus", "produktion", "schrottplatz" },
	Default = "werkstatt",
	Title = "Wie willst du starten?",
	Intro = "Such dir aus, womit du in der Spielermeile loslegst – deine Story beginnt sofort! Deine Werkstatt hast du immer, alles andere kannst du später auch noch bauen.",
	Paths = {
		werkstatt = {
			id = "werkstatt", name = "Werkstatt", color = "blue", building = nil, yieldHours = 0, icon = "wrench",
			chapter = "Kapitel 1: Die ersten Kunden",
			short = "Autos reparieren wie ein echter Mechaniker",
			desc = "Kunden bringen ihre Autos zu dir.\nDu findest den Fehler mit dem OBD-Tester und reparierst sie.",
			first = "Zuerst: einen Ölwechsel annehmen, reparieren und abrechnen.",
			bonus = "Bonus: der klassische Start – Aufträge bringen dir am meisten XP.",
		},
		autohaus = {
			id = "autohaus", name = "Verkaufshaus", color = "green", building = "autohaus", yieldHours = 0.2, icon = "car",
			chapter = "Kapitel 1: Der Kiesplatz",
			short = "Autos verkaufen und Credits verdienen",
			desc = "Du verkaufst Gebrauchtwagen am Kiesplatz.\nIn der Großen Werkstatt machst du sie schick – und verkaufst sie teurer.",
			first = "Zuerst: Credits im Verkaufshaus abholen und am Kiesplatz verkaufen.",
			bonus = "Bonus: Verkaufshaus Stufe 1 geschenkt – Credits jede Stunde und Rabatt beim Händler.",
		},
		produktion = {
			id = "produktion", name = "Herstellung", color = "yellow", building = "produktion", yieldHours = 12, icon = "factory",
			chapter = "Kapitel 1: Die kleine Fabrik",
			short = "Bauteile herstellen und ausliefern",
			desc = "Deine Fabrik packt Bauteil-Pakete voller Altteile.\nDu lieferst sie mit deinem Flitzer aus und verkaufst Teile.",
			first = "Zuerst: Bauteil-Pakete abholen und die erste Lieferung fahren.",
			bonus = "Bonus: Herstellung Stufe 1 geschenkt – Bauteil-Pakete und schnelleres Tuning.",
		},
		schrottplatz = {
			id = "schrottplatz", name = "Schrottplatz", color = "red", building = "schrottplatz", yieldHours = 1, icon = "scrap",
			chapter = "Kapitel 1: Schrott ist Gold",
			short = "Schrott sammeln und Altteile finden",
			desc = "Dein Schrottplatz sammelt Schrott und Altteile.\nDu presst Schrott, zerlegst Autos und verkaufst Teile an die Große Werkstatt.",
			first = "Zuerst: Schrott abholen und Altteile an die Große Werkstatt verkaufen.",
			bonus = "Bonus: Schrottplatz Stufe 1 geschenkt – Schrott, Altteile und mehr Schrott an der Presse.",
		},
	} :: { [string]: StartPath },
	Texts = {
		chosen = "Super! Du startest mit: %s. Deine erste Mission wartet schon!",
		gift = "Geschenk: %s Stufe 1 steht schon fertig auf deinem Grundstück!",
		already = "Deinen Start hast du schon gewählt.",
		invalid = "Diesen Start gibt es nicht. Tipp auf eine der vier Karten.",
		notHere = "Deinen Start wählst du in der Spielermeile (Open World).",
		choose = "Das wähle ich!",
		waiting = "Einen Moment …",
		mustChoose = "Wähle zuerst, womit du startest – tipp auf eine der vier Karten.",
		reset = "Startwahl zurückgesetzt: Kapitel 1 beginnt von vorn. Wähle deinen Start neu!",
	},
}
GameConfig.Start.PathSet = {}
for _, typ in ipairs(GameConfig.Start.Order) do
	GameConfig.Start.PathSet[typ] = true
end

---------------------------------------------------------------- Beginner-Hinweise (§6)
-- when: "unlock:<key>" (Level mit Freischaltung erreicht), "station:<key>" (Station geöffnet, Plot oder Stadt
-- oder Lobby), "first:<stat>" (Statistik aus MiniRules.STAT_KEYS zum ersten Mal > 0), "job:<phase>" (ein 2.4.0-Auftrag
-- ist zum ersten Mal in dieser Phase: accepted = angenommen, approval = Kunde muss per Handy freigeben; TutorialService.Tick). Je einmal
-- (meta.hintsSeen), nur bei meta.beginner = true, Anzeige als Karte oben rechts.
GameConfig.Hints = {
	{ id = "h_workshop", when = "station:workshop", text = "Am Empfang nimmst du Aufträge an und rechnest fertige Autos ab." },
	{ id = "h_hand", when = "job:accepted", text = "Werkzeug musst du nicht wechseln: Beim Drücken von E nimmt dein Mechaniker das richtige selbst. Mit dem Hand-Knopf links in der Werkzeugleiste (Taste 1) hast du die Hände frei." },
	{ id = "h_phone", when = "job:approval", text = "Der OBD-Tester hat Fehler gefunden! Nimm dein Handy (Taste P oder der Handy-Knopf rechts) und ruf den Kunden an. Er entscheidet, ob du reparieren darfst." },
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
	{ id = "h_tycoon", when = "station:mode_tycoon", text = "Tycoon: eine Tycoon-Runde mit Bargeld. Fertige Runden bringen dauerhafte Boni in der Open World." },
} :: { Hint }

---------------------------------------------------------------- Deckel der Werkstatt-Vergütung (§8)
-- Gilt nur für den Ausbaustufe-4-Faktor Tycoon × OW-Perk (CrossBonus.CareerCapped); Prestige wirkt außerhalb.
GameConfig.WorkshopRewardCap = 1.6

---------------------------------------------------------------- XP-Regler (§3)
-- Ziel Level 50 nach etwa 8 Std., Level 90 nach etwa 25–35 Std. gemischtem Spiel (geprüft von
-- tools/economy_sim.py --check, Stand docs/BALANCE.md: 8,2 / 25,3 Std.). Nachgeregelt wird nur hier, nie in Rules.XPNeeded.
-- Rund 90 % der XP kommen aus den 2.4.0-Aufträgen; diese Regler können XP nur hinzufügen (nicht bremsen).
GameConfig.XP = {
	Tutorial = 60, -- = Tutorial.Reward.xp
	StoryMission = { 60, 120, 250, 500, 900 }, -- je Mission nach Kapitel (Platzhalter)
	StoryChapter = { 150, 300, 600, 1200, 2500 }, -- Abschluss je Kapitel (Platzhalter)
	SideMission = 50, -- Nebenmission (Platzhalter)
	TycoonStage = 40, -- je erreichter Tycoon-Stufe (Platzhalter)
	TycoonRun = 300, -- je abgeschlossenem Durchlauf / Rebirth (Platzhalter)
	OwBuild = 30, -- je gebauter Gebäudestufe in der Open World (Platzhalter)
}

---------------------------------------------------------------- Tycoon / Tycoon (§8, Meilenstein 4)
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
			name = "Verkaufshaus", desc = "Vom Kiesplatz zum Glaspalast: mehr Ausstellungsfläche, mehr Verkäufe.", -- 3.x: Name wie die Startwahl
			baseRate = 2.5, items = { "lack", "reifen" },
			producers = { "Verkaufsstand", "Showroom", "Glashalle", "Probefahrt-Strecke", "Luxus-Etage" },
			tempo = { "Prospekte", "Verkaufstraining", "Online-Anzeigen", "Finanzierungsbüro", "Drehbühne" },
			lager = { "Stellplätze", "Parkdeck", "Lackdepot", "Reifenhotel", "Auslieferungshalle" },
			deko = { "Fahnenmast", "Ballonbogen", "Lichtband", "Kaffeebar", "Springbrunnen" },
		},
		produktion = {
			name = "Herstellung", desc = "Deine eigene Autofabrik: Band, Presse, Roboter – und Bauteile für alle.", -- 3.x: Name wie die Startwahl
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
-- Einnahmen zusammen ≤ 25 %): Autohaus Stufe 1 = 25 Cr/Min (3 % auf Level 10) … Stufe 4 = 300 Cr/Min ab Level 35 (≈ 7 %);
-- je Stufe ein eigenes Mindest-Level (st.level), geprüft von tools/economy_sim.py --check (≤ 25 % der Werkstatt des Levels).
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
			typ = "autohaus", name = "Verkaufshaus", unlock = "building:autohaus", -- 3.x: Name wie die Startwahl
			desc = "Dein eigenes Verkaufshaus auf dem Grundstück: verkauft Autos, während du unterwegs bist (Credits je Stunde, abholen) und bringt dir Rabatt beim Händler.",
			Stages = {
				-- Stufen-Level (Balance): Ertrag/Min ≤ 25 % der Werkstatt dieses Levels (tools/economy_sim.py --check)
				{ stage = 1, price = 12000, buildSeconds = 600, yieldPerHour = 1500 },
				{ stage = 2, price = 50000, buildSeconds = 2700, yieldPerHour = 4000, level = 15 },
				{ stage = 3, price = 180000, buildSeconds = 10800, yieldPerHour = 9000, level = 25 },
				{ stage = 4, price = 600000, buildSeconds = 28800, yieldPerHour = 18000, level = 35 },
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
			typ = "produktion", name = "Herstellung", unlock = "building:produktion", -- 3.x: Name wie die Startwahl
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
--   Startweg (GameConfig.Start, meta.startPath), 3.x: Ein Kapitel kann Paths = { [typ] = { Mission, … } } tragen (gleich
--   viele Missionen wie Missions); für Spieler mit diesem Startweg gilt diese Liste (StoryRules.MissionAt/Missions), ohne
--   Startweg Missions. Stelle i aller Listen ist eine Stelle mit Varianten: erledigt, sobald irgendeine Variante erledigt
--   ist (Veteranen behalten ihren Stand); eine schon laufende Variante läuft zu Ende. PathInfo[typ] = { title, intro }.
--   minLevel = n: Mission braucht mindestens dieses Level (StoryRules.RequiredLevel); repaired = true (kind sell): zählt
--   nur Verkäufe frisch reparierter Wagen (Sale.RepairedBonus); events = { … } bei kind sell: diese Ereignisse zählen auch.
--   Neue Ereignisse 3.x: "settle:<auftragsart>" (abgerechneter 2.4.0-Auftrag dieser Art; "settle:inspection" = ein
--   abgerechneter Fahrzeug-Check, auch mit freigegebenem Befund), "parts_bought" (Ersatzteile gekauft),
--   "equipment_bought" (Werkstattgerät gekauft), "pw_repair" / "pw_parts_sold" (Große Werkstatt, PublicWorkshopService).
--   kind = "own" mit owTyp/owStat: Lebenszeit-Zähler eines Open-World-Gebäudes (d.games.ow.buildings[owTyp][owStat],
--   OWRules: packs = abgeholte Bauteil-Pakete, partsTotal = abgeholte Altteile, collects = Abholungen mit Ertrag)
local Story = {}

Story.Title = "Vom Kiesplatzhändler zum Mega-Verkäufer"

---------------------------------------------------------------- Kapitel (§7: 5 Kapitel à 3 Missionen; Level wie GameConfig.Unlocks "story:<n>")
Story.Chapters = {
	-- Balance wie tools/economy_sim.py: (Credits + XP × XP-Wert) / Minuten + Kapitel-Bonus ≤ 40 % der Werkstatt auf Level 1
	-- (tests/test_start.lua prüft das für jeden Weg)
	-- 3.x: Kapitel 1 je Startweg (GameConfig.Start): Paths[typ] = die Missionen des Wegs, alle Wege gleich viele Stellen
	-- (Stelle i aller Wege = Variante derselben Stelle; erledigt ist sie, sobald irgendeine Variante erledigt ist).
	-- Missions = Weg autohaus (Verkaufshaus; auch ohne Startwahl). PathInfo[typ] = { title, intro } (Kapitelkopf,
	-- Startkarten). Die Story startet sofort nach der Wahl (StoryService: Mission 1 aktiv), danach läuft jede nächste
	-- Mission von selbst an (StoryRules.AutoStart). xp = 80 je Mission: nach drei Missionen ist jeder Spieler Level 3
	-- (2.4.0-Kurve: 106 + 132 XP) – so sind Presse (Level 2) und Zerlegeplatz (Level 3) ohne Sackgasse erreichbar
	-- (StoryRules.UnlockCheck rechnet die XP der vorigen Missionen mit). Belohnungen ≤ 40 % der Werkstatt auf Level 1.
	-- Ereignisse: settle:<auftragsart> und parts_bought / equipment_bought erkennt StoryService aus dem Profil (d.jobs,
	-- d.inventory/d.orders, d.equipment); pw_repair / pw_parts_sold kommen von PublicWorkshopService (api.storyEvent);
	-- delivery = Lieferfahrt (City.Missions.Delivery_<n>, mit dem Flitzer).
	{
		id = 1, title = "Der Kiesplatz", unlockLevel = 1,
		intro = "Neben deinem neuen Verkaufshaus hast du einen kleinen Kiesplatz am Stadtrand gepachtet: drei alte Autos und ein handgemaltes Schild. "
			.. "Die Kunden kommen schon, jetzt brauchst du nur noch den richtigen Preis. "
			.. "Und in der Großen Werkstatt machst du alte Autos wieder schick – die verkaufen sich teurer!",
		Missions = {
			{ id = "c1_ah1", title = "Erste Einnahmen vom Verkaufshaus", kind = "own", owTyp = "autohaus", owStat = "collects", target = 1, minutes = 3,
				text = "Dein Verkaufshaus auf deinem Grundstück hat schon Credits verdient. Drück M, öffne den Tab „Gebäude“ und tipp beim Verkaufshaus auf „Abholen“.",
				reward = { credits = 60, xp = 80 } },
			{ id = "c1_m1", title = "Drei Gebrauchtwagen verkaufen", kind = "sell", target = 3, minutes = 4,
				text = "Reise mit dem Stadtplan zum „Kiesplatz (Gebrauchtwagen)“ am Stadtrand. Sprich dort mit den Kunden und nenne deinen Preis: günstig klappt immer, teuer braucht Verhandlungsglück.",
				reward = { credits = 150, xp = 80 } },
			{ id = "c1_m2", title = "Zurück in die Werkstatt", kind = "event", event = "settle", target = 1, minutes = 4,
				text = "Deine Kunden wollen auch reparieren lassen. Geh in deiner Werkstatt zum Empfang, nimm einen Auftrag an, repariere das Auto mit E und rechne am Empfang ab.",
				reward = { credits = 100, xp = 80 } },
			-- ein eigener Gebrauchtwagen für die Große Werkstatt (der Flitzer ist das Startauto und wird dort nicht repariert);
			-- Händler ab Level 3 – nach drei Missionen (240 XP) sicher erreicht
			{ id = "c1_ah5", title = "Dein erster Gebrauchtwagen", kind = "event", event = "car_bought", target = 1, minutes = 6,
				text = "Spar deine Credits und kauf beim Händler im „Autohaus“ der Stadt (Stadtplan) deinen ersten Gebrauchtwagen, zum Beispiel den Komet C1. Dein Verkaufshaus gibt dir dort Rabatt.",
				reward = { credits = 250, xp = 80 } },
			{ id = "c1_ah3", title = "Ab in die Große Werkstatt", kind = "event", event = "pw_repair", target = 1, minutes = 5,
				text = "Fahr deinen Gebrauchtwagen in die „Große Werkstatt“ am Westende der Spielermeile (Stadtplan: „Große Werkstatt“) und lass ihn dort reparieren. Repariert bringt er beim Verkauf mehr.",
				reward = { credits = 200, xp = 80 } },
			{ id = "c1_ah4", title = "Den reparierten Wagen teurer verkaufen", kind = "sell", target = 1, repaired = true, events = { "action:mini_car_sell" }, minutes = 4,
				text = "Verkauf jetzt teurer: Am „Kiesplatz (Gebrauchtwagen)“ bringt dein nächster Verkauf nach der Reparatur 50 % mehr Gewinn – oder verkauf deinen reparierten Wagen beim Händler (Garage im Menü M) zum höheren Preis.",
				reward = { credits = 150, xp = 80 } },
		},
		PathInfo = {
			autohaus = { title = "Der Kiesplatz" }, -- Intro wie oben
			werkstatt = { title = "Die ersten Kunden",
				intro = "Deine eigene Werkstatt! Die ersten Kunden stehen schon am Empfang. Ölwechsel, Fahrzeug-Check mit dem OBD-Tester, "
					.. "Ersatzteile bestellen – zeig, dass du ein echter Mechaniker bist." },
			produktion = { title = "Die kleine Fabrik",
				intro = "Deine Herstellung packt Bauteil-Pakete voller Altteile. Jetzt musst du sie unter die Leute bringen: "
					.. "mit deinem Flitzer auf Lieferfahrt und an die Große Werkstatt der Spielermeile." },
			schrottplatz = { title = "Schrott ist Gold",
				intro = "Was andere wegwerfen, ist für dich bares Geld. Dein Schrottplatz sammelt Schrott und Altteile – "
					.. "du presst, zerlegst und verkaufst die besten Teile an die Große Werkstatt." },
		},
		Paths = {
			werkstatt = {
				{ id = "c1_ws1", title = "Der erste Ölwechsel", kind = "event", event = "settle:oil", target = 1, minutes = 4,
					text = "Geh in deiner Werkstatt zum Empfang und nimm einen „Ölwechsel“ an. Repariere das Auto mit E und rechne danach am Empfang ab.",
					reward = { credits = 150, xp = 80 } },
				{ id = "c1_ws2", title = "Fahrzeug-Check mit Kundenanruf", kind = "event", event = "settle:inspection", target = 1, minutes = 5,
					text = "Nimm am Empfang einen „Fahrzeug-Check“ an und lies am Auto mit dem OBD-Tester den Fehlerspeicher. Findet er Fehler, ruf den Kunden mit dem Handy an (Taste P). Rechne den Check am Empfang ab.",
					reward = { credits = 180, xp = 80 } },
				{ id = "c1_ws3", title = "Ersatzteile kaufen", kind = "event", event = "parts_bought", target = 1, minutes = 3,
					text = "Kauf Ersatzteile für die nächsten Aufträge: am Büro-PC in deiner Werkstatt oder im Tablet (Taste Tab) unter „Teilehandel“, zum Beispiel Ölfilter.",
					reward = { credits = 80, xp = 80 } },
				{ id = "c1_ws4", title = "Drei Aufträge abrechnen", kind = "stat", stat = "jobsDone", target = 3, minutes = 9,
					text = "Rechne in deiner Werkstatt drei weitere Aufträge am Empfang ab. Jeder Auftrag bringt Credits, XP und Ruf.",
					reward = { credits = 300, xp = 80 } },
				{ id = "c1_ws5", title = "Ein neues Werkstattgerät", kind = "event", event = "equipment_bought", minLevel = 2, target = 1, minutes = 4,
					text = "Kauf im Tablet (Taste Tab) unter „Ausbau“ ein Werkstattgerät, zum Beispiel den Radheber – damit kannst du Reifen wechseln.",
					reward = { credits = 120, xp = 80 } },
				-- Startgeld 800 + Tutorial 500 + Missionen ≈ 2.000 Cr: 2.500 verlangt noch etwas eigenes Spiel
				-- (gemeinsame letzte Mission der Wege Werkstatt, Herstellung und Schrottplatz)
				{ id = "c1_m3", title = "Die ersten 2.500 Credits", kind = "own", money = 2500, target = 2500, minutes = 4,
					text = "Bring deinen Kontostand auf 2.500 Credits – mit Aufträgen in deiner Werkstatt, Verkäufen und dem Abholen in deinen Gebäuden (Tab „Gebäude“).",
					reward = { credits = 160, xp = 80 } },
			},
			produktion = {
				{ id = "c1_m1_produktion", title = "Zwei Bauteil-Pakete abholen", kind = "own", owTyp = "produktion", owStat = "packs", target = 2, minutes = 4,
					text = "Deine Herstellung hat schon Bauteil-Pakete voller Altteile gepackt. Drück M, öffne den Tab „Gebäude“ und tipp bei der Herstellung auf „Abholen“.",
					reward = { credits = 150, xp = 80 } },
				{ id = "c1_pr2", title = "Die erste Lieferfahrt", kind = "event", event = "delivery", target = 1, minutes = 5,
					text = "Hol dir deinen Flitzer (dein kleines Startauto) und fahr zum blauen Marker „LIEFERUNG · START“ an der Straße. Bring die Lieferung dann rechtzeitig zum grünen Ziel-Marker.",
					reward = { credits = 200, xp = 80 } },
				{ id = "c1_pr3", title = "Bauteile für die Große Werkstatt", kind = "event", event = "pw_parts_sold", target = 1, minutes = 4,
					text = "Fahr zur „Großen Werkstatt“ am Westende der Spielermeile (Stadtplan: „Große Werkstatt“) und verkauf dort Teile aus deiner Herstellung.",
					reward = { credits = 150, xp = 80 } },
				{ id = "c1_pr4", title = "Zwei Lieferfahrten", kind = "event", event = "delivery", target = 2, minutes = 8,
					text = "Deine Kunden warten! Fahr mit dem Flitzer noch zwei Lieferungen – vom blauen Start-Marker zum grünen Ziel-Marker.",
					reward = { credits = 250, xp = 80 } },
				{ id = "c1_pr5", title = "Ein Auftrag in der Werkstatt", kind = "event", event = "settle", target = 1, minutes = 4,
					text = "Deine Bauteile helfen auch beim Reparieren: Geh in deiner Werkstatt zum Empfang, nimm einen Auftrag an, repariere das Auto mit E und rechne ab.",
					reward = { credits = 100, xp = 80 } },
				"c1_m3",
			},
			schrottplatz = {
				{ id = "c1_m1_schrottplatz", title = "Altteile vom Schrottplatz", kind = "own", owTyp = "schrottplatz", owStat = "partsTotal", target = 2, minutes = 4,
					text = "Dein Schrottplatz hat schon Schrott und Altteile gesammelt. Drück M, öffne den Tab „Gebäude“ und tipp beim Schrottplatz auf „Abholen“.",
					reward = { credits = 150, xp = 80 } },
				{ id = "c1_sc2", title = "Teile an die Große Werkstatt", kind = "event", event = "pw_parts_sold", target = 1, minutes = 4,
					text = "Fahr zur „Großen Werkstatt“ am Westende der Spielermeile (Stadtplan: „Große Werkstatt“) und verkauf dort deine Altteile.",
					reward = { credits = 150, xp = 80 } },
				{ id = "c1_sc3", title = "Ran an die Schrottpresse", kind = "stat", stat = "clicks", target = 20, minutes = 3,
					text = "Reise mit dem Stadtplan zur „Schrottpresse“, drück dort E und klick 20-mal auf die Presse.",
					reward = { credits = 80, xp = 80 } },
				{ id = "c1_sc4", title = "Das erste Unfallauto zerlegen", kind = "stat", stat = "dismantled", target = 1, minutes = 4,
					text = "Reise mit dem Stadtplan zum „Schrottplatz“. Kauf am Zerlegeplatz ein Unfallauto und zerleg es in Altteile.",
					reward = { credits = 120, xp = 80 } },
				{ id = "c1_sc5", title = "Schrott gegen Credits", kind = "event", event = "action:mini_press_exchange", target = 1, minutes = 3,
					text = "Geh zum „Schrotthändler“ an der Schrottpresse (Stadtplan) und tausch deinen Schrott gegen Credits.",
					reward = { credits = 80, xp = 80 } },
				"c1_m3",
			},
		},
	},
	{
		id = 2, title = "Die erste Werkstatt", unlockLevel = 5,
		intro = "Mit den ersten Credits wird deine Werkstatt zum richtigen Betrieb. "
			.. "Deine Kunden wollen nicht nur kaufen, sondern auch reparieren lassen. "
			.. "Zeig, was du kannst – an der Hebebühne und im Mechaniker-Quiz.",
		Missions = {
			{ id = "c2_m1", title = "Fünf Aufträge abrechnen", kind = "stat", stat = "jobsDone", target = 5, minutes = 10,
				text = "Fünf Kundenautos in deiner Werkstatt reparieren und am Empfang abrechnen. Jeder Auftrag bringt Credits, XP und Ruf.",
				reward = { credits = 800 } },
			{ id = "c2_m2", title = "Hebebühne Nummer zwei", kind = "own", bays = 2, target = 2, minutes = 5,
				text = "Kauf am Hallenanbau deiner Werkstatt (Tablet → „Ausbau“) eine zweite Hebebühne. Zwei Aufträge gleichzeitig – doppelt so schnell.",
				reward = { credits = 500 } },
			{ id = "c2_m3", title = "Mechaniker-Quiz bestehen", kind = "stat", stat = "quizCorrect", target = 10, minutes = 3,
				text = "Beantworte im „Mechaniker-Quiz“ (Stadtplan) zehn Fragen richtig. Diagnosepunkte machen deine Reparaturen schneller.",
				reward = { credits = 400 } },
		},
	},
	{
		id = 3, title = "Das Autohaus", unlockLevel = 15,
		intro = "Die ganze Stadt redet über dich! Zeit für ein eigenes Autohaus auf deinem Grundstück. "
			.. "Kauf dein erstes Auto beim Händler, fahr es auf der Teststrecke ein und mach dir im Auktionshaus einen Namen.",
		Missions = {
			{ id = "c3_m1", title = "Das eigene Verkaufshaus", kind = "build", typ = "autohaus", stage = 1, target = 1, minutes = 10,
				text = "Bau auf deinem Grundstück das Gebäude „Verkaufshaus“ (Menü M → Tab „Gebäude“). Es bringt passive Verkaufserlöse und Händler-Rabatt.",
				reward = { credits = 2500 } },
			{ id = "c3_m2", title = "Der erste Neuwagen", kind = "event", event = "car_bought", target = 1, minutes = 8,
				text = "Kauf beim Händler im „Autohaus“ der Stadt (Stadtplan) ein Auto für deine Garage. Mit Rabatt aus deinem Verkaufshaus wird's günstiger.",
				reward = { credits = 2000 } },
			{ id = "c3_m3", title = "Ab auf die Teststrecke", kind = "event", event = "track_finish", target = 1, minutes = 4,
				text = "Fahr mit deinem eigenen Auto auf der „Teststrecke“ (Stadtplan) ein Zeitfahren bis ins Ziel. Die Zeit ist egal – Hauptsache ankommen!",
				reward = { credits = 400 } },
			{ id = "c3_m4", title = "Unter dem Hammer", kind = "event", events = { "auction_won", "auction_consigned" }, target = 1, minutes = 10,
				text = "Gewinne eine NPC-Auktion im Auktionshaus (Stadtplan: „Auktion“) – oder (ab Level 20) gib ein eigenes Auto in die Auktion.",
				reward = { credits = 3000 } },
		},
	},
	{
		id = 4, title = "Die Produktion", unlockLevel = 30,
		intro = "Große Verkäufer bauen ihre Autos selbst. Mit Schrottplatz und Produktion wird aus Altteilen Neues – "
			.. "und am Kiesplatz warten jetzt Kunden mit besonderen Wünschen und dickem Geldbeutel.",
		Missions = {
			{ id = "c4_m1", title = "Der eigene Schrottplatz", kind = "build", typ = "schrottplatz", stage = 1, target = 1, minutes = 10,
				text = "Bau das Gebäude „Schrottplatz“ auf deinem Grundstück (Menü M → Tab „Gebäude“). Es liefert passiv Schrott und Altteile.",
				reward = { credits = 6000 } },
			{ id = "c4_m2", title = "Die Herstellung läuft an", kind = "build", typ = "produktion", stage = 1, target = 1, minutes = 15,
				text = "Bau die „Herstellung“ auf deinem Grundstück (Menü M → Tab „Gebäude“). Sie produziert Bauteil-Pakete – und später ganze Autos.",
				reward = { credits = 9000 } },
			{ id = "c4_m3", title = "Drei Sondermodelle verkaufen", kind = "sell", target = 3, special = true, minutes = 6,
				text = "Am „Kiesplatz (Gebrauchtwagen)“ fragen jetzt Sammler nach Sondermodellen. Verkauf drei davon – die Preisstufen gelten wie immer.",
				reward = { credits = 5000 } },
		},
	},
	{
		id = 5, title = "Der Mega-Verkäufer", unlockLevel = 50,
		intro = "Der letzte Schritt: Deine Produktion läuft auf Hochtouren, deine Kunden zahlen Bestpreise, "
			.. "und in deiner Garage steht ein Traumwagen. Dann kennt die ganze Stadt deinen Namen – Mega-Verkäufer!",
		Missions = {
			{ id = "c5_m1", title = "Herstellung auf Stufe 4", kind = "build", typ = "produktion", stage = 4, target = 4, minutes = 30,
				text = "Bau deine Herstellung bis Stufe 4 aus (Menü M → Tab „Gebäude“). Ab dann rollt alle zwei Tage ein Auto-Gutschein für einen Kompaktwagen vom Band.",
				reward = { credits = 20000 } },
			{ id = "c5_m2", title = "Zehn Verkäufe zum Bestpreis", kind = "sell", target = 10, tier = 3, minutes = 15,
				text = "Verkauf am „Kiesplatz (Gebrauchtwagen)“ zehn Autos zur Preisstufe „teuer“. Nur erfolgreiche Verhandlungen zählen.",
				reward = { credits = 15000 } },
			{ id = "c5_m3", title = "Der Traumwagen", kind = "own", cars = { "vektor_gold", "vektor_gtx", "aureon", "elys", "aureon_nero", "elys_proto" }, target = 1, minutes = 30,
				text = "Besitze einen Traumwagen: das Vektor RS Goldstück (Auktion, ab Level 50), einen Vektor GTX (Händler, ab Level 58) "
					.. "oder später einen Vektor Aureon V12 (ab Level 72) bzw. Nord Elys E9 (ab Level 90). Dann bist du der Mega-Verkäufer!",
				reward = { credits = 25000, cosmetic = "wrap_mega", title = "Mega-Verkäufer" } },
		},
	},
}

-- Weg autohaus = Missions; "c1_m3" in den Wegen Herstellung/Schrottplatz = dieselbe Mission wie im Weg Werkstatt
-- (gemeinsame letzte Stelle)
do
	local ch1 = Story.Chapters[1]
	local byId = {}
	for _, m in ipairs(ch1.Missions) do
		byId[m.id] = m
	end
	for _, list in pairs(ch1.Paths) do
		for _, m in ipairs(list) do
			if type(m) == "table" then
				byId[m.id] = m
			end
		end
	end
	for _, list in pairs(ch1.Paths) do
		for i, m in ipairs(list) do
			if type(m) == "string" then
				list[i] = byId[m]
			end
		end
	end
	ch1.Paths.autohaus = ch1.Missions
	ch1.PathInfo.autohaus.intro = ch1.intro
end

---------------------------------------------------------------- Kiesplatz-Verkauf (story_sell {offer, price}; price = Preisstufe 1..3)
-- Der Spieler kauft den Gebrauchtwagen gedanklich aus dem Erlös: gutgeschrieben wird nur der Reingewinn (profit) je Stufe,
-- skaliert mit dem Level (×(1 + LevelFactor × (Level − 1)), Deckel LevelFactorCap) und bei Sondermodell-Kunden ×SpecialMultiplier.
-- Stufe 1 klappt immer, Stufe 2 meistens, Stufe 3 verhandelt der Kunde: Erfolg, wenn der beim Angebot festgelegte
-- Zufallswurf (Seed, Server) unter chance liegt. Kein Wurf je Klick – wer denselben Kunden zweimal fragt, bekommt dieselbe Antwort.
Story.Sale = {
	FirstOfferDelay = 2, -- Sekunden nach dem Beitritt bis zum ersten Kunden
	OfferInterval = 45, -- Sekunden bis zum nächsten Kunden nach einem Verkauf
	FailInterval = 20, -- Sekunden bis zum nächsten Kunden nach einer geplatzten Verhandlung
	-- 3.x: in der Großen Werkstatt reparierte Gebrauchtwagen (Ereignis pw_repair) verkaufen sich am Kiesplatz teurer:
	-- der nächste gelungene Verkauf bringt Gewinn × RepairedBonus (je Reparatur ein Verkauf, höchstens RepairedMax warten)
	RepairedBonus = 1.5,
	RepairedMax = 3,
	Patience = 180, -- Sekunden, die ein Kunde wartet, bevor er weiterzieht
	Range = 45, -- Studs: so nah muss die Figur an City.Stations.kiesplatz sein (ohne Station keine Prüfung)
	LevelFactor = 0.04,
	LevelFactorCap = 3, -- höchstens ×3 (ab Level 51)
	SpecialMultiplier = 3,
	SpecialChapter = 4, -- ab diesem Kapitel kommen Sondermodell-Kunden (jeder dritte Kunde)
	SpecialEvery = 3,
	Xp = { 6, 10, 15 }, -- XP je gelungenem Verkauf nach Preisstufe
	Tiers = {
		{ tier = 1, label = "günstig", profit = 35, chance = 1, hint = "Sicherer Verkauf, kleiner Gewinn." },
		{ tier = 2, label = "fair", profit = 60, chance = 0.85, hint = "Klappt meistens." },
		{ tier = 3, label = "teuer", profit = 95, chance = 0.5, hint = "Der Kunde feilscht – mit etwas Glück ein dicker Gewinn." },
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
		repaired = " Frisch repariert aus der Großen Werkstatt: +50 % Gewinn!",
		repairedReady = "Repariert! Am Kiesplatz bringt dein nächster Verkauf jetzt 50 % mehr Gewinn.",
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
		arcade_round = "feature:arcade",
		-- 3.x: Lieferfahrten gehen mit dem Flitzer (Startauto jedes Profils, car_call) schon ab Level 1; die Nebenmission
		-- s_delivery behält ihr eigenes unlock
		["action:mini_auction_bid"] = "feature:auction", ["action:mini_carwash"] = "feature:carwash",
		["action:mini_press_exchange"] = "feature:press", ["action:mini_car_tune"] = "feature:dealer",
		["action:mini_car_sell"] = "feature:dealer" },
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
	autoStarted = "Neue Mission: „%s“ – schau auf die Karte „Deine Mission“.", -- 3.x: Missionen starten von selbst
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

---------------------------------------------------------------- Shop & Monetarisierung (§9, Meilenstein 8)
-- Alle Zahlen des Shops: Kosmetik (Folierungen, Felgen-Sets, Hupen, Reifenspuren), DLC-Autos (Modelle in
-- CarCatalog.Dlc), Developer Products und Game Passes. Regeln in ShopRules, Server in ShopService, Quittungen in
-- Purchases/Profiles.GrantReceipt. Grundsätze für ein junges Publikum (Roblox-Richtlinien):
--   * keine bezahlten Zufallsboxen, keine Wahrscheinlichkeiten, kein Glücksspiel, kein Handel für Robux;
--   * kein Pay-to-win: DLC-Autos haben exakt die Fahrwerte ihres Basismodells (CarCatalog.Dlc.base);
--   * alles ist ohne Robux erreichbar: jede Kosmetik hat einen Credits-Preis ODER ist Belohnung (Prestige, Story,
--     DLC-Auto-Beigabe); DLC-Autos sind ab dem Level des Basismodells mit Credits kaufbar (DlcPriceFactor);
--   * alle Produkt-/Pass-IDs sind Platzhalter 0 -> der Client zeigt „noch nicht eingerichtet“ und öffnet keinen Prompt.
-- Kosmetik-Ids: "<slot>_<name>" (Slot wrap | rims | horn | trail). Prestige-Belohnungen heißen wrap_prestige_<rang>
-- (ungerade Ränge) bzw. rims_prestige_<rang> (gerade Ränge), vgl. GameConfig.Prestige.Rewards[].cosmetic; die
-- Story vergibt wrap_mega (Kapitel 5). Optik ist rein prozedural (Parts/Farben), keine rbxassetid.
-- style je Slot (VehicleFactory.ApplyCosmetics):
--   wrap  = { pattern = "stripes"|"flames"|"checker"|"waves"|"laurel"|"solid", color = {r,g,b}, color2 = {r,g,b}? }
--   rims  = { color = {r,g,b}, reflectance = 0..1, neon = {r,g,b}? }   (neon: Leuchtring an der Felge)
--   horn  = { text = string (Sprechblase beim Hupen), light = {r,g,b} (Blinkfarbe der Scheinwerfer) }
--   trail = { color = {r,g,b}, width = Studs }
export type Cosmetic = {
	id: string, slot: string, name: string, desc: string, creditsPrice: number?, rewardOnly: boolean?, level: number?,
	rewardText: string?, style: { [string]: any },
}
export type ShopGrants = { cosmetics: { string }?, cars: { string }? }
export type ShopProduct = {
	key: string, kind: string, name: string, desc: string, productId: number,
	grants: ShopGrants, creditsPrice: number?, pack: any?,
}
export type ShopPass = { key: string, name: string, desc: string, id: number, grants: ShopGrants }

local Shop = {
	Slots = { "wrap", "rims", "horn", "trail" },
	SlotNames = { wrap = "Folierung", rims = "Felgen-Set", horn = "Hupe", trail = "Reifenspur" },
	DlcPriceFactor = 1.5, -- Credits-Preis eines DLC-Autos = Händlerpreis des Basismodells × 1,5 (gleiche Werte)
	BuyXp = 10, -- XP für einen Kosmetik-Kauf mit Credits (DLC-Auto: CarCatalog.BuyXp)
	MaxOwned = 400, -- Deckel für owned beim Laden (Schutz vor aufgeblähten Profilen)
	PromptGraceSeconds = 60, -- so lange nach einem Robux-Prompt kein Credits-Kauf derselben Teile (Doppelkauf-Schutz)
	ReceiptRetrySeconds = 8, -- Takt, in dem eine aufgeschobene Quittung (Garage voll) erneut versucht wird (Purchases)
	HornSeconds = 0.6, -- Lichthupe: Dauer des Aufblitzens (mini_car_horn, VehicleFactory.Flash)
	HornCooldown = 1.5, -- Lichthupe: Abstand zwischen zwei Hupen
	Cosmetics = {} :: { Cosmetic },
	Products = {} :: { ShopProduct },
	Passes = {} :: { ShopPass },
}

-- Kaufbare Kosmetik (Credits; dieselbe Optik gibt es als Developer Product oder im Game Pass)
local COSMETICS: { Cosmetic } = {
	-- Folierungen
	{ id = "wrap_streifen", slot = "wrap", name = "Rennstreifen", desc = "Zwei klassische Streifen über Haube und Dach.",
		creditsPrice = 1500, level = 1, style = { pattern = "stripes", color = { 236, 238, 240 }, color2 = { 28, 30, 34 } } },
	{ id = "wrap_karo", slot = "wrap", name = "Zielflagge", desc = "Schwarz-weißes Karo wie auf der Zielflagge.",
		creditsPrice = 2000, level = 2, style = { pattern = "checker", color = { 236, 238, 240 }, color2 = { 28, 30, 34 } } },
	{ id = "wrap_flammen", slot = "wrap", name = "Flammen", desc = "Orange Flammen, die von der Motorhaube nach hinten züngeln.",
		creditsPrice = 2500, level = 3, style = { pattern = "flames", color = { 247, 120, 40 }, color2 = { 255, 210, 60 } } },
	{ id = "wrap_wellen", slot = "wrap", name = "Wellen", desc = "Türkise Wellen an den Seiten – wie Surfen auf Asphalt.",
		creditsPrice = 3000, level = 5, style = { pattern = "waves", color = { 48, 170, 157 }, color2 = { 107, 199, 210 } } },
	-- Felgen-Sets
	{ id = "rims_gold", slot = "rims", name = "Goldfelgen", desc = "Glänzende Felgen in Gold.",
		creditsPrice = 1200, level = 1, style = { color = { 224, 172, 60 }, reflectance = 0.35 } },
	{ id = "rims_carbon", slot = "rims", name = "Carbon-Felgen", desc = "Matte, dunkle Felgen im Carbon-Look.",
		creditsPrice = 1500, level = 2, style = { color = { 40, 42, 48 }, reflectance = 0.05 } },
	{ id = "rims_chrom_blau", slot = "rims", name = "Blauchrom", desc = "Chromfelgen mit blauem Schimmer.",
		creditsPrice = 1800, level = 4, style = { color = { 150, 190, 230 }, reflectance = 0.5 } },
	{ id = "rims_neon", slot = "rims", name = "Neonfelgen", desc = "Felgen mit leuchtendem Neonring – nachts ein Hingucker.",
		creditsPrice = 2500, level = 6, style = { color = { 30, 32, 36 }, reflectance = 0.1, neon = { 60, 255, 120 } } },
	-- Hupen (Text in der Sprechblase + Blinkfarbe der Scheinwerfer)
	{ id = "horn_melodie", slot = "horn", name = "Melodie-Hupe", desc = "Lichthupe mit Melodie-Sprechblase „♪ Tü-dü-düüü ♪“ und warmem Licht (Taste H oder HUPE-Knopf).",
		creditsPrice = 800, level = 1, style = { text = "♪ Tü-dü-düüü ♪", light = { 255, 220, 120 } } },
	{ id = "horn_fanfare", slot = "horn", name = "Fanfare", desc = "Lichthupe mit Fanfaren-Sprechblase „TÄÄÄ-TÄÄÄ!“ und orangem Licht (Taste H oder HUPE-Knopf).",
		creditsPrice = 1200, level = 3, style = { text = "TÄÄÄ-TÄÄÄ!", light = { 255, 160, 60 } } },
	{ id = "horn_laser", slot = "horn", name = "Laser-Hupe", desc = "Lichthupe mit Weltraum-Sprechblase „Piu-piu!“ und eisblauem Licht (Taste H oder HUPE-Knopf).",
		creditsPrice = 1500, level = 6, style = { text = "Piu-piu!", light = { 120, 220, 255 } } },
	-- Reifenspuren
	{ id = "trail_blau", slot = "trail", name = "Blaue Spur", desc = "Blaue Reifenspuren beim Driften.",
		creditsPrice = 1000, level = 2, style = { color = { 60, 120, 255 }, width = 0.6 } },
	{ id = "trail_regenbogen", slot = "trail", name = "Regenbogenspur", desc = "Bunte Spur in allen Farben.",
		creditsPrice = 2000, level = 4, style = { color = { 255, 90, 200 }, color2 = { 60, 200, 255 }, width = 0.8 } },
	{ id = "trail_neon", slot = "trail", name = "Neonspur", desc = "Grün leuchtende Spur – passt zu den Neonfelgen.",
		creditsPrice = 1800, level = 6, style = { color = { 60, 255, 120 }, width = 0.7 } },
	-- Belohnungen (nicht kaufbar): Story-Finale und Beigaben der DLC-Autos
	{ id = "wrap_mega", slot = "wrap", name = "Mega-Verkäufer", desc = "Die Folierung für den Mega-Verkäufer der Stadt.",
		rewardOnly = true, rewardText = "Story: Kapitel 5 „Der Traumwagen“",
		style = { pattern = "laurel", color = { 224, 172, 60 }, color2 = { 28, 30, 34 } } },
	{ id = "wrap_sunset", slot = "wrap", name = "Sunset", desc = "Sonnenuntergangs-Verlauf, exklusiv zum Komet S2 Sunset.",
		rewardOnly = true, rewardText = "Beigabe: Komet S2 Sunset",
		style = { pattern = "waves", color = { 247, 120, 40 }, color2 = { 235, 167, 48 } } },
	{ id = "wrap_nacht", slot = "wrap", name = "Nachtfalke", desc = "Violette Nachtstreifen, exklusiv zum Nord R4 Nachtfalke.",
		rewardOnly = true, rewardText = "Beigabe: Nord R4 Nachtfalke",
		style = { pattern = "stripes", color = { 160, 80, 255 }, color2 = { 28, 30, 34 } } },
	{ id = "wrap_blitz", slot = "wrap", name = "Blitz", desc = "Eisblaue Blitze, exklusiv zum Vektor RS Blitz.",
		rewardOnly = true, rewardText = "Beigabe: Vektor RS Blitz",
		style = { pattern = "flames", color = { 107, 199, 210 }, color2 = { 236, 238, 240 } } },
}
for _, c in ipairs(COSMETICS) do
	table.insert(Shop.Cosmetics, c)
end
-- Prestige-Belohnungen (GameConfig.Prestige.Rewards[rank].cosmetic): je Rang eine Folierung oder ein Felgen-Set
do
	local tierColors = { { 97, 112, 124 }, { 150, 110, 70 }, { 205, 210, 216 }, { 224, 172, 60 } } -- Silber, Bronze, Chrom, Gold je 5 Ränge
	for _, r in ipairs(GameConfig.Prestige.Rewards) do
		local tier = tierColors[math.min(#tierColors, math.floor((r.rank - 1) / 5) + 1)]
		local isWrap = r.cosmetic:sub(1, 5) == "wrap_"
		table.insert(Shop.Cosmetics, {
			id = r.cosmetic, slot = isWrap and "wrap" or "rims",
			name = (isWrap and "Prestige-Folierung " or "Prestige-Felgen ") .. r.rank,
			desc = (isWrap and "Lorbeer-Folierung" or "Felgen-Set") .. " für den Prestige-Rang " .. r.rank .. " („" .. r.title .. "“).",
			rewardOnly = true, rewardText = "Prestige-Rang " .. r.rank,
			style = isWrap and { pattern = "laurel", color = tier, color2 = { 28, 30, 34 } }
				or { color = tier, reflectance = 0.2 + 0.1 * math.min(3, math.floor((r.rank - 1) / 5)) },
		})
	end
end

-- Developer Products. productId 0 = Platzhalter (kein Prompt, Hinweis „noch nicht eingerichtet“).
-- Credits-Pakete zeigen auf die 2.4.0-Einträge (pack = C.CreditProducts[i], Referenz: productId/credits werden
-- dort gepflegt; Purchases verbucht sie weiter über Profiles.GrantCredits). Robux-Preise stehen bewusst nicht hier:
-- der Shop zeigt nur den echten Preis aus MarketplaceService:GetProductInfoAsync (sonst „Mit Robux“ ohne Zahl).
for _, p in ipairs(C.CreditProducts) do
	table.insert(Shop.Products, {
		key = p.key, kind = "credits", name = p.name, pack = p, productId = p.productId,
		desc = string.format("%s Credits%s.", tostring(p.credits), p.bonus > 0 and (" (+" .. p.bonus .. " % Bonus)") or ""),
		grants = { credits = p.credits },
	})
end
local PRODUCTS: { ShopProduct } = {
	-- DLC-Autos: gleiche Fahrwerte wie das Basismodell, dazu feste Optik und eine exklusive Folierung
	{ key = "car_komet_sunset", kind = "car", name = "Komet S2 Sunset", productId = 0,
		desc = "Der Komet S2 in Bernstein mit Goldfelgen, Unterbodenlicht und Sunset-Folierung. Fährt wie der Komet S2.",
		grants = { cars = { "dlc_komet_sunset" }, cosmetics = { "wrap_sunset" } } },
	{ key = "car_nord_nacht", kind = "car", name = "Nord R4 Nachtfalke", productId = 0,
		desc = "Der Nord R4 in Tiefschwarz mit Chromfelgen, violettem Licht und Nachtfalke-Folierung. Fährt wie der Nord R4.",
		grants = { cars = { "dlc_nord_nacht" }, cosmetics = { "wrap_nacht" } } },
	{ key = "car_vektor_blitz", kind = "car", name = "Vektor RS Blitz", productId = 0,
		desc = "Der Vektor RS in Eisblau mit weißen Felgen, blauem Licht und Blitz-Folierung. Fährt wie der Vektor RS.",
		grants = { cars = { "dlc_vektor_blitz" }, cosmetics = { "wrap_blitz" } } },
	-- Kosmetik (dieselben Teile gibt es für Credits)
	{ key = "cos_wrap_flammen", kind = "cosmetic", name = "Flammen-Folierung", productId = 0,
		desc = "Orange Flammen für jedes deiner Autos.", grants = { cosmetics = { "wrap_flammen" } }, creditsPrice = 2500 },
	{ key = "cos_rims_gold", kind = "cosmetic", name = "Goldfelgen", productId = 0,
		desc = "Glänzende Goldfelgen für jedes deiner Autos.", grants = { cosmetics = { "rims_gold" } }, creditsPrice = 1200 },
	{ key = "cos_horn_fanfare", kind = "cosmetic", name = "Fanfare", productId = 0,
		desc = "Fanfaren-Lichthupe für große Auftritte.", grants = { cosmetics = { "horn_fanfare" } }, creditsPrice = 1200 },
	{ key = "cos_trail_regenbogen", kind = "cosmetic", name = "Regenbogenspur", productId = 0,
		desc = "Bunte Reifenspur in allen Farben.", grants = { cosmetics = { "trail_regenbogen" } }, creditsPrice = 2000 },
	-- Bündel
	{ key = "bundle_starter", kind = "bundle", name = "Starter-Set", productId = 0,
		desc = "Rennstreifen, Goldfelgen, Melodie-Lichthupe und Blaue Spur in einem Paket.",
		grants = { cosmetics = { "wrap_streifen", "rims_gold", "horn_melodie", "trail_blau" } }, creditsPrice = 4500 },
}
for _, p in ipairs(PRODUCTS) do
	table.insert(Shop.Products, p)
end

-- Game Passes (rein kosmetisch; id 0 = Platzhalter). Die bestehenden Presse-Pässe (MiniPasses) bleiben.
Shop.Passes = {
	{ key = "neon", name = "Neon-Paket", id = 0,
		desc = "Neonfelgen, Neonspur und Laser-Lichthupe – alles, was nachts leuchtet.",
		grants = { cosmetics = { "rims_neon", "trail_neon", "horn_laser" } } },
	{ key = "deko", name = "Werkstatt-Deko", id = 0,
		desc = "Zielflagge, Blauchrom-Felgen und Regenbogenspur für den Deko-Look deiner Werkstattflotte.",
		grants = { cosmetics = { "wrap_karo", "rims_chrom_blau", "trail_regenbogen" } } },
}

Shop.Text = {
	notReady = "Dieser Kauf ist noch nicht eingerichtet. Alles gibt es auch für Credits oder als Belohnung!",
	unknown = "Diesen Artikel gibt es nicht.",
	owned = "Das hast du schon.",
	rewardOnly = "Das gibt es nur als Belohnung: %s.",
	level = "Dafür brauchst du Level %d.",
	money = "Nicht genug Credits.",
	garageFull = "Deine Garage ist voll (%d Autos).",
	bought = "Gekauft: %s!",
	boughtCar = "Dein neues Auto steht in der Garage: %s!",
	equipped = "Angelegt: %s.",
	unequipped = "%s abgelegt.",
	notOwned = "Das gehört dir noch nicht.",
	wrongSlot = "Das passt nicht in diesen Platz.",
	badSlot = "Unbekannter Platz.",
	receipt = "Danke für deinen Einkauf: %s!",
	receiptCar = "Danke! Dein neues Auto steht in der Garage: %s!",
	receiptDeferred = "Deine Garage ist voll (%d von %d Autos) – dein neues Auto „%s“ wird gutgeschrieben, sobald ein Platz frei ist. Verkaufe einfach ein Auto.",
	receiptWaiting = "Dein letzter Kauf von „%s“ wartet noch auf einen freien Garagenplatz.",
	receiptRefund = "Du hattest %s schon – dafür bekommst du %s Credits gutgeschrieben.",
	partlyOwned = "Du hast schon %d von %d Teilen dieses Pakets (%s). Kauf die fehlenden Teile einzeln für Credits.",
	promptPending = "Für diesen Artikel läuft gerade ein Robux-Kauf. Bitte warte kurz.",
	horn = "Lichthupe: Hol zuerst dein Auto und steig ein.",
	hint = "Alles im Shop gibt es auch für Credits oder als Belohnung – ganz ohne Robux.",
}

-- Nachschlagetabellen
Shop.CosmeticById = {} :: { [string]: Cosmetic }
Shop.CosmeticsBySlot = {} :: { [string]: { Cosmetic } }
Shop.SlotSet = {} :: { [string]: boolean }
for _, slot in ipairs(Shop.Slots) do
	Shop.SlotSet[slot] = true
	Shop.CosmeticsBySlot[slot] = {}
end
for _, c in ipairs(Shop.Cosmetics) do
	Shop.CosmeticById[c.id] = c
	if Shop.CosmeticsBySlot[c.slot] then
		table.insert(Shop.CosmeticsBySlot[c.slot], c)
	end
end
Shop.ProductByKey = {} :: { [string]: ShopProduct }
for _, p in ipairs(Shop.Products) do
	Shop.ProductByKey[p.key] = p
end
Shop.PassByKey = {} :: { [string]: ShopPass }
for _, p in ipairs(Shop.Passes) do
	Shop.PassByKey[p.key] = p
end
GameConfig.Shop = Shop

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

GameConfig.TutorialStepById = {} -- id -> Schritt (alle Wege)
GameConfig.TutorialStepIndex = {} -- id -> Nummer (1-basiert) im klassischen Weg (werkstatt)
GameConfig.TutorialStepIndexByPath = {} -- typ -> id -> Nummer
for i, s in ipairs(GameConfig.Tutorial.Steps) do
	GameConfig.TutorialStepById[s.id] = s
	GameConfig.TutorialStepIndex[s.id] = i
end
for typ, list in pairs(GameConfig.Tutorial.ByPath) do
	GameConfig.TutorialStepIndexByPath[typ] = {}
	for i, s in ipairs(list) do
		GameConfig.TutorialStepById[s.id] = s
		GameConfig.TutorialStepIndexByPath[typ][s.id] = i
	end
end
GameConfig.Tutorial.Count = #GameConfig.Tutorial.Steps

-- Entwickler-Menü (DevService/DevUI): Chat-Befehl „/dev“ oder Strg+Umschalt+D. Erlaubt nur in Roblox Studio, für den
-- Ersteller des Spiels (bei Gruppenspielen: den Gruppenbesitzer) und für die UserIds unten. Alle anderen merken nichts.
GameConfig.Dev = {
	-- Hier deine Roblox-UserId eintragen (Zahl, z. B. { 123456789 }), damit das Menü auch im veröffentlichten Spiel geht.
	-- Deine UserId steht in der Adresszeile deines Roblox-Profils (roblox.com/users/<UserId>/profile).
	AllowedUserIds = {},
	Command = "/dev", -- Chat-Befehl (TextChatCommand und Player.Chatted)
	MaxLevel = 1000, -- höchstes Level, das das Menü setzt (mindestens das höchste Freischalt-Level)
	MaxCredits = 1e9,
	MaxCash = 1e12, -- Tycoon-Bargeld des laufenden Durchlaufs
	MaxXP = 1e9, -- „XP setzen“: XP im aktuellen Level, Überschuss steigt wie gewohnt auf
	AddCredits = 10000, -- Knopf „+10.000 Credits“
	MaxUnlockCards = 5, -- mehr neue Freischaltungen auf einmal: eine Sammel-Meldung statt vieler Karten
	OpenCooldown = 0.5, -- Sekunden zwischen zwei Öffnen-Befehlen eines Spielers
}

-- Große Werkstatt (PublicWorkshopService/PublicWorkshopUI, Welt: City.Districts.Grosswerkstatt am Westende der
-- Spielermeile): eigene Autos reparieren (Zustand -> 100 %, Wertbonus beim Verkauf) und Altteile verkaufen.
-- Wirtschaft: Reparaturkosten immer unter dem Wertgewinn (CostShare/MinCostShare < 1), ein Auto nur einmal, Bonus
-- gedeckelt (MaxBonus), verkaufte Teile werden vor dem Bezahlen abgebucht, Tageslimit für den Teile-Ankauf.
GameConfig.PublicWorkshop = {
	Title = "Große Werkstatt",
	StationRepair = "grosswerkstatt", -- City.Stations.<key> an den Reparatur-Hallen
	StationParts = "teileankauf", -- City.Stations.<key> am Teile-Ankauf
	RepairRange = 60, -- Studs um die Station grosswerkstatt (Hallen + Vorplatz); während der Reparatur in der Nähe bleiben
	PartsRange = 14, -- Studs um die Station teileankauf (Prompt-Reichweite 10 + Spielraum)
	RangeSlack = 4,
	RepairSeconds = 8, -- Dauer einer Reparatur (Fortschritt im Panel)
	MaxBonus = 1.35, -- höchster Wertbonus beim Verkauf (×1,35)
	BonusPerMissing = 0.7, -- Bonus = (100 − Zustand) / 100 × 0,7 (gedeckelt durch MaxBonus)
	CondMin = 45, CondMax = 85, -- Anfangszustand eines Händlerautos (fest aus der Auto-Id)
	UsedCondMin = 30, UsedCondMax = 65, -- Anfangszustand eines Sondermodells (Auktion: Gebrauchtwagen)
	CostShare = 0.7, -- Reparaturkosten = Wertgewinn × 0,7 × Rabatte …
	MinCostShare = 0.5, -- … aber nie unter 50 % des Wertgewinns (kein Gewinn aus Kauf + Reparatur + Verkauf)
	MinGain = 40, -- kleinere Wertgewinne lohnen keine Reparatur
	StockDiscount = 0.2, -- −20 %, solange der Teile-Vorrat der Werkstatt (Server) Teile hat
	PartsPerRepair = 6, -- so viele Teile verbraucht eine Reparatur aus dem Vorrat
	StockStart = 24, -- Vorrat beim Serverstart
	StockCap = 400, -- Vorrat höchstens
	PathDiscount = { werkstatt = 0.1 }, -- Startweg Werkstatt: −10 % auf Reparaturen
	PathPartsBonus = { schrottplatz = 0.1 }, -- Startweg Schrottplatz: +10 % beim Teile-Ankauf
	Parts = { -- Ankauf (Schrotthändler: 16 Cr je Altteil)
		{ id = "altteile", name = "Altteile", price = 22, xp = 1 },
	},
	MaxSellCount = 50, -- Teile je Verkauf (Nutzlast count 1..50)
	DailyPartsLimit = 200, -- Teile je Spieler und Tag
	RepairXP = 20, -- XP je bezahlter Reparatur
	ExcludedModels = { flitzer = true }, -- Startauto (nicht verkäuflich) braucht keine Reparatur
}

---------------------------------------------------------------- Startauto „Flitzer“ / Auto rufen (3.x, Team Autos)
-- Fahrwerte des Flitzers stehen in CarCatalog.Starter; hier nur das Rufen (car_call, Taste G, Handy „Auto rufen“).
GameConfig.StarterCar = {
	Model = "flitzer", -- CarCatalog.StarterId
	CallCooldown = 5, -- Sekunden zwischen zwei car_call eines Spielers
	SearchRadius = 300, -- Studs: so weit sucht der Server die nächste Fahrbahn (City.Roads, Asphalt / CarRoad)
	RoadMargin = 5, -- Abstand der Wagenmitte zum Fahrbahnrand
	RoadCandidates = 8, -- so viele nächstgelegene Fahrbahnstücke werden geprüft
	SlideStep = 9, -- belegt (Laterne, Ampel, Auto): so weit entlang der Fahrbahn ausweichen
	IntroDelay = 2, -- Sekunden in der Open World nach der Startwahl, bis der Begrüßungs-Flitzer kommt
	IntroRetry = 5, -- erneuter Versuch, wenn gerade kein Platz frei war
	ClientSendGap = 1, -- Client: Taste G höchstens 1× pro Sekunde
	Text = {
		intro = "Dein Flitzer! Ruf ihn jederzeit mit dem Handy (P) → „Auto rufen“ oder Taste G",
		called = "%s ist da – gute Fahrt!",
		cooldown = "Dein Auto ist gleich wieder rufbar (noch %d s).",
		openWorld = "Auto rufen geht nur in der Open World.",
		track = "Während des Zeitfahrens kannst du kein Auto rufen.",
		testdrive = "Beende zuerst die Probefahrt.",
		arcade = "Beende zuerst deine Runde in der Spielhalle.",
		repair = "Warte, bis die Reparatur in der Großen Werkstatt fertig ist.",
		delivery = "Während einer Lieferfahrt bleibt dein Auto draußen – steig wieder ein!",
		seated = "Du sitzt schon in deinem Auto.",
		noCharacter = "Warte, bis deine Figur wieder da ist.",
		favourite = "Lieblingsauto: %s. Ruf es mit Taste G oder im Handy.",
		favouriteMissing = "Dein Lieblingsauto steht gerade nicht bereit – der Flitzer kommt.",
		nitro = "Der Flitzer hat kein Nitro – dafür ist er super wendig!",
		trackStarter = "Zeitfahren fährst du mit einem Auto aus dem Autohaus – der Flitzer fährt außer Konkurrenz.",
	},
}

return GameConfig
