## 2.4.0 shared modules: data model, economy and how 3.0 fits in

Sources: `/tmp/claude-0/old/scripts/GarageShared.{Config,Rules,Locale}.ModuleScript.lua`. I checked them against the `Source` strings inside `old.rbxlx` and they are byte-identical. I also used Profiles, GarageServer, GarageClient and World for context. Line numbers below refer to those files.

### 1. Main findings
1. **3.0 would not see any 2.4.0 progress.** 2.4.0 saves under the key `"Player_"..UserId` (Profiles.lua:22). 3.0 uses `"player_"` (3.0 Config `ProfileKeyPrefix`, 3.0 Profiles.lua:35-37). DataStore keys are case-sensitive, so these are two different keys. Even if the key matched, 3.0 reads the wrong shape: it looks for top-level `credits/level/games`, but 2.4.0 stores the envelope `{version=2, data={money,...}, receipts, lock={token,expires}}`.
2. **The 3.0 migration test uses a made-up profile.** `tests/test_rules.lua:34-47` builds a "2.4.0 profile" with `credits`, `lifts`, `devices` and no envelope. None of that matches the real 2.4.0 format.
3. **2.4.0 `Rules.LoadData` deletes every field it doesn't know.** It builds a fresh `NewData` and copies over only whitelisted fields. `Profiles.Load` runs it inside the `UpdateAsync` transform (Profiles.lua:35-36), so the normalized result is written back **at join time**, not only at save. Any 3.0 field has to be added both to `R.NewData` and to `R.LoadData`, or it is lost on the next join.
4. **`raw.version ~= 2` resets the whole profile** (Rules.lua:33). Because Load writes back straight away, a merged build that writes `data.version=3` would wipe every player the moment they join a 2.4.0 server that is still running. Keep `version=2` and add a separate addon version field.
5. **The 3.0 diagnosis bonus makes repairs longer, not shorter.** 3.0 `WorkshopRules.RepairSpeed` (WorkshopRules.lua:23-25) is `(1+(tool-1)*0.08)*(1-diag)`, and `Accept` (line 96) sets `duration = time/RepairSpeed`. So 35 % diagnosis gives about 54 % *longer* repairs. The bug is copied from the reference HTML (`reference/Ultimate_Car_Game.html:704`).
6. **The 3.0 rewards are far too high for the 2.4.0 economy.** Details in section 6.

### 2. The 2.4.0 profile data model

**Stored envelope** (Profiles.lua:36/79/127): `{version=2, data=<profile>, receipts={[PurchaseId]=true}, lock={token=GUID, expires=os.time()+180}}`. There are three writers: Load, Save and GrantCredits. **All three rebuild the envelope from scratch**, so any other top-level key in the envelope is dropped.

**Profile** (`R.NewData`, Rules.lua:23-29):

| field | default | LoadData normalization |
|---|---|---|
| version | 2 | gate: anything else gives a fresh profile (l.33) |
| workshopVersion | 1 | missing means old 6-bay save, which triggers a refund (l.41-43) |
| days | 0 | integer 0..1e9 (l.34) |
| money | 800 (`C.StartMoney`) | `number` 0..1e24 (`C.NumberCap`) (l.35) |
| xp, reputation, completed | 0 | same as money (l.35) |
| level | 1 | integer 1..1e6 (l.36) |
| serial | 0 | integer 0..1e7 (id counter for `offer_N`, `job_N`, `delivery_N`) (l.37) |
| bays / offerSlots / toolLevel | 1 / 3 / 1 | loop over `C.Upgrades`: integer from `start` to `max` (4 / 30 / 100) (l.38) |
| equipment[id] | `starter or 0` (oil_drain=1) | integer from starter to `max` 5 (l.44) |
| equipmentBays[id] | {} | kept only if owned, bay is an integer in 1..bays, and one device per bay (l.103-109) |
| loadout | `C.DefaultLoadout` {scanner,ratchet,oil,tire,meter} | valid, de-duplicated, at most 5 (`HotbarSize`), topped up from the default (l.46-57) |
| yardReady[key] | 0 | clamped to `now + cooldown` (l.58-60) |
| inventory[sku] | {nexra_C_filter=3, nexra_C_oil=3} | only SKUs in `C.PartById`, integer 0..1e6 (l.61-64) |
| jobs / parkedJobs | {} | at most 6 in total, at most 2 parked, bay collisions resolved (l.65-94) |
| orders | {} | at most 30, `{id,sku,qty 1..20,eta ≤ now+120}` (l.95-102) |
| offers | {} | **not loaded**. Offers are regenerated at join (GarageServer:413) |

