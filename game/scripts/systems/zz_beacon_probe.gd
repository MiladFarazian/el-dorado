extends Node
## OBJECTIVE-BEACON VERIFICATION HARNESS (D-015 / D-032). Windowed, like
## `zz_shot.gd`; completely inert unless one of its flags is passed, so it costs
## a boot nothing.
##
##   godot -- --shot  --freeze              the review set, world frozen
##   godot -- --shot  --freeze --nobeacon   the same frames, beacons hidden
##   godot -- --bshot --freeze              the FINDABILITY set (below)
##   godot -- --bshot --freeze --nobeacon   its plate
##
## WHY IT EXISTS. D-015 was re-photographed for four cycles and mis-attributed
## three times — to a street tree, to a character rig, and to a project-wide
## instance-colour bug that did not exist — because everybody was looking at a
## frame and arguing about what a colour meant. This removes the argument:
## `--nobeacon` hides every node in the "objective_beacon" group, so the SAME
## frame can be rendered with and without the marker and subtracted. Whatever
## differs is a beacon. Nothing else can be.
##
## `--freeze` stops the world at frame 39 (after it has settled) and pins
## repo_board's pulse phase, so the two renders differ by the beacon and by
## nothing else: measured non-beacon drift across the 59-vantage set is 8 px.
## Without it, ambient traffic alone puts a 99.5th-percentile noise floor of
## 235-342 (sum |dRGB|) into the frame and buries the thing being measured.
##
## KNOWN AND HARMLESS: `--freeze` makes the physics delta zero, so the vehicle
## and chase camera produce non-finite intermediates and log NaN warnings. That
## is an artefact of the harness, not of the game — it does not occur in play or
## in either CI gate.

const OUT_DIR := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/bshots"

var main_ref: Node = null
var _hide := false
var _run := false
var _freeze := false
var _ff := 0
var _cam: Camera3D = null
var _f := 0
var _idx := 0
var _busy := false

# [name, camera pos, look-at, hour] — the findability set.
# Repo target sits at (338.6, 0, 528.0).
var _shots: Array = [
	# From the impound pad, day and night — the "where do I go next" moment.
	["find_impound_day", Vector3(709.0, 2.2, 558.0), Vector3(338.6, 8.0, 528.0), 13.0],
	["find_impound_night", Vector3(709.0, 2.2, 558.0), Vector3(338.6, 8.0, 528.0), 21.8],
	# Across downtown, driver's eye height, ~160 m and ~300 m out.
	["find_downtown_day", Vector3(193.0, 1.6, 470.0), Vector3(338.6, 8.0, 528.0), 13.0],
	["find_downtown_night", Vector3(193.0, 1.6, 470.0), Vector3(338.6, 8.0, 528.0), 21.8],
	["find_far_day", Vector3(451.0, 4.9, 305.0), Vector3(338.6, 10.0, 528.0), 13.0],
	["find_far_night", Vector3(451.0, 4.9, 305.0), Vector3(338.6, 10.0, 528.0), 21.8],
	# On foot, 1.6 m eye, mid range and standing right on top of it.
	["find_foot_mid", Vector3(338.6, 1.6, 448.0), Vector3(338.6, 6.0, 528.0), 13.0],
	["find_foot_close", Vector3(332.0, 1.6, 519.0), Vector3(338.6, 1.4, 528.0), 13.0],
	["find_foot_close_night", Vector3(332.0, 1.6, 519.0), Vector3(338.6, 1.4, 528.0), 21.8],
	# Driving: chase-cam eye, 60 m and 25 m out on the approach.
	["find_drive_60", Vector3(338.6, 3.2, 468.0), Vector3(338.6, 5.0, 528.0), 13.0],
	["find_drive_25", Vector3(338.6, 3.2, 503.0), Vector3(338.6, 3.0, 528.0), 13.0],
	["find_drive_night", Vector3(338.6, 3.2, 468.0), Vector3(338.6, 5.0, 528.0), 21.8],
	# Elevated: the freeway deck read, and straight down (the aerial case).
	["find_freeway", Vector3(338.6, 12.5, 120.0), Vector3(338.6, 8.0, 528.0), 13.0],
	["find_overhead", Vector3(338.6, 90.0, 560.0), Vector3(338.6, 0.0, 528.0), 13.0],
]


