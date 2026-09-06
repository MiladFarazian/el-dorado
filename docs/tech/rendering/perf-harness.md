# THE PERF HARNESS — how to measure frame rate in this project

`game/scripts/systems/perf_harness.gd`. Infrastructure, not a throwaway. The QA
Director is expected to re-run this every cycle; this page is the operating
manual.

## Run it

```
cd game/
godot -- --perf                              # the whole matrix, table, quit
godot -- --perf --perf-repeat=3              # 3 passes, best + spread per station
godot -- --perf --perf-only=downtown_night   # one station (comma-separate for more)
godot -- --perf --perf-frames=600 --perf-warmup=300
godot -- --perf --perf-no-anchor             # do NOT move the player
godot -- --perf --perf-shot=/some/dir        # also save a PNG of every station
```

**Must run windowed.** `--headless` renders nothing, so every number would be a
statement about an idle GPU. The harness refuses to run under it.

Without `--perf` the file costs the project one `set_process(false)` at boot and
nothing else, ever.

## The stations

Ten: five places x day (13.0) and night (21.8). Cameras are the QA screenshot
vantages, so a perf row and a photometric row describe the same frame. Day and
night share a camera per place, so the day→night delta is attributable to
lighting and nothing else.

| place | what it is for |
|---|---|
| `downtown` | the worst case, and the district the player lives in |
| `suburb` | Stonebridle Ranch, the 492-light district |
| `freeway` | the deck at speed |
| `hospital` | County General's apron |
| `hospital_door` | **the post-death respawn frame** — the one view no player can avoid |

`hospital_door` is derived from the respawn contract, not picked by eye:
`on_foot.gd:243` puts the avatar on `HOSPITAL_DOOR` facing −Z and calls
`chase_camera.snap_foot_rig(0)`. It is the heaviest frame in the game, because
you stand outside downtown looking straight down its length.

## Why the player gets teleported

`traffic.gd` spawns in a 70–260 m ring around **the player vehicle**;
`pedestrians.gd` anchors on the player actor. Park a free camera in the suburb
while the truck sits downtown and you measure an empty suburb: no cars, no peds,
a beautiful number and a false one. Each station therefore teleports the
player's rig to a ground anchor on real pavement in that station's view, and the
row prints where the rig actually ended up plus the ambient counts it achieved.
`--perf-no-anchor` disables it for an A/B of pure renderer cost, and for
photometry (`zz_shot` does not move the player either, so an anchored run would
park the wrecker in the middle of the shot).

## Reading the table — three things that will mislead you

1. **The GPU column is `n/a` on this machine.** Godot 4.7.1's Metal backend does
   not implement `viewport_get_measured_render_time_gpu`; it returns 0.00 every
   frame. The harness detects an all-zero column and prints `n/a` rather than a
   zero somebody could read as "free". **CPU ms is renderer CPU only** — command
   building — not total frame cost.
2. **Which way the error runs.** A display that will not release vsync makes a
   frame *longer*; it can never make one shorter. So FRAME is an upper bound on
   frame time and fps is a lower bound. **A station that passes 60 fps passes for
   real. A headroom figure (120 fps, 180 fps) is a floor and must not be quoted
   as the engine's ceiling.** `pin%` — the share of frames within 2% of the
   median — is how much to distrust the headroom.
3. **The dev machine is not a bench.** Identical scenes (same draw calls, same
   objects, same population) have measured 5.4 ms and 11.1 ms in the same
   session. Nothing in the engine changed; a browser, a chat client and sustained
   thermal load did. **Never quote a single run.** Use `--perf-repeat=3` and read
   `best` (the least-contended sample) next to `spr%`.

## The two numbers that are trustworthy regardless

Draw calls and objects-in-frame come from the renderer's own counters and do not
care what else the machine is doing. They are the right thing to regress against
between cycles, and the right thing to budget in. Frame time on this box is a
supporting number, not the headline.

## The MultiMesh shadow probe — the biggest cheap win in the project

```
godot -- --perf --perf-mm-audit                          # the worklist
godot -- --perf --perf-only=downtown_day --perf-mm-noshadow   # the upper bound
```

**A MultiMesh is frustum-culled as ONE unit.** One visible instance drags the
whole set into every directional-shadow cascade, every frame. `--perf-mm-audit`
measured, on 2026-08-11:

> **189 MultiMeshes, 63,563 instances, 55,251 of them (87%) in every shadow
> cascade.**

