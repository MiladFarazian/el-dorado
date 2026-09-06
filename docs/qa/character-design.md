# Character design pass — 2026-09-06

User request: improve character design. Changes are in the production character
factory (shared faces/hair for Book and NPCs) and the skinned wardrobe.

- Reduce the lower-jaw ellipsoid width and lateral jaw relief; broaden the chin's
  central support to remove the narrow point below the inflated jowls.
- Replace the eyebrow bead chains with tapered strips fitted to the face.
- Replace protruding eye/lid primitives with almond-shaped surface meshes,
  per-person irises, pupils, catchlights and thin lid margins. The socket relief
  remains part of the head. Eye and eyebrow offsets stay under 2 mm by construction.
- Replace hair bands and oversized hair spheres with a closed scalp-following
  mesh, shaped hairline, hairstyle-dependent volume, and rear lengths for long
  and tied hair. Bald configurations now expose the scalp.
- Lower the collar stand from 1.525–1.578 m to 1.505–1.542 m and expose the neck
  above it. Garment cache version 11 invalidates the old tall shells.
- Book keeps his western outfit, pearl snaps, denim and boots; change the shirt
  from bright white to a warmer, darker ivory so its cloth reads more clearly.

Review tool: `game/tools/character_review.gd`, run windowed with
`--script res://tools/character_review.gd -- --out=/tmp/character-review`.
It uses a neutral isolated stage, fixed lighting and matched camera views,
and includes a 120-second watchdog. It also captures a walking pose, normal
buffer, and five seeded NPC heads. No physics, rig pivots, or RNG draws changed.

Evidence: `evidence/character-design/comparison.html` has the matched before/after
renders. Face/profile/full/back, walking pose and NPC cast were visually inspected.
The normal-buffer render shows outward-facing surfaces on the revised face.

Remaining limitations: stylized procedural assets, not realistic scans; beard
patches and hats still need refinement, as do the garment edges and hand anatomy.
This is a targeted design improvement, not certification of the entire character
quality bar or a measured performance claim.

Validation: final 900-frame full-game boot exited successfully with zero error or
warning lines. Two smoke runs returned the identical established driving result.
Logs are saved beside the render evidence.
