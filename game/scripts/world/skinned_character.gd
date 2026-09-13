extends RefCounted
## SKINNED CHARACTER — proof of concept, NOT live. Nothing loads this unless
## `--skinned` is on the command line (see the gate in pedestrians.gd,
## player_character.gd, foot_cops.gd, carjack.gd). `character_factory.gd` is
## untouched and remains the shipping path.
##
## THE THESIS. The factory builds a human out of ~123 rigid MeshInstance3D
## primitives parented to a joint tree. Two convex surfaces that meet always
## produce a visible crossing curve, so every cycle fixes one intersection and
## exposes the next; and because the parts are rigid, nothing can bend, crease
## or stretch — every joint is a hard boundary by construction.
##
## This file builds the body as ONE closed surface with vertex weights driven by
## a Skeleton3D. There is no crossing to fix because there is no second surface:
##
##   1. the anatomy is declared as ~26 implicit primitives (capsules, tapered
##      capsules, ellipsoids) — the same masses the factory already declares,
##      re-expressed as a FIELD instead of as geometry;
##   2. they are combined with a POLYNOMIAL SMOOTH-MIN, which is C1 everywhere.
##      A smin union has no crossing curve at all: where two masses meet, the
##      field blends, and the isosurface is a fillet. The entire defect class
##      that produced shoulder orbs, trapezius stipple and the muzzle patch
##      cannot occur;
##   3. the isosurface is polygonised with NAIVE SURFACE NETS — one vertex per
##      sign-changing cell, quads across sign-changing grid edges. Manifold,
##      uniform-ish quad topology, and it handles the five-way branch of a
##      humanoid without anybody authoring a topology;
##   4. vertices are Taubin-smoothed then re-projected onto the isosurface, so
##      the voxel stair-step goes away without the volume going with it;
##   5. normals come from the ANALYTIC FIELD GRADIENT, not from the triangles.
##      Shading is therefore as smooth as the field, not as smooth as the grid;
##   6. weights: each primitive names an owner bone. A vertex takes weight from
##      its owner and the owner's immediate relatives, inverse-distance to the
##      BONE SEGMENT, then the whole weight vector is Laplacian-smoothed across
##      the mesh. That smoothing IS the joint falloff — a shoulder becomes a
##      surface that deforms.
##
## COLOUR WITHOUT LOSING SHARING. One mesh must serve everybody or the bake cost
## multiplies by the crowd. So the mesh carries no colour: it carries a ZONE ID
## baked into UV.x, and each character gets a 16x1 palette texture built from
## its own config (RGB = albedo, A = roughness, read back through
## `roughness_texture_channel`). Geometry is shared across the population in six
## build/girth buckets; only the 16-pixel texture is per-character. One surface,
## one material, ONE DRAW CALL for the whole body.
##
## THE RIG CONTRACT IS PRESERVED EXACTLY, and this is the load-bearing claim of
## the whole experiment. `build()` returns the same dict keys pointing at real
## Node3Ds at the same frozen pivots, so `animate()`, `aim_pose()`,
## player_character's crouch pose and melee's bat-parented-to-`el_1` all work
## against this body with ZERO caller changes. A `_SkinSync` node copies the
## proxy joints' local rotations onto the Skeleton3D every frame. Migration
## therefore costs one symbol per call site, not a rewrite.
##
## Joint sign law (D-020) is inherited, not re-litigated: the proxy joints ARE
## the factory's joints, so positive rotation.x is still FORWARD.

const FACTORY := preload("res://scripts/world/character_factory.gd")
const SHD := preload("res://scripts/world/city_shaders.gd")

# ---- frozen joint pivots (mirrored from character_factory — DO NOT DRIFT) ----
const HIP_PIVOT := Vector3(0.10, 0.90, 0.0)
const KNEE_PIVOT := Vector3(0.0, -0.43, 0.0)
const TORSO_PIVOT := Vector3(0.0, 0.90, 0.0)
const COLLAR_PIVOT := Vector3(0.0, 0.56, 0.0)
const HEAD_PIVOT := Vector3(0.0, 0.08, 0.0)
const SHOULDER_X := 0.192   # D-061: was 0.183 — the arm hung INSIDE a 0.30 m chest
const ELBOW_PIVOT := Vector3(0.0, -0.30, 0.0)

# ---- bones. Index order IS the skin bind order. ----
const B_ROOT := 0
const B_HIP0 := 1
const B_KNEE0 := 2
const B_HIP1 := 3
const B_KNEE1 := 4
const B_TORSO := 5
const B_COLLAR := 6
const B_HEAD := 7
const B_SH0 := 8
const B_EL0 := 9
const B_SH1 := 10
const B_EL1 := 11
const BONE_N := 12
## name, parent, rest offset from parent. `sx` marks an offset whose x is
## multiplied by the build factor (shoulders) — legs never scale with build,
## exactly as in the factory.
const BONES: Array = [
	["root", -1, Vector3.ZERO, false],
	["hip_0", B_ROOT, Vector3(-0.10, 0.90, 0.0), false],
	["knee_0", B_HIP0, KNEE_PIVOT, false],
	["hip_1", B_ROOT, Vector3(0.10, 0.90, 0.0), false],
	["knee_1", B_HIP1, KNEE_PIVOT, false],
	["torso", B_ROOT, TORSO_PIVOT, false],
	["collar", B_TORSO, COLLAR_PIVOT, false],
	["head", B_COLLAR, HEAD_PIVOT, false],
	["sh_0", B_COLLAR, Vector3(-SHOULDER_X, 0.0, 0.0), true],
	["el_0", B_SH0, ELBOW_PIVOT, false],
	["sh_1", B_COLLAR, Vector3(SHOULDER_X, 0.0, 0.0), true],
	["el_1", B_SH1, ELBOW_PIVOT, false],
]
## Which bones a vertex owned by bone B is allowed to take weight from. Keeping
## this tight is what stops the left thigh picking up right-thigh weight where
## the two surfaces smin together at the crotch.
const KIN: Dictionary = {
	B_ROOT: [B_ROOT, B_HIP0, B_HIP1, B_TORSO],
	B_HIP0: [B_HIP0, B_ROOT, B_KNEE0, B_TORSO],
	B_KNEE0: [B_KNEE0, B_HIP0],
	B_HIP1: [B_HIP1, B_ROOT, B_KNEE1, B_TORSO],
	B_KNEE1: [B_KNEE1, B_HIP1],
	B_TORSO: [B_TORSO, B_ROOT, B_COLLAR, B_HIP0, B_HIP1],
	B_COLLAR: [B_COLLAR, B_TORSO, B_HEAD, B_SH0, B_SH1],
	B_HEAD: [B_HEAD, B_COLLAR],
	B_SH0: [B_SH0, B_COLLAR, B_EL0],
	B_EL0: [B_EL0, B_SH0],
	B_SH1: [B_SH1, B_COLLAR, B_EL1],
	B_EL1: [B_EL1, B_SH1],
}

# ---- material zones. UV.x = (zone + 0.5) / PAL_W picks a COLUMN of the palette;
# UV.y = the zone's own normalised height picks a ROW.
#
# The PoC palette was 16x1: one flat colour per zone, and every colour boundary
# on the body had to be a boundary between two ZONES — i.e. a boundary between
# two sets of triangles, which staircases by one voxel (18 mm) unless the mesh
# is cut along it. That is why the PoC had four garment features and the factory
# has forty.
#
# The palette is now 32 x 64. UV.y is a CONTINUOUS per-zone coordinate
# (rest-space height, remapped to the zone's own y-range), so it interpolates
# across every triangle: a colour boundary drawn as a ROW BOUNDARY in the
# palette lands at an exact height on the body, at FRAGMENT resolution, with no
# cut, no extra triangle and no staircase. Every horizontal garment line —
# a reflective band, a jersey stripe, a snap row, a sock line, a hem — is
# therefore free. Only boundaries that are NOT horizontal still need a cut.
#
# BODY zones are baked into the shared per-bucket mesh, so their BOUNDARIES are
# identical for every character in the game and only their COLOURS vary. That is
# what keeps one bake serving the whole population.
const Z_SOLE := 0
const Z_SHOE := 1
const Z_SHIN := 2
const Z_THIGH_LO := 3
const Z_THIGH_HI := 4
const Z_PELVIS := 5
const Z_HIPBAND := 6         # 0.958..1.012 — where an UNTUCKED shirt hangs
const Z_BELT := 7
const Z_SHIRT_F := 8         # trunk, front of the side seam (z < 0 is FORWARD)
const Z_SHIRT_B := 9         # trunk, behind it
const Z_CHEST_V := 10        # the V-neck notch: shirt for everyone but SCRUBS
const Z_SLEEVE := 11
const Z_UPARM := 12
const Z_FOREARM := 13
const Z_CUFF := 14
const Z_HAND := 15
const Z_NECK := 16
const Z_COLLAR := 17
# GARMENT zones — carried by the second skinned surface (see THE WARDROBE).
const Z_G_PLACKET := 18
const Z_G_COLLAR := 19
const Z_G_POCKET := 20
const Z_G_TRIM := 21         # yoke seam, epaulets, hem welt
const Z_G_TIE := 22
const Z_G_VEST := 23
const Z_G_APRON := 24
const Z_G_DUTY := 25
const Z_G_METAL := 26        # buckle
const Z_G_BADGE := 27        # shield, name tape, ID card
const Z_G_CORD := 28
const Z_G_HOOD := 29
const Z_G_ACCENT := 30       # V-neck binding, scrub trim
const Z_G_TAPE := 31         # name tape
const PAL_W := 32
const PAL_H := 64
## The y-range each zone's UV.y spans. A row of the palette is therefore
## (hi - lo) / 64 metres tall on the body — 7 to 9 mm on the trunk zones, which
## is finer than the 18 mm voxel and far finer than any zone boundary could be.
const ZV: Array = [
	[0.000, 0.033],   # SOLE
	[0.033, 0.118],   # SHOE
	[0.118, 0.680],   # SHIN
	[0.118, 0.680],   # THIGH_LO
	[0.680, 0.958],   # THIGH_HI
	[0.780, 0.958],   # PELVIS
	[0.958, 1.012],   # HIPBAND
	[1.012, 1.062],   # BELT
	[1.062, 1.620],   # SHIRT_F
	[1.062, 1.620],   # SHIRT_B
	[1.400, 1.512],   # CHEST_V
	[1.300, 1.470],   # SLEEVE
	[1.100, 1.300],   # UPARM
	[0.938, 1.170],   # FOREARM
	[0.906, 0.938],   # CUFF
	[0.730, 0.906],   # HAND   (M25: tips at 0.735)
	[1.576, 1.620],   # NECK   (M23: was 1.512 — 108 mm of bare neck read as a giraffe at `face`; M24: 1.560 -> 1.576, the band's top edge)
	[1.460, 1.576],   # COLLAR
	[1.060, 1.560],   # G_PLACKET
	[1.390, 1.590],   # G_COLLAR (M24: band + points)
	[1.330, 1.470],   # G_POCKET
	[1.100, 1.560],   # G_TRIM
	[1.150, 1.530],   # G_TIE
	[1.020, 1.500],   # G_VEST
	[0.780, 1.500],   # G_APRON
	[0.900, 1.100],   # G_DUTY
	[1.010, 1.060],   # G_METAL
	[1.320, 1.390],   # G_BADGE
	[1.250, 1.520],   # G_CORD
	[1.380, 1.620],   # G_HOOD
	[1.380, 1.520],   # G_ACCENT
	[1.340, 1.390],   # G_TAPE
]

# ---- meshing resolution ----
## 18 mm. The forearm is the thinnest thing in the field (r ~46 mm), so it is
## ~6.5 cells across — enough for surface nets plus Taubin plus gradient normals
## to read as round. 10 mm was tried and costs 2.4x the bake for a difference no
## screenshot at the judgement vantages could resolve.
const VOX := 0.018
const SMOOTH_PASSES := 3
const WEIGHT_SMOOTH_PASSES := 3

static var _mesh_cache: Dictionary = {}    # bucket key -> ArrayMesh
static var _pal_cache: Dictionary = {}     # palette key -> Material (palette shader; StandardMaterial3D under --gfx-legacy)
static var _bake_us := 0                   # cumulative bake microseconds
static var _bake_n := 0
static var _no_disk := false               # tools set this to force a real bake
## Bump when the field, the mesher or the vertex format changes, so a stale
## user:// bake can never outlive the code that made it.
const CACHE_VER := 21   # 21: boots, pecs, scapulae, a rounder deltoid, a lumbar curve (D-062); 20: the trunk rebuilt as a rib cage, r2 (D-061); 18: leaves layered over the stand, pocket flaps, placket 5 mm (D-054); 17: tailored collar, placket and pockets replace voxel-cut shells (Codex).


# ============================== PUBLIC API ===================================
## Same signature, same return keys, same feet origin as
## `character_factory.build()`. Drop-in.
static func build(root: Node3D, cfg: Dictionary, feet_y: float) -> Dictionary:
	var s := float(cfg.get("scale", 1.0))
	var w := float(cfg.get("build", 1.0))
	var g := float(cfg.get("girth", 1.0))

	var vis := Node3D.new()
	vis.name = "Body"
	vis.position = Vector3(0, feet_y, 0)
	vis.scale = Vector3(s, s, s)
	root.add_child(vis)

	var rig := {"vis": vis, "phase": 0.0, "bob": 0.0, "lean": 0.0}

	# ---- proxy joints: byte-for-byte the factory's hierarchy and pivots, so
	# every caller that reaches into the rig keeps working unchanged.
	var joints: Array[Node3D] = []
	joints.resize(BONE_N)
	joints[B_ROOT] = vis
	for b in range(1, BONE_N):
		var n := Node3D.new()
		n.name = str(BONES[b][0])
		var off: Vector3 = BONES[b][2]
		if bool(BONES[b][3]):
			off.x *= w
		n.position = off
		joints[int(BONES[b][1])].add_child(n)
		joints[b] = n
	rig["hip_0"] = joints[B_HIP0]; rig["knee_0"] = joints[B_KNEE0]
	rig["hip_1"] = joints[B_HIP1]; rig["knee_1"] = joints[B_KNEE1]
	rig["torso"] = joints[B_TORSO]; rig["collar"] = joints[B_COLLAR]
	rig["head"] = joints[B_HEAD]
	rig["sh_0"] = joints[B_SH0]; rig["el_0"] = joints[B_EL0]
	rig["sh_1"] = joints[B_SH1]; rig["el_1"] = joints[B_EL1]

	# ---- skeleton
	var skel := Skeleton3D.new()
	skel.name = "Skel"
	vis.add_child(skel)
	for b in BONE_N:
		skel.add_bone(str(BONES[b][0]))
		if int(BONES[b][1]) >= 0:
			skel.set_bone_parent(b, int(BONES[b][1]))
		var off: Vector3 = BONES[b][2]
		if bool(BONES[b][3]):
			off.x *= w
		skel.set_bone_rest(b, Transform3D(Basis(), off))
		skel.set_bone_pose_position(b, off)
		skel.set_bone_pose_rotation(b, Quaternion.IDENTITY)

	# ---- the one skinned surface
	var mat := _palette_material(cfg)
	var mi := MeshInstance3D.new()
	mi.name = "Skin"
	mi.mesh = _mesh_for(w, g)
	mi.material_override = mat
	# The body is one convex-ish blob about the rig; a hand-set AABB keeps the
	# skinned instance from being culled when a limb swings out of the rest box.
	mi.custom_aabb = AABB(Vector3(-0.55, -0.15, -0.55), Vector3(1.10, 1.95, 1.10))
	skel.add_child(mi)
	# ORDER MATTERS, and it cost an afternoon. MeshInstance3D.skeleton does NOT
	# default to NodePath("..") in 4.7 — it defaults to EMPTY, so a mesh parented
	# to a Skeleton3D renders in bind pose and nothing about the rig reaches it.
	# The symptom is a character that animates perfectly in the joint tree and
	# stands stock still on screen. Set the path AND set the skin after the node
	# is in the tree, so the SkinReference is created against a resolved
	# skeleton.
	mi.skeleton = NodePath("..")
	mi.skin = skel.create_skin_from_rest_transforms()

	# ---- the wardrobe: a SECOND skinned surface on the SAME skeleton, made of
	# constant-offset shells of the same field. Same material, same palette, one
	# extra draw call for however many garment pieces the character wears.
	var lay := _layout(cfg)
	if OS.get_cmdline_user_args().has("--skinned-bare"):
		lay = 0   # QA toggle: the body alone, no garment shells — bisects body vs wardrobe
	if lay != 0:
		var bkey := _bucket_key(w, g)
		# Tools run as `--script` SceneTrees and may quit from _init before any
		# join hook fires (verify7: SIGSEGV in skin_d020); they bake inline.
		if _lib_ready(bkey) or OS.get_cmdline_args().has("--script"):
			_attach_garment(skel, lay, w, g, mat, mi.custom_aabb)
		else:
			# Cold bucket: never stall the main thread for a 12 s bake (D-036 S2).
			# The body ships now with its painted clothes; the shells arrive when
			# the worker lands them. The first cold build warms every bucket.
			prewarm_all()
			var waiter := GarmentWaiter.new()
			waiter.name = "GarmentWaiter"
			waiter.key = bkey
			waiter.lay = lay
			waiter.w = w
			waiter.g = g
			waiter.mat = mat
			waiter.aabb = mi.custom_aabb
			waiter.poll = _poll_pending
			waiter.attach = _attach_garment
			skel.add_child(waiter)

	# ---- hood UP is the one wardrobe piece still built the old way, because it
	# wraps the HEAD and the head is deliberately still the factory's. It goes
	# with the head, in the head milestone. Declared here rather than quietly
	# omitted.
	if bool(cfg.get("hood_up", false)):
		var hood := MeshInstance3D.new()
		hood.name = "HoodUp"
		var sm := SphereMesh.new()
		sm.radius = 0.128
		sm.height = 0.262
		sm.radial_segments = 16
		sm.rings = 9
		hood.mesh = sm
		hood.position = Vector3(0, 0.148, 0.062)
		hood.scale = Vector3(0.98, 1.0, 0.95)
		var hm := StandardMaterial3D.new()
		hm.albedo_color = (cfg["shirt"] as Color).darkened(0.04)
		hm.roughness = 0.92
		hood.material_override = hm
		joints[B_HEAD].add_child(hood)

	# ---- the head is NOT part of this experiment. It was already
	# re-topologised into one closed surface and that worked, so it is built by
	# the factory's own head code, unchanged, on the head proxy. Swapping it out
	# would confound the measurement.
	# M24: the factory head used to bring its own rigid neck, nape and two neck
	# muscles. On this body they sat OVER the skinned neck (r 56/62 vs 58/66,
	# but 190 mm long, ending in a flat cap at 1.445) and hid it — the "tube set
	# into a hole" at `face` (D-050) was that cap. The flag makes the factory
	# build the head alone; the neck below is this body's own field.
	var hcfg := cfg.duplicate()
	hcfg["skinned_body"] = true
	FACTORY._build_head(joints[B_HEAD], hcfg)

	var hand_material := FACTORY._skin(cfg["skin"], float(cfg.get("skin_rough", 0.72)))
	if bool(cfg.get("gloves", false)):
		hand_material = FACTORY._m(Color(0.20, 0.16, 0.12), 0.9)
	for side in 2:
		_build_hand(
			joints[B_EL0 if side == 0 else B_EL1], -1.0 if side == 0 else 1.0, hand_material)

	# ---- the sync. Callers never learn the skeleton exists.
	var sync := SkinSync.new()
	sync.name = "SkinSync"
	sync.setup(skel, joints)
	vis.add_child(sync)
	return rig


## The gait and the shooter stance are the FACTORY's, verbatim. They pose the
## proxy joints; SkinSync carries the pose to the bones. Delegating rather than
## reimplementing is the point: if the mesh cannot be driven by the shipping
## animator with no edits, the migration is dead, so it had better be driven by
## literally that function.
static func animate(rig: Dictionary, speed: float, delta: float,
		moving: bool, grounded := true) -> void:
	FACTORY.animate(rig, speed, delta, moving, grounded)


static func aim_pose(rig: Dictionary, delta: float) -> void:
	FACTORY.aim_pose(rig, delta)


static func random_config(rng: RandomNumberGenerator) -> Dictionary:
	return FACTORY.random_config(rng)


static func cop_config(rng: RandomNumberGenerator) -> Dictionary:
	return FACTORY.cop_config(rng)


static var _hand_mesh_cache: Dictionary = {}
const HAND_VOX := 0.004   # D-054: was 0.003 (Codex); see _build_hand

