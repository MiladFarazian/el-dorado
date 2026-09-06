extends Control
## North-up schematic from the world's road coordinates; no extra 3D camera.
const CITY := preload("res://scripts/world/greybox_city.gd")
const DRESS := preload("res://scripts/world/city_dressing.gd")
const GOLD := Color("edbd63")
var session: Node
var _scale := 1.0
var _center := Vector2.ZERO

func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(300, 240)
	resized.connect(queue_redraw)
	gui_input.connect(_map_input)

func world_to_map(point: Vector2) -> Vector2:
	return _center + point * _scale

func map_to_world(point: Vector2) -> Vector2:
	return (point - _center) / _scale

func _map_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			session.clear_destination()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			var nearest := -1
			var best := 15.0
			for i in session.activities.size():
				var distance: float = event.position.distance_to(world_to_map(session.activities[i].pos))
				if distance < best:
					best = distance
					nearest = i
			if nearest >= 0:
				session.select_activity(nearest)
				accept_event()
				return
			var point := map_to_world(event.position)
			if absf(point.x) <= CITY.MAP_HALF and absf(point.y) <= CITY.MAP_HALF:
				session.set_destination(point, "Waypoint")
				session.detail.text = "WAYPOINT SET\nThe gold marker shows your destination. Distance is straight-line; use the streets and crossings to get there."
		accept_event()

func _line(a: Vector2, b: Vector2, color: Color, width: float = 2.0) -> void:
	draw_line(world_to_map(a), world_to_map(b), color, width, true)

func _block(rect: Rect2, color: Color) -> void:
	draw_rect(Rect2(world_to_map(rect.position), rect.size * _scale), color)

func _text(point: Vector2, value: String, color: Color, font_size: int = 13) -> void:
	draw_string(ThemeDB.fallback_font, point, value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func _draw() -> void:
	_scale = minf(size.x, size.y) / 2100.0
	_center = size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), Color("101b22"))
	_block(Rect2(-1000, -1000, 2000, 2000), Color("1e302e"))
	_block(CITY.SUB_RECT, Color("2c4038"))
	_block(Rect2(120, 60, 688, 516), Color("344047"))
	_block(Rect2(CITY.CH_X0, CITY.CH_Z0, CITY.CH_X1 - CITY.CH_X0, 900), Color("49575a"))
	for x in DRESS.NS_X:
		_line(Vector2(x, DRESS.NS_Z_RANGE.x), Vector2(x, DRESS.NS_Z_RANGE.y), Color("8b9798"), 3)
	for z in DRESS.EW_Z:
		_line(Vector2(DRESS.EW_X_RANGE.x, z), Vector2(DRESS.EW_X_RANGE.y, z), Color("8b9798"), 3)
	_line(Vector2(-800, 0), Vector2(800, 0), Color("b2a88b"), 5)
	for side in [-1, 1]:
		_line(Vector2(-800, side * CITY.FRONTAGE_Z), Vector2(800, side * CITY.FRONTAGE_Z), Color("6c797b"))
	_line(Vector2(365, 563), Vector2(365, 640), Color("8b9798"))
	_text(world_to_map(Vector2(-520, -750)), "STONEBRIDLE", Color("a5b7aa"))
	_text(world_to_map(Vector2(230, 90)), "DORADO", Color("c9d1d0"))
	_text(world_to_map(Vector2(-940, 550)), "THREEFORK", Color("a5b7aa"))
	_draw_markers()

func _draw_markers() -> void:
	for i in range(1, session.route.size()):
		_line(session.route[i - 1], session.route[i], GOLD, 3)
	for i in session.activities.size():
		var p := world_to_map(session.activities[i].pos)
		draw_circle(p, 8, GOLD)
		_text(p + Vector2(-4, 4), str(i + 1), Color("101b22"), 12)
	var actor: Node3D = session.main_ref.player_actor()
	if is_instance_valid(actor):
		var p := world_to_map(Vector2(actor.global_position.x, actor.global_position.z))
		var points := PackedVector2Array()
		for v in [Vector2(0, -9), Vector2(6, 6), Vector2(0, 3), Vector2(-6, 6)]:
			points.append(p + v.rotated(-actor.rotation.y))
		draw_circle(p, 12, Color("101b22"))
		draw_colored_polygon(points, Color.WHITE)
		_text(p + Vector2(14, 4), "YOU", Color.WHITE, 12)
	var destination: Dictionary = session.navigation_target()
	if not destination.is_empty():
		var p := world_to_map(destination.pos)
		draw_arc(p, 13, 0, TAU, 32, GOLD, 2, true)
		_line(destination.pos - Vector2(25, 0), destination.pos + Vector2(25, 0), GOLD)
		_line(destination.pos - Vector2(0, 25), destination.pos + Vector2(0, 25), GOLD)
	_text(Vector2(16, 24), "1 DISPATCH    2 NIGHT REPO    3 RACE    4 IMPOUND    5 HOSPITAL", GOLD, 12)