Job whitelist (l.77-79): `{id,kind,carId,bay,phase∈diagnose/repair/working/verify/invoice, step, quality 0..100, scanReady, workUntil ≤ now+120, selectedParts{kind→sku same family}, usedParts[≤8]}`. Any other job field is dropped. After normalizing, `R.Advance(d,now)` runs (l.110): orders whose eta has passed go into the inventory, and finished `working` steps move on.

Key lines of the function:
```lua
function R.LoadData(raw,_,now)
    now=now or os.time()
    local d=R.NewData(now)
    if type(raw)~="table" or raw.version~=2 then return d end
    ...
    for _,u in ipairs(C.Upgrades) do d[u.key]=integer(raw[u.key],u.start,u.start,u.max) end
    if not raw.workshopVersion and type(raw.bays)=="number" and raw.bays>=5 and raw.bays<=6 then
        for i=5,math.floor(raw.bays) do add(d,"money",finiteCost(800,1.7,i-3)) end
    end
```
The refund for retired bays 5 and 6 is 2312 and 3930 Cr. Other helpers: `number/integer` (l.4-8) reject NaN/inf and default the upper bound to `NumberCap`. `clone` (l.9-13) returns nil below depth 12. `R.Snapshot` is a deep clone, used both for saving and for the client push.

Other version fields: `C.Version="2.4.0"` (display only), `C.DataStoreName="UltimateCarGame_v2"`, `C.StudioDataStoreName="UltimateCarGame_Studio_v2"`, `SaveInStudio=false`, `AutosaveSeconds=45`, `LeaseSeconds=180`.

### 3. Economy and catalogs (Config.lua)

**Level and XP.** `R.XPNeeded = floor(80 + L*22 + L^1.16*4)` (Rules:121). Level 1 needs 106 XP, level 10 needs 357, level 38 needs 1188. Total XP to reach level 10 is 1944, level 38 is 23054, level 100 is 155043. `R.GainXP` (l.122-130) gives `120 + newLevel*18` Cr and +2 reputation per level, with at most 1000 level-ups per call. XP grants: Settle `round(def.xp*car.xp)`, BuyEquipment 20, BuyUpgrade 25 (none for bays), yard tasks 6 and 5.

**Cars** (l.34-44): `{id, brand, body, family C/L/P, level, value, reward mult, xp mult}`.

| car | level | reward | XP |
|---|---|---|---|
| komet | 1 | 1 | 1 |
| komet_s2 | 3 | 1.25 | 1.2 |
| nord | 4 | 1.5 | 1.35 |
| komet_urban | 7 | 1.85 | 1.5 |
| atlas | 10 | 2.2 | 1.7 |
| vektor | 18 | 3.6 | 2.25 |
| vektor_gtx | 24 | 4.5 | 2.6 |
| aureon | 30 | 5.8 | 3 |
| elys | 38 | 7 | 3.6 |

**Jobs** (l.94-178): level / base reward / XP / sum of step seconds.

| job | level | reward | XP | step seconds |
|---|---|---|---|---|
| oil | 1 | 240 | 42 | 14 |
| inspection | 1 | 155 | 32 | 12 |
| tire | 2 | 360 | 54 | 17 |
| battery | 3 | 425 | 62 | 16 |
| brakes | 5 | 720 | 80 | 26 |
| ignition | 8 | 850 | 95 | 18 |
| cooling | 12 | 1100 | 115 | 21 |
| turbo | 18 | 1800 | 160 | 30 |
| chain | 26 | 2700 | 220 | 34 |
| hv | 38 | 3900 | 280 | 34 |

Each job also has complaint/report/answers/`cause` for the diagnosis quiz. Steps are `{tool, point, lifted, hood, equipment, equipmentLevel, part, effect, seconds, alternatives}`. Tool alternatives are set on l.189-194.

