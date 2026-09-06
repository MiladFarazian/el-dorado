class_name PlayerCharacter
extends CharacterBody3D
## BOOK REYES, ON FOOT — the walking half of the game (M5 foundation, M16
## movement verbs: crouch / jump quality / mantle / sprint intent).
## Origin is at the FEET, so global_position sits on the ground and the camera
## rigs' "shoulder height 1.65" reads literally as feet + 1.65.
##
## Instanced/freed exclusively by scripts/systems/on_foot.gd, which sets
## main_ref before add_child. Reads input ONLY while it is the active actor
## (main.on_foot == true, main.character == self, tree not paused, alive), so
## a parked character existing in the world is inert and safe. Movement is
## camera-relative: basis comes from the chase camera's foot-rig orbit_yaw
## (fallback: camera flat -Z), read via main_ref.get("camera").
##
## ============ CROSS-SYSTEM CONTRACT (metas/properties others read) ==========
##   is_sprinting: bool       — foot_cops (accuracy penalty vs a sprinter),
##                              chase_camera (FOV kick). UNCHANGED MEANING:
##                              "tier 2", i.e. real sprint intent while moving;
##                              never while crouched. Stays true while winded.
##   move_tier: int           — M19 three-tier read for the HUD: 0 WALK
##                              (Alt held, or crouched, or a sub-threshold
##                              analog stick), 1 JOG (the default), 2 SPRINT.
##                              A stance, not a speedometer: it reports intent
##                              and is valid while standing still.
##   stamina: float           — 0..1. Drains only in tier 2, refills fastest at
##                              rest. At 0 you keep running, just slower (see
##                              SPRINT_WINDED_SPEED) — GTA never takes the verb
##                              away, it takes the top end away.
##   max_health: float        — mirrors MAX_HEALTH as a READABLE property.
##                              D-062: combat.gd:1199 calls get("max_health")
##                              and constants are invisible to Object.get(), so
##                              the health bar was right only by coincidence.
##   move_state: int          — MoveState enum {0 STAND, 1 CROUCH, 2 AIR,
##                              3 MANTLE, 4 ROLL}. Combat/melee gate stances on
##                              it (e.g. no melee windup mid-MANTLE). 0..3 are
##                              frozen; ROLL was appended, never inserted.
##   meta "is_crouched"       — present AND true only while the crouch collider
##                              is down (1.15 m). Absent while standing. Read
##                              with get_meta("is_crouched", false). Combat
##                              reads it for spread; chase_camera lowers the
##                              foot/aim pivots on it.
##   meta "is_character"      — true; identifies the body to camera/systems.
##   meta "combat_speed_cap"  — READ here (combat.gd writes it while aiming):
##                              caps planar target speed, min-composed with
##                              the crouch cap (both can apply; lowest wins).
##   health / MAX_HEALTH, take_damage(), heal(), begin_walkout(t),
##   signals health_changed / died — unchanged M5/M13 API.
##
## ================= STATE MACHINE (move_state) — transitions =================
##   STAND  -> CROUCH  "crouch" toggle (CTRL) while grounded.
##   CROUCH -> STAND   toggle again / sprint held / jump press — ONLY when the
##                     stand-up probe above the head is clear. Under a low
##                     ceiling you STAY crouched (the collider never restores
##                     into geometry); the latch survives and retries on the
##                     next intent.
##   STAND  -> AIR     jump (incl. the 0.12 s coyote window after a ledge
##                     walk-off) or simply losing the floor.
##   AIR    -> STAND   landing. A jump pressed up to 0.15 s early fires here
##                     (input buffer). Falling faster than 7 m/s is a HARD
##                     landing: a beat of lost control + camera trauma. No
##                     fall damage in v1 (knob below, by design).
##   CROUCH -> AIR     ledge walk-off while crouched; the crouch latch (and
##                     collider) survive the fall and land back in CROUCH.
##   AIR    -> ROLL    M19: a hard landing WITH forward speed becomes a tuck
##                     and roll (0.42 s, input ignored, half the trauma) rather
##                     than the lost-control beat. Landing on the spot still
##                     buckles — the roll is a reward for committing.
##   STAND  -> ROLL    M19 dodge: aiming + jump + a direction dives that way.
##                     Same state, same 0.42 s, i-frames are NOT granted (this
##                     is a repositioning verb, not an invulnerability window).
##   ROLL   -> STAND   the roll ends on its feet carrying ROLL_EXIT_SPEED.
##   STAND  -> MANTLE  moving into STATIC geometry with a top 0.4–1.1 m up
##                     within 0.9 m ahead: auto-mantle. v1 is static-only —
##                     cars are dynamic bodies (car-hood vaults = future verb).
##   MANTLE -> STAND   scripted ~0.35 s vertical+forward glide ends on top;
##                     ALL input is ignored during. No wall-climbing: anything
##                     taller than 1.1 m simply refuses.
##
## Crouch is a TOGGLE, not a hold: CTRL is a pinky key and crouch here is a
## stance you live in (sneaking, cover, steady shots) while WASD+Shift+mouse
## already claim the hand — holding it is claw-grip. Toggle also gives combat
## a stable meta instead of a flickering one. (GTA V made the same call.)

signal health_changed(hp: float)
signal died

enum MoveState { STAND, CROUCH, AIR, MANTLE, ROLL }
## Tier names for move_tier. WALK is a deliberate, modifier-held gait; JOG is
## what you get for pressing a direction; SPRINT is Shift with a stamina cost.
enum MoveTier { WALK, JOG, SPRINT }

# ============================== TUNABLES =====================================
# --- M19 three-tier locomotion -----------------------------------------------
# GTA's read, in numbers: the DEFAULT is a jog with momentum (not a walk),
# walk is a modifier you hold, sprint is a burst you spend. WALK_SPEED keeps
# its name because it is still the tier-0 speed; the default is JOG_SPEED.
const WALK_SPEED := 1.9               # m/s, tier 0 — "walk" modifier (Alt) held
const JOG_SPEED := 4.6                # m/s, tier 1 — THE DEFAULT GAIT
const SPRINT_SPEED := 7.6             # m/s, tier 2 — Shift, with stamina
const SPRINT_WINDED_SPEED := 5.4      # m/s, tier 2 at stamina 0: still running,
									  # just out of top end. The verb never dies.
