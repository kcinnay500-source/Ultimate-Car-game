# Vertrag Ausbaustufe 4: Lobby, Tutorial, Level & Prestige, Schnelles Spiel (Tycoon), Open World, Story, Shop

Verbindlich für alle Teams dieser Stufe. Er baut auf `docs/MERGE_CONTRACT.md` (ein Eingang, ein Profil, keine neuen
Remotes) und `docs/PHASE2_CONTRACT.md` (Autos, Auktion, Spielhalle) auf. Alles, was dort steht, gilt weiter.

Entscheidungen des Auftraggebers (Chat, 2026-09-29):

1. Die bestehende Stadt („Werkstattmeile“) **ist** die Open World. „Schnelles Spiel“ ist ein eigener Place. Die
   2.4.0-Werkstatt am Grundstück ist das Gebäude „Werkstatt“ der Open World.
2. **Zwei Währungen**: Credits (persistent, überall) und **Bargeld** (nur innerhalb eines Tycoon-Durchlaufs).
3. **Prestige = Rang** ohne Level-Reset (Level, Credits, Autos bleiben). Die Freischaltkurve ist gestreckt: das
   letzte Auto (Nord Elys E9) erst ab **Level 90**, alle anderen Autos ebenfalls später als bisher.
4. **Nichts veröffentlichen.** Keine Place-IDs, keine Produkt-IDs. Platzhalter (0) und Studio-Simulation.
5. Story: **„Vom Kiesplatzhändler zum Mega-Verkäufer“** (Verkaufsgeschäft als roter Faden, Werkstatt-Legende als
   zweiter Strang).

## 1. Places und Studio-Simulation

| Datei | Inhalt | `PlaceKind` |
|---|---|---|
| `Ultimate_Car_Game.rbxlx` | **Alles in einem** (Lobby-Halle + Stadt + Tycoon-Gelände). Das ist die Datei für Roblox Studio. | `all` |
| `Ultimate_Car_Game_Lobby.rbxlx` | nur Lobby-Halle | `lobby` |
| `Ultimate_Car_Game_OpenWorld.rbxlx` | Stadt (wie bisher) | `openworld` |
| `Ultimate_Car_Game_Tycoon.rbxlx` | nur Tycoon-Gelände | `tycoon` |

- `python3 tools/build_place.py [--place all|lobby|openworld|tycoon] <out.rbxlx>`; ohne `--place` = `all`.
  Der Builder setzt das Attribut `PlaceKind` auf `ReplicatedStorage.GarageShared` und ruft
  `worldgen.apply(tree, new_referent, place)`. Alle Skripte sind in jedem Place enthalten (ein Code, Verhalten nach
  `PlaceKind`). `tools/validate.py` prüft weiterhin den `all`-Place; `tools/export_fixture.py` exportiert den
  `all`-Baum.
- Zonen im `all`-Place (kollisionsfrei zur Stadt, die X −450..450 / Z −320..320 belegt):
  **Lobby** `workspace.Lobby` bei Z −700 (Halle 120 × 80, Boden Y 0), **Tycoon** `workspace.Tycoon` ab Z +700
  (Gelände 8 Grundstücke à 70 × 70 in zwei Reihen, Mittelweg, Marktplatz für Handel).
- `GameConfig.Places = { lobby = 0, openworld = 0, tycoon = 0 }` (Place-IDs, Platzhalter 0).
- **PlaceRouter** (`src/mini/server/PlaceRouter.lua`): `PlaceRouter.Go(p, kind: "lobby"|"openworld"|"tycoon", data)`.
  Ist die Ziel-ID > 0, kein Studio und die Ziel-ID ≠ `game.PlaceId` → `TeleportService:TeleportAsync` (Singleplayer:
  vorher `ReserveServer`, Partys reisen gemeinsam) mit `TeleportData = { mode, single, party }`; alles andere (Studio,
  Platzhalter, Ziel im selben Place) → **Simulation**: Sitzung wechselt den Modus (`p.mode`), Figur wird per
  `ctx.moveTo`/`CityService.Travel`-Mechanik zur Zonen-Ankunft versetzt (`Lobby.Arrivals.hub`, `City.Arrivals.hub`,
  `Tycoon.Arrivals.hub`), Snapshot-Feld `mode` ändert sich. Der Client zeigt bei Simulation einen kurzen Hinweis
  „Studio-Simulation: Ortswechsel ohne Teleport“. Teleports laufen immer in `pcall`, Fehler → Simulation + Toast.
- Beim Beitritt: `PlaceKind == lobby` → Modus `lobby`; `openworld`/`tycoon` → dieser Modus; `all` → gespeicherter
  Modus `d.games.meta.lastMode`, beim allerersten Beitritt `lobby`. `Player:GetJoinData().TeleportData` (falls
  vorhanden, nur Strings/Zahlen/Booleans, geprüft) überschreibt Modus/Einstellungen für diese Sitzung.
