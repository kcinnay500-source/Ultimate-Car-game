# Start hier

## Spielen in Roblox Studio

1. `Ultimate_Car_Game.rbxlx` in Roblox Studio öffnen. Die Stadt ist schon im Editor sichtbar.
2. **Play** (F5). Du erscheinst in der Ankunftshalle, danach bringt dich das Spiel in den Empfang deiner eigenen Werkstatt.
3. Minispiele: zu einer Station gehen und **E** drücken, oder Taste **M** / Knopf „Minispiele“. Der Tab **Karte** bietet Schnellreise.

In Studio wird nicht gespeichert (wie in 2.4.0). Nach dem Veröffentlichen speichert das Spiel im DataStore `UltimateCarGame_v2`.

## Am Code arbeiten

Voraussetzungen: Python 3 (mit `matplotlib` nur für Vorschaubilder) und Rust/cargo (für den Luau-Runner der Tests).

```bash
python tools/build_place.py Ultimate_Car_Game.rbxlx    # Basisplace 2.4.0 + src/ + Stadt (tools/worldgen)
python tools/export_fixture.py                         # Test-Fixture nach Welt-Änderungen erneuern
python tools/validate.py Ultimate_Car_Game.rbxlx       # Place, Luau-Compiler, statische Prüfungen, Tests
python tools/worldgen/render.py Ultimate_Car_Game.rbxlx --plots   # Draufsicht nach /tmp/claude-0/renders
```

| Ordner | Inhalt |
|---|---|
| `base/` | Original-Place 2.4.0 (Welt, Autos, Geräte, Licht) |
| `src/garage` | 2.4.0-Skripte (Änderungen mit `-- 3.0:` markiert) |
| `src/mini` | Minispiele: shared (Regeln), server (Dienste), client (UI, Stadt-Animationen) |
| `tools/worldgen` | Python-Generator der Stadt; `design/` = geprüfter Stadtplan |
| `tests` | Roblox-Mock, der den echten GarageServer/Client ausführt |
| `docs` | Stadtplan, Schnittstellen-Vertrag, Analyse von 2.4.0, Vorschaubilder |

Game Passes: IDs in `src/mini/shared/MiniConfig.lua` eintragen. Credits-Produkte (Robux): IDs in `src/garage/shared/Config.lua` → `C.CreditProducts`.
