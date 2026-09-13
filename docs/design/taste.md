# Taste — how EL DORADO GRANDE decides what to build next

**Owner:** the producer (main session). **Ratified as working practice 2026-09-12** under
Milad's direction: *"Build up taste and discretion to iterate on improvements without me,
because a lot of work still needs to go into design and mechanics."* This document is the
discretion. It is loaded before any autonomous round and it is what a round is judged against.
Canon it derives from: `docs/story/story-direction.md` (the spine), `docs/research/gta-design-dna.md`
(§8 is the scorecard), `docs/qa/quality-bar.md` (the bar), `docs/decisions.md` (what already landed).

## 1. The thesis, in one line each

- **The story:** extraction versus stewardship. The neighborhood is never the joke; the paperwork is.
- **The protagonist:** Booker "Book" Reyes, a repo man who used to ride bulls. Holding on is his
  discipline; letting go is his need.
- **The game:** *the Hook and the Paper ARE the game* (story bible §12, binding). Everything else
  is water.
- **The feel we borrow:** GTA's world as a reagent — systems that react to the player interestingly,
  wide not deep, and a wanted ladder that is legible, survivable and exitable.

## 2. Ten principles, each with a test

1. **Verbs before views.** A mechanic a player touches in minute one outranks any plate.
   *Test:* a fresh boot, ten minutes, no menu — did the change get used?
2. **Every output is another system's input.** *Test:* name the two systems that read the new
   state before writing it. A system with no reader is a screenshot.
3. **Heat is legible, survivable, exitable** (DNA §4). *Test:* the player can say, live, why the
   star lit, what is coming, and two ways out.
4. **Every verb has sound + visual + camera** (bar §4). A verb missing one of the three is not
   done; a verb missing two is not shipped.
5. **Data over constants.** Anything a designer would want to touch in a tuning session lives in
   `game/data/*.json`, with a doc row that says what "too low" and "too high" feel like.
6. **The HUD never lies** (D-041). An indicator is rendered *from* the value it reports, never from
   a second opinion.
7. **Fail forward, cheaply.** A second fail state must cost something *different* from the first.
   Retry is never a repeated commute.
8. **Book, not "the player".** A generic GTA mechanic ships only with a Book twist: the special
   ability is a bull rope, the arrest is an impound, the respect meter is a slab strip. If the twist
   is not obvious, the mechanic waits.
9. **Wide, not deep, for the crowd.** A pedestrian reaction in ten lines beats a routine in three
   hundred. The sim exists to react, not to live.
10. **Measure, then speak.** A change without a number, a plate, or a harness check is an opinion.
    Opinions do not close defects and do not get a decision-log entry.

## 3. The rubric — how an item earns the top of the backlog

Score 0–3 on each, sum, highest first. Ties go to the item that moves a DNA checklist row
from 0 to ≥1.

| Axis | 0 | 3 |
|---|---|---|
| **Canon weight** | not in any doc | a named verb or system in the story bible |
| **Minute-one visibility** | endgame only | felt in the first ten minutes of a fresh boot |
| **Interlock** | reads nothing, nobody reads it | ≥2 readers and ≥2 writers |
| **Cost (inverse)** | new pipeline / render change / >4 files | one new file + ≤2 edits |
| **Measurability** | "feels better" | a harness number or a plate at a judgement vantage |

Round rules: a round is **three to five items and one full gate**, never more than one S1 at a
time, and **no render-pipeline work in a mechanics round** (§4b is settled by the perf ruling, not
by taste). Each item lands with a decision-log line, a defect claim if it closes one, and its
tunables in data.

## 4. Scorecard — DNA checklist §8, scored against the tree at commit `0f2c2de` (2026-09-12)

0 absent · 1 present but weak · 2 meets the GTA bar · 3 beats it. Evidence is a file or a plate,
never a feeling. Re-score at the end of every round; a row may only move with evidence.

