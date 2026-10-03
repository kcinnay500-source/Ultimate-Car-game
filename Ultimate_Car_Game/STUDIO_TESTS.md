# Studio-Prüfliste 3.x (mit Ausbaustufe 4)

Die automatischen Tests (`tools/validate.py`) prüfen Regeln, Server und Oberfläche in einer Nachbildung von Roblox.
Was nur Roblox Studio zeigen kann – Grafik, Licht, echte Physik beim Fahren, Netzwerk mit zwei Spielern,
Handy-Bedienung – steht hier. Einfach von oben nach unten abhaken. Du brauchst keine Programmierkenntnisse.

**So liest du die Liste:** `[ ]` = ausprobieren und abhaken. „Ab Level n“ heißt: Dieser Punkt geht erst, wenn deine
Figur so weit ist. In Studio fängt jeder Test mit Level 1 an (es wird nichts gespeichert, siehe unten). Punkte mit hohem
Level darfst du überspringen und später im veröffentlichten Spiel nachholen.

---

## 0. Vorbereitung

- [ ] Roblox Studio öffnen → **Datei → Öffnen** → `Ultimate_Car_Game.rbxlx` (die Datei „alles in einem“).
      Im Editor siehst du schon die Lobby-Halle (Süden), die Stadt (Mitte) und das Tycoon-Gelände (Norden).
- [ ] **Test → Play** (F5). Nach wenigen Sekunden stehst du in der **Lobby**.
- [ ] Unten am Bildschirm steht der Speicher-Status. In Studio ist das **„Nur diese Sitzung“** – richtig so:
      Studio speichert absichtlich nicht (`C.SaveInStudio = false` in `src/garage/shared/Config.lua`).
- [ ] Optional, nur für den Abschnitt „Speichern und Laden“: Spiel als **privates** Spiel bei Roblox anlegen
      (Datei → Bei Roblox speichern), dann **Game Settings → Security → Enable Studio Access to API Services**
      einschalten und in `src/garage/shared/Config.lua` `C.SaveInStudio = true` setzen und neu bauen. Studio speichert
      dann in einen eigenen Test-Speicher (`UltimateCarGame_Studio_v2`), nie in den echten.
- [ ] Ausgabe-Fenster öffnen (**Ansicht → Ausgabe**). Während aller Tests sollen dort **keine roten Fehler** erscheinen.
      Gelbe „Studio-Simulation“-Hinweise sind in Ordnung.

> **Wichtig für Studio-Tests:** Manche Dinge brauchen ein gespeichertes Profil und sind darum in Studio ohne
> API-Zugriff gesperrt. Dann erscheint eine freundliche Meldung („Dein Profil wird gerade nicht gespeichert …“) –
> das ist **kein Fehler**. Betroffen: Open-World-Gebäude bauen, Handel im Tycoon, Spieler-Auktionen,
> Bestenliste, Robux-Käufe.

---

## 1. Lobby, Einstellungen und Party

- [ ] Die Lobby-Halle ist hell, hat eine hohe Decke, zwei große Portale **„Tycoon“** und **„Open World“**,
      ein Einstellungs-Terminal, eine Party-Tafel und einen Tutorial-Kiosk. Der Drehteller mit dem Ausstellungsauto dreht sich.
- [ ] Taste **M** (oder Knopf „Minispiele“) öffnet das Menü. Der Tab **„Lobby“** zeigt: Modus-Karten, Einstellungen,
      Party, Tutorial.
- [ ] An einem Portal **E** drücken → die passende Modus-Karte ist ausgewählt.
- [ ] Einstellungen umschalten: **Einzelspieler/Mehrspieler**, **Passiv-Modus An/Aus**, **Beginner-Modus An/Aus**.
      Der Schalter wechselt sofort; ein kurzer Hinweis bestätigt es.
- [ ] Ohne Party: „Los geht's“ reist in den gewählten Modus (siehe Abschnitt 2).
- [ ] In der Open World und im Tycoon gibt es den Knopf **„Zurück zur Lobby“** – er bringt dich zurück.

**Party mit 2 Spielern** (Studio: **Test → Clients und Server**, Anzahl **2 Spieler**, **Start**):

