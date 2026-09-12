extends RefCounted
## VEHICLE BODY BUILDER (M9 → M10 lofts → M16 tub+greenhouse → M19 SURFACES).
##
## HOW A CAR IS BUILT HERE:
##   1. RAKE NODE   — every panel hangs off one child node so a style can sit
##                    nose-high (Brisket) or laid-out (Slab) without touching
##                    the collision box or the wheels (which stay level on the
##                    visual root, parented by raycast_vehicle). M19: this node
##                    also carries the VISUAL RIDE DROP (see `DROP`).
##   2. THE TUB     — a three-axis lofted hull that stops at the beltline. It
##                    is swept as a run of CROSS-SECTIONS along Z, not extruded
##                    flat:
##                      * `SECT` gives the section its shoulder — the flank
##                        swells to full width at 48% of tub height and tumbles
##                        back in at the belt, with a hard smooth-group crease
##                        ON the shoulder so a 3/4 view gets a highlight band
##                        instead of one flat value (M18's hull was a single
##                        ruled plane per flank: one value, folded cardboard).
##                      * `_plan()` narrows the body toward the nose and tail,
##                        so the tail is a shape and not a wall.
##                      * `_blister()` swells the lower flank around each wheel
##                        station until the bodywork REACHES THE TYRE. It is
##                        derived from the same hardpoints raycast_vehicle uses
##                        (never hand-placed). Measured before M19: the tyre's
##                        outer face stood 23–142 mm outboard of the flank on
##                        the heroes and 226–255 mm on the ambient shells
##                        (traffic hangs its wheels at size.x*0.5 + 0.02, i.e.
##                        a track WIDER than the car), and the arch lip sat up
##                        to 97 mm INSIDE the tyre. Hence: discs bolted on.
##                      * the hood and decklid carry a real crown.
##   3. THE GREENHOUSE — a domed roof shell, fat A/B/C pillars, a drip rail and
##                    separately-built glass. The cabin is genuinely OPEN.
##   4. THE INTERIOR — seats, headrests, dash, steering wheel, column, and the
##                    per-model extras (police partition + MDT, wrecker
##                    clipboard and CB). Sized off the greenhouse it lives in.
##   5. DETAILS     — wheel arches (dark well band + a proud lip bead), door
##                    seams, handles, mirrors, wipers, model-specific lamp
##                    clusters, exhaust tips, fuel door, rocker, badges, plates.
##                    Chrome is a ROUND BEAD, never a flat stripe — a highlight
##                    needs a curved surface to run along.
##
## Anything bolted to a flank is placed through `_fx()` (the hull's real
## half-width at that height AND length station) and tilted by `_ftilt()` (the
## local surface slope, finite-differenced off the same function), so trim lies
## FLUSH on a curved body instead of floating off at one end.
##
## Fine detail carries `visibility_range_end`, so a parked block costs a hull
## and a greenhouse at 60 m and the full jewellery only when you are on it.
##
## The collision box is NEVER touched — this only fills a visual root. Fully
## deterministic (zero RNG), and every mesh/material is cached, so a fleet of
## identical cars shares one resource set.

const KIT := preload("res://scripts/world/mesh_kit.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")

static var _mats: Dictionary = {}
static var _meshes: Dictionary = {}

# ------------------------------- palette -------------------------------------
# D-039: the Slab's greenhouse photographed as an OPAQUE cream panel. Two
# causes, both here: privacy glass at 0.66 alpha leaves only 34% of the interior
# showing, and metallic 0.35 on a low-roughness surface with no reflection probe
# in the scene renders as a flat sample of the bright Texas sky — i.e. a painted
# panel. Alpha down, metal off (see _glass): the cabin behind it is the point.
const GLASS := Color(0.46, 0.56, 0.63, 0.34)        # alpha: cabins are visible
const GLASS_TINT := Color(0.13, 0.16, 0.19, 0.46)   # privacy glass (slab, cop)
const DEADGLASS := Color(0.42, 0.44, 0.45)          # junker: opaque, crazed
# Chrome is a MIRROR, and a mirror of a bright Texas sky at roughness 0.10 is
# just white. Darker albedo + a little roughness leaves room for a highlight to
# be brighter than the surface it sits on, which is what "chrome" actually is.
const CHROME := Color(0.70, 0.72, 0.77)
const TRIM := Color(0.09, 0.09, 0.10)
const SEAM := Color(0.10, 0.10, 0.115)
const TIREBLACK := Color(0.07, 0.07, 0.08)
const HEADLIGHT := Color(1.0, 0.96, 0.85)
const TAILLIGHT := Color(0.85, 0.09, 0.07)
const AMBER := Color(1.0, 0.55, 0.06)
const BEACON := Color(1.0, 0.62, 0.08)
const RUST := Color(0.31, 0.19, 0.12)
const PLATE := Color(0.90, 0.90, 0.86)
const SEAT_DARK := Color(0.085, 0.085, 0.095)
const SEAT_TAN := Color(0.56, 0.45, 0.30)   # reads through privacy glass
const GRIME := Color(0.115, 0.105, 0.085)
const STEEL := Color(0.47, 0.48, 0.50)

# Detail cull distances (m). Nothing here changes silhouette, only jewellery.
const D_FINE := 42.0      # seams, handles, wipers, badges, lamp sub-pieces
const D_MID := 75.0       # interior, arch flares, mirrors, trim
const D_FAR := 0.0        # never culled (hull, greenhouse, main lamps, bumpers)

# Per-style stance. Positive = nose up. Visual only: the collider stays level
# and the wheels hang off the visual root, not off this node.
const RAKE := {
	"sedan": 0.004, "police": -0.003, "pickup": 0.017,
	"wrecker": 0.007, "slab": -0.012, "junker": -0.018,
}

## VISUAL RIDE DROP (m). How far the BODY sits down on its wheels — the rake
## node moves, the wheels and the collider do not, so this is not suspension.
## Measured M18 sill-to-ground against the class it is imitating (car
## 130–170 mm, lifted truck 300–350 mm):
##     hero sedan  228 → 148   police 315 → 155   slab 315 → 145
##     Brisket     435 → 335   wrecker 398 → 318
##     traffic sedan 348 → 158  traffic truck 473 → 333  junker 224 → 164
## The wrecker line is a PANEL OFFSET only; nothing here reaches physics.
## CYCLE-1 RE-DROP. The producer ruled the sill is the LOWEST POINT OF THE
## ROCKER TRIM (what a viewer reads as the car's bottom edge), not the tub
## floor. Every number above was set against the tub floor and every one of them
## left the band when re-measured to the rocker: 198.6 / 207.1 / 400.7 / 358.7 /
## 207.5 / 195.4 / 373.6 / 77.1 mm against 130-170 (car) and 300-350 (truck).
## Re-solved against the rocker AND against the wheel-diameter:height row, which
## pulls the other way (dropping the body shortens it and RAISES the ratio):
##     Vantage 150 / 0.430   Interceptor 150 / 0.510   Brisket 325 / 0.413
##     Wrecker 340 / 0.453   Slab 150 / 0.478   amb sedan 150 / 0.509
##     amb truck 328 / 0.455  junker 150 / 0.487
## The WRECKER line is a PANEL OFFSET and nothing here reaches physics: DROP
## moves the rake node only, never the collider, the hardpoints or the wheels.
const DROP := {
	"sedan": 0.129, "police": 0.217, "pickup": 0.176,
	"wrecker": 0.099, "slab": 0.228, "junker": -0.013,
	"amb_sedan": 0.235, "amb_pickup": 0.189,
}

## ARCH GEOMETRY, IN METRES (D-020). The old ring radii were
## [1.015, 1.055, 1.085, 1.245] * wheel_radius, which hard-wired the arch gap to
## 0.085 * wr: to reach the 45 mm car floor a wheel needed R >= 0.53 m and the
## 90 mm truck floor needed R >= 1.06 m. No wheel in the fleet, or any plausible
## one, could satisfy the row. The gap is now a REAL DIMENSION:
##   GAP  tyre crown -> the arch's opening edge, where the dark cut ends and the
##        bodywork begins. This is the number the bar row reads.
##   LIPW radial width of the painted lip beyond the opening, sized so the
##        die-back edge lands INSIDE the same band as the opening edge — the row
##        then passes whichever of the two edges a reviewer measures to.
##   CLEAR tyre-to-dark-cut clearance. Deliberately tiny: push the dark cut out
##        to the full gap and the tyre reads as BURIED in painted bodywork.
const ARCH_GAP := {"car": 0.074, "truck": 0.118}
const ARCH_LIPW := {"car": 0.013, "truck": 0.019}
const ARCH_CLEAR := 0.006
## Where the black THROAT hands over to the shadowed inner lip. A single flat
## black band the full width of the gap does not read as a hole — it reads as a
## horseshoe painted on the fender, which is what the first cycle-1 draft shot
## looked like on the Slab's gold flank. Three tones (throat -> body colour in
## shadow -> body colour in light) is what an arch actually does. It also makes
## the row robust: all THREE candidate edges — 50 / 74 / 87 mm on a car,
## 95 / 118 / 137 on a truck — land inside the same band, so the measurement no
## longer depends on which edge a reviewer picks.
const ARCH_MID := {"car": 0.050, "truck": 0.095}
## The lip bead stands LIP_PROUD off whatever the hull is doing at that point on
## the arc — but never further than LIP_CAP outboard of the tyre's own face.
##
## D-021, ROUND TWO — the cap was a NO-OP on the one shell it was written for.
## `_arch_mesh` ends the lip with `x = max(x, skin + 0.002)` (the lip may never
## sink INTO the bodywork it is an edge of), and on the Slab the hull skin was
## already 53.9 mm outboard of its own tyre, so that line overrode the cap every
## time. Measured, in-engine, off the real vertices: Slab +55.6 mm against a
## 40 mm ceiling and a 25 mm original — unchanged since cycle 1.
##
## The cap was never the bug. THE FLANK WAS. Capping a lip that has to stand
## proud of a hull which is itself outboard of the track is arguing with
## arithmetic. `BEAM_MAX` below fixes the cause; with the hull inside
## `tyre + 18 mm`, `skin + 0.002` can never exceed `tyre + 0.020`, the cap binds
## for the first time, and every shell in the fleet lands on +22.0 mm — inside
## the ORIGINAL 25 mm ceiling, not just the widened 40.
const LIP_PROUD := 0.022
const LIP_CAP := 0.022

## THE BEAM CLAMP (D-021). A car's bodywork STOPS AT ITS OWN TYRE. The tub's
## maximum half-width is the collision box's — EXCEPT where the box is wider than
## the track can carry, and then the tyre wins.
##
## This is a GEOMETRIC INVARIANT, not a per-model patch: the arch arc sweeps
## +-84 deg, which always crosses SECT's shoulder (the widest point of the
## section), so any shell whose beam exceeds its track drags its own arch lip
## outboard with it. Three did — Slab +55.0 mm, Wrecker +30.0, Vantage +20.0 —
## and all three failed the row for exactly that reason.
##
## BEAM_INSET is the blister's own target (`tgt` in _desc) with 4 mm of daylight
## added, and that number is doing two jobs. The bar job: with `skin <= tyre -
## 0.022`, `max(skin, tyre)` in _arch_mesh is always `tyre`, so the lip lands on
## `tyre + LIP_PROUD` and the guard line `skin + 0.002` can never override the
## cap again. The LOOKS job, which is the one you can see: a first draft clamped
## to `tyre + 18 mm` and passed the row while making the cars WORSE — bodywork
## outboard of the tread swallows the wheel, and the Slab photographed with its
## arch as a horseshoe stencilled on a flank with the tyre hiding behind it. The
## tyre must stand PROUD of the flank to sit in a hole. The 4 mm also keeps the
## arch throat off the hull skin, which would otherwise be coincident at the top
## of the arc and stipple.
##
## VISUAL ONLY, and it has to be: `body_size` is the COLLIDER and is frozen for
## every model. This narrows the painted shell inside a box that never moves —
## the same contract DROP has carried since M18. Measured cost after the two
## non-smoke track corrections (see slab.json / sedan.json): Vantage 2 mm per
## side, Slab 2 mm, Wrecker 52 mm (its track is a FROZEN smoke field, so the
## bodywork is the only end of this that may move). Every other shell in the
## fleet is already inside the clamp and is not touched at all.
const BEAM_INSET := 0.022

## AMBIENT WHEEL MIRROR. traffic.gd / parked_cars.gd hardcode SEDAN_WHEEL 0.32
## on a 4.4 m shell and TRUCK_WHEEL 0.44 on a 5.2 m one, with mesh widths
## 0.24 / 0.32 and ride heights 0.85 / 1.10. The old `size.z * 0.075` guess
## returned 0.330 and 0.390 — 50 mm short on the truck, which is exactly why its
## tyre crown stood ABOVE its own fender (D-019). These four numbers must stay
## in lockstep with those two spawners, same as `wheel_x` below.
const AMB := {
	"sedan": {"r": 0.32, "w": 0.24, "ride": 0.85},
	"pickup": {"r": 0.44, "w": 0.32, "ride": 1.10},
}
## repo_board.gd's junker lattice, mirrored the same way: r 0.32, mesh width
## 0.24, hubs at +-1.45 and at -JUNKER_SIZE.y * 0.5 + 0.12 = -0.43.
# NOTE: "y" MUST equal repo_board.gd's junker hub height. Cycle 1 measured the
# old -0.43 as putting the tyre bottom 80 mm UNDER the pavement (body origin
# sits ground+0.67, r=0.32 -> hub must be at 0.32-0.67 = -0.35). Changed here
# and in repo_board.gd:186/194 in the SAME edit — split them and the arches
# leave the tyres by 80 mm.
const JUNKER_W := {"r": 0.32, "w": 0.24, "z": 1.45, "y": -0.35}


