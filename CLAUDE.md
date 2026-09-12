# Project: EL DORADO GRANDE (DFW open-world game)

An original open-world action game with GTA 5/6 genre DNA — open-world crime fiction, sharp social satire, freedom-first design — set in a fictionalized Dallas–Fort Worth metroplex. Built by Milad (solo dev) + a team of AI agents. Currently in **discovery/pre-production**.

## Canon structure — docs/ is the source of truth
- `docs/research/` — DFW geography, culture, 2026 satire targets, GTA design DNA. Immutable reference; append, don't rewrite history.
- `docs/story/` — story pitches, the chosen direction (`story-direction.md`), character sheets.
- `docs/design/` — map concept, naming bible, mission specs (`missions/`), system specs (`systems/`).
- `docs/tech/` — engine evaluation, architecture, physics/rendering deep dives.
- `docs/decisions.md` — decision log. Every significant creative or technical decision gets one entry: date, decision, rationale, owner.
- `game/` — the Godot project (Milestone 1: Tier-1 greybox driving slice). All tunables in JSON data files; everything agent-legible text.

If code and docs disagree, docs win until the decision log says otherwise.

## Non-negotiable world rules
1. **Parody, never verbatim**: every real place, brand, team, church, and company gets a fictional name, recorded once in `docs/design/naming-bible.md`. Two names for one thing is a canon bug.
2. **No real living person** appears as a character. Archetype composites only.
3. **Satire punches up**: institutions, industries, hype cycles. Never ordinary people, victims, communities, or protected groups. Ethnic neighborhoods are rendered with warmth and specificity.
4. **Playable over watchable**: if a story beat can't be staged as gameplay, redesign it.
5. **Raunch is licensed** (D-006, per Milad): full M-rated GTA register — crude, profane, horny, druggy. The rails in rules 2–3 plus no-sexual-violence / no-torture hold; we ship M, never AO.

## The team (.claude/agents/)
Story-forward team (talk to these for creative work):
- **Story Director** — narrative vision, protagonists, arcs, tone. Milad's primary creative interlocutor.
- **World Builder** — districts, factions, lore, naming bible.
- **Head Writer (Satire)** — radio, ads, social feed, billboards, dialogue punch-up.
- **Mission Designer** — story beats → playable mission specs.

Technical team:
- **Technical Director** — stack, architecture, roadmap, scope guardian.
- **Game Systems Designer** — driving feel, wanted system, economy, progression specs.
- **Physics Engineer** — vehicle dynamics, ragdolls, collisions.
- **Rendering Engineer** — streaming, LOD, lighting, weather, budgets.
- **Customization Designer** — garage, wardrobe, properties, save data model.
- **Environment Artist** — procedural textures/materials, atmosphere, street dressing, screenshot-driven art review.
- **Audio Director** — all-procedural synthesis, the mix, ambience, the radio dial.
- **AI & Traffic Engineer** — every non-player brain: traffic, crowds, police, future foot cops and signal logic.

Design guild (M16, per Milad — depth specialists; they coordinate with the artists above):
- **Scenic Designer** — sky, water, terrain beauty, nature-as-flora.
- **Character Designer** — anatomy, faces, wardrobe systems, archetypes that tell a story.
- **Car Designer** — fleet body design, model identity, per-vehicle driving character (in data).
- **Building Designer** — landmarks, district architecture, skyline, interactivity promise.
- **City Designer** — right-of-way quality: roads, freeways, signals, streetlights, wayfinding.

Mechanics guild (M16, per Milad — how the game plays, one verb each):
- **Driving Mechanics Engineer** — suspension/tire feel, assists, the tunable space.
- **Shooting Mechanics Engineer** — weapon inventory, per-weapon ballistics, gunfeel.
- **Movement Mechanics Engineer** — run/jump/crouch/vault, stamina, movement states.
- **Fighting Mechanics Engineer** — melee: strikes, combos, hit reactions, brawl consequences.

The main session orchestrates as producer. For cross-cutting creative questions, consult Story Director first; for feasibility, Technical Director first.

## The QA loop (autonomous — Milad's standing authorization, 2026-08-10)
Milad: *"set up a qa flow so that you can just iterate and build without my input…
this is nothing close to the quality of what i want."* He should not have to be the
bug tracker. The loop runs without him:

1. **AUDIT** — the **QA Director** agent audits against `docs/qa/quality-bar.md` and
   rewrites `docs/qa/defects.md`. It assumes everything is broken until measured.
