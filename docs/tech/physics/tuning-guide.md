# Vehicle Tuning Guide

Canonical reference for the JSON vehicle profiles read by
`game/scripts/vehicle/raycast_vehicle.gd`. Profiles live in
`game/data/vehicles/*.json`; `main.gd` scans that directory at boot, spawns the
wrecker first, and **Tab** cycles through the rest. **T hot-reloads the active
profile in-game** — edit the JSON, alt-tab back, press T, feel the change.
Unknown keys (like `_tuning_math`) are silently ignored, so annotate freely.

Conventions: Godot forward is **-Z**. Physics ticks at 60 Hz. All positions
below are in the body's local frame, whose origin is the center of the collision
box; Y is up, so "height" fields are usually *negative* (below body center).
Every field is optional — the code default is listed in each table.

## Field reference

### Identity and body

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `name` | string | "Unnamed" | Display name shown by the HUD and reload toast. | — | — | — |
| `color` | [r,g,b] 0-1 | [0.8,0.2,0.2] | Albedo of the greybox body mesh. | 0-1 each | black box | white box |
| `body_size` | [x,y,z] m | [2.0,1.4,4.5] | Collision box AND visual box (x=width, y=height, z=length). | 1.6-2.5 / 1.1-2.1 / 4-6.5 | wheels poke out, tips on nothing | catches on world, blocks camera |
| `mass` | kg | 1500 | RigidBody mass. Every force in the profile fights this number. | 900-3500 | twitchy, forces overpowered | inert unless every force is scaled up |

### Center of mass

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `com_height` | m (local Y) | -0.3 | CoM offset from body center. THE rollover/lean knob. Must sit **above** `hardpoint_height` or the car leans *into* corners (see "Lean direction" below). | -0.5 to +0.1 | glued down, no body motion, arcade-flat | leans hard, lifts wheels, rolls over |
| `com_forward` | m (+ = toward nose) | 0.0 | CoM offset along length. Stored as `-com_forward` on local Z, so positive = engine up front. | -0.2 to 0.3 | tail-heavy, spin-prone | nose-heavy, plows/understeers |

### Wheel geometry

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `wheelbase_front` | m | 1.4 | Front axle distance ahead of body center. | 1.2-2.0 | — | — |
| `wheelbase_rear` | m | 1.4 | Rear axle distance behind body center. Long total wheelbase = stable/lazy yaw; short = agile/twitchy. | 1.2-2.0 | darty, nervous | barge-like turning circle |
| `track_width` | m | 1.7 | Distance between left and right hardpoints. Wide = roll resistance and later rollover. | 1.5-2.2 | tippy, wobbly | can exceed body_size.x visually |
| `hardpoint_height` | m (local Y) | -0.3 | Ray origin / suspension mount height. More negative = wheels hang lower = **taller ride height**. Also the height at which tire forces act (see below). | -0.6 to -0.15 | (near 0) body drags on ground | (very negative) stilts, huge lean levers |
| `wheel_radius` | m | 0.38 | Extends the suspension ray and sets visual wheel size + spin rate. Adds directly to ride height. | 0.28-0.5 | body sits low, bottoms out | monster-truck stance |
| `wheel_width` | m | 0.28 | Visual cylinder width only. No physics effect. | 0.2-0.5 | — | — |

### Suspension

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `suspension_rest` | m | 0.4 | Ray travel below the hardpoint. Total ray = rest + wheel_radius. More travel = more visible body motion. | 0.3-0.6 | crashy, bottoms out on bumps | floaty, slow to settle, stilty |
| `spring_rate` | N/m | 45000 | Spring force per meter of compression, per wheel. Set from the mass recipe below, never by vibes. | see recipe | sags past 30%, bottoms out, mushy | pogo-stick, skips over bumps, no weight transfer |
| `damping` | N·s/m | 4500 | Damper force per m/s of compression speed, per wheel. Set as a fraction of critical (recipe below). | 0.3-0.7 × critical | boat wallow, endless bouncing | harsh, transmits every bump, kills float entirely |

