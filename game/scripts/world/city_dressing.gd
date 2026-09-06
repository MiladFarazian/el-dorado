extends Node3D
## CITY DRESSING (M8) — the layer that makes the greybox read as a PLACE.
## Lane paint, crosswalks, streetlights, street trees, freeway billboards,
## strip-mall storefront signs, and rooftop skyline signs — every word of
## signage pulled from the canon brand bible (docs/design/naming-bible.md §7:
## parody names only, satire punches at institutions).
##
## CONTRACT: everything here is VISUAL-ONLY (no collision anywhere — you can
## drive through a streetlight; greybox tier accepts that and the smoke
## corridor stays untouched by construction) and uses its OWN seeded RNG, so
## the city's frozen M1 draw stream and the physics world are byte-stable.
## Repeated elements are MultiMeshes: one draw call per element type.

const RNG_SEED := 424242
const EXTRA_SEED := 90210            # M10 ambient upgrades ONLY — never _rng
const DETAIL_SEED := 131313          # M13 street-detail pass ONLY — never _rng
# Street geometry mirrored from greybox_city.gd (the layout source of truth).
const NS_X := [193.0, 279.0, 365.0, 451.0, 537.0, 623.0, 709.0]
const EW_Z := [133.0, 219.0, 305.0, 391.0, 477.0, 563.0]
const NS_Z_RANGE := Vector2(50.0, 546.0)
const EW_X_RANGE := Vector2(110.0, 780.0)
const FRONTAGE_Z := 30.0
const FRONTAGE_X := 754.0
const BLOCK_ORIGIN := Vector2(150.0, 90.0)
const BLOCK_PITCH := 86.0
const GRID_COLS := 8
const GRID_ROWS := 6
const DASH_STEP := 7.0               # one 3 m dash every 7 m
const LIGHT_STEP := 46.0             # streetlight spacing along a street edge
const PAINT_Y := 0.045               # above both street-bed slab tops (0.0/0.01)
const SLAB_TOP := 0.2                # raised block slabs — trees stand on these

# ===== C4 RIGHT-OF-WAY GEOMETRY — "nothing stands in the roadway" ============
# greybox_city.STREET is 26 m, so the KERB FACE is at |13.0| from every street
# centreline and the raised block slab (SLAB_TOP) begins there. Milad, cycle 4:
# "improve streetlight placement (rn some have poles in the middle of the
# street)." He was right about every pole family downtown:
#   cobra streetlights   |11.4|  -> 1.6 m INSIDE the traffic lane
#   mast-arm signals     |12.6|  -> 0.4 m INSIDE, on both axes
#   ped heads + blades   ride those masts, so they were in the roadway too
# One number now governs every downtown pole: POLE_OFF. It is not arbitrary —
# it is the only offset in this city that clears BOTH kerbs and every existing
# sidewalk furniture line at once, and it was picked by measuring them:
#   kerb face      13.00        pole face at 13.86 -> 0.86 m of clear walk
#   parking meters 13.45 (±0.03) -> 0.52 m clear
#   hydrants       13.60 (±0.15) -> 0.26 m clear
#   bins           13.60 (±0.31) -> 0.10 m clear
#   benches        14.60 (±0.25) -> 0.21 m clear
#   planters       14.60 (±0.45) -> 0.01 m clear  (the binding constraint)
# The mast ARM grows by exactly the distance the base moved, so every luminaire
# and every signal head keeps the lane it always covered.
const KERB := 13.0                   # kerb face |offset| from a street centreline
const POLE_OFF := 14.0               # every downtown pole base: 1.0 m behind it
const LIGHT_ARM := 4.6               # cobra arm (was 3.4 when the base was 11.4)
const LIGHT_REACH := 4.3             # luminaire out along the arm (was 3.1)
const MAST_ARM := 8.4                # signal mast arm (was 7.0 at |12.6|)
const MAST_REACH := 7.6              # signal head out along the arm (was 6.2):
                                     # 14.0 - 7.6 = 6.4, the exact distance the
                                     # M8 head stood at, so nothing moved along
                                     # the arm axis — only the base came out.
const FRONT_ARM := 3.4               # frontage roads keep the M8 arm verbatim:
const FRONT_REACH := 3.1             # their poles were ALREADY clear of the road
# Intersection paint (defect D-040, "paint pile-up"). The M8 crossing sat at
# |10.4| — 2.6 m INSIDE the 26x26 intersection box — so every zebra ended in
# the cross street's roadway instead of at a kerb, and the stop bar sat at
# |13.6|, inside the crossing's own approach. Both move out together (the move
# QA authorised this cycle): the crossing lands on the corner slabs, the bar
# lands behind it, and the longitudinal lines stop before both.
const XWALK_OFF := 15.5              # zebra centreline (was 10.4)
const XWALK_HALF := 1.7              # half the crossing's 3.4 m width
const BAR_OFF := 18.6                # stop bar (was 13.6). The crossing's far
                                     # edge is at 17.2 and the bar's near edge
                                     # at 18.35, so a driver gets the 1.15 m of
                                     # clear asphalt a stop bar is set back by
const EDGE_OFF := 12.5               # white edge line (was 11.0): 0.5 m off the
                                     # kerb face, so the road's edge reads as the
                                     # road's edge and every pole is BEYOND it
const PAINT_GAP := 20.0              # edge lines stop this far out: 1.15 m
                                     # clear of the stop bar's outer edge
const DASH_GAP := 22.0               # centre line and lane line stop here. They
                                     # run on a 7 m dash grid, so the gap has to
                                     # cover the WHOLE 3 m dash that straddles
                                     # it — at 22 the nearest dash still ends
                                     # 1.65 m short of the bar

# The freeway billboard rotation — canon §7. (name, slogan, panel bg, text fg)
const BILLBOARDS: Array = [
	["HOLLERBURGER", "IT'S BIGGER DOWN HERE", Color(0.72, 0.13, 0.1), Color(1.0, 0.94, 0.8)],
	["THE TEXAS SLEDGEHAMMER", "1-800-WRECKED · SE HABLA JUSTICE", Color(0.08, 0.12, 0.3), Color(1.0, 0.83, 0.25)],
	["PARLAYPAL", "A FORECAST YOU CAN BUY™", Color(0.05, 0.42, 0.26), Color(0.95, 0.98, 0.95)],
	["DR. ZING", "24 FLAVORS. ONE IS CLASSIFIED.", Color(0.42, 0.08, 0.12), Color(0.98, 0.92, 0.8)],
	["SMOKE 'EM IF YOU GOT 'EM", "NOW LEGAL / NEVER MIND / ASK BUBBA", Color(0.07, 0.07, 0.07), Color(0.62, 0.95, 0.3)],
	["THE PECOS BULLET", "ARRIVING IN: 7 YEARS", Color(0.78, 0.8, 0.82), Color(0.1, 0.15, 0.35)],
	["BOONE TRUCKS", "APPRECIATE YOU!", Color(0.12, 0.3, 0.6), Color(1.0, 1.0, 1.0)],
	["HARVEST HILLS™", "HOMES FROM THE $400s. TREES FROM 2041.", Color(0.5, 0.72, 0.85), Color(1.0, 1.0, 1.0)],
	["OMNIMIND", "AGI IN 18 MONTHS", Color(0.94, 0.94, 0.94), Color(0.1, 0.1, 0.1)],
	["T-GRID", "THE GRID IS FINE.", Color(0.35, 0.35, 0.37), Color(1.0, 0.72, 0.2)],
	["GIGASTEAD", "YOUR NEIGHBORS ALREADY SAID YES", Color(0.1, 0.14, 0.12), Color(0.4, 0.9, 0.55)],
	["Y'ALLMART", "WE'RE WHY YOUR TOWN LOOKS LIKE THIS", Color(0.15, 0.35, 0.68), Color(1.0, 0.85, 0.2)],
	["AMPT MOTORS", "THE WEDGENEER. ZERO REGRETS*", Color(0.85, 0.86, 0.88), Color(0.75, 0.1, 0.1)],
	["CLUCK ALMIGHTY", "CLOSED SUNDAY. BLESSED ALWAYS.", Color(0.95, 0.93, 0.88), Color(0.75, 0.12, 0.1)],
	["WOOLY COOLERS", "COLD FOR 11 GENERATIONS", Color(0.82, 0.75, 0.6), Color(0.15, 0.2, 0.35)],
	["PARLAYPAL SPORTSBOOK LOUNGE", "YOU CAN'T LOSE IF YOU NEVER STOP", Color(0.05, 0.32, 0.2), Color(1.0, 0.9, 0.4)],
]
# Strip-mall storefronts — canon §7 retail. (name, sign bg, text fg)
const SHOPS: Array = [
	["KWIKSIP", Color(0.85, 0.2, 0.15), Color(1, 1, 1)],
	["11SEVEN", Color(0.95, 0.55, 0.1), Color(0.15, 0.3, 0.2)],
	["SCORCHY'S", Color(0.8, 0.25, 0.1), Color(1.0, 0.9, 0.6)],
	["CLUCK ALMIGHTY", Color(0.92, 0.9, 0.85), Color(0.75, 0.12, 0.1)],
	["T-E-X GROCERY", Color(0.75, 0.1, 0.1), Color(1, 1, 1)],
	["CAYENNES", Color(0.35, 0.1, 0.1), Color(0.95, 0.75, 0.3)],
	["VARSITY SPORTS + AMMO", Color(0.15, 0.25, 0.5), Color(1.0, 0.85, 0.3)],
	["HOLLERBURGER", Color(0.72, 0.13, 0.1), Color(1.0, 0.94, 0.8)],
	["MAY BELLE COSMETICS", Color(0.9, 0.7, 0.8), Color(0.4, 0.15, 0.3)],
	["SHINDIG BOCK ICEHOUSE", Color(0.5, 0.32, 0.15), Color(1.0, 0.9, 0.7)],
	["PRIMEMALE PROTOCOL", Color(0.1, 0.1, 0.12), Color(0.85, 0.9, 1.0)],
	["FENCE POST RANCH WATER", Color(0.7, 0.85, 0.8), Color(0.2, 0.3, 0.3)],
	["LONGHORN WRECKER & RECOVERY", Color(0.55, 0.14, 0.1), Color(1.0, 0.9, 0.75)],
	["BASSMAN'S BAIT OUTPOST", Color(0.2, 0.35, 0.3), Color(0.95, 0.85, 0.5)],
]
# Rooftop skyline signs — the institutions get the high ground. (name, color)
const ROOFTOPS: Array = [
	["BOLO CAPITAL", Color(1.0, 0.75, 0.2)],
	["CLINGTEL", Color(0.3, 0.7, 1.0)],
	["TEXOTRONICS", Color(0.9, 0.3, 0.25)],
	["OMNIMIND", Color(0.92, 0.92, 0.95)],
	["LONGHORN DYNAMICS", Color(0.45, 0.95, 0.6)],
	["BLUR+", Color(0.7, 0.4, 0.95)],
]

const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")

var _rng := RandomNumberGenerator.new()
# M15 de-blocking: extra canopy-lobe randomness rides its OWN stream so the
# shared _rng draw order stays frozen (the _tree call still makes exactly the
# same two _rng draws it always has).
var _blob_rng := RandomNumberGenerator.new()
var _dash_xf: Array[Transform3D] = []
var _stripe_xf: Array[Transform3D] = []
var _pole_xf: Array[Transform3D] = []
var _arm_xf: Array[Transform3D] = []
var _head_xf: Array[Transform3D] = []
var _trunk_xf: Array[Transform3D] = []
var _canopy_xf: Array[Transform3D] = []
var _canopy_col: Array[Color] = []
var _head_body_xf: Array[Transform3D] = []   # traffic signal housings
var _red_xf: Array[Transform3D] = []
var _amber_xf: Array[Transform3D] = []
var _grn_xf: Array[Transform3D] = []
# Hydrant/bin BASE positions (M10): recorded here — with the exact same _rng
# draws as when they were MultiMeshes — and handed to interactables.gd, which
# stands real knockable physics props on them.
var _hydrant_spots: Array[Vector3] = []
var _bin_spots: Array[Vector3] = []
var _unit_mesh := BoxMesh.new()
# C4 pole siting. `_c4_obs` is a read-only plan-space obstruction map (podium
# footprints and their sidewalk canopies, as x, z, half-x, half-z) taken from
# greybox_city's own record — no rng, no replay. `_c4_poles` is where every
# cobra base actually ended up, so the transit pass can keep a bus shelter off
# a lamp post.
var _c4_obs: Array[Vector4] = []
var _c4_poles: Array[Vector2] = []


func build(city: Node3D) -> void:
	_rng.seed = RNG_SEED
	_blob_rng.seed = 424243  # M15 canopy lobes ONLY — never _rng
	_unit_mesh.size = Vector3.ONE
	_lane_paint()
	_edge_lines()
	_crosswalks()
	_stop_bars()
	_turn_arrows()
	_streetlights(city)
	_traffic_signals()
	_trees(city)
	_street_furniture()
	_utility_poles()
	_billboards()
	_storefronts(city)
	_rooftop_signs(city)
	_flush()
	# M10 ambient upgrades — appended at the END only (never reorder the steps
	# above: the shared _rng draw order is a frozen contract). Their placement
	# randomness comes from a fresh RNG with its own literal seed.
	_benches_and_planters()
	_tire_wear()
	# M13 street-detail pass — same append-only law, own seed (DETAIL_SEED).
	_street_detail()
	_power_lines()
	# M14 storefront/facade pass — same append-only law; its fresh literal seed
	# lives in _facade_pass. Called last: every frozen draw stream above is done.
	_facade_pass(city)
	# M16 right-of-way quality pass — same append-only law, own literal seed
	# (ROW_SEED). Makes ZERO draws on the shared _rng; every element ships in its
	# own MultiMesh because _flush() above has already run.
	_right_of_way(city)
	# M18 signal-cycle pass — same append-only law. Makes ZERO rng draws of any
	# kind (every lens position is a literal), and ships hidden: the runtime
	# system in scripts/systems/signal_cycle.gd is what turns it on.
	_signal_cycle_pass()
	# M20 Stonebridle Ranch lane pass (defect D-011) — same append-only law,
	# own literal seed. Paints the residential plat greybox_city publishes, and
	# nudges the handful of yard trees that stand in the new pavement. Runs
	# LAST because it rewrites instances in MultiMeshes _flush() already built.
	_suburb_lanes_pass(city)


# ============================== LANE PAINT ===================================
## Dashed center lines on every downtown street + solid-ish frontage edges.
## Thin unshaded boxes floated 4.5 cm over the asphalt — no z-fighting, no
## collision, and MultiMesh makes ~1400 dashes one draw call.
## C4 (D-040): the centre line used to run STRAIGHT THROUGH every intersection,
## so the north-south dashes and the east-west dashes crossed each other inside
## the box, on top of the zebra bars, on top of the stop bar — which is most of
## what "a pile of white rectangles with no readable order" was. No centreline
## in any country is painted through a signalised box: it stops at the crossing.
## It stops here now. Zero rng draws in this function, before or after.
func _lane_paint() -> void:
	for x in NS_X:
		var z := NS_Z_RANGE.x
		while z <= NS_Z_RANGE.y:
			if not _row_near(z, EW_Z, DASH_GAP):
				_dash_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.22, 0.02, 3.0)),
					Vector3(x, PAINT_Y, z)))
			z += DASH_STEP
	for z2 in EW_Z:
		var x2 := EW_X_RANGE.x
		while x2 <= EW_X_RANGE.y:
			if not _row_near(x2, NS_X, DASH_GAP):
				_dash_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(3.0, 0.02, 0.22)),
					Vector3(x2, PAINT_Y, z2)))
			x2 += DASH_STEP
	for side: float in [-1.0, 1.0]:  # frontage center dashes
		var fx := -FRONTAGE_X
		while fx <= FRONTAGE_X:
			_dash_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(3.0, 0.02, 0.22)),
				Vector3(fx, PAINT_Y + 0.06, side * FRONTAGE_Z)))
			fx += DASH_STEP


