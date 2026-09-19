# THE DEBTOR WHO RUNS — repo_orders FLEE (loop 15)

Files owned and changed (only these two):
- /Users/miladfarazian/Documents/Projects/gta_clone/game/scripts/systems/repo_orders.gd
- /Users/miladfarazian/Documents/Projects/gta_clone/game/data/mechanics/repo_orders.json

Gate: `parse_all.gd` → `PARSE: 94 scripts, 0 failed`; `.venv/bin/gdlint game/scripts/systems/repo_orders.gd`
→ `Success: no problems found`. Both re-run after the last edit.

## 1. Public contract changes

- `enum State { IDLE, PUSHED, HOOKED, FLEEING }` — FLEEING == 3, as the probe expects.
- `enum Reaction { PLEAD, CALL_IT_IN, OFFER, FIGHT, FLEE }` — FLEE == 4.
- `push_now(bad_paper := false, flee := false) -> bool` — third-arg-compatible; `flee` forces
  Reaction.FLEE. Bad paper still wins: `push_now(true, true)` is CALL_IT_IN, never a run.
- `objective_text()` while FLEEING: `"CATCH THE <MODEL> · <d> m · <kph> km/h"`.
- `target()` keeps returning the car in every non-IDLE state (the probe reads it while FLEEING).
- `active` stays true through FLEEING, so hud_gta and phone pick the CATCH line up with no change.
- `walk_away()` / `prompt_text()` / `accept_offer()` unchanged: all three already gate on
  `state == State.PUSHED`, which refuses while FLEEING for free.
- `_close(outcome, keep_towable := false)` and `_abandon_car(keep_towable := false)` — new default
  arg only; every existing call site is untouched.

## 2. New tunables (game/data/mechanics/repo_orders.json)

| key | value | meaning |
|---|---|---|
| `reactions.flee` | 0.20 | share of CLEAN orders that run. Other weights rebalanced to keep the total 1.00: plead .42→.34, call_it_in .18→.14, offer .22→.18, fight .18→.14 |
| `flee_trigger_m` | 18.0 | player-to-CAR distance that breaks the conversation |
| `flee_walk_s` | 2.0 | the walk to the door before the car wakes up |
| `flee_stuck_s` | 5.0 | `traffic.stuck_for()` seconds that count as boxed in |
| `flee_escape_m` | 650.0 | distance beyond which the escape clock runs |
| `flee_escape_s` | 8.0 | unbroken seconds beyond that distance = lost |
| `flee_bonus` | 1.5 | delivery pay multiplier for an order that ran |
| `flee_lines` | 6 lines | panic / resolve / apology, incl. the brief's "I can't lose this one. I'm sorry." |
| `app_flee` | "TARGET IS MOBILE. Recover it. …" | required sentence first, app-voice tail after |
| `app_flee_secured` | "TARGET SECURED. Haul it. …" | hooked while fleeing |
| `app_flee_stopped` | "TARGET STOPPED. Hook it." | boxed in |
| `app_flee_lost` | "TARGET LOST. Reassigned to a contractor who wanted it." | escaped |

