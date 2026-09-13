extends Node
## MISSION: HOOK AND LADDER — EL DORADO GRANDE's first scripted mission.
## Tutorial repo contract: roll into LONGHORN DISPATCH (north of the impound
## pad), haul a pearl-white Steed Longrider "Baron Brisket" out of a
## Stonebridle Ranch cul-de-sac, and deliver it to the impound — while an HOA
## drone livestreams you to Porchlight and drips police heat. State machine:
## IDLE -> DRIVE_TO -> HOOK_IT -> DELIVER -> COMPLETE (cooldown), repeatable.
## Peers (tow_hook, police, repo_board) all load AFTER this file, so every
## peer is bound lazily and null-checked. Fully inert in smoke mode.

const BEACON := preload("res://scripts/world/beacon_kit.gd")

# ============================== TUNABLES =====================================
const RNG_SEED := 0xB415C7                        # brisket parking-yaw draws
const SIGN := preload("res://scripts/world/sign_kit.gd")
const DISPATCH_POS := Vector3(709.0, 0.0, 528.0)  # 30 m north of impound pad
const DISPATCH_RADIUS := 7.0; const DISPATCH_MAX_SPEED := 3.0  # roll-in trigger
# Beacons (D-015 / D-032): were 60 m constant-width boxes visible as hard sticks
# from 300 m up, then tapered top-faded shafts that still alpha-MIXED a veil
# over everything behind them. Now ADDITIVE and range-driven (beacon_kit.gd):
# the column fades to nothing inside 26 m and the ground corona takes over, so
# neither of these can wash out the yard, the sign, or the brisket itself.
const BEAM_HEIGHT := 16.0                         # dispatch (fixed landmark)
const TARGET_BEAM_HEIGHT := 12.0                  # the brisket itself
const DISPATCH_COLOR := Color(1.0, 0.85, 0.15)
# Cul-de-sac: midway between suburb house-grid columns x=540/635, rows z=-400/
# -320 (x -600 step 95, z -880 step 80, jitter ±8, half-diag ~8.6 -> >=23m clear).
const TARGET_POS := Vector3(587.5, 0.0, -360.0)
const TARGET_SIZE := Vector3(2.35, 1.9, 5.8)      # bigger than any junker
const TARGET_MASS := 1400.0; const TARGET_FRICTION := 0.2  # junker wheel fiction
const TARGET_COLOR := Color(0.93, 0.92, 0.88)     # pearl white
const HOOK_ZONE := 35.0                           # DRIVE_TO -> HOOK_IT radius
const PAD_CENTER := Vector3(709.0, 0.0, 558.0)    # mirrors repo_board's pad
const PAD_HALF := Vector2(7.0, 5.0); const PAD_MAX_Y := 4.0
const PAYOUT := 600; const COOLDOWN_SECONDS := 30.0  # $ / dispatch re-arm (s)
const ABANDON_DISTANCE := 600.0; const ABANDON_SECONDS := 20.0  # DRIVE_TO/HOOK_IT
const FALL_RESET_Y := -30.0                       # brisket below this re-parks
const DRONE_HOVER := 12.0; const DRONE_SPEED := 14.0  # hover m / chase m/s
const DRONE_BOB_AMPLITUDE := 0.45; const DRONE_BOB_HZ := 0.4
const DRONE_EXIT_SPEED := 30.0; const DRONE_EXIT_SECONDS := 4.0  # straight-up out
const EXPOSURE_RANGE := 55.0; const EXPOSURE_SECONDS := 11.0  # full meter -> +1 heat
const SIGNAL_LOST_DISTANCE := 120.0; const SIGNAL_LOST_SECONDS := 5.0  # continuous
const FLASH_SECONDS := 3.0
const OBJECTIVE_FONT := 18; const FLASH_FONT := 28  # title flash reuses the label
const BAR_WIDTH := 320.0                          # PORCHLIGHT LIVE meter (px)
# D-063 DETAIL. The order has a number and a voice (the LONGHORN app, in Bolo
# Capital's push-notification register), the debtor comes out of the house and
# calls it in if you dawdle, and the contract ends on a CARD with the bonuses
# you earned: no clips posted, under the window, no heat, and a medal by time.
const ORDER_NO := "3319"
const OWNER_CALL_SECONDS := 14.0                  # standing by the truck this long: she calls it in
const OWNER_RANGE := 20.0                         # ...if the truck is still this close
const OWNER_FOLLOW_SECONDS := 45.0
const OWNER_DOOR := Vector3(-9.0, 0.0, 6.0)       # where she comes out, off the target's tail
const BONUS_NO_CLIPS := 150; const BONUS_TIME := 100; const BONUS_NO_HEAT := 100
const TIME_GOLD := 240.0; const TIME_SILVER := 360.0

