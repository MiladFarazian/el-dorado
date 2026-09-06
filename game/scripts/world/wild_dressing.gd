extends Node3D
## WILD DRESSING (M15) — the Threefork Floodway + the open prairie.
## Two districts, one layer: the race channel gets its urban-wild identity
## (graffiti pieces and tags from the canon registry, the high-water bathtub
## ring, outfall pipes, depth gauges, edge debris) and the prairie stops being
## a tan void (grass tuft clusters, mesquite scrub stands, dirt two-track
## roads, a broken wire fence, tumbleweeds).
##
## CONTRACT (house law): 100% visual — no collision, no physics, no _process,
## build-time only. Fresh RNG with its own literal seed; the frozen M1 draw
## streams are never touched. Repeated elements are MultiMeshes (one per
## archetype); unique lettering is cheap Label3D nodes. The channel FLOOR is
## the Floodway Sprint race arena: floor objects stay pinned to the bank toes
## (x < -688 or x > -552) and flat paint only appears near the channel ends.
## Nothing spawns in the smoke corridor x[174,212] z[424,576].
##
## Review lessons baked in (screenshot-caught, per D-011 discipline):
## - MultiMesh instance colors reach the shader RAW (no sRGB->linear pass,
##   unlike albedo_color), so authored colors render washed-out bright. _mm()
##   converts every instance color with srgb_to_linear() — khaki stays khaki.
## - The banks are ~14-degree planes seen nearly edge-on from the race floor:
##   bank art must be HUGE (30 m pieces, 3 m ring band) or it vanishes.
## - A grass tuft drawn as a solid quad reads as a pale sign; the mesh needs a
##   jagged blade silhouette.

const SIGN := preload("res://scripts/world/sign_kit.gd")
const SEED := 555003
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")

# --- Channel geometry, mirrored from greybox_city.gd (layout source of truth).
# Bank SURFACE endpoints as (x, y): the _ramp() calls' bottom/top points.
const CH_MID_X := -620.0
const W_TOE := Vector2(-685.0, -6.05)      # west bank: toe on the floor
const W_RIM := Vector2(-709.6, 0.09)       # west bank: crest at the prairie rim
const E_TOE := Vector2(-555.0, -6.05)
const E_RIM := Vector2(-530.4, 0.09)
const CH_ZA := 106.0                       # banks' north end (past the mouth bank)
const CH_ZB := 994.0
const END_TOE := Vector2(126.0, -6.05)     # mouth end-bank surface as (z, y)
const END_RIM := Vector2(100.6, 0.09)
const BRIDGE_Z: Array[float] = [300.0, 650.0]
const COLUMN_X: Array[float] = [-680.0, -620.0, -560.0]

# --- Canon lettering (docs/design/naming-bible.md — never invent names).
# Big block-letter pieces: [text, fill color, backer color]. All canon or
# canon-adjacent: Candyland C.C. (§8), the Candyland Slab (§7a), "the Big
# Empty" (§4 vernacular for this very channel), the Bottomland Riders (§8),
# T-GRID's slogan thrown back at it (§7), Bolo Capital's "We Own That Too"
# (§8), Trail Ride Traxx 88.1 (§9), Deep Elm (§3). Satire punches at
# institutions; the drought gag punches at the sky.
const PIECES: Array = [
	["CANDYLAND", Color(0.92, 0.45, 0.72), Color(0.16, 0.72, 0.70)],
	["SLAB LIFE", Color(0.72, 0.52, 0.94), Color(0.97, 0.83, 0.28)],
	["BIG EMPTY", Color(0.94, 0.92, 0.86), Color(0.12, 0.12, 0.14)],
	["BOTTOMLAND RIDERS", Color(0.95, 0.76, 0.26), Color(0.42, 0.20, 0.10)],
	["THE GRID IS FINE", Color(0.96, 0.55, 0.16), Color(0.10, 0.10, 0.11)],
	["PRAY 4 RAIN", Color(0.55, 0.78, 0.94), Color(0.10, 0.18, 0.30)],
	["BOLO OWNS THIS TOO", Color(0.46, 0.88, 0.55), Color(0.08, 0.14, 0.10)],
	["TRAXX 88.1", Color(0.90, 0.30, 0.25), Color(0.94, 0.90, 0.80)],
	["DEEP ELM", Color(0.30, 0.60, 0.92), Color(0.92, 0.88, 0.78)],
]
const TAGS: Array[String] = ["CCC", "slab", "big empty", "traxx 88.1",
	"rustlers: 0 rings", "CANDYLAND", "bolo owns u", "the hook", "SLAB",
	"pray 4 rain"]
const COL_TAGS: Array[String] = ["CCC", "slab", "SLAB", "ccc"]  # fit 2 m faces
const SPRAY: Array[Color] = [Color(0.92, 0.45, 0.72), Color(0.20, 0.75, 0.72),
	Color(0.72, 0.52, 0.94), Color(0.96, 0.55, 0.16), Color(0.94, 0.90, 0.84),
	Color(0.45, 0.88, 0.55), Color(0.90, 0.30, 0.26), Color(0.98, 0.83, 0.28),
	Color(0.35, 0.55, 0.90)]

var _rng := RandomNumberGenerator.new()
var _unit := BoxMesh.new()
var _road_pts: Array[Vector2] = []         # dirt-road midpoints, for thinning
var _route2: Array[Vector2] = []           # fence follows this polyline

