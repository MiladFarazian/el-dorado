extends Node3D
## LANDMARKS (M16) — the metro gets four structures a player can navigate by:
##   1. OVERFLOW FELLOWSHIP flagship campus  (~x 140,  z 720) — naming bible §8
##   2. RUSTLERS STADIUM / Colt Bidwell Field (~x 640,  z 782) — §7/§8 (name
##      flagged for ratification in the M16 report; team + owner are canon)
##   3. GIGASTEAD compute-ranch campus        (~x -260, z 480) — §6/§8
##   4. MIDDLINGTON municipal water tower     (~x -300, z -140) — §2
##
## CONTRACT (Building Designer house law): static collision IS carried by these
## structures, but ONLY on the four pre-approved empty prairie sites above —
## all verified clear of the smoke corridor (x 174..212, z 424..576), streets,
## freeway/ramps/frontage, the race channel, the suburb rect (z <= -180), the
## hospital campus (x 339..391), and >= 25 m from every hazard-box coordinate
## in greybox_city._build_edge_and_flavor. Zero draws from any seeded stream:
## one fresh RNG with a literal seed, used for cosmetic jitter only.
## Repeated elements are MultiMeshes; unique elements are cheap nodes; text is
## Label3D under the measured-glyph fit law; emission colors ride materials
## with NO texture (legal); every rotated scaled transform uses
## rot * Basis.from_scale(). Built once in build(); no _process.

const RNG_SEED := 616161

const TEX := preload("res://scripts/world/city_textures.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")
const MESH_KIT := preload("res://scripts/world/mesh_kit.gd")
const SIGN := preload("res://scripts/world/sign_kit.gd")

# -- Palette ------------------------------------------------------------------
const STEEL := Color(0.24, 0.26, 0.28)
const GALV := Color(0.58, 0.61, 0.63)
const PAINT_WHITE := Color(0.88, 0.88, 0.86)
const NAVY := Color(0.10, 0.15, 0.30)          # Rustlers team navy
const SILVER := Color(0.72, 0.74, 0.78)        # Rustlers team silver
const STUCCO := Color(0.80, 0.76, 0.68)        # megachurch tilt-wall tan
const BARN_DARK := Color(0.27, 0.28, 0.31)     # GigaStead panel charcoal
const TOWER_CREAM := Color(0.87, 0.87, 0.83)   # water-tower municipal cream

var _rng := RandomNumberGenerator.new()
var _city: Node3D = null
var _mesh_cache: Dictionary = {}
var _unit_box := BoxMesh.new()

# Shared city materials (triplanar, built once by greybox_city).
var _mat_asphalt: Material
var _mat_concrete: Material

# -- MultiMesh accumulators (flushed once at the end of build) ----------------
var _white_xf: Array[Transform3D] = []         # stall/lane paint (unshaded)
var _yellow_xf: Array[Transform3D] = []        # helipad ring / hazard paint
var _steel_xf: Array[Transform3D] = []         # poles, frames, sign posts
var _galv_xf: Array[Transform3D] = []          # fence posts, catwalk, rails
var _navy_xf: Array[Transform3D] = []          # stadium trim + banners
var _silver_xf: Array[Transform3D] = []        # stadium silver band
var _bowl_xf: Array[Transform3D] = []          # stadium wall segments (taper)
var _bowl_col: Array[Color] = []
var _rib_xf: Array[Transform3D] = []           # barn pilasters / arena ribs
var _stack_xf: Array[Transform3D] = []         # cooling stacks (prism)
var _ac_xf: Array[Transform3D] = []            # rooftop mechanicals
var _wire_xf: Array[Transform3D] = []          # fence mesh runs + barb rows
var _flood_xf: Array[Transform3D] = []         # floodlight heads (emissive)
var _beacon_xf: Array[Transform3D] = []        # red aircraft beacons
var _bollard_xf: Array[Transform3D] = []       # plaza bollards (prism)
var _porta_xf: Array[Transform3D] = []         # porta-potty bodies
var _porta_door_xf: Array[Transform3D] = []    # porta-potty door panels
var _hedge_xf: Array[Transform3D] = []         # landscaping hedges
var _planter_xf: Array[Transform3D] = []       # concrete planters
var _trunk_xf: Array[Transform3D] = []         # tree trunks (round_limb)
var _canopy_xf: Array[Transform3D] = []        # tree canopies (sphere)
var _canopy_col: Array[Color] = []
var _doorglass_xf: Array[Transform3D] = []     # lit entry glass (doors!)
var _frame_xf: Array[Transform3D] = []         # dark door/window frames
var _panel_white_xf: Array[Transform3D] = []   # small white sign panels
var _jet_white_xf: Array[Transform3D] = []     # Blessing One airframe


func build(city: Node3D) -> void:
	_city = city
	_rng.seed = RNG_SEED
	_unit_box.size = Vector3.ONE
	_mat_asphalt = city.get("mat_asphalt")
	_mat_concrete = city.get("mat_concrete")
	_overflow_fellowship()
	_rustlers_stadium()
	_gigastead()
	_middlington_tower()
	_flush()