static func _build_hand(parent: Node3D, side: float, material: Material) -> void:
	if not _hand_mesh_cache.has(side):
		var prims: Array = []
		for p in preload("res://scripts/world/character_hands.gd").parts(side):
			prims.append(_cap(p[0], p[1], p[2], p[3], p[4], p[5], B_EL0, 0))
		# D-054: 3 mm gave 10,516 triangles per hand — a character's two hands
		# carried as many triangles as its body, and hospital_door_night went
		# from 16.67 to 17.79 ms p95 across seventeen of them. 4 mm keeps four
		# fingers and a thumb; the triangle count is measured by the probe below.
		var grid := _field_grid(prims, _flatten(prims), HAND_VOX)
		var surface := _polygonise(grid.f, grid.lo, grid.nx, grid.ny, grid.nz, grid.syz, HAND_VOX)
		var indices: PackedInt32Array = surface.idx
		# The field mesher emits outward cross products; Godot fronts are clockwise.
		for i in range(0, indices.size(), 3):
			var temp := indices[i + 1]
			indices[i + 1] = indices[i + 2]
			indices[i + 2] = temp
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = surface.verts
		arrays[Mesh.ARRAY_NORMAL] = surface.normals
		arrays[Mesh.ARRAY_INDEX] = indices
		var importer := ImporterMesh.new()
		importer.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays)
		importer.generate_lods(25.0, 60.0, [])
		_hand_mesh_cache[side] = importer.get_mesh()
	var hand := MeshInstance3D.new()
	hand.name = "Hand"
	hand.mesh = _hand_mesh_cache[side]
	hand.material_override = material
	hand.position = Vector3(side * 0.050, -0.260, -0.004)
	parent.add_child(hand)


static func book_config() -> Dictionary:
	return FACTORY.book_config()


static func bake_stats() -> String:
	return "SKIN BAKE | meshes=%d total=%.0f ms" % [_bake_n, _bake_us / 1000.0]


## One Node per character. Eleven quaternion writes a frame. Deliberately not a
## singleton manager for the proof of concept — see the migration note in the
## report; a manager iterating a flat array is the obvious next optimisation and
## it removes 16 script `_process` calls.
class SkinSync extends Node:
	var _skel: Skeleton3D
	var _joints: Array[Node3D]

	func setup(skel: Skeleton3D, joints: Array[Node3D]) -> void:
		_skel = skel
		_joints = joints

	func _process(_d: float) -> void:
		if not is_instance_valid(_skel):
			return
		for b in range(1, _joints.size()):
			_skel.set_bone_pose_rotation(b, _joints[b].quaternion)


# ============================== THE FIELD ====================================
## The anatomy, as implicit primitives. Each is a tapered capsule (a == b gives
## a sphere) evaluated in its own scaled space, so a torso can be wider than it
## is deep without a second primitive.
##   a, b   segment endpoints (rest space, feet at y = 0)
##   r0, r1 radius at a and at b
##   sc     per-axis scale of the space the capsule lives in
##   k      smooth-min radius against everything unioned before it
##   bone   owner bone (weights)
##   zone   material zone (UV.x)
##
## The numbers are lifted from the factory's own anatomy — HIP_PIVOT, the thigh
## and shin radii in `_build_legs`, the barrel radii and depth factor in
## `_torso_masses`, the girdle span in `_girdle_params`, the arm radii in
## `_build_arms` — so this is the same person, described as a field.
static func _prims(w: float, g: float) -> Array:
	var lg := 1.0 + (g - 1.0) * 0.55                        # limb thickness
	var dep := clampf(0.74 + (g - 1.0) * 0.50, 0.66, 0.94)   # trunk depth factor
	var belly := 1.0 + (g - 1.0) * 0.85
	var out: Array = []
	# BLEND DISCIPLINE. `k` is the only number in this file that can destroy the
	# figure, and the first bake proved it: at k = 0.05 the arms melted into the
	# chest and the whole trunk became one lozenge. A smin fillet of radius k
	# eats k of clearance on BOTH surfaces, so k must always be small against
	# the thinner of the two masses it joins. Rule used below:
	#   inside one mass (chest to chest, thigh to thigh)   k ~ 0.030-0.040
	#   mass to a limb that must stay readable as a limb    k ~ 0.014-0.020
	# Nothing here is above 0.040.

	# ---------- legs ----------
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var hb := B_HIP0 if side == 0 else B_HIP1
		var kb := B_KNEE0 if side == 0 else B_KNEE1
		var hx := sx * HIP_PIVOT.x
		# thigh: from inside the pelvis down to the knee, drifting outboard so
		# the two do not weld into a column where they pass the crotch.
		out.append(_cap(Vector3(hx, 0.880, 0.004), Vector3(hx * 1.06, 0.500, 0.008),
			0.092 * lg, 0.062 * lg, Vector3(1, 1, 1.06), 0.026, hb, 0))   # D-061: 88/68 -> 92/62, a quad and a knee
		# knee
		out.append(_cap(Vector3(hx * 1.06, 0.500, 0.008), Vector3(hx * 1.05, 0.452, 0.004),
			0.062 * lg, 0.058 * lg, Vector3(1, 1, 1.04), 0.018, kb, 0))
		# calf belly high, hard taper to a real ankle
		# M25 (D-053): the shin was one cone from r 70 below the knee to r 36 at
		# the ankle — a pipe. Now a slimmer shin, a gastrocnemius belly high on
		# the BACK of the calf, and a patella on the front of the knee.
		out.append(_cap(Vector3(hx * 1.04, 0.395, 0.014), Vector3(hx, 0.100, -0.004),
			0.058 * lg, 0.036 * lg, Vector3(1, 1, 1.05), 0.020, kb, 0))
		out.append(_cap(Vector3(hx * 1.02, 0.400, 0.040), Vector3(hx, 0.300, 0.034),
			0.058 * lg, 0.048 * lg, Vector3(1, 1, 1.0), 0.020, kb, 0))   # D-061: a fuller gastrocnemius
		out.append(_cap(Vector3(hx * 1.05, 0.470, -0.050), Vector3(hx * 1.05, 0.470, -0.050),
			0.032, 0.032, Vector3(1, 1.1, 0.8), 0.016, kb, 0))
		# D-062: A BOOT, not a loaf. The old foot was three round masses of the
		# same height — a bread roll with a sole. A boot is a shaft over an
		# ankle, a vamp that SLOPES from the instep (0.085) down to a low toe box
		# (0.045), a heel BLOCK behind it, and a thin welted sole.
		out.append(_cap(Vector3(hx, 0.150, 0.004), Vector3(hx, 0.078, 0.008),          # shaft to the ankle
			0.042, 0.046, Vector3(1.0, 1.0, 1.06), 0.016, kb, 0))
		out.append(_cap(Vector3(hx, 0.062, 0.010), Vector3(hx, 0.036, -0.150),         # vamp: instep sloping to the toe
			0.050, 0.038, Vector3(1.0, 0.68, 1.0), 0.016, kb, 0))
		out.append(_cap(Vector3(hx, 0.034, -0.148), Vector3(hx, 0.030, -0.178),        # toe box: low and narrowing
			0.038, 0.027, Vector3(1.0, 0.58, 1.0), 0.012, kb, 0))
		out.append(_cap(Vector3(hx, 0.040, 0.040), Vector3(hx, 0.040, 0.058),          # heel block: a step, k low
			0.042, 0.040, Vector3(0.94, 1.15, 0.80), 0.010, kb, 0))
		out.append(_cap(Vector3(hx, 0.010, -0.176), Vector3(hx, 0.010, 0.064),         # welted sole, thin
			0.048, 0.044, Vector3(1.0, 0.26, 1.0), 0.008, kb, 0))

	# ---------- pelvis ----------
	# widest at the trochanter and tapering BOTH ways. The factory learned in
	# M21 that an inverted cone gives everyone a peplum; a field cannot make
	# that mistake silently, because the taper IS the silhouette.
	out.append(_cap(Vector3(0, 1.010, 0.0), Vector3(0, 0.905, 0.006),
		0.130 * w * (1.0 + (g - 1.0) * 0.72), 0.143 * w * g,
		Vector3(1, 1, dep + 0.03), 0.038, B_ROOT, 0))   # D-061: 132/150 -> 130/143 (hips 0.378 -> ~0.36)
	out.append(_cap(Vector3(0, 0.905, 0.006), Vector3(0, 0.845, 0.008),
		0.143 * w * g, 0.118 * w, Vector3(1, 1, dep + 0.05), 0.034, B_ROOT, 0))
	# the seat: the pelvis being deeper BEHIND than in front, as one mass
	for gs: float in [-1.0, 1.0]:   # M25: two glutes with a cleft, not one pill
		out.append(_cap(Vector3(gs * 0.068 * w, 0.868, 0.064), Vector3(gs * 0.068 * w, 0.868, 0.064),
			0.090 * w, 0.090 * w, Vector3(1, 1.0, 0.58), 0.036, B_ROOT, 0))

	# ---------- trunk ----------
	# waist (narrowest), navel, chest, upper chest. Four sections, so the side
	# view gets a real taper instead of a barrel.
	# D-061 (Milad: "design better with more realistic body structure"). The
	# measured trunk (tools/body_measure.gd) was 0.27 m wide from the ribs to
	# the belt — no taper, a tube — and 15 % narrow against a 1.78 m man. A rib
	# cage is an EGG: widest at the mid-ribs, narrowing to the waist AND to the
	# clavicles. Now: ribs r 152 -> under-ribs 146 -> waist 124, so the side
	# and the front both read a taper, and the shoulder girdle sits on a chest
	# instead of a pipe.
	out.append(_cap(Vector3(0, 1.090, -0.006), Vector3(0, 1.005, -0.012),   # the waist, carried forward: a lumbar curve (D-062)
		0.124 * w * belly, 0.128 * w * belly,
		Vector3(1, 1, dep + 0.02), 0.034, B_TORSO, 0))
	out.append(_cap(Vector3(0, 1.190, -0.004), Vector3(0, 1.090, 0.0),   # under the ribs
		0.146 * w * belly, 0.124 * w * belly,
		Vector3(1, 1, dep + 0.02), 0.034, B_TORSO, 0))
	out.append(_cap(Vector3(0, 1.320, -0.010), Vector3(0, 1.190, -0.004),   # the rib cage
		0.148 * w, 0.146 * w * belly, Vector3(1, 1, dep), 0.034, B_TORSO, 0))
	# The top section TAPERS IN. It carried the full chest radius on the first
	# two bakes and the arms welded to it: the arm axis is at 0.183*w and its
	# radius 0.049, so its inner edge sits 14 mm INSIDE a 0.150*w chest and the
	# smin closed the armpit. Narrowing the section the arm passes is what buys
	# the notch back; the shoulder WIDTH still comes from the girdle, where it
	# anatomically comes from.
	# M25 r2: this capsule's hemispherical top reached 1.412 + 0.126 = 1.538 —
	# THAT was the neck-base mound (collar7/collar_probe: r 85 at y 1.53).
	# Squashed to 0.60 in y its top is 1.488, a shoulder line, and the
	# trapezius slopes below carry the neck down onto the deltoids.
	# r2: the top section narrows toward the clavicles (126 up top, 146 where it
	# meets the ribs) — the first cut carried the rib width up under the deltoid
	# and every plate showed a shoulder pad.
	out.append(_cap(Vector3(0, 1.412, -0.010), Vector3(0, 1.320, -0.010),
		0.126 * w, 0.146 * w, Vector3(1, 0.60, dep - 0.02), 0.034, B_TORSO, 0))
	# lats: the V of the back and the flank's taper, one flattened mass per side
	# from the armpit to the waist, inboard of the arm so the notch stays open.
	for ls: float in [-1.0, 1.0]:
		out.append(_cap(Vector3(ls * 0.118 * w, 1.300, 0.046), Vector3(ls * 0.096 * w, 1.110, 0.034),
			0.046 * w, 0.034 * w, Vector3(0.70, 1, 0.95), 0.030, B_TORSO, 0))
	# gut: forward-only, and only on the heavy end of the girth roll
	var gut := clampf((g - 0.85) / 0.30, 0.0, 1.0)   # D-061: none on a lean build, full by g 1.15
	out.append(_cap(Vector3(0, 1.130, -0.048 * belly), Vector3(0, 1.062, -0.046 * belly),
		0.086 * w * belly * gut, 0.082 * w * belly * gut, Vector3(1, 0.90, 0.50), 0.036,
		B_TORSO, 0))
	# pec swell forward, scapula plane aft — the side view lives or dies here
	# D-062: TWO pecs with a sternum between them, each a lens from the clavicle
	# corner down and in to the nipple line — the old single bar read as a chest plate.
	for ps: float in [-1.0, 1.0]:
		out.append(_cap(Vector3(ps * 0.078 * w, 1.348, -0.078), Vector3(ps * 0.044 * w, 1.296, -0.088),
			0.060 * w, 0.058 * w, Vector3(1.05, 0.92, 0.55), 0.036, B_TORSO, 0))
	out.append(_cap(Vector3(-0.056 * w, 1.330, 0.070), Vector3(0.056 * w, 1.330, 0.070),
		0.086 * w, 0.086 * w, Vector3(1, 1.10, 0.48), 0.038, B_TORSO, 0))
	# D-062: scapulae — two flat mounds on the upper back, the blades under a shirt.
	for ss: float in [-1.0, 1.0]:
		out.append(_cap(Vector3(ss * 0.074 * w, 1.318, 0.074), Vector3(ss * 0.060 * w, 1.236, 0.068),
			0.040 * w, 0.032 * w, Vector3(1.15, 1, 0.55), 0.032, B_TORSO, 0))

	# ---------- shoulder girdle: ONE mass, acromion to acromion ----------
	# This is M21's swept girdle written the way it always wanted to be. The
	# trapezius, both acromions and both deltoid caps are the same surface, so
	# there is no cap rim and no crease for a screenshot to find. It belongs to
	# the COLLAR, so it turns with the torso, and each arm smins into it at
	# k = 0.016 — a joint that deforms, not two balls that cross.
	# M25 (D-053): this was ONE capsule the full width of the shoulders at
	# 1.452, r 50 scaled 1.30 tall — a 65 mm bar from deltoid to deltoid, i.e.
	# the shoulder pad every plate showed. A clavicle is a thin bar 25 mm
	# below the deltoid tops; the slope from the neck down to the acromion is
	# what makes a shoulder read.
	# (r2: the clavicle bar went too — with the trapezius as a slope per side
	# there is nothing for it to bridge, and it read as a second dip.)
	# trapezius ramp: same surface, a taller section nearer the midline
	# M25 r2: the trapezius as a SLOPE, one capsule per side from the neck
	# base (top 1.502) down to the acromion (top 1.468), where it meets the
	# deltoid's 1.475. A horizontal bar here, at any radius, either mounds
	# the neck or leaves a dip before the shoulder cap — the puffed sleeve of
	# body8/after/back.png.
	for ts: float in [-1.0, 1.0]:
		out.append(_cap(Vector3(ts * 0.060 * w, 1.462, 0.012), Vector3(ts * 0.178 * w, 1.422, 0.006),
			0.040, 0.040, Vector3(1, 1, 1.05), 0.030, B_COLLAR, 0))   # D-061: ends at the acromion (0.192)
	# neck. M23 (D-102): r 47/57 -> 58/66 mm, deeper than wide. At 47 mm the
	# neck read as a stalk under the head at `face`; an adult neck is ~38 cm
	# around (r ~60 mm) and the collar ring below grows with it.
	out.append(_cap(Vector3(0, 1.605, 0.006), Vector3(0, 1.462, 0.012),
		0.058, 0.062, Vector3(1, 1, 1.12), 0.026, B_HEAD, 0))   # M25: base 66 -> 62, less flare
	# ---------- garment features, as FIELD not as parts ----------
	# A collar, a belt welt and two cuffs. The factory spends 6-10 separate
	# MeshInstance3Ds on these and each one is a rim that can lift off the
	# surface it sits on (D-081 was exactly that, on a boot shaft). Here they
	# are ridges IN the same surface: they cost no draw call, they cannot lift,
	# and they cannot be left behind when the body deforms.
	# M25: the D-102 "collar ring" (r 63..78 at 1.466..1.508) is gone. It was a
	# flare at the neck base that made the mound; the collar is a shell now.
	out.append(_cap(Vector3(0, 1.058, 0.0), Vector3(0, 1.016, 0.0),
		0.134 * w * belly, 0.132 * w * belly, Vector3(1, 1, dep + 0.03), 0.008,
		B_TORSO, 0))

	# ---------- arms ----------
	for side in 2:
		var ax := -1.0 if side == 0 else 1.0
		var sb := B_SH0 if side == 0 else B_SH1
		var eb := B_EL0 if side == 0 else B_EL1
		var sx := ax * SHOULDER_X * w
		# deltoid cap, then the upper arm proper. Both k = 0.016: below the
		# armpit the arm has to read as an arm, and 50 mm of fillet is what ate
		# it on the first bake.
		# M25: the deltoid's top was at 1.505 (centre 1.452 + r 53): five cm
		# above where an acromion sits on a 1.75 m body, hence the hunched square
		# shoulder. Centre 1.425, top 1.475, under the trapezius' 1.492.
		out.append(_cap(Vector3(sx - ax * 0.004, 1.418, 0.002), Vector3(sx + ax * 0.010, 1.340, 0.004),
			0.046 * lg, 0.045 * lg, Vector3(1.0, 1.18, 0.97), 0.016, sb, 0))   # D-062: a taller cap rounds the acromion corner
		out.append(_cap(Vector3(sx + ax * 0.010, 1.340, 0.004),
			Vector3(sx + ax * 0.022, 1.175, 0.006),
			0.046 * lg, 0.039 * lg, Vector3.ONE, 0.014, sb, 0))   # M25: bicep -> elbow taper
		out.append(_cap(Vector3(sx + ax * 0.024, 1.165, 0.028), Vector3(sx + ax * 0.024, 1.165, 0.028),
			0.030 * lg, 0.030 * lg, Vector3.ONE, 0.014, eb, 0))   # M25: the elbow's point
		# forearm: elbow swell, taper to a wrist. It SPLAYS outboard, and that
		# is load-bearing rather than cosmetic — at the factory's offsets the
		# hand hangs 13 mm INSIDE the thigh, which for rigid parts is a hidden
		# intersection and for a field is a webbed hand. A field cannot fake
		# clearance it does not have, so the arm has to actually clear the leg.
		out.append(_cap(Vector3(sx + ax * 0.026, 1.150, 0.006),   # M25: forearm belly, then
			Vector3(sx + ax * 0.036, 1.060, 0.002),                 # a taper to a FLAT wrist
			0.044 * lg, 0.040 * lg, Vector3.ONE, 0.014, eb, 0))
		out.append(_cap(Vector3(sx + ax * 0.036, 1.060, 0.002),
			Vector3(sx + ax * 0.050, 0.905, -0.004),
			0.040 * lg, 0.029 * lg, Vector3(1, 1, 0.85), 0.014, eb, 0))
		# cuff welt
		out.append(_cap(Vector3(sx + ax * 0.048, 0.938, -0.003),
			Vector3(sx + ax * 0.050, 0.908, -0.004),
			0.031 * lg, 0.030 * lg, Vector3(1, 1, 0.75), 0.006, eb, 0))   # M25: a wrist is 55 x 40
		# Hands are attached at forearm joints with their own finer mesh.
	return out


## Material zone for a rest-space vertex, given the bone that owns it.
##
## The first bake assigned zones by nearest primitive and the shirt/trouser line
## came out as voxel confetti: on the surface where two masses meet, the two
## distances are equal to within a rounding error, so the winner alternates cell
## by cell. Zones are therefore GEOMETRIC RULES on the owner bone plus a height,
## which is stable, and which puts a hem exactly where a hem goes instead of
## wherever the field happened to tie.
static func _zone_of(bone: int, p: Vector3) -> int:
	match bone:
		B_KNEE0, B_KNEE1:
			if p.y < 0.033: return Z_SOLE
			if p.y < 0.118: return Z_SHOE
			return Z_SHIN
		B_HIP0, B_HIP1:
			return Z_THIGH_LO if p.y < 0.680 else Z_THIGH_HI
		B_COLLAR:
			if p.y > 1.468: return Z_COLLAR
			return _trunk_zone(p)
		B_ROOT, B_TORSO:
			# ONE rule for the whole trunk, keyed on height only. Keying it on
			# which of root/torso/collar won the nearest-primitive test put
			# voxel confetti along the shirt hem: on the surface where two
			# masses meet the distances tie to within a rounding error, so the
			# winner alternated cell by cell. A hem is a horizontal line on a
			# real garment; here it is a horizontal line by construction.
			if p.y < 0.958: return Z_PELVIS
			if p.y < 1.012: return Z_HIPBAND
			if p.y < 1.062: return Z_BELT
			return _trunk_zone(p)
		B_HEAD:
			return Z_COLLAR if p.y < 1.576 else Z_NECK   # M24: the collar band's top edge
		B_SH0, B_SH1:
			return Z_SLEEVE if p.y > 1.300 else Z_UPARM
		B_EL0, B_EL1:
			if p.y > 0.938: return Z_FOREARM
			if p.y > 0.906: return Z_CUFF
			return Z_HAND
	return Z_SHIRT_F


## -Z IS FORWARD on this body (the pec swell sits at z = −0.072 and the scapula
## plane at +0.070), so the side seam is the z = 0 plane and the V-neck notch is
## a wedge on the front of it.
##
## The V is CUT into the shared mesh for everybody and painted shirt-colour for
## everybody but SCRUBS. That is the pattern the whole zone system runs on: a
## boundary is baked once into the geometry that the entire population shares,
## and only its colour is per-character. A boundary that had to be per-outfit
## would multiply the bake by the wardrobe.
const V_APEX := 1.400        # bottom of the notch
const V_SLOPE := 0.55        # half-width gained per metre of height

static func _trunk_zone(p: Vector3) -> int:
	if p.z >= 0.0:
		return Z_SHIRT_B
	if p.y > V_APEX and p.y < 1.512 and absf(p.x) < (p.y - V_APEX) * V_SLOPE:
		return Z_CHEST_V
	return Z_SHIRT_F


