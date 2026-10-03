# Start hier

## Spielen in Roblox Studio

1. **`Ultimate_Car_Game.rbxlx`** in Roblox Studio öffnen (Datei → Öffnen). Das ist die Datei zum Spielen: Lobby,
   Stadt (Open World) und Tycoon-Gelände sind alle drin.
2. **Test → Play** (F5). Du startest in der **Lobby**.
3. Taste **M** (oder Knopf „Minispiele“) öffnet das Menü. Im Tab **Lobby** wählst du **Open World** oder
   **Tycoon** und drückst **„Los geht's“**. Du kannst auch zu einem der Portale in der Halle laufen und **E** drücken.
4. In der Open World wählst du beim ersten Mal, womit du startest: **Werkstatt**, **Verkaufshaus**, **Herstellung**
   oder **Schrottplatz**. Danach beginnt sofort Kapitel 1 deiner Story (Karte „Deine Mission“ oben links mit
   „Hinreisen“) und dein **Flitzer** fährt vor – ein kleines, schnelles Startauto, das du jederzeit mit **G** (oder
   Handy → „Auto rufen“) holst. Stationen in der Stadt öffnest du mit **E**, Schnellreise im Tab **Stadtplan**. Die
   **Große Werkstatt** (Autos reparieren, Teile verkaufen) steht am Westende der **Spielermeile**.
5. **Tasten in der Werkstatt:** **E** = am markierten Punkt arbeiten (Werkzeug, Hebebühne und Motorhaube kommen
   automatisch) · **1** = freie Hand (nichts in der Hand) · **2–6** = Werkzeuge · **P** = Handy (Kunden anrufen,
   Nachrichten, Aufträge, Karte, Konto, Einstellungen) · **F** = Hebebühne · **H** = Motorhaube · **TAB** = Tablet ·
   **M** = Menü. Findet der OBD-Tester beim Fahrzeug-Check Fehler, ruf den Kunden mit dem Handy an.
6. Zu zweit testen: **Test → Clients und Server**, 2 Spieler, Start. In der Lobby eine Party erstellen und den Code
   beim zweiten Spieler eingeben.

7. **Entwickler-Menü** (nur für dich): im Chat **/dev** schreiben oder **Strg+Umschalt+D** drücken. Dort setzt du
   Level, XP und Credits (Open World und Tycoon), im Tycoon auch das Bargeld, und kannst den Startweg zurücksetzen.
   In Studio geht das immer. Damit es auch im veröffentlichten Spiel für dich geht, trag deine Roblox-UserId in
   `src/mini/shared/GameConfig.lua` ein: `GameConfig.Dev.AllowedUserIds = { 123456789 }` (deine UserId ist die Zahl
   in der Adresse deines Roblox-Profils, `roblox.com/users/<UserId>/profile`) und baue die Place-Dateien neu (unten).
   Der Ersteller des Spiels (bei Gruppenspielen der Gruppenbesitzer) darf es auch ohne Eintrag; alle anderen sehen nichts.

Was du alles ausprobieren kannst, steht als Abhak-Liste in **[STUDIO_TESTS.md](STUDIO_TESTS.md)**.

**Gut zu wissen**

- **Nichts ist veröffentlicht.** Es gibt keine Place-IDs, keine Produkt-IDs, keine Game-Pass-IDs (alles 0).
  Ortswechsel laufen darum in Studio als **Simulation** innerhalb der einen Datei („Studio-Simulation: Ortswechsel ohne
  Teleport“), Robux-Knöpfe zeigen „noch nicht eingerichtet“.
- **In Studio wird nicht gespeichert** (Status „Nur diese Sitzung“). Nach Stop und Play beginnt alles neu. Darum sind in
  Studio auch Dinge gesperrt, die ein gespeichertes Profil brauchen (Gebäude bauen, Handel, Spieler-Auktionen) – du
  bekommst dann einen freundlichen Hinweis. Wer Speichern in Studio testen will: Spiel privat bei Roblox anlegen,
  *Game Settings → Security → Enable Studio Access to API Services* einschalten und in
  `src/garage/shared/Config.lua` `C.SaveInStudio = true` setzen (Studio nutzt dann den eigenen Test-Speicher
  `UltimateCarGame_Studio_v2`). Das veröffentlichte Spiel speichert im DataStore `UltimateCarGame_v2`.

