extends Node
## POLICE + WANTED v1 — heat 0..3, cruiser spawn/maintain, dumb-aggressive
## pursuit, escape decay, star HUD. Peers call main.systems["police"].add_heat().
## The pursued ACTOR (character on foot, vehicle otherwise) is re-read from
## main_ref each use (Tab and E both replace it).
## Design bias: dumb cops that ram and overshoot beat smart cops.

signal heat_changed(heat: int)

# ============================== TUNABLES =====================================
const CRUISER_PROFILE := "res://data/vehicles/ai/police.json"
const MAX_HEAT := 5                  # M23: GTA scale. Also the cruiser cap: min(heat, MAX_HEAT)
# ---- M23 SEARCH (line of sight) ----------------------------------------------
# Distance-based escape let a player shed stars by outrunning nothing in
# particular. Now the police have to SEE you: every LOS_INTERVAL each cruiser and
# officer casts a ray at the player; LOS_LOST_SECONDS without a single clear ray
# opens a search around the last sighting. Cruisers sweep the circle instead of
# homing, spawns anchor on it, and stars decay only while you stay unseen.
const LOS_INTERVAL := 0.3            # s between sight checks
const LOS_LOST_SECONDS := 3.0        # unseen this long -> search
const LOS_EYE := 1.2                 # ray origin above a cruiser's origin (m)
const LOS_RANGE := 140.0             # m: beyond this nobody sees anything (probe: an unbounded
                                     # ray saw a player 400 m away across open ground)
