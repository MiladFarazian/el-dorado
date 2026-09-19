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
##
## AND THEY DRIVE THE REST OF THE COUNTY. Four lane kinds now: the downtown grid
## (KIND_NS/KIND_EW), I-3's frontage roads (KIND_FRONTAGE) and KIND_SPUR — any
## "street" polyline in the atlas, which is how Juárez Boulevard, Pioneer Vision
## Parkway and the Cedar Cliff streets got traffic without a line of geometry
## being hard-coded here. See the SPURS section at the bottom.

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
# -- SPURS: ambient traffic on the atlas's non-grid "street" polylines. Juárez
# Boulevard, Pioneer Vision Parkway and the Cedar Cliff streets are real roads
# with nobody on them; a spur is one of those polylines driven exactly the way
# the grid is — 3.5 m right of the centreline (so one polyline carries BOTH
# directions), the existing arcs at the corners, and a U-turn at each end unless
# the end meets a grid lane it can merge straight onto. A corner is never a
# signal. Tunables live in data/mechanics/traffic_spurs.json; these are the
# fallbacks used when that file is missing or a key is absent.
const SPURS_PATH := "res://data/mechanics/traffic_spurs.json"
const ATLAS_PATH := "res://data/world/atlas.json"   # optional: no file, no spurs
const SPUR_CAP := 3                  # frozen cars per spur (TRAFFIC_COUNT still rules)
const SPUR_MIN_LEN := 120.0          # an 8 m drive or a 66 m stub gets no traffic
const SPUR_CORNER_CLEAR := 12.0      # never spawn this near a polyline vertex
const SPUR_JOIN := 30.0              # a spur end this near a grid lane end merges
const SPUR_JOIN_LAT := 1.5           # ... and this close to that lane, laterally
const SPUR_GIVEUP := 9.0             # stopped this long out here: give up, U-turn
const SPUR_UTURN_CREEP := 1.5        # ... and a U-turn always sweeps, blocked or not
const SPUR_AXIS_TOL := 0.01          # a spur segment must be axis-aligned
const SPUR_RNG_SEED := 990413        # spur spawns ONLY — never a seeded grid draw
# -- GIVE-WAY AT SPUR CROSSINGS. Two atlas polylines that cross have no signal,
# no stop sign and no priority rule, so on the shipped atlas four unsignalled
# crossroads (Cliff side west/east against both Juárez Boulevard and the Cliff
# back street) were settled by whoever got there first and, when that tied, by
# the give-up timer nine seconds later. The rule: the SHORTER polyline yields.
# It is arbitrary, it is stable, and it reads on screen as a side street waiting
# for a boulevard. The give-up timer stays exactly where it was, as the backstop.
const XING_YIELD := 12.0             # a yielder watches inside this of the crossing
const XING_WATCH := 18.0             # ... for a car on the longer road this near it
const XING_CLOSING := 0.5            # and actually pointing at it (unit dot)
# -- ADOPTION (repo orders). A body the brain did NOT spawn, driven as a shell.
const ADOPT_RANGE := 40.0            # no lane centreline this close: no adoption
const ADOPT_RNG_SEED := 0xD06213     # foreign shells ONLY — never a grid draw
const FLEE_SPEED := Vector2(15.0, 18.0)  # a runner's target speed (m/s)
const FLEE_STRAIGHT := 0.8; const FLEE_RIGHT := 0.1  # straight 80 / right 10 / left 10
const ADOPT_STUCK := 0.5             # under this counts as stopped for stuck_for()
const ADOPT_OFF_LANE := 6.0          # this far off the lane centreline ...
const ADOPT_OFF_HOLD := 3.0          # ... for this long: hand it back to the owner
const ADOPT_MERGE := 3.0             # lateral m/s onto the lane (no teleport)
# What a jacked shell turns into (carjack.gd reads the "jack_profile" meta).
# The black lifted truck IS the Baron Brisket — same joke, same rollover.
const SEDAN_PROFILE := "res://data/vehicles/sedan.json"
const TRUCK_PROFILE := "res://data/vehicles/brisket.json"
const BODY_BUILDER := preload("res://scripts/vehicle/vehicle_body_builder.gd")
# M18: the signal schedule. Its GO/CAUTION/STOP codes ARE PH_GO/PH_CAUTION/
# PH_STOP below (0/1/2) — it returns straight into _signal_limit.
const SIGNAL_CYCLE := preload("res://scripts/systems/signal_cycle.gd")

enum { CRUISE, TURN }; enum { KIND_NS, KIND_EW, KIND_FRONTAGE, KIND_SPUR }
# What a spur car does at the far end of its current segment.
enum { SP_JOIN, SP_RIGHT, SP_LEFT, SP_UTURN, SP_STRAIGHT }  # 1/2/3 == _start_turn's codes
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
# Spur state. `_spur_rng` is a THIRD stream on its own literal seed for the same
# reason `_sig_rng` is a second one: the seeded grid spawn stream (_rng) must
# keep its exact draw order, so no spur draw may ever touch it.
var _spur_rng := RandomNumberGenerator.new()
var _spurs: Array[Dictionary] = []   # polyline routes read from the atlas
# spur index -> Array of {pos: Vector3, other: int}: the crossings where THIS
# spur is the shorter polyline and therefore the one that gives way.
var _yield_at: Dictionary = {}
# A FOURTH stream, same reason as the second and third: a body the brain adopts
# draws its speed and its turn choices from here, so a repo order driving past
# can never shift a single number in the seeded grid stream.
var _adopt_rng := RandomNumberGenerator.new()
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
	_spur_rng.seed = SPUR_RNG_SEED; _adopt_rng.seed = ADOPT_RNG_SEED
	if bool(main.get("smoke_mode")):
		set_physics_process(false); return  # smoke gate: no spawns/processing/UI
	for i in 7: _ns_x.append(193.0 + 86.0 * float(i))
	for j in 5: _ew_z.append(133.0 + 86.0 * float(j))
	_build_shared(); _load_spurs(); _build_crossings()

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
	# The grid is tried FIRST and unconditionally — its 12 tries draw the same
	# seeded numbers in the same order they always have. Spurs only get the slot
	# the grid could not fill (out in Cedar Cliff every grid lane is out of ring),
	# so downtown density and the seeded stream are both exactly as before.
	if pv != null and _spawn_cd <= 0.0 and _frozen_count() < TRAFFIC_COUNT \
			and (_try_spawn(pv.global_position) or _try_spawn_spur(pv.global_position)):
		_spawn_cd = SPAWN_INTERVAL
	for car in _cars:
		if bool(car["frozen"]): _drive(car, delta, pv)
	_pair_crashes()

