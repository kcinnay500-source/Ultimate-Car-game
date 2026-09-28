# Plan 3.0 – Minispiel-Sammlung

Stand: umgesetzt, alle Phasen abgehakt. Grundlage ist **kein** vorhandenes 2.4.0-Projekt (siehe „Abweichungen“), sondern ein Neuaufbau nach dem Auftrag `MASTER_PROMPT_3.0.md` mit der HTML-App (`reference/Ultimate_Car_Game.html`) als inhaltlicher Vorlage.

## Fortschritt

- [x] Phase 1 – Grundlage: Profilfelder mit Migration, Remote-Aktionen, Menübereich „Minispiele“, Hof-Stationen, Zahlenformat (Tsd., Mio., Mrd., Bio., …)
- [x] Phase 2 – Schrottpresse: Klicks mit Combo, 100 Upgrades, Maschinen im Server-Tick, Offline-Ertrag, Schrotthändler, Rebirth, Bestenliste (Menü + Tafel)
- [x] Phase 3 – Idle Tuning Garage: Echtzeit-Projekte 5 Min. bis 8 Std., passive Einnahmen, Tuning-Stufe → Werkstatt
- [x] Phase 4 – Nebenspiele: Schrottplatz, Mechaniker-Quiz, Parkplatz-Chaos (und die Werkstatt als mittleres Hauptspiel)
- [x] Phase 5 – Ziele und Verzahnung: Meilensteine, Tagesauftrag, 3 Tagesziele, „Nächstes Ziel“, Boni-Übersicht, Game-Pass-Vorbereitung, Version 3.0.0
- [x] Nach jeder Phase: Build, Luau-Compiler, Tests grün; Selbst-Review

## Datenmodell

Das Profil liegt im DataStore `UltimateCarGame_v2`, Schlüssel `player_<UserId>`. Gemeinsame Karrierefelder stehen oben, alles Neue im Bereich `games`. Unbekannte Felder (z. B. aus einem 2.4.0-Profil) bleiben unverändert erhalten. `Rules.LoadData` normalisiert idempotent: `nil`, negative Werte, `NaN` und `inf` werden durch Standardwerte ersetzt oder gedeckelt.

| Feld | Standard | Bedeutung |
|---|---|---|
| `credits` | 800 | Credits (HTML „€“) |
| `level`, `xp` | 1, 0 | Karriere (HTML `xpNeeded`) |
| `games.parts` | 3 | Lager (Teile) |
| `games.reputation` | 0 | Ruf |
| `games.bays` / `offerSlots` / `toolLevel` / `tuningLevel` / `scrapyardLevel` | 1 / 3 / 1 / 1 / 1 | Ausbau (HTML `upgrades`) |
| `games.jobs`, `games.offers`, `games.nextId` | leer, leer, 1 | Werkstatt |
| `games.press.scrap` | 0 | Schrott-Guthaben |
| `games.press.runScrap` | 0 | Schrott im aktuellen Rebirth-Durchlauf |
| `games.press.lifetime` | 0 | Bestenlistenwert (nur Grundertrag, ohne Game Passes) |
| `games.press.clicks`, `upgrades`, `rebirths`, `lastTick`, `combo` | 0, {}, 0, 0, 1 | Presse |
| `games.tuning.projects`, `lastIdle`, `completed` | {}, 0, 0 | Tuning-Garage |
| `games.scrapyard.vehicle` | false | Fahrzeug bereit zum Zerlegen |
| `games.quiz.diagPoints` | 0 | Diagnosepunkte |
| `games.parking.streak`, `best`, `puzzle` | 0, 0, false | Parkplatz |
| `games.stats.*` | 0 | Zähler für Ziele |
| `games.milestones` | {} | abgeholte Meilensteine |
| `games.daily` | Tag "", nicht abgeholt | Tagesauftrag und Tagesziele (UTC) |
| `_lock` | – | Sitzungssperre `{ job, t }` |

## Remote-Aktionen

Ein `RemoteEvent` **Action** (Client → Server, Absicht + Nutzlast), **Sync** (Server → Client, Snapshot) und **Notice** (Server → Client, Hinweise). Alle Aktionen laufen durch `Actions.Handle`: Remote-Budget (Token-Bucket 25/s, Burst 40), Typprüfung gegen `Net.Actions`, Anfrage-ID gegen Wiederholungen, Handler ohne Yield zwischen Prüfung und Änderung.

`press_click {count}`, `press_buy {id, level}`, `press_exchange {index}`, `press_rebirth {rebirths}`, `workshop_accept {id}`, `workshop_finish {id}`, `upgrade_buy {key, level}`, `tuning_start {id}`, `tuning_collect {slot}`, `tuning_idle`, `scrapyard_buy`, `scrapyard_dismantle`, `scrapyard_sell`, `quiz_new`, `quiz_answer {token, choice}`, `parking_new`, `parking_tap {cell}`, `daily_claim`, `daily_goal_claim {id}`, `milestone_claim {id}`, `leaderboard_refresh`, `pass_prompt {pass}`, `ui_ready`.