const LOS_TARGET := 1.0              # ray target above the player's origin (m)
const SEARCH_BASE := 70.0            # m radius at 1 star
const SEARCH_PER_HEAT := 35.0        # + per star
const SEARCH_GROW := 1.15            # radius growth per decay tick (they widen the net)
const PATROL_REROLL := 6.0           # s a cruiser holds one sweep point
const PATROL_REACH := 8.0            # m: reached, roll a new point
const ESCALATE_HEAT := 4             # from here: faster spawns, hotter cruisers
const ESCALATE_POWER := 0.06         # +power_modifier per star above 3
const SPAWN_DIST_MIN := 100.0        # cruisers appear 100-160 m from the player
const SPAWN_DIST_MAX := 160.0
const SPAWN_Y := 1.2
const SPAWN_INTERVAL := 2.0          # s between spawns (no 3-cop pile-in blink)
const ESCAPE_DISTANCE := 250.0       # all cops beyond this -> escape timer runs
const ESCAPE_SECONDS := 12.0         # continuous clean-gap seconds per -1 heat
const SPAWN_PAUSE_AFTER := 3.0       # clean-gap seconds after which spawns pause
const DESPAWN_DISTANCE := 400.0      # lost cops teleport home via respawn
const FAR_GRACE := 4.0               # min cruiser age before far-despawn (s)
const RAM_HEAT_SPEED := 8.0          # m/s closing speed on contact for +1 heat
const RAM_COOLDOWN := 5.0
const PURSUIT_LEAD := 0.5            # s of player velocity to lead the target
const FOOT_CHASE_DIST := 18.0        # cruiser this close to an on-foot actor...
const FOOT_CHASE_THROTTLE := 0.45    # ...caps throttle: menace, don't pancake
# PULL-ALONGSIDE (D-057): at low heat a target that has STOPPED gets the arrest,
# not the ram. Inside PULLOVER_RANGE the cruiser eases in and parks at
# PULLOVER_STOP from the actor's origin — inside arrest.gd's cruiser reach —
# and holds there while the actor stays still. Moving again releases the chase.
const PULLOVER_MAX_HEAT := 2         # 3+ stars: they ram, they shoot, they do not park
const PULLOVER_STILL := 2.0          # m/s: the actor counts as stopped under this
const PULLOVER_RANGE := 45.0         # m: from here the approach is an approach
const PULLOVER_STOP := 5.0           # m: park here (origin to origin)
const PULLOVER_HOLD_SLACK := 3.0     # m: once parked, hold the brake out to this
const PULLOVER_EASE_DIST := 20.0     # m over which the throttle eases off
const PULLOVER_THROTTLE := Vector2(0.18, 0.55)  # min..max while easing in
# TAIL (D-064): at low heat a SLOW driver (a slab comin' down at 5 m/s) is not
# rammed either — the cruiser falls in TAIL_GAP behind him and matches speed,
# riding the bumper. Speed up past PULLOVER_SLOW and it is a chase again.
const PULLOVER_SLOW := 8.0           # m/s: under this, cruisers tail instead of ram
const TAIL_GAP := 7.0                # m behind the actor the tail wants to sit
const TAIL_CLOSE_GAIN := 0.5         # m/s of extra speed per metre of gap past the slot
const PULLOVER_SPEED_GAIN := 0.5     # wanted approach speed = gap x this (m/s per m)
const PULLOVER_CREEP := 1.5          # m/s floor: the last metres are a creep, never a ram
const PULLOVER_APPROACH_MAX := 9.0   # m/s ceiling on the approach (RAM_HEAT_SPEED is 8 at contact)
const STEER_FULL_ANGLE_DEG := 30.0   # error angle that saturates the steer
const SLIDE_ANGLE_DEG := 70.0        # off-axis error that triggers a handbrake
const SLIDE_MIN_SPEED := 12.0
const STUCK_SPEED := 1.0
const STUCK_SECONDS := 2.0
const REVERSE_SECONDS := 1.2
const FLIP_UP_DOT := 0.2             # up.dot(Y) below this counts as flipped
const FLIP_SECONDS := 3.0
const LIGHTBAR_HZ := 3.0             # red/blue swaps per second
const LIGHTBAR_Y := 0.76             # roof height for the lightbar (body 1.35)
const LIGHTBAR_Z := -0.35            # slightly toward the nose (forward is -Z)
const FLASH_SECONDS := 1.6           # WANTED/EVADED banner fade time
const STAR_FULL := Color(1.0, 0.82, 0.2)
const STAR_DIM := Color(0.45, 0.45, 0.5, 0.55)
const RNG_SEED := 0xD0AD0
# Downtown layout mirrored from scripts/world/greybox_city.gd: N-S street
# centrelines x = 193 + 86*i (i 0..6), E-W z = 133 + 86*j (j 0..4), frontage
# roads at z = +/-30. The protected smoke corridor below must stay clear.
const BLOCK := 60.0
const STREET := 26.0
const GRID_COLS := 8
const GRID_ROWS := 6
const GRID_WEST := 120.0
const GRID_NORTH := 60.0
const FRONTAGE_Z := 30.0
const CORRIDOR := Rect2(180.0, 430.0, 26.0, 140.0)  # protected smoke corridor
const CORRIDOR_MARGIN := 6.0

# ============================== STATE ========================================
var heat: int = 0
# PUBLIC (hud_gta): the search circle. Meaningful only while search_active.
var search_active := false
var search_center := Vector3.ZERO
var search_radius := 0.0
var _search_rng := RandomNumberGenerator.new()   # runtime sweep jitter ONLY — never a spawn draw
var _last_seen := Vector3.ZERO
var _lost_t := 0.0
var _los_cd := 0.0
var main_ref: Node = null
var cruisers: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _ram_cd := 0.0
var _escape_t := 0.0
var _spawn_cd := 0.0
var _flash_t := 0.0
var _spawned_total := 0

var _ui: CanvasLayer = null
var _stars: Array[Label] = []
var _banner: Label = null
var _banner_sub: Label = null        # the reason line under WANTED
var _banner_t := 0.0
var last_reason := ""                # PUBLIC (HUD, arrest): why the last star lit


func setup(main: Node) -> void:
	main_ref = main
	_rng.seed = RNG_SEED
	_search_rng.seed = 0x5EA4C4
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		set_process(false)
		return  # smoke gate: fully inert
	_build_ui()


