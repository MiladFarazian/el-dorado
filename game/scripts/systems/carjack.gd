extends Node
## CARJACK — grand theft auto, the verb the genre is named after.
##
## On foot, E takes the nearest ride: your own truck (free), a car you already
## stole and parked (free), a civilian's ride (+2 stars, and the driver leaves
## by the far door), or a marked cruiser with the bar still going (+3 stars —
## that is the whole department's afternoon).
##
## THE CONVERSION. Traffic cars are frozen-kinematic PROPS moved by transform,
## not physics vehicles — there is nothing in them to drive. So a jacked shell
## is converted in one frame: traffic drops it from its roster and reports the
## lane speed it was doing, the shell is stripped of collision and freed, and a
## real RaycastVehicle inherits its position, yaw and motion. Cruisers are
## already RaycastVehicles, so those merely change hands.
##
## on_foot.gd owns the vehicle/character mode switch and drives this system
## through find_target() + claim(). Everything else is ours: the crime, the
## conversion, the ejected driver, abandoned-car housekeeping, and the prompt.
## ENTIRELY INERT in smoke mode. Peers bound lazily; every ref is null-checked.

# ============================== TUNABLES =====================================
const RNG_SEED := 0x3A17
const JACK_RANGE := 4.6              # character origin -> vehicle origin (m)
const JUNKER_HINT_RANGE := 5.5       # "no keys" prompt reach for dead junkers
const CIVILIAN_HEAT := 2             # grand theft auto
const POLICE_HEAT := 3               # ...of a marked unit. Everyone notices.
const SPAWN_LIFT := 0.45             # shell ride height -> new body origin (m)
const MIN_SPAWN_Y := 1.1             # never convert below this (m)
const DRIVER_META := "carjack_has_driver"   # false once somebody has been tossed
const FALLBACK_PROFILE := "res://data/vehicles/sedan.json"
# Ejected driver: a pedestrians.gd mannequin, thrown out the door away from you.
const DRIVER_MASS := 80.0
const DRIVER_OUT := 2.4              # sideways exit speed (m/s)
const DRIVER_POP := 3.0              # up-fling so the exit reads as a toss
const DRIVER_CARRY := 0.55           # share of the car's velocity they keep
const DRIVER_SPIN := 3.5             # rad/s of undignified tumble
const DRIVER_DOOR := 1.35            # lateral offset from the car origin (m)
const DRIVER_LIFE := 55.0            # s before an ejected driver is swept up
const DRIVER_DIST := 200.0           # ...or this far from the player (m)
# Housekeeping: a jacked car is a REAL vehicle (4 suspension rays a frame), so
# the city cannot keep every one the player has ever touched.
const MAX_JACKED := 5
const ABANDON_GRACE := 15.0          # s parked before it is a candidate
const ABANDON_DIST := 260.0          # ...and this far away (m)
const LIGHTBAR_HZ := 3.0             # stolen cruisers keep strobing (police.gd's rate)
const PROMPT_MARGIN := 96            # centre-bottom slot above the tow hint (56)
const PROMPT_FONT_SIZE := 21
const PROMPT_COLOR := Color(0.95, 0.92, 0.8)
const CRIME_COLOR := Color(1.0, 0.62, 0.25)   # prompt tint when it IS a crime
# Ejected drivers are factory people (M9) with the pedestrian collider.
const COLLIDER_SIZE := Vector3(0.5, 1.75, 0.35)
const FACTORY := preload("res://scripts/world/character_factory.gd")
## SKINNED-BODY PROOF OF CONCEPT — inert unless `--skinned` is on the command
## line. `character_factory` remains the shipping path and is not modified; only
## `build()` is redirected, because `animate()` / `aim_pose()` / the rig dict are
## contract-identical between the two and the skinned body delegates to the
## factory's animator anyway.
const SKINNED := preload("res://scripts/world/skinned_character.gd")
static func _body_script() -> GDScript:
	return FACTORY if OS.get_cmdline_user_args().has("--factory") else SKINNED   # D-050: skinned is the default; --factory is the M22 body

