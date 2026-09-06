extends Node3D
## FREEWAY CORRIDOR DRESSING (M15) — the I-3 deck stops being a bare runway.
## Overhead gantry signage (canon destinations only — naming bible §2-§4/§6),
## guardrails atop the deck barriers and down the ramp edges, full deck lane
## paint, exit/entrance/advisory signage at the ramps, column water-streaks and
## canon-brand posters, and the frontage retail strip's parking stalls,
## dumpsters, reflector posts and drive-thru lanes.
##
## CONTRACT (house law): 100% VISUAL-ONLY — zero collision, zero edits to any
## seeded stream. Cars can still fly off the deck through the barrier gaps;
## that is canon comedy and nothing here changes it. All randomness comes from
## ONE fresh RNG with a literal seed. Repeated elements are MultiMeshes; text
## is Label3D with the measured-glyph fit law (font ~ width/(chars*0.66*0.01)).
## Everything is built once in build(); no _process, no per-frame allocation.

const RNG_SEED := 555002

# -- Geometry mirrored from greybox_city.gd (layout source of truth). --------
const FWY_TOP := 9.0                 # deck driving surface
const HALF_LEN := 800.0              # deck x span
const HALF_W := 12.0                 # deck z span
const DECK_PAINT_Y := 9.04           # paint floats 4 cm over the deck
const RAMP_TOP_X := 517.4            # ramp tip |x| (meets deck height)
const RAMP_BOT_X := 582.0            # ramp mouth |x| (grade)
const RAMP_Z := 18.0                 # ramp lane centreline |z|
const FRONTAGE_Z := 30.0             # frontage strip centreline |z|
const FRONTAGE_TOP := 0.05           # frontage road slab top
const COLUMN_STEP := 30.0            # columns every 30 m at z=0
const BARRIER_SEGS: Array = [        # deck barrier x-runs (gapped at merges)
	Vector2(-800.0, -519.0), Vector2(-477.0, 477.0), Vector2(519.0, 800.0)]
const BARRIER_Z := 11.7              # barrier centreline |z| (top y = 10.0)
# Junker curb slots (repo_board.gd) on the south frontage — stall paint skips
# them so parallel-parked wrecks never straddle head-in stall lines.
const JUNKER_X: Array = [258.0, 334.0, 410.0, 486.0]

# -- Gantry schedule: [x, EB panels (face -X), WB panels (face +X)]. ----------
# Every destination is canon (naming bible §2 cities, §3 districts, §4 roads/
# interchanges/bridges, §6 POIs). Distances/EXIT lines are genericisms.
const GANTRIES: Array = [
	[-700.0, [["DOWNTOWN DORADO", "3 MILES"], ["DEEP ELM", "6 MILES"]],
		[["FORT VERDE", "12 MILES"]]],
	[-450.0, [["TO LOOP 8", "THE BIG HOWDY"]],
		[["FORT VERDE", "I-5W · THE KNOT"]]],
	[-200.0, [["DOWNTOWN DORADO", "2 MILES"]],
		[["THREEFORK FLOODWAY", "NEXT EXIT"]]],
	[50.0, [["DOWNTOWN DORADO", "EXIT 1 MILE"], ["I-5E · THE TANGLE", "3 MILES"]],
		[["THREEFORK FLOODWAY", "1 MILE"]]],
	[240.0, [["DOWNTOWN DORADO", "EXIT 1/2 MILE"]],
		[["THREEFORK FLOODWAY", "2 MILES"]]],
	[460.0, [["DOWNTOWN DORADO", "EXIT ONLY"]],
		[["THREEFORK FLOODWAY", "3 MILES"]]],
	[700.0, [["LAKE HOLLOWAY", "THE LONG BRIDGE"]],
		[["FORT VERDE", "14 MILES"], ["MIDDLINGTON", "7 MILES"]]],
]

