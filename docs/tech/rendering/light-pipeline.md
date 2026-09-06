# THE LIGHT PIPELINE — what is on, why, what it cost, and what it breaks

M23. Companion to `perf-harness.md` (how to measure) and `shadow-policy.md`
(what casts). **If you are changing anything global about how this game is lit,
this page and `game/scripts/world/render_pipeline.gd` are the whole brief.**

Before M23 the entire lighting rig was ~50 lines in `main.gd::_build_environment`:
a gradient sky, fog, ACES, glow, SSAO, and one directional light with a 300 m
shadow. No GI, no reflections, no volumetrics, no cascade tuning, no soft
shadows, no exposure, no grade.

## THE TIERS (D-040 → D-042, 2026-09-06) — read this before the rest

The set this page was written for — call it **photo** — measured **17.5–25 ms at every
perf station on a quiet machine** (bar §4b is ≤16.67). It ships behind `--env-photo`.
The **default is the budget tier**: every feature ON, each at a cheaper resolution.

| tier | flag | SDFGI | fog grid | SSR | shadows | AA | mean ms | worst station |
|---|---|---|---|---|---|---|---|---|
| legacy (M22) | `--env-legacy` | off | off | off | 300 m, 4096, hard | MSAA 8× | 7.38 | 11.11 |
| **budget (DEFAULT)** | *(none)* / `--env-budget` | 3 cascades, 0.75 m cells, 16 rays, light every 16 f | 48³ | 12 steps | 450 m, 4096 16-bit, Soft Low, PCSS 0.53° | **TAA only** | **11.65** | **15.31** (hospital_door_night; repeats 15.31 / 15.53 / 16.36) |
| photo | `--env-photo` | 4 cascades, 0.5 m, 64 rays, light every 2 f | 96³ | 32 | 900 m, 8192 16-bit, Soft High | MSAA 2× + TAA | 20.57 | 23.81 |

Ablation on the photo set (`meas7/ablation.md`): SDFGI ≈ 6 ms, TAA ≈ 1.4, volumetric fog
≈ 1.3, SSR < 1; the atlas/filter were never ablated singly. Two intermediate budget
tiers were measured and rejected — 9/10 stations, then 10/10 with zero margin — before
dropping the redundant MSAA 2× under TAA bought the 1.4 ms that made every repeat pass.
**At street level the budget and photo plates are indistinguishable to the eye.** The
census line names the tier (`RENDER: tier=budget …`), so no plate can be misattributed.

**Daylight palette (same decision):** `DAY_HOR` and `DAY_FOG` went from the M8 tan to a
pale blue-white, noon exposure −0.35 → −0.20 stops, `DAY_FOG_DENSITY` 0.0004 → 0.0002/m.
Dawn and dusk keep their canon warmth.

## The one rule this page exists to enforce

**Every feature has a switch and a number.** The dev machine measured the same
build at 8.33 ms and 14.29 ms twenty minutes apart, this project has no VCS, and
three agents boot Godot at once. So a renderer feature is only priced by running
both arms **out of one tree, interleaved** — the same argument `--perf-mm-cast=`
makes in `shadow-policy.md`.

```
godot -- --perf --perf-repeat=3                  the new pipeline
godot -- --perf --perf-repeat=3 --env-legacy     EXACTLY the pre-M23 environment
godot -- --perf --perf-repeat=3 --env-no-sdfgi   price one feature
godot -- --shot --env-legacy                     the same, for the 59 plates
```

| flag | what it does |
|---|---|
| `--env-legacy` | rebuilds the pre-M23 environment byte for byte, **including the GPU state that used to live in `project.godot`** |
| `--env-no-sdfgi` | global illumination off |
| `--env-no-ssr` | screen-space reflections off |
| `--env-no-volfog` | volumetric fog off |
| `--env-no-taa` | TAA off (MSAA 2× alone) |
| `--env-no-farshadow` | shadow distance back to 300 m, cascades kept |
| `--env-no-grade` | LUT + contrast/saturation off |
| `--env-no-scatter` | Rayleigh/Mie off, M16 keyframe dome alone |
| `--env-no-exposure` | the time-of-day exposure ramp off |
| `--env-sdfgi-converge=N` | SDFGI temporal accumulation, N ∈ 5/10/15/20/25/30 |
| `--env-autoexposure` | probe only — auto exposure instead of the ramp |
| `--env-ssil` | probe only — screen-space indirect lighting on |