static func build(root: Node3D, style: String, size: Vector3, paint: Color,
		door_text: String = "", opts: Dictionary = {}) -> void:
	var hero := bool(opts.get("hero", false))
	var drop_key := style
	if not hero and (style == "sedan" or style == "pickup"):
		drop_key = "amb_" + style      # ambient shells start 120 mm higher
	var drop: float = float(DROP.get(drop_key, 0.0))
	var pitch: float = float(RAKE.get(style, 0.0))
	var rake := Node3D.new()
	rake.rotation.x = pitch
	rake.position.y = -drop
	root.add_child(rake)
	# Wheel stations: the hero profiles hand us the real wheelbase so the arches
	# land ON the wheels. Ambient shells mirror their spawner's own constants
	# (see AMB) instead of guessing them off the collision box.
	var amb: Dictionary = AMB.get(style, {}) if not hero else {}
	var wr: float = float(opts.get("wheel_r", amb.get("r", size.z * 0.075)))
	var span: float = size.z * 0.5 - wr - 0.7
	var wz: Vector2 = opts.get("wheel_z", Vector2(-span, span))
	# Hero cars hand us the real static ride height; ambient shells hang their
	# wheels at (radius - ride). Getting this wrong centres every wheel arch
	# above the tire it is supposed to trace, which is what the first draft did.
	# PER STATION (front, rear). A hero's two axles do NOT settle at the same
	# height — com_forward loads one of them harder — so this is a Vector2, and
	# feeding one average through both arches missed the settled tyre by up to
	# 42 mm on a 45 mm-wide bar row. Ambient shells hang level, so both entries
	# are equal for them.
	var wyp := Vector2(-0.506 * size.y, -0.506 * size.y)
	if amb.has("ride"):
		wyp = Vector2.ONE * (wr - float(amb["ride"]))
	if opts.has("wheel_y"):
		var wyo: Variant = opts["wheel_y"]
		wyp = wyo if wyo is Vector2 else Vector2.ONE * float(wyo)
	# HALF-TRACK + tread width. The fender blister is built from this number, so
	# it MUST equal what the spawner actually uses or the arch misses the tyre.
	# The M19 producer fix moved traffic.gd / parked_cars.gd / repo_board.gd from
	# `size.x*0.5 + 0.02` (a track wider than the car) to `- 0.075`; this default
	# now matches, and CYCLE 1 re-measured the pair as agreeing to 0.0 mm.
	var wx: float = float(opts.get("wheel_x", size.x * 0.5 - 0.075))
	var ww: float = float(opts.get("wheel_w", amb.get("w", wr * 0.74)))
	if style == "junker" and not opts.has("wheel_z"):
		# repo_board mounts junker wheels on its own lattice (see JUNKER_W); the
		# ambient formula would miss them by 0.24 m.
		wr = float(JUNKER_W["r"])
		ww = float(JUNKER_W["w"])
		wz = Vector2(-1.0, 1.0) * float(JUNKER_W["z"])
		wyp = Vector2.ONE * float(JUNKER_W["y"])
	# INTO RAKE SPACE. Everything under the rake node is pitched by `pitch` and
	# lowered by `drop`; the WHEELS are neither — they hang off the visual root.
	# Feeding the collider-space station straight in tilted every arch off its own
	# tyre by z * pitch: measured 32 mm on the Brisket's rear station and 29 mm
	# the other way on its front, against a 90-140 mm gap bar. Each station now
	# gets its OWN rake-space height, so both arches trace their real tyre.
	var cp := cos(pitch)
	var sp := sin(pitch)
	var wyd := Vector2(wyp.x + drop, wyp.y + drop)
	var wyv := Vector2(wyd.x * cp + wz.x * sp, wyd.y * cp + wz.y * sp)
	var wzv := Vector2(-wyd.x * sp + wz.x * cp, -wyd.y * sp + wz.y * cp)
	var body_mat := _candy(paint) if style == "slab" else _paint(paint)
	var g := {
		"s": size, "wz": wzv, "wr": wr, "wy": wyv,
		"tyre": wx + ww * 0.5, "hero": hero, "drop": drop, "paint": body_mat,
		"paint_col": paint,
		"truck": style == "pickup" or style == "wrecker",
	}
	match style:
		"sedan":
			_sedan(rake, g, body_mat, false, "")
		"police":
			_sedan(rake, g, body_mat, true, door_text)
		"pickup":
			_pickup(rake, g, body_mat)
		"wrecker":
			_wrecker(rake, g, body_mat, door_text)
		"slab":
			_slab(rake, g, body_mat)
		"junker":
			_junker(rake, g, body_mat)
		_:
			_mesh(rake, KIT.taper(size, Vector2(size.x, size.z)), Vector3.ZERO, _paint(paint))
	if hero:
		_badge(rake, size, str(opts.get("badge", "")), style)
		_plate_text(rake, size, str(opts.get("plate", "")))


# ============================== SILHOUETTES ==================================
## Sunbelt Vantage — the anonymous rental midsize. Soft shoulders, a long dull
## hood, a greenhouse with nothing to say. The Interceptor shares the shell.
static func _sedan(p: Node3D, g: Dictionary, body: Material,
		cop: bool, door_text: String) -> void:
	var s: Vector3 = g["s"]
	var hero: bool = g["hero"]
	var w := s.x
	var h := s.y
	var l := s.z
	# TUB: air dam -> floor -> valance -> tail -> decklid crown -> BELTLINE RUN
	# -> hood crown -> grille header -> nose. 17 points, so smooth shading has
	# real curvature to flow across instead of four flat facets.
	var prof := PackedVector2Array([
		Vector2(-0.470 * l, -0.440 * h),
		Vector2(-0.300 * l, -0.478 * h),
		Vector2(0.320 * l, -0.478 * h),
		Vector2(0.470 * l, -0.440 * h),
		Vector2(0.500 * l, -0.290 * h),
		Vector2(0.503 * l, -0.100 * h),
		Vector2(0.497 * l, 0.030 * h),     # tail-lamp shelf
		Vector2(0.470 * l, 0.096 * h),     # decklid lip
		Vector2(0.414 * l, 0.126 * h),     # decklid crown
		Vector2(0.330 * l, 0.133 * h),     # backlight base  == greenhouse rear
		Vector2(-0.215 * l, 0.152 * h),    # cowl            == greenhouse front
		Vector2(-0.272 * l, 0.132 * h),    # hood rear crown
		Vector2(-0.366 * l, 0.118 * h),    # hood crown
		Vector2(-0.450 * l, 0.064 * h),    # hood falls to the header
		Vector2(-0.489 * l, -0.020 * h),
		Vector2(-0.503 * l, -0.170 * h),   # nose face
		Vector2(-0.494 * l, -0.330 * h),
	])
	var f := _tub(p, prof, "sed", g, body, {
		"nose": 0.140, "tail": 0.115,
		"crown": 0.032 * h, "cfz": -0.215 * l, "crz": 0.330 * l,
	})
	# AMBIENT CABIN LIFT. The traffic/parked shells are 1.05 m tall boxes wearing
	# 0.64 m wheels: measured ground-to-roof they read 0.525 against a 0.42-0.52
	# bar — a wheel diameter more than half the car's height. The hero Vantage
	# carries 0.414 m of cabin above its beltline; the ambient shell carried 0.26.
	# Lifting the roof (only the roof — the beltline, the tub and the collider are
	# untouched) fixes the ratio AND the squat, toy proportion in one number.
	var lift := 0.0 if hero else 0.109 * h
	# D-065: the Vantage and the Interceptor share this shell, and at 50 m they
	# read as the same three-box outline in two colours. They now differ where an
	# outline actually reads — the CABIN. The cruiser is taller and its roof runs
	# 52 mm further aft (a squarer, upright pursuit greenhouse); the rental sits
	# lower and its backlight falls away faster. Nothing below the beltline moves,
	# so both keep every bar number they just earned.
	var ctop_z := (0.238 if cop else 0.180) * l
	var a_hi := (0.498 if cop else 0.452) * h
	var c_hi := (0.488 if cop else 0.436) * h
	var gh := {
		"cowl": Vector2(-0.215 * l, 0.152 * h),
		"a_top": Vector2(-0.055 * l, a_hi + lift),
		"c_top": Vector2(ctop_z, c_hi + lift),
		"deck": Vector2(0.330 * l, 0.133 * h),
		"b_z": 0.048 * l,
		"belt_y": 0.150 * h,
		"ghw": _fx(f, 0.150 * h, 0.048 * l) * 0.962,
		"pillar": 0.042 * w,
		"tint": cop,
	}
	var roof_u := _greenhouse(p, gh, body)
	_interior(p, {
		"belt_y": 0.150 * h, "roof_u": roof_u,
		"front_z": 0.010 * l, "rear_z": 0.230 * l, "rear": true,
		"seat_x": 0.215 * w, "seat_hw": 0.108 * w, "bench": false, "tan": false,
		"dash_z": -0.150 * l, "dash_w": 0.70 * w,
		"sw_x": -0.215 * w, "sw_z": -0.088 * l,
		"ghw": gh["ghw"], "cab": Vector2(-0.215 * l, 0.330 * l),
	}, hero)
	_chassis(p, g, f)
	_bumper(p, f, s, -0.5 * l, 0.115, false)
	_bumper(p, f, s, 0.5 * l, 0.110, false)
	_grille(p, s, -0.075 * h, 0.44, 0.115, false)
	_lamps_sedan(p, s, cop)
	_mirrors(p, f, 0.128 * h, -0.145 * l)
	_seams(p, f, [-0.078 * l, 0.148 * l], 0.140 * h, -0.245 * h, 0.34 * l)
	_handles(p, f, 0.098 * h, [-0.010 * l, 0.212 * l])
	_wipers(p, s, -0.196 * l, 0.156 * h)
	_fuel_door(p, f, 0.268 * l, -0.030 * h)
	_exhaust(p, s, [0.20 * w], 0.5 * l + 0.03, -0.300 * h, 0.035)
	if cop:
		_police_extras(p, s, f, roof_u, 0.150 * h, door_text, hero)
	else:
		_roof_fin(p, 0.150 * l, roof_u + 0.030)
		# Rental-fleet barcode sticker, bottom corner of the rear quarter glass:
		# the Vantage's whole biography in one 9 cm decal.
		_barcode(p, gh, 0.245 * l, 0.150 * h, roof_u)


## Baron Brisket — lifted crew-cab luxury truck. Slab flanks, tall flat hood,
## bull bar, nerf bars, twin stacks, and enough ride height to be the joke.
static func _pickup(p: Node3D, g: Dictionary, body: Material) -> void:
	var s: Vector3 = g["s"]
	var hero: bool = g["hero"]
	var w := s.x
	var h := s.y
	var l := s.z
	var prof := PackedVector2Array([
		Vector2(-0.475 * l, -0.450 * h),
		Vector2(-0.320 * l, -0.482 * h),
		Vector2(0.330 * l, -0.482 * h),
		Vector2(0.480 * l, -0.450 * h),
		Vector2(0.502 * l, -0.300 * h),
		Vector2(0.505 * l, -0.060 * h),
		Vector2(0.500 * l, 0.070 * h),     # tailgate top
		Vector2(0.120 * l, 0.076 * h),     # bed floor line
		Vector2(0.098 * l, 0.130 * h),     # cab rear wall  == greenhouse rear
		Vector2(-0.262 * l, 0.148 * h),    # cowl           == greenhouse front
		Vector2(-0.310 * l, 0.142 * h),
		Vector2(-0.418 * l, 0.136 * h),    # long flat hood
		Vector2(-0.482 * l, 0.104 * h),
		Vector2(-0.502 * l, 0.010 * h),    # tall grille header
		Vector2(-0.508 * l, -0.180 * h),
		Vector2(-0.498 * l, -0.340 * h),
	])
	var f := _tub(p, prof, "pu", g, body, {
		"nose": 0.105, "tail": 0.085,
		"crown": 0.026 * h, "cfz": -0.262 * l, "crz": 0.52 * l,
	})
	# Bed walls + tailgate cap the open box. Placed on the tub's own belt corner
	# (they used to stand 95 mm outboard of it — a bed wider than its truck).
	var bedx := _fx(f, 0.148 * h, 0.300 * l)
	for sx: float in [-1.0, 1.0]:
		_box(p, Vector3(w * 0.06, h * 0.16, l * 0.40), Vector3(sx * (bedx - w * 0.030), 0.148 * h, 0.300 * l), body)
		_box(p, Vector3(w * 0.078, h * 0.022, l * 0.40), Vector3(sx * (bedx - w * 0.030), 0.234 * h, 0.300 * l), _m("bedrail", TRIM, 0.55, 0.2), D_MID)
	_box(p, Vector3(bedx * 2.0, h * 0.16, l * 0.045), Vector3(0, 0.148 * h, 0.480 * l), body)
	_box(p, Vector3(bedx * 1.84, h * 0.012, l * 0.38), Vector3(0, 0.088 * h, 0.300 * l), _m("bedliner", Color(0.11, 0.11, 0.12), 0.92, 0.0), D_MID)
	# AMBIENT CAB LIFT — see _sedan. The traffic truck measured 0.527 against a
	# 0.40-0.46 truck bar. Lifted to the Baron Brisket's own cabin height (0.67 m
	# of cab above the beltline on both), which is what it is supposed to BE.
	var lift := 0.0 if hero else 0.220 * h
	var gh := {
		"cowl": Vector2(-0.262 * l, 0.148 * h),
		"a_top": Vector2(-0.150 * l, 0.468 * h + lift),
		"c_top": Vector2(0.088 * l, 0.465 * h + lift),
		"deck": Vector2(0.098 * l, 0.130 * h),
		"b_z": -0.036 * l,
		"belt_y": 0.146 * h,
		"ghw": _fx(f, 0.146 * h, -0.036 * l) * 0.968,
		"pillar": 0.046 * w,
		"tint": false,
	}
	var roof_u := _greenhouse(p, gh, body)
	_interior(p, {
		"belt_y": 0.146 * h, "roof_u": roof_u,
		"front_z": -0.110 * l, "rear_z": 0.030 * l, "rear": true,
		"seat_x": 0.225 * w, "seat_hw": 0.120 * w, "bench": false, "tan": true,
		"dash_z": -0.202 * l, "dash_w": 0.74 * w,
		"sw_x": -0.222 * w, "sw_z": -0.148 * l,
		"ghw": gh["ghw"], "cab": Vector2(-0.262 * l, 0.098 * l),
	}, hero)
	_chassis(p, g, f)
	_bumper(p, f, s, -0.5 * l, 0.10, false)
	_bumper(p, f, s, 0.5 * l, 0.10, false)
	_grille(p, s, -0.055 * h, 0.50, 0.20, true)
	_lamps_truck(p, s)
	_mirrors(p, f, 0.140 * h, -0.216 * l)
	_seams(p, f, [-0.118 * l, 0.014 * l], 0.136 * h, -0.230 * h, 0.30 * l)
	_handles(p, f, 0.086 * h, [-0.052 * l, 0.070 * l])
	_wipers(p, s, -0.244 * l, 0.152 * h)
	_fuel_door(p, f, 0.230 * l, -0.020 * h)
	var chrome := _m("chrome", CHROME, 0.19, 0.95)
	# Bull bar, nerf steps, twin stacks — the Brisket's whole personality.
	_box(p, Vector3(w * 0.88, h * 0.045, 0.10), Vector3(0, -0.090 * h, -l * 0.525), chrome)
	_box(p, Vector3(w * 0.88, h * 0.045, 0.10), Vector3(0, -0.300 * h, -l * 0.525), chrome)
	for sx2: float in [-1.0, 1.0]:
		_box(p, Vector3(0.065, h * 0.26, 0.065), Vector3(sx2 * w * 0.30, -0.200 * h, -l * 0.525), chrome)
		_cyl(p, 0.055, h * 0.50, Vector3(sx2 * w * 0.400, 0.360 * h, 0.100 * l), chrome)
		_cyl(p, 0.062, h * 0.028, Vector3(sx2 * w * 0.400, 0.612 * h, 0.100 * l), _m("stacktip", Color(0.24, 0.22, 0.20), 0.7, 0.4), false, D_MID)
		_box(p, Vector3(0.075, 0.05, l * 0.34), Vector3(sx2 * (_fx(f, -0.42 * h, -0.020 * l) + 0.05), -0.420 * h, -0.020 * l), _m("nerf", Color(0.13, 0.13, 0.14), 0.5, 0.5), D_MID)
	# Amber cab-roof clearance lights: five across, pure truck.
	for i in 5:
		_lamp(p, Vector3(0.075, 0.045, 0.07), Vector3((float(i) - 2.0) * w * 0.085, roof_u + 0.075, -0.148 * l), AMBER, 1.1, "amber_lo", D_FINE)


