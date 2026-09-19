extends Node
## BOOK'S PHONE (loop14) — the one screen the loop is legible on.
##
## The Hook, the Paper and the money are three systems that only ever speak in
## passing: a push that fades in five seconds, a card that fades in six, a number
## in the corner of the HUD. The phone is where they SIT STILL. P opens it,
## P again walks LONGHORN -> BOONE -> WALLET -> shut.
##
## LAWS THIS FILE OBEYS
##  * READ-ONLY. Nothing on this screen changes the world: no pause, no input
##    capture, no money, no heat, no spawn. It reports and it shuts up.
##  * Every peer is optional. repo_orders, mission_kit, dealer, repo_board and
##    random_events are each read through main.systems.get() + get() + null
##    checks; with all five absent the phone still builds, toggles and renders.
##  * Nothing is allocated while it is shut, and the labels refresh at
##    `refresh_hz` (4 Hz), not per frame — a report, not an instrument.
##  * Every Control is MOUSE_FILTER_IGNORE (HUD law: a STOP control eats
##    captured-mouse look).
##  * Inert in smoke mode: no CanvasLayer, no process, no strings.
##  * The words live in data/mechanics/phone.json. The satire is the copy, and
##    the copy is a tunable.
##
## THE PAPER. repo_orders.gd holds a live order's `days` and `amount` in LOCAL
## variables (repo_orders.gd:377-381) — they exist nowhere but the push line the
## app already said. So the phone reads them back out of mission_kit's log with
## `due_pattern`, and flags bad paper by matching the literal head of each entry
## in repo_orders.json's `paper_tells` against that push. No duplicated truth.

const DATA_PATH := "res://data/mechanics/phone.json"
const ORDERS_DATA := "res://data/mechanics/repo_orders.json"
const ACTION := "phone"
const TAB_LONGHORN := 0
const TAB_BOONE := 1
const TAB_WALLET := 2
const TAB_COUNT := 3
const PART_KEYS: Array[String] = ["head", "sub", "body", "alert", "tail", "foot"]

# PUBLIC (probe + peers): is the screen up, and which tab is on it.
var open := false
var tab := TAB_LONGHORN
var main_ref: Node = null
var cfg: Dictionary = {}

var _disabled := false
var _ui: CanvasLayer = null
var _panel: ColorRect = null
var _head: Label = null
var _sub: Label = null
var _body: Label = null
var _alert: Label = null
var _tail: Label = null
var _dots: Label = null
var _foot: Label = null
var _tick := 0.0
var _tells: Array[String] = []
var _due_re: RegEx = null
var _names: Dictionary = {}          # profile path -> model name, read once each


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		_disabled = true                  # SMOKE GATE: build nothing, draw nothing
		set_process(false)
		return
	cfg = _load_json(DATA_PATH)
	_load_tells()
	_compile_due()
	_bind_key()
	_build()


## main.gd owns most bindings; register a fallback so the phone opens either way.
## P is free: main binds W/S/A/D, arrows, SPACE, F, E, G, N, Q, CTRL, SHIFT, R,
## BACKSPACE, TAB, C, T, CAPSLOCK, X, H; chase_camera and player_character add
## shoulder_swap and walk_slow; session.gd reads ESC/M raw. None of them is P.
func _bind_key() -> void:
	if InputMap.has_action(ACTION):
		return
	InputMap.add_action(ACTION)
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_P
	InputMap.action_add_event(ACTION, ev)


func _compile_due() -> void:
	var pattern := _s("due_pattern", "")
	if pattern == "":
		return
	var re := RegEx.new()
	if re.compile(pattern) == OK:
		_due_re = re


## The tells come off disk, not off repo_orders.cfg: systems load alphabetically,
## so "phone" is set up before "repo_orders" has read its own file.
func _load_tells() -> void:
	var v: Variant = _load_json(ORDERS_DATA).get("paper_tells", [])
	if not (v is Array):
		return
	for row: Variant in (v as Array):
		var s := str(row)
		if s != "":
			_tells.append(s)


# ============================== THE KEY =======================================
func _process(delta: float) -> void:
	if _disabled:
		return
	if InputMap.has_action(ACTION) and Input.is_action_just_pressed(ACTION):
		toggle()
	if not open:
		return                            # shut: one action poll, zero allocation
	_tick -= delta
	if _tick <= 0.0:
		_refresh()


