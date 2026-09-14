# Round 10 Gait Review — AFTER strips (Movement Mechanics Engineer)

Judged against the brief's real-gait targets (walk ~1.9 steps/s, thigh +30/-10°,
straight knee at heel strike, ~60° swing flexion, near-straight arms; sprint
~3.3 steps/s, thigh +45/-25°, ~110° recovery knee, bent-knee landing under the
body, elbows ~90°, ~8° lean, 8-10cm bounce, a flight phase), cross-checked
against the exact constants in `animate()` (`character_factory.gd`, D-065 GAIT
block), not the pictures alone.

## 1. Per-gait verdict

**Walk (1.4 m/s)**
Reads as a walk: alternating legs, a near-straight knee at heel-strike (walk_side
f3/f7), correct ~1.9 Hz cadence, upright torso, arms swinging opposite the
same-side leg. Single most wrong thing: the thigh's range is +22.3°/-16.6°
(ratio 1.3:1) against the real +30°/-10° (3:1) — the trailing leg swings too
far behind the body instead of staying gathered under it, a "pendulum/scissor"
look rather than a purposeful stride. Cadence, stride length, and knee timing
are otherwise sound.

**Jog (3.2 m/s)**
Reads as a jog: a believable in-between cadence (~2.7 steps/s), knee still
lands close to straight, moderate arm bend, mild lean. Single most wrong
thing: the same hip-bias shortfall as the walk carries through the blend
(+30.6°/-19.6° here), so the back leg again trails visibly further than the
front leg reaches — most visible at the scissored moment (jog_side f3/f7).

**Sprint (6.5 m/s)**
Reads as an all-out sprint at a glance: good forward lean, thigh range
matches the target almost exactly (+45.8°/-25.2° vs +45/-25), correct ~112°
recovery-knee peak, a real bounce. Single most wrong thing: at the moment of
peak stride — the biggest, most visible pose in the strip — the leading leg
is almost dead straight, reaching far out in front of the hips instead of
landing bent and gathered underneath the body. Reads as a stiff, robotic
"goose-step reach," the strongest single candidate for "looks retarded."
Visible in sprint_side f3/f7 and sprint_quarter f3.

## 2. Ranked faults (numeric, from AFTER)

1. **Sprint: stiff straight leading leg at peak reach.** sprint_side f3 & f7
   (also sprint_quarter f3). Real running lands with the knee still visibly
   bent (~90-110° through recovery) and the foot tucked back under the hip,
   never reached way out front on a straight leg. At phase = TAU/4 (frame 3)
   the swing knee-bend term has already decayed to 0 — `cos(ph + 0.35)` goes
   negative past ph≈1.22 rad, well before the thigh finishes its forward
   excursion at ph=pi/2 — leaving only `RUN_LAND`, a mere 0.35 rad (20°), so
   the shank still points ~26° forward of vertical instead of tucking back.
   Fix: `const RUN_LAND := 0.35` → `0.9` (knee bend rises to ~52° at max
   reach, netting the shank to ~6° *behind* vertical — under the hip, per the
   round's own "lands on a bent knee, under the body" comment).

2. **Walk/jog: thigh backswing over-extends, forward reach under-extends.**
   walk_side f3 & f7 (also jog_side f3/f7, smaller). Real walk thigh range is
   +30°/-10° (3:1 fwd:back); code gives +22.3°/-16.6° (1.3:1) because the
   forward bias is too small relative to the swing amplitude. Fix:
   `const WALK_HIP_BIAS := 0.05` → `0.17` (keeps `WALK_HIP := 0.34`'s
   amplitude, shifts the range to ≈+29°/-10°; the jog blend improves
   proportionally since it lerps toward the same bias).

3. **Sprint: total vertical bob exceeds the target bounce.** Compare
   sprint_side f3 (low) against f5 (high) — the swing reads slightly bigger
   than a real sprinter's hop. `RUN_SINK (0.05) + RUN_RISE (0.09)` = 14cm
   peak-to-peak against the target 8-10cm. Fix: `const RUN_SINK := 0.05` →
   `0.03`; `const RUN_RISE := 0.09` → `0.06` (nets ~9cm).

4. **Sprint: elbow never reads as sharply cocked as ~90°.** sprint_side
   f1/f3, sprint_quarter f1/f3. `RUN_ELBOW := 1.30` (74.5°) is the *mean*
   flexion; combined with `RUN_EF`/`RUN_EB` the working range is only
   57°-89°, so the arm looks more "jogging" than "sprinting" at its
   straightest points. Fix: `const RUN_ELBOW := 1.30` → `1.55` (~89°).

5. **Walk: forward arm swing slightly over-bent for "nearly straight."**
   walk_side f2/f7 (the forward-swinging arm). `WALK_EF := 0.30` pushes the
   elbow to 31.5° at the front of the swing; a relaxed stroll's arm rarely
   passes ~20°. Fix: `const WALK_EF := 0.30` → `0.18`.

6. **Stance-leg loading bend peaks at the wrong instant** (lower confidence —
   mostly occluded behind the torso in these strips; worth a dedicated
   stance-side vantage before touching it). The single
   `var stance := maxf(-cos(ph), 0.0)` hump peaks exactly when the thigh is
   vertical — real mid-stance, where the stance leg should be *straightest*
   — instead of just after heel-strike / just before toe-off. At a sprint
   this puts 37° of knee bend (`RUN_LOAD := 0.65`) on the leg that should be
   extending to drive the body forward. Fix: lower `const RUN_LOAD := 0.65`
   → `0.40` as a stopgap, or split `stance` into two smaller humps (post-
   strike + pre-toe-off) for a real fix.

## 3. Needs a rig change, not a constant

- **Ankle / foot roll** (fault 1's residual): even with a bigger `RUN_LAND`,
  the foot is a rigid paddle fixed to the shin — it can't plantarflex at
  toe-off or dorsiflex for swing clearance, so contact always reads as a flat
  stomp rather than a heel-to-toe roll. Needs one ankle bone per leg plus a
  plantar/dorsiflexion curve in `animate()`. Cost: ~0.5-1 day (new pivot, FK
  wiring, re-verify the D-013 no-skate/no-float numeric harness).
- **Pelvis bone** (softens fault 2 and the general quarter/back-view
  silhouette): hip drop/hike and transverse pelvic rotation during single
  support are currently faked entirely through the shared torso's sway/twist,
  so pelvis and ribcage can never move independently the way they do in a
  real stride. Needs a pelvis node the two hip pivots hang from, separate
  from torso lean/twist. Cost: ~0.5 day, moderate risk (hip-pivot local-space
  is a contract other systems read — re-verify colliders/anatomy after).
- **Foot IK**: nothing here guarantees the planted foot is actually locked to
  the ground — the sink/flight curve and the walker's pendulum height are
  both hand-authored curves, not derived from real contact, so residual
  float/penetration on slopes or during tight turns is inherent to the
  current approach. A proper 2-bone leg IK + ground raycast would fix it
  outright. Cost: 2-4 days, the highest regression risk of the three (touches
  the "no IK" contract this rig was deliberately built without).
