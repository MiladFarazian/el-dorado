extends Node
## MECHANICS PROBE — permanent QA infrastructure for D-056 (`godot -- --mech-probe`,
## headless is fine). Reads state, never renders. Stages:
##  1. legible heat: add_heat(1, reason) publishes last_reason and the banner subline.
##  2. the Full Eight charges from speed (threshold lowered to what the spawn street
##     reaches), brake lamps flare on S and the horn plays on H while driving.
##  3. the Full Eight fires: time scale, audio scale, grip bonus, chain hold — then
##     ends on its own and restores all four.
##  4. busted: heat 1, a still truck, an officer at arm's length → the card, then
##     Book on the impound lot with the wrecker, heat 0, fine paid, not healed.
## Windowed with `--mech-shots=/abs/dir` it also saves three evidence plates.
const REPO := preload("res://scripts/systems/repo_board.gd")
var main_ref: Node = null
var _t := 0.0
var _stage := 0
var _sub := 0
var _rows: Array[String] = []
var _shots := ""
var _money0 := 0
var _officer: RigidBody3D = null
var _key_tried := 0
var _shot_done := false


func setup(main: Node) -> void:
	main_ref = main
	var args := OS.get_cmdline_user_args()
	if bool(main.get("smoke_mode")) or not args.has("--mech-probe"):
		set_physics_process(false); set_process(false); return
	for a in args:
		if a.begins_with("--mech-shots="):
			_shots = a.substr(13)
			DirAccess.make_dir_recursive_absolute(_shots)
			if DisplayServer.get_name() != "headless":
				DisplayServer.window_set_size(Vector2i(1600, 900))  # D-053: plates at the canvas size


func _sys(nm: String) -> Node:
	var sys: Variant = main_ref.get("systems")
	return (sys as Dictionary).get(nm) if sys is Dictionary else null


func _pv() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle")
	return v as RigidBody3D if v is RigidBody3D and is_instance_valid(v) else null


func _say(ok: bool, text: String) -> void:
	_rows.append("%s %s" % ["PASS" if ok else "FAIL", text])
	print("MECHPROBE %s %s" % ["PASS" if ok else "FAIL", text])


func _shot(nm: String) -> void:
	if _shots == "" or DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(_shots + "/" + nm + ".png")
	print("MECHPROBE shot %s" % nm)


func _finish() -> void:
	var fails := 0
	for r in _rows:
		if r.begins_with("FAIL"): fails += 1
	print("MECH PROBE: %s (%d/%d)" % ["PASS" if fails == 0 else "FAIL", _rows.size() - fails, _rows.size()])
	set_physics_process(false)
	get_tree().quit(0 if fails == 0 else 1)


func _process(_d: float) -> void:
	# Key path for the special: a press fed from idle time is what a real key looks
	# like to the next physics tick. Tried thrice; the probe falls back to _fire().
	if _stage == 3 and _sub == 0 and _key_tried < 3:
		_key_tried += 1
		Input.action_press("special")
		if _key_tried == 3:
			Input.action_release("special")
	elif _stage == 3 and _sub == 0 and _key_tried == 3:
		Input.action_release("special")


func _physics_process(delta: float) -> void:
	_t += delta
	var pv := _pv()
	if pv == null:
		if _t > 8.0:
			_say(false, "no player vehicle after 8 s"); _finish()
		return
	match _stage:
		0:
			if _t >= 2.0:
				_stage = 1; _t = 0.0
		1: _stage_heat()
		2: _stage_drive(pv)
		3: _stage_fire(pv)
		4: _stage_busted(pv)
		_: _finish()


func _stage_heat() -> void:
	var pol := _sys("police")
	if pol == null:
		_say(false, "stage1 police missing"); _finish(); return
	pol.call("add_heat", 1, "PROBE CRIME")
	_say(pol.get("last_reason") == "PROBE CRIME", "stage1 last_reason published: %s" % pol.get("last_reason"))
	var sub: Variant = pol.get("_banner_sub")
	var vis: bool = sub is Label and (sub as Label).visible and (sub as Label).text == "PROBE CRIME"
	_say(vis, "stage1 banner subline shows the reason")
	pol.call("add_heat", -10)
	_say(pol.get("last_reason") == "", "stage1 evaded clears the reason")
	_stage = 2; _sub = 0; _t = 0.0


