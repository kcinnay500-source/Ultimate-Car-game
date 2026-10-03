# 2.4.0 world geometry: what is in /tmp/claude-0/old/old.rbxlx

Everything below comes from parsing the XML with python. The helper scripts are in /tmp/claude-0/scratch_geo/: parse.py, common.py, map.py, map2.py, free.py and car.py; ws_parts.txt holds the full part dump. Coordinates are plot-local studs. +Z is the road side ("front") and -Z is the back.

## 0. The most important fact: the whole world is a per-player plot template

- `Workspace.Werkstatt` is the only model in Workspace. Its PrimaryPart `Root` is at (0,0,0).
- World.lua lines 7-9 run when the module loads. They clone the entire Werkstatt into `ServerStorage.PlotTemplate` and destroy the original.
- `W.Create` (line 56) then gives every player a private copy: `model:PivotTo(CFrame.new(((slot-1)%4)*330,0,math.floor((slot-1)/4)*260))`.
  - `C.MaxPlots=8`, so there are two rows of four.
  - Plot pivots: X = 0, 330, 660, 990 at Z = 0 (slots 1-4), and the same X values at Z = 260 (slots 5-8).
  - Total occupancy is about X -141..1131 and Z -88..392.
  - Gaps between plots: 50 studs in X (140..190) and 40 studs in Z (132..172).
- Each plot is fenced in by four invisible collidable `Architecture/Boundary` walls (Transparency 1, 52 tall, Y -1..51):
  - Z = +132: 282×52×1 at (0,25,132)
  - Z = -82: 282×52×1 at (0,25,-82)
  - X = ±140: 1×52×215 at (±140,25,25)
- Ground:
  - The only ground is `Architecture/Yard`: a 280×1×220 Concrete slab at (0,-1.5,22), covering X -140..140, Z -88..132, top at Y -1.
  - The strip Z -88..-82 lies outside the boundary and cannot be reached.
  - There is no Terrain object and no baseplate between plots, only void.
- Workspace settings: FallenPartsDestroyHeight = -80, Gravity 196.2, StreamingEnabled false.
- StarterPlayer: CharacterWalkSpeed 19, camera zoom 6..30.
- All 4054 parts in the file are Anchored, with Smooth top and bottom surfaces.
- What this means for the merge:
  - Anything placed inside Werkstatt gets copied into every plot (up to 8 times).
  - Anything placed directly in Workspace at these coordinates lands inside slot 1's copy, because slot 1's pivot is the origin.
- Height levels:
  - Outdoor ground: Y = -1
  - Building floors: top at Y 0 (1-stud slab from -1 to 0)
  - EntranceApron: top at Y -0.5
  - Road: top at Y -0.96

## 1. Top-down layout of one plot

One character is 3 studs in X; one row is 5 studs in Z, and the row label is the band's minimum Z. The map shows the hall at its maximum of 4 bays. The rows Z 110..130 are empty and omitted.

```
  X:        -120                -60                 0                   60                  120
  -85XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
  -80X            NNNNNNNNNNNNN                                         NNNNNNNNNNNNN             X
  -70X;;;;;;;;!   NNNNNNNNNNNNN                                         NNNNNNNNNNNNN    !;;;;;;;;X
  -60X|;;;;;;;!   NNNNNNNNNNNNN                                         NNNNNNNNNNNNN    !;;;;;;;|X
  -55X|;;;;;;;!   NNNNNNNNNNNNN                                         NNNNNNNNNNNNN    !;;;;;;;|X
  -50X|;**T**;!                                                                          !;**T**;|X
  -40X|;**TTT;!                                                                          !;**TTT;|X
  -35X|;**TTT;!            #####################################                         !;**TTT;|X
  -30X|;;;;;;;!            #eeeeOO..WWW..++WWWW++++WWW++++WWW++#                         !;;;;;;;|X
  -25X|;;;;;;;!            #eeeeOOL.....LL++++++LL+++++LL+++++L#                         !;;;;;;;|X
  -15X|;;;;;;;!            #eeee..L.L.L.LL+LLLL+LL+L+L+LL+L+L+L#                         !;;;;;;;|X
  -10X|;;;;;;;!            #eeee..LLL.LLLLLLLLLLLLLL+LLLLLL+LLL#                         !;;;;;;;|X
   -5X|;;;;;;;!            #######LLL.LLLLLLLLLLLLLL+LLLLLL+LLL#                         !;;;;;;;|X
    0X|;**;;;;!            ########.L.LLLL+LLLLLLL+L+LLLL+L+LLL#                         !;**;;;;|X
    5X|;**T**;!            #......L....LLL++++LLLL+++LLLL++++LL#                         !;**T**;|X
   10X|;**TTT;!            ###.####.LLLLLL++LLLLLL+LLLLLL+LLLLL#                         !;**TTT;|X
   15X|;**TTT;!            ###.####....EE++++++++++++++++++++++#                         !;**TTT;|X
   20X|;;;;;;;!            #$$RRR......EE++++++++++++++++++++++#                         !;;;;;;;|X
   25X|;;;;;;;!            #RSSSR##......++++++++++++++++++++++#                         !;;;;;;;|X
   30X|;;;;;;;!            #=SSS=#D......D++++++#++++++##++++++#,,,,,,,,,,,,,            !;;;;;;;|X
   35X|;;;;;;;!  oo        ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,        oo  !;;;;;;;|X
   40X|;;;;;;;!       bbbb ,__,i,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,i,__, bbbb       !;;;;;;;|X
   45X|;;;;;;;!       bbbb     i                                        i     bbbb       !;;;;;;;|X
   50X|;;;;;;;!                i    //   //   //   //   //   //   //    i                !;;;;;;;|X
   55X|;**;**;!      Y Y            //   //   //   //   //   //   //            YYY      !;**;**;|X
   60X|;**T**;!      YYY          CCC/   //   //   //   //   //   CCCC          YYY      !;**T**;|X
   70X|;**TTT;!                   CCCC   //   //   //   //   //   CCCCC                  !;**TTT;|X
   80X|;;;;;;;!  oo~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~oo  !;;;;;;;|X
   90X;;;;;;;;!  ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~  !;;;;;;;;X
   95X;;;;;;;;!  ~~~~----~~~----~~~----~~----~~~----~~~----~~----~~~----~~~----~~~~~~~~  !;;;;;;;;X
  105X           ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~           X
```

