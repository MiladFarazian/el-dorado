extends Node3D
## STREET WEAR (D-059; Milad: "designs and assets still aren't the most detailed").
## The downtown roadway was a clean dark plane with paint on it. A real street
## carries its plumbing and its repairs: manhole covers on the travel lanes, storm
## drains at the kerbs by every crossing, and tar patches where the utility cuts
## were. Three flat MultiMeshes and a lathed lid — four draw calls for the whole
## grid, no per-frame work, cast_shadow OFF on all of it (D-028: a decal is not a
## caster). Seeded; the same street wears the same way every boot.
##
## Geometry is city_dressing's: N-S streets at x = 193 + 86 i (7), E-W crossings at
## z = 133 + 86 j (5), kerb face at |13|, curb lane 7..13, travel lane centre 3.5.
## Decals sit at WEAR_Y, 2 mm over the row paint, so they read on top of the lines.

const RNG_SEED := 0x5E4A
const NS_X0 := 193.0; const NS_DX := 86.0; const NS_COUNT := 7
const EW_Z0 := 133.0; const EW_DZ := 86.0; const EW_COUNT := 5
const NS_Z_RANGE := Vector2(50.0, 546.0)
const EW_X_RANGE := Vector2(110.0, 780.0)
const KERB := 13.0
const LANE_C := 3.5                   # travel-lane centre from the street centreline
const CROSS_CLEAR := 17.0             # no wear inside a crossing box
const WEAR_Y := 0.048                 # 2 mm over city_dressing's ROW_PAINT_Y
const MANHOLE_STEP := 38.0            # m between lids along a lane
const MANHOLE_R := 0.31
const DRAIN_SIZE := Vector3(0.72, 0.012, 0.38)
const DRAIN_OFF := 12.55              # centre, just inside the kerb face
const DRAIN_AT := 15.5                # m from the crossing centreline
const PATCH_PER_LANE_M := 0.055       # ~1 patch per 18 m of lane
const PATCH_SIZE := Vector2(1.1, 2.8) # m, shortest .. longest side
const IRON := Color(0.16, 0.15, 0.14)
const TAR := Color(0.045, 0.043, 0.042)

var _rng := RandomNumberGenerator.new()


func build(_city: Node3D) -> void:
	_rng.seed = RNG_SEED
	var lids: Array[Transform3D] = []
	var drains: Array[Transform3D] = []
	var patches: Array[Transform3D] = []
	for i in NS_COUNT:
		var cx := NS_X0 + NS_DX * float(i)
		_lane_wear(lids, patches, Vector3(cx, 0.0, NS_Z_RANGE.x), Vector3(0, 0, 1), NS_Z_RANGE.y - NS_Z_RANGE.x, Vector3(1, 0, 0), _ew_centres())
		for j in EW_COUNT:
			var cz := EW_Z0 + EW_DZ * float(j)
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					# Four drains per crossing, one at each kerb just short of the box.
					drains.append(Transform3D(Basis.IDENTITY, Vector3(cx + sx * DRAIN_OFF, WEAR_Y, cz + sz * DRAIN_AT)))
					drains.append(Transform3D(Basis.from_euler(Vector3(0, PI * 0.5, 0)), Vector3(cx + sx * DRAIN_AT, WEAR_Y, cz + sz * DRAIN_OFF)))
	for j in EW_COUNT:
		var cz := EW_Z0 + EW_DZ * float(j)
		_lane_wear(lids, patches, Vector3(EW_X_RANGE.x, 0.0, cz), Vector3(1, 0, 0), EW_X_RANGE.y - EW_X_RANGE.x, Vector3(0, 0, 1), _ns_centres())
	_emit(_lid_mesh(), _iron(), lids)
	_emit(_drain_mesh(), _iron(), drains)
	_emit(_patch_mesh(), _tar(), patches)
	print("STREET WEAR: %d lids, %d drains, %d patches, 3 draw calls" % [lids.size(), drains.size(), patches.size()])
	if OS.get_cmdline_user_args().has("--wear-diag") and not lids.is_empty():
		_diag_lid = lids[0].origin
		_diag.call_deferred()


var _diag_lid := Vector3.ZERO

