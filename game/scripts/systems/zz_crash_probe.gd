extends Node
## CRASH PROBE — permanent QA infrastructure. `godot --headless -- --crash-probe`:
## drops an invisible wall 34 m ahead of the player's truck, full throttle into
## it, and asserts the hull mesh moved (sum of vertex displacement), a dent was
## counted, and hull points fell. Smoke-guarded; inert without the flag.
var main_ref: Node = null
var _t := 0.0
var _stage := 0
var _v0 := PackedVector3Array()
var _hp0 := 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")) or not OS.get_cmdline_user_args().has("--crash-probe"):
		set_physics_process(false); set_process(false); return


func _hull(v: Node) -> MeshInstance3D:
	var h := v.find_child("Hull", true, false)
	return h as MeshInstance3D if h is MeshInstance3D else null


func _verts(mi: MeshInstance3D) -> PackedVector3Array:
	var m := mi.mesh as ArrayMesh
	if m == null or m.get_surface_count() == 0: return PackedVector3Array()
	return m.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]


func _physics_process(delta: float) -> void:
	_t += delta
	var pv: Variant = main_ref.get("vehicle")
	if not (pv is RigidBody3D): return
	var v := pv as RigidBody3D
	match _stage:
		0:
			if _t < 1.5: return
			var wall := StaticBody3D.new()
			var cs := CollisionShape3D.new(); var bs := BoxShape3D.new(); bs.size = Vector3(8, 4, 1)
			cs.shape = bs; wall.add_child(cs)
			main_ref.add_child(wall)
			var fwd := -v.global_transform.basis.z
			wall.global_position = v.global_position + fwd * 34.0 + Vector3(0, 1.5, 0)
			wall.look_at(v.global_position, Vector3.UP)
			var h := _hull(v)
			_v0 = _verts(h) if h != null else PackedVector3Array()
			var dmg: Variant = (main_ref.get("systems") as Dictionary).get("vehicle_damage")
			_hp0 = float(v.get_meta("gunfire_hull", -1.0))
			print("CRASHPROBE wall placed 34 m ahead; hull verts=%d; damage system=%s" % [_v0.size(), dmg != null])
			v.call("set_external_input", 1.0, 0.0, 0.0, false)
			_stage = 1; _t = 0.0
		1:
			if _t < 5.0 and v.linear_velocity.length() > 1.0 or _t < 2.0: return
			var h := _hull(v)
			var v1 := _verts(h) if h != null else PackedVector3Array()
			# ORDER-INDEPENDENT metric: the hull's extent along the impact axis
			# (local -Z = the nose). A rebuilt surface may re-order vertices, so
			# a by-index diff is meaningless (it read 5.4 m on a 24 cm dent).
			var nose0 := _extent(_v0, Vector3(0, 0, -1))
			var nose1 := _extent(v1, Vector3(0, 0, -1))
			var moved := 0; var maxd := 0.0
			for i in mini(v1.size(), _v0.size()):
				var dd := v1[i].distance_to(_v0[i])
				if dd > 0.002: moved += 1
				maxd = maxf(maxd, dd)
			print("CRASHPROBE %s by-index (order preserved): %d vertices moved, max %.0f mm" % ["PASS" if moved >= 20 and maxd < 0.5 else "FAIL", moved, maxd * 1000.0])
			var dmg: Node = (main_ref.get("systems") as Dictionary).get("vehicle_damage")
			var dents := int(dmg.get("dent_count")) if dmg != null else -1
			var hp := float(v.get_meta("gunfire_hull", -1.0))
			print("CRASHPROBE %s dents counted: %d" % ["PASS" if dents >= 1 else "FAIL", dents])
			print("CRASHPROBE %s nose extent %.3f -> %.3f m (pushed back %.0f mm; verts %d -> %d)" % [
				"PASS" if nose0 - nose1 > 0.02 else "FAIL", nose0, nose1, (nose0 - nose1) * 1000.0, _v0.size(), v1.size()])
			print("CRASHPROBE %s hull points %.1f -> %.1f (max %.0f)" % ["PASS" if hp < float(v.get_meta("gunfire_hull_max", 1e9)) else "FAIL", _hp0, hp, float(v.get_meta("gunfire_hull_max", -1.0))])
			if DisplayServer.get_name() != "headless":
				var cam := Camera3D.new()
				cam.fov = 40.0
				main_ref.add_child(cam)
				var fwd := -v.global_transform.basis.z
				var right := v.global_transform.basis.x
				cam.global_position = v.global_position + fwd * 5.5 + right * 3.2 + Vector3(0, 1.4, 0)
				cam.look_at(v.global_position + fwd * 2.2 + Vector3(0, 0.6, 0), Vector3.UP)
				cam.make_current()
				_stage = 2; _t = 0.0
				return
			print("CRASHPROBE ---- done ----")
			get_tree().quit(0)
		2:
			if _t < 0.4: return
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var out := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/crash7/crash.png"
			img.save_png(out)
			print("CRASHPROBE captured " + out)
			print("CRASHPROBE ---- done ----")
			get_tree().quit(0)


## Mean forward extent of the NOSE PATCH (|x| < 0.7, front 0.6 m of the tub),
## order-independent. A top-N of the whole face failed: the tub's front face
## holds more than forty vertices on one plane, so a dented patch of them just
## drops out of the top forty and the mean never moves (crash probe, run 3).
func _extent(vs: PackedVector3Array, dir: Vector3) -> float:
	var lo := 1e9
	for p in vs: lo = minf(lo, p.z)
	var acc := 0.0; var n := 0
	for p in vs:
		if absf(p.x) < 0.7 and p.z < lo + 0.6:
			acc += p.dot(dir); n += 1
	return acc / maxf(float(n), 1.0)


func _max_disp(v1: PackedVector3Array) -> float:
	var m := 0.0
	for i in mini(v1.size(), _v0.size()):
		m = maxf(m, v1[i].distance_to(_v0[i]))
	return m