## Longhorn Wrecker — cab-forward rollback: stubby hood, tall boxy cab, flat
## planked deck, boom pylon over the hitch, hydraulic grime and amber warning
## gear. VISUAL ONLY on this model, always: the smoke baseline drives this rig.
static func _wrecker(p: Node3D, g: Dictionary, body: Material,
		door_text: String) -> void:
	var s: Vector3 = g["s"]
	var hero: bool = g["hero"]
	var w := s.x
	var h := s.y
	var l := s.z
	var prof := PackedVector2Array([
		Vector2(-0.480 * l, -0.430 * h),
		Vector2(-0.330 * l, -0.470 * h),
		Vector2(0.400 * l, -0.470 * h),
		Vector2(0.500 * l, -0.420 * h),
		Vector2(0.505 * l, -0.145 * h),    # chassis rail under the deck
		Vector2(0.180 * l, -0.120 * h),
		Vector2(-0.048 * l, -0.108 * h),
		Vector2(-0.058 * l, 0.140 * h),    # cab rear wall == greenhouse rear
		Vector2(-0.372 * l, 0.152 * h),    # cowl          == greenhouse front
		Vector2(-0.452 * l, 0.128 * h),    # stubby cab-forward hood
		Vector2(-0.492 * l, 0.040 * h),
		Vector2(-0.505 * l, -0.140 * h),
		Vector2(-0.496 * l, -0.320 * h),
	])
	var f := _tub(p, prof, "wr", g, body, {
		"nose": 0.095, "tail": 0.070,
		"crown": 0.020 * h, "cfz": -0.372 * l, "crz": 0.52 * l,
	})
	var deck := _m("deck", Color(0.34, 0.35, 0.37), 0.75, 0.25)
	var deckgrime := _m("deckgrime", GRIME, 0.94, 0.05)
	# The rollback deck is the widest thing on this truck, so it follows the tub's
	# own clamped beam (BEAM_INSET). Sized off the collision box it would stand
	# 25 mm proud of the hull and 7 mm outboard of the tyre it is parked over.
	var deckx: float = float(f["bw"])
	_box(p, Vector3(deckx * 1.96, h * 0.055, l * 0.58), Vector3(0, -0.085 * h, 0.205 * l), deck)
	# Deck planking: raised ribs read as a rollback bed, not a plate.
	for i in 5:
		_box(p, Vector3(deckx * 1.88, h * 0.012, l * 0.018), Vector3(0, -0.052 * h, (0.02 + 0.09 * float(i)) * l), _m("deckrib", Color(0.28, 0.29, 0.31), 0.8, 0.3), D_MID)
	for sx: float in [-1.0, 1.0]:
		_box(p, Vector3(0.055, h * 0.085, l * 0.56), Vector3(sx * (deckx - 0.010), -0.030 * h, 0.205 * l), _m("deckrail", TRIM, 0.62, 0.1))
		# Hydraulic grime: oil streaks down the rails and under the pylon.
		_box(p, Vector3(0.062, h * 0.052, l * 0.16), Vector3(sx * (deckx - 0.007), -0.056 * h, 0.100 * l), deckgrime, D_MID)
		_box(p, Vector3(0.062, h * 0.040, l * 0.09), Vector3(sx * (deckx - 0.007), -0.062 * h, 0.360 * l), deckgrime, D_FINE)
	var gh := {
		"cowl": Vector2(-0.372 * l, 0.152 * h),
		"a_top": Vector2(-0.300 * l, 0.462 * h),
		"c_top": Vector2(-0.072 * l, 0.458 * h),
		"deck": Vector2(-0.058 * l, 0.140 * h),
		"b_z": -0.182 * l,
		"belt_y": 0.150 * h,
		"ghw": _fx(f, 0.150 * h, -0.182 * l) * 0.975,
		"pillar": 0.048 * w,
		"tint": false,
	}
	var roof_u := _greenhouse(p, gh, body)
	# Work-truck cab: a vinyl BENCH, a flat upright dash, a big truck wheel.
	_interior(p, {
		"belt_y": 0.150 * h, "roof_u": roof_u,
		"front_z": -0.168 * l, "rear_z": 0.0, "rear": false,
		"seat_x": 0.20 * w, "seat_hw": 0.165 * w, "bench": true, "tan": false,
		"dash_z": -0.312 * l, "dash_w": 0.80 * w,
		"sw_x": -0.205 * w, "sw_z": -0.256 * l,
		"ghw": gh["ghw"], "cab": Vector2(-0.372 * l, -0.058 * l),
	}, hero)
	if hero:
		_box(p, Vector3(0.16, 0.02, 0.22), Vector3(0.20 * w, roof_u - 0.34, -0.296 * l), _m("clipboard", Color(0.72, 0.66, 0.50), 0.85, 0.0), D_FINE)
		_box(p, Vector3(0.14, 0.07, 0.11), Vector3(0.0, roof_u - 0.14, -0.352 * l), _m("cbradio", Color(0.14, 0.14, 0.15), 0.6, 0.2), D_FINE)
	_chassis(p, g, f)
	_bumper(p, f, s, -0.5 * l, 0.115, false)
	# The deck takes the tail, so the rear plate mounts on the chassis end.
	_box(p, Vector3(0.34, 0.145, 0.028), Vector3(0, -0.300 * h, l * 0.505 + 0.055), _m("plate", PLATE, 0.7, 0.0))
	_grille(p, s, -0.050 * h, 0.48, 0.165, false)
	_lamps_wrecker(p, s)
	_mirrors(p, f, 0.140 * h, -0.334 * l)
	_seams(p, f, [-0.185 * l], 0.140 * h, -0.245 * h, 0.22 * l)
	_handles(p, f, 0.086 * h, [-0.128 * l])
	_wipers(p, s, -0.350 * l, 0.156 * h)
	var chrome := _m("chrome", CHROME, 0.19, 0.95)
	# Boom: pylon at the deck head, arm angled back over the tow anchor, braced
	# by a chrome hydraulic ram, with a chain spool on the pylon face.
	_box(p, Vector3(w * 0.20, h * 0.40, l * 0.065), Vector3(0, 0.135 * h, 0.010 * l), deck)
	_box(p, Vector3(w * 0.26, h * 0.045, l * 0.085), Vector3(0, 0.318 * h, 0.010 * l), _m("boomcap", Color(0.28, 0.28, 0.30), 0.7, 0.3), D_MID)
	var arm := MeshInstance3D.new()
	arm.mesh = KIT.taper(Vector3(w * 0.12, 0.10, l * 0.40), Vector2(w * 0.08, l * 0.40))
	arm.material_override = _m("boomyellow", Color(0.80, 0.66, 0.20), 0.6, 0.2)
	arm.position = Vector3(0, 0.285 * h, 0.235 * l)
	arm.rotation.x = -0.36
	p.add_child(arm)
	# Wear stripe on the boom — a boom that never scraped anything is a toy.
	_box(p, Vector3(w * 0.125, 0.012, l * 0.05), Vector3(0, 0.246 * h, 0.362 * l), deckgrime, D_MID)
	var ram := MeshInstance3D.new()
	ram.mesh = KIT.prism(0.045, l * 0.20, 12)
	ram.material_override = _m("hydraulic", STEEL, 0.22, 0.85)
	ram.position = Vector3(w * 0.115, 0.185 * h, 0.145 * l)
	ram.rotation.x = 1.05
	p.add_child(ram)
	var ram2 := MeshInstance3D.new()
	ram2.mesh = KIT.prism(0.032, l * 0.13, 12)
	ram2.material_override = chrome
	ram2.position = Vector3(-w * 0.115, 0.205 * h, 0.118 * l)
	ram2.rotation.x = 1.05
	p.add_child(ram2)
	_cyl(p, h * 0.075, w * 0.16, Vector3(0, 0.245 * h, -0.028 * l), _m("spool", Color(0.30, 0.28, 0.26), 0.85, 0.4), true)
	_box(p, Vector3(w * 0.13, 0.085, 0.13), Vector3(0, 0.135 * h, 0.435 * l), chrome)
	# Amber warning gear: a proper bar, three modules on a dark plinth.
	_box(p, Vector3(w * 0.62, 0.048, 0.20), Vector3(0, roof_u + 0.055, -0.230 * l), _m("beaconbase", Color(0.13, 0.13, 0.14), 0.6, 0.2))
	for i in 3:
		_lamp(p, Vector3(w * 0.165, 0.085, 0.175), Vector3((float(i) - 1.0) * w * 0.195, roof_u + 0.122, -0.230 * l), BEACON, 2.4, "beacon", D_FAR)
	_box(p, Vector3(w * 0.66, 0.022, 0.21), Vector3(0, roof_u + 0.176, -0.230 * l), chrome, D_MID)
	# Rear work lamps + the deck-edge marker strip.
	for sx3: float in [-1.0, 1.0]:
		_lamp(p, Vector3(0.16, 0.085, 0.05), Vector3(sx3 * w * 0.30, -0.020 * h, l * 0.508), HEADLIGHT, 1.4, "worklamp", D_MID)
	_lamp(p, Vector3(w * 0.80, 0.05, 0.045), Vector3(0, -0.140 * h, l * 0.510), BEACON, 1.2, "amber_lo", D_MID)
	_door(p, door_text, f, 0.050 * h, -0.215 * l)


## Candyland Slab — long, low, laid out. Formal roof, chrome belt and window
## surrounds, vinyl top, and the fifth wheel on the trunk. Slow is the flex.
static func _slab(p: Node3D, g: Dictionary, body: Material) -> void:
	var s: Vector3 = g["s"]
	var hero: bool = g["hero"]
	var w := s.x
	var h := s.y
	var l := s.z
	var prof := PackedVector2Array([
		Vector2(-0.478 * l, -0.470 * h),
		Vector2(-0.300 * l, -0.500 * h),   # rocker skirt: it sits ON the ground
		Vector2(0.320 * l, -0.500 * h),
		Vector2(0.478 * l, -0.470 * h),
		Vector2(0.500 * l, -0.320 * h),
		Vector2(0.506 * l, -0.080 * h),
		Vector2(0.502 * l, 0.055 * h),     # tail panel top
		Vector2(0.470 * l, 0.128 * h),
		Vector2(0.400 * l, 0.152 * h),     # long flat deck
		Vector2(0.262 * l, 0.158 * h),     # backlight base
		Vector2(-0.240 * l, 0.148 * h),    # cowl (the beltline runs dead level)
		Vector2(-0.330 * l, 0.128 * h),
		Vector2(-0.430 * l, 0.108 * h),    # long low hood
		Vector2(-0.482 * l, 0.062 * h),
		Vector2(-0.505 * l, -0.060 * h),
		Vector2(-0.500 * l, -0.300 * h),
	])
	var f := _tub(p, prof, "sl", g, body, {
		"nose": 0.135, "tail": 0.160,
		"crown": 0.024 * h, "cfz": -0.240 * l, "crz": 0.262 * l,
	})
	var gh := {
		"cowl": Vector2(-0.240 * l, 0.148 * h),
		"a_top": Vector2(-0.080 * l, 0.452 * h),
		"c_top": Vector2(0.132 * l, 0.454 * h),
		"deck": Vector2(0.262 * l, 0.158 * h),
		"b_z": 0.020 * l,
		"belt_y": 0.152 * h,
		"ghw": _fx(f, 0.152 * h, 0.020 * l) * 0.950,
		"pillar": 0.058 * w,               # heavy formal pillars
		"tint": true,
		"surround": true,                  # chrome window frames: slab canon
		"sail": true,                      # formal roof: blind rear quarter
	}
	var roof_u := _greenhouse(p, gh, body)
	_interior(p, {
		"belt_y": 0.152 * h, "roof_u": roof_u,
		"front_z": 0.000 * l, "rear_z": 0.196 * l, "rear": true,
		"seat_x": 0.20 * w, "seat_hw": 0.160 * w, "bench": true, "tan": true,
		"dash_z": -0.176 * l, "dash_w": 0.74 * w,
		"sw_x": -0.205 * w, "sw_z": -0.112 * l,
		"ghw": gh["ghw"], "cab": Vector2(-0.240 * l, 0.262 * l),
	}, hero)
	_chassis(p, g, f)
	var chrome := _m("chrome", CHROME, 0.19, 0.95)
	# Vinyl half-roof, chrome belt BEAD, chrome rocker bead. A flat strip only
	# ever reads as a white stripe; a round bead runs a moving highlight.
	# The vinyl half-top has to lie ON the domed roof, not hover 90 mm over it.
	var vy: float = roof_u + float(gh["pillar"]) * 0.425 + float(gh["ghw"]) * 0.062
	_box(p, Vector3(gh["ghw"] * 1.62, h * 0.020, l * 0.150), Vector3(0, vy, 0.055 * l), _m("vinyl", Color(0.10, 0.09, 0.11), 0.88, 0.0))
	_bead(p, f, 0.104 * h, -0.010 * l, l * 0.86, h * 0.016, chrome, D_FAR)
	_bead(p, f, -0.430 * h, -0.010 * l, l * 0.60, h * 0.020, chrome, D_MID)
	_bumper(p, f, s, -0.5 * l, 0.125, true)
	_bumper(p, f, s, 0.5 * l, 0.125, true)
	_grille(p, s, -0.020 * h, 0.50, 0.135, true)
	_lamps_slab(p, s)
	var rz_tail := l * 0.5 + 0.016
	_mirrors(p, f, 0.118 * h, -0.172 * l)
	_seams(p, f, [-0.100 * l, 0.130 * l], 0.140 * h, -0.300 * h, 0.36 * l)
	_handles(p, f, 0.098 * h, [-0.032 * l, 0.196 * l])
	_wipers(p, s, -0.222 * l, 0.154 * h)
	_fuel_door(p, f, 0.218 * l, 0.020 * h)
	_exhaust(p, s, [-0.24 * w, 0.24 * w], 0.5 * l + 0.04, -0.340 * h, 0.045)
	# D-009: dead astern the tail was five stacked horizontal bands and not one
	# vertical element in 2 m of bodywork. Everything below breaks that grain:
	# four chrome dividers standing THROUGH the lamp bar, two bumper bullets, a
	# raised centre spine down the decklid, and a recessed plate housing.
	for bx: float in [-0.355, -0.118, 0.118, 0.355]:
		_box(p, Vector3(w * 0.020, h * 0.135, 0.062), Vector3(bx * w, 0.030 * h, rz_tail + 0.006), chrome, D_MID)
	for bl: float in [-1.0, 1.0]:
		_cyl(p, h * 0.048, 0.16, Vector3(bl * w * 0.235, -0.255 * h, l * 0.5 + 0.10), chrome, false, D_MID, true)
	_box(p, Vector3(w * 0.30, h * 0.030, l * 0.235), Vector3(0, 0.166 * h, 0.310 * l), body, D_MID)
	_box(p, Vector3(w * 0.075, h * 0.036, l * 0.235), Vector3(0, 0.176 * h, 0.310 * l), chrome, D_MID)
	_box(p, Vector3(0.40, 0.175, 0.030), Vector3(0, -0.300 * h, l * 0.5 + 0.086), _m("platewell", Color(0.09, 0.09, 0.10), 0.8, 0.0), D_MID)
	# The fifth wheel, laid on the trunk — canon slab jewellery, now polished.
	_cyl(p, h * 0.195, 0.13, Vector3(0, 0.245 * h, 0.360 * l), _m("tire", TIREBLACK, 0.95, 0.0), true)
	_cyl(p, h * 0.125, 0.16, Vector3(0, 0.245 * h, 0.360 * l), chrome, true)
	_cyl(p, h * 0.038, 0.19, Vector3(0, 0.245 * h, 0.360 * l), _m("spinner", Color(0.94, 0.88, 0.60), 0.10, 0.98), true)
	for i in 5:
		var spk := MeshInstance3D.new()
		spk.mesh = KIT.taper(Vector3(0.016, h * 0.23, 0.016), Vector2(0.016, 0.016))
		spk.material_override = chrome
		spk.position = Vector3(0, 0.245 * h, 0.360 * l)
		spk.rotation.x = PI * float(i) / 5.0
		spk.visibility_range_end = D_MID
		p.add_child(spk)


