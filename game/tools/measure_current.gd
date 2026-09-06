extends SceneTree
## Offline measurement of the CURRENT character_factory build. Read-only.
##   cd game/ && godot --headless --script res://tools/measure_current.gd

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
			var mm: Dictionary = acc["mats"]
			var key := str((c as MeshInstance3D).material_override)
			mm[key] = true
		elif c is Label3D:
			acc["labels"] = int(acc["labels"]) + 1
		_count(c, acc)


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260803
	var rows: Array = []
	var configs: Array = []
	for i in 8:
		configs.append(["ped_%d" % i, FACTORY.random_config(rng)])
	configs.append(["cop", FACTORY.cop_config(rng)])
	configs.append(["book", FACTORY.book_config()])
	var t0 := Time.get_ticks_usec()
	for entry in configs:
		var root := Node3D.new()
		root.name = "T_" + str(entry[0])
		var acc := {"nodes": 0, "meshes": 0, "tris": 0, "verts": 0, "labels": 0,
			"mats": {}}
		var t := Time.get_ticks_usec()
		FACTORY.build(root, entry[1], 0.0)
		var dt := (Time.get_ticks_usec() - t) / 1000.0
		_count(root, acc)
		rows.append([entry[0], acc["nodes"], acc["meshes"], acc["tris"],
			acc["verts"], (acc["mats"] as Dictionary).size(), dt])
		root.free()
	var total := (Time.get_ticks_usec() - t0) / 1000.0
	print("CURRENT CHARACTER FACTORY — measured")
	print("name        nodes  meshInst   tris   verts  mats  build_ms")
	var sm := 0; var st := 0; var sn := 0
	for r in rows:
		print("%-10s %6d %8d %7d %7d %5d %8.2f" % r)
		sm += int(r[2]); st += int(r[3]); sn += int(r[1])
	print("MEAN meshInst=%.1f tris=%.1f nodes=%.1f over %d configs (total %.1f ms)"
		% [float(sm) / rows.size(), float(st) / rows.size(),
		float(sn) / rows.size(), rows.size(), total])
	quit(0)