# Instance buckets — one MultiMesh per archetype, flushed at the end of build.
var _blob_xf: Array[Transform3D] = []      # graffiti throw-up fields (opaque)
var _blob_col: Array[Color] = []
var _stain_xf: Array[Transform3D] = []     # ring/drips/outfall stains (alpha)
var _stain_col: Array[Color] = []
var _paint_xf: Array[Transform3D] = []     # floor paint near the ends (alpha)
var _paint_col: Array[Color] = []
var _board_xf: Array[Transform3D] = []     # yellow depth-gauge boards
var _pipe_xf: Array[Transform3D] = []      # outfall pipe stubs
var _mouth_xf: Array[Transform3D] = []     # dark pipe mouths
var _tire_xf: Array[Transform3D] = []
var _tire_col: Array[Color] = []
var _wood_xf: Array[Transform3D] = []      # driftwood planks + pallets
var _wood_col: Array[Color] = []
var _weed_xf: Array[Transform3D] = []      # tumbleweeds (channel + prairie)
var _weed_col: Array[Color] = []
var _tuft_xf: Array[Transform3D] = []      # prairie grass
var _tuft_col: Array[Color] = []
var _trunk_xf: Array[Transform3D] = []     # mesquite
var _trunk_col: Array[Color] = []
var _bush_xf: Array[Transform3D] = []
var _bush_col: Array[Color] = []
var _track_xf: Array[Transform3D] = []     # dirt two-track strips
var _track_col: Array[Color] = []
var _post_xf: Array[Transform3D] = []      # fence
var _post_col: Array[Color] = []
var _wire_xf: Array[Transform3D] = []


func build(_city: Node3D) -> void:
	_rng.seed = SEED
	_unit.size = Vector3.ONE
	# Channel first, then prairie (roads before grass: tufts thin near them).
	_channel_graffiti()
	_channel_ring_and_drips()
	_channel_outfalls()
	_channel_depth_boards()
	_channel_floor_paint()
	_channel_stencils()
	_channel_debris()
	_dirt_roads()
	_fence_line()
	_prairie_grass()
	_prairie_scrub()
	_prairie_weeds()
	_flush()


# ============================ BANK PLUMBING ==================================
## The levee banks are ~14-degree planes. Everything painted "on" a bank is a
## thin box lying in that plane, positioned by (t, z): t=0 at the floor toe,
## t=1 at the prairie rim, z free along the channel.
func _bank_pt(east: bool, t: float, z: float) -> Vector3:
	var toe := E_TOE if east else W_TOE
	var rim := E_RIM if east else W_RIM
	return Vector3(lerpf(toe.x, rim.x, t), lerpf(toe.y, rim.y, t), z)


func _bank_up(east: bool) -> Vector3:      # unit up-slope direction
	var toe := E_TOE if east else W_TOE
	var rim := E_RIM if east else W_RIM
	return Vector3(rim.x - toe.x, rim.y - toe.y, 0.0).normalized()


func _bank_normal(east: bool) -> Vector3:  # unit out-of-surface, +y hemisphere
	var u := _bank_up(east)
	var n := Vector3(u.y, -u.x, 0.0)
	return -n if n.y < 0.0 else n


## Rotation for a box lying on the bank: local X along the channel, local Y
## out of the surface (thickness), local Z down-slope. Right-handed.
func _bank_rot(east: bool) -> Basis:
	var r := Vector3(0, 0, 1.0 if east else -1.0)
	return Basis(r, _bank_normal(east), -_bank_up(east))


## Rotation for text lying on the bank, readable from inside the channel.
func _bank_text_rot(east: bool) -> Basis:
	var r := Vector3(0, 0, 1.0 if east else -1.0)
	return Basis(r, _bank_up(east), _bank_normal(east))


func _bank_t_for_y(y: float) -> float:     # both banks share toe/rim heights
	return (y - W_TOE.y) / (W_RIM.y - W_TOE.y)


## Ground height ON the lower bank at world x (debris sits on this).
func _bank_y_at_x(east: bool, x: float) -> float:
	var toe := E_TOE if east else W_TOE
	var rim := E_RIM if east else W_RIM
	return lerpf(toe.y, rim.y, clampf((x - toe.x) / (rim.x - toe.x), 0.0, 1.0))


## One painted patch on a bank: w along the channel, h along the slope, lifted
## off the plane by `lift` (distinct lifts = the z-fighting law). Optional
## in-plane roll for the hand-sprayed look.
func _bank_patch(bucket: Array[Transform3D], east: bool, t: float, z: float,
		w: float, h: float, lift: float, roll := 0.0) -> void:
	var rot := _bank_rot(east)
	if roll != 0.0:
		rot = rot * Basis(Vector3(0, 1, 0), roll)
	bucket.append(Transform3D(rot * Basis.from_scale(Vector3(w, 0.02, h)),
		_bank_pt(east, t, z) + _bank_normal(east) * lift))