`--env-legacy` deliberately does **not** read `project.godot`. Before M23 the
`[rendering]` section held exactly one line (`msaa_3d=3`), so "today's
environment" was the engine defaults plus that, and those defaults are hardcoded
in the kit. Legacy therefore stays a true arm A no matter what `[rendering]`
grows to later.

## The boot census line (D-032: every layer prints one)

```
RENDER: sdfgi=on c4 cell0.50 ssr=on s32 volfog=on 96x96 aa=msaa2x+taa \
        sky=custom(m16)+scatter shadow=900m/pcss0.53deg grade=lut32 exposure=tod
RENDER: sdfgi=legacy ssr=off volfog=off aa=msaa8x sky=custom(m16) \
        shadow=300m/hard grade=off exposure=off
```

## Who owns what

| thing | file |
|---|---|
| the rig — every global light decision, all the flags, the LUT | `scripts/world/render_pipeline.gd` |
| everything that CHANGES with the clock or the weather | `scripts/systems/sky_weather.gd` |
| the three lines that build it | `scripts/main.gd::_build_environment` |
| GPU state mirrored for the editor | `project.godot` `[rendering]` |

`main.gd` no longer knows what a cascade is. `sky_weather` still owns sun
angle/energy/colour, sky colours, fog, ambient, and now also volumetric fog
density/albedo/emission, the exposure ramp, and the scattering blend — because
all of those are functions of the clock and the storm, and the clock and the
storm already live there.

---

## 1. GLOBAL ILLUMINATION — SDFGI

This world is **generated at boot**. There is no author-time step to bake into,
so lightmaps and baked probes are not options; SDFGI is the only real-time GI in
Godot 4 that needs no offline pass. That is the whole argument for it.

| knob | value | why |
|---|---|---|
| `sdfgi_cascades` | 4 | with the cell size below, 256 m of GI — matched to the shadow range |
| `sdfgi_min_cell_size` | 0.5 m | cascade 0 = 32 m ≈ a downtown block |
| `sdfgi_use_occlusion` | on | the leak control; see the artefacts section |
| `sdfgi_read_sky_light` | on | the sky is this game's dominant light source |
| `sdfgi_bounce_feedback` | 0.5 | above 0.5 sunlit concrete runs away |
| `sdfgi_y_scale` | 75 % | flat sprawl, but 150 m towers — 50 % smears floor to floor |
| frames to converge | **30** | measured; see below |
| frames to update light | 2 | the sun crosses 24 h in 600 s here |
| ray count | 64 | |

**Ambient had to give way.** SDFGI and `AMBIENT_SOURCE_SKY` are both "light
arriving from the environment"; with both at full strength the world
double-counts and noon goes milky. `sky_weather` now scales
`ambient_light_energy` by **0.58 by day, 0.96 at night** — not a flat factor,
because SDFGI reading a night sky returns almost nothing, so night must keep
what it had. This is also the D-079 lever.

### The artefacts, honestly, with vantages

1. **It is temporally noisy at day vantages, permanently.** Two independent
   boots photographed at the *same* depth (309 frames after the camera enters
   the station), `downtown_day`, whole-frame mean Rec.709 luminance:

   | arm | pixels differing > 6/255 | mean luminance |
   |---|---|---|
   | `--env-no-sdfgi` (control) | **0.38 %** | −0.01 |
   | SDFGI, converge = 10 | 6.85 % | −1.77 |
   | SDFGI, converge = 30 | 4.36 % | +1.13 |

   The control proves the rest of the frame is deterministic (traffic is
   seeded), so that residual is SDFGI and nothing else. **The project's own
   measuring instrument — plate photometry — gains a ±2 luminance noise floor
   at day vantages that it did not have.** Converge = 30 was chosen because it
   is the quieter of the two.

2. **Night is unaffected.** `downtown_night` moved +0.04 against a −0.14
   control. SDFGI contributes essentially nothing at 21.8 h, which is why the
   ledger's night photometry (D-014 / D-069 / D-079) survives this pass.

