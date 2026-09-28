## Merge plan: 2.4.0 place + 3.0 minigames

### 0. Verified facts
- `Ultimate_Car_Game/base/Ultimate_Car_Game_2.4.0.rbxlx` is byte-identical to `/tmp/claude-0/old/old.rbxlx` (md5 1328ebe7…). All 11 extracted scripts match the XML `Source` values byte for byte.
- Parsing the base with `xml.etree` and writing it back gives a byte-identical file (5,636,778 bytes). The base has no CDATA, no attributes and no SharedStrings. Referents run `RBX000001`–`RBX004345`. An ElementTree-based builder therefore produces minimal diffs.
- The 3.0 suite is green: 9 files, 724 checks, 0 failures.
- 2.4.0 gives each player their own copy of the world:
  - `World.lua` L7-9 clones `workspace.Werkstatt` into `ServerStorage.PlotTemplate` and then destroys the original.
  - `W.Create` (L51-72) clones one plot per player at `CFrame.new(((slot-1)%4)*330,0,floor((slot-1)/4)*260)`, up to 8 plots.
  - A plot measures X −141..141 and Z −88..132.5. Four invisible, collidable, 52-stud-high `Architecture.Boundary` walls enclose it, so players cannot leave their plot.

### 1. Conflicts
**1.1 DataStore: both use "UltimateCarGame_v2", with incompatible schemes**

| | 2.4.0 `Profiles` | 3.0 `Profiles` |
|---|---|---|
| Key | `"Player_"..UserId` (L22) | `"player_"..UserId` (`Config.ProfileKeyPrefix`) |
| Record | `{version=2,data=<career>,receipts,lock={token=GUID,expires=os.time()+180}}` (L36/79/127) | the profile itself at top level: `{schema=3,credits,level,xp,games,_lock={job,id,t}}` |
| Money field | `data.money` | `credits` |
| Lock | 180 s lease, renewed by the 45 s autosave. If blocked, the player gets a temporary unsaved profile | 600 s timeout, 5×3 s retries, then Kick |
| Studio | uses `UltimateCarGame_Studio_v2`, and `SaveInStudio=false` | writes to the production store whenever API access is enabled |
| Unknown fields | `R.LoadData` keeps only known fields, so it would drop `games` | keeps unknown fields |

Consequences:
- The two keys differ only in letter case, so 3.0 as written never sees a 2.4.0 save. Every existing player would restart at 800 Cr, and their 2.4.0 record would be orphaned.
- The "2.4.0 migration" test (`test_rules.lua` L34-47) uses a made-up flat profile (`credits`, `equipmentBays` as an array). That shape never exists in production.
- Aligning only the key prefix would make it worse. The locks `lock` and `_lock` would ignore each other, and 2.4.0 `Profiles.Save` would rewrite the record as `{version,data,receipts,lock}`, which deletes `games`.

**1.2 Remotes**
- 2.4.0 ships `GarageShared.Remotes.{Command,Event}` inside the place file. All actions pass one gate, `request()` (L372-389):
  - action name up to 32 characters;
  - at most 10 scalar arguments;
  - token bucket of 30, refilling at 20/s;
  - 0.12 s cooldown per action;
  - blocked while a Robux purchase is being saved (`profile.transacting`, L374).
- 3.0 creates `ReplicatedStorage.Remotes.{Action,Sync,Notice}` at runtime (`Main.server` L30-43) with its own bucket (25/s, burst 40). That gives a second budget and a path around the `transacting` block.
- Payload clash: the 3.0 `toast` notice sends `{text=…}`, but the 2.4.0 client's `toast(value)` (L413) expects a string and would show "table: 0x…".
- Action names do not collide (`upgrade_buy` vs `upgrade`, `ui_ready` vs `hello`).