**Repair duration.** `R.StepDuration = max(1, seconds / ((1+(toolLevel-1)*0.08) * (1+(eqLevel-1)*0.12)))` (l.269-272), used by `R.StartWork` (l.282). The gauge width is `min(0.48, 0.28+(toolLevel-1)*0.006)` (GarageServer:156).

**Pay.** `R.Reward` (l.285-293): `round(def.reward*car.reward*(1 + quality*0.0025 + avgPartQuality*0.01))`. Quality (0..100) can add at most +25 %, part brand quality (0/4/8) at most +8 %. Quality drops by 5 for a wrong diagnosis (`R.Diagnose`, l.226) and by 2 for a missed gauge (GarageServer:262). `R.Settle` (l.294-303) adds money, +1 `completed`, +2 reputation, then XP, and returns a parked job to a free bay.

**Offers.** `R.RefreshOffers` (l.178-199) fills up to `min(35, offerSlots)` offers. An inspection offer is always kept. `hv` jobs always use the Elys, and the Elys only takes inspection, tire, brakes, battery and hv jobs.

**Parts and the Lager (warehouse).** 3 brands (nexra ×1 q0, ferrovia ×1.35 q4, orvex ×1.75 q8) × 3 families (C ×1, L ×1.4, P ×2.4) × 11 `PartTypes` gives 99 SKUs named `brand_family_kind`. Price is `floor(kind.price*brand*family+0.5)`. Examples: nexra_C_filter 18, orvex_P_hvmodule 2016. `eta` is 0 for instant parts or 60/75/120 s for deliveries, and each part has a level gate (1..38). `R.Order` (l.254-268) takes qty 1..20, allows at most 30 open deliveries, and puts eta-0 parts straight into the inventory. `R.ChoosePart` never substitutes a brand the player picked explicitly. Inventory is `d.inventory`, deliveries are `d.orders`.

**Equipment** (l.84-93): 8 devices, max level 5 each. `R.EquipmentCost = cost*1.75^owned`, level-gated, one device per bay.

| device | price | level |
|---|---|---|
| oil_drain (starter) | 250 | 1 |
| wheel_jack | 350 | 2 |
| tire_machine | 700 | 2 |
| diagnostic_rig | 520 | 3 |
| brake_bleeder | 780 | 5 |
| compressor | 1650 | 12 |
| engine_crane | 2600 | 18 |
| hv_station | 6200 | 38 |

The tire and meter tools unlock through wheel_jack and diagnostic_rig.

**Upgrades and hall extensions** (l.179-187). `R.UpgradeCost = round(base*growth^(level-start))`.
- `bays`: base 800, growth 1.7, max 4. Stage 2/3/4 costs 800 / 1360 / 2312 Cr and needs level 2 / 4 / 8 (`C.BayLevels={1,2,4,8}`). The purchase goes through the quote-and-commit flow (GarageServer:171-183, 313-320) with an `expectedStage` check. World.lua:24-38 clones `ServerStorage.WorkshopExtensions.Stage_i`, moves `EndWall` to `-32+(bays-1)*22` and moves `ExpansionPoint` by 22 studs per stage.
- `offerSlots`: base 900, growth 1.48, start 3, max 30.
- `toolLevel`: base 700, growth 1.34, max 100.

**Yard tasks** (l.197-200): pressure gives 35 Cr and 6 XP, recycle gives 25 Cr and 5 XP, each with a 120 s cooldown, handled by `R.FinishYard`.

**Developer products** (`C.CreditProducts`, l.47-53). All five have `productId=0`, so they are disabled: `Purchases.ByProduct` rejects ids ≤ 0, and the client shows "In Kürze verfügbar".

| product | Robux | credits | bonus |
|---|---|---|---|
| starter | 80 | 3000 | 0 |
| service | 400 | 16500 | 10 % |
| garage | 800 | 34500 | 15 % |
| master | 1600 | 72000 | 20 % |
| fleet | 4000 | 187500 | 25 % |

That is 37.5 to 46.9 Cr per Robux. The grant goes through `Profiles.GrantCredits`, which writes money and the receipt atomically.

**Day and night.** `C.DaySeconds=1200` (20 real minutes per in-game day) and `DayStartHour=8`. `R.DayClock(at,epoch)` returns `hours = 8 + (at-epoch)*24/1200`, giving `(hours%24, floor(hours/24))`. The server sets `Lighting.ClockTime` every 0.5 s. `data.days` only increases while the player is online (`advanceDays`). The static Lighting in the place file is ClockTime 14.3, Brightness 2.6, plus Atmosphere (Density 0.23, Haze 1.1), ColorCorrection and Bloom.