## WHY WALK IS A MODIFIER AND NOT AN ANALOG MAGNITUDE: a keyboard has no stick,
## so `_read_move_input()` can only ever return length 1.0 and a magnitude tier
## would be unreachable. The threshold below is implemented anyway and is inert
## today — the day a stick is bound, a gentle push walks with no new code.
const WALK_STICK_MAG := 0.55          # analog magnitude at or under this = tier 0
## D-016 CONTRACT: the hospital walk-out is a SCRIPTED beat, 1.4 s long, and it
## must cover the same ground it covered in M13 no matter how the player tiers
## are retuned. Pinned to the old WALK_SPEED (3.4) on purpose — the M19 retier
## dropped tier 0 to 1.9, which would have left Book short of the ER apron.
const WALKOUT_SPEED := 3.4            # m/s during begin_walkout()
const ACCEL := 16.0                   # m/s^2 toward desired velocity (snappy)
const DECEL := 20.0                   # m/s^2 back to rest (snappier still)
const JUMP_SPEED := 4.6               # m/s vertical on "jump" (Space)
const GRAVITY := 14.0                 # m/s^2 (gamey — floatier than 9.8 reads wrong)
const AIR_CONTROL := 0.55             # accel multiplier airborne (M16: was 0.4)
const TURN_RATE := 12.0               # yaw exp-decay rate toward travel direction
const MAX_HEALTH := 100.0
const RUNOVER_MIN_SPEED := 6.0        # m/s — slower rigid bodies are a shove, not a hit
const RUNOVER_DMG_PER_MPS := 6.0      # damage = 6 x striker speed
const RUNOVER_IFRAMES := 0.5          # s of run-over immunity after a hit
const RUNOVER_CARRY := 0.8            # share of striker velocity inherited
const RUNOVER_POP := 2.5              # m/s up-fling so the hit reads as a launch
const COLLIDER_SIZE := Vector3(0.5, 1.75, 0.35)  # STANDING envelope — contract
# --- M16 crouch ---
const CROUCH_HEIGHT := 1.15           # crouched collider height (m), feet origin
const CROUCH_SPEED := 1.8             # m/s planar cap while crouched
const STAND_PROBE_PAD := 0.05         # extra headroom the stand-up probe demands (m)
# --- M16 jump quality ---
const COYOTE_TIME := 0.12             # s after a ledge walk-off a jump still fires
const JUMP_BUFFER := 0.15             # s early a jump press is banked for landing
const JUMP_CUT_GRAVITY_MULT := 2.4    # gravity boost ascending with Space released
const HARD_LAND_SPEED := 7.0          # m/s down that costs a beat on touchdown
const HARD_LAND_RECOVER := 0.35       # s of lost control after a hard landing
const HARD_LAND_TRAUMA_BASE := 0.3    # camera trauma at exactly HARD_LAND_SPEED
const HARD_LAND_TRAUMA_PER_MPS := 0.04
const HARD_LAND_TRAUMA_MAX := 0.65
const FALL_DAMAGE_PER_MPS := 0.0      # KNOB: STILL 0, deliberately (v1 decision;
									  # not mine to overturn silently).
## PROPOSED VALUE: 2.6 dmg per m/s over HARD_LAND_SPEED. Derivation, so the
## number is arguable instead of vibes — impact speed off a drop of h under
## GRAVITY 14 is sqrt(2*14*h):
##   1.5 m kerb/porch  ->  6.5 m/s  -> under the 7.0 threshold, FREE (correct:
##                          hopping off a loading dock must never chip you)
##   3.0 m garage roof ->  9.2 m/s  ->  5.7 dmg   (a wince)
##   6.0 m two storeys -> 13.0 m/s  -> 15.5 dmg   (you feel it, you live)
##  12.0 m four storeys-> 18.3 m/s  -> 29.4 dmg   (a third of the bar)
##  30.0 m Trust Tower -> 29.0 m/s  -> 57.1 dmg   (survivable ONCE, at full HP)
## The shape I want and the reason for 2.6: nothing a player does by accident
## while traversing costs health, a deliberate stupid jump costs a real bite,
## and no single fall is lethal from full — because dying to geometry with no
## enemy on screen is the least interesting death in an open world. Pair it
## with the M19 landing roll (below), which should REFUND the damage: rolling
## out of a fall you committed to is the skill expression the number funds.
## NOT SHIPPED. Needs a Game Systems Designer call plus a health-pickup audit
## (Dr. Zing is +25 for $3 — at 2.6/m/s a rooftop tour is affordable, which may
## be exactly wrong). Set it here; nothing else needs to change.
# --- M16 mantle ---
const MANTLE_MIN := 0.4               # ledge tops below this are just steps (m)
const MANTLE_MAX := 1.1               # above this is a wall — refuse, no climbing
const MANTLE_AHEAD := 0.9             # face must be within this reach (m)
const MANTLE_FACE_PROBE_Y := 0.35     # face-ray height: below MANTLE_MIN so every
									  # legal ledge presents a face to hit
const MANTLE_TOP_INSET := 0.18        # how far past the face the top-ray drops (m)
const MANTLE_TOP_CLEAR := 0.35        # top-ray starts this far above MANTLE_MAX
const MANTLE_TIME := 0.35             # s of scripted glide, input ignored
const MANTLE_UP_SHARE := 0.6          # first fraction of the glide that is the rise
const MANTLE_FWD_START := 0.25        # forward drift eases in from this fraction
const MANTLE_EXIT_SPEED := 2.2        # m/s carried over the lip at the end
const MANTLE_COOLDOWN := 0.25         # s before the next auto-mantle can trigger
# --- M19 landing roll / dodge roll -------------------------------------------
## A hard landing WITH forward speed is a roll, not a stumble. Standing still
## keeps the M16 buckle beat, so the roll is a reward for committing to the
## jump rather than a free pass on every drop.
const ROLL_TIME := 0.42               # s of scripted roll, input ignored
const ROLL_MIN_SPEED := 2.5           # m/s planar at touchdown to earn the roll
const ROLL_SPEED := 5.6               # m/s carried through the roll
const ROLL_EXIT_SPEED := 3.4          # m/s left when it ends (you come up running)
const ROLL_TRAUMA_MULT := 0.45        # a roll absorbs — less camera than a buckle
const DODGE_SPEED := 6.4              # m/s of the aiming dodge-dive
const DODGE_COOLDOWN := 0.75          # s between dodges (no infinite skating)
const ROLL_POSE := {                  # scripted tuck, peaks mid-roll
	"torso": 1.15, "head": 0.55, "hip_0": 1.5, "hip_1": 1.5,
	"knee_0": -1.9, "knee_1": -1.9,
}
const ROLL_VIS_DROP := 0.42           # m the body sinks at the tuck's deepest
const ROLL_POSE_K := 18.0             # tuck blend rate (fast — a roll is quick)
# --- M19 lean (visual only; the collider never tilts) -------------------------
## Root tilt on rig["vis"], which pivots at the FEET, so boots stay planted.
## Nothing else in the project writes vis.rotation (audited: the factory writes
## only vis.position.y; melee owns head.y/torso.y/sh.z and never touches vis).
const LEAN_ROLL_PER_MPS2 := 0.030     # rad of bank per m/s^2 of lateral accel
const LEAN_ROLL_MAX := 0.140          # rad — 8.0 deg, the mandated ceiling
const LEAN_PITCH_PER_MPS2 := 0.017    # rad of forward lean per m/s^2 along travel
const LEAN_PITCH_MAX := 0.122         # rad — 7.0 deg at a sprint launch
const LEAN_K := 7.0                   # exp-decay rate toward the target tilt
const LEAN_ACCEL_K := 9.0             # exp-decay rate on the measured accel
const LEAN_SINK_PER_RAD := 0.060      # m the body sinks per rad of total tilt,
									  # so the outside foot never lifts off