# ============================== POPULATION ===================================
func _validate(pv: RigidBody3D, delta: float) -> void:
	for i in range(_cars.size() - 1, -1, -1):
		var car := _cars[i]; var body := car["body"] as RigidBody3D
		if not is_instance_valid(body) or not body.is_inside_tree():
			_cars.remove_at(i); continue      # freed by its owner: drop the entry
		# A FOREIGN BODY IS NEVER FREED HERE. Distance and debris age are the
		# brain's licence to delete things it made; an adopted body belongs to
		# whoever built it. All this branch can do is hand it back.
		if bool(car.get("foreign", false)):
			if _foreign_lapsed(car, body, delta): _foreign_restore(car); _cars.remove_at(i)
			continue
		if not bool(car["frozen"]): car["age"] = float(car["age"]) + delta
		if pv == null: continue
		var d := body.global_position.distance_to(pv.global_position)
		if (d > DESPAWN_FROZEN) if bool(car["frozen"]) \
				else (float(car["age"]) > DEBRIS_MIN_AGE and d > DESPAWN_DEBRIS):
			body.queue_free(); _cars.remove_at(i)

## Ambient shells only: an adopted body is somebody else's car standing in the
## same street, and counting it would silently thin the ambient fleet — and with
## it the moment at which the seeded spawn stream draws its next number.
func _frozen_count() -> int:
	var n := 0
	for car in _cars:
		if bool(car.get("foreign", false)): continue
		n += 1 if bool(car["frozen"]) and is_instance_valid(car["body"]) else 0
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
		_make_car(pos, dirv, kind, center, _rng); return true
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

## `rng` is the stream this car's shape/paint/speed are drawn from, and it is
## ALWAYS the same stream that chose the spawn point: the grid passes the seeded
## `_rng` (whose draw order is frozen), spurs pass `_spur_rng`. `extra` is merged
## into the car record before _plan_next sees it — that is how a spur car arrives
## already knowing which polyline, segment and direction it is on.
func _make_car(pos: Vector3, dirv: Vector3, kind: int, center: float,
		rng: RandomNumberGenerator, extra: Dictionary = {}) -> void:
	var truck := rng.randf() < TRUCK_CHANCE
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
		else PALETTE[rng.randi_range(0, PALETTE.size() - 1)]  # SAME draw as before
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
		"tspeed": rng.randf_range(SPEED_RANGE.x, SPEED_RANGE.y), "speed": 0.0,
		"choice": 0, "decided": false, "event": 0.0, "event_end": false,
		"arc_c": Vector3.ZERO, "arc_u": Vector3.ZERO, "arc_sweep": 0.0, "arc_sgn": 1.0,
		"arc_r": 1.0, "exit_dir": dirv, "exit_center": center, "exit_kind": kind,
		# Spur state: -1 = not on a spur. `seg` indexes the polyline segment and
		# `sdir` (+1/-1) which way along it, so `dir` is dirs[seg] * sdir.
		"spur": -1, "seg": 0, "sdir": 1.0, "sp_end": SP_UTURN, "sp_seg": 0,
		"sp_sdir": 1.0, "sp_kind": KIND_NS, "sp_center": 0.0, "stuck_t": 0.0,
		"exit_spur": -1, "exit_seg": 0, "exit_sdir": 1.0,
		# Signal state. sig_jit comes off the SEPARATE runtime stream so the
		# seeded spawn draws above stay in their frozen order.
		"sig_key": -1, "sig_mode": SG_NEW, "sig_wait": 0.0,
		"sig_jit": _sig_rng.randf() * SIG_JITTER}
	car["speed"] = float(car["tspeed"])
	car.merge(extra, true)
	_cars.append(car); _plan_next(car)

# ============================== LANE DRIVING =================================
## Next event along travel: nearest perpendicular crossing beyond DECIDE_DIST,
## else the street end (grid ends U-turn; frontage ends despawn at map edge).
func _plan_next(car: Dictionary) -> void:
	var body := car["body"] as RigidBody3D
	_sig_forget(car)  # the old intersection is behind us: drop its hold + token
	if not is_instance_valid(body): return
	if int(car["kind"]) == KIND_SPUR: _plan_spur(car); return
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

## Where this shell is along its own road, and which way "forward" moves that
## number. Grid lanes ride a world axis, so the coordinate IS x or z and the sign
## is the heading's component. A spur segment can point either way along either
## axis, so its coordinate is the projection onto the heading — which always
## grows forward, hence a sign of +1. One pair, so `rem` is the same subtraction
## for every kind.
func _travel_coord(car: Dictionary, body: RigidBody3D) -> float:
	var pos := body.global_position
	if int(car["kind"]) == KIND_SPUR:
		var d := car["dir"] as Vector3
		return pos.x * d.x + pos.z * d.z
	return pos.z if int(car["kind"]) == KIND_NS else pos.x


func _travel_sign(car: Dictionary) -> float:
	if int(car["kind"]) == KIND_SPUR: return 1.0
	var d := car["dir"] as Vector3
	return d.x + d.z

func _drive(car: Dictionary, delta: float, pv: RigidBody3D) -> void:
	var body := car["body"] as RigidBody3D
	if not is_instance_valid(body) or not body.is_inside_tree(): return
	var turning := int(car["state"]) == TURN
	var heading: Vector3 = (car["arc_u"] as Vector3).rotated(
		Vector3.UP, float(car["arc_sgn"]) * PI * 0.5) if turning else car["dir"] as Vector3
	var foreign := bool(car.get("foreign", false))
	# Fast player closing inside 4 m: unfreeze BEFORE impact so the hit lands
	# on loose physics, not an immovable kinematic wall. NOT for an adopted
	# body: wrecking it is the owner's call (and the player's job), not ours.
	if pv != null and not foreign:
		var sep := body.global_position - pv.global_position; var d := sep.length()
		var lat := (sep - heading * sep.dot(heading)).length()  # drive-bys stay frozen
		if d < CRASH_DIST and d > 0.01 and lat < CRASH_LATERAL and (pv.linear_velocity
				- heading * float(car["speed"])).dot(sep / d) > CRASH_CLOSING:
			_unfreeze(car); return
	var limit := _sense_limit(car, body, heading)
	limit = minf(limit, _follow_limit(car, body, heading))
	# The owner's "is it boxed in?" clock. Runs for every adopted body of every
	# kind, on its own threshold, and never touches the spur give-up timer.
	if foreign:
		car["f_stuck"] = float(car.get("f_stuck", 0.0)) + delta \
			if float(car["speed"]) < ADOPT_STUCK else 0.0
	_honk_check(car, body, heading, limit, delta)
	if turning:
		_set_speed(car, _turn_limit(car, limit), delta); _step_turn(car, body, delta); return
	var dirv := car["dir"] as Vector3
	var rem := (float(car["event"]) - _travel_coord(car, body)) * _travel_sign(car)  # dist to event
	# Out on a spur there is no signal, no queue and nobody coming to sort it out:
	# a shell that has been stopped this long (the player parked across the lane,
	# or two of them nose to nose at an unsignalled Cedar Cliff crossroads) gives
	# up and turns around instead of standing there for the rest of the session.
	if int(car["kind"]) == KIND_SPUR:
		limit = minf(limit, _yield_limit(car, body, heading))  # give way at a crossing
		car["stuck_t"] = float(car["stuck_t"]) + delta if float(car["speed"]) < SIG_CREEP \
			else 0.0
		# An adopted shell never turns itself around out of boredom: a runner
		# that doubles back is a runner driving at the player. The owner reads
		# stuck_for() and decides the car is boxed in.
		if foreign: car["stuck_t"] = 0.0
		if float(car["stuck_t"]) >= SPUR_GIVEUP:
			car["stuck_t"] = 0.0
			_spur_exit(car, int(car["seg"]), -float(car["sdir"]))
			_start_turn(car, body, 3, limit, delta); return
	if bool(car["event_end"]):
		if rem < APPROACH_DIST: limit = minf(limit, TURN_SPEED)
		if rem <= _end_trigger(car):
			if int(car["kind"]) == KIND_SPUR:
				if _spur_event(car, body, limit, delta): return
			elif int(car["kind"]) == KIND_FRONTAGE:
				# An adopted body is never retired — it is handed back instead,
				# next frame, from _validate (mutating _cars mid-iteration here
				# would skip a car). The frontage is the ONE lane kind whose end
				# frees the shell, so this guard is the whole of that hazard.
				if foreign: car["lapse"] = true; return
				body.queue_free(); return  # one-way road meets the map edge: retire
			elif not _join_spur(car, body):
				_start_turn(car, body, 3, limit, delta); return  # dead-end U-turn
	else:
		limit = minf(limit, _signal_limit(car, rem, delta))  # M17: the light
		if not bool(car["decided"]) and rem <= DECIDE_DIST:
			car["decided"] = true
			if foreign:
				# Own stream, own weights: a runner prefers straight (80/10/10),
				# and the seeded grid draw order is untouched either way.
				var st := FLEE_STRAIGHT if bool(car.get("flee", false)) else TURN_STRAIGHT
				var rt := FLEE_RIGHT if bool(car.get("flee", false)) else TURN_RIGHT
				var froll := _adopt_rng.randf()
				car["choice"] = 0 if froll < st else (1 if froll < st + rt else 2)
			else:
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
	if foreign: pos = _lane_converge(car, pos, dirv, delta)
	pos.y = float(car["ride"]); _place(body, dirv, pos)