## PUBLIC (player + probe): one key walks the whole phone and puts it away.
func toggle() -> void:
	if not open:
		open = true
		tab = TAB_LONGHORN
	else:
		tab += 1
		if tab >= TAB_COUNT:
			open = false
			tab = TAB_LONGHORN
	_apply()


## PUBLIC (probe): open the phone straight to a tab.
func show_tab(i: int) -> void:
	open = true
	tab = clampi(i, 0, TAB_COUNT - 1)
	_apply()


## PUBLIC (probe): exactly what a tab renders, as one string, without a window.
## `--mech-probe` asserts on this — e.g. "ORDER" in text_of(0) under a live order.
@warning_ignore("shadowed_variable")
func text_of(tab: int) -> String:
	var parts: Array[String] = []
	var d := _compose(clampi(tab, 0, TAB_COUNT - 1))
	for key: String in PART_KEYS:
		var s := str(d.get(key, ""))
		if s != "":
			parts.append(s)
	return "\n".join(parts)


func _apply() -> void:
	if _panel != null:
		_panel.visible = open
	if open:
		_refresh()


func _refresh() -> void:
	_tick = 1.0 / maxf(_n("refresh_hz", 4.0), 0.5)
	if _panel == null:
		return
	var d := _compose(tab)
	_head.text = str(d.get("head", ""))
	_sub.text = str(d.get("sub", ""))
	_body.text = str(d.get("body", ""))
	_alert.text = str(d.get("alert", ""))
	_tail.text = str(d.get("tail", ""))
	_foot.text = str(d.get("foot", ""))
	_alert.visible = _alert.text != ""
	_sub.visible = _sub.text != ""
	_tail.visible = _tail.text != ""
	_head.add_theme_color_override("font_color", _accent())
	_dots.text = ""
	var dots: Variant = cfg.get("tab_dots", [])
	if dots is Array and tab < (dots as Array).size():
		_dots.text = str((dots as Array)[tab])


## LONGHORN's orange is the order's colour everywhere else in the game; the
## money tabs stay gold so a live order is readable from the dots alone.
func _accent() -> Color:
	if tab == TAB_LONGHORN:
		return _col("orange", "#fa7314")
	return _col("gold", "#edbd63")


func _compose(which: int) -> Dictionary:
	if which == TAB_BOONE:
		return _compose_boone()
	if which == TAB_WALLET:
		return _compose_wallet()
	return _compose_longhorn()


# ============================== 1. LONGHORN ===================================
func _compose_longhorn() -> Dictionary:
	var ro := _peer("repo_orders")
	var body: Array[String] = []
	var alert: Array[String] = []
	if ro != null and bool(ro.get("active")):
		body.append_array(_order_card(ro))
		body.append("")
		body.append(_s("paper_head", "THE PAPER"))
		var push := _last_push()
		body.append(push if push != "" else _s("no_push", ""))
		var tell := _tell_in(push)
		if tell != "":
			alert.append(tell)
			alert.append(_s("read_the_paper", "READ THE PAPER."))
	else:
		body.append(_s("idle", "No open orders."))
	return {
		"head": _s("head_longhorn", "LONGHORN WRECKER & RECOVERY"),
		"sub": _s("sub_longhorn", "a Bolo Capital Company"),
		"body": "\n".join(body),
		"alert": "\n".join(alert),
		"tail": _standing(ro),
		"foot": _s("foot_longhorn", ""),
	}


## The order, as a card. id / debtor / vehicle / what they say is owed, then
## repo_orders' own live objective line verbatim under it — that line already
## counts the metres down, and two formatters for one distance is a canon bug.
func _order_card(ro: Node) -> Array[String]:
	var out: Array[String] = []
	var id := 0
	if ro.has_method("order_id"):
		id = int(ro.call("order_id"))
	out.append(_s("order_head", "ORDER %d") % id)
	var who := _gs(ro, "_who")
	if who != "":
		out.append(who)
	var model := _gs(ro, "_model")
	var year := _gi(ro, "_year")
	var rig := ("%d %s" % [year, model]) if year > 0 and model != "" else model
	if rig != "":
		out.append(rig)
	var due := _due_of(_order_push())
	if due != "":
		out.append(due)
	if ro.has_method("objective_text"):
		var obj := str(ro.call("objective_text"))
		if obj != "":
			out.append(obj)
	return out