2. **FIX** — specialists take the top S1/S2 defects, one owner per file, in parallel.
   Each proves its fix with a measurement or a screenshot at a judgement vantage.
3. **VERIFY** — QA Director re-audits, personally confirming each claimed fix and
   filing whatever the fixes broke. **A builder may never mark its own defect FIXED.**
4. **REPEAT.** Milestone entries go in `docs/decisions.md` as usual.

**TWO FIX MISSIONS MAY NEVER HOLD THE SAME FILE** (D-029). Ownership is exclusive per
cycle and the producer enforces it. Violating it cost a cycle: a shader migration was
dispatched into files a right-of-way pass already owned, a boot was caught carrying 20
`SCRIPT ERROR` lines mid-migration, and the second agent had to freeze a byte-copy of
the tree — with its "before" being that copy minus only its own edits — to produce any
trustworthy number at all. Before dispatching, list each mission's files and check for
intersection. If two missions need one file, run them in series.

**A FIX CYCLE AND A QA CYCLE MAY NEVER OVERLAP** (QA cycle 2, D-084). Eleven world
files were rewritten under an audit in eleven minutes; three gate boots and a full
39-shot sweep ran against a tree that did not parse, and QA had to fall back to a
frozen byte-copy to finish. Either hold all writes until QA reports, or hand it a
named frozen revision. This is the producer's job, not QA's.

**LONG AGENT RUNS STALL — CHECKPOINT TO DISK, AND SALVAGE BEFORE RELAUNCHING** (cycle 5).
Two consecutive QA Director launches died to a stream watchdog with no final report. The
agent definition was fine; the runs were simply long and tool-heavy. **What saved the
cycle is that the first one had already written its evidence to disk** — frozen plates,
gate logs and its own `diff.py` — so the producer finished the measurement from its
artifacts instead of paying for a third pass. Therefore:
- Brief every long mission to **write findings to disk as it goes** rather than composing
  one report at the end. Partial verified findings on disk beat a perfect report that
  never lands.
- **When an agent dies, look in the scratchpad before relaunching.** A stalled agent is
  usually not a wasted agent. **Prefer resuming it** (SendMessage to the same agent id)
  over relaunching fresh — its research context survives the stall; a relaunch pays for
  all of it again.
- **THE STALL HAS A CAUSE: ONE ENORMOUS WRITE (wave 6).** Four of four batch-one
  missions died to the watchdog at the *same* moment — the first tool call that emitted a
  whole 500–1,000-line file. A single generation that long stalls the stream under load.
  **Rule: no tool call writes more than ~120 lines.** Build files in appended chunks
  (`cat >> file <<'EOF'` blocks via Bash, or several targeted Edits), append a line to
  `findings.md` after every chunk, parse-check after every completed file. Put this rule
  in every long-mission brief verbatim.
- Prefer several short focused missions over one monolithic pass, and order the brief so
  the highest-value question is answered first.
- **A 59-vantage `--shot` sweep takes ~1–3 minutes — WITH A REAL RENDERER.** The earlier
  "15–18 minutes" figure in this file was wrong; it was inferred from a run that had in
  fact deadlocked. **`--headless` + `--shot` hangs forever:** the dummy renderer never
  fires `RenderingServer.frame_post_draw`, so `_settle_and_save` awaits a frame that never
  comes. One such process sat wedged for **38 hours** before the producer noticed. Never
  combine them; `zz_shot.gd` now refuses `--headless` outright, as `perf_harness.gd`
  always has. Screenshots and perf run windowed. Only `--smoke` and the 900-frame boot
  gate are headless.
- **`2>&1` IS POSITIONAL.** `godot ... > log 2>&1` is right. `godot ... 2>&1 > log` sends
  stderr to the terminal and leaves a permanently clean log that *looks* compliant — the
  D-075 failure in a disguise that passes inspection. The producer committed it while
  gating cycle 5. Details in `docs/qa/quality-bar.md` §5.
- **Check the machine before quoting §4b: `ps -Ao %cpu,comm | sort -rn | head`.** On 2026-09-08
  Docker Desktop's Linux VM (a Parkway container) held ~90% of a core all afternoon and every
  station read +1–3 ms p95, including the committed tree; the fix was a same-day A/B via
  `git stash`, not a code change. Load average above ~2 on this machine means no ruling.
- **Frame-time numbers taken while other agents are booting Godot are CONTENDED and may
  not be quoted as pass/fail.** Bar §4b demands a quiet machine. During a fix wave, a
  mission may only report *relative* cost from an interleaved A/B on one tree (a
  `--x-legacy` toggle, `--perf-repeat=3`, read `best`). Absolute ≥60 fps rulings happen
  in a producer-run quiet window after the wave lands, with nothing else running.