# ============================== THE HORN (D-060) =============================
## A driver you are holding up leans on the horn — DNA §4: "drivers honk, flee,
## fight back". Blocked (lane speed under HONK_SPEED) with the PLAYER ahead in
## the lane for HONK_AFTER seconds → one honk, then a cooldown drawn off the
## runtime stream, never the seeded spawn draws. The stream is vehicle_audio's
## own horn synthesis, pitched a little differently per honk.
const HONK_AFTER := 2.4; const HONK_SPEED := 0.4; const HONK_GAP := 10.0
const HONK_COOLDOWN := Vector2(4.0, 8.0); const HONK_DB := -6.0; const HONK_LEN := 0.9
func _honk_check(car: Dictionary, body: RigidBody3D, heading: Vector3, limit: float, delta: float) -> void:
	var actor := _player_actor()
	var blocked := false
	if limit < HONK_SPEED and actor != null:
		blocked = _gap_ahead(body.global_position, heading, actor.global_position, float(car["half_len"])) < HONK_GAP
	car["blocked_t"] = float(car.get("blocked_t", 0.0)) + delta if blocked else 0.0
	car["honk_cd"] = maxf(float(car.get("honk_cd", 0.0)) - delta, 0.0)
	if float(car["blocked_t"]) >= HONK_AFTER and float(car["honk_cd"]) <= 0.0:
		car["honk_cd"] = _jit(car).randf_range(HONK_COOLDOWN.x, HONK_COOLDOWN.y)
		car["blocked_t"] = 0.0
		_honk(car, body)

## Which runtime-jitter stream this shell draws from. An ambient shell uses
## `_sig_rng` exactly as it always has — same stream, same order, same numbers
## — and an ADOPTED body uses `_adopt_rng`, so a repo order leaning on its horn
## cannot shift the dwell jitter of the traffic around it either.
func _jit(car: Dictionary) -> RandomNumberGenerator:
	return _adopt_rng if bool(car.get("foreign", false)) else _sig_rng


func _honk(car: Dictionary, body: RigidBody3D) -> void:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if not (sys is Dictionary) or not (sys as Dictionary).has("vehicle_audio"): return
	var va: Variant = (sys as Dictionary)["vehicle_audio"]
	if not (va is Node) or not (va as Node).has_method("horn_stream"): return
	var stream: Variant = (va as Node).call("horn_stream")
	if not (stream is AudioStreamWAV): return
	var p: Variant = car.get("horn_p")
	if not (p is AudioStreamPlayer3D) or not is_instance_valid(p):
		var np := AudioStreamPlayer3D.new()
		np.stream = stream; np.unit_size = 12.0; np.max_distance = 150.0; np.volume_db = HONK_DB
		body.add_child(np); car["horn_p"] = np; p = np
	var hp := p as AudioStreamPlayer3D
	hp.pitch_scale = 0.9 + 0.2 * _jit(car).randf()   # not every horn is the same horn
	hp.play()
	get_tree().create_timer(HONK_LEN).timeout.connect(func() -> void:
		if is_instance_valid(hp): hp.stop())   # the stream loops; a honk is a beat

## The body a driver is stuck behind: the player's vehicle, or Book on foot.
func _player_actor() -> Node3D:
	if main_ref == null: return null
	var key := "character" if main_ref.get("on_foot") == true else "vehicle"
	var a: Variant = main_ref.get(key)
	return a if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree() else null

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
	# A RUNNER READS EVERY RED AS AN AMBER. Not a separate code path — the late-
	# amber logic below already models "too late to stop honestly, clear the box
	# instead", and at 15-18 m/s inside SIG_AMBER_LOOK it is always too late. So
	# a fleeing shell runs the light for a reason the geometry agrees with, and
	# if traffic has it down to a crawl it still waits, which is what makes the
	# chase readable. It still yields to the box via car-following.
	if ph == PH_STOP and bool(car.get("flee", false)): ph = PH_CAUTION
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


## The arc's own ceiling. A U-turn is the one manoeuvre whose first quarter is
## still pointing at whatever it is turning away from: the sense ray reads the
## blocker head-on, the limit is 0, and _step_turn's d_ang is speed*delta/r — so
## a shell that U-turns because it is blocked would freeze at zero degrees and
## never sweep. Spur U-turns therefore keep a walking-pace floor until the arc
## has swung far enough to see round it. Grid cars are untouched.
func _turn_limit(car: Dictionary, limit: float) -> float:
	var cap := minf(limit, TURN_SPEED)
	if int(car["kind"]) == KIND_SPUR and float(car["arc_sweep"]) > PI * 0.6:
		return maxf(cap, SPUR_UTURN_CREEP)
	return cap


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
	if int(car["kind"]) == KIND_SPUR:
		# The exit polyline/segment/direction were staged by _spur_exit before the
		# call; a spur turn never crosses onto the grid, so the kind is carried.
		car["exit_kind"] = KIND_SPUR; car["exit_center"] = float(car["center"])
	elif turn == 3:
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
	if int(car["kind"]) == KIND_SPUR:
		car["spur"] = int(car["exit_spur"]); car["seg"] = int(car["exit_seg"])
		car["sdir"] = float(car["exit_sdir"]); car["stuck_t"] = 0.0
		pos = _spur_snap(car, pos, dirv)
	elif int(car["kind"]) == KIND_NS: pos.x = float(car["center"]) + lane.x
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
		# An adopted body leaves the way it arrived: the owner's freeze state
		# back, its momentum along the heading it was driving.
		if bool(_cars[i].get("foreign", false)): _foreign_restore(_cars[i])
		_cars.remove_at(i)
		return sp
	return 0.0