## Solid white edge lines down both sides of every street: the single biggest
## "this is a real road" cue after the centre line. Continuous, not dashed.
## C4, two fixes in one zero-rng function:
##  (a) the line moved from |11.0| to |12.5|. At 11.0 it marked nothing — it sat
##      2 m short of the kerb with the streetlight poles standing BEYOND it, in
##      the gutter, which is precisely how a pole reads as "in the middle of the
##      street". At 12.5 it is 0.5 m off the kerb face, it is the edge of the
##      travelled way, and every pole in the city is now outside it.
##  (b) it no longer runs through the intersections. A solid white line crossing
##      another solid white line on top of a crossing is the other half of
##      D-040. Runs are cut PAINT_GAP clear of every cross centreline and then
##      chopped into <=24 m pieces exactly as before.
func _edge_lines() -> void:
	for x in NS_X:
		for s: float in [-1.0, 1.0]:
			for run: Vector2 in _paint_runs(NS_Z_RANGE, EW_Z):
				var z := run.x
				while z < run.y:
					var seg := minf(24.0, run.y - z)
					_stripe_xf.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.16, 0.02, seg)),
						Vector3(x + s * EDGE_OFF, PAINT_Y, z + seg * 0.5)))
					z += seg
	for z2 in EW_Z:
		for s2: float in [-1.0, 1.0]:
			for run2: Vector2 in _paint_runs(EW_X_RANGE, NS_X):
				var x2 := run2.x
				while x2 < run2.y:
					var seg2 := minf(24.0, run2.y - x2)
					_stripe_xf.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(seg2, 0.02, 0.16)),
						Vector3(x2 + seg2 * 0.5, PAINT_Y, z2 + s2 * EDGE_OFF)))
					x2 += seg2


## Split a street's length into the runs that carry continuous paint: the whole
## span minus a PAINT_GAP-wide throat at every crossing. Pure function of two
## literal lists — no rng, and identical every boot.
func _paint_runs(span: Vector2, crossings: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	var cursor := span.x
	for c: Variant in crossings:
		var cv := float(c)
		var a := cv - PAINT_GAP
		var b := cv + PAINT_GAP
		if b <= span.x or a >= span.y:
			continue
		if a > cursor:
			out.append(Vector2(cursor, minf(a, span.y)))
		cursor = maxf(cursor, b)
	if cursor < span.y:
		out.append(Vector2(cursor, span.y))
	return out


## Stop bars: a fat white band across each approach's lanes at every
## intersection. C4 — the coordinated move QA authorised. The bar was at |13.6|,
## which put it INSIDE the crossing it is supposed to stand behind (the M8 zebra
## was at |10.4| and 3.4 m wide, so it reached 12.1). It now sits at |18.0|:
## 0.8 m clear behind the relocated crossing, in approach order (bar, then
## zebra, then the box), which is the order a driver meets them in.
## The band also grew from 10.0 m to 12.0 m and re-centred from |5.4| to |6.4|,
## so it spans 0.4 -> 12.4 and dies on the new edge line at 12.5 instead of
## stopping 2 m short of it in open asphalt. Zero rng draws, before and after.
## traffic.gd's SIG_BAR moved with it — the shells stop on the paint, not 4.4 m
## past it.
func _stop_bars() -> void:
	for cx in NS_X:
		for cz in EW_Z:
			for s: float in [-1.0, 1.0]:
				_stripe_xf.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(12.0, 0.02, 0.5)),
					Vector3(cx + s * 6.4, PAINT_Y, cz + s * BAR_OFF)))
				_stripe_xf.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.5, 0.02, 12.0)),
					Vector3(cx + s * BAR_OFF, PAINT_Y, cz - s * 6.4)))


## Through arrows in the inside travel lane on the approach to each
## intersection: a shaft plus a chevron head, painted from three boxes.
##
## C4, TWO DEFECTS, both photographed at `street_north` before the fix:
##  1. HALF OF THE 84 ARROWS WERE BROKEN GEOMETRY. The head legs were yawed by
##     `s * 0.7` in a frame that never flipped, while the TIP flipped with the
##     approach — so on every `s < 0` approach (42 arrows, and the one nearest
##     the `street_north` camera is one of them) the two legs ran from a metre
##     BEHIND the tip out to level with it, crossing the shaft. It rendered as a
##     three-legged asterisk, not an arrow. The fix is to yaw the WHOLE marking:
##     one canonical shape pointing -Z, turned 180 deg for the other approach.
##  2. It sat at |3.0| while traffic.gd drives the inner lane at |3.5| and the
##     tyre-wear strips are painted at |3.5| — the arrow was half a metre off
##     its own lane. It is on the lane centre now, and the shaft grew from
##     0.34 x 3.4 m to 0.5 x 4.6 m, which is inside the real 0.3-0.6 m stem /
##     4.6 m minimum for a lane arrow and is legible from a moving car.
## The docstring said "left-turn"; the geometry has always drawn a THROUGH
## arrow, and a through arrow is the honest marking here — traffic.gd drives
## this lane straight ahead, and a left-only arrow over a lane the city's own
## traffic drives through would be a lane-logic lie. Zero rng draws.
func _turn_arrows() -> void:
	for cx in NS_X:
		for cz in EW_Z:
			for s: float in [-1.0, 1.0]:
				_arrow(Vector3(cx + s * 3.5, PAINT_Y, cz + s * 22.0), s > 0.0)


func _arrow(pos: Vector3, southbound: bool) -> void:
	# ONE yaw for the whole marking. rot * from_scale, NOT Basis.scaled() — the
	# latter scales in GLOBAL axes and shears a rotated box (it mangled this
	# arrowhead once, and shearing was never the only thing wrong with it).
	var yaw := Basis(Vector3.UP, 0.0 if southbound else PI)
	_stripe_xf.append(Transform3D(yaw * Basis.from_scale(Vector3(0.5, 0.02, 4.6)),
		pos))
	# Canonical frame points -Z: the tip is the shaft's -Z end (z = -2.3) and the
	# legs splay back from it. Leg half-length 0.7 along (sin 0.7, 0, cos 0.7),
	# so the inner end lands exactly ON the tip and the outer end 0.90 m out and
	# 1.07 m back — a 1.8 m head on a 0.5 m stem.
	for s: float in [-1.0, 1.0]:
		var leg := Basis(Vector3.UP, s * 0.7) * Basis.from_scale(Vector3(0.34, 0.02, 1.4))
		_stripe_xf.append(Transform3D(yaw * leg,
			pos + yaw * Vector3(s * 0.451, 0, -1.764)))


## Zebra bands across each street mouth at every downtown intersection.
##
## C4 — the relocation M16 identified and deferred, and QA authorised this
## cycle. The bands were at |10.4|, 2.6 m INSIDE the 26x26 intersection box, so
## both ends of every crossing died in the middle of the cross street's roadway
## instead of at a kerb: a crossing that starts and ends in traffic. At |15.5|
## the crossing clears the box and both ends land on the corner slabs — the
## outermost bar reaches |12.45| and the kerb is at |13.0|, 0.55 m of gutter to
## spare, which is where a crossing actually meets a curb ramp. The ramps in
## _row_curb_ramps were re-keyed to match. Zero rng draws, before and after.
func _crosswalks() -> void:
	for xi in NS_X.size():
		for zi in EW_Z.size():
			var cx: float = NS_X[xi]
			var cz: float = EW_Z[zi]
			for k in 5:  # north + south mouths: stripes run east-west
				var off := -6.0 + 3.0 * float(k)
				for s: float in [-1.0, 1.0]:
					_stripe_xf.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.9, 0.02, 3.4)),
						Vector3(cx + off, PAINT_Y, cz + s * XWALK_OFF)))
					_stripe_xf.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(3.4, 0.02, 0.9)),
						Vector3(cx + s * XWALK_OFF, PAINT_Y, cz + off)))


# ============================== STREETLIGHTS =================================
## Cobra-head lights along both edges of every NS street and the frontage
## roads: dark pole, arm reaching over the lane, warm emissive head. The heads
## glow through sky_weather's nights for free. Visual-only.
## C4: the pole base moved from |11.4| — 1.6 m inside the traffic lane, in the
## gutter, on the wrong side of its own edge line — to |14.0|, 1.0 m behind the
## kerb face. The base is sited against the retail podiums greybox_city records,
## because a podium can overhang its block edge and a pole inside a shop wall is
## not an improvement on a pole in the road.
func _streetlights(city: Node3D) -> void:
	_c4_load_obstructions(city)
	for x in NS_X:
		var z := NS_Z_RANGE.x + 18.0
		var flip := false
		while z <= NS_Z_RANGE.y - 10.0:
			var side := -1.0 if flip else 1.0  # alternate edges up the street
			_light(_c4_site(x + side * POLE_OFF, z, false), Vector3(-side, 0, 0))
			flip = not flip
			z += LIGHT_STEP
	# The frontage roads were ALREADY clear: their poles stand at |36.6| against
	# a 24..36 carriageway, 0.6 m outside it. Base, arm and luminaire all keep
	# the M8 numbers verbatim so not one frontage light pool moves.
	for side: float in [-1.0, 1.0]:
		var fx := -FRONTAGE_X + 20.0
		while fx <= FRONTAGE_X:
			_light(Vector3(fx, 0.0, side * (FRONTAGE_Z + 6.6)), Vector3(0, 0, -side),
				FRONT_ARM, FRONT_REACH)
			fx += LIGHT_STEP * 1.5


func _light(base: Vector3, toward: Vector3, arm: float = LIGHT_ARM,
		reach: float = LIGHT_REACH) -> void:
	# Local scale THEN rotation (rot * from_scale) — .scaled() would apply the
	# long axis in global space and break the east-west arms.
	var along := Basis.looking_at(toward, Vector3.UP)
	_pole_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.28, 7.6, 0.28)),
		base + Vector3(0, 3.8, 0)))
	# The arm always starts 0.1 m inside the shaft and ends just past the head,
	# so lengthening it to follow the base outward needs no second number.
	_arm_xf.append(Transform3D(along * Basis.from_scale(Vector3(0.22, 0.22, arm)),
		base + Vector3(0, 7.45, 0) + toward * (arm * 0.5 - 0.1)))
	_head_xf.append(Transform3D(along * Basis.from_scale(Vector3(0.5, 0.22, 1.3)),
		base + Vector3(0, 7.28, 0) + toward * reach))
	_c4_poles.append(Vector2(base.x, base.z))


# --------------------------- C4 POLE SITING ----------------------------------
## Read greybox_city's retail-podium record once and turn it into a plan-space
## obstruction map: the podium box itself, and the canopy that grows 0.8 m past
## it on every side. Read-only, no rng draws, safe to call at any point in
## build() because greybox_city has finished before city_dressing starts.
##
## WHY THIS EXISTS. Downtown's sidewalk is not a clean 17 m band. A tower's
## footprint carries +-3 m of jitter, its podium grows 0.75 m past that and its
## canopy 0.8 m past THAT, so on the worst blocks the built edge reaches within
## a metre of the kerb. Measured in-engine before this pass: at |11.4| nothing
## conflicts (which is exactly why M16 kept the poles in the gutter), and at
## |14.0| a handful of stations land inside a podium or under a canopy. Those
## stations slide along the street instead of standing in a wall.
func _c4_load_obstructions(city: Node3D) -> void:
	_c4_obs.clear()
	if not city.has_method("get_podium_xforms"):
		return
	var got: Variant = city.call("get_podium_xforms")
	if not (got is Array):
		return
	for v: Variant in (got as Array):
		if not (v is Transform3D):
			continue
		var p := v as Transform3D
		_c4_obs.append(Vector4(p.origin.x, p.origin.z,
			absf(p.basis.x.x) * 0.5 + 0.8, absf(p.basis.z.z) * 0.5 + 0.8))


## True when a 0.28 m pole standing here would be inside a podium or under a
## canopy lip (0.25 m of breathing room on top of the pole's own half-width).
func _c4_blocked(px: float, pz: float) -> bool:
	for o in _c4_obs:
		if absf(o.x - px) < o.z + 0.39 and absf(o.y - pz) < o.w + 0.39:
			return true
	return false


## THE SECOND POLE DEFECT, found by auditing rather than by looking: getting the
## lateral offset right is not enough, because a pole 1.0 m behind the kerb of
## the avenue it lights is still standing in the middle of the CROSS street if
## its station lands in an intersection throat. `_streetlights` walks a flat
## 46 m rhythm from z = 68 with no reference to the grid at all, and the grid
## pitch is 86 — so the rhythm drifts into a crossing four times per avenue.
## Measured before this fix: 21 M8 cobra poles and their 21 M16 mates stood
## inside an east-west roadway, three of them 1.0 m off its centreline.
## (M16 knew about this class of bug — its own EW lighting is block-locked "so a
## head can never land in an intersection throat" — but it never went back and
## applied the same rule to the M8 north-south rhythm it was infilling.)
##
## A station inside a throat is pushed to 18 m clear of that crossing, which is
## just past the stop bar and beside nothing, and its M16 mate follows because
## both loops walk the same literal z sequence. Then, and only then, podium
## conflicts slide it 3-9 m more.
func _c4_site(px: float, pz: float, slide_x: bool) -> Vector3:
	var ax := px
	var az := pz
	if slide_x:
		ax = _c4_throat(ax, NS_X)
	else:
		az = _c4_throat(az, EW_Z)
	if not _c4_blocked(ax, az):
		return Vector3(ax, 0.0, az)
	for d: float in [3.0, -3.0, 6.0, -6.0, 9.0, -9.0]:
		var qx := ax + (d if slide_x else 0.0)
		var qz := az + (0.0 if slide_x else d)
		if not _c4_blocked(qx, qz) and _c4_throat(qz if not slide_x else qx,
				EW_Z if not slide_x else NS_X) == (qz if not slide_x else qx):
			return Vector3(qx, 0.0, qz)
	return Vector3(ax, 0.0, az)


## Push a station out of any intersection throat. 16 m is the test (3 m of slack
## past the 13 m kerb line) and 18 m is the landing, so a pole never lands ON the
## boundary and never lands beside the corner mast at |14|.
func _c4_throat(v: float, crossings: Array) -> float:
	for c: Variant in crossings:
		var cv := float(c)
		var d := v - cv
		if absf(d) < 16.0:
			return cv + (18.0 if d >= 0.0 else -18.0)
	return v


# ============================== TRAFFIC SIGNALS ==============================
## Mast-arm signals on the near-right corner of each downtown intersection: a
## pole, an arm reaching over the lanes, and a three-lens head. The lenses are
## emissive so they read at night; the phase is baked per intersection (a live
## signal system would have to argue with traffic.gd, which is M11's problem).
func _traffic_signals() -> void:
	for xi in NS_X.size():
		for zi in EW_Z.size():
			var cx: float = NS_X[xi]
			var cz: float = EW_Z[zi]
			# Two opposing corners, arms reaching across the approach lanes.
			# C4: the corner offset was |12.6| on both axes — 0.4 m inside the
			# roadway on both, i.e. a signal mast standing in the intersection.
			# POLE_OFF puts it on the corner slab; MAST_REACH grows by the same
			# 1.4 m, so the head hangs exactly where it always did.
			_signal(Vector3(cx + POLE_OFF, 0.0, cz + POLE_OFF), Vector3(0, 0, -1),
				(xi + zi) % 2 == 0)
			_signal(Vector3(cx - POLE_OFF, 0.0, cz - POLE_OFF), Vector3(0, 0, 1),
				(xi + zi) % 2 == 0)


func _signal(base: Vector3, toward: Vector3, green: bool) -> void:
	var along := Basis.looking_at(toward, Vector3.UP)
	_pole_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.24, 6.4, 0.24)),
		base + Vector3(0, 3.2, 0)))
	_arm_xf.append(Transform3D(along * Basis.from_scale(Vector3(0.18, 0.18, MAST_ARM)),
		base + Vector3(0, 6.25, 0) + toward * (MAST_ARM * 0.5 - 0.1)))
	var head_pos := base + Vector3(0, 5.55, 0) + toward * MAST_REACH
	_head_body_xf.append(Transform3D(along * Basis.from_scale(Vector3(0.34, 1.0, 0.3)),
		head_pos))
	# Three lenses; only the live one is bright.
	var lenses := [_red_xf, _amber_xf, _grn_xf]
	for i in 3:
		var lit := (i == 2) if green else (i == 0)
		var arr: Array[Transform3D] = lenses[i]
		if lit:
			arr.append(Transform3D(along * Basis.from_scale(Vector3(0.2, 0.2, 0.08)),
				head_pos + Vector3(0, 0.33 - 0.33 * float(i), 0) + toward * 0.17))


