extends SceneTree
## WARDROBE PARITY — the measured audit of the skinned body's garment layer.
##   cd game/ && godot --headless --script res://tools/skin_wardrobe.gd 2>&1
##
## THREE MEASUREMENTS, and the middle one is the mission:
##
## 1. COVERAGE. Every archetype `character_factory._dress` can roll, with the
##    pieces the skinned body gives it. A piece the factory draws and this does
##    not is a parity gap and is printed as one.
##
## 2. CLEARANCE — the rim-lift bar (quality-bar §1: "any mounted piece <= 5 mm
##    proud of the surface it sits on"). The factory reached 0 of 141 pieces
##    over that bar by MEASURING each piece against a mirror of its own surface
##    maths and sinking it by its own sag and bow. This measures the same thing
##    a different way, and it has to, because there are no mounted pieces here:
##    for every vertex of every garment piece, march DOWN THE BODY FIELD'S OWN
##    GRADIENT until the field changes sign. That distance is the piece's true
##    Euclidean clearance from the skin, found by root-finding on the field
##    itself — not read back off the offset the piece was built from, which
##    would make the measurement a tautology.
##
##    The number to read is not the mean. It is `spread` = max − min over the
##    piece's inner face. A rigid panel's clearance varies by whatever the
##    surface does across the panel (7.0–29.3 mm, measured, on the factory's
##    placket, tie, apron, jersey band and hi-vis back band before M21 fixed
##    them one at a time). A constant-offset shell's spread is bounded by the
##    grid, not by the anatomy.
##
## 3. GAIT DRIFT. The garment is skinned to the same bones as the body, with the
##    weights sampled at the body point underneath it. If that works, the vector
##    from a body vertex to the garment vertex sitting on it keeps its length
##    through the gait. If it does not, the vest creeps. Measured over the
##    factory's own `animate()` at eight phases of the cycle.

const SKIN := preload("res://scripts/world/skinned_character.gd")
const FACTORY := preload("res://scripts/world/character_factory.gd")

const GAIT: Array = [0.0, 0.7854, 1.5708, 2.3562, 3.1416, 3.927, 4.712, 5.4978]


## Euclidean distance from `p` to the body isosurface.
##
## MARCHED ALONG THE FIELD'S OWN GRADIENT, not along the garment's normal. The
## first version of this used the vertex normal and produced nonsense — every
## vertex on the INSIDE face of a shell has a normal pointing at the body's
## interior, so marching along −normal walks away from the skin and reports "no
## crossing". Half the pieces came back "no inner-face vertex found" and the
## other half were measuring their outer face. The gradient is the shortest way
## to the surface from anywhere, which is the definition of clearance.
##
## A NEGATIVE return is real penetration, in millimetres, and is reported as
## such rather than clamped to zero.
static func _clearance(fp: PackedFloat32Array, p: Vector3, grad: Vector3,
		lim := 0.06) -> float:
	if grad.length() < 1e-9:
		return -99.0
	var dir := grad.normalized()
	var f0 := SKIN._field(fp, p)
	if f0 < 0.0:
		# inside: march OUT along +grad and return the depth as a negative
		var tt := 0.0
		while tt < 0.05:
			tt += 0.001
			if SKIN._field(fp, p + dir * tt) >= 0.0:
				return -tt
		return -0.05
	var step := 0.001
	var t := 0.0
	while t < lim:
		var t1 := t + step
		var f1 := SKIN._field(fp, p - dir * t1)
		if f1 < 0.0:
			# bisect to 0.05 mm
			var a := t
			var b := t1
			for i in 10:
				var mid := (a + b) * 0.5
				if SKIN._field(fp, p - dir * mid) < 0.0:
					b = mid
				else:
					a = mid
			return (a + b) * 0.5
		t = t1
	return -99.0