**Reputation** is stored but never shown or used anywhere in 2.4.0. There is only a Locale key, "Ruf". It is free to take over the 3.0 meaning.

### 4. Locale
2.4.0 `Locale.lua` uses the German source phrase as the key. `L.Catalog.en` (l.4-22) holds about 50 English entries. `L.t(source, args, lang)` (l.23-36) fills **named** `{name}` placeholders and translates string arguments recursively. **There is no number formatting in Locale.** The only formatter is a client-local `fmt` in GarageClient.lua:50-56, and it has problems:
- It uses a dot decimal: `%.1f` gives "1.5 Tsd.".
- Numbers under 1000 get no digit grouping.
- It labels 1e18 as "Tsd. Brd." (wrong).
- World.lua:46-47 and the shop (`%.0f`) print raw numbers.

3.0 `Locale.lua` provides `Group` ("12.345"), `Number` (grouped below 1e5, then "123,5 Tsd.", "Mio.", "Mrd.", "Bio.", "Brd.", "Trio.", "Trd.", "Quadr.", then an e-notation fallback), `Credits`, `Scrap`, `Duration`, `Percent`, and `Locale.T(key, ...)` with **positional** `{1}` placeholders over id-keyed `Locale.Strings`.

**Plan:** keep a single `GarageShared.Locale`. Add the 3.0 number helpers as `L.Number`, `L.Credits` and so on. Keep both `L.t` (phrase keys) and `L.T` (id keys); Lua names are case-sensitive, so they can coexist. Replace GarageClient `fmt` with `L.Number`.

### 5. Where the 3.0 formulas plug into 2.4.0
Put all bonus helpers in a new leaf module (for example `GarageShared.Bonuses`) that requires only Config. 3.0 `PressRules` requires `Rules`, so putting these helpers in PressRules would create a circular require. Every helper must return 1 or 0 when a field is missing, because the client also calls `R.Reward` (GarageClient:190).
- **Diagnosis points shorten repairs, capped at 35 %.** In `R.StepDuration` (Rules:269-272), multiply by `(1 - DiagReduction(d))` with `DiagReduction = min(0.35, d.games.quiz.diagPoints*0.015)`, and keep `max(1, …)`. This fixes the sign error from 3.0 and the HTML. As an option, a correct first-try `R.Diagnose` (l.222-228) could award a diagnosis point.
- **Parking streak improves job quality, capped at 1.7.** Do *not* fold this into `job.quality`: that is a 0..100 workmanship score and the UI shows it as "Qualität {q}%" (GarageClient:185). Instead:
  1. Set `offer.customer = min(1.7, 1 + streak*0.03)` in `R.RefreshOffers` (l.187 and l.197).
  2. Copy it into the job in `R.Accept` (l.217).
  3. Whitelist `customer = number(j.customer, 1, 1, 1.7)` in LoadData l.77-79.
  4. In `R.Reward` (l.290), use `base = def.reward*car.reward*(job.customer or 1)` and XP `round(def.xp*car.xp*(1+(customer-1)*0.5))`.

  The 3.0 offer bonus (`DesiredOffers`, WorkshopRules:31-35) becomes, at Rules l.180, `target = min(35, offerSlots + min(5, floor(streak/5)))`.
