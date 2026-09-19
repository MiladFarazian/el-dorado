# loop18 — Character Designer: D-129/D-157, D-102, D-156

## DIAGNOSIS (before any edit)

### D-129 — the crowd is five copies of one man. THREE causes, all measured.

**1. Every rig in the game shares one idle seed. THE line, `character_factory.gd:2212`:**
```
if not rig.has("idle_seed"):
    rig["idle_seed"] = fmod(float(rig.get("phase", 0.0)) * 7.31 + float(rig.get("base_y", 0.0)) * 13.7, TAU)
```
`build()` seeds the dict `{"vis":…, "phase": 0.0, …}` and `base_y` is written at the BOTTOM of
`animate()`, i.e. AFTER this line runs. So on the first call every rig computes
`fmod(0.0*7.31 + 0.0*13.7) == 0.0`, caches it, and never recomputes. Every pedestrian in the
Megaplex breathes, sways and drifts its head in **perfect unison, on the same phase**. The
comment two lines above ("seeded per rig off its own phase so a crowd never breathes in unison")
describes an intent the code cannot deliver.

**2. The idle amplitudes are below the resolution of an 8 m view.** IDLE_SWAY 0.035 rad = 2.0deg
of torso roll; IDLE_HEAD 0.12 rad, gated by a SECOND sine (`sin(0.06t) * sin(0.043t)`) so its
RMS is ~0.06 rad = 3.4deg; IDLE_BREATH 4 mm. Even with distinct seeds, nothing in that list
changes a SILHOUETTE. There is no stance axis at all: every standing rig gets hip_x = 0,
knee = 0.04, sh.z = +-ARM_ABDUCT, el = IDLE_ELBOW. One pose, by construction.

**3. The body is SIX shapes, not a population.** `skinned_character._mesh_for(w,g)` buckets
build into 2 (`w < 1.02`) and girth into 3, and bakes at the bucket's canonical
`cw = [0.97,1.07] / cg = [0.93,1.07,1.22]` — NOT at the character's own w/g. The per-character
`w` survives only in the bone rest offsets, and since `create_skin_from_rest_transforms()` binds
pose == rest, it has zero visual effect. So `random_config`'s `frame` and `girth` draws are
QUANTISED AWAY: the only continuous per-person body axis reaching the screen is `scale`
(0.89..1.07 uniform). Five peds standing together = at most two widths and three girths.

### D-102 — nobody has a neck. Measured, in body space (feet at 0):
- head joint = COLLAR_PIVOT 1.46 + HEAD_PIVOT 0.08 = **1.540**; the head mesh spans
  `HEAD_YB 0.0160 .. HEAD_YT 0.2518` in head space, so **the chin is at y 1.556** and the crown
  at 1.792.
- the collar band SHELL (`skinned_character.gd` P_COLLAR_PTS) is clipped `_sly(1.505, 1.542)`.
  **Its top edge is 14 mm below the chin.** That is the whole available neck: 14 mm.
- the painted skin band on Z_COLLAR starts at 1.523 (1.500 for CREW/V/HOODED), so below that
  the neck prim is painted shirt cloth — a painted turtleneck under a cloth band under the jaw.
- Z_NECK's zone range is `[1.576, 1.620]` — **entirely above the chin**, i.e. dead paint that
  no camera can ever see.
- why the band cannot simply be lowered: the neck-base MOUND. The trapezius ramp's inner end is
  at `(+-0.060w, 1.462)` with r 0.040, so it tops out at **1.502** right beside the neck axis and
  smins into the r-60 neck at k 0.030. The collar probe measured the body at r 85 mm at y 1.530
  and r 60 only by 1.560: the neck does not become a neck until 1.53. A collar can only sit
  where the neck is thin, so it sat at 1.505 and ate the throat.

### D-156 — the armhole hole. Two holes, one cause.
`_pieces` "THE CLOTHES THEMSELVES": shirt `_slx(-ax_w, ax_w)`, sleeve `_slx(+-ax_w, +-0.40)`,
`ax_w = 0.140 * w`. The two shells ABUT on one vertical plane and each closes its cut with a
wall rounded by `k = 0.005` — so each retreats from the plane and the pair leaves a slit that,
where the surface is near-tangential to the cut (the armpit), opens into the lens.
Worse, the plane is in the wrong place below the armpit: at y 1.19 the trunk's own offset shell
reaches **x 0.195** (measured trunk span 0.324 at nominal, x1.07 build, + CLOTH_OFF+CLOTH_TH
0.022) while the shirt is cut at 0.150 and the SHORT sleeve does not start until y 1.265. That
leaves **45 mm of flank with no garment on it** between y~1.13 and 1.265 — a 12 mm-deep cut wall
seen at a grazing angle from `torso`, which is the "unlit interior" in the crop.

