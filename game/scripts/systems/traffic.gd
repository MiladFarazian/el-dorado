extends Node
## TRAFFIC v1 — ambient civilian cars for downtown Dorado + the frontage roads.
## Frozen-kinematic RigidBody3D shells moved by transform each physics frame:
## they follow lanes offset 3.5 m RIGHT of the street centreline (forward = -Z,
## so northbound rides at centreline +X — right-hand traffic), brake for
## anything a 15 m ray sees, and turn along short arcs (never teleport-rotate).
## Contact with any dynamic body, a tow-hook, or the player closing fast inside
## 4 m unfreezes a car PERMANENTLY into towable debris. DISABLED in smoke mode.
##
## M17: they also STOP FOR THE LIGHTS. The phase is re-derived from the same
## literal rule city_dressing bakes the lit lens from (see _phase) — no accessor,
## no plumbing, nothing to desync. The player is never governed by any of this.

# ============================== TUNABLES =====================================
const RNG_SEED := 777; const TRAFFIC_COUNT := 10  # seed; frozen cars maintained
const SPAWN_RING := Vector2(70.0, 260.0)  # spawn ring around the player (m)
const SPAWN_INTERVAL := 0.4; const SPAWN_TRIES := 12  # s between; tries each
const SPAWN_CLEARANCE := 8.0; const GROUP_REFRESH := 0.5  # m clear; scan every s
const DESPAWN_FROZEN := 320.0        # frozen cars vanish beyond this (m)
const DESPAWN_DEBRIS := 200.0; const DEBRIS_MIN_AGE := 10.0  # m; min age s
const LANE_OFFSET := 3.5             # lane = centreline + right * this (m)
const SPEED_RANGE := Vector2(9.0, 13.0)  # per-car target speed (seeded, m/s)
const TURN_SPEED := 5.5; const APPROACH_DIST := 24.0  # arc cap; slow window
const ACCEL := 5.0; const DECEL := 9.0   # m/s^2: speed-up / smooth braking
const SENSE_LEN := 15.0; const DECIDE_DIST := 13.0  # obstacle ray; choice dist
const STOP_GAP := 4.0; const BRAKE_RANGE := 8.0  # stop gap / speed ramp span
const FOLLOW_RANGE := 14.0; const FOLLOW_STOP := 4.0  # M14 car-following window
const FOLLOW_LATERAL := 2.0          # lateral overlap that counts as same-lane
# -- M17 signals: the stop-bar model. Bar paint is at |18.6| from the centreline
# (city_dressing.BAR_OFF), so a shell holds with its BUMPER on the paint.
# C4 moved the paint from |13.6| to |18.6| when the crossing was relocated out
# of the intersection box; this number is the ONLY place traffic knows where the
# paint is, and it has to move with it or every shell stops 5 m past the bar,
# on top of the crossing it is stopping for.
const SIG_BAR := 18.6                # stop bar, |offset| from the centreline
const SIG_LOOK := 20.0               # bumper-to-bar distance a red is read at
const SIG_AMBER_LOOK := 11.0         # ... an amber is read late, so some run it
const SIG_AMBER_DECEL := 6.0         # "comfortable" braking for the amber call
const SIG_SNAP := 0.3                # inside this the hold is a dead stop
const SIG_CREEP := 1.0               # the wait clock only runs below this speed
const SIG_RED_DWELL := 6.0; const SIG_AMBER_DWELL := 2.2  # tier-2 watchdog (s)
const SIG_JITTER := 1.6              # per-car dwell spread (own rng, see below)
const SIG_HARD_RELEASE := 20.0       # tier-3 watchdog: unconditional release
const SIG_BOX_CLEAR := 14.0          # anything this near the box centre blocks
const SIG_APPROACH := 30.0           # ... and closers are judged out to here
const SIG_TTC := 2.5                 # closing time that counts as "coming"
const SIG_LANE_TOL := 2.5            # lateral: my own lane is follow's problem
const SIG_TOKEN_TTL := 8.0           # a crossing token nobody handed back
const SIG_RNG_SEED := 170817         # runtime jitter ONLY — never a spawn draw
const GRID_X0 := 193.0; const GRID_Z0 := 133.0; const GRID_PITCH := 86.0
const TURN_STRAIGHT := 0.6; const TURN_RIGHT := 0.2  # weights (rest = left)
const R_RIGHT := 4.5; const R_LEFT := 7.5; const R_UTURN := 3.5  # arc radii
const CRASH_DIST := 4.0; const CRASH_CLOSING := 5.0  # player proximity crash
const CRASH_LATERAL := 2.2           # path overlap needed (abreast pass ≠ crash)
const PAIR_CRASH := 2.6              # frozen cars this close = T-bone wreck
const SEDAN_SIZE := Vector3(1.9, 1.05, 4.4); const SEDAN_RIDE := 0.85
const TRUCK_SIZE := Vector3(2.15, 1.3, 5.2); const TRUCK_RIDE := 1.1  # lifted
const SEDAN_WHEEL := 0.32; const TRUCK_WHEEL := 0.44
const CAR_MASS := 1300.0; const TRUCK_MASS := 1750.0
const CAR_FRICTION := 0.3; const TRUCK_CHANCE := 0.12
const PALETTE: Array[Color] = [      # civilian whites and silvers
	Color(0.93, 0.93, 0.9), Color(0.87, 0.87, 0.85), Color(0.76, 0.77, 0.79),
	Color(0.64, 0.66, 0.69), Color(0.55, 0.57, 0.59)]
