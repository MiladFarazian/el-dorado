extends Node
## MECHANICS PROBE — permanent QA infrastructure for D-056 (`godot -- --mech-probe`,
## headless is fine). Reads state, never renders. Stages:
##  0. a parked truck stays parked (Milad, 2026-09-13: "all cars drift forward when
##     they shouldn't"): no input for 8 s on the flat spawn street, horizontal drift
##     must stay under 2 cm.
##  1. legible heat: add_heat(1, reason) publishes last_reason and the banner subline.
##  2. the Full Eight charges from speed (threshold lowered to what the spawn street
##     reaches), brake lamps flare on S and the horn plays on H while driving.
##  3. the Full Eight fires: time scale, audio scale, grip bonus, chain hold — then
##     ends on its own and restores all four.
##  4. busted, the cruiser path: heat 1, a still truck, a cruiser 40 m back — it
##     pulls alongside and parks (D-057) → the card → Book on the impound lot with
##     the wrecker, heat 0, fine paid, not healed.
##  5. a favor owed: heat 1 on foot on the lot, an officer at arm's length → the
##     card carries the favor line, no fine, the favor is spent.
##  6. random events: spawn_now places a dead sedan + driver + beacon; an
##     unanswered one despawns at its TTL.
##  7. the impound pad takes a towed box (Milad, 2026-09-13: "the drop-off area
##     was blocking the vehicle"): a junker-sized box dragged at the chain's
##     force along z has to end up ON the pad, not against its edge.
##  9. Hook and Ladder end to end (D-063): board the wrecker, roll into dispatch
##     (the app speaks), reach the Brisket, hook it (the drone and the owner
##     appear), deliver on the pad — the card, the payout with every bonus, GOLD.
## 10. Comin' Down (D-064): TAB into the Candyland Slab, roll up to the club's
##     board, one pass gate to gate (the probe shortens the night to one), the
##     Task Force lights a star, park on the lot, lose them: the card, +$250, respect.
##  8. melee (D-058): fists up, a brave man 1.3 m out — the jab lands and he
##     squares up; his punch takes 6 unguarded, 3 through a held guard, nothing
##     through a guard raised inside the perfect window (and he staggers); the
##     counter puts him down.
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
var _hour0 := -1.0
var _cruiser: RigidBody3D = null
var _min_d := 999.0
var _heat_at_bust := 1
var _box: RigidBody3D = null
var _brawler: RigidBody3D = null
var _p0 := Vector3.ZERO
var _only := -1                       # --mech-only=N: run stage N alone, then quit
var _hp0 := 0.0
var _press := ""                      # an action fed from idle time for one frame
const HOOK := preload("res://scripts/systems/mission_hook_and_ladder.gd")
const COMIN := preload("res://scripts/systems/mission_comin_down.gd")
var _hop_x := 0.0
var _respect0 := 0
var _cycles := 0
var _rel := Transform3D.IDENTITY
var _press_frames := 0


func setup(main: Node) -> void:
	main_ref = main
	var args := OS.get_cmdline_user_args()
	if bool(main.get("smoke_mode")) or not args.has("--mech-probe"):
		set_physics_process(false); set_process(false); return
	for a in args:
		if a.begins_with("--mech-only="):
			_only = int(a.substr(12))
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
	# Any action fed from idle time reads as a real key to the next physics tick.
	if _press != "":
		_press_frames += 1
		if _press_frames <= 2:
			Input.action_press(_press)
		else:
			Input.action_release(_press); _press = ""; _press_frames = 0
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
		0: _stage_drift(pv)
		1: _stage_heat()
		2: _stage_drive(pv)
		3: _stage_fire(pv)
		4: _stage_pullover(pv)
		5: _stage_favor()
		6: _stage_stranded()
		7: _stage_drag()
		8: _stage_melee()
		9: _stage_mission()
		10: _stage_comin()
		11: _stage_orders()
		12: _stage_dealer()
		13: _stage_alive()
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
			if _shots != "":  # the night plate D-120 owes: set 22:00 now, the sky needs seconds to turn
				var sky := _sys("sky_weather")
				if sky != null and sky.get("time_of_day") is float:
					_hour0 = float(sky.get("time_of_day"))
					sky.set("time_of_day", 22.0)
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
				if not _shot_done:  # once: the checks, and the plate if asked for
					_shot_done = true
					_say(e > 4.0, "stage2 brake lamps flare on S: energy %.2f (idle 1.5, brake 6.5)" % e)
					_say(honking, "stage2 horn plays while H is held")
					if _shots != "":
						_shot("brake_night")
				if _shots != "" and _t < 0.9:
					return  # one more beat with the pedal down for the plate
				Input.action_release("brake_reverse"); Input.action_release("horn")
				var sky := _sys("sky_weather")
				if _hour0 >= 0.0 and sky != null:
					sky.set("time_of_day", _hour0)
				_sub = 4; _t = 0.0
		4:
			if _t >= 1.0:
				_say(e < 2.5, "stage2 brake lamps settle on release: energy %.2f" % e)
				_say(not honking, "stage2 horn stops on release")
				fe.set("charge", 1.0)
				_shot_done = false
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


