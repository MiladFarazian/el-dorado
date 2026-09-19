# D-153 / D-154 — the notice controller (notices.gd)

## 0 · Coordinate space (measured, not assumed)
`game/project.godot`: `window/size/viewport_width=1600`, `height=900`,
`window/stretch/mode="canvas_items"`, `window_width_override=1280/720`.
Therefore **every CanvasLayer control lives in a 1600x900 logical space at all times**;
the 1280x720 window is the same layout scaled 0.8 uniformly (same 16:9 aspect).
So there is ONE region map, authored at 1600x900; the 1280x720 rect is x0.8.

## 1 · The offence, measured from the shipped code
`mission_kit.gd:_build()` (before):
  _card: PRESET_CENTER, offset_left -900 / right +900 -> x -100..1700 (1800 px wide,
  i.e. 112% of the 1600 px frame), offset_top -135 / bottom +55 -> y 315..505.
  Veil area 1800x190 = 342,000 px^2 = 23.8% of the 1,440,000 px^2 frame, 100% of frame width.
  The VBox inside is PRESET_FULL_RECT + ALIGNMENT_CENTER, so the 44 px title + sub + 7 rows +
  medal (~290 px of type) SPILL past the 190 px veil, top and bottom, un-clipped -- which is why
  the plate shows text above and below the dark band.
In `round16/plates/order_debtor.png` (1200x675 = the 1600x900 frame x0.75) the target vehicle
occupies plate y 380..540 -> 1600-space y 507..720, directly under the card's text column.

## 2 · The region map (1600x900 logical; x0.8 for a 1280x720 window)
| Region | Owner | Rect @1600x900 | Rect @1280x720 |
|---|---|---|---|
| POLICE BAND (reserved, not drawn here) | police.gd | x 0..1600, y 56..158 | x 0..1280, y 45..126 |
| TICKER row 0 | notices.gd | x 1182..1582, y 168..194 | x 946..1266, y 134..155 |
| TICKER row 1 | notices.gd | x 1182..1582, y 202..228 | x 946..1266, y 162..182 |
| TICKER row 2 | notices.gd | x 1182..1582, y 236..262 | x 946..1266, y 189..210 |
| CARD (two columns) | notices.gd | x 350..1250, y 170..390 | x 280..1000, y 136..312 |
| CARD (one column, <=4 rows) | notices.gd | x 520..1080, y <=170..<=390 | x 416..864, same x0.8 |
| TICKET (shrunk card) | notices.gd | x 1262..1582, y 266..330 | x 1010..1266, y 213..264 |
| APP / SAY panel | mission_kit.gd | x 1162..1582, y 786..882 | unchanged, x0.8 |
| OBJECTIVE + hint | hud_gta.gd | x 380..1220, bottom-anchored to y 882 | x0.8 |
| RADAR + bars | hud_gta.gd | x 18..318, bottom-left | x0.8 |
Card y-extent 170..390 = 19%..43% of frame height, entirely in the upper third.
Nothing notices.gd draws is inside the police band, and nothing is within 390 px
of the bottom, where the road and any target vehicle live.

## 3 · The card rules as implemented (notices.gd)
- **Size:** 900x220 max (`card_w`/`card_h`), narrowing to 560 when four rows or
  fewer put everything in one column, and the height is the content's own
  combined minimum clamped to 120..220. The cap is enforced twice: by the clamp
  and by `clip_contents = true` on the panel. THE OLD CARD'S REAL BUG WAS THE
  SPILL — 290 px of type in a 190 px veil, drawn outside the panel it belonged to.
- **Place:** horizontally centred; vertical centre at `card_centre_y` 0.30 of the
  frame, hard-clamped so the top never rises above `band_bottom + 12`.
- **When:** `card()` sets state "waiting"; the card appears on the first frame the
  player's actor is under `card_speed_gate` 2 m/s, or after `card_wait_max` 4 s,
  whichever comes first. Speed is read off `main.player_actor()` (RigidBody3D
  linear_velocity, CharacterBody3D velocity), so it works on foot and driving.
- **Life:** `seconds` (6 s from the call sites), fade in 0.30 s, fade out 0.60 s.
- **Interruption:** `repo_orders.active` is polled every frame. A false->true edge
  while the card is up shrinks it to a 320x64 ticket at top-right under the
  ticker for the remainder of its life (title + subtitle only). An order that was
  ALREADY live when the card appeared is not a new objective and does not ticket.
- **One at a time:** a second `card()` queues; it starts its own "waiting" when
  the first one finishes.
- **Type:** ThemeDB.fallback_font everywhere, 6 px black outline, ink #101b22 at
  0.85 alpha, gold #edbd63 for money/medal, off-white #d7dcd9 for text. Rows are
  a two-column table: labels right-aligned into a 220 px gutter, values
  left-aligned out of it, so the numbers line up instead of drifting.

## 4 · Routing — what the producer changes (I did not touch these files)
### repo_board.gd — the gold centre-screen flash becomes ticker lines
`_flash_label` is PRESET_CENTER_BOTTOM, offsets -320..320 / -170..-120 => x 480..1120,
y 730..780 at 1600x900, 30 px gold, dead centre. That is the "GAVE THEM THE WEEK
RESPECT +1" in `order_push.png`. Add the helper once (repo_board already has `_peer`):

