extends SceneTree
## PARSE GATE — every script in the tree compiled in ONE boot, no game.
##   cd game/ && godot --headless --script res://tools/parse_all.gd
## Prints PARSE: <n> scripts, <e> failed and exits 1 on any failure. A broken
## script prints its own SCRIPT ERROR lines above the summary. ~5 s, so it runs
## before every smoke and as the pre-commit hook (D-055). A file that fails to
## load here would have disabled a whole system at boot without a trace (D-074).
func _init() -> void:
	var failed := 0
	var total := 0
	for root in ["res://scripts", "res://tools"]:
		for path in _gd_files(root):
			if path == "res://tools/parse_all.gd":
				continue   # reload() of the running script is not a parse verdict
			total += 1
			var s: Variant = ResourceLoader.load(path, "GDScript", ResourceLoader.CACHE_MODE_REPLACE)
			# The loader returns a GDScript object even when its source failed to
			# compile (the ERROR line above it is the only sign); reload() reports
			# the compile result as an Error, which is what a gate needs.
			if s == null or (s as GDScript).reload() != OK:
				failed += 1
				push_error("PARSE FAIL: " + path)
	print("PARSE: %d scripts, %d failed" % [total, failed])
	quit(1 if failed > 0 else 0)


static func _gd_files(dir_path: String) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(dir_path)
	if d == null:
		return out
	d.list_dir_begin()
	var name := d.get_next()
	while name != "":
		var p := dir_path.path_join(name)
		if d.current_is_dir():
			if not name.begins_with("."):
				out.append_array(_gd_files(p))
		elif name.ends_with(".gd"):
			out.append(p)
		name = d.get_next()
	d.list_dir_end()
	out.sort()
	return out