**1.3 UI**
- Both clients create `PlayerGui.UltimateCarGame`: `GarageClient` L66 with DisplayOrder 20, and `UI.lua` L202-207 with DisplayOrder 10.
- The top-centre HUDs overlap: 2.4.0 `CompactProgress` (310×46 at y 8, toast at y 62) and 3.0 `Top` (up to 480 wide at y 6).
- The 3.0 bottom "Minispiele" button covers the 2.4.0 tool-hotbar row inside the 132 px HUD (L91).
- Because of DisplayOrder 10, the 3.0 panel renders underneath the 2.4.0 HUD.
- Credits are formatted two ways: `fmt` (L50-56) gives "1.2 Mio.", `Locale.Number` gives "1,2 Mio.".
- Level-ups would be announced twice.

**1.4 World and SpawnLocations**
- 3.0 `World.Build` creates a `Hof` folder at the origin with a 400×400 "Wiese" (grass, top at y 0) and 150×150 asphalt.
  - This buries plot 1's Yard (top −1.0) and entrance apron (−0.5).
  - It z-fights with the hall floor (top 0).
- The 3.0 stations sit on a radius-50 circle. The workshop station (−50,0,0) lands inside the hall (X −74..−32), and the leaderboard board (0,0,50) sits on the apron.
- 3.0 adds a second neutral SpawnLocation "Start" at (0,0.3,0), inside the Stage_3 extension footprint (X −10..12). With two neutral spawns, Roblox picks one at random.
- 2.4.0 has one `Werkstatt.Start` at (−64,0.13,31), copied into each plot.
- The 3.0 `car()` helper (7 parts) duplicates `ServerStorage.CarTemplates`, which has 9 car models of 114–149 parts each.

**1.5 Name clashes**
- Config, Rules and Locale exist in both `GarageShared` and `Shared`. Profiles, Purchases and World exist in both `Garage` and `Server`. Both have a folder called `Remotes`.
- There is no runtime instance clash, because the parents differ. Tooling breaks, though:
  - `validate.py` builds flat, name-keyed module sets.
  - `H.Shared` keys modules by Name.
  - The grep checks look for `Config.Version = "3.0.0"` and `Config.ProfileStoreName`, which won't be where they expect after the merge.
- The A2 check in `validate.py` also fails on 2.4.0 `Locale` L21, which contains "Nicht genug Autopunkte."

**1.6 Loops**
- 2.4.0 server:
  - a 0.5 s loop (Lighting clock, days, `R.Advance`, full-state `push` every 0.5 s);
  - a 45 s autosave;
  - its own `BindToClose`.
- 3.0 server:
  - a 1 s tick that always marks the session dirty;
  - a 0.5 s Sync;
  - a 60 s autosave;
  - leaderboard writes every 120 s and reads every 60 s (5 pages);
  - its own `BindToClose`.
- Two autosaves on the same key would interleave `UpdateAsync` calls.

**1.7 Economy conflicts**
- **`offerSlots` cost differs.** 2.4.0 charges 900·1.48^(lvl−3), 3.0 charges 900·1.48^(lvl−1).
- **`bays` differs.** 2.4.0 uses (800, 1.7, max 4), 3.0 uses (1100, 1.42, max 50).
- **`toolLevel` matches** in both versions.
- **XP curve and level-up bonus are identical.** `R.XPNeeded` (L121) equals `Rules.XpNeeded`; both give 120+18·level credits and +2 reputation. The return values differ: 2.4.0 `R.GainXP` returns a count, 3.0 returns `{levels,credits}`.
- **Caps differ:** 1e24 in 2.4.0 vs 2^53 in 3.0.
- **3.0 copies an HTML bug.** `RepairSpeed` multiplies speed by (1−diag), so quiz points make repairs about 1.54× slower. The UI says "kürzere Reparaturzeit".
- **Purchase saves can lose minigame money.** `Profiles.GrantCredits` snapshots the data, yields, then sets `profile.data.money=result.data.money` (L131). Any money change during that window is lost.

### 2. Server merge
**2.1 Data.** Keep 2.4.0 `Profiles` unchanged (key, lock, receipts, Studio store). Store the 3.0 fields under `data.games`, keeping the 3.0 name to minimise diffs. Keep `data.version=2`: `R.LoadData` L33 returns a fresh profile for any other value. Add `games.v=1` for future migrations.