# -- Column posters: canon §7 brands only (name, bg, fg). ---------------------
const POSTERS: Array = [
	["DR. ZING", Color(0.42, 0.08, 0.12), Color(0.98, 0.92, 0.8)],
	["THE TEXAS\nSLEDGEHAMMER", Color(0.08, 0.12, 0.3), Color(1.0, 0.83, 0.25)],
	["PARLAYPAL", Color(0.05, 0.42, 0.26), Color(0.95, 0.98, 0.95)],
	["SMOKE 'EM IF\nYOU GOT 'EM", Color(0.07, 0.07, 0.07), Color(0.62, 0.95, 0.3)],
	["BLUR+", Color(0.12, 0.08, 0.2), Color(0.7, 0.4, 0.95)],
	["LASSOED™", Color(0.75, 0.2, 0.4), Color(1, 1, 1)],
	["SONBEAM\nNETWORK", Color(0.9, 0.85, 0.7), Color(0.5, 0.3, 0.1)],
	["PRIMEMALE\nPROTOCOL", Color(0.1, 0.1, 0.12), Color(0.85, 0.9, 1.0)],
]

# Drive-thru brands (must match city_dressing.SHOPS entries exactly).
const DRIVE_THRU_BRANDS: Array = ["HOLLERBURGER", "CLUCK ALMIGHTY"]
const CITY_DRESSING := preload("res://scripts/world/city_dressing.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")

const SIGN_GREEN := Color(0.04, 0.30, 0.13)
const SIGN_TEXT := Color(0.96, 0.97, 0.95)
const EXIT_YELLOW := Color(0.95, 0.78, 0.12)
const STEEL := Color(0.24, 0.26, 0.28)
const GALV := Color(0.58, 0.61, 0.63)     # weathered galvanized rail gray
const PAINT_WHITE := Color(0.88, 0.88, 0.86)
const PAINT_YELLOW := Color(0.85, 0.72, 0.25)

var _rng := RandomNumberGenerator.new()
var _unit_mesh := BoxMesh.new()
# MultiMesh accumulators — flushed once at the end of build().
var _white_xf: Array[Transform3D] = []       # all white paint
var _yellow_xf: Array[Transform3D] = []      # centre-line yellow paint
var _rail_xf: Array[Transform3D] = []        # galvanized rails + posts
var _steel_xf: Array[Transform3D] = []       # gantry posts/trusses, sign posts
var _green_xf: Array[Transform3D] = []       # green highway panels
var _warn_xf: Array[Transform3D] = []        # yellow advisory boards
var _streak_xf: Array[Transform3D] = []      # column water streaks
var _poster_xf: Array[Transform3D] = []      # column poster backers
var _poster_col: Array[Color] = []
var _dump_xf: Array[Transform3D] = []        # dumpster bodies
var _lid_xf: Array[Transform3D] = []         # dumpster lids
var _refl_xf: Array[Transform3D] = []        # reflector posts
var _cap_xf: Array[Transform3D] = []         # reflector red caps
var _dark_xf: Array[Transform3D] = []        # drive-thru lane asphalt strips


func build(city: Node3D) -> void:
	_rng.seed = RNG_SEED
	_unit_mesh.size = Vector3.ONE
	_deck_paint()
	_guardrails()
	_gantries()
	_ramp_signage()
	_column_dressing()
	_frontage_strip(city)
	_flush()


