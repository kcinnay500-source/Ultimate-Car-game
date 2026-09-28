## Completeness review of the five 2.4.0 / 3.0 merge reports

I checked the claims against the extracted scripts, `old.rbxlx` (parsed with ElementTree) and the 3.0 sources. Helper scripts are in `/tmp/claude-0/scratch_critic/` (`parse.py`, `q1.py` to `q7.py`). Nothing in the repo was modified; `git status` is clean. I also ran the 3.0 test runner, which only reads files.

**Verdict:** the five reports are mostly accurate. The load-bearing facts all hold: the per-player plot model, the DataStore envelope and whitelist, the remote gate, the geometry anchors, and the 3.0 DataStore key clash. Section 2 lists 9 wrong or imprecise claims. Section 3 lists 15 topics that no report covered, with the answers I found.

### 1. Load-bearing claims verified (all correct)

| # | Claim | Evidence |
|---|---|---|
| 1 | Werkstatt is cloned to `ServerStorage.PlotTemplate` and destroyed when World is required. Plot pivot is `((slot-1)%4)*330, 0, floor((slot-1)/4)*260`, with `MaxPlots=8`. | World.lua L7-10 and L56; Config L16 |
| 2 | Boundary walls, Yard and hall roof | XML: `Boundary` 282×52×1 at (0,25,132) and (0,25,-82); 1×52×215 at (±140,25,25); all Transparency 1 and CanCollide true. `Yard` is 280×1×220 at (0,-1.5,22). `ClosedRoof` is centred at Y 20.5 and 1 thick, so its underside is at 20. |
| 3 | Profile storage, envelope and money overwrite | Key `"Player_"..UserId` (Profiles L22). The envelope is rebuilt at L36, L79 and L127. `GrantCredits` overwrites only money from a pre-yield snapshot (L111-115, L131). A lost lock leaves `transacting=true`: set at L118, never cleared on the L135 or L138 paths. |
| 4 | `raw.version~=2` wipes the profile, and LoadData runs inside `UpdateAsync` at load | Rules L33; Profiles L35-36 |
| 5 | The remote gate | GarageServer: `transacting` check L374, flat-args sanitizer L376, 30-token bucket refilling at 20/s L379-380, 0.12 s per-action cooldown L381-383 |
| 6 | Remotes | Exactly 2 RemoteEvents, `GarageShared.Remotes.{Command,Event}`, and no RemoteFunctions or Bindables. The file holds 13 ProximityPrompts. |
| 7 | Prompt settings | Station, door and yard prompts: Default style, E (101) or ButtonA (1002), hold 0.25, range 10 (door 8). `Stations.home` has **no** prompt. The `tools` prompt range is 10 but the server check is 9 (GarageServer L30). `WorkPrompt`: hold 0.12, range 8, OnePerButton, ButtonX (CarFactory L31-48). The lift prompt is stored as E in the XML and switched to F/ButtonB at World L202. |
| 8 | Geometry anchors | Bay_1: `CarOrigin` (-43,0,-5), `PlayerArrival` (-49.4,3.5,1), `EquipmentSpot` (-36.8,0,7.5). `EndWall.Root` is at X -32. The Stage_2/3/4 floors are centred at X -21, 1 and 23, 22 wide, 119 parts each. All 4,054 BaseParts are anchored. The 9 car templates have 122-149 parts each, with exactly 30 CanCollide=false parts. |
| 9 | 3.0 DataStore and upgrade facts | Key prefix `"player_"` (Config L7-8). 3.0 Profiles opens the live store in Studio (L21-33). `RepairSpeed` multiplies by `(1-diag)` (WorkshopRules L23-25) and the duration is `time/RepairSpeed` (L96). Upgrade cost uses `^(level-1)` (L139-140). The "legacy" profile in `test_rules.lua` L34-47 is fabricated. |
| 10 | 3.0 UI and world facts | ScreenGui `UltimateCarGame` with DisplayOrder 10 (UI.lua L203, L207). `Wiese` is 400×2×400 at Y -1, `Asphalt` 150×0.2×150 at Y 0.1, spawn at (0,0.3,0) (World.lua L117-124). The `Net.Actions` payloads are flat primitives (Net.lua L11-35), plus `rid` (Remote.lua L18), so they pass the 2.4 sanitizer. |
| 11 | A 3.0 toast payload `{text=}` renders as "table: 0x…" | `L.t` calls `tostring(source)` (Locale L24) |
| 12 | Numbers | XP needed at levels 1/10/38: 106/357/1188. Cumulative XP to 10/38/100: 1944/23054/155043. Refunds 2312/3930. An 8 h tuning job pays about 99k. |
| 13 | Tooling | md5 is `1328ebe7…`; the ElementTree round trip is byte-identical (5,636,778 bytes) **only with `xml_declaration=True`**. The 3.0 suite reports "9 Dateien, 724 Prüfungen, 0 Fehler". validate.py's A2 check (L166-168) fails on 2.4 Locale L21 ("Autopunkte"). |