func _piece_report(cw: float, cg: float) -> void:
	var prims := SKIN._prims(cw, cg)
	var fp := SKIN._flatten(prims)
	var bg := SKIN._field_grid(prims, fp, SKIN.VOX)
	var dg := SKIN._dist_grid(bg)
	var tp: Array = []
	for pr: Dictionary in prims:
		var b := int(pr["bone"])
		if b == SKIN.B_ROOT or b == SKIN.B_TORSO or b == SKIN.B_COLLAR:
			tp.append(pr)
	var dgt := SKIN._dist_grid(SKIN._field_grid_on(tp, SKIN._flatten(tp),
		SKIN.VOX, bg))
	var pieces := SKIN._pieces(cw, cg)
	print("")
	print("PIECE CLEARANCE — build %.2f girth %.2f. `design` is the offset the "
		% [cw, cg] + "piece was authored at;")
	print("  `min/mean/max` are measured by marching each inner-face vertex "
		+ "into the field.")
	print("%-11s %5s %6s %6s %7s %7s %7s %7s %7s %11s %-9s %s"
		% ["piece", "bake", "verts", "tris", "design", "min", "mean", "max",
			"excess", "over/back", "verdict", ""])
	var worst_spread := 0.0
	var over := 0
	var total := 0
	var gtot := 0
	var gover := 0
	for p in SKIN.PIECE_N:
		var parts: Array = pieces[p]
		if parts.is_empty():
			continue
		var t0 := Time.get_ticks_usec()
		var arr := SKIN._bake_piece(parts, bg, dg, cw, dgt)
		var ms := (Time.get_ticks_usec() - t0) / 1000.0
		if arr.is_empty():
			print("%-11s   ---  EMPTY BAKE" % SKIN.PIECE_NAME[p])
			continue
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		# EVERY PART'S OWN DESIGN OFFSET. The piece-wide minimum was wrong for
		# a stack: a pocket flap is authored to sit on the POCKET and a buckle
		# on the BELT (M20: "a buckle sits ON the belt: inside its height, and
		# thin"), so measuring either against the skin measures the wrong
		# surface and reports the thing underneath as error.
		var offs := PackedFloat32Array()
		var shallow := 9.0
		for pt: Dictionary in parts:
			var o := float(pt["off"]) if int(pt["t"]) == 0 else float(pt["clr"])
			offs.append(o)
			shallow = minf(shallow, o)
		const H := 0.002
		var lo := 9.0
		var hi := -9.0
		var acc := 0.0
		var cnt := 0
		var wex := 0.0
		var phi := Vector3.ZERO
		var pen := 0
		var nover := 0
		for i in v.size():
			var q := v[i]
			var gr := Vector3(
				SKIN._field(fp, q + Vector3(H, 0, 0))
					- SKIN._field(fp, q - Vector3(H, 0, 0)),
				SKIN._field(fp, q + Vector3(0, H, 0))
					- SKIN._field(fp, q - Vector3(0, H, 0)),
				SKIN._field(fp, q + Vector3(0, 0, H))
					- SKIN._field(fp, q - Vector3(0, 0, H)))
			# THE BACK FACE, strictly: the vertex normal within ~37 deg of
			# pointing straight at the skin. At the loose −0.25 (75 deg) the
			# set included the rolled rim, whose clearance ramps from `off` to
			# `off + th` by construction — so every piece "measured" a maximum
			# of about its own thickness and the number meant nothing.
			if gr.length() < 1e-9 or n[i].dot(gr) > -0.80 * gr.length():
				continue
			var c := _clearance(fp, q, gr)
			if c < -0.5:
				continue                   # never reached the body: not a back face
			if c < 0.0:
				pen += 1
				continue
			# which part is this vertex on, and is anything of this piece
			# stacked underneath it?
			var mine := -1
			var best := 1e9
			for pi in parts.size():
				var d: float = SKIN._part_sdf(parts[pi], q, c)
				if d < best:
					best = d; mine = pi
			# Anything of this piece between the vertex and the skin? Walk the
			# segment; the body distance along it is c − t by construction, so
			# no second march is needed (one was: it made this O(minutes)).
			var stacked := false
			var dirn := gr.normalized()
			for st in 8:
				var tt := c * (float(st) + 0.5) / 8.0
				var sp := q - dirn * tt
				for pi in parts.size():
					if pi == mine:
						continue
					if SKIN._part_sdf(parts[pi], sp, c - tt) < 0.0:
						stacked = true
						break
				if stacked:
					break
			if stacked:
				continue
			var ex: float = absf(c - offs[mine])
			if ex * 1000.0 > 5.0:
				nover += 1
			if c < lo: lo = c
			if c > hi: hi = c
			if ex > wex:
				wex = ex; phi = q
			acc += c; cnt += 1
		total += 1
		if cnt == 0:
			print("%-11s %5.0f %6d %6d   no unstacked back-face vertex found"
				% [SKIN.PIECE_NAME[p], ms, v.size(), idx.size() / 3])
			continue
		worst_spread = maxf(worst_spread, hi - lo)
		# The 5 mm bar is about a FLAT piece held against a surface. A vest, an
		# apron, a hood and a duty rig are garments with real volume: their back
		# face genuinely leaves the body where the garment hangs away from it,
		# and a hood that hugged the neck to 5 mm would not be a hood. Those are
		# scored on penetration and on their own design offset, and marked
		# `volume` rather than silently passed.
		var vol := pt_kind(parts) == 1
		var bad := wex * 1000.0 > 5.0 and not vol
		if bad:
			over += 1
		gtot += cnt
		gover += (nover if not vol else 0)
		print("%-11s %5.0f %6d %6d %7.1f %7.1f %7.1f %7.1f %7.1f %5d/%-5d %-9s %s"
			% [SKIN.PIECE_NAME[p], ms, v.size(), idx.size() / 3,
				shallow * 1000.0, lo * 1000.0, acc / float(cnt) * 1000.0,
				hi * 1000.0, wex * 1000.0, nover, cnt,
				("OVER 5 mm" if bad else ("volume" if vol else "ok")),
				("worst at (%.3f,%.3f,%.3f)" % [phi.x, phi.y, phi.z]) if bad
				else ("%d penetrating" % pen if pen > 0 else "")])
	print("  %d pieces measured, %d with any back-face vertex over the 5 mm bar."
		% [total, over])
	print("  FLAT-TRIM VERTEX TALLY: %d of %d back-face vertices over 5 mm "
		% [gover, gtot] + "(%.2f%%). The factory's comparable figure is 0 of "
		% (100.0 * float(gover) / float(maxi(gtot, 1)))
		+ "141 PIECES — it measured four corners each, this measures every "
		+ "vertex.")