# --- M19 head look ------------------------------------------------------------
## The head tracks where the CAMERA looks, not where the body goes: that split
## is most of why a GTA character reads as a person driving a body rather than a
## turret. Yaw is clamped to a human neck; past the clamp the body has to turn.
const HEAD_YAW_MAX := 1.222           # rad — 70.0 deg each way (the mandate)
const HEAD_PITCH_FOLLOW := 0.55       # share of camera pitch the neck takes
const HEAD_PITCH_MAX := 0.45          # rad ceiling on that
const HEAD_LOOK_K := 9.0              # exp-decay rate (a neck is not instant)
const HEAD_AIM_PITCH_FOLLOW := 0.85   # aiming: the head goes where the gun goes
# --- M16 sprint intent / M19 stamina ---
const SPRINT_RAMP_TIME := 0.55        # s from jog to full sprint speed
const SPRINT_RAMP_FALL := 0.25        # s back down when Shift releases
## STAMINA (M19). v1 asked whether a sprint meter earns its HUD space; the
## answer GTA gives is that the meter is not the point — the SLOWDOWN is. You
## get a real burst, then the top end goes away and comes back if you back off.
## Nothing here takes the sprint key away, so it can never dead-end (bar §4).
const STAMINA_SPRINT_SECONDS := 8.0   # s of full-tilt sprint from a full bar
const STAMINA_RECOVER_REST := 0.26    # /s standing or walking  (~3.8 s refill)
const STAMINA_RECOVER_JOG := 0.11     # /s jogging              (~9.1 s refill)
const STAMINA_RECOVER_DELAY := 0.6    # s after releasing sprint before refill
const STAMINA_TIRED_BAND := 0.35      # below this fraction the top end bleeds
									  # off toward SPRINT_WINDED_SPEED
## TURN RADIUS IS A CURVE, NOT TWO CONSTANTS (M19). Radius = v / omega, so a
## flat rad/s cap makes a sprint turn tighter than a jog turn in metres, which
## is backwards. Three knots, interpolated by SPEED (not by the sprint ramp),
## give: walk 0.12 m radius (twitch), jog 0.66 m (leans), sprint 2.9 m (arcs).
const STEER_RATE_WALK := 16.0         # rad/s at or below WALK_SPEED
const STEER_RATE_JOG := 7.0           # rad/s at JOG_SPEED
const STEER_RATE_SPRINT := 2.6        # rad/s at SPRINT_SPEED
const STEER_CURVE_POW := 1.35         # >1 holds jog agility, then falls off hard
## A 180 AT SPRINT COSTS A STEP: asking for a heading behind your velocity also
## cuts the target speed, so you shed pace to turn and the rising steer rate
## (slower = tighter) completes the turn. That coupling IS the step.
const HARD_TURN_DOT := -0.15          # dot(vel_dir, want_dir) under this is "hard"
const HARD_TURN_SPEED_MULT := 0.45    # target speed multiplier at a full 180
## THE PLANT: releasing the stick at speed does not stop you dead. For
## PLANT_TIME the heading is locked (no instant reversal) and decel is gentler,
## which reads as a short skid. Below PLANT_MIN_SPEED there is nothing to plant.
const PLANT_MIN_SPEED := 5.0          # m/s — under this, stopping is just DECEL
const PLANT_TIME := 0.22              # s of committed, un-steerable stop
const PLANT_DECEL := 13.0             # m/s^2 during the plant (2.2 m from sprint)
# --- M16 crouch pose (visual only — collider is the contract, above) ---
# rotation.x offsets per rig joint at full crouch, applied AFTER the factory's
# gait step and stripped BEFORE the next one, so the factory's exponential
# blends never see (and re-amplify) them. Signs follow the factory's knee law:
# knees only ever bend backward (<= 0).
const CROUCH_POSE := {
	"hip_0": 1.25, "hip_1": 1.25,     # thighs fold forward/up
	"knee_0": -1.7, "knee_1": -1.7,   # shins tuck back under
	"torso": -0.65,                   # hunch forward over the knees
	"head": 0.45,                     # eyes come back up to level
}
const CROUCH_VIS_DROP := 0.33         # the whole body sinks so boots stay planted
const CROUCH_POSE_K := 10.0           # pose blend exp-decay rate
# (M9: Book's look — pearl snaps, dark denim, boots, charcoal flat-brim,
# buckle — is defined ONCE in character_factory.book_config.)

# ============================== STATE ========================================
# Set by on_foot.gd before add_child; everything degrades null-safe without it.
var main_ref: Node = null
var health := 100.0
var max_health := MAX_HEALTH          # PUBLIC contract — D-062: a const is
									  # invisible to Object.get(); combat.gd
									  # polls this by name for the health bar.
var is_sprinting := false             # PUBLIC contract (foot_cops, camera)
var move_state: int = MoveState.STAND # PUBLIC contract (combat/melee)
var move_tier: int = MoveTier.JOG     # PUBLIC contract (HUD) — 0/1/2
var stamina := 1.0                    # PUBLIC contract (HUD) — 0..1
var _iframes := 0.0
var _rig: Dictionary = {}   # character_factory joint refs (M10 walk cycle)
var _walkout_t := 0.0       # M13: scripted hospital walk-out timer
# M16 movement internals.
var _crouched := false                # the crouch latch (collider is down)
var _coyote_t := 0.0
var _jump_buffer := 0.0
var _jump_active := false             # this air time came from OUR jump
var _land_recover_t := 0.0
var _sprint_ramp := 0.0               # 0 walk .. 1 full sprint
var _mantle_t := 0.0
var _mantle_cd := 0.0
var _mantle_from := Vector3.ZERO
var _mantle_to := Vector3.ZERO
var _crouch_pose_w := 0.0             # eased visual crouch weight
var _pose_applied: Dictionary = {}    # joint -> rotation.x offset added last frame
var _vis_y_applied := 0.0
var _col_node: CollisionShape3D = null
var _box_shape: BoxShape3D = null
var _probe_shape: BoxShape3D = null   # cached stand-up clearance probe
# M19 internals.
var _stamina_hold := 0.0              # s left before stamina starts refilling
var _plant_t := 0.0                   # s left in a committed stop
var _roll_pose_w := 0.0               # eased visual roll-tuck weight
var _roll_t := 0.0                    # s left in a roll (landing or dodge)
var _roll_dir := Vector3.ZERO         # unit heading of the roll
var _roll_cd := 0.0                   # s before the next dodge roll
var _lean_accel := Vector3.ZERO       # smoothed planar acceleration, world space
var _prev_hvel := Vector3.ZERO        # last frame's planar velocity
var _lean_roll := 0.0                 # eased bank (rad, applied to vis.rotation.z)
var _lean_pitch := 0.0                # eased forward lean (vis.rotation.x)
var _head_yaw := 0.0                  # eased head yaw offset (rad, local)
var _head_pitch := 0.0                # eased head pitch offset (rad, local)


## M19 verbs that main.gd has no binding for yet. Registered from HERE at
## runtime so they work in today's build without editing a file this mission
## does not own; the permanent lines for main.gd's `_register_input_actions`
## bindings dict are in the mission report. Idempotent — main.gd adding them
## later simply wins, because we only ever create a MISSING action.
##   "walk_slow"  ALT  — hold to drop from jog (tier 1) to walk (tier 0)
static func _register_move_actions() -> void:
	if InputMap.has_action("walk_slow"):
		return
	InputMap.add_action("walk_slow")
	for key: Key in [KEY_ALT]:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event("walk_slow", ev)