enum State { IDLE, DRIVE_TO, HOOK_IT, DELIVER, COMPLETE }

# ============================== STATE ========================================
var main_ref: Node = null
var state: State = State.IDLE
var _rng := RandomNumberGenerator.new()
var _t := 0.0                       # visual clock (bob, blink)
var _tow: Node = null               # lazily bound tow_hook peer
var _target: RigidBody3D = null
var _target_yaw := 0.0              # drawn once per contract; reused on reset
var _drone: Node3D = null; var _drone_rig: Node3D = null   # rig bobs/blinks
var _cam_mat: StandardMaterial3D = null
var _drone_spawned := false         # one drone per contract, even after escape
var _drone_leaving := false; var _drone_exit_t := 0.0
var _expose_t := 0.0; var _signal_t := 0.0
var _abandon_t := 0.0; var _cooldown_t := 0.0
var _was_near := false              # abandon clock arms only after first approach
var _dispatch_beam: Node3D = null; var _target_beam: Node3D = null
var _ui: CanvasLayer = null; var _objective: Label = null
var _bar_bg: ColorRect = null; var _bar_fill: ColorRect = null
var _flash_text := ""; var _flash_left := 0.0
var _start_t := 0.0; var _clips := 0; var _heat0 := 0; var _heat_max := 0
var _arrived := false; var _owner: RigidBody3D = null
var _owner_t := 0.0; var _owner_called := false

func setup(main: Node) -> void:
	main_ref = main; _rng.seed = RNG_SEED
	if bool(main.get("smoke_mode")):
		set_physics_process(false); set_process(false)  # smoke gate: fully inert
		return
	_build_dispatch(); _build_ui()
	# No on_vehicle_changed: Tab swap -> tow_hook releases -> _on_tow_released.

# ============================== PER-FRAME ====================================
func _physics_process(delta: float) -> void:
	if main_ref == null: return
	_try_bind_tow()
	var player := _player()
	match state:
		State.IDLE: _tick_idle(player)
		State.DRIVE_TO: _tick_seek(player, delta, true)
		State.HOOK_IT: _tick_seek(player, delta, false)
		State.DELIVER: _tick_deliver()
		State.COMPLETE:
			_cooldown_t -= delta
			if _cooldown_t <= 0.0: state = State.IDLE
	if state != State.IDLE and state != State.COMPLETE:
		_tick_details(delta)
	if is_instance_valid(_target) and _target.global_position.y < FALL_RESET_Y:
		_target.global_transform = _target_transform()   # fell out of world
		_target.linear_velocity = Vector3.ZERO; _target.angular_velocity = Vector3.ZERO
	_tick_drone(player, delta)

func _tick_idle(player: RigidBody3D) -> void:
	if player == null: return
	var p := player.global_position
	if Vector2(p.x - DISPATCH_POS.x, p.z - DISPATCH_POS.z).length() <= DISPATCH_RADIUS \
			and absf(p.y - DISPATCH_POS.y) < 4.0 and player.linear_velocity.length() < DISPATCH_MAX_SPEED:
		_start_mission()