# ============================== DECK LANE PAINT ==============================
## The deck currently has NO paint. Two lanes each direction: solid yellow
## centre pair, white dashed lane dividers at |z|=5.5, solid white edge lines
## at |z|=10.45 (inside the gantry-post shoulder). All floated 4 cm up.
func _deck_paint() -> void:
	var x := -798.0
	while x < 798.0:   # solid lines in 28 m segments (one MM instance each)
		var seg := minf(28.0, 798.0 - x)
		for zy: float in [-0.3, 0.3]:
			_yellow_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(seg, 0.02, 0.14)),
				Vector3(x + seg * 0.5, DECK_PAINT_Y, zy)))
		for ze: float in [-10.45, 10.45]:
			_white_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(seg, 0.02, 0.18)),
				Vector3(x + seg * 0.5, DECK_PAINT_Y, ze)))
		x += seg
	var dx := -794.0
	while dx <= 794.0:  # lane-divider dashes, 3 m every 7 m, both directions
		for zd: float in [-5.5, 5.5]:
			_white_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(3.0, 0.02, 0.24)),
				Vector3(dx, DECK_PAINT_Y, zd)))
		dx += 7.0
	# Ramp edge lines: one rotated stripe per edge, following the slope.
	for endx: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var zc := side * RAMP_Z
			var bottom := Vector3(endx * RAMP_BOT_X, -0.05, zc)
			var top := Vector3(endx * RAMP_TOP_X, FWY_TOP + 0.09, zc)
			for edge: float in [-4.7, 4.7]:
				_slope_stripe(bottom + Vector3(0, 0, edge),
					top + Vector3(0, 0, edge), 0.16)


## A paint stripe from a to b along a slope, floated 3 cm above the surface.
func _slope_stripe(a: Vector3, b: Vector3, w: float) -> void:
	var run := b - a
	var slope := run.normalized()
	var side := Vector3.UP.cross(slope).normalized()
	var normal := slope.cross(side).normalized()
	var basis := Basis(side, normal, slope) * Basis.from_scale(
		Vector3(w, 0.02, run.length() - 1.0))
	_white_xf.append(Transform3D(basis, (a + b) * 0.5 + normal * 0.03))


# ============================== GUARDRAILS ===================================
## Galvanized tube rail on stub posts along the TOP of the existing concrete
## barriers (adds the missing silhouette height), following the same gapped
## segments — the merge-pad gaps stay open, so launching off the deck there
## remains exactly as flyable as canon demands. Same treatment down both edges
## of every ramp. VISUAL ONLY: no rail here stops anything.
func _guardrails() -> void:
	for side: float in [-1.0, 1.0]:
		for seg_v: Variant in BARRIER_SEGS:
			var seg: Vector2 = seg_v
			var seg_len := seg.y - seg.x
			# Continuous top tube, one instance per segment.
			_rail_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(seg_len, 0.15, 0.15)),
				Vector3((seg.x + seg.y) * 0.5, 10.36, side * BARRIER_Z)))
			var px := seg.x + 2.0
			while px <= seg.y - 1.9:   # stub posts every 4 m
				_rail_xf.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.1, 0.36, 0.1)),
					Vector3(px, 10.14, side * BARRIER_Z)))
				px += 4.0
	# Ramp rails: a sloped tube + posts along both edges of each ramp.
	for endx: float in [-1.0, 1.0]:
		for side: float in [-1.0, 1.0]:
			var zc := side * RAMP_Z
			var bottom := Vector3(endx * RAMP_BOT_X, -0.05, zc)
			var top := Vector3(endx * RAMP_TOP_X, FWY_TOP + 0.09, zc)
			for edge: float in [-4.9, 4.9]:
				var a := bottom + Vector3(0, 0, edge)
				var b := top + Vector3(0, 0, edge)
				var run := b - a
				var slope := run.normalized()
				var rside := Vector3.UP.cross(slope).normalized()
				var basis := Basis(rside, slope.cross(rside).normalized(), slope)
				_rail_xf.append(Transform3D(
					basis * Basis.from_scale(Vector3(0.13, 0.13, run.length() - 2.0)),
					(a + b) * 0.5 + Vector3(0, 0.78, 0)))
				for k in 9:
					var t := (float(k) + 0.5) / 9.0
					var p := a.lerp(b, t)
					_rail_xf.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.09, 0.72, 0.09)),
						p + Vector3(0, 0.38, 0)))