## Rental-fleet barcode sticker on the rear quarter glass. A white chip with
## four dark bars — reads as fleet paperwork at 5 m, as nothing at 40 m.
static func _barcode(p: Node3D, g: Dictionary, z: float, belt_y: float,
		roof_u: float) -> void:
	var y := belt_y + (roof_u - belt_y) * 0.26
	var x: float = float(g["ghw"]) + 0.010
	_box(p, Vector3(0.012, 0.075, 0.100), Vector3(x, y, z), _m("sticker", Color(0.90, 0.90, 0.88), 0.8, 0.0), D_FINE)
	for i in 4:
		_box(p, Vector3(0.008, 0.052, 0.010), Vector3(x + 0.004, y + 0.004, z - 0.033 + 0.022 * float(i)),
			_m("barcode", Color(0.08, 0.08, 0.09), 0.8, 0.0), D_FINE)


## Dorado PD Interceptor extras: livery flanks, pushbar, spotlight, antenna,
## the lightbar plinth (police.gd bolts its strobing modules on top) and the
## cage between you and the back seat.
static func _police_extras(p: Node3D, s: Vector3, f: Dictionary, roof_u: float,
		belt_y: float, door_text: String, hero: bool) -> void:
	var w := s.x
	var h := s.y
	var l := s.z
	var white := _m("livery", Color(0.93, 0.93, 0.94), 0.5, 0.0)
	_flank(p, f, -0.055 * h, -0.020 * l, Vector3(0.024, h * 0.20, l * 0.42), 0.006, white, D_FAR)
	_flank(p, f, 0.078 * h, -0.020 * l, Vector3(0.022, h * 0.05, l * 0.30), 0.008, _m("liveryblue", Color(0.10, 0.16, 0.44), 0.5, 0.0), D_MID)
	var push := _m("pushbar", TRIM, 0.55, 0.3)
	_box(p, Vector3(w * 0.84, h * 0.20, 0.085), Vector3(0, -0.145 * h, -l * 0.532), push)
	_box(p, Vector3(0.085, h * 0.24, 0.085), Vector3(-w * 0.20, -0.070 * h, -l * 0.532), push)
	_box(p, Vector3(0.085, h * 0.24, 0.085), Vector3(w * 0.20, -0.070 * h, -l * 0.532), push)
	# Lightbar plinth. police.gd's strobes occupy |x| <= 0.48 at y 0.76; these
	# end caps sit outboard so a parked marked unit still reads as marked.
	_box(p, Vector3(w * 0.68, 0.055, 0.26), Vector3(0, roof_u + 0.062, -0.075 * l), _m("barbase", Color(0.11, 0.11, 0.12), 0.6, 0.2))
	_lamp(p, Vector3(0.13, 0.10, 0.24), Vector3(-w * 0.315, roof_u + 0.115, -0.075 * l), Color(0.95, 0.09, 0.09), 0.9, "flash_r", D_MID)
	_lamp(p, Vector3(0.13, 0.10, 0.24), Vector3(w * 0.315, roof_u + 0.115, -0.075 * l), Color(0.12, 0.26, 1.0), 0.9, "flash_b", D_MID)
	# Pillar spotlight, driver's side — the thing that finds you in an alley.
	var chrome := _m("chrome", CHROME, 0.19, 0.95)
	var sy := belt_y + (roof_u - belt_y) * 0.34
	_box(p, Vector3(0.045, 0.13, 0.045), Vector3(-w * 0.412, sy, -0.196 * l), chrome, D_MID)
	_cyl(p, 0.062, 0.10, Vector3(-w * 0.412, sy + 0.10, -0.196 * l), chrome, true, D_MID)
	_lamp(p, Vector3(0.045, 0.10, 0.10), Vector3(-w * 0.452, sy + 0.10, -0.196 * l), HEADLIGHT, 1.2, "spotlamp", D_MID)
	_box(p, Vector3(0.018, h * 0.42, 0.018), Vector3(w * 0.26, 0.330 * h, 0.395 * l), _m("antenna", Color(0.10, 0.10, 0.11), 0.5, 0.3), D_FINE)
	_lamp(p, Vector3(0.14, 0.055, 0.045), Vector3(-w * 0.155, -0.020 * h, -l * 0.505), Color(0.95, 0.09, 0.09), 0.7, "flash_r", D_FINE)
	_lamp(p, Vector3(0.14, 0.055, 0.045), Vector3(w * 0.155, -0.020 * h, -l * 0.505), Color(0.12, 0.26, 1.0), 0.7, "flash_b", D_FINE)
	# THE PARTITION: the detail that makes a cruiser interior read as a cruiser.
	var cage := _m("cage", Color(0.16, 0.17, 0.18), 0.55, 0.4)
	var cy := belt_y + (roof_u - belt_y) * 0.45
	_box(p, Vector3(w * 0.72, (roof_u - belt_y) * 0.80, 0.020), Vector3(0, cy, 0.140 * l), cage, D_MID)
	if hero:
		for i in 5:
			_box(p, Vector3(0.014, (roof_u - belt_y) * 0.76, 0.030), Vector3((float(i) - 2.0) * w * 0.145, cy, 0.140 * l), _m("cagebar", Color(0.30, 0.31, 0.33), 0.4, 0.7), D_FINE)
		_box(p, Vector3(0.13, 0.16, 0.02), Vector3(0, cy - 0.03, -0.048 * l), _m("mdt", Color(0.09, 0.12, 0.16), 0.35, 0.1), D_FINE)
	_door(p, door_text, f, -0.075 * h, -0.020 * l)


## Repo stock: sagging, hood ajar, crazed glass, rust, no front bumper.
## CONTRACT: the hull must be the RAKE NODE'S FIRST MESH CHILD — repo_board
## walks `vis -> first Node3D -> first MeshInstance3D` and re-skins exactly
## that instance so the target beacon can pulse.
## M19 BUG FIX: M16 inserted the rake node above the junker's own `sag` node,
## which made that walk land on a bare Node3D and quietly re-skin NOTHING — the
## repo target beacon has been dead since M16. The sag now rides on the rake
## node itself (geometrically identical: the junker's RAKE is 0.0), so the hull
## is once again the first mesh under the first child.
static func _junker(root: Node3D, g: Dictionary, body: Material) -> void:
	var s: Vector3 = g["s"]
	var w := s.x
	var h := s.y
	var l := s.z
	var sag := root
	# The pitch half of the sag lives in RAKE (build() has to know it to put the
	# wheel stations into rake space); the roll half is local to the wreck.
	sag.rotation.z = 0.020
	var prof := PackedVector2Array([
		Vector2(-0.470 * l, -0.440 * h),
		Vector2(-0.300 * l, -0.478 * h),
		Vector2(0.320 * l, -0.478 * h),
		Vector2(0.470 * l, -0.440 * h),
		Vector2(0.500 * l, -0.290 * h),
		Vector2(0.503 * l, -0.100 * h),
		Vector2(0.497 * l, 0.030 * h),
		Vector2(0.470 * l, 0.096 * h),
		Vector2(0.414 * l, 0.126 * h),
		Vector2(0.330 * l, 0.133 * h),
		Vector2(-0.215 * l, 0.152 * h),
		Vector2(-0.272 * l, 0.132 * h),
		Vector2(-0.366 * l, 0.118 * h),
		Vector2(-0.450 * l, 0.064 * h),
		Vector2(-0.489 * l, -0.020 * h),
		Vector2(-0.503 * l, -0.170 * h),
		Vector2(-0.494 * l, -0.330 * h),
	])
	var f := _tub(sag, prof, "jk", g, body, {
		"nose": 0.140, "tail": 0.115,
		"crown": 0.032 * h, "cfz": -0.215 * l, "crz": 0.330 * l,
	})
	var gh := {
		"cowl": Vector2(-0.215 * l, 0.152 * h),
		"a_top": Vector2(-0.055 * l, 0.464 * h),
		"c_top": Vector2(0.186 * l, 0.448 * h),
		"deck": Vector2(0.330 * l, 0.133 * h),
		"b_z": 0.048 * l,
		"belt_y": 0.150 * h,
		"ghw": _fx(f, 0.150 * h, 0.048 * l) * 0.962,
		"pillar": 0.042 * w,
		"tint": false,
		"dead": true,
	}
	var roof_u := _greenhouse(sag, gh, body)
	# One torn seat still in it, because somebody used to drive this.
	_box(sag, Vector3(w * 0.22, (roof_u - 0.150 * h) * 0.8, 0.10),
		Vector3(-w * 0.19, 0.150 * h + (roof_u - 0.150 * h) * 0.45, 0.09 * l),
		_m("torn", Color(0.22, 0.19, 0.16), 0.95, 0.0), D_MID)
	_chassis(sag, g, f)
	var hood := MeshInstance3D.new()
	hood.mesh = KIT.taper(Vector3(w * 0.86, h * 0.05, l * 0.26), Vector2(w * 0.80, l * 0.26))
	hood.material_override = body
	hood.position = Vector3(0, 0.240 * h, -0.300 * l)
	hood.rotation.x = 0.34
	sag.add_child(hood)
	var rust := _m("rust", RUST, 0.96, 0.0)
	_box(sag, Vector3(w * 0.42, 0.02, l * 0.20), Vector3(w * 0.18, 0.140 * h, 0.14 * l), rust)
	_box(sag, Vector3(0.02, h * 0.18, l * 0.28), Vector3(-w * 0.50, -0.14 * h, -0.08 * l), rust)
	_box(sag, Vector3(w * 0.30, 0.02, l * 0.12), Vector3(-w * 0.14, 0.150 * h, 0.30 * l), rust)
	_box(sag, Vector3(0.02, h * 0.14, l * 0.16), Vector3(w * 0.50, -0.10 * h, 0.22 * l), rust, D_MID)
	# Dead lamps: a wreck with glowing headlights is not a wreck.
	var dull := _m("deadlens", Color(0.30, 0.30, 0.29), 0.85, 0.0)
	var dullred := _m("deadred", Color(0.30, 0.10, 0.09), 0.85, 0.0)
	for sx: float in [-1.0, 1.0]:
		_box(sag, Vector3(w * 0.24, h * 0.075, 0.05), Vector3(sx * w * 0.29, -0.055 * h, -l * 0.5 - 0.014), dull)
		_box(sag, Vector3(w * 0.15, h * 0.085, 0.05), Vector3(sx * w * 0.315, -0.005 * h, l * 0.5 + 0.014), dullred)


# ============================== THE TUB ======================================
## THE SECTION. Right half of a body cross-section, rocker (v 0) to beltline
## (v 1); `y` is the height fraction, `x` the fraction of the maximum
## half-width. This curve is the whole reason a flank stops reading as
## cardboard: it tucks under at the rocker, swells to FULL width at 48% height
## (the shoulder) and tumbles back to 0.855 at the belt. The smooth-group break
## lands exactly on the shoulder, so the highlight terminates on a crease that
## runs the length of the car — a character line, not a gradient.
const SECT := [
	Vector2(0.000, 0.620), Vector2(0.045, 0.845), Vector2(0.130, 0.945),
	Vector2(0.300, 0.992), Vector2(0.480, 1.000), Vector2(0.660, 0.988),
	Vector2(0.820, 0.955), Vector2(0.930, 0.912), Vector2(1.000, 0.855),
]
const SHOULDER_I := 4            # index of the crease in SECT
const RING_N := 22               # SECT(9) + crown(3) + SECT mirrored(9) + floor(1)


## Build the hull and return the flank descriptor every trim helper needs.
## `st` carries the per-style surface tuning: nose/tail plan taper and the
## hood/deck crown with the z window it applies over.
static func _tub(p: Node3D, prof: PackedVector2Array, hint: String,
		g: Dictionary, mat: Material, st: Dictionary) -> Dictionary:
	var f := _desc(prof, g, st)
	var size: Vector3 = g["s"]
	# The cache key carries height, length AND the wheel geometry the blister is
	# derived from: two styles that happened to share a width (the traffic sedan
	# and the Vantage) were silently sharing ONE mesh before M16.
	var wyk: Vector2 = g["wy"]
	var wzk: Vector2 = g["wz"]
	var key := "tub_%s_%.2f_%.2f_%.2f_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f" % [hint,
		size.x, size.y, size.z, float(g["wr"]), wyk.x, wyk.y, wzk.x, wzk.y,
		float(g["tyre"])]
	var mesh: ArrayMesh = _meshes.get(key)
	if mesh == null:
		mesh = _tub_mesh(f)
		_meshes[key] = mesh
	_mesh(p, mesh, Vector3.ZERO, mat).name = "Hull"   # named: measured by QA harness
	return f


