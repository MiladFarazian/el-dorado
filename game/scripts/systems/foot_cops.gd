extends Node
## FOOT COPS v1 (M14) — the cruiser door finally opens. At heat 2+ while the
## player is ON FOOT, any police cruiser that has come to a stop near him
## unloads its officer: a frozen-kinematic factory cop (pedestrians.gd's proven
## pattern, moved by transform every physics tick) who runs the man down at
## 5.6 m/s — Book sprints 7.0, so he can be OUTRUN, per the dumb-fun design law
## — stops at nine metres, and shoots only after a fair-warning windup with
## continuous line of sight. Officers jog back to the cruiser and vanish when
## the player mounts up, drop everything the moment heat clears, and go down to
## two pistol hits (one to the hat) as loose tumbling physics — downing one is
## +1 heat. Group "officer" ONLY (reserved): never "pedestrian", never
## "towable". Never spawns in the protected corridor. ENTIRELY INERT in smoke
## mode. Peers bound lazily via main.systems; every reference null-checked.

signal shot_fired(pos: Vector3)   # pedestrians bind this: officer fire scatters

# ============================== TUNABLES =====================================
const RNG_SEED := 0xF007C0        # own stream: costumes, aim rolls, tumbles
const MAX_OFFICERS := 4           # global cap on live officers, downed included
const DEPLOY_HEAT := 2            # stars at which stopped cruisers unload
const DEPLOY_SCAN := 0.5          # s between deploy scans (cheap cadence)
const DEPLOY_RANGE := 35.0        # cruiser-to-player reach for a deploy (m)
const CRUISER_STILL := 1.5        # cruiser speed that counts as stopped (m/s)
const DOOR_OUT := 1.7             # officer appears this far out the door (m)
const RUN_SPEED := 5.6            # pursuit run — player sprint is 7.0
const RETURN_SPEED := 4.5         # the jog back to the cruiser
const HOLD_DIST := 9.0            # stop here and shoot; don't hug the target (m)
const DESPAWN_DIST := 130.0       # player farther than this: give it up (m)
const AT_CRUISER := 2.2           # close enough to the cruiser to mount (m)
const LOST_CRUISER := 8.0         # s to give up when the cruiser is gone
const DOWN_TIME := 20.0           # s a downed officer lies before cleanup
const HITS_TO_DOWN := 2           # pistol body hits; a headshot counts double
const DOWN_HEAT := 1              # downing an officer is +1 heat
# Gunfire (the police_gunfire fair-warning model, sidearm numbers).
const RANGE := 45.0               # max firing distance (m)
const WINDUP := 0.9               # s of continuous LOS before the first shot
const FIRE_INTERVAL := 1.5        # s between shots per officer
const ACC_NEAR := 0.75            # hit probability at ACC_NEAR_DIST...
const ACC_FAR := 0.2              # ...falling linearly to this at RANGE
const ACC_NEAR_DIST := 4.0
const SPRINT_MULT := 0.55         # a sprinting player is harder to hit
const SHOT_DMG := 9.0             # per hit on the character (100 hp)
const MUZZLE_UP := 0.55           # muzzle above the officer's centre origin (m)
const AIM_UP := 1.05              # chest height above the feet-origin character
# Body (the pedestrians.gd mannequin envelope; centre-origin collider).
const COLLIDER_SIZE := Vector3(0.5, 1.75, 0.35)
const OFFICER_MASS := 80.0
const HALF_H := 0.875             # half of the 1.75 m collider
const GROUND_FALLBACK := 0.2      # slab top, used when the down-ray finds nothing
const KNOCK_RADIUS := 1.7; const KNOCK_CLOSING := 4.0  # pre-impact unfreeze
const TUMBLE_CARRY := 0.6; const TUMBLE_POP := 2.2     # down-tumble kinematics
const TUMBLE_PUSH := 2.0          # shove away from whoever downed him (m/s)
const CORRIDOR := Rect2(174.0, 424.0, 38.0, 152.0)  # protected: NEVER spawn in
# FX pools (built at setup, zero per-shot allocation; pooled audio lives on
# this never-freed node — the 4.7.1 audio-at-quit law).
const TRACER_POOL := 3; const TRACER_TIME := 0.04
const FLASH_POOL := 2; const FLASH_TIME := 0.05
const AUDIO_POOL := 3; const MIX_RATE := 22050
const SHOT_DB := -9.0; const SHOT_UNIT_SIZE := 13.0; const SHOT_MAX_DIST := 150.0

