extends Node3D
## POSE TEST — the decisive one. Drives the SAME joints the game drives
## (rig["sh_1"].rotation.x etc, D-020 sign law: positive = forward) to three
## poses and shoots the shoulder from a 3/4 upper-body vantage. A rigid-parts
## shoulder shows two balls sliding through each other; a skinned shoulder is
## one surface that changes shape.
const FACTORY := preload("res://scripts/world/character_factory.gd")
const SKIN := preload("res://scripts/world/skinned_character.gd")
const OUT := "/private/tmp/claude-501/-Users-miladfarazian-Documents-Projects-gta-clone/318bd236-7d38-47d4-81c8-06f13bf519a8/scratchpad/shots/skin"
# name, sh_1.x, sh_1.z, el_1.x, hip_1.x, knee_1.x
const POSES: Array = [
	["rest", 0.0, 0.0, 0.10, 0.0, 0.0],
	["arm_fwd", 1.45, 0.0, 0.15, 0.0, 0.0],
	["arm_out", 0.30, -1.05, 0.90, 0.0, 0.0],
	["stride", 0.55, 0.0, 0.60, 0.62, -0.90],
]
var _cam: Camera3D
var _sun: DirectionalLight3D
var _env: WorldEnvironment
var _sub: Node3D
var _rig: Dictionary
var _jobs: Array = []
var _f := 0
var _busy := false

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(OUT)
	SKIN._no_disk = true
	_env = WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.30, 0.34, 0.40)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.55, 0.60, 0.70)
	e.ambient_light_energy = 0.45
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	_env.environment = e
	add_child(_env)
	_sun = DirectionalLight3D.new()
	_sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(34.0), 0.0)
	_sun.light_energy = 0.95
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 14.0
	_sun.shadow_normal_bias = 0.6
	_sun.shadow_bias = 0.02
	add_child(_sun)
	_cam = Camera3D.new(); _cam.fov = 40.0; add_child(_cam); _cam.make_current()
	_sub = Node3D.new(); add_child(_sub)
	for p in ["old", "new"]:
		for pose in POSES:
			_jobs.append([p, pose])

func _process(_d: float) -> void:
	_f += 1
	if _f < 6 or _busy: return
	if _jobs.is_empty():
		print("POSE DONE"); get_tree().quit(0); return
	_busy = true
	_run(_jobs.pop_front())

func _run(job: Array) -> void:
	for c in _sub.get_children():
		_sub.remove_child(c); c.queue_free()
	var h := Node3D.new(); _sub.add_child(h)
	var cfg := FACTORY.book_config()
	_rig = FACTORY.build(h, cfg, 0.0) if job[0] == "old" else SKIN.build(h, cfg, 0.0)
	var p: Array = job[1]
	(_rig["sh_1"] as Node3D).rotation = Vector3(float(p[1]), 0.0, float(p[2]))
	(_rig["el_1"] as Node3D).rotation.x = float(p[3])
	(_rig["sh_0"] as Node3D).rotation.x = -float(p[1]) * 0.5
	(_rig["el_0"] as Node3D).rotation.x = 0.25
	(_rig["hip_1"] as Node3D).rotation.x = float(p[4])
	(_rig["knee_1"] as Node3D).rotation.x = float(p[5])
	(_rig["hip_0"] as Node3D).rotation.x = -float(p[4])
	# 3/4 front-left, framed on the shoulder and upper arm
	_cam.global_position = Vector3(-1.05, 1.62, -1.05)
	_cam.look_at(Vector3(0.02, 1.32, 0.0), Vector3.UP)
	await _save("pose_%s_%s" % [job[0], str(p[0])])
	_busy = false

func _save(tag: String) -> void:
	for i in 4: await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(OUT + "/" + tag + ".png")
	print("SHOT " + tag)
