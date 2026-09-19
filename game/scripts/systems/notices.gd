extends Node
## NOTICES — the screen's traffic controller (D-153, D-154). Until this existed
## five systems each stood up their own CanvasLayer and their own label, and in
## `round16/plates/order_push.png` all five fire at once: a finished mission's
## 1800x190 card across the whole frame, the police EVADED banner, repo_board's
## gold respect flash, the LONGHORN app panel and the objective line. In
## `order_debtor.png` the card is parked on top of the target vehicle the
## objective is sending the player to — the HUD covering the thing the HUD is
## pointing at.
##
## ONE CONTROLLER, FIVE FIXED REGIONS (all rects in the 1600x900 logical UI
## space; project.godot stretches canvas_items, so a 1280x720 window is this
## same layout x0.8):
##   TOP-CENTRE   y 56..158   the police WANTED/EVADED band + its reason subline.
##                            police.gd draws it; this system RESERVES it and
##                            nothing here is ever allowed inside it.
##   TOP-RIGHT    under cash  the TICKER: short one-line notices (money, respect,
##                            promotions), 18 px, newest on top, three at most,
##                            2.4 s each. Money and respect belong HERE, not in
##                            the middle of the windscreen.
##   CENTRE-UPPER the CARD:   900x220 max, centred on y = 30% of the frame, one
##                            at a time, a second queues. It waits for the player
##                            to stop (or 4 s, whichever comes first) before it
##                            appears, and if a new objective goes live while it
##                            is up it shrinks to a 320x64 ticket in the corner.
##   BOTTOM-RIGHT             mission_kit's LONGHORN app panel (unchanged).
##   BOTTOM-CENTRE            hud_gta's objective line (untouched).
##
## Data: data/mechanics/notices.json. Every peer is optional and null-checked;
## this boots with no hud, no police, no orders. Builds nothing in smoke mode.

const DATA_PATH := "res://data/mechanics/notices.json"
const LAYER := 17                    # over mission_kit's app panel (16), under the menus (30)
const C_INK := Color(0.063, 0.106, 0.133, 0.85)     # #101b22 panel ink
const C_MONEY := Color(0.929, 0.741, 0.388)         # #edbd63 gold — money
const C_TEXT := Color(0.843, 0.863, 0.851)          # #d7dcd9 off-white — everything else
const C_APP := Color(0.95, 0.55, 0.16)              # LONGHORN orange — the dispatcher
const C_MEDAL := {
	"GOLD": Color(0.98, 0.82, 0.30),
	"SILVER": Color(0.82, 0.84, 0.88),
	"BRONZE": Color(0.80, 0.52, 0.30),
}
const OUTLINE := 6                   # HUD law: 6 px black outline on anything over the world

## card_state(): "none" | "waiting" | "up" | "ticket".
var ticker_count := 0
var cfg: Dictionary = {}
var main_ref: Node = null

var _ui: CanvasLayer = null
var _root: Control = null
var _rows: Array[Label] = []
var _row_text: Array[String] = []
var _ticks: Array[Dictionary] = []
var _card: ColorRect = null
var _card_box: VBoxContainer = null
var _card_title: Label = null
var _card_sub: Label = null
var _card_medal: Label = null
var _cols: HBoxContainer = null
var _col_b: HBoxContainer = null
var _names: Array[Label] = []
var _vals: Array[Label] = []
var _state := "none"
var _pending: Dictionary = {}
var _queue: Array[Dictionary] = []
var _wait := 0.0
var _left := 0.0
var _age := 0.0
var _order_prev := false


func setup(main: Node) -> void:
	main_ref = main
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
	if bool(main.get("smoke_mode")):
		set_process(false)
		return                        # smoke gate: no nodes, no draws, byte-stable line
	_build()


# ============================== PUBLIC API ===================================

## One short line in the TOP-RIGHT ticker, under the cash readout: a payout, a
## respect tick, a promotion. Newest on top, three at most, `ticker_seconds`
## each. This is where money goes — never the middle of the screen.
func ticker(text: String, colour := C_TEXT) -> void:
	if _root == null or text.strip_edges() == "":
		return
	_ticks.push_front({"text": text, "col": colour, "left": _n("ticker_seconds", 2.4), "age": 0.0})
	while _ticks.size() > int(_n("ticker_max", 3.0)):
		_ticks.pop_back()
	ticker_count = _ticks.size()