# ============================== CRASH HANDOFF ================================
## Permanent handoff to loose physics: keeps momentum, stays towable forever.
func _unfreeze(car: Dictionary) -> void:
	if not bool(car["frozen"]) or bool(car.get("foreign", false)): return
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
	if car.is_empty(): return
	# The chain is on an adopted body: hand it straight back. The owner is meant
	# to call release() on this same signal — this is the belt to that brace, and
	# it fires no heat, because hooking a repo order is the JOB, not a theft.
	if bool(car.get("foreign", false)):
		release(body as RigidBody3D); return
	if not bool(car["frozen"]): return
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

# ============================== SPURS ========================================
## THE ATLAS IS THE REGISTER OF THE ROADS. Every road that is not the downtown
## grid lives in data/world/atlas.json (D-066) as a class plus a polyline in
## world x,z, and the city map draws straight from it. Traffic reads the SAME
## register — the "street" polylines only — so a street added to the atlas gets
## cars without anyone editing this file. The atlas is optional: no file, no
## spurs, and downtown drives exactly as it did.
##
## A polyline qualifies when it is axis-aligned (the arc helpers turn between
## cardinals, and 90 degrees is the only corner they can sweep) and longer than
## spur_min_len — which is what keeps Boone Trucks' 8 m drive, the two ~76 m
## hospital drives and Fair Drive's 66 m stub empty.
func _load_spurs() -> void:
	var tune := _read_json(SPURS_PATH)
	var min_len := float(tune.get("spur_min_len", SPUR_MIN_LEN))
	var def_cap := int(tune.get("spur_cap", SPUR_CAP))
	var def_lane := float(tune.get("lane_offset", LANE_OFFSET))
	var raw_caps: Variant = tune.get("caps", {})
	var caps := raw_caps as Dictionary if raw_caps is Dictionary else {}
	var raw_lanes: Variant = tune.get("lanes", {})
	var lanes := raw_lanes as Dictionary if raw_lanes is Dictionary else {}
	var roads: Variant = _read_json(ATLAS_PATH).get("roads", [])
	if not (roads is Array): return
	for entry: Variant in roads as Array:
		if not (entry is Dictionary): continue
		var road := entry as Dictionary
		if String(road.get("class", "")) != "street": continue
		var spur := _build_spur(road)
		if spur.is_empty() or float(spur["total"]) < min_len: continue
		var nm := String(road.get("name", ""))
		spur["cap"] = int(caps.get(nm, def_cap))
		# The lane offset is HALF THE ROAD, and the atlas does not carry a width:
		# 3.5 m is Juárez Boulevard's 12 m of asphalt, but Cedar Cliff's side and
		# back streets are 8 m wide and a 3.5 m lane would hang a wheel off the
		# edge of them. Per-road override, by atlas name, in traffic_spurs.json.
		spur["lane"] = float(lanes.get(nm, def_lane))
		_spurs.append(spur)


## Optional JSON: a missing or malformed file is a quiet {}. The spur layer is
## additive, and downtown must not care whether either file shipped.
func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path): return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null: return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	return parsed as Dictionary if parsed is Dictionary else {}


## One polyline -> {pts, dirs, lens, total, cap}. Returns {} for anything this
## brain cannot drive: fewer than two points, a degenerate segment, or a segment
## that is not axis-aligned (the arcs sweep exactly 90 degrees between cardinals,
## so a diagonal corner would exit on a heading the lane maths does not expect).
func _build_spur(road: Dictionary) -> Dictionary:
	var raw: Variant = road.get("pts", [])
	if not (raw is Array) or (raw as Array).size() < 2: return {}
	var pts := PackedVector2Array()
	for p: Variant in raw as Array:
		if not (p is Array) or (p as Array).size() < 2: return {}
		var pair := p as Array
		pts.append(Vector2(float(pair[0]), float(pair[1])))
	var dirs: Array[Vector3] = []
	var lens := PackedFloat32Array()
	var total := 0.0
	for i in pts.size() - 1:
		var leg := pts[i + 1] - pts[i]
		var leg_len := leg.length()
		if leg_len < 1.0: return {}
		var d := Vector3(leg.x / leg_len, 0.0, leg.y / leg_len)
		if absf(d.x) > SPUR_AXIS_TOL and absf(d.z) > SPUR_AXIS_TOL: return {}
		var card := _cardinal(d)
		# A polyline that doubles back on itself has no drivable corner: the
		# turn classifier would read the reversal as "straight on".
		if not dirs.is_empty() and (dirs[dirs.size() - 1] as Vector3).dot(card) < -0.5:
			return {}
		dirs.append(card); lens.append(leg_len); total += leg_len
	return {"pts": pts, "dirs": dirs, "lens": lens, "total": total, "cap": SPUR_CAP}


## A spur car spawns under the same rules a grid car does — inside the ring, out
## of the corridor, SPAWN_CLEARANCE from anything solid — plus two of its own:
## the per-spur cap, and never within SPUR_CORNER_CLEAR of a vertex, so nothing
## materialises inside an arc it would immediately be turning through. EVERY draw
## here comes off _spur_rng; the seeded grid stream is never touched.
func _try_spawn_spur(ppos: Vector3) -> bool:
	if _spurs.is_empty(): return false
	for _a in SPAWN_TRIES:
		var si := _spur_rng.randi_range(0, _spurs.size() - 1)
		var spur := _spurs[si]
		if _spur_count(si) >= int(spur["cap"]): continue
		var lens: PackedFloat32Array = spur["lens"]
		var seg := _pick_segment(lens, _spur_rng.randf() * float(spur["total"]))
		var span := lens[seg] - 2.0 * SPUR_CORNER_CLEAR
		if span <= 0.0: continue
		var sdir := 1.0 if _spur_rng.randf() < 0.5 else -1.0
		var along := SPUR_CORNER_CLEAR + _spur_rng.randf() * span
		var dirs: Array = spur["dirs"]
		var dirv := (dirs[seg] as Vector3) * sdir
		var head: Vector2 = (spur["pts"] as PackedVector2Array)[seg]
		var pos := Vector3(head.x, 0.0, head.y) + (dirs[seg] as Vector3) * along \
			+ _right(dirv) * float(spur["lane"])
		var d := Vector2(pos.x - ppos.x, pos.z - ppos.z).length()
		if d < SPAWN_RING.x or d > SPAWN_RING.y: continue
		if CORRIDOR.has_point(Vector2(pos.x, pos.z)): continue
		if not _clear_at(pos): continue
		_make_car(pos, dirv, KIND_SPUR, 0.0, _spur_rng,
			{"spur": si, "seg": seg, "sdir": sdir})
		return true
	return false