```gdscript
## D-154: money and respect are ticker lines now — notices.gd owns the corner.
func _notice(text: String, col: Color) -> void:
	var n := _peer("notices")
	if n != null and n.has_method("ticker"):
		n.call("ticker", text, col)
		return
	_flash(text)
```
Then three one-line call-site edits:
- `add_money()` (repo_board.gd:310):
  `_notice("%s %s$%s" % [reason, "+" if amount >= 0 else "-", _thousands(absi(amount))], Color(0.929, 0.741, 0.388))`
- `add_respect()` (repo_board.gd:319):
  `_notice("%s  RESPECT %+d" % [reason, amount], Color(0.843, 0.863, 0.851))`
- `flash()` (repo_board.gd:325-326, the public banner API carjack uses):
  `_notice(text, Color(0.95, 0.55, 0.16))`
`_deliver()`'s two `_flash("REPO PAID $%d")` calls (repo_board.gd:335/337) should take the
gold `_notice` too. Leave `_flash` and its label in place as the fallback.
Copy note (repo_board's, not mine): the ticker is right-aligned, so "ORDER 4506 +$675"
reads worse than "+$675 ORDER 4506" — the number lands in a fixed place if it leads.

### police.gd — no change required
Its banner IS the top-centre region and notices.gd reserves it: `police.gd:588`
WANTED at PRESET_CENTER_TOP margin 70 / 46 px font, `police.gd:596` the reason
subline at margin 126 / 22 px font. Measured extent y 70..157, which is why
`band_bottom` is 158 and not the 130 in the brief. If police ever wants to move,
`main.systems["notices"].call("banner_band")` returns the Rect2 to sit inside.

### Nothing else needs routing
`hud_gta.gd` objective/cash/stars/hint/radar are untouched and unshadowed.
The mission `_flash` fallbacks (`mission_hook_and_ladder.gd:185`,
`mission_second_collection.gd:353`) only fire when mission_kit is ABSENT; leave them.

## 5 · mission_kit.gd — what changed, what did not
UNCHANGED (verified by reading every call site): `say(speaker, line, seconds)`,
`card(title, subtitle, rows, medal, seconds)`, `lines_queued()`, `card_visible()`,
the `log` array, the LONGHORN app panel's position, colours, fade and queueing.
CHANGED: the card's nodes are gone from this file (-16 lines of build, -6 of
tick, -6 of state). `card()` is now a forward to `notices.card()`; `card_visible()`
asks `notices.card_state() != "none"`, so it stays TRUE while a card is waiting
for the player to stop — which is what `zz_mech_probe.gd:578/646/729` assert, and
those stages zero the vehicle's velocity first, so the card shows immediately there.
A late `_peer()` helper was added: systems load alphabetically, so `notices` does
not exist when mission_kit's `setup()` runs.
The say panel stays exactly where it was: PRESET_BOTTOM_RIGHT, 420x96, margin 18.

## 6 · What could NOT be verified without a boot (the mission's hard rule was
## parse-only; one Godot at a time)
1. **Rendered card height.** The 220 px cap is arithmetic on a 1.4x line-height
   estimate for ThemeDB.fallback_font (title 28 + sub 14 + 4 rows of 15 + medal 17
   ~= 173 px). It is self-correcting — the height is `get_combined_minimum_size()`
   clamped into 120..220 — and `clip_contents` makes an overflow impossible to
   draw outside the panel, but the exact rendered rect of a seven-row COMIN' DOWN
   card is UNMEASURED. First windowed plate settles it.
2. **`clip_contents` on a ColorRect clipping a VBoxContainer child's overflow** is
   documented Godot 4 behaviour; not exercised here.
3. **ticker_top 168 clearing the live cash readout.** Derived from the shipped
   plate ($1,050 at 1600-space y 117..143) plus hud_gta's font constants, not from
   a running HUD with a weapon equipped (ammo label non-empty).
4. **The ticket edge.** `repo_orders.active` false->true while a card is up is
   unexercised; nothing in the current probe drives it.
5. **Session hide.** `session.opened` polling is by the same contract every other
   system uses (`session.gd:16`), unrun.

### Probe rows worth adding (zz_mech_probe.gd is not mine to edit)
- after a completion **while driving**: `notices.card_state() == "waiting"`, then
  `"up"` within 4.1 s — the D-153 rule, with a number.
- `notices.card_state() == "ticket"` after forcing an order live under a card.
- `notices.ticker_count >= 1` after `repo_board.add_money(650, "ORDER 4506")`, and
  `repo_board._flash_label.modulate.a == 0.0` at the same moment — i.e. the centre
  of the screen stayed empty.
- card rect vs band: `not notices.banner_band().intersects(card rect)`.

## 7 · Gate
`parse_all.gd`: **PARSE: 96 scripts, 0 failed** (Godot 4.7.1, headless, one process).
`gdlint game/scripts/systems/notices.gd game/scripts/systems/mission_kit.gd`:
**Success: no problems found.**
`notices.json` parses (35 keys).

## 8 · Producer FYI (not mine, not touched)
`game/scripts/systems/zz_mech_probe.gd` became dirty (+17/-4) DURING this mission
and `docs/qa/evidence/loop-sept18/round18/` appeared — another mission is live on
this tree. Its diff contains no `card_visible` / `card_state` / `notices` / `ticker`
text, so there is no intersection with this work; flagging it only because D-029
ownership is the producer's to enforce.

## 9 · Files this mission owns and changed
- `game/scripts/systems/notices.gd` (NEW, 450 lines)
- `game/scripts/systems/mission_kit.gd` (-16 net; card forwards, API identical)
- `game/data/mechanics/notices.json` (NEW, 35 keys)