| # | Property | Score | Evidence (before this round) |
|---|---|---|---|
| 1 | Landmark navigation | 1 | Tall Tom, the Green Light, the Big Howdy exist (`landmarks.gd`); never tested from five spawns |
| 2 | District legibility | 1 | downtown / suburb / prairie / floodway dressings differ; no playtester has named one |
| 3 | Ring-road flow | 1 | freeway ring exists; D-059 lists three dead ends |
| 4 | Greatest-hits compression | 1 | eight parody landmarks built; zero locals asked |
| 5 | Map editorializes | 1 | billboards and sign kit carry copy; no 60-second drive has been counted |
| 6 | Diegetic tutorials | 1 | missions teach by doing; the session menu's job text is non-diegetic |
| 7 | Prep→execute loop | 0 | no score has open-world prep |
| 8 | Approach freedom | 1 | The Second Collection accepts quiet or loud; Hook and Ladder accepts one |
| 9 | Cheap retry | 1 | missions repeat after 30 s; death costs 4 s + the drive back from County General |
| 10 | Fail-forward | 1 | the loud path in The Second Collection continues under lockdown; death resets |
| 11 | Legible heat | 1 | five stars, line-of-sight search, blink-on-lost (D-044); **no reason is ever shown**, one evasion verb |
| 12 | Systems interlock | 2 | crash → debris → hook → heat → cruisers → peds flee, unscripted (`traffic.gd`, `tow_hook.gd`, `police.gd`, `pedestrians.gd`) |
| 13 | Emergent clips | 1 | pursuit overshoot comedy is real; no 30-minute session has been logged |
| 14 | World memory | 0 | nothing persists but money, respect, race best (`save_load.gd`) |
| 15 | Economy metronome | 1 | one wallet, two sinks (hospital $300, body shop); no tiers, nothing to buy |
| 16 | Satire thesis | 1 | nine-station dial and ad copy exist; no asset cites the thesis line |
| 17 | Playable satire | 1 | the HOA drone livestreams you (+1 heat per clip) — satire as mechanic, once |
| 18 | Radio as worldbuilding | 1 | five stations play; not one is identifiable blind |
| 19 | Side-content taxonomy | 1 | races yes; hobbies, character quests, random events, challenges no |
| 20 | Flat difficulty, deep mastery | 1 | race medals; no special ability, no optional goals elsewhere |

**Sum 21 / 60.** Rows 7, 14 and 19 are the zeros and the near-zeros; rows 11 and 20 are the
cheapest to move because the systems they need already exist.

## 5. The backlog, in rubric order (re-ranked every round; struck through when landed)

| Rank | Item | Canon | Min-1 | Interlock | Cost⁻¹ | Measure | Sum | Moves row |
|---|---|---|---|---|---|---|---|---|
| 1 | **The Full Eight** — the bull-rope special: eight seconds of dilation, charged by holding on | 3 | 3 | 3 | 2 | 2 | 13 | 20 |
| 2 | **Legible heat** — every star says why, under the banner | 2 | 3 | 3 | 3 | 2 | 13 | 11 |
| 3 | **Busted** — the second fail state is the impound lot, fine by the star | 3 | 2 | 3 | 2 | 2 | 12 | 9, 10 |
| 4 | **Driving feedback** — brake and reverse lamps, headlamps at night, a horn peds hear | 1 | 3 | 2 | 2 | 3 | 11 | bar §4 |
| 5 | Random events that pay forward — a stranded driver you tow shows up later | 2 | 2 | 3 | 1 | 2 | 10 | 19, 14 |
| 6 | World memory v1 — the radio names the last crime; peds fear a hot player | 2 | 1 | 3 | 2 | 1 | 9 | 14 |
| 7 | Fall and crash damage for the driver — the knob in `player_character.gd` (deliberately 0) | 1 | 2 | 2 | 3 | 3 | 11 | bar §4 (but see anti-taste: friction) |
| 8 | Melee guard that blocks — `GUARD_DAMAGE_MULT` is read by nobody | 1 | 2 | 1 | 3 | 2 | 9 | bar §4 |
| 9 | The Paper v1 — one title-fraud job with a bureaucratic timer (office hours) | 3 | 0 | 2 | 0 | 1 | 6 | 7, 17 |
| 10 | Property ladder — buy to flip or hold; the block visibly changes | 3 | 0 | 3 | 0 | 1 | 7 | 15 |
| 11 | Roadblocks at 3★, a chopper at 4★ | 1 | 1 | 2 | 1 | 2 | 7 | 11 |
| 12 | Ragdoll on the skinned rig (`PhysicalBoneSimulator3D`) | 1 | 2 | 2 | 0 | 2 | 7 | bar §1 |