# ============================== GANTRIES =====================================
## Overhead sign bridges every ~250 m: two posts on the deck shoulders, a truss
## box spanning the full width at ~6 m over the surface, green panels for each
## direction hung under it. Eastbound panels hang over the south lanes (z>0)
## and face -X; westbound mirror. Panel text on BOTH faces of every panel.
func _gantries() -> void:
	for g_v: Variant in GANTRIES:
		var g: Array = g_v
		var gx: float = g[0]
		for pz: float in [-11.05, 11.05]:   # shoulder posts, behind the edge line
			_steel_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.62, 6.7, 0.62)),
				Vector3(gx, FWY_TOP + 3.35, pz)))
		_steel_xf.append(Transform3D(               # truss box, full span
			Basis.IDENTITY.scaled(Vector3(0.8, 0.95, 24.6)),
			Vector3(gx, 15.25, 0.0)))
		_steel_xf.append(Transform3D(               # thin top chord for profile
			Basis.IDENTITY.scaled(Vector3(0.9, 0.14, 24.6)),
			Vector3(gx, 15.85, 0.0)))
		_gantry_face(gx, g[1], -1.0)   # eastbound: faces -X, panels over z>0
		_gantry_face(gx, g[2], 1.0)    # westbound: faces +X, panels over z<0


## One direction's panels on a gantry. face=-1 means readable by +X travel.
## A single panel gets the full 7.6 m board; a pair narrows to 5.4 m each so
## the boards never overlap over the half-deck (5.4 spans +-2.7; centres 6 m
## apart leave a 0.6 m gap).
func _gantry_face(gx: float, panels: Array, face: float) -> void:
	var lane_side := -face   # EB (face -1) panels hang over south lanes (z>0)
	var zs: Array = [[5.6, 7.6]] if panels.size() == 1 \
		else [[2.6, 5.4], [8.6, 5.4]]
	for i in panels.size():
		var p: Array = panels[i]
		var zw: Array = zs[i]
		_panel(Vector3(gx + face * 0.55, 13.55, float(zw[0]) * lane_side),
			Vector2(float(zw[1]), 2.5), face, str(p[0]), str(p[1]))


## A green guide panel: box + two text lines on both faces. For a face normal
## of ±X the label yaw is ±PI/2 (Label3D's face is +Z; +Z maps to (sin, 0, cos)).
func _panel(center: Vector3, size: Vector2, face: float, line1: String,
		line2: String) -> void:
	_green_xf.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(0.24, size.y, size.x)), center))
	for f: float in [face, -face]:
		var off := Vector3(f * 0.16, 0, 0)
		var l2_col := EXIT_YELLOW if line2.begins_with("EXIT") \
			or line2 == "NEXT EXIT" else SIGN_TEXT
		_label(line1, center + off + Vector3(0, size.y * 0.18, 0), f, 110,
			SIGN_TEXT, size.x * 0.92, -1.0, SIGN.GANTRY, size.y * 0.42)
		_label(line2, center + off + Vector3(0, -size.y * 0.26, 0), f, 78,
			l2_col, size.x * 0.86, -1.0, SIGN.GANTRY, size.y * 0.34)