const FACTORY := preload("res://scripts/world/character_factory.gd")
## SKINNED-BODY PROOF OF CONCEPT — inert unless `--skinned` is on the command
## line. `character_factory` remains the shipping path and is not modified; only
## `build()` is redirected, because `animate()` / `aim_pose()` / the rig dict are
## contract-identical between the two and the skinned body delegates to the
## factory's animator anyway.
const SKINNED := preload("res://scripts/world/skinned_character.gd")
static func _body_script() -> GDScript:
	return FACTORY if OS.get_cmdline_user_args().has("--factory") else SKINNED   # D-050: skinned is the default; --factory is the M22 body


func _ready() -> void:
	add_to_group("player")
	set_meta("is_character", true)
	_register_move_actions()
	_col_node = CollisionShape3D.new()
	_box_shape = BoxShape3D.new()
	_box_shape.size = COLLIDER_SIZE
	_col_node.shape = _box_shape
	_col_node.position = Vector3(0.0, COLLIDER_SIZE.y * 0.5, 0.0)  # origin at feet
	add_child(_col_node)
	# M9: Book gets the factory body — pearl snaps, dark denim, boots, the
	# charcoal flat-brim, and the buckle. Collider identical to M5.
	# M10: keep the rig so he actually walks.
	_rig = _body_script().build(self, FACTORY.book_config(), 0.0)


func _physics_process(delta: float) -> void:
	_iframes = maxf(_iframes - delta, 0.0)
	_mantle_cd = maxf(_mantle_cd - delta, 0.0)
	_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	_roll_cd = maxf(_roll_cd - delta, 0.0)

	# MANTLE: a scripted glide owns the body outright — input, gravity and the
	# run-over scan all wait the 0.35 s out (documented v1 simplification).
	if move_state == MoveState.MANTLE:
		is_sprinting = false
		_mantle_step(delta)
		_drive_rig(delta, 0.0, false, false, false)
		return

	# ROLL: same deal for the 0.42 s tuck — one scripted arc, no steering. Run-
	# over still applies (a car may absolutely flatten you mid-roll).
	if move_state == MoveState.ROLL:
		is_sprinting = false
		_roll_step(delta)
		_scan_runover()
		return

	var active := _is_active()
	var grounded := is_on_floor()          # result of LAST frame's slide
	var was_airborne := not grounded
	if grounded:
		_coyote_t = COYOTE_TIME
		_jump_active = false
	else:
		_coyote_t = maxf(_coyote_t - delta, 0.0)

	var move_dir := Vector3.ZERO
	var sprint := false
	var walk_mod := false
	if active:
		move_dir = _read_move_input()
		sprint = Input.is_action_pressed("sprint")
		walk_mod = InputMap.has_action("walk_slow") \
			and Input.is_action_pressed("walk_slow")
	if _land_recover_t > 0.0:  # hard landing: a beat with no legs under you
		_land_recover_t = maxf(_land_recover_t - delta, 0.0)
		move_dir = Vector3.ZERO
		sprint = false
	if _walkout_t > 0.0:  # M13: walking out of County General overrides the stick
		_walkout_t = maxf(_walkout_t - delta, 0.0)
		if health > 0.0:
			move_dir = Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
			sprint = false
	var moving := move_dir.length_squared() > 0.001
	var aiming := active and _combat_aiming()

	# --- Crouch verbs (toggle; grounded only; walkout stays hands-off) -------
	var verbs_ok := active and _walkout_t <= 0.0 and _land_recover_t <= 0.0
	if verbs_ok and InputMap.has_action("crouch") \
			and Input.is_action_just_pressed("crouch"):
		if _crouched:
			_try_stand()               # blocked under a slab? stay down, no-op
		elif grounded:
			_set_crouched(true)
	if _crouched and sprint and moving:
		_try_stand()  # sprint intent pops you up the frame headroom allows

	# --- Jump verbs ----------------------------------------------------------
	# ("jump" shares Space with the handbrake; the active guard keeps a parked
	# character from bunny-hopping while you drive.)
	if verbs_ok and Input.is_action_just_pressed("jump"):
		if aiming and grounded and moving and not _crouched and _roll_cd <= 0.0:
			# M19 DODGE: aiming turns Space from a hop into GTA's sideways dive.
			# Aiming is the only stance where it fires, so a normal jump can
			# never be eaten by it — the verb is additive, not a mode.
			_begin_roll(move_dir, DODGE_SPEED)
			_drive_rig(delta, 0.0, false, true, false)
			return
		if _crouched:
			_try_stand()               # crouched Space = stand up, not hop
		elif grounded or _coyote_t > 0.0:
			_do_jump()
		else:
			_jump_buffer = JUMP_BUFFER  # banked; fires on touchdown

	# --- Auto-mantle: moving into a low static ledge -------------------------
	if verbs_ok and moving and grounded and not _crouched and not aiming \
			and _mantle_cd <= 0.0 and _try_begin_mantle(move_dir):
		velocity = Vector3.ZERO
		is_sprinting = false
		_drive_rig(delta, 0.0, false, false, false)
		return

	# --- TIER + STAMINA ------------------------------------------------------
	# is_sprinting keeps its M16 meaning EXACTLY (foot_cops reads it): real
	# sprint intent while moving, never crouched. Being winded does not demote
	# you out of tier 2 — you are still sprinting, just badly.
	is_sprinting = sprint and moving and not _crouched
	var walking := _crouched or walk_mod \
		or (moving and move_dir.length() <= WALK_STICK_MAG)
	if is_sprinting:
		move_tier = MoveTier.SPRINT
	elif walking:
		move_tier = MoveTier.WALK
	else:
		move_tier = MoveTier.JOG
	_stamina_step(delta)
	_sprint_ramp = move_toward(_sprint_ramp, 1.0 if is_sprinting else 0.0,
		delta / (SPRINT_RAMP_TIME if is_sprinting else SPRINT_RAMP_FALL))

	# Horizontal: accelerate toward camera-relative intent, decelerate to rest.
	# Tier 1 (jog) is the floor the sprint ramp climbs FROM, so letting go of
	# Shift returns you to a jog, never to a standstill.
	var top := lerpf(SPRINT_WINDED_SPEED, SPRINT_SPEED,
		clampf(stamina / STAMINA_TIRED_BAND, 0.0, 1.0))
	var target_speed := lerpf(JOG_SPEED, top, _sprint_ramp)
	if move_tier == MoveTier.WALK:
		target_speed = minf(target_speed, WALK_SPEED)
	if _walkout_t > 0.0:              # D-016: the scripted beat sets its own pace
		target_speed = minf(target_speed, WALKOUT_SPEED)
	if _crouched:
		target_speed = minf(target_speed, CROUCH_SPEED)
	if has_meta("combat_speed_cap"):  # shooter stance: combat caps the stride
		var cap: Variant = get_meta("combat_speed_cap")
		if cap is float or cap is int:
			target_speed = minf(target_speed, float(cap))

	# --- STEERING: the heading is rate-limited by a SPEED curve --------------
	var steer_dir := move_dir
	var hvel := Vector3(velocity.x, 0.0, velocity.z)
	var speed_now := hvel.length()
	if moving and speed_now > WALK_SPEED:
		var cur := hvel / speed_now
		var want := move_dir.normalized()
		# A 180 costs a step: asking for a heading behind your velocity sheds
		# pace, and shedding pace tightens the turn (steer rate rises as speed
		# falls). The two effects together are what "costs a step" means.
		var d := cur.dot(want)
		if d < HARD_TURN_DOT:
			var hard := clampf((HARD_TURN_DOT - d) / (1.0 + HARD_TURN_DOT), 0.0, 1.0)
			target_speed *= lerpf(1.0, HARD_TURN_SPEED_MULT, hard)
		var ang := cur.signed_angle_to(want, Vector3.UP)
		var max_step := _steer_rate(speed_now) * delta
		steer_dir = cur.rotated(Vector3.UP, clampf(ang, -max_step, max_step)) \
			* move_dir.length()

	# --- THE PLANT: a committed stop out of a run ----------------------------
	if grounded and not moving and _plant_t <= 0.0 and speed_now >= PLANT_MIN_SPEED:
		_plant_t = PLANT_TIME
	var rate := ACCEL if moving else DECEL
	if _plant_t > 0.0:
		_plant_t = maxf(_plant_t - delta, 0.0)
		if moving:
			_plant_t = 0.0   # steering back in cancels it; the skid was yours
		else:
			steer_dir = Vector3.ZERO
			target_speed = 0.0
			rate = PLANT_DECEL
	if not grounded:
		rate *= AIR_CONTROL
	hvel = hvel.move_toward(steer_dir * target_speed, rate * delta)
	velocity.x = hvel.x
	velocity.z = hvel.z

	# Vertical: gravity, with the jump-cut boost — release Space on the way up
	# and gravity leans on you harder, so tap = hop and hold = full arc.
	if not grounded:
		var g := GRAVITY
		if _jump_active and velocity.y > 0.0 \
				and not (active and Input.is_action_pressed("jump")):
			g *= JUMP_CUT_GRAVITY_MULT
		velocity.y -= g * delta

	# Yaw: face travel direction, unless aiming — then face the camera yaw so
	# strafing reads like a shooter stance.
	if aiming:
		rotation.y = lerp_angle(rotation.y, _camera_yaw(), 1.0 - exp(-TURN_RATE * delta))
	elif moving:
		var face := steer_dir if steer_dir.length_squared() > 0.001 else move_dir
		var want_yaw := atan2(-face.x, -face.z)
		rotation.y = lerp_angle(rotation.y, want_yaw, 1.0 - exp(-TURN_RATE * delta))

	var vy_before := velocity.y
	move_and_slide()

	# Landing (floor state is fresh only after move_and_slide).
	if was_airborne and is_on_floor():
		_on_land(-vy_before)
		if move_state == MoveState.ROLL:
			# The landing became a roll. Hand the frame straight to the roll
			# path rather than falling through to the STAND/AIR classifier,
			# which would clobber the state it just set.
			_scan_runover()
			return

	# STATE (MANTLE and ROLL are set/cleared by their own paths above).
	if not is_on_floor():
		move_state = MoveState.AIR
	elif _crouched:
		move_state = MoveState.CROUCH
	else:
		move_state = MoveState.STAND

	# Walk cycle: gait phase advances with real ground speed, so the stride
	# always matches the distance covered — a crouch-walk at 1.8 m/s just
	# reads as careful steps. Aiming overrides it with a stance.
	var planar := Vector3(velocity.x, 0.0, velocity.z).length()
	_measure_accel(delta)
	_drive_rig(delta, planar, moving, is_on_floor(), aiming)
	_scan_runover()


