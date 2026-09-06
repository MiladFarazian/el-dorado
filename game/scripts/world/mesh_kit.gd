extends RefCounted
## MESH KIT (M10) — real geometry, still 100% code and zero asset files.
## Boxes can't describe a car: a hood slopes, a windshield rakes, a roof is
## narrower than the beltline (tumblehome), a fender flares. These builders
## emit flat-shaded ArrayMeshes for exactly those shapes, cached by parameter
## key so a fleet of identical cars shares one mesh resource.
##
## Everything is deterministic and allocation-light after first use. Flat
## shading throughout (set_smooth_group(-1)) to keep the stylized read — this
## is a sharper greybox, not an attempt at photoreal.

static var _cache: Dictionary = {}


## A box whose TOP face may be a different size and shifted in plan. One shape
## covers: plain boxes, wedges (hood slope), tapered cabins (tumblehome),
## truncated pyramids (roof tapers), leaning posts.
##   size      full bottom extents (x, y, z)
##   top_size  top face extents (x, z); defaults to the bottom
##   top_shift top face centre offset (x, z)
static func taper(size: Vector3, top_size: Vector2, top_shift := Vector2.ZERO) -> ArrayMesh:
	var key := "t_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f_%.3f" % [size.x, size.y, size.z,
		top_size.x, top_size.y, top_shift.x, top_shift.y]
	if _cache.has(key):
		return _cache[key]
	var bx := size.x * 0.5
	var bz := size.z * 0.5
	var hy := size.y * 0.5
	var tx := top_size.x * 0.5
	var tz := top_size.y * 0.5
	var sx := top_shift.x
	var sz := top_shift.y
	var b := [Vector3(-bx, -hy, -bz), Vector3(bx, -hy, -bz),
		Vector3(bx, -hy, bz), Vector3(-bx, -hy, bz)]
	var t := [Vector3(sx - tx, hy, sz - tz), Vector3(sx + tx, hy, sz - tz),
		Vector3(sx + tx, hy, sz + tz), Vector3(sx - tx, hy, sz + tz)]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)                       # flat faces, hard edges
	_quad(st, b[0], b[3], b[2], b[1])             # bottom (faces -Y)
	_quad(st, t[0], t[1], t[2], t[3])             # top
	_quad(st, b[0], b[1], t[1], t[0])             # -Z front
	_quad(st, b[1], b[2], t[2], t[1])             # +X right
	_quad(st, b[2], b[3], t[3], t[2])             # +Z back
	_quad(st, b[3], b[0], t[0], t[3])             # -X left
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


## Extrude a closed 2D side profile (x = length along Z, y = height) across a
## width, with an optional narrower top width for tumblehome. This is what
## gives a car its actual silhouette: one polygon describes nose, hood, glass,
## roof and deck in a single continuous shape.
##   profile  CCW points in the (z, y) plane, centred on the origin
##   width    full width at the profile's LOWEST point
##   top_w    full width at the profile's HIGHEST point (lerped by height)
static func loft(profile: PackedVector2Array, width: float, top_w: float,
		key_hint: String, smooth := false) -> ArrayMesh:
	var key := "l_%s_%.3f_%.3f_%s" % [key_hint, width, top_w, str(smooth)]
	if _cache.has(key):
		return _cache[key]
	var n := profile.size()
	if n < 3:
		return taper(Vector3(1, 1, 1), Vector2(1, 1))
	var lo := INF
	var hi := -INF
	for p in profile:
		lo = minf(lo, p.y)
		hi = maxf(hi, p.y)
	var span := maxf(hi - lo, 0.0001)
	var half: PackedFloat32Array = PackedFloat32Array()
	half.resize(n)
	for i in n:
		half[i] = lerpf(width, top_w, (profile[i].y - lo) / span) * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# M15: `smooth` merges normals around the profile loop so a curved hood /
	# roof reads as a curve, not a stack of facets. Caps stay flat (planar).
	st.set_smooth_group(0 if smooth else -1)
	# Side walls: one quad per profile edge, mirrored left and right.
	for i in n:
		var j := (i + 1) % n
		var a := profile[i]
		var c := profile[j]
		_quad(st, Vector3(half[i], a.y, a.x), Vector3(half[j], c.y, c.x),
			Vector3(-half[j], c.y, c.x), Vector3(-half[i], a.y, a.x))
	# Caps (the car's flanks): triangle fan from the first profile point.
	# A profile listed CCW in the (z, y) plane reads CW when viewed from +X, so
	# the +X fan is emitted REVERSED and the -X fan forward. (Worked by hand:
	# for p0(-1,-1) p1(1,-1) p2(1,1) at x=+1 the forward winding yields a -X
	# normal — i.e. an inside-out flank you can see straight through.)
	for i in range(1, n - 1):
		var p0 := profile[0]
		var p1 := profile[i]
		var p2 := profile[i + 1]
		_tri(st, Vector3(half[i + 1], p2.y, p2.x), Vector3(half[i], p1.y, p1.x),
			Vector3(half[0], p0.y, p0.x))
		_tri(st, Vector3(-half[0], p0.y, p0.x), Vector3(-half[i], p1.y, p1.x),
			Vector3(-half[i + 1], p2.y, p2.x))
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