## LANDED 1/3 — D-156, the armhole (skinned_character.gd, PARSE 96/0 clean)

**Not** the sleeve moving inboard, and the reason is worth keeping: an inner clip at 0.118 w on
the LONG sleeve (y 0.945..1.500) is inboard of the hip's own shell (~0.155) all the way down, so
it hangs a free-floating cloth tab over the waistband at y 1.010..1.066 where the shirt has not
started. The overlap has to come from the SHIRT.

The shirt's `_slx(-ax_w, ax_w)` is now an OBLIQUE pair of slabs, `|x| <= ax_d + ax_c * y` with
`ax_c = 0.130 * w`, `ax_d = 0.0314 * w` (two `_sl` clips with mirrored normals, which is how you
get a symmetric bound that GROWS with height out of plane slabs). At build w = 1.07:

| y | shirt cut | what it must clear | overlap with the sleeve (0.150) |
|---|---|---|---|
| 1.066 (hem) | 0.180 | trunk shell 0.166; forearm shell inner 0.191 | 30 mm |
| 1.190 (armpit floor) | 0.199 | trunk shell 0.195 | 49 mm |
| 1.265 (short-sleeve hem) | 0.209 | trunk shell ~0.198 | 59 mm |
| 1.500 (shoulder) | 0.242 | deltoid shell outer 0.273 — still cut, edge under the sleeve | 92 mm |

So the 45 mm of bare flank under a short sleeve is covered, and the abutting seam is gone: the
shirt's cut edge is under cloth everywhere along it. Sleeve offset CLOTH_OFF + 0.001 -> + 0.002,
because 1 mm of separation across 92 mm of near-parallel same-coloured cloth is a stipple waiting
for a distant camera; 2 mm is also what an armhole seam ridge looks like. `P_SHIRT_V` (scrubs)
carries the identical clip. CACHE_VER 28 -> 29.

## LANDED 2/3 — D-102, the neck (skinned_character.gd, PARSE 96/0 clean)

**There is no crowd-only cfg key. The player has no neck either** — D-102's own evidence says so
(`cloth-sept13/plates/face.png`, "the jaw runs into the shirt with ~15 px of throat"), and Book
Reyes wears `Neck.SNAP`, which takes the same collar band as every OFFICE, WESTERN and CASUAL
ped. The 15 px IS the 14 mm between the band's top edge (1.542) and the chin (1.556). One defect,
whole population.

Four numbers moved, all in `skinned_character.gd`:

1. **`_prims`, trapezius ramp** — inner end `(+-0.060 w, 1.462) r 40` -> `(+-0.086 w, 1.444) r 38`.
   Crown 1.502 -> 1.482, and it is now 86 mm off the neck axis instead of 60. This is the one
   that matters: the collar probe's "r 85 at y 1.530" was this capsule, not the neck's radius,
   and no collar can sit lower than the mound it has to clear. Outer end (0.178 w, 1.422) and
   k = 0.030 UNTOUCHED, so the measured deltoid span at 1.425 (0.468) cannot move — the
   deltoid cap reaches 0.251 and sets that row.
2. **`_prims`, neck capsule** — base 1.462 -> 1.432, r 62 -> 64, k 0.026 -> 0.024. The column now
   passes through the shoulder mass instead of standing on it. Free neck, shoulder line (1.488)
   to chin (1.556): **68 mm**.
3. **collar band shell** — `_sly(1.505, 1.542)` -> `_sly(1.468, 1.508)`, box lowered and widened
   to +-0.125. A 40 mm stand that still flares onto the mound at its foot where the r 92 wall
   stops it (the fold). Collar points `_sly(1.462, 1.532)` -> `_sly(1.452, 1.504)` so they hang
   from the new band and still stop at the placket's top snap.
4. **`_palette_spec` skin bands on Z_COLLAR** — 1.523 -> **1.502** collared (6 mm under the band
   shell, so the paint boundary is under cloth), 1.500 -> **1.486** for CREW / V / HOODED, whose
   neckline IS the paint boundary.

Also lowered, or they would have been the new "no neck": the hood-down roll (top 1.548 -> 1.516,
it sat 8 mm under the jaw) and the V-neck binding (top 1.512 -> 1.492, it climbed the neck and
read as a choker).