# ============================== RAMP SIGNAGE =================================
## Per ramp: a gore EXIT panel on the merge pad at the top (read from the
## deck), a yellow RAMP 25 MPH advisory board mid-slope, and a green TO I-3
## trailblazer at the grade mouth. All four ramps; east-end signage faces -X
## (read by outbound eastbound traffic), west-end mirrors.
func _ramp_signage() -> void:
	for endx: float in [-1.0, 1.0]:
		var face := -endx
		for side: float in [-1.0, 1.0]:
			# Gore EXIT panel on the merge pad (pad top y=8.48).
			var gpos := Vector3(endx * 508.0, 0, side * 12.55)
			_steel_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.14, 2.3, 0.14)),
				gpos + Vector3(0, 8.48 + 1.15, 0)))
			var pc := gpos + Vector3(0, 11.35, 0)
			_green_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.2, 1.35, 1.9)), pc))
			for f: float in [face, -face]:
				_label("EXIT", pc + Vector3(f * 0.14, 0, 0), f, 95,
					EXIT_YELLOW, 1.72, -1.0, SIGN.GANTRY, 1.10)
			# Advisory board beside the ramp mid-slope, posted from grade in
			# the 1 m verge between ramp edge (|z|=23) and frontage road (24).
			var apos := Vector3(endx * 550.0, 0, side * 23.45)
			var ramp_h := 4.55   # ramp surface height at |x|=550
			_steel_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.14, ramp_h + 2.2, 0.14)),
				apos + Vector3(0, (ramp_h + 2.2) * 0.5, 0)))
			var bc := apos + Vector3(0, ramp_h + 2.55, 0)
			_warn_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.16, 1.5, 1.35)), bc))
			_label("RAMP", bc + Vector3(face * 0.12, 0.3, 0), face, 52,
				Color(0.08, 0.08, 0.08), 1.22, -1.0, SIGN.GANTRY, 0.56)
			_label("25 MPH", bc + Vector3(face * 0.12, -0.32, 0), face, 46,
				Color(0.08, 0.08, 0.08), 1.22, -1.0, SIGN.GANTRY, 0.56)
		# Grade-mouth trailblazer (one per end, between the two ramp mouths):
		# entering here climbs INWARD, so the east mouth feeds I-3 WEST.
		var dest := "DOWNTOWN DORADO" if endx < 0.0 else "FORT VERDE"
		var road := "TO I-3 EAST" if endx < 0.0 else "TO I-3 WEST"
		var mpos := Vector3(endx * 594.0, 0, 0)
		for px: float in [-1.6, 1.6]:
			_steel_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.16, 3.2, 0.16)),
				mpos + Vector3(0, 1.6, px)))
		var mc := mpos + Vector3(0, 3.9, 0)
		_green_xf.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(0.22, 1.8, 4.2)), mc))
		for f: float in [face, -face]:
			_label(road, mc + Vector3(f * 0.15, 0.34, 0), f, 62, SIGN_TEXT, 3.9,
				-1.0, SIGN.GANTRY, 0.72)
			_label(dest, mc + Vector3(f * 0.15, -0.38, 0), f, 56, SIGN_TEXT, 3.9,
				-1.0, SIGN.GANTRY, 0.72)


# ============================== COLUMN DRESSING ==============================
## The 53 deck columns (x -780..780 step 30, z=0): dark water-streak quads
## bleeding down from the deck joint, and canon-brand posters pasted low on
## the odd one — the under-freeway register every American city has.
func _column_dressing() -> void:
	var poster_i := 0
	var x := -780.0
	while x <= 780.1:
		var streaks := 1 + (1 if _rng.randf() < 0.45 else 0)
		for _s in streaks:
			var fc := _rng.randi_range(0, 3)
			var w := _rng.randf_range(0.5, 1.1)
			var h := _rng.randf_range(1.8, 3.6)
			var jitter := _rng.randf_range(-0.3, 0.3)
			_streak_xf.append(_column_face_xf(x, fc, jitter, 7.9 - h * 0.5,
				Vector3(w, h, 0.03)))
		if _rng.randf() < 0.26:
			var e: Array = POSTERS[poster_i % POSTERS.size()]
			poster_i += 1
			var fc2 := _rng.randi_range(0, 1)  # posters on the ±Z faces only
			var pj := _rng.randf_range(-0.25, 0.25)
			var pxf := _column_face_xf(x, fc2, pj, 1.7, Vector3(0.74, 1.05, 0.05))
			_poster_xf.append(pxf)
			_poster_col.append(e[1])
			var f := 1.0 if fc2 == 0 else -1.0
			_label(str(e[0]), Vector3(x + pj, 1.7, f * 0.88), f, 26, e[2], 0.68,
				0.0 if f > 0.0 else PI, SIGN.HOARDING, 0.86)  # ±Z, under-deck
		x += COLUMN_STEP
	# Face code: 0=+Z 1=-Z 2=+X 3=-X. Quads sit proud of the 1.6-wide column.