const FACTORY := preload("res://scripts/world/character_factory.gd")
## SKINNED-BODY PROOF OF CONCEPT — inert unless `--skinned` is on the command
## line. `character_factory` remains the shipping path and is not modified; only
## `build()` is redirected, because `animate()` / `aim_pose()` / the rig dict are
## contract-identical between the two and the skinned body delegates to the
## factory's animator anyway.
const SKINNED := preload("res://scripts/world/skinned_character.gd")
static func _body_script() -> GDScript:
	return FACTORY if OS.get_cmdline_user_args().has("--factory") else SKINNED   # D-050: skinned is the default; --factory is the M22 body

enum { PURSUE, RETURN, DOWN }

# ============================== STATE ========================================
var main_ref: Node = null
var _rng := RandomNumberGenerator.new()
var _officers: Array[Dictionary] = []
var _scan_cd := 0.0; var _spawned := 0
var _tracers: Array[MeshInstance3D] = []; var _tracer_t := PackedFloat32Array()
var _flashes: Array[MeshInstance3D] = []; var _flash_t := PackedFloat32Array()
var _tracer_i := 0; var _flash_i := 0; var _pool_i := 0
var _shot_stream: AudioStreamWAV = null
var _players: Array[AudioStreamPlayer3D] = []


func setup(main: Node) -> void:
	main_ref = main; _rng.seed = RNG_SEED
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false); return  # smoke gate: inert
	_shot_stream = _build_pistol_crack()
	_build_fx()


# ============================== PER-FRAME ====================================
func _physics_process(delta: float) -> void:
	if main_ref == null: return
	var heat := _heat()
	if heat <= 0 and not _officers.is_empty():
		_despawn_all()  # EVADED: everybody back in the cars, instantly
	var pv := _actor()
	_scan_cd = maxf(_scan_cd - delta, 0.0)
	if _scan_cd <= 0.0:
		_scan_cd = DEPLOY_SCAN
		if pv != null and heat >= DEPLOY_HEAT and _on_foot() and not _player_down():
			_deploy_scan(pv)
	for i in range(_officers.size() - 1, -1, -1):
		var o := _officers[i]
		var body := o["body"] as RigidBody3D
		if not is_instance_valid(body) or not body.is_inside_tree():
			_officers.remove_at(i); continue
		if _update_officer(o, body, delta, pv):
			body.queue_free(); _officers.remove_at(i)


func _process(delta: float) -> void:
	for i in _tracers.size():
		if _tracer_t[i] > 0.0:
			_tracer_t[i] -= delta
			if _tracer_t[i] <= 0.0: _tracers[i].visible = false
	for i in _flashes.size():
		if _flash_t[i] > 0.0:
			_flash_t[i] -= delta
			if _flash_t[i] <= 0.0: _flashes[i].visible = false


# ============================== DEPLOYMENT ===================================
## Stopped cruisers within reach of an on-foot player each unload ONE officer,
## up to the global cap. Real cruiser spawn sites already avoid the corridor;
## the door position is clamped against it anyway (physics is sacred).
func _deploy_scan(pv: Node3D) -> void:
	if _officers.size() >= MAX_OFFICERS: return
	for n: Node in get_tree().get_nodes_in_group("police"):
		if _officers.size() >= MAX_OFFICERS: return
		if not (n is RigidBody3D) or not is_instance_valid(n) or not n.is_inside_tree():
			continue
		var cr := n as RigidBody3D
		if cr.linear_velocity.length() > CRUISER_STILL: continue
		var cp := cr.global_position
		if Vector2(cp.x - pv.global_position.x, cp.z - pv.global_position.z).length() \
				> DEPLOY_RANGE: continue
		if _has_officer_from(cr): continue  # one officer per cruiser
		var pos := cp + cr.global_transform.basis.x * DOOR_OUT
		if CORRIDOR.has_point(Vector2(pos.x, pos.z)): continue  # sacred corridor
		_deploy(cr, pos, pv)


