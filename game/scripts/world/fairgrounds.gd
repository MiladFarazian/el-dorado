extends Node3D
## THE LONE STAR FAIRGROUNDS (D-066) — the Eastside's first piece, off the end
## of Howdy Street. A Deco gate on Fair Drive, the Lone Spur wheel (a 54 m
## ring you can see from the grid's east streets), Tall Tom on his plinth, a
## midway of booths facing each other across a 40 m concourse, Deco lamps, the
## lots. Off-season: the booths are shuttered and the gate says when it opens.
## The satire is institutional — the fair's own signage — never the crowd.
##
## CONTRACT (house law): visual-only build, a literal seed, MultiMeshes with
## a custom AABB (D-059), colliders only on masses a car must not pass
## through (pylons, the wheel's legs, Tom's plinth, booths). Nothing in the
## smoke corridor x[174,212] z[424,576]. Registered in the atlas
## (data/world/atlas.json: district `fairgrounds`, places the Lone Spur and
## Tall Tom); the map draws from there.
const SEED := 616010
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")
const SKIN := preload("res://scripts/world/skinned_character.gd")
const FACTORY := preload("res://scripts/world/character_factory.gd")

# ---- the ground plan (world metres; north is -z) ----
const GATE_X := 846.0; const GATE_Z := 305.0          # the gate straddles Fair Drive
const MIDWAY_X := 900.0                               # concourse centreline
const BOOTH_W_X := 878.0; const BOOTH_E_X := 922.0    # the two booth rows
const BOOTH_Z0 := 150.0; const BOOTH_Z1 := 330.0; const BOOTH_PITCH := 10.0
const WHEEL := Vector3(960.0, 30.0, 250.0)            # hub
const WHEEL_R := 27.0
const TOM := Vector3(868.0, 0.0, 258.0)               # Tall Tom's plinth centre
const LOT := Rect2(832.0, 340.0, 156.0, 88.0)         # the parking sea

const STUCCO := Color(0.90, 0.86, 0.74)               # Deco cream
const TEAL := Color(0.16, 0.50, 0.52)                 # Deco accent
const STEEL := Color(0.24, 0.26, 0.28)
const GALV := Color(0.58, 0.61, 0.63)
const PAINT_WHITE := Color(0.88, 0.88, 0.86)
const PLY := Color(0.62, 0.50, 0.34)                  # booth plywood
const SHUTTER := Color(0.36, 0.38, 0.40)
const CANDY: Array[Color] = [Color(0.85, 0.20, 0.22), Color(0.98, 0.78, 0.20),
	Color(0.18, 0.52, 0.82), Color(0.92, 0.92, 0.90), Color(0.20, 0.66, 0.42)]

var _rng := RandomNumberGenerator.new()
var _mat_asphalt: Material
var _mat_concrete: Material
var _mesh_cache: Dictionary = {}
var _unit_box := BoxMesh.new()
# MultiMesh accumulators, one per archetype, flushed once.
var _white_xf: Array[Transform3D] = []      # lot paint
var _steel_xf: Array[Transform3D] = []      # rim, spokes, posts, legs
var _galv_xf: Array[Transform3D] = []       # fence posts
var _wire_xf: Array[Transform3D] = []       # fence mesh
var _stucco_xf: Array[Transform3D] = []     # Deco masses
var _teal_xf: Array[Transform3D] = []       # Deco bands
var _gondola_xf: Array[Transform3D] = []    # the wheel's cars (coloured)
var _gondola_col: Array[Color] = []
var _rimlight_xf: Array[Transform3D] = []   # emissive bulbs on the rim
var _ply_xf: Array[Transform3D] = []        # booth bodies
var _shutter_xf: Array[Transform3D] = []    # booth roll-downs
var _awning_xf: Array[Transform3D] = []     # striped awnings (coloured)
var _awning_col: Array[Color] = []
var _globe_xf: Array[Transform3D] = []      # lamp globes (emissive)
var _flag_xf: Array[Transform3D] = []       # pennants (coloured)
var _flag_col: Array[Color] = []


func build(city: Node3D) -> void:
	_rng.seed = SEED
	_unit_box.size = Vector3.ONE
	_mat_asphalt = city.get("mat_asphalt")
	_mat_concrete = city.get("mat_concrete")
	_grounds()
	_gate()
	_fence()
	_wheel()
	_tall_tom()
	_midway()
	_flush()