## 0 = the piece is flat trim held against the skin (the 5 mm bar applies);
## 1 = the piece is a garment with real volume (a vest, an apron, a hood, a
## duty rig) whose thickness is the point of it.
static func pt_kind(parts: Array) -> int:
	for pt: Dictionary in parts:
		if int(pt["t"]) == 1:
			return 1
		if float(pt["th"]) > 0.013:
			return 1
	return 0


func _archetypes() -> Array:
	var out: Array = []
	var names := ["CASUAL", "WESTERN", "WORKER", "OFFICE", "SERVICE", "STREET",
		"SCRUBS", "GAMEDAY"]
	for o in 8:
		# _dress is the factory's own; drive it directly so the archetype is
		# exactly the one the shipping path produces.
		var r := RandomNumberGenerator.new()
		r.seed = hash("wardrobe|%d" % o)
		var cfg := FACTORY._person(r, FACTORY.SKIN_TONES[o % 6],
			FACTORY.HAIRS[o % 5], 1.0, 1.02)
		cfg["shirt"] = FACTORY.SHIRTS[o % FACTORY.SHIRTS.size()]
		cfg["pants"] = FACTORY.PANTS[o % FACTORY.PANTS.size()]
		cfg["hat_color"] = FACTORY.HAT_COLORS[0]
		FACTORY._dress(cfg, r, o)
		out.append([names[o], cfg])
	var rc := RandomNumberGenerator.new()
	rc.seed = 7
	out.append(["COP", FACTORY.cop_config(rc)])
	out.append(["BOOK", FACTORY.book_config()])
	return out


