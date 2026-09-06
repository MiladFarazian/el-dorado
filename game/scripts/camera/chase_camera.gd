extends Camera3D
## EL DORADO GRANDE — chase / hood / orbit camera.
## main.gd instances this from CAMERA_SCRIPT_PATH and assigns `target` (the
## active vehicle) after spawning; the target can be swapped or freed at any
## moment (Tab cycles vehicles), so every frame is null-guarded.
## "toggle_camera" (C) cycles CHASE -> HOOD -> ORBIT. Godot forward is -Z, so
## "behind" the target is +basis.z.
## ON FOOT: when the target is a CharacterBody3D (or carries meta
## is_character), the vehicle modes are bypassed entirely for a mouse-orbit
## FOOT rig (plus an over-the-shoulder AIM rig while systems/combat reports
## is_aiming). C is ignored on foot — the hood rig is never valid for a body.
## The rig publishes `orbit_yaw`; player_character.gd reads it as its movement
## basis. Mouse motion is consumed ONLY on foot with the mouse captured, so
## vehicle behavior stays pixel-identical.

enum Mode { CHASE, HOOD, ORBIT }

# --- Tunables -------------------------------------------------------------
const CHASE_DISTANCE := 8.5           # metres behind target at rest
## M19 SPEED PULL-BACK. The M11 rig raised the camera with speed but never
## moved it BACK, so the FOV kick (70->85) was doing the whole job of selling
## pace and the car grew in frame as it got faster — exactly backwards. Pulling
## the boom out with speed keeps the car a roughly constant size while the world
## widens around it, which is the read GTA has. Reviewed and changed.
const CHASE_DIST_PER_MPS := 0.055     # extra boom length per m/s
const CHASE_DIST_MAX_BONUS := 2.2     # cap (m) — 10.7 m total at 38 m/s
const CHASE_HEIGHT := 3.5             # metres above target at rest
const CHASE_HEIGHT_PER_MPS := 0.045   # extra camera height per m/s of speed
const CHASE_HEIGHT_MAX_BONUS := 1.6   # cap on that extra height (m)
## M19 REVERSE LOOK. Reverse for REVERSE_LOOK_DELAY and the boom swings over
## the hood to face the way you are actually going, then eases back the moment
## you drive forward. Suppressed while the player is manually free-looking —
## a hand on the mouse always outranks an automatic camera.
const REVERSE_LOOK_SPEED := -2.0      # m/s along the car's own forward axis
const REVERSE_LOOK_DELAY := 0.35      # s of reversing before the swing starts
const REVERSE_LOOK_BLEND := 0.55      # s to swing the full half-turn
const REVERSE_LOOK_HEIGHT := -0.6     # m the boom drops while reversed (over
									  # the hood, not over the roof)
const CHASE_SMOOTH_K := 6.0           # exp-decay rate for position smoothing
const LOOK_AHEAD_TIME := 0.55         # aim point leads target by velocity * this
const LOOK_AHEAD_MAX := 12.0          # cap on look-ahead distance (m)
const LOOK_HEIGHT := 1.2              # aim slightly above the chassis
const FOV_BASE := 70.0
const FOV_MAX := 85.0                 # FOV kick fully open at FOV_FULL_SPEED
const FOV_FULL_SPEED := 38.0          # m/s (~85 mph)
const FOV_SMOOTH_K := 4.0             # exp-decay rate for FOV changes
const HOOD_OFFSET := Vector3(0.0, 1.05, -1.4)  # local offset: front is -Z
const HOOD_FOV := 95.0
const HOOD_LOOK_AHEAD := 40.0         # metres ahead the hood cam aims at
const ORBIT_RADIUS := 9.0
const ORBIT_HEIGHT := 3.0
const ORBIT_SPEED := 0.35             # radians/sec beauty-shot auto orbit
const ORBIT_FOV := 60.0
const TRANSITION_TIME := 0.3          # seconds to blend between modes
# --- On-foot rig ----------------------------------------------------------
const FOOT_DISTANCE := 4.0            # metres behind the shoulder pivot
const FOOT_SHOULDER_HEIGHT := 1.65    # pivot height above the feet (m)
const FOOT_SMOOTH_K := 16.0           # snappier than vehicle chase (6.0)
const FOOT_LOOK_AHEAD := 8.0          # metres past the pivot the rig aims at
const FOOT_FOV := 70.0
const FOOT_SPRINT_FOV_BONUS := 6.0    # slight kick while target.is_sprinting
const FOOT_FOV_K := 14.0              # foot-rig FOV exp-decay rate
const MOUSE_SENSITIVITY := 0.0028     # radians per mouse px
const PITCH_MIN_DEG := -60.0          # look-down clamp (M19: was -50; you must
									  # be able to look at your own feet, and at
									  # a body you just put on the pavement)
