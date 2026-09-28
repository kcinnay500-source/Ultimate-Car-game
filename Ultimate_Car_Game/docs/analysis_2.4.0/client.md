# 2.4.0 client: how it works and where the 3.0 minigames fit

Files analysed (read-only):
- `/tmp/claude-0/old/scripts/StarterPlayerScripts.GarageClient.LocalScript.lua` (563 lines, called **GC** below)
- `/tmp/claude-0/old/scripts/StarterPlayerScripts.InputController.ModuleScript.lua` (**IC**)
- `/tmp/claude-0/old/scripts/StarterPlayerScripts.ClientEffects.ModuleScript.lua` (**FX**)
- Supporting context from `Garage.GarageServer.Script.lua`, `Garage.World.ModuleScript.lua`, `Garage.CarFactory.ModuleScript.lua` and `old.rbxlx`, parsed with the helper `/tmp/claude-0/scratch_client/*.py`.
- The 3.0 client in `/home/user/Ultimate-Car-game/Ultimate_Car_Game/src/client/`.

The place file has **no StarterGui, no Sound, no ParticleEmitter, no Animator and no custom camera script**. All UI is built in code.

## 1. UI structure

**ScreenGui:** `UltimateCarGame` (GC:66). DisplayOrder 20, ResetOnSpawn=false, IgnoreGuiInset=false, ZIndexBehavior Sibling.

**Helpers**
- `make`, `corner` (radius 10), `frame`, `text` and `button` are at GC:27-49.
- `text`: Font **Gotham** (regular), default size 17, left-aligned, wrapped. Every string goes through `t()`, which is `L.t` with the German source phrase as key and `language="de"` (GC:16-17).
- `button`: height **38 px**, GothamBold 15, corner 8, text in `colors.text` (light) on a coloured background. It has a press animation: a UIScale set to 0.95 and tweened back to 1 over 0.18 s with Back/Out (GC:43-47). There is no client debounce; the server has a 0.12 s cooldown per action (Server:376-378).
- `fmt` (GC:50-56) prints "%.1f Tsd./Mio./Mrd./Bio./Brd." with a **dot** as decimal separator and no thousands grouping below 1000.

**Theme `colors`** (GC:25-26), all RGB:

| Token | Value |
|---|---|
| bg | 11,16,25 |
| panel | 20,29,43 |
| card | 28,40,57 |
| line | 49,67,87 |
| text | 235,243,250 |
| muted | 156,176,199 |
| green | 50,192,137 |
| blue | 59,134,218 |
| red | 212,65,89 |
| yellow | 235,184,72 |
| purple | 143,82,214 |
| purpleDark | 79,47,124 |

In-world signs use SurfaceGuis with Font 19 (GothamBold), TextScaled, amber 247,176,63, screen teal 121,225,206 and white 224,231,230.

**Top bar `CompactProgress`** (GC:67-71)
- 310×46, centred at y=8, background bg.
- `headline`: "TAG n · hh:mm", size 10, muted.
- `stats`: "Lv. X · Y Cr", GothamBold 13.
- 3 px green XP bar.
- Width is adapted in `resize` (GC:507).

**Tablet (the main menu)** (GC:72-90)
- Design size 1060×700. It becomes 480 wide if the screen is under 700 px wide and 520 tall if the screen is under 500 px tall.
- Centred at (0.5, 0.5 + 35 px) and scaled with a UIScale: `min(1.1, (X-24)/w, (Y-90)/h)`.
- Title: GothamBold 24. Subtitle: 15, muted. Close button "×" at `width-60`.
- `nav`: horizontal ScrollingFrame at (20,80), 48 high.
- `body`: ScrollingFrame at (20,140), size (1,-40,1,-178).
- `foot`: size 12, at `height-30`.

Nav entries:
- `navOrder` is `C.Stations` (home, workshop, parts, upgrades, shop) with "tools" inserted at index 2 (GC:79).
- Buttons are 112 wide; "shop" is 172×44 with TextSize 18 and purpleDark.
- **Every nav button sends `travel`**, which on the server teleports the character to that station (Server:187-191, `moveTo`) and then sends `page`.

