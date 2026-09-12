# Face and body refinement — 2026-09-08

Baseline: the M25 / cache-v13 code found in the workspace on September 8,
including the existing shoulder, calf and elbow revisions. Those changes were
preserved. Earlier September 6 screenshots are not used as this pass's baseline.

Changes:

- Broaden the chest's forward mass and increase upper-back depth.
- Extend and widen the feet, retaining the existing knee and ankle animation.
- Remove coarse hand masses from the body field. New hands are continuous
  surfaces generated at 3 mm resolution, with a palm, thumb and four fingers.
  They attach to the existing forearm joints, use shared left/right meshes and
  generated LODs. Fingers have a resting curl; they are not individually animated.
- Reduce the mouth area's projection, narrow the mouth crease, move eyes and
  brows inward, narrow the eye openings, and add raised upper eyelids.
- Reduce the shared skin shader's micro-normal strength from 0.60 to 0.22.
- Cache version 15 invalidates obsolete body and garment geometry.

Measurements from actual Book body mesh vertices at nominal scale:

| Measurement | Before | After |
|---|---:|---:|
| Foot Z extent below Y=0.10 m | 226.2 mm | 292.5 mm |
| Chest Z extent, Y=1.30–1.37 m and abs(X)<0.10 m | 254.2 mm | 265.5 mm |

These measurements describe the mesh changes, not a certification of all
anthropometric requirements. Rig pivots, physics and seeded RNG order are unchanged.

Evidence: `evidence/anatomy-sept8/comparison.html` includes matched before/after
views plus hand detail, body profile and walking pose. The final renderer and
session integration run completed without error lines. The first segmented hand
prototype was rejected in visual review and replaced with the continuous mesh.

Remaining work: collar and pocket edges still show coarse geometry; body clothing
folds, facial hair, ears and hats remain procedural. Finger gripping and facial
animation are not implemented by this pass. No full quality-bar or performance
signoff is claimed.

Final verification: 900-frame full-game boot completed with zero error lines;
session integration PASS; two driving smoke runs matched the established baseline
exactly. Logs are saved with the comparison.

## Continuation — 2026-09-08 (Claude, after Codex's usage ran out)

Codex continued past this report into an undocumented layer, cache v17: the collar
stand, placket and pockets as tailored fabric meshes (`_tailored_piece`) replacing the
voxel shells. That layer parsed, baked and booted clean as found. Finished here (cache
v18): collar leaves layered 2 mm over the stand (they shared its offset and z-fought at
the junction), pocket flaps, placket relief 5 mm, and the surface beard turned into
feathered stubble. Recorded as D-054; matched views in `evidence/anatomy-sept8/continuation/`.
