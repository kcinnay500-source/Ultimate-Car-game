# Studio-Prüffolge 3.0

Was die automatischen Tests nicht abdecken können: Rendering, echtes Netzwerk, Live-DataStore und das Touch-Gefühl. Diese Liste in Roblox Studio einmal durchgehen.

## Vorbereitung

1. `Ultimate_Car_Game.rbxlx` in Roblox Studio öffnen (Datei → Öffnen).
2. Für echtes Speichern: Spiel veröffentlichen, dann **Game Settings → Security → Enable Studio Access to API Services** einschalten. Ohne diese Einstellung läuft das Spiel mit einem Sitzungsprofil und zeigt den Hinweis „Speichern nicht aktiv“.
3. **Test → Play** (F5).

## Stadt und Ankunft

- [ ] Beim Start erscheinst du in der Ankunftshalle (hohe Decke, Empfangstresen); danach landest du im Empfang deiner eigenen Werkstatt an der Werkstattmeile.
- [ ] Der Hausnummer-Pylon vor deiner Werkstatt zeigt „WILLKOMMEN, <Name>“; im Meile-Verzeichnis am Stadtplatz steht dein Name.
- [ ] Zu Fuß: vom Stadtplatz zu Schrottplatz, Tuning-Zentrum, Meisterschule, Parkplatz, Autohaus in unter 35 s erreichbar; farbige Bodenlinien führen hin.
- [ ] Kamera in allen Innenräumen (Ankunftshalle, Presse-Halle, Tuning-Zentrum, Spielhalle, Auktionshaus, Meisterschule, Autohaus) ohne Clipping.
- [ ] Animationen: Presse zerdrückt Autos, Magnetkran schwenkt, Drehteller im Autohaus, Brunnen, Ampeln, NPC-Verkehr fährt flüssig, Neon in der Spielhalle, Fenster leuchten nachts.
- [ ] Nachts sind Straßen und Gebäude beleuchtet.
- [ ] Die 2.4.0-Werkstatt funktioniert unverändert: Auftrag annehmen, OBD, Hebebühne (F), Motorhaube (H), Reparatur-QTE, Endkontrolle, Abrechnen, Hallenanbau, Rolltor.
- [ ] Werkstätten auf der Südseite (gedreht): Ankunft, Rolltor und Bühnen funktionieren genauso.
- [ ] Taste **M** öffnet die Minispiele; während einer Reparatur-QTE öffnet es nicht; Tablet (Tab) und Minispiele überlagern sich nicht.
- [ ] Große Zahlen erscheinen als „1,2 Mio.“, „3,5 Mrd.“ usw.

## Schrottpresse

- [ ] Klicks/Tipps aufs Schrottauto: Zahl fliegt hoch, Auto wackelt, Funken, kurzer Klick-Sound.
- [ ] Die Combo steigt bei schnellem Klicken und fällt nach knapp 2 s zurück.
- [ ] Das erste Upgrade (Brecheisen, 8 Schrott) ist nach wenigen Klicks kaufbar.
- [ ] Nach dem Kauf eines Förderbands steigt Schrott auch ohne Klicken.
- [ ] Schrotthändler: Paket verkaufen → Credits steigen, Schrott sinkt; zu teure Pakete sind ausgegraut.
- [ ] Offline: Maschine kaufen, Spiel beenden, einige Minuten warten, neu starten → Hinweis „Während du weg warst: +…“ (nur mit API-Zugriff).
- [ ] Rebirth: ausgegraut unter der Schwelle; ab der Schwelle Bestätigungsdialog; danach Schrott und Presse-Upgrades zurückgesetzt, Credits/Level bleiben.
- [ ] Stresstest: 30 s so schnell wie möglich klicken → keine Ruckler, kein wachsender Speicher (Developer Console → Memory).

## Bestenliste

- [ ] Mit API-Zugriff: nach etwa 1–2 Minuten erscheint der eigene Eintrag im Bereich „Bestenliste“ und auf der Tafel.
- [ ] Ohne API-Zugriff: „Bestenliste gerade nicht verfügbar“ statt eines Fehlers.

## Tuning, Werkstatt, Nebenspiele