const TRUCK_COLOR := Color(0.07, 0.07, 0.08)  # the occasional black truck
# Streets per scripts/world/greybox_city.gd: N-S centrelines x = 193 + 86*i
# (i 0..6), E-W z = 133 + 86*j (j 0..4); frontage roads z=+30 east / -30 west.
const NS_Z := Vector2(47.0, 545.0); const EW_X := Vector2(107.0, 783.0)  # 545: U-turn apex clears the impound pad (z 553+)
const FR_Z := 30.0; const FR_X_END := 760.0
const CORRIDOR := Rect2(174.0, 424.0, 38.0, 152.0)  # protected: NEVER spawn in
# What a jacked shell turns into (carjack.gd reads the "jack_profile" meta).
# The black lifted truck IS the Baron Brisket — same joke, same rollover.
const SEDAN_PROFILE := "res://data/vehicles/sedan.json"
const TRUCK_PROFILE := "res://data/vehicles/brisket.json"
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
# M18: the signal schedule. Its GO/CAUTION/STOP codes ARE PH_GO/PH_CAUTION/
# PH_STOP below (0/1/2) — it returns straight into _signal_limit.
const SIGNAL_CYCLE := preload("res://scripts/systems/signal_cycle.gd")

enum { CRUISE, TURN }; enum { KIND_NS, KIND_EW, KIND_FRONTAGE }
enum { PH_GO, PH_CAUTION, PH_STOP }      # what the lens facing this shell says
enum { SG_NEW, SG_HOLD, SG_CLEARED }     # what this shell decided about it

# ============================== STATE ========================================
var main_ref: Node = null; var _tow: Node = null
var _rng := RandomNumberGenerator.new()
# Signal state. `_sig_rng` is a SEPARATE stream on its own literal seed: the
# seeded spawn stream (_rng) must keep its exact draw order, so runtime jitter
# never touches it. `signal_period` is 0 = the static baked phase; see _phase().
var _sig_rng := RandomNumberGenerator.new()
# M18: DEAD CLOCK. It drove the old two-state toggle; the live cycle is timed
# off Engine.get_physics_frames() instead, so every node in a tick reads one
# integer and the dressing cannot drift from the shells. Kept, not read.
var _sig_clock := 0.0
var _sig_token: Dictionary = {}          # intersection key -> {body, ttl}
var signal_period := 0.0                 # >0: half-cycle seconds (see _phase)
var _cars: Array[Dictionary] = []
var _ns_x: Array[float] = []; var _ew_z: Array[float] = []
var _spawn_cd := 0.0; var _cache_t := 0.0; var _spawned := 0
var _obstacle_pts := PackedVector3Array()
var _follow_obs: Array[Node3D] = []  # live follow targets, rebuilt every tick
var _sedan_mesh: BoxMesh; var _truck_mesh: BoxMesh
var _sedan_wheel: CylinderMesh; var _truck_wheel: CylinderMesh
var _mats: Array[StandardMaterial3D] = []; var _phys_mat: PhysicsMaterial
var _truck_mat: StandardMaterial3D; var _wheel_mat: StandardMaterial3D

func setup(main: Node) -> void:
	main_ref = main; _rng.seed = RNG_SEED; _sig_rng.seed = SIG_RNG_SEED
	if bool(main.get("smoke_mode")):
		set_physics_process(false); return  # smoke gate: no spawns/processing/UI
	for i in 7: _ns_x.append(193.0 + 86.0 * float(i))
	for j in 5: _ew_z.append(133.0 + 86.0 * float(j))
	_build_shared()

## One mesh/material set shared by every car — spawning never allocates meshes.
func _build_shared() -> void:
	_sedan_mesh = BoxMesh.new(); _sedan_mesh.size = SEDAN_SIZE
	_truck_mesh = BoxMesh.new(); _truck_mesh.size = TRUCK_SIZE
	_sedan_wheel = CylinderMesh.new(); _sedan_wheel.height = 0.24
	_sedan_wheel.top_radius = SEDAN_WHEEL; _sedan_wheel.bottom_radius = SEDAN_WHEEL
	_truck_wheel = CylinderMesh.new(); _truck_wheel.height = 0.32
	_truck_wheel.top_radius = TRUCK_WHEEL; _truck_wheel.bottom_radius = TRUCK_WHEEL
	for c in PALETTE:
		var m := StandardMaterial3D.new()
		m.albedo_color = c; m.roughness = 0.45; _mats.append(m)
	_truck_mat = StandardMaterial3D.new(); _truck_mat.albedo_color = TRUCK_COLOR
	_truck_mat.roughness = 0.35
	_wheel_mat = StandardMaterial3D.new(); _wheel_mat.albedo_color = Color(0.1, 0.1, 0.11)
	_phys_mat = PhysicsMaterial.new(); _phys_mat.friction = CAR_FRICTION

func _physics_process(delta: float) -> void:
	if main_ref == null: return
	_bind_tow()
	_sig_clock += delta; _sig_tick_tokens(delta)
	_cache_t -= delta
	if _cache_t <= 0.0: _cache_t = GROUP_REFRESH; _refresh_obstacles()  # 0.5 s cache
	var pv := _player()
	_refresh_follow(pv)
	_validate(pv, delta); _spawn_cd = maxf(_spawn_cd - delta, 0.0)
	if pv != null and _spawn_cd <= 0.0 and _frozen_count() < TRAFFIC_COUNT \
			and _try_spawn(pv.global_position):
		_spawn_cd = SPAWN_INTERVAL
	for car in _cars:
		if bool(car["frozen"]): _drive(car, delta, pv)
	_pair_crashes()