Row 7 scores high on the rubric and still waits: it adds friction before it adds fun, and the
bar's "no dead ends" row is the one a fall-damage death from a mantle would threaten. It ships
after the ragdoll, so a fall reads as a fall.

## 6. Anti-taste — what a round does not do

- **No feature whose only proof is "feels better."** If it cannot be counted or photographed at a
  judgement vantage, it is not in a round.
- **No third fail state, no map clutter, no tutorial screens.** Two ways to lose (County General,
  Longhorn Impound) is GTA's number and it is enough.
- **No asset files, ever** (engine evaluation, D-055). Everything is code; a horn is a synthesis
  routine, a lamp is an emissive material.
- **No non-diegetic timer where a diegetic one exists.** Office hours, the opening bell, the
  radio's traffic report, a signal cycle. A countdown is the last resort.
- **No generic GTA mechanic without the Book twist** (principle 8).
- **No render-pipeline change in a mechanics round.** §4b is decided by the perf ruling on a
  quiet machine, not by a mechanic that happened to need a light.
- **No system without a reader.** A number nobody consumes is a screenshot with a variable name.

## 7. Round log

**Round 1 — 2026-09-12 (D-056).** Landed backlog items 1–4: the Full Eight, legible heat,
Busted, driving feedback (lamps + horn + peds that hear it). Gate 5/5, `--mech-probe` 27/27,
plates in `docs/qa/evidence/mechanics-sept12/`. Claims D-118…D-122 await QA. Expected
scorecard moves once QA rules: row 11 → 2 (a reason for every star; two evasion verbs still),
row 20 → 2 (a special with mastery in the charge), rows 9/10 unchanged until retry stops
repeating the commute. A bug outside the round's files fell out of the probe (D-121) — the
rubric's "measurability" axis paid for itself on the first day. Next round's top of the list by
the same rubric: random events that pay forward (rank 5) and world memory v1 (rank 6), with
the cruiser pull-alongside as the police lever the Busted gap needs.

**Round 2 — 2026-09-12 (D-057).** Inbox empty; the rubric's next three: the cruiser
pull-alongside (the Busted gap), random events that pay forward (STRANDED, a favor that covers
bail), crowds that fear a wanted man. Gate 5/5, probe 36/36 (the first cut of the pull-over lit a
ram star and the probe said so — measurability again), wanted probe unchanged. Expected moves
once QA rules: row 19 → 1 with a real random event that pays forward, row 14 → 1 (favors persist;
peds react to heat), row 11 held at 2. Next by the rubric: melee guard that blocks (rank 8, cheap),
then the Paper v1 spike (rank 9) once a mission skeleton with a diegetic timer is designed; fall
and crash damage stay parked behind the ragdoll.

**Round 3 — 2026-09-13 (D-058).** Milad's first played-it bug report outranked the backlog:
the impound pad was a curb to a towed box (reproduced by a drag test before the fix, passing
after). Then rank 8, the melee guard — which turned out to need an opponent first: brave
pedestrians that square up, a guard that halves, a perfect guard that counters, soft lock and
step-in. Probe 44/44. Rule learned: a bug Milad finds by playing goes to the top of the round,
and gets a harness row before the fix so the fix has a number.

**Round 4 — 2026-09-13 (D-059).** Milad's three notes ran the round: a drift bug (measured 3.27 m,
fixed to 0.000 with a park hold and a probe row), the mannequin (a rewritten animator: a stroll
that swings like a stroll, an idle that breathes), and detail (a street-wear layer: lids, drains,
tar). Gate 5/5, probe 45/45. Lesson filed: a script-built MultiMesh can carry an empty AABB and cull
itself everywhere — two sweeps showed a clean road until a diagnostic printed the bounds; set
`custom_aabb`, and judge a new layer at a vantage that actually contains it.
Next: hands that curl at rest, foot roll, wear on the frontage and suburb roads; then the
backlog (rank 9, the Paper v1 spike).

**Round 5 — 2026-09-13 (D-060).** "More improvements." Stayed on the character note: hands that
rest, lips that read, a brawler who swings; then drivers who honk and wear on the frontage.
Found the ceiling: the shirt and trousers are painted on the body by the palette architecture, so
cloth VOLUME is a milestone (a shell wardrobe), not a round. Filed as the next character lever.
Gate 5/5, probe 45/45.
