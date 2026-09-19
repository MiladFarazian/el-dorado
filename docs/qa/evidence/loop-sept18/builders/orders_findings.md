# REPO ORDERS — build log (Game Systems Designer, loop13)

Files owned: `game/scripts/systems/repo_orders.gd`, `game/data/mechanics/repo_orders.json`.
Nothing else edited.

## Research landed (before writing a line)
- `main.gd:304 _load_systems()` — every `scripts/systems/*.gd` is instanced, `node.name` =
  file basename, registered in `main.systems[name]`, then `setup(self)`. So the file name
  IS the key: `repo_orders`. Confirmed.
- `main.gd:136` — `"interact": [KEY_G]`. There is NO `[input]` section in `project.godot`;
  actions are registered at runtime in `_register_input_actions()`. The G action name is
  `interact`; hook is `hook` = F. No collision with the tow prompt.
- `random_events._quiet_world()` verbatim checks: `main.on_foot != true`, player vehicle
  non-null with `has_boom()` true, `police.heat == 0` (I allow `<= 1` per brief),
  `mission_hook_and_ladder|mission_second_collection|mission_comin_down` `state == 0`,
  `repo_board._delivering != true`, `tow_hook.hooked_body == null`.
- `parked_cars._build_slots() -> Array[Vector3]` returns `(x, side, z)`; `side` is +1/-1 and
  is the curb side, NOT a y coordinate. Nose direction is `Vector3(0,0,-side)`.
  It already excludes `CORRIDOR = Rect2(174,424,38,152)`; I re-check it anyway (peer optional).
- **A frozen car cannot be towed.** `parked_cars._on_hooked()` unfreezes on the tow's
  `hooked` signal; I do the same for the order target (`freeze = false` on hook).
- `repo_board`: `PAD_CENTER = Vector3(709,0,558)`, `PAD_HALF = Vector2(7,5)`, pad test is
  `absf(dx) <= 7 and absf(dz) <= 5 and y < 4.0`. `add_money(int, String)` /
  `add_respect(int, String)` both flash when the reason is non-empty.
- `pedestrians.spawn_follower_at(pos, facing, target, seconds) -> RigidBody3D` wraps
  `spawn_brawler_at(pos, facing)` and flips the ped to FOLLOW. Both `add_child` themselves.
- `beacon_kit.beacon(color, height, width, peak_alpha, energy, ring_radius, ring_alpha=-1)`.
- `vehicle_body_builder.build(root, style, size, paint, door_text="", opts={})` — styles
  "sedan" and "pickup" exist and get the ambient shell drop.
- Naming bible §7a: **vehicle names are never hard-coded in script** — the `name` field of
  `data/vehicles/*.json` is the single source. So repo_orders.json stores PROFILE PATHS and
  the system reads the name out of the profile at setup. Sedan = "Sunbelt Vantage",
  pickup = "Baron Brisket". No new vehicle name invented.

