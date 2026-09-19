# PED ZONES — findings (loop 14, AI & Traffic)
Owner: game/scripts/systems/pedestrians.gd (+ new game/data/mechanics/ped_zones.json)

## Ground truth read before writing (coordinates are from the BUILT world, not the brief)
- `cedar_cliff.gd`: Juárez Blvd is 12 m wide at z 800, run x −480..285. Concrete sidewalk
  slabs are `_solid(170 x 0.10 x 4, at (-148, -0.01, 800 ± 9))` -> x −233..−63, z 789..793
  and 807..811, TOP y = +0.04. Storefront bodies (WITH colliders) are z 780..790 (north row)
  and 810..820 (south row), so the walkable strip is z 790.2..793 / 807..809.8.
  -> polylines at z 791.7 and z 808.3, width 1.2 m: inside the brief's z 800±6..±10 band,
  clear of both shop colliders. East end pulled back to x 44: the Cliff Lofts fenced lot is
  Rect2(52, 802, 56, 66) and a ped must not walk inside its fence.
- Side streets: SIDE_X −300 / −80, 8 m of asphalt. Craftsman FRONTAGE rows face them from
  x −282 (porch to −290) and x −98 (porch to −90) -> walk lines at x −294 and x −86.5.
- Park: grass 50x40 at (−190, 870), gazebo 8.2 m, benches at r 9, live oaks at r 19/15
  -> a 24 x 24 loop at ±12/±12 threads between benches and trees.
- `harvest_hills.gd`: mud lanes are 7 m wide at z −500/−620/−740 and x −900/−800/−720,
  extent x −964..−656 / z −470..−846. Trailer 12 x 3.6 at (−836, −470), door/steps and every
  label on its +z face -> the walk line sits 6 m south at z −464.
- `dealer.gd`: showroom 24 x 12 at (−145, −100) => walls z −106..−94; WADE_POS is
  (−138, 0, −92) and he has a StaticBody3D. The lot line is (−153, −93)..(−141, −93):
  centred on the brief's door point, stopping 3 m short of Wade.
- `fairgrounds.gd`: concourse slab 150 x 220 at (908, 240), top +0.04; gate pylons are
  5 x 5 colliders at (846, 294) and (846, 316) -> groundskeeper line at x 851, z 297..313
  then east along z 313, clear of both pylons and the chain-link (fence opens z 291..319).

## WHAT LANDED
`game/data/mechanics/ped_zones.json` (new) and `game/scripts/systems/pedestrians.gd`
(+336 lines). Parse: `PARSE: 94 scripts, 0 failed`. Lint: `Success: no problems found`.

### The zone file's shape
```
{"_doc": "...", "zones": [ {
   "name":   "cliff_boulevard",     # the handle zone_count() takes
   "pts":    [[x,z], ...],          # the sidewalk, in world metres
   "loop":   true,                  # wrap the last point back to the first
   "width":  1.2,                   # m either side a ped may stand on (also the panic band)
   "cap":    10,                    # max live peds from this zone
   "y":      0.05,                  # walking-surface height; feet sit here
   "min_dist": 40.0,                # optional; default 50 (SPAWN_MIN_DIST)
   "outfits": {"CASUAL": 3, "WESTERN": 2, "STREET": 2, "SERVICE": 2},
   "hat":    "HARD_HAT"             # optional; applied ONLY to a WORKER roll
} ] }
```
Eight zones, caps read as per-GROUP totals the way the brief phrased them:
cliff_boulevard 10 | cliff_side_west 1 + cliff_side_east 1 + cliff_park 2 (= the "cap 4"
for side streets and the park) | harvest_trailer 1 + harvest_lanes 3 (= "cap 4") |
boone_lot 2 | fair_gate 2. All of it is one-line tunable; PED_COUNT 16 is still the
global ceiling and the districts are far enough apart that no two ever compete.

### How it hangs off the existing spawner
- `_physics_process` now reads `(_try_spawn(...) or _try_zone_spawn(...))`. Downtown runs
  FIRST and BYTE-UNCHANGED — not one draw added, removed or reordered on `_rng` — and the
  districts only ever get the frame when no block qualified, which is what happens the
  instant the player leaves the grid (nearest block centre from Juárez Blvd is ~450 m).