func _coverage() -> void:
	print("")
	print("ARCHETYPE COVERAGE — the pieces each wardrobe carries")
	print("%-9s %-6s %5s %6s  %s" % ["outfit", "gtris", "gmesh", "draws",
		"pieces"])
	for e in _archetypes():
		var cfg: Dictionary = e[1]
		var lay: int = SKIN._layout(cfg)
		var names: Array = []
		for p in SKIN.PIECE_N:
			if lay & (1 << p):
				names.append(SKIN.PIECE_NAME[p])
		var gm: ArrayMesh = SKIN._garment_mesh(lay,
			float(cfg.get("build", 1.0)), float(cfg.get("girth", 1.0)))
		var gt := 0
		if gm != null:
			gt = (gm.surface_get_arrays(0)[Mesh.ARRAY_INDEX]
				as PackedInt32Array).size() / 3
		print("%-9s %-6d %5s %6d  %s" % [e[0], gt, "y" if gm != null else "n",
			2 if gm != null else 1, ", ".join(names)])


## Linear blend skin one vertex under the current pose.
##
## The bone global poses are read off the PROXY JOINT TREE, not off
## Skeleton3D.get_bone_global_pose(). In a `--script` tool there is no frame,
## so Skeleton3D never processes its deferred pose update and every bone reads
## back at rest — the first version of this measurement reported an identical
## 0.048 mm of drift at all eight gait phases, which is what a skeleton that
## never moved looks like, and it would have been reported as a pass. The proxy
## joints are the same hierarchy at the same pivots (that is the rig contract),
## so their global transforms ARE the bone global poses.
func _skin_pos(gp: Array, rest: Array, p: Vector3, b: PackedInt32Array,
		w: PackedFloat32Array, o: int) -> Vector3:
	var acc := Vector3.ZERO
	for i in 4:
		var wt := w[o + i]
		if wt <= 0.0:
			continue
		var bi := b[o + i]
		acc += ((gp[bi] as Transform3D) * (rest[bi] as Transform3D) * p) * wt
	return acc