Der Client sendet nie Beträge, Preise, Ergebnisse oder Zeitstempel. `level`/`rebirths` sind die vom Client gesehene Stufe: stimmt sie nicht mehr, wird die Anfrage still verworfen (Doppelklick-Schutz).

## Module

| Bereich | Shared (reine Formeln) | Server (Handler) | Client (UI) |
|---|---|---|---|
| Grundlage | `Config`, `Rules`, `Locale`, `Net`, `Catalog`, `Snapshot` | `Main.server`, `Core`, `Actions`, `Profiles`, `DataUtil`, `World` | `Main.client`, `UI`, `Remote`, `Effects`, `OverviewUI` |
| Schrottpresse | `PressRules` | `PressService`, `LeaderboardService`, `Purchases` | `PressUI`, `LeaderboardUI`, `ShopUI` |
| Tuning | `TuningRules` | `TuningService` | `TuningUI` |
| Werkstatt | `WorkshopRules` | `WorkshopService` | `WorkshopUI` |
| Nebenspiele | `SideGameRules` | `SideGamesService` | `ScrapyardUI`, `QuizUI`, `ParkingUI` |
| Ziele | `GoalRules` | `GoalsService` | `GoalsUI` |

## Formeln (Quelle: HTML-Funktion)

| Formel | Quelle | Umsetzung |
|---|---|---|
| Upgrade-Kosten `max(1, floor(Basis × 1,145^Stufe))`, Basis `round(8 × 1,19^i)` | `clickerCost` | `PressRules.UpgradeCost` |
| Globaler Multiplikator `1 + Stufen × 0,0025` | `clickerGlobalMultiplier` | `PressRules.GlobalMultiplier` |
| Klick `max(1, (5 + Klick-Boni) × global × Rebirth)` | `clickPowerTotal` | `PressRules.ClickPower` |
| Maschine `(1 + Effekt × 0,35) × global × Rebirth` | `autoPowerTotal` | `PressRules.MachinePower` |
| Combo +0,25 je Klick in 1,8 s, max. 25 | `clickCar` | `PressRules.ApplyClicks` |
| Querboni ×0,6 Werkstatt, ×0,8 Tuning | `clickerWorkshopMultiplier`, `clickerTuningMultiplier` | `PressRules.WorkshopMultiplier/TuningMultiplier` |
| Umtausch 4 : 1 mit 20 % Abschlag | `sellCarPoints` | `PressRules.ExchangeCredits` |
| Rebirth-Multiplikator +10 % je Rebirth | `prestigeApMultiplier` | `PressRules.RebirthMultiplier` |
| `idleRate = (10 + Stufe × 4 + Projekte^1,12 × 1,5) × Tuningbonus` je Minute, gedeckelt 8 Std. | `idleRate`, `pendingIdle` | `TuningRules.IdleRate/PendingIdle` |
| Werkstatt-Bonus `1 + (Tuning-Stufe − 1) × 0,045` | `workshopBonus` | `WorkshopRules.TuningWorkshopBonus` |
| Angebote, Stufen-Aufträge, Barkosten nach Teilen | `refreshOffers`, `acceptJob` | `WorkshopRules.RefreshOffers/Accept` |
| Reparaturtempo `(1 + (Werkzeug − 1) × 0,08) × (1 − Diagnose)` | `acceptJob` | `WorkshopRules.RepairSpeed` |
| Diagnose `min(0,35, Punkte × 0,015)` | `diagReduction` | `WorkshopRules.DiagReduction` |
| Kundenbonus `min(1,7, 1 + Serie × 0,03)` | `customerBonus` | `WorkshopRules.CustomerBonus` |
| Schrottplatz-Funde, seltene Teile, Verkauf 5 → 220 | `buyScrap`, `sellParts` | `SideGameRules.Dismantle/SellParts` |
| Parkplatz-Belohnung `120 + Serie × 15` | `tapSpot` | `SideGameRules.Tap` |
| Tagesauftrag 350 Cr, 3 Teile, 40 XP | `claimDaily` | `GoalRules.ClaimDaily` |
| Level-Kurve und Level-Bonus | `xpNeeded`, `gainXP` | `Rules.XpNeeded/GainXP` |
| Tuning-Projekt-Belohnung `60 × Minuten^1,2` (überproportional) | neu | `TuningRules.BaseReward` |
| Bestenlisten-Kodierung `floor(log10(1 + x) × 10^13)` | neu | `PressRules.EncodeScore/DecodeScore` |

## Umbenennung HTML → Spiel