## CHUNK: data/mechanics/repo_orders.json written (157 lines, `python3 -m json.tool` clean)
All tunables + name pools + every line of copy. No vehicle model name in it — only
profile PATHS, per naming bible §7a. New fictional proper nouns introduced in the copy
(producer: these want a naming-bible row): **LONGHORN DYNAMICS** (the fake-HQ con — a
shell that sounds like Book's own employer) and **CATTLEMAN'S TRUST** (a bank that closed
every branch). Both punch at institutions; the debtors are never the joke.

## CHUNK: repo_orders.gd through line 561 (consts, setup, API, clock, push, car, beacon)
- Order car is deliberately NOT in group `civilian`: `carjack.gd:417` gates jacking on
  `civilian`/`police`, so the only way to close an order is the boom. Confirmed by read.
- Beacon ladder now explicit: stranded 14 m < ORDER 16 m < repo_board contract 21 m.
- One tell in the JSON became a template (`DAYS PAST DUE: {true_days} (system shows {days})`)
  so the fake-vs-system number is generated, not hard-coded. All tells run through
  `String.format` with the order's fields; a tell with no placeholders is unchanged.

## GATE: repo_orders.gd 1,004 lines — PARSE CLEAN, LINT CLEAN
- `parse_all.gd` → `PARSE: 93 scripts, 1 failed`. The one failure is
  **`res://scripts/world/cedar_cliff.gd` (`_axf()` / `_label()` not found)** — an UNTRACKED
  file (`git status` = `??`) that another agent is writing right now. Zero occurrences of
  `repo_orders` in the parse log: my file compiled. Producer: that failure is not mine and
  was already there.
- `.venv/bin/gdlint game/scripts/systems/repo_orders.gd` → `Success: no problems found`.
  Zero `gdlint:ignore` exceptions needed.

---

# DELIVERY — repo_orders v1

`game/scripts/systems/repo_orders.gd` (1,027 lines) · `game/data/mechanics/repo_orders.json` (157)
Re-gated after the last edit: `PARSE: 93 scripts, 1 failed` (cedar_cliff, not mine), gdlint clean.

## Tunables in repo_orders.json (name = default)
CADENCE: `first_gap` 12.0 (seconds of QUIET, not clock) · `order_gap` 40.0 · `gap_jitter` 20.0
(uniform 0..20 added) · `retry_gap` 6.0 (no open curb anywhere) · `min_m` 120.0 · `max_m` 450.0
THE MEETING: `debtor_range` 25.0 · `debtor_out_m` 3.0 · `choice_range` 4.0 ·
`follower_seconds` 120.0 · `line_seconds` 5.0 · `plead_gap_s` 5.0 · `fight_delay_s` 2.5 ·
`call_delay_s` 12.0 · `call_range_m` 20.0 · `call_hook_near_m` 10.0
THE CLOCK: `expire_seconds` 240.0 (real s ~= 6 in-game min) · `expire_unfreeze` 1 ·
`despawn_m` 300.0
ECONOMY: `quota` 3 · `bad_paper_chance` 0.20 · `offer_amount` 200 · `offer_demotes` absent
(= 0, taking the cash costs no rank progress; set to 1 to make it cost one) ·
`respect_walk_bad` 3 · `respect_walk_clean` 1 · `respect_offer` 2 · `respect_taken` -3 ·
`distance_basis` "haul" · `distance_ref_m` 400.0 · `distance_bonus_max` 0.5
THE ORDER: `pickup_chance` 0.45 · `amount_min` 2400 · `amount_max` 24000 (rounded to $10) ·
`days_min` 31 · `days_max` 210 · `bad_days_min` 3 · `bad_days_max` 9 · `year_min` 2009 ·
`year_max` 2022 · `order_id_base` 4471 · `order_id_step_min` 3 · `order_id_step_max` 41
`reactions` {plead .42, call_it_in .18, offer .22, fight .18} (renormalised, any weights work)
`profiles` {sedan: sedan.json, pickup: brisket.json} — PATHS, never names
POOLS: `paint` 8 · `first_names` 24 · `last_names` 24 (576 debtors) · `paper_tells` 6 ·
`plead_lines` 12 · `offer_lines` 6 · `fight_lines` 6 · `bad_paper_lines` 8 · `promo_lines` 5
COPY: `app_push` `app_tell` `app_void` `app_offer_void` `app_expire` `app_missed_quota`
`app_hooked` — all `String.format` templates: `{id} {name} {year} {model} {days} {true_days}
{amount} {q} {quota} {tell}` in the app lines, `{rank}` in promo_lines. A template with no
placeholder is passed through untouched, so copy can be rewritten without touching code.

## Exact peer calls made (every one guarded, every peer optional)
- `repo_board.add_money(int, String)` — "ORDER 4471" / "CASH, NO QUESTIONS"
- `repo_board.add_respect(int, String)` — "LEFT THE PAPER" / "GAVE THEM THE WEEK" /
  "TOOK THE PAPER" / the debtor's name on an accepted offer
- `repo_board.PAD_CENTER` / `.PAD_HALF` (read off the preloaded script, not the instance)
- `repo_board._delivering` (read, quiet check)
- `police.add_heat(1, "THE OWNER CALLED IT IN")` · `police.heat` (read, quiet + medal)
- `tow_hook.hooked(body)` / `released(body)` signals · `tow_hook.hooked_body` (read)
- `pedestrians.spawn_follower_at(pos, facing, actor, seconds)` ·
  `pedestrians.spawn_brawler_at(pos, facing)` · `PEDS.PED_HALF` (const off the preload)
- `mission_kit.say(speaker, line, seconds)` · `mission_kit.card(title, sub, rows, medal)`
- `parked_cars._build_slots()` (once, lazily, cached)
- `sky_weather.time_of_day` (read, day rollover)
- `main.player_actor()` with a `character`/`vehicle` fallback · `main.on_foot` ·
  `main.vehicle.has_boom()` · `main.systems` · `main.smoke_mode`

## REQUESTS FOR THE PRODUCER (I edited nothing outside my two files)
1. **HUD** — `hud_gta.gd`: draw `repo_orders.objective_text()` on the objective line whenever
   it returns non-empty (it returns "" when idle, so it is safe to call unconditionally).
   Optional second wire: `repo_orders.prompt_text()` on the interact-prompt line — returns
   "G — WALK AWAY" / "G — TAKE THE $200" / "".
2. **SAVE** — `save_load.gd`: persist `rank`, `deliveries`, `paper_taken`, `paper_burned`,
   `quota_done`, `quota_day`. Restore with `set()`; call `sync_rank()` afterwards (public, no
   args) OR restore `rank` too — either keeps the two consistent. If you want order NUMBERS
   to survive a save, also persist `set("_next_id", n)`.
3. **PROBE** — `zz_mech_probe.gd` rows worth having: (a) `push_now(false)` → `state == PUSHED`,
   `target()` non-null, in groups `towable`/`mission_target`/`repo_order`, `active == true`;
   (b) `push_now(true)` → `order_pushed` emitted with `bad == true` and the tell said;
   (c) drive to the target → `debtor()` non-null within `debtor_range`; (d) `walk_away()` →
   `order_closed("voided")`, respect moved, `paper_burned == 1`, car still in the world but
   NOT in `towable`; (e) hook + release on the pad → money, `deliveries == 1`,
   `order_closed("delivered")`, card visible. Every one is reachable headless except the
   card check. Run the probe after any change here (this file joins the
   police/pedestrians/repo_board/mission_kit list).
4. **BEACON COMPETITION** — repo_board keeps its own 21 m contract beacon lit at all times.
   With an order live there are now two orange columns downtown. My ladder (16 m vs 21 m)
   keeps them legible, but consider having repo_board hide its beam while
   `repo_orders.active` is true — one job at a time reads better. Your file, your call.
5. **NAMING BIBLE** — two new fictional institutions appear in the copy and want a row:
   **LONGHORN DYNAMICS** (the shell that holds the fake liens — deliberately one letter away
   from Book's own employer) and **CATTLEMAN'S TRUST** (a bank that closed every branch).
6. **DECISION LOG** — the design call worth an entry: *walking away pays respect and costs
   rank; the game never says which is the right number.*

## KNOWN GAPS / THINGS I COULD NOT VERIFY WITHOUT A BOOT
- **No boot, no probe, no plate.** Parse + lint only, per brief. Everything below is read
  from peer source, not observed.
- `interact` (G) is also consumed by `interactables.gd:338` in the same frame. If the player
  is standing next to a hydrant AND a debtor, both fire. Low odds (the debtor stands 3 m off
  a curb slot), but it is real; if it bites, the producer can gate interactables on
  `repo_orders.prompt_text() == ""`.
- **The follower gives up at 40 m** (`pedestrians.FOLLOW_GIVE_UP`) and `_validate` despawns
  any ped past `DESPAWN_DIST`. So I never free the debtor myself — pedestrians owns that
  life. Consequence I chose deliberately: CALL_IT_IN keeps counting once the car is ON THE
  HOOK even if the debtor node is already gone (they watched you take it). Positional rules
  still apply while it is only pushed.
- **Hooking disarms the expiry** (brief said 6 minutes "with no hook after the push"). Once
  the chain is on, the order cannot expire under you — including after a snapped chain, when
  it drops back to PUSHED with the beacon re-raised at the car's real position and no clock.
- `expire_unfreeze: 1` follows the brief — the abandoned car goes dynamic and will settle
  ~30 cm (its origin sits at ride height, like random_events' stranded sedan). If that plop
  reads badly on screen, set it to 0 and it stays frozen-kinematic where it was parked.
- The order car is NOT in group `civilian`, so it cannot be carjacked (`carjack.gd:417`) —
  the only way to close an order is the boom. Untested in play.
- Distance bonus is measured **slot → impound pad** (`distance_basis: "haul"`), i.e. the drag
  you are paid for. Flip the one word to `"fetch"` to pay for the drive out instead.
- Balance hypotheses, stated as numbers to playtest against: an order should land roughly
  **once per 60 s of quiet driving**; pay floor **$300**, ceiling **$1,080** (PARTNER, a
  pickup, a 400 m+ haul) against repo_board's flat $250-450; **PARTNER at 30 deliveries** is
  ~45-60 minutes of steady work; `bad_paper_chance` **0.20** is the whole moral dial — under
  0.10 nobody notices a tell, over 0.35 the player stops reading and refuses everything.
