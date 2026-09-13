# DEFECT LEDGER

Single source of truth for what is wrong with EL DORADO GRANDE right now.
Owned and rewritten by the **QA Director** each cycle. Fix order is S1 → S2 → S3.
Bar: `docs/qa/quality-bar.md`.

**Cycle:** 3 (verification cycle), 2026-08-11.

> **CYCLE 6 INTERIM — PRODUCER-MEASURED, 2026-09-06.** No QA Director pass has run since
> wave 6 landed (both cycle-3 QA launches died to the watchdog; the wave-6 model change
> routes measurement to cheap runners and judgement to the producer). Until QA rewrites
> this ledger, the following entry is the highest-severity known defect and outranks
> everything below it.
>
> ### D-100  [S1]  The M23 light pipeline (the shipped default) fails bar §4b at 10 of 10 perf stations
> - **Area:** performance / rendering
> - **Evidence:** `perf_harness --perf-repeat=3`, quiet machine, single Godot instance,
>   best-of-three medians. New default: downtown_day 21.88 ms, downtown_night 24.37,
>   suburb_day 17.54, suburb_night 17.59, freeway_day 19.90, freeway_night 18.75,
>   hospital_day 19.05, hospital_night 19.23, hospital_door_day 23.61,
>   hospital_door_night 23.81 — **every station over 16.67 ms**. `--env-legacy` from the
>   same tree: 7.72 / 8.26 / 5.56 / 6.25 / 6.67 / 7.14 / 4.80 / 6.25 / 10.00 / 11.11 —
>   10 of 10 pass, and downtown matches its historical 8.33 ms baseline (the run is
>   quiet). Cost is flat across stations (17.5 ms floor at 671 draws) → fixed
>   full-screen/volume passes, not geometry. Logs: scratchpad `meas7/perf_new.log`,
>   `meas7/perf_legacy.log`; table in `docs/decisions.md` D-040.
> - **Bar violated:** §4b "≥60 fps at every station, best of ≥3, quiet machine".
> - **Status:** RESOLVED PENDING QA (2026-09-06).
>
> **PRODUCER-CLAIMED CLOSURES, PENDING QA VERIFICATION (2026-09-06, wave 6).** A builder
> may never close its own defect; these are claims with evidence pointers, for QA to rule on:
> - **D-025** (no shadow beyond 300 m): shadows to 450 m over four cascades in the shipped
>   budget tier (900 m under `--env-photo`). Evidence: `meas7/plates_default/aerial.png`.
> - **D-031, D-032, D-033, D-034, D-035, D-037** (the "HUD lies" family): closed by
>   construction in `hud_gta.gd` / `debug_hud.gd` / `combat.gd` / `main.gd` — see D-041.
>   Evidence: `hud7/plates/hud_vehicle.png`, `hud_foot.png`.
> - **D-034 (decisions)** the race_event MIX veil: migrated to beacon_kit, sign test in
>   `docs/tech/rendering/light-pipeline.md` §7.
> - **D-079** (night brightness): re-measure under the budget tier still owed.
>
> **NEW, PRODUCER-FILED (severity proposed):**
> - **D-101 [S2] The factory's swept shoulder girdle is the "pillow shoulders"** —
>   `character_factory.gd:571-586`, proven by D-036 §02–03. Argument for the skinned flip.
> - **D-102 [S3] Skinned neck** — PRODUCER-CLAIMED IMPROVED 2026-09-06: neck prim r 47/57 →
>   58/66 mm, collar ring grown (`plates_skinned3/face.png`, D-045). The head remains the
>   factory's. QA to rule.
> - **D-103 [S3] Foot officers during a search** — PRODUCER-CLAIMED FIXED: officers converge on
>   `police.search_center` while `search_active` (D-045). Gated; no runtime plate (needs a
>   scripted pursuit probe).
> - **D-104 [S3] Lit windows at noon** — PRODUCER-CLAIMED FIXED in two halves (tower/storefront
>   materials, then the four `_facade()` builders); `meas7/plates_default3/sky_wide.png` shows
>   uniform dark glass at 13:00. QA to rule.
> - **D-103 [S3] Foot officers path to the true player position during a police search**
>   (`foot_cops.gd` reads the player directly); cruisers honour line of sight, officers do
>   not. Fix: police publishes `pursuit_target`, officers read it.
> - **D-104 [S3] Lit-window emission is on at noon** in both legacy and new towers
>   (`sky_wide` plates, both arms) — the night ramp has no daylight suppression.
> - **D-105 [S4] `race_event` D-036 (race left RUNNING forever on foot)** still open.
> - **D-107 [S1] Every skinned body and garment rendered inside out** — the bake's triangle
>   winding was Godot's back face (D-051), so the outer skin was culled and the far wall's inside
>   drawn with inward normals. PRODUCER-CLAIMED FIXED 2026-09-06 (corner swap at both index
>   assemblies, cache v9). Proof: `--shot --shot-debug=normals` at `face`, chest pixel (880,640):
>   before (205,144,27) = facing away; factory body (154,132,229); after (148,167,246) — the
>   former dark-strip pixel went (159,71,17) → (96,181,238). QA to rule; every skinned plate
>   changes. Bar §1 gained a "Facing" row for it.
> - **D-108 [S2] The collar is two detached tabs on a knife-edge neckline** (D-050 crop) —
>   PRODUCER-CLAIMED REWORKED: one shell, a 4 mm-off stand within r 85 of the neck axis from
>   1.500 to 1.578, points tucked under it (`collar7/collar_probe.gd`: 10,655 vertices within
>   80 mm of the axis, was 1,492). v10: stand 1.525–1.578 (53 mm) with the points hanging
>   63 mm from its foot; crew/V/hooded necks paint skin above 1.500 instead of a turtleneck.
>   What it is now: a stand collar with two tabs. What it is not yet: a fold-over leaf with an
>   open front — that needs the neck-base mound resolved finer than the 18 mm body voxel.
>   QA to rule on the r4 `face`/`side`/`back` plates.
> - **D-109 [S3] The factory head's rigid neck showed through the skinned neck** — its flat cap
>   at 1.445 was the "tube set into a hole". PRODUCER-CLAIMED FIXED: `skinned_body` flag makes
>   `_build_head` skip neck, nape and both neck muscles. (Root cause of the visibility: D-107.)
> - **D-110 [S3] Eye whites read startled** (sclera 0.84 with 0.13 emission, 36 mm wide) —
>   PRODUCER-CLAIMED ADJUSTED: sclera 0.74/0.71/0.68, emission 0.06, 34 mm; iris 12.8 mm with a
>   14.8 mm limbal ring; catchlight 3.0 mm. QA to rule at `face`.
> - **D-111 [S3] Body skin and cloth had no surface, and the neck changed shading where the
>   factory head met the body** (StandardMaterial3D body vs skin-shader head) — PRODUCER-CLAIMED
>   FIXED: the palette shader (`city_shaders.PALETTE_SHADER`) with class-keyed pore/cloth
>   micro-normals on a bind-pose UV2 and the head's subsurface terms on skin rows; head gets a
>   triplanar pore normal. Seam-split UV2 (a bright line ran down the spine before). QA to rule.
> - **D-112 [S4] `tools/measure_skin.gd` measured winding with the wrong-handed law** and
>   reported 99.9% agreement on inside-out meshes. FIXED with D-107 (now (c−a)×(b−a)).
> - **D-113 [S3] Four flat-trim garment vertices over the 5 mm rim bar after the body pass** —
>   belt 2 of 3,600 (max 26.6 mm at (0.171, 1.056, 0.002), the waist's side) and apron 2 of
>   12,209 (27.9 mm at (−0.038, 1.125, −0.148)). Both trunk-field shells; the body's waist
>   narrowed under them (D-053). `docs/qa/evidence/character-body/garment-clearance.log`.
> - **D-114 [S4] Fingertips ragged at the 18 mm body voxel** — the hand is a paddle (D-053);
>   its tips are ~45 mm thick and still show marching artefacts at `gait`. Separate fingers
>   need a finer voxel around the hands or rigid hand parts.
> - **D-115 [ruling needed] Codex's two passes are self-certified only** — session flow
>   (`docs/qa/session-flow.md`, 34 checks in `tools/session_test.gd`) and the face pass
>   (`docs/qa/character-design.md`). Gated by Codex (boot, smoke ×2) and re-gated here
>   (D-053 gate), but no QA Director ruling. Their evidence folders are under
>   `docs/qa/evidence/`.
> - **D-116 [S4] `tools/skin_rim.gd` cannot grade the tailored pieces** — collar, placket and
>   both pockets ship as explicit fabric meshes (D-054), not shells; the tool now prints
>   TAILORED and skips them. A clearance measure for fabric grids (distance of each vertex to
>   the body along its normal) does not exist yet.
> - **D-117 [S3] The surface beard read as a flat patch** (codex9/review/cast.png: a bandage
>   moustache on a dark head, a mask beard on a light one) — PRODUCER-CLAIMED FIXED: per-vertex
>   hair/skin stubble mix, feather widened from 7% to 22% of the patch. QA to rule at `cast`.
> - **D-118 [S3] Heat had no reason** — a star lit and the player was never told why (DNA §4
>   "legible"; the checklist's row 11 scored 1). PRODUCER-CLAIMED FIXED 2026-09-12 (D-056):
>   `police.add_heat(n, reason)`, 16 call sites named, the reason drawn under WANTED for 2.6 s,
>   `police.last_reason` public. Evidence: `evidence/mechanics-sept12/busted.png` (banner
>   "WANTED / PROBE: LOITERING"), `mech_probe_headless.log` stage 1 (3/3). QA to rule.
> - **D-119 [S2] There was no second fail state** — evade or die; a player who stopped with the
>   law on him was shot at (heat ≥ 2) or rammed forever (heat 1). PRODUCER-CLAIMED FIXED (D-056):
>   `systems/arrest.gd` + `on_foot.arrest(fine)` — still for 1.8 s with an officer at 2.6 m or a
>   stopped cruiser within 5 m → BUSTED card → the impound lot beside the wrecker, heat 0, fine
>   $150/star, not healed, not repaired. Evidence: `mech_probe_*.log` stage 4 (6/6: card, lot
>   3.7 m from the pad, on foot, heat 0, $-150), `busted.png`. **Known gap, filed with it:** at
>   heat 1 cruisers ram rather than pull alongside, so the cruiser path needs a wedged cruiser;
>   the officer path (heat ≥ 2) is clean. QA to rule on both.
> - **D-120 [S3] The player's ride had no brake lamps, reverse lamps, working headlamps, or a
>   horn** (bar §4 "every verb has feedback": braking had none). PRODUCER-CLAIMED FIXED (D-056):
>   `systems/vehicle_lamps.gd` (private lamp materials — the builder's cache is fleet-wide —
>   brake 1.5 → 6.5, reverse white, night headlamps 5.0 + two shadowless spots), horn on H in
>   `vehicle_audio.gd`, walkers ahead bolt (`pedestrians.honk_at`). Evidence: probe stage 2
>   (7/7: energy 6.50 on S, 1.50 on release, horn plays/stops, 2 spots bound). Traffic lamps
>   remain D-045. The night plate: `evidence/mechanics-sept12/round2/brake_night.png` (22:00,
>   tail lamps flared, both spots lighting the road). QA to rule.
> - **D-121 [S3] `vehicle_damage.gd` assigned a freed cruiser to a typed variable** — every
>   heat clear with a tracked cruiser (the hospital respawn included) logged `SCRIPT ERROR:
>   Trying to assign invalid previously freed instance` at line 61; the §5 boot gate never
>   sees it because the gate never clears heat. PRODUCER-CLAIMED FIXED: checked as a Variant
>   before the cast. Evidence: `mech_probe_headless.log` (the error at probe3, gone at probe4).
> - **D-122 [S2] The protagonist's canon special ability did not exist** (story bible §4: "The
>   Full Eight"; checklist row 20 scored 1). PRODUCER-CLAIMED LANDED (D-056):
>   `systems/full_eight.gd` + `data/mechanics/full_eight.json` + the rope in `hud_gta.gd`.
>   Evidence: probe stage 3 (11/11: key path fires; 0.35 / 0.55 / ×1.30 / chain held; ends at
>   8.0 real-s; all four restored; cooldown 6 s), `full_eight.png` (veil + rope). Tuning is a
>   first guess; QA to rule on feel at the `car_34` vantage with the veil up.
> - **D-123 [S3] At one star a cruiser could only "arrest" by ramming and wedging** (the gap
>   D-119 filed against itself). PRODUCER-CLAIMED FIXED 2026-09-12 (D-057): PULLOVER_* in
>   `police.gd` — a still target at heat ≤ 2 gets a gap-scaled, braking approach that parks at
>   5 m and holds; first cut lit "RAMMED A CRUISER" on contact, second cut busts at heat 1.
>   Evidence: `evidence/mechanics-sept12/round2/mech_probe_headless.log` stage 4 (closest 5.2 m,
>   0.03 m/s, heat 1 at the bust, fine $150), `--wanted-probe` unchanged. QA to rule.
> - **D-124 [S2] No random events; nothing the player did was ever remembered** (checklist rows
>   14 and 19 at 0/1). PRODUCER-CLAIMED LANDED (D-057): `systems/random_events.gd` — STRANDED,
>   a towable dead sedan + waiting driver + beacon at an open curb when the world is quiet; the
>   tow pays $220 + 2 respect and a favor that covers the next bail (persisted in the save).
>   Evidence: probe stages 5–6 (favor spent, $0 fine, the line on the card; spawn 1/1 with a
>   beacon; TTL despawn). No in-play plate yet — the event needs a quiet 75 s drive; QA to
>   take one. QA to rule.
> - **D-125 [S4] Pedestrians ignored a wanted man standing next to them.** PRODUCER-CLAIMED
>   FIXED (D-057): heat ≥ 2 within 12 m → flee straight away. No probe row (needs a ped in
>   range); QA to check by hand at 2★ on a downtown block.
> - **D-126 [S2] The impound pad blocked the delivery** — Milad, playing Hook and Ladder
>   2026-09-13: "the area to drop off the vehicle was blocking the vehicle." Root cause: the pad
>   was a 24 cm StaticBody3D slab with 22 cm lips; a towed box cannot climb a step.
>   PRODUCER-CLAIMED FIXED (D-058): the pad is visual-only paint, flush. Evidence:
>   `evidence/mechanics-sept13/mech_probe_headless.log` stage 7 — before: the box stops at
>   z −7.2 m (the slab face); after: on the pad in 2.2 s. QA to rule by delivering the Brisket.
> - **D-127 [S3] Melee had no opponent and a guard that blocked nothing** (`GUARD_DAMAGE_MULT`
>   "read by nobody yet"; a landed jab did nothing visible). PRODUCER-CLAIMED FIXED (D-058):
>   brave pedestrians square up and punch (6 hp, 1.1 s), guard halves, perfect guard counters,
>   soft lock and step-in, stride cap while swinging. Evidence: probe stage 8 (7/7),
>   `evidence/mechanics-sept13/brawl.png`. QA to rule by hand on a downtown block at fists.
> - **D-128 [S2] Every car crept forward at rest** — Milad, 2026-09-13: "all cars drift forward
>   when they shouldn't." Measured: 3.27 m in 8 s, settling at 0.50 m/s (the rolling-resistance
>   threshold). Root cause: no static friction in the tyre model; springs along body up.
>   PRODUCER-CLAIMED FIXED (D-059): park hold + rolling resistance from rest. Evidence:
>   `evidence/mechanics-sept13/round4/drift_before.log` (3.270 m) / `drift_after.log` (0.000 m);
>   probe stage 0 guards it. QA to rule with a parked car on the frontage slope.
> - **D-129 [S2] Characters stood in an A-pose and walked in a shuffle** (the "super shit" note;
>   review `full.png`: arms straight; `gait.png`: 8° hips at a stroll). PRODUCER-CLAIMED FIXED
>   (D-059): `animate()` rewritten — stride saturates at 1.4 m/s, torso twist, elbow on the
>   forward arm, a living idle. Evidence: `round4/gait_before.png` → `gait_after.png`,
>   `full_before.png` → `full_after.png`. QA to rule at `gait` and `full`; the idle still hangs
>   its hands open (D-114 territory).
> - **D-130 [S3] The downtown roadway was a clean plane with paint on it** (the "not detailed"
>   note; `street_detail.png`). PRODUCER-CLAIMED IMPROVED (D-059): `street_wear.gd` — 230 lids,
>   280 drains, 460 tar patches, three draw calls. Evidence: `round4/street_detail_before.png` →
>   `street_detail_after.png`. QA to rule; the frontage roads and the suburb remain clean.
> - **D-131 [S3] The hands hung as paddles** — straight fingers at rest (review `hand.png`,
>   2026-09-13 morning). PRODUCER-CLAIMED FIXED (D-060): proximal ~15°, middle ~40° flexion in
>   `character_hands.gd`. Evidence: `evidence/mechanics-sept13/round5/hand_before.png` →
>   `hand_after.png`. QA to rule at `hand`.
> - **D-132 [S3] The lips read as a smudge at `face`** despite 3–4 mm crowns. PRODUCER-CLAIMED
>   IMPROVED (D-060): deeper, slightly wider vermilion multipliers. Evidence: `round5/face_before.png`
>   → `face_after.png`. QA to rule.
> - **D-133 [S4] The brawler's punch was a lean; traffic never honked.** PRODUCER-CLAIMED FIXED
>   (D-060): `_brawl_arms` (guard, cock, drive, sag) and `traffic._honk_check` (2.4 s blocked → horn).
>   Evidence: `round5/brawl.png` (arms up); the honk is unprobed — QA by hand at a light.
> - **D-130 update:** the frontage strips now carry wear too (390 lids, 790 patches). Suburb still clean.
> - **D-114 update:** PRODUCER-CLAIMED RESOLVED by Codex's 3 mm hand meshes (palm, thumb, four
>   fingers on the forearm joints; `character_hands.gd`). The paddle is gone. QA to rule at `hand`.
> - **D-108 update:** the collar is now a tailored stand with fold-over points (Codex v17,
>   finished v18) — neither tabs nor turtleneck. QA to rule at the new `collar` review view.
> - **D-106 [ruling needed] The audio-at-quit leak is 10, not ≤6, in WINDOWED runs.**
>   `--verbose` on a windowed `--hudshot` exit lists exactly 5 `AudioStreamWAV` + 5
>   `AudioStreamPlaybackWAV` and nothing else (`gate7/verbose_leaks.txt`) — the same
>   D-023 mechanism, more streams live at quit than a headless boot has. Headless 900-frame
>   boots (the §5 gate) measure 0–6. The producer has NOT widened the row (integrity rule);
>   QA to rule whether §5's exception should read "audio-at-quit instances of any count
>   with zero error lines" or stay at 6 with the gate defined as headless. Ablation priced each pass (SDFGI ~6 ms,
>   TAA ~1.4, volumetric fog ~1.3, SSR <1; the 8192 atlas + Soft High filter unablated).
>   A budget tier (SDFGI c3/0.75 m/16 rays/light every 16 f, fog 48³, SSR 12, 4096 atlas
>   Soft Low over 450 m, TAA only) measures **10/10 stations under 16.67 ms across all
>   three repeats**, worst `hospital_door_night` 15.31 (15.31/16.22/16.39), mean 11.65.
>   It is now the DEFAULT; the full set is `--env-photo`. Decision: D-042. Verification
>   run of the flipped default queued (`meas7/perf_default.log`).