# ============================== POPULATION ===================================
func _validate(pv: RigidBody3D, delta: float) -> void:
	for i in range(_cars.size() - 1, -1, -1):
		var car := _cars[i]; var body := car["body"] as RigidBody3D
		if not is_instance_valid(body) or not body.is_inside_tree():
			_cars.remove_at(i); continue
		if not bool(car["frozen"]): car["age"] = float(car["age"]) + delta
		if pv == null: continue
		var d := body.global_position.distance_to(pv.global_position)
		if (d > DESPAWN_FROZEN) if bool(car["frozen"]) \
				else (float(car["age"]) > DEBRIS_MIN_AGE and d > DESPAWN_DEBRIS):
			body.queue_free(); _cars.remove_at(i)

func _frozen_count() -> int:
	var n := 0
	for car in _cars: n += 1 if bool(car["frozen"]) and is_instance_valid(car["body"]) else 0
	return n

## Seeded lane points: in the 70-260 m ring, never in the protected corridor,
## and 8 m clear of every towable/police (cached scan + live own cars).
func _try_spawn(ppos: Vector3) -> bool:
	for _a in SPAWN_TRIES:
		var pick := _rng.randi_range(0, 13)  # 7 N-S + 5 E-W + 2 frontage
		var kind: int; var center: float; var dirv: Vector3; var t: float
		if pick < 7:
			kind = KIND_NS; center = _ns_x[pick]
			dirv = Vector3(0, 0, -1.0 if _rng.randf() < 0.5 else 1.0)
			t = _rng.randf_range(NS_Z.x + 6.0, NS_Z.y - 6.0)
		elif pick < 12:
			kind = KIND_EW; center = _ew_z[pick - 7]
			dirv = Vector3(-1.0 if _rng.randf() < 0.5 else 1.0, 0, 0)
			t = _rng.randf_range(EW_X.x + 6.0, EW_X.y - 6.0)
		else:  # one-way frontage: z=+30 eastbound, z=-30 westbound
			kind = KIND_FRONTAGE; center = FR_Z if pick == 12 else -FR_Z
			dirv = Vector3(1, 0, 0) if pick == 12 else Vector3(-1, 0, 0)
			t = _rng.randf_range(20.0 - FR_X_END, FR_X_END - 20.0)
		# Frontage lanes ride the inner (freeway) side of the strip so they
		# clear repo_board's curb-parked junkers at z=33; grid streets keep the
		# standard right-hand offset.
		var lane := _right(dirv) * (LANE_OFFSET if kind != KIND_FRONTAGE else -LANE_OFFSET)
		var pos := Vector3(center + lane.x, 0.0, t) if kind == KIND_NS \
			else Vector3(t, 0.0, center + lane.z)
		var d := Vector2(pos.x - ppos.x, pos.z - ppos.z).length()
		if d < SPAWN_RING.x or d > SPAWN_RING.y: continue
		if CORRIDOR.has_point(Vector2(pos.x, pos.z)): continue
		if not _clear_at(pos): continue
		_make_car(pos, dirv, kind, center); return true
	return false

func _clear_at(pos: Vector3) -> bool:
	for p in _obstacle_pts:
		if Vector2(pos.x - p.x, pos.z - p.z).length() < SPAWN_CLEARANCE: return false
	for car in _cars:  # own cars move fast; check them live, not via the cache
		var b := car["body"] as RigidBody3D
		if is_instance_valid(b) and Vector2(pos.x - b.global_position.x,
				pos.z - b.global_position.z).length() < SPAWN_CLEARANCE: return false
	return true

