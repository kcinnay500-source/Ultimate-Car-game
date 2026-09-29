# Integrations-Vertrag 3.0 (2.4.0-Welt + Minispiele + Stadt)

Dieser Vertrag legt fest, wie die Teile zusammenpassen. Alle Agenten und Menschen, die am Merge arbeiten, halten sich daran. Änderungen an diesem Vertrag nur durch den Leiter.

Hintergrund: `docs/analysis_2.4.0/*.md` (server, shared, client, world, merge, critic) beschreibt 2.4.0 vollständig. Zeilennummern dort beziehen sich auf die unveränderten Skripte (heute `src/garage/**`).

## 0. Leitlinien

1. **2.4.0 bleibt funktionsfähig.** Reparaturablauf, OBD, Werkzeugkiste, E/F/H, Interaktions-Token, Hebebühnen, Anbauten, Geräte, Teilehandel, Lieferungen, Rolltor, Tag/Nacht, Credits-Shop, Developer Products. Eingriffe in `src/garage/**` sind minimal, kommentiert und nötig.
2. **Ein Profil.** Nur `src/garage/server/Profiles.lua` spricht mit dem Profil-DataStore (`UltimateCarGame_v2`, Schlüssel `Player_<id>`, Hülle `{version=2,data,receipts,lock}`). `data.version` bleibt 2. Minispiel-Daten liegen in `data.games` (whitelist-normalisiert).
3. **Ein Eingang.** Alle Client-Absichten laufen über `GarageShared.Remotes.Command` und `request()` in `GarageServer` (Budget, `transacting`-Sperre, Arg-Filter). Server → Client über `GarageShared.Remotes.Event`. Keine neuen Remotes.
4. **Serverautorität.** Der Client sendet nie Beträge, Preise, Ergebnisse oder Zeitstempel.
5. **Keine externen Assets** (`rbxassetid://` verboten). Animationen prozedural (TweenService, PivotTo, CFrame).
6. **Deutsch** in allen sichtbaren Texten.

## 1. Dateien und Module

| Ordner | Ziel im Place | Inhalt |
|---|---|---|
| `src/garage/shared` | `ReplicatedStorage.GarageShared` | 2.4.0 Config, Rules, Locale |
| `src/garage/server` | `ServerScriptService.Garage` | 2.4.0 GarageServer (Script), Profiles, Purchases, CarFactory, World |
| `src/garage/client` | `StarterPlayer.StarterPlayerScripts` | 2.4.0 GarageClient (LocalScript), ClientEffects, InputController |
| `src/mini/shared` | `ReplicatedStorage.GarageShared.Mini` | MiniConfig, MiniCatalog, MiniLocale, MiniNet, MiniRules, PressRules, TuningRules, SideGameRules, GoalRules, CrossBonus, MiniSnapshot |
| `src/mini/server` | `ServerScriptService.Garage.Mini` | MiniService, PressService, TuningService, SideGamesService, GoalsService, LeaderboardService, MiniPasses, CityService |
| `src/mini/client` | `StarterPlayer.StarterPlayerScripts.Mini` | MiniClient, MiniUI, MiniRemote, MiniEffects, OverviewUI, PressUI, TuningUI, ScrapyardUI, QuizUI, ParkingUI, GoalsUI, LeaderboardUI, MapUI, ShopUI, CityClient |

- Die alten 3.0-Ordner `src/shared`, `src/server`, `src/client` verschwinden (Inhalt wandert nach `src/mini/*` mit neuen Namen). Entfällt ganz: 2D-Werkstatt (`WorkshopRules` außer Boni → `CrossBonus`, `WorkshopService`, `WorkshopUI`), 3.0 `Profiles`, `World`, `Main.server`, `Core`, `Actions`, `DataUtil`, `Main.client`, `Remote`.
- Modulnamen sind im ganzen Place eindeutig (daher `Mini*`-Präfix für Config/Locale/Net/Rules/Snapshot/UI/Remote/Effects).
- Mini-Shared-Module laden sich gegenseitig mit `require(script.Parent:WaitForChild("X"))`, die 2.4.0-Module mit `require(script.Parent.Parent:WaitForChild("Rules"))` bzw. `"Config"`.
- `tools/build_place.py` baut Basisplace + `src/**` + `tools/worldgen` (Welt). `python tools/build_place.py --roundtrip` muss mit unverändertem `src/garage` byte-identisch bleiben (Test gegen die Basis-Skripte nur solange `src/garage` unverändert ist; danach wird die Prüfung auf „nur Skripte geändert“ umgestellt).

## 2. Daten (`data` = `profile.data` von 2.4.0)

| 3.0 bisher | 3.0 jetzt |
|---|---|
| `p.credits` | `d.money` (Änderungen nur über einen Helfer, der auf `C.NumberCap` deckelt) |
| `p.level`, `p.xp`, `Rules.GainXP` | `d.level`, `d.xp`, `MiniRules.GainXP(d, n)` → ruft `R.GainXP` und liefert `{levels, credits}` |
| `games.reputation`, `games.toolLevel` | `d.reputation`, `d.toolLevel` (2.4.0) |
| `games.bays/offerSlots/jobs/offers/nextId` | entfällt |
| `games.parts` | `d.games.parts` („Altteile“) |
| `press, tuning, scrapyard, quiz, parking, stats, milestones, daily, tuningLevel, scrapyardLevel` | `d.games.*` |
| `schema`, `_lock` | entfällt |