# ============================== PUBLIC API ===================================
## `reason` is the crime, in the player's words ("GRAND THEFT AUTO", "HIT A
## PEDESTRIAN"): DNA §4 says heat must be LEGIBLE, so every star that lights says
## why, under the WANTED banner. Callers that pass nothing still work.
func add_heat(n: int, reason: String = "") -> void:
	var new_heat := clampi(heat + n, 0, MAX_HEAT)
	if new_heat == heat:
		return
	var went_up := new_heat > heat
	heat = new_heat
	if went_up:
		_escape_t = 0.0  # fresh pursuit: re-arm spawning and the escape clock
		if reason != "":
			last_reason = reason
		_show_banner("WANTED", Color(0.95, 0.2, 0.15), reason)
	elif heat == 0:
		_despawn_all()
		_escape_t = 0.0
		last_reason = ""
		_show_banner("EVADED", Color(0.35, 0.9, 0.45))
	_update_stars()
	heat_changed.emit(heat)


## PUBLIC (carjack): somebody just took this cruiser. It leaves the pursuit
## roster and the "police" group WITHOUT being freed — it is the player's ride
## now, and a car that is still in the group would draw its own sirens, count
## itself as a witness to its own driver, and take pistol damage as a cruiser.
## Returns [mat_red, mat_blue] so the thief can keep the bar strobing.
func release_cruiser(body: Node) -> Array:
	var mats: Array = []
	for c in cruisers.duplicate():
		if c["body"] != body:
			continue
		mats = [c["mat_red"], c["mat_blue"]]
		cruisers.erase(c)
		break
	if not is_instance_valid(body):
		return mats
	if body.is_in_group("police"):
		body.remove_from_group("police")
	# Ram-heat handler is already inert for a stolen unit (it only fires when
	# the OTHER body is the pursued actor, and a cruiser never reports itself),
	# but a live connection into our roster is a dangling contract: drop it.
	if body.has_signal("body_entered"):
		var cb := _on_cruiser_body_entered.bind(body)
		if body.is_connected("body_entered", cb):
			body.disconnect("body_entered", cb)
	# Whatever combat did to it, it is a civilian vehicle now — nothing in this
	# system will ever re-issue the crippled brake hold.
	if body.has_meta("combat_crippled"):
		body.remove_meta("combat_crippled")
	if body.has_meta("combat_hp"):
		body.remove_meta("combat_hp")
	return mats


# ============================== PER-FRAME ====================================
func _physics_process(delta: float) -> void:
	if main_ref == null:
		return
	_ram_cd = maxf(_ram_cd - delta, 0.0)
	_spawn_cd = maxf(_spawn_cd - delta, 0.0)
	cruisers.assign(cruisers.filter(func(c: Dictionary) -> bool: return is_instance_valid(c["body"])))
	if heat <= 0:
		if not cruisers.is_empty():
			_despawn_all()
		return
	var pv := _player()
	if pv == null:
		return

	# Escape decay: clean gap (no cruiser inside ESCAPE_DISTANCE; vacuously
	# true with zero cruisers) held ESCAPE_SECONDS continuously -> heat -1.
	# On foot the full 250 m gap is unwalkable at 7 m/s — hiding behind downtown
	# blocks at 100 m can shed stars instead (the truck may be parked deep in
	# cop country and dying shouldn't be the only exit).
	# M23: sight, not distance. Vacuously unseen with zero units on the street.
	_los_cd -= delta
	if _los_cd <= 0.0:
		_los_cd = LOS_INTERVAL
		if _anyone_sees(pv):
			_last_seen = pv.global_position
			_lost_t = 0.0
			if search_active:
				search_active = false   # spotted: the chase is back on
				_escape_t = 0.0
		else:
			_lost_t += LOS_INTERVAL
			if not search_active and _lost_t >= LOS_LOST_SECONDS:
				search_active = true
				search_center = _last_seen if _last_seen != Vector3.ZERO else pv.global_position
				search_radius = SEARCH_BASE + SEARCH_PER_HEAT * float(heat)
				for c in cruisers:
					c["patrol_t"] = 0.0
	if search_active:
		_escape_t += delta
		if _escape_t >= ESCAPE_SECONDS:
			_escape_t = 0.0  # re-arms spawning -> next wave if heat > 0
			add_heat(-1)
			if heat <= 0:
				return
			# They widen the net and shift the centre: a sweep, not a stakeout.
			search_radius *= SEARCH_GROW
			search_center += Vector3(_search_rng.randf_range(-1.0, 1.0), 0.0,
				_search_rng.randf_range(-1.0, 1.0)) * search_radius * 0.3
	else:
		_escape_t = 0.0

	# Lost cops despawn beyond DESPAWN_DISTANCE (age grace stops spawn thrash).
	for c in cruisers.duplicate():
		c["age"] = float(c["age"]) + delta
		var body: Node3D = c["body"]
		if float(c["age"]) > FAR_GRACE \
				and body.global_position.distance_to(pv.global_position) > DESPAWN_DISTANCE:
			_despawn(c)

	# Maintain min(heat, MAX_HEAT) cruisers both ways: trim newest-first on a
	# heat drop; spawn when short (paused during a clean gap so escape works).
	var want := mini(heat, MAX_HEAT)
	while cruisers.size() > want:
		_despawn(cruisers.back())
	if cruisers.size() < want and _spawn_cd <= 0.0 and _escape_t < SPAWN_PAUSE_AFTER:
		_spawn_cruiser(pv)
		_spawn_cd = SPAWN_INTERVAL if heat < ESCALATE_HEAT else maxf(0.8, SPAWN_INTERVAL - 0.4 * float(heat - 3))

	for c in cruisers.duplicate():
		_drive(c, delta, pv)


