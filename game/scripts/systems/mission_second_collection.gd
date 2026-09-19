extends Node
## MISSION: THE SECOND COLLECTION — EL DORADO GRANDE's second scripted mission.
##
## Longhorn Wrecker's night board hands Book order 4471: an Ampt Motors
## Wedgeneer — "Overflow Fellowship Outreach Fleet, Unit 3" — ninety-four days
## past due on paper Bolo Capital bought last quarter. The car sits in the
## reserved stall at the arena doors, booted and plugged into a fleet
## immobiliser pedestal, and three Watchman masts sweep the plaza. The order is
## lawful. The debtor has twelve campuses and a jet.
##
## TWO WAYS THROUGH, both playable end to end:
##   QUIET — leave the rig out in the parking ocean, walk in CROUCHED under the
##           sweeps, tap the SeedFaith giving kiosk at the doors for a courtesy
##           release. No alarm, no heat, and the paper stays clean.
##   LOUD  — break the pedestal with a bullet, a bat, or a bumper. +2 heat, the
##           campus goes to LOCKDOWN, and you haul a screaming car out past
##           Blessing One with cruisers inbound.
## A third axis rides on top of both: the three Watchman flood housings are
## shootable. Ammo and a few minutes buy darkness.
##
## Systems exercised: tow_hook (the Hook), police (heat -> foot cops deploy on
## the man), combat/melee (breaking the pedestal or the floods), the M16 crouch
## state (halves exposure), the interact verb (the kiosk, an ATM in a chasuble),
## radio (the diegetic-score bonus at delivery), repo_board (money + Respect).
##
## State machine: IDLE -> APPROACH -> LOCKED -> HOOK_IT -> DELIVER -> COMPLETE
## (cooldown), repeatable. Peers are bound lazily and null-checked — the systems
## loader is alphabetical, so police/repo_board/radio/tow_hook all load AFTER
## this file. Fully inert in smoke mode.

const BEACON := preload("res://scripts/world/beacon_kit.gd")

# ============================== TUNABLES =====================================
## No RNG anywhere in this file, on purpose. A sweep the player can LEARN beats
## a sweep the player can only survive — the three masts run on fixed phases at
## a fixed rate, so the gap through the plaza is the same gap every attempt.

# --- the night board (accept marker), at the mouth of the campus entry drive --
const SIGN := preload("res://scripts/world/sign_kit.gd")
const BOARD_POS := Vector3(142.0, 0.0, 596.0)     # on Overflow's entry drive
const BOARD_RADIUS := 8.0                         # roll-in trigger radius (m)
const BOARD_MAX_SPEED := 3.0                      # must be nearly stopped
const BOARD_COLOR := Color(0.95, 0.83, 0.45)      # Overflow's marquee gold
# Beacons (D-015 / D-032). Both were 60 m constant-width boxes; then tapered
# top-faded shafts that still alpha-MIXED a veil over everything behind them.
# Now ADDITIVE and range-driven (scripts/world/beacon_kit.gd) — a beacon can
# brighten what is behind it and nothing else, and the column fades out inside
# 26 m so the ground corona carries the arrival. The accept board is a fixed
# landmark you are driving TO, so it is the taller of the two; the target
# beacon sits on a car you are already beside.
const BEAM_HEIGHT := 16.0                         # accept-board beacon
const TARGET_BEAM_HEIGHT := 12.0                  # the car itself

# --- the target: order 4471 -------------------------------------------------
const TARGET_POS := Vector3(142.0, 0.0, 690.0)    # reserved stall, 13 m off the doors
const TARGET_YAW := PI                            # nose to the glass, rear to the drive
const TARGET_SIZE := Vector3(2.06, 1.40, 4.86)    # a wedge, lower than any truck
const TARGET_MASS := 2150.0                       # it is mostly battery
const TARGET_COLOR := Color(0.93, 0.90, 0.85)     # pearl under the wrap
const WRAP_COLOR := Color(0.86, 0.69, 0.26)       # SeedFaith gold
const TARGET_FRICTION := 0.2                      # junker wheel fiction (M3 parity)
const FALL_RESET_Y := -30.0                       # fell out of the world -> re-park

# --- the immobiliser pedestal ------------------------------------------------
const PEDESTAL_POS := Vector3(142.0, 0.0, 695.4)  # at the Wedgeneer's nose
const PEDESTAL_SIZE := Vector3(0.52, 1.26, 0.44)
const PEDESTAL_MASS := 90.0
const RAM_SPEED := 6.0                            # m/s: a bumper counts as a tool
const RAM_RADIUS := 3.6

# --- the SeedFaith giving kiosk (the quiet release) --------------------------
const KIOSK_POS := Vector3(148.0, 0.0, 699.2)     # under the door canopy
const KIOSK_SIZE := Vector3(0.64, 1.52, 0.50)
const KIOSK_REACH := 3.0                          # on-foot interact radius (m)

# --- the Watchmen (campus security masts) ------------------------------------
const MAST_POS: Array[Vector3] = [
	Vector3(112.0, 0.0, 664.0),   # west flank, off the parking ocean
	Vector3(176.0, 0.0, 664.0),   # east flank, clear of the marquee
	Vector3(120.0, 0.0, 696.0),   # the doors — this one owns the kiosk approach
]
const MAST_PHASE: Array[float] = [0.0, 2.0943951, 4.1887902]   # 0, 120, 240 deg
const MAST_HEIGHT := 9.0
const HEAD_Y := 9.15                              # flood housing centre (m)
const SWEEP_RATE := 0.55                          # rad/s at rest
const SWEEP_ALERT_MULT := 1.9                     # ...and in lockdown
const SWEEP_HALF := 0.42                          # gameplay cone half-angle (rad)
const WATCH_RANGE := 46.0
const WATCH_ALERT_BONUS := 16.0                   # lockdown reach (m)
const WATCH_MIN := 5.0                            # hugging the pole is a blind spot
## The meter ACCUMULATES ACROSS PASSES on purpose. One pass of one mast is
## 2*SWEEP_HALF/SWEEP_RATE = 1.53 s, so if the meter reset between passes no
## amount of standing in the open would ever get you made. Tuned against the
## plaza, where all three masts reach: a man standing gains ~4.6 s and loses
## ~1.4 s per 11.4 s revolution and is made in about one turn; crouched he
## nets +0.2 a turn and can cross at will; a wrecker parked out there is made
## in seven seconds. Out in the parking ocean only one mast reaches and the
## decay wins outright — which is why the smart play is to leave the rig there.
const EXPOSE_SECONDS := 3.2                       # lit this long -> SPOTTED
const EXPOSE_DECAY := 0.20                        # per second out of the light
const CROUCH_FACTOR := 0.34                       # the M16 crouch, paying rent
const VEHICLE_FACTOR := 1.5                       # a wrecker on a church plaza at 2 a.m.
const SPOT_COOLDOWN := 6.0                        # grace after being made
const CHEST_STAND := 1.20                         # LOS aim points (feet origin)
const CHEST_CROUCH := 0.70
const CHEST_VEHICLE := 0.40

