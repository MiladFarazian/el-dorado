# traffic.gd — adoption API + spur give-way (loop 15)

File: `/Users/miladfarazian/Documents/Projects/gta_clone/game/scripts/systems/traffic.gd`
1145 → 1571 lines. `parse_all.gd`: **94 scripts, 0 failed**. `gdlint`: **no problems found**.

## 1. The public signatures (exact)

```gdscript
func adopt(body: RigidBody3D, flee := true) -> bool
func release(body: RigidBody3D) -> void
func is_driving(body: RigidBody3D) -> bool
func driven_speed(body: RigidBody3D) -> float   # m/s along its lane, 0 if not ours
func stuck_for(body: RigidBody3D) -> float      # s under 0.5 m/s while adopted, 0 while moving
```

All five are no-ops / false / 0.0 for a body the brain is not driving, and every one
does `is_instance_valid()` BEFORE any cast.

`adopt` returns **false and touches nothing** when: the body is invalid or out of tree;
`main_ref` is null or `_ns_x` is empty (smoke mode — `setup()` returns before the lane
tables are built, so adoption is inert there for free); no lane centreline within 40 m;
or the body is already an *ambient* roster car. Called again on a body it already drives
it returns true and changes nothing.

## 2. The lane-snap rule

`_nearest_lane(p)` measures planar distance to the **centreline** of every drivable lane —
7 N-S streets, 5 E-W streets, both frontage roads, and every segment of every atlas spur —
and returns the closest if it is within `ADOPT_RANGE = 40.0`. Distance is to the centreline,
not to the lane, because which side of the road the car rides is not known until the
direction of travel is chosen.

Direction: the lane axis, signed so it points **away from `main.player_actor()`**
(`axis.dot(body.pos - actor.pos) >= 0`). With no actor (headless / probe) it falls back to
the way the body is already facing (`-basis.z`).

**The heading snaps; the position does not.** A curbside order car is 3–8 m off its lane
and the search reaches 40 m, so a hard lateral snap would be a visible pop and at range a
pop through a building. `adopt` places the body at its own position on the new heading and
it crabs onto the lane at `ADOPT_MERGE = 3.0` m/s of lateral correction
(`_lane_converge`, one snap-point call per adopted body per frame, nothing for ambient
traffic). This is why `adopt` sets `"merging": true` — the off-lane watchdog is not armed
until the body reaches its lane (within 1 m) for the first time.

It starts at the speed it already had along the new heading
(`clampf(body.linear_velocity.dot(dirv), 0, tspeed)`), not at target speed, so a debtor who
just jumped in accelerates out of the space on the normal `ACCEL = 5.0` ramp.

## 3. The FLEE profile — the numbers

| knob | value | where |
|---|---|---|
| target speed | `FLEE_SPEED = (15.0, 18.0)` m/s, drawn from `_adopt_rng` | `adopt` |
| turn weights | `FLEE_STRAIGHT = 0.8`, `FLEE_RIGHT = 0.1`, left = 0.1 | `_drive` |
| reds | `if ph == PH_STOP and car.flee: ph = PH_CAUTION` | `_signal_limit` |
| U-turns | only at a dead end (grid end that joins no spur; spur polyline terminus) | `_drive` |
| spur give-up U-turn | suppressed (`stuck_t` zeroed every frame for a foreign body) | `_drive` |
| player-proximity crash | skipped entirely for a foreign body | `_drive` |
| car-following / obstacle ray | **unchanged, still applies** | `_sense_limit`, `_follow_limit` |

Red-as-amber is not a separate code path: the existing late-amber logic already models
"too late to stop honestly, clear the box instead", and at 15–18 m/s inside
`SIG_AMBER_LOOK = 11.0` the geometry always agrees (`sp² = 225…324 > 2·6.0·11 = 132`), so a
runner clears every red *for a reason the arithmetic backs*. If traffic has it down to a
crawl it still waits — which is what makes the chase readable.

