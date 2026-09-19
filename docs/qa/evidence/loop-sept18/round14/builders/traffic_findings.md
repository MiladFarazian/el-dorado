# KIND_SPUR — ambient traffic on every road that is not the grid

Files: `/Users/miladfarazian/Documents/Projects/gta_clone/game/scripts/systems/traffic.gd` (only
existing file touched, +405/-19), new
`/Users/miladfarazian/Documents/Projects/gta_clone/game/data/mechanics/traffic_spurs.json`.

Gate: `parse_all.gd` 94/94, `gdlint game/scripts/systems/traffic.gd` 0 findings.
(One intermediate parse run reported `pedestrians.gd` FAIL — another agent was mid-write on it,
8 s before my run; the next run was clean. Not my file, not my change.)

## What landed
- **Fourth lane kind `KIND_SPUR`.** A spur is a polyline route read from
  `data/world/atlas.json` at `setup()` (FileAccess + `JSON.parse_string`, the `city_map.load_atlas()`
  pattern). Atlas optional: no file / bad parse / no `roads` array -> `_spurs` stays empty and
  downtown is byte-for-byte what it was. Built in `_load_spurs` / `_build_spur`.
- **Everything else is the existing machinery.** Same shells (sedan / 12% truck, same palette,
  same jack profile, `civilian` + `towable`), same one ray per car per frame, same car-following,
  same crash/unfreeze/debris/despawn, same honk, same `release_car` handoff to carjack.
  New per-frame cost for a spur car is two dict reads.

## Tunables: a new data file (not consts)
`game/data/mechanics/traffic_spurs.json` — `spur_cap` (3), `spur_min_len` (120.0),
`lane_offset` (3.5), plus `caps` and `lanes` maps keyed by the atlas road name. Every key optional;
the `SPUR_*` consts at the top of traffic.gd are the fallbacks, so deleting the file changes nothing
but the numbers. `TRAFFIC_COUNT` (10) is untouched and still the global ceiling.

## Which roads qualified (verified against the shipped atlas)
| road | length | segs | cap | lane | |
|---|---|---|---|---|---|
| Juárez Boulevard | 993 m | 2 | 4 | 3.5 | **driven** (the only one with a corner) |
| Cliff back street | 580 m | 1 | 3 | 2.0 | **driven** |
| Pioneer Vision Parkway | 404 m | 1 | 3 | 3.5 | **driven** |
| Cliff side street (west/east) | 240 m each | 1 | 3 | 2.0 | **driven** |
| County General spur 77 m · Overflow entry drive 75 m · Fair Drive 66 m · Boone Trucks drive 8 m | | | | | skipped, under `spur_min_len` |

**Fair Drive gets no traffic** — 66 m, below the 120 m floor the brief set — so the Fair Drive /
Howdy Street join named in the brief never fires. The rule is implemented generically; only Juárez
exercises it on this atlas.

**Lane offset is per road, and that was not cosmetic.** `cedar_cliff._roads()` lays the side and
back streets as `Vector3(8.0, …)` — 8 m of asphalt, half-width 4.0. At the grid's 3.5 m offset a
1.9 m shell spans 2.55–4.45 m off the centreline, i.e. a quarter of every car parked on the grass.
Those three roads are 2.0 in `lanes`. Juárez is 12 m (`BLVD_W`) and Pioneer Vision Parkway 10 m,
both fine at 3.5.

## The join rule I implemented (both directions, one pair actually fires)
A spur end merges onto a grid lane, and a grid lane merges onto a spur, **only as a straight
continuation**: same heading, spur terminal at most `SPUR_JOIN` (30 m) ahead, lane centres within
`SPUR_JOIN_LAT` (1.5 m), and the spur's own lane offset equal to the grid's 3.5 (otherwise the two
lanes are not collinear and the merge is refused). No arc, no gap, no lane jump — the shell keeps
its heading and changes which brain drives it (`_join_grid` spur->grid, `_join_spur` grid->spur).
Everything else U-turns at the end exactly as before.

On the shipped atlas exactly one pair passes: **Juárez Boulevard's north end (279, 566) <-> the
x=279 grid street, which traffic bounds at z=545** — 21 m apart, same centreline, and
`greybox_city` runs the downtown street bed out to z=566, so the merge happens on real asphalt, not
prairie. Verified by hand: southbound grid lane x=275.5 and southbound Juárez lane x=275.5 are the
same line; northbound both are 282.5. A merged northbound car re-plans onto the grid and picks up
the signal at (279, 477) normally. Every other spur terminal (Juárez west, both Cliff streets, the
back street, both Pioneer ends) finds no grid lane and U-turns.