func _column_face_xf(cx: float, fc: int, jitter: float, y: float,
		size: Vector3) -> Transform3D:
	if fc <= 1:
		var zf := 0.845 if fc == 0 else -0.845
		return Transform3D(Basis.IDENTITY.scaled(size),
			Vector3(cx + jitter, y, zf))
	var xf := 0.845 if fc == 2 else -0.845
	return Transform3D(
		Basis(Vector3.UP, PI * 0.5) * Basis.from_scale(size),
		Vector3(cx + xf, y, jitter))


# ============================== FRONTAGE STRIP ===============================
## The retail strip earns its parking: head-in stall paint on the outer half
## of the frontage road in front of every mall (skipping the junker curb
## slots), a dumpster out back, reflector posts along both road edges, and a
## drive-thru lane + menu board at every HOLLERBURGER / CLUCK ALMIGHTY slot
## (identified via city_dressing's SHOPS order — the same modular assignment
## _storefronts uses, read from the same constant).
func _frontage_strip(city: Node3D) -> void:
	var slots: Array[Vector3] = []
	if city.has_method("get_mall_slots"):
		var got: Variant = city.call("get_mall_slots")
		if got is Array:
			for v: Variant in (got as Array):
				if v is Vector3:
					slots.append(v)
	var shops: Array = CITY_DRESSING.SHOPS
	for i in slots.size():
		var slot := slots[i]
		var side := slot.y
		# Stall lines: 8 dividers = 7 stalls across the mall's 26 m frontage.
		for k in 8:
			var lx := slot.x - 10.15 + 2.9 * float(k)
			if side > 0.0 and _near_junker(lx):
				continue
			_white_xf.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.12, 0.02, 4.6)),
				Vector3(lx, FRONTAGE_TOP + 0.045, side * 33.5)))
		# Dumpster behind the mall, jittered along the back wall.
		var dxp := slot.x + _rng.randf_range(-9.0, 9.0)
		var dyaw := _rng.randf_range(-0.15, 0.15)
		_dump_xf.append(Transform3D(
			Basis(Vector3.UP, dyaw) * Basis.from_scale(Vector3(1.9, 1.15, 1.25)),
			Vector3(dxp, 0.55, side * 52.0)))
		_lid_xf.append(Transform3D(
			Basis(Vector3.UP, dyaw) * Basis(Vector3.RIGHT, 0.1) \
			* Basis.from_scale(Vector3(2.0, 0.1, 1.3)),
			Vector3(dxp, 1.16, side * 52.0)))
		# Drive-thru dressing where the brand mapping says so.
		var shop: Array = shops[i % shops.size()]
		if DRIVE_THRU_BRANDS.has(str(shop[0])):
			_drive_thru(slot, shop)
	# Reflector posts along both frontage edges every 40 m (inner edge skips
	# the ramp zones where the slope crowds the shoulder).
	for side2: float in [-1.0, 1.0]:
		var rx := -760.0
		while rx <= 760.0:
			_reflector(Vector3(rx, 0, side2 * 36.5))
			if absf(rx) < 505.0 or absf(rx) > 595.0:
				_reflector(Vector3(rx, 0, side2 * 23.5))
			rx += 40.0


func _near_junker(x: float) -> bool:
	for jx_v: Variant in JUNKER_X:
		if absf(x - float(jx_v)) < 6.5:
			return true
	return false