- **Warm the garment cache before judging a wardrobe** (D-050): a cold `skinw_*` bucket
  lands ~18 s after boot, after the `face` plate. `--headless --quit-after 20000` first
  (~146 s, six `SKIN LIB … ready` lines); a warm `--shot` log has none.
- **Run `--script` tools under a watchdog.** A tool that errors inside `_init` never reaches
  `quit()` and idles forever at 1% CPU; two gate chains wedged on that this way.
- **Godot's front face is CLOCKWISE** — (b−a)×(c−a) points INTO the body on a front face
  (D-021, D-051). Verify any new mesher with `--shot --shot-debug=normals`: a camera-facing
  surface must be blue, never yellow. D-051 rendered every skinned character inside out for
  three milestones because a metric encoded the wrong-handed rule.
- **The 3D view renders at the WINDOW size, and the game window is 1280×720 by default**
  (Codex's `project.godot` override over the 1600×900 canvas). `perf_harness.gd` and
  `zz_shot.gd` pin their own 1600×900 window (D-053); any new measurement tool must do the
  same or its numbers are not comparable — check the `PERF HARNESS:` size or the plate size.
- **A null control is not optional.** Before trusting any two-plate differential, diff two
  plates of the *same* configuration. Cycle 5's "five vantages where the beacon subtracts
  light" appeared identically in the null control — it was traffic drifting between
  boots, never the beacon. The harness noise floor on a QUIET machine is ~11–12k touched
  pixels across 59 vantages; at load average 8 (2026-09-12) two identical sweeps differed by
  801k. Never quote the number — pass the null control (`game/.gate/null/B`) to
  `plates_diff.py --null` and let the per-vantage 3× rule decide.

**WORKING MODEL SINCE 2026-09-06 (Milad: "the fan on my computer was going crazy").**
The main session (Fable) **makes the code changes itself.** Haiku/Sonnet subagents do only
bounded, low-cost work: run a named command, capture its output to a file, parse a table,
report facts. **One Godot process at a time, always** — the fan incident was four concurrent
Opus missions each running windowed Godot with SDFGI/SSR/volumetric fog, plus perf and
screenshot sweeps, simultaneously. Headless for smoke/boot gates; windowed only for a
screenshot or a perf number, never two windowed runs in parallel. Never edit a game file
while a runner is booting the tree — a half-written file poisons its next boot (D-084).
Runners never edit `game/` or `docs/`. Long-mission builder agents are the exception, not the
rule, and need Milad's say-so.

Standing rules the loop exists to enforce:
- **"Better than before" is not a pass.** The bar is absolute.
- **Measure it.** Every quality breakthrough in this project came from a number
  (rim lift, wheel offset, chest span, face-normal direction) and every plateau came
  from trading opinions about screenshots.
- **Look from the bad angle.** Judgement vantages exist in `zz_shot.gd`:
  `face`/`torso`/`side`/`back` for people, `car_34`/`car_side`/`car_rear34`/`car_wheel`
  for vehicles, plus the night vantages. A thing that cannot survive those is not done.
- **CURRENT TOGGLES (2026-09-06)** — all from one tree, so A/B is never a before/after:
  `--env-photo` (full light set, fails §4b), `--env-budget` (the default, explicit),
  `--env-legacy` (M22 look), `--env-no-{sdfgi,ssr,volfog,taa,farshadow,grade,scatter,exposure}`,
  `--env-aa=off|msaa2|msaa4|msaa8|taa|msaa2taa|msaa8taa`, `--factory` (the M22 rigid-part body; skinned is the default since D-050),
  `--skinned-bare` (body with no garment shells — bisects body vs wardrobe),
  `--gfx-legacy` (M22 materials), `--shot` (59 plates, windowed), `--hudshot` (the live HUD,
  windowed), `--perf` (see `docs/tech/rendering/perf-harness.md`), `--nobeacon`,
  `--surf-census-quit`, `--mech-probe` (D-056), `--shot-debug=normals|unshaded|lighting|overdraw` (the sweep through a
  G-buffer view — normals answers "mesh or light?" in one plate; D-051 was found with it).
  Boot census lines: `RENDER:`, `SURFACES:`, `SKIN LIB:`, `SKIN MICRO:`; `SHOT sun:` at `face`.
- **Mechanics probe (D-056):** `godot --headless -- --mech-probe` — 27 checks in ~40 s: legible
  heat, brake lamps and horn, the Full Eight (fire, four effects, self-end, restore), busted
  (card, impound, fine). Prints `MECH PROBE: PASS (n/n)`. Windowed with
  `--mech-shots=/abs/dir` it also saves `full_eight.png` and `busted.png`. Run it after any
  change to police/on_foot/full_eight/arrest/vehicle_lamps/vehicle_audio.
- **Taste (D-056):** `docs/design/taste.md` is the discretion for autonomous rounds — thesis,
  ten principles, the rubric, the DNA scorecard, the ranked backlog, anti-taste. Load it before
  choosing what to build; re-score the card at the end of a round.
- **Milad's task inbox:** a shared Apple Note, "El Dorado Tasks". `game/tools/tasks_note.sh`
  reads it from Notes.app and diffs against `game/.gate/tasks_seen.txt`; run it at the start of a
  session and between rounds, and work new items before the backlog.
- **Codex's tools (2026-09-06, kept):** `tools/character_review.gd -- --out=DIR` (windowed;
  a neutral stage, fixed light, matched `face/profile/full/back/gait/normals/cast` plates —
  the right before/after instrument for people, 25 s) and `tools/session_test.gd --
  --session-test` (headless; 34 session-flow checks, prints `SESSION TEST: PASS`). Both are
  part of the gate for character and session work.
