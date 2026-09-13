extends SceneTree
## BODY MEASURE (D-061) — the skinned body's silhouette as NUMBERS. Builds the
## 18 mm body field from skinned_character._prims(w, g) exactly as the bake does
## and, at each anatomical height, reports the outer x-span, the depth (z-span),
## and each separate mass across x (1 = trunk, 2 = legs or arms) with its width.
## Compare against the anthropometric row in docs/qa/anatomy-sept13.md.
##   godot --headless --script res://tools/body_measure.gd -- --w=1.0 --g=1.0
const SKIN := preload("res://scripts/world/skinned_character.gd")
const HEIGHTS := [
	["shoulders (deltoid line)", 1.425], ["upper chest", 1.380], ["chest (nipple line)", 1.300],
	["under ribs", 1.190], ["waist", 1.080], ["belt", 1.030], ["hips (trochanter)", 0.900],
	["crotch", 0.840], ["upper thigh", 0.760], ["mid thigh", 0.650], ["knee", 0.480],
	["calf", 0.370], ["ankle", 0.110], ["upper arm", 1.250], ["forearm", 1.050], ["wrist", 0.930]]


func _init() -> void:
	var w := 1.0
	var g := 1.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--w="): w = float(a.substr(4))
		if a.begins_with("--g="): g = float(a.substr(4))
	var prims: Array = SKIN._prims(w, g)
	var fp: PackedFloat32Array = SKIN._flatten(prims)
	var grid: Dictionary = SKIN._field_grid(prims, fp, SKIN.VOX)
	var f: PackedFloat32Array = grid.f
	var lo: Vector3 = grid.lo
	var nx: int = grid.nx; var ny: int = grid.ny; var nz: int = grid.nz; var syz: int = grid.syz
	var vox: float = SKIN.VOX
	print("BODY MEASURE w=%.2f g=%.2f vox=%.3f grid=%dx%dx%d" % [w, g, vox, nx, ny, nz])
	print("| height | y | x-span | depth | masses (width each) |")
	print("|---|---|---|---|---|")
	for row: Array in HEIGHTS:
		var y: float = row[1]
		var j := clampi(int(round((y - lo.y) / vox)), 0, ny - 1)
		var xmin := INF; var xmax := -INF; var zmin := INF; var zmax := -INF
		var cols := PackedByteArray(); cols.resize(nx)
		for i in nx:
			var any := false
			for k in nz:
				if f[i * syz + j * nz + k] < 0.0:
					any = true
					var z := lo.z + k * vox
					zmin = minf(zmin, z); zmax = maxf(zmax, z)
			cols[i] = 1 if any else 0
			if any:
				var x := lo.x + i * vox
				xmin = minf(xmin, x); xmax = maxf(xmax, x)
		var masses: Array[String] = []
		var run := 0
		for i in nx + 1:
			if i < nx and cols[i] == 1:
				run += 1
			elif run > 0:
				masses.append("%.3f" % (run * vox)); run = 0
		if xmin == INF:
			print("| %s | %.3f | — | — | — |" % [row[0], y]); continue
		print("| %s | %.3f | %.3f | %.3f | %d: %s |" % [row[0], y, xmax - xmin + vox, zmax - zmin + vox, masses.size(), ", ".join(masses)])
	quit(0)