## Split the closed side profile into its lower and upper chains (both strictly
## z-ascending) and stash every constant the surface functions need. Every
## profile in this file runs nose -> bottom -> tail -> top -> nose, so the
## extreme-z points are the split.
static func _desc(prof: PackedVector2Array, g: Dictionary,
		st: Dictionary) -> Dictionary:
	var n := prof.size()
	var i_nose := 0
	var i_tail := 0
	for i in n:
		if prof[i].x < prof[i_nose].x:
			i_nose = i
		if prof[i].x > prof[i_tail].x:
			i_tail = i
	var bot := PackedVector2Array()
	var top := PackedVector2Array()
	var i2 := i_nose
	while true:
		bot.append(prof[i2])
		if i2 == i_tail:
			break
		i2 = (i2 + 1) % n
	i2 = i_tail
	while true:
		top.append(prof[i2])
		if i2 == i_nose:
			break
		i2 = (i2 + 1) % n
	top.reverse()                       # both chains now run z-ascending
	var size: Vector3 = g["s"]
	return {
		"bot": bot, "top": top,
		"z0": prof[i_nose].x, "z1": prof[i_tail].x,
		# THE BEAM CLAMP (see BEAM_INSET). The section's full-width point is the
		# shoulder, and the arch arc always crosses it, so a hull wider than its
		# own track puts the arch lip outboard of the tyre no matter what the lip
		# is told to do — and buries the tyre while it is at it. The collider
		# (size.x) is never touched: this is paint.
		"bw": minf(size.x * 0.5, float(g["tyre"]) - BEAM_INSET), "l": size.z,
		"nose": float(st.get("nose", 0.12)), "tail": float(st.get("tail", 0.10)),
		"crown": float(st.get("crown", 0.0)),
		"cfz": float(st.get("cfz", -size.z)), "crz": float(st.get("crz", size.z)),
		"wz": g["wz"], "wr": float(g["wr"]), "wy": g["wy"],
		# The fender has to reach the TYRE, not the hardpoint: 18 mm inboard of
		# the tread's outer face leaves the tyre just kissing the arch, which is
		# how a stock road car sits.
		"tgt": float(g["tyre"]) - 0.018,
	}


static func _chain_y(chain: PackedVector2Array, z: float) -> float:
	var n := chain.size()
	if z <= chain[0].x:
		return chain[0].y
	for i in range(1, n):
		if z <= chain[i].x:
			var d := chain[i].x - chain[i - 1].x
			var t := 0.0 if d < 0.0001 else (z - chain[i - 1].x) / d
			return lerpf(chain[i - 1].y, chain[i].y, t)
	return chain[n - 1].y


## Plan taper: the body narrows toward the nose and the tail, so a rear 3/4
## sees a SHAPE. Before M19 the hull was a constant-width extrusion and every
## tail was a flat wall the full width of the car.
static func _plan(f: Dictionary, z: float) -> float:
	var z0: float = f["z0"]
	var z1: float = f["z1"]
	var u := clampf((z - z0) / maxf(z1 - z0, 0.0001), 0.0, 1.0)
	var a := clampf((0.20 - u) / 0.20, 0.0, 1.0)
	var b := clampf((u - 0.80) / 0.20, 0.0, 1.0)
	return 1.0 - float(f["nose"]) * a * a - float(f["tail"]) * b * b


## Fender blister strength at (y, z): 1 on the wheel centre, 0 past the arch.
## Elliptical in the wheel's own radii, so it is a function OF THE HARDPOINT
## and cannot drift away from the tyre the way a hand-placed arch did.
static func _blister(f: Dictionary, y: float, z: float) -> float:
	var wr: float = f["wr"]
	var wy: Vector2 = f["wy"]
	var wz: Vector2 = f["wz"]
	var best := 0.0
	for i in 2:
		var d := Vector2((z - wz[i]) / (wr * 1.95), (y - wy[i]) / (wr * 1.60)).length()
		var k := clampf((1.0 - d) / 0.62, 0.0, 1.0)
		best = maxf(best, k * k * (3.0 - 2.0 * k))
	return best


## |x| of the hull surface for section fraction `s` at (y, z).
static func _surf(f: Dictionary, y: float, z: float, s: float) -> float:
	var xb := absf(s) * float(f["bw"]) * _plan(f, z)
	# Ramp the blister in with |s| so the flank swells and the flat underbody
	# centreline does not.
	var ramp := clampf((absf(s) - 0.25) / 0.35, 0.0, 1.0)
	return xb + maxf(0.0, float(f["tgt"]) - xb) * _blister(f, y, z) * ramp


## Section fraction at height fraction v (piecewise-linear over SECT).
static func _sect_s(v: float) -> float:
	var vc := clampf(v, 0.0, 1.0)
	for i in range(1, SECT.size()):
		if vc <= SECT[i].x:
			var d: float = SECT[i].x - SECT[i - 1].x
			var t: float = 0.0 if d < 0.0001 else (vc - SECT[i - 1].x) / d
			return lerpf(SECT[i - 1].y, SECT[i].y, t)
	return SECT[SECT.size() - 1].y


## Half-width of the hull at (y, z) — where a trim strip has to sit.
static func _fx(f: Dictionary, y: float, z: float) -> float:
	var yb := _chain_y(f["bot"], z)
	var yt := _chain_y(f["top"], z)
	var v := clampf((y - yb) / maxf(yt - yb, 0.0001), 0.0, 1.0)
	return _surf(f, y, z, _sect_s(v))


## Roll angle that lays a strip flat on the local surface. Finite-differenced
## off _fx, so it tracks the shoulder crown and the fender blister for free.
static func _ftilt(f: Dictionary, sx: float, y: float, z: float) -> float:
	var d := 0.045
	return -sx * atan((_fx(f, y + d, z) - _fx(f, y - d, z)) / (2.0 * d))


## Both flanks, flush-mounted, proud by `proud` metres.
static func _flank(p: Node3D, f: Dictionary, y: float, z: float, size: Vector3,
		proud: float, mat: Material, cull := 0.0) -> void:
	for sx: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = KIT.taper(size, Vector2(size.x, size.z))
		mi.material_override = mat
		mi.position = Vector3(sx * (_fx(f, y, z) + proud), y, z)
		mi.rotation.z = _ftilt(f, sx, y, z)
		if cull > 0.0:
			mi.visibility_range_end = cull
		p.add_child(mi)


## A ROUND bead laid along the flank. Chrome only reads as chrome when the
## highlight has a curved surface to run down; the M18 flat strips read as
## painted-on white tape from every angle.
static func _bead(p: Node3D, f: Dictionary, y: float, z: float, length: float,
		r: float, mat: Material, cull := 0.0) -> void:
	for sx: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		mi.mesh = KIT.prism(r, length, 10)
		mi.material_override = mat
		mi.position = Vector3(sx * (_fx(f, y, z) + r * 0.55), y, z)
		mi.rotation.x = PI * 0.5
		if cull > 0.0:
			mi.visibility_range_end = cull
		p.add_child(mi)


# ------------------------------ the swept mesh -------------------------------
## One cross-section ring at station z, in ring order (CCW in x/y seen from
## +Z). Godot's front faces are CLOCKWISE seen from outside, which is what the
## quad order in _tub_mesh is built for.
static func _ring(f: Dictionary, z: float) -> PackedVector3Array:
	var yb := _chain_y(f["bot"], z)
	var yt := _chain_y(f["top"], z)
	var span := yt - yb
	# Crown only over the hood and the decklid: crowning the belt plane would
	# push the cabin floor up through the seat cushions, and crowning a pickup
	# bed floor would lift it through the bedliner.
	var cr := 0.0
	var crown: float = f["crown"]
	if crown > 0.0:
		var ramp: float = maxf(float(f["l"]) * 0.06, 0.001)
		var a := clampf((float(f["cfz"]) - z) / ramp, 0.0, 1.0)
		var b := clampf((z - float(f["crz"])) / ramp, 0.0, 1.0)
		cr = crown * maxf(a, b)
	var out := PackedVector3Array()
	out.resize(RING_N)
	var i := 0
	for k in SECT.size():                          # right flank, rocker -> belt
		var v: float = SECT[k].x
		var y := yb + span * v
		out[i] = Vector3(_surf(f, y, z, SECT[k].y), y, z)
		i += 1
	for c: float in [0.55, 0.0, -0.55]:            # crowned top face
		var s: float = SECT[SECT.size() - 1].y * c
		out[i] = Vector3(_surf(f, yt, z, s) * signf(c), yt + cr * (1.0 - c * c), z)
		i += 1
	for k in range(SECT.size() - 1, -1, -1):       # left flank, belt -> rocker
		var v2: float = SECT[k].x
		var y2 := yb + span * v2
		out[i] = Vector3(-_surf(f, y2, z, SECT[k].y), y2, z)
		i += 1
	out[i] = Vector3(0.0, yb, z)                   # floor centreline
	return out


## Length stations. Every profile breakpoint is kept (the silhouette is exact),
## plus a ring of samples around each wheel so the blister is smooth, plus a
## subdivision cap so long flat runs still curve in plan.
static func _stations(f: Dictionary) -> PackedFloat32Array:
	var l: float = f["l"]
	var z0: float = float(f["z0"]) + l * 0.005
	var z1: float = float(f["z1"]) - l * 0.005
	var raw: Array[float] = []
	for pt in (f["bot"] as PackedVector2Array):
		raw.append(clampf(pt.x, z0, z1))
	for pt2 in (f["top"] as PackedVector2Array):
		raw.append(clampf(pt2.x, z0, z1))
	var wz: Vector2 = f["wz"]
	var wr: float = f["wr"]
	for wzi: float in [wz.x, wz.y]:
		for m: float in [-1.5, -1.0, -0.55, 0.0, 0.55, 1.0, 1.5]:
			raw.append(clampf(wzi + m * wr, z0, z1))
	raw.sort()
	var keep: Array[float] = []
	for v: float in raw:
		if keep.is_empty() or v - keep[keep.size() - 1] > l * 0.006:
			keep.append(v)
	var out := PackedFloat32Array()
	for i in keep.size():
		out.append(keep[i])
		if i + 1 < keep.size():
			var gap: float = keep[i + 1] - keep[i]
			var extra := int(gap / (l * 0.11))
			for k in extra:
				out.append(keep[i] + gap * float(k + 1) / float(extra + 1))
	return out


static func _tub_mesh(f: Dictionary) -> ArrayMesh:
	var zs := _stations(f)
	var n := zs.size()
	var rings: Array[PackedVector3Array] = []
	for z: float in zs:
		rings.append(_ring(f, z))
	# Smooth group per ring segment: 3 = lower flank, 4 = shoulder and up,
	# 1 = top face, 2 = floor. The 3/4 boundary IS the character line.
	# Ring layout: 0..8 right flank, 9..11 crown, 12..20 left flank, 21 floor.
	var grp := PackedInt32Array()
	grp.resize(RING_N)
	for i in RING_N:
		var gv := 3                                # lower flank
		if i >= SHOULDER_I and i <= 7:
			gv = 4                                 # right shoulder and up
		elif i >= 8 and i <= 11:
			gv = 1                                 # top face
		elif i >= 12 and i <= 15:
			gv = 4                                 # left shoulder and up
		elif i >= 20:
			gv = 2                                 # floor
		grp[i] = gv
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for k in n - 1:
		var a := rings[k]
		var b := rings[k + 1]
		for i in RING_N:
			var j := (i + 1) % RING_N
			st.set_smooth_group(grp[i])
			_q(st, a[i], b[i], b[j], a[j])
	st.set_smooth_group(-1)                        # flat nose and tail faces
	var r0 := rings[0]
	var c0 := _centroid(r0)
	for i in RING_N:
		_t(st, c0, r0[i], r0[(i + 1) % RING_N])
	var r1 := rings[n - 1]
	var c1 := _centroid(r1)
	for i in RING_N:
		_t(st, c1, r1[(i + 1) % RING_N], r1[i])
	st.generate_normals()
	return st.commit()


static func _centroid(r: PackedVector3Array) -> Vector3:
	var acc := Vector3.ZERO
	for v in r:
		acc += v
	return acc / float(r.size())


