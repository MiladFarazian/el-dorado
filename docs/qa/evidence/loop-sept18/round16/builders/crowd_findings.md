# COMIN' DOWN — the takeover is a crowd (loop 16)

File owned and changed: `/Users/miladfarazian/Documents/Projects/gta_clone/game/scripts/systems/mission_comin_down.gd`
(262 -> 594 lines). Parse: `PARSE: 95 scripts, 0 failed`. Lint: `Success: no problems found`.

## What was added

A `_lot_*` section at the end of the file plus three one-line hooks into the
existing state machine. Nothing else changed: timings, pay ($250), medal rule
and every existing objective/line are untouched. The card gains exactly one row.

| hook | where | what |
|---|---|---|
| `_lot_open()` | `_tick_cruise`, right after `state = State.TAKEOVER` | the lot opens the instant the last pass lands |
| `_lot_arrive()` | `_tick_takeover`, right after `state = State.SLIDE_OUT` | the salute, +2 respect, the club turns |
| `_lot_sync(delta)` | tail of `_physics_process` | fill / talk / watch while 2-3; close on anything else |

`_lot_close()` therefore fires on COMPLETE, on `_abort()` (out of the slab, off
the strip 20 s, player down) and on re-arm — one exit, no leak path.

## Positions used (all relative to `TAKEOVER_POS = (340, 0, 522)`)

- **Markers** (`_build_marks`): ring at **r = 4.6 m ±(-0.7/+0.9)**, angle `TAU*i/_want` jittered ±0.22 rad, y = 0.875.
- **People spawn** (`_lot_fill`): **r = 13.0 m** on the marker's own bearing, y = **0.875** (`PEDS.PED_HALF` over a y=0 lot), facing inward.
- **Where they end up**: `FOLLOW_STOP` is 2.8 m, so 4.6 + 2.8 = **~7.4 m from centre** — a ring, not a pile, and 7.4 m of clearance around where the slab parks. This is the whole reason for the two radii.
- **Club rides** (`_build_rides`): **r = 16.5 m ±0.8** at **30° / 90° / 150° / 210°** (east-south round to west; measured `Vector3(cos a, 0, sin a)`, so +Z = south). **North stays open** — that is the side the player arrives from (strip at z 477, lot at z 522). Nosed in, y = 0.85.
- **Bulb string**: two poles at **x ±14 m** on the centre's east-west line, tops at 5.2 m; 26 bulbs hung 0.22 m under a straight wire with a 0.40 m sag.

## Counts

- `CLUB_MIN/MAX = 10/14`; `_want` drawn once per takeover from `_lot_rng` seeded `LOT_SEED = 0xCA9D1A` — **deterministic across boots**, so the smoke line and the plate sweep are unaffected.
- `CLUB_PER_TICK = 2` spawned per physics frame -> 14 members in 7 frames (~0.12 s). Never a single-frame hitch.
- `RIDE_COUNT = 4`, one per candy paint (apple / grape / teal / gold).
- `BULB_COUNT = 26` in **one** MultiMesh, `use_colors`, `custom_aabb = bounds.grow(1.0)` (D-059).
- 8 arrival lines, 4 slide-out lines, one every `CROWD_LINE_EVERY = 9.0` s at most.

## Peer calls (public API only — nothing reaches into a peer's internals)

| peer | call | note |
|---|---|---|
| `pedestrians` | `spawn_follower_at(pos, -head, mark, 600.0)` | the only spawn verb used. NOT `spawn_brawler_at` — the club must never fight the player |
| `pedestrians` | `state_of(body)` compared against `PEDS.DOWN` | `PEDS.DOWN` resolves (unnamed enum -> script constant); confirmed by parse |
| `pedestrians` | `honk_at(pv, 18.0)` | once, at arrival |
| `repo_board` | `add_respect(2, "THE CLUB SHOWED")` / `add_respect(-4, "HIT ONE OF OURS")` | the second charged once per night (`_hit_charged`) |
| `mission_kit` | `say("CANDYLAND C.C.", line, 4.2)` via the file's existing `_say` | |
| `sky_weather` | `.get("time_of_day")`, read-only | bulbs only past 19:00 or before 06:00 |
| `vehicle_body_builder` | `build(vis, "sedan", (1.9,1.05,4.4), paint)` | same call shape as `random_events._spawn_at`; wheels mirror `_add_wheels` with matching `RIDE_WHEEL=0.32` / `RIDE_RIDE_H=0.85` so the ambient `amb_sedan` drop lands on the tyres |

`send_to` was read but is **not** called: `spawn_follower_at` already sets the
target, and re-facing is done by moving the marker (below), which is cheaper and
does not reset `follow_t`.

## Design notes worth keeping

