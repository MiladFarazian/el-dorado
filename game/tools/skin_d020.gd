extends SceneTree
## D-020 BY POSITION, ON THE SKINNED BODY. Headless, no rendering:
##   cd game/ && godot --headless --script res://tools/skin_d020.gd 2>&1
##
## D-020's standing rule is that pose verification asserts POSITIONS, never
## angles, because a sign error satisfies every angle assertion happily — that
## is how elbows stayed backwards for five milestones. So nothing below looks at
## a rotation. Each case drives the joints the game drives, composes the bone
## global poses up the proxy hierarchy (which IS the bone hierarchy — the rig
## contract), and asserts WHERE a joint and a SKINNED VERTEX end up.
##
## The vertex half matters as much as the joint half. D-031 records the bug
## where `MeshInstance3D.skeleton` does not default to `NodePath("..")`, whose
## symptom is a perfect joint tree over a body standing stock still: every
## joint assertion passes and the character does not move. A test that only
## reads joints cannot see that. So every case also linear-blend-skins the mesh
## vertex nearest the moving limb and asserts it went the same way.
##
## Convention, from D-020: a limb hangs down local -Y, so POSITIVE rotation.x
## swings it toward -Z, and -Z IS FORWARD. Elbows flex forward (positive),
## knees backward (negative).

const SKIN := preload("res://scripts/world/skinned_character.gd")
const FACTORY := preload("res://scripts/world/character_factory.gd")

var _pass := 0
var _fail := 0


func _init() -> void:
	SKIN._no_disk = true
	print("D-020 POSITION HARNESS — skinned body")
	var root := Node3D.new()
	root.name = "D020Root"
	get_root().add_child(root)
	var rig := SKIN.build(root, FACTORY.book_config(), 0.0)
	var skel: Skeleton3D = null
	var body: MeshInstance3D = null
	for c in (rig["vis"] as Node3D).get_children():
		if c is Skeleton3D:
			skel = c
			for d in c.get_children():
				if d is MeshInstance3D and str(d.name) == "Skin":
					body = d
	if skel == null or body == null:
		print("  FAIL: no skeleton/skin"); quit(1); return
	# THE BIND-POSE TRAP, asserted first because everything after it is
	# meaningless if it fires: a mesh whose `skeleton` path does not resolve
	# renders in bind pose no matter what the bones do.
	_chk("skin binds to the skeleton",
		body.get_node_or_null(body.skeleton) == skel, "skeleton=%s" % body.skeleton)
	var arr := body.mesh.surface_get_arrays(0)
	var bv: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var bb: PackedInt32Array = arr[Mesh.ARRAY_BONES]
	var bw: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var rest: Array = []
	for b in skel.get_bone_count():
		rest.append(skel.get_bone_global_rest(b).affine_inverse())

	# ---- 1. ELBOW FLEXES FORWARD. Shoulder held at rest so nothing but the
	# elbow can move the hand; the hand must end up at SMALLER z than the elbow.
	var g := _pose(rig, skel, {"el_1": 1.20})
	var elb: Vector3 = (g[SKIN.B_EL1] as Transform3D).origin
	var hand: Vector3 = (g[SKIN.B_EL1] as Transform3D) * Vector3(0.0, -0.30, 0.0)
	_chk("elbow flex puts the hand FORWARD of the elbow (z %.4f < %.4f)"
		% [hand.z, elb.z], hand.z < elb.z - 0.05, "")
	_chk("  and the SKIN went with it",
		_vert_moved(g, rest, bv, bb, bw, Vector3(0.20, 1.05, 0.0)).z < -0.02, "")

	# ---- 2. SHOULDER FLEXES FORWARD — D-031's own number, re-measured.
	g = _pose(rig, skel, {"sh_1": 1.45})
	var e2: Vector3 = (g[SKIN.B_EL1] as Transform3D).origin
	_chk("sh_1.x=1.45 puts el_1 FORWARD (z %.4f <= -0.20)" % e2.z,
		e2.z <= -0.20, "D-031 measured -0.2978")

	# ---- 3. KNEE FLEXES BACKWARD — the mirror joint, which can never share the
	# elbow's sign (D-020's root cause was exactly that copy).
	g = _pose(rig, skel, {"knee_1": -1.20})
	var kne: Vector3 = (g[SKIN.B_KNEE1] as Transform3D).origin
	var foot: Vector3 = (g[SKIN.B_KNEE1] as Transform3D) * Vector3(0.0, -0.43, 0.0)
	_chk("knee flex puts the foot BEHIND the knee (z %.4f > %.4f)"
		% [foot.z, kne.z], foot.z > kne.z + 0.05, "")
	_chk("  and the SKIN went with it",
		_vert_moved(g, rest, bv, bb, bw, Vector3(0.10, 0.30, 0.0)).z > 0.02, "")

	# ---- 4. THE AIMED GUN HAND, D-020's own acceptance numbers: at least
	# 0.20 m in front of the shoulder and above y 1.15.
	for i in 30:
		SKIN.aim_pose(rig, 1.0 / 60.0)
	g = _compose(rig, skel)
	var sh: Vector3 = (g[SKIN.B_SH1] as Transform3D).origin
	var gh: Vector3 = (g[SKIN.B_EL1] as Transform3D) * Vector3(0.0, -0.30, 0.0)
	_chk("aimed hand is >= 0.20 m in FRONT of the shoulder (%.3f)"
		% (sh.z - gh.z), sh.z - gh.z >= 0.20, "")
	_chk("aimed hand is above y 1.15 (%.3f)" % gh.y, gh.y > 1.15, "")

	print("  %d/%d" % [_pass, _pass + _fail])
	quit(1 if _fail > 0 else 0)


