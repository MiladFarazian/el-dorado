extends Node3D
## SCENIC DRESSING (M16) — the land, not the city. Four things the skyline
## needed under it:
##   1. The world stops at a wall. An apron of prairie OUTSIDE the containment
##      ring carries the ground to the horizon, so the Megaplex sits in country
##      instead of on a table. Ring-shaped, never over the floodway cut.
##   2. A far treeline and a few low swells at the map edge — the Cross Timbers
##      reading as a soft dark line under the sky, fogging out with distance.
##   3. Colour breakup on the prairie: soil, caliche, red clay scrapes and
##      greener drainage draws, laid as chained soft-edged decals so the ground
##      reads as land rather than carpet.
##   4. Flora with SILHOUETTES, clustered ecologically: little bluestem bunches
##      in the draws, yucca standing alone, prickly pear in clumps, live-oak
##      motts in the open — the four things you actually see out a truck window
##      between Fort Verde and the county line.
## Plus the floodway's low-flow trickle: canon says NO WATER NEITHER, so it is
## a damp stain and a few shallow puddles, never a river.
##
## CONTRACT (house law): 100% visual — no collision, no physics, no _process,
## build-time only. One fresh RNG with its own literal seed; no gameplay or
## layout stream is touched. Repeated elements are MultiMeshes, one per
## archetype. Nothing spawns in the smoke corridor x[174,212] z[424,576], and
## everything on the channel floor stays under 0.02 m so the race line is flat.

const SEED := 616001
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const TEX := preload("res://scripts/world/city_textures.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")

# --- Layout constants mirrored from greybox_city.gd (that file is the source
# of truth; these are read-only copies, same as wild_dressing keeps).
const MAP_HALF := 1000.0
const CH_FLOOR := -6.0               # floodway floor top surface
const CH_MID_X := -620.0
const BRIDGE_Z: Array[float] = [300.0, 650.0]
const APRON_OUT := 2700.0            # outer edge of the far prairie apron
const RACE_PAD_Z := Vector2(136.0, 166.0)   # keep the start pad clean

# --- Prairie decal palette. Alpha is deliberately low: these are soil tones
# showing THROUGH the prairie texture, not paint on top of it.
const PATCH_KINDS: Array = [
	[Color(0.72, 0.68, 0.55), 0.34],   # caliche / exposed limestone
	[Color(0.33, 0.40, 0.22), 0.42],   # a draw holding moisture, greener
	[Color(0.54, 0.33, 0.20), 0.30],   # red clay scrape
	[Color(0.44, 0.39, 0.25), 0.32],   # burnt-off dry ground
]

var _rng := RandomNumberGenerator.new()
var _unit := BoxMesh.new()
var _draws: Array[Vector2] = []       # centres of kind-1 patches: wetter ground

# Instance buckets — one MultiMesh per archetype, flushed at the end of build.
var _patch_xf: Array[Transform3D] = []
var _patch_col: Array[Color] = []
var _far_xf: Array[Transform3D] = []          # distant treeline blobs + swells
var _far_col: Array[Color] = []
var _bunch_xf: Array[Transform3D] = []        # little bluestem
var _bunch_col: Array[Color] = []
var _yucca_xf: Array[Transform3D] = []
var _yucca_col: Array[Color] = []
var _stalk_xf: Array[Transform3D] = []        # yucca flower stalks
var _stalk_col: Array[Color] = []
var _pad_xf: Array[Transform3D] = []          # prickly pear pads
var _pad_col: Array[Color] = []
var _tuna_xf: Array[Transform3D] = []         # pear fruit
var _trunk_xf: Array[Transform3D] = []        # mott trees
var _trunk_col: Array[Color] = []
var _canopy_xf: Array[Transform3D] = []
var _canopy_col: Array[Color] = []
var _damp_xf: Array[Transform3D] = []         # trickle stain + margins
var _damp_col: Array[Color] = []
var _pool_xf: Array[Transform3D] = []         # standing water, such as it is
var _pool_col: Array[Color] = []