# ============================== STREET FURNITURE =============================
## Hydrants and trash cans along the block edges. M10: no longer drawn here —
## the SAME seeded draws (side, jitter, roll: the order is a frozen contract)
## now only record WHERE, and interactables.gd spawns physics props there.
func _street_furniture() -> void:
	for x in NS_X:
		var z := NS_Z_RANGE.x + 30.0
		while z <= NS_Z_RANGE.y - 20.0:
			var side := -1.0 if _rng.randf() < 0.5 else 1.0
			var p := Vector3(x + side * 13.6, SLAB_TOP, z + _rng.randf_range(-8.0, 8.0))
			var roll := _rng.randf()
			if roll < 0.45:
				_hydrant_spots.append(p)
			elif roll < 0.75:
				_bin_spots.append(p)
			z += 62.0


## Contracts for interactables.gd (read-only records; no rng replay needed).
func get_hydrant_spots() -> Array[Vector3]:
	return _hydrant_spots.duplicate()


func get_bin_spots() -> Array[Vector3]:
	return _bin_spots.duplicate()


## Suburban utility poles with crossarms — the most North Texas object there is.
func _utility_poles() -> void:
	var x := -580.0
	while x <= 640.0:
		var z := -860.0
		while z <= -200.0:
			_pole_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.3, 9.5, 0.3)),
				Vector3(x, 4.75, z)))
			_arm_xf.append(Transform3D(
				Basis.from_scale(Vector3(2.6, 0.14, 0.14)), Vector3(x, 8.7, z)))
			_arm_xf.append(Transform3D(
				Basis.from_scale(Vector3(1.9, 0.12, 0.12)), Vector3(x, 8.1, z)))
			z += 160.0
		x += 190.0


# ============================== TREES ========================================
## Crepe-myrtle-ish street trees: box trunk + two-tone box canopy. Downtown:
## ringing the LOT blocks (towers own their plazas); suburbs: yard clusters.
func _trees(city: Node3D) -> void:
	var lots: Array[Vector2i] = []
	if city.has_method("get_lot_cells"):
		var got: Variant = city.call("get_lot_cells")
		if got is Array:
			for v: Variant in got:
				if v is Vector2i:
					lots.append(v)
	for cell in lots:
		var cx := BLOCK_ORIGIN.x + BLOCK_PITCH * float(cell.x)
		var cz := BLOCK_ORIGIN.y + BLOCK_PITCH * float(cell.y)
		for k in 8:  # around the lot rim
			var ang := TAU * float(k) / 8.0 + _rng.randf_range(-0.2, 0.2)
			var r := 26.0
			_tree(Vector3(cx + cos(ang) * r, SLAB_TOP,
				cz + sin(ang) * r), _rng.randf_range(0.8, 1.25))
	# Suburb yards: loose rows between the house grid lines.
	var sx := -560.0
	while sx <= 660.0:
		var sz := -840.0
		while sz <= -220.0:
			if _rng.randf() < 0.55:
				# M20 RECORDING ONLY (D-011). Zero added draws and the draw
				# ORDER is byte-identical — the x and z jitters are still drawn
				# building the position, and the scale is still drawn at the
				# call. What is new is that the suburb trees now say WHERE they
				# are and which MultiMesh instances are theirs, because the
				# Stonebridle Ranch plat has to keep its houses off them and
				# has to be able to move the few that stand in new pavement.
				var tp := Vector3(sx + _rng.randf_range(-14, 14), 0.0,
					sz + _rng.randf_range(-14, 14))
				var ti := _trunk_xf.size()
				var ci := _canopy_xf.size()
				_tree(tp, _rng.randf_range(0.9, 1.5))
				_sub_trees.append({"pos": tp, "trunk": ti, "can": ci,
					"n": _canopy_xf.size() - ci})
			sz += 80.0
		sx += 95.0


## M15: trees stopped being boxes. Trunk = tapered round limb; canopy = a main
## sphere lobe + 2-3 offset lobes (organic clumping). The TWO historic _rng
## draws (yaw, colour) are preserved verbatim; every extra number comes from
## _blob_rng so all downstream _rng placement stays byte-identical.
func _tree(base: Vector3, s: float) -> void:
	_trunk_xf.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.4, 2.6, 0.4) * s),
		base + Vector3(0, 1.3 * s, 0)))
	var yaw := _rng.randf_range(0.0, TAU)                     # historic draw 1
	var col := Color(0.30, 0.45, 0.22).lerp(Color(0.45, 0.52, 0.2),
		_rng.randf())                                          # historic draw 2
	var rot := Basis(Vector3.UP, yaw)
	var crown := base + Vector3(0, (2.6 + 1.2) * s, 0)
	# M15 (wild-layer find): MultiMesh instance colors skip the sRGB->linear
	# pass that albedo_color gets — convert here or the canopies render pale.
	col = col.srgb_to_linear()
	_canopy_xf.append(Transform3D(rot * Basis.from_scale(Vector3(3.4, 2.9, 3.4) * s), crown))
	_canopy_col.append(col)
	for _l in _blob_rng.randi_range(2, 3):
		var off := Vector3(_blob_rng.randf_range(-1.5, 1.5),
			_blob_rng.randf_range(-0.5, 0.6), _blob_rng.randf_range(-1.5, 1.5)) * s
		var k := _blob_rng.randf_range(0.5, 0.75)
		var b := clampf(_blob_rng.randf_range(0.88, 1.05), 0.0, 1.0)
		_canopy_xf.append(Transform3D(
			rot * Basis.from_scale(Vector3(3.4, 2.9, 3.4) * s * k), crown + off))
		_canopy_col.append(Color(minf(col.r * b, 1.0), minf(col.g * b, 1.0),
			minf(col.b * b, 1.0)))


# ============================== BILLBOARDS ===================================
## Freeway-facing satire: steel post + panel + two Label3D lines, alternating
## sides of the corridor, every brand from the canon rotation exactly once.
func _billboards() -> void:
	var count := BILLBOARDS.size()
	var span := 1440.0
	for i in count:
		var e: Array = BILLBOARDS[i]
		var x := -720.0 + span * (float(i) + 0.5) / float(count) + _rng.randf_range(-18.0, 18.0)
		var side := -1.0 if i % 2 == 0 else 1.0
		var z := side * 56.0
		var face := -side  # panel faces the freeway/frontage
		var h := _rng.randf_range(9.0, 12.5)
		_static_visual(Vector3(0.6, h, 0.6), Vector3(x, h * 0.5, z),
			Color(0.25, 0.26, 0.28), 0.6)
		var panel_c := Vector3(x, h + 2.9, z)
		_static_visual(Vector3(12.0, 6.0, 0.5), panel_c, e[2], 0.85)
		for f: float in [face, -face]:  # both faces read from both directions
			_sign_text(e[0], panel_c + Vector3(0, 0.9, f * 0.34), f, 190, e[3],
				11.2, null, SIGN.HOARDING, 2.40)
			_sign_text(e[1], panel_c + Vector3(0, -1.6, f * 0.34), f, 95, e[3],
				11.2, null, SIGN.HOARDING, 1.30)


# ============================== STOREFRONTS ==================================
## Every strip mall the city recorded gets a lit fascia sign facing its road.
func _storefronts(city: Node3D) -> void:
	if not city.has_method("get_mall_slots"):
		return
	var slots: Variant = city.call("get_mall_slots")
	if not (slots is Array):
		return
	var i := 0
	for v: Variant in (slots as Array):
		if not (v is Vector3):
			continue
		var slot := v as Vector3
		var e: Array = SHOPS[i % SHOPS.size()]
		i += 1
		var side := slot.y                      # mall z = side * 44, faces road
		var face := -side
		var sign_c := Vector3(slot.x, 4.15, side * 44.0 + face * 6.2)
		_static_visual(Vector3(18.0, 1.7, 0.35), sign_c, Color(0.12, 0.12, 0.13), 0.7)
		# FASCIA: a strip-mall sign is height-led, not width-led — the letters
		# are a fixed cap height and the word is however long the word is, which
		# is why KWIKSIP uses a quarter of the board and HOLLERBURGER most of
		# it. `max_h` is the 1.4 m backer plate, so no name can now grow taller
		# than the box it is lit inside.
		_sign_text(e[0], sign_c + Vector3(0, 0, face * 0.24), face, 105, e[2],
			15.5, e[1], SIGN.FASCIA, 1.24)


# ============================== ROOFTOP SIGNS ================================
## The tallest recorded roofs carry the institutions' names in lit letters,
## turned to face downtown's center — the skyline does the satire at night.
func _rooftop_signs(city: Node3D) -> void:
	# One entry per TOWER (greybox_city.get_roof_signs), already sorted tallest
	# first — see that function for why the raw tops array is the wrong list.
	if not city.has_method("get_roof_signs"):
		return
	var tops_v: Variant = city.call("get_roof_signs")
	if not (tops_v is Array):
		return
	var tops: Array = (tops_v as Array)
	var center := Vector2(451.0, 305.0)
	for i in mini(ROOFTOPS.size(), tops.size()):
		var t: Vector4 = tops[i]
		var e: Array = ROOFTOPS[i]
		# M22 FIT: this was `font_size = 300` flat, with no reference to the
		# roof it stands on. LONGHORN DYNAMICS drew 33.7 m of letters across a
		# 26 m tower — 129 % of the roof, overhanging 3.9 m of open air on each
		# side — while BLUR+ used 36 % of the same roof. `t.w` is the recorded
		# footprint (greybox_city stores it in the Vector4's fourth slot and
		# nobody had ever read it), so the sign is now fitted to the building
		# it is bolted to. CHANNEL style: heavy, wide-set letters — the skyline
		# read is the whole point of these six.
		for flipf in 2:
			var lbl := SIGN.make(e[0], SIGN.CHANNEL, e[1], t.w * 0.94, 0.0, 300)
			var to_c := Vector2(center.x - t.x, center.y - t.y)
			var yaw := atan2(to_c.x, to_c.y) + PI * float(flipf)
			# STANDING HEIGHT (M22, screenshot-caught). At `top + 2.6` the sign
			# stood INSIDE the rooftop plant box, which is 4.2 m tall and
			# reaches 0.44 of the footprint out from the centreline — so half
			# of every skyline name was behind concrete. CLINGTEL read
			# "NGTEL" and TEXOTRONICS read "ONICS" from the freeway. Real
			# rooftop letters stand on a frame ABOVE the plant, near the
			# parapet, which is now where these are: clear of the 4.2 m box and
			# pushed out toward the roof edge it faces.
			lbl.position = Vector3(t.x, t.z + 5.4, t.y) \
				+ Vector3(sin(yaw), 0, cos(yaw)) * (t.w * 0.30)
			lbl.rotation.y = yaw
			add_child(lbl)


# ============================== AMBIENT UPGRADES (M10) =======================
## Benches and square planters along the block edges, ~1 per 50 m: wood slat
## top + two dark legs, or a concrete cube with a shrub box. Visual-only MMs,
## deeper on the slab than the (physics) hydrants so they never interleave.
func _benches_and_planters() -> void:
	var xrng := RandomNumberGenerator.new()
	xrng.seed = EXTRA_SEED
	var tops: Array[Transform3D] = []
	var legs: Array[Transform3D] = []
	var planters: Array[Transform3D] = []
	var shrubs: Array[Transform3D] = []
	for x in NS_X:
		var z := NS_Z_RANGE.x + 26.0
		while z <= NS_Z_RANGE.y - 16.0:
			var side := -1.0 if xrng.randf() < 0.5 else 1.0
			# C4: the jitter is +-6 m on a 50 m pitch with no reference to the
			# grid, so 23 of these 70 benches and planters were sitting inside
			# an east-west street's roadway — one of them 0.87 m off its
			# centreline, a park bench in the middle of a road. Pushed clear of
			# the throat. The xrng draw above is unchanged in count and in
			# order; only the number it produced is used differently.
			var p := Vector3(x + side * 14.6, SLAB_TOP,
				_c4_throat(z + xrng.randf_range(-6.0, 6.0), EW_Z))
			if xrng.randf() < 0.55:
				tops.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.5, 0.09, 1.7)), p + Vector3(0, 0.42, 0)))
				for e: float in [-1.0, 1.0]:
					legs.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.46, 0.38, 0.12)), p + Vector3(0, 0.19, e * 0.72)))
			else:
				planters.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.9, 0.9, 0.9)), p + Vector3(0, 0.45, 0)))
				shrubs.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(0.66, 0.5, 0.66)), p + Vector3(0, 1.08, 0)))
			z += 50.0
	# Street furniture is real volume at human scale — the shadow under a bench
	# is most of what stops it floating. All four cast.
	_mmi(tops, Color(0.48, 0.33, 0.18), "BenchTops", false, true)
	_mmi(legs, Color(0.16, 0.16, 0.18), "BenchLegs", false, true)
	_mmi(planters, Color(0.58, 0.57, 0.54), "Planters", false, true)
	_mmi(shrubs, Color(0.28, 0.44, 0.22), "PlanterShrubs", false, true,
		false, MESH_KIT.canopy(0.5, 6, 10, 3, 0.18, 0.07))   # M23: crown, not ball (coarse: shrubs)


## Tire-wear strips: faint translucent darkening down each traffic lane
## (centre ±3.5, traffic.gd's LANE_OFFSET) of every NS and EW street — the
## cheapest "cars live here" cue there is. NS and EW ride different heights so
## their crossings never share a face, and both stay under the paint (0.035).
func _tire_wear() -> void:
	var wear: Array[Transform3D] = []
	for x in NS_X:
		for s: float in [-1.0, 1.0]:
			var z := NS_Z_RANGE.x + 13.0
			while z <= NS_Z_RANGE.y - 11.0:
				wear.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(2.2, 0.015, 22.0)),
					Vector3(x + s * 3.5, 0.027, z)))
				z += 26.0
	for z2 in EW_Z:
		for s2: float in [-1.0, 1.0]:
			var x2 := EW_X_RANGE.x + 13.0
			while x2 <= EW_X_RANGE.y - 11.0:
				wear.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(22.0, 0.015, 2.2)),
					Vector3(x2, 0.023, z2 + s2 * 3.5)))
				x2 += 26.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0, 0, 0, 0.13)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 15 mm translucent decal lying on the asphalt: shadow-free by definition.
	_mmi_build(wear, [], m, "TireWear", false)


