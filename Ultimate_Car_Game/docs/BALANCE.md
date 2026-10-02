# Balance 3.x: Credits pro Minute und Autopreise

Dieses Dokument hält die Wirtschaft von Ultimate Car Game 3.x gegen die Ziele aus `docs/PHASE2_CONTRACT.md` §7 fest.
Die Tabellen unten schreibt `tools/economy_sim.py`. Das Skript liest die echten Zahlen aus den Modulen (über
`tools/economy_dump.lua` und luaurun) und rechnet sie nicht von Hand nach.

```
python3 tools/economy_sim.py              # Tabellen ausgeben
python3 tools/economy_sim.py --check      # Ziele aus §7 prüfen (Exit-Code 1 bei Verstoß)
python3 tools/economy_sim.py --write-doc  # Tabellenblock in diesem Dokument erneuern
python3 tools/economy_sim.py --tycoon     # nur die Rundendauer des Schnellen Spiels
```

`--check` prüft seit Ausbaustufe 4 zusätzlich die Ziele aus `docs/PHASE4_CONTRACT.md` (Abschnitt „Ziele Ausbaustufe 4“).
Die Zahlen dafür liest `tools/economy_dump.lua` aus `GameConfig` (XP-Regler, Unlocks, Prestige, Tycoon-Boni,
OW-Gebäude und -Perks, Story, Shop).

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

## Ziele Ausbaustufe 4 (PHASE4_CONTRACT §3, §7, §8, §9) und Stand

| Ziel | Prüfung in `--check` | Stand |
|---|---|---|
| Level 50 nach ≈ 8 Std. gemischtem Spiel | 6,5–9,5 Std. | 8,2 Std. |
| Level 90 (Nord Elys E9) nach 25–35 Std. gemischtem Spiel | 25–35 Std. | 25,3 Std. (knapp, siehe unten) |
| Jeder Tycoon-Gebäudetyp bis Stufe 5 komplett in 4–6,5 Std. | je Typ | 4,9–5,0 Std. (2. Runde 4,3 Std.) |
| Story-, Neben-, Legenden-Missionen und Kiesplatz: Credits + XP-Wert je Minute ≤ 40 % der Werkstatt des Levels | jede Mission, Nebenmissionen auf jedem Level ab Freischaltung | höchstens 39 % (Kapitel 1 und Kiesplatz auf Level 1) |
| OW-Gebäude: passiver Ertrag ≤ 25 % der Werkstatt | jede Stufe ab ihrem Level und alle Gebäude zusammen | höchstens 10 % je Stufe, alle zusammen ≤ 8 % |
| Erste Kosmetik nach ≈ 1 Std. kaufbar, aber ein echtes Sparziel | erstes Auto + billigste Kosmetik ≤ 1 Std., Preis ≥ 10 % des ersten Autos | 26 Min. (Melodie-Hupe 800 Cr) |
| DLC-Autos für Credits erst ab dem Level ihres Basismodells, nie billiger als das Basismodell | Level = Basis-Level, Preis ≥ Basispreis | ja (Faktor 1,5) |
| Shop-Preise stimmig | Bündel ≤ Summe der Teile, Produkt-Credits-Preis = Kosmetik-Preis | ja |
| Gestapelte Boni (Prestige + Tycoon + OW-Perks) bleiben unter den Deckeln | Tabelle „Deckel der Boni“ | ja |