## Bind-pose micro UV (ARRAY_TEX_UV2, M24): a cylindrical unwrap about the axis
## of the limb the vertex belongs to, in tiles of MICRO_TILE metres, with an
## INTEGER number of tiles around each region so the seam at the back closes.
## The shared character material tiles its skin/cloth micro-normal on this; the
## tangent frame is derived per pixel in the shader, so the bake stores none.
const MICRO_TILE := 0.08

static func _micro_around(bone: int) -> int:
	match bone:
		B_SH0, B_EL0, B_SH1, B_EL1:
			return 3
		B_HIP0, B_KNEE0, B_HIP1, B_KNEE1:
			return 6
	return 12   # trunk, collar and the neck share one unwrap: no ring at the throat


static func _micro_uv(bone: int, p: Vector3) -> Vector2:
	var ax := 0.0
	match bone:
		B_SH0, B_EL0:
			ax = -(SHOULDER_X + 0.012)
		B_SH1, B_EL1:
			ax = SHOULDER_X + 0.012
		B_HIP0, B_KNEE0:
			ax = -0.092
		B_HIP1, B_KNEE1:
			ax = 0.092
	var u := (atan2(p.x - ax, -p.z) / TAU + 0.5) * float(_micro_around(bone))
	return Vector2(u, p.y / MICRO_TILE)


## The seam. A triangle whose corners straddle u = 0/around gets the whole
## texture streaked across it and a bright line down the spine (collar7/
## back.png). Corners on the low side are lifted by `around` — the texture
## repeats there anyway — and the caller splits those vertices. Returns which
## corners moved; `mus` is edited in place.
static func _micro_seam(mus: Array, b0: int, b1: int, b2: int) -> Array:
	var out: Array = [false, false, false]
	var ar := _micro_around(b0)
	if _micro_around(b1) != ar or _micro_around(b2) != ar:
		return out
	var umin := minf(minf((mus[0] as Vector2).x, (mus[1] as Vector2).x), (mus[2] as Vector2).x)
	var umax := maxf(maxf((mus[0] as Vector2).x, (mus[1] as Vector2).x), (mus[2] as Vector2).x)
	if umax - umin <= float(ar) * 0.5:
		return out
	for e in 3:
		var m: Vector2 = mus[e]
		if m.x < float(ar) * 0.5:
			mus[e] = Vector2(m.x + float(ar), m.y)
			out[e] = true
	return out


## UV for a vertex in zone `z`: the column that names the zone, and the row that
## says how far up the zone's own y-range the vertex sits.
static func _zone_uv(z: int, p: Vector3) -> Vector2:
	var r: Array = ZV[z]
	var lo := float(r[0])
	return Vector2((float(z) + 0.5) / float(PAL_W),
		clampf((p.y - lo) / maxf(float(r[1]) - lo, 1e-4), 0.0, 1.0))



static func _cap(a: Vector3, b: Vector3, r0: float, r1: float, sc: Vector3,
		k: float, bone: int, zone: int) -> Dictionary:
	var ab := (b - a) / sc
	# The radius is stored AS AUTHORED. It used to be divided by min(sc) — an
	# error that inflated every mass by 1/min(sc) along its unscaled axes, so a
	# trunk authored at 0.150 half-width with a 0.74 depth factor came out 0.203
	# wide, a pec lens came out 2.2x, and a shoe sole came out 2.8x. That single
	# line is what made the torso a pillow, and it is what closed the 34 mm gap
	# between a hanging hand and the thigh: the hand fused into the leg, the
	# elbow bone therefore owned trouser vertices, and a swinging arm dragged
	# them out into a fan. `ms` still scales the RETURNED value, which is what
	# keeps it a conservative distance rather than a bare implicit value.
	return {"a": a, "sc": sc, "ab": ab, "l2": ab.length_squared(),
		"r0": r0, "r1": r1,
		"ms": minf(minf(sc.x, sc.y), sc.z), "k": k, "bone": bone, "zone": zone,
		"lo": Vector3(minf(a.x, b.x), minf(a.y, b.y), minf(a.z, b.z)),
		"hi": Vector3(maxf(a.x, b.x), maxf(a.y, b.y), maxf(a.z, b.z)),
		"rmax": maxf(r0, r1) * maxf(maxf(sc.x, sc.y), sc.z)}


## Distance from `p` to one primitive. Not an exact SDF for a tapered capsule

# =========================== THE FIELD, FLATTENED ============================
## The anatomy above is authored as Dictionaries because a human has to read and
## tune it. The mesher cannot afford them: a Dictionary lookup in an inner loop
## that runs ten million times is the difference between a 90-second bake and a
## two-second one. So the prim list is flattened ONCE into a stride-16
## PackedFloat32Array and every hot loop indexes that.
##   0..2 a | 3..5 sc | 6..8 ab | 9 l2 | 10 r0 | 11 r1 | 12 ms | 13 k
##   14 bone | 15 zone
const PS := 16


static func _flatten(prims: Array) -> PackedFloat32Array:
	var f := PackedFloat32Array()
	f.resize(prims.size() * PS)
	for i in prims.size():
		var pr: Dictionary = prims[i]
		var a: Vector3 = pr["a"]; var sc: Vector3 = pr["sc"]; var ab: Vector3 = pr["ab"]
		var o := i * PS
		f[o] = a.x; f[o + 1] = a.y; f[o + 2] = a.z
		f[o + 3] = sc.x; f[o + 4] = sc.y; f[o + 5] = sc.z
		f[o + 6] = ab.x; f[o + 7] = ab.y; f[o + 8] = ab.z
		f[o + 9] = pr["l2"]; f[o + 10] = pr["r0"]; f[o + 11] = pr["r1"]
		f[o + 12] = pr["ms"]; f[o + 13] = pr["k"]
		f[o + 14] = float(int(pr["bone"])); f[o + 15] = float(int(pr["zone"]))
	return f


## Distance from `p` to prim `o` (a byte offset into the flat array). Not an
## exact SDF for a tapered capsule (the true one needs the tangent cone) but the
## ZERO SET is exact, which is all a mesher needs.
static func _fd(fp: PackedFloat32Array, o: int, px: float, py: float,
		pz: float) -> float:
	var qx := (px - fp[o]) / fp[o + 3]
	var qy := (py - fp[o + 1]) / fp[o + 4]
	var qz := (pz - fp[o + 2]) / fp[o + 5]
	var t := 0.0
	var l2 := fp[o + 9]
	if l2 > 1e-9:
		t = clampf((qx * fp[o + 6] + qy * fp[o + 7] + qz * fp[o + 8]) / l2, 0.0, 1.0)
	qx -= fp[o + 6] * t; qy -= fp[o + 7] * t; qz -= fp[o + 8] * t
	return (sqrt(qx * qx + qy * qy + qz * qz)
		- (fp[o + 10] + (fp[o + 11] - fp[o + 10]) * t)) * fp[o + 12]


## Polynomial smooth-min. C1 everywhere, which is the whole reason there is no
## crossing curve on this body.
static func _smin(a: float, b: float, k: float) -> float:
	if k <= 0.0:
		return minf(a, b)
	var h := clampf(0.5 + 0.5 * (b - a) / k, 0.0, 1.0)
	return lerpf(b, a, h) - k * h * (1.0 - h)


static func _field(fp: PackedFloat32Array, p: Vector3) -> float:
	var d := 1.0
	var n := fp.size() / PS
	for i in n:
		var o := i * PS
		d = _smin(d, _fd(fp, o, p.x, p.y, p.z), fp[o + 13])
	return d


# ============================== THE BAKE =====================================
static func _mesh_for(w: float, g: float) -> ArrayMesh:
	# Six buckets cover the whole population: build is drawn from [0.92, 1.12]
	# and girth from [0.86, 1.30]. Bucketing is what makes the bake a fixed cost
	# instead of a per-pedestrian cost.
	var bw := 0 if w < 1.02 else 1
	var bg := 0 if g < 1.00 else (1 if g < 1.15 else 2)
	var key := "%d_%d" % [bw, bg]
	if _mesh_cache.has(key):
		return _mesh_cache[key]
	var cw: float = [0.97, 1.07][bw]
	var cg: float = [0.93, 1.07, 1.22][bg]
	# Disk cache. The bake is deterministic, so the SECOND boot pays nothing.
	# This is a build artifact in user://, not an authored asset — the pipeline
	# stays "generated in code", it just stops re-deriving the same bytes.
	var path := "user://skin_%s_v%d.res" % [key, CACHE_VER]
	if not _no_disk and ResourceLoader.exists(path):
		var cached := ResourceLoader.load(path)
		if cached is ArrayMesh:
			_mesh_cache[key] = cached
			return cached
	var t0 := Time.get_ticks_usec()
	var mesh := _bake(cw, cg)
	_bake_us += Time.get_ticks_usec() - t0
	_bake_n += 1
	if not _no_disk:
		ResourceSaver.save(mesh, path)
	_mesh_cache[key] = mesh
	return mesh


## Sample the smin union of `prims` onto a regular grid. Extracted from `_bake`
## verbatim so the WARDROBE can reuse the identical body field: a garment that
## sits at a constant offset from the body must be measuring the same field the
## body's own isosurface came from, or the offset is a fiction.
## Returns {f, lo, nx, ny, nz, syz}.
static func _field_grid(prims: Array, fp: PackedFloat32Array,
		vox: float) -> Dictionary:
	var np := prims.size()
	# ---- grid bounds from the primitives themselves, plus two cells of air so
	# no surface can touch the boundary (an open surface is not a closed one).
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for pr: Dictionary in prims:
		# radii live in prim space; 1.35 covers the largest axis scale in use
		var m: float = (float(pr["rmax"]) + float(pr["k"])) * 1.35
		var pad := Vector3(m, m, m)
		lo = lo.min((pr["lo"] as Vector3) - pad)
		hi = hi.max((pr["hi"] as Vector3) + pad)
	lo -= Vector3(vox, vox, vox) * 2.0
	hi += Vector3(vox, vox, vox) * 2.0
	var nx := int(ceil((hi.x - lo.x) / vox)) + 1
	var ny := int(ceil((hi.y - lo.y) / vox)) + 1
	var nz := int(ceil((hi.z - lo.z) / vox)) + 1
	var syz := ny * nz

	# ---- fill the field. Per PRIMITIVE over its own AABB, not per sample over
	# every primitive: outside a primitive's box the smin is a no-op, so the
	# work collapses from nx*ny*nz*|prims| to the sum of the primitive volumes.
	# An earlier version kept a `hit` byte per grid point so the mesher could
	# skip pure air by sampling two of a cell's eight corners. It was removed on
	# suspicion of dropping cells; measurement cleared it (vertex counts were
	# identical either way, because the per-primitive AABB is padded past the
	# blend radius) but it is 100 ms of a once-per-install bake against a
	# correctness argument that has to be made by inspection. Not worth it.
	var f := PackedFloat32Array()
	f.resize(nx * ny * nz)
	f.fill(1.0)
	for pi in np:
		var pr: Dictionary = prims[pi]
		var o := pi * PS
		var m: float = (float(pr["rmax"]) + float(pr["k"])) * 1.35 + vox
		var plo: Vector3 = (pr["lo"] as Vector3) - Vector3(m, m, m)
		var phi: Vector3 = (pr["hi"] as Vector3) + Vector3(m, m, m)
		var i0 := maxi(0, int(floor((plo.x - lo.x) / vox)))
		var i1 := mini(nx - 1, int(ceil((phi.x - lo.x) / vox)))
		var j0 := maxi(0, int(floor((plo.y - lo.y) / vox)))
		var j1 := mini(ny - 1, int(ceil((phi.y - lo.y) / vox)))
		var k0 := maxi(0, int(floor((plo.z - lo.z) / vox)))
		var k1 := mini(nz - 1, int(ceil((phi.z - lo.z) / vox)))
		var kk := fp[o + 13]
		var ax := fp[o]; var ay := fp[o + 1]; var az := fp[o + 2]
		var sx := fp[o + 3]; var sy := fp[o + 4]; var sz := fp[o + 5]
		var bx := fp[o + 6]; var by := fp[o + 7]; var bz := fp[o + 8]
		var l2 := fp[o + 9]; var r0 := fp[o + 10]; var dr := fp[o + 11] - r0
		var ms := fp[o + 12]
		for i in range(i0, i1 + 1):
			var qx0 := (lo.x + float(i) * vox - ax) / sx
			var bi := i * syz
			for j in range(j0, j1 + 1):
				var qy0 := (lo.y + float(j) * vox - ay) / sy
				var bj := bi + j * nz
				for k in range(k0, k1 + 1):
					var qz0 := (lo.z + float(k) * vox - az) / sz
					var t := 0.0
					if l2 > 1e-9:
						t = clampf((qx0 * bx + qy0 * by + qz0 * bz) / l2, 0.0, 1.0)
					var dx := qx0 - bx * t
					var dy := qy0 - by * t
					var dz := qz0 - bz * t
					var d := (sqrt(dx * dx + dy * dy + dz * dz) - (r0 + dr * t)) * ms
					var idx := bj + k
					var cur := f[idx]
					if d < cur + kk:
						var h := clampf(0.5 + 0.5 * (d - cur) / kk, 0.0, 1.0)
						f[idx] = (d + (cur - d) * h) - kk * h * (1.0 - h)
	return {"f": f, "lo": lo, "nx": nx, "ny": ny, "nz": nz, "syz": syz}


## Naive surface nets + Taubin + gradient re-projection + smoothed normals, on
## any grid. Extracted from `_bake` unchanged so the wardrobe surface is
## polygonised by literally the same code as the body — a garment meshed by a
## second, similar-looking algorithm is a garment that will disagree with the
## body somewhere and no reviewer will ever find out where.
## Returns {} for a grid with no isosurface in it.
static func _polygonise(f: PackedFloat32Array, lo: Vector3, nx: int, ny: int,
		nz: int, syz: int, vox: float) -> Dictionary:
	# ---- naive surface nets: one vertex per sign-changing cell. Corner offsets
	# are flat ints into `f`, so the inner gather is eight array reads.
	var co := PackedInt32Array([0, 1, nz, nz + 1, syz, syz + 1, syz + nz,
		syz + nz + 1])
	# the 12 cube edges, as (corner_a, corner_b) with corner = 4*i + 2*j + k
	var ea := PackedInt32Array([0, 2, 4, 6, 0, 1, 4, 5, 0, 1, 2, 3])
	var eb := PackedInt32Array([1, 3, 5, 7, 2, 3, 6, 7, 4, 5, 6, 7])
	var cell := PackedInt32Array()
	cell.resize((nx - 1) * (ny - 1) * (nz - 1))
	cell.fill(-1)
	var cyz := (ny - 1) * (nz - 1)
	var cz := nz - 1
	var verts := PackedVector3Array()
	var cv := PackedFloat32Array(); cv.resize(8)
	for i in nx - 1:
		var bi := i * syz
		var ci := i * cyz
		for j in ny - 1:
			var bj := bi + j * nz
			var cj := ci + j * cz
			for k in cz:
				var base := bj + k
				var neg := 0
				for c in 8:
					var d := f[base + co[c]]
					cv[c] = d
					if d < 0.0:
						neg += 1
				if neg == 0 or neg == 8:
					continue
				var sx := 0.0; var sy := 0.0; var sz := 0.0
				var n := 0
				for e in 12:
					var ca := ea[e]; var cb := eb[e]
					var da := cv[ca]; var db := cv[cb]
					if (da < 0.0) == (db < 0.0):
						continue
					var t := da / (da - db)
					sx += float((ca >> 2) & 1) + t * float(((cb >> 2) & 1) - ((ca >> 2) & 1))
					sy += float((ca >> 1) & 1) + t * float(((cb >> 1) & 1) - ((ca >> 1) & 1))
					sz += float(ca & 1) + t * float((cb & 1) - (ca & 1))
					n += 1
				var inv := 1.0 / float(n)
				cell[cj + k] = verts.size()
				verts.append(Vector3(lo.x + (float(i) + sx * inv) * vox,
					lo.y + (float(j) + sy * inv) * vox,
					lo.z + (float(k) + sz * inv) * vox))

	# ---- quads across every sign-changing grid edge whose four adjacent cells
	# all exist. Winding follows the sign direction, so the surface comes out
	# consistently outward without a post-hoc flip.
	var idx := PackedInt32Array()
	for i in range(1, nx - 1):
		var bi := i * syz
		var ci := i * cyz
		for j in range(1, ny - 1):
			var bj := bi + j * nz
			var cj := ci + j * cz
			for k in range(1, cz):
				var base := bj + k
				var inside := f[base] < 0.0
				var c000 := cj + k                       # cell (i,   j,   k)
				if inside != (f[base + syz] < 0.0):      # +x edge
					_quad(idx, cell, c000 - cz - 1, c000 - 1, c000, c000 - cz, inside)
				if inside != (f[base + nz] < 0.0):       # +y edge
					_quad(idx, cell, c000 - cyz - 1, c000 - cyz, c000, c000 - 1, inside)
				if inside != (f[base + 1] < 0.0):        # +z edge
					_quad(idx, cell, c000 - cyz - cz, c000 - cz, c000, c000 - cyz, inside)

	var nv := verts.size()
	if nv == 0 or idx.size() == 0:
		return {}

	# ---- adjacency straight off the index buffer. No de-duplication on
	# purpose: on a closed quad mesh every edge, diagonals included, is visited
	# exactly twice, so the multiplicities are uniform and the Laplacian average
	# is unaffected.
	var nbr := PackedInt32Array()
	var ncnt := PackedInt32Array(); ncnt.resize(nv)
	var t3 := idx.size() / 3
	for t in t3:
		ncnt[idx[t * 3]] += 2
		ncnt[idx[t * 3 + 1]] += 2
		ncnt[idx[t * 3 + 2]] += 2
	var nstart := PackedInt32Array(); nstart.resize(nv + 1)
	var run := 0
	for v in nv:
		nstart[v] = run
		run += ncnt[v]
	nstart[nv] = run
	nbr.resize(run)
	var fill := PackedInt32Array(); fill.resize(nv)
	for t in t3:
		for e in 3:
			var a := idx[t * 3 + e]
			var b := idx[t * 3 + (e + 1) % 3]
			nbr[nstart[a] + fill[a]] = b; fill[a] += 1
			nbr[nstart[b] + fill[b]] = a; fill[b] += 1

	# ---- Taubin smoothing (shrink then un-shrink), then one Newton step back
	# onto the isosurface sampled from the grid. The stair-step goes; the volume
	# stays.
	for p in SMOOTH_PASSES:
		verts = _laplace(verts, nbr, nstart, 0.62)
		verts = _laplace(verts, nbr, nstart, -0.64)
	for v in nv:
		var p := verts[v]
		var d := _sample(f, lo, nx, ny, nz, syz, p)
		var gx := _sample(f, lo, nx, ny, nz, syz, p + Vector3(vox, 0, 0)) \
			- _sample(f, lo, nx, ny, nz, syz, p - Vector3(vox, 0, 0))
		var gy := _sample(f, lo, nx, ny, nz, syz, p + Vector3(0, vox, 0)) \
			- _sample(f, lo, nx, ny, nz, syz, p - Vector3(0, vox, 0))
		var gz := _sample(f, lo, nx, ny, nz, syz, p + Vector3(0, 0, vox)) \
			- _sample(f, lo, nx, ny, nz, syz, p - Vector3(0, 0, vox))
		var gr := Vector3(gx, gy, gz)
		var gl := gr.length()
		# CLAMP THE NEWTON STEP TO ONE CELL, and refuse it outright where the
		# grid holds no field. Unclamped, `d / gl` is a division by a gradient
		# that goes to zero in any region the per-primitive fill never touched:
		# a vertex that Taubin nudged into such a cell reads d = 1.0 with
		# gl ~ 1e-5 and is flung metres away. On the body that never fired
		# (2 cells of air pad everywhere); on a garment piece it did, and it is
		# what put a belt vertex at x = −0.324 on a man 0.16 m wide, and what
		# put the yoke's worst back-face vertex 68 mm above the yoke.
		if gl > 1e-6 and absf(d) < vox * 2.0:
			var stepv := gr * (d / gl)
			var sl := stepv.length()
			if sl > vox:
				stepv *= vox / sl
			verts[v] = p - stepv

	# ---- normals: area-weighted face normals, then smoothed over the same
	# adjacency. On a surface this dense that is indistinguishable from the
	# analytic field gradient and about forty times cheaper.
	var normals := PackedVector3Array(); normals.resize(nv)
	for t in t3:
		var a := idx[t * 3]; var b := idx[t * 3 + 1]; var c := idx[t * 3 + 2]
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		normals[a] += fn; normals[b] += fn; normals[c] += fn
	for v in nv:
		normals[v] = normals[v].normalized()
	for p in 2:
		var sm := PackedVector3Array(); sm.resize(nv)
		for v in nv:
			var acc := normals[v]
			for q in range(nstart[v], nstart[v + 1]):
				acc += normals[nbr[q]] * 0.25
			sm[v] = acc.normalized()
		normals = sm

	return {"verts": verts, "idx": idx, "normals": normals, "nbr": nbr,
		"nstart": nstart}


