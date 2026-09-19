# The audit's top three — round 18, 2026-09-18 (D-073)

Built straight from `docs/qa/defects.md`'s new entries (D-153/D-154 the HUD notice controller,
D-129/D-157/D-102 the crowd's one body and no neck, D-156 the armhole) plus two tooling defects
(D-160 the reticle in every plate, D-164 the chase probe's weak pay row).

- `mech_probe.log` — the headless probe on this tree.
- `plates/` — `review_*` (the character review tool on the v29 cache: face, profile, collar,
  collar_normals, full, cast, walk_side), `showcase_people` / `torso` / `boone_wade` from the
  18c sweep, the mechanics plates from the 18c windowed probe (`takeover` is 18d's, from the
  probe's own camera), `armhole_new_x3` (Book's right armpit at the sweep's torso vantage),
  `reticle_18a_18b` (the dot that survived two hides) and the two earlier takeover plates
  (`takeover_18a_chase_cam`, `takeover_18b_no_club`) for the record.
- `gate_quick.md` — the gate on this tree.
- `builders/` — the two findings files (the notice controller, the character work).

## Producer notes for the next audit (what the plates showed, 2026-09-18)

- **The neck (D-102)**: `plates/review_face.png` / `review_profile.png` — a run of skin from
  the jaw to the collar band on Book; the band no longer touches the chin. `review_collar.png`
  shows a dark ring between the band and the shirt's neck hole: the two are separate pieces
  and read as an inset stand. Not filed; QA to rule.
- **The armhole (D-156)**: the lens-shaped void to the background is gone at `full` and at
  the sweep's `torso` (`plates/armhole_new_x3.png`, Book's right armpit at 3×) — the flank
  under the sleeve is now shirt. What remains is a dark CAVITY between the sleeve's inner
  wall and the trunk from a low angle: the sleeve hangs ~30 mm off the arm. The review
  tool's own `torso` shows the sleeves billowing like a blouse — that plate looked the same
  in `cloth-sept13/after/torso.png`, so it is a D-067 property, not a v29 regression.
- **The crowd (D-129/D-157)**: `plates/showcase_people.png` — five in frame, four stances
  (easy, arms folded ×2, a phone in hand), heads at different yaws, no two alike. The
  showcase row was in the bind pose in every earlier plate (never animated).
- **The takeover plate** (18a–18e): from the chase camera only two of fourteen were in
  frame; 18b–18d took it from the probe's own camera and showed NONE — the probe dropped the
  heat in the frame it requested the plate, the takeover completed on the next tick and sent
  the club home before the capture's second frame (the plate's own ticker carried THE CLUB'S
  THANKS). The numbers, headless, at the five-second mark: 14 on the lot, radii 6.9–11.9 m
  (mean 8.0) from TAKEOVER_POS, 7 standing, 5 still walking in, **2 DOWN** (knocked over —
  by what is the next question; `pedestrians.downed_by_player` is not charging Book for it),
  every rig visible and in the tree, 17–27 meshes each all drawn, no empty AABB, scales
  0.82–1.12 (the widened ranges, as a non-uniform scale). 18e holds the heat drop for half a
  second after the plate. Also learned: `pedestrians.gd` passes `moving = (state != DOWN)` to
  `animate()` for every ped, so the stance path is reached only because the factory derives
  "walking" from speed — a standing club member does get a stance.
- **The reticle (D-160)**: hiding every CanvasLayer once at boot was not enough — combat
  re-shows its layer when it goes active, and the ticks were in every 18a plate. 18b hides
  them before every capture; judge `sweep2`.
- **The phone plate**: 18a's `phone_paper.png` had no phone — the probe closed it in the
  frame it opened (the capture is a coroutine). 18b closes it a frame later.
- **Two objective lines at the takeover**: tow_hook's "NO BOOM — THE WRECKER DOES THAT"
  printed 15 px above the HUD's "SLIDE OUT — LOSE THE TASK FORCE". The HUD's prompt slot
  carries the hook hint now (`tow_hook.hint_text()`); tow_hook's label never joins the tree.
- **Still there, not this round**: `order_push.png` is black — the chase camera is inside
  geometry at that moment (it was in round 16 too); the faded "BOOT" over the wallet in
  `phone_paper.png` is the SADDLERY · BOOTS MADE TO ORDER sign on the building behind the HUD,
  not a notice (18b's plate shows the whole sign); the probe's stage 14 asserted the IT
  RAN row in the frame the order closed, before the notice controller had shown the card
  (93/94 headless AND windowed) — 18b polls up to 6 s.