func _stage_pullover(pv: RigidBody3D) -> void:
	var pol := _sys("police"); var of := _sys("on_foot"); var repo := _sys("repo_board")
	if pol == null or of == null or repo == null:
		_say(false, "stage4 systems missing"); _finish(); return
	match _sub:
		0:
			pv.call("set_external_input", 0.0, 1.0, 0.0, true)  # stand on the brakes
			_sub = 1; _t = 0.0
		1:
			if pv.linear_velocity.length() < 1.0 or _t > 6.0:
				pol.call("add_heat", 1, "PROBE: LOITERING")
				_money0 = int(repo.get("money"))
				_sub = 2; _t = 0.0
		2:  # the first cruiser exists: put it 40 m back down the street, facing us
			var cr: Variant = pol.get("cruisers")
			if cr is Array and (cr as Array).size() >= 1:
				var b: Variant = ((cr as Array)[0] as Dictionary).get("body")
				if b is RigidBody3D and is_instance_valid(b):
					var back := pv.global_transform.basis.z  # +z is behind the truck
					var at := pv.global_position + back * 40.0 + Vector3.UP * 0.4
					(b as RigidBody3D).global_transform = Transform3D(Basis.looking_at(-back, Vector3.UP), at)
					(b as RigidBody3D).linear_velocity = Vector3.ZERO
					(b as RigidBody3D).angular_velocity = Vector3.ZERO
					_cruiser = b
					_sub = 3; _t = 0.0
			elif _t > 8.0:
				_say(false, "stage4 no cruiser spawned in %.1f s" % _t); _finish()
		3:
			pv.linear_velocity = Vector3.ZERO  # Book sits still, whatever the cruiser does
			var cd := _cruiser.global_position.distance_to(pv.global_position) if is_instance_valid(_cruiser) else -1.0
			_min_d = minf(_min_d, cd)
			if of.call("player_down") == true:
				var cs := _cruiser.linear_velocity.length() if is_instance_valid(_cruiser) else -1.0
				_say(true, "stage4 cruiser pulled alongside and busted a still Book after %.1f s (closest %.1f m, at the bust %.1f m, cruiser speed %.2f)" % [_t, _min_d, cd, cs])
				_heat_at_bust = int(pol.get("heat"))
				_say(_heat_at_bust == 1, "stage4 heat at the bust %d (want 1; last reason: %s)" % [_heat_at_bust, pol.get("last_reason")])
				var title: Variant = of.get("_card_title")
				_say(title is Label and (title as Label).text == "BUSTED.", "stage4 the card says BUSTED.")
				_sub = 4; _t = 0.0; _shot_done = false
			elif _t > 30.0:
				var arrest := _sys("arrest")
				_say(false, "stage4 cruiser never closed the arrest in 30 s (closest %.1f m, now %.1f m, hold=%s)" % [_min_d, cd, arrest.get("hold") if arrest != null else "n/a"])
				_finish()
		4:
			if not _shot_done and _t > 1.2:
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
				_say(m == _money0 - 150 * _heat_at_bust, "stage4 fine paid: $%d -> $%d (want -%d at %d star(s))" % [_money0, m, 150 * _heat_at_bust, _heat_at_bust])
				_stage = 5; _sub = 0; _t = 0.0
			elif _t > 7.0:
				_say(false, "stage4 card never cleared"); _finish()