## The same fill, on a grid whose bounds are borrowed from another one. The
## trunk-only field must be sampled by the identical index arithmetic as the
## full field or a garment built on one and weighted from the other would be
## offset by whatever the two grids' origins differ by.
static func _field_grid_on(prims: Array, fp: PackedFloat32Array, vox: float,
		like: Dictionary) -> Dictionary:
	var lo: Vector3 = like["lo"]
	var nx: int = like["nx"]; var ny: int = like["ny"]; var nz: int = like["nz"]
	var syz: int = like["syz"]
	var f := PackedFloat32Array()
	f.resize(nx * ny * nz)
	f.fill(1.0)
	for pi in prims.size():
		var pr: Dictionary = prims[pi]
		var o := pi * PS
		var m: float = (float(pr["rmax"]) + float(pr["k"])) * 1.35 + vox
		var plo: Vector3 = (pr["lo"] as Vector3) - Vector3(m, m, m)
		var phi: Vector3 = (pr["hi"] as Vector3) + Vector3(m, m, m)
		var i0 := maxi(0, int(floor((plo.x - lo.x) / vox)))
		var i1 := mini(nx - 1, int(ceil((phi.x - lo.x) / vox)))
		var j0 := maxi(0, int(floor((plo.y - lo.y) / vox)))
		var j1 := mini(ny - 1, int(ceil((phi.y - lo.y) / vox)))
		var k0 := maxi(0, int(floor((plo.z - lo.z) / vox)))
		var k1 := mini(nz - 1, int(ceil((phi.z - lo.z) / vox)))
		var kk := fp[o + 13]
		for i in range(i0, i1 + 1):
			var px := lo.x + float(i) * vox
			var bi := i * syz
			for j in range(j0, j1 + 1):
				var py := lo.y + float(j) * vox
				var bj := bi + j * nz
				for k in range(k0, k1 + 1):
					var d := _fd(fp, o, px, py, lo.z + float(k) * vox)
					var idx := bj + k
					f[idx] = _smin(f[idx], d, kk)
	return {"f": f, "lo": lo, "nx": nx, "ny": ny, "nz": nz, "syz": syz}


static func _bake(w: float, g: float) -> ArrayMesh:
	var prims := _prims(w, g)
	var fp := _flatten(prims)
	var np := prims.size()
	var bg := _field_grid(prims, fp, VOX)
	var f: PackedFloat32Array = bg["f"]
	var lo: Vector3 = bg["lo"]
	var nx: int = bg["nx"]; var ny: int = bg["ny"]; var nz: int = bg["nz"]
	var syz: int = bg["syz"]

	var pg := _polygonise(f, lo, nx, ny, nz, syz, VOX)
	if pg.is_empty():
		push_error("skinned_character: empty bake")
		return ArrayMesh.new()
	var verts: PackedVector3Array = pg["verts"]
	var idx: PackedInt32Array = pg["idx"]
	var normals: PackedVector3Array = pg["normals"]
	var nbr: PackedInt32Array = pg["nbr"]
	var nstart: PackedInt32Array = pg["nstart"]
	var nv := verts.size()
	var t3 := idx.size() / 3

	# ---- zones and owner bones: nearest primitive wins
	var owner := PackedInt32Array(); owner.resize(nv)
	for v in nv:
		var p := verts[v]
		var best := 1e9
		var bo := B_TORSO
		for pi in np:
			var o := pi * PS
			var d := _fd(fp, o, p.x, p.y, p.z)
			if d < best:
				best = d
				bo = int(fp[o + 14])
		owner[v] = bo

	# Owner smoothing — a majority vote over the mesh neighbourhood, three
	# passes. Nearest-primitive is right almost everywhere and catastrophically
	# wrong in a few places: where a hanging hand passes a thigh, thigh surface
	# vertices are genuinely nearer to the hand than to their own leg, and a raw
	# assignment paints a skin-coloured smear down the trouser. Vote it out.
	for p_i in 3:
		var nxt := PackedInt32Array()
		nxt.resize(nv)
		var tally := PackedInt32Array()
		tally.resize(BONE_N)
		for v in nv:
			for b in BONE_N:
				tally[b] = 0
			tally[owner[v]] = 2                     # self counts double
			for q in range(nstart[v], nstart[v + 1]):
				tally[owner[nbr[q]]] += 1
			var bb := owner[v]
			var bc := -1
			for b in BONE_N:
				if tally[b] > bc:
					bc = tally[b]
					bb = b
			nxt[v] = bb
		owner = nxt

	# CONNECTED-COMPONENT FILTER. The majority vote clears salt-and-pepper but
	# not a coherent patch, and a coherent patch is what actually tears: nine
	# vertices of trouser that the nearest-primitive test handed to the elbow
	# get 100% elbow weight, and when the arm swings they leave the leg behind
	# as a fan of long thin triangles. Every bone is allowed exactly ONE island
	# on the surface; anything else is dissolved into its neighbours.
	owner = _one_island(owner, nbr, nstart, nv)


	var wt := _weights(verts, owner, nbr, nstart, w)
	var bones: PackedInt32Array = wt[0]
	var wts: PackedFloat32Array = wt[1]

	# ---- CUT THE GARMENT PLANES.
	# Zone boundaries are horizontal planes in rest space; the mesh is not, so a
	# hem falls wherever the triangles happen to lie and comes out as an 18 mm
	# sawtooth — the single loudest defect on the first three bakes. Pulling the
	# nearest vertices onto the plane does NOT fix it: where a plane passes
	# THROUGH a vertex row the row's own vertices alternate above and below, and
	# the "ring" zigzags through them. The only thing that fixes it is cutting
	# the triangles, so the boundary is a real edge loop lying exactly in the
	# plane. Ten planes, one pass each; each pass turns the ~2% of triangles
	# that straddle into three.
	var pln := PackedFloat32Array()
	for yv: float in [0.033, 0.118, 0.680, 0.906, 0.938, 0.958, 1.012, 1.062,
			1.300, 1.400, 1.468, 1.512, 1.576]:
		pln.append_array(PackedFloat32Array([0.0, 1.0, 0.0, yv]))
	pln.append_array(PackedFloat32Array([0.0, 0.0, 1.0, 0.0]))   # the side seam
	var vn := Vector2(1.0, -V_SLOPE).normalized()                # the V flanks
	for sx: float in [1.0, -1.0]:
		pln.append_array(PackedFloat32Array([sx * vn.x, vn.y, 0.0,
			vn.y * V_APEX]))
	var cut := _cut(verts, normals, bones, wts, owner, idx, pln)
	verts = cut[0]; normals = cut[1]; bones = cut[2]; wts = cut[3]
	owner = cut[4]; idx = cut[5]
	nv = verts.size()
	t3 = idx.size() / 3

	# ---- ZONES ARE PER TRIANGLE, NOT PER VERTEX, and the vertices along a zone
	# boundary are split so every triangle's three corners agree.
	#
	# Per-vertex zones interpolate across the triangles that straddle a hem, and
	# a NEAREST palette lookup then flips at the halfway point — so the shirt's
	# bottom edge landed wherever UV.x happened to cross a texel boundary and
	# came out as an 18 mm sawtooth. Deciding the zone at the CENTROID and
	# duplicating the shared vertices makes the hem exactly the ring of mesh
	# edges the snap pass already straightened. It costs the ~6% of vertices
	# that sit on a boundary, and it is the difference between a garment edge
	# and a torn one.
	var vmap := {}
	var v2 := PackedVector3Array()
	var n2 := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var mu2 := PackedVector2Array()   # M24: micro UV (ARRAY_TEX_UV2)
	var b2 := PackedInt32Array()
	var w2 := PackedFloat32Array()
	var i2 := PackedInt32Array()
	i2.resize(idx.size())
	for t in t3:
		var a := idx[t * 3]; var b := idx[t * 3 + 1]; var c := idx[t * 3 + 2]
		var cen := (verts[a] + verts[b] + verts[c]) / 3.0
		# the owner that two of three corners agree on, else the first corner's
		var ow := owner[a]
		if owner[b] == owner[c]:
			ow = owner[b]
		var z := _zone_of(ow, cen)
		var mus: Array = [_micro_uv(owner[a], verts[a]), _micro_uv(owner[b], verts[b]),
			_micro_uv(owner[c], verts[c])]
		var moved := _micro_seam(mus, owner[a], owner[b], owner[c])
		for e in 3:
			var vi := idx[t * 3 + e]
			var key := (vi * 64 + z) * 2 + (1 if bool(moved[e]) else 0)
			var ni: int = vmap.get(key, -1)
			if ni < 0:
				ni = v2.size()
				vmap[key] = ni
				v2.append(verts[vi])
				n2.append(normals[vi])
				uv2.append(_zone_uv(z, verts[vi]))
				mu2.append(mus[e])
				for q in 4:
					b2.append(bones[vi * 4 + q])
					w2.append(wts[vi * 4 + q])
			i2[t * 3 + (e if e == 0 else 3 - e)] = ni   # D-051: Godot front = CLOCKWISE; see WINDING note

	# WINDING (D-051). The polygoniser emits triangles whose (b-a)x(c-a) points
	# OUT of the body, and Godot's front face is the CLOCKWISE one — the face
	# whose (b-a)x(c-a) points INWARD (D-021's law, checked in the factory
	# against mesh_kit.round_limb). So every skinned surface since D-031 was a
	# back face: the renderer culled the outer skin and drew the far wall's
	# inside, with inward normals. The normal buffer at `face` showed the chest
	# as (205,144,27) — pointing away from the camera — against the factory's
	# (154,132,229); the factory neck showed THROUGH the skinned neck; and the
	# whole shirt front read as sun-lit with the sun behind the character. The
	# corner swap above turns each triangle around; the normals stay outward.
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v2
	arr[Mesh.ARRAY_NORMAL] = n2
	arr[Mesh.ARRAY_TEX_UV] = uv2
	arr[Mesh.ARRAY_TEX_UV2] = mu2
	arr[Mesh.ARRAY_INDEX] = i2
	arr[Mesh.ARRAY_BONES] = b2
	arr[Mesh.ARRAY_WEIGHTS] = w2
	# ---- LOD. meshoptimizer, at runtime, 8 ms for an eleven-level chain. The
	# factory has no LOD at all — every pedestrian on screen draws its full
	# 123-part self at 60 m — so this is not a like-for-like feature, it is a
	# capability the rigid-parts build cannot have: you cannot decimate a
	# hierarchy of separate meshes without the parts coming apart.
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "body", 0)
	im.generate_lods(25.0, 60.0, [])
	return im.get_mesh()


## Split every triangle that straddles one of the garment planes, so a hem is
## an edge loop lying exactly in its plane instead of whatever the isosurface
## happened to tessellate. Intersections are cached per EDGE, so the result is
## still one welded manifold; an intersection that lands within 1 mm of an
## existing vertex reuses it rather than emitting a sliver.
##
## The planes were y = const only, which is why every zone boundary the PoC
## could draw was horizontal. They are now general (nx, ny, nz, d) with the
## inside test dot(n, v) > d, which costs three multiplies and buys the side
## seam (z = 0) and the two oblique flanks of the V-neck. A cut is VISUALLY
## FREE — it moves no vertex and changes no normal, it only gives the zone
## assignment an edge loop to land on — so the only budget it spends is
## triangles.
static func _cut(verts: PackedVector3Array, normals: PackedVector3Array,
		bones: PackedInt32Array, wts: PackedFloat32Array,
		owner: PackedInt32Array, idx: PackedInt32Array,
		planes: PackedFloat32Array) -> Array:
	for pi in planes.size() / 4:
		var n := Vector3(planes[pi * 4], planes[pi * 4 + 1], planes[pi * 4 + 2])
		var pl := planes[pi * 4 + 3]
		var cache := {}
		var out := PackedInt32Array()
		var t3 := idx.size() / 3
		for t in t3:
			var a := idx[t * 3]; var b := idx[t * 3 + 1]; var c := idx[t * 3 + 2]
			var sa := n.dot(verts[a]) > pl
			var sb := n.dot(verts[b]) > pl
			var sc := n.dot(verts[c]) > pl
			if sa == sb and sb == sc:
				out.append(a); out.append(b); out.append(c)
				continue
			# rotate so `l` is the vertex alone on its side of the plane
			var l := a; var p := b; var q := c
			if sb != sa and sb != sc:
				l = b; p = c; q = a
			elif sc != sa and sc != sb:
				l = c; p = a; q = b
			# −1 means "this edge produced no new vertex" (the plane passes
			# through an existing corner). The decision is CACHED PER EDGE, so
			# the triangle on the other side of that edge is guaranteed to make
			# the same call.
			#
			# THE T-JUNCTION BUG THIS FIXES. The PoC bailed out whenever either
			# side snapped, and emitted the triangle whole — but its neighbour,
			# for which the other edge was the snapping one, went ahead and put a
			# vertex on the SHARED edge. That vertex then sits in the middle of
			# an edge this triangle still treats as unbroken: a T-junction, which
			# is what the bake audit reports as boundary and non-manifold edges.
			# One new vertex splits a triangle in two; two split it in three;
			# neither case may ever be skipped.
			var na := _split(verts, normals, bones, wts, owner, cache, l, p, n, pl)
			var nb := _split(verts, normals, bones, wts, owner, cache, l, q, n, pl)
			if na < 0 and nb < 0:
				out.append(a); out.append(b); out.append(c)
			elif nb < 0:
				out.append(l); out.append(na); out.append(q)
				out.append(na); out.append(p); out.append(q)
			elif na < 0:
				out.append(l); out.append(p); out.append(nb)
				out.append(nb); out.append(p); out.append(q)
			else:
				out.append(l); out.append(na); out.append(nb)
				out.append(na); out.append(p); out.append(q)
				out.append(na); out.append(q); out.append(nb)
		idx = out
	return [verts, normals, bones, wts, owner, idx]


static func _split(verts: PackedVector3Array, normals: PackedVector3Array,
		bones: PackedInt32Array, wts: PackedFloat32Array,
		owner: PackedInt32Array, cache: Dictionary, a: int, b: int,
		n: Vector3, pl: float) -> int:
	var key := (mini(a, b) << 22) | maxi(a, b)
	if cache.has(key):
		return cache[key]
	var ya := n.dot(verts[a])
	var yb := n.dot(verts[b])
	if absf(yb - ya) < 1e-7:
		cache[key] = -1
		return -1
	var t := (pl - ya) / (yb - ya)
	# A cut within 2% of an end emits a sliver: at VOX = 18 mm that is a vertex
	# 0.36 mm from one it already has, which is below any resolution this project
	# measures at and above the 0.1 mm the bake audit rounds positions to. Two
	# vertices that round to the same position make an edge look four-valent, and
	# THAT — not a real pinch — is where the non-manifold count comes from; it
	# tracked the number of cut planes exactly. Snap, and record the snap as the
	# edge's answer so both faces on the edge agree and no T-junction is created.
	if t <= 0.02 or t >= 0.98:
		cache[key] = -1
		return -1
	var ni := verts.size()
	var pnew := verts[a].lerp(verts[b], t)
	# nudge the new point exactly onto the plane; the lerp is already on it to
	# within float error, and a boundary that is only nearly planar is what put
	# an 18 mm sawtooth on the first three bakes.
	verts.append(pnew - n * (n.dot(pnew) - pl))
	normals.append(normals[a].lerp(normals[b], t).normalized())
	# WEIGHTS MUST BE BLENDED, NOT COPIED. Taking the nearer parent's four
	# bones looks harmless and is not: the new vertex sits on an edge whose two
	# ends may be weighted to different bones, so copying one end makes the
	# triangles either side of the cut disagree about where that vertex goes.
	# In the bind pose nothing shows; the moment a hip or a shoulder rotates,
	# the garment line opens into a crack and trails long thin triangles. Both
	# parents' four-bone lists are therefore expanded into the full 12-wide
	# vector, mixed at t, and re-reduced to the top four.
	var acc := PackedFloat32Array(); acc.resize(BONE_N)
	for i in 4:
		acc[bones[a * 4 + i]] += wts[a * 4 + i] * (1.0 - t)
		acc[bones[b * 4 + i]] += wts[b * 4 + i] * t
	var bi := [0, 0, 0, 0]
	var bw := [0.0, 0.0, 0.0, 0.0]
	for bb in BONE_N:
		var val := acc[bb]
		for sl in 4:
			if val > bw[sl]:
				for u in range(3, sl, -1):
					bw[u] = bw[u - 1]; bi[u] = bi[u - 1]
				bw[sl] = val; bi[sl] = bb
				break
	var sum: float = bw[0] + bw[1] + bw[2] + bw[3]
	if sum <= 0.0:
		bi[0] = bones[a * 4]; bw[0] = 1.0; sum = 1.0
	for i in 4:
		bones.append(bi[i])
		wts.append(bw[i] / sum)
	owner.append(owner[a] if t < 0.5 else owner[b])
	cache[key] = ni
	return ni


## Keep only the largest connected run of each bone's ownership; dissolve every
## other island into whatever surrounds it.
static func _one_island(owner: PackedInt32Array, nbr: PackedInt32Array,
		nstart: PackedInt32Array, nv: int) -> PackedInt32Array:
	var comp := PackedInt32Array(); comp.resize(nv); comp.fill(-1)
	var comp_owner := PackedInt32Array()
	var comp_size := PackedInt32Array()
	var stack := PackedInt32Array()
	for v in nv:
		if comp[v] >= 0:
			continue
		var ci := comp_size.size()
		comp_owner.append(owner[v])
		comp_size.append(0)
		stack.clear()
		stack.append(v)
		comp[v] = ci
		while stack.size() > 0:
			var u := stack[stack.size() - 1]
			stack.remove_at(stack.size() - 1)
			comp_size[ci] = comp_size[ci] + 1
			for q in range(nstart[u], nstart[u + 1]):
				var n := nbr[q]
				if comp[n] < 0 and owner[n] == owner[u]:
					comp[n] = ci
					stack.append(n)
	var best := PackedInt32Array(); best.resize(BONE_N); best.fill(-1)
	for ci in comp_size.size():
		var b := comp_owner[ci]
		if best[b] < 0 or comp_size[ci] > comp_size[best[b]]:
			best[b] = ci
	var stray := PackedByteArray(); stray.resize(nv)
	var n_stray := 0
	for v in nv:
		if comp[v] != best[owner[v]]:
			stray[v] = 1
			n_stray += 1
	if n_stray == 0:
		return owner
	# erode the islands from their boundaries inward
	var tally := PackedInt32Array(); tally.resize(BONE_N)
	for p in 8:
		if n_stray == 0:
			break
		var changed := 0
		for v in nv:
			if stray[v] == 0:
				continue
			for b in BONE_N:
				tally[b] = 0
			var any := false
			for q in range(nstart[v], nstart[v + 1]):
				var n := nbr[q]
				if stray[n] == 0:
					tally[owner[n]] += 1
					any = true
			if not any:
				continue
			var bb := owner[v]
			var bc := -1
			for b in BONE_N:
				if tally[b] > bc:
					bc = tally[b]
					bb = b
			owner[v] = bb
			stray[v] = 0
			n_stray -= 1
			changed += 1
		if changed == 0:
			break
	return owner


## Trilinear sample of the baked grid.
static func _sample(f: PackedFloat32Array, lo: Vector3, nx: int, ny: int,
		nz: int, syz: int, p: Vector3) -> float:
	var gx := (p.x - lo.x) / VOX
	var gy := (p.y - lo.y) / VOX
	var gz := (p.z - lo.z) / VOX
	var i := clampi(int(gx), 0, nx - 2)
	var j := clampi(int(gy), 0, ny - 2)
	var k := clampi(int(gz), 0, nz - 2)
	var tx := clampf(gx - float(i), 0.0, 1.0)
	var ty := clampf(gy - float(j), 0.0, 1.0)
	var tz := clampf(gz - float(k), 0.0, 1.0)
	var b := i * syz + j * nz + k
	var c00 := f[b] + (f[b + syz] - f[b]) * tx
	var c01 := f[b + 1] + (f[b + syz + 1] - f[b + 1]) * tx
	var c10 := f[b + nz] + (f[b + syz + nz] - f[b + nz]) * tx
	var c11 := f[b + nz + 1] + (f[b + syz + nz + 1] - f[b + nz + 1]) * tx
	var c0 := c00 + (c10 - c00) * ty
	var c1 := c01 + (c11 - c01) * ty
	return c0 + (c1 - c0) * tz


static func _quad(idx: PackedInt32Array, cell: PackedInt32Array, a: int, b: int,
		c: int, d: int, flip: bool) -> void:
	var va := cell[a]; var vb := cell[b]; var vc := cell[c]; var vd := cell[d]
	if va < 0 or vb < 0 or vc < 0 or vd < 0:
		return
	if flip:
		idx.append(va); idx.append(vb); idx.append(vc)
		idx.append(va); idx.append(vc); idx.append(vd)
	else:
		idx.append(va); idx.append(vc); idx.append(vb)
		idx.append(va); idx.append(vd); idx.append(vc)


static func _laplace(v: PackedVector3Array, nbr: PackedInt32Array,
		nstart: PackedInt32Array, lam: float) -> PackedVector3Array:
	var out := PackedVector3Array()
	out.resize(v.size())
	for i in v.size():
		var s := nstart[i]
		var e := nstart[i + 1]
		if e <= s:
			out[i] = v[i]
			continue
		var acc := Vector3.ZERO
		for q in range(s, e):
			acc += v[nbr[q]]
		out[i] = v[i] + (acc / float(e - s) - v[i]) * lam
	return out