# ============================ 1. THE GROUNDS ================================
## Fair Drive (Howdy Street carried east, 14 m of asphalt to the gate), the
## concourse slab, the parking sea with its stall paint and lot lights.
func _grounds() -> void:
	_solid(Vector3(70.0, 0.08, 14.0), Vector3(812.0, -0.02, GATE_Z), _mat_asphalt)      # Fair Drive
	_solid(Vector3(150.0, 0.08, 220.0), Vector3(908.0, 0.0, 240.0), _mat_concrete)      # the concourse
	_solid(Vector3(LOT.size.x, 0.08, LOT.size.y),
		Vector3(LOT.position.x + LOT.size.x * 0.5, -0.01, LOT.position.y + LOT.size.y * 0.5), _mat_asphalt)
	var z := LOT.position.y + 8.0
	while z < LOT.end.y - 6.0:
		var x := LOT.position.x + 6.0
		while x < LOT.end.x - 6.0:
			_white_xf.append(_axf(Vector3(0.14, 0.02, 5.4), Vector3(x, 0.09, z)))
			x += 2.75
		z += 18.0
	for i in 6:
		_lot_light(Vector3(LOT.position.x + 14.0 + 26.0 * float(i), 0.0, LOT.position.y + 44.0))


func _lot_light(base: Vector3) -> void:
	_steel_xf.append(_axf(Vector3(0.28, 9.0, 0.28), base + Vector3(0, 4.5, 0)))
	_globe_xf.append(_axf(Vector3(1.6, 0.3, 0.6), base + Vector3(0, 9.1, 0)))


# ============================ 2. THE DECO GATE ==============================
## Two stepped pylons, a lintel, the name across it and the season's promise
## under it. Read from Fair Drive, so the signs face west.
func _gate() -> void:
	for side: float in [-1.0, 1.0]:
		var pz := GATE_Z + side * 11.0
		_stucco_xf.append(_axf(Vector3(5.0, 6.0, 5.0), Vector3(GATE_X, 3.0, pz)))
		_stucco_xf.append(_axf(Vector3(4.0, 5.0, 4.0), Vector3(GATE_X, 8.5, pz)))
		_stucco_xf.append(_axf(Vector3(3.0, 4.0, 3.0), Vector3(GATE_X, 13.0, pz)))
		_teal_xf.append(_axf(Vector3(5.2, 0.4, 5.2), Vector3(GATE_X, 6.1, pz)))
		_teal_xf.append(_axf(Vector3(4.2, 0.4, 4.2), Vector3(GATE_X, 11.1, pz)))
		_teal_xf.append(_axf(Vector3(3.4, 0.5, 3.4), Vector3(GATE_X, 15.2, pz)))
		_collider(Vector3(5.0, 15.5, 5.0), Vector3(GATE_X, 7.75, pz))
		_steel_xf.append(_axf(Vector3(0.16, 9.0, 0.16), Vector3(GATE_X + 4.0, 4.5, pz + side * 4.0)))
		_flag_xf.append(_axf(Vector3(0.08, 1.0, 1.8), Vector3(GATE_X + 4.0, 8.4, pz + side * 4.0 + 0.9)))
		_flag_col.append(CANDY[0] if side < 0.0 else CANDY[2])
	_stucco_xf.append(_axf(Vector3(1.6, 2.8, 24.0), Vector3(GATE_X, 12.6, GATE_Z)))    # the lintel
	_teal_xf.append(_axf(Vector3(1.8, 0.3, 24.2), Vector3(GATE_X, 14.15, GATE_Z)))
	_teal_xf.append(_axf(Vector3(1.8, 0.3, 24.2), Vector3(GATE_X, 11.05, GATE_Z)))
	_label("LONE STAR FAIRGROUNDS", Vector3(GATE_X - 0.85, 12.6, GATE_Z), 150, TEAL, 21.0, -PI * 0.5)
	_label("GROUNDS CLOSED  ·  STATE FAIR OPENS SEPT 26", Vector3(GATE_X - 0.85, 10.2, GATE_Z), 44,
		PAINT_WHITE, 19.0, -PI * 0.5)
	_label("24 DAYS OF FRIED  ·  TALL TOM SAYS HOWDY  ·  PARKING $40", Vector3(GATE_X + 0.85, 10.2, GATE_Z), 40,
		PAINT_WHITE, 19.0, PI * 0.5)