# --- delivery + economy ------------------------------------------------------
const PAD_CENTER := Vector3(709.0, 0.0, 558.0)    # mirrors repo_board's impound pad
const PAD_HALF := Vector2(7.0, 5.0)
const PAD_MAX_Y := 4.0
const PAYOUT_BASE := 1100
const PAYOUT_CLEAN := 550                         # no alarm AND never spotted
const PAYOUT_RADIO := 75                          # diegetic-only mission scoring
const RESPECT_CLEAN := 4
const RESPECT_LOUD := 1
const COOLDOWN_SECONDS := 30.0

# --- fail forward ------------------------------------------------------------
const HOOK_ZONE := 70.0                           # APPROACH -> LOCKED radius
const ABANDON_DISTANCE := 600.0                   # only while the car is still there
const ABANDON_SECONDS := 20.0
const ALARM_HEAT := 2
const SPOT_HEAT := 1

# --- HUD ---------------------------------------------------------------------
## Assigned bottom-centre slot: y in [-400,-310]. Below it, in order, live the
## slab flash (-310..-255), the M3 mission line (-240..-190), the combat health
## band (-196..-166) and the repo flash (-170..-120). Nothing of ours crosses.
const OBJECTIVE_FONT := 18
const FLASH_FONT := 28
const PROMPT_FONT := 17
const FLASH_SECONDS := 3.0
const SPOT_FLASH_SECONDS := 2.4
const BAR_WIDTH := 320.0

enum State { IDLE, APPROACH, LOCKED, HOOK_IT, DELIVER, COMPLETE }

# ============================== STATE ========================================
var main_ref: Node = null
var state: State = State.IDLE
var _t := 0.0                        # visual clock (blink)
var _watch_t := 0.0                  # sweep clock, physics-stepped: deterministic
var _tow: Node = null                # lazily bound tow_hook peer
var _target: RigidBody3D = null
var _pedestal: RigidBody3D = null
var _kiosk: StaticBody3D = null
var _masts: Array[Dictionary] = []   # {root, pivot, housing, light, lens, phase, alive}
var _expose_t := 0.0
var _spot_grace := 0.0
var _abandon_t := 0.0
var _cooldown_t := 0.0
var _was_near := false
var _released := false               # the boot is off, by either road
var _loud := false                   # the alarm went off: no CLEAN PAPER
var _spotted := false                # a Watchman made you: no CLEAN PAPER
var _lit := false                    # a live sweep has you RIGHT NOW
var _board_beam: Node3D = null
var _target_beam: Node3D = null
var _ui: CanvasLayer = null
var _objective: Label = null
var _prompt: Label = null
var _bar_bg: ColorRect = null
var _bar_fill: ColorRect = null
var _bar_label: Label = null
var _flash_text := ""
var _flash_left := 0.0


func setup(main: Node) -> void:
	main_ref = main
	if bool(main.get("smoke_mode")):
		set_physics_process(false)   # smoke gate: fully inert, no props, no UI
		set_process(false)
		return
	_build_board()
	_build_ui()
	# No on_vehicle_changed: a Tab swap makes tow_hook release, which reaches us
	# through _on_tow_released exactly like the M3 contract.


# ============================== PER-FRAME ====================================
func _physics_process(delta: float) -> void:
	if main_ref == null:
		return
	_try_bind_tow()
	if _player_down() and state != State.IDLE and state != State.COMPLETE:
		_abort_mission("ORDER 4471 GOES BACK ON THE BOARD")
		return
	var actor := _actor()
	match state:
		State.IDLE:
			_tick_idle(actor)
		State.APPROACH:
			_tick_seek(actor, delta, true)
		State.LOCKED:
			_tick_locked(actor, delta)
		State.HOOK_IT:
			_tick_seek(actor, delta, false)
		State.DELIVER:
			_tick_deliver()
		State.COMPLETE:
			_cooldown_t -= delta
			if _cooldown_t <= 0.0:
				state = State.IDLE
	if is_instance_valid(_target) and _target.global_position.y < FALL_RESET_Y:
		_target.global_transform = _target_transform()   # fell out of the world
		_target.linear_velocity = Vector3.ZERO
		_target.angular_velocity = Vector3.ZERO
	_tick_watchmen(actor, delta)


func _tick_idle(actor: Node3D) -> void:
	if actor == null:
		return
	var p := actor.global_position
	if Vector2(p.x - BOARD_POS.x, p.z - BOARD_POS.z).length() <= BOARD_RADIUS \
			and absf(p.y - BOARD_POS.y) < 4.0 and _actor_speed(actor) < BOARD_MAX_SPEED:
		_start_mission()


## Shared APPROACH / HOOK_IT tick: hook detection, proximity promote, abandon.
func _tick_seek(actor: Node3D, delta: float, promote: bool) -> void:
	if not is_instance_valid(_target):
		_abort_mission("CONTRACT LAPSED")
		return
	if _hooked_on_target():
		_enter_deliver()   # poll fallback in case the signal bound late
		return
	if actor == null:
		return
	var d := actor.global_position.distance_to(_target.global_position)
	if promote and d <= HOOK_ZONE:
		state = State.LOCKED
	# The board sits 94 m from the stall, so this latch arms on the first
	# approach and never on the accept frame (M3's lesson, kept).
	if d <= ABANDON_DISTANCE:
		_was_near = true
		_abandon_t = 0.0
	elif _was_near:
		_abandon_t += delta
		if _abandon_t >= ABANDON_SECONDS:
			_abort_mission("CONTRACT LAPSED")


