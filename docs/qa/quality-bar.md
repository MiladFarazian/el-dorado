# THE QUALITY BAR — what "GTA-quality" means here, in numbers

Milad's standing verdict (2026-08-10): *"this is nothing close to the quality of what I want."*
He is the customer and he is right. This document exists so nobody — human or agent —
has to ask him again what "good" means. **It replaces him as the judge.**

## The three laws of this document

1. **A criterion that cannot be measured or photographed is not a criterion.** Every
   line below is either a number, or a named vantage a screenshot must survive.
2. **"Better than before" is not a pass.** The bar is absolute. A thing is DONE when it
   meets the bar, and OPEN at every other time, including when it improved a lot.
3. **The reviewer's job is to find what is wrong, not to confirm what is right.** A QA
   pass that reports no defects is presumed lazy and is re-run.

## Why this exists (the failure pattern it prevents)

Five times this project shipped something the producer signed off on and Milad rejected:
plank torsos, elbows that bent backwards for five milestones, shoulder orbs, cars whose
wheels stood a quarter-metre proud, faces judged from a flattering middle distance.
**Every one was caught by measuring or by looking from an unflattering angle** — and
every one had been "reviewed" first. The difference between a review that works and one
that doesn't is: *did somebody put a number on it, and did they look from the bad side?*

---

## 1. CHARACTERS

| Criterion | Bar | How to check |
|---|---|---|
| Silhouette at 1 m | Reads as a person from `face`, `torso`, `side`, `back` | screenshots, all four |
| Feature rim lift | Any mounted piece ≤ 5 mm proud of the surface it sits on; nothing "floating" | measured (mirror the surface math) |
| Chest width incl. arms | **0.48–0.56 m at NOMINAL scale (1.0)** — a proportion check, not an absolute one | measured |
| Chest width, absolute | 0.40–0.58 m including the height roll (real adult bideltoid breadth) | measured |
| Head height | total height ÷ 7.0–7.8 (hat excluded) | measured |
| Joint direction | Elbows flex FORWARD, knees BACKWARD | position harness, never angles |
| Surface intersections | No z-fight stipple, no visible seam where two masses cross | `torso`/`side` screenshot |
| Mid-face at 4× zoom | Reads as a face, not a snout | crop |
| Crowd variety | No two adjacent peds read as the same person | `showcase_people` |
| Facing (added 2026-09-06) | Every visible character surface is a Godot FRONT face: in `--shot --shot-debug=normals`, a camera-facing patch (the chest at `face`, plate pixel ~(880,640)) is BLUE (B > R+40), never yellow/orange | normal-buffer plate; D-051 |

## 2. VEHICLES