## Chain-link around the grounds, open at the gate.
func _fence() -> void:
	var x0 := 832.0; var x1 := 988.0; var z0 := 104.0; var z1 := 428.0
	_fence_run(Vector3(x0, 0, z0), Vector3(x1, 0, z0))
	_fence_run(Vector3(x1, 0, z0), Vector3(x1, 0, z1))
	_fence_run(Vector3(x1, 0, z1), Vector3(x0, 0, z1))
	_fence_run(Vector3(x0, 0, z1), Vector3(x0, 0, GATE_Z + 14.0))
	_fence_run(Vector3(x0, 0, GATE_Z - 14.0), Vector3(x0, 0, z0))


# ============================ 3. THE LONE SPUR ==============================
## A 54 m wheel in the y-z plane (its face toward downtown): two rims of 48
## segments, 16 spokes each, 24 upright gondolas in candy colours, bulbs on
## the outer rim, a hub, two A-frames a side. Legs and pads collide.
func _wheel() -> void:
	var seg := TAU * WHEEL_R / 48.0
	for side: float in [-1.0, 1.0]:
		var rx := WHEEL.x + side * 2.2
		for i in 48:
			var a := (float(i) + 0.5) * TAU / 48.0
			var rot := Basis(Vector3.RIGHT, -a)
			_steel_xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.55, seg + 0.1, 0.55)), _rim(rx, a)))
			if side > 0.0:
				_rimlight_xf.append(_axf(Vector3(0.45, 0.45, 0.45), _rim(rx + 0.6, a)))
		for i in 16:
			var a := float(i) * TAU / 16.0
			var rot := Basis(Vector3.RIGHT, -a)
			_steel_xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.3, 0.3, WHEEL_R - 1.0)),
				Vector3(rx, WHEEL.y, WHEEL.z) + Vector3(0, sin(a), cos(a)) * (WHEEL_R * 0.5)))
	for j in 24:
		var a := float(j) * TAU / 24.0
		var p := _rim(WHEEL.x, a)
		_steel_xf.append(_axf(Vector3(0.12, 1.5, 0.12), p + Vector3(0, -0.75, 0)))
		_gondola_xf.append(_axf(Vector3(2.4, 2.2, 2.4), p + Vector3(0, -2.6, 0)))
		_gondola_col.append(CANDY[j % CANDY.size()])
	_steel_xf.append(_axf(Vector3(6.0, 2.6, 2.6), WHEEL))                                      # the hub
	for side: float in [-1.0, 1.0]:
		for foot: float in [-1.0, 1.0]:
			var base := Vector3(WHEEL.x + side * 3.6, 0.0, WHEEL.z + foot * 21.0)
			_leg(base, WHEEL + Vector3(side * 3.4, 0, 0))
		_solid(Vector3(3.0, 0.5, 48.0), Vector3(WHEEL.x + side * 3.6, 0.25, WHEEL.z), _mat_concrete)
	_label("THE LONE SPUR", WHEEL + Vector3(-3.05, 0.0, 0.0), 40, PAINT_WHITE, 5.6, -PI * 0.5)


func _rim(x: float, a: float) -> Vector3:
	return Vector3(x, WHEEL.y + WHEEL_R * sin(a), WHEEL.z + WHEEL_R * cos(a))


## One steel leg from a footing to the hub, with a collider along it.
func _leg(base: Vector3, top: Vector3) -> void:
	var v := top - base
	var b := Basis.looking_at(v.normalized(), Vector3.RIGHT)
	var mid := (base + top) * 0.5
	_steel_xf.append(Transform3D(b * Basis.from_scale(Vector3(0.7, 0.7, v.length())), mid))
	_collider_b(Vector3(0.7, 0.7, v.length()), mid, b)