| 3.0 (`p`) | Merged (`d` = record.data) |
|---|---|
| `p.credits` | `d.money` (use `add`, capped at `C.NumberCap`) |
| `p.level`, `p.xp`, `Rules.GainXP` | `d.level`, `d.xp`, `R.GainXP` through a wrapper that returns `{levels,credits}` |
| `games.reputation`, `games.toolLevel` | `d.reputation`, `d.toolLevel` |
| `games.bays/offerSlots/jobs/offers/nextId` | dropped |
| `games.parts` | `d.games.parts` ("Altteile", scrapyard and daily reward) |
| everything else (`press`, `tuning`, `scrapyard`, `quiz`, `parking`, `stats`, `milestones`, `daily`, `tuningLevel`, `scrapyardLevel`) | `d.games.*` unchanged |
| `schema`, `_lock` | dropped |

- `R.NewData`: add `games=MiniRules.DefaultGames()`.
- `R.LoadData`: before L110, set `d.games=MiniRules.LoadGames(raw.games,now)`. This is the 3.0 `Rules.LoadData` L182-273 with the career and workshop parts removed, keeping only known fields and staying idempotent.
- `Profiles.Save` L67: add an `IsClean` (no NaN/inf) guard.

**2.2 Code adaptation.** Rename field accesses mechanically:
- `GoalRules` L17/47/98/113-114
- `PressRules` L166-167/188
- `SideGameRules` L10/22/25/44/57/108/191-192
- `TuningRules` L85/105-106/139
- `Snapshot` L88-92
- `Core.ReportXp` L99

Move the cross-bonuses (`WorkshopRules` L9-33, `PressRules.WorkshopMultiplier`) into a new `CrossBonus` module and apply them to the 2.4.0 workshop:
- `R.Reward` (L285): multiply by the press, tuning and parking-streak bonuses. It must be nil-safe, because `GarageClient` L190 also calls it on `state.data`.
- `R.StepDuration` (L269): multiply by (1−DiagReduction), so quiz points actually shorten repairs.
- `R.RefreshOffers` target (L180): add the parking-streak offer bonus.
- `jobsDone` stat: add it after `settle` (L297-302).

**2.3 Dispatch: reuse the existing remote.**
- A new `MiniService` replaces 3.0 `Core`, `Actions` and `Main`. Insert `if Mini.Handles(action) then return Mini.Handle(p,action,a) end` before `act()` (L388).
- This inherits the existing budget, cooldown, `transacting` block and `R.Advance`.
- `Mini.Handle` keeps the 3.0 per-action type checks and request-ID deduplication.
- Handlers receive `ms={player,userId,data=p.profile.data,passes,rng,clickTokens,…}`, with `writable` read live from `p.profile.writable`.
- If a handler changed money, call `changed(p)`, so the revision bumps and `W.Sync` updates the expansion sign. Otherwise call `push(p)`.
- Server→client messages use `Event` kinds: `mini` (the snapshot), `mini_open{tab}`, `mini_quiz`, `mini_scrapyard`, `mini_offline`, `mini_rebirth`, `mini_leaderboard`. Toasts use the existing string `toast`. The 2.4.0 client ignores unknown kinds. Drop the 3.0 `levelup` notice; 2.4.0 already detects level-ups.
- A second remote is not justified. Clicks are batched at 2/s, and a second remote would add a second budget and a path around the `transacting` block.
- Drop the actions `workshop_accept`, `workshop_finish` and `ui_ready` (use `hello` instead). Rename `upgrade_buy` to `mini_upgrade`, limited to `tuningLevel` and `scrapyardLevel`.

**2.4 Lifecycle.** Hook into the existing 2.4.0 flow:
- **Join:** `Mini.OnJoin` handles offline press output, tuning `lastIdle`, `EnsureDay`, and an asynchronous game-pass check.
- **Tick:** the 0.5 s loop runs `Mini.Tick`, skipped while a purchase is being saved (`transacting`).
- **Autosave:** use the 2.4.0 one only.
- **Leave and shutdown:** run `Mini.Flush` before `P.Save`. Write the leaderboard only if the profile was writable *before* the release; capture that first, because L93 sets `writable=false`. This also keeps Studio sessions from writing to the production OrderedDataStore.
- **Snapshot:** send the `mini` snapshot only when something changed and either the panel is open or 1 s has passed. Put the HUD fields in `push`. Widen the `PressUI.DisplayScrap` interpolation window (currently `min(2,…)`).