static func _q(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_t(st, a, b, c)
	_t(st, a, c, d)


static func _t(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


# ============================== GREENHOUSE ===================================
## Roof + pillars + separately-glazed windows. The cabin is genuinely open, so
## the interior behind the (alpha) glass is what you actually see. Returns the
## roof UNDERSIDE height — the ceiling every interior piece is sized against.
static func _greenhouse(p: Node3D, g: Dictionary, body: Material) -> float:
	var cowl: Vector2 = g["cowl"]
	var a_top: Vector2 = g["a_top"]
	var c_top: Vector2 = g["c_top"]
	var deck: Vector2 = g["deck"]
	var belt_y: float = g["belt_y"]
	# ONE half-width for the whole greenhouse. An earlier draft lerped it from
	# beltline to roof, which put the side glass OUTBOARD of the roof panel it
	# was supposed to tuck under — the cabin read as a bubble bolted on top.
	var ghw: float = g["ghw"]
	var pw: float = g["pillar"]
	var b_z: float = g["b_z"]
	var roof_y: float = minf(a_top.y, c_top.y)
	var roof_t := pw * 0.85
	var roof_u := roof_y - roof_t * 0.5
	var dead: bool = bool(g.get("dead", false))
	var glass := _m("deadglass", DEADGLASS, 0.75, 0.0) if dead \
		else (_glass("glass_tint", GLASS_TINT) if bool(g.get("tint", false)) \
		else _glass("glass", GLASS))

	# --- roof shell: DOMED across the width and cambered fore/aft. M18 shipped
	# a flat plate, which is why the cabin read as a lid rather than a roof. ---
	var rd := c_top - a_top
	var rlen := rd.length()
	var roof := MeshInstance3D.new()
	var rkey := "roof_%.3f_%.3f_%.3f" % [ghw, rlen, roof_t]
	var rmesh: ArrayMesh = _meshes.get(rkey)
	if rmesh == null:
		# Only a little wider than the glass: M18's 2.06x overhang read as a
		# plank balanced on the cabin.
		rmesh = _dome(ghw * 1.94, rlen + pw * 0.9, ghw * 0.105, roof_t, ghw * 1.74)
		_meshes[rkey] = rmesh
	roof.mesh = rmesh
	roof.name = "Roof"                  # named: the O:H bar row measures to it
	roof.material_override = body
	roof.position = Vector3(0, (a_top.y + c_top.y) * 0.5, (a_top.x + c_top.x) * 0.5)
	roof.rotation.x = -atan2(rd.y, rd.x)
	p.add_child(roof)
	# Drip rail: the joint between roof and side glass. Without it the roof is a
	# slab balanced on nothing.
	for sxr: float in [-1.0, 1.0]:
		var rail := MeshInstance3D.new()
		rail.mesh = KIT.prism(pw * 0.22, rlen + pw * 1.5, 8)
		rail.material_override = _m("driprail", Color(0.10, 0.10, 0.11), 0.5, 0.35)
		rail.position = Vector3(sxr * (ghw * 1.00), roof_y - roof_t * 0.22,
			(a_top.x + c_top.x) * 0.5)
		rail.rotation.x = PI * 0.5 - atan2(rd.y, rd.x)
		rail.visibility_range_end = D_MID
		p.add_child(rail)

	# --- glazing ---
	_pane(p, cowl, a_top, ghw * 1.92, ghw * 1.80, pw * 0.34, glass)
	_pane(p, deck, c_top, ghw * 1.88, ghw * 1.76, pw * 0.34, glass)
	var y0 := belt_y + pw * 0.16
	var y1 := roof_u - pw * 0.06
	var f_bot0 := lerpf(cowl.x, a_top.x, 0.40)
	var f_top0 := a_top.x + pw * 1.0
	var r_bot1 := lerpf(deck.x, c_top.x, 0.40)
	var r_top1 := c_top.x - pw * 1.0
	var gx := ghw - pw * 0.34
	# A FORMAL ROOF has no rear quarter GLASS — it has a blind sail panel that
	# carries the roof into the decklid. That is what makes a slab a slab, and it
	# is also the fix for D-007: the C-pillar stops being a lone post on a rake
	# and becomes the leading edge of a panel, so its corners have something to
	# resolve INTO. It changes the outline at 50 m too (D-065).
	var sail: bool = bool(g.get("sail", false))
	for sx: float in [-1.0, 1.0]:
		_window(p, sx * gx, f_bot0, b_z - pw * 0.5, f_top0, b_z - pw * 0.5, y0, y1, pw * 0.30, glass)
		if r_bot1 - (b_z + pw * 0.5) > 0.06:
			if sail:
				_window(p, sx * (gx + pw * 0.10), b_z + pw * 0.5, r_bot1,
					b_z + pw * 0.5, r_top1, y0 - pw * 0.20, y1, pw * 0.72, body)
			else:
				_window(p, sx * gx, b_z + pw * 0.5, r_bot1, b_z + pw * 0.5, r_top1, y0, y1, pw * 0.30, glass)

	# --- pillars, painted, sitting proud of the glass. M18 ran them at 0.030*w
	# (57 mm on the Vantage) and they barely registered; a real A-pillar is
	# ~100 mm and the C-pillar of a formal roof is twice that. ---
	_post(p, g, cowl, a_top, pw * 1.15, pw * 1.20, body, 0.90)             # A
	_post(p, g, deck, c_top, pw * 1.45, pw * 1.20, body, 0.90)             # C
	_post(p, g, Vector2(b_z, belt_y), Vector2(b_z, roof_u), pw * 1.20, pw * 1.15, body)  # B
	# Beltline sill: the tub/greenhouse joint. A ROUND bead, so the shut line
	# under the glass throws a highlight instead of a painted stripe.
	var sill_z := (cowl.x + deck.x) * 0.5
	var sill_len := absf(deck.x - cowl.x) * 0.98
	var sillm := _m("chrome", CHROME, 0.19, 0.95) if bool(g.get("surround", false)) \
		else _m("sill", TRIM, 0.55, 0.25)
	for sx2: float in [-1.0, 1.0]:
		var sb := MeshInstance3D.new()
		sb.mesh = KIT.prism(pw * 0.24, sill_len, 8)
		sb.material_override = sillm
		sb.position = Vector3(sx2 * (ghw + pw * 0.12), belt_y + pw * 0.16, sill_z)
		sb.rotation.x = PI * 0.5
		sb.visibility_range_end = D_MID
		p.add_child(sb)
	return roof_u


## A domed panel: flat underside, parabolic top, smooth across the width. Used
## for the roof, where a flat plate is the difference between "a car" and "a
## box with a lid". Local +Y up, +Z along its length.
static func _dome(width: float, length: float, rise: float, thick: float,
		top_w: float) -> ArrayMesh:
	const NX := 7
	var st := SurfaceTool.new()
	var hx := width * 0.5
	var tx := top_w * 0.5
	var hz := length * 0.5
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var top := PackedVector2Array()
	var bot := PackedVector2Array()
	for i in NX:
		var u := -1.0 + 2.0 * float(i) / float(NX - 1)
		# Narrows AND domes: tumblehome and crown in one surface.
		top.append(Vector2(u * tx, thick * 0.5 + rise * (1.0 - u * u)))
		bot.append(Vector2(u * hx, -thick * 0.5))
	for i in NX - 1:
		st.set_smooth_group(0)                      # the crown is a curve
		_q(st, Vector3(top[i].x, top[i].y, -hz), Vector3(top[i + 1].x, top[i + 1].y, -hz),
			Vector3(top[i + 1].x, top[i + 1].y, hz), Vector3(top[i].x, top[i].y, hz))
		st.set_smooth_group(-1)
		_q(st, Vector3(bot[i].x, bot[i].y, hz), Vector3(bot[i + 1].x, bot[i + 1].y, hz),
			Vector3(bot[i + 1].x, bot[i + 1].y, -hz), Vector3(bot[i].x, bot[i].y, -hz))
	st.set_smooth_group(-1)
	for i2 in NX - 1:                               # front / rear edge faces
		_q(st, Vector3(bot[i2].x, bot[i2].y, -hz), Vector3(bot[i2 + 1].x, bot[i2 + 1].y, -hz),
			Vector3(top[i2 + 1].x, top[i2 + 1].y, -hz), Vector3(top[i2].x, top[i2].y, -hz))
		_q(st, Vector3(top[i2].x, top[i2].y, hz), Vector3(top[i2 + 1].x, top[i2 + 1].y, hz),
			Vector3(bot[i2 + 1].x, bot[i2 + 1].y, hz), Vector3(bot[i2].x, bot[i2].y, hz))
	for sxe: float in [-1.0, 1.0]:                  # roof drip faces
		var idx := 0 if sxe < 0.0 else NX - 1
		var a := Vector3(top[idx].x, top[idx].y, -hz)
		var b := Vector3(top[idx].x, top[idx].y, hz)
		var c := Vector3(bot[idx].x, bot[idx].y, hz)
		var d := Vector3(bot[idx].x, bot[idx].y, -hz)
		if sxe > 0.0:
			_q(st, d, c, b, a)
		else:
			_q(st, a, b, c, d)
	st.generate_normals()
	return st.commit()


## A raked full-width plate (windshield / backlight): local +Y runs up the rake,
## and the top face narrows to the roof's width.
static func _pane(p: Node3D, a: Vector2, b: Vector2, w_bot: float, w_top: float,
		thick: float, mat: Material) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.02:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = KIT.taper(Vector3(w_bot, len, thick), Vector2(w_top, thick))
	mi.material_override = mat
	mi.position = Vector3(0, (a.y + b.y) * 0.5, (a.x + b.x) * 0.5)
	mi.rotation.x = atan2(d.x, d.y)
	p.add_child(mi)


## A trapezoid side window: taper's shifted, resized top face gives the real
## quarter-light slant instead of a rectangle pretending to be one.
static func _window(p: Node3D, x: float, z0b: float, z1b: float, z0t: float,
		z1t: float, y0: float, y1: float, thick: float,
		mat: Material) -> void:
	var lb := z1b - z0b
	var lt := z1t - z0t
	if lb < 0.05 or y1 - y0 < 0.03:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = KIT.taper(Vector3(thick, y1 - y0, lb), Vector2(thick, maxf(lt, 0.05)),
		Vector2(0, ((z0t + z1t) - (z0b + z1b)) * 0.5))
	mi.material_override = mat
	mi.position = Vector3(x, (y0 + y1) * 0.5, (z0b + z1b) * 0.5)
	p.add_child(mi)


## A pillar: a painted post running between two profile points, on both flanks.
static func _post(p: Node3D, g: Dictionary, a: Vector2, b: Vector2,
		wide: float, thick: float, mat: Material, shorten := 1.0) -> void:
	var d := b - a
	var len := d.length()
	if len < 0.02:
		return
	# A raked post is a BOX centred on its axis: its top corners stand `wide/2`
	# perpendicular to that axis, which on an A- or C-pillar is mostly UPWARD.
	# At M18's pillar widths that was invisible; at M19's it put a painted fin
	# through the roof on every car. Pull the top end down inside the panel.
	b = a + d * shorten
	d = b - a
	len = d.length()
	var mid := (a + b) * 0.5
	var ghw: float = g["ghw"]
	for sx: float in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		# `top_size` is the (x, z) of the +Y face — and z here is the pillar's
		# LENGTH. Passing `wide` for it collapsed every post into a knife-edge wedge
		# in side view: full length at its trailing face, 90 mm at its leading one.
		# That is D-007's "flat-sided prism ... unresolved corners" — the corners do
		# not resolve because the two faces are not the same shape. A post now keeps
		# its length and takes a small chamfer across its thickness.
		mi.mesh = KIT.taper(Vector3(thick, wide, len), Vector2(thick * 0.88, len * 0.97))
		mi.material_override = mat
		# INSIDE the roof's edge. M18 sat the post at ghw - 10% of its own
		# thickness, which put its outer face proud of both the glass AND the
		# roof panel — from a 3/4 view the pillars read as loose wedges stuck to
		# the outside of the cabin.
		mi.position = Vector3(sx * (ghw - thick * 0.52), mid.y, mid.x)
		mi.rotation.x = -atan2(d.y, d.x)
		p.add_child(mi)


# ============================== INTERIOR =====================================
## Seats, headrests, dash, wheel, column — all proportioned off the greenhouse
## they live in (belt_y .. roof_u), so a 0.33 m slab cabin and a 0.55 m truck
## cab both get furniture that fits and never pokes through the roof.
static func _interior(p: Node3D, c: Dictionary, hero: bool) -> void:
	var belt_y: float = c["belt_y"]
	var roof_u: float = c["roof_u"]
	var span: float = maxf(roof_u - belt_y, 0.12)
	var tan: bool = bool(c.get("tan", false))
	var seat := _m("seat_tan" if tan else "seat_dark",
		SEAT_TAN if tan else SEAT_DARK, 0.82, 0.0)
	var dashm := _m("dashtop", Color(0.075, 0.075, 0.085), 0.72, 0.05)
	var seat_x: float = c["seat_x"]
	var seat_hw: float = c["seat_hw"]
	var bench: bool = bool(c.get("bench", false))
	var fz: float = c["front_z"]
	var base_y := belt_y - span * 0.10
	var back_top := belt_y + span * 0.70
	var back_h := back_top - (base_y + span * 0.06)

	if bench:
		_box(p, Vector3(seat_hw * 2.5, span * 0.20, 0.50), Vector3(0, base_y, fz), seat, D_MID)
		_seatback(p, Vector3(0, back_top - back_h * 0.5, fz + 0.24), seat_hw * 2.5, back_h, seat)
		if hero:
			_box(p, Vector3(seat_hw * 2.3, span * 0.14, 0.09), Vector3(0, back_top + span * 0.09, fz + 0.28), seat, D_FINE)
	else:
		for sx: float in [-1.0, 1.0]:
			_box(p, Vector3(seat_hw * 1.9, span * 0.20, 0.48), Vector3(sx * seat_x, base_y, fz), seat, D_MID)
			_seatback(p, Vector3(sx * seat_x, back_top - back_h * 0.5, fz + 0.23), seat_hw * 1.9, back_h, seat)
			if hero:
				_box(p, Vector3(seat_hw * 1.15, span * 0.17, 0.085), Vector3(sx * seat_x, back_top + span * 0.10, fz + 0.27), seat, D_FINE)
	if bool(c.get("rear", false)):
		var rz: float = c["rear_z"]
		_box(p, Vector3(seat_x * 2.8, span * 0.20, 0.44), Vector3(0, base_y, rz), seat, D_MID)
		_seatback(p, Vector3(0, back_top - back_h * 0.55, rz + 0.22), seat_x * 2.8, back_h * 0.90, seat)
	# Dash: a body-wide shelf with a binnacle in front of the driver.
	var dash_y := belt_y + span * 0.14
	_box(p, Vector3(c["dash_w"], span * 0.30, 0.34), Vector3(0, dash_y, c["dash_z"]), dashm, D_MID)
	if hero:
		_box(p, Vector3(0.34, span * 0.18, 0.20), Vector3(c["sw_x"], dash_y + span * 0.22, float(c["dash_z"]) + 0.09), dashm, D_FINE)
		_box(p, Vector3(0.28, span * 0.11, 0.02), Vector3(c["sw_x"], dash_y + span * 0.24, float(c["dash_z"]) + 0.185),
			_m("gauge", Color(0.11, 0.13, 0.15), 0.35, 0.1), D_FINE)
	# Steering wheel: an octagon ring reads perfectly round behind glass.
	var swr := span * 0.44
	var hub := Vector3(c["sw_x"], belt_y + span * 0.42, c["sw_z"])
	# NOTE: the cull range goes on the MESHES, never on this pivot —
	# `visibility_range_end` is a GeometryInstance3D property and assigning it
	# to a bare Node3D throws once per car and leaks the node at quit.
	var ring := Node3D.new()
	ring.position = hub
	ring.rotation.x = -0.46                # the top of a wheel leans forward
	p.add_child(ring)
	var rim := _m("swrim", Color(0.055, 0.055, 0.06), 0.65, 0.05)
	var segs := 8
	var seg_len := 2.0 * swr * sin(PI / float(segs)) * 1.12
	for i in segs:
		var a := TAU * float(i) / float(segs)
		var seg := MeshInstance3D.new()
		seg.mesh = KIT.taper(Vector3(seg_len, swr * 0.19, swr * 0.19), Vector2(seg_len, swr * 0.19))
		seg.material_override = rim
		seg.position = Vector3(cos(a) * swr, sin(a) * swr, 0)
		seg.rotation.z = a
		seg.visibility_range_end = D_MID
		ring.add_child(seg)
	var boss := MeshInstance3D.new()
	boss.mesh = KIT.taper(Vector3(swr * 0.72, swr * 0.44, swr * 0.22), Vector2(swr * 0.62, swr * 0.22))
	boss.material_override = rim
	boss.visibility_range_end = D_MID
	ring.add_child(boss)
	if hero:
		_box(p, Vector3(0.045, 0.045, absf(float(c["dash_z"]) - hub.z) * 0.9),
			Vector3(hub.x, hub.y - swr * 0.55, (hub.z + float(c["dash_z"])) * 0.5),
			_m("column", Color(0.09, 0.09, 0.10), 0.6, 0.1), D_FINE)
	# DOOR CARDS + PARCEL SHELF. Seats and a dash floating in a glass box still
	# read as an aquarium from a 3/4 view, because the flanks of the cabin are
	# empty air: you see straight through the near glass, past the seats, and out
	# the far glass. Trim panels down both sides and a shelf under the backlight
	# close the cabin off, which is what makes it read as an INTERIOR.
	var ghw: float = float(c.get("ghw", 0.0))
	if ghw <= 0.0:
		return
	var cab: Vector2 = c.get("cab", Vector2.ZERO)
	var cz0 := minf(cab.x, cab.y) + 0.10
	var cz1 := maxf(cab.x, cab.y) - 0.10
	if cz1 - cz0 < 0.20:
		return
	var card := _m("doorcard" if not tan else "doorcard_tan",
		(SEAT_TAN * 0.72) if tan else Color(0.11, 0.11, 0.125), 0.85, 0.0)
	for sx2: float in [-1.0, 1.0]:
		_box(p, Vector3(0.026, span * 0.42, cz1 - cz0),
			Vector3(sx2 * (ghw - 0.020), belt_y + span * 0.20, (cz0 + cz1) * 0.5),
			card, D_MID)
	if bool(c.get("rear", false)):
		_box(p, Vector3(ghw * 1.64, 0.028, 0.30),
			Vector3(0, belt_y + span * 0.24, cz1 - 0.13), card, D_MID)


static func _seatback(p: Node3D, pos: Vector3, wide: float, hgt: float,
		mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = KIT.taper(Vector3(wide, hgt, 0.12), Vector2(wide * 0.90, 0.12))
	mi.material_override = mat
	mi.position = pos
	mi.rotation.x = 0.15                   # seatbacks lean
	mi.visibility_range_end = D_MID
	p.add_child(mi)


# ============================== CHASSIS DETAIL ===============================
## Wheel arches and rockers, all derived from the SAME hardpoints raycast_vehicle
## drives the wheels with — never hand-placed (they were once, and sat 0.45 m
## behind the tyres for three milestones).
##
## M18 had one thin lip at radius 1.12*wr, positioned at `_fx + 8 mm`. Measured:
## that put it 17–97 mm INSIDE the tyre's outer face on three of five heroes, so
## there was no arch edge in the picture at all — just a disc against a flank.
## An arch needs three things to read, and now has them:
##   WELL  a dark band from the tyre's radius out to the lip: the hole
##   LIP   a raised bead OUTBOARD of the tyre, standing proud of the local
##         surface wherever the body happens to be at that point on the arc
##   TUCK  the hull's own blister (see _blister) already carried the bodywork
##         out to the tyre, so the lip has something to be an edge OF.
static func _chassis(p: Node3D, g: Dictionary, f: Dictionary) -> void:
	var s: Vector3 = g["s"]
	var wz: Vector2 = g["wz"]
	var wr: float = g["wr"]
	var wy: Vector2 = g["wy"]
	var tyre: float = g["tyre"]
	var truck: bool = bool(g.get("truck", false))
	var gap: float = float(ARCH_GAP["truck" if truck else "car"])
	var lipw: float = float(ARCH_LIPW["truck" if truck else "car"])
	var amid: float = float(ARCH_MID["truck" if truck else "car"])
	var h := s.y
	var well := _m("archwell", Color(0.052, 0.052, 0.058), 0.92, 0.0)
	# The arch lip is painted body colour (below), so the MATERIAL is still
	# needed. The shadow underneath only ever wanted the COLOUR, and a
	# ShaderMaterial has no `albedo_color` to read it back from — so the colour
	# now travels in the dict beside the material rather than being recovered
	# from it.
	var paint: Material = g["paint"]
	var pc: Color = g.get("paint_col", Color(0.5, 0.5, 0.5))
	var shadow := _m("archshade_%s" % pc.to_html(false), pc * 0.34, 0.75, 0.0)
	for sx: float in [-1.0, 1.0]:
		for i in 2:
			var z: float = wz[i]
			var ay: float = wy[i]
			var key := "arch_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f_%.1f_%.3f" % [wr, ay, z,
				tyre, gap, lipw, sx, _fx(f, ay + wr + gap + lipw, z)]
			var mesh: ArrayMesh = _meshes.get(key)
			if mesh == null:
				mesh = _arch_mesh(f, ay, z, wr, tyre, sx, gap, amid, lipw)
				_meshes[key] = mesh
			var mi2 := MeshInstance3D.new()
			mi2.mesh = mesh
			mi2.name = "Arch"       # named: the arch-gap bar row measures to it
			mi2.set_surface_override_material(0, well)     # the throat
			mi2.set_surface_override_material(1, shadow)   # the lip, in shadow
			mi2.set_surface_override_material(2, paint)    # the lip, in light
			p.add_child(mi2)
		# Rocker: the sill panel between the wheels, tucked under the shoulder.
		var rky := -0.400 * h
		var rkz := (wz.x + wz.y) * 0.5
		var mi := MeshInstance3D.new()
		mi.mesh = KIT.taper(Vector3(0.045, h * 0.07, (wz.y - wz.x) * 0.70),
			Vector2(0.030, (wz.y - wz.x) * 0.70))
		mi.name = "Rocker"      # named: the sill-to-ground bar row measures to it
		mi.material_override = _m("rocker", Color(0.10, 0.10, 0.11), 0.72, 0.1)
		mi.position = Vector3(sx * (_fx(f, rky, rkz) + 0.004), rky, rkz)
		mi.rotation.z = _ftilt(f, sx, rky, rkz)
		p.add_child(mi)


## One wheel arch, swept as a single cached two-surface mesh (4 instances a car,
## where the M18 segment soup cost 20 and still didn't read).
## The swept cross-section, from the tyre outward:
##   A  at the tyre's outer face, radius 1.02*wr — the inner edge of the hole
##   B  the WELL floor: SURFACE 0, dark, the shadow you see past the tyre
##   C  the LIP crest, 22 mm proud of whatever the hull is doing here
##   D  dying back into the body skin — C..D is SURFACE 1 and is PAINTED, so
##      the arch edge is body colour catching a highlight. A single dark strip
##      only ever reads as a horseshoe stencilled on the flank.
## Proudness eases to zero at both ends of the arc, so the arch dissolves into
## the fender instead of ending on a cut edge.
static func _arch_mesh(f: Dictionary, wy: float, wz: float, wr: float,
		tyre: float, sx: float, gap: float, amid: float, lipw: float) -> ArrayMesh:
	const ARC := 1.46                               # +-84 deg: a real opening
	const SEGN := 13
	# The DARK CUT runs from the tyre's clearance out to the arch's opening edge
	# (`gap`, a real dimension — see ARCH_GAP); the PAINTED lip runs `lipw` beyond
	# it. Getting the split wrong (M19 ran the dark band out to 1.175 wr) stencils
	# a black horseshoe on the fender instead of cutting a hole in it.
	var rs: Array[float] = [wr + ARCH_CLEAR, wr + amid, wr + gap, wr + gap + lipw]
	var pts: Array[PackedVector3Array] = []
	for k in SEGN:
		var ang := -ARC + (2.0 * ARC / float(SEGN - 1)) * float(k)
		var e := clampf((ARC - absf(ang)) / 0.36, 0.0, 1.0)
		e = e * e * (3.0 - 2.0 * e)
		var col := PackedVector3Array()
		for i in rs.size():
			var r: float = rs[i]
			var y := wy + cos(ang) * r
			var z := wz + sin(ang) * r
			var skin := _fx(f, y, z)
			var x := skin
			match i:
				# The throat is TUCKED INBOARD of the tyre's own face, so the arch
				# has depth behind its edge instead of being a ribbon laid on the
				# flank. It can never go inboard of the hull skin.
				0: x = maxf(skin, tyre - 0.018 * e)
				1: x = maxf(skin, tyre) + 0.003 * e
				2:
					# Proud of the local skin, but NEVER further outboard of the
					# tyre than the bar's ceiling allows (D-021).
					x = minf(maxf(skin, tyre) + LIP_PROUD * e, tyre + LIP_CAP)
					# The lip may not sink INTO the hull it is the edge of. This
					# line used to OVERRIDE the cap above (the whole of D-021
					# round two) because the Slab's skin was outboard of its own
					# tyre; BEAM_MAX now holds skin <= tyre + 0.018, so the worst
					# this can ask for is tyre + 0.020 and the cap always wins.
					x = maxf(x, skin + 0.002 * e)
				3: x = skin + 0.003
			col.append(Vector3(sx * x, y, z))
		pts.append(col)
	var mesh: ArrayMesh = null
	for band in 3:                # 0 = throat, 1 = lip in shadow, 2 = lip in light
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for k in SEGN - 1:
			var a: PackedVector3Array = pts[k]
			var b: PackedVector3Array = pts[k + 1]
			for i in range(band, band + 1):
				# The throat stays flat (it is a shadow); the lip rolls.
				st.set_smooth_group(-1 if band == 0 else 6 + band)
				if sx > 0.0:
					_q(st, a[i], b[i], b[i + 1], a[i + 1])
				else:
					_q(st, a[i], a[i + 1], b[i + 1], b[i])
		st.generate_normals()
		mesh = st.commit(mesh)
	return mesh


# ============================== DETAIL PASSES ================================
## Door seam grooves + the beltline shadow line, laid flush to the tumblehome.
static func _seams(p: Node3D, f: Dictionary, cuts: Array, top_y: float,
		bot_y: float, belt_len: float) -> void:
	var mat := _m("seam", SEAM, 0.8, 0.0)
	var mid := (top_y + bot_y) * 0.5
	for z: float in cuts:
		_flank(p, f, mid, z, Vector3(0.016, top_y - bot_y, 0.014), 0.002, mat, D_FINE)
	if cuts.size() > 0:
		var z0: float = float(cuts[0])
		_flank(p, f, bot_y + (top_y - bot_y) * 0.72, z0 + belt_len * 0.42,
			Vector3(0.016, 0.013, belt_len), 0.003, mat, D_FINE)


static func _handles(p: Node3D, f: Dictionary, y: float, zs: Array) -> void:
	var mat := _m("handle", Color(0.62, 0.63, 0.66), 0.28, 0.85)
	for z: float in zs:
		_flank(p, f, y, z, Vector3(0.030, 0.038, 0.155), 0.020, mat, D_FINE)


static func _wipers(p: Node3D, s: Vector3, z: float, y: float) -> void:
	var mat := _m("wiper", Color(0.06, 0.06, 0.065), 0.85, 0.0)
	for sx: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		arm.mesh = KIT.taper(Vector3(s.x * 0.34, 0.018, 0.026), Vector2(s.x * 0.34, 0.026))
		arm.material_override = mat
		arm.position = Vector3(sx * s.x * 0.17, y + 0.020, z)
		arm.rotation.y = sx * 0.20
		arm.visibility_range_end = D_FINE
		p.add_child(arm)


static func _fuel_door(p: Node3D, f: Dictionary, z: float, y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = KIT.taper(Vector3(0.020, 0.145, 0.155), Vector2(0.020, 0.155))
	mi.material_override = _m("fueldoor", Color(0.13, 0.13, 0.14), 0.5, 0.3)
	mi.position = Vector3(-(_fx(f, y, z) + 0.008), y, z)
	mi.rotation.z = _ftilt(f, -1.0, y, z)
	mi.visibility_range_end = D_FINE
	p.add_child(mi)


static func _exhaust(p: Node3D, _s: Vector3, xs: Array, z: float, y: float,
		r: float) -> void:
	for x: float in xs:
		_cyl(p, r, 0.13, Vector3(x, y, z), _m("chrome", CHROME, 0.19, 0.95), false, D_FINE, true)


static func _roof_fin(p: Node3D, z: float, y: float) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = KIT.taper(Vector3(0.055, 0.055, 0.16), Vector2(0.02, 0.09))
	mi.material_override = _m("sharkfin", Color(0.10, 0.10, 0.11), 0.55, 0.1)
	mi.position = Vector3(0, y, z)
	mi.visibility_range_end = D_FINE
	p.add_child(mi)


## A bumper that WRAPS. The M18 version was a full-width box: from a rear 3/4
## it read as a white plank nailed across a flat wall. This one is a taper laid
## on its side, so its outer face is narrower and shorter than its root — the
## ends turn the corner into the fender — and it is sized off the hull's own
## half-width at that height instead of a fraction of the collision box.
static func _bumper(p: Node3D, f: Dictionary, s: Vector3, z: float,
		hfrac: float, chrome: bool) -> void:
	var mat := _m("chrome", CHROME, 0.19, 0.95) if chrome else _m("bumper", TRIM, 0.6, 0.05)
	var sgn := signf(z)
	var y := -0.255 * s.y
	# NARROWER than the body, so the fender corners wrap around it the way they
	# do on a real car. M18's bumper was the full collision width and read as a
	# plank nailed across a wall.
	var root := _fx(f, y, z - sgn * 0.16) * 1.84
	var mi := MeshInstance3D.new()
	var bkey := "bump_%.3f_%.3f_%.1f" % [root, s.y * hfrac, sgn]
	var bmesh: ArrayMesh = _meshes.get(bkey)
	if bmesh == null:
		# BULGED, not flat: chrome only reads as chrome where the surface turns
		# under a highlight. A flat plate reflects one value and looks painted.
		bmesh = _dome(root, s.y * hfrac * 0.80, 0.105, 0.13, root * 0.70)
		_meshes[bkey] = bmesh
	mi.mesh = bmesh
	mi.material_override = mat
	mi.position = Vector3(0, y, z + sgn * 0.022)
	mi.rotation.x = sgn * PI * 0.5
	p.add_child(mi)
	# Valance below it: the tuck-under that stops a tail being a wall.
	var val := MeshInstance3D.new()
	val.mesh = KIT.taper(Vector3(root * 0.86, 0.10, s.y * 0.070),
		Vector2(root * 0.58, s.y * 0.045))
	val.material_override = _m("valance", Color(0.09, 0.09, 0.10), 0.8, 0.0)
	val.position = Vector3(0, -0.372 * s.y, z - sgn * 0.038)
	val.rotation.x = sgn * PI * 0.5
	val.visibility_range_end = D_MID
	p.add_child(val)
	_box(p, Vector3(0.34, 0.145, 0.028), Vector3(0, -0.300 * s.y, z + sgn * 0.100), _m("plate", PLATE, 0.7, 0.0))


static func _grille(p: Node3D, s: Vector3, y: float, wfrac: float, hfrac: float,
		chrome: bool) -> void:
	var mat := _m("chrome", CHROME, 0.19, 0.95) if chrome else _m("grille", Color(0.055, 0.055, 0.065), 0.5, 0.3)
	_box(p, Vector3(s.x * wfrac, s.y * hfrac, 0.055), Vector3(0, y, -s.z * 0.5 - 0.012), mat)
	for i in 3:
		_box(p, Vector3(s.x * wfrac * 0.94, s.y * hfrac * 0.13, 0.03),
			Vector3(0, y + (float(i) - 1.0) * s.y * hfrac * 0.30, -s.z * 0.5 - 0.036),
			_m("slat", Color(0.16, 0.16, 0.17), 0.4, 0.6), D_FINE)


# ------------------------------ lamp clusters --------------------------------
## Sunbelt Vantage / Interceptor: wide low headlamps with an amber corner that
## wraps onto the fender; tails are a red bar with a white reverse inboard.
static func _lamps_sedan(p: Node3D, s: Vector3, cop: bool) -> void:
	var w := s.x
	var h := s.y
	var l := s.z
	var fz := -l * 0.5 - 0.014
	var rz := l * 0.5 + 0.014
	for sx: float in [-1.0, 1.0]:
		_lamp(p, Vector3(w * 0.24, h * 0.075, 0.05), Vector3(sx * w * 0.29, -0.055 * h, fz), HEADLIGHT, 1.8, "headlight", D_FAR)
		_lamp(p, Vector3(w * 0.085, h * 0.055, 0.05), Vector3(sx * w * 0.155, -0.070 * h, fz), HEADLIGHT, 1.5, "headlight_lo", D_FINE)
		_lamp(p, Vector3(w * 0.055, h * 0.055, 0.045), Vector3(sx * w * 0.405, -0.050 * h, fz + 0.006), AMBER, 1.2, "amber", D_FINE)
		# Tail: red main, white reverse inboard, amber turn outboard.
		_lamp(p, Vector3(w * 0.15, h * 0.085, 0.05), Vector3(sx * w * 0.315, -0.005 * h, rz), TAILLIGHT, 1.5, "taillight", D_FAR)
		_lamp(p, Vector3(w * 0.075, h * 0.075, 0.045), Vector3(sx * w * 0.195, -0.005 * h, rz), Color(0.92, 0.93, 0.95), 0.7, "reverse", D_FINE)
		_lamp(p, Vector3(w * 0.06, h * 0.075, 0.045), Vector3(sx * w * 0.408, -0.005 * h, rz), AMBER, 1.0, "amber", D_FINE)
	if cop:
		return
	_box(p, Vector3(w * 0.30, h * 0.020, 0.03), Vector3(0, -0.060 * h, rz), _m("reflector", Color(0.34, 0.05, 0.05), 0.4, 0.1), D_FINE)


## Baron Brisket: big stacked square lamps in chrome bezels, tall vertical
## tails on the bed corners.
static func _lamps_truck(p: Node3D, s: Vector3) -> void:
	var w := s.x
	var h := s.y
	var l := s.z
	var fz := -l * 0.5 - 0.016
	var rz := l * 0.5 + 0.016
	var chrome := _m("chrome", CHROME, 0.19, 0.95)
	for sx: float in [-1.0, 1.0]:
		_box(p, Vector3(w * 0.25, h * 0.145, 0.035), Vector3(sx * w * 0.315, -0.030 * h, fz + 0.006), chrome)
		_lamp(p, Vector3(w * 0.205, h * 0.075, 0.05), Vector3(sx * w * 0.315, -0.004 * h, fz), HEADLIGHT, 1.8, "headlight", D_FAR)
		_lamp(p, Vector3(w * 0.205, h * 0.040, 0.05), Vector3(sx * w * 0.315, -0.070 * h, fz), AMBER, 1.1, "amber", D_FINE)
		_lamp(p, Vector3(w * 0.055, h * 0.05, 0.04), Vector3(sx * w * 0.452, -0.010 * h, fz + 0.010), AMBER, 1.1, "amber", D_FINE)
		_lamp(p, Vector3(w * 0.10, h * 0.185, 0.05), Vector3(sx * w * 0.375, 0.010 * h, rz), TAILLIGHT, 1.5, "taillight", D_FAR)
		_lamp(p, Vector3(w * 0.10, h * 0.045, 0.045), Vector3(sx * w * 0.375, -0.105 * h, rz), Color(0.92, 0.93, 0.95), 0.7, "reverse", D_FINE)


## Longhorn Wrecker: round lamps in chrome buckets, amber corner markers, and
## a stacked red-over-amber-over-white trailer cluster on the rear post.
static func _lamps_wrecker(p: Node3D, s: Vector3) -> void:
	var w := s.x
	var h := s.y
	var l := s.z
	var fz := -l * 0.5 - 0.014
	var chrome := _m("chrome", CHROME, 0.19, 0.95)
	for sx: float in [-1.0, 1.0]:
		_cyl(p, h * 0.10, 0.05, Vector3(sx * w * 0.30, -0.040 * h, fz + 0.012), chrome, false, D_FAR, true)
		var lens := MeshInstance3D.new()
		lens.mesh = KIT.prism(h * 0.078, 0.05, 14)
		lens.material_override = _emis("headlight", HEADLIGHT, 1.8)
		lens.position = Vector3(sx * w * 0.30, -0.040 * h, fz)
		lens.rotation.x = PI * 0.5
		p.add_child(lens)
		_lamp(p, Vector3(w * 0.06, h * 0.05, 0.04), Vector3(sx * w * 0.442, -0.030 * h, fz + 0.008), AMBER, 1.2, "amber", D_FINE)
		_lamp(p, Vector3(w * 0.11, h * 0.065, 0.045), Vector3(sx * w * 0.36, -0.215 * h, l * 0.510), TAILLIGHT, 1.5, "taillight", D_FAR)
		_lamp(p, Vector3(w * 0.11, h * 0.045, 0.045), Vector3(sx * w * 0.36, -0.290 * h, l * 0.510), AMBER, 1.1, "amber", D_FINE)
		_lamp(p, Vector3(w * 0.11, h * 0.040, 0.045), Vector3(sx * w * 0.36, -0.350 * h, l * 0.510), Color(0.92, 0.93, 0.95), 0.7, "reverse", D_FINE)


## Candyland Slab: quad round headlamps in chrome, a full-width tail bar.
static func _lamps_slab(p: Node3D, s: Vector3) -> void:
	var w := s.x
	var h := s.y
	var l := s.z
	var fz := -l * 0.5 - 0.014
	var rz := l * 0.5 + 0.016
	var chrome := _m("chrome", CHROME, 0.19, 0.95)
	for sx: float in [-1.0, 1.0]:
		_box(p, Vector3(w * 0.24, h * 0.115, 0.035), Vector3(sx * w * 0.30, -0.020 * h, fz + 0.008), chrome)
		for k: float in [-1.0, 1.0]:
			var lens := MeshInstance3D.new()
			lens.mesh = KIT.prism(h * 0.052, 0.05, 12)
			lens.material_override = _emis("headlight", HEADLIGHT, 1.8)
			lens.position = Vector3(sx * w * 0.30 + k * w * 0.058, -0.020 * h, fz)
			lens.rotation.x = PI * 0.5
			p.add_child(lens)
		_lamp(p, Vector3(w * 0.05, h * 0.06, 0.04), Vector3(sx * w * 0.446, -0.010 * h, fz + 0.010), AMBER, 1.2, "amber", D_FINE)
		_lamp(p, Vector3(w * 0.075, h * 0.055, 0.045), Vector3(sx * w * 0.20, 0.030 * h, rz + 0.008), Color(0.92, 0.93, 0.95), 0.7, "reverse", D_FINE)
	# Full-width tail bar between chrome ribs — the boulevard signature.
	_lamp(p, Vector3(w * 0.86, h * 0.075, 0.05), Vector3(0, 0.030 * h, rz), TAILLIGHT, 1.5, "taillight", D_FAR)
	_box(p, Vector3(w * 0.90, h * 0.022, 0.055), Vector3(0, 0.076 * h, rz + 0.004), chrome, D_MID)
	_box(p, Vector3(w * 0.90, h * 0.022, 0.055), Vector3(0, -0.016 * h, rz + 0.004), chrome, D_MID)


# ------------------------------ mirrors / badges -----------------------------
## Door mirrors: they belong at the BELTLINE just aft of the A-pillar. The
## first M16 draft hung them low on the front fender, where they read as black
## scoops bolted to the wing.
static func _mirrors(p: Node3D, f: Dictionary, y: float, z: float) -> void:
	var shell := _m("mirrorshell", Color(0.10, 0.10, 0.11), 0.55, 0.15)
	var face := _m("mirrorface", Color(0.62, 0.68, 0.74), 0.10, 0.90)
	var x := _fx(f, y, z)
	for sx: float in [-1.0, 1.0]:
		_box(p, Vector3(0.055, 0.020, 0.038), Vector3(sx * (x + 0.030), y, z), shell, D_MID)
		_box(p, Vector3(0.038, 0.072, 0.100), Vector3(sx * (x + 0.072), y + 0.016, z), shell, D_MID)
		_box(p, Vector3(0.012, 0.054, 0.078), Vector3(sx * (x + 0.094), y + 0.016, z - 0.003), face, D_MID)


## Model name on the decklid, §7a canon — the JSON `name` is the only source.
static func _badge(p: Node3D, s: Vector3, text: String, style: String) -> void:
	if text == "" or style == "wrecker":
		return                             # the door livery IS the wrecker's badge
	var y := -0.10 * s.y
	if style == "pickup":
		y = -0.16 * s.y
	elif style == "slab":
		y = 0.108 * s.y
	var lbl := Label3D.new()
	lbl.double_sided = false   # D-016: cull the mirrored back face
	lbl.text = text.to_upper()
	lbl.font_size = 44
	lbl.pixel_size = 0.0022
	lbl.modulate = Color(0.86, 0.87, 0.90)
	lbl.outline_size = 6
	lbl.outline_modulate = Color(0, 0, 0, 0.7)
	lbl.position = Vector3(0, y, s.z * 0.5 + 0.032)
	lbl.visibility_range_end = D_FINE
	p.add_child(lbl)


static func _plate_text(p: Node3D, s: Vector3, text: String) -> void:
	if text == "":
		return
	for e: float in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.double_sided = false   # D-016: cull the mirrored back face
		lbl.text = text
		lbl.font_size = 48
		lbl.pixel_size = 0.0026
		lbl.modulate = Color(0.14, 0.16, 0.30)
		lbl.position = Vector3(0, -0.300 * s.y, e * (s.z * 0.5 + 0.072))
		lbl.rotation.y = 0.0 if e > 0.0 else PI
		lbl.visibility_range_end = D_FINE
		p.add_child(lbl)


## Door livery. `f` (not the collision width) places it: the hull is clamped to
## the track by BEAM_INSET, so `size.x * 0.5` is no longer the flank — on the
## wrecker that difference is 48 mm and the lettering would have floated off the
## door it is painted on.
static func _door(root: Node3D, text: String, f: Dictionary, y: float,
		z: float) -> void:
	if text == "":
		return
	var w := _fx(f, y, z) * 2.0
	for s: float in [-1.0, 1.0]:
		var lbl := Label3D.new()
		lbl.double_sided = false   # D-016: cull the mirrored back face
		lbl.text = text
		lbl.font_size = mini(56, int(1.6 / (float(maxi(text.length(), 1)) * 0.66 * 0.004)))
		lbl.pixel_size = 0.004
		lbl.modulate = Color(0.96, 0.9, 0.75)
		lbl.outline_size = 8
		lbl.outline_modulate = Color(0, 0, 0, 0.85)
		lbl.position = Vector3(s * (w * 0.5 + 0.02), y, z)
		# D-016: this was -s, which pointed BOTH door liveries INTO the body —
		# so every flank showed the mirrored reverse face (`YREVOCER & REKCERW`
		# on the wrecker, QA cycle 1 `car_side`). Label3D faces +Z at yaw 0, so
		# the +X flank needs +PI/2 and the -X flank -PI/2.
		lbl.rotation.y = s * PI * 0.5
		root.add_child(lbl)


# ============================== PLUMBING =====================================
static func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3,
		mat: Material, cull := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if cull > 0.0:
		mi.visibility_range_end = cull
	parent.add_child(mi)
	return mi


static func _box(parent: Node3D, size: Vector3, pos: Vector3,
		mat: Material, cull := 0.0) -> void:
	_mesh(parent, KIT.taper(size, Vector2(size.x, size.z)), pos, mat, cull)


static func _lamp(parent: Node3D, size: Vector3, pos: Vector3, c: Color,
		energy: float, key: String, cull := 0.0) -> void:
	_mesh(parent, KIT.taper(size, Vector2(size.x, size.z)), pos, _emis(key, c, energy), cull)


static func _cyl(parent: Node3D, r: float, hgt: float, pos: Vector3,
		mat: Material, lay_flat := false, cull := 0.0,
		face_z := false) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = KIT.prism(r, hgt, 18)
	mi.material_override = mat
	mi.position = pos
	if lay_flat:
		mi.rotation.z = PI * 0.5
	elif face_z:
		mi.rotation.x = PI * 0.5
	if cull > 0.0:
		mi.visibility_range_end = cull
	parent.add_child(mi)


## Ordinary body paint. The shader arm adds the second specular lobe a real car
## has: a clear lacquer over the pigment with its own, much tighter roughness.
## That is what "a tight bright highlight riding on a broad soft one" IS, and no
## single-lobe StandardMaterial3D produces it at any roughness value. Flake stays
## low here — these are fleet sedans, not the Slab.
static func _paint(c: Color) -> Material:
	if SHD.legacy():
		return _m("paint_%s" % c.to_html(false), c, 0.42, 0.2)
	var key := "shpaint_%s" % c.to_html(false)
	if not _mats.has(key):
		_mats[key] = SHD.paint_material(c, 0.34, 0.12, 0.55, 0.18)
	return _mats[key]


## Slab candy paint — the one place this project already reached for clearcoat
## (the only `clearcoat_enabled` in the whole codebase). The shader arm keeps
## that and adds the heavy metalflake a candy job actually has, which a
## StandardMaterial3D cannot do without a flake texture the doctrine forbids.
static func _candy(c: Color) -> Material:
	var key := "candy_%s" % c.to_html(false)
	if not _mats.has(key):
		if SHD.legacy():
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.1
			m.metallic = 0.7
			m.clearcoat_enabled = true
			m.clearcoat = 0.9
			_mats[key] = m
		else:
			_mats[key] = SHD.paint_material(c, 0.14, 0.52, 0.95, 0.46)
	return _mats[key]


static func _m(key: String, c: Color, rough: float, metal: float) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.roughness = rough
		m.metallic = metal
		_mats[key] = m
	return _mats[key]


## Alpha glass. Without this the greenhouse is a painted shell and every
## interior in this file is invisible — the whole point of the M16 pass.
static func _glass(key: String, c: Color) -> Material:
	if not _mats.has(key):
		if SHD.legacy():
			var m := StandardMaterial3D.new()
			m.albedo_color = c
			m.roughness = 0.12
			m.metallic = 0.0
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			_mats[key] = m
		else:
			# D-039 fixed the metallic half of this and left the other half: a
			# CONSTANT alpha. Real glass is not 34% transparent from every angle —
			# it is see-through head-on and a mirror at the edge, and that ramp is
			# what makes a windscreen read as glass rather than tinted plastic.
			# Head-on transmission is preserved exactly, so the cabins D-039
			# fought for stay visible.
			_mats[key] = SHD.glass_material(Color(c.r, c.g, c.b, 1.0), c.a, 0.05)
	return _mats[key]


static func _emis(key: String, c: Color, energy: float) -> StandardMaterial3D:
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = energy
		_mats[key] = m
	return _mats[key]