# ============================== 4. TALL TOM =================================
## The fair's 17 m greeter, built from the same skinned body as everyone else
## at scale 9.4 — a cowboy hat, a red western shirt, one arm up. He stands on
## a plinth that tells the truth about him (55 ft; burned twice; doesn't
## discuss it). Static: his joints are posed once and never animated.
func _tall_tom() -> void:
	_solid(Vector3(7.0, 1.2, 7.0), TOM + Vector3(0, 0.6, 0), _mat_concrete)
	_teal_xf.append(_axf(Vector3(7.2, 0.3, 7.2), TOM + Vector3(0, 1.2, 0)))
	var cfg: Dictionary = FACTORY.book_config().duplicate()
	cfg["scale"] = 9.4
	cfg["hat"] = FACTORY.Hat.COWBOY
	cfg["hat_color"] = Color(0.86, 0.80, 0.66)
	cfg["shirt"] = Color(0.74, 0.16, 0.18)
	cfg["accent"] = Color(0.95, 0.94, 0.90)
	cfg["pants"] = Color(0.20, 0.27, 0.44)
	cfg["belt_color"] = Color(0.30, 0.18, 0.10)
	cfg["asym"] = 0.0
	var tom := Node3D.new()
	tom.name = "TallTom"
	tom.position = TOM + Vector3(0, 1.35, 0)
	tom.rotation.y = PI * 0.5                    # faces west, down Fair Drive
	add_child(tom)
	var rig := SKIN.build(tom, cfg, 0.0)
	if not rig.is_empty():
		(rig["sh_1"] as Node3D).rotation = Vector3(2.55, 0.0, 0.55)   # the wave
		(rig["el_1"] as Node3D).rotation.x = 0.4
		(rig["sh_0"] as Node3D).rotation = Vector3(0.35, 0.0, -0.62)  # hand on the hip
		(rig["el_0"] as Node3D).rotation.x = 1.95
		(rig["head"] as Node3D).rotation.x = -0.06
	# Boot census line, like every layer's: he was "missing" once because the
	# fair_gate vantage's 36-degree field of view stopped short of him.
	var vis: Node3D = rig.get("vis")
	if vis != null:
		print("TALL TOM: %.0f m tall at %s" % [1.78 * vis.scale.y, vis.global_position])
	_collider(Vector3(3.6, 17.0, 3.6), TOM + Vector3(0, 9.85, 0))
	_label("TALL TOM", TOM + Vector3(-3.55, 0.85, 0.0), 40, TEAL, 5.4, -PI * 0.5)
	_label("55 FT  ·  EST. 1952  ·  BURNED TWICE  ·  DOESN'T DISCUSS IT", TOM + Vector3(-3.55, 0.42, 0.0), 18,
		PAINT_WHITE, 6.2, -PI * 0.5)


# ============================== 5. THE MIDWAY ===============================
const BOOTH_NAMES: Array[String] = ["FRIED EVERYTHING", "CORNY DOGS · ORIGINAL SINCE WHENEVER",
	"BEER GARDEN · 21+ · $14", "RING TOSS · WIN A HAT", "TALL TOM SOUVENIRS", "DEEP-FRIED BUTTER™",
	"FUNNEL CAKE · NO REFUNDS", "GUESS YOUR CREDIT SCORE", "AIRBRUSH T-SHIRTS", "LEMONADE $9",
	"SNAKE HOUSE", "TEXCHANGE KIDS' ZONE", "OVERFLOW PRAYER TENT", "PIONEER VISION MODEL HOME TOUR",
	"GIGASTEAD CAREER TENT", "LONGHORN WRECKER · OFFICIAL TOWING PARTNER"]

## Two rows of shuttered booths facing each other across the concourse, a
## striped awning each, a name over the first eight a side, Deco lamps down
## the centreline.
func _midway() -> void:
	var n := 0
	for row: float in [-1.0, 1.0]:                      # -1 west row faces east
		var bx := BOOTH_W_X if row < 0.0 else BOOTH_E_X
		var z := BOOTH_Z0
		var k := 0
		while z <= BOOTH_Z1:
			var face := bx + row * 2.4                   # the concourse-facing wall
			_ply_xf.append(_axf(Vector3(4.6, 2.7, 3.4), Vector3(bx, 1.35, z)))
			_shutter_xf.append(_axf(Vector3(0.12, 1.6, 3.0), Vector3(face, 1.7, z)))
			_awning_xf.append(Transform3D(Basis(Vector3.FORWARD, row * 0.32) * Basis.from_scale(Vector3(2.4, 0.14, 4.6)),
				Vector3(face + row * 1.0, 3.05, z)))
			_awning_col.append(CANDY[n % CANDY.size()])
			_collider(Vector3(4.6, 2.7, 3.4), Vector3(bx, 1.35, z))
			if k < 8:
				var yaw := PI * 0.5 if row < 0.0 else -PI * 0.5
				_label(BOOTH_NAMES[(k + (0 if row < 0.0 else 8)) % BOOTH_NAMES.size()],
					Vector3(face + row * 0.08, 2.35, z), 22, PAINT_WHITE, 3.2, yaw)
			n += 1
			k += 1
			z += BOOTH_PITCH
	var lz := BOOTH_Z0 - 4.0
	while lz <= BOOTH_Z1 + 4.0:
		_steel_xf.append(_axf(Vector3(0.22, 6.0, 0.22), Vector3(MIDWAY_X, 3.0, lz)))
		_teal_xf.append(_axf(Vector3(0.9, 0.25, 0.9), Vector3(MIDWAY_X, 6.1, lz)))
		_globe_xf.append(_axf(Vector3(0.9, 0.9, 0.9), Vector3(MIDWAY_X, 6.75, lz)))
		lz += 20.0