func build(city: Node3D) -> void:
	_rng.seed = SEED
	_unit.size = Vector3.ONE
	_far_apron(city)
	_far_treeline()
	_prairie_patches()
	_bunchgrass()
	_yucca()
	_prickly_pear()
	_motts()
	_low_flow_channel()
	_flush()


# ============================== THE FAR COUNTRY ==============================
## Prairie beyond the containment walls, as four strips forming a ring. A
## single big plane would slice straight through the floodway cut six metres
## above the race floor — the ring never crosses x[-1000,1000] z[-1000,1000],
## so the channel stays open sky-to-floor. Sunk to y=-0.05: that is INSIDE the
## 1 m ground slabs everywhere the real map exists, so it can only ever be seen
## past the edge, and it can never z-fight the ground you drive on.
func _far_apron(city: Node3D) -> void:
	var mat: Variant = city.get("mat_prairie") if city != null else null
	var pm: StandardMaterial3D = mat if mat is StandardMaterial3D else TEX.prairie_material()
	var span := APRON_OUT - MAP_HALF
	var mid := (APRON_OUT + MAP_HALF) * 0.5
	var strips: Array = [
		[Vector3(2.0 * APRON_OUT, 0.0, span), Vector3(0.0, -0.05, -mid)],
		[Vector3(2.0 * APRON_OUT, 0.0, span), Vector3(0.0, -0.05, mid)],
		[Vector3(span, 0.0, 2.0 * MAP_HALF), Vector3(-mid, -0.05, 0.0)],
		[Vector3(span, 0.0, 2.0 * MAP_HALF), Vector3(mid, -0.05, 0.0)],
	]
	for s: Array in strips:
		var size: Vector3 = s[0]
		var plane := PlaneMesh.new()
		plane.size = Vector2(size.x, size.z)
		var mi := MeshInstance3D.new()
		mi.name = "FarPrairie"
		mi.mesh = plane
		mi.material_override = pm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = s[1]
		add_child(mi)


## The Cross Timbers on the skyline: groves of squashed blobs ringing the map
## just past the walls, in two bands so the line has depth instead of reading
## as one cut-out. Colours are pre-hazed blue-green — atmospheric perspective
## baked in, then real fog and aerial perspective finish the job.
##
## Review lesson (first aerial): a 600 m x 20 m "rolling swell" rendered as a
## dark RING. Godot transforms instance normals by the transform basis, not by
## its inverse transpose, so a 30:1 non-uniform scale rotates every sloped
## normal almost flat — the dome's rim lit sideways while its top matched the
## ground. Blackland prairie is flat anyway. The swells are gone, and nothing
## here exceeds roughly 3:1.
## The ring is SQUARE, not circular. The map is a square: a circle of radius
## 1016 cuts INSIDE it at all four corners, which put 15 m tree blobs on the
## playable prairie near (840, 780) — caught in the first high shot, where they
## read as huge dark horseshoes. Walking the four sides guarantees every grove
## clears the wall on the axis it belongs to.
func _far_treeline() -> void:
	for band in 2:
		var groves := 320 if band == 0 else 200
		var d0 := 1022.0 if band == 0 else 1250.0
		var d1 := 1215.0 if band == 0 else 1600.0
		var reach := 1500.0 if band == 0 else 1600.0
		var scale := 1.0 if band == 0 else 1.9   # further band reads bigger
		for i in groves:
			if _rng.randf() < 0.14:
				continue                            # gaps: a treeline has holes
			var along := _rng.randf_range(-reach, reach)
			var out := _rng.randf_range(d0, d1)
			var cx := along
			var cz := -out
			match i % 4:
				1: cz = out
				2: cx = -out; cz = along
				3: cx = out; cz = along
			for k in _rng.randi_range(2, 5):
				var w := _rng.randf_range(11.0, 27.0) * scale
				var h := w * _rng.randf_range(0.34, 0.62)
				var ox := _rng.randf_range(-26.0, 26.0) * scale
				var oz := _rng.randf_range(-26.0, 26.0) * scale
				_far_xf.append(Transform3D(
					Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
					* Basis.from_scale(Vector3(w, h, w * _rng.randf_range(0.75, 1.2))),
					Vector3(cx + ox, h * 0.38, cz + oz)))
				var c := Color(0.19, 0.24, 0.21).lerp(Color(0.28, 0.31, 0.26), _rng.randf())
				if band == 1:
					c = c.lerp(Color(0.38, 0.43, 0.43), 0.38)   # further = hazier
				_far_col.append(c * _rng.randf_range(0.88, 1.10))