const PITCH_MAX_DEG := 45.0           # look-up clamp (M19: was 35; downtown is
									  # 140 m tall and the old clamp cut it off)
# --- M19 foot rig: off-centre framing, auto-centre, speed settle -------------
## THE PLAYER IS NOT DEAD CENTRE. A third-person action camera puts the body
## slightly to one side so the screen ahead of them is the read. This shifts the
## WHOLE follow rig (pivot, lens and look point together), so the framing moves
## but the aim does not: the centre ray still leaves the pivot down the barrel.
const FOOT_LATERAL := 0.30            # m the follow rig sits to the player's right
## AUTO-CENTRE (GTA's single most-felt camera behaviour): let go of the mouse
## while you are actually going somewhere and the view eases back behind your
## facing. It NEVER fights an active hand — the hold restarts on any motion —
## and it is off while aiming, where the yaw belongs to the player alone.
const FOOT_RECENTER_HOLD := 1.0       # s of no mouse input before it engages
const FOOT_RECENTER_K := 2.2          # exp-decay rate toward the body's facing
const FOOT_RECENTER_MIN_SPEED := 1.2  # m/s under this you are loitering, not
									  # travelling — hold the view still
const FOOT_RECENTER_MAX_RATE := 1.9   # rad/s ceiling, so it can never whip
## SPEED SETTLE: the boom eases out and the follow lag lengthens with speed, so
## a sprint pulls the camera back and lets the body run away from it for a beat
## before it catches up. A first-order lag, never noise — this is the opposite
## of shake and must never read as it.
const FOOT_DIST_PER_MPS := 0.075      # extra boom length per m/s
const FOOT_DIST_MAX_BONUS := 0.55     # cap on that (m)
const FOOT_SMOOTH_K_RUN := 9.0        # smoothing rate at FOOT_SETTLE_SPEED
const FOOT_SETTLE_SPEED := 7.6        # m/s at which the lag is fully long
const AIM_DISTANCE := 1.7             # over-the-shoulder rig
const AIM_LATERAL := 0.55             # lateral offset (m), SIGNED by _shoulder
const SHOULDER_SWAP_TIME := 0.16      # s to ease across (V) — fast, not a cut
const AIM_HEIGHT := 1.55              # pivot height above the feet (m)
const AIM_FOV := 50.0                 # M13: real zoom — was 55, aiming needs it
const AIM_LOOK_AHEAD := 30.0          # aim rig looks down the barrel
const AIM_BLEND_TIME := 0.12          # near-instant aim snap (s)
const AIM_SENS_MULT := 0.55           # M13: slower mouse while aiming (fine work)
# --- M16: crouch camera accommodation (reads the body's "is_crouched" meta) --
const CROUCH_PIVOT_DROP := 0.52       # metres both foot pivots sink when crouched
const CROUCH_BLEND_TIME := 0.18       # s to ease between stances
# --- M11: collision, shake, recoil, free-look -----------------------------
## D-050 FIX: the arm was a ZERO-WIDTH ray, so the near plane clipped geometry
## the ray sailed past. At near 0.1 and FOV 70 (16:9) the near-plane corner sits
## 0.175 m off the lens origin, so a 0.20 m sphere is the smallest shape that
## guarantees the whole near plane is outside whatever the cast cleared. Cast
## with `cast_motion`, which reports the safe fraction of the sweep — the same
## number a spring arm actually wants — instead of a first-hit point.
const CAM_SPHERE_R := 0.20            # swept probe radius (m) >= near-plane corner
const COLLIDE_MARGIN := 0.06          # extra clearance ON TOP of the sphere (m).
									  # M11's 0.42 was standing in for the sphere
									  # radius; with a real shape it can shrink,
									  # which BUYS BACK 0.16 m of framing.
const COLLIDE_MIN := 0.55             # never pull closer than this to the pivot
const COLLIDE_RETURN_K := 5.0         # ease back OUT when the wall clears
const TRAUMA_DECAY := 1.9             # trauma units/sec
const SHAKE_POS := 0.26               # metres of positional shake at trauma 1
const SHAKE_ROT := 0.055              # radians of rotational shake at trauma 1
const SHAKE_FREQ := 26.0              # noise sampling rate
const RECOIL_RECOVER := 9.0           # exp-decay rate back to zero
const FREELOOK_HOLD := 0.9            # s of no mouse input before recentring
const FREELOOK_RECENTER_K := 3.5
const FREELOOK_YAW_MAX := 2.6         # rad, how far around the car you can look
const FREELOOK_PITCH := Vector2(-0.5, 0.45)
# --------------------------------------------------------------------------