# ============================== STREET DETAIL (M13) ==========================
## The "unfinished GTA III -> lived-in city" pass: manholes and storm drains in
## the asphalt, parking meters feeding the M12 curb slots, red no-parking curb
## paint at every corner, patched asphalt scars, and newspaper-box clusters on
## the intersections. All visual-only MultiMeshes off DETAIL_SEED.
func _street_detail() -> void:
	var d := RandomNumberGenerator.new()
	d.seed = DETAIL_SEED
	var manholes: Array[Transform3D] = []
	var grates: Array[Transform3D] = []
	var meter_poles: Array[Transform3D] = []
	var meter_heads: Array[Transform3D] = []
	var curb_red: Array[Transform3D] = []
	var patches: Array[Transform3D] = []
	var patch_col: Array[Color] = []
	var news: Array[Transform3D] = []
	var news_col: Array[Color] = []
	# Manholes: staggered off the centreline, both street grids.
	for x in NS_X:
		var z := NS_Z_RANGE.x + d.randf_range(6.0, 20.0)
		while z <= NS_Z_RANGE.y - 6.0:
			var yaw := d.randf_range(0.0, TAU)
			manholes.append(Transform3D(Basis(Vector3.UP, yaw) \
				* Basis.from_scale(Vector3(0.8, 0.02, 0.8)),
				Vector3(x + (1.8 if d.randf() < 0.5 else -1.8), 0.052, z)))
			z += d.randf_range(34.0, 56.0)
	for z2 in EW_Z:
		var x2 := EW_X_RANGE.x + d.randf_range(6.0, 20.0)
		while x2 <= EW_X_RANGE.y - 6.0:
			var yaw2 := d.randf_range(0.0, TAU)
			manholes.append(Transform3D(Basis(Vector3.UP, yaw2) \
				* Basis.from_scale(Vector3(0.8, 0.02, 0.8)),
				Vector3(x2, 0.052, z2 + (1.8 if d.randf() < 0.5 else -1.8))))
			x2 += d.randf_range(34.0, 56.0)
	# Intersections: storm drains against two corners, curb paint on all four,
	# newspaper boxes on a lucky corner.
	for x3 in NS_X:
		for z3 in EW_Z:
			for _g in 2:
				var sx := -1.0 if d.randf() < 0.5 else 1.0
				var sz := -1.0 if d.randf() < 0.5 else 1.0
				# C4, three literals, zero draws changed. |11.2| put a storm inlet
				# 1.8 m out from the kerb, in the travelled way, lying ACROSS the
				# gutter it is supposed to drain. An inlet takes water from the
				# gutter, so it runs ALONG the kerb: 0.55 x 1.5 turned to 1.5
				# along the street, sitting at 12.5 (outer edge 0.25 m off the
				# kerb face, under the new edge line). And it moved upstream of
				# the relocated crossing — 13.0 -> 18.6 — so no drain now sits in
				# the middle of a zebra.
				grates.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.55, 0.03, 1.5)),
					Vector3(x3 + sx * 12.5, 0.055, z3 + sz * (18.6 + d.randf_range(2.0, 6.0)))))
			for sxf: float in [-1.0, 1.0]:
				for szf: float in [-1.0, 1.0]:
					curb_red.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.22, 0.015, 5.5)),
						Vector3(x3 + sxf * 12.89, SLAB_TOP + 0.007, z3 + szf * 16.5)))
					curb_red.append(Transform3D(Basis.IDENTITY.scaled(Vector3(5.5, 0.015, 0.22)),
						Vector3(x3 + sxf * 16.5, SLAB_TOP + 0.007, z3 + szf * 12.89)))
			if d.randf() < 0.5:
				var cx: float = x3 + (14.6 if d.randf() < 0.5 else -14.6)
				var cz: float = z3 + (14.6 if d.randf() < 0.5 else -14.6)
				for k in d.randi_range(1, 3):
					news.append(Transform3D(
						Basis(Vector3.UP, d.randf_range(-0.15, 0.15)) \
						* Basis.from_scale(Vector3(0.45, 0.85, 0.4)),
						Vector3(cx + 0.55 * float(k), SLAB_TOP + 0.425, cz)))
					news_col.append([Color(0.75, 0.15, 0.12), Color(0.15, 0.3, 0.65),
						Color(0.85, 0.7, 0.15), Color(0.9, 0.9, 0.88)][d.randi_range(0, 3)])
	# Parking meters: sidewalk edge of every NS street, one per M12 curb slot
	# pitch, skipping the intersection throats.
	for x4 in NS_X:
		for side: float in [-1.0, 1.0]:
			var z4 := NS_Z_RANGE.x + 20.0
			while z4 <= NS_Z_RANGE.y - 20.0:
				var near_int := false
				for ez in EW_Z:
					if absf(z4 - ez) < 16.0:
						near_int = true
						break
				if not near_int:
					var mx: float = x4 + side * 13.45
					meter_poles.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.06, 1.15, 0.06)),
						Vector3(mx, SLAB_TOP + 0.575, z4)))
					meter_heads.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.2, 0.28, 0.12)),
						Vector3(mx, SLAB_TOP + 1.27, z4)))
				z4 += 14.0
	# Asphalt scars: dark repair patches and the odd fresh concrete one.
	for _p in 130:
		var on_ns := d.randf() < 0.55
		var px: float; var pz: float
		if on_ns:
			px = NS_X[d.randi_range(0, NS_X.size() - 1)] + d.randf_range(-8.0, 8.0)
			pz = d.randf_range(NS_Z_RANGE.x, NS_Z_RANGE.y)
		else:
			px = d.randf_range(EW_X_RANGE.x, EW_X_RANGE.y)
			pz = EW_Z[d.randi_range(0, EW_Z.size() - 1)] + d.randf_range(-8.0, 8.0)
		patches.append(Transform3D(Basis(Vector3.UP, d.randf_range(-0.2, 0.2)) \
			* Basis.from_scale(Vector3(d.randf_range(1.6, 5.0), 0.012, d.randf_range(1.2, 3.8))),
			Vector3(px, 0.018, pz)))
		patch_col.append(Color(0.075, 0.075, 0.085) if d.randf() < 0.75 \
			else Color(0.30, 0.30, 0.29))
	# Manholes (20 mm), grates (30 mm), curb paint (15 mm) and asphalt scars
	# (12 mm) are all flat in the road surface — nothing to cast. Meters and
	# newspaper boxes are standing props at hip height and keep theirs.
	_mmi(manholes, Color(0.16, 0.16, 0.17), "Manholes", false, false)
	_mmi(grates, Color(0.13, 0.14, 0.16), "StormDrains", false, false)
	_mmi(meter_poles, Color(0.25, 0.26, 0.28), "MeterPoles", false, true)
	_mmi(meter_heads, Color(0.30, 0.32, 0.36), "MeterHeads", false, true)
	_mmi(curb_red, Color(0.62, 0.16, 0.12), "CurbPaint", true, false)
	_mmi_colored(patches, patch_col, "AsphaltPatches", false)
	_mmi_colored(news, news_col, "NewsBoxes", true)


## Overhead wires between the suburb's utility poles (same literal grid as
## _utility_poles): two lines per crossarm, four sagging segments per span —
## the sky stops being empty over the subdivisions.
func _power_lines() -> void:
	var wires: Array[Transform3D] = []
	var x := -580.0
	while x <= 640.0:
		var z := -860.0
		while z <= -200.0 - 160.0:
			for dx: float in [-1.05, 1.05]:
				var y0 := 8.55
				var pts: Array[Vector3] = []
				for s in 5:
					var t := float(s) / 4.0
					var sag := 2.1 * (1.0 - pow(2.0 * t - 1.0, 2.0))
					pts.append(Vector3(x + dx, y0 - sag, z + 160.0 * t))
				for s2 in 4:
					var a := pts[s2]; var b := pts[s2 + 1]
					var mid := (a + b) * 0.5
					var dir := b - a
					wires.append(Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP) \
						* Basis.from_scale(Vector3(0.045, 0.045, dir.length())), mid))
			z += 160.0
		x += 190.0
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.08)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# 45 mm wire at 8.5 m: the shadow is a sub-pixel thread the shadow map
	# cannot resolve anyway, so it costs a cascade draw and renders as aliasing.
	_mmi_build(wires, [], m, "PowerLines", false)


# ============================== HELPERS ======================================
## Billboard and storefront lettering. `max_h` 0 leaves the height free.
## M22: the old `0.66 × chars` estimate is gone — SIGN measures the actual
## string in the actual font (see `sign_kit.gd`); the estimate was under by 10 %
## on wide names and over by 25 % on narrow ones, so boards were simultaneously
## overflowing and half empty.
func _sign_text(text: String, pos: Vector3, face: float, fsize: int, col: Color,
		max_w: float, bg: Variant = null, style: int = SIGN.HOARDING,
		max_h: float = 0.0) -> void:
	if bg is Color:  # optional colored backer behind storefront lettering
		_static_visual(Vector3(max_w * 0.92, 1.4, 0.1),
			pos - Vector3(0, 0, face * 0.06), bg as Color, 0.8, true)
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	lbl.rotation.y = 0.0 if face > 0.0 else PI
	add_child(lbl)


func _static_visual(size: Vector3, pos: Vector3, col: Color, rough: float,
		emissive: bool = false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _unit_mesh
	mi.scale = size
	mi.position = pos
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	if emissive:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.8
	mi.material_override = m
	add_child(mi)


func _flush() -> void:
	# Paint lies in the road: 1,505 dashes + 1,890 markings were the third and
	# fourth biggest shadow sets in the game, and a stripe cannot shade asphalt
	# it is painted onto. Masts, arms and signal housings are the real volume on
	# an intersection and keep their shadows; the lamp and lens glass do not —
	# a 0.2 m emissive lens 9 m up throws a smudge the housing already throws.
	_mmi(_dash_xf, Color(0.85, 0.8, 0.55), "LaneDashes", true, false)
	_mmi(_stripe_xf, Color(0.88, 0.88, 0.86), "RoadMarkings", true, false)
	_mmi(_pole_xf, Color(0.22, 0.23, 0.25), "Poles", false, true)
	_mmi(_arm_xf, Color(0.22, 0.23, 0.25), "Arms", false, true)
	_mmi(_head_xf, Color(1.0, 0.82, 0.45), "LightHeads", false, false, true)
	_mmi(_head_body_xf, Color(0.12, 0.13, 0.14), "SignalHousings", false, true)
	_mmi(_red_xf, Color(1.0, 0.15, 0.1), "SignalRed", false, false, true)
	_mmi(_amber_xf, Color(1.0, 0.65, 0.1), "SignalAmber", false, false, true)
	_mmi(_grn_xf, Color(0.2, 1.0, 0.35), "SignalGreen", false, false, true)
	# Street trees keep theirs — dappled shade on a sidewalk is the single most
	# valuable shadow in the frame and there are only 546 instances of it.
	_mmi(_trunk_xf, Color(0.35, 0.24, 0.16), "TreeTrunks", false, true,
		false, MESH_KIT.round_limb(0.5, 0.34, 1.0, 7))
	_mmi_colored(_canopy_xf, _canopy_col, "TreeCanopies", true,
		MESH_KIT.canopy(0.5, 8, 12, 7))   # M23: a lobed crown (8x12: 10x16 cost 1.8 ms at hospital_door_night, D-046)
	# M23 foliage + wind on the street trees (material only; the seeded draws above are untouched)
	SUB_SHD.apply_wind(self, "TreeCanopies", 0.88, false, 0.05, 0.10, 0.75, 0.0, 1.0, true, 7)


# --------------------------- SHADOW POLICY (D-028) ---------------------------
## `casts` is REQUIRED on all three builders below, and there is no default,
## because a MultiMesh is frustum-culled as ONE unit: a single visible instance
## drags all 2,095 of its siblings into every directional-shadow cascade, every
## frame. This layer alone was pushing 20,090 instances through the shadow pass,
## most of them road paint. A new layer must now state its answer.
##
## The rule, applied per layer with the reason at each call site:
##   flat on the ground (paint, decals, wear, patches, manholes, ramps)  -> OFF
##   thin scatter and wire (power lines)                                 -> OFF
##   emissive lenses and lamp heads (the fixture that holds them casts)  -> OFF
##   sign plates hung on a pole that already casts                       -> OFF
##   real volumes (poles, housings, furniture, trees, masonry)           -> ON
func _mmi(xf: Array[Transform3D], col: Color, label: String, unshaded: bool,
		casts: bool, emissive: bool = false, mesh: Mesh = null) -> void:
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
		m.emission_energy_multiplier = 1.6
	_mmi_build(xf, [], m, label, casts, mesh)


func _mmi_colored(xf: Array[Transform3D], cols: Array[Color], label: String,
		casts: bool, mesh: Mesh = null) -> void:
	if xf.is_empty():
		return
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = 0.95
	m.vertex_color_use_as_albedo = true
	_mmi_build(xf, cols, m, label, casts, mesh)


func _mmi_build(xf: Array[Transform3D], cols: Array[Color],
		m: Material, label: String, casts: bool,
		mesh: Mesh = null) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = not cols.is_empty()
	mm.mesh = mesh if mesh != null else _unit_mesh
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


# ============================== FACADE PASS (M14) ============================
## Storefront depth on the retail podiums, rooftop/wall clutter, and blade
## signs on the main drags. All geometry lives in facade_kit.gd — this hands
## it the podium transforms greybox_city recorded, the canon SHOPS registry
## (naming bible §7 — never invent a brand), and a FRESH RNG with its own
## literal seed, so the shared _rng draw order stays a frozen contract.
func _facade_pass(city: Node3D) -> void:
	if not city.has_method("get_podium_xforms"):
		return
	var got: Variant = city.call("get_podium_xforms")
	if not (got is Array):
		return
	var podiums: Array[Transform3D] = []
	for v: Variant in (got as Array):
		if v is Transform3D:
			podiums.append(v)
	if podiums.is_empty():
		return
	var kit: GDScript = load("res://scripts/world/facade_kit.gd")
	if kit == null:
		return
	var frng := RandomNumberGenerator.new()
	frng.seed = 8140917  # M14 facade pass ONLY — never _rng
	kit.build(self, podiums, frng, SHOPS)


## Contract for streetlight_glow.gd (read-only record, no rng replay): the
## world transform of every cobra light head — origin is the head centre and
## the basis is looking_at(toward the street), so callers can recover both
## position and throw direction. Traffic-signal heads live in a different
## array (_head_body_xf) and are NOT included. M16 appends its EW-street,
## intersection and frontage-infill heads to the SAME array (after _flush, so
## they draw from their own MultiMesh) — the contract promises "every cobra
## head", and streetlight_glow reads it long after build() returns.
func get_streetlight_head_xfs() -> Array[Transform3D]:
	return _head_xf.duplicate()


# ======================= RIGHT-OF-WAY QUALITY (M16) ==========================
## The finishing pass on everything between the curbs. Appended whole under the
## house law: ZERO draws on the shared `_rng` (this pass owns ROW_SEED), and
## every element ships in a NEW MultiMesh because _flush() already ran.
##
## What it adds, and why:
##  1. WAYFINDING — paired street-name blades on two diagonal corners of all 42
##     downtown intersections. A blade is mounted PARALLEL to the street it
##     names and faces the approach that needs it, so every one of the four
##     approaches reads the cross-street name on its right. Names are canon §4
##     where canon has one and descriptive genericisms (numbered streets) where
##     it does not — never an invented proper name.
##  2. INTERSECTION COMPLETENESS — the M8 build gave every intersection two
##     mast-arm signals, BOTH serving the north-south approaches; the east-west
##     approaches had no signal head at all. This adds the missing two masts on
##     the two free corners (so all four corners now carry a pole), running the
##     COMPLEMENT of the baked NS phase so an intersection can no longer show
##     green in both directions. Plus pedestrian heads + push buttons on all
##     four poles (WALK is on exactly when the parallel traffic is stopped),
##     directional curb ramps with tactile pads at all eight crosswalk
##     landings, and the outer zebra bars the M8 crosswalks were missing.
##  3. LANE LOGIC — a dashed white lane line at |7 m| on every downtown street.
##     The 26 m section was previously a centre line and two edge lines with
##     nothing between: this makes the inner travel lane (centre 3.5 m, exactly
##     where traffic.gd drives and where the tire wear already is) and the
##     outer curb/parking lane (centre 9 m, where the meters are) explicit.
##  4. NIGHT RHYTHM — the east-west streets had NO streetlights whatsoever and
##     the intersections had none either. Both are filled: block-locked cobra
##     heads at 43 m staggered on all six EW streets, a luminaire arm added to
##     each intersection's northwest signal pole, and the frontage roads' 69 m
##     spacing halved to 34.5 m. Every new head is registered with the
##     streetlight_glow contract so the pools follow.
##  5. TRANSIT — MART bus stops (canon §4) on the avenues: shelter, bench, lit
##     ad panel, flag blade with route number, red bus zone at the curb.
##
## Height stratum (audited, unchanged): bed 0.0 / 0.01 · patches 0.018 · tire
## wear 0.023/0.027 · paint 0.045 · MY paint 0.046 (1 mm proud so a new dash
## crossing an old stop bar cannot z-fight) · manholes 0.052 · drains 0.055 ·
## light pools 0.075 · curb top 0.2 · curb paint 0.207 · MY bus zone 0.209.
## Visual-only: not one collider anywhere in this pass, and no shelter is
## placed inside the smoke corridor x[174,212] z[424,576].
const ROW_SEED := 160477             # M16 right-of-way pass ONLY — never _rng
const ROW_PAINT_Y := 0.046           # 1 mm over the frozen paint plane
const ROW_CURB_Y := SLAB_TOP + 0.009 # 2 mm over the M13 curb paint
const LANE_DIV := 7.0                # lane line: inner 3.5 travel / outer curb
const CORNER := POLE_OFF             # C4: was 12.6 — 0.4 m inside the roadway
                                     # on both axes. Every corner pole, its ped
                                     # heads, its push buttons and its name
                                     # blades rode that number, so all of them
                                     # were standing in the intersection.
const CORRIDOR_X := Vector2(174.0, 212.0)
const CORRIDOR_Z := Vector2(424.0, 576.0)
# Street names. Canon §4 has no name for any street inside this greybox grid
# (its named roads — Barry Vines Blvd, Juárez Blvd — are elsewhere in the
# metroplex), so the grid uses descriptive genericisms, which §4 explicitly
# permits. EW north->south, NS west->east. Open for World Builder ratification.
const EW_NAMES: Array[String] = ["E 1ST ST", "E 2ND ST", "HOWDY ST",
	"E 4TH ST", "E 5TH ST", "E 6TH ST"]
const NS_NAMES: Array[String] = ["N 1ST AVE", "N 2ND AVE", "N 3RD AVE",
	"N 4TH AVE", "N 5TH AVE", "N 6TH AVE", "N 7TH AVE"]
const BUS_ROUTES: Array[int] = [11, 23, 35, 47, 59, 71, 83]
const BLADE_GREEN := Color(0.05, 0.29, 0.14)
const BLADE_TEXT := Color(0.95, 0.97, 0.94)
const MART_BLUE := Color(0.07, 0.22, 0.44)
const MART_TEXT := Color(0.96, 0.97, 0.99)
const MART_TAGLINE := "NOW SERVING 40% FEWER CITIES"   # canon §4, verbatim
const AD_SHOPS: Array[int] = [0, 1, 2, 5, 7]  # SHOPS rows short enough to fit

var _row_white: Array[Transform3D] = []      # new lane/crosswalk/stop paint
var _row_red_curb: Array[Transform3D] = []   # bus zones
var _row_conc: Array[Transform3D] = []       # curb ramps
var _row_tactile: Array[Transform3D] = []    # ramp detectable-warning pads
var _row_steel: Array[Transform3D] = []      # poles, arms, shelter frames
var _row_dark: Array[Transform3D] = []       # signal + ped-signal housings
var _row_sig_r: Array[Transform3D] = []
var _row_sig_a: Array[Transform3D] = []
var _row_sig_g: Array[Transform3D] = []
var _row_walk: Array[Transform3D] = []       # ped WALK lenses
var _row_hand: Array[Transform3D] = []       # ped DON'T WALK lenses
var _row_lamp: Array[Transform3D] = []       # new cobra heads
var _row_blade: Array[Transform3D] = []      # green name blades
var _row_mart: Array[Transform3D] = []       # MART flag blades
var _row_roof: Array[Transform3D] = []       # shelter roof decks
var _row_panel: Array[Transform3D] = []      # shelter tinted-glass walls
var _row_wood: Array[Transform3D] = []       # shelter bench slats
var _row_glow: Array[Transform3D] = []       # shelter ceiling light strips
var _row_ad: Array[Transform3D] = []
var _row_ad_col: Array[Color] = []


func _right_of_way(city: Node3D) -> void:
	var r := RandomNumberGenerator.new()
	r.seed = ROW_SEED
	_row_lane_lines()
	_row_crosswalk_fill()
	_row_curb_ramps()
	_row_intersections()
	_row_street_lighting()
	_row_transit(r, _row_podiums(city))
	_row_driveway(city)
	_row_flush()


## The retail-podium footprints greybox_city recorded, used only as an
## obstruction map for transit siting. Read-only; no rng replay.
func _row_podiums(city: Node3D) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	if not city.has_method("get_podium_xforms"):
		return out
	var got: Variant = city.call("get_podium_xforms")
	if not (got is Array):
		return out
	for v: Variant in (got as Array):
		if v is Transform3D:
			out.append(v)
	return out


# ------------------------------ LANE LOGIC -----------------------------------
## Dashed white lane line at |7 m| on both grids, on the SAME 7 m dash rhythm
## as the frozen centre line so the paint reads as one system. Dashes stop
## clear of every intersection throat. C4: the throat grew from 17 m to
## DASH_GAP, because the stop bar moved from |13.6| to |18.0| and a lane line
## running past its own stop bar is the same defect as a centre line running
## through the box. The nearest dash now ends 1.25 m short of the bar.
func _row_lane_lines() -> void:
	for x in NS_X:
		var z := NS_Z_RANGE.x
		while z <= NS_Z_RANGE.y:
			if not _row_near(z, EW_Z, DASH_GAP):
				for s: float in [-1.0, 1.0]:
					_row_white.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.16, 0.02, 3.0)),
						Vector3(x + s * LANE_DIV, ROW_PAINT_Y, z)))
			z += DASH_STEP
	for z2 in EW_Z:
		var x2 := EW_X_RANGE.x
		while x2 <= EW_X_RANGE.y:
			if not _row_near(x2, NS_X, DASH_GAP):
				for s2: float in [-1.0, 1.0]:
					_row_white.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(3.0, 0.02, 0.16)),
						Vector3(x2, ROW_PAINT_Y, z2 + s2 * LANE_DIV)))
			x2 += DASH_STEP