- Singleplayer in der Simulation: nur Kennzeichnung (`p.single = true`), andere Spieler bleiben sichtbar.
- Grundstücke: In jedem Place legt `World.Create` wie bisher das Werkstatt-Grundstück an (auch in der Lobby, höchstens
  8 Spieler je Server wie überall). Das ist bewusst so, damit 2.4.0-Code unverändert läuft.

## 2. Daten (alles unter `d.games`, Hülle `{version=2,data,receipts,lock}` bleibt; `data.version` bleibt 2)

Jedes neue Modul liefert `Default()` und `Load(raw, d, now)` (idempotent, NaN/negativ → Standard, Whitelist der
Schlüssel, Tiefe ≤ 5). `MiniRules.DefaultGames/LoadGames` rufen sie auf. Nichts wird in `data` direkt angelegt.

```
d.games.meta     = { tutorialDone=bool, tutorialStep=int, tutorialSkipped=bool, tutorialRewarded=bool, beginner=bool,
                     passive=bool, single=bool, lastMode="lobby"|"openworld"|"tycoon", firstSeen=unix, playSeconds=int,
                     hintsSeen={ [hintId]=true } }   -- tutorialRewarded: Belohnung verbucht (Neustart am Kiosk ohne zweite)
d.games.prestige = { claimed={ [rank:int]=true }, titleRank=int }          -- Rang = PrestigeRules.RankFor(d.level)
d.games.tycoon   = { runsDone={ werkstatt=int, autohaus=int, produktion=int, schrottplatz=int },
                     rebirths=int,
                     run=false | { building=<typ>, stage=1..5, cash=number, upgrades={ [id]=int }, startedAt=unix,
                                   lastTick=unix, produced=number, rebirthBoost=number, storage={ [item]=int } } }
d.games.ow       = { buildings={ [typ]={ stage=int, built=int, readyAt=unix, collectedAt=unix, carAt=unix } },
                     passive=bool, lastPassiveAt=unix }   -- typ: autohaus|produktion|schrottplatz (werkstatt = d.bays, nicht gespeichert);
                                                          -- stage = gekaufte Stufe, built = fertig gebaute Stufe (stage > built: Baustelle bis readyAt);
                                                          -- passive spiegelt meta.passive (eine Quelle: meta)
d.games.story    = { chapter=int, step=int, done={ [missionId]=true },
                     side={ [missionId]={ n=int, day="YYYY-MM-DD", claimed=bool } },   -- Legende: day="legend"
                     active=false | { id=string, progress=number, startedAt=unix, party=int },
                     sales={ n=int, best=int, special=int, serial=int }, title=string }   -- chapter/step werden aus done neu bestimmt
d.games.shop     = { owned={ [itemId]=true }, equipped={ wrap=string|"", rims=string|"", horn=string|"", trail=string|"" },
                     dlcCars={ [modelId]=true } }
d.games.stats    -- bestehende Zähler + neue Schlüssel (MiniRules.STAT_KEYS): missionsDone, tycoonRuns, prestigeClaims
```

- Prestige-Rang wird **nicht** gespeichert, sondern immer aus dem Level berechnet; gespeichert sind nur die
  abgeholten Belohnungen (`claimed`).
- `tycoon.run` ist der gespeicherte Durchlauf (Fortsetzen nach Verlassen). `cash` ist **Bargeld**, nie Credits.
- Robux-Käufe (DLC-Autos, Kosmetik) landen wie die Credits in derselben Quittungs-Transaktion
  (`Profiles.GrantReceipt`, §8): erst wenn `receipts[purchaseId]` und Profil zusammen geschrieben sind, gilt der Kauf.

## 3. Zentrale Konfiguration und Freischaltungen

- **`src/mini/shared/GameConfig.lua`** ist die eine Stelle für alle neuen Zahlen: Places, Unlock-Tabelle,
  Prestige-Schwellen und -Belohnungen, Tycoon (Gebäudetypen, Stufen, Preise, Einkommen, Rundendauer-Ziel, Rebirth,
  Bonus-Tabelle), Open World (Gebäude, Bauzeiten, Passiv-Modus), Story (Kapitel, Missionen, Belohnungen),
  Shop (Produkte, Kosmetik, Game Passes), Tutorial-Schritte, Beginner-Hinweise. 2.4.0-Zahlen bleiben in
  `GarageShared.Config`, Minispiel-Zahlen in `MiniConfig`, Autos in `CarCatalog` (dort steht am Kopf ein Verweis).
  Balance-Änderungen anderer Teams gehen **nur** über diese Dateien, nie über Zahlen im Code.
- **Unlock-Tabelle** `GameConfig.Unlocks` = Liste `{ level=int, key=string, kind="feature"|"car"|"building"|"mode",
  title=string, hint=string }`, sortiert nach Level. `src/mini/shared/Unlocks.lua` liefert
  `Unlocks.Level(key)`, `Unlocks.Has(d, key)`, `Unlocks.NextFor(d)` (nächste Freischaltung für HUD/Beginner-Hinweis),
  `Unlocks.ListFor(d)` (für die Tabelle in der UI). **Autos**: `CarCatalog` nimmt das Händler-Level aus
  `Unlocks.Level("car:" .. id)` statt aus `C.Cars[].level` (das 2.4.0-Feld gilt weiter für Kundenautos der Werkstatt
  und bleibt unverändert).