var target: Node3D
# Foot-rig orbit state. orbit_yaw is PUBLIC contract: player_character.gd
# builds its camera-relative movement basis from it.
var orbit_yaw := 0.0
# M13 sticky aim: combat.gd sets this each physics tick (1.0 = no target near
# the reticle; <1.0 = mouse slowed over a target). Only read while aiming.
var aim_friction := 1.0
## M19: PUBLIC alongside orbit_yaw (it was `_orbit_pitch`). +up, radians.
## player_character.gd reads it to aim the head; nothing else did, so the
## rename is contained. Clamped to PITCH_MIN_DEG..PITCH_MAX_DEG at every write.
var orbit_pitch := -0.15
var _foot_active := false
var _aim_w := 0.0                     # 0 = follow rig, 1 = aim rig

var _mode: int = Mode.CHASE
var _chase_pos := Vector3.ZERO        # chase mode's smoothed position state
var _orbit_angle := 0.0
var _transition_left := 0.0
var _from_pos := Vector3.ZERO         # snapshot taken when a mode switch begins
var _from_look := Vector3.ZERO
var _last_look := Vector3.FORWARD     # last aim point, reused as blend source
var _initialized := false
# M11 state.
var _trauma := 0.0                    # 0..1 shake energy, decays every frame
var _shake_t := 0.0
var _shake_rng := RandomNumberGenerator.new()
var _recoil_pitch := 0.0              # applied to the CAMERA only, so the gun
var _recoil_yaw := 0.0                # follows it but movement basis does not
var _boom := 1.0                      # 0..1 spring-arm extension (1 = clear)
var _look_yaw := 0.0                  # vehicle free-look offsets
var _look_pitch := 0.0
var _crouch_w := 0.0                  # M16: 0 = standing, 1 = fully crouched
var _look_idle := 0.0
# M19 state.
var _foot_idle := 0.0                 # s since the mouse last moved, on foot
var _shoulder := 1.0                  # aim side: +1 right, -1 left (target)
var _shoulder_w := 1.0                # eased toward _shoulder
var _aim_fov_override := -1.0         # <=0 means "use AIM_FOV"
var _rev_t := 0.0                     # s the vehicle has been reversing
var _rev_w := 0.0                     # 0..1 reverse-look swing weight
var _probe: SphereShape3D = null      # cached spring-arm sweep shape


## M19 verbs main.gd has no binding for yet, registered at runtime from the file
## that consumes them (the permanent `_register_input_actions` lines are in the
## mission report). Idempotent: we only ever create a MISSING action, so main.gd
## adopting them later simply takes over.
##   "shoulder_swap"  V  — flip the aim camera to the other shoulder
static func _register_camera_actions() -> void:
	if InputMap.has_action("shoulder_swap"):
		return
	InputMap.add_action("shoulder_swap")
	for key: Key in [KEY_V]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event("shoulder_swap", ev)


func _ready() -> void:
	fov = FOV_BASE
	near = 0.1
	far = 2000.0
	_shake_rng.seed = 0xCAFE
	_register_camera_actions()


## PUBLIC (M19) — SCOPE ZOOM CONTRACT for the shooting mission.
## `set_aim_fov(28.0)` makes the AIM rig's target FOV 28 instead of AIM_FOV 50;
## `clear_aim_fov()` gives it back. Both are safe to call every frame and safe
## to call while not aiming (the value only ever applies to the aim half of the
## FOV blend, so a scoped weapon holstered mid-zoom eases back on its own).
## The existing FOOT_FOV_K blend does the easing — a scope should NOT cut.
## Typical values: 4x scope 28.0, 8x 16.0, iron sights just leave it alone.
func set_aim_fov(f: float) -> void:
	_aim_fov_override = clampf(f, 10.0, 90.0)


func clear_aim_fov() -> void:
	_aim_fov_override = -1.0


# ============================== PUBLIC (M11) =================================
## Kick the camera. Callers pass 0.15 for a pistol shot, ~0.5 for taking a
## hit, up to 1.0 for a wreck. Trauma is CLAMPED and decays on its own, so
## spamming it never locks the view into a blur.
func add_trauma(amount: float) -> void:
	_trauma = clampf(_trauma + amount, 0.0, 1.0)


## Muzzle climb. Applied to the camera basis only — the gun follows the view
## (so recoil genuinely spoils your aim) while the character's movement basis,
## which reads `orbit_yaw`, stays put and never drifts under the player.
func add_recoil(pitch: float, yaw: float) -> void:
	_recoil_pitch += pitch
	_recoil_yaw += yaw


## M13 aim snap (combat.gd, on the aim press): point the foot rig straight at
## a target. This IS the shot direction — the centre ray passes through the
## aim pivot, so setting yaw/pitch here puts the crosshair on the chest.
func aim_snap(yaw: float, pitch: float) -> void:
	orbit_yaw = wrapf(yaw, -PI, PI)
	orbit_pitch = clampf(pitch, deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))