**Legend**

| Char | Meaning |
|---|---|
| X | invisible Boundary |
| N | NeighbourBuilding |
| ; | Grass garden bed |
| ! | curb |
| \| | fence |
| T | tree |
| * | bush |
| # | ground-level wall |
| . | current hall floor |
| + | Stage_2..4 floor (appears only when purchased) |
| L | lifts and bay lines |
| W | tool chest / cabinet |
| O | tire stacks |
| e | equipment storage spots |
| $ | Credits shop |
| R | reception desk |
| S | spawn |
| E | expansion ring |
| D | roller door guides |
| = | front glazing |
| , | EntranceApron |
| _ | drain grate |
| i | bollard |
| b | bench |
| o | street lamp |
| / | parking lines |
| C | show car |
| Y | yard activity |
| ~ | road |
| - | road centre dashes |

**Exact extents** (AABB X / Z; Y as noted):

- **Hall** (current): X -74..-32, Z -33.4..33.4, roof Y 20..21. At 4 bays the EndWall moves to X 34, so the hall grows to X -74..34.4.
- **Reception / Empfang**: X -74..-54, Z 15..33. **Office / Büro**: X -74..-54, Z 0..15. **Storage / parts area**: X -74..-54, Z -33..0.
- **RollerDoor** opening: X -53..-33 at Z 31.6.
- **EntranceApron**: Concrete (114,121,124) 149×0.5×12, X -74.5..74.5, Z 33..45.
- **Parking**:
  - 7 ParkingLines (0.17×24, colour (224,231,230)) at X = -45, -30, …, 45, Z 52..76. That makes 6 bays, each 15 wide and 24 deep.
  - Showcar_compact: Root at (-49,-1,70). Showcar_sport: Root at (49,-1,70). Both are rotated 180° so their noses face the road (+Z).
- **Road**: Concrete (46,52,59) 210×0.06×26, X -105..105, Z 83..109.
  - 9 amber RoadMark dashes (9×0.25) at Z 97, X -86..74, 20 studs apart.
  - The road is a dead end at both ends.
- **Sidewalks**: there are none; the plain yard concrete (83,88,91) serves as the sidewalk.
- **Bollards**: yellow Metal 0.42×3.2 with a black band, at (±61, 43) and (±61, 50).
- **Benches**: at (±84, 45). **DrainGrates**: at (±69, 42).
- **Street lamps**: 12.5-stud post plus arm plus Neon head (255,224,169) with a PointLight. Posts at (±102, 38) and (±102, 84); heads at X ±100.2.
- **Garden beds**: Grass (73,91,64) 23×164, X ±(112.5..135.5), Z -68..96. Curbs at X ±111.8. Grass tufts every 13 studs.
- **Fences**: steel posts every 18 studs at X ±137 (Z -62..82), with 2 rails at Y 0.7 and 2.5.
- **Trees**: 6 trees at X ±124, Z -39 (Birch), Z 13 (WorkshopPine), Z 67 (Birch). Each has 3 bushes of 7 LeafSpray wedges around it.
- **"Office buildings"**: 2 NeighbourBuilding blocks, Concrete (82,97,109) 38×28×26.
  - West block X -101..-63; east block X 60..98; both Z -77..-51.
  - 6 windows each (7×5 Glass) on the +Z face at Z -50.8, at Y 8 and 18.
- **YardActivities**:
  - `pressure`: teal Metal column 2.3×5×2.3 at (88,1.5,62), part of the "REIFENSERVICE" air station.
    - The sign is at (88,4.5,59.16) on posts at X 85 and 91.
    - AirStationDisplay "2.4 BAR" is at Z 63.19; PracticeWheel/Rim at (91.5,0.3,61); 3 AirHose cylinders.
  - `recycle`: Metal (66,103,116) box 8×3×4 at (-88,0.5,63), the recycling corner.
    - The "RECYCLING" sign is at (-88,4.5,60.16) on posts at X -91 and -85.
    - The "ALTTEILE / METALL" label is at Z 65.06.
    - 3 SortingBinRims and 6 UsedFilter cylinders sit on top.
  - Both prompts are 10-stud "E" prompts with 0.25 s hold.
  - Cosmetic issue: all sign text sits on the +Z face, so both yard signs show their blank backs to players coming from the hall.