func _deploy(cruiser: RigidBody3D, pos: Vector3, pv: Node3D) -> void:
	var body := RigidBody3D.new()
	_spawned += 1
	body.name = "FootCop%d" % _spawned  # unique: no @Name@N auto-rename
	body.mass = OFFICER_MASS
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; body.freeze = true
	# 8, not 2: speculative contacts with the slab exhaust a small budget and
	# dynamic-body contacts then never report (hard-learned in traffic.gd).
	body.contact_monitor = true; body.max_contacts_reported = 8
	body.add_to_group("officer")  # ONLY — never "pedestrian", never "towable"
	var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = COLLIDER_SIZE; col.shape = shape; body.add_child(col)
	var rig: Dictionary = _body_script().build(body, FACTORY.cop_config(_rng), -HALF_H)
	add_child(body)  # Node3D under a plain Node: transform acts as global
	var head := pv.global_position - pos; head.y = 0.0
	head = head.normalized() if head.length() > 0.1 else Vector3.FORWARD
	_place(body, head, Vector3(pos.x, _ground_y(body, pos), pos.z))
	body.body_entered.connect(_on_contact.bind(body))
	_officers.append({
		"body": body, "rig": rig, "cruiser": cruiser,
		"cruiser_pos": cruiser.global_position, "state": PURSUE,
		"los": 0.0, "cd": 0.0, "hits": 0, "down_t": 0.0, "lost_t": 0.0})


# ============================== BEHAVIOUR ====================================
## One officer's tick. Returns true when he should despawn.
func _update_officer(o: Dictionary, body: RigidBody3D, delta: float, pv: Node3D) -> bool:
	if int(o["state"]) == DOWN:
		# D-059: no animate() on a downed man — the idle would breathe on the pavement.
		o["down_t"] = float(o["down_t"]) + delta
		return float(o["down_t"]) >= DOWN_TIME
	if pv != null:
		var sep := body.global_position - pv.global_position
		if Vector2(sep.x, sep.z).length() > DESPAWN_DIST:
			return true  # the man is long gone; so is the manhunt
		# Fast actor bearing down: unfreeze BEFORE the impact so the hit lands
		# on loose physics, not an immovable kinematic wall (house rule).
		var d := sep.length()
		if d > 0.01 and d < KNOCK_RADIUS and _actor_velocity(pv).dot(sep / d) > KNOCK_CLOSING:
			_down(o, body, pv, true)
			return false
	o["state"] = PURSUE if _on_foot() else RETURN
	var gait := 0.0
	if int(o["state"]) == PURSUE:
		if pv != null:
			gait = _step_pursue(body, delta, pv)
			_fire_logic(o, body, delta, pv)
	else:
		o["los"] = 0.0  # nobody shoots on the jog home
		if _step_return(o, body, delta): return true
		gait = RETURN_SPEED
	# Kinematic bodies have zero velocity: the gait speed is the SCRIPTED one.
	FACTORY.animate(o["rig"] as Dictionary, gait, delta, gait > 0.05, true)
	if int(o["state"]) == PURSUE and gait <= 0.05:
		FACTORY.aim_pose(o["rig"] as Dictionary, delta)  # holding at nine metres
	return false