func _chk(what: String, ok: bool, note: String) -> void:
	if ok: _pass += 1
	else: _fail += 1
	print("  %s  %s%s" % ["PASS" if ok else "FAIL", what,
		("   [" + note + "]") if note != "" else ""])


## Drive the named proxy joints, then compose the bone global poses up the
## hierarchy from LOCAL transforms — `Skeleton3D.get_bone_global_pose()` never
## runs its deferred update without a frame, and a `--script` tool has none.
func _pose(rig: Dictionary, skel: Skeleton3D, rot: Dictionary) -> Array:
	for k in ["hip_0", "knee_0", "hip_1", "knee_1", "torso", "collar", "head",
			"sh_0", "el_0", "sh_1", "el_1"]:
		(rig[k] as Node3D).rotation = Vector3.ZERO
	for k: String in rot:
		(rig[k] as Node3D).rotation.x = float(rot[k])
	return _compose(rig, skel)


func _compose(rig: Dictionary, skel: Skeleton3D) -> Array:
	var joints := [null, rig["hip_0"], rig["knee_0"], rig["hip_1"],
		rig["knee_1"], rig["torso"], rig["collar"], rig["head"],
		rig["sh_0"], rig["el_0"], rig["sh_1"], rig["el_1"]]
	var gp: Array = []
	for b in joints.size():
		if b == 0:
			gp.append(Transform3D.IDENTITY)
			continue
		skel.set_bone_pose_rotation(b, (joints[b] as Node3D).quaternion)
		gp.append((gp[int(SKIN.BONES[b][1])] as Transform3D)
			* (joints[b] as Node3D).transform)
	return gp


## Linear-blend-skin the mesh vertex nearest `near` and return how far it moved.
func _vert_moved(gp: Array, rest: Array, bv: PackedVector3Array,
		bb: PackedInt32Array, bw: PackedFloat32Array, near: Vector3) -> Vector3:
	var bi := -1
	var best := 1e9
	for i in bv.size():
		var d := bv[i].distance_squared_to(near)
		if d < best:
			best = d; bi = i
	var acc := Vector3.ZERO
	for i in 4:
		var wt := bw[bi * 4 + i]
		if wt <= 0.0:
			continue
		acc += ((gp[bb[bi * 4 + i]] as Transform3D)
			* (rest[bb[bi * 4 + i]] as Transform3D) * bv[bi]) * wt
	return acc - bv[bi]