# ============================== TIER / STAMINA ===============================
## Stamina drains ONLY in tier 2 and only while actually moving, refills after
## a short hold, and refills faster the less you are asking of your legs. There
## is no branch here that can refuse the sprint key — the cost is speed, never
## the verb, so this cannot create a state the player is stuck in (bar §4).
func _stamina_step(delta: float) -> void:
	if is_sprinting:
		stamina = maxf(stamina - delta / STAMINA_SPRINT_SECONDS, 0.0)
		_stamina_hold = STAMINA_RECOVER_DELAY
		return
	if _stamina_hold > 0.0:
		_stamina_hold = maxf(_stamina_hold - delta, 0.0)
		return
	var rate := STAMINA_RECOVER_JOG if move_tier == MoveTier.JOG \
		else STAMINA_RECOVER_REST
	stamina = minf(stamina + rate * delta, 1.0)


## Turn-rate curve, keyed on SPEED so the radius (v / omega) grows the faster
## you go. Two straight segments through three knots; the sprint half is bent
## by STEER_CURVE_POW so agility survives most of the jog band and then goes.
func _steer_rate(speed: float) -> float:
	if speed <= WALK_SPEED:
		return STEER_RATE_WALK
	if speed <= JOG_SPEED:
		var t := (speed - WALK_SPEED) / maxf(JOG_SPEED - WALK_SPEED, 0.001)
		return lerpf(STEER_RATE_WALK, STEER_RATE_JOG, t)
	var u := clampf((speed - JOG_SPEED) / maxf(SPRINT_SPEED - JOG_SPEED, 0.001),
		0.0, 1.0)
	return lerpf(STEER_RATE_JOG, STEER_RATE_SPRINT, pow(u, STEER_CURVE_POW))


## Planar acceleration in world space, exp-smoothed. The lean reads this; it is
## measured from the body's own velocity rather than from input, so a shove, a
## plant and a run-over all lean the body correctly for free.
func _measure_accel(delta: float) -> void:
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	if delta > 0.0001:
		var a := (hv - _prev_hvel) / delta
		_lean_accel = _lean_accel.lerp(a, 1.0 - exp(-LEAN_ACCEL_K * delta))
	_prev_hvel = hv


# ============================== JUMP / LAND ==================================
func _do_jump() -> void:
	velocity.y = JUMP_SPEED
	_jump_active = true
	_coyote_t = 0.0
	_jump_buffer = 0.0


func _on_land(fall_speed: float) -> void:
	_jump_active = false
	if fall_speed > HARD_LAND_SPEED:
		var hv := Vector3(velocity.x, 0.0, velocity.z)
		var trauma := clampf(HARD_LAND_TRAUMA_BASE
			+ (fall_speed - HARD_LAND_SPEED) * HARD_LAND_TRAUMA_PER_MPS,
			HARD_LAND_TRAUMA_BASE, HARD_LAND_TRAUMA_MAX)
		_jump_buffer = 0.0
		if hv.length() >= ROLL_MIN_SPEED and not _crouched:
			# M19: you were GOING somewhere. Tuck and roll — the momentum
			# survives, the beat of lost control does not, and the camera takes
			# a fraction of the hit because a roll is what absorbing looks like.
			_begin_roll(hv.normalized(), ROLL_SPEED)
			_camera_trauma(trauma * ROLL_TRAUMA_MULT)
		else:
			# Landing on the spot still buckles (the M16 beat, unchanged).
			_land_recover_t = HARD_LAND_RECOVER
			_camera_trauma(trauma)
		if FALL_DAMAGE_PER_MPS > 0.0:  # v1 knob, off by design (see const)
			take_damage((fall_speed - HARD_LAND_SPEED) * FALL_DAMAGE_PER_MPS)
	elif _jump_buffer > 0.0 and not _crouched:
		_do_jump()  # buffered press fires the frame you touch down