- Freischaltkurve (Level): Schrottpresse 2, Schrottplatz 3, Quiz 4, Parkplatz 5, Tuning-Projekte 6, Tycoon-Modus 1
  (immer), Story Kapitel 2 ab 5, Kapitel 3 ab 15, Kapitel 4 ab 30, Kapitel 5 ab 50; Autohaus 3, Teststrecke 8,
  Waschstraße 8, Spielhalle 10, Auktionshaus 12, Spieler-Auktionen 20; OW-Gebäude Autohaus 10, Schrottplatz 18,
  Produktion 30 (wie Kapitel 4, das sie bauen lässt). Jede Story-Mission ist spätestens auf dem Level ihres Kapitels
  machbar (`StoryRules.UnlockCheck()`, Test). Autos beim Händler: Komet C1 3, Komet S2 8, Nord R4 14, Komet Urban 22, Nord Atlas Tourer 32,
  Vektor RS 45, Vektor GTX 58, Vektor Aureon V12 72, **Nord Elys E9 90**. Sondermodelle (NPC-Auktion): Rallye 10,
  Classic 18, Goldstück 50, Nero 78, Prototyp 95. Das Balance-Team darf Level verschieben, Elys bleibt 90.
- Level-Kurve: `R.XPNeeded` bleibt (2.4.0). Zielwerte für das Balance-Team: Level 50 nach ≈ 8 Std. gemischtem
  Spiel, Level 90 nach ≈ 25–35 Std. (Werkstatt + Missionen + Tycoon-Boni + Story-XP). Falls die Kurve dafür zu
  steil ist, wird **nur** in `GameConfig.XP` (Story-/Missions-XP, Tycoon-XP je Durchlauf) nachgeregelt, nie in
  `Rules.XPNeeded`.

## 4. Level & Prestige (`src/mini/shared/PrestigeRules.lua`, `src/mini/server/PrestigeService.lua`)

- Schwellen: Rang 1 ab Level 100, Rang 2 ab 250, Rang 3 ab 500, danach
  `Schwelle(n) = ceil(Schwelle(n−1) × 1,8 / 50) × 50` (900, 1.650, 2.950, …), Deckel Rang 20.
  `PrestigeRules.Threshold(n)`, `PrestigeRules.RankFor(level)`, `PrestigeRules.NextThreshold(level)`.
- **Kein Reset**: Level, XP, Credits, Autos, Gebäude, Story bleiben. Prestige ist ein Rang mit Titel und Abzeichen.
- Dauerhafte Belohnungen je Rang (in `GameConfig.Prestige.Rewards[n]`): Titel („Meisterschrauber I“ …), Credits-Bonus
  auf alle Einnahmen `+2 %` je Rang (Deckel +30 %, `CrossBonus.PrestigeIncome(d)`), eine Kosmetik (Folierung/Felgen)
  je Rang, Rabatt im Autohaus 1 % je Rang (Deckel 10 %), ab Rang 3 ein zusätzlicher Tycoon-Rebirth-Bonus +5 %.
  Belohnungen holt der Spieler mit `prestige_claim {rank}` einmalig ab (`claimed[rank]`).
- HUD zeigt Level, XP-Balken, Prestige-Rang und „Nächste Freischaltung: … (Level n)“.

## 5. Lobby (`LobbyService`, `LobbyUI`, Halle `workspace.Lobby`)

- Halle (worldgen `tools/worldgen/lobby.py`): Empfangshalle mit hoher Decke, zwei Portale **„Schnelles Spiel“** und
  **„Open World“** (Stationen `Lobby.Stations.mode_tycoon` / `mode_openworld`, Attribut `MiniTab="lobby"`,
  ProximityPrompt), **Einstellungs-Terminal** (`settings`), **Party-Tafel** (`party`), **Tutorial-Kiosk** (`tutorial`),
  Ankunft `Lobby.Arrivals.hub`, `Lobby.LobbySpawn` (SpawnLocation; im `all`-Place ist `City.CitySpawn` weiterhin da –
  der Server versetzt beim Beitritt nach Modus). Animierte Deko (Anim-Attribute wie in der Stadt: `neon`, `door`,
  `turntable` mit Showcar).
- Aktionen: `lobby_mode {mode}` (`"tycoon"|"openworld"`), `lobby_settings {single, passive, beginner}` (Booleans),
  `party_create`, `party_join {code}`, `party_leave`, `party_kick {userId}`, `lobby_go` (reist mit den gewählten
  Einstellungen; Party-Leiter nimmt Mitglieder mit), `lobby_return` (aus jedem Modus zurück in die Lobby).