func _process(delta: float) -> void:
	# Lightbar strobe: one shared clock, red/blue emission swapped at ~3 Hz.
	_flash_t += delta
	var red_on := fmod(_flash_t * LIGHTBAR_HZ, 1.0) < 0.5
	for c in cruisers:
		if not is_instance_valid(c["body"]):
			continue
		(c["mat_red"] as StandardMaterial3D).emission_energy_multiplier = 4.0 if red_on else 0.15
		(c["mat_blue"] as StandardMaterial3D).emission_energy_multiplier = 0.15 if red_on else 4.0
	if _banner != null and _banner_t > 0.0:
		_banner_t -= delta
		_banner.modulate.a = clampf(_banner_t / (FLASH_SECONDS * 0.5), 0.0, 1.0)
		if _banner_sub != null:
			_banner_sub.modulate.a = _banner.modulate.a
		if _banner_t <= 0.0:
			_banner.visible = false
			if _banner_sub != null:
				_banner_sub.visible = false


# ============================== PURSUIT AI ===================================
func _drive(c: Dictionary, delta: float, pv: Node3D) -> void:
	var body: RaycastVehicle = c["body"]
	if not is_instance_valid(body) or not body.is_inside_tree():
		return
	# Combat cripples cruisers via meta; without this gate _drive would re-issue
	# fresh inputs every tick and instantly "heal" a crippled car.
	if body.has_meta("combat_crippled"):
		body.set_external_input(0.0, 1.0, 0.0, true)  # dead in the water
		return
	var up := body.global_transform.basis.y
	var fwd := -body.global_transform.basis.z

	# Flipped for FLIP_SECONDS -> despawn (maintenance respawns it elsewhere).
	if up.dot(Vector3.UP) < FLIP_UP_DOT:
		c["flip_t"] = float(c["flip_t"]) + delta
		if float(c["flip_t"]) >= FLIP_SECONDS:
			_despawn(c)
			return
	else:
		c["flip_t"] = 0.0

	# Pursuit point leads the actor by PURSUIT_LEAD seconds of velocity.
	var target := pv.global_position + _actor_velocity(pv) * PURSUIT_LEAD
	if search_active:
		# Sweep: hold a random point inside the circle for PATROL_REROLL s or
		# until reached, then roll another. No lead — they are not chasing you.
		c["patrol_t"] = float(c.get("patrol_t", 0.0)) - delta
		var pp: Vector3 = c.get("patrol_p", search_center)
		if float(c["patrol_t"]) <= 0.0 or body.global_position.distance_to(pp) < PATROL_REACH:
			var ang := _search_rng.randf() * TAU
			var r := sqrt(_search_rng.randf()) * search_radius
			pp = search_center + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			c["patrol_p"] = pp
			c["patrol_t"] = PATROL_REROLL
		target = pp
	var to_t := target - body.global_position
	to_t -= up * to_t.dot(up)  # flatten into the cruiser's ground plane

	# Cache pre-contact closing speed for ram-heat: body_entered fires AFTER the
	# solver has consumed the impact, so the handler must read this instead.
	var sep := body.global_position - pv.global_position
	var sep_len := sep.length()
	if sep_len > 0.01 and sep_len < 12.0:
		c["closing"] = (_actor_velocity(pv) - body.linear_velocity).dot(sep / sep_len)
	else:
		c["closing"] = 0.0
	# The tail: heat 1-2, the actor SLOW but moving — fall in behind and match.
	var av := _actor_velocity(pv)
	if heat <= PULLOVER_MAX_HEAT and not search_active and sep_len < PULLOVER_RANGE \
			and av.length() >= PULLOVER_STILL and av.length() < PULLOVER_SLOW:
		c["stuck_t"] = 0.0; c["pulled"] = false
		var adir := av.normalized()
		var slot := pv.global_position - adir * TAIL_GAP
		var to_slot := slot - body.global_position; to_slot -= up * to_slot.dot(up)
		var gap := to_slot.length()
		var want := clampf(av.length() + gap * TAIL_CLOSE_GAIN, 1.0, av.length() + 6.0)
		var a_t := fwd.signed_angle_to(to_slot.normalized(), up) if gap > 0.5 else 0.0
		var s_t := clampf(a_t / deg_to_rad(STEER_FULL_ANGLE_DEG), -1.0, 1.0)
		var v_t := body.linear_velocity.length()
		if v_t > want + 0.5:
			body.set_external_input(0.0, clampf((v_t - want) / 4.0, 0.3, 1.0), s_t, false)
		else:
			body.set_external_input(clampf(0.25 + gap * 0.03, 0.25, 0.7), 0.0, s_t, false)
		return
	# The arrest approach: heat 1-2, the actor still, the cruiser near — park, hold.
	if heat <= PULLOVER_MAX_HEAT and not search_active and sep_len < PULLOVER_RANGE \
			and av.length() < PULLOVER_STILL:
		c["stuck_t"] = 0.0  # a deliberate stop is not a stuck cruiser
		var parked: bool = c.get("pulled", false) == true
		if sep_len <= PULLOVER_STOP or (parked and sep_len <= PULLOVER_STOP + PULLOVER_HOLD_SLACK):
			c["pulled"] = true
			# Handbrake only: below 0.5 m/s a brake input is REVERSE in raycast_vehicle,
			# and the park hold (D-059) needs both pedals up to take over.
			body.set_external_input(0.0, 0.0, 0.0, true)
			return
		var gap := sep_len - PULLOVER_STOP
		var ease := clampf(gap / PULLOVER_EASE_DIST, 0.0, 1.0)
		var t_in := lerpf(PULLOVER_THROTTLE.x, PULLOVER_THROTTLE.y, ease)
		var a_in := fwd.signed_angle_to(to_t.normalized(), up) if to_t.length() > 0.5 else 0.0
		var s_in := clampf(a_in / deg_to_rad(STEER_FULL_ANGLE_DEG), -1.0, 1.0)
		# Speed follows the gap down: carrying more than that into the last metres
		# is a ram (+1 heat at RAM_HEAT_SPEED), so brake it off instead of coasting.
		var want := clampf(gap * PULLOVER_SPEED_GAIN, PULLOVER_CREEP, PULLOVER_APPROACH_MAX)
		var v_in := body.linear_velocity.length()
		if v_in > want + 0.5:
			body.set_external_input(0.0, clampf((v_in - want) / 4.0, 0.3, 1.0), s_in, false)
		else:
			body.set_external_input(t_in, 0.0, s_in, false)
		return
	c["pulled"] = false
	if to_t.length() < 1.0:
		body.set_external_input(0.3, 0.0, 0.0, false)
		return
	# Sign check (see raycast_vehicle.gd): steer +1 = LEFT (wheel_forward is
	# rotated by +steer around up, swinging toward -X). signed_angle_to(t, up)
	# is positive when the target is left of forward -> pass through, no flip.
	var angle := fwd.signed_angle_to(to_t.normalized(), up)
	var steer := clampf(angle / deg_to_rad(STEER_FULL_ANGLE_DEG), -1.0, 1.0)
	var speed := body.linear_velocity.length()

	# Stuck: back out with inverted steer (nose swings to target), then resume.
	if float(c["rev_t"]) > 0.0:
		c["rev_t"] = float(c["rev_t"]) - delta
		body.set_external_input(0.0, 1.0, -steer, false)
		return
	if speed < STUCK_SPEED:
		c["stuck_t"] = float(c["stuck_t"]) + delta
		if float(c["stuck_t"]) >= STUCK_SECONDS:
			c["stuck_t"] = 0.0
			c["rev_t"] = REVERSE_SECONDS
			body.set_external_input(0.0, 1.0, -steer, false)
			return
	else:
		c["stuck_t"] = 0.0

	# Throttle 1.0 always — including closing fast inside 12 m: ramming is the
	# point, overshoot is the comedy. Only spice: an off-axis handbrake lunge.
	# Exception: near an on-foot actor, cap the throttle so cruisers menace and
	# cut off instead of endlessly pancaking the character (funny, not lethal).
	var handbrake := absf(angle) > deg_to_rad(SLIDE_ANGLE_DEG) and speed > SLIDE_MIN_SPEED
	var throttle := 1.0
	if not (pv is RigidBody3D) and sep_len < FOOT_CHASE_DIST:
		throttle = FOOT_CHASE_THROTTLE
	body.set_external_input(throttle, 0.0, steer, handbrake)