**Visible skin, chin to cloth: 48 mm collared, 70 mm crew** (target 40-60). Z_NECK's zone range
`[1.576, 1.620]` is still dead paint — every millimetre of it is above the chin, inside the head.
Left alone deliberately: the skin BAND on Z_COLLAR does the work and rewriting `_zone_of` +
`ZV` would re-cut the shared mesh for no pixel.

## LANDED 3/3 — D-129, one body / one pose (PARSE 96/0, gdlint 0 findings)

### (a) the seed bug — `character_factory.gd:animate()`
Replaced. `build()` now calls the new `seed_rig(rig, cfg)`, which hashes the cfg's own numbers
(scale, build, girth, asym, brow, skin_rough, outfit, neck, hairdo, shirt) into a
RandomNumberGenerator and writes `idle_seed`, `stance`, `idle_slouch`, `idle_chin`, `idle_yaw`,
`idle_side`, `stance_pose`. **No RNG draw is taken from any caller's stream** — the seed is the
cfg, which is already deterministic — so pedestrians / carjack / foot_cops keep their sequences.
The in-`animate()` fallback stays for a hand-assembled rig but now reads the vis node's own
position, so two of those still differ.

### (b) the amplitudes
IDLE_SWAY 0.035 -> 0.055, IDLE_BREATH 0.004 -> 0.006, IDLE_HEAD 0.12 -> 0.30, IDLE_HEAD_HZ
0.06 -> 0.085, plus a per-person constant head YAW (+-0.34 rad) so a crowd is not all squared to
the lens, and a per-person slouch (-0.035..+0.075 on top of IDLE_SLOUCH) and chin (-0.10..+0.075).
Damped to a quarter for EASY, which is the player's stance — a protagonist with a permanently
cocked head is a bug report.

### (c) THE STANCES — `rig["stance"]`, eight of them, chosen at build from the rig's seed
| stance | odds | what it is | where the hand lands (solved through the rig's offsets) |
|---|---|---|---|
| EASY | 0.18 | the M24 living idle, arms hanging | — |
| HIP_L / HIP_R | 0.30 | contrapposto: free foot 7 cm forward and 5 cm out, that knee unlocked 0.22 rad, weighted knee locked, torso rolled 0.055 onto the weighted leg | — |
| ARMS_X | 0.12 | arms folded, side 0's forearm riding over side 1's | (−0.038, 1.257, −0.162) / one 5 cm higher — they never share a plane |
| POCKETS | 0.15 | both hands in the front pockets, elbows winged 6 cm | (0.202, 0.910, −0.135) |
| HAND_HIP | 0.08 | one hand on the hip, the opposite knee soft, weight on the held side | (0.151, 0.970, −0.136) — on the iliac crest |
| PHONE | 0.12 | phone up at the sternum, chin down 0.28 rad | (0.105, 1.377, −0.299) |
| WIDE | 0.05 | feet 10 cm wider, both hands at the belt, chin up | cop_config's signature |

Mechanically: a 16-float row per stance (hip pitch / hip abduction / knee / shoulder pitch,
**yaw**, abduction / elbow, per side, plus torso roll and head pitch), solved ONCE in `seed_rig`
and cached in `rig["stance_pose"]`, held with a 0.11 Hz +-5.5 % drift so it is a held pose and not
a loop. The load-bearing discovery is the YAW: Node3D composes Ry.Rx.Rz, so `sh.rotation.y`
turns the ELBOW'S BEND AXIS — it is the one number that takes a forearm across a chest, into a
pocket or onto a hip, and `animate()` never drove it before. It is now driven on every path
(zero while walking) and unwound in `aim_pose()`, so a stance cannot leak into a gait or a gun.

### (d) the body spread
`random_config` height 0.89..1.07 -> **0.86..1.10**, frame 0.92..1.12 -> **0.88..1.20**, `_person`
girth 0.86..1.30 -> **0.80..1.40** (same draws, same order, same count). And the reason those
draws were invisible is fixed in `skinned_character.build()`: the six-bucket bake threw the
residual away, so the residual now goes back on as a NON-UNIFORM SCALE above the skeleton —
`x = s * clamp((w/cw)^0.60 * (g/cg)^0.45, 0.94, 1.06)`, `z = s * clamp((g/cg)^0.55, …)`, y
untouched so the feet origin and the 1.75 m envelope do not move. Shoulder width across the
population now spans **0.91..1.13** instead of two values. `_canon(w,g)` is shared with
`_mesh_for` so the thresholds cannot drift apart.

## ONE THING THE PRODUCER MUST FIX, IN A FILE I DO NOT OWN

**`zz_shot.gd`'s showcase row is never animated.** `_build_showcase` (zz_shot.gd:148-159)
builds seven peds plus Book and calls nothing else — no `animate()`, no `_process` that touches
them. **They are standing in the BIND POSE.** That is why `showcase_people.png` shows "feet
together, arms straight down, head level, identical in all five": it is not the idle failing, it
is the idle never running at that vantage. D-129 could not have been seen as fixed there no
matter what I did in the animator, and it cannot be seen as fixed now either.

The fix is one line per rig, in the producer's file (`zz_shot.gd` is already modified in this
tree, so I have not touched it — D-029):

    var rig := factory.build(p, cfg, 0.0)
    factory.animate(rig, 0.0, 1.0, false)     # dt 1.0 -> k = 0.999994: the stance lands in ONE call