## Weights. A vertex takes weight only from its owner bone and the owner's
## immediate kin (that restriction is what stops the left thigh picking up
## right-thigh weight where the two smin together at the crotch), Gaussian in
## the distance to the BONE SEGMENT, then the whole weight vector is
## Laplacian-smoothed across the mesh.
##
## That smoothing is the joint falloff, and it is the entire difference between
## this body and the factory's. A rigid part has a weight function that is a
## step; this one is C1 across every joint, so the surface at a shoulder is
## SHARED between the collar and the arm and bends instead of hinging.
static func _weights(verts: PackedVector3Array, owner: PackedInt32Array,
		nbr: PackedInt32Array, nstart: PackedInt32Array, w: float) -> Array:
	# bone segments in rest space: head = the bone's own global rest origin,
	# tail = the mean of its children (or a short stub for leaves)
	var gpos: Array[Vector3] = []; gpos.resize(BONE_N)
	for b in BONE_N:
		var off: Vector3 = BONES[b][2]
		if bool(BONES[b][3]):
			off.x *= w
		var par := int(BONES[b][1])
		gpos[b] = off if par < 0 else gpos[par] + off
	var tail: Array[Vector3] = []; tail.resize(BONE_N)
	for b in BONE_N:
		var acc := Vector3.ZERO
		var n := 0
		for c in BONE_N:
			if int(BONES[c][1]) == b:
				acc += gpos[c]; n += 1
		tail[b] = acc / float(n) if n > 0 else gpos[b] + Vector3(0, -0.26, 0)

	var nv := verts.size()
	var full := PackedFloat32Array(); full.resize(nv * BONE_N)
	# Falloff width. 0.115 was the first guess and it was far too wide: at that
	# sigma an upper-arm vertex still carried ~7% of the collar and the torso
	# carried the arm, so an 83-degree shoulder rotation smeared the whole
	# shoulder into taffy. 0.065 is about one limb radius, which is the width a
	# real joint's skin actually blends over.
	const SIG := 0.065
	for i in nv:
		var p := verts[i]
		var allowed: Array = KIN[owner[i]]
		var sum := 0.0
		var base := i * BONE_N
		for b: int in allowed:
			var d := _seg_dist(p, gpos[b], tail[b])
			var ww := exp(-(d * d) / (SIG * SIG))
			full[base + b] = ww
			sum += ww
		if sum > 1e-9:
			for b: int in allowed:
				full[base + b] /= sum
		else:
			full[base + owner[i]] = 1.0

	for pass_i in WEIGHT_SMOOTH_PASSES:
		var nxt := PackedFloat32Array(); nxt.resize(nv * BONE_N)
		for i in nv:
			var base := i * BONE_N
			var s := nstart[i]
			var e := nstart[i + 1]
			var cnt := e - s
			if cnt <= 0:
				for b in BONE_N:
					nxt[base + b] = full[base + b]
				continue
			var inv := 0.55 / float(cnt)
			var tot := 0.0
			for b in BONE_N:
				var acc := 0.0
				for q in range(s, e):
					acc += full[nbr[q] * BONE_N + b]
				var val := full[base + b] * 0.45 + acc * inv
				nxt[base + b] = val
				tot += val
			# RE-MASK AFTER EVERY PASS. Laplacian smoothing runs over mesh
			# adjacency and knows nothing about kinematics, so wherever two
			# limbs are close enough for the field to have fused them — a hand
			# passing a thigh is the case that bit — arm weight leaks onto the
			# leg and the trouser is dragged along with the wrist. Zeroing
			# everything outside the vertex's own kinematic neighbourhood after
			# each pass keeps the falloff smooth AND local.
			# ...except on the LAST pass. A strict mask makes the weight field
			# discontinuous wherever two neighbouring vertices have owners that
			# are not kin, and a discontinuity is a tear: the few vertices where
			# a wrist still touches a hip fly off as thin spikes. One unmasked
			# pass at the end blurs those seams across a single ring, which
			# costs nothing anywhere else on the body.
			tot = 0.0
			if pass_i < WEIGHT_SMOOTH_PASSES - 1:
				var allow: Array = KIN[owner[i]]
				var keep := PackedByteArray(); keep.resize(BONE_N)
				for b: int in allow:
					keep[b] = 1
				for b in BONE_N:
					if keep[b] == 0:
						nxt[base + b] = 0.0
					else:
						tot += nxt[base + b]
			else:
				for b in BONE_N:
					tot += nxt[base + b]
			if tot > 1e-9:
				for b in BONE_N:
					nxt[base + b] /= tot
			else:
				nxt[base + owner[i]] = 1.0
		full = nxt

	# top 4 per vertex, renormalised
	var bones := PackedInt32Array(); bones.resize(nv * 4)
	var wts := PackedFloat32Array(); wts.resize(nv * 4)
	for i in nv:
		var base := i * BONE_N
		var bi := [0, 0, 0, 0]
		var bw := [0.0, 0.0, 0.0, 0.0]
		for b in BONE_N:
			var val := full[base + b]
			for s in 4:
				if val > bw[s]:
					for t in range(3, s, -1):
						bw[t] = bw[t - 1]; bi[t] = bi[t - 1]
					bw[s] = val; bi[s] = b
					break
		var sum: float = bw[0] + bw[1] + bw[2] + bw[3]
		if sum <= 0.0:
			bi[0] = owner[i]; bw[0] = 1.0; sum = 1.0
		for s in 4:
			bones[i * 4 + s] = bi[s]
			wts[i * 4 + s] = bw[s] / sum
	return [bones, wts]


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 1e-9:
		return p.distance_to(a)
	return p.distance_to(a + ab * clampf((p - a).dot(ab) / l2, 0.0, 1.0))


# ============================== THE WARDROBE =================================
## THE ROUTE, AND WHY IT IS NOT THE OTHER ONE.
##
## Two routes were on the table: (a) flat pieces as small RIGID meshes on the
## proxy joints, on the argument that a planar decal does not cross a
## silhouette; (b) everything in the shell.
##
## (a) is wrong, and the reason is the same reason this architecture exists. A
## rigid piece parented to a joint is rigid with respect to the SKIN, and the
## skin deforms. A placket on a torso that bends, a pocket on a chest that
## turns, a vest strap over a shoulder that lifts — each is a surface that
## SLIDES ACROSS the surface it sits on as the pose changes, which is exactly
## the mechanism D-031 measured: the factory's shoulder seam count swings 10.7%
## through a gait cycle because which crossing is exposed depends on the phase.
## Forty flat pieces reintroduce forty of those, and each one is also a rim that
## can lift, because a flat piece laid tangent to a curved surface departs from
## it by the curvature over its own half-width — the entire M16-to-M21 history.
##
## (b) is what is implemented, in two mechanisms, and NEITHER of them can
## produce a crossing curve:
##
##   1. FLAT features are painted. A colour boundary is a row of the palette,
##      and a row boundary lands at an exact height with no geometry at all.
##      Reflective bands, snap rows, jersey stripes, sock tops, the height a
##      short sleeve ends at — all free, all exact, all zero draw calls.
##
##   2. FEATURES WITH THICKNESS are CONSTANT-OFFSET SHELLS OF THE SAME FIELD.
##      A piece is not a mesh laid on the body; it is the set of points at a
##      fixed distance from the body's own isosurface, clipped to a patch:
##
##          piece(p) = smax( | d(p) − c | − t/2 ,  clip(p) )
##
##      where d is the body's own distance field. Two level sets of one field
##      are disjoint by construction — they cannot cross, cannot touch, cannot
##      z-fight, and cannot change their relationship with the pose, because
##      the piece is skinned with the weights sampled AT THE BODY POINT IT SITS
##      ON. Rim lift is not "measured at 4.2 mm and therefore under the bar";
##      it is c, a number chosen when the piece was authored, everywhere on the
##      piece. The defect becomes unrepresentable rather than small.
##
## The cost that governs every decision here: the body mesh is SHARED by the
## whole population in six build/girth buckets. Garment geometry cannot go in
## it — 8 outfits' worth of flags would multiply six bakes into hundreds. So
## garments are a SECOND skinned surface on the same skeleton, assembled per
## character by concatenating pieces from a library that is baked once per
## bucket. Two draw calls for a dressed character, one material, still.
const VOX_G := 0.009
## THE RIM-LIFT FIX (M23), and it is a resolution bug with a specific number.
##
## A constant-offset shell is exact BY CONSTRUCTION — `piece(p)` puts its inner
## face at `off` everywhere, analytically. What was not exact was the MESH of
## it. Naive surface nets emits one vertex per sign-changing cell, so a shell
## whose THICKNESS is at or below the cell size has both of its faces inside a
## single layer of cells: the mesher cannot place an inner face at 3 mm and an
## outer at 11 mm when the grid step is 9 mm, so it places one surface
## somewhere between them, and three passes of Taubin then round the rim.
##
## Every one of the six failing pieces was a thin one, and the tell is in the
## measurement: the yoke is authored at 2.0 mm off the skin and its MINIMUM
## measured clearance was 3.1 mm — the whole piece had drifted outwards,
## which no clipping or design error can do and only under-resolution can.
##   placket th 8 mm | yoke 6 | lanyard 8 | epaulet 9 | apron 10 | hem 11
##   ... against a 9 mm cell. The eleven pieces that passed are the thick ones.
##
## So the bake voxel is chosen PER PIECE from the thinnest part in it, at
## VOX_DIV cells across that thickness. The cost is real and is paid once per
## build bucket into the disk cache; `skin_rim.gd` prints it next to the tally
## so the two can be traded against each other honestly.
const VOX_G_MIN := 0.0025
## Cells across the thinnest part of a piece. 3.0 is the floor at which surface
## nets can resolve two faces and a rim; measured against 1.0/1.5/2.0/3.0/4.0 in
## skin6/vox_sweep.txt.
# UPPER-case statics: tunables the tools set at run time, not constants.
static var VOX_DIV := 3.0  # gdlint:ignore=class-variable-name
## Snap the meshed vertices onto the piece's ANALYTIC isosurface after Taubin.
## The in-grid Newton step in `_polygonise` cannot do this job for a garment: it
## samples the same grid that is too coarse, and it refuses to act at all where
## the per-part band fill left the field at its 1.0 initialiser — which is
## exactly the rim. This one evaluates `_part_sdf` directly, so it is limited by
## the mesh's TOPOLOGY and not by the grid.
##
## SHIPPED OFF (0), and the sweep is why. At the 9 mm grid it fixed penetration
## outright (20 -> 0) but made the rim tally WORSE (10 -> 26 of ~7.6k) — not
## because it introduced error, but because it stops Taubin from averaging an
## under-resolved shell's two faces into one plausible sheet, and starts
## reporting where those faces actually are. Once VOX_DIV resolves the shell the
## rim tally is 0 with this OFF, and it is then pure cost:
##   voxdiv 3.0, reproj 0 -> 0 of 45,920 over 5 mm, 0 penetrating, 18.9 s
##   voxdiv 3.0, reproj 3 -> 0 of 46,442 over 5 mm, 0 penetrating, 66.5 s
## Kept as a measured lever rather than deleted, because the next agent to meet
## a garment that will not resolve at any affordable cell size wants it.
static var REPROJ := 0  # gdlint:ignore=class-variable-name

const P_PLACKET := 0
const P_COLLAR_PTS := 1
const P_COLLAR_VEE := 2
const P_HOOD := 3
const P_POCKET_L := 4
const P_POCKET_R := 5
const P_YOKE := 6
const P_TIE := 7
const P_LANYARD := 8
const P_VEST := 9
const P_APRON := 10
const P_BELT := 11
const P_BUCKLE := 12
const P_DUTY := 13
const P_EPAULET := 14
const P_BADGE := 15
const P_HEM := 16
const PIECE_N := 17
const PIECE_NAME: Array = ["placket", "collar_pts", "collar_vee", "hood",
	"pocket_l", "pocket_r", "yoke", "tie", "lanyard", "vest", "apron", "belt",
	"buckle", "duty", "epaulet", "badge", "hem"]

static var _lib_cache: Dictionary = {}     # bucket key -> {piece -> arrays}
static var _gmesh_cache: Dictionary = {}   # layout|bucket -> ArrayMesh
## Hand-off for the threaded piece bake in `_piece_lib`. Only ever written by
## `_piece_lib` BEFORE the group task starts and read after it joins; each task
## writes exactly one distinct index of `_bake_out`. `_piece_lib` is itself
## called from `build()` on the main thread and is not re-entrant, which is the
## precondition this pair relies on.
static var _bake_in: Array = []
static var _bake_out: Array = []
## Bake the 17 pieces on WorkerThreadPool. A lever, not a constant, because the
## honest way to report what threading bought is to run both arms in ONE process
## back to back so machine contention hits them equally (`skin_rim -- --lib`).
static var THREADED := true  # gdlint:ignore=class-variable-name
# ---- ASYNC BAKE (M23, D-036 S2) ----------------------------------------------
# ONE dedicated background Thread bakes cold buckets sequentially from a mutex-
# guarded queue and drops finished arrays into `_bake_done`; a persistent
# BakeHarvester on the scene root finishes them on the main thread (mesh, disk,
# cache) and joins the thread at exit. Not six pool tasks: six 20 s bakes
# fighting for every core hung a headless boot past five minutes (gate7/boot_h)
# and would do the same to the fan. One core, in order, never blocking.
static var _pending: Dictionary = {}       # key -> t0 usec, queued or baking (main thread)
static var _bake_thread: Thread = null
static var _bake_mutex: Mutex = null    # created on first use, dropped on join (exit leak check)
static var _bake_queue: Array = []         # [[cw, cg, key], ...]  guarded
static var _bake_done: Dictionary = {}     # key -> arrays           guarded
static var _bake_stop := false             # guarded
static var _harvester: Node = null
const BUCKET_W: Array = [0.97, 1.07]
const BUCKET_G: Array = [0.93, 1.07, 1.22]


static func _bucket_key(w: float, g: float) -> String:
	var bw := 0 if w < 1.02 else 1
	var bg_i := 0 if g < 1.00 else (1 if g < 1.15 else 2)
	return "%d_%d" % [bw, bg_i]


static func _lib_ready(key: String) -> bool:
	if _lib_cache.has(key):
		return true
	return not _no_disk and ResourceLoader.exists("user://skinw_%s_v%d.res" % [key, CACHE_VER])


## Kick every bucket that is neither in memory nor on disk. Called by the first
## cold build(); a no-op once the disk cache is warm.
static func prewarm_all() -> void:
	for bw in 2:
		for bg_i in 3:
			_prewarm(float(BUCKET_W[bw]), float(BUCKET_G[bg_i]), "%d_%d" % [bw, bg_i])


static func _prewarm(cw: float, cg: float, key: String) -> void:
	if _pending.has(key) or _lib_ready(key):
		return
	_pending[key] = Time.get_ticks_usec()
	if _bake_mutex == null:
		_bake_mutex = Mutex.new()
	_bake_mutex.lock()
	_bake_queue.append([cw, cg, key])
	_bake_mutex.unlock()
	print("SKIN LIB: async bake queued for bucket %s" % key)
	if _bake_thread == null:
		_bake_thread = Thread.new()
		_bake_thread.start(_bake_worker)
		# Safety net for tools and instant quits: a `--script` SceneTree that quits
		# from _init never lets the deferred harvester enter the tree, so its
		# _exit_tree join never ran and the Thread died unjoined (SIGSEGV at exit,
		# verify7 skin_d020). The root's tree_exiting fires on every shutdown.
		var ml := Engine.get_main_loop()
		if ml is SceneTree and (ml as SceneTree).root != null:
			(ml as SceneTree).root.tree_exiting.connect(_join_bake_thread, CONNECT_ONE_SHOT)
	_ensure_harvester()


## The background thread. Sleeps 50 ms when idle; exits on the stop flag.
static func _bake_worker() -> void:
	while true:
		var job: Array = []
		_bake_mutex.lock()
		var stop := _bake_stop
		if not stop and not _bake_queue.is_empty():
			job = _bake_queue.pop_front()
		_bake_mutex.unlock()
		if stop:
			return
		if job.is_empty():
			OS.delay_msec(50)
			continue
		var out := _bake_lib_arrays(float(job[0]), float(job[1]))
		_bake_mutex.lock()
		_bake_done[str(job[2])] = out
		_bake_mutex.unlock()


## Main thread, every frame from the harvester: finish whatever has landed.
static func _harvest() -> void:
	if _bake_mutex == null:
		return
	var landed: Dictionary = {}
	_bake_mutex.lock()
	if not _bake_done.is_empty():
		landed = _bake_done.duplicate()
		_bake_done.clear()
	_bake_mutex.unlock()
	for key in landed.keys():
		var k := str(key)
		_finish_lib(k, landed[key])
		var t0 := int(_pending.get(k, Time.get_ticks_usec()))
		_pending.erase(k)
		print("SKIN LIB: bucket %s ready (async, %.1f s wall)" % [k,
			float(Time.get_ticks_usec() - t0) / 1e6])


## Stop and join the thread (harvester, on exit). Waits for the bake in
## flight — bounded by one bucket.
static func _join_bake_thread() -> void:
	if _bake_mutex != null:
		_bake_mutex.lock()
		_bake_stop = true
		_bake_mutex.unlock()
	if _bake_thread != null and _bake_thread.is_started():
		_bake_thread.wait_to_finish()
	_bake_thread = null
	_bake_mutex = null
	_harvester = null


## For GarmentWaiter: the lib once it is in memory, else {}.
static func _poll_pending(key: String) -> Dictionary:
	return _lib_cache.get(key, {})


static func _ensure_harvester() -> void:
	if _harvester != null and is_instance_valid(_harvester):
		return
	var ml := Engine.get_main_loop()
	if not (ml is SceneTree):
		return
	var h := BakeHarvester.new()
	h.name = "SkinBakeHarvester"
	h.harvest = _harvest
	h.join = _join_bake_thread
	_harvester = h
	(ml as SceneTree).root.call_deferred("add_child", h)


class BakeHarvester extends Node:
	var harvest: Callable
	var join: Callable

	func _process(_d: float) -> void:
		harvest.call()

	func _exit_tree() -> void:
		join.call()


## The whole bake, thread-safe: every callee is pure (audited D-036 §09), no
## static is touched, and the caller decides what to do with the arrays.
static func _bake_lib_arrays(cw: float, cg: float) -> Array:
	var prims := _prims(cw, cg)
	var bg := _field_grid(prims, _flatten(prims), VOX)
	var dg := _dist_grid(bg)
	var tp: Array = []
	for pr: Dictionary in prims:
		var b := int(pr["bone"])
		if b == B_ROOT or b == B_TORSO or b == B_COLLAR:
			tp.append(pr)
	var dgt := _dist_grid(_field_grid_on(tp, _flatten(tp), VOX, bg))
	var pieces := _pieces(cw, cg)
	var out: Array = []
	out.resize(PIECE_N)
	for p in PIECE_N:
		var parts: Array = pieces[p]
		if p in [P_PLACKET, P_COLLAR_PTS, P_POCKET_L, P_POCKET_R]:
			out[p] = _tailored_piece(p, _flatten(prims), cw)
		else:
			out[p] = [] if parts.is_empty() else _bake_piece(parts, bg, dg, cw, dgt)
	return out


## Fabric cut lines are explicit edges, independent of the field's voxel size.
static func _tailored_piece(piece: int, field: PackedFloat32Array, w: float) -> Array:
	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var zone := Z_G_PLACKET
	var owner := B_TORSO
	if piece == P_COLLAR_PTS:
		zone = Z_G_COLLAR
		owner = B_COLLAR
		# Open-front stand. The centre gap removes the continuous turtleneck ring.
		for row in 5:
			var y := lerpf(1.494, 1.523, float(row) / 4.0)
			for col in 65:
				var angle := lerpf(0.30, TAU - 0.30, float(col) / 64.0)
				var direction := Vector3(sin(angle), 0, -cos(angle))
				var lo := 0.0
				var hi := 0.18
				for iteration in 16:
					var radius := (lo + hi) * 0.5
					if _field(field, Vector3(0, y, 0.012) + direction * radius) < 0:
						lo = radius
					else:
						hi = radius
				vertices.append(Vector3(0, y, 0.012) + direction * (hi + 0.0045))
		_fabric_grid(indices, 0, 65, 5, false)
		# Triangular fold-over leaves, with the tip defined by the pattern.
		for side: float in [-1.0, 1.0]:
			var base := vertices.size()
			for row in 13:
				var v := float(row) / 12.0
				for col in 9:
					var u := float(col) / 8.0
					var a := Vector2(side * 0.014, 1.514).lerp(Vector2(side * 0.050, 1.443), v)
					var b := Vector2(side * 0.074, 1.500).lerp(Vector2(side * 0.050, 1.443), v)
					var xy := a.lerp(b, u)
					# 6.5 mm, not the stand's 4.5: the leaf lies OVER the stand where
					# they overlap, so the two sheets no longer fight for depth at the
					# junction (the jagged inner edges in codex9/review/collar.png).
					vertices.append(_fabric_front(field, xy, 0.0065))
			_fabric_grid(indices, base, 9, 13, side > 0)
	else:
		var x0 := -0.013
		var x1 := 0.013
		var y0 := 1.09
		var y1 := 1.470
		if piece != P_PLACKET:
			zone = Z_G_POCKET
			var cx := -0.086 if piece == P_POCKET_L else 0.086
			x0 = cx - 0.034
			x1 = cx + 0.034
			y0 = 1.283
			y1 = 1.371
		var relief := 0.0050 if piece == P_PLACKET else 0.0040
		for row in 25:
			var v := float(row) / 24.0
			for col in 9:
				var u := float(col) / 8.0
				var y := lerpf(y0, y1, v)
				if piece != P_PLACKET:
					y += 0.012 * absf(u * 2 - 1) * pow(1.0 - v, 3)
				vertices.append(_fabric_front(field, Vector2(lerpf(x0, x1, u), y), relief))
		_fabric_grid(indices, 0, 9, 25, false)
		if piece != P_PLACKET:
			# A flap: 22 mm over the pocket's top, proud at its free edge (8 mm) and
			# tucked at its seam (4.5) — the ledge a pocket needs to read at all.
			var base := vertices.size()
			for row in 5:
				var v := float(row) / 4.0
				for col in 9:
					var u := float(col) / 8.0
					var y := lerpf(y1 - 0.004, y1 + 0.022, v)
					vertices.append(_fabric_front(field, Vector2(lerpf(x0 - 0.002, x1 + 0.002, u), y),
						lerpf(0.0080, 0.0045, v)))
			_fabric_grid(indices, base, 9, 5, false)
	return _fabric_arrays(vertices, indices, zone, owner, w, field)