# ============================== SPAWNING =====================================
func _spawn_cruiser(pv: Node3D) -> void:
	var anchor := search_center if search_active else pv.global_position
	var pos := _pick_spawn_pos(anchor)
	if not pos.is_finite():
		return  # nowhere sane to spawn; cooldown retries shortly
	var cruiser := RaycastVehicle.new()
	cruiser.profile_path = CRUISER_PROFILE  # must be set BEFORE add_child
	cruiser.set_external_input(0.0, 0.0, 0.0, false)  # never reads the keyboard
	_spawned_total += 1
	cruiser.name = "PoliceCruiser%d" % _spawned_total
	cruiser.add_to_group("police")
	cruiser.add_to_group("towable")
	cruiser.contact_monitor = true
	cruiser.max_contacts_reported = 4
	main_ref.add_child(cruiser)
	var look := pv.global_position - pos
	look.y = 0.0
	look = look.normalized() if look.length() > 0.5 else Vector3.FORWARD
	cruiser.global_transform = Transform3D(Basis.looking_at(look, Vector3.UP), pos)
	cruiser.body_entered.connect(_on_cruiser_body_entered.bind(cruiser))
	if heat >= ESCALATE_HEAT:
		cruiser.power_modifier = 1.0 + ESCALATE_POWER * float(heat - 3)
	var mats := _add_lightbar(cruiser)
	cruisers.append({
		"body": cruiser, "age": 0.0, "stuck_t": 0.0, "rev_t": 0.0,
		"flip_t": 0.0, "closing": 0.0, "mat_red": mats[0], "mat_blue": mats[1],
	})


