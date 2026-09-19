# QA CYCLE 7 (loop 17) — RULINGS ON D-107…D-152
QA Director, 2026-09-18. READ-ONLY cycle: no Godot run was made (producer holds the gate).
Rulings are FIXED / PARTIAL / OPEN / PLAUSIBLE-UNVERIFIED. Every line cites a plate or a log line.

## Running log (appended as each ruling is made)

### Build audited
HEAD = `d499c08` "Round 16b (D-071): one objective line on screen", 2026-09-18 19:32.
**The tree was being edited while this audit ran** (D-084 again): `git status` at audit
time showed uncommitted work on `game/scripts/systems/repo_orders.gd`, `save_load.gd`,
`session.gd`, `game/data/mechanics/repo_orders.json` and `docs/decisions.md` — the D-072
NEW GAME work. Every code ruling below is against **HEAD d499c08**, not the dirty tree.
No Godot process was started by QA this cycle (producer holds the gate).

### First hard finding, before any ruling
`round16/plates/order_push.png` — the plate filed as evidence for the loop's push — does not
show a push. It shows **four HUD elements stacked at once**: the COMIN' DOWN contract card
(mission_kit, layer 16, an 1800x190 78%-alpha veil across the whole frame), a green "EVADED"
banner, repo_board's gold flash "GAVE THEM THE WEEK RESPECT +1", and the LONGHORN app panel
bottom-right — plus **two mission objective labels overprinting character-for-character** in
one 30 px band. Colour separation of the crop (scratchpad `c2.png`, `sep_pink.png`) resolves
them: cream (242,237,219 = `mission_hook_and_ladder` objective colour 0.95/0.92/0.8) reading
"LONGHORN DISPATCH RE-ARM 22s", over pink (229,147,206 = `mission_comin_down`'s
`CANDY.lightened(0.35)` = 232,149,209) reading "CANDYLAND RE-ARM ..".
The producer found the same thing and committed `d499c08` blanking both COMPLETE strings —
AFTER the plate. **The structural cause is untouched**: `mission_hook_and_ladder.gd:471` and
`mission_comin_down.gd:294` both claim `PRESET_CENTER_BOTTOM, offset_top=-240,
offset_bottom=-210`, with no arbiter. Filed as D-155.

## RULINGS — D-107 … D-152

