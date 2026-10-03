# Ultimate Car Game 3.x – Spielermeile (Roblox)

Aufbauend auf **Ultimate Car Game 2.4.0** (Schrauberwerkstatt mit 3D-Reparaturen) ist das Spiel eine **begehbare Stadt**
mit Lobby, Story, einem Tycoon-Modus und einem fairen Shop.

## Ausbaustufe 4 (neu)

- **Lobby**: Empfangshalle mit zwei Portalen **„Tycoon“** und **„Open World“**, Einstellungen
  (Einzel-/Mehrspieler, Passiv-Modus, Beginner-Modus), **Party** mit 4-stelligem Code (bis 4 Spieler reisen gemeinsam),
  Tutorial-Kiosk. In Studio werden Ortswechsel simuliert (keine echten Teleports).
- **Tutorial** (11 Schritte, überspringbar, Belohnung einmalig) und **Beginner-Hinweise** als Karten.
- **Freischaltungen** nach Level (Tab „Freischaltungen“) – das letzte Auto, der Nord Elys E9, kommt ab **Level 90**.
- **Prestige-Ränge** ab Level 100 **ohne Reset**: Titel, Kosmetik, kleine Boni; Level, Credits und Autos bleiben.
- **Open World**: eigene Gebäude auf dem Grundstück (Autohaus, Schrottplatz, Produktion) mit Bauzeit, passiven
  Einnahmen und Vorteilen in der Stadt; **Passiv-Modus** zum entspannten Spielen.
- **Story** „Vom Kiesplatzhändler zum Mega-Verkäufer“: 5 Kapitel, Kapitel 1 je Startweg (z. B. am
  **Kiesplatz** Gebrauchtwagen an NPC-Kunden verkaufen), dazu täglich 3 **Nebenmissionen** (u. a. Lieferfahrt) und der Strang „Werkstatt-Legende“.
  Missionen laufen in einer Party gemeinsam (Co-op).
- **Tycoon**: Gebäude wählen (Werkstatt, Autohaus, Produktion, Schrottplatz), mit **Bargeld** über
  Kaufpads bis Stufe 5 ausbauen, mit anderen Spielern handeln, **Rebirth** – jede fertige Runde gibt einen dauerhaften
  Bonus in der Open World.
- **Shop**: Kosmetik (Folierungen, Felgen, Hupen, Reifenspuren), DLC-Autos mit den gleichen Fahrwerten wie ihr
  Basismodell, kosmetische Pässe. Alles auch mit Credits oder als Belohnung erreichbar, **keine Zufallsboxen,
  kein Pay-to-win**. Alle Produkt-IDs sind Platzhalter – nichts ist veröffentlicht.

## Spielermeile-Update (3.x, neu)

- **Story ab dem ersten Moment**: In der Open World wählst du sofort, womit du startest – **Werkstatt**,
  **Verkaufshaus**, **Herstellung** oder **Schrottplatz**. Kapitel 1 hat für jeden Weg eigene Missionen; dein Gebäude
  steht schon auf deinem Grundstück an der **Spielermeile** (so heißt die Hauptstraße jetzt).
- **Große Werkstatt** am Westende der Spielermeile: eigene Autos reparieren (verkaufen sich danach teurer, bis ×1,35)
  und Altteile verkaufen – passt zu Verkaufshaus und Schrottplatz.
- **Flitzer**: winziges, schnelles Startauto für alle. Rufen mit **G** oder Handy → „Auto rufen“.
- **Neue Teststrecke**: großer Grand-Prix-Kurs mit S-Kurve, Haarnadel und 12 Checkpoints.
- **Welt**: Hügelkette mit Bäumen und Felsen als natürlicher Weltrand (niemand fällt herunter), Hochhaus-Skyline am
  Horizont.
- **Verkehr**: weiches Bremsen, mehr Abstand, Autos halten vor der Haltelinie, man läuft nicht mehr durch Autos; die
  Ampeln schalten Grün → Gelb → Rot mit Fußgängerampeln.