The top of that list is content that has no business casting a shadow at all:
11,919 grass tufts, 3,968 bluestem, 3,255 fence pickets, 2,095 road paint, 1,890
road markings, 1,505 lane dashes, 566 tyre-wear decals, curb paint, glazing.
Only 5 of the 13 files that build MultiMeshes set `cast_shadow` at all.

Measured A/B (back-to-back, quiet machine, `--perf-repeat=2`), stripping **all**
of them — an upper bound, because building masses must keep their shadows:

| station | frame ms | draw calls |
|---|---|---|
| downtown_day | 8.33 → **7.41** (−11%) | 3,906 → **3,222** (−684, −17.5%) |
| downtown_night | 8.62 → **8.21** | 4,248 → **3,677** (−571) |
| suburb_day | 5.38 → **5.00** | 702 → **542** (−160, −23%) |
| freeway_day | 6.67 → **6.14** | 2,849 → **2,558** (−291) |

**The draw-call column is the one to act on** — it comes from the renderer's own
counters and does not care what else the machine is doing. A fifth of every
frame's draw calls are shadow-pass draws for paint and grass. The fix is one
line per MultiMesh in the layer that owns it; this file only measures it.

**CASHED, 2026-08-11 (D-028).** The nine owning files now set `cast_shadow`
deliberately per layer: **55,251 → 10,579 casting instances (87% → 17%)**, all
ten stations faster on draws and on frame time, −5.0% of every draw call across
the matrix. The rule and the per-file table live in
`docs/tech/rendering/shadow-policy.md`. The `--perf-mm-noshadow` row above
remains the *upper bound*, not the achieved result: it strips the tower masses
too, which is why downtown really gets −4.7% and not −17.5%.

## `--perf-mm-cast=A,B` — how to A/B a shadow change with no VCS

```
godot -- --perf --perf-repeat=2                                    # arm A: as built
godot -- --perf --perf-repeat=2 --perf-mm-cast=GrassTufts,RowPaint # arm B: those back ON
godot -- --shot --perf-mm-cast=<list>                              # same, for the 39 QA vantages
```

Forces the **named** MultiMeshInstance3D nodes back to
`SHADOW_CASTING_SETTING_ON` at boot, so both arms run **from one tree** and can
be interleaved minutes apart. Build the list by diffing two `--perf-mm-audit`
outputs. Unlike `--perf-mm-noshadow` (all off, an upper bound) this reproduces
an *exact* prior policy, which is the only way to get a trustworthy number here:

- the machine drifts. An identical build measured **8.33 ms and 14.29 ms** at
  `downtown_day` twenty minutes apart during D-028. A sequential before/after
  reported every station slower while its draw calls went down.
- **the tree changes under you.** D-028's first screenshot A/B was taken 25
  minutes apart and another agent's camera-FOV fix (D-080) landed in
  `zz_shot.gd` in between, so half the "differences" were a lens change. *With
  concurrent agents and no version control, a before/after taken at two points
  in time is not evidence.*

It is the only probe that works **without `--perf`** — that is how the
screenshot harness gets an honest A/B; in that mode it applies the flag on frame
3, prints one line, and calls `set_process(false)`.

## What did NOT generalise: `Label3D.alpha_cut`

`ALPHA_CUT_DISCARD` moves a label out of the sorted transparent pass — and into
the opaque, depth-prepass and shadow passes. Applied blanket-wide to all 1,146
Label3Ds in the project it is **a 33% regression**, reproduced in two interleaved
rounds:

| | downtown_day |
|---|---|
| baseline | 8.33 ms (120 fps), 3,906 draws |
| `--perf-label-cut` | **11.11 ms (90 fps)**, 3,941 draws |

It can still be right for a *specific* layer whose signage dominates its own
frame. It is not a project-wide setting, and it should not be rolled out as one.

## Adding a station

Append to `PLACES`: `[name, camera position, look-at, player ground anchor]`.
Put the anchor on real pavement and check the row's `rig at (...)` output — an
anchor that silently fails deletes the ambient load from that row without
telling you. A camera placed inside a collider will happily measure the inside
of a box: `hospital_door` did exactly that on its first build and scored a mean
luminance of 0.94.

## Related

- Photometric method (night luminance) is the D-014/D-069 procedure: ground half
  of the frame, Rec.709 luminance on encoded 0–255 values, reporting mean,
  median, % below 8/255 and count above 64/255.
- `suburb_night.gd`'s older `--suburb-perf` flag still works and is left alone.
  It is a single-vantage probe; this is its generalisation. Prefer this one.