## Street points (downtown centrelines + frontage roads) in the 100-160 m ring
## around the player, corridor excluded. Fallback: the wide spawn street x=193.
func _pick_spawn_pos(ppos: Vector3) -> Vector3:
	var candidates: Array[Vector3] = []
	# Occupancy: junkers park on the same frontage lattice and cruisers can
	# re-pick the same point — never materialize inside another body.
	var occupied: Array[Vector3] = []
	for n in get_tree().get_nodes_in_group("towable"):
		if n is Node3D and is_instance_valid(n):
			occupied.append((n as Node3D).global_position)
	var pitch := BLOCK + STREET
	for i in GRID_COLS - 1:  # N-S streets between block columns
		var x := GRID_WEST + BLOCK + STREET * 0.5 + i * pitch
		var z := GRID_NORTH
		while z <= GRID_NORTH + GRID_ROWS * pitch - STREET:
			_consider(candidates, Vector3(x, SPAWN_Y, z), ppos, occupied)
			z += 20.0
	for j in GRID_ROWS - 1:  # E-W streets between block rows
		var z2 := GRID_NORTH + BLOCK + STREET * 0.5 + j * pitch
		var x2 := GRID_WEST + 6.0
		while x2 <= GRID_WEST + GRID_COLS * pitch - STREET:
			_consider(candidates, Vector3(x2, SPAWN_Y, z2), ppos, occupied)
			x2 += 20.0
	for side: float in [-1.0, 1.0]:  # at-grade frontage roads along the freeway
		var fx := -760.0
		while fx <= 760.0:
			_consider(candidates, Vector3(fx, SPAWN_Y, side * FRONTAGE_Z), ppos, occupied)
			fx += 24.0
	if not candidates.is_empty():
		return candidates[_rng.randi_range(0, candidates.size() - 1)]
	# No street point in the ring (player off-grid, e.g. deep in the floodway):
	# skip this attempt — the caller's cooldown retries in SPAWN_INTERVAL and
	# escape decay already handles heat when police cannot reach the player.
	return Vector3.INF