## LOCKED: the car is frozen, unhooked and un-towable until the boot comes off.
## Three roads out — the kiosk (quiet), violence to the pedestal or the car
## itself (loud), or a bumper at speed (also loud, and the funniest).
func _tick_locked(actor: Node3D, delta: float) -> void:
	if not is_instance_valid(_target):
		_abort_mission("CONTRACT LAPSED")
		return
	if _broken_open():
		_release_target(true)
		return
	if _rammed():
		_release_target(true)
		return
	if _kiosk_in_reach() and InputMap.has_action("interact") \
			and Input.is_action_just_pressed("interact"):
		_release_target(false)
		return
	if actor == null:
		return
	var d := actor.global_position.distance_to(_target.global_position)
	if d <= ABANDON_DISTANCE:
		_was_near = true
		_abandon_t = 0.0
	elif _was_near:
		_abandon_t += delta
		if _abandon_t >= ABANDON_SECONDS:
			_abort_mission("CONTRACT LAPSED")


func _tick_deliver() -> void:
	if not is_instance_valid(_target):
		_abort_mission("CONTRACT LAPSED")
		return
	# Signals cover releases synchronously; this poll is the late-bind backup.
	if not _hooked_on_target():
		if _in_pad(_target.global_position):
			_complete_mission()
		else:
			state = State.HOOK_IT
			_flash("RE-HOOK THE WEDGENEER")


# ============================== TRANSITIONS ==================================
func _start_mission() -> void:
	_abandon_t = 0.0
	_expose_t = 0.0
	_spot_grace = 0.0
	_was_near = false
	_released = false
	_loud = false
	_spotted = false
	_lit = false
	_watch_t = 0.0
	_spawn_target()
	_spawn_pedestal()
	_spawn_kiosk()
	_spawn_masts()
	state = State.APPROACH
	_flash("THE SECOND COLLECTION")
	_say("ORDER 4471 · AMPT WEDGENEER · Overflow Fellowship, north plaza, stall 9. Booted to a fleet immobiliser. Lienholder of record: Bolo Capital (acquired Q2).", 6.5)
	_say("Quiet work pays better. The kiosk prints a courtesy release if you can find the words. Or you can't.", 5.0)


## The boot comes off. `loud` means somebody heard it: +2 heat, the masts go to
## alert, and the CLEAN PAPER bonus is gone. Quiet means the kiosk printed a
## courtesy release and the campus never woke up.
func _release_target(loud: bool) -> void:
	if _released:
		return
	_released = true
	if is_instance_valid(_target):
		_target.freeze = false
		if not _target.is_in_group("towable"):
			_target.add_to_group("towable")
	if loud:
		_loud = true
		if is_instance_valid(_pedestal) and _pedestal.freeze:
			_pedestal.freeze = false      # it goes over either way
		_add_heat(ALARM_HEAT, "TRIPPED THE ALARM")
		_flash("LOCKDOWN — TWELVE CAMPUSES, ONE ALARM")
		_say("ALARM EVENT LOGGED. Twelve campuses notified. Longhorn Wrecker & Recovery is not liable. Hook it and go.", 5.0)
	else:
		_flash("RELEASE PRINTED. THE LORD PROVIDES A ROUTING NUMBER.")
		_say("Courtesy release printed. Campus asleep. CLEAN PAPER bonus in play — keep it that way.", 4.5)
	state = State.HOOK_IT


func _enter_deliver() -> void:
	state = State.DELIVER
	_abandon_t = 0.0


func _complete_mission() -> void:
	var board := _peer("repo_board")
	var clean := not _loud and not _spotted
	if board != null and board.has_method("add_money"):
		board.call("add_money", PAYOUT_BASE, "ORDER 4471: THE SECOND COLLECTION")
		if clean:
			board.call("add_money", PAYOUT_CLEAN, "CLEAN PAPER — NOBODY WOKE UP")
		if _radio_on():
			board.call("add_money", PAYOUT_RADIO, "HAULIN' MUSIC")
	if board != null and board.has_method("add_respect"):
		board.call("add_respect", RESPECT_CLEAN if clean else RESPECT_LOUD,
			"OVERFLOW TOOK THE LOSS")
	_teardown_props()
	state = State.COMPLETE
	_cooldown_t = COOLDOWN_SECONDS
	if _peer("mission_kit") == null:   # the card says it otherwise
		_flash("CLEAN PAPER — NOBODY WOKE UP" if clean else "CONTRACT COMPLETE")
	# D-063: the card, and the app's closing line.
	var rows: Array = [["RECOVERY", "$%d" % PAYOUT_BASE]]
	var total := PAYOUT_BASE
	if clean:
		rows.append(["CLEAN PAPER — NOBODY WOKE UP", "+$%d" % PAYOUT_CLEAN]); total += PAYOUT_CLEAN
	if _radio_on():
		rows.append(["HAULIN' MUSIC", "+$%d" % PAYOUT_RADIO]); total += PAYOUT_RADIO
	rows.append(["RESPECT", "%+d" % (RESPECT_CLEAN if clean else RESPECT_LOUD)])
	rows.append(["TOTAL", "$%d" % total])
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("card"):
		kit.call("card", "CONTRACT COMPLETE", "ORDER 4471 · THE SECOND COLLECTION", rows, "GOLD" if clean else "SILVER")
	_say("Recovery logged. The receipt lists the lienholder in eight-point type. Nobody reads receipts. Bolo Capital thanks you for your hustle.", 6.0)


## Fail forward: the order lapses, the props go away, the board re-arms NOW.
## Heat you earned is yours to keep — the church does not un-call the police.
func _abort_mission(reason: String) -> void:
	_teardown_props()
	state = State.IDLE
	_abandon_t = 0.0
	_flash(reason)
	_say("Order 4471 reassigned. Rating impact: −0.3★", 4.0)


## D-063: the LONGHORN app talks in Bolo Capital's push-notification voice.
func _say(line: String, seconds := 4.5) -> void:
	var kit := _peer("mission_kit")
	if kit != null and kit.has_method("say"):
		kit.call("say", "LONGHORN · RECOVERY", line, seconds)


func _teardown_props() -> void:
	_despawn_target()
	_despawn_pedestal()
	_despawn_kiosk()
	_despawn_masts()
	_expose_t = 0.0
	_spot_grace = 0.0
	_lit = false


