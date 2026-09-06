extends Node3D
## EL DORADO GRANDE — Tier-1 city (layout M1; design-and-texture pass M8).
## A ~2km x 2km slice of the Megaplex, built entirely in _ready() from code:
##   - Downtown Dorado tower grid (southeast) crowned by Cattleman's Trust
##     Tower — "the Green Light" (canon per naming bible §13.5)
##   - Elevated I-3 freeway spine (east-west at z=0) with ramps + frontage strips
##   - The Threefork floodway race channel (southwest) with levees, bridges, jumps
##   - Suburb fringe (north), containment wall, construction-frontier flavor
## Physics: StaticBody3D + BoxShape3D only (rotated boxes for ramps/banks).
## Visuals: procedural world-triplanar textures (city_textures.gd), varied tower
## silhouettes, and a street-dressing/billboard child (city_dressing.gd).
## DETERMINISM CONTRACT: the original `rng` draw sequence is FROZEN — every
## M8 visual decision draws from the separate `drng`, and dressing is
## visual-only, so the physics layout (and the smoke baseline) is byte-stable.
## Deterministic fixed-seed RNG, no Time/Date, headless-safe.
## Axes: +X east, -Z north (Godot forward).

# ============================== TUNABLES =====================================
const WORLD_SEED := 31337
const MAP_HALF := 1000.0             # world spans [-1000, 1000] on x and z

# -- Downtown Dorado (east half, south of the freeway) --
const BLOCK := 60.0                  # raised block slab edge (m)
const STREET := 26.0                 # street gap between blocks (m)
const GRID_COLS := 8                 # blocks east-west
const GRID_ROWS := 6                 # blocks north-south
const GRID_WEST := 120.0             # x of the grid's west edge
const GRID_NORTH := 60.0             # z of the grid's north edge
const TOWER_H_MIN := 25.0
const TOWER_H_MAX := 140.0           # ordinary towers; only the Trust tops this
const GIANT_H := 165.0               # Cattleman's Trust Tower ("the Green Light")
const GIANT_CELL := Vector2i(3, 2)   # grid cell hosting the Trust (identifier
                                     # kept generic; canon name lives in docs)
const DRESS_SEED := 555777           # decoration RNG — NEVER touches `rng`
const LOT_CHANCE := 0.15             # chance a block is a flat parking lot

# -- Elevated freeway (east-west spine at z = 0) --
const FWY_TOP := 9.0                 # deck driving-surface height
const FWY_HALF_LEN := 800.0          # deck is 1.6 km long
const FWY_HALF_W := 12.0             # deck is 24 m wide
const FWY_THICK := 1.2
const COLUMN_STEP := 30.0            # column spacing beneath the deck
const RAMP_Z := 18.0                 # ramp lane centreline offset (band z 13..23)
const RAMP_BOT_X := 582.0            # |x| where ramps meet grade (rise 9.1m/64.6m ~ 8 deg)
const RAMP_TOP_X := 517.4            # ramp tip: 0.6 m past the pad edge (|x|=518)
const FRONTAGE_Z := 30.0             # frontage strip centreline (clear band z 24..36)

# -- The Floodway (southwest, runs north-south; the race arena) --
const CH_X0 := -710.0                # west levee rim
const CH_X1 := -530.0                # east levee rim (180 m wide)
const CH_Z0 := 100.0                 # north mouth (south end runs to the map edge)
const CH_FLOOR := -6.0               # smooth concrete floor height
const BANK_RUN := 24.0               # horizontal run of each levee bank (~13 deg)

# -- Suburb fringe (north) --
const SUB_RECT := Rect2(-600, -880, 1300, 700)  # x, z, width, depth
const HOUSE_CHANCE := 0.42           # loose grid: big cul-de-sac gaps
const HOUSE_SIZES: Array[Vector3] = [Vector3(11, 4, 13), Vector3(14, 4.5, 9)]

# ============================== STATE ========================================
const TEX := preload("res://scripts/world/city_textures.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")
const DRESSING_PATH := "res://scripts/world/city_dressing.gd"

var rng := RandomNumberGenerator.new()
var drng := RandomNumberGenerator.new()          # M8 decoration draws ONLY
var _spawn := Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))
var _mesh_cache: Dictionary = {}                 # size-key -> shared BoxMesh
var _tower_xforms: Array[Transform3D] = []       # glass segments -> one MultiMesh
var _tower_colors: Array[Color] = []             # per-segment facade tint
var _cap_xforms: Array[Transform3D] = []         # rooftop mechanicals/parapets
var _antenna_xforms: Array[Transform3D] = []     # rooftop masts on the tallest
var _podium_xforms: Array[Transform3D] = []      # ground-floor retail bases
var _canopy_xforms: Array[Transform3D] = []      # sidewalk canopies over them
var _column_xforms: Array[Transform3D] = []      # batched into one MultiMesh
var _trim_xforms: Array[Transform3D] = []        # M15 corner mullions + cornices
var _lot_cells: Array[Vector2i] = []             # parking-lot cells, as built
# Recorded WHERE things landed (no extra rng draws) so the dressing layer can
# decorate them: strip-mall storefront faces and tower roofs for signage.
var _mall_slots: Array[Vector3] = []             # (x, side, unused) per mall
var _tower_tops: Array[Vector4] = []             # (x, z, height, footprint_x)
var _house_xforms: Array[Transform3D] = []       # M15: suburb houses (rot + pos)
var _house_sizes: Array[Vector3] = []            # M15: matching box sizes

# Shared material palette (6 shared + Cattleman's Trust signature green).
var mat_asphalt: Material
var mat_concrete: Material
var mat_glass: StandardMaterial3D
var mat_brick: StandardMaterial3D
var mat_prairie: StandardMaterial3D
var mat_hazard: StandardMaterial3D
var mat_green: StandardMaterial3D
var mat_podium: StandardMaterial3D
var mat_tank: StandardMaterial3D


func _ready() -> void:
	rng.seed = WORLD_SEED
	drng.seed = DRESS_SEED
	_make_materials()
	_build_ground()
	_build_downtown()
	_build_freeway()
	_build_floodway()
	_build_suburbs()
	_build_edge_and_flavor()
	_flush_multimeshes()
	_build_dressing()
	# M13: County General — appended at the END, fully literal (zero RNG draws),
	# so every seeded draw order above stays frozen (physics is sacred).
	_build_hospital()
	# M20 (defect D-011): the Stonebridle Ranch infill — a SECOND suburb pass
	# on its own literal seed, appended after every frozen `rng`/`drng` stream
	# above has finished, so the M1 draw order is untouched. It must run BEFORE
	# _build_extra_layers() and nowhere else: suburb_dressing reads
	# get_house_xforms() when its layer builds, so a house recorded after that
	# call would ship as a bare brick box next to a detailed one.
	_build_suburb_infill()
	# M15: district dressing layers — each a self-contained visual-only file
	# with its own literal seed, loaded in a FIXED order (list below), each
	# skipped cleanly if absent so partial trees still boot.
	_build_extra_layers()