- **Character modules since 2026-09-08:** `character_hands.gd` (Codex; hands are their own
  3 mm field meshes on the forearm joints, not part of the 18 mm body field) and
  `_tailored_piece` in `skinned_character.gd` (collar, placket, pockets are fabric grids
  projected onto the body, not shells — `skin_rim.gd` skips them). The review tool has a
  `collar` close-up and a `collar_normals` view.
- Milad's input is welcome at any time but is never required to continue.

## Tooling (D-055, 2026-09-12) — one command per question
- **`game/tools/gate.sh`** — THE gate. Quick: machine load, parse (one boot, every script), lint,
  smoke ×2, boot 900, session harness. `--full` adds the warm garment cache, the 59-plate sweep
  under its watchdog, a plate diff against `GATE_PREV_PLATES` (with `GATE_NULL` as the null
  control), and perf — which it REFUSES under load (`CONTENDED`). Writes `GATE.md` + logs to
  `$GATE_OUT`. Use it instead of hand-writing chains: every chain written by hand this month had
  a bug in it (redirect order, a crop loop, a missing copy).
- **`game/tools/parse_all.gd`** — every `.gd` compiled in one headless boot, 4 s, exit 1 on any
  failure. Also the pre-commit hook (`.git/hooks/pre-commit`, machine-local; re-create it from
  D-055 on a fresh clone). It found a tool that had not parsed for weeks.
- **`gdlint`** (gdtoolkit in `.venv/`, `.gdlintrc` = substance only: names, unused args, duplicated
  loads, returns). Zero findings is the bar; deliberate exceptions carry a bare
  `# gdlint:ignore=<rule>` at the end of the line, explanation on the line above.
- **`game/tools/plates_diff.py BEFORE AFTER [--null CTRL] --report out.md`** — per-vantage
  meanAbs and px>16 with the noise floor built in; a vantage is flagged only when it exceeds
  4,000 px AND 3× its null-control change. The null control lives in
  `docs/qa/evidence/null-control/`; regenerate it after any change to traffic or spawning.
- **`game/tools/gpu_trace.sh STATION`** — the GPU column the harness never had: boots the perf
  station, attaches Instruments' Metal System Trace for 12 s of measured frames, and prints
  GPU wall/busy per frame plus the vertex/fragment/compute mix (`tools/gpu_frame.py`).
  Instruments adds overhead: read splits and mixes, not absolutes against §4b.
- **`game/tools/character_review.gd`** (matched-view people plates), **`session_test.gd`**,
  **`--shot-debug=normals`**: see the toggles above.
- **Not adopted, and why:** Blender/Substance pipelines (asset files are out of canon), RenderDoc
  (no Metal), a Godot editor MCP server (a second Godot process; the CLI tools already answer
  the questions), gdformat (it would rewrite every file's style in one commit).

## Working conventions
- Ambition is tiered (see `docs/tech/engine-evaluation.md`): greybox driving slice → stylized vertical-slice district → systemic open city. Don't build tier-2 features before tier-1 acceptance.
- Tunables live in data files (JSON/text), not code — the pipeline must stay AI-agent-legible.
- Estimates are honest. A month is "a month."