# ============================== RELEASE TESTS ================================
## Combat and melee both do the same thing to a frozen rigid body that is not a
## ped, an officer or a cruiser: they thaw it. So "did somebody hit this" is a
## freeze check on the pedestal — and on the car, because shooting the debtor's
## car open is a perfectly good, perfectly loud way to do this job.
func _broken_open() -> bool:
	if is_instance_valid(_pedestal) and not _pedestal.freeze:
		return true
	if is_instance_valid(_target) and not _target.freeze:
		return true
	return false


## A bumper is a tool. Only the vehicle counts — Book cannot body-check a
## charge pedestal at 6 m/s, and the on-foot actor never should.
func _rammed() -> bool:
	var v := _vehicle()
	if v == null:
		return false
	if v.linear_velocity.length() < RAM_SPEED:
		return false
	var p := v.global_position
	return Vector2(p.x - PEDESTAL_POS.x, p.z - PEDESTAL_POS.z).length() <= RAM_RADIUS


func _kiosk_in_reach() -> bool:
	if not is_instance_valid(_kiosk) or not _on_foot():
		return false
	var ch := _character()
	if ch == null:
		return false
	var p := ch.global_position
	return Vector2(p.x - KIOSK_POS.x, p.z - KIOSK_POS.z).length() <= KIOSK_REACH \
		and absf(p.y - KIOSK_POS.y) < 4.0


# ============================== THE WATCHMEN =================================
## Three masts sweeping the plaza on fixed phases. Being lit fills a meter;
## a full meter is +1 heat and a fresh six-second grace. Crouching is worth
## roughly three times a stand-up walk; sitting in the rig is worth half.
func _tick_watchmen(actor: Node3D, delta: float) -> void:
	if _masts.is_empty():
		_lit = false
		return
	var live := state == State.APPROACH or state == State.LOCKED \
		or state == State.HOOK_IT or state == State.DELIVER
	var rate := SWEEP_RATE * (SWEEP_ALERT_MULT if _loud else 1.0)
	_watch_t += delta * rate
	for m: Dictionary in _masts:
		var pivot: Variant = m.get("pivot")
		if pivot is Node3D and is_instance_valid(pivot):
			(pivot as Node3D).rotation.y = float(m["phase"]) + _watch_t
		var housing: Variant = m.get("housing")
		if bool(m["alive"]) and housing is RigidBody3D and is_instance_valid(housing) \
				and not (housing as RigidBody3D).freeze:
			m["alive"] = false           # shot out, batted off, or knocked loose
			var lit_node: Variant = m.get("light")
			if lit_node is Node3D and is_instance_valid(lit_node):
				(lit_node as Node3D).visible = false
			var lens: Variant = m.get("lens")
			if lens is Node3D and is_instance_valid(lens):
				(lens as Node3D).visible = false
			if live:
				_flash("A WATCHMAN GOES DARK")
	if _spot_grace > 0.0:
		_spot_grace = maxf(0.0, _spot_grace - delta)
	if not live or actor == null:
		_lit = false
		_expose_t = maxf(0.0, _expose_t - EXPOSE_DECAY * delta)
		return
	_lit = _in_any_sweep(actor)
	if _lit and _spot_grace <= 0.0:
		_expose_t += delta * _expose_rate()
		if _expose_t >= EXPOSE_SECONDS:
			_expose_t = 0.0
			_spot_grace = SPOT_COOLDOWN
			_spotted = true
			_add_heat(SPOT_HEAT, "SPOTTED BY A WATCHMAN")
			_flash_for("A WATCHMAN HAS YOU. SMILE, FRIEND.", SPOT_FLASH_SECONDS)
	elif not _lit:
		_expose_t = maxf(0.0, _expose_t - EXPOSE_DECAY * delta)


func _expose_rate() -> float:
	if not _on_foot():
		return VEHICLE_FACTOR
	return CROUCH_FACTOR if _crouched() else 1.0


func _in_any_sweep(actor: Node3D) -> bool:
	var reach := WATCH_RANGE + (WATCH_ALERT_BONUS if _loud else 0.0)
	var aim := actor.global_position + Vector3.UP * _chest_offset()
	for m: Dictionary in _masts:
		if not bool(m["alive"]):
			continue
		var base: Vector3 = m["pos"]
		var flat := Vector2(aim.x - base.x, aim.z - base.z)
		var d := flat.length()
		if d > reach or d < WATCH_MIN:
			continue
		var yaw := float(m["phase"]) + _watch_t
		var facing := Vector2(-sin(yaw), -cos(yaw))   # pivot local -Z, flattened
		if facing.dot(flat / d) < cos(SWEEP_HALF):
			continue
		if _los_clear(base + Vector3(0.0, HEAD_Y, 0.0), aim, actor):
			return true
	return false


func _chest_offset() -> float:
	if not _on_foot():
		return CHEST_VEHICLE
	return CHEST_CROUCH if _crouched() else CHEST_STAND


## Ray head -> chest, excluding only the actor (masts have their own colliders,
## and we WANT the target car, the pedestal and the arena to block). An empty
## hit means the light reaches.
func _los_clear(from: Vector3, to: Vector3, actor: Node3D) -> bool:
	if not (actor is CollisionObject3D):
		return false
	var space := actor.get_world_3d().direct_space_state
	if space == null:
		return false
	var q := PhysicsRayQueryParameters3D.create(from, to, 0xFFFFFFFF,
		[(actor as CollisionObject3D).get_rid()])
	return space.intersect_ray(q).is_empty()


# ============================== TOW EVENTS ===================================
func _try_bind_tow() -> void:
	if _tow != null and is_instance_valid(_tow):
		return
	_tow = _peer("tow_hook")
	if _tow == null:
		return
	for sig: String in ["hooked", "released"]:
		var cb: Callable = _on_tow_hooked if sig == "hooked" else _on_tow_released
		if _tow.has_signal(sig) and not _tow.is_connected(sig, cb):
			_tow.connect(sig, cb)


func _hooked_on_target() -> bool:
	if _tow == null or not is_instance_valid(_tow):
		return false
	var v: Variant = _tow.get("hooked_body")
	return v is Node and is_instance_valid(v) and v == _target


func _on_tow_hooked(body: Variant) -> void:
	if state == State.HOOK_IT and body is Node and body == _target \
			and is_instance_valid(_target):
		_enter_deliver()