func _row_near(v: float, list: Array, tol: float) -> bool:
	for e: Variant in list:
		if absf(v - float(e)) < tol:
			return true
	return false


## AUDIT FIX (M16): the M8 zebra spans only |6.45| of a 26 m street — a crosswalk
## that stops 6.5 m short of both curbs. The four missing outer bars per mouth
## are appended here at the same 3 m pitch, taking the crossing out to |12.45|
## (curb to curb, 0.55 m of gutter to spare). C4 moved the whole crossing out to
## XWALK_OFF with the M8 bands, so these ride the same constant and the nine
## bars of a mouth still land on one line.
func _row_crosswalk_fill() -> void:
	for cx in NS_X:
		for cz in EW_Z:
			for off: float in [-12.0, -9.0, 9.0, 12.0]:
				for s: float in [-1.0, 1.0]:
					_row_white.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(0.9, 0.02, 3.4)),
						Vector3(cx + off, ROW_PAINT_Y, cz + s * XWALK_OFF)))
					_row_white.append(Transform3D(
						Basis.IDENTITY.scaled(Vector3(3.4, 0.02, 0.9)),
						Vector3(cx + s * XWALK_OFF, ROW_PAINT_Y, cz + off)))


# --------------------------- CURB RAMPS --------------------------------------
## Two directional ramps per corner, eight per intersection: one on each of the
## corner's two curb faces, descending into the street that face fronts.
##
## SITING NOTE — M16 WROTE THIS AS AN APOLOGY; C4 RETIRES IT. The M16 note read:
## "the frozen M8 zebra bands sit at |10.4| — INSIDE the 26x26 intersection box
## — so a ramp built at a zebra END lands in open roadway... Moving the paint
## instead would mean relocating the frozen crosswalk AND stop-bar geometry
## together; that is reported, not done." It is done now. The crossing is at
## XWALK_OFF, on the corner slabs, and these ramps are RE-KEYED onto it: each
## sits at XWALK_OFF along its curb face, so its 3.4 m width and the crossing's
## 3.4 m width are the same band of ground. A ramp is no longer "roughly 1 m
## outboard of the zebra it serves" — it IS the end of the zebra it serves.
##
## The ramp top reaches curb height 10 cm inside the slab in plan, so it
## emerges from the curb face and never presents a face coplanar with the
## sidewalk (a flush landing would z-fight).
func _row_curb_ramps() -> void:
	for cx in NS_X:
		for cz in EW_Z:
			for sxf: float in [-1.0, 1.0]:
				for szf: float in [-1.0, 1.0]:
					# Curb face x = cx + sxf*13, fronting the avenue.
					_row_ramp(Vector3(cx + sxf * 11.4, -0.01, cz + szf * XWALK_OFF),
						Vector3(cx + sxf * 12.9, 0.205, cz + szf * XWALK_OFF))
					# Curb face z = cz + szf*13, fronting the cross street.
					_row_ramp(Vector3(cx + sxf * XWALK_OFF, -0.01, cz + szf * 11.4),
						Vector3(cx + sxf * XWALK_OFF, 0.205, cz + szf * 12.9))


func _row_ramp(bottom: Vector3, top: Vector3) -> void:
	var run := top - bottom
	var slope := run.normalized()
	var side := Vector3.UP.cross(slope).normalized()
	var normal := slope.cross(side).normalized()
	var rot := Basis(side, normal, slope)
	_row_conc.append(Transform3D(rot * Basis.from_scale(
		Vector3(3.4, 0.34, run.length())), (bottom + top) * 0.5 - normal * 0.17))
	# Detectable-warning pad at the street end of the ramp — the one detail that
	# makes a wedge read as a curb ramp instead of a lump of concrete.
	_row_tactile.append(Transform3D(rot * Basis.from_scale(Vector3(3.0, 0.02, 0.7)),
		bottom.lerp(top, 0.26) + normal * 0.011))


# --------------------------- INTERSECTIONS -----------------------------------
## Per intersection: the two MISSING east-west mast-arm signals on the two free
## corners, a luminaire arm on the northwest pole, pedestrian heads and push
## buttons on all four corner poles, and the name-blade pair on two diagonal
## corners. Geometry mirrors _signal/_light exactly so old and new hardware are
## indistinguishable. Phase: the M8 bake greens NS when (xi+zi) is even, so EW
## takes the complement — and where NS is red, one intersection in three shows
## EW amber instead of green (a cycle caught mid-change; the never-used amber
## MultiMesh finally has something in it).
func _row_intersections() -> void:
	for xi in NS_X.size():
		for zi in EW_Z.size():
			var cx: float = NS_X[xi]
			var cz: float = EW_Z[zi]
			var ns_green := (xi + zi) % 2 == 0
			var ew_amber := not ns_green and (xi + zi) % 3 == 0
			# NE corner serves eastbound, SW corner serves westbound. Both use
			# the M8 convention: head MAST_REACH out along `toward`, facing it,
			# so the driver travelling AGAINST `toward` reads it.
			_row_signal(Vector3(cx + CORNER, 0.0, cz - CORNER), Vector3(-1, 0, 0),
				ns_green, ew_amber)
			_row_signal(Vector3(cx - CORNER, 0.0, cz + CORNER), Vector3(1, 0, 0),
				ns_green, ew_amber)
			# Combination signal/luminaire pole: the NW mast gets a 2.3 m shaft
			# extension, an arm over the intersection and a cobra head. Every
			# downtown intersection was previously unlit.
			var nw := Vector3(cx - CORNER, 0.0, cz - CORNER)
			_row_steel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.2, 2.3, 0.2)),
				nw + Vector3(0, 7.55, 0)))
			var into := Vector3(0.7071, 0, 0.7071)
			var along := Basis.looking_at(into, Vector3.UP)
			# C4: the base moved 1.4 m out on BOTH axes (1.98 m along this
			# diagonal), so the arm grows 5.2 -> 7.2 and the reach 5.0 -> 6.98.
			# The luminaire hangs over the same square metre of intersection it
			# always did; only the mast under it left the roadway.
			_row_steel.append(Transform3D(along * Basis.from_scale(Vector3(0.2, 0.2, 7.2)),
				nw + Vector3(0, 8.45, 0) + into * 3.5))
			var head := nw + Vector3(0, 8.28, 0) + into * 6.98
			var head_xf := Transform3D(along * Basis.from_scale(Vector3(0.5, 0.22, 1.3)), head)
			_row_lamp.append(head_xf)
			_head_xf.append(head_xf)   # streetlight_glow pools follow the heads
			# Pedestrian hardware on all four corners. Head A serves the walk
			# ACROSS the avenue (lit when the avenue is red); head B serves the
			# walk across the street (lit when the avenue is green).
			for c: Vector2 in [Vector2(CORNER, -CORNER), Vector2(CORNER, CORNER),
					Vector2(-CORNER, CORNER), Vector2(-CORNER, -CORNER)]:
				var p := Vector3(cx + c.x, 0.0, cz + c.y)
				_row_ped(p, Vector3(-signf(c.x), 0, 0), not ns_green)
				_row_ped(p, Vector3(0, 0, -signf(c.y)), ns_green)
			# Name blades: northeast reads the southbound and westbound
			# approaches, southwest reads the northbound and eastbound ones.
			_row_blades(Vector3(cx + CORNER, 0.0, cz - CORNER), -1.0, 1.0,
				EW_NAMES[zi], NS_NAMES[xi])
			_row_blades(Vector3(cx - CORNER, 0.0, cz + CORNER), 1.0, -1.0,
				EW_NAMES[zi], NS_NAMES[xi])


## One mast-arm signal, geometry-identical to the frozen _signal(): pole, arm
## along `toward`, three-lens head MAST_REACH out. Only the live lens is drawn.
func _row_signal(base: Vector3, toward: Vector3, ns_green: bool, amber: bool) -> void:
	var along := Basis.looking_at(toward, Vector3.UP)
	_row_steel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.24, 6.4, 0.24)),
		base + Vector3(0, 3.2, 0)))
	_row_steel.append(Transform3D(along * Basis.from_scale(Vector3(0.18, 0.18, MAST_ARM)),
		base + Vector3(0, 6.25, 0) + toward * (MAST_ARM * 0.5 - 0.1)))
	var head_pos := base + Vector3(0, 5.55, 0) + toward * MAST_REACH
	_row_dark.append(Transform3D(along * Basis.from_scale(Vector3(0.34, 1.0, 0.3)),
		head_pos))
	var lens_i := 0 if ns_green else (1 if amber else 2)
	var lens := Transform3D(along * Basis.from_scale(Vector3(0.2, 0.2, 0.08)),
		head_pos + Vector3(0, 0.33 - 0.33 * float(lens_i), 0) + toward * 0.17)
	if lens_i == 0:
		_row_sig_r.append(lens)
	elif lens_i == 1:
		_row_sig_a.append(lens)
	else:
		_row_sig_g.append(lens)


## Pedestrian head + push button on a corner pole, facing `d` (the crosswalk it
## serves). `walk` picks the lit symbol; a ped head shows exactly one at a time.
func _row_ped(pole: Vector3, d: Vector3, walk: bool) -> void:
	var rot := Basis(Vector3.UP, atan2(d.x, d.z))
	_row_dark.append(Transform3D(rot * Basis.from_scale(Vector3(0.38, 0.46, 0.24)),
		pole + Vector3(0, 2.95, 0) + d * 0.2))
	var lens := Transform3D(rot * Basis.from_scale(Vector3(0.26, 0.3, 0.05)),
		pole + Vector3(0, 2.95, 0) + d * 0.33)
	if walk:
		_row_walk.append(lens)
	else:
		_row_hand.append(lens)
	_row_dark.append(Transform3D(rot * Basis.from_scale(Vector3(0.16, 0.26, 0.12)),
		pole + Vector3(0, 1.15, 0) + d * 0.16))


## A blade pair on one corner pole: the east-west name up top facing `zface`,
## the north-south name below facing `xface`. Each blade is mounted PARALLEL to
## the street it names, which is what makes a blade legible from a moving car.
func _row_blades(pole: Vector3, zface: float, xface: float, ew_name: String,
		ns_name: String) -> void:
	_row_blade.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.6, 0.46, 0.07)),
		pole + Vector3(0, 4.78, 0)))
	_row_text(ew_name, pole + Vector3(0, 4.78, zface * 0.06),
		0.0 if zface > 0.0 else PI, 44, BLADE_TEXT, 2.42, SIGN.BLADE, 0.38)
	_row_blade.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.07, 0.46, 2.6)),
		pole + Vector3(0, 4.28, 0)))
	_row_text(ns_name, pole + Vector3(xface * 0.06, 4.28, 0),
		PI * 0.5 * xface, 44, BLADE_TEXT, 2.42, SIGN.BLADE, 0.38)