## The end-of-job CONTRACT card, placed and timed by the rules above. `rows` is
## [[label, value], ...]; `medal` is GOLD/SILVER/BRONZE or "". A second card
## queues behind this one — two cards are never on screen together.
## `seconds` <= 0 takes the tunable.
func card(title: String, subtitle: String, rows: Array, medal := "", seconds := 0.0) -> void:
	if _card == null:
		return
	var payload := {
		"title": title,
		"sub": subtitle,
		"rows": rows,
		"medal": medal,
		"s": seconds if seconds > 0.0 else _n("card_seconds", 6.0),
	}
	if _state != "none":
		_queue.append(payload)
		return
	_pending = payload
	_state = "waiting"
	_wait = 0.0


## The band TOP-CENTRE that police.gd's WANTED/EVADED banner and its reason
## subline own. Nothing this system draws enters it; anything else that wants to
## put text near the top of the screen should ask here first.
func banner_band() -> Rect2:
	var w := 1600.0
	if _root != null:
		w = _root.size.x
	var top := _n("band_top", 56.0)
	return Rect2(0.0, top, w, _n("band_bottom", 158.0) - top)


## PROBE: "none" | "waiting" (held back until the player stops) | "up" | "ticket".
func card_state() -> String:
	return _state


# ============================== THE LOOP =====================================

func _process(delta: float) -> void:
	if _root == null:
		return
	if _session_open():
		_root.visible = false         # the pause menu owns the screen; freeze, do not draw
		return
	_root.visible = true
	_tick_ticker(delta)
	_tick_card(delta)


func _tick_ticker(delta: float) -> void:
	var i := 0
	while i < _ticks.size():
		var t: Dictionary = _ticks[i]
		t["left"] = float(t["left"]) - delta
		t["age"] = float(t["age"]) + delta
		if float(t["left"]) <= 0.0:
			_ticks.remove_at(i)
		else:
			i += 1
	ticker_count = _ticks.size()
	var fade_in := maxf(_n("ticker_fade_in", 0.15), 0.01)
	var fade_out := maxf(_n("ticker_fade_out", 0.4), 0.01)
	for r in _rows.size():
		var lbl := _rows[r]
		if r >= _ticks.size():
			lbl.visible = false
			_row_text[r] = ""
			continue
		var row: Dictionary = _ticks[r]
		var text := str(row["text"])
		if _row_text[r] != text:      # only re-theme on a change: every override dirties layout
			_row_text[r] = text
			lbl.text = text
			var col: Variant = row["col"]
			lbl.add_theme_color_override("font_color", col if col is Color else C_TEXT)
		var fi := minf(float(row["age"]) / fade_in, 1.0)
		var fo := minf(float(row["left"]) / fade_out, 1.0)
		lbl.modulate.a = clampf(minf(fi, fo), 0.0, 1.0)
		lbl.visible = true


## The card's whole policy: hold it back until the player is actually stopped
## (or four seconds, whichever comes first), fade it in, and get out of the way
## of a live objective by shrinking into a corner ticket.
func _tick_card(delta: float) -> void:
	var live := _order_live()
	if _state == "waiting":
		_wait += delta
		if _speed() < _n("card_speed_gate", 2.0) or _wait >= _n("card_wait_max", 4.0):
			_show_card()
	elif _state == "up" or _state == "ticket":
		_left -= delta
		_age += delta
		var fi := minf(_age / maxf(_n("card_fade_in", 0.3), 0.01), 1.0)
		var fo := minf(_left / maxf(_n("card_fade_out", 0.6), 0.01), 1.0)
		_card.modulate.a = clampf(minf(fi, fo), 0.0, 1.0)
		if _state == "up" and live and not _order_prev:
			_to_ticket()
		if _left <= 0.0:
			_hide_card()
	_order_prev = live


func _show_card() -> void:
	_fill_card(_pending)
	_place_card(false)
	_pending = {}
	_state = "up"
	_age = 0.0
	_card.modulate.a = 0.0
	_card.visible = true
	_order_prev = _order_live()       # already-live order is not a NEW objective


