extends Node
## POLICE GUNFIRE — the arms race, evened. Since M5 the player has had a pistol
## and the cops have had bumpers; this closes the loop. The escalation ladder:
##   heat 0-1  chase and ram only (gray work stays survivable — the strip
##             teaches, it doesn't punish)
##   heat 2+   cruisers open fire ON THE RIDE — they want the vehicle stopped
##   heat 3    they will also shoot the man on foot
## Hitscan from each cruiser with a windup after line-of-sight is gained (fair
## warning), accuracy falling with distance and speed, tracers, muzzle flash,
## sparks and synthesized reports. Vehicle damage lands on a per-body HULL
## (meta, max from the JSON profile's "hull") which drags power_modifier down:
## the engine sputters below ~half, dies at zero — bail out and jack something
## (M6 is the getaway plan) — and sustained fire past dead kills the driver.
## The impound pad doubles as the body shop: stop on it, damaged, pay up.
## ENTIRELY INERT in smoke mode. Peers bound lazily, every ref null-checked.

signal shot_fired(pos: Vector3)   # pedestrians bind this: cop fire scatters too

# ============================== TUNABLES =====================================
const RNG_SEED := 0xC0FFE
const HEAT_VEHICLE := 2              # stars at which the ride draws fire
const HEAT_BOOK := 3                 # stars at which Book on foot draws fire
const RANGE := 55.0                  # max firing distance (m); no minimum —
                                     # parking next to a cop car is how you get
                                     # shot, never a safe zone
const WINDUP := 0.75                 # s of continuous LOS before the first shot
const FIRE_INTERVAL := 1.2           # s between shots per cruiser
const ACC_NEAR := 0.8                # hit probability at point blank...
const ACC_FAR := 0.25                # ...falling linearly to this at RANGE
const MOVING_TARGET_MULT := 0.6      # target above 12 m/s is hard to hit
const MOVING_SHOOTER_MULT := 0.75    # shooting from a moving cruiser is harder
const BOOK_DMG := 9.0                # per hit on the character (100 hp)
const VEHICLE_DMG := 7.0             # per hit on a vehicle hull
const HIT_IMPULSE := 420.0           # cars rock when shot (N*s)
const SPUTTER_FRAC := 0.55           # below this hull fraction power fades...
const MIN_POWER := 0.35              # ...toward this floor (0 only when dead)
const DEATH_HULL := -35.0            # keep shooting a dead car: driver dies
const MUZZLE_UP := 0.8               # muzzle height above cruiser origin (m)
const AIM_UP_CHAR := 1.05            # aim at the chest, feet-origin character
const AIM_UP_VEH := 0.45             # aim at the body, centre-origin vehicle
const HULL_META := "gunfire_hull"; const HULL_MAX_META := "gunfire_hull_max"
const DEAD_META := "gunfire_dead"
# Body shop: the impound pad, mirrored from repo_board.gd (PAD_CENTER/PAD_HALF).
const PAD_CENTER := Vector2(709.0, 558.0)
const PAD_HALF := Vector2(7.0, 5.0)
const REPAIR_TIME := 1.6             # s stopped on the pad before the bill
const REPAIR_STOP_SPEED := 1.2       # m/s counts as stopped
const COST_PER_POINT := 1.5          # $ per hull point ($195 full wrecker)
# FX pools (all built at setup, zero per-shot allocation).
const TRACER_POOL := 4; const TRACER_TIME := 0.04
const SPARK_POOL := 6; const SPARK_TIME := 0.16
const SPARK_SCALE := Vector2(0.14, 0.7)
const FLASH_POOL := 3; const FLASH_TIME := 0.05
const AUDIO_POOL := 4; const MIX_RATE := 22050
const SHOT_DB := -8.0; const THUNK_DB := -7.0
const SHOT_UNIT_SIZE := 13.0; const SHOT_MAX_DIST := 150.0
const VIGNETTE_SPIKE := 0.38; const VIGNETTE_DECAY := 1.1  # alpha; alpha/s
const RIDE_W := 150.0                # ride-condition bar under the stars