# ============================ CHANNEL GRAFFITI ===============================
## Block-letter pieces over layered throw-up fields, plus scattered tags. The
## banks are near-horizontal, so the work reads like the huge ground murals of
## a real drainage channel — and it is SIZED like them: 20-34 m pieces, or the
## edge-on view from the race floor turns them into slivers.
func _channel_graffiti() -> void:
	for i in 14:
		var e: Array = PIECES[i % PIECES.size()]
		var fill: Color = e[1]
		var back: Color = e[2]
		if i >= PIECES.size():             # second lap: same words, new crew colors
			fill = SPRAY[(i * 2) % SPRAY.size()]
			back = SPRAY[(i * 5 + 3) % SPRAY.size()] * 0.55
		var z := 150.0 + 60.0 * float(i) + _rng.randf_range(-14.0, 14.0)
		for bz in BRIDGE_Z:                # nudge clear of the bridge decks
			if absf(z - bz) < 22.0:
				z = bz + (24.0 if z > bz else -24.0)
		var east := i % 2 == 0
		var text: String = e[0]
		var width := clampf(2.6 * float(text.length()) + 6.0, 12.0, 34.0)
		# Backer field: 4-6 overlapping patches at stepped lifts.
		var n_back := _rng.randi_range(4, 6)
		for k in n_back:
			_bank_patch(_blob_xf, east, _rng.randf_range(0.16, 0.66),
				z + _rng.randf_range(-width * 0.35, width * 0.35),
				width * _rng.randf_range(0.35, 0.75),
				_rng.randf_range(3.0, 5.5), 0.055 + 0.005 * float(k),
				_rng.randf_range(-0.08, 0.08))
			_blob_col.append(back.lerp(fill, _rng.randf_range(0.0, 0.25))
				* _rng.randf_range(0.8, 1.0))
		# The letters themselves — mid-bank, heroic scale.
		_graffiti_label(text, _bank_pt(east, 0.40, z)
			+ _bank_normal(east) * 0.11, _bank_text_rot(east)
			* Basis(Vector3(0, 0, 1), _rng.randf_range(-0.05, 0.05)),
			width, 420, fill, back * 0.4)
		# Colored drips running down-slope from the letter base.
		for k2 in _rng.randi_range(2, 4):
			var dz := z + _rng.randf_range(-width * 0.4, width * 0.4)
			_bank_patch(_stain_xf, east, _rng.randf_range(0.10, 0.24), dz,
				_rng.randf_range(0.15, 0.4), _rng.randf_range(1.6, 4.0), 0.075)
			var dc := fill * 0.7
			dc.a = 0.5
			_stain_col.append(dc)
	# Standalone throw-up clusters between the pieces (both banks breathe).
	for i2 in 20:
		var east3 := _rng.randf() < 0.5
		var cz := _rng.randf_range(CH_ZA + 18.0, CH_ZB - 18.0)
		var blocked3 := false
		for bz3 in BRIDGE_Z:
			if absf(cz - bz3) < 14.0:
				blocked3 = true
		if blocked3:
			continue
		for k3 in _rng.randi_range(2, 4):
			_bank_patch(_blob_xf, east3, _rng.randf_range(0.10, 0.55),
				cz + _rng.randf_range(-4.0, 4.0), _rng.randf_range(2.5, 6.0),
				_rng.randf_range(1.2, 2.6), 0.052 + 0.005 * float(k3),
				_rng.randf_range(-0.12, 0.12))
			_blob_col.append(SPRAY[_rng.randi_range(0, SPRAY.size() - 1)]
				* _rng.randf_range(0.7, 1.0))
	# Tag scribbles: small, crooked, everywhere on the lower banks.
	for i4 in 26:
		var east2 := _rng.randf() < 0.5
		var tz := _rng.randf_range(CH_ZA + 20.0, CH_ZB - 20.0)
		var skip := false
		for bz2 in BRIDGE_Z:
			if absf(tz - bz2) < 12.0:
				skip = true
		if skip:
			continue
		_graffiti_label(TAGS[i4 % TAGS.size()],
			_bank_pt(east2, _rng.randf_range(0.08, 0.55), tz)
			+ _bank_normal(east2) * 0.095, _bank_text_rot(east2)
			* Basis(Vector3(0, 0, 1), _rng.randf_range(-0.18, 0.18)),
			_rng.randf_range(3.5, 6.5), 240,
			SPRAY[_rng.randi_range(0, SPRAY.size() - 1)], Color(0, 0, 0, 0.6))
	# Bridge columns: vertical throw-ups facing the race line, a tag on some.
	for bz4 in BRIDGE_Z:
		for cx in COLUMN_X:
			for s: float in [-1.0, 1.0]:
				for k4 in _rng.randi_range(1, 2):
					var c := SPRAY[_rng.randi_range(0, SPRAY.size() - 1)]
					_blob_xf.append(Transform3D(
						Basis(Vector3(0, 0, 1), _rng.randf_range(-0.1, 0.1))
						* Basis.from_scale(Vector3(_rng.randf_range(1.3, 1.9),
							_rng.randf_range(1.2, 2.4), 0.03)),
						Vector3(cx + _rng.randf_range(-0.05, 0.05),
							_rng.randf_range(-4.4, -2.4),
							bz4 + s * (1.0 + 0.03 + 0.012 * float(k4)))))
					_blob_col.append(c * _rng.randf_range(0.75, 1.0))
				if _rng.randf() < 0.5:
					var word := COL_TAGS[_rng.randi_range(0, COL_TAGS.size() - 1)]
					# M22: the fit budget was 1.8 m but a deck column face is
					# 1.69 m, so CCC ran past the concrete onto open air.
					var lbl := SIGN.make(word, SIGN.HANDPAINT,
						SPRAY[_rng.randi_range(0, SPRAY.size() - 1)],
						1.58, 0.0, 90)
					lbl.shaded = true
					lbl.position = Vector3(cx, _rng.randf_range(-3.6, -1.8),
						bz4 + s * 1.09)
					lbl.rotation.y = 0.0 if s > 0.0 else PI
					add_child(lbl)


## The high-water "bathtub ring": a continuous stain band both banks carry at
## y=-2 (one big storm, years ago), a fainter older line below, and dark
## streaks bleeding down-slope. The ring rides ABOVE the graffiti lifts —
## the water came after the paint.
func _channel_ring_and_drips() -> void:
	for east: bool in [false, true]:
		for ring in 2:
			var t := _bank_t_for_y(-2.0 if ring == 0 else -2.9)
			var alpha := 0.42 if ring == 0 else 0.18
			var z := CH_ZA
			var k := 0
			while z < CH_ZB:
				var w := minf(30.0, CH_ZB - z)
				_bank_patch(_stain_xf, east, t, z + w * 0.5, w,
					3.2 if ring == 0 else 1.6,
					(0.09 if ring == 0 else 0.086) + 0.003 * float(k % 2))
				_stain_col.append(Color(0.15, 0.12, 0.09, alpha))
				z += w
				k += 1
		# Dark streaks bleeding down-slope from the main ring.
		var t_ring := _bank_t_for_y(-2.0)
		var sz := CH_ZA + 6.0
		while sz < CH_ZB - 6.0:
			var dt := _rng.randf_range(0.12, 0.4)
			_bank_patch(_stain_xf, east, t_ring - dt * 0.5, sz,
				_rng.randf_range(0.3, 0.8), dt * 25.4, 0.084)
			_stain_col.append(Color(0.12, 0.10, 0.08, _rng.randf_range(0.22, 0.45)))
			sz += _rng.randf_range(6.0, 16.0)