# ======================= 1. OVERFLOW FELLOWSHIP ==============================
## The 12-campus prosperity juggernaut's flagship: a curved-roof arena church,
## a parking ocean with painted stalls, a landscaped entry drive off the
## downtown street bed, a monument marquee, glass doors that read as doors,
## and Blessing One waiting on its pad. Satire is institutional (the app, the
## jet, the marquee copy) — never theological.
func _overflow_fellowship() -> void:
	# Grounds: entry drive from the street bed (z 566), campus lot, entry plaza.
	_solid(Vector3(28, 0.08, 76), Vector3(142, -0.02, 603), _mat_asphalt)
	_solid(Vector3(205, 0.08, 160), Vector3(142.5, 0.0, 695), _mat_asphalt)
	_solid(Vector3(48, 0.08, 66), Vector3(142, 0.03, 671), _mat_concrete)
	# Arena: one smooth loft — vertical walls into a curved crown (mesh kit).
	var stucco := _flat(STUCCO, false)
	stucco.roughness = 0.8
	var profile := PackedVector2Array([Vector2(-32, 0), Vector2(32, 0),
		Vector2(32, 12), Vector2(26, 17.5), Vector2(12, 21.5),
		Vector2(-12, 21.5), Vector2(-26, 17.5), Vector2(-32, 12)])
	var arena := MeshInstance3D.new()
	arena.mesh = MESH_KIT.loft(profile, 64.0, 46.0, "ovf_arena", true)
	arena.material_override = stucco
	arena.position = Vector3(142, 0.04, 735)
	add_child(arena)
	_collider(Vector3(64, 12, 64), Vector3(142, 6.04, 735))
	_collider(Vector3(46, 9.5, 46), Vector3(142, 16.5, 735))
	# Front fascia band + name across the face (north face at z 703).
	_rib_xf.append(_axf(Vector3(40, 2.6, 0.7), Vector3(142, 10.6, 702.9)))
	# The fascia band is 40 x 2.6; the old fit used 59 % of its width because
	# it was solving for a width the letters never needed. Height-led now, in
	# CHANNEL: the lit letters a 12-campus church bolts to its arena face.
	_label("OVERFLOW FELLOWSHIP", Vector3(142, 10.6, 702.4), 260,
		Color(0.95, 0.83, 0.45), 37.6, PI, SIGN.CHANNEL, 2.10)
	# Entry: six glass door leafs in dark frames, proud of the wall, warm-lit
	# (the interactivity promise — these read as doors you will someday open).
	for k in 6:
		var dx := 142.0 - 8.75 + 3.5 * float(k)
		_frame_xf.append(_axf(Vector3(3.0, 4.4, 0.3), Vector3(dx, 2.2, 702.9)))
		_doorglass_xf.append(_axf(Vector3(2.5, 3.9, 0.34), Vector3(dx, 2.05, 702.82)))
	# Canopy over the doors on four posts.
	_rib_xf.append(_axf(Vector3(26, 0.5, 7), Vector3(142, 5.6, 699.6)))
	for px: float in [-11.0, 11.0]:
		for pz: float in [697.0, 701.5]:
			_steel_xf.append(_axf(Vector3(0.3, 5.4, 0.3), Vector3(142 + px, 2.7, pz)))
	# Steeple: cross-free spire — shaft, belt, tapered needle, gilded orb.
	_solid(Vector3(4.4, 1.2, 4.4), Vector3(184, 0.6, 714), _mat_concrete)
	var shaft := MeshInstance3D.new()
	shaft.mesh = MESH_KIT.prism(1.7, 30.0, 8)
	shaft.material_override = _flat(Color(0.9, 0.88, 0.82), false)
	shaft.position = Vector3(184, 16.2, 714)
	add_child(shaft)
	var needle := MeshInstance3D.new()
	needle.mesh = MESH_KIT.taper(Vector3(3.2, 9.0, 3.2), Vector2(0.2, 0.2))
	needle.material_override = _flat(Color(0.82, 0.8, 0.74), false)
	needle.position = Vector3(184, 35.7, 714)
	add_child(needle)
	var orb := MeshInstance3D.new()
	orb.mesh = MESH_KIT.sphere(0.5, 6, 10)
	var gold := _flat(Color(0.85, 0.68, 0.25), false)
	gold.metallic = 0.85
	gold.roughness = 0.25
	orb.material_override = gold
	orb.scale = Vector3(1.7, 1.7, 1.7)
	orb.position = Vector3(184, 40.9, 714)
	add_child(orb)
	_collider(Vector3(3.6, 40, 3.6), Vector3(184, 20.6, 714))
	# Monument marquee at the drive mouth, readable both ways.
	# A church marquee is the single best joke surface in the world and this one
	# was reading like a lobby directory. It now does what a real one does:
	# brand, sermon series, and the week's one operational notice. "Blessed &
	# Zoned" is the canon sermon-series title (bible §11); the Watchmen are the
	# canon parking-and-security ministry (§8), which is why parking is one.
	_marquee(Vector3(168, 0, 652),
		["OVERFLOW FELLOWSHIP", "SERIES: BLESSED & ZONED",
			"OVERFLOW PARKING IS A MINISTRY"],
		["OVERFLOW FELLOWSHIP", "THE OVERFLOW HOUR · KSOL",
			"SOW EARLY · THE LOT FILLS AT 8"],
		Color(0.95, 0.83, 0.45))
	# Landscaped entry: hedges + planters + crepe-myrtle-ish trees on the drive.
	for hz in 5:
		var z := 644.0 + 12.0 * float(hz)
		_hedge_xf.append(_axf(Vector3(1.0, 0.9, 7.0), Vector3(117.4, 0.5, z)))
		_hedge_xf.append(_axf(Vector3(1.0, 0.9, 7.0), Vector3(166.6, 0.5, z)))
	for pxx: float in [128.0, 156.0]:
		_planter_xf.append(_axf(Vector3(2.2, 0.8, 2.2), Vector3(pxx, 0.45, 699.5)))
	for t in 6:
		var tx := 123.0 if t % 2 == 0 else 161.0
		_tree(Vector3(tx, 0.05, 622.0 + 13.0 * float(t)))
	# Parking ocean: two painted lots flanking the plaza. West rows skip the
	# helipad; the steeple block interrupts nothing east of x 198.
	_stall_rows(46.0, 112.0, 628.0, 764.0, 17.0, Vector2(60.0, 745.0), 14.0)
	_stall_rows(198.0, 242.0, 628.0, 764.0, 17.0, Vector2.ZERO, 0.0)
	for lp in 4:
		_lot_light(Vector3(80.0 + 0.0 * float(lp), 0, 640.0 + 34.0 * float(lp)))
		_lot_light(Vector3(220.0, 0, 640.0 + 34.0 * float(lp)))
	# Helipad + BLESSING ONE (the jet is the sermon).
	var pad := MeshInstance3D.new()
	pad.mesh = MESH_KIT.prism(7.5, 0.22, 16)
	pad.material_override = _flat(Color(0.3, 0.31, 0.33), false)
	pad.position = Vector3(60, 0.16, 745)
	add_child(pad)
	for r in 12:
		var a := TAU * float(r) / 12.0
		_yellow_xf.append(Transform3D(
			Basis(Vector3.UP, -a) * Basis.from_scale(Vector3(1.6, 0.02, 0.24)),
			Vector3(60 + cos(a) * 5.6, 0.3, 745 + sin(a) * 5.6)))
	_blessing_one(Vector3(60, 0.28, 745), -0.5)