Pages:
- The `pages` table is at GC:301: home, workshop (reception: offers and billing), parts, upgrades, shop, tools.
- Cards use absolute positioning through an upvalue `y` (`card` GC:128), a 12 px gap and 16 px inner x offset. Headings are GothamBold 20 (16 if the text is longer than 40 characters); descriptions are 15, muted.
- `rebuild` (GC:302-311) **destroys every child of `body`** and rebuilds the page. It runs on every state `revision` change, on `resize` and on `showPage`.
- Live labels use `bind` getters, refreshed by `refresh` (GC:337) every 0.25 s and on each state push.
- Car previews are ViewportFrames showing clones of `GarageShared.PreviewCars` (GC:146-160).

**The tablet is visible at startup** (`visible=true`, GC:58).

**HUD** (GC:91-103, 340-350)
- Size (0.96,0,0,132) at (0.02,0,1,-138).
- `objective` text, size 16.
- Row at y=47: "Zum Ziel" (blue; sends `target`, which teleports), `workButton` "Arbeiten [E]" (the label and action follow `state.target.Name`: LiftControl, HoodPoint, parts, workshop, or an EquipmentId parent), and "Menü [Tab]".
- Row at y=90: **5 tool slots**, each 92×30, labelled "i · short". The slot is green when `state.tool==id`; the text is muted when the tool is locked.
- `hud.Visible = not visible and not overlay.Visible` (GC:317).

**Toast** (GC:104-111)
- A single panel, 330×60, at (0.5,0,0,62), colour panel, text size 14.
- A new toast replaces the old one (serial counter) and hides after 4 s.

**Modal** (GC:112-125)
- `InteractionOverlay`: full screen, black at 0.25 transparency, ZIndex 10, Active.
- `modal`: 580×440 panel with its own UIScale. `modalTitle` is GothamBold 24.
- It is used for: `diagnose` (OBD answer buttons), `challenge` (QTE gauge), `receipt`, `device` (assign a bay) and `confirm` (cancel a job or buy an extension, both token-based).

**World-space helpers**
- `marker`: a BillboardGui "Ziel", 170×38, AlwaysOnTop, text "▼ …" in green size 12.
- `highlight`: "WorkPartHighlight", fill transparency 0.75, AlwaysOnTop. Both are parented to the ScreenGui and adorned to `state.target` or the matching WorkPoint part (`markTarget`, GC:391-402).

## 2. How state arrives; remotes

**Remotes:** `ReplicatedStorage.GarageShared.Remotes.Command` (client to server, `send(action,args)` GC:18) and `.Event` (server to client, `kind,value`).

**Client to server actions:** hello, travel, target, select, tool, swapTool, accept, work, scan, lift, hood, diagnose, hit, abortInteraction, settle, confirm, commit, partSelect, order, equipment, upgrade, deviceMenu, assignEquipment, buyCredits, save. The `yard` and `door` actions come only from prompts.

**Arguments** are checked in `request` (Server:367-389): at most 10 keys, keys up to 24 characters, scalar values only, strings up to 100 characters. Each player has a budget of 30 actions, refilled at 20/s.

**Server to client kinds** (GC:403-475): state, page, close, toast, purchaseFX, workFX, purchasePrompt, interactionReset, diagnosisDone, scan, diagnose, challenge, receipt, device, confirm. `challengeEnd` is handled on the client but the server never sends it.

**`state` payload** (Server:76-77):
- `data`: `R.Snapshot(d)`, which is a **full clone of the saved profile**.
- revision, selected, tool, objective.
- `target`: an Instance.
- time, dayEpoch.
- `interaction`: `{token,kind,expires}` or nil.
- neededXP, shopReady, saveStatus.
- `visuals`: `{[jobId]={lifted,hood,moving,model}}`.
- `plot`: an Instance.

It is sent after every change **and every 0.5 s by the server loop** (Server:435-446).

What the client does with it (GC:404-410):
- Replaces `state`.
- Dismisses a stale challenge whose token no longer matches.
- Plays `effects.Level` when the level went up.
- Calls `markTarget` and `refresh`.
- Calls `rebuild` only when `revision` changed.

