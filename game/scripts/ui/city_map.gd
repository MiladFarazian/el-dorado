extends Control
## North-up schematic of the built world, drawn from THE ATLAS
## (data/world/atlas.json, D-066): every district, every road that is not the
## downtown grid, every nameable place — plus the session's jobs, the route,
## the player and the waypoint. The grid itself comes from city_dressing's
## constants, which are the streets' source of truth. No extra 3D camera.
const CITY := preload("res://scripts/world/greybox_city.gd")
const DRESS := preload("res://scripts/world/city_dressing.gd")
const ATLAS_PATH := "res://data/world/atlas.json"
const GOLD := Color("edbd63")
const INK := Color("101b22")
const PRAIRIE := Color("1e302e")
const GRID_ROAD := Color("8b9798")
const ROAD_STYLE := {   # class -> [colour, width]; dirt is dashed
	"freeway": [Color("b2a88b"), 5.0], "frontage": [Color("6c797b"), 1.5],
	"ramp": [Color("8b9798"), 2.0], "street": [Color("8b9798"), 3.0],
	"strip": [Color("d98fb8"), 3.0], "dirt": [Color("7a6446"), 1.5],
}
const PLACE_STYLE := {   # kind -> colour of the dot
	"tower": Color("7ee08a"), "hospital": Color("f0605a"), "impound": GOLD,
	"church": Color("e8d9a8"), "stadium": Color("9fb4e8"), "industry": Color("a0d060"),
	"watertower": Color("cfd6d8"), "race": Color("d98fb8"), "wheel": Color("f2b070"),
	"statue": Color("f2b070"), "sales": Color("e8e070"),
}
var session: Node
var _scale := 1.0
var _center := Vector2.ZERO
var _atlas: Dictionary = {}

func _ready() -> void:
	clip_contents = true
	custom_minimum_size = Vector2(300, 240)
	resized.connect(queue_redraw)
	gui_input.connect(_map_input)
	_atlas = load_atlas()

## Shared with anything else that wants the register (the radar, a test).
static func load_atlas() -> Dictionary:
	var empty := {"districts": [], "roads": [], "places": []}
	var f := FileAccess.open(ATLAS_PATH, FileAccess.READ)
	if f == null:
		push_error("ATLAS missing: " + ATLAS_PATH)
		return empty
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if not (parsed is Dictionary):
		push_error("ATLAS failed to parse: " + ATLAS_PATH)
		return empty
	return parsed

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

func _polyline(pts: Array, cls: String) -> void:
	var style: Array = ROAD_STYLE.get(cls, ROAD_STYLE["street"])
	for i in range(1, pts.size()):
		var a := world_to_map(Vector2(float(pts[i - 1][0]), float(pts[i - 1][1])))
		var b := world_to_map(Vector2(float(pts[i][0]), float(pts[i][1])))
		if cls == "dirt":
			draw_dashed_line(a, b, style[0], style[1], 5.0, true, true)
		else:
			draw_line(a, b, style[0], style[1], true)

func _draw() -> void:
	_scale = minf(size.x, size.y) / 2100.0
	_center = size * 0.5
	draw_rect(Rect2(Vector2.ZERO, size), INK)
	_block(Rect2(-1000, -1000, 2000, 2000), PRAIRIE)
	var districts: Array = _atlas.get("districts", [])
	for d: Dictionary in districts:
		var r: Array = d["rect"]
		var rect := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
		_block(rect, Color(str(d.get("fill", "2c4038"))))
		draw_rect(Rect2(world_to_map(rect.position), rect.size * _scale), Color(1, 1, 1, 0.08), false, 1.0)
	var roads: Array = _atlas.get("roads", [])
	for cls in ["dirt", "frontage", "ramp", "street", "strip"]:
		for road: Dictionary in roads:
			if str(road["class"]) == cls:
				_polyline(road["pts"], cls)
	for x in DRESS.NS_X:
		_line(Vector2(x, DRESS.NS_Z_RANGE.x), Vector2(x, DRESS.NS_Z_RANGE.y), GRID_ROAD, 3)
	for z in DRESS.EW_Z:
		_line(Vector2(DRESS.EW_X_RANGE.x, z), Vector2(DRESS.EW_X_RANGE.y, z), GRID_ROAD, 3)
	for road: Dictionary in roads:
		if str(road["class"]) == "freeway":
			_polyline(road["pts"], "freeway")
	# Type scales with the panel: a 2 km world in 420 px cannot carry names
	# beside every dot (each name would span 500 m of ground), so a small map
	# shows district names and dots, and the place names arrive with size.
	var district_font := clampi(int(_scale * 52.0), 9, 14)
	var place_font := clampi(int(_scale * 40.0), 9, 12)
	for d: Dictionary in districts:
		var lp: Array = d["label"]
		_text(world_to_map(Vector2(float(lp[0]), float(lp[1]))) + Vector2(0, -3), str(d["name"]), Color("a5b7aa"), district_font)
	for p: Dictionary in _atlas.get("places", []):
		var pos := world_to_map(Vector2(float(p["pos"][0]), float(p["pos"][1])))
		var col: Color = PLACE_STYLE.get(str(p.get("kind", "")), Color("d7dcd9"))
		draw_circle(pos, 4.0, col)
		draw_arc(pos, 4.5, 0, TAU, 16, INK, 1.0, true)
		if _scale >= 0.26:
			_text(pos + Vector2(7, 4), str(p["name"]), Color("d7dcd9"), place_font)
	_draw_markers()
	var bar := 500.0 * _scale
	var o := Vector2(16, size.y - 16)
	draw_line(o, o + Vector2(bar, 0), Color("a6b1b8"), 2.0, true)
	_text(o + Vector2(0, -6), "500 m", Color("a6b1b8"), 11)

func _draw_markers() -> void:
	for i in range(1, session.route.size()):
		_line(session.route[i - 1], session.route[i], GOLD, 3)
	var legend := PackedStringArray()
	for i in session.activities.size():
		var p := world_to_map(session.activities[i].pos)
		draw_circle(p, 8, GOLD)
		_text(p + Vector2(-4, 4), str(i + 1), INK, 12)
		legend.append("%d %s" % [i + 1, str(session.activities[i].name).to_upper()])
	var actor: Node3D = session.main_ref.player_actor()
	if is_instance_valid(actor):
		var p := world_to_map(Vector2(actor.global_position.x, actor.global_position.z))
		var points := PackedVector2Array()
		for v in [Vector2(0, -9), Vector2(6, 6), Vector2(0, 3), Vector2(-6, 6)]:
			points.append(p + v.rotated(-actor.rotation.y))
		draw_circle(p, 12, INK)
		draw_colored_polygon(points, Color.WHITE)
		_text(p + Vector2(14, 4), "YOU", Color.WHITE, 12)
	var destination: Dictionary = session.navigation_target()
	if not destination.is_empty():
		var p := world_to_map(destination.pos)
		draw_arc(p, 13, 0, TAU, 32, GOLD, 2, true)
		_line(destination.pos - Vector2(25, 0), destination.pos + Vector2(25, 0), GOLD)
		_line(destination.pos - Vector2(0, 25), destination.pos + Vector2(0, 25), GOLD)
	# The job key, split across two lines so seven jobs fit the panel.
	var half := int(ceil(legend.size() / 2.0))
	_text(Vector2(16, 24), "    ".join(legend.slice(0, half)), GOLD, 12)
	_text(Vector2(16, 42), "    ".join(legend.slice(half)), GOLD, 12)