## Shared DRIVE_TO / HOOK_IT tick: hook detection, proximity promote, abandon.
func _tick_seek(player: RigidBody3D, delta: float, promote: bool) -> void:
	if not is_instance_valid(_target):
		_abort_mission(); return   # target vanished under us — lapse cleanly
	if _hooked_on_target():
		_enter_deliver(); return   # poll fallback in case the signal bound late
	if player == null: return
	var d := player.global_position.distance_to(_target.global_position)
	if promote and d <= HOOK_ZONE:
		state = State.HOOK_IT
		if not _arrived:
			_arrived = true
			_say("Unit located. Back to the tailgate and hook. Do not engage the debtor.")
	# Latch: dispatch sits ~896 m from the brisket — beyond ABANDON_DISTANCE at
	# accept time — so the abandon clock only arms after the first approach.
	if d <= ABANDON_DISTANCE:
		_was_near = true; _abandon_t = 0.0
	elif _was_near:
		_abandon_t += delta
		if _abandon_t >= ABANDON_SECONDS: _abort_mission()

func _tick_deliver() -> void:
	if not is_instance_valid(_target):
		_abort_mission(); return
	# Signals cover releases synchronously; this poll is the late-bind backup.
	if not _hooked_on_target():
		if _in_pad(_target.global_position): _complete_mission()
		else: state = State.HOOK_IT; _flash("RE-HOOK THE BRISKET")

# ============================== TRANSITIONS ==================================
func _start_mission() -> void:
	_abandon_t = 0.0; _expose_t = 0.0; _signal_t = 0.0; _drone_spawned = false
	_was_near = false; _arrived = false; _clips = 0; _owner_t = 0.0; _owner_called = false
	_start_t = Time.get_ticks_msec() / 1000.0
	_heat0 = _heat(); _heat_max = _heat0
	_target_yaw = _rng.randf_range(-0.35, 0.35) + PI * 0.5
	_spawn_target(); state = State.DRIVE_TO; _flash("HOOK AND LADDER")
	_say("ORDER %s · BARON BRISKET · 96-month note, four payments behind. STONEBRIDLE RANCH, the cul-de-sac. Recovery window 6:00. Your rating: 4.7★" % ORDER_NO, 6.0)
	_say("HOA cameras on file. Longhorn Wrecker & Recovery is not liable for what Porchlight posts.", 4.5)

func _enter_deliver() -> void:
	state = State.DELIVER; _abandon_t = 0.0
	if not _drone_spawned:
		_drone_spawned = true; _spawn_drone(); _flash("PORCHLIGHT IS WATCHING")
		_spawn_owner()

func _complete_mission() -> void:
	var board := _peer("repo_board")
	var took := Time.get_ticks_msec() / 1000.0 - _start_t
	var rows: Array = [["RECOVERY", "$%d" % PAYOUT]]
	var total := PAYOUT
	if board != null and board.has_method("add_money"):
		board.call("add_money", PAYOUT, "CONTRACT: HOOK AND LADDER")
		if _clips == 0:
			board.call("add_money", BONUS_NO_CLIPS, "NO CLIPS POSTED"); total += BONUS_NO_CLIPS
			rows.append(["NO CLIPS POSTED", "+$%d" % BONUS_NO_CLIPS])
		if took <= TIME_SILVER:
			board.call("add_money", BONUS_TIME, "INSIDE THE WINDOW"); total += BONUS_TIME
			rows.append(["INSIDE THE WINDOW", "+$%d" % BONUS_TIME])
		if _heat_max <= _heat0:
			board.call("add_money", BONUS_NO_HEAT, "NO HEAT DRAWN"); total += BONUS_NO_HEAT
			rows.append(["NO HEAT DRAWN", "+$%d" % BONUS_NO_HEAT])
	rows.append(["TIME", "%d:%02d" % [int(took) / 60, int(took) % 60]])
	rows.append(["TOTAL", "$%d" % total])
	var medal := "GOLD" if took <= TIME_GOLD and _clips == 0 else ("SILVER" if took <= TIME_SILVER else "BRONZE")
	_despawn_target(); _despawn_drone(); _despawn_owner()
	state = State.COMPLETE; _cooldown_t = COOLDOWN_SECONDS
	if _peer("mission_kit") == null: _flash("CONTRACT COMPLETE")   # the card says it otherwise
	_card("CONTRACT COMPLETE", "ORDER %s · HOOK AND LADDER" % ORDER_NO, rows, medal)
	_say("Recovery logged. Payout net of platform fee (0% this quarter). Bolo Capital thanks you for your hustle.", 5.0)