### 2. Wrong or imprecise claims

1. **Merge report §1.4 on spawns.** It says "2.4.0 has one `Werkstatt.Start`" and that two neutral spawns give a random pick.
   - At runtime `Start` is cloned into **every** plot. It is Neutral, Enabled, Transparency 1, CanCollide false and Duration 0.
   - So there are up to 8 random spawn pads today, and players already spawn in other players' plots. The 3.0 spawn would be the 9th.
2. **Merge report, StreamingEnabled risk.** The client never reads `state.plot` or `visuals[].model`; the only local that touches visuals is `visual` at GarageClient L324, and it is unused. The Instance references that matter are:
   - `state.target`, used at GarageClient L327-330, L343-348 and L392-401;
   - the `point` in `scan`, `challenge` and `workFX`, used by ClientEffects L50 and L55.
3. **Merge report, "ExpansionPoint reaches about 44".** It is wrong. The ring sits at X = -36+(bays-1)·22, which is -36, -14 or 8, and it is destroyed at 4 bays (World L35). Its maximum is about X 11.
4. **"travel teleports to the station"** (server and client reports). `shop` is special-cased at GarageServer L189: it opens the page without teleporting.
5. **"Any ProximityPrompt under `Werkstatt.Stations` / `YardActivities` auto-binds."** Only a prompt that is a **direct child of a direct child** is bound (`FindFirstChildOfClass`, World L60-62 and L66-69). It must also already exist when the template is cloned (L55).
6. **World report's table of 3.0 stations** lists 7. `World.lua` builds 8; the Schrotthändler at (34,0,-38) is missing (L145-150). I sampled the rotated 18×18 platforms against the 4-bay hall footprint:

   | 3.0 station | Overlap with the 4-bay hall |
   |---|---|
   | Schrotthändler | about 36 sq studs, inside the Stage_4 annex |
   | Quiz | about 38 sq studs, inside the Stage_4 annex (the report said "the apron") |
   | Parkplatz | reaches Z 23.3 at X -36, about 10 studs into the hall through the roller door |
   | Schrottplatz | about 104 sq studs |
   | Werkstatt | fully inside the hall |

   This only matters if any of `World.Build` survives the merge.
7. **Client report, key and camera conflicts.** The 3.0 client has no ContextActionService or UserInputService key bindings and no camera code. The only matches are a GUI `InputBegan` in PressUI L133 and a Sound in Effects. These are rules for new code, not existing conflicts.
8. **"fmt labels 1e18 as 'Tsd. Brd.' (wrong)".** It is mathematically correct (1000 × Billiarde); the label is just unusual. "No grouping below 1000" is vacuous, because numbers under 1000 have nothing to group.
9. **"There is no Terrain object."** That is true for the file, but the engine creates an empty `Workspace.Terrain` at load. It is global and not part of any plot, so terrain would have to be painted at all 8 plot positions.

### 3. Gaps no report covered, with answers