Turn weights for `flee = false` stay 0.6/0.2/0.2, but still drawn from `_adopt_rng`.

## 4. Never freeing a foreign body — every path audited

- `_validate`: foreign entries branch out **before** the despawn-distance and debris-age
  tests. That branch can only hand the body back.
- `_unfreeze`: early-returns for foreign, so neither `_pair_crashes` nor a contact can
  convert the body to debris (which is what would have put it on the despawn clock).
- `_on_contact` is never connected on a foreign body.
- **The frontage road was the one real landmine**: `_drive`'s `KIND_FRONTAGE` end-of-road
  branch called `body.queue_free()`. It now sets `car["lapse"] = true` and returns; the
  release happens next frame from `_validate`, because mutating `_cars` mid-iteration
  would skip a car. This was the only `queue_free` reachable from the driving path
  (`grep` confirms two in the file: `_validate`'s ambient despawn, and this one).
- `_on_hooked` (traffic's own subscription to the tow's `hooked` signal) now releases a
  foreign body instead of unfreezing it, **and fires no heat** — hooking a repo order is
  the job, not GRAND THEFT AUTO.
- `release_car` (the carjack handoff) restores foreign state before dropping the entry.

Groups, metadata, name and mesh are never touched. The **only** node the brain ever adds to
a foreign body is the horn `AudioStreamPlayer3D`, and `_foreign_restore` frees it, so the
owner's car goes back exactly as it came.

## 5. Belt-and-braces release (`_foreign_lapsed`, run from `_validate` every frame)

1. `car["lapse"]` — a deferred request from `_drive` (frontage end of road).
2. **The freeze flag is no longer the one the brain set.** *Deliberate reading of the
   brief, flagged here.* The brief says "release if `body.get("freeze") == true`". The
   brain must hold an adopted body `freeze = true` / `FREEZE_MODE_KINEMATIC` — that is what
   "drives it as a shell" means in this codebase — so a literal `== true` test would fire
   on the brain's own flag on frame one. The equivalent-and-correct test is
   `bool(body.get("freeze")) != car["own_freeze"]`, i.e. *somebody else touched it*, which
   fires exactly on the tow hook's `freeze = false` (parked_cars' law: a frozen car cannot
   be towed) and equally on an owner re-parking the car underneath us. **If the parent
   wanted the literal test, the mechanism needs re-specifying, not the line.**
3. More than `ADOPT_OFF_LANE = 6.0` m off its lane for `ADOPT_OFF_HOLD = 3.0` s. A shell
   mid-arc is exempt (an arc is off the lane by design) and its clock resets; a merging
   shell is exempt until it arrives.
4. A freed body is dropped by `_validate`'s existing first test; `release(null)` (or with an
   already-freed body) prunes every stale foreign entry.

`release()` hands back: the owner's `freeze` / `freeze_mode` as captured at adopt, and
`linear_velocity = -basis.z * car["speed"]` when the body ends up dynamic.

## 6. Give-way at spur crossings — DONE, and it is real on the shipped atlas

Computed once in `setup()` (`_build_crossings`, after `_load_spurs`). Two axis-aligned
segments cross iff one runs along x and the other along z and each contains the other's
constant coordinate (`_axis_cross`); parallel pairs are not junctions. **The shorter
polyline yields**, ties to the higher index so the answer is identical every boot.

On `data/world/atlas.json` today, five polylines qualify (>120 m) and there are exactly
**four crossings**, all with an unambiguous answer:

| crossing | yielder | gives way to |
|---|---|---|
| (−300, 800) | Cliff side street (west), 240 m | Juárez Boulevard, 993 m |
| (−80, 800) | Cliff side street (east), 240 m | Juárez Boulevard, 993 m |
| (−300, 900) | Cliff side street (west) | Cliff back street, 580 m |
| (−80, 900) | Cliff side street (east) | Cliff back street, 580 m |