# ============================== PRAIRIE COLOUR ===============================
## Soil variation as chained decals. Each chain walks a slowly turning heading
## and drops overlapping ellipses, which is how soil actually varies — along
## drainage, in scrapes, in burn scars — instead of as isolated dots. Kind-1
## chains are remembered as "draws": the bunchgrass clusters follow them.
## Heights: 2.4-3.8 cm above the ground slabs. The first cut sat at 1.5 mm and
## simply VANISHED past a couple of hundred metres — a transparent decal writes
## no depth, so at long range float depth precision let the ground win the test.
## That puts these above wild_dressing's dirt tracks; the ruts still read fine
## through a 35%-alpha soil stain, which is the right way round anyway.
func _prairie_patches() -> void:
	# Pass 1: broad regional tone. A handful of very large, very faint fields —
	# this is what makes ground read as country at 500 m, where chain detail is
	# already below a pixel.
	var broad := 0
	var tries := 0
	while broad < 70 and tries < 700:
		tries += 1
		var bx := _rng.randf_range(-900.0, 900.0)
		var bz := _rng.randf_range(-900.0, 900.0)
		var br := _rng.randf_range(110.0, 250.0)
		if not _open(bx, bz, br):
			continue
		broad += 1
		var bk := _rng.randi_range(0, PATCH_KINDS.size() - 1)
		var bc: Color = PATCH_KINDS[bk][0] * _rng.randf_range(0.9, 1.1)
		bc.a = _rng.randf_range(0.12, 0.20)
		_patch_xf.append(Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			* Basis.from_scale(Vector3(br * 2.0, 1.0, br * _rng.randf_range(1.0, 1.8))),
			Vector3(bx, 0.024 if broad % 2 == 0 else 0.028, bz)))
		_patch_col.append(bc)
	# Pass 2: chains. Each walks a slowly turning heading and drops overlapping
	# ellipses, which is how soil actually varies — along drainage, in scrapes,
	# in burn scars — instead of as isolated dots. Kind-1 chains are remembered
	# as "draws": the bunchgrass clusters follow them.
	var chains := 0
	var attempts := 0
	while chains < 420 and attempts < 3600:
		attempts += 1
		var pos := Vector2(_rng.randf_range(-955.0, 955.0), _rng.randf_range(-955.0, 955.0))
		if not _open(pos.x, pos.y, 50.0):
			continue
		chains += 1
		var kind := _rng.randi_range(0, PATCH_KINDS.size() - 1)
		var base: Color = PATCH_KINDS[kind][0]
		var alpha: float = PATCH_KINDS[kind][1]
		var heading := _rng.randf_range(0.0, TAU)
		var links := _rng.randi_range(2, 7)
		for i in links:
			var rx := _rng.randf_range(20.0, 68.0)
			var rz := rx * _rng.randf_range(0.45, 1.0)
			if not _open(pos.x, pos.y, maxf(rx, rz) + 2.0):
				break
			var y := 0.032 if _patch_xf.size() % 2 == 0 else 0.038
			_patch_xf.append(Transform3D(
				Basis(Vector3.UP, heading + _rng.randf_range(-0.4, 0.4))
				* Basis.from_scale(Vector3(rx * 2.0, 1.0, rz * 2.0)),
				Vector3(pos.x, y, pos.y)))
			var c := base * _rng.randf_range(0.88, 1.12)
			c.a = alpha * _rng.randf_range(0.75, 1.2)
			_patch_col.append(c)
			if kind == 1:
				_draws.append(pos)
			heading += _rng.randf_range(-0.55, 0.55)
			pos += Vector2(cos(heading), sin(heading)) * rx * _rng.randf_range(0.7, 1.15)