func _stage_favor() -> void:
	var pol := _sys("police"); var of := _sys("on_foot"); var repo := _sys("repo_board"); var re := _sys("random_events")
	if pol == null or of == null or repo == null or re == null:
		_say(false, "stage5 systems missing"); _finish(); return
	var ch: Variant = main_ref.get("character")
	match _sub:
		0:
			if _t < 1.6:
				return  # the 1.4 s walk-out ends; Book stands on the lot
			re.set("favors", 1)
			_money0 = int(repo.get("money"))
			pol.call("add_heat", 1, "PROBE: LOITERING II")
			_officer = RigidBody3D.new()
			_officer.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
			_officer.freeze = true
			_officer.add_to_group("officer")
			var col := CollisionShape3D.new(); var box := BoxShape3D.new()
			box.size = Vector3(0.5, 1.75, 0.35); col.shape = box; _officer.add_child(col)
			main_ref.add_child(_officer)
			_sub = 1; _t = 0.0
		1:
			if ch is CharacterBody3D and is_instance_valid(ch) and is_instance_valid(_officer):
				_officer.global_position = (ch as Node3D).global_position + Vector3(1.8, 0.9, 0.0)
				(ch as CharacterBody3D).velocity = Vector3.ZERO
			if of.call("player_down") == true:
				var sub: Variant = of.get("_card_sub")
				var txt := (sub as Label).text if sub is Label else ""
				_say(int(re.get("favors")) == 0, "stage5 the favor was spent (favors=%s)" % re.get("favors"))
				_say(not txt.contains("Bail $") and txt.contains("LONGHORN IMPOUND."), "stage5 the card carries the favor line: %s" % txt)
				_sub = 2; _t = 0.0
			elif _t > 6.0:
				var arrest := _sys("arrest")
				_say(false, "stage5 never busted on foot with an officer at arm's length (hold=%s)" % (arrest.get("hold") if arrest != null else "n/a"))
				_finish()
		2:
			if of.call("player_down") != true:
				_say(int(repo.get("money")) == _money0, "stage5 no fine with a favor owed: $%d -> $%d" % [_money0, int(repo.get("money"))])
				_say(int(pol.get("heat")) == 0, "stage5 heat cleared")
				if is_instance_valid(_officer):
					_officer.queue_free()
				_stage = 6; _sub = 0; _t = 0.0
			elif _t > 7.0:
				_say(false, "stage5 card never cleared"); _finish()


func _stage_stranded() -> void:
	var re := _sys("random_events")
	if re == null:
		_say(false, "stage6 random_events missing"); _finish(); return
	match _sub:
		0:
			var ok: bool = re.call("spawn_now") == true
			_say(ok, "stage6 spawn_now placed a stranded driver: %s" % re.get("event_name"))
			_sub = 1; _t = 0.0
		1:
			if _t > 0.5:
				var cars := get_tree().get_nodes_in_group("stranded").size()
				var drivers := get_tree().get_nodes_in_group("stranded_driver").size()
				_say(cars == 1 and drivers == 1, "stage6 one dead sedan, one driver (%d/%d), active=%s" % [cars, drivers, re.get("active")])
				var beacons := 0
				for n in get_tree().get_nodes_in_group("objective_beacon"):
					if is_instance_valid(n): beacons += 1
				_say(beacons >= 1, "stage6 a beacon marks it (%d beacon(s) in the world)" % beacons)
				re.set("_ttl", 0.5)
				_sub = 2; _t = 0.0
		2:
			if _t > 2.0:
				var cars := 0
				for n in get_tree().get_nodes_in_group("stranded"):
					if is_instance_valid(n) and not n.is_queued_for_deletion(): cars += 1
				_say(cars == 0 and re.get("active") == false, "stage6 unanswered, they called somebody else: %d left, active=%s" % [cars, re.get("active")])
				_stage = 7; _sub = 0; _t = 0.0


func _stage_drag() -> void:
	var pad: Vector3 = REPO.PAD_CENTER
	match _sub:
		0:
			_box = RigidBody3D.new()
			_box.name = "ProbeDragBox"
			_box.mass = 1500.0
			var pm := PhysicsMaterial.new(); pm.friction = 0.2; _box.physics_material_override = pm
			var col := CollisionShape3D.new(); var bs := BoxShape3D.new()
			bs.size = Vector3(2.0, 1.1, 4.5); col.shape = bs; _box.add_child(col)
			main_ref.add_child(_box)
			_box.global_position = pad + Vector3(4.5, 0.56, -13.0)  # clear of the wrecker and of Book
			_sub = 1; _t = 0.0
		1:
			if not is_instance_valid(_box):
				_say(false, "stage7 drag box vanished"); _finish(); return
			_box.apply_central_force(Vector3(0.0, 0.0, 9000.0))  # a chain's pull, straight at the pad
			var p := _box.global_position
			var dz := p.z - pad.z
			if absf(dz) <= REPO.PAD_HALF.y - 1.0 and absf(p.x - pad.x) <= REPO.PAD_HALF.x:
				_say(true, "stage7 a towed box slides onto the impound pad (z %.1f m from centre after %.1f s, y %.2f)" % [dz, _t, p.y])
				_box.queue_free(); _stage = 8; _sub = 0; _t = 0.0
			elif _t > 6.0:
				_say(false, "stage7 a towed box never made the pad: z %.1f m from centre, y %.2f — the pad edge is a wall to a box on a chain (Milad's report)" % [dz, p.y])
				_box.queue_free(); _stage = 8; _sub = 0; _t = 0.0