- Party: serverlokal (`PartyService` im `LobbyService`), Code 4 Zeichen, max. 4 Mitglieder, Leiter startet die Reise;
  Party-Mitglieder erhalten `mini_notice { kind="party" }`. Story-Missionen laufen für alle Mitglieder mit
  (§7). Keine Party über Server-Grenzen hinweg (bewusst einfach).
- Einstellungen wirken sofort und werden in `d.games.meta` gespeichert: **Passiv-Modus** (`passive`): in der Open
  World nur Zuschauen/Handeln, keine Missionen/Story-Fortschritt, keine Auktionen; passive Einnahmen laufen weiter
  (Tuning-Projekte, OW-Gebäude). **Beginner-Modus** (`beginner`): Hinweise (§6) an, Tutorial-Erinnerung, einfachere
  Erklärtexte, mehr Zeit bei QTEs nicht (Server-Regeln bleiben gleich, kein Vorteil).

## 6. Tutorial, Beginner-Hinweise, Unlock-Anzeige (`TutorialRules`, `TutorialService`, `TutorialUI`)

- Pflicht beim ersten Beitritt in der Open World (`meta.tutorialDone == false`), jederzeit über **„Überspringen“**
  beendbar (`tutorial_skip`, setzt `tutorialSkipped=true, tutorialDone=true`). Schritte in `GameConfig.Tutorial.Steps`
  `{ id, text, target=<Stationsschlüssel|nil>, event=<Serverereignis> }`: Bewegen, Menü öffnen (M), zum Empfang,
  Auftrag annehmen, OBD, Reparatur, Abrechnen, Stadtplan, Autohaus ansehen, Ziele, Kiesplatz (Anschluss an die Story,
  Meilenstein 7: Station `kiesplatz`, Ereignis `tab:story`). Fortschritt bestätigt **der
  Server** aus echten Ereignissen (`OnSettled`, Stationsbesuch, Aktionen) – der Client sendet nur `tutorial_next` für
  reine Lese-Schritte („Weiter“). Belohnung am Ende: 500 Credits + 60 XP (`GameConfig.Tutorial.Reward`), einmalig
  (`meta.tutorialRewarded`). Das Tutorial läuft **nur in der Open World**: in Lobby und Schnellem Spiel ist
  `snapshot.tutorial.active = false`, `tutorial_next` wird mit Toast abgelehnt, Ereignisse zählen nicht. Neue
  Spieler mit laufendem Tutorial kommen aus der Lobby in ihrer **eigenen Werkstatt** an (nicht am Stadt-Hub).
  Verlangt der aktuelle Schritt eine Station mit Level-Sperre (Autohaus ab 3), öffnet der Tab trotzdem (nur
  ansehen; Kauf/Probefahrt bleiben gesperrt). **Tutorial-Kiosk** in der Lobby: `tutorial_restart` startet es nach
  Ende/Überspringen neu (Schritt 1, ohne zweite Belohnung); LobbyUI zeigt dafür den Abschnitt „Tutorial“.
- Beginner-Hinweise (`GameConfig.Hints`): `{ id, text, when="unlock:<key>"|"station:<key>"|"first:<stat>" }`, je
  einmal (`meta.hintsSeen`), nur bei `beginner=true`; Anzeige als Karte oben rechts (nicht als Toast, Toasts bleiben
  2.4.0). `first:<stat>` löst nur beim Übergang 0 → 1 aus; 2.4.0-Veteranen (Profil ohne `meta`, `d.completed > 0`)
  bekommen `first:jobsDone`/`station:workshop` als gesehen. Karten (Hinweis, „Neu freigeschaltet“) liegen unter dem
  tatsächlichen Abzeichen und unter der Toast-Zone und laufen als Warteschlange nacheinander (nie überschrieben).
- Unlock-Anzeige: Tab **„Freischaltungen“** (`unlocks`) mit der Tabelle Level → Freischaltung (erreicht/offen), plus
  HUD-Zeile „Nächste Freischaltung“. Beim Erreichen eines Levels mit Freischaltung: `mini_notice { kind="unlock" }`
  mit Titel (Client zeigt eine Karte mit Effekt).

## 7. Open World: Missionen, Story, Gebäude, Passiv-Modus (`OWRules`, `StoryRules`, `OWService`, `StoryService`, `StoryUI`, `BuildingsUI`, `MissionClient`)