## Length-weighted segment pick: the 759 m leg of Juárez Boulevard should carry
## three times the cars of its 234 m leg, not the same number.
func _pick_segment(lens: PackedFloat32Array, roll: float) -> int:
	var acc := roll
	for i in lens.size() - 1:
		acc -= lens[i]
		if acc <= 0.0: return i
	return lens.size() - 1


## PUBLIC (probe/QA): how many spur routes the atlas handed us, and how many
## shells are driving them right now. A census is the only honest way for a
## headless check to assert "Juárez Boulevard has traffic on it".
func spur_census() -> Dictionary:
	var n := 0
	for car in _cars:
		if int(car.get("spur", -1)) >= 0 and is_instance_valid(car["body"]): n += 1
	return {"routes": _spurs.size(), "cars": n}


func _spur_count(si: int) -> int:
	var n := 0
	for car in _cars:
		if int(car.get("spur", -1)) == si and bool(car["frozen"]) \
				and is_instance_valid(car["body"]): n += 1
	return n


## The spur half of _plan_next. The event is ALWAYS the far vertex of the
## current segment — a spur has no signalled crossing, so `event_end` stays true
## — and WHAT happens there is settled here, once, instead of being rolled at
## the intersection the way a grid turn is: a corner is not a choice.
func _plan_spur(car: Dictionary) -> void:
	var si := int(car["spur"])
	if si < 0 or si >= _spurs.size(): return
	var spur := _spurs[si]
	var pts: PackedVector2Array = spur["pts"]
	var dirs: Array = spur["dirs"]
	var seg := clampi(int(car["seg"]), 0, dirs.size() - 1)
	var sdir := float(car["sdir"])
	var dirv := (dirs[seg] as Vector3) * sdir
	car["seg"] = seg; car["dir"] = dirv   # exact: no drift off an arc exit
	car["decided"] = false; car["choice"] = 0; car["event_end"] = true
	var tgt: Vector2 = pts[seg + 1] if sdir > 0.0 else pts[seg]
	car["event"] = tgt.x * dirv.x + tgt.y * dirv.z   # same projection as _travel_coord
	var nseg := seg + 1 if sdir > 0.0 else seg - 1
	if nseg >= 0 and nseg < dirs.size():
		var side := _right(dirv).dot((dirs[nseg] as Vector3) * sdir)
		var turn := SP_STRAIGHT if absf(side) < 0.5 else (SP_RIGHT if side > 0.0 else SP_LEFT)
		_spur_stage(car, turn, nseg, sdir); return
	if _join_grid(car, tgt, dirv): return   # the end meets a grid lane: merge
	_spur_stage(car, SP_UTURN, seg, -sdir)  # otherwise turn around on the spot


func _spur_stage(car: Dictionary, end_code: int, nseg: int, nsdir: float) -> void:
	car["sp_end"] = end_code; car["sp_seg"] = nseg; car["sp_sdir"] = nsdir


## How far short of the event the manoeuvre begins. Grid streets and the
## frontage act AT the end (0). A spur corner is the same geometry as a grid
## crossing — the arc has to start LANE_OFFSET + R_RIGHT short of the vertex to
## land on the exit lane, R_LEFT - LANE_OFFSET short for a left — so it reuses
## the same two triggers, and a U-turn or a merge still happens at the end.
func _end_trigger(car: Dictionary) -> float:
	if int(car["kind"]) != KIND_SPUR: return 0.0
	var lane := _spur_lane(car)
	match int(car["sp_end"]):
		SP_RIGHT: return lane + R_RIGHT
		SP_LEFT: return R_LEFT - lane
	return 0.0


## The manoeuvre at the far vertex. Returns true when this frame belongs to an
## arc (the caller must not move the shell as well); false for the two collinear
## continuations — another segment dead ahead, or a merge onto a grid lane —
## where the heading does not change and the shell just keeps rolling.
func _spur_event(car: Dictionary, body: RigidBody3D, limit: float, delta: float) -> bool:
	var end_code := int(car["sp_end"])
	if end_code == SP_RIGHT or end_code == SP_LEFT or end_code == SP_UTURN:
		_spur_exit(car, int(car["sp_seg"]), float(car["sp_sdir"]))
		_start_turn(car, body, end_code, limit, delta)
		return true
	if end_code == SP_JOIN:
		car["kind"] = int(car["sp_kind"]); car["center"] = float(car["sp_center"])
		car["spur"] = -1; car["stuck_t"] = 0.0
		var dirv := car["dir"] as Vector3
		var lane := _right(dirv) * LANE_OFFSET
		var pos := body.global_position
		if int(car["kind"]) == KIND_NS: pos.x = float(car["center"]) + lane.x
		else: pos.z = float(car["center"]) + lane.z
		pos.y = float(car["ride"]); _place(body, dirv, pos)
		_plan_next(car); return false
	car["seg"] = int(car["sp_seg"]); car["sdir"] = float(car["sp_sdir"])
	_plan_next(car); return false        # collinear next segment: drive straight on


## Stage what _finish_turn will land this shell on: the same polyline, the
## segment the arc exits onto, and which way along it.
func _spur_exit(car: Dictionary, nseg: int, nsdir: float) -> void:
	car["exit_spur"] = int(car["spur"]); car["exit_seg"] = nseg
	car["exit_sdir"] = nsdir


## How far right of its centreline this shell rides. Defaults to the grid's own
## LANE_OFFSET; a narrower road overrides it in traffic_spurs.json.
func _spur_lane(car: Dictionary) -> float:
	var si := int(car["spur"])
	if si < 0 or si >= _spurs.size(): return LANE_OFFSET
	return float(_spurs[si]["lane"])


## Put the shell exactly on its lane — the line _spur_lane right of the segment
## it is now on — keeping whatever progress it already has along that line. Same
## snap _finish_turn does for a grid lane, generalised to a segment that can run
## any of four ways.
func _spur_snap(car: Dictionary, pos: Vector3, dirv: Vector3) -> Vector3:
	var si := int(car["spur"])
	if si < 0 or si >= _spurs.size(): return pos
	var pts: PackedVector2Array = _spurs[si]["pts"]
	var seg := clampi(int(car["seg"]), 0, pts.size() - 2)
	var head: Vector2 = pts[seg]
	var base := Vector3(head.x, 0.0, head.y) + _right(dirv) * _spur_lane(car)
	var rel := pos - base; rel.y = 0.0
	return base + dirv * rel.dot(dirv)


# ---- THE TWO MERGES ---------------------------------------------------------
## Juárez Boulevard's north end at (279, 566) is 21 m from where the x=279 grid
## street stops at z=545, on the same centreline — and the downtown street bed
## runs out to z=566 — so the two lanes are literally collinear. A shell that
## reaches either end keeps its heading and simply changes which brain drives
## it: no arc, no gap, no U-turn in the middle of a boulevard. Both directions
## are covered (_join_grid takes a spur car onto the grid, _join_spur takes a
## grid car off it) and both refuse anything that is not a straight continuation
## — SPUR_JOIN metres ahead at most, SPUR_JOIN_LAT off the lane at most. On the
## shipped atlas exactly one pair of ends passes: Juárez's north end. Every
## other end U-turns, which is the documented fallback.

