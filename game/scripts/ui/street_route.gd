extends RefCounted
## Downtown GPS uses the real connected street grid. Outside this network the
## UI shows a destination bearing, never a fabricated line through buildings.
const DRESS := preload("res://scripts/world/city_dressing.gd")
var graph := AStar2D.new()
var edges: Array[Vector2i] = []

func _init() -> void:
	var width: int = DRESS.NS_X.size()
	for z in DRESS.EW_Z.size():
		for x in width:
			var id := z * width + x
			graph.add_point(id, Vector2(DRESS.NS_X[x], DRESS.EW_Z[z]))
	for z in DRESS.EW_Z.size():
		for x in width:
			var id := z * width + x
			if x + 1 < width:
				_connect(id, id + 1)
			if z + 1 < DRESS.EW_Z.size():
				_connect(id, id + width)
	graph.add_point(100, Vector2(365, 640))
	_connect((DRESS.EW_Z.size() - 1) * width + 2, 100)

func _connect(a: int, b: int) -> void:
	graph.connect_points(a, b)
	edges.append(Vector2i(a, b))

func _nearest(point: Vector2) -> Dictionary:
	var result := {}
	var best := INF
	for edge in edges:
		var projection := Geometry2D.get_closest_point_to_segment(point, graph.get_point_position(edge.x), graph.get_point_position(edge.y))
		var distance := point.distance_to(projection)
		if distance < best:
			best = distance
			result = {"edge": edge, "pos": projection, "distance": distance}
	return result

func build_route(start: Vector2, finish: Vector2) -> PackedVector2Array:
	var a := _nearest(start)
	var b := _nearest(finish)
	if a.distance > 24.0 or b.distance > 24.0:
		return PackedVector2Array()
	graph.add_point(1000, a.pos)
	graph.add_point(1001, b.pos)
	for id in [a.edge.x, a.edge.y]:
		graph.connect_points(1000, id)
	for id in [b.edge.x, b.edge.y]:
		graph.connect_points(1001, id)
	if a.edge == b.edge:
		graph.connect_points(1000, 1001)
	var points := graph.get_point_path(1000, 1001)
	graph.remove_point(1000)
	graph.remove_point(1001)
	var result := PackedVector2Array([start])
	result.append_array(points)
	result.append(finish)
	return result