- **Gebäude** (`GameConfig.OW.Buildings[typ]`, Stufen 1–4 mit Preis, Bauzeit, Wirkung):
  - `werkstatt` = 2.4.0-Grundstück (Stufe = Bühnenzahl `d.bays`; Kauf über den bestehenden Hallenanbau; hier nur
    angezeigt, kein zweiter Kaufweg).
  - `autohaus`: eigener Verkaufsstand/Autohaus auf dem Grundstück (Modelle `ServerStorage.OWBuildings.autohaus_1..4`,
    plot-lokal am Anker `Plot.OWAnchors.autohaus`, rotationssicher wie `moveTo`). Wirkung: passive Verkaufserlöse
    (Credits je Stunde, abholen), Rabatt beim Händler.
  - `schrottplatz`: eigener Schrottplatz (Anker `schrottplatz`): passiver Schrott (Presse) + Altteile.
  - `produktion`: Automobil-Produktion (Anker `produktion`): produziert alle n Stunden ein Bauteil-Paket / ab Stufe 4
    ein Auto-Gutschein (Kompaktwagen). Bauzeiten lang (Stufe 1: 10 Min., 2: 45 Min., 3: 3 Std., 4: 8 Std.), Preise
    in `GameConfig.OW`. Bauzeit läuft offline weiter (`readyAt`).
  - Aktionen: `ow_build {typ}` (Kauf/nächste Stufe, prüft Level (§3), Credits, laufenden Bau), `ow_collect {typ}`,
    `ow_passive {on}` (Passiv-Modus umschalten, auch ohne Lobby).
  - Der Ausbau-Fortschritt jedes Karriereweges gibt Vorteile in der Open World (Tabelle `GameConfig.OW.Perks`):
    Werkstatt-Stufe → Auftragswert, Autohaus → Rabatt/Verkaufserlös, Schrottplatz → Presse-Bonus,
    Produktion → Tuning-Geschwindigkeit. Alles gedeckelt (≤ +25 %).
- **Story** „Vom Kiesplatzhändler zum Mega-Verkäufer“ (`GameConfig.Story.Chapters`, 5 Kapitel à 3–5 Missionen):
  1. *Der Kiesplatz* (Level 1): Kiesplatz-Stand am Stadtrand (worldgen: `City.Districts.Kiesplatz`, Station `kiesplatz`,
     Ankunft `kiesplatz`): 3 Gebrauchtwagen an NPC-Kunden verkaufen (Dialog-Karten: Preis nennen, NPC feilscht;
     reine Serverlogik mit Seed und Server-Geheimnis), zurück in die Werkstatt (Tutorial-Anschluss), erste 2.500 Credits.
  2. *Die erste Werkstatt* (Level 5): 5 Aufträge abrechnen, Hebebühne 2, zehn Quizfragen (die Teststrecke kommt erst
     ab Level 8 und braucht ein eigenes Auto – darum liegt das Zeitfahren in Kapitel 3 nach dem Autokauf).
  3. *Das Autohaus* (Level 15): OW-Gebäude Autohaus bauen, ein Auto beim Händler kaufen, damit ein Zeitfahren bis ins
     Ziel fahren, ein Auto in die Auktion geben (ab Level 20) oder eine NPC-Auktion gewinnen.
  4. *Die Produktion* (Level 30): Schrottplatz + Produktion bauen, 3 Sondermodell-Verkäufe (NPC-Kunden am
     Kiesplatz mit Preisstufen).
  5. *Der Mega-Verkäufer* (Level 50): Produktion Stufe 4, 10 Verkäufe mit Bestpreis, einen Traumwagen
     besitzen (Vektor RS Goldstück ab 50, Vektor GTX ab 58 – oder später Aureon/Elys; die Mission nennt die Level) → Titel „Mega-Verkäufer“, Kosmetik, 25.000 Credits. Zweiter Strang „Werkstatt-Legende“ als
     Nebenmissionen (100 Aufträge, alle Geräte, 4 Bühnen).
  - Missionen: `story_start {id}`, `story_claim {id}`; Fortschritt zählt der Server über Statistiken
    (`MiniRules.STAT_KEYS`, `GoalsService`-Mechanik) und Ereignisse (Verkauf am Kiesplatz `story_sell {offer, price}`
    – `price` ist eine gewählte Preisstufe 1..3, kein Betrag).
  - **Nebenmissionen** (`GameConfig.Story.Side`): täglich 3 aus dem Pool (Lieferung: Auto von A nach B fahren
    (Checkpoint-Berührung), Zeitfahren unter Zielzeit, 3 Automaten spielen, 5 Fahrzeuge zerlegen …), Belohnung
    Credits + XP, Tageslimit.
  - **Co-op**: Story-Missionen laufen für Party-Mitglieder gemeinsam: Fortschritt eines Mitglieds zählt für alle
    Mitglieder im selben Kapitel/Mission (Server prüft Party-Zugehörigkeit im Moment des Ereignisses). Belohnung holt
    jeder einzeln ab. Solo funktioniert identisch ohne Party.
- **Passiv-Modus** (§5): `MiniService.Handle` blockt in Passiv `story_start`, `story_sell`, `mini_auction_bid` und
  `mini_auction_consign` zentral (`PASSIVE_BLOCKED`, Rückgabe `"passive"`, gedrosselter Hinweis `GameConfig.OW.PassiveHint`
  über `OWService.BlockIfPassive`); Abholen (`story_claim`, `side_claim`, `ow_collect`) bleibt erlaubt, Ereignisse zählen
  nicht (`StoryService`), Co-op überträgt nichts an Passive. Quelle ist `meta.passive` (`lobby_settings` und `ow_passive`).