- [ ] Spieler 1: Lobby-Tab → **„Party erstellen“** → ein Code mit 4 Zeichen erscheint („Code: ABCD · 1/4“).
- [ ] Spieler 2: Code ins Feld „Party-Code“ tippen → **„Beitreten“** → beide sehen „2/4“ und beide Namen.
- [ ] Spieler 2 sieht: „Nur der Party-Leiter startet die Reise – du reist automatisch mit.“
- [ ] Spieler 1 wählt Open World → „Los geht's“ → **beide** landen in der Stadt.
- [ ] Spieler 2 geht allein „Zurück zur Lobby“ → die Party bleibt bestehen. Spieler 2 drückt „Los geht's“ →
      „Dein Party-Leiter ist schon dort – du reist zu ihm.“ und landet bei Spieler 1.
- [ ] Spieler 1 entfernt Spieler 2 (**„Entfernen“**) → Spieler 2 ist in keiner Party mehr.
- [ ] **„Party verlassen“** funktioniert; wenn der Leiter geht, bekommt das andere Mitglied die Leitung oder die Party löst sich auf.
- [ ] Beide Spieler sehen sich gegenseitig; Werte (Credits, Level) bleiben getrennt. Öffnet Spieler 2 eine Station,
      öffnet sich bei Spieler 1 nichts.

## 2. Studio-Simulation der Ortswechsel

In Studio gibt es keine echten Teleports zwischen Places. Das Spiel versetzt dich stattdessen innerhalb der einen Datei.

- [ ] Lobby → Open World: kurzer Hinweis **„Studio-Simulation: Ortswechsel ohne Teleport“**, du stehst danach in der Stadt
      (mit laufendem Tutorial: im Empfang deiner eigenen Werkstatt).
- [ ] Lobby → Tycoon: Hinweis, du stehst auf dem **Tycoon-Gelände** (Norden).
- [ ] Aus der Lobby oder dem Tycoon im Menü **Stadtplan** ein Ziel wählen (oder im Tablet „Zum Empfang“) →
      du wechselst automatisch in die Open World und reist hin.
- [ ] Nach jedem Wechsel ist die Oberfläche vollständig, nichts doppelt, keine roten Fehler.
- [ ] Optional: die Einzel-Places `Ultimate_Car_Game_Lobby.rbxlx`, `…_OpenWorld.rbxlx`, `…_Tycoon.rbxlx` öffnen und
      **Play** drücken. Jeder startet direkt in seinem Bereich. Ein Wechsel in einen Bereich, der in dieser Datei fehlt,
      zeigt nur einen Hinweis (ohne eingetragene Place-IDs gibt es kein Ziel) – kein Fehler, kein Hängenbleiben.

## 3. Tutorial und Beginner-Hinweise

- [ ] Erster Wechsel in die Open World: Tutorial-Karte erscheint (Schritt 1 von 11). Du stehst in deiner Werkstatt.
- [ ] Die Schritte der Reihe nach: laufen → Menü öffnen (M) → Empfang (E) → Auftrag annehmen → OBD → Reparatur →
      Abrechnen → Stadtplan-Reise → Autohaus ansehen (E) → Ziele an der Infotafel → **Kiesplatz** (Schnellreise, E an der Hütte).
- [ ] Pfeil/Marker zeigt jeweils zum Ziel; „Weiter“ gibt es nur bei reinen Lese-Schritten.
- [ ] Ende: **500 Credits + 60 XP**, Tab „Story“ öffnet sich.
- [ ] **„Überspringen“** beendet das Tutorial sofort (ohne Belohnung).
- [ ] Lobby → Tutorial-Kiosk → **„Tutorial erneut starten“** → beginnt bei Schritt 1, am Ende **keine** zweite Belohnung.
- [ ] Während man in Lobby oder Schnellem Spiel ist, ruht das Tutorial („es geht in der Werkstattmeile weiter“).
- [ ] Beginner-Modus an: Beim ersten Besuch einer Station/einer neuen Freischaltung erscheint oben rechts eine Hinweiskarte,
      jede nur einmal. Mehrere Karten kommen nacheinander, keine überdeckt eine andere oder die Toasts.
- [ ] Beginner-Modus aus: keine Hinweiskarten mehr.

## 4. Freischaltungen und Prestige

