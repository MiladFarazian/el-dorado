# DEFECT LEDGER

Single source of truth for what is wrong with EL DORADO GRANDE right now.
Owned and rewritten by the **QA Director** each cycle. Fix order is S1 → S2 → S3.
Bar: `docs/qa/quality-bar.md`.

**Cycle:** 7 — the ruling cycle on waves D-056…D-071. **2026-09-18.**

## HOW THIS CYCLE WAS RUN, AND WHAT THAT COSTS THE RULINGS

**Read-only.** The producer held the gate, so QA started **no Godot process**: no boot, no
sweep, no `parse_all`, no probe. Every ruling below is made from (a) the probe logs and gate
tables the rounds filed, (b) the plates they filed, read at judgement crops with a pixel
analyser, and (c) the source at HEAD. Where a ruling needs a run QA could not make, it says
**PLAUSIBLE-UNVERIFIED** and names the exact command and assertion. **No claim was upgraded to
FIXED on a builder's word.**

**Build audited: `d499c08` — "Round 16b (D-071): one objective line on screen", 19:32.**

**D-084 HAPPENED AGAIN.** At audit time `git status` showed uncommitted edits to
`game/scripts/systems/repo_orders.gd`, `save_load.gd`, `session.gd` and
`game/data/mechanics/repo_orders.json` — the D-072 NEW GAME work — landing while this audit
ran. A fix cycle and a QA cycle overlapped for the third recorded time. Rulings are against
committed HEAD, not the dirty tree, and any claim that lands in those four files after
19:32 is **not** covered here. See D-084.

**A second, quieter version of the same problem:** the plates filed as round 16's evidence
were rendered by a build that HEAD no longer contains — `order_push.png` shows
`LONGHORN DISPATCH RE-ARM 22s`, a string `d499c08` deleted. **Evidence older than the commit it
is filed under cannot close a defect**, and two of this cycle's rulings had to be softened for it.

---

## COUNTS

| Severity | Open | Note |
|---|---|---|
| **S1 BLOCKER** | 1 | D-100 only — and only because no quiet-machine perf run has happened since the budget tier shipped |
| **S2 MAJOR** | 35 | 17 ruled/filed this cycle + 18 carried from cycle 3, unverified |
| **S3 MINOR** | 53 | 21 ruled/filed this cycle + 32 carried, unverified |
| **S4 POLISH** | 10 | 5 + 5 carried |
| **Total open** | **99** | 44 in this cycle's scope + 55 carried |
| FIXED (verified this cycle) | 25 | listed below, deleted next cycle |
| WONTFIX / RULED / NOT REPRODUCED | 4 | D-012, D-022, D-071, D-106 |

