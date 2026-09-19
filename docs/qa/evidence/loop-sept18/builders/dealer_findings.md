# BOONE TRUCKS — dealer.gd findings (loop 13)

Owner: Customization Designer. Files owned: `game/scripts/systems/dealer.gd`,
`game/data/mechanics/dealer.json`. Nothing else touched.

## Research notes (before any write)

- **interact action is `"interact"` = KEY_G**, registered in code by
  `main._register_input_actions()` (`game/scripts/main.gd`), not in
  `project.godot` — `project.godot` has NO `[input]` section at all. `interactables.gd`
  uses `InputMap.has_action("interact") and Input.is_action_just_pressed("interact")`;
  dealer.gd copies that guard verbatim.
- **Monthly formula settled**: `monthly = ceil(price * note_apr_total / months)` with
  `note_apr_total = 1.31`, `months = 96`. That makes Brisket **$392/mo**, not the
  `$299/mo` in the brief's example prompt string — $299 is `ceil(28700 * 1.00 / 96)`,
  i.e. the struck ×1.0 formula. The formula wins; the example string was stale.
  Same for the card's `"$28,704 in interest"`: that is `299 × 96` (the whole note),
  not the interest. dealer.gd computes `interest = monthly*months - price`.
  Brisket: 392×96 = $37,632 total, **$8,932 in interest** on a $28,700 truck.
- Peer API confirmed: `repo_board.add_money(amount: int, reason: String = "")`,
  `repo_board.flash(text)`, `repo_board.money` (int);
  `mission_kit.say(speaker, line, seconds := 4.5)` and
  `mission_kit.card(title, subtitle, rows, medal := "", seconds := 6.0)`;
  `sky_weather.time_of_day` (float hours). House precedent for a debit is
  `repo.call("add_money", -ZING_PRICE, "DR. ZING")` (interactables.gd:391), so the
  `+$-392` in repo_board's own flash string is a pre-existing house quirk, not mine.