- [ ] Tab **„Freischaltungen“**: Tabelle Level → Freischaltung, erreichte Einträge markiert. Im HUD steht
      „Nächste Freischaltung: … (Level n)“.
- [ ] Gesperrte Stationen (z. B. Schrottpresse vor Level 2, Spielhalle vor Level 10) zeigen „Ab Level n“ statt eines Fehlers.
- [ ] Beim Levelaufstieg auf ein Level mit Freischaltung erscheint die Karte **„Neu freigeschaltet“** mit Effekt.
- [ ] Autohaus: Komet C1 ab Level 3 … **Nord Elys E9 erst ab Level 90**; gesperrte Autos zeigen ihr Level.
- [ ] Tab **„Prestige“**: Rang 0, „Rang 1 ab Level 100“. Es gibt **keinen Reset** – nirgends wird Level oder Geld gelöscht.
- [ ] (Ab Level 100, nur im veröffentlichten Spiel realistisch) Belohnung abholen → Titel, Kosmetik, Bonus; zweites Abholen geht nicht.

## 5. Werkstatt (2.4.0)

- [ ] Empfang (E): Auftrag annehmen → Kundenauto fährt vor.
- [ ] OBD-Gerät anschließen, Fehler finden; Hebebühne (**F**), Motorhaube (**H**); Reparatur-QTE; Endkontrolle; **Abrechnen**.
- [ ] Hallenanbau kaufen (zweite Bühne) → neuer Hallenabschnitt erscheint, zwei Aufträge gleichzeitig möglich.
- [ ] Rolltor öffnet/schließt; Werkzeugleiste **1–5**, **TAB** öffnet das Tablet.
- [ ] Werkstätten auf der Südseite (gedreht): Ankunft, Rolltor und Bühnen funktionieren genauso.
- [ ] Während einer Reparatur-QTE öffnet **M** das Menü nicht; Tablet (TAB) und Menü überlagern sich nicht.

## 6. Stadt und Minispiele

- [ ] Der Hausnummer-Pylon vor deiner Werkstatt zeigt „WILLKOMMEN, <Name>“; im Meile-Verzeichnis am Stadtplatz steht dein Name.
- [ ] Zu Fuß: vom Stadtplatz zu Schrottplatz, Tuning-Zentrum, Meisterschule, Parkplatz, Autohaus in unter 35 s; farbige
      Bodenlinien führen hin. Tab **„Stadtplan“** bietet Schnellreise.
- [ ] Kamera in allen Innenräumen (Ankunftshalle, Presse-Halle, Tuning-Zentrum, Spielhalle, Auktionshaus, Meisterschule,
      Autohaus) ohne Clipping.
- [ ] Animationen: Presse zerdrückt Autos, Magnetkran schwenkt, Drehteller im Autohaus, Brunnen, Ampeln, NPC-Verkehr fährt
      flüssig, Neon in der Spielhalle. Nachts sind Straßen und Gebäude beleuchtet.
- [ ] Große Zahlen erscheinen als „1,2 Mio.“, „3,5 Mrd.“ usw.
- [ ] **Schrottpresse** (ab Level 2): Klick aufs Schrottauto → Zahl fliegt hoch, Auto wackelt, Funken, Klick-Sound; Combo
      steigt bei schnellem Klicken. Erstes Upgrade (Brecheisen) nach wenigen Klicks kaufbar; Förderband erzeugt Schrott ohne
      Klicken. Schrotthändler: Paket verkaufen → Credits steigen. Rebirth erst ab Schwelle, mit Bestätigung.
- [ ] Stresstest: 30 s so schnell wie möglich klicken → keine Ruckler (Developer Console → Memory wächst nicht dauernd).
- [ ] **Schrottplatz** (ab Level 3): Fahrzeug kaufen, zerlegen → Teile im Lager; 5 Teile verkaufen.
- [ ] **Quiz** (ab Level 4): Antwort tippen → grün/rot; die richtige Antwort steht an wechselnden Stellen.
- [ ] **Parkplatz** (ab Level 5): rote Autos wegtippen, dann das gelbe → „Parkplatz frei!“.
- [ ] **Tuning-Projekte** (ab Level 6): Projekt starten, Countdown, nach Ablauf „Abholen“.
- [ ] **Ziele**: Tagesauftrag abholbar, danach „Heute erledigt ✓“; Tagesziele mit Balken; „Nächstes Ziel“ im HUD führt
      zum passenden Bereich.