Runtime: `_yield_limit` fires only for a spur shell within `XING_YIELD = 12.0` m of a
crossing that is **ahead** of it, and only when `_xing_busy` finds a shell on the longer
polyline within `XING_WATCH = 18.0` m of the same point with `(to/d).dot(dir) > 0.5`. The
ceiling is the same `_gap_speed` curve the stop bar and car-following use, fed the bumper
distance, so giving way brakes like a queue rather than throwing a switch. Cost: an empty
`Array` lookup for the three spurs that yield nowhere; at most two crossings × ≤11 roster
cars for the two that do. **No new rays.** `SPUR_GIVEUP` is untouched and stays the backstop.

## 7. RNG discipline (the gate-critical part)

`_adopt_rng` is a **fourth** stream, seed `ADOPT_RNG_SEED = 0xD06213`, and it is the only
source of randomness any foreign body touches: target speed, `sig_jit`, turn choice, horn
cooldown and horn pitch (`_jit(car)` routes ambient shells to `_sig_rng` unchanged, foreign
to `_adopt_rng`).

Verified mechanically: the set and order of `_rng.` draw sites is **byte-identical to HEAD**
apart from one extra tab of indentation on the existing turn roll (it moved inside an
`else:`). No draw added, removed or reordered on any existing path.

`_frozen_count()` now **excludes** foreign bodies, on purpose: counting an adopted car
toward `TRAFFIC_COUNT` would silently thin the ambient fleet and, with it, change the frame
on which the seeded stream draws its next number.

## 8. What could NOT be verified without a boot

Per the brief, the only Godot run permitted was `parse_all.gd`. Everything below is
reasoned-and-unmeasured:

- that `adopt` actually finds the lane next to a real repo-order slot (the 40 m search is
  untested against live geometry — in particular whether a curbside slot is ever closer to
  a *frontage* centreline than to the street it faces);
- the merge looking right on screen (3 m/s lateral at 15 m/s forward is an 11° crab);
- the flee car clearing a red without T-boning cross traffic — it still car-follows, but
  it does not consult `_sig_may_enter`, by design;
- the give-way reading as courtesy rather than as a stall, and whether 12/18 m are the
  right windows at spur speeds (9–13 m/s);
- `driven_speed` / `stuck_for` values under real contention;
- **the smoke baseline.** `pos=(193.000000, 1.097968, 517.631836) moved=40.4m
  speed=16.7m/s` should be unchanged (traffic is inert in smoke and no `_rng` draw moved),
  but it has not been run.

## 9. Suggested probe assertion (`zz_mech_probe.gd`)

One stage, ~6 s, headless-safe:

```gdscript
# ADOPT: the brain drives a body it did not spawn
var body := <build a frozen kinematic shell at (283.0, 0.85, 300.0), groups
             "towable"/"mission_target"/"repo_order", freeze = false>
assert(traffic.adopt(body, true) == true)          # x=279 N-S street is 4 m away
assert(traffic.is_driving(body))
assert(body.is_in_group("repo_order"))             # groups survive adoption
assert(body.freeze == true)                        # driven as a shell
<run 3 s of physics>
assert(traffic.driven_speed(body) > 12.0)          # FLEE profile is up to speed
assert(absf(body.global_position.x - 279.0) - 3.5 < 1.2)   # merged onto the lane
assert(traffic.stuck_for(body) == 0.0)
var v := traffic.driven_speed(body)
traffic.release(body)
assert(not traffic.is_driving(body))
assert(body.freeze == false)                       # owner's state handed back
assert(body.linear_velocity.length() > v - 1.0)    # ... with its momentum
assert(is_instance_valid(body))                    # AND THE BRAIN NEVER FREED IT
```

Two cheap extras worth adding: `assert(traffic.adopt(<body at (0, 0.85, -2000)>) == false)`
for the 40 m refusal, and — after parking the player vehicle across the lane 8 m ahead —
`assert(traffic.stuck_for(body) >= 2.5)` after 4 s, which is the owner's boxed-in signal
and the reason the brain deliberately refuses to U-turn a runner.