func _abort_mission(reason := "lapsed") -> void:
	_despawn_target(); _despawn_drone(); _despawn_owner()
	state = State.IDLE; _abandon_t = 0.0; _flash("CONTRACT LAPSED")  # re-arms now
	if reason == "busted":
		_say("Order %s reassigned. A Longhorn unit in the county impound is a Longhorn problem. Rating impact: −0.3★" % ORDER_NO, 5.0)
	elif reason == "down":
		_say("Order %s reassigned. Get well soon. Rating impact: −0.3★" % ORDER_NO, 4.5)
	else:
		_say("Order %s reassigned. Recovery window exceeded. Rating impact: −0.3★" % ORDER_NO, 4.5)

# ============================== TOW EVENTS ===================================
func _try_bind_tow() -> void:
	if _tow != null and is_instance_valid(_tow): return
	_tow = _peer("tow_hook")
	if _tow == null: return
	for sig: String in ["hooked", "released"]:
		var cb: Callable = _on_tow_hooked if sig == "hooked" else _on_tow_released
		if _tow.has_signal(sig) and not _tow.is_connected(sig, cb): _tow.connect(sig, cb)

func _hooked_on_target() -> bool:
	if _tow == null or not is_instance_valid(_tow): return false
	var v: Variant = _tow.get("hooked_body")
	return v is Node and is_instance_valid(v) and v == _target

func _on_tow_hooked(body: Variant) -> void:
	if (state == State.DRIVE_TO or state == State.HOOK_IT) and body is Node \
			and body == _target and is_instance_valid(_target):
		_enter_deliver()

func _on_tow_released(body: Variant) -> void:
	if state != State.DELIVER or not is_instance_valid(_target): return
	if not (body is Node3D) or body != _target: return   # not our brisket
	if _in_pad(_target.global_position): _complete_mission()
	else: state = State.HOOK_IT; _flash("RE-HOOK THE BRISKET")  # snap/early drop

func _in_pad(p: Vector3) -> bool:
	return absf(p.x - PAD_CENTER.x) <= PAD_HALF.x \
		and absf(p.z - PAD_CENTER.z) <= PAD_HALF.y and p.y < PAD_MAX_Y

# ============================== THE BRISKET ==================================
func _spawn_target() -> void:
	_despawn_target()
	var body := RigidBody3D.new(); body.name = "BaronBrisket"; body.mass = TARGET_MASS
	var pm := PhysicsMaterial.new(); pm.friction = TARGET_FRICTION
	body.physics_material_override = pm
	body.add_to_group("towable"); body.add_to_group("mission_target")
	var col := CollisionShape3D.new(); var shape := BoxShape3D.new()
	shape.size = TARGET_SIZE; col.shape = shape; body.add_child(col)
	var mat := _mat3(TARGET_COLOR, 0.35); mat.metallic = 0.4   # pearl sheen
	_box_part(body, TARGET_SIZE, Vector3.ZERO, mat)
	_box_part(body, Vector3(2.0, 0.65, 2.8), Vector3(0, TARGET_SIZE.y * 0.5 + 0.3, 0.3),
		_mat3(Color(0.25, 0.30, 0.34), 0.3))   # cab glass
	var wmesh := CylinderMesh.new()
	wmesh.top_radius = 0.38; wmesh.bottom_radius = 0.38; wmesh.height = 0.28
	var wmat := _mat3(Color(0.10, 0.10, 0.11), 0.8)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new(); w.mesh = wmesh; w.material_override = wmat
		w.rotation_degrees = Vector3(0, 0, 90)
		w.position = Vector3(c.x * (TARGET_SIZE.x * 0.5 + 0.02), -TARGET_SIZE.y * 0.5 + 0.16, c.y * 1.95)
		body.add_child(w)
	add_child(body)
	body.global_transform = _target_transform()
	_target = body