## Rounded-ish cylinder for wheels/poles: N-sided prism, flat shaded.
static func prism(radius: float, height: float, sides: int) -> ArrayMesh:
	var key := "p_%.3f_%.3f_%d" % [radius, height, sides]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)
	var hy := height * 0.5
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var p0 := Vector3(cos(a0) * radius, -hy, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, -hy, sin(a1) * radius)
		_quad(st, p0, p1, p1 + Vector3(0, height, 0), p0 + Vector3(0, height, 0))
		_tri(st, Vector3(0, hy, 0), p0 + Vector3(0, height, 0), p1 + Vector3(0, height, 0))
		_tri(st, Vector3(0, -hy, 0), p1, p0)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


# ============================ M15 — DE-BLOCKING ==============================
## Smooth-shaded UV sphere (unit-friendly: pass radius 0.5 and scale per
## instance; non-uniform instance scale gives squashed canopy blobs). Smooth
## group 0 + generate_normals = merged normals: actually round, not faceted.
static func sphere(radius: float, rings := 6, segs := 10) -> ArrayMesh:
	var key := "s_%.3f_%d_%d" % [radius, rings, segs]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for r in rings:
		var t0 := PI * float(r) / float(rings)
		var t1 := PI * float(r + 1) / float(rings)
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p00 := Vector3(sin(t0) * cos(a0), cos(t0), sin(t0) * sin(a0)) * radius
			var p01 := Vector3(sin(t0) * cos(a1), cos(t0), sin(t0) * sin(a1)) * radius
			var p10 := Vector3(sin(t1) * cos(a0), cos(t1), sin(t1) * sin(a0)) * radius
			var p11 := Vector3(sin(t1) * cos(a1), cos(t1), sin(t1) * sin(a1)) * radius
			# WINDING (M17 fix): these two triangles were emitted reversed, so
			# every sphere in the game — tree canopies, faces, water tanks,
			# prairie blobs — was INSIDE-OUT since M15. The renderer culled the
			# near hemisphere and drew the far inner wall, which shades as if
			# lit from behind (the waxy, inflated look) and writes the FAR
			# side's depth, so anything nested inside a ball melted into it.
			# Found by the M17 character agent measuring baked face normals
			# against the radial direction: outward=0, inward=360.
			if r > 0:
				_tri(st, p00, p11, p01)
			if r < rings - 1:
				_tri(st, p00, p10, p11)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