### Tires and grip

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `tire_friction` | — (μ) | 1.2 | Friction-circle budget: max total tire force = μ × spring force on that wheel. The grip ceiling for lateral + longitudinal combined. | 0.8-1.5 | ice; slides everywhere | rails; hides all other tuning, feeds rollover |
| `lateral_stiffness` | N per m/s slip | 8000 | How hard the tire fights sideways slip *below* the friction ceiling. Response sharpness, not ultimate grip. | 5000-15000 | vague, drifty, slow to bite | darty, snappy breakaway |
| `handbrake_grip_mult` | 0-1 | 0.3 | Multiplies rear `lateral_stiffness` while Space is held. Lower = looser, easier slides. | 0.1-0.5 | rear becomes a hovercraft | handbrake does nothing sideways |

### Drivetrain and brakes

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `drive` | "front"/"rear"/"all" | "rear" | Which wheels get engine/reverse force. Rear = throttle oversteer; front = throttle understeer; all = traction. | — | — | — |
| `max_engine_force` | N | 9000 | Total drive force at standstill, split across driven wheels. Low-end shove ≈ this ÷ mass. | 6×mass to 12×mass | sluggish | wheelspin past the friction circle, wasted |
| `top_speed` | m/s | 40 | Engine force tapers **linearly to zero** at this speed. Actual top speed lands ~10-15% *below* it, where the taper crosses drag + rolling resistance. | 30-60 | crawls | taper so shallow it never pulls at speed |
| `brake_force` | N | 15000 | Total braking force (0.25 × this per wheel, all four) when moving forward >0.5 m/s. | 8×mass to 14×mass | sails through intersections | nose-dive head-nod stops |
| `reverse_force` | N | 5000 | Drive force applied backwards through driven wheels when nearly stopped. | 2×mass to 5×mass | can't back out of a ditch | comedy reverse burnouts |
| `reverse_top_speed` | m/s | 12 | Reverse force tapers linearly to zero at this reverse speed (the reverse governor). | 8-16 | reverse crawl | freeway-speed reverse |

### Steering

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `max_steer_deg` | degrees | 32 | Max front-wheel angle at standstill. | 25-38 | mall-parking turning circle | scrubby, unstable |
| `steer_speed` | rad/s | 4.0 | How fast wheels move toward the target angle. THE laziness knob: low = languid cruiser, high = darty. | 2-6 | unresponsive, drifts wide | twitchy, impossible to be smooth |
| `steer_falloff` | per m/s | 0.03 | Divides max angle by (1 + speed × this). High-speed stability. | 0.02-0.06 | highway death-wobble | can't lane-change at speed |

### Resistances and misc

| Field | Unit | Default | What it does | Safe range | Too low | Too high |
|---|---|---|---|---|---|---|
| `drag` | N per (m/s)² | 0.5 | Aero drag, quadratic with speed. Sets how hard the top end tapers and coast-down feel. | 0.4-1.6 | glides forever, exceeds intended top speed | hits a wall of air at speed |
| `rolling_resistance` | N | 150 | Constant resistance while moving >0.5 m/s. Low-speed coast decay. | 100-400 | creeps forever at idle | feels like driving in sand |
| `downforce` | N per (m/s)² | 2.0 | Extra downward force with speed². More suspension load = more grip at speed. | 0-6 | floaty over crests at speed | crushes the springs at top speed |
| `angular_damp` | — | 0.5 | Godot angular damping on all axes. Settles yaw after slides and calms roll oscillation. | 0.3-0.9 | pirouettes after every slide | rotation feels like it's in syrup |
| `apply_forces_at_hub` | bool | true | true = tire forces act at the hardpoint; false = at the ground contact point. Contact-point application lengthens the roll lever (more lean, more rollover) for the same profile. | true | — | — |
| `_tuning_math` | string | — | Not read by the loader. Convention: show your spring/damper arithmetic here so the next agent can audit it. | — | — | — |

## The spring/damper recipe

Always derive suspension numbers from mass — never copy them between cars.

1. **Corner mass**: `m_corner = mass / 4` (kg per wheel).
2. **Static load**: `F_static = m_corner × 9.81` (N).
3. **Pick a static compression fraction** of `suspension_rest`: **20-30%**.
   20-23% = taut (trucks, sports), 27-30% = soft (cruisers, boats).
   `spring_rate = F_static / (fraction × suspension_rest)`.