func _reflector(base: Vector3) -> void:
	_refl_xf.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(0.09, 0.8, 0.09)),
		base + Vector3(0, 0.4, 0)))
	_cap_xf.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(0.11, 0.1, 0.11)),
		base + Vector3(0, 0.84, 0)))


## Drive-thru: a dark lane strip hugging the mall's east flank and back wall,
## white guide dashes down its centre, and a menu board at the back corner.
## Mall box: 26 wide x 12 deep at z = side*44 (front face side*38, back 50).
func _drive_thru(slot: Vector3, shop: Array) -> void:
	var side := slot.y
	var lane_x := slot.x + 14.7          # side lane centre, 1.7 m off the flank
	var lane_y := 0.035                  # prairie top is -0.02
	_dark_xf.append(Transform3D(         # side lane: road edge to past the back
		Basis.IDENTITY.scaled(Vector3(3.2, 0.02, 16.0)),
		Vector3(lane_x, lane_y, side * 45.0)))
	_dark_xf.append(Transform3D(         # back lane behind the mall
		Basis.IDENTITY.scaled(Vector3(18.0, 0.02, 3.2)),
		Vector3(slot.x + 7.3, lane_y, side * 51.6)))
	var dz := side * 38.2
	for _k in 6:                          # guide dashes down the side lane
		_white_xf.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(0.14, 0.02, 1.2)),
			Vector3(lane_x, lane_y + 0.03, dz)))
		dz += side * 2.3
	var bx := slot.x + 11.5
	for _k2 in 6:                         # and along the back lane
		_white_xf.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(1.2, 0.02, 0.14)),
			Vector3(bx, lane_y + 0.03, side * 51.6)))
		bx -= 2.3
	# Menu board tucked against the mall's back corner, out of the lane strip
	# (back wall at side*50, lane inner edge side*50.0 — the board sits in the
	# corner notch beside the side lane), facing cars coming down that lane.
	var mpos := Vector3(slot.x + 13.4, 0, side * 49.5)
	_steel_xf.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(0.12, 1.5, 0.12)),
		mpos + Vector3(0, 0.75, 0)))
	_poster_xf.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(0.95, 1.25, 0.16)),
		mpos + Vector3(0, 2.05, 0)))
	_poster_col.append(shop[1])
	var f := -side   # readable driving outward (+side z) down the side lane
	var yaw := 0.0 if f > 0.0 else PI
	_label(str(shop[0]), mpos + Vector3(0, 2.32, f * 0.1), f, 26, shop[2],
		0.88, yaw, SIGN.FASCIA, 0.30)
	_label("DRIVE-THRU", mpos + Vector3(0, 1.78, f * 0.1), f, 20, shop[2],
		0.88, yaw, SIGN.STENCIL, 0.22)


# ============================== HELPERS ======================================
## M22: the `0.66 x chars` estimate is retired — it under-measured the one
## destination this corridor repeats most. **DOWNTOWN DORADO advances 0.7287 em
## per character**, not 0.66, so on every gantry that named it the sign drew
## 109 % of its board: 8.31 m of letters on a 7.6 m panel, 5.90 m on a 5.4 m
## panel, 4.59 m on the 4.2 m trailblazer. Five gantries, both faces, ten
## signs, and it had never been measured. SIGN measures the actual string.
## GANTRY style is the highway register: even, open tracking, no synthetic
## weight, a thin outline — engineered to be read at 70 mph, not shouted.
## Default yaw ±PI/2 faces ±X (gantry/ramp signage reads along the freeway);
## pass yaw_override (0 or PI) for ±Z-facing text.
func _label(text: String, pos: Vector3, face: float, fsize: int, col: Color,
		max_w: float, yaw_override: float = -1.0, style: int = SIGN.GANTRY,
		max_h: float = 0.0) -> void:
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	if yaw_override >= 0.0:
		lbl.rotation.y = yaw_override
	else:
		lbl.rotation.y = PI * 0.5 * face   # face=+1 -> +X, face=-1 -> -X
	add_child(lbl)


