extends Node3D
## HARVEST HILLS™ — A PIONEER VISION DEVELOPMENT (D-066). The slab-farm
## frontier at the map's north-west corner: Pioneer Vision Parkway north off
## the I-3 frontage road, a monument sign, a billboard bigger than any house,
## mud lanes on a grid, and the lots in every stage a developer sells from —
## survey stakes, bare slabs, framing lumber, wrapped boxes, five finished
## model homes with the flags out — plus the sales trailer and its two
## porta-potties. "The map's visibly growing edge." The satire is the
## developer's own copy; nobody who would live here is in it.
##
## CONTRACT (house law): visual-only build, a literal seed, MultiMeshes with
## a custom AABB (D-059), colliders on slabs, houses, the trailer and the
## sign piers. Nothing in the smoke corridor x[174,212] z[424,576].
## Registered in the atlas (district `harvest`, the sales office).
const SEED := 616020
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")

const PARKWAY_X := -800.0
const MONUMENT_Z := -452.0
const LANES_Z: Array[float] = [-500.0, -620.0, -740.0]     # mud lanes east-west
const LANES_X: Array[float] = [-900.0, -800.0, -720.0]     # mud lanes north-south
const LANE_X0 := -964.0; const LANE_X1 := -656.0
const LANE_Z0 := -470.0; const LANE_Z1 := -846.0
const LOT_PITCH := 24.0
const BILLBOARD := Vector3(-790.0, 0.0, -482.0)
const TRAILER := Vector3(-836.0, 0.0, -470.0)

const LUMBER := Color(0.78, 0.66, 0.46)
const WRAP := Color(0.82, 0.86, 0.80)
const MUD := Color(0.40, 0.33, 0.24)
const BRICK := Color(0.58, 0.36, 0.28)
const SHINGLE := Color(0.30, 0.30, 0.32)
const STEEL := Color(0.24, 0.26, 0.28)
const PAINT_WHITE := Color(0.90, 0.90, 0.88)
const PV_GREEN := Color(0.18, 0.52, 0.30)                  # the developer's green
const LAWN := Color(0.32, 0.50, 0.22)

var _rng := RandomNumberGenerator.new()
var _mat_asphalt: Material
var _mat_concrete: Material
var _mat_hazard: Material
var _mesh_cache: Dictionary = {}
var _unit_box := BoxMesh.new()
var _lumber_xf: Array[Transform3D] = []; var _lumber_col: Array[Color] = []
var _mud_xf: Array[Transform3D] = []
var _stake_xf: Array[Transform3D] = []
var _flag_xf: Array[Transform3D] = []; var _flag_col: Array[Color] = []
var _steel_xf: Array[Transform3D] = []
var _white_xf: Array[Transform3D] = []      # sign faces, trailer, PVC stubs (emissive a touch)
var _roof_xf: Array[Transform3D] = []       # model-home hip roofs (taper mesh)
var _glass_xf: Array[Transform3D] = []
var _lawn_xf: Array[Transform3D] = []
var _porta_xf: Array[Transform3D] = []; var _porta_door_xf: Array[Transform3D] = []
var _flood_xf: Array[Transform3D] = []
var _puddle_xf: Array[Transform3D] = []
var _barrel_xf: Array[Transform3D] = []
var _taken: Array[Rect2] = []               # footprints already used (lots avoid them)


func build(city: Node3D) -> void:
	_rng.seed = SEED
	_unit_box.size = Vector3.ONE
	_mat_asphalt = city.get("mat_asphalt")
	_mat_concrete = city.get("mat_concrete")
	_mat_hazard = city.get("mat_hazard")
	_roads()
	_billboard()
	_sales()
	_lots()
	_flush()