## Spur terminal -> grid lane. Stages SP_JOIN plus the lane to land on; false
## when no grid street continues ahead, and _plan_spur stages a U-turn instead.
func _join_grid(car: Dictionary, tgt: Vector2, dirv: Vector3) -> bool:
	if absf(_spur_lane(car) - LANE_OFFSET) > 0.01: return false  # lanes not collinear
	var ns := absf(dirv.z) > 0.5              # travelling north/south -> an N-S street
	var lanes: Array[float] = _ns_x if ns else _ew_z
	var mine := tgt.x if ns else tgt.y        # the spur's centreline at this end
	var along := tgt.y if ns else tgt.x       # ... and where along the grid street
	var s := dirv.z if ns else dirv.x         # +1 toward the +axis
	var bounds := NS_Z if ns else EW_X
	if ((bounds.x if s < 0.0 else bounds.y) - along) * s <= 0.0: return false  # behind us
	if ((bounds.y if s < 0.0 else bounds.x) - along) * s > SPUR_JOIN: return false  # too far
	for c in lanes:
		if absf(c - mine) > SPUR_JOIN_LAT: continue
		car["sp_end"] = SP_JOIN; car["sp_center"] = c
		car["sp_kind"] = KIND_NS if ns else KIND_EW
		return true
	return false


## Grid lane end -> spur. The same test from the other side: a spur terminal
## ahead of us, on our heading, whose lane is the one we are already in. Switches
## the shell over in place and returns true; false means the caller does the
## old dead-end U-turn, exactly as before.
func _join_spur(car: Dictionary, body: RigidBody3D) -> bool:
	var dirv := car["dir"] as Vector3
	var pos := body.global_position
	var side := _right(dirv)
	for si in _spurs.size():
		var spur := _spurs[si]
		var pts: PackedVector2Array = spur["pts"]
		var dirs: Array = spur["dirs"]
		for tail in 2:
			var seg := 0 if tail == 0 else dirs.size() - 1
			var sdir := 1.0 if tail == 0 else -1.0
			if (dirs[seg] as Vector3).dot(dirv) * sdir < 0.999: continue
			var p: Vector2 = pts[0] if tail == 0 else pts[pts.size() - 1]
			var to := Vector3(p.x, 0.0, p.y) - pos; to.y = 0.0
			var ahead := to.dot(dirv)
			if ahead < 0.0 or ahead > SPUR_JOIN: continue
			if absf((to - dirv * ahead).dot(side) + float(spur["lane"])) > SPUR_JOIN_LAT: continue
			car["kind"] = KIND_SPUR; car["spur"] = si; car["seg"] = seg
			car["sdir"] = sdir; car["stuck_t"] = 0.0
			var np := _spur_snap(car, pos, dirv); np.y = float(car["ride"])
			_place(body, dirv, np); _plan_next(car)
			return true
	return false

# ============================== ADOPTION =====================================
## THE BRAIN CAN DRIVE A BODY IT DID NOT SPAWN. repo_orders builds the order car
## — same frozen kinematic shell, same wheels, its own groups ("towable",
## "mission_target", "repo_order") and its own name — and when the debtor gets
## in and runs, it hands the body here. From that frame the lane brain drives it
## exactly like an ambient shell: right-hand lane, arcs at the corners, the
## signals, car-following, the obstacle ray. Three things are different, and
## they are the whole contract:
##   1. THE BRAIN NEVER FREES IT. Not on despawn distance, not on debris age,
##      not on a crash. Its groups, metadata, name and mesh are never touched.
##      The owner built it and the owner deletes it.
##   2. Every random number it needs comes off `_adopt_rng`, a fourth stream on
##      its own literal seed, so a repo order tearing through downtown cannot
##      move the seeded grid spawn stream by a single draw.
##   3. With `flee` it uses the FLEE profile: 15-18 m/s, reds read as ambers,
##      straight preferred 80/10/10, no U-turn that is not a dead end, and the
##      player-proximity crash rule off — stopping it is the player's job.
## Returns false and touches NOTHING when no lane centreline of any kind (grid,
## frontage, spur) passes within ADOPT_RANGE of the body.
func adopt(body: RigidBody3D, flee := true) -> bool:
	if not is_instance_valid(body) or not body.is_inside_tree(): return false
	if main_ref == null or _ns_x.is_empty(): return false   # smoke mode: inert
	var known := _find(body)
	if not known.is_empty(): return bool(known.get("foreign", false))  # already ours
	var lane := _nearest_lane(body.global_position)
	if lane.is_empty(): return false
	# HEADING: the lane runs two ways; take the one pointing away from the man
	# it is running from. No player (headless, a probe) falls back to the way the
	# body is already facing, which is what the owner parked it doing.
	var axis := _cardinal(lane["axis"] as Vector3)
	var actor := _player_actor()
	var away := body.global_position - actor.global_position if actor != null \
		else -body.global_transform.basis.z
	away.y = 0.0
	if away.length_squared() < 0.01: away = -body.global_transform.basis.z
	var dirv := axis if axis.dot(away) >= 0.0 else -axis
	var kind := int(lane["kind"])
	var ride := body.global_position.y
	var car := {
		"body": body, "frozen": true, "state": CRUISE, "dir": dirv, "kind": kind,
		"center": float(lane["center"]), "ride": ride,
		"half_len": _body_half_len(body), "age": 0.0,
		"tspeed": _adopt_rng.randf_range(FLEE_SPEED.x, FLEE_SPEED.y) if flee \
			else _adopt_rng.randf_range(SPEED_RANGE.x, SPEED_RANGE.y),
		"speed": 0.0, "choice": 0, "decided": false, "event": 0.0, "event_end": false,
		"arc_c": Vector3.ZERO, "arc_u": Vector3.ZERO, "arc_sweep": 0.0, "arc_sgn": 1.0,
		"arc_r": 1.0, "exit_dir": dirv, "exit_center": float(lane["center"]),
		"exit_kind": kind,
		"spur": int(lane["spur"]), "seg": int(lane["seg"]), "sdir": 1.0,
		"sp_end": SP_UTURN, "sp_seg": 0, "sp_sdir": 1.0, "sp_kind": KIND_NS,
		"sp_center": 0.0, "stuck_t": 0.0,
		"exit_spur": int(lane["spur"]), "exit_seg": int(lane["seg"]), "exit_sdir": 1.0,
		"sig_key": -1, "sig_mode": SG_NEW, "sig_wait": 0.0,
		"sig_jit": _adopt_rng.randf() * SIG_JITTER,
		# The foreign half of the record. `own_freeze` is the flag the brain is
		# holding; `was_*` is the state handed back on release.
		"foreign": true, "flee": flee, "f_stuck": 0.0, "off_t": 0.0,
		"merging": true, "lapse": false,
		"own_freeze": true, "was_freeze": body.freeze, "was_mode": body.freeze_mode}
	if kind == KIND_SPUR:
		car["sdir"] = 1.0 if (lane["axis"] as Vector3).dot(dirv) > 0.0 else -1.0
		car["exit_sdir"] = float(car["sdir"])
	# It launches from whatever it was already doing, not from its target speed:
	# a debtor who just jumped in accelerates out of the space like a person.
	car["speed"] = clampf(body.linear_velocity.dot(dirv), 0.0, float(car["tspeed"]))
	body.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	body.freeze = true
	# THE HEADING SNAPS, THE POSITION DOES NOT. A curbside order car is 3-8 m off
	# the lane it is about to join and the search reaches 40 m; teleporting it
	# sideways onto the centreline is a pop, and at 40 m it is a pop through a
	# building. It keeps where it is and crabs onto the lane at ADOPT_MERGE m/s,
	# which is what pulling out of a parking space looks like.
	_place(body, dirv, body.global_position)
	_cars.append(car); _plan_next(car)
	return true