- **Ereignisse** für Story-/Nebenmissionen: Statistiken über `MiniRules.StatHook` (jede `AddStat`-Erhöhung erreicht
  `StoryService.OnStat`), Ereignisse aus Hinweisen der Dienste (`car_bought`, `track_finish`, `auction_won`,
  `arcade_result` → `arcade_round`, `ow_build` → `ow_built:<typ>`) in `MiniService.notice`, `api.event(ms, event, data)` für
  Dienste (`auction_consigned`), `settle` aus `Mini.OnSettled`, `action:<name>` nach jeder gelungenen Aktion.
- Beschränkungen: Missions-Belohnungen ≤ 40 % der Werkstatt-Einnahme/Minute des Levels (Balance-Team).

## 8. Schnelles Spiel (Tycoon) (`TycoonRules`, `TycoonService`, `TycoonUI`, Gelände `workspace.Tycoon`)

- 8 Grundstücke (`GameConfig.Tycoon.Slots`, x/z/rot wie `C.PlotSlots`), Vergabe wie `World` (erster freier Slot,
  serverlokal `TycoonService.Plots`), Schild mit Spielername, offenes Gelände (jeder darf jedes Grundstück betreten;
  Kaufknöpfe reagieren nur auf den Besitzer).
- Rundenstart am eigenen Grundstück: **Gebäudetyp wählen** (`tycoon_choose {building}`: `werkstatt`, `autohaus`,
  `produktion`, `schrottplatz`), sofort Stufe 1. Läuft schon ein Durchlauf (`d.games.tycoon.run`), wird er
  fortgesetzt (Modelle nach `stage`/`upgrades` wieder aufgebaut).
- Klassische Tycoon-Mechanik: **Kaufpads** auf dem Grundstück (Part mit Attribut `TycoonButton=<upgradeId>`,
  Touched vom Besitzer → `TycoonService.Buy`), Produzenten („Dropper“) erzeugen **Bargeld** in einen Sammelbehälter,
  Sammeln per Pad/Knopf (`tycoon_collect`), Upgrades (`GameConfig.Tycoon.Upgrades[typ]`, je Stufe 4–6 Upgrades:
  Produzent, Tempo, Lager, Deko; Kosten wachsen), **Stufe 2–5** über das Stufen-Pad (`tycoon_stage`), Modelle
  `ServerStorage.TycoonTemplates.<typ>.Stage_1..5` (worldgen `tools/worldgen/tycoon.py`, jede Stufe sichtbar größer:
  Halle, Anbau, Schild, Deko, Licht). Zielzeit **≈ 5 Std. aktiv bis Stufe 5 komplett** (Balance-Team, Simulation in
  `tools/economy_sim.py --tycoon`).
- Alle Gewinne im Server-Tick (0,5 s) aus `lastTick`; Offline zählt nicht (Schnelles Spiel ist aktiv). `cash` Deckel
  `C.NumberCap`.
- **Handel Spieler ↔ Spieler** (nur im Tycoon, nur Bargeld): `tycoon_trade_offer {to, item, qty, price}` (item aus
  `GameConfig.Tycoon.Items`, `qty` 1..999, `price` = gewählter Preis in Bargeld = Absicht; Server prüft Lager und
  Bargeld), `tycoon_trade_accept {id}`, `tycoon_trade_cancel {id}`; Angebot 120 s gültig; Übergabe in einem
  Server-Schritt; Handel nie mit Credits. Marktplatz-Tafel in der Mitte zeigt offene Angebote (`mini_notice
  { kind="tycoon_market" }`).
- **Rebirth** (`tycoon_rebirth`): erst ab Stufe 5 komplett; setzt `run` zurück, `rebirths + 1`, Boost
  `+15 %` Einkommen je Rebirth (Deckel +150 %). Zählt als abgeschlossener Durchlauf (`runsDone[typ] + 1`).
- **Bonus-Tabelle Open World** (`GameConfig.Tycoon.Bonus[typ]`): je abgeschlossenem Durchlauf des Typs
  (Deckel 5 Durchläufe je Typ, danach zählt nichts mehr; Formel `min(n,5) × Schritt`):
  werkstatt → +2 % Werkstatt-Vergütung (max +10 %), autohaus → −1,5 % Händlerpreise (max −7,5 %),
  produktion → +3 % Tuning-Tempo (max +15 %), schrottplatz → +3 % Schrott (max +15 %). Wirkt über `CrossBonus`
  (`CrossBonus.TycoonWorkshop(d)` usw.). Der Deckel ×1,6 (`GameConfig.WorkshopRewardCap`) gilt **nur** für den
  Ausbaustufe-4-Faktor Tycoon × OW-Perk (`CrossBonus.CareerCapped`); die 3.x-Querboni (Presse, Tuning-Abteilung,
  Kundenbonus) bleiben ungedeckelt (bestehende Profile verlieren nichts), und der Prestige-Einnahmenbonus (§4)
  wird außerhalb des Deckels multipliziert, damit jeder Rang messbar wirkt. `CrossBonus.WorkshopReward` =
  Presse × Tuning × Kunde × CareerCapped × PrestigeIncome. Auf Minispiel-Einnahmen (Tuning, Presse-Händler,
  Schrottplatz, Quiz, Parkplatz, Teststrecke, Spielhalle) wirkt Prestige über `MiniRules.AddIncome`; der
  Händler-Rabatt über `CarRules.DealerPrice` (Katalog `price` = rabattiert, `basePrice` = Listenpreis).