# ============================== FLORA ========================================
## Little bluestem: the signature prairie bunchgrass, russet by late summer and
## twice the height of wild_dressing's ground tufts. Two thirds of the clumps
## are pulled toward a drainage draw, which is exactly where the tall grass is.
func _bunchgrass() -> void:
	var clusters := 0
	var attempts := 0
	while clusters < 300 and attempts < 1600:
		attempts += 1
		var cx: float
		var cz: float
		if not _draws.is_empty() and _rng.randf() < 0.66:
			var d: Vector2 = _draws[_rng.randi_range(0, _draws.size() - 1)]
			var a := _rng.randf_range(0.0, TAU)
			var r := _rng.randf_range(0.0, 46.0)
			cx = d.x + cos(a) * r
			cz = d.y + sin(a) * r
		else:
			cx = _rng.randf_range(-960.0, 960.0)
			cz = _rng.randf_range(-960.0, 960.0)
		if not _open(cx, cz, 9.0):
			continue
		clusters += 1
		for k in _rng.randi_range(7, 20):
			var a := _rng.randf_range(0.0, TAU)
			var r := 6.5 * sqrt(_rng.randf())
			var tx := cx + cos(a) * r
			var tz := cz + sin(a) * r
			if not _open(tx, tz, 1.0):
				continue
			var s := _rng.randf_range(0.62, 1.20)
			_bunch_xf.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
				* Basis.from_scale(Vector3(s * _rng.randf_range(0.85, 1.15),
					s * _rng.randf_range(0.9, 1.25), s * _rng.randf_range(0.85, 1.15))),
				Vector3(tx, -0.04, tz)))
			# Russet seed heads over a tired blue-green base.
			_bunch_col.append(Color(0.66, 0.48, 0.29).lerp(
				Color(0.54, 0.52, 0.33), _rng.randf()) * _rng.randf_range(0.88, 1.08))


## Yucca stands alone or in twos — never a field of it. A third throw up the
## cream flower stalk that makes the silhouette unmistakable at 200 m.
func _yucca() -> void:
	var placed := 0
	var attempts := 0
	while placed < 320 and attempts < 2200:
		attempts += 1
		var cx := _rng.randf_range(-965.0, 965.0)
		var cz := _rng.randf_range(-965.0, 965.0)
		if not _open(cx, cz, 3.0):
			continue
		for k in (2 if _rng.randf() < 0.28 else 1):
			var x := cx + _rng.randf_range(-2.4, 2.4)
			var z := cz + _rng.randf_range(-2.4, 2.4)
			if not _open(x, z, 1.5):
				continue
			placed += 1
			var s := _rng.randf_range(0.75, 1.35)
			_yucca_xf.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
				* Basis.from_scale(Vector3(s, s * _rng.randf_range(0.85, 1.2), s)),
				Vector3(x, -0.03, z)))
			_yucca_col.append(Color(0.47, 0.56, 0.41) * _rng.randf_range(0.85, 1.1))
			if _rng.randf() < 0.34:
				var sh := _rng.randf_range(1.1, 1.9) * s
				_stalk_xf.append(Transform3D(
					Basis.from_scale(Vector3(0.05, sh, 0.05)),
					Vector3(x, sh * 0.5, z)))
				_stalk_col.append(Color(0.55, 0.52, 0.40))
				_stalk_xf.append(Transform3D(
					Basis.from_scale(Vector3(0.20, sh * 0.34, 0.20)),
					Vector3(x, sh * 0.94, z)))
				_stalk_col.append(Color(0.86, 0.84, 0.72))