## `--wear-diag`: where is the first lid, what is under it, and is anything visible.
func _diag() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	print("WEAR DIAG layer global=%s visible_in_tree=%s children=%d" % [global_position, is_visible_in_tree(), get_child_count()])
	for c in get_children():
		if c is MultiMeshInstance3D:
			var mmi := c as MultiMeshInstance3D
			var aabb := mmi.get_aabb()
			print("WEAR DIAG mmi %s inst=%d aabb pos=%s size=%s vis=%s layers=%d" % [mmi.multimesh.mesh.get_class(), mmi.multimesh.instance_count, aabb.position, aabb.size, mmi.is_visible_in_tree(), mmi.layers])
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(_diag_lid + Vector3.UP * 5.0, _diag_lid + Vector3.DOWN * 5.0)
	var hit := space.intersect_ray(q)
	print("WEAR DIAG lid0 at %s; road hit=%s" % [_diag_lid, (str(hit.get("position")) + " " + str((hit.get("collider") as Node).name)) if not hit.is_empty() else "NONE"])
	var cam := get_viewport().get_camera_3d()
	print("WEAR DIAG camera=%s" % [cam.global_position if cam != null else "none"])


## Along one street: lids on both travel lanes every MANHOLE_STEP, patches at
## random along the lanes, none inside a crossing box.
func _lane_wear(lids: Array[Transform3D], patches: Array[Transform3D], start: Vector3,
		along: Vector3, length: float, across: Vector3, crossings: Array[float]) -> void:
	var s := _rng.randf_range(6.0, MANHOLE_STEP)
	while s < length:
		for side: float in [-1.0, 1.0]:
			var p := start + along * s + across * (side * LANE_C)
			if not _in_crossing(p, along, crossings):
				lids.append(Transform3D(Basis.from_euler(Vector3(0, _rng.randf() * TAU, 0)), Vector3(p.x, WEAR_Y, p.z)))
		s += MANHOLE_STEP + _rng.randf_range(-6.0, 6.0)
	var n := int(length * 2.0 * PATCH_PER_LANE_M)
	for _i in n:
		var t := _rng.randf() * length
		var off := _rng.randf_range(-KERB + 2.0, KERB - 2.0)
		var p := start + along * t + across * off
		if _in_crossing(p, along, crossings):
			continue
		var w := _rng.randf_range(PATCH_SIZE.x, PATCH_SIZE.y)
		var h := _rng.randf_range(PATCH_SIZE.x, PATCH_SIZE.y)
		var yaw := atan2(along.x, along.z) + _rng.randf_range(-0.12, 0.12) + (PI * 0.5 if _rng.randf() < 0.5 else 0.0)
		var b := Basis.from_euler(Vector3(0, yaw, 0)).scaled(Vector3(w, 1.0, h))
		patches.append(Transform3D(b, Vector3(p.x, WEAR_Y - 0.001, p.z)))


func _in_crossing(p: Vector3, along: Vector3, crossings: Array[float]) -> bool:
	var coord := p.z if along.z != 0.0 else p.x
	for c in crossings:
		if absf(coord - c) < CROSS_CLEAR:
			return true
	return false


func _ew_centres() -> Array[float]:
	var out: Array[float] = []
	for j in EW_COUNT:
		out.append(EW_Z0 + EW_DZ * float(j))
	return out


func _ns_centres() -> Array[float]:
	var out: Array[float] = []
	for i in NS_COUNT:
		out.append(NS_X0 + NS_DX * float(i))
	return out


# ============================== MESHES =======================================
## A lid: a flat cast-iron disc with a raised rim and a shallow pick hole, one
## lathe. Front faces per the winding law (D-021): quads wound so the normal
## points OUT of the iron.
func _lid_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEG := 24
	# (radius, height) profile from the outer edge inward; the top is what reads.
	var prof: Array[Vector2] = [
		Vector2(MANHOLE_R, 0.0), Vector2(MANHOLE_R, 0.014), Vector2(MANHOLE_R * 0.90, 0.016),
		Vector2(MANHOLE_R * 0.86, 0.011), Vector2(MANHOLE_R * 0.18, 0.011), Vector2(MANHOLE_R * 0.12, 0.006),
		Vector2(0.0, 0.006)]
	for i in prof.size() - 1:
		st.set_smooth_group(i)
		for k in SEG:
			var a0 := TAU * float(k) / float(SEG)
			var a1 := TAU * float(k + 1) / float(SEG)
			var p00 := _lathe(prof[i], a0); var p10 := _lathe(prof[i + 1], a0)
			var p11 := _lathe(prof[i + 1], a1); var p01 := _lathe(prof[i], a1)
			st.add_vertex(p00); st.add_vertex(p01); st.add_vertex(p11)
			st.add_vertex(p00); st.add_vertex(p11); st.add_vertex(p10)
	st.generate_normals()
	return st.commit()