## Die vier Place-Dateien

| Datei | Inhalt | Wofür |
|---|---|---|
| `Ultimate_Car_Game.rbxlx` | alles in einem (Lobby + Stadt + Tycoon) | **zum Spielen und Testen in Studio** |
| `Ultimate_Car_Game_Lobby.rbxlx` | nur die Lobby-Halle | späteres Start-Place beim Veröffentlichen |
| `Ultimate_Car_Game_OpenWorld.rbxlx` | nur die Stadt (Open World) | späteres Place „Open World“ |
| `Ultimate_Car_Game_Tycoon.rbxlx` | nur das Tycoon-Gelände | späteres Place „Tycoon“ |

Alle vier enthalten denselben Code; das Attribut `PlaceKind` an `ReplicatedStorage.GarageShared` sagt dem Spiel, welcher
Teil es ist. Die drei einzelnen Places braucht man erst, wenn das Spiel als Experience mit mehreren Places veröffentlicht wird.

## Später beim Veröffentlichen: wo die IDs hingehören

Alle Platzhalter stehen auf `0`. Nach dem Eintragen einmal neu bauen (siehe unten).

| Was | Datei | Stelle |
|---|---|---|
| Place-IDs (Lobby, Open World, Tycoon) | `src/mini/shared/GameConfig.lua` | `GameConfig.Places = { lobby = 0, openworld = 0, tycoon = 0 }` |
| DLC-Autos und Kosmetik (Developer Products) | `src/mini/shared/GameConfig.lua` | `Shop.Products` → `productId` je Eintrag |
| Kosmetik-Game-Passes („Neon-Paket“, „Werkstatt-Deko“) | `src/mini/shared/GameConfig.lua` | `Shop.Passes` → `id` |
| Credits-Pakete (Robux) | `src/garage/shared/Config.lua` | `C.CreditProducts` → `productId` |
| Presse-Game-Passes | `src/mini/shared/MiniConfig.lua` | `MiniConfig.GamePasses` → `id` |

Robux-Preise stellt man nur auf der Roblox-Website ein; das Spiel liest sie von dort.

## Am Code arbeiten

Voraussetzungen: Python 3 (mit `matplotlib` nur für Vorschaubilder) und Rust/cargo (für den Luau-Runner der Tests).

```bash
python3 tools/build_place.py Ultimate_Car_Game.rbxlx                                   # alles in einem
python3 tools/build_place.py --place lobby     Ultimate_Car_Game_Lobby.rbxlx
python3 tools/build_place.py --place openworld Ultimate_Car_Game_OpenWorld.rbxlx
python3 tools/build_place.py --place tycoon    Ultimate_Car_Game_Tycoon.rbxlx
python3 tools/export_fixture.py                         # Test-Fixture nach Welt-Änderungen erneuern
python3 tools/validate.py Ultimate_Car_Game.rbxlx       # Place, Luau-Compiler, statische Prüfungen, alle Tests
python3 tools/economy_sim.py --check                    # Balance-Grenzen (docs/BALANCE.md)
tools/luaurun/target/release/luaurun run tests/run_tests.lua . <Teil des Testnamens>     # einzelne Tests
```

| Ordner | Inhalt |
|---|---|
| `base/` | Original-Place 2.4.0 (Welt, Autos, Geräte, Licht) |
| `src/garage` | 2.4.0-Skripte (Änderungen mit `-- 3.0:` markiert) |
| `src/mini` | alles Neue: `shared` (Regeln, `GameConfig`, `MiniConfig`, `CarCatalog`), `server` (Dienste), `client` (Oberfläche) |
| `tools/worldgen` | Python-Generator für Stadt, Lobby und Tycoon-Gelände |
| `tests` | Roblox-Nachbildung, die den echten GarageServer/Client ausführt |
| `docs` | Verträge (Schnittstellen), Balance, Stadtplan, Analyse von 2.4.0, Vorschaubilder |

Alle Zahlen (Preise, Level, Belohnungen) stehen in `GameConfig.lua`, `MiniConfig.lua` und `CarCatalog.lua` – nie im Code.