- Every zone draw is on `_zone_rng` (new RNG, literal seed `ZONE_SEED := 0x2ED20E`):
  zone pick, arc coord, wdir, stroll speed, brave roll, and the whole costume roll.
  `_make_zone_ped` is deliberately NOT a re-parameterised `_make_ped` for that reason.
- Smoke: `_load_zones()` sits after the smoke gate in `setup()`, so smoke mode never even
  opens the file. Corridor: `_try_zone_spawn` runs the same `CORRIDOR.has_point` reject as
  `_try_spawn`, and a 2 m sweep of all eight polylines shows 0 points in x[174,212]
  z[424,576] anyway (nearest district is 890 m from it).
- Ring/interval/tries are shared: ring top SPAWN_RING.y = 200 m, `min_dist` per zone.
  A zone is only considered when its bounding circle is within ring range — `_zone_near`,
  rebuilt on the 0.3 s threat cadence, so when the player is downtown a zone spawn attempt
  costs one `is_empty()` and returns.

### The path generalisation
`_zone_point` / `_zone_nearest` are the polyline twins of `_path_point` / `_nearest_s`,
with the same out-params, and `_point_at` / `_nearest_at` dispatch on `ped["zone"]`
(absent or −1 = a downtown block ped, unchanged). Polylines are precomputed at load into
segment starts + unit directions + lengths, so walking one is a subtraction per segment
and projecting onto one is a dot per segment (≤ 4 segments in this file). An OPEN zone
turns the ped around at its ends; a LOOP zone wraps. States, flee, brawl, follow,
knockdown, gunfire panic and despawn are untouched shared code.

## HOW OUTFITS ARE BIASED — and the factory change I could not make
`character_factory.random_config(rng)` takes an RNG AND NOTHING ELSE. There is no outfit
override key: the archetype is drawn inside, by `_pick_outfit(r)`, off a LOCAL rng seeded
from the eight caller draws, and `_dress()` then writes ~15 wardrobe keys. I was told not
to edit that file, so the bias is **rejection sampling on our own stream**: draw the
archetype from the zone's weight table, then roll `random_config(_zone_rng)` until one
comes up in that archetype (`ZONE_OUTFIT_TRIES := 24` checked rolls, then keep what we
have — the sidewalk gets a visitor rather than a stall).
- Miss rate = (1 − p)^24 with p the factory's base share: WORKER .12 → 4.6 %, OFFICE
  .13 → 3.5 %, SERVICE .10 → 8.0 %, SCRUBS .08 → 13.8 % (SCRUBS is 1/7 of one zone).
- Cost: ≤ 25 `random_config` calls, ONLY at spawn, and at most one spawn per 0.3 s.
  Nothing per frame, nothing on `_rng`.
- **Recommended one-line factory change (not mine this round): `static func
  random_config(rng, outfit := -1)` that passes `outfit` through to `_dress` when ≥ 0.**
  `_zone_config()` then becomes a single call and the miss rate goes to zero. I did NOT
  post-set `cfg["outfit"]`, and did NOT call `FACTORY._dress()` on an already-dressed cfg:
  re-dressing leaves the previous archetype's keys behind ("jersey" + "shorts" + a hi-vis
  vest), which is a worse bug than an occasional visitor.
- The one key the factory DOES accept post-hoc is the hat — `build()` reads `cfg["hat"]`
  and `cfg["hat_color"]` as plain data — so a zone's `"hat": "HARD_HAT"` is applied
  directly, and ONLY when the accepted roll is WORKER (hard hat on a man in a polo is a
  costume error). Colours are the factory's own three hard-hat colours.

## PUBLIC API FOR THE PROBE
- `const ZONES_PATH := "res://data/mechanics/ped_zones.json"`
- `func zone_count(zone_name: String) -> int` — live peds from that zone (validity-checked).
  The parameter is `zone_name`, NOT `name`: a parameter called `name` shadows `Node.name`.
  Calls are positional, so `peds.call("zone_count", "cliff_boulevard")` is unaffected.