static func _fabric_front(field: PackedFloat32Array, xy: Vector2, relief: float) -> Vector3:
	var lo := -0.30
	var hi := 0.0
	for i in 18:
		var z := (lo + hi) * 0.5
		if _field(field, Vector3(xy.x, xy.y, z)) > 0:
			lo = z
		else:
			hi = z
	return Vector3(xy.x, xy.y, hi - relief)


static func _fabric_grid(indices: PackedInt32Array, base: int, cols: int, rows: int, flip: bool) -> void:
	for row in rows - 1:
		for col in cols - 1:
			var a := base + row * cols + col
			var b := a + 1
			var c := a + cols
			var d := c + 1
			if flip:
				indices.append_array(PackedInt32Array([a, c, d, a, d, b]))
			else:
				indices.append_array(PackedInt32Array([a, d, c, a, b, d]))


static func _fabric_arrays(vertices: PackedVector3Array, indices: PackedInt32Array,
		zone: int, bone: int, w: float, field: PackedFloat32Array) -> Array:
	var normals := PackedVector3Array()
	var uv := PackedVector2Array()
	var micro := PackedVector2Array()
	var owners := PackedInt32Array()
	var neighbors := PackedInt32Array()
	var starts := PackedInt32Array()
	starts.resize(vertices.size() + 1)
	for p in vertices:
		var epsilon := 0.001
		var n := Vector3(
			_field(field, p + Vector3(epsilon, 0, 0)) - _field(field, p - Vector3(epsilon, 0, 0)),
			_field(field, p + Vector3(0, epsilon, 0)) - _field(field, p - Vector3(0, epsilon, 0)),
			_field(field, p + Vector3(0, 0, epsilon)) - _field(field, p - Vector3(0, 0, epsilon)))
		normals.append(n.normalized())
		uv.append(_zone_uv(zone, p))
		micro.append(_micro_uv(bone, p))
		owners.append(bone)
	var weights := _weights(vertices, owners, neighbors, starts, w)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_TEX_UV2] = micro
	arrays[Mesh.ARRAY_INDEX] = indices
	arrays[Mesh.ARRAY_BONES] = weights[0]
	arrays[Mesh.ARRAY_WEIGHTS] = weights[1]
	return arrays


## Main thread: arrays -> lib dict + ArrayMesh, disk cache, memory cache.
static func _finish_lib(key: String, out: Array) -> Dictionary:
	var lib := {}
	var mesh := ArrayMesh.new()
	var pieces_named := _pieces(float(BUCKET_W[int(key.get_slice("_", 0))]),
		float(BUCKET_G[int(key.get_slice("_", 1))]))
	for p in PIECE_N:
		var arr: Array = out[p]
		if arr.is_empty():
			if not (pieces_named[p] as Array).is_empty():
				push_warning("skinned_character: piece %s baked empty" % PIECE_NAME[p])
			continue
		lib[p] = arr
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_name(mesh.get_surface_count() - 1, str(p))
	_bake_n += 1
	if not _no_disk:
		ResourceSaver.save(mesh, "user://skinw_%s_v%d.res" % [key, CACHE_VER])
	_lib_cache[key] = lib
	return lib


## Attach a finished garment mesh to a character's skeleton (both paths).
static func _attach_garment(skel: Skeleton3D, lay: int, w: float, g: float,
		mat: Material, aabb: AABB) -> void:
	var gm := _garment_mesh(lay, w, g)
	if gm == null:
		return
	var gi := MeshInstance3D.new()
	gi.name = "Garment"
	gi.mesh = gm
	gi.material_override = mat
	gi.custom_aabb = aabb
	skel.add_child(gi)
	gi.skeleton = NodePath("..")
	gi.skin = skel.create_skin_from_rest_transforms()


## Sits on a character whose bucket was cold at build time; attaches the garment
## the frame its async bake lands, then frees itself. Costs one dictionary
## lookup per frame while waiting; first run only.
class GarmentWaiter extends Node:
	var key := ""
	var lay := 0
	var w := 1.0
	var g := 1.0
	var mat: Material = null
	var aabb := AABB()
	var poll: Callable
	var attach: Callable

	func _process(_d: float) -> void:
		var lib: Dictionary = poll.call(key)
		if lib.is_empty():
			return
		var skel := get_parent()
		if skel is Skeleton3D and is_instance_valid(skel):
			attach.call(skel as Skeleton3D, lay, w, g, mat, aabb)
		queue_free()


## One group-task element: bake piece `p`.


static func _bake_one(p: int) -> void:
	var parts: Array = (_bake_in[0] as Array)[p]
	if parts.is_empty():
		_bake_out[p] = []
		return
	_bake_out[p] = _bake_piece(parts, _bake_in[1], _bake_in[2],
		float(_bake_in[3]), _bake_in[4])


static func _smax(a: float, b: float, k: float) -> float:
	return -_smin(-a, -b, k)


## A slab constraint d0 <= n.p <= d1, normalised so the returned SDF is a true
## distance (getting this wrong makes the smooth-max corner radius vary with the
## slab's arbitrary scale).
static func _sl(n: Vector3, d0: float, d1: float) -> Array:
	var l := n.length()
	return [n / l, d0 / l, d1 / l]

static func _slx(a: float, b: float) -> Array:
	return [Vector3(1, 0, 0), a, b]

static func _sly(a: float, b: float) -> Array:
	return [Vector3(0, 1, 0), a, b]

static func _slz(a: float, b: float) -> Array:
	return [Vector3(0, 0, 1), a, b]


## Radial clip: keep where the distance from the vertical axis through (cx, cz)
## lies in [r0, r1]. A collar is round; three slabs cannot say so.
static func _slr(r0: float, r1: float, cx: float, cz: float) -> Array:
	return [Vector3.ZERO, r0, r1, cx, cz]


static func _clip_sdf(clip: Array, p: Vector3, ke: float) -> float:
	var d := -1e9
	for c: Array in clip:
		var t: float
		if c.size() == 5:
			t = Vector2(p.x - float(c[3]), p.z - float(c[4])).length()
		else:
			t = (c[0] as Vector3).dot(p)
		d = _smax(d, maxf(float(c[1]) - t, t - float(c[2])), ke)
	return d


## A constant-offset shell patch. `off` is the clearance of its INNER face from
## the body; `th` its thickness. Both are exact everywhere on the patch.
##
## `trunk` picks the TRUNK-ONLY field instead of the whole body's. A belt is
## clipped by height and nothing else, and the forearm passes through that
## height band — so a belt built on the full body field puts a second ring of
## belt around each WRIST. It is visible in every archetype screenshot as a
## dark band across both forearms, and it is where the 67 mm of gait drift
## came from: that ring is weighted to the root bone while the arm it encircles
## is weighted to the elbow, so it stays at the hip and the arm swings out of
## it. A field that does not contain the arms cannot wrap them.
##
## `carve` is the other half of the `trunk` trick, and it is what stopped the
## belt entering the forearm. A trunk-field piece is built as though the arms do
## not exist — that is the entire point, it is why a belt does not ring the
## wrist — but a belt hanging 4 to 16 mm off the trunk at y 1.01..1.06 occupies
## the same cubic centimetres as the forearm that hangs past it at rest, and 13
## of its vertices were measured INSIDE the arm. So a carve part is additionally
## trimmed by the FULL body field: keep only where the whole body is at least
## `carve` away. The removed material is the part buried in the arm, which no
## camera can see, and the crossing class this architecture exists to eliminate
## stops being represented at all.
static func _sh(off: float, th: float, blo: Vector3, bhi: Vector3, clip: Array,
		ke: float, bone: int, zone: int, k := 0.005,
		trunk := false, carve := 0.0) -> Dictionary:
	return {"t": 0, "off": off, "th": th, "clip": clip, "ke": ke, "k": k,
		"bone": bone, "zone": zone, "lo": blo, "hi": bhi, "trunk": trunk,
		"carve": carve}


## A solid prop (holster, radio, pouch). Trimmed by the body's own offset
## surface at `clr`, so a prop can be placed where a real one hangs without
## ever entering the leg it hangs against.
static func _sp(a: Vector3, b: Vector3, r0: float, r1: float, sc: Vector3,
		clr: float, bone: int, zone: int, ke := 0.010, k := 0.008) -> Dictionary:
	var pr := _cap(a, b, r0, r1, sc, 0.0, bone, zone)
	var m: float = float(pr["rmax"]) * 1.2 + 0.02
	return {"t": 1, "cap": pr, "clr": clr, "clip": [], "ke": ke, "k": k,
		"bone": bone, "zone": zone,
		"lo": (pr["lo"] as Vector3) - Vector3(m, m, m),
		"hi": (pr["hi"] as Vector3) + Vector3(m, m, m)}


## Distance to one capsule dict, in the same convention as `_fd`.
static func _cap_d(pr: Dictionary, p: Vector3) -> float:
	var sc: Vector3 = pr["sc"]
	var a: Vector3 = pr["a"]
	var q := Vector3((p.x - a.x) / sc.x, (p.y - a.y) / sc.y, (p.z - a.z) / sc.z)
	var ab: Vector3 = pr["ab"]
	var t := 0.0
	var l2: float = pr["l2"]
	if l2 > 1e-9:
		t = clampf(q.dot(ab) / l2, 0.0, 1.0)
	return ((q - ab * t).length()
		- (float(pr["r0"]) + (float(pr["r1"]) - float(pr["r0"])) * t)) \
		* float(pr["ms"])


## `bd` is the distance to the field this part is BUILT on (trunk-only for a
## belt, the whole body for everything else). `bdf` is the distance to the whole
## body, and is only consulted by a `carve` part; it defaults to `bd` so every
## existing caller — the bake fill, the owner search, and both measurement
## harnesses, which march the FULL field — keeps its exact previous meaning.
static func _part_sdf(pt: Dictionary, p: Vector3, bd: float,
		bdf := 1e9) -> float:
	var s: float
	if int(pt["t"]) == 0:
		var c := float(pt["off"]) + float(pt["th"]) * 0.5
		s = absf(bd - c) - float(pt["th"]) * 0.5
	else:
		s = _smax(_cap_d(pt["cap"], p), float(pt["clr"]) - bd, float(pt["ke"]))
	var cl: Array = pt["clip"]
	if not cl.is_empty():
		s = _smax(s, _clip_sdf(cl, p, float(pt["ke"])), float(pt["ke"]))
	var cv := float(pt.get("carve", 0.0))
	if cv > 0.0:
		s = _smax(s, cv - (bd if bdf > 1e8 else bdf), float(pt["ke"]))
	return s


## THE GARMENT CATALOGUE. Heights are rest space, feet at y = 0, and −Z is
## FORWARD. Every one of these numbers is the factory's own placement carried
## across: the factory works in torso space (pivot y = 0.90) and collar space
## (a further 0.56), so e.g. its chest pocket at torso y 0.424 is 1.324 here.
static func _pieces(w: float, _g: float) -> Array:
	var out: Array = []
	out.resize(PIECE_N)
	for i in PIECE_N:
		out[i] = []

	# ---- placket: the strip a shirt buttons down. 38 mm wide, 5 mm proud.
	out[P_PLACKET] = [_sh(0.003, 0.008,
		Vector3(-0.034, 1.078, -0.20), Vector3(0.034, 1.458, 0.02),
		[_slx(-0.019, 0.019), _sly(1.085, 1.452), _slz(-9.0, -0.012)],
		0.006, B_TORSO, Z_G_PLACKET)]

	# ---- collar points. The M16 version was pinned 68 mm off a plane through
	# the chest and flew off the portrait like paper wings; there is no plane
	# here, only the surface, and the points are 4 mm off it by construction.
	#
	# M24 (D-050's "two detached tabs on a knife-edge neckline"): the collar is
	# now a STAND with its fold-over leaf — one shell, 4 mm off the body and
	# 6 mm thick, kept within 92 mm of the neck axis between the neckline and
	# the band's top edge at 1.534. On the neck it is the band; where the
	# surface turns onto the trapezius it becomes the leaf lying on the
	# shoulders, and its rim at r 92 is the leaf's edge. The two points hang
	# from the band's front edge, tucked 14 mm under it.
	var pts: Array = []
	# WHERE THE NECK IS. The probe (collar7/collar_probe.gd) put the body
	# surface at r 85 mm from the neck axis at y 1.530 and only at r 60 by
	# 1.560: the neck base is a mound (trapezius ramp + collar ring + deltoid
	# blend), and the neck proper stands on it from ~1.55 up. A band clipped at
	# 1.464..1.534 shelled the mound's top, not the neck — a flat shelf with a
	# sawtooth inner edge where a horizontal plane grazed a bumpy slope. So
	# the band lives from 1.500 to 1.578 inside r 85: on the neck it is the
	# band with a perpendicular (clean) top cut, and at its foot it flares
	# onto the mound until the r 85 wall stops it, which is the fold.
	# Heights (v10): 1.525..1.578 — 53 mm, a stand with its fold, not the 78 mm
	# turtleneck the first cut was; the points hang 63 mm from its foot and
	# stop just above the placket's top snap (1.452).
	pts.append(_sh(0.004, 0.006,
		Vector3(-0.11, 1.495, -0.11), Vector3(0.11, 1.552, 0.12),
		[_sly(1.505, 1.542), _slr(0.0, 0.092, 0.0, 0.012)],
		0.004, B_COLLAR, Z_G_COLLAR))
	for sx: float in [-1.0, 1.0]:
		pts.append(_sh(0.002, 0.004,   # M23: 4/9 -> 2/4 mm — a collar point is cloth, not a pillow
			Vector3(minf(sx * 0.024, sx * 0.076) - 0.01, 1.455, -0.20),
			Vector3(maxf(sx * 0.024, sx * 0.076) + 0.01, 1.540, 0.02),
			[_slx(minf(sx * 0.024, sx * 0.076), maxf(sx * 0.024, sx * 0.076)),
			 _sly(1.462, 1.532), _slz(-9.0, -0.010)],
			0.007, B_COLLAR, Z_G_COLLAR))
	out[P_COLLAR_PTS] = pts

	# ---- V trim: two strips along the flanks of the notch the body already
	# carries as a cut. The notch itself is skin; this is its binding.
	var vee: Array = []
	for sx: float in [-1.0, 1.0]:
		vee.append(_sh(0.004, 0.008,
			Vector3(-0.085, 1.392, -0.20), Vector3(0.085, 1.520, 0.02),
			[_sl(Vector3(sx * 1.0, -V_SLOPE, 0.0), -V_SLOPE * V_APEX - 0.011,
				-V_SLOPE * V_APEX + 0.011),
			 _sly(1.402, 1.512), _slz(-9.0, -0.010)],
			0.006, B_COLLAR, Z_G_ACCENT))
	out[P_COLLAR_VEE] = vee

	# ---- hood, DOWN: a roll of cloth behind the neck. Up is on the head, and
	# the head is not part of this migration yet.
	out[P_HOOD] = [_sh(0.020, 0.032,
		Vector3(-0.14, 1.372, -0.04), Vector3(0.14, 1.556, 0.26),
		[_slx(-0.115, 0.115), _sly(1.380, 1.548), _slz(0.010, 9.0)],
		0.014, B_COLLAR, Z_G_HOOD)]

	# ---- chest pockets, with a flap. THE floating panel of M16: mounted on a
	# plane through the chest its outer edge stood 29 mm off the shirt.
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var cx := sx * 0.086
		out[P_POCKET_L if side == 0 else P_POCKET_R] = [
			_sh(0.003, 0.005, Vector3(cx - 0.05, 1.276, -0.20),      # M23: 4/10 -> 3/5 mm — a patch pocket is cloth, not a box
				Vector3(cx + 0.05, 1.380, 0.02),
				[_slx(cx - 0.037, cx + 0.037), _sly(1.286, 1.362),
				 _slz(-9.0, -0.010)], 0.012, B_TORSO, Z_G_POCKET),
			_sh(0.004, 0.005, Vector3(cx - 0.052, 1.348, -0.20),     # flap: 6/12 -> 4/5 mm
				Vector3(cx + 0.052, 1.388, 0.02),
				[_slx(cx - 0.040, cx + 0.040), _sly(1.356, 1.376),
				 _slz(-9.0, -0.010)], 0.010, B_TORSO, Z_G_POCKET)]

	# ---- western yoke: a SEAM, which means constant relief. M17 drew it as a
	# raised ring and MEASURED 2-3 mm SUNK across the front and 2.3 mm proud at
	# the flanks — a tube laid on a chest. A 2 mm shell of the body's own field
	# is 2 mm everywhere, which is what makes a seam read as a seam.
	var yoke: Array = []
	for sx: float in [-1.0, 1.0]:
		yoke.append(_sh(0.002, 0.003,            # front: a shallow V (a SEAM: 2 mm off — 1 mm penetrated at 11 vertices, verify7)
			Vector3(-0.16, 1.330, -0.20), Vector3(0.16, 1.410, 0.02),
			[_sl(Vector3(sx * 1.0, -0.4667, 0.0), -0.4667 * 1.3416 - 0.005,
				-0.4667 * 1.3416 + 0.005),
			 _slx(-0.150, 0.150), _sly(1.330, 1.404), _slz(-9.0, -0.010)],
			0.008, B_COLLAR, Z_G_TRIM))
		yoke.append(_sh(0.002, 0.003,            # back: across the blades
			Vector3(-0.28, 1.352, -0.02), Vector3(0.28, 1.500, 0.24),
			[_sl(Vector3(sx * 1.0, -0.416, 0.0), -0.416 * 1.372 - 0.006,
				-0.416 * 1.372 + 0.006),
			 _sly(1.352, 1.492), _slz(0.006, 9.0)],
			0.008, B_COLLAR, Z_G_TRIM))
	out[P_YOKE] = yoke

	# ---- tie. M21 measured 16.9 mm at the knot and 29.3 at the top of the
	# blade — the worst mounted piece in the population, because a rigid blade
	# laid tangent at its centre lifts by whatever the chest does over 65 mm and
	# above y 1.39 the chest is falling away fast. A shell does not care what
	# the chest does; it IS what the chest does, 14 mm out.
	out[P_TIE] = [
		_sh(0.014, 0.014, Vector3(-0.030, 1.404, -0.22),
			Vector3(0.030, 1.450, 0.02),
			[_slx(-0.020, 0.020), _sly(1.410, 1.444), _slz(-9.0, -0.010)],
			0.008, B_COLLAR, Z_G_TIE),
		_sh(0.014, 0.012, Vector3(-0.046, 1.176, -0.22),
			Vector3(0.046, 1.416, 0.02),
			[_sl(Vector3(1.0, 0.055, 0.0), -9.0, 0.020 + 0.055 * 1.412),
			 _sl(Vector3(-1.0, 0.055, 0.0), -9.0, 0.020 + 0.055 * 1.412),
			 _sly(1.186, 1.412), _slz(-9.0, -0.010)],
			0.007, B_TORSO, Z_G_TIE)]

	# ---- lanyard. M20 measured both cords 33.9 mm INSIDE the shirt: they had
	# never drawn, at any height, on any build, because they hung at a fraction
	# of a PLANE through the chest. A shell cannot be inside the shirt.
	var lan: Array = []
	for sx: float in [-1.0, 1.0]:
		lan.append(_sh(0.028, 0.008,
			Vector3(-0.075, 1.320, -0.24), Vector3(0.075, 1.520, 0.02),
			[_sl(Vector3(sx * 1.0, 0.14, 0.0),
				sx * sx * (0.020 + 0.14 * 1.336) - 0.007,
				sx * sx * (0.020 + 0.14 * 1.336) + 0.007),
			 _sly(1.330, 1.505), _slz(-9.0, -0.010)],
			0.006, B_COLLAR, Z_G_CORD))
	lan.append(_sh(0.028, 0.008, Vector3(-0.036, 1.256, -0.24),
		Vector3(0.036, 1.348, 0.02),
		[_slx(-0.026, 0.026), _sly(1.266, 1.338), _slz(-9.0, -0.010)],
		0.008, B_TORSO, Z_G_CORD))
	out[P_LANYARD] = lan

	# ---- hi-vis vest: back shell plus two front panels, meeting over the
	# shoulder. The reflective bands are ROWS OF THE PALETTE, not the ten
	# mounted panels the factory spends on them.
	var vest: Array = [_sh(0.014, 0.014,
		Vector3(-0.30, 1.150, -0.06), Vector3(0.30, 1.492, 0.30),
		[_slx(-0.156 * w / 1.02, 0.156 * w / 1.02), _sly(1.162, 1.478),
		 _slz(-0.030, 9.0)], 0.014, B_TORSO, Z_G_VEST)]
	for sx: float in [-1.0, 1.0]:
		vest.append(_sh(0.014, 0.014,
			Vector3(-0.30, 1.150, -0.26), Vector3(0.30, 1.492, 0.06),
			[_slx(minf(sx * 0.030, sx * 0.156 * w / 1.02),
				maxf(sx * 0.030, sx * 0.156 * w / 1.02)),
			 _sly(1.162, 1.478), _slz(-9.0, 0.020)],
			0.014, B_TORSO, Z_G_VEST))
	out[P_VEST] = vest

	# ---- apron: bib, skirt, straps, pocket. M21 measured the bib at 11.0 mm
	# and the skirt at 23.3 — a 290 mm rigid board hung on a barrel.
	var apron: Array = [
		_sh(0.014, 0.012, Vector3(-0.11, 1.150, -0.26),
			Vector3(0.11, 1.406, 0.04),
			[_slx(-0.082, 0.082), _sly(1.160, 1.394), _slz(-9.0, 0.0)],
			0.014, B_TORSO, Z_G_APRON),
		_sh(0.014, 0.012, Vector3(-0.20, 0.990, -0.26),
			Vector3(0.20, 1.176, 0.04),
			[_slx(-0.168, 0.168), _sly(1.000, 1.168), _slz(-9.0, 0.0)],
			0.016, B_ROOT, Z_G_APRON),
		_sh(0.030, 0.010, Vector3(-0.11, 1.096, -0.28),
			Vector3(0.02, 1.170, 0.02),
			[_slx(-0.096, -0.024), _sly(1.104, 1.162), _slz(-9.0, -0.010)],
			0.008, B_ROOT, Z_G_APRON)]
	for sx: float in [-1.0, 1.0]:
		apron.append(_sh(0.014, 0.010,
			Vector3(-0.12, 1.386, -0.24), Vector3(0.12, 1.512, 0.04),
			[_sl(Vector3(sx * 1.0, -0.30, 0.0), -0.30 * 1.394 - 0.010,
				-0.30 * 1.394 + 0.010),
			 _sly(1.392, 1.500), _slz(-9.0, -0.006)],
			0.006, B_COLLAR, Z_G_APRON))
	out[P_APRON] = apron

	# ---- belt and buckle. A buckle sits ON the belt: inside its height, and
	# thin. M20's was 80 mm of buckle on a 55 mm band, +15.4/+17.7 mm proud.
	out[P_BELT] = [_sh(0.004, 0.012, Vector3(-0.24, 1.002, -0.24),
		Vector3(0.24, 1.072, 0.24), [_sly(1.012, 1.062)],
		0.006, B_ROOT, Z_BELT, 0.005, true, 0.001)]
	out[P_BUCKLE] = [_sh(0.018, 0.010, Vector3(-0.07, 1.008, -0.24),
		Vector3(0.07, 1.066, 0.02),
		[_slx(-0.052, 0.052), _sly(1.018, 1.056), _slz(-9.0, -0.010)],
		0.008, B_ROOT, Z_G_METAL)]

	# ---- duty rig (D-017 officers): belt, holster right, radio left, pouches
	# front, shoulder mic. The props are trimmed by the body's offset surface,
	# so they hang where a real one hangs and cannot enter the leg.
	out[P_DUTY] = [
		_sh(0.006, 0.016, Vector3(-0.24, 0.995, -0.26),
			Vector3(0.24, 1.080, 0.26), [_sly(1.005, 1.070)],
			0.008, B_ROOT, Z_G_DUTY, 0.005, true, 0.001),
		_sp(Vector3(0.152, 1.030, 0.020), Vector3(0.156, 0.936, 0.024),
			0.030, 0.024, Vector3(0.80, 1.0, 1.0), 0.004, B_ROOT, Z_G_DUTY),
		_sp(Vector3(-0.150, 1.038, 0.014), Vector3(-0.152, 0.972, 0.014),
			0.021, 0.019, Vector3(0.86, 1.0, 1.0), 0.004, B_ROOT, Z_G_DUTY),
		_sp(Vector3(-0.078, 1.070, -0.070), Vector3(-0.078, 1.024, -0.070),
			0.024, 0.022, Vector3(1.0, 1.0, 0.70), 0.004, B_ROOT, Z_G_DUTY),
		_sp(Vector3(0.080, 1.070, -0.070), Vector3(0.080, 1.028, -0.070),
			0.022, 0.020, Vector3(1.0, 1.0, 0.70), 0.004, B_ROOT, Z_G_DUTY),
		_sp(Vector3(-0.104, 1.462, -0.086), Vector3(-0.104, 1.434, -0.086),
			0.017, 0.014, Vector3(1.0, 1.0, 0.60), 0.003, B_COLLAR, Z_G_DUTY)]

	# ---- epaulets. M20: 96 mm long on a shoulder that falls away 34 mm across
	# that span — the forward corner measured +15.7 mm off the cloth.
	var ep: Array = []
	for sx: float in [-1.0, 1.0]:
		ep.append(_sh(0.003, 0.009,
			Vector3(-0.20, 1.440, -0.10), Vector3(0.20, 1.560, 0.10),
			[_slx(minf(sx * 0.082, sx * 0.158), maxf(sx * 0.082, sx * 0.158)),
			 _sly(1.440, 1.556), _slz(-0.050, 0.034)],   # M25 r2: the shoulder top moved down and forward
			0.008, B_COLLAR, Z_G_TRIM))
	out[P_EPAULET] = ep

	# ---- shield and name tape.
	out[P_BADGE] = [
		_sh(0.005, 0.010, Vector3(-0.116, 1.316, -0.22),
			Vector3(-0.044, 1.394, 0.02),
			[_slx(-0.104, -0.056), _sly(1.326, 1.384), _slz(-9.0, -0.010)],
			0.008, B_TORSO, Z_G_BADGE),
		_sh(0.005, 0.008, Vector3(0.020, 1.344, -0.22),
			Vector3(0.142, 1.386, 0.02),
			[_slx(0.032, 0.130), _sly(1.354, 1.376), _slz(-9.0, -0.010)],
			0.006, B_TORSO, Z_G_TAPE)]

	# ---- the hem of an UNTUCKED shirt.
	out[P_HEM] = [_sh(0.005, 0.011, Vector3(-0.24, 0.948, -0.26),
		Vector3(0.24, 1.010, 0.26), [_sly(0.958, 1.000)],
		0.007, B_ROOT, Z_HIPBAND, 0.005, true, 0.001)]
	return out


