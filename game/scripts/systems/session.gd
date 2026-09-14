extends Node
## Session flow and navigation. Does not move the player or bypass mission rules.
const MAP_VIEW := preload("res://scripts/ui/city_map.gd")
const HOOK := preload("res://scripts/systems/mission_hook_and_ladder.gd")
const SECOND := preload("res://scripts/systems/mission_second_collection.gd")
const RACE := preload("res://scripts/systems/race_event.gd")
const COMIN := preload("res://scripts/systems/mission_comin_down.gd")
const GOLD := Color("edbd63")
var main_ref: Node
var menu: CanvasLayer
var map: Control
var title: Label
var detail: Label
var nav_label: Label
var resume_button: Button
var opened := false
var started := false
var waypoint := Vector2.ZERO
var waypoint_name := ""
var _hidden_layers: Array[CanvasLayer] = []
var _arrival_left := 0.0
var _previous_fps := 0
var route := PackedVector2Array()
var _route_timer := 0.0
var _roads: RefCounted = preload("res://scripts/ui/street_route.gd").new()
var activities: Array[Dictionary] = [
	{"name": "Hook and Ladder", "pos": Vector2(HOOK.DISPATCH_POS.x, HOOK.DISPATCH_POS.z),
	 "text": "LONGHORN DISPATCH  /  $600\nYour first job. Drive your wrecker into the gold marker and stop. Find the Brisket, back up close, press F to hook it, then haul it to impound."},
	{"name": "The Second Collection", "pos": Vector2(SECOND.BOARD_POS.x, SECOND.BOARD_POS.z),
	 "text": "OVERFLOW FELLOWSHIP  /  NIGHT REPO\nA booted fleet vehicle. Reach the job board to begin. Leave the truck outside, sneak in, and find a way to remove the boot. Quiet work pays better."},
	{"name": "Comin' Down", "pos": Vector2(COMIN.BOARD_POS.x, COMIN.BOARD_POS.z),
	 "text": "CANDYLAND C.C.  /  THE SLOW LANE\nBring the Candyland Slab (TAB) to the strip's west gate, slow. Three passes gate to gate under thirty while the Task Force shows. Then the takeover on the lot, and slide out."},
	{"name": "Floodway Sprint", "pos": Vector2(RACE.PAD_CENTER.x, RACE.PAD_CENTER.z),
	 "text": "THREEFORK FLOODWAY  /  TIME TRIAL\nDrive down into the concrete channel and stop on the race marker. Follow the checkpoints. Beat your best time."},
	{"name": "Impound", "pos": Vector2(HOOK.PAD_CENTER.x, HOOK.PAD_CENTER.z),
	 "text": "LONGHORN IMPOUND\nBring repossessed vehicles here. Stop inside the pad and press F to release your tow."},
	{"name": "County General", "pos": Vector2(365, 612),
	 "text": "COUNTY GENERAL\nThe city puts you back on your feet here when a night goes wrong."},
]

func setup(main: Node) -> void:
	main_ref = main
	if main.smoke_mode:
		set_process(false)
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_menu()
	_build_navigation()
	# Give save restoration five physics frames before the opening screen.
	_boot.call_deferred()

func _boot() -> void:
	for i in 8:
		await get_tree().physics_frame
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--mapshot="):
			await _map_shot(arg.trim_prefix("--mapshot="))
			return
		if arg.begins_with("--shot") or arg.begins_with("--hudshot") or arg.begins_with("--perf") \
				or arg.begins_with("--session-test") or arg.begins_with("--mech-probe") or arg.begins_with("--wanted-probe"):
			started = true
			return
	if DisplayServer.get_name() != "headless":
		select_activity(0)
		show_menu()

## D-066: `--mapshot=/abs/path.png` (windowed) — open the city map exactly as
## the player sees it and save the window. The map's own review plate.
func _map_shot(path: String) -> void:
	started = true
	select_activity(0)
	show_menu()
	for i in 6:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("MAPSHOT: " + path)
	get_tree().quit()

func _input(event: InputEvent) -> void:
	if main_ref.smoke_mode or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.physical_keycode in [KEY_ESCAPE, KEY_M]:
		if opened:
			resume()
		else:
			show_menu()
		get_viewport().set_input_as_handled()

func show_menu() -> void:
	if opened:
		return
	opened = true
	_previous_fps = Engine.max_fps
	Engine.max_fps = 30
	var combat: Node = main_ref.systems.get("combat")
	if combat != null:
		combat._wheel_close(false)
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_hidden_layers.clear()
	for system: Node in main_ref.systems.values():
		if system == self:
			continue
		for child in system.get_children():
			if child is CanvasLayer and child.visible:
				_hidden_layers.append(child)
				child.hide()
	title.text = "THE MEGAPLEX" if started else "EL DORADO\nGRANDE"
	resume_button.text = "RESUME  →" if started else "ENTER THE CITY  →"
	menu.show()
	map.queue_redraw()
	resume_button.grab_focus()

func resume() -> void:
	opened = false
	started = true
	Engine.max_fps = _previous_fps
	menu.hide()
	for layer in _hidden_layers:
		if is_instance_valid(layer):
			layer.show()
	_hidden_layers.clear()
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func set_destination(pos: Vector2, label_text: String) -> void:
	waypoint = pos
	waypoint_name = label_text
	_arrival_left = 0.0
	_refresh_route()
	map.queue_redraw()

func select_activity(index: int) -> void:
	var activity := activities[index]
	set_destination(activity.pos, activity.name)
	detail.text = activity.text + "\n\nDestination selected. Resume to head there."

func clear_destination() -> void:
	waypoint_name = ""
	route.clear()
	map.queue_redraw()