# ============================ 1. ROADS AND THE ENTRY ========================
## The parkway is real asphalt to the monument; past it the developer's
## "streets" are graded mud, seven metres wide, with the puddles they earn.
func _roads() -> void:
	_solid(Vector3(10.0, 0.08, 434.0), Vector3(PARKWAY_X, -0.02, -36.0 - 217.0), _mat_asphalt)
	for z in LANES_Z:
		_mud_xf.append(_axf(Vector3(LANE_X1 - LANE_X0, 0.02, 7.0), Vector3((LANE_X0 + LANE_X1) * 0.5, 0.005, z)))
	for x in LANES_X:
		_mud_xf.append(_axf(Vector3(7.0, 0.02, LANE_Z0 - LANE_Z1), Vector3(x, 0.006, (LANE_Z0 + LANE_Z1) * 0.5)))
	for i in 10:
		var on_ew := _rng.randf() < 0.6
		var p := Vector3(_rng.randf_range(LANE_X0 + 10.0, LANE_X1 - 10.0), 0.012,
			LANES_Z[_rng.randi_range(0, 2)] + _rng.randf_range(-2.0, 2.0)) if on_ew \
			else Vector3(LANES_X[_rng.randi_range(0, 2)] + _rng.randf_range(-2.0, 2.0), 0.012,
				_rng.randf_range(LANE_Z1 + 10.0, LANE_Z0 - 10.0))
		_puddle_xf.append(Transform3D(Basis(Vector3.UP, _rng.randf_range(0.0, PI))
			* Basis.from_scale(Vector3(_rng.randf_range(2.0, 4.5), 1.0, _rng.randf_range(1.2, 2.4))), p))
	# the monument: two brick piers, a low wall, the developer's name on it
	for side: float in [-1.0, 1.0]:
		_solid(Vector3(1.4, 2.4, 1.4), Vector3(PARKWAY_X + side * 8.5, 1.2, MONUMENT_Z), _flat(BRICK, 0.9))
		_white_xf.append(_axf(Vector3(1.7, 0.2, 1.7), Vector3(PARKWAY_X + side * 8.5, 2.5, MONUMENT_Z)))
	_solid(Vector3(15.6, 1.7, 0.5), Vector3(PARKWAY_X, 0.85, MONUMENT_Z), _flat(BRICK, 0.9))
	_white_xf.append(_axf(Vector3(15.8, 0.16, 0.7), Vector3(PARKWAY_X, 1.78, MONUMENT_Z)))
	_label("HARVEST HILLS", Vector3(PARKWAY_X, 1.15, MONUMENT_Z + 0.27), 60, PAINT_WHITE, 12.0, 0.0)
	_label("A PIONEER VISION DEVELOPMENT  ·  FROM THE $400s", Vector3(PARKWAY_X, 0.55, MONUMENT_Z + 0.27), 20,
		PAINT_WHITE, 12.0, 0.0)
	_taken.append(Rect2(PARKWAY_X - 10.0, MONUMENT_Z - 6.0, 20.0, 12.0))
	# orange barrels where the asphalt gives up
	for i in 6:
		_barrel_xf.append(_axf(Vector3.ONE, Vector3(PARKWAY_X - 5.5 + 2.2 * float(i), 0.45, MONUMENT_Z - 14.0)))


# ============================== 2. THE BILLBOARD ============================
## Faces south, so the parkway reads it the whole way in. Lit from a catwalk.
func _billboard() -> void:
	for side: float in [-1.0, 1.0]:
		_steel_xf.append(_axf(Vector3(0.6, 15.0, 0.6), BILLBOARD + Vector3(side * 9.0, 7.5, 0.0)))
	_steel_xf.append(_axf(Vector3(26.0, 8.4, 0.5), BILLBOARD + Vector3(0, 13.0, -0.3)))
	_white_xf.append(_axf(Vector3(25.4, 7.8, 0.08), BILLBOARD + Vector3(0, 13.0, 0.0)))
	_steel_xf.append(_axf(Vector3(26.0, 0.12, 1.4), BILLBOARD + Vector3(0, 8.6, 0.8)))
	for i in 3:
		_flood_xf.append(_axf(Vector3(0.9, 0.25, 0.5), BILLBOARD + Vector3(-8.0 + 8.0 * float(i), 8.85, 1.2)))
	_label("HARVEST HILLS™", BILLBOARD + Vector3(0, 15.6, 0.1), 200, PV_GREEN, 22.0, 0.0)
	_label("\"WHERE TEXAS IS GOING\"™", BILLBOARD + Vector3(0, 13.2, 0.1), 80, Color(0.2, 0.2, 0.22), 22.0, 0.0)
	_label("FROM THE $400s   ·   A PIONEER VISION DEVELOPMENT   ·   PHASE 3 SOLD OUT*", BILLBOARD + Vector3(0, 11.2, 0.1), 40,
		Color(0.2, 0.2, 0.22), 23.0, 0.0)
	_label("*phase 3 does not exist", BILLBOARD + Vector3(9.5, 9.7, 0.1), 12, Color(0.45, 0.45, 0.47), 5.0, 0.0)
	_collider(Vector3(26.0, 17.5, 1.2), BILLBOARD + Vector3(0, 8.75, 0.0))
	_taken.append(Rect2(BILLBOARD.x - 14.0, BILLBOARD.z - 4.0, 28.0, 8.0))