The `hello` message is retried every second until the first state arrives (GC:561-563).

## 3. Input: E/F/H, Tab, 1–5, Space

**InputController (ContextActionService bindings)**
- `UCG_WorkshopMenu`: Tab at priority 10000. It **always sinks Tab** and toggles the menu only if not locked (IC:36-40). There is no gamepad equivalent.
- `UCG_Hotbar`: keys One to Five at priority 3000. They are **always sunk**; `SelectTool(slot)` runs if not locked (IC:41-48). GC:482-484 then sends `tool` if `not overlay.Visible`. The keys are **not** gated by the tablet being open.
- `UCG_QTEStop`: Space, ButtonA and `PlayerActions.CharacterJump` (which covers the mobile jump button) at priority 10000. It passes when unlocked; when locked it sinks and calls `StopQTE` once (IC:27-35).

**E/F/H are native ProximityPrompts, not client key bindings**
- E: `WorkPrompt`, Custom style, gamepad ButtonX, HoldDuration 0.12, range 8, Exclusivity OnePerButton, `VehicleAction="work"` (CarFactory:31-48).
- F: `LiftControl`. Custom style is set in `bindBay` (World:16-21). The key is overwritten to F with gamepad ButtonB in `W.Sync` (World:202); the place file still stores E.
- H: `HoodPrompt`, gamepad ButtonY, Custom style (World:132-135).
- Stations, the roller door, the expansion point and yard prompts use **Default style**: E, gamepad ButtonA, HoldDuration 0.25, range 10 (8 for the door), `RequiresLineOfSight=false`, ClickablePrompt, ActionText "Bereich öffnen".

**On-screen buttons for Custom-style prompts**
- Because Custom-style prompts draw no UI, the client builds `VehicleActions` (GC:356-390): up to three 36 px buttons ("E · <ActionText>"), stacked above the HUD at (0,12,1,-150-count*42).
- They are fed by `PromptShown`/`PromptHidden` and only count prompts with a `VehicleAction` attribute of work, lift or hood; the nearest one within `MaxActivationDistance` wins.
- Tapping a button **sends the remote directly**, bypassing HoldDuration. The server re-checks distance (8 studs).
- `PromptShown` also turns off, on the local client only, any prompt whose ancestor has a different `OwnerUserId` (GC:541-549).

**Desktop world clicks** (GC:525-539)
- Only `MouseButton1` on car parts with a `WorkPoint` attribute. Touch taps on parts are not handled; mobile players use the VehicleActions buttons.
- Ignored when the tablet or overlay is open, or when the input was already processed by the GUI.

**Camera:** no custom camera. It is the default Classic camera with StarterPlayer `CameraMaxZoomDistance=30`, `CameraMinZoomDistance=6` and `CharacterWalkSpeed=19`. The only `Camera` instances are inside ViewportFrames (FOV 40). "Travel" teleports with `PivotTo`, with no camera tween.

**Lighting:** GC:552-556 overwrites `Lighting.ClockTime` every 0.1 s from `R.DayClock(serverNow, state.dayEpoch)`: 20 real minutes per day, starting at 08:00. The server also sets it every 0.5 s. **No area can own ClockTime**, so interiors need their own lights (17 PointLights exist today).

## 4. Mobile support
- `resize` (GC:504-523) runs on `ViewportSize` changes:
  - narrow tablet (480 wide) and short tablet (520 high);
  - UIScale on the tablet and the modal;
  - tool slot width `min(92,(usable-24)/5)`, text size 11 under 500 px wide;
  - adapted width for the top bar, the three HUD buttons and the toast.
- `protectCoreUI` (GC:490-503): turns off the Backpack permanently, hides the PlayerList while the menu or overlay is open, and hides the top bar while chat is open on screens under 900 px.
- The QTE has a large STOPP button; the mobile jump button also stops it.
- Weaknesses:
  - Buttons are 38 px (tool slots 30, vehicle actions 36).
  - On phone landscape (844×354) the tablet scale is about 0.51, so 17 px text renders at about 9 px.
  - `TouchControlsEnabled` is never switched off.
  - The tablet is not `Active`.