**Build audited — READ THIS BEFORE READING ANY NUMBER BELOW.** The project tree
was being **rewritten while this audit ran** (the MultiMesh `cast_shadow` sweep:
`city_dressing.gd` 01:34, `facade_kit` 01:35, `suburb_dressing` 01:36,
`wild_dressing` 01:36, `scenic_dressing` 01:37, `plaza_dressing` 01:37,
`freeway_dressing` 01:39, `landmarks` 01:40, `greybox_city` 01:40,
`perf_harness` 01:45). Three of my gate boots and one whole 39-shot sweep ran
against a tree that **did not parse** — see D-074 and D-084.

Everything below was therefore measured on a **frozen byte-copy taken at 01:28**,
before the sweep began. That copy is identical to the live tree in every file
carrying a claim under verification — `downtown_types.gd`, `vehicle_body_builder.gd`,
`raycast_vehicle.gd`, `interactables.gd`, `streetlight_glow.gd`,
`hospital_night.gd`, `zz_shot.gd`, all five vehicle JSONs, `character_factory.gd`
— checked by md5, file by file. It differs only in the eleven files the sweep is
touching. **No claim was graded against a file the sweep had already moved.**

**Evidence base (all taken by QA this cycle, nothing carried on a builder's word):**
39 screenshots (full `zz_shot` set re-shot from the frozen copy, zero error
lines), 9 crops at 2–5× NEAREST, photometry over all six night vantages, a
vertex-level in-engine probe reading the **real ArrayMesh vertices** of all eight
vehicle shells in vehicle-local space, a 120-frame prop-freeze probe run on three
consecutive boots, an **A/B collider census with and without `downtown_types.gd`**,
a downward physics ray under each of the six rooftop signs, `--perf --perf-repeat=3`
(10 stations × 3 passes × 300 measured frames), `--smoke` ×3 + ×1 live, and a
**randomised interleaved 80-boot leak experiment** plus 10 stream-split boots.
All probes were added to the frozen copy, never to the project tree.

**Method note.** Seven of the eight claims on the producer's list are **verified
genuinely fixed** — four of them proven by a measurement the builder did not run.
One (D-026) is no longer photographable and is re-scoped rather than closed.
**Three new S2s were found that nobody reported**, one of them a bar row the
producer reported as passing.

---

## COUNTS

| Severity | Open | Change |
|---|---|---|
| **S1 BLOCKER** | 0 | — both CI gates PASS on the live tree as of 01:51 |
| **S2 MAJOR** | 19 | 19 → 19 (4 closed, 1 downgraded, 5 new) |
| **S3 MINOR** | 32 | 26 → 32 (2 closed, 1 in, 7 new) |
| **S4 POLISH** | 5 | 5 → 5 (1 closed, 1 new) |
| **Total open** | **56** | **50 → 56** (7 closed, 13 opened) |
| FIXED (verified this cycle) | 7 | kept below for one cycle, then deleted |
| WONTFIX | 2 | D-012 (now RULED, see below), D-022 |
| NOT REPRODUCED | 1 | D-071 |
| CLOSED unreproduced | 1 | D-008, after three cycles |

By area: vehicles 6, characters 11, world 16, feel 19, ci/audit-infrastructure 4.

**Gates.**
- `--smoke` ×3 on the frozen copy, **byte-identical**, exactly the baseline:
  `SMOKE PASS | pos=(193.000000, 1.097957, 517.465332) moved=40.5m speed=16.7m/s`
  (md5 of all three logs `09732a3e…`). Live tree after the sweep: same line. **PASS.**
- `--headless --quit-after 900` ×90 (80 experiment + 10 split-stream), zero error
  lines and zero nonzero exits **except** the three that caught the sweep mid-edit
  (D-084). Leak rate ruled below. **PASS** under the documented carve-out.
- `--perf --perf-repeat=3`: **one station FAILS the §4b row** — see D-073.
- **Live tree re-checked at 01:57, after the sweep landed:** 12 boots with stderr
  captured — **1 dirty (inside the ruled 13 % interval), zero error lines**, and
  `--smoke` PASS on the frozen baseline line. The sweep's edits parse and the
  gates hold. Its *visual and draw-call effect* is unmeasured (D-086).

---

## THE THREE DEFECTS MOST HURTING THE GAME

**1 · D-076 + D-029 + D-030 — the face got worse.** A **gold-tan ellipsoid now
sits on Book's left cheek**, its edge cutting across his near eye, at the `face`
vantage's own distance. Behind it, unchanged from two cycles ago: the mid-face is
one forward-projecting muzzle with no nostrils, and the far eye is still the
larger of the two and the only one showing sclera. This is the defect Milad
opened the character programme with, and this cycle it acquired a new one.

**2 · D-073 — the post-death respawn frame does not hold 60 fps.**
`hospital_door_night` measures **54.0 fps** (18.52 ms median, p95 18.52, worst
26.73) on the **best of three passes**, with a 1 % spread across passes — this is
not a contention artefact. It is the one frame in the game no player can avoid.
**This directly refutes "nothing under 60 fps."**

**3 · D-039 + D-009 — the Slab, now that it finally has vantages.** From
`slab_side` the car reads as an **open convertible**: the near glass renders
essentially invisible and there is no interior mass, so you see the street
straight through the cabin and the roof reads as a plate floating on two
hairlines. From `slab_rear` the tail is **six stacked horizontal bands** with the
decklid badge **buried in the sheet metal**, its glyph tops sheared off.

Runner-up: **D-015** — the repo beacon is still a salmon column over the sky,
re-photographed this cycle in `face`, `showcase_people` and `slab_side`.

---

# S2 — MAJOR

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

---

# FIXED THIS CYCLE — verified by QA, delete after cycle 4

### D-021  [FIXED verified 2026-08-11]  Tyre vs arch lip, fleet-wide — inside the ORIGINAL 25 mm ceiling
- **Independent vertex-level probe**, reading the real `ArrayMesh` vertices of
  every mesh in each shell, transformed into the vehicle's own local frame — a
  different method from both my cycle-2 Python mirror and the builder's harness.
  Lip = max |x| over meshes named `Arch`; tyre = `track/2 + wheel_width/2`.

  | shell | lip − tyre | ≤ 25 mm? | ≤ 40 mm? |
  |---|---|---|---|
  | Sunbelt Vantage | **22.0 mm** | ✔ | ✔ |
  | Dorado PD Interceptor | **22.0** | ✔ | ✔ |
  | Baron Brisket | **22.0** | ✔ | ✔ |
  | Longhorn Wrecker | **22.0** | ✔ | ✔ |
  | Candyland Slab | **22.0** | ✔ | ✔ |
  | ambient sedan | **22.0** | ✔ | ✔ |
  | ambient truck | **22.0** | ✔ | ✔ |
  | junker | **22.9** | ✔ | ✔ |

  **8 of 8 PASS at 25 mm.** The Slab has moved 55.4 → 22.0 mm. Measured against
  the tyre's *rendered* outer face rather than the nominal one, the five heroes are
  better still — the lathed tyre's bead stands 12.0 mm proud of `track/2 + w/2`, so
  the real lip-to-tread figure on every hero is **10.0 mm**.
- **The mechanism is a genuine invariant, not a per-model patch.** `BEAM_INSET`
  clamps the tub half-width to `tyre − 22 mm`, so `_arch_mesh`'s guard line
  `x = max(x, skin + 0.002)` can never again exceed `tyre + 0.020` and `LIP_CAP`
  binds for the first time. Every future profile inherits it.
- **The two track changes are sound.** Slab 1.65 → 1.80 and Vantage 1.62 → 1.70
  are non-smoke models; the Wrecker's frozen track was correctly left alone and its
  bodywork moved instead. Rollover margin moved the safe way on both.
- **Residue filed as D-082** (wrecker/junker flank 25.6 / 25.1 mm outboard).

### D-023  [FIXED verified 2026-08-11]  Downtown is architecturally uniform — one building, repeated
- **The screenshots are a different city.** `street_north` now carries, in one
  frame: a cream masonry block under a rooftop BLUR+ billboard on steel legs, a
  brown pre-war brick with punched windows and a corbelled cornice, a green-grey
  mid-century ribbon slab with solid end walls, a pale corporate tower with
  expressed corner fins, and two further brick and limestone masses. `plaza` adds
  a black-glass curtain box and two deco ziggurats with lanterns. Against cycle
  1's "every tower a rectangular prism in the same dark brown with the same beige
  window grid", this row is not arguable.
- **NO COLLIDER CHANGED — proven, not asserted.** I built a second sandbox with
  `downtown_types.gd` removed from `EXTRA_LAYERS` and ran an identical collider
  census on both:
  ```
  WITH    downtown_types: staticbodies=688 shapes=790 boxvol=8147452.955 digest=638643.397309
  WITHOUT downtown_types: staticbodies=688 shapes=790 boxvol=8147452.955 digest=638643.397309
  ```
  Identical to six decimal places on a digest of every shape's world position and
  size. `--smoke` byte-identical ×3 on top of that.
- **NO ROOFTOP SIGN LOST ITS ROOF — proven.** A downward physics ray from
  `top + 8 m` under each of the six `city_dressing` rooftop signs hits solid
  geometry at **exactly the recorded top height, delta 0.00 m, on all six**, with
  and without the re-skin. The `signed` → forced-CORP rule works.
- **Cost:** boot log reports 5 287 instances in 17 MultiMeshes + 142 signs, and
  `--perf` shows downtown_day/night both inside budget on this machine.
- **Two things this fix broke, filed separately: D-079** (downtown lost 21 % of its
  night brightness) and the storefront podiums, which are now blank tan bays in
  `plaza` and `street_detail` — folded into D-040/D-046's density row rather than
  given a new number, because they were never verified present.
- **Not verified:** that five canon §6 names landed on buildings. The labels exist
  in `downtown_types.gd` and the type assignment is a rule rather than a
  coordinate, but no vantage frames them legibly and I did not confirm them by
  eye. **Request: an `aerial_downtown` or `magnate` vantage.**

### D-038  [FIXED verified 2026-08-11]  `car_wheel` did not frame a wheel, and no vantage framed the Slab
- Both requests are done. `car_wheel` is now **1.22 m** from the hub (was 4.4 m)
  and the rim is ~200 px across — enough to judge, and it is the frame D-068 was
  closed from. `slab_side`, `slab_34` and `slab_rear` all exist and all frame the
  Slab, which unblocked D-039, D-007 and D-009 in one cycle after two cycles of
  "could not verify". **A separate lens problem remains and is filed as D-080.**

### D-067  [FIXED verified 2026-08-11]  All 26 fire hydrants unfroze on the first physics frame of every boot
- **In-engine probe, three consecutive boots, sampled at physics frames 1, 2, 3,
  4, 5, 6, 30 and 120.** Every sample, every boot, identical:
  ```
  QA3PROP f=1   hydrants=26 loose=0 sunk=0 bins=19 binloose=0 jets=0
  QA3PROP f=120 hydrants=26 loose=0 sunk=0 bins=19 binloose=0 jets=0
  ```
  **26 of 26 hydrants and 19 of 19 bins stay frozen, none sinks, and no water jet
  emits.** Cycle 2 measured 26 of 26 loose at t = 0.03 s on every boot. The
  transform-before-`add_child` fix is correct and complete.
- **It also closed the thing I said I would not report without measuring:** the
  bins share the path and they are clean too.
- Note the striker guard in `_on_prop_hit` still only excludes `StaticBody3D`, so
  the cause is removed but not the mechanism — if any future spawner ever enters
  the tree at the origin again, this comes straight back.

### D-068  [FIXED verified 2026-08-11]  Hero rims rendered as a black void
- Measured on the new `car_wheel` vantage, Rec.709 luminance 0–255 over a 70 px
  disc centred on the rim face: **mean 74.6** (min 6.8, max 200.5, σ 53.1), centre
  cap **117.3**. Cycle 2 measured the same feature at **19.0**. Against the shaded
  asphalt under the car in the same frame (71.7) the rim is now **level**; against
  fully sunlit asphalt (138.1) it is darker, which is correct — a wheel lives in
  its own fender's shadow. **The builder's "level with sunlit asphalt" framing is
  wrong; the fix is not.** Crop `qa3/crop/wheelA_3x.png` shows a bright flange
  ring, eight distinct spokes, a raised centre cap and a recessed dish behind them.
  The root cause the builder found — the lathe's only up-facing surfaces carrying
  the dark material — is consistent with a 3.9× recovery on the exact surfaces that
  face the sky.

### D-069  [FIXED verified 2026-08-11]  County General at night was the darkest place in the game
- Independent photometry, ground half of frame, Rec.709 0–255, same method as
  cycle 2. `hospital_night`: mean **4.23 → 24.31**, median **0.07 → 10.80**,
  share below 8/255 **92.3 % → 40.6 %**, pixels > 64/255 **9 590 → 56 519** (the
  builder reported 56 517; the two-pixel gap is anti-aliasing).
  **It is now the brightest night vantage in the game by mean, and the only one
  with a real median** — every other night frame medians at 0.07–3.01. The frame
  reads: lit ward windows, a lit EMERGENCY canopy, a lit entrance, mast pools on
  the apron and legible stall paint. `suburb_night` is **pixel-identical** to cycle
  2 (mean 9.87, 28 237 bright px) exactly as claimed. **The freeway is not** — see
  D-079.

### D-070  [FIXED verified 2026-08-11]  42 downtown light pools were rotated 45° to the street grid
- Verified three ways. **(a) Code:** `streetlight_glow.gd:246-250` now tests
  `min(|toward.x|, |toward.z|) > DIAG_TOL (0.26 = sin 15°)` and, for those heads
  only, replaces the 8.6 × 5.4 m ellipse with `rot = Basis.IDENTITY` and a
  7.4 × 7.4 m round wash — which is a better description of what a luminaire hung
  over an intersection actually does. **(b) Count:** the boot log prints
  `POOLS: arterial=536 (42 intersection box washes, D-070)` — **exactly the 42 I
  counted independently last cycle**, on the same set, with the instance count and
  order unchanged. **(c) Photograph:** no diagonal ellipse appears in `street_night`.
  Fixed in the file that owned the defect, with no other owner's geometry, draw
  order or RNG touched.

---

# WHAT I GOT WRONG — the 3-versus-6 adjudication

**The builder is right. I was wrong, and the error was mine alone.**

The claim under dispute: at the original 25 mm tyre-vs-lip ceiling, how many of
the eight shells failed on the build the cycle-2 vehicle pass inherited? The
builder measured **3**. My ledger and the bar's amendment both say **6**.

**My own cycle-2 D-021 table answers it, and it says 3.** Those were my numbers,
measured by me, in the same document:

> Vantage +34.0, Interceptor +22.0, Brisket +22.0, Wrecker +34.0, ambient sedan
> +22.0, ambient truck +22.0, junker +22.0, **Slab +55.4**

Three of those exceed 25 mm: Vantage, Wrecker, Slab. **Exactly the three the
builder names.** The other five sit at 22.0 mm and pass the original ceiling
outright.

The "six of eight" sentence was written in **cycle 1**, about the cycle-1 build —
before the D-018 `wheel_x` fix brought the three ambient shells into agreement
with their spawners. It was then **carried verbatim into the cycle-2 ledger and
into the bar's amendment without re-deriving it from the cycle-2 table sitting
eight sections above it.** That is a stale claim laundered into a live document by
the one agent whose entire job is not to do that.

**Consequences, stated plainly:**
1. **The bar's 2026-08-10 amendment is factually wrong as it stands** and should be
   corrected: at the 25 mm ceiling, three of eight shells failed the build the
   vehicle pass inherited, not six. **This is a correction to QA's testimony, not
   to the producer's ruling.**
2. **The loosening was not load-bearing, and now provably so.** All eight shells
   measure inside the *original* 25 mm ceiling today (D-021 FIXED). Nothing in the
   fleet depends on the 40 mm figure.
3. **The standing rule stands regardless, and the producer already said why:** the
   rule is about who may move the goalposts, not about how many shells it saved. A
   bar row widened by the person grading the work is a conflict whether or not it
   changed an outcome. Keep it.
4. **The integrity rule worked in both directions this cycle** — it caught the
   producer once and it has now caught me. That is the correct number of times for
   a rule to catch its own author.

---

# COULD NOT TEST THIS CYCLE

- **A stable build.** The tree moved under the audit (D-084). Everything above is
  graded against a frozen 01:28 copy that is byte-identical to the live tree in
  every file under verification, and differs in the eleven the sweep is rewriting.
  **The sweep's own result (D-086) is therefore unverified by me.**
- **Character rim lift in millimetres, chest span, head-height ratio.** Owed since
  cycle 1, three cycles running. D-027 / D-028 / D-029 / D-030 / D-049 / D-076 /
  D-081 / D-083 are all filed on photographic evidence only. **A Python or in-engine
  mirror of `character_factory.gd`'s surface/sag/lay math remains the single
  highest-value missing measurement in the project**, and the character file has
  not been touched in two cycles while eight defects have accumulated against it.
- **The hydrant jet's appearance** (D-026). Nothing in any harness triggers one now
  that D-067 is fixed. Request: a harness hook that knocks one loose.
- **The five canon §6 building names** (D-023). No vantage frames them legibly.
- **The camera against walls, in tight gaps, on foot vs driving.** `zz_shot` parks
  a free camera and never exercises `chase_camera.gd`. D-050 / D-051 / D-052 remain
  code findings. Request: a harness hook that renders through the gameplay camera.
- **`hospital_door_night` on a quiet machine.** My 54.0 fps and the producer's
  84 fps are both honest; the bar row does not say which one grades. See D-073.

---

*QA Director · 2026-08-11 · 56 open (0 S1 / 19 S2 / 32 S3 / 5 S4) · 7 verified
fixed · 2 WONTFIX/RULED · 1 NOT REPRODUCED · 1 closed · smoke PASS ×3
byte-identical · 90 boots with stderr captured, 11 dirty at the documented
carve-out (13.0 %, CI 7.2–22.3 %), zero error lines outside the D-084 window ·
perf FAIL at hospital_door_night, 54.0 fps*