## 2. Interior: hall, reception, office

One character is 1 stud in X; one row is 2 studs in Z. Only parts that reach the floor are drawn.

```
  X:                 -60                 -40
  -33 ############################################
  -29 ##..........................WWWWWWWW......##   ToolChest (-43,-28)
  -27 ##.eeee....eeee.OOOO........WWWWWWWW......##   TireStacks (-57,-25)/(-57,-18)
  -23 ##.eeee....eeee.......L..................L##   BayLines X -52.1 / -33.9
  -13 ##.eeee....eeee.......L.....LL....LL.....L##   MovingLift pads
   -7 ##.eeee....eeee.......LLLLL.LL....LL.LLLLL##   LiftPosts (-50,-4),(-36,-4)
   -1 ######################L..LLLLL....LLLLL..L##   Office BackWall Z=0
    1 ##PPPPPPPP..UUUUUUUU##L.....LL....LL.....L##   PartsArea / UpgradeBench desks
    9 ##....................L......LLLLLL.L..L.L##   (hall opening X=-54, Z 4..12)
   13 ########......########L..................L##   FoyerPartition Z=15, door X -67.2..-60.8
   17 ##.$$$$$$...........##..............EEEEEE##   CreditShop (-69,19); Expansion ring (-36,21)
   21 ##...RRRRRRRRRRRR...................EEEEEE##   Reception desk (-64,25); opening Z 18..28
   29 ##****..SSSSSS......#DD...................##   plant (-71.5,30); Spawn Start (-64,31)
   31 ##======SSSSSS======#DD...................D#   glazing | entry | glazing | RollerDoor
```

**Heights**

- Hall floor top Y 0. ClosedRoof underside Y 20 (1 thick), so clear height is 20.
  - RoofTrusses at Y 19.2..19.8, at Z -21, -4, 15 and 31.
  - Neon light bars at Y 18.8..19.0.
- Reception and office have no ceiling of their own. Their Concrete partitions are only 8 tall, so both rooms are open up to the hall roof at 20.

**Walls**

- Exterior walls and pillars are 0.8 thick. Facade header and roof are 1.0; floor slab 1.0; interior partitions 0.4; glass 0.35 (side bands) and 0.25 (front).
- Side walls (X -74, and the movable EndWall at X -32):
  - SideWall Y 0..9
  - Glass window band Y 9..12.2 (Z -31..31, T 0.3)
  - UpperBeam Y 12.2..20
  - WallFrame pilasters 0.9×0.4 (66,80,94), every 16 studs at Z -32, -16, 0, 16, 32
- BackWall Z -33 is solid, 20 tall.
- Front (Z 32):
  - FacadeHeader Y 12..20.
  - FacadeAccent Neon strip (247,176,63): 42×0.16×0.1 at Y 11.95, Z 32.56.
  - ShopName sign 39×3.4 at Y 12.4..15.8 with 4 corner bolts.
  - FrontPillar at X -32 with a SafetyStripe.

**Door openings**

| Opening | Where | Size |
|---|---|---|
| Pedestrian entry | Z 32, X -65.4..-61.6 | 3.8 wide × 9.6 high (EntryLintel Y 9.6..12, label "EMPFANG") |
| Roller door | X -53..-33 | 20 wide × about 11.5 high |
| Foyer → office | Z 15, X -67.2..-60.8 | 6.4 × 6.6 |
| Office → hall | X -54, Z 4..12 | 8 × 6.6 |
| Foyer → hall | X -54, Z 18..28 | 10 × 6.6 |
| Storage area | X -74..-54, Z < 0 | fully open to the bays |

- Pedestrian entry: FrontGlazing on either side, X -74..-65.6 and -61.4..-54, Y 0..11.6, T 0.32, mullion at Y 6.2.
- Roller door details:
  - Guides at X -53.15 and -32.85; Housing at Y 12..12.9; amber Control at (-52.9,3.3,30.95).
  - The Panel starts open (0.3 tall at Y 11.7). `W.RollDoor` tweens it to 11.8 tall.
  - `doorwayOccupied` checks |dX|<11 and |dZ|<2 around ClosedOrigin (-43,5.95,31.6).

**Glass parts in Workspace (44)**

- 2 hall window bands
- 2 front glazing panes
- 12 neighbour windows
- 28 show-car glass parts

All architectural glass is (116,159,178).

**Lights: 17 PointLights**

- Hall (3): in the WorkshopLight neon bars (232,246,249), 10×0.2×0.5, at (-43,18.9,-21/-4/15). Range 25, Brightness 0.85, Color (224,238,255).
- Office (1): Office/Light neon (224,231,230) at (-64,7.7,0.32). Range 18, Brightness 0.7.
- Street lamps (4): at (±100.2,11.65,38/84). Range 20, Brightness 0.65.
- Extensions (9): 3 per Stage, at X -21, 1 and 23, same Z values as the hall lights.

Other neon: ExpansionPoint Ring (amber; turns green (62,217,166) at runtime once affordable), CreditShop accent (135,75,196), and car head and tail lamps.

## 3. Style guide

Parts by material in Workspace:

| Material | Parts |
|---|---|
| SmoothPlastic | 508 |
| Metal | 305 |
| Plastic | 216 (tires and trim) |
| Glass | 44 |
| Wood | 42 |
| Concrete | 20 |
| Neon | 19 |
| Grass | 2 |
| DiamondPlate | 2 |

**Palette (RGB)**

- **Structure**
  - Walls, facade, sign panels and desks: dark slate (31,43,55) Metal or SmoothPlastic.
  - Roof: graphite (42,48,55).
  - Frames: (66,80,94). Trusses: (79,91,103).
  - Brushed steel (156,170,177) Metal is the most common colour (149 parts): rails, bolts, posts, handles, fences.
  - Near-black (22,26,31) for bases, tires, bezels and trim.
- **Signature accent**: amber (247,176,63). Used for the neon strip, sign text, safety stripes, lift arms, bollards, wheel hubs and the lift control.
- **Second accent**: teal (47,169,163). Used for lift posts, equipment bodies, default car paint and the spawn.
- **Tool storage**: petrol (43,102,121) / (50,117,135) on the tool chest and cabinets.
- **Screens**: (27,72,82) with text (121,225,206).
- **Floors**
  - Hall: Concrete (96,105,111).
  - Yard: (83,88,91). Apron: (114,121,124). Foyer: (126,130,128).
  - Partitions: Concrete (130,139,144).
  - Office floor: Wood (152,145,127). Counter: Wood (181,153,112).
- **Foliage**: 4 shades from (57,91,58) to (69,111,70). Bushes (61,100,65) to (79,124,77). Grass tufts (109,132,78).
- **Credits shop purple**: (135,75,196), (70,45,103), display (45,28,72), text (233,212,255).

**Signage recipe**

- A dark slate SmoothPlastic plate 0.1-0.3 thick, with steel bolt cubes (0.16-0.17) in the corners.
- SurfaceGui settings: Face = Back (+Z), SizingMode 0 with a fixed CanvasSize, LightInfluence 0.
- TextLabel settings: 0.96×0.88 at (0.02,0.06), transparent background, TextScaled, Font token 19 (GothamBold).
- Text colour is amber, or (224,231,230) for secondary text.

**Lighting service**

- Brightness 2.6, GlobalShadows on.
- Ambient (124,135,150), OutdoorAmbient (145,156,171).
- EnvironmentDiffuse 0.55, EnvironmentSpecular 0.65.
- ClockTime is 14.3 in the file, but GarageServer sets it to `C.DayStartHour` (8) on line 15 and then cycles it (one day = 20 minutes).
- Atmosphere: Density 0.23, Offset 0.15, Haze 1.1, Color (203,223,237).
- ColorCorrection: Saturation -0.08, Contrast 0.06, Brightness 0.02.
- Bloom: Intensity 0.13, Size 18, Threshold 1.7.
- There is no Sky object.

## 4. Free space for new zones

Method (free.py): I built a 1-stud occupancy grid and reserved:
- the 4-bay hall, X -74.5..34.5, Z -33.5..33.5
- the apron
- the parking lot, X -54..54, Z 52..78
- the road

plus a 2-stud buffer. The largest free rectangles inside the current boundaries:

| Area | Rectangle | Size |
|---|---|---|
| **East yard** | X 37..109, Z -48..31 | 72×79 |
| **Back lot** (between the NeighbourBuildings) | X -60..58, Z -81..-36 | about 118×45 |
| **South strip** (behind the road) | X -139..139, Z 112..131 | 278×19 |
| **West side** | X -109..-77, Z -48..35 | 32×83 |
| Corners | X 57..109, Z 66..81 (52×15); X -81..-56, Z 53..81 (25×28); X -109..-94, Z 42..81 (15×39) | small |

Suggested zones (plot-local, ground at Y -1, floors at Y 0):

1. **Idle Tuning Garage (high ceiling)** in the east yard, for example a building at X 44..104, Z -40..24 with a roof at Y 28-32 and a glass showroom front facing +Z. Extend the apron to X 110. Keep at least 6 studs from the EndWall at X 34.4 as a walkway.
2. **Schrottplatz plus press building (Schrottpresse)** in the back lot, for example:
   - Press hall X -58..-20, Z -79..-44 with a ceiling of about 26.
   - Open scrapyard with a fence X -16..56, Z -80..-40, holding wreck piles, a crane and the Schrotthändler kiosk.
   - Access is by the west passage (X -111..-75) and the east passage (X 35..111). Removing the NeighbourBuildings would widen this to about X -110..110.
3. **Parkplatz-Chaos**: reuse the existing lined lot (6 bays 15×24 at X -45..45, Z 52..76), with a prompt kiosk at about (0,-1,48). The 3.0 game is a grid puzzle in the UI, so the physical lot is only decoration.
4. **Mechaniker-Quiz / training room**: a west annex, for example X -106..-80, Z -20..12, reached through a new door cut into Architecture/SideWall at X -74 (the wall runs Z -33..33, Y 0..9).
   - Alternative: a mezzanine over the office and foyer (X -74..-54, Z 0..33) at Y about 8.5, with about 11 studs of clearance. It would cross the window band at Y 9..12.2.