## 5. The lock / busy pattern
It has four layers.

1. **Server authority, `p.pending`** (Server:31-56). `beginInteraction` stores `{token,kind,expires,character,tool,point}`. These actions refuse while pending: `work`, `lift`/`hood`, `swapTool`, `deviceMenu`, `buyCredits` and the expansion quote ("Beende zuerst die laufende Interaktion.").
   - `validateInteraction` resets it on timeout, character change, tool change, moving more than 8 studs away, or a job phase/step change.
   - `resetInteraction` sends `interactionReset {token}`.
   - **`travel`, `target`, station prompts (`kind=="station"`), tool switching and respawn all call `resetInteraction`**, so opening another area cancels the interaction on the server.
   - `p.profile.transacting` (while a purchase is being saved) blocks every action except hello and abortInteraction.
2. **Mirror in the payload:** `state.interaction`. GC:406 dismisses the client challenge if its token disappears.
3. **Client modal gate, `overlay.Visible`.** While the overlay is visible:
   - Tab/ToggleMenu is ignored (GC:478);
   - hotbar keys are ignored (GC:483), and HUD tool buttons (GC:100) and vehicle buttons (GC:363) are blocked;
   - world clicks are ignored (GC:526);
   - the marker and highlight are hidden (GC:393, 401);
   - the HUD and VehicleActions are hidden (GC:317, 389);
   - the PlayerList is hidden (GC:492).
   
   `dismiss()` (GC:116) clears challenge and diagnosis, hides the overlay, calls `effects.StopWork()` and `inputControl.Unlock()`.
   
   **Pitfall:** `interactionReset` dismisses the overlay whenever `challenge` is nil (GC:425). Any modal that shares the overlay can be closed by an unrelated reset.
4. **Input lock, `inputControl.Lock()`**, only for `challenge` (GC:435). It turns off Jumping and AutoJump and routes Space to `submitChallenge`, which is guarded against double submission by `challenge.submitted`. `Unlock` sets a release 0.15 s later, and the lock is only restored after Space is released (IC:23-26, 52-57).

In addition, `visible` (tablet open) blocks world clicks and vehicle buttons and hides the HUD. The events `diagnose` and `challenge` force the tablet closed (GC:429, 435).

## 6. Effects and animations
- **FX** creates its own ScreenGui "GarageCelebrations" with DisplayOrder 45 (FX:6).
- `fx.Purchase({title,detail})`:
  - 300×84 dark-green panel at (0.5,0.79), UIStroke green 55,218,155;
  - UIScale 0.75 to 1 over 0.3 s (Back), a "✓", held 1.8 s, then slides and fades over 0.22 s.
  - Triggered by the server's `purchaseFX`, which is also used for yard rewards.
- `fx.Level(level)`:
  - 340×124 gold panel at (0.5,0.26), UIScale 0.45 to 1 (Back 0.5 s);
  - 22 confetti Frames tweened 1.3–1.75 s with rotation and fade;
  - closes at 3 s.
- `fx.Work` and `StopWork`: a RenderStepped loop that swings the **right shoulder Motor6D C0** and the tool weld `ToolGrip` C0 with sine waves that depend on the tool. It writes the `Readout` SurfaceGui text ("OBD SCAN nn%", "12.40 V").
  - It stops when the time is up, the tool changes, or the player is more than 18 studs from the work point.
  - This is client-only: other players do not see the swing.
- **Server-side effects (visible to everyone):**
  - `CarFactory.WorkEffect`: neon parts with tweens (oil stream, rotating wheel, turning socket, pulsing test orb);
  - lift: a 2 s Sine tween on a NumberValue that drives PivotTo;
  - roller door: 1.8 s Sine tween;
  - hood: snaps to 65° with no tween;
  - equipment: neon LevelIndicator.
- The QTE cursor is driven every RenderStepped by `R.GaugePosition`.
- Opening and closing the tablet and HUD is instant, with no tween.
- **There are no sounds or particles.**