## PUBLIC: the brain lets go. The body keeps the velocity it was driving at,
## along the heading it was driving, and gets its owner's freeze state back.
## Called with a body that has already been freed (or with null) this prunes
## every stale foreign entry instead — which is also the automatic drop.
func release(body: RigidBody3D) -> void:
	for i in range(_cars.size() - 1, -1, -1):
		var car := _cars[i]
		if not bool(car.get("foreign", false)): continue
		var b: Variant = car.get("body")
		if is_instance_valid(b) and b != body: continue
		_foreign_restore(car)
		_cars.remove_at(i)


## PUBLIC: is the brain driving this body right now?
func is_driving(body: RigidBody3D) -> bool:
	if not is_instance_valid(body): return false
	var car := _find(body)
	return not car.is_empty() and bool(car.get("foreign", false))


## PUBLIC: its lane speed in m/s (0 for anything the brain is not driving).
func driven_speed(body: RigidBody3D) -> float:
	if not is_instance_valid(body): return 0.0
	var car := _find(body)
	if car.is_empty() or not bool(car.get("foreign", false)): return 0.0
	return float(car["speed"])


## PUBLIC: seconds this adopted body has been under ADOPT_STUCK, 0 while it is
## moving. The owner's "boxed in" test — the brain deliberately does NOT turn a
## runner around by itself, so this number is the only way out of a blocked lane.
func stuck_for(body: RigidBody3D) -> float:
	if not is_instance_valid(body): return 0.0
	var car := _find(body)
	if car.is_empty() or not bool(car.get("foreign", false)): return 0.0
	return float(car["f_stuck"])


## The nearest drivable lane of ANY kind to a world point, or {} when the
## closest one is further than ADOPT_RANGE. Distance is measured to the
## CENTRELINE (the polyline / street axis), not to the lane the car will ride:
## the offset is applied afterwards, once a direction of travel is chosen, and
## which side of the road that is depends on which way the car ends up pointing.
## Returns {kind, center, axis, spur, seg}. One-shot, at adopt time only.
func _nearest_lane(p: Vector3) -> Dictionary:
	var best: Dictionary = {}
	var bd := ADOPT_RANGE
	for x: float in _ns_x:
		var d := _seg_near(p, Vector2(x, NS_Z.x), Vector2(x, NS_Z.y))
		if d < bd:
			bd = d
			best = {"kind": KIND_NS, "center": x, "axis": Vector3(0, 0, 1),
				"spur": -1, "seg": 0}
	for z: float in _ew_z:
		var d := _seg_near(p, Vector2(EW_X.x, z), Vector2(EW_X.y, z))
		if d < bd:
			bd = d
			best = {"kind": KIND_EW, "center": z, "axis": Vector3(1, 0, 0),
				"spur": -1, "seg": 0}
	for z: float in [FR_Z, -FR_Z]:
		var d := _seg_near(p, Vector2(-FR_X_END, z), Vector2(FR_X_END, z))
		if d < bd:
			bd = d
			best = {"kind": KIND_FRONTAGE, "center": z, "axis": Vector3(1, 0, 0),
				"spur": -1, "seg": 0}
	for si in _spurs.size():
		var pts: PackedVector2Array = _spurs[si]["pts"]
		var dirs: Array = _spurs[si]["dirs"]
		for seg in pts.size() - 1:
			var d := _seg_near(p, pts[seg], pts[seg + 1])
			if d < bd:
				bd = d
				best = {"kind": KIND_SPUR, "center": 0.0, "axis": dirs[seg],
					"spur": si, "seg": seg}
	return best