5. **Leaderboard board** (3.0 board is 22×16 on 18-stud supports):
   - East forecourt, around X 76..110, Z 33..44 (avoid the bench at X 80.5..87.5, Z 44..46 and the lamp at (102,38)).
   - Or west, around X -110..-76, facing the entrance and spawn at (-64,31).
6. **Second street**:
   - Only the 19-stud strip at Z 112..131 fits inside the boundary: a road of about 12 plus a sidewalk of about 5.
   - Anything bigger means moving the Boundary walls, enlarging the Yard, and changing the 330/260 spacing on World.lua line 56. The current plot size of 280×220 leaves at most 50/40 studs of slack.
   - If the world should be shared and walkable, the per-plot Boundary concept itself has to change.

## 5. Car templates: the "schön designte Autos"

**Where they live and how they are used**

- `ServerStorage.CarTemplates` holds 9 cars. `ReplicatedStorage.GarageShared.PreviewCars` holds 9 identical copies (verified part-for-part).
- PreviewCars are used by `viewport()` in GarageClient line 146: a camera at (18,11,-23) looking at (0,2,0), FOV 40.
- Every template is a flat Model with PrimaryPart `Root` (0.1 cube, T 1) at the origin. Y 0 is where the tires touch the ground.
- All parts are Anchored. 30 parts per car are CanCollide false (trim rods, work points, OBD).
- The front of the car is -Z and the rear is +Z.
- The template paint is teal (47,169,163). `CarFactory.Spawn` recolours every part named Paint, Hood or Mirror to `C.Cars[i].color` and then calls `PivotTo(bay.CarOrigin.CFrame)`.

**Sizes and part counts**

Width is always 9.85 including mirrors (7.8 without). Parts are counted as blocks/cylinders + wedges; every car has exactly 8 wedges.

| Template | Parts | Length × height | Rear axle Z | Wheelbase |
|---|---|---|---|---|
| compact | 114+8 | 13.9 × 5.3 | 3.2 | 7.7 |
| hot_hatch | 127+8 | 14.3 × 5.5 | 3.7 | 8.2 |
| crossover | 127+8 | 15.8 × 6.6 | 5.0 | 9.5 |
| sedan | 126+8 | 16.1 × 5.4 | 5.3 | 9.8 |
| wagon | 125+8 | 17.3 × 5.9 | 6.1 | 10.6 |
| sport | 125+8 | 14.8 × 5.0 | 4.2 | 8.7 |
| gt_coupe | 140+8 | 16.5 × 5.2 | 5.3 | 9.8 |
| super | 124+8 | 17.0 × 4.7 | 5.2 | 9.7 |
| electric | 141+8 | 15.7 × 5.2 | 4.8 | 9.3 |

The front axle is always at Z -4.5.

**Construction, shared by all nine** (compact values; Paint is Metal material for a metallic look)

- **Chassis**: Metal (22,26,31) slab 7.3×0.45×L at Y 1.65.
- **Body**
  - Lower tub: Paint 7.8×1.35×(8.7..12.1) at Y 2.5.
  - Front fender walls: Paint 0.45×1.7×4.65 at (±3.67, 2.95, -5.03).
  - Nose panel: 7.8×1.8×0.3 at Z -7.2.
  - Door skins: 0.2×1.5×6.8 at (±3.87, 3.1, 0.7).
  - Black Sills: 0.22×0.35×7.8.
  - Rear quarter panels (±3.83, Y 3.49) and tail panel 7.75×0.72×0.16.
  - Roof: Paint slab 6.9×0.28 at Y 4.55 (super) up to 6.1 (crossover).
- **Hood**: 7.1×0.22×3.9 at (0, 3.9, -5.5). `SetHood` hinges it at root·(0,3.9,-3.55) with a 65° opening.
- **Greenhouse**
  - Windscreen and RearGlass: 6.66×0.07 plates rotated about X. Windscreen rake from horizontal:

    | compact | hot_hatch | crossover | sedan | wagon | sport | gt_coupe | super | electric |
    |---|---|---|---|---|---|---|---|---|
    | 31° | 35° | 50° | 38° | 46° | 24° | 40° | 14° | 36° |

  - 2 thin WedgeParts (0.07×0.43) at X ±3.54 close each end of the windscreen and rear glass.
  - Side glass: 2 panes per side (0.07 thick), rotated about 19° around Z for tumblehome.
  - WedgePart FrontQuarterGlass and RearQuarterGlass fill the A-pillar and C-pillar triangles.
  - All glass: Glass (75,107,123), T 0.24, Reflectance 0.12.
  - Pillars and trim are Plastic (22,26,31) Cylinder rods:
    - WindowPillar 0.2, aligned to the glass edges with compound rotations.
    - B-Pillar 0.24; QuarterDivider 0.07.
    - WindowTrim 0.13 along the belt line (Y 3.83) and the roof edge (Y 5.04).
- **Wheels** (names WheelFL/FR/RL/RR + Tire/Rim/Hub/Spoke, and BrakeFL etc.)
  - Tire: Cylinder 1.0×2.6×2.6 SmoothPlastic (22,26,31) at X ±4.02, Y 1.3.
  - Rim: Cylinder 0.09×1.9 Metal (97,112,124) at X ±4.55.
  - Amber Hub: 0.12×0.48 at X ±4.61.
  - N spoke blocks 0.14×1.75×0.16 in steel, each rotated k·180°/N about X. N is 3 for compact and super, 4 for crossover, 5 for hot_hatch, wagon and sport, 6 for sedan, 8 for gt_coupe, 10 for electric.
  - Brake disc: Cylinder 0.38×1.5 copper (154,102,80).