## 7. Collisions with the current 3.0 client (`UI.lua`, `Main.client.lua`)
- **Same ScreenGui name** "UltimateCarGame" (3.0 uses DisplayOrder 10). The 2.4.0 tablet and HUD (DisplayOrder 20) would draw on top of the 3.0 panel.
- **Overlapping positions:**
  - The 3.0 top HUD and goal bar (y=6, up to 480 wide) sit over CompactProgress and the 2.4.0 toast.
  - The 3.0 "Minispiele" button (0.5,1,-12, 170×52) and bottom toasts (1,-76) sit over the 2.4.0 HUD.
- **Duplicated concepts:**
  - The 3.0 "workshop" tab is a second, abstract workshop.
  - The 3.0 "shop" and "overview" tabs duplicate the 2.4.0 Credits-Shop and Übersicht.
  - The 3.0 HUD repeats credits, level and XP.
  - The 3.0 `levelup` toast would duplicate `fx.Level`.
- **No shared lock:** a 3.0 `open` notice can open the panel during a QTE, and the 2.4.0 HUD and world clicks stay active under the 3.0 panel.
- **Keys:** keys 1–4 in a minigame would switch tools, because UCG_Hotbar always sinks them. Space jumps unless something binds it above priority 10000 with Pass.
- **Formatting:** 3.0 `Locale.Number` writes "123,5 Tsd." while 2.4.0 `fmt` writes "123.5 Tsd.".
- **Button text colour:** 3.0 uses dark text 7,17,27 on coloured buttons; 2.4.0 uses light text.

## 8. Recommended integration: one menu, one lock

**Menu entry.** Add a **"Minispiele" nav entry inside the existing tablet**, inserted before "shop" (`table.insert(navOrder,#navOrder,"minigames")` at GC:79). It must be **local-only**: call `showPage("minigames")` instead of `send("travel")`.
- If "minigames" were added to `C.StationNames` without a `Stations.minigames` part, the server's `travel` would index a missing child at Server:191 and error.
- Width 150; nav total ≈ 938 px, which is under the 1020 px body.
- Highlight it green when `page` is the hub or any minigame key.

**Persistent host.** Add a sibling of `body` inside `tablet`, for example `MinigameHost`, at the same rectangle ((20,140), (1,-40,1,-178)). It holds a small sub-tab row and a ScrollingFrame with `AutomaticCanvasSize=Y`.
- In `rebuild` (GC:302-311), when `isMini(page)`: set `body.Visible=false` and `host.Visible=true`, skip destroying and rebuilding, and update title and nav colours. Otherwise do the reverse.
- The 3.0 `Build(page,ctx)` functions run **once** into persistent page Frames. `Render(snapshot)` runs on the 3.0 sync; `Step()` runs while `visible and isMini(page)`. This replaces `UI.IsOpen` and `UI.CurrentTab`.

**Tabs to keep:**
- Keep: Minispiele (hub, formerly 3.0 overview), Schrottpresse (+Bestenliste), Tuning, Schrottplatz, Quiz, Parkplatz, Ziele.
- Drop the 3.0 WorkshopUI.
- Move the Game-Pass cards into the 2.4.0 `shopPage` (GC:264) as extra purple cards.
- Use keys `minigames`, `press`, `tuning`, `scrapyard`, `quiz`, `parking`, `goals`, `leaderboard`. None collide with home/workshop/parts/upgrades/shop/tools.

**Physical places.** Put `Stations/<key>` parts with Default-style prompts inside the plot template. The existing `W.Create` wiring (World:60-63), the `station` callback, `resetInteraction` and `emit("page",key)` then open `showPage(key)` automatically, as long as `pages[key]` exists; unknown keys are already ignored safely (GC:313). The lock then works for free.
- "Hingehen" buttons can use `travel` only when `C.StationNames[key]` and the station part both exist.
- `moveTo` places the player at part.X, plotY+3.5, part.Z+6, so that spot must be open floor.
- Keep these prompts at least 12 studs from car WorkPrompts (both use E).
- If 3.0 keeps its own `open` notice, gate it on the client: `if overlay.Visible or inputControl.locked then return end`.