func setup(main: Node) -> void:
	main_ref = main
	var args := OS.get_cmdline_user_args()
	_hide = args.has("--nobeacon")
	_run = args.has("--bshot")
	_freeze = args.has("--freeze")
	if not _hide and not _run and not _freeze:
		set_process(false)
		return
	if _run:
		DirAccess.make_dir_recursive_absolute(OUT_DIR)


func _process(_d: float) -> void:
	# Freeze the world AFTER it has settled, so a with-beacon frame and a
	# without-beacon frame differ ONLY by the beacon. Runs before zz_shot in
	# systems order (alphabetical), so shot 0 is already frozen.
	if _freeze:
		_ff += 1
		if _ff == 39:
			Engine.time_scale = 0.0
			# repo_board pulses the TARGET junker's own emission at
			# 1.2 + 0.8*sin(_t*5) — a +/-40 % swing. Freezing at whatever phase
			# wall-clock happened to reach makes the target car a different
			# brightness in every run, which shows up in a differential render
			# as a car-sized patch that got DARKER (impossible for the beacon).
			# Pin the phase so the only difference between two runs is the beacon.
			var rb: Variant = (main_ref.get("systems") as Dictionary).get("repo_board")
			if rb is Node and is_instance_valid(rb):
				(rb as Node).set("_t", 8.0)
			# A zero physics delta makes the chase camera's critically-damped
			# spring divide by zero; it then logs a NaN warning EVERY frame from
			# two call sites. Left running it wrote a 12.6-million-line log and
			# turned a six-minute capture into a forty-minute one. The shot
			# harness has made its own camera current by now, so neither of
			# these has anything left to do.
			for n: Variant in [main_ref.get("camera"), main_ref.get("vehicle")]:
				if n is Node and is_instance_valid(n):
					(n as Node).set_process(false)
					(n as Node).set_physics_process(false)
		# One-line census of every beacon in the tree, so a boot log can be read
		# for "is the marker where I think it is, and how bright" without a
		# screenshot. Per D-032: every layer should print one.
		if _ff == 45:
			for n in get_tree().get_nodes_in_group("objective_beacon"):
				var n3 := n as Node3D
				var col := n3.get_child(0) as MeshInstance3D
				var mm := col.material_override as StandardMaterial3D
				print("BEACON: pos=%v root=%s column=%s energy=%.3f" % [
					n3.global_position, n3.visible, col.visible,
					mm.emission_energy_multiplier])
	if _hide:
		for n in get_tree().get_nodes_in_group("objective_beacon"):
			if n is Node3D:
				(n as Node3D).visible = false
	if not _run:
		return
	_f += 1
	if _f < 40 or _busy:
		return
	if _cam == null:
		for n in (main_ref as Node).get_children():
			if n is CanvasLayer:
				(n as CanvasLayer).visible = false
		for sys: Node in (main_ref.get("systems") as Dictionary).values():
			for c in sys.get_children():
				if c is CanvasLayer:
					(c as CanvasLayer).visible = false
		_cam = Camera3D.new()
		_cam.fov = 40.0
		_cam.far = 4000.0
		add_child(_cam)
		_cam.make_current()
	if _idx >= _shots.size():
		get_tree().quit(0)
		return
	_busy = true
	_take(_shots[_idx])


func _take(shot: Array) -> void:
	var sky: Variant = (main_ref.get("systems") as Dictionary).get("sky_weather")
	if sky is Node and is_instance_valid(sky):
		(sky as Node).set("time_of_day", shot[3])
	_cam.global_position = shot[1]
	_cam.look_at(shot[2], Vector3.UP)
	_settle_and_save(str(shot[0]))


func _settle_and_save(shot_name: String) -> void:
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_DIR + "/" + shot_name + ".png")
	print("BSHOT saved: " + shot_name)
	_idx += 1
	_busy = false