# ================================ PLUMBING ==================================
## SHADOW POLICY (D-028): massing casts; paint, bulbs, globes, flags and the
## alpha fence do not.
func _flush() -> void:
	_mm(_white_xf, [], _flat(PAINT_WHITE, 0.85, true), _unit_box, "FgPaint", false)
	_mm(_steel_xf, [], _flat(STEEL, 0.55), _unit_box, "FgSteel", true)
	var galv := _flat(GALV, 0.45)
	galv.metallic = 0.4
	_mm(_galv_xf, [], galv, _unit_box, "FgGalv", true)
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.45, 0.47, 0.48, 0.4)
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire.roughness = 0.6
	wire.metallic = 0.3
	wire.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mm(_wire_xf, [], wire, _unit_box, "FgFenceMesh", false)
	_mm(_stucco_xf, [], _flat(STUCCO, 0.85), _unit_box, "FgStucco", true)
	_mm(_teal_xf, [], _flat(TEAL, 0.6), _unit_box, "FgTeal", true)
	_mm(_gondola_xf, _gondola_col, _vtx_mat(0.5), _unit_box, "FgGondolas", true)
	var bulb := _flat(Color(0.98, 0.85, 0.55), 0.5)
	bulb.emission_enabled = true
	bulb.emission = Color(0.98, 0.85, 0.55)
	bulb.emission_energy_multiplier = 1.0
	_mm(_rimlight_xf, [], bulb, _unit_box, "FgRimBulbs", false)
	_mm(_ply_xf, [], _flat(PLY, 0.9), _unit_box, "FgBooths", true)
	_mm(_shutter_xf, [], _flat(SHUTTER, 0.5), _unit_box, "FgShutters", true)
	_mm(_awning_xf, _awning_col, _vtx_mat(0.8), _unit_box, "FgAwnings", true)
	var globe := _flat(Color(0.95, 0.93, 0.85), 0.6)
	globe.emission_enabled = true
	globe.emission = Color(0.95, 0.93, 0.85)
	globe.emission_energy_multiplier = 1.0
	_mm(_globe_xf, [], globe, MESH_KIT.sphere(0.5, 6, 10), "FgGlobes", false)
	_mm(_flag_xf, _flag_col, _vtx_mat(0.8), _unit_box, "FgFlags", false)


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
	_collider_b(size, origin, Basis.IDENTITY)


func _collider_b(size: Vector3, origin: Vector3, basis: Basis) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis, origin)
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


func _flat(col: Color, rough: float, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
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


## One MultiMesh per archetype. The AABB is set from the instance origins
## (D-059: a script-built MultiMesh can carry an EMPTY one and draw nothing);
## instance colours go in linear (they reach the shader raw).
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


func _fence_run(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var run_len := d.length()
	var dir := d / run_len
	var yaw := atan2(dir.x, dir.z) + PI * 0.5
	var mid := (a + b) * 0.5
	var rot := Basis(Vector3.UP, yaw)
	_wire_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 2.4, 0.05)), mid + Vector3(0, 1.25, 0)))
	for w in 3:
		_wire_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 0.05, 0.05)),
			mid + Vector3(0, 2.62 + 0.14 * float(w), 0)))
	var n := int(run_len / 8.0)
	for i in n + 1:
		var t := float(i) / float(maxi(n, 1))
		_galv_xf.append(_axf(Vector3(0.14, 2.9, 0.14), a.lerp(b, t) + Vector3(0, 1.45, 0)))
	_collider_b(Vector3(run_len, 2.9, 0.15), mid + Vector3(0, 1.45, 0), rot)