**Drop from 3.0 `UI.Build`:** its ScreenGui, top HUD, MenuButton, toasts and shade.
- `UI.Toast` should call the 2.4.0 `toast`.
- `UI.Confirm` should use `modalTitle` with "Zurück" (card) and "Bestätigen" (green or red), or its own dialog above the overlay.
- Reward and level feedback should go through `ctx.Effects` (Purchase/Level).
- Scrap can go into the hub header or the tablet `foot`.

**Keys.** Gate `SelectTool` while a minigame page is open. For minigame shortcuts, bind a CAS action at priority between 3000 and 10000 that sinks only while the page is open.

## 9. UI conventions the 3.0 modules should adopt
- **Colours:** make `UI.Theme` alias the 2.4.0 palette:

  | 3.0 token | 2.4.0 colour |
  |---|---|
  | bg | bg |
  | panel | panel |
  | panel2 | card |
  | text | text |
  | muted | muted |
  | accent | green |
  | accent2 | blue |
  | warn | yellow |
  | danger | red |
  | line | line |
  | purple | purple (purpleDark for hero cards) |

  Button text should be light (`colors.text`). Disabled buttons: card background with muted text. Avoid UIStroke on cards.
- **Fonts:** body Gotham 16–17; card titles GothamBold 20; descriptions Gotham 15 muted; status 12–14; buttons GothamBold 15. Keep GothamBlack only for big numbers and pop-ups.
- **Geometry:** card corner 10, button corner 8, 16 px horizontal padding, 12 px gap between cards. Keep 44 px buttons (the 3.0 tests require them), add the UIScale press tween (0.95 to 1, Back 0.18 s), and keep the 0.3 s debounce.
- **Text:** German, "·" as separator, no emojis (2.4.0 uses only ✓ ▼ ×). Route strings through `L.t`. Use one number formatter for both.
- **Sizing:** pages must size relative to the host (Scale X), since the tablet applies a UIScale. PressUI's AbsolutePosition maths still works under UIScale.
- **Sounds:** optional. The only one is the built-in `rbxasset://sounds/clickfast.wav`; 2.4.0 has none.