- [ ] **Bestenliste**: ohne Speichern „Bestenliste gerade nicht verfügbar“ statt eines Fehlers.

## 7. Autos, Fahren, Tuning, Teststrecke (echte Physik – nur in Studio prüfbar)

- [ ] Autohaus (ab Level 3): Komet C1 kaufen (Bestätigung), unter „Meine Autos“ holen – das Auto erscheint am Spawnpunkt.
- [ ] Einsteigen und fahren (WASD / Handy-Steuerung): Federung federt, Räder drehen, Lenkrichtung stimmt, Bremsen und
      Rückwärts funktionieren; Bordsteine und Einfahrten sind befahrbar.
- [ ] Tacho zeigt km/h, Nitro (**N** / Knopf) gibt kurz Schub. Lichthupe (**H** / Knopf „HUPE“) blinkt die Scheinwerfer.
- [ ] Jede Karosserie einmal fahren (wenn erreichbar): nichts schlägt aus, kein Kopf durchs Dach.
- [ ] Ein anderer Spieler kann dein Auto nicht fahren. Umgekipptes Auto lässt sich wieder aufrichten.
- [ ] Tuning-Zentrum: Motorstufe kaufen, während man im Auto sitzt → wirkt sofort; Lack/Felgen/Unterbodenlicht/Spoiler
      ändern sich sichtbar.
- [ ] Probefahrt: 60 s, danach verschwindet das Auto. Waschstraße (ab Level 8): Glanz-Effekt.
- [ ] Teststrecke (ab Level 8): Zeitfahren starten, Checkpoints zählen, Bestzeit und Belohnung.

## 8. Auktionshaus (ab Level 12)

- [ ] NPC-Auktion läuft, Bieten erhöht den Preis, der Bildschirm im Saal zeigt Los, Gebot und Restzeit; ein Gewinn landet
      unter „Meine Autos“.
- [ ] Spieler-Auktion (ab Level 20, 2 Spieler, nur mit Speichern): einliefern, bieten, Übergabe von Auto und Credits;
      Verkäufer verlässt → Auktion abgebrochen. DLC-Autos lassen sich nicht einliefern.
- [ ] Passiv-Modus an → Bieten und Einliefern antworten mit dem freundlichen Passiv-Hinweis.

## 9. Spielhalle (ab Level 10)

- [ ] Jeder der 8 Automaten startet, reagiert flüssig auf Maus/Touch und zahlt nach Leistung; das Tageslimit greift.
- [ ] Ein abgebrochener Automat zahlt nichts und zählt nicht für Nebenmissionen.

## 10. Open-World-Gebäude und Passiv-Modus

- [ ] Tab **„Gebäude“**: vier Karten (Werkstatt = Hebebühnen, Autohaus, Schrottplatz, Produktion). Gesperrte zeigen „Ab Level n“.
- [ ] (Ab Level 10, mit 12.000 Credits, **nur mit Speichern**) „Bauen“ beim Autohaus → Credits weg, auf deinem Grundstück
      (Ostseite neben der Halle) steht eine Baustelle mit Bautafel und Countdown; der Tab zeigt Restzeit und Balken.
- [ ] Nach 10 Minuten (auch offline): Baustelle wird zum Autohaus Stufe 1, Hinweis „fertig gebaut“, Neon/Tür/Fahne bewegen sich.
- [ ] „Abholen“ nach einer Weile: Credits gutgeschrieben; sofort noch einmal → „nichts abzuholen“.
- [ ] Händlerpreise im Autohaus sind danach etwas günstiger; Produktion verkürzt Tuning-Projekte; eigener Schrottplatz
      bringt mehr Schrott (jeweils höchstens +25 %).
- [ ] Ohne Speichern (normales Studio): „Bauen“ zeigt „Dein Profil wird gerade nicht gespeichert – bauen ist jetzt nicht
      möglich.“ – kein Fehler, kein Credit-Abzug.