## Storm-drain outfalls: concrete stubs poking out of the lower banks with a
## dark mouth and the green-brown drool every dry channel wears below them.
## Mouths stay over the bank (west < -688, east > -552): race floor is clean.
func _channel_outfalls() -> void:
	for east: bool in [false, true]:
		var z := 165.0 + _rng.randf_range(-15.0, 15.0)
		while z < CH_ZB - 30.0:
			var blocked := false
			for bz in BRIDGE_Z:
				if absf(z - bz) < 20.0:
					blocked = true
			if not blocked:
				var dir := -1.0 if east else 1.0   # mouth points into the channel
				var p := _bank_pt(east, 0.22, z)
				var rot := Basis(Vector3(0, 0, 1), dir * -PI * 0.5)
				_pipe_xf.append(Transform3D(rot, p))
				# Mouth disc sits PROUD of the pipe's end cap (the prism is a
				# closed solid — a disc inside it would simply vanish).
				_mouth_xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.85, 0.10, 0.85)),
					p + Vector3(dir * 1.62, 0, 0)))
				_bank_patch(_stain_xf, east, 0.10, z, _rng.randf_range(2.0, 3.2),
					5.2, 0.05)
				_stain_col.append(Color(0.22, 0.26, 0.15, 0.45))
				_bank_patch(_stain_xf, east, 0.10, z, 0.9, 5.2, 0.058)
				_stain_col.append(Color(0.14, 0.17, 0.10, 0.55))
			z += 118.0 + _rng.randf_range(-20.0, 20.0)


## Yellow depth-marker gauges at the bank toes every ~150 m: FT numbers on a
## board that has never once been underwater on purpose.
func _channel_depth_boards() -> void:
	for east: bool in [false, true]:
		for i in 6:
			var z := 185.0 + 150.0 * float(i)
			var x := -553.9 if east else -686.1
			var gy := _bank_y_at_x(east, x)
			_board_xf.append(Transform3D(
				Basis.from_scale(Vector3(0.14, 3.4, 0.9)),
				Vector3(x, gy + 1.55, z)))
			var lbl := SIGN.make("6\n4\n2", SIGN.STENCIL,
				Color(0.10, 0.09, 0.07), 0.78, 3.0, 88)
			lbl.shaded = true
			lbl.position = Vector3(x + (-0.13 if east else 0.13), gy + 1.55, z)
			lbl.rotation.y = -PI * 0.5 if east else PI * 0.5
			add_child(lbl)


## Faded functional paint on the floor NEAR THE ENDS ONLY — the mid-channel
## race line stays visually clean for the Floodway Sprint.
func _channel_floor_paint() -> void:
	var faded := Color(0.72, 0.62, 0.28, 0.55)
	for zone: Vector2 in [Vector2(140.0, 250.0), Vector2(880.0, 975.0)]:
		var z := zone.x
		while z < zone.y:
			_paint_xf.append(Transform3D(
				Basis.from_scale(Vector3(0.4, 0.02, 4.4)),
				Vector3(CH_MID_X, -5.985, z)))
			_paint_col.append(faded)
			z += 11.0
	# Chevrons warning of the dead ends near each mouth.
	for zone2: Vector2 in [Vector2(146.0, -1.0), Vector2(952.0, 1.0)]:
		for c in 3:
			var tip_z := zone2.x + zone2.y * 24.0 * float(c) * -1.0
			for s: float in [-1.0, 1.0]:
				var arm := Basis(Vector3.UP, s * 0.72 * zone2.y) \
					* Basis.from_scale(Vector3(0.75, 0.02, 6.2))
				_paint_xf.append(Transform3D(arm, Vector3(CH_MID_X + s * 2.1,
					-5.982, tip_z + zone2.y * 2.5)))
				_paint_col.append(Color(0.72, 0.62, 0.28, 0.4))


## Authority stencils, and the city talking back to them. Punches at the
## institution (a NO SWIMMING sign in a channel that has not held water since
## the gauge was painted), never at anyone in it.
func _channel_stencils() -> void:
	# Mouth end-bank: the official line, and the reply underneath.
	var u := Vector3(0, END_RIM.y - END_TOE.y, END_RIM.x - END_TOE.x).normalized()
	var n := Vector3(0, -u.z, u.y)
	if n.y < 0.0:
		n = -n
	var rot := Basis(Vector3(1, 0, 0), u, n)
	var p1 := Vector3(CH_MID_X, lerpf(END_TOE.y, END_RIM.y, 0.62),
		lerpf(END_TOE.x, END_RIM.x, 0.62)) + n * 0.10
	_graffiti_label("CITY OF DORADO · NO SWIMMING", p1, rot, 44.0, 260,
		Color(0.92, 0.92, 0.88, 0.85), Color(0, 0, 0, 0.5), SIGN.STENCIL)
	var p2 := Vector3(CH_MID_X, lerpf(END_TOE.y, END_RIM.y, 0.30),
		lerpf(END_TOE.x, END_RIM.x, 0.30)) + n * 0.12
	_graffiti_label("NO WATER NEITHER", p2,
		rot * Basis(Vector3(0, 0, 1), 0.06), 30.0, 300,
		Color(0.90, 0.26, 0.20), Color(0.1, 0.02, 0.02, 0.6))
	# Bridge fascias: stenciled like real flood-control property.
	for bz in BRIDGE_Z:
		for s: float in [-1.0, 1.0]:
			var lbl := SIGN.make(
				"THREEFORK FLOODWAY  ·  NO SWIMMING  ·  NO KIDDING",
				SIGN.STENCIL, Color(0.85, 0.85, 0.80, 0.8), 23.0, 1.1, 80)
			lbl.outline_modulate = Color(0, 0, 0, 0.5)
			lbl.shaded = true
			lbl.position = Vector3(CH_MID_X, -0.54, bz + s * 8.05)
			lbl.rotation.y = 0.0 if s > 0.0 else PI
			add_child(lbl)