## Straight-line pursuit, ground-clamped; stops and holds at HOLD_DIST.
## D-103: officers honour the police SEARCH. While the player is unseen they
## converge on the last sighting (police.search_center), not on a position they
## have no way of knowing; their guns already need line of sight (_clear_shot),
## so the whole squad now plays by one rule. Falls back to the true position
## whenever the police system is absent or not searching.
func _chase_point(pv: Node3D) -> Vector3:
	var police := _peer("police")
	if police != null and police.get("search_active") == true:
		var c: Variant = police.get("search_center")
		if c is Vector3:
			return c as Vector3
	return pv.global_position


func _step_pursue(body: RigidBody3D, delta: float, pv: Node3D) -> float:
	var to := _chase_point(pv) - body.global_position; to.y = 0.0
	var d := to.length()
	var head := to / d if d > 0.05 else Vector3.FORWARD
	var pos := body.global_position
	var gait := 0.0
	if d > HOLD_DIST:
		gait = RUN_SPEED
		pos += head * minf(RUN_SPEED * delta, d - HOLD_DIST)
	pos.y = _ground_y(body, pos)
	_place(body, head, pos)
	return gait


## The jog back to the cruiser. Returns true when he is done (mounted up, or
## the cruiser has been gone for LOST_CRUISER seconds).
func _step_return(o: Dictionary, body: RigidBody3D, delta: float) -> bool:
	var cr: Variant = o["cruiser"]
	var target := o["cruiser_pos"] as Vector3
	if is_instance_valid(cr) and (cr as Node).is_inside_tree():
		target = (cr as Node3D).global_position
		o["cruiser_pos"] = target
	else:
		o["lost_t"] = float(o["lost_t"]) + delta
		if float(o["lost_t"]) >= LOST_CRUISER: return true
	var to := target - body.global_position; to.y = 0.0
	var d := to.length()
	if d <= AT_CRUISER: return true  # back at the door: gone
	var head := to / d
	var pos := body.global_position + head * minf(RETURN_SPEED * delta, d)
	pos.y = _ground_y(body, pos)
	_place(body, head, pos)
	return false


## Ground clamp: one short ray down onto STATIC world only (streets y=0, slabs
## y=0.2, the freeway deck if a cruiser ever stops up there). Nothing under
## him: keep the current height rather than tunnel.
func _ground_y(body: RigidBody3D, pos: Vector3) -> float:
	var from := Vector3(pos.x, pos.y + 1.2, pos.z)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 4.0)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if not hit.is_empty() and hit.get("collider") is StaticBody3D:
		return float((hit["position"] as Vector3).y) + HALF_H
	return pos.y


# ============================== GUNFIRE ======================================
## Fair warning: WINDUP seconds of continuous line of sight before the first
## shot, then one per FIRE_INTERVAL. ALL fire held over the funeral card.
func _fire_logic(o: Dictionary, body: RigidBody3D, delta: float, pv: Node3D) -> void:
	o["cd"] = maxf(float(o["cd"]) - delta, 0.0)
	if _player_down():
		o["los"] = 0.0  # hold fire over the funeral card; windup re-arms
		return
	var muzzle := body.global_position + Vector3.UP * MUZZLE_UP
	var tp := pv.global_position + Vector3.UP * AIM_UP
	var dist := muzzle.distance_to(tp)
	if dist > RANGE or not _clear_shot(body, muzzle, tp, pv):
		o["los"] = 0.0  # windup re-arms whenever the shot is lost
		return
	o["los"] = float(o["los"]) + delta
	if float(o["los"]) >= WINDUP and float(o["cd"]) <= 0.0:
		o["cd"] = FIRE_INTERVAL
		_fire(body, muzzle, tp, pv, dist)


## Ray to the aim point, excluding the shooter: clear when nothing sits between
## the muzzle and the target (hitting the target itself IS clear).
func _clear_shot(body: RigidBody3D, from: Vector3, to: Vector3, pv: Node3D) -> bool:
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	return hit.is_empty() or hit.get("collider") == pv