**G1. The real arrival point is `Stations.home`, not the SpawnLocation.**
- `character()` resets the interaction and calls `moveTo(Stations.home)` (GarageServer L419-423). With the home anchor at (-64,5,25.5), the player lands at (-64, 3.5, 31.5): the pedestrian entry, facing into the reception. This happens on every spawn and every respawn.
- `home` and `workshop` share that anchor position.
- Moving the reception therefore means moving `Stations.home`. The `Start` pad is irrelevant after the teleport.
- **Void risk on the first join.** Werkstatt is destroyed at boot and the file has no other ground (Workspace holds only Werkstatt and Camera). A first player whose character loads before `P.Load`/`W.Create` finishes has no spawn pad and no floor. The character then falls to the FallenPartsDestroyHeight of -80 and respawns.
- **Fix options:** a permanent global ground and spawn outside the plot grid, or `CharacterAutoLoads=false` followed by `LoadCharacter` after `W.Create`.

**G2. `moveTo` and `doorwayOccupied` assume flat, unrotated plots.**
- `moveTo` teleports to `CFrame.new(part.X, plotY+3.5, part.Z+6)` (GarageServer L95). This is a world-space +Z offset with a fixed Y.
- `doorwayOccupied` tests world X and Z deltas (World L79-80).
- Consequences:
  - An elevated station, such as the world report's suggested quiz mezzanine at Y 8.5, cannot be a `travel` target: the player would land on the floor below.
  - Plots arranged by rotation around a shared hub would break both functions.

**G3. Client rebuild cost.**
- `rebuild()` runs on every revision change even while the tablet is hidden (GarageClient L410).
- `homePage`, the default page, creates 10 ViewportFrames (L161-178), each cloning a 122-149-part PreviewCar. That is about 1,300 part clones per rebuild.
- This is the concrete reason minigame actions must use `push()` and never `changed()`.

**G4. The 0.12 s per-action cooldown silently drops legitimate minigame input.**
- The cooldown is keyed by action name (L381-383).
- The 3.0 UI debounces per button (UI.lua L123-142). Two quick taps on *different* parking cells (`parking_tap`) or different press upgrades (`press_buy`) share one key, so the second is dropped with no feedback.
- 2.4 `act()` also has no `pcall`, while 3.0 `Actions.Handle` wraps its handlers (Actions.lua L99). A merged `Mini.Handle` should `pcall` and either exempt its actions from the name cooldown or key it by action plus target.

**G5. The place is script-generated.**
- The header uses ElementTree's single-quoted `<?xml version='1.0' encoding='utf-8'?>`.
- There is no Players, StarterGui, SoundService, TextChatService or Terrain item, and no Sky.
- `Lighting.Technology` is not set, so the engine default applies, not Future.
- There are no MeshParts, Decals, Textures, Sounds, ParticleEmitters, Attachments or Animations.
- Consequences:
  - A Studio re-save would rewrite the file and break the byte-identical build gate.
  - Night is 50% of every 20-minute cycle (ClockTime 18→6), with 8 PointLights in the base hall and 17 at 4 bays.
  - validate.py A2 bans `rbxassetid://` in scripts, so the requested "animations" must be procedural (TweenService, Motor6D C0, PivotTo), as in 2.4.

**G6. Migrating veterans into goals.**
- `m_level_25` reads `level` (GoalRules L16), so every 2.4 player at level 25 or higher can claim 5000 Cr immediately.
- `jobsDone` starts at 0 even though `d.completed` exists.
- `daily.active` is set only by `Rules.AddStat` with `now` and not passive (3.0 Rules L321-331). Unless `R.Settle`/`R.FinishYard` call `AddStat`, a workshop-only player can never claim the daily bonus.

**G7. Transaction window versus press production.**
- `GrantCredits` restores only money, so scrap produced during a purchase save is safe.
- Skipping `Mini.Tick` while `transacting`, as proposed, loses production. `PressService.Tick` caps `dt` at 10 s (L44), and a grant can take longer: up to 10 s waiting for a running save (Profiles L106-107) plus 1 s and 2 s retry waits.

**G8. Save depth limit.** `R.Snapshot` returns nil past depth 12 (Rules L9-13) and is used by Save (L67) and GrantCredits (L111). Current 3.0 nesting is about 4 levels deep, which is safe, but it is a hard limit.

