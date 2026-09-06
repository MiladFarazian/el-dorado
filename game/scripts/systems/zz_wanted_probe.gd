extends Node
## WANTED-SYSTEM PROBE — permanent QA infrastructure. Runtime probe for the M23 wanted system (D-044/D-103). `godot -- --wanted-probe`
## (headless is fine: it reads state, it does not render). Stages:
##  1. heat 2 at the player's position; wait for cruisers to spawn and SEE the player.
##  2. break line of sight by teleporting the player 400 m east and every cruiser 400 m
##     west; assert search_active flips within LOS_LOST_SECONDS + 1 s, and that
##     search_center is near the last sighting (the pre-teleport position).
##  3. teleport the player next to a cruiser; assert search_active clears within 1 s.
##  4. print PASS/FAIL rows and quit. Smoke-guarded; inert without the flag.
var main_ref: Node = null
var _t := 0.0
var _stage := 0
var _p0 := Vector3.ZERO
var _rows: Array[String] = []


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")) or not OS.get_cmdline_user_args().has("--wanted-probe"):
		set_physics_process(false); set_process(false); return


func _police() -> Node:
	var sys: Variant = main_ref.get("systems")
	return (sys as Dictionary).get("police") if sys is Dictionary else null


func _pv() -> Node3D:
	var v: Variant = main_ref.get("vehicle")
	return v as Node3D if v is Node3D and is_instance_valid(v) else null


func _say(ok: bool, text: String) -> void:
	_rows.append("%s %s" % ["PASS" if ok else "FAIL", text])
	print("WANTEDPROBE %s %s" % ["PASS" if ok else "FAIL", text])


func _physics_process(delta: float) -> void:
	_t += delta
	var police := _police(); var pv := _pv()
	if police == null or pv == null:
		if _t > 5.0: _finish(); return
		return
	match _stage:
		0:
			if _t < 2.0: return
			police.call("add_heat", 2)
			_p0 = pv.global_position
			_stage = 1; _t = 0.0
		1:  # cruisers spawn and must see the player
			var cr: Array = police.get("cruisers")
			if _t > 6.0 or (cr.size() >= 2 and _t > 3.0):
				_say(cr.size() >= 1, "stage1 cruisers spawned: %d" % cr.size())
				_say(police.get("search_active") == false, "stage1 seen -> no search (search_active=%s)" % police.get("search_active"))
				# break LOS: player far east, cruisers far west
				pv.global_position = _p0 + Vector3(400, 0, 0)
				for c in cr:
					var b: Node3D = c["body"]
					if is_instance_valid(b): b.global_position = _p0 + Vector3(-400, 0, 0)
				_stage = 2; _t = 0.0
		2:  # search must open within LOS_LOST_SECONDS + 1
			if police.get("search_active") == true:
				var sc: Vector3 = police.get("search_center")
				var d := Vector2(sc.x - _p0.x, sc.z - _p0.z).length()
				_say(true, "stage2 search opened after %.1f s" % _t)
				_say(d < 30.0, "stage2 search_center %.1f m from last sighting (want < 30)" % d)
				_say(float(police.get("search_radius")) > 100.0, "stage2 search_radius %.0f m at heat %d" % [police.get("search_radius"), police.get("heat")])
				# re-contact: player beside a cruiser
				var cr2: Array = police.get("cruisers")
				if cr2.size() > 0:
					var b: Node3D = cr2[0]["body"]
					pv.global_position = b.global_position + Vector3(6, 0, 0)
				_stage = 3; _t = 0.0
			elif _t > 5.0:
				_say(false, "stage2 search never opened in %.1f s" % _t); _finish()
		3:  # spotted again -> search closes
			if police.get("search_active") == false:
				_say(true, "stage3 search closed after %.2f s of re-contact" % _t); _finish()
			elif _t > 2.0:
				_say(false, "stage3 search still active %.1f s after re-contact" % _t); _finish()


func _finish() -> void:
	print("WANTEDPROBE ---- %d rows ----" % _rows.size())
	get_tree().quit(0)
