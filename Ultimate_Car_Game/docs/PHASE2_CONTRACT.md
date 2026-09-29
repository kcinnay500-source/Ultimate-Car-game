# Vertrag Ausbaustufen 2 und 3: Autos, Fahren, Tuning, Auktionshaus, Spielhalle, Teststrecke, Credit-Center

Ergänzt `docs/MERGE_CONTRACT.md` (gilt weiter: ein Profil, ein Eingang über `request()`, Serverautorität, keine Asset-IDs, deutsche Texte, 2.4.0 bleibt funktionsfähig). Stadt: `docs/CITY_SPEC.md`, Stationen in `tools/worldgen/contract.py`.

## 1. Ziele

- **Autohaus:** Autos kaufen (Katalog = die 9 Karosserien der 2.4.0-`CarTemplates`, Modelle aus `C.Cars`), Probefahrt (60 s, Teststrecke), „Meine Autos“ (Garage-Liste, Auto holen/abstellen).
- **Fahren:** eigene Autos als echte Roblox-Fahrzeuge (VehicleSeat, Radaufhängung, Antrieb, Lenkung), gebaut aus dem Template-Modell, Netzwerk-Besitz beim Fahrer, nur der Besitzer darf fahren. Tacho-HUD. Auf Handy mit Standard-Steuerung fahrbar.
- **Eigenes Tuning (Tuning-Zentrum):** Leistung (Motor, Getriebe, Reifen/Grip, Fahrwerk, Nitro) in Stufen, Optik (Lackfarbe, Felgenfarbe, Unterbodenlicht, Spoiler an/aus). Wirkt sofort auf das gefahrene Auto.
- **Teststrecke:** Zeitfahren mit Checkpoints, serverseitig gemessen, Belohnung nach Bestzeit-Verbesserung, gedeckelt.
- **Auktionshaus:** NPC-Versteigerungen seltener Sondermodelle (serverweit, regelmäßig) + Spieler-Auktionen eigener Autos an Spieler auf demselben Server.
- **Spielhalle:** 8 Automaten mit Geschicklichkeitsspielen (siehe `ARCADE_GAMES`), Credits nur nach Leistung, kein Einsatz, kein Zufallsgewinn, Tageslimit.
- **Credit-Center:** öffnet den 2.4.0-Credits-Shop (Robux, `C.CreditProducts`) und die Game Passes.
- **Waschstraße:** kosmetisch (Glanz-Effekt fürs aktive Auto, kleiner Preis).
- **Balance:** Werkstatt bleibt Haupteinnahme (siehe §7).

## 2. Daten (`d.games`, whitelist in `MiniRules.LoadGames`, Tiefe ≤ 5)

```
d.games.cars      = { {id=<int>, model=<C.Cars id>, paint=<int palette>, rims=<int>, glow=<int 0=aus>, spoiler=<bool>,
                       engine=0..5, gearbox=0..5, tires=0..5, suspension=0..5, nitro=0..3, bought=<unix>, locked=<bool Auktion>} , ... }  -- max 20
d.games.carSerial = <int>
d.games.activeCar = <int id oder 0>
d.games.track     = { best=<Sekunden oder 0>, rewardedBest=<Sekunden oder 0>, runs=<int> }
d.games.arcade    = { day=<"YYYY-MM-DD">, earned=<Cr heute>, best={ [gameKey]=<score> } }
d.games.auction   = { won=<int>, sold=<int>, partners={ {u=<userId>, at=<unix>} } (≤ 20, 24 h), received={ <tid> } (≤ 20) }
```

- Jedes Modul liefert `Default()` und `Load(raw, d, now)` (normalisiert, idempotent, NaN/negativ → Standard, unbekannte Modell-IDs verworfen). `MiniRules.DefaultGames/LoadGames` rufen sie auf.
- Autos ändern sich nur serverseitig. `locked=true` = in einer Spieler-Auktion; gesperrte Autos können nicht gespawnt, getunt oder erneut eingeliefert werden.

## 3. Module (neue Dateien, jeweils ein Besitzer)