func _target_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, _target_yaw),
		TARGET_POS + Vector3(0, TARGET_SIZE.y * 0.5 + 0.15, 0))

func _despawn_target() -> void:
	if is_instance_valid(_target): _target.queue_free()  # tow self-releases freed
	_target = null

# ============================== THE DRONE ====================================
func _spawn_drone() -> void:
	_despawn_drone()
	_drone = Node3D.new(); _drone.name = "PorchlightDrone"
	add_child(_drone)   # Node3D under a plain Node: transform acts as global
	_drone.position = TARGET_POS + Vector3(0, 1.8, 0)   # rises out of the court
	_drone_rig = Node3D.new(); _drone.add_child(_drone_rig)
	_box_part(_drone_rig, Vector3(0.72, 0.2, 0.72), Vector3.ZERO, _mat3(Color(0.16, 0.17, 0.18), 0.6))
	_box_part(_drone_rig, Vector3(0.36, 0.16, 0.36), Vector3(0, 0.18, 0), _mat3(Color(0.82, 0.80, 0.75), 0.5))
	var rmesh := CylinderMesh.new()
	rmesh.top_radius = 0.26; rmesh.bottom_radius = 0.26; rmesh.height = 0.05
	var rmat := _mat3(Color(0.30, 0.31, 0.33), 0.4)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var r := MeshInstance3D.new(); r.mesh = rmesh; r.material_override = rmat
		r.position = Vector3(c.x * 0.45, 0.15, c.y * 0.45); _drone_rig.add_child(r)
	_cam_mat = _mat3(Color(0.9, 0.08, 0.08), 0.3)
	_cam_mat.emission_enabled = true; _cam_mat.emission = Color(1.0, 0.05, 0.05)
	_box_part(_drone_rig, Vector3(0.12, 0.12, 0.12), Vector3(0, -0.15, 0), _cam_mat)
	var spot := SpotLight3D.new(); spot.rotation_degrees = Vector3(-90, 0, 0)  # down
	spot.spot_range = 20.0; spot.spot_angle = 35.0; spot.light_energy = 2.5
	spot.light_color = Color(1.0, 0.97, 0.9); _drone_rig.add_child(spot)
	_drone_leaving = false; _drone_exit_t = 0.0; _signal_t = 0.0; _expose_t = 0.0

func _despawn_drone() -> void:
	if is_instance_valid(_drone): _drone.queue_free()
	_drone = null; _drone_rig = null; _cam_mat = null; _drone_leaving = false

func _tick_drone(player: RigidBody3D, delta: float) -> void:
	if _drone == null: return
	if not is_instance_valid(_drone): _drone = null; return
	if _drone_leaving:
		_drone.position.y += DRONE_EXIT_SPEED * delta; _drone_exit_t += delta
		if _drone_exit_t >= DRONE_EXIT_SECONDS: _despawn_drone()
		return
	if player == null: return   # no player body: hover in place, keep filming
	var desired := player.global_position + Vector3.UP * DRONE_HOVER
	_drone.position = _drone.position.move_toward(desired, DRONE_SPEED * delta)
	var flat := player.global_position - _drone.position; flat.y = 0.0
	if flat.length() > 1.0: _drone.rotation.y = atan2(-flat.x, -flat.z)  # face player
	var d := _drone.global_position.distance_to(player.global_position)
	if d <= EXPOSURE_RANGE and _los_clear(player):
		_expose_t += delta
		if _expose_t >= EXPOSURE_SECONDS:
			_expose_t = 0.0   # clip uploaded: +1 heat, then it keeps filming
			_clips += 1
			var pol := _peer("police")
			if pol != null and pol.has_method("add_heat"): pol.call("add_heat", 1, "FILMED BY THE HOA")
	if d > SIGNAL_LOST_DISTANCE:
		_signal_t += delta
		if _signal_t >= SIGNAL_LOST_SECONDS:
			_drone_leaving = true; _drone_exit_t = 0.0; _flash("DRONE: SIGNAL LOST")
	else: _signal_t = 0.0