- `R.NewData` legt `games = MiniRules.DefaultGames()` an. `R.LoadData` setzt `d.games = MiniRules.LoadGames(raw.games, d, now)` (vor `R.Advance`). Idempotent, whitelist, NaN/inf/negativ → Standard.
- Erstmaliges Anlegen für Veteranen: `stats.jobsDone = d.completed`.
- `Profiles.Save` speichert nur, wenn `MiniRules.IsClean(data)`.
- Verschachtelungstiefe von `games` ≤ 5 (Grenze von `R.Snapshot` ist 12).

## 3. Server-Anbindung (`MiniService`)

`GarageServer` ruft:

| Stelle | Aufruf |
|---|---|
| nach dem Laden der Module | `Mini.Init({emit=emit, toast=toast, changed=changed, push=push, getSession=getSession, moveTo=moveTo, now=now})` |
| `request()` vor `act()` | `if Mini.Handles(action) then return Mini.Handle(p, action, a) end` (Mini-Aktionen sind vom 0,12-s-Namens-Cooldown ausgenommen; Budget, `transacting`-Sperre und Arg-Filter gelten) |
| `act 'hello'` | `Mini.Hello(p)` |
| `act 'settle'` nach Erfolg | `Mini.OnSettled(p)` |
| `act 'yard'` nach Erfolg | `Mini.OnActivity(p)` |
| `join()` nach Profil und Plot | `Mini.OnJoin(p)` |
| 0,5-s-Tick je Sitzung | `Mini.Tick(p, now)` (auch während `transacting`: Produktion wird angesammelt, Geld aber nicht verändert) |
| `PlayerRemoving` vor `P.Save` | `Mini.OnLeave(p, wasWritable)` |
| `BindToClose` je Sitzung | `Mini.OnLeave(p, wasWritable)` |
| `character()` nach `moveTo(home)` (Ausbaustufe 4) | `Mini.OnCharacter(p)` – Lobby/Tycoon-Spieler werden zur Zonen-Ankunft versetzt (`LobbyService.OnCharacter`), Open World bleibt in der Werkstatt |
| `W.Create`-Rückruf `station` und `act 'travel'` (Ausbaustufe 4) | `Mini.OnStation(p, key)` – Tutorial-Schritt `station:<key>` und Beginner-Hinweis (`TutorialService.OnStation`) |

- `Mini.Handle` prüft Nutzlast gegen `MiniNet.Actions`, dedupliziert per `rid`, ruft den Handler in `pcall`. Ändert ein Handler `d.money`, ruft er `ctx.changed(p)`, sonst markiert er den Mini-Snapshot als geändert.
- Geldänderungen durch Minispiele nur innerhalb von `request()` (also nie während `transacting`). Offline- und Tick-Erträge der Presse sind Schrott, nicht Geld.
- Game Passes: `MiniPasses` (UserOwnsGamePassAsync, PromptGamePassPurchaseFinished). `MarketplaceService.ProcessReceipt` gehört allein `Purchases`.
- Bestenliste: `LeaderboardService` schreibt nur bei `wasWritable`/`profile.writable` (in Studio nie), liest max. 1×/60 s, schreibt max. 1×/120 s je Spieler.

### Aktionen (Client → Server, `Command:FireServer(name, flatTable)`)

Flache Nutzlast (≤ 10 Schlüssel, nur string/number/boolean), dazu optional `rid` (number).

`mini_press_click {count}`, `mini_press_buy {id, level}`, `mini_press_exchange {index}`, `mini_press_rebirth {rebirths}`, `mini_tuning_start {id}`, `mini_tuning_collect {slot}`, `mini_tuning_idle`, `mini_upgrade {key, level}` (nur `tuningLevel`, `scrapyardLevel`), `mini_scrapyard_buy`, `mini_scrapyard_dismantle`, `mini_scrapyard_sell`, `mini_quiz_new`, `mini_quiz_answer {token, choice}`, `mini_parking_new`, `mini_parking_tap {cell}`, `mini_daily_claim`, `mini_daily_goal_claim {id}`, `mini_milestone_claim {id}`, `mini_leaderboard_refresh`, `mini_pass_prompt {pass}`, `mini_travel {key}`, `mini_sync`.

### Events (Server → Client, `Event:FireClient(kind, data)`)

| kind | data |
|---|---|
| `mini` | `MiniSnapshot.Build(d, now, passes)` (höchstens 2×/s, nur bei Änderung oder alle 1 s bei laufender Produktion) |
| `mini_open` | `{tab=string}` |
| `mini_notice` | `{kind=string, ...}` (offline, quiz, scrapyard, rebirth, leaderboard, levelup wird **nicht** gesendet – 2.4.0 zeigt Level-ups selbst) |
| `toast` | **String** (2.4.0-Format) |