**2.5 Physical places.**
- Build the minigame venues as geometry inside the plot template (`Werkstatt.Minigames`), so every plot gets its own copy automatically.
- Add station Parts to `Werkstatt.Stations`: `mini_press`, `mini_dealer`, `mini_tuning`, `mini_scrapyard`, `mini_quiz`, `mini_parking`, `mini_goals`, `mini_board`. Give each prompt ActionText "Bereich öffnen", key E, hold 0.25 s, range 10.
  - `W.Create` (L60-63) wires these up automatically.
  - `station()` provides the 10-stud range check.
  - The client's `PromptShown` handler (L541) already hides other players' prompts through `OwnerUserId` (L55).
- Free space in the current yard:
  - west: X −137..−80 (near the recycle station at −88, 63);
  - east: X ≥ 50 (Stage_4 ends at 34.4, and the ExpansionPoint reaches about 44);
  - front parking: Z 52..76 (suitable for the 4×4 Parkplatz grid);
  - Office: X −74..−54, Z 0..33 (quiz terminal).
- A bigger world means resizing the Yard and Boundary and changing `World.lua` L56 spacing, which is currently 330/260 against a 282/220.5 footprint. Move the spacing into `C.PlotSpacingX/Z`.
- Dynamic parts go in a small `MiniWorld` module that iterates `W.plots`: press animation, tuning cars cloned from `CarTemplates`, and a per-plot leaderboard SurfaceGui.

### 3. Client merge
- **Entry module:** turn `Main.client` into a `MiniClient` module, required by `GarageClient` after L21. It gets its own `Event.OnClientEvent` listener for the `mini*` kinds. `MiniRemote.Send` becomes `Command:FireServer`, keeping the request ID.
- **UI layer:** call `MiniUI.Build({hud=false})`.
  - Drop the duplicate credits/level/XP HUD and the bottom button.
  - Keep the "Nächstes Ziel" chip and the scrap counter as a second row under `CompactProgress`, and move the 2.4.0 toast (L104) down.
  - Rename the ScreenGui to "Minispiele" and set DisplayOrder 30 (tablet is 20, `GarageCelebrations` is 45).
- **Entry points:**
  - a nav button in `navOrder` (L79);
  - a HUD button next to "Menü [Tab]" (L96);
  - the key M in `InputController` (Tab, 1–5 and Space are taken);
  - the `mini_open` event sent when a venue prompt fires.
- **Mutual exclusion:** add `and not Mini.IsOpen()` to `hud.Visible` (L317) and `vehicleActions.Visible` (L389). `MiniUI.Open` must refuse while `overlay.Visible` (QTE or diagnosis dialog) and must close the tablet.
- **Look and feel:** set `UI.Theme` from the 2.4.0 colours (L25-26) and use one number formatter.
- **Shop:** the game-pass section from `ShopUI` moves into the 2.4.0 `shopPage`.
- **Tabs:** overview, press, tuning, scrapyard, quiz, parking, goals, leaderboard. `OverviewUI` L48-61 reads `state.data.jobs` instead of the 2D workshop.

### 4. Build pipeline
Command: `build_place.py --base base/Ultimate_Car_Game_2.4.0.rbxlx --project default.project.json --out Ultimate_Car_Game.rbxlx`.

1. Parse the base with ElementTree (byte-stable, verified above).
2. Remove every Script/LocalScript/ModuleScript Item. Fail if a removed script path has no matching src file.
3. Insert scripts per the Rojo-style mapping. Create folders as needed and keep non-script siblings such as `GarageShared.PreviewCars` and `Remotes`.
4. Apply the declared geometry additions and patches. Each patch asserts the old values it expects.
5. Give new Items fresh referents with their own prefix.
6. Write the file.