## Rank, the quota, and the two counters that are the endings' meter in daily
## form. Shown whether or not an order is live — it is the standing, not the job.
func _standing(ro: Node) -> String:
	if ro == null:
		return ""
	var out: Array[String] = []
	var names := _script_const(ro, "RANK_NAMES")
	var at := _script_const(ro, "RANK_AT")
	var rank := maxi(_gi(ro, "rank", 1), 1)
	var here := str(names[clampi(rank - 1, 0, names.size() - 1)]) if not names.is_empty() else ""
	out.append(_s("rank_line", "RANK %d · %s") % [rank, here])
	if rank < at.size():
		var next_name := str(names[rank]) if rank < names.size() else ""
		out.append(_s("rank_next", "NEXT: %s at %d deliveries") % [next_name, int(at[rank])])
	else:
		out.append(_s("rank_top", ""))
	out.append(_s("deliveries_line", "DELIVERIES %d") % _gi(ro, "deliveries"))
	var quota := 3
	var c: Variant = ro.get("cfg")
	if c is Dictionary:
		quota = maxi(int(_num((c as Dictionary).get("quota", 3), 3.0)), 1)
	out.append(_s("quota_line", "Quota %d/%d today") % [_gi(ro, "quota_done"), quota])
	out.append(_s("counters_line", "PAPER TAKEN %d  ·  PAPER BURNED %d")
		% [_gi(ro, "paper_taken"), _gi(ro, "paper_burned")])
	return "\n".join(out)


# ============================== THE PAPER =====================================
## mission_kit's rolling log of everything anybody has said. The producer is
## adding it; until it lands this returns [] and the phone reads "no push".
func _log() -> Array:
	var mk := _peer("mission_kit")
	if mk == null:
		return []
	var v: Variant = mk.get("log")
	if v is Array:
		return v
	return []


## The app's newest line. For a BAD order that is the FLAG, which is the point:
## the tell is what the phone is for. Falls back to the newest line from anyone
## if the app has not spoken, so the screen is never blank on a live order.
func _last_push() -> String:
	var rows := _log()
	var who := _s("app_speaker", "")
	var newest := ""
	for i in range(rows.size() - 1, -1, -1):
		var d: Dictionary = _row(rows[i])
		var line := str(d.get("line", ""))
		if line == "":
			continue
		if newest == "":
			newest = line
		if who == "" or str(d.get("speaker", "")) == who:
			return line
	return newest


## The ORDER push specifically — the only line that carries the days and the
## amount. Searched backwards over the last `paper_scan` app lines so a live
## order can never quote paper from an order two jobs ago.
func _order_push() -> String:
	if _due_re == null:
		return ""
	var rows := _log()
	var who := _s("app_speaker", "")
	var scan := maxi(_i("paper_scan", 12), 1)
	var seen := 0
	for i in range(rows.size() - 1, -1, -1):
		var d: Dictionary = _row(rows[i])
		var line := str(d.get("line", ""))
		if line == "" or (who != "" and str(d.get("speaker", "")) != who):
			continue
		seen += 1
		if seen > scan:
			break
		if _due_re.search(line) != null:
			return line
	return ""


func _due_of(push: String) -> String:
	if _due_re == null or push == "":
		return ""
	var m := _due_re.search(push)
	if m == null or m.get_group_count() < 2:
		return ""
	return _s("order_due", "%s DAYS PAST DUE  ·  $%s") % [m.get_string(1), m.get_string(2)]


## Does this push carry one of repo_orders' bad-paper tells? The tells hold
## {placeholders}, so the match is on the literal text BEFORE the first brace —
## and a prefix under `tell_min_prefix` is refused outright, which is why
## "DAYS PAST DUE: " (with the colon) can never fire on a clean push that reads
## "118 DAYS PAST DUE". Returns the tell AS THE APP WROTE IT, for the red line.
func _tell_in(push: String) -> String:
	if push == "":
		return ""
	var shortest := _i("tell_min_prefix", 8)
	for t: String in _tells:
		var brace := t.find("{")
		var prefix := (t.substr(0, brace) if brace >= 0 else t).strip_edges()
		if prefix.length() < shortest or not push.contains(prefix):
			continue
		if brace < 0:
			return t
		var rest := push.substr(push.find(prefix))
		var stop := rest.find(". ")
		return (rest.substr(0, stop) if stop > 0 else rest).strip_edges()
	return ""