- **Front and rear**
  - Black Bumpers 7.5×0.65×0.3.
  - Grille 3.7×0.55 with 5 GrilleBars.
  - Neon Headlamps (226,247,255): round (0.83 dia), twin rounds (gt_coupe), double slim strips (hot_hatch, super), rectangle (sedan, wagon) or slit (sport, electric).
  - TailLamps: Neon (240,78,65) 1.9×0.35×0.2.
  - Plate: 2.7×0.55 (224,231,230) with GothamBold text "UCG · 07".
- **Details**
  - Mirrors: Paint 0.85×0.4×0.75 at (±4.5, 3.95, -1.5) on stalks.
  - DoorHandles; 2 Seats 2.1×1.6×1.4.
- **Open engine bay** (identical in every car, used by jobs): EngineBayFloor, Engine plus 5 EngineRib, Battery plus BatteryTerminal, Ignition, Hose, Turbo, OilFilter, FilterMount, OilPan, LowerEngine, DrainBolt.
- **Invisible work points** (0.35 cubes): DiagnosticPoint, EnginePoint, BatteryPoint, WheelPoint, OilPort, HoodPoint. Plus OBDPort with 4 amber OBDPin.

**Per-body extras**

- hot_hatch: RoofSpoiler, SideStripe.
- crossover: steel RoofRail with feet, Cladding, SkidPlate.
- wagon: RoofRail, RearWiper.
- sport: Spoiler 8.1×0.17×1 on 2 SpoilerMounts.
- gt_coupe: SideVent, Exhaust.
- super: FrontSplitter, Intake, RearWingEnd, Spoiler.
- electric: painted grille, Front/RearLightBar, AeroSill.

**Show cars in the world**: Showcar_compact is teal. Showcar_sport has amber paint (247,176,63) but teal mirrors (they were not recoloured).

**Other techniques in the place worth copying**

- Tire stacks: each tire is 12 TreadBody blocks + 12 Sidewall blocks + 6 grooves arranged in a flat ring, 30 parts per tire.
- Trees: a vertical Cylinder trunk plus 5 tilted Cylinder branches, each carrying 4 WedgePart foliage pieces (3.4×2.6×4.1) in 4 graded greens.
- Bushes: 7 LeafSpray wedges each.

## 6. WorkshopExtensions and EquipmentTemplates

**Stage_2 / Stage_3 / Stage_4** (119 parts each)

- Authored in plot coordinates with Root at the origin. `layout()` in World.lua (lines 24-38) calls `PivotTo(plot pivot)`, parents the stage to Werkstatt.Extensions, and moves its `Bay_N` into Bays.
- Each stage is a 22-wide slice:

  | Stage | X range | FrontPillar X |
  |---|---|---|
  | Stage_2 | -32..-10 | -10 |
  | Stage_3 | -10..12 | 12 |
  | Stage_4 | 12..34 | 34 |

- Each slice contains Floor 22×1×66, BackWall, ClosedRoof, FacadeHeader, FacadeAccent, 4 RoofTrusses, 3 lights, FrontPillar, SafetyStripe, BackPillar, and AnnexSign "SERVICE / 0N".
- It also has a ServiceCabinet (the same 21-part tool chest), a ToolWall (38 parts), 3 PartsBoxes, and Bay_N.
- There are no side walls. The annex front below Y 12 is open; there is no roller door.
- The EndWall moves to X = -32+(bays-1)·22 (line 32).
- The ExpansionPoint moves to X = -36+(bays-1)·22 at Z 21, and is destroyed at `C.MaxBays` = 4.

**Bay_N** (34 parts), shown for Bay_1; the others are offset by +22 in X:

- CarOrigin (-43,0,-5); PlayerArrival (-49.4,3.5,1); EquipmentSpot (-36.8,0,7.5).
- Two teal LiftPosts (1.35×12×1.8) at X -50 and -36, Z -4, with LiftCaps and a LiftBridge 14 long at Y 12.2.
- MovingLift (15 parts): DiamondPlate platforms (76,85,92), 4 amber LiftArms, pads. It is raised by `C.LiftHeight` = 3.6.
- LiftControl (amber, carries the prompt).
- Amber BayLines at X -52.1 and -33.9; DeviceParkingLines.
- Sign on the back wall at Y 9.5; floor decal "01" at Z 11.7.

**EquipmentTemplates** (8 models, 12-13 parts each, Root at the origin)

- Shared base: Frame 2.5×0.3×2.8 slate Metal, 4 Caster cylinders, BadgeStand, and a Badge 2.3×0.85 with the name.
- Distinct bodies:

  | Device | Body |
  |---|---|
  | oil_drain | teal Tank, Bowl, Stand |
  | wheel_jack | Column, Forks, Wheel |
  | tire_machine | Housing, Turntable, Tower, Lever |
  | diagnostic_rig | teal Cabinet, Laptop, neon Screen (50,180,191), Meter |
  | hv_station | same as diagnostic_rig but amber |
  | brake_bleeder | amber PressureTank, Gauge, Hose, Bottle |
  | compressor | same as brake_bleeder but teal |
  | engine_crane | amber Mast plus Boom, Chain, Hook |