func _stage_drive(pv: RigidBody3D) -> void:
	var fe := _sys("full_eight"); var lamps := _sys("vehicle_lamps"); var audio := _sys("vehicle_audio")
	if fe == null or lamps == null or audio == null:
		_say(false, "stage2 systems missing"); _finish(); return
	var speed := pv.linear_velocity.length()
	var tm: Variant = lamps.get("_tail")
	var e := (tm as StandardMaterial3D).emission_energy_multiplier if tm is StandardMaterial3D else -1.0
	var horn: Variant = audio.get("_horn")
	var honking: bool = horn is AudioStreamPlayer3D and (horn as AudioStreamPlayer3D).playing
	match _sub:
		0:
			var cfg: Variant = fe.get("cfg")
			if cfg is Dictionary:
				(cfg as Dictionary)["charge_speed_threshold_mps"] = 8.0  # the mechanism, not the tuning
			pv.call("set_external_input", 1.0, 0.0, 0.0, false)
			_sub = 1; _t = 0.0
		1:
			if speed >= 8.0:
				_sub = 2; _t = 0.0
			elif _t > 12.0:
				_say(false, "stage2 never reached 8 m/s (%.1f)" % speed); _finish()
		2:
			if _t >= 3.0:
				var c := float(fe.get("charge"))
				_say(c > 0.05, "stage2 rope charged from speed: %.3f after 3 s at %.1f m/s" % [c, speed])
				var spots: Variant = lamps.get("_spots")
				var ns := (spots as Array).size() if spots is Array else -1
				_say(ns >= 1, "stage2 headlamp spots bound to the ride: %d" % ns)
				_say(tm is StandardMaterial3D, "stage2 tail lamp material is private to the player's ride")
				Input.action_press("brake_reverse"); Input.action_press("horn")
				_sub = 3; _t = 0.0
		3:
			if _t >= 0.6:
				_say(e > 4.0, "stage2 brake lamps flare on S: energy %.2f (idle 1.5, brake 6.5)" % e)
				_say(honking, "stage2 horn plays while H is held")
				Input.action_release("brake_reverse"); Input.action_release("horn")
				_sub = 4; _t = 0.0
		4:
			if _t >= 1.0:
				_say(e < 2.5, "stage2 brake lamps settle on release: energy %.2f" % e)
				_say(not honking, "stage2 horn stops on release")
				fe.set("charge", 1.0)
				_stage = 3; _sub = 0; _t = 0.0


func _stage_fire(pv: RigidBody3D) -> void:
	var fe := _sys("full_eight")
	var active: bool = fe.get("active") == true
	match _sub:
		0:
			if active:
				_say(true, "stage3 fired from the key path (special)")
				_sub = 1; _t = 0.0
			elif _t > 0.6:
				fe.call("_fire")
				_say(fe.get("active") == true, "stage3 fired via _fire() (key path not observable from a probe)")
				_sub = 1; _t = 0.0
		1:
			_say(is_equal_approx(Engine.time_scale, 0.35), "stage3 time scale %.2f (want 0.35)" % Engine.time_scale)
			_say(is_equal_approx(AudioServer.playback_speed_scale, 0.55), "stage3 audio scale %.2f (want 0.55)" % AudioServer.playback_speed_scale)
			_say(is_equal_approx(float(pv.get("grip_bonus")), 1.30), "stage3 grip bonus %.2f (want 1.30)" % float(pv.get("grip_bonus")))
			_say(fe.get("chain_held") == true, "stage3 chain held")
			_sub = 2; _t = 0.0
		2:
			if active and not _shot_done and _t > 0.35:  # ~1 real-s in: the veil has faded in
				_shot_done = true
				_shot("full_eight")
			if not active:
				_say(true, "stage3 ended on its own after %.1f game-s (%.1f real-s)" % [_t, _t / 0.35])
				_say(is_equal_approx(Engine.time_scale, 1.0), "stage3 time restored %.2f" % Engine.time_scale)
				_say(is_equal_approx(AudioServer.playback_speed_scale, 1.0), "stage3 audio restored %.2f" % AudioServer.playback_speed_scale)
				_say(is_equal_approx(float(pv.get("grip_bonus")), 1.0), "stage3 grip restored %.2f" % float(pv.get("grip_bonus")))
				_say(fe.get("chain_held") == false, "stage3 chain released")
				_say(float(fe.get("_cooldown")) > 0.0, "stage3 cooldown armed %.1f s" % float(fe.get("_cooldown")))
				_stage = 4; _sub = 0; _t = 0.0
			elif _t > 6.0:
				_say(false, "stage3 still active after %.1f game-s" % _t); _finish()


