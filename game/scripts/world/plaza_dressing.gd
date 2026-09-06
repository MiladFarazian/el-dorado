extends Node3D
## PLAZA + PARKING-LOT DRESSING (M15) — downtown's block interiors. Tower
## blocks get corporate plaza furniture (planter rings around each tower,
## flagpoles, seat-height plaza walls, bike racks); the flat parking-lot
## blocks get what real lots have (stall paint, curb stops, corner light
## poles, a pay hut). Visual-only by contract: zero collision, zero touches
## to any seeded stream — own RNG, literal seed. Loaded by greybox_city's
## EXTRA_LAYERS list; build-time only, no per-frame cost.

const SIGN := preload("res://scripts/world/sign_kit.gd")

const SEED := 246810
const SLAB_TOP := 0.2
const BLOCK_ORIGIN := Vector2(150.0, 90.0)
const BLOCK_PITCH := 86.0
const GRID_COLS := 8
const GRID_ROWS := 6
const GIANT_CELL := Vector2i(3, 2)

var _unit := BoxMesh.new()


func build(city: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	_unit.size = Vector3.ONE
	var lots: Array[Vector2i] = []
	if city.has_method("get_lot_cells"):
		for v: Variant in city.call("get_lot_cells"):
			if v is Vector2i:
				lots.append(v)
	var tops: Array[Vector4] = []
	if city.has_method("get_tower_tops"):
		for t: Variant in city.call("get_tower_tops"):
			if t is Vector4:
				tops.append(t)
	_dress_lots(lots, rng)
	_dress_plazas(lots, tops, rng)


# ============================== PARKING LOTS =================================
func _dress_lots(lots: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	var stalls: Array[Transform3D] = []
	var stops: Array[Transform3D] = []
	var poles: Array[Transform3D] = []
	var heads: Array[Transform3D] = []
	for cell in lots:
		var cx := BLOCK_ORIGIN.x + BLOCK_PITCH * float(cell.x)
		var cz := BLOCK_ORIGIN.y + BLOCK_PITCH * float(cell.y)
		# Two double rows of stalls (matching the junker rows at z ±9): white
		# dividers every 3 m, curb stops at the head of each stall.
		for rz: float in [-9.0, 9.0]:
			var x := cx - 21.0
			while x <= cx + 21.0:
				stalls.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.12, 0.015, 5.4)),
					Vector3(x, SLAB_TOP + 0.008, cz + rz)))
				if x <= cx + 18.5:
					stops.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(1.8, 0.14, 0.22)),
						Vector3(x + 1.5, SLAB_TOP + 0.07,
							cz + rz + (2.4 if rz > 0.0 else -2.4))))
				x += 3.0
		# Corner light poles (taller + plainer than the street cobras).
		for corner: Vector2 in [Vector2(-24, -24), Vector2(24, -24),
				Vector2(24, 24), Vector2(-24, 24)]:
			var base := Vector3(cx + corner.x, SLAB_TOP, cz + corner.y)
			poles.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.28, 8.0, 0.28)),
				base + Vector3(0, 4.0, 0)))
			heads.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.5, 0.28, 0.5)),
				base + Vector3(0, 8.1, 0)))
		# The pay hut, jauntily off-square near one entrance.
		var hut := Vector3(cx - 24.0, SLAB_TOP + 1.15, cz + rng.randf_range(-3.0, 3.0))
		var yaw := rng.randf_range(-0.12, 0.12)
		_solo(Vector3(2.0, 2.3, 2.0), hut, Color(0.82, 0.78, 0.68), 0.9, yaw)
		_solo(Vector3(2.5, 0.22, 2.5), hut + Vector3(0, 1.35, 0), Color(0.35, 0.33, 0.3), 0.9, yaw)
		# M22 FIT — the worst overflow in the audit. This was one 34 pt line of
		# 36 characters at pixel_size 0.01: **6.85 m of text hanging in clear
		# air beside a 2.0 m shed, 342 % of the thing it belongs to**, with no
		# backer behind it. It is now a real A-frame rate board bolted to the
		# hut's +X face: a panel, a rate in big money-green figures, and the
		# terms underneath in the small print they are always in.
		# The plate's thin axis is its local Z, so it has to be spun a quarter
		# turn to face +X off the hut (plus the hut's own jitter).
		var board := Vector3(1.72, 1.02, 0.06)
		var bpos := hut + Vector3(1.06, 0.30, 0)
		var byaw := yaw + PI * 0.5
		_solo(board, bpos, Color(0.14, 0.15, 0.16), 0.85, byaw)
		_solo(Vector3(board.x + 0.10, board.y + 0.10, 0.04),
			bpos - Vector3(0.05, 0, 0), Color(0.62, 0.60, 0.55), 0.8, byaw)
		for line: Array in [["PARKING $12", 0.22, 0.42, Color(0.55, 0.92, 0.55),
					SIGN.FASCIA],
				["EVENT PRICING", -0.16, 0.22, Color(0.93, 0.91, 0.84),
					SIGN.STENCIL],
				["WHENEVER", -0.38, 0.20, Color(0.93, 0.91, 0.84),
					SIGN.STENCIL]]:
			var sign := SIGN.make(str(line[0]), int(line[4]), line[3] as Color,
				board.x * 0.90, float(line[2]), 120)
			sign.position = bpos + Vector3(0.05, float(line[1]), 0)
			# D-016: the board hangs off the hut's +X face, so the readable
			# face has to point +X. -PI/2 aimed it back into the hut and showed
			# the mirrored reverse to the lot.
			sign.rotation.y = byaw
			add_child(sign)
	# SHADOW POLICY (D-028). Stall dividers are 15 mm of paint on the lot slab.
	# Curb stops KEEP theirs: 224 concrete blocks lying loose on an otherwise
	# empty apron, and the strip of shade under each one is the only thing that
	# grounds them — without it they read as more paint. The pole casts, the
	# emissive luminaire head sitting on top of it does not.
	_mmi(stalls, Color(0.88, 0.88, 0.86), "LotStalls", true, false)
	_mmi(stops, Color(0.75, 0.72, 0.65), "LotCurbStops", false, true)
	_mmi(poles, Color(0.2, 0.21, 0.23), "LotPoles", false, true)
	_mmi(heads, Color(0.9, 0.85, 0.6), "LotPoleHeads", false, false, true)