## Ray drone -> player chest, excluding only the player (the drone has no
## physics body); empty hit = clear line of sight.
func _los_clear(player: RigidBody3D) -> bool:
	var space := player.get_world_3d().direct_space_state
	if space == null: return false
	var q := PhysicsRayQueryParameters3D.create(_drone.global_position,
		player.global_position + Vector3.UP * 0.4, 0xFFFFFFFF, [player.get_rid()])
	return space.intersect_ray(q).is_empty()

# ============================== VISUAL FRAME =================================
func _process(delta: float) -> void:
	_t += delta
	if _dispatch_beam != null and is_instance_valid(_dispatch_beam):
		_dispatch_beam.visible = state == State.IDLE   # lit only when armed
	if _target_beam != null and is_instance_valid(_target_beam):
		if is_instance_valid(_target) and state != State.COMPLETE:
			_target_beam.visible = true
			_target_beam.position = _target.global_position * Vector3(1, 0, 1)
		else: _target_beam.visible = false
	if _drone_rig != null and is_instance_valid(_drone_rig):
		_drone_rig.position.y = sin(_t * TAU * DRONE_BOB_HZ) * DRONE_BOB_AMPLITUDE
		if _cam_mat != null:
			_cam_mat.emission_energy_multiplier = 3.5 if fmod(_t * 2.0, 1.0) < 0.5 else 0.4
	_update_ui(delta)

# ============================== WORLD PROPS ==================================
func _build_dispatch() -> void:
	# Gold against a pale Texas sky is the lowest-contrast beacon in the game, so
	# it still runs the hottest of the five: 0.30 x 1.45 = 0.435 added, against
	# the repo target's 0.39. Under the old MIX blend these ran 0.38 x 1.9 —
	# roughly double — because half of that was being spent cancelling the crush
	# the blend itself introduced. Additive needs less light to read brighter.
	_dispatch_beam = _make_beam(BEAM_HEIGHT, 2.2, DISPATCH_COLOR, 0.30, 1.45, 4.0, 0.12)
	_dispatch_beam.position = DISPATCH_POS
	_dispatch_beam.visible = true
	# Subtle white: the brisket is a car you walk up to, not a place you drive
	# to, so it is the quietest beacon in the game (0.22 x 1.05 = 0.231) and its
	# 12 m column is gone entirely by the time you are close enough to hook it (the
	# kit hides every column inside 26 m).
	_target_beam = _make_beam(TARGET_BEAM_HEIGHT, 1.9, Color.WHITE, 0.22, 1.05, 4.0, 0.11)
	# Sign: static pole + emissive board + Label3D, 3 m east, facing west.
	var pole := StaticBody3D.new()
	var pcol := CollisionShape3D.new(); var pshape := BoxShape3D.new()
	pshape.size = Vector3(0.22, 2.7, 0.22); pcol.shape = pshape; pole.add_child(pcol)
	_box_part(pole, pshape.size, Vector3.ZERO, _mat3(Color(0.5, 0.5, 0.5), 0.8))
	# x+9 matches the impound sign offset and clears the northbound traffic
	# lane (centre x=712.5) — at x+3 the pole sat inside the lane.
	pole.position = DISPATCH_POS + Vector3(9.0, 1.35, 0); add_child(pole)
	var bmat := _mat3(DISPATCH_COLOR, 0.6)
	bmat.emission_enabled = true; bmat.emission = DISPATCH_COLOR; bmat.emission_energy_multiplier = 0.6
	var board := MeshInstance3D.new(); var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.15, 1.0, 4.6); board.mesh = bmesh; board.material_override = bmat
	board.position = DISPATCH_POS + Vector3(9.0, 3.2, 0); add_child(board)
	# M22 FIT: `font_size = 60` drew 4.89 m across a 4.6 m board — the name ran
	# off both ends of the yard sign. Fitted, and set in FASCIA: this is a
	# lit yard board on a wrecker lot, not a highway panel.
	var sign := SIGN.make("LONGHORN DISPATCH", SIGN.FASCIA,
		Color(0.12, 0.10, 0.05), 4.40, 0.82, 60, 0.0075)
	sign.position = DISPATCH_POS + Vector3(8.9, 3.2, 0)
	sign.rotation.y = -PI * 0.5   # front normal west, toward downtown traffic
	add_child(sign)

