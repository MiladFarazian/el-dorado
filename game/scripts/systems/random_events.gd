extends Node
## RANDOM EVENTS — ambient encounters that pay forward (D-057; DNA §4: "a rescued
## stranger later joins your heist crew — the world remembering kindness is the
## single best trick in the game"). v1 has one event, STRANDED: a driver beside a
## dead sedan at a downtown curb. Hook it, haul it to Longhorn Impound, get paid
## under repo rates, and they OWE YOU ONE — the favor covers the bail the next
## time you are busted (arrest.gd asks; save_load persists the count). Spawns
## only when the world is quiet: heat 0, no scripted job, a rig with a boom,
## nothing on the hook. Data: data/mechanics/random_events.json.

const DATA_PATH := "res://data/mechanics/random_events.json"
const REPO := preload("res://scripts/systems/repo_board.gd")     # PAD_CENTER / PAD_HALF
const PEDS := preload("res://scripts/systems/pedestrians.gd")    # body script + envelope
const FACTORY := preload("res://scripts/world/character_factory.gd")
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
const BEACON := preload("res://scripts/world/beacon_kit.gd")
const RNG_SEED := 0x57A4D
const SEDAN_SIZE := Vector3(1.9, 1.05, 4.4)
const SEDAN_RIDE := 0.85
const SEDAN_WHEEL := 0.32
const CAR_MASS := 1300.0
const CAR_FRICTION := 0.3
const SIDEWALK_Y := 0.2              # slab top: where the driver stands
const DRIVER_OUT := 3.0              # m outboard of the curb slot (past the 11 m kerb)
const OCCUPIED_M := 7.0              # a slot with a towable this close is taken
const HAIL_RANGE := 14.0             # the driver speaks once, this close
const HAZARD_HZ := 1.4
const HAZARD := Color(0.95, 0.55, 0.10)
const BEAM_HEIGHT := 14.0            # under the repo target's 21 m: a favor, not the job
const BEAM_WIDTH := 1.8
const BEAM_ALPHA := 0.26
const BEAM_ENERGY := 1.1
const RING_RADIUS := 3.2
const PAINT: Array[Color] = [Color(0.72, 0.70, 0.66), Color(0.20, 0.24, 0.30),
	Color(0.55, 0.12, 0.10), Color(0.33, 0.40, 0.30)]

# ============================== PUBLIC =======================================
var favors := 0                      # owed to Book; save_load persists, arrest spends
var active := false
var event_name := ""
var cfg: Dictionary = {}

# ============================== STATE ========================================
var main_ref: Node = null
var _disabled := false
var _rng := RandomNumberGenerator.new()
var _cooldown := 0.0
var _ttl := 0.0
var _car: RigidBody3D = null
var _driver: RigidBody3D = null
var _beacon: Node3D = null
var _hazard: StandardMaterial3D = null
var _hazard_t := 0.0
var _driver_cfg: Dictionary = {}
var _hailed := false
var _hooked := false
var _tow: Node = null
var _prev_hooked: Node = null
var _favor_lines: Array[String] = []
var _slots: Array[Vector3] = []      # (x, side, z) curb slots from parked_cars