func _refresh_obstacles() -> void:
	_obstacle_pts.clear()
	for g: String in ["towable", "police"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n is Node3D and is_instance_valid(n): _obstacle_pts.append((n as Node3D).global_position)

func _make_car(pos: Vector3, dirv: Vector3, kind: int, center: float) -> void:
	var truck := _rng.randf() < TRUCK_CHANCE
	var size := TRUCK_SIZE if truck else SEDAN_SIZE
	var ride := TRUCK_RIDE if truck else SEDAN_RIDE  # lifted trucks sit higher
	var body := RigidBody3D.new()
	_spawned += 1; body.name = "Traffic%d" % _spawned
	body.mass = TRUCK_MASS if truck else CAR_MASS
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC; body.freeze = true
	body.physics_material_override = _phys_mat
	# 8, not 2: speculative contacts with the road slab exhaust a budget of 2
	# and dynamic-body contacts then never report (review-verified in 4.7.1).
	body.contact_monitor = true; body.max_contacts_reported = 8
	body.add_to_group("civilian"); body.add_to_group("towable")
	body.set_meta("jack_profile", TRUCK_PROFILE if truck else SEDAN_PROFILE)
	var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = size; col.shape = shape; body.add_child(col)
	# M9: styled silhouettes via the shared body builder (visual-only; the
	# collision box and this function's rng draw order are unchanged).
	var vis := Node3D.new(); body.add_child(vis)
	var paint: Color = TRUCK_COLOR if truck \
		else PALETTE[_rng.randi_range(0, PALETTE.size() - 1)]  # SAME draw as before
	BODY_BUILDER.build(vis, "pickup" if truck else "sedan", size, paint)
	var radius := TRUCK_WHEEL if truck else SEDAN_WHEEL; var zoff := size.z * 0.5 - radius - 0.7
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new(); w.mesh = _truck_wheel if truck else _sedan_wheel
		w.material_override = _wheel_mat; w.rotation_degrees = Vector3(0, 0, 90)
		# M19: was `+ 0.02` — a track WIDER than the car, so every ambient shell's
		# tyres stood ~235 mm proud of the flank and the body-builder had to flare
		# 120-180 mm of fender to cover them. Tuck the hub inboard instead.
		w.position = Vector3(c.x * (size.x * 0.5 - 0.075), radius - ride, c.y * zoff)
		body.add_child(w)
	add_child(body)  # Node3D under a plain Node: transform acts as global
	_place(body, dirv, Vector3(pos.x, ride, pos.z)); body.body_entered.connect(_on_contact.bind(body))
	var car := {
		"body": body, "frozen": true, "state": CRUISE, "dir": dirv, "kind": kind,
		"center": center, "ride": ride, "half_len": size.z * 0.5, "age": 0.0,
		"tspeed": _rng.randf_range(SPEED_RANGE.x, SPEED_RANGE.y), "speed": 0.0,
		"choice": 0, "decided": false, "event": 0.0, "event_end": false,
		"arc_c": Vector3.ZERO, "arc_u": Vector3.ZERO, "arc_sweep": 0.0, "arc_sgn": 1.0,
		"arc_r": 1.0, "exit_dir": dirv, "exit_center": center, "exit_kind": kind,
		# Signal state. sig_jit comes off the SEPARATE runtime stream so the
		# seeded spawn draws above stay in their frozen order.
		"sig_key": -1, "sig_mode": SG_NEW, "sig_wait": 0.0,
		"sig_jit": _sig_rng.randf() * SIG_JITTER}
	car["speed"] = float(car["tspeed"])
	_cars.append(car); _plan_next(car)

# ============================== LANE DRIVING =================================
## Next event along travel: nearest perpendicular crossing beyond DECIDE_DIST,
## else the street end (grid ends U-turn; frontage ends despawn at map edge).
func _plan_next(car: Dictionary) -> void:
	var body := car["body"] as RigidBody3D
	_sig_forget(car)  # the old intersection is behind us: drop its hold + token
	if not is_instance_valid(body): return
	var dirv := car["dir"] as Vector3
	var s := dirv.x + dirv.z  # +1 toward +axis, -1 toward -axis
	var t := _travel_coord(car, body)
	car["decided"] = false; car["choice"] = 0; car["event_end"] = true
	var kind := int(car["kind"])
	if kind == KIND_FRONTAGE:
		car["event"] = s * FR_X_END; return
	var bounds := NS_Z if kind == KIND_NS else EW_X
	car["event"] = bounds.y if s > 0.0 else bounds.x
	var best := INF
	for c in (_ew_z if kind == KIND_NS else _ns_x):
		var d := (c - t) * s
		if d > DECIDE_DIST and d < best:
			best = d; car["event"] = c; car["event_end"] = false

func _travel_coord(car: Dictionary, body: RigidBody3D) -> float:
	return body.global_position.z if int(car["kind"]) == KIND_NS else body.global_position.x

func _drive(car: Dictionary, delta: float, pv: RigidBody3D) -> void:
	var body := car["body"] as RigidBody3D
	if not is_instance_valid(body) or not body.is_inside_tree(): return
	var turning := int(car["state"]) == TURN
	var heading: Vector3 = (car["arc_u"] as Vector3).rotated(
		Vector3.UP, float(car["arc_sgn"]) * PI * 0.5) if turning else car["dir"] as Vector3
	# Fast player closing inside 4 m: unfreeze BEFORE impact so the hit lands
	# on loose physics, not an immovable kinematic wall.
	if pv != null:
		var sep := body.global_position - pv.global_position; var d := sep.length()
		var lat := (sep - heading * sep.dot(heading)).length()  # drive-bys stay frozen
		if d < CRASH_DIST and d > 0.01 and lat < CRASH_LATERAL and (pv.linear_velocity
				- heading * float(car["speed"])).dot(sep / d) > CRASH_CLOSING:
			_unfreeze(car); return
	var limit := _sense_limit(car, body, heading)
	limit = minf(limit, _follow_limit(car, body, heading))
	if turning:
		_set_speed(car, minf(limit, TURN_SPEED), delta); _step_turn(car, body, delta); return
	var dirv := car["dir"] as Vector3
	var rem := (float(car["event"]) - _travel_coord(car, body)) * (dirv.x + dirv.z)  # dist to event
	if bool(car["event_end"]):
		if rem < APPROACH_DIST: limit = minf(limit, TURN_SPEED)
		if rem <= 0.0:
			if int(car["kind"]) == KIND_FRONTAGE:
				body.queue_free()  # one-way road meets the map edge: retire
			else:
				_start_turn(car, body, 3, limit, delta)  # dead-end U-turn
			return
	else:
		limit = minf(limit, _signal_limit(car, rem, delta))  # M17: the light
		if not bool(car["decided"]) and rem <= DECIDE_DIST:
			car["decided"] = true
			var roll := _rng.randf()  # seeded: straight 60 / right 20 / left 20
			car["choice"] = 0 if roll < TURN_STRAIGHT \
				else (1 if roll < TURN_STRAIGHT + TURN_RIGHT else 2)
		var choice := int(car["choice"])
		if bool(car["decided"]) and choice > 0:
			if rem < APPROACH_DIST: limit = minf(limit, TURN_SPEED)
			if rem <= ((LANE_OFFSET + R_RIGHT) if choice == 1 else (R_LEFT - LANE_OFFSET)):
				_start_turn(car, body, choice, limit, delta); return
		elif bool(car["decided"]) and rem <= -2.0:
			_plan_next(car)  # cleared the intersection going straight
	_set_speed(car, limit, delta)
	var pos := body.global_position + dirv * float(car["speed"]) * delta
	pos.y = float(car["ride"]); _place(body, dirv, pos)

## ONE bumper-height ray per car per frame (10 cars = 10 rays, the whole
## budget); hit distance maps to a limit: 0 at STOP_GAP, full at +8 m.
func _sense_limit(car: Dictionary, body: RigidBody3D, heading: Vector3) -> float:
	var from := body.global_position + heading * (float(car["half_len"]) + 0.3)
	var q := PhysicsRayQueryParameters3D.create(from, from + heading * SENSE_LEN)
	q.exclude = [body.get_rid()]
	var hit := body.get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty(): return float(car["tspeed"])
	var d: float = from.distance_to(hit["position"])
	return float(car["tspeed"]) * clampf((d - STOP_GAP) / BRAKE_RANGE, 0.0, 1.0)

## M14 CAR-FOLLOWING: the thin sense ray misses laterally-offset leaders, so
## each shell also does pure distance math against every body that could be
## ahead in its lane — the roster, the player vehicle, and "drivable"/"police"
## — and ramps its lane speed to 0 as the bumper gap closes FOLLOW_RANGE ->
## FOLLOW_STOP, resuming when clear. Zero raycasts, zero rng draws (the seeded
## spawn streams are untouched); target refs are gathered ONCE per tick.
func _refresh_follow(pv: RigidBody3D) -> void:
	_follow_obs.clear()
	if pv != null: _follow_obs.append(pv)
	for g: String in ["drivable", "police"]:
		for n: Node in get_tree().get_nodes_in_group(g):
			if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
				_follow_obs.append(n as Node3D)

func _follow_limit(car: Dictionary, body: RigidBody3D, heading: Vector3) -> float:
	var pos := body.global_position
	var half := float(car["half_len"])
	var best := INF
	for other in _cars:
		var ob := other["body"] as RigidBody3D
		if ob != body and is_instance_valid(ob) and ob.is_inside_tree():
			best = minf(best, _gap_ahead(pos, heading, ob.global_position, half))
	for n in _follow_obs:
		if n != body and is_instance_valid(n):
			best = minf(best, _gap_ahead(pos, heading, n.global_position, half))
	if best >= FOLLOW_RANGE: return float(car["tspeed"])
	return _gap_speed(car, best)


## THE deceleration curve: lane speed ramps linearly 0 -> target as a gap opens
## FOLLOW_STOP -> FOLLOW_RANGE. Car-following feeds it a bumper gap; the signal
## code feeds it the stop bar (gap = bar + FOLLOW_STOP, so limit hits 0 exactly
## on the paint) — one curve, so stopping for a light and stopping for a bumper
## are the same motion. _set_speed's DECEL clamp keeps it from ever snapping.
func _gap_speed(car: Dictionary, gap: float) -> float:
	return float(car["tspeed"]) \
		* clampf((gap - FOLLOW_STOP) / (FOLLOW_RANGE - FOLLOW_STOP), 0.0, 1.0)

## Bumper gap to a body AHEAD in this car's lane, INF when it is no obstacle
## (behind, beside, or beyond the window). Planar math, own half-length off.
func _gap_ahead(pos: Vector3, heading: Vector3, op: Vector3, half: float) -> float:
	var to := op - pos; to.y = 0.0
	var ahead := to.dot(heading)
	if ahead <= 0.3: return INF  # behind or on top of us: not a follow target
	if (to - heading * ahead).length() > FOLLOW_LATERAL: return INF
	var gap := maxf(ahead - half, 0.0)
	return gap if gap <= FOLLOW_RANGE else INF

# ============================== TRAFFIC SIGNALS ==============================
## THE BAKED PHASE, RE-DERIVED — NOT READ. city_dressing decides which lens is
## lit at build time from a pure function of the intersection indices:
##   ns_green = (xi + zi) % 2 == 0            (_traffic_signals, M8)
##   east-west takes the complement, and shows AMBER instead of green on one
##   intersection in three where north-south is red: (xi + zi) % 3 == 0
##   (_row_intersections, M16 — which added the missing east-west heads).
## Repeating that literal here beats an accessor: there is no call, no ordering
## dependency, and no way for the cars and the glass to disagree.
##
## `signal_period` is the seam, and M18 CLOSED IT: signal_cycle.gd sets it to
## the half-cycle length (green + amber + clearance) the moment it takes over
## the glass, and from then on both sides read the SAME pure functions — the
## dressing precomputes its lens buffers from them at build time and this
## function calls them per shell. There is one literal, not two to drift apart,
## which is the same guarantee the M17 duplication bought at a six-stage
## schedule where duplication would have been a bad bet.
##
## At signal_period 0.0 (signal_cycle.gd absent or not yet bound) this returns
## the M17 STATIC baked phase verbatim, and the tier-2/tier-3 watchdogs in
## _signal_limit are the working release path — downtown drives like a grid of
## four-way stops, exactly as it did before M18.
func _phase(kind: int, xi: int, zi: int) -> int:
	if kind == KIND_FRONTAGE: return PH_GO
	if signal_period > 0.0:
		return int(SIGNAL_CYCLE.phase(kind == KIND_NS, xi, zi, signal_period))
	var ns_green := (xi + zi) % 2 == 0
	if kind == KIND_NS: return PH_GO if ns_green else PH_STOP
	if ns_green: return PH_STOP
	return PH_CAUTION if (xi + zi) % 3 == 0 else PH_GO


## Grid indices of the crossing this shell is approaching, or (-1,-1) when it is
## not approaching a signalled downtown intersection (frontage road, or the
## planned event is a street end rather than a crossing).
func _sig_index(car: Dictionary) -> Vector2i:
	if int(car["kind"]) == KIND_FRONTAGE or bool(car["event_end"]):
		return Vector2i(-1, -1)
	var ns := int(car["kind"]) == KIND_NS
	var xi := _grid_i(float(car["center"]) if ns else float(car["event"]), GRID_X0)
	var zi := _grid_i(float(car["event"]) if ns else float(car["center"]), GRID_Z0)
	if xi < 0 or xi >= _ns_x.size() or zi < 0 or zi >= _ew_z.size():
		return Vector2i(-1, -1)
	return Vector2i(xi, zi)


func _grid_i(c: float, c0: float) -> int:
	var i := int(roundf((c - c0) / GRID_PITCH))
	return i if absf(c - (c0 + GRID_PITCH * float(i))) < 0.5 else -1


## THE LIGHT. INF when this shell has no reason to care; otherwise the lane
## ceiling that walks it down onto the stop bar with _gap_speed. Three release
## paths, most honest first:
##   1. the phase goes green — the real one, live whenever signal_period > 0;
##   2. tier-2 watchdog: waited out the dwell AND holds the crossing token AND
##      nothing is in or closing on the box. A jammed light becomes a four-way
##      stop, one shell at a time — which is why released shells do not T-bone;
##   3. tier-3 watchdog: waited SIG_HARD_RELEASE, go regardless of everything.
##      Unconditional, so "parked on a stop bar forever" is not reachable.
## Committing (SG_CLEARED) is also how the shell refuses a hard stop it cannot
## physically make: if the required braking exceeds the honest decel it clears
## the box instead of teleport-stopping.
func _signal_limit(car: Dictionary, rem: float, delta: float) -> float:
	var idx := _sig_index(car)
	if idx.x < 0:
		_sig_forget(car); return INF
	var key := idx.x * 8 + idx.y
	if int(car["sig_key"]) != key:
		_sig_forget(car); car["sig_key"] = key
	if int(car["sig_mode"]) == SG_CLEARED: return INF
	var bar := rem - float(car["half_len"]) - SIG_BAR  # bumper -> the paint
	var ph := _phase(int(car["kind"]), idx.x, idx.y)
	var sp := float(car["speed"])
	if int(car["sig_mode"]) == SG_NEW:
		if ph == PH_GO: return INF          # stays undecided; re-read next frame
		if bar > (SIG_AMBER_LOOK if ph == PH_CAUTION else SIG_LOOK): return INF
		var brake := SIG_AMBER_DECEL if ph == PH_CAUTION else DECEL
		if sp * sp > 2.0 * brake * maxf(bar, 0.0):
			car["sig_mode"] = SG_CLEARED; return INF   # too late: clear the box
		car["sig_mode"] = SG_HOLD; car["sig_wait"] = 0.0
	if ph == PH_GO:
		car["sig_mode"] = SG_CLEARED; return INF       # it turned green: go
	if sp < SIG_CREEP: car["sig_wait"] = float(car["sig_wait"]) + delta
	var wait := float(car["sig_wait"])
	var slack := _sig_slack()
	var dwell := (SIG_AMBER_DWELL if ph == PH_CAUTION else SIG_RED_DWELL) \
		+ float(car["sig_jit"]) + slack
	if wait >= SIG_HARD_RELEASE + slack \
			or (wait >= dwell and _sig_may_enter(car, idx, key)):
		car["sig_mode"] = SG_CLEARED
		_sig_token[key] = {"body": car["body"], "ttl": SIG_TOKEN_TTL}
		return INF
	if bar <= SIG_SNAP: return 0.0          # on the paint: hold a dead stop
	return _gap_speed(car, bar + FOLLOW_STOP)


## M18 — THE WATCHDOGS ARE A NET, NOT A RELEASE PATH. They were sized against a
## signal that never changed: 6 s of dwell and a 20 s hard release are exactly
## right for a jammed light, and exactly WRONG once the light cycles, because a
## healthy red legitimately holds a shell for the whole cycle minus its own
## green (25 s at the shipped 15/3/2 timings) — every shell would have run
## every red a few seconds in and the lenses would have meant nothing. So the
## live cycle's own red length is added to all three timers. Returns 0.0 at
## signal_period 0.0, i.e. the M17 static diorama keeps the M17 numbers
## verbatim, and "parked on a stop bar forever" stays unreachable either way.
func _sig_slack() -> float:
	if signal_period <= 0.0: return 0.0
	return 2.0 * signal_period - float(SIGNAL_CYCLE.green_len(signal_period))


## Tier-2 gate. One shell per intersection may hold the crossing token, and the
## box plus everything closing on it must be clear. Own-lane bodies are skipped
## on purpose — a queue behind me is car-following's job, not a conflict. Only
## runs for shells that have already waited out their dwell, so it is rare.
func _sig_may_enter(car: Dictionary, idx: Vector2i, key: int) -> bool:
	if not is_instance_valid(car["body"]): return false   # valid BEFORE the cast
	var body := car["body"] as RigidBody3D
	var held: Variant = (_sig_token.get(key, {}) as Dictionary).get("body")
	if is_instance_valid(held) and held is Node and held != body: return false
	var ic := Vector3(_ns_x[idx.x], 0.0, _ew_z[idx.y])
	var heading := car["dir"] as Vector3
	var pos := body.global_position
	for other in _cars:
		if not is_instance_valid(other["body"]): continue
		var ob := other["body"] as RigidBody3D
		if ob == body or not ob.is_inside_tree(): continue
		var vel := ob.linear_velocity
		if bool(other["frozen"]):
			vel = (other["dir"] as Vector3) * float(other["speed"])
		if _sig_conflict(pos, heading, ic, ob.global_position, vel): return false
	for n in _follow_obs:
		if n == body or not is_instance_valid(n): continue
		if _sig_conflict(pos, heading, ic, n.global_position, _sig_vel(n)): return false
	return true


## Is `op` (moving at `vel`) a reason not to enter the box centred on `ic`?
## Anything already inside SIG_BOX_CLEAR is; anything further out counts only
## while it is genuinely bearing down on the box inside SIG_TTC seconds.
func _sig_conflict(pos: Vector3, heading: Vector3, ic: Vector3, op: Vector3,
		vel: Vector3) -> bool:
	var to := ic - op; to.y = 0.0
	var d := to.length()
	if d > SIG_APPROACH: return false
	var rel := op - pos; rel.y = 0.0
	if (rel - heading * rel.dot(heading)).length() <= SIG_LANE_TOL: return false
	if d < SIG_BOX_CLEAR: return true
	if d <= 0.01: return true
	var closing := (to / d).dot(Vector3(vel.x, 0.0, vel.z))
	return closing > 2.0 and d < closing * SIG_TTC


## Duck-typed velocity: RigidBody3D vehicles vs CharacterBody3D actors (the
## house rule — the player on foot is a character, in a car it is a rigid body).
func _sig_vel(n: Node3D) -> Vector3:
	if n is RigidBody3D: return (n as RigidBody3D).linear_velocity
	if n is CharacterBody3D: return (n as CharacterBody3D).velocity
	return Vector3.ZERO


## Drop this shell's hold on whatever intersection it was watching, handing the
## crossing token back so the next shell in the queue can take its turn.
func _sig_forget(car: Dictionary) -> void:
	if int(car["sig_key"]) == -1 and int(car["sig_mode"]) == SG_NEW: return
	_sig_drop_token(car["body"] as Node)
	car["sig_key"] = -1; car["sig_mode"] = SG_NEW; car["sig_wait"] = 0.0


func _sig_drop_token(body: Node) -> void:
	if body == null: return
	for k: int in _sig_token.keys():
		if (_sig_token[k] as Dictionary).get("body") == body: _sig_token.erase(k)


## Tokens expire on their own: a holder that gets wrecked, jacked or despawned
## mid-crossing must not lock its intersection for the rest of the session.
func _sig_tick_tokens(delta: float) -> void:
	for k: int in _sig_token.keys():
		var e := _sig_token[k] as Dictionary
		e["ttl"] = float(e["ttl"]) - delta
		var b: Variant = e.get("body")
		if float(e["ttl"]) <= 0.0 or not (b is Node and is_instance_valid(b)):
			_sig_token.erase(k)


func _set_speed(car: Dictionary, limit: float, delta: float) -> void:
	var sp := float(car["speed"])
	car["speed"] = move_toward(sp, limit, (ACCEL if limit > sp else DECEL) * delta)

## Arc setup + first step. Right-turn trigger at remaining = 3.5 + r lands the
## exit exactly on the crossing street's right lane; left trigger r - 3.5
## sweeps to the far lane; U-turn (3) = 180-degree left arc at a dead end.
func _start_turn(car: Dictionary, body: RigidBody3D, turn: int, limit: float, delta: float) -> void:
	var h := _cardinal(car["dir"] as Vector3); var pos := body.global_position
	var r := R_RIGHT if turn == 1 else (R_LEFT if turn == 2 else R_UTURN)
	if turn == 1:  # clockwise, centre to the car's right
		car["arc_sgn"] = -1.0; car["arc_c"] = pos + _right(h) * r
		car["arc_u"] = _left(h); car["exit_dir"] = _right(h)
	else:  # left turn and U-turn: counterclockwise, centre to the left
		car["arc_sgn"] = 1.0; car["arc_c"] = pos + _left(h) * r
		car["arc_u"] = _right(h); car["exit_dir"] = _left(h) if turn == 2 else -h
	car["arc_r"] = r; car["arc_sweep"] = PI if turn == 3 else PI * 0.5
	if turn == 3:
		car["exit_kind"] = int(car["kind"]); car["exit_center"] = float(car["center"])
	else:
		car["exit_kind"] = KIND_EW if int(car["kind"]) == KIND_NS else KIND_NS
		car["exit_center"] = float(car["event"])
	car["state"] = TURN
	_set_speed(car, minf(limit, TURN_SPEED), delta); _step_turn(car, body, delta)

func _step_turn(car: Dictionary, body: RigidBody3D, delta: float) -> void:
	var r := float(car["arc_r"])
	var d_ang := minf(float(car["speed"]) * delta / r, float(car["arc_sweep"]))
	var u := (car["arc_u"] as Vector3).rotated(Vector3.UP, float(car["arc_sgn"]) * d_ang)
	car["arc_u"] = u; car["arc_sweep"] = float(car["arc_sweep"]) - d_ang
	var pos := (car["arc_c"] as Vector3) + u * r; pos.y = float(car["ride"])
	_place(body, u.rotated(Vector3.UP, float(car["arc_sgn"]) * PI * 0.5), pos)
	if float(car["arc_sweep"]) <= 0.0005: _finish_turn(car, body)

func _finish_turn(car: Dictionary, body: RigidBody3D) -> void:
	var dirv := _cardinal(car["exit_dir"] as Vector3)
	car["dir"] = dirv; car["kind"] = int(car["exit_kind"])
	car["center"] = float(car["exit_center"]); car["state"] = CRUISE
	var lane := _right(dirv) * LANE_OFFSET  # snap exactly onto the exit lane
	var pos := body.global_position
	if int(car["kind"]) == KIND_NS: pos.x = float(car["center"]) + lane.x
	else: pos.z = float(car["center"]) + lane.z
	pos.y = float(car["ride"]); _place(body, dirv, pos); _plan_next(car)

# ============================== CARJACK HANDOFF ==============================
## PUBLIC (carjack): the player is taking this shell. Drop it from the roster
## WITHOUT freeing it — the thief frees it after reading its transform — and
## report the lane speed it was doing, so the real vehicle that replaces it
## inherits the motion instead of materialising at a dead stop in traffic.
## Returns 0.0 for anything we do not own (or crashed debris, whose real
## linear_velocity the caller should read off the body instead).
func release_car(body: Node) -> float:
	for i in _cars.size():
		if _cars[i]["body"] != body:
			continue
		var sp := float(_cars[i]["speed"]) if bool(_cars[i]["frozen"]) else 0.0
		_sig_drop_token(body)  # it leaves the roster mid-crossing: free the box
		_cars.remove_at(i)
		return sp
	return 0.0

# ============================== CRASH HANDOFF ================================
## Permanent handoff to loose physics: keeps momentum, stays towable forever.
func _unfreeze(car: Dictionary) -> void:
	if not bool(car["frozen"]): return
	car["frozen"] = false; car["age"] = 0.0; var body := car["body"] as RigidBody3D
	if is_instance_valid(body):
		body.freeze = false  # keeps momentum along its current heading:
		body.linear_velocity = -body.global_transform.basis.z * float(car["speed"])

## Static world is NOT a crash: the engine reports speculative contacts with
## the road slab cars float over — that would instantly wreck the whole fleet.
func _on_contact(other: Node, body: Node) -> void:
	if other is StaticBody3D: return
	var car := _find(body)
	if not car.is_empty() and bool(car["frozen"]): _unfreeze(car)

## Kinematic-kinematic contacts are not reliably reported by the solver:
## intersection T-bones between frozen cars get an explicit centre check.
func _pair_crashes() -> void:
	for i in _cars.size():
		for j in range(i + 1, _cars.size()):
			var ca := _cars[i]; var cb := _cars[j]
			if not (bool(ca["frozen"]) and bool(cb["frozen"])): continue
			var a := ca["body"] as RigidBody3D; var b := cb["body"] as RigidBody3D
			if is_instance_valid(a) and is_instance_valid(b) \
					and a.global_position.distance_to(b.global_position) < PAIR_CRASH:
				_unfreeze(ca); _unfreeze(cb)

func _on_hooked(body: Node) -> void:
	var car := _find(body)
	if car.is_empty() or not bool(car["frozen"]): return
	_unfreeze(car)  # once per event: no longer frozen afterwards
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"): pol.call("add_heat", 1, "GRAND THEFT AUTO")  # car theft

# ============================== PLUMBING =====================================
func _bind_tow() -> void:
	if _tow != null and is_instance_valid(_tow): return
	_tow = _peer("tow_hook")
	if _tow != null and _tow.has_signal("hooked") and not _tow.is_connected("hooked", _on_hooked):
		_tow.connect("hooked", _on_hooked)

func _find(body: Node) -> Dictionary:
	for car in _cars:
		if car["body"] == body: return car
	return {}

func _player() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle") if main_ref != null else null
	return v if v is RigidBody3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null

func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n): return n
	return null

func _place(body: RigidBody3D, heading: Vector3, pos: Vector3) -> void:
	body.global_transform = Transform3D(Basis.looking_at(heading, Vector3.UP), pos)

# Exact cardinal helpers (algebraic, no trig drift). Forward = -Z: north
# (0,0,-1) -> right (1,0,0) east, so lanes sit right of travel. Verified.
func _right(d: Vector3) -> Vector3: return Vector3(-d.z, 0.0, d.x)

func _left(d: Vector3) -> Vector3: return Vector3(d.z, 0.0, -d.x)

func _cardinal(v: Vector3) -> Vector3:
	return Vector3(roundf(v.x), 0.0, roundf(v.z)).normalized()