- **Press multiplier boosts workshop pay at a 0.6 share, and tuning level boosts it too.** In `R.Reward` (l.291), multiply by `(1+(tuningLevel-1)*0.045) * (1 + (1 + totalPressLevels*0.0025 - 1)*0.6)`. `totalPressLevels` is the sum of `d.games.press.upgrades`, so no Catalog is needed. Also update the "Basis" line on the offer card (GarageClient:197). Note that a rebirth resets press upgrades, so the workshop bonus from the press drops back after a rebirth.
- **Tuning and scrapyard upgrades.** Add `{key="tuningLevel", base=850, growth=1.38, max=100, start=1}` and `{key="scrapyardLevel", base=650, growth=1.35, max=100, start=1}` to `C.Upgrades`. LoadData l.38, `R.UpgradeCost`, `R.BuyUpgrade` and the client Ausbau page (GarageClient:254-262) then handle them automatically. 3.0 uses the field name `desc`; 2.4.0 needs `description`. The server `upgrade` action requires `station(p,"upgrades")`; decide whether tuning upgrades should also be allowed at the tuning hall.
- **Goals, daily goals and milestones.** Call `AddStat(d,"jobsDone")` in `R.Settle` (l.300). 3.0 milestones that use `level` read `d.level`. `GoalRules.NextGoal` has to switch from `job.endsAt` to 2.4.0 `phase=="invoice"`. Also emit stats from `R.FinishYard` and `R.BuyEquipment`.
- **Money grants.** Every 3.0 `p.credits += x` becomes `add(d,"money",x)`, which respects the 1e24 cap. Every 3.0 `Rules.GainXP` becomes `R.GainXP`. The formula is identical, but 2.4.0 returns a number and 3.0 returns `{levels, credits}`.

### 6. Duplicated concepts and how to unify them

| 3.0 | 2.4.0 | Unify as |
|---|---|---|
| `p.credits` (cap 2^53) | `d.money` (cap 1e24) | `d.money` |
| `p.level`, `p.xp`, `XpNeeded`, `GainXP` | identical formulas | keep 2.4.0 |
| `games.reputation` (integer) | `d.reputation` (unused) | `d.reputation`, keeping the 3.0 sources (+1 parking, +2 tuning, press type-2 upgrades) |
| `games.bays` (1100×1.42^n, max 50) | `d.bays` (800×1.7^n, max 4, level-gated, physical Stage_2..4) | **2.4.0 only** |
| `games.offerSlots` (cost `^(lvl-1)`, so 1971 at level 3) | same parameters but `^(lvl-start)` (900 at level 3) | 2.4.0 formula |
| `games.toolLevel` | identical parameters | `d.toolLevel`. 3.0 `SideGameRules.ToolBonus` (l.9-11) reads it |
| `games.parts` (a count; +3 daily, dismantle, sell 5 for 220 Cr, cuts job cash cost) | `d.inventory` SKUs plus `d.orders` | Recommended: Schrottplatz finds become real SKUs in the car's family (nexra, or orvex for a rare find) and go into `d.inventory`. Otherwise add a separate `d.salvage` counter for SellParts. The daily parts become nexra_C filter/oil. Drop `CashCost`. |
| `games.jobs/offers/nextId`, `Config.Jobs` (7 timer jobs), `WorkshopRules.Accept/Finish/Reward/RefreshOffers` | 2.4.0 hands-on jobs and `serial` | drop the 3.0 versions |
| `schema=3`, `_lock{job,id,t}`, 600 s timeout | `version=2`, `lock{token,expires}`, 180 s | keep 2.4.0 Profiles. Add `d.addonVersion` |
| `Snapshot.Build` (derived view) | push `R.Snapshot(d)` (full clone) | send the 3.0 view on its own remote. Never clone secrets into it |
| `Net` (Action/Sync/Notice under `ReplicatedStorage.Shared`) | `GarageShared.Remotes.Command/Event` | move the 3.0 modules into `GarageShared` to avoid two Config/Rules/Locale sets |
| UTC `daily` | in-game `days` | keep both. They mean different things |
| GamePasses (UserOwnsGamePassAsync) | DevProducts (ProcessReceipt) | compatible. Only 2.4.0 sets ProcessReceipt |

**Proposed storage:** `d.games = {press, tuning{projects,lastIdle,completed}, scrapyard{vehicle}, quiz{diagPoints}, parking{streak,best,puzzle}, stats, milestones, daily}`. Put `d.tuningLevel` and `d.scrapyardLevel` at the top level. Port the 3.0 LoadData blocks (3.0 Rules.lua:182-273) into 2.4.0 LoadData before `R.Advance` (l.110), reading from `raw.games`. Use `hi=1e300` for scrap and lifetime, because the default `number()` cap of 1e24 would cut them off.