## Contract for main.gd: spawn on the wide north-south street at downtown's
## south edge, facing north (-Z) straight down the street toward the freeway.
func get_spawn_point() -> Transform3D:
	return _spawn


## Contract for gameplay systems (repo_board): the grid cells that became flat
## parking lots, recorded during the build — the single source of truth, so
## nobody has to replay this script's RNG draw order.
func get_lot_cells() -> Array[Vector2i]:
	return _lot_cells.duplicate()


# ============================== MATERIALS ====================================
## M8: the flat greybox colors became procedural world-triplanar textures
## (city_textures.gd). Same variable names — every existing _box call gets the
## upgrade for free. mat_glass carries the window grid + night-lit emission.
func _make_materials() -> void:
	mat_asphalt = SHD.asphalt_material()                # dark road beds
	mat_concrete = SHD.concrete_material()              # slabs, freeway, channel
	mat_glass = TEX.tower_material(Color(0.42, 0.54, 0.62))  # downtown towers
	mat_brick = TEX.brick_material(Color(0.50, 0.31, 0.22))  # houses, strip malls
	mat_prairie = TEX.prairie_material()                # ground, levee banks
	mat_hazard = _mat(Color(0.92, 0.45, 0.10), 0.8)     # jumps, construction
	mat_green = _mat(Color(0.20, 0.52, 0.36), 0.3)      # Cattleman's Trust glass
	mat_green.emission_enabled = true
	mat_green.emission = Color(0.05, 0.30, 0.15)
	mat_podium = TEX.brick_material(Color(0.40, 0.29, 0.24))  # retail bases
	mat_tank = _mat(Color(0.44, 0.42, 0.38), 0.9)       # rooftop water tanks


func _mat(albedo: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.roughness = rough
	return m


# ============================== GROUND =======================================
## Prairie base in THREE slabs that surround the floodway cut — there is no
## ground under the channel; its floor at y=-6 is a separate slab. Adjacent
## slabs overlap ~1-2 m in plan with tops offset 1 cm so coplanar faces never
## z-fight; steps that small vanish under the raycast suspension.
func _build_ground() -> void:
	# North slab: everything above the channel mouth, full width.
	_slab(Rect2(-MAP_HALF, -MAP_HALF, 2.0 * MAP_HALF, MAP_HALF + CH_Z0 + 1.0), -0.02, mat_prairie)
	# East slab: from the east levee rim to the map edge.
	_slab(Rect2(CH_X1 - 1.0, CH_Z0 - 1.0, MAP_HALF - CH_X1 + 1.0, MAP_HALF - CH_Z0 + 1.0), -0.03, mat_prairie)
	# West slab: the thin strip west of the channel.
	_slab(Rect2(-MAP_HALF, CH_Z0 - 1.0, MAP_HALF + CH_X0 + 1.0, MAP_HALF - CH_Z0 + 1.0), -0.03, mat_prairie)
	# Dark asphalt aprons: at-grade freeway corridor + downtown street bed.
	_slab(Rect2(-800, -42, 1600, 84), 0.01, mat_asphalt)
	_slab(Rect2(100, 40, 690, 526), 0.0, mat_asphalt)


# ============================ DOWNTOWN DORADO ================================
## 8x6 blocks: raised lighter slabs (0.2 m curb — trivial for 0.42 m wheels)
## over the dark asphalt street bed, so the 26 m streets read as gaps. Towers
## get taller toward the grid centre; some blocks stay flat parking lots.
## Tower visuals are batched: one unit BoxMesh, per-instance scaled transforms.
func _build_downtown() -> void:
	var pitch := BLOCK + STREET
	var gcx := GRID_WEST + BLOCK * 0.5 + 3.5 * pitch     # grid centre x (=451)
	var gcz := GRID_NORTH + BLOCK * 0.5 + 2.5 * pitch    # grid centre z (=305)
	var quads := [Vector2(-15, -15), Vector2(15, -15), Vector2(15, 15), Vector2(-15, 15)]
	for i in GRID_COLS:
		for j in GRID_ROWS:
			var cx := GRID_WEST + BLOCK * 0.5 + i * pitch
			var cz := GRID_NORTH + BLOCK * 0.5 + j * pitch
			var giant := Vector2i(i, j) == GIANT_CELL
			var lot := not giant and rng.randf() < LOT_CHANCE
			_box(Vector3(BLOCK, 0.2, BLOCK), Vector3(cx, 0.1, cz), mat_asphalt if lot else mat_concrete)
			if lot:
				_lot_cells.append(Vector2i(i, j))
				continue
			if giant:  # Cattleman's Trust Tower — solitary on its block.
				_box(Vector3(26, GIANT_H, 26), Vector3(cx, GIANT_H * 0.5 + 0.1, cz), mat_green)
				_build_trust_crown(cx, cz)
				continue
			var count := rng.randi_range(1, 4)
			var start := rng.randi_range(0, 3)
			for k in count:  # one tower per 30 m quadrant — no overlap possible
				var q: Vector2 = quads[(start + k) % 4]
				var sx := rng.randf_range(14.0, 24.0)
				var sz := rng.randf_range(14.0, 24.0)
				var falloff := clampf(Vector2(cx - gcx, cz - gcz).length() / 380.0, 0.0, 1.0)
				var h := clampf(lerpf(TOWER_H_MAX, TOWER_H_MIN, falloff) \
					* rng.randf_range(0.75, 1.1), TOWER_H_MIN, TOWER_H_MAX)
				var pos := Vector3(cx + q.x + rng.randf_range(-3, 3), h * 0.5 + 0.1,
					cz + q.y + rng.randf_range(-3, 3))
				# Collider: the ORIGINAL full box, frozen since M1 (physics is
				# sacred). Visuals: a varied silhouette drawn from drng only.
				_box(Vector3(sx, h, sz), pos, null, Basis.IDENTITY, false)
				_tower_visual(pos, sx, h, sz, j)
	# Spawn: south margin of the street bed, aimed north up the wide straight
	# street between block columns 0 and 1 (Godot forward is -Z).
	var spawn_x := GRID_WEST + BLOCK + STREET * 0.5
	_spawn = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), Vector3(spawn_x, 1.3, 558.0))