- [ ] Tuning: „Folierung“ starten, Countdown läuft; nach 5 Minuten „Abholen“. Passive Einnahmen wachsen.
- [ ] Werkstatt: Auftrag annehmen, Countdown, „Abrechnen“. Hebebühne im Ausbau kaufen → zwei Aufträge gleichzeitig.
- [ ] Schrottplatz: Fahrzeug kaufen, zerlegen → Teile im Lager, Schrott steigt; 5 Teile verkaufen.
- [ ] Quiz: Frage starten, Antwort tippen → grün/rot markiert; die richtige Antwort steht an wechselnden Stellen.
- [ ] Parkplatz: rote Autos wegtippen, dann das gelbe → „Parkplatz frei!“; gelbes Auto bei rotem Weg → „Blechschaden“.

## Ziele

- [ ] Nach einer beliebigen Aktion ist der Tagesauftrag abholbar, danach „Heute erledigt ✓“.
- [ ] Tagesziele zeigen Fortschrittsbalken; erreichte Ziele sind abholbar.
- [ ] Meilenstein „10 Tsd. Schrott gepresst“ wird abholbar, sobald erreicht.
- [ ] „Nächstes Ziel“ im HUD ändert sich nach Käufen und Abholungen; Antippen öffnet den passenden Bereich.

## Geräte und Übergänge

- [ ] Device Emulator: iPhone 14 (390×844) hoch und quer (844×390). Alle Knöpfe sind erreichbar und groß genug, Listen scrollen.
- [ ] Desktop-Fenster klein und groß ziehen: Das Menü bleibt nutzbar (max. 820×700).
- [ ] Menü offen lassen und die Spielfigur zurücksetzen (Reset Character) → Oberfläche bleibt, nichts doppelt.
- [ ] Zwischen Bereichen schnell wechseln, Menü öffnen/schließen → keine hängenden Dialoge.
- [ ] **Test → Server & Clients mit 2 Spielern:** Beide spielen gleichzeitig; Spieler 2 öffnet eine Station, bei Spieler 1 öffnet sich nichts; Werte bleiben getrennt.
- [ ] Spieler verlässt während eines laufenden Tuning-Projekts, tritt wieder bei → Projekt läuft weiter.

## Game Passes (optional)

- [ ] Ohne IDs zeigen beide Pässe „noch nicht eingerichtet“, der Kauf startet nicht.
- [ ] Nach Eintragen echter IDs in `src/shared/Config.lua` (`Config.GamePasses`) und neuem Build startet das Kauffenster.

## Autos, Fahren, Tuning (nur in Studio prüfbar: echte Physik)

- [ ] Autohaus: Komet C1 kaufen (Bestätigung), unter „Meine Autos“ holen – das Auto erscheint am Spawnpunkt.
- [ ] Einsteigen und fahren (WASD / Handy-Steuerung): Federung federt, Räder drehen, Lenkrichtung stimmt, Bremsen und Rückwärts funktionieren; Bordsteine und Einfahrten sind befahrbar.
- [ ] Tacho zeigt km/h, Nitro (N / Knopf) gibt kurz Schub. Jede Karosserie einmal fahren (9 Stück): nichts schlägt aus, kein Kopf durchs Dach.
- [ ] Ein anderer Spieler kann dein Auto nicht fahren. Umgekipptes Auto lässt sich wieder aufrichten.
- [ ] Tuning-Zentrum: Motorstufe kaufen, während man im Auto sitzt → wirkt sofort; Lack/Felgen/Unterbodenlicht/Spoiler ändern sich sichtbar.
- [ ] Probefahrt: 60 s, danach verschwindet das Auto. Waschstraße: Glanz-Effekt.
- [ ] Teststrecke: Zeitfahren starten, Checkpoints zählen, Bestzeit und Belohnung.

## Auktionshaus und Spielhalle

- [ ] NPC-Auktion läuft, Bieten erhöht den Preis, Bildschirm im Saal zeigt Los, Gebot und Zeit; Gewinn landet unter „Meine Autos“.
- [ ] Spieler-Auktion (2 Spieler, veröffentlichtes Spiel mit Speichern): einliefern, bieten, Übergabe von Auto und Credits; Verkäufer verlässt → Auktion abgebrochen.
- [ ] Jeder der 8 Automaten startet, reagiert flüssig auf Maus/Touch und zahlt nach Leistung; Tageslimit greift.
- [ ] Credit-Center öffnet den Credits-Shop (Robux-Produkte erst mit eingetragenen IDs).

## Open World: Gebäude und Passiv-Modus (Ausbaustufe 4, Meilenstein 6)