Mapping:
- `src/garage/shared` → `ReplicatedStorage.GarageShared`
- `src/garage/server` → `ServerScriptService.Garage`
- `src/garage/client` → `StarterPlayer.StarterPlayerScripts` (placed directly there; `GarageClient` uses `script.Parent:WaitForChild("ClientEffects")`)
- `src/mini/{shared,server,client}` → a `Mini` subfolder in each

Rename all 3.0 modules so names are unique across the place: `MiniConfig`, `MiniRules`, `MiniLocale`, `MiniNet`, `MiniSnapshot`, `MiniService`, `MiniPasses`, `MiniWorld`, `MiniUI`, `MiniRemote`, `MiniEffects`. For Rojo, set `$ignoreUnknownInstances: true` on these folders.

First commit: move the extracted scripts into `src/garage`. Gate: building the base with the unmodified extracted sources must reproduce the base byte for byte.

`validate.py` additions:
- no script in the place that is not from src;
- the non-script fingerprint equals the base plus the declared additions;
- exactly one SpawnLocation;
- `Command` and `Event` exist;
- `Werkstatt.PrimaryPart` resolves;
- version check moves to `C.Version`, store check to `C.DataStoreName`;
- remove the "Autopunkte" entry from `Locale` L21;
- the CSV export path follows the rename.

### 5. Mock and tests
Export the base's non-script instances to a Lua table fixture (`tools/export_fixture.py` → `tests/fixtures/base_tree.lua`) and load it before the scripts.

**Missing Roblox API surface in `tests/mock_roblox.lua`:**

*Services*
- ServerStorage
- Lighting
- `HttpService:GenerateGUID`
- StarterGui (`Get/SetCoreGuiEnabled`, `GetCore`)
- UserInputService (`InputEnded`, `GetFocusedTextBox`, `IsKeyDown`)
- `ContextActionService:BindActionAtPriority`
- `ProximityPromptService.PromptShown/Hidden`
- `workspace.CurrentCamera.ViewportSize`
- `Players.LocalPlayer`
- `Player:GetMouse`

*Instance methods*
- A deep `Clone` (children, attributes, remapped `PrimaryPart`). The current `Clone` is shallow; `World.lua` clones the whole Werkstatt.
- `PivotTo` / `GetPivot`
- `FindFirstChild(name, recursive)`
- `FindFirstChildWhichIsA`
- `IsDescendantOf`
- `Position` derived from `CFrame`

*Datatypes and signals*
- `CFrame:Inverse`, CFrame ± Vector3
- Tweens with a `Completed` signal that apply their goals (`W.Lift` depends on this)
- A `NumberValue.Changed` signal
- `CharacterAdded`, `Completed`, `InputEnded`, `PromptShown`, `PromptHidden`
- `IsA("BasePart")` must include WedgePart
- class defaults such as `CanvasPosition` (`rebuild` L304 indexes it)

*Other*
- `Humanoid:Get/SetStateEnabled`
- `MarketplaceService:GetProductInfoAsync`
- A `Mock.SpawnCharacter` helper that builds HumanoidRootPart, Humanoid and RightHand
- `os.time` and `os.clock` bound to the mock clock. This works in luaurun: I tested overriding `_G.os` and it takes effect.

**Test harness changes.** `H.Server` should run `Garage.GarageServer`. Better still, move `request`/`act` into a `GarageService` module so tests can call them directly.

**New tests:**
- load a real `{version=2,data,receipts,lock}` record;
- run the old base `R.LoadData` on a merged record and document that it drops `games`;
- a Robux purchase save racing a minigame action;
- minigame actions blocked while `transacting`;
- clicks passing the 0.12 s cooldown;
- a leaderboard write on leave.

### 6. Obsolete in 3.0 (per A1)
- **2D workshop and its data:**
  - `WorkshopUI.lua` and `WorkshopService.lua`;
  - everything in `WorkshopRules` except the bonus functions;
  - `Config.Jobs/JobTierNames/MaxOffers`, and the `bays`/`offerSlots`/`toolLevel` entries in `Config.Upgrades`;
  - `Rules.normalizeJob`, the `games` workshop fields, `XpNeeded`/`GainXP`/`StartCredits`/`LevelUp*`;
  - `Snapshot.workshop`, and the `GoalRules.NextGoal` workshop entry (L168, which should point to 2.4.0 invoice jobs instead).