## One tower's VISUAL: base shaft + (for the tall ones) an inset upper setback,
## a concrete rooftop mechanical cap, and an antenna mast on true high-rises.
## Facade tint varies north (cool corporate blue) to south (warm bronze toward
## the strip) with per-tower jitter — MultiMesh instance colors, one material.
func _tower_visual(pos: Vector3, sx: float, h: float, sz: float, row: int) -> void:
	var warm := clampf((float(row) - 1.0) / 4.0, 0.0, 1.0)  # row 0 north .. 5 south
	var tint := Color(0.82, 0.9, 1.0).lerp(Color(1.0, 0.88, 0.72), warm) \
		* drng.randf_range(0.78, 1.0)
	# Clamp: HDR instance colors (>1) read as glow — review-caught.
	tint = Color(minf(tint.r, 1.0), minf(tint.g, 1.0), minf(tint.b, 1.0), 1.0)
	var base_y := pos.y - h * 0.5  # tower footprint bottom (slab top)
	if h >= 60.0 and drng.randf() < 0.65:
		var split := drng.randf_range(0.55, 0.72)
		var inset := drng.randf_range(0.58, 0.8)
		var h1 := h * split
		var h2 := h - h1
		_glass_seg(Vector3(sx, h1, sz), Vector3(pos.x, base_y + h1 * 0.5, pos.z), tint)
		_glass_seg(Vector3(sx * inset, h2, sz * inset),
			Vector3(pos.x, base_y + h1 + h2 * 0.5, pos.z), tint * drng.randf_range(0.95, 1.05))
		_roof_cap(Vector3(pos.x, base_y + h, pos.z), sx * inset, sz * inset)
	else:
		_glass_seg(Vector3(sx, h, sz), pos, tint)
		_roof_cap(Vector3(pos.x, base_y + h, pos.z), sx, sz)
	if h >= 105.0 and drng.randf() < 0.7:  # mast on the true high-rises
		var mast_h := drng.randf_range(8.0, 18.0)
		_antenna(Vector3(pos.x + drng.randf_range(-2.0, 2.0), base_y + h + mast_h * 0.5,
			pos.z + drng.randf_range(-2.0, 2.0)), mast_h)
	elif h < 105.0 and drng.randf() < 0.35:  # water tank on the mid-rises
		_water_tank(Vector3(pos.x, base_y + h, pos.z), sx)
	if drng.randf() < 0.55:  # street-level retail base
		_podium(pos, sx, h, sz, base_y)


func _glass_seg(size: Vector3, pos: Vector3, tint: Color) -> void:
	tint.a = 1.0  # instance alpha must stay opaque on an opaque material
	_tower_xforms.append(Transform3D(Basis.IDENTITY.scaled(size), pos))
	_tower_colors.append(tint)
	# M15 de-blocking: corner mullion columns + a cornice band per segment
	# (zero rng draws — derived purely from the segment box) so the silhouette
	# reads as built structure instead of an extruded rectangle.
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			_trim_xforms.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.42, size.y, 0.42)),
				pos + Vector3(cx * size.x * 0.5, 0.0, cz * size.z * 0.5)))
	_trim_xforms.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(size.x + 0.5, 0.9, size.z + 0.5)),
		pos + Vector3(0, size.y * 0.5 - 0.45, 0)))
	if size.y > 55.0:  # remember roofs big enough to host a skyline sign
		_tower_tops.append(Vector4(pos.x, pos.z, pos.y + size.y * 0.5, size.x))


## Ground-floor retail podium: a wider two-storey base with a canopy lip. This
## is what makes a street feel enclosed and commercial instead of a runway
## between slabs. Visual-only — the tower's collider still owns the footprint,
## so the podium overhang is cosmetic (greybox tier accepts that).
func _podium(pos: Vector3, sx: float, h: float, sz: float, base_y: float) -> void:
	var ph := minf(7.5, h * 0.32)
	var grow := 1.5
	_podium_xforms.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(sx + grow, ph, sz + grow)),
		Vector3(pos.x, base_y + ph * 0.5, pos.z)))
	# Canopy lip over the sidewalk.
	_canopy_xforms.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(sx + grow + 1.6, 0.35, sz + grow + 1.6)),
		Vector3(pos.x, base_y + ph, pos.z)))


## Rooftop water tank on a stand — the other North Texas skyline object.
func _water_tank(top: Vector3, fx: float) -> void:
	var r := clampf(fx * 0.22, 1.1, 2.4)
	var mi := MeshInstance3D.new()
	mi.mesh = MESH_KIT.prism(r, r * 1.7, 10)
	mi.material_override = mat_tank
	mi.position = top + Vector3(0, 2.6 + r * 0.85, 0)
	add_child(mi)
	for lx: float in [-1.0, 1.0]:
		for lz: float in [-1.0, 1.0]:
			_cap_xforms.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.22, 2.6, 0.22)),
				top + Vector3(lx * r * 0.62, 1.3, lz * r * 0.62)))


func _roof_cap(top: Vector3, fx: float, fz: float) -> void:
	var w := fx * drng.randf_range(0.3, 0.45)
	var d := fz * drng.randf_range(0.3, 0.45)
	var hh := drng.randf_range(1.8, 3.6)
	_cap_xforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(w, hh, d)),
		top + Vector3(drng.randf_range(-fx * 0.18, fx * 0.18), hh * 0.5,
			drng.randf_range(-fz * 0.18, fz * 0.18))))
	# Parapet lip: a thin slab overhanging the roof edge finishes the skyline.
	_cap_xforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(fx + 0.7, 0.7, fz + 0.7)),
		top + Vector3(0.0, 0.15, 0.0)))


func _antenna(pos: Vector3, mast_h: float) -> void:
	_antenna_xforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, mast_h, 0.5)), pos))


## THE GREEN LIGHT — Cattleman's Trust Tower's crown: two emissive green bands
## below the roofline and the bank's name on all four faces. The whole skyline
## reads it at night; the map's one true landmark (naming bible §13.5).
func _build_trust_crown(cx: float, cz: float) -> void:
	var crown := StandardMaterial3D.new()
	crown.albedo_color = Color(0.15, 0.9, 0.4)
	crown.emission_enabled = true
	crown.emission = Color(0.1, 0.95, 0.35)
	crown.emission_energy_multiplier = 3.0
	crown.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_mesh(Vector3(27.4, 1.6, 27.4))
	mi.material_override = crown
	mi.position = Vector3(cx, GIANT_H - 6.0, cz)
	add_child(mi)
	var mi2 := MeshInstance3D.new()
	mi2.mesh = _shared_mesh(Vector3(26.8, 0.8, 26.8))
	mi2.material_override = crown
	mi2.position = Vector3(cx, GIANT_H - 11.0, cz)
	add_child(mi2)
	# M22 FIT: `font_size = 340` drew 34.0 m of letters on a 26 m tower — the
	# map's ONE true landmark (bible 13.5), overhanging 4 m of open sky on each
	# of its four faces, and nobody had put a number on it in nine milestones.
	# Fitted to the crown collar it is mounted on, in CHANNEL: heavy, wide-set
	# letters, which is what a bank actually bolts to a roofline.
	for face in 4:
		var label := SIGN.make("CATTLEMAN'S TRUST", SIGN.CHANNEL,
			Color(0.85, 1.0, 0.9), 24.6, 0.0, 340)
		label.outline_modulate = Color(0.02, 0.25, 0.12)
		var ang := face * PI * 0.5
		label.position = Vector3(cx, GIANT_H - 15.5, cz) \
			+ Vector3(sin(ang), 0.0, cos(ang)) * 13.6
		label.rotation.y = ang
		add_child(label)