## Prickly pear: a clump of pads at wild angles, a few with magenta tunas on
## the rim. Pads are flat, so the clump reads as a cactus from any direction.
func _prickly_pear() -> void:
	var clumps := 0
	var attempts := 0
	while clumps < 190 and attempts < 1400:
		attempts += 1
		var cx := _rng.randf_range(-965.0, 965.0)
		var cz := _rng.randf_range(-965.0, 965.0)
		if not _open(cx, cz, 4.0):
			continue
		clumps += 1
		var green := Color(0.33, 0.47, 0.33).lerp(Color(0.40, 0.50, 0.30), _rng.randf())
		for k in _rng.randi_range(3, 7):
			var x := cx + _rng.randf_range(-1.1, 1.1)
			var z := cz + _rng.randf_range(-1.1, 1.1)
			var s := _rng.randf_range(0.45, 0.95)
			var yaw := _rng.randf_range(0.0, TAU)
			var tilt := _rng.randf_range(-0.45, 0.45)
			var b := Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), tilt) \
				* Basis.from_scale(Vector3(s, s, s))
			_pad_xf.append(Transform3D(b, Vector3(x, -0.02, z)))
			_pad_col.append(green * _rng.randf_range(0.85, 1.12))
			if _rng.randf() < 0.35:
				_tuna_xf.append(Transform3D(b * Basis.from_scale(Vector3(0.16, 0.16, 0.5)),
					Vector3(x, s * 1.02 - 0.02, z)))


## Live-oak motts: the islands of trees that punctuate open blackland. Wide,
## low, dense — a different plant from wild_dressing's scrappy leaning mesquite
## and from the street trees, so the eye can tell city from country.
func _motts() -> void:
	var motts := 0
	var attempts := 0
	while motts < 18 and attempts < 260:
		attempts += 1
		var cx := _rng.randf_range(-930.0, 930.0)
		var cz := _rng.randf_range(-930.0, 930.0)
		if not _open(cx, cz, 26.0):
			continue
		motts += 1
		for k in _rng.randi_range(3, 7):
			var a := _rng.randf_range(0.0, TAU)
			var r := 14.0 * sqrt(_rng.randf())
			var x := cx + cos(a) * r
			var z := cz + sin(a) * r
			var h := _rng.randf_range(3.4, 5.6)
			var lean := _rng.randf_range(-0.06, 0.06)
			_trunk_xf.append(Transform3D(
				Basis(Vector3(1, 0, 0), lean) * Basis.from_scale(Vector3(1, h, 1)),
				Vector3(x, h * 0.5, z)))
			_trunk_col.append(Color(0.29, 0.24, 0.19) * _rng.randf_range(0.85, 1.1))
			var spread := _rng.randf_range(5.4, 9.0)
			var leaf := Color(0.21, 0.30, 0.17).lerp(Color(0.27, 0.34, 0.19), _rng.randf())
			for lobe in _rng.randi_range(2, 4):
				var la := _rng.randf_range(0.0, TAU)
				var lr := spread * _rng.randf_range(0.0, 0.30)
				var lw := spread * _rng.randf_range(0.62, 1.0)
				_canopy_xf.append(Transform3D(
					Basis.from_scale(Vector3(lw, lw * _rng.randf_range(0.60, 0.84),
						lw * _rng.randf_range(0.8, 1.15))),
					Vector3(x + cos(la) * lr, h * _rng.randf_range(0.98, 1.24),
						z + sin(la) * lr)))
				_canopy_col.append(leaf * _rng.randf_range(0.82, 1.14))


