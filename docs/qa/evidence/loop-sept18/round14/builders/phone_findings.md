# BOOK'S PHONE — loop14 (UI Designer)

## Recon (read-only, before writing a line)
- Keys already bound in `main.gd::_register_input_actions`: W/UP S/DOWN A/LEFT D/RIGHT,
  SPACE, F, E, G, N, Q, CTRL, SHIFT, R, BACKSPACE, TAB, C, T, CAPSLOCK, X, H + LMB/RMB.
  Other files bind: `shoulder_swap` (chase_camera), `walk_slow` (player_character),
  ESC/M (session.gd, raw `physical_keycode` check, not an action).
  **KEY_P is free.** Bound here with radio.gd's fallback pattern (has_action guard).
- CanvasLayer census: repo_board 5, full_eight 5, minimap 9, hud_gta 10, combat 11,
  police/arrest 12, missions 14, mission_kit 16, **20 = carjack / dealer / interactables
  prompts**, police_gunfire 25, on_foot 30. Phone takes 20 as briefed (prompt-tier).
- `main.gd::_load_systems` loads every `scripts/systems/*.gd`, keys by basename,
  calls `setup(self)`. `phone.gd` needs no registration anywhere.

## Peer fields actually verified in source (not assumed)
- `repo_orders.gd`: `active:bool`, `rank:int` (1-based, starts 1), `deliveries:int`,
  `paper_taken:int`, `paper_burned:int`, `quota_done:int`, `cfg:Dictionary`;
  `const RANK_NAMES: Array[String]` (5), `const RANK_AT: Array[int]` [0,4,10,18,30];
  `order_id() -> int`, `objective_text() -> String`, `rank_name()`, `rank_mult()`.
  Private-by-convention order fields: `_who`, `_year`, `_model`, `_tell`, `_haul_m`.
- **`days` and `amount` are LOCAL variables in `_push_order` — they are never stored.**
  (repo_orders.gd:377-381; they live only inside the `fields` dict used to format the
  push.) The phone therefore reads them back out of the push line by regex. The pattern
  is a tunable (`due_pattern`) so a copy change in repo_orders.json is a one-line fix
  here, not a code change.
- `repo_board.gd`: `money:int`, `respect:int`. `random_events.gd`: `favors:int`.
- `dealer.gd`: `notes: Array` of `{path, balance, monthly, paid, missed}` (built at
  dealer.gd:762) and `cfg: Dictionary` → `note_months` (96 in dealer.json).
- `main.owned_paths: Array[String]` — res:// paths to vehicle profiles; the profile
  JSON's `name` is the model name (naming bible §7a: never hard-code one).
- `mission_kit.gd` **has no `log` array today** (read it in full — say/card only). Every
  read goes through `mission_kit.get("log")` and survives the null.

## What landed
- `game/scripts/systems/phone.gd` (661 lines) — auto-loaded by `main.gd::_load_systems`,
  keyed `"phone"`, `setup(main)`. CanvasLayer 20, ColorRect 360x640 bottom-right at a
  24 px margin, `visible = false` until P. No pause, no `Input.mouse_mode` touch, no
  gameplay write of any kind — the file contains no `add_money`/`add_heat`/`spawn` call.
- `game/data/mechanics/phone.json` (76 keys) — geometry, palette, every string, and the
  two parsers. Nothing the screen says is spelled in the script.
- Public surface as briefed: `var open: bool`, `var tab: int`, `toggle()`, `show_tab(i)`,
  `text_of(tab) -> String` (joins head/sub/body/alert/tail/foot, so a headless probe can
  assert `"ORDER" in phone.text_of(0)`).

## Gates (both clean)
- `godot --headless --script res://tools/parse_all.gd` -> `PARSE: 94 scripts, 1 failed`.
  The one failure is **`scripts/systems/traffic.gd`**, a file I neither own nor touched —
  a parallel agent was mid-write on it (mtime 18:14:48, one minute before my first run;
  `_load_spurs/_try_spawn_spur/_plan_spur/...` not yet defined). **phone.gd: 0 error
  lines across three consecutive runs.** Proof it was actually in the scan set, not
  skipped: `find scripts tools -name '*.gd' | grep -v parse_all` = 94 = the gate's count.
- `.venv/bin/gdlint game/scripts/systems/phone.gd` -> `Success: no problems found`.