**Gemischtes Spiel** (Annahme `MIX` im Skript): Die Spielzeit teilt sich je Spielstunde auf. Bis Level 14: Werkstatt 55 %,
Minispiele 15 %, Story/Nebenmissionen/Kiesplatz 15 %, Schnelles Spiel 10 %, Freizeit 5 %. Level 15–49: 45 / 10 / 10 / 20 / 15 %.
Ab Level 50: 30 / 10 / 10 / 25 / 25 %. „Freizeit“ ist Autos fahren und tunen, Auktionen, Waschstraße und Lobby. Sie
bringt keine XP. Story-Missionen laufen der Reihe nach, sobald das Kapitel-Level erreicht ist (Aufwand = `minutes`).
Danach kommen bis zu 3 Nebenmissionen je Spieltag (2 Std. Spielzeit je Tag), die restliche Story-Zeit geht an den Kiesplatz.
Das Schnelle Spiel läuft Durchlauf für Durchlauf (Werkstatt, Autohaus, Produktion, Schrottplatz). Es bringt
`GameConfig.XP.TycoonStage` je Stufe und `TycoonRun` je Durchlauf, und der Werkstatt-Bonus wirkt in der Werkstatt mit.
OW-Gebäude werden gebaut, sobald Level und das 1,5-Fache des Preises da sind.

**Warum Level 90 knapp ist:** Rund 90 % aller XP kommen aus den 2.4.0-Aufträgen (`GarageShared.Config`, unverändert).
Die Werkstatt allein erreicht Level 50 nach 4,8 Std. und Level 90 nach 11,5 Std. Die Regler in `GameConfig.XP` können
nur XP **hinzufügen**. Sie verlangsamen nichts. Die 25–35 Std. hängen darum an der Annahme, dass Spieler ab Level 50
höchstens ein knappes Drittel ihrer Zeit in der Werkstatt verbringen. Wer nur Aufträge abarbeitet, hat den Elys nach
etwa 12–18 Std. Für eine feste Untergrenze bräuchte es einen XP-Faktor für die 2.4.0-Aufträge ab Level 50. Das wäre
eine Code-Änderung (Garage + Config) und keine Zahl im Balance-Bereich (siehe „Offene Punkte“).

**Deckel der Boni** (verbindlich, geprüft): Prestige-Einnahmen ≤ +30 %, Prestige-Rabatt ≤ 10 %, Tycoon-Boni wie §8
(Werkstatt +10 %, Autohaus −7,5 %, Produktion/Schrottplatz +15 %), jeder OW-Perk ≤ +25 %, Tycoon × OW-Perk auf die
Werkstatt ≤ ×1,6 (`GameConfig.WorkshopRewardCap`), **Händlerrabatt gesamt ≤ 30 %**, **Tuning-Tempo gesamt ≤ +40 %**,
**Schrott gesamt ≤ +40 %**, Rebirth-Boost ≤ +150 %.

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
| Blitz-Reaktion | 35 | 22 | 33 |
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
| Komet C1 | 3 | 4.500 Cr | 6 Min. | **26 Min.** | 19 Min. |
| Komet S2 | 8 | 18.000 Cr | 26 Min. | **48 Min.** | 33 Min. |
| Nord R4 | 14 | 28.000 Cr | 52 Min. | **57 Min.** | 52 Min. |
| Komet Urban | 22 | 40.000 Cr | 1,7 Std. | **1,7 Std.** | 1,7 Std. |
| Nord Atlas Tourer | 32 | 72.000 Cr | 2,7 Std. | **2,7 Std.** | 2,7 Std. |
| Vektor RS | 45 | 390.000 Cr | 4,1 Std. | **4,1 Std.** | 4,1 Std. |
| Vektor GTX | 58 | 850.000 Cr | 5,8 Std. | **5,8 Std.** | 5,8 Std. |
| Vektor Aureon V12 | 72 | 2.600.000 Cr | 7,9 Std. | **11,9 Std.** | 7,9 Std. |
| Nord Elys E9 | 90 | 4.600.000 Cr | 11,5 Std. | **17,7 Std.** | 11,5 Std. |

Querboni (Spalte rechts): Parkplatz-Serie gedeckelt (×1,25), Diagnosepunkte gedeckelt (−35 % Arbeitszeit), Tuning-Abteilung wie Annahme, Presse-Anteil nach gleicher Presszeit.

#### Werkstatt-Verlauf (nur Aufträge)

| Level | 2 | 5 | 10 | 18 | 24 | 30 | 38 | 40 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| erreicht nach | 4 Min. | 15 Min. | 34 Min. | 78 Min. | 1,9 Std. | 2,6 Std. | 3,3 Std. | 3,5 Std. |

