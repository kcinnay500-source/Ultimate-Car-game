# Balance 3.x: Credits pro Minute und Autopreise

Dieses Dokument hält die Wirtschaft von Ultimate Car Game 3.x gegen die Ziele aus `docs/PHASE2_CONTRACT.md` §7 fest.
Die Tabellen unten schreibt `tools/economy_sim.py`. Das Skript liest die echten Zahlen aus den Modulen (über
`tools/economy_dump.lua` und luaurun) und rechnet sie nicht von Hand nach.

```
python3 tools/economy_sim.py              # Tabellen ausgeben
python3 tools/economy_sim.py --check      # Ziele aus §7 prüfen (Exit-Code 1 bei Verstoß)
python3 tools/economy_sim.py --write-doc  # Tabellenblock in diesem Dokument erneuern
```

## Ziele (§7) und Stand

| Ziel | Stand |
|---|---|
| Die Werkstatt (2.4.0-Aufträge) ist auf jedem Level die ergiebigste aktive Einnahme | erfüllt: kein Minispiel erreicht 60 % |
| Jedes Minispiel bringt aktiv gespielt höchstens 60 % der Werkstatt pro Minute | erfüllt: höchster Wert 58 % (Level 1) |
| Passive Einnahmen bringen höchstens 25 % | erfüllt: 24 % auf Level 1, sonst 13–18 % |
| Das erste eigene Auto (Komet C1) ist nach 20–30 Min. kaufbar | 26 Min. |
| Der Sportwagen (Vektor RS) ist nach mehreren Stunden kaufbar | 3,9 Std. |
| Supersportwagen und Elektro sind Langzeitziele | Aureon 11,9 Std., Elys 17,7 Std. |
| Tuning-Kosten skalieren mit dem Autowert | ja (`CarCatalog.Tune[].share` × Autowert × 1,45^(Stufe−1)) |
| Die Spielhalle hat ein Tageslimit, das Zeitfahren zahlt nur für neue Bestzeiten | ja (1.500 Cr/Tag, Topf je Spieler) |

## Modell und Annahmen

- **Werkstatt:** Der Angebotspool arbeitet wie `R.RefreshOffers`: immer eine Inspektion, der Rest zufällig. Der
  Spieler nimmt jeweils das Angebot mit den meisten Credits pro Minute, für das er die Geräte hat. Die Vergütung
  folgt `R.Reward` bei Qualität 96, mit Nexra-Teilen und abzüglich der Teilekosten. Aktive Zeit je Auftrag:
  40 s fest (Empfang, Diagnose, Endkontrolle, Abrechnen) plus 8 s je Arbeitsschritt (hingehen, Werkzeug,
  Bühne/Haube, Mess-QTE). Die Arbeitszeit folgt `R.StepDuration`. Mit n Bühnen gilt als Zyklus
  `max(aktiv, (aktiv + Arbeit) / n)`. Bühnen werden freigeschaltet wie `C.BayLevels`. Auftragsannahme und
  Werkzeugqualität steigen mit dem Level (Tabelle `ASSUME` im Skript). Querboni der Minispiele sind in der
  Grundrechnung **nicht** enthalten. Deshalb ist der Vergleich für die Minispiele streng.
- **XP zählen mit:** 2.4.0 zahlt bei jedem Level-up 120 + 18 × Level Credits aus. Die XP aller Tätigkeiten
  (Werkstatt und Minispiele) werden darum mit „Credits je XP“ des jeweiligen Levels bewertet (Zeile „Wert von 1 XP“).
- **Quiz:** Der Katalog hat nur 20 Fragen, die bald auswendig bekannt sind. Angenommen werden 5 s je Frage und 95 %
  richtige Antworten.
- **Parkplatz:** Zufallsrätsel wie `SideGameRules.NewPuzzle`. Ein Rätsel dauert 2,5 s plus 0,7 s je Tipp, in 3 %
  der Fälle gibt es Blechschaden.
- **Schrottplatz:** Ein Zyklus besteht aus Kaufen, Vorbereitung, Zerlegen und Verkauf (Vorbereitungszeit + 4 s).
  Funde, seltene Teile (Wert = Nexra-Preis) und XP folgen `SideGameRules`.