# ============================== THE LOW-FLOW CHANNEL =========================
## "NO SWIMMING / NO WATER NEITHER" is canon and the stencils on the bank say
## so. What a real concrete floodway holds between storms is a damp trickle in
## the centre notch and a few standing puddles, and that is exactly all this
## is: a stain 1 cm proud of a floor that is also a race track. Everything here
## is under 0.02 m, has no collider, and is dark and low-contrast so it never
## competes with the racing pylons. Skipped across the start pad and the
## centreline jump so neither reads as wet.
func _low_flow_channel() -> void:
	var z := 112.0
	while z < 986.0:
		var seg := 8.0
		var cx := CH_MID_X + sin(z * 0.0125) * 2.4 + sin(z * 0.041) * 0.8
		if not (z > RACE_PAD_Z.x and z < RACE_PAD_Z.y) and not (z > 548.0 and z < 572.0):
			# Per-segment jitter on top of the sine: a purely analytic width gave
			# two dead-straight parallel algae lines running a kilometre, which
			# read as paint. Water does not do that.
			var w := (1.05 + 0.40 * (0.5 + 0.5 * sin(z * 0.031))) * _rng.randf_range(0.82, 1.22)
			var wet := _rng.randf_range(0.88, 1.14)
			# Damp margin first (wider, fainter), then the wet core over it.
			# First cut ran a 3.4x margin plus fat algae fringes and read as an
			# 8 m smear down the race line — a low-flow notch is NARROW.
			_damp_xf.append(Transform3D(
				Basis.from_scale(Vector3(w * 2.2, 1.0, seg + 0.4)),
				Vector3(cx, CH_FLOOR + 0.008, z + seg * 0.5)))
			_damp_col.append(Color(0.34, 0.35, 0.31, 0.16 * wet))
			_damp_xf.append(Transform3D(
				Basis.from_scale(Vector3(w, 1.0, seg + 0.4)),
				Vector3(cx, CH_FLOOR + 0.012, z + seg * 0.5)))
			_damp_col.append(Color(0.10, 0.13, 0.12, 0.52 * wet))
			# Algae fringe: the thin green line at the waterline. Broken, not
			# continuous — a third of the segments simply have none.
			for side: float in [-1.0, 1.0]:
				if _rng.randf() < 0.34:
					continue
				_damp_xf.append(Transform3D(
					Basis.from_scale(Vector3(w * _rng.randf_range(0.16, 0.30),
						1.0, seg + 0.4)),
					Vector3(cx + side * w * _rng.randf_range(0.52, 0.70),
						CH_FLOOR + 0.015, z + seg * 0.5)))
				_damp_col.append(Color(0.20, 0.29, 0.14, _rng.randf_range(0.24, 0.40)))
		z += seg
	# Standing water: small, shallow, and glossy enough to hold the sky.
	var pools := 0
	var tries := 0
	while pools < 16 and tries < 200:
		tries += 1
		var pz := _rng.randf_range(180.0, 970.0)
		if (pz > RACE_PAD_Z.x and pz < RACE_PAD_Z.y) or (pz > 540.0 and pz < 580.0):
			continue
		var near_bridge := false
		for bz: float in BRIDGE_Z:
			if absf(pz - bz) < 14.0:
				near_bridge = true
		if near_bridge:
			continue
		pools += 1
		var px := CH_MID_X + sin(pz * 0.0125) * 2.4 + _rng.randf_range(-1.4, 1.4)
		_pool_xf.append(Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			* Basis.from_scale(Vector3(_rng.randf_range(1.6, 3.4), 1.0,
				_rng.randf_range(2.4, 6.0))),
			Vector3(px, CH_FLOOR + 0.018, pz)))
		_pool_col.append(Color(0.10, 0.13, 0.13, 0.72))


# ============================== PLACEMENT RULES ==============================
## Open prairie test, expanded by a radius so a 44 m decal cannot creep onto a
## street the way a centre-point test would let it. Zones mirror the ones
## wild_dressing uses, plus reserves around the landmark sites so a concurrent
## layer never finds a live oak in its churchyard.
func _open(x: float, z: float, r: float) -> bool:
	if absf(x) + r > 978.0 or absf(z) + r > 978.0:
		return false                                        # containment walls
	if x + r > 96.0 and x - r < 794.0 and z + r > 36.0 and z - r < 570.0:
		return false                                        # downtown street bed
	if absf(z) - r < 62.0 and absf(x) - r < 820.0:
		return false                                        # freeway/frontage/malls
	if x + r > -615.0 and x - r < 715.0 and z + r > -900.0 and z - r < -168.0:
		return false                                        # suburb fringe + yards
	if x + r > -716.0 and x - r < -524.0 and z + r > 94.0:
		return false                                        # the channel + rims
	if x + r > -510.0 and x - r < 110.0 and z + r > 630.0 and z - r < 950.0:
		return false                                        # Cedar Cliff (D-068): the blocks and the boulevard
	for bz: float in BRIDGE_Z:
		if x + r > -746.0 and x - r < -494.0 and absf(z - bz) < 10.0 + r:
			return false                                    # bridge approach decks
	if x + r > 330.0 and x - r < 400.0 and z + r > 552.0 and z - r < 652.0:
		return false                                        # County General campus
	if x + r > 170.0 and x - r < 216.0 and z + r > 420.0 and z - r < 580.0:
		return false                                        # smoke corridor (sacred)
	if x + r > 60.0 and x - r < 240.0 and z + r > 596.0 and z - r < 824.0:
		return false                                        # landmark reserve, south
	if x + r > 516.0 and x - r < 780.0 and z + r > 616.0 and z - r < 864.0:
		return false                                        # landmark reserve, east
	return true