# ============================== PLAZAS =======================================
func _dress_plazas(lots: Array[Vector2i], tops: Array[Vector4],
		rng: RandomNumberGenerator) -> void:
	var planters: Array[Transform3D] = []
	var shrubs: Array[Transform3D] = []
	var walls: Array[Transform3D] = []
	var flags: Array[Transform3D] = []
	var banners: Array[Transform3D] = []
	var banner_col: Array[Color] = []
	var racks: Array[Transform3D] = []
	# Planter ring around every tower base (footprint recorded per tower).
	for t in tops:
		var r := t.w * 0.5 + 2.6
		for off: Vector2 in [Vector2(r, 0), Vector2(-r, 0), Vector2(0, r), Vector2(0, -r)]:
			var p := Vector3(t.x + off.x, SLAB_TOP, t.y + off.y)
			planters.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(1.5, 0.7, 1.5)), p + Vector3(0, 0.35, 0)))
			shrubs.append(Transform3D(
				Basis(Vector3.UP, rng.randf_range(0.0, TAU)) \
				* Basis.from_scale(Vector3(1.1, 0.65, 1.1)), p + Vector3(0, 0.98, 0)))
	# Per-block furniture: plaza walls, flagpoles with corporate banners, racks.
	for i in GRID_COLS:
		for j in GRID_ROWS:
			if lots.has(Vector2i(i, j)):
				continue
			var cx := BLOCK_ORIGIN.x + BLOCK_PITCH * float(i)
			var cz := BLOCK_ORIGIN.y + BLOCK_PITCH * float(j)
			var trust := Vector2i(i, j) == GIANT_CELL
			for k in (4 if trust else rng.randi_range(2, 3)):
				var ang := TAU * float(k) / 4.0 + rng.randf_range(-0.3, 0.3)
				var wp := Vector3(cx + cos(ang) * 24.0, SLAB_TOP + 0.24, cz + sin(ang) * 24.0)
				walls.append(Transform3D(
					Basis(Vector3.UP, ang + PI * 0.5) * Basis.from_scale(Vector3(6.0, 0.48, 0.55)), wp))
			for k2 in (4 if trust else 2):
				var fp := Vector3(cx + rng.randf_range(-20.0, 20.0), SLAB_TOP,
					cz + rng.randf_range(-20.0, 20.0))
				flags.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.14, 9.0, 0.14)), fp + Vector3(0, 4.5, 0)))
				banners.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(1.7, 1.0, 0.05)), fp + Vector3(0.92, 8.2, 0)))
				banner_col.append(Color(0.1, 0.45, 0.28) if trust \
					else [Color(0.7, 0.15, 0.12), Color(0.15, 0.3, 0.6),
						Color(0.85, 0.7, 0.2), Color(0.9, 0.9, 0.88)][rng.randi_range(0, 3)])
			var rp := Vector3(cx + rng.randf_range(-18.0, 18.0), SLAB_TOP + 0.4,
				cz + rng.randf_range(-18.0, 18.0))
			for h in 3:
				racks.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.08, 0.8, 0.9)),
					rp + Vector3(0.5 * float(h), 0, 0)))
	# All six cast. A corporate plaza is a flat pale slab with six things
	# standing on it; the furniture shadows ARE the composition, and the whole
	# set is 778 instances — the cheapest shadows in the project.
	_mmi(planters, Color(0.55, 0.54, 0.5), "PlazaPlanters", false, true)
	_mmi(shrubs, Color(0.26, 0.42, 0.2), "PlazaShrubs", false, true)
	_mmi(walls, Color(0.6, 0.58, 0.54), "PlazaWalls", false, true)
	_mmi(flags, Color(0.65, 0.66, 0.68), "Flagpoles", false, true)
	_mmi_colored(banners, banner_col, "FlagBanners", true)
	_mmi(racks, Color(0.3, 0.31, 0.34), "BikeRacks", false, true)


# ============================== HELPERS ======================================
func _solo(size: Vector3, pos: Vector3, col: Color, rough: float, yaw: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit
	mi.transform = Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(size), pos)
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	mi.material_override = m
	add_child(mi)


## `casts` is required, no default (D-028): a MultiMesh is culled as ONE unit,
## so one visible stall line put all 240 of them in every shadow cascade.
func _mmi(xf: Array[Transform3D], col: Color, label: String, unshaded: bool,
		casts: bool, emissive: bool = false) -> void:
	if xf.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 1.2
	_build_mmi(xf, [], m, label, casts)


func _mmi_colored(xf: Array[Transform3D], cols: Array[Color], label: String,
		casts: bool) -> void:
	if xf.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = 0.9
	m.vertex_color_use_as_albedo = true
	_build_mmi(xf, cols, m, label, casts)


func _build_mmi(xf: Array[Transform3D], cols: Array[Color],
		m: StandardMaterial3D, label: String, casts: bool) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = _unit
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if not cols.is_empty():
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = m
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
