## 2.4.0 server: how it works (read-only analysis)

Sources: `/tmp/claude-0/old/scripts/*.lua` (line numbers below refer to these files) and `/tmp/claude-0/old/old.rbxlx`. That place file is byte-identical to `/home/user/Ultimate-Car-game/Ultimate_Car_Game/base/Ultimate_Car_Game_2.4.0.rbxlx` (same md5). Throwaway parsers are in `/tmp/claude-0/scratch_server/`.

### 1. Boot order (`Garage.GarageServer.Script.lua`)
1. **L1-9: requires.** It requires Config and Rules, then Profiles, CarFactory, World and Purchases.
   - **Profiles** (L9-16) opens the DataStore when it is required. It uses `Config.DataStoreName="UltimateCarGame_v2"`, or the Studio name in Studio. Saving only happens if `EnableSaving and (not Studio or SaveInStudio)`. `SaveInStudio=false`, so **Studio never saves**.
   - **World** (L7-10), also at require time: `workspace.Werkstatt:Clone()` goes to `ServerStorage.PlotTemplate`, then `workspace.Werkstatt:Destroy()`, then it creates `workspace.PlayerWorkshops`.
2. **L9: remotes.** `Remotes.Command` and `Remotes.Event` are static in the XML (`ReplicatedStorage.GarageShared.Remotes`). There are **only 2 RemoteEvents**: no RemoteFunctions, no Bindables.
3. **L10-15: state and time.** It creates `sessions` and `joining`. `dayEpoch=workspace:GetServerTimeNow()` (the server start) and `Lighting.ClockTime=8`.
4. **L390:** `Command.OnServerEvent:Connect(request)`.
5. **L391:** `Purchases.Init(getSession,onGranted)`, which sets `MarketplaceService.ProcessReceipt`.
6. **L429-430:** `PlayerAdded→join`, plus `task.spawn(join)` for players already in the server.
7. **L431:** PlayerRemoving. **L435:** 0.5 s tick loop. **L449:** autosave loop. **L452:** BindToClose.

### 2. Remote protocol
**Client→server:** `Command:FireServer(action:string, args:table)`. The action set, with the args each one reads:

| Action | Args |
|---|---|
| `hello` | – |
| `travel` | `{key}` (teleports to the station) |
| `select` | `{id}` |
| `target` | `{id, car?}` (teleport, "Zum Ziel") |
| `swapTool` | `{slot,id}` |
| `tool` | `{id}` |
| `accept` | `{id}` |
| `work` / `scan` | `{id, point?}` |
| `door` | – |
| `lift` / `hood` | `{id}` |
| `diagnose` | `{id, choice}` |
| `hit` | `{token, at}` |
| `abortInteraction` | `{token}` |
| `yard` | `{id}` |
| `settle` | `{id}` |
| `confirm` | `{key="cancel",id}` or `{key="bays"}` |
| `commit` | `{token}` |
| `partSelect` | `{job, sku}` |
| `order` | `{sku, qty}` |
| `deviceMenu` | `{id}` |
| `assignEquipment` | `{id, bay}` (bay=0 means storage) |
| `equipment` / `upgrade` | `{id}` |
| `buyCredits` | `{key}` |
| `save` | – |

**Server→client:** `Event:FireClient(kind, data)`.

| Kind | Payload |
|---|---|
| `state` | `{data=R.Snapshot(d), revision, selected, tool, objective, target(Instance), time, dayEpoch, interaction={token,kind,expires}, neededXP, shopReady, saveStatus, visuals={[jobId]={lifted,hood,moving,model}}, plot=model}` |
| `toast` | string |
| `interactionReset` | `{token}` or nil |
| `page` | station key |
| `close` | – |
| `diagnose` | `{job,car,report,answers,phase}` |
| `scan` | `{duration,tool,point}` |
| `challenge` | the whole pending table: `startAt, period, center, width, expires, token, point…` |
| `workFX` | `{tool,point,duration}` |
| `diagnosisDone` | jobId |
| `confirm` | `{token,key,job?,stage?,cost?,level?,expires}` |
| `receipt` | `{money,xp,levels,name,quality}` |
| `purchaseFX` | `{title,detail}` |
| `device` | `{id}` |
| `purchasePrompt` | `{productId}` |

