# THE SHADOW POLICY — what casts, what doesn't, and why

Decision **D-028**. Companion to `perf-harness.md`. If you are adding a
MultiMesh to this project, this page is the whole brief.

## The one fact everything follows from

**A MultiMesh is frustum-culled as ONE unit.** One visible instance submits the
whole set to every directional-shadow cascade, every frame. There is no
per-instance culling in the shadow pass. So a `GrassTufts` MultiMesh with 11,919
blades costs the shadow pass all 11,919 the moment a single blade is on screen —
and the cascade renders it as a hard black shard, because the shadow map has no
alpha channel and the blade is a two-sided card with no thickness.

Before D-028: **189 MultiMeshes, 63,563 instances, 55,251 (87%) casting.**
After: **10,579 (17%) casting.** Same 189 sets, same 63,563 instances — this was
a render-flag pass, not a content change.

## The rule

`casts` is a **required parameter with no default** on the MultiMesh builder in
every file that has one. That is deliberate and it is the actual fix. The flag
existing was never the problem; `scenic_dressing.gd` already had it and still
shipped 6,142 casting instances of grass, because it had `= true` as a default
and a default is a decision nobody makes. **A new layer must not compile until
somebody answers the question.**

| Category | Answer | Why |
|---|---|---|
| Flat on the ground | **OFF** | Paint, dashes, crosswalks, curb paint, tyre wear, asphalt scars, manholes (20 mm), grates (30 mm), driveways (40 mm), aprons (30 mm), pavement slabs (60 mm), stall lines, curb ramps, tactile pads. A stripe cannot shade the asphalt it is painted onto. |
| Thin scatter and wire | **OFF** | Grass, bluestem, yucca, prickly pear, tumbleweeds, fence wire, power lines (45 mm), delineators, post-and-rail fencing. Below the cascade's resolving power; renders as shimmer, not shade. |
| Two-sided card flora | **OFF, hard rule** | The shadow map has neither alpha nor thickness. A caster turns a grass card into a black shard and a chain-link panel into a solid wall of shade. This is *worse than no shadow*, not merely wasteful. |
| Relief bolted to a caster | **OFF** | Pilasters, bulkheads, fascias, doors, glazing, house trim, garage doors, sign plates on a mast, grime streaks, posters. Set 10–50 mm proud of a wall that already casts the building's shadow — what they produce is shadow acne. |
| Emissive fixtures | **OFF** | Lamp heads, signal lenses, porch lights, lit windows, beacons, floodlight heads. A surface that is emitting light has no business occluding the sun. Signal lenses doubly so: unlit ones are collapsed to a zero-scale basis, so casting pushed 1,176 degenerate instances through every cascade to draw nothing. |
| Real volumes | **ON** | Buildings, podiums, towers, columns, poles, masts, signal housings, benches, planters, meters, news boxes, shelters, dumpsters, sheds, chimneys, roofs, bike racks, plaza walls, flagpoles, bollards, debris, landmark massing — and **every tree in the game**. |

### Exceptions kept ON against the rule of thumb, with reasons

- **StoreAwnings** (385) — 1.35 m of overhang at 3.3 m. The band of shade on the
  sidewalk is what makes a shopfront read as sheltered rather than painted on.
- **PodiumAC** (159) — free-standing mass on an open podium deck. Without it the
  roof is a flat gray lid from every tower window and from `aerial`.
- **StonebridleStopSigns** (156) — a 0.84 m octagon at 2.25 m, driver eye
  height, the only sign out there big enough to lay a readable disc on pale
  caliche. The 70 mm blades above it are OFF.
- **LotCurbStops** (224) — concrete blocks lying loose on an empty apron. The
  strip of shade under each one is the only thing separating them from paint.
- **BladeSigns** (13) — a projecting sign hangs 1.8 m clear of the wall; the
  shadow crossing the sidewalk is the entire point of a projecting sign. Its
  90 mm brackets are OFF.

### The one judgement call to re-litigate if anybody disagrees

**FwyGuardrails (842) went OFF.** A 0.15 m beam and 0.10 m post at the *deck
edge*: overhead sun hides the shadow under the rail, low sun throws it off the
side of the deck into open air. `freeway_deck` before/after is
pixel-indistinguishable. It is one word in `freeway_dressing.gd` if the call is
wrong.

## Per-file ownership