func _build_menu() -> void:
	menu = CanvasLayer.new()
	menu.layer = 100
	add_child(menu)
	var root := ColorRect.new()
	root.color = Color(0.022, 0.031, 0.039, 0.97)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	menu.add_child(root)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 32)
	root.add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	margin.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 360
	left.add_theme_constant_override("separation", 12)
	columns.add_child(left)
	left.add_child(_label("BOOKER REYES  /  DORADO, TEXAS", 14, GOLD))
	title = _label("EL DORADO\nGRANDE", 48, Color.WHITE)
	left.add_child(title)
	left.add_child(_label("A city on credit. You're here to collect.", 17, Color("a6b1b8")))
	resume_button = _button("ENTER THE CITY  →", resume)
	left.add_child(resume_button)
	left.add_child(_label("JOBS & PLACES", 14, GOLD))
	for i in activities.size():
		left.add_child(_button(activities[i].name, select_activity.bind(i)))
	detail = _label("You're Book Reyes, repo man.\nStart with Hook and Ladder, chase a race time, or take the city at your own pace.\n\nChoose a place to set your destination.", 17, Color("bbc5cb"))
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(detail)
	left.add_child(_button("CLEAR DESTINATION", clear_destination))
	left.add_child(_button("QUIT TO DESKTOP", _quit))
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 12)
	columns.add_child(right)
	right.add_child(_label("CITY MAP     /     N ↑", 22, GOLD))
	map = MAP_VIEW.new()
	map.session = self
	map.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(map)
	right.add_child(_label("CLICK MAP: WAYPOINT     ·     RIGHT CLICK: CLEAR     ·     ESC / M: RESUME", 13, Color("a6b1b8")))
	var controls := _label("BEHIND THE WHEEL\nWASD  Drive     SPACE  Handbrake     E  Exit     F  Tow hook\nC  Camera     N  Radio     BACKSPACE  Recover vehicle\n\nON FOOT\nWASD  Move     SHIFT  Sprint     SPACE  Jump     CTRL  Crouch\nE  Take vehicle     RMB  Aim     LMB  Attack     Q  Weapon\nR  Reload     V  Swap shoulder     G  Interact", 16, Color("c5cbd0"))
	right.add_child(controls)
	menu.hide()

func _label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _button(value: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = value
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.custom_minimum_size.y = 38
	button.add_theme_font_size_override("font_size", 16)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("19242c")
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.set_corner_radius_all(3)
	button.add_theme_stylebox_override("normal", style)
	var focus := style.duplicate() as StyleBoxFlat
	focus.bg_color = Color("584a31")
	focus.border_color = GOLD
	focus.set_border_width_all(1)
	button.add_theme_stylebox_override("hover", focus)
	button.add_theme_stylebox_override("focus", focus)
	button.pressed.connect(action)
	return button

func _quit() -> void:
	var save: Node = main_ref.systems.get("save_load")
	if save != null:
		save.save_now()
	get_tree().quit()

func navigation_target() -> Dictionary:
	for key in ["mission_hook_and_ladder", "mission_second_collection"]:
		var mission: Node = main_ref.systems.get(key)
		if mission == null:
			continue
		var state: int = mission.state
		var delivering := 3 if key == "mission_hook_and_ladder" else 4
		if state < 1 or state > delivering:
			continue
		if state == delivering:
			return {"pos": Vector2(HOOK.PAD_CENTER.x, HOOK.PAD_CENTER.z), "name": "Deliver to impound"}
		var target: Node3D = mission.get("_target")
		if is_instance_valid(target):
			return {"pos": Vector2(target.global_position.x, target.global_position.z), "name": "Repo vehicle"}
	if not waypoint_name.is_empty():
		return {"pos": waypoint, "name": waypoint_name}
	return {}

func _build_navigation() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 15
	add_child(layer)
	var box := VBoxContainer.new()
	box.position = Vector2(24, 24)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(box)
	nav_label = _label("", 20, GOLD)
	nav_label.add_theme_constant_override("outline_size", 5)
	nav_label.add_theme_color_override("font_outline_color", Color.BLACK)
	nav_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(nav_label)
	var hint := _label("M  CITY MAP    /    ESC  PAUSE", 13, Color.WHITE)
	hint.add_theme_constant_override("outline_size", 4)
	hint.add_theme_color_override("font_outline_color", Color.BLACK)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(hint)

func _process(delta: float) -> void:
	if opened or nav_label == null:
		return
	var actor: Node3D = main_ref.player_actor()
	if not is_instance_valid(actor):
		return
	var destination := navigation_target()
	_route_timer -= delta
	if _route_timer <= 0.0:
		_route_timer = 0.5
		_refresh_route()
	if destination.is_empty():
		_arrival_left = maxf(0.0, _arrival_left - delta)
		nav_label.text = "DESTINATION REACHED" if _arrival_left > 0.0 else "Find work at Longhorn Dispatch  ·  M"
		return
	var position_2d := Vector2(actor.global_position.x, actor.global_position.z)
	var distance := position_2d.distance_to(destination.pos)
	nav_label.text = "%s  ·  %d m" % [destination.name.to_upper(), int(distance)]
	if not waypoint_name.is_empty() and distance < 12.0 and destination.pos == waypoint:
		waypoint_name = ""
		_arrival_left = 4.0

func _refresh_route() -> void:
	var actor: Node3D = main_ref.player_actor()
	var destination := navigation_target()
	route.clear()
	if is_instance_valid(actor) and not destination.is_empty():
		route = _roads.build_route(Vector2(actor.global_position.x, actor.global_position.z), destination.pos)