#### Schnelles Spiel: Zeit bis Stufe 5 komplett (aktiv, gieriger Kauf alle 15 s)

| Gebäude | Stufe 2 | Stufe 3 | Stufe 4 | Stufe 5 | **komplett** | 2. Runde (Rebirth +15 %) | Bargeld gesamt |
|---|---:|---:|---:|---:|---:|---:|---:|
| Werkstatt | 15 Min. | 49 Min. | 1,7 Std. | 3,1 Std. | **5,0 Std.** | 4,3 Std. | 27.776.961 |
| Autohaus | 15 Min. | 48 Min. | 1,7 Std. | 3,0 Std. | **4,9 Std.** | 4,3 Std. | 34.192.799 |
| Produktion | 15 Min. | 48 Min. | 1,7 Std. | 3,1 Std. | **5,0 Std.** | 4,3 Std. | 41.484.083 |
| Schrottplatz | 15 Min. | 48 Min. | 1,7 Std. | 3,1 Std. | **5,0 Std.** | 4,3 Std. | 20.766.717 |

Ziel (Vertrag §8): ≈ 5 Std. je Durchlauf (geprüft: 4,0 Std. bis 6,5 Std.); Bargeld bleibt im Durchlauf und wird nie zu Credits.

### Ausbaustufe 4 (PHASE4_CONTRACT)

#### Level im gemischten Spiel (Werkstatt + Minispiele + Story/Nebenmissionen/Kiesplatz + Schnelles Spiel)

| Level | 5 | 10 | 20 | 30 | 40 | 50 | 60 | 72 | 90 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| erreicht nach | 12 Min. | 34 Min. | 2,3 Std. | 4,3 Std. | 6,4 Std. | 8,2 Std. | 11,2 Std. | 16,1 Std. | 25,3 Std. |

XP-Quellen in 50 Std. (2 Tycoon-Durchläufe):

| Quelle | XP | Anteil |
|---|---:|---:|
| Werkstatt-Aufträge (inkl. Ausbau-XP) | 218.480 | 89 % |
| Minispiele | 11.860 | 5 % |
| Story-Missionen | 10.490 | 4 % |
| Nebenmissionen | 1.800 | 1 % |
| Schnelles Spiel (Stufen + Durchläufe) | 1.040 | 0 % |
| Kiesplatz-Verkäufe | 709 | 0 % |
| OW-Gebäude bauen | 360 | 0 % |
| Tutorial | 60 | 0 % |

Spielzeit-Anteile: bis Level 14: workshop 55 %, minigames 15 %, story 15 %, tycoon 10 %, free 5 %; bis Level 49: workshop 45 %, minigames 10 %, story 10 %, tycoon 20 %, free 15 %; bis Level ∞: workshop 30 %, minigames 10 %, story 10 %, tycoon 25 %, free 25 %. Die Werkstatt-Aufträge allein erreichen Level 50 nach 4,8 Std. und Level 90 nach 11,5 Std..

#### Missionen: Credits + XP-Wert je Minute (Grenze 40 % der Werkstatt des Levels)