func _lathe(p: Vector2, a: float) -> Vector3:
	return Vector3(cos(a) * p.x, p.y, sin(a) * p.x)


## A drain: a shallow iron frame with five slats and the dark slots between them.
func _drain_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var half := DRAIN_SIZE * 0.5
	_box(st, Vector3(-half.x, 0.0, -half.z), Vector3(half.x, 0.004, half.z))          # the bed (dark slots)
	var slats := 5
	for i in slats:
		var x0 := -half.x + 0.03 + (DRAIN_SIZE.x - 0.06) * float(i) / float(slats)
		_box(st, Vector3(x0, 0.0, -half.z), Vector3(x0 + 0.055, DRAIN_SIZE.y, half.z))  # a slat
	_box(st, Vector3(-half.x, 0.0, -half.z), Vector3(half.x, DRAIN_SIZE.y, -half.z + 0.03))  # frame
	_box(st, Vector3(-half.x, 0.0, half.z - 0.03), Vector3(half.x, DRAIN_SIZE.y, half.z))
	st.generate_normals()
	return st.commit()


## An axis-aligned box into a SurfaceTool, wound clockwise for Godot's front face.
func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var v := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z)]
	var faces := [[4, 5, 6, 7], [0, 3, 2, 1], [0, 1, 5, 4], [3, 7, 6, 2], [0, 4, 7, 3], [1, 2, 6, 5]]
	for f: Array in faces:
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[2]]); st.add_vertex(v[f[1]])
		st.add_vertex(v[f[0]]); st.add_vertex(v[f[3]]); st.add_vertex(v[f[2]])


## A patch: a unit quad the instance transform scales; the alpha texture gives
## it a ragged, soft edge so it reads as poured tar, not a sticker.
func _patch_mesh() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	q.orientation = PlaneMesh.FACE_Y
	return q


func _iron() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = IRON
	m.roughness = 0.62
	m.metallic = 0.35
	return m


func _tar() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = TAR
	m.roughness = 0.55
	m.albedo_texture = _blotch_texture()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_BACK
	return m


## 64² soft blotch: a ragged disc, darker centre, alpha fading to nothing.
func _blotch_texture() -> ImageTexture:
	var n := 64
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED + 1
	var wob: Array[float] = []
	for _i in 12:
		wob.append(rng.randf_range(0.72, 1.0))
	for y in n:
		for x in n:
			var u := (float(x) + 0.5) / float(n) * 2.0 - 1.0
			var v := (float(y) + 0.5) / float(n) * 2.0 - 1.0
			var ang := atan2(v, u)
			var seg := int(fposmod(ang / TAU, 1.0) * 12.0) % 12
			var edge: float = lerpf(wob[seg], wob[(seg + 1) % 12], fposmod(ang / TAU * 12.0, 1.0))
			var r := sqrt(u * u + v * v) / edge
			var a := clampf((1.0 - r) * 3.2, 0.0, 1.0) * 0.86
			var shade := 1.0 - 0.25 * clampf(1.0 - r, 0.0, 1.0)
			img.set_pixel(x, y, Color(shade, shade, shade, a))
	return ImageTexture.create_from_image(img)


func _emit(mesh: Mesh, mat: Material, xfs: Array[Transform3D]) -> void:
	if xfs.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xfs.size()
	var bounds := AABB(xfs[0].origin, Vector3.ZERO)
	for i in xfs.size():
		mm.set_instance_transform(i, xfs[i])
		bounds = bounds.expand(xfs[i].origin)
	# The renderer's own AABB for a script-built MultiMesh read (0,0,0)/(0,0,0)
	# two frames after build (`--wear-diag`) — culled everywhere, "a clean
	# road". Hand it the bounds: every origin, grown by the largest instance.
	mm.custom_aabb = bounds.grow(4.0)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # D-028: decals never cast
	# No visibility range: it is measured from the INSTANCE's origin, which for a
	# grid-wide MultiMesh is the world origin, 400 m from downtown — the first
	# sweep culled the whole layer and the plate showed a clean road.
	add_child(mmi)