- **Entwickler-Menü** (nur für dich): Chat **/dev** oder **Strg+Umschalt+D** → Level, XP, Credits und Tycoon-Bargeld
  setzen, Startweg zurücksetzen. Geht in Studio immer; im veröffentlichten Spiel für den Ersteller und für die UserIds
  in `src/mini/shared/GameConfig.lua` → `GameConfig.Dev.AllowedUserIds = { 123456789 }` (deine UserId steht in der
  Adresse deines Roblox-Profils).

## Werkstatt-Update (3.x)

- **Nur mit E reparieren**: Werkzeug, Hebebühne, Motorhaube und Geräte stellt der Mechaniker beim E-Druck selbst
  (Ölwechsel mit Ölfilter, Endkontrolle mit gehobener Bühne – nichts bleibt mehr hängen).
- **Freie Hand**: fester Platz „Hand“ ganz links in der Werkzeugleiste (**Taste 1**), Werkzeuge auf **2–6**.
- **OBD-Tester** „UCG-Tester 3000“ als echtes Handgerät: Fehlerspeicher, Messwerte, Befund, Endkontrolle.
- **Fahrzeug-Check** liest den Fehlerspeicher. Findet er Fehler, rufst du den Kunden mit dem **Handy** an (**Taste P**,
  wie bei GTA 5) – sagt er Ja, reparierst du gleich mit und bekommst den Check dazu bezahlt.
- **Handy** mit den Apps Kunden, Nachrichten, Aufträge, Karte, Konto und Einstellungen.

**Steuerung:** E = benutzen/arbeiten · F = Hebebühne · H = Motorhaube · 1 = freie Hand · 2–6 = Werkzeuge ·
P = Handy · G = Auto rufen · M = Menü · TAB = Tablet · /dev bzw. Strg+Umschalt+D = Entwickler-Menü.

## Stadt und Minispiele (3.0)

- **Spielermeile**: Jeder Spieler hat seine eigene 2.4.0-Werkstatt (Empfang, Bühnen, Anbauten, Geräte) – acht
  Grundstücke an der Hauptstraße.
- **Stadtplatz** mit Ankunftshalle, Bestenliste und Farbleitsystem; **Schrottplatz** mit Presse und Kran
  (*Schrottpresse*, *Schrottplatz*), **Tuning-Zentrum** (*Tuning-Projekte*), **Meisterschule** (*Quiz*),
  **Parkhaus** (*Parkplatz-Chaos*).
- **Autohaus** mit 9 Modellen und Probefahrt; eigene Autos **selbst fahren** (Federung, Lenkung, Nitro, Tacho) und tunen.
- **Teststrecke**, **Waschstraße**, **Auktionshaus** (NPC- und Spieler-Auktionen), **Spielhalle** mit 8
  Geschicklichkeits-Automaten (Credits nur für Können, Tageslimit, kein Glücksspiel).
- Belebte Straßen: NPC-Verkehr, Ampeln, Kreisverkehre, Licht bei Nacht.

Der Server rechnet alles; der Spielstand bleibt im 2.4.0-Profil (`UltimateCarGame_v2`, nichts geht verloren).
Balance: [docs/BALANCE.md](docs/BALANCE.md) – die Werkstatt bleibt die beste Einnahmequelle.

**Loslegen:** [START_HIER.md](START_HIER.md) · **Studio-Prüfliste:** [STUDIO_TESTS.md](STUDIO_TESTS.md) ·
**Testbericht:** [TESTBERICHT.txt](TESTBERICHT.txt) · **Schnittstellen:** [docs/PHASE4_CONTRACT.md](docs/PHASE4_CONTRACT.md),
[docs/MERGE_CONTRACT.md](docs/MERGE_CONTRACT.md), [docs/PHASE2_CONTRACT.md](docs/PHASE2_CONTRACT.md) ·
**Stadtplan:** [docs/CITY_SPEC.md](docs/CITY_SPEC.md)