4. **Critical damping**: `c_crit = 2 × sqrt(spring_rate × m_corner)` (N·s/m).
5. **Pick a damping ratio**: `damping = ratio × c_crit`.
   0.30-0.40 = floaty, visible bounce; 0.45-0.55 = controlled; 0.6+ = stiff.
6. Paste the arithmetic into `_tuning_math`.

Worked examples (the shipped cars):

```
Candyland Slab (1900 kg, rest 0.40):
  corner = 475 kg, static = 4659.8 N
  spring_rate 41500  ->  4659.8/41500 = 0.112 m = 28% of rest   (soft)
  c_crit = 2*sqrt(41500*475) = 8880  ->  damping 3110 = 0.35 crit (float)

Baron Brisket (2900 kg, rest 0.55):
  corner = 725 kg, static = 7112.3 N
  spring_rate 56000  ->  7112.3/56000 = 0.127 m = 23% of rest    (taut)
  c_crit = 2*sqrt(56000*725) = 12744 ->  damping 5735 = 0.45 crit
```

Sanity checks after changing suspension:
- Static compression outside 20-30%? Redo step 3.
- Ride height = `(rest − static_comp) + wheel_radius − hardpoint_height` above
  body center; keep ground clearance (that minus `body_size.y/2`) positive.

## Lean direction — the hidden lever

With `apply_forces_at_hub: true`, cornering forces act at `hardpoint_height`.
The vertical gap `com_height − hardpoint_height` is the roll lever:

- **CoM above hardpoint** (e.g. slab: −0.26 vs −0.34): body leans **out** of
  corners and dives under braking — normal car feel. Bigger gap = more lean.
- **CoM below hardpoint**: body leans *into* corners like a motorcycle. Almost
  never what you want; treat it as a bug in the profile.

Rollover threshold ≈ `(track_width/2) / CoM-height-above-ground` in g. If
`tire_friction` exceeds that number, the car can trip over its own grip
(the Brisket does this on purpose: threshold ~0.74 g, grip ~1.35 g).

## Recipes

- **Understeer (plows wide)**: lower `com_forward`; raise `lateral_stiffness`;
  raise `max_steer_deg` slightly; if front-drive, ease off throttle mid-corner
  or switch `drive` to "rear"; check the front isn't overloaded by braking
  while turning (friction circle is shared).
- **Oversteer (tail steps out uninvited)**: raise `com_forward`; lower
  `lateral_stiffness` a touch (softer breakaway) but raise `angular_damp`;
  lower `max_engine_force` or go `drive: "all"`; raise `steer_falloff` so you
  can't dial in as much angle at speed.
- **Float / wallow (bounces after crests, mushy)**: raise damping ratio toward
  0.5; if static compression is over 30%, raise `spring_rate` and re-derive
  damping; trim `suspension_rest`.
- **Twitchiness (darty, oversensitive)**: lower `steer_speed` first — it fixes
  most of it; raise `steer_falloff`; lower `lateral_stiffness`; lengthen the
  wheelbase; raise `angular_damp`.
- **Rollover (lifts wheels, ends up on its roof)**: lower `com_height`; widen
  `track_width`; lower `tire_friction` below the rollover threshold; raise the
  damping ratio; shorten `suspension_rest`; less negative `hardpoint_height`.
- **Drift car**: `drive: "rear"`, `handbrake_grip_mult` 0.15-0.2, modest
  `tire_friction` (~1.0), `lateral_stiffness` 6000-7500 (progressive
  breakaway), `angular_damp` 0.5-0.6 so slides are catchable, plenty of
  `max_engine_force` to sustain the slide, low `com_height` so it never rolls.
- **Grip car**: `tire_friction` 1.3-1.45, `lateral_stiffness` 11000-14000,
  static compression ~20% with damping ratio ~0.55, `downforce` 3-5, low
  `com_height`, wide `track_width`, `drive: "all"` for corner-exit traction.

## Workflow

1. Edit the JSON profile (or copy one as a starting point — new files in
   `game/data/vehicles/` are picked up at next boot and cycled with **Tab**).
2. Press **T** in-game to hot-reload the active profile in place. Note the
   vehicle rebuilds at its current transform; press **R** if it lands badly.
3. Change one field at a time; re-derive spring/damper whenever `mass`,
   `suspension_rest`, or the compression target changes.
4. Record the arithmetic in `_tuning_math` — the loader ignores it, the next
   agent doesn't.