func _on_tow_released(body: Variant) -> void:
	if state != State.DELIVER or not is_instance_valid(_target):
		return
	if not (body is Node3D) or body != _target:
		return   # not our Wedgeneer
	if _in_pad(_target.global_position):
		_complete_mission()
	else:
		state = State.HOOK_IT
		_flash("RE-HOOK THE WEDGENEER")


func _in_pad(p: Vector3) -> bool:
	return absf(p.x - PAD_CENTER.x) <= PAD_HALF.x \
		and absf(p.z - PAD_CENTER.z) <= PAD_HALF.y and p.y < PAD_MAX_Y


# ============================== THE WEDGENEER ================================
## Ampt Motors Wedgeneer (naming bible §7), wearing the campus wrap. Built here
## as a mission prop, not a drivable profile — if it ever becomes drivable it
## needs data/vehicles/wedgeneer.json and a §7a row, per the bible's rule.
func _spawn_target() -> void:
	_despawn_target()
	var body := RigidBody3D.new()
	body.name = "OutreachWedgeneer"
	body.mass = TARGET_MASS
	var pm := PhysicsMaterial.new()
	pm.friction = TARGET_FRICTION
	body.physics_material_override = pm
	body.add_to_group("mission_target")   # NOT "towable" and NOT "junker" until
	body.freeze = true                    # the boot comes off — repo_board only
	var col := CollisionShape3D.new()     # ever pays for its own junkers.
	var shape := BoxShape3D.new()
	shape.size = TARGET_SIZE
	col.shape = shape
	body.add_child(col)
	var paint := _mat3(TARGET_COLOR, 0.28)
	paint.metallic = 0.45
	_box_part(body, TARGET_SIZE, Vector3.ZERO, paint)
	# The wedge: a short glasshouse set back and tapered, not a second brick.
	_box_part(body, Vector3(1.78, 0.56, 2.55), Vector3(0.0, TARGET_SIZE.y * 0.5 + 0.26, -0.16),
		_mat3(Color(0.16, 0.18, 0.21), 0.22))
	# Gold wrap: belt stripes down both flanks + a nose bar.
	var wrap := _mat3(WRAP_COLOR, 0.35)
	wrap.metallic = 0.5
	for side: float in [-1.0, 1.0]:
		_box_part(body, Vector3(0.03, 0.24, 3.9),
			Vector3(side * (TARGET_SIZE.x * 0.5 + 0.01), 0.08, 0.0), wrap)
	_box_part(body, Vector3(1.5, 0.16, 0.03),
		Vector3(0.0, 0.16, -TARGET_SIZE.z * 0.5 - 0.01), wrap)
	for side: float in [-1.0, 1.0]:
		# A fleet wrap fills the door; this one was using 36 % of the flank.
		var tag := SIGN.make("OVERFLOW FELLOWSHIP", SIGN.FASCIA,
			Color(0.30, 0.24, 0.08), 2.60, 0.20, 60, 0.0042)
		tag.position = Vector3(side * (TARGET_SIZE.x * 0.5 + 0.03), 0.44, 0.35)
		tag.rotation.y = PI * 0.5 * side
		body.add_child(tag)
		var unit := SIGN.make("OUTREACH FLEET · UNIT 3", SIGN.STENCIL,
			Color(0.34, 0.28, 0.11), 2.20, 0.13, 34, 0.0042)
		unit.position = Vector3(side * (TARGET_SIZE.x * 0.5 + 0.03), 0.24, 0.35)
		unit.rotation.y = PI * 0.5 * side
		body.add_child(unit)
	var wmesh := CylinderMesh.new()
	wmesh.top_radius = 0.34
	wmesh.bottom_radius = 0.34
	wmesh.height = 0.26
	var wmat := _mat3(Color(0.09, 0.09, 0.10), 0.8)
	for c: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var w := MeshInstance3D.new()
		w.mesh = wmesh
		w.material_override = wmat
		w.rotation_degrees = Vector3(0, 0, 90)
		w.position = Vector3(c.x * (TARGET_SIZE.x * 0.5 + 0.02),
			-TARGET_SIZE.y * 0.5 + 0.14, c.y * 1.62)
		body.add_child(w)
	# The boot: a fat orange clamp on the near front wheel, so "locked" reads
	# from the driver's seat without a single line of UI.
	var boot := _mat3(Color(0.93, 0.42, 0.08), 0.55)
	_box_part(body, Vector3(0.28, 0.72, 0.72),
		Vector3(-(TARGET_SIZE.x * 0.5 + 0.14), -TARGET_SIZE.y * 0.5 + 0.16, 1.62), boot)
	# TRANSFORM BEFORE add_child (D-017 lesson): a physics body placed after it
	# joins the tree reports a one-step teleport velocity whose swept path can
	# speculatively thaw nearby frozen bodies — and the pedestal 5 m away IS the
	# alarm. Under a plain Node parent, local transform is the global one.
	body.transform = _target_transform()
	add_child(body)
	_target = body
	# Subtle white: it stands on a car you park next to, not a place you drive
	# to — the quietest beacon in the game (0.22 x 1.05 = 0.231 added), and its
	# 12 m column is gone by the time you are close enough to board it.
	_target_beam = _make_beam(TARGET_BEAM_HEIGHT, 1.9, Color.WHITE, 0.22, 1.05, 4.0, 0.11)
	_target_beam.visible = true


func _target_transform() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, TARGET_YAW),
		TARGET_POS + Vector3(0, TARGET_SIZE.y * 0.5 + 0.18, 0))


func _despawn_target() -> void:
	if is_instance_valid(_target):
		_target.queue_free()   # tow_hook self-releases a freed body
	_target = null
	if is_instance_valid(_target_beam):
		_target_beam.queue_free()
	_target_beam = null