func _stage_melee() -> void:
	var peds := _sys("pedestrians"); var melee := _sys("melee"); var combat := _sys("combat"); var pol := _sys("police")
	var ch: Variant = main_ref.get("character")
	if peds == null or melee == null or combat == null or not (ch is CharacterBody3D):
		_say(false, "stage8 systems or character missing"); _finish(); return
	var c := ch as CharacterBody3D
	if pol != null and int(pol.get("heat")) > 0:
		pol.call("add_heat", -10)   # a brawl draws heat; the law would end this test early
	match _sub:
		0:
			_shot_done = false
			var ok: bool = combat.call("select_weapon", "fists") == true
			var fwd := -c.global_transform.basis.z; fwd.y = 0.0; fwd = fwd.normalized()
			var b: Variant = peds.call("spawn_brawler_at", c.global_position + fwd * 1.3 + Vector3.UP * 0.875, -fwd)
			_brawler = b if b is RigidBody3D else null
			_say(ok and _brawler != null, "stage8 fists up, a brave man 1.3 m in front")
			_hp0 = float(c.get("health"))
			_press = "fire"
			_sub = 1; _t = 0.0
		1:
			if _t > 0.7:
				var hits := int(_brawler.get_meta("melee_hits", 0))
				var st := int(peds.call("state_of", _brawler))
				_say(hits == 1 and st == 3, "stage8 the jab landed (hits=%d) and he squared up (state=%d, BRAWL=3)" % [hits, st])
				_sub = 2; _t = 0.0
		2:
			var hp := float(c.get("health"))
			if hp < _hp0:
				_say(is_equal_approx(_hp0 - hp, 6.0), "stage8 his punch landed unguarded: -%.0f hp after %.1f s (want 6)" % [_hp0 - hp, _t])
				_hp0 = hp
				Input.action_press("aim")   # guard up, and held past the perfect window
				_sub = 3; _t = 0.0
			elif _t > 3.5:
				_say(false, "stage8 he never threw a punch in 3.5 s (state=%s punch_in=%s)" % [peds.call("state_of", _brawler), peds.call("punch_in", _brawler)]); _finish()
		3:
			var hp := float(c.get("health"))
			if hp < _hp0:
				_say(is_equal_approx(_hp0 - hp, 3.0), "stage8 guard held: -%.0f hp (want 3, half)" % (_hp0 - hp))
				_hp0 = hp
				Input.action_release("aim")
				_sub = 4; _t = 0.0
			elif _t > 3.5:
				_say(false, "stage8 no punch against the guard in 3.5 s"); _finish()
		4:
			var pin := float(peds.call("punch_in", _brawler))
			if _shots != "" and not _shot_done and pin > 0.0 and pin <= 0.30:
				_shot_done = true
				_shot("brawl")   # the plate: he is leaning into the punch
			if pin > 0.0 and pin <= 0.18:
				Input.action_press("aim")   # inside the perfect window
				_sub = 5; _t = 0.0
			elif _t > 3.5:
				_say(false, "stage8 no windup to counter in 3.5 s"); _finish()
		5:
			if _t > 0.45:
				var hp := float(c.get("health"))
				var stunned: bool = peds.call("is_stunned", _brawler) == true
				_say(is_equal_approx(hp, _hp0) and melee.get("last_block_perfect") == true, "stage8 perfect block: %.0f hp lost, perfect=%s" % [_hp0 - hp, melee.get("last_block_perfect")])
				_say(stunned, "stage8 he is staggered (stunned=%s)" % stunned)
				Input.action_release("aim")
				_press = "fire"   # the counter: an automatic heavy
				_sub = 6; _t = 0.0
		6:
			if _t > 0.8:
				var st := int(peds.call("state_of", _brawler))
				_say(st == 2, "stage8 the counter put him down (state=%d, DOWN=2)" % st)
				_stage = 9; _sub = 0; _t = 0.0


func _stage_drift(pv: RigidBody3D) -> void:
	match _sub:
		0:
			if _t >= 2.0:   # let the springs settle
				_p0 = pv.global_position
				_sub = 1; _t = 0.0
		1:
			if _t >= 8.0:
				var d := pv.global_position - _p0
				var horiz := Vector2(d.x, d.z).length()
				var fwd := -pv.global_transform.basis.z
				var along := Vector3(d.x, 0.0, d.z).dot(Vector3(fwd.x, 0.0, fwd.z).normalized())
				_say(horiz < 0.02, "stage0 parked wrecker drift over 8 s: %.3f m (%.3f m along its nose, speed now %.3f m/s; want < 0.02)" % [horiz, along, pv.linear_velocity.length()])
				if _only == 0:
					_finish(); return
				_stage = 1; _sub = 0; _t = 0.0