The client also handles `challengeEnd`, but the server never sends it.

**Dispatch.** `request()` (L372-389) is one gate in front of one if-chain, `act()` (L184-371). It checks, in order:
- The session exists and is not closing, and `#action<=32` (L373).
- While `profile.transacting`, only `hello` and `abortInteraction` get through; everything else gets a toast (L374).
- Args are sanitised (L376): at most 10 keys, string keys of 24 chars or fewer, values only string/number/boolean, strings of 100 chars or fewer, numbers finite with |v|≤1e25. **No nested tables.**
- `validateInteraction` runs.
- **Remote budget** (L379-380): a token bucket of 30 that refills at 20/s and costs 1 per request. A `hit`/`abortInteraction` carrying the current pending token is free.
- **Per-action cooldown** (L381-383): 0.12 s, except for hello, hit and abortInteraction.
- Then `R.Advance`, `advanceDays`, delivery arrival and `W.Sync` if anything changed.
- Finally `act()` runs.

Extra throttles: `buyCredits` 3 s (L361), `save` 30 s (L368).

**Prompt callbacks.** ProximityPrompt callbacks enter through the `W.Create` callback (L401-407):
- `station` bypasses `request` completely.
- `expand` becomes `request("confirm",{key="bays"})`.
- `lift` maps the bay to its job and calls `request("lift")`.
- Everything else becomes `request(kind,{id=value,point=point})`.

### 3. Repair workflow end to end
**Offers.** `R.RefreshOffers` (Rules L178-199) always keeps one `inspection` offer and fills up to `offerSlots`. It runs at join, and after accept, settle and equipment/upgrade purchases.

1. **Accept** (L225-230). The player must be within 10 studs of `Stations.workshop` (the reception terminal at (-64,5,25.5)). `R.Accept` needs a free bay, the level, and `RequiredEquipment`. It creates the job `{id="job_N",kind,carId,bay,phase="diagnose",step=1,quality=100,scanReady=false,selectedParts={},usedParts={}}`. Then `changed()` → `W.Sync` → `W.Spawn`: the car **appears instantly** at `bay.CarOrigin`.
2. **Diagnosis (OBD)**, in `work()` (L123-162):
   - Needs the scanner tool active, the player within 8 studs of `DiagnosticPoint`, and the lift not moving.
   - Creates pending `{kind="scan", token=GUID, expires=now+3}` and runs `beginInteraction`.
   - Emits `scan` (2.5 s) and plays the server FX `F.WorkEffect`.
   - `task.delay(2.5)` re-checks character, proximity and tool, then sets `scanReady=true` and emits `diagnose` (report and answers).
   - The client sends `diagnose{choice}`; `R.Diagnose` handles it. A wrong answer costs quality −5. The right one sets `phase="repair"` and emits `diagnosisDone`.
3. **Repair steps** (`C.Jobs[].steps`). `jobConditions` (L98-118) requires all of the following:
   - lift state equals `step.lifted`
   - hood open if `step.hood`
   - a tool that is in the loadout and matches, `step.tool` or `step.alternatives`
   - the equipment level, **and** the equipment assigned to this bay (`equipmentBays[eq]==j.bay`), **and** that equipment not busy on another working job
   - the part present (`R.ChoosePart`; an explicitly chosen brand is never substituted)
   - the player within 8 studs of `step.point`

   It then starts the **gauge QTE**: `startAt=now+0.7, period=1.5, center=0.62, width=min(0.48,0.28+(toolLevel-1)*0.006), expires=now+12`. The client animates the cursor with `R.GaugePosition(serverTime)` and sends `hit{token,at=GetServerTimeNow()}`.

   The server (L253-271) accepts `at ∈ [now-0.5, now+0.06]` if `R.GaugeHit` passes. A miss costs quality −2. A hit calls `R.StartWork`: it consumes the part, sets `phase="working"` and `workUntil=now+StepDuration`. Then `F.Effect` (visual state), `F.WorkEffect` and `workFX` fire. The player can work on other cars in parallel.