## Measured, not eyeballed
Python mirror of `_tell_in` / `_due_of` run against the REAL `repo_orders.json` copy:
- **6/6** `paper_tells` matched inside their own `app_tell` flag line.
- **0 false positives**: the clean `app_push` reads "118 DAYS PAST DUE" and the tell's
  literal prefix is "DAYS PAST DUE:" — the colon is what separates them, which is exactly
  what `tell_min_prefix: 8` exists to protect.
- `due_pattern` recovers `118` / `12,480` from the clean push, and matches **none** of
  `app_tell` / `app_void` / `app_expire` / `app_hooked` / `app_missed_quota` (it requires
  a `$amount` after the days). So `_order_push()` can only ever land on a real ORDER push.
- Geometry fits both window sizes (D-053): 1280x720 -> x 896..1256, y 56..696;
  1600x900 -> x 1216..1576, y 236..876.

## Peer fields read (exact)
| peer | read | how |
|---|---|---|
| `repo_orders` | `active`, `rank`, `deliveries`, `quota_done`, `paper_taken`, `paper_burned`, `cfg.quota`, `_who`, `_year`, `_model` | `get()`, null-guarded via `_gs`/`_gi`/`_num` |
| `repo_orders` | `order_id()`, `objective_text()` | `has_method()` then `call()` |
| `repo_orders` | `RANK_NAMES`, `RANK_AT` | `get_script().get_script_constant_map()` — `peer.CONST` will not compile through a `Node`-typed ref, and copying the ladder here would be a second source of truth |
| `mission_kit` | `log` | `mk.get("log")`, `is Array` guard |
| `dealer` | `notes[] {path,balance,monthly,paid,missed}`, `cfg.note_months` | `get()`, `is Array`/`is Dictionary` guards |
| `repo_board` | `money`, `respect` | `_gi` |
| `random_events` | `favors` | `_gi` |
| `main` | `smoke_mode`, `systems`, `owned_paths` | `get()` |
| disk | `repo_orders.json -> paper_tells`; each owned/noted vehicle profile's `name` | read once, names cached per path |

**`mission_kit.log` landed while I was building** — `var log: Array` at mission_kit.gd:27,
`{speaker, line, t}`, newest last, **capped at 12**. My `paper_scan` default is 12, so the
scan window is exactly the log depth; it is a ceiling that can never bind, which is the
safe direction.

## Design decisions worth a reviewer's eye
- **Why the days and the amount come out of a regex.** They are locals in
  `repo_orders._push_order` and are stored nowhere. The alternatives were to add a field
  to a file I do not own, or to re-roll the numbers here (two truths, a canon bug). The
  phone instead reads them back out of the sentence the app already said, and the pattern
  is a tunable so a copy rewrite in repo_orders.json is a one-line data fix.
- **THE PAPER shows the app's NEWEST line.** For a bad order that is the FLAG, which is
  the whole point of the screen; the days/amount still come from the earlier ORDER push
  found by `_order_push()`. Clean orders show the push itself.
- **The haul distance is `objective_text()` verbatim** under the card, per brief — that
  line already counts metres down live, and a second formatter for one distance is a bug.
- **LONGHORN orange heads tab 1, gold heads tabs 2-3**, so a live order is identifiable
  from the tab dots and the header colour alone without reading a word.
- `@warning_ignore("shadowed_variable")` on `text_of(tab: int)` — the brief's signature is
  honoured exactly; the annotation keeps the boot log clean (a parameter shadowing the
  `tab` member is a Godot WARN).

## Not verifiable without a boot (flagged, not claimed)
1. **Nothing here has been seen on a screen.** No `--shot`/`--hudshot` plate was taken:
   CLAUDE.md allows one Godot at a time and another agent held the tree (traffic.gd was
   being rewritten under me). The layout is arithmetic, not a judged image — text overflow
   past the 640 px column on a very long note list or a long feed line is the likeliest
   defect and only a plate will show it. `--hudshot` with `phone.show_tab(i)` driven from
   `zz_shot.gd` is the instrument.
2. **P is unbound in practice only if main.gd never binds it.** The fallback binding is
   verified by inspection (no file in the tree binds KEY_P), not by a keypress.
3. **The red tell has not been rendered**, only computed. The alert Label is a separate
   child so the red is real, but a live bad order is the proof.
4. `--mech-probe` has no phone row yet; `text_of()` exists precisely so one can be added
   by whoever owns `zz_mech_probe.gd` (currently modified by another agent — untouched).