func _stage_mission() -> void:
	var m := _sys("mission_hook_and_ladder"); var kit := _sys("mission_kit"); var repo := _sys("repo_board")
	var pv := _pv()
	if m == null or kit == null or repo == null or pv == null:
		_say(false, "stage9 mission systems missing"); _finish(); return
	match _sub:
		0:   # Book boards the wrecker
			_shot_done = false
			var ch: Variant = main_ref.get("character")
			if ch is Node3D and is_instance_valid(ch):
				(ch as Node3D).global_position = pv.global_position - pv.global_transform.basis.x * 2.3 + Vector3(0, -0.9, 0)
			_press = "enter_exit"
			_sub = 1; _t = 0.0
		1:
			if main_ref.get("on_foot") != true:
				pv.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), HOOK.DISPATCH_POS + Vector3.UP * 1.2)
				pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
				_money0 = int(repo.get("money"))
				_sub = 2; _t = 0.0
			elif _t > 3.0:
				_say(false, "stage9 Book never boarded the wrecker (on_foot=%s)" % main_ref.get("on_foot")); _finish()
		2:
			pv.linear_velocity = Vector3.ZERO
			if int(m.get("state")) == 1:
				_say(true, "stage9 rolled into dispatch: ORDER accepted (state=1) after %.1f s" % _t)
				_say(int(kit.call("lines_queued")) >= 1, "stage9 the app spoke (%d lines queued)" % int(kit.call("lines_queued")))
				pv.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), HOOK.TARGET_POS + Vector3(0, 1.2, -8.0))
				pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
				_sub = 3; _t = 0.0
			elif _t > 4.0:
				_say(false, "stage9 dispatch never triggered (state=%s)" % m.get("state")); _finish()
		3:
			pv.linear_velocity = Vector3.ZERO
			if int(m.get("state")) == 2 and _t > 0.3:
				_press = "hook"
				_sub = 4; _t = 0.0
			elif _t > 4.0:
				_say(false, "stage9 never promoted to HOOK_IT (state=%s)" % m.get("state")); _finish()
		4:
			if int(m.get("state")) == 3 and _t > 0.8:
				var tgt: Variant = m.get("_target")
				var owner := get_tree().get_nodes_in_group("mission_owner").size()
				var drone: Variant = m.get("_drone")
				_say(true, "stage9 hooked: DELIVER (state=3)")
				_say(drone is Node and is_instance_valid(drone), "stage9 the Porchlight drone is up")
				_say(owner == 1, "stage9 the owner came out of the house (%d follower)" % owner)
				if tgt is Node3D:
					_rel = pv.global_transform.affine_inverse() * (tgt as Node3D).global_transform
					var tx := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), REPO.PAD_CENTER + Vector3(0, 1.2, -6.0))
					pv.global_transform = tx
					(tgt as RigidBody3D).global_transform = tx * _rel
					pv.linear_velocity = Vector3.ZERO; (tgt as RigidBody3D).linear_velocity = Vector3.ZERO
				_sub = 5; _t = 0.0
			elif _t > 4.0:
				_say(false, "stage9 the hook never took (state=%s)" % m.get("state")); _finish()
		5:
			pv.linear_velocity = Vector3.ZERO
			if _t > 0.5 and _press == "":
				_press = "hook"   # release on the pad
				_sub = 6; _t = 0.0
		6:
			if int(m.get("state")) == 4:
				var delta := int(repo.get("money")) - _money0
				_say(true, "stage9 delivered: CONTRACT COMPLETE (state=4) after %.1f s" % _t)
				_say(delta == 950, "stage9 payout with every bonus: $%d (want 950 = 600 + no clips 150 + window 100 + no heat 100)" % delta)
				_say(kit.call("card_visible") == true, "stage9 the contract card is up")
				_sub = 7; _t = 0.0
			elif _t > 5.0:
				_say(false, "stage9 release on the pad did not complete (state=%s)" % m.get("state")); _finish()
		7:   # the card has faded in (0.7 s) and the app's closing line is up
			if _t > 1.2:
				if _shots != "" and not _shot_done:
					_shot_done = true; _shot("mission_card")
				if _t > 1.6:
					_stage = 10; _sub = 0; _t = 0.0


