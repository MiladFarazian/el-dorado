# Cloth volume — 2026-09-13 (D-067)

Milad (round 10): *"Make it look like an actual person."* Both guild reviews named cloth volume
as the next lever: the shirt and the trousers were PAINT on the body.

- `before/` — round 10's final plates (cache v24): shirt and trousers painted on the skin.
- `after/` — the clothes as constant-offset shells of the body field (cache v28): the shirt
  (hem to the neck's foot, armhole to armhole), the sleeves (short to 1.265, long to the cuff),
  the trousers (one piece, waistband to the boot), the tail of an untucked shirt, shorts.
  10 mm off the skin, 12 mm thick, 4 mm cells, zones inherited from the skin under them,
  weights inherited from the skin under them (so `sprint_side.png` moves as the skin does).
- `lace/` — the three passes that taught the rules: `full_r1_wrist_ring.png` (a full-field
  hip band rang the wrist — the belt's old bug), `torso_6mm_on_6mm.png` (6 mm cloth on 6 mm
  cells bakes as lace: a sheet needs three cells across it), `torso_r3_sleeve_ring.png` (two
  sleeve parts meet in a ring — every part closes its cut with a wall; a garment is one piece).
- `plates/` — the in-game sweep: `showcase_people`, `torso`, `face`, `hero_*` with the crowd dressed.
- `gate_quick.md` — the gate on this tree.

Costs: the garment library per bucket went 6.8 MB → 40.7 MB on disk (six buckets, baked once,
~63 s each on a worker thread; the first boot after a cache bump dresses the crowd over four
minutes). The merged wardrobe per layout is LOD'd as before. No perf ruling: load average 6–9
(the Virtualization VM) all evening.