- `func zone_length(zone_name: String) -> float` — the polyline's length, 0.0 if unknown;
  handy for a probe that wants to assert the file loaded at all.

## SUGGESTED PROBE STAGE (zones)
1. `zone_length("cliff_boulevard") > 1000.0` — the file parsed (it is 1001.3 m).
2. Park the player at **(−200, 1.1, 796)** (the north sidewalk outside Botánica San Judas),
   wait 40 s → `zone_count("cliff_boulevard") >= 3`. 57 % of that polyline is inside the
   50–200 m ring from there, so the 10-try loop hits on the first frame and the cap of 10
   fills at one per 0.3 s; downtown cannot compete (nearest block centre is 446 m away).
   `zone_count("cliff_park") >= 1` should also hold (100 % of the park loop qualifies).
3. Drive to **(−110, −44)** (Boone's lot entrance, 60 m from the showroom door) and wait
   20 s → `zone_count("boone_lot") >= 1`; every one of them should be OFFICE.
4. Park at **(−870, −470)** → `zone_count("harvest_lanes") + zone_count("harvest_trailer") >= 1`.
5. Regression: teleport downtown (e.g. 193, 517-ish is the corridor — use (400, 300))
   and assert every `zone_count` is 0 within one despawn window (260 m).

## WHAT I COULD NOT VERIFY WITHOUT A BOOT
- Anything visual. No ped was ever placed in a running tree by me — agents run
  `parse_all.gd` only. The polylines were checked against the BUILT geometry by reading
  the world scripts and by a Python port of the new math (below), not by a plate.
- I DID prove the two behaviours that a narrow sidewalk breaks, by porting `_zone_point`,
  `_zone_nearest`, `_zone_clamp` and `_zone_flee` to Python and running them on the real
  JSON: (a) 120 s of walking on all three zone shapes stays 0.0000 m off the line, the
  open ones turn around at their ends (side street 2 turns, Boone's 12 m line 14 turns —
  a pacing salesman, which is the right read); (b) a ped shoved SQUARE at the storefronts
  on Juárez runs **7.6 m up the block in 2 s and never gets closer than z 790.50 to the
  shopfront wall at z 790.0**. That second one is why `_zone_flee` exists: a hard clamp on
  a 2.4 m band makes a fleeing ped run in place at the kerb (the moonwalk). The panic's
  cross-pavement half becomes speed along the pavement, the side is chosen once per run
  (`ped["fdir"]`) so the zigzag cannot flip him, and 30 % of the sideways component is
  kept as weave.
- Unverified by measurement: frame cost. The added per-frame work is one `_zone_nearest`
  (≤4 dots) per FLEEING zone ped, plus ≤10 RNG draws per frame while a district is in
  range and uncapped. No rays were added — the house budget is untouched.

## TWO THINGS I FIXED WHILE IN HERE (same D-068 hazard as the two guarded today)
`honk_at()` did `var body: RigidBody3D = ped["body"]` and `_on_shot_fired()` did
`ped["body"] as RigidBody3D` BEFORE `is_instance_valid` — both cast a possibly-freed
instance, which 4.7 errors on. Both now take the Variant, validate, then cast. They are
signal callbacks, so they can fire between a `queue_free()` and the next `_validate()`.

## FOLLOW-UPS I DID NOT TAKE
- A `"stand": true` zone flag (a salesman who stands instead of pacing) needs the IDLE
  state to answer `_check_threats` first, or he would ignore a car bearing down on him.
- Zones are not registered in `atlas.json` — that file is the producer's.
- `cliff_boulevard`'s two end segments are street crossings (x −440 and x 44). Both ends
  were pulled in off the brief's x −480..100 on purpose: Gilead Bottoms' lot fences and
  sign posts stand at z 790/792/810 west of x −440, and the Cliff Lofts lot is fenced from
  x 58. If traffic ever drives Juárez, those two crossings are where peds will be hit.