## Flood-washed junk pinned along both bank toes: tires, driftwood, pallets,
## tumbleweeds. Race law: every item lives at x < -688 or x > -552.
func _channel_debris() -> void:
	var bank_ang := atan2(W_RIM.y - W_TOE.y, absf(W_RIM.x - W_TOE.x))  # ~14 deg
	for east: bool in [false, true]:
		var z := 132.0
		while z < 972.0:
			var x := _rng.randf_range(-551.4, -546.5) if east \
				else _rng.randf_range(-693.5, -688.6)
			var gy := _bank_y_at_x(east, x)
			var tilt := (1.0 if east else -1.0) * bank_ang
			var lean := Basis(Vector3(0, 0, 1), tilt)
			var yaw := Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			var roll := _rng.randf()
			if roll < 0.32:                # tires, sometimes a lazy stack
				var r := _rng.randf_range(0.4, 0.55)
				var col := Color(0.08, 0.08, 0.09) * _rng.randf_range(0.8, 1.3)
				_tire_xf.append(Transform3D(lean * yaw
					* Basis.from_scale(Vector3(r, 0.26, r)),
					Vector3(x, gy + 0.14, z)))
				_tire_col.append(col)
				if _rng.randf() < 0.3:
					_tire_xf.append(Transform3D(lean
						* Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
						* Basis.from_scale(Vector3(r * 0.96, 0.26, r * 0.96)),
						Vector3(x, gy + 0.41, z)))
					_tire_col.append(col * 0.9)
			elif roll < 0.56:              # driftwood planks
				_wood_xf.append(Transform3D(yaw
					* Basis(Vector3(1, 0, 0), _rng.randf_range(-0.06, 0.06))
					* Basis.from_scale(Vector3(_rng.randf_range(2.2, 5.0),
						_rng.randf_range(0.14, 0.22), _rng.randf_range(0.18, 0.34))),
					Vector3(x, gy + 0.11, z)))
				_wood_col.append(Color(0.50, 0.45, 0.38) * _rng.randf_range(0.8, 1.1))
			elif roll < 0.74:              # pallets, some leaned on the bank
				var flat := _rng.randf() < 0.6
				var pb := yaw * Basis.from_scale(Vector3(1.15, 0.12, 0.95)) if flat \
					else lean * Basis(Vector3(0, 0, 1),
						(1.0 if east else -1.0) * 1.15) \
						* Basis.from_scale(Vector3(1.15, 0.12, 0.95))
				_wood_xf.append(Transform3D(pb, Vector3(x, gy + (0.08 if flat else 0.55), z)))
				_wood_col.append(Color(0.55, 0.47, 0.35) * _rng.randf_range(0.75, 1.05))
			elif roll < 0.9:               # tumbleweeds caught on the toe
				var s := _rng.randf_range(0.6, 1.1)
				_weed_xf.append(Transform3D(yaw
					* Basis(Vector3(1, 0, 0), _rng.randf_range(-0.3, 0.3))
					* Basis.from_scale(Vector3(s, s, s)),
					Vector3(x, gy + s * 0.42, z)))
				_weed_col.append(Color(0.66, 0.58, 0.42) * _rng.randf_range(0.85, 1.1))
			z += _rng.randf_range(9.0, 22.0)


# ============================== THE PRAIRIE ==================================
## Everything outside the built city. One shared placement filter keeps the
## wild layer out of every district, road, campus, and the smoke corridor.
func _prairie_ok(x: float, z: float) -> bool:
	if absf(x) > 985.0 or absf(z) > 985.0:
		return false                                   # containment walls
	if x > 96.0 and x < 794.0 and z > 36.0 and z < 570.0:
		return false                                   # downtown street bed
	if absf(z) < 62.0 and absf(x) < 820.0:
		return false                                   # freeway/frontage/malls
	if x > -615.0 and x < 715.0 and z > -900.0 and z < -168.0:
		return false                                   # suburb fringe + yards
	if x > -716.0 and x < -524.0 and z > 94.0:
		return false                                   # the channel + rims
	for bz in BRIDGE_Z:
		if x > -746.0 and x < -494.0 and absf(z - bz) < 10.0:
			return false                               # bridge approach decks
	if x > 330.0 and x < 400.0 and z > 552.0 and z < 652.0:
		return false                                   # County General campus
	if x > 170.0 and x < 216.0 and z > 420.0 and z < 580.0:
		return false                                   # smoke corridor (sacred)
	return true


func _dist_to_road(x: float, z: float) -> float:
	var best := 1.0e9
	for p in _road_pts:
		var d := Vector2(x, z).distance_squared_to(p)
		if d < best:
			best = d
	return sqrt(best)