| Datei | Inhalt |
|---|---|
| `src/mini/shared/CarCatalog.lua` | Katalog (Modell-ID, Name, Karosserie, Preis, Level, Grundwerte: Leistung, Höchstgeschwindigkeit, Grip, Gewicht), Tuning-Stufen und Preise, Farbpaletten (Lack 12, Felgen 8, Unterboden 6), Sondermodelle für NPC-Auktionen |
| `src/mini/shared/CarRules.lua` | `Default/Load`, `Buy`, `Stats(car)` (effektive Fahrwerte aus Grundwerten + Tuning), `Tune`, `Paint`, `SetActive`, `CanSpawn`, `Sell` (Rückkauf 50 % durch Händler, optional) |
| `src/mini/shared/TrackRules.lua` | Checkpoint-Reihenfolge, gültige Rundenzeit (Mindestzeit gegen Teleport), Belohnung |
| `src/mini/shared/AuctionRules.lua` | Lot-Zustände, Mindestgebot/Schritt, Gebotsprüfung, Abrechnung (Gebühr 5 %) als reine Funktionen |
| `src/mini/shared/ArcadeRules.lua` | je Spiel: Rundenparameter aus Seed, Bewertung aus Server-Zeitstempeln, Belohnung, Tageslimit |
| `src/mini/server/VehicleFactory.lua` | Baut aus `ServerStorage.CarTemplates.<body>` ein fahrbares Modell: Chassis-Part (unsichtbar, Masse), alle Karosserieteile per WeldConstraint + `Massless`, Räder als eigene Parts mit `CylindricalConstraint` (Federung + Motor) bzw. Hinge + Servo-Lenkung, `VehicleSeat` auf dem Fahrersitz, Werte aus `CarRules.Stats`. Farben/Optik anwenden. Keine Asset-IDs. |
| `src/mini/server/CarService.lua` | Aktionen §4 (Autos), Spawn an Spawnpunkten (`City.CarSpawns.<key>` bzw. Plot-Parkplatz), Despawn beim Verlassen/Tod/erneutem Holen, `SetNetworkOwner(owner)`, Sitzschutz (fremde Insassen werden sofort entfernt), Probefahrt-Timer, Zeitfahren-Checkpoints (Touched + Serverzeit), Waschstraße |
| `src/mini/server/AuctionService.lua` | NPC-Auktionszeitplan, Spieler-Auktionen, Abrechnung, Aktionen §4 (Auktion), Push an alle Spieler des Servers |
| `src/mini/server/ArcadeService.lua` | Runden starten/auswerten, Aktionen §4 (Spielhalle) |
| `src/mini/client/DealerUI.lua` | Tab `dealer`: Katalog mit 3D-Vorschau (ViewportFrame aus `GarageShared.PreviewCars`), Kaufen, Probefahrt, „Meine Autos“ (holen/abstellen/verkaufen) |
| `src/mini/client/CarTuningUI.lua` | Unterseite im Tab `tuning` („Mein Auto tunen“) |
| `src/mini/client/DriveClient.lua` | Tacho-HUD beim Fahren (km/h, Gang-Anzeige, Nitro-Taste N / Handy-Knopf) unter der 2.4.0-Fortschrittsleiste, weicht dem 2.4.0-Tablet; Zeitfahren-Anzeige; „Auto aufrichten“ (R / Handy-Knopf, wenn das Auto umgekippt liegen bleibt); Fahrwerte (Torque …) jedes Frame aus den Modell-Attributen; Kamera bleibt Roblox-Standard |
| `src/mini/server/AuctionLedger.lua` | Auktionsbuch: Übergaben je Spieler (DataStore), Abgleich beim Laden (`Mini.Reconcile`) |
| `src/mini/client/TrackUI.lua` | Tab `track`: Bestzeit, Start des Zeitfahrens |
| `src/mini/client/AuctionUI.lua` | Tab `auction`: laufende NPC-Auktion, Spieler-Auktionen, Bieten, Einliefern |
| `src/mini/client/ArcadeUI.lua` | Tab `arcade`: Automatenauswahl + die Spieloberflächen |
| `tools/worldgen/…` | `City.CarSpawns.<key>` (dealer, testdrive, track, carwash, und je Plot ein Spawn-Punkt über die Plot-Vorlage: Part `CarSpawn` im Werkstatt-Parkplatz), `City.Track.Checkpoints.CP1..CPn` (unsichtbar, CanCollide false, CanTouch true), Start/Ziel; Auktions-Bildschirm-SurfaceGui (`AuctionScreen` mit Labels `Title`, `Lot`, `Bid`, `Time`), Spielhallen-Bildschirme; `Soon`-Attribut der Stationen entfernen |