- Static ride height per profile is derivable and EXACT (verified against each
  profile's `_tuning_math`): `comp = mass*9.81 / (2*spring_rate)` split per axle by
  `front_share = (wb_r + 2*com_forward) / (wb_f + wb_r)`; body origin sits
  `-(hardpoint_height - (suspension_rest - comp_axle) - wheel_radius)` above ground.
  Brisket 1.351 m / Sedan 0.873 m / Slab 0.940 m — matches the three JSON comments
  ("~1.35 m above ground", "Ground sits 0.873 m below the body origin",
  "ground at -0.940"). Display bodies use the same numbers as the hero cars.
- Ground under the lot: `greybox_city._build_ground()` prairie north slab top is
  **y = -0.02**; the at-grade freeway apron `Rect2(-800,-42,1600,84)` top is
  **y = +0.01**. Lot slab top = 0.02, drive top = 0.03 — both above their neighbours,
  steps of 4 cm/2 cm (curbs in this city are 0.2 m, so trivially drivable).
- Carjack targets only the `drivable` and `civilian` groups (carjack.gd:105).
  Display bodies join NEITHER, and not `towable` — the stock cannot be hooked or
  jacked, only bought.

## Chunk log

- **CHUNK 1 — `game/data/mechanics/dealer.json` written, `json.load` clean.**
  Tunables: `note_months` 96, `note_apr_total` 1.31, `day_seconds` 600, `miss_limit` 2,
  `buy_range_m` 3.5, `hold_seconds` 1.2, `repo_distance_m` 30, `display_gap_m` 5,
  `stock[]` (path + price: brisket 28700 / sedan 14900 / slab 39900), `sign{}` (name,
  tagline, terms, showroom fascia), `prompt{}` (4 named-token format strings),
  `cash_short`, 8 `wade_lines` + 3 `wade_cash_lines`, `app{}` (paid / missed×2 /
  missed_more / signed / title_clear), `repo{}`, `card{}`. Format strings use
  `{name}`-style named tokens replaced by String.replace, not positional `%`.
  Uncertain: nothing — parsed and counted.
- **CHUNKS 2-6 — dealer.gd through the front line (533 lines).** Lot slab + drive
  (both carry collision: they ARE the driving surface), showroom 24x6x12 at
  (-145, 3, -100) with a proud dark-glass storefront and mullions, the 14 m pylon at
  (-98, -47) with the three-line board, two pennant runs (10 poles, 2 MultiMeshes,
  `custom_aabb` set), six lot lights, and one frozen display body per profile built
  through `vehicle_body_builder.build(..., {"hero": true, ...})` with the real wheel
  stations. Ride heights computed, not eyeballed: 1.3508 / 0.8732 / 0.9403 m.
  Monthly/interest computed: Brisket 392 ($8,932 int), Vantage 204 ($4,684),
  Slab 545 ($12,420). Not yet parsed — next chunks are UI, buying, the note.
- **CHUNKS 7-11 + fixes — dealer.gd complete, 1,172 lines.** Slot price cards, the
  prompt CanvasLayer, the tap/hold loop, buying, the note, the repossession, peers
  and build helpers. Three review fixes applied before delivery: `EXIT_POINT.y`
  1.2 -> 1.6 (the Brisket's 1.351 m ride would have spawned it in the asphalt); two
  lot-light poles moved x -112 -> -128 (a 9 m pole two metres off the exit lane is a
  defect, not dressing); buy range measured to the vehicle FOOTPRINT rather than its
  centre point (a centre-point 3.5 m test puts a player at the Brisket's front
  bumper, 2.9 m + standing distance, out of range of the truck they are looking at).
- **GATE: `PARSE: 93 scripts, 1 failed` — the one failure is
  `res://scripts/world/cedar_cliff.gd` (`_axf()` / `_label()` not found in base self),
  another loop-13 agent's file, NOT mine and not touched.** `dealer.gd` and
  `dealer.json` appear in no error. `.venv/bin/gdlint game/scripts/systems/dealer.gd`
  -> `Success: no problems found`.

---

## 1. JSON tunables (`game/data/mechanics/dealer.json`)

| key | value | what it moves |
|---|---|---|
| `note_months` | 96 | the note's length; every prompt, card and draft reads it |
| `note_apr_total` | 1.31 | total cost multiplier. `monthly = ceil(price*apr/months)` |
| `day_seconds` | 600.0 | one draft day of play time |
| `miss_limit` | 2 | returned drafts before LONGHORN comes |
| `buy_range_m` | 3.5 | prompt range, measured to the body footprint |
| `hold_seconds` | 1.2 | hold-G-for-cash threshold |
| `repo_distance_m` | 30.0 | how far you walk before a deferred repo lands |
| `display_gap_m` | 5.0 | CLEAR metres between bumpers on the front line |
| `stock[]` | 3 rows | `{path, price}`; brisket 28700 / sedan 14900 / slab 39900 |
| `sign{}` | 5 strings | pylon name / tagline / terms, showroom fascia + sub |
| `prompt{}` | 4 strings | `buy`, `signing`, `on_note`, `owned` — `{token}` fields |
| `cash_short`, `cash_short_line` | | the refusal, flashed and spoken |
| `wade_lines[]` | **8** | signing lines, Wade's pitchman warmth with the cracks showing |
| `wade_cash_lines[]` | 3 | what he says when you don't need him |
| `app{}` | 6 | BOONE FINANCIAL: `signed`, `paid`, `missed[2]`, `missed_more`, `title_clear` |
| `repo{}` | 3 | LONGHORN's speaker, `warn` (deferred), `line` (the taking) |
| `card{}` | 2 | contract-card title + subtitle template |

Derived and verified: Brisket **$392/mo**, $37,632 paid, **$8,932 interest**;
Vantage **$204/mo**, $19,584, $4,684; Slab **$545/mo**, $52,320, $12,420.

## 2. main.gd hooks called — the signatures I assumed

All four are reached through `has_method()` / `get()` and the system runs correctly
with **none** of them present (it keeps its own `_local_owned` mirror and simply
does not spawn anything).

```
func grant_vehicle(path: String) -> bool     # true = granted. null/absent is
                                             # also treated as success.
func revoke_vehicle(path: String) -> void    # return value ignored
var owned_paths: Array[String]               # read-only to me; the wrecker is
                                             # always in it. main is the truth,
                                             # dealer mirrors.
func _spawn_vehicle(path: String) -> void    # EXISTS ALREADY (main.gd:~215).
var vehicle: RigidBody3D                     # read after _spawn_vehicle to place
var profile_paths: Array[String]             # scanned for the wrecker profile
var on_foot: bool ; func player_actor() -> Node3D ; var smoke_mode: bool
```

**Three things the producer should know about `_spawn_vehicle` as it stands:**
1. It does `own_vehicle = vehicle` — so buying a Brisket makes the **Brisket** Book's
   owned rig and orphans the wrecker (County General's drop-off and Tab's re-profile
   both key off `own_vehicle`). If the wrecker must stay Book's rig, `grant_vehicle`
   should set `own_vehicle` back, or `_spawn_vehicle` needs an `own := true` flag.
2. It `queue_free()`s the current vehicle, so an in-car purchase destroys the car you
   were in — the same thing `_cycle_vehicle` does, so this is consistent, not new.
3. It does not update `profile_index`, so the next Tab cycles from the stale index.
   Harmless, but the producer may want `profile_index` re-synced on a grant.

## 3. Atlas entry I want (`game/data/world/atlas.json`)

A `places` row (nothing I own can write this file):
```json
{ "name": "Boone Trucks", "aka": "Appreciate You!", "pos": [-110, -77], "kind": "dealer" }
```
And, if the producer wants the lot as a district rather than bare prairie, a
`districts` row for the frontage strip it sits on:
```json
{ "id": "boone_frontage", "name": "I-3 NORTH FRONTAGE",
  "rect": [-180, -110, 140, 66], "fill": "3a3330", "label": [-176, -106],
  "note": "Boone Trucks: 96 months, $0 down, and a fourteen-metre pylon saying so." }
```
`docs/design/world-atlas.md` still-prairie table should lose the rect
x -180..-40 / z -110..-44. Naming bible §7 already carries **Boone Trucks
("Appreciate You!")** and **Longhorn Wrecker & Recovery ("We Own That Too")** —
no new name is introduced by this system, so §7 needs no edit.

## 4. Public API as built

```
const LOT_CENTER := Vector3(-110.0, 0.0, -77.0)
signal vehicle_granted(path: String)
signal vehicle_repossessed(path: String)
var notes: Array                       # [{path, balance, monthly, paid, missed}]
func buy_cash(path: String) -> bool
func sign_note(path: String) -> bool
func note_tick_now() -> void           # force one draft day
func repossess_now(path: String) -> bool
func inventory() -> Array              # [{path, name, price, monthly, owned}]
```
`notes` is a plain `Array` of plain `Dictionary` with only String/int values, so
`save_load` can `set("notes", restored_array)` with no schema translation and
`JSON.stringify` it directly. Forward-compatible: unknown keys on a restored note
are preserved (the draft only reads `monthly`, `paid`, `missed`, `path`).

## 5. What I could NOT verify without a boot

The hard rule allowed only `parse_all.gd`, so everything below is reasoned, not seen:
1. **Nothing is rendered-verified.** No plate was taken. The pennant and wire
   MultiMeshes set `custom_aabb` from instance origins (grown 1 m) per D-059, but
   "it draws" is unproven — judge it windowed at a vantage that contains the lot.
   There is no `--shot` vantage on this lot yet; one is worth adding.
2. **Sign fit.** `SIGN.make` solves the size, so clipping is arithmetically
   impossible, but the three pylon lines' RELATIVE sizes (2.1 / 1.45 / 1.75 m of
   board height) are an art call made blind. The terms line runs through
   `SIGN.balance(text, 2)`.
3. **Ride heights** match all three profiles' own `_tuning_math` to 4 decimal
   places (1.3508 / 0.8732 / 0.9403) — but whether the `vehicle_body_builder`'s
   own per-style `DROP` lands the shells on my wheel cylinders is unverified.
   If a display car floats or sinks, the suspect is `DROP[style]`, not the ride math.
4. **Ground clearance at the lot/prairie seam** (4 cm) and the drive/apron seam
   (2 cm) are computed from `greybox_city` constants, not driven over.
5. **The prompt's readability at 21 pt** and whether the buy line is too long for
   720p — it is ~86 characters. It may want two lines.
6. **`repo_board.add_money(-monthly, "BOONE FINANCIAL")` renders its flash as
   `BOONE FINANCIAL +$-392`** because `repo_board._flash` hard-codes `+$%d`. That is
   pre-existing (interactables.gd:391 has the same), it is repo_board's string, not
   mine, and the mission_kit app line carries the real copy. Worth a producer fix
   in repo_board some day.
7. **Sky clock unused.** `sky_weather.time_of_day` is deliberately NOT the draft
   trigger — `_day_t += delta` is, so the draft is identical headless, in a probe,
   and with the sun frozen. `sky_weather` is listed as an optional peer but the
   system never reads it.

---

## 6. LATE CHECK — the producer had already landed the hooks (D-068)

`game/scripts/main.gd` now carries `var owned_paths: Array[String]`, seeded with the
wrecker, plus `grant_vehicle(path) -> bool` and `revoke_vehicle(path) -> bool`, and
`_cycle_vehicle` reads `owned_paths` unless `--dev-fleet`. Two behaviours differ from
the assumptions in §2 above, and dealer.gd was corrected to match them:

1. **`grant_vehicle` returns FALSE for a path not in `profile_paths`.** `buy_cash`
   debited the cash BEFORE granting, so a refused grant would have taken $28,700 and
   handed over nothing. **Reordered: grant first, debit only on success.** (Path
   strings do match — `_scan_vehicle_profiles` builds exactly
   `res://data/vehicles/<file>.json`, which is what `stock[].path` holds.)
2. **`revoke_vehicle` returns FALSE** when `owned_paths.size() < 2` or the path is the
   wrecker — i.e. when there is nothing to take. dealer.gd now reads that return: the
   note is voided and the stock restored, but LONGHORN's "WE OWN THAT TOO" line does
   NOT fire for a car that was never there.

Both changes re-gated: `PARSE: 93 scripts, 1 failed` (cedar_cliff.gd, not mine) and
`gdlint … Success: no problems found`.

The §2 note about `_spawn_vehicle` setting `own_vehicle = vehicle` **still stands and
is still unresolved** — buying anything currently makes the purchase Book's owned rig
and orphans the wrecker that County General and Tab key off. That is a producer call
in `main.gd`, which I do not own.