- **Spielhalle:** Gerechnet wird mit 700 von 1000 Punkten und der mittleren Rundendauer aus
  `ArcadeRules.NewRound` × 0,9, plus 9 s für Countdown und Neustart.
- **Teststrecke:** Das Oval ist etwa 780 Studs lang, eine Runde dauert 8–16 s. Gerechnet ist die ergiebigste
  Strategie: eine absichtlich langsame erste Runde bis zur Basiszeit, danach die Bestzeit.
- **Schrottpresse:** Gerechnet wird mit Dauerklicken (6 Klicks/s, volle Combo) und gierig gekauften Upgrades. Die
  Presse ist nicht an das Level gebunden. Verglichen wird darum bei **gleicher investierter Zeit**: Der Spieler
  presst so lange, wie die Werkstatt bis zu diesem Level braucht.
- **Passiv:** Gerechnet wird das beste freigeschaltete Tuning-Projekt × Plätze, sofort neu gestartet, plus die
  passiven Tuning-Einnahmen (`TuningRules.IdleRate`) und die Presse-Maschinen über den Schrotthändler. Die
  Tuning-Abteilung steigt mit dem Level (1, 2, 4, 7, 10, 13). Die abgeschlossenen Projekte steigen ebenfalls
  (0, 2, 8, 25, 50, 80).
- **Autokauf:** Der Spieler macht nur Werkstatt-Aufträge. Er kauft Bühnen und nötige Geräte, sobald er sie
  braucht, und spart ab Start für genau dieses Auto. Die rechte Spalte rechnet zusätzlich mit allen Querboni der
  Minispiele (Parkplatz-Serie, Diagnosepunkte, Tuning-Abteilung, Presse).

## Ergebnis

<!-- SIM:BEGIN -->
#### Credits pro Minute, aktiv gespielt (inkl. Wert der XP über den Level-Bonus)

| Tätigkeit | Lv 1 | Lv 5 | Lv 10 | Lv 20 | Lv 30 | Lv 40 |
|---|---:|---:|---:|---:|---:|---:|
| **Werkstatt (2.4.0-Aufträge)** | **214** | **531** | **803** | **1.468** | **2.850** | **5.765** |
| davon reine Auftrags-Credits | 172 | 469 | 736 | 1.384 | 2.734 | 5.597 |
| Mechaniker-Quiz | 113 (53 %) | 104 (20 %) | 100 (12 %) | 97 (7 %) | 96 (3 %) | 95 (2 %) |
| Parkplatz-Chaos | 123 (58 %) | 117 (22 %) | 115 (14 %) | 113 (8 %) | 112 (4 %) | 112 (2 %) |
| Schrottplatz | 123 (57 %) | 183 (34 %) | 288 (36 %) | 535 (36 %) | 826 (29 %) | 1.182 (21 %) |
| Spielhalle (bester Automat) | 52 (24 %) | 48 (9 %) | 46 (6 %) | 45 (3 %) | 45 (2 %) | 44 (1 %) |
| Teststrecke (Bestzeiten) | 117 (54 %) | 152 (29 %) | 200 (25 %) | 299 (20 %) | 398 (14 %) | 498 (9 %) |
| Schrottpresse (Klicken → Händler) | 65 (30 %) | 107 (20 %) | 151 (19 %) | 213 (14 %) | 253 (9 %) | 277 (5 %) |
| Wert von 1 XP (Level-Bonus) | 1,47 | 1,06 | 0,89 | 0,77 | 0,72 | 0,69 |

In Klammern: Anteil an der Werkstatt auf demselben Level (Ziel ≤ 60 %). Schrottpresse: so lange gepresst, wie die Werkstatt bis zu diesem Level braucht (Lv 1: 5 Min., Lv 5: 15 Min., Lv 10: 34 Min., Lv 20: 90 Min., Lv 30: 155 Min., Lv 40: 212 Min.).

#### Passive Einnahmen pro Minute