| HTML | Spiel |
|---|---|
| Auto Clicker | Schrottpresse |
| Autopunkte (AP) | Schrott (kg) |
| Klick-Upgrades (Typ 0/3) | Werkzeuge (Brecheisen, Hydraulikschere, …) |
| Auto-Upgrades (Typ 1/4) | Maschinen und Mitarbeiter (Förderband, Magnetkran, Schredder, Praktikant, …) |
| Typ 2 (Ruf/Geld beim Kauf) | Händlerkontakte (Kleinanzeige, Abschleppdienst-Deal, …) |
| AP kaufen / verkaufen | nur Schrott → Credits am Schrotthändler |
| Prestige (Level 1000) | Rebirth der Schrottpresse |
| € | Credits (Cr) |
| Werkstatt Tycoon | Werkstatt (2D, siehe Abweichungen) |
| Tuning (tuneCar, idle) | Idle Tuning Garage |
| Schrottplatz | Schrottplatz (Kaufen + Zerlegen als zwei Schritte) |
| Diagnose-Quiz | Mechaniker-Quiz |
| Parken | Parkplatz-Chaos |
| Tagesbonus | Tagesauftrag + 3 Tagesziele |

## Testplan

| Phase | Datei | Inhalt |
|---|---|---|
| 1 | `tests/test_rules.lua` | Migration 2.4.0-Profil, idempotentes Laden, NaN/negativ/nil, Zahlenformat, XP, UTC-Tag, Katalog |
| 2 | `tests/test_press.lua` | Formeln, erstes Upgrade ≤ 15 s, Klick-Limit, gefälschte Werte, Doppelkauf, Server-Tick, Offline 1 h/24 h/negativ, Umtausch, Rebirth, Game Pass |
| 2 | `tests/test_leaderboard.lua` | Kodierung, Reihenfolge, eigene Platzierung, Drosselung, Fehlerfall |
| 3 | `tests/test_tuning.lua` | Start, Rejoin, Abholen, kein Doppelabholen, Uhr rückwärts, passive Einnahmen |
| 4 | `tests/test_sidegames.lua` | Schrottplatz, Quiz-Spam, Parkplatz-Prüfung, Deckel, Werkstatt, Ausbau |
| 5 | `tests/test_goals.lua` | Meilensteine einmalig, Tages-Reset UTC, Rejoin, „Nächstes Ziel“, Boni |
| Übergänge | `tests/test_transitions.lua` | Sitzungssperre, Verlassen beim Laden, Autosave-Rennen, Studio ohne DataStore, Herunterfahren, Verbindungen, Remote-Budget, Stationen |
| Mehrspieler | `tests/test_multiplayer.lua` | 2 Spieler getrennt, Bestenlistenwerte, 8 Spieler |
| Client | `tests/test_client.lua` | UI baut und rendert jeden Bereich, Tasten senden nur Absichten, 10.000 Klicks ohne Instanzflut, Touch ≥ 44 px, keine Asset-IDs |

## Abweichungen von Annahmen und Auftrag

1. **Kein 2.4.0-Projekt vorhanden.** In den Repositories gab es nur die HTML-App. Deshalb gibt es hier keine 3D-Werkstatt, keine 1.393 Bestandsprüfungen und keine vorhandenen Developer Products. Die Struktur (`src/`, `tools/build_place.py`, `tools/validate.py`, `tests/`, DataStore `UltimateCarGame_v2`, `Rules.LoadData`) ist nach dem Auftrag neu angelegt.
2. **A1:** Statt der fehlenden 3D-Werkstatt ist die HTML-Werkstatt als 2D-Spiel das mittellange Hauptspiel (Aufträge, Hebebühnen, Ausbau).
3. **Migration:** Getestet mit einem nachgebauten 2.4.0-Profil (Credits, Level, `days`, `equipmentBays`, Aufträge, Lager, Geräte). Alle neuen Felder liegen unter `games`, damit bestehende Felder nie überschrieben werden.
4. **HTML-Geldrinnsal der Presse** (Klick gibt 2,5 % in €) entfällt: Schrott ist nach A3 nur über den Schrotthändler in Credits tauschbar.
5. **Schrott aus dem Schrottplatz (A8)** landet im Guthaben, zählt aber nicht für die Bestenliste (A4: nur Klicks + Maschinen).
6. **Parkplatz-Chaos** bekommt eine echte Rätselregel (Weg freiräumen, sonst Blechschaden), weil die HTML-Mechanik ohne Regel keine Lösung zu prüfen hätte.
7. **Klick-Limit:** Token-Bucket mit 20 Klicks/s und 2 s Puffer, damit gebündelte Pakete bei Lag nicht verloren gehen. Über längere Zeit gilt exakt ≤ 20 × Zeit.
8. **Bestenliste, eigene Platzierung:** OrderedDataStore liefert keinen Rang. Der Server liest bis zu 5 Seiten (500 Einträge, einmal pro Minute) und zählt; darüber hinaus zeigt die UI „jenseits von 500“.
9. **Game-Pass-Regel für die Bestenliste:** Der Bestenlistenwert zählt Grundertrag × Upgrades × Rebirth × Combo, **ohne** Game-Pass-Multiplikatoren. Das Guthaben erhält den vollen Wert.
10. **Luau-Compiler:** Geprüft wird mit dem echten Luau-Compiler und -Interpreter (über `mlua`, `tools/luaurun`). Typanalyse (`luau-analyze`) ist nicht enthalten.