## Shared objective-beacon look (D-015). The origin of the returned node is the
## GROUND point being marked — no half-height offset at the call site.
func _make_beam(height: float, width: float, color: Color, alpha: float,
		energy: float, ring: float, ring_alpha := -1.0) -> Node3D:
	var n := BEACON.beacon(color, height, width, alpha, energy, ring, ring_alpha)
	n.visible = false; add_child(n)
	return n

# ============================== DETAIL (D-063) ===============================
## Per tick while a contract is live: the heat high-water mark (for the NO HEAT
## bonus), the owner's clock, and the two ways a contract ends badly.
func _tick_details(delta: float) -> void:
	_heat_max = maxi(_heat_max, _heat())
	var of := _peer("on_foot")
	if of != null and of.has_method("player_down") and of.call("player_down") == true:
		var mode: Variant = of.get("_card_mode")
		_abort_mission("busted" if mode == "busted" else "down")
		return
	if is_instance_valid(_owner) and not _owner_called:
		var player := _player()
		if player != null and player.global_position.distance_to(_owner.global_position) <= OWNER_RANGE:
			_owner_t += delta
			if _owner_t >= OWNER_CALL_SECONDS:
				_owner_called = true
				var pol := _peer("police")
				if pol != null and pol.has_method("add_heat"): pol.call("add_heat", 1, "THE OWNER CALLED IT IN")
				_say_as("THE OWNER", "I've got your plate and I've got Porchlight. They're on their way.", 4.5)
		else:
			_owner_t = maxf(_owner_t - delta, 0.0)

## She comes out of the house the moment the chain goes taut.
func _spawn_owner() -> void:
	_despawn_owner()
	var peds := _peer("pedestrians")
	var player := _player()
	if peds == null or player == null or not peds.has_method("spawn_follower_at"): return
	var at := TARGET_POS + OWNER_DOOR + Vector3(0, 1.075, 0)
	var b: Variant = peds.call("spawn_follower_at", at, (player.global_position - at).normalized(), player, OWNER_FOLLOW_SECONDS)
	if b is RigidBody3D:
		_owner = b; _owner.add_to_group("mission_owner")
		_say_as("THE OWNER", "That's my truck! I'm four days late, not four months — who told you four months?!", 4.5)

func _despawn_owner() -> void:
	if is_instance_valid(_owner): _owner.queue_free()
	_owner = null

func _heat() -> int:
	var pol := _peer("police")
	var hv: Variant = pol.get("heat") if pol != null else null
	return int(hv) if hv is int else 0

func _say(line: String, seconds := 4.5) -> void:
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("say"): kit.call("say", "LONGHORN · RECOVERY", line, seconds)

func _say_as(who: String, line: String, seconds := 4.5) -> void:
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("say"): kit.call("say", who, line, seconds)

func _card(title: String, sub: String, rows: Array, medal: String) -> void:
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("card"): kit.call("card", title, sub, rows, medal)