## Head-in stall paint between x0..x1, double-loaded rows every `pitch` in z,
## skipping lines within `skip_r` of `skip` (the helipad carve-out).
func _stall_rows(x0: float, x1: float, z0: float, z1: float, pitch: float,
		skip: Vector2, skip_r: float) -> void:
	var z := z0
	while z <= z1:
		var x := x0
		while x <= x1:
			if skip_r <= 0.0 or Vector2(x, z).distance_to(skip) > skip_r:
				_white_xf.append(_axf(Vector3(0.14, 0.02, 5.4), Vector3(x, 0.09, z)))
			x += 2.75
		z += pitch


func _lot_light(base: Vector3) -> void:
	_steel_xf.append(_axf(Vector3(0.28, 9.0, 0.28), base + Vector3(0, 4.5, 0)))
	_flood_xf.append(_axf(Vector3(1.6, 0.3, 0.6), base + Vector3(0, 9.1, 0)))


## Blessing One: a bizjet silhouette in white and gold, parked on the pad.
func _blessing_one(pos: Vector3, yaw: float) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var lay := rot * Basis(Vector3(0, 0, 1), -PI * 0.5)  # +Y limb axis -> +X
	var jet := pos + Vector3(0, 1.35, 0)
	# Fuselage: nose limb + tail limb laid horizontal along local +X.
	_jet_white_xf.append(Transform3D(lay * Basis.from_scale(Vector3(1.7, 5.4, 1.7)),
		jet + rot * Vector3(2.6, 0, 0)))
	_jet_white_xf.append(Transform3D(
		lay * Basis(Vector3.UP, PI) * Basis.from_scale(Vector3(1.7, 4.6, 1.4)),
		jet + rot * Vector3(-2.4, 0, 0)))
	# Wings: thin swept slabs; tail plane + fin; two aft engine pods.
	for side: float in [-1.0, 1.0]:
		_jet_white_xf.append(Transform3D(
			rot * Basis(Vector3.UP, side * 0.5) * Basis.from_scale(Vector3(4.8, 0.16, 1.5)),
			jet + rot * Vector3(0.3, -0.5, side * 2.6)))
		_jet_white_xf.append(Transform3D(
			rot * Basis(Vector3.UP, side * 0.6) * Basis.from_scale(Vector3(1.9, 0.12, 0.8)),
			jet + rot * Vector3(-4.3, 1.5, side * 1.1)))
		_jet_white_xf.append(Transform3D(rot * Basis.from_scale(Vector3(1.6, 0.9, 0.7)),
			jet + rot * Vector3(-2.9, 0.35, side * 1.35)))
	_jet_white_xf.append(Transform3D(
		rot * Basis(Vector3(0, 0, 1), 0.35) * Basis.from_scale(Vector3(1.6, 2.4, 0.16)),
		jet + rot * Vector3(-4.6, 1.0, 0)))
	# Gold belt stripe + name on both flanks (the fit law caps the font).
	for side: float in [-1.0, 1.0]:
		_yellow_xf.append(Transform3D(rot * Basis.from_scale(Vector3(6.5, 0.14, 0.05)),
			jet + rot * Vector3(0.6, 0.25, side * 0.86)))
		_label("BLESSING ONE", jet + rot * Vector3(0.6, 0.62, side * 0.9), 40,
			Color(0.72, 0.58, 0.2), 4.2, yaw + (0.0 if side > 0.0 else PI))


# ========================= 2. RUSTLERS STADIUM ===============================
## The cathedral of decline: a leaning superellipse bowl in precast tan with
## navy-and-silver trim, four labeled gates, the marquee over Gate A, corner
## floodlight masts, a bollarded entry plaza and a painted tailgate lot.
const STAD_C := Vector2(640.0, 782.0)   # bowl centre
const STAD_A := 68.0                    # x semi-axis
const STAD_B := 82.0                    # z semi-axis
const SEGS := 36