Verkabelung (Integrator): `MiniNet.Actions`, `MiniNet.Events`, `MiniService` (Register der neuen Dienste, OnJoin/OnLeave/Tick-Weiterleitung), `MiniSnapshot` (Felder §5), `MiniClient`/`MiniUI` (Tabs `dealer`, `track`, `auction`, `arcade`, `carwash`), `MiniRules.DefaultGames/LoadGames`, Credit-Center → 2.4.0-Shopseite.

## 4. Aktionen (flach, ≤ 10 Felder, optional `rid`)

Autos: `mini_car_buy {model}`, `mini_car_sell {id}`, `mini_car_spawn {id, at}` (`at` = Spawn-Key oder `"workshop"`), `mini_car_despawn`, `mini_car_testdrive {model}`, `mini_car_tune {id, part, level}` (part = engine|gearbox|tires|suspension|nitro; `level` = gesehene Stufe), `mini_car_style {id, paint, rims, glow, spoiler}`, `mini_car_nitro`, `mini_carwash`.
Teststrecke: `mini_track_start`, (Checkpoints serverseitig über Berührung).
Auktion: `mini_auction_bid {lot, amount}` (Betrag ist ein Gebot = Absicht; Server prüft gegen Mindestgebot und Guthaben), `mini_auction_consign {id, start, duration}` (start aus erlaubten Stufen, duration ∈ {120, 300, 600}), `mini_auction_cancel {lot}` (nur ohne Gebote).
Spielhalle: `mini_arcade_start {game}`, `mini_arcade_input {token, at, value}` (`at` = `GetServerTimeNow()` des Clients, nur zur Bewertung innerhalb enger Toleranz wie 2.4.0-QTE; `value` = gewählte Option), `mini_arcade_finish {token}`.

Server → Client: `mini` (Snapshot), `mini_notice {kind=...}` mit `car_spawned`, `testdrive_end`, `track_checkpoint`, `track_finish`, `auction_update` (öffentlicher Auktionszustand an alle), `auction_won`, `auction_sold`, `arcade_round` (Rundenparameter), `arcade_go` (BLITZ-REAKTION: Lampen aus), `arcade_result`.

## 5. Snapshot-Felder (zusätzlich)

`cars` (Liste mit `id, model, name, body, paint, rims, glow, spoiler, engine..nitro, locked, stats`), `activeCar`, `spawnedCar` (bool), `catalog` (nur einmal pro Sitzung nötig; darf im Snapshot stehen, wenn klein), `track {best, rewardedBest}`, `arcade {earnedToday, cap, best}`, `auction` (öffentlicher Zustand kommt über `auction_update`).

## 6. Sicherheit