func _stage_busted(pv: RigidBody3D) -> void:
	var pol := _sys("police"); var of := _sys("on_foot"); var repo := _sys("repo_board")
	if pol == null or of == null or repo == null:
		_say(false, "stage4 systems missing"); _finish(); return
	match _sub:
		0:
			pv.call("set_external_input", 0.0, 1.0, 0.0, true)  # stand on the brakes
			_sub = 1; _t = 0.0
		1:
			if pv.linear_velocity.length() < 1.0 or _t > 6.0:
				print("MECHPROBE note: stage4 truck speed at officer placement %.2f m/s after %.1f s" % [pv.linear_velocity.length(), _t])
				pol.call("add_heat", 1, "PROBE: LOITERING")
				_money0 = int(repo.get("money"))
				_officer = RigidBody3D.new()
				_officer.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
				_officer.freeze = true
				_officer.add_to_group("officer")
				var col := CollisionShape3D.new(); var box := BoxShape3D.new()
				box.size = Vector3(0.5, 1.75, 0.35); col.shape = box; _officer.add_child(col)
				main_ref.add_child(_officer)
				_officer.global_position = pv.global_position + pv.global_transform.basis.x * 1.8 + Vector3.UP * 0.9
				_sub = 2; _t = 0.0
		2:
			# The law keeps pace: a cruiser rams the parked truck (heat 1 is chase-and-
			# ram) and shoves it metres; the officer walks with it and Book stays put.
			if is_instance_valid(_officer):
				_officer.global_position = pv.global_position + pv.global_transform.basis.x * 1.8 + Vector3.UP * 0.9
			pv.linear_velocity = Vector3.ZERO
			if of.call("player_down") == true:
				var title: Variant = of.get("_card_title")
				_say(true, "stage4 busted after %.1f s still with an officer at arm's length" % _t)
				_say(title is Label and (title as Label).text == "BUSTED.", "stage4 the card says BUSTED.")
				_sub = 3; _t = 0.0
				_shot_done = false
			elif _t > 5.0:
				var arrest := _sys("arrest")
				var od := _officer.global_position.distance_to(pv.global_position) if is_instance_valid(_officer) else -1.0
				_say(false, "stage4 never busted in %.1f s (hold=%s heat=%s speed=%.2f officer_d=%.2f frozen=%s on_foot=%s)" % [
					_t, arrest.get("hold") if arrest != null else "n/a", pol.get("heat"),
					pv.linear_velocity.length(), od, _officer.freeze if is_instance_valid(_officer) else "?", main_ref.get("on_foot")])
				_finish()
		3:
			if not _shot_done and _t > 1.2:  # the card has faded in (0.45 s) and held
				_shot_done = true
				_shot("busted")
			if of.call("player_down") != true:
				var pad: Vector3 = REPO.PAD_CENTER
				var veh := _pv()
				var d := veh.global_position.distance_to(pad) if veh != null else 999.0
				_say(d < 10.0, "stage4 wrecker on the impound lot: %.1f m from the pad" % d)
				_say(main_ref.get("on_foot") == true, "stage4 Book on foot on the lot")
				_say(int(pol.get("heat")) == 0, "stage4 heat cleared")
				var m := int(repo.get("money"))
				_say(m == _money0 - 150, "stage4 fine paid: $%d -> $%d (want -150 at one star)" % [_money0, m])
				if is_instance_valid(_officer):
					_officer.queue_free()
				_finish()
			elif _t > 7.0:
				_say(false, "stage4 card never cleared"); _finish()