func _consider(arr: Array[Vector3], p: Vector3, ppos: Vector3, occupied: Array[Vector3]) -> void:
	if CORRIDOR.grow(CORRIDOR_MARGIN).has_point(Vector2(p.x, p.z)):
		return  # never drop anything into the protected spawn corridor
	var d := Vector2(p.x - ppos.x, p.z - ppos.z).length()
	if d < SPAWN_DIST_MIN or d > SPAWN_DIST_MAX:
		return
	for o in occupied:
		if Vector2(p.x - o.x, p.z - o.z).length() < 6.0:
			return  # would materialize inside a parked junker or cruiser
	arr.append(p)


func _add_lightbar(cruiser: Node3D) -> Array:
	var bar := Node3D.new()
	bar.name = "Lightbar"
	bar.position = Vector3(0.0, LIGHTBAR_Y, LIGHTBAR_Z)
	cruiser.add_child(bar)
	var mats: Array = []
	for i in 2:
		var col := Color(0.95, 0.05, 0.05) if i == 0 else Color(0.1, 0.25, 1.0)
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = 0.15
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, 0.14, 0.34)
		mi.mesh = bm
		mi.material_override = m
		mi.position = Vector3(-0.33 if i == 0 else 0.33, 0.0, 0.0)
		bar.add_child(mi)
		mats.append(m)
	return mats


func _despawn(c: Dictionary) -> void:
	var body: Node = c["body"]
	if is_instance_valid(body):
		body.queue_free()
	cruisers.erase(c)


func _despawn_all() -> void:
	for c in cruisers.duplicate():
		_despawn(c)


# ============================== HEAT SOURCES =================================
func _on_cruiser_body_entered(body: Node, cruiser: RaycastVehicle) -> void:
	if _ram_cd > 0.0 or not is_instance_valid(body) or not is_instance_valid(cruiser):
		return
	var pv := _player()
	if pv == null or body != pv:
		return
	if not (pv is RigidBody3D):
		return  # cruiser vs the on-foot CHARACTER: the run-over damage is its
				# own consequence — heat only for the player's truck ramming cops
	# Pre-contact closing speed cached by _drive — post-solve velocities here
	# have already had the impact consumed and read near zero on real rams.
	var closing := 0.0
	for c in cruisers:
		if c["body"] == cruiser:
			closing = float(c.get("closing", 0.0))
			break
	if closing >= RAM_HEAT_SPEED:
		_ram_cd = RAM_COOLDOWN
		add_heat(1, "RAMMED A CRUISER")