func _flush() -> void:
	# SHADOW POLICY (D-028). Deck paint and the dark drive-thru lane patch are
	# flat on the pavement; 950 instances of it were in every cascade.
	_mm(_white_xf, [], _flat(PAINT_WHITE, true), "FwyPaintWhite", false)
	_mm(_yellow_xf, [], _flat(PAINT_YELLOW, true), "FwyPaintYellow", false)
	_mm(_dark_xf, [], _flat(Color(0.11, 0.11, 0.12), true),
		"FwyDriveThruLanes", false)
	var galv := _flat(GALV, false)
	galv.metallic = 0.4
	galv.roughness = 0.45
	# Guardrail: 842 instances of 0.15 m beam and 0.10 m post standing at the
	# deck EDGE. There is no sun angle where that shadow is worth a cascade —
	# overhead it hides under the rail, low it falls off the side of the deck
	# into open air. The barrier's read comes from its own shading, not a cast.
	_mm(_rail_xf, [], galv, "FwyGuardrails", false)
	# The gantry casts. Steel over a live carriageway laying a bar of shade
	# across four lanes is the signature freeway read at any hour but noon.
	_mm(_steel_xf, [], _flat(STEEL, false), "FwySignSteel", true)
	var green := _flat(SIGN_GREEN, false)
	green.emission_enabled = true            # retroreflective read at night;
	green.emission = SIGN_GREEN              # no texture, so a color is legal
	green.emission_energy_multiplier = 0.5   # well under the 1.05 bloom gate
	_mm(_green_xf, [], green, "FwySignPanels", true)
	var warn := _flat(EXIT_YELLOW, false)
	warn.emission_enabled = true
	warn.emission = EXIT_YELLOW
	warn.emission_energy_multiplier = 0.4
	_mm(_warn_xf, [], warn, "FwyAdvisoryBoards", true)
	var streak := StandardMaterial3D.new()
	streak.albedo_color = Color(0.03, 0.03, 0.04, 0.3)
	streak.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	streak.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# Grime streak: a translucent unshaded decal painted onto a column face.
	_mm(_streak_xf, [], streak, "FwyColumnStreaks", false)
	var poster := StandardMaterial3D.new()
	poster.albedo_color = Color.WHITE
	poster.roughness = 0.9
	poster.vertex_color_use_as_albedo = true
	# Fly-posters are paper flush on a wall. Dumpsters are 1.5 m steel boxes
	# sitting on tarmac and keep theirs — 54 instances, and a dumpster with no
	# contact shadow is the classic floating-prop tell.
	_mm(_poster_xf, _poster_col, poster, "FwyPosters", false)
	_mm(_dump_xf, [], _flat(Color(0.10, 0.22, 0.12), false), "FwyDumpsters", true)
	_mm(_lid_xf, [], _flat(Color(0.07, 0.16, 0.09), false),
		"FwyDumpsterLids", true)
	# Delineator: a 90 mm flexible post with an emissive cap. Hairline shadow,
	# emissive top — neither belongs in a cascade.
	_mm(_refl_xf, [], _flat(Color(0.85, 0.85, 0.82), false),
		"FwyReflectorPosts", false)
	var cap := _flat(Color(0.85, 0.12, 0.1), false)
	cap.emission_enabled = true
	cap.emission = Color(0.85, 0.12, 0.1)
	cap.emission_energy_multiplier = 0.6
	_mm(_cap_xf, [], cap, "FwyReflectorCaps", false)


func _flat(col: Color, unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


## `casts` is required, no default (D-028): a MultiMesh is culled as ONE unit,
## so one visible lane stripe put all 836 of them in every shadow cascade.
func _mm(xf: Array[Transform3D], cols: Array[Color], m: StandardMaterial3D,
		label: String, casts: bool) -> void:
	if xf.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = _unit_mesh
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