## M13 hospital walk-out (on_foot.gd): hard-place the foot rig at a known yaw
## so frame one is already the framing — no glide across the map from wherever
## the death happened.
func snap_foot_rig(yaw: float) -> void:
	_foot_active = true
	_aim_w = 0.0
	_trauma = 0.0
	orbit_yaw = wrapf(yaw, -PI, PI)
	orbit_pitch = -0.12
	_shoulder = 1.0
	_shoulder_w = 1.0
	_rev_t = 0.0
	_rev_w = 0.0
	_boom = 1.0
	# The hold starts EXPIRED so the very first frame is already settled — the
	# walk-out must not drift under a recentre the player never asked for.
	_foot_idle = FOOT_RECENTER_HOLD
	if target is Node3D and is_instance_valid(target) and target.is_inside_tree():
		var fwd := Vector3(-sin(orbit_yaw), 0.0, -cos(orbit_yaw))
		var right := Vector3(cos(orbit_yaw), 0.0, -sin(orbit_yaw))
		# Must match _foot_process's pivot exactly (M19 added FOOT_LATERAL), or
		# frame one of the respawn is a different framing from frame two — the
		# whole point of this call. perf_harness's `hospital_door` station is
		# derived from this math; it holds, shifted by the same 0.30 m.
		var pivot: Vector3 = target.global_position \
			+ Vector3.UP * FOOT_SHOULDER_HEIGHT + right * FOOT_LATERAL
		_chase_pos = pivot - fwd * FOOT_DISTANCE + Vector3.UP * 0.4
		global_position = _chase_pos
		look_at(pivot + fwd * FOOT_LOOK_AHEAD, Vector3.UP)
		_last_look = pivot + fwd * FOOT_LOOK_AHEAD
	_initialized = true


# ============================== SHARED RIG HELPERS ===========================
## SPRING ARM. Cast from the pivot to where the camera wants to be; if the
## world is in the way, pull the lens in to the hit (minus a margin) so the
## camera never ends up inside a tower or on the far side of a wall. Easing
## back OUT is smoothed; pulling IN is instant, because a frame spent inside
## geometry is a frame of black screen.
## D-050: this used to cast a zero-width RAY, which cannot protect a near plane
## that is 0.25 x 0.14 m wide — the lens clipped corners the ray flew past. It
## now SWEEPS a CAM_SPHERE_R sphere with `cast_motion`, whose "safe fraction" is
## exactly the quantity a spring arm wants.
func _spring(pivot: Vector3, desired: Vector3, delta: float) -> Vector3:
	var span := desired - pivot
	var dist := span.length()
	if dist < 0.01:
		return desired
	var dir := span / dist
	var world := get_world_3d()
	var want := 1.0
	if world != null:
		if _probe == null:
			_probe = SphereShape3D.new()
			_probe.radius = CAM_SPHERE_R
		var q := PhysicsShapeQueryParameters3D.new()
		q.shape = _probe
		q.transform = Transform3D(Basis.IDENTITY, pivot)
		q.motion = dir * (dist + COLLIDE_MARGIN)
		q.exclude = _exclusions()
		# cast_motion returns [safe, unsafe] fractions of `motion`. A sphere
		# that STARTS inside geometry (pivot shoved into a wall, a ped clipped
		# into a slab) returns [0, 0] — which correctly reads as "no room", the
		# case the old ray's hit_from_inside flag was there to catch.
		var frac := world.direct_space_state.cast_motion(q)
		if frac.size() == 2 and frac[0] < 1.0:
			var d: float = float(frac[0]) * (dist + COLLIDE_MARGIN) - COLLIDE_MARGIN
			want = clampf(maxf(d, COLLIDE_MIN) / dist, 0.0, 1.0)
	_boom = want if want < _boom else lerpf(_boom, want, 1.0 - exp(-COLLIDE_RETURN_K * delta))
	return pivot + dir * (dist * _boom)