## Planar distance from a world point to a 2-D segment (x,z). No allocation.
func _seg_near(p: Vector3, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	var t := 0.0 if l2 < 0.0001 else clampf((Vector2(p.x, p.z) - a).dot(ab) / l2, 0.0, 1.0)
	var q := a + ab * t
	return Vector2(p.x - q.x, p.z - q.y).length()


## The point on THIS car's lane nearest its own position, keeping whatever
## progress it has along the road. One generalisation of the three snaps already
## in the file (_finish_turn's grid snap, _spur_event's merge snap, _spur_snap),
## so adoption and the off-lane watchdog cannot disagree with the driving code.
func _lane_snap_point(car: Dictionary, pos: Vector3, dirv: Vector3) -> Vector3:
	var kind := int(car["kind"])
	if kind == KIND_SPUR: return _spur_snap(car, pos, dirv)
	# Frontage lanes ride the inner side of the strip — the same sign flip
	# _try_spawn uses, and for the same reason (repo_board's junkers at z=33).
	var lane := _right(dirv) * (LANE_OFFSET if kind != KIND_FRONTAGE else -LANE_OFFSET)
	var p := pos
	if kind == KIND_NS: p.x = float(car["center"]) + lane.x
	else: p.z = float(car["center"]) + lane.z
	return p


## Half the length of a body the brain did not build, off its own collision box.
## Falls back to the sedan's, which is what everything on four wheels in this
## project is within half a metre of.
func _body_half_len(body: RigidBody3D) -> float:
	for c: Node in body.get_children():
		if not is_instance_valid(c) or not (c is CollisionShape3D): continue
		var sh: Shape3D = (c as CollisionShape3D).shape
		if sh is BoxShape3D: return (sh as BoxShape3D).size.z * 0.5
	return SEDAN_SIZE.z * 0.5


## BELT AND BRACES. The owner is expected to call release() on the tow's
## `hooked` signal; these two catch the cases where it does not.
##   1. The freeze flag is no longer the one the brain set. The brain holds an
##      adopted body frozen-kinematic — that is what "driven as a shell" means —
##      so "somebody else touched freeze" is exactly what the tow hook does when
##      it wakes a car to drag it (parked_cars' law), and equally what an owner
##      does when it re-parks the car underneath us.
##   2. More than 6 m off its lane for 3 s: something is physically moving this
##      body and it is not us. An arc is off the lane by design, so a turning
##      shell is exempt and its clock is reset.
func _foreign_lapsed(car: Dictionary, body: RigidBody3D, delta: float) -> bool:
	if bool(car.get("lapse", false)): return true   # _drive asked, deferred to here
	if bool(body.get("freeze")) != bool(car.get("own_freeze", true)): return true
	if int(car["state"]) == TURN:
		car["off_t"] = 0.0; return false
	var p := body.global_position
	var lp := _lane_snap_point(car, p, car["dir"] as Vector3)
	var off := Vector2(p.x - lp.x, p.z - lp.z).length()
	# A body still crabbing onto its lane after adoption is off it BY DESIGN;
	# the watchdog only arms once it has arrived (within a metre) the first time.
	if bool(car["merging"]):
		if off > 1.0:
			car["off_t"] = 0.0; return false
		car["merging"] = false
	car["off_t"] = float(car["off_t"]) + delta if off > ADOPT_OFF_LANE else 0.0
	return float(car["off_t"]) >= ADOPT_OFF_HOLD


## Hand a foreign body back: the owner's freeze state, and the momentum it was
## carrying along the heading it was driving. Never frees, never regroups,
## never renames. Validity FIRST, then the cast — 4.7 errors on both against a
## freed instance.
func _foreign_restore(car: Dictionary) -> void:
	var b: Variant = car.get("body")
	if not is_instance_valid(b): return
	var rb := b as RigidBody3D
	if rb == null: return
	_sig_drop_token(rb)          # it leaves mid-crossing: free the box
	# The horn player is the ONE node the brain ever adds to a foreign body;
	# it goes back with us, so the owner's car returns exactly as it came.
	var hp: Variant = car.get("horn_p")
	if is_instance_valid(hp) and hp is Node: (hp as Node).queue_free()
	rb.freeze_mode = int(car.get("was_mode", RigidBody3D.FREEZE_MODE_KINEMATIC))
	rb.freeze = bool(car.get("was_freeze", false))
	if not rb.freeze:
		rb.linear_velocity = -rb.global_transform.basis.z * float(car["speed"])


# ============================== SPUR CROSSINGS ===============================
## WHERE TWO SPURS CROSS, SOMEBODY HAS TO GO SECOND. The downtown grid has
## lights; a spur has nothing, so on the shipped atlas four unsignalled
## crossroads — the two Cliff side streets against both Juárez Boulevard
## (z=800) and the Cliff back street (z=900) — were settled by arrival order,
## and when two shells arrived together the 9 s give-up timer eventually turned
## one of them around, which looks like a driver losing their nerve for no
## reason. The rule, computed ONCE at setup and then pure arithmetic per frame:
## the SHORTER polyline yields to the longer one. A side street waiting for a
## boulevard is what that reads as on screen, and it is stable across a session
## because the polylines never change length. The give-up timer is untouched and
## still the backstop for everything this does not cover.
func _build_crossings() -> void:
	for i in _spurs.size():
		for j in range(i + 1, _spurs.size()):
			var ti := float(_spurs[i]["total"]); var tj := float(_spurs[j]["total"])
			# Shorter yields; an exact tie goes to the higher index, so the
			# answer is the same every boot.
			var yielder := i if ti < tj else j
			var other := j if yielder == i else i
			for p: Vector3 in _spur_pair_crossings(i, j):
				if not _yield_at.has(yielder): _yield_at[yielder] = []
				(_yield_at[yielder] as Array).append({"pos": p, "other": other})


## Every point where two spur polylines actually cross, as world Vector3s.
func _spur_pair_crossings(i: int, j: int) -> Array:
	var out: Array = []
	var pi: PackedVector2Array = _spurs[i]["pts"]
	var pj: PackedVector2Array = _spurs[j]["pts"]
	for a in pi.size() - 1:
		for b in pj.size() - 1:
			var hit := _axis_cross(pi[a], pi[a + 1], pj[b], pj[b + 1])
			if not hit.is_empty():
				var c := hit["p"] as Vector2
				out.append(Vector3(c.x, 0.0, c.y))
	return out


## Two AXIS-ALIGNED segments (the only kind _build_spur accepts) cross at one
## point exactly when one runs along x and the other along z and each contains
## the other's constant coordinate. Parallel pairs never cross for this purpose
## — two roads lying on top of each other is an atlas bug, not a junction.
func _axis_cross(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> Dictionary:
	var a_horiz := absf(a1.y - a0.y) < SPUR_AXIS_TOL
	var b_horiz := absf(b1.y - b0.y) < SPUR_AXIS_TOL
	if a_horiz == b_horiz: return {}
	var h0 := a0 if a_horiz else b0; var h1 := a1 if a_horiz else b1
	var v0 := b0 if a_horiz else a0; var v1 := b1 if a_horiz else a1
	var c := Vector2(v0.x, h0.y)
	if c.x < minf(h0.x, h1.x) or c.x > maxf(h0.x, h1.x): return {}
	if c.y < minf(v0.y, v1.y) or c.y > maxf(v0.y, v1.y): return {}
	return {"p": c}


## THE YIELD. INF unless this shell is on the shorter polyline, inside
## XING_YIELD of a crossing that is AHEAD of it, and somebody on the longer one
## is inside XING_WATCH of the same point and pointing at it. The ceiling is the
## same _gap_speed curve the stop bar and car-following use, fed the bumper
## distance to the crossing — so giving way looks like braking for a queue, not
## like a switch being thrown. Spur shells only, and only the handful of
## crossings this spur actually yields at: the common case is an empty Array.
func _yield_limit(car: Dictionary, body: RigidBody3D, heading: Vector3) -> float:
	var si := int(car["spur"])
	if si < 0: return INF
	var list: Variant = _yield_at.get(si)
	if not (list is Array): return INF
	var pos := body.global_position
	for e: Variant in list as Array:
		var x := e as Dictionary
		var to := (x["pos"] as Vector3) - pos; to.y = 0.0
		var ahead := to.dot(heading)
		if ahead <= 0.0 or ahead > XING_YIELD: continue
		if not _xing_busy(int(x["other"]), x["pos"] as Vector3, body): continue
		return _gap_speed(car, maxf(ahead - float(car["half_len"]), 0.0))
	return INF


## Is anyone on spur `other` bearing down on this crossing?
func _xing_busy(other: int, c: Vector3, me: RigidBody3D) -> bool:
	for o in _cars:
		if int(o.get("spur", -1)) != other or not bool(o["frozen"]): continue
		var ob: Variant = o["body"]
		if not is_instance_valid(ob) or ob == me: continue
		var to := c - (ob as Node3D).global_position; to.y = 0.0
		var d := to.length()
		if d > XING_WATCH or d < 0.01: continue
		if (to / d).dot(o["dir"] as Vector3) > XING_CLOSING: return true
	return false


## Crab an adopted body onto its lane at ADOPT_MERGE m/s of LATERAL correction
## while it drives forward normally. Pulling out of a parking space, not a
## teleport. Costs one snap-point call per adopted body per frame and nothing
## at all for ambient traffic.
func _lane_converge(car: Dictionary, pos: Vector3, dirv: Vector3, delta: float) -> Vector3:
	var lp := _lane_snap_point(car, pos, dirv)
	var off := lp - pos; off.y = 0.0
	var m := off.length()
	if m < 0.001: return pos
	return pos + off * minf(1.0, ADOPT_MERGE * delta / m)