func _to_ticket() -> void:
	_state = "ticket"
	_place_card(true)


func _hide_card() -> void:
	_card.visible = false
	_state = "none"
	if _queue.is_empty():
		return
	_pending = _queue.pop_front()
	_state = "waiting"
	_wait = 0.0


# ============================== PLACEMENT ====================================

func _fill_card(p: Dictionary) -> void:
	_left = float(p.get("s", 6.0))
	_card_title.text = str(p.get("title", ""))
	_card_sub.text = str(p.get("sub", ""))
	var medal := str(p.get("medal", ""))
	_card_medal.text = medal
	var mcol: Variant = C_MEDAL.get(medal, C_MONEY)
	_card_medal.add_theme_color_override("font_color", mcol if mcol is Color else C_MONEY)
	var pairs: Array[Array] = []
	var rows: Variant = p.get("rows", [])
	if rows is Array:
		for r: Variant in rows as Array:
			if r is Array and (r as Array).size() >= 2:
				pairs.append([str((r as Array)[0]), str((r as Array)[1])])
	# Two columns past four rows: a seven-row contract in one column needs 9 px
	# type to fit 220 px. Split it and the type stays at 15.
	var half := pairs.size()
	if pairs.size() > 4:
		half = int(ceilf(pairs.size() * 0.5))
	_fill_column(0, pairs.slice(0, half))
	_fill_column(1, pairs.slice(half))
	_col_b.visible = pairs.size() > half


func _fill_column(idx: int, pairs: Array) -> void:
	if idx >= _names.size():
		return
	var names: Array[String] = []
	var vals: Array[String] = []
	for pr: Variant in pairs:
		names.append(str((pr as Array)[0]))
		vals.append(str((pr as Array)[1]))
	_names[idx].text = "\n".join(names)
	_vals[idx].text = "\n".join(vals)


## The card's rect. Three invariants, enforced here rather than trusted: it
## never enters the police band, it never exceeds card_w x card_h, and it hugs
## its own content — a three-row receipt does not get a 900 px slab.
func _place_card(ticket: bool) -> void:
	var vs := _root.size
	if vs.x < 1.0:
		vs = Vector2(1600.0, 900.0)
	var pad_x := 10.0 if ticket else _n("card_pad", 24.0)
	var pad_y := 6.0 if ticket else 12.0
	_card_box.offset_left = pad_x
	_card_box.offset_right = -pad_x
	_card_box.offset_top = pad_y
	_card_box.offset_bottom = -pad_y
	_cols.visible = not ticket
	_card_medal.visible = not ticket
	_card_title.add_theme_font_size_override(
		"font_size", int(_n("ticket_font", 19.0)) if ticket else int(_n("card_font_title", 28.0))
	)
	_card_sub.add_theme_font_size_override(
		"font_size", int(_n("ticket_sub_font", 13.0)) if ticket else int(_n("card_font_sub", 14.0))
	)
	var w := _n("ticket_w", 320.0) if ticket else _n("card_w", 900.0)
	var h := _n("ticket_h", 64.0) if ticket else _n("card_h", 220.0)
	if not ticket:
		if not _col_b.visible:
			w = _n("card_w_narrow", 560.0)      # one column of rows: fit, do not fill
		var want := _card_box.get_combined_minimum_size().y + 2.0 * pad_y
		if want > 40.0:
			h = clampf(want, _n("card_h_min", 120.0), _n("card_h", 220.0))
	var x := 0.0
	var y := 0.0
	if ticket:
		x = vs.x - _n("margin", 18.0) - w
		y = _ticker_bottom() + 8.0
	else:
		x = (vs.x - w) * 0.5
		y = maxf(_n("band_bottom", 158.0) + 12.0, vs.y * _n("card_centre_y", 0.30) - h * 0.5)
	_card.offset_left = x
	_card.offset_right = x + w
	_card.offset_top = y
	_card.offset_bottom = y + h


func _ticker_bottom() -> float:
	var n := _n("ticker_max", 3.0)
	return _n("ticker_top", 168.0) + n * (_n("ticker_row_h", 26.0) + _n("ticker_gap", 4.0))


# ============================== NODES ========================================