| Mission | Level | Cr/Min | Grenze | Anteil |
|---|---:|---:|---:|---:|
| Story c1_m1 | 1 | 80 | 86 | 37 % |
| Story c1_m2 | 1 | 83 | 86 | 39 % |
| Story c1_m3 | 1 | 82 | 86 | 38 % |
| Story c2_m1 | 5 | 110 | 213 | 21 % |
| Story c2_m2 | 5 | 143 | 213 | 27 % |
| Story c2_m3 | 5 | 193 | 213 | 36 % |
| Story c3_m1 | 15 | 286 | 397 | 29 % |
| Story c3_m2 | 15 | 291 | 397 | 29 % |
| Story c3_m3 | 15 | 166 | 397 | 17 % |
| Story c3_m4 | 15 | 336 | 397 | 34 % |
| Story c4_m1 | 30 | 664 | 1.148 | 23 % |
| Story c4_m2 | 30 | 652 | 1.148 | 23 % |
| Story c4_m3 | 30 | 921 | 1.148 | 32 % |
| Story c5_m1 | 50 | 709 | 2.291 | 12 % |
| Story c5_m2 | 50 | 1.062 | 2.291 | 19 % |
| Story c5_m3 | 50 | 876 | 2.291 | 15 % |
| Neben s_delivery | 3 | 55 | 159 | 14 % |
| Neben s_timetrial | 8 | 57 | 287 | 8 % |
| Neben s_arcade | 10 | 66 | 322 | 8 % |
| Neben s_dismantle | 3 | 73 | 159 | 18 % |
| Neben s_auction | 15 | 70 | 397 | 7 % |
| Neben s_wash | 8 | 72 | 287 | 10 % |
| Neben s_press | 2 | 63 | 122 | 21 % |
| Neben s_tune | 3 | 94 | 159 | 24 % |
| Neben s_quiz | 4 | 83 | 173 | 19 % |
| Neben s_parking | 5 | 83 | 213 | 16 % |
| Neben s_jobs | 1 | 45 | 86 | 21 % |
| Legende l_jobs100 | 10 | 179 | 322 | 22 % |
| Legende l_equipment | 14 | 283 | 397 | 29 % |
| Legende l_bays4 | 8 | 259 | 287 | 36 % |
| Kiesplatz-Verkauf | 1 | 83 | 86 | 39 % |

Neben- und Kiesplatz-Zeilen: jeweils das ungünstigste Level (Nebenmissionen wachsen mit dem Level bis ×3, die Werkstatt wächst schneller). Aufwand der Nebenmissionen: Annahme `MIX.side_minutes`.

#### Open-World-Gebäude: passiver Ertrag je Minute (Grenze 25 % der Werkstatt des Stufen-Levels)

| Gebäude | Stufe | ab Level | Preis | Cr/Min | Anteil |
|---|---:|---:|---:|---:|---:|
| Autohaus | 1 | 10 | 12.000 Cr | 25 | 3 % |
| Autohaus | 2 | 15 | 50.000 Cr | 67 | 7 % |
| Autohaus | 3 | 25 | 180.000 Cr | 150 | 8 % |
| Autohaus | 4 | 35 | 600.000 Cr | 300 | 10 % |
| Produktion | 1 | 30 | 150.000 Cr | 0 | 0 % |
| Produktion | 2 | 30 | 500.000 Cr | 1 | 0 % |
| Produktion | 3 | 30 | 1.500.000 Cr | 2 | 0 % |
| Produktion | 4 | 30 | 4.000.000 Cr | 6 | 0 % |
| Schrottplatz | 1 | 18 | 40.000 Cr | 3 | 0 % |
| Schrottplatz | 2 | 18 | 140.000 Cr | 9 | 1 % |
| Schrottplatz | 3 | 18 | 400.000 Cr | 22 | 2 % |
| Schrottplatz | 4 | 18 | 1.100.000 Cr | 57 | 4 % |

| Level | Lv 1 | Lv 5 | Lv 10 | Lv 20 | Lv 30 | Lv 40 |
|---|---:|---:|---:|---:|---:|---:|
| alle OW-Gebäude (höchste baubare Stufe) | 0 (0 %) | 0 (0 %) | 25 (3 %) | 124 (8 %) | 213 (7 %) | 363 (6 %) |
| dazu Tuning + Presse-Maschinen | 51 (24 %) | 73 (14 %) | 121 (15 %) | 225 (15 %) | 523 (18 %) | 761 (13 %) |

#### Shop: Kosmetik für Credits (Zeit ab Start, gespart für Komet C1 + dieses Teil)

