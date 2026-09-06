extends Node
## MINIMAP (M14) — a schematic radar, bottom-left, drawn from the city's own
## layout constants (no cameras, no viewports: a Control _draw pass at 20 Hz).
## North-up, centred on the player; roads from city_dressing's street tables,
## the freeway/frontage/floodway from greybox_city's, plus blips: player arrow
## (facing), the wrecker, police cruisers, foot officers, the repo target, and
## fixed markers for County General and the impound pad. ENTIRELY INERT in
## smoke mode. Every Control is MOUSE_FILTER_IGNORE (HUD law — a STOP control
## eats captured-mouse look).

const DRESS := preload("res://scripts/world/city_dressing.gd")
const CITY := preload("res://scripts/world/greybox_city.gd")

# ============================== TUNABLES =====================================
const SIZE := 160.0                  # px, square
const RANGE := 170.0                 # metres of world shown across half the map
const MARGIN_LEFT := 14.0
const BOTTOM_OFFSET := -380.0        # ledger slot: y[-380,-220] bottom-left
const REDRAW_HZ := 20.0
const BG_COLOR := Color(0.05, 0.06, 0.07, 0.72)
const BORDER_COLOR := Color(0.85, 0.8, 0.65, 0.5)
const ROAD_COLOR := Color(0.45, 0.45, 0.48, 0.85)
const FWY_COLOR := Color(0.55, 0.53, 0.5, 0.9)
const WATER_COLOR := Color(0.25, 0.4, 0.5, 0.8)
const PLAYER_COLOR := Color(1, 1, 1, 0.95)
const TRUCK_COLOR := Color(0.35, 0.65, 1.0, 0.95)
const COP_COLOR := Color(1.0, 0.25, 0.2, 0.95)
const TARGET_COLOR := Color(1.0, 0.75, 0.2, 0.95)
const HOSPITAL_COLOR := Color(0.9, 0.2, 0.2, 0.9)
const PAD_COLOR := Color(0.4, 0.9, 0.5, 0.85)
const HOSPITAL_POS := Vector2(365.0, 612.0)
const PAD_POS := Vector2(709.0, 558.0)

# ============================== STATE ========================================
var main_ref: Node = null
var _ui: CanvasLayer = null
var _map: Control = null
var _accum := 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		set_process(false)
		return  # smoke gate: fully inert
	_ui = CanvasLayer.new()
	_ui.layer = 9  # under combat (11) / stars (12); over nothing that matters
	add_child(_ui)
	_map = Control.new()
	_map.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_map.offset_left = MARGIN_LEFT
	_map.offset_right = MARGIN_LEFT + SIZE
	_map.offset_top = BOTTOM_OFFSET
	_map.offset_bottom = BOTTOM_OFFSET + SIZE
	_map.clip_contents = true
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law
	_map.draw.connect(_on_draw)
	_ui.add_child(_map)


func _process(delta: float) -> void:
	# M23: hud_gta draws the radar; this square yields to it whenever that
	# system is loaded (kept as the fallback if hud_gta is ever removed).
	if _map != null and is_instance_valid(_map):
		var sys: Variant = main_ref.get("systems") if main_ref != null else null
		var yield_to_hud := sys is Dictionary and (sys as Dictionary).has("hud_gta")
		if _map.visible == yield_to_hud:
			_map.visible = not yield_to_hud
		if yield_to_hud:
			return
	_accum += delta
	if _accum >= 1.0 / REDRAW_HZ:
		_accum = 0.0
		if _map != null and is_instance_valid(_map):
			_map.queue_redraw()