# ============================== THE PEDESTAL =================================
## Frozen so it stands there; thawed the moment anything hits it, which is
## exactly how combat.gd and melee.gd treat any frozen prop that is not a
## person. That thaw IS the alarm.
func _spawn_pedestal() -> void:
	_despawn_pedestal()
	var body := RigidBody3D.new()
	body.name = "FleetImmobiliser"
	body.mass = PEDESTAL_MASS
	body.freeze = true
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = PEDESTAL_SIZE
	col.shape = shape
	body.add_child(col)
	_box_part(body, PEDESTAL_SIZE, Vector3.ZERO, _mat3(Color(0.22, 0.24, 0.26), 0.6))
	var face := _mat3(Color(0.10, 0.32, 0.20), 0.3)
	face.emission_enabled = true
	face.emission = Color(0.15, 0.95, 0.45)
	face.emission_energy_multiplier = 0.9
	_box_part(body, Vector3(0.34, 0.26, 0.04),
		Vector3(0.0, 0.34, -PEDESTAL_SIZE.z * 0.5 - 0.01), face)
	# M22 FIT: `font_size = 30` put 1.32 m of label on a 0.52 m pedestal —
	# 253 %, the worst ratio in the game. Machine-plate register: small,
	# wide-tracked STENCIL, fitted to the face it is screwed to.
	var tag := SIGN.make("OVERFLOW FLEET\nCHARGE + IMMOBILISER\nUNIT 3 · HOLD 4471",
		SIGN.STENCIL, Color(0.88, 0.88, 0.84),
		PEDESTAL_SIZE.x * 0.88, PEDESTAL_SIZE.y * 0.46, 30, 0.0038)
	tag.position = Vector3(0.0, 0.05, -PEDESTAL_SIZE.z * 0.5 - 0.02)
	tag.rotation.y = PI          # D-016: it hangs on the -Z face, so face -Z
	body.add_child(tag)
	# The cable: a slack gold line down to the car's nose. Visual only.
	var cable := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(0.05, 0.05, 2.4)
	cable.mesh = cm
	cable.material_override = _mat3(Color(0.72, 0.60, 0.22), 0.45)
	cable.position = Vector3(0.0, -0.42, -1.35)
	body.add_child(cable)
	body.transform = Transform3D(Basis.IDENTITY,      # before add_child, always
		PEDESTAL_POS + Vector3(0, PEDESTAL_SIZE.y * 0.5, 0))
	add_child(body)
	_pedestal = body


func _despawn_pedestal() -> void:
	if is_instance_valid(_pedestal):
		_pedestal.queue_free()
	_pedestal = null


# ============================== THE KIOSK ====================================
## A SeedFaith giving kiosk (naming bible §10) at the doors. The satire is the
## frictionless money machine, never the people who use it: the same terminal
## that takes a tithe at 3 a.m. will also print a lien release, because both are
## just Fleet Services menu items to whoever wrote the firmware.
func _spawn_kiosk() -> void:
	_despawn_kiosk()
	var body := StaticBody3D.new()
	body.name = "SeedFaithKiosk"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = KIOSK_SIZE
	col.shape = shape
	body.add_child(col)
	_box_part(body, KIOSK_SIZE, Vector3.ZERO, _mat3(Color(0.90, 0.88, 0.83), 0.5))
	var screen := _mat3(Color(0.12, 0.16, 0.24), 0.2)
	screen.emission_enabled = true
	screen.emission = Color(0.35, 0.72, 1.0)
	screen.emission_energy_multiplier = 1.1
	_box_part(body, Vector3(0.46, 0.34, 0.03),
		Vector3(0.0, 0.44, -KIOSK_SIZE.z * 0.5 - 0.01), screen)
	var crown := _mat3(BOARD_COLOR, 0.4)
	crown.emission_enabled = true
	crown.emission = BOARD_COLOR
	crown.emission_energy_multiplier = 0.7
	_box_part(body, Vector3(KIOSK_SIZE.x + 0.06, 0.16, KIOSK_SIZE.z + 0.06),
		Vector3(0.0, KIOSK_SIZE.y * 0.5 + 0.06, 0.0), crown)
	# M22 FIT: 1.36 m of label on a 0.64 m kiosk (212 %). The brand gets the
	# lit-panel treatment it would really have; the instruction gets small type.
	var tag := SIGN.make("SEEDFAITH", SIGN.CHANNEL, Color(0.20, 0.18, 0.10),
		KIOSK_SIZE.x * 0.86, 0.16, 40, 0.0040)
	tag.position = Vector3(0.0, 0.20, -KIOSK_SIZE.z * 0.5 - 0.02)
	tag.rotation.y = PI          # D-016: it hangs on the -Z face, so face -Z
	body.add_child(tag)
	var sow := SIGN.make("GIVE 24/7 · TAP TO SOW", SIGN.STENCIL,
		Color(0.24, 0.22, 0.13), KIOSK_SIZE.x * 0.86, 0.10, 26, 0.0040)
	sow.position = Vector3(0.0, 0.06, -KIOSK_SIZE.z * 0.5 - 0.02)
	sow.rotation.y = PI
	body.add_child(sow)
	body.position = KIOSK_POS + Vector3(0, KIOSK_SIZE.y * 0.5, 0)
	body.rotation.y = 0.0
	add_child(body)
	_kiosk = body


func _despawn_kiosk() -> void:
	if is_instance_valid(_kiosk):
		_kiosk.queue_free()
	_kiosk = null


# ============================== THE MASTS ====================================
func _spawn_masts() -> void:
	_despawn_masts()
	for i in MAST_POS.size():
		var base: Vector3 = MAST_POS[i]
		var root := Node3D.new()
		root.name = "Watchman%d" % (i + 1)
		root.position = base            # Node3D under a plain Node: local IS global
		add_child(root)
		var pole := StaticBody3D.new()
		var pcol := CollisionShape3D.new()
		var pshape := BoxShape3D.new()
		pshape.size = Vector3(0.30, MAST_HEIGHT, 0.30)
		pcol.shape = pshape
		pole.add_child(pcol)
		_box_part(pole, pshape.size, Vector3.ZERO, _mat3(Color(0.42, 0.44, 0.46), 0.7))
		pole.position = Vector3(0, MAST_HEIGHT * 0.5, 0)
		root.add_child(pole)
		# The housing is the shootable part and it NEVER moves under its own
		# parent — a frozen body dragged by a rotating pivot is the M14 teleport
		# bug waiting to happen. The sweep is the pivot; the target is static.
		var housing := RigidBody3D.new()
		housing.name = "WatchmanHead%d" % (i + 1)
		housing.mass = 22.0
		housing.freeze = true
		var hcol := CollisionShape3D.new()
		var hshape := BoxShape3D.new()
		hshape.size = Vector3(1.10, 0.52, 0.86)
		hcol.shape = hshape
		housing.add_child(hcol)
		_box_part(housing, hshape.size, Vector3.ZERO, _mat3(Color(0.34, 0.35, 0.37), 0.55))
		housing.position = Vector3(0, HEAD_Y, 0)   # set BEFORE add_child, always
		root.add_child(housing)
		var pivot := Node3D.new()
		pivot.position = Vector3(0, HEAD_Y, 0)
		root.add_child(pivot)
		var lensmat := _mat3(Color(1.0, 0.96, 0.86), 0.2)
		lensmat.emission_enabled = true
		lensmat.emission = Color(1.0, 0.95, 0.80)
		lensmat.emission_energy_multiplier = 3.0
		var lens := MeshInstance3D.new()
		var lm := BoxMesh.new()
		lm.size = Vector3(0.62, 0.40, 0.10)
		lens.mesh = lm
		lens.material_override = lensmat
		lens.position = Vector3(0, -0.12, -0.50)
		pivot.add_child(lens)
		var light := SpotLight3D.new()
		light.rotation_degrees = Vector3(-35, 0, 0)   # down and out along -Z
		light.position = Vector3(0, -0.10, -0.45)
		light.spot_range = 62.0
		light.spot_angle = 24.0          # matches SWEEP_HALF: what you see is the rule
		light.spot_attenuation = 0.6
		light.light_energy = 6.5
		light.light_color = Color(1.0, 0.97, 0.88)
		light.shadow_enabled = false
		pivot.add_child(light)
		_masts.append({
			"pos": base, "root": root, "pivot": pivot, "housing": housing,
			"light": light, "lens": lens,
			"phase": MAST_PHASE[i] if i < MAST_PHASE.size() else 0.0,
			"alive": true,
		})