3. **A camera teleport needs ~60 frames, and `zz_shot` gives 8.** Settle at
   `downtown_day`, against a 309-frame plate: 10 frames is **−5.21** luminance
   short, 30 frames −4.66, 60 frames −1.14 — and −1.14 is inside the flicker
   floor above, so 60 is where settle stops being the limiting term.
   `zz_shot.gd::_settle_and_save` awaits **eight** `process_frame`s.
   **Every day plate in the QA sweep is therefore captured ~5 % dark.** The fix
   is one number in a file this mission does not own; the request is in the
   report and `render_pipeline.SETTLE_FRAMES = 60` records the answer.

4. **Leaking through thin walls is bounded by the cell size, and stated up
   front.** A 0.5 m cascade-0 cell cannot represent a 0.2 m podium wall. This is
   a budget, not a bug to be surprised by: the alternative is a smaller cell,
   which costs range, which costs the whole point of GI on a 1 km map.

---

## 2. REFLECTIONS — SSR

Wet asphalt is a signature look here: `sky_weather` soaks the road in 14 s and
dries it over **105 s**, so the street is still visibly damp long after a
supercell has moved on. A wet road with no reflection is a grey road.

| knob | value | why |
|---|---|---|
| `ssr_max_steps` | 32 | at 1600×900 the other 32 buy reflection length on surfaces that are, in this game, nearly all rough |
| `ssr_fade_in` | 0.15 | keeps the reflection off the contact point, where SSR has no data and smears |
| `ssr_fade_out` | 2.0 | ends the reflection before the screen edge, so nothing pops when the camera turns |
| `ssr_depth_tolerance` | 0.2 | |

**Known and inherent:** SSR can only reflect what is on screen. A car reflected
in wet asphalt loses its reflection as it leaves the frame, and anything behind
the camera is simply absent. That is the technique, not a defect — the fix is
reflection probes, which is a separate decision with its own cost.

Tune it live with `city_shaders.set_wetness(1.0)`.

---

## 3. VOLUMETRIC FOG

Owned by `sky_weather` because everything about it is a function of the clock
and the storm.

| state | density | albedo |
|---|---|---|
| noon | 0.0055 | neutral-cool 0.88/0.90/0.95 |
| **the shaft hour** | **0.0230** | sun-warm 1.00/0.82/0.66 |
| night | 0.0120 | 0.62/0.66/0.82 + self-emission |
| supercell | 0.0340 | green-grey 0.66/0.72/0.68 |

The shaft hour is a hump on **sun elevation**, not on the hour, so it survives
anybody retuning `DAY_LENGTH`: centred at 14° with a 22° half-width, which puts
it across roughly 16:30–19:30 game time. Anisotropy runs 0.55 clear (forward
scattering — the beam toward the sun) to 0.10 in a storm, where the light really
is coming from everywhere. Night gets a whisper of self-emission (energy 0.22,
colour 0.10/0.12/0.19) and nothing else does: that is the city's own light dome,
the thing that puts a distant skyline in a bowl of glow instead of a black hole.
It is zeroed in a storm, because a shelf cloud smothers a light dome.

Two things guard the sky: `volumetric_fog_sky_affect = 0.0` and the existing
`fog_sky_affect = 0.1`. Letting volume fog repaint the dome would do exactly
what `fog_sky_affect = 1.0` did in M8 — the whole sky read as tan haze at noon.

`light_volumetric_fog_energy` defaults to 1.0, so the 492 Stonebridle porch and
flood lights and the 14 hospital fixtures grew visible cones **with no change to
any of those files**. That is the cheapest spectacle in this pass.

Froxel grid is 96×96×96 (engine default 64³); 128 m of volume length.

---

## 4. SHADOWS — and D-025

> **D-025 [S2]** *Nothing casts a shadow beyond 300 m — the aerial view is
> completely flat.* `aerial` shoots from (880, 300, 880) at (300, 0, 230) —
> **921 m**, 3× beyond the shadow range. 108 towers of genuinely varied height
> and not one of them puts a shadow on the ground.

Fixed by raising `directional_shadow_max_distance` from **300 m to 900 m** over
four hand-split cascades. The splits are front-loaded so the range comes out of
the far cascade, not out of the street the player is standing in:

| cascade | split | reaches | what lives there |
|---|---|---|---|
| 0 | 0.04 | 36 m | the street, cars, people, kerbs |
| 1 | 0.12 | 108 m | the block |
| 2 | 0.33 | 297 m | the district — the whole old range |
| 3 | 1.00 | 900 m | the skyline, and `aerial` |