4. `R.Advance` (tick and every request) moves a job to `step+1` once `workUntil` has passed. After the last step the job moves to `verify`.
5. **Final check:** lift lowered and hood closed, then another scan (2.5 s) → `phase="invoice"`.
6. **Billing:** `settle` at `Stations.workshop` → `R.Settle`. It removes the job first (so a replay is safe), restores parked jobs, adds money, `completed`+1, reputation +2 and XP (`R.GainXP`: level-up pays `120+18L` Cr and +2 reputation). It emits `receipt`. `W.Sync` then destroys the car instantly.

   Cancelling works through a confirm token (30 s) and `commit` → `R.CancelJob`.

**Interaction tokens and abort.** `p.pending` holds at most one interaction (`scan`, `gauge` or `yard`) with a GUID and an expiry.
- `beginInteraction` (L47-56) stores `character` and `tool`, sets `world.interactionJob` (W.Sync then disables that job's prompts) and schedules a `task.delay` reset at expiry.
- `validateInteraction` (L40-46) runs on every request and every tick. It resets the interaction on expiry, a changed character, a changed tool, the player more than 8 studs from the point, or a change in the job's phase, step or selection.
- `resetInteraction` emits `interactionReset`. A nil payload closes any client modal.
- A stale `abortInteraction` (token mismatch) is ignored (L274).
- Travel, target, select, a tool switch and respawn all reset.

**Toolbox and 5 slots.** `d.loadout` holds 5 of the 8 `C.ToolOrder` tools. `swapTool` needs the player within 9 studs of `Stations.tools` (-43,4.7,-26.1) and no pending interaction.
- `tire` unlocks with `wheel_jack`, `meter` with `diagnostic_rig`.
- `tool` runs `F.Equip`, which builds a server-side "GarageTool" model welded to the right hand.
- Hotbar keys 1-5 live on the client (InputController).

**E/F/H.** All three are Custom-style prompts with a `VehicleAction` attribute. The client mirrors them into its "VehicleActions" buttons.

| Key | Gamepad | Prompt | Where | Details |
|---|---|---|---|---|
| E | ButtonX | `WorkPrompt` | only the current target point | hold 0.12 s, range 8 |
| F | ButtonB | `LiftControl` | each bay | enabled only with a job on the bay, not moving, not working |
| H | ButtonY | `HoodPrompt` | HoodPoint | – |

Station prompts use the default style with E. Space/ButtonA stops the QTE, Tab opens the menu.

**Server vs client.** The server does all logic, timers, validation, world mutation, prompt enabling, the `WorkPoint` highlight attributes, the lift/door tweens, the FX parts and `Lighting.ClockTime`. The client does the UI, the gauge rendering, the hit timestamp, the arm/grip animation (local Motor6D C0), the highlight and billboard, click-to-work on car parts, the jump lock, a local ClockTime interpolation, and disabling prompts under a foreign `OwnerUserId`.

### 4. World and plot features
**Per-player plot (World L51-72).**
- There are `C.MaxPlots=8` slots. Each slot clones the full template to `CFrame.new(((slot-1)%4)*330,0,floor((slot-1)/4)*260)`, so slot 1 sits at the origin.
- The clone is named `Plot_<UserId>` and gets the attribute `OwnerUserId`.
- Every plot is a complete private copy of the 280×220 yard. It is fenced by invisible, collidable `Boundary` walls 52 studs high at X±140, Z-82 and Z132, so **players cannot walk between plots**.
- About 1,157 parts per plot, plus extensions and cars. If there is no free slot, the joining player is kicked (GS L408).

**Static (XML) vs runtime.**
- **Static:** all architecture and decor; Bay_1; reception at (-64,*,24); office with the parts PC (-69,4.75,2.8) and the upgrades PC (-59,4.75,2.8); shop kiosk (-69,4.6,19.4); tool chest; roller door (ClosedOrigin (-43,5.95,31.6), 19.8 wide); expansion ring (-36,0,21); yard stations pressure (88,1.5,62) and recycle (-88,0.5,63); parking and show cars at Z≈64-78; road at Z 96; spawn "Start" at (-64,0.13,31). Also `ServerStorage.WorkshopExtensions.Stage_2..4`, `CarTemplates`(9), `EquipmentTemplates`(8) and `GarageShared.PreviewCars`(9).
- **Runtime (World):**
  - plot clone and pivot
  - prompt bindings
  - the door `Open` attribute
  - `layout()` (L23-50): clones `Stage_i`, pivots it to the plot pivot (stages are authored in plot-local coordinates with their Root at the origin), and reparents `Bay_i` into `Bays`. It moves `EndWall` to X=`-32+(bays-1)*22` and `ExpansionPoint` by `(bays-1)*22`, destroying the latter at 4 bays. It also updates the sign text and ring colour.
  - bay signs, and the lift prompt's `Enabled`, `ActionText`, key and JobId
  - cars and their prompts
  - equipment clones with `LevelIndicator`, `IndicatorMount` and `AssignPrompt`
  - delivery boxes
  - the door and lift tweens

  The hall is X -74..-32 with 1 bay and grows to X -74..34 with 4 bays; Z -33..32; roof bottom at Y 20.

**Only these names are referenced by code.** Everything else (Architecture, Details, Reception, Office, UpgradeBench, CreditShopStation) is decorative and free to redesign.
- `Stations.{home,workshop,parts,upgrades,tools,shop}`
- `Bays.Bay_n.{CarOrigin,PlayerArrival,EquipmentSpot,LiftControl,MovingLift,Sign}`
- `RollerDoor.{Panel,ClosedOrigin,Control}`
- `ExpansionPoint.{Activate,Sign,Ring}`
- `EndWall`, `Extensions`, `ActiveCars`, `Equipment`, `EquipmentPositions.<id>`
- `PartsArea.{DeliveryOrigin,DeliveryBoxes}`, `YardActivities`, `PrimaryPart` Root

**Lifts.** `W.Lift` tweens a NumberValue for 2 s (Sine) to `LiftHeight=3.6`. Each `Changed` does a PivotTo of the anchored car **on the server** plus a PivotTo of `MovingLift`. `v.moving` blocks interactions.

**Extensions.** Levels come from `C.BayLevels={1,2,4,8}`. The cost is `800*1.7^(bays-1)`. It is bought through the confirm/commit token (`expansionQuote` L171-183, commit L313-320), which triggers an immediate `P.Save`.

**Equipment.** `R.AssignEquipment` allows one device per bay. `W.Equipment` places the device at `bay.EquipmentSpot` (Bay_1 at (-36.8,0,7.5)) or at storage `EquipmentPositions` (X -70/-62, Z -24..-4.5).

**Parts and deliveries.**
- `order` needs `Stations.parts`. Parts with `eta=0` go straight to inventory; the others become `d.orders` with a 60-120 s ETA.
- On arrival, `W.Deliver` spawns a box at `DeliveryOrigin` (-70,0,-29.8) and destroys it after 40 s.
- `partSelect` has no proximity check.

**Roller door.** Purely cosmetic: a 1.8 s tween of Panel size and CFrame. It refuses to close if anyone is in the doorway and reopens automatically if the doorway is occupied after closing.

**Day/night.** `C.DaySeconds=1200`, start hour 8. `R.DayClock(now,dayEpoch)` is per server. `advanceDays` adds midnights passed while online to `d.days`. Both the server (0.5 s) and the client (0.1 s) write ClockTime.

**Yard tasks.** `C.YardTasks` pressure (35 Cr, 6 XP) and recycle (25 Cr, 5 XP) with a 120 s cooldown stored in `d.yardReady`. They run as a pending `yard` interaction with a `task.delay`, then `R.FinishYard`.

**Credits shop.** Five `C.CreditProducts`, **all with productId=0**, so `buyCredits` always answers "noch nicht verfügbar". `ProcessReceipt` (Purchases L21-40) resolves the product by id, then `Profiles.GrantCredits`, which commits the credits and the receipt marker atomically. Otherwise it returns NotProcessedYet and retries every 8 s while the session is still writable.

### 5. Profiles
**Record.** Key `"Player_"..UserId`. Shape: `{version=2, data=<Rules.LoadData-normalised>, receipts={[PurchaseId]=true}, lock={token=GUID, expires=os.time()+180}}`.

**Load (L18-54).**
- Up to 3 `UpdateAsync` attempts. A foreign lock that has not expired gives an **immediate temporary session (no retry)**.
- Load **writes the normalised data back immediately**.
- A failed load gives a temporary profile and never overwrites the stored one.

**Save (L56-98).**
- Refuses when the profile is not writable or `receiptPending` is set.
- On release it waits up to 12 s for a running save.
- Checks the lock token. A lost lock sets `writable=false`.
- Release sets `lock=nil`.

**Other timing.** Autosave runs every 45 s through `task.spawn` for each player. BindToClose saves everyone with release and waits at most 25 s. `R.LoadData` is a **whitelist**: it builds `NewData()` and copies only known fields; `raw.version~=2` means a full reset. It also migrates old 6-bay saves and applies offline `R.Advance`.

**Data fields.**
- `version, workshopVersion, days, money, xp, level, reputation, bays, offerSlots, toolLevel, jobs[], offers[], orders[], inventory{}, equipment{}, equipmentBays{}, serial, completed, loadout[5], yardReady{}, parkedJobs[]`
- Timestamps are absolute unix seconds.

### 6. CarFactory
`F.Spawn` (L6-22):
- Clones `CarTemplates[def.body]`: all parts are anchored, PrimaryPart is Root, and the front faces −Z (toward the back wall).
- Names the clone after the jobId and sets the attributes `OwnerUserId` and `JobId`.
- Recolours the parts named Paint, Hood and Mirror.
- Pivots the car to `CarOrigin` and calls `SetHood(false)`.

Behaviour:
- **Cars never drive.** Only the lift moves them.
- `SetHood` puts the hood at a hard-coded hinge `root*(0,3.9,-3.55)*rot(65°)*(0,0,-1.95)`.
- `Effect` toggles the WheelFL*, WheelFR*, Battery*, Ignition*, Hose* and Turbo* parts and recolours others. `newTire` and `fill` do nothing.
- `TargetParts` names the parts that get the `WorkPoint` attribute.
- `AddPrompt` creates the E prompt.
- `Equip` builds the hand-tool models.
- `WorkEffect` creates temporary neon FX with tweens.

### 7. Loops, spawns and cleanup
**Loops.**
- Tick every 0.5 s (L435-448): ClockTime, then for each session `advanceDays`, `validateInteraction`, `R.Advance`, `W.Sync` if something changed, `W.Deliver`, and **a full `push` of the state every time**.
- Autosave every 45 s.

**Delayed work (`task.delay`).** Interaction expiry, the scan (2.5 s), yard tasks, delivery boxes (40 s) and FX cleanup.

**`task.spawn` uses.** Join, the initial character, save on bay commit, the `save` action, autosave, BindToClose saves and the receipt retry loop.

**PlayerRemoving (L431-434).** `advanceDays`, set `closing`, clear `pending`, then `P.Save(release)`, which yields. Only after that does it clear `sessions` and call `W.Destroy`: cancel the door tween, remove the cars, destroy the model, free the slot.

### 8. Existing quirks worth knowing
- The tools prompt range is 10 but the server check is 9.
- `Stations.home` has no prompt.
- A lost lock during `GrantCredits` leaves `transacting=true`, which locks out all actions for the rest of the session.
- The QTE `at` window of 0.5 s is client-choosable, but that only affects quality.
- The lift is animated by server PivotTo of about 130 parts per frame.
- The full data snapshot is sent at 2 Hz per player.
- With no plots yet, there is no SpawnLocation in the workspace.

### Integration points
- GarageServer.request() L372-389: route 3.0 actions right before `act(p,action,a)` at L388. Keep the transacting guard (L374), the flat-args sanitizer (L376: ≤10 keys, primitives only, strings ≤100), the token bucket (L379-380: 30 burst, 20/s) and the 0.12 s per-action cooldown (L381-383). The 3.0 Net.Actions payloads (press_click{count}, quiz_answer{token,choice}, parking_tap{cell}, …) are flat and pass it.
- GarageServer.act() L184-371: add the 3.0 action branches or a registry fallback after the `save` branch (L368-370). Use messageResult/changed only for world-visible changes.
- GarageServer.push() L71-80: the 'state' payload goes out every 0.5 s. Send 3.0 state as a separate Event kind (e.g. emit(p,'games',…)) rather than bumping p.revision, because the client rebuilds the tablet on every revision change (GarageClient L410).
- GarageServer.join() L394-428: after R.RefreshOffers/W.Sync/W.Equipment (L413), initialise the 3.0 services on the same session `p` (p.profile.data). Reuse the leaderstats created at L411-412 (Credits=d.money, Level=d.level).
- GarageServer tick loop L435-448 (0.5 s): add press machine income, idle-tuning progress and goal/daily checks inside `for _,p in pairs(sessions)`. Skip them when p.profile.transacting, like advanceDays (L17).
- GarageServer PlayerRemoving L431-434 and BindToClose L452-456: add the 3.0 leaderboard writes/cleanup. P.Save(release) yields and W.Destroy runs after it; the BindToClose deadline is 25 s.
- Purchases.Init (Purchases.lua L14-40; called at GarageServer L391-393) is the only MarketplaceService.ProcessReceipt owner. Any 3.0 developer products must go through it. The 3.0 game passes (UserOwnsGamePassAsync / PromptGamePassPurchaseFinished) do not conflict.
- Profiles.lua record transforms at L36 (Load), L79 (Save) and L127 (GrantCredits) all rebuild {version=2,data,receipts,lock}. A new top-level field must be added to all three, so store minigame progress inside `data` instead.
- Rules.NewData L23-29 and Rules.LoadData L30-112: add a namespaced, whitelist-normalised minigame subtable (e.g. d.games={press=…,tuning=…,goals=…,daily=…}). Keep d.version==2 (L33). Map 3.0 `credits` to d.money and use R.GainXP (L122-130); the XP formula (80+22L+L^1.16*4) and level bonus (120+18L, +2 reputation) are identical to 3.0.
- World.lua L7-10: workspace.Werkstatt is cloned to ServerStorage.PlotTemplate and destroyed at require. Per-plot minigame stations must be authored inside Werkstatt in the XML (or added to PlotTemplate before the first W.Create). Global/shared geometry must sit outside the plot grid: plots cover X -140..1130, Z -82..392 (slot pitch 330 in X, 260 in Z; slot 1 at the origin).
- World.W.Create L60-63: any ProximityPrompt under Werkstatt.Stations auto-binds to callback('station',name) → station(p,name) (range 10, or 9 for 'tools') → emit 'page' name. New stations also need C.StationNames (Config L185-186) and a client page in GarageClient `pages` (L301) and nav (L79-87).
- World.W.Create L66-70: any prompt under Werkstatt.YardActivities auto-binds to the 'yard' action with a C.YardTasks key (Config L197-200). This is a cheap hook for small outdoor tasks that share the pending/timer/reward path (act L277-296).
- World.layout L23-50: extension geometry uses fixed constants: EndWall X = -32+(bays-1)*22 (L32), ExpansionPoint offset (bays-1)*22 (L36), Stage_n pivoted to the plot pivot (L28). A higher or wider hall redesign must update these and the Stage_2..4 models together.
- World.W.Spawn L119-137 / W.Remove L138-145 / CarFactory.Spawn L6-22: hooks for drive-in and drive-out animation. Set v.moving=true during a drive-in tween (the NumberValue+PivotTo pattern from W.Lift L150-166) and call changed(p) when done. A drive-out must be a detached visual clone because R.Settle removes the job before W.Sync destroys the car. Car path for Bay_1: through the roller door at (-43, *, 31.6) to CarOrigin (-43,0,-5), front facing -Z. Annex bays 2-4 have open fronts at Z 32 (CarOrigin X -21, 1, 23).
- CarFactory.SetHood L24-29 (hinge root*(0,3.9,-3.55), 65°, -1.95 offset) and Effect/TargetParts L60-92: the contract for redesigned car templates. Keep Root as PrimaryPart; keep the parts DiagnosticPoint, EnginePoint, BatteryPoint, WheelPoint, OilPort, HoodPoint, Hood, OBDPort, OilPan, OilFilter, DrainBolt, Turbo, Battery, EngineBayFloor, WheelFLTire, WheelFLRim, BrakeFL/FR, Engine, Ignition, Hose; keep the WheelFL*/WheelFR*/Battery*/Ignition*/Hose*/Turbo* prefixes; recolouring applies to parts named Paint/Hood/Mirror. Mirror every change in ReplicatedStorage.GarageShared.PreviewCars.
- Day/night: GarageServer L14-15 (dayEpoch, ClockTime=8), L438 (server ClockTime every 0.5 s) and GarageClient L555 (client every 0.1 s) via R.DayClock (Rules L19-22, DaySeconds=1200). 3.0 daily/goal timing should use real time; any lighting ambience must read state.dayEpoch rather than write ClockTime.
- World.W.Create L56 plot pitch and Config C.MaxPlots=8 (Config L16): a bigger per-plot world needs a larger pitch (the current per-plot footprint of 280×214 inside boundaries leaves 50-stud and 46-stud gaps), and Players.MaxPlayers must stay ≤ MaxPlots (kick at GarageServer L408).

### Risks
- DataStore clash: 3.0 Config.ProfileStoreName is the same 'UltimateCarGame_v2' but ProfileKeyPrefix is 'player_' (lowercase), while 2.4 uses 'Player_'. Keys are case-sensitive, so the standalone 3.0 Profiles would give every existing player a fresh profile. If the prefix is 'fixed' to 'Player_', 3.0 would treat the 2.4 record root {version,data,receipts,lock} as its own profile, ignore the 2.4 `lock` (it uses `_lock={job,id,t}`), and write back stale deep copies of `data`/`receipts`. The result is lost progress and lost Robux receipt markers (double-grant or lost purchase). Only one Profiles module (2.4's) may own this key.
- Rules.LoadData (Rules L30-112) is a whitelist and Profiles.Load writes the normalised record back immediately (Profiles L35-36). Any 3.0 field not added to NewData/LoadData is silently deleted on the next join, and a place rollback to 2.4.0 permanently strips all 3.0 progress stored in `data`.
- Changing data.version away from 2 makes R.LoadData return NewData (Rules L33): a full wipe of every player's career. The record-level version=2 is also hard-coded in Profiles L36/L79/L127.
- Profiles.Save (L79) and GrantCredits (L127) rewrite the record as {version,data,receipts,lock}. A new top-level sibling field is dropped on every 45 s autosave. Dropping or renaming `receipts` removes the idempotency guard for ProcessReceipt.
- Money race: GrantCredits sets profile.data.money=result.data.money on success (Profiles L131), taken from a snapshot made before the commit. Credits added by 3.0 ticks or actions during the transaction window are lost. 3.0 code that bypasses request() (its own remote or tick) must honour profile.transacting/receiptPending like request() L374 and advanceDays L17 do.
- d.bays > 4 crashes World.layout: SS.WorkshopExtensions['Stage_5'] is nil (World L27) and W.Sync errors on every changed()/push for that player. The 3.0 Config.Upgrades defines bays (max 50, base 1100, growth 1.42) with the same key names as 2.4 (bays/offerSlots/toolLevel). The 3.0 upgrade_buy and the 3.0 simplified workshop (WorkshopService/WorkshopRules) must not touch the 2.4 d.bays/d.jobs; drop the 3.0 workshop in favour of 2.4's.
- 3.0 World.Build puts its 'Hof' at workspace origin: a 400×400 grass slab at Y -1 (top Y 0) plus an asphalt layer, which covers the 2.4 yard (top Y -1.0), z-fights the hall floor (top Y 0) and sits exactly on plot slot 1 (pivot at 0,0,0). Its station at (-50,0,0) intersects the Bay_1 lift post (-50,6,-4), and it adds an extra Neutral SpawnLocation at the origin. Relocate it or rebuild the stations inside the plot template.
- workspace.Werkstatt no longer exists at runtime (destroyed at World require, World L9). Anything that looks it up after boot fails; static edits must go into the XML Werkstatt (the per-plot template). Geometry placed outside Werkstatt is global and shared, but plots are walled off by invisible 52-high Boundary walls (X±140, Z -82/132), so shared hubs are reachable only by teleport.
- Renaming or removing code-referenced anchors breaks 2.4: Stations.*, Bays.Bay_n.{CarOrigin,PlayerArrival,EquipmentSpot,LiftControl,MovingLift,Sign}, RollerDoor.{Panel,ClosedOrigin,Control}, ExpansionPoint.{Activate,Sign,Ring}, EndWall, Extensions, ActiveCars, Equipment, EquipmentPositions.<id>, PartsArea.{DeliveryOrigin,DeliveryBoxes}, YardActivities, the plot PrimaryPart Root, and the car/equipment template part names. Changing hall width or height without updating the 22-stud constants in World.layout misplaces EndWall and ExpansionPoint.
- Redesigned cars must keep the CarFactory contract (anchored parts, Root PrimaryPart, front toward -Z, named points and prefixes, the Hood hinge constants in SetHood L28). Moving the work points changes the 8-stud reach checks (near() in jobConditions/work) and bay.PlayerArrival teleports.
- UI churn and performance: every changed() runs W.Sync and increments p.revision, and the 2.4 client rebuilds the whole tablet on a revision change. High-frequency minigame actions (press clicks batched at 0.5 s) must not call changed(). push() already sends a full deep snapshot at 2 Hz per player, so adding big 3.0 tables to it doubles the bandwidth.
- Only one MarketplaceService.ProcessReceipt can exist. Any 3.0 code assigning it would silently disable the 2.4 credit-receipt path (currently inert because all productIds are 0, but it becomes live once IDs are set).
- Studio writes to production: 2.4 never saves in Studio (SaveInStudio=false), but 3.0 Profiles.Init opens 'UltimateCarGame_v2' in Studio whenever API access is enabled. Test sessions would then write live player data.
- Session-lock behaviour differs: 2.4 returns a non-saving temporary session immediately when a foreign lock is fresh (Profiles L46-48, lease 180 s). Minigame progress earned in such a session is lost without a clear warning, and a second 3.0 lock system on another key would not coordinate with it.
- Input conflicts on the client: InputController always sinks Tab (priority 10000) and keys 1-5 (priority 3000), and sinks Space/ButtonA/jump during a QTE. The 2.4 client disables prompts under any model whose OwnerUserId is a different player, and routes only prompts that carry a VehicleAction attribute. Custom-style prompts without that attribute render nothing.
- Duplicate leaderstats: 2.4 creates leaderstats (Credits, Level) in join (L411-412); a second folder from 3.0 code would confuse the player list and scripts.
- Capacity: exceeding C.MaxPlots=8 kicks players (GarageServer L408), and each plot duplicates the full template (~1,157 parts plus up to 357 extension parts plus cars). Enlarging the per-plot world multiplies by 8, and the plot pitch (World L56: 330/260) must grow or the plots overlap.