### Integration points
- GarageClient.LocalScript.lua:25-26 `colors`: extract into a shared Theme table/module and make 3.0 `UI.Theme` (src/client/UI.lua:9-21) alias it (panel2->card, accent->green, accent2->blue, warn->yellow, danger->red).
- GarageClient.LocalScript.lua:79 `navOrder`: insert a local-only 'minigames' key before 'shop' (table.insert(navOrder,#navOrder,'minigames')).
- GarageClient.LocalScript.lua:81-87 nav button loop: for 'minigames' call showPage('minigames') instead of send('travel',{key=key}); width ~150; highlight via isMini(page).
- GarageClient.LocalScript.lua:89 `body`: add sibling `MinigameHost` in `tablet` at UDim2.fromOffset(20,140), size UDim2.new(1,-40,1,-178), Visible=false; it holds the 3.0 sub-tab row plus a ScrollingFrame (AutomaticCanvasSize Y) with persistent page Frames.
- GarageClient.LocalScript.lua:301 `pages` table: add entries minigames/press/tuning/scrapyard/quiz/parking/goals/leaderboard (no-op builders), so server 'page' events for new Stations open them (showPage guard at :313).
- GarageClient.LocalScript.lua:302-311 `rebuild`: if isMini(page), skip the body:GetChildren() destroy loop and pages[page](), toggle body.Visible/MinigameHost.Visible, set the title from a client-local name table, and colour the nav 'minigames' button green.
- GarageClient.LocalScript.lua:316-338 `refresh` (or the 0.25 s loop at :559): call the minigame module Render/Step when `visible and isMini(page)`; replaces 3.0 Main.client.lua Heartbeat checks of UI.IsOpen/UI.CurrentTab.
- GarageClient.LocalScript.lua:107-111 `toast`: expose it to 3.0 via ctx so UI.Toast (src/client/UI.lua:402) delegates; remove 3.0 bottom toast host.
- GarageClient.LocalScript.lua:123-125 `modalTitle`/`modal`/`dismiss` (:116): expose for 3.0 UI.Confirm (rebirth), or keep 3.0 confirm but in the same ScreenGui above overlay ZIndex 10.
- GarageClient.LocalScript.lua:403-475 Event handler: optional new kinds (e.g. 'minigame') or, if 3.0 keeps Remotes.Notice 'open', route to showPage(key) only when not overlay.Visible and not inputControl.locked.
- GarageClient.LocalScript.lua:407 level-up FX: 2.4.0 already plays effects.Level on data.level increase; drop 3.0 'levelup' toast in Main.client.lua:84-85 to avoid double feedback.
- GarageClient.LocalScript.lua:476-485 InputController callbacks: gate SelectTool(slot) when a minigame page is active (keys 1-5 are always sunk by UCG_Hotbar, InputController:41-48, priority 3000).
- InputController.ModuleScript.lua:36-40 UCG_WorkshopMenu (Tab, priority 10000): Tab toggles the unified tablet including Minispiele; for minigame shortcuts bind new CAS actions at priority between 3000 and 10000 that sink only while a minigame page is open.
- GarageClient.LocalScript.lua:96 HUD 'Menü [Tab]' button and resize :517-519: an optional 'Minispiele' HUD button fits right of `menu` only when usable width >= ~700 px (landscape); not in portrait (390 px has no room).
- GarageClient.LocalScript.lua:504-523 `resize`: the MinigameHost inherits tablet UIScale; consider a compact header for screen.Y<500 (scale is ~0.51 at 844x354) similar to 3.0 UI.ApplyLayout compact mode.
- ClientEffects.ModuleScript.lua:15-38 fx.Purchase / fx.Level: pass `effects` into the 3.0 ctx so quiz/scrapyard/rebirth/milestone rewards use the same celebration panels (GarageCelebrations, DisplayOrder 45).
- World.ModuleScript.lua:60-63 (W.Create station prompt wiring) + GarageServer.Script.lua:403 (kind=='station' -> resetInteraction + emit 'page'): add Workspace.Werkstatt.Stations/<press|tuning|scrapyard|quiz|parking|goals|leaderboard> parts with Default-style prompts (E/ButtonA, HoldDuration 0.25, range 10, ActionText 'Bereich öffnen') to open minigame pages physically with the lock respected.
- GarageServer.Script.lua:187-191 `travel`: only send travel for keys that exist both in C.StationNames and as Stations parts; moveTo puts the player at part.X, plotY+3.5, part.Z+6.
- GarageClient.LocalScript.lua:264-300 `shopPage`: append 3.0 Game Pass cards (ShopUI.lua pass_prompt) here instead of a separate 3.0 'shop' tab.
- src/client/UI.lua:200-363 `UI.Build`: replace with a BuildInto(host) that creates only the sub-tab bar + content; delete the separate ScreenGui 'UltimateCarGame' (name collision), top HUD, 'Minispiele' MenuButton at (0.5,1,-12), confirm shade; update tests/test_client.lua (expects PlayerGui.UltimateCarGame, DisplayOrder 10, UI.Top/MenuButton/Hud).

### Risks
- The 3.0 ScreenGui has the same name 'UltimateCarGame' as the 2.4.0 GUI (GarageClient:66). FindFirstChild/WaitForChild and the 3.0 tests become ambiguous, and the 2.4.0 GUI (DisplayOrder 20) draws over the 3.0 panel (DisplayOrder 10).
- Position overlap: the 3.0 top HUD/goal bar (y=6, up to 480 px) covers CompactProgress (y=8) and the 2.4.0 toast (y=62). The 3.0 'Minispiele' button (0.5,1,-12) and bottom toasts (1,-76) cover the 2.4.0 HUD (bottom 138 px) and the VehicleActions E/F/H buttons, so they could block the workshop controls on mobile.
- rebuild() destroys every child of `body` on each revision change, resize and showPage (GarageClient:305). Any 3.0 page parented to `body` would be wiped and its pooled rows and references would break. The host must be a separate container.
- If 'minigames' (or any new key) is added to C.StationNames without a matching Workspace.Werkstatt.Stations part, a client `travel` makes the server index a missing child (GarageServer:191 `p.world.model.Stations[a.key]`) and the request errors. The 3.0 keys 'workshop'/'shop'/'overview' collide semantically with 2.4.0 station 'workshop' (reception), 'shop' (Credits-Shop) and 'home' (Übersicht).
- Lock bypass: a 3.0 'open' notice or a local minigame panel can open during a QTE or diagnosis. The 2.4.0 overlay/inputControl lock and the server `p.pending` lock know nothing about 3.0 actions. The HUD and world clicks stay active under a separate 3.0 panel because GarageClient only checks its local `visible`/`overlay.Visible`.
- Keys 1–5 are always sunk by UCG_Hotbar (priority 3000) and call SelectTool even while the tablet is open. Quiz or minigame number shortcuts would change the workshop tool, and on the server that calls resetInteraction and cancels a pending scan or QTE. Space triggers a jump unless a higher-priority binding sinks it.
- A minigame confirm dialog that reuses the 2.4.0 modal can be closed by any unrelated `interactionReset` (GarageClient:425 dismisses whenever challenge is nil), or by respawn (:540). The callback is then silently dropped, which is acceptable only if it is idempotent.
- Profile payload bloat: R.Snapshot(d) clones the entire profile into every 2.4.0 `state` push, including the 0.5 s server loop. Storing 3.0 data under d.games (100 press upgrade levels, goals, leaderboard caches) would ship it twice a second unless Snapshot excludes it.
- Revision churn: if 3.0 actions (press_click every 0.5 s) bump the 2.4.0 p.revision via changed(p), the tablet fully rebuilds each time (scroll jumps, work lost in partsPage/toolsPage). Money changes from minigames should use push(p) without a revision bump.
- Profile writes during a purchase: 2.4.0 blocks all actions while profile.transacting (GarageServer:369). 3.0 handlers that write the shared profile during a receipt save could race the purchase save and lose credits. They must honour transacting/receiptPending.
- Double feedback and inconsistent numbers: the 3.0 HUD duplicates credits/level/XP, the 3.0 levelup toast duplicates fx.Level, and 3.0 Locale.Number ('123,5 Tsd.') differs from 2.4.0 fmt ('123.5 Tsd.'), so the same balance can look different in two places.
- Mobile legibility: hosting 3.0 pages inside the tablet applies its UIScale (about 0.51 at 844x354 landscape). The 44 px touch targets become about 22 px on screen. A compact-header fix in resize() is needed, and 3.0 tests that assert all buttons are at least 44 px would also fail if they scan the whole merged GUI (2.4.0 buttons are 38 px, tool slots 30 px).
- Prompt conflicts: new minigame prompts on E near the car WorkPrompts (E, OnePerButton) or the station prompts (E, default OneGlobally) may both show and both trigger. Custom-style minigame prompts get no on-screen button because refreshVehicleActions only handles VehicleAction work/lift/hood. Prompts inside a plot inherit OwnerUserId and are turned off on other players' clients (GarageClient:541-549).
- Lighting.ClockTime is overwritten every 0.1 s by the client (GarageClient:555) and every 0.5 s by the server. Any minigame area or 3.0 code that tries to set time of day or its own lighting mood will flicker. Interiors must use local lights.
- Camera: 2.4.0 relies on the default camera (zoom 6..30). A minigame that switches CameraType (for example a top-down Parkplatz view) must restore Custom/Humanoid subject on close, on CharacterAdded and when a 2.4.0 challenge or diagnosis opens, or the workshop becomes unplayable.
- Receipts: 3.0 server Purchases uses PromptGamePassPurchase, and 2.4.0 Purchases.Init owns ProcessReceipt. Only one ProcessReceipt callback can exist, so merging the purchase code carelessly can break credit-pack delivery (visible on the client as shopReady/saveStatus stuck).