## Bodies the arm must never collide against.
##
## D-051 RE-DECIDED (the ledger asked for a decision, not a silent patch).
## M11 excluded `main.vehicle` unconditionally so the truck you just stepped out
## of could not shove the lens into your face. That is right while you are IN
## it — you are inside its bodywork by definition — and wrong the moment you are
## on foot, where it is just a large opaque object standing between the lens and
## you, and the arm reported clear straight through it. So: the FOLLOW TARGET is
## always excluded (you can never be occluded by yourself), `main.character`
## stays excluded (it is the target on foot and a freed ghost otherwise), and
## `main.vehicle` is excluded ONLY while driving.
func _exclusions() -> Array[RID]:
	var out: Array[RID] = []
	if target is CollisionObject3D and is_instance_valid(target):
		out.append((target as CollisionObject3D).get_rid())
	var main := get_parent()
	if main == null:
		return out
	var on_foot: bool = main.get("on_foot") == true
	# (A ternary between two array literals yields an untyped Array, which will
	#  not assign to Array[String] — build it instead.)
	var props: Array[String] = ["character"]
	if not on_foot:
		props.append("vehicle")
	for prop: String in props:
		var v: Variant = main.get(prop)
		if v is CollisionObject3D and is_instance_valid(v):
			out.append((v as CollisionObject3D).get_rid())
	return out


## Additive shake, applied AFTER look_at so it never fights the framing.
## Trauma is squared: small knocks stay subtle, big ones read as violence.
func _apply_shake(delta: float) -> void:
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	if _trauma <= 0.001:
		return
	_shake_t += delta * SHAKE_FREQ
	var e := _trauma * _trauma
	var ox := sin(_shake_t * 1.7) * _shake_rng.randf_range(0.7, 1.0)
	var oy := sin(_shake_t * 2.3 + 1.1) * _shake_rng.randf_range(0.7, 1.0)
	var oz := sin(_shake_t * 1.3 + 2.7) * _shake_rng.randf_range(0.7, 1.0)
	global_position += (global_transform.basis.x * ox + global_transform.basis.y * oy) \
		* SHAKE_POS * e
	rotate_object_local(Vector3.RIGHT, oy * SHAKE_ROT * e)
	rotate_object_local(Vector3.UP, ox * SHAKE_ROT * e)
	rotate_object_local(Vector3.FORWARD, oz * SHAKE_ROT * e * 0.6)


func _decay_recoil(delta: float) -> void:
	var k := 1.0 - exp(-RECOIL_RECOVER * delta)
	_recoil_pitch = lerpf(_recoil_pitch, 0.0, k)
	_recoil_yaw = lerpf(_recoil_yaw, 0.0, k)


func _process(delta: float) -> void:
	var foot := _is_foot_target()
	if InputMap.has_action("toggle_camera") and Input.is_action_just_pressed("toggle_camera"):
		if not foot:
			_cycle_mode()
		# On foot C is ignored: the foot rig is the only on-foot framing and
		# the hood rig must never grab a walking body.
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return
	if foot:
		_foot_process(delta)
		return
	if _foot_active:
		_leave_foot_rig()
	if not _initialized:
		_snap_to_target()

	var t_pos: Vector3 = target.global_position
	var vel := Vector3.ZERO
	if target is RigidBody3D:
		vel = (target as RigidBody3D).linear_velocity
	var speed := vel.length()

	var desired_pos := t_pos
	var look_point := t_pos
	var desired_fov := FOV_BASE

	match _mode:
		Mode.CHASE:
			# Free-look: the mouse swings the boom around the car and springs
			# back after FREELOOK_HOLD of no input, so a glance over your
			# shoulder mid-chase costs nothing and self-corrects.
			_look_idle += delta
			if _look_idle > FREELOOK_HOLD:
				var rk := 1.0 - exp(-FREELOOK_RECENTER_K * delta)
				_look_yaw = lerpf(_look_yaw, 0.0, rk)
				_look_pitch = lerpf(_look_pitch, 0.0, rk)
			_reverse_look_step(delta, vel)
			# The reverse swing is a ROTATION of the boom around the car, not a
			# lerp of two opposed vectors — a lerp would collapse through the
			# chassis at the halfway point and put the lens inside the cab.
			var back := _flat_back().rotated(Vector3.UP, _look_yaw + PI * _rev_w)
			var height := CHASE_HEIGHT + minf(speed * CHASE_HEIGHT_PER_MPS, CHASE_HEIGHT_MAX_BONUS)
			height += _look_pitch * CHASE_DISTANCE + REVERSE_LOOK_HEIGHT * _rev_w
			var boom := CHASE_DISTANCE \
				+ minf(speed * CHASE_DIST_PER_MPS, CHASE_DIST_MAX_BONUS)
			var goal := t_pos + back * boom + Vector3.UP * maxf(height, 0.4)
			_chase_pos = _chase_pos.lerp(goal, 1.0 - exp(-CHASE_SMOOTH_K * delta))
			desired_pos = _spring(t_pos + Vector3.UP * LOOK_HEIGHT, _chase_pos, delta)
			var lead := vel * LOOK_AHEAD_TIME
			lead.y = 0.0
			look_point = t_pos + Vector3.UP * LOOK_HEIGHT + lead.limit_length(LOOK_AHEAD_MAX)
			# While glancing — or swung round to reverse — look AT the car, not
			# past it: the lead vector points the wrong way through the swing.
			if absf(_look_yaw) > 0.01 or _rev_w > 0.01:
				look_point = t_pos + Vector3.UP * LOOK_HEIGHT
			desired_fov = lerpf(FOV_BASE, FOV_MAX, clampf(speed / FOV_FULL_SPEED, 0.0, 1.0))
		Mode.HOOD:
			# D-052: the hood rig was a rigid offset with nothing to pull it out
			# of geometry. Spring it from the cabin so nosing into a wall pulls
			# the lens back to the windscreen instead of through the brickwork.
			var xf: Transform3D = target.global_transform
			desired_pos = _spring(t_pos + Vector3.UP * LOOK_HEIGHT,
				xf * HOOD_OFFSET, delta)
			look_point = desired_pos - xf.basis.z * HOOD_LOOK_AHEAD
			desired_fov = HOOD_FOV
			_chase_pos = desired_pos  # keep chase state nearby for a clean switch back
		Mode.ORBIT:
			# D-052: same for the beauty-shot orbit, which used to sweep the
			# lens straight through whatever the car was parked next to.
			_orbit_angle = wrapf(_orbit_angle + ORBIT_SPEED * delta, 0.0, TAU)
			desired_pos = _spring(t_pos + Vector3.UP * 0.8, t_pos + Vector3(
				cos(_orbit_angle) * ORBIT_RADIUS, ORBIT_HEIGHT,
				sin(_orbit_angle) * ORBIT_RADIUS), delta)
			look_point = t_pos + Vector3.UP * 0.8
			desired_fov = ORBIT_FOV
			_chase_pos = desired_pos

	# Blend out of the previous mode's framing over TRANSITION_TIME.
	var pos := desired_pos
	var look := look_point
	if _transition_left > 0.0:
		_transition_left = maxf(_transition_left - delta, 0.0)
		var w := smoothstep(0.0, 1.0, 1.0 - _transition_left / TRANSITION_TIME)
		pos = _from_pos.lerp(desired_pos, w)
		look = _from_look.lerp(look_point, w)

	global_position = pos
	if pos.distance_squared_to(look) > 0.0001:
		look_at(look, Vector3.UP)
	_last_look = look
	fov = lerpf(fov, desired_fov, 1.0 - exp(-FOV_SMOOTH_K * delta))
	_decay_recoil(delta)
	_apply_shake(delta)