# ============================== 3. THE SALES TRAILER ========================
## A white double-wide on blocks, the roof sign, a flag, two porta-potties,
## a lumber yard and a dumpster. The fine print is on the trailer.
func _sales() -> void:
	_solid(Vector3(12.0, 3.2, 3.6), TRAILER + Vector3(0, 2.0, 0), _flat(Color(0.92, 0.92, 0.90), 0.7))
	_steel_xf.append(_axf(Vector3(12.2, 0.4, 3.8), TRAILER + Vector3(0, 0.2, 0)))
	for i in 3:
		_steel_xf.append(_axf(Vector3(1.4, 0.18, 0.4), TRAILER + Vector3(-3.0, 0.15 + 0.3 * float(i), 2.2 - 0.4 * float(i))))
	_white_xf.append(_axf(Vector3(10.0, 1.6, 0.12), TRAILER + Vector3(0, 4.5, 0.0)))
	_label("HARVEST HILLS™  SALES CENTER  ·  MODELS OPEN →", TRAILER + Vector3(0, 4.5, 0.1), 40, PV_GREEN, 9.4, 0.0)
	_label("OPEN 7 DAYS  ·  FINANCING AVAILABLE™  ·  FROM THE $400s*", TRAILER + Vector3(0, 2.9, 1.85), 24,
		PV_GREEN, 10.0, 0.0)
	_label("*lot premium, HOA, MUD tax, PID, wrap fee and sunshine fee not included", TRAILER + Vector3(0, 1.1, 1.85), 12,
		Color(0.35, 0.35, 0.37), 9.0, 0.0)
	_steel_xf.append(_axf(Vector3(0.1, 8.0, 0.1), TRAILER + Vector3(7.5, 4.0, 2.5)))
	_flag_xf.append(_axf(Vector3(2.4, 1.4, 0.06), TRAILER + Vector3(8.7, 7.2, 2.5)))
	_flag_col.append(PV_GREEN)
	for i in 2:
		var p := TRAILER + Vector3(8.6 + 1.6 * float(i), 1.15, -1.4)
		_porta_xf.append(_axf(Vector3(1.2, 2.3, 1.2), p))
		_porta_door_xf.append(_axf(Vector3(1.0, 2.0, 0.06), p + Vector3(0, -0.1, 0.62)))
	for i in 6:
		var p := TRAILER + Vector3(-11.0 - 2.0 * float(i % 3), 0.6, 4.5 + 1.6 * float(i / 3))
		_lumber(Vector3(4.0, 1.2, 1.2), p)
	_solid(Vector3(6.0, 1.5, 2.4), TRAILER + Vector3(-12.0, 0.75, -3.0), _flat(Color(0.22, 0.38, 0.24), 0.7))
	_taken.append(Rect2(TRAILER.x - 22.0, TRAILER.z - 8.0, 34.0, 16.0))


# ============================== 4. THE LOTS =================================
## Every stage the developer sells from, on both sides of every mud lane.
## The five model homes stand on the first lane's south side, nearest the
## entry, where the drive-in sees them first.
func _lots() -> void:
	for x in LANES_X:
		_taken.append(Rect2(x - 6.0, LANE_Z1, 12.0, LANE_Z0 - LANE_Z1))
	var models := 0
	for lz in LANES_Z:
		for side: float in [-1.0, 1.0]:
			var cz := lz + side * 19.0
			var x := LANE_X0 + 16.0
			while x < LANE_X1 - 12.0:
				var fp := Rect2(x - 9.0, cz - 8.0, 18.0, 16.0)
				if _clear(fp):
					var c := Vector3(x, 0.0, cz)
					var roll := _rng.randf()
					if lz == LANES_Z[0] and side > 0.0 and models < 5 and x > -960.0 and x < -830.0:
						_model_home(c, -side)
						models += 1
					elif roll < 0.28:
						_frame_house(c)
					elif roll < 0.38:
						_wrapped_house(c, -side)
					elif roll < 0.60:
						_slab(c)
					else:
						_stakes(c)
					_taken.append(fp)
				x += LOT_PITCH


func _clear(fp: Rect2) -> bool:
	for t in _taken:
		if t.intersects(fp):
			return false
	return true


func _lumber(size: Vector3, pos: Vector3, rot := Basis.IDENTITY) -> void:
	_lumber_xf.append(Transform3D(rot * Basis.from_scale(size), pos))
	_lumber_col.append(LUMBER * _rng.randf_range(0.90, 1.08))