# ============================ ELEVATED FREEWAY ===============================
## 1.6 km deck at y=9 with columns every 30 m, 1 m side barriers (gapped at the
## ramp merges), two ramps per side (one climbing each direction), merge pads,
## clear 12 m frontage strips at grade, and strip malls facing them.
## Joint rule everywhere: a rising box's low end sinks under the lower slab,
## and its tip crosses the upper slab's top height AT the slab's plan edge
## (then pokes ~10 cm proud just past it — a crest bump the raycast suspension
## eats). The drivable crossing happens where the surfaces are level — no lip.
func _build_freeway() -> void:
	# Deck (driving surface at FWY_TOP).
	_box(Vector3(2.0 * FWY_HALF_LEN, FWY_THICK, 2.0 * FWY_HALF_W),
		Vector3(0, FWY_TOP - FWY_THICK * 0.5, 0), mat_concrete)
	# Columns: collider per column now; one shared MultiMesh visual later.
	var x := -FWY_HALF_LEN + 20.0
	while x <= FWY_HALF_LEN - 19.9:
		_column(Vector3(x, 3.85, 0.0), Vector3(1.6, 8.2, 1.6))
		x += COLUMN_STEP
	# Side barriers: 3 segments per edge, gapped over the merge pads (|x| 478..518).
	for side: float in [-1.0, 1.0]:
		for seg: Vector2 in [Vector2(-800, -519), Vector2(-477, 477), Vector2(519, 800)]:
			var seg_len := seg.y - seg.x
			_box(Vector3(seg_len, 1.0, 0.6),
				Vector3((seg.x + seg.y) * 0.5, FWY_TOP + 0.5, side * (FWY_HALF_W - 0.3)), mat_concrete)
	# Ramps + merge pads: two per side. Pad top sits 2 cm below the deck and
	# overlaps its edge in plan (tiny step up, zero gap, zero z-fight). The
	# ramp tip reaches pad height exactly at the pad's outer edge (|x|=518).
	for side: float in [-1.0, 1.0]:
		for endx: float in [-1.0, 1.0]:
			var zc := side * RAMP_Z
			_ramp(Vector3(endx * RAMP_BOT_X, -0.05, zc),
				Vector3(endx * RAMP_TOP_X, FWY_TOP + 0.09, zc), 10.0, mat_asphalt)
			_box(Vector3(40, 1.0, 11.6), Vector3(endx * 498.0, FWY_TOP - 0.52, side * 17.3), mat_concrete)
	# Frontage roads: clear flat 12 m asphalt strips at grade (z 24..36), with
	# one-story brick strip malls facing them from across a sidewalk gap.
	for side: float in [-1.0, 1.0]:
		_box(Vector3(1600, 0.5, 12), Vector3(0, -0.2, side * FRONTAGE_Z), mat_asphalt)
		var mx := -760.0
		while mx <= 760.0:
			if rng.randf() < 0.75:
				var bx := mx + rng.randf_range(-8, 8)  # SAME draw as always
				_box(Vector3(26, 5, 12), Vector3(bx, 2.45, side * 44.0), mat_brick)
				_mall_slots.append(Vector3(bx, side, 0.0))  # recorded for signage
			mx += 110.0


# ============================== THE FLOODWAY =================================
## 180 m depressed channel, smooth concrete floor at y=-6 (the race arena),
## ~13-degree drivable levee banks on both sides plus an end bank at the north
## mouth, two flat bridge decks on columns, and three hazard-orange jump ramps
## placed well clear of the bridges so launches never clip a deck.
func _build_floodway() -> void:
	var mid_x := (CH_X0 + CH_X1) * 0.5
	var zc := (CH_Z0 + MAP_HALF) * 0.5
	var zlen := MAP_HALF - CH_Z0
	# Channel floor slab (the ONLY ground inside the cut).
	_box(Vector3(CH_X1 - CH_X0, 1.0, zlen), Vector3(mid_x, CH_FLOOR - 0.5, zc), mat_concrete)
	# Levee banks (~14 deg): floor ends tuck 1 m under the floor slab; rim tips
	# clear the prairie slab top at its plan edge (rim slab edges sit 1 m out
	# from CH_X0/CH_X1), cresting ~10 cm proud 0.6 m past it.
	_ramp(Vector3(CH_X1 - BANK_RUN - 1.0, CH_FLOOR - 0.05, zc),
		Vector3(CH_X1 - 0.4, 0.09, zc), zlen - 4.0, mat_prairie, 1.2)
	_ramp(Vector3(CH_X0 + BANK_RUN + 1.0, CH_FLOOR - 0.05, zc),
		Vector3(CH_X0 + 0.4, 0.09, zc), zlen - 4.0, mat_prairie, 1.2)
	# End bank across the north mouth so the channel dead-ends drivably.
	_ramp(Vector3(mid_x, CH_FLOOR - 0.05, CH_Z0 + 26.0),
		Vector3(mid_x, 0.09, CH_Z0 + 0.6), CH_X1 - CH_X0 - 2.0 * BANK_RUN, mat_prairie, 1.2)
	# Two bridge crossings: flat decks slightly proud of grade (7 cm step),
	# overlapping both rims by 30 m, on columns rising from the channel floor.
	for bz: float in [300.0, 650.0]:
		_box(Vector3(240, 1.2, 16), Vector3(mid_x, -0.54, bz), mat_concrete)
		for cx: float in [-680.0, -620.0, -560.0]:
			_column(Vector3(cx, -3.4, bz), Vector3(2.0, 5.6, 2.0))
	# Jump ramps (~17 deg, launch edge at floor+3.4 m). dir: +1 launches south.
	_jump(-660.0, 400.0, 1.0)
	_jump(-580.0, 480.0, -1.0)
	_jump(-620.0, 560.0, -1.0)


func _jump(x: float, z: float, dir: float) -> void:
	_ramp(Vector3(x, CH_FLOOR - 0.05, z - dir * 5.5),
		Vector3(x, CH_FLOOR + 3.4, z + dir * 5.5), 12.0, mat_hazard, 0.8)


# ============================== SUBURB FRINGE ================================
## Loose north-side grid of one-story brick houses: big gaps, jittered
## positions, varied yaw — cul-de-sac sprawl without actual cul-de-sacs.
func _build_suburbs() -> void:
	var x := SUB_RECT.position.x
	while x <= SUB_RECT.end.x:
		var z := SUB_RECT.position.y
		while z <= SUB_RECT.end.y:
			if rng.randf() < HOUSE_CHANCE:
				var size: Vector3 = HOUSE_SIZES[rng.randi_range(0, HOUSE_SIZES.size() - 1)]
				var yaw := rng.randf_range(-0.25, 0.25) + (PI * 0.5) * float(rng.randi_range(0, 3))
				var pos := Vector3(x + rng.randf_range(-8, 8), size.y * 0.5 - 0.1,
					z + rng.randf_range(-8, 8))
				_box(size, pos, mat_brick, Basis(Vector3.UP, yaw))
				# M15: record WHERE each house landed (zero extra draws) so the
				# suburb dressing layer can put roofs and yards on them.
				_house_xforms.append(Transform3D(Basis(Vector3.UP, yaw), pos))
				_house_sizes.append(size)
			z += 80.0
		x += 95.0