func _despawn_masts() -> void:
	for m: Dictionary in _masts:
		var root: Variant = m.get("root")
		if root is Node and is_instance_valid(root):
			(root as Node).queue_free()
	_masts.clear()


# ============================== VISUAL FRAME =================================
func _process(delta: float) -> void:
	_t += delta
	if _board_beam != null and is_instance_valid(_board_beam):
		_board_beam.visible = state == State.IDLE   # lit only when armed
	if _target_beam != null and is_instance_valid(_target_beam):
		if is_instance_valid(_target) and state != State.COMPLETE:
			_target_beam.visible = true
			_target_beam.position = _target.global_position * Vector3(1, 0, 1)
		else:
			_target_beam.visible = false
	if _loud:
		var pulse := 4.2 if fmod(_t * 2.4, 1.0) < 0.5 else 1.4
		for m: Dictionary in _masts:
			var lens: Variant = m.get("lens")
			if bool(m["alive"]) and lens is MeshInstance3D and is_instance_valid(lens):
				var mat: Variant = (lens as MeshInstance3D).material_override
				if mat is StandardMaterial3D:
					(mat as StandardMaterial3D).emission_energy_multiplier = pulse
	_update_ui(delta)


# ============================== WORLD PROPS ==================================
func _build_board() -> void:
	# Marquee gold against a pale sky: same low-contrast problem as the Longhorn
	# dispatch beacon, so it runs the same hottest-of-five 0.30 x 1.45 = 0.435.
	_board_beam = _make_beam(BEAM_HEIGHT, 2.2, BOARD_COLOR, 0.30, 1.45, 4.0, 0.12)
	_board_beam.position = BOARD_POS
	_board_beam.visible = true
	# The night board: a pole, an emissive panel, and two lines of Longhorn's
	# own copy. Set 18 m east of the drive centreline — the campus drive is
	# 28 m wide (x 128..156), so the pole stands off the pavement.
	var pole := StaticBody3D.new()
	var pcol := CollisionShape3D.new()
	var pshape := BoxShape3D.new()
	pshape.size = Vector3(0.22, 2.7, 0.22)
	pcol.shape = pshape
	pole.add_child(pcol)
	_box_part(pole, pshape.size, Vector3.ZERO, _mat3(Color(0.5, 0.5, 0.5), 0.8))
	pole.position = BOARD_POS + Vector3(18.0, 1.35, 0)
	add_child(pole)
	var bmat := _mat3(BOARD_COLOR, 0.6)
	bmat.emission_enabled = true
	bmat.emission = BOARD_COLOR
	bmat.emission_energy_multiplier = 0.6
	var board := MeshInstance3D.new()
	var bmesh := BoxMesh.new()
	bmesh.size = Vector3(0.15, 1.3, 5.0)
	board.mesh = bmesh
	board.material_override = bmat
	board.position = BOARD_POS + Vector3(18.0, 3.3, 0)
	add_child(board)
	# M22 FIT: 7.72 m of lettering on a 5.0 m board — 154 %, both lines running
	# off both ends. The company motto is canon (§8, "We Own That Too") and now
	# gets its own line at its own weight instead of being a run-on.
	var sign := SIGN.make("LONGHORN WRECKER", SIGN.FASCIA,
		Color(0.12, 0.10, 0.05), 4.60, 0.52, 54, 0.0075)
	sign.position = BOARD_POS + Vector3(17.9, 3.52, 0)
	sign.rotation.y = -PI * 0.5   # front normal west, back toward the drive
	add_child(sign)
	var motto := SIGN.make("NIGHT BOARD · WE OWN THAT TOO", SIGN.STENCIL,
		Color(0.16, 0.13, 0.06), 4.60, 0.30, 40, 0.0075)
	motto.position = BOARD_POS + Vector3(17.9, 3.02, 0)
	motto.rotation.y = -PI * 0.5
	add_child(motto)


## Shared objective-beacon look (D-015). The origin of the returned node is the
## GROUND point being marked — no half-height offset at the call site.
func _make_beam(height: float, width: float, color: Color, alpha: float,
		energy: float, ring: float, ring_alpha := -1.0) -> Node3D:
	var n := BEACON.beacon(color, height, width, alpha, energy, ring, ring_alpha)
	n.visible = false
	add_child(n)
	return n


func _box_part(parent: Node, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)