## Dirt two-track roads: pairs of worn wheel strips meandering across the
## prairie — one in the band between the suburbs and the freeway, one down the
## west prairie off the channel, one through the south range past the
## hospital. Segments steer around every exclusion zone.
func _dirt_roads() -> void:
	var routes: Array = [
		[Vector2(-540, -150), Vector2(700, -84)],
		[Vector2(-495, 150), Vector2(70, 880)],
		[Vector2(140, 610), Vector2(760, 930)],
	]
	for ri in routes.size():
		var route: Array = routes[ri]
		var pos: Vector2 = route[0]
		var goal: Vector2 = route[1]
		var pts: Array[Vector2] = [pos]
		var heading := (goal - pos).angle()
		var guard := 0
		while pos.distance_to(goal) > 45.0 and guard < 70:
			guard += 1
			var to_goal := (goal - pos).angle()
			heading = lerp_angle(heading, to_goal, 0.30) \
				+ _rng.randf_range(-0.28, 0.28)
			var step := _rng.randf_range(26.0, 38.0)
			var nxt := pos + Vector2.from_angle(heading) * step
			var ok := _prairie_ok(nxt.x, nxt.y)
			var tries := 0
			while not ok and tries < 7:
				tries += 1
				heading += 0.45 * (1.0 if (tries % 2 == 0) else -1.0) * float(tries)
				nxt = pos + Vector2.from_angle(heading) * step
				ok = _prairie_ok(nxt.x, nxt.y)
			if not ok:
				break
			# Two wheel strips per segment, parity heights (z-fighting law).
			var dirv := (nxt - pos).normalized()
			var perp := Vector2(-dirv.y, dirv.x)
			var mid := (pos + nxt) * 0.5
			var yaw := atan2(dirv.x, dirv.y)
			var y := 0.004 if pts.size() % 2 == 0 else 0.007
			for side: float in [-1.0, 1.0]:
				var c := mid + perp * side * 0.95
				_track_xf.append(Transform3D(Basis(Vector3.UP, yaw)
					* Basis.from_scale(Vector3(0.62, 0.012, step + 1.6)),
					Vector3(c.x, y, c.y)))
				_track_col.append(Color(0.42, 0.36, 0.26) * _rng.randf_range(0.88, 1.05))
			_road_pts.append(mid)
			pts.append(nxt)
			pos = nxt
		if ri == 1:
			_route2 = pts


## A wire fence flanking the west-prairie two-track: posts every 6 m, three
## strands, broken and leaning where the years won.
func _fence_line() -> void:
	if _route2.size() < 3:
		return
	var count := int(float(_route2.size()) * 0.6)
	var prev_top := Vector3.ZERO
	var have_prev := false
	for i in range(0, count - 1):
		var a: Vector2 = _route2[i]
		var b: Vector2 = _route2[i + 1]
		var seg := b - a
		var seg_len := seg.length()
		var dirv := seg / seg_len
		var perp := Vector2(-dirv.y, dirv.x)
		var d := 0.0
		while d < seg_len:
			var fp := a + dirv * d + perp * 10.0
			d += 6.0
			if not _prairie_ok(fp.x, fp.y):
				have_prev = false
				continue
			if _rng.randf() < 0.08:        # missing post: broken span
				have_prev = false
				continue
			var lean := 0.0
			if _rng.randf() < 0.14:
				lean = _rng.randf_range(0.07, 0.2) * (1.0 if _rng.randf() < 0.5 else -1.0)
			var base := Vector3(fp.x, -0.03, fp.y)
			_post_xf.append(Transform3D(
				Basis(Vector3(dirv.x, 0, dirv.y), lean)
				* Basis.from_scale(Vector3(0.14, 1.35, 0.14)),
				base + Vector3(0, 0.66, 0)))
			_post_col.append(Color(0.30, 0.22, 0.15) * _rng.randf_range(0.8, 1.15))
			var top := base + Vector3(0, 1.2, 0)
			if have_prev:
				for h: float in [0.5, 0.82, 1.14]:
					var wa := prev_top + Vector3(0, h - 1.2, 0)
					var wb := top + Vector3(0, h - 1.2, 0)
					var wd := wb - wa
					_wire_xf.append(Transform3D(
						Basis.looking_at(wd.normalized(), Vector3.UP)
						* Basis.from_scale(Vector3(0.03, 0.03, wd.length())),
						(wa + wb) * 0.5))
			prev_top = top
			have_prev = true


## Grass tufts in natural clusters — the single biggest emptiness fix.
## Cluster centers land anywhere the filter allows; tufts thin near the dirt
## roads (traffic kills grass) and vanish from the wheel lines entirely.
func _prairie_grass() -> void:
	var clusters := 0
	var attempts := 0
	while clusters < 850 and attempts < 3000:
		attempts += 1
		var cx := _rng.randf_range(-980.0, 980.0)
		var cz := _rng.randf_range(-980.0, 980.0)
		if not _prairie_ok(cx, cz):
			continue
		var road_d := _dist_to_road(cx, cz)
		if road_d < 4.0 or (road_d < 11.0 and _rng.randf() < 0.75):
			continue
		clusters += 1
		var n := _rng.randi_range(8, 20)
		var radius := _rng.randf_range(2.5, 7.0)
		for k in n:
			var ang := _rng.randf_range(0.0, TAU)
			var r := radius * sqrt(_rng.randf())
			var tx := cx + cos(ang) * r
			var tz := cz + sin(ang) * r
			if not _prairie_ok(tx, tz) or _dist_to_road(tx, tz) < 2.5:
				continue
			var s := _rng.randf_range(0.35, 0.75)
			_tuft_xf.append(Transform3D(
				Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
				* Basis.from_scale(Vector3(s * _rng.randf_range(0.9, 1.3),
					s * _rng.randf_range(0.8, 1.2), s * _rng.randf_range(0.9, 1.3))),
				Vector3(tx, -0.045, tz)))
			var c := Color(0.58, 0.50, 0.30).lerp(Color(0.44, 0.46, 0.28), _rng.randf())
			if _rng.randf() < 0.25:
				c = c.lerp(Color(0.63, 0.55, 0.35), 0.7)
			_tuft_col.append(c * _rng.randf_range(0.85, 1.05))


