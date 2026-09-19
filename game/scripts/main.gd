extends Node3D
## EL DORADO GRANDE — Milestone 1 bootstrap.
## Builds environment, city, vehicle, camera, and HUD entirely in code so the
## whole project stays agent-legible text. Subsystem scripts are loaded
## defensively: missing pieces fall back to simple stand-ins so the slice
## always boots, even mid-integration.

const CITY_SCRIPT_PATH := "res://scripts/world/greybox_city.gd"
const CAMERA_SCRIPT_PATH := "res://scripts/camera/chase_camera.gd"
const HUD_SCRIPT_PATH := "res://scripts/ui/debug_hud.gd"
const VEHICLE_SCRIPT := preload("res://scripts/vehicle/raycast_vehicle.gd")
const VEHICLE_DATA_DIR := "res://data/vehicles"
const SYSTEMS_DIR := "res://scripts/systems"

var vehicle: RigidBody3D
# YOUR truck — the Longhorn Wrecker the game hands you. `vehicle` is whatever
# you are currently sitting in (carjack.gd swaps it); this one stays the ride
# you own, so County General knows where to drop you and Tab only ever
# re-profiles the rig that is actually yours.
var own_vehicle: RigidBody3D
var camera: Camera3D
var city: Node3D
var hud: CanvasLayer
# World handles for systems (sky_weather drives these): may be null pre-build.
var world_env: WorldEnvironment
var sun: DirectionalLight3D
var fallback_cam := false
var spawn_transform := Transform3D(Basis.IDENTITY, Vector3(0, 2, 0))
var profile_paths: Array[String] = []
var profile_index := 0
# D-068: the rigs Book OWNS. TAB cycles these in play; the wrecker is always
# his. Boone Trucks grants (a note or cash) and LONGHORN revokes (a missed
# note). Tools and probes (`dev_fleet`) still cycle every profile on disk.
var owned_paths: Array[String] = []
var dev_fleet := false

# Gameplay systems auto-loaded from scripts/systems/*.gd, keyed by basename
# (e.g. systems["tow_hook"]). Each gets setup(self) and may implement
# on_vehicle_changed(vehicle). Systems must tolerate absent peers.
var systems: Dictionary = {}

# On-foot mode (owned by the on_foot system): character is the walking avatar,
# null while driving. Systems that target "the player" should prefer
# player_actor() over reading vehicle directly.
var character: Node3D = null
var on_foot := false


func player_actor() -> Node3D:
	if on_foot and character != null and is_instance_valid(character):
		return character
	return vehicle


## SWAP THE KEYS. The single funnel for "the player is now driving THIS" —
## carjack hands the boarded vehicle here through on_foot. Points the camera and
## the HUD at it, hands it back to the keyboard (a stolen cruiser was on
## external input), and fires on_vehicle_changed so systems holding refs to the
## old body (tow chain, engine audio) drop them before it becomes somebody
## else's parked car.
func set_player_vehicle(v: RigidBody3D) -> void:
	if v == null or not is_instance_valid(v) or not v.is_inside_tree() or v == vehicle:
		return
	if vehicle != null and is_instance_valid(vehicle):
		vehicle.set("player_controlled", false)
		vehicle.remove_from_group("player")
	vehicle = v
	if v.has_method("clear_external_input"):
		v.call("clear_external_input")
	v.set("player_controlled", true)
	if not v.is_in_group("player"):
		v.add_to_group("player")
	if camera and "target" in camera:
		camera.set("target", v)
	if hud and "vehicle" in hud:
		hud.set("vehicle", v)
	for s: Node in systems.values():
		if s.has_method("on_vehicle_changed"):
			s.call("on_vehicle_changed", v)

# Smoke-test state (run with: godot --headless -- --smoke). Drives the vehicle
# programmatically and exits nonzero on failure so CI can gate on it.
var smoke_mode := false
var smoke_frames := 0
var smoke_start := Vector3.ZERO


func _ready() -> void:
	smoke_mode = OS.get_cmdline_user_args().has("--smoke")
	_register_input_actions()
	_build_environment()
	_build_city()
	_scan_vehicle_profiles()
	_spawn_vehicle(profile_paths[0] if not profile_paths.is_empty() else "")
	_build_camera()
	_build_hud()
	_load_systems()
	if not smoke_mode:
		# Mouse look is live in both modes (chase boom + drive-by aim); ESC in
		# on_foot.gd is the release valve. NEVER in smoke — headless must not
		# touch the display server.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_delta: float) -> void:
	if vehicle:
		if not on_foot and Input.is_action_just_pressed("reset_vehicle"):
			_reset_vehicle()
		# Tab re-profiles YOUR rig only. In a carjacked car it would free the
		# stolen body and orphan the wrecker parked across town.
		if not on_foot and vehicle == own_vehicle \
				and Input.is_action_just_pressed("switch_vehicle"):
			_cycle_vehicle()
		if hud == null and Input.is_action_just_pressed("reload_tuning") \
				and vehicle.has_method("reload_profile"):
			vehicle.call("reload_profile")
	if smoke_mode:
		_smoke_tick()