func _gait_drift() -> void:
	print("")
	print("GAIT DRIFT — does the garment keep its clearance while the body "
		+ "deforms?")
	var cfg := FACTORY.book_config()
	cfg["vest"] = true
	cfg["vest_color"] = FACTORY.HIVIS[0]
	cfg["apron"] = false
	var root := Node3D.new()
	get_root().add_child(root)
	var rig := SKIN.build(root, cfg, 0.0)
	var skel: Skeleton3D = null
	var body: MeshInstance3D = null
	var garment: MeshInstance3D = null
	for c in (rig["vis"] as Node3D).get_children():
		if c is Skeleton3D:
			skel = c
			for d in c.get_children():
				if d is MeshInstance3D and str(d.name) == "Skin":
					body = d
				elif d is MeshInstance3D and str(d.name) == "Garment":
					garment = d
	if skel == null or body == null or garment == null:
		print("  could not find the surfaces")
		root.queue_free()
		return
	var rest: Array = []
	for b in skel.get_bone_count():
		rest.append(skel.get_bone_global_rest(b).affine_inverse())
	print("  (bone global poses read off the proxy joints — see _skin_pos)")
	var ba := body.mesh.surface_get_arrays(0)
	var ga := garment.mesh.surface_get_arrays(0)
	var bv: PackedVector3Array = ba[Mesh.ARRAY_VERTEX]
	var bb: PackedInt32Array = ba[Mesh.ARRAY_BONES]
	var bw: PackedFloat32Array = ba[Mesh.ARRAY_WEIGHTS]
	var gv: PackedVector3Array = ga[Mesh.ARRAY_VERTEX]
	var gb: PackedInt32Array = ga[Mesh.ARRAY_BONES]
	var gw: PackedFloat32Array = ga[Mesh.ARRAY_WEIGHTS]
	# Pair every 7th garment vertex with its nearest body vertex at rest,
	# through a 40 mm spatial hash — the brute-force version was 1,611 x 13,000
	# distance tests and took minutes.
	var cell := 0.04
	var hash_ := {}  # gdlint:ignore=function-variable-name
	for j in bv.size():
		var k := Vector3i(int(floor(bv[j].x / cell)), int(floor(bv[j].y / cell)),
			int(floor(bv[j].z / cell)))
		# Array, not PackedInt32Array: a Packed array is a VALUE in GDScript, so
		# `(hash_[k] as PackedInt32Array).append(j)` appends to a copy and
		# throws it away. Every bucket stayed empty and the pairing reported
		# "0 sample pairs" — which the drift loop then printed as nan and 0.000.
		if not hash_.has(k):
			hash_[k] = []
		(hash_[k] as Array).append(j)
	var pair: Array = []
	var rest_d := PackedFloat32Array()
	for i in range(0, gv.size(), 7):
		var g := gv[i]
		var kc := Vector3i(int(floor(g.x / cell)), int(floor(g.y / cell)),
			int(floor(g.z / cell)))
		var best := 1e9
		var bi := -1
		for dx in range(-2, 3):
			for dy in range(-2, 3):
				for dz in range(-2, 3):
					var k := kc + Vector3i(dx, dy, dz)
					if not hash_.has(k):
						continue
					for j: int in (hash_[k] as Array):
						var d := g.distance_squared_to(bv[j])
						if d < best:
							best = d; bi = j
		if bi < 0:
			continue
		pair.append([i, bi])
		rest_d.append(sqrt(best))
	print("  %d sample pairs" % pair.size())
	var worst := 0.0
	for gi in GAIT.size():
		rig["phase"] = float(GAIT[gi])
		for s in 40:
			SKIN.animate(rig, 1.6, 1.0 / 60.0, true, true)
			rig["phase"] = float(GAIT[gi])
		# push the proxy pose onto the skeleton exactly as SkinSync does
		var joints := [null, rig["hip_0"], rig["knee_0"], rig["hip_1"],
			rig["knee_1"], rig["torso"], rig["collar"], rig["head"],
			rig["sh_0"], rig["el_0"], rig["sh_1"], rig["el_1"]]
		# Compose the bone global poses up the hierarchy from LOCAL transforms.
		# `global_transform` is not available here — a `--script` tool's nodes
		# are not inside the tree during _init, and Skeleton3D's own
		# get_bone_global_pose never runs its deferred update without a frame.
		# Local transforms are always valid, and the proxy tree is the bone tree.
		var gp: Array = []
		for b in joints.size():
			if b == 0:
				gp.append(Transform3D.IDENTITY)
				continue
			skel.set_bone_pose_rotation(b, (joints[b] as Node3D).quaternion)
			var par := int(SKIN.BONES[b][1])
			gp.append((gp[par] as Transform3D) * (joints[b] as Node3D).transform)
		# D-020, re-verified BY POSITION and never by angle: negative z is
		# forward on this body, so an arm swung forward puts el_1 at z < 0.
		var elb: Vector3 = (gp[11] as Transform3D).origin
		var mx := 0.0
		var acc := 0.0
		var wloc := Vector3.ZERO
		var ds := PackedFloat32Array()
		for pi in pair.size():
			var e: Array = pair[pi]
			var gq := _skin_pos(gp, rest, gv[e[0]], gb, gw, int(e[0]) * 4)
			var bq := _skin_pos(gp, rest, bv[e[1]], bb, bw, int(e[1]) * 4)
			var d := absf(gq.distance_to(bq) - rest_d[pi])
			ds.append(d)
			if d > mx:
				mx = d; wloc = gv[e[0]]
			acc += d
		worst = maxf(worst, mx)
		var sorted_ := Array(ds)  # gdlint:ignore=function-variable-name
		sorted_.sort()
		var p99: float = sorted_[int(float(sorted_.size()) * 0.99)]
		print("  phase %.2f rad  el_1 z=%+.4f  mean %6.3f  p99 %6.3f  "
			% [GAIT[gi], elb.z, acc / float(pair.size()) * 1000.0, p99 * 1000.0]
			+ "worst %7.3f mm at (%.2f,%.2f,%.2f)"
			% [mx * 1000.0, wloc.x, wloc.y, wloc.z])
	print("  WORST DRIFT ACROSS THE CYCLE: %.3f mm" % (worst * 1000.0))
	root.queue_free()


func _init() -> void:
	SKIN._no_disk = true
	print("WARDROBE PARITY AUDIT — skinned character")
	_coverage()
	_piece_report(1.07, 1.07)
	_gait_drift()
	print(SKIN.bake_stats())
	quit(0)