func _mat3(color: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	return m


# ============================== PEER ACCESS ==================================
func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null


func _actor() -> Node3D:
	if main_ref == null:
		return null
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a as Node3D
	return _vehicle()


func _vehicle() -> RigidBody3D:
	var v: Variant = main_ref.get("vehicle") if main_ref != null else null
	if v is RigidBody3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v as RigidBody3D
	return null


func _character() -> Node3D:
	var c: Variant = main_ref.get("character") if main_ref != null else null
	if c is Node3D and is_instance_valid(c) and (c as Node).is_inside_tree():
		return c as Node3D
	return null


func _on_foot() -> bool:
	return main_ref != null and bool(main_ref.get("on_foot")) and _character() != null


func _crouched() -> bool:
	var ch := _character()
	return ch != null and bool(ch.get_meta("is_crouched", false))


func _actor_speed(a: Node3D) -> float:
	if a is RigidBody3D:
		return (a as RigidBody3D).linear_velocity.length()
	if a is CharacterBody3D:
		return (a as CharacterBody3D).velocity.length()
	return 0.0


func _player_down() -> bool:
	var of := _peer("on_foot")
	if of != null and of.has_method("player_down"):
		return bool(of.call("player_down"))
	return false


func _add_heat(n: int, reason: String = "") -> void:
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"):
		pol.call("add_heat", n, reason)


## Story canon: jobs are soundtracked by the getaway vehicle's own dial. A dead
## radio at the impound gate costs you the score bonus and nothing else.
func _radio_on() -> bool:
	var r := _peer("radio")
	if r == null:
		return false
	var s: Variant = r.get("_station")
	return s is int and int(s) >= 0


# ============================== UI ===========================================
## Slot: bottom-centre, y in [-400,-310] — prompt on top, objective line, then
## the WATCHMEN meter. Clear of slab (-310..-255), the M3 mission (-240..-190),
## the combat band (-196..-166) and the repo flash (-170..-120).
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 15
	add_child(_ui)
	_prompt = _hud_label(PROMPT_FONT, Color(1.0, 0.93, 0.72))
	_prompt.offset_left = -420.0
	_prompt.offset_right = 420.0
	_prompt.offset_top = -400.0
	_prompt.offset_bottom = -374.0
	_prompt.visible = false
	_ui.add_child(_prompt)
	_objective = _hud_label(OBJECTIVE_FONT, Color(0.95, 0.92, 0.8))
	_objective.offset_left = -420.0
	_objective.offset_right = 420.0
	_objective.offset_top = -370.0
	_objective.offset_bottom = -340.0
	_objective.visible = false
	_ui.add_child(_objective)
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0, 0, 0, 0.55)
	_bar_bg.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_bar_bg.offset_left = -BAR_WIDTH * 0.5
	_bar_bg.offset_right = BAR_WIDTH * 0.5
	_bar_bg.offset_top = -338.0
	_bar_bg.offset_bottom = -322.0
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE   # HUD law (D-016)
	_bar_bg.visible = false
	_ui.add_child(_bar_bg)
	_bar_fill = ColorRect.new()
	_bar_fill.color = Color(0.98, 0.78, 0.20, 0.9)
	_bar_fill.position = Vector2(2, 2)
	_bar_fill.size = Vector2(0, 12)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar_fill)
	_bar_label = Label.new()
	_bar_label.text = "THE WATCHMEN"
	_bar_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bar_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_bar_label.add_theme_font_size_override("font_size", 11)
	_bar_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	_bar_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar_label)


func _hud_label(size: int, color: Color) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE   # HUD law (D-016)
	return l


func _flash(text: String) -> void:
	_flash_for(text, FLASH_SECONDS)


func _flash_for(text: String, seconds: float) -> void:
	_flash_text = text
	_flash_left = seconds


func _update_ui(delta: float) -> void:
	if _ui == null or _objective == null:
		return
	if _flash_left > 0.0:   # title/event flash reuses the objective label, big
		_flash_left = maxf(0.0, _flash_left - delta)
		_objective.add_theme_font_size_override("font_size", FLASH_FONT)
		_objective.text = _flash_text   # D-155: the HUD draws this text; the label stays hidden
		_objective.modulate.a = clampf(_flash_left, 0.0, 1.0)
		_objective.visible = false   # D-155
	else:
		_objective.add_theme_font_size_override("font_size", OBJECTIVE_FONT)
		_objective.modulate.a = 1.0
		_objective.visible = false   # D-155
		_objective.text = _objective_text()
	if _prompt != null:
		var show_prompt := state == State.LOCKED and _kiosk_in_reach()
		_prompt.visible = show_prompt
		if show_prompt:
			_prompt.text = "[G]  SEEDFAITH KIOSK — FLEET SERVICES › COURTESY RELEASE"
	var watching := not _masts.is_empty() and state != State.COMPLETE \
		and state != State.IDLE
	if _bar_bg != null:
		_bar_bg.visible = watching
		if watching:
			if _bar_fill != null:
				_bar_fill.size = Vector2(
					(BAR_WIDTH - 4.0) * clampf(_expose_t / EXPOSE_SECONDS, 0.0, 1.0), 12.0)
				_bar_fill.color = Color(0.98, 0.25, 0.18, 0.92) if _loud \
					else Color(0.98, 0.78, 0.20, 0.9)
			if _bar_label != null:
				if _loud:
					_bar_label.text = "THE WATCHMEN — LOCKDOWN"
				elif _lit:
					_bar_label.text = "THE WATCHMEN — YOU ARE IN THE LIGHT"
				else:
					_bar_label.text = "THE WATCHMEN"


func _objective_text() -> String:
	var actor := _actor()
	match state:
		State.APPROACH:
			var d := 0.0
			if actor != null and is_instance_valid(_target):
				d = actor.global_position.distance_to(_target.global_position)
			return "ORDER 4471: AMPT WEDGENEER — OVERFLOW FELLOWSHIP, NORTH PLAZA   %dm" % int(d)
		State.LOCKED:
			var d2 := 0.0
			if actor != null and is_instance_valid(_target):
				d2 = actor.global_position.distance_to(_target.global_position)
			return "IT'S BOOTED. PRINT A RELEASE AT THE KIOSK, OR BREAK THE PEDESTAL   %dm" % int(d2)
		State.HOOK_IT:
			var d3 := 0.0
			if actor != null and is_instance_valid(_target):
				d3 = actor.global_position.distance_to(_target.global_position)
			return "HOOK THE WEDGENEER — BRING THE WRECKER   %dm" % int(d3)
		State.DELIVER:
			var d4 := 0.0
			if is_instance_valid(_target):
				d4 = Vector2(_target.global_position.x - PAD_CENTER.x,
					_target.global_position.z - PAD_CENTER.z).length()
			return "HAUL IT TO THE IMPOUND   %dm" % int(d4)
		State.COMPLETE:
			return ""   # D-071: one objective line on screen
	return ""