# ============================== STATE ========================================
var main_ref: Node = null
var _rng := RandomNumberGenerator.new()
var _gun: Dictionary = {}            # cruiser instance id -> {cd, los}
var _gc_t := 5.0
var _repair_t := 0.0
var _tracers: Array[MeshInstance3D] = []; var _tracer_t := PackedFloat32Array()
var _sparks: Array[MeshInstance3D] = []; var _spark_t := PackedFloat32Array()
var _flashes: Array[MeshInstance3D] = []; var _flash_t := PackedFloat32Array()
var _flash_light: OmniLight3D = null
var _tracer_i := 0; var _spark_i := 0; var _flash_i := 0; var _pool_i := 0
var _shot_stream: AudioStreamWAV = null; var _thunk_stream: AudioStreamWAV = null
var _players: Array[AudioStreamPlayer3D] = []
var _ui: CanvasLayer = null
var _vignette: ColorRect = null; var _vignette_a := 0.0
var _ride_root: Control = null; var _ride_fill: ColorRect = null
var _ride_label: Label = null


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		set_process(false)
		return  # smoke gate: fully inert — no UI, no FX, no audio buffers
	_rng.seed = RNG_SEED
	_shot_stream = _build_gunshot()
	_thunk_stream = _build_thunk()
	_build_fx()
	_build_ui()


func on_vehicle_changed(_vehicle: Node) -> void:
	pass  # hull rides the body as meta; nothing cached here


# ============================== PER-FRAME ====================================
func _physics_process(delta: float) -> void:
	if main_ref == null:
		return
	_pad_repair(delta)
	_gc_t -= delta
	if _gc_t <= 0.0:
		_gc_t = 5.0
		for id: int in _gun.keys():
			if instance_from_id(id) == null:
				_gun.erase(id)
	var pol := _peer("police")
	if pol == null:
		return
	var heat := int(pol.get("heat"))
	var pv := _actor()
	if heat < HEAT_VEHICLE or pv == null:
		if not _gun.is_empty():
			_gun.clear()
		return
	var on_foot := pv is CharacterBody3D
	if on_foot and heat < HEAT_BOOK:
		if not _gun.is_empty():
			_gun.clear()  # two stars corners the man; three shoots him
		return
	var of_peer := _peer("on_foot")
	if of_peer != null and of_peer.has_method("player_down") \
			and bool(of_peer.call("player_down")):
		return  # hold fire over the funeral card
	var tp := pv.global_position + Vector3.UP * (AIM_UP_CHAR if on_foot else AIM_UP_VEH)
	for n: Node in get_tree().get_nodes_in_group("police"):
		if not (n is RigidBody3D) or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var cr := n as RigidBody3D
		if cr.has_meta("combat_crippled"):
			continue  # five pistol rounds bought this silence; honour it
		var id := cr.get_instance_id()
		var g: Dictionary = _gun.get(id, {"cd": 0.0, "los": 0.0})
		g["cd"] = maxf(float(g["cd"]) - delta, 0.0)
		var muzzle := cr.global_position + Vector3.UP * MUZZLE_UP
		var dist := muzzle.distance_to(tp)
		if dist > RANGE or dist < 1.5 or not _clear_shot(cr, muzzle, tp, pv):
			g["los"] = 0.0  # windup re-arms whenever the shot is lost
		else:
			g["los"] = float(g["los"]) + delta
			if float(g["los"]) >= WINDUP and float(g["cd"]) <= 0.0:
				g["cd"] = FIRE_INTERVAL
				_fire(cr, muzzle, tp, pv, dist)
		_gun[id] = g


func _process(delta: float) -> void:
	for i in _tracers.size():
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			if _tracer_t[i] <= 0.0:
				_tracers[i].visible = false
	var any_flash := false
	for i in _flashes.size():
		if _flash_t[i] > 0.0:
			_flash_t[i] -= delta
			if _flash_t[i] <= 0.0:
				_flashes[i].visible = false
		any_flash = any_flash or _flash_t[i] > 0.0
	if _flash_light != null and _flash_light.visible and not any_flash:
		_flash_light.visible = false
	for i in _sparks.size():
		if _spark_t[i] <= 0.0:
			continue
		_spark_t[i] -= delta
		var k := 1.0 - clampf(_spark_t[i] / SPARK_TIME, 0.0, 1.0)
		_sparks[i].scale = Vector3.ONE * lerpf(SPARK_SCALE.x, SPARK_SCALE.y, k)
		if _spark_t[i] <= 0.0:
			_sparks[i].visible = false
	if _vignette != null:
		_vignette_a = maxf(_vignette_a - VIGNETTE_DECAY * delta, 0.0)
		_vignette.modulate.a = _vignette_a
		_vignette.visible = _vignette_a > 0.005
	_update_ride_ui()