- [ ] Tab „Gebäude“ (M → Gebäude): vier Karten (Werkstatt = Bühnen, Autohaus, Schrottplatz, Produktion), gesperrte Stufen zeigen „Ab Level n“.
- [ ] Auf Level 10 mit ≥ 12.000 Credits: „Bauen“ beim Autohaus → Credits weg, auf dem eigenen Grundstück (Ostseite neben der Halle) steht eine Baustelle mit Bautafel, deren Countdown jede Sekunde läuft; Tab zeigt Restzeit und Balken.
- [ ] Nach 10 Minuten (oder nach Verlassen/Wiederkommen, Bauzeit läuft offline weiter): Baustelle wird zum Autohaus Stufe 1, Toast + Hinweis „ow_ready“, Neon/Tür/Fahne am Gebäude bewegen sich.
- [ ] „Abholen“ nach einer Weile: Credits gutgeschrieben (25 Cr/Min); zweites Abholen sofort → „nichts abzuholen“. Nach > 12 Std. nur 12 Std. Ertrag.
- [ ] Händlerpreise im Autohaus sind nach dem Bau 3 % günstiger; Tuning-Projekte mit Produktion kürzer; Schrottplatz-Gebäude erhöht Schrott beim Zerlegen und an der Presse (jeweils ≤ +25 %).
- [ ] Passiv-Modus (Schalter im Tab „Gebäude“ oder Lobby-Einstellungen): Story-Start, Kiesplatz-Verkauf und Auktionen antworten mit dem freundlichen Hinweis; Gebäude und Tuning verdienen weiter; Schalter aus → alles wieder offen. Einstellung bleibt nach Neustart.

## Story und Missionen (Meilenstein 7)

- [ ] Tutorial endet jetzt am Kiesplatz (Schritt 11): Schnellreise „Kiesplatz“, E an der Hütte öffnet den Tab „Story“, Belohnung einmalig.
- [ ] Kapitel 1: Mission „Drei Gebrauchtwagen verkaufen“ starten; am Kiesplatz steht ein Kunde (NPC-Figuren wippen leicht), Karte mit Wunsch und drei Preisknöpfen; „günstig“ klappt immer, „teuer“ platzt manchmal (gleicher Kunde = gleiche Antwort), Gewinn wird gutgeschrieben, nächster Kunde nach 45 s. Weit weg vom Kiesplatz: Hinweis, kein Verkauf.
- [ ] Mission „Zurück in die Werkstatt“ wird durch eine echte Abrechnung erledigt; „2.500 Credits“ durch den Kontostand; Abholen gibt Credits + XP, Kapitel 2 ab Level 5 (gesperrt: „Ab Level 5“).
- [ ] Kiesplatz: Kunden kommen nur, solange die Figur am Kiesplatz steht (in der Werkstatt kein „hatte keine Lust mehr“-Hinweis); nach einem Verkauf bringt Lobby-Hin-und-Zurück oder ein Rejoin keinen früheren Kunden (45 s). Die Preistafel neben der Hütte zeigt die drei Preise des aktuellen Kunden, sonst günstig/fair/teuer.
- [ ] Lieferung: mit Vollgas durch das Start- und das Zielfeld fahren (nicht anhalten) – Start und „abgeliefert“ werden trotzdem erkannt.
- [ ] Nebenmissionen: ein abgelehnter Schrott-Tausch (0 Schrott), eine Waschstraße ohne Auto, ein abgebrochener Spielhallen-Automat zählen nicht; nur Nebenmissionen, die das Level schon erlaubt, stehen im Tab.
- [ ] Gebäude: Baustelle läuft (Gebäude-Tab zählt lokal herunter); ein Bau, der offline fertig wird, meldet sich beim nächsten Beitritt mit „fertig gebaut“. Schrottplatz: zweimal kurz hintereinander abholen verliert keine Altteile (Rest wird aufgehoben).
- [ ] Welt-Marker (▼) über dem Ziel der aktiven Mission (Kiesplatz/Empfang/Autohaus …), Missions-Karte oben bei Fortschritt, Kapitel-Intro beim neuen Kapitel.
- [ ] Nebenmissionen: täglich 3 (UTC), z. B. Lieferung: mit dem eigenen Auto auf das Start-Feld „Lieferung“ fahren, Timer läuft, Ziel erreichen → erledigt; Tageslimit 3, am nächsten Tag neue Auswahl. „Werkstatt-Legende“ dauerhaft.
- [ ] Co-op (2 Spieler, Party in der Lobby): beide starten dieselbe Mission, ein Verkauf des einen zählt für beide (Hinweis „Party: … hat … weitergebracht“), jeder holt selbst ab; passives Mitglied bekommt nichts.