func setup(main: Node) -> void:
	main_ref = main
	_rng.seed = RNG_SEED
	if bool(main.get("smoke_mode")):
		_disabled = true
		set_physics_process(false)
		return
	var f := FileAccess.open(DATA_PATH, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			cfg = parsed
	_cooldown = _n("first_delay_s", 40.0)


func _n(key: String, def: float) -> float:
	var v: Variant = cfg.get(key, def)
	return float(v) if (v is float or v is int) else def


func _physics_process(delta: float) -> void:
	if _disabled or main_ref == null:
		return
	_try_bind_tow()
	if active:
		_tick_live(delta)
		return
	_cooldown -= delta
	if _cooldown <= 0.0:
		_cooldown = _rng.randf_range(_n("interval_min_s", 75.0), _n("interval_max_s", 140.0))
		if _quiet_world():
			var pv := _player_vehicle()
			if pv != null:
				var slot := _pick_slot(pv.global_position, _n("spawn_min_m", 55.0), _n("spawn_max_m", 150.0))
				if slot.is_finite():
					_spawn_at(slot)


## PUBLIC (probe/debug): the next stranded driver, now, at any open curb.
func spawn_now() -> bool:
	if active:
		return false
	var a := _actor()
	if a == null:
		return false
	var slot := _pick_slot(a.global_position, 0.0, 1e9)
	if not slot.is_finite():
		return false
	_spawn_at(slot)
	return true


## PUBLIC (arrest): a favor called in. Returns the line for the card.
func spend_favor() -> String:
	if favors <= 0:
		return ""
	favors -= 1
	if _favor_lines.is_empty():   # a favor restored from a save has no face
		return "Somebody you towed made a call. Bail's covered."
	return _favor_lines.pop_front()


# ============================== WHEN =========================================
## Quiet: driving a rig with a boom, no heat, no scripted job, nothing hooked.
func _quiet_world() -> bool:
	if main_ref.get("on_foot") == true:
		return false
	var pv := _player_vehicle()
	if pv == null or not pv.has_method("has_boom") or not bool(pv.call("has_boom")):
		return false
	var pol := _peer("police")
	if pol != null:
		var hv: Variant = pol.get("heat")
		if hv is int and int(hv) > 0:
			return false
	for key: String in ["mission_hook_and_ladder", "mission_second_collection", "mission_comin_down"]:
		var m := _peer(key)
		if m != null and int(m.get("state")) != 0:
			return false
	var repo := _peer("repo_board")
	if repo != null and repo.get("_delivering") == true:
		return false
	if _tow != null and is_instance_valid(_tow) and _tow.get("hooked_body") != null:
		return false
	return true


## An open curb slot in the distance ring, roughly mid-ring, with some chance in it.
func _pick_slot(from: Vector3, dmin: float, dmax: float) -> Vector3:
	if _slots.is_empty():
		var parked := _peer("parked_cars")
		if parked != null and parked.has_method("_build_slots"):
			var got: Variant = parked.call("_build_slots")
			if got is Array:
				for v: Variant in got:
					if v is Vector3:
						_slots.append(v)
	var best := Vector3.INF
	var best_score := INF
	var towables := get_tree().get_nodes_in_group("towable")
	var mid := (dmin + minf(dmax, 400.0)) * 0.5
	for s in _slots:
		var d := Vector2(s.x - from.x, s.z - from.z).length()
		if d < dmin or d > dmax:
			continue
		var p := Vector3(s.x, SEDAN_RIDE, s.z)
		var taken := false
		for t in towables:
			if t is Node3D and is_instance_valid(t) and (t as Node3D).global_position.distance_to(p) < OCCUPIED_M:
				taken = true
				break
		if taken:
			continue
		var score := absf(d - mid) + _rng.randf() * 30.0
		if score < best_score:
			best_score = score
			best = s
	return best


# ============================== THE SCENE ====================================
func _spawn_at(slot: Vector3) -> void:
	var pos := Vector3(slot.x, SEDAN_RIDE, slot.z)
	var side := signf(slot.y) if absf(slot.y) > 0.5 else 1.0
	var fwd := Vector3(0.0, 0.0, -side)   # parked_cars' convention: nose along the curb
	_driver_cfg = {"name": "A STRANGER", "hail": "Somebody you towed made a call. Bail's covered."}
	var drivers: Variant = cfg.get("drivers", [])
	if drivers is Array and not (drivers as Array).is_empty():
		var pick: Variant = (drivers as Array)[_rng.randi_range(0, (drivers as Array).size() - 1)]
		if pick is Dictionary:
			_driver_cfg = pick
	var nm := str(_driver_cfg.get("name", ""))
	event_name = "STRANDED · %s" % nm
	# The car: a dead sedan, dynamic like a junker (it has to tow), hazards on.
	_car = RigidBody3D.new()
	_car.name = "Stranded"
	_car.mass = CAR_MASS
	var pm := PhysicsMaterial.new()
	pm.friction = CAR_FRICTION
	_car.physics_material_override = pm
	_car.add_to_group("towable")
	_car.add_to_group("stranded")
	_car.set_meta("carjack_has_driver", false)
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = SEDAN_SIZE
	col.shape = shape
	_car.add_child(col)
	var vis := Node3D.new()
	_car.add_child(vis)
	BODY_BUILDER.build(vis, "sedan", SEDAN_SIZE, PAINT[_rng.randi_range(0, PAINT.size() - 1)])
	_add_wheels(_car)
	_add_hazards(_car)
	_car.transform = Transform3D(Basis.looking_at(fwd, Vector3.UP), pos)
	add_child(_car)  # Node3D under a plain Node: transform acts as global
	# The driver: on the sidewalk, facing the road, waiting (no walk cycle).
	_driver = RigidBody3D.new()
	_driver.name = "StrandedDriver"
	_driver.mass = PEDS.PED_MASS
	_driver.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	_driver.freeze = true
	_driver.add_to_group("stranded_driver")
	var dcol := CollisionShape3D.new()
	var dshape := BoxShape3D.new()
	dshape.size = PEDS.COLLIDER_SIZE
	dcol.shape = dshape
	_driver.add_child(dcol)
	PEDS._body_script().build(_driver, FACTORY.random_config(_rng), -PEDS.PED_HALF)
	var dpos := Vector3(pos.x + side * DRIVER_OUT, SIDEWALK_Y + PEDS.PED_HALF, pos.z)
	_driver.transform = Transform3D(Basis.looking_at(Vector3(-side, 0.0, 0.0), Vector3.UP), dpos)
	add_child(_driver)
	_beacon = BEACON.beacon(HAZARD, BEAM_HEIGHT, BEAM_WIDTH, BEAM_ALPHA, BEAM_ENERGY, RING_RADIUS)
	_beacon.position = Vector3(pos.x, 0.05, pos.z)
	add_child(_beacon)
	_ttl = _n("ttl_s", 240.0)
	_hailed = false
	_hooked = false
	_hazard_t = 0.0
	active = true
	_flash("%s — a dead sedan on the curb. Hook it, haul it to the impound." % event_name)


func _add_wheels(body: RigidBody3D) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = SEDAN_WHEEL
	mesh.bottom_radius = SEDAN_WHEEL
	mesh.height = 0.24
	mesh.radial_segments = 18
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.08, 0.08, 0.09)
	mat.roughness = 0.9
	var zoff := SEDAN_SIZE.z * 0.5 - SEDAN_WHEEL - 0.7
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new()
		w.mesh = mesh
		w.material_override = mat
		w.rotation_degrees = Vector3(0, 0, 90)
		w.position = Vector3(c.x * (SEDAN_SIZE.x * 0.5 - 0.075), SEDAN_WHEEL - SEDAN_RIDE, c.y * zoff)
		body.add_child(w)