`directional_shadow_fade_start = 0.92` dissolves the last 8 % instead of
clipping it, and `blend_splits` is on so no cascade seam crosses a street.

**PCSS.** `light_angular_distance = 0.53°` is the sun's real angular diameter,
and it is the single number that stops every shadow in the game having the same
razor edge whether it is cast by a kerb or by a 150 m tower. It needs a real
filter to sample with, so `soft_shadow_filter_quality` goes to **Soft High**;
at the engine default (Soft Low) the same setting reads as jitter, not penumbra.
`shadow_normal_bias` goes 1.0 → 1.4 because a 900 m cascade needs it.

**The atlas is where the money went.** A 900 m cascade set in the default 4096
atlas is mush. `directional_shadow/size = 8192` at 16 bits is **128 MB** of
shadow map. That is the price of D-025 and it is a memory price, not only a
frame-time one. `--env-no-farshadow` puts the distance back to 300 m with the
cascades and PCSS kept, which is the tier to ship if the memory is refused.

**This does not re-open the shadow policy.** D-028's rule stands unchanged: 17 %
of MultiMesh instances cast, and a longer cascade does not make grass worth
casting. It makes the 108 tower masses that *already* cast reach the aerial.

---

## 5. THE SKY — why there is no PhysicalSkyMaterial here

The mandate asked for `PhysicalSkyMaterial`. **Shipping it would have been a
regression, and the reason is worth writing down so nobody re-proposes it.**

`main.gd` builds a `ProceduralSkyMaterial`, but that is only a boot value:
`sky_weather.gd::_install_scenic_sky()` **retires it on frame 0** (`_sky_mat =
null`) and installs a custom sky shader that already carries two projected cloud
decks with true perspective and self-shadowing, a sun disc that swells from
0.016 to 0.062 rad and reddens as it drops, a moon with a terminator and maria,
a star field with a Milky Way band, and two layers of horizon haze.
PhysicalSky has **none** of that and goes black at night.

So the physics came to the dome instead. `scatter_sky()` in that shader is
analytic Rayleigh/Mie single scattering with **no raymarch**: real sea-level
coefficients (Rayleigh 5.8 / 13.5 / 33.1 × 10⁻⁶ per metre — the λ⁻⁴ that makes
a zenith blue and a sunset red is *in those three numbers*, not in a colour
ramp), Mie 21 × 10⁻⁶ with g = 0.76, scale heights 8000 m and 1200 m, and the
flat-slab air-mass approximation `H / (ray.y + 0.055)` — exact at the zenith and
growing without bound at grazing angles the way the real one does, which is the
only part a table-flat Texas horizon needs. About 30 ALU, no loop, so the
realtime radiance cubemap still keeps up with a 600 s day.

It **blends over** the M16 keyframes rather than replacing them, at
`scatter_gain = lerp(0.62, 0, storm_mix) × smoothstep(−1°, 8°, elevation)`:

- **zero below the horizon**, so the night keyframes — which carry the entire
  night-photometry history in the defect ledger — are bit-for-bit untouched;
- **zero in a storm**, so `STORM_HOR`'s supercell green survives. It is canon and
  no atmosphere model knows about it.