- [ ] **Passiv-Modus** (Schalter im Tab „Gebäude“ oder in der Lobby): Story-Start, Kiesplatz-Verkauf und Auktionen antworten
      mit dem Passiv-Hinweis; Tuning und Gebäude verdienen weiter; Abholen geht. Schalter aus → alles wieder offen.

## 11. Story Kapitel 1 am Kiesplatz, Nebenmissionen, Lieferfahrt

- [ ] Stadtplan → **Kiesplatz** (Stadtrand) → **E** an der Hütte öffnet den Tab **„Story“**: Kapitel 1 „Der Kiesplatz“.
- [ ] Mission **„Drei Gebrauchtwagen verkaufen“** starten. Am Kiesplatz steht ein Kunde (Figur wippt leicht); eine Karte
      zeigt Name, Wunsch und drei Preisknöpfe (günstig/fair/teuer).
- [ ] „Günstig“ klappt immer; „teuer“ platzt manchmal – derselbe Kunde gibt immer dieselbe Antwort. Gewinn wird
      gutgeschrieben, der nächste Kunde kommt nach etwa 45 s.
- [ ] Die Preistafel neben der Hütte zeigt die drei Preise des aktuellen Kunden.
- [ ] Weit weg vom Kiesplatz: Hinweis, kein Verkauf. In der Werkstatt kommt keine Meldung „hatte keine Lust mehr“.
- [ ] Nach einem Verkauf bringt Lobby-hin-und-zurück keinen früheren Kunden (Wartezeit bleibt).
- [ ] Mission **„Zurück in die Werkstatt“**: wird durch eine echte Abrechnung erledigt.
- [ ] Mission **„Die ersten 2.500 Credits“**: erledigt durch den Kontostand. **„Abholen“** gibt Credits + XP.
- [ ] Kapitel 2 zeigt „Ab Level 5“, solange das Level fehlt.
- [ ] Welt-Marker (▼) über dem Ziel der aktiven Mission; Missions-Karte oben bei Fortschritt; Kapitel-Intro beim neuen Kapitel.
- [ ] **Nebenmissionen** (im Tab „Story“): täglich 3, nur solche, die dein Level schon erlaubt. Ein abgelehnter
      Schrott-Tausch, eine Waschstraße ohne Auto oder ein abgebrochener Automat zählen nicht.
- [ ] **Lieferfahrt** (Nebenmission „Lieferung“, eigenes Auto nötig): auf das Start-Feld „Lieferung“ fahren → Timer läuft →
      Zielfeld erreichen → erledigt. Auch mit Vollgas durch beide Felder (ohne anzuhalten) wird es erkannt.
- [ ] **Co-op** (2 Spieler in einer Party, siehe Abschnitt 1): beide starten Mission 1, ein Verkauf des einen zählt für
      beide (Hinweis „Party: … hat … weitergebracht“), jeder holt selbst ab. Ein Mitglied im Passiv-Modus bekommt nichts.

## 12. Tycoon

- [ ] Lobby → Modus **„Tycoon“** → „Los geht's“ → du stehst auf dem Tycoon-Gelände; dein Grundstück trägt ein
      Schild mit deinem Namen.
- [ ] Start-Pad (E) auf deinem Grundstück oder Tab **„Tycoon“** → **Gebäude wählen**: Werkstatt, Autohaus,
      Produktion oder Schrottplatz. Du startest sofort auf Stufe 1 mit 50 Bargeld.
- [ ] Am Start-Pad eines **fremden** Grundstücks: Hinweis „Das ist nicht dein Grundstück. Deins ist Nr. …“, nichts passiert.
- [ ] **Kaufpads**: drauflaufen → Upgrade gekauft (Pad wird grün), Bargeld sinkt; zu teure Pads sind orange/grau und
      reagieren mit Hinweis. Neue Teile erscheinen sichtbar.
- [ ] **Bargeld**: Der Behälter füllt sich („Behälter: x / y“); Sammel-Pad oder Knopf **„Sammeln“** → Bargeld steigt.
      Bargeld ist nie Credits (Credits-Anzeige ändert sich nicht).
- [ ] **Stufen**: Wenn alle Upgrades einer Stufe gekauft sind, erscheint das Stufen-Pad → Stufe 2 … 5; jede Stufe ist
      sichtbar größer (Halle, Anbau, Schild, Licht).