func _build() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = LAYER
	add_child(_ui)
	_root = Control.new()
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE   # HUD law: never eat mouse look
	_ui.add_child(_root)
	var margin := _n("margin", 18.0)
	var width := _n("ticker_w", 400.0)
	var row_h := _n("ticker_row_h", 26.0)
	for i in int(_n("ticker_max", 3.0)):
		var lbl := _label("", int(_n("ticker_font", 18.0)), C_TEXT)
		lbl.set_anchors_preset(Control.PRESET_TOP_RIGHT)
		lbl.offset_left = -(margin + width)
		lbl.offset_right = -margin
		lbl.offset_top = _n("ticker_top", 168.0) + i * (row_h + _n("ticker_gap", 4.0))
		lbl.offset_bottom = lbl.offset_top + row_h
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.visible = false
		_root.add_child(lbl)
		_rows.append(lbl)
		_row_text.append("")
	_build_card()


func _build_card() -> void:
	_card = ColorRect.new()
	_card.color = C_INK
	_card.clip_contents = true          # D-153: type can NEVER spill past the panel again
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_root.add_child(_card)
	_card_box = VBoxContainer.new()
	_card_box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_card_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_card_box.add_theme_constant_override("separation", 2)
	_card_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.add_child(_card_box)
	_card_title = _label("", int(_n("card_font_title", 28.0)), C_TEXT)
	_card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_box.add_child(_card_title)
	_card_sub = _label("", int(_n("card_font_sub", 14.0)), C_MONEY)
	_card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_box.add_child(_card_sub)
	_cols = HBoxContainer.new()
	_cols.alignment = BoxContainer.ALIGNMENT_CENTER
	_cols.add_theme_constant_override("separation", 52)
	_cols.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_box.add_child(_cols)
	_cols.add_child(_column())
	_col_b = _column()
	_cols.add_child(_col_b)
	_card_medal = _label("", int(_n("card_font_medal", 17.0)), C_MONEY)
	_card_medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_box.add_child(_card_medal)


## One column of the contract table: labels right-aligned into a gutter, values
## left-aligned out of it, so the numbers line up instead of drifting.
func _column() -> HBoxContainer:
	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var size := int(_n("card_font_row", 15.0))
	var name_w := _n("card_name_w", 220.0)
	var names := _label("", size, Color(C_TEXT.r, C_TEXT.g, C_TEXT.b, 0.78))
	names.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	names.custom_minimum_size = Vector2(name_w, 0.0)
	names.add_theme_constant_override("line_spacing", 5)
	col.add_child(names)
	var vals := _label("", size, C_TEXT)
	vals.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	vals.custom_minimum_size = Vector2(maxf(_n("card_col_w", 400.0) - name_w, 80.0), 0.0)
	vals.add_theme_constant_override("line_spacing", 5)
	col.add_child(vals)
	_names.append(names)
	_vals.append(vals)
	return col


func _label(text: String, size: int, col: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", ThemeDB.fallback_font)
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_constant_override("outline_size", OUTLINE)
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


# ============================== PEERS ========================================

func _n(key: String, fallback: float) -> float:
	var v: Variant = cfg.get(key, fallback)
	return float(v) if (v is float or v is int) else fallback


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary and (sys as Dictionary).has(peer_name):
		var n: Variant = (sys as Dictionary)[peer_name]
		if n is Node and is_instance_valid(n):
			return n
	return null


## How fast the thing the player is currently steering is going. A card waits
## for this to drop under card_speed_gate — you cannot read at 30 m/s.
func _speed() -> float:
	if main_ref == null or not main_ref.has_method("player_actor"):
		return 0.0
	var actor: Variant = main_ref.call("player_actor")
	if actor is RigidBody3D:
		return (actor as RigidBody3D).linear_velocity.length()
	if actor is CharacterBody3D:
		return (actor as CharacterBody3D).velocity.length()
	return 0.0


## Is a live order pointing the player somewhere right now? A card that is up
## when this goes true has just started covering a target: shrink to a ticket.
func _order_live() -> bool:
	var orders := _peer("repo_orders")
	return orders != null and orders.get("active") == true


func _session_open() -> bool:
	var sess := _peer("session")
	return sess != null and sess.get("opened") == true