| # | Sev | Ruling | Why (plate / log line / source line) |
|---|---|---|---|
| D-107 | S1 | **FIXED** | `cloth-sept13/after/torso.png`: the light terminator runs correctly across the sleeve and the only dark interior in the frame is seen *through* the armhole void — the signature of an outward-facing one-sided mesh. Every skinned plate since is correctly lit and shadowed. |
| D-108 | S2 | **OPEN** | `cloth-sept13/after/torso.png` + `plates/face.png`: the shirt carries a placket and two pockets and **no collar of any kind** — a plain crew curve at the neckline. No `collar` review plate was ever filed. |
| D-109 | S3 | **FIXED** | `character_factory.gd:1574` `if not bool(cfg.get("skinned_body", false))` guards the neck/nape build; no tube seam at `face`. |
| D-110 | S3 | **PARTIAL** | Near eye is calm: `character_factory.gd:74` SCLERA 0.74/0.71/0.68, and `face.png` at 4x shows lid, iris, limbal ring, catchlight. **The far eye is a lidless white almond on the silhouette** — filed D-168. |
| D-111 | S3 | **PARTIAL** | Boot line `SURFACES: materials=947 shaders=7 normalmapped=72`; pores read at 4x; head/body no longer shade differently. **Cloth has no surface**: `after/torso.png` is a uniform matte panel, no weave, no fold, no drape. |
| D-112 | S4 | **FIXED** | Corrected with D-107 to `(c-a)x(b-a)`. |
| D-113 | S3 | **PLAUSIBLE-UNVERIFIED** | The 26.6/27.9 mm numbers describe garments that no longer exist (D-067 rebuilt them as shells). Needs: `godot --headless --script res://tools/skin_rim.gd` — assert max proud <= 5 mm on every shell. |
| D-114 | S4 | **PARTIAL** | `character_hands.gd` exists (3 mm field, separate meshes). No current `hand` plate: the newest is round5, three rounds before the cloth shells. Needs `tools/character_review.gd -- --out=DIR`, `hand` view. |
| D-115 | — | **SPLIT** | Session flow: **FIXED** — `SESSION TEST: PASS (0 failures)` in three consecutive `gate_quick.md` (rounds 13/14/16). Face pass: **OPEN** — see D-117 and D-108. |
| D-116 | S4 | **OPEN** | `tools/skin_rim.gd:84` still prints `TAILORED (explicit fabric mesh; not a shell, not graded here)`. No clearance measure for fabric grids exists. |
| D-117 | S3 | **OPEN** | `cloth-sept13/plates/face.png`, left pedestrian, crop x0-110/y230-360 at 5x: the beard is a **hard-edged dark polygon** glued from the ear to the chin with a straight diagonal boundary across the cheek, and a **lighter rectangular sub-panel with a dotted seam inside it**. The moustache is a separate pale sliver. The 22% feather is in the code (`character_factory.gd:1515`); it is not in the render. |
| D-118 | S3 | **FIXED** | round16 windowed probe, stage1 3/3: `last_reason published: PROBE CRIME`, `banner subline shows the reason`, `evaded clears the reason`. |
| D-119 | S2 | **FIXED** | stage4 6/6 in four consecutive probe logs: card, lot 3.7 m from the pad, on foot, heat 0, `$0 -> $-150`. Both the officer path and (D-123) the cruiser path. |
| D-120 | S3 | **FIXED** | stage2 7/7: `energy 6.50` on S, `1.50` on release, `2` spots bound, tail material private to the player's ride, horn plays/stops. |
| D-121 | S3 | **FIXED** | `vehicle_damage.gd:63-65` reads `var vv: Variant = st["v"]` and validity-checks before the cast, with the D-121 comment on it. |
| D-122 | S2 | **FIXED** | stage3 11/11: 0.35 / 0.55 / x1.30 / chain held / ends at 8.0 real-s / all four restored / 6 s cooldown. Tuning is unjudged — that is a Milad question, not a bar row. |
| D-123 | S3 | **FIXED** | stage4: `closest 5.2 m, at the bust 5.2 m, cruiser speed 0.03`, `heat at the bust 1`. |
| D-124 | S2 | **FIXED** | stage5 4/4 + stage6 4/4; persisted at `save_load.gd:159` / `:204` (`favors`). |
| D-125 | S4 | **PLAUSIBLE-UNVERIFIED** | Code is there: `pedestrians.gd:477` with `HOT_HEAT := 2; HOT_RADIUS := 12.0`. **No probe row, no plate.** Needs a probe stage: 2 stars, a ped at 10 m, assert the ped's state goes to FLEE within 1 s. |
| D-126 | S2 | **FIXED** | stage7: before `z -7.2 m` (`mech_probe_pad_before_fix.log`), after `on the pad, z -3.9 m, y 0.54, in 2.2 s`. |
| D-127 | S3 | **FIXED** | stage8 7/7: jab lands, he squares up (state 3), -6 unguarded, -3 guarded, 0 on a perfect block, staggered, counter puts him down. |
| D-128 | S2 | **FIXED (flat ground only)** | stage0 `0.000 m` over 8 s in rounds 14/15/16 (before: 3.270 m). **Not tested on a slope** — the probe parks on flat ground. Needs: park on the frontage grade, 8 s, assert < 0.02 m. |
| D-129 | S2 | **OPEN** | The player's animator moved (gait strips). **The crowd's did not.** `loop-sept18/plates/showcase_people.png` (round 13, the newest in-game crowd plate): five pedestrians in ONE identical pose — feet together, arms straight down at the sides, no weight shift, no head turn. That is the A-pose complaint with the arms lowered. |
| D-130 | S3 | **FIXED (downtown + frontage)** | Boot line `STREET WEAR: 390 lids, 280 drains, 790 patches, 3 draw calls`; lids visible in `boone_lot.png`. Suburb still clean — carried as the remainder. |
| D-131 | S3 | **PLAUSIBLE-UNVERIFIED** | No `hand` plate newer than round 5 (pre-cloth, pre-`character_hands.gd`). Needs `character_review.gd -- --out=DIR`, `hand` + `collar` views. |
| D-132 | S3 | **FIXED against the bar row** | Bar §1 grades mid-face "at 4x zoom". At 4x (`f_midface.png`) the vermilion, the philtrum and the nasolabial read. At 1:1 the mouth is still a dark smear — noted, but the row is 4x and the row passes. |
| D-133 | S4 | **PARTIAL** | Punch: stage8 proves damage and `brawl.png` the stance. **Honk: unprobed and unverified.** Needs a probe row: block a traffic car for 2.4 s, assert its horn stream is playing. |
| D-134 | S2 | **PARTIAL** | The taper is real (`measure_after.txt`: rib trunk 0.324 -> waist 0.288, lats, pecs). Three things are not: **shoulders measure 0.468 m at nominal, 12 mm under the bar's 0.48 floor** (D-163); the legs are ONE mass from crotch 0.840 down to mid-thigh 0.650, so `cloth-sept13/after/full.png` reads as a skirt; and `showcase_people.png` gives five people one body. |
| D-135 | S3 | **FIXED** | `measure_after.txt`: instep 0.085 / vamp 0.050 / sole 0.020 with depth 0.288, span 0.216 — a shaft, a vamp below instep height, a welt. Visible in `after/full.png`. |
| D-136 | S2 | **FIXED (the content) / the presentation is now the defect** | stage9 8/8 (2 lines queued, drone, owner out, card, $950 = 600+150+100+100). The card itself now blanks the centre of the screen over live play — D-153. |
| D-055 upd | S3 | **FIXED by construction** | `hud_gta.gd:460-468` draws the D marker, the N marker and a gold ring on a live mission target. A `--hudshot` plate is still owed. |
| D-137 | S3 | **FIXED** | stage10 8/8: 3 cycles into the Slab, board, 7 lines, pass at x=770, Task Force star, SLIDE OUT, +$250 / respect +6, card. |
| D-138 | S1 | **FIXED** | `gait-sept13/after/sprint_side.png`, 8 frames: the legs split ~60-70 deg, the heel recovers to the seat, the knee lands bent, elbows ~90, a 12 px crown oscillation on a 338 px figure = 6.2 cm of bounce. It is a run. **New, smaller**: the arms never swing behind the torso in any of the 8 frames (D-171). |
| D-139 | S2 | **PARTIAL** | Knees fixed and measured (knee 0.108 each, outer span 0.252, was ~0.34). The shoulder is not: 0.468 fails the bar (D-163), and the "one-cell armpit slot" is now an actual **through-hole in the garment** (D-156). |
| D-140 | S2 | **PARTIAL** | `loop-sept18/plates/map.png`: 8 districts, ~11 place dots, a job legend from the session, a 500 m bar — the claim is met structurally. It is **not legible**: `HARVEST HILLS(TM)STONEBRIDLE RANCH` runs together, `OVERFLOW CAMPUS` is overprinted by marker 2 and the player arrow, `Cattleman's Trust Tow..`, `Iglesia Baut..` truncate, `Gilead Bottoms` collides with `Teatro Estrella`. Filed D-167. |
| D-141 | S2 | **FIXED (the build)** | `world-sept13/plates/{fair_gate,tall_tom,fair_wheel_night,harvest_edge}.png` + `TALL TOM: 17 m tall at (868.0, 1.35, 258.0)`. Remainder carried: no traffic on Fair Drive or the parkway. |
| D-142 | S1 -> S2 | **PARTIAL** | The S1 is gone: `after/torso.png` shows a shell with real volume off the body. Three failures remain — an **open hole at the armhole** (D-156), sleeves whose diameter is two thirds of the whole chest panel, and trousers that merge into one column. |
| D-143 | S1 | **FIXED (the system)** | stage11 in three separate rounds: push, phone (351 chars), towable + radar ring, debtor out, hook, `DELIVERED: +$675`, RECOVERED card, bad paper pushed and voided (respect +3, paper burned 1), rank and quota persisted (`save_load.gd:163`). The ten-quiet-minutes playtest is still owed and only Milad can take it. |
| D-144 | S2 | **FIXED (the system)** | stage12 8/8: 3 rigs stocked, 96-month note $0 down, nothing at signing, first draft -$392, two misses -> recovered, wrecker kept, sedan for cash $5100. Notes persisted (`save_load.gd:173-176`). **The lot has no trucks on it** — D-158. |
| D-145 | S3 | **FIXED (the build)** | `CEDAR CLIFF: 45 houses, 14 storefronts, 31 labels`; `cliff_boulevard.png`. Remainder: the mid-distance sign panels read as blank colour blocks (D-166). |
| D-146 | S2 | **FIXED** | stage13: `five spur routes qualified from the atlas (5)`, `spur traffic on the boulevard after 40 s: 12 shells`. The nine-second nose-to-nose playtest is owed. |
| D-147 | S2 | **FIXED** | stage13: `the boulevard's sidewalks have people: 10 (want >= 2)`. |
| D-148 | S2 | **FIXED (the mechanism) / PLAUSIBLE-UNVERIFIED (legibility)** | stage11: `the phone opens on the order (351 chars)`, `closes after three tabs`. **No phone plate was ever filed**, so "is the tell legible at 720p, does the note list overflow the column" is untested. Needs `--hudshot` with the phone open on a bad-paper order. |
| D-149 | S3 | **PLAUSIBLE-UNVERIFIED** | `round14/plates/boone_wade.png` exists but Wade is not in `boone_lot.png`, the vantage a player arrives at. Needs the `boone_lot` vantage re-shot with Wade in frame. |
| D-150 | S1 | **FIXED** | stage14 in rounds 15 AND 16, headless and windowed: `FLEEING`, `the traffic brain is driving the car`, `ran 23 m in 4.5 s`, `boxed in and hooked after 7.2 s`, `the brain let go`, `+$1013` (pickup 450 x 1.5 distance x 1.5 run). **But the windowed run threw `ERROR: Lambda capture at index 0 was freed` inside this stage** — D-165. |
| D-151 | S2 | **PLAUSIBLE-UNVERIFIED** | stage11 proves only that `loop_audio carries 11 cues` and that one plays **on demand**. Nothing proves a cue fires on the loop's own signals, and nothing in a log can be judged by ear. Needs a probe row per signal (push / delivered / drafted / bad paper) asserting the stream is playing within 0.3 s, and then Milad's ears. |
| D-152 | S2 | **PARTIAL** | The count is met (`the club came out: 14 on the lot (want >= 6)`). The plate is not: `round16/plates/takeover.png` shows a **row of identically-posed ambient walkers crossing an empty daylight lot** — evenly spaced ~8 m apart, same stride phase, none facing the Slab, no four rides gathered, and no bulbs because the plate is not at night. D-157. |