# ========================= MAP EDGE + CONSTRUCTION ===========================
## Containment: four walls (tops at y=3.5, roots at y=-8.5 so the channel's
## south exit is sealed too; corners interpenetrate, which is fine for statics).
## Plus scattered hazard-orange boxes — the construction frontier.
func _build_edge_and_flavor() -> void:
	var wall_len := 2.0 * MAP_HALF
	for side: float in [-1.0, 1.0]:
		_box(Vector3(wall_len, 12.0, 2.0), Vector3(0, -2.5, side * (MAP_HALF - 2.0)), mat_concrete)
		_box(Vector3(2.0, 12.0, wall_len), Vector3(side * (MAP_HALF - 2.0), -2.5, 0), mat_concrete)
	# Hand-picked open-prairie spots (clear of roads, grid, channel, suburbs).
	for s: Vector2 in [Vector2(-300, 700), Vector2(200, 800), Vector2(700, 650),
			Vector2(900, 200), Vector2(-900, -700), Vector2(-850, 60),
			Vector2(500, 900), Vector2(-200, 900)]:
		_box(Vector3(6, 3, 4),
			Vector3(s.x + rng.randf_range(-15, 15), 1.4, s.y + rng.randf_range(-15, 15)),
			mat_hazard, Basis(Vector3.UP, rng.randf_range(0.0, PI)))


# ============================== BUILD HELPERS ================================
## One static box: StaticBody3D + BoxShape3D collider, plus an optional visual
## using a cached shared BoxMesh (identical sizes share one mesh resource).
func _box(size: Vector3, origin: Vector3, mat: Material,
		basis := Basis.IDENTITY, with_visual := true) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(basis, origin)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	if with_visual:
		var mi := MeshInstance3D.new()
		mi.mesh = _shared_mesh(size)
		mi.material_override = mat
		body.add_child(mi)
	add_child(body)


## Ground slab helper: rect is (x, z, width, depth); top is the surface height.
func _slab(rect: Rect2, top: float, mat: Material) -> void:
	var c := rect.get_center()
	_box(Vector3(rect.size.x, 1.0, rect.size.y), Vector3(c.x, top - 0.5, c.y), mat)


## Sloped box whose TOP surface runs from `bottom` to `top` (world points).
## Width is the horizontal axis perpendicular to the slope. Used for freeway
## ramps, levee banks, and jump ramps — rotated boxes are legal colliders.
func _ramp(bottom: Vector3, top: Vector3, width: float, mat: Material,
		thickness := 1.0) -> void:
	var run := top - bottom
	var slope := run.normalized()
	var side := Vector3.UP.cross(slope).normalized()
	var normal := slope.cross(side).normalized()
	var center := (bottom + top) * 0.5 - normal * (thickness * 0.5)
	_box(Vector3(width, thickness, run.length()), center, mat, Basis(side, normal, slope))


## Column: individual collider now, pooled MultiMesh visual on flush.
func _column(pos: Vector3, size: Vector3) -> void:
	_box(size, pos, null, Basis.IDENTITY, false)
	_column_xforms.append(Transform3D(Basis.IDENTITY.scaled(size), pos))


## Batch the most repeated visual elements into MultiMeshes: one unit cube
## mesh each, per-instance scaled transforms — one draw call per element type.
func _flush_multimeshes() -> void:
	# SHADOW POLICY (D-028). Everything this file builds is BUILDING MASS, and
	# building mass is what the whole shadow pass exists for — a tower that does
	# not lay a block of shade down the avenue is a cardboard cutout. All seven
	# sets cast, and the flag is stated rather than defaulted so the next set
	# added here has to answer. (Only three are non-empty today: downtown_types
	# owns the skyline now and the other four arrays build nothing.)
	_make_mmi(_tower_xforms, mat_glass, "TowerVisuals", true, _tower_colors)
	_make_mmi(_podium_xforms, mat_podium, "RetailPodiums", true)
	_make_mmi(_canopy_xforms, mat_concrete, "PodiumCanopies", true)
	_make_mmi(_cap_xforms, mat_concrete, "RoofCaps", true)
	var mast := _mat(Color(0.2, 0.2, 0.22), 0.6)
	_make_mmi(_antenna_xforms, mast, "Antennas", true)
	_make_mmi(_column_xforms, mat_concrete, "ColumnVisuals", true)
	_make_mmi(_trim_xforms, _mat(Color(0.15, 0.15, 0.17), 0.65), "TowerTrim", true)