# ============================== MESHES + FLUSH ===============================
## Little bluestem: four blades and a seed stalk, crossed. Same law as the
## ground tufts — normals forced UP so a SHADED material lets every blade take
## the terrain's light, sunlit at noon and properly dark at midnight.
static func _bunch_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var blades: Array = [
		[-0.24, -0.08, -0.32, 0.80], [-0.12, 0.04, -0.04, 1.08],
		[0.00, 0.16, 0.18, 0.92], [0.10, 0.26, 0.36, 0.64],
		[-0.05, 0.05, 0.02, 1.38],
	]
	for b: Array in blades:
		st.add_vertex(Vector3(b[0], 0, 0)); st.add_vertex(Vector3(b[1], 0, 0))
		st.add_vertex(Vector3(b[2], b[3], 0))
		st.add_vertex(Vector3(0, 0, b[0])); st.add_vertex(Vector3(0, 0, b[1]))
		st.add_vertex(Vector3(0, b[3], b[2]))
	return st.commit()


## Yucca: a rosette of stiff blades radiating out and up from the crown. The
## droop varies per blade so the star silhouette is irregular, not a logo.
static func _yucca_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	var n := 13
	for i in n:
		var a := TAU * float(i) / float(n)
		var d := Vector3(cos(a), 0.0, sin(a))
		var lean := 0.22 + 0.20 * float(i % 4)
		var tip := d * lean * 1.6 + Vector3.UP * (0.95 - lean * 0.5)
		var side := Vector3(-d.z, 0.0, d.x) * 0.055
		st.add_vertex(side); st.add_vertex(-side); st.add_vertex(tip)
	return st.commit()


## Prickly pear pad: a flat nine-gon standing on its base point, so the
## instance origin can sit on the ground and the pad tilts around it.
static func _pad_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	var n := 9
	var c := Vector3(0.0, 0.54, 0.0)
	for i in n:
		var a0 := TAU * float(i) / float(n)
		var a1 := TAU * float(i + 1) / float(n)
		st.add_vertex(c)
		st.add_vertex(c + Vector3(cos(a0) * 0.40, sin(a0) * 0.52, 0.0))
		st.add_vertex(c + Vector3(cos(a1) * 0.40, sin(a1) * 0.52, 0.0))
	return st.commit()