func _cycle_mode() -> void:
	_mode = (_mode + 1) % Mode.size()
	_transition_left = TRANSITION_TIME
	_from_pos = global_position
	_from_look = _last_look
	if _mode == Mode.ORBIT and is_instance_valid(target) and target.is_inside_tree():
		# Start the orbit from wherever the camera already is, so the blend is short.
		var offset := global_position - target.global_position
		_orbit_angle = atan2(offset.z, offset.x)


func _snap_to_target() -> void:
	## First valid frame: place the camera directly at the chase pose so we do
	## not swoop in from the world origin.
	var back := _flat_back()
	_chase_pos = target.global_position + back * CHASE_DISTANCE + Vector3.UP * CHASE_HEIGHT
	global_position = _chase_pos
	_last_look = target.global_position + Vector3.UP * LOOK_HEIGHT
	if global_position.distance_squared_to(_last_look) > 0.0001:
		look_at(_last_look, Vector3.UP)
	_initialized = true


## M19 REVERSE LOOK. Reversing is the one time the direction you are going and
## the direction the camera faces disagree, and every driving game that does not
## solve it makes you back into things. Trigger is the car's own longitudinal
## velocity (not the key), so it fires when you are ACTUALLY going backwards —
## rolling back down a hill counts, flooring the accelerator in reverse gear
## while still sliding forward does not. It yields instantly to the mouse: a
## hand on free-look outranks any automatic camera.
func _reverse_look_step(delta: float, vel: Vector3) -> void:
	var fwd_speed := vel.dot(-target.global_transform.basis.z)
	var want := fwd_speed < REVERSE_LOOK_SPEED and absf(_look_yaw) <= 0.01
	if want:
		_rev_t += delta
	else:
		_rev_t = 0.0
	var goal := 1.0 if _rev_t >= REVERSE_LOOK_DELAY else 0.0
	_rev_w = move_toward(_rev_w, goal, delta / REVERSE_LOOK_BLEND)


func _flat_back() -> Vector3:
	## Target's backward direction (+basis.z, since forward is -Z), flattened to
	## the ground plane so the camera does not pitch with the chassis.
	var back: Vector3 = target.global_transform.basis.z
	back.y = 0.0
	return back.normalized() if back.length() > 0.01 else Vector3.BACK


