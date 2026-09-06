extends SceneTree
## Offline bake + validation of the skinned body. Read-only w.r.t. the game.
##   cd game/ && godot --headless --script res://tools/measure_skin.gd

const SKIN := preload("res://scripts/world/skinned_character.gd")
const FACTORY := preload("res://scripts/world/character_factory.gd")


func _count(n: Node, acc: Dictionary) -> void:
	for c in n.get_children():
		acc["nodes"] = int(acc["nodes"]) + 1
		if c is MeshInstance3D:
			acc["meshes"] = int(acc["meshes"]) + 1
			var m: Mesh = (c as MeshInstance3D).mesh
			if m != null:
				for s in m.get_surface_count():
					var arr := m.surface_get_arrays(s)
					var vtx: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
					acc["verts"] = int(acc["verts"]) + vtx.size()
					var ic := 0
					if arr[Mesh.ARRAY_INDEX] != null:
						ic = (arr[Mesh.ARRAY_INDEX] as PackedInt32Array).size()
					acc["tris"] = int(acc["tris"]) + (ic / 3 if ic > 0 else vtx.size() / 3)
		_count(c, acc)


## Manifold + winding audit of one baked surface.
func _audit(mesh: ArrayMesh, tag: String) -> void:
	var arr := mesh.surface_get_arrays(0)
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nrm: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var wts: PackedFloat32Array = arr[Mesh.ARRAY_WEIGHTS]
	var edge := {}
	var tri := idx.size() / 3
	var agree := 0
	var area := 0.0
	for t in tri:
		var a := idx[t * 3]; var b := idx[t * 3 + 1]; var c := idx[t * 3 + 2]
		# Godot's front face is the CLOCKWISE one: its outward normal is
		# (c-a)x(b-a), not (b-a)x(c-a) (D-021's law; D-051 found the skinned
		# bake wound the other way and rendering every body inside out — this
		# metric said 99.9% because it measured the same wrong-handed rule).
		var fn := (v[c] - v[a]).cross(v[b] - v[a])
		area += fn.length() * 0.5
		if fn.normalized().dot((nrm[a] + nrm[b] + nrm[c]).normalized()) > 0.0:
			agree += 1
		# Key on POSITION, not on vertex index. The zone split duplicates the
		# vertices along every garment seam so each triangle's corners can agree
		# on one zone, so an index-keyed audit reports thousands of "boundary"
		# edges that are UV seams and not holes.
		for e in 3:
			var pa := v[idx[t * 3 + e]]
			var pb := v[idx[t * 3 + (e + 1) % 3]]
			var ka := "%.4f_%.4f_%.4f" % [pa.x, pa.y, pa.z]
			var kb := "%.4f_%.4f_%.4f" % [pb.x, pb.y, pb.z]
			var key: String = (ka + "|" + kb) if ka < kb else (kb + "|" + ka)
			edge[key] = int(edge.get(key, 0)) + 1
	var bad := 0
	var boundary := 0
	for k: String in edge:
		var n := int(edge[k])
		if n == 1: boundary += 1
		elif n != 2: bad += 1
	# weight sanity
	var wmin := 9.0
	var wmax := -9.0
	for i in v.size():
		var s := wts[i * 4] + wts[i * 4 + 1] + wts[i * 4 + 2] + wts[i * 4 + 3]
		wmin = minf(wmin, s); wmax = maxf(wmax, s)
	var lo := Vector3(1e9, 1e9, 1e9)
	var hi := Vector3(-1e9, -1e9, -1e9)
	for p in v:
		lo = lo.min(p); hi = hi.max(p)
	print("  %-8s verts=%5d tris=%5d area=%.3f m2 | boundary_edges=%d nonmanifold=%d"
		% [tag, v.size(), tri, area, boundary, bad])
	print("           winding_agrees=%.1f%%  weightsum=[%.4f..%.4f]  aabb=%.3f..%.3f y"
		% [100.0 * float(agree) / float(maxi(tri, 1)), wmin, wmax, lo.y, hi.y])
	print("           x=%.3f..%.3f  z=%.3f..%.3f" % [lo.x, hi.x, lo.z, hi.z])


func _init() -> void:
	SKIN._no_disk = true
	print("SKINNED BODY — bake audit")
	var t0 := Time.get_ticks_usec()
	var buckets := [[0.97, 0.93], [1.07, 0.93], [0.97, 1.07], [1.07, 1.07],
		[0.97, 1.22], [1.07, 1.22]]
	for b in buckets:
		var t := Time.get_ticks_usec()
		var m: ArrayMesh = SKIN._bake(float(b[0]), float(b[1]))
		var dt := (Time.get_ticks_usec() - t) / 1000.0
		_audit(m, "w%.2f g%.2f" % [b[0], b[1]])
		print("           bake=%.0f ms" % dt)
	print("ALL SIX BUCKETS baked in %.0f ms" % ((Time.get_ticks_usec() - t0) / 1000.0))

	# ---- full character assembly, both paths, same configs
	print("")
	print("ASSEMBLED CHARACTER — parts, tris, build time")
	SKIN._mesh_cache.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260803
	var cfgs: Array = []
	for i in 8:
		cfgs.append(["ped_%d" % i, FACTORY.random_config(rng)])
	cfgs.append(["cop", FACTORY.cop_config(rng)])
	cfgs.append(["book", FACTORY.book_config()])
	print("name        path      nodes  meshInst   tris  build_ms")
	var agg := {"old": [0, 0, 0.0], "new": [0, 0, 0.0]}
	for e in cfgs:
		for which in ["old", "new"]:
			var root := Node3D.new()
			var acc := {"nodes": 0, "meshes": 0, "tris": 0, "verts": 0}
			var t := Time.get_ticks_usec()
			if which == "old":
				FACTORY.build(root, e[1], 0.0)
			else:
				SKIN.build(root, e[1], 0.0)
			var dt := (Time.get_ticks_usec() - t) / 1000.0
			_count(root, acc)
			print("%-10s %-8s %6d %8d %7d %8.2f"
				% [e[0], which, acc["nodes"], acc["meshes"], acc["tris"], dt])
			agg[which][0] += int(acc["meshes"])
			agg[which][1] += int(acc["tris"])
			agg[which][2] += dt
			root.free()
	var n := float(cfgs.size())
	for which in ["old", "new"]:
		print("MEAN %-4s meshInst=%.1f tris=%.0f build=%.2f ms"
			% [which, agg[which][0] / n, agg[which][1] / n, agg[which][2] / n])
	print(SKIN.bake_stats())
	quit(0)