- **3.0 world and server core:**
  - `World.lua` (the `Hof`, grass, spawn, `car()`);
  - `Main.server.lua`, `Core.lua`, the `Actions` wiring, `Profiles.lua`, `DataUtil.Retry`, the 3.0 runtime `Remotes`.
- **Client and tests:**
  - the `Main.client` bootstrap, the HUD in `UI.lua`, `Remote.lua`;
  - the fabricated migration test and the workshop/upgrade test cases;
  - `PLAN_3.0` deviations 1–2;
  - the scratch-built `Ultimate_Car_Game.rbxlx`.

### 7. Order of work
1. Extract the scripts and add the base-derived build with the round-trip gate.
2. Extend the mock and add smoke tests for 2.4.0.
3. Rename the 3.0 modules, map the data, and hook `MiniService` into `GarageServer`.
4. Merge the client.
5. Add the geometry.
6. Publish with a full server shutdown.

### Integration points
- ReplicatedStorage.GarageShared.Rules (Rules.lua) R.NewData L23-29: add games=MiniRules.DefaultGames(); keep version=2
- Rules.lua R.LoadData L30-112: never change the `raw.version~=2` check at L33; insert d.games=MiniRules.LoadGames(raw.games, now) before R.Advance(d,now) at L110 (whitelisted, idempotent)
- Rules.lua R.Reward L285-293: multiply by CrossBonus (PressRules.WorkshopMultiplier x TuningWorkshopBonus x CustomerBonus), nil-safe because GarageClient L190 calls R.Reward(d(),j) on state.data
- Rules.lua R.StepDuration L269-272: multiply by (1 - DiagReduction(d.games)), capped at 0.35 (fixes the direction bug inherited from HTML acceptJob L704 / 3.0 WorkshopRules.RepairSpeed L23-25)
- Rules.lua R.RefreshOffers L180 target=min(35,d.offerSlots): add the parking-streak offer bonus (3.0 WorkshopRules.DesiredOffers L31-34)
- Rules.lua R.GainXP L122-130 and R.XPNeeded L121: shared career; wrap as Career.GainXP(d,n) returning {levels,credits} for 3.0 callers (Core.ReportXp L96-101)
- Garage.Profiles Save L67 (snapshot=Rules.Snapshot): add a MiniRules.IsClean guard before UpdateAsync; Profiles.GrantCredits L102-140 (money overwrite at L131) stays unchanged, but minigame money must never change outside request()
- GarageServer.request L372-389: insert `if Mini.Handles(action) then return Mini.Handle(p,action,a) end` before act(p,action,a) at L388 (inherits budget L379-380, 0.12 s cooldown L381-383, transacting block L374, payload limits L376)
- GarageServer act 'hello' L186: also call Mini.Hello(p) (sends the mini snapshot and leaderboard view); replaces the 3.0 ui_ready action
- GarageServer act 'settle' L297-302: after a successful R.Settle call Mini.OnSettled(p,receipt) -> AddStat jobsDone and daily progress
- GarageServer join L394-428: W.Create callback L401-407 (kind=='station' L403): route mini_* station names to Mini.Open(p,name) -> Event 'mini_open'; after L413 call Mini.OnJoin(p) (offline press, tuning lastIdle, GoalRules.EnsureDay, async game-pass check guarded by sessions[player]==p)
- GarageServer PlayerRemoving L431-434: Mini.Flush(p) (PressService.Tick) before P.Save; capture wasWritable=p.profile.writable before P.Save(profile,true) (Profiles L93 clears it), then LeaderboardService.Write if wasWritable
- GarageServer 0.5 s loop L435-448: inside the per-session block, `if not p.profile.transacting then Mini.Tick(p,now()) end` plus throttled Mini.Sync(p); once per iteration task.spawn(LeaderboardService.Refresh,false) (self-throttled 60 s); leaderboard Write throttled 120 s
- GarageServer autosave L449-451: the only autosave (drop 3.0 Config.AutosaveInterval and Profiles.Save); BindToClose L452-456: add Mini.Flush + leaderboard write per session
- GarageServer push L71-80: data=R.Snapshot(d) now includes games; add a compact mini HUD block (scrap, scrap/s, next goal); Purchases.Init L391-393 unchanged, add MiniPasses.Init (PromptGamePassPurchaseFinished)
- GarageShared.Config: C.Version L5 -> '3.0.0'; C.DataStoreName L10 / C.StudioDataStoreName L11 unchanged; C.StationNames L184-186 add the mini_* names (makes 'travel' L187-192 work); add C.PlotSpacingX/Z
- Garage.World: W.Create L56 plot spacing (330/260 vs 282x220.5 footprint) -> C.PlotSpacing for a bigger world; L60-63 wires every Stations child prompt automatically; OwnerUserId attribute at L55 drives the client prompt filter; add a per-plot leaderboard board update fed from W.plots
- GarageShared.Locale L21: remove the ['Nicht genug Autopunkte.'] entry (fails the validate.py A2 check)
- Place XML Workspace.Werkstatt.Stations: add Parts mini_press, mini_dealer, mini_tuning, mini_scrapyard, mini_quiz, mini_parking, mini_goals, mini_board, each with a ProximityPrompt (ActionText 'Bereich öffnen', KeyboardKeyCode 101=E, HoldDuration 0.25, MaxActivationDistance 10, RequiresLineOfSight false) like the existing station prompts
- Place XML Workspace.Werkstatt: new Model 'Minigames' (cloned per plot by World.lua L7-9). Free zones: west X -137..-80 (near recycle station -88,63), east X>=50 (Stage_4 ends 34.4, ExpansionPoint up to about 44), front parking Z 52..76 (ParkingLine), Office X -74..-54 Z 0..33; resizing Architecture.Yard (280x220 at 0,-1.5,22) and Boundary (X +/-140, Z -82/132) requires new spacing
- GarageClient: ScreenGui L66 keeps the name 'UltimateCarGame'; the 3.0 gui is renamed 'Minispiele' with DisplayOrder 30; navOrder L79 add a 'mini' button; HUD 'Menü [Tab]' button L96 add a 'Minispiele' button beside it; toastPanel L104 moves down for the mini row
- GarageClient refresh L316-317 (hud.Visible) and refreshVehicleActions L389: add `and not MiniClient.IsOpen()`; Event.OnClientEvent L403 unchanged (MiniClient registers its own listener for mini* kinds); fmt L50-56 -> MiniLocale.Number
- InputController L36-41 (UCG_WorkshopMenu, Tab, priority 10000) and L42 (UCG_Hotbar 1-5): add an optional callbacks.ToggleMini bound to KeyCode.M; do not reuse Tab, 1-5, Space, E, F or H
- 3.0 src/client/Main.client.lua -> MiniClient module required by GarageClient after L21; Remote.lua -> MiniRemote using GarageShared.Remotes.Command:FireServer(action,payload) with rid; UI.lua UI.Build -> Build({hud=false}); PressUI.DisplayScrap min(2,...) window widened
- tools/build_place.py: new --base/--project mode (ElementTree parse, strip Script/LocalScript/ModuleScript Items, re-inject from default.project.json mapping, own referent prefix, declarative geometry additions and asserted patches); export_locale_csv path follows MiniLocale
- tools/validate.py validate_place/validate_static: no scripts outside src, non-script fingerprint = base + declared additions (Part 3568, WedgePart 485, ProximityPrompt 13, ...), exactly 1 SpawnLocation, Remotes Command/Event present; version/store greps retargeted to GarageShared Config C.Version/C.DataStoreName
- tests/mock_roblox.lua: Mock.LoadPlace must first build tests/fixtures/base_tree.lua (exported from the base); add the services/methods/datatypes listed in the report; H.Server runs ServerScriptService.Garage.GarageServer; H.Act fires GarageShared.Remotes.Command.OnServerEvent (or move request/act into a GarageService ModuleScript)

