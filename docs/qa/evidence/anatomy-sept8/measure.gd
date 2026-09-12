extends SceneTree
func _initialize() -> void:
	_run.call_deferred()
func _run() -> void:
	for path in [get_script().resource_path.get_base_dir() + "/baseline_skinned.gd", "res://scripts/world/skinned_character.gd"]:
		var script = load(path)
		var mesh: ArrayMesh = script._mesh_for(1.06, 1.02)
		var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
		var foot_min := INF
		var foot_max := -INF
		var chest_min := INF
		var chest_max := -INF
		for p in vertices:
			assert(p.is_finite())
			if p.y < 0.10:
				foot_min = minf(foot_min, p.z)
				foot_max = maxf(foot_max, p.z)
			if p.y > 1.30 and p.y < 1.37 and absf(p.x) < 0.10:
				chest_min = minf(chest_min, p.z)
				chest_max = maxf(chest_max, p.z)
		print("BODY MEASURE ", path, " foot_length_mm=", (foot_max-foot_min)*1000, " chest_depth_mm=", (chest_max-chest_min)*1000)
	quit()