# ============================== DRAW =========================================
## World -> map: north-up, player-centred. World -z is north; screen y grows
## down; so map_y = (wz - pz) * s + half lands north at the top for free.
func _on_draw() -> void:
	var focus := _focus_pos()
	var s := SIZE * 0.5 / RANGE
	var half := SIZE * 0.5
	_map.draw_rect(Rect2(0, 0, SIZE, SIZE), BG_COLOR, true)

	# --- Downtown street grid (from the dressing layer's own tables).
	for xv: Variant in DRESS.NS_X:
		var x := float(xv)
		_seg(Vector2(x, DRESS.NS_Z_RANGE.x), Vector2(x, DRESS.NS_Z_RANGE.y),
			focus, s, half, ROAD_COLOR, 3.0)
	for zv: Variant in DRESS.EW_Z:
		var z := float(zv)
		_seg(Vector2(DRESS.EW_X_RANGE.x, z), Vector2(DRESS.EW_X_RANGE.y, z),
			focus, s, half, ROAD_COLOR, 3.0)
	# --- Freeway deck + frontage roads.
	_seg(Vector2(-CITY.FWY_HALF_LEN, 0), Vector2(CITY.FWY_HALF_LEN, 0),
		focus, s, half, FWY_COLOR, maxf(CITY.FWY_HALF_W * 2.0 * s, 4.0))
	for side: float in [-1.0, 1.0]:
		_seg(Vector2(-CITY.FWY_HALF_LEN, side * CITY.FRONTAGE_Z),
			Vector2(CITY.FWY_HALF_LEN, side * CITY.FRONTAGE_Z),
			focus, s, half, ROAD_COLOR, 2.0)
	# --- The Threefork floodway channel.
	var ch_a := _to_map(Vector2(CITY.CH_X0, CITY.CH_Z0), focus, s, half)
	var ch_b := _to_map(Vector2(CITY.CH_X1, 1000.0), focus, s, half)
	var ch_rect := Rect2(ch_a, ch_b - ch_a).abs()
	if ch_rect.intersects(Rect2(0, 0, SIZE, SIZE)):
		_map.draw_rect(ch_rect, WATER_COLOR, true)

	# --- Fixed markers.
	_marker(HOSPITAL_POS, focus, s, half, HOSPITAL_COLOR, "H")
	_marker(PAD_POS, focus, s, half, PAD_COLOR, "P")

	# --- Blips.
	var own: Variant = main_ref.get("own_vehicle")
	if own is Node3D and is_instance_valid(own) and (own as Node3D).is_inside_tree():
		var p := _to_map(_flat((own as Node3D).global_position), focus, s, half)
		_map.draw_rect(Rect2(p - Vector2(3, 3), Vector2(6, 6)), TRUCK_COLOR, true)
	for grp: String in ["police", "officer"]:
		for n: Node in get_tree().get_nodes_in_group(grp):
			if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
				var cp := _to_map(_flat((n as Node3D).global_position), focus, s, half)
				_map.draw_circle(cp, 3.0, COP_COLOR)
	var repo := _peer("repo_board")
	if repo != null:
		var tgt: Variant = repo.get("_target")
		if tgt is Node3D and is_instance_valid(tgt) and (tgt as Node3D).is_inside_tree():
			var tp := _to_map(_flat((tgt as Node3D).global_position), focus, s, half)
			_map.draw_circle(tp, 3.5, TARGET_COLOR)

	# --- The player arrow, rotated to facing, always at centre.
	var yaw := _focus_yaw()
	var c := Vector2(half, half)
	var pts := PackedVector2Array()
	for v: Vector2 in [Vector2(0, -7), Vector2(4.6, 5), Vector2(-4.6, 5)]:
		pts.append(c + v.rotated(-yaw))
	_map.draw_colored_polygon(pts, PLAYER_COLOR)

	_map.draw_rect(Rect2(0.5, 0.5, SIZE - 1.0, SIZE - 1.0), BORDER_COLOR, false, 1.5)


func _seg(wa: Vector2, wb: Vector2, focus: Vector2, s: float, half: float,
		col: Color, width: float) -> void:
	_map.draw_line(_to_map(wa, focus, s, half), _to_map(wb, focus, s, half), col, width)


func _marker(world: Vector2, focus: Vector2, s: float, half: float,
		col: Color, glyph: String) -> void:
	var p := _to_map(world, focus, s, half)
	if p.x < -8.0 or p.y < -8.0 or p.x > SIZE + 8.0 or p.y > SIZE + 8.0:
		return
	_map.draw_rect(Rect2(p - Vector2(5, 5), Vector2(10, 10)), col, true)
	_map.draw_string(ThemeDB.fallback_font, p + Vector2(-3.4, 3.6), glyph,
		HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color(1, 1, 1, 0.95))


func _to_map(world: Vector2, focus: Vector2, s: float, half: float) -> Vector2:
	return (world - focus) * s + Vector2(half, half)


func _flat(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


# ============================== PLUMBING =====================================
## The thing the map centres on: the character on foot, else the vehicle.
func _focus_node() -> Node3D:
	for prop: String in (["character", "vehicle"] if main_ref.get("on_foot") == true \
			else ["vehicle", "character"]):
		var v: Variant = main_ref.get(prop)
		if v is Node3D and is_instance_valid(v) and (v as Node3D).is_inside_tree():
			return v
	return null


func _focus_pos() -> Vector2:
	var n := _focus_node()
	return _flat(n.global_position) if n != null else Vector2.ZERO


## Facing yaw for the arrow. Vehicles face -basis.z; the character's facing is
## rotation.y. atan2 in world (x, z) with north (-z) = 0.
func _focus_yaw() -> float:
	var n := _focus_node()
	if n == null:
		return 0.0
	var fwd := -n.global_transform.basis.z
	return atan2(-fwd.x, -fwd.z)


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var v: Variant = (sys as Dictionary).get(peer_name)
		if v is Node and is_instance_valid(v):
			return v
	return null
