extends Node
## MISSION KIT (D-063; Milad: "improve details of missions"). The presentation
## layer every scripted job shares: the LONGHORN app talking to Book in Bolo
## Capital's push-notification voice (canon: Bolo bought Longhorn and "installed
## quotas and an app"), and the CONTRACT card at the end — title, payout, the
## bonuses that landed, the time, a medal. Text only; the satire is in the copy.
## Missions call say()/card() through main.systems; both are queued and timed
## here so two jobs never shout over each other. Inert in smoke mode.

const LAYER := 16                      # over the missions' 14, under the cards at 30
const PANEL_W := 420.0; const PANEL_H := 96.0; const MARGIN := 18.0
const APP_NAME := "LONGHORN · RECOVERY"
const CARD_H := 190.0
const FADE := 0.35
const C_BG := Color(0.06, 0.07, 0.09, 0.88)
const C_HEAD := Color(0.94, 0.78, 0.30)
const C_TEXT := Color(0.95, 0.93, 0.86)
const C_CARD := Color(0.03, 0.03, 0.04, 0.78)
const C_MEDAL := {"GOLD": Color(0.98, 0.82, 0.30), "SILVER": Color(0.82, 0.84, 0.88), "BRONZE": Color(0.80, 0.52, 0.30)}

var main_ref: Node = null
var _ui: CanvasLayer = null
var _panel: ColorRect = null
var _head: Label = null
var _line: Label = null
var _queue: Array[Dictionary] = []
var log: Array = []   # D-069: {speaker, line, t}, newest last, twelve deep — read by the phone
var _line_left := 0.0
var _line_total := 0.0
var _card: ColorRect = null
var _card_title: Label = null
var _card_sub: Label = null
var _card_rows: Label = null
var _card_medal: Label = null
var _card_left := 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_process(false)
		return
	_build()


## PUBLIC (missions): a line from `speaker`, held `seconds`, queued behind any earlier line.
func say(speaker: String, line: String, seconds := 4.5) -> void:
	_queue.append({"who": speaker, "line": line, "s": maxf(seconds, 1.0)})
	# D-069: the phone shows the last twelve things anyone said.
	log.append({"speaker": speaker, "line": line, "t": Time.get_ticks_msec() * 0.001})
	while log.size() > 12:
		log.pop_front()


## PUBLIC (missions): the end card. `rows` is [[label, value], ...]; `medal` GOLD/SILVER/BRONZE or "".
func card(title: String, subtitle: String, rows: Array, medal := "", seconds := 6.0) -> void:
	if _card == null:
		return
	_card_title.text = title
	_card_sub.text = subtitle
	var lines: Array[String] = []
	for r: Variant in rows:
		if r is Array and (r as Array).size() >= 2:
			lines.append("%s    %s" % [str((r as Array)[0]), str((r as Array)[1])])
	_card_rows.text = "\n".join(lines)
	_card_medal.text = medal
	_card_medal.add_theme_color_override("font_color", C_MEDAL.get(medal, C_HEAD))
	_card_left = seconds
	_card.modulate.a = 0.0
	_card.visible = true


## PUBLIC (probe): lines still to show, including the one on screen.
func lines_queued() -> int:
	return _queue.size() + (1 if _line_left > 0.0 else 0)


func card_visible() -> bool:
	return _card != null and _card.visible


func _process(delta: float) -> void:
	if _panel == null:
		return
	if _line_left > 0.0:
		_line_left -= delta
		var a := minf(_line_left / FADE, 1.0)
		var b := minf((_line_total - _line_left) / FADE, 1.0)
		_panel.modulate.a = clampf(minf(a, b), 0.0, 1.0)
		if _line_left <= 0.0:
			_panel.visible = false
	elif not _queue.is_empty():
		var q: Dictionary = _queue.pop_front()
		_head.text = str(q["who"])
		_line.text = str(q["line"])
		_line_total = float(q["s"]); _line_left = _line_total
		_panel.modulate.a = 0.0
		_panel.visible = true
	if _card != null and _card.visible:
		_card_left -= delta
		var ca := minf(_card_left / (FADE * 2.0), 1.0)
		_card.modulate.a = clampf(ca, 0.0, 1.0)
		if _card_left <= 0.0:
			_card.visible = false


func _build() -> void:
	_ui = CanvasLayer.new(); _ui.layer = LAYER; add_child(_ui)
	_panel = ColorRect.new(); _panel.color = C_BG
	_panel.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_panel.offset_left = -(MARGIN + PANEL_W); _panel.offset_right = -MARGIN
	_panel.offset_top = -(MARGIN + PANEL_H); _panel.offset_bottom = -MARGIN
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_panel.visible = false; _ui.add_child(_panel)
	_head = _label(APP_NAME, 12, C_HEAD); _head.position = Vector2(12, 8); _panel.add_child(_head)
	_line = _label("", 15, C_TEXT); _line.position = Vector2(12, 28)
	_line.size = Vector2(PANEL_W - 24, PANEL_H - 34)
	_line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; _panel.add_child(_line)
	_card = ColorRect.new(); _card.color = C_CARD
	_card.set_anchors_preset(Control.PRESET_CENTER)
	_card.offset_left = -900.0; _card.offset_right = 900.0
	_card.offset_top = -CARD_H * 0.5 - 40.0; _card.offset_bottom = CARD_H * 0.5 - 40.0
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE; _card.visible = false; _ui.add_child(_card)
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 4)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE; _card.add_child(box)
	_card_title = _label("", 44, C_TEXT); _card_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_sub = _label("", 18, C_HEAD); _card_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_rows = _label("", 16, C_TEXT); _card_rows.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_card_medal = _label("", 22, C_HEAD); _card_medal.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for l in [_card_title, _card_sub, _card_rows, _card_medal]:
		box.add_child(l)


func _label(text: String, size: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 5)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l
