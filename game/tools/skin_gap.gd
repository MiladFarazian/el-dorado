extends SceneTree
const SKIN := preload("res://scripts/world/skinned_character.gd")
func _init() -> void:
	var prims = SKIN._prims(1.02, 1.05)
	var fp = SKIN._flatten(prims)
	print("field along +x at several heights (negative = inside the body)")
	for y in [0.80, 0.86, 0.90, 0.95, 1.00, 1.10, 1.25, 1.35]:
		var line := "y=%.2f : " % y
		var inside_runs := 0
		var prev := 1.0
		for i in 40:
			var x := 0.02 * float(i)
			var d: float = SKIN._field(fp, Vector3(x, y, 0.0))
			if d < 0.0 and prev >= 0.0:
				inside_runs += 1
			prev = d
			if i % 2 == 0:
				line += ("#" if d < 0.0 else ".")
		print(line + "  runs=%d" % inside_runs)
	print("(each char = 4 cm of x from 0.00 to 0.80; two runs = leg and arm are separate)")
	quit(0)