| Kosmetik | Platz | Level | Preis | kaufbar nach |
|---|---|---:|---:|---:|
| Melodie-Hupe | horn | 1 | 800 Cr | 26 Min. |
| Blaue Spur | trail | 2 | 1.000 Cr | 26 Min. |
| Goldfelgen | rims | 1 | 1.200 Cr | 26 Min. |
| Fanfare | horn | 3 | 1.200 Cr | 26 Min. |
| Rennstreifen | wrap | 1 | 1.500 Cr | 26 Min. |
| Carbon-Felgen | rims | 2 | 1.500 Cr | 26 Min. |
| Laser-Hupe | horn | 6 | 1.500 Cr | 26 Min. |
| Blauchrom | rims | 4 | 1.800 Cr | 29 Min. |
| Neonspur | trail | 6 | 1.800 Cr | 29 Min. |
| Zielflagge | wrap | 2 | 2.000 Cr | 29 Min. |
| Regenbogenspur | trail | 4 | 2.000 Cr | 29 Min. |
| Flammen | wrap | 3 | 2.500 Cr | 30 Min. |
| Neonfelgen | rims | 6 | 2.500 Cr | 30 Min. |
| Wellen | wrap | 5 | 3.000 Cr | 31 Min. |

| DLC-Auto | Basismodell | Level | Credits-Preis | Level erreicht | kaufbar (nur Werkstatt) |
|---|---|---:|---:|---:|---:|
| Komet S2 Sunset | Komet S2 | 8 | 27.000 Cr | 26 Min. | 56 Min. |
| Nord R4 Nachtfalke | Nord R4 | 14 | 42.000 Cr | 52 Min. | 74 Min. |
| Vektor RS Blitz | Vektor RS | 45 | 585.000 Cr | 4,1 Std. | 4,8 Std. |

#### Deckel der Boni (Prestige, Schnelles Spiel, OW-Perks)

| Bonus | Höchstwert | Deckel | ok |
|---|---:|---:|---|
| Prestige: Einnahmen | 30,0 % | 30,0 % | ja |
| Prestige: Händlerrabatt | 10,0 % | 10,0 % | ja |
| Prestige: Tycoon-Rebirth-Zusatz | 5,0 % | 5,0 % | ja |
| Tycoon-Bonus werkstatt | 10,0 % | 10,0 % | ja |
| Tycoon-Bonus autohaus | 7,5 % | 7,5 % | ja |
| Tycoon-Bonus produktion | 15,0 % | 15,0 % | ja |
| Tycoon-Bonus schrottplatz | 15,0 % | 15,0 % | ja |
| OW-Perk autohaus (Händlerrabatt) | 12,0 % | 25,0 % | ja |
| OW-Perk produktion (Tuning-Tempo) | 20,0 % | 25,0 % | ja |
| OW-Perk schrottplatz (Presse-Schrott) | 20,0 % | 25,0 % | ja |
| OW-Perk werkstatt (Auftragswert) | 24,0 % | 25,0 % | ja |
| Werkstatt-Deckel (GameConfig.WorkshopRewardCap) | ×1,60 | ×1,60 | ja |
| Werkstatt: Tycoon × OW-Perk (gedeckelt) | ×1,36 | ×1,60 | ja |
| Händlerrabatt gesamt (Prestige + Tycoon + OW) | 29,5 % | 30,0 % | ja |
| Tuning-Tempo gesamt (Tycoon × OW) | 38,0 % | 40,0 % | ja |
| Schrott gesamt (Tycoon × OW) | 38,0 % | 40,0 % | ja |
| Tycoon-Rebirth-Boost (%) | 150 % | 150 % | ja |

Höchster Werkstatt-Faktor der Ausbaustufe 4: Tycoon × OW-Perk (gedeckelt) × Prestige = ×1,77 (dazu die ungedeckelten 3.x-Querboni Presse, Tuning-Abteilung, Kundenbonus).

<!-- SIM:END -->

Open-World-Gebäude (Ausbaustufe 4, Meilenstein 6, `GameConfig.OW.Buildings`): Die Erträge sammeln sich höchstens
12 Std. an. Die Tabellen im Block oben rechnen je Minute aktiver Spielzeit. Wer nur einmal am Tag abholt, bekommt
bis zu 12 Std. Ertrag auf einmal (Autohaus Stufe 4: 216.000 Cr). Das ist gewollt: Belohnung fürs Wiederkommen, aber
keine XP.