# ============================== ROLL =========================================
## One state, two doors: a hard landing with forward speed, and the aiming
## dodge-dive. Both are a scripted 0.42 s arc along a fixed heading with input
## ignored — the same contract MANTLE already established, so combat and melee
## can gate on `move_state` with one rule instead of two.
func _begin_roll(dir_in: Vector3, speed: float) -> void:
	var dir := Vector3(dir_in.x, 0.0, dir_in.z)
	_roll_dir = dir.normalized() if dir.length() > 0.01 \
		else Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	_roll_t = ROLL_TIME
	_roll_cd = DODGE_COOLDOWN
	_land_recover_t = 0.0
	_jump_buffer = 0.0
	move_state = MoveState.ROLL
	velocity = _roll_dir * speed


## The arc: speed eases from the entry value down to ROLL_EXIT_SPEED so you
## come up running rather than stopping dead, and gravity still applies (rolling
## off a ledge mid-roll is legal and lands you in AIR on the next frame).
func _roll_step(delta: float) -> void:
	_roll_t = maxf(_roll_t - delta, 0.0)
	var t := 1.0 - _roll_t / ROLL_TIME
	var sp := lerpf(ROLL_SPEED, ROLL_EXIT_SPEED, smoothstep(0.0, 1.0, t))
	velocity.x = _roll_dir.x * sp
	velocity.z = _roll_dir.z * sp
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		velocity.y = minf(velocity.y, 0.0)
	# The body faces where it is rolling — a dive is a committed direction.
	rotation.y = lerp_angle(rotation.y, atan2(-_roll_dir.x, -_roll_dir.z),
		1.0 - exp(-TURN_RATE * delta))
	move_and_slide()
	_measure_accel(delta)
	_drive_rig(delta, 0.0, false, is_on_floor(), false)
	if _roll_t <= 0.0:
		move_state = MoveState.CROUCH if _crouched else MoveState.STAND


## Null-safe peer call — the camera may be absent (headless, fallback cam).
func _camera_trauma(amount: float) -> void:
	var cam: Variant = main_ref.get("camera") if main_ref != null else null
	if cam is Object and is_instance_valid(cam) \
			and (cam as Object).has_method("add_trauma"):
		(cam as Object).call("add_trauma", amount)


# ============================== CROUCH =======================================
## The ONLY licensed collider change (house law): crouch shrinks the box to
## CROUCH_HEIGHT, feet-origin preserved. Standing restores the M5 envelope —
## and only ever through _try_stand()'s clearance probe.
func _set_crouched(down: bool) -> void:
	_crouched = down
	if _box_shape != null:
		_box_shape.size.y = CROUCH_HEIGHT if down else COLLIDER_SIZE.y
	if _col_node != null:
		_col_node.position.y = (CROUCH_HEIGHT if down else COLLIDER_SIZE.y) * 0.5
	if down:
		set_meta("is_crouched", true)
	elif has_meta("is_crouched"):
		remove_meta("is_crouched")


## Stand up ONLY if the head-space the standing collider needs is clear.
## Returns false (and stays crouched) under a low ceiling — the caller's
## intent simply retries later.
func _try_stand() -> bool:
	if not _crouched:
		return true
	if not _stand_clear():
		return false
	_set_crouched(false)
	return true


## Probe the band the standing collider adds above the crouched one
## (feet+1.125 .. feet+1.775, slightly slimmer than the body so brushing a
## wall never false-blocks). Anything solid in it — slab, truck chassis,
## another body — vetoes the stand.
func _stand_clear() -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	if _probe_shape == null:
		_probe_shape = BoxShape3D.new()
		_probe_shape.size = Vector3(COLLIDER_SIZE.x * 0.9,
			COLLIDER_SIZE.y - CROUCH_HEIGHT + STAND_PROBE_PAD,
			COLLIDER_SIZE.z * 0.9)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe_shape
	q.transform = Transform3D(Basis.IDENTITY, global_position
		+ Vector3.UP * ((CROUCH_HEIGHT + COLLIDER_SIZE.y) * 0.5))
	q.exclude = [get_rid()]
	return world.direct_space_state.intersect_shape(q, 1).is_empty()