**G9. Quick rejoin on a full server.** `PlayerRemoving` yields in `P.Save(release)` before `W.Destroy` (L433). A rejoin inside that window finds the old lock, so the player gets a temporary, non-saving session. On a server with 8 players the slot is also still taken, so the kick at L408 fires.

**G10. The replication budget is unmeasured.**
- StreamingEnabled is false. A plot can reach about 2,200 parts: 1,158 base, plus 357 for the extensions, 4 cars and the equipment.
- With 8 plots that is about 17.5k parts, plus about 1.2k PreviewCar parts, all replicated to every client before any minigame venues are added.

**G11. Travel defeats the walk.** Every tablet nav button (GarageClient L83) and the "Zum Ziel" button teleport the player. A bigger walkable world needs a design decision on whether to keep instant travel.

### Integration points
- GarageServer.request L372-389: insert the mini dispatch before act() at L388, wrapped in pcall (3.0 Actions.lua L99 did this, 2.4 act() does not). Exempt mini actions from the per-action-name 0.12 s cooldown (L381-383), or key it by action+target (parking_tap cell, press_buy id); otherwise rapid taps on different buttons are silently dropped.
- GarageServer join character() L414-424 -> moveTo(Stations.home) L423: this is the real arrival point for every spawn and respawn. Player lands at (-64,3.5,31.5), derived from the home anchor (-64,5,25.5), the same position as Stations.workshop. A redesigned reception must move Werkstatt.Stations.home and keep open floor at (x, 3.5, z+6).
- GarageServer.moveTo L87-97: Y is hard-coded to plotY+3.5 and the offset is world +Z 6. Replace it with an anchor-relative arrival (e.g. a child 'Arrival' part) before adding elevated stations (mezzanine quiz room) or rotated plots.
- World.doorwayOccupied L74-84: world-axis |dX|<11, |dZ|<2 test. Make it plot-local if plots are ever rotated around a shared hub.
- World.W.Create L55-70: prompts are bound only if they are a direct child of a direct child of Stations/YardActivities (FindFirstChildOfClass) and exist in PlotTemplate at clone time; late-added minigame prompts need their own Triggered binding with the p==player owner check.
- Workspace.Werkstatt.Start SpawnLocation (-64,0.13,31; Neutral, Enabled, invisible, non-collidable) is cloned per plot. Add a permanent global ground+spawn outside the plot grid (X -141..1131, Z -88..392), or set Players.CharacterAutoLoads=false and call LoadCharacter after W.Create (GarageServer L401-409). Disable plot pads if a hub spawn is added.
- GarageClient Event 'state' handler L404-410: rebuild() runs on every revision even when the tablet is hidden. homePage L161-178 creates 10 viewports (viewport() L146-160, 122-149-part clones each). Minigame updates must use push(p) or a separate Event kind, never changed(p).
- GarageClient L324 (unused local 'visual'), L327-348 and L392-401 (state.target), and ClientEffects L50/L55 (FX point): the only Instance references that matter if StreamingEnabled is ever enabled.
- Rules.R.Settle L294-303 and R.FinishYard L171-177: call the ported AddStat(d.games, 'jobsDone'/'yard', n, os.time()) with a non-passive now, so daily.active (3.0 Rules.AddStat L321-331) is set for workshop-only players.
- Rules.R.LoadData L30-112 (games block before R.Advance L110): decide how veterans are seeded. Option: games.stats.jobsDone from d.completed. m_level_25 (3.0 Config L176, GoalRules.Stat L16) is otherwise instantly claimable for 5000 Cr by any 2.4 player at level 25 or above.
- Profiles.Save L67 and GrantCredits L111 use Rules.Snapshot (clone depth limit 12, Rules L9-13): keep d.games nesting shallow (currently about 4 levels).
- GarageServer tick L435-448 + 3.0 PressService.Tick L39-47 (dt capped at 10 s): if Mini.Tick is skipped while transacting, accumulate production; GrantCredits (Profiles L102-140) only restores money, so scrap production during the window is safe.
- GarageServer PlayerRemoving L431-434: W.Destroy runs only after P.Save(release) yields. Consider destroying the plot/freeing W.slots first (P.Save does not need the plot) to avoid the rejoin kick at L408 on full servers.
- Place XML Lighting (Brightness 2.6, no Technology, no Sky): set Technology explicitly and add lighting for night. ClockTime is driven at GarageServer L438 and GarageClient L555; 50% of each 1200 s cycle is night.
- tools/validate.py L166-170 (A2: no rbxassetid/roblox.com/asset in scripts): animations for drive-in cars, press and tuning must be procedural (TweenService/PivotTo/Motor6D C0), like W.Lift L150-166 and CarFactory.WorkEffect L211-240.
- 3.0 src/server/World.lua L145-150 (Schrotthändler at 34,0,-38) and L184-199 (Quiz 36,36; Parkplatz -36,36): their rotated 18x18 platforms intrude into the Stage_4 annex and the hall front. They must be relocated into plot-local free zones, not just translated.