# ============================== FIRING =======================================
## Ray to the aim point, excluding the shooter: clear when nothing is between
## the muzzle and the target (the target itself being hit IS clear).
func _clear_shot(cr: RigidBody3D, from: Vector3, to: Vector3, pv: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [cr.get_rid()]
	var hit := cr.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == pv


func _fire(cr: RigidBody3D, muzzle: Vector3, tp: Vector3, pv: Node3D, dist: float) -> void:
	var acc := lerpf(ACC_NEAR, ACC_FAR, clampf(dist / RANGE, 0.0, 1.0))
	if _speed_of(pv) > 12.0:
		acc *= MOVING_TARGET_MULT
	if cr.linear_velocity.length() > 12.0:
		acc *= MOVING_SHOOTER_MULT
	var hit := _rng.randf() < acc
	var dir := (tp - muzzle).normalized()
	var endp := tp
	if hit:
		if pv is CharacterBody3D and pv.has_method("take_damage"):
			pv.call("take_damage", BOOK_DMG, cr)
			_vignette_a = VIGNETTE_SPIKE
			_shake(0.45)   # taking a round shoves the camera
		elif pv is RigidBody3D:
			_damage_vehicle(pv as RigidBody3D, tp, dir)
			_play(_thunk_stream, THUNK_DB, _rng.randf_range(0.9, 1.1), tp)
			_shake(0.22)   # rounds punching sheet metal around you
		_spawn_spark(tp)
	else:
		# A clean miss reads as a miss: kicked sideways past the target, never
		# landing so close it looks like a phantom hit.
		var side := Vector3(-dir.z, 0.0, dir.x)
		var sgn := 1.0 if _rng.randf() < 0.5 else -1.0
		endp = tp + side * sgn * _rng.randf_range(1.2, 2.6) \
			+ Vector3.UP * _rng.randf_range(-0.3, 0.9)
	_show_tracer(muzzle, endp)
	_show_flash(muzzle)
	_play(_shot_stream, SHOT_DB, _rng.randf_range(0.92, 1.05), muzzle)
	shot_fired.emit(muzzle)


# ============================== HULL DAMAGE ==================================
## Hull lives in meta on the body (it survives Tab-less ownership changes and
## belongs to the car, not to us); the max is read once from the JSON profile.
func _hull_max(veh: RigidBody3D) -> float:
	if veh.has_meta(HULL_MAX_META):
		return float(veh.get_meta(HULL_MAX_META))
	var mx := 100.0
	var prof: Variant = veh.get("p")
	if prof is Dictionary:
		mx = float((prof as Dictionary).get("hull", 100.0))
	veh.set_meta(HULL_MAX_META, mx)
	veh.set_meta(HULL_META, mx)
	return mx


func _damage_vehicle(veh: RigidBody3D, pos: Vector3, dir: Vector3) -> void:
	var mx := _hull_max(veh)
	var hull := float(veh.get_meta(HULL_META, mx)) - VEHICLE_DMG
	veh.set_meta(HULL_META, hull)
	_apply_power(veh, hull, mx)
	veh.apply_impulse(dir * HIT_IMPULSE, pos - veh.global_position)
	if hull <= 0.0 and not veh.has_meta(DEAD_META):
		veh.set_meta(DEAD_META, true)
		_flash_banner("ENGINE'S SHOT — BAIL OUT (E)")
	# They keep shooting the wreck you refuse to leave: eventually the wreck
	# stops being between you and the bullets.
	if hull <= DEATH_HULL and _fetch("vehicle") == veh and not _on_foot():
		var of_peer := _peer("on_foot")
		if of_peer != null and of_peer.has_method("kill_player"):
			of_peer.call("kill_player")


func _apply_power(veh: RigidBody3D, hull: float, mx: float) -> void:
	var pm := 1.0
	if hull <= 0.0:
		pm = 0.0
	else:
		var frac := clampf(hull / mx, 0.0, 1.0)
		if frac < SPUTTER_FRAC:
			pm = lerpf(MIN_POWER, 1.0, frac / SPUTTER_FRAC)
	veh.set("power_modifier", pm)


## PUBLIC (on_foot._respawn): County General's parking lot fixes what the
## county shot. Current ride + your own truck, free with the $300 bill.
func repair_all() -> void:
	for v: Variant in [_fetch("vehicle"), _fetch("own_vehicle")]:
		if v is RigidBody3D and is_instance_valid(v):
			_repair(v as RigidBody3D)


func _repair(veh: RigidBody3D) -> void:
	var mx := _hull_max(veh)
	veh.set_meta(HULL_META, mx)
	if veh.has_meta(DEAD_META):
		veh.remove_meta(DEAD_META)
	veh.set("power_modifier", 1.0)


# ============================== BODY SHOP ====================================
## The impound pad moonlights as the body shop: sit still on it with a shot-up
## ride for REPAIR_TIME and the hull comes back at $1.50 a point.
func _pad_repair(delta: float) -> void:
	var pv := _fetch("vehicle")
	if pv == null or not (pv is RigidBody3D) or _on_foot() \
			or not pv.has_meta(HULL_META):
		_repair_t = 0.0
		return
	var veh := pv as RigidBody3D
	var mx := _hull_max(veh)
	var hull := float(veh.get_meta(HULL_META, mx))
	if hull >= mx - 0.01:
		_repair_t = 0.0
		return
	var p := veh.global_position
	if absf(p.x - PAD_CENTER.x) > PAD_HALF.x or absf(p.z - PAD_CENTER.y) > PAD_HALF.y \
			or veh.linear_velocity.length() > REPAIR_STOP_SPEED:
		_repair_t = 0.0
		return
	_repair_t += delta
	if _repair_t < REPAIR_TIME:
		return
	_repair_t = 0.0
	var cost := int(ceilf((mx - maxf(hull, 0.0)) * COST_PER_POINT))
	_repair(veh)
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("add_money"):
		repo.call("add_money", -cost, "BODY SHOP")


# ============================== FX ===========================================
func _build_fx() -> void:
	var tracer_mat := _emissive(Color(1.0, 0.75, 0.35))
	_tracer_t.resize(TRACER_POOL)
	for i in TRACER_POOL:
		var t := _box_mesh(Vector3(0.03, 0.03, 1.0), tracer_mat)
		t.visible = false
		add_child(t)  # Node3D under a plain Node: transform acts as global
		_tracers.append(t)
		_tracer_t[i] = 0.0
	var spark_mat := _emissive(Color(1.0, 0.7, 0.3))
	_spark_t.resize(SPARK_POOL)
	for i in SPARK_POOL:
		var s := _box_mesh(Vector3.ONE, spark_mat)
		s.visible = false
		add_child(s)
		_sparks.append(s)
		_spark_t[i] = 0.0
	var flash_mat := _emissive(Color(1.0, 0.88, 0.5))
	_flash_t.resize(FLASH_POOL)
	for i in FLASH_POOL:
		var f := _box_mesh(Vector3(0.16, 0.16, 0.24), flash_mat)
		f.visible = false
		add_child(f)
		_flashes.append(f)
		_flash_t[i] = 0.0
	_flash_light = OmniLight3D.new()
	_flash_light.light_color = Color(1.0, 0.85, 0.5)
	_flash_light.light_energy = 2.5
	_flash_light.omni_range = 6.0
	_flash_light.shadow_enabled = false
	_flash_light.visible = false
	add_child(_flash_light)
	for i in AUDIO_POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = SHOT_UNIT_SIZE
		p.max_distance = SHOT_MAX_DIST
		add_child(p)
		_players.append(p)


func _show_tracer(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.2:
		return
	var idx := _tracer_i
	_tracer_i = (_tracer_i + 1) % TRACER_POOL
	var t := _tracers[idx]
	var n := d / len
	var up := Vector3.UP if absf(n.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	t.global_transform = Transform3D(
		Basis.looking_at(n, up) * Basis.from_scale(Vector3(1.0, 1.0, len)),
		from + d * 0.5)
	t.visible = true
	_tracer_t[idx] = TRACER_TIME


func _show_flash(muzzle: Vector3) -> void:
	var f := _flashes[_flash_i]
	_flash_t[_flash_i] = FLASH_TIME
	_flash_i = (_flash_i + 1) % FLASH_POOL
	f.global_position = muzzle
	f.visible = true
	_flash_light.global_position = muzzle
	_flash_light.visible = true


func _spawn_spark(pos: Vector3) -> void:
	var s := _sparks[_spark_i]
	_spark_t[_spark_i] = SPARK_TIME
	_spark_i = (_spark_i + 1) % SPARK_POOL
	s.global_position = pos
	s.scale = Vector3.ONE * SPARK_SCALE.x
	s.visible = true


func _emissive(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.5
	return m


func _box_mesh(size: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	return mi


# ============================== AUDIO ========================================
## Pooled players live on this node (never leaves the tree until quit), so the
## _exit_tree stop is the whole 4.7.1 leak mitigation — no per-cruiser players.
func _play(stream: AudioStreamWAV, db: float, pitch: float, at: Vector3) -> void:
	if stream == null or _players.is_empty():
		return
	var p := _players[_pool_i]
	_pool_i = (_pool_i + 1) % _players.size()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree():
		return
	p.global_position = at
	p.stream = stream
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


func _exit_tree() -> void:
	for p in _players:
		if p != null and is_instance_valid(p):
			p.stop()


## Duty pistol, deeper than Book's: slower crack over a 120->40 Hz thump.
func _build_gunshot() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(6000)
	var phase := 0.0
	for i in samples.size():
		var t := float(i) / float(MIX_RATE)
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-70.0 * t) * 0.8
		phase += TAU * lerpf(120.0, 40.0, clampf(t / 0.27, 0.0, 1.0)) / float(MIX_RATE)
		var thump := sin(phase) * exp(-12.0 * t) * 0.75
		samples[i] = (crack + thump) * minf(float(i) / 8.0, 1.0)  # ramp kills pop
	return _wav(samples)


## Sheet-metal thunk for a hull hit: short lowpassed burst, fast decay.
func _build_thunk() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(2756)
	var n0 := 0.0; var n1 := 0.0; var n2 := 0.0
	for i in samples.size():
		n2 = n1; n1 = n0
		n0 = _rng.randf_range(-1.0, 1.0)
		var t := float(i) / float(MIX_RATE)
		samples[i] = (n0 + n1 + n2) / 3.0 * exp(-40.0 * t) \
			* minf(float(i) / 10.0, 1.0) * 0.9
	return _wav(samples)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = bytes
	return w


# ============================== UI ===========================================
## Damage vignette (layer 25, under the death card's 30) + the RIDE bar tucked
## under the wanted stars top-right (stars end ~y 70; bar band y 78-98).
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 25
	add_child(_ui)
	_vignette = ColorRect.new()
	_vignette.color = Color(0.55, 0.02, 0.02)
	_vignette.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_vignette.modulate.a = 0.0
	_vignette.visible = false
	_ui.add_child(_vignette)
	_ride_root = Control.new()
	_ride_root.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_ride_root.offset_left = -(RIDE_W + 16.0)
	_ride_root.offset_right = -16.0
	_ride_root.offset_top = 78.0
	_ride_root.offset_bottom = 104.0
	_ride_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ride_root.visible = false
	_ui.add_child(_ride_root)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.45)
	bg.size = Vector2(RIDE_W, 5)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_ride_root.add_child(bg)
	_ride_fill = ColorRect.new()
	_ride_fill.size = Vector2(RIDE_W, 5)
	_ride_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_ride_root.add_child(_ride_fill)
	_ride_label = Label.new()
	_ride_label.position = Vector2(0, 7)
	_ride_label.add_theme_font_size_override("font_size", 12)
	_ride_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_ride_label.add_theme_constant_override("outline_size", 4)
	_ride_root.add_child(_ride_label)


func _update_ride_ui() -> void:
	if _ride_root == null:
		return
	var pv := _fetch("vehicle")
	var show := false
	if pv is RigidBody3D and not _on_foot() and pv.has_meta(HULL_META):
		var mx := float(pv.get_meta(HULL_MAX_META, 100.0))
		var hull := float(pv.get_meta(HULL_META, mx))
		if hull < mx - 0.01:
			show = true
			var frac := clampf(hull / mx, 0.0, 1.0)
			_ride_fill.size.x = RIDE_W * frac
			_ride_fill.color = Color(0.85, 0.25, 0.2).lerp(Color(0.35, 0.8, 0.4), frac)
			if hull <= 0.0:
				_ride_label.text = "ENGINE DEAD — BAIL (E)"
				_ride_label.add_theme_color_override("font_color", Color(1.0, 0.4, 0.3))
			else:
				_ride_label.text = "RIDE"
				_ride_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_ride_root.visible = show


# ============================== PLUMBING =====================================
func _shake(amount: float) -> void:
	var cam: Variant = main_ref.get("camera") if main_ref != null else null
	if cam is Object and is_instance_valid(cam) and (cam as Object).has_method("add_trauma"):
		(cam as Object).call("add_trauma", amount)


func _flash_banner(text: String) -> void:
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("flash"):
		repo.call("flash", text)


func _fetch(prop: String) -> Node3D:
	var v: Variant = main_ref.get(prop) if main_ref != null else null
	return v if v is Node3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null


func _on_foot() -> bool:
	return main_ref != null and main_ref.get("on_foot") == true


## The body the cops are shooting at: character on foot, vehicle otherwise.
func _actor() -> Node3D:
	if main_ref != null and main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	return _fetch("vehicle")


## Duck-typed speed: rigid bodies and characters store velocity differently.
func _speed_of(a: Node3D) -> float:
	if a is RigidBody3D:
		return (a as RigidBody3D).linear_velocity.length()
	if a is CharacterBody3D:
		return (a as CharacterBody3D).velocity.length()
	return 0.0


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null
