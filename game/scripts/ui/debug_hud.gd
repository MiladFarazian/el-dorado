extends CanvasLayer
## EL DORADO GRANDE — DEBUG overlay (M23: demoted from "the HUD" to F3).
## The player-facing HUD is `scripts/systems/hud_gta.gd`. This layer is hidden by
## default and toggles with F3; it shows the numbers a developer wants and a
## player never should: planar speed, the vehicle profile name, FPS, and the
## debug-only keys. It still owns the "reload_tuning" (T) action.
##
## D-031 / D-032 fixed here: every readout comes from `main.player_actor()` — on
## foot that is the character, not the parked truck — and speed is PLANAR
## (x/z), so falling off the freeway deck no longer reads as 30 MPH.
## `vehicle` is kept as a property because main.gd still assigns it (the
## profile_reloaded toast needs the signal); it is not used for any readout.

const MARGIN := 16
const PANEL_BG := Color(0.05, 0.05, 0.08, 0.72)
const TEXT_COLOR := Color(0.95, 0.95, 0.95)
const ACCENT_COLOR := Color(1.0, 0.82, 0.3)
const DIM_COLOR := Color(0.75, 0.75, 0.78)
const SPEED_FONT_SIZE := 34
const BODY_FONT_SIZE := 14
const TOAST_TIME := 1.5
const TOAST_FADE := 0.35
const MPH_PER_MPS := 2.236936

var vehicle: Node:
	set(v):
		vehicle = v
		_connect_vehicle_signals()

var _speed_label: Label
var _name_label: Label
var _fps_label: Label
var _toast_panel: PanelContainer
var _toast_label: Label
var _toast_left := 0.0
var _mono: Font
var _f3_was := false


func _ready() -> void:
	layer = 10
	visible = false  # F3 shows it
	_mono = _make_mono_font()
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := _make_panel()
	top.position = Vector2(MARGIN, MARGIN)
	root.add_child(top)
	var top_box := VBoxContainer.new()
	top_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(top_box)
	_speed_label = _make_label(SPEED_FONT_SIZE, TEXT_COLOR, "--- MPH")
	top_box.add_child(_speed_label)
	_name_label = _make_label(BODY_FONT_SIZE, ACCENT_COLOR, "")
	top_box.add_child(_name_label)
	_fps_label = _make_label(BODY_FONT_SIZE, DIM_COLOR, "FPS --")
	top_box.add_child(_fps_label)
	top_box.add_child(_make_label(BODY_FONT_SIZE, DIM_COLOR,
		"F3 debug · T reload tuning · BACKSPACE reset rig · TAB own rig"))
	_toast_panel = _make_panel()
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast_panel.offset_top = MARGIN * 3
	_toast_panel.visible = false
	root.add_child(_toast_panel)
	_toast_label = _make_label(BODY_FONT_SIZE + 5, ACCENT_COLOR, "TUNING RELOADED")
	_toast_panel.add_child(_toast_label)


func _process(delta: float) -> void:
	var f3 := Input.is_physical_key_pressed(KEY_F3)
	if f3 and not _f3_was:
		visible = not visible
	_f3_was = f3
	if InputMap.has_action("reload_tuning") and Input.is_action_just_pressed("reload_tuning"):
		_request_reload()
	if _toast_left > 0.0:
		_toast_left = maxf(_toast_left - delta, 0.0)
		_toast_panel.modulate.a = clampf(_toast_left / TOAST_FADE, 0.0, 1.0)
		_toast_panel.visible = _toast_left > 0.0
	if visible:
		_update_readouts()


func _actor() -> Node3D:
	var m := get_parent()
	if m != null and m.has_method("player_actor"):
		var a: Variant = m.call("player_actor")
		if a is Node3D and is_instance_valid(a):
			return a as Node3D
	return null


func _update_readouts() -> void:
	_fps_label.text = "FPS %d" % int(Engine.get_frames_per_second())
	var a := _actor()
	if a == null:
		_speed_label.text = "--- MPH"; _name_label.text = ""; return
	var v := Vector3.ZERO
	if a is RigidBody3D: v = (a as RigidBody3D).linear_velocity
	elif a is CharacterBody3D: v = (a as CharacterBody3D).velocity
	_speed_label.text = "%3.0f MPH" % (Vector2(v.x, v.z).length() * MPH_PER_MPS)
	_name_label.text = str(a.get("display_name")) if "display_name" in a else "ON FOOT"


func _request_reload() -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.has_method("reload_profile"):
		return
	_show_toast("TUNING RELOADED")
	vehicle.call("reload_profile")


func _connect_vehicle_signals() -> void:
	if vehicle == null or not is_instance_valid(vehicle) or not vehicle.has_signal("profile_reloaded"):
		return
	var cb := Callable(self, "_on_profile_reloaded")
	if not vehicle.is_connected("profile_reloaded", cb):
		vehicle.connect("profile_reloaded", cb)


func _on_profile_reloaded(display_name: String) -> void:
	_show_toast("TUNING RELOADED: %s" % display_name)


func _show_toast(text: String) -> void:
	_toast_left = TOAST_TIME
	if _toast_label: _toast_label.text = text
	if _toast_panel:
		_toast_panel.modulate.a = 1.0
		_toast_panel.visible = true


func _make_panel() -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_BG
	style.set_corner_radius_all(4)
	style.content_margin_left = 12; style.content_margin_right = 12
	style.content_margin_top = 8; style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return panel


func _make_label(font_size: int, color: Color, text := "") -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", _mono)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_mono_font() -> Font:
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Menlo", "Monaco", "Consolas", "DejaVu Sans Mono", "Courier New", "monospace"])
	return font
