# Gait and body, round 10 — 2026-09-13 (D-065)

Milad: *"The running looks retarded and the character's proportions and body still looks like
shit. Make it look like an actual person."*

Plates from `tools/character_review.gd` (neutral stage, fixed light), downscaled by half. The
gait strips are new this round: eight frames across one full stride at phase marks of TAU/8,
side-on and from the front quarter, at 1.4 / 3.2 / 6.5 m/s.

- `before/` — the tree at adc0fed (round 9).
- `after/` — this round, final pass: `character_factory.animate()` rewritten (plus the Movement
  Engineer's four constants), `skinned_character._prims` knees 28 mm inboard, knee r52, deltoid
  lowered and tapered, lats inboard, cache v24. The review stage has SSAO now.
- `measure_after.txt` — `tools/body_measure.gd` after: knee 0.108 each (target 0.11), knee outer
  span 0.252 (centres ±0.072, were ±0.106), ankles under the knees, shoulders 0.468, trunk
  unchanged, the arm one cell clear of the trunk at the armpit floor.
- `review_character_designer.md`, `review_movement.md` — the two guild reviews of the FIRST
  pass (read-only, Sonnet); their top items are what the final pass changed.

What the strips showed BEFORE (`before/sprint_side.png`): a sprint that is a walk with a lean —
legs barely open, arms hanging, no knee lift. Three causes, all in `animate()`: a fixed 1.74 m
stride (7.5 steps a second at 6.5 m/s), a 12/s pose blend that halves a 3.75 Hz signal, and a
knee that flexed in stance and swung forward straight.

AFTER (`after/sprint_side.png`): stride 4.0 m at a sprint (3.3 steps a second), heel to the
seat in recovery, a landing on a bent knee under the body, elbows at ~90 with the hands between
the hip and the chin, a 10-degree lean, a designed 9 cm bounce. The walk (`after/walk_side.png`)
plants its supporting foot at every phase (it floated 5 cm at double support before).

Body (`after/front.png` vs `before/front.png`): the femur angles in, the shins are vertical, the
shoulder line runs neck to acromion to round to arm without a corner.