## `casts` is required, no default (D-028) — see the policy note at the flush.
func _make_mmi(xforms: Array[Transform3D], mat: Material, label: String,
		casts: bool, colors: Array[Color] = []) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not colors.is_empty()
	mm.mesh = _shared_mesh(Vector3.ONE)
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		if not colors.is_empty():
			mm.set_instance_color(i, colors[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## The M8 street-dressing/signage layer: a child that reads what this script
## RECORDED (lot cells, mall slots, tower tops) and paints the world — lane
## markings, streetlights, trees, and the satire billboard canon. Visual-only
## by contract (its poles carry no collision near the smoke corridor and it
## draws from drng-style seeds of its own), so physics stays byte-stable.
func _build_dressing() -> void:
	if not ResourceLoader.exists(DRESSING_PATH):
		push_error("city_dressing.gd MISSING — the street is undressed")
		return
	var script: Variant = load(DRESSING_PATH)
	# D-074: a parse error makes load() return null and `script.new()` used to
	# die quietly — observed exit 0 with EVERY streetlight, sign, tree and lane
	# marking gone and nothing reported. A broken layer must be LOUD.
	if not (script is GDScript):
		push_error("city_dressing.gd FAILED TO PARSE — no street dressing built")
		return
	var node: Node3D = (script as GDScript).new()
	node.name = "CityDressing"
	add_child(node)
	if node.has_method("build"):
		node.call("build", self)


# ============================ COUNTY GENERAL (M13) ===========================
## The county hospital, on the open prairie just south of the downtown street
## bed, aligned with the x=365 north-south street — where you wake up after a
## death. Its own campus: driveway off the street bed, ambulance apron, ER wing
## under a canopy, five-storey ward slab (lit tower glass at night), rooftop
## helipad, and the roadside sign. Every coordinate is a literal — this builder
## makes NO rng/drng draws — and everything sits far outside the smoke corridor
## (x 339..391 vs corridor x 174..212).
const HOSPITAL_X := 365.0            # campus centreline (matches an NS street)
const HOSPITAL_DOOR := Vector3(365.0, 0.15, 610.5)   # feet, just outside ER glass
const HOSPITAL_TRUCK := Vector3(349.0, 1.0, 605.0)   # wrecker's spot on the apron


func _build_hospital() -> void:
	var x := HOSPITAL_X
	var mat_ward := TEX.tower_material(Color(0.78, 0.84, 0.82))   # pale, lit at night
	var mat_er := TEX.brick_material(Color(0.62, 0.58, 0.52))     # tan precast
	# Ground: driveway bridging the street bed (ends z=566) to the apron, then
	# the ambulance apron itself. Tops at 0.02 — a 4 cm curb, trivial for wheels.
	_box(Vector3(12, 0.08, 26), Vector3(x, -0.02, 579), mat_asphalt)
	_box(Vector3(52, 0.08, 26), Vector3(x, -0.02, 604), mat_asphalt)
	# Main ward slab (collider + lit-window visual) with a concrete roof cap.
	_box(Vector3(42, 18, 15), Vector3(x, 9.1, 629.5), mat_ward)
	_box(Vector3(42.6, 0.5, 15.6), Vector3(x, 18.35, 629.5), mat_concrete)
	_box(Vector3(4, 2.2, 3), Vector3(x - 13, 19.7, 627), mat_tank)   # mechanicals
	_box(Vector3(3, 1.6, 2.4), Vector3(x - 7, 19.4, 631), mat_tank)
	# Helipad: flat drum on the roof cap + a painted H + corner lights.
	var pad := MeshInstance3D.new()
	pad.mesh = MESH_KIT.prism(5.5, 0.36, 20)
	pad.position = Vector3(x + 11, 18.78, 629.5)
	pad.material_override = _mat(Color(0.30, 0.31, 0.33), 0.9)
	add_child(pad)
	var hmark := Label3D.new()
	hmark.double_sided = false   # D-016: cull the mirrored back face
	hmark.text = "H"
	hmark.font_size = 620
	hmark.pixel_size = 0.01
	hmark.modulate = Color(0.95, 0.8, 0.2)
	hmark.rotation.x = -PI * 0.5      # painted flat on the pad, read from above
	hmark.position = Vector3(x + 11, 18.99, 629.5)
	add_child(hmark)
	var padlight := _mat(Color(0.9, 0.25, 0.15), 0.4)
	padlight.emission_enabled = true
	padlight.emission = Color(0.9, 0.25, 0.15)
	padlight.emission_energy_multiplier = 1.8
	for c: Vector2 in [Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)]:
		var pl := MeshInstance3D.new()
		pl.mesh = _shared_mesh(Vector3(0.22, 0.22, 0.22))
		pl.material_override = padlight
		pl.position = Vector3(x + 11 + c.x, 19.07, 629.5 + c.y)
		add_child(pl)
	# ER wing: low front block tucked against the ward, glass doors proud of the
	# face (a lofted-hull lesson: glazing buried flush reads as a hole).
	_box(Vector3(20, 6, 12), Vector3(x, 3.1, 618), mat_er)
	var door := MeshInstance3D.new()
	door.mesh = _shared_mesh(Vector3(5.2, 3.4, 0.3))
	door.position = Vector3(x, 1.8, 611.9)
	var dg := _mat(Color(0.16, 0.20, 0.24), 0.15)
	dg.metallic = 0.3
	door.material_override = dg
	add_child(door)
	# Canopy over the ambulance bay on four posts, EMERGENCY on the fascia.
	_box(Vector3(14, 0.5, 8), Vector3(x, 4.85, 607), mat_concrete)
	for px: float in [-5.5, 5.5]:
		for pz: float in [604.0, 610.0]:
			_box(Vector3(0.35, 4.6, 0.35), Vector3(x + px, 2.3, pz), mat_concrete)
	var red := _mat(Color(0.75, 0.08, 0.06), 0.6)
	red.emission_enabled = true
	red.emission = Color(0.75, 0.08, 0.06)
	red.emission_energy_multiplier = 1.6
	var fascia := MeshInstance3D.new()
	fascia.mesh = _shared_mesh(Vector3(11, 1.2, 0.3))
	fascia.position = Vector3(x, 4.85, 602.9)
	fascia.material_override = red
	add_child(fascia)
	# The canopy fascia is 11.0 x 1.2 and the ward face is 42 x 18. Two signs
	# in two different registers so they stop reading as one sign at two sizes
	# (D-041): EMERGENCY is a lit hospital fascia, the ward name is CHANNEL
	# lettering on the building itself.
	_hospital_label("EMERGENCY", Vector3(x, 4.85, 602.65), 150, Color(1, 1, 1),
		1.0, 10.4, 1.02, SIGN.FASCIA)
	_hospital_label("COUNTY GENERAL", Vector3(x, 15.5, 621.6), 210,
		Color(0.62, 0.85, 0.82), 1.0, 30.0, 0.0, SIGN.CHANNEL)
	# Ambulance-bay red zone + visitor stalls the wrecker wakes up in.
	_paint(Vector3(13, 0.02, 0.4), Vector3(x, 0.065, 611.3), Color(0.78, 0.12, 0.1))
	for k in 5:
		_paint(Vector3(0.14, 0.02, 5.2), Vector3(x - 21 + 5.0 * float(k), 0.065, 605.0),
			Color(0.88, 0.88, 0.86))
	# Roadside sign at the driveway mouth, readable from both directions —
	# on the EAST verge (D-041). It used to stand on the west verge at x-13,
	# which put it 20.5 deg off the campus centreline from the south-west while
	# the ward sign sat at 20.2 deg: **0.3 deg apart**, so from `face` and
	# `showcase_people` — the vantages a player gets after every death — a big
	# pale COUNTY GENERAL and a small blue COUNTY GENERAL landed on top of each
	# other and read as one illegible stack. Mirrored to x+13 the same two
	# signs sit 15.6 deg apart and separate cleanly. Same verge width, same
	# distance from the driveway, both faces still lettered.
	_box(Vector3(0.4, 6.5, 0.4), Vector3(x + 13, 3.25, 585), mat_concrete)
	_box(Vector3(7.5, 3.2, 0.4), Vector3(x + 13, 7.6, 585), mat_concrete)
	# M22 FIT. This 7.5 m panel was carrying 10.59 m of COUNTY GENERAL (141 % of
	# the board) over 8.43 m of HOSPITAL · EMERGENCY (112 %) — two lines running
	# off both ends of a sign the player is required to read after every death.
	# Fitted, and set as a municipal guide sign (STENCIL) so it cannot be
	# confused with the CHANNEL lettering on the building behind it.
	for face: float in [1.0, -1.0]:  # face=1 reads from the north (label on -z side)
		_hospital_label("COUNTY GENERAL", Vector3(x + 13, 8.42, 585 - face * 0.26),
			120, Color(0.2, 0.45, 0.55), face, 6.9, 0.95, SIGN.STENCIL)
		_hospital_label("HOSPITAL  ·  EMERGENCY", Vector3(x + 13, 7.46, 585 - face * 0.26),
			70, Color(0.75, 0.1, 0.08), face, 6.9, 0.62, SIGN.STENCIL)
		_hospital_label("YOU BLEED. WE BILL.", Vector3(x + 13, 6.62, 585 - face * 0.26),
			52, Color(0.25, 0.26, 0.3), face, 6.9, 0.52, SIGN.PLAQUE)


## Label readable from the NORTH (the arriving player) by default: Label3D's
## face is +Z, the reader looks toward +Z, so the label flips PI. face=-1 flips
## it back for the south-bound reading of the roadside sign.
func _hospital_label(text: String, pos: Vector3, fsize: int, col: Color,
		face: float = 1.0, max_w: float = 40.0, max_h: float = 0.0,
		style: int = SIGN.FLAT) -> void:
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	lbl.rotation.y = PI if face > 0.0 else 0.0
	add_child(lbl)


## Flat unshaded paint stripe (no collision) — apron markings.
func _paint(size: Vector3, pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_mesh(size)
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	add_child(mi)


## Contracts for on_foot.gd's respawn: where Book walks out, and where the
## wrecker waits. Both face north (-Z), straight at downtown.
func get_hospital_spawn() -> Transform3D:
	return Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), HOSPITAL_DOOR)