## Which pieces this character wears. The cfg keys are `character_factory`'s
## own, produced by its `_dress` — no archetype logic is duplicated here, which
## is what keeps the two bodies dressed by one source of truth.
static func _layout(cfg: Dictionary) -> int:
	var neck := int(cfg.get("neck", 0))
	var m := 0
	if neck != 4 and neck != 5 and not bool(cfg.get("jersey", false)):
		m |= 1 << P_PLACKET
	if neck == 1 or neck == 2 or neck == 3:
		m |= 1 << P_COLLAR_PTS
	if neck == 4:
		m |= 1 << P_COLLAR_VEE
	if neck == 5 and not bool(cfg.get("hood_up", false)):
		m |= 1 << P_HOOD
	if bool(cfg.get("pocket", false)):
		m |= 1 << P_POCKET_L
		if int(cfg.get("outfit", 0)) != 6:            # SCRUBS wear one, left
			m |= 1 << P_POCKET_R
	if bool(cfg.get("yoke", false)):
		m |= 1 << P_YOKE
	if bool(cfg.get("tie", false)):
		m |= 1 << P_TIE
	if bool(cfg.get("lanyard", false)):
		m |= 1 << P_LANYARD
	if bool(cfg.get("vest", false)):
		m |= 1 << P_VEST
	if bool(cfg.get("apron", false)):
		m |= 1 << P_APRON
	var duty := bool(cfg.get("duty", false))
	if duty:
		m |= (1 << P_DUTY) | (1 << P_EPAULET) | (1 << P_BADGE)
	elif bool(cfg.get("tucked", false)) and bool(cfg.get("belt", false)):
		m |= 1 << P_BELT
		if bool(cfg.get("buckle", false)):
			m |= 1 << P_BUCKLE
	if not bool(cfg.get("tucked", false)):
		m |= 1 << P_HEM
	return m


## The body field, renormalised to a TRUE distance by dividing by its own
## gradient. This matters and is not a nicety: `_fd` multiplies by the
## primitive's minimum axis scale, so on a trunk authored with a 0.74 depth
## factor the field reads 0.74x the real distance along x and 1.0x along z. A
## shell built on the raw field would stand 12 mm proud at the sternum and
## 16 mm at the flank — a 4 mm variation invented by the units, on a piece whose
## whole claim is that its clearance is constant.
static func _dist_grid(bg: Dictionary) -> PackedFloat32Array:
	var f: PackedFloat32Array = bg["f"]
	var nx: int = bg["nx"]; var ny: int = bg["ny"]; var nz: int = bg["nz"]
	var syz: int = bg["syz"]
	var out := PackedFloat32Array()
	out.resize(f.size())
	var inv := 1.0 / (2.0 * VOX)
	for i in nx:
		var im := maxi(i - 1, 0) * syz
		var ip := mini(i + 1, nx - 1) * syz
		var ic := i * syz
		for j in ny:
			var jm := maxi(j - 1, 0) * nz
			var jp := mini(j + 1, ny - 1) * nz
			var jc := j * nz
			for k in nz:
				var km := maxi(k - 1, 0)
				var kp := mini(k + 1, nz - 1)
				var b := ic + jc
				var c := f[b + k]
				# ONLY WHERE THE FIELD IS A FIELD. `_field_grid` fills per
				# primitive over its own padded box and leaves everything else
				# at the initial 1.0, so at the edge of a fill box the value
				# steps from ~0.05 to 1.0 and the central difference reads 26 —
				# clamped to 3.0, which divides a 50 mm distance down to 17 mm
				# and invents an offset surface out in open air. That is where
				# the vest's back panel came out standing 66 mm off the man's
				# shoulder blade, and the belt, the hem, the epaulets and the
				# duty rig all had the same shadow. A cell whose neighbourhood
				# is not entirely near the body is left as it is: far.
				var x0 := f[im + jc + k]; var x1 := f[ip + jc + k]
				var y0 := f[ic + jm + k]; var y1 := f[ic + jp + k]
				var z0 := f[b + km]; var z1 := f[b + kp]
				if absf(c) > 0.12 or maxf(maxf(absf(x0), absf(x1)),
						maxf(maxf(absf(y0), absf(y1)),
							maxf(absf(z0), absf(z1)))) > 0.30:
					out[b + k] = c
					continue
				var gx := (x1 - x0) * inv
				var gy := (y1 - y0) * inv
				var gz := (z1 - z0) * inv
				var gl := sqrt(gx * gx + gy * gy + gz * gz)
				out[b + k] = c / clampf(gl, 0.55, 1.60)
	return out


## The bake voxel for one piece: VOX_DIV cells across its thinnest part, capped
## at VOX_G (never coarser than the old uniform grid) and floored at VOX_G_MIN
## (the point past which the bake cost stops buying anything measurable).
##
## A solid prop (`t == 1`) is scored on its smallest RADIUS, not on a thickness
## it does not have — the duty rig's shoulder mic is a 14 mm capsule and it is
## the reason that piece needs a finer grid than its belt does.
static func _piece_vox(parts: Array) -> float:
	var thin := 1e9
	for pt: Dictionary in parts:
		if int(pt["t"]) == 0:
			thin = minf(thin, float(pt["th"]))
		else:
			var pr: Dictionary = pt["cap"]
			thin = minf(thin, minf(float(pr["r0"]), float(pr["r1"])) * 2.0)
	if thin > 1e8:
		return VOX_G
	return clampf(thin / VOX_DIV, VOX_G_MIN, VOX_G)


## The whole piece's analytic SDF at `p`: the same smooth-min of the same
## `_part_sdf` calls the bake grid is filled from, evaluated directly instead of
## sampled. Each part is fed the body distance from ITS OWN field (trunk-only
## for the belt and the hem, full body for everything else) — feeding the wrong
## one here would re-introduce the wrist ring the `trunk` flag exists to stop.
static func _parts_sdf(parts: Array, p: Vector3, dg: PackedFloat32Array,
		dgt: PackedFloat32Array, bg: Dictionary) -> float:
	var blo: Vector3 = bg["lo"]
	var bnx: int = bg["nx"]; var bny: int = bg["ny"]; var bnz: int = bg["nz"]
	var bsyz: int = bg["syz"]
	var s := 1e9
	for pt: Dictionary in parts:
		var src := dgt if bool(pt.get("trunk", false)) and dgt.size() > 0 else dg
		var bd := _sample(src, blo, bnx, bny, bnz, bsyz, p)
		var bdf := (_sample(dg, blo, bnx, bny, bnz, bsyz, p)
			if float(pt.get("carve", 0.0)) > 0.0 else 1e9)
		s = _smin(s, _part_sdf(pt, p, bd, bdf), float(pt["k"]))
	return s


## Area-weighted face normals smoothed over the mesh's own adjacency — the same
## rule `_polygonise` ends on, re-run after the vertices moved.
static func _renormal(verts: PackedVector3Array, idx: PackedInt32Array,
		nbr: PackedInt32Array, nstart: PackedInt32Array) -> PackedVector3Array:
	var nv := verts.size()
	var normals := PackedVector3Array(); normals.resize(nv)
	for t in idx.size() / 3:
		var a := idx[t * 3]; var b := idx[t * 3 + 1]; var c := idx[t * 3 + 2]
		var fn := (verts[b] - verts[a]).cross(verts[c] - verts[a])
		normals[a] += fn; normals[b] += fn; normals[c] += fn
	for v in nv:
		normals[v] = normals[v].normalized()
	for _p in 2:
		var sm := PackedVector3Array(); sm.resize(nv)
		for v in nv:
			var acc := normals[v]
			for q in range(nstart[v], nstart[v + 1]):
				acc += normals[nbr[q]] * 0.25
			sm[v] = acc.normalized()
		normals = sm
	return normals


## Bake one piece into mesh arrays. Returns [] if the piece has no surface.
static func _bake_piece(parts: Array, bg: Dictionary, dg: PackedFloat32Array,
		w: float, dgt := PackedFloat32Array()) -> Array:
	if parts.is_empty():
		return []
	var VG := _piece_vox(parts)  # gdlint:ignore=function-variable-name
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	var cmax := 0.0
	for pt: Dictionary in parts:
		lo = lo.min(pt["lo"]); hi = hi.max(pt["hi"])
		if int(pt["t"]) == 0:
			cmax = maxf(cmax, float(pt["off"]) + float(pt["th"]))
		else:
			cmax = maxf(cmax, 0.12)
	lo -= Vector3(VG, VG, VG) * 2.0
	hi += Vector3(VG, VG, VG) * 2.0
	var nx := int(ceil((hi.x - lo.x) / VG)) + 1
	var ny := int(ceil((hi.y - lo.y) / VG)) + 1
	var nz := int(ceil((hi.z - lo.z) / VG)) + 1
	var syz := ny * nz
	var f := PackedFloat32Array()
	f.resize(nx * ny * nz)
	f.fill(1.0)
	var blo: Vector3 = bg["lo"]
	var bnx: int = bg["nx"]; var bny: int = bg["ny"]; var bnz: int = bg["nz"]
	var bsyz: int = bg["syz"]
	# PER PART OVER ITS OWN BOX, not per cell over every part — the same
	# collapse the body bake makes, and it matters more here: the duty rig's
	# parts span from the shoulder mic to the holster, so its union box is
	# 231,000 cells of which the belt occupies a tenth. Union-box iteration cost
	# 2.07 s for that one piece; this is a quarter of it.
	# The band test then prunes what is left, which on a vest is mostly the
	# inside of a man.
	var band_lo := -VG * 2.0
	# THE TOUCHED SUB-BOX. Finer cells made this worth doing: a piece's authored
	# bounding box is generous on the axis its clip is a half-space on — the
	# placket's box is 220 mm deep because it is clipped at z <= -0.012 and the
	# chest is somewhere in there — but the piece itself only ever exists within
	# `off + th` of the skin, so the band test leaves the overwhelming majority
	# of those cells at the 1.0 initialiser. `_polygonise` gathers eight corners
	# and walks twelve edges for EVERY cell, empty or not, so it was paying for
	# a solid block of air. Tracking what the fill actually touched and
	# polygonising only that costs one integer compare per written cell.
	var ti0 := nx; var ti1 := -1
	var tj0 := ny; var tj1 := -1
	var tk0 := nz; var tk1 := -1
	for pt: Dictionary in parts:
		var band_hi := (float(pt["off"]) + float(pt["th"]) if int(pt["t"]) == 0
			else 0.10) + VG * 2.0
		var kk := float(pt["k"])
		var carve := float(pt.get("carve", 0.0)) > 0.0
		var src := dgt if bool(pt.get("trunk", false)) and dgt.size() > 0 else dg
		var plo: Vector3 = (pt["lo"] as Vector3) - Vector3(VG, VG, VG)
		var phi: Vector3 = (pt["hi"] as Vector3) + Vector3(VG, VG, VG)
		var i0 := maxi(0, int(floor((plo.x - lo.x) / VG)))
		var i1 := mini(nx - 1, int(ceil((phi.x - lo.x) / VG)))
		var j0 := maxi(0, int(floor((plo.y - lo.y) / VG)))
		var j1 := mini(ny - 1, int(ceil((phi.y - lo.y) / VG)))
		var k0 := maxi(0, int(floor((plo.z - lo.z) / VG)))
		var k1 := mini(nz - 1, int(ceil((phi.z - lo.z) / VG)))
		for i in range(i0, i1 + 1):
			var px := lo.x + float(i) * VG
			var bi := i * syz
			for j in range(j0, j1 + 1):
				var py := lo.y + float(j) * VG
				var bj := bi + j * nz
				for k in range(k0, k1 + 1):
					var p := Vector3(px, py, lo.z + float(k) * VG)
					var bd := _sample(src, blo, bnx, bny, bnz, bsyz, p)
					if bd > band_hi or bd < band_lo:
						continue
					var bdf := (_sample(dg, blo, bnx, bny, bnz, bsyz, p)
						if carve else 1e9)
					f[bj + k] = _smin(f[bj + k], _part_sdf(pt, p, bd, bdf), kk)
					if i < ti0: ti0 = i
					if i > ti1: ti1 = i
					if j < tj0: tj0 = j
					if j > tj1: tj1 = j
					if k < tk0: tk0 = k
					if k > tk1: tk1 = k
	if ti1 < ti0:
		return []
	# Two cells of air on every side, so the surface closes inside the sub-grid
	# exactly as it did inside the full one and no face is clipped open.
	ti0 = maxi(ti0 - 2, 0); ti1 = mini(ti1 + 2, nx - 1)
	tj0 = maxi(tj0 - 2, 0); tj1 = mini(tj1 + 2, ny - 1)
	tk0 = maxi(tk0 - 2, 0); tk1 = mini(tk1 + 2, nz - 1)
	var cnx := ti1 - ti0 + 1
	var cny := tj1 - tj0 + 1
	var cnz := tk1 - tk0 + 1
	if cnx * cny * cnz < nx * ny * nz:
		var cf := PackedFloat32Array()
		cf.resize(cnx * cny * cnz)
		cf.fill(1.0)
		var csyz := cny * cnz
		for i in cnx:
			var s0 := (i + ti0) * syz + tj0 * nz + tk0
			var d0 := i * csyz
			for j in cny:
				for k in cnz:
					cf[d0 + j * cnz + k] = f[s0 + j * nz + k]
		f = cf
		lo += Vector3(float(ti0), float(tj0), float(tk0)) * VG
		nx = cnx; ny = cny; nz = cnz; syz = csyz
	var pg := _polygonise(f, lo, nx, ny, nz, syz, VG)
	if pg.is_empty():
		return []
	var verts: PackedVector3Array = pg["verts"]
	var idx: PackedInt32Array = pg["idx"]
	var normals: PackedVector3Array = pg["normals"]
	var nbr: PackedInt32Array = pg["nbr"]
	var nstart: PackedInt32Array = pg["nstart"]
	var nv := verts.size()

	# ---- ANALYTIC RE-PROJECTION. `_polygonise` finishes with a Newton step
	# taken against the GRID, and for a garment that step is the weakest part of
	# the pipeline twice over: the grid is the thing that was too coarse in the
	# first place, and the step refuses to fire wherever `absf(d) >= vox * 2`,
	# which is precisely the rim — the band fill leaves those cells at the 1.0
	# initialiser, so the vertices that lift are exactly the vertices the grid
	# step declines to correct. This one evaluates the piece's own SDF, the same
	# expression the piece is DEFINED by, and it is therefore limited by mesh
	# topology rather than by cell size.
	for _it in REPROJ:
		for v in nv:
			var p := verts[v]
			var h := VG * 0.25
			var s := _parts_sdf(parts, p, dg, dgt, bg)
			var gr := Vector3(
				_parts_sdf(parts, p + Vector3(h, 0, 0), dg, dgt, bg)
					- _parts_sdf(parts, p - Vector3(h, 0, 0), dg, dgt, bg),
				_parts_sdf(parts, p + Vector3(0, h, 0), dg, dgt, bg)
					- _parts_sdf(parts, p - Vector3(0, h, 0), dg, dgt, bg),
				_parts_sdf(parts, p + Vector3(0, 0, h), dg, dgt, bg)
					- _parts_sdf(parts, p - Vector3(0, 0, h), dg, dgt, bg))
			var gl := gr.length()
			if gl < 1e-7:
				continue
			var stepv := gr * (s * 2.0 * h / (gl * gl))
			var sl := stepv.length()
			if sl > VG:
				stepv *= VG / sl
			verts[v] = p - stepv
	# Normals follow the vertices they were computed from, or the shading is
	# the old surface's on the new one's geometry.
	if REPROJ > 0:
		normals = _renormal(verts, idx, nbr, nstart)

	# ---- owner bone and zone: the nearest PART wins, which is exact rather
	# than approximate because the parts are disjoint by their offsets.
	var owner := PackedInt32Array(); owner.resize(nv)
	var zone := PackedInt32Array(); zone.resize(nv)
	# ---- and the weights are sampled AT THE BODY POINT THE VERTEX SITS ON,
	# not at the vertex. This is what makes the clearance constant through the
	# gait: the garment is bound to the same bones, in the same proportions, as
	# the skin directly underneath it. Weighting it at its own position would
	# put it 14 mm further from every bone segment and give it its own, subtly
	# different, falloff — which is a garment that creeps.
	var proj := PackedVector3Array(); proj.resize(nv)
	for v in nv:
		var p := verts[v]
		var best := 1e9
		for pt: Dictionary in parts:
			var sp := dgt if bool(pt.get("trunk", false)) and dgt.size() > 0 else dg
			var d := _part_sdf(pt, p, _sample(sp, blo, bnx, bny, bnz, bsyz, p))
			if d < best:
				best = d
				owner[v] = int(pt["bone"])
				zone[v] = int(pt["zone"])
		# The projection onto the body always uses the FULL field: the weights a
		# garment vertex inherits are the weights of the skin actually under it,
		# whichever field decided the garment's shape.
		var bd := _sample(dg, blo, bnx, bny, bnz, bsyz, p)
		var gx := _sample(dg, blo, bnx, bny, bnz, bsyz, p + Vector3(VOX, 0, 0)) \
			- _sample(dg, blo, bnx, bny, bnz, bsyz, p - Vector3(VOX, 0, 0))
		var gy := _sample(dg, blo, bnx, bny, bnz, bsyz, p + Vector3(0, VOX, 0)) \
			- _sample(dg, blo, bnx, bny, bnz, bsyz, p - Vector3(0, VOX, 0))
		var gz := _sample(dg, blo, bnx, bny, bnz, bsyz, p + Vector3(0, 0, VOX)) \
			- _sample(dg, blo, bnx, bny, bnz, bsyz, p - Vector3(0, 0, VOX))
		var gr := Vector3(gx, gy, gz)
		var gl := gr.length()
		proj[v] = p - gr * (bd / gl) if gl > 1e-6 else p

	var wt := _weights(proj, owner, nbr, nstart, w)
	var bones: PackedInt32Array = wt[0]
	var wts: PackedFloat32Array = wt[1]

	# ---- per-triangle zone, corners split so all three agree (same rule as
	# the body, for the same reason: a NEAREST palette lookup on an interpolated
	# zone puts the boundary wherever UV.x happens to cross a texel).
	var vmap := {}
	var v2 := PackedVector3Array(); var n2 := PackedVector3Array()
	var uv2 := PackedVector2Array(); var b2 := PackedInt32Array()
	var mu2 := PackedVector2Array()   # M24: micro UV (ARRAY_TEX_UV2)
	var w2 := PackedFloat32Array()
	var i2 := PackedInt32Array()
	var t3 := idx.size() / 3
	i2.resize(idx.size())
	for t in t3:
		var a := idx[t * 3]; var b := idx[t * 3 + 1]; var c := idx[t * 3 + 2]
		var z := zone[a]
		if zone[b] == zone[c]:
			z = zone[b]
		var mus: Array = [_micro_uv(bones[a * 4], verts[a]), _micro_uv(bones[b * 4], verts[b]),
			_micro_uv(bones[c * 4], verts[c])]
		var moved := _micro_seam(mus, bones[a * 4], bones[b * 4], bones[c * 4])
		for e in 3:
			var vi := idx[t * 3 + e]
			var key := (vi * 64 + z) * 2 + (1 if bool(moved[e]) else 0)
			var ni: int = vmap.get(key, -1)
			if ni < 0:
				ni = v2.size()
				vmap[key] = ni
				v2.append(verts[vi])
				n2.append(normals[vi])
				uv2.append(_zone_uv(z, verts[vi]))
				mu2.append(mus[e])
				for q in 4:
					b2.append(bones[vi * 4 + q])
					w2.append(wts[vi * 4 + q])
			i2[t * 3 + (e if e == 0 else 3 - e)] = ni   # D-051: Godot front = CLOCKWISE; see WINDING note
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v2
	arr[Mesh.ARRAY_NORMAL] = n2
	arr[Mesh.ARRAY_TEX_UV] = uv2
	arr[Mesh.ARRAY_TEX_UV2] = mu2
	arr[Mesh.ARRAY_INDEX] = i2
	arr[Mesh.ARRAY_BONES] = b2
	arr[Mesh.ARRAY_WEIGHTS] = w2
	return arr