- **Facing without fighting the follower controller.** `_update_follow` re-`_place`s the body every frame pointing at its marker, so any transform I set is overwritten next frame. `_face_club` instead moves each marker to `body_pos + dir_to_slab * 2.4 m`. 2.4 < `FOLLOW_STOP` (2.8), so the member does not walk — he turns to the slab and stands. Only members already within 10 m of the centre are re-faced; anyone still walking in keeps walking in (a snapped marker would freeze him in a ragged ring).
- **Never towable.** The rides are added to no group at all. `random_events` puts its dead sedan in `towable` + `stranded`; the club's rides deliberately get neither. They are frozen `FREEZE_MODE_KINEMATIC` RigidBody3Ds, so they are solid but immovable, and `pedestrians._refresh_threats` skips frozen bodies — the crowd will not flee its own cars.
- **Poles carry no collision** (plain `MeshInstance3D`). The probe teleports the slab onto this lot; nothing of ours may be in its way.
- **Fill is self-healing.** `_lot_fill` prunes freed entries and tops back up to `_want`, gated on the player being within `CLUB_NEAR = 180 m` (peds despawn at 260 m). A member lost to the ped budget comes back; nobody is spawned 480 m away for nothing.
- **Never in the player's way.** A spawn slot within `CLUB_CLEAR = 4 m` of the player's rig is skipped and retried next frame.

## Could not be verified without a boot

1. **The lot's ground is assumed y = 0.** Inferred: `TAKEOVER_POS.y = 0.0`, the board's pole at `BOARD_POS + (…, 1.35, …)` with a 2.7 m box bottoms at 0, and the probe teleports to `TAKEOVER_POS + (0, 1, 0)`. If the lot sits on a 0.2 m slab like the downtown sidewalks, every member and every ride is 0.2 m sunk. **One windowed plate at the lot settles it**; the fix is two constants (`CLUB_Y`, `RIDE_RIDE_H`).
2. **Nothing else occupies r = 13–17 m around (340, 522).** No world script referenced that area (`scenic_dressing`'s exclusions are z 136–166 and 540–580, so scrub *may* be seeded at z 522). A club ride could end up inside a bush. Visual only.
3. **The bulb string's `custom_aabb` and the unshaded vertex-colour path.** Headless cannot show AABBs (dummy renderer, D-059). Needs a windowed night plate that actually contains the lot.
4. **`honk_at` does not do what the brief described.** Read of `pedestrians.honk_at`: it makes ambient peds **in state WALK** bolt away from the horn — it does **not** sound traffic horns. Club members are in `FOLLOW`, so they are immune; the visible effect is bystanders stepping out of the slab's path as it rolls in. That reads as the crowd parting, which is why I kept it at a tight 18 m. If the intent was really an audible salute, that is a `vehicle_audio` / `traffic` feature and does not exist yet.
5. **Crowd density / silhouette at 7.4 m.** Ten to fourteen 0.5 × 1.75 m colliders on a 46 m circumference is ~3.3 m apart — should read as a loose crowd, not a wall, but that is a judgement call for a plate at a `car_34`-style vantage on the lot.
6. **Frame cost of 14 followers + 4 built sedan shells.** Four `BODY_BUILDER.build` calls happen in one frame inside `_lot_open()`. `random_events` builds one and is fine; four at once is untested. If it hitches, spread the rides over frames the way the people already are.

## Probe rows I would add (zz_mech_probe stage 10 — not my file)

Insert in `_stage_comin`, between the existing sub 2 (TAKEOVER reached) and sub 3
(parked). `crowd_count()` is exposed on the mission for exactly this.

- **sub 2, after the teleport to `TAKEOVER_POS`** — give the fill 3 s, then:
  `_say(int(m.call("crowd_count")) >= 8, "stage10 the lot filled: %d club members out" % int(m.call("crowd_count")))`
  (state 2 held for 3 s -> `crowd_count() >= 8`. `_want` is 10–14 and fills at 2/frame, so 8 is a floor with slack for the ped budget.)
- **sub 3, on reaching state 3**:
  `_say(int(repo.get("respect")) - _respect_before_arrive == 2, "stage10 THE CLUB SHOWED: +2 respect on arrival")`
- **sub 4, after COMPLETE**: give it 1 s, then
  `_say(int(m.call("crowd_count")) == 0, "stage10 the lot emptied after the card (%d left)" % int(m.call("crowd_count")))`
  — this is the one that catches a leak; `_lot_close()` runs on the first frame in COMPLETE.
- **An abort row worth having**: force `m.call("_abort", "probe")` from state 2 and assert `crowd_count() == 0` a frame later.

**Caveat for whoever writes the row**: as the probe is written today, sub 3 fires
on the **first frame** after the teleport, so `_crowd_peak` — and therefore the
card's `THE LOT  <n> came out` row — will read 2–6 in a probe run, not 10–14.
The row is honest (it reports the peak live count), but a probe assertion on the
*card text* would be wrong. Assert on `crowd_count()` after a deliberate 3 s hold
instead, which is why the row above buys the hold first.