func _stage_comin() -> void:
	var m := _sys("mission_comin_down"); var kit := _sys("mission_kit"); var repo := _sys("repo_board"); var pol := _sys("police")
	var pv := _pv()
	if m == null or kit == null or repo == null or pol == null or pv == null:
		_say(false, "stage10 mission systems missing"); _finish(); return
	match _sub:
		0:   # TAB into the slab
			if str(pv.get("display_name")) == "Candyland Slab":
				_say(true, "stage10 in the Candyland Slab after %d cycles" % _cycles)
				pv.global_transform = Transform3D(Basis.IDENTITY, COMIN.BOARD_POS + Vector3(0, 1.0, -5.0))
				pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
				_money0 = int(repo.get("money")); _respect0 = int(repo.get("respect"))
				m.set("passes_needed", 1)
				_sub = 1; _t = 0.0
			elif _cycles >= 6:
				_say(false, "stage10 could not cycle into the slab (%s)" % pv.get("display_name")); _finish()
			elif _t > 0.4 and main_ref.has_method("_cycle_vehicle"):
				main_ref.call("_cycle_vehicle"); _cycles += 1; _t = 0.0
		1:
			pv.linear_velocity = Vector3.ZERO
			if int(m.get("state")) == 1 and _t > 0.3:
				_say(true, "stage10 rolled up to the board in the slab: CRUISE (state=1)")
				_say(int(kit.call("lines_queued")) >= 1, "stage10 Candyland spoke (%d lines queued)" % int(kit.call("lines_queued")))
				_hop_x = 320.0
				_sub = 2; _t = 0.0
			elif _t > 4.0:
				_say(false, "stage10 the board never took (state=%s, name=%s)" % [m.get("state"), pv.get("display_name")]); _finish()
		2:   # gate to gate in hops (the mission counts the crossing, not the speed)
			if int(m.get("state")) == 2:
				_say(true, "stage10 pass complete at x=%.0f: TAKEOVER (state=2), heat %s" % [_hop_x, pol.get("heat")])
				_say(int(pol.get("heat")) >= 1, "stage10 the Task Force lit a star")
				pv.global_transform = Transform3D(Basis.IDENTITY, COMIN.TAKEOVER_POS + Vector3(0, 1.0, 0))
				pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
				_sub = 3; _t = 0.0
			elif _t > 0.25:
				_t = 0.0; _hop_x += 45.0
				pv.global_transform = Transform3D(Basis.looking_at(Vector3(1, 0, 0), Vector3.UP), Vector3(_hop_x, 1.0, 477.0))
				pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
				if _hop_x > 820.0:
					_say(false, "stage10 crossed the east gate and no pass counted (state=%s)" % m.get("state")); _finish()
		3:
			pv.linear_velocity = Vector3.ZERO
			if int(m.get("state")) == 3:
				_say(true, "stage10 parked on the lot: SLIDE OUT (state=3)")
				pol.call("add_heat", -10)   # the probe loses them for you
				_sub = 4; _t = 0.0
			elif _t > 4.0:
				_say(false, "stage10 the takeover never took (state=%s)" % m.get("state")); _finish()
		4:
			if int(m.get("state")) == 4:
				var dm := int(repo.get("money")) - _money0; var dr := int(repo.get("respect")) - _respect0
				_say(dm == 250 and dr >= 4, "stage10 COMPLETE: +$%d, respect +%d (want 250, >= 4)" % [dm, dr])
				_say(kit.call("card_visible") == true, "stage10 the Candyland card is up")
				_stage = 11; _sub = 0; _t = 0.0; _cycles = 0
			elif _t > 4.0:
				_say(false, "stage10 slide-out never completed (state=%s heat=%s)" % [m.get("state"), pol.get("heat")]); _finish()