func _fire(body: RigidBody3D, muzzle: Vector3, tp: Vector3, pv: Node3D, dist: float) -> void:
	var acc := lerpf(ACC_NEAR, ACC_FAR,
		clampf((dist - ACC_NEAR_DIST) / (RANGE - ACC_NEAR_DIST), 0.0, 1.0))
	var sprinting: bool = pv.get("is_sprinting") == true
	if sprinting: acc *= SPRINT_MULT
	var hit := _rng.randf() < acc
	var endp := tp
	if hit:
		if pv.has_method("take_damage"):
			pv.call("take_damage", SHOT_DMG, body)
		_shake(0.3)
	else:
		# A clean miss reads as a miss: kicked sideways past the target, never
		# landing so close it looks like a phantom hit. Nothing lands.
		var dir := (tp - muzzle).normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var sgn := 1.0 if _rng.randf() < 0.5 else -1.0
		endp = tp + side * sgn * _rng.randf_range(1.0, 2.4) \
			+ Vector3.UP * _rng.randf_range(-0.3, 0.8)
	_show_tracer(muzzle, endp)
	_show_flash(muzzle)
	_play(muzzle)
	shot_fired.emit(muzzle)


# ============================== GOING DOWN ===================================
## PUBLIC (combat wiring): an officer took one of the player's pistol rounds.
## Two body hits — or one to the hat — put him DOWN: loose tumbling physics,
## no more fire, +1 heat (you shot a cop), swept after DOWN_TIME.
func officer_shot(body: RigidBody3D, head: bool) -> void:
	if body == null or not is_instance_valid(body): return
	for o in _officers:
		if o["body"] != body: continue
		if int(o["state"]) == DOWN: return
		o["hits"] = int(o["hits"]) + (HITS_TO_DOWN if head else 1)
		if int(o["hits"]) >= HITS_TO_DOWN:
			_down(o, body, _actor(), true)
		return


## Handoff to loose physics: the same bloodless mannequin tumble pedestrians
## do. `charge` prices the takedown (+1 heat) — true for the player's bullets
## and the player's bumper, false for stray debris and friendly cruiser fire.
func _down(o: Dictionary, body: RigidBody3D, striker: Node3D, charge: bool) -> void:
	if int(o["state"]) == DOWN: return
	o["state"] = DOWN; o["down_t"] = 0.0; o["los"] = 0.0
	body.freeze = false
	var push := Vector3.ZERO
	if striker != null and is_instance_valid(striker):
		var away := body.global_position - striker.global_position; away.y = 0.0
		if away.length() > 0.1: push = away.normalized() * TUMBLE_PUSH
		push += _actor_velocity(striker) * TUMBLE_CARRY
	body.linear_velocity = push + Vector3.UP * TUMBLE_POP
	body.angular_velocity = Vector3(_rng.randf_range(-4.0, 4.0),
		_rng.randf_range(-2.0, 2.0), _rng.randf_range(-4.0, 4.0))
	if not charge: return
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"):
		pol.call("add_heat", DOWN_HEAT, "DOWNED AN OFFICER")


## Contact backup for hits the proximity check missed. Static world is NOT a
## hit (speculative slab contacts), neither is a frozen kinematic peer, and a
## strolling character shoves past — only sprint speed bowls an officer over.
func _on_contact(other: Node, body: RigidBody3D) -> void:
	if other is StaticBody3D: return
	if other is RigidBody3D and (other as RigidBody3D).freeze: return
	var v := Vector3.ZERO
	if other is Node3D: v = _actor_velocity(other as Node3D)
	if v.length() < KNOCK_CLOSING: return
	var o := _find(body)
	if o.is_empty() or int(o["state"]) == DOWN: return
	_down(o, body, other as Node3D, other == _actor())