func _process(delta: float) -> void:
	if fallback_cam and vehicle and camera:
		var target_pos: Vector3 = vehicle.global_position
		var back: Vector3 = vehicle.global_transform.basis.z
		back.y = 0.0
		back = back.normalized() if back.length() > 0.01 else Vector3.BACK
		var desired := target_pos + back * 9.0 + Vector3.UP * 4.0
		camera.global_position = camera.global_position.lerp(desired, 1.0 - exp(-6.0 * delta))
		camera.look_at(target_pos + Vector3.UP * 1.2, Vector3.UP)


func _register_input_actions() -> void:
	var bindings := {
		"accelerate": [KEY_W, KEY_UP],
		"brake_reverse": [KEY_S, KEY_DOWN],
		"steer_left": [KEY_A, KEY_LEFT],
		"steer_right": [KEY_D, KEY_RIGHT],
		"handbrake": [KEY_SPACE],
		"hook": [KEY_F],
		"enter_exit": [KEY_E],
		"interact": [KEY_G],
		"radio_next": [KEY_N],
		"weapon_next": [KEY_Q],
		"crouch": [KEY_CTRL],
		"sprint": [KEY_SHIFT],
		"jump": [KEY_SPACE],
		"reload": [KEY_R],
		"reset_vehicle": [KEY_BACKSPACE],  # D-037: R is reload; one key, one verb
		"switch_vehicle": [KEY_TAB],
		"toggle_camera": [KEY_C],
		"reload_tuning": [KEY_T],
		"special": [KEY_CAPSLOCK, KEY_X],  # THE FULL EIGHT (GTA's Caps Lock; X for laptops)
		"horn": [KEY_H],
	}
	for action: String in bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for key: Key in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
	var mouse_bindings := {"fire": MOUSE_BUTTON_LEFT, "aim": MOUSE_BUTTON_RIGHT}
	for action: String in mouse_bindings:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var mev := InputEventMouseButton.new()
		mev.button_index = mouse_bindings[action]
		InputMap.action_add_event(action, mev)


func _build_environment() -> void:
	# EVERY global light decision lives in scripts/world/render_pipeline.gd —
	# SDFGI, SSR, volumetric fog, the 4-cascade PCSS shadow rig, the generated
	# filmic LUT, and the anti-aliasing choice. It is one file so that one file
	# can be read, and so every feature has a switch:
	#   --env-legacy      rebuild EXACTLY the pre-M23 environment (arm A)
	#   --env-no-sdfgi / --env-no-ssr / --env-no-volfog / --env-no-taa
	#   --env-no-farshadow / --env-no-grade / --env-no-scatter
	#   --env-autoexposure / --env-ssil       opt-in probes
	# sky_weather.gd still owns everything that CHANGES with time of day and
	# weather; this builds the rig it drives.
	var built: Dictionary = preload("res://scripts/world/render_pipeline.gd").build(self)
	world_env = built["world_env"]
	sun = built["sun"]


func _build_city() -> void:
	if ResourceLoader.exists(CITY_SCRIPT_PATH):
		var city_script: GDScript = load(CITY_SCRIPT_PATH)
		city = city_script.new()
		city.name = "GreyboxCity"
		add_child(city)
		if city.has_method("get_spawn_point"):
			spawn_transform = city.call("get_spawn_point")
	else:
		var ground := StaticBody3D.new()
		ground.name = "FallbackGround"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2000, 2, 2000)
		shape.shape = box
		ground.add_child(shape)
		var mesh := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(2000, 2, 2000)
		mesh.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.35, 0.34, 0.32)
		mesh.material_override = mat
		ground.add_child(mesh)
		ground.position = Vector3(0, -1, 0)
		add_child(ground)