## Stage 11 (D-068): THE HOOK, ENDLESS. The app pushes an order; the target is
## towable and on the radar; the debtor comes out; hook, haul to the pad, get
## paid and ranked. Then a bad-paper order: go to the debtor and walk away —
## respect, and the paper burned.
func _stage_orders() -> void:
	var o := _sys("repo_orders"); var repo := _sys("repo_board"); var pol := _sys("police"); var kit := _sys("mission_kit")
	var pv := _pv()
	if o == null or repo == null or pol == null or pv == null:
		_say(false, "stage11 repo_orders / peers missing"); _finish(); return
	match _sub:
		0:   # back into the wrecker (the dev fleet cycles every profile)
			if int(o.get("state")) == 1 and _t > 0.2:
				# The loop is live on its own: twelve quiet seconds of the early
				# stages was enough for the app to push. Clear it, then force ours.
				o.call("walk_away"); _t = 0.0
			elif pv.has_method("has_boom") and bool(pv.call("has_boom")) and int(o.get("state")) == 0 and _t > 0.3:
				pol.call("add_heat", -10)
				_money0 = int(repo.get("money")); _respect0 = int(repo.get("respect"))
				var ok := bool(o.call("push_now", false))
				_say(ok, "stage11 the app pushed an order (push_now)")
				if not ok:
					_finish(); return
				_sub = 1; _t = 0.0
			elif _cycles >= 6:
				_say(false, "stage11 could not cycle into the wrecker (%s)" % pv.get("display_name")); _finish()
			elif _t > 0.4 and main_ref.has_method("_cycle_vehicle"):
				main_ref.call("_cycle_vehicle"); _cycles += 1; _t = 0.0
		1:   # the target exists; drive up behind it
			var tgt: Variant = o.call("target")
			if tgt is Node3D and is_instance_valid(tgt):
				_say(int(o.get("state")) == 1, "stage11 PUSHED (state=%s): '%s'" % [o.get("state"), o.call("objective_text")])
				_shot("order_push")   # the push line, the beacon, the objective
				var ph := _sys("phone")   # D-069: the paper you can read
				if ph != null and ph.has_method("toggle") and ph.has_method("text_of"):
					ph.call("toggle")
					var t0 := str(ph.call("text_of", 0))
					_say(ph.get("open") == true and t0.contains("ORDER"), "stage11 the phone opens on the order (%d chars)" % t0.length())
					ph.call("toggle"); ph.call("toggle"); ph.call("toggle")   # BOONE, WALLET, closed
					_say(ph.get("open") == false, "stage11 the phone closes after three tabs")
				_say((tgt as Node).is_in_group("towable") and (tgt as Node).is_in_group("mission_target"),
					"stage11 the target is towable and rings on the radar")
				var tp := (tgt as Node3D).global_position
				pv.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), tp + Vector3(0, 1.2, -8.0))
				pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
				_sub = 2; _t = 0.0
			elif _t > 3.0:
				_say(false, "stage11 no target after the push (state=%s)" % o.get("state")); _finish()
		2:   # the debtor comes out at 25 m; then the hook
			if _t > 1.5 and _press == "":
				var db: Variant = o.call("debtor")
				_say(db is Node3D and is_instance_valid(db), "stage11 the debtor came out to meet him")
				_shot("order_debtor")
				_press = "hook"; _sub = 3; _t = 0.0
		3:
			if int(o.get("state")) == 2:
				_say(true, "stage11 hooked: HOOKED (state=2): '%s'" % o.call("objective_text"))
				var tgt: Variant = o.call("target")
				if tgt is RigidBody3D:
					_rel = pv.global_transform.affine_inverse() * (tgt as Node3D).global_transform
					var tx := Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), REPO.PAD_CENTER + Vector3(0, 1.2, -6.0))
					pv.global_transform = tx; (tgt as RigidBody3D).global_transform = tx * _rel
					pv.linear_velocity = Vector3.ZERO; (tgt as RigidBody3D).linear_velocity = Vector3.ZERO
				_sub = 4; _t = 0.0
			elif _t > 3.0 and _press == "":
				_press = "hook"; _t = 0.0   # one retry
			elif _t > 9.0:
				_say(false, "stage11 the hook never took (state=%s)" % o.get("state")); _finish()
		4:   # release on the pad
			if int(o.get("state")) == 0:
				var dm := int(repo.get("money")) - _money0
				_say(dm >= 300, "stage11 DELIVERED: +$%d (want >= 300), deliveries %s, rank %s" % [dm, o.get("deliveries"), o.get("rank")])
				_say(kit == null or kit.call("card_visible") == true, "stage11 the RECOVERED card is up")
				_sub = 5; _t = 0.0
			elif _t > 0.5 and _press == "" and int(o.get("state")) == 2:
				_press = "hook"; _t = -2.0
			elif _t > 9.0:
				_say(false, "stage11 the release on the pad did not deliver (state=%s)" % o.get("state")); _finish()
		5:   # bad paper: push, meet the debtor, walk away
			if _t > 1.0:
				pol.call("add_heat", -10)
				_respect0 = int(repo.get("respect"))
				var ok2 := bool(o.call("push_now", true))
				_say(ok2, "stage11 the app pushed a bad-paper order")
				if not ok2:
					_finish(); return
				_sub = 6; _t = 0.0
		6:
			var tgt2: Variant = o.call("target")
			if tgt2 is Node3D and is_instance_valid(tgt2):
				var tp2 := (tgt2 as Node3D).global_position
				pv.global_transform = Transform3D(Basis.looking_at(Vector3.FORWARD, Vector3.UP), tp2 + Vector3(0, 1.2, -8.0))
				pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
				_sub = 7; _t = 0.0
			elif _t > 3.0:
				_say(false, "stage11 no bad-paper target"); _finish()
		7:   # the debtor comes out; leave the paper from where the wrecker stands
			# (a teleport onto the debtor knocked them down and cost 2 respect: the
			# probe's doing, not the system's)
			var db2: Variant = o.call("debtor")
			if db2 is Node3D and is_instance_valid(db2) and _t > 1.0:
				_sub = 8; _t = 0.0
			elif _t > 5.0:
				_say(false, "stage11 the bad-paper debtor never came out"); _finish()
		8:
			if _t > 0.6:
				var walked := bool(o.call("walk_away"))
				_say(walked, "stage11 walked away from the bad paper (walk_away)")
				_sub = 9; _t = 0.0
		9:
			if _t > 0.5:
				var dr := int(repo.get("respect")) - _respect0
				_say(int(o.get("state")) == 0 and dr >= 3, "stage11 VOIDED: respect +%d (want >= 3), paper burned %s" % [dr, o.get("paper_burned")])
				_stage = 12; _sub = 0; _t = 0.0