## Two things I added that the brief did not ask for, and why
1. **`SPUR_GIVEUP` (9 s) — a blocked spur car turns around.** The Cliff back street (z=900) crosses
   both Cliff side streets (x=-300, x=-80) and they are separate polylines, so there is no
   intersection logic between them: two shells arriving together each stop 4 m short on the
   obstacle ray and neither ever moves again. A spur shell stopped longer than `SPUR_GIVEUP`
   U-turns out of it. It also makes a driver the player has parked in front of give up after
   honking, which is the behaviour DNA §4 wants anyway.
2. **`_turn_limit` / `SPUR_UTURN_CREEP` (1.5 m/s).** Required by (1): `_step_turn`'s `d_ang` is
   `speed*delta/r`, and the first quarter of a U-turn still points at the thing being escaped, so
   the limit is 0, so the arc never sweeps and the shell freezes at zero degrees — worse than the
   deadlock it was fixing. Spur U-turns therefore keep a walking-pace floor until `arc_sweep` drops
   below 0.6·PI. **Grid cars are untouched** (`kind == KIND_SPUR` guard), so no grid arc changes.

## Determinism / the seeded stream
- `_try_spawn` is still called **first and unconditionally** every eligible frame; spurs only get
  the slot it could not fill (`_try_spawn(p) or _try_spawn_spur(p)`). Its 12 tries draw the same
  numbers in the same order they always did.
- `_make_car` now takes the rng as a parameter. The grid passes `_rng` — the same three draws
  (`randf` truck, `randi_range` paint, `randf_range` tspeed) in the same order. Spurs pass a new
  `_spur_rng`, literal seed `990413`, third stream after `_sig_rng`. **No `_rng` draw was added,
  removed or reordered** — the `git diff` deleted-line list is 19 lines and every one is accounted
  for.
- Spur spawns respect `CORRIDOR` per candidate point, `SPAWN_RING`, `SPAWN_CLEARANCE` (`_clear_at`),
  the per-spur cap, and never land within `SPUR_CORNER_CLEAR` (12 m) of any polyline vertex.
- `setup()` still returns before `_load_spurs()` in smoke mode: **no spurs, no process, inert.**

## What I could NOT verify without a boot
Everything below is analytic (hand-derived geometry + a Python mirror of the loader over the real
atlas), not observed:
- that a spur car is actually **on the asphalt** at each of the five roads (I checked the slab
  extents in `cedar_cliff.gd` / `harvest_hills.gd` by hand: Juárez z-leg 566..800 and x-leg
  -480..285 at z=800 ✓, side streets z 700..940 ✓, back street x -480..100 ✓, parkway z -470..-36
  ✓ — the parkway's brick monument sits at z=-452, 12 m past the polyline end, and the U-turn apex
  reaches only ~-446, so it clears);
- that the **Juárez corner** (279,800) reads right on screen — the trigger maths is the grid's own
  (`lane + R_RIGHT` / `R_LEFT - lane`, both re-derived generically for any lane offset) and the
  corner classification is `_right(dir)·next_dir`, which I checked by hand for both directions
  (south->west = right, east->north = left);
- that the **merge** looks like a merge rather than a pop;
- frame cost with spur cars live (should be nil — no new rays, no new group scans);
- whether spur density *feels* right. Caps are 3 (4 on Juárez) against a global 10, and the ring is
  unchanged, so in Cedar Cliff you should see roughly 3–6 cars, never a downtown crowd.

## Suggested probe row (headless, for the producer)
`traffic.gd` now exposes **`spur_census() -> {"routes": int, "cars": int}`** for exactly this.

- **Load check (instant, no sim):** after `setup()`, `traffic.spur_census()["routes"] == 5`.
  Fails loudly if the atlas moves, a road is renamed, or `spur_min_len` is edited carelessly.
- **Live check:** park the player at **(-200, ride, 800)** — the middle of Juárez Boulevard's
  east-west spine, with the back street (100 m) and both side streets (100 / 120 m) inside the
  70–260 m ring — run ~60 s of physics, then assert `spur_census()["cars"] >= 1`.
  A stricter version that also proves the lane and not just the count: assert some `civilian` body
  has `absf(absf(z - 800.0) - 3.5) < 0.6`, i.e. it is sitting on a Juárez lane.
- **Merge check (optional, slower):** park at **(275.5, ride, 520)** (southbound x=279 grid lane,
  just north of z=545) and assert that within ~60 s some `civilian` body exists at z > 570 with
  `absf(x - 275.5) < 0.6` — that is a shell that can only have got there through the grid->spur
  merge, since spur spawns in that ring would be caught by the same assertion only south of the
  corridor... (if that ambiguity matters, assert on `spur_census()["cars"]` rising while the player
  never leaves the grid).