# --------------------------- STREET LIGHTING ---------------------------------
## AUDIT FIX (the biggest one in this pass): _streetlights() lights the seven
## north-south streets and the frontage roads and NOTHING ELSE — all six
## east-west streets ran pitch black. They are lit here on a block-locked
## schedule (two heads per block face at +-21.5 m from each block centre, so a
## head can never land in an intersection throat) alternating sides for a 43 m
## staggered rhythm, which is what the NS streets already read as at 46 m.
## The frontage roads' 69 m single-sided spacing is halved to 34.5 m.
func _row_street_lighting() -> void:
	# NORTH-SOUTH INFILL. _streetlights() steps 46 m but ALTERNATES kerbs, so
	# each kerb line only sees a head every 92 m and the pools read as isolated
	# puddles with 75 m of black between them. Every existing head gets its mate
	# across the street (the exact complement of the frozen flip sequence),
	# turning a 92 m staggered layout into a 46 m opposite layout — TxDOT urban
	# arterial spacing, and both halves of the roadway finally get pools.
	for x in NS_X:
		var nz := NS_Z_RANGE.x + 18.0
		var flip := false
		while nz <= NS_Z_RANGE.y - 10.0:
			var s := 1.0 if flip else -1.0
			_row_light(_c4_site(x + s * POLE_OFF, nz, false), Vector3(-s, 0, 0))
			flip = not flip
			nz += LIGHT_STEP
	var i := 0
	for cz in EW_Z:
		for col in GRID_COLS:
			var bx := BLOCK_ORIGIN.x + BLOCK_PITCH * float(col)
			for d: float in [-21.5, 21.5]:
				var side := -1.0 if i % 2 == 0 else 1.0
				_row_light(_c4_site(bx + d, cz + side * POLE_OFF, true),
					Vector3(0, 0, -side))
				i += 1
	for side2: float in [-1.0, 1.0]:
		var fx := -FRONTAGE_X + 20.0 + LIGHT_STEP * 0.75
		while fx <= FRONTAGE_X:
			_row_light(Vector3(fx, 0.0, side2 * (FRONTAGE_Z + 6.6)),
				Vector3(0, 0, -side2), FRONT_ARM, FRONT_REACH)
			fx += LIGHT_STEP * 1.5


## Geometry-identical to the frozen _light(): 7.6 m shaft, arm over the lane,
## warm emissive head. The head is registered with the streetlight_glow
## contract so its light pool appears at night with no further wiring.
func _row_light(base: Vector3, toward: Vector3, arm: float = LIGHT_ARM,
		reach: float = LIGHT_REACH) -> void:
	var along := Basis.looking_at(toward, Vector3.UP)
	_row_steel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.28, 7.6, 0.28)),
		base + Vector3(0, 3.8, 0)))
	_row_steel.append(Transform3D(along * Basis.from_scale(Vector3(0.22, 0.22, arm)),
		base + Vector3(0, 7.45, 0) + toward * (arm * 0.5 - 0.1)))
	var head := Transform3D(along * Basis.from_scale(Vector3(0.5, 0.22, 1.3)),
		base + Vector3(0, 7.28, 0) + toward * reach)
	_row_lamp.append(head)
	_head_xf.append(head)
	_c4_poles.append(Vector2(base.x, base.z))


# --------------------------- TRANSIT (MART) ----------------------------------
## The chosen quality feature. A city with signals, blades and lit streets but
## no transit is a movie set; MART (canon §4, "Now Serving 40% Fewer Cities")
## is the cheapest object that implies a whole system the player can't use yet.
## Two stops per avenue, sited on the FAR side of an intersection where a bus
## actually stops, with a red curb zone that reads as enforcement. Nothing is
## placed inside the smoke corridor — that box stays a driving surface.
## SITING (screenshot-caught): a tower's footprint carries +-3 m of jitter and
## its retail podium grows 0.75 m past that, so a fixed sidewalk offset buries
## some shelters inside a building. Placement is therefore data-driven — the
## shelter box is tested against the podium footprints greybox_city recorded and
## walks down a list of candidate distances past the intersection until it finds
## clear sidewalk (far side first, then mid-block). A stop with nowhere legal to
## stand is dropped rather than shipped inside a wall.
func _row_transit(r: RandomNumberGenerator, podiums: Array[Transform3D]) -> void:
	for xi in NS_X.size():
		var nsx: float = NS_X[xi]
		for zi: int in [1, 4]:
			var cz: float = float(EW_Z[zi])
			var side := 1.0 if (xi + zi) % 2 == 0 else -1.0
			var sx := nsx + side * 14.1
			var ad: Array = SHOPS[AD_SHOPS[r.randi_range(0, AD_SHOPS.size() - 1)]]
			for dz: float in [22.0, 43.0, 30.0, 56.0, 64.0]:
				var sz := cz + dz
				if _row_corridor(sx, sz) or _row_blocked(podiums, sx, sz):
					continue
				_row_shelter(sx, sz, side, nsx, BUS_ROUTES[xi], ad)
				break


func _row_corridor(x: float, z: float) -> bool:
	return x > CORRIDOR_X.x - 4.0 and x < CORRIDOR_X.y + 4.0 \
		and z > CORRIDOR_Z.x - 4.0 and z < CORRIDOR_Z.y + 4.0


## Plan-space overlap between the shelter footprint (plus the flag post's reach
## up the sidewalk) and any recorded retail podium, with a 0.6 m breathing gap.
## C4 adds the second obstruction that now exists: the cobra streetlights moved
## onto the sidewalk at |14.0| and a MART shelter spans |13.3|..|14.9|, so a
## shelter sited on a lamp post would swallow it. The shelter walks to its next
## candidate distance instead. No rng draw is added or removed — `r` is rolled
## once per stop before this loop and is untouched by which candidate wins.
func _row_blocked(podiums: Array[Transform3D], sx: float, sz: float) -> bool:
	for p in podiums:
		if absf(p.origin.x - sx) < absf(p.basis.x.x) * 0.5 + 1.6 \
				and absf(p.origin.z - sz) < absf(p.basis.z.z) * 0.5 + 4.2:
			return true
	for q in _c4_poles:
		if absf(q.x - sx) < 1.3 and absf(q.y - sz) < 2.6:
			return true
	return false


func _row_shelter(sx: float, sz: float, side: float, nsx: float, route: int,
		ad: Array) -> void:
	var top := SLAB_TOP
	var inward := -side                      # toward the street (open face)
	for px: float in [-0.8, 0.8]:            # four frame posts
		for pz: float in [-1.7, 1.7]:
			_row_steel.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.1, 2.5, 0.1)),
				Vector3(sx + px, top + 1.25, sz + pz)))
	_row_roof.append(Transform3D(Basis.IDENTITY.scaled(Vector3(2.1, 0.14, 4.1)),
		Vector3(sx, top + 2.57, sz)))                          # roof
	_row_panel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.08, 1.95, 3.6)),
		Vector3(sx + side * 0.8, top + 1.2, sz)))              # back wall
	_row_panel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.6, 1.95, 0.08)),
		Vector3(sx, top + 1.2, sz + 1.76)))                    # closed end
	_row_glow.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.6, 0.06, 3.2)),
		Vector3(sx, top + 2.44, sz)))                          # ceiling strip
	_row_wood.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.5, 0.09, 2.9)),
		Vector3(sx + side * 0.5, top + 0.52, sz)))             # bench slat
	for lz: float in [-1.25, 1.25]:
		_row_steel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.44, 0.44, 0.1)),
			Vector3(sx + side * 0.5, top + 0.26, sz + lz)))
	# Backlit ad panel forms the other end wall — canon brand, canon satire.
	_row_ad.append(Transform3D(Basis.IDENTITY.scaled(Vector3(1.52, 1.85, 0.1)),
		Vector3(sx, top + 1.15, sz - 1.76)))
	_row_ad_col.append((ad[1] as Color).srgb_to_linear())
	_row_text(str(ad[0]), Vector3(sx, top + 1.15, sz - 1.83), PI, 30,
		ad[2] as Color, 1.40, SIGN.FASCIA, 0.55)
	_row_text(MART_TAGLINE, Vector3(sx + side * 0.75, top + 1.62, sz),
		PI * 0.5 * inward, 20, Color(0.72, 0.75, 0.78), 3.2, SIGN.STENCIL, 0.30)
	# Flag blade at the curb, faces up and down the avenue.
	var fx := nsx + side * 13.35
	var fz := sz + 2.9
	_row_steel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.1, 3.4, 0.1)),
		Vector3(fx, top + 1.7, fz)))
	_row_mart.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.98, 0.64, 0.07)),
		Vector3(fx, top + 3.25, fz)))
	for f: float in [-1.0, 1.0]:
		_row_text("MART", Vector3(fx, top + 3.37, fz + f * 0.05),
			0.0 if f > 0.0 else PI, 28, MART_TEXT, 0.85, SIGN.FASCIA, 0.28)
		_row_text("ROUTE %d" % route, Vector3(fx, top + 3.11, fz + f * 0.05),
			0.0 if f > 0.0 else PI, 17, Color(0.82, 0.88, 0.95), 0.82,
			SIGN.FLAT, 0.20)
	# Red bus zone at the curb, clear of the M13 corner curb paint (ends 19.25).
	_row_red_curb.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.22, 0.015, 8.0)),
		Vector3(nsx + side * 12.89, ROW_CURB_Y, sz + 1.5)))


# --------------------------- MINOR APPROACH ----------------------------------
## The one uncontrolled minor approach in the map: County General's driveway,
## which meets the downtown street bed with no stop line, no centre line and no
## crosswalk — and it is where the player walks out after every death. Painted
## in approach order for a car leaving the campus: stop bar, then the crossing.
func _row_driveway(city: Node3D) -> void:
	if not city.has_method("get_hospital_spawn"):
		return
	var x := 365.0
	var y := 0.048                       # driveway slab top is 0.02
	_row_white.append(Transform3D(Basis.IDENTITY.scaled(Vector3(11.0, 0.02, 0.5)),
		Vector3(x, y, 572.5)))
	for off: float in [-4.0, -2.0, 0.0, 2.0, 4.0]:
		_row_white.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.8, 0.02, 2.4)),
			Vector3(x + off, y, 569.2)))
	for dz: float in [577.0, 583.5, 590.0]:
		_row_white.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.2, 0.02, 2.5)),
			Vector3(x, y, dz)))


# --------------------------- HELPERS -----------------------------------------
## Right-of-way lettering (blades, transit flags, shelter ads), with an
## explicit yaw: Label3D faces +Z at yaw 0. M22: exact fit via SIGN, and the
## outline is now a RATIO of the size — at 12 px flat, a 17 pt route number
## carried an outline as thick as its own stroke and read as a black smudge.
func _row_text(text: String, pos: Vector3, yaw: float, fsize: int, col: Color,
		max_w: float, style: int = SIGN.BLADE, max_h: float = 0.0) -> void:
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	lbl.rotation.y = yaw
	add_child(lbl)