| Tätigkeit | Lv 1 | Lv 5 | Lv 10 | Lv 20 | Lv 30 | Lv 40 |
|---|---:|---:|---:|---:|---:|---:|
| Tuning-Projekte (bestes Projekt × Plätze) | 35 | 47 | 69 | 106 | 304 | 416 |
| Passive Tuning-Einnahmen | 16 | 26 | 51 | 118 | 219 | 345 |
| Presse-Maschinen (→ Händler) | 0 | 0 | 0 | 0 | 0 | 1 |
| **Summe passiv** | **51** (24 %) | **73** (14 %) | **121** (15 %) | **225** (15 %) | **523** (18 %) | **761** (13 %) |
| bestes Projekt (Plätze) | Sportfahrwerk (1) | Sportabgasanlage (1) | Motorsoftware (1) | Turbo-Umbau (1) | Motor-Revision (2) | Restomod-Komplettaufbau (2) |

In Klammern: Anteil an der Werkstatt (Ziel ≤ 25 %).

Open-World-Gebäude (Ausbaustufe 4, Meilenstein 6, `GameConfig.OW.Buildings`; Erträge sammeln sich höchstens 12 Std. an):

| Gebäude | Stufe 1 | Stufe 2 | Stufe 3 | Stufe 4 | Level |
|---|---:|---:|---:|---:|---:|
| Autohaus (Credits/Min) | 25 (3 % auf Lv 10) | 67 (5 % auf Lv 20) | 150 (5 % auf Lv 30) | 300 (≈ 10 % auf Lv 30, 5 % auf Lv 40) | 10 |
| Schrottplatz (Schrott/Std. → Credits/Min beim Händler) | 2 Mrd. (≈ 3) | 6 Mrd. (≈ 10) | 15 Mrd. (≈ 25) | 40 Mrd. (≈ 67) | 18 |
| Produktion (Altteile) | 10 je 6 Std. | 15 je 4 Std. | 20 je 3 Std. | 30 je 2 Std. + Auto-Gutschein je 48 Std. | 35 |

Story-Missionen (Meilenstein 7): `StoryRules.BalanceCheck()` prüft je Mission `credits / minutes ≤ 0,4 × Werkstatt-Cr/Min`
des Kapitel-Levels (Tabelle oben, interpoliert; `GameConfig.Story.Balance`), abgesichert in `tests/test_story.lua`.

#### Tageslimits der Minispiele

| Minispiel | Limit je UTC-Tag | Credits/Tag Lv 1 | Credits/Tag Lv 40 | Minuten bis zum Limit |
|---|---|---:|---:|---:|
| Mechaniker-Quiz | 60 bezahlte richtige Antworten | 420 | 420 | 5 |
| Parkplatz-Chaos | 60 bezahlte Lösungen | 402 | 402 | 4 |
| Schrottplatz | 25 Unfallfahrzeuge | 566 | 10.779 | 10 |
| Spielhalle (bester Automat) | 1.500 Cr | 1.500 | 1.500 | 40 |
| Teststrecke (Bestzeiten) | nur neue Bestzeiten (Topf je Spieler) | 400 | 1.960 | 4 |

#### Spielhalle je Automat (typisch 700 von 1000 Punkten)

| Automat | Credits bei 1000 P. | Credits/Runde | Credits/Min. |
|---|---:|---:|---:|
| Blitz-Reaktion | 35 | 22 | 37 |
| Bremsweg-Profi | 40 | 26 | 39 |
| Boxenstopp | 30 | 19 | 33 |
| Drehmoment | 30 | 19 | 37 |
| Motor-Ohr | 40 | 26 | 28 |
| Einpark-Profi | 45 | 29 | 32 |
| Rennsimulator 1 · Landstraße | 45 | 29 | 39 |
| Rennsimulator 2 · Nachtrennen | 50 | 32 | 39 |

#### Zeit bis zum Autokauf (ab Spielstart, Ersparnis nur für dieses Auto)