### Carried block D-100 … D-106 (not in scope, status recorded)
- D-100 S1 perf: **PLAUSIBLE-UNVERIFIED.** No quiet-machine perf run has happened since the budget
  tier shipped; every gate since has said `CONTENDED` (`gate_quick.md` load 5.22, 5.6, 7.98). Needs
  `tools/gate.sh --full` with load < 2.
- D-101 S2 factory pillow shoulders: **WONTFIX-BY-DEFAULT** — the factory body is no longer the
  default (`--factory` only). Reword, do not close.
- D-102 S3 skinned neck: **OPEN.** At `face`, `torso` and all five of `showcase_people` the head
  meets the garment with **no visible neck column** — no throat, no sternocleidomastoid.
- D-103 S3 foot officers: **FIXED by construction** — `foot_cops.gd:212-213` reads
  `police.search_center` while `search_active`; `police.gd:222-223` publishes it.
- D-104 S3 lit windows at noon: **FIXED by construction** — `downtown_types.gd:103`
  `DAY_E: [0.10, 0.10, 0.10, 1.05, 1.15]` with the D-104 note; `facade_kit.gd:307-308` drives
  `set_night_level` in every arm.
- D-105 S4 race RUNNING forever: **OPEN**, no evidence either way this cycle.
- D-106 audio-at-quit leak in windowed runs: **RULING — leave §5 as written.** The gate row is
  defined on the headless 900-frame boot and that boot measures 0-6. Do not widen a bar row to
  cover a measurement the row does not take; if windowed leaks matter, add a row for them.