func _row_emissive(col: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.7
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	return m


func _row_flush() -> void:
	# 2,095 crosswalk/stopbar quads and 13 red bus-zone strips: paint again.
	# A curb ramp is a 0.34 m concrete wedge lying IN the sidewalk slope and the
	# tactile pad is a 20 mm sticker on top of it — both are ground, not volume.
	_mmi(_row_white, Color(0.88, 0.88, 0.86), "RowPaint", true, false)
	_mmi(_row_red_curb, Color(0.62, 0.16, 0.12), "RowBusZones", true, false)
	_mmi(_row_conc, Color(0.66, 0.65, 0.62), "CurbRamps", false, false)
	_mmi(_row_tactile, Color(0.74, 0.62, 0.20), "CurbRampPads", false, false)
	_mmi(_row_steel, Color(0.22, 0.23, 0.25), "RowPoles", false, true)
	_mmi(_row_dark, Color(0.12, 0.13, 0.14), "RowSignalHousings", false, true)
	_mmi(_row_sig_r, Color(1.0, 0.15, 0.1), "RowSignalRed", false, false, true)
	_mmi(_row_sig_a, Color(1.0, 0.65, 0.1), "RowSignalAmber", false, false, true)
	_mmi(_row_sig_g, Color(0.2, 1.0, 0.35), "RowSignalGreen", false, false, true)
	_mmi(_row_lamp, Color(1.0, 0.82, 0.45), "RowLightHeads", false, false, true)
	_mmi_build(_row_walk, [], _row_emissive(Color(0.88, 0.95, 0.9), 1.2),
		"PedWalk", false)
	_mmi_build(_row_hand, [], _row_emissive(Color(0.95, 0.42, 0.1), 1.2),
		"PedHand", false)
	# Blades and transit flags carry a low emission: sheeting is retroreflective,
	# and 0.35 keeps them legible at night while staying under the bloom gate.
	# 70 mm plates hung off a mast whose own shadow already draws the pole —
	# the plate adds a hairline and a cascade draw, so it is shadow-free.
	_mmi_build(_row_blade, [], _row_emissive(BLADE_GREEN, 0.35),
		"StreetBlades", false)
	_mmi_build(_row_mart, [], _row_emissive(MART_BLUE, 0.35), "MartFlags", false)
	# Pale roof deck over dark tinted glazing: the value split is what makes a
	# shelter read as a shelter from behind instead of a gray box. The shelter
	# is a real box a player walks into, so roof, glazing and bench all cast;
	# the ad plate is flush on a casting panel and the strip light is emissive.
	_mmi(_row_roof, Color(0.68, 0.70, 0.72), "ShelterRoofs", false, true)
	_mmi(_row_panel, Color(0.26, 0.31, 0.35), "ShelterGlass", false, true)
	_mmi(_row_wood, Color(0.44, 0.31, 0.17), "ShelterBenches", false, true)
	_mmi_build(_row_glow, [], _row_emissive(Color(1.0, 0.93, 0.78), 0.9),
		"ShelterLights", false)
	_mmi_colored(_row_ad, _row_ad_col, "ShelterAds", false)


# ========================== SIGNAL CYCLE (M18) ===============================
## MAKING THE LIGHTS ACTUALLY CHANGE.
##
## M8 and M16 each baked ONE lit lens per head and left the other two sockets
## empty, so the phase was frozen into the MultiMesh transforms at build time —
## 168 vehicle heads and 336 pedestrian heads that could never change (D-021).
## This pass rebuilds the glass as an animatable set and hands it to the M18
## runtime system, which drives it from scripts/systems/signal_cycle.gd.
##
## THE APPROACH, AND WHY IT IS THE CHEAP ONE. Three lens MultiMeshes are kept
## (red / amber / green), each carrying ONE instance per head, and the unlit
## ones are collapsed to a zero-scale basis AT THEIR OWN LENS ORIGIN —
## degenerate triangles the rasteriser drops, and an AABB that never grows, so
## culling is unchanged. The alternative, one MultiMesh recoloured per
## instance, was rejected for a concrete reason: these lenses read at night
## because their material is EMISSIVE, and emission is a material property with
## no per-instance channel in StandardMaterial3D. Per-instance colour would
## have meant either a custom shader or unshaded albedo, and unshaded albedo
## cannot cross the 1.05 HDR glow threshold main.gd sets — the signals would
## have stopped blooming, which is most of what sells them after dark.
##
## And the per-frame cost is ZERO, not merely small: every one of the forty
## 1-second SLOTS of the cycle has its full MultiMesh buffer PRECOMPUTED here
## at build time, so a slot change is five PackedFloat32Array assignments
## (~55 KB), once a second. Nothing walks 1176 instances at runtime, ever.
##
## M20 (defect D-010): the index used to be the six-stage global stage, which
## could only ever express the `(xi+zi)%2` half-cycle checkerboard — an
## anti-strobe, not a green wave. The GREEN WAVE's progression offset is 7 s
## per block and the stages are 15/3/2 s, so no stage shift can carry it; the
## index is a 1-second slot instead. It stays EXACT rather than quantised
## because every stage boundary and every offset is a whole second — the proof
## is in signal_cycle.gd. Cost: 2.3 MB of baked buffer instead of 338 KB.
##
## SHIPS HIDDEN. This pass only builds; `set_signal_cycle_active(true)` from
## the runtime system is what swaps the static M8/M16 lenses out for these. If
## signal_cycle.gd is absent the game is the M17 diorama, byte for byte.
##
## GEOMETRY: every transform below is the SAME literal the frozen `_signal`,
## `_row_signal` and `_row_ped` use — head 6.2 m out along the mast arm at
## y 5.55, lenses at +0.33 / 0 / -0.33 and 0.17 m proud of the housing face;
## ped lens 2.95 m up the corner pole, 0.33 m proud. Nothing moves; only which
## one is lit. Visual-only, no collision, and not one RNG draw in this section.
const SIGNAL_CYCLE := preload("res://scripts/systems/signal_cycle.gd")
const CYC_LENS := Vector3(0.2, 0.2, 0.08)      # vehicle lens box (M8 _signal)
const CYC_PED_LENS := Vector3(0.26, 0.3, 0.05) # ped lens box (M16 _row_ped)
const CYC_HEAD_Y := 5.55                       # mast-arm head centre height
const CYC_HEAD_OUT := MAST_REACH               # head distance along the arm
const CYC_LENS_PROUD := 0.17                   # lens face proud of the housing
const CYC_LENS_PITCH := 0.33                   # red / amber / green stacking
const CYC_PED_Y := 2.95
const CYC_PED_PROUD := 0.33
# The static lenses this pass replaces. "SignalAmber" never existed — the M8
# bake had no amber to draw — and get_node_or_null simply returns null for it.
const CYC_STATIC: Array[String] = ["SignalRed", "SignalAmber", "SignalGreen",
	"RowSignalRed", "RowSignalAmber", "RowSignalGreen", "PedWalk", "PedHand"]

# BUILD ORDER IS A CONTRACT (the M18 probe indexes on it and so does anything
# that ever wants to address one head): heads run xi-major, then zi, then the
# four heads of that intersection in the order NS-north, NS-south, EW-east,
# EW-west — head index = ((xi * EW_Z.size() + zi) * 4) + k. Ped heads run the
# same intersection order, then the four corners NE/SE/SW/NW, then the two
# heads on that corner: avenue-crossing first, street-crossing second.
var _cyc_red: Array[Transform3D] = []
var _cyc_amb: Array[Transform3D] = []
var _cyc_grn: Array[Transform3D] = []
var _cyc_ns: Array[bool] = []                  # head serves a N-S approach
var _cyc_isect: Array[int] = []                # xi * EW_Z.size() + zi
var _cyc_ped: Array[Transform3D] = []
var _cyc_ped_ns: Array[bool] = []              # walks parallel to N-S traffic
var _cyc_ped_isect: Array[int] = []
var _cyc_table: Array[PackedInt32Array] = []   # [slot][intersection] -> stage
var _cyc_groups: Array = []                    # runtime contract (see getter)
var _cyc_mmis: Array[MultiMeshInstance3D] = []


func _signal_cycle_pass() -> void:
	for xi in NS_X.size():
		for zi in EW_Z.size():
			var cx: float = NS_X[xi]
			var cz: float = EW_Z[zi]
			var ii := xi * EW_Z.size() + zi
			# The two frozen M8 masts, both serving the north-south approaches.
			_cyc_head(Vector3(cx + CORNER, 0.0, cz + CORNER), Vector3(0, 0, -1), true, ii)
			_cyc_head(Vector3(cx - CORNER, 0.0, cz - CORNER), Vector3(0, 0, 1), true, ii)
			# The two M16 masts on the free corners, serving east-west.
			_cyc_head(Vector3(cx + CORNER, 0.0, cz - CORNER), Vector3(-1, 0, 0), false, ii)
			_cyc_head(Vector3(cx - CORNER, 0.0, cz + CORNER), Vector3(1, 0, 0), false, ii)
			for c: Vector2 in [Vector2(CORNER, -CORNER), Vector2(CORNER, CORNER),
					Vector2(-CORNER, CORNER), Vector2(-CORNER, -CORNER)]:
				var p := Vector3(cx + c.x, 0.0, cz + c.y)
				# Facing +-X: the crossing OF the avenue, walked alongside the
				# east-west movement. Facing +-Z: across the street, alongside
				# north-south. Same pairing the M16 heads were baked with.
				_cyc_pedhead(p, Vector3(-signf(c.x), 0, 0), false, ii)
				_cyc_pedhead(p, Vector3(0, 0, -signf(c.y)), true, ii)
	_cyc_build_table()
	var red := _cyc_mm(_cyc_red.size(), Color(1.0, 0.15, 0.1), 1.6, "CycleSignalRed")
	var amb := _cyc_mm(_cyc_amb.size(), Color(1.0, 0.65, 0.1), 1.6, "CycleSignalAmber")
	var grn := _cyc_mm(_cyc_grn.size(), Color(0.2, 1.0, 0.35), 1.6, "CycleSignalGreen")
	var wlk := _cyc_mm(_cyc_ped.size(), Color(0.88, 0.95, 0.9), 1.2, "CycleWalk")
	var hnd := _cyc_mm(_cyc_ped.size(), Color(0.95, 0.42, 0.1), 1.2, "CycleHand")
	_cyc_groups = [
		_cyc_bake(red, _cyc_red, 0), _cyc_bake(amb, _cyc_amb, 1),
		_cyc_bake(grn, _cyc_grn, 2), _cyc_bake(wlk, _cyc_ped, 3),
		_cyc_bake(hnd, _cyc_ped, 4)]


## One three-lens vehicle head, mirroring the frozen `_signal` / `_row_signal`.
func _cyc_head(base: Vector3, toward: Vector3, is_ns: bool, ii: int) -> void:
	var along := Basis.looking_at(toward, Vector3.UP)
	var b := along * Basis.from_scale(CYC_LENS)
	var face := base + Vector3(0, CYC_HEAD_Y, 0) + toward * CYC_HEAD_OUT \
		+ toward * CYC_LENS_PROUD
	_cyc_red.append(Transform3D(b, face + Vector3(0, CYC_LENS_PITCH, 0)))
	_cyc_amb.append(Transform3D(b, face))
	_cyc_grn.append(Transform3D(b, face - Vector3(0, CYC_LENS_PITCH, 0)))
	_cyc_ns.append(is_ns)
	_cyc_isect.append(ii)


## One pedestrian head, mirroring the frozen `_row_ped` lens exactly. WALK and
## DON'T WALK share the socket, so both MultiMeshes carry the same transform
## and exactly one of them is ever un-collapsed.
func _cyc_pedhead(pole: Vector3, d: Vector3, walks_with_ns: bool, ii: int) -> void:
	var rot := Basis(Vector3.UP, atan2(d.x, d.z))
	_cyc_ped.append(Transform3D(rot * Basis.from_scale(CYC_PED_LENS),
		pole + Vector3(0, CYC_PED_Y, 0) + d * CYC_PED_PROUD))
	_cyc_ped_ns.append(walks_with_ns)
	_cyc_ped_isect.append(ii)


## THE GREEN WAVE, resolved once (defect D-010). `[slot][intersection]` -> the
## local stage that intersection holds for the whole of that 1-second slot.
## 40 x 42 integers, computed from signal_cycle's own progression offset, so
## the glass and traffic.gd's shells are reading one function and one clock.
## Building the table here instead of calling into the schedule 564,480 times
## from the bake loop is the difference between a boot cost worth measuring and
## one that is not.
func _cyc_build_table() -> void:
	var n_i := NS_X.size() * EW_Z.size()
	var slots := int(SIGNAL_CYCLE.SLOTS)
	_cyc_table.resize(slots)
	for s in slots:
		var row := PackedInt32Array()
		row.resize(n_i)
		for xi in NS_X.size():
			for zi in EW_Z.size():
				row[xi * EW_Z.size() + zi] = int(SIGNAL_CYCLE.stage_in_slot(
					s, xi, zi, SIGNAL_CYCLE.HALF))
		_cyc_table[s] = row


## An emissive lens MultiMesh, materially identical to the static one it
## replaces (same albedo, same emission, same 1.6 / 1.2 energies), built hidden.
func _cyc_mm(count: int, col: Color, energy: float, label: String) -> MultiMesh:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _unit_mesh
	mm.instance_count = count
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = m
	# Signal glass never casts. Two reasons, either sufficient: the lens is a
	# 0.2 m emissive disc inside a housing that already casts, and the unlit
	# lenses are collapsed to a ZERO-SCALE basis, so a caster would push 1,176
	# degenerate instances through every cascade to draw nothing at all.
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.visible = false
	add_child(mmi)
	_cyc_mmis.append(mmi)
	return mm


## Precompute this MultiMesh's buffer for all forty 1-second slots. `role`
## picks what "lit" means: 0/1/2 = the red/amber/green lens of a vehicle head,
## 3 = ped WALK, 4 = ped DON'T WALK.
##
## The lit test is inlined against `_cyc_table` rather than calling back into
## the schedule: the three vehicle roles partition every head (exactly one lens
## is lit at all times, which is what a real signal head does) and the two ped
## roles partition every ped socket, so each is two integer compares on the
## local stage. NS greens on stage 0 and ambers on 1; EW on 3 and 4.
##
## The floats are packed by hand rather than round-tripped through
## set_instance_transform + MultiMesh.buffer, because MEASURED: under the
## headless dummy renderer the engine stores no instance data at all — the
## getter returns an empty array and get_instance_transform returns identity —
## so a round trip builds a zero-length buffer and every CI boot throws. The
## layout is the engine's TRANSFORM_3D packing, twelve floats as three rows of
## four: (basis row i, origin component i).
func _cyc_bake(mm: MultiMesh, xf: Array[Transform3D], role: int) -> Dictionary:
	var stages: Array = []
	var zero := Basis.from_scale(Vector3.ZERO)
	var ped := role >= 3
	var isect: Array[int] = _cyc_ped_isect if ped else _cyc_isect
	var ns: Array[bool] = _cyc_ped_ns if ped else _cyc_ns
	var n := xf.size()
	for s in _cyc_table.size():
		var row: PackedInt32Array = _cyc_table[s]
		var buf := PackedFloat32Array()
		buf.resize(n * 12)
		for i in n:
			var l := row[isect[i]]
			var is_ns: bool = ns[i]
			var lit := false
			if ped:
				var walk := l == (0 if is_ns else 3)
				lit = walk if role == 3 else not walk
			elif role == 2:                              # green
				lit = (l == 0) if is_ns else (l == 3)
			elif role == 1:                              # amber
				lit = (l == 1) if is_ns else (l == 4)
			else:                                        # red = everything else
				lit = (l > 1) if is_ns else (l < 3 or l == 5)
			var t := xf[i]
			# Unlit lenses collapse IN PLACE: degenerate triangles the
			# rasteriser drops, at an origin already inside the AABB.
			var b := t.basis if lit else zero
			var o := t.origin
			var k := i * 12
			buf[k] = b.x.x;     buf[k + 1] = b.y.x;  buf[k + 2] = b.z.x
			buf[k + 3] = o.x
			buf[k + 4] = b.x.y; buf[k + 5] = b.y.y;  buf[k + 6] = b.z.y
			buf[k + 7] = o.y
			buf[k + 8] = b.x.z; buf[k + 9] = b.y.z;  buf[k + 10] = b.z.z
			buf[k + 11] = o.z
		stages.append(buf)
	mm.buffer = stages[0]
	return {"mm": mm, "stages": stages}


## Contract for signal_cycle.gd: one entry per animated MultiMesh, each with
## its forty precomputed 1-second slot buffers, indexed by
## `signal_cycle.slot(now())`. Read-only record; no rng replay.
func get_signal_cycle_groups() -> Array:
	return _cyc_groups.duplicate()


## Hand the glass over to the runtime cycle (or take it back). Flipping this is
## the ONLY thing that changes what the player sees; the static M8/M16 lenses
## survive untouched underneath so the diorama is always one call away.
func set_signal_cycle_active(on: bool) -> void:
	for n: String in CYC_STATIC:
		var m := get_node_or_null(n)
		if m is Node3D:
			(m as Node3D).visible = not on
	for mmi in _cyc_mmis:
		if is_instance_valid(mmi):
			mmi.visible = on


# =============== STONEBRIDLE RANCH — THE LANE PASS (M20) =====================
## DEFECT D-011, the right-of-way half. greybox_city publishes the plat (pod
## centrelines, lane offsets, connector rows); this pass paints it. Appended
## whole under the house law: ZERO rng draws of ANY kind — every number here is
## either a literal or comes from the plat greybox_city publishes — and every
## element ships in a NEW MultiMesh because _flush() ran a long time ago.
##
## WHAT A SUBDIVISION STREET IS, and what it is not. These are 9 m RURAL-SECTION
## local streets: pavement, a shoulder, and nothing else. No curbs, no curb
## ramps, no gutter, no edge lines and — deliberately — NO CENTRE LINE. A 9 m
## local street is not striped in Texas or anywhere else, and painting one here
## to look busy would be the exact opposite of the job. The 11 m COLLECTORS
## (the three east-west Ranch Roads) do get a centre line, because a collector
## carries two-way traffic between subdivisions and is striped for it.
##
## Control is stop-on-the-minor: every lane approach to a Ranch Road gets a stop
## bar set back 7 m from the collector edge and a stop sign on its right-hand
## shoulder, and the street-name blades ride that same post — which is where a
## subdivision actually hangs its blades, and saves 39 poles.
##
## NIGHT. The suburb's night read was porch lights and lit windows and nothing
## between them. Cobra heads every 112 m alternating shoulders give the plat a
## rhythm at the spacing a subdivision actually gets (a downtown arterial is 46
## m; a residential street is not). Every head is registered with the
## streetlight_glow contract, so the warm pools follow with no further wiring.
##
## HEIGHT STRATUM (the z-fighting law — every crossing surface gets its own
## plane): prairie top -0.020 · lane top 0.020 · suburb_dressing dirt apron
## 0.023 · connector top 0.030 · court stub 0.034 · court bulb 0.038 ·
## suburb_dressing driveway 0.040 · my paint 0.045.
##
## VISUAL-ONLY: not one collider in this pass. The plat is 250 m clear of the
## smoke corridor on every axis and nothing here is placed by chance.
const SUB_PAVE_Y := -0.010           # 60 mm slab, top at 0.020
const SUB_COLL_Y := 0.000            # collector top 0.030
const SUB_STUB_Y := 0.004            # court stub top 0.034
const SUB_BULB_Y := 0.008            # court bulb top 0.038
const SUB_PAINT_Y := 0.045
const SUB_LANE_HALF := 4.5
const SUB_COLL_HALF := 5.5
const SUB_TRUNK_CLEAR := 1.0         # trunk margin outside the pavement edge
const SUB_LIGHT_STEP := 112.0        # residential luminaire spacing
const SUB_STOP_SET := 2.5            # stop bar setback from the collector edge:
                                     # 1 m clear of the collector's own shoulder
                                     # and no further, so the bar reads as part
                                     # of the intersection instead of a stray
                                     # stripe seven metres up the block
# The pavement uses the CITY's asphalt material, not a flat colour of its own:
# a subdivision street is the same product as a downtown street and a flat
# 0.105 grey read as a hole beside downtown's aggregate-flecked triplanar
# (screenshot-caught at the lane vantage).
const SUB_TEX := preload("res://scripts/world/city_textures.gd")
const SUB_SHD := preload("res://scripts/world/city_shaders.gd")
const SUB_SHOULDER_W := 1.6          # caliche shoulder each side of the lane
const SUB_SHOULDER := Color(0.56, 0.51, 0.41)
const SUB_STONE := Color(0.52, 0.48, 0.42)
const SUB_ROAD_NAMES: Array[String] = ["RANCH RD 1", "RANCH RD 2", "RANCH RD 3"]
const STOP_RED := Color(0.62, 0.10, 0.09)

# Suburb yard trees, recorded by _trees(): {pos, trunk, can, n}.
var _sub_trees: Array = []
var _sub_pave: Array[Transform3D] = []       # lane + collector + stub asphalt
var _sub_shoulder: Array[Transform3D] = []   # caliche edge strips
var _sub_stone: Array[Transform3D] = []      # entry monument plinth
var _sub_paint: Array[Transform3D] = []      # collector dashes, stop bars
var _sub_steel: Array[Transform3D] = []      # luminaire + sign posts and arms
var _sub_lamp: Array[Transform3D] = []       # cobra heads
var _sub_stop: Array[Transform3D] = []       # stop-sign panels
var _sub_blade: Array[Transform3D] = []      # street-name blades


func _suburb_lanes_pass(city: Node3D) -> void:
	if not (city.has_method("get_suburb_lane_x")
			and city.has_method("get_suburb_connector_z")
			and city.has_method("get_suburb_pod_x")):
		return
	var lanes: PackedFloat32Array = city.call("get_suburb_lane_x")
	var conns: PackedFloat32Array = city.call("get_suburb_connector_z")
	var pods: PackedFloat32Array = city.call("get_suburb_pod_x")
	if lanes.is_empty() or pods.is_empty():
		return
	var span := Vector2(-874.0, -198.0)
	if city.has_method("get_suburb_lane_z"):
		var got: Variant = city.call("get_suburb_lane_z")
		if got is Vector2:
			span = got as Vector2
	var z0 := span.x
	var z1 := span.y
	_sub_clear_trees(lanes, conns, z0, z1)
	_sub_pavement(lanes, conns, z0, z1)
	_sub_control(lanes, conns)
	_sub_lighting(lanes, z0, z1)
	_sub_court(city, pods, pods[0] - lanes[0])
	_sub_entry(pods, z1)
	_sub_flush()


## THE ONLY THING THIS PASS MOVES. A tree whose TRUNK stands in new pavement is
## a defect; a canopy overhanging it is a street tree, so only the trunk is
## tested. Lane conflicts are pushed EAST — the west lane is the only one the
## yard-tree lattice can reach (tree column = pod - 7.5 m, jitter +-14 m), and
## east lands in the front-yard strip between that pavement and the house row,
## while west would land on city_dressing's own utility-pole line. Collector
## conflicts are pushed NORTH into the same yard band. Trunks and every canopy
## lobe of a moved tree translate together, in its MultiMesh and in the arrays
## that back it, so the record and the render cannot disagree.
func _sub_clear_trees(lanes: PackedFloat32Array, conns: PackedFloat32Array,
		z0: float, z1: float) -> void:
	var moved := 0
	var stuck := 0
	for _pass in 3:
		for e: Variant in _sub_trees:
			var t := e as Dictionary
			var p: Vector3 = t["pos"]
			if p.z < z0 - 20.0 or p.z > z1 + 20.0:
				continue
			for lx: float in lanes:
				if absf(p.x - lx) < SUB_LANE_HALF + SUB_TRUNK_CLEAR:
					_sub_move_tree(t, Vector3(
						lx + SUB_LANE_HALF + SUB_TRUNK_CLEAR + 0.5 - p.x, 0.0, 0.0))
					p = t["pos"]
					moved += 1
			for cz: float in conns:
				if absf(p.z - cz) < SUB_COLL_HALF + SUB_TRUNK_CLEAR:
					_sub_move_tree(t, Vector3(0.0, 0.0,
						cz - SUB_COLL_HALF - SUB_TRUNK_CLEAR - 0.5 - p.z))
					p = t["pos"]
					moved += 1
	for e2: Variant in _sub_trees:
		var t2 := e2 as Dictionary
		var p2: Vector3 = t2["pos"]
		for lx2: float in lanes:
			if absf(p2.x - lx2) < SUB_LANE_HALF and p2.z > z0 and p2.z < z1:
				stuck += 1
	if stuck > 0:
		push_warning("Stonebridle lanes: %d yard trees still in pavement" % stuck)


func _sub_move_tree(t: Dictionary, d: Vector3) -> void:
	var trunks := get_node_or_null("TreeTrunks") as MultiMeshInstance3D
	var canopies := get_node_or_null("TreeCanopies") as MultiMeshInstance3D
	var ti: int = t["trunk"]
	if ti >= 0 and ti < _trunk_xf.size():
		_trunk_xf[ti] = Transform3D(_trunk_xf[ti].basis, _trunk_xf[ti].origin + d)
		if trunks != null and trunks.multimesh != null:
			trunks.multimesh.set_instance_transform(ti, _trunk_xf[ti])
	var ci: int = t["can"]
	for k in int(t["n"]):
		var j := ci + k
		if j < 0 or j >= _canopy_xf.size():
			continue
		_canopy_xf[j] = Transform3D(_canopy_xf[j].basis, _canopy_xf[j].origin + d)
		if canopies != null and canopies.multimesh != null:
			canopies.multimesh.set_instance_transform(j, _canopy_xf[j])
	t["pos"] = (t["pos"] as Vector3) + d


## Contract for greybox_city's infill: where the yard trees stand AFTER this
## pass, so the plat can keep its houses off them.
func get_suburb_tree_spots() -> Array[Vector3]:
	var out: Array[Vector3] = []
	for e: Variant in _sub_trees:
		out.append((e as Dictionary)["pos"] as Vector3)
	return out


# ------------------------------ PAVEMENT -------------------------------------
func _sub_pavement(lanes: PackedFloat32Array, conns: PackedFloat32Array,
		z0: float, z1: float) -> void:
	var mid := (z0 + z1) * 0.5
	var run := z1 - z0
	for lx: float in lanes:
		_sub_pave.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(SUB_LANE_HALF * 2.0, 0.06, run)),
			Vector3(lx, SUB_PAVE_Y, mid)))
		# Caliche shoulder both sides. A rural-section street has no curb, so
		# the pavement edge is the only edge there is — without a shoulder it
		# reads as asphalt laid straight onto a lawn.
		for s2: float in [-1.0, 1.0]:
			_sub_shoulder.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(SUB_SHOULDER_W, 0.05, run)),
				Vector3(lx + s2 * (SUB_LANE_HALF + SUB_SHOULDER_W * 0.5),
					SUB_PAVE_Y - 0.010, mid)))
	if lanes.is_empty():
		return
	var x0: float = lanes[0] - SUB_LANE_HALF - 4.0
	var x1: float = lanes[lanes.size() - 1] + SUB_LANE_HALF + 4.0
	for cz: float in conns:
		_sub_pave.append(Transform3D(
			Basis.IDENTITY.scaled(Vector3(x1 - x0, 0.06, SUB_COLL_HALF * 2.0)),
			Vector3((x0 + x1) * 0.5, SUB_COLL_Y, cz)))
		for s3: float in [-1.0, 1.0]:
			_sub_shoulder.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(x1 - x0, 0.05, SUB_SHOULDER_W)),
				Vector3((x0 + x1) * 0.5, SUB_COLL_Y - 0.010,
					cz + s3 * (SUB_COLL_HALF + SUB_SHOULDER_W * 0.5))))
		# Collector centre line: the same 3 m dash on the same 7 m rhythm the
		# downtown grid uses, so the two street systems read as one city.
		var dx := x0 + 6.0
		while dx <= x1:
			_sub_paint.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(3.0, 0.02, 0.20)),
				Vector3(dx, SUB_PAINT_Y, cz)))
			dx += DASH_STEP