# ============================== 2. BOONE FINANCIAL ============================
func _compose_boone() -> Dictionary:
	var dl := _peer("dealer")
	var body: Array[String] = []
	var alert: Array[String] = []
	var notes := _notes(dl)
	var months := _note_months(dl)
	if notes.is_empty():
		body.append(_s("boone_none", "No paper with Boone. Appreciate you!"))
	for row: Variant in notes:
		var d := _row(row)
		if d.is_empty():
			continue
		# NAMING BIBLE 7a: the model name is read from the profile it belongs to.
		var rig := _vehicle_name(str(d.get("path", "")))
		var paid := int(_num(d.get("paid", 0), 0.0))
		var missed := int(_num(d.get("missed", 0), 0.0))
		var balance := int(_num(d.get("balance", 0), 0.0))
		body.append(rig)
		body.append("  " + _s("note_line", "$%s/day · %d/%d paid · %d returned")
			% [_commas(int(_num(d.get("monthly", 0), 0.0))), paid, months, missed])
		if paid >= months:
			body.append("  " + _s("title_clear", "TITLE CLEAR"))
		elif balance > 0:
			body.append("  " + _s("note_balance", "balance $%s") % _commas(balance))
		if missed == 1:
			alert.append(_s("warn_recovery", "%s — TWO RETURNED DRAFTS = RECOVERY") % rig)
		body.append("")
	body.append(_s("rigs_head", "RIGS IN YOUR NAME"))
	var rigs := _owned_names()
	if rigs.is_empty():
		body.append(_s("rigs_none", "Nothing titled to you."))
	for r: String in rigs:
		body.append("  " + r)
	return {
		"head": _s("head_boone", "BOONE FINANCIAL"),
		"sub": _s("sub_boone", ""),
		"body": "\n".join(body),
		"alert": "\n".join(alert),
		"tail": "",
		"foot": _s("foot_boone", "Appreciate you!"),
	}


func _notes(dl: Node) -> Array:
	if dl == null:
		return []
	var v: Variant = dl.get("notes")
	if v is Array:
		return v
	return []


func _note_months(dl: Node) -> int:
	var fallback := _i("note_months_default", 96)
	if dl == null:
		return fallback
	var v: Variant = dl.get("cfg")
	if not (v is Dictionary):
		return fallback
	return maxi(int(_num((v as Dictionary).get("note_months", fallback), float(fallback))), 1)


## The profile's own `name`, read once per path and remembered. Never a literal.
func _vehicle_name(path: String) -> String:
	if path == "":
		return ""
	if _names.has(path):
		return str(_names[path])
	var name_of := str(_load_json(path).get("name", ""))
	if name_of == "":
		name_of = path.get_file().get_basename().capitalize()
	_names[path] = name_of
	return name_of


func _owned_names() -> Array[String]:
	var out: Array[String] = []
	if main_ref == null:
		return out
	var v: Variant = main_ref.get("owned_paths")
	if not (v is Array):
		return out
	for p: Variant in (v as Array):
		var name_of := _vehicle_name(str(p))
		if name_of != "":
			out.append(name_of)
	return out


# ============================== 3. WALLET =====================================
func _compose_wallet() -> Dictionary:
	var board := _peer("repo_board")
	var events := _peer("random_events")
	var body: Array[String] = []
	body.append(_s("money_line", "$%s") % _commas(_gi(board, "money")))
	body.append(_s("respect_line", "RESPECT %d") % _gi(board, "respect"))
	body.append(_s("favors_line", "FAVORS %d") % _gi(events, "favors"))
	body.append("")
	body.append(_s("feed_head", "RECENT"))
	var feed := _feed()
	if feed.is_empty():
		body.append(_s("feed_none", "Nobody has said anything to you."))
	body.append_array(feed)
	return {
		"head": _s("head_wallet", "WALLET"),
		"sub": _s("sub_wallet", ""),
		"body": "\n".join(body),
		"alert": "",
		"tail": "",
		"foot": _s("foot_wallet", ""),
	}


## The last few lines anybody said, oldest first — the phone reads down, so the
## newest sits at the bottom where a chat log's newest sits.
func _feed() -> Array[String]:
	var out: Array[String] = []
	var rows := _log()
	var want := maxi(_i("feed_lines", 6), 1)
	var fmt := _s("feed_line", "%s: %s")
	for i in range(maxi(rows.size() - want, 0), rows.size()):
		var d := _row(rows[i])
		if d.is_empty():
			continue
		out.append(fmt % [str(d.get("speaker", "")), str(d.get("line", ""))])
	return out