A single call with `delta = 1.0` snaps the pose fully (the idle blend is `1 - exp(-12 * dt)`), so
the plate stays deterministic — no per-frame drift, no settle loop. Call it for the cop (k == 6)
and Book too; their stances are WIDE and EASY.

Same note for `character_review.gd`: it DOES animate (90 fixed idle steps, line 66) but builds
only `book_config()`, which is deliberately EASY. Its `face` / `profile` / `full` / `back` /
`collar` views are the right instrument for the NECK and the ARMHOLE; they will not show the
stances. To see those, the showcase row above is the plate.

## WHAT TO CHECK IN THE PLATES

1. `character_review.gd` **`face` / `profile`** — 48 mm of skin between the collar band and the
   jaw on Book (SNAP collar). If the collar still touches the jaw, the trapezius change did not
   take: check the bake actually rebuilt (CACHE_VER 29, six `SKIN LIB ... ready` lines).
2. **`collar` and `collar_normals`** — the band must be a 40 mm stand from ~1.478 to 1.508 with
   its fold at the foot, and the two points hanging to 1.452. A band that has VANISHED means the
   r 0.092 radial wall is now inside the body at that height; a band that is a flat shelf means
   it is not.
3. **`full`** — the armhole. The lens-shaped void at the armpit must be gone, and the new thing
   to look for is its opposite: a visible DOUBLE EDGE down the flank where the sleeve's 2 mm
   step now lands on cloth instead of across a gap. That step is meant to read as a seam.
4. **`torso` in the sweep** (`zz_shot`) — the vantage D-156 was filed at. Crop x310-420 /
   y270-400 at 5x, the same crop as `cloth-sept13/after/torso.png`.
5. **`showcase_people`** — AFTER the one-line fix above. Seven peds should show: at least four
   distinct stances, no two adjacent heads at the same yaw, and a visible spread of shoulder
   width and height. A phone in one pair of hands.
6. **`--skinned-bare`** at `torso` — proves the armhole change is in the garment and not the body.
7. The smoke line must be byte-identical twice: no caller's RNG stream was touched (`seed_rig`
   takes no draw from the caller's rng, and `random_config`'s draw count and order are unchanged
   — only the RANGES of two `randf_range` calls moved).

## STILL OPEN, NOT MINE THIS ROUND
- **D-157 proper**: the stance system only poses a ped that is STANDING. The takeover's club are
  ambient WALKERS (`mission_comin_down.gd` spawns them through `pedestrians.gd`'s walker), so
  they will still cross the lot in step. They need to be stopped and faced at the Slab before any
  of this shows; the moment they are stopped, they get eight stances for free.
- The weight shift is carried by the torso roll because **there is no pelvis bone** — the hips
  hang off the root, so a hip DROP cannot be expressed. That is the next real gain for the idle,
  and it is the same bone the guild lists have wanted since round 10.
- `Z_NECK`'s zone range `[1.576, 1.620]` is still dead paint above the chin.

## GATES
`cd game && … --script res://tools/parse_all.gd` -> **PARSE: 96 scripts, 0 failed** (final run).
`.venv/bin/gdlint game/scripts/world/character_factory.gd game/scripts/world/skinned_character.gd`
-> **Success: no problems found**. Files touched: those two only. CACHE_VER 28 -> 29, so the
producer must bake (`--headless --quit-after 20000`, six `SKIN LIB … ready` lines) before any
plate is judged. Nothing else in `game/` was edited.