func _box_part(parent: Node, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm; mi.material_override = mat; mi.position = pos
	parent.add_child(mi)

func _mat3(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new(); m.albedo_color = color; m.roughness = rough
	return m

func _player() -> RigidBody3D:
	if main_ref == null: return null
	var v: Variant = main_ref.get("vehicle")
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null

func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n): return n
	return null

# ============================== UI ===========================================
## Slot: bottom-center, y in [-240,-190] from the bottom edge — objective line
## on top, PORCHLIGHT LIVE meter beneath; both above the repo flash zone.
func _build_ui() -> void:
	_ui = CanvasLayer.new(); _ui.layer = 14
	add_child(_ui)
	_objective = Label.new()
	_objective.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_objective.offset_left = -420.0; _objective.offset_right = 420.0
	_objective.offset_top = -240.0; _objective.offset_bottom = -210.0
	_objective.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_objective.add_theme_font_size_override("font_size", OBJECTIVE_FONT)
	_objective.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8))
	_objective.add_theme_constant_override("outline_size", 6)
	_objective.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	_objective.visible = false; _ui.add_child(_objective)
	_bar_bg = ColorRect.new(); _bar_bg.color = Color(0, 0, 0, 0.55)
	_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar_bg.offset_left = -BAR_WIDTH * 0.5; _bar_bg.offset_right = BAR_WIDTH * 0.5
	_bar_bg.offset_top = -208.0; _bar_bg.offset_bottom = -192.0
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_bar_bg.visible = false; _ui.add_child(_bar_bg)
	_bar_fill = ColorRect.new(); _bar_fill.color = Color(0.95, 0.15, 0.15, 0.9)
	_bar_fill.position = Vector2(2, 2); _bar_fill.size = Vector2(0, 12)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar_fill)
	var bl := Label.new(); bl.text = "PORCHLIGHT LIVE"
	bl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bl.add_theme_font_size_override("font_size", 11)
	bl.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_bar_bg.add_child(bl)

func _flash(text: String) -> void:
	_flash_text = text; _flash_left = FLASH_SECONDS

func _update_ui(delta: float) -> void:
	if _ui == null or _objective == null: return
	if _flash_left > 0.0:   # title/event flash reuses the objective label, big
		_flash_left = maxf(0.0, _flash_left - delta)
		_objective.add_theme_font_size_override("font_size", FLASH_FONT)
		_objective.text = _flash_text; _objective.modulate.a = clampf(_flash_left, 0.0, 1.0)
		_objective.visible = true
	else:
		_objective.add_theme_font_size_override("font_size", OBJECTIVE_FONT)
		_objective.modulate.a = 1.0; _objective.visible = state != State.IDLE
		_objective.text = _objective_text()
	var filming := _drone != null and is_instance_valid(_drone) and not _drone_leaving
	if _bar_bg != null:
		_bar_bg.visible = filming
		if filming and _bar_fill != null:
			_bar_fill.size = Vector2(
				(BAR_WIDTH - 4.0) * clampf(_expose_t / EXPOSURE_SECONDS, 0.0, 1.0), 12.0)

func _objective_text() -> String:
	var player := _player()
	match state:
		State.DRIVE_TO, State.HOOK_IT:
			var d := 0.0
			if player != null and is_instance_valid(_target):
				d = player.global_position.distance_to(_target.global_position)
			var verb := "REPO ORDER: Baron Brisket — Stonebridle Ranch" if state == State.DRIVE_TO else "HOOK THE BRISKET"
			return "%s   %dm" % [verb, int(d)]
		State.DELIVER:
			var d2 := 0.0
			if is_instance_valid(_target):
				d2 = Vector2(_target.global_position.x - PAD_CENTER.x, _target.global_position.z - PAD_CENTER.z).length()
			return "DELIVER TO IMPOUND   %dm" % int(d2)
		State.COMPLETE:
			return "LONGHORN DISPATCH RE-ARM %ds" % int(ceilf(_cooldown_t))
	return ""