## Studs at 0.61 m on plates, four walls, trusses over — a house as a drawing.
func _frame_house(c: Vector3) -> void:
	_solid(Vector3(12.0, 0.2, 10.0), c + Vector3(0, 0.1, 0), _mat_concrete)
	for wall in 4:
		var along_x := wall < 2
		var off := -1.0 if wall % 2 == 0 else 1.0
		var length := 12.0 if along_x else 10.0
		var centre := c + (Vector3(0, 0, off * 5.0) if along_x else Vector3(off * 6.0, 0, 0))
		var plate := Vector3(length, 0.09, 0.09) if along_x else Vector3(0.09, 0.09, length)
		_lumber(plate, centre + Vector3(0, 0.25, 0))
		_lumber(plate, centre + Vector3(0, 2.95, 0))
		var n := int(length / 0.61)
		for i in n + 1:
			var t := -length * 0.5 + float(i) * 0.61
			var p := centre + (Vector3(t, 0, 0) if along_x else Vector3(0, 0, t))
			_lumber(Vector3(0.04, 2.6, 0.09) if along_x else Vector3(0.09, 2.6, 0.04), p + Vector3(0, 1.6, 0))
	_trusses(c, 3.0)


func _trusses(c: Vector3, top: float) -> void:
	var x := -5.8
	while x <= 5.8:
		for s: float in [-1.0, 1.0]:
			_lumber(Vector3(0.04, 0.2, 5.4), c + Vector3(x, top + 1.0, s * 2.5), Basis(Vector3.RIGHT, s * 0.38))
		x += 0.61
	_lumber(Vector3(0.04, 0.2, 12.0), c + Vector3(0, top + 1.95, 0))


func _wrapped_house(c: Vector3, facing: float) -> void:
	_solid(Vector3(12.0, 2.8, 10.0), c + Vector3(0, 1.4, 0), _flat(WRAP, 0.9))
	_trusses(c, 2.8)
	_label("PIONEER VISION HOMEWRAP  ·  PIONEER VISION HOMEWRAP  ·  PIONEER VISION HOMEWRAP",
		c + Vector3(0, 1.5, facing * 5.06), 16, PV_GREEN, 11.6, 0.0 if facing > 0.0 else PI)


func _slab(c: Vector3) -> void:
	_solid(Vector3(12.0, 0.2, 10.0), c + Vector3(0, 0.1, 0), _mat_concrete)
	for i in 3:
		_white_xf.append(_axf(Vector3(0.1, 0.9, 0.1), c + Vector3(-3.0 + 3.0 * float(i), 0.65, 1.5 - float(i))))


func _stakes(c: Vector3) -> void:
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var p := c + Vector3(sx * 7.5, 0.5, sz * 6.5)
			_stake_xf.append(_axf(Vector3(0.05, 1.0, 0.05), p))
			_flag_xf.append(_axf(Vector3(0.35, 0.12, 0.02), p + Vector3(0.17, 0.44, 0)))
			_flag_col.append(Color(0.95, 0.45, 0.10))


## A finished model home: brick, a hip roof, windows and a door on the lane
## side, a porch, a lawn, a drive, three pennants and the A-frame sign.
func _model_home(c: Vector3, facing: float) -> void:
	_lawn_xf.append(_axf(Vector3(17.0, 0.02, 15.0), c + Vector3(0, 0.01, 0)))
	_solid(Vector3(12.0, 4.6, 10.0), c + Vector3(0, 2.3, 0), _flat(BRICK, 0.9))
	_roof_xf.append(_axf(Vector3.ONE, c + Vector3(0, 4.6 + 1.2, 0)))
	var fz := c.z + facing * 5.04
	for i in 3:
		var wx := c.x - 4.0 + 4.0 * float(i)
		if i == 1:
			_steel_xf.append(_axf(Vector3(1.0, 2.1, 0.08), Vector3(wx, 1.05, fz)))
		else:
			_glass_xf.append(_axf(Vector3(1.5, 1.4, 0.06), Vector3(wx, 2.4, fz)))
	_solid(Vector3(5.0, 0.3, 2.6), Vector3(c.x, 0.15, c.z + facing * 6.3), _mat_concrete)
	for sx: float in [-1.0, 1.0]:
		_white_xf.append(_axf(Vector3(0.2, 3.0, 0.2), Vector3(c.x + sx * 2.3, 1.5, c.z + facing * 7.4)))
	_white_xf.append(_axf(Vector3(5.4, 0.2, 3.0), Vector3(c.x, 3.1, c.z + facing * 6.3)))
	_solid(Vector3(3.0, 0.03, 8.0), Vector3(c.x + 5.0, 0.015, c.z + facing * 10.0), _mat_concrete)
	var pole := Vector3(c.x - 7.5, 0.0, c.z + facing * 7.0)
	_steel_xf.append(_axf(Vector3(0.08, 5.0, 0.08), pole + Vector3(0, 2.5, 0)))
	var cols: Array[Color] = [PV_GREEN, Color(0.95, 0.95, 0.92), Color(0.95, 0.45, 0.10)]
	for i in 3:
		_flag_xf.append(_axf(Vector3(1.1, 0.5, 0.04), pole + Vector3(0.6, 4.6 - 0.7 * float(i), 0)))
		_flag_col.append(cols[i])
	var sign := Vector3(c.x + 2.0, 0.0, c.z + facing * 13.0)
	_white_xf.append(_axf(Vector3(1.3, 0.8, 0.06), sign + Vector3(0, 1.0, 0)))
	_stake_xf.append(_axf(Vector3(0.05, 1.4, 0.05), sign + Vector3(-0.5, 0.7, 0)))
	_stake_xf.append(_axf(Vector3(0.05, 1.4, 0.05), sign + Vector3(0.5, 0.7, 0)))
	_label("MODEL OPEN", sign + Vector3(0, 1.0, facing * 0.05), 22, PV_GREEN, 1.2, 0.0 if facing > 0.0 else PI)