func _despawn_all() -> void:
	for o in _officers:
		var b: Variant = o["body"]
		if is_instance_valid(b): (b as Node).queue_free()
	_officers.clear()


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
	var flash_mat := _emissive(Color(1.0, 0.88, 0.5))
	_flash_t.resize(FLASH_POOL)
	for i in FLASH_POOL:
		var f := _box_mesh(Vector3(0.14, 0.14, 0.2), flash_mat)
		f.visible = false
		add_child(f)
		_flashes.append(f)
		_flash_t[i] = 0.0
	for _i in AUDIO_POOL:
		var p := AudioStreamPlayer3D.new()
		p.unit_size = SHOT_UNIT_SIZE
		p.max_distance = SHOT_MAX_DIST
		p.tree_exiting.connect(p.stop)  # audio law: no playing stream at quit
		add_child(p)
		_players.append(p)


func _show_tracer(from: Vector3, to: Vector3) -> void:
	var d := to - from
	var len := d.length()
	if len < 0.2: return
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
func _play(at: Vector3) -> void:
	if _shot_stream == null or _players.is_empty(): return
	var p := _players[_pool_i]
	_pool_i = (_pool_i + 1) % _players.size()
	if p == null or not is_instance_valid(p) or not p.is_inside_tree(): return
	p.global_position = at
	p.stream = _shot_stream
	p.volume_db = SHOT_DB
	p.pitch_scale = _rng.randf_range(0.94, 1.08)
	p.play()


func _exit_tree() -> void:
	for p in _players:
		if p != null and is_instance_valid(p):
			p.stop()


## Sidearm, snappier than the cruisers' duty pistol: fast crack, 150->55 Hz.
func _build_pistol_crack() -> AudioStreamWAV:
	var samples := PackedFloat32Array()
	samples.resize(5200)
	var phase := 0.0
	for i in samples.size():
		var t := float(i) / float(MIX_RATE)
		var crack := _rng.randf_range(-1.0, 1.0) * exp(-90.0 * t) * 0.85
		phase += TAU * lerpf(150.0, 55.0, clampf(t / 0.22, 0.0, 1.0)) / float(MIX_RATE)
		var thump := sin(phase) * exp(-15.0 * t) * 0.6
		samples[i] = (crack + thump) * minf(float(i) / 8.0, 1.0)  # ramp kills pop
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


# ============================== PLUMBING =====================================
func _has_officer_from(cruiser: RigidBody3D) -> bool:
	for o in _officers:
		var cr: Variant = o["cruiser"]
		if is_instance_valid(cr) and cr == cruiser: return true
	return false


func _find(body: Node) -> Dictionary:
	for o in _officers:
		if o["body"] == body: return o
	return {}


func _heat() -> int:
	var pol := _peer("police")
	if pol == null: return 0
	var h: Variant = pol.get("heat")
	return int(h) if h is int else 0


func _on_foot() -> bool:
	return main_ref != null and main_ref.get("on_foot") == true


func _player_down() -> bool:
	var of_peer := _peer("on_foot")
	return of_peer != null and of_peer.has_method("player_down") \
		and bool(of_peer.call("player_down"))


## The one the officers care about: ALWAYS main.player_actor() (character on
## foot, vehicle otherwise).
func _actor() -> Node3D:
	if main_ref != null and main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	var v: Variant = main_ref.get("vehicle") if main_ref != null else null
	return v if v is Node3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null


## Duck-typed actor velocity: rigid bodies and characters store it differently.
func _actor_velocity(a: Node3D) -> Vector3:
	if a is RigidBody3D: return (a as RigidBody3D).linear_velocity
	if a is CharacterBody3D: return (a as CharacterBody3D).velocity
	return Vector3.ZERO


func _shake(amount: float) -> void:
	var cam: Variant = main_ref.get("camera") if main_ref != null else null
	if cam is Object and is_instance_valid(cam) and (cam as Object).has_method("add_trauma"):
		(cam as Object).call("add_trauma", amount)


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n): return n
	return null


func _place(body: RigidBody3D, heading: Vector3, pos: Vector3) -> void:
	if heading.length_squared() < 0.0001: heading = Vector3.FORWARD
	body.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), pos)