- Speichern: `run` bei jedem Autosave; Verlassen → `run` bleibt (Fortsetzen). Abbruch: `tycoon_abandon` (Bestätigung).

## 9. Shop & Monetarisierung (`ShopRules`, `ShopService`, `ShopUI`-Erweiterung, `Purchases`)

- **Developer Products** (`GameConfig.Shop.Products`): Credits-Pakete (bestehend, `C.CreditProducts`), **DLC-Autos**
  (`kind="car"`, eigene Modell-IDs `dlc_*` in `CarCatalog.Dlc`, Karosserie aus bestehenden Vorlagen mit eigenem
  Lack/Felgen-Set, **gleiche Fahrwerte wie ein Auto derselben Klasse** – kein Pay-to-win), **Kosmetik** (`kind="cosmetic"`:
  Folierungen/Wraps (prozedurale Streifen/Muster aus Parts, keine Decal-Assets), Felgen-Sets, Hupen-Text/Lichtfarbe,
  Reifenspur-Farbe). **Game Passes** (`GameConfig.Shop.Passes`): rein kosmetische Pakete („Neon-Paket“,
  „Werkstatt-Deko“); die bestehenden Presse-Pässe bleiben.
- Alles ist auch **ohne Robux** erreichbar: jede Kosmetik hat einen Credits-Preis **oder** ist Belohnung
  (Prestige, Story, Tycoon). DLC-Autos sind mit Credits ab dem passenden Level ebenfalls kaufbar (höherer
  Credits-Preis, gleiche Werte). IDs sind Platzhalter (0) → Kauf zeigt „noch nicht eingerichtet“.
- **Keine bezahlten Zufallsboxen**, keine Wahrscheinlichkeiten nötig, keine Handel-für-Robux-Wege, keine
  Glücksspielmechanik. Texte für junges Publikum.
- Server: `Purchases.lua` bekommt neben Credits eine allgemeine Quittungs-Gutschrift
  `Profiles.GrantReceipt(profile, purchaseId, apply)` (Schnappschuss ändern, mit Quittung atomar schreiben, gleiches
  Wiederholungs-/`transacting`-Verhalten wie `GrantCredits`). `ProcessReceipt` bleibt allein in `Purchases`.
  `ShopService` liefert `Apply(product, snapshot)` (fügt DLC-Auto/Kosmetik ein) und die Credits-Käufe
  (`shop_buy {item}`), `shop_equip {slot, item}`, `shop_prompt {product}` (Client-Prompt läuft über den bestehenden
  Weg `purchasePrompt`).
- Kosmetik-Anwendung: `VehicleFactory.ApplyCosmetics(model, car, shop)` (Wrap-Parts, Felgen-Farben, Lichtfarbe).
- **Stand nach Meilenstein 8** (Schnittstellen wie umgesetzt): `Profiles.GrantReceipt(profile, purchaseId, apply, commit?)`
  – `apply(snapshot) -> true/false` läuft auf einer Kopie (false → nichts geschrieben, `NotProcessedYet`); nach dem
  atomaren Schreiben überträgt `commit(profile.data, stored)` (Standard: `apply` erneut auf dem Live-Profil) die
  Änderung. `ShopService.Apply(product, snapshot, now)` = `ShopRules.ApplyReceipt(snapshot, product, now)`;
  `ShopRules.Grant(d, grants, now)` (idempotent; Prestige/Story/Pässe nutzen es für Belohnungs-Kosmetik).
  `GarageServer` meldet jede Quittung mit `Purchases.FX(product)` und `Mini.OnGranted(p, product)` (Toast,
  `mini_notice {kind="shop", event="receipt"}`, Optik). Snapshot: `shop {owned[], equipped{}, dlcCars[], passes{},
  catalog (nur full, sticky)}`. DLC-Modelle (`CarCatalog.Dlc`, `dlc=true`, `base=<Modell>`) haben keinen eigenen
  Unlock-Eintrag: Freischaltung über `car:<basis>`. `CarService` wendet `ApplyCosmetics` nach Bau/Umstylen an und
  setzt `ShopService.Restyle` (stehende Autos nach `shop_equip`/Kauf/Quittung/Pass ohne Neubau). Das Credit-Center
  öffnet den Tab `shop`; der 2.4.0-Credits-Shop bleibt als Tablet-Seite erreichbar.

## 10. Aktionen (Zusammenfassung; alle flach, ≤ 10 Felder, Beträge sind nie Client-Werte außer den markierten Absichten)

