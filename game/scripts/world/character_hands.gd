extends RefCounted
## Fine-resolution hand anatomy consumed by the body's existing field mesher.
static func parts(side: float) -> Array:
	var result: Array = []
	result.append([Vector3(0, 0.024, 0), Vector3(0, -0.020, 0), 0.025, 0.019, Vector3(1, 1, 0.9), 0.008])
	result.append([Vector3(0, -0.008, 0), Vector3(side * 0.002, -0.067, 0), 0.021, 0.020, Vector3(0.72, 1, 1.65), 0.009])
	var zs := [-0.025, -0.007, 0.012, 0.029]
	var lengths := [0.061, 0.079, 0.073, 0.054]
	# D-060: a RELAXED hand. The fingers used to hang dead straight — a paddle.
	# At rest the proximal joint flexes ~15 deg and the middle joint ~40 deg
	# toward the palm (-side x is the palm side: the thumb crosses that way), so
	# the tips hang a couple of centimetres in front of the palm. Still one
	# field: the 4 mm mesher unions the bent segments as it did the straight.
	for i in 4:
		var start := Vector3(side * 0.002, -0.062, zs[i])
		var l1: float = float(lengths[i]) * 0.53
		var l2: float = float(lengths[i]) * 0.47
		var middle := start + Vector3(-side * (0.004 + l1 * 0.26), -l1 * 0.965, 0)
		var end := middle + Vector3(-side * l2 * 0.64, -l2 * 0.77, 0)
		result.append([start, middle, 0.009, 0.008, Vector3.ONE, 0.004])
		result.append([middle, end, 0.008, 0.006, Vector3.ONE, 0.003])
	result.append([Vector3(0, -0.018, -0.024), Vector3(-side * 0.010, -0.041, -0.044), 0.015, 0.011, Vector3.ONE, 0.008])
	result.append([Vector3(-side * 0.010, -0.041, -0.044), Vector3(-side * 0.016, -0.067, -0.054), 0.011, 0.008, Vector3.ONE, 0.004])
	return result