## NEW DEFECTS FILED THIS CYCLE — D-153 … D-171
(full text in `docs/qa/defects.md`)
D-153 S2 the contract card blanks the centre of the frame over live play ·
D-154 S2 no HUD arbitration: five elements at once ·
D-155 S3 two missions' objective labels share one slot ·
D-156 S2 an open hole at the armhole ·
D-157 S2 the takeover "club" is a row of identically-posed walkers ·
D-158 S3 Boone Trucks' lot has no trucks on it ·
D-159 S3 the Boone pylon's own frame splits every line of its text ·
D-160 S3 the combat reticle is baked into every judgement plate ·
D-161 S3 a downed pedestrian is interpenetrated by a knocked-over hydrant ·
D-162 S3 `body_measure.gd` has no head row, so bar §1's head-height row is unmeasured ·
D-163 S3 shoulders 0.468 m — 12 mm under the bar floor, and the row is ambiguous ·
D-164 S3 `zz_mech_probe.gd:942` asserts `>= 450` while naming "base x 1.5" ·
D-165 S3 `Lambda capture at index 0 was freed` at stage 14 ·
D-166 S3 Cedar Cliff's mid-distance sign panels are blank colour blocks ·
D-167 S3 the pause map's labels collide and truncate at 1280x720 ·
D-168 S2 the far eye is a lidless white almond at `face` ·
D-171 S3 the arms never swing behind the torso in the sprint.
(D-026 and D-084 updated with new evidence rather than renumbered.)