## Mesquite scrub: low, gnarled, scrappier than any city tree — leaning dark
## trunks under ragged olive canopies, in loose stands.
func _prairie_scrub() -> void:
	var stands := 0
	var attempts := 0
	while stands < 110 and attempts < 900:
		attempts += 1
		var cx := _rng.randf_range(-980.0, 980.0)
		var cz := _rng.randf_range(-980.0, 980.0)
		if not _prairie_ok(cx, cz) or _dist_to_road(cx, cz) < 7.0:
			continue
		stands += 1
		for b in _rng.randi_range(2, 5):
			var bx := cx + _rng.randf_range(-14.0, 14.0)
			var bz := cz + _rng.randf_range(-14.0, 14.0)
			if not _prairie_ok(bx, bz):
				continue
			for tr in _rng.randi_range(2, 3):
				var h := _rng.randf_range(0.9, 1.4)
				_trunk_xf.append(Transform3D(
					Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
					* Basis(Vector3(1, 0, 0), _rng.randf_range(0.12, 0.38))
					* Basis.from_scale(Vector3(_rng.randf_range(0.08, 0.14), h,
						_rng.randf_range(0.08, 0.14))),
					Vector3(bx + _rng.randf_range(-0.25, 0.25), h * 0.42,
						bz + _rng.randf_range(-0.25, 0.25))))
				_trunk_col.append(Color(0.22, 0.17, 0.12) * _rng.randf_range(0.85, 1.15))
			for cn in _rng.randi_range(1, 2):
				# Chunky low canopy tight over the trunks — the first cut's
				# wide flat slab on two visible legs read as a picnic table.
				_bush_xf.append(Transform3D(
					Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
					* Basis.from_scale(Vector3(_rng.randf_range(1.2, 2.2),
						_rng.randf_range(0.6, 1.1), _rng.randf_range(1.2, 2.2))),
					Vector3(bx + _rng.randf_range(-0.3, 0.3),
						_rng.randf_range(0.75, 1.3),
						bz + _rng.randf_range(-0.3, 0.3))))
				_bush_col.append(Color(0.33, 0.36, 0.20).lerp(
					Color(0.44, 0.44, 0.26), _rng.randf()) * _rng.randf_range(0.85, 1.05))


## A few loose tumbleweeds drifting on the open range.
func _prairie_weeds() -> void:
	var placed := 0
	var attempts := 0
	while placed < 26 and attempts < 300:
		attempts += 1
		var x := _rng.randf_range(-980.0, 980.0)
		var z := _rng.randf_range(-980.0, 980.0)
		if not _prairie_ok(x, z):
			continue
		placed += 1
		var s := _rng.randf_range(0.5, 1.1)
		_weed_xf.append(Transform3D(
			Basis(Vector3.UP, _rng.randf_range(0.0, TAU))
			* Basis(Vector3(1, 0, 0), _rng.randf_range(-0.3, 0.3))
			* Basis.from_scale(Vector3(s, s, s)),
			Vector3(x, s * 0.45 - 0.03, z)))
		_weed_col.append(Color(0.66, 0.58, 0.42) * _rng.randf_range(0.85, 1.1))


# ============================== MESHES + FLUSH ===============================
## Grass tuft: two crossed planes of jagged BLADES, base at y=0. A solid quad
## reads as a pale sign (review-caught) — the silhouette is the grass. All
## normals are forced UP (the classic grass trick) so a SHADED material makes
## every blade track the terrain's lighting: sunlit tan at noon, properly
## dark at night (unshaded grass glowed in the freeway night shot).
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Blades as (base_x0, base_x1, tip_x, tip_y) in plane coordinates.
	var blades: Array = [
		[-0.50, -0.22, -0.40, 0.62], [-0.28, 0.02, -0.10, 1.00],
		[-0.04, 0.30, 0.20, 0.78], [0.24, 0.50, 0.42, 0.88],
	]
	st.set_normal(Vector3.UP)
	for b: Array in blades:
		st.add_vertex(Vector3(b[0], 0, 0)); st.add_vertex(Vector3(b[1], 0, 0))
		st.add_vertex(Vector3(b[2], b[3], 0))
		st.add_vertex(Vector3(0, 0, b[0])); st.add_vertex(Vector3(0, 0, b[1]))
		st.add_vertex(Vector3(0, b[3], b[2]))
	return st.commit()


## Tumbleweed: three crossed hexagon fans — a ragged ball, not a box. Up
## normals for the same day/night lighting reason as the tufts.
static func _ball_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3.UP)
	for plane in 3:
		for i in 6:
			var a0 := TAU * float(i) / 6.0
			var a1 := TAU * float(i + 1) / 6.0
			var r0 := 0.5 if i % 2 == 0 else 0.38   # ragged rim
			var r1 := 0.5 if (i + 1) % 2 == 0 else 0.38
			var p0 := Vector2(cos(a0) * r0, sin(a0) * r0)
			var p1 := Vector2(cos(a1) * r1, sin(a1) * r1)
			var v0: Vector3
			var v1: Vector3
			match plane:
				0:
					v0 = Vector3(p0.x, p0.y, 0)
					v1 = Vector3(p1.x, p1.y, 0)
				1:
					v0 = Vector3(0, p0.y, p0.x)
					v1 = Vector3(0, p1.y, p1.x)
				_:
					v0 = Vector3(p0.x, 0, p0.y)
					v1 = Vector3(p1.x, 0, p1.y)
			st.add_vertex(Vector3.ZERO)
			st.add_vertex(v0)
			st.add_vertex(v1)
	return st.commit()