- Placement (`W.Equipment`, lines 232-254):
  - Storage grid `EquipmentPositions` at X {-70, -62} × Z {-24, -17.5, -11, -4.5}, in the order oil_drain, wheel_jack / tire_machine, diagnostic_rig / brake_bleeder, compressor / engine_crane, hv_station.
  - Or `Bay_N.EquipmentSpot` at (-36.8+22(N-1), 0, 7.5).
  - At runtime a neon LevelIndicator (62,217,166) and an IndicatorMount are added at +1.1 X.

## 7. Clash with the standalone 3.0 World.lua

`Ultimate_Car_Game/src/server/World.lua` `World.Build()` builds a Folder "Hof" at the world origin. That is exactly where slot 1's plot sits.

- Surfaces:
  - "Wiese" 400×2×400 Grass: top at Y 0, spans X/Z ±200, which also reaches slot 2's yard (X ≥ 190).
  - "Asphalt" 150×0.2×150 at Y 0..0.2.
  - Result: z-fighting with the hall floor (top Y 0) and a 0.2-stud lip above it.
- It adds its own Neutral SpawnLocation at (0,0.3,0).
- Its stations land on top of 2.4.0 geometry:

  | 3.0 station | Position | Lands on |
  |---|---|---|
  | Werkstatt | (-50,0) | inside the hall |
  | Schrottplatz | (-36,-36) | through the BackWall |
  | Parkplatz-Chaos | (-36,36) | the apron in front of the roller door |
  | Quiz | (36,36) | the apron |
  | Bestenliste | (0,50) | the parking lot |
  | Schrottpresse | (0,-48) | the back lot (free) |
  | Tuning | (50,0) | the east yard (free) |

- Its `car()` helper makes cars from 5 or more primitive parts, which look far worse than the 2.4.0 templates.
- It must be re-targeted to plot-local anchors (or a separate hub outside X -141..1131, Z -88..392) and should reuse CarTemplates.

### Integration points
- old World.lua L7-9: Werkstatt is cloned to ServerStorage.PlotTemplate and destroyed when the module loads. Per-player 3.0 zone geometry must be authored inside Workspace.Werkstatt (plot-local, Root at 0,0,0) before this runs, or be cloned and pivoted per plot in W.Create after L55-56.
- old World.lua L56: plot pivot CFrame.new(((slot-1)%4)*330,0,floor((slot-1)/4)*260), MaxPlots=8 (Config L16). Change this spacing if the plot template grows beyond 280x220 (current gaps are 50 in X and 40 in Z).
- Architecture/Boundary x4 (invisible, CanCollide, Y -1..51): (0,25,132) 282x52x1; (0,25,-82) 282x52x1; (+-140,25,25) 1x52x215. Move these to enlarge the walkable plot or to connect plots.
- Architecture/Yard: Concrete 280x1x220 at (0,-1.5,22), top Y -1. It is the only ground (no Terrain, void between plots, FallenPartsDestroyHeight -80). It must be enlarged under any new area.
- Reserved hall-growth corridor X -32..34.4, Z -33.4..33.4, Y -1..21: Stage_2..4 pivoted in World.lua layout() L24-38, EndWall moved to X=-32+(bays-1)*22 (L32), ExpansionPoint moved to X=-36+(bays-1)*22, Z 21 (L36).
- Free zone EAST X 37..109, Z -48..31 (72x79): Idle Tuning Garage building, e.g. X 44..104, Z -40..24, roof Y 28-32, front facing +Z. Extend EntranceApron (currently X -74.5..74.5, Z 33..45) east to X ~110.
- Free zone BACK LOT X -60..58, Z -81..-36 (118x45), between the NeighbourBuildings at X -101..-63 and 60..98 (Z -77..-51): Schrottplatz plus press hall, e.g. press hall X -58..-20, Z -79..-44, yard X -16..56. Accessed via the passages X -111..-75 and X 35..111.
- Free zone WEST X -109..-77, Z -48..35 (32x83): Quiz/training annex, e.g. X -106..-80, Z -20..12, with a door cut into Architecture/SideWall (X -74, Z -33..33, Y 0..9). Alternative: a mezzanine over the office and foyer (X -74..-54, Z 0..33) at Y ~8.5.
- Existing parking lot: ParkingLine x7 at X -45..45 step 15, Z 52..76 (6 bays 15x24); showcars at (+-49,-1,70). Use it as the Parkplatz-Chaos station, with a prompt kiosk near (0,-1,48).
- Leaderboard board (22x16 on 18-high supports): east forecourt X 76..110, Z 33..44 (avoid bench X 80.5..87.5 Z 44..46 and lamp at (102,38)) or west X -110..-76 facing the spawn at (-64,0.13,31).
- Second street: only the strip Z 112..131 (278x19) is free inside the boundary. A larger street needs the Boundary, Yard and L56 spacing changes.
- Prompt routing: do NOT parent 3.0 ProximityPrompts under Werkstatt.Stations (World.Create L60-63 binds them to callback('station', name), which opens a 2.4 page) or Werkstatt.YardActivities (L66-70 routes to the 'yard' action, GarageServer L277-278, which rejects ids not in C.YardTasks). Use a new folder such as Werkstatt.Minigames.
- 3.0 src/server/World.lua World.Build(): drop Wiese (400x2x400, Y -1), Asphalt (150x0.2x150, Y 0.1) and the SpawnLocation (0,0.3,0). Remap station CFrames (currently a ring of radius ~50 around the origin) to the plot-local zones above, multiplied by the plot pivot.
- Cars for 3.0 zones (wrecks, tuning, parking): clone ServerStorage.CarTemplates.<body> (Root at the origin, front -Z, wheels touching Y 0) and recolor parts named Paint/Hood/Mirror as CarFactory.Spawn L13-17 does, instead of the 3.0 car() primitive. Keep ReplicatedStorage.GarageShared.PreviewCars identical (used by GarageClient viewport() L146).
- GarageServer moveTo L88-97 teleports to (part.X, plotY+3.5, part.Z+6), where plotY is the PrimaryPart Y (0). New station anchor parts need free floor 6 studs toward +Z.
- Style constants for new builds: walls (31,43,55) Metal 0.8 thick; roof (42,48,55); frames (66,80,94); steel (156,170,177); amber accent Neon (247,176,63) strip under the header; teal (47,169,163); architectural glass (116,159,178) T 0.3; signs are slate plates with a GothamBold amber SurfaceGui on Face=Back (+Z), LightInfluence 0; building floors top Y 0 over yard Y -1; hall lights are Neon bars (232,246,249) with PointLight Range 25, Brightness 0.85, Color (224,238,255).