# ============================== STATE ========================================
var main_ref: Node = null
var _rng := RandomNumberGenerator.new()
# Cars this system created or handed over: {body, idle, mat_red, mat_blue}.
# Never contains main.own_vehicle, so your truck is never swept up.
var _jacked: Array[Dictionary] = []
var _drivers: Array[Dictionary] = []   # {body, age}
var _ejected := 0                      # lifetime count, for unique node names
var _names: Dictionary = {}            # profile path -> display name (parsed once)
var _strobe_t := 0.0
var _ui: CanvasLayer = null
var _prompt: Label = null
var _prompt_crime := false   # matches the colour the label was built with


func setup(main: Node) -> void:
	main_ref = main
	_rng.seed = RNG_SEED
	if bool(main.get("smoke_mode")):
		set_physics_process(false)
		set_process(false)
		return  # smoke gate: no UI, no spawns, no conversions
	_build_ui()


## The player vehicle changed under us (Tab re-profiled the truck, or on_foot
## boarded something). Nothing here caches it — kept explicit for the contract.
func on_vehicle_changed(_vehicle: Node) -> void:
	pass


# ============================== PUBLIC API ===================================
## The vehicle E would take right now, or null. Nearest origin within
## JACK_RANGE across every profile-driven vehicle ("drivable" — your truck,
## cruisers, cars you already stole) and every traffic shell ("civilian").
## Junkers are deliberately absent: they are dead weight with no keys, which is
## the whole reason the job is to HOOK them.
func find_target(ch: Node3D) -> Node3D:
	if ch == null or not is_instance_valid(ch):
		return null
	var origin := ch.global_position
	var best: Node3D = null
	var best_d := JACK_RANGE
	for group: String in ["drivable", "civilian"]:
		for n: Node in get_tree().get_nodes_in_group(group):
			if not (n is RigidBody3D) or not is_instance_valid(n) or not n.is_inside_tree():
				continue
			var d := origin.distance_to((n as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = n as Node3D
	return best


## Take it. Returns the RigidBody3D the player should board (converting a
## traffic shell into a real vehicle if needed), or null if the handover failed
## — on_foot falls back to its own truck rather than soft-locking on foot.
func claim(target: Node3D) -> RigidBody3D:
	if target == null or not is_instance_valid(target) or not target.is_inside_tree():
		return null
	var occupied := _is_occupied(target)
	var drivable: RigidBody3D = null
	if target.is_in_group("drivable"):
		drivable = _claim_vehicle(target as RigidBody3D)
	else:
		drivable = _convert_shell(target as RigidBody3D)
	if drivable == null:
		return null
	drivable.set_meta(DRIVER_META, false)  # empty from here on: no repeat crime
	if occupied:
		var police := target.is_in_group("police")
		_add_heat(POLICE_HEAT if police else CIVILIAN_HEAT, "STOLE A CRUISER" if police else "GRAND THEFT AUTO")
		_flash("YOU TOOK THE MAN'S CAR" if police else "GRAND THEFT AUTO")
	return drivable


# ============================== TAKING =======================================
## Already a RaycastVehicle: it only changes hands. A marked cruiser has to be
## signed out of the police roster first (and loses its siren — a wail that
## never ends stops being funny about nine seconds in; the lightbar stays).
func _claim_vehicle(v: RigidBody3D) -> RigidBody3D:
	if v == _own_vehicle() or v == _player_vehicle():
		return v  # your own rig: no crime, no ceremony
	var mats: Array = []
	if v.is_in_group("police"):
		var pol := _peer("police")
		if pol != null and pol.has_method("release_cruiser"):
			var got: Variant = pol.call("release_cruiser", v)
			if got is Array:
				mats = got
		_silence(v)
		_eject_driver(v, true)
	elif _is_occupied(v):
		_eject_driver(v, false)
	_track(v, mats)
	return v


## A frozen-kinematic prop cannot be driven, so it is replaced: same spot, same
## heading, same speed, but with suspension, tires and an engine under it.
func _convert_shell(shell: RigidBody3D) -> RigidBody3D:
	var profile := str(shell.get_meta("jack_profile", FALLBACK_PROFILE))
	if not ResourceLoader.exists(profile):
		profile = FALLBACK_PROFILE
	# Traffic owns the lane speed; a frozen shell's linear_velocity is stale.
	var lane_speed := 0.0
	var traffic := _peer("traffic")
	if traffic != null and traffic.has_method("release_car"):
		lane_speed = float(traffic.call("release_car", shell))
	var t := shell.global_transform
	var fwd := -t.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var vel := shell.linear_velocity if not shell.freeze else fwd * lane_speed

	var car := RaycastVehicle.new()
	car.profile_path = profile  # must be set BEFORE add_child (_ready loads it)
	car.name = "Jacked%d" % (_jacked.size() + 1)
	car.add_to_group("towable")  # you can still hook it later like anything else
	car.contact_monitor = true
	car.max_contacts_reported = 8
	# The shell dies at end-of-frame; kill its collision NOW so the vehicle
	# materialising in the same cubic metre is not shoved by its own corpse.
	shell.collision_layer = 0
	shell.collision_mask = 0
	shell.visible = false
	shell.queue_free()

	main_ref.add_child(car)
	car.global_transform = Transform3D(Basis.looking_at(fwd, Vector3.UP),
		Vector3(t.origin.x, maxf(t.origin.y + SPAWN_LIFT, MIN_SPAWN_Y), t.origin.z))
	car.linear_velocity = vel
	_eject_driver(car, false)
	_track(car, [])
	return car


## Somebody was driving. They leave by the door AWAY from the player (you are
## standing in the other one) and land as a bloodless mannequin — the same
## greybox tumble a struck pedestrian does, because that is the register.
func _eject_driver(car: Node3D, police: bool) -> void:
	var actor := _actor()
	var side := car.global_transform.basis.x
	if actor != null:
		# Push them out the far side: you approached from one, they use the other.
		side = -side if side.dot(actor.global_position - car.global_position) > 0.0 else side
	var body := RigidBody3D.new()
	_ejected += 1
	body.name = "EjectedDriver%d" % _ejected  # unique: no @Name@2 auto-rename
	body.mass = DRIVER_MASS
	body.add_to_group("pedestrian")  # NOT "towable" — we do not tow people
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = COLLIDER_SIZE
	col.shape = shape
	body.add_child(col)
	# M9: factory people — an officer keeps the uniform on the way out.
	_body_script().build(body, FACTORY.cop_config(_rng) if police \
		else FACTORY.random_config(_rng), -COLLIDER_SIZE.y * 0.5)
	add_child(body)  # Node3D under a plain Node: transform acts as global
	body.global_position = car.global_position + side * DRIVER_DOOR + Vector3.UP * 0.2
	var carried := Vector3.ZERO
	if car is RigidBody3D:
		carried = (car as RigidBody3D).linear_velocity * DRIVER_CARRY
	body.linear_velocity = carried + side * DRIVER_OUT + Vector3.UP * DRIVER_POP
	body.angular_velocity = Vector3(_rng.randf_range(-DRIVER_SPIN, DRIVER_SPIN),
		_rng.randf_range(-2.0, 2.0), _rng.randf_range(-DRIVER_SPIN, DRIVER_SPIN))
	_drivers.append({"body": body, "age": 0.0})


func _track(body: RigidBody3D, mats: Array) -> void:
	if body == _own_vehicle():
		return  # your truck is never housekeeping's problem
	for d in _jacked:
		if d["body"] == body:
			return
	_jacked.append({
		"body": body, "idle": 0.0,
		"mat_red": mats[0] if mats.size() > 1 else null,
		"mat_blue": mats[1] if mats.size() > 1 else null})


# ============================== HOUSEKEEPING =================================
func _physics_process(delta: float) -> void:
	if main_ref == null:
		return
	_sweep_drivers(delta)
	_sweep_jacked(delta)


func _sweep_drivers(delta: float) -> void:
	var actor := _actor()
	for i in range(_drivers.size() - 1, -1, -1):
		var d := _drivers[i]
		var body: Node3D = d["body"]
		if not is_instance_valid(body) or not body.is_inside_tree():
			_drivers.remove_at(i)
			continue
		d["age"] = float(d["age"]) + delta
		var far := actor != null \
			and body.global_position.distance_to(actor.global_position) > DRIVER_DIST
		if float(d["age"]) > DRIVER_LIFE or far:
			body.queue_free()
			_drivers.remove_at(i)


## Cars you stole and walked away from are real vehicles running suspension
## every frame. Parked long enough AND far enough away, they are gone; over the
## cap, the longest-abandoned goes first. Never the one you are driving, never
## the one on the hook, never your truck.
func _sweep_jacked(delta: float) -> void:
	var pv := _player_vehicle()
	var actor := _actor()
	var hooked := _hooked_body()
	for i in range(_jacked.size() - 1, -1, -1):
		var d := _jacked[i]
		var body: Node3D = d["body"]
		if not is_instance_valid(body) or not body.is_inside_tree():
			_jacked.remove_at(i)
			continue
		d["idle"] = 0.0 if body == pv else float(d["idle"]) + delta
		if body == pv or body == hooked or float(d["idle"]) < ABANDON_GRACE:
			continue
		if actor != null and body.global_position.distance_to(actor.global_position) > ABANDON_DIST:
			body.queue_free()
			_jacked.remove_at(i)
	if _jacked.size() <= MAX_JACKED:
		return
	# Over the cap: retire the longest-abandoned, one per frame (queue_free only
	# takes effect at end of frame, so a second pick here would be picking a
	# corpse). Never the one being driven, hooked, or still inside its grace.
	var worst := -1
	var worst_idle := ABANDON_GRACE
	for i in _jacked.size():
		var body: Node3D = _jacked[i]["body"]
		if body == pv or body == hooked or float(_jacked[i]["idle"]) <= worst_idle:
			continue
		worst_idle = float(_jacked[i]["idle"])
		worst = i
	if worst >= 0:
		(_jacked[worst]["body"] as Node).queue_free()
		_jacked.remove_at(worst)


# ============================== PROMPT / STROBE ==============================
func _process(delta: float) -> void:
	_strobe(delta)
	if _prompt == null or not is_instance_valid(_prompt):
		return
	var ch := _character()
	if ch == null:
		_prompt.visible = false
		return
	var hp: Variant = ch.get("health")
	if (hp is float or hp is int) and float(hp) <= 0.0:
		_prompt.visible = false  # nothing to steal from under the funeral card
		return
	var target := find_target(ch)
	if target == null:
		_prompt.text = "NO KEYS — THAT ONE GETS HOOKED" if _junker_near(ch) else ""
		_prompt.visible = _prompt.text != ""
		_tint(false)
		return
	var crime := _is_occupied(target)
	var label := "JACK" if crime else ("GET IN" if target == _player_vehicle() else "TAKE")
	var suffix := "   (they will notice)" if target.is_in_group("police") else ""
	_prompt.text = "E — %s THE %s%s" % [label, _vehicle_label(target).to_upper(), suffix]
	_tint(crime)
	_prompt.visible = true


## Theme overrides fire a notification and force a redraw, so only touch the
## colour when it actually changes — this runs every frame the player is afoot.
func _tint(crime: bool) -> void:
	if crime == _prompt_crime:
		return
	_prompt_crime = crime
	_prompt.add_theme_color_override("font_color", CRIME_COLOR if crime else PROMPT_COLOR)


## Stolen cruisers keep their lightbar going — you are driving a marked unit
## and everyone can see it. One shared clock, same 3 Hz as police.gd.
func _strobe(delta: float) -> void:
	_strobe_t += delta
	var red_on := fmod(_strobe_t * LIGHTBAR_HZ, 1.0) < 0.5
	for d in _jacked:
		var mr: Variant = d["mat_red"]
		var mb: Variant = d["mat_blue"]
		if not (mr is StandardMaterial3D) or not (mb is StandardMaterial3D):
			continue
		(mr as StandardMaterial3D).emission_energy_multiplier = 4.0 if red_on else 0.15
		(mb as StandardMaterial3D).emission_energy_multiplier = 0.15 if red_on else 4.0


func _junker_near(ch: Node3D) -> bool:
	for n: Node in get_tree().get_nodes_in_group("junker"):
		if n is Node3D and is_instance_valid(n) \
				and ch.global_position.distance_to((n as Node3D).global_position) <= JUNKER_HINT_RANGE:
			return true
	return false


## Display name: a live vehicle knows its own; a traffic shell is named by the
## profile it will become, parsed once and cached (the JSON is the ONE source of
## truth for a vehicle's name — two names for one thing is a canon bug).
func _vehicle_label(v: Node3D) -> String:
	var dn: Variant = v.get("display_name")
	if dn is String and (dn as String) != "" and (dn as String) != "Unnamed":
		return dn
	return _profile_name(str(v.get_meta("jack_profile", FALLBACK_PROFILE)))


func _profile_name(path: String) -> String:
	if _names.has(path):
		return _names[path]
	var out := "CAR"
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		# Instance API, not JSON.parse_string: the static helper pushes engine
		# errors on corrupt input and gate 2 counts every one of those.
		var parser := JSON.new()
		if parser.parse(f.get_as_text()) == OK and parser.data is Dictionary:
			out = str((parser.data as Dictionary).get("name", out))
	_names[path] = out
	return out


# (M9: mannequin building moved to scripts/world/character_factory.gd.)
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 20
	add_child(_ui)
	_prompt = Label.new()
	_prompt.set_anchors_and_offsets_preset(
		Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, PROMPT_MARGIN)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_prompt.add_theme_font_size_override("font_size", PROMPT_FONT_SIZE)
	_prompt.add_theme_color_override("font_color", PROMPT_COLOR)
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_prompt.visible = false
	_ui.add_child(_prompt)


# ============================== PLUMBING =====================================
## Occupied = there is somebody to throw out. Traffic shells and live cruisers
## always are; a car you already emptied carries the meta and never is again.
func _is_occupied(v: Node) -> bool:
	if v.has_meta(DRIVER_META):
		return bool(v.get_meta(DRIVER_META))
	if v == _own_vehicle() or v == _player_vehicle():
		return false
	return v.is_in_group("civilian") or v.is_in_group("police")


## Stop and free every audio player riding a stolen cruiser (the siren). The
## tree_exiting -> stop hookup vehicle_audio installs means queue_free alone
## would do it; the explicit stop keeps teardown honest either way.
func _silence(v: Node) -> void:
	for c in v.get_children():
		if c is AudioStreamPlayer3D:
			(c as AudioStreamPlayer3D).stop()
			c.queue_free()
	if v.has_meta("vehicle_audio_siren"):
		v.remove_meta("vehicle_audio_siren")


func _fetch(prop: String) -> Node3D:
	var v: Variant = main_ref.get(prop) if main_ref != null else null
	return v if v is Node3D and is_instance_valid(v) \
		and (v as Node).is_inside_tree() else null


func _character() -> Node3D:
	if main_ref == null or main_ref.get("on_foot") != true:
		return null
	return _fetch("character")


func _player_vehicle() -> Node3D: return _fetch("vehicle")


func _own_vehicle() -> Node3D: return _fetch("own_vehicle")


## The actor distances are measured from: character on foot, vehicle otherwise.
func _actor() -> Node3D:
	if main_ref != null and main_ref.has_method("player_actor"):
		var a: Variant = main_ref.call("player_actor")
		if a is Node3D and is_instance_valid(a) and (a as Node).is_inside_tree():
			return a
	return _player_vehicle()


func _hooked_body() -> Node:
	var tow := _peer("tow_hook")
	if tow == null:
		return null
	var v: Variant = tow.get("hooked_body")
	return v if v is Node and is_instance_valid(v) else null


func _add_heat(n: int, reason: String = "") -> void:
	var pol := _peer("police")
	if pol != null and pol.has_method("add_heat"):
		pol.call("add_heat", n, reason)


func _flash(text: String) -> void:
	var repo := _peer("repo_board")
	if repo != null and repo.has_method("flash"):
		repo.call("flash", text)  # one flash line in the game; it belongs to repo


func _peer(peer_name: String) -> Node:
	var sys: Variant = main_ref.get("systems") if main_ref != null else null
	if sys is Dictionary:
		var n: Variant = (sys as Dictionary).get(peer_name)
		if n is Node and is_instance_valid(n):
			return n
	return null