func _flush() -> void:
	var tuft := _tuft_mesh()
	var ball := _ball_mesh()
	var pipe := MESH_KIT.prism(1.05, 3.2, 10)
	var drum := MESH_KIT.prism(1.0, 1.0, 10)
	# Channel art + stains + paint. Graffiti and stains are SHADED: spray
	# paint is not luminous, and the night pass caught unshaded surfaces
	# glowing at midnight. Floor paint stays unshaded like the city's road
	# markings — retroreflective paint reading is an accepted city idiom.
	# SHADOW POLICY (D-028). Graffiti, stains and floor paint are pigment ON the
	# channel's concrete — they cannot shade what they are painted onto.
	_mm(_unit, _blob_xf, _blob_col, _mat_colored(false, false, 0.95),
		"GraffitiBlobs", false)
	_mm(_unit, _stain_xf, _stain_col, _mat_colored(false, true, 0.95),
		"ChannelStains", false)
	_mm(_unit, _paint_xf, _paint_col, _mat_colored(true, true),
		"FloorPaint", false)
	# Depth boards, outfall pipes and their black mouths are real structure
	# standing off the channel wall — the pipe shadow is what gives the outfall
	# its socket. 36 instances in total; cheap and they read.
	_mm(_unit, _board_xf, [], _mat_flat(Color(0.85, 0.72, 0.15), 0.7),
		"DepthBoards", true)
	_mm(pipe, _pipe_xf, [], _mat_flat(Color(0.42, 0.41, 0.38), 0.9),
		"OutfallPipes", true)
	_mm(drum, _mouth_xf, [], _mat_flat(Color(0.05, 0.05, 0.05), 1.0),
		"PipeMouths", true)
	# Debris. Tyres and lumber are solid objects lying in an empty concrete
	# channel — with no shadow they float. Tumbleweeds are a two-sided alpha
	# ball: the shadow map has no alpha, so a caster would render them as solid
	# black spheres, which is worse than no shadow.
	_mm(drum, _tire_xf, _tire_col, _mat_colored(false, false, 0.85),
		"DebrisTires", true)
	_mm(_unit, _wood_xf, _wood_col, _mat_colored(false, false, 0.95),
		"DebrisWood", true)
	_mm(ball, _weed_xf, _weed_col, _mat_colored(false, false, 1.0, true),
		"Tumbleweeds", false)
	# Prairie. GrassTufts is the single largest shadow set in the project at
	# 11,919 instances — two-sided blade cards whose shadow is per-pixel noise
	# at every distance, and one visible tuft dragged the entire prairie into
	# every cascade. Mesquite is a tree and keeps its shade; the fence is a
	# 4-strand WIRE fence, so posts cast and the wire does not.
	_mm(tuft, _tuft_xf, _tuft_col, _mat_colored(false, false, 1.0, true),
		"GrassTufts", false)
	_mm(_unit, _trunk_xf, _trunk_col, _mat_colored(false, false, 0.95),
		"MesquiteTrunks", true)
	_mm(MESH_KIT.canopy(0.5, 6, 10, 5, 0.30, 0.12), _bush_xf, _bush_col, _mat_colored(false, false, 0.95),
		"MesquiteCanopies", true)   # M23: a ragged crown (30 % lobes), not a unit box
	_mm(_unit, _track_xf, _track_col, _mat_colored(false, false, 0.98),
		"DirtTracks", false)
	_mm(_unit, _post_xf, _post_col, _mat_colored(false, false, 0.9),
		"FencePosts", true)
	_mm(_unit, _wire_xf, [], _mat_flat(Color(0.10, 0.09, 0.08), 0.9, true),
		"FenceWires", false)
	_apply_wind()


## M23 VEGETATION WIND (append-only; material assignment ONLY). Swaps
## `material_override` on layers that are already built and already carry their
## D-028 answer. No transform, no RNG draw, no instance count, no shadow flag.
##
## SHADOW POLICY RESTATED HERE (D-028): GrassTufts (11,919 two-sided blade
## cards) and Tumbleweeds (a two-sided alpha ball) are `casts` = false and stay
## that way — a two-sided card is OFF as a hard rule, and moving it does not
## make it a solid. MesquiteCanopies keep the caster the layer gave them;
## MesquiteTrunks are NOT in this list at all, which is the point: a trunk that
## sways is a rubber tree.
func _apply_wind() -> void:
	# The biggest set in the game and the one that sells the whole prairie.
	# flutter 0.06 is blade chatter — the term that makes grass read as grass
	# and not as a field of small flags.
	SHD.apply_wind(self, "GrassTufts", 1.0, true, 0.34, 0.52, 2.05, 0.06)
	# rigid_mix 1.0: a mesquite crown is a lobe whose origin is its own centre.
	SHD.apply_wind(self, "MesquiteCanopies", 0.90, false, 0.06, 0.12, 0.95, 0.0, 1.0, true, 5)
	# A tumbleweed is not rooted. It jitters and shifts; it does not bend.
	SHD.apply_wind(self, "Tumbleweeds", 1.0, true, 0.09, 0.22, 1.70, 0.03, 1.0)


func _mat_flat(col: Color, rough: float, unshaded := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _mat_colored(unshaded: bool, transparent: bool, rough := 0.9,
		two_sided := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if transparent:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if two_sided:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


## `casts` is required, no default (D-028). A MultiMesh is culled as ONE unit:
## one visible grass tuft put all 11,919 of them in every shadow cascade.
func _mm(mesh: Mesh, xf: Array[Transform3D], cols: Array[Color],
		mat: StandardMaterial3D, label: String, casts: bool) -> void:
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
			# Instance colors skip the sRGB->linear pass that albedo_color
			# gets, so raw values render washed-out bright (review-caught:
			# khaki grass turned to cream). Convert here; alpha is untouched.
			mm.set_instance_color(i, cols[i].srgb_to_linear())
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Graffiti/stencil lettering with the glyph-fit law: default-font advance is
## ~0.66 x font px, so the size is capped to the panel width, never clipped.
## Shaded: paint on a wall goes dark at night with the wall.
func _graffiti_label(text: String, pos: Vector3, rot: Basis, max_w: float,
		fsize: int, col: Color, out_col: Color, style: int = SIGN.HANDPAINT) -> void:
	# HANDPAINT: a slight lean and open spacing. Spray-can copy and stencilled
	# flood-control copy are not the same hand, and now they do not look it.
	var lbl := SIGN.make(text, style, col, max_w, 0.0, fsize)
	lbl.outline_modulate = out_col
	lbl.shaded = true
	lbl.transform = Transform3D(rot, pos)
	add_child(lbl)