- [ ] Verlassen und wieder in den Tycoon: Die Runde läuft an derselben Stufe weiter (innerhalb der Studio-Sitzung).
- [ ] **Handel** (2 Spieler, beide im Tycoon, nur mit Speichern): Ware, Menge und Preis wählen, „An: Spieler“ →
      der andere sieht das Angebot und kann **„Annehmen“**; Ware und Bargeld wechseln den Besitzer. **„Zurückziehen“**
      löscht das eigene Angebot; nach 120 s verfällt es. Ohne Speichern: freundlicher Hinweis statt Handel.
- [ ] **Rebirth**: Knopf erst bei Stufe 5 mit allen Upgrades aktiv („Noch: …“ erklärt, was fehlt). Danach Bestätigung →
      Gebäude zurückgesetzt, Bargeld weg, +15 % Einkommen in der nächsten Runde.
- [ ] **Bonus in der Open World**: Nach einem Rebirth zeigt der Tab „Tycoon“ den Bonus (z. B. Werkstatt
      +2 % Vergütung je fertiger Runde, höchstens 5 Runden). In der Werkstatt ist die Abrechnung entsprechend höher.
      (Eine ganze Runde dauert etwa 5 Stunden – in Studio nur, wenn du Zeit hast.)
- [ ] „Abbrechen“ (mit Bestätigung) beendet die Runde ohne Bonus.

## 13. Shop

- [ ] Credit-Center in der Stadt (E) oder Tab **„Shop“**: Bereiche Credits, Autos, Kosmetik, Pässe.
- [ ] **Kosmetik kaufen**: z. B. „Goldfelgen“ (1.200 Credits) → „Gekauft: Goldfelgen!“, Credits sinken. Zweiter Kauf → „Das hast du schon.“
- [ ] **Kosmetik anlegen**: „Anlegen“ → am eigenen Auto sind die Felgen sofort golden (auch wenn es schon steht).
      „Ablegen“ → wieder normal. Folierungen zeigen Streifen/Karo/Flammen aus Teilen am Auto.
- [ ] Hupen-Kosmetik: beim Hupen (**H**) erscheint die Sprechblase in der gewählten Farbe.
- [ ] **DLC-Auto mit Credits** (ab dem Level des Basismodells, z. B. Komet S2 Sunset ab Level 8): Kauf → „Dein neues Auto
      steht in der Garage“; es fährt genau wie ein Komet S2 (kein Vorteil). Es lässt sich nicht versteigern.
- [ ] **Robux-Knöpfe** (Credits-Pakete, DLC-Autos, Kosmetik, Game Passes): zeigen
      **„Dieser Kauf ist noch nicht eingerichtet …“** – es öffnet sich kein Kauffenster. Es gibt keine Zufallsboxen.

## 14. Speichern und Laden

Ohne die optionale Vorbereitung (API-Zugriff + `C.SaveInStudio = true`) wird in Studio nichts gespeichert – nach Stop
und Play beginnt alles neu. Das ist gewollt.

Mit Speichern:

- [ ] Etwas verdienen, Kosmetik kaufen, Einstellungen ändern, eine Tycoon-Runde starten → **Stop** → **Play**:
      Credits, Level, Kosmetik, Einstellungen, Story-Fortschritt und Tycoon-Runde sind wieder da.
- [ ] Gebäude-Bau starten, Stop, 10 Minuten warten, Play → „fertig gebaut“.
- [ ] Beim Wiederkommen in die Open World landest du im zuletzt gespielten Modus.
- [ ] Spieler verlässt während eines Tuning-Projekts, tritt wieder bei → Projekt läuft weiter.

## 15. Geräte und Übergänge

- [ ] Device Emulator: iPhone 14 (390×844) hoch und quer (844×390). Alle Knöpfe sind erreichbar, Listen scrollen.
- [ ] Desktop-Fenster klein und groß ziehen: das Menü bleibt nutzbar.
- [ ] Menü offen lassen und die Figur zurücksetzen (Reset Character) → Oberfläche bleibt, nichts doppelt.
- [ ] Schnell zwischen Bereichen und Modi wechseln, Menü öffnen/schließen → keine hängenden Dialoge.