Story-Missionen (Meilenstein 7): `StoryRules.BalanceCheck()` prüft je Mission `credits / minutes ≤ 0,4 × Werkstatt-Cr/Min`
des Kapitel-Levels (Tabelle oben, interpoliert; `GameConfig.Story.Balance`), und `StoryRules.UnlockCheck()` prüft, dass jede
Mission spätestens auf dem Level ihres Kapitels machbar ist (Freischaltungen aus `GameConfig.Unlocks`); beides abgesichert
in `tests/test_story.lua`. Die Spalte „Level“ der Auto-Tabelle oben ist das Händler-/Auktions-Level aus `GameConfig.Unlocks`
(`Unlocks.CarLevel`, über `tools/economy_dump.lua`), nicht das 2.4.0-Feld `C.Cars[].level`.

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
| `GameConfig.OW.Buildings.autohaus` Stufen-Level (Ausbaustufe 4) | alle ab 10 | 10 / 15 / 25 / 35 | Stufe 4 (300 Cr/Min) war schon auf Level 10 baubar, das wären 37 % der Werkstatt gewesen. Jetzt sind es höchstens 10 %. |
| `GameConfig.Story` Kapitel 1: `c1_m2` / `c1_m3` Credits | 120 / 200 | 100 / 160 | Mit Missions- und Kapitel-XP lagen beide knapp über 40 % der Werkstatt auf Level 1. |
| `GameConfig.Story.Sale`: Gewinn je Preisstufe / XP je Verkauf | 40 / 75 / 130, XP 8 / 12 / 20 | 35 / 60 / 95, XP 6 / 10 / 15 | Der Kiesplatz brachte auf Level 1 53 % der Werkstatt (Stufe „teuer“). Jetzt sind es 39 %. |
| `GameConfig.WorkshopRewardCap` | fehlte (Standard 1,6 im Code) | 1,6 | Der Deckel steht jetzt sichtbar in der Konfiguration. |
| Teststrecke (`CarCatalog.Track`) | 400 / 60 je s / Basis 60 s / Deckel 1.500 / +4 % je Level / 30 XP | 100 / 15 / 30 s / 250 / +10 % / 15 XP | Eine Runde dauert nur 8–16 s. Die alte Basiszeit von 60 s erlaubte einen Topf von rund 3.400 Cr in 3 Min. |

Unverändert blieben die Spielhalle (8 Automaten mit 30–50 Cr bei 1000 Punkten, Tageslimit 1.500 Cr), die
Auktionsregeln (5 % Gebühr, NPC-Startgebot 60 %, NPC-Limits 70–120 % des Richtwerts) und die Tuning-Anteile der
Autos (voller Leistungsausbau ≈ 3,2 × Autowert). Unverändert blieben auch die Waschstraße (150 Cr) und die
2.4.0-Zahlen (Aufträge, XP, Level-Bonus, Geräte, Ausbau).

## Offene Punkte (Code, nicht Zahlen)

0. **Ausbaustufe 4:** (a) Level 90 hängt an der Spielzeit-Annahme (siehe „Warum Level 90 knapp ist“). Eine feste
   Untergrenze bräuchte einen XP-Faktor auf die 2.4.0-Aufträge ab Level 50 (Code). (b) DLC-Autos lassen sich mit
   Robux schon **vor** dem Level des Basismodells kaufen: `ShopRules.CanPrompt` und `ApplyReceipt` prüfen kein Level.
   Für Credits gilt die Sperre. Vorschlag: Prompt erst ab `m.level` (wie `CanBuy`). (c) Passiv **zusammen**
   (Tuning + Presse + alle OW-Gebäude) liegt auf Level 30 bei etwa 26 % der Werkstatt. Jeder Teil für sich bleibt unter
   25 %. Der Treiber ist Punkt 2 (passive Tuning-Rate).

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
