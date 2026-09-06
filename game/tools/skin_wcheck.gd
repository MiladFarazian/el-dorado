extends SceneTree
const SKIN := preload("res://scripts/world/skinned_character.gd")
func _init() -> void:
	SKIN._no_disk = true
	var m: ArrayMesh = SKIN._bake(1.02, 1.05)
	var a := m.surface_get_arrays(0)
	var v: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
	var bn: PackedInt32Array = a[Mesh.ARRAY_BONES]
	var wt: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
	print("verts=%d bones/4=%d weights/4=%d" % [v.size(), bn.size() / 4, wt.size() / 4])
	var bad := 0; var wsum_bad := 0; var zero := 0
	var maxb := 0
	for i in v.size():
		var s := 0.0
		for q in 4:
			var b := bn[i * 4 + q]
			maxb = maxi(maxb, b)
			if b < 0 or b >= 12: bad += 1
			s += wt[i * 4 + q]
		if absf(s - 1.0) > 0.01: wsum_bad += 1
		if s < 0.001: zero += 1
	print("bad bone idx=%d  weightsum!=1 count=%d  zero-weight verts=%d  maxbone=%d"
		% [bad, wsum_bad, zero, maxb])
	# per-bone vertex share, to see if any bone owns an implausible slice
	var share := PackedFloat32Array(); share.resize(12)
	for i in v.size():
		for q in 4:
			share[bn[i * 4 + q]] += wt[i * 4 + q]
	var names := ["root","hip0","knee0","hip1","knee1","torso","collar","head","sh0","el0","sh1","el1"]
	for b in 12:
		print("  %-6s %.1f%%" % [names[b], 100.0 * share[b] / float(v.size())])
	# where do arm-dominant vertices actually LIVE?
	var lo := Vector3(9, 9, 9); var hi := Vector3(-9, -9, -9)
	var stray := 0
	for i in v.size():
		var b := bn[i * 4]
		if b == 9 or b == 11:      # el_0 / el_1 dominant
			lo = lo.min(v[i]); hi = hi.max(v[i])
			if absf(v[i].x) < 0.20 and v[i].y < 0.98:
				stray += 1
	print("elbow-dominant bbox x=[%.3f %.3f] y=[%.3f %.3f]" % [lo.x, hi.x, lo.y, hi.y])
	print("elbow-dominant verts inside leg/hip territory: %d" % stray)
	lo = Vector3(9, 9, 9); hi = Vector3(-9, -9, -9)
	var stray2 := 0
	for i in v.size():
		var b := bn[i * 4]
		if b == 8 or b == 10:      # sh_0 / sh_1 dominant
			lo = lo.min(v[i]); hi = hi.max(v[i])
			if absf(v[i].x) < 0.16:
				stray2 += 1
	print("shoulder-dominant bbox x=[%.3f %.3f] y=[%.3f %.3f]" % [lo.x, hi.x, lo.y, hi.y])
	print("shoulder-dominant verts inboard of |x|=0.16: %d" % stray2)
	quit(0)