## The actor being pursued: character on foot, vehicle otherwise.
func _player() -> Node3D:
	if main_ref == null:
		return null
	if main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	var v: Variant = main_ref.get("vehicle")
	if v is Node3D and is_instance_valid(v) and (v as Node).is_inside_tree():
		return v
	return null


## Duck-typed actor velocity: rigid bodies and characters store it differently.
func _actor_velocity(a: Node3D) -> Vector3:
	if a is RigidBody3D:
		return (a as RigidBody3D).linear_velocity
	if a is CharacterBody3D:
		return (a as CharacterBody3D).velocity
	return Vector3.ZERO


# ============================== UI ===========================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 12
	add_child(_ui)
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 14)
	row.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE  # HUD law: STOP eats mouse look
	_ui.add_child(row)
	for i in MAX_HEAT:
		var star := Label.new()
		star.text = "*"
		star.add_theme_font_size_override("font_size", 42)
		star.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
		star.add_theme_constant_override("outline_size", 6)
		row.add_child(star)
		_stars.append(star)
	_banner = Label.new()
	_banner.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.add_theme_font_size_override("font_size", 46)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.visible = false
	_ui.add_child(_banner)
	_banner_sub = Label.new()
	_banner_sub.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 126)
	_banner_sub.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner_sub.add_theme_font_size_override("font_size", 22)
	_banner_sub.add_theme_color_override("font_color", Color(0.95, 0.90, 0.80))
	_banner_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner_sub.add_theme_constant_override("outline_size", 6)
	_banner_sub.visible = false
	_ui.add_child(_banner_sub)
	_update_stars()


func _update_stars() -> void:
	# M23: hud_gta draws the five-star row top-right; this three-star row yields
	# to it whenever that system is loaded. WANTED/EVADED banners stay here.
	var hud_owns := _hud_present()
	for i in _stars.size():
		_stars[i].visible = not hud_owns
		_stars[i].add_theme_color_override("font_color", STAR_FULL if i < heat else STAR_DIM)


func _hud_present() -> bool:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	return sys is Dictionary and (sys as Dictionary).has("hud_gta")


## True if any cruiser or foot officer has a clear line to the player's chest.
## <= (cruisers + officers) rays per LOS_INTERVAL; the world mask only.
func _anyone_sees(pv: Node3D) -> bool:
	var space := pv.get_world_3d().direct_space_state
	var to := pv.global_position + Vector3.UP * LOS_TARGET
	var ex: Array[RID] = []
	if pv is CollisionObject3D:
		ex.append((pv as CollisionObject3D).get_rid())
	var eyes: Array[Node3D] = []
	for c in cruisers:
		var b: Node3D = c["body"]
		if is_instance_valid(b) and b.is_inside_tree():
			eyes.append(b)
	for n in get_tree().get_nodes_in_group("officer"):
		if n is Node3D and is_instance_valid(n) and (n as Node3D).is_inside_tree():
			eyes.append(n as Node3D)
	for e in eyes:
		if e.global_position.distance_to(pv.global_position) > LOS_RANGE:
			continue
		var from := e.global_position + Vector3.UP * LOS_EYE
		var q := PhysicsRayQueryParameters3D.create(from, to)
		q.exclude = ex
		if e is CollisionObject3D:
			var ex2 := ex.duplicate()
			ex2.append((e as CollisionObject3D).get_rid())
			q.exclude = ex2
		q.collide_with_areas = false
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return true
		var col: Variant = hit.get("collider")
		if col == pv or (col is Node and (col as Node).is_in_group("player")):
			return true
	return false


func _show_banner(text: String, col: Color, sub: String = "") -> void:
	if _banner == null:
		return
	_banner.text = text
	_banner.add_theme_color_override("font_color", col)
	_banner.modulate.a = 1.0
	_banner.visible = true
	_banner_t = FLASH_SECONDS if sub == "" else FLASH_SECONDS * 1.6  # a reason needs reading time
	if _banner_sub != null:
		_banner_sub.text = sub
		_banner_sub.modulate.a = 1.0
		_banner_sub.visible = sub != ""
