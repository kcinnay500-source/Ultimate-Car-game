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