**Balance.** 3.0 values were tuned for the HTML idle game:
- **Press:** 5 per click × combo up to 25 × 20 clicks/s gives 2500 scrap/s. At the exchange rate of 4:1 × 0.8 that is **500 Cr/s**, so about 70 s of auto-clicking equals the 800-Robux pack.
- **Quiz:** 90 Cr and 20 XP per correct answer with a **1 s cooldown**. At that rate a player gets from level 1 to 10 in about 97 s, which bypasses the 2.4.0 level gates for jobs, cars, parts, equipment and `BayLevels`.
- **Tuning:** an 8-hour project pays about 99k Cr, compared with an oil change at 240 Cr.

Rescale these, add cooldowns, or pay in a separate currency.

### Integration points
- 2.4.0 Rules.lua:23-29 R.NewData: add defaults d.games={press,tuning,scrapyard,quiz{diagPoints},parking,stats,milestones,daily}, d.addonVersion=1; tuningLevel/scrapyardLevel come from C.Upgrades loop
- 2.4.0 Rules.lua:30-112 R.LoadData: keep 'raw.version~=2' gate (l.33) but never bump version; insert normalization of raw.games.* (port of 3.0 Rules.lua:182-273, adapted to d.games, scrap/lifetime hi=1e300) before R.Advance at l.110; otherwise fields are erased at join because Profiles.Load (Profiles.lua:35) writes LoadData output back inside UpdateAsync
- 2.4.0 Rules.lua:77-79 job whitelist in LoadData: add customer=number(j.customer,1,1,1.7) (and any other new job field)
- 2.4.0 Rules.lua:269-272 R.StepDuration: multiply seconds by (1-min(0.35,d.games.quiz.diagPoints*0.015)) keeping math.max(1,...) - correct sign, unlike 3.0 WorkshopRules.RepairSpeed l.23-25 / Accept l.96
- 2.4.0 Rules.lua:178-199 R.RefreshOffers: l.180 target=min(35,d.offerSlots+min(5,floor(streak/5))); l.187/l.197 set offer.customer=min(1.7,1+streak*0.03)
- 2.4.0 Rules.lua:207-221 R.Accept l.217: copy job.customer=offer.customer or 1
- 2.4.0 Rules.lua:285-293 R.Reward: base*=job.customer; reward*=(1+(d.tuningLevel-1)*0.045)*(1+totalPressLevels*0.0025*0.6); xp*=(1+(customer-1)*0.5); must be nil-safe because GarageClient.lua:190 calls R.Reward on the client
- 2.4.0 Rules.lua:294-303 R.Settle l.300: AddStat jobsDone for daily goals/milestones; optionally reputation 2+floor((tuningLevel-1)/3)
- 2.4.0 Rules.lua:122-130 R.GainXP: single XP/level-up implementation; replace 3.0 Rules.GainXP (3.0 Rules.lua:303) calls, adapting return value (number vs {levels,credits})
- 2.4.0 Rules.lua:14 add(d,'money',x): replace every 3.0 'p.credits += x' (PressRules.Exchange l.177, TuningRules.Collect l.91/CollectIdle l.134, SideGameRules Dismantle l.31/SellParts l.51/Answer l.95/Tap, GoalRules claims) so NumberCap 1e24 applies
- 2.4.0 Config.lua:179-183 C.Upgrades: append tuningLevel {base=850,growth=1.38,max=100,start=1} and scrapyardLevel {base=650,growth=1.35,max=100,start=1} with 'description' field; auto-handled by LoadData l.38, R.UpgradeCost l.339, R.BuyUpgrade l.343, GarageClient upgradesPage l.254
- New leaf module GarageShared.Bonuses (requires only Config): DiagReduction, CustomerBonus, PressGlobal(d) from sum of d.games.press.upgrades, WorkshopPressMultiplier, TuningWorkshopBonus - avoids circular require (3.0 PressRules requires Rules)
- 2.4.0 Locale.lua: add L.Group/L.Number/L.Credits/L.Scrap/L.Duration/L.Percent from 3.0 Locale.lua:20-98 and L.Strings+L.T; replace GarageClient.lua:50-56 fmt; format raw numbers in World.lua:46-47 and shop GarageClient.lua:269
- GarageServer.lua:71-80 push: sends R.Snapshot(d) (full clone) every 0.5 s (tick loop l.435-448); send 3.0 Snapshot.Build view on its own remote and keep quiz.current (answer order, 3.0 SideGameRules.lua:76) out of d
- GarageServer.lua:374 transacting guard and Profiles.lua:131 (GrantCredits overwrites profile.data.money): all new minigame remote handlers must refuse money mutations while profile.transacting
- 3.0 SideGameRules.ToolBonus l.9-11 -> read d.toolLevel; SideGameRules.Dismantle l.31-49 -> write SKUs into d.inventory (or d.salvage); GoalRules.ClaimDaily l.103-117 +3 parts -> SKUs
- 3.0 GoalRules.Stat l.12-24 / NextGoal l.131-184: map level->d.level, jobsDone->stats (or d.completed), replace g.jobs endsAt check with 2.4.0 phase=='invoice'
- 3.0 Profiles.lua / Config.ProfileKeyPrefix 'player_': drop entirely; use 2.4.0 Profiles (key 'Player_'..UserId, envelope {version=2,data,receipts,lock})
- Purchases: keep 2.4.0 Purchases.lua ProcessReceipt as the only receipt handler; 3.0 GamePasses (UserOwnsGamePassAsync) can coexist