### Risks
- Running the 3.0 World.Build() unchanged overlaps plot slot 1 at the origin. The 400x400 Wiese (top Y 0) z-fights the hall floor, and the Asphalt (Y 0..0.2) forms a lip above it. The Werkstatt station at (-50,0) sits inside the hall, Schrottplatz (-36,-36) cuts through the BackWall at Z -33, Parkplatz (-36,36) blocks the apron in front of the roller door, and Bestenliste (0,50) sits in the parking lot. The Wiese reaches X 200, into slot 2's yard (X >= 190).
- Any geometry placed directly in Workspace (outside Werkstatt) at the free coordinates collides with slot 1's cloned plot, because slot 1's pivot is (0,0,0). Shared-hub content must go outside X -141..1131, Z -88..392, or the plot grid must be redesigned.
- Everything added to Workspace.Werkstatt is cloned for every player (up to 8). There are 1158 parts per plot today, rising to about 2200 with 4 bays, all equipment and 4 cars. Detailed new zones multiply part count, memory and clone time in W.Create at join.
- Enlarging the plot (moving Boundary walls or the Yard) without changing the 330/260 spacing on World.lua L56 makes neighbouring plots overlap (current slack: 50 studs in X, 40 in Z).
- Building anything in the corridor X -32..34.4, Z -33.4..33.4 clips into Stage_2..4 when a player buys bays (layout() L24-38, EndWall and ExpansionPoint are moved). Existing profiles can already have bays=4.
- Script-referenced names and structure must stay unchanged: Werkstatt.PrimaryPart Root, Bays.Bay_N.{CarOrigin, PlayerArrival, EquipmentSpot, LiftControl, MovingLift, Sign}, ActiveCars, Extensions, EndWall, ExpansionPoint.{Ring, Activate, Sign}, RollerDoor.{Panel, Control, ClosedOrigin}, Stations.{home, workshop, parts, upgrades, tools, shop}, YardActivities.{pressure, recycle}, PartsArea.{DeliveryOrigin, DeliveryBoxes}, EquipmentPositions.<id>, Equipment, ServerStorage.WorkshopExtensions.Stage_N, EquipmentTemplates.<id>, CarTemplates.<body>.
- Any new prompt placed under Werkstatt.Stations or Werkstatt.YardActivities is auto-bound by World.Create to 2.4 callbacks. It would open unknown 2.4 pages or be rejected as a yard task.
- Editing CarTemplates breaks 2.4 jobs. CarFactory relies on these part names: Paint/Hood/Mirror (recolor), WheelFL*/WheelFR*, Battery, Ignition, Hose, Turbo, OilFilter, OilPan, DrainBolt, Engine, EngineBayFloor, OBDPort, and the six *Point parts. SetHood hard-codes the hinge at root*(0,3.9,-3.55) with offset (0,0,-1.95). New 3.0 car looks should be new templates, and PreviewCars must stay identical to CarTemplates.
- A second SpawnLocation (for example the 3.0 Start at (0,0.3,0)) changes where characters first appear. In 2.4 the only spawn lives inside the plot clones and players are teleported to Stations.home via moveTo.
- The roller doorway check (|dX|<11, |dZ|<2 around (-43,5.95,31.6)) and car access over the apron (Z 33..45) must stay clear. Props there block the door close or the drive-in path.
- Lighting: GarageServer sets Lighting.ClockTime (L15 and the 0.5 s loop, 20-minute days). New zones need their own PointLights for night, but each light is duplicated per plot (17 per plot at 4 bays already); many lights times 8 plots cost performance.
- Cutting a door into Architecture/SideWall (X -74) means replacing a single 66-stud part and the Window/UpperBeam above it. Keep the WallFrame pilasters, and do not touch the movable EndWall at X -32, which relocates.