## Four amber lamps at the corners, blinking together: the universal "I'm stuck".
func _add_hazards(body: RigidBody3D) -> void:
	_hazard = StandardMaterial3D.new()
	_hazard.albedo_color = HAZARD
	_hazard.emission_enabled = true
	_hazard.emission = HAZARD
	_hazard.emission_energy_multiplier = 0.2
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var m := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.22, 0.09, 0.06)
			m.mesh = bm
			m.material_override = _hazard
			m.position = Vector3(sx * (SEDAN_SIZE.x * 0.5 - 0.2), -0.05, sz * (SEDAN_SIZE.z * 0.5 + 0.01))
			body.add_child(m)


# ============================== WHILE LIVE ===================================
func _tick_live(delta: float) -> void:
	if not is_instance_valid(_car) or not _car.is_inside_tree():
		_clear()
		return
	_hazard_t += delta
	if _hazard != null:
		_hazard.emission_energy_multiplier = 3.2 if fmod(_hazard_t * HAZARD_HZ, 1.0) < 0.5 else 0.15
	_evaluate_hook_state()
	if not _hooked:
		_ttl -= delta
		if _ttl <= 0.0:
			_clear()   # they called somebody else
			return
	var a := _actor()
	if a != null and not _hailed and a.global_position.distance_to(_car.global_position) < HAIL_RANGE:
		_hailed = true
		_flash("%s: \"Tow me to the lot and I'll make it right.\"" % str(_driver_cfg.get("name", "")))


func _try_bind_tow() -> void:
	if _tow != null and is_instance_valid(_tow):
		return
	_tow = _peer("tow_hook")
	if _tow == null:
		return
	for sig: String in ["hooked", "released"]:
		if _tow.has_signal(sig) and not _tow.is_connected(sig, _on_tow_event):
			_tow.connect(sig, _on_tow_event)


func _on_tow_event(_body: Variant = null) -> void:
	_evaluate_hook_state()


func _evaluate_hook_state() -> void:
	if _tow == null or not is_instance_valid(_tow) or _car == null:
		return
	var v: Variant = _tow.get("hooked_body")
	var cur: Node = v if (v is Node and is_instance_valid(v)) else null
	if cur == _prev_hooked:
		return
	var prev := _prev_hooked
	_prev_hooked = cur
	if cur == _car:
		_hooked = true
		if _beacon != null and is_instance_valid(_beacon):
			_beacon.queue_free()
			_beacon = null
		_flash("HAUL %s TO LONGHORN IMPOUND" % str(_driver_cfg.get("name", "")))
	elif prev == _car:
		_hooked = false
		var p := _car.global_position
		if absf(p.x - REPO.PAD_CENTER.x) <= REPO.PAD_HALF.x \
				and absf(p.z - REPO.PAD_CENTER.z) <= REPO.PAD_HALF.y and p.y < 4.0:
			_deliver()


func _deliver() -> void:
	var nm := str(_driver_cfg.get("name", "A STRANGER"))
	var repo := _peer("repo_board")
	if repo != null:
		if repo.has_method("add_money"):
			repo.call("add_money", int(_n("pay", 220)), "STRANDED · %s" % nm)
		if repo.has_method("add_respect"):
			repo.call("add_respect", int(_n("respect", 2)), nm)
	favors += 1
	_favor_lines.append(str(_driver_cfg.get("hail", "")))
	_clear()
	_flash("%s OWES YOU ONE." % nm)


func _clear() -> void:
	for n: Variant in [_car, _driver, _beacon]:
		if n is Node and is_instance_valid(n):
			(n as Node).queue_free()
	_car = null
	_driver = null
	_beacon = null
	_hazard = null
	active = false
	_hooked = false
	_prev_hooked = null
	event_name = ""
	_cooldown = _rng.randf_range(_n("interval_min_s", 75.0), _n("interval_max_s", 140.0))


# ============================== PLUMBING =====================================
func _flash(text: String) -> void:
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("flash"):
		repo.call("flash", text)


func _player_vehicle() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null


func _actor() -> Node3D:
	var key := "character" if main_ref.get("on_foot") == true else "vehicle"
	var a: Variant = main_ref.get(key)
	if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
		return a
	return null


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary and (sys as Dictionary).has(peer_name):
		var n: Variant = (sys as Dictionary)[peer_name]
		if n is Node and is_instance_valid(n):
			return n
	return null