func get_hospital_truck_spawn() -> Transform3D:
	return Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), HOSPITAL_TRUCK)


# ======================== DISTRICT LAYERS (M15) ==============================
## Visual-only dressing layers, one per district. FIXED order; a missing or
## parse-broken file is skipped (load() returns null on parse error — guarded)
## so the tree boots green while layers are still being written.
const EXTRA_LAYERS: Array[String] = [
	"res://scripts/world/plaza_dressing.gd",
	"res://scripts/world/suburb_dressing.gd",
	"res://scripts/world/freeway_dressing.gd",
	"res://scripts/world/wild_dressing.gd",
	"res://scripts/world/scenic_dressing.gd",
	"res://scripts/world/landmarks.gd",
	# M21 (defect D-023): downtown's architectural vocabulary. MUST stay LAST —
	# it re-skins the tower stack from the recorded segments, and it frees the
	# four tower MultiMeshes the M1 recipe emitted. Every layer that reads
	# get_tower_tops() / get_podium_xforms() (city_dressing's rooftop signs and
	# storefronts, plaza_dressing's planter rings) has to have placed its work
	# against the recorded numbers BEFORE the re-skin, because the re-skin
	# honours those numbers rather than republishing them.
	"res://scripts/world/downtown_types.gd",
]


func _build_extra_layers() -> void:
	for path: String in EXTRA_LAYERS:
		if not ResourceLoader.exists(path):
			continue
		var script: Variant = load(path)
		if not (script is GDScript):
			push_error("district layer FAILED TO PARSE, skipped: %s" % path)
			continue  # D-074: skip, but never silently
		var node: Variant = (script as GDScript).new()
		if not (node is Node3D):
			push_error("district layer is not a Node3D, skipped: %s" % path)
			continue
		(node as Node3D).name = path.get_file().get_basename()
		add_child(node as Node3D)
		if (node as Node3D).has_method("build"):
			(node as Node3D).call("build", self)


## M15 contracts for the suburb layer (read-only records; no rng replay).
func get_house_xforms() -> Array[Transform3D]:
	return _house_xforms.duplicate()


func get_house_sizes() -> Array[Vector3]:
	return _house_sizes.duplicate()


## Dressing contracts (read-only records; no rng replay needed).
func get_mall_slots() -> Array[Vector3]:
	return _mall_slots.duplicate()


func get_tower_tops() -> Array[Vector4]:
	return _tower_tops.duplicate()


## The roofs that can carry a skyline sign: ONE entry per tower — the highest
## recorded segment, carrying THAT segment's footprint.
##
## WHY THIS EXISTS (M22, screenshot-caught). `_tower_tops` records every glass
## segment over 55 m, and `_tower_visual` splits a setback tower into TWO
## segments at the same plan position — so a tall tower appears twice, once at
## its roof and once at its **setback ledge**. Both `city_dressing`
## (rooftop signs) and `downtown_types` (the `signed` flag) independently
## rebuilt a "six tallest" list off that array, so a sign could be planted on a
## ledge with the upper shaft standing right beside it, eating half the word:
## CLINGTEL read "LINGTEL" from anywhere north of it.
##
## `get_tower_tops()` is deliberately left alone — `plaza_dressing` rings the
## tower BASE with planters and needs the base footprint, which is the entry
## this list throws away.
func get_roof_signs() -> Array[Vector4]:
	var best: Dictionary = {}
	for t in _tower_tops:
		var k := "%.3f|%.3f" % [t.x, t.y]
		if not best.has(k) or (best[k] as Vector4).z < t.z:
			best[k] = t
	var out: Array[Vector4] = []
	for v: Variant in best.values():
		out.append(v as Vector4)
	out.sort_custom(func(a: Vector4, b: Vector4) -> bool: return a.z > b.z)
	return out


## M21 dressing contract (read-only record, no rng replay): every glass segment
## the tower recipe emitted, as `Basis.IDENTITY.scaled(size)` about its centre.
## Segments sharing an (x, z) are one tower; the base of the stack always sits
## at y = 0.1. This is what downtown_types.gd re-skins from — the alternative
## would be replaying `_build_downtown`'s draw order, which is frozen.
func get_tower_segments() -> Array[Transform3D]:
	return _tower_xforms.duplicate()


## M14 dressing contract (read-only record, no rng replay): the retail podium
## world transforms, for the storefront facade pass. Axis-aligned by build:
## basis is Basis.IDENTITY.scaled(size), origin the podium centre.
func get_podium_xforms() -> Array[Transform3D]:
	return _podium_xforms.duplicate()