# ============================== ON-FOOT RIG ==================================
## Mouse-orbit input. Consumed ONLY when the target is a character AND the
## mouse is captured — vehicle modes never see or eat mouse motion.
func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventMouseMotion):
		return
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	var rel: Vector2 = (event as InputEventMouseMotion).relative
	if not _is_foot_target():
		# DRIVING: the mouse swings the boom (and with it the drive-by firing
		# line). Only CHASE has a boom to swing; hood and orbit ignore it.
		if _mode == Mode.CHASE:
			_look_yaw = clampf(_look_yaw - rel.x * MOUSE_SENSITIVITY,
				-FREELOOK_YAW_MAX, FREELOOK_YAW_MAX)
			_look_pitch = clampf(_look_pitch + rel.y * MOUSE_SENSITIVITY * 0.6,
				FREELOOK_PITCH.x, FREELOOK_PITCH.y)
			_look_idle = 0.0
			get_viewport().set_input_as_handled()
		return
	# M13: while aiming, the mouse slows for fine work (AIM_SENS_MULT), and
	# slows further over a target (aim_friction, fed by combat.gd) — sticky aim.
	var sens := MOUSE_SENSITIVITY
	if _combat_aiming():
		sens *= AIM_SENS_MULT * clampf(aim_friction, 0.3, 1.0)
	orbit_yaw = wrapf(orbit_yaw - rel.x * sens, -PI, PI)
	orbit_pitch = clampf(orbit_pitch - rel.y * sens,
		deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))
	# Any hand on the mouse restarts the auto-centre hold. Motion events fire
	# with a zero relative on some platforms, so gate on real movement — a
	# jittering sensor must not be able to hold the camera hostage forever.
	if rel.length_squared() > 0.0:
		_foot_idle = 0.0
	get_viewport().set_input_as_handled()


## AUTO-CENTRE — the GTA behaviour people describe as "the camera follows you".
## After FOOT_RECENTER_HOLD of no mouse input, and only while the body is
## actually travelling, orbit_yaw eases toward the body's facing.
##
## The feedback loop is deliberate and stable: orbit_yaw is also the movement
## basis, so with W held the body already faces the camera and this is a no-op;
## with A held the body faces 90 deg off, the camera swings toward it, and the
## input direction rotates with the camera — which is why strafing in GTA
## curves you around rather than crabbing sideways forever. FOOT_RECENTER_MAX_RATE
## caps it so a 180 eases rather than whips, and it is OFF while aiming, where
## the yaw is the crosshair and belongs to nobody but the player.
func _auto_centre(delta: float) -> void:
	if _foot_idle < FOOT_RECENTER_HOLD or _combat_aiming():
		return
	var v: Variant = target.get("velocity")
	if not (v is Vector3):
		return
	var planar := Vector3((v as Vector3).x, 0.0, (v as Vector3).z)
	if planar.length() < FOOT_RECENTER_MIN_SPEED:
		return
	var body_yaw: float = (target as Node3D).rotation.y
	var diff := wrapf(body_yaw - orbit_yaw, -PI, PI)
	var step := diff * (1.0 - exp(-FOOT_RECENTER_K * delta))
	step = clampf(step, -FOOT_RECENTER_MAX_RATE * delta, FOOT_RECENTER_MAX_RATE * delta)
	orbit_yaw = wrapf(orbit_yaw + step, -PI, PI)


func _is_foot_target() -> bool:
	return target != null and is_instance_valid(target) and target.is_inside_tree() \
		and (target is CharacterBody3D or target.has_meta("is_character"))


## First foot frame after a target swap: derive yaw/pitch from wherever the
## camera already faces so the E handoff does not snap the view.
func _enter_foot_rig() -> void:
	_foot_active = true
	_aim_w = 0.0
	_rev_t = 0.0
	_rev_w = 0.0
	_foot_idle = 0.0   # stepping out is a deliberate act; let the player look
	var fwd := -global_transform.basis.z
	orbit_yaw = atan2(-fwd.x, -fwd.z)
	orbit_pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)),
		deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG))
	_chase_pos = global_position
	_initialized = true


## Hand the camera back to the vehicle rig from wherever the foot rig left it;
## the chase smoothing walks it home, so re-entry is a glide, not a cut.
func _leave_foot_rig() -> void:
	_foot_active = false
	_aim_w = 0.0
	_chase_pos = global_position
	_transition_left = 0.0
	_initialized = true