The star field the mandate asked for already existed. Nothing was added to
`city_textures.gd` (not this mission's file) and nothing needed to be.

---

## 6. EXPOSURE AND GRADE — and the one thing that must not move

`glow_hdr_threshold = 1.05` is a **project-wide contract**: D-032 re-tuned 827
strip lights and 22 tower collars against it. Anything that scales light before
the glow pass moves every emissive in the game relative to that threshold. So:

- **The grade is post-tonemap.** `adjustment_enabled` with contrast 1.06,
  saturation 1.08 and a generated **32³ colour-correction LUT**. Because Godot
  applies adjustments after tonemapping, the grade *cannot* change what crosses
  1.05. That is the whole reason the look lives here and not in exposure.
  The LUT is a split-tone: shadows cool (0.94/0.98/1.06), highlights warm
  (1.045/1.005/0.955), an 0.008 toe lift so black is charcoal rather than a
  hole, and a cubic shoulder at 0.94 so a specular highlight keeps its hue
  instead of blowing to flat white. Generated in code — zero asset files, per
  project doctrine.
- **Exposure is a deterministic time-of-day ramp**, in stops: −0.35 at noon,
  +0.10 at dusk, +0.55 at night, +0.28 under a supercell, written to
  `WorldEnvironment.camera_attributes.exposure_multiplier` by `sky_weather`.
  It **does** sit before glow, so it is measured, not assumed — see the cost
  table's `--env-no-exposure` row.

### Why auto exposure is NOT shipped

Every quality number in `docs/qa/defects.md` is screenshot photometry, and
`zz_shot.gd::_settle_and_save` gives a plate 8 process frames.
`CameraAttributesPractical.auto_exposure_speed` converges over roughly `1/speed`
**seconds**, so plates would be captured mid-adaptation and the ledger's
photometric history would stop being comparable to itself. A renderer feature
that breaks the instrument the project measures quality with has to clear a much
higher bar than "it looks nice", and it does not.

It is built and reachable behind `--env-autoexposure` for anyone who wants to
price it. The shipped ramp gives the same result — night dark but readable, noon
not washed — as a pure function of `time_of_day`, which means the same hour
always produces the same plate.

### DOF: deliberately not shipped

Far DOF is wrong for an open world (the skyline is the point). Aim DOF was
considered — `main.systems["combat"].get("is_aiming")` is readable — and
rejected for now: the constraint is that the target must never be blurred, and
the target in this game can be at any distance from 2 m to 200 m, so a fixed
far-blur distance would blur the thing you are shooting at some ranges. It needs
a focus distance driven from the aim raycast, which belongs to whoever owns
combat, not to this file.

---

## 7. D-034 — the last MIX veil, and the sign test that settles it

`race_event.gd` built the Floodway Sprint's two gate markers as **34 m emissive
BoxMeshes at `TRANSPARENCY_ALPHA` (MIX) alpha 0.4 / 0.25** — the exact mechanism
D-032 measured and D-033 fixed in `beacon_kit.gd`. Migrated to the kit. Three
arms, **one tree, one boot each**, same camera, via a temporary
`aa_race_shot.gd` harness (since deleted). Arm `none` = beacons hidden = the
reference; every number is a differential against it at threshold 6/255.

| vantage | BEFORE covered | BEFORE dR | BEFORE % of covered px made DARKER | AFTER covered | AFTER dR | AFTER darker |
|---|---|---|---|---|---|---|
| `race_near` (11 m) | 248,449 (17.25 %) | **−9.68** | 8.6 % | 145,864 | +2.71 | 1.3 % |
| `race_mid` (60 m) | 33,526 (2.33 %) | **−8.10** | 24.3 % | 6,318 | +4.14 | 1.9 % |
| `race_far` (220 m) | 4,248 (0.29 %) | **−7.71** | **36.4 %** | 1,044 | +5.54 | 0.7 % |
| `race_pair` | 39,933 (2.77 %) | **−10.30** | 22.3 % | 8,459 | +3.75 | 1.2 % |
| `race_mid_night` | 33,012 | +24.25 | 0.4 % | 13,764 | +4.29 | 0.1 % |
| `race_pair_night` | 38,903 | +4.42 | 0.2 % | 18,352 | +0.26 | 0.4 % |

**The one number that settles it: `dR` is NEGATIVE at every daylight vantage in
the BEFORE arm.** A cyan MIX veil *subtracts red* from whatever is behind it. An
additive light source cannot subtract any channel. In the AFTER arm dR is
positive everywhere. This is the same sign test D-032 used — it was the blue
channel there, because that beacon was orange.

**The budget also ran backwards, and now does not.** At 220 m — the range a
beacon exists for — the old box painted 4,248 px for a median luminance lift of
only **+5.10**; the kit paints 1,044 px for **+10.44** median, 95th percentile
**+36.65**, which is 2.4× D-033's documented findability floor of 15.0. Less
area, more light, at the range that matters.

The 6 Hz emission pulse was removed with it: the kit's `Driver` owns
`emission_energy_multiplier` (it writes the distance gain there every frame), so
a second writer would fight it — and a 6 Hz flicker on an additive column is the
attention-grab those two cycles existed to remove. The two gates are told apart
by colour (cyan next, blue after), energy (1.30 vs 0.85), the ground corona
under the live one, and the HUD line that already prints the gate number and a
live metre count.