# ================= STONEBRIDLE RANCH — SUBURB INFILL (M20) ===================
## DEFECT D-011: "the suburbs read as sparse". They do. The M1 layout drops one
## house per 95 x 80 m cell at p=0.42 — 54 houses across 91 hectares, no street
## network, and every front door facing a fiction. This pass keeps all of that
## untouched (the `rng` stream is a frozen contract) and builds a SECOND,
## denser layer on top of it: **Stonebridle Ranch** (naming bible §6 — the
## canon gated-HOA subdivision, and already the setting of the Hook and Ladder
## cul-de-sac), a real subdivision plat threaded through the gaps.
##
## THE PLAT, and why every number is what it is.
## The free space is fixed by two lattices this pass may not disturb: the M1
## house columns at x = -600 + 95k (occupying +-15 m of plan, +-24 m once
## suburb_dressing's driveways, aprons and fences are counted) and
## city_dressing's yard trees at x = col+40 +-14, z = row+40 +-14. That leaves a
## 65 m clear band between every pair of house columns, and the plat is 51 m
## wide, centred in it:
##
##   pod centreline   x = col + 47.5   (a row of houses, ridges running N-S)
##   lanes            x = pod +- 21    (9 m residential pavement)
##
## ONE ROW OF HOUSES BETWEEN TWO LANES, not two rows either side of one lane,
## and that is the whole trick. suburb_dressing picks which long wall is the
## FRONT from its own RNG (`fs`), and this pass may not edit that file — so a
## house on a one-lane street would put its door, driveway, mailbox and apron
## on the wrong side half the time. With pavement 21 m off BOTH long walls,
## whichever way the coin lands the driveway runs to a street. 21 m is derived,
## not chosen: suburb_dressing's dirt apron ends wall_off + 10.3 m out (15.8 m
## worst case), the pavement edge is at 4.5 m, so the apron dies 0.7 m short of
## the asphalt — which is exactly where a driveway apron dies.
##
## Everything else is a clearance check against something already on the map,
## and the smoke corridor is checked even though it is 250 m away, because that
## is the law and laws that are only enforced when convenient are not laws.
const INFILL_SEED := 771102          # M20 suburb infill ONLY — never `rng`
const SUB_POD_N := 13                # gaps between the 14 M1 house columns
const SUB_POD_X0 := -552.5           # = SUB_RECT.x + 47.5
const SUB_POD_PITCH := 95.0
const SUB_LANE_OFF := 21.0           # lane centreline off the house row
const SUB_LANE_HALF := 4.5           # 9 m of residential pavement
const SUB_LANE_Z := Vector2(-874.0, -198.0)      # lanes run the plat's depth
const SUB_CONNECTOR_Z: Array[float] = [-760.0, -520.0, -280.0]
const SUB_CONNECTOR_HALF := 5.5      # 11 m collector, centre-striped
const SUB_LOT_PITCH := 25.0
const SUB_LOT_Z := Vector2(-872.0, -200.0)
const SUB_TREE_CLEAR := 13.5         # house half-diagonal 9.0 + canopy reach 4.2
const SUB_HOUSE_CLEAR := 21.0        # two half-diagonals (8.51) plus eaves
const SUB_COURT := Vector3(587.5, -360.0, 13.0)  # Hook and Ladder cul-de-sac
const SUB_COURT_CLEAR := 40.0        # the wrecker needs room to swing a hook


func _build_suburb_infill() -> void:
	var irng := RandomNumberGenerator.new()
	irng.seed = INFILL_SEED
	var trees := _suburb_tree_spots()
	for k in SUB_POD_N:
		var pod_x := SUB_POD_X0 + SUB_POD_PITCH * float(k)
		var z := SUB_LOT_Z.x
		var run := 0
		var gap := 0
		while z <= SUB_LOT_Z.y:
			if run <= 0 and gap <= 0:
				run = irng.randi_range(5, 11)        # a platted phase
			if run > 0:
				run -= 1
				if run == 0:
					gap = irng.randi_range(2, 5)     # 50-125 m of raw dirt
				_try_lot(irng, pod_x, z, trees)
			else:
				gap -= 1
			z += SUB_LOT_PITCH


## One platted lot. Every draw happens BEFORE the clearance test so the RNG
## stream depends only on the plat, never on what the test decided — a rejected
## lot must not shift every house after it.
func _try_lot(irng: RandomNumberGenerator, pod_x: float, lot_z: float,
		trees: Array[Vector3]) -> void:
	var big := irng.randf() < 0.5
	var size: Vector3 = HOUSE_SIZES[0] if big else HOUSE_SIZES[1]
	# Ridge runs north-south so the long walls (and therefore the front, whichever
	# suburb_dressing picks) face the lanes: HOUSE_SIZES[0] is long in z already,
	# HOUSE_SIZES[1] is long in x and gets the quarter turn.
	var base_yaw := 0.0 if size.z >= size.x else PI * 0.5
	var yaw := base_yaw + PI * float(irng.randi_range(0, 1)) \
		+ irng.randf_range(-0.03, 0.03)
	# HOA-tight jitter on purpose: the M1 scatter is +-8 m of "cul-de-sac
	# sprawl", Stonebridle Ranch is approved beige on a surveyed setback.
	var pos := Vector3(pod_x + irng.randf_range(-0.8, 0.8), size.y * 0.5 - 0.1,
		lot_z + irng.randf_range(-1.0, 1.0))
	if not _lot_clear(pos, lot_z, trees):
		return
	_box(size, pos, mat_brick, Basis(Vector3.UP, yaw))
	# Recorded into the SAME arrays the M1 houses use, so suburb_dressing gives
	# every one of these roofs, chimneys, trim, glass, driveways, walks,
	# mailboxes, fences, sheds and porch lights for free.
	_house_xforms.append(Transform3D(Basis(Vector3.UP, yaw), pos))
	_house_sizes.append(size)


func _lot_clear(pos: Vector3, lot_z: float, trees: Array[Vector3]) -> bool:
	# The corridor is 250 m away and can never be hit from here. Checked anyway.
	if pos.x > 170.0 and pos.x < 216.0 and pos.z > 420.0 and pos.z < 580.0:
		return false
	if pos.z < SUB_RECT.position.y or pos.z > SUB_RECT.end.y:
		return false
	for cz: float in SUB_CONNECTOR_Z:               # keep the collector clear
		if absf(lot_z - cz) < 20.0:
			return false
	if Vector2(pos.x, pos.z).distance_to(Vector2(SUB_COURT.x, SUB_COURT.y)) \
			< SUB_COURT_CLEAR:
		return false
	for t in trees:                                  # city_dressing's yard trees
		if Vector2(pos.x, pos.z).distance_to(Vector2(t.x, t.z)) < SUB_TREE_CLEAR:
			return false
	for h in _house_xforms:                          # M1 houses AND earlier lots
		if Vector2(pos.x, pos.z).distance_to(Vector2(h.origin.x, h.origin.z)) \
				< SUB_HOUSE_CLEAR:
			return false
	return true


## Where city_dressing's suburb yard trees ended up AFTER its lane pass nudged
## the handful that stood in new pavement. Empty (and harmless) if the dressing
## layer is absent — the clearance test simply has nothing to avoid.
func _suburb_tree_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var d := get_node_or_null("CityDressing")
	if d == null or not d.has_method("get_suburb_tree_spots"):
		return out
	var got: Variant = d.call("get_suburb_tree_spots")
	if not (got is Array):
		return out
	for v: Variant in (got as Array):
		if v is Vector3:
			out.append(v as Vector3)
	return out


## THE PLAT, published. city_dressing's lane pass paints against exactly these
## numbers, so the pavement and the setbacks cannot drift apart.
func get_suburb_pod_x() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in SUB_POD_N:
		out.append(SUB_POD_X0 + SUB_POD_PITCH * float(k))
	return out


func get_suburb_lane_x() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for k in SUB_POD_N:
		var pod_x := SUB_POD_X0 + SUB_POD_PITCH * float(k)
		out.append(pod_x - SUB_LANE_OFF)
		out.append(pod_x + SUB_LANE_OFF)
	return out


func get_suburb_connector_z() -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for cz: float in SUB_CONNECTOR_Z:
		out.append(cz)
	return out


func get_suburb_lane_z() -> Vector2:
	return SUB_LANE_Z


## (x, z, bulb radius) of the Hook and Ladder cul-de-sac.
func get_suburb_court() -> Vector3:
	return SUB_COURT


func _shared_mesh(size: Vector3) -> BoxMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _mesh_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_mesh_cache[key] = bm
	return _mesh_cache[key]