## RE-SCORE OF `docs/design/taste.md` §4 (the DNA scorecard, was 21/60 at `0f2c2de`)
Scored against `d499c08`. A row moves only with evidence; five rows do not move.

| # | Property | 21/60 | NEW | Justification (one line) |
|---|---|---|---|---|
| 1 | Landmark navigation | 1 | **2** | Tall Tom, the Lone Spur, Teatro Estrella's blade, the Boone pylon and the Harvest monument are each nameable from one plate; the five-spawn test is still undone, so not 3. |
| 2 | District legibility | 1 | **2** | Cedar Cliff, the fairgrounds, Harvest Hills, downtown and the floodway are distinct at street level in the sweeps; the Cliff's mid-distance read is still colour blocks (D-166). |
| 3 | Ring-road flow | 1 | **1** | No evidence moved; D-059's dead ends are still open in the ledger. |
| 4 | Greatest-hits compression | 1 | **1** | Two new districts, still zero locals asked. |
| 5 | Map editorializes | 1 | **2** | The pause map carries 8 districts and 11 places, and the world's copy has an opinion ("96 MONTHS, $0 DOWN — YOUR SIGNATURE IS YOUR CREDIT"); the 60-second drive is still uncounted. |
| 6 | Diegetic tutorials | 1 | **1** | The session menu's job text is still non-diegetic, and the in-flight D-072 edit makes it longer. |
| 7 | Prep -> execute | 0 | **1** | Boone Trucks is prep you buy before the job and the Paper is a choice made before the haul; no score has open-world prep, so 1, not 2. |
| 8 | Approach freedom | 1 | **2** | An order can be hooked, chased, boxed in, or walked away from, and bad paper can be taken or voided — two axes with numbers on both (stage11, stage14). |
| 9 | Cheap retry | 1 | **2** | Busted returns you to the impound lot with your truck and a $150/star fine (stage4); orders re-push continuously. |
| 10 | Fail-forward | 1 | **2** | Busted keeps the fleet and clears heat; a voided bad-paper order still pays respect +3; a lost flee closes cleanly. |
| 11 | Legible heat | 1 | **2** | `add_heat(n, reason)`, 16 named call sites, the reason under WANTED for 2.6 s, and a second evasion outcome (stage1 3/3, stage4 6/6). |
| 12 | Systems interlock | 2 | **2** | The chain is deeper (order -> reaction -> `traffic.adopt` -> hook -> impound -> police -> favor -> bail) but no 30-minute session has been logged, which is what a 3 costs. |
| 13 | Emergent clips | 1 | **1** | Still no logged session. |
| 14 | World memory | 0 | **2** | `save_load.gd` persists rank, deliveries, paper taken/burned, quota, favors and the dealer's notes; a towed stranger's favor covers a later bail (stage5). |
| 15 | Economy metronome | 1 | **2** | Boone on a note, a daily draft, repossession after two misses, five ranks with a payout multiplier (stage12 8/8). |
| 16 | Satire thesis | 1 | **2** | LONGHORN speaks in Bolo Capital's push voice and the liability line is the thesis in the mechanic's own words. |
| 17 | Playable satire | 1 | **2** | The Paper is satire with a number on it — take it or void it, respect either way — alongside the drone. |
| 18 | Radio as worldbuilding | 1 | **1** | No evidence this cycle. |
| 19 | Side-content taxonomy | 1 | **2** | Endless orders, the night board, STRANDED, Comin' Down, the dealership; hobbies and character quests still absent. |
| 20 | Flat difficulty, deep mastery | 1 | **2** | The Full Eight (stage3 11/11) plus melee's perfect block and counter, and medals on cards. |