### Risks
- Mixed-version window: an old 2.4.0 server's R.LoadData (whitelist) and Profiles.Save (writes only {version,data,receipts,lock}) drop data.games. A player who hops back to an old server loses all minigame progress. Publish with 'Shut down all servers' / migrate-to-latest, or keep a separate backup key for games
- Never let 3.0 Profiles touch the store. Its key 'player_' differs only in case from 2.4.0 'Player_', so as written 3.0 silently starts every veteran at 800 Cr. With an aligned prefix, the lock fields `_lock` and `lock` ignore each other and 2.4.0 Save deletes games (write ping-pong / data loss)
- Changing data.version or the outer record version from 2 makes 2.4.0 R.LoadData (L33) return a fresh profile, wiping all 2.4.0 careers
- GrantCredits (Profiles L102-140) overwrites profile.data.money with the pre-yield snapshot (L131). Any minigame code that changes money outside request() (tick, task.spawn callbacks, game-pass callbacks) loses credits during a Robux receipt write
- 3.0 upgrade_buy on offerSlots/toolLevel/bays uses different cost formulas (offerSlots 900*1.48^(lvl-1) vs 2.4.0 900*1.48^(lvl-3); bays max 50 vs 4). Leaving it routed lets players buy 2.4.0 upgrades at wrong prices or beyond C.MaxBays, breaking World.layout (Stage_5 does not exist)
- Money cap mismatch: 3.0 uses 2^53, 2.4.0 C.NumberCap=1e24 and GrantCredits rejects balance>NumberCap. Mini credit grants must use the capped add helper
- 3.0 in Studio writes to the production DataStore and OrderedDataStore when API access is enabled. The merged code must keep 2.4.0 SaveInStudio=false / UltimateCarGame_Studio_v2 and gate leaderboard writes on profile.writable
- Leaving 3.0 World.Build in place buries plot 1 (400x400 Wiese top y=0 over Yard/apron/hall floor) and adds a second neutral SpawnLocation at (0,0.3,0) inside the Stage_3 hall extension; players randomly spawn in someone else's plot
- Enlarging plots or adding venues beyond the 330x260 spacing (World.lua L56) makes plots overlap neighbours; +parts per plot x8 plots increases clone time at join and memory; the Boundary walls (invisible, collidable, 52 high) trap players unless moved
- Turning on StreamingEnabled for a bigger world breaks the 2.4.0 client: push() sends Instance refs (target, visuals[].model, plot) that arrive nil when not streamed
- Bandwidth: 2.4.0 already pushes full state twice per second per player; adding the full 3.0 Snapshot.Build on every push without dirty/visibility throttling multiplies traffic; conversely throttling too hard freezes PressUI.DisplayScrap (2 s interpolation cap)
- UI collisions if merged naively: two ScreenGuis named UltimateCarGame (tests index PlayerGui.UltimateCarGame), 3.0 panel at DisplayOrder 10 renders under the 2.4.0 HUD, 3.0 toast payload {text=} renders 'table: 0x...' in the 2.4.0 toast, double level-up feedback
- OrderedDataStore budget: the 3.0 leaderboard reads 5 pages every 60 s plus up to 50 GetNameFromUserIdAsync calls; on small servers this approaches the GetSortedAsync budget (5+2*players per minute)
- Porting the 3.0 RepairSpeed formula unchanged makes quiz diagnosis points slow repairs (x1/0.65) while the UI promises shorter times
- Deleting or renaming base script Items without a matching src file would silently drop 2.4.0 behaviour; the builder must fail on orphaned scripts and verify the byte-identical round trip before any edits
- validate.py will fail or give false confidence after the merge: A2 'Autopunkt' check hits 2.4.0 Locale L21; version/store greps point at src/shared/Config.lua; flat module-name sets are ambiguous while Config/Rules/Locale/Profiles/Purchases/World exist twice
- Committing the base-derived 5.6+ MB rbxlx on every build bloats the git history; keep the base plus src and treat the build output as an artifact (gitignore or LFS)