| Auto | Level | Preis | Level erreicht | Kaufbar: nur Werkstatt | Kaufbar: mit Querboni |
|---|---:|---:|---:|---:|---:|
| Komet C1 | 1 | 4.500 Cr | 0 Min. | **26 Min.** | 19 Min. |
| Komet S2 | 3 | 18.000 Cr | 6 Min. | **48 Min.** | 33 Min. |
| Nord R4 | 4 | 28.000 Cr | 9 Min. | **57 Min.** | 42 Min. |
| Komet Urban | 7 | 40.000 Cr | 22 Min. | **70 Min.** | 50 Min. |
| Nord Atlas Tourer | 10 | 72.000 Cr | 34 Min. | **1,8 Std.** | 68 Min. |
| Vektor RS | 18 | 390.000 Cr | 78 Min. | **3,9 Std.** | 2,8 Std. |
| Vektor GTX | 24 | 850.000 Cr | 1,9 Std. | **5,7 Std.** | 3,8 Std. |
| Vektor Aureon V12 | 30 | 2.600.000 Cr | 2,6 Std. | **11,9 Std.** | 6,4 Std. |
| Nord Elys E9 | 38 | 4.600.000 Cr | 3,3 Std. | **17,7 Std.** | 9,6 Std. |

Querboni (Spalte rechts): Parkplatz-Serie gedeckelt (×1,25), Diagnosepunkte gedeckelt (−35 % Arbeitszeit), Tuning-Abteilung wie Annahme, Presse-Anteil nach gleicher Presszeit.

#### Werkstatt-Verlauf (nur Aufträge)

| Level | 2 | 5 | 10 | 18 | 24 | 30 | 38 | 40 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| erreicht nach | 4 Min. | 15 Min. | 34 Min. | 78 Min. | 1,9 Std. | 2,6 Std. | 3,3 Std. | 3,5 Std. |

<!-- SIM:END -->

## Geänderte Stellschrauben (gegenüber dem Stand vor dem Abgleich)

| Wert | vorher | jetzt | Grund |
|---|---:|---:|---|
| `MiniConfig.ScrapPerCredit` | 4 | 10.000.000 | Die Presse (100 billige, additive Upgrades, Combo ×25) erzeugt nach 5 Min. rund 800 Mio. Schrott/Min. Beim alten Kurs wären das über 100 Mio. Cr/Min. gewesen. |
| `MiniConfig.ScrapExchangePackages` | 100 … 10 Mio. | 100 Mio. … 10 Bio. | Die Pakete passen jetzt zum Kurs (8 Cr … 800.000 Cr). |
| `MiniConfig.PressWorkshopShare` / `PressTuningShare` | 0,6 / 0,8 | 0,02 / 0,02 | Nach 1 Min. Pressen lagen über 1.900 Stufen an (globaler Faktor ×5,8). Mit 0,6 hätte das die Werkstatt vervierfacht. Jetzt bringt es +5 % bis +20 %. |
| `MiniConfig.RebirthBaseThreshold` | 1 Mio. | 10 Mrd. | 1 Mio. war nach Sekunden erreicht. |
| Meilensteine der Presse (`m_scrap_*`, `m_press_upg_25`, `m_rebirth_1`) | 10 Tsd. / 1 Mio. / 1 Mrd. Schrott, 25 Upgrades, 50.000 Cr … | 100 Mio. / 100 Mrd. / 10 Bio. Schrott, 500 Upgrades, 300 … 15.000 Cr | Vorher kamen in den ersten 3 Min. rund 67.000 Cr zusammen. Die Ids bleiben wegen des gespeicherten Fortschritts. |
| Tagesziele `d_scrap`, `d_upg` | 20.000 Schrott, 5 Upgrades | 100 Mio. Schrott, 50 Upgrades | Die Ziele passen jetzt zum Tempo der Presse. |
| `QuizCorrectCredits` / `QuizCorrectXp` / `QuizWrongXp` | 90 / 20 / 4 | 7 / 2 / 0 | Bei ~11 richtigen Antworten pro Minute kam das Quiz vorher auf 1.000+ Cr/Min. Falsche Antworten gaben unbegrenzt XP. |
| `QuizPaidPerDay` | 40 | 60 | Das Tageslimit ist in Minuten gerechnet etwas länger. |
| `ParkingRewardBase` / `PerStreak` / `ParkingXp` | 120 / 15 / 16 | 2 / 1 / 1 | Ein Rätsel dauert etwa 5 s, vorher waren es rund 5.900 Cr/Min. |
| `CustomerBonusPerStreak` / `CustomerBonusCap` | 0,03 / 1,7 | 0,05 / 1,25 | Der Querbonus der Serie galt dauerhaft ×1,7 auf die Werkstatt und war in 2 Min. erreicht. Jetzt ist er nach 5 Rätseln voll und bringt +25 %. |
| `ParkingPaidPerDay` | 40 | 60 | wie beim Quiz |
| `ScrapyardCarCost` / `SellCredits` / `DismantleSeconds` | 180 / 220 / 8 | 105 / 80 / 20 | Vorher brachte ein Fahrzeug im Schnitt +125 Cr und die XP (fest 8 + Funde) alle 12 s. Jetzt ist der Gewinn klein und positiv. |
| `TuningRewardBase` / `TuningCostShare` | 60 / 0,35 | 28 / 0,45 | Passiv auf Level 1 vorher 40 %, jetzt 24 %. |
| Händlerpreise (`CarCatalog.Dealer`) | 4.500 … 320.000 | 4.500 … 4,6 Mio. | Die 2.4.0-Aufträge bringen auf Level 30–40 etwa 3.000–6.000 Cr/Min. Mit den alten Preisen wäre der Elys nach 3,5 Std. kaufbar gewesen. |
| Sondermodelle (`CarCatalog.Specials.value`) | 16.000 … 450.000 | 24.000 … 5,8 Mio. | Etwa das 1,3-Fache des Grundmodells. |
| Teststrecke (`CarCatalog.Track`) | 400 / 60 je s / Basis 60 s / Deckel 1.500 / +4 % je Level / 30 XP | 100 / 15 / 30 s / 250 / +10 % / 15 XP | Eine Runde dauert nur 8–16 s. Die alte Basiszeit von 60 s erlaubte einen Topf von rund 3.400 Cr in 3 Min. |

