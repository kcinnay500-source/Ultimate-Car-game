# Start hier

## Spielen in Roblox Studio (ohne Werkzeuge)

1. `Ultimate_Car_Game.rbxlx` herunterladen und in Roblox Studio öffnen.
2. **Play** drücken (F5).
3. Unten auf **Minispiele** tippen oder zu einer Station laufen und **E** drücken.

Speichern funktioniert erst, wenn das Spiel veröffentlicht ist und unter **Game Settings → Security → Enable Studio Access to API Services** der API-Zugriff erlaubt ist. Vorher spielt man mit einem Sitzungsprofil, das beim Beenden verfällt.

## Am Code arbeiten

Voraussetzungen: Python 3 und Rust (`cargo`, nur für die Tests).

```bash
# Place aus src/ bauen
python tools/build_place.py Ultimate_Car_Game.rbxlx

# Alles prüfen: Place-Struktur, Luau-Compiler, statische Prüfungen, Tests
python tools/validate.py Ultimate_Car_Game.rbxlx
```

Der erste `validate.py`-Lauf baut den Luau-Runner (`tools/luaurun`, echter Luau-Compiler über `mlua`) einmalig mit cargo.

Einzelne Testdatei ausführen:

```bash
tools/luaurun/target/release/luaurun run tests/run_tests.lua . test_press
```

Alternativ mit Rojo: `rojo serve` nutzt `default.project.json` mit derselben Zuordnung.

## Wo steht was?

| Ordner | Inhalt |
|---|---|
| `src/shared` | reine Formeln und Konfiguration (`Config.lua` enthält alle Spielwerte) |
| `src/server` | Server-Handler je Spiel, Profile, Bestenliste, Welt |
| `src/client` | 2D-Oberfläche je Spiel |
| `tests` | Roblox-Mock und automatisierte Tests |
| `tools` | Build, Validierung, Luau-Runner |
| `docs/PLAN_3.0.md` | Datenmodell, Aktionen, Formeln, Umbenennungen, Abweichungen |
| `STUDIO_TESTS.md` | Prüfliste für Roblox Studio |
| `reference` | HTML-Vorlage |

## Game Passes einrichten

In Roblox zwei Game Passes anlegen und die IDs in `src/shared/Config.lua` bei `Config.GamePasses` eintragen (`DoubleScrap.id`, `PressPlus.id`). Danach den Place neu bauen.