func _rustlers_stadium() -> void:
	# Bowl: 36 outward-leaning taper segments on the ellipse, one MultiMesh.
	var seg_mesh := MESH_KIT.taper(Vector3(13.8, 23.0, 9.0), Vector2(13.8, 7.0),
		Vector2(0.0, 2.2))
	for i in SEGS:
		var th := TAU * float(i) / float(SEGS)
		var p := Vector3(STAD_C.x + STAD_A * cos(th), 11.54, STAD_C.y + STAD_B * sin(th))
		var t := Vector3(-STAD_A * sin(th), 0.0, STAD_B * cos(th)).normalized()
		var yaw := atan2(-t.z, t.x)
		var out := Vector3(t.z, 0.0, -t.x)
		var rot := Basis(Vector3.UP, yaw)
		_bowl_xf.append(Transform3D(rot, p))
		var v := _rng.randf_range(0.94, 1.03)
		_bowl_col.append(Color(0.78 * v, 0.75 * v, 0.70 * v).srgb_to_linear())
		# Team-color crown rings ride the same lean.
		_navy_xf.append(Transform3D(rot * Basis.from_scale(Vector3(13.9, 1.6, 0.9)),
			p + out * 2.2 + Vector3(0, 11.3, 0)))
		_silver_xf.append(Transform3D(rot * Basis.from_scale(Vector3(13.9, 0.9, 0.8)),
			p + out * 2.05 + Vector3(0, 9.9, 0)))
		_collider_rot(Vector3(14.0, 23.0, 9.0), p, yaw)
	# The stadium bowl is the district's nameable structure — it casts.
	_mm(_bowl_xf, _bowl_col, _vtx_mat(), seg_mesh, "LmBowl", true)
	_bowl_xf = []
	_bowl_col = []
	# Grounds: entry plaza (north, camera side) + tailgate lot (west).
	_solid(Vector3(100, 0.08, 22), Vector3(640, 0.0, 701), _mat_concrete)
	_solid(Vector3(94, 0.08, 168), Vector3(515, -0.02, 780), _mat_asphalt)
	_stall_rows(472.0, 558.0, 708.0, 852.0, 18.0, Vector2.ZERO, 0.0)
	for lp in 3:
		_lot_light(Vector3(486.0 + 34.0 * float(lp), 0, 712.0))
		_lot_light(Vector3(486.0 + 34.0 * float(lp), 0, 848.0))
	for b in 10:
		_bollard_xf.append(_axf(Vector3(1, 1, 1), Vector3(602.0 + 8.4 * float(b), 0.55, 692.0)))
	# Four gates (A north — the marquee gate — then clockwise B east, C south,
	# D west), each a proud portal with recessed doors: gates that could open.
	_stadium_gate(Vector3(640, 0, 700), 0.0, Vector3(0, 0, -1), "GATE A", true)
	_stadium_gate(Vector3(708, 0, 782), PI * 0.5, Vector3(1, 0, 0), "GATE B", false)
	_stadium_gate(Vector3(640, 0, 864), 0.0, Vector3(0, 0, 1), "GATE C", false)
	_stadium_gate(Vector3(572, 0, 782), PI * 0.5, Vector3(-1, 0, 0), "GATE D", false)
	# Box office west of Gate A.
	_solid(Vector3(6, 3.4, 4), Vector3(612, 1.74, 695), _mat_concrete)
	_frame_xf.append(_axf(Vector3(3.6, 1.4, 0.3), Vector3(612, 1.9, 692.9)))
	_label("BOX OFFICE", Vector3(612, 3.0, 692.8), 40, PAINT_WHITE, 5.0, PI,
		SIGN.STENCIL, 0.42)
	# Corner floodlight masts with banks aimed into the bowl + red beacons.
	for th: float in [PI * 0.25, PI * 0.75, PI * 1.25, PI * 1.75]:
		var mp := Vector3(STAD_C.x + STAD_A * 1.15 * cos(th), 0.0,
			STAD_C.y + STAD_B * 1.15 * sin(th))
		var mast := MeshInstance3D.new()
		mast.mesh = MESH_KIT.prism(0.8, 30.0, 8)
		mast.material_override = _flat(STEEL, false)
		mast.position = mp + Vector3(0, 15, 0)
		add_child(mast)
		_collider(Vector3(1.8, 30, 1.8), mp + Vector3(0, 15, 0))
		var to_c := Vector3(STAD_C.x - mp.x, 0.0, STAD_C.y - mp.z).normalized()
		var byaw := atan2(to_c.x, to_c.z)
		var brot := Basis(Vector3.UP, byaw) * Basis(Vector3(1, 0, 0), -0.6)
		_flood_xf.append(Transform3D(brot * Basis.from_scale(Vector3(6.0, 4.0, 0.5)),
			mp + Vector3(0, 31.6, 0) + to_c * 0.8))
		_beacon_xf.append(_axf(Vector3(0.3, 0.3, 0.3), mp + Vector3(0, 34.3, 0)))
	# Tailgate clutter: porta-potty rank + dumpsters along the lot's east edge.
	for pp in 12:
		var pz := 742.0 + 2.1 * float(pp)
		_porta_xf.append(_axf(Vector3(1.2, 2.3, 1.2), Vector3(566.0, 1.2, pz)))
		_porta_door_xf.append(_axf(Vector3(0.06, 1.9, 0.8), Vector3(565.35, 1.1, pz)))
	for dz: float in [712.0, 718.0]:
		_ac_xf.append(_axf(Vector3(4.4, 1.5, 2.0), Vector3(566.0, 0.8, dz)))
	_label("RESERVED TAILGATING · $89", Vector3(516, 2.2, 700.0), 34,
		NAVY.lightened(0.5), 8.0, PI, SIGN.STENCIL, 0.40)
	_steel_xf.append(_axf(Vector3(0.16, 2.2, 0.16), Vector3(516, 1.1, 700.4)))


## One gate portal: pylons + lintel + recessed dark leaf panel. `face_dir` is
## the outward normal; yaw 0 means the portal spans along x.
func _stadium_gate(p: Vector3, yaw: float, face_dir: Vector3, name_txt: String,
		marquee: bool) -> void:
	var rot := Basis(Vector3.UP, yaw)
	var out := face_dir.normalized()
	var base := p + out * 4.0
	for side: float in [-1.0, 1.0]:
		var pp := base + rot.x * (side * 10.0)
		_solid_rot(Vector3(2.2, 14.0, 2.2), pp + Vector3(0, 7, 0), yaw, _mat_concrete)
	_rib_xf.append(Transform3D(rot * Basis.from_scale(Vector3(22.4, 2.4, 2.4)),
		base + Vector3(0, 13.2, 0)))
	# Recessed gate leaves: dark panel + steel mullions, set back toward the bowl.
	_frame_xf.append(Transform3D(rot * Basis.from_scale(Vector3(16.0, 11.0, 0.5)),
		p + out * 1.2 + Vector3(0, 5.6, 0)))
	for m in 5:
		_steel_xf.append(Transform3D(rot * Basis.from_scale(Vector3(0.24, 11.0, 0.6)),
			p + out * 1.1 + rot.x * (-6.4 + 3.2 * float(m)) + Vector3(0, 5.6, 0)))
	var lyaw := atan2(out.x, out.z)   # Label3D +Z face turned along the normal
	# The gate letter sits on a 22.4 x 2.4 lintel.
	_label(name_txt, base + out * 1.3 + Vector3(0, 12.9, 0), 130, PAINT_WHITE,
		10.0, lyaw, SIGN.CHANNEL, 1.90)
	if not marquee:
		return
	# The marquee over Gate A: navy backboard, three lines of canon copy.
	_navy_xf.append(Transform3D(rot * Basis.from_scale(Vector3(26.0, 7.0, 0.9)),
		base + Vector3(0, 18.4, 0)))
	_silver_xf.append(Transform3D(rot * Basis.from_scale(Vector3(26.6, 0.5, 1.0)),
		base + Vector3(0, 22.1, 0)))
	var front := base + out * 0.6
	# Backboard is 26.0 x 7.0 centred at +18.4, i.e. it spans 14.9 .. 21.9.
	_label("RUSTLERS STADIUM", front + Vector3(0, 19.9, 0), 230, PAINT_WHITE,
		24.4, lyaw, SIGN.MARQUEE, 2.10)
	_label("COLT BIDWELL FIELD", front + Vector3(0, 17.6, 0), 120, SILVER,
		20.0, lyaw, SIGN.CHANNEL, 1.30)
	_label("HOME OF AMERICA'S FRANCHISE™", front + Vector3(0, 16.0, 0), 80,
		SILVER, 22.0, lyaw, SIGN.STENCIL, 0.90)