`_tuning_flee` in the JSON carries the defence of every one of those numbers as playtest
hypotheses (why 18 is inside debtor_range 25, why 2.0 s is the whole performance at
pedestrians' FOLLOW_SPEED 2.4 m/s, why 650/8 is a loss you have to earn).

Pay check: chased sedan 300 × 1.5 = **$450** floor, chased pickup 450 × 1.5 = **$675** before the
haul and rank multipliers; ceiling at PARTNER on a long pickup haul is 450 × 1.5 × 1.6 × 1.5 =
$1,620. The RECOVERED card gains a fourth row `["IT RAN", "×1.5"]` (formatted from `flee_bonus`).

## 3. The exact traffic calls (all through `_peer("traffic")`, all `has_method`-guarded)

| where | call | on failure |
|---|---|---|
| `_traffic_can_adopt()` (at `_meet`, before the first line is chosen) | `tr.has_method("adopt")` | reaction silently becomes PLEAD, prints `REPO ORDERS: flee degraded to PLEAD — traffic.adopt unavailable` |
| `_take_the_car()` | `tr.call("adopt", _car, true)` → bool | `_car.freeze = true` (parked again), reaction → PLEAD, `_fled = false`, state stays PUSHED, prints `REPO ORDERS: order %d could not run — traffic.adopt refused` |
| `_tick_flee()` | `tr.call("stuck_for", _car)` → float | method absent → the boxed-in exit simply never fires; the escape rule still closes the order |
| `_tick_flee()` | `tr.call("is_driving", _car)` → bool, only after `_flee_age > 1.0` | method absent → skipped; this is a safety net for the brain dropping the car on its own |
| `_car_speed()` (objective line) | `tr.call("driven_speed", _car)` → float, m/s, `×3.6` for km/h | falls back to the body's own flat `linear_velocity` |
| `_on_hook()` / `_flee_stopped()` / `_flee_lost()` | `tr.call("release", _car)` | method absent → no-op; every one of those paths also fixes the car's freeze/groups itself |

`adopt` is called AFTER `_car.freeze = false`, because a frozen RigidBody3D is not drivable
(parked_cars' law) and the brain should receive a woken body. If `adopt` returns false the freeze
is put straight back.

Note for the traffic builder: `traffic.gd` already has an unrelated `release_car(body) -> float`
at line 769. This work calls `release(body)` exactly as specified — they must not collide.

## 4. State diagram

```
                       push (clean, 20%: Reaction.FLEE)
   IDLE ───────────────────────────────────────────────► PUSHED
     ▲                                                     │
     │                              player ≤ 25 m  → _meet(): debtor spawns as a follower
     │                              traffic.adopt missing?  → reaction degrades to PLEAD here
     │                                                     │
     │                              player ≤ 18 m  → _begin_flee(): one flee_line,
     │                                                     │   marker at the near door,
     │                                                     │   follower walks 2.0 s
     │                                                     │
     │                        ┌─ hook takes during the walk ┘ (walk cancelled, no run,
     │                        │                                 debtor re-follows player)
     │                        ▼
     │                     HOOKED ◄──────────── tow "hooked" ──────────┐
     │                        │                 (+ traffic.release)     │
     │                        │  app: TARGET SECURED. Haul it.          │
     │                        │                                         │
     │       release off pad  │  release on impound pad → _deliver()    │
     │       → PUSHED         │     pay = base × haul × rank × 1.5      │
     │       (beacon re-lit)  │     card row ["IT RAN", "×1.5"]         │
     │                        ▼                                         │
     └──────────────────── IDLE ("delivered")                           │
                                                                        │
   PUSHED ── walk_s elapses → traffic.adopt(car, true) ──► FLEEING ──────┘
                                                            │
                          app: TARGET IS MOBILE. Recover it.│
                          beacon repositioned every tick    │
                          objective: CATCH THE <MODEL>…     │
                          expiry DISARMED                   │
                                                            │
        stuck_for(car) ≥ 5 s ──► traffic.release ──► PUSHED (expiry RE-armed at 240 s,
                                 app: TARGET STOPPED. Hook it.   car left unfrozen, hookable)
                                                            │
        dist > 650 m for 8 s ──► traffic.release, freeze, drop "mission_target",
                                 KEEP "towable" ──► _close("expired", keep_towable=true)
                                 app: TARGET LOST. Reassigned to a contractor who wanted it.
```

## 5. Design calls I made that the brief left open

1. **The plea comes first, the break second.** `debtor_range` is 25 m and `flee_trigger_m` is 18 m,
   so a runner who is approached slowly says a `plead_line` at 25 m and their `flee_line` at 18 m —
   plea, then panic, then the door. If the player arrives already inside 18 m (the probe teleports
   to 14 m), `_first_line()` skips the plea and the flee line IS the first line, so mission_kit's
   single line panel is never stomped by two lines in one tick.
2. **They reach for the NEAR door, not literally the driver's door.** `_update_follow` walks a
   straight line with no avoidance; routing them around the hood would walk the ped through the
   car body. The side is chosen by `sign((debtor − car)·basis.x)`.
3. **Expiry is disarmed on entering FLEEING and RE-ARMED (fresh 240 s) when the car is boxed in.**
   Without the re-arm, a stopped runner the player drives away from holds the endless loop open
   forever and the app never pushes again.
4. **Hooked-during-the-walk cancels the run** (no adopt, no `flee_bonus`) rather than adopting a
   car that is already chained to the boom.
5. **`walk_away()` during the 2 s walk still voids the order** — it is still PUSHED, the person is
   still on screen, and taking that out would be taking away the last-second mercy.
6. **A car that escaped keeps "towable" and is frozen** where it stopped; it enters `_abandoned`
   and the existing 300 m sweep collects it (the player is ≥650 m away by definition, so it is
   usually gone on the next sweep tick).

## 6. The one coupling I am not comfortable with

`_send_to_door()` and `_release_door()` reach into `pedestrians.gd` via `peds.call("_find", body)`
and mutate the returned entry's `follow` / `follow_t`. That works because GDScript Dictionaries are
references and `_find` hands back the live entry, and it is guarded three ways (`has_method("_find")`,
`is Dictionary`, `not is_empty()`) so it degrades to "the debtor just despawns at the door" if
pedestrians ever changes. **It is still private-field access across a system boundary.** The clean
fix, for whoever owns `pedestrians.gd` next: a public `send_to(body: RigidBody3D, pos: Vector3,
seconds: float) -> bool` that sets a follower's destination. One line here would then replace the
whole `_find` dance. `PEDS.FOLLOW_STOP` (2.8 m) is also read off the preloaded script so the door
marker can be placed `FOLLOW_STOP` past the door — the follower's standoff ring then lands on the
handle instead of 2.8 m short of it.

## 7. What I could NOT verify

- **Nothing at runtime.** Per the brief I ran only `parse_all.gd` and `gdlint`. No boot, no
  `--mech-probe`, no smoke — one Godot at a time, and `traffic.gd` is mid-write by another builder.
- **`traffic.adopt/release/is_driving/driven_speed/stuck_for` do not exist in the tree yet** (as of
  this write `traffic.gd` has only `release_car`). Every call is `has_method`-guarded, so the file
  parses and boots today and the whole FLEE reaction degrades to PLEAD until they land. That
  degradation is ALSO the thing to check first if stage 14 fails: look for
  `REPO ORDERS: flee degraded to PLEAD` in the boot log.
- **`driven_speed` units are assumed m/s** (×3.6 → km/h). If the peer returns km/h the objective
  line will read ~3.6× too fast. One-line fix in `_car_speed()`.
- **`stuck_for` on a body traffic is not driving** is assumed to return 0 (or anything < 5), never
  a large number. If it returns e.g. INF for an unknown body, the boxed-in exit would fire on the
  first FLEEING tick — visible as an instant "TARGET STOPPED".
- Whether the 2.0 s walk actually reads as a person getting into a car is a **screenshot question**,
  not a parse question. Nobody has looked at it.
- `docs/design/systems/the-hook-endless.md` still says under **Open**: *"No pursuit of a fleeing
  debtor"*. That line is now stale. I did not edit it — the doc is not one of my two files.

## 8. Recommended probe sequence — stage 14

`game/scripts/systems/zz_mech_probe.gd` ALREADY carries `_stage_chase()` (line ~843) and it matches
this implementation as written. I did not touch it (not my file). Read against the code it asserts:

| sub | what it does | what this implementation gives it |
|---|---|---|
| 0 | clears the board, heat −10, `push_now(false, true)` | returns true if a curb slot exists; the push line is IDENTICAL to a non-fleeing push (the player must not be able to read a chase coming) |
| 1 | teleports the wrecker to `target + (0,1.2,−14)` | 14 m < `flee_trigger_m` 18, so `_meet` (≤25 m) and the break fire on consecutive ticks; the flee line is the first and only line |
| 2 | waits ≤8 s for `state == 3` and asserts `traffic.is_driving(target)` | state flips to FLEEING at `flee_walk_s` = 2.0 s after the break; `objective_text()` then reads `CATCH THE <MODEL> · <d> m · <kph> km/h` |
| 3 | asserts the car moved > 15 m in 3 s | entirely traffic.gd's to satisfy — ~5 m/s average |
| 4 | rides the bumper, presses hook until `state == 2`, asserts `not is_driving` | `_on_hook()` calls `traffic.release(car)` BEFORE flipping to HOOKED, and the app says TARGET SECURED |
| 5 | releases on the pad, asserts `+$ ≥ 450` | sedan 300 × haul(≥1.0) × rank 1.0 × **1.5** = ≥$450; pickup ≥$675. The card carries `["IT RAN", "×1.5"]` |

Two extra rows I would add if there is room (both cheap, both cover a path stage 14 never walks):

- **14b — boxed in.** After sub 2, park the wrecker across the car's nose and hold for 6 s; assert
  `state == 1` (PUSHED) again, `not traffic.is_driving(car)`, and that the car is still in group
  `"towable"`. Proves `flee_stuck_s` and that a stopped runner is still a job.
- **14c — lost.** After sub 2, teleport the wrecker 800 m away and hold 9 s; assert `state == 0`,
  `order_closed` fired with `"expired"`, the body is NOT in `"mission_target"` and IS in `"towable"`,
  and `freeze == true`. Proves the escape branch and that the world keeps the car.

And one negative row worth having in stage 11 (the non-fleeing order), because it is the failure
mode most likely to appear when traffic.gd changes: assert that a `push_now(true, true)` order —
bad paper AND forced flee — is `_reaction == CALL_IT_IN` and never reaches state 3. Bad paper does
not run; it calls the county.