By area (this cycle's 44): characters 16, feel/HUD 12, world 8, ci/measurement 7, vehicles 1.

**Gates (as filed by the rounds, not re-run by QA).** `round16/gate_quick.md`: parse 95/95,
lint 0, `--smoke` ×2 byte-identical on the D-059 baseline line, boot 900 `ERROR=0 WARN=0`,
`SESSION TEST: PASS (0 failures)`. **Perf: not run — `machine LOADED load=5.22`.** Every gate
since round 13 has refused perf under load (5.22 / 5.6 / 7.98). §4b has therefore been
un-adjudicated for nine rounds.

---

## THE THREE DEFECTS MOST HURTING THE GAME RIGHT NOW

**1 · D-154 + D-153 — the HUD has no traffic controller, and it is the first thing a player
sees.** In the two plates the producer filed to prove the loop works
(`round16/plates/order_push.png`, `order_debtor.png`) there are **five text elements on screen
at once**: a finished mission's contract card, a green EVADED banner, repo_board's gold respect
flash, the LONGHORN app panel, and **two mission objective labels overprinting each other
character-for-character**. The card is an 1800×190 78 %-alpha band across the full width of the
frame that runs for 6 s of live driving — in `order_debtor.png` it hides the target vehicle the
objective is sending the player to. Milad does not need a crop to see this one.

**2 · D-129 + D-157 + D-102 — the crowd is still five copies of one man standing at
attention.** `loop-sept18/plates/showcase_people.png`: five pedestrians, one pose — feet
together, arms straight down, no weight shift, no head turn, one body, and **no neck on any of
them**. `round16/plates/takeover.png`: the "club" that was supposed to come out for the takeover
is a row of ambient walkers crossing an empty daylight lot, evenly spaced, same stride phase,
none of them looking at the Slab. The animation work landed on the *player*; the crowd never got
it, and the crowd is what fills the frame.

**3 · D-156 + D-142 — the shirt has a hole in it.** At the `torso` vantage
(`cloth-sept13/after/torso.png`, crop x310-420/y270-400 at 5×) there is a lens-shaped **void
between the sleeve and the body panel at the armpit** that you see straight through into the
garment's dark interior, with a ragged marching-cubes stair along its cut. The cloth pass
turned paint into volume — a genuine S1 kill — and left an open hole at the one joint the
`torso` vantage exists to photograph.

Runner-up: **D-100**, unresolved for nine rounds because nobody has had a quiet machine.

---

# S1 — BLOCKER

### D-100  [S1]  The shipped light pipeline has not been adjudicated against §4b since the budget tier landed
- **Area:** performance / ci
- **Evidence:** the budget tier's own 10/10 pass is a wave-6 producer measurement. Every gate
  since: `round13/gate_quick.md` `LOADED load=7.98`, `round14` `5.22`, `round16` `LOADED
  load=5.22, top 33.3% Virtualization.framework`. `gate.sh --full` refuses perf under load and
  has refused it nine rounds running.
- **Bar violated:** §4b "≥ 60 fps at every station, best of ≥ 3, **on an otherwise quiet machine**".
- **Suspected cause:** not a code defect — a process one. The machine is never quiet.
- **Run that decides it:** `ps -Ao %cpu,comm | sort -rn | head` (load < 2), then
  `cd game && tools/gate.sh --full`; assert 10/10 stations < 16.67 ms at `best`.
- **Status:** OPEN (PLAUSIBLE-UNVERIFIED — QA may not start a Godot process this cycle)

---

# S2 — MAJOR (ruled or filed this cycle)

### D-153  [S2]  The contract card is a full-width opaque band over live play, and it hides the objective it just replaced
- **Area:** feel
- **Evidence:** `docs/qa/evidence/loop-sept18/round16/plates/order_debtor.png` — the COMIN' DOWN
  card is up while the player drives a live order; its veil (`mission_kit.gd:_build`,
  `offset_left = -900 … offset_right = 900`, `C_CARD = Color(0.03,0.03,0.04,0.78)`, `CARD_H 190`)
  covers the middle of the frame full-width and **the dark-red target vehicle is behind it**.
  Same veil in `order_push.png`, where it blanks two thirds of the world. Default life 6.0 s,
  not skippable, no input dismisses it.
- **Bar violated:** §4 "every verb has feedback" is satisfied; §4 "no dead ends" / §4 "the HUD
  never lies" is not — the HUD is telling the player to drive to a target it is covering.
- **Suspected cause:** `game/scripts/systems/mission_kit.gd`, `card()` + `_build()` — a centred
  `ColorRect` 1800 px wide with no gameplay-aware placement and no dismiss.
- **Status:** OPEN

### D-154  [S2]  Five HUD elements can be on screen at once, with nothing arbitrating between them
- **Area:** feel
- **Evidence:** `round16/plates/order_push.png` — simultaneously: the mission card (layer 16),
  the police EVADED banner (`police.gd:151`), repo_board's flash "GAVE THEM THE WEEK RESPECT +1"
  (`repo_board.gd:319`), the LONGHORN app panel bottom-right (`mission_kit` layer 16), and two
  overprinted mission objective labels. Five owners, five layers, zero coordination.
- **Bar violated:** §4 "The HUD never lies" (an unreadable HUD cannot report anything) and §1's
  spirit — a judgement plate that cannot be read.
- **Suspected cause:** every system stands up its own `CanvasLayer` and its own label; there is
  no HUD manager. Owners: `mission_kit.gd`, `police.gd`, `repo_board.gd`, `slab_cruise.gd`,
  `hud_gta.gd`, three `mission_*.gd`.
- **Status:** OPEN

### D-156  [S2]  There is an open hole through the shirt at the armpit
- **Area:** characters
- **Evidence:** `docs/qa/evidence/cloth-sept13/after/torso.png`, crop x310–420 / y270–400 at 5×
  (scratchpad `t_armhole.png`): a lens-shaped void ≈10×40 px in a 960-wide plate between the
  sleeve and the body panel, showing the garment's unlit interior, with a ragged stair along the
  cut edge. The builder filed this as "the armhole is a straight seam"; at the `torso` vantage it
  is not a seam, it is a hole.
- **Bar violated:** §1 "Surface intersections — no z-fight stipple, no visible seam where two
  masses cross"; §3 "No floating geometry — nothing intersects or hovers visibly".
- **Suspected cause:** `game/scripts/world/skinned_character.gd` — the garment shell's armhole
  cut; the sleeve and the trunk piece close their cuts with walls that do not meet.
- **Status:** OPEN

### D-157  [S2]  The takeover's "club" is a row of identically-posed ambient walkers on an empty lot
- **Area:** characters / feel
- **Evidence:** `round16/plates/takeover.png`, crop x80–700 / y270–400 (scratchpad
  `tk_crowd.png`): five of the fourteen are visible, spaced ≈8 m apart on a straight line, **all
  in the same walking pose at the same stride phase**, none facing the Slab, none near a car, no
  bulbs. The probe row that certified it asserts only a count
  (`stage10 the club came out: 14 on the lot (want >= 6)`). The plate is also **daylight**, so
  D-152's claimed bulbs are untested at the vantage the claim names.
- **Bar violated:** §1 "Crowd variety — no two adjacent peds read as the same person".
- **Suspected cause:** `game/scripts/systems/mission_comin_down.gd` spawns crowd members through
  `pedestrians.gd`'s ordinary walker and gives them no gathering behaviour or pose set.
- **Status:** OPEN

### D-168  [S2]  The far eye is a lidless white almond sitting on the silhouette of the head
- **Area:** characters
- **Evidence:** `cloth-sept13/plates/face.png`, crop x520–700 / y180–340 at 4× (scratchpad
  `f_midface.png`): the near eye is correct — lid, lash line, iris, limbal ring, catchlight. The
  far eye, at the head's silhouette edge, is a bare pale almond with a grey iris and **no upper
  lid, no socket, no brow shadow** — it reads as an eye painted on the side of the skull.
- **Bar violated:** §1 "Mid-face at 4× zoom reads as a face, not a snout"; this is the surviving
  half of D-030 ("the two eyes disagree with perspective").
- **Suspected cause:** `game/scripts/world/character_factory.gd` — the eye is built as two layers
  (sclera + iris under a lid) at a fixed local orientation; at grazing angle the lid geometry no
  longer covers the sclera.
- **Status:** OPEN

### D-108  [S2]  There is still no collar — the shirt has a placket and two pockets and a plain crew neckline
- **Area:** characters
- **Evidence:** `cloth-sept13/after/torso.png` and `cloth-sept13/plates/face.png`: the neckline is
  a smooth crew curve; no stand, no leaf, no fold-over points, nothing at all, on a garment that
  carries a visible placket with four buttons and two chest pockets. **No `collar` review plate
  has ever been filed** — the D-108 update says "QA to rule at the new `collar` review view" and
  that view's output is not in `docs/qa/evidence/`.
- **Bar violated:** §1 silhouette at 1 m from `face`/`torso`.
- **Suspected cause:** `skinned_character.gd` `_tailored_piece` / the garment catalogue — either
  the collar piece is not emitted for this archetype, or it is emitted inside the body field.
- **Run that decides it:** `cd game && /Applications/Godot.app/Contents/MacOS/Godot --script res://tools/character_review.gd -- --out=/abs/dir`, the `collar` and `collar_normals` views.
- **Status:** OPEN

### D-129  [S2]  The crowd stands in one pose — the living idle landed on the player only
- **Area:** characters
- **Evidence:** `docs/qa/evidence/loop-sept18/plates/showcase_people.png` (round 13, the newest
  in-game crowd plate): five pedestrians, **feet together, arms straight down at the sides, head
  level, identical in all five** — no weight shift, no head turn, no idle breath, and the same
  body under different shirts. This is D-047 with the arms lowered.
- **Bar violated:** §1 "Crowd variety — no two adjacent peds read as the same person".
- **Suspected cause:** `character_factory.animate()`'s idle is driven for the player actor;
  `pedestrians.gd` walkers at rest hold a static pose.
- **Status:** OPEN (the *player's* gait is FIXED — see D-138)

### D-134  [S2]  The body has a rib cage now, but the shoulders miss the bar and the legs are one mass to mid-thigh
- **Area:** characters
- **Evidence:** `gait-sept13/measure_after.txt` — the taper is real (rib trunk 0.324 → waist
  0.288, lats, pecs, lumbar). Three things are not: **shoulders (deltoid line) x-span 0.468 m at
  nominal**, 12 mm under the bar's 0.48 floor (see D-163); **crotch 0.840 → mid-thigh 0.650 is a
  single 0.360-wide mass** (`masses: 1: 0.360` at both 0.840 and 0.760), which under a 10 mm
  garment shell is why `cloth-sept13/after/full.png` reads as a skirt from the front; and
  `showcase_people.png` gives five people one body.
- **Bar violated:** §1 "Chest width incl. arms 0.48–0.56 m at nominal".
- **Suspected cause:** `skinned_character.gd` `_prims` — the thigh capsules and the deltoid line.
- **Status:** OPEN (PARTIAL — moved a long way, does not meet the bar)

### D-139  [S2]  The A-frame is fixed; the shoulder and the armpit are not
- **Area:** characters
- **Evidence:** `measure_after.txt`: knee 0.108 each, knee outer span 0.252 (was ≈0.34), ankles
  under the knees — the A-frame is gone and measured. The deltoid is still 0.468 (D-163) and the
  "armpit renders as a one-cell slot" the builder filed against itself is now an actual
  through-hole in the garment (D-156).
- **Bar violated:** §1 chest width; §1 surface intersections.
- **Status:** OPEN (PARTIAL)

### D-142  [S2]  The clothes are volume now, but the sleeve is a leg-of-mutton and the trousers are a column
- **Area:** characters
- **Evidence:** `cloth-sept13/after/torso.png`: the sleeve's diameter at the bicep is ≈130 px
  against a 190 px body panel — two thirds of the whole chest — and it hangs past the belt line
  while the shirt hem stops above it. `after/full.png`: the two trouser legs read as one navy
  bell from waist to mid-calf. Plus the armhole hole (D-156).
- **Bar violated:** §1 silhouette at `torso` / `full`.
- **Suspected cause:** `skinned_character.gd`, the sleeve and trouser shell radii (constant
  10 mm offset applied to an already-thick arm field).
- **Status:** OPEN — **downgraded from S1**: the "paint on skin" S1 is genuinely dead.

### D-140  [S2]  The map draws the world now — and its labels collide and truncate at the shipped window size
- **Area:** world
- **Evidence:** `loop-sept18/plates/map.png` at 1280×720 (the project default):
  `HARVEST HILLS™STONEBRIDLE RANCH` runs together with no gap; `OVERFLOW CAMPUS` is overprinted
  by marker 2 **and** the player arrow; `Cattleman's Trust Tow…`, `Iglesia Baut…` truncate at the
  district box edge; `Gilead Bottoms` collides with `Teatro Estrella`. Of 15 declared roads, four
  are legible as lines. The structural claim (8 districts, 11 places, a session-derived legend,
  a 500 m bar) is met.
- **Bar violated:** §3 "Landmark legibility — each district has ≥1 structure nameable from a
  screenshot"; the map is the wayfinding instrument and it is not readable.
- **Suspected cause:** `game/scripts/ui/city_map.gd` — labels are drawn at their place's position
  with no collision resolution and no clipping policy. See also D-167.
- **Status:** OPEN (PARTIAL)

### D-151  [S2]  The loop's eleven audio cues are proven to exist, not to fire
- **Area:** feel / audio
- **Evidence:** the only probe rows are `stage11 loop_audio carries 11 cues (want >= 11)` and
  `loop_audio plays the delivered cue on demand`. Neither touches a loop signal. Nothing in the
  evidence shows a cue firing at a push, a delivery, a draft or bad paper, and a log cannot
  answer "by ear".
- **Bar violated:** §4 "Every verb has feedback — sound + visual + camera response on every action".
- **Run that decides it:** a probe row per signal — fire `repo_orders.pushed` / `delivered` /
  `dealer.drafted` / `paper_bad`, assert the matching `AudioStreamPlayer` is playing within 0.3 s.
- **Status:** OPEN (PLAUSIBLE-UNVERIFIED)

### D-152  [S2]  The takeover has a count, not a scene
- **Area:** feel / world
- **Evidence:** see D-157. `stage10 the club came out: 14 on the lot (want >= 6)` passes; the
  plate shows nobody gathered, nobody looking at the car, and no bulbs (daylight).
- **Status:** OPEN (PARTIAL)

### D-148  [S2]  The phone works; nobody has ever photographed it
- **Area:** feel
- **Evidence:** mechanism proven — `stage11 the phone opens on the order (351 chars)`,
  `the phone closes after three tabs`, `phone.gd:32-36` three tabs. **No phone plate exists in
  `docs/qa/evidence/`**, so the two questions the defect actually asks — is the red tell legible
  at 720p, does the note list overflow the column — are untested.
- **Run that decides it:** `cd game && /Applications/Godot.app/Contents/MacOS/Godot -- --hudshot`
  with the phone open on a bad-paper order.
- **Status:** OPEN (PLAUSIBLE-UNVERIFIED on legibility; mechanism FIXED)

### D-128  [S2]  Parked cars hold on flat ground; the slope is still untested
- **Area:** vehicles
- **Evidence:** `stage0 parked wrecker drift over 8 s: 0.000 m` in rounds 14, 15 and 16
  (before: `drift_before.log` 3.270 m). The probe parks on flat asphalt. Milad's report was
  "all cars drift forward"; the frontage grade is where a park hold fails.
- **Run that decides it:** the same 8 s hold with the wrecker parked on the frontage slope;
  assert < 0.02 m.
- **Status:** OPEN (PARTIAL — the flat case is genuinely FIXED)

### D-141  [S2]  The two new edge districts are built and empty
- **Area:** world
- **Evidence:** the build is real — `TALL TOM: 17 m tall at (868.0, 1.35, 258.0)`,
  `world-sept13/plates/{fair_gate,tall_tom,fair_wheel_night,harvest_edge}.png`. Neither Fair Drive
  nor Pioneer Vision Parkway carries traffic; the spur work (D-146) covered Juárez and the Cliff.
- **Status:** OPEN (PARTIAL — the prairie claim is FIXED, the emptiness is not)

### D-101  [S2]  (reworded) The factory body's swept shoulder girdle is still the "pillow shoulders" — but it is no longer the default
- **Area:** characters
- **Evidence:** `character_factory.gd:571-586` unchanged; reachable only via `--factory` since
  D-050. It remains a comparison arm, not a shipped surface.
- **Status:** OPEN (no longer player-facing; close it when `--factory` is retired)

---

# S3 — MINOR (ruled or filed this cycle)

### D-155  [S3]  Two missions' objective labels claim the identical HUD slot, with no arbiter
- **Area:** feel
- **Evidence:** `mission_hook_and_ladder.gd:471` and `mission_comin_down.gd:294` are byte-identical
  placements: `PRESET_CENTER_BOTTOM, offset_left -420, offset_right 420, offset_top -240,
  offset_bottom -210`. `round16/plates/order_push.png` shows both drawing at once: colour
  separation of the crop (scratchpad `c2.png` / `sep_pink.png`) resolves cream (242,237,219 =
  H&L's `Color(0.95,0.92,0.8)`) reading `LONGHORN DISPATCH RE-ARM 22s` over pink (229,147,206 =
  Comin' Down's `CANDY.lightened(0.35)` = 232,149,209). `d499c08` blanked both COMPLETE strings;
  **the shared slot is untouched**, so any two missions RUNNING together reproduce it.
- **Bar violated:** §4 "The HUD never lies".
- **Suspected cause:** as cited — two files, one hard-coded slot, no owner. `hud_gta.gd:358-362`
  already solves this for its own line by yielding; the missions do not yield to each other.
- **Status:** OPEN

### D-160  [S3]  The combat reticle is baked into every plate in the judgement sweep
- **Area:** ci / measurement
- **Evidence:** a 2×3 pure-white block at (599–600, 336–338) — exact screen centre of a
  1200×675 plate — in **5 of 5** plates tested (`showcase_people`, `face`, `cliff_boulevard`,
  `boone_lot`, `gilead_bottoms`), plus a 5×1 dash at (719–723, 337) = the spread ring at r≈119 px.
  At the `face` vantage it lands on the subject's chest.
- **Bar violated:** the bar's first law — a plate is the instrument; a constant artefact in the
  instrument corrupts every §1/§3 judgement and every `plates_diff.py` comparison.
- **Suspected cause:** `combat.gd:1236-1239` builds `_dot` (a 4×4 white `ColorRect`) and `_cross`;
  `zz_shot.gd:200-205` hides `CanvasLayer`s only at root depth 1 and 2, and combat's is deeper.
  **`zz_shot.gd` is the producer's file — QA reports, does not edit.**
- **Status:** OPEN

### D-162  [S3]  Bar §1's head-height row has gone unmeasured for nine rounds — the tool has no head
- **Area:** characters / measurement
- **Evidence:** `game/tools/body_measure.gd:10-14` — the row list runs
  `shoulders (deltoid line) 1.425` down to `wrist 0.930`. **There is no crown row, no chin row and
  no total-height row.** The head is the factory's rigid head, outside the body field, so the tool
  cannot see it. A silhouette measure off `cloth-sept13/after/full.png` (subject rows 51–506,
  chin ≈131, crown hidden by the hat) puts the ratio at **6.6–7.0 heads**, i.e. at or below the
  bar's floor — but that estimate is not a measurement and must not be quoted as one.
- **Bar violated:** §1 "Head height = total height ÷ 7.0–7.8 (hat excluded)".
- **Suspected cause:** `game/tools/body_measure.gd`.
- **Status:** OPEN

### D-163  [S3]  Shoulders measure 0.468 m at nominal — 12 mm under the bar floor — and the bar row does not say which height it grades
- **Area:** characters / bar integrity
- **Evidence:** `gait-sept13/measure_after.txt`: `shoulders (deltoid line) 0.468`,
  `upper chest 0.468`, `chest (nipple line) 0.504`, and the widest span at any height is `0.540`
  (waist/hips/wrist, because the hands splay). Bar §1 says "Chest width incl. arms 0.48–0.56 m at
  NOMINAL". Graded at the deltoid line it **fails by 12 mm**; graded at the nipple line or at the
  widest span it passes. D-134, D-139 and D-061 all quote 0.468 as if it were a pass.
- **Bar violated:** §1 "Chest width incl. arms" — indeterminately, which is itself the defect.
- **Ask of the producer:** pin the row the way the Ø:H denominator and the sill reference were
  pinned (bar amendment log, 2026-08-10). QA's reading is bideltoid breadth = the deltoid line;
  on that reading the body fails and D-134/D-139 stay open on this number alone.
- **Status:** OPEN

### D-164  [S3]  A probe row names "base × 1.5" and asserts something that cannot fail for it
- **Area:** ci
- **Evidence:** `game/scripts/systems/zz_mech_probe.gd:942` —
  `_say(dm >= 450, "stage14 DELIVERED after the run: +$%d (want >= 450: base x 1.5)" % dm)`.
  `repo_orders.gd:47` `BASE_PAY := {"sedan": 300, "pickup": 450}`; a pickup delivered **without**
  the run bonus pays `450 × 1.5 (distance) × 1.0 = $675`, which passes `>= 450`. The two filed
  runs differ ($1013 for a Brisket, $675 for a Vantage) and both pass, so the row cannot
  distinguish a working bonus from a missing one.
- **Bar violated:** §5's spirit — a gate that cannot fail is not a gate.
- **Suspected cause:** as cited. The correct assertion is
  `dm == round(BASE_PAY[cls] * dist_bonus * rank_mult * flee_bonus)`, or at minimum
  `dm >= 1.4 × the same order delivered unfled`.
- **Status:** OPEN

### D-165  [S3]  `Lambda capture at index 0 was freed` inside the flee stage
- **Area:** ci / feel
- **Evidence:** `round16/mech_probe_windowed.log:111`, between
  `stage14 the app pushed an order that will run` and `stage14 FLEEING` —
  `ERROR: Lambda capture at index 0 was freed. Passed "null" instead.
  at: call (modules/gdscript/gdscript_lambda_callable.cpp:110)`.
  The headless run of the same stage is clean, so it is timing-dependent. **The §5 boot gate
  cannot see it** — the gate never pushes an order, which is the same blind spot D-121 had.
- **Bar violated:** §5 "zero error lines".
- **Suspected cause:** a lambda in the flee path capturing the debtor or the car and outliving it
  — `repo_orders.gd` around `_flee_start` / `traffic.adopt`, or `traffic.gd`'s adopt callback.
- **Status:** OPEN

### D-158  [S3]  Boone Trucks is a truck dealership with no trucks on the lot
- **Area:** world
- **Evidence:** `loop-sept18/plates/boone_lot.png` — the sales apron is bare asphalt from the
  kerb to the showroom; the pennant string, two signs and a showroom are there and **not one
  vehicle**. The probe says `stage12 Boone Trucks stocks 3 rigs`: the stock exists in data only.
- **Bar violated:** §3 "Landmark legibility" / the promise-of-interactivity read — the one place
  in the game whose whole purpose is vehicles shows none.
- **Suspected cause:** `game/scripts/systems/dealer.gd` — stock is a data list; no display
  vehicles are spawned on the lot.
- **Status:** OPEN

### D-159  [S3]  The Boone pylon sign's own frame member splits every line of its text
- **Area:** world
- **Evidence:** `loop-sept18/plates/boone_lot.png`, crop x965–1105 / y175–320 at 5×
  (scratchpad `bl_sign.png`): a red frame column runs down the **middle of the sign face**,
  eating a character-wide slice out of all four lines — `BOONE|TRUCKS`, `APPREC|TE YOU!`,
  `96 MONT|0 DO`, `- YOUR SIGNAT|S YOU|EDIT`. A streetlight mast also cuts the bottom-right corner.
- **Bar violated:** §3 "Landmark legibility — nameable from a screenshot".
- **Suspected cause:** `dealer.gd` / `sign_kit.gd` — the text is laid across a two-panel sign as
  one string, so the frame between the panels lands inside the glyph run.
- **Status:** OPEN

### D-161  [S3]  A downed pedestrian lies interpenetrated by a knocked-over fire hydrant
- **Area:** world / characters
- **Evidence:** `round16/plates/takeover.png`, crop x880–1080 / y300–420 at 4× (scratchpad
  `tk_down.png`): a prone pedestrian on the asphalt with a bright red hydrant passing **through**
  his torso at an angle, the jet running. Nothing in the takeover script knocks anybody down, so
  this is ambient traffic hitting a ped and a hydrant on the shared kerb.
- **Bar violated:** §3 "No floating geometry — nothing intersects or hovers visibly".
- **Suspected cause:** unknown — needs a repro. Candidates: `pedestrians.gd`'s downed state has
  no collision against props, or `interactables.gd`'s knocked hydrant keeps its collider where
  the ped body already is.
- **Status:** OPEN

### D-026 update  [S3]  The hydrant jet is worse than "a column of cards" — it is a 20 m stack of unshaded white quads
- **Area:** world
- **Evidence (new, this cycle):** `round16/plates/takeover.png`, crop x930–1060 / y140–330 at 4×
  (scratchpad `tk_jet.png`): individually rectangular, hard-edged, unlit white quads scattered
  from the hydrant to **third-storey height of the building behind**, with no falloff, no
  softening and no arc. Re-photographed from an ordinary gameplay vantage, not a hunting crop.
- **Status:** OPEN (the original D-026 entry is carried below; this is its current evidence)

### D-166  [S3]  Cedar Cliff's mid-distance signage reads as blank saturated colour blocks over the carriageway
- **Area:** world
- **Evidence:** `loop-sept18/plates/cliff_boulevard.png`, crop x420–700 / y300–400 at 4×
  (scratchpad `cc_awn.png`): a row of flat single-colour rectangles (maroon, brown, purple,
  green, navy) on thin poles, **no glyphs on any of them**, threaded on a black horizontal member
  that spans the full frame; two of them read as standing over the roadway rather than over a
  storefront. Near-field signage in the same plate (`MERCADO REYES`, `TEATRO · ESTRELLA`) reads
  correctly, so this is a distance behaviour.
- **Bar violated:** §3 "No floating geometry"; §3 "Street furniture density" (a cue every ≤30 m
  that carries no information is not a cue).
- **Suspected cause:** unknown — `cedar_cliff.gd` `_awning_xf`/`_awning_col` (flat coloured
  awnings) or `SIGN.FASCIA` panels whose glyph texture has mipped away. **Do not guess: this needs
  the boulevard driven windowed to separate the two.**
- **Run that decides it:** a windowed plate from the boulevard at 60 m and at 20 m from the same
  panel; if the glyphs appear at 20 m it is mip/LOD, if not it is geometry.
- **Status:** OPEN

### D-167  [S3]  The pause map's place and district labels collide and truncate at 1280×720
- **Area:** world / ui
- **Evidence:** see D-140's list, from `loop-sept18/plates/map.png`.
- **Suspected cause:** `game/scripts/ui/city_map.gd` — no label collision pass, no leader lines,
  no per-zoom label budget.
- **Status:** OPEN

### D-171  [S3]  In a full sprint stride the arms never swing behind the torso
- **Area:** characters
- **Evidence:** `gait-sept13/after/sprint_side.png`, all 8 phase frames: both hands stay forward
  of the belt line in every frame; no frame drives an elbow back past the ribs. The rest of the
  run is right — measured crown oscillation 12 px on a 338 px figure = **6.2 cm of bounce**, legs
  split 60–70°, knee bent at landing.
- **Bar violated:** §4 "every verb has feedback" at the animation level; §1 silhouette from `side`.
- **Suspected cause:** `character_factory.animate()` — the arm swing's rearward amplitude, or an
  elbow-forward clamp left in from the walk.
- **Status:** OPEN

### D-117  [S3]  The surface beard is a hard-edged polygon with a rectangular seam inside it
- **Area:** characters
- **Evidence:** `cloth-sept13/plates/face.png`, the left pedestrian, crop x0–110 / y230–360 at 5×
  (scratchpad `f_ped2.png`): the beard is a sharply-bounded dark quad from the ear down the
  jawline to the chin with a **straight diagonal boundary across the cheek**, and a lighter
  rectangular sub-panel with a dotted seam visible inside it; the moustache is a separate pale
  sliver that does not join it. The 22 % feather is in the source
  (`character_factory.gd:1515` `minf(minf(u,1-u)*4.5, minf(v,1-v)*4.5)`) and not in the render.
- **Bar violated:** §1 "Mid-face at 4× reads as a face".
- **Suspected cause:** `character_factory.gd:_beard_surface` — the feather is applied to the
  displacement (`r += lerpf(-0.0006, 0.0010, feather)`) but the **colour** boundary is not
  feathered with it, and the patch's own UV grid shows through as a seam.
- **Status:** OPEN

### D-102  [S3]  Nobody in this game has a neck
- **Area:** characters
- **Evidence:** `cloth-sept13/plates/face.png` (the hero: jaw runs into the shirt with ≈15 px of
  throat and no sternocleidomastoid), `after/torso.png` (same), and **all five** figures in
  `loop-sept18/plates/showcase_people.png`, where the head sits directly on the shoulder mass.
  The prim radii did grow (47/57 → 58/66 mm, D-045); the read did not change.
- **Bar violated:** §1 "Silhouette at 1 m reads as a person from `face`, `torso`".
- **Suspected cause:** the neck column's *length*, not its radius: the head's chin sits at
  roughly the clavicle. `skinned_character.gd` `_prims` neck segment + the factory head's mount
  height (`character_factory.gd`, `_build_head` at 1.445).
- **Status:** OPEN

### D-110  [S3]  Eye whites are calm now; the far eye is not (split)
- **Area:** characters
- **Evidence:** `character_factory.gd:74` `SCLERA := Color(0.74, 0.71, 0.68)` with the M24 note,
  emission down to 0.06; the near eye at 4× reads correctly. The remaining half is D-168.
- **Status:** OPEN (PARTIAL — near eye FIXED, far eye filed as D-168)

### D-111  [S3]  Skin has a surface; cloth does not
- **Area:** characters
- **Evidence:** boot census `SURFACES: materials=947 shaders=7 normalmapped=72 roughmapped=69`;
  pores read at 4× on `face.png` and the head/neck no longer change shading at the join — that
  half is done. `cloth-sept13/after/torso.png` is a **uniform matte panel**: no weave, no fold,
  no drape, no wear, one value across the whole chest.
- **Bar violated:** §1 "Surface intersections" / the `torso` read.
- **Suspected cause:** `city_shaders.PALETTE_SHADER`'s cloth micro-normal is keyed on the skinned
  body's UV2; the D-067 garment shells are new geometry and may not carry that UV2.
- **Status:** OPEN (PARTIAL)

### D-113  [S3]  The garment rim measurement describes garments that no longer exist
- **Area:** characters / measurement
- **Evidence:** the 26.6 mm belt and 27.9 mm apron vertices were measured before D-067 rebuilt
  every garment as a constant-offset shell. The number is stale, not wrong.
- **Run that decides it:** `cd game && /Applications/Godot.app/Contents/MacOS/Godot --headless --script res://tools/skin_rim.gd`; assert max proud ≤ 5 mm on every shell.
- **Status:** OPEN (PLAUSIBLE-UNVERIFIED)

### D-130  [S3]  The suburb road is still a clean plane
- **Area:** world
- **Evidence:** downtown and the frontage are FIXED — boot line
  `STREET WEAR: 390 lids, 280 drains, 790 patches, 3 draw calls`, lids visible in the asphalt of
  `boone_lot.png`. `street_wear.gd`'s zones do not cover the suburb.
- **Bar violated:** §3 "Street furniture density — a cue every ≤ 30 m".
- **Status:** OPEN (PARTIAL)

### D-131  [S3]  The resting hand has no current plate
- **Area:** characters
- **Evidence:** the newest `hand` plate is `mechanics-sept13/round5/hand_after.png`, three rounds
  and two cache versions before `character_hands.gd` and the garment shells. At `torso` the hand
  is a pale mitten below the cuff with no finger separation visible.
- **Run that decides it:** `character_review.gd -- --out=/abs/dir`, the `hand` view.
- **Status:** OPEN (PLAUSIBLE-UNVERIFIED) — supersedes the D-114 "paddle is gone" claim

### D-145  [S3]  Cedar Cliff is built; its mid-distance read is not
- **Area:** world
- **Evidence:** `CEDAR CLIFF: 45 houses, 14 storefronts, 31 labels` + `cliff_boulevard.png`.
  The prairie claim is FIXED. The remainder is D-166.
- **Status:** OPEN (PARTIAL)

### D-149  [S3]  Wade is not at the vantage a player arrives at
- **Area:** world
- **Evidence:** `round14/plates/boone_wade.png` exists; `loop-sept18/plates/boone_lot.png` — the
  plate taken at the lot's own vantage — contains no figure at all.
- **Run that decides it:** re-shoot `boone_lot` with Wade in frame, or move the greeting radius.
- **Status:** OPEN (PLAUSIBLE-UNVERIFIED)

### D-084 update  [S2→ carried]  A fix wave ran against the tree during this audit, for the third time
- **Area:** ci / process
- **Evidence:** `git status` at audit time: `M game/scripts/systems/repo_orders.gd`,
  `M save_load.gd`, `M session.gd`, `M game/data/mechanics/repo_orders.json` (the D-072 NEW GAME
  work) — uncommitted, during a declared QA window. Separately, round 16's filed plates were
  rendered by a build HEAD no longer contains (`LONGHORN DISPATCH RE-ARM 22s`, deleted in
  `d499c08`).
- **Bar violated:** the loop's own rule (CLAUDE.md, D-084): a fix cycle and a QA cycle may never
  overlap.
- **Status:** OPEN (process; the producer owns it)

---

# S4 — POLISH (ruled this cycle)

### D-114  [S4]  Fingertips at the body voxel — claim of resolution not photographed
- **Area:** characters · **Evidence:** `character_hands.gd` exists (3 mm field meshes on the
  forearm joints) but no post-cloth `hand` plate. · **Status:** OPEN (see D-131)

### D-116  [S4]  `skin_rim.gd` still cannot grade the tailored pieces
- **Area:** characters / measurement · **Evidence:** `game/tools/skin_rim.gd:84` still prints
  `TAILORED (explicit fabric mesh; not a shell, not graded here)`. No clearance measure for a
  fabric grid exists. · **Status:** OPEN

### D-125  [S4]  Pedestrians fleeing a wanted man is code with no witness
- **Area:** feel · **Evidence:** `pedestrians.gd:477` with `HOT_HEAT := 2; HOT_RADIUS := 12.0`
  (`:36`). No probe row, no plate. · **Run:** 2 stars, ped at 10 m, assert FLEE within 1 s. ·
  **Status:** OPEN (PLAUSIBLE-UNVERIFIED)

### D-133  [S4]  The brawler swings; traffic's horn is still unwitnessed
- **Area:** feel · **Evidence:** punch proven at `stage8` + `brawl.png`; `traffic._honk_check`
  has no probe row and no plate. · **Status:** OPEN (PARTIAL)

### D-105  [S4]  `race_event` can be left RUNNING forever on foot
- **Area:** feel · **Evidence:** none either way this cycle. · **Status:** OPEN (carried)

---

# FIXED — verified by QA this cycle, 2026-09-18. Delete after cycle 8.

Verified from the filed probe rows, boot census lines and source at `d499c08`, each cited in
`scratchpad/loop17/qa_findings.md`. **None was accepted on a builder's assertion.**

- **D-107 [S1] FIXED** — skinned bodies render right way out. `cloth-sept13/after/torso.png`:
  a correct light terminator across the sleeve, and the only unlit interior in the frame is seen
  *through* the armhole void — which is what an outward-facing one-sided mesh looks like.
- **D-109 [S3] FIXED** — `character_factory.gd:1574` `skinned_body` guard; no tube seam at `face`.
- **D-112 [S4] FIXED** — winding law corrected to `(c−a)×(b−a)` with D-107.
- **D-103 [S3] FIXED** — `foot_cops.gd:212-213` reads `police.search_center` while
  `search_active`; `police.gd:222-223` publishes it.
- **D-104 [S3] FIXED** — `downtown_types.gd:103` `DAY_E: [0.10, 0.10, 0.10, 1.05, 1.15]`;
  `facade_kit.gd:307-308` drives `set_night_level` in every arm.
- **D-025 [S2] FIXED** — boot census, every round: `RENDER: … shadow=450m/pcss0.53deg`.
- **D-118 [S3] FIXED** — stage1 3/3 (reason published, drawn under WANTED, cleared on evade).
- **D-119 [S2] FIXED** — stage4 6/6 across four rounds: card, lot 3.7 m, on foot, heat 0, $−150.
- **D-120 [S3] FIXED** — stage2 7/7: 6.50 → 1.50, 2 spots, private lamp material, horn on/off.
- **D-121 [S3] FIXED** — `vehicle_damage.gd:63-65` Variant-checks before the cast.
- **D-122 [S2] FIXED** — stage3 11/11 (0.35 / 0.55 / ×1.30 / chain / 8.0 s / 4 restores / 6 s).
- **D-123 [S3] FIXED** — stage4 `closest 5.2 m … cruiser speed 0.03`, heat 1 at the bust.
- **D-124 [S2] FIXED** — stage5 4/4 + stage6 4/4; persisted `save_load.gd:159/204`.
- **D-126 [S2] FIXED** — stage7: `-7.2 m` before, on the pad in 2.2 s after.
- **D-127 [S3] FIXED** — stage8 7/7 (jab, square-up, −6, −3, perfect 0, stagger, counter).
- **D-132 [S3] FIXED against the row** — bar §1 grades mid-face at 4×, and at 4× the vermilion,
  philtrum and nasolabial read (`f_midface.png`). At 1:1 the mouth is still a smear; the row is 4×.
- **D-135 [S3] FIXED** — `measure_after.txt` instep 0.085 / vamp 0.050 / sole 0.020, depth 0.288,
  span 0.216: shaft, vamp below instep height, welt. Visible in `after/full.png`.
- **D-136 [S2] FIXED (content)** — stage9 8/8: 2 lines, drone, owner out, card, $950 = 600+150+100+100.
- **D-055 update [S3] FIXED by construction** — `hud_gta.gd:460-468` draws D, N and the gold ring.
- **D-137 [S3] FIXED** — stage10 8/8 end to end.
- **D-138 [S1] FIXED** — `gait-sept13/after/sprint_side.png`: legs split 60–70°, heel to seat,
  bent-knee landing, elbows ≈90°, 6.2 cm measured bounce. (Arm rearward swing filed as D-171.)
- **D-143 [S1] FIXED (system)** — stage11 in three rounds, persisted `save_load.gd:163`.
- **D-144 [S2] FIXED (system)** — stage12 8/8; notes persisted `save_load.gd:173-176`.
- **D-146 [S2] FIXED** — stage13 `five spur routes qualified (5)`, `12 shells` after 40 s.
- **D-147 [S2] FIXED** — stage13 `the boulevard's sidewalks have people: 10`.
- **D-150 [S1] FIXED** — stage14 in rounds 15 and 16, headless and windowed (brain drives, 23 m in
  4.5 s, hooked on the move, ×1.5). The error line it threw is filed separately as D-165.
- **D-115 (session-flow half) FIXED** — `SESSION TEST: PASS (0 failures)` in three consecutive
  gates. The face-pass half stays open as D-117 and D-108.

### D-106  [RULED 2026-09-18 — §5 stays as written]  Audio-at-quit leak is 10 in windowed runs
The §5 row is defined on the **headless 900-frame boot**, and that boot measures 0–6. A bar row
is not widened to cover a measurement it does not take. If windowed leaks matter, add a row for
windowed runs and measure it; do not launder the headless row into covering them.

---

# CARRIED FORWARD — cycle 3's open ledger, NOT re-verified this cycle

**Read this before reading anything below.** These 60 entries were filed and measured by the
cycle-3 QA pass (2026-08-11). This cycle was read-only and scoped to D-107…D-152, so **not one
of them was re-measured.** They are kept verbatim because the ledger's rule is that an OPEN entry
may only be deleted by the QA Director who personally verified it fixed — and this cycle
verified none of them. Their numbers describe the tree at cycle 3; several are almost certainly
stale and a few are almost certainly worse.

Three notes from this cycle that bear on them:
- **D-025 is closed** (moved to the FIXED list above): the boot census reads
  `shadow=450m/pcss0.53deg` in every round's log.
- **D-031 … D-037, the "HUD lies" family**, carry wave-6 producer-claimed closures "by
  construction in `hud_gta.gd`". This cycle did not have scope to rule them, and D-153/D-154 are
  evidence that the HUD's *presentation* problems are not closed even where its *truthfulness* is.
  They stay OPEN. `--hudshot` decides them.
- **D-026** (hydrant jet) and **D-047** (identical A-pose) were both re-photographed this cycle
  and are worse than their entries describe: see the D-026 update and D-129 / D-157 above.

## S2 — MAJOR (carried from cycle 3, unverified)

### D-015  [S2]  The objective beacon is still a visible column in the judgement vantages
- **Area:** world
- **Evidence:** re-photographed this cycle in `face`, `showcase_people` and
  `slab_side` — a soft salmon column running from the repo target to the top of
  the frame, over the sky, in three of the twelve judgement vantages I re-checked
  by eye. Cycle 2's measured figure stands as the fuller count (8 of 12; in
  `car_side` the shaft ran 370 of 900 px, 41 % of frame height, at +17 R / −40 B
  above the sky beside it).
- **Bar violated:** world / "No floating geometry"; degrades the character and
  vehicle vantages for their own rows.
- **Suspected cause:** `repo_board.gd:28 BEAM_HEIGHT := 21.0` with `_process`
  setting `_beam.visible = true` whenever a repo target exists — i.e. always.
  `beacon_kit._ramp()`'s `pow(v, 1.75)` still carries alpha over the top third.
- **Status:** OPEN — unchanged since cycle 2.

### D-025  [S2]  Nothing casts a shadow beyond 300 m — the aerial view is completely flat
- **Area:** world
- **Evidence:** `aerial` re-shot this cycle. Zero cast shadows anywhere in frame;
  108 towers of genuinely varied height (see D-023 FIXED) and not one of them
  puts a shadow on the ground. Camera (880, 300, 880) → aim (300, 0, 230) =
  **921 m**, 3× beyond the shadow range. Unchanged.
- **Bar violated:** world / "Landmark legibility … `aerial`".
- **Suspected cause:** `main.gd:211 sun.directional_shadow_max_distance = 300.0`.
- **Status:** OPEN

### D-027  [S2]  Deltoids read as spheres stuck on a barrel — and there is a second pair at the elbows
- **Area:** characters
- **Evidence:** `back`, 2× NEAREST (`qa3/crop/back_2x.png`). Two smooth white
  domes sit on the torso with a hard crease at the join, and a **second, smaller
  pair sits at the elbows** — four orbs on one figure. There is a visible seam
  where each sleeve meets its cap. Unchanged from cycles 1 and 2.
- **Bar violated:** characters / "Silhouette at 1 m"; "Surface intersections".
- **Suspected cause:** the deltoid cap masses in `character_factory.gd` (file
  unchanged since 2026-08-10 23:42 — nothing was attempted this cycle).
- **Status:** OPEN — **a defect Milad has rejected once and that has now been
  reported fixed twice.**

### D-028  [S2]  Book's untucked hem reads as a hard-edged navy peplum standing off the trousers
- **Area:** characters
- **Evidence:** `back` 2× — a navy trapezoidal panel hangs over the hips with a
  hard horizontal bottom edge and a shadow gap where it stands off the leg tubes.
  From behind it reads as a skirt on a repo man in a western shirt. Unchanged.
- **Bar violated:** characters / "Silhouette at 1 m … `back`"; "Feature rim lift ≤ 5 mm".
- **Suspected cause:** the untucked-hem wardrobe piece in `character_factory.gd`.
- **Status:** OPEN

### D-029  [S2]  Mid-face is one continuous muzzle
- **Area:** characters
- **Evidence:** `qa3/crop/face_5x.png` (5×, NEAREST). Nose, philtrum, upper lip
  and chin are a single forward-projecting mass. No nostrils, no alar crease, no
  philtrum. The mouth is a dark seam laid on the front of it; the jaw is a broad
  rounded shelf. Reads as a snout **at the vantage's own 1.1 m distance**.
  **Unchanged from cycles 1 and 2.**
- **Bar violated:** characters / "Mid-face at 4× zoom reads as a face, not a snout".
- **Suspected cause:** the face masses in `character_factory.gd` — re-topology, not tuning.
- **Status:** OPEN

### D-030  [S2]  The two eyes disagree with perspective, and the near one is now occluded
- **Area:** characters
- **Evidence:** `qa3/crop/face_5x.png`. The **far** eye (frame-right) is the
  larger, carries a wide field of bright sclera and a dark iris; the **near** eye
  is a dark slit and is now **partly covered by the gold mass of D-076**.
  Perspective foreshortening should make the far eye the smaller. The eyebrows
  remain two hard black slabs, and the hat band sits low enough across them to
  read as a blindfold (see D-083). **Unchanged.**
- **Bar violated:** characters / "Mid-face at 4× zoom".
- **Suspected cause:** unknown — measure the socket normals; do not guess.
- **Status:** OPEN

### D-031  [S2]  The HUD reports a vehicle the player is not in
- **Area:** feel
- **Evidence:** `debug_hud.vehicle` is written only at `main.gd:279`, `:334`,
  `:70-71` and is never cleared; `on_foot.gd:90-116` sets `main.on_foot = true`
  without touching the HUD. On foot the panel shows the parked truck's name and
  its suspension jitter as the player's speed. `main.gd:44-47 player_actor()`
  exists to answer this and `debug_hud` never calls it. Four more HUDs share the
  bug: `repo_board.gd:379-383`, `race_event.gd:196-200,:287`,
  `slab_cruise.gd:163-165,:77-80`, `mission_hook_and_ladder.gd:324-329,:399`.
  Neither `main.gd` nor `debug_hud.gd` has been touched in three cycles.
- **Bar violated:** feel / "The HUD never lies".
- **Status:** OPEN

### D-032  [S2]  The speedometer reads 3D velocity, so falling shows as speed
- **Area:** feel
- **Evidence:** `debug_hud.gd:104` uses `linear_velocity.length()`. Off the
  freeway deck (`greybox_city.gd:39 FWY_TOP := 9.0`) v_y ≈ 13.3 m/s → the speedo
  reads ~30 MPH at zero ground speed. On a race jump at 20 m/s horizontal + 8
  vertical it over-reads 7 % at exactly the moment the player is judging the jump.
  `combat.gd:442` already computes the honest flat-plane speed.
- **Bar violated:** feel / "The HUD never lies".
- **Status:** OPEN

### D-033  [S2]  The on-screen control sheet is wrong in 4 of 6 lines on foot, and omits 9 verbs
- **Area:** feel
- **Evidence:** `debug_hud.gd:66-72`, a hardcoded 6-line string, never mode-aware,
  against 20 actions at `main.gd:128-161`. Wrong on foot: "W/A/S/D drive + steer",
  "SPACE handbrake" (jump), "R reset vehicle" (reload), "TAB switch vehicle"
  (gated to your own rig, so it fails silently in any carjacked car). Surfaced in
  none of the 16 HUDs: `radio_next` N, `weapon_next` Q, `crouch` CTRL, `sprint`
  SHIFT, `jump` SPACE, `reload` R, `fire` LMB, `aim` RMB, `ui_cancel` ESC.
  **There is still no prompt anywhere for E-to-exit the vehicle** — the entire
  on-foot half of the game sits behind an unadvertised key.
- **Bar violated:** feel / "Every verb has feedback"; "The HUD never lies".
- **Status:** OPEN

### D-034  [S2]  The combat HUD is hidden during drive-bys — the player fires blind
- **Area:** feel
- **Evidence:** `combat.gd:1165-1167` gates the whole UI on
  `active := on_foot and ch != null`. `_drive_by` (`:669`) decrements
  `_mags[_slot]` and auto-reloads at `:693` with no ammo readout, no reload
  indicator, no health bar and no reticle.
- **Bar violated:** feel / "Every verb has feedback".
- **Status:** OPEN

### D-035  [S2]  The minimap paints the race arena as water
- **Area:** feel
- **Evidence:** `minimap.gd:96-100` fills the floodway rect with
  `WATER_COLOR := Color(0.25, 0.4, 0.5, 0.8)`. `greybox_city.gd:398-407` builds
  that surface from `mat_concrete`; `race_event.gd` runs the map's signature
  16-gate time trial on it. **180 m × 900 m = 162 000 m² of dry drivable concrete
  is drawn to the player as a river.** It also uses the levee rims
  (`CH_X0 −710 / CH_X1 −530`) rather than the drivable floor
  (x ∈ [−685, −555], `race_event.gd:15`).
- **Bar violated:** feel / "The HUD never lies".
- **Status:** OPEN

### D-036  [S2]  A race can be left RUNNING forever with no exit transition
- **Area:** feel
- **Evidence:** `race_event.gd:103-107` — `_player()` returns `main.vehicle`,
  which stays valid on foot, so the `pv == null` bail never fires. Park in the
  channel, press E: `:158` keeps `_out_t` at zero (car inside `CHANNEL`, below
  `OUT_ABOVE_Y`) and `:153` never trips abandon (a stationary car stays inside the
  abandon radius). `_race_t` climbs forever with a live clock on screen while the
  player is a kilometre away on foot.
- **Bar violated:** feel / "No dead ends".
- **Status:** OPEN

### D-037  [S2]  One R press both resets the car and starts a weapon reload
- **Area:** feel
- **Evidence:** `main.gd:142-143` binds KEY_R to both `reset_vehicle` and
  `reload`; `Input.is_action_just_pressed` sets the edge on both from one physical
  press. `main.gd:102` resets the vehicle, `combat.gd:648-651` starts a 1.3 s
  reload, guarded only by `not accelerate`. Reachable while driving, off the
  throttle, mag not full — exactly when a player reloads. The car teleports
  upright, velocity zeroed.
- **Bar violated:** feel / "Input → response; no input eaten".
- **Status:** OPEN

### D-039  [S2]  From a dead-side elevation the Slab reads as an open car — you see the street through the cabin
- **Area:** vehicles
- **Evidence:** **now verifiable — thank you for `slab_side`.** Crop
  `qa3/crop/slab_flank_3x.png` (3×, NEAREST, from the new `slab_side` vantage at
  8.5 m on the car's flank): the side glass renders essentially invisible and
  there is no interior mass behind it, so the buildings on the far side of the
  street are visible **through** the greenhouse. The roof reads as a gold plate
  floating over a gap, carried by two 1-px black hairlines standing in for the A
  and B pillars. The same car at `slab_34` (`qa3/crop/slab34_2x.png`) **does** show
  glass, a windscreen tint and an interior mass — so this is an angle-dependent
  failure, which is exactly the class of defect the judgement vantages exist to
  catch. It is worse than the "opaque painted panel" originally filed: an empty
  aquarium at least has walls.
- **Bar violated:** vehicles / "Cabin: interior visible through glass; no empty aquarium".
- **Suspected cause:** unknown. Probably the same physics as D-068's root cause —
  a surface whose only light is sky ambient, plus nothing solid behind it — but I
  did not read the glass material and will not guess.
- **Status:** OPEN — **re-scoped on new evidence, no longer blocked.**

### D-073  [S2]  The post-death respawn frame does not hold 60 fps — 54.0 fps, best of three
- **Area:** feel / rendering
- **Evidence:** my own `--perf --perf-repeat=3`, 10 stations × 300 measured
  frames, 1600×900, vsync off, anchor on, run on the frozen copy. The harness's
  own verdict line: `VERDICT: p95 OVER BUDGET at: hospital_door_night`.

  | station | best ms | fps | p95 ms | worst | spread | draws | objs | 60 fps |
  |---|---|---|---|---|---|---|---|---|
  | downtown_day | 12.50 | 80.0 | 12.96 | 22.83 | 4 % | 3 615 | 5 203 | ok |
  | downtown_night | 12.96 | 77.1 | 14.27 | 30.90 | 0 % | 4 411 | 6 428 | ok |
  | suburb_day | 8.39 | 119.2 | 9.09 | 11.39 | 13 % | 705 | 972 | ok |
  | suburb_night | 11.90 | 84.0 | 12.96 | 15.10 | 5 % | 661 | 926 | ok |
  | freeway_day | 11.11 | 90.0 | 11.67 | 17.51 | 7 % | 2 863 | 4 584 | ok |
  | freeway_night | 13.59 | 73.6 | 13.87 | 23.84 | 5 % | 3 135 | 4 711 | ok |
  | hospital_day | 8.33 | 120.0 | 9.09 | 14.95 | 3 % | 446 | 578 | ok |
  | hospital_night | 12.23 | 81.7 | 13.89 | 16.56 | 2 % | 810 | 974 | ok |
  | hospital_door_day | 14.81 | 67.5 | 15.73 | 22.17 | 3 % | 5 994 | 10 408 | ok |
  | **hospital_door_night** | **18.52** | **54.0** | **18.52** | 26.73 | **1 %** | **6 975** | **11 743** | **FAIL** |

  The three passes for that station measured 18.52 / 18.52 / 18.75 ms — a 1 %
  spread. **That is not machine noise; it is a stable number.** Boot to playable
  4.12 s (bar ≤ 20 s, ok).
- **Bar violated:** §4b / "Frame time, downtown at street level — ≥ 60 fps
  sustained on the dev machine". (The row names downtown; the station that fails
  is the ER doors *looking down downtown's length*, which is the same geometry
  with more of it in frame.)
- **This refutes the report.** "Nothing under 60 fps … 84 fps quiet" is not what
  this machine returns. **Both numbers are honest**, which is the problem: the
  §4b row says "on the dev machine" and does not say in what state, so the same
  station legitimately passes at 84 fps and fails at 54 fps depending on what else
  is running. **Request to the producer: pin the row** — a stated machine state
  (e.g. "best of 3 passes, no other agent session running") the way you pinned
  Ø:H, sill and arch-gap. As written the row is unfalsifiable and can be passed
  or failed at will, which is the exact failure this loop exists to remove.
- **The durable numbers do not move:** `hospital_door_night` draws **6 975–7 017**
  calls over **11 718–11 964** objects, 1.6× `downtown_night`. Whatever the clock
  says, it is the heaviest frame in the game and it is mandatory.
- **Suspected cause:** no HLOD/imposters for the downtown skyline; the frame
  stands outside downtown looking down its full length.
- **Status:** OPEN

### D-074  [S2]  A dressing layer that fails to parse is swallowed — the game boots, exits 0, and ships a city with a whole layer missing
- **Area:** ci
- **Evidence:** captured live, three times, when a concurrent edit left
  `city_dressing.gd` unparseable. `greybox_city.gd:568-572 _build_dressing()` does
  `var script: GDScript = load(DRESSING_PATH)` then `script.new()` with **no null
  check**; `_build_extra_layers()` (`:733-741`) does check (`if not (script is
  GDScript): continue`) and therefore **skips a broken layer in total silence**.
  The observed result — process **exit code 0**, and a city that printed
  `POOLS: arterial=0` and `SUBURB NIGHT: 357 lights (… head 0)` against the
  healthy build's `arterial=536` / `492 lights (… head 156)`. Every streetlight,
  every lane marking, every sign and every tree was gone and nothing failed.
  Reproduced identically in `S_8_3/4/5.log`; the same thing hit `plaza_dressing.gd`
  during a 39-shot sweep, which saved all 39 PNGs of a city with no plaza dressing.
- **Bar violated:** §5 / "`--headless --quit-after 900`: zero error lines" —
  the gate catches it **only if the runner captures stderr** (see D-075), and
  nothing catches it at runtime at all.
- **Suspected cause:** pinned — `greybox_city.gd:570` (`script.new()` on a
  possibly-null load) and `:735-736` (silent `continue`).
- **Status:** OPEN

### D-075  [S2]  Every warning and error in this project goes to stderr only — any gate quoted from a stdout-only log is void
- **Area:** ci
- **Evidence:** measured directly. Ten boots with the streams split
  (`> out.txt 2> err.txt`): the `WARNING: 6 ObjectDB instances were leaked at exit`
  line appeared in **0 of 10 stdout files and 1 of 10 stderr files**. `SCRIPT
  ERROR` and `ERROR` lines behave the same way — the 44-error boot of D-074 wrote
  **nothing** to stdout beyond its normal build summary.
  **Consequence:** an agent running `godot --headless --quit-after 900 > run.log`
  will see a perfectly clean log for 50 consecutive boots **of a build that does
  not compile**. This single omission is the whole explanation of the "0 dirty in
  50 boots" report, and it has now cost the producer three separate escalations on
  a number that was never being measured.
- **Bar violated:** §5, which specifies the command but not the redirection.
  **Request to the producer: the bar's §5 command must read
  `--headless --quit-after 900 2>&1`, and any leak/error rate quoted without it is
  to be discarded on sight.**
- **Status:** OPEN — bar amendment owed.

### D-076  [S2]  A gold-tan ellipsoid intersects Book's left cheek and covers his near eye
- **Area:** characters
- **Evidence:** `qa3/crop/face_5x.png` (5×, NEAREST, from the `face` vantage's own
  1.1 m). A smooth gold-tan ellipsoid roughly the width of the character's eye
  socket sits on the left cheek, forward of the face plane, with its own lighting
  gradient and a hard silhouette edge. It occludes the cheek and cuts across the
  near eye's sclera. It is **not background**: the camera looks toward +X/+Z and
  the only gold object in the scene (the Slab, x = 321.5) is behind the camera.
  The **far** temple carries a dark, correctly-placed ear-shaped mass in the same
  position — so the two sides do not match.
- **Bar violated:** characters / "Silhouette at 1 m … `face`"; "Feature rim lift
  ≤ 5 mm; nothing floating"; "Mid-face at 4× zoom".
- **Suspected cause:** unknown. It renders like a `mesh_kit.sphere()` ear in the
  wrong material at the wrong offset, but I did not confirm that in
  `character_factory.gd` and I will not guess. **Whoever fixes this must check
  both ears on the full population, not just Book.**
- **Status:** OPEN — **new, and it is on the protagonist at the primary vantage.**

### D-084  [S2]  The tree is edited during the QA verification window, so no measurement describes a build anybody can name
- **Area:** ci / process
- **Evidence:** this cycle. Between 01:34 and 01:45 eleven world files were
  rewritten while the audit was running. Consequences I measured, not inferred:
  three of eighty gate boots ran against an unparseable tree; a full 39-shot
  photometric sweep ran against a city with `plaza_dressing` missing; and 17
  distinct build fingerprints appeared across 80 boots that should have been one.
  I had to fall back to a frozen 01:28 byte-copy to grade anything at all.
- **Bar violated:** the bar's first law — "a criterion that cannot be measured or
  photographed is not a criterion". A criterion measured against a moving tree is
  not measured.
- **Request to the producer:** a fix mission and a QA cycle may not overlap. Either
  (a) QA is handed a named, frozen revision to grade, or (b) fix missions hold
  their writes until QA reports. Right now every number in this ledger carries an
  asterisk that has nothing to do with the work.
- **Status:** OPEN

---

# S3 — MINOR

### D-003  [S3]  Mouth under-readable at the `face` vantage
- **Area:** characters
- **Evidence:** the geometry is present at 5× (a dark seam, a slightly proud lower
  lip) but does not read at the vantage's native 1.1 m — a consequence of the
  muzzle mass, not of the mouth.
- **Status:** OPEN, **re-scoped — fix with D-029, never independently.**

### D-005  [S3]  Bare neck between the hair shell and the collar
- **Area:** characters
- **Evidence:** `back` 2× — the hair shell at the back of the skull is now present
  and reads (an improvement on cycle 2), but below it a bare brown neck runs to the
  collar with a hard horizontal step where the skull mass ends.
- **Bar violated:** characters / "Silhouette at 1 m … `back`"; "Surface intersections".
- **Status:** OPEN — **re-scoped: the hair is fixed, the neck join is not.**

### D-007  [S3]  The Slab's C-pillar reads as a plate, not a lofted shell, from the side
- **Area:** vehicles
- **Evidence:** **now verifiable.** `slab_34` shows the promised blind sail panel
  and it works — the rear quarter has a real shoulder and a chrome belt bead. But
  `slab_flank_3x` from the dead-side elevation shows the roof and pillar collapsing
  into a flat plate over the open cabin of D-039. The sail panel is not the problem;
  what it is attached to is.
- **Status:** OPEN — **re-scoped; fix alongside D-039.**

### D-009  [S3]  Dead astern the Slab stacks six horizontal bands
- **Area:** vehicles
- **Evidence:** **now verifiable — thank you for `slab_rear`.** Crop
  `qa3/crop/slab_tail_3x.png` (3×, NEAREST). Counting from the roof down:
  backlight, decklid, chrome badge strip, a full-width red lamp bar broken by two
  white segments, a chrome bumper bar, a gold valance with two round reflectors.
  Six bands, all horizontal, no vertical element anywhere on the tail, no separate
  lamp lenses, no plate recess. The red bar reads as a period American tail, which
  is the right idea; nothing interrupts it, which is the defect.
- **Bar violated:** vehicles / "Surface — a character line the highlight
  terminates on; no flat-value flank" (applied to the tail).
- **Status:** OPEN — **confirmed on first sight of a real vantage.**

### D-026  [S3]  The hydrant water jet renders as a column of floating hard-edged cards
- **Area:** world
- **Evidence:** **downgraded S2 → S3 and re-scoped, NOT closed.** With D-067
  fixed, no jet fires anywhere in a 39-vantage sweep or in 120 physics frames on
  three boots (probe: `jets=0` at every sample). The card-look defect is therefore
  **no longer visible at boot** and is no longer costing 14 screenshots. But
  `_start_jet` and its `ParticleProcessMaterial` are unchanged, so the defect is
  latent and will render the first time a player hits a hydrant — which is a
  thing players do on purpose.
- **Could not test:** nothing in `zz_shot` or any harness triggers a hydrant.
  **Request to the producer: a harness hook that knocks one hydrant loose and
  shoots it**, or this row stays permanently unphotographable.
- **Status:** OPEN — latent, player-triggered only.

### D-040  [S3]  Crosswalk paint, stop bars and turn arrows pile up inside the intersection box
- **Area:** world
- **Evidence:** `street_detail` — the near intersection still carries zebra bars, a
  stop bar, lane arrows and road lettering overlapping in the same box; the
  bottom-right of frame is a pile of white rectangles with no readable order.
  Visibly cleaner than cycle 1 but **not clear**.
- **Bar violated:** world / "Street furniture density" (cues present but illegible).
- **Status:** OPEN

### D-041  [S3]  County General's two signs collide in the sightline into an illegible stack
- **Area:** world
- **Evidence:** `face`, `showcase_people` — a large white "COUNTY GENERAL", a
  smaller blue "COUNTY GENERAL", a red "EMERGENCY" and a fourth unreadable line
  pile up on the same apparent wall at different scales. **Unchanged.** County
  General is the mandatory post-death respawn.
- **Cause (verified in code):** two *different* signs 36 m apart in depth line up
  from any southern approach — the fascia sign at `greybox_city.gd:644` (z 621.6,
  210 pt) and the roadside sign at `:653-658` (z 585). Placement, not labelling.
- **Status:** OPEN

### D-042  [S3]  Floodway graffiti renders as flat saturated colour rectangles, some floating
- **Area:** world
- **Evidence:** `floodway` — violet, salmon, orange and turquoise hard-edged quads
  on the prairie with no legible lettering; the violet quad casts its own shadow,
  so it is raised off the terrain. Unchanged.
- **Bar violated:** world / "No floating geometry".
- **Suspected cause:** `wild_dressing.gd:65-66 SPRAY`.
- **Status:** OPEN

### D-043  [S3]  The floodway channel is a clean tiled plane — none of its declared dressing reads
- **Area:** world
- **Evidence:** `floodway` — flat mid-grey with a regular seam grid. No slope, no
  low-flow channel, no staining, no debris; none of the declared bathtub ring,
  outfall pipes or depth gauges is visible; the channel walls are absent (prairie
  meets floor on a bare diagonal). Unchanged.
- **Bar violated:** world / "Street furniture density".
- **Status:** OPEN

### D-044  [S3]  Road paint is emissive — it glows at night on a black road
- **Area:** world
- **Evidence:** `street_night` re-shot. Lane lines, centre lines, the near stop bar
  and the CANDYLAND STRIP magenta kerb bands all render at near-full brightness
  while the asphalt beside them measures 0–2/255. The paint is the only thing
  lighting the road and it lights itself. Unchanged.
- **Bar violated:** world / "Night identity".
- **Suspected cause:** `_paint()` in `greybox_city.gd:681-691` sets `SHADING_MODE_UNSHADED`.
- **Status:** OPEN

### D-045  [S3]  Ambient traffic runs at night with no headlights or tail lights
- **Area:** world / feel
- **Evidence:** `street_night` — vehicles down the avenue are dark silhouettes with
  no lamps lit. The warm pools on the road are streetlight pools, not headlight
  throw. Unchanged.
- **Bar violated:** world / "Night identity".
- **Status:** OPEN

### D-046  [S3]  Downtown streets are near-empty of pedestrians
- **Area:** world
- **Evidence:** `street_detail` and `street_north` show two or three distant
  figures on 200 m of sidewalk. `pedestrians.gd:13-16` maintains `PED_COUNT := 16`
  in a 60–200 m ring around **the player**; the `zz_shot` free camera is not the
  player. Corroborated by the perf harness, which teleports the rig and then
  reports `peds 16` at downtown — sixteen people in a downtown.
- **Bar violated:** world / "Street furniture density".
- **Status:** OPEN

### D-047  [S3]  Every pedestrian in the crowd stands in an identical neutral A-pose
- **Area:** characters
- **Evidence:** `showcase_people` re-shot. The wardrobe half remains genuinely
  fixed — eight adjacent figures differ in height, build, skin tone, hair, facial
  hair and outfit, and no two read as the same person. **All eight stand
  feet-together, arms straight down, shoulders square, facing the same way.** One
  pose, 100 % of the crowd. Hands are brown blocks with no fingers.
- **Bar violated:** characters / "Crowd variety" (in spirit; the "no two adjacent
  peds" clause passes).
- **Status:** OPEN — half fixed.

### D-049  [S3]  The western yoke and the ID lanyard sit visibly off the garment
- **Area:** characters
- **Evidence:** `back` 2× — a continuous dark slit of shadow runs under the yoke's
  trailing edge across the whole back, and the yoke reads as a separate raised
  panel rather than a seam. `showcase_people` — the scrubs ped's ID lanyard is a
  flat card standing off the chest.
- **Bar violated:** characters / "Feature rim lift ≤ 5 mm; nothing floating".
- **Note:** the decision log claims the yoke was rebuilt to a constant 1.7–3.5 mm
  relief. What renders does not look like 3.5 mm. **A numeric rim-lift mirror of
  `character_factory.gd` is still owed** — see "Could not test".
- **Status:** OPEN

### D-050  [S3]  The camera's spring arm is a single ray, so geometry clips the near plane
- **Area:** feel
- **Evidence:** `chase_camera.gd:163-184` casts one `intersect_ray` from pivot to
  desired position. With `near = 0.1` (`:109`) and FOV 70° at 16:9 the lens needs
  ≈0.25 × 0.14 m of clearance and a zero-width ray guarantees none of it. A
  shape-cast is the standard fix.
- **Status:** OPEN — code finding; still not photographable.

### D-051  [S3]  The camera ignores the player's own vehicle, so the lens passes through it
- **Area:** feel
- **Evidence:** `chase_camera.gd:186-199 _exclusions()` adds both `main.vehicle`
  and `main.character` to the exclude list. Standing on the far side of your own
  truck renders the camera from inside its bodywork.
- **Status:** OPEN — deliberate trade-off; re-decide rather than silently patch.

### D-052  [S3]  Hood and orbit camera modes have no collision handling at all
- **Area:** feel
- **Evidence:** `_spring()` is called from only two sites (`chase_camera.gd:268`,
  `:435`). The hood rig (`HOOD_OFFSET`, `:31`) and the orbit rig (`ORBIT_RADIUS`,
  `:34`) are rigid offsets with nothing to pull the lens out of geometry.
- **Status:** OPEN

### D-053  [S3]  Three HUDs share layer 9 and two of them overlap on screen
- **Area:** feel
- **Evidence:** `minimap.gd:48`, `radio.gd:197`, `sky_weather.gd:657` are all
  `layer = 9`. The radio station card (CENTER_TOP y 170, 34 pt) and the storm
  banner (CENTER_TOP y 180, 26 pt) overlap text-on-text — reachable by pressing N
  during a storm warning. Layer 20 is triple-booked (tow_hook / carjack /
  interactables). Three more reachable overlaps: tow_hook "SNAPPED" over the race
  countdown; the debug_hud toast under the WANTED banner; the combat health band
  against the mission bar at viewport widths ≤ 620 px.
- **Status:** OPEN

### D-054  [S3]  The vehicle damage bar is pinned empty across 35 points of live health
- **Area:** feel
- **Evidence:** `police_gunfire.gd:518` clamps `hull/mx` to [0,1] but hull
  legitimately runs to `DEATH_HULL := -35.0` (`:37`, `:245`). From hull 0 down to
  −35 — five more hits — the bar reads empty while the player is being killed.
  `:514` also reads a hardcoded `100.0` denominator instead of `_hull_max()`
  (`:222-231`).
- **Bar violated:** feel / "The HUD never lies".
- **Status:** OPEN

### D-055  [S3]  Neither mission is findable from the minimap
- **Area:** feel
- **Evidence:** `minimap.gd:102-121` draws six things and neither mission start is
  among them. `mission_hook_and_ladder.DISPATCH_POS (709, 528)` lands 14 px from
  the "P" marker with nothing drawn there; `mission_second_collection.BOARD_POS
  (142, 596)` is a blank grey square. Both are discoverable only by driving into a
  7–8 m trigger radius — and the sky beam that used to advertise them is now
  `visible = false` unless the mission is running.
- **Status:** OPEN

### D-056  [S3]  The world's edge renders as a visible drawn rectangle
- **Area:** world
- **Evidence:** `aerial` — a thin hard line runs around the whole map and the scrub
  scatter changes density discontinuously across it. Unchanged.
- **Status:** OPEN

### D-058  [S3]  Overflow Fellowship's spire is disconnected from the building
- **Area:** world
- **Evidence:** `landmark_church` — a plain white cone with a gold ball rises
  straight out of flat asphalt in the car park, with no base or connection to the
  church. Unchanged. (The landmark otherwise passes its bar row.)
- **Status:** OPEN

### D-059  [S3]  Three more dead ends: race pad, Candyland pause, and the tow chain
- **Area:** feel
- **Evidence:**
  - `race_event.gd:115-117` — `_must_exit_pad` clears only when the **vehicle** is
    >13 m from the pad; finish a race, step out, walk away and the pad never re-arms.
  - `slab_cruise.gd:89-94` — park inside the Candyland band and walk away:
    "CANDYLAND PAUSED — ROLL ON" stays pinned bottom-right for the session.
  - `tow_hook.gd:66-76, 97-98` — hook a car, press E: the chain persists, F is
    gated to `not on_foot`, and the hint is hidden on foot.
- **Bar violated:** feel / "No dead ends".
- **Status:** OPEN

### D-060  [S3]  SPACE arms a race while the player is on foot
- **Area:** feel
- **Evidence:** `main.gd:133,141` binds SPACE to both `handbrake` and `jump`;
  `race_event.gd:120` reads `Input.is_action_pressed("handbrake")` with no
  `on_foot` guard and `_player()` returns `main.vehicle`, still valid while
  walking. Park on the start pad, step out, hold SPACE to jump for
  `HOLD_SECONDS := 1.0` → the countdown starts on a driverless car. Feeds D-036.
- **Status:** OPEN

### D-066  [S3]  A fire hydrant is embedded in a parked car's front bumper
- **Area:** world
- **Evidence:** cycle-1 `showcase_cars`. **Still not re-verified** — no vantage
  frames that corner of the lot. Kept OPEN per the standing rule (I have never
  personally verified it as fixed).
- **Bar violated:** world / "No floating geometry".
- **Status:** OPEN

### D-077  [S3]  The Slab's door shut-lines are hairlines that overrun the door opening
- **Area:** vehicles
- **Evidence:** `qa3/crop/slab_flank_3x.png` and `slab34_2x.png`. Two vertical
  1-px black lines and one long horizontal 1-px black line are drawn on the flank.
  The horizontal line runs the **whole length of the car**, through the front
  fender and into the rear quarter, where no shut-line exists; the vertical lines
  run down past the rocker. At 3× they read as scratches in the paint, not panel
  gaps — and on a car whose entire thesis is a flawless gold flank, that is the
  first thing the eye lands on.
- **Bar violated:** vehicles / "Surface — a character line the highlight
  terminates on"; "Surface intersections — no visible seam where two masses cross".
- **Suspected cause:** unknown — the shut-line pass in `vehicle_body_builder.gd`.
- **Status:** OPEN

### D-078  [S3]  The Slab's decklid badge is buried in the sheet metal — the glyph tops are sheared off
- **Area:** vehicles
- **Evidence:** `qa3/crop/slab_tail_3x.png` (3×, NEAREST). The decklid lettering
  reads as "CANDYLAND ST_R" because the top ~30 % of every glyph is cut off by the
  decklid surface it is sitting inside. The text is co-planar with, or inside, the
  bodywork rather than standing on it.
- **Bar violated:** characters/vehicles / "Feature rim lift ≤ 5 mm proud of the
  surface it sits on" (applied to badges), and "no visible seam where two masses cross".
- **Suspected cause:** unknown — the badge/plate placement in
  `vehicle_body_builder.gd`. Note the same file's D-016 fix proved every `Label3D`
  in the project needed auditing once; this is the depth axis of the same problem.
- **Status:** OPEN

### D-079  [S3]  Re-skinning the towers cost downtown a fifth of its night brightness
- **Area:** world
- **Evidence:** photometry, ground half of frame, Rec.709 0–255, same vantages,
  same method as cycle 2:

  | vantage | mean (was) | bright px > 64/255 (was) | change |
  |---|---|---|---|
  | street_night | **15.33** (18.74) | **48 837** (61 998) | −21 % bright px |
  | skyline_night | **9.98** (11.10) | **26 303** (32 153) | −18 % |
  | freeway_night | **8.57** (10.06) | **21 190** (27 668) | −23 % |
  | suburb_night | 9.87 (9.87) | 28 237 (28 237) | **pixel-identical ✔** |

  The suburb claim ("pixel-identical") is exactly true. The freeway claim is not:
  `freeway_night` lost 23 % of its bright pixels. The cause is not
  `hospital_night.gd` — it is the tower re-skin, which replaced a wall of emissive
  glass with masonry, concrete and painted block. **That is the right city and the
  wrong night.** Downtown at night is now dimmer than it was, and D-064's bimodal
  read (hard yellow windows on pure black walls) is more pronounced, not less.
- **Bar violated:** world / "Night identity — every district has a distinct night
  read; no black voids".
- **Suspected cause:** the new type materials in `downtown_types.gd` carry no
  night emission where `mat_glass` did.
- **Status:** OPEN — **a regression caused by a fix I am closing in the same cycle.**

### D-080  [S3]  The judgement vantages shoot through a ~107° horizontal lens, so the subject is a fifth of the frame
- **Area:** ci / audit infrastructure
- **Evidence:** `zz_shot.gd:129-131` creates the free camera and sets only `far`,
  so it runs Godot's default **75° vertical** FOV — at 16:9 that is **107°
  horizontal**. At `car_side`'s 8.5 m stand-off the frame is 22 m wide, so the
  4.8 m Interceptor occupies **19 % of frame width (~300 px of 1600)**. Two bar
  rows name that vantage ("Surface — a character line the highlight terminates
  on", "Cabin — interior visible through glass") and neither can be judged at that
  scale; D-039 had to be measured off a 3× crop of a *different* vantage. The same
  lens is why `car_wheel` at 1.22 m still frames the whole front of the car.
- **Bar violated:** the bar's own method column.
- **Request to the producer:** set `_cam.fov` to something in the 35–45° range for
  the judgement vantages (a portrait lens), or halve their stand-off distances.
  `zz_shot.gd` is your file; I did not edit it.
- **Status:** OPEN

### D-081  [S3]  Book's trousers carry a hard horizontal colour step across both calves
- **Area:** characters
- **Evidence:** `back` 2× — a hard horizontal seam runs across both legs at
  mid-calf with navy above and a darker navy below, on both legs at the same
  height. It reads as a boot top that is not a boot; there is no geometry change
  at the line, only a value change.
- **Bar violated:** characters / "Silhouette at 1 m … `back`"; "Surface intersections".
- **Suspected cause:** unknown — the trouser/boot material split in `character_factory.gd`.
- **Status:** OPEN

### D-083  [S3]  The hat crown has a rectangular notch bitten out of its silhouette, and the band sits across the eyebrows
- **Area:** characters
- **Evidence:** `qa3/crop/face_5x.png`. Two things at the top of the same crop:
  (a) the crown's rear silhouette carries a **hard-edged rectangular step**, as if
  a box had been subtracted from the top-rear of the hat; (b) the black hat band
  sits low enough that it crosses the top of both eyebrows, so at the `face`
  vantage the character reads as wearing a blindfold pushed up on his forehead.
- **Bar violated:** characters / "Silhouette at 1 m"; "Surface intersections".
- **Suspected cause:** unknown — the crown/band construction in `character_factory.gd`.
- **Status:** OPEN

### D-086  [S3]  63 563 MultiMesh instances, 87 % of them entering every shadow cascade
- **Area:** world / rendering
- **Evidence:** filed from the producer's `--perf-mm-audit` (189 MultiMeshes,
  63 563 instances, 55 251 in every cascade; only 5 of 13 MultiMesh-building files
  set `cast_shadow`), with a measured upper bound of downtown_day 8.33 → 7.41 ms
  and 3 906 → 3 222 draws (−17.5 %). **Not measured by me** — the sweep was
  landing while I audited (D-084) and I could not get a stable A/B.
- **Bar violated:** §4b / "No per-frame work over batched instance sets".
- **Status:** OPEN — **sweep in flight; QA to verify next cycle.** It is filed so
  that it cannot quietly become "done" without a number.

---

# S4 — POLISH

### D-061  [S4]  Eleven HUD files leave Labels on the engine default instead of the stated law
- **Area:** feel
- **Evidence:** the "HUD law" (a STOP control eats captured-mouse look) is written
  in only 5 of 16 HUDs. Eleven rely on `Label`'s class default
  `MOUSE_FILTER_IGNORE`: `tow_hook`, `slab_cruise`, `police_gunfire`, `carjack`,
  `interactables`, `race_event`, `mission_hook_and_ladder`, `police`, `on_foot`,
  `repo_board`, `sky_weather`. Functionally correct today.
  `combat.gd:1118-1123` documents why this bit the project before. Any of these
  becoming a `RichTextLabel`, `Button`, `Panel` or `ColorRect` reintroduces the bug
  and no harness catches it.
- **Status:** OPEN

### D-062  [S4]  `combat.gd` reads a `max_health` property that does not exist
- **Area:** feel
- **Evidence:** `combat.gd:1199` calls `ch.get("max_health")`, always null —
  `player_character.gd:75` declares `const MAX_HEALTH := 100.0` and constants are
  not readable via `Object.get()`. The health bar is correct only because the
  hardcoded fallback at `:1200` happens to equal `MAX_HEALTH`.
- **Status:** OPEN

### D-063  [S4]  ESC cannot release the mouse during the death card
- **Area:** feel
- **Evidence:** `on_foot.gd:63-64` returns on `_death_active` above the
  `ui_cancel` handler at `:65-70`. For the 4 s the card is up the one escape valve
  is unreachable.
- **Status:** OPEN

### D-064  [S4]  Night is bimodal — emissives on black, with no mid-tones
- **Area:** world
- **Evidence:** `street_night` measures **86.9 %** of the ground half below 8/255
  (cycle 2: 84.2 %) with a median of **0.07**. Downtown at night has essentially
  no surfaces in the readable middle of the range, and the tower re-skin made this
  worse, not better (see D-079). **The one place in the game that now has real
  mid-tones is County General** (median 10.80) — which is the proof that this is
  solvable, and the model for how.
- **Status:** OPEN — worsened.

### D-082  [S4]  Wrecker and junker bodywork stands proud of the tyre inside the arch band
- **Area:** vehicles
- **Evidence:** vertex probe, vehicle-local space, non-arch meshes only, measured
  inside the arch sweep band. Wrecker **+25.6 mm** outboard of the nominal tyre
  face (3.6 mm past its own lip crest), from an unnamed `ArrayMesh` at local
  (1.08, −0.08, −1.04). Junker **+25.1 mm** (2.2 mm past its lip crest), from the
  body shell itself. Every other shell's widest bodywork lands exactly on the lip.
- **This does NOT fail the bar row** — the row measures the arch lip against the
  tyre and that passes at 22.0 mm on all eight (D-021 FIXED). It is filed because
  `BEAM_INSET`'s stated intent is "a car's bodywork STOPS AT ITS OWN TYRE" and on
  two shells something walks past it.
- **Status:** OPEN

---

# WONTFIX / RULED

### D-012  [RULED 2026-08-11 — rate settled at 13 %, and the 0/50 explained]  Ambience leaks 6 ObjectDB instances at exit
- **Area:** ci
- **THE EXPERIMENT.** Randomised interleaved block design, 8 blocks × (5 serial +
  5 concurrent), within-block order alternating so thermal and background drift
  cannot align with one arm. Same binary, same tree, same command line, stderr
  captured. 80 boots; 3 excluded because they caught the tree mid-edit (D-084);
  **77 scored**, plus 10 stream-split boots = **87 valid boots**.

  | arm | dirty / n | rate |
  |---|---|---|
  | serial, quiet machine | 7 / 37 | 18.9 % |
  | 5-way concurrent | 3 / 40 | 7.5 % |
  | **pooled (77)** | **10 / 77** | **13.0 %** |
  | + 10 split-stream boots | 11 / 87 | 12.6 % |

  **THE NUMBER YOU CAN TRUST: 13 %, Wilson 95 % CI [7.2 %, 22.3 %].**
- **Machine load is not the driver.** Serial vs concurrent, Fisher exact
  **p = 0.115**, and the difference is in the *wrong* direction for the load
  hypothesis. Wald–Wolfowitz runs test on the chronological sequence:
  **z = −0.72** — no clustering, no bursts. It behaves as an independent coin.
- **THE 0-IN-50 IS NOT SAMPLING NOISE AND IT IS NOT A MYSTERY.** Under p = 0.13,
  P(0 dirty in 50) = **9.5 × 10⁻⁴**. It is a measurement artefact, and I have
  reproduced the artefact: **the leak warning is written to stderr and nothing
  else.** Ten boots with the streams split put the line in 0/10 stdout files and
  1/10 stderr files. An agent running `godot … > run.log` sees a clean log every
  time, forever, at any n. That agent measured nothing. So did the 0/3 agent. The
  3/12 agent captured stderr and its number sits comfortably inside my CI
  (p = 0.20). **Filed as its own defect — D-075 — because the same omission hides
  `ERROR` and `SCRIPT ERROR` lines, which is far worse than hiding a warning.**
- **My own cycle-2 figure of 19/46 (41.3 %) does not reproduce.** Under 13 % it is
  as unlikely as the 0/50 is in the other direction. I cannot A/B a tree that no
  longer exists, so I will not manufacture an explanation: the honest statement is
  that the cycle-2 number described a build that has since had `downtown_types`,
  `hospital_night` and a streetlight rework land on it, and **13 % is what this
  tree does.** The cycle-1 figure (2/19, 10.5 %) *is* consistent with today.
- **Ruling:** the carve-out in the bar is correctly sized — every one of the 11
  dirty boots was exactly `6 ObjectDB instances`, with zero error lines and zero
  other warnings. The gate passes. **Stop re-measuring this.** If anyone quotes a
  new rate, the first question is whether they captured stderr.
- **Status:** WONTFIX (carve-out holds) — **rate ruled, case closed.**

### D-022  [WONTFIX — producer ruling, 2026-08-11]  Suspension bump travel exceeds the arch gap
- **Area:** vehicles / physics
- **Ruling stands:** the Slab's and Brisket's ratified D-012 driving identities
  outrank the millimetre count, and spring rate will not be touched.
- **Note carried forward, not a re-litigation:** the Vantage and Interceptor miss
  by 12.8 and 5.7 mm and the car arch-gap bar runs to 90 mm. Raising
  `ARCH_GAP["car"]` from 0.074 to 0.090 clears both **without touching physics and
  without leaving the bar**. It does not help the Slab or the Brisket.
- **Status:** WONTFIX (character over geometry, per the ruling)

---

# NOT REPRODUCED

### D-071  [NOT REPRODUCED, cycle 2 of 2]  `SpatialMaterial remapped parameter not found: specular`
- Cycle 2: 48 runs, zero occurrences. Cycle 3: **90 further boots with stderr
  captured, zero occurrences.** The only `specular`-adjacent write in the tree is
  `suburb_night.gd:253 l.light_specular = SPECULAR`, a valid `Light3D` property
  that cannot emit that string (it comes from `BaseMaterial3D`'s Godot-3
  compatibility remap). **138 boots, no reproduction. Close it next cycle unless
  someone supplies the exact command line and log.**

### D-008  [CLOSED 2026-08-11]  "Windshields flare white in sun"
- Three cycles, no reproduction at any daylight vantage, no vantage ever supplied.
  Closed. Re-file with a screenshot if it is real.