### Risks
- First-join void spawn: Workspace holds only Werkstatt (destroyed at World require) and Camera, so until the first W.Create there is no SpawnLocation and no floor. A character that loads before P.Load finishes can fall past FallenPartsDestroyHeight -80 and respawn after RespawnTime.
- Random spawns into foreign plots: the Neutral 'Start' pad exists in every plot (up to 8), so (re)spawning characters appear in other players' plots before moveTo. A shared hub SpawnLocation would just be one more random candidate unless the plot pads are disabled.
- Elevated or rotated minigame venues break travel and arrival: moveTo forces Y=plotY+3.5 and world +Z 6 (GarageServer L95); doorwayOccupied uses world axes (World L79-80).
- Client frame spikes: rebuild() on every revision (even with the tablet hidden) re-clones about 1,300 preview-car parts on the home page. Any minigame path that calls changed(p) at click or tick rate causes continuous rebuild thrash.
- Silent input loss: the 2.4 per-action-name cooldown of 0.12 s drops a second parking_tap or press_buy for a different target inside 120 ms. The 3.0 UI only debounces per button, so the player gets no feedback.
- Unprotected handlers: 2.4 act() has no pcall. An error in a ported 3.0 handler aborts mid-mutation after budget and cooldown are consumed; 3.0 relied on Actions.Handle's pcall.
- Veteran windfalls or stalls: m_level_25 (5000 Cr, 0 XP) is instantly claimable by 2.4 players at level 25 or above; jobsDone starts at 0 despite d.completed; daily.active is never set by workshop-only play unless R.Settle/R.FinishYard call AddStat.
- Production loss during Robux grants if Mini.Tick is skipped while transacting: PressService.Tick caps dt at 10 s, while GrantCredits can hold transacting longer than 10 s (10 s wait for a running save plus retry waits).
- Studio re-save of the script-generated base (ElementTree header, many default properties absent) rewrites the file and invalidates the byte-identical build gate and any fingerprint checks.
- Night visibility and look: Lighting.Technology is unset (engine default, not Future), there is no Sky, and half of every 20-minute cycle is night. The exterior has only 4 street lamps (Range 20) per plot, and every added light is multiplied by 8 plots.
- Asset rule: validate.py A2 bans rbxassetid in scripts, so Animation/KeyframeSequence-based character or car animations and asset sounds would fail validation. Only procedural tweens and rbxasset:// built-ins are allowed.
- Rejoin race on full servers: W.Destroy runs after P.Save(release) yields, so the old slot stays taken. A fast rejoin gets a temporary non-saving profile (foreign lock still fresh) and can be kicked with 'Alle Werkstätten sind belegt' at GarageServer L408.
- Replication budget: StreamingEnabled=false means about 17.5k plot parts (8 plots x ~2,200 at 4 bays with cars and equipment) plus about 1.2k PreviewCar parts reach every client before any minigame venue is added.
- Keeping any part of 3.0 World.Build: besides the known origin overlap, the Schrotthändler and Quiz platforms clip into the Stage_4 annex, Parkplatz extends about 10 studs into the hall through the roller door, and Schrottplatz covers about 104 sq studs of the hall.
- R.Snapshot depth limit (12) silently drops deeper tables on Save/GrantCredits; any future deeply nested minigame state would vanish without error.