| Criterion | Bar | How to check |
|---|---|---|
| Tyre vs flank | Tyre outer face 0–40 mm **inboard** of the arch lip's outer edge | measured |
| Wheel Ø : body height | 0.42–0.52 (car), 0.40–0.46 (truck). **Height = ground to the highest point of the ROOF**, excluding masts, lightbars, beacons and bed rails | measured |
| Sill to ground | 130–170 mm (car), 300–350 (lifted truck). **Sill = the lowest point of the ROCKER TRIM** (what a viewer reads as the car's bottom edge), not the tub floor | measured |
| Arch gap over tyre | 45–90 mm (car), 90–140 (truck), measured from the tyre's top to the **inner opening edge** of the arch (the dark cut), not the proud lip | measured |
| Surface | A character line the highlight terminates on; no flat-value flank | `car_34`, `car_side` |
| Silhouette ID | Each model identifiable at 50 m by outline alone | `showcase_cars` |
| Cabin | Interior visible through glass; no empty aquarium | `car_34` |

## 3. WORLD

| Criterion | Bar | How to check |
|---|---|---|
| Street furniture density | A cue (paint, sign, pole, drain, curb detail) every ≤ 30 m | `street_north`, `street_detail` |
| Night identity | Every district has a distinct night read; no black voids | `street_night`, `suburb_night`, `freeway_night` |
| Sky | Clouds, celestial body, haze at all four times of day | `sky_wide`, `sky_night` |
| Landmark legibility | Each district has ≥ 1 structure nameable from a screenshot | `aerial` |
| No floating geometry | Nothing intersects or hovers visibly | every vantage |

## 4. FEEL / MECHANICS

| Criterion | Bar | How to check |
|---|---|---|
| Input → response | On-foot verbs respond within 100 ms; no input eaten | harness |
| The HUD never lies | Any indicator is rendered FROM the value it reports | code review + harness |
| Every verb has feedback | Sound + visual + camera response on every action | play/harness |
| No dead ends | No state a player can enter and not leave | harness |

## 4b. PERFORMANCE (added cycle 1 — QA correctly noted the bar had no row)

| Criterion | Bar | How to check |
|---|---|---|
| Frame time, EVERY perf-harness station, day and night | ≥ 60 fps at `best` of ≥ 3 passes, **on an otherwise quiet machine, vsync off** | `perf_harness.gd` — manual at `docs/tech/rendering/perf-harness.md` |
| Boot to playable | ≤ 20 s | `perf_harness.gd` |
| Contention caveat | A station that passes quiet but fails under normal workstation load is an **S2**, not a pass — file it with both numbers | two runs |
| No per-frame work over batched instance sets | O(1) per frame, not O(instances) | code review |

## 5. NON-NEGOTIABLE (CI)

- `--smoke` twice, byte-identical: `SMOKE PASS | pos=(193.000000, 1.097957, 517.465332) moved=40.5m speed=16.7m/s`
- `--headless --quit-after 900 2>&1`: zero error lines.
  **THE `2>&1` IS MANDATORY AND IS NOT A STYLE CHOICE (QA cycle 2, D-075).** Godot
  writes `WARNING:`, `ERROR:` and `SCRIPT ERROR:` to **stderr only**. An agent running
  `godot ... > run.log` sees a clean log **forever, at any sample size** — QA proved it
  with split-stream boots (0/10 in stdout, 1/10 in stderr) and caught three of its own
  boots passing a tree carrying **44 parse errors with exit code 0 and clean stdout**.
  **Any gate result quoted without `2>&1` is void.** This invalidated at least three
  reported leak rates, including a "0 dirty in 50 boots".
  **REDIRECT ORDER IS PART OF THE RULE (added 2026-08-11, producer, after committing
  this exact error myself while gating cycle 5).** `2>&1` is not a token you sprinkle
  anywhere in the line — it is positional:
  - ✅ `godot ... > run.log 2>&1` — stdout to the file, then stderr follows it. Correct.
  - ❌ `godot ... 2>&1 > run.log` — stderr is duplicated to the CURRENT stdout (**the
    terminal**) *first*, and only then is stdout redirected. **The file never receives a
    single stderr line.** It contains `2>&1`, it looks compliant, and it is void.
  This produces the identical failure mode D-075 describes — a permanently clean log at
  any sample size — while *appearing* to satisfy the rule, which makes it strictly worse
  than omitting `2>&1`. I caught it only because the leaked-ObjectDB warning printed to
  my terminal while the log I was grepping reported zero. **Grep the file for a line you
  KNOW should be there before trusting a clean gate.**
  **Documented upstream exception (D-023):** `≤ 6 ObjectDB instances were leaked at exit`
  with zero error lines is the known Godot 4.7.1 audio-at-quit defect in `ambience.gd`.
  Tolerated only at ≤ 6 and only with zero error lines. Any higher count, or any error
  line, fails the gate.
  **Rate is unstable and must not be quoted from one small batch** — measured across
  cycles at 2/19, 3/12, 5/12 and 8/17 of boots. The producer once escalated it as the
  project's worst defect on a 12-run sample; QA's 19-run sample refuted that. If you
  need the rate, run ≥ 20 boots. It is still present as of cycle 1 (3/12).
- Physics sacred: colliders, seeded RNG draw order, and the smoke corridor
  x∈[174,212] ∧ z∈[424,576] are frozen.

## Amendments to this document — the integrity rule

**When a bar row changes, the change is recorded here with its date, its reason, and
who asked for it.** A bar that quietly loosens is worse than no bar, because it
launders failures as passes.

- **2026-09-06, producer — NEW ROW §1 "Facing", a tightening.** D-051 found every skinned
  body and garment had rendered as back faces for three milestones: the outer skin was culled
  and the far wall's inside drawn with inward normals. No existing row could catch it — the
  silhouette rows pass either way, and the bake audit's own winding metric encoded the same
  wrong-handed rule at 99.9%. The new row is measurable in one plate: the normal-buffer view
  must show a camera-facing patch as blue. Nothing was loosened.
- **2026-08-11, producer — chest-span row split, at a builder's request.** The row was
  **mathematically unsatisfiable as written** and had been since cycle 1: span scales
  with the per-person `scale` roll (0.89–1.07), so to lift the 1.60 m corner above
  0.48 m the nominal figure must exceed 0.539, while keeping the 1.92 m corner under
  0.56 m requires it to stay below 0.523. **No fixed absolute window can contain a ±10%
  height roll.** It is now two rows: a **proportion** check at nominal scale (0.48–0.56)
  and an **absolute** sanity range (0.40–0.58) matching real adult bideltoid breadth.
  The builder measured the problem, declined to widen the row itself citing the
  integrity rule, and asked — which is exactly the behaviour the rule is for.
- **2026-08-10, producer.** Three ambiguous definitions pinned at QA's request (Ø:H
  denominator, sill reference, arch-gap edge) — these were *disambiguations*: the rows
  were previously unmeasurable, and a builder could pass or fail the same car depending
  on a definition nobody had fixed.
- **2026-08-10, producer — A GENUINE LOOSENING, flagged by QA in the same cycle it
  landed.** Tyre-vs-lip widened from 0–25 mm to 0–40 mm inboard while the vehicle fix
  was in flight, and the builder then sized `LIP_CAP` to 34 mm against the new ceiling.
  **CORRECTED 2026-08-11 by QA's own adjudication: THREE of eight failed at 25 mm**
  (Vantage, Wrecker, Slab), not six. QA had carried a cycle-1 figure about a pre-fix
  build verbatim into a live document without re-deriving it from its own table eight
  sections above — "a stale claim laundered into a live document by the one agent whose
  job is not to do that," in its words. All eight shells now sit inside the **original
  25 mm**, so the loosening was never load-bearing. **The standing rule below stays
  anyway: it is about who may move goalposts, not about how many shells it saved — and
  it has now caught its own author as well as the producer, which is the correct number
  of times for a rule to catch each.** QA's words: "the rows
  pass as written and I re-measured them myself; but the rows got easier at the same
  moment the work landed, and that belongs in the record." It does. The 40 mm figure is
  defensible on its own terms (a real arch lip does stand proud of the tyre), but it was
  set by the person grading the work, which is the exact conflict this loop exists to
  remove. **Standing rule from here: the producer may not widen a bar row in the same
  cycle as a fix that row is blocking. Widen it before, or after QA has ruled.**

## Severity

- **S1 BLOCKER** — a gate fails, or the game is unplayable/unshippable.
- **S2 MAJOR** — Milad would reject it on sight. Anything failing a bar above.
- **S3 MINOR** — visible to a careful eye at a judgement vantage.
- **S4 POLISH** — noticeable only when hunting.

Fix order is strictly S1 → S2 → S3. **S2s are the whole job**; that is the band the
player actually sees.
