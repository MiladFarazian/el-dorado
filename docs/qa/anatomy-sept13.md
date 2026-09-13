# Anatomy, measured — 2026-09-13 (D-061)

Milad: *"character still looks unnatural, design better with more realistic body structure."*

The body is a field of capsules (`skinned_character._prims`). Nobody had measured its silhouette;
`tools/body_measure.gd` now does — the 18 mm body field, sliced at anatomical heights: outer
x-span, depth (z-span), and each separate mass across x with its width. Targets are for an
adult male of ~1.78 m (biacromial 0.40 + deltoids, chest 0.33–0.34 wide at the nipple line and
~0.25 deep, waist ~0.30, trochanters ~0.36, thigh ~0.17 wide at the top, knee ~0.11, calf ~0.125,
ankle ~0.07). Cells are 18 mm, so every number carries ±18 mm.

| height | y | before | after (r2) | target |
|---|---|---|---|---|
| shoulders (deltoid span) | 1.425 | 0.450 | 0.468 | ~0.47 |
| chest, trunk width | 1.300 | merged with the arms | merged with the arms (notch opens at 1.19) | 0.33 |
| chest depth | 1.300 | 0.252 | 0.252 | ~0.25 |
| under ribs, trunk | 1.190 | 0.270 | 0.324 | 0.32 |
| waist, trunk | 1.080 | 0.270 | 0.288 | 0.30 |
| belt, trunk | 1.030 | 0.270 | 0.288 | 0.31 |
| hips | 0.900 | 0.378 | 0.378 | 0.36 |
| upper thigh, both | 0.760 | 0.378 | 0.360 | 0.36 |
| mid thigh, each | 0.650 | 0.144 | 0.162 / 0.144 | 0.15 |
| knee, each | 0.480 | 0.126 | 0.126 | 0.11 |
| calf, each | 0.370 | 0.108 | 0.126 | 0.125 |
| ankle, each | 0.110 | 0.072 | 0.072 | 0.07 |
| upper arm | 1.250 | 0.090 | 0.090 | 0.09 |
| wrist | 0.930 | 0.054 | 0.054 | 0.055 |

**What the numbers said before the eye did:** the limbs, pelvis and thighs were within a cell of
real; the TRUNK was the fault — 0.27 m wide from the ribs to the belt with no taper (a tube, 15 %
narrow), and the arm hung inside the chest's radius (the armpit welded). That is the "coat hanger
on two pipes" every plate showed and no amount of face work would fix.

**What changed (`_prims`):** the rib cage is an egg — r 148 at the ribs, 146 under them, 124 at the
waist; the top section narrows toward the clavicles (126 up top, 146 at the ribs — the first cut
carried the rib width up under the deltoid and made a shoulder pad); a flattened lat per side from
the armpit to the waist gives the back its V and the flank its taper; the shoulder pivot moved
0.183 → 0.192 so the arm clears the chest; deltoid 50/46 → 47/45; the gut is now scaled by the
girth roll (none on a lean build); pelvis 132/150 → 130/143; thigh 88/68 → 92/62 (a quad and a
knee); a fuller gastrocnemius. Cache v20.

**Posture (`animate`, D-061):** arms hang ~7° off the flanks with elbows just unlocked, the feet toe
out ~8° and stand a shade wider than the hips — constant in both gaits.

**Still open:** the armpit notch at the nipple line does not resolve at 18 mm (it opens one cell
lower); the deltoid still reads square in the sleeve; the shirt and trousers are palette paint, so
cloth volume is a shell-wardrobe milestone (D-060); no scapulae; the boots are loaves.

## Round 7 (D-062): the boot, the deltoid, the back

Three foot rows joined the tool. The old foot was three round masses of the same height: a bread
roll on a sole. The boot is a shaft over the ankle, a vamp that slopes from the instep down to a
low toe box, a heel block, and a thin welted sole.

| height | y | after (r3) | reading |
|---|---|---|---|
| ankle | 0.110 | width 0.090, length 0.108 | the shaft |
| instep | 0.085 | width 0.090, length 0.162 | only the rear half of the boot reaches this height — the toe is lower |
| vamp | 0.050 | width 0.090, length 0.288 | the full boot |
| sole | 0.020 | width 0.090, length 0.306 | the welt |

Also in r3: two pecs with a sternum between them (the single bar read as a chest plate), two flat
scapula mounds, a deltoid cap 18 % taller than wide (rounds the acromion corner), the trapezius
slope ending 6 mm lower, and the waist carried 12 mm forward for a lumbar curve. Trunk rows are
unchanged from r2 (ribs 0.324, waist 0.288, shoulders 0.468). At 1.25 the arm and trunk now read as
one mass at 18 mm — the lat's outer edge is one cell from the arm's inner edge; the posed abduction
opens it in game.