# ============================== THE HANDSET ===================================
## A phone-shaped slab bottom-right: ink bezel, darker screen, one column.
## Hidden until P. Layer 20 is the prompt tier (carjack, dealer, interactables) —
## over the HUD and the app's own push, under the arrest and pause curtains.
func _build() -> void:
	var w := _n("panel_w", 360.0)
	var h := _n("panel_h", 640.0)
	var m := _n("margin", 24.0)
	var bezel := _n("bezel", 10.0)
	var pad := _n("pad", 16.0)
	_ui = CanvasLayer.new()
	_ui.layer = _i("layer", 20)
	add_child(_ui)
	_panel = ColorRect.new()
	_panel.color = _col("ink", "#101b22", _n("ink_alpha", 0.85))
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -(m + w)
	_panel.offset_right = -m
	_panel.offset_top = -(m + h)
	_panel.offset_bottom = -m
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_ui.add_child(_panel)
	var screen := ColorRect.new()
	screen.color = _col("screen", "#0a1218", _n("screen_alpha", 0.92))
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.offset_left = bezel
	screen.offset_top = bezel
	screen.offset_right = -bezel
	screen.offset_bottom = -bezel
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.add_child(screen)
	screen.add_child(_column(pad))


func _column(pad: float) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.offset_left = pad
	box.offset_top = pad
	box.offset_right = -pad
	box.offset_bottom = -pad
	box.add_theme_constant_override("separation", _i("gap", 7))
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gold := _col("gold", "#edbd63")
	_head = _label(_i("font_head", 13), gold)
	_sub = _label(_i("font_sub", 11), _col("dim", "#8f9a9c"))
	var rule := ColorRect.new()
	rule.color = _col("gold", "#edbd63", 0.35)
	rule.custom_minimum_size = Vector2(0.0, 1.0)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body = _label(_i("font_body", 13), _col("text", "#d7dcd9"))
	_alert = _label(_i("font_alert", 13), _col("red", "#e05a4e"))
	_tail = _label(_i("font_tail", 12), _col("dim", "#8f9a9c"))
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_dots = _label(_i("font_foot", 11), _col("gold", "#edbd63", 0.7))
	_foot = _label(_i("font_foot", 11), _col("dim", "#8f9a9c"))
	for c: Control in [_head, _sub, rule, _body, _alert, _tail, spacer, _dots, _foot]:
		box.add_child(c)
	return box


func _label(size: int, col: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_override("font", ThemeDB.fallback_font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 4)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ============================== DEFENSIVE READS ===============================
## Every peer goes through here. A missing system is a blank line, never a crash.
func _peer(key: String) -> Node:
	if main_ref == null:
		return null
	var sys: Variant = main_ref.get("systems")
	if not (sys is Dictionary):
		return null
	var n: Variant = (sys as Dictionary).get(key, null)
	if n is Node and is_instance_valid(n as Node):
		return n
	return null


func _row(v: Variant) -> Dictionary:
	return v if v is Dictionary else {}


func _gs(o: Object, prop: String, def := "") -> String:
	if o == null:
		return def
	var v: Variant = o.get(prop)
	return str(v) if v != null else def


func _gi(o: Object, prop: String, def := 0) -> int:
	if o == null:
		return def
	return int(_num(o.get(prop), float(def)))


func _num(v: Variant, def: float) -> float:
	return float(v) if (v is int or v is float) else def


## A const off a peer's script (RANK_NAMES, RANK_AT) — `peer.CONST` will not
## compile through a Node-typed reference, and hard-copying the ladder here
## would be a second source of truth for the ranks.
func _script_const(o: Object, key: String) -> Array:
	if o == null:
		return []
	var sc: Variant = o.get_script()
	if not (sc is GDScript):
		return []
	var v: Variant = (sc as GDScript).get_script_constant_map().get(key, [])
	if v is Array:
		return v
	return []


# ============================== SMALL CHANGE ==================================
func _s(key: String, def: String) -> String:
	var v: Variant = cfg.get(key, def)
	return str(v)


func _n(key: String, def: float) -> float:
	return _num(cfg.get(key, def), def)


func _i(key: String, def: int) -> int:
	return int(_n(key, float(def)))


func _col(key: String, def: String, alpha := 1.0) -> Color:
	var c := Color(_s(key, def))
	c.a = alpha
	return c


func _commas(n: int) -> String:
	var digits := str(maxi(n, 0))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return out


func _load_json(path: String) -> Dictionary:
	if path == "" or not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed
	return {}