| file | node prefix | casting after | notes |
|---|---|---|---|
| `world/city_dressing.gd` | `CityDressing/*` | 12 of 45 own sets | The biggest owner. 20,090 → ~2,400 casting instances. |
| `world/facade_kit.gd` | `CityDressing/Store*`, `Podium*`, `Blade*` | 3 of 14 | Storefront relief; awnings, AC and blade signs cast. |
| `world/suburb_dressing.gd` | `suburb_dressing/*` | 7 of 17 | Roofs, chimneys, sheds, trampolines, mailboxes cast. |
| `world/wild_dressing.gd` | `wild_dressing/*` | 7 of 15 | Mesquite, pipes, debris, fence posts cast. |
| `world/scenic_dressing.gd` | `scenic_dressing/*` | 2 of 11 | Only the live-oak motts. |
| `world/plaza_dressing.gd` | `plaza_dressing/*` | 8 of 10 | A plaza *is* its furniture shadows. |
| `world/freeway_dressing.gd` | `freeway_dressing/*` | 5 of 13 | Gantry, sign panels, dumpsters. |
| `world/landmarks.gd` | `landmarks/*` | 16 of 24 | Mostly ON: landmark massing is the point (bar §3). |
| `world/greybox_city.gd` | `GreyboxCity/*` | 3 of 3 | All building mass. Flag stated, never `false`. |
| `world/downtown_types.gd` | `downtown_types/*` | 6 of 17 | **The reference implementation.** Predates D-028. |
| `systems/streetlight_glow.gd`, `slab_cruise.gd`, `hospital_night.gd` | — | 0 | Already unconditionally OFF; untouched. |

## How to A/B a shadow change on a machine that drifts 40%

This project has **no VCS**, and the dev machine measured the same build at
8.33 ms and 14.29 ms twenty minutes apart. Sequential before/after is therefore
worthless — the first attempt at this pass reported every station *slower* while
its draw calls went *down*.

`perf_harness.gd` gained one probe for it:

```
godot -- --perf --perf-mm-audit                    # get the current worklist
godot -- --perf --perf-repeat=2                                    # arm A: as built
godot -- --perf --perf-repeat=2 --perf-mm-cast=GrassTufts,RowPaint # arm B: those back ON
```

`--perf-mm-cast=` forces the named MultiMeshInstance3D nodes back to
`SHADOW_CASTING_SETTING_ON` at boot, so **both arms run from one tree** and can
be interleaved minutes apart. Build the name list by diffing two
`--perf-mm-audit` outputs.

It also works **without `--perf`**, which is how the visual A/B is done:

```
godot -- --shot                        # arm A, all 39 QA vantages
godot -- --shot --perf-mm-cast=<list>  # arm B, same tree, same lens
```

**This is not a convenience, it is a correctness requirement.** The first
before/after screenshot set for D-028 was taken 25 minutes apart and another
agent's camera-FOV fix (D-080) landed in `zz_shot.gd` in between, so half the
"differences" were a lens change. *In a repo with concurrent agents and no
version control, a before/after taken at two points in time is not evidence.*

## What "no visual loss" looked like, in numbers

Per-pixel diff, all 39 vantages, same tree, interleaved. Share of pixels
changing by more than 6/255:

| vantage | changed | vantage | changed |
|---|---|---|---|
| `suburb_street` | 0.28% | `street_north` | 0.17% |
| `street_detail` | 0.21% | `hospital` | 0.03% |
| `freeway_deck` | 0.21% | `aerial` | 0.01% |
| `plaza` | 0.20% | `floodway`, `landmark_stadium` | 0.00% |

Every night vantage ≤ 0.02%. The heat maps put essentially all of it on moving
cars and pedestrians. The only structural change visible at 2× zoom is a
hairline that *disappeared* from the plaza storefront reveals — self-shadow acne
from a pilaster standing 5 cm proud of its wall.

**44,672 instances stopped casting and the game does not look different.** That
is the whole argument, and it is the reason the rule of thumb is what it is:
if a shadow's absence is not visible at a judgement vantage, it was never a
shadow, it was a draw call.

## What this does NOT fix

Downtown got −4.7% of its draws, not the −17.5% the D-027 upper bound
advertised, because that bound stripped the tower masses too. Six
`downtown_types` building sets plus the greybox podiums and columns are most of
downtown's shadow pass and they keep casting — a tower that lays no block of
shade down the avenue is a cardboard cutout. **The remaining downtown headroom
is HLOD/imposters for the skyline, exactly as D-027 said. Not more shadow
flags.**