## Stage 12 (D-068): BOONE TRUCKS. Sign a 96-month note on the Brisket ($0
## down), take the first draft, go broke, miss two — LONGHORN recovers it and
## leaves the wrecker; then buy the sedan for cash.
func _stage_dealer() -> void:
	var d := _sys("dealer"); var repo := _sys("repo_board"); var pv := _pv()
	if d == null or repo == null or pv == null:
		_say(false, "stage12 dealer / peers missing"); _finish(); return
	const BRISKET := "res://data/vehicles/brisket.json"
	const SEDAN := "res://data/vehicles/sedan.json"
	match _sub:
		0:
			var inv: Variant = d.call("inventory")
			var n := (inv as Array).size() if inv is Array else 0
			_say(n >= 3, "stage12 Boone Trucks stocks %d rigs" % n)
			_money0 = int(repo.get("money"))
			var owned0 := (main_ref.get("owned_paths") as Array).size()
			var ok := bool(d.call("sign_note", BRISKET))
			_say(ok, "stage12 signed a 96-month note on the Brisket, $0 down")
			var owned1 := (main_ref.get("owned_paths") as Array).size()
			_say(owned1 == owned0 + 1, "stage12 the Brisket is his now (%d -> %d rigs)" % [owned0, owned1])
			_say(int(repo.get("money")) == _money0, "stage12 nothing drafted at signing")
			_sub = 1; _t = 0.0; _cycles = 0
		1:   # step out of the Brisket (back to the wrecker) so a recovery can take it
			var cur := _pv()
			if cur != null and cur.has_method("has_boom") and bool(cur.call("has_boom")):
				_sub = 2; _t = 0.0
			elif _cycles >= 6:
				_say(false, "stage12 could not cycle back to the wrecker"); _finish()
			elif _t > 0.4:
				main_ref.call("_cycle_vehicle"); _cycles += 1; _t = 0.0
		2:
			if _t > 0.5:
				d.call("note_tick_now")
				var dm := _money0 - int(repo.get("money"))
				_say(dm > 0, "stage12 the first draft came out: -$%d" % dm)
				repo.call("add_money", -int(repo.get("money")), "PROBE: BROKE")
				d.call("note_tick_now"); d.call("note_tick_now")
				_sub = 3; _t = 0.0
		3:
			if _t > 0.6:
				var owned2: Array = main_ref.get("owned_paths")
				_say(not owned2.has(BRISKET), "stage12 two missed drafts: LONGHORN recovered the Brisket (%d rigs)" % owned2.size())
				_say(owned2.size() >= 1 and str(owned2[0]).contains("wrecker"), "stage12 the wrecker is still his")
				repo.call("add_money", 20000, "PROBE: FUNDED")
				var ok2 := bool(d.call("buy_cash", SEDAN))
				_say(ok2 and int(repo.get("money")) == 20000 - 14900, "stage12 bought the sedan for cash ($%s left, want 5100)" % repo.get("money"))
				_stage = 13; _sub = 0; _t = 0.0


## Stage 13 (D-069): ALIVE. Park on Juárez Boulevard in the Cliff and wait:
## the spur lanes carry traffic (five routes qualified from the atlas) and the
## boulevard's sidewalks fill from the zone file. A live order may push
## meanwhile — that is the loop working, not a fault.
func _stage_alive() -> void:
	var tr := _sys("traffic"); var peds := _sys("pedestrians"); var pv := _pv()
	if tr == null or peds == null or pv == null:
		_say(false, "stage13 traffic / pedestrians missing"); _finish(); return
	match _sub:
		0:
			pv.global_transform = Transform3D(Basis.looking_at(Vector3(-1, 0, 0), Vector3.UP), Vector3(-200.0, 1.2, 796.0))
			pv.linear_velocity = Vector3.ZERO; pv.angular_velocity = Vector3.ZERO
			var c: Variant = tr.call("spur_census") if tr.has_method("spur_census") else null
			var routes := int((c as Dictionary).get("routes", 0)) if c is Dictionary else -1
			_say(routes == 5, "stage13 five spur routes qualified from the atlas (%d)" % routes)
			_sub = 1; _t = 0.0
		1:
			pv.linear_velocity = Vector3.ZERO
			if _t > 40.0:
				var c: Variant = tr.call("spur_census")
				var cars := int((c as Dictionary).get("cars", 0)) if c is Dictionary else 0
				_say(cars >= 1, "stage13 spur traffic on the boulevard after 40 s: %d shells" % cars)
				var zc := int(peds.call("zone_count", "cliff_boulevard")) if peds.has_method("zone_count") else -1
				_say(zc >= 2, "stage13 the boulevard's sidewalks have people: %d (want >= 2)" % zc)
				_finish()