func _flush() -> void:
	var quad := PlaneMesh.new()          # 1x1 in XZ, facing +Y
	quad.size = Vector2.ONE
	var blob := MESH_KIT.canopy(0.5, 6, 10, 11, 0.22, 0.08)   # M23: lobed motts + far treeline; 6x10 — distance objects, cost-bound (D-046)
	var trunk := MESH_KIT.round_limb(0.16, 0.11, 1.0, 6)
	# Ground decals: alpha, shaded (soil is not luminous — the night pass on
	# every previous layer caught unshaded ground glowing), and shadow-free,
	# because a flat quad lying on the terrain that casts shadows is just acne.
	var patch_mat := StandardMaterial3D.new()
	patch_mat.albedo_texture = TEX.prairie_patch_texture()
	patch_mat.albedo_color = Color.WHITE
	patch_mat.vertex_color_use_as_albedo = true
	patch_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	patch_mat.texture_repeat = false
	patch_mat.roughness = 1.0
	_mm(quad, _patch_xf, _patch_col, patch_mat, "PrairiePatches", false)
	_mm(blob, _far_xf, _far_col, _mat(0.98), "FarTreeline", false)
	# SCATTER FLORA IS SHADOW-FREE (D-028). Bluestem, yucca and pear pads are
	# all TWO-SIDED CARD geometry — flat triangles with no thickness. The shadow
	# map has no alpha and no thickness either, so what a caster actually
	# renders is a hard black shard, and 5,246 of them were being pushed through
	# every cascade because one tuft on screen brings the whole prairie. Stalks
	# (50 mm) and tunas (0.16 m fruit stuck on a pad) are below the cascade's
	# resolving power at any range the player ever sees them from.
	_mm(_bunch_mesh(), _bunch_xf, _bunch_col, _mat(1.0, true), "Bluestem", false)
	_mm(_yucca_mesh(), _yucca_xf, _yucca_col, _mat(1.0, true), "Yucca", false)
	_mm(_unit, _stalk_xf, _stalk_col, _mat(0.92), "YuccaStalks", false)
	_mm(_pad_mesh(), _pad_xf, _pad_col, _mat(0.88, true), "PricklyPear", false)
	_mm(_unit, _tuna_xf, [], _flat(Color(0.62, 0.14, 0.30), 0.7),
		"PearTunas", false)
	# The motts KEEP theirs. They are solid limb-and-blob trees, not cards, and
	# an island of live oaks throwing shade across open blackland is the whole
	# reason the mott exists — 341 instances is a bargain for it.
	_mm(trunk, _trunk_xf, _trunk_col, _mat(0.95), "MottTrunks", true)
	_mm(blob, _canopy_xf, _canopy_col, _mat(0.95), "MottCanopies", true)
	# The trickle. Shaded and alpha so it darkens with the floor at night; the
	# puddles get their own glossier material so they hold a sky highlight.
	_mm(quad, _damp_xf, _damp_col, TEX.wet_concrete_material(false), "Trickle", false)
	_mm(quad, _pool_xf, _pool_col, TEX.wet_concrete_material(true), "TricklePools", false)
	_apply_wind()


## M23 VEGETATION WIND (append-only; material assignment ONLY). Every layer
## below is already built, already populated and already carries its D-028
## `casts` answer — this swaps `material_override` on the finished
## MultiMeshInstance3D by NAME and touches nothing else. No transform, no RNG
## draw, no instance count and no shadow flag changes, which is the only way a
## visual pass is allowed near a seeded layer.
##
## SHADOW POLICY RESTATED AT THE CALL SITE, because that is the rule (D-028):
## Bluestem, Yucca and PricklyPear are two-sided card flora and stay
## `casts` = false — set by `_mm` above, untouched here. MottCanopies keep the
## caster they were given; a moving canopy casting a moving shadow is the point
## of an island of live oaks.
##
## The numbers are metres of tip sway per unit of lever, at gust 0. A 0.5 m
## bunchgrass at sway 0.30 tips 75 mm; a yucca's sword leaves are stiff and get
## a third of that; a prickly-pear pad is a slab of water and barely moves.
func _apply_wind() -> void:
	SHD.apply_wind(self, "Bluestem", 1.0, true, 0.30, 0.45, 1.90, 0.05)
	SHD.apply_wind(self, "Yucca", 1.0, true, 0.10, 0.16, 1.55, 0.02)
	SHD.apply_wind(self, "PricklyPear", 0.88, true, 0.04, 0.07, 1.20, 0.0)
	# rigid_mix 1.0: the canopy blob's local origin is its own centre, so the
	# cantilever term would shear the crown against itself. A live oak sways
	# about a trunk that is not in this mesh.
	SHD.apply_wind(self, "MottCanopies", 0.88, false, 0.05, 0.10, 0.75, 0.0, 1.0, true, 11)


func _mat(rough: float, two_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func _flat(col: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	return m


## D-028: `shadows` lost its `= true` default. This layer already had the flag
## and still shipped 6,142 casting instances, because a default is a decision
## nobody makes. Every call site now states its answer.
func _mm(mesh: Mesh, xf: Array[Transform3D], cols: Array[Color],
		mat: StandardMaterial3D, label: String, shadows: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		if not cols.is_empty():
			# Instance colours skip the sRGB->linear pass albedo_color gets, so
			# raw values render washed out (the M15 finding). Alpha is untouched.
			var c := cols[i].srgb_to_linear()
			c.a = cols[i].a
			mm.set_instance_color(i, c)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not shadows:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