func _foot_process(delta: float) -> void:
	if not _foot_active:
		_enter_foot_rig()
	_foot_idle += delta
	if InputMap.has_action("shoulder_swap") \
			and Input.is_action_just_pressed("shoulder_swap"):
		_shoulder = -_shoulder
	_shoulder_w = move_toward(_shoulder_w, _shoulder, delta / SHOULDER_SWAP_TIME)
	_auto_centre(delta)
	# Recoil rides on TOP of the player's aim: the view (and therefore the
	# shot, which is cast from the camera) climbs, while orbit_yaw — the
	# character's movement basis — is left alone.
	var rot := Basis(Vector3.UP, orbit_yaw + _recoil_yaw) \
		* Basis(Vector3.RIGHT, clampf(orbit_pitch + _recoil_pitch,
			deg_to_rad(PITCH_MIN_DEG), deg_to_rad(PITCH_MAX_DEG)))
	var fwd := -rot.z
	var right := rot.x
	var t_pos: Vector3 = target.global_position  # character origin = feet
	# M16 crouch accommodation: the body's "is_crouched" meta drops both foot
	# and aim pivots by CROUCH_PIVOT_DROP, eased so the view sinks with the
	# stance instead of cutting. (Contract: player_character publishes the meta
	# only while the short collider is actually down.)
	var want_crouch := 1.0 if target.get_meta("is_crouched", false) else 0.0
	_crouch_w = move_toward(_crouch_w, want_crouch, delta / CROUCH_BLEND_TIME)
	var drop := Vector3.DOWN * (CROUCH_PIVOT_DROP * _crouch_w)

	# FOLLOW rig: shoulder-pivot orbit, offset off-centre, smoothed snappier
	# than vehicle chase — and progressively LESS snappy the faster you move, so
	# a sprint lets the body run away from the lens for a beat before it settles.
	# FOOT_LATERAL shifts the pivot, the lens AND the look point together, so
	# the framing moves off-centre while the centre ray stays on the pivot.
	var pivot := t_pos + Vector3.UP * FOOT_SHOULDER_HEIGHT + drop \
		+ right * FOOT_LATERAL
	var planar := Vector3.ZERO
	var v: Variant = target.get("velocity")
	if v is Vector3:
		planar = Vector3((v as Vector3).x, 0.0, (v as Vector3).z)
	var settle := clampf(planar.length() / FOOT_SETTLE_SPEED, 0.0, 1.0)
	var boom := FOOT_DISTANCE \
		+ minf(planar.length() * FOOT_DIST_PER_MPS, FOOT_DIST_MAX_BONUS)
	var smooth_k := lerpf(FOOT_SMOOTH_K, FOOT_SMOOTH_K_RUN, settle)
	_chase_pos = _chase_pos.lerp(pivot - fwd * boom, 1.0 - exp(-smooth_k * delta))
	var follow_look := pivot + fwd * FOOT_LOOK_AHEAD
	var follow_fov := FOOT_FOV
	if target.get("is_sprinting") == true:
		follow_fov += FOOT_SPRINT_FOV_BONUS

	# AIM rig: over ONE shoulder — which one is _shoulder_w, flipped by V and
	# eased across in SHOULDER_SWAP_TIME so the swap is a move, not a cut. The
	# aim rig keeps its own lateral and ignores FOOT_LATERAL: an aiming camera
	# is a shoulder camera, and stacking the two offsets doubles the parallax.
	_aim_w = move_toward(_aim_w, 1.0 if _combat_aiming() else 0.0, delta / AIM_BLEND_TIME)
	var aim_pivot := t_pos + Vector3.UP * AIM_HEIGHT \
		+ right * (AIM_LATERAL * _shoulder_w) + drop
	var aim_pos := aim_pivot - fwd * AIM_DISTANCE
	var aim_look := aim_pivot + fwd * AIM_LOOK_AHEAD

	var pos := _chase_pos.lerp(aim_pos, _aim_w)
	var look := follow_look.lerp(aim_look, _aim_w)
	# Spring-arm from the shoulder pivot: walking backwards into a wall pulls
	# the lens in instead of putting it inside the building.
	pos = _spring(pivot.lerp(aim_pivot, _aim_w), pos, delta)
	global_position = pos
	if pos.distance_squared_to(look) > 0.0001:
		look_at(look, Vector3.UP)
	_last_look = look
	var aim_fov := _aim_fov_override if _aim_fov_override > 0.0 else AIM_FOV
	fov = lerpf(fov, lerpf(follow_fov, aim_fov, _aim_w), 1.0 - exp(-FOOT_FOV_K * delta))
	_decay_recoil(delta)
	_apply_shake(delta)


## Aim state lives on the (optional) combat system; the camera hangs off main,
## so its parent is the systems owner. Null-safe at every hop (contract).
func _combat_aiming() -> bool:
	var main := get_parent()
	if main == null:
		return false
	var sys: Variant = main.get("systems")
	if sys is Dictionary:
		var combat: Variant = (sys as Dictionary).get("combat")
		if combat is Object and is_instance_valid(combat):
			return (combat as Object).get("is_aiming") == true
	return false