# ================================ PLUMBING ==================================
func _flush() -> void:
	_mm(_lumber_xf, _lumber_col, _vtx_mat(0.9), _unit_box, "HhLumber", true)
	_mm(_mud_xf, [], _flat(MUD, 0.95), _unit_box, "HhMud", false)
	_mm(_stake_xf, [], _flat(LUMBER, 0.9), _unit_box, "HhStakes", false)
	_mm(_flag_xf, _flag_col, _vtx_mat(0.8), _unit_box, "HhFlags", false)
	_mm(_steel_xf, [], _flat(STEEL, 0.55), _unit_box, "HhSteel", true)
	var white := _flat(PAINT_WHITE, 0.7)
	white.emission_enabled = true
	white.emission = PAINT_WHITE
	white.emission_energy_multiplier = 0.25
	_mm(_white_xf, [], white, _unit_box, "HhWhite", true)
	_mm(_roof_xf, [], _flat(SHINGLE, 0.9), MESH_KIT.taper(Vector3(13.4, 2.4, 11.4), Vector2(5.0, 3.0)), "HhRoofs", true)
	var glass := _flat(Color(0.20, 0.26, 0.30), 0.15)
	glass.metallic = 0.4
	_mm(_glass_xf, [], glass, _unit_box, "HhGlass", false)
	_mm(_lawn_xf, [], _flat(LAWN, 0.95), _unit_box, "HhLawns", false)
	_mm(_porta_xf, [], _flat(Color(0.12, 0.3, 0.55), 0.6), _unit_box, "HhPorta", true)
	_mm(_porta_door_xf, [], _flat(Color(0.09, 0.22, 0.4), 0.6), _unit_box, "HhPortaDoors", false)
	var flood := _flat(Color(0.95, 0.93, 0.85), 0.5)
	flood.emission_enabled = true
	flood.emission = Color(0.95, 0.93, 0.85)
	flood.emission_energy_multiplier = 1.3
	_mm(_flood_xf, [], flood, _unit_box, "HhFloodHeads", false)
	var wet := _flat(Color(0.18, 0.16, 0.13), 0.08)
	wet.metallic = 0.2
	_mm(_puddle_xf, [], wet, MESH_KIT.prism(1.0, 0.02, 12), "HhPuddles", false)
	_mm(_barrel_xf, [], _mat_hazard if _mat_hazard != null else _flat(Color(0.95, 0.45, 0.10), 0.6),
		MESH_KIT.prism(0.3, 0.9, 10), "HhBarrels", true)


func _solid(size: Vector3, origin: Vector3, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis.IDENTITY, origin)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_box(size)
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _collider(size: Vector3, origin: Vector3) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis.IDENTITY, origin)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _axf(size: Vector3, pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)


func _label(text: String, pos: Vector3, fsize: int, col: Color, max_w: float,
		yaw: float, style: int = SIGN.FLAT, max_h: float = 0.0) -> void:
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	lbl.rotation.y = yaw
	add_child(lbl)


func _flat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


func _vtx_mat(rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	return m


func _shared_box(size: Vector3) -> BoxMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _mesh_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_mesh_cache[key] = bm
	return _mesh_cache[key]


## One MultiMesh per archetype, AABB from the instance origins (D-059),
## instance colours in linear (they reach the shader raw).
func _mm(xf: Array[Transform3D], cols: Array[Color], mat: Material,
		mesh: Mesh, label: String, casts: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	var bounds := AABB(xf[0].origin, Vector3.ZERO)
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		bounds = bounds.expand(xf[i].origin)
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i].srgb_to_linear())
	mm.custom_aabb = bounds.grow(30.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