```
lobby_mode {mode}  lobby_settings {single,passive,beginner}  lobby_go  lobby_return
party_create  party_join {code}  party_leave  party_kick {userId}
tutorial_next {step}  tutorial_skip  tutorial_restart
prestige_claim {rank}
ow_build {typ}  ow_collect {typ}  ow_passive {on}
story_start {id}  story_claim {id}  story_sell {offer, price}      -- price = Stufe 1..3 (Absicht)
side_claim {id}
tycoon_choose {building}  tycoon_collect  tycoon_buy {id}  tycoon_stage  tycoon_rebirth  tycoon_abandon
tycoon_trade_offer {to, item, qty, price}  tycoon_trade_accept {id}  tycoon_trade_cancel {id}   -- qty/price = Absicht (Bargeld)
shop_buy {item}  shop_equip {slot, item}  shop_prompt {product}
unlocks_seen
```

Events: `mini_notice` mit `kind` ∈ { `mode`, `party`, `tutorial`, `unlock`, `prestige`, `story`, `mission`,
`ow_ready`, `tycoon_market`, `tycoon_stage`, `trade`, `shop` }. Snapshot-Felder (§11).

Neue Tabs: `lobby`, `unlocks`, `story` (Missionen + Nebenmissionen), `tycoon`, `buildings` (OW-Gebäude), `prestige`;
`shop` wird erweitert (Credits, Autos, Kosmetik, Pässe).

## 11. Snapshot-Felder (zusätzlich zu MiniSnapshot)

`mode`, `placeKind`, `meta {beginner, passive, single, tutorialDone, tutorialStep}`, `party {code, leader, members[]}`,
`prestige {rank, next, claimable[], claimed[]}`, `unlocks {next, list[] (nur bei full)}`,
`tutorial {step, text, target, done}`, `story {chapter, active, missions[], side[]}`, `ow {buildings{}, passive}`,
`tycoon {run, slot, offers[], bonus{}}`, `shop {owned[], equipped{}, dlcCars[], passes{}, catalog{} (full)}`.
Sticky (nur bei full): `unlocks.list`, `shop.catalog`, `story.missions`.

## 12. Sicherheit und Regeln

- Server-Autorität für Geld, Bargeld, XP, Level, Käufe, Missionen; Client sendet Absichten. Alle neuen Aktionen laufen
  über `MiniService` (Budget, Abklingzeit, `transacting`-Sperre, Duplikate über `rid`).
- Unlock-Prüfung im Server für jede Aktion, die etwas Freischaltbares nutzt (`Unlocks.Has`).
- Party/Handel/Missionen prüfen bei jeder Übergabe erneut (Mitglied noch da, Angebot gültig, Lager reicht).
- DataStore: unverändert `UltimateCarGame_v2`, Sitzungssperre, Autosave 45 s, Versionierung über `d.games.v` und
  `Load`-Whitelists (alte Profile laden mit Standardwerten). Studio schreibt nie in Produktion.
- TeleportService nur in `pcall`; `TeleportData` als unvertrauenswürdig behandeln (Whitelist, Typen, Längen).
  `TeleportService.TeleportInitFailed` ist verbunden (`PlaceRouter.Init`): asynchrone Fehler → warn + Toast +
  Simulation je Spieler; kommt die Reise nicht zustande, zeigt `meta.lastMode` wieder auf den aktuellen Modus.
- Unlock-Sperren decken alle Aktionen eines Bereichs: Presse (Klick, Maschinen, Händler, Rebirth, keine Produktion
  vor Level 2), Tuning (Start, Abholen, passive Einnahmen – vor Level 6 wird nichts angespart), Ausbau
  (`mini_upgrade` je Bereich), Gebote auf **Spieler-Lose** erst mit `auction:player` (NPC-Lose ab `feature:auction`).
- `lobby_return` ist auch für Party-Mitglieder erlaubt (allein zurück, Party bleibt); nur `lobby_go` ist Leitersache.
- Alle Texte Deutsch, junges Publikum, keine externen Assets (`rbxassetid`), keine Glücksspielmechanik.
- Neue Luau-Dateien mit Typannotationen an Funktionssignaturen (keine `--!strict`-Pflicht, aber `--!nonstrict` ok),
  ModuleScripts, Kommentare Deutsch.

## 13. Tests

- Jedes neue Regelmodul: reiner Test (Default/Load idempotent, NaN, Grenzen). Jeder neue Dienst: Test im echten
  Server (`H.Garage`), inkl. Speichern/Laden, zwei Spieler, Verlassen mitten im Vorgang.
- End-to-End: Lobby → Einstellungen → Reise (Simulation) → Tutorial bis Ende → Story Kapitel 1 → Tycoon-Runde
  (Zeitraffer über `g:Advance`) → Rebirth → Bonus wirkt in der Werkstatt → Shop-Kauf mit Quittung.
- `tools/validate.py` bleibt bei 0 Fehlern/0 Warnungen; `tools/economy_sim.py --check` erweitert um Tycoon-Rundendauer,
  Level-90-Zeit, Missions-Anteil.
- `STUDIO_TESTS.md` bekommt eine Prüfliste je neuem System (Milestone 9).