func _scan_vehicle_profiles() -> void:
	profile_paths.clear()
	var dir := DirAccess.open(VEHICLE_DATA_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			profile_paths.append(VEHICLE_DATA_DIR + "/" + fname)
		fname = dir.get_next()
	profile_paths.sort()
	for i in profile_paths.size():
		if profile_paths[i].contains("wrecker"):
			var w := profile_paths[i]
			profile_paths.remove_at(i)
			profile_paths.insert(0, w)
			break
	owned_paths.clear()
	if not profile_paths.is_empty():
		owned_paths.append(profile_paths[0])   # the wrecker: the Hook is equipment he owns
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--shot") or a.begins_with("--perf") or a.begins_with("--mech-probe") \
				or a.begins_with("--hudshot") or a.begins_with("--wanted-probe") or a == "--dev-fleet":
			dev_fleet = true


## D-068: Boone Trucks calls this on a sale. True if the rig is now owned.
func grant_vehicle(path: String) -> bool:
	if path == "" or not profile_paths.has(path):
		return false
	if not owned_paths.has(path):
		owned_paths.append(path)
	return true


## D-068: LONGHORN calls this on a missed note. The wrecker can never go.
func revoke_vehicle(path: String) -> bool:
	if owned_paths.size() < 2 or path.contains("wrecker"):
		return false
	var i := owned_paths.find(path)
	if i < 0:
		return false
	owned_paths.remove_at(i)
	return true


func _spawn_vehicle(path: String) -> void:
	if vehicle:
		vehicle.queue_free()
		vehicle = null
	vehicle = VEHICLE_SCRIPT.new()
	if path != "":
		vehicle.set("profile_path", path)
	vehicle.name = "Vehicle"
	vehicle.add_to_group("player")
	add_child(vehicle)
	own_vehicle = vehicle  # the rig you own; carjacked cars never take this slot
	vehicle.global_transform = spawn_transform
	smoke_start = vehicle.global_position
	if camera and "target" in camera:
		camera.set("target", vehicle)
	if hud and "vehicle" in hud:
		hud.set("vehicle", vehicle)
	for s: Node in systems.values():
		if s.has_method("on_vehicle_changed"):
			s.call("on_vehicle_changed", vehicle)


func _reset_vehicle() -> void:
	var t := vehicle.global_transform
	var fwd := -t.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.1:
		fwd = Vector3.FORWARD
	var basis := Basis.looking_at(fwd.normalized(), Vector3.UP)
	var target := Transform3D(basis, t.origin + Vector3(0, 1.5, 0))
	if vehicle.has_method("reset_to"):
		vehicle.call("reset_to", target)


func _cycle_vehicle() -> void:
	var fleet: Array[String] = profile_paths if dev_fleet else owned_paths
	if fleet.size() < 2:
		return
	var cur: String = str(vehicle.get("profile_path")) if vehicle != null else ""
	var at := fleet.find(cur)
	profile_index = (at + 1) % fleet.size()
	var t := vehicle.global_transform
	t.origin += Vector3(0, 0.5, 0)
	var lv: Vector3 = vehicle.linear_velocity
	var av: Vector3 = vehicle.angular_velocity
	_spawn_vehicle(fleet[profile_index])
	vehicle.global_transform = t
	vehicle.linear_velocity = lv
	vehicle.angular_velocity = av


func _build_camera() -> void:
	if ResourceLoader.exists(CAMERA_SCRIPT_PATH):
		var cam_script: GDScript = load(CAMERA_SCRIPT_PATH)
		camera = cam_script.new()
		add_child(camera)
		if "target" in camera:
			camera.set("target", vehicle)
	else:
		camera = Camera3D.new()
		camera.position = spawn_transform.origin + Vector3(0, 4, 9)
		add_child(camera)
		fallback_cam = true
	camera.make_current()


func _build_hud() -> void:
	if smoke_mode:
		return
	if ResourceLoader.exists(HUD_SCRIPT_PATH):
		var hud_script: GDScript = load(HUD_SCRIPT_PATH)
		hud = hud_script.new()
		add_child(hud)
		if "vehicle" in hud:
			hud.set("vehicle", vehicle)


func _load_systems() -> void:
	var dir := DirAccess.open(SYSTEMS_DIR)
	if dir == null:
		return
	dir.list_dir_begin()
	var paths: Array[String] = []
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".gd"):
			paths.append(SYSTEMS_DIR + "/" + fname)
		fname = dir.get_next()
	paths.sort()
	for path in paths:
		var script: GDScript = load(path)
		var node: Node = script.new()
		node.name = path.get_file().get_basename()
		add_child(node)
		systems[node.name] = node
		if node.has_method("setup"):
			node.call("setup", self)


func _smoke_tick() -> void:
	smoke_frames += 1
	if smoke_frames == 30 and vehicle and vehicle.has_method("set_external_input"):
		vehicle.call("set_external_input", 1.0, 0.0, 0.0, false)
	if smoke_frames != 300:
		return
	var ok := true
	var report: Array[String] = []
	if vehicle == null:
		ok = false
		report.append("vehicle missing")
	else:
		var moved := smoke_start.distance_to(vehicle.global_position)
		var speed := vehicle.linear_velocity.length()
		report.append("pos=%v moved=%.1fm speed=%.1fm/s" % [vehicle.global_position, moved, speed])
		if vehicle.global_position.y < -10.0:
			ok = false
			report.append("FELL THROUGH WORLD")
		if moved < 5.0:
			ok = false
			report.append("did not move (drivetrain dead?)")
		if speed < 1.0:
			ok = false
			report.append("no speed at frame 300")
	print("SMOKE %s | %s" % ["PASS" if ok else "FAIL", "; ".join(report)])
	get_tree().quit(0 if ok else 1)