# ------------------------------ CONTROL --------------------------------------
## Stop-on-the-minor at all 78 lane approaches: bar across the approach half of
## the pavement, sign on that approach's right-hand shoulder, blades on the
## sign post. Northbound (heading -Z) drives the +X half and reads a sign
## facing +Z; southbound is the mirror. Getting that backwards is the classic
## way to ship a city where every sign faces away from the driver.
func _sub_control(lanes: PackedFloat32Array, conns: PackedFloat32Array) -> void:
	for li in lanes.size():
		var lx: float = lanes[li]
		# Every lane is its OWN street and gets its own name. The first cut
		# named both lanes of a pod alike, which put two different streets 42 m
		# apart under one blade — a wayfinding lie, caught at the corner shot.
		var lane_name := "LANE %d" % (li + 1)
		for ci in conns.size():
			var cz: float = conns[ci]
			var road: String = SUB_ROAD_NAMES[ci % SUB_ROAD_NAMES.size()]
			for s: float in [1.0, -1.0]:    # +1 northbound approach, -1 south
				var bar_z := cz + s * (SUB_COLL_HALF + SUB_STOP_SET)
				_sub_paint.append(Transform3D(
					Basis.IDENTITY.scaled(Vector3(SUB_LANE_HALF - 0.3, 0.02, 0.5)),
					Vector3(lx + s * (SUB_LANE_HALF * 0.5), SUB_PAINT_Y, bar_z)))
				_sub_sign(lx + s * (SUB_LANE_HALF + 1.1), bar_z + s * 0.6, s,
					lane_name, road)


## Stop sign + the two name blades on one post. `s` = +1 for the approach a
## northbound driver makes (post east of the lane, faces +Z), -1 for southbound.
func _sub_sign(px: float, pz: float, s: float, lane_name: String,
		road: String) -> void:
	var yaw := 0.0 if s > 0.0 else PI
	_sub_steel.append(Transform3D(Basis.IDENTITY.scaled(Vector3(0.1, 3.6, 0.1)),
		Vector3(px, 1.8, pz)))
	# A real octagon, not a red square: mesh_kit.prism with 8 sides, stood on
	# end (the prism extrudes along its own +Y, so -90 deg about X points that
	# axis at the driver) and spun an eighth of a turn so a flat edge is on top.
	_sub_stop.append(Transform3D(Basis(Vector3.UP, yaw)
		* Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI / 8.0),
		Vector3(px, 2.25, pz)))
	_row_text("STOP", Vector3(px, 2.25, pz + s * 0.05), yaw, 34,
		Color(0.97, 0.97, 0.95), 0.66, SIGN.FLAT, 0.30)
	# Blade naming the COLLECTOR, mounted parallel to it (long axis in X) and
	# faced at the stopped driver. Blade naming the LANE runs the other way.
	_sub_blade.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(2.4, 0.42, 0.07)), Vector3(px, 3.42, pz)))
	_row_text(road, Vector3(px, 3.42, pz + s * 0.05), yaw, 40, BLADE_TEXT,
		2.22, SIGN.BLADE, 0.34)
	_sub_blade.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(0.07, 0.42, 2.4)), Vector3(px, 2.98, pz)))
	_row_text(lane_name, Vector3(px + s * 0.05, 2.98, pz), PI * 0.5 * s, 40,
		BLADE_TEXT, 2.22, SIGN.BLADE, 0.34)


# ------------------------------ LIGHTING -------------------------------------
## Geometry identical to the frozen _light() / _row_light(): 7.6 m shaft, arm
## over the pavement, warm emissive head — one street-lighting vocabulary for
## the whole map. Alternating shoulders at 112 m gives each shoulder a head
## every 224 m, which is subdivision spacing, not arterial spacing.
##
## C4: the base stood at |5.8| off a 9 m lane whose caliche shoulder runs
## 4.5..6.1 — i.e. IN the shoulder, on the strip a stopped car uses, which out
## here is the rural-section equivalent of standing in the gutter downtown. It
## is at |6.9| now, 0.8 m behind the shoulder's outer edge, on grass. The arm
## grows by the same 1.1 m (3.4 -> 4.6, reach 3.1 -> 4.2), so the luminaire
## still hangs 2.7 m off the lane centreline and not one suburb pool moves.
const SUB_LIGHT_OFF := SUB_LANE_HALF + SUB_SHOULDER_W + 0.8   # 6.9
const SUB_LIGHT_ARM := 4.6
const SUB_LIGHT_REACH := 4.2


func _sub_lighting(lanes: PackedFloat32Array, z0: float, z1: float) -> void:
	for li in lanes.size():
		var lx: float = lanes[li]
		var z := z0 + 26.0
		var flip := li % 2 == 1
		while z <= z1 - 12.0:
			var s := -1.0 if flip else 1.0
			var base := Vector3(lx + s * SUB_LIGHT_OFF, 0.0, z)
			var toward := Vector3(-s, 0, 0)
			var along := Basis.looking_at(toward, Vector3.UP)
			_sub_steel.append(Transform3D(
				Basis.IDENTITY.scaled(Vector3(0.28, 7.6, 0.28)),
				base + Vector3(0, 3.8, 0)))
			_sub_steel.append(Transform3D(
				along * Basis.from_scale(Vector3(0.22, 0.22, SUB_LIGHT_ARM)),
				base + Vector3(0, 7.45, 0) + toward * (SUB_LIGHT_ARM * 0.5 - 0.1)))
			var head := Transform3D(along * Basis.from_scale(Vector3(0.5, 0.22, 1.3)),
				base + Vector3(0, 7.28, 0) + toward * SUB_LIGHT_REACH)
			_sub_lamp.append(head)
			_head_xf.append(head)     # streetlight_glow pools follow the heads
			flip = not flip
			z += SUB_LIGHT_STEP


# ------------------------------ THE COURT ------------------------------------
## mission_hook_and_ladder parks its Baron Brisket at (587.5, -360) and calls
## the spot "a Stonebridle Ranch cul-de-sac". It never was one — it was open
## dirt between two house-grid columns. It is one now: a paved bulb on a stub
## joining the plat's last two lanes, with the infill's own houses held 40 m
## clear so the wrecker still has room to swing a hook.
func _sub_court(city: Node3D, pods: PackedFloat32Array, lane_off: float) -> void:
	if not city.has_method("get_suburb_court"):
		return
	var court: Variant = city.call("get_suburb_court")
	if not (court is Vector3):
		return
	var c := court as Vector3
	var pod_x: float = pods[pods.size() - 1]
	if absf(pod_x - c.x) > 1.0:
		return
	var w := lane_off + SUB_LANE_HALF
	_sub_pave.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(w * 2.0, 0.06, SUB_LANE_HALF * 2.0)),
		Vector3(c.x, SUB_STUB_Y, c.y)))
	var bulb := MeshInstance3D.new()
	bulb.name = "StonebridleCourt"
	bulb.mesh = MESH_KIT.prism(c.z, 0.06, 22)
	bulb.position = Vector3(c.x, SUB_BULB_Y, c.y)
	bulb.material_override = SUB_SHD.asphalt_material()
	add_child(bulb)


# ------------------------------ THE ENTRY ------------------------------------
## District entry sign, on the plat's north front — the end players arrive at,
## driving north off the frontage road. Both proper nouns are canon (naming
## bible §6 Stonebridle Ranch, §7 Pioneer Vision Development); the third line
## is the HOA's own registered character, punching at the institution.
func _sub_entry(pods: PackedFloat32Array, z1: float) -> void:
	var pod_x: float = pods[pods.size() / 2]
	var x := pod_x - 13.0
	var z := z1 - 7.0
	# Plinth and wall are STONE, not asphalt (the first cut put the plinth in
	# the pavement MultiMesh and it read as a stray patch of road).
	_sub_stone.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(9.4, 0.5, 2.2)), Vector3(x, 0.05, z)))
	_sub_stone.append(Transform3D(
		Basis.IDENTITY.scaled(Vector3(8.4, 2.4, 0.5)), Vector3(x, 1.45, z)))
	# Text goes on the +Z face — the side the arriving driver sees. Reading it
	# off the -Z face put every line INSIDE the wall (caught at the entry shot).
	_row_text("STONEBRIDLE RANCH", Vector3(x, 1.92, z + 0.28), 0.0, 80,
		Color(0.94, 0.92, 0.86), 7.6, SIGN.MARQUEE, 0.62)
	_row_text("A PIONEER VISION DEVELOPMENT", Vector3(x, 1.36, z + 0.28), 0.0, 34,
		Color(0.80, 0.78, 0.70), 7.4, SIGN.PLAQUE, 0.30)
	_row_text("DRONE PATROLLED  ·  APPROVED BEIGE", Vector3(x, 0.92, z + 0.28),
		0.0, 30, Color(0.68, 0.66, 0.58), 7.4, SIGN.PLAQUE, 0.26)


func _sub_flush() -> void:
	# The pavement slabs (60 mm) and caliche shoulders (50 mm) ARE the ground
	# here; a road casting a shadow onto the dirt beside it is acne, not shade.
	_mmi_build(_sub_pave, [], SUB_SHD.asphalt_material(),
		"StonebridlePavement", false)
	_mmi(_sub_shoulder, SUB_SHOULDER, "StonebridleShoulders", false, false)
	_mmi(_sub_stone, SUB_STONE, "StonebridleMonument", false, true)
	_mmi(_sub_paint, Color(0.86, 0.83, 0.62), "StonebridlePaint", true, false)
	_mmi(_sub_steel, Color(0.22, 0.23, 0.25), "StonebridlePoles", false, true)
	_mmi(_sub_lamp, Color(1.0, 0.82, 0.45), "StonebridleLightHeads",
		false, false, true)
	# KEPT AGAINST THE RULE OF THUMB. A stop sign is a 0.84 m octagon standing
	# at 2.25 m — driver eye height — and it is the only sign out here big
	# enough to lay a readable disc on pale caliche. The blades above it are
	# 70 mm strips whose shadow is a pencil line, so those go off.
	_mmi_build(_sub_stop, [], _row_emissive(STOP_RED, 0.35),
		"StonebridleStopSigns", true, MESH_KIT.prism(0.42, 0.07, 8))
	_mmi_build(_sub_blade, [], _row_emissive(BLADE_GREEN, 0.35),
		"StonebridleBlades", false)