**NEW SUM: 34 / 60** (was 21). The zeros are gone. The cheapest remaining rows are 6 (diegetic
tutorials — the session text is the last non-diegetic surface) and 13/12 (both need one logged
30-minute session, which costs a playtest, not a build).

## RUNS I COULD NOT MAKE (exact command + the assertion that decides it)
1. `cd game && /Applications/Godot.app/Contents/MacOS/Godot -- --shot --shot-debug=normals` —
   at `face`, plate pixel (880,640) must satisfy B > R+40. Closes the last doubt on D-107.
2. `cd game && /Applications/Godot.app/Contents/MacOS/Godot -- --script res://tools/character_review.gd -- --out=/abs/dir`
   — the `collar`, `collar_normals` and `hand` views. Decides D-108, D-114, D-131.
3. `cd game && /Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tools/skin_rim.gd`
   — assert every shell's max proud <= 5 mm on the post-D-067 garments. Decides D-113.
4. `cd game && /Applications/Godot.app/Contents/MacOS/Godot -- --hudshot` with the phone open on a
   bad-paper order — is the red tell legible at 720p, does the note column overflow. Decides D-148.
5. `cd game && tools/gate.sh --full` on a machine with load average < 2
   (`ps -Ao %cpu,comm | sort -rn | head` first) — 10/10 stations under 16.67 ms. Decides D-100.
6. A probe stage for D-125 (2 stars, ped at 10 m, assert FLEE within 1 s) and for D-133's honk
   (block a traffic car 2.4 s, assert its horn stream is playing).
7. A night `takeover` vantage in the Slab — decides whether D-152's bulbs exist at all.

## SUMMARY FOR THE PRODUCER
- **Counts:** S1 1 · S2 35 · S3 53 · S4 10 · **99 open** (44 in this cycle's scope, 55 carried
  from cycle 3 and not re-verified — a read-only cycle cannot close what it cannot measure).
  **25 FIXED, verified.** The nine rounds were not wasted: every S1 in scope (D-107, D-138,
  D-143, D-150) is genuinely dead, and D-142's S1 downgraded to S2.
- **The three that hurt most now:** D-154 + D-153 (five HUD elements at once; the contract card
  is a full-width veil over live play that hides the target it is sending you to) · D-129 + D-157
  + D-102 (the crowd is five copies of one neckless man standing at attention, and the takeover's
  "club" is a row of ambient walkers) · D-156 + D-142 (there is an open hole through the shirt at
  the armpit, at the `torso` vantage).
- **Ledger written:** `/Users/miladfarazian/Documents/Projects/gta_clone/docs/qa/defects.md`.
- **Process:** D-084 recurred — four game files were dirty in the working tree during this audit,
  and round 16's own plates were rendered by a build `d499c08` no longer contains.