## 4. Welt (Stadt)

- **Globale Stadt:** `Workspace.City` (Model), zur Build-Zeit von `tools/worldgen` erzeugt. Enthält `Ground`, `Roads`, `Districts.<Name>`, `Stations.<key>`, `Arrivals.<key>`, `Animated`, `Lights` und die globale `SpawnLocation` `CitySpawn`.
- **Stationen:** `City.Stations.<key>` ist ein Part mit Attribut `MiniTab` (Tab-Name) und einem `ProximityPrompt` (ActionText „Öffnen“, Taste E, Hold 0,25, Reichweite 10, RequiresLineOfSight false). `MiniService` bindet sie selbst (nicht `W.Create`) und prüft die Reichweite serverseitig.
- **Ankunftspunkte:** `City.Arrivals.<key>` (unsichtbar, CanCollide false, oben freier Boden). `mini_travel {key}` teleportiert dorthin (Abklingzeit 3 s). `key = "workshop"` teleportiert zur eigenen Werkstatt (`Stations.home`).
- **Tabs/Keys:** `press`, `tuning`, `scrapyard`, `quiz`, `parking`, `goals`, `leaderboard`, `shop`, `map`, `overview`. Weitere Stations-Keys der Stadt (Autohaus, Auktion, Spielhalle) zeigen in Ausbaustufe 1 einen Hinweis „Eröffnet bald“.
- **Animationen:** Parts oder Models unter `City.Animated` tragen Attribute (`Anim` = `press`, `crane`, `turntable`, `door`, `fountain`, `neon`, `dyno`, `traffic` …) und werden von `CityClient` (Client, rein optisch) animiert. Die Presse bekommt zusätzlich einen lokalen Stoß bei eigenen Klicks.
- **Grundstücke:** `C.PlotSlots = { {x=, z=, rot=0|180}, ... }` (8 Einträge) in `GarageShared.Config`. `World.W.Create` platziert Plot `slot` bei `CFrame.new(x,0,z) * CFrame.Angles(0, math.rad(rot), 0)`. `moveTo` und `doorwayOccupied` sind drehsicher (lokal zum Plot/Anker gerechnet).
- **Plot-Vorlage:** `tools/worldgen` trimmt `Workspace.Werkstatt` (entfernt NeighbourBuildings, Gartenbeete, Zaun, Straße, Boundary-Wände; verkleinert den Hof) und deaktiviert den Plot-Spawn `Start` (`Enabled=false`).
- **Erster Beitritt:** Spieler erscheinen am `CitySpawn`, danach teleportiert 2.4.0 sie wie gewohnt in den eigenen Empfang.

## 5. Client-Anbindung

- `GarageClient` requiret `script.Parent:WaitForChild("Mini"):WaitForChild("MiniClient")` und ruft `MiniClient.Start({ isBlocked = function() ... end, closeTablet = function() ... end, openTablet = ... })` nach dem Aufbau des UI.
- `MiniClient` hat einen eigenen `Event.OnClientEvent`-Listener für `mini*`-Kinds; 2.4.0 ignoriert unbekannte Kinds.
- ScreenGui `Minispiele`, DisplayOrder 30. Einstieg: Nav-Knopf „Minispiele“ im Tablet, HUD-Knopf neben „Menü [Tab]“, Taste **M** (über `InputController`), `mini_open` von Stationen.
- Gegenseitiger Ausschluss: Minispiel-UI öffnet nicht während QTE/Diagnose (`isBlocked`), schließt beim Öffnen das Tablet; 2.4.0-HUD blendet sich bei offenem Minispiel-UI aus.
- Theme = 2.4.0-Farben und -Schriften; eine Zahlenformatierung (`MiniLocale.Number`).
- `MapUI` (Tab `map`): Schnellreise zu allen `City.Arrivals` und zur eigenen Werkstatt.
- `CityClient`: optische Animationen der Stadt (siehe 4), gestartet von `MiniClient`.

## 6. Tests

- `tests/mock_roblox.lua` bildet die für 2.4.0 nötige API nach (siehe `docs/analysis_2.4.0/merge.md` §5). Der Basisbaum (Nicht-Skript-Instanzen) wird für Tests aus dem Place geladen.
- Tests starten `ServerScriptService.Garage.GarageServer` wie in Roblox und sprechen über `Remotes.Command`.
- Pflicht-Szenarien: echte Hülle `{version=2,data,receipts,lock}` lädt ohne Verlust inkl. `games`; `version` bleibt 2; Robux-Kauf (`GrantCredits`) während Minispiel-Aktion verliert kein Geld; Minispiel-Aktionen während `transacting` blockiert; Klickpakete passieren den Cooldown; Leaderboard-Schreiben nur mit `writable`; 2.4.0-Reparaturablauf (Annehmen → Diagnose → Reparatur → Endkontrolle → Abrechnen) läuft; Plots aller 8 Slots überlappen weder sich noch die Stadt; Drehung 180° funktioniert für Ankunft, Rolltor und Hebebühne.