## Tapered round limb: an N-gon frustum with SMOOTH sides and flat caps — the
## anti-box for arms, legs, torsos, trunks. Origin at the centre, +Y up,
## radius r_bottom at -Y half-height, r_top at +Y.
## A tree crown (M23). Radius 1 sphere, radially displaced by two octaves of
## deterministic value noise so the silhouette is lobed rather than round, and
## the lower half pulled in (crowns are fuller above the branch line). One mesh
## shared by every instance; the per-instance yaw draw the dressings already
## make turns one lump pattern into hundreds of different trees.
static func canopy(radius: float, rings := 10, segs := 16, seed := 7, lump := 0.16,
		fine := 0.07) -> ArrayMesh:
	if OS.get_cmdline_user_args().has("--crowns-legacy"):
		return sphere(radius, 6, 10)   # A/B: the pre-M23 ball from the same tree
	var key := "cn_%.3f_%d_%d_%d_%.2f_%.2f" % [radius, rings, segs, seed, lump, fine]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(0)
	for r in rings:
		var t0 := PI * float(r) / float(rings)
		var t1 := PI * float(r + 1) / float(rings)
		for s in segs:
			var a0 := TAU * float(s) / float(segs)
			var a1 := TAU * float(s + 1) / float(segs)
			var p00 := _crown_pt(t0, a0, radius, seed, lump, fine)
			var p01 := _crown_pt(t0, a1, radius, seed, lump, fine)
			var p10 := _crown_pt(t1, a0, radius, seed, lump, fine)
			var p11 := _crown_pt(t1, a1, radius, seed, lump, fine)
			if r > 0:
				_tri(st, p00, p11, p01)
			if r < rings - 1:
				_tri(st, p00, p10, p11)
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


static func _crown_pt(t: float, a: float, radius: float, seed: int, lump: float,
		fine: float) -> Vector3:
	var d := Vector3(sin(t) * cos(a), cos(t), sin(t) * sin(a))
	var n1 := _vnoise3(d * 2.1 + Vector3(seed, 0.37 * seed, 1.9 * seed))
	var n2 := _vnoise3(d * 5.3 + Vector3(0.7 * seed, seed, 0.2 * seed))
	var rr := radius * (1.0 + lump * (n1 * 2.0 - 1.0) + fine * (n2 * 2.0 - 1.0))
	var p := d * rr
	if p.y < 0.0:
		p.y *= 0.82   # the crown's underside is flatter than its top
	return p


## Smooth deterministic value noise in [0,1] on a lattice (no engine RNG, so a
## mesh is byte-identical across boots).
static func _vnoise3(p: Vector3) -> float:
	var i := Vector3(floor(p.x), floor(p.y), floor(p.z))
	var f := p - i
	f = f * f * (Vector3(3, 3, 3) - 2.0 * f)   # smoothstep fade
	var acc := 0.0
	for dz in 2:
		for dy in 2:
			for dx in 2:
				var w := (f.x if dx == 1 else 1.0 - f.x) * (f.y if dy == 1 else 1.0 - f.y) \
					* (f.z if dz == 1 else 1.0 - f.z)
				acc += w * _hash3(i + Vector3(dx, dy, dz))
	return acc


static func _hash3(p: Vector3) -> float:
	var h := int(p.x) * 374761393 + int(p.y) * 668265263 + int(p.z) * 2147483647
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xFFFF) / 65535.0


static func round_limb(r_bottom: float, r_top: float, height: float, sides := 7) -> ArrayMesh:
	var key := "rl_%.3f_%.3f_%.3f_%d" % [r_bottom, r_top, height, sides]
	if _cache.has(key):
		return _cache[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hy := height * 0.5
	st.set_smooth_group(0)  # smooth around the girth
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		var b0 := Vector3(cos(a0) * r_bottom, -hy, sin(a0) * r_bottom)
		var b1 := Vector3(cos(a1) * r_bottom, -hy, sin(a1) * r_bottom)
		var t0 := Vector3(cos(a0) * r_top, hy, sin(a0) * r_top)
		var t1 := Vector3(cos(a1) * r_top, hy, sin(a1) * r_top)
		_quad(st, b0, b1, t1, t0)
	st.set_smooth_group(-1)  # flat caps
	for i in sides:
		var a0 := TAU * float(i) / float(sides)
		var a1 := TAU * float(i + 1) / float(sides)
		_tri(st, Vector3(0, hy, 0), Vector3(cos(a0) * r_top, hy, sin(a0) * r_top),
			Vector3(cos(a1) * r_top, hy, sin(a1) * r_top))
		_tri(st, Vector3(0, -hy, 0), Vector3(cos(a1) * r_bottom, -hy, sin(a1) * r_bottom),
			Vector3(cos(a0) * r_bottom, -hy, sin(a0) * r_bottom))
	st.generate_normals()
	var m: ArrayMesh = st.commit()
	_cache[key] = m
	return m


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