- Kauf/Tuning/Stil: gesehene Stufe gegen Doppelklick, Level-Voraussetzung, Guthaben, Deckel `C.NumberCap`.
- Fahrzeuge: max. 1 gespawntes Auto pro Spieler + 1 Probefahrt; Despawn beim Verlassen; Fahrzeug-Modelle unter `workspace.PlayerCars`; fremde Spieler können nicht einsteigen (Sitz leert sich sofort); Abstand-/Geschwindigkeits-Plausibilität beim Zeitfahren (Mindestzeit je Abschnitt und je Runde aus dem Tempo des **gefahrenen** Autos: Spitze × Nitro × `speedMargin`; Tuning während des Laufs passt nur nach unten an).
- Figur versetzen (Reise, Werkstatt, Probefahrt): vor jedem serverseitigen `PivotTo` der Figur zuerst die `SeatWeld` unter dem Sitz zerstören (`CityService.Unseat`), `Humanoid.Sit = false` allein löst sie auf einem Live-Server nicht sofort – sonst reist das ganze Auto mit.
- Auktion: nur Spieler mit schreibbarem Profil (kein Studio-/Ersatzprofil) dürfen einliefern oder bei Spieler-Auktionen bieten. Übergabe Auto + Geld passiert synchron in einem Server-Schritt, danach sofort `P.Save` beider Profile. Verlässt der Verkäufer den Server, wird die Auktion abgebrochen (Auto entsperrt). Verlässt ein Bieter, fällt sein Gebot weg. Gebot erfordert **freies** Guthaben ≥ Gebot zum Gebotszeitpunkt (Guthaben minus eigene Höchstgebote auf anderen laufenden Losen); bei Abrechnung erneut geprüft. Fällt dabei das **Höchstgebot** weg (nicht gedeckt, Garage voll, …), läuft das Los 30 s weiter (höchstens 2-mal; Gebote des Bieters gestrichen, NPC-Bedenkzeiten neu), damit ein Scheingebot am Höchstbetrag nicht einem Niedriggebot den Zuschlag verschafft; wer nicht zahlen konnte, darf 10 Minuten nicht bieten. Verlässt der Höchstbieter kurz vor Schluss den Server, bleiben ebenfalls 30 s. Danach gewinnt das nächsthöhere gültige Gebot. Geldschieben: Käufer und Verkäufer einer Spieler-Auktion können 24 h lang nicht erneut miteinander handeln (beide Richtungen, `d.games.auction.partners`). Übergabe: nach dem Server-Schritt wird sie ins Auktionsbuch (DataStore `UCG_Auktionsbuch_v1`, Schlüssel `U_<userId>`) geschrieben, danach beide Profile gespeichert. Beim Laden gleicht `Mini.Reconcile` ab: Verkäufer-Profil mit dem übergebenen Auto (gleiche Id, Modell, Kaufzeit) → Auto weg, Auszahlung gutgeschrieben; Käufer-Profil ohne die Übergabe-Id in `received` → Auto dazu, Preis ab. Restrisiko: Absturz in den Millisekunden zwischen Übergabe und Buch-Eintrag, wenn genau dann ein Autosave eines der beiden Profile landet. Nie Geldänderung außerhalb `request()` für den Spieler ohne `transacting`-Prüfung: Abrechnung wartet, solange ein beteiligtes Profil `transacting` ist.
- Spielhalle: Bewertung ausschließlich aus Server-Zeit + Rundentoken; ein Token = eine Auszahlung; Tageslimit. `at` darf höchstens bis Ankunft − Einweg-Latenz (`Player:GetNetworkPing()/2`, ≤ 0,15 s) − 0,05 s zurückliegen (sonst angehoben). BLITZ-REAKTION: Startzeiten fest getaktet, die Zeitpunkte des Lampen-Aus stehen nicht im Rundenpaket, sondern kommen erst im Moment selbst (`mini_notice arcade_go {token, attempt, g}`); die Reaktionszeit wird um die Einweg-Latenz bereinigt.
- Keine Glücksspiel-Mechanik, keine bezahlten Zufallsbelohnungen.

## 7. Balance-Ziele

- Werkstatt (2.4.0-Aufträge) ist die ergiebigste aktive Einnahme pro Minute auf jedem Level.
- Jedes Minispiel aktiv gespielt ≤ 60 % der Werkstatt-Einnahme/Minute auf vergleichbarem Level; passive Einnahmen (Presse-Maschinen, Idle-Tuning) ≤ 25 %.
- Erstes eigenes Auto (Kompakt) nach etwa 20–30 Minuten Spielzeit; Sportwagen nach mehreren Stunden; Supersportwagen/Elektro als Langzeitziel (Level-Voraussetzung wie `C.Cars`).
- Tuning-Kosten skalieren mit dem Autowert.
- Spielhalle: Tageslimit an Credits; Zeitfahren nur für neue Bestzeiten.