### Risks
- Bumping data.version to 3 (or anything !=2) makes any still-running 2.4.0 server return NewData in LoadData (Rules.lua:33) and immediately write it back in Profiles.Load (l.35-36): total progress wipe. Keep version=2 and add a separate addonVersion field.
- Old 2.4.0 servers still running after publish will strip all new fields (LoadData whitelist + envelope rebuilt in Load/Save/GrantCredits as {version,data,receipts,lock}). Use 'Shut down all servers'/migrate on publish; a player hopping to an old server loses minigame progress.
- Forgetting to add any new field to both R.NewData and R.LoadData deletes it on the next join (LoadData output is written back at load time, not only at save).
- Using 3.0 Profiles as-is: key 'player_' vs 2.4.0 'Player_' (case-sensitive), so every player would start fresh with 800 Cr and level 1. With the key corrected it would still misread the envelope (no top-level credits/level) and ignore the 2.4.0 lock format {token,expires}, which allows two concurrent writers.
- 3.0 Profiles uses the live store name in Studio (no Studio-specific store), unlike 2.4.0 (UltimateCarGame_Studio_v2, SaveInStudio=false). Studio tests of 3.0 code with API access could write to production data.
- 3.0 migration test (tests/test_rules.lua:34-47) uses a fabricated 2.4.0 profile shape; it gives false confidence and must be replaced with a real envelope from old.rbxlx-era data.
- Profiles.GrantCredits sets profile.data.money=result.data.money (Profiles.lua:131). Any minigame credit earned between the snapshot and the commit is lost unless new handlers respect profile.transacting like GarageServer.lua:374.
- Quiz answer order (games.quiz.current.order) stored in d would be cloned to the client every 0.5 s by push (R.Snapshot(d)), leaking the correct answer. Keep it in server session state.
- The 3.0 diagnosis bonus as written makes repairs up to 54% longer (RepairSpeed multiplies speed by (1-diag), then duration=time/speed). Do not port it as-is.
- 3.0 offerSlots cost uses growth^(level-1) instead of ^(level-start): offerSlots 3 would cost 1971 instead of 900. Mixing formulas changes prices for existing players.
- Economy: press exchange yields ~500 Cr/s with an autoclicker (5×25 combo×20 clicks/s /4×0.8); quiz 90 Cr + 20 XP per 1 s cooldown; 8 h tuning ~99k Cr. These dwarf 2.4.0 jobs (155-3900 Cr), bypass level gates (cars/jobs/parts/equipment/BayLevels) and undercut the Robux credit packs (3000 Cr for 80 Robux).
- The default number() cap (C.NumberCap=1e24) would silently clamp press scrap/lifetime if normalized with 2.4.0 helpers; the 3.0 leaderboard relies on values up to 1e300.
- Circular require if 2.4.0 Rules requires 3.0 PressRules (which requires Rules); R.Reward/StepDuration run on the client too (GarageClient.lua:190), so bonus helpers must be nil-safe.
- Adding press/tuning/goals data to d increases push payload (full deep clone every 0.5 s per player, GarageServer.lua:445) and DataStore size; the receipts map in the envelope is also never pruned.
- Two module sets (ReplicatedStorage.Shared vs GarageShared) with the same names Config/Rules/Locale make it easy to require the wrong one; C.Upgrades entries need 'description' (2.4.0 UI) while 3.0 uses 'desc'.