# ============================ 3. GIGASTEAD ===================================
## Prairie-industrial menace: three windowless server barns behind a fenced,
## floodlit yard; cooling stacks; a Range Wardens gatehouse; the sign that
## already answered for you. Canon: §6 compute ranch, §8 GigaStead/Wardens.
func _gigastead() -> void:
	var barn_mat := _flat(BARN_DARK, false)
	barn_mat.roughness = 0.55
	barn_mat.metallic = 0.25
	# Yard + approach stub off the prairie to the north.
	_solid(Vector3(184, 0.08, 158), Vector3(-260, 0.0, 480), _mat_concrete)
	_solid(Vector3(20, 0.08, 24), Vector3(-260, -0.02, 390), _mat_asphalt)
	# Three barns in a row, pilaster ribs, rooftop units, south-side stacks.
	var halls := ["HALL A", "HALL B", "HALL C"]
	for b in 3:
		var bz := 435.0 + 45.0 * float(b)
		_solid(Vector3(120, 10.5, 26), Vector3(-260, 5.29, bz), barn_mat)
		_rib_xf.append(_axf(Vector3(120.6, 0.9, 26.6), Vector3(-260, 10.2, bz)))
		for r in 14:
			var rx := -318.0 + 9.0 * float(r)
			_rib_xf.append(_axf(Vector3(0.5, 9.6, 0.35), Vector3(rx, 4.8, bz - 13.1)))
			_rib_xf.append(_axf(Vector3(0.5, 9.6, 0.35), Vector3(rx, 4.8, bz + 13.1)))
		for u in 5:
			_ac_xf.append(_axf(Vector3(3.2, 1.4, 2.6), Vector3(-310.0 + 25.0 * float(u), 11.3, bz)))
		for s in 12:
			_stack_xf.append(_axf(Vector3(1, 1, 1), Vector3(-315.0 + 10.0 * float(s), 2.55, bz + 15.2)))
		# West-end rollup door + hall name (doors: the interactivity promise).
		_frame_xf.append(_axf(Vector3(0.3, 5.0, 4.5), Vector3(-320.2, 2.5, bz)))
		_label(str(halls[b]), Vector3(-320.5, 7.2, bz), 60, GALV, 7.0, PI * 1.5,
			SIGN.STENCIL, 0.70)
	# The brand, read from the freeway approach: huge on Hall A's north face.
	# 120 m of windowless barn wall, and the brand was using 13 % of it. This is
	# the read from the freeway approach — it is allowed to be enormous.
	_label("GIGASTEAD", Vector3(-260, 6.6, 421.8), 620, Color(0.62, 0.85, 0.3),
		84.0, PI, SIGN.CHANNEL, 6.20)
	# Security fence: post-and-mesh perimeter, gapped at the north gate lane.
	_fence_run(Vector3(-352, 0, 400), Vector3(-270, 0, 400))
	_fence_run(Vector3(-250, 0, 400), Vector3(-168, 0, 400))
	_fence_run(Vector3(-168, 0, 400), Vector3(-168, 0, 560))
	_fence_run(Vector3(-168, 0, 560), Vector3(-352, 0, 560))
	_fence_run(Vector3(-352, 0, 560), Vector3(-352, 0, 400))
	# Gatehouse ("RANGE WARDENS") + barrier arm (visual-only: drive on in —
	# and explain yourself to a man with a clipboard).
	_solid(Vector3(4.6, 3.4, 3.4), Vector3(-247, 1.74, 396), _mat_concrete)
	_frame_xf.append(_axf(Vector3(4.0, 1.1, 0.3), Vector3(-247, 2.3, 394.25)))
	_frame_xf.append(_axf(Vector3(0.3, 1.1, 2.6), Vector3(-249.45, 2.3, 396)))
	_rib_xf.append(_axf(Vector3(5.2, 0.3, 4.0), Vector3(-247, 3.6, 396)))
	_beacon_xf.append(_axf(Vector3(0.9, 0.22, 0.5), Vector3(-247, 3.85, 396)))
	_label("RANGE WARDENS", Vector3(-247, 3.25, 394.1), 34, Color(0.9, 0.75, 0.3),
		4.2, PI, SIGN.STENCIL, 0.36)
	_steel_xf.append(_axf(Vector3(0.3, 1.3, 0.3), Vector3(-270.6, 0.65, 396)))
	for a in 4:
		var ax := -268.3 + 4.6 * float(a)
		var arm_col := a % 2 == 0
		var arm := _axf(Vector3(4.6, 0.16, 0.16), Vector3(ax, 1.25, 396))
		if arm_col:
			_beacon_xf.append(arm)
		else:
			_panel_white_xf.append(arm)
	# The sign: two posts, big panel, the neighborly threat.
	_solid(Vector3(0.4, 4.6, 0.4), Vector3(-236, 2.3, 391))
	_solid(Vector3(0.4, 4.6, 0.4), Vector3(-224, 2.3, 391))
	_sign_panel(Vector3(-230, 7.0, 391), Vector2(14, 5), BARN_DARK)
	for face: float in [1.0, -1.0]:
		var sz := 391.0 - face * 0.56
		var syaw := PI if face > 0.0 else 0.0
		# Panel is 14 x 5, centre y 7.0 -> spans 4.5 .. 9.5.
		_label("GIGASTEAD", Vector3(-230, 8.25, sz), 200, Color(0.62, 0.85, 0.3),
			13.2, syaw, SIGN.CHANNEL, 1.60)
		_label("YOUR NEIGHBORS ALREADY SAID YES", Vector3(-230, 6.45, sz), 70,
			PAINT_WHITE, 13.2, syaw, SIGN.STENCIL, 0.80)
		_label("COMPUTE RANCH No. 7", Vector3(-230, 5.30, sz), 46, GALV, 13.2,
			syaw, SIGN.PLAQUE, 0.55)
	# Canon banner on the fence + NO TRESPASSING plates around the wire.
	_sign_panel(Vector3(-300, 1.7, 399.5), Vector2(10, 1.5), PAINT_WHITE)
	_label("ECONOMIC MIRACLE IN PROGRESS", Vector3(-300, 1.7, 398.9), 60,
		Color(0.2, 0.2, 0.22), 9.4, PI, SIGN.STENCIL, 1.10)
	for spot: Vector3 in [Vector3(-330, 0, 400), Vector3(-200, 0, 400),
			Vector3(-168, 0, 450), Vector3(-168, 0, 520), Vector3(-300, 0, 560),
			Vector3(-352, 0, 480)]:
		var nyaw := PI if spot.z <= 400.0 else 0.0
		if spot.x <= -352.0:
			nyaw = PI * 1.5
		elif spot.x >= -168.0:
			nyaw = PI * 0.5
		var n_out := Vector3(sin(nyaw), 0, cos(nyaw))
		_panel_white_xf.append(Transform3D(
			Basis(Vector3.UP, nyaw) * Basis.from_scale(Vector3(1.5, 1.05, 0.06)),
			spot + Vector3(0, 1.6, 0) + n_out * 0.12))
		_label("NO TRESPASSING\nRANGE WARDENS PATROL", spot + Vector3(0, 1.6, 0)
			+ n_out * 0.18, 20, Color(0.75, 0.1, 0.08), 1.36, nyaw,
			SIGN.STENCIL, 0.86)
	# Floodlight poles ringing the yard, banks aimed inward.
	for fp: Vector3 in [Vector3(-345, 0, 408), Vector3(-305, 0, 408),
			Vector3(-215, 0, 408), Vector3(-175, 0, 408), Vector3(-345, 0, 552),
			Vector3(-260, 0, 552), Vector3(-175, 0, 552), Vector3(-348, 0, 480)]:
		_steel_xf.append(_axf(Vector3(0.3, 14.0, 0.3), fp + Vector3(0, 7, 0)))
		var to_c := (Vector3(-260, 0, 480) - fp).normalized()
		var fyaw := atan2(to_c.x, to_c.z)
		_flood_xf.append(Transform3D(
			Basis(Vector3.UP, fyaw) * Basis(Vector3(1, 0, 0), -0.6)
			* Basis.from_scale(Vector3(2.2, 1.0, 0.5)), fp + Vector3(0, 14.2, 0)))
	# Substation corner: transformers + insulator stacks, SE of Hall C.
	for tb in 4:
		var tp := Vector3(-186.0 + 4.6 * float(tb % 2), 1.1, 542.0 + 6.0 * float(tb / 2))
		_solid(Vector3(2.6, 2.2, 1.9), tp, _flat(Color(0.22, 0.3, 0.24), false))
		for ins in 3:
			_bollard_xf.append(_axf(Vector3(0.24, 0.9, 0.24),
				tp + Vector3(-0.8 + 0.8 * float(ins), 1.55, 0)))
	_label("DANGER · HIGH VOLTAGE", Vector3(-184, 1.2, 537.9), 30,
		Color(0.95, 0.78, 0.12), 3.4, PI, SIGN.STENCIL, 0.40)


## Chain-link fence run: translucent mesh band + galvanized posts + three barb
## wires on top. Collision: one thin static box per run (a fence you must ram).
func _fence_run(a: Vector3, b: Vector3) -> void:
	var d := b - a
	var run_len := d.length()
	var dir := d / run_len
	var yaw := atan2(dir.x, dir.z) + PI * 0.5   # box long axis (x) along the run
	var mid := (a + b) * 0.5
	var rot := Basis(Vector3.UP, yaw)
	_wire_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 2.4, 0.05)),
		mid + Vector3(0, 1.25, 0)))
	for w in 3:
		_wire_xf.append(Transform3D(rot * Basis.from_scale(Vector3(run_len, 0.05, 0.05)),
			mid + Vector3(0, 2.62 + 0.14 * float(w), 0)))
	var n := int(run_len / 8.0)
	for i in n + 1:
		var t := float(i) / float(maxi(n, 1))
		_galv_xf.append(_axf(Vector3(0.14, 2.9, 0.14), a.lerp(b, t) + Vector3(0, 1.45, 0)))
	_collider_rot(Vector3(run_len, 2.9, 0.15), mid + Vector3(0, 1.45, 0), yaw)


# ===================== 4. MIDDLINGTON WATER TOWER ============================
## The suburb's whole identity in one object: pedestal stem, squashed spheroid
## tank, catwalk, MIDDLINGTON on both faces, red beacon for the night sky.
## Visible from the freeway deck (z=0) a kilometre east.
func _middlington_tower() -> void:
	var cream := _flat(TOWER_CREAM, false)
	cream.roughness = 0.7
	_solid(Vector3(14, 0.3, 14), Vector3(-300, 0.1, -140), _mat_concrete)
	var stem := MeshInstance3D.new()
	stem.mesh = MESH_KIT.round_limb(3.1, 2.3, 34.0, 10)
	stem.material_override = cream
	stem.position = Vector3(-300, 17.2, -140)
	add_child(stem)
	_collider(Vector3(5.4, 34, 5.4), Vector3(-300, 17.2, -140))
	var flare := MeshInstance3D.new()
	flare.mesh = MESH_KIT.round_limb(1.9, 5.6, 5.0, 10)
	flare.material_override = cream
	flare.position = Vector3(-300, 30.0, -140)
	add_child(flare)
	var tank := MeshInstance3D.new()
	tank.mesh = MESH_KIT.sphere(0.5, 8, 14)
	tank.material_override = cream
	tank.scale = Vector3(16.4, 11.0, 16.4)
	tank.position = Vector3(-300, 36.5, -140)
	add_child(tank)
	var cap := MeshInstance3D.new()
	cap.mesh = MESH_KIT.sphere(0.5, 5, 10)
	cap.material_override = _flat(Color(0.62, 0.64, 0.6), false)
	cap.scale = Vector3(5.0, 2.6, 5.0)
	cap.position = Vector3(-300, 41.9, -140)
	add_child(cap)
	var mast := MeshInstance3D.new()
	mast.mesh = MESH_KIT.prism(0.09, 3.0, 6)
	mast.material_override = _flat(STEEL, false)
	mast.position = Vector3(-300, 44.2, -140)
	add_child(mast)
	_beacon_xf.append(_axf(Vector3(0.26, 0.26, 0.26), Vector3(-300, 45.8, -140)))
	# Catwalk ring + rail at the equator.
	for i in 12:
		var a := TAU * float(i) / 12.0
		var ring_rot := Basis(Vector3.UP, -a)
		var rp := Vector3(-300 + cos(a) * 8.7, 0, -140 + sin(a) * 8.7)
		_galv_xf.append(Transform3D(ring_rot * Basis.from_scale(Vector3(4.7, 0.12, 0.9)),
			rp + Vector3(0, 33.4, 0)))
		_galv_xf.append(Transform3D(ring_rot * Basis.from_scale(Vector3(4.7, 0.06, 0.06)),
			rp * Vector3(1, 0, 1) + Vector3(0, 34.4, 0)
			+ Vector3(cos(a), 0, sin(a)) * 0.42))
		_galv_xf.append(_axf(Vector3(0.06, 1.0, 0.06), rp + Vector3(0, 33.95, 0)))
	# The name, readable from the freeway (south face) and the suburb (north).
	# The tank is a 16.4 m spheroid, so the name has to stay well inside its
	# equator or the outer letters float off the curve into open sky.
	_label("MIDDLINGTON", Vector3(-300, 36.9, -132.2), 150, NAVY, 11.0, 0.0,
		SIGN.MARQUEE, 3.0)
	_label("MIDDLINGTON", Vector3(-300, 36.9, -147.8), 150, NAVY, 11.0, PI,
		SIGN.MARQUEE, 3.0)
	# Pump shed with the municipal plate.
	_solid(Vector3(3.2, 2.6, 2.6), Vector3(-293, 1.34, -134), TEX.brick_material(Color(0.52, 0.4, 0.3)))
	_label("CITY OF MIDDLINGTON UTILITIES", Vector3(-293, 1.5, -132.6), 22,
		PAINT_WHITE, 2.9, PI, SIGN.STENCIL, 0.32)


# ============================== SHARED KIT ===================================
## Monument marquee: brick plinth, panel, three copy lines per face.
func _marquee(base: Vector3, north_lines: Array, south_lines: Array, accent: Color) -> void:
	_solid(Vector3(9.0, 1.1, 1.2), base + Vector3(0, 0.55, 0),
		TEX.brick_material(Color(0.5, 0.38, 0.3)))
	_solid(Vector3(8.4, 4.2, 0.8), base + Vector3(0, 3.2, 0), _flat(Color(0.93, 0.92, 0.88), false))
	var lines := [north_lines, south_lines]
	for f in 2:
		var face := 1.0 if f == 0 else -1.0
		var yaw := PI if face > 0.0 else 0.0
		var z_off := -face * 0.46
		var use: Array = lines[f]
		# Panel is 8.4 x 4.2 (centre y 3.2, so it spans 1.1 .. 5.3). Name in the
		# monument register, the two changeable lines in the flat plastic
		# letters a marquee is actually spelled out in.
		_label(str(use[0]), base + Vector3(0, 4.55, z_off), 90, accent,
			7.8, yaw, SIGN.MARQUEE, 0.80)
		_label(str(use[1]), base + Vector3(0, 3.35, z_off), 60,
			Color(0.2, 0.2, 0.24), 7.6, yaw, SIGN.FLAT, 0.62)
		_label(str(use[2]), base + Vector3(0, 2.45, z_off), 50,
			Color(0.35, 0.35, 0.4), 7.6, yaw, SIGN.FLAT, 0.52)


func _sign_panel(pos: Vector3, size: Vector2, col: Color) -> void:
	var m := _flat(col, false)
	m.emission_enabled = true            # retroreflective night read; color-only
	m.emission = col                     # emission on an UNtextured material is
	m.emission_energy_multiplier = 0.35  # legal — and stays under the bloom gate
	var mi := MeshInstance3D.new()
	mi.mesh = _shared_box(Vector3(size.x, size.y, 0.5))
	mi.material_override = m
	mi.position = pos
	add_child(mi)


func _tree(base: Vector3) -> void:
	_trunk_xf.append(_axf(Vector3(1, 3.2, 1), base + Vector3(0, 1.6, 0)))
	var s := _rng.randf_range(0.9, 1.15)
	for lobe in 3:
		var off := Vector3(_rng.randf_range(-0.9, 0.9), 3.4 + _rng.randf_range(0.0, 1.0),
			_rng.randf_range(-0.9, 0.9))
		_canopy_xf.append(Transform3D(
			Basis.from_scale(Vector3(3.6, 2.9, 3.6) * s * _rng.randf_range(0.8, 1.0)),
			base + off))
		var g := _rng.randf_range(0.85, 1.05)
		_canopy_col.append(Color(0.36 * g, 0.42 * g, 0.22 * g).srgb_to_linear())


## Static box WITH collision (the Building Designer license) + shared visual.
func _solid(size: Vector3, origin: Vector3, mat: Material = null) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis.IDENTITY, origin)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	if mat != null:
		var mi := MeshInstance3D.new()
		mi.mesh = _shared_box(size)
		mi.material_override = mat
		body.add_child(mi)
	add_child(body)


func _solid_rot(size: Vector3, origin: Vector3, yaw: float, mat: Material) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
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


## Collision-only rotated box (visual handled elsewhere, e.g. bowl segments).
func _collider_rot(size: Vector3, origin: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.transform = Transform3D(Basis(Vector3.UP, yaw), origin)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	body.add_child(col)
	add_child(body)


func _collider(size: Vector3, origin: Vector3) -> void:
	_collider_rot(size, origin, 0.0)


## Axis-aligned scaled transform (the MultiMesh workhorse).
func _axf(size: Vector3, pos: Vector3) -> Transform3D:
	return Transform3D(Basis.from_scale(size), pos)


## M22: exact fit (`sign_kit.gd` — the 0.66 estimate is retired) plus a
## register per structure. A megachurch fascia, a stadium marquee, a compute
## barn and a municipal water tank are four different institutions and now
## carry four different hands out of the one font the project is allowed.
func _label(text: String, pos: Vector3, fsize: int, col: Color, max_w: float,
		yaw: float, style: int = SIGN.FLAT, max_h: float = 0.0) -> void:
	var lbl := SIGN.make(text, style, col, max_w, max_h, fsize)
	lbl.position = pos
	lbl.rotation.y = yaw
	add_child(lbl)


func _flat(col: Color, unshaded: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.85
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


func _vtx_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color.WHITE
	m.roughness = 0.85
	m.vertex_color_use_as_albedo = true
	return m


func _shared_box(size: Vector3) -> BoxMesh:
	var key := "%.2f_%.2f_%.2f" % [size.x, size.y, size.z]
	if not _mesh_cache.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_mesh_cache[key] = bm
	return _mesh_cache[key]


## SHADOW POLICY (D-028). Landmarks are the one layer where MOST sets keep
## their shadows, and deliberately so: these are the structures §3 of the
## quality bar says must be nameable from a screenshot, and a landmark is
## nameable because of its massing. Ribs, cornice bands, stacks, mechanicals
## and canopies are all real architectural mass and all stay on. What comes off
## is the same three categories as everywhere else — lot paint, an emissive
## fixture, and alpha-cut mesh the shadow map cannot represent.
func _flush() -> void:
	_mm(_white_xf, [], _flat(PAINT_WHITE, true), _unit_box, "LmPaintWhite", false)
	var gold := _flat(Color(0.85, 0.72, 0.25), true)
	_mm(_yellow_xf, [], gold, _unit_box, "LmPaintGold", false)
	_mm(_steel_xf, [], _flat(STEEL, false), _unit_box, "LmSteel", true)
	var galv := _flat(GALV, false)
	galv.metallic = 0.4
	galv.roughness = 0.45
	_mm(_galv_xf, [], galv, _unit_box, "LmGalv", true)
	var navy := _flat(NAVY, false)
	navy.emission_enabled = true
	navy.emission = NAVY
	navy.emission_energy_multiplier = 0.4
	# Not "trim" in the storefront sense — these are 26 x 7 m facade panels and
	# 0.9 m cornice bands, i.e. the massing that makes each landmark itself.
	_mm(_navy_xf, [], navy, _unit_box, "LmNavyTrim", true)
	_mm(_silver_xf, [], _flat(SILVER, false), _unit_box, "LmSilverTrim", true)
	_mm(_rib_xf, [], _flat(Color(0.34, 0.33, 0.34), false), _unit_box,
		"LmRibs", true)
	var stack_m := _flat(GALV, false)
	stack_m.metallic = 0.5
	stack_m.roughness = 0.4
	_mm(_stack_xf, [], stack_m, MESH_KIT.prism(1.05, 4.6, 10), "LmStacks", true)
	_mm(_ac_xf, [], _flat(Color(0.5, 0.51, 0.5), false), _unit_box,
		"LmMechs", true)
	var wire := StandardMaterial3D.new()
	wire.albedo_color = Color(0.45, 0.47, 0.48, 0.4)
	wire.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wire.roughness = 0.6
	wire.metallic = 0.3
	wire.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Chain-link is a 40%-alpha two-sided panel. The shadow map has no alpha, so
	# a caster here renders the fence as a SOLID wall of shade — actively wrong.
	_mm(_wire_xf, [], wire, _unit_box, "LmFenceMesh", false)
	var flood := _flat(Color(0.95, 0.93, 0.85), false)
	flood.emission_enabled = true
	flood.emission = Color(0.95, 0.93, 0.85)
	flood.emission_energy_multiplier = 1.3
	_mm(_flood_xf, [], flood, _unit_box, "LmFloodHeads", false)
	var beacon := _flat(Color(0.85, 0.12, 0.1), false)
	beacon.emission_enabled = true
	beacon.emission = Color(0.85, 0.12, 0.1)
	beacon.emission_energy_multiplier = 1.2
	_mm(_beacon_xf, [], beacon, _unit_box, "LmBeacons", false)
	_mm(_bollard_xf, [], _flat(Color(0.35, 0.36, 0.38), false),
		MESH_KIT.prism(0.18, 1.1, 8), "LmBollards", true)
	_mm(_porta_xf, [], _flat(Color(0.12, 0.3, 0.55), false), _unit_box,
		"LmPorta", true)
	_mm(_porta_door_xf, [], _flat(Color(0.09, 0.22, 0.4), false), _unit_box,
		"LmPortaDoors", false)
	_mm(_hedge_xf, [], _flat(Color(0.3, 0.36, 0.2), false), _unit_box,
		"LmHedges", true)
	_mm(_planter_xf, [], _flat(Color(0.5, 0.49, 0.46), false), _unit_box,
		"LmPlanters", true)
	_mm(_trunk_xf, [], _flat(Color(0.32, 0.24, 0.17), false),
		MESH_KIT.round_limb(0.24, 0.17, 1.0, 7), "LmTrunks", true)
	var canopy := _vtx_mat()
	_mm(_canopy_xf, _canopy_col, canopy, MESH_KIT.canopy(0.5, 7, 11, 13, 0.17, 0.07),   # M23: crown (7x11)
		"LmCanopies", true)
	SHD.apply_wind(self, "LmCanopies", 0.88, false, 0.04, 0.08, 0.70, 0.0, 1.0, true, 13)   # M23 foliage
	# Lit glazing set in a frame that already casts: doubly wrong as an occluder.
	_mm(_doorglass_xf, [], SHD.storefront_glass(true), _unit_box,
		"LmDoorGlass", false)
	_mm(_frame_xf, [], _flat(Color(0.13, 0.13, 0.15), false), _unit_box,
		"LmFrames", true)
	var plate := _flat(PAINT_WHITE, false)
	plate.emission_enabled = true
	plate.emission = PAINT_WHITE
	plate.emission_energy_multiplier = 0.3
	_mm(_panel_white_xf, [], plate, _unit_box, "LmPlates", false)
	var jet := _flat(Color(0.93, 0.93, 0.9), false)
	jet.roughness = 0.3
	jet.metallic = 0.35
	_mm(_jet_white_xf, [], jet, _unit_box, "LmJet", true)


## `casts` is required, no default (D-028). Landmarks mostly answer `true`;
## the point of the parameter is that a new set has to say so out loud.
func _mm(xf: Array[Transform3D], cols: Array[Color], mat: Material,
		mesh: Mesh, label: String, casts: bool) -> void:
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
			mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = label
	mmi.multimesh = mm
	mmi.material_override = mat
	if not casts:
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
