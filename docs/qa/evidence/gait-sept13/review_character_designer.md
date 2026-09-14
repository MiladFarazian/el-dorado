# Character Designer Review — Round 10 (D-065)

## Verdict
1. The gait rewrite is the one change that actually reads: `sprint_side`/`jog_quarter` after now show real elbow flexion (~90°) and forearm swing where before the arms were straight pendulums — running no longer looks broken.
2. The three body-prim edits (knee 20mm in, deltoid centre 2.5cm down, rib r148→r151) are real in `body_measure.gd`'s numbers but too small to read in a full-body plate: `front/full/body_side/back/torso/face/hand/profile` are visually indistinguishable from BEFORE.
3. The trunk taper that makes this read as a body at all (ribs 0.324 / waist 0.288 / hips 0.360, all within a cell of target) was won two rounds ago (D-061/D-062), not this one — round 10 spent its geometry budget on a fix whose own headline complaint (the A-frame) still doesn't visibly resolve.
4. The single most damning "not a person" cue — the arm fused into the torso with no armpit crease anywhere near the chest — is untouched by round 10 and is worse than the knee angle for reading as a mannequin, not a man.
5. Net: Book moves like a person now; standing still, he looks exactly as he did before this round shipped.

## Ranked faults

**1. No armpit crease anywhere near the chest — the arm reads welded to the torso.**
Plates: `front.png`, `torso.png` (both after2). A real underarm crease starts at the
nipple line (the bra line). `measure_after.txt` shows the field still fused there: at
y=1.300 (nipple line) the whole shoulder+torso+arm is ONE mass, 0.504m wide; the gap
only opens at y=1.190, a full rib-height (0.11m) lower than it should. This is the
"still open" defect from D-061, never touched by round 10. Change: the rib-cage's top
section, `skinned_character.gd:587` —
`out.append(_cap(Vector3(0, 1.412, -0.010), Vector3(0, 1.320, -0.010), 0.126 * w, 0.146 * w, Vector3(1, 0.60, dep - 0.02), 0.034, B_TORSO, 0))`
— needs to taper faster above y≈1.30 (or the arm's smin at `skinned_character.gd:668`
needs a smaller k / more clearance) so the notch opens at the nipple line, not below it.

**2. The knee-inboard fix (this round's headline) doesn't read at full-body distance.**
Plates: `front.png`, `full.png` — pixel-indistinguishable from BEFORE at this crop.
An adult male's visible hip-to-knee valgus reads closer to 8-10°; `KNEE_IN := 0.02`
over the 0.38m thigh drop (`HIP_PIVOT.y` 0.880 → knee 0.500) is atan(0.02/0.38) ≈ 3°.
The gait-strip table in `anatomy-sept13.md` (round 10 row) shows a genuine 52mm drop in
knee-to-knee outer span (0.340→0.288m), but at this render's ~350px/m scale that is a
~9px shift per leg, lost in the trouser shading. Change: `const KNEE_IN := 0.02`
(`skinned_character.gd:74`) wants roughly doubling (~0.035-0.04) and a re-shot `front.png`
to confirm it is visible, not just measurable.

**3. The knee is nearly as wide as the thigh and calf — no joint taper.**
Plates: `front.png`, `body_side.png`. A real knee is the leg's narrowest girth, visibly
less than the calf belly and the mid-thigh above it. `measure_after.txt`: mid-thigh
0.144-0.162 (target 0.15, hit), knee 0.126 (target 0.11 — 14%, a full cell over), calf
0.126 (target 0.125, hit). The knee is statistically THICKER than target and equal to
the calf, so the leg reads as one even-width tube through the joint. Change: the knee
capsule, `skinned_character.gd:514` —
`out.append(_cap(Vector3(kx, 0.500, 0.008), Vector3(kx, 0.452, 0.004), 0.062 * lg, 0.058 * lg, Vector3(1, 1, 1.04), 0.018, kb, 0))`
— bring 0.062/0.058 down toward ~0.050/0.048 to land the diameter near the 0.11m target.

**4. The deltoid still reads as a rounded block, not a shoulder.**
Plates: `front.png`, `back.png` (the shoulder-to-sleeve line). A real deltoid tapers
into the bicep distinctly faster than it swells outward — a ball-and-taper, not a
cylinder. `skinned_character.gd:668` —
`out.append(_cap(Vector3(sx - ax * 0.004, 1.395, 0.002), Vector3(sx + ax * 0.010, 1.330, 0.004), 0.048 * lg, 0.045 * lg, Vector3(1.0, 1.06, 0.97), 0.016, sb, 0))`
— only goes r48mm→r45mm over 6.5cm, squashed 3% in z. Round 10 moved this capsule's
Y-centre down 2.5cm (per D-065) but never touched its taper or roundness, so the
`anatomy-sept13.md` r2 note "the deltoid still reads square in the sleeve" still holds
two rounds later. Change: steepen the taper (e.g. 0.050→0.036) and tighten the z-scale
toward ~0.85 so the cap reads spherical from front and side, not boxy.

**5. No waist-to-hip cinch visible from the front.**
Plates: `front.png`, `full.png`. Waist (target 0.30) should read ~17% narrower than
hips (target 0.36) even head-on, not only in profile's lumbar curve. The trunk data IS
there (waist 0.288 vs hips 0.360, `measure_after.txt`) but it never reaches the eye
because the belt geometry sits exactly at the transition (`skinned_character.gd:647`,
`y=1.058→1.016`) and visually resets the silhouette before any taper above it is
visible. Change: no radius here needs to move — carry the narrow waist radius up to
about y≈1.09-1.10 before handing off to the belt ring, so a sliver of taper shows
above the buckle in a front plate.

**6. Hands read as a fused paddle.**
Plate: `hand.png` (unchanged before/after — out of round 10's scope, owned by
`character_hands.gd`). A real hand's fingers taper toward the tip and the thumb sits
opposed, out of the palm's plane; here the four fingers are near-uniform-width
cylinders in one plane with the thumb barely rotated out of it. Flagged last because
it is out of scope this round, but it is the closest-range plate in the set and reads
"not a person" the instant a sleeve rides up (rolled cuffs, short sleeves, a raised arm).

## Is cloth volume now the dominant fault?
Not yet — fault #1 (the missing armpit) and #3 (the knee's girth) are body-field bugs
that a shell wardrobe would inherit and amplify, not hide, so they should be fixed
before spending on cloth. But cloth is close behind and will overtake the list the
moment those two land: because the shirt is palette paint on the same capsules, every
fold, drape and gather this game will ever show is currently zero — the sleeve is a
smooth arm, the collar stands proud only because it is real geometry, and the shirt
between the pecs, at the small of the back, and above the belt has no thickness at all,
which is why fault #5's waist never reads (a real shirt would drape and gather right
there, doing the storytelling the body can't). A minimal shell wardrobe should NOT try
to cover the whole torso at once: it needs, in order, (a) a sleeve shell from deltoid to
cuff, separate from the arm, so it can drape looser than skin and finally sell the
armpit gap fault #1 is fighting for; (b) a torso shell with a hem that can gather at the
waist/belt line, since that is the one place a shirt visibly differs from skin on a
standing figure; and (c) trouser volume at the knee and seat, since flat-painted trousers
over a capsule leg is the most common wide shot in the game (walking, driving, standing
at a corner) and currently shows a knee that bends but never creases.