Unverändert blieben die Spielhalle (8 Automaten mit 30–50 Cr bei 1000 Punkten, Tageslimit 1.500 Cr), die
Auktionsregeln (5 % Gebühr, NPC-Startgebot 60 %, NPC-Limits 70–120 % des Richtwerts) und die Tuning-Anteile der
Autos (voller Leistungsausbau ≈ 3,2 × Autowert). Unverändert blieben auch die Waschstraße (150 Cr) und die
2.4.0-Zahlen (Aufträge, XP, Level-Bonus, Geräte, Ausbau).

## Offene Punkte (Code, nicht Zahlen)

Diese Punkte lassen sich mit den Stellschrauben allein nicht sauber lösen. Sie liegen in Dateien anderer Besitzer:

1. **Presse → Credits ohne Tagesgrenze** (`PressRules.Exchange`). Der Kurs hält den Umtausch bei gleicher
   investierter Zeit unter 30 % der Werkstatt. Die Presse ist aber nicht an das Level gebunden: Wer 10 Std. nur
   presst, bekommt ~4,3 Mrd. Schrott/Min. Das sind ~350 Cr/Min., auch auf Level 1. Vorschlag: ein
   Tageslimit für den Umtausch wie in der Spielhalle, oder ein Kurs, der vom Spielerlevel abhängt.
2. **Die passive Tuning-Rate wächst unbegrenzt** mit abgeschlossenen Projekten (`TuningRules.IdleRate`:
   `completed^1,12 × 1,5` pro Minute, Formel fest im Code). Nach 500 Projekten wären das allein ~1.600 Cr/Min.
   Vorschlag: `completed` deckeln (z. B. `min(completed, 60)`) und die Werte nach `MiniConfig` ziehen.
3. Die „Händler“-Upgrades der Presse (Typ 2) zahlen bei jedem Kauf `max(1, ⌊Effekt/2⌋)` Cr und +1 Ruf. Das
   ist klein (einmalig einige Tausend Cr), wächst aber mit dem Schrott. Die Formel ist fest in `PressRules.BuyUpgrade`.
4. Beim Schrottplatz sind die Zufalls-Credits (0–90 je Fahrzeug) und die XP (8 + Funde, Verkauf 5) fest in
   `SideGameRules`. Nur deshalb braucht es die längere Vorbereitungszeit von 20 s.
5. Veraltete Kommentare mit alten Zahlen: `SideGameRules.lua` (Kopf: „5 Stück → 220 Cr“) und `CrossBonus.lua`
   („höchstens ×1,7“).