## The piece library for one build/girth bucket: every piece, baked once,
## disk-cached. Assembling a character is then array concatenation — which is
## what makes ~40 distinct wardrobes affordable on six bakes.
static func _piece_lib(cw: float, cg: float, key: String) -> Dictionary:
	if _lib_cache.has(key):
		return _lib_cache[key]
	var path := "user://skinw_%s_v%d.res" % [key, CACHE_VER]
	if not _no_disk and ResourceLoader.exists(path):
		var cached := ResourceLoader.load(path)
		if cached is ArrayMesh:
			var lib := {}
			for sfc in (cached as ArrayMesh).get_surface_count():
				lib[int((cached as ArrayMesh).surface_get_name(sfc))] = \
					(cached as ArrayMesh).surface_get_arrays(sfc)
			_lib_cache[key] = lib
			return lib
	# Synchronous fallback — tools, or a caller that insists. Gameplay builds go
	# through prewarm_all()/_poll_pending() and never block here (D-036 S2).
	var t0 := Time.get_ticks_usec()
	var out := _bake_lib_arrays(cw, cg)
	_bake_us += Time.get_ticks_usec() - t0
	return _finish_lib(key, out)


static func _garment_mesh(lay: int, w: float, g: float) -> ArrayMesh:
	var bw := 0 if w < 1.02 else 1
	var bg_i := 0 if g < 1.00 else (1 if g < 1.15 else 2)
	var bkey := "%d_%d" % [bw, bg_i]
	var key := "%d_%s" % [lay, bkey]
	if _gmesh_cache.has(key):
		return _gmesh_cache[key]
	var lib := _piece_lib([0.97, 1.07][bw], [0.93, 1.07, 1.22][bg_i], bkey)
	var v := PackedVector3Array(); var n := PackedVector3Array()
	var uv := PackedVector2Array(); var b := PackedInt32Array()
	var mu := PackedVector2Array()
	var wt := PackedFloat32Array(); var idx := PackedInt32Array()
	for p in PIECE_N:
		if (lay & (1 << p)) == 0 or not lib.has(p):
			continue
		var a: Array = lib[p]
		var base := v.size()
		v.append_array(a[Mesh.ARRAY_VERTEX])
		n.append_array(a[Mesh.ARRAY_NORMAL])
		uv.append_array(a[Mesh.ARRAY_TEX_UV])
		mu.append_array(a[Mesh.ARRAY_TEX_UV2])
		b.append_array(a[Mesh.ARRAY_BONES])
		wt.append_array(a[Mesh.ARRAY_WEIGHTS])
		for i: int in (a[Mesh.ARRAY_INDEX] as PackedInt32Array):
			idx.append(i + base)
	if v.is_empty():
		return null
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = mu
	arr[Mesh.ARRAY_INDEX] = idx
	arr[Mesh.ARRAY_BONES] = b
	arr[Mesh.ARRAY_WEIGHTS] = wt
	# LOD, on the merged wardrobe. The cost (~8 ms) is paid once per LAYOUT, not
	# per character, because the merge is cached — and the wardrobe is where the
	# triangles are: a hi-vis worker's garment is 21.8k triangles against a
	# 27.8k body, and at 40 m nobody can see a pocket flap.
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, null, "garment", 0)
	im.generate_lods(25.0, 60.0, [])
	var m := im.get_mesh()
	if _gmesh_cache.size() < 96:
		_gmesh_cache[key] = m
	return m


# ============================== PALETTE ======================================
## 32 x 64 RGBA + a 32 x 64 R8 metallic map. RGB is albedo, A is roughness read
## back through `roughness_texture_channel`, R of the second map is metallic.
## One material, one draw call, and the GEOMETRY stays shared across the whole
## crowd — which is the constraint that governs this entire file. Anything a
## wardrobe wants to say that can be said in the palette costs nothing; anything
## that needs its own geometry multiplies the bake by the wardrobe.
##
## A column is a zone. A ROW is a height inside that zone. So a horizontal
## garment line is a row boundary: a reflective band, a snap row, a jersey
## stripe, a sock top, and — the one that matters most — WHERE A SHORT SLEEVE
## ENDS, which the factory spends a whole rigid mesh on and which here is a
## number between 1.225 and 1.265 that varies per person.
##
## `bands` are painted in order, so a later band overrides an earlier one.
##   entry = [base_colour, base_roughness, base_metallic, [[y0, y1, c, r, m], ...]]
static func _palette_spec(cfg: Dictionary) -> Array:
	var skin: Color = cfg["skin"]
	var shirt: Color = cfg["shirt"]
	var pants: Color = cfg["pants"]
	var acc: Color = cfg.get("accent", shirt)
	var shorts := bool(cfg.get("shorts", false))
	var long_sleeve := bool(cfg.get("sleeve_long", false))
	var tucked := bool(cfg.get("tucked", false))
	var neck := int(cfg.get("neck", 0))
	var outfit := int(cfg.get("outfit", 0))
	var shoe_c: Color = cfg.get("shoe_color", Color(0.18, 0.12, 0.09))
	var belt_c: Color = cfg.get("belt_color", pants) if bool(cfg.get("belt", false)) \
		else pants
	var hand_c: Color = Color(0.44, 0.35, 0.25) if bool(cfg.get("gloves", false)) \
		else skin
	var sk_r := float(cfg.get("skin_rough", 0.72))
	var leg_c := skin if shorts else pants
	var leg_r := sk_r if shorts else 0.88
	# Deterministic per-person jitter with NO rng draw: the caller's stream is
	# frozen (8 draws for a ped, 3 for a cop) and this must not add a ninth.
	var jit := fposmod(sk_r * 137.0 + float(cfg.get("girth", 1.0)) * 91.7
		+ float(cfg.get("build", 1.0)) * 53.3, 1.0)

	var pal: Array = []
	pal.resize(PAL_W)
	for i in PAL_W:
		pal[i] = [Color(1, 0, 1), 0.9, 0.0, []]      # magenta = a zone I forgot
	pal[Z_SOLE] = [Color(0.11, 0.10, 0.10), 0.94, 0.0, []]
	pal[Z_SHOE] = [shoe_c, 0.62, 0.0, []]
	# Sock: only visible on bare legs, and it is what stops a GAMEDAY fan in
	# shorts reading as a man who forgot his trousers.
	var shin: Array = [leg_c, leg_r, 0.0, []]
	if shorts:
		shin[3] = [[0.118, 0.235 + 0.09 * jit, acc, 0.90, 0.0]]
	pal[Z_SHIN] = shin
	pal[Z_THIGH_LO] = [leg_c, leg_r, 0.0, []]
	pal[Z_THIGH_HI] = [pants, 0.88, 0.0, []]
	pal[Z_PELVIS] = [pants, 0.88, 0.0, []]
	# An untucked shirt hangs over the waistband; a tucked one does not. Both are
	# the same two columns, painted differently.
	pal[Z_HIPBAND] = [shirt if not tucked else pants, 0.92 if not tucked else 0.88,
		0.0, []]
	pal[Z_BELT] = [belt_c if tucked else shirt, 0.55 if tucked else 0.92, 0.0, []]

	var shirt_bands: Array = []
	if bool(cfg.get("jersey", false)):
		shirt_bands.append([1.268, 1.330, acc, 0.90, 0.0])
		shirt_bands.append([1.196, 1.222, acc, 0.90, 0.0])
	pal[Z_SHIRT_F] = [shirt, 0.92, 0.0, shirt_bands]
	pal[Z_SHIRT_B] = [shirt, 0.92, 0.0, shirt_bands]
	# The V notch is cut into every body in the game and painted shirt for all of
	# them but the one archetype that wears a V.
	pal[Z_CHEST_V] = [skin if neck == 4 else shirt, sk_r if neck == 4 else 0.92,
		0.0, []]

	var sl_bands: Array = []
	if bool(cfg.get("jersey", false)):
		sl_bands.append([1.300, 1.322, acc, 0.90, 0.0])
	pal[Z_SLEEVE] = [shirt, 0.92, 0.0, sl_bands]
	# SLEEVE LENGTH, as a row boundary. 1.225..1.265 is mid-biceps to just above
	# the elbow — the range a real short sleeve covers.
	var up: Array = [shirt, 0.92, 0.0, []]
	if not long_sleeve:
		up = [skin, sk_r, 0.0, [[1.225 + 0.040 * jit, 1.300, shirt, 0.92, 0.0]]]
	pal[Z_UPARM] = up
	pal[Z_FOREARM] = [shirt if long_sleeve else skin,
		0.92 if long_sleeve else sk_r, 0.0, []]
	pal[Z_CUFF] = [acc if long_sleeve else skin, 0.90 if long_sleeve else sk_r,
		0.0, []]
	pal[Z_HAND] = [hand_c, sk_r, 0.0, []]
	pal[Z_NECK] = [skin, sk_r, 0.0, []]
	# The neck prim is painted collar-cloth from 1.462 to the shared boundary at
	# 1.576 (one mesh for the whole population). A CREW, V or HOODED neck has
	# no collar shell to cover that, and wore it as a painted turtleneck
	# (collar7/r3 showcase: a red tee with a red neck). Above the neckline the
	# paint is skin for those; the collared styles keep cloth, which the band
	# shell (P_COLLAR_PTS, 1.525..1.578) hides anyway.
	var collar_bands: Array = [[1.523, 1.576, skin, sk_r, 0.0]]
	if neck == 0 or neck == 4 or neck == 5:
		collar_bands.append([1.500, 1.576, skin, sk_r, 0.0])
	pal[Z_COLLAR] = [shirt.darkened(0.06), 0.90, 0.0, collar_bands]

	# ---------------- garment columns ----------------
	var plack_bands: Array = []
	if bool(cfg.get("snaps", false)):
		for i in 5:
			var sy := 1.176 + 0.078 * float(i)
			plack_bands.append([sy - 0.005, sy + 0.005,
				shirt.lerp(Color(1, 1, 1), 0.35), 0.40, 0.0])   # M23: pearl, not chrome
	elif neck == 3 or neck == 2 or neck == 0:          # DRESS / POLO / CREW
		for i in 5:
			var sy := 1.180 + 0.076 * float(i)
			plack_bands.append([sy - 0.007, sy + 0.007, shirt.darkened(0.34),
				0.55, 0.0])
	pal[Z_G_PLACKET] = [shirt, 0.92, 0.0, plack_bands]   # same cloth as the shirt; relief shows the band
	pal[Z_G_COLLAR] = [shirt.lerp(Color(1, 1, 1), 0.08) if (neck == 3 or neck == 1)
		else shirt.darkened(0.06), 0.90, 0.0, []]
	pal[Z_G_POCKET] = [shirt.darkened(0.04), 0.92, 0.0, []]   # M23: was 0.10 — read as a bolted box
	pal[Z_G_TRIM] = [shirt.darkened(0.05), 0.92, 0.0, []]    # M23: was 0.17 — the yoke read as a seatbelt
	pal[Z_G_TIE] = [cfg.get("tie_color", Color(0.42, 0.10, 0.14)), 0.70, 0.0, []]
	# The hi-vis reflective bands are two rows of one column. The factory spends
	# ten mounted panels on them.
	pal[Z_G_VEST] = [cfg.get("vest_color", Color(0.86, 0.90, 0.16)), 0.62, 0.0,
		[[1.256, 1.280, Color(0.80, 0.83, 0.86), 0.28, 0.0],
		 [1.382, 1.406, Color(0.80, 0.83, 0.86), 0.28, 0.0]]]
	pal[Z_G_APRON] = [cfg.get("apron_color", Color(0.20, 0.22, 0.26)), 0.90, 0.0,
		[]]
	pal[Z_G_DUTY] = [Color(0.07, 0.07, 0.08), 0.50, 0.0, []]
	pal[Z_G_METAL] = [Color(0.85, 0.70, 0.30), 0.22, 0.85, []]
	pal[Z_G_BADGE] = [Color(0.86, 0.74, 0.36), 0.18, 0.90, []]
	pal[Z_G_TAPE] = [Color(0.88, 0.88, 0.86), 0.60, 0.0, []]
	# One column, two jobs, separated by a row: the cord is webbing above the
	# card and the card is a white plastic rectangle below it.
	pal[Z_G_CORD] = [Color(0.20, 0.24, 0.34), 0.90, 0.0,
		[[1.250, 1.342, Color(0.88, 0.88, 0.86), 0.40, 0.0]]]
	pal[Z_G_HOOD] = [shirt.darkened(0.05), 0.92, 0.0, []]
	pal[Z_G_ACCENT] = [acc, 0.90, 0.0, []]
	return pal


static func _palette_material(cfg: Dictionary) -> Material:
	var pal := _palette_spec(cfg)
	var skin: Color = cfg["skin"]
	var key := "L" if SHD.legacy() else "S"
	for i in PAL_W:
		var e: Array = pal[i]
		key += "%s%02x%02x" % [(e[0] as Color).to_html(false),
			int(float(e[1]) * 255.0), int(float(e[2]) * 255.0)]
		for b: Array in e[3]:
			key += "|%.3f%.3f%s%02x%02x" % [b[0], b[1], (b[2] as Color).to_html(false),
				int(float(b[3]) * 255.0), int(float(b[4]) * 255.0)]
		key += ";"
	if _pal_cache.has(key):
		return _pal_cache[key]
	var img := Image.create_empty(PAL_W, PAL_H, false, Image.FORMAT_RGBA8)
	# R = metallic; G = surface CLASS for the micro-detail shader (M24):
	# 0 skin, 0.5 cloth, 1 hard. A row is skin when it is painted the skin
	# colour verbatim (every bare zone and every bare band is), hard on the
	# sole/shoe/buckle/badge columns and wherever metal is.
	var met := Image.create_empty(PAL_W, PAL_H, false, Image.FORMAT_RG8)
	for z in PAL_W:
		var e: Array = pal[z]
		var r: Array = ZV[z]
		var lo := float(r[0])
		var span := maxf(float(r[1]) - lo, 1e-4)
		var hard := z == Z_SOLE or z == Z_SHOE or z == Z_G_METAL or z == Z_G_BADGE \
			or z == Z_G_TAPE
		for row in PAL_H:
			var y := lo + span * (float(row) + 0.5) / float(PAL_H)
			var c: Color = e[0]
			var rough := float(e[1])
			var metal := float(e[2])
			for b: Array in e[3]:
				if y >= float(b[0]) and y < float(b[1]):
					c = b[2]; rough = float(b[3]); metal = float(b[4])
			var cls := 0.0 if c.is_equal_approx(skin) else (1.0 if hard or metal > 0.5 else 0.5)
			img.set_pixel(z, row, Color(c.r, c.g, c.b, rough))
			met.set_pixel(z, row, Color(metal, cls, 0))
	var tex := ImageTexture.create_from_image(img)
	if not SHD.legacy():
		var sm := SHD.palette_material(tex, ImageTexture.create_from_image(met))
		_pal_cache[key] = sm
		return sm
	var m := StandardMaterial3D.new()
	m.albedo_texture = tex
	m.roughness_texture = tex
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_ALPHA
	m.metallic = 1.0
	m.metallic_texture = ImageTexture.create_from_image(met)
	m.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_RED
	# LINEAR, not NEAREST, and the reason is worth stating: UV.x is CONSTANT
	# across every triangle (the zone split guarantees all three corners agree)
	# and lands exactly on a texel centre, so linear filtering returns that
	# column's texel bit-exactly — no bleed between zones is possible. In UV.y
	# it softens a band edge by one row (7-9 mm on the trunk), which is both
	# what a real garment edge looks like and free anti-aliasing.
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	_pal_cache[key] = m
	return m