# ============================== MANTLE =======================================
## Three probes, in order: (1) a face at shin height within reach, (2) a flat
## static top 0.4–1.1 m up just past that face, (3) stand-room for the whole
## body on the landing. All three pass -> the glide begins. STATIC geometry
## only in v1: parked/traffic cars are (frozen) RigidBodies and stay refused —
## the car-hood vault is a noted future verb.
func _try_begin_mantle(dir_in: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return false
	var dir := Vector3(dir_in.x, 0.0, dir_in.z)
	if dir.length() < 0.5:
		return false
	dir = dir.normalized()
	var space := world.direct_space_state
	var feet := global_position
	# (1) the obstacle's face, at a height every legal ledge must occupy
	var q := PhysicsRayQueryParameters3D.create(
		feet + Vector3.UP * MANTLE_FACE_PROBE_Y,
		feet + Vector3.UP * MANTLE_FACE_PROBE_Y + dir * MANTLE_AHEAD)
	q.exclude = [get_rid()]
	var face := space.intersect_ray(q)
	if face.is_empty() or not (face.get("collider") is StaticBody3D):
		return false
	# (2) the ledge top: drop a ray just past the face. Starting above
	# MANTLE_MAX means anything taller either reads too high or (solid all the
	# way up) swallows the ray — refused either way. No wall-climbing.
	var over: Vector3 = (face["position"] as Vector3) + dir * MANTLE_TOP_INSET
	var q2 := PhysicsRayQueryParameters3D.create(
		Vector3(over.x, feet.y + MANTLE_MAX + MANTLE_TOP_CLEAR, over.z),
		Vector3(over.x, feet.y + 0.05, over.z))
	q2.exclude = [get_rid()]
	var top := space.intersect_ray(q2)
	if top.is_empty() or not (top.get("collider") is StaticBody3D):
		return false
	var top_y := (top["position"] as Vector3).y
	var rise := top_y - feet.y
	if rise < MANTLE_MIN or rise > MANTLE_MAX:
		return false
	if (top.get("normal", Vector3.UP) as Vector3).y < 0.7:
		return false  # a slope face, not a ledge top
	# (3) the body must fit standing on the landing
	var land := Vector3(over.x, top_y + 0.02, over.z)
	if not _clear_for_body(land):
		return false
	_mantle_from = feet
	_mantle_to = land
	_mantle_t = MANTLE_TIME
	move_state = MoveState.MANTLE
	return true


## Stand-room check for a full standing body at candidate feet position.
func _clear_for_body(feet: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var shape := BoxShape3D.new()
	shape.size = Vector3(COLLIDER_SIZE.x * 0.9, COLLIDER_SIZE.y - 0.15,
		COLLIDER_SIZE.z * 0.9)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis.IDENTITY,
		feet + Vector3.UP * (shape.size.y * 0.5 + 0.08))
	q.exclude = [get_rid()]
	return world.direct_space_state.intersect_shape(q, 1).is_empty()


## The glide: rise first (MANTLE_UP_SHARE of the time), forward drift eases in
## from MANTLE_FWD_START — so the body clears the lip before it crosses it.
## Driven through velocity + move_and_slide (self-correcting against the
## face), never a teleport.
func _mantle_step(delta: float) -> void:
	_mantle_t = maxf(_mantle_t - delta, 0.0)
	var t := 1.0 - _mantle_t / MANTLE_TIME
	var up_w: float = smoothstep(0.0, 1.0, clampf(t / MANTLE_UP_SHARE, 0.0, 1.0))
	var fwd_w: float = smoothstep(MANTLE_FWD_START, 1.0, t)
	var desired := Vector3(
		lerpf(_mantle_from.x, _mantle_to.x, fwd_w),
		lerpf(_mantle_from.y, _mantle_to.y, up_w),
		lerpf(_mantle_from.z, _mantle_to.z, fwd_w))
	velocity = (desired - global_position) / maxf(delta, 0.0001)
	move_and_slide()
	if _mantle_t <= 0.0:
		var flat := _mantle_to - _mantle_from
		flat.y = 0.0
		velocity = flat.normalized() * MANTLE_EXIT_SPEED \
			if flat.length() > 0.01 else Vector3.ZERO
		move_state = MoveState.STAND
		_mantle_cd = MANTLE_COOLDOWN


# ============================== RIG DRIVING ==================================
## One funnel for the factory handshake: strip last frame's crouch offsets so
## the factory's exponential blends see the pure gait pose, step the gait (or
## the aim stance), then re-apply the crouch pose at the current eased weight.
## The factory itself is never edited — we only pose the rig's joint nodes.
func _drive_rig(delta: float, planar: float, moving: bool, grounded: bool,
		aiming: bool) -> void:
	_strip_pose()
	if aiming and planar < 0.4:
		FACTORY.aim_pose(_rig, delta)
	else:
		FACTORY.animate(_rig, planar, delta, moving, grounded)
	_drive_head_look(delta, aiming)
	_drive_lean(delta)
	var target := 1.0 if (_crouched and grounded) else 0.0
	_crouch_pose_w = lerpf(_crouch_pose_w, target, 1.0 - exp(-CROUCH_POSE_K * delta))
	if _crouch_pose_w < 0.001:
		_crouch_pose_w = 0.0
	var rt := 0.0
	if move_state == MoveState.ROLL:
		rt = sin(PI * clampf(1.0 - _roll_t / ROLL_TIME, 0.0, 1.0))
	_roll_pose_w = lerpf(_roll_pose_w, rt, 1.0 - exp(-ROLL_POSE_K * delta))
	if _roll_pose_w < 0.001:
		_roll_pose_w = 0.0
	_apply_pose()


## HEAD LOOK. The head tracks the CAMERA, the body tracks its travel — that
## split is most of why a GTA character reads as a person steering a body
## instead of a turret. Yaw is the camera yaw minus the body yaw, clamped to a
## human neck; past the clamp you have to turn the body, which is the point.
##
## OWNERSHIP: `character_factory.animate()` writes head.rotation.X only, so
## head.rotation.Y is free — EXCEPT that melee.gd owns it (with torso.y and
## sh.z) while striking or guarding, and this body's _physics_process runs
## AFTER the systems, so writing unconditionally would silently delete melee's
## "eyes stay on the man". We yield instead. Pitch is ADDITIVE over the
## factory's value and is stripped next frame like the crouch pose.
func _drive_head_look(delta: float, aiming: bool) -> void:
	var head: Variant = _rig.get("head")
	if not (head is Node3D and is_instance_valid(head)):
		return
	var k := 1.0 - exp(-HEAD_LOOK_K * delta)
	var want_yaw := 0.0
	var want_pitch := 0.0
	if move_state != MoveState.MANTLE and move_state != MoveState.ROLL:
		want_yaw = clampf(wrapf(_camera_yaw() - rotation.y, -PI, PI),
			-HEAD_YAW_MAX, HEAD_YAW_MAX)
		# Camera pitch is +up (fwd.y = sin(pitch)); a head nods down on a
		# POSITIVE rotation.x (the factory counter-rotates it NEGATIVE against
		# a forward torso lean to keep the eyes level), so the sign flips.
		var follow := HEAD_AIM_PITCH_FOLLOW if aiming else HEAD_PITCH_FOLLOW
		want_pitch = clampf(-_camera_pitch() * follow,
			-HEAD_PITCH_MAX, HEAD_PITCH_MAX)
	_head_yaw = lerp_angle(_head_yaw, want_yaw, k)
	_head_pitch = lerpf(_head_pitch, want_pitch, k)
	if not _melee_posing():
		(head as Node3D).rotation.y = _head_yaw


## LEAN. Root tilt on rig["vis"], which pivots at the FEET, so the boots stay
## planted; LEAN_SINK_PER_RAD sinks the body the sliver a tilt would otherwise
## lift the outside foot by (the same trick CROUCH_VIS_DROP uses). Driven by
## MEASURED acceleration rather than by input, so a plant leans you back and a
## sprint launch leans you forward without either being special-cased.
##   bank:  rotation.z is NEGATIVE to tilt the top toward +X (local right), so
##          leaning INTO a right-hand turn is -k * a_right.
##   lean:  rotation.x is NEGATIVE to tilt the top toward -Z (forward).
## Both verified by POSITION in aa_move_probe (D-020's standing rule), never
## by reading the angles back.
func _drive_lean(delta: float) -> void:
	var vis: Variant = _rig.get("vis")
	if not (vis is Node3D and is_instance_valid(vis)):
		return
	var fwd := Vector3(-sin(rotation.y), 0.0, -cos(rotation.y))
	var right := Vector3(cos(rotation.y), 0.0, -sin(rotation.y))
	var want_roll := 0.0
	var want_pitch := 0.0
	if move_state != MoveState.MANTLE and move_state != MoveState.ROLL:
		want_roll = clampf(-_lean_accel.dot(right) * LEAN_ROLL_PER_MPS2,
			-LEAN_ROLL_MAX, LEAN_ROLL_MAX)
		want_pitch = clampf(-_lean_accel.dot(fwd) * LEAN_PITCH_PER_MPS2,
			-LEAN_PITCH_MAX, LEAN_PITCH_MAX)
	var k := 1.0 - exp(-LEAN_K * delta)
	_lean_roll = lerpf(_lean_roll, want_roll, k)
	_lean_pitch = lerpf(_lean_pitch, want_pitch, k)
	var n := vis as Node3D
	n.rotation.z = _lean_roll
	n.rotation.x = _lean_pitch


## Melee owns head.rotation.y / torso.rotation.y / sh.rotation.z while a swing
## or a guard is live (melee.gd:513-519). We run after it, so we yield the yaw.
func _melee_posing() -> bool:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var m: Variant = (sys as Dictionary).get("melee")
		if m is Object and is_instance_valid(m):
			return (m as Object).get("is_striking") == true \
				or (m as Object).get("is_guarding") == true
	return false


func _strip_pose() -> void:
	if not _pose_applied.is_empty():
		for joint: String in _pose_applied:
			var n: Variant = _rig.get(joint)
			if n is Node3D and is_instance_valid(n):
				(n as Node3D).rotation.x -= float(_pose_applied[joint])
		_pose_applied.clear()
	if _vis_y_applied != 0.0:
		var vis: Variant = _rig.get("vis")
		if vis is Node3D and is_instance_valid(vis):
			(vis as Node3D).position.y += _vis_y_applied
		_vis_y_applied = 0.0


## One additive pass over rotation.x: the crouch stance, the roll tuck and the
## head's look-pitch are SUMMED per joint before they touch the rig, so two
## poses at once (crouch-walking off a ledge into a roll) can never double-apply
## or leave a residue — _strip_pose subtracts exactly what this recorded.
func _apply_pose() -> void:
	var off: Dictionary = {}
	if _crouch_pose_w > 0.0:
		for joint: String in CROUCH_POSE:
			off[joint] = float(CROUCH_POSE[joint]) * _crouch_pose_w
	if _roll_pose_w > 0.0:
		for joint: String in ROLL_POSE:
			off[joint] = float(off.get(joint, 0.0)) \
				+ float(ROLL_POSE[joint]) * _roll_pose_w
	if absf(_head_pitch) > 0.0001:
		off["head"] = float(off.get("head", 0.0)) + _head_pitch
	for joint: String in off:
		var n: Variant = _rig.get(joint)
		if n is Node3D and is_instance_valid(n):
			var a := float(off[joint])
			(n as Node3D).rotation.x += a
			_pose_applied[joint] = a
	var vis: Variant = _rig.get("vis")
	if vis is Node3D and is_instance_valid(vis):
		# The tilt sink keeps the outside boot on the ground: a body pivoting at
		# the feet lifts its far edge, so drop the root by the tilt it just took.
		_vis_y_applied = CROUCH_VIS_DROP * _crouch_pose_w \
			+ ROLL_VIS_DROP * _roll_pose_w \
			+ LEAN_SINK_PER_RAD * (absf(_lean_roll) + absf(_lean_pitch))
		(vis as Node3D).position.y -= _vis_y_applied


## RUN-OVER: any RigidBody3D in the slide collisions moving faster than
## RUNOVER_MIN_SPEED deals 6x its speed and shoves the character (comedy is
## physics: you inherit its momentum). Runs even while parked — a parked
## character reads no input but can absolutely still be hit by traffic.
func _scan_runover() -> void:
	if _iframes > 0.0:
		return
	for i in get_slide_collision_count():
		var col := get_slide_collision(i)
		if col == null:
			continue
		var other := col.get_collider()
		if not (other is RigidBody3D):
			continue
		var striker := other as RigidBody3D
		var sp := striker.linear_velocity.length()
		if sp <= RUNOVER_MIN_SPEED:
			continue
		_iframes = RUNOVER_IFRAMES
		velocity += striker.linear_velocity * RUNOVER_CARRY + Vector3.UP * RUNOVER_POP
		take_damage(sp * RUNOVER_DMG_PER_MPS, striker)
		return


# ============================== HEALTH =======================================
func take_damage(amount: float, _source: Node = null) -> void:
	if amount <= 0.0 or health <= 0.0:
		return
	health = maxf(health - amount, 0.0)
	health_changed.emit(health)
	if health <= 0.0:
		died.emit()


func heal(amount: float) -> void:
	if amount <= 0.0:
		return
	health = minf(health + amount, MAX_HEALTH)
	health_changed.emit(health)


## M13: on_foot.gd calls this at the hospital respawn — Book walks himself out
## the ER doors for `t` seconds (a real physics walk, so gait/camera all work)
## before the player takes over. M16: he leaves on his feet — the crouch latch
## pops (the ER doorway is open air) and any banked jump/stagger is cleared.
func begin_walkout(t: float) -> void:
	_walkout_t = t
	_try_stand()
	_jump_buffer = 0.0
	_land_recover_t = 0.0
	# M19: County General discharges you rested and upright. Any plant, roll or
	# lean left over from however you died is cleared, so frame one of the
	# walk-out is a clean jog cycle (perf_harness's `hospital_door` station is
	# derived from exactly this frame — see on_foot.gd:243).
	_plant_t = 0.0
	_roll_t = 0.0
	_roll_pose_w = 0.0
	_roll_cd = 0.0
	_lean_accel = Vector3.ZERO
	_lean_roll = 0.0
	_lean_pitch = 0.0
	_prev_hvel = Vector3.ZERO
	stamina = 1.0
	_stamina_hold = 0.0
	move_state = MoveState.STAND
	move_tier = MoveTier.JOG


# ============================== INPUT BASIS ==================================
## Active only when this body IS "the player": on foot, registered on main,
## alive, and the tree not paused. Everything else leaves it a physics prop.
func _is_active() -> bool:
	if health <= 0.0 or get_tree() == null or get_tree().paused:
		return false
	return main_ref != null and is_instance_valid(main_ref) \
		and main_ref.get("on_foot") == true and main_ref.get("character") == self


## WASD via the shared driving actions (they are bound to WASD/arrows), mapped
## through the camera's yaw so "forward" is always where the player is looking.
func _read_move_input() -> Vector3:
	var fwd := Vector3.FORWARD
	var right := Vector3.RIGHT
	var cam: Variant = main_ref.get("camera") if main_ref != null else null
	if cam is Node3D and is_instance_valid(cam):
		var yaw_v: Variant = (cam as Object).get("orbit_yaw")
		if typeof(yaw_v) == TYPE_FLOAT:
			var a := float(yaw_v)
			fwd = Vector3(-sin(a), 0.0, -cos(a))
			right = Vector3(cos(a), 0.0, -sin(a))
		else:  # camera without a foot rig: flatten its -Z
			var cf: Vector3 = -(cam as Node3D).global_transform.basis.z
			cf.y = 0.0
			if cf.length() > 0.01:
				fwd = cf.normalized()
				right = Vector3(-fwd.z, 0.0, fwd.x)
	var f := Input.get_action_strength("accelerate") - Input.get_action_strength("brake_reverse")
	var r := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
	return (fwd * f + right * r).limit_length(1.0)


func _camera_yaw() -> float:
	var cam: Variant = main_ref.get("camera") if main_ref != null else null
	if cam is Object and is_instance_valid(cam):
		var yaw_v: Variant = (cam as Object).get("orbit_yaw")
		if typeof(yaw_v) == TYPE_FLOAT:
			return float(yaw_v)
	return rotation.y


## The foot rig's pitch, +up. Public on the camera alongside orbit_yaw (M19);
## a camera without a foot rig reports level, which reads as "eyes forward".
func _camera_pitch() -> float:
	var cam: Variant = main_ref.get("camera") if main_ref != null else null
	if cam is Object and is_instance_valid(cam):
		var p: Variant = (cam as Object).get("orbit_pitch")
		if typeof(p) == TYPE_FLOAT:
			return float(p)
	return 0.0


func _combat_aiming() -> bool:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var combat: Variant = (sys as Dictionary).get("combat")
		if combat is Object and is_instance_valid(combat):
			return (combat as Object).get("is_aiming") == true
	return false


# (M9: the old 4-box build moved into scripts/world/character_factory.gd —
# one anatomy for the